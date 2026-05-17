{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.FilesystemMinIO
  ( FilesystemMinIO (..)
  , runFilesystemMinIO
  )
where

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
  )
import System.FilePath ((</>))

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
    exists <- liftIO (doesFileExist path)
    if exists
      then pure (Left (SEConflict "filesystem: object exists"))
      else do
        liftIO (createDirectoryIfMissing True (takeDirectory' path))
        liftIO (writeText path payload)
        pure (Right ref)

  minioReadObject ref = do
    root <- ask
    let path = objectPath root ref
    exists <- liftIO (doesFileExist path)
    if exists
      then fmap Right (liftIO (readText path))
      else pure (Left (SEUnauthorized "filesystem: object missing"))

  putBlobIfAbsent ref payload = do
    root <- ask
    let path = objectPath root ref
    exists <- liftIO (doesFileExist path)
    if exists
      then pure (Left (SEConflict "filesystem: object exists"))
      else do
        liftIO (createDirectoryIfMissing True (takeDirectory' path))
        liftIO (writeText path payload)
        pure (Right (ETag (sha256Hex payload)))

  casPointer ref expected payload = do
    root <- ask
    let path = objectPath root ref
    exists <- liftIO (doesFileExist path)
    case (expected, exists) of
      (Nothing, True) -> pure (Left (SEConflict "filesystem: object exists"))
      (Nothing, False) -> do
        liftIO (createDirectoryIfMissing True (takeDirectory' path))
        liftIO (writeText path payload)
        pure (Right (ETag (sha256Hex payload)))
      (Just (ETag expectedEtag), True) -> do
        current <- liftIO (readText path)
        let currentEtag = sha256Hex current
        if currentEtag == expectedEtag
          then do
            liftIO (writeText path payload)
            pure (Right (ETag (sha256Hex payload)))
          else pure (Left (SEConflict "filesystem: object exists"))
      (Just _, False) -> pure (Left (SEConflict "filesystem: object exists"))

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

writeText :: FilePath -> Text -> IO ()
writeText path content =
  ByteString.writeFile path (Text.Encoding.encodeUtf8 content)

readText :: FilePath -> IO Text
readText path =
  fmap Text.Encoding.decodeUtf8 (ByteString.readFile path)

sha256Hex :: Text -> Text
sha256Hex =
  Text.pack . concatMap byteHex . ByteString.unpack . SHA256.hash . Text.Encoding.encodeUtf8
 where
  byteHex :: Word8 -> String
  byteHex byte =
    [ intToDigit (fromIntegral byte `div` 16)
    , intToDigit (fromIntegral byte `mod` 16)
    ]

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
