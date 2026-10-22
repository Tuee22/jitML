{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

module JitML.Cluster.PVSnapshot
  ( SnapshotRequest (..)
  , NodeIdentity (..)
  , TreeManifest
  , decodeTreeManifest
  , sameRestoredTree
  , FileDigest (..)
  , NodeCandidate (..)
  , NodeSnapshot (..)
  , SnapshotSelection (..)
  , encodeSelection
  , decodeSelection
  , VerifiedSnapshot
  , verifiedSelection
  , SnapshotStore (..)
  , SnapshotBackend (..)
  , RestoreOutcome (..)
  , preserveBeforeDelete
  , restoreBeforeMounts
  , invalidateForPurge
  , validateRequest
  ) where

import Control.Exception (mask, throwIO)
import Control.Monad (forM, unless, void, when)
import Data.Aeson
  ( FromJSON (..)
  , Result (..)
  , ToJSON (..)
  , Value (..)
  , eitherDecodeStrict'
  , encode
  , fromJSON
  , object
  , withObject
  , (.:)
  , (.=)
  )
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString (ByteString)
import Data.ByteString.Lazy qualified as LBS
import Data.Foldable (toList)
import Data.List (sort)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import GHC.Generics (Generic)

-- Stable role maps archives across newly created CIDs. Source CID is evidence,
-- never a request to attach a replacement node's volume to the old CID.
data NodeIdentity = NodeIdentity
  { nodeRole :: Text
  , nodeContainerId :: Text
  }
  deriving (Eq, Show, Generic)
instance FromJSON NodeIdentity
instance ToJSON NodeIdentity

-- Construct from the actual cluster and Storage.manualPVsFor, not arbitrary
-- caller-selected paths. registeredRoots are relative to the whole node root
-- /var/local/jitml-stateful-pv, e.g. jitml/.data/platform/minio/pv_0.
data SnapshotRequest = SnapshotRequest
  { snapshotLane :: Text
  , snapshotCluster :: Text
  , snapshotNodes :: [NodeIdentity]
  , registeredRoots :: [Text]
  }
  deriving (Eq, Show, Generic)
instance FromJSON SnapshotRequest
instance ToJSON SnapshotRequest

data TreeManifest = TreeManifest
  { treeRoot :: Text
  , treeRows :: [Value]
  , treeHardlinks :: [[Text]]
  }
  deriving (Eq, Show)

data FileDigest = FileDigest
  { digestBytes :: Integer
  , digestSHA256 :: Text
  }
  deriving (Eq, Show, Generic)
instance FromJSON FileDigest
instance ToJSON FileDigest

-- The backend must hash the closed archive, drain tar, and retain all statuses.
-- Payload is an exclusive generation-relative path; never a .build raw receipt.
data NodeCandidate = NodeCandidate
  { candidateNode :: NodeIdentity
  , candidateArchive :: FilePath
  , candidateDigest :: FileDigest
  , candidateBefore :: ByteString
  , candidateAfter :: ByteString
  , candidateScratch :: ByteString
  }

data NodeSnapshot = NodeSnapshot
  { savedNode :: NodeIdentity
  , savedArchive :: FilePath
  , savedDigest :: FileDigest
  , savedManifest :: ByteString
  }
  deriving (Eq, Show)

instance ToJSON NodeSnapshot where
  toJSON saved =
    object
      [ "node" .= savedNode saved
      , "archive" .= savedArchive saved
      , "digest" .= savedDigest saved
      , "manifest_utf8" .= Text.decodeUtf8 (savedManifest saved)
      ]
instance FromJSON NodeSnapshot where
  parseJSON = withObject "NodeSnapshot" $ \value ->
    NodeSnapshot
      <$> value .: "node"
      <*> value .: "archive"
      <*> value .: "digest"
      <*> (Text.encodeUtf8 <$> value .: "manifest_utf8")

-- ByteString's JSON encoding is deliberately explicit below, not an accidental
-- instance that could alter the snapshot manifest codec.
data SnapshotSelection = SnapshotSelection
  { selectionRequest :: SnapshotRequest
  , selectionGeneration :: Text
  , selectionNodes :: [NodeSnapshot]
  }
  deriving (Eq, Show)

instance ToJSON SnapshotSelection where
  toJSON saved =
    object
      [ "format" .= ("jitml-node-pv-snapshot-v1" :: Text)
      , "request" .= selectionRequest saved
      , "generation" .= selectionGeneration saved
      , "nodes" .= selectionNodes saved
      ]
instance FromJSON SnapshotSelection where
  parseJSON = withObject "SnapshotSelection" $ \value -> do
    format <- value .: "format"
    unless (format == ("jitml-node-pv-snapshot-v1" :: Text)) (fail "snapshot version")
    SnapshotSelection <$> value .: "request" <*> value .: "generation" <*> value .: "nodes"

encodeSelection :: SnapshotSelection -> ByteString
encodeSelection = LBS.toStrict . encode

decodeSelection :: ByteString -> Either String SnapshotSelection
decodeSelection bytes = do
  saved <- eitherDecodeStrict' bytes
  validateRequest (selectionRequest saved)
  unless (safeRelative (selectionGeneration saved)) (Left "unsafe generation")
  unless
    (fmap savedNode (selectionNodes saved) == snapshotNodes (selectionRequest saved))
    (Left "snapshot node membership")
  mapM_
    ( \node -> do
        unless
          ( Text.splitOn "/" (Text.pack (savedArchive node))
              == ["generations", selectionGeneration saved, nodeRole (savedNode node) <> ".pax"]
              && safeRelative (Text.pack (savedArchive node))
              && digestBytes (savedDigest node) > 0
              && validSHA (digestSHA256 (savedDigest node))
          )
          (Left "invalid saved archive")
        void (decodeTreeManifest (selectionRequest saved) (savedManifest node))
    )
    (selectionNodes saved)
  pure saved

newtype VerifiedSnapshot = VerifiedSnapshot SnapshotSelection
verifiedSelection :: VerifiedSnapshot -> SnapshotSelection
verifiedSelection (VerifiedSnapshot value) = value

-- Storage interpreter requirements are part of this interface:

-- * exclusive lifecycle lock, no-follow traversal, private .data-owned paths;

-- * stage immutable archives+manifests, fsync/readback all and generation dir;

-- * compare-and-swap selection against original bytes; durable atomic replace;

-- * failed CAS never replaces current; cancellation before commit leaves it;

-- * absent/null selection means do not restore ANY unselected generation.

-- The POSIX interpreter implements these storage requirements.
data SnapshotStore = SnapshotStore
  { withLifecycleLock :: forall a. IO a -> IO a
  , readSelection :: IO (Maybe SnapshotSelection)
  , stageGeneration :: SnapshotRequest -> [NodeSnapshot] -> IO SnapshotSelection
  , commitSelection :: Maybe SnapshotSelection -> SnapshotSelection -> IO ()
  , clearSelection :: IO ()
  }

-- withQuiesced must pause all actual writers of the CLOSED registry, wait for
-- their pods/processes to exit, retain original replicas, and hold that state
-- across the callback. Its failure compensation attempts every original owner,
-- preserving first async exception. It must not automatically resume writers
-- after successful deletion; on failure it may resume only unchanged old CIDs.
-- No method accepts shell text. The interpreter uses typed Subprocess /
-- typed-process file handles; binary tar never travels through Text capture.
data SnapshotBackend = SnapshotBackend
  { withQuiesced :: forall a. SnapshotRequest -> IO a -> IO a
  , captureAndScratchRestore :: SnapshotRequest -> NodeIdentity -> IO NodeCandidate
  , revalidateSourceNodes :: SnapshotRequest -> [NodeSnapshot] -> IO ()
  , requireFreshEmptyRoots :: SnapshotRequest -> IO ()
  , verifySelectedArchive :: NodeSnapshot -> IO ()
  , restoreNode :: NodeIdentity -> NodeSnapshot -> IO ByteString
  }

data RestoreOutcome = NoSelectedSnapshot | RestoredSnapshot Text
  deriving (Eq, Show)

failure :: String -> IO a
failure = throwIO . userError

safeRelative :: Text -> Bool
safeRelative value =
  not (Text.null value)
    && not (Text.isPrefixOf "/" value)
    && all (\part -> part /= ".." && part /= "." && not (Text.null part)) (Text.splitOn "/" value)
    && not (Text.any (== '\NUL') value)

validateRequest :: SnapshotRequest -> Either String ()
validateRequest request = do
  unless
    (snapshotLane request `elem` ["linux-cpu", "apple-silicon"])
    (Left "not a node-local PV lane")
  unless (snapshotCluster request == "jitml-" <> snapshotLane request) (Left "cluster/lane mismatch")
  let nodes = snapshotNodes request
      roles = fmap nodeRole nodes
      cids = fmap nodeContainerId nodes
      roots = registeredRoots request
  unless
    (not (null nodes) && length roles == Set.size (Set.fromList roles))
    (Left "missing/duplicate node role")
  unless
    (length cids == Set.size (Set.fromList cids) && not (any Text.null cids))
    (Left "missing/duplicate node CID")
  unless
    (not (null roots) && length roots == Set.size (Set.fromList roots) && all safeRelative roots)
    (Left "invalid closed PV registry")

field :: Text -> Value -> Either String Value
field key (Object row) = maybe (Left ("missing field " <> Text.unpack key)) Right (KM.lookup (fromStringKey key) row)
field _ _ = Left "expected object"

fromStringKey :: Text -> Key.Key
fromStringKey = Key.fromText

textField :: Text -> Value -> Either String Text
textField key row =
  field key row >>= \case
    String text -> Right text
    _ -> Left ("not a string: " <> Text.unpack key)

arrayField :: Text -> Value -> Either String [Value]
arrayField key row =
  field key row >>= \case
    Array values -> Right (toList values)
    _ -> Left ("not an array: " <> Text.unpack key)

-- Decode the tested no-follow Linux manifest format. Reject unregistered
-- payloads, missing PV directories, traversal, duplicate rows and special types
-- whose complete restoration the selected tar protocol cannot establish.
decodeTreeManifest :: SnapshotRequest -> ByteString -> Either String TreeManifest
decodeTreeManifest request bytes = do
  validateRequest request
  value <- eitherDecodeStrict' bytes
  format <- textField "format" value
  unless (format == "quiesced-tree-manifest-v1") (Left "manifest version")
  completed <- field "completed" value
  unless (completed == Bool True) (Left "manifest not complete")
  manifestRoot <- textField "root" value
  unless
    (Text.isPrefixOf "/" manifestRoot && safeRelative (Text.drop 1 manifestRoot))
    (Left "unsafe manifest root")
  unsupported <- arrayField "unsupported_restore_types" value
  unless (null unsupported) (Left "unsupported restore type")
  rows <- arrayField "records" value
  paths <- traverse (textField "path") rows
  unless
    (paths == sort paths && length paths == Set.size (Set.fromList paths))
    (Left "noncanonical/duplicate paths")
  unless ("." `elem` paths) (Left "missing whole-tree root")
  let roots = registeredRoots request
      below root path = root == path || (root <> "/") `Text.isPrefixOf` path
      allowed path = path == "." || any (\root -> below root path || (path <> "/") `Text.isPrefixOf` root) roots
  unless
    (all (\path -> (path == "." || safeRelative path) && allowed path) paths)
    (Left "unregistered path")
  mapM_ (validateRow roots) rows
  mapM_ (\root -> unless (any (isDirectoryAt root) rows) (Left "registered PV root absent")) roots
  groups <- arrayField "hardlink_groups" value >>= traverse stringArray
  unless
    ( groups == sort groups
        && all (\g -> length g >= 2 && g == sort g && length g == Set.size (Set.fromList g)) groups
    )
    (Left "invalid hardlink groups")
  unless
    ( all (all (`elem` paths)) groups
        && length (concat groups) == Set.size (Set.fromList (concat groups))
    )
    (Left "invalid hardlink membership")
  pure (TreeManifest manifestRoot rows groups)
 where
  stringArray (Array items) =
    traverse (\case String t -> Right t; _ -> Left "hardlink path not string") (toList items)
  stringArray _ = Left "hardlink group not array"
  isDirectoryAt path row = textField "path" row == Right path && textField "type" row == Right "directory"
  validateRow roots row = do
    path <- textField "path" row
    kind <- textField "type" row
    unless
      (kind `elem` ["directory", "file", "symlink", "fifo", "char-device", "block-device"])
      (Left "unsupported row type")
    unless (any (\root -> root == path || (root <> "/") `Text.isPrefixOf` path) roots) $
      unless (kind == "directory") (Left "payload outside registered PV root")
    mapM_
      (\key -> integerField key row >>= \n -> unless (n >= 0) (Left "negative metadata"))
      ["mode", "uid", "gid", "nlink", "size", "rdev"]
    mode <- integerField "mode" row
    unless (mode <= 4095) (Left "invalid permission bits")
    void (integerField "mtime_ns" row)
    identity <- field "identity" row
    case identity of
      Object fields ->
        unless
          (Set.fromList (KM.keys fields) == Set.fromList ["device", "inode", "ctime_ns"])
          (Left "identity fields")
      _ -> Left "identity not object"
    mapM_ (\key -> void (integerField key identity)) ["device", "inode", "ctime_ns"]
    attrs <- field "xattrs_base64" row
    case attrs of
      Object fields -> unless (all isString (KM.elems fields)) (Left "xattr not encoded string")
      _ -> Left "xattrs not object"
    when (kind == "file") $ do
      digest <- textField "sha256" row
      unless (validSHA digest) (Left "invalid file SHA256")
    when (kind == "symlink") (void (textField "link_target" row))
  isString (String _) = True
  isString _ = False
  integerField key row = do
    value <- field key row
    case fromJSON value of
      Success number -> Right (number :: Integer)
      Error _ -> Left ("not an integer: " <> Text.unpack key)

validSHA :: Text -> Bool
validSHA value = Text.length value == 64 && Text.all (`elem` ("0123456789abcdef" :: String)) value

-- Full source before/after equality includes identity and directory metadata.
-- Only CROSS-filesystem restoration drops inode/device/ctime and DIR size.
-- File sizes, owners, permissions, nanosecond mtime, xattrs, special metadata,
-- link targets and the complete hardlink partition remain strict.
sameRestoredTree :: TreeManifest -> TreeManifest -> Bool
sameRestoredTree left right =
  treeHardlinks left == treeHardlinks right
    && fmap portable (treeRows left) == fmap portable (treeRows right)
 where
  portable (Object row) =
    Object $
      (if KM.lookup "type" row == Just (String "directory") then KM.delete "size" else id)
        (KM.delete "identity" row)
  portable other = other

verifyCandidate :: SnapshotRequest -> NodeIdentity -> NodeCandidate -> IO NodeSnapshot
verifyCandidate request node candidate = do
  unless (candidateNode candidate == node) (failure "snapshot node identity mismatch")
  unless
    (safeRelative (Text.pack (candidateArchive candidate)))
    (failure "unsafe generation archive path")
  unless
    (digestBytes (candidateDigest candidate) > 0 && validSHA (digestSHA256 (candidateDigest candidate)))
    (failure "invalid archive digest")
  before <- either failure pure (decodeTreeManifest request (candidateBefore candidate))
  after <- either failure pure (decodeTreeManifest request (candidateAfter candidate))
  restored <- either failure pure (decodeTreeManifest request (candidateScratch candidate))
  unless (before == after) (failure "source tree changed during snapshot")
  unless (sameRestoredTree before restored) (failure "scratch restore differs from quiesced source")
  pure
    ( NodeSnapshot
        node
        (candidateArchive candidate)
        (candidateDigest candidate)
        (candidateBefore candidate)
    )

-- This is the sole delete boundary. All slow reads are cancellable; no delete
-- is scheduled on a failing/cancelled capture, scratch restore or stage. After
-- commit and entry into delete, failures are genuinely uncertain: retain the
-- new recoverable selection rather than rolling it back to stale state.
preserveBeforeDelete
  :: SnapshotBackend
  -> SnapshotStore
  -> SnapshotRequest
  -> (SnapshotRequest -> IO ())
  -> IO VerifiedSnapshot
preserveBeforeDelete backend store request deleteKind = do
  either failure pure (validateRequest request)
  withLifecycleLock store $ withQuiesced backend request $ do
    prior <- readSelection store
    nodes <- forM (snapshotNodes request) $ \node ->
      captureAndScratchRestore backend request node >>= verifyCandidate request node
    staged <- stageGeneration store request nodes
    unless
      ( selectionRequest staged == request
          && selectionNodes staged == nodes
          && decodeSelection (encodeSelection staged) == Right staged
      )
      (failure "storage staged a different/invalid generation")
    revalidateSourceNodes backend request nodes
    mask $ \restore -> do
      -- commit must be a short atomic storage operation with readback. No
      -- uninterruptible masking around child waits or filesystem workloads.
      commitSelection store prior staged
      restore (deleteKind request)
    pure (VerifiedSnapshot staged)

restoreBeforeMounts :: SnapshotBackend -> SnapshotStore -> SnapshotRequest -> IO RestoreOutcome
restoreBeforeMounts backend store request = do
  either failure pure (validateRequest request)
  withLifecycleLock store $ do
    selected <- readSelection store
    case selected of
      Nothing -> pure NoSelectedSnapshot
      Just saved -> do
        let old = selectionRequest saved
        unless
          ( snapshotLane old == snapshotLane request
              && snapshotCluster old == snapshotCluster request
              && registeredRoots old == registeredRoots request
              && fmap nodeRole (snapshotNodes old) == fmap nodeRole (snapshotNodes request)
              && fmap savedNode (selectionNodes saved) == snapshotNodes old
          )
          (failure "selection topology/registry mismatch")
        -- Check EVERY root and EVERY archive before the first extraction.
        requireFreshEmptyRoots backend request
        mapM_ (verifySelectedArchive backend) (selectionNodes saved)
        mapM_
          ( \(fresh, snapshot) -> do
              bytes <- restoreNode backend fresh snapshot
              expected <- either failure pure (decodeTreeManifest request (savedManifest snapshot))
              actual <- either failure pure (decodeTreeManifest request bytes)
              unless
                (sameRestoredTree expected actual)
                (failure "restored node differs; no mount/release permitted")
          )
          (zip (snapshotNodes request) (selectionNodes saved))
        pure (RestoredSnapshot (selectionGeneration saved))

-- Invalidate before purge deletes .data; crash after invalidation must not
-- resurrect any retained/unselected archive. Purge is allowed to destroy data.
invalidateForPurge :: SnapshotStore -> IO ()
invalidateForPurge store = withLifecycleLock store (clearSelection store)
