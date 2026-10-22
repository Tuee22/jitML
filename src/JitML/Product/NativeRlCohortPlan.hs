{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Canonical native five-child plan DATA. No value establishes training,
-- actual prepared optimizer configuration, origin, durable attempts, device
-- execution, learning, checkpoint admission or qualification.
module JitML.Product.NativeRlCohortPlan
  ( NativeRlCohortPlan
  , NativeRlSeedPlan
  , NativeSeedIndex
  , NativeRlCohortBatch
  , NativeSeedHeadroom
  , nativeRlCohortDataContract
  , nativeSeedIndices
  , nativeSeedIndexValue
  , mkNativeRlCohortPlan
  , mkCanonicalNativeRlCohorts
  , refineNativeRlCohortBatch
  , nativeRlCohortPlanProjection
  , nativeRlCohortPlanRow
  , nativeRlCohortPlanChildren
  , nativeRlCohortServingChild
  , nativeRlCohortPlanTransport
  , nativeRlCohortPlanId
  , nativeRlSeedPlanIndex
  , nativeRlSeedPlanSeed
  , nativeRlSeedPlanSingleton
  , nativeRlSeedPlanCompiledReturn
  , nativeRlSeedPlanAlphaZero
  , nativeRlSeedPlanTrainingBudget
  , nativeRlSeedPlanHeadroom
  , nativeRlCohortBatchPlans
  , nativeRlCohortBatchSubstrate
  , nativeRlSeedAssociation
  , checkedNativeSeedHeadroom
  , nativeSeedHeadroomBase
  , nativeSeedHeadroomOffsets
  , nativeSeedHeadroomMaximum
  ) where

import Control.Monad (unless)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.List (find)
import Data.List.NonEmpty qualified as NE
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Encoding
import Data.Word (Word64)
import GHC.Float (castDoubleToWord64)
import Numeric (showHex)

import JitML.Plan.NativeChildAssociation qualified as Association
import JitML.Plan.NativeSingletonPlan qualified as Native
import JitML.Plan.Plan qualified as Plan
import JitML.Plan.Workload qualified as Workload
import JitML.Product.Convergence qualified as Convergence
import JitML.Product.Matrix qualified as Matrix
import JitML.RL.AlphaZero qualified as Game
import JitML.RL.ProductBudget qualified as ProductBudget
import JitML.SL.Architecture qualified as Architecture
import JitML.Substrate (Substrate, renderSubstrate)
import JitML.Training.Budget qualified as Budget

nativeRlCohortDataContract :: Text
nativeRlCohortDataContract = "jitml-native-rl-cohort-plan-data-v1"

newtype NativeSeedIndex = NativeSeedIndex Int deriving stock (Eq, Ord, Show)

nativeSeedIndices :: [NativeSeedIndex]
nativeSeedIndices = fmap NativeSeedIndex [0 .. 4]

nativeSeedIndexValue :: NativeSeedIndex -> Int
nativeSeedIndexValue (NativeSeedIndex index) = index

-- CompiledRlPlan is the public checked schedule/input record, NOT the full
-- optimizer configuration assembled privately by TrainerExecution.
data NativeRecipe
  = NativeReturnRecipe !ProductBudget.CompiledRlPlan
  | NativeArenaRecipe !Workload.AlphaZeroPlan
  deriving stock (Eq, Show)

data NativeSeedHeadroom = NativeSeedHeadroom !Word64 ![(Text, Integer, Integer)] !Integer
  deriving stock (Eq, Show)

data NativeRlSeedPlan
  = NativeRlSeedPlan
      !NativeSeedIndex
      !Native.NativeSingletonPlan
      !Budget.TrainingBudget
      !NativeRecipe
      !NativeSeedHeadroom
  deriving stock (Eq, Show)

data NativeRlCohortPlan
  = NativeRlCohortPlan
      !(Matrix.ProductRow 'Matrix.Declared)
      !Matrix.SomeProductProjection
      !NativeRlSeedPlan
      ![NativeRlSeedPlan]
      !ByteString
      !Plan.PlanId
  deriving stock (Eq, Show)

data NativeRlCohortBatch = NativeRlCohortBatch !Substrate ![NativeRlCohortPlan]
  deriving stock (Eq, Show)

nativeRlCohortPlanProjection :: NativeRlCohortPlan -> Matrix.SomeProductProjection
nativeRlCohortPlanProjection (NativeRlCohortPlan _ projection _ _ _ _) = projection

nativeRlCohortPlanRow :: NativeRlCohortPlan -> Matrix.ProductRow 'Matrix.Declared
nativeRlCohortPlanRow (NativeRlCohortPlan row _ _ _ _ _) = row

nativeRlCohortPlanChildren :: NativeRlCohortPlan -> [NativeRlSeedPlan]
nativeRlCohortPlanChildren (NativeRlCohortPlan _ _ first rest _ _) = first : rest

nativeRlCohortServingChild :: NativeRlCohortPlan -> NativeRlSeedPlan
nativeRlCohortServingChild (NativeRlCohortPlan _ _ first _ _ _) = first

nativeRlCohortPlanTransport :: NativeRlCohortPlan -> ByteString
nativeRlCohortPlanTransport (NativeRlCohortPlan _ _ _ _ bytes _) = bytes

nativeRlCohortPlanId :: NativeRlCohortPlan -> Plan.PlanId
nativeRlCohortPlanId (NativeRlCohortPlan _ _ _ _ _ identity) = identity

nativeRlSeedPlanIndex :: NativeRlSeedPlan -> NativeSeedIndex
nativeRlSeedPlanIndex (NativeRlSeedPlan index _ _ _ _) = index

nativeRlSeedPlanSeed :: NativeRlSeedPlan -> Word64
nativeRlSeedPlanSeed = Native.nativeSingletonSeed . nativeRlSeedPlanSingleton

nativeRlSeedPlanSingleton :: NativeRlSeedPlan -> Native.NativeSingletonPlan
nativeRlSeedPlanSingleton (NativeRlSeedPlan _ plan _ _ _) = plan

nativeRlSeedPlanCompiledReturn :: NativeRlSeedPlan -> Maybe ProductBudget.CompiledRlPlan
nativeRlSeedPlanCompiledReturn (NativeRlSeedPlan _ _ _ (NativeReturnRecipe recipe) _) = Just recipe
nativeRlSeedPlanCompiledReturn (NativeRlSeedPlan _ _ _ (NativeArenaRecipe _) _) = Nothing

nativeRlSeedPlanAlphaZero :: NativeRlSeedPlan -> Maybe Workload.AlphaZeroPlan
nativeRlSeedPlanAlphaZero (NativeRlSeedPlan _ _ _ (NativeReturnRecipe _) _) = Nothing
nativeRlSeedPlanAlphaZero (NativeRlSeedPlan _ _ _ (NativeArenaRecipe recipe) _) = Just recipe

nativeRlSeedPlanTrainingBudget :: NativeRlSeedPlan -> Budget.TrainingBudget
nativeRlSeedPlanTrainingBudget (NativeRlSeedPlan _ _ budget _ _) = budget

nativeRlSeedPlanHeadroom :: NativeRlSeedPlan -> NativeSeedHeadroom
nativeRlSeedPlanHeadroom (NativeRlSeedPlan _ _ _ _ headroom) = headroom

nativeRlCohortBatchPlans :: NativeRlCohortBatch -> [NativeRlCohortPlan]
nativeRlCohortBatchPlans (NativeRlCohortBatch _ plans) = plans

nativeRlCohortBatchSubstrate :: NativeRlCohortBatch -> Substrate
nativeRlCohortBatchSubstrate (NativeRlCohortBatch lane _) = lane

nativeSeedHeadroomBase :: NativeSeedHeadroom -> Word64
nativeSeedHeadroomBase (NativeSeedHeadroom base _ _) = base

nativeSeedHeadroomOffsets :: NativeSeedHeadroom -> [(Text, Integer, Integer)]
nativeSeedHeadroomOffsets (NativeSeedHeadroom _ offsets _) = offsets

nativeSeedHeadroomMaximum :: NativeSeedHeadroom -> Integer
nativeSeedHeadroomMaximum (NativeSeedHeadroom _ _ largest) = largest

-- | Arithmetic data only: this public helper proves neither family offsets
-- nor canonical membership. The cohort constructor supplies its own offsets.
checkedNativeSeedHeadroom :: Word64 -> [(Text, Integer)] -> Either Text NativeSeedHeadroom
checkedNativeSeedHeadroom base offsets = do
  require
    (not (null offsets) && length offsets <= 32)
    "native seed headroom requires 1..32 addressed offsets"
  require (not (any (Text.null . fst) offsets)) "native seed headroom offset label is empty"
  unique "native seed headroom offset labels" (fmap fst offsets)
  let checked = [(label, offset, toInteger base + offset) | (label, offset) <- offsets]
      bound = min (toInteger (maxBound :: Int)) (toInteger (maxBound :: Word64))
  require (toInteger base <= bound) "native seed base exceeds Word64 or actual Int range"
  mapM_
    ( \(label, offset, actual) -> do
        require (offset >= 0) ("native seed offset is negative: " <> label)
        require
          (offset <= bound && actual <= bound)
          ("native seed arithmetic exceeds Word64 or actual Int range: " <> label)
    )
    checked
  pure (NativeSeedHeadroom base checked (foldr (max . third) (toInteger base) checked))
 where
  third (_, _, value) = value

-- | One canonical row/lane and its five prescribed child plans only. This
-- value carries no global namespace-injectivity or reservation authority.
-- A future coordinator must require the separately checked whole-lane batch.
mkNativeRlCohortPlan :: Matrix.SomeProductProjection -> Either Text NativeRlCohortPlan
mkNativeRlCohortPlan supplied@(Matrix.SomeProductProjection witness projection) = do
  let rowId = Matrix.productProjectionRowId projection
      lane = Matrix.productProjectionSubstrate projection
  row <- case filter ((== rowId) . Matrix.rowId) Matrix.allProductRows of
    [value] -> Right value
    _ -> Left "native cohort requires exactly one current canonical ProductRow"
  require (nativeRow row) "native cohort rejects non-native ProductRows"
  canonical <- case Matrix.projectProductRow lane row of
    Plan.Success value -> Right value
    Plan.Failure _ -> Left "native cohort canonical ProductRow did not project"
  require (supplied == canonical) "native cohort full canonical projection differs"
  -- Eq Double treats signed zero alike. Exact serialized metadata must agree.
  actualFields <- projectionFields supplied
  canonicalFields <- projectionFields canonical
  require
    (actualFields == canonicalFields)
    "native cohort exact canonical projection metadata bits differ"
  parent <- case (witness, Matrix.productProjectionResolvedPlan projection) of
    (Plan.ReinforcementLearningWitness, Matrix.ResolvedRlProductPlan plan) -> Native.nativeRlSingletonPlan plan
    (Plan.AlphaZeroSelfPlayWitness, Matrix.ResolvedAlphaZeroProductPlan plan) -> Native.nativeAlphaZeroSingletonPlan plan
    _ -> Left "native cohort supports only native RL/HER and full AlphaZero workloads"
  children <- traverse (makeChild projection parent) nativeSeedIndices
  case children of
    first : rest | length rest == 4 -> do
      require
        (nativeRlSeedPlanSingleton first == parent)
        "native serving index zero differs from complete canonical parent"
      require
        (nativeRlSeedPlanTrainingBudget first == Matrix.productProjectionTrainingBudget projection)
        "native serving index zero budget differs from canonical parent"
      rowMetadata <- rowFields row
      childMetadata <- fmap concat (traverse childFields children)
      bytes <-
        renderFields
          ( [ scalar "data-contract" nativeRlCohortDataContract
            , scalar "child-namespace-contract" Native.nativeChildNamespaceContract
            ]
              <> rowMetadata
              <> actualFields
              <> [number "child-count" (5 :: Int)]
              <> childMetadata
          )
      identity <- case Plan.planIdFromCanonicalText (Encoding.decodeUtf8 bytes) of
        Plan.Success value -> Right value
        Plan.Failure _ -> Left "native cohort data identity did not refine"
      pure (NativeRlCohortPlan row supplied first rest bytes identity)
    _ -> Left "native cohort must have exactly five ordered child plans"

makeChild
  :: Matrix.ProductProjection kind
  -> Native.NativeSingletonPlan
  -> NativeSeedIndex
  -> Either Text NativeRlSeedPlan
makeChild projection parent index = do
  child <- Native.deriveNativeChildPlan parent (nativeSeedIndexValue index)
  let declared = Matrix.productProjectionTrainingBudget projection
      seed = Native.nativeSingletonSeed child
  budget <-
    Budget.mkTrainingBudget
      (Budget.trainingBudgetKind declared)
      (Budget.trainingBudgetTargetUnits declared)
      (Just seed)
  recipe <- case ( Matrix.productProjectionDescriptor projection
                 , Native.nativeSingletonRlPlan child
                 , Native.nativeSingletonAlphaZeroPlan child
                 ) of
    (descriptor@Matrix.RlProductDescriptor {}, Just plan, Nothing) ->
      NativeReturnRecipe <$> compileChildReturn descriptor plan budget
    (descriptor@Matrix.AlphaZeroProductDescriptor {}, Nothing, Just plan) -> do
      validateArenaRecipe descriptor plan budget
      pure (NativeArenaRecipe plan)
    _ -> Left "native child recipe kind differs from complete workload"
  headroom <- recipeHeadroom seed recipe
  pure (NativeRlSeedPlan index child budget recipe headroom)

compileChildReturn
  :: Matrix.ProductPlanDescriptor 'Plan.ReinforcementLearning
  -> Plan.RunPlan 'Plan.ReinforcementLearning
  -> Budget.TrainingBudget
  -> Either Text ProductBudget.CompiledRlPlan
compileChildReturn descriptor plan budget = do
  let (targetQ, ticksQ, vectorsQ, stepsQ, evalQ) = Plan.runPlanRlBudget plan
      target = Plan.quantityValue targetQ
      ticks = Plan.quantityValue ticksQ
      vectors = Plan.quantityValue vectorsQ
      steps = Plan.quantityValue stepsQ
      evaluations = Plan.quantityValue evalQ
      seedWord = NE.head (Plan.seedCohortValues (Plan.runPlanSeeds plan))
      trainer = ProductBudget.trainerKindForAlgorithm (Matrix.rlDescriptorAlgorithm descriptor)
      environment = Matrix.rlDescriptorEnvironment descriptor
  require
    ( ticks == Matrix.rlDescriptorRolloutTicksPerEnv descriptor
        && vectors == Matrix.rlDescriptorVectorEnvironments descriptor
        && steps == Matrix.rlDescriptorEpisodeSteps descriptor
        && evaluations == Matrix.rlDescriptorEvaluationEpisodes descriptor
    )
    "native child return descriptor quantities differ from complete plan"
  require
    ( Budget.trainingBudgetKind budget == Budget.RlEnvironmentStepBudget
        && Budget.trainingBudgetTargetUnits budget == target
        && Budget.trainingBudgetSeed budget == Just seedWord
    )
    "native child return budget differs from complete plan"
  seed <- intValue "native child return seed" seedWord
  vectorCount <- intValue "native child vector count" vectors
  episodeSteps <- intValue "native child episode steps" steps
  evaluationCount <- intValue "native child evaluation count" evaluations
  recipe <-
    ProductBudget.compileRlPlan
      ProductBudget.TrainingPlan
        { ProductBudget.trainingPlanTrainerKind = trainer
        , ProductBudget.trainingPlanEnvironment = environment
        , ProductBudget.trainingPlanSeed = seed
        , ProductBudget.trainingPlanMaxEpisodeSteps = episodeSteps
        , ProductBudget.trainingPlanEpisodeBudgetFloor = ProductBudget.productRlDefaultTrainingEpisodeFloor
        , ProductBudget.trainingPlanVectorEnvironments = Just vectorCount
        , ProductBudget.trainingPlanRequestedTransitionFloor = Just target
        , ProductBudget.trainingPlanExactTransitionTarget = Just target
        }
      (ProductBudget.EvaluationPlan evaluationCount)
  case ProductBudget.rlTrainerEnvironmentCompatibilityError trainer environment of
    Nothing -> pure ()
    Just err -> Left ("native child trainer/environment differs: " <> err)
  schedule <-
    maybe
      (Left "native child requires a concrete native schedule")
      Right
      (ProductBudget.compiledRlSchedule recipe)
  require
    (ProductBudget.scheduleObservedEnvironmentSteps schedule == target)
    "native child compiled schedule target differs"
  validateSchedule ticks vectors steps schedule
  roundtrip <-
    ProductBudget.parseCompiledRlPlanTransport (ProductBudget.renderCompiledRlPlanTransport recipe)
  require (roundtrip == recipe) "native child compiled recipe transport differs"
  pure recipe

validateSchedule :: Word64 -> Word64 -> Word64 -> ProductBudget.RlTrainingSchedule -> Either Text ()
validateSchedule ticks vectors steps schedule = require matches "native child compiled schedule descriptor differs"
 where
  same integer word = toInteger integer == toInteger word
  matches = case schedule of
    ProductBudget.OnPolicyTrainingSchedule {} ->
      same (ProductBudget.scheduleOnPolicyRolloutSteps schedule) ticks
        && same (ProductBudget.scheduleOnPolicyVectorEnvironments schedule) vectors
        && same (ProductBudget.scheduleOnPolicyMaxEpisodeSteps schedule) steps
    ProductBudget.FixedStepTrainingSchedule {} ->
      ticks == 1
        && vectors == 1
        && same (ProductBudget.scheduleFixedMaxEpisodeSteps schedule) steps
    ProductBudget.ArsTrainingSchedule {} ->
      vectors == 1
        && same (ProductBudget.scheduleArsMaxEpisodeSteps schedule) ticks
        && same (ProductBudget.scheduleArsMaxEpisodeSteps schedule) steps
    ProductBudget.HerTrainingSchedule {} ->
      vectors == 1
        && same (ProductBudget.scheduleHerEnvironmentStepsPerEpisode schedule) ticks
        && same (ProductBudget.scheduleHerEnvironmentStepsPerEpisode schedule) steps

validateArenaRecipe
  :: Matrix.ProductPlanDescriptor 'Plan.AlphaZeroSelfPlay
  -> Workload.AlphaZeroPlan
  -> Budget.TrainingBudget
  -> Either Text ()
validateArenaRecipe descriptor plan budget = do
  let q = Plan.quantityValue
      game = Workload.renderAlphaZeroGame (Workload.alphaZeroPlanGame plan)
      values =
        [ q (Workload.alphaZeroPlanGenerations plan)
        , q (Workload.alphaZeroPlanSelfPlayGames plan)
        , q (Workload.alphaZeroPlanMctsSimulations plan)
        , q (Workload.alphaZeroPlanMaxPlies plan)
        , q (Workload.alphaZeroPlanUpdates plan)
        , q (Workload.alphaZeroPlanArenaGames plan)
        ]
      seed = NE.head (Plan.seedCohortValues (Plan.runPlanSeeds (Workload.alphaZeroPlanRunPlan plan)))
  require
    ( game == Matrix.alphaZeroDescriptorGame descriptor
        && q (Workload.alphaZeroPlanSelfPlayGames plan) == Matrix.alphaZeroDescriptorSelfPlayGames descriptor
        && q (Workload.alphaZeroPlanMctsSimulations plan)
          == Matrix.alphaZeroDescriptorMctsSimulations descriptor
        && q (Workload.alphaZeroPlanMaxPlies plan) == Matrix.alphaZeroDescriptorMaxPlies descriptor
        && q (Workload.alphaZeroPlanUpdates plan) == Matrix.alphaZeroDescriptorOptimizerUpdates descriptor
        && q (Workload.alphaZeroPlanArenaGames plan) == Matrix.alphaZeroDescriptorArenaGames descriptor
    )
    "native child full AlphaZero game/descriptor differs"
  require
    ( Budget.trainingBudgetKind budget == Budget.AlphaZeroSelfPlayBudget
        && Budget.trainingBudgetTargetUnits budget == q (Workload.alphaZeroPlanGenerations plan)
        && Budget.trainingBudgetSeed budget == Just seed
    )
    "native child AlphaZero budget differs from complete workload"
  mapM_ (intValue "native child AlphaZero quantity") values
  _ <- intValue "native child AlphaZero seed" seed
  require
    (toInteger (Game.actionCountFor game) + 1 <= toInteger (maxBound :: Int))
    "native child AlphaZero action-plus-one Int arithmetic overflows"
  roundtrip <- case Workload.parseAlphaZeroPlanTransport (Workload.renderAlphaZeroPlanTransport plan) of
    Plan.Success value -> Right value
    Plan.Failure _ -> Left "native child full AlphaZero transport did not refine"
  require (roundtrip == plan) "native child full AlphaZero transport differs"

recipeHeadroom :: Word64 -> NativeRecipe -> Either Text NativeSeedHeadroom
recipeHeadroom seed recipe = do
  offsets <- case recipe of
    NativeReturnRecipe plan -> case ProductBudget.compiledRlTrainerKind plan of
      "ars" -> Right [("host-generator", 0)]
      "her" -> Right [("initial", 0), ("training-generator", 1), ("final-evaluation", 104729)]
      trainer
        | trainer `elem` ["ddpg", "td3", "sac", "crossq", "tqc"] ->
            Right
              [ ("actor-initial", 0)
              , ("training-generator", 1)
              , ("critic-A-initial", 101)
              , ("critic-B-initial", 202)
              ]
      trainer
        | trainer `elem` ["ppo", "a2c", "trpo", "maskableppo", "recurrentppo", "dqn", "qrdqn"] ->
            Right [("initial", 0), ("training-generator", 1)]
      _ -> Left "native child seed arithmetic has an unsupported trainer family"
    NativeArenaRecipe plan ->
      let q = toInteger . Plan.quantityValue
          generations = q (Workload.alphaZeroPlanGenerations plan)
          games = q (Workload.alphaZeroPlanSelfPlayGames plan)
          plies = q (Workload.alphaZeroPlanMaxPlies plan)
          arena = q (Workload.alphaZeroPlanArenaGames plan)
          generationProduct = (generations - 1) * 7919
          plyProduct = (plies - 1) * 7919
          arenaProduct = (arena - 1) * 1009
       in Right
            [ ("initial", 0)
            , ("generation-product", generationProduct)
            , ("last-game-index", games - 1)
            , ("ply-product", plyProduct)
            , ("self-play-game", generationProduct + games - 1)
            , ("self-play-MCTS", generationProduct + games - 1 + plyProduct)
            , ("arena-base", 7919)
            , ("arena-game-product", arenaProduct)
            , ("arena-MCTS", 7919 + arenaProduct + plyProduct)
            ]
  checkedNativeSeedHeadroom seed offsets

-- | The whole canonical pool, including all215 per-lane namespace/full-ID
-- injectivity checks. This is still data validation, not a durable reservation.
mkCanonicalNativeRlCohorts :: Substrate -> Either Text NativeRlCohortBatch
mkCanonicalNativeRlCohorts lane = do
  cohorts <- traverse project nativeRows
  refineNativeRlCohortBatch lane cohorts
 where
  project row = case Matrix.projectProductRow lane row of
    Plan.Success projection -> mkNativeRlCohortPlan projection
    Plan.Failure _ -> Left "canonical native cohort batch row did not project"

-- | An explicit list refinement enables meaningful missing/duplicate/order and
-- lane controls. It still proves plan data only, not actual executions.
refineNativeRlCohortBatch :: Substrate -> [NativeRlCohortPlan] -> Either Text NativeRlCohortBatch
refineNativeRlCohortBatch lane cohorts = do
  require
    (length nativeRows == 43 && length cohorts == 43)
    "native cohort batch requires exactly43 canonical rows"
  require
    (fmap (Matrix.rowId . nativeRlCohortPlanRow) cohorts == fmap Matrix.rowId nativeRows)
    "native cohort batch canonical row order or membership differs"
  let children = concatMap nativeRlCohortPlanChildren cohorts
      plans = fmap nativeRlSeedPlanSingleton children
  require (length plans == 215) "native cohort batch requires exactly215 child plans"
  require
    (all ((== lane) . Native.nativeSingletonSubstrate) plans)
    "native cohort batch child lane differs"
  unique "native cohort child experiment identities" (fmap Native.nativeSingletonExperiment plans)
  artifacts <- traverse singletonArtifact plans
  unique "native cohort child artifact identities" artifacts
  unique "native cohort child full PlanIds" (fmap Native.nativeSingletonPlanId plans)
  pure (NativeRlCohortBatch lane cohorts)

nativeRlSeedAssociation
  :: NativeRlCohortPlan
  -> Budget.ProductScenarioInvocation
  -> NativeSeedIndex
  -> Either Text Association.NativeChildAssociation
nativeRlSeedAssociation cohort invocation index = do
  child <-
    maybe
      (Left "native association child index is absent")
      Right
      (find ((== index) . nativeRlSeedPlanIndex) (nativeRlCohortPlanChildren cohort))
  Association.mkNativeChildAssociation
    (Matrix.rowId (nativeRlCohortPlanRow cohort))
    (nativeRlSeedPlanSingleton (nativeRlCohortServingChild cohort))
    invocation
    (nativeSeedIndexValue index)
    (nativeRlSeedPlanSingleton child)

nativeRows :: [Matrix.ProductRow 'Matrix.Declared]
nativeRows = filter nativeRow Matrix.allProductRows

nativeRow :: Matrix.ProductRow state -> Bool
nativeRow row = case Matrix.rowClass row of
  Matrix.RlAlgorithmEnvironment _ _ -> True
  Matrix.RlGoalConditioned _ -> True
  Matrix.AlphaZeroGame _ -> True
  _ -> False

singletonArtifact :: Native.NativeSingletonPlan -> Either Text Text
singletonArtifact plan = case (Native.nativeSingletonRlPlan plan, Native.nativeSingletonAlphaZeroPlan plan) of
  (Just value, Nothing) -> Right (Plan.runPlanArtifactId value)
  (Nothing, Just value) -> Right (Plan.runPlanArtifactId (Workload.alphaZeroPlanRunPlan value))
  _ -> Left "native lower singleton has an impossible kind combination"

intValue :: Text -> Word64 -> Either Text Int
intValue label value = do
  require (toInteger value <= toInteger (maxBound :: Int)) (label <> " exceeds actual Int range")
  pure (fromIntegral value)

require :: Bool -> Text -> Either Text ()
require condition message = unless condition (Left message)

unique :: (Ord value) => Text -> [value] -> Either Text ()
unique label values = require (Set.size (Set.fromList values) == length values) (label <> " are not injective")

-- Bounded renderer-only schema. Names, integers and exact binary64 words are
-- explicitly encoded; derived Show instances never participate in identity.
data Field = Field !Int !Text !Text deriving stock (Eq, Show)

scalar :: Text -> Text -> Field
scalar = Field 4096

number :: (Integral value) => Text -> value -> Field
number key = scalar key . Text.pack . show . toInteger

planField :: Text -> Text -> Field
planField = Field 32768

fieldsPrefix :: Text -> [Field] -> [Field]
fieldsPrefix prefix = fmap (\(Field limit key value) -> Field limit (prefix <> key) value)

budgetFields :: Text -> Budget.TrainingBudget -> [Field]
budgetFields prefix budget =
  fieldsPrefix
    prefix
    ( [ scalar "kind" (Budget.renderBudgetKind (Budget.trainingBudgetKind budget))
      , number "target" (Budget.trainingBudgetTargetUnits budget)
      , scalar "unit-label" (Budget.trainingBudgetUnitLabel budget)
      ]
        <> case Budget.trainingBudgetSeed budget of
          Nothing -> [scalar "seed-presence" "none"]
          Just seed -> [scalar "seed-presence" "some", number "seed" seed]
    )

barFields :: Text -> Convergence.ConvergenceBar -> [Field]
barFields prefix bar =
  fieldsPrefix
    prefix
    [ scalar "metric" (Convergence.convergenceMetricName bar)
    , scalar "goal" goal
    , scalar "target-bits" (doubleWord (Convergence.convergenceLiteratureTarget bar))
    , scalar "slack-bits" (doubleWord (Convergence.convergenceSlack bar))
    , scalar "threshold-bits" (doubleWord (Convergence.convergenceThreshold bar))
    ]
 where
  goal = case Convergence.convergenceMetricGoal bar of
    Budget.MetricMaximise -> "maximise"
    Budget.MetricMinimise -> "minimise"

doubleWord :: Double -> Text
doubleWord value =
  let digits = showHex (castDoubleToWord64 value) ""
   in Text.pack (replicate (16 - length digits) '0' <> digits)

listFields :: Text -> [Text] -> Either Text [Field]
listFields prefix values = do
  require (length values <= 64) (prefix <> " exceeds64 items")
  pure
    ( number (prefix <> "count") (length values)
        : [scalar (prefix <> decimal index) value | (index, value) <- zip [0 :: Int ..] values]
    )

decimal :: (Integral value) => value -> Text
decimal = Text.pack . show . toInteger

familyTag :: Matrix.RowFamily -> Text
familyTag value = case value of
  Matrix.Supervised -> "supervised"
  Matrix.ReinforcementLearning -> "reinforcement-learning"
  Matrix.AlphaZero -> "alphazero"
  Matrix.Tuning -> "tuning"

claimTag :: Matrix.DeviceClaim -> Text
claimTag value = case value of
  Matrix.SubstrateBackedANN -> "substrate-backed-ann"
  Matrix.SubstrateBackedPolicy -> "substrate-backed-policy"
  Matrix.GoalConditionedPolicy -> "goal-conditioned-policy"
  Matrix.SelfPlayPolicyValueNetwork -> "self-play-policy-value-network"
  Matrix.TuningPromotedTraining -> "tuning-promoted-training"

runKindTag :: Matrix.ProductRunKind -> Text
runKindTag value = case value of
  Matrix.ProductSupervisedRun -> "supervised"
  Matrix.ProductRlRun -> "reinforcement-learning"
  Matrix.ProductAlphaZeroRun -> "alphazero-self-play"
  Matrix.ProductTuningRun -> "tuning"

classFields :: Text -> Matrix.RowClass -> [Field]
classFields prefix value = fieldsPrefix prefix $ case value of
  Matrix.SupervisedClassification dataset model -> [scalar "tag" "supervised-classification", scalar "dataset" dataset, scalar "model" model]
  Matrix.SupervisedRegression dataset model -> [scalar "tag" "supervised-regression", scalar "dataset" dataset, scalar "model" model]
  Matrix.RlAlgorithmEnvironment algorithm environment -> [scalar "tag" "rl", scalar "algorithm" algorithm, scalar "environment" environment]
  Matrix.RlGoalConditioned environment -> [scalar "tag" "her", scalar "environment" environment]
  Matrix.AlphaZeroGame game -> [scalar "tag" "alphazero", scalar "game" game]
  Matrix.HyperparameterTuning algorithm -> [scalar "tag" "tuning", scalar "algorithm" algorithm]

descriptorFields :: Text -> Matrix.ProductPlanDescriptor kind -> Either Text [Field]
descriptorFields prefix descriptor = fmap (fieldsPrefix prefix) $ case descriptor of
  Matrix.RlProductDescriptor algorithm environment ticks vectors steps evaluations ->
    Right
      [ scalar "tag" "rl"
      , scalar "algorithm" algorithm
      , scalar "environment" environment
      , number "rollout-ticks-per-env" ticks
      , number "vector-environments" vectors
      , number "episode-steps" steps
      , number "evaluation-episodes" evaluations
      ]
  Matrix.AlphaZeroProductDescriptor game games simulations plies updates arena ->
    Right
      [ scalar "tag" "alphazero"
      , scalar "game" game
      , number "self-play-games" games
      , number "mcts-simulations" simulations
      , number "max-plies" plies
      , number "optimizer-updates" updates
      , number "arena-games" arena
      ]
  _ -> Left "native metadata descriptor has non-native kind"

evidenceTag :: Matrix.ProductEvidenceRequirements kind -> Either Text Text
evidenceTag value = case value of
  Matrix.RlProductEvidence -> Right "native-rl-completed-training"
  Matrix.AlphaZeroProductEvidence -> Right "alphazero-completed-training"
  _ -> Left "native metadata evidence requirement has non-native kind"

rowFields :: Matrix.ProductRow state -> Either Text [Field]
rowFields row = do
  features <-
    listFields
      "architecture-features."
      (fmap Architecture.renderArchitectureFeature (Matrix.rowArchitectureFeatures row))
  capability <- case Matrix.productCapability row of
    Matrix.ExecutableProduct descriptor requirements -> do
      descriptorData <- descriptorFields "capability.descriptor." descriptor
      tag <- evidenceTag requirements
      pure
        ( [scalar "capability.tag" "executable"]
            <> descriptorData
            <> [scalar "capability.evidence-requirements" tag]
        )
    Matrix.UnsupportedProduct _ -> Left "native metadata row capability is unsupported"
  pure
    ( fieldsPrefix
        "canonical-row."
        ( [scalar "row-id" (Matrix.rowId row), scalar "family" (familyTag (Matrix.family row))]
            <> classFields "row-class." (Matrix.rowClass row)
            <> [scalar "implementation" (Matrix.implementation row)]
            <> features
            <> [scalar "experiment-config-path" (Matrix.experimentConfig row)]
            <> budgetFields "training-budget." (Matrix.trainingBudget row)
            <> barFields "convergence-bar." (Matrix.convergenceBar row)
            <> [scalar "device-claim" (claimTag (Matrix.deviceClaim row))]
            <> capability
            <> [ scalar "integration-test" (Matrix.integrationTest row)
               , scalar "e2e-test" (Matrix.e2eTest row)
               , scalar "demo-panel" (Matrix.demoPanel row)
               ]
        )
    )

projectionFields :: Matrix.SomeProductProjection -> Either Text [Field]
projectionFields (Matrix.SomeProductProjection witness projection) = do
  parent <- case (witness, Matrix.productProjectionResolvedPlan projection) of
    (Plan.ReinforcementLearningWitness, Matrix.ResolvedRlProductPlan plan) -> Native.nativeRlSingletonPlan plan
    (Plan.AlphaZeroSelfPlayWitness, Matrix.ResolvedAlphaZeroProductPlan plan) -> Native.nativeAlphaZeroSingletonPlan plan
    _ -> Left "native metadata projection is not a native full workload"
  descriptor <- descriptorFields "descriptor." (Matrix.productProjectionDescriptor projection)
  requirement <- evidenceTag (Matrix.productProjectionEvidenceRequirements projection)
  features <-
    listFields
      "architecture-features."
      ( fmap
          Architecture.renderArchitectureFeature
          (Matrix.productProjectionArchitectureFeatures projection)
      )
  command <- listFields "command." (Matrix.productProjectionCommand projection)
  pure
    ( fieldsPrefix
        "parent-projection."
        ( [ scalar "row-id" (Matrix.productProjectionRowId projection)
          , scalar "family" (familyTag (Matrix.productProjectionFamily projection))
          ]
            <> classFields "row-class." (Matrix.productProjectionRowClass projection)
            <> [scalar "implementation" (Matrix.productProjectionImplementation projection)]
            <> features
            <> [ scalar "experiment-hash" (Matrix.productProjectionExperimentHash projection)
               , scalar "experiment-config-path" (Matrix.productProjectionExperimentConfig projection)
               ]
            <> budgetFields "training-budget." (Matrix.productProjectionTrainingBudget projection)
            <> barFields "convergence-bar." (Matrix.productProjectionConvergenceBar projection)
            <> [ scalar "device-claim" (claimTag (Matrix.productProjectionDeviceClaim projection))
               , scalar "integration-test" (Matrix.productProjectionIntegrationTest projection)
               , scalar "e2e-test" (Matrix.productProjectionE2ETest projection)
               , scalar "demo-panel" (Matrix.productProjectionDemoPanel projection)
               , scalar "substrate" (renderSubstrate (Matrix.productProjectionSubstrate projection))
               , scalar "run-kind" (runKindTag (Matrix.productProjectionRunKind projection))
               ]
            <> command
            <> descriptor
            <> [ scalar "evidence-requirements" requirement
               , planField "resolved-plan" (Native.renderNativeSingletonPlan parent)
               ]
        )
    )

childFields :: NativeRlSeedPlan -> Either Text [Field]
childFields child = do
  let plan = nativeRlSeedPlanSingleton child
      prefix = "child." <> decimal (nativeSeedIndexValue (nativeRlSeedPlanIndex child)) <> "."
      recipe = case nativeRlSeedPlanCompiledReturn child of
        Just value ->
          [ scalar "recipe-kind" "compiled-native-return"
          , scalar "compiled-return-transport" (ProductBudget.renderCompiledRlPlanTransport value)
          ]
        Nothing -> case nativeRlSeedPlanAlphaZero child of
          Just value ->
            [ scalar "recipe-kind" "full-alphazero-workload"
            , planField "complete-alphazero-transport" (Workload.renderAlphaZeroPlanTransport value)
            ]
          Nothing -> [] -- Closed private recipe sum makes this unreachable.
      headroom = nativeRlSeedPlanHeadroom child
      offsets = nativeSeedHeadroomOffsets headroom
  require (not (null recipe)) "native child recipe data is absent"
  pure
    ( fieldsPrefix
        prefix
        ( [ number "index" (nativeSeedIndexValue (nativeRlSeedPlanIndex child))
          , number "seed" (nativeRlSeedPlanSeed child)
          , planField "complete-singleton-transport" (Native.renderNativeSingletonPlan plan)
          , scalar "full-plan-id" (Plan.planIdText (Native.nativeSingletonPlanId plan))
          , scalar "common-plan-id" (Plan.planIdText (Native.nativeSingletonCommonPlanId plan))
          ]
            <> budgetFields "training-budget." (nativeRlSeedPlanTrainingBudget child)
            <> recipe
            <> [number "headroom.base" (nativeSeedHeadroomBase headroom), number "headroom.count" (length offsets)]
            <> concat
              [ let p = "headroom." <> decimal ordinal <> "."
                 in [scalar (p <> "label") label, number (p <> "offset") offset, number (p <> "actual-seed") actual]
              | (ordinal, (label, offset, actual)) <- zip [0 :: Int ..] offsets
              ]
            <> [number "headroom.maximum-actual-seed" (nativeSeedHeadroomMaximum headroom)]
        )
    )

renderFields :: [Field] -> Either Text ByteString
renderFields fields = do
  require (length fields <= 512) "native cohort transport exceeds512 fields"
  unique "native cohort transport field names" [name | Field _ name _ <- fields]
  encoded <- traverse encode fields
  let prefix = Encoding.encodeUtf8 (nativeRlCohortDataContract <> "|")
      total = toInteger (BS.length prefix) + sum (fmap (toInteger . BS.length) encoded)
  require (total <= 1048576) "native cohort transport exceeds1MiB"
  pure (BS.concat (prefix : encoded))
 where
  encode (Field bound name value) = do
    require
      (Text.length name <= 128 && Text.length value <= bound)
      "native cohort transport scalar character count exceeds bound"
    let keyBytes = Encoding.encodeUtf8 name
        valueBytes = Encoding.encodeUtf8 value
    require
      (BS.length keyBytes <= 128 && BS.length valueBytes <= bound)
      "native cohort transport scalar UTF8 bytes exceed bound"
    pure (frame keyBytes <> frame valueBytes)
  frame bytes = Encoding.encodeUtf8 (decimal (BS.length bytes) <> ":") <> bytes
