{-# LANGUAGE OverloadedStrings #-}

module JitML.Cluster.Storage
  ( ManualPV (..)
  , manualPVs
  , pvLocalDataPath
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
  , pvClaimRefName :: Maybe Text
  }
  deriving stock (Eq, Show)

manualPVs :: [ManualPV]
manualPVs =
  concat
    [ statefulSetReplicas "platform" "minio" 4 "20Gi"
    , statefulSetReplicas "platform" "pulsar-bookkeeper" 3 "20Gi"
    , statefulSetReplicas "platform" "pulsar-zookeeper" 3 "10Gi"
    , perconaReplicas "platform" "harbor-pg" 3 "10Gi"
    , perconaReplicas "platform" "harbor-pg-repo1" 1 "10Gi"
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
  Text.unlines $
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
    ]
      <> claimRefLines pv

pvName :: ManualPV -> Text
pvName pv =
  pvNamespace pv <> "-" <> pvStatefulSet pv <> "-pv-" <> Text.pack (show (pvReplica pv))

pvHostPath :: ManualPV -> Text
pvHostPath pv =
  "/jitml/.data/"
    <> pvNamespace pv
    <> "/"
    <> pvStatefulSet pv
    <> "/pv_"
    <> Text.pack (show (pvReplica pv))
    <> "/"

pvLocalDataPath :: ManualPV -> Text
pvLocalDataPath pv =
  "./.data/"
    <> pvNamespace pv
    <> "/"
    <> pvStatefulSet pv
    <> "/pv_"
    <> Text.pack (show (pvReplica pv))
    <> "/"

claimRefLines :: ManualPV -> [Text]
claimRefLines pv =
  case pvClaimRefName pv of
    Nothing -> []
    Just claimName ->
      [ "  claimRef:"
      , "    namespace: " <> pvNamespace pv
      , "    name: " <> claimName
      ]

statefulSetReplicas :: Text -> Text -> Int -> Text -> [ManualPV]
statefulSetReplicas namespace statefulSet count size =
  [ ManualPV
      namespace
      statefulSet
      replica
      size
      (Just ("data-" <> statefulSet <> "-" <> Text.pack (show replica)))
  | replica <- [0 .. count - 1]
  ]

perconaReplicas :: Text -> Text -> Int -> Text -> [ManualPV]
perconaReplicas namespace statefulSet count size =
  [ ManualPV namespace statefulSet replica size Nothing
  | replica <- [0 .. count - 1]
  ]
