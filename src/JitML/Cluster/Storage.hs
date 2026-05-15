{-# LANGUAGE OverloadedStrings #-}

module JitML.Cluster.Storage
    ( ManualPV (..)
    , manualPVs
    , renderManualPV
    , renderStorageClass
    )
where

import Data.Text (Text)
import Data.Text qualified as Text

data ManualPV = ManualPV
    { pvNamespace :: Text
    , pvStatefulSet :: Text
    , pvReplica :: Int
    , pvSize :: Text
    }
    deriving stock (Eq, Show)

manualPVs :: [ManualPV]
manualPVs =
    concat
        [ replicas "platform" "minio" 4 "20Gi"
        , replicas "platform" "pulsar-bookkeeper" 3 "20Gi"
        , replicas "platform" "pulsar-zookeeper" 3 "10Gi"
        , replicas "platform" "harbor-pg" 3 "10Gi"
        ]

renderStorageClass :: Text
renderStorageClass =
    Text.unlines
        [ "apiVersion: storage.k8s.io/v1"
        , "kind: StorageClass"
        , "metadata:"
        , "  name: jitml-manual"
        , "provisioner: kubernetes.io/no-provisioner"
        , "volumeBindingMode: WaitForFirstConsumer"
        ]

renderManualPV :: ManualPV -> Text
renderManualPV pv =
    Text.unlines
        [ "apiVersion: v1"
        , "kind: PersistentVolume"
        , "metadata:"
        , "  name: " <> pvName pv
        , "spec:"
        , "  capacity:"
        , "    storage: " <> pvSize pv
        , "  accessModes:"
        , "    - ReadWriteOnce"
        , "  persistentVolumeReclaimPolicy: Retain"
        , "  storageClassName: jitml-manual"
        , "  local:"
        , "    path: " <> pvHostPath pv
        , "  nodeAffinity:"
        , "    required:"
        , "      nodeSelectorTerms:"
        , "        - matchExpressions:"
        , "            - key: kubernetes.io/hostname"
        , "              operator: Exists"
        , "  claimRef:"
        , "    namespace: " <> pvNamespace pv
        , "    name: data-" <> pvStatefulSet pv <> "-" <> Text.pack (show (pvReplica pv))
        ]

pvName :: ManualPV -> Text
pvName pv =
    pvNamespace pv <> "-" <> pvStatefulSet pv <> "-pv-" <> Text.pack (show (pvReplica pv))

pvHostPath :: ManualPV -> Text
pvHostPath pv =
    "./.data/" <> pvNamespace pv <> "/" <> pvStatefulSet pv <> "/pv_" <> Text.pack (show (pvReplica pv)) <> "/"

replicas :: Text -> Text -> Int -> Text -> [ManualPV]
replicas namespace statefulSet count size =
    [ ManualPV namespace statefulSet replica size
    | replica <- [0 .. count - 1]
    ]
