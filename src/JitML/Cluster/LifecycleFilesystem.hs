{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Cluster.LifecycleFilesystem
  ( readLifecyclePublication
  , writeStoppedPublication
  , writeStoppingPublication
  , purgeRuntimeRoots
  ) where

import Control.Exception (bracket, onException, throwIO)
import Control.Monad (unless, void)
import Data.Aeson (eitherDecodeStrict', encode)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Text qualified as Text
import Foreign.C.Error (eNOENT, getErrno, throwErrno, throwErrnoIfMinus1_)
import Foreign.C.String (CString, withCString)
import Foreign.C.Types (CInt (..), CSize (..))
import System.IO (hClose)
import System.Posix.Files
  ( FileStatus
  , deviceID
  , fileID
  , fileMode
  , fileSize
  , getFdStatus
  , isRegularFile
  , linkCount
  , modificationTimeHiRes
  , statusChangeTimeHiRes
  )
import System.Posix.IO (closeFd, dup, fdToHandle)
import System.Posix.Types (Fd (..))

import JitML.Cluster.LifecycleTarget
  ( PublicationAuthority (..)
  , stoppedPublication
  , stoppingPublication
  )
import JitML.Cluster.PVSnapshotPosix (LifecycleLease, validateLifecycleScope)
import JitML.Cluster.Publication (ClusterPublication)

foreign import ccall safe "jitml_lifecycle_publication" cPublication :: CString -> IO CInt
foreign import ccall safe "jitml_lifecycle_stopped"
  cStopped :: CString -> CString -> CSize -> CString -> CSize -> CString -> IO CInt
foreign import ccall safe "jitml_lifecycle_purge" cPurge :: CString -> CString -> CInt -> IO CInt

failure :: String -> IO a
failure = throwIO . userError

sameStatus :: FileStatus -> FileStatus -> Bool
sameStatus a b =
  deviceID a == deviceID b
    && fileID a == fileID b
    && fileMode a == fileMode b
    && linkCount a == linkCount b
    && fileSize a == fileSize b
    && modificationTimeHiRes a == modificationTimeHiRes b
    && statusChangeTimeHiRes a == statusChangeTimeHiRes b

-- Fixed repo-local path; C holds every ancestor through no-follow descriptors.
-- A missing file is distinct from corrupt authority or an inaccessible path.
readLifecyclePublication :: FilePath -> IO (PublicationAuthority, Maybe ByteString)
readLifecyclePublication root = withCString root $ \path -> do
  raw <- cPublication path
  if raw < 0
    then do
      err <- getErrno
      if err == eNOENT
        then pure (PublicationMissing, Nothing)
        else throwErrno "open lifecycle publication"
    else bracket (pure (Fd raw)) closeFd $ \fd -> do
      before <- getFdStatus fd
      unless
        (isRegularFile before && linkCount before == 1 && fileSize before <= 65536)
        (failure "cluster publication must be a bounded regular file with one link")
      bytes <-
        bracket
          (do copied <- dup fd; fdToHandle copied `onException` closeFd copied)
          hClose
          (`BS.hGet` 65537)
      after <- getFdStatus fd
      unless
        (sameStatus before after && fromIntegral (BS.length bytes) == fileSize after)
        (failure "cluster publication changed during read")
      pure
        (either (PublicationCorrupt . Text.pack) PublicationPresent (eitherDecodeStrict' bytes), Just bytes)

writeStoppedPublication
  :: LifecycleLease -> FilePath -> String -> ByteString -> ClusterPublication -> IO ()
writeStoppedPublication lease root token before publication =
  void (writeLifecyclePublication lease root token before (stoppedPublication publication))

writeStoppingPublication
  :: LifecycleLease -> FilePath -> String -> ByteString -> ClusterPublication -> IO ByteString
writeStoppingPublication lease root token before publication =
  writeLifecyclePublication lease root token before (stoppingPublication publication)

writeLifecyclePublication
  :: LifecycleLease -> FilePath -> String -> ByteString -> ClusterPublication -> IO ByteString
writeLifecyclePublication lease root token before publication = do
  validateLifecycleScope lease root
  let after = LBS.toStrict (encode publication)
  withCString root $ \path -> withCString token $ \generation ->
    BS.useAsCStringLen before $ \(old, oldLength) -> BS.useAsCStringLen after $ \(new, newLength) ->
      throwErrnoIfMinus1_
        "durable stopped publication CAS"
        (cStopped path old (fromIntegral oldLength) new (fromIntegral newLength) generation)
  pure after

-- Caller must invalidate ALL lane selections and prove exact Kind deletion
-- before entering this primitive. Every argument remains fixed to this root;
-- C detaches .data into an exclusive ignored quarantine, then unlinks by FD.
-- A failed cleanup retains detached bytes and cannot reselect the old data.
purgeRuntimeRoots :: LifecycleLease -> FilePath -> String -> Bool -> IO ()
purgeRuntimeRoots lease root token full = do
  validateLifecycleScope lease root
  withCString root $ \path -> withCString token $ \generation ->
    throwErrnoIfMinus1_ "purge runtime roots" (cPurge path generation (if full then 1 else 0))
