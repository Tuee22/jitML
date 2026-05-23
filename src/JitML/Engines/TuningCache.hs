{-# LANGUAGE OverloadedStrings #-}

module JitML.Engines.TuningCache
  ( TuningCachePlan (..)
  , cacheSubstrateFor
  , defaultTuningCachePlan
  , selectTuningCachePlan
  , tuningCacheSelectionSource
  )
where

import Data.Text (Text)

import JitML.Cache.Key qualified as Cache
import JitML.Codegen.RuntimeSource
  ( RuntimeSource
  , renderRuntimeSource
  , runtimeSourcePayload
  )
import JitML.Engines.TuningStore
  ( PersistedTuningSelection (..)
  , readTuningSelection
  )
import JitML.Substrate (Substrate (..))

data TuningCachePlan = TuningCachePlan
  { tuningCacheSubstrate :: Substrate
  , tuningCacheBaseHash :: Cache.Hash
  , tuningCacheHash :: Cache.Hash
  , tuningCacheTuningChoice :: Cache.TuningChoice
  , tuningCacheRuntimeSource :: RuntimeSource
  , tuningCachePersistedSelection :: Maybe PersistedTuningSelection
  }
  deriving stock (Eq, Show)

selectTuningCachePlan
  :: FilePath
  -> Cache.KernelSpec
  -> Cache.Kind
  -> Substrate
  -> Cache.ToolchainFingerprint
  -> IO (Either Text TuningCachePlan)
selectTuningCachePlan buildRoot kernelSpec kind substrate fingerprint = do
  let basePlan = defaultTuningCachePlan kernelSpec kind substrate fingerprint
  persistedResult <- readTuningSelection buildRoot substrate (tuningCacheBaseHash basePlan)
  pure $
    case persistedResult of
      Left err -> Left err
      Right Nothing -> Right basePlan
      Right (Just persistedSelection) ->
        Right (planWithPersistedSelection kernelSpec kind fingerprint basePlan persistedSelection)

defaultTuningCachePlan
  :: Cache.KernelSpec
  -> Cache.Kind
  -> Substrate
  -> Cache.ToolchainFingerprint
  -> TuningCachePlan
defaultTuningCachePlan kernelSpec kind substrate fingerprint =
  let source =
        renderRuntimeSource
          kernelSpec
          kind
          (cacheSubstrateFor substrate)
          Cache.defaultTuningChoice
      hash =
        tuningCacheHashFor
          kernelSpec
          kind
          substrate
          fingerprint
          source
          Cache.defaultTuningChoice
   in TuningCachePlan
        { tuningCacheSubstrate = substrate
        , tuningCacheBaseHash = hash
        , tuningCacheHash = hash
        , tuningCacheTuningChoice = Cache.defaultTuningChoice
        , tuningCacheRuntimeSource = source
        , tuningCachePersistedSelection = Nothing
        }

planWithPersistedSelection
  :: Cache.KernelSpec
  -> Cache.Kind
  -> Cache.ToolchainFingerprint
  -> TuningCachePlan
  -> PersistedTuningSelection
  -> TuningCachePlan
planWithPersistedSelection kernelSpec kind fingerprint basePlan persistedSelection =
  let substrate = tuningCacheSubstrate basePlan
      tuningChoice = persistedTuningChoice persistedSelection
      source =
        renderRuntimeSource
          kernelSpec
          kind
          (cacheSubstrateFor substrate)
          tuningChoice
      hash =
        tuningCacheHashFor
          kernelSpec
          kind
          substrate
          fingerprint
          source
          tuningChoice
   in basePlan
        { tuningCacheHash = hash
        , tuningCacheTuningChoice = tuningChoice
        , tuningCacheRuntimeSource = source
        , tuningCachePersistedSelection = Just persistedSelection
        }

tuningCacheHashFor
  :: Cache.KernelSpec
  -> Cache.Kind
  -> Substrate
  -> Cache.ToolchainFingerprint
  -> RuntimeSource
  -> Cache.TuningChoice
  -> Cache.Hash
tuningCacheHashFor kernelSpec kind substrate fingerprint source =
  Cache.cacheKey
    kernelSpec
    kind
    (cacheSubstrateFor substrate)
    fingerprint
    (runtimeSourcePayload source)

tuningCacheSelectionSource :: TuningCachePlan -> Text
tuningCacheSelectionSource plan =
  case tuningCachePersistedSelection plan of
    Just _ -> "persisted"
    Nothing -> "default"

cacheSubstrateFor :: Substrate -> Cache.Substrate
cacheSubstrateFor AppleSilicon = Cache.AppleSilicon
cacheSubstrateFor LinuxCPU = Cache.LinuxCPU
cacheSubstrateFor LinuxCUDA = Cache.LinuxCUDA
