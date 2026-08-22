{-# LANGUAGE OverloadedStrings #-}

-- | The Docker Registry v2 implementation of 'HasImageRegistry'.
--
-- Every operation here is expressible against any registry that serves the v2
-- API. Push, pull, tag and manifest inspection are plain @docker@ invocations
-- and were always registry-agnostic; catalogue listing, existence and promotion
-- are the three that previously used Harbor's @\/api\/v2.0@ projects and
-- artifacts endpoints and are now expressed as @\/v2@ calls.
--
-- There is no login step. The local stack runs the registry without
-- authentication and is reached over loopback, which Docker already treats as an
-- insecure registry, so there is no credential to present and no token endpoint
-- to challenge against.
module JitML.Service.RegistrySubprocess
  ( RegistrySettings (..)
  , RegistrySubprocess (..)
  , defaultRegistrySettings
  , registryCatalogSubprocess
  , registryImageDigestSubprocess
  , registryManifestFetchSubprocess
  , registryManifestPutSubprocess
  , registryManifestStatusSubprocess
  , registryManifestInspectSubprocess
  , registrySettingsForLocalEdge
  , runRegistrySubprocess
  )
where

import Control.Monad (void)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Reader (MonadReader, ReaderT, ask, runReaderT)
import Data.Aeson (FromJSON (..), eitherDecode, withObject, (.:), (.:?))
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import System.Directory (createDirectoryIfMissing)

import JitML.Service.Capabilities
  ( ETag (..)
  , HasImageRegistry (..)
  , ImageRef (..)
  )
import JitML.Service.Retry (ServiceError (..))
import JitML.Sub.Outcome
  ( ProcessFailure
  , ProcessOutcome (..)
  , ProcessTranscript (..)
  , processFailureStderr
  , renderProcessFailure
  )
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (Subprocess, subprocess)

data RegistrySettings = RegistrySettings
  { registryDockerBinary :: FilePath
  , registryDockerHost :: Maybe Text
  , registryDockerConfigDir :: FilePath
  , registryCurlBinary :: FilePath
  , registryEndpoint :: Text
  , registryBaseUrl :: Text
  }
  deriving stock (Eq, Show)

defaultRegistrySettings :: RegistrySettings
defaultRegistrySettings =
  registrySettingsForLocalEdge 9090

registrySettingsForLocalEdge :: Int -> RegistrySettings
registrySettingsForLocalEdge edgePort =
  RegistrySettings
    { registryDockerBinary = "docker"
    , registryDockerHost = Nothing
    , -- Keep docker's config isolated from the invoking user's `~/.docker`
      -- even though nothing is written to it any more: the daemon must not
      -- read or mutate developer credentials.
      registryDockerConfigDir = "./.build/docker/registry"
    , registryCurlBinary = "curl"
    , registryEndpoint = "127.0.0.1:" <> portText
    , registryBaseUrl = "http://127.0.0.1:" <> portText
    }
 where
  portText = Text.pack (show edgePort)

newtype RegistrySubprocess a = RegistrySubprocess
  { unRegistrySubprocess :: ReaderT RegistrySettings IO a
  }
  deriving newtype
    ( Functor
    , Applicative
    , Monad
    , MonadIO
    , MonadReader RegistrySettings
    )

runRegistrySubprocess :: RegistrySettings -> RegistrySubprocess a -> IO a
runRegistrySubprocess settings action =
  runReaderT (unRegistrySubprocess action) settings

registryManifestInspectSubprocess :: RegistrySettings -> ImageRef -> Subprocess
registryManifestInspectSubprocess settings (ImageRef imageRef) =
  subprocess
    (registryDockerBinary settings)
    (dockerArgs settings ["manifest", "inspect", imageRef])

registryImageDigestSubprocess :: RegistrySettings -> ImageRef -> Subprocess
registryImageDigestSubprocess settings (ImageRef imageRef) =
  subprocess
    (registryDockerBinary settings)
    (dockerArgs settings ["image", "inspect", "--format", "{{.Id}}", imageRef])

-- | @GET \/v2\/_catalog@ — the whole catalogue, filtered by caller.
--
-- Registry v2 has no project scoping, so repositories are plain path prefixes
-- and the caller narrows the result itself.
registryCatalogSubprocess :: RegistrySettings -> Subprocess
registryCatalogSubprocess settings =
  subprocess
    (registryCurlBinary settings)
    [ "--fail"
    , "--silent"
    , "--show-error"
    , registryBaseUrl settings <> "/v2/_catalog?n=100"
    ]

-- | @HEAD \/v2\/{repository}\/manifests\/{reference}@ — existence as a status code.
registryManifestStatusSubprocess :: RegistrySettings -> Text -> Text -> Subprocess
registryManifestStatusSubprocess settings repository reference =
  subprocess
    (registryCurlBinary settings)
    ( [ "--silent"
      , "--show-error"
      , "--head"
      , "--output"
      , "/dev/null"
      , "--write-out"
      , "%{http_code}"
      ]
        <> manifestAcceptArgs
        <> [manifestUrl settings repository reference]
    )

-- | @GET \/v2\/{repository}\/manifests\/{reference}@ — the manifest document.
registryManifestFetchSubprocess :: RegistrySettings -> Text -> Text -> Subprocess
registryManifestFetchSubprocess settings repository reference =
  subprocess
    (registryCurlBinary settings)
    ( ["--fail", "--silent", "--show-error"]
        <> manifestAcceptArgs
        <> [manifestUrl settings repository reference]
    )

-- | @PUT \/v2\/{repository}\/manifests\/{tag}@ — the whole of \"create a tag\".
--
-- Registry v2 has no tag API. A tag is just a name a manifest is stored under,
-- so re-@PUT@ting the source manifest under the target name adds the tag without
-- moving a single blob. The @Content-Type@ must be the manifest's own declared
-- @mediaType@ or the registry rejects it.
registryManifestPutSubprocess :: RegistrySettings -> Text -> Text -> Text -> Text -> Subprocess
registryManifestPutSubprocess settings repository tag mediaType manifest =
  subprocess
    (registryCurlBinary settings)
    [ "--silent"
    , "--show-error"
    , "--output"
    , "/dev/null"
    , "--write-out"
    , "%{http_code}"
    , "--request"
    , "PUT"
    , "--header"
    , "Content-Type: " <> mediaType
    , "--data-binary"
    , manifest
    , manifestUrl settings repository tag
    ]

manifestUrl :: RegistrySettings -> Text -> Text -> Text
manifestUrl settings repository reference =
  registryBaseUrl settings <> "/v2/" <> repository <> "/manifests/" <> reference

-- | Both schema-2 media types, so a v2 or an OCI manifest is returned verbatim
-- rather than being converted to the legacy schema 1.
manifestAcceptArgs :: [Text]
manifestAcceptArgs =
  concat
    [ ["--header", "Accept: " <> mediaType]
    | mediaType <-
        [ "application/vnd.docker.distribution.manifest.v2+json"
        , "application/vnd.docker.distribution.manifest.list.v2+json"
        , "application/vnd.oci.image.manifest.v1+json"
        , "application/vnd.oci.image.index.v1+json"
        ]
    ]

newtype RegistryCatalog = RegistryCatalog
  { catalogRepositories :: [Text]
  }
  deriving stock (Eq, Show)

instance FromJSON RegistryCatalog where
  parseJSON =
    withObject "RegistryCatalog" $ \objectValue ->
      RegistryCatalog . fromMaybe [] <$> objectValue .:? "repositories"

newtype ManifestMediaType = ManifestMediaType
  { manifestMediaType :: Text
  }
  deriving stock (Eq, Show)

instance FromJSON ManifestMediaType where
  parseJSON =
    withObject "ManifestMediaType" $ \objectValue ->
      ManifestMediaType <$> objectValue .: "mediaType"

instance HasImageRegistry RegistrySubprocess where
  registryImageExists imageRef = do
    settings <- ask
    case parseImageRef settings imageRef of
      Left err -> pure (Left err)
      Right (repository, reference) -> do
        statusResult <-
          invokeText
            "registryImageExists"
            (registryManifestStatusSubprocess settings repository reference)
        case Text.strip <$> statusResult of
          Left err -> pure (Left err)
          Right "200" -> pure (Right True)
          Right "404" -> pure (Right False)
          Right "401" -> pure (Left (SEUnauthorized "registryImageExists: unauthorized"))
          Right status ->
            pure (Left (SETransient ("registryImageExists: unexpected HTTP " <> status)))

  registryPromoteImage source target = do
    settings <- ask
    case sameRepositoryPromotion settings source target of
      Just (repository, sourceTag, targetTag) -> do
        manifestResult <-
          invokeText
            "registryPromoteImage.manifestFetch"
            (registryManifestFetchSubprocess settings repository sourceTag)
        case manifestResult of
          Left err -> pure (Left err)
          Right manifest ->
            case decodeMediaType manifest of
              Left err -> pure (Left err)
              Right mediaType -> do
                putResult <-
                  invokeText
                    "registryPromoteImage.manifestPut"
                    ( registryManifestPutSubprocess
                        settings
                        repository
                        targetTag
                        mediaType
                        manifest
                    )
                pure (promoteStatusToResult target (Text.strip <$> putResult))
      Nothing -> do
        -- Across repositories the manifest's blobs may not be mounted, so the
        -- honest move is a re-push rather than a manifest copy.
        tagResult <-
          invokeUnit
            "registryPromoteImage.tag"
            ( subprocess
                (registryDockerBinary settings)
                (dockerArgs settings ["tag", unImageRef source, unImageRef target])
            )
        case tagResult of
          Left err -> pure (Left err)
          Right () -> do
            pushResult <- registryPushImage target
            pure (target <$ pushResult)

  registryPushImage imageRef = do
    settings <- ask
    liftIO (createDirectoryIfMissing True (registryDockerConfigDir settings))
    pushResult <-
      invokeText
        "registryPushImage"
        ( subprocess
            (registryDockerBinary settings)
            (dockerArgs settings ["push", unImageRef imageRef])
        )
    case pushResult of
      Left err -> pure (Left err)
      Right stdoutText -> imageDigest imageRef stdoutText

  registryPullImage imageRef = do
    settings <- ask
    liftIO (createDirectoryIfMissing True (registryDockerConfigDir settings))
    pullResult <-
      invokeText
        "registryPullImage"
        ( subprocess
            (registryDockerBinary settings)
            (dockerArgs settings ["pull", unImageRef imageRef])
        )
    case pullResult of
      Left err -> pure (Left err)
      Right stdoutText -> imageDigest imageRef stdoutText

  registryListImages repositoryPrefix = do
    settings <- ask
    listResult <- invokeText "registryListImages" (registryCatalogSubprocess settings)
    case listResult of
      Left err -> pure (Left err)
      Right stdoutText ->
        case eitherDecode (LazyByteString.fromStrict (Text.Encoding.encodeUtf8 stdoutText)) of
          Left parseError ->
            pure
              ( Left
                  ( SETransient
                      ("registryListImages: JSON parse failed: " <> Text.pack parseError)
                  )
              )
          Right catalog ->
            pure
              ( Right
                  [ ImageRef (registryEndpoint settings <> "/" <> repository)
                  | repository <- catalogRepositories catalog
                  , (repositoryPrefix <> "/") `Text.isPrefixOf` repository
                  ]
              )

decodeMediaType :: Text -> Either ServiceError Text
decodeMediaType manifest =
  case eitherDecode (LazyByteString.fromStrict (Text.Encoding.encodeUtf8 manifest)) of
    Left parseError ->
      Left
        ( SETransient
            ("registryPromoteImage: manifest parse failed: " <> Text.pack parseError)
        )
    Right value -> Right (manifestMediaType value)

dockerArgs :: RegistrySettings -> [Text] -> [Text]
dockerArgs settings args =
  maybe [] (\dockerHost -> ["--host", dockerHost]) (registryDockerHost settings)
    <> ["--config", Text.pack (registryDockerConfigDir settings)]
    <> args

-- | Split a registry-qualified image reference into repository and tag.
--
-- Registry v2 repositories are path prefixes, so everything between the endpoint
-- and the tag is the repository name — there is no separate project segment to
-- pull out.
parseImageRef :: RegistrySettings -> ImageRef -> Either ServiceError (Text, Text)
parseImageRef settings (ImageRef imageRef) = do
  imagePath <-
    maybe
      (Left (SETransient ("image is outside registry " <> registryEndpoint settings)))
      Right
      (Text.stripPrefix (registryEndpoint settings <> "/") imageRef)
  (repository, tag) <-
    maybe
      (Left (SETransient ("image ref lacks tag: " <> imageRef)))
      Right
      (splitTag imagePath)
  if Text.null repository
    then Left (SETransient ("image ref lacks repository: " <> imageRef))
    else Right (repository, tag)

splitTag :: Text -> Maybe (Text, Text)
splitTag imagePath =
  case Text.breakOnEnd ":" imagePath of
    ("", _) -> Nothing
    (pathWithColon, tag)
      | Text.null tag -> Nothing
      | otherwise -> Just (Text.dropEnd 1 pathWithColon, tag)

sameRepositoryPromotion
  :: RegistrySettings -> ImageRef -> ImageRef -> Maybe (Text, Text, Text)
sameRepositoryPromotion settings source target =
  case (parseImageRef settings source, parseImageRef settings target) of
    (Right (sourceRepository, sourceTag), Right (targetRepository, targetTag))
      | sourceRepository == targetRepository ->
          Just (sourceRepository, sourceTag, targetTag)
    _ -> Nothing

promoteStatusToResult :: ImageRef -> Either ServiceError Text -> Either ServiceError ImageRef
promoteStatusToResult target result =
  case result of
    Left err -> Left err
    Right status
      | status == "200" || status == "201" -> Right target
      | status == "401" || status == "403" ->
          Left (SEUnauthorized ("registryPromoteImage: HTTP " <> status))
      | status == "404" ->
          Left (SETransient "registryPromoteImage: source manifest missing")
      | otherwise ->
          Left (SETransient ("registryPromoteImage: HTTP " <> status))

imageDigest :: ImageRef -> Text -> RegistrySubprocess (Either ServiceError ETag)
imageDigest imageRef stdoutText =
  case digestFromDockerOutput stdoutText of
    Just digest -> pure (Right (ETag digest))
    Nothing -> do
      settings <- ask
      digestResult <-
        invokeText "registryImageDigest" (registryImageDigestSubprocess settings imageRef)
      case digestResult of
        Left err -> pure (Left err)
        Right digestText ->
          pure (Right (ETag (Text.strip digestText)))

digestFromDockerOutput :: Text -> Maybe Text
digestFromDockerOutput =
  go . Text.words
 where
  go [] = Nothing
  go ("digest:" : digest : _) = Just (Text.strip digest)
  go ("Digest:" : digest : _) = Just (Text.strip digest)
  go (_ : rest) = go rest

invokeUnit :: Text -> Subprocess -> RegistrySubprocess (Either ServiceError ())
invokeUnit tag command = do
  result <- invokeText tag command
  pure (void result)

invokeText :: Text -> Subprocess -> RegistrySubprocess (Either ServiceError Text)
invokeText tag command = do
  outcome <- liftIO (runStreaming defaultSubprocessEnv command)
  case outcome of
    ProcessSucceeded transcript -> pure (Right (processTranscriptStdout transcript))
    ProcessFailed failure -> pure (Left (classifyRegistryFailure tag failure))

classifyRegistryFailure :: Text -> ProcessFailure -> ServiceError
classifyRegistryFailure tag failure
  | "unauthorized" `Text.isInfixOf` lowerStderr || "401" `Text.isInfixOf` stderrText =
      SEUnauthorized rendered
  | otherwise = SETransient rendered
 where
  stderrText = processFailureStderr failure
  lowerStderr = Text.toLower stderrText
  rendered = tag <> ": " <> renderProcessFailure failure
