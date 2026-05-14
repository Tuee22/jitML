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
        ]
    , homebrewPackagePrerequisite (NodeId "cluster.kind") "kind is installed." "kind" "kind" []
    , homebrewPackagePrerequisite (NodeId "cluster.kubectl") "kubectl is installed." "kubectl" "kubernetes-cli" []
    , homebrewPackagePrerequisite (NodeId "cluster.helm") "helm is installed." "helm" "helm" []
    , kindestNodePinPrerequisite
    ]

kindestNodePinPrerequisite :: Prerequisite
kindestNodePinPrerequisite =
    Prerequisite
        { nodeId = NodeId "cluster.kindest-node-pin"
        , nodeDescription = "kindest/node pin is mirrored between kind configs and cabal.project."
        , remedyHint = Just "keep the kindest/node pin in kind/cluster-<substrate>.yaml and cabal.project aligned"
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
