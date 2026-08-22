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

-- | The authoritative service-Postgres registry.
--
-- Empty. `harbor-pg` was its only row, and it existed solely to back Harbor's
-- core database; removing Harbor removed the last consumer of a service-managed
-- Postgres, and with it the Percona operator release and both persistent
-- volumes. The type and the `jitml lint chart` guard are retained rather than
-- deleted so that adding a Postgres-backed service later is still a matter of
-- adding one row here, and so that no chart may declare a `PerconaPGCluster`
-- this list does not.
postgresRegistry :: [PerconaPGCluster]
postgresRegistry = []

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

-- | Per-instance CPU/memory requests+limits matching the @postgres@ budget in
-- @dhall/cluster/resources.dhall@.
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
