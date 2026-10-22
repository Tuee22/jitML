{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Copy only a SourceJournal's actual retained file plan. No DATA decoder
-- constructs this plan, and completing a copy grants no execution authority.
module JitML.Test.NativeLaneBundle.Write
  ( NativeBundleWritePlan
  , makeNativeBundleWritePlan
  , nativeBundleWritePlanReference
  , nativeBundleWritePlanRoot
  , writeNativeBundleObjects
  , prepareNativeBundleDirectory
  , copyNativeBundleFileData
  , readNativeBundleObjectBytes
  , verifyNativeBundleObjectFile
  ) where

import Control.Exception (IOException, bracket, evaluate, try)
import Control.Exception.Safe (tryAny)
import Control.Monad (unless)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Char (intToDigit)
import Data.Foldable (for_)
import Data.List (sortOn)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import System.Directory (createDirectory, removeFile)
import System.FilePath (splitDirectories, takeDirectory, (</>))
import System.IO (Handle, IOMode (ReadMode), hClose, hFileSize, openBinaryTempFile, withBinaryFile)
import System.IO.Error (isAlreadyExistsError, isDoesNotExistError)
import System.Posix.Files
  ( createLink
  , getSymbolicLinkStatus
  , isDirectory
  , isRegularFile
  , isSymbolicLink
  )

import JitML.Checkpoint.NativePhase.Failure qualified as Failure
import JitML.Checkpoint.NativePhase.Types
import JitML.Test.NativeLaneBundle.Data
import JitML.Test.NativeScenarioRetention qualified as Retained

data NativeBundleWritePlan
  = NativeBundleWritePlan
      !NativeBundleRootData
      !NativeBundleReferenceData
      !ByteString
      ![Retained.NativeScenarioPortableFileData]
  deriving stock (Eq, Show)

makeNativeBundleWritePlan
  :: Retained.AuthenticatedRetainedNativeQualification
  -> Either CodecError NativeBundleWritePlan
makeNativeBundleWritePlan retained = do
  let files =
        sortOn
          Retained.nativePortableObjectKey
          (Retained.nativePortableFiles (Retained.retainedNativeScenarioPortableInventory retained))
      root =
        NativeBundleRootData
          (Retained.retainedNativeScenarioBinding retained)
          (Retained.retainedNativeScenarioReceiptData retained)
          [ NativeBundleObjectData
              (Retained.nativePortableObjectKey file)
              (Retained.nativePortableObjectSha256 file)
              (Retained.nativePortableObjectBytes file)
          | file <- files
          ]
  count <- boundedLength AggregateSequenceElements maximumNativeBundleObjects files
  unless (count > 0) (Left (Malformed "native portable write plan has no retained files"))
  mapM_ checkFile files
  _ <- foldCounts Map.empty files
  rootBytes <- encodeNativeBundleRootData root
  reference <- nativeBundleRootReference root
  pure (NativeBundleWritePlan root reference rootBytes files)
 where
  checkFile file =
    unless
      ( Retained.nativePortableObjectMaximumBytes file >= 0
          && toInteger (Retained.nativePortableObjectBytes file)
            <= Retained.nativePortableObjectMaximumBytes file
      )
      (Left (Malformed "native portable retained count exceeds its original role cap"))
  foldCounts seen [] = Right seen
  foldCounts seen (file : rest) = case Map.lookup (Retained.nativePortableObjectSha256 file) seen of
    Just count
      | count /= Retained.nativePortableObjectBytes file ->
          Left (Malformed "native portable same SHA has conflicting file byte counts")
    _ ->
      foldCounts
        ( Map.insert
            (Retained.nativePortableObjectSha256 file)
            (Retained.nativePortableObjectBytes file)
            seen
        )
        rest

nativeBundleWritePlanReference :: NativeBundleWritePlan -> NativeBundleReferenceData
nativeBundleWritePlanReference (NativeBundleWritePlan _ reference _ _) = reference
nativeBundleWritePlanRoot :: NativeBundleWritePlan -> NativeBundleRootData
nativeBundleWritePlanRoot (NativeBundleWritePlan root _ _ _) = root

-- Objects and root become visible before the main journal is atomically
-- issued by Lane. Failed/partial copies never produce a main journal.
writeNativeBundleObjects
  :: FilePath
  -> NativeBundleWritePlan
  -> IO (Either Failure.NativeDiagnosticData ())
writeNativeBundleObjects journalPath plan = do
  attempted <- tryAny $ do
    _ <- evaluate plan
    checkedPath <- boundedIOPath journalPath
    let NativeBundleWritePlan _ reference rootBytes files = plan
        directory = checkedPath <> ".qualifications"
    prepareDirectory directory
    mapM_ (copyOne directory) files
    basename <- codecIO (nativeBundleObjectBasename (nativeBundleReferenceSha256 reference))
    writeRoot directory basename reference rootBytes
  case attempted of
    Left exception -> Left <$> Failure.captureNativeExceptionDiagnostic exception
    Right () -> pure (Right ())

-- Lane calls this before writing any detached objects for a native-bearing
-- journal. Each missing prefix is created only after its actual parent passed
-- lstat; dangling links are never interpreted as an absent directory.
prepareNativeBundleDirectory :: FilePath -> IO (Either Failure.NativeDiagnosticData ())
prepareNativeBundleDirectory journalPath = do
  attempted <- tryAny $ do
    path <- boundedIOPath journalPath
    prepareDirectory (path <> ".qualifications")
  case attempted of
    Left exception -> Left <$> Failure.captureNativeExceptionDiagnostic exception
    Right () -> pure (Right ())

prepareDirectory :: FilePath -> IO ()
prepareDirectory = mapM_ ensureObjectDirectory . pathPrefixes

-- | Forgeable FILE utility only. Useful for independent byte-copy controls;
-- this does not create a write plan, Lane journal or private audit.
copyNativeBundleFileData
  :: FilePath
  -> Retained.NativeScenarioPortableFileData
  -> IO (Either Failure.NativeDiagnosticData ())
copyNativeBundleFileData journalPath file = do
  attempted <- tryAny $ do
    path <- boundedIOPath journalPath
    _ <- boundedIOPath (Retained.nativePortableOriginalPath file)
    let directory = path <> ".qualifications"
    prepareDirectory directory
    copyOne directory file
  case attempted of
    Left exception -> Left <$> Failure.captureNativeExceptionDiagnostic exception
    Right () -> pure (Right ())

-- These two ordinary FILE utilities confer no qualification. Read uses only
-- a checked SHA basename, exact expected count and an independently chosen
-- role cap. Large report/raw roles must use stream verification instead.
readNativeBundleObjectBytes :: FilePath -> NativeBundleObjectData -> Integer -> IO ByteString
readNativeBundleObjectBytes directory object cap = do
  basename <- codecIO (nativeBundleObjectBasename (nativeBundleObjectSha256 object))
  let path = directory </> basename
      expected = toInteger (nativeBundleObjectBytes object)
  ioRequire
    (expected <= cap && expected < toInteger (maxBound :: Int))
    "native portable strict object exceeds its role or Int allocation cap"
  ensureRegularPath path
  bytes <- withBinaryFile path ReadMode $ \handle -> do
    size <- hFileSize handle
    ioRequire (size == expected) "native portable strict object size differs"
    BS.hGet handle (fromInteger expected + 1)
  ioRequire
    ( toInteger (BS.length bytes) == expected
        && hex (SHA256.hash bytes) == nativeBundleObjectSha256 object
    )
    "native portable strict object actual count/SHA differs"
  ensureRegularPath path
  pure bytes

verifyNativeBundleObjectFile :: FilePath -> NativeBundleObjectData -> Integer -> IO ()
verifyNativeBundleObjectFile directory object cap = do
  basename <- codecIO (nativeBundleObjectBasename (nativeBundleObjectSha256 object))
  let path = directory </> basename
      expected = toInteger (nativeBundleObjectBytes object)
  ioRequire (expected <= cap) "native portable streamed object exceeds its role cap"
  ensureRegularPath path
  withBinaryFile path ReadMode $ \handle -> do
    size <- hFileSize handle
    ioRequire (size == expected) "native portable streamed object size differs"
    (actual, count) <- stream handle Nothing expected
    ioRequire
      (actual == nativeBundleObjectSha256 object && count == expected)
      "native portable streamed object actual count/SHA differs"
  ensureRegularPath path

copyOne :: FilePath -> Retained.NativeScenarioPortableFileData -> IO ()
copyOne directory file = do
  basename <- codecIO (nativeBundleObjectBasename (Retained.nativePortableObjectSha256 file))
  let path = Retained.nativePortableOriginalPath file
      expected = toInteger (Retained.nativePortableObjectBytes file)
  ensureRegularPath path
  ioRequire
    (expected <= Retained.nativePortableObjectMaximumBytes file)
    "native portable source count exceeds its original role cap"
  withBinaryFile path ReadMode $ \source -> do
    size <- hFileSize source
    ioRequire (size == expected) "native portable source file size changed before copy"
    temporary directory $ \temporaryPath destination -> do
      (digest, count) <- stream source (Just destination) expected
      ioRequire
        (count == expected && digest == Retained.nativePortableObjectSha256 file)
        "native portable source actual bytes differ from its retained count/SHA"
      hClose destination
      install temporaryPath (directory </> basename) digest expected
  ensureRegularPath path

writeRoot :: FilePath -> FilePath -> NativeBundleReferenceData -> ByteString -> IO ()
writeRoot directory basename reference bytes =
  temporary directory $ \temporaryPath handle -> do
    BS.hPut handle bytes
    hClose handle
    install
      temporaryPath
      (directory </> basename)
      (nativeBundleReferenceSha256 reference)
      (toInteger (nativeBundleReferenceBytes reference))

-- Hard-link creation is create-only. The temporary is already fully closed
-- and verified. An existing SHA object must independently agree exactly.
install :: FilePath -> FilePath -> Text -> Integer -> IO ()
install temporaryPath target sha count = do
  created <- tryIO (createLink temporaryPath target)
  case created of
    Left exception | isAlreadyExistsError exception -> pure ()
    Left exception -> ioError exception
    Right () -> pure ()
  ensureRegularPath target
  withBinaryFile target ReadMode $ \handle -> do
    size <- hFileSize handle
    ioRequire (size == count) "native portable existing destination count differs"
    (actual, actualCount) <- stream handle Nothing count
    ioRequire (actual == sha && actualCount == count) "native portable destination bytes differ"
  ensureRegularPath target

temporary :: FilePath -> (FilePath -> Handle -> IO a) -> IO a
temporary directory =
  bracket
    (openBinaryTempFile directory ".native-bundle-copy")
    ( \(path, handle) -> do
        _ <- tryIO (hClose handle)
        removeFile path
    )
    . uncurry

stream :: Handle -> Maybe Handle -> Integer -> IO (Text, Integer)
stream source destination expected = loop SHA256.init 0
 where
  loop !context !count = do
    chunk <- BS.hGetSome source (fromInteger (min 65536 (expected - count + 1)))
    if BS.null chunk
      then pure (hex (SHA256.finalize context), count)
      else do
        let next = count + toInteger (BS.length chunk)
        ioRequire (next <= expected) "native portable physical file exceeds expected count"
        for_ destination (`BS.hPut` chunk)
        loop (SHA256.update context chunk) next

ensureObjectDirectory :: FilePath -> IO ()
ensureObjectDirectory path = do
  status <- tryIO (getSymbolicLinkStatus path)
  case status of
    Left exception | isDoesNotExistError exception -> do
      created <- tryIO (createDirectory path)
      case created of
        Left raced | isAlreadyExistsError raced -> pure ()
        Left problem -> ioError problem
        Right () -> pure ()
    Left exception -> ioError exception
    Right _ -> pure ()
  ensureDirectoryPath path

ensureDirectoryPath :: FilePath -> IO ()
ensureDirectoryPath = mapM_ one . pathPrefixes
 where
  one path = do
    status <- getSymbolicLinkStatus path
    ioRequire
      (isDirectory status && not (isSymbolicLink status))
      "native portable directory prefix is not a real nonlink directory"

ensureRegularPath :: FilePath -> IO ()
ensureRegularPath path = do
  ensureDirectoryPath (takeDirectory path)
  status <- getSymbolicLinkStatus path
  ioRequire
    (isRegularFile status && not (isSymbolicLink status))
    "native portable file is not a real regular nonlink"

pathPrefixes :: FilePath -> [FilePath]
pathPrefixes = filter (not . null) . scanl (</>) "" . splitDirectories

boundedIOPath :: FilePath -> IO FilePath
boundedIOPath path = do
  let prefix = take 4097 path
  ioRequire (length prefix <= 4096) "native portable journal path exceeds its character cap"
  pure prefix

tryIO :: IO a -> IO (Either IOException a)
tryIO = try
ioRequire :: Bool -> String -> IO ()
ioRequire condition message = unless condition (ioError (userError message))
codecIO :: (Show error) => Either error value -> IO value
codecIO = either (ioError . userError . show) pure
hex :: ByteString -> Text
hex =
  Text.pack
    . concatMap
      ( \byte ->
          [intToDigit (div (fromIntegral byte) 16), intToDigit (mod (fromIntegral byte) 16)]
      )
    . BS.unpack
