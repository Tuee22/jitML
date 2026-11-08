{-# LANGUAGE OverloadedStrings #-}

module JitML.Prerequisite.Nodes.Cluster
  ( clusterPrerequisites
  )
where

import Data.List (isPrefixOf, isSuffixOf)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath ((</>))

import JitML.Cluster.ResourceRuntime (checkResourceEnvelopeIO)
import JitML.Cluster.Resources (loadClusterResourcesOrDefault)
import JitML.Prerequisite.Nodes.Common (homebrewPackagePrerequisite, purePrerequisite)
import JitML.Prerequisite.Types (NodeId (..), Prerequisite (..))

clusterPrerequisites :: [Prerequisite]
clusterPrerequisites =
  [ purePrerequisite
      (NodeId "cluster")
      "Cluster prerequisite root."
      [ NodeId "container"
      , NodeId "cluster.kind"
      , NodeId "cluster.kubectl"
      , NodeId "cluster.helm"
      , NodeId "cluster.kindest-node-pin"
      , NodeId "cluster.host-memory"
      ]
  , homebrewPackagePrerequisite (NodeId "cluster.kind") "kind is installed." "kind" "kind" []
  , homebrewPackagePrerequisite
      (NodeId "cluster.kubectl")
      "kubectl is installed."
      "kubectl"
      "kubernetes-cli"
      []
  , homebrewPackagePrerequisite (NodeId "cluster.helm") "helm is installed." "helm" "helm" []
  , kindestNodePinPrerequisite
  , clusterHostMemoryPrerequisite
  ]

kindestNodePinPrerequisite :: Prerequisite
kindestNodePinPrerequisite =
  Prerequisite
    { nodeId = NodeId "cluster.kindest-node-pin"
    , nodeDescription = "kindest/node pin is mirrored between kind configs and cabal.project."
    , remedyHint =
        Just "keep the kindest/node pin in kind/cluster-<substrate>.yaml and cabal.project aligned"
    , dependsOn = []
    , remediation = Nothing
    , checkNode = checkKindestNodePin
    }

checkKindestNodePin :: IO Bool
checkKindestNodePin = do
  kindExists <- doesDirectoryExist "kind"
  if not kindExists
    then pure True
    else do
      cabalExists <- doesFileExist "cabal.project"
      kindFiles <- filter isKindClusterConfig <$> listDirectory "kind"
      if not cabalExists || null kindFiles
        then pure False
        else do
          cabalProject <- Text.IO.readFile "cabal.project"
          kindContents <- traverse (Text.IO.readFile . ("kind" </>)) kindFiles
          pure ("kindest/node" `isInText` cabalProject && all ("kindest/node" `isInText`) kindContents)

isKindClusterConfig :: FilePath -> Bool
isKindClusterConfig path =
  "cluster-" `isPrefixOf` path && ".yaml" `isSuffixOf` path

isInText :: String -> Text -> Bool
isInText needle haystack =
  Text.pack needle `Text.isInfixOf` haystack

-- | Check the full hard envelope against the already-selected Docker runtime,
-- including every Kind node, the client job and VM overhead. Missing runtime
-- observations fail on every host; this never starts or resizes a VM.
clusterHostMemoryPrerequisite :: Prerequisite
clusterHostMemoryPrerequisite =
  Prerequisite
    { nodeId = NodeId "cluster.host-memory"
    , nodeDescription =
        "Docker CPU/RAM fit every Kind node, the client job and VM reserve."
    , remedyHint =
        Just
          "select a fitting JITML_CLUSTER_RESOURCES profile and explicitly start its Docker runtime"
    , dependsOn = []
    , remediation = Nothing
    , checkNode = checkMinimumHostMemory
    }

checkMinimumHostMemory :: IO Bool
checkMinimumHostMemory = do
  resources <- loadClusterResourcesOrDefault "."
  outcome <- checkResourceEnvelopeIO resources
  pure (either (const False) (const True) outcome)
