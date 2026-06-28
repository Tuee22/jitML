{-# LANGUAGE OverloadedStrings #-}

module JitML.Cluster.Kind
  ( KindConfig (..)
  , defaultKindestNodeImage
  , defaultKindWorkerCount
  , kindConfigFor
  , kindConfigForEdgePort
  , kindConfigForEdgePortAndWorkers
  , kindConfigForWorkers
  , kindConfigNodeContainerNames
  , renderKindConfig
  , substrateKindNodeContainerNames
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Substrate (Substrate (..), renderSubstrate, substrateClusterName, substrateEdgePort)

data KindConfig = KindConfig
  { kindConfigSubstrate :: Substrate
  , kindConfigName :: Text
  , kindConfigNodeImage :: Text
  , kindConfigEdgePort :: Int
  , kindConfigWorkerCount :: Int
  , kindConfigGpuLabel :: Bool
  }
  deriving stock (Eq, Show)

defaultKindestNodeImage :: Text
defaultKindestNodeImage = "kindest/node:v1.34.0"

defaultKindWorkerCount :: Int
defaultKindWorkerCount = 3

kindConfigFor :: Substrate -> KindConfig
kindConfigFor substrate =
  kindConfigForEdgePort substrate (substrateEdgePort substrate)

kindConfigForEdgePort :: Substrate -> Int -> KindConfig
kindConfigForEdgePort substrate edgePort =
  kindConfigForEdgePortAndWorkers substrate edgePort defaultKindWorkerCount

kindConfigForWorkers :: Substrate -> Int -> KindConfig
kindConfigForWorkers substrate =
  kindConfigForEdgePortAndWorkers substrate (substrateEdgePort substrate)

kindConfigForEdgePortAndWorkers :: Substrate -> Int -> Int -> KindConfig
kindConfigForEdgePortAndWorkers substrate edgePort workerCount =
  KindConfig
    { kindConfigSubstrate = substrate
    , kindConfigName = substrateClusterName substrate
    , kindConfigNodeImage = defaultKindestNodeImage
    , kindConfigEdgePort = edgePort
    , kindConfigWorkerCount = max 1 workerCount
    , kindConfigGpuLabel = substrate == LinuxCUDA
    }

renderKindConfig :: KindConfig -> Text
renderKindConfig config =
  Text.unlines $
    [ "kind: Cluster"
    , "apiVersion: kind.x-k8s.io/v1alpha4"
    , "name: " <> kindConfigName config
    ]
      <> nvidiaContainerdPatch
      <> ["nodes:"]
      <> controlPlaneNode
      <> concatMap workerNode [1 .. kindConfigWorkerCount config]
 where
  controlPlaneNode =
    [ "  - role: control-plane"
    , "    image: " <> kindConfigNodeImage config
    , "    extraPortMappings:"
    , "      - containerPort: 30090"
    , "        hostPort: " <> Text.pack (show (kindConfigEdgePort config))
    , "        listenAddress: 127.0.0.1"
    , "        protocol: TCP"
    ]
      <> nodeLabels "InitConfiguration" False
      <> nodeMounts False

  workerNode _index =
    [ "  - role: worker"
    , "    image: " <> kindConfigNodeImage config
    ]
      <> nodeLabels "JoinConfiguration" True
      <> nodeMounts True

  nvidiaContainerdPatch
    | kindConfigGpuLabel config =
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

  nodeLabels kubeadmKind computeNode =
    [ "    kubeadmConfigPatches:"
    , "      - |"
    , "        kind: " <> kubeadmKind
    , "        nodeRegistration:"
    , "          kubeletExtraArgs:"
    , "            node-labels: " <> Text.intercalate "," labels
    ]
   where
    labels =
      ["jitml.substrate/" <> renderSubstrate (kindConfigSubstrate config) <> "=true"]
        <> ["jitml.node-role/compute=true" | computeNode]
        <> ["jitml.runtime/gpu=true" | computeNode && kindConfigGpuLabel config]

  nodeMounts includeNvidia =
    [ "    extraMounts:"
    , "      - hostPath: ./.build"
    , "        containerPath: /jitml/.build"
    , "        readOnly: false"
    , "      - hostPath: ./.data"
    , "        containerPath: /jitml/.data"
    , "        readOnly: false"
    ]
      <> nvidiaToolkitMounts includeNvidia

  nvidiaToolkitMounts includeNvidia
    | includeNvidia && kindConfigGpuLabel config =
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

kindConfigNodeContainerNames :: KindConfig -> [Text]
kindConfigNodeContainerNames config =
  substrateKindNodeContainerNames
    (kindConfigSubstrate config)
    (kindConfigWorkerCount config)

substrateKindNodeContainerNames :: Substrate -> Int -> [Text]
substrateKindNodeContainerNames substrate workerCount =
  substrateClusterName substrate
    <> "-control-plane"
    : [ substrateClusterName substrate <> workerSuffix index
      | index <- [1 .. max 1 workerCount]
      ]
 where
  workerSuffix 1 = "-worker"
  workerSuffix index = "-worker" <> Text.pack (show index)
