{-# LANGUAGE OverloadedStrings #-}

module JitML.Prerequisite.Nodes.Cluster
  ( clusterPrerequisites
  )
where

import Data.List (isPrefixOf, isSuffixOf)
import Data.Maybe (listToMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath ((</>))

import JitML.Cluster.Resources (loadClusterResourcesOrDefault, nodeMemoryMiB)
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

-- | Sprint 2.8 — fail bootstrap fast when host RAM is below the dhall/cluster/
-- node cap plus a 4 GiB host reserve, so the user does not start a rollout that
-- cannot fit. Passes on non-Linux hosts where @/proc/meminfo@ is absent.
clusterHostMemoryPrerequisite :: Prerequisite
clusterHostMemoryPrerequisite =
  Prerequisite
    { nodeId = NodeId "cluster.host-memory"
    , nodeDescription =
        "Host MemTotal is sufficient for the dhall/cluster/ node cap + 4 GiB reserve."
    , remedyHint =
        Just
          "lower nodeMemoryMiB in dhall/cluster/resources.dhall, free RAM, or use a bigger host"
    , dependsOn = []
    , remediation = Nothing
    , checkNode = checkMinimumHostMemory
    }

checkMinimumHostMemory :: IO Bool
checkMinimumHostMemory = do
  meminfoExists <- doesFileExist "/proc/meminfo"
  if not meminfoExists
    then pure True
    else do
      contents <- Text.IO.readFile "/proc/meminfo"
      case parseMemTotalKB contents of
        Nothing -> pure True
        Just totalKB -> do
          res <- loadClusterResourcesOrDefault "."
          let reserveMiB = 4096
              totalMiB = totalKB `div` 1024
              needMiB = nodeMemoryMiB res + reserveMiB
          pure (totalMiB >= needMiB)

parseMemTotalKB :: Text -> Maybe Int
parseMemTotalKB contents = listToMaybe $ do
  line <- Text.lines contents
  case Text.words line of
    ["MemTotal:", kbText, "kB"] ->
      case reads (Text.unpack kbText) of
        [(parsed, "")] -> [parsed :: Int]
        _ -> []
    _ -> []
