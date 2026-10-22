{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE InterruptibleFFI #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module JitML.Cluster.PVSnapshotPosix
  ( LifecycleLease
  , PosixSnapshotConfig (..)
  , PosixSnapshotStore
  , withPosixLifecycle
  , validateLifecycleScope
  , openPosixSnapshotStore
  , snapshotStore
  , reserveOwnedGeneration
  , verifyHostArchive
  , recordLifecycleEvent
  , lifecycleEventPath
  , invalidateAllSnapshotSelections
  , RestoreToken
  , beginSnapshotRestore
  , completeSnapshotRestore
  , assertReusableCluster
  ) where

import Control.Concurrent (ThreadId, myThreadId)
import Control.Exception
  ( IOException
  , SomeAsyncException
  , SomeException
  , catch
  , fromException
  , mask
  , mask_
  , throwIO
  , try
  )
import Control.Monad (forM_, join, unless, void, when)
import Crypto.Hash.SHA256 qualified as SHA
import Data.Aeson (Value, eitherDecodeStrict', encode, object, (.=))
import Data.Aeson.Types (parseEither, withObject, (.:))
import Data.Bits ((.&.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.Maybe (isNothing)
import Data.Text (Text)
import Data.Text qualified as Text
import Foreign.C.Error (throwErrnoIfMinus1, throwErrnoIfMinus1_)
import Foreign.C.String (CString, withCString)
import Foreign.C.Types (CInt (..))
import GHC.Clock (getMonotonicTimeNSec)
import Numeric (showHex)
import System.Directory (makeAbsolute)
import System.FilePath (isAbsolute, splitDirectories, (</>))
import System.IO (hClose, hFlush)
import System.IO.Error (isAlreadyExistsError, isDoesNotExistError)
import System.Posix.Files
  ( FileStatus
  , deviceID
  , fileGroup
  , fileID
  , fileMode
  , fileOwner
  , fileSize
  , getFdStatus
  , isDirectory
  , isRegularFile
  , linkCount
  , modificationTimeHiRes
  , statusChangeTimeHiRes
  )
import System.Posix.IO (closeFd, dup, fdToHandle)
import System.Posix.Process (getProcessID)
import System.Posix.Types (Fd (..), ProcessID)
import System.Posix.User (getEffectiveGroupID, getEffectiveUserID)

import JitML.Cluster.PVSnapshot

foreign import ccall unsafe "jitml_pv_root" cRoot :: IO CInt
foreign import ccall unsafe "jitml_pv_dir" cDir :: CInt -> CString -> IO CInt
foreign import ccall unsafe "jitml_pv_mkdir" cMkdir :: CInt -> CString -> IO CInt
foreign import ccall unsafe "jitml_pv_file" cFile :: CInt -> CString -> CInt -> IO CInt
foreign import ccall safe "jitml_pv_sync" cSync :: CInt -> IO CInt
foreign import ccall unsafe "jitml_pv_rename" cRename :: CInt -> CString -> CString -> IO CInt
foreign import ccall interruptible "jitml_pv_lock" cLock :: CInt -> IO CInt
foreign import ccall unsafe "jitml_pv_unlock" cUnlock :: CInt -> IO CInt
foreign import ccall safe "jitml_pv_claim_acquire" cClaimAcquire :: CInt -> CString -> IO CInt
foreign import ccall safe "jitml_pv_claim_release"
  cClaimRelease :: CInt -> CInt -> CString -> IO CInt

data LifecycleLease = LifecycleLease
  { leaseRoot :: FilePath
  , leaseThread :: ThreadId
  , leaseProcess :: ProcessID
  , leaseLive :: IORef Bool
  , leaseEventToken :: String
  , leaseEventBytes :: IORef (Maybe ByteString)
  }

data PosixSnapshotConfig = PosixSnapshotConfig
  { posixWorkspaceRoot :: FilePath
  , posixLane :: Text
  , posixGenerationToken :: Text
  }
  deriving (Eq, Show)

data PosixSnapshotStore = PosixSnapshotStore
  { storeLease :: LifecycleLease
  , storeConfig :: PosixSnapshotConfig
  , storeReservedEpoch :: IORef (Maybe Integer)
  , storeTempSerial :: IORef Integer
  }

data RestoreToken = RestoreToken PosixSnapshotStore SnapshotSelection SnapshotRequest Integer ByteString

failStore :: String -> IO a
failStore = throwIO . userError . ("PV snapshot store: " <>)

component :: String -> Bool
component value =
  not (null value)
    && length value <= 160
    && all
      (\c -> c `elem` ("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-" :: String))
      value

validateLease :: LifecycleLease -> IO ()
validateLease lease = do
  live <- readIORef (leaseLive lease)
  owner <- myThreadId
  pid <- getProcessID
  unless
    (live && owner == leaseThread lease && pid == leaseProcess lease)
    (failStore "lease expired or used by a different thread/process")

validateLifecycleScope :: LifecycleLease -> FilePath -> IO ()
validateLifecycleScope lease workspace = do
  validateLease lease
  root <- makeAbsolute workspace
  unless (root == leaseRoot lease) (failStore "workspace does not match lifecycle lease")

-- Keep original async failure even when a cleanup also fails; never skip close.
finish :: Either SomeException a -> Either SomeException b -> IO a
finish (Right value) (Right _) = pure value
finish (Left first) (Right _) = throwIO first
finish (Right _) (Left cleanup) = throwIO cleanup
finish (Left first) (Left cleanup) =
  case fromException first :: Maybe SomeAsyncException of
    Just _ -> throwIO first
    Nothing -> case fromException cleanup :: Maybe SomeAsyncException of
      Just _ -> throwIO cleanup
      Nothing -> throwIO first

bracket :: IO a -> (a -> IO b) -> (a -> IO c) -> IO c
bracket acquire release action = mask $ \restore -> do
  resource <- acquire
  actual <- try (restore (action resource))
  cleanup <- try (release resource)
  finish actual cleanup

-- A permanent repo-local lock inode survives BOTH .data and .build removal.
-- The callback owns the complete mutation boundary, not just snapshot copying.
-- Lease and handles cannot be used after return or on a forked thread.
withPosixLifecycle :: forall a. FilePath -> (LifecycleLease -> IO a) -> IO a
withPosixLifecycle workspace action = do
  absolute <- makeAbsolute workspace
  withAbsoluteDirectory absolute $ \root ->
    bracket (openFileAt root ".jitml-pv-lifecycle.lock" 2) closeFd $ \lock -> mask $ \restore -> do
      checkRegular lock
      syncFD root
      restore (void (throwErrnoIfMinus1 "flock lifecycle" (cLock (unFd lock))))
      owner <- myThreadId
      pid <- getProcessID
      tick <- getMonotonicTimeNSec
      eventBytes <- newIORef Nothing
      let token = "lease-" <> show pid <> "-" <> show tick
          acquire =
            Fd
              <$> withCString
                token
                ( throwErrnoIfMinus1
                    "exclusive lifecycle mkdir claim (existing claim is busy; no automatic reclaim)"
                    . cClaimAcquire (unFd root)
                )
          release claim = do
            removed <-
              try
                ( withCString
                    token
                    ( throwErrnoIfMinus1_ "release exact lifecycle claim"
                        . cClaimRelease (unFd root) (unFd claim)
                    )
                )
            closed <- try (closeFd claim)
            finish removed closed
      result <- try $ bracket acquire release $ \_ -> do
        live <- newIORef True
        attempted <- try (restore (action (LifecycleLease absolute owner pid live token eventBytes)))
        writeIORef live False
        either throwIO pure (attempted :: Either SomeException a)
      released <- try (throwErrnoIfMinus1_ "unlock lifecycle" (cUnlock (unFd lock)))
      finish result released

openPosixSnapshotStore :: LifecycleLease -> PosixSnapshotConfig -> IO PosixSnapshotStore
openPosixSnapshotStore lease config = do
  validateLifecycleScope lease (posixWorkspaceRoot config)
  unless
    ( posixLane config `elem` ["linux-cpu", "apple-silicon", "linux-cuda"]
        && component (Text.unpack (posixGenerationToken config))
    )
    (failStore "invalid config/root/lane/token")
  reserved <- newIORef Nothing
  serial <- newIORef 0
  pure (PosixSnapshotStore lease config reserved serial)

snapshotStore :: PosixSnapshotStore -> SnapshotStore
snapshotStore handle =
  SnapshotStore
    { withLifecycleLock = \action -> validateLease (storeLease handle) >> action
    , readSelection = readCurrent handle
    , stageGeneration = stage handle
    , commitSelection = commit handle
    , clearSelection = invalidate handle
    }

unFd :: Fd -> CInt
unFd (Fd value) = value

openDirectoryAt :: Fd -> FilePath -> IO Fd
openDirectoryAt parent name =
  Fd
    <$> withCString
      name
      (throwErrnoIfMinus1 ("openat directory " <> name) . cDir (unFd parent))

openFileAt :: Fd -> FilePath -> CInt -> IO Fd
openFileAt parent name how =
  Fd
    <$> withCString
      name
      (\value -> throwErrnoIfMinus1 ("openat file " <> name) (cFile (unFd parent) value how))

syncFD :: Fd -> IO ()
syncFD fd = throwErrnoIfMinus1_ "fsync snapshot" (cSync (unFd fd))

withAbsoluteDirectory :: FilePath -> (Fd -> IO a) -> IO a
withAbsoluteDirectory absolute action = do
  let parts = filter (/= "/") (splitDirectories absolute)
  unless
    (isAbsolute absolute && all (\p -> p /= ".." && p /= "." && notElem '\NUL' p) parts)
    (failStore "unsafe absolute directory")
  bracket (Fd <$> throwErrnoIfMinus1 "open filesystem root" cRoot) closeFd $ \root -> walk root parts
 where
  walk parent [] = action parent
  walk parent (name : rest) = bracket (openDirectoryAt parent name) closeFd (`walk` rest)

withChild :: Bool -> Fd -> FilePath -> (Fd -> IO a) -> IO a
withChild create parent name action = do
  when create $
    withCString name (throwErrnoIfMinus1_ ("mkdirat " <> name) . cMkdir (unFd parent))
      `catch` \(e :: IOException) -> unless (isAlreadyExistsError e) (throwIO e)
  bracket (openDirectoryAt parent name) closeFd $ \child -> do
    checkDirectory child
    when create (syncFD parent)
    action child

withControl :: PosixSnapshotStore -> Bool -> (Fd -> IO a) -> IO a
withControl handle create action = do
  validateLease (storeLease handle)
  withAbsoluteDirectory (leaseRoot (storeLease handle)) $ \root ->
    -- .build/runtime are shared owned paths and need not have private modes.
    withAncestor create root ".build" $ \build -> withAncestor create build "runtime" $ \runtime ->
      withChild create runtime "pv-snapshot-control" $ \controls ->
        withChild create controls (Text.unpack (posixLane (storeConfig handle))) action

withAncestor :: Bool -> Fd -> FilePath -> (Fd -> IO a) -> IO a
withAncestor create parent name action = do
  when create $
    withCString
      name
      (throwErrnoIfMinus1_ ("mkdirat ancestor " <> name) . cMkdir (unFd parent))
      `catch` \(e :: IOException) -> unless (isAlreadyExistsError e) (throwIO e)
  bracket (openDirectoryAt parent name) closeFd $ \child -> do
    status <- getFdStatus child
    unless (isDirectory status) (failStore "ancestor not directory")
    when create (syncFD parent)
    action child

withLane :: PosixSnapshotStore -> Bool -> (Fd -> IO a) -> IO a
withLane handle create action = do
  validateLease (storeLease handle)
  withAbsoluteDirectory (leaseRoot (storeLease handle)) $ \root ->
    withAncestor create root ".data" $ \dat ->
      withChild create dat ".jitml-pv-snapshots" $ \snapshots ->
        withChild create snapshots (Text.unpack (posixLane (storeConfig handle))) action

checkDirectory :: Fd -> IO ()
checkDirectory fd = do
  s <- getFdStatus fd
  uid <- getEffectiveUserID
  gid <- getEffectiveGroupID
  unless
    (isDirectory s && fileMode s .&. 0o7777 == 0o700 && fileOwner s == uid && fileGroup s == gid)
    (failStore "reserved directory owner/group/mode/type")

checkRegular :: Fd -> IO ()
checkRegular fd = do
  s <- getFdStatus fd
  uid <- getEffectiveUserID
  gid <- getEffectiveGroupID
  unless
    ( isRegularFile s
        && linkCount s == 1
        && fileMode s .&. 0o7777 == 0o600
        && fileOwner s == uid
        && fileGroup s == gid
    )
    (failStore "regular file owner/group/mode/nlink/type")

identity :: FileStatus -> [String]
identity s =
  [ show (deviceID s)
  , show (fileID s)
  , show (fileMode s)
  , show (fileOwner s)
  , show (fileGroup s)
  , show (linkCount s)
  , show (fileSize s)
  , show (modificationTimeHiRes s)
  , show (statusChangeTimeHiRes s)
  ]

hex :: ByteString -> Text
hex =
  Text.pack
    . concatMap (\n -> let value = showHex n "" in if length value == 1 then '0' : value else value)
    . BS.unpack

-- The same-domain full fd and final-name identities surround the complete read.
-- Archive bytes are streamed, never accumulated; only bounded controls collect.
readClosed :: Fd -> FilePath -> Maybe Integer -> IO (ByteString, FileDigest)
readClosed parent name cap = bracket (openFileAt parent name 0) closeFd $ \fd -> do
  checkRegular fd
  before <- getFdStatus fd
  case cap of
    Just limit -> unless (toInteger (fileSize before) <= limit) (failStore "control exceeds byte cap")
    Nothing -> pure ()
  (chunks, count, ctx) <- bracket (dup fd >>= fdToHandle) hClose $ \stream -> loop stream [] 0 SHA.init
  after <- getFdStatus fd
  unless
    (identity before == identity after)
    (failStore ("file changed during read: " <> show (identity before, identity after)))
  bracket (openFileAt parent name 0) closeFd $ \again -> do
    checkRegular again
    final <- getFdStatus again
    unless
      (identity before == identity final)
      (failStore ("file name changed during read: " <> show (identity before, identity final)))
  unless (count == toInteger (fileSize before)) (failStore "read byte count differs from stat")
  pure (BS.concat (reverse chunks), FileDigest count (hex (SHA.finalize ctx)))
 where
  loop stream pieces !count !ctx = do
    bytes <- BS.hGetSome stream (1024 * 1024)
    if BS.null bytes
      then pure (pieces, count, ctx)
      else do
        let count' = count + toInteger (BS.length bytes)
        case cap of
          Just limit -> when (count' > limit) (failStore "control grew past cap")
          Nothing -> pure ()
        loop stream (case cap of Just _ -> bytes : pieces; Nothing -> pieces) count' (SHA.update ctx bytes)

controlCap :: Integer
controlCap = 64 * 1024 * 1024

readOptional :: Fd -> FilePath -> IO (Maybe ByteString)
readOptional parent name =
  (Just . fst <$> readClosed parent name (Just controlCap))
    `catch` \(e :: IOException) -> if isDoesNotExistError e then pure Nothing else throwIO e

writeExclusive :: Fd -> FilePath -> ByteString -> IO ()
writeExclusive parent name bytes = bracket (openFileAt parent name 1) closeFd $ \fd -> do
  checkRegular fd
  bracket (dup fd >>= fdToHandle) hClose $ \stream -> BS.hPut stream bytes >> hFlush stream
  syncFD fd
  (actual, _) <- readClosed parent name (Just controlCap)
  unless (actual == bytes) (failStore "exclusive file readback differs")
  syncFD parent

atomicReplace :: PosixSnapshotStore -> Fd -> FilePath -> ByteString -> IO ()
atomicReplace handle parent name bytes = do
  serial <- readIORef (storeTempSerial handle)
  writeIORef (storeTempSerial handle) (serial + 1)
  let temp =
        "."
          <> name
          <> "."
          <> Text.unpack (posixGenerationToken (storeConfig handle))
          <> "."
          <> show serial
          <> ".pending"
  -- Do not implicitly repair an existing symlink/hardlink/wrong-mode control.
  -- The durable epoch still invalidates data if null-selector write is refused.
  void (readOptional parent name)
  writeExclusive parent temp bytes
  mask_ $ do
    withCString temp $ \from -> withCString name $ \to ->
      throwErrnoIfMinus1_ "renameat selection" (cRename (unFd parent) from to)
    syncFD parent
    actual <- readOptional parent name
    unless (actual == Just bytes) (failStore "atomic control readback differs")

epoch :: PosixSnapshotStore -> IO Integer
epoch handle = withControl handle True $ \control -> do
  existing <- readOptional control "epoch"
  case existing of
    Nothing -> do
      prior <- optionalLane handle (\_ -> pure ())
      unless (isNothing prior) (failStore "external epoch missing while canonical snapshot data exists")
      writeExclusive control "epoch" "0\n"
      pure 0
    Just bytes -> case reads (map (toEnum . fromEnum) (BS.unpack bytes)) of
      [(value, "\n")] | value >= (0 :: Integer) && value <= 9223372036854775807 -> pure value
      _ -> failStore "noncanonical epoch"

reserveOwnedGeneration :: PosixSnapshotStore -> IO ()
reserveOwnedGeneration handle = do
  validateLease (storeLease handle)
  currentEpoch <- epoch handle
  existing <- readIORef (storeReservedEpoch handle)
  case existing of
    Just expected -> unless (expected == currentEpoch) (failStore "reservation invalidated by purge")
    Nothing -> do
      withLane handle True $ \lane -> withChild True lane "generations" $ \generations -> do
        let token = Text.unpack (posixGenerationToken (storeConfig handle))
        -- mkdirat is the exclusive directory reservation; the marker additionally
        -- uses O_EXCL. EEXIST is refused, never treated as resume/reuse.
        withCString
          token
          (throwErrnoIfMinus1_ "exclusive generation mkdirat" . cMkdir (unFd generations))
        bracket (openDirectoryAt generations token) closeFd $ \generation -> do
          checkDirectory generation
          writeExclusive
            generation
            "reservation.json"
            ( LBS.toStrict
                ( encode
                    ( object
                        [ "format" .= ("jitml-pv-reservation-v1" :: Text)
                        , "lane" .= posixLane (storeConfig handle)
                        , "token" .= posixGenerationToken (storeConfig handle)
                        , "epoch" .= currentEpoch
                        ]
                    )
                )
            )
          syncFD generation
        syncFD generations
      writeIORef (storeReservedEpoch handle) (Just currentEpoch)

archiveParts :: FilePath -> IO (String, String)
archiveParts path = case splitDirectories path of
  ["generations", token, file]
    | component token
    , reverse (take 4 (reverse file)) == ".pax"
    , let role = take (length file - 4) file
    , component role ->
        pure (token, file)
  _ -> failStore "archive must be generations/<token>/<role>.pax"

verifyHostArchive :: PosixSnapshotStore -> FilePath -> FileDigest -> IO ()
verifyHostArchive handle relative expected = do
  validateLease (storeLease handle)
  (token, file) <- archiveParts relative
  withLane handle False $ \lane -> withChild False lane "generations" $ \generations ->
    withChild False generations token $ \generation -> do
      (_, actual) <- readClosed generation file Nothing
      unless (actual == expected) (failStore "archive full bytes/SHA differ from selected digest")

generationMeta :: Integer -> ByteString -> Value
generationMeta value bytes =
  object
    [ "format" .= ("jitml-pv-generation-v1" :: Text)
    , "epoch" .= value
    , "selection_bytes" .= BS.length bytes
    , "selection_sha256" .= hex (SHA.hash bytes)
    ]

validateSelectionPaths :: SnapshotSelection -> IO ()
validateSelectionPaths saved = do
  unless
    (component (Text.unpack (selectionGeneration saved)))
    (failStore "unsafe selection generation")
  forM_ (selectionNodes saved) $ \node -> do
    (token, file) <- archiveParts (savedArchive node)
    unless
      ( token == Text.unpack (selectionGeneration saved)
          && file == Text.unpack (nodeRole (savedNode node)) <> ".pax"
      )
      (failStore "archive generation/node-role mismatch")

stage :: PosixSnapshotStore -> SnapshotRequest -> [NodeSnapshot] -> IO SnapshotSelection
stage handle request nodes = do
  validateLease (storeLease handle)
  expectedEpoch <-
    readIORef (storeReservedEpoch handle) >>= maybe (failStore "generation was not reserved") pure
  now <- epoch handle
  unless
    (now == expectedEpoch && snapshotLane request == posixLane (storeConfig handle))
    (failStore "staging lane/epoch mismatch")
  let saved = SnapshotSelection request (posixGenerationToken (storeConfig handle)) nodes
      bytes = encodeSelection saved
  unless (decodeSelection bytes == Right saved) (failStore "invalid staged selection")
  validateSelectionPaths saved
  forM_ nodes $ \node -> verifyHostArchive handle (savedArchive node) (savedDigest node)
  withLane handle False $ \lane -> withChild False lane "generations" $ \generations ->
    withChild False generations (Text.unpack (selectionGeneration saved)) $ \generation -> do
      forM_ nodes $ \node -> do
        let name = Text.unpack (nodeRole (savedNode node))
        writeExclusive generation (name <> ".manifest.json") (savedManifest node)
        bracket (openFileAt generation (name <> ".pax") 0) closeFd syncFD
      writeExclusive generation "selection.json" bytes
      writeExclusive generation "generation.json" (LBS.toStrict (encode (generationMeta now bytes)))
      syncFD generation
      syncFD generations
      syncFD lane
  pure saved

readCurrent :: PosixSnapshotStore -> IO (Maybe SnapshotSelection)
readCurrent handle = do
  validateLease (storeLease handle)
  value <- epoch handle
  observed <- optionalLane handle $ \lane -> do
    current <- readOptional lane "current.json"
    case current of
      Nothing -> pure Nothing
      Just "null\n" -> pure Nothing
      Just bytes -> do
        saved <- either failStore pure (decodeSelection bytes)
        unless
          ( encodeSelection saved == bytes
              && snapshotLane (selectionRequest saved) == posixLane (storeConfig handle)
          )
          (failStore "noncanonical/wrong-lane selection")
        validateSelectionPaths saved
        withChild False lane "generations" $ \generations ->
          withChild False generations (Text.unpack (selectionGeneration saved)) $ \generation -> do
            immutable <- readOptional generation "selection.json"
            unless (immutable == Just bytes) (failStore "selected generation bytes differ")
            meta <-
              readOptional generation "generation.json" >>= maybe (failStore "missing generation metadata") pure
            actual <- either failStore pure (eitherDecodeStrict' meta)
            if actual == generationMeta value bytes
              then do
                forM_ (selectionNodes saved) $ \node -> do
                  manifest <- readOptional generation (Text.unpack (nodeRole (savedNode node)) <> ".manifest.json")
                  unless (manifest == Just (savedManifest node)) (failStore "saved manifest readback differs")
                pure (Just saved)
              else do
                -- A higher external epoch intentionally invalidates old selections.
                -- Still demand structurally exact metadata for SOME older epoch.
                old <- either failStore pure (parseEither (withObject "Generation" (.: "epoch")) actual)
                unless
                  (old >= (0 :: Integer) && old < value && actual == generationMeta old bytes)
                  (failStore "generation metadata corrupt or from a future epoch")
                pure Nothing
  pure (join observed)

-- Only absent lane/ancestors mean no selection. Missing files INSIDE an already
-- entered lane (selected generation/meta/manifests) are corruption, not absence.
optionalLane :: PosixSnapshotStore -> (Fd -> IO a) -> IO (Maybe a)
optionalLane handle action = do
  entered <- newIORef False
  (Just <$> withLane handle False (\lane -> writeIORef entered True >> action lane))
    `catch` \(e :: IOException) -> do
      inside <- readIORef entered
      if not inside && isDoesNotExistError e then pure Nothing else throwIO e

commit :: PosixSnapshotStore -> Maybe SnapshotSelection -> SnapshotSelection -> IO ()
commit handle expected saved = do
  validateLease (storeLease handle)
  actual <- readCurrent handle
  unless (actual == expected) (failStore "selection compare-and-swap failed")
  unless
    (selectionGeneration saved == posixGenerationToken (storeConfig handle))
    (failStore "commit generation differs from owned reservation")
  validateSelectionPaths saved
  value <- epoch handle
  reserved <- readIORef (storeReservedEpoch handle)
  unless (reserved == Just value) (failStore "commit has no current owned generation")
  let bytes = encodeSelection saved
  withLane handle False $ \lane -> withChild False lane "generations" $ \generations ->
    withChild False generations (Text.unpack (selectionGeneration saved)) $ \generation -> do
      staged <- readOptional generation "selection.json"
      meta <- readOptional generation "generation.json"
      unless
        (staged == Just bytes && meta == Just (LBS.toStrict (encode (generationMeta value bytes))))
        (failStore "staged selection/meta changed")
  forM_ (selectionNodes saved) $ \node -> verifyHostArchive handle (savedArchive node) (savedDigest node)
  withLane handle False $ \lane -> atomicReplace handle lane "current.json" bytes

invalidate :: PosixSnapshotStore -> IO ()
invalidate handle = do
  validateLease (storeLease handle)
  value <- epoch handle
  -- Outside .data, durable first. Even failure of the following null write or
  -- recursive payload removal cannot resurrect a generation from the old epoch.
  withControl handle True $ \control ->
    atomicReplace handle control "epoch" (BS.pack (map (toEnum . fromEnum) (show (value + 1) <> "\n")))
  void (optionalLane handle (\lane -> atomicReplace handle lane "current.json" "null\n"))

lifecycleEventPath :: LifecycleLease -> FilePath
lifecycleEventPath lease =
  leaseRoot lease </> ".build" </> "runtime" </> "pv-lifecycle-events" </> leaseEventToken lease
    <> ".jsonl"

-- This is deliberately real I/O, not a default no-op hook. Callers pass only
-- filtered event facts, never credentials/config contents or raw run payloads.
recordLifecycleEvent :: LifecycleLease -> Value -> IO ()
recordLifecycleEvent lease value = do
  validateLease lease
  let bytes = LBS.toStrict (encode value) <> "\n"
      name = leaseEventToken lease <> ".jsonl"
  previous <- readIORef (leaseEventBytes lease)
  withAbsoluteDirectory (leaseRoot lease) $ \root ->
    withAncestor True root ".build" $ \build -> withAncestor True build "runtime" $ \runtime ->
      withChild True runtime "pv-lifecycle-events" $ \events -> case previous of
        Nothing -> writeExclusive events name bytes
        Just expected -> do
          existing <- readOptional events name
          unless (existing == Just expected) (failStore "event prefix changed")
          bracket (openFileAt events name 3) closeFd $ \fd -> do
            checkRegular fd
            before <- getFdStatus fd
            bracket (openFileAt events name 0) closeFd $ \named -> do
              namedStatus <- getFdStatus named
              unless (identity before == identity namedStatus) (failStore "event FD/name differs before append")
            bracket (dup fd >>= fdToHandle) hClose $ \stream -> BS.hPut stream bytes >> hFlush stream
            syncFD fd
            actual <- readOptional events name
            unless (actual == Just (expected <> bytes)) (failStore "event append readback differs")
            after <- getFdStatus fd
            bracket (openFileAt events name 0) closeFd $ \named -> do
              namedStatus <- getFdStatus named
              unless (identity after == identity namedStatus) (failStore "event FD/name differs after append")
            syncFD events
  writeIORef (leaseEventBytes lease) (Just (maybe bytes (<> bytes) previous))

invalidateAllSnapshotSelections :: LifecycleLease -> IO ()
invalidateAllSnapshotSelections lease = do
  validateLease lease
  outcomes <-
    mapM
      ( \lane -> try $ do
          handle <-
            openPosixSnapshotStore
              lease
              (PosixSnapshotConfig (leaseRoot lease) lane (Text.pack (leaseEventToken lease <> "-purge")))
          invalidate handle
      )
      ["linux-cpu", "apple-silicon"]
  foldl
    ( \prior outcome -> do
        first <- prior
        try (finish first (outcome :: Either SomeException ()))
    )
    (pure (Right ()))
    outcomes
    >>= \result -> either throwIO pure result

restoreValue :: Integer -> Text -> SnapshotSelection -> SnapshotRequest -> Value
restoreValue value status selected fresh =
  object
    [ "format" .= ("jitml-pv-restore-v1" :: Text)
    , "epoch" .= value
    , "status" .= status
    , "generation" .= selectionGeneration selected
    , "selection_sha256" .= hex (SHA.hash (encodeSelection selected))
    , "nodes" .= snapshotNodes fresh
    ]

-- Read the single selected restore control, never scan historic marker files.
-- Preserve stale pending controls too: cancelled purge may have invalidated the
-- selection without deleting the partially restored nodes.
readRestoreControl
  :: PosixSnapshotStore -> IO (Maybe (Integer, Text, Text, Text, [NodeIdentity], Value))
readRestoreControl handle = withControl handle True $ \control -> do
  raw <- readOptional control "restore.json"
  case raw of
    Nothing -> pure Nothing
    Just bytes -> do
      value <- either failStore pure (eitherDecodeStrict' bytes)
      (e, status, generation, sha, nodes) <-
        either
          failStore
          pure
          ( parseEither
              ( withObject "Restore" $ \obj -> do
                  format <- obj .: "format"
                  unless (format == ("jitml-pv-restore-v1" :: Text)) (fail "restore format")
                  (,,,,)
                    <$> obj .: "epoch"
                    <*> obj .: "status"
                    <*> obj .: "generation"
                    <*> obj .: "selection_sha256"
                    <*> obj .: "nodes"
              )
              value
          )
      let canonical =
            object
              [ "format" .= ("jitml-pv-restore-v1" :: Text)
              , "epoch" .= (e :: Integer)
              , "status" .= (status :: Text)
              , "generation" .= (generation :: Text)
              , "selection_sha256" .= (sha :: Text)
              , "nodes" .= (nodes :: [NodeIdentity])
              ]
      unless
        ( value == canonical
            && LBS.toStrict (encode value) == bytes
            && e >= 0
            && e <= 9223372036854775807
            && status `elem` ["pending", "complete"]
            && component (Text.unpack generation)
            && Text.length sha == 64
            && Text.all (`elem` ("0123456789abcdef" :: String)) sha
            && not (null nodes)
        )
        (failStore "invalid restore control")
      pure (Just (e, status, generation, sha, nodes, value))

beginSnapshotRestore
  :: PosixSnapshotStore -> SnapshotRequest -> SnapshotSelection -> IO RestoreToken
beginSnapshotRestore handle fresh selected = do
  validateLease (storeLease handle)
  either failStore pure (validateRequest fresh)
  actual <- readCurrent handle
  unless (actual == Just selected) (failStore "restore selection changed before pending marker")
  let original = selectionRequest selected
      oldCIDs = fmap nodeContainerId (snapshotNodes original)
  unless
    ( snapshotLane fresh == snapshotLane original
        && snapshotCluster fresh == snapshotCluster original
        && registeredRoots fresh == registeredRoots original
        && fmap nodeRole (snapshotNodes fresh) == fmap nodeRole (snapshotNodes original)
        && all ((`notElem` oldCIDs) . nodeContainerId) (snapshotNodes fresh)
    )
    (failStore "restore requires exact topology and genuinely fresh CIDs")
  value <- epoch handle
  prior <- readRestoreControl handle
  case prior of
    Just (e, status, _, _, _, _)
      | e > value -> failStore "restore control from future epoch"
      | e == value && status == "pending" -> failStore "prior restore pending; no retry or overwrite"
    _ -> pure ()
  let bytes = LBS.toStrict (encode (restoreValue value "pending" selected fresh))
      history = "restore-" <> leaseEventToken (storeLease handle) <> "-pending.json"
  withControl handle True $ \control -> do
    writeExclusive control history bytes
    atomicReplace handle control "restore.json" bytes
  pure (RestoreToken handle selected fresh value bytes)

-- Call only after every real restored-node manifest has passed core comparison.
-- A token is single-use by exact pending-byte CAS.
completeSnapshotRestore :: RestoreToken -> IO ()
completeSnapshotRestore (RestoreToken handle selected fresh expectedEpoch pending) = do
  validateLease (storeLease handle)
  actual <- readCurrent handle
  value <- epoch handle
  unless
    (actual == Just selected && value == expectedEpoch)
    (failStore "restore selection/epoch changed before completion")
  withControl handle True $ \control -> do
    current <- readOptional control "restore.json"
    unless (current == Just pending) (failStore "restore is no longer the exact pending operation")
    let bytes = LBS.toStrict (encode (restoreValue value "complete" selected fresh))
    writeExclusive control ("restore-" <> leaseEventToken (storeLease handle) <> "-complete.json") bytes
    atomicReplace handle control "restore.json" bytes

assertReusableCluster :: LifecycleLease -> Text -> [NodeIdentity] -> IO ()
assertReusableCluster lease laneName actualNodes = do
  validateLease lease
  when (null actualNodes) (failStore "reuse requires actual nodes")
  handle <-
    openPosixSnapshotStore
      lease
      (PosixSnapshotConfig (leaseRoot lease) laneName (Text.pack (leaseEventToken lease <> "-reuse")))
  selected <- readCurrent handle
  value <- epoch handle
  marker <- readRestoreControl handle
  case marker of
    Just (e, status, _, _, nodes, _) -> do
      unless (e <= value) (failStore "restore control from future epoch")
      when
        ( status == "pending"
            && (e == value || any (\n -> nodeContainerId n `elem` fmap nodeContainerId actualNodes) nodes)
        )
        (failStore "restore pending for current/remaining nodes; reuse refused")
    Nothing -> pure ()
  case selected of
    Nothing -> pure ()
    Just saved ->
      if snapshotNodes (selectionRequest saved) == actualNodes
        then pure ()
        else case marker of
          Just (e, "complete", generation, sha, nodes, _) ->
            unless
              ( e == value
                  && generation == selectionGeneration saved
                  && sha == hex (SHA.hash (encodeSelection saved))
                  && nodes == actualNodes
              )
              (failStore "reuse completion does not bind these nodes/selection")
          _ -> failStore "new/different nodes have no completed restore proof"
