{-# LANGUAGE OverloadedStrings #-}

module JitML.Prerequisite.Registry
  ( NodeId (..)
  , Prerequisite (..)
  , prerequisiteRegistry
  , renderPrerequisiteRegistry
  , scopeRootNodeId
  , syntheticMissingPrerequisite
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Prerequisite.Nodes.Cluster (clusterPrerequisites)
import JitML.Prerequisite.Nodes.Container (containerPrerequisites)
import JitML.Prerequisite.Nodes.Toolchain (toolchainPrerequisites)
import JitML.Prerequisite.Types (NodeId (..), Prerequisite (..))

prerequisiteRegistry :: [Prerequisite]
prerequisiteRegistry =
  toolchainPrerequisites
    <> containerPrerequisites
    <> clusterPrerequisites

scopeRootNodeId :: Text -> Maybe NodeId
scopeRootNodeId "toolchain" = Just (NodeId "toolchain")
scopeRootNodeId "container" = Just (NodeId "container")
scopeRootNodeId "cluster" = Just (NodeId "cluster")
scopeRootNodeId _ = Nothing

syntheticMissingPrerequisite :: Prerequisite
syntheticMissingPrerequisite =
  Prerequisite
    { nodeId = NodeId "synthetic.missing"
    , nodeDescription = "Synthetic missing prerequisite for validation."
    , remedyHint = Just "create the synthetic prerequisite fixture"
    , dependsOn = []
    , remediation = Nothing
    , checkNode = pure False
    }

renderPrerequisiteRegistry :: [Prerequisite] -> Text
renderPrerequisiteRegistry [] =
  Text.unlines
    [ "Prerequisites:"
    , "  (none registered yet)"
    ]
renderPrerequisiteRegistry prerequisites =
  Text.unlines ("Prerequisites:" : fmap renderPrerequisite prerequisites)

renderPrerequisite :: Prerequisite -> Text
renderPrerequisite prerequisite =
  "  "
    <> unNodeId (nodeId prerequisite)
    <> " - "
    <> nodeDescription prerequisite
    <> dependencyText
 where
  dependencyText
    | null (dependsOn prerequisite) = ""
    | otherwise =
        " (depends on: "
          <> Text.intercalate ", " (fmap unNodeId (dependsOn prerequisite))
          <> ")"
