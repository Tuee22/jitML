{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Finite native task-reference observations only. This module has no learned
-- policy, training, criterion, checkpoint, qualification or producer authority.
module JitML.RL.NativeReturnReferences
  ( NativeReturnReferenceSpec
  , NativeReturnDomain (..)
  , NativeReturnController (..)
  , NativeContinuousControl (..)
  , NativeReturnEpisode (..)
  , NativeReturnReferenceObservation (..)
  , NativeReturnReferenceSet (..)
  , nativeReturnReferenceContract
  , mkCanonicalNativeReturnSpec
  , canonicalNativeReturnSpec
  , allCanonicalNativeReturnSpecs
  , nativeReturnSpecRowId
  , nativeReturnSpecAlgorithm
  , nativeReturnSpecEnvironment
  , nativeReturnSpecTrainer
  , nativeReturnSpecBudget
  , nativeReturnSpecSchedule
  , nativeReturnSpecEpisodeCount
  , nativeReturnSpecHorizon
  , nativeReturnSpecObservationSize
  , nativeReturnSpecDomain
  , nativeReturnControllerId
  , discreteReferenceControllers
  , continuousReferenceControllers
  , selectDiscreteReferenceAction
  , evaluateDiscreteReference
  , evaluateContinuousReference
  , evaluateCanonicalNativeReturnReferences
  ) where

import Control.Monad (unless)
import Data.List (find, permutations, sort)
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as Text
import GHC.Float (castDoubleToWord64)

import JitML.RL.Algorithms.Registry qualified as Registry
import JitML.RL.ConvergenceThresholds qualified as Thresholds
import JitML.RL.ProductBudget qualified as Budget
import JitML.RL.Simulator qualified as Sim
import JitML.Training.Budget
  ( BudgetKind (..)
  , TrainingBudget
  , trainingBudgetKind
  , trainingBudgetTargetUnits
  )

nativeReturnReferenceContract :: Text
nativeReturnReferenceContract = "native-return-fixed-action-references-v1"

data NativeReturnDomain
  = NativeUnmaskedDiscrete !Int
  | NativeMaskedDiscrete !Int
  | NativeContinuous !Double !Double
  deriving stock (Eq, Show)

data NativeContinuousControl = NativeZero | NativeLowerEndpoint | NativeUpperEndpoint
  deriving stock (Eq, Show)

-- Public raw controller descriptions are revalidated against the actual
-- environment before execution. They are not evidence of a canonical row.
data NativeReturnController
  = ConstantDiscrete !Int
  | FixedMaskedPreference ![Int]
  | ConstantContinuous !NativeContinuousControl !Double
  deriving stock (Eq, Show)

-- Private constructor and ordinary observers prevent external record updates.
-- The canonical convergence row is retained for exact identity/budget binding;
-- its quality measurements are never evaluated or used to tune a reference.
data NativeReturnReferenceSpec
  = NativeReturnReferenceSpec
      !Thresholds.FixedBudgetRlConvergenceRow
      !Budget.RlTrainingSchedule
      !Text
      !Int
      !Int
      !Int
      !NativeReturnDomain
  deriving stock (Eq, Show)

data NativeReturnEpisode = NativeReturnEpisode
  { nativeReturnEpisodeId :: !Int
  , nativeReturnEpisodeReward :: !Double
  , nativeReturnEpisodeSteps :: !Int
  , nativeReturnEpisodeTerminated :: !Bool
  }
  deriving stock (Eq, Show)

data NativeReturnReferenceObservation = NativeReturnReferenceObservation
  { nativeReturnObservedController :: !NativeReturnController
  , nativeReturnObservedEpisodes :: ![NativeReturnEpisode]
  , nativeReturnObservedEvaluationTransitions :: !Integer
  }
  deriving stock (Eq, Show)

data NativeReturnReferenceSet = NativeReturnReferenceSet
  { nativeReturnObservedSpec :: !NativeReturnReferenceSpec
  , nativeReturnObservedReferences :: ![NativeReturnReferenceObservation]
  , nativeReturnTotalEvaluationTransitions :: !Integer
  }
  deriving stock (Eq, Show)

canonicalNativeReturnSpec :: Text -> Text -> Either Text NativeReturnReferenceSpec
canonicalNativeReturnSpec algorithm environment =
  case find
    (\row -> Thresholds.fbrAlgorithm row == algorithm && Thresholds.fbrEnvironment row == environment)
    Thresholds.fixedBudgetRlConvergenceRows of
    Nothing -> Left "native return reference row is not canonical"
    Just row -> mkCanonicalNativeReturnSpec row

allCanonicalNativeReturnSpecs :: Either Text [NativeReturnReferenceSpec]
allCanonicalNativeReturnSpecs = traverse mkCanonicalNativeReturnSpec Thresholds.fixedBudgetRlConvergenceRows

mkCanonicalNativeReturnSpec
  :: Thresholds.FixedBudgetRlConvergenceRow -> Either Text NativeReturnReferenceSpec
mkCanonicalNativeReturnSpec row = do
  let algorithm = Thresholds.fbrAlgorithm row
      environment = Thresholds.fbrEnvironment row
      canonical =
        filter
          ( \candidate ->
              Thresholds.fbrAlgorithm candidate == algorithm && Thresholds.fbrEnvironment candidate == environment
          )
          Thresholds.fixedBudgetRlConvergenceRows
  require
    (canonical == [row])
    "native return reference row differs from the exact canonical declaration"
  cohort <- Registry.mkCohort algorithm environment
  schedule <- Budget.canonicalProductRlSchedule algorithm environment
  horizon <- scheduleHorizon schedule
  require
    (horizon > 0 && Budget.productRlDefaultEvaluationEpisodes > 0)
    "native return reference schedule has invalid evaluation dimensions"
  require
    ( trainingBudgetKind (Thresholds.fbrBudget row) == RlEnvironmentStepBudget
        && trainingBudgetTargetUnits (Thresholds.fbrBudget row)
          == Budget.scheduleObservedEnvironmentSteps schedule
    )
    "native return reference row budget differs from the canonical schedule"
  (observationSize, domain) <- case Registry.cohortActionDomain cohort of
    Registry.DiscreteDomain -> do
      wrapped <-
        maybe
          (Left "canonical discrete return simulator is absent")
          Right
          (Sim.lookupSimulatedEnvironmentByName environment)
      case wrapped of
        Sim.SomeSimulatedEnvironment env -> do
          validateDiscreteMetadata env
          require (Sim.envName env == environment) "canonical discrete return simulator identity differs"
          require
            (horizon >= Sim.envMaxEpisodeSteps env)
            "canonical discrete return horizon is shorter than its simulator"
          pure
            ( Sim.envObservationSize env
            , if isJust (Sim.envActionMask env)
                then NativeMaskedDiscrete (Sim.envActionCount env)
                else NativeUnmaskedDiscrete (Sim.envActionCount env)
            )
    Registry.ContinuousDomain -> do
      wrapped <-
        maybe
          (Left "canonical continuous return simulator is absent")
          Right
          (Sim.lookupContinuousEnvironmentByName environment)
      case wrapped of
        Sim.SomeContinuousEnvironment env -> do
          validateContinuousMetadata env
          require (Sim.cEnvName env == environment) "canonical continuous return simulator identity differs"
          require
            (horizon >= Sim.cEnvMaxEpisodeSteps env)
            "canonical continuous return horizon is shorter than its simulator"
          pure
            (Sim.cEnvObservationSize env, NativeContinuous (Sim.cEnvActionLow env) (Sim.cEnvActionHigh env))
    Registry.GoalConditionedDomain -> Left "goal-conditioned references are outside the native return family"
  pure
    ( NativeReturnReferenceSpec
        row
        schedule
        (Registry.cohortTrainerKind cohort)
        Budget.productRlDefaultEvaluationEpisodes
        horizon
        observationSize
        domain
    )

nativeReturnSpecRowId :: NativeReturnReferenceSpec -> Text
nativeReturnSpecRowId spec = nativeReturnSpecAlgorithm spec <> "/" <> nativeReturnSpecEnvironment spec
nativeReturnSpecAlgorithm :: NativeReturnReferenceSpec -> Text
nativeReturnSpecAlgorithm (NativeReturnReferenceSpec row _ _ _ _ _ _) = Thresholds.fbrAlgorithm row
nativeReturnSpecEnvironment :: NativeReturnReferenceSpec -> Text
nativeReturnSpecEnvironment (NativeReturnReferenceSpec row _ _ _ _ _ _) = Thresholds.fbrEnvironment row
nativeReturnSpecTrainer :: NativeReturnReferenceSpec -> Text
nativeReturnSpecTrainer (NativeReturnReferenceSpec _ _ trainer _ _ _ _) = trainer
nativeReturnSpecBudget :: NativeReturnReferenceSpec -> TrainingBudget
nativeReturnSpecBudget (NativeReturnReferenceSpec row _ _ _ _ _ _) = Thresholds.fbrBudget row
nativeReturnSpecSchedule :: NativeReturnReferenceSpec -> Budget.RlTrainingSchedule
nativeReturnSpecSchedule (NativeReturnReferenceSpec _ schedule _ _ _ _ _) = schedule
nativeReturnSpecEpisodeCount :: NativeReturnReferenceSpec -> Int
nativeReturnSpecEpisodeCount (NativeReturnReferenceSpec _ _ _ count _ _ _) = count
nativeReturnSpecHorizon :: NativeReturnReferenceSpec -> Int
nativeReturnSpecHorizon (NativeReturnReferenceSpec _ _ _ _ horizon _ _) = horizon
nativeReturnSpecObservationSize :: NativeReturnReferenceSpec -> Int
nativeReturnSpecObservationSize (NativeReturnReferenceSpec _ _ _ _ _ width _) = width
nativeReturnSpecDomain :: NativeReturnReferenceSpec -> NativeReturnDomain
nativeReturnSpecDomain (NativeReturnReferenceSpec _ _ _ _ _ _ domain) = domain

scheduleHorizon :: Budget.RlTrainingSchedule -> Either Text Int
scheduleHorizon schedule = case schedule of
  Budget.OnPolicyTrainingSchedule {} -> Right (Budget.scheduleOnPolicyMaxEpisodeSteps schedule)
  Budget.FixedStepTrainingSchedule {} -> Right (Budget.scheduleFixedMaxEpisodeSteps schedule)
  Budget.ArsTrainingSchedule {} -> Right (Budget.scheduleArsMaxEpisodeSteps schedule)
  Budget.HerTrainingSchedule {} -> Left "HER schedules are outside native return references"

nativeReturnControllerId :: NativeReturnController -> Text
nativeReturnControllerId controller = case controller of
  ConstantDiscrete action -> "constant-discrete/" <> showText action
  FixedMaskedPreference preference -> "fixed-masked-preference/" <> Text.intercalate "," (fmap showText preference)
  ConstantContinuous NativeZero _ -> "native-zero"
  ConstantContinuous NativeLowerEndpoint _ -> "native-lower-endpoint"
  ConstantContinuous NativeUpperEndpoint _ -> "native-upper-endpoint"

discreteReferenceControllers
  :: Sim.SimulatedEnvironment state -> Either Text [NativeReturnController]
discreteReferenceControllers env = do
  validateDiscreteMetadata env
  let domain = [0 .. Sim.envActionCount env - 1]
  pure $ case Sim.envActionMask env of
    Nothing -> fmap ConstantDiscrete domain
    Just _ -> fmap FixedMaskedPreference (sort (permutations domain))

continuousReferenceControllers
  :: Sim.ContinuousEnvironment state -> Either Text [NativeReturnController]
continuousReferenceControllers env = do
  validateContinuousMetadata env
  pure
    [ ConstantContinuous NativeZero 0
    , ConstantContinuous NativeLowerEndpoint (Sim.cEnvActionLow env)
    , ConstantContinuous NativeUpperEndpoint (Sim.cEnvActionHigh env)
    ]

-- The complete preference is validated even if an early legal action exists;
-- a malformed suffix cannot be hidden by leftmost selection.
selectDiscreteReferenceAction
  :: Sim.SimulatedEnvironment state -> NativeReturnController -> state -> Either Text Int
selectDiscreteReferenceAction env controller state = do
  validateDiscreteMetadata env
  case (Sim.envActionMask env, controller) of
    (Nothing, ConstantDiscrete action) -> do
      require
        (action >= 0 && action < Sim.envActionCount env)
        "discrete reference constant is outside the actual action domain"
      pure action
    (Just maskFor, FixedMaskedPreference preference) -> do
      require
        (sort preference == [0 .. Sim.envActionCount env - 1])
        "masked reference preference is not a complete action-domain permutation"
      let mask = maskFor state
      require
        (length mask == Sim.envActionCount env)
        "native return action mask width differs from the action domain"
      require (or mask) "native return action mask has no legal action"
      maybe
        (Left "native return complete preference has no legal action")
        Right
        (find (mask !!) preference)
    _ -> Left "native return controller does not match the simulator action domain"

evaluateDiscreteReference
  :: Sim.SimulatedEnvironment state
  -> Int
  -> Int
  -> NativeReturnController
  -> Either Text NativeReturnReferenceObservation
evaluateDiscreteReference env count horizon controller = do
  validateDiscreteMetadata env
  validateEvaluationDimensions count horizon
  episodes <- traverse (episode controller) [0 .. count - 1]
  pure (observation controller episodes)
 where
  episode selected index = loop (Sim.envInitial env) 0 0
   where
    loop !state !steps !reward
      | steps >= horizon = Right (NativeReturnEpisode index reward steps False)
      | otherwise = do
          validateObservation
            (Sim.envObservationSize env)
            (Sim.renderObservation (Sim.envRenderFrame env state))
          action <- selectDiscreteReferenceAction env selected state
          let result = Sim.envStep env state action
              reward' = reward + Sim.simStepReward result
              steps' = steps + 1
          require
            (finite (Sim.simStepReward result) && finite reward')
            "native return reward or accumulated return is nonfinite"
          validateObservation
            (Sim.envObservationSize env)
            (Sim.renderObservation (Sim.envRenderFrame env (Sim.simStepState result)))
          if Sim.simStepDone result
            then Right (NativeReturnEpisode index reward' steps' True)
            else loop (Sim.simStepState result) steps' reward'

evaluateContinuousReference
  :: Sim.ContinuousEnvironment state
  -> Int
  -> Int
  -> NativeReturnController
  -> Either Text NativeReturnReferenceObservation
evaluateContinuousReference env count horizon controller = do
  validateContinuousMetadata env
  validateEvaluationDimensions count horizon
  action <- case controller of
    ConstantContinuous kind value -> do
      let expected = case kind of
            NativeZero -> 0
            NativeLowerEndpoint -> Sim.cEnvActionLow env
            NativeUpperEndpoint -> Sim.cEnvActionHigh env
      require
        ( finite value
            && castDoubleToWord64 value == castDoubleToWord64 expected
            && value >= Sim.cEnvActionLow env
            && value <= Sim.cEnvActionHigh env
        )
        "continuous reference is not its declared native zero or endpoint"
      pure value
    _ -> Left "native return controller does not match the simulator action domain"
  episodes <- traverse (episode action) [0 .. count - 1]
  pure (observation controller episodes)
 where
  episode action index = loop (Sim.cEnvInitial env) 0 0
   where
    loop !state !steps !reward
      | steps >= horizon = Right (NativeReturnEpisode index reward steps False)
      | otherwise = do
          validateObservation (Sim.cEnvObservationSize env) (Sim.cEnvObservation env state)
          let result = Sim.cEnvStep env state action
              reward' = reward + Sim.cStepReward result
              steps' = steps + 1
          require
            (finite (Sim.cStepReward result) && finite reward')
            "native return reward or accumulated return is nonfinite"
          validateObservation (Sim.cEnvObservationSize env) (Sim.cEnvObservation env (Sim.cStepState result))
          if Sim.cStepDone result
            then Right (NativeReturnEpisode index reward' steps' True)
            else loop (Sim.cStepState result) steps' reward'

evaluateCanonicalNativeReturnReferences
  :: NativeReturnReferenceSpec -> Either Text NativeReturnReferenceSet
evaluateCanonicalNativeReturnReferences spec = do
  expected <-
    canonicalNativeReturnSpec (nativeReturnSpecAlgorithm spec) (nativeReturnSpecEnvironment spec)
  require
    (spec == expected)
    "native return reference specification is not the current canonical descriptor"
  let environment = nativeReturnSpecEnvironment spec
      count = nativeReturnSpecEpisodeCount spec
      horizon = nativeReturnSpecHorizon spec
  references <- case nativeReturnSpecDomain spec of
    NativeContinuous {} -> do
      wrapped <-
        maybe
          (Left "canonical continuous return simulator is absent")
          Right
          (Sim.lookupContinuousEnvironmentByName environment)
      case wrapped of
        Sim.SomeContinuousEnvironment env -> continuousReferenceControllers env >>= traverse (evaluateContinuousReference env count horizon)
    _ -> do
      wrapped <-
        maybe
          (Left "canonical discrete return simulator is absent")
          Right
          (Sim.lookupSimulatedEnvironmentByName environment)
      case wrapped of
        Sim.SomeSimulatedEnvironment env -> discreteReferenceControllers env >>= traverse (evaluateDiscreteReference env count horizon)
  pure
    ( NativeReturnReferenceSet
        spec
        references
        (sum (fmap nativeReturnObservedEvaluationTransitions references))
    )

observation :: NativeReturnController -> [NativeReturnEpisode] -> NativeReturnReferenceObservation
observation controller episodes =
  NativeReturnReferenceObservation
    controller
    episodes
    (sum (fmap (toInteger . nativeReturnEpisodeSteps) episodes))

validateDiscreteMetadata :: Sim.SimulatedEnvironment state -> Either Text ()
validateDiscreteMetadata env =
  require
    (Sim.envActionCount env > 0 && Sim.envObservationSize env > 0 && Sim.envMaxEpisodeSteps env > 0)
    "native discrete simulator metadata is invalid"

validateContinuousMetadata :: Sim.ContinuousEnvironment state -> Either Text ()
validateContinuousMetadata env = do
  require
    ( Sim.cEnvObservationSize env > 0
        && Sim.cEnvMaxEpisodeSteps env > 0
        && all finite [Sim.cEnvActionLow env, Sim.cEnvActionHigh env]
        && Sim.cEnvActionLow env < Sim.cEnvActionHigh env
    )
    "native continuous simulator metadata or bounds are invalid"
  require
    (Sim.cEnvActionLow env <= 0 && Sim.cEnvActionHigh env >= 0)
    "native zero reference is outside the actual action bounds"

validateEvaluationDimensions :: Int -> Int -> Either Text ()
validateEvaluationDimensions count horizon =
  require
    (count > 0 && horizon > 0)
    "native return evaluation count and horizon must be positive"

validateObservation :: Int -> [Double] -> Either Text ()
validateObservation width values =
  require
    (length values == width && all finite values)
    "native return simulator observation shape or finite values differ"

require :: Bool -> Text -> Either Text ()
require condition reason = unless condition (Left reason)
finite :: Double -> Bool
finite value = not (isNaN value || isInfinite value)
showText :: (Show value) => value -> Text
showText = Text.pack . show
