{-# LANGUAGE OverloadedStrings #-}

-- | Ordinary GC retention DATA only. A protected key is neither admission nor
-- evidence of an authenticated producer, learning or qualification. No object
-- is written or deleted here. Store stays below the receipt/retention modules.
module JitML.Checkpoint.NativeQualificationGc
  ( NativeQualificationGcReachability
  , nativeGcProtectedObjectKeys
  , nativeGcSelectedMetadataKeys
  , nativeGcKeptManifests
  , refineNativeQualificationGcReachability
  , loadNativeQualificationGcReachability
  , loadLocalNativeQualificationGcReachability
  ) where

import Control.Exception (IOException, try)
import Control.Monad (foldM, unless)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Char (intToDigit)
import Data.Either.Combinators (mapLeft)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory, pathIsSymbolicLink)
import System.IO (IOMode (ReadMode), withBinaryFile)
import System.IO.Error (isDoesNotExistError)

import JitML.Checkpoint.Format qualified as Format
import JitML.Checkpoint.NativePhase.Types (digestBytes)
import JitML.Checkpoint.NativeQualificationReceiptData qualified as Metadata
import JitML.Checkpoint.NativeRetention qualified as Retain
import JitML.Checkpoint.Store qualified as Store
import JitML.Plan.Plan qualified as Plan
import JitML.Product.ValidationRecord (sha256Hex)
import JitML.Service.Capabilities (BucketName (..), HasMinIO (..), ObjectKey (..), ObjectRef (..))
import JitML.Service.Retry (ServiceError (SETransient))
import JitML.Training.Budget qualified as Training

-- Private ordinary DATA constructor, not a physical-read/retention capability.
data NativeQualificationGcReachability
  = NativeQualificationGcReachability
      !(Set Text)
      !(Set Text)
      !(Set Text)
  deriving stock (Eq, Show)

nativeGcProtectedObjectKeys :: NativeQualificationGcReachability -> [Text]
nativeGcProtectedObjectKeys (NativeQualificationGcReachability protected _ _) = Set.toAscList protected

nativeGcSelectedMetadataKeys :: NativeQualificationGcReachability -> [Text]
nativeGcSelectedMetadataKeys (NativeQualificationGcReachability _ selected _) = Set.toAscList selected

emptyReachability :: NativeQualificationGcReachability
emptyReachability = NativeQualificationGcReachability Set.empty Set.empty Set.empty

-- Use exactly the caller's existing complete physical GC retention selection,
-- including immediate parents and independent/intrinsic roots. No new policy.
nativeGcKeptManifests :: [Format.CheckpointManifest] -> Store.GcPlan -> [Format.CheckpointManifest]
nativeGcKeptManifests manifests plan =
  Map.elems
    ( Map.fromList
        [ (Format.manifestContentSha value, value)
        | value <- manifests
        , Format.manifestContentSha value `Set.member` kept
        ]
    )
 where
  kept = Set.fromList (Store.gcKeptManifestShas plan)

-- Supplied bytes are ordinary DATA. Real adapters below establish only their
-- physical key/hash/size; even those observations confer no source authority.
refineNativeQualificationGcReachability
  :: Text
  -> [Format.CheckpointManifest]
  -> [(Text, ByteString)]
  -> Either Text NativeQualificationGcReachability
refineNativeQualificationGcReachability experiment live objects = do
  _ <- prefixFor experiment
  manifests <- liveMap experiment live
  foldM (addMetadata experiment manifests) emptyReachability objects

liveMap :: Text -> [Format.CheckpointManifest] -> Either Text (Map Text Format.CheckpointManifest)
liveMap experiment = foldM insert Map.empty
 where
  insert current manifest = do
    require
      (Format.manifestExperiment manifest == experiment)
      "native GC live manifest belongs to another experiment"
    let sha = Format.manifestContentSha manifest
    case Map.lookup sha current of
      Just previous -> require (previous == manifest) "native GC duplicate live manifest SHA has different DATA"
      Nothing -> pure ()
    pure (Map.insert sha manifest current)

addMetadata
  :: Text
  -> Map Text Format.CheckpointManifest
  -> NativeQualificationGcReachability
  -> (Text, ByteString)
  -> Either Text NativeQualificationGcReachability
addMetadata experiment manifests (NativeQualificationGcReachability protected selected seen) (key, bytes) = do
  require (key `Set.notMember` seen) "native GC metadata object is duplicated"
  require
    (toInteger (BS.length bytes) <= Metadata.maximumNativeQualificationReceiptBytes)
    "native GC metadata exceeds its four MiB bound"
  sha <- metadataSha experiment key
  require (sha256Hex bytes == sha) "native GC metadata physical SHA differs from its exact key"
  metadata <-
    either
      (const (Left "native GC metadata canonical decoder refused"))
      Right
      (Metadata.decodeNativeQualificationReceiptData bytes)
  let fields = Metadata.nativeQualificationReceiptFields metadata
      manifestSha = hexDigest (digestBytes (Metadata.nativeReceiptManifest fields))
      observed = Set.insert key seen
  require
    (Metadata.nativeReceiptExperiment fields == experiment)
    "native GC metadata experiment differs from its physical namespace"
  case Map.lookup manifestSha manifests of
    Nothing -> pure (NativeQualificationGcReachability protected selected observed)
    Just manifest -> do
      completed <-
        maybe
          (Left "native GC live native receipt has no completed training")
          Right
          (Format.manifestCompletedTraining manifest)
      require
        (Metadata.nativeReceiptCompletedTrainingBytes fields == Training.encodeCompletedTraining completed)
        "native GC metadata whole completion differs from its live manifest"
      require
        ( Format.manifestPlanId manifest == Just (Training.completedTrainingPlanId completed)
            && hexDigest (digestBytes (Metadata.nativeReceiptWholePlan fields))
              == Plan.planIdText (Training.completedTrainingPlanId completed)
        )
        "native GC metadata whole plan differs from its live manifest"
      let references =
            Metadata.nativeReceiptAllocation fields
              : Metadata.nativeReceiptPhases fields
                <> map Metadata.nativeReceiptReplayObject (Metadata.nativeReceiptReplays fields)
          keys = key : map Retain.nativeRetainedObjectKey references
      pure
        ( NativeQualificationGcReachability
            (foldr Set.insert protected keys)
            (Set.insert key selected)
            observed
        )

-- Concrete HasMinIO uses its existing complete ordered page collector. Reject
-- foreign/duplicate/unordered responses independently before fetching bodies.
-- Existing minioReadBytes materializes strict network bytes BEFORE this cap;
-- no stronger remote allocation bound is claimed by this adapter.
loadNativeQualificationGcReachability
  :: (HasMinIO m)
  => Text
  -> [Format.CheckpointManifest]
  -> m (Either ServiceError NativeQualificationGcReachability)
loadNativeQualificationGcReachability experiment live = case (prefixFor experiment, liveMap experiment live) of
  (Left reason, _) -> pure (Left (SETransient reason))
  (_, Left reason) -> pure (Left (SETransient reason))
  (Right prefix, Right manifests) -> do
    listed <- listObjects (BucketName "jitml-checkpoints") (Text.drop (Text.length bucketPrefix) prefix)
    case listed of
      Left failure -> pure (Left failure)
      Right references -> case validateListing experiment references of
        Left reason -> pure (Left (SETransient reason))
        Right keys -> foldM (readOne manifests) (Right emptyReachability) (zip references keys)
 where
  readOne _ failure@(Left _) _ = pure failure
  readOne manifests (Right current) (reference, key) = do
    fetched <- minioReadBytes reference
    pure $ do
      bytes <- fetched
      mapLeft SETransient (addMetadata experiment manifests current (key, bytes))

validateListing :: Text -> [ObjectRef] -> Either Text [Text]
validateListing experiment references = do
  keys <- traverse one references
  require
    (keys == Set.toAscList (Set.fromList keys))
    "native GC metadata listing is not ordered unique DATA"
  pure keys
 where
  one reference = do
    require
      (objectBucket reference == BucketName "jitml-checkpoints")
      "native GC metadata listing returned another bucket"
    let key = bucketPrefix <> unObjectKey (objectKey reference)
    _ <- metadataSha experiment key
    pure key

-- Actual local files are opened only after exact closed-key validation, then
-- at most4MiB+one bytes are materialized. Missing directory means no new refs.
-- Process each body once rather than retaining every raw metadata buffer.
loadLocalNativeQualificationGcReachability
  :: FilePath
  -> Text
  -> [Format.CheckpointManifest]
  -> IO (Either Text NativeQualificationGcReachability)
loadLocalNativeQualificationGcReachability root experiment live = case (prefixFor experiment, liveMap experiment live) of
  (Left reason, _) -> pure (Left reason)
  (_, Left reason) -> pure (Left reason)
  (Right prefix, Right manifests) -> do
    attempted <- tryIO $ do
      directory <- either (fail . Text.unpack) pure (Store.objectPathForKey root (Text.dropEnd 1 prefix))
      -- lstat-like entry inspection must precede following the path. A
      -- dangling symlink exists even though doesDirectoryExist/doesPathExist
      -- both report False. Only an actual missing-entry error yields empty.
      entry <- tryIO (pathIsSymbolicLink directory)
      case entry of
        Left failure
          | isDoesNotExistError failure -> pure (Right emptyReachability)
          | otherwise -> pure (Left "native GC local metadata filesystem read failed")
        Right True -> pure (Left "native GC metadata directory is a symlink")
        Right False -> do
          directoryExists <- doesDirectoryExist directory
          if not directoryExists
            then pure (Left "native GC metadata prefix is not a directory")
            else do
              names <- listDirectory directory
              let keys = Set.toAscList (Set.fromList (map ((prefix <>) . Text.pack) names))
              case traverse (metadataSha experiment) keys of
                Left reason -> pure (Left reason)
                Right _ -> foldM (readOne manifests) (Right emptyReachability) keys
    pure $ case attempted of
      Left _ -> Left "native GC local metadata filesystem read failed"
      Right actual -> actual
 where
  readOne _ failure@(Left _) _ = pure failure
  readOne manifests (Right current) key = do
    path <- either (fail . Text.unpack) pure (Store.objectPathForKey root key)
    symlink <- pathIsSymbolicLink path
    regular <- doesFileExist path
    if symlink || not regular
      then pure (Left "native GC metadata object is not a regular non-symlink file")
      else do
        bytes <- withBinaryFile path ReadMode $ \handle ->
          BS.hGet
            handle
            (fromInteger Metadata.maximumNativeQualificationReceiptBytes + 1)
        pure (addMetadata experiment manifests current (key, bytes))

bucketPrefix :: Text
bucketPrefix = "jitml-checkpoints/"

prefixFor :: Text -> Either Text Text
prefixFor experiment = do
  _ <-
    mapLeft
      (Text.pack . show)
      ( Retain.nativeDetachedArtifactKey
          Retain.NativeQualificationArtifact
          experiment
          (Text.replicate 64 "0")
      )
  pure (bucketPrefix <> experiment <> "/artifacts/native-qualification/")

metadataSha :: Text -> Text -> Either Text Text
metadataSha experiment key = do
  prefix <- prefixFor experiment
  suffix <-
    maybe
      (Left "native GC metadata key is outside its exact experiment kind")
      Right
      (Text.stripPrefix prefix key)
  sha <-
    maybe
      (Left "native GC metadata key lacks its exact CBOR extension")
      Right
      (Text.stripSuffix ".cbor" suffix)
  expected <-
    mapLeft
      (Text.pack . show)
      (Retain.nativeDetachedArtifactKey Retain.NativeQualificationArtifact experiment sha)
  require (key == expected) "native GC metadata key is not its canonical content address"
  pure sha

hexDigest :: ByteString -> Text
hexDigest =
  Text.pack
    . concatMap
      ( \byte ->
          [intToDigit (fromIntegral byte `div` 16), intToDigit (fromIntegral byte `mod` 16)]
      )
    . BS.unpack

require :: Bool -> Text -> Either Text ()
require condition reason = unless condition (Left reason)

tryIO :: IO a -> IO (Either IOException a)
tryIO = try
