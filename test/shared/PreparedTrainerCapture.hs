{-# LANGUAGE OverloadedStrings #-}

-- | Lossless bounded numerical diagnostic shared by the frozen OLD capture
-- driver and the proposed prepared-state controls. No device/provider witness,
-- canonical run, convergence assertion or origin is created here.
module PreparedTrainerCapture
  ( captureLegacyRuns
  , ppoConfig
  , dqnConfig
  , qrConfig
  , herConfig
  , recordingDevice
  , paramsValue
  , rawValue
  , ppoStatValue
  , dqnStatValue
  , qrStatValue
  , herStatValue
  ) where

import Data.Aeson (Value, object, (.=))
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)
import GHC.Float (castDoubleToWord64)

import JitML.Numerics.Mlp qualified as Mlp
import JitML.Numerics.MlpDevice (MlpDevice (..), pureReferenceMlpDevice)
import JitML.RL.Algorithms.Common qualified as Common
import JitML.RL.Algorithms.DqnTrainer qualified as Dqn
import JitML.RL.Algorithms.HerTrainer qualified as Her
import JitML.RL.Algorithms.PpoTrainer qualified as Ppo
import JitML.RL.Algorithms.QrDqnTrainer qualified as Qr
import JitML.RL.Simulator qualified as Sim

ppoConfig :: Ppo.OnPolicyVariant -> Ppo.PpoTrainConfig
ppoConfig variant =
  Ppo.defaultPpoTrainConfig
    { Ppo.ppoVariant = variant
    , Ppo.ppoHiddenUnits = 2
    , Ppo.ppoNumIterations = 1
    , Ppo.ppoRolloutSteps = 4
    , Ppo.ppoVectorEnvCount = 2
    , Ppo.ppoMaxEpisodeSteps = 2
    , Ppo.ppoEpochsPerUpdate = 1
    , Ppo.ppoMiniBatchSize = 2
    , Ppo.ppoTrpoCgIterations = 2
    , Ppo.ppoTrpoBacktrackIterations = 2
    , Ppo.ppoTrpoCriticUpdates = 1
    , Ppo.ppoRecurrentStateSize = 2
    }

dqnConfig :: Dqn.DqnTrainConfig
dqnConfig =
  Dqn.defaultDqnTrainConfig
    { Dqn.dqnHiddenUnits = 2
    , Dqn.dqnNumSteps = 4
    , Dqn.dqnReplayCapacity = 16
    , Dqn.dqnBatchSize = 2
    , Dqn.dqnTrainStart = 0
    , Dqn.dqnUpdateFrequency = 1
    , Dqn.dqnTargetUpdateInterval = 2
    , Dqn.dqnStatInterval = 1
    , Dqn.dqnMaxEpisodeSteps = 2
    , Dqn.dqnEpsilonStart = 0
    , Dqn.dqnEpsilonEnd = 0
    , Dqn.dqnUseDouble = True
    }

qrConfig :: Qr.QrDqnTrainConfig
qrConfig =
  Qr.defaultQrDqnTrainConfig
    { Qr.qrHiddenUnits = 2
    , Qr.qrNumQuantiles = 2
    , Qr.qrNumSteps = 4
    , Qr.qrReplayCapacity = 16
    , Qr.qrBatchSize = 2
    , Qr.qrTrainStart = 0
    , Qr.qrUpdateFrequency = 1
    , Qr.qrTargetUpdateInterval = 2
    , Qr.qrStatInterval = 1
    , Qr.qrMaxEpisodeSteps = 2
    , Qr.qrEpsilonStart = 0
    , Qr.qrEpsilonEnd = 0
    }

herConfig :: Her.HerTrainConfig
herConfig =
  Her.defaultHerTrainConfig
    { Her.herHiddenUnits = 2
    , Her.herNumBits = 2
    , Her.herEpisodes = 3
    , Her.herReplayCapacity = 16
    , Her.herBatchSize = 1
    , Her.herTargetUpdateInterval = 2
    , Her.herStatInterval = 1
    , Her.herUpdatesPerEpisode = 1
    , Her.herEpsilon = 0
    }

vectorValue :: VU.Vector Double -> [Word64]
vectorValue = fmap castDoubleToWord64 . VU.toList

paramsValue :: Mlp.MlpParams -> Value
paramsValue params =
  object
    [ "shape" .= [Mlp.mlpInputs shape, Mlp.mlpHidden shape, Mlp.mlpOutputs shape]
    , "w1_f64_bits" .= vectorValue (Mlp.paramW1 params)
    , "b1_f64_bits" .= vectorValue (Mlp.paramB1 params)
    , "w2_f64_bits" .= vectorValue (Mlp.paramW2 params)
    , "b2_f64_bits" .= vectorValue (Mlp.paramB2 params)
    ]
 where
  shape = Mlp.paramShape params

gradientValue :: Mlp.MlpGradient -> Value
gradientValue gradient =
  object
    [ "w1_f64_bits" .= vectorValue (Mlp.gradW1 gradient)
    , "b1_f64_bits" .= vectorValue (Mlp.gradB1 gradient)
    , "w2_f64_bits" .= vectorValue (Mlp.gradW2 gradient)
    , "b2_f64_bits" .= vectorValue (Mlp.gradB2 gradient)
    ]

forwardValue :: Mlp.MlpForward -> Value
forwardValue forward =
  object
    [ "input_f64_bits" .= vectorValue (Mlp.forwardInput forward)
    , "hidden_pre_f64_bits" .= vectorValue (Mlp.forwardHiddenPre forward)
    , "hidden_act_f64_bits" .= vectorValue (Mlp.forwardHiddenAct forward)
    , "output_f64_bits" .= vectorValue (Mlp.forwardOutput forward)
    ]

resultValue :: (a -> Value) -> Either Text a -> Value
resultValue render result = case result of
  Left err -> object ["left" .= err]
  Right value -> object ["right" .= render value]

-- Every actual argument/result is recorded at its real callback boundary.
-- Delegation is the explicitly non-provider pure reference numerical device.
-- Keep strict pair-pattern demand in lossless callback capture.
{- HLINT ignore recordingDevice "Use bimap" -}
{- HLINT ignore recordingDevice "Use both" -}
recordingDevice :: IORef [Value] -> MlpDevice
recordingDevice trace =
  pureReferenceMlpDevice
    { mlpdForward = \params input -> do
        note "forward-start" (object ["params" .= paramsValue params, "input" .= vectorValue input])
        result <- mlpdForward pureReferenceMlpDevice params input
        note "forward-return" (resultValue forwardValue result)
        pure result
    , mlpdBackward = \params forward upstream -> do
        note
          "backward-start"
          ( object
              [ "params" .= paramsValue params
              , "forward" .= forwardValue forward
              , "upstream" .= vectorValue upstream
              ]
          )
        result <- mlpdBackward pureReferenceMlpDevice params forward upstream
        note "backward-return" (resultValue gradientValue result)
        pure result
    , mlpdForwardBatch = \params inputs -> do
        note
          "batch-forward-start"
          (object ["params" .= paramsValue params, "inputs" .= fmap vectorValue inputs])
        result <- mlpdForwardBatch pureReferenceMlpDevice params inputs
        note "batch-forward-return" (resultValue (object . pure . ("outputs" .=) . fmap vectorValue) result)
        pure result
    , mlpdBatchGradient = \params pairs -> do
        note
          "batch-gradient-start"
          ( object
              [ "params" .= paramsValue params
              , "pairs" .= fmap (\(input, upstream) -> (vectorValue input, vectorValue upstream)) pairs
              ]
          )
        result <- mlpdBatchGradient pureReferenceMlpDevice params pairs
        note "batch-gradient-return" (resultValue gradientValue result)
        pure result
    , mlpdInputGradientBatch = \params pairs -> do
        note
          "input-gradient-start"
          ( object
              [ "params" .= paramsValue params
              , "pairs" .= fmap (\(input, upstream) -> (vectorValue input, vectorValue upstream)) pairs
              ]
          )
        result <- mlpdInputGradientBatch pureReferenceMlpDevice params pairs
        note
          "input-gradient-return"
          (resultValue (object . pure . ("outputs" .=) . fmap vectorValue) result)
        pure result
    , mlpdExecutionWitness = do
        note "witness" (object [])
        pure (Right Nothing)
    }
 where
  note operation value = modifyIORef' trace (object ["operation" .= (operation :: Text), "value" .= value] :)

rawValue
  :: (Show config) => (stat -> Value) -> Common.RawTrainerResult Mlp.MlpParams stat config -> Value
rawValue renderStat result =
  object
    [ "initial" .= paramsValue (Common.rawTrainerInitialParams result)
    , "final" .= paramsValue (Common.rawTrainerFinalParams result)
    , "statistics" .= fmap renderStat (Common.rawTrainerStats result)
    , "transitions" .= Common.observedEnvironmentTransitionCount (Common.rawTrainerCounters result)
    , "updates" .= Common.observedOptimizerUpdateCount (Common.rawTrainerCounters result)
    , "actual_config_show" .= show (Common.rawTrainerConfig result)
    ]

ppoStatValue :: Ppo.PpoIterationStat -> Value
ppoStatValue stat =
  object
    [ "index" .= Ppo.iterIndex stat
    , "episodes" .= Ppo.iterEpisodes stat
    , "mean_f64_bits" .= castDoubleToWord64 (Ppo.iterMeanReward stat)
    , "median_f64_bits" .= castDoubleToWord64 (Ppo.iterMedianReward stat)
    , "max_f64_bits" .= castDoubleToWord64 (Ppo.iterMaxReward stat)
    ]
dqnStatValue :: Dqn.DqnIterationStat -> Value
dqnStatValue stat =
  object
    [ "step" .= Dqn.dqnIterStep stat
    , "episodes" .= Dqn.dqnIterEpisodes stat
    , "mean_f64_bits" .= castDoubleToWord64 (Dqn.dqnIterMeanReward stat)
    , "last_reward_f64_bits" .= castDoubleToWord64 (Dqn.dqnIterLastEpisodeReward stat)
    ]
qrStatValue :: Qr.QrDqnIterationStat -> Value
qrStatValue stat =
  object
    [ "step" .= Qr.qrIterStep stat
    , "episodes" .= Qr.qrIterEpisodes stat
    , "mean_f64_bits" .= castDoubleToWord64 (Qr.qrIterMeanReward stat)
    ]
herStatValue :: Her.HerIterationStat -> Value
herStatValue stat =
  object
    [ "episode" .= Her.herIterEpisode stat
    , "success_f64_bits" .= castDoubleToWord64 (Her.herIterSuccessRate stat)
    ]

captureLegacyRuns :: IO [(Text, Value)]
captureLegacyRuns =
  sequence
    [ pureCapture "ppo-pure" ppoStatValue (Ppo.trainPpoOnCartpoleRaw (ppoConfig Ppo.VariantPPO))
    , deviceCapture
        "ppo-device"
        ppoStatValue
        ( \device -> Ppo.trainOnPolicyOnDeviceWithEnvironmentRaw device env Ppo.VariantPPO (ppoConfig Ppo.VariantPPO)
        )
    , deviceCapture
        "trpo-device"
        ppoStatValue
        ( \device ->
            Ppo.trainOnPolicyOnDeviceWithEnvironmentRaw device env Ppo.VariantTRPO (ppoConfig Ppo.VariantTRPO)
        )
    , deviceCapture
        "recurrent-device"
        ppoStatValue
        ( \device ->
            Ppo.trainOnPolicyOnDeviceWithEnvironmentRaw
              device
              env
              Ppo.VariantRecurrentPPO
              (ppoConfig Ppo.VariantRecurrentPPO)
        )
    , pureCapture "dqn-pure" dqnStatValue (Dqn.trainDqnOnCartpoleRaw dqnConfig)
    , deviceCapture
        "dqn-device"
        dqnStatValue
        (\device -> Dqn.trainDqnOnDeviceWithEnvironmentRaw device env dqnConfig)
    , pureCapture "qr-pure" qrStatValue (Qr.trainQrDqnOnCartpoleRaw qrConfig)
    , deviceCapture
        "qr-device"
        qrStatValue
        (\device -> Qr.trainQrDqnOnDeviceWithEnvironmentRaw device env qrConfig)
    , pureCapture "her-pure" herStatValue (Her.trainHerOnBitFlipRaw herConfig)
    , deviceCapture "her-device" herStatValue (`Her.trainHerOnDeviceRaw` herConfig)
    ]
 where
  env = Sim.SomeSimulatedEnvironment Sim.cartPoleEnvironment
  pureCapture
    :: (Show config)
    => Text
    -> (stat -> Value)
    -> IO (Common.RawTrainerResult Mlp.MlpParams stat config)
    -> IO (Text, Value)
  pureCapture name render action = do
    result <- action
    pure (name, object ["raw" .= rawValue render result, "callbacks" .= ([] :: [Value])])
  deviceCapture
    :: (Show config)
    => Text
    -> (stat -> Value)
    -> (MlpDevice -> IO (Either Text (Common.RawTrainerResult Mlp.MlpParams stat config)))
    -> IO (Text, Value)
  deviceCapture name render run = do
    trace <- newIORef []
    result <- run (recordingDevice trace)
    calls <- reverse <$> readIORef trace
    pure (name, object ["result" .= resultValue (rawValue render) result, "callbacks" .= calls])
