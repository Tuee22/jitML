-- | The MinIO bucket set.
--
-- Phase 4, Sprint 4.9 (durable-state DSL adoption) — retired the former
-- hand-written @bucketNames :: [Text]@ literal. The bucket set is now __projected
-- from the durable-state registry__ (`JitML.Project.Config.defaultProjectConfig`):
-- every `ObjectBucket` entry's physical name. The registry (the source of
-- `jitml project init`'s @jitml.dhall@) is the single source of truth, so a bucket
-- can only exist if it is a declared `Live` store.
module JitML.Storage.Buckets
  ( bucketNames
  )
where

import Data.Text (Text)

import JitML.Project.Config
  ( StoreKind (ObjectBucket)
  , defaultProjectConfig
  , projectStores
  , storeKind
  , storePhysicalName
  )

bucketNames :: [Text]
bucketNames =
  [ storePhysicalName entry
  | entry <- projectStores defaultProjectConfig
  , storeKind entry == ObjectBucket
  ]
