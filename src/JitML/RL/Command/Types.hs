module JitML.RL.Command.Types
  ( RlCommandRuntime (..)
  , RlWorkerServices (..)
  )
where

import Data.Text (Text)
import Data.Word (Word64)

import JitML.CLI.Parser (ParsedOption)
import JitML.Env.Env (App)
import JitML.Proto.Rl qualified as ProtoRl
import JitML.Service.PulsarWebSocketSubprocess qualified as PulsarWebSocketSubprocess
import JitML.Service.Retry (ServiceError)
import JitML.Substrate (Substrate)

data RlWorkerServices = RlWorkerServices
  { rlWorkerServiceSubstrate :: Substrate
  , rlWorkerServicePulsarSettings :: PulsarWebSocketSubprocess.PulsarWebSocketSettings
  }

data RlCommandRuntime = RlCommandRuntime
  { rlCommandWorkerSubstrateBase :: App Substrate
  , rlCommandWorkerExperimentHash :: App (Maybe Text)
  , rlCommandRunCheckpointEval :: Text -> [ParsedOption] -> App ()
  , rlCommandWorkerBrokerTarget
      :: App (Maybe (Substrate, PulsarWebSocketSubprocess.PulsarWebSocketSettings))
  , rlCommandAlphaZeroWorkerServices :: App (Maybe RlWorkerServices)
  , rlCommandPublishEvent
      :: PulsarWebSocketSubprocess.PulsarWebSocketSettings
      -> Substrate
      -> ProtoRl.RlEvent
      -> IO (Either ServiceError ())
  , rlCommandTimestampNs :: IO Word64
  }
