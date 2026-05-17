module JitML.RL.Algorithms.Registry
  ( algorithmModuleRegistry
  , moduleFor
  , offPolicyModules
  , onPolicyModules
  , specialisedModules
  )
where

import Data.Text (Text)

import JitML.RL.Algorithms (RLAlgorithm (..))
import JitML.RL.Algorithms.A2c (a2cModule)
import JitML.RL.Algorithms.Ars (arsModule)
import JitML.RL.Algorithms.Common (AlgorithmModule (..))
import JitML.RL.Algorithms.CrossQ (crossQModule)
import JitML.RL.Algorithms.Ddpg (ddpgModule)
import JitML.RL.Algorithms.Dqn (dqnModule)
import JitML.RL.Algorithms.Her (herModule)
import JitML.RL.Algorithms.MaskablePpo (maskablePpoModule)
import JitML.RL.Algorithms.Ppo (ppoModule)
import JitML.RL.Algorithms.QrDqn (qrDqnModule)
import JitML.RL.Algorithms.RecurrentPpo (recurrentPpoModule)
import JitML.RL.Algorithms.Sac (sacModule)
import JitML.RL.Algorithms.Td3 (td3Module)
import JitML.RL.Algorithms.Tqc (tqcModule)
import JitML.RL.Algorithms.Trpo (trpoModule)

algorithmModuleRegistry :: [AlgorithmModule]
algorithmModuleRegistry =
  onPolicyModules <> offPolicyModules <> specialisedModules

onPolicyModules :: [AlgorithmModule]
onPolicyModules =
  [ ppoModule
  , a2cModule
  , trpoModule
  , maskablePpoModule
  , recurrentPpoModule
  ]

offPolicyModules :: [AlgorithmModule]
offPolicyModules =
  [ dqnModule
  , qrDqnModule
  , ddpgModule
  , td3Module
  , sacModule
  ]

specialisedModules :: [AlgorithmModule]
specialisedModules =
  [ crossQModule
  , tqcModule
  , arsModule
  , herModule
  ]

moduleFor :: Text -> Maybe AlgorithmModule
moduleFor name =
  case [m | m <- algorithmModuleRegistry, algorithmName (moduleAlgorithm m) == name] of
    (first : _) -> Just first
    [] -> Nothing
