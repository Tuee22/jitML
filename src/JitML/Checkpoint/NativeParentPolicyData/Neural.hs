{-# LANGUAGE OverloadedStrings #-}

-- | Public raw numerical DATA reconstruction; no low Pending/capsule factory.
module JitML.Checkpoint.NativeParentPolicyData.Neural (neuralReturned) where

import Data.Text (Text)
import JitML.Checkpoint.NativeParentPolicyData.Node
import JitML.Checkpoint.NativePhase.Types
import JitML.RL.Algorithms.Common qualified as Common
import JitML.RL.Algorithms.ContinuousTrainer qualified as Continuous
import JitML.RL.Algorithms.DqnTrainer qualified as Dqn
import JitML.RL.Algorithms.HerTrainer qualified as Her
import JitML.RL.Algorithms.PpoTrainer qualified as Ppo
import JitML.RL.Algorithms.QrDqnTrainer qualified as Qr
import JitML.RL.TrainerConfiguration qualified as Config
import JitML.RL.TrainerObservation qualified as Observation

neuralReturned
  :: Text
  -> Config.NeuralTrainerConfiguration
  -> Digest
  -> Digest
  -> Digest
  -> Decode Observation.ReturnedPolicy
neuralReturned transport config configRoot initialRoot root = do
  actual <- fields NRawNeural root
  case actual of
    [ VWord family
      , VText compiled
      , VRef expectedConfig
      , VRef expectedInitial
      , VRef actualConfig
      , VRef actualInitial
      , VRef final
      , VRef stats
      , VWord transitions
      , VWord updates
      ] -> do
        require
          ( compiled == transport
              && expectedConfig == configRoot
              && actualConfig == configRoot
              && expectedInitial == initialRoot
              && actualInitial == initialRoot
          )
          "parent neural raw expected/actual recipe or effective initial binding differs"
        first <- parameters initialRoot
        last_ <- parameters final
        let statCap =
              1 + case config of
                Config.OnPolicyConfiguration c -> toInteger (Ppo.ppoNumIterations c)
                Config.DqnConfiguration c -> toInteger (Dqn.dqnNumSteps c)
                Config.QrDqnConfiguration c -> toInteger (Qr.qrNumSteps c)
                Config.ContinuousConfiguration c -> toInteger (Continuous.ctNumSteps c)
                Config.HerConfiguration c -> toInteger (Her.herEpisodes c)
        roots <-
          referenceData
            (AliasElement NeuralStatAlias)
            (min statCap (nativePhaseLimit PerSequenceElements))
            stats
        counters <-
          either reject pure (Common.mkObservedTrainerCounters (toInteger transitions) (toInteger updates))
        case (family, config) of
          (0, Config.OnPolicyConfiguration c) ->
            Observation.ReturnedOnPolicy . (\s -> Common.RawTrainerResult first last_ s counters c)
              <$> traverse ppoStat roots
          (1, Config.DqnConfiguration c) ->
            Observation.ReturnedDqn . (\s -> Common.RawTrainerResult first last_ s counters c)
              <$> traverse dqnStat roots
          (2, Config.QrDqnConfiguration c) ->
            Observation.ReturnedQrDqn . (\s -> Common.RawTrainerResult first last_ s counters c)
              <$> traverse qrStat roots
          (3, Config.ContinuousConfiguration c) ->
            Observation.ReturnedContinuous . (\s -> Common.RawTrainerResult first last_ s counters c)
              <$> traverse continuousStat roots
          (4, Config.HerConfiguration c) ->
            Observation.ReturnedHer . (\s -> Common.RawTrainerResult first last_ s counters c)
              <$> traverse herStat roots
          _ -> reject "parent raw neural family differs from the actual canonical typed recipe"
    _ -> reject "parent raw neural fields differ"
 where
  ppoStat digest = do
    actual <- fields NPpoStat digest
    case actual of
      [index, mean, median, maximum_, episodes] ->
        Ppo.PpoIterationStat <$> int index <*> bits mean <*> bits median <*> bits maximum_ <*> int episodes
      _ -> reject "parent on-policy raw statistic differs"
  dqnStat digest = do
    actual <- fields NDqnStat digest
    case actual of
      [step, episodes, mean, last_] -> Dqn.DqnIterationStat <$> int step <*> int episodes <*> bits mean <*> bits last_
      _ -> reject "parent DQN raw statistic differs"
  qrStat digest = do
    actual <- fields NQrStat digest
    case actual of
      [step, episodes, mean] -> Qr.QrDqnIterationStat <$> int step <*> int episodes <*> bits mean
      _ -> reject "parent QR-DQN raw statistic differs"
  continuousStat digest = do
    actual <- fields NContinuousStat digest
    case actual of
      [step, episodes, mean, last_] -> Continuous.ContinuousIterationStat <$> int step <*> int episodes <*> bits mean <*> bits last_
      _ -> reject "parent continuous raw statistic differs"
  herStat digest = do
    actual <- fields NHerStat digest
    case actual of
      [episode, success] -> Her.HerIterationStat <$> int episode <*> bits success
      _ -> reject "parent HER raw statistic differs"
