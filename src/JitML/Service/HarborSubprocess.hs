{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.HarborSubprocess
  ( HarborSettings (..)
  , HarborSubprocess (..)
  , defaultHarborSettings
  , harborArtifactStatusSubprocess
  , harborImageDigestSubprocess
  , harborListRepositoriesSubprocess
  , harborLoginSubprocess
  , harborManifestInspectSubprocess
  , harborSettingsForLocalEdge
  , runHarborSubprocess
  )
where

import Control.Monad (void)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Reader (MonadReader, ReaderT, ask, runReaderT)
import Data.Aeson (FromJSON (..), eitherDecode, withObject, (.:))
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import System.Directory (createDirectoryIfMissing)
import System.Exit (ExitCode (..))

import JitML.Service.Capabilities
  ( ETag (..)
  , HasHarbor (..)
  , ImageRef (..)
  )
import JitML.Service.Retry (ServiceError (..))
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (Subprocess, subprocess, subprocessWithStdin)

data HarborSettings = HarborSettings
  { harborDockerBinary :: FilePath
  , harborDockerHost :: Maybe Text
  , harborDockerConfigDir :: FilePath
  , harborCurlBinary :: FilePath
  , harborRegistry :: Text
  , harborApiBaseUrl :: Text
  , harborUsername :: Text
  , harborPassword :: Text
  }
  deriving stock (Eq, Show)

defaultHarborSettings :: HarborSettings
defaultHarborSettings =
  harborSettingsForLocalEdge 9090

harborSettingsForLocalEdge :: Int -> HarborSettings
harborSettingsForLocalEdge edgePort =
  HarborSettings
    { harborDockerBinary = "docker"
    , harborDockerHost = Nothing
    , harborDockerConfigDir = "./.build/docker/harbor"
    , harborCurlBinary = "curl"
    , harborRegistry = "127.0.0.1:" <> portText
    , harborApiBaseUrl = "http://127.0.0.1:" <> portText <> "/harbor/api"
    , harborUsername = "admin"
    , harborPassword = "Harbor12345"
    }
 where
  portText = Text.pack (show edgePort)

newtype HarborSubprocess a = HarborSubprocess
  { unHarborSubprocess :: ReaderT HarborSettings IO a
  }
  deriving newtype
    ( Functor
    , Applicative
    , Monad
    , MonadIO
    , MonadReader HarborSettings
    )

runHarborSubprocess :: HarborSettings -> HarborSubprocess a -> IO a
runHarborSubprocess settings action =
  runReaderT (unHarborSubprocess action) settings

harborLoginSubprocess :: HarborSettings -> Subprocess
harborLoginSubprocess settings =
  subprocessWithStdin
    (harborDockerBinary settings)
    ( dockerArgs
        settings
        [ "login"
        , "--username"
        , harborUsername settings
        , "--password-stdin"
        , harborRegistry settings
        ]
    )
    (harborPassword settings)

harborManifestInspectSubprocess :: HarborSettings -> ImageRef -> Subprocess
harborManifestInspectSubprocess settings (ImageRef imageRef) =
  subprocess
    (harborDockerBinary settings)
    (dockerArgs settings ["manifest", "inspect", imageRef])

harborImageDigestSubprocess :: HarborSettings -> ImageRef -> Subprocess
harborImageDigestSubprocess settings (ImageRef imageRef) =
  subprocess
    (harborDockerBinary settings)
    (dockerArgs settings ["image", "inspect", "--format", "{{.Id}}", imageRef])

harborListRepositoriesSubprocess :: HarborSettings -> Text -> Subprocess
harborListRepositoriesSubprocess settings project =
  subprocess
    (harborCurlBinary settings)
    [ "--fail"
    , "--silent"
    , "--show-error"
    , "--user"
    , harborUsername settings <> ":" <> harborPassword settings
    , harborApiBaseUrl settings <> "/v2.0/projects/" <> project <> "/repositories?page_size=100"
    ]

harborArtifactStatusSubprocess :: HarborSettings -> Text -> Text -> Text -> Subprocess
harborArtifactStatusSubprocess settings project repository tag =
  subprocess
    (harborCurlBinary settings)
    [ "--silent"
    , "--show-error"
    , "--user"
    , harborUsername settings <> ":" <> harborPassword settings
    , "--output"
    , "/dev/null"
    , "--write-out"
    , "%{http_code}"
    , harborApiBaseUrl settings
        <> "/v2.0/projects/"
        <> project
        <> "/repositories/"
        <> encodeRepository repository
        <> "/artifacts/"
        <> tag
    ]

newtype HarborRepository = HarborRepository
  { repositoryName :: Text
  }
  deriving stock (Eq, Show)

instance FromJSON HarborRepository where
  parseJSON =
    withObject "HarborRepository" $ \objectValue ->
      HarborRepository <$> objectValue .: "name"

instance HasHarbor HarborSubprocess where
  harborImageExists imageRef = do
    settings <- ask
    case parseHarborImageRef settings imageRef of
      Left err -> pure (Left err)
      Right (project, repository, tag) -> do
        statusResult <-
          invokeText
            "harborImageExists"
            (harborArtifactStatusSubprocess settings project repository tag)
        case Text.strip <$> statusResult of
          Left err -> pure (Left err)
          Right "200" -> pure (Right True)
          Right "404" -> pure (Right False)
          Right "401" -> pure (Left (SEUnauthorized "harborImageExists: unauthorized"))
          Right status ->
            pure (Left (SETransient ("harborImageExists: unexpected HTTP " <> status)))

  harborPromoteImage source target = do
    settings <- ask
    tagResult <-
      invokeUnit
        "harborPromoteImage.tag"
        ( subprocess
            (harborDockerBinary settings)
            (dockerArgs settings ["tag", unImageRef source, unImageRef target])
        )
    case tagResult of
      Left err -> pure (Left err)
      Right () -> do
        pushResult <- harborPushImage target
        pure (target <$ pushResult)

  harborPushImage imageRef = do
    loginResult <- harborLogin
    case loginResult of
      Left err -> pure (Left err)
      Right () -> do
        settings <- ask
        pushResult <-
          invokeText
            "harborPushImage"
            ( subprocess
                (harborDockerBinary settings)
                (dockerArgs settings ["push", unImageRef imageRef])
            )
        case pushResult of
          Left err -> pure (Left err)
          Right stdoutText -> imageDigest imageRef stdoutText

  harborPullImage imageRef = do
    loginResult <- harborLogin
    case loginResult of
      Left err -> pure (Left err)
      Right () -> do
        settings <- ask
        pullResult <-
          invokeText
            "harborPullImage"
            ( subprocess
                (harborDockerBinary settings)
                (dockerArgs settings ["pull", unImageRef imageRef])
            )
        case pullResult of
          Left err -> pure (Left err)
          Right stdoutText -> imageDigest imageRef stdoutText

  harborListImages project = do
    settings <- ask
    listResult <- invokeText "harborListImages" (harborListRepositoriesSubprocess settings project)
    case listResult of
      Left err -> pure (Left err)
      Right stdoutText ->
        case eitherDecode (LazyByteString.fromStrict (Text.Encoding.encodeUtf8 stdoutText)) of
          Left parseError ->
            pure (Left (SETransient ("harborListImages: JSON parse failed: " <> Text.pack parseError)))
          Right repositories ->
            pure
              ( Right
                  [ ImageRef (harborRegistry settings <> "/" <> repositoryName repository)
                  | repository <- repositories
                  ]
              )

harborLogin :: HarborSubprocess (Either ServiceError ())
harborLogin = do
  settings <- ask
  liftIO (createDirectoryIfMissing True (harborDockerConfigDir settings))
  invokeUnit "harborLogin" (harborLoginSubprocess settings)

dockerArgs :: HarborSettings -> [Text] -> [Text]
dockerArgs settings args =
  maybe [] (\dockerHost -> ["--host", dockerHost]) (harborDockerHost settings)
    <> ["--config", Text.pack (harborDockerConfigDir settings)]
    <> args

parseHarborImageRef :: HarborSettings -> ImageRef -> Either ServiceError (Text, Text, Text)
parseHarborImageRef settings (ImageRef imageRef) = do
  imagePath <-
    maybe
      (Left (SETransient ("harborImageExists: image is outside registry " <> harborRegistry settings)))
      Right
      (Text.stripPrefix (harborRegistry settings <> "/") imageRef)
  (repositoryPath, tag) <-
    maybe
      (Left (SETransient ("harborImageExists: image ref lacks tag: " <> imageRef)))
      Right
      (splitTag imagePath)
  let (project, repositoryWithSlash) = Text.breakOn "/" repositoryPath
      repository = Text.drop 1 repositoryWithSlash
  if Text.null project || Text.null repository
    then Left (SETransient ("harborImageExists: image ref lacks project/repository: " <> imageRef))
    else Right (project, repository, tag)

splitTag :: Text -> Maybe (Text, Text)
splitTag imagePath =
  case Text.breakOnEnd ":" imagePath of
    ("", _) -> Nothing
    (pathWithColon, tag)
      | Text.null tag -> Nothing
      | otherwise -> Just (Text.dropEnd 1 pathWithColon, tag)

encodeRepository :: Text -> Text
encodeRepository =
  Text.replace "/" "%252F"

imageDigest :: ImageRef -> Text -> HarborSubprocess (Either ServiceError ETag)
imageDigest imageRef stdoutText =
  case digestFromDockerOutput stdoutText of
    Just digest -> pure (Right (ETag digest))
    Nothing -> do
      settings <- ask
      digestResult <- invokeText "harborImageDigest" (harborImageDigestSubprocess settings imageRef)
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

invokeUnit :: Text -> Subprocess -> HarborSubprocess (Either ServiceError ())
invokeUnit tag command = do
  result <- invokeText tag command
  pure (void result)

invokeText :: Text -> Subprocess -> HarborSubprocess (Either ServiceError Text)
invokeText tag command = do
  (exitCode, stdoutText, stderrText) <- liftIO (runStreaming defaultSubprocessEnv command)
  case exitCode of
    ExitSuccess -> pure (Right stdoutText)
    ExitFailure code ->
      pure
        ( Left
            ( classifyHarborFailure
                tag
                code
                stderrText
            )
        )

classifyHarborFailure :: Text -> Int -> Text -> ServiceError
classifyHarborFailure tag code stderrText
  | "unauthorized" `Text.isInfixOf` lowerStderr || "401" `Text.isInfixOf` stderrText =
      SEUnauthorized rendered
  | otherwise =
      SETransient rendered
 where
  lowerStderr = Text.toLower stderrText
  rendered =
    tag
      <> ": exit "
      <> Text.pack (show code)
      <> ": "
      <> stderrText
