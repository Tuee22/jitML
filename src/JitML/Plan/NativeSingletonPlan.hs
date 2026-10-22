{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Complete singleton-plan data for native qualification children. These
-- values do not establish canonical Matrix membership or actual execution.
module JitML.Plan.NativeSingletonPlan
  ( NativeSingletonPlan
  , nativeRlSingletonPlan
  , nativeAlphaZeroSingletonPlan
  , nativeSingletonRlPlan
  , nativeSingletonAlphaZeroPlan
  , nativeSingletonPlanId
  , nativeSingletonCommonPlanId
  , nativeSingletonSeed
  , nativeSingletonSubstrate
  , nativeSingletonExperiment
  , renderNativeSingletonPlan
  , parseNativeSingletonPlan
  , deriveNativeChildPlan
  , nativeChildNamespaceContract
  )
where

import Control.Monad (unless, when)
import Data.ByteString qualified as ByteString
import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word64)
import Text.Read (readMaybe)

import JitML.Plan.Plan qualified as Plan
import JitML.Plan.Workload qualified as Workload
import JitML.Substrate (Substrate, parseSubstrate, renderSubstrate)

-- Constructors are deliberately private. The enclosed RunPlans themselves
-- already crossed resolveRun; this wrapper additionally requires one seed.
data NativeSingletonPlan
  = NativeRlSingleton !(Plan.RunPlan 'Plan.ReinforcementLearning)
  | NativeAlphaZeroSingleton !Workload.AlphaZeroPlan
  deriving stock (Eq, Show)

nativeRlSingletonPlan
  :: Plan.RunPlan 'Plan.ReinforcementLearning -> Either Text NativeSingletonPlan
nativeRlSingletonPlan plan = singletonSeed plan >> bounded (NativeRlSingleton plan)

nativeAlphaZeroSingletonPlan
  :: Workload.AlphaZeroPlan -> Either Text NativeSingletonPlan
nativeAlphaZeroSingletonPlan plan = singletonSeed (Workload.alphaZeroPlanRunPlan plan) >> bounded (NativeAlphaZeroSingleton plan)

bounded :: NativeSingletonPlan -> Either Text NativeSingletonPlan
bounded value = do
  unless
    (ByteString.length (Text.Encoding.encodeUtf8 (renderNativeSingletonPlan value)) <= 32768)
    (Left "native singleton transport exceeds 32768 UTF-8 bytes")
  pure value

nativeSingletonRlPlan
  :: NativeSingletonPlan -> Maybe (Plan.RunPlan 'Plan.ReinforcementLearning)
nativeSingletonRlPlan (NativeRlSingleton plan) = Just plan
nativeSingletonRlPlan (NativeAlphaZeroSingleton _) = Nothing

nativeSingletonAlphaZeroPlan
  :: NativeSingletonPlan -> Maybe Workload.AlphaZeroPlan
nativeSingletonAlphaZeroPlan (NativeRlSingleton _) = Nothing
nativeSingletonAlphaZeroPlan (NativeAlphaZeroSingleton plan) = Just plan

nativeSingletonPlanId :: NativeSingletonPlan -> Plan.PlanId
nativeSingletonPlanId (NativeRlSingleton plan) = Plan.runPlanId plan
nativeSingletonPlanId (NativeAlphaZeroSingleton plan) = Workload.alphaZeroPlanId plan

nativeSingletonCommonPlanId :: NativeSingletonPlan -> Plan.PlanId
nativeSingletonCommonPlanId (NativeRlSingleton plan) = Plan.runPlanId plan
nativeSingletonCommonPlanId (NativeAlphaZeroSingleton plan) = Plan.runPlanId (Workload.alphaZeroPlanRunPlan plan)

nativeSingletonSubstrate :: NativeSingletonPlan -> Substrate
nativeSingletonSubstrate (NativeRlSingleton plan) = Plan.runPlanSubstrate plan
nativeSingletonSubstrate (NativeAlphaZeroSingleton plan) = Plan.runPlanSubstrate (Workload.alphaZeroPlanRunPlan plan)

nativeSingletonExperiment :: NativeSingletonPlan -> Text
nativeSingletonExperiment (NativeRlSingleton plan) = Plan.runPlanExperimentId plan
nativeSingletonExperiment (NativeAlphaZeroSingleton plan) = Plan.runPlanExperimentId (Workload.alphaZeroPlanRunPlan plan)

nativeSingletonSeed :: NativeSingletonPlan -> Word64
nativeSingletonSeed (NativeRlSingleton plan) = NonEmpty.head (Plan.seedCohortValues (Plan.runPlanSeeds plan))
nativeSingletonSeed (NativeAlphaZeroSingleton plan) = NonEmpty.head (Plan.seedCohortValues (Plan.runPlanSeeds (Workload.alphaZeroPlanRunPlan plan)))

singletonSeed :: Plan.RunPlan kind -> Either Text Word64
singletonSeed plan = case NonEmpty.toList (Plan.seedCohortValues (Plan.runPlanSeeds plan)) of
  [seed] -> Right seed
  _ -> Left "native child plan requires exactly one execution seed"

renderNativeSingletonPlan :: NativeSingletonPlan -> Text
renderNativeSingletonPlan (NativeRlSingleton plan) = renderPlan "reinforcement-learning" plan
renderNativeSingletonPlan (NativeAlphaZeroSingleton plan) =
  encodeFields
    [ "jitml-native-singleton-plan-v1"
    , "alphazero-self-play"
    , Workload.renderAlphaZeroPlanTransport plan
    ]

renderPlan :: Text -> Plan.RunPlan kind -> Text
renderPlan kind plan =
  encodeFields
    ( [ "jitml-native-singleton-plan-v1"
      , kind
      , Plan.planIdText (Plan.runPlanId plan)
      , showText (Plan.runPlanVersion plan)
      , Plan.runPlanExperimentId plan
      , Plan.runPlanSubjectId plan
      , Plan.runPlanArtifactId plan
      , Plan.runPlanTopicId plan
      , renderSubstrate (Plan.runPlanSubstrate plan)
      , renderPlacement (Plan.runPlanPlacement plan)
      , showText (NonEmpty.head (Plan.seedCohortValues (Plan.runPlanSeeds plan)))
      ]
        <> concatMap (\(name, value) -> [name, showText value]) (Plan.runPlanBudgetSummary plan)
    )

-- | A bounded canonical transport. Re-refinement checks every common field,
-- seed, unit/quantity and derived PlanId. No source or producer is authenticated.
parseNativeSingletonPlan :: Text -> Either Text NativeSingletonPlan
parseNativeSingletonPlan input = do
  unless
    (ByteString.length (Text.Encoding.encodeUtf8 input) <= 32768)
    (Left "native singleton transport exceeds 32768 UTF-8 bytes")
  fields <- decodeFields 64 input
  parsed <- case fields of
    ["jitml-native-singleton-plan-v1", "alphazero-self-play", transport] ->
      case Workload.parseAlphaZeroPlanTransport transport of
        Plan.Failure errors -> Left ("native AlphaZero transport did not refine: " <> showText errors)
        Plan.Success plan -> nativeAlphaZeroSingletonPlan plan
    tag : kind : identity : version : experiment : subject : artifact : topic : lane : placement : seed
      : budget -> do
        unless
          (tag == "jitml-native-singleton-plan-v1")
          (Left "unsupported native singleton transport version")
        expectedId <- Plan.refinePlanIdText identity
        runVersion <- decimal "run version" version
        substrate <- maybe (Left "native singleton substrate is invalid") Right (parseSubstrate lane)
        location <- parsePlacement placement
        seedValue <- decimal "seed" seed
        let request :: Plan.RunKindWitness kind -> Plan.RawRunBudget kind -> Plan.RawRunRequest kind
            request witness rawBudget =
              Plan.RawRunRequest
                { Plan.rawRunVersion = runVersion
                , Plan.rawRunKind = witness
                , Plan.rawRunExperimentId = experiment
                , Plan.rawRunSubjectId = subject
                , Plan.rawRunArtifactId = artifact
                , Plan.rawRunTopicId = topic
                , Plan.rawRunSubstrate = substrate
                , Plan.rawRunPlacement = location
                , Plan.rawRunSeeds = [seedValue]
                , Plan.rawRunBudget = rawBudget
                }
        result <- case kind of
          "reinforcement-learning" -> do
            values <- parseBudget rlBudgetNames budget
            case values of
              [transitions, ticks, vector, steps, evaluations] ->
                refine
                  ( request
                      Plan.ReinforcementLearningWitness
                      (Plan.RawRlBudget transitions ticks vector steps evaluations)
                  )
                  >>= nativeRlSingletonPlan
              _ -> Left "native RL budget field count differs"
          _ -> Left "native singleton transport has unsupported run kind"
        unless
          (nativeSingletonPlanId result == expectedId)
          (Left "native singleton transport PlanId differs from the complete refined plan")
        pure result
    _ -> Left "native singleton transport common field count differs"
  unless
    (renderNativeSingletonPlan parsed == input)
    (Left "native singleton transport is not canonical")
  pure parsed

rlBudgetNames :: [Text]
rlBudgetNames =
  [ "environment-transitions"
  , "rollout-ticks-per-environment"
  , "vector-environments"
  , "episode-steps"
  , "evaluation-episodes"
  ]

parseBudget :: [Text] -> [Text] -> Either Text [Integer]
parseBudget [] [] = Right []
parseBudget (name : names) (actual : value : rest) = do
  unless (name == actual) (Left "native singleton budget unit/order differs")
  quantity <- decimal name value
  remaining <- parseBudget names rest
  pure (toInteger quantity : remaining)
parseBudget _ _ = Left "native singleton budget field count differs"

-- This versions only the prescribed child derivation. It adopts no learning
-- criterion and is not the future qualification-policy recipe in Matrix.
nativeChildNamespaceContract :: Text
nativeChildNamespaceContract = "native-rl-qualification-v1"

-- | Child zero is the entire parent. Other children change only the singleton
-- seed and experiment/artifact namespaces. Subject, topic, placement, lane,
-- budget and run version remain identical. Family-specific offset headroom
-- and complete canonical Matrix equality remain higher-layer requirements.
deriveNativeChildPlan :: NativeSingletonPlan -> Int -> Either Text NativeSingletonPlan
deriveNativeChildPlan parent index = do
  unless (index >= 0 && index < 5) (Left "native child ordinal must be in 0..4")
  validateNamespace (nativeSingletonExperiment parent)
  let largest = toInteger (nativeSingletonSeed parent) + 4
  unless
    (largest <= toInteger (maxBound :: Int))
    (Left "native child seed sequence exceeds the native Int range")
  result <-
    if index == 0
      then pure parent
      else case parent of
        NativeRlSingleton plan -> do
          let (transitions, ticks, vector, steps, evaluations) = Plan.runPlanRlBudget plan
          refine
            ( childRequest
                Plan.ReinforcementLearningWitness
                plan
                ( Plan.RawRlBudget
                    (quantity transitions)
                    (quantity ticks)
                    (quantity vector)
                    (quantity steps)
                    (quantity evaluations)
                )
            )
            >>= nativeRlSingletonPlan
        NativeAlphaZeroSingleton workload -> do
          let plan = Workload.alphaZeroPlanRunPlan workload
              (generations, games, simulations, plies, updates, arena) = Plan.runPlanAlphaZeroBudget plan
              request =
                Workload.RawAlphaZeroPlan
                  { Workload.rawAlphaZeroRun =
                      childRequest
                        Plan.AlphaZeroSelfPlayWitness
                        plan
                        ( Plan.RawAlphaZeroBudget
                            (quantity generations)
                            (quantity games)
                            (quantity simulations)
                            (quantity plies)
                            (quantity updates)
                            (quantity arena)
                        )
                  , Workload.rawAlphaZeroGame = Workload.renderAlphaZeroGame (Workload.alphaZeroPlanGame workload)
                  }
          case Workload.resolveAlphaZeroPlan request of
            Plan.Failure errors -> Left ("native AlphaZero child refinement failed: " <> showText errors)
            Plan.Success child -> nativeAlphaZeroSingletonPlan child
  validateNamespace (nativeSingletonExperiment result)
  roundtrip <- parseNativeSingletonPlan (renderNativeSingletonPlan result)
  unless (roundtrip == result) (Left "native child complete plan roundtrip differs")
  pure result
 where
  suffix = "." <> nativeChildNamespaceContract <> "." <> showText index
  childRequest
    :: Plan.RunKindWitness kind -> Plan.RunPlan kind -> Plan.RawRunBudget kind -> Plan.RawRunRequest kind
  childRequest witness plan budget =
    Plan.RawRunRequest
      { Plan.rawRunVersion = Plan.runPlanVersion plan
      , Plan.rawRunKind = witness
      , Plan.rawRunExperimentId = Plan.runPlanExperimentId plan <> suffix
      , Plan.rawRunSubjectId = Plan.runPlanSubjectId plan
      , Plan.rawRunArtifactId = Plan.runPlanArtifactId plan <> suffix
      , Plan.rawRunTopicId = Plan.runPlanTopicId plan
      , Plan.rawRunSubstrate = Plan.runPlanSubstrate plan
      , Plan.rawRunPlacement = Plan.runPlanPlacement plan
      , Plan.rawRunSeeds = [fromInteger (toInteger (nativeSingletonSeed parent) + toInteger index)]
      , Plan.rawRunBudget = budget
      }
  quantity :: Plan.Quantity unit -> Integer
  quantity = toInteger . Plan.quantityValue

validateNamespace :: Text -> Either Text ()
validateNamespace value =
  unless
    ( not (Text.null value)
        && Text.length value <= 256
        && value /= "."
        && value /= ".."
        && Text.all
          ( \c ->
              isAsciiUpper c || isAsciiLower c || isDigit c || c == '.' || c == '-'
          )
          value
    )
    (Left "native child experiment namespace is not a bounded flat ASCII component")

refine :: Plan.RawRunRequest kind -> Either Text (Plan.RunPlan kind)
refine raw = case Plan.resolveRun raw of
  Plan.Success plan -> Right plan
  Plan.Failure errors -> Left ("native singleton plan refinement failed: " <> showText errors)

decimal :: Text -> Text -> Either Text Word64
decimal label raw
  | Text.null raw || Text.length raw > 20 || not (Text.all isDigit raw) =
      Left ("native singleton invalid decimal " <> label)
  | otherwise =
      maybe
        (Left ("native singleton decimal overflows Word64: " <> label))
        Right
        (readMaybe (Text.unpack raw))

encodeFields :: [Text] -> Text
encodeFields = Text.concat . fmap (\value -> showText (Text.length value) <> ":" <> value)

decodeFields :: Int -> Text -> Either Text [Text]
decodeFields remaining input
  | Text.null input = Right []
  | remaining <= 0 = Left "native singleton transport has too many fields"
  | otherwise = do
      let (count, colonAndBody) = Text.breakOn ":" input
      when (Text.null colonAndBody) (Left "native singleton field length has no separator")
      size <- decimal "field length" count
      let body = Text.drop 1 colonAndBody
      unless (toInteger size <= toInteger (Text.length body)) (Left "native singleton field is truncated")
      let (value, rest) = Text.splitAt (fromIntegral size) body
      (value :) <$> decodeFields (remaining - 1) rest

renderPlacement :: Plan.RunPlacement -> Text
renderPlacement Plan.ClusterRun = "cluster"
renderPlacement Plan.HostRun = "host"
renderPlacement Plan.InProcessRun = "in-process"

parsePlacement :: Text -> Either Text Plan.RunPlacement
parsePlacement "cluster" = Right Plan.ClusterRun
parsePlacement "host" = Right Plan.HostRun
parsePlacement "in-process" = Right Plan.InProcessRun
parsePlacement _ = Left "native singleton placement is invalid"

showText :: (Show a) => a -> Text
showText = Text.pack . show
