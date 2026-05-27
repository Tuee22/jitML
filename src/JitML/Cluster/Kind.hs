{-# LANGUAGE OverloadedStrings #-}

module JitML.Cluster.Kind
  ( KindConfig (..)
  , defaultKindestNodeImage
  , kindConfigFor
  , kindConfigForEdgePort
  , kindConfigForEdgePortNamed
  , kindConfigForNamed
  , renderKindConfig
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
  , kindConfigGpuLabel :: Bool
  }
  deriving stock (Eq, Show)

defaultKindestNodeImage :: Text
defaultKindestNodeImage = "kindest/node:v1.32.2"

kindConfigFor :: Substrate -> KindConfig
kindConfigFor substrate =
  kindConfigForEdgePort substrate (substrateEdgePort substrate)

kindConfigForEdgePort :: Substrate -> Int -> KindConfig
kindConfigForEdgePort substrate =
  kindConfigForEdgePortNamed substrate (substrateClusterName substrate)

-- | Overrides the cluster name so the Pulumi ephemeral path can produce a
-- per-stack `jitml-e2e-<short-sha>` Kind cluster from the same substrate-shaped
-- config. Sprint 13.1.
kindConfigForNamed :: Substrate -> Text -> KindConfig
kindConfigForNamed substrate name =
  kindConfigForEdgePortNamed substrate name (substrateEdgePort substrate)

kindConfigForEdgePortNamed :: Substrate -> Text -> Int -> KindConfig
kindConfigForEdgePortNamed substrate name edgePort =
  KindConfig
    { kindConfigSubstrate = substrate
    , kindConfigName = name
    , kindConfigNodeImage = defaultKindestNodeImage
    , kindConfigEdgePort = edgePort
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
      <> [ "nodes:"
         , "  - role: control-plane"
         , "    image: " <> kindConfigNodeImage config
         , "    extraPortMappings:"
         , "      - containerPort: 30090"
         , "        hostPort: " <> Text.pack (show (kindConfigEdgePort config))
         , "        listenAddress: 127.0.0.1"
         , "        protocol: TCP"
         ]
      <> gpuPatch
      <> nodeMounts
 where
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

  gpuPatch
    | kindConfigGpuLabel config =
        [ "    kubeadmConfigPatches:"
        , "      - |"
        , "        kind: InitConfiguration"
        , "        nodeRegistration:"
        , "          kubeletExtraArgs:"
        , "            node-labels: jitml.runtime/gpu=true,jitml.substrate/"
            <> renderSubstrate (kindConfigSubstrate config)
            <> "=true"
        ]
    | otherwise = []

  nodeMounts =
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
    | kindConfigGpuLabel config =
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
