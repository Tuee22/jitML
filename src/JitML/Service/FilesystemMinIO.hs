{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.FilesystemMinIO
  ( FilesystemMinIO (..)
  , runFilesystemMinIO
  )
where

import Control.Concurrent.MVar (MVar, newMVar, withMVar)
import Control.Exception (IOException, bracket, bracket_, try)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Reader (MonadReader, ReaderT, ask, runReaderT)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified as ByteString
import Data.Char (intToDigit)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word8)
import System.Directory
  ( createDirectoryIfMissing
  , doesFileExist
  , listDirectory
  , removeFile
  , renameFile
  )
import System.FilePath ((</>))
import System.IO (SeekMode (AbsoluteSeek), hFlush)
import System.IO.Temp (withTempFile)
import System.IO.Unsafe (unsafePerformIO)
import System.Posix.Files (createLink)
import System.Posix.IO
  ( LockRequest (Unlock, WriteLock)
  , OpenFileFlags (creat)
  , OpenMode (WriteOnly)
  , closeFd
  , defaultFileFlags
  , openFd
  , setLock
  , waitToSetLock
  )

import JitML.Service.Capabilities
  ( BucketName (..)
  , ETag (..)
  , HasMinIO (..)
  , ObjectKey (..)
  , ObjectRef (..)
  )
import JitML.Service.Retry (ServiceError (..))

-- | Filesystem-backed `HasMinIO` instance. Maps each bucket to a directory
-- under `<root>/<bucket>/` and each key to a file. The instance honours the
-- conditional-write semantics:
--
-- - `putBlobIfAbsent` writes only if the file does not exist, returning
--   `SEConflict` otherwise (mirrors `If-None-Match: *` → 412).
-- - `casPointer` writes only if the recorded ETag matches the current
--   content's SHA-256 (or the file does not yet exist when expected = Nothing),
--   returning `SEConflict` otherwise (mirrors `If-Match: <etag>` → 412).
--
-- The instance is used by `jitml-integration` to exercise the conditional
-- semantics end-to-end without a live MinIO server; the typed surface is
-- identical to the production HTTP client.
newtype FilesystemMinIO a = FilesystemMinIO
  { unFilesystemMinIO :: ReaderT FilePath IO a
  }
  deriving newtype
    ( Functor
    , Applicative
    , Monad
    , MonadIO
    , MonadReader FilePath
    )

runFilesystemMinIO :: FilePath -> FilesystemMinIO a -> IO a
runFilesystemMinIO root action = do
  createDirectoryIfMissing True root
  runReaderT (unFilesystemMinIO action) root

objectPath :: FilePath -> ObjectRef -> FilePath
objectPath root ref =
  root </> Text.unpack (unBucketName (objectBucket ref)) </> Text.unpack (unObjectKey (objectKey ref))

prefixPath :: FilePath -> BucketName -> FilePath
prefixPath root bucket =
  root </> Text.unpack (unBucketName bucket)

instance HasMinIO FilesystemMinIO where
  minioPutIfAbsent ref payload = do
    root <- ask
    let path = objectPath root ref
    created <- liftIO (createBytesIfAbsent path (Text.Encoding.encodeUtf8 payload))
    pure $
      case created of
        Left err -> Left err
        Right () -> Right ref

  minioReadObject ref = do
    root <- ask
    let path = objectPath root ref
    exists <- liftIO (doesFileExist path)
    if exists
      then fmap Right (liftIO (readText path))
      else pure (Left (SEUnauthorized "filesystem: object missing"))

  minioReadBytes ref = do
    root <- ask
    let path = objectPath root ref
    exists <- liftIO (doesFileExist path)
    if exists
      then fmap Right (liftIO (ByteString.readFile path))
      else pure (Left (SEUnauthorized "filesystem: object missing"))

  putBlobBytesIfAbsent ref payload = do
    root <- ask
    let path = objectPath root ref
    created <- liftIO (createBytesIfAbsent path payload)
    pure $
      case created of
        Left err -> Left err
        Right () -> Right (ETag (sha256BytesHex payload))

  putBlobIfAbsent ref payload = do
    root <- ask
    let path = objectPath root ref
    created <- liftIO (createBytesIfAbsent path (Text.Encoding.encodeUtf8 payload))
    pure $
      case created of
        Left err -> Left err
        Right () -> Right (ETag (sha256Hex payload))

  casPointer ref expected payload = do
    root <- ask
    let path = objectPath root ref
    liftIO (casPointerBytes path expected payload)

  listObjects bucket prefix = do
    root <- ask
    let dir = prefixPath root bucket
    exists <- liftIO (doesFileExist dir)
    entries <-
      liftIO
        ( if exists
            then pure []
            else listDirectoryQuiet dir
        )
    pure
      ( Right
          [ ObjectRef bucket (ObjectKey (Text.pack entry))
          | entry <- entries
          , Text.pack entry `Text.isPrefixOf` prefix || Text.null prefix
          ]
      )

  deleteObject ref = do
    root <- ask
    let path = objectPath root ref
    exists <- liftIO (doesFileExist path)
    if exists
      then liftIO (removeFile path) >> pure (Right ())
      else pure (Left (SEUnauthorized "filesystem: object missing"))

readText :: FilePath -> IO Text
readText path =
  fmap Text.Encoding.decodeUtf8 (ByteString.readFile path)

sha256Hex :: Text -> Text
sha256Hex =
  sha256BytesHex . Text.Encoding.encodeUtf8

sha256BytesHex :: ByteString.ByteString -> Text
sha256BytesHex =
  Text.pack . concatMap byteHex . ByteString.unpack . SHA256.hash
 where
  byteHex :: Word8 -> String
  byteHex byte =
    [ intToDigit (fromIntegral byte `div` 16)
    , intToDigit (fromIntegral byte `mod` 16)
    ]

createBytesIfAbsent
  :: FilePath -> ByteString.ByteString -> IO (Either ServiceError ())
createBytesIfAbsent path payload = do
  createDirectoryIfMissing True (takeDirectory' path)
  created <-
    try
      ( withTempFile (takeDirectory' path) ".jitml-minio-object.tmp" $ \tempPath handle -> do
          ByteString.hPut handle payload
          hFlush handle
          createLink tempPath path
      )
      :: IO (Either IOException ())
  pure $
    case created of
      Right () -> Right ()
      Left _ -> Left (SEConflict "filesystem: object exists")

casPointerBytes
  :: FilePath -> Maybe ETag -> Text -> IO (Either ServiceError ETag)
casPointerBytes path expected payload = do
  withMVar filesystemPointerCasProcessLock $ \() -> do
    createDirectoryIfMissing True (takeDirectory' path)
    let lockPath = path <> ".lock"
        lock = (WriteLock, AbsoluteSeek, 0, 0)
    bracket
      (openFd lockPath WriteOnly defaultFileFlags {creat = Just 0o600})
      closeFd
      ( \lockFd ->
          bracket_
            (waitToSetLock lockFd lock)
            (setLock lockFd (Unlock, AbsoluteSeek, 0, 0))
            ( do
                exists <- doesFileExist path
                currentEtag <-
                  if exists
                    then Just . ETag . sha256BytesHex <$> ByteString.readFile path
                    else pure Nothing
                if currentEtag /= expected
                  then pure (Left (SEConflict "filesystem: pointer CAS mismatch"))
                  else do
                    withTempFile (takeDirectory' path) ".jitml-minio-pointer.tmp" $ \tempPath handle -> do
                      ByteString.hPut handle (Text.Encoding.encodeUtf8 payload)
                      hFlush handle
                      renameFile tempPath path
                    pure (Right (ETag (sha256Hex payload)))
            )
      )

-- fcntl locks coordinate processes, not threads within one process.
filesystemPointerCasProcessLock :: MVar ()
filesystemPointerCasProcessLock = unsafePerformIO (newMVar ())
{-# NOINLINE filesystemPointerCasProcessLock #-}

takeDirectory' :: FilePath -> FilePath
takeDirectory' path =
  case break (== '/') (reverse path) of
    (_, '/' : rest) -> reverse rest
    _ -> "."

listDirectoryQuiet :: FilePath -> IO [FilePath]
listDirectoryQuiet path = do
  exists <- doesFileExist path
  if exists
    then pure []
    else listDirectory path
