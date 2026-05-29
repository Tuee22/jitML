{-# LANGUAGE OverloadedStrings #-}

module JitML.Cluster.PostgresRegistry
  ( PerconaPGCluster (..)
  , Postgres (..)
  , perconaPgVolumeNames
  , postgresRegistry
  , renderPerconaPGCluster
  , validateRegisteredPostgres
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

newtype Postgres = Postgres
  { postgresName :: Text
  }
  deriving stock (Eq, Show)

data PerconaPGCluster = PerconaPGCluster
  { perconaClusterName :: Text
  , perconaNamespace :: Text
  , perconaReplicas :: Int
  , perconaStorageSize :: Text
  , perconaDatabase :: Text
  , perconaSecretName :: Text
  }
  deriving stock (Eq, Show)

-- | The authoritative service-Postgres registry. The first entry is
-- `harbor-pg` per Sprint 4.2. Adding a new service-managed Postgres means
-- adding a row here; `jitml lint chart` rejects any `PerconaPGCluster` not
-- declared here.
postgresRegistry :: [PerconaPGCluster]
postgresRegistry =
  [ PerconaPGCluster
      { perconaClusterName = "harbor-pg"
      , perconaNamespace = "platform"
      , -- Sprint 4.8 (reopened 2026-05-29): right-sized from `3` (HA) to `1`
        -- so the cluster fits under the Sprint 2.8 kind-node cap on a
        -- ~16 GiB single-node host. The dhall/cluster/ profile's
        -- `postgres.replicas` is the single source of truth for this value.
        perconaReplicas = 1
      , perconaStorageSize = "10Gi"
      , perconaDatabase = "harbor"
      , perconaSecretName = "harbor-pg-secrets"
      }
  ]

renderPerconaPGCluster :: PerconaPGCluster -> Text
renderPerconaPGCluster cluster =
  Text.unlines
    ( [ "apiVersion: pgv2.percona.com/v2"
      , "kind: PerconaPGCluster"
      , "metadata:"
      , "  name: " <> perconaClusterName cluster
      , "  namespace: " <> perconaNamespace cluster
      , "spec:"
      , "  postgresVersion: 16"
      , "  image: percona/percona-postgresql-operator:2.5.1-ppg16.8-postgres"
      , "  backups:"
      , "    pgbackrest:"
      , "      image: percona/percona-postgresql-operator:2.5.1-ppg16.8-pgbackrest2.54.2"
      , "      repos:"
      , "        - name: repo1"
      , "          volume:"
      , "            volumeClaimSpec:"
      , "              accessModes:"
      , "                - ReadWriteOnce"
      , "              resources:"
      , "                requests:"
      , "                  storage: " <> perconaStorageSize cluster
      , "              storageClassName: jitml-manual"
      , "              volumeName: " <> perconaPgBackupVolumeName cluster
      , "  instances:"
      ]
        <> concatMap (renderInstance cluster) [0 .. perconaReplicas cluster - 1]
        <> [ "  proxy:"
           , "    pgBouncer:"
           , "      image: percona/percona-postgresql-operator:2.5.1-ppg16.8-pgbouncer1.24.0"
           , "      replicas: 1"
           , "  users:"
           , "    - name: " <> perconaDatabase cluster
           , "      databases:"
           , "        - " <> perconaDatabase cluster
           , "      secretName: " <> perconaSecretName cluster
           ]
    )

perconaPgVolumeNames :: PerconaPGCluster -> [Text]
perconaPgVolumeNames cluster =
  perconaPgBackupVolumeName cluster
    : fmap (perconaPgVolumeName cluster) [0 .. perconaReplicas cluster - 1]

-- | Sprint 4.8 — per-instance CPU/memory requests+limits matching the
-- @postgres@ budget in @dhall/cluster/resources.dhall@ so the platform fits
-- under the Sprint 2.8 kind-node cap.
renderInstance :: PerconaPGCluster -> Int -> [Text]
renderInstance cluster replica =
  [ "    - name: instance" <> Text.pack (show (replica + 1))
  , "      replicas: 1"
  , "      resources:"
  , "        requests:"
  , "          cpu: 200m"
  , "          memory: 512Mi"
  , "        limits:"
  , "          cpu: 500m"
  , "          memory: 1Gi"
  , "      dataVolumeClaimSpec:"
  , "        accessModes:"
  , "          - ReadWriteOnce"
  , "        resources:"
  , "          requests:"
  , "            storage: " <> perconaStorageSize cluster
  , "        storageClassName: jitml-manual"
  , "        volumeName: " <> perconaPgVolumeName cluster replica
  ]

perconaPgVolumeName :: PerconaPGCluster -> Int -> Text
perconaPgVolumeName cluster replica =
  perconaNamespace cluster
    <> "-"
    <> perconaClusterName cluster
    <> "-pv-"
    <> Text.pack (show replica)

perconaPgBackupVolumeName :: PerconaPGCluster -> Text
perconaPgBackupVolumeName cluster =
  perconaNamespace cluster
    <> "-"
    <> perconaClusterName cluster
    <> "-repo1-pv-0"

-- | Lint helper: given a cluster name observed in a manifest, return Nothing
-- if it is in the registry and `Just <reason>` if it must be removed.
validateRegisteredPostgres :: Text -> Maybe Text
validateRegisteredPostgres clusterName
  | clusterName `elem` registered = Nothing
  | otherwise =
      Just
        ( "PerconaPGCluster '"
            <> clusterName
            <> "' is not in postgresRegistry"
            <> "; add it to src/JitML/Cluster/PostgresRegistry.hs or remove the manifest"
        )
 where
  registered = fmap perconaClusterName postgresRegistry
