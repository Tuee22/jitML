{-# LANGUAGE OverloadedStrings #-}

module JitML.Cluster.PostgresRegistry
  ( PerconaPGCluster (..)
  , Postgres (..)
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
      , perconaReplicas = 3
      , perconaStorageSize = "10Gi"
      , perconaDatabase = "harbor"
      , perconaSecretName = "harbor-pg-secrets"
      }
  ]

renderPerconaPGCluster :: PerconaPGCluster -> Text
renderPerconaPGCluster cluster =
  Text.unlines
    [ "apiVersion: pgv2.percona.com/v2"
    , "kind: PerconaPGCluster"
    , "metadata:"
    , "  name: " <> perconaClusterName cluster
    , "  namespace: " <> perconaNamespace cluster
    , "spec:"
    , "  postgresVersion: 16"
    , "  instances:"
    , "    - name: instance1"
    , "      replicas: " <> Text.pack (show (perconaReplicas cluster))
    , "      dataVolumeClaimSpec:"
    , "        accessModes: [\"ReadWriteOnce\"]"
    , "        resources:"
    , "          requests:"
    , "            storage: " <> perconaStorageSize cluster
    , "  database: " <> perconaDatabase cluster
    , "  users:"
    , "    - name: " <> perconaDatabase cluster
    , "      databases:"
    , "        - " <> perconaDatabase cluster
    , "      secretName: " <> perconaSecretName cluster
    ]

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
