{-# LANGUAGE OverloadedStrings #-}

-- | Uncensored returned DATA. No final evaluation, refinement or numerical
-- reconstruction occurs here; expected and actual bindings remain separate.
module JitML.Checkpoint.NativePhase.Projection.Returns
  ( neuralReturned
  , arsReturned
  , alphaZeroReturned
  , lowNeuralFailure
  ) where

import JitML.Checkpoint.NativePhase.Projection.Build
import JitML.Checkpoint.NativePhase.Projection.Values
import JitML.Checkpoint.NativePhase.Types
import JitML.RL.Algorithms.ArsTrainer qualified as Ars
import JitML.RL.Algorithms.Common qualified as Common
import JitML.RL.AlphaZero.PolicyValueNet qualified as PVN
import JitML.RL.AlphaZero.PreparedTrainer qualified as AZ
import JitML.RL.PreparedNeuralAttempt qualified as Low
import JitML.RL.ProductBudget qualified as Plan
import JitML.RL.TrainerObservation qualified as Observation

neuralReturned :: Low.NeuralReturnedData -> Build Digest
neuralReturned actual = do
  compiled <-
    textValue
      CompiledTransportBytes
      (Plan.renderCompiledRlPlanTransport (Low.neuralReturnedPlan actual))
  expectedConfiguration <- neuralConfiguration (Low.neuralReturnedExpectedConfiguration actual)
  expectedInitial <- parameters (Low.neuralReturnedExpectedInitialParams actual)
  (family, actualConfiguration, initial, final, statistics, counters) <- case Low.neuralReturnedPolicy actual of
    Observation.ReturnedOnPolicy raw -> do
      c <- ppoConfig (Common.rawTrainerConfig raw)
      i <- parameters (Common.rawTrainerInitialParams raw)
      f <- parameters (Common.rawTrainerFinalParams raw)
      s <- referenceSequence (AliasElement NeuralStatAlias) ppoStat (Common.rawTrainerStats raw)
      pure (0, c, i, f, s, Common.rawTrainerCounters raw)
    Observation.ReturnedDqn raw -> do
      c <- dqnConfig (Common.rawTrainerConfig raw)
      i <- parameters (Common.rawTrainerInitialParams raw)
      f <- parameters (Common.rawTrainerFinalParams raw)
      s <- referenceSequence (AliasElement NeuralStatAlias) dqnStat (Common.rawTrainerStats raw)
      pure (1, c, i, f, s, Common.rawTrainerCounters raw)
    Observation.ReturnedQrDqn raw -> do
      c <- qrConfig (Common.rawTrainerConfig raw)
      i <- parameters (Common.rawTrainerInitialParams raw)
      f <- parameters (Common.rawTrainerFinalParams raw)
      s <- referenceSequence (AliasElement NeuralStatAlias) qrStat (Common.rawTrainerStats raw)
      pure (2, c, i, f, s, Common.rawTrainerCounters raw)
    Observation.ReturnedContinuous raw -> do
      c <- continuousConfig (Common.rawTrainerConfig raw)
      i <- parameters (Common.rawTrainerInitialParams raw)
      f <- parameters (Common.rawTrainerFinalParams raw)
      s <- referenceSequence (AliasElement NeuralStatAlias) continuousStat (Common.rawTrainerStats raw)
      pure (3, c, i, f, s, Common.rawTrainerCounters raw)
    Observation.ReturnedHer raw -> do
      c <- herConfig (Common.rawTrainerConfig raw)
      i <- parameters (Common.rawTrainerInitialParams raw)
      f <- parameters (Common.rawTrainerFinalParams raw)
      s <- referenceSequence (AliasElement NeuralStatAlias) herStat (Common.rawTrainerStats raw)
      pure (4, c, i, f, s, Common.rawTrainerCounters raw)
    Observation.ReturnedArs _ -> dataEither (Left (Malformed "neural returned observation has an ARS policy"))
  emit
    NRawNeural
    [ VWord family
    , compiled
    , VRef expectedConfiguration
    , VRef expectedInitial
    , VRef actualConfiguration
    , VRef initial
    , VRef final
    , VRef statistics
    , VWord (Common.observedEnvironmentTransitionCount counters)
    , VWord (Common.observedOptimizerUpdateCount counters)
    ]

arsReturned :: Plan.CompiledRlPlan -> Ars.ArsTrainObservation -> Build Digest
arsReturned suppliedPlan raw = do
  compiled <- textValue CompiledTransportBytes (Plan.renderCompiledRlPlanTransport suppliedPlan)
  config <- arsConfig (Common.rawTrainerConfig raw)
  initial <- tensor (Common.rawTrainerInitialParams raw)
  final <- tensor (Common.rawTrainerFinalParams raw)
  statistics <-
    referenceSequence (RefElement NArsIterationObservation) arsIteration (Common.rawTrainerStats raw)
  let counters = Common.rawTrainerCounters raw
  emit
    NRawArs
    [ compiled
    , VRef config
    , VRef initial
    , VRef final
    , VRef statistics
    , VWord (Common.observedEnvironmentTransitionCount counters)
    , VWord (Common.observedOptimizerUpdateCount counters)
    ]

arsIteration :: Ars.ArsIterationObservation -> Build Digest
arsIteration (Ars.ArsIterationObservation statistic step) = do
  s <- arsStat statistic
  a <- arsAppliedStep step
  emit NArsIterationObservation [VRef s, VRef a]

arsAppliedStep :: Ars.ArsAppliedStep -> Build Digest
arsAppliedStep step = do
  config <- arsConfig (Ars.arsStepConfig step)
  runtime <- arsRuntime (Ars.arsStepNumericalRuntime step)
  index <- intValue (Ars.arsStepIndex step)
  before <- tensor (Ars.arsStepThetaBefore step)
  after <- tensor (Ars.arsStepThetaAfter step)
  sampled <- referenceSequence (AliasElement TensorAlias) tensor (Ars.arsStepSampledDirections step)
  evaluated <-
    referenceSequence
      (RefElement NArsPerturbation)
      arsPerturbation
      (Ars.arsStepEvaluatedPerturbations step)
  kept <- referenceSequence (RefElement NArsKeptDirection) arsKept (Ars.arsStepKeptDirections step)
  direction <- listTensor (Ars.arsStepUpdateDirection step)
  transitions <- integerValue (Ars.arsStepObservedTransitions step)
  emit
    NArsAppliedStep
    [ VRef config
    , VRef runtime
    , index
    , VRef before
    , VRef after
    , VRef sampled
    , VRef evaluated
    , VRef kept
    , bitValue (Ars.arsStepNoiseStd step)
    , bitValue (Ars.arsStepReturnStdDev step)
    , VRef direction
    , bitValue (Ars.arsStepScale step)
    , transitions
    ]

arsRuntime :: Ars.ArsNumericalRuntime -> Build Digest
arsRuntime (Ars.ArsNumericalRuntime os arch compiler version recipe) = do
  fields <-
    sequence
      [ textValue ProducerComponentBytes os
      , textValue ProducerComponentBytes arch
      , textValue ProducerComponentBytes compiler
      , textValue ProducerComponentBytes version
      , textValue GeneralTextBytes recipe
      ]
  emit NArsRuntime fields

arsPerturbation :: ((Double, Int), (Double, Int), [Double]) -> Build Digest
arsPerturbation ((plus, plusSteps), (minus, minusSteps), delta) = do
  p <- intValue plusSteps
  m <- intValue minusSteps
  d <- listTensor delta
  emit NArsPerturbation [bitValue plus, p, bitValue minus, m, VRef d]

arsKept :: (Double, Double, [Double]) -> Build Digest
arsKept (plus, minus, delta) = do
  d <- listTensor delta
  emit NArsKeptDirection [bitValue plus, bitValue minus, VRef d]

alphaZeroReturned :: AZ.AlphaZeroTrainObservation -> Build Digest
alphaZeroReturned actual = do
  initialState <- gameState (AZ.alphaZeroObservedInitialState actual)
  initial <- policyValueNet (AZ.alphaZeroObservedInitialNet actual)
  initialAdam <- adam (AZ.alphaZeroObservedInitialAdam actual)
  final <- policyValueNet (AZ.alphaZeroObservedFinalNet actual)
  finalAdam <- adam (AZ.alphaZeroObservedFinalAdam actual)
  samples <-
    referenceSequence
      (RefElement NPolicyValueSample)
      policyValueSample
      (AZ.alphaZeroObservedSamples actual)
  counts <-
    traverse
      intValue
      [ AZ.alphaZeroObservedGenerationCount actual
      , AZ.alphaZeroObservedGenerationTarget actual
      , AZ.alphaZeroObservedGames actual
      , AZ.alphaZeroObservedSimulations actual
      , AZ.alphaZeroObservedMaxPlies actual
      , AZ.alphaZeroObservedUpdates actual
      , AZ.alphaZeroObservedSeed actual
      ]
  emit
    NRawAlphaZero
    ( [VRef initialState, VRef initial, VRef initialAdam, VRef final, VRef finalAdam, VRef samples]
        <> counts
    )

policyValueSample :: PVN.PolicyValueTrainingSample -> Build Digest
policyValueSample sample = do
  state <- gameState (PVN.sampleState sample)
  distribution <- tensor (PVN.sampleVisitDist sample)
  emit NPolicyValueSample [VRef state, VRef distribution, bitValue (PVN.sampleOutcome sample)]

lowNeuralFailure :: Low.NeuralAttemptFailure -> Build Digest
lowNeuralFailure actual = do
  detail <- textValue DiagnosticTextBytes (Low.neuralFailureDetail actual)
  facts <- lowFacts (Low.neuralFailureFacts actual)
  emit
    NLowNeuralFailure
    [ lowStage (Low.neuralFailureStage actual)
    , lowKind (Low.neuralFailureKind actual)
    , detail
    , VRef facts
    ]

lowFacts :: Low.NeuralFailureFacts -> Build Digest
lowFacts actual = do
  plan <- case Low.neuralFailurePlan actual of
    Nothing -> pure VNull
    Just supplied -> textValue CompiledTransportBytes (Plan.renderCompiledRlPlanTransport supplied)
  expected <- optional neuralConfiguration (Low.neuralFailureExpectedConfiguration actual)
  initial <- optional parameters (Low.neuralFailureInitialParams actual)
  returned <- optional neuralConfiguration (Low.neuralFailureReturnedConfiguration actual)
  let counters = case Low.neuralFailureReturnedCounters actual of
        Nothing -> VNull
        Just observed ->
          VList
            [ VWord (Common.observedEnvironmentTransitionCount observed)
            , VWord (Common.observedOptimizerUpdateCount observed)
            ]
  emit NLowNeuralFailureFacts [plan, expected, initial, returned, counters]

lowStage :: Low.NeuralAttemptStage -> NodeValue
lowStage value = VWord $ case value of
  Low.NeuralAdmission -> 0
  Low.NeuralProbe -> 1
  Low.NeuralRecipe -> 2
  Low.NeuralPrepare -> 3
  Low.NeuralInitialization -> 4
  Low.NeuralContinuation -> 5
  Low.NeuralReturnMaterialization -> 6
  Low.NeuralReturnBinding -> 7

lowKind :: Low.NeuralFailureKind -> NodeValue
lowKind value = VWord $ case value of
  Low.NeuralRejected -> 0
  Low.NeuralSynchronousFailure -> 1
  Low.NeuralAlreadyConsumed -> 2
