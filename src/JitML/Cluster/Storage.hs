{-# LANGUAGE OverloadedStrings #-}

module JitML.Cluster.Storage
  ( ManualPV (..)
  , manualPVs
  , pvLocalDataPath
  , pvNodeDataPath
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

-- | Sprint 3.6 — HA manual-PV layout. Replica counts match the target
-- `dhall/cluster/resources.dhall` profile and chart values: distributed MinIO,
-- Pulsar ZooKeeper/BookKeeper persistence, three Percona Postgres instances,
-- and one pgBackRest repository PV.
manualPVs :: [ManualPV]
manualPVs =
  concat
    [ statefulSetReplicas "platform" "minio" 4 "20Gi"
    , pulsarBookieReplicas "platform" 3
    , pulsarZookeeperReplicas "platform" 3 "10Gi"
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
    , "    path: " <> pvNodeDataPath pv
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

pvNodeDataPath :: ManualPV -> Text
pvNodeDataPath pv =
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

pulsarBookieReplicas :: Text -> Int -> [ManualPV]
pulsarBookieReplicas namespace count =
  pulsarBookieVolume "pulsar-bookie-journal" "journal" "10Gi"
    ++ pulsarBookieVolume "pulsar-bookie-ledgers" "ledgers" "20Gi"
 where
  pulsarBookieVolume statefulSet volumeName size =
    [ ManualPV
        namespace
        statefulSet
        replica
        size
        (Just ("pulsar-bookie-" <> volumeName <> "-pulsar-bookie-" <> Text.pack (show replica)))
    | replica <- [0 .. count - 1]
    ]

pulsarZookeeperReplicas :: Text -> Int -> Text -> [ManualPV]
pulsarZookeeperReplicas namespace count size =
  [ ManualPV
      namespace
      "pulsar-zookeeper-data"
      replica
      size
      (Just ("pulsar-zookeeper-data-pulsar-zookeeper-" <> Text.pack (show replica)))
  | replica <- [0 .. count - 1]
  ]

perconaReplicas :: Text -> Text -> Int -> Text -> [ManualPV]
perconaReplicas namespace statefulSet count size =
  [ ManualPV namespace statefulSet replica size Nothing
  | replica <- [0 .. count - 1]
  ]
