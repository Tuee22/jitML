{-# LANGUAGE OverloadedStrings #-}

module JitML.Prerequisite.Nodes.Container
  ( containerPrerequisites
  , fixedMetalBridgePathCandidates
  , probeFixedMetalBridge
  )
where

import JitML.Engines.MetalBridge qualified as MetalBridge
import JitML.Engines.MetalRuntime qualified as MetalRuntime
import JitML.Prerequisite.Nodes.Common
  ( commandPrerequisite
  , homebrewPackagePrerequisite
  , purePrerequisite
  )
import JitML.Prerequisite.Types (NodeId (..), Prerequisite (..), PrerequisiteRemediation (..))
import JitML.Sub.Subprocess (subprocess)

containerPrerequisites :: [Prerequisite]
containerPrerequisites =
  [ purePrerequisite
      (NodeId "container")
      "Container prerequisite root."
      [NodeId "container.docker"]
  , purePrerequisite
      (NodeId "container.apple-silicon")
      "Apple Silicon container prerequisite root."
      [ NodeId "container.docker"
      , NodeId "container.colima"
      ]
  , purePrerequisite
      (NodeId "container.apple-silicon.jit-cache-miss")
      "Apple Silicon first JIT cache miss prerequisite root (fixed Metal bridge)."
      [ NodeId "apple.metal-runtime"
      , NodeId "apple.metal-bridge"
      ]
  , appleMetalRuntimePrerequisite
  , appleMetalBridgePrerequisite
  , commandPrerequisite
      (NodeId "apple.swiftc")
      "Optional Swift compiler for non-core generated Swift modules."
      "swiftc"
      "install Xcode Command Line Tools only for optional Swift module work"
      []
  , commandPrerequisite
      (NodeId "apple.macos-sdk")
      "Optional macOS SDK discovery tool for non-core generated Swift modules."
      "xcrun"
      "install Xcode Command Line Tools only for optional Swift module work"
      []
  , commandPrerequisite
      (NodeId "container.docker")
      "Docker CLI is installed."
      "docker"
      "install Docker"
      []
  , homebrewPackagePrerequisite
      (NodeId "container.colima")
      "Colima is installed for Apple Silicon bootstrap."
      "colima"
      "colima"
      []
  ]

appleMetalRuntimePrerequisite :: Prerequisite
appleMetalRuntimePrerequisite =
  Prerequisite
    { nodeId = NodeId "apple.metal-runtime"
    , nodeDescription =
        "Host OS Metal runtime is visible for in-process MSL compilation and dispatch."
    , remedyHint = Just "run on an Apple Silicon macOS host with Metal available"
    , dependsOn = []
    , remediation = Nothing
    , checkNode = MetalRuntime.metalRuntimeAvailable <$> MetalRuntime.probeMetalRuntime
    }

appleMetalBridgePrerequisite :: Prerequisite
appleMetalBridgePrerequisite =
  Prerequisite
    { nodeId = NodeId "apple.metal-bridge"
    , nodeDescription =
        "Fixed jitML Metal bridge dylib loads and its probe symbol succeeds."
    , remedyHint = Just "build or install the fixed jitML Metal bridge dylib"
    , dependsOn = [NodeId "apple.metal-runtime"]
    , remediation =
        Just
          PrerequisiteRemediation
            { remediationDescription = "Build the fixed jitML Metal bridge dylib."
            , remediationCommand = subprocess "jitml" ["internal", "install-metal-bridge"]
            }
    , checkNode = probeFixedMetalBridge
    }

fixedMetalBridgePathCandidates :: IO [FilePath]
fixedMetalBridgePathCandidates =
  MetalBridge.fixedMetalBridgePathCandidates

probeFixedMetalBridge :: IO Bool
probeFixedMetalBridge =
  MetalBridge.probeFixedMetalBridge
