module JitML.Prerequisite.Types
  ( NodeId (..)
  , Prerequisite (..)
  , PrerequisiteRemediation (..)
  )
where

import Data.Text (Text)

import JitML.Sub.Subprocess (Subprocess)

newtype NodeId = NodeId
  { unNodeId :: Text
  }
  deriving stock (Eq, Ord, Show)

data Prerequisite = Prerequisite
  { nodeId :: NodeId
  , nodeDescription :: Text
  , remedyHint :: Maybe Text
  , dependsOn :: [NodeId]
  , remediation :: Maybe PrerequisiteRemediation
  , checkNode :: IO Bool
  }

data PrerequisiteRemediation = PrerequisiteRemediation
  { remediationDescription :: Text
  , remediationCommand :: Subprocess
  }
  deriving stock (Eq, Show)
