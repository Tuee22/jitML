{-# LANGUAGE OverloadedStrings #-}

module JitML.Cluster.Kind
  ( KindConfig (..)
  , defaultKindestNodeImage
  , kindConfigFor
  , kindConfigForEdgePort
  , kindConfigWithWorkerCount
  , renderKindConfig
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Numeric.Natural (Natural)

import JitML.Substrate (Substrate (..), renderSubstrate, substrateClusterName, substrateEdgePort)

data KindConfig = KindConfig
  { kindConfigSubstrate :: Substrate
  , kindConfigName :: Text
  , kindConfigNodeImage :: Text
  , kindConfigEdgePort :: Int
  , kindConfigWorkerGpuLabel :: Bool
  , kindConfigWorkerCount :: Natural
  }
  deriving stock (Eq, Show)

defaultKindestNodeImage :: Text
defaultKindestNodeImage = "kindest/node:v1.32.2"

kindConfigFor :: Substrate -> KindConfig
kindConfigFor substrate =
  kindConfigForEdgePort substrate (substrateEdgePort substrate)

kindConfigForEdgePort :: Substrate -> Int -> KindConfig
kindConfigForEdgePort substrate edgePort =
  KindConfig
    { kindConfigSubstrate = substrate
    , kindConfigName = substrateClusterName substrate
    , kindConfigNodeImage = defaultKindestNodeImage
    , kindConfigEdgePort = edgePort
    , kindConfigWorkerGpuLabel = substrate == LinuxCUDA
    , kindConfigWorkerCount = 1
    }

kindConfigWithWorkerCount :: Natural -> KindConfig -> KindConfig
kindConfigWithWorkerCount workerCount config =
  config {kindConfigWorkerCount = max 1 workerCount}

renderKindConfig :: KindConfig -> Text
renderKindConfig config =
  Text.unlines $
    [ "kind: Cluster"
    , "apiVersion: kind.x-k8s.io/v1alpha4"
    , "name: " <> kindConfigName config
    ]
      <> nvidiaContainerdPatch
      <> [ "nodes:"
         , "  - role: control-plane"
         , "    image: " <> kindConfigNodeImage config
         , "    extraPortMappings:"
         , "      - containerPort: 30090"
         , "        hostPort: " <> Text.pack (show (kindConfigEdgePort config))
         , "        listenAddress: 127.0.0.1"
         , "        protocol: TCP"
         ]
      <> concatMap renderWorkerNode [1 .. kindConfigWorkerCount config]
 where
  renderWorkerNode _workerIndex =
    [ "  - role: worker"
    , "    image: " <> kindConfigNodeImage config
    ]
      <> gpuPatch
      <> workerMounts

  nvidiaContainerdPatch
    | kindConfigWorkerGpuLabel config =
        [ "containerdConfigPatches:"
        , "  - |-"
        , "    [plugins.\"io.containerd.grpc.v1.cri\".containerd.runtimes.nvidia]"
        , "      runtime_type = \"io.containerd.runc.v2\""
        , "      base_runtime_spec = \"/etc/containerd/cri-base.json\""
        , "      privileged_without_host_devices = false"
        , "    [plugins.\"io.containerd.grpc.v1.cri\".containerd.runtimes.nvidia.options]"
        , "      BinaryName = \"/usr/bin/nvidia-container-runtime\""
        , "      SystemdCgroup = true"
        ]
    | otherwise = []

  gpuPatch
    | kindConfigWorkerGpuLabel config =
        [ "    kubeadmConfigPatches:"
        , "      - |"
        , "        kind: JoinConfiguration"
        , "        nodeRegistration:"
        , "          kubeletExtraArgs:"
        , "            node-labels: jitml.runtime/gpu=true,jitml.substrate/"
            <> renderSubstrate (kindConfigSubstrate config)
            <> "=true"
        ]
    | otherwise = []

  workerMounts =
    [ "    extraMounts:"
    , "      - hostPath: ./.build"
    , "        containerPath: /jitml/.build"
    , "        readOnly: false"
    , "      - hostPath: ./.data"
    , "        containerPath: /jitml/.data"
    , "        readOnly: false"
    ]
      <> nvidiaToolkitMounts

  nvidiaToolkitMounts
    | kindConfigWorkerGpuLabel config =
        concatMap
          renderReadOnlyMount
          [ ("./kind/nvidia-container-runtime", "/etc/nvidia-container-runtime")
          , ("/", "/run/nvidia/driver")
          , ("/usr/bin/nvidia-container-runtime", "/usr/bin/nvidia-container-runtime")
          , ("/usr/bin/nvidia-container-runtime-hook", "/usr/bin/nvidia-container-runtime-hook")
          , ("/usr/bin/nvidia-container-toolkit", "/usr/bin/nvidia-container-toolkit")
          , ("/usr/bin/nvidia-container-cli", "/usr/bin/nvidia-container-cli")
          , ("/usr/bin/nvidia-cdi-hook", "/usr/bin/nvidia-cdi-hook")
          , ("/usr/bin/nvidia-ctk", "/usr/bin/nvidia-ctk")
          ,
            ( "/usr/lib/x86_64-linux-gnu/libnvidia-container.so.1"
            , "/usr/lib/x86_64-linux-gnu/libnvidia-container.so.1"
            )
          ,
            ( "/usr/lib/x86_64-linux-gnu/libnvidia-container-go.so.1"
            , "/usr/lib/x86_64-linux-gnu/libnvidia-container-go.so.1"
            )
          , ("/usr/lib/x86_64-linux-gnu/libnvidia-ml.so.1", "/usr/lib/x86_64-linux-gnu/libnvidia-ml.so.1")
          ]
    | otherwise = []

  renderReadOnlyMount (hostPath, containerPath) =
    [ "      - hostPath: " <> hostPath
    , "        containerPath: " <> containerPath
    , "        readOnly: true"
    ]
