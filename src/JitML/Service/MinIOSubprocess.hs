{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.MinIOSubprocess
  ( MinIOSettings (..)
  , MinIOSubprocess (..)
  , defaultMinIOSettings
  , minioSettingsForEndpoint
  , minioDeleteObjectSubprocess
  , minioGetObjectSubprocess
  , minioListObjectsSubprocess
  , minioPutObjectSubprocess
  , minioSettingsForLocalEdge
  , parseListObjectsResponse
  , runMinIOSubprocess
  )
where

import Control.Exception (bracket)
import Control.Monad (void, when)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Reader (MonadReader, ReaderT (..), ask, runReaderT)
import Data.ByteString qualified as ByteString
import Data.Char (intToDigit, isAlphaNum)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Text.Encoding.Error qualified as TextErr
import System.Directory (doesFileExist, getTemporaryDirectory, removeFile)
import System.Exit (ExitCode (..))
import System.IO (hClose, openTempFile)

import JitML.Service.Capabilities
  ( BucketName (..)
  , ETag (..)
  , HasMinIO (..)
  , ObjectKey (..)
  , ObjectRef (..)
  )
import JitML.Service.Retry (ServiceError (..))
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (Subprocess, subprocess)

data MinIOSettings = MinIOSettings
  { minioCurlBinary :: FilePath
  , minioEndpoint :: Text
  , minioRegion :: Text
  , minioAccessKey :: Text
  , minioSecretKey :: Text
  , minioRequestPathPrefix :: Text
  }
  deriving stock (Eq, Show)

defaultMinIOSettings :: MinIOSettings
defaultMinIOSettings =
  minioSettingsForLocalEdge 9090

minioSettingsForEndpoint :: Text -> MinIOSettings
minioSettingsForEndpoint endpoint =
  MinIOSettings
    { minioCurlBinary = "curl"
    , minioEndpoint = endpoint
    , minioRegion = "us-east-1"
    , minioAccessKey = "minio"
    , minioSecretKey = "minioadmin"
    , minioRequestPathPrefix = ""
    }

minioSettingsForLocalEdge :: Int -> MinIOSettings
minioSettingsForLocalEdge edgePort =
  (minioSettingsForEndpoint ("http://127.0.0.1:" <> Text.pack (show edgePort)))
    { minioRequestPathPrefix = "/minio/s3"
    }

newtype MinIOSubprocess a = MinIOSubprocess
  { unMinIOSubprocess :: ReaderT MinIOSettings IO a
  }
  deriving newtype
    ( Functor
    , Applicative
    , Monad
    , MonadIO
    , MonadReader MinIOSettings
    )

runMinIOSubprocess :: MinIOSettings -> MinIOSubprocess a -> IO a
runMinIOSubprocess settings action =
  runReaderT (unMinIOSubprocess action) settings

minioPutObjectSubprocess
  :: MinIOSettings -> ObjectRef -> FilePath -> FilePath -> FilePath -> Maybe ETag -> Subprocess
minioPutObjectSubprocess settings ref payloadPath bodyPath etagPath expected =
  subprocess
    (minioCurlBinary settings)
    ( baseCurlArgs settings
        <> [ "--request"
           , "PUT"
           , "--upload-file"
           , Text.pack payloadPath
           , "--output"
           , Text.pack bodyPath
           , "--write-out"
           , "%{http_code}"
           , "--etag-save"
           , Text.pack etagPath
           , "--header"
           , "Content-Type: application/octet-stream"
           ]
        <> conditionalHeader expected
        <> requestTargetArgs settings (objectPath ref)
        <> [objectUrl settings ref]
    )

minioGetObjectSubprocess :: MinIOSettings -> ObjectRef -> FilePath -> Subprocess
minioGetObjectSubprocess settings ref bodyPath =
  subprocess
    (minioCurlBinary settings)
    ( baseCurlArgs settings
        <> [ "--request"
           , "GET"
           , "--output"
           , Text.pack bodyPath
           , "--write-out"
           , "%{http_code}"
           ]
        <> requestTargetArgs settings (objectPath ref)
        <> [objectUrl settings ref]
    )

minioDeleteObjectSubprocess :: MinIOSettings -> ObjectRef -> FilePath -> Subprocess
minioDeleteObjectSubprocess settings ref bodyPath =
  subprocess
    (minioCurlBinary settings)
    ( baseCurlArgs settings
        <> [ "--request"
           , "DELETE"
           , "--output"
           , Text.pack bodyPath
           , "--write-out"
           , "%{http_code}"
           ]
        <> requestTargetArgs settings (objectPath ref)
        <> [objectUrl settings ref]
    )

minioListObjectsSubprocess :: MinIOSettings -> BucketName -> Text -> FilePath -> Subprocess
minioListObjectsSubprocess settings bucket prefix bodyPath =
  let query = listObjectsQuery prefix
   in subprocess
        (minioCurlBinary settings)
        ( baseCurlArgs settings
            <> [ "--request"
               , "GET"
               , "--output"
               , Text.pack bodyPath
               , "--write-out"
               , "%{http_code}"
               ]
            <> requestTargetArgs settings (bucketPath bucket <> query)
            <> [bucketUrl settings bucket <> query]
        )

instance HasMinIO MinIOSubprocess where
  minioPutIfAbsent ref payload = do
    putResult <- putBlobIfAbsent ref payload
    pure (ref <$ putResult)

  minioReadObject ref = do
    readResult <- minioReadBytes ref
    pure (Text.Encoding.decodeUtf8With TextErr.lenientDecode <$> readResult)

  minioReadBytes ref = do
    settings <- ask
    withResponseFile $ \bodyPath -> do
      result <-
        invokeCurl
          "minioReadBytes"
          ["200"]
          MissingIsUnauthorized
          (minioGetObjectSubprocess settings ref bodyPath)
          bodyPath
      pure (fst <$> result)

  putBlobIfAbsent ref payload =
    putBlobBytesIfAbsent ref (Text.Encoding.encodeUtf8 payload)

  putBlobBytesIfAbsent ref payload = do
    settings <- ask
    withPayloadFile payload $ \payloadPath ->
      withResponseFile $ \bodyPath ->
        withResponseFile $ \etagPath -> do
          result <-
            invokeCurl
              "putBlobBytesIfAbsent"
              ["200", "201"]
              MissingIsUnauthorized
              (minioPutObjectSubprocess settings ref payloadPath bodyPath etagPath Nothing)
              bodyPath
          case result of
            Left err -> pure (Left err)
            Right _ -> readSavedEtag "putBlobBytesIfAbsent" etagPath

  casPointer ref expected payload = do
    settings <- ask
    withPayloadFile (Text.Encoding.encodeUtf8 payload) $ \payloadPath ->
      withResponseFile $ \bodyPath ->
        withResponseFile $ \etagPath -> do
          result <-
            invokeCurl
              "casPointer"
              ["200", "201"]
              MissingIsConflict
              (minioPutObjectSubprocess settings ref payloadPath bodyPath etagPath expected)
              bodyPath
          case result of
            Left err -> pure (Left err)
            Right _ -> readSavedEtag "casPointer" etagPath

  listObjects bucket prefix = do
    settings <- ask
    withResponseFile $ \bodyPath -> do
      result <-
        invokeCurl
          "listObjects"
          ["200"]
          MissingIsUnauthorized
          (minioListObjectsSubprocess settings bucket prefix bodyPath)
          bodyPath
      pure
        ( parseListObjectsResponse bucket . Text.Encoding.decodeUtf8With TextErr.lenientDecode . fst
            <$> result
        )

  deleteObject ref = do
    settings <- ask
    withResponseFile $ \bodyPath -> do
      result <-
        invokeCurl
          "deleteObject"
          ["200", "202", "204"]
          MissingIsUnauthorized
          (minioDeleteObjectSubprocess settings ref bodyPath)
          bodyPath
      pure (void result)

data MissingObjectMode
  = MissingIsUnauthorized
  | MissingIsConflict
  deriving stock (Eq, Show)

invokeCurl
  :: Text
  -> [Text]
  -> MissingObjectMode
  -> Subprocess
  -> FilePath
  -> MinIOSubprocess (Either ServiceError (ByteString.ByteString, Text))
invokeCurl tag successCodes missingMode command bodyPath = do
  (exitCode, stdoutText, stderrText) <- liftIO (runStreaming defaultSubprocessEnv command)
  body <- liftIO (ByteString.readFile bodyPath)
  let status = Text.strip stdoutText
  case exitCode of
    ExitFailure code ->
      pure (Left (SETransient (tag <> ": curl exit " <> Text.pack (show code) <> ": " <> stderrText)))
    ExitSuccess
      | status `elem` successCodes ->
          pure (Right (body, status))
      | status == "412" ->
          pure (Left (SEConflict (tag <> ": precondition failed")))
      | status == "404" && missingMode == MissingIsConflict ->
          pure (Left (SEConflict (tag <> ": object missing")))
      | status == "401" || status == "403" || status == "404" ->
          pure (Left (SEUnauthorized (tag <> ": HTTP " <> status)))
      | otherwise ->
          pure (Left (SETransient (tag <> ": HTTP " <> status <> ": " <> decodeBody body)))

readSavedEtag :: Text -> FilePath -> MinIOSubprocess (Either ServiceError ETag)
readSavedEtag tag etagPath = do
  exists <- liftIO (doesFileExist etagPath)
  if exists
    then do
      etag <-
        liftIO
          ( fmap
              (stripEtag . Text.strip)
              (Text.Encoding.decodeUtf8With TextErr.lenientDecode <$> ByteString.readFile etagPath)
          )
      if Text.null etag
        then pure (Left (SETransient (tag <> ": missing ETag")))
        else pure (Right (ETag etag))
    else pure (Left (SETransient (tag <> ": missing ETag file")))

parseListObjectsResponse :: BucketName -> Text -> [ObjectRef]
parseListObjectsResponse bucket =
  fmap (ObjectRef bucket . ObjectKey . xmlUnescape) . keyTexts
 where
  keyTexts xml =
    case Text.breakOn "<Key>" xml of
      (_, "") -> []
      (_, rest) ->
        let afterOpen = Text.drop (Text.length ("<Key>" :: Text)) rest
            (keyText, afterKey) = Text.breakOn "</Key>" afterOpen
         in keyText : keyTexts (Text.drop (Text.length ("</Key>" :: Text)) afterKey)

baseCurlArgs :: MinIOSettings -> [Text]
baseCurlArgs settings =
  [ "--silent"
  , "--show-error"
  , "--aws-sigv4"
  , "aws:amz:" <> minioRegion settings <> ":s3"
  , "--user"
  , minioAccessKey settings <> ":" <> minioSecretKey settings
  ]

conditionalHeader :: Maybe ETag -> [Text]
conditionalHeader Nothing =
  ["--header", "If-None-Match: *"]
conditionalHeader (Just (ETag etag)) =
  ["--header", "If-Match: " <> quoteEtag etag]

quoteEtag :: Text -> Text
quoteEtag etag
  | "\"" `Text.isPrefixOf` etag && "\"" `Text.isSuffixOf` etag = etag
  | otherwise = "\"" <> etag <> "\""

stripEtag :: Text -> Text
stripEtag =
  Text.dropAround (== '"')

objectUrl :: MinIOSettings -> ObjectRef -> Text
objectUrl settings ref =
  stripTrailingSlash (minioEndpoint settings) <> objectPath ref

bucketUrl :: MinIOSettings -> BucketName -> Text
bucketUrl settings bucket =
  stripTrailingSlash (minioEndpoint settings) <> bucketPath bucket

objectPath :: ObjectRef -> Text
objectPath ref =
  bucketPath (objectBucket ref) <> "/" <> percentEncodePath (unObjectKey (objectKey ref))

bucketPath :: BucketName -> Text
bucketPath bucket =
  "/" <> percentEncodePath (unBucketName bucket)

listObjectsQuery :: Text -> Text
listObjectsQuery prefix =
  "?list-type=2&prefix=" <> percentEncodeQuery prefix

requestTargetArgs :: MinIOSettings -> Text -> [Text]
requestTargetArgs settings upstreamPathAndQuery =
  case normalizeRequestPathPrefix (minioRequestPathPrefix settings) of
    "" -> []
    prefix -> ["--request-target", prefix <> upstreamPathAndQuery]

normalizeRequestPathPrefix :: Text -> Text
normalizeRequestPathPrefix prefix =
  stripTrailingSlash (ensureLeadingSlash prefix)

ensureLeadingSlash :: Text -> Text
ensureLeadingSlash value
  | Text.null value = ""
  | "/" `Text.isPrefixOf` value = value
  | otherwise = "/" <> value

stripTrailingSlash :: Text -> Text
stripTrailingSlash value
  | "/" `Text.isSuffixOf` value = stripTrailingSlash (Text.dropEnd 1 value)
  | otherwise = value

withPayloadFile :: ByteString.ByteString -> (FilePath -> MinIOSubprocess a) -> MinIOSubprocess a
withPayloadFile payload action =
  withTempFile "jitml-minio-payload" $ \path -> do
    liftIO (ByteString.writeFile path payload)
    action path

withResponseFile :: (FilePath -> MinIOSubprocess a) -> MinIOSubprocess a
withResponseFile =
  withTempFile "jitml-minio-response"

withTempFile :: String -> (FilePath -> MinIOSubprocess a) -> MinIOSubprocess a
withTempFile prefix action =
  MinIOSubprocess $
    ReaderT $ \settings -> do
      tempRoot <- getTemporaryDirectory
      bracket
        (openTempFile tempRoot prefix)
        (\(path, handle) -> hClose handle >> removeFileIfExists path)
        ( \(path, handle) -> do
            hClose handle
            runReaderT (unMinIOSubprocess (action path)) settings
        )

removeFileIfExists :: FilePath -> IO ()
removeFileIfExists path = do
  exists <- doesFileExist path
  when exists (removeFile path)

decodeBody :: ByteString.ByteString -> Text
decodeBody =
  Text.Encoding.decodeUtf8With TextErr.lenientDecode

percentEncodePath :: Text -> Text
percentEncodePath =
  Text.concatMap encodeChar
 where
  encodeChar '/' =
    "/"
  encodeChar char
    | isUnreserved char = Text.singleton char
    | otherwise = percentEncodeUtf8 char

percentEncodeQuery :: Text -> Text
percentEncodeQuery =
  Text.concatMap encodeChar
 where
  encodeChar char
    | isUnreserved char = Text.singleton char
    | otherwise = percentEncodeUtf8 char

isUnreserved :: Char -> Bool
isUnreserved char =
  isAlphaNum char || char `elem` ("-._~" :: String)

percentEncodeUtf8 :: Char -> Text
percentEncodeUtf8 =
  Text.concatMap (Text.pack . bytePercentHex)
    . Text.Encoding.decodeLatin1
    . Text.Encoding.encodeUtf8
    . Text.singleton

bytePercentHex :: Char -> String
bytePercentHex char =
  let byte = fromEnum char
   in [ '%'
      , intToDigitUpper (byte `div` 16)
      , intToDigitUpper (byte `mod` 16)
      ]

intToDigitUpper :: Int -> Char
intToDigitUpper digit =
  let rendered = intToDigit digit
   in if rendered >= 'a' && rendered <= 'f'
        then toEnum (fromEnum rendered - 32)
        else rendered

xmlUnescape :: Text -> Text
xmlUnescape =
  Text.replace "&quot;" "\""
    . Text.replace "&apos;" "'"
    . Text.replace "&gt;" ">"
    . Text.replace "&lt;" "<"
    . Text.replace "&amp;" "&"
