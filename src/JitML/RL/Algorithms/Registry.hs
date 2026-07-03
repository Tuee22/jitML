{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.Algorithms.Registry
  ( algorithmModuleRegistry
  , moduleFor
  , offPolicyModules
  , onPolicyModules
  , specialisedModules
  , updateContractFor
  , validateAlgorithmModuleRegistry
  )
where

import Data.List qualified as List
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.RL.Algorithms (RLAlgorithm (..))
import JitML.RL.Algorithms.A2c (a2cModule)
import JitML.RL.Algorithms.Ars (arsModule)
import JitML.RL.Algorithms.Common
  ( AlgorithmModule (..)
  , AlgorithmUpdateContract (..)
  )
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

updateContractFor :: Text -> Maybe AlgorithmUpdateContract
updateContractFor name =
  moduleUpdateContract <$> moduleFor name

validateAlgorithmModuleRegistry :: [AlgorithmModule] -> [Text]
validateAlgorithmModuleRegistry modules =
  duplicateAlgorithmErrors
    <> duplicateUpdateIdentityErrors
    <> missingContractErrors
 where
  algorithmNames = fmap (algorithmName . moduleAlgorithm) modules
  updateIdentities = fmap (updateIdentity . moduleUpdateContract) modules
  duplicateAlgorithmErrors =
    [ "duplicate algorithm module: " <> name
    | name <- duplicates algorithmNames
    ]
  duplicateUpdateIdentityErrors =
    [ "duplicate algorithm update identity: " <> identity
    | identity <- duplicates updateIdentities
    ]
  missingContractErrors =
    [ algorithmName (moduleAlgorithm m) <> " has incomplete update contract"
    | m <- modules
    , contractIncomplete (moduleUpdateContract m)
    ]
  contractIncomplete contract =
    Text.null (Text.strip (updateIdentity contract))
      || Text.null (Text.strip (trainerEntryPoint contract))
      || Text.null (Text.strip (rolloutSurface contract))
      || Text.null (Text.strip (learnedArtifact contract))
      || null (updateFeatures contract)

duplicates :: (Ord a) => [a] -> [a]
duplicates values =
  [ value
  | value : _ : _ <- List.group (List.sort values)
  ]
