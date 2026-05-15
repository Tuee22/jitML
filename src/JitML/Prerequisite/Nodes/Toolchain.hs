{-# LANGUAGE OverloadedStrings #-}

module JitML.Prerequisite.Nodes.Toolchain
  ( toolchainPrerequisites
  )
where

import System.Directory (doesFileExist, getHomeDirectory)
import System.FilePath ((</>))

import JitML.Prerequisite.Nodes.Common
  ( checkAnyExecutable
  , homebrewPackagePrerequisite
  , purePrerequisite
  )
import JitML.Prerequisite.Types (NodeId (..), Prerequisite (..))

toolchainPrerequisites :: [Prerequisite]
toolchainPrerequisites =
  [ purePrerequisite
      (NodeId "toolchain")
      "Toolchain prerequisite root."
      [ NodeId "toolchain.ghc-9.14.1"
      , NodeId "toolchain.cabal-3.16.1.0"
      , NodeId "toolchain.protoc"
      , NodeId "toolchain.node"
      , NodeId "toolchain.poetry"
      , NodeId "toolchain.purescript"
      , NodeId "toolchain.spago"
      , NodeId "toolchain.pulumi"
      ]
  , ghcPrerequisite
  , cabalPrerequisite
  , homebrewPackagePrerequisite
      (NodeId "toolchain.protoc")
      "Protocol buffer compiler is installed."
      "protoc"
      "protobuf"
      []
  , homebrewPackagePrerequisite (NodeId "toolchain.node") "Node.js is installed." "node" "node" []
  , homebrewPackagePrerequisite (NodeId "toolchain.poetry") "Poetry is installed." "poetry" "poetry" []
  , homebrewPackagePrerequisite
      (NodeId "toolchain.purescript")
      "PureScript compiler is installed."
      "purs"
      "purescript"
      []
  , homebrewPackagePrerequisite (NodeId "toolchain.spago") "Spago is installed." "spago" "spago" []
  , homebrewPackagePrerequisite (NodeId "toolchain.pulumi") "Pulumi is installed." "pulumi" "pulumi" []
  ]

ghcPrerequisite :: Prerequisite
ghcPrerequisite =
  Prerequisite
    { nodeId = NodeId "toolchain.ghc-9.14.1"
    , nodeDescription = "GHC 9.14.1 is installed."
    , remedyHint = Just "run `ghcup install ghc 9.14.1`"
    , dependsOn = []
    , remediation = Nothing
    , checkNode = checkPinnedGhc
    }

cabalPrerequisite :: Prerequisite
cabalPrerequisite =
  Prerequisite
    { nodeId = NodeId "toolchain.cabal-3.16.1.0"
    , nodeDescription = "Cabal 3.16.1.0 is installed."
    , remedyHint = Just "run `ghcup install cabal 3.16.1.0`"
    , dependsOn = []
    , remediation = Nothing
    , checkNode = checkPinnedCabal
    }

checkPinnedGhc :: IO Bool
checkPinnedGhc = do
  commandPresent <- checkAnyExecutable ["ghc-9.14.1"]
  home <- getHomeDirectory
  homePresent <- doesFileExist (home </> ".ghcup" </> "ghc" </> "9.14.1" </> "bin" </> "ghc")
  pure (commandPresent || homePresent)

checkPinnedCabal :: IO Bool
checkPinnedCabal = do
  commandPresent <- checkAnyExecutable ["cabal-3.16.1.0"]
  home <- getHomeDirectory
  homePresent <- doesFileExist (home </> ".ghcup" </> "bin" </> "cabal-3.16.1.0")
  pure (commandPresent || homePresent)
