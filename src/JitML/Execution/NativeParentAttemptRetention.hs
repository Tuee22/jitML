{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Concrete, append-only attempt filesystem retention. These capabilities
-- establish only this IO/readback path, never authenticity or qualification.
module JitML.Execution.NativeParentAttemptRetention
  ( ReservedNativeParentAttempt
  , RetainedNativeParentAttempt
  , NativeParentAttemptStage (..)
  , NativeParentAttemptFailure (..)
  , NativeParentAttemptFileKind (..)
  , NativeParentAttemptFileData (..)
  , NativeParentAttemptInventory (..)
  , reserveNativeParentAttempt
  , retainNativeParentAttemptResult
  , reservedNativeParentAttemptDirectory
  , reservedNativeParentAttemptScopeSha256
  , reservedNativeParentAttemptIssued
  , retainedNativeParentAttemptReserved
  , retainedNativeParentAttemptDirectory
  , retainedNativeParentAttemptInventory
  , checkNativeParentAttemptByteCount
  ) where

import Codec.CBOR.Encoding qualified as CBOR
import Codec.CBOR.Write qualified as CBOR
import Control.Exception (IOException, bracket, evaluate, onException, try)
import Control.Exception.Safe (tryAny)
import Control.Monad (foldM_, unless)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Char (intToDigit, ord)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.List (sort)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as UTF8
import Data.Word (Word64)
import System.Directory (canonicalizePath, createDirectory)
import System.FilePath (isAbsolute, normalise, splitDirectories, takeDirectory, (</>))
import System.IO (Handle, IOMode (ReadMode), hClose, hFlush, hSetBinaryMode, withBinaryFile)
import System.IO.Error (isDoesNotExistError)
import System.Posix.Directory qualified as Directory
import System.Posix.Files
  ( getSymbolicLinkStatus
  , isDirectory
  , isRegularFile
  , isSymbolicLink
  , setFileMode
  )
import System.Posix.IO
  ( OpenFileFlags (cloexec, creat, exclusive)
  , OpenMode (WriteOnly)
  , closeFd
  , defaultFileFlags
  , fdToHandle
  , openFd
  )

import JitML.Checkpoint.NativePhase.Failure (NativeDiagnosticData, captureNativeExceptionDiagnostic)
import JitML.Substrate (renderSubstrate)
import JitML.Training.Budget
  ( ProductScenarioInvocation
  , productScenarioInvocationRowId
  , productScenarioInvocationRunId
  , productScenarioInvocationSubstrate
  )

data NativeParentAttemptStage
  = AttemptReservationInput
  | AttemptReservationFilesystem
  | AttemptIssuedWrite
  | AttemptResultClaim
  | AttemptResultInput
  | AttemptResultWrite
  | AttemptResultReadback
  deriving stock (Eq, Show)

data NativeParentAttemptFailure = NativeParentAttemptFailure
  { nativeParentAttemptFailureStage :: !NativeParentAttemptStage
  , nativeParentAttemptFailureDirectory :: !(Maybe FilePath)
  , nativeParentAttemptFailureDiagnostic :: !NativeDiagnosticData
  }
  deriving stock (Eq, Show)

data NativeParentAttemptFileKind
  = IssuedRecordFile
  | ParentReportFile
  | ParentStdoutFile
  | ParentStderrFile
  | RawAvailabilityFile
  deriving stock (Eq, Show)

-- Public ordinary DATA is not a filesystem capability.
data NativeParentAttemptFileData = NativeParentAttemptFileData
  { nativeParentAttemptFileKind :: !NativeParentAttemptFileKind
  , nativeParentAttemptFilePath :: !FilePath
  , nativeParentAttemptFileBytes :: !Word64
  , nativeParentAttemptFileSha256 :: !Text
  }
  deriving stock (Eq, Show)

data NativeParentAttemptInventory = NativeParentAttemptInventory
  { nativeParentAttemptIssuedFile :: !NativeParentAttemptFileData
  , nativeParentAttemptReportFile :: !NativeParentAttemptFileData
  , nativeParentAttemptStdoutFile :: !(Maybe NativeParentAttemptFileData)
  , nativeParentAttemptStderrFile :: !(Maybe NativeParentAttemptFileData)
  , nativeParentAttemptAvailabilityFile :: !NativeParentAttemptFileData
  }
  deriving stock (Eq, Show)

data ReservedNativeParentAttempt
  = ReservedNativeParentAttempt
      !FilePath
      !Text
      !NativeParentAttemptFileData
  deriving stock (Show)

data RetainedNativeParentAttempt
  = RetainedNativeParentAttempt
      !ReservedNativeParentAttempt
      !FilePath
      !NativeParentAttemptInventory
  deriving stock (Show)

reservedNativeParentAttemptDirectory :: ReservedNativeParentAttempt -> FilePath
reservedNativeParentAttemptDirectory (ReservedNativeParentAttempt directory _ _) = directory
reservedNativeParentAttemptScopeSha256 :: ReservedNativeParentAttempt -> Text
reservedNativeParentAttemptScopeSha256 (ReservedNativeParentAttempt _ scope _) = scope
reservedNativeParentAttemptIssued :: ReservedNativeParentAttempt -> NativeParentAttemptFileData
reservedNativeParentAttemptIssued (ReservedNativeParentAttempt _ _ issued) = issued
retainedNativeParentAttemptReserved :: RetainedNativeParentAttempt -> ReservedNativeParentAttempt
retainedNativeParentAttemptReserved (RetainedNativeParentAttempt reserved _ _) = reserved
retainedNativeParentAttemptDirectory :: RetainedNativeParentAttempt -> FilePath
retainedNativeParentAttemptDirectory (RetainedNativeParentAttempt _ directory _) = directory
retainedNativeParentAttemptInventory :: RetainedNativeParentAttempt -> NativeParentAttemptInventory
retainedNativeParentAttemptInventory (RetainedNativeParentAttempt _ _ inventory) = inventory

-- Ordinary count validation only: no IO, reservation, retention or cap factory.
checkNativeParentAttemptByteCount :: NativeParentAttemptFileKind -> Integer -> Either Text ()
checkNativeParentAttemptByteCount kind count
  | count < 0 = Left "native parent attempt byte count is negative"
  | count > fileLimit kind = Left "native parent attempt file exceeds its exact role byte cap"
  | otherwise = Right ()

fileLimit :: NativeParentAttemptFileKind -> Integer
fileLimit IssuedRecordFile = 64 * 1024
fileLimit ParentReportFile = 4 * 1024 * 1024 * 1024
fileLimit ParentStdoutFile = 1024 * 1024 * 1024
fileLimit ParentStderrFile = 1024 * 1024 * 1024
fileLimit RawAvailabilityFile = 4096

type Progress = IORef (NativeParentAttemptStage, Maybe FilePath)

reserveNativeParentAttempt
  :: FilePath
  -> ProductScenarioInvocation
  -> ByteString
  -> IO (Either NativeParentAttemptFailure ReservedNativeParentAttempt)
reserveNativeParentAttempt childWorkdir invocation issued = safely AttemptReservationInput $ \progress -> do
  -- All issued/scope/path bounds are forced before filesystem IO.
  requireCount IssuedRecordFile (toInteger (BS.length issued))
  require (length (take 4097 childWorkdir) <= 4096) "child workdir exceeds its path character cap"
  require
    (isAbsolute childWorkdir && normalise childWorkdir == childWorkdir)
    "child workdir must be absolute and normalized"
  let runId = productScenarioInvocationRunId invocation
      rowId = productScenarioInvocationRowId invocation
      lane = renderSubstrate (productScenarioInvocationSubstrate invocation)
  mapM_
    (\value -> require (Text.length value <= 4096) "attempt scope text exceeds its character cap")
    [runId, rowId, lane]
  let slotBytes =
        encodeStrict $
          CBOR.encodeListLen 4
            <> CBOR.encodeString "jitml-native-parent-attempt-slot-v1"
            <> CBOR.encodeString runId
            <> CBOR.encodeString rowId
            <> CBOR.encodeString lane
      scopeSha = hex (SHA256.hash slotBytes)
      slot = childWorkdir </> ".build" </> "native-parent-attempts" </> Text.unpack scopeSha
  _ <- evaluate (BS.length slotBytes + Text.length scopeSha + length slot)
  setProgress progress AttemptReservationFilesystem (Just slot)
  ensureDirectoryPath childWorkdir
  canonical <- canonicalizePath childWorkdir
  require (canonical == childWorkdir) "child workdir differs from its physical canonical path"
  ensureParentDirectory (childWorkdir </> ".build")
  ensureParentDirectory (childWorkdir </> ".build" </> "native-parent-attempts")
  -- This exact atomic create consumes the stable runId/row/lane slot. There is
  -- deliberately no remove/rollback on any later failure or cancellation.
  createPrivateDirectory slot
  setProgress progress AttemptIssuedWrite (Just slot)
  issuedFile <- writeStrict IssuedRecordFile (slot </> "issued.cbor") issued
  requireMembers slot ["issued.cbor"]
  pure (ReservedNativeParentAttempt slot scopeSha issuedFile)

retainNativeParentAttemptResult
  :: ReservedNativeParentAttempt
  -> String
  -> Maybe (LBS.ByteString, LBS.ByteString)
  -> IO (Either NativeParentAttemptFailure RetainedNativeParentAttempt)
retainNativeParentAttemptResult reserved report raw = safely AttemptResultClaim $ \progress -> do
  let slot = reservedNativeParentAttemptDirectory reserved
      resultDirectory = slot </> "result"
  _ <- evaluate (length slot)
  setProgress progress AttemptResultClaim (Just slot)
  ensureDirectoryPath slot
  requireMembers slot ["issued.cbor"]
  -- Claim before touching report/raw input. The terminal attempt remains spent
  -- even if those values are lazy, oversized, faulty or asynchronously killed.
  createPrivateDirectory resultDirectory
  setProgress progress AttemptResultInput (Just slot)
  rawCounts <- case raw of
    Nothing -> pure Nothing
    Just (stdoutBytes, stderrBytes) -> do
      stdoutCount <- countLazy ParentStdoutFile stdoutBytes
      stderrCount <- countLazy ParentStderrFile stderrBytes
      pure (Just (stdoutCount, stderrCount))
  setProgress progress AttemptResultWrite (Just slot)
  reportFile <-
    writeExclusive ParentReportFile (resultDirectory </> "report.utf8") (writeReport report)
  (stdoutFile, stderrFile) <- case (raw, rawCounts) of
    (Nothing, Nothing) -> pure (Nothing, Nothing)
    (Just (stdoutBytes, stderrBytes), Just (stdoutCount, stderrCount)) -> do
      stdoutFile <- writeLazy ParentStdoutFile (resultDirectory </> "stdout.bin") stdoutCount stdoutBytes
      stderrFile <- writeLazy ParentStderrFile (resultDirectory </> "stderr.bin") stderrCount stderrBytes
      pure (Just stdoutFile, Just stderrFile)
    _ -> ioError (userError "raw availability changed during retention")
  let present = case rawCounts of Nothing -> False; Just _ -> True
      availability =
        encodeStrict $
          CBOR.encodeListLen 4
            <> CBOR.encodeString "jitml-native-parent-raw-availability-v1"
            <> CBOR.encodeWord 1
            <> CBOR.encodeBool present
            <> CBOR.encodeBool present
  availabilityFile <-
    writeStrict RawAvailabilityFile (resultDirectory </> "availability.cbor") availability
  setProgress progress AttemptResultReadback (Just slot)
  issuedFile <- rereadExpected (reservedNativeParentAttemptIssued reserved)
  requireMembers slot ["issued.cbor", "result"]
  requireMembers resultDirectory $
    ["report.utf8", "availability.cbor"] <> if present then ["stdout.bin", "stderr.bin"] else []
  let inventory = NativeParentAttemptInventory issuedFile reportFile stdoutFile stderrFile availabilityFile
  pure (RetainedNativeParentAttempt reserved resultDirectory inventory)

safely :: NativeParentAttemptStage -> (Progress -> IO a) -> IO (Either NativeParentAttemptFailure a)
safely initial action = do
  progress <- newIORef (initial, Nothing)
  result <- tryAny (action progress >>= evaluate)
  case result of
    Right actual -> pure (Right actual)
    Left exception -> do
      (stage, directory) <- readIORef progress
      diagnostic <- captureNativeExceptionDiagnostic exception
      pure (Left (NativeParentAttemptFailure stage directory diagnostic))

setProgress :: Progress -> NativeParentAttemptStage -> Maybe FilePath -> IO ()
setProgress progress stage directory = writeIORef progress (stage, directory)

require :: Bool -> String -> IO ()
require condition reason = unless condition (ioError (userError reason))

requireCount :: NativeParentAttemptFileKind -> Integer -> IO ()
requireCount kind count = either (ioError . userError . Text.unpack) pure (checkNativeParentAttemptByteCount kind count)

encodeStrict :: CBOR.Encoding -> ByteString
encodeStrict = LBS.toStrict . CBOR.toLazyByteString

-- Every observed prefix is checked with lstat semantics; dangling links refuse.
-- Exclusive creation + checks are not claimed to resist a hostile concurrent
-- rename race. No openat/fsync/power-loss or authentication guarantee is made.
ensureDirectoryPath :: FilePath -> IO ()
ensureDirectoryPath path = foldM_ check "" (splitDirectories path)
 where
  check prefix component = do
    let current = if null prefix then component else prefix </> component
    status <- getSymbolicLinkStatus current
    require
      (not (isSymbolicLink status) && isDirectory status)
      "attempt path prefix is not a real directory"
    pure current

ensureParentDirectory :: FilePath -> IO ()
ensureParentDirectory path = do
  ensureDirectoryPath (takeDirectory path)
  observed <- try (getSymbolicLinkStatus path)
  case observed of
    Right status ->
      require (not (isSymbolicLink status) && isDirectory status) "attempt parent is not a real directory"
    Left (exception :: IOException)
      | isDoesNotExistError exception -> createPrivateDirectory path
      | otherwise -> ioError exception

createPrivateDirectory :: FilePath -> IO ()
createPrivateDirectory path = do
  ensureDirectoryPath (takeDirectory path)
  createDirectory path
  setFileMode path 0o700
  ensureDirectoryPath path

requireMembers :: FilePath -> [FilePath] -> IO ()
requireMembers directory expected = do
  ensureDirectoryPath directory
  -- Enumerate at most the expected members plus the first foreign member.
  -- A hostile directory cannot cause a full unbounded list allocation first.
  actual <-
    bracket (Directory.openDirStream directory) Directory.closeDirStream (collect (length expected) [])
  require (sort actual == sort expected) "attempt directory has missing or unexpected members"
 where
  collect remaining actual stream = do
    entry <- Directory.readDirStream stream
    if null entry
      then pure actual
      else
        if entry == "." || entry == ".."
          then collect remaining actual stream
          else do
            require (remaining > 0) "attempt directory exceeds its exact member-count bound"
            collect (remaining - 1) (entry : actual) stream

withExclusiveFile :: FilePath -> (Handle -> IO a) -> IO a
withExclusiveFile path action = do
  ensureDirectoryPath (takeDirectory path)
  bracket acquire hClose $ \handle -> do
    hSetBinaryMode handle True
    actual <- action handle
    hFlush handle
    pure actual
 where
  acquire = do
    descriptor <-
      openFd path WriteOnly defaultFileFlags {creat = Just 0o600, exclusive = True, cloexec = True}
    fdToHandle descriptor `onException` closeFd descriptor

writeStrict
  :: NativeParentAttemptFileKind -> FilePath -> ByteString -> IO NativeParentAttemptFileData
writeStrict kind path bytes = do
  requireCount kind (toInteger (BS.length bytes))
  writeExclusive kind path $ \handle -> do
    BS.hPut handle bytes
    pure (toInteger (BS.length bytes), SHA256.hash bytes)

writeExclusive
  :: NativeParentAttemptFileKind
  -> FilePath
  -> (Handle -> IO (Integer, ByteString))
  -> IO NativeParentAttemptFileData
writeExclusive kind path writer = do
  (count, digest) <- withExclusiveFile path writer
  requireCount kind count
  let expected = NativeParentAttemptFileData kind path (fromInteger count) (hex digest)
  rereadExpected expected

rereadExpected :: NativeParentAttemptFileData -> IO NativeParentAttemptFileData
rereadExpected expected = do
  let path = nativeParentAttemptFilePath expected
      expectedCount = toInteger (nativeParentAttemptFileBytes expected)
      kind = nativeParentAttemptFileKind expected
  requireCount kind expectedCount
  ensureDirectoryPath (takeDirectory path)
  status <- getSymbolicLinkStatus path
  require
    (not (isSymbolicLink status) && isRegularFile status)
    "attempt member is not a regular physical file"
  (actualCount, actualDigest) <-
    withBinaryFile path ReadMode (readBounded expectedCount SHA256.init 0)
  require
    (actualCount == expectedCount && hex actualDigest == nativeParentAttemptFileSha256 expected)
    "attempt physical readback byte count or SHA256 differs"
  pure expected
 where
  readBounded expectedCount !context !count handle = do
    -- Read at most expected+1 total; never materialize a huge unexpected file.
    let remaining = expectedCount - count + 1
    chunk <- BS.hGetSome handle (fromInteger (min 65536 remaining))
    if BS.null chunk
      then pure (count, SHA256.finalize context)
      else do
        let nextCount = count + toInteger (BS.length chunk)
        require (nextCount <= expectedCount) "attempt physical file exceeds expected byte count"
        readBounded expectedCount (SHA256.update context chunk) nextCount handle

countLazy :: NativeParentAttemptFileKind -> LBS.ByteString -> IO Integer
countLazy kind = loop 0 . LBS.toChunks
 where
  loop !count [] = pure count
  loop !count (chunk : rest) = do
    let next = count + toInteger (BS.length chunk)
    requireCount kind next
    loop next rest

writeLazy
  :: NativeParentAttemptFileKind
  -> FilePath
  -> Integer
  -> LBS.ByteString
  -> IO NativeParentAttemptFileData
writeLazy kind path preCounted bytes = writeExclusive kind path (loop SHA256.init 0 (LBS.toChunks bytes))
 where
  loop !context !count [] _handle = do
    require (count == preCounted) "raw stream differs from its forced pre-write count"
    pure (count, SHA256.finalize context)
  loop !context !count (chunk : rest) handle = do
    let next = count + toInteger (BS.length chunk)
    requireCount kind next
    require (next <= preCounted) "raw stream exceeds its forced pre-write count"
    BS.hPut handle chunk
    loop (SHA256.update context chunk) next rest handle

writeReport :: String -> Handle -> IO (Integer, ByteString)
writeReport = loop SHA256.init 0
 where
  loop !context !count [] _handle = pure (count, SHA256.finalize context)
  loop !context !count remaining handle = do
    let (characters, rest) = splitAt 4096 remaining
    -- Text.pack would replace surrogate code points; refuse that lossy case.
    require
      (all (\character -> ord character < 0xd800 || ord character > 0xdfff) characters)
      "report contains a Unicode surrogate code point"
    let bytes = UTF8.encodeUtf8 (Text.pack characters)
        next = count + toInteger (BS.length bytes)
    requireCount ParentReportFile next
    BS.hPut handle bytes
    loop (SHA256.update context bytes) next rest handle

hex :: ByteString -> Text
hex = Text.pack . concatMap byteHex . BS.unpack
 where
  byteHex byte = [intToDigit (fromIntegral byte `div` 16), intToDigit (fromIntegral byte `mod` 16)]
