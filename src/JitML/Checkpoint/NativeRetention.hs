{-# LANGUAGE OverloadedStrings #-}

-- | Concrete byte retention only. These opaque acknowledgements establish no
-- training, device origin, parent authentication, qualification or fsync claim.
module JitML.Checkpoint.NativeRetention
  ( NativeRetentionMode (..)
  , NativePublicationData (..)
  , NativePublicationResolution (..)
  , NativeAllocationContext (..)
  , NativeAllocationScope (..)
  , NativeAllocationAddress
  , mkNativeAllocationAddress
  , nativeAllocationAddressKey
  , nativeAllocationAddressScope
  , NativeRetentionPhaseLabel
  , mkNativeRetentionPhaseLabel
  , NativeRetentionSession
  , captureNativeRetentionSession
  , captureNativeRetentionSessionAt
  , nativeRetentionPublication
  , RetainedNativeAllocation
  , nativeRetainedAllocationData
  , RetainedNativePhase
  , nativeRetainedPhaseData
  , NativeRetainedObjectData (..)
  , NativeRetentionCursor
  , NativeRetentionStage (..)
  , NativeRetentionFailure (..)
  , NativeRetentionReason (..)
  , claimNativeAllocation
  , appendNativeRetentionPhase
  , maximumNativeRetentionPayloadBytes
  , NativePhysicalReadFailure (..)
  , NativeReadObject
  , readNativeRetainedObject
  , nativeReadObjectReference
  , nativeReadObjectBytes
  , NativeReadCheckpoint
  , readNativeExecutionCheckpoint
  , nativeReadCheckpointLocal
  , nativeReadCheckpointEffective
  , nativeReadCheckpointPublication
  , nativePublicationDigest
  , NativeDetachedArtifactKind (..)
  , maximumNativeDetachedArtifactBytes
  , nativeDetachedArtifactKey
  , NativeReadDetachedArtifact
  , readNativeDetachedArtifact
  , nativeReadDetachedArtifactKind
  , nativeReadDetachedArtifactReference
  , nativeReadDetachedArtifactBytes
  ) where

import Codec.CBOR.Encoding qualified as CBOR
import Codec.CBOR.Write qualified as CBOR
import Control.Exception (evaluate)
import Control.Exception.Safe (tryAny)
import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Char (intToDigit)
import Data.Either (fromRight)
import Data.Either.Combinators (mapLeft)
import Data.Int (Int64)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Encoding
import Data.Word (Word64)
import System.IO (IOMode (ReadMode), withBinaryFile)

import JitML.Checkpoint.Store qualified as Store
import JitML.Checkpoint.Writer qualified as Writer
import JitML.Env.Env (App)
import JitML.Execution.SingleUse qualified as SingleUse
import JitML.Product.SourceDigest qualified as Source
import JitML.Service.Capabilities qualified as Capabilities
import JitML.Service.MinIOSubprocess qualified as MinIO
import JitML.Service.Retry (ServiceError (..))
import JitML.Service.WorkerPublication qualified as Worker
import JitML.Training.Budget qualified as TrainingBudget

data NativeRetentionMode = AllowLocalNativeRetention | RequireLiveNativeRetention
  deriving stock (Eq, Show)

-- No raw endpoint or credentials occur in this descriptor.
data NativePublicationResolution
  = NativeDefaultPublicationResolution
  | NativeExplicitPublicationResolution !Text
  deriving stock (Eq, Show)
data NativePublicationData
  = NativeLocalPublication !NativePublicationResolution !Text
  | NativeConfiguredPublication !NativePublicationResolution !Text !Text !Bool
  deriving stock (Eq, Show)
data NativeAllocationContext
  = NativeSuppliedScenarioDigest !Text
  | NativeDirectLocalAcquisition !Text
  deriving stock (Eq, Show)
data NativeAllocationScope = NativeAllocationScope
  { nativeAllocationContext :: !NativeAllocationContext
  , nativeAllocationRow :: !Text
  , nativeAllocationSource :: !Source.SourceStamp
  , nativeAllocationRecipeSha256 :: !Text
  , nativeAllocationAcquisitionId :: !Text
  }
  deriving stock (Eq, Show)
data NativeAllocationAddress = NativeAllocationAddress NativeAllocationScope Text
  deriving stock (Eq, Show)

-- Retain the data wrapper: newtype would change its intentional laziness.
{- HLINT ignore NativeRetentionPhaseLabel "Use newtype instead of data" -}
data NativeRetentionPhaseLabel = NativeRetentionPhaseLabel Text
  deriving stock (Eq, Show)

-- Settings, guards and executable continuations never cross a DATA codec.
data NativeRetentionSession
  = NativeRetentionSession
      FilePath
      (Maybe MinIO.MinIOSettings)
      NativePublicationData
      SingleUse.SingleUse
data RetainedNativeAllocation
  = RetainedNativeAllocation NativeAllocationAddress NativePublicationData NativeRetainedObjectData

-- Retain the data wrapper: newtype would change its intentional laziness.
{- HLINT ignore RetainedNativePhase "Use newtype instead of data" -}
data RetainedNativePhase = RetainedNativePhase NativeRetainedObjectData
data NativeRetentionCursor
  = NativeRetentionCursor
      NativeRetentionSession
      RetainedNativeAllocation
      NativeRetainedObjectData
      Word64
      SingleUse.SingleUse
data NativeRetainedObjectData = NativeRetainedObjectData
  { nativeRetainedObjectKey :: !Text
  , nativeRetainedObjectSha256 :: !Text
  , nativeRetainedObjectBytes :: !Word64
  , nativeRetainedObjectPublication :: !NativePublicationData
  }
  deriving stock (Eq, Show)
data NativeRetentionStage = NativePublicationCapture | NativeAllocationClaim | NativePhaseAppend
  deriving stock (Eq, Show)
data NativeRetentionReason
  = NativeRetentionSynchronousFailure
  | NativePublicationConfigurationInvalid
  | NativePublicationRequired
  | NativeRetentionAlreadyConsumed
  | NativeRetentionPayloadTooLarge
  | NativeRetentionLocalInvalid
  | NativeRetentionLocalConflict
  | NativeRetentionLocalFailure
  | NativeRetentionAlreadyClaimedLocally
  | NativeRetentionLocalReadbackMismatch
  | NativeRetentionRemoteConflict
  | NativeRetentionRemoteUnauthorized
  | NativeRetentionRemoteTimeout
  | NativeRetentionRemoteUnavailable
  | NativeRetentionRemoteMissing
  | NativeRetentionRemoteReadbackMismatch
  | NativeRetentionAlreadyClaimedRemotely
  | NativeRetentionOrdinalExhausted
  deriving stock (Eq, Show)
data NativeRetentionFailure = NativeRetentionFailure !NativeRetentionStage !NativeRetentionReason
  deriving stock (Eq, Show)

maximumNativeRetentionPayloadBytes :: Int64
maximumNativeRetentionPayloadBytes = 256 * 1024 * 1024

mkNativeAllocationAddress :: NativeAllocationScope -> Either Text NativeAllocationAddress
mkNativeAllocationAddress scope = do
  case nativeAllocationContext scope of
    NativeSuppliedScenarioDigest value -> require (canonicalSha value) "native allocation scenario digest is not canonical SHA256"
    NativeDirectLocalAcquisition value -> require (component 128 value) "native allocation local acquisition is invalid"
  require (component 128 (nativeAllocationRow scope)) "native allocation row is invalid"
  require
    (component 128 (nativeAllocationAcquisitionId scope))
    "native allocation acquisition identifier is invalid"
  require
    ( Source.stampAlgorithm (nativeAllocationSource scope) == Source.sourceDigestAlgorithm
        && canonicalSha (Source.stampSha256 (nativeAllocationSource scope))
    )
    "native allocation source stamp differs"
  require
    (canonicalSha (nativeAllocationRecipeSha256 scope))
    "native allocation recipe digest differs"
  let address = "jitml-checkpoints/native-rl-allocations-v1/" <> digest (scopeBytes scope) <> "/claim.cbor"
  pure (NativeAllocationAddress scope address)

mkNativeRetentionPhaseLabel :: Text -> Either Text NativeRetentionPhaseLabel
mkNativeRetentionPhaseLabel label = do
  require
    ( Text.length label >= 1
        && Text.length label <= 64
        && Text.all (\c -> c `elem` ("abcdefghijklmnopqrstuvwxyz0123456789.-" :: String)) label
    )
    "native retention phase label is invalid"
  pure (NativeRetentionPhaseLabel label)

nativeAllocationAddressKey :: NativeAllocationAddress -> Text
nativeAllocationAddressKey (NativeAllocationAddress _ key) = key
nativeAllocationAddressScope :: NativeAllocationAddress -> NativeAllocationScope
nativeAllocationAddressScope (NativeAllocationAddress scope _) = scope
nativeRetentionPublication :: NativeRetentionSession -> NativePublicationData
nativeRetentionPublication (NativeRetentionSession _ _ publication _) = publication
nativeRetainedAllocationData :: RetainedNativeAllocation -> NativeRetainedObjectData
nativeRetainedAllocationData (RetainedNativeAllocation _ _ object) = object
nativeRetainedPhaseData :: RetainedNativePhase -> NativeRetainedObjectData
nativeRetainedPhaseData (RetainedNativePhase object) = object

captureNativeRetentionSession
  :: NativeRetentionMode -> App (Either NativeRetentionFailure NativeRetentionSession)
captureNativeRetentionSession mode =
  captureSession NativeDefaultPublicationResolution mode Worker.workerServiceBootConfigPath "."

-- | Explicit real filesystem configuration, without global cwd changes or a
-- settings/callback factory. This is labelled separately from default ambient
-- resolution. A producer must capture its own default publication internally.
captureNativeRetentionSessionAt
  :: NativeRetentionMode
  -> FilePath
  -> FilePath
  -> App (Either NativeRetentionFailure NativeRetentionSession)
captureNativeRetentionSessionAt mode bootPath repositoryRoot =
  captureSession
    (NativeExplicitPublicationResolution configurationIdentity)
    mode
    bootPath
    repositoryRoot
 where
  configurationIdentity =
    digest $
      encode $
        CBOR.encodeListLen 3
          <> CBOR.encodeString "jitml-native-explicit-publication-paths-v1"
          <> CBOR.encodeString (Text.pack bootPath)
          <> CBOR.encodeString (Text.pack repositoryRoot)

captureSession
  :: NativePublicationResolution
  -> NativeRetentionMode
  -> FilePath
  -> FilePath
  -> App (Either NativeRetentionFailure NativeRetentionSession)
captureSession resolution mode bootPath repositoryRoot = do
  root <- Writer.localCheckpointRoot
  liftIO $ boundary NativePublicationCapture $ do
    _ <- evaluate (length root)
    _ <- evaluate mode
    resolved <- Worker.resolveWorkerLiveContextAt bootPath repositoryRoot
    case resolved of
      -- Never propagate configuration text or exception rendering: they may
      -- contain secrets from the actual config/subprocess command.
      Left _ -> pure (failed NativePublicationCapture NativePublicationConfigurationInvalid)
      Right Nothing
        | mode == RequireLiveNativeRetention ->
            pure (failed NativePublicationCapture NativePublicationRequired)
      Right context -> do
        let rootHash = digest (Encoding.encodeUtf8 (Text.pack root))
            settings = Worker.workerLiveMinIOSettings <$> context
            publication = case context of
              Nothing -> NativeLocalPublication resolution rootHash
              Just actual ->
                NativeConfiguredPublication
                  resolution
                  rootHash
                  (settingsIdentity (Worker.workerLiveMinIOSettings actual))
                  (Worker.workerLiveUsesMountedServices actual)
        _ <- evaluate (BS.length (publicationBytes publication))
        Right . NativeRetentionSession root settings publication <$> SingleUse.newSingleUse

-- The fixed key excludes claim payload and every newly generated attempt ID.
scopeBytes :: NativeAllocationScope -> BS.ByteString
scopeBytes scope =
  encode $
    CBOR.encodeListLen 8
      <> CBOR.encodeString "jitml-native-allocation-scope-v1"
      <> ( case nativeAllocationContext scope of
             NativeSuppliedScenarioDigest value -> CBOR.encodeString "supplied-scenario" <> CBOR.encodeString value
             NativeDirectLocalAcquisition value -> CBOR.encodeString "direct-local" <> CBOR.encodeString value
         )
      <> CBOR.encodeString (nativeAllocationRow scope)
      <> CBOR.encodeWord64 (Source.stampAlgorithm (nativeAllocationSource scope))
      <> CBOR.encodeString (Source.stampSha256 (nativeAllocationSource scope))
      <> CBOR.encodeString (nativeAllocationRecipeSha256 scope)
      <> CBOR.encodeString (nativeAllocationAcquisitionId scope)

publicationBytes :: NativePublicationData -> BS.ByteString
publicationBytes publication =
  encode $
    CBOR.encodeListLen 7
      <> CBOR.encodeString "jitml-native-retention-publication-v1"
      <> CBOR.encodeString "jitml-checkpoints"
      <> case publication of
        NativeLocalPublication resolution root ->
          resolutionEncoding resolution
            <> CBOR.encodeString "local"
            <> CBOR.encodeString root
            <> CBOR.encodeString ""
            <> CBOR.encodeBool False
        NativeConfiguredPublication resolution root endpoint fromBootConfig ->
          resolutionEncoding resolution
            <> CBOR.encodeString "configured"
            <> CBOR.encodeString root
            <> CBOR.encodeString endpoint
            <> CBOR.encodeBool fromBootConfig

resolutionEncoding :: NativePublicationResolution -> CBOR.Encoding
resolutionEncoding resolution =
  CBOR.encodeBytes $
    encode $
      CBOR.encodeListLen 2
        <> case resolution of
          NativeDefaultPublicationResolution -> CBOR.encodeString "default" <> CBOR.encodeString ""
          NativeExplicitPublicationResolution identity -> CBOR.encodeString "explicit-filesystem" <> CBOR.encodeString identity

settingsIdentity :: MinIO.MinIOSettings -> Text
settingsIdentity settings =
  digest $
    encode $
      CBOR.encodeListLen 4
        <> CBOR.encodeString "jitml-native-retention-endpoint-v1"
        <> CBOR.encodeString (MinIO.minioEndpoint settings)
        <> CBOR.encodeString (MinIO.minioRegion settings)
        <> CBOR.encodeString (MinIO.minioRequestPathPrefix settings)

encode :: CBOR.Encoding -> BS.ByteString
encode = LBS.toStrict . CBOR.toLazyByteString
digest :: BS.ByteString -> Text
digest =
  Text.pack
    . concatMap
      (\byte -> [intToDigit (fromIntegral byte `div` 16), intToDigit (fromIntegral byte `mod` 16)])
    . BS.unpack
    . SHA256.hash
canonicalSha :: Text -> Bool
canonicalSha value = Text.length value == 64 && Text.all (`elem` ("0123456789abcdef" :: String)) value
component :: Int -> Text -> Bool
component bound value =
  Text.length value >= 1
    && Text.length value <= bound
    && Text.all
      (`elem` ("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789./_-" :: String))
      value
require :: Bool -> Text -> Either Text ()
require condition reason = unless condition (Left reason)

claimNativeAllocation
  :: NativeRetentionSession
  -> NativeAllocationAddress
  -> LBS.ByteString
  -> IO (Either NativeRetentionFailure (RetainedNativeAllocation, NativeRetentionCursor))
claimNativeAllocation session address supplied =
  boundary NativeAllocationClaim $ do
    let NativeRetentionSession _ _ publication guard = session
    consumed <- SingleUse.tryConsumeSingleUse guard
    if not consumed
      then pure (failed NativeAllocationClaim NativeRetentionAlreadyConsumed)
      else do
        -- A private address still may be supplied as an unevaluated exception.
        _ <- evaluate (BS.length (scopeBytes (nativeAllocationAddressScope address)))
        materialized <- boundedPayload NativeAllocationClaim supplied
        case materialized of
          Left reason -> pure (Left reason)
          Right payload -> do
            let bytes =
                  encode
                    ( CBOR.encodeListLen 4
                        <> CBOR.encodeString "jitml-native-allocation-claim-v1"
                        <> CBOR.encodeBytes (scopeBytes (nativeAllocationAddressScope address))
                        <> CBOR.encodeBytes (publicationBytes publication)
                        <> CBOR.encodeBytes payload
                    )
            written <- retainBytes NativeAllocationClaim True session (nativeAllocationAddressKey address) bytes
            case written of
              Left reason -> pure (Left reason)
              Right object -> do
                let allocation = RetainedNativeAllocation address publication object
                next <- SingleUse.newSingleUse
                pure (Right (allocation, NativeRetentionCursor session allocation object 0 next))

appendNativeRetentionPhase
  :: NativeRetentionCursor
  -> NativeRetentionPhaseLabel
  -> LBS.ByteString
  -> IO (Either NativeRetentionFailure (RetainedNativePhase, NativeRetentionCursor))
appendNativeRetentionPhase suppliedCursor suppliedLabel supplied =
  boundary NativePhaseAppend $ do
    let NativeRetentionCursor session allocation previous ordinal guard = suppliedCursor
        NativeRetentionPhaseLabel label = suppliedLabel
    consumed <- SingleUse.tryConsumeSingleUse guard
    if not consumed
      then pure (failed NativePhaseAppend NativeRetentionAlreadyConsumed)
      else
        if ordinal == maxBound
          then pure (failed NativePhaseAppend NativeRetentionOrdinalExhausted)
          else do
            _ <- evaluate (Text.length label)
            materialized <- boundedPayload NativePhaseAppend supplied
            case materialized of
              Left reason -> pure (Left reason)
              Right payload -> do
                let RetainedNativeAllocation address publication claim = allocation
                    bytes =
                      encode
                        ( CBOR.encodeListLen 9
                            <> CBOR.encodeString "jitml-native-retention-phase-v1"
                            <> CBOR.encodeString (nativeAllocationAddressKey address)
                            <> CBOR.encodeString (nativeRetainedObjectSha256 claim)
                            <> CBOR.encodeBytes (publicationBytes publication)
                            <> CBOR.encodeWord64 ordinal
                            <> CBOR.encodeString (nativeRetainedObjectKey previous)
                            <> CBOR.encodeString (nativeRetainedObjectSha256 previous)
                            <> CBOR.encodeString label
                            <> CBOR.encodeBytes payload
                        )
                    key =
                      "jitml-checkpoints/native-rl-allocations-v1/"
                        <> digest (scopeBytes (nativeAllocationAddressScope address))
                        <> "/phases/"
                        <> digest bytes
                        <> ".cbor"
                written <- retainBytes NativePhaseAppend False session key bytes
                case written of
                  Left reason -> pure (Left reason)
                  Right object -> do
                    next <- SingleUse.newSingleUse
                    pure
                      ( Right
                          (RetainedNativePhase object, NativeRetentionCursor session allocation object (ordinal + 1) next)
                      )

-- At most limit+1 bytes are inspected before checking the payload limit. An
-- infinite/oversized lazy tail is neither hashed nor materialized in full.
boundedPayload
  :: NativeRetentionStage -> LBS.ByteString -> IO (Either NativeRetentionFailure BS.ByteString)
boundedPayload stage supplied = do
  let bytes = LBS.toStrict (LBS.take (maximumNativeRetentionPayloadBytes + 1) supplied)
  count <- evaluate (BS.length bytes)
  pure $
    if toInteger count > toInteger maximumNativeRetentionPayloadBytes
      then failed stage NativeRetentionPayloadTooLarge
      else Right bytes

retainBytes
  :: NativeRetentionStage
  -> Bool
  -> NativeRetentionSession
  -> Text
  -> BS.ByteString
  -> IO (Either NativeRetentionFailure NativeRetainedObjectData)
retainBytes stage fresh (NativeRetentionSession root settings publication _) key payload = do
  -- Address/descriptor overhead has fixed bounded fields. This is a request
  -- encoding limit; the existing remote interpreter's download is not bounded
  -- by this module, and no such read-allocation guarantee is claimed.
  count <- evaluate (BS.length payload)
  if toInteger count > toInteger maximumNativeRetentionPayloadBytes + 8192
    then pure (failed stage NativeRetentionPayloadTooLarge)
    else do
      let sha = digest payload
      _ <- evaluate (Text.length sha)
      stored <- Store.writeObjectIfAbsent root key (LBS.fromStrict payload)
      case stored of
        Left errorValue -> pure (failed stage (localReason errorValue))
        Right (Store.ObjectAlreadyPresent _) | fresh -> pure (failed stage NativeRetentionAlreadyClaimedLocally)
        Right actual -> do
          let actualKey = case actual of Store.ObjectCreated value -> value; Store.ObjectAlreadyPresent value -> value
          if actualKey /= key
            then pure (failed stage NativeRetentionLocalReadbackMismatch)
            else do
              remote <- case settings of
                Nothing -> pure (Right ())
                Just actualSettings -> do
                  result <-
                    MinIO.runMinIOSubprocess actualSettings $
                      if fresh
                        then createFreshRemote (Store.checkpointObjectRef key) payload
                        else do
                          written <- Writer.writeVerifiedRemoteArtifact (Store.checkpointObjectRef key) payload
                          pure (mapLeft remoteReason written)
                  pure (either (failed stage) Right result)
              case remote of
                Left reason -> pure (Left reason)
                Right () -> do
                  case Store.objectPathForKey root key of
                    Left _ -> pure (failed stage NativeRetentionLocalReadbackMismatch)
                    Right path -> do
                      -- Strict bounded IO stays inside its handle bracket. A
                      -- mismatching extra byte never leaves a lazy unread handle.
                      matches <- withBinaryFile path ReadMode $ \handle -> do
                        actualBytes <- BS.hGet handle (count + 1)
                        evaluate (actualBytes == payload)
                      pure $
                        if matches
                          then Right (NativeRetainedObjectData key sha (fromIntegral count) publication)
                          else failed stage NativeRetentionLocalReadbackMismatch

-- The generic Writer artifact helper is intentionally idempotent; allocation
-- acquisition instead rejects even an identical remote conditional conflict.
createFreshRemote
  :: Capabilities.ObjectRef
  -> BS.ByteString
  -> MinIO.MinIOSubprocess (Either NativeRetentionReason ())
createFreshRemote ref payload = do
  written <- Capabilities.putBlobBytesIfAbsent ref payload
  case written of
    Left (SEConflict _) -> pure (Left NativeRetentionAlreadyClaimedRemotely)
    Left errorValue -> pure (Left (remoteReason errorValue))
    Right _ -> do
      readback <- Capabilities.minioReadBytes ref
      pure $ case readback of
        Left errorValue -> Left (remoteReason errorValue)
        Right bytes | bytes == payload -> Right ()
        Right _ -> Left NativeRetentionRemoteReadbackMismatch

localReason :: Store.CheckpointWriteError -> NativeRetentionReason
localReason errorValue = case errorValue of
  Store.CheckpointWriteInvalid _ -> NativeRetentionLocalInvalid
  Store.CheckpointWriteObjectConflict _ _ -> NativeRetentionLocalConflict
  Store.CheckpointWritePointerConflict _ -> NativeRetentionLocalConflict
  Store.CheckpointWriteIOFailure _ _ -> NativeRetentionLocalFailure
remoteReason :: ServiceError -> NativeRetentionReason
remoteReason errorValue = case errorValue of
  SEConflict _ -> NativeRetentionRemoteConflict
  SEUnauthorized _ -> NativeRetentionRemoteUnauthorized
  SETimeout _ -> NativeRetentionRemoteTimeout
  SETransient _ -> NativeRetentionRemoteUnavailable
  SENotFound _ -> NativeRetentionRemoteMissing

failed :: NativeRetentionStage -> NativeRetentionReason -> Either NativeRetentionFailure value
failed stage reason = Left (NativeRetentionFailure stage reason)
boundary
  :: NativeRetentionStage
  -> IO (Either NativeRetentionFailure value)
  -> IO (Either NativeRetentionFailure value)
boundary stage action = do
  attempted <- tryAny $ do
    outer <- action >>= evaluate
    case outer of
      Left failure@(NativeRetentionFailure actualStage reason) -> do
        _ <- evaluate (actualStage `seq` reason)
        pure (Left failure)
      Right value -> pure (Right value)
  -- safe tryAny deliberately propagates asynchronous exceptions.
  pure (fromRight (failed stage NativeRetentionSynchronousFailure) attempted)

-- Physical read capsules establish only that this concrete captured session
-- fetched the exact bytes. They are not write ACKs, source authentication,
-- exhaustive attempt inventories, learning or native publication authority.
data NativePhysicalReadFailure
  = NativePhysicalReadScopeMismatch
  | NativePhysicalReadAddressInvalid
  | NativePhysicalReadSizeInvalid
  | NativePhysicalReadLocalFailed
  | NativePhysicalReadRemoteFailed
  | NativePhysicalReadBytesMismatch
  | NativePhysicalReadCheckpointRefused
  | NativePhysicalReadSynchronousFailure
  deriving stock (Eq, Show)

data NativeReadObject = NativeReadObject !NativeRetainedObjectData !BS.ByteString

nativeReadObjectReference :: NativeReadObject -> NativeRetainedObjectData
nativeReadObjectReference (NativeReadObject actual _) = actual
nativeReadObjectBytes :: NativeReadObject -> BS.ByteString
nativeReadObjectBytes (NativeReadObject _ actual) = actual

-- The recorded publication must be the SAME captured local/remote scope. For
-- configured publication both local and remote bytes must match exactly. The
-- local cap+1 slice precedes strict allocation; HasMinIO returns strict bytes,
-- so its own network allocation precedes this module's post-read bound check.
readNativeRetainedObject
  :: NativeRetentionSession
  -> NativeRetainedObjectData
  -> IO (Either NativePhysicalReadFailure NativeReadObject)
readNativeRetainedObject session reference = physicalReadBoundary $ do
  _ <- evaluate session
  _ <- evaluate reference
  let NativeRetentionSession root settings publication _ = session
  case validateReadReference publication reference of
    Left failure -> pure (Left failure)
    Right () -> do
      local <- Store.readObject root (nativeRetainedObjectKey reference)
      case local of
        Left _ -> pure (Left NativePhysicalReadLocalFailed)
        Right lazyBytes -> do
          bytes <-
            evaluate
              (LBS.toStrict (LBS.take (fromIntegral (nativeRetainedObjectBytes reference) + 1) lazyBytes))
          case exactReadBytes reference bytes of
            Left failure -> pure (Left failure)
            Right () -> case settings of
              Nothing -> pure (Right (NativeReadObject reference bytes))
              Just actual -> do
                remote <-
                  MinIO.runMinIOSubprocess
                    actual
                    (Capabilities.minioReadBytes (Store.checkpointObjectRef (nativeRetainedObjectKey reference)))
                pure $ case remote of
                  Left _ -> Left NativePhysicalReadRemoteFailed
                  Right remoteBytes
                    | remoteBytes == bytes -> Right (NativeReadObject reference bytes)
                    | otherwise -> Left NativePhysicalReadBytesMismatch

validateReadReference
  :: NativePublicationData
  -> NativeRetainedObjectData
  -> Either NativePhysicalReadFailure ()
validateReadReference publication reference = do
  unless
    (nativeRetainedObjectPublication reference == publication)
    (Left NativePhysicalReadScopeMismatch)
  unless
    ( toInteger (nativeRetainedObjectBytes reference)
        <= toInteger maximumNativeRetentionPayloadBytes + 4096
    )
    (Left NativePhysicalReadSizeInvalid)
  unless
    (isCanonicalSha (nativeRetainedObjectSha256 reference) && validKey)
    (Left NativePhysicalReadAddressInvalid)
 where
  validKey = case Text.splitOn "/" (nativeRetainedObjectKey reference) of
    ["jitml-checkpoints", "native-rl-allocations-v1", scope, "claim.cbor"] -> isCanonicalSha scope
    ["jitml-checkpoints", "native-rl-allocations-v1", scope, "phases", filename] ->
      isCanonicalSha scope && filename == nativeRetainedObjectSha256 reference <> ".cbor"
    _ -> False

exactReadBytes :: NativeRetainedObjectData -> BS.ByteString -> Either NativePhysicalReadFailure ()
exactReadBytes reference bytes =
  unless
    ( toInteger (BS.length bytes) == toInteger (nativeRetainedObjectBytes reference)
        && digest bytes == nativeRetainedObjectSha256 reference
    )
    (Left NativePhysicalReadBytesMismatch)

isCanonicalSha :: Text -> Bool
isCanonicalSha value = Text.length value == 64 && Text.all (`elem` ("0123456789abcdef" :: String)) value

data NativeReadCheckpoint
  = NativeReadCheckpoint
      !Store.AdmittedExecutionCheckpoint
      !(Maybe Store.AdmittedExecutionCheckpoint)
      !NativePublicationData

nativeReadCheckpointLocal :: NativeReadCheckpoint -> Store.AdmittedExecutionCheckpoint
nativeReadCheckpointLocal (NativeReadCheckpoint actual _ _) = actual
nativeReadCheckpointEffective :: NativeReadCheckpoint -> Store.AdmittedExecutionCheckpoint
nativeReadCheckpointEffective (NativeReadCheckpoint local Nothing _) = local
nativeReadCheckpointEffective (NativeReadCheckpoint _ (Just remote) _) = remote
nativeReadCheckpointPublication :: NativeReadCheckpoint -> NativePublicationData
nativeReadCheckpointPublication (NativeReadCheckpoint _ _ actual) = actual

-- Exact new immutable address only, with the captured session's fixed remote
-- settings. No latest pointer, user fetcher, admission callback or replacement
-- completed proof enters this concrete local/remote physical read boundary.
readNativeExecutionCheckpoint
  :: NativeRetentionSession
  -> Text
  -> Text
  -> IO (Either NativePhysicalReadFailure NativeReadCheckpoint)
readNativeExecutionCheckpoint session experiment manifestSha = physicalReadBoundary $ do
  _ <- evaluate session
  _ <- evaluate (Text.length experiment + Text.length manifestSha)
  let NativeRetentionSession root settings publication _ = session
  local <- Store.admitLocalExecutionCheckpointAt root experiment manifestSha
  case local of
    Left _ -> pure (Left NativePhysicalReadCheckpointRefused)
    Right actual
      | not (sameAddress actual) -> pure (Left NativePhysicalReadBytesMismatch)
      | otherwise -> case settings of
          Nothing -> pure (Right (NativeReadCheckpoint actual Nothing publication))
          Just selected -> do
            remote <-
              MinIO.runMinIOSubprocess selected (Store.admitExecutionCheckpointAt experiment manifestSha)
            pure $ case remote of
              Left _ -> Left NativePhysicalReadCheckpointRefused
              Right remoteActual
                | sameAddress remoteActual && sameCheckpoint actual remoteActual ->
                    Right (NativeReadCheckpoint actual (Just remoteActual) publication)
                | otherwise -> Left NativePhysicalReadBytesMismatch
 where
  sameAddress actual = Store.admittedCheckpointManifestSha (Store.admittedExecutionCheckpoint actual) == manifestSha
  sameCheckpoint local remote =
    TrainingBudget.encodeCompletedTraining (Store.admittedExecutionCompletedTraining local)
      == TrainingBudget.encodeCompletedTraining (Store.admittedExecutionCompletedTraining remote)
      && weightBytes local == weightBytes remote
  weightBytes =
    fmap (\loaded -> (Store.loadedWeightTensor loaded, Store.loadedWeightJmw1Bytes loaded))
      . Store.admittedCheckpointWeights
      . Store.admittedExecutionCheckpoint

physicalReadBoundary
  :: IO (Either NativePhysicalReadFailure a) -> IO (Either NativePhysicalReadFailure a)
physicalReadBoundary action = do
  attempted <- tryAny (action >>= evaluate)
  pure (fromRight (Left NativePhysicalReadSynchronousFailure) attempted)

-- Exact digest of the existing versioned publication DATA encoding. This
-- does not observe configuration or construct a session, ACK or authority.
nativePublicationDigest :: NativePublicationData -> Text
nativePublicationDigest = digest . publicationBytes

-- Closed detached classes. Allocation/phase keys retain their original,
-- disjoint validator; no arbitrary artifact class or caller cap is accepted.
data NativeDetachedArtifactKind
  = NativeQualificationArtifact
  | NativeEvaluationReplayArtifact
  | NativeStoreLoadedReplayArtifact
  deriving stock (Eq, Show)

maximumNativeDetachedArtifactBytes :: NativeDetachedArtifactKind -> Word64
maximumNativeDetachedArtifactBytes kind = case kind of
  NativeQualificationArtifact -> 4 * 1024 * 1024
  NativeEvaluationReplayArtifact -> fromIntegral maximumNativeRetentionPayloadBytes + 4096
  NativeStoreLoadedReplayArtifact -> fromIntegral maximumNativeRetentionPayloadBytes + 4096

-- Ordinary address DATA only. Product experiment namespaces are bounded
-- path segments (e.g. product-row-*), rather than SHA256 identities.
nativeDetachedArtifactKey
  :: NativeDetachedArtifactKind
  -> Text
  -> Text
  -> Either NativePhysicalReadFailure Text
nativeDetachedArtifactKey kind experiment sha = do
  unless
    (detachedExperiment experiment && isCanonicalSha sha)
    (Left NativePhysicalReadAddressInvalid)
  pure
    ( "jitml-checkpoints/"
        <> experiment
        <> "/artifacts/"
        <> detachedKindText kind
        <> "/"
        <> sha
        <> ".cbor"
    )

data NativeReadDetachedArtifact
  = NativeReadDetachedArtifact
      !NativeDetachedArtifactKind
      !NativeRetainedObjectData
      !BS.ByteString

nativeReadDetachedArtifactKind :: NativeReadDetachedArtifact -> NativeDetachedArtifactKind
nativeReadDetachedArtifactKind (NativeReadDetachedArtifact actual _ _) = actual
nativeReadDetachedArtifactReference :: NativeReadDetachedArtifact -> NativeRetainedObjectData
nativeReadDetachedArtifactReference (NativeReadDetachedArtifact _ actual _) = actual
nativeReadDetachedArtifactBytes :: NativeReadDetachedArtifact -> BS.ByteString
nativeReadDetachedArtifactBytes (NativeReadDetachedArtifact _ _ actual) = actual

-- Only this actual IO route constructs the private physical read. No
-- decoder, reference DATA, supplied bytes, fetch callback or publication
-- digest constructs it. It establishes byte reads, not receipt semantics,
-- parent authentication, write freshness, model execution or qualification.
readNativeDetachedArtifact
  :: NativeRetentionSession
  -> NativeDetachedArtifactKind
  -> NativeRetainedObjectData
  -> IO (Either NativePhysicalReadFailure NativeReadDetachedArtifact)
readNativeDetachedArtifact session kind reference = physicalReadBoundary $ do
  _ <- evaluate session
  _ <- evaluate kind
  _ <- evaluate reference
  let NativeRetentionSession root settings publication _ = session
  case validateDetachedReference kind publication reference of
    Left failure -> pure (Left failure)
    Right () -> case Store.objectPathForKey root (nativeRetainedObjectKey reference) of
      Left _ -> pure (Left NativePhysicalReadAddressInvalid)
      Right path -> do
        -- The validated recorded count is within its closed per-kind cap
        -- and Int range. Read at most count+1 strict bytes INSIDE the handle
        -- bracket: no lazy unread file handle or full-object read escapes.
        local <- tryAny $ withBinaryFile path ReadMode $ \handle ->
          BS.hGet handle (fromIntegral (nativeRetainedObjectBytes reference) + 1)
        case local of
          Left _ -> pure (Left NativePhysicalReadLocalFailed)
          Right bytes -> case exactReadBytes reference bytes of
            Left failure -> pure (Left failure)
            Right () -> case settings of
              Nothing -> pure (Right (NativeReadDetachedArtifact kind reference bytes))
              Just actual -> do
                -- HasMinIO returns a strict ByteString, so network-side
                -- allocation precedes these post-read cap/count/SHA checks.
                -- No streaming remote allocation bound is claimed here.
                remote <-
                  MinIO.runMinIOSubprocess
                    actual
                    (Capabilities.minioReadBytes (Store.checkpointObjectRef (nativeRetainedObjectKey reference)))
                pure $ case remote of
                  Left _ -> Left NativePhysicalReadRemoteFailed
                  Right remoteBytes -> case exactReadBytes reference remoteBytes of
                    Right () | remoteBytes == bytes -> Right (NativeReadDetachedArtifact kind reference bytes)
                    _ -> Left NativePhysicalReadBytesMismatch

validateDetachedReference
  :: NativeDetachedArtifactKind
  -> NativePublicationData
  -> NativeRetainedObjectData
  -> Either NativePhysicalReadFailure ()
validateDetachedReference kind publication reference = do
  unless
    (nativeRetainedObjectPublication reference == publication)
    (Left NativePhysicalReadScopeMismatch)
  let count = nativeRetainedObjectBytes reference
  unless
    ( count > 0
        && count <= maximumNativeDetachedArtifactBytes kind
        && toInteger count < toInteger (maxBound :: Int)
    )
    (Left NativePhysicalReadSizeInvalid)
  experiment <- case Text.splitOn "/" (nativeRetainedObjectKey reference) of
    ["jitml-checkpoints", actual, "artifacts", tag, filename]
      | tag == detachedKindText kind && filename == nativeRetainedObjectSha256 reference <> ".cbor" ->
          Right actual
    _ -> Left NativePhysicalReadAddressInvalid
  expected <- nativeDetachedArtifactKey kind experiment (nativeRetainedObjectSha256 reference)
  unless
    (expected == nativeRetainedObjectKey reference)
    (Left NativePhysicalReadAddressInvalid)

detachedKindText :: NativeDetachedArtifactKind -> Text
detachedKindText kind = case kind of
  NativeQualificationArtifact -> "native-qualification"
  NativeEvaluationReplayArtifact -> "native-evaluation-replay"
  NativeStoreLoadedReplayArtifact -> "native-store-loaded-replay"

detachedExperiment :: Text -> Bool
detachedExperiment value =
  not (Text.null value)
    && Text.length value <= 1024
    && value /= "."
    && value /= ".."
    && Text.all
      (`elem` ("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-" :: String))
      value
