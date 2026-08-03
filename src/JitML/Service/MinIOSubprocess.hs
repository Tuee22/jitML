{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.MinIOSubprocess
  ( MinIOSettings (..)
  , MinIOSubprocess (..)
  , defaultMinIOSettings
  , minioSettingsForEndpoint
  , minioDeleteObjectSubprocess
  , minioGetObjectSubprocess
  , minioObjectETag
  , minioListObjectsSubprocess
  , minioListObjectsPageSubprocess
  , minioPutObjectSubprocess
  , minioSettingsForLocalEdge
  , collectListObjectsPages
  , parseListObjectsResponse
  , parseSavedEtag
  , runMinIOSubprocess
  )
where

import Control.Exception (bracket)
import Control.Monad (void, when)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Reader (MonadReader, ReaderT (..), ask, runReaderT)
import Data.ByteString qualified as ByteString
import Data.Char
  ( chr
  , digitToInt
  , intToDigit
  , isAscii
  , isAsciiLower
  , isAsciiUpper
  , isDigit
  , isHexDigit
  , ord
  )
import Data.Maybe (fromMaybe)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Text.Encoding.Error qualified as TextErr
import System.Directory (doesFileExist, getTemporaryDirectory, removeFile)
import System.IO (hClose, openTempFile)
import Text.Read (readMaybe)

import JitML.Service.Capabilities
  ( BucketName (..)
  , ETag (..)
  , HasMinIO (..)
  , ObjectKey (..)
  , ObjectRef (..)
  )
import JitML.Service.Retry (ServiceError (..))
import JitML.Sub.Outcome
  ( ProcessOutcome (..)
  , ProcessTranscript (..)
  , renderProcessFailure
  )
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
        <> retryCurlArgs
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

minioGetObjectWithEtagSubprocess :: MinIOSettings -> ObjectRef -> FilePath -> FilePath -> Subprocess
minioGetObjectWithEtagSubprocess settings ref bodyPath etagPath =
  subprocess
    (minioCurlBinary settings)
    ( baseCurlArgs settings
        <> retryCurlArgs
        <> [ "--request"
           , "GET"
           , "--output"
           , Text.pack bodyPath
           , "--write-out"
           , "%{http_code}"
           , "--etag-save"
           , Text.pack etagPath
           ]
        <> requestTargetArgs settings (objectPath ref)
        <> [objectUrl settings ref]
    )

minioDeleteObjectSubprocess :: MinIOSettings -> ObjectRef -> FilePath -> Subprocess
minioDeleteObjectSubprocess settings ref bodyPath =
  subprocess
    (minioCurlBinary settings)
    ( baseCurlArgs settings
        <> retryCurlArgs
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
minioListObjectsSubprocess settings bucket prefix =
  minioListObjectsPageSubprocess settings bucket prefix Nothing

minioListObjectsPageSubprocess
  :: MinIOSettings -> BucketName -> Text -> Maybe Text -> FilePath -> Subprocess
minioListObjectsPageSubprocess settings bucket prefix continuationToken bodyPath =
  let query = listObjectsQuery prefix continuationToken
   in subprocess
        (minioCurlBinary settings)
        ( baseCurlArgs settings
            <> retryCurlArgs
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

  minioReadBytesWithETag ref = do
    settings <- ask
    withResponseFile $ \bodyPath ->
      withResponseFile $ \etagPath -> do
        result <-
          invokeCurl
            "minioReadBytesWithETag"
            ["200"]
            MissingIsUnauthorized
            (minioGetObjectWithEtagSubprocess settings ref bodyPath etagPath)
            bodyPath
        case result of
          Left err -> pure (Left err)
          Right (body, _) -> do
            etag <- readSavedEtag "minioReadBytesWithETag" etagPath
            pure ((,) body <$> etag)

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
    collectListObjectsPages bucket prefix $ \continuationToken ->
      withResponseFile $ \bodyPath -> do
        result <-
          invokeCurl
            "listObjects"
            ["200"]
            MissingIsUnauthorized
            (minioListObjectsPageSubprocess settings bucket prefix continuationToken bodyPath)
            bodyPath
        pure $ case result of
          Left err -> Left err
          Right (body, _) ->
            case Text.Encoding.decodeUtf8' body of
              Left decodeError ->
                Left
                  ( SETransient
                      ( "listObjects: response is not valid UTF-8: "
                          <> Text.pack (show decodeError)
                      )
                  )
              Right response -> Right response

  deleteObject ref = do
    settings <- ask
    withResponseFile $ \bodyPath -> do
      result <-
        invokeCurl
          "deleteObject"
          ["200", "202", "204"]
          MissingIsSuccess
          (minioDeleteObjectSubprocess settings ref bodyPath)
          bodyPath
      pure (void result)

minioObjectETag :: ObjectRef -> MinIOSubprocess (Either ServiceError (Maybe ETag))
minioObjectETag ref = do
  settings <- ask
  withResponseFile $ \bodyPath ->
    withResponseFile $ \etagPath -> do
      result <-
        invokeCurl
          "minioObjectETag"
          ["200"]
          MissingIsConflict
          (minioGetObjectWithEtagSubprocess settings ref bodyPath etagPath)
          bodyPath
      case result of
        Left (SEConflict _) -> pure (Right Nothing)
        Left err -> pure (Left err)
        Right _ -> fmap Just <$> readSavedEtag "minioObjectETag" etagPath

data MissingObjectMode
  = MissingIsUnauthorized
  | MissingIsConflict
  | MissingIsSuccess
  deriving stock (Eq, Show)

invokeCurl
  :: Text
  -> [Text]
  -> MissingObjectMode
  -> Subprocess
  -> FilePath
  -> MinIOSubprocess (Either ServiceError (ByteString.ByteString, Text))
invokeCurl tag successCodes missingMode command bodyPath = do
  outcome <- liftIO (runStreaming defaultSubprocessEnv command)
  body <- liftIO (ByteString.readFile bodyPath)
  case outcome of
    ProcessFailed failure ->
      pure (Left (SETransient (tag <> ": " <> renderProcessFailure failure)))
    ProcessSucceeded transcript
      | status `elem` successCodes ->
          pure (Right (body, status))
      | status == "412" ->
          pure (Left (SEConflict (tag <> ": precondition failed")))
      | status == "404" && missingMode == MissingIsSuccess ->
          pure (Right (body, status))
      | status == "404" && missingMode == MissingIsConflict ->
          pure (Left (SEConflict (tag <> ": object missing")))
      | status == "401" || status == "403" || status == "404" ->
          pure (Left (SEUnauthorized (tag <> ": HTTP " <> status)))
      | otherwise ->
          pure (Left (SETransient (tag <> ": HTTP " <> status <> ": " <> decodeBody body)))
     where
      status = Text.strip (processTranscriptStdout transcript)

readSavedEtag :: Text -> FilePath -> MinIOSubprocess (Either ServiceError ETag)
readSavedEtag tag etagPath = do
  exists <- liftIO (doesFileExist etagPath)
  if exists
    then do
      saved <- liftIO (ByteString.readFile etagPath)
      pure $
        case parseSavedEtag saved of
          Left parseError -> Left (SETransient (tag <> ": invalid ETag: " <> parseError))
          Right etag -> Right etag
    else pure (Left (SETransient (tag <> ": missing ETag file")))

-- | Parse the exact format written by curl's @--etag-save@ option. Curl
-- terminates the strong, quoted entity-tag with one platform line ending.
-- Keep the opaque tag unquoted internally so conditional requests can render
-- one canonical pair of quotes without accepting header injection material.
parseSavedEtag :: ByteString.ByteString -> Either Text ETag
parseSavedEtag encoded = do
  decoded <-
    case Text.Encoding.decodeUtf8' encoded of
      Left decodeError -> Left ("not valid UTF-8: " <> Text.pack (show decodeError))
      Right value -> Right value
  let line =
        case Text.stripSuffix "\r\n" decoded of
          Just withoutLineEnding -> withoutLineEnding
          Nothing -> fromMaybe decoded (Text.stripSuffix "\n" decoded)
  opaque <-
    case Text.stripPrefix "\"" line >>= Text.stripSuffix "\"" of
      Nothing -> Left "expected one quoted strong entity-tag"
      Just value -> Right value
  if Text.null opaque
    then Left "entity-tag is empty"
    else
      if Text.all isStrongEtagCharacter opaque
        then Right (ETag opaque)
        else Left "entity-tag contains a quote, whitespace, control, or non-ASCII character"
 where
  isStrongEtagCharacter character =
    character == '\x21'
      || (character >= '\x23' && character <= '\x7e')

parseListObjectsResponse :: BucketName -> Text -> Either ServiceError [ObjectRef]
parseListObjectsResponse bucket xml =
  fmap
    (fmap (ObjectRef bucket . ObjectKey))
    (parseListBucketDocument xml >>= listBucketKeys)

data ListObjectsPage = ListObjectsPage
  { listObjectsPageObjects :: [ObjectRef]
  , listObjectsPageNextContinuationToken :: Maybe Text
  }

-- | Collect every page from one ListObjectsV2 snapshot. The fetch function is
-- parameterized so the pagination state machine can be tested without a live
-- object store. Every continuation response must echo the exact requested
-- token, and keys must be globally strictly ascending. A malformed page, a
-- continuation-token cycle, a duplicate key, or an ordering regression fails
-- the whole listing rather than returning an incomplete deletion candidate set
-- to a caller such as checkpoint GC.
collectListObjectsPages
  :: (Monad m)
  => BucketName
  -> Text
  -> (Maybe Text -> m (Either ServiceError Text))
  -> m (Either ServiceError [ObjectRef])
collectListObjectsPages bucket prefix fetchPage =
  go Set.empty Set.empty [] Nothing Nothing
 where
  go seenTokens seenKeys pagesRev lastListedKey continuationToken = do
    response <- fetchPage continuationToken
    case response of
      Left err -> pure (Left err)
      Right xml ->
        case parseListObjectsPage bucket prefix continuationToken xml of
          Left err -> pure (Left err)
          Right page ->
            case addUniqueObjectKeys seenKeys (listObjectsPageObjects page) of
              Left duplicateKey ->
                pure
                  ( invalidListResponse
                      ("duplicate object key across pages: " <> duplicateKey)
                  )
              Right nextSeenKeys ->
                case advanceStrictObjectOrder lastListedKey (listObjectsPageObjects page) of
                  Left orderingFailure ->
                    pure (invalidListResponse orderingFailure)
                  Right nextLastListedKey ->
                    let nextPagesRev = listObjectsPageObjects page : pagesRev
                     in case listObjectsPageNextContinuationToken page of
                          Nothing -> pure (Right (concat (reverse nextPagesRev)))
                          Just nextToken
                            | Set.member nextToken seenTokens ->
                                pure
                                  ( invalidListResponse
                                      ("repeated continuation token: " <> nextToken)
                                  )
                            | otherwise ->
                                go
                                  (Set.insert nextToken seenTokens)
                                  nextSeenKeys
                                  nextPagesRev
                                  nextLastListedKey
                                  (Just nextToken)

parseListObjectsPage
  :: BucketName
  -> Text
  -> Maybe Text
  -> Text
  -> Either ServiceError ListObjectsPage
parseListObjectsPage bucket expectedPrefix requestedContinuationToken xml = do
  root <- parseListBucketDocument xml
  body <- directChildElements root
  responseBucket <- requiredSingleElementText "Name" body
  whenEither
    (responseBucket /= unBucketName bucket)
    ( "response bucket mismatch: expected "
        <> unBucketName bucket
        <> ", got "
        <> responseBucket
    )
  responsePrefix <- requiredSingleElementText "Prefix" body
  whenEither
    (responsePrefix /= expectedPrefix)
    ( "response prefix mismatch: expected "
        <> expectedPrefix
        <> ", got "
        <> responsePrefix
    )
  continuationTokens <- elementTexts "ContinuationToken" body
  case (requestedContinuationToken, continuationTokens) of
    (Nothing, []) -> Right ()
    (Nothing, _) ->
      invalidListResponse
        "first page unexpectedly echoes a ContinuationToken"
    (Just expectedToken, [responseToken]) -> do
      whenEither
        (responseToken /= expectedToken)
        ( "response ContinuationToken mismatch: expected "
            <> expectedToken
            <> ", got "
            <> responseToken
        )
    (Just _, []) ->
      invalidListResponse
        "continuation page is missing the echoed ContinuationToken"
    (Just _, _) ->
      invalidListResponse
        "continuation page has multiple ContinuationToken elements"
  keys <- listBucketKeys root
  case filter (not . Text.isPrefixOf expectedPrefix) keys of
    keyOutsidePrefix : _ ->
      invalidListResponse
        ( "response key does not match requested prefix "
            <> expectedPrefix
            <> ": "
            <> keyOutsidePrefix
        )
    [] -> pure ()
  keyCountText <- requiredSingleElementText "KeyCount" body
  keyCount <- parseNonNegativeElement "KeyCount" keyCountText
  whenEither
    (keyCount /= length keys)
    ( "KeyCount mismatch: declared "
        <> Text.pack (show keyCount)
        <> ", decoded "
        <> Text.pack (show (length keys))
    )
  maxKeysText <- requiredSingleElementText "MaxKeys" body
  maxKeys <- parseNonNegativeElement "MaxKeys" maxKeysText
  whenEither
    (length keys > maxKeys)
    ( "page contains more keys than MaxKeys: "
        <> Text.pack (show (length keys))
        <> " > "
        <> Text.pack (show maxKeys)
    )
  truncatedText <- Text.strip <$> requiredSingleElementText "IsTruncated" body
  truncated <-
    case truncatedText of
      "true" -> Right True
      "false" -> Right False
      _ -> invalidListResponse ("invalid IsTruncated value: " <> truncatedText)
  tokens <- elementTexts "NextContinuationToken" body
  continuationToken <-
    case (truncated, tokens) of
      (True, [token]) -> do
        if Text.null token
          then invalidListResponse "truncated page has an empty NextContinuationToken"
          else Right (Just token)
      (True, []) ->
        invalidListResponse "truncated page is missing NextContinuationToken"
      (True, _) ->
        invalidListResponse "truncated page has multiple NextContinuationToken elements"
      (False, []) -> Right Nothing
      (False, _) ->
        invalidListResponse "non-truncated page unexpectedly has NextContinuationToken"
  pure
    ListObjectsPage
      { listObjectsPageObjects =
          fmap (ObjectRef bucket . ObjectKey) keys
      , listObjectsPageNextContinuationToken = continuationToken
      }

data XmlElement = XmlElement
  { xmlElementName :: Text
  , xmlElementAttributes :: [(Text, Text)]
  , xmlElementContent :: [XmlContent]
  }

data XmlContent
  = XmlText Text
  | XmlChild XmlElement

data XmlOpeningEnd
  = XmlOpeningNormal
  | XmlOpeningSelfClosing

parseListBucketDocument :: Text -> Either ServiceError XmlElement
parseListBucketDocument xml = do
  root <-
    case parseXmlDocument xml of
      Left reason -> invalidListResponse ("malformed XML document: " <> reason)
      Right parsed -> Right parsed
  whenEither
    (xmlElementName root /= "ListBucketResult")
    ("unexpected root element: " <> xmlElementName root)
  case xmlElementAttributes root of
    [("xmlns", namespace)]
      | namespace == "http://s3.amazonaws.com/doc/2006-03-01/" -> Right ()
      | otherwise ->
          invalidListResponse
            ("unexpected ListBucketResult namespace: " <> namespace)
    _ ->
      invalidListResponse
        "ListBucketResult must declare only the canonical default S3 namespace"
  children <- directChildElements root
  mapM_ validateListBucketChild children
  case filter (not . isListBucketChildName . xmlElementName) children of
    unexpected : _ ->
      invalidListResponse
        ("unexpected direct ListBucketResult element: " <> xmlElementName unexpected)
    [] -> Right root

isListBucketChildName :: Text -> Bool
isListBucketChildName name =
  name
    `elem` [ "Name"
           , "Prefix"
           , "ContinuationToken"
           , "NextContinuationToken"
           , "KeyCount"
           , "MaxKeys"
           , "IsTruncated"
           , "Contents"
           ]

validateListBucketChild :: XmlElement -> Either ServiceError ()
validateListBucketChild element = do
  requireNoAttributes element
  if xmlElementName element == "Contents"
    then validateContentsElement element
    else void (directElementText element)

validateContentsElement :: XmlElement -> Either ServiceError ()
validateContentsElement contents = do
  children <- directChildElements contents
  case filter (not . isContentsChildName . xmlElementName) children of
    unexpected : _ ->
      invalidListResponse
        ("unexpected direct Contents element: " <> xmlElementName unexpected)
    [] -> Right ()
  mapM_ validateContentsChild children
  void (requiredSingleElementText "Key" children)
  mapM_ (requireAtMostOneElement children) contentsSingletonElements
 where
  contentsSingletonElements =
    [ "LastModified"
    , "ETag"
    , "ChecksumType"
    , "Size"
    , "StorageClass"
    ]

isContentsChildName :: Text -> Bool
isContentsChildName name =
  name
    `elem` [ "Key"
           , "LastModified"
           , "ETag"
           , "ChecksumAlgorithm"
           , "ChecksumType"
           , "Size"
           , "StorageClass"
           ]

validateContentsChild :: XmlElement -> Either ServiceError ()
validateContentsChild child = do
  requireNoAttributes child
  void (directElementText child)

listBucketKeys :: XmlElement -> Either ServiceError [Text]
listBucketKeys root = do
  children <- directChildElements root
  let contents = filter ((== "Contents") . xmlElementName) children
  traverse contentsKey contents
 where
  contentsKey contents = do
    children <- directChildElements contents
    key <- requiredSingleElementText "Key" children
    whenEither (Text.null key) "Contents has an empty Key"
    pure key

directChildElements :: XmlElement -> Either ServiceError [XmlElement]
directChildElements parent =
  go [] (xmlElementContent parent)
 where
  go children [] = Right (reverse children)
  go children (XmlChild child : remaining) = go (child : children) remaining
  go children (XmlText value : remaining)
    | Text.all isXmlWhitespace value = go children remaining
    | otherwise =
        invalidListResponse
          ("non-whitespace text directly inside " <> xmlElementName parent)

directElementText :: XmlElement -> Either ServiceError Text
directElementText element =
  go [] (xmlElementContent element)
 where
  go chunks [] = Right (Text.concat (reverse chunks))
  go chunks (XmlText value : remaining) = go (value : chunks) remaining
  go _ (XmlChild child : _) =
    invalidListResponse
      ( "nested markup in "
          <> xmlElementName element
          <> ": "
          <> xmlElementName child
      )

requiredSingleElementText :: Text -> [XmlElement] -> Either ServiceError Text
requiredSingleElementText elementName elements = do
  element <- requiredSingleElement elementName elements
  directElementText element

requiredSingleElement :: Text -> [XmlElement] -> Either ServiceError XmlElement
requiredSingleElement elementName elements =
  case filter ((== elementName) . xmlElementName) elements of
    [element] -> Right element
    [] -> invalidListResponse ("missing " <> elementName <> " element")
    _ -> invalidListResponse ("multiple " <> elementName <> " elements")

elementTexts :: Text -> [XmlElement] -> Either ServiceError [Text]
elementTexts elementName elements =
  traverse
    directElementText
    (filter ((== elementName) . xmlElementName) elements)

requireAtMostOneElement :: [XmlElement] -> Text -> Either ServiceError ()
requireAtMostOneElement elements elementName =
  whenEither
    (length (filter ((== elementName) . xmlElementName) elements) > 1)
    ("multiple " <> elementName <> " elements")

requireNoAttributes :: XmlElement -> Either ServiceError ()
requireNoAttributes element =
  whenEither
    (not (null (xmlElementAttributes element)))
    ("attributes are not allowed on " <> xmlElementName element)

parseXmlDocument :: Text -> Either Text XmlElement
parseXmlDocument rawDocument = do
  let withoutBom = fromMaybe rawDocument (Text.stripPrefix "\xFEFF" rawDocument)
  afterDeclaration <- parseOptionalXmlDeclaration withoutBom
  let beforeRoot = Text.dropWhile isXmlWhitespace afterDeclaration
  (root, afterRoot) <- parseXmlElement 0 beforeRoot
  if Text.null (Text.dropWhile isXmlWhitespace afterRoot)
    then Right root
    else Left "content follows the document root"

parseOptionalXmlDeclaration :: Text -> Either Text Text
parseOptionalXmlDeclaration document =
  case Text.stripPrefix "<?xml" document of
    Nothing -> Right document
    Just remaining -> do
      case Text.uncons remaining of
        Just (character, _)
          | isXmlWhitespace character -> Right ()
        _ -> Left "XML declaration name is not followed by whitespace"
      (attributes, afterDeclaration) <- parseDeclarationAttributes [] remaining
      validateXmlDeclaration attributes
      Right afterDeclaration

parseDeclarationAttributes
  :: [(Text, Text)]
  -> Text
  -> Either Text ([(Text, Text)], Text)
parseDeclarationAttributes attributes remaining = do
  let afterWhitespace = Text.dropWhile isXmlWhitespace remaining
  case Text.stripPrefix "?>" afterWhitespace of
    Just afterDeclaration -> Right (reverse attributes, afterDeclaration)
    Nothing -> do
      whenText
        (afterWhitespace == remaining)
        "expected whitespace before XML declaration attribute"
      (attribute, afterAttribute) <- parseXmlAttribute False afterWhitespace
      whenText
        (any ((== fst attribute) . fst) attributes)
        ("duplicate XML declaration attribute: " <> fst attribute)
      parseDeclarationAttributes (attribute : attributes) afterAttribute

validateXmlDeclaration :: [(Text, Text)] -> Either Text ()
validateXmlDeclaration attributes = do
  let attributeNames = fmap fst attributes
  whenText
    ( attributeNames
        `notElem` [ ["version"]
                  , ["version", "encoding"]
                  , ["version", "standalone"]
                  , ["version", "encoding", "standalone"]
                  ]
    )
    "XML declaration attributes are missing, out of order, or unexpected"
  whenText
    (lookup "version" attributes /= Just "1.0")
    "XML declaration must specify version 1.0"
  case lookup "encoding" attributes of
    Nothing -> Right ()
    Just encoding ->
      whenText
        (Text.toUpper encoding /= "UTF-8")
        "XML declaration encoding must be UTF-8"
  case lookup "standalone" attributes of
    Nothing -> Right ()
    Just standalone ->
      whenText
        (standalone /= "yes" && standalone /= "no")
        "XML declaration standalone value must be yes or no"
  case filter ((`notElem` ["version", "encoding", "standalone"]) . fst) attributes of
    [] -> Right ()
    (name, _) : _ -> Left ("unexpected XML declaration attribute: " <> name)

parseXmlElement :: Int -> Text -> Either Text (XmlElement, Text)
parseXmlElement depth document = do
  whenText (depth > 32) "XML nesting depth exceeds 32 elements"
  afterOpen <-
    maybe (Left "expected element opening tag") Right (Text.stripPrefix "<" document)
  whenText
    (any (`Text.isPrefixOf` afterOpen) ["/", "!", "?"])
    "expected an element name"
  (elementName, afterName) <- parseXmlName afterOpen
  (attributes, openingEnd, afterOpeningTag) <- parseElementAttributes [] afterName
  case openingEnd of
    XmlOpeningSelfClosing ->
      Right
        ( XmlElement
            { xmlElementName = elementName
            , xmlElementAttributes = attributes
            , xmlElementContent = []
            }
        , afterOpeningTag
        )
    XmlOpeningNormal -> do
      (content, afterClosingTag) <- parseXmlContent depth elementName [] afterOpeningTag
      Right
        ( XmlElement
            { xmlElementName = elementName
            , xmlElementAttributes = attributes
            , xmlElementContent = content
            }
        , afterClosingTag
        )

parseElementAttributes
  :: [(Text, Text)]
  -> Text
  -> Either Text ([(Text, Text)], XmlOpeningEnd, Text)
parseElementAttributes attributes remaining =
  case Text.stripPrefix ">" remaining of
    Just afterOpeningTag -> Right (reverse attributes, XmlOpeningNormal, afterOpeningTag)
    Nothing ->
      case Text.stripPrefix "/>" remaining of
        Just afterOpeningTag ->
          Right (reverse attributes, XmlOpeningSelfClosing, afterOpeningTag)
        Nothing -> do
          case Text.uncons remaining of
            Just (character, _)
              | isXmlWhitespace character -> Right ()
            _ -> Left "expected whitespace or the end of an opening tag"
          let afterWhitespace = Text.dropWhile isXmlWhitespace remaining
          case Text.stripPrefix ">" afterWhitespace of
            Just afterOpeningTag ->
              Right (reverse attributes, XmlOpeningNormal, afterOpeningTag)
            Nothing ->
              case Text.stripPrefix "/>" afterWhitespace of
                Just afterOpeningTag ->
                  Right (reverse attributes, XmlOpeningSelfClosing, afterOpeningTag)
                Nothing -> do
                  (attribute, afterAttribute) <- parseXmlAttribute True afterWhitespace
                  whenText
                    (any ((== fst attribute) . fst) attributes)
                    ("duplicate attribute: " <> fst attribute)
                  parseElementAttributes (attribute : attributes) afterAttribute

parseXmlAttribute :: Bool -> Text -> Either Text ((Text, Text), Text)
parseXmlAttribute allowEntityReferences document = do
  (attributeName, afterName) <- parseXmlName document
  let beforeEquals = Text.dropWhile isXmlWhitespace afterName
  afterEquals <-
    maybe
      (Left ("missing '=' after attribute " <> attributeName))
      Right
      (Text.stripPrefix "=" beforeEquals)
  let beforeValue = Text.dropWhile isXmlWhitespace afterEquals
  (quote, afterQuote) <-
    case Text.uncons beforeValue of
      Just ('\'', remaining) -> Right ('\'', remaining)
      Just ('"', remaining) -> Right ('"', remaining)
      _ -> Left ("attribute " <> attributeName <> " must have a quoted value")
  let (encodedValue, fromValueEnd) =
        Text.span (\character -> character /= quote && character /= '<') afterQuote
  case Text.uncons fromValueEnd of
    Just (character, afterValue)
      | character == quote -> do
          whenText
            (not allowEntityReferences && Text.any (== '&') encodedValue)
            ("entity references are not allowed in XML declaration attribute " <> attributeName)
          value <- decodeXmlCharacters ("attribute " <> attributeName) encodedValue
          Right ((attributeName, value), afterValue)
      | character == '<' -> Left ("attribute " <> attributeName <> " contains '<'")
    _ -> Left ("unclosed value for attribute " <> attributeName)

parseXmlContent
  :: Int
  -> Text
  -> [XmlContent]
  -> Text
  -> Either Text ([XmlContent], Text)
parseXmlContent depth expectedName content remaining
  | Text.null remaining = Left ("unclosed " <> expectedName <> " element")
  | Just afterClosingOpen <- Text.stripPrefix "</" remaining = do
      (closingName, afterClosingName) <- parseXmlName afterClosingOpen
      afterClosingTag <-
        maybe
          (Left ("malformed closing tag for " <> closingName))
          Right
          (Text.stripPrefix ">" (Text.dropWhile isXmlWhitespace afterClosingName))
      whenText
        (closingName /= expectedName)
        ( "closing element "
            <> closingName
            <> " does not match opening element "
            <> expectedName
        )
      Right (reverse content, afterClosingTag)
  | "<!--" `Text.isPrefixOf` remaining =
      Left "XML comments are not allowed"
  | "<![CDATA[" `Text.isPrefixOf` remaining =
      Left "CDATA sections are not allowed"
  | "<!DOCTYPE" `Text.isPrefixOf` remaining =
      Left "DOCTYPE declarations are not allowed"
  | "<?" `Text.isPrefixOf` remaining =
      Left "processing instructions are not allowed"
  | "<!" `Text.isPrefixOf` remaining =
      Left "XML declarations inside element content are not allowed"
  | "<" `Text.isPrefixOf` remaining = do
      (child, afterChild) <- parseXmlElement (depth + 1) remaining
      parseXmlContent depth expectedName (XmlChild child : content) afterChild
  | otherwise = do
      let (encodedText, afterText) = Text.span (/= '<') remaining
      decodedText <- decodeXmlCharacters ("text in " <> expectedName) encodedText
      parseXmlContent depth expectedName (XmlText decodedText : content) afterText

parseXmlName :: Text -> Either Text (Text, Text)
parseXmlName document =
  case Text.uncons document of
    Just (firstCharacter, remaining)
      | isXmlNameStart firstCharacter ->
          let (suffix, afterName) = Text.span isXmlNameCharacter remaining
           in Right (Text.cons firstCharacter suffix, afterName)
    _ -> Left "invalid or missing XML name"

isXmlNameStart :: Char -> Bool
isXmlNameStart character =
  isAsciiLetter character || character == '_'

isXmlNameCharacter :: Char -> Bool
isXmlNameCharacter character =
  isXmlNameStart character
    || isAsciiDigit character
    || character `elem` ("-._:" :: String)

isXmlWhitespace :: Char -> Bool
isXmlWhitespace character =
  character `elem` ['\x20', '\x9', '\xA', '\xD']

decodeXmlCharacters :: Text -> Text -> Either Text Text
decodeXmlCharacters context encoded = do
  whenText ("]]>" `Text.isInfixOf` encoded) (context <> " contains forbidden ']]>'")
  decoded <-
    case xmlUnescapeStrict encoded of
      Left reason -> Left ("invalid XML entity in " <> context <> ": " <> reason)
      Right value -> Right value
  whenText
    (not (Text.all (validXmlCodePoint . toInteger . ord) decoded))
    (context <> " contains an invalid XML character")
  Right decoded

whenText :: Bool -> Text -> Either Text ()
whenText condition message
  | condition = Left message
  | otherwise = Right ()

parseNonNegativeElement :: Text -> Text -> Either ServiceError Int
parseNonNegativeElement elementName rawValue =
  let value = Text.strip rawValue
   in if Text.null value || not (Text.all isAsciiDigit value)
        then invalidListResponse ("invalid " <> elementName <> " value: " <> value)
        else case readMaybe (Text.unpack value) of
          Just parsed -> Right parsed
          Nothing -> invalidListResponse ("out-of-range " <> elementName <> " value: " <> value)

addUniqueObjectKeys :: Set.Set Text -> [ObjectRef] -> Either Text (Set.Set Text)
addUniqueObjectKeys =
  go
 where
  go seen [] = Right seen
  go seen (ref : remaining) =
    let key = unObjectKey (objectKey ref)
     in if Set.member key seen
          then Left key
          else go (Set.insert key seen) remaining

advanceStrictObjectOrder :: Maybe Text -> [ObjectRef] -> Either Text (Maybe Text)
advanceStrictObjectOrder =
  go
 where
  go previous [] = Right previous
  go Nothing (ref : remaining) =
    let key = unObjectKey (objectKey ref)
     in go (Just key) remaining
  go (Just previous) (ref : remaining) =
    let key = unObjectKey (objectKey ref)
     in if key > previous
          then go (Just key) remaining
          else
            Left
              ( "object keys are not in strict ascending order: "
                  <> key
                  <> " follows "
                  <> previous
              )

whenEither :: Bool -> Text -> Either ServiceError ()
whenEither condition message
  | condition = invalidListResponse message
  | otherwise = Right ()

invalidListResponse :: Text -> Either ServiceError a
invalidListResponse message =
  Left (SETransient ("listObjects: invalid ListObjectsV2 response: " <> message))

baseCurlArgs :: MinIOSettings -> [Text]
baseCurlArgs settings =
  [ "--silent"
  , "--show-error"
  , "--path-as-is"
  , "--connect-timeout"
  , "10"
  , "--max-time"
  , "300"
  , "--aws-sigv4"
  , "aws:amz:" <> minioRegion settings <> ":s3"
  , "--user"
  , minioAccessKey settings <> ":" <> minioSecretKey settings
  ]

retryCurlArgs :: [Text]
retryCurlArgs =
  [ "--retry"
  , "5"
  , "--retry-delay"
  , "2"
  , "--retry-max-time"
  , "120"
  , "--retry-connrefused"
  , "--retry-all-errors"
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

listObjectsQuery :: Text -> Maybe Text -> Text
listObjectsQuery prefix continuationToken =
  "?list-type=2&prefix="
    <> percentEncodeQuery prefix
    <> maybe
      ""
      (("&continuation-token=" <>) . percentEncodeQuery)
      continuationToken

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
  isAsciiLetter char || isAsciiDigit char || char `elem` ("-._~" :: String)

isAsciiLetter :: Char -> Bool
isAsciiLetter character =
  isAsciiUpper character || isAsciiLower character

isAsciiDigit :: Char -> Bool
isAsciiDigit character =
  isAscii character && isDigit character

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

xmlUnescapeStrict :: Text -> Either Text Text
xmlUnescapeStrict =
  go
 where
  go remaining =
    let (literal, fromAmpersand) = Text.span (/= '&') remaining
     in if Text.null fromAmpersand
          then Right literal
          else do
            let afterAmpersand = Text.drop 1 fromAmpersand
                (entityName, fromSemicolon) = Text.span (/= ';') afterAmpersand
            if Text.null fromSemicolon
              then Left "unterminated entity"
              else do
                decodedEntity <- decodeXmlEntity entityName
                decodedRest <- go (Text.drop 1 fromSemicolon)
                Right (literal <> Text.singleton decodedEntity <> decodedRest)

decodeXmlEntity :: Text -> Either Text Char
decodeXmlEntity entityName =
  case entityName of
    "amp" -> Right '&'
    "lt" -> Right '<'
    "gt" -> Right '>'
    "apos" -> Right '\''
    "quot" -> Right '"'
    _
      | Just hexadecimal <- Text.stripPrefix "#x" entityName ->
          decodeNumericXmlEntity 16 isHexDigit hexadecimal
      | Just decimal <- Text.stripPrefix "#" entityName ->
          decodeNumericXmlEntity 10 isAsciiDigit decimal
      | otherwise -> Left ("unknown entity &" <> entityName <> ";")

decodeNumericXmlEntity :: Int -> (Char -> Bool) -> Text -> Either Text Char
decodeNumericXmlEntity base validDigit digits
  | Text.null digits || not (Text.all validDigit digits) =
      Left "invalid numeric entity"
  | otherwise =
      let codePoint =
            Text.foldl'
              (\total digit -> total * toInteger base + toInteger (digitToInt digit))
              0
              digits
       in if validXmlCodePoint codePoint
            then Right (chr (fromInteger codePoint))
            else Left "numeric entity is not a valid XML character"

validXmlCodePoint :: Integer -> Bool
validXmlCodePoint codePoint =
  codePoint == 0x9
    || codePoint == 0xA
    || codePoint == 0xD
    || (codePoint >= 0x20 && codePoint <= 0xD7FF)
    || (codePoint >= 0xE000 && codePoint <= 0xFFFD)
    || (codePoint >= 0x10000 && codePoint <= 0x10FFFF)
