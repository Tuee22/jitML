{-# LANGUAGE CPP #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Typed source-data projections only. Positional patterns intentionally make
-- an added/reordered source field a source-review/compiler obligation.
module JitML.Checkpoint.NativePhase.Projection.Values
  ( neuralConfiguration
  , ppoConfig
  , dqnConfig
  , qrConfig
  , continuousConfig
  , herConfig
  , arsConfig
  , ppoStat
  , dqnStat
  , qrStat
  , continuousStat
  , herStat
  , arsStat
  , parameters
  , gradient
  , adam
  , policyValueNet
  , policyValueNetWithParameters
  , generator
  , discreteReplay
  , discreteTuple
  , continuousReplay
  , gameState
  ) where

import Data.List.NonEmpty qualified as NE
import Data.Text qualified as Text
import Data.Vector.Unboxed (Vector)
import System.Random qualified as Random

import JitML.Checkpoint.NativePhase.Projection.Build
import JitML.Checkpoint.NativePhase.Types
import JitML.Numerics.Mlp qualified as Mlp
import JitML.RL.Algorithms.ArsTrainer qualified as Ars
import JitML.RL.Algorithms.ContinuousTrainer qualified as Continuous
import JitML.RL.Algorithms.DqnTrainer qualified as Dqn
import JitML.RL.Algorithms.HerLoss qualified as HerLoss
import JitML.RL.Algorithms.HerTrainer qualified as Her
import JitML.RL.Algorithms.PpoTrainer qualified as Ppo
import JitML.RL.Algorithms.QrDqnTrainer qualified as Qr
import JitML.RL.AlphaZero qualified as Game
import JitML.RL.AlphaZero.PolicyValueNet qualified as PVN
import JitML.RL.TrainerConfiguration qualified as Config

neuralConfiguration :: Config.NeuralTrainerConfiguration -> Build Digest
neuralConfiguration value = case value of
  Config.OnPolicyConfiguration actual -> ppoConfig actual
  Config.DqnConfiguration actual -> dqnConfig actual
  Config.QrDqnConfiguration actual -> qrConfig actual
  Config.ContinuousConfiguration actual -> continuousConfig actual
  Config.HerConfiguration actual -> herConfig actual

ppoConfig :: Ppo.PpoTrainConfig -> Build Digest
ppoConfig
  ( Ppo.PpoTrainConfig
      ppoSeed
      ppoHiddenUnits
      ppoVectorEnvCount
      ppoRolloutSteps
      ppoNumIterations
      ppoEpochsPerUpdate
      ppoMiniBatchSize
      ppoGamma
      ppoLambda
      ppoClipEps
      ppoValueCoef
      ppoEntropyCoef
      ppoCountBeta
      ppoMaxEpisodeSteps
      ppoActionCount
      ppoObsSize
      ppoLearningRate
      ppoVariant
      ppoKlTarget
      ppoTrpoCgIterations
      ppoTrpoCgDamping
      ppoTrpoBacktrackIterations
      ppoTrpoBacktrackCoef
      ppoTrpoCriticUpdates
      ppoTrpoCriticLearningRate
      ppoRecurrentStateSize
    ) = do
    fields <-
      sequence
        [ intValue ppoSeed
        , intValue ppoHiddenUnits
        , intValue ppoVectorEnvCount
        , intValue ppoRolloutSteps
        , intValue ppoNumIterations
        , intValue ppoEpochsPerUpdate
        , intValue ppoMiniBatchSize
        , pure (bitValue ppoGamma)
        , pure (bitValue ppoLambda)
        , pure (bitValue ppoClipEps)
        , pure (bitValue ppoValueCoef)
        , pure (bitValue ppoEntropyCoef)
        , pure (bitValue ppoCountBeta)
        , intValue ppoMaxEpisodeSteps
        , intValue ppoActionCount
        , intValue ppoObsSize
        , pure (bitValue ppoLearningRate)
        , pure (ppoVariantValue ppoVariant)
        , pure (bitValue ppoKlTarget)
        , intValue ppoTrpoCgIterations
        , pure (bitValue ppoTrpoCgDamping)
        , intValue ppoTrpoBacktrackIterations
        , pure (bitValue ppoTrpoBacktrackCoef)
        , intValue ppoTrpoCriticUpdates
        , pure (bitValue ppoTrpoCriticLearningRate)
        , intValue ppoRecurrentStateSize
        ]
    emit NPpoConfig fields

dqnConfig :: Dqn.DqnTrainConfig -> Build Digest
dqnConfig
  ( Dqn.DqnTrainConfig
      dqnSeed
      dqnHiddenUnits
      dqnNumSteps
      dqnReplayCapacity
      dqnBatchSize
      dqnLearningRate
      dqnGamma
      dqnTargetUpdateInterval
      dqnEpsilonStart
      dqnEpsilonEnd
      dqnEpsilonDecaySteps
      dqnTrainStart
      dqnUpdateFrequency
      dqnMaxEpisodeSteps
      dqnActionCount
      dqnObsSize
      dqnStatInterval
      dqnUseDouble
    ) = do
    fields <-
      sequence
        [ intValue dqnSeed
        , intValue dqnHiddenUnits
        , intValue dqnNumSteps
        , intValue dqnReplayCapacity
        , intValue dqnBatchSize
        , pure (bitValue dqnLearningRate)
        , pure (bitValue dqnGamma)
        , intValue dqnTargetUpdateInterval
        , pure (bitValue dqnEpsilonStart)
        , pure (bitValue dqnEpsilonEnd)
        , intValue dqnEpsilonDecaySteps
        , intValue dqnTrainStart
        , intValue dqnUpdateFrequency
        , intValue dqnMaxEpisodeSteps
        , intValue dqnActionCount
        , intValue dqnObsSize
        , intValue dqnStatInterval
        , pure (VBool dqnUseDouble)
        ]
    emit NDqnConfig fields

qrConfig :: Qr.QrDqnTrainConfig -> Build Digest
qrConfig
  ( Qr.QrDqnTrainConfig
      qrSeed
      qrHiddenUnits
      qrNumQuantiles
      qrNumSteps
      qrReplayCapacity
      qrBatchSize
      qrLearningRate
      qrGamma
      qrKappa
      qrTargetUpdateInterval
      qrEpsilonStart
      qrEpsilonEnd
      qrEpsilonDecaySteps
      qrTrainStart
      qrUpdateFrequency
      qrMaxEpisodeSteps
      qrActionCount
      qrObsSize
      qrStatInterval
    ) = do
    fields <-
      sequence
        [ intValue qrSeed
        , intValue qrHiddenUnits
        , intValue qrNumQuantiles
        , intValue qrNumSteps
        , intValue qrReplayCapacity
        , intValue qrBatchSize
        , pure (bitValue qrLearningRate)
        , pure (bitValue qrGamma)
        , pure (bitValue qrKappa)
        , intValue qrTargetUpdateInterval
        , pure (bitValue qrEpsilonStart)
        , pure (bitValue qrEpsilonEnd)
        , intValue qrEpsilonDecaySteps
        , intValue qrTrainStart
        , intValue qrUpdateFrequency
        , intValue qrMaxEpisodeSteps
        , intValue qrActionCount
        , intValue qrObsSize
        , intValue qrStatInterval
        ]
    emit NQrConfig fields

continuousConfig :: Continuous.ContinuousTrainConfig -> Build Digest
continuousConfig
  ( Continuous.ContinuousTrainConfig
      ctVariant
      ctSeed
      ctHidden
      ctNumSteps
      ctReplayCapacity
      ctBatchSize
      ctActorLr
      ctCriticLr
      ctGamma
      ctTau
      ctPolicyDelay
      ctExplNoise
      ctTargetNoise
      ctNoiseClip
      ctSacAlpha
      ctAlphaLr
      ctTargetEntropy
      ctPolicyStd
      ctTqcDropPerCritic
      ctStartSteps
      ctTrainStart
      ctMaxEpisodeSteps
      ctObsSize
      ctActionLow
      ctActionHigh
      ctStatInterval
      ctEnvName
      ctCountBeta
    ) = do
    fields <-
      sequence
        [ pure (continuousVariant ctVariant)
        , intValue ctSeed
        , intValue ctHidden
        , intValue ctNumSteps
        , intValue ctReplayCapacity
        , intValue ctBatchSize
        , pure (bitValue ctActorLr)
        , pure (bitValue ctCriticLr)
        , pure (bitValue ctGamma)
        , pure (bitValue ctTau)
        , intValue ctPolicyDelay
        , pure (bitValue ctExplNoise)
        , pure (bitValue ctTargetNoise)
        , pure (bitValue ctNoiseClip)
        , pure (bitValue ctSacAlpha)
        , pure (bitValue ctAlphaLr)
        , pure (bitValue ctTargetEntropy)
        , pure (bitValue ctPolicyStd)
        , intValue ctTqcDropPerCritic
        , intValue ctStartSteps
        , intValue ctTrainStart
        , intValue ctMaxEpisodeSteps
        , intValue ctObsSize
        , pure (bitValue ctActionLow)
        , pure (bitValue ctActionHigh)
        , intValue ctStatInterval
        , textValue GeneralTextBytes ctEnvName
        , pure (bitValue ctCountBeta)
        ]
    emit NContinuousConfig fields

herConfig :: Her.HerTrainConfig -> Build Digest
herConfig
  ( Her.HerTrainConfig
      herSeed
      herNumBits
      herHiddenUnits
      herEpisodes
      herReplayCapacity
      herBatchSize
      herLearningRate
      herGamma
      herTargetUpdateInterval
      herEpsilon
      herUseHindsight
      herStrategy
      herStatInterval
      herUpdatesPerEpisode
    ) = do
    fields <-
      sequence
        [ intValue herSeed
        , intValue herNumBits
        , intValue herHiddenUnits
        , intValue herEpisodes
        , intValue herReplayCapacity
        , intValue herBatchSize
        , pure (bitValue herLearningRate)
        , pure (bitValue herGamma)
        , intValue herTargetUpdateInterval
        , pure (bitValue herEpsilon)
        , pure (VBool herUseHindsight)
        , pure (herStrategyValue herStrategy)
        , intValue herStatInterval
        , intValue herUpdatesPerEpisode
        ]
    emit NHerConfig fields

arsConfig :: Ars.ArsTrainConfig -> Build Digest
arsConfig
  ( Ars.ArsTrainConfig
      arsSeed
      arsIterations
      arsNumDirections
      arsTopB
      arsStepSize
      arsNoiseStd
      arsMaxEpisodeSteps
      arsActionCount
      arsObsSize
    ) = do
    fields <-
      sequence
        [ intValue arsSeed
        , intValue arsIterations
        , intValue arsNumDirections
        , intValue arsTopB
        , pure (bitValue arsStepSize)
        , pure (bitValue arsNoiseStd)
        , intValue arsMaxEpisodeSteps
        , intValue arsActionCount
        , intValue arsObsSize
        ]
    emit NArsConfig fields

ppoStat :: Ppo.PpoIterationStat -> Build Digest
ppoStat (Ppo.PpoIterationStat iterIndex iterMeanReward iterMedianReward iterMaxReward iterEpisodes) = do
  fields <-
    sequence
      [ intValue iterIndex
      , pure (bitValue iterMeanReward)
      , pure (bitValue iterMedianReward)
      , pure (bitValue iterMaxReward)
      , intValue iterEpisodes
      ]
  emit NPpoStat fields

dqnStat :: Dqn.DqnIterationStat -> Build Digest
dqnStat (Dqn.DqnIterationStat dqnIterStep dqnIterEpisodes dqnIterMeanReward dqnIterLastEpisodeReward) = do
  fields <-
    sequence
      [ intValue dqnIterStep
      , intValue dqnIterEpisodes
      , pure (bitValue dqnIterMeanReward)
      , pure (bitValue dqnIterLastEpisodeReward)
      ]
  emit NDqnStat fields

qrStat :: Qr.QrDqnIterationStat -> Build Digest
qrStat (Qr.QrDqnIterationStat qrIterStep qrIterEpisodes qrIterMeanReward) = do
  fields <-
    sequence
      [ intValue qrIterStep
      , intValue qrIterEpisodes
      , pure (bitValue qrIterMeanReward)
      ]
  emit NQrStat fields

continuousStat :: Continuous.ContinuousIterationStat -> Build Digest
continuousStat
  ( Continuous.ContinuousIterationStat
      contIterStep
      contIterEpisodes
      contIterMeanReward
      contIterLastEpisodeReward
    ) = do
    fields <-
      sequence
        [ intValue contIterStep
        , intValue contIterEpisodes
        , pure (bitValue contIterMeanReward)
        , pure (bitValue contIterLastEpisodeReward)
        ]
    emit NContinuousStat fields

herStat :: Her.HerIterationStat -> Build Digest
herStat (Her.HerIterationStat herIterEpisode herIterSuccessRate) = do
  fields <-
    sequence
      [ intValue herIterEpisode
      , pure (bitValue herIterSuccessRate)
      ]
  emit NHerStat fields

arsStat :: Ars.ArsIterationStat -> Build Digest
arsStat (Ars.ArsIterationStat arsIterIndex arsIterMeanReturn arsIterBestReturn) = do
  fields <-
    sequence
      [ intValue arsIterIndex
      , pure (bitValue arsIterMeanReturn)
      , pure (bitValue arsIterBestReturn)
      ]
  emit NArsStat fields

ppoVariantValue :: Ppo.OnPolicyVariant -> NodeValue
ppoVariantValue value = VWord $ case value of
  Ppo.VariantPPO -> 0
  Ppo.VariantA2C -> 1
  Ppo.VariantTRPO -> 2
  Ppo.VariantMaskablePPO -> 3
  Ppo.VariantRecurrentPPO -> 4

continuousVariant :: Continuous.ContinuousVariant -> NodeValue
continuousVariant value = VWord $ case value of
  Continuous.VariantDDPG -> 0
  Continuous.VariantTD3 -> 1
  Continuous.VariantSAC -> 2
  Continuous.VariantCrossQ -> 3
  Continuous.VariantTQC -> 4

herStrategyValue :: HerLoss.HerStrategy -> NodeValue
herStrategyValue value = VWord $ case value of
  HerLoss.HerFuture -> 0
  HerLoss.HerEpisode -> 1
  HerLoss.HerRandom -> 2

parameters :: Mlp.MlpParams -> Build Digest
parameters (Mlp.MlpParams (Mlp.MlpShape inputs hidden outputs) w1 b1 w2 b2) = do
  shape <- VList <$> traverse intValue [inputs, hidden, outputs]
  refs <- traverse tensor [w1, b1, w2, b2]
  emit NParams (shape : map VRef refs)

gradient :: Mlp.MlpGradient -> Build Digest
gradient (Mlp.MlpGradient w1 b1 w2 b2) = do
  refs <- traverse tensor [w1, b1, w2, b2]
  emit NGradient (map VRef refs)

adam :: Mlp.AdamState -> Build Digest
adam (Mlp.AdamState step m v) = do
  actualStep <- intValue step
  mRef <- gradient m
  vRef <- gradient v
  emit NAdam [actualStep, VRef mRef, VRef vRef]

policyValueNet :: PVN.PolicyValueNet -> Build Digest
policyValueNet = fmap fst . policyValueNetWithParameters

policyValueNetWithParameters :: PVN.PolicyValueNet -> Build (Digest, Digest)
policyValueNetWithParameters (PVN.PolicyValueNet actual actions observations) = do
  p <- parameters actual
  a <- intValue actions
  o <- intValue observations
  root <- emit NPVN [VRef p, a, o]
  pure (root, p)

-- Cabal supplies this exact dependency version macro. No received metadata is
-- relabelled compiled, and no System.Random.Internal/SplitMix/Show is imported.
-- Prospective registration requires random>=1.3 and its public SeedGen API.
generator :: Random.StdGen -> Build Digest
generator actual = case NE.toList (Random.toSeed64 actual) of
  [first, second] ->
    emit
      NGeneratorState
      [ VText "stdgen-seedgen-toSeed64-v1"
      , VText (Text.pack VERSION_random)
      , VWord 2
      , VList [VWord first, VWord second]
      ]
  _ -> dataEither (Left (Malformed "public StdGen SeedGen observation is not exactly two words"))

discreteReplay :: Dqn.Transition -> Build Digest
discreteReplay (Dqn.Transition observation action reward nextObservation done) =
  discreteTuple (observation, action, reward, nextObservation, done)

discreteTuple :: (Vector Double, Int, Double, Vector Double, Bool) -> Build Digest
discreteTuple (observation, action, reward, nextObservation, done) = do
  before <- tensor observation
  after <- tensor nextObservation
  selected <- intValue action
  emit NDiscreteReplay [VRef before, selected, bitValue reward, VRef after, VBool done]

continuousReplay :: Continuous.ContTransition -> Build Digest
continuousReplay (Continuous.ContTransition observation action reward nextObservation done) = do
  before <- tensor observation
  after <- tensor nextObservation
  emit NContinuousReplay [VRef before, bitValue action, bitValue reward, VRef after, VBool done]

gameState :: Game.GameState -> Build Digest
gameState (Game.GameState game moves currentPlayer) = do
  name <- textValue GeneralTextBytes game
  history <- scalarSequenceWith ScalarInt intValue moves
  player <- intValue currentPlayer
  emit NGameState [name, VRef history, player]
