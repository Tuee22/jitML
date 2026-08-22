{-# LANGUAGE OverloadedStrings #-}

module JitML.Cluster.Storage
  ( ManualPV (..)
  , manualPVs
  , manualPVsFor
  , pvLocalDataPath
  , pvNodeDataPath
  , renderManualPV
  , renderStorageClass
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Cluster.Resources
  ( ClusterResources
  , budgetReplicas
  , defaultClusterResources
  , minio
  , pulsar
  )

data ManualPV = ManualPV
  { pvNamespace :: Text
  , pvStatefulSet :: Text
  , pvReplica :: Int
  , pvSize :: Text
  , pvClaimRefName :: Maybe Text
  }
  deriving stock (Eq, Show)

-- | Manual-PV layout for the checked-in default resource profile.
manualPVs :: [ManualPV]
manualPVs = manualPVsFor defaultStorageResources

-- | Derive stateful storage cardinality from the same typed replica profile
-- that drives cluster materialization. BookKeeper and ZooKeeper share the
-- Pulsar replica count; pgBackRest retains one repository per PG cluster.
manualPVsFor :: ClusterResources -> [ManualPV]
manualPVsFor resources =
  concat
    [ minioReplicas "platform" (budgetReplicas (minio resources))
    , pulsarBookieReplicas "platform" (budgetReplicas (pulsar resources))
    , pulsarZookeeperReplicas "platform" (budgetReplicas (pulsar resources)) "10Gi"
    ]

-- Avoid a module cycle through the loader while keeping the compatibility
-- registry available to retained callers. Phase 53 will make its reduced
-- profile the default and regenerate the manifest set.
defaultStorageResources :: ClusterResources
defaultStorageResources = defaultClusterResources

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

-- Bitnami MinIO renders a Deployment with PVC @minio@ in standalone mode;
-- distributed mode renders StatefulSet PVCs @data-minio-N@.
minioReplicas :: Text -> Int -> [ManualPV]
minioReplicas namespace count =
  [ ManualPV
      namespace
      "minio"
      replica
      "20Gi"
      (Just (if count == 1 then "minio" else "data-minio-" <> Text.pack (show replica)))
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
