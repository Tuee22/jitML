{-# LANGUAGE OverloadedStrings #-}

module JitML.Cluster.Kind
    ( KindConfig (..)
    , defaultKindestNodeImage
    , kindConfigFor
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
    , kindConfigWorkerGpuLabel :: Bool
    }
    deriving stock (Eq, Show)

defaultKindestNodeImage :: Text
defaultKindestNodeImage = "kindest/node:v1.32.2"

kindConfigFor :: Substrate -> KindConfig
kindConfigFor substrate =
    KindConfig
        { kindConfigSubstrate = substrate
        , kindConfigName = substrateClusterName substrate
        , kindConfigNodeImage = defaultKindestNodeImage
        , kindConfigEdgePort = substrateEdgePort substrate
        , kindConfigWorkerGpuLabel = substrate == LinuxCUDA
        }

renderKindConfig :: KindConfig -> Text
renderKindConfig config =
    Text.unlines $
        [ "kind: Cluster"
        , "apiVersion: kind.x-k8s.io/v1alpha4"
        , "name: " <> kindConfigName config
        , "nodes:"
        , "  - role: control-plane"
        , "    image: " <> kindConfigNodeImage config
        , "    extraPortMappings:"
        , "      - containerPort: 30090"
        , "        hostPort: " <> Text.pack (show (kindConfigEdgePort config))
        , "        listenAddress: 127.0.0.1"
        , "        protocol: TCP"
        , "  - role: worker"
        , "    image: " <> kindConfigNodeImage config
        ]
            <> gpuPatch
            <> [ "    extraMounts:"
               , "      - hostPath: ./.build"
               , "        containerPath: /jitml/.build"
               , "        readOnly: false"
               ]
  where
    gpuPatch
        | kindConfigWorkerGpuLabel config =
            [ "    kubeadmConfigPatches:"
            , "      - |"
            , "        kind: JoinConfiguration"
            , "        nodeRegistration:"
            , "          kubeletExtraArgs:"
            , "            node-labels: jitml.runtime/gpu=true,jitml.substrate/" <> renderSubstrate (kindConfigSubstrate config) <> "=true"
            ]
        | otherwise = []
