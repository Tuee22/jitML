{-# LANGUAGE OverloadedStrings #-}

module JitML.Prerequisite.Nodes.Common
    ( checkAnyExecutable
    , commandPrerequisite
    , homebrewPackagePrerequisite
    , purePrerequisite
    )
where

import Data.Maybe (isJust)
import Data.Text (Text)
import System.Directory (findExecutable)

import JitML.Prerequisite.Types (NodeId, Prerequisite (..), PrerequisiteRemediation (..))
import JitML.Sub.Subprocess (subprocess)

commandPrerequisite :: NodeId -> Text -> String -> Text -> [NodeId] -> Prerequisite
commandPrerequisite node description command remedy dependencies =
    Prerequisite
        { nodeId = node
        , nodeDescription = description
        , remedyHint = Just remedy
        , dependsOn = dependencies
        , remediation = Nothing
        , checkNode = checkAnyExecutable [command]
        }

homebrewPackagePrerequisite :: NodeId -> Text -> String -> Text -> [NodeId] -> Prerequisite
homebrewPackagePrerequisite node description command packageName dependencies =
    Prerequisite
        { nodeId = node
        , nodeDescription = description
        , remedyHint = Just ("brew install " <> packageName)
        , dependsOn = dependencies
        , remediation =
            Just
                PrerequisiteRemediation
                    { remediationDescription = "Install Homebrew package " <> packageName <> "."
                    , remediationCommand = subprocess "brew" ["install", packageName]
                    }
        , checkNode = checkAnyExecutable [command]
        }

purePrerequisite :: NodeId -> Text -> [NodeId] -> Prerequisite
purePrerequisite node description dependencies =
    Prerequisite
        { nodeId = node
        , nodeDescription = description
        , remedyHint = Nothing
        , dependsOn = dependencies
        , remediation = Nothing
        , checkNode = pure True
        }

checkAnyExecutable :: [String] -> IO Bool
checkAnyExecutable commands =
    any isJust <$> traverse findExecutable commands
