{-# LANGUAGE RankNTypes #-}

-- | Actual public getters only; private simulator state has explicit omission
-- markers. No state codec, initializer or restored continuation is constructed.
module JitML.Checkpoint.NativePhase.Projection.Snapshots
  ( neuralSnapshot
  , ppoSnapshot
  , dqnSnapshot
  , qrSnapshot
  , continuousSnapshot
  , herSnapshot
  , arsSnapshot
  , alphaZeroSnapshot
  ) where

import JitML.Checkpoint.NativePhase.Projection.Build
import JitML.Checkpoint.NativePhase.Projection.Values
import JitML.Checkpoint.NativePhase.Types
import JitML.RL.Algorithms.ArsTrainer qualified as Ars
import JitML.RL.Algorithms.ContinuousTrainer qualified as Continuous
import JitML.RL.Algorithms.DqnTrainer qualified as Dqn
import JitML.RL.Algorithms.HerTrainer qualified as Her
import JitML.RL.Algorithms.PpoTrainer qualified as Ppo
import JitML.RL.Algorithms.QrDqnTrainer qualified as Qr
import JitML.RL.AlphaZero.PreparedTrainer qualified as AZ
import JitML.RL.PreparedNeuralAttempt qualified as Low

neuralSnapshot :: Low.NeuralSnapshot -> Build Digest
neuralSnapshot = Low.foldNeuralSnapshot ppoSnapshot dqnSnapshot qrSnapshot continuousSnapshot herSnapshot

ppoSnapshot :: Ppo.PpoPreparedSnapshot state -> Build Digest
ppoSnapshot actual = do
  field0 <- VRef <$> ppoConfig (Ppo.ppoPreparedConfig actual)
  field1 <- VRef <$> parameters (Ppo.ppoPreparedInitialParams actual)
  field2 <- VRef <$> adam (Ppo.ppoPreparedAdam actual)
  field3 <- VRef <$> generator (Ppo.ppoPreparedGenerator actual)
  let field4 = VList [VWord (case Ppo.ppoPreparedSingleState actual of Nothing -> 0; Just _ -> 1)]
  field5 <-
    VRef <$> scalarSequenceWith ScalarSlotSummary slotValue (Ppo.ppoPreparedVectorSlots actual)
  field6 <-
    VRef <$> referenceSequence (AliasElement TensorAlias) frameTensor (Ppo.ppoPreparedFrames actual)
  field7 <-
    VRef <$> scalarSequenceWith ScalarCountTriple countValue (Ppo.ppoPreparedCountEntries actual)
  field8 <-
    VRef <$> referenceSequence (RefElement NPpoStat) ppoStat (Ppo.ppoPreparedStatistics actual)
  field9 <- intValue (Ppo.ppoPreparedActorSteps actual)
  field10 <- integerValue (Ppo.ppoPreparedTransitions actual)
  field11 <- textValue GeneralTextBytes (Ppo.ppoPreparedEnvironmentName actual)
  field12 <- intValue (Ppo.ppoPreparedObservationWidth actual)
  field13 <- intValue (Ppo.ppoPreparedActionCount actual)
  emit
    NPpoSnapshot
    [ field0
    , field1
    , field2
    , field3
    , field4
    , field5
    , field6
    , field7
    , field8
    , field9
    , field10
    , field11
    , field12
    , field13
    ]

dqnSnapshot :: Dqn.DqnPreparedSnapshot state -> Build Digest
dqnSnapshot actual = do
  field0 <- VRef <$> dqnConfig (Dqn.dqnPreparedConfig actual)
  field1 <- VRef <$> parameters (Dqn.dqnPreparedInitialParams actual)
  field2 <- VRef <$> parameters (Dqn.dqnPreparedOnlineParams actual)
  field3 <- VRef <$> parameters (Dqn.dqnPreparedTargetParams actual)
  field4 <- VRef <$> adam (Dqn.dqnPreparedAdam actual)
  field5 <- VRef <$> generator (Dqn.dqnPreparedGenerator actual)
  field6 <-
    VRef
      <$> referenceSequence (RefElement NDiscreteReplay) discreteReplay (Dqn.dqnPreparedReplay actual)
  field7 <- intValue (Dqn.dqnPreparedStep actual)
  let field8 = VList [VWord 0] -- dqnPreparedState: private state deliberately not forced/captured.
  field9 <- intValue (Dqn.dqnPreparedEpisodeLength actual)
  let field10 = bitValue (Dqn.dqnPreparedEpisodeReturn actual)
  field11 <- VRef <$> scalarSequence ScalarBits (map bitValue (Dqn.dqnPreparedRecentReturns actual))
  field12 <-
    VRef <$> referenceSequence (RefElement NDqnStat) dqnStat (Dqn.dqnPreparedStatistics actual)
  field13 <- textValue GeneralTextBytes (Dqn.dqnPreparedEnvironmentName actual)
  field14 <- intValue (Dqn.dqnPreparedObservationWidth actual)
  field15 <- intValue (Dqn.dqnPreparedActionCount actual)
  field16 <- VRef <$> frameTensor (Dqn.dqnPreparedFrame actual)
  emit
    NDqnSnapshot
    [ field0
    , field1
    , field2
    , field3
    , field4
    , field5
    , field6
    , field7
    , field8
    , field9
    , field10
    , field11
    , field12
    , field13
    , field14
    , field15
    , field16
    ]

qrSnapshot :: Qr.QrDqnPreparedSnapshot state -> Build Digest
qrSnapshot actual = do
  field0 <- VRef <$> qrConfig (Qr.qrDqnPreparedConfig actual)
  field1 <- VRef <$> parameters (Qr.qrDqnPreparedInitialParams actual)
  field2 <- VRef <$> parameters (Qr.qrDqnPreparedOnlineParams actual)
  field3 <- VRef <$> parameters (Qr.qrDqnPreparedTargetParams actual)
  field4 <- VRef <$> adam (Qr.qrDqnPreparedAdam actual)
  field5 <- VRef <$> generator (Qr.qrDqnPreparedGenerator actual)
  field6 <-
    VRef
      <$> referenceSequence (RefElement NDiscreteReplay) discreteTuple (Qr.qrDqnPreparedReplay actual)
  field7 <- intValue (Qr.qrDqnPreparedStep actual)
  let field8 = VList [VWord 0] -- qrDqnPreparedState: private state deliberately not forced/captured.
  field9 <- intValue (Qr.qrDqnPreparedEpisodeLength actual)
  let field10 = bitValue (Qr.qrDqnPreparedEpisodeReturn actual)
  field11 <- VRef <$> scalarSequence ScalarBits (map bitValue (Qr.qrDqnPreparedRecentReturns actual))
  field12 <-
    VRef <$> referenceSequence (RefElement NQrStat) qrStat (Qr.qrDqnPreparedStatistics actual)
  field13 <- textValue GeneralTextBytes (Qr.qrDqnPreparedEnvironmentName actual)
  field14 <- intValue (Qr.qrDqnPreparedObservationWidth actual)
  field15 <- intValue (Qr.qrDqnPreparedActionCount actual)
  field16 <- VRef <$> frameTensor (Qr.qrDqnPreparedFrame actual)
  emit
    NQrSnapshot
    [ field0
    , field1
    , field2
    , field3
    , field4
    , field5
    , field6
    , field7
    , field8
    , field9
    , field10
    , field11
    , field12
    , field13
    , field14
    , field15
    , field16
    ]

continuousSnapshot :: Continuous.ContinuousPreparedSnapshot state -> Build Digest
continuousSnapshot actual = do
  let field0 =
        VWord
          ( case Continuous.continuousPreparedStage actual of
              Continuous.ContinuousCold -> 0
              Continuous.ContinuousEffective -> 1
          )
  field1 <- VRef <$> continuousConfig (Continuous.continuousPreparedConfig actual)
  field2 <- VRef <$> parameters (Continuous.continuousPreparedColdActor actual)
  field3 <- VRef <$> parameters (Continuous.continuousPreparedActor actual)
  field4 <- VRef <$> parameters (Continuous.continuousPreparedCriticA actual)
  field5 <- VRef <$> parameters (Continuous.continuousPreparedCriticB actual)
  field6 <- optional parameters (Continuous.continuousPreparedTargetActor actual)
  field7 <- optional parameters (Continuous.continuousPreparedTargetCriticA actual)
  field8 <- optional parameters (Continuous.continuousPreparedTargetCriticB actual)
  let field9 = bitValue (Continuous.continuousPreparedLogAlpha actual)
  field10 <- VRef <$> adam (Continuous.continuousPreparedActorAdam actual)
  field11 <- VRef <$> adam (Continuous.continuousPreparedCriticAAdam actual)
  field12 <- VRef <$> adam (Continuous.continuousPreparedCriticBAdam actual)
  field13 <- optional adam (Continuous.continuousPreparedWarmAdam actual)
  field14 <- VRef <$> generator (Continuous.continuousPreparedGenerator actual)
  field15 <-
    VRef
      <$> referenceSequence
        (RefElement NContinuousReplay)
        continuousReplay
        (Continuous.continuousPreparedReplay actual)
  field16 <- intValue (Continuous.continuousPreparedStep actual)
  let field17 = VList [VWord 0] -- continuousPreparedState: private state deliberately not forced/captured.
  field18 <- intValue (Continuous.continuousPreparedEpisodeLength actual)
  let field19 = bitValue (Continuous.continuousPreparedEpisodeReturn actual)
  field20 <-
    VRef
      <$> scalarSequence ScalarBits (map bitValue (Continuous.continuousPreparedRecentReturns actual))
  field21 <-
    VRef
      <$> referenceSequence
        (RefElement NContinuousStat)
        continuousStat
        (Continuous.continuousPreparedStatistics actual)
  field22 <- textValue GeneralTextBytes (Continuous.continuousPreparedEnvironmentName actual)
  field23 <- VRef <$> frameListTensor (Continuous.continuousPreparedObservation actual)
  field24 <-
    VRef
      <$> scalarSequenceWith ScalarCountTriple countValue (Continuous.continuousPreparedCountEntries actual)
  field25 <- intValue (Continuous.continuousPreparedWarmUpdateCount actual)
  emit
    NContinuousSnapshot
    [ field0
    , field1
    , field2
    , field3
    , field4
    , field5
    , field6
    , field7
    , field8
    , field9
    , field10
    , field11
    , field12
    , field13
    , field14
    , field15
    , field16
    , field17
    , field18
    , field19
    , field20
    , field21
    , field22
    , field23
    , field24
    , field25
    ]

herSnapshot :: Her.HerPreparedSnapshot -> Build Digest
herSnapshot actual = do
  field0 <- VRef <$> herConfig (Her.herPreparedConfig actual)
  field1 <- VRef <$> parameters (Her.herPreparedInitialParams actual)
  field2 <- VRef <$> parameters (Her.herPreparedOnlineParams actual)
  field3 <- VRef <$> parameters (Her.herPreparedTargetParams actual)
  field4 <- VRef <$> adam (Her.herPreparedAdam actual)
  field5 <- VRef <$> generator (Her.herPreparedGenerator actual)
  field6 <-
    VRef <$> referenceSequence (RefElement NDiscreteReplay) discreteTuple (Her.herPreparedReplay actual)
  field7 <- intValue (Her.herPreparedEpisode actual)
  field8 <- integerValue (Her.herPreparedObservedTransitions actual)
  field9 <- VRef <$> scalarSequence ScalarBool (map VBool (Her.herPreparedRecentSuccesses actual))
  field10 <-
    VRef <$> referenceSequence (RefElement NHerStat) herStat (Her.herPreparedStatistics actual)
  emit
    NHerSnapshot
    [field0, field1, field2, field3, field4, field5, field6, field7, field8, field9, field10]

arsSnapshot :: Ars.ArsPreparedSnapshot -> Build Digest
arsSnapshot actual = do
  field0 <- VRef <$> arsConfig (Ars.arsPreparedConfig actual)
  field1 <- VRef <$> tensor (Ars.arsPreparedInitialParams actual)
  field2 <- VRef <$> generator (Ars.arsPreparedGenerator actual)
  field3 <- VRef <$> frameTensor (Ars.arsPreparedInitialFrame actual)
  emit NArsSnapshot [field0, field1, field2, field3]

alphaZeroSnapshot :: AZ.AlphaZeroPreparedSnapshot -> Build Digest
alphaZeroSnapshot actual = do
  field0 <- textValue GeneralTextBytes (AZ.alphaZeroPreparedGame actual)
  field1 <- VRef <$> gameState (AZ.alphaZeroPreparedInitialState actual)
  field2 <- VRef <$> policyValueNet (AZ.alphaZeroPreparedInitialNet actual)
  field3 <- VRef <$> adam (AZ.alphaZeroPreparedInitialAdam actual)
  field4 <- intValue (AZ.alphaZeroPreparedHiddenUnits actual)
  field5 <- intValue (AZ.alphaZeroPreparedSeed actual)
  field6 <- intValue (AZ.alphaZeroPreparedGenerationTarget actual)
  field7 <- intValue (AZ.alphaZeroPreparedGames actual)
  field8 <- intValue (AZ.alphaZeroPreparedSimulations actual)
  field9 <- intValue (AZ.alphaZeroPreparedMaxPlies actual)
  field10 <- intValue (AZ.alphaZeroPreparedUpdates actual)
  emit
    NAlphaZeroSnapshot
    [field0, field1, field2, field3, field4, field5, field6, field7, field8, field9, field10]

countValue :: ((Int, Int), Int) -> Build NodeValue
countValue ((stateHash, action), count) = VList <$> traverse intValue [stateHash, action, count]

slotValue :: (state, Double, Int) -> Build NodeValue
slotValue (_, reward, count) = do
  observedLength <- intValue count
  pure (VList [VList [VWord 0], bitValue reward, observedLength])
