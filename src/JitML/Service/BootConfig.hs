{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.BootConfig
  ( BootConfig (..)
  , HttpListener (..)
  , InferenceMode (..)
  , Residency (..)
  , defaultBootConfig
  , loadBootConfig
  , renderBootConfigDhall
  , renderInferenceMode
  , renderResidency
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Dhall qualified
import Numeric.Natural (Natural)

import JitML.Substrate (Substrate (..), parseSubstrate, renderSubstrate, substrateEdgePort)

data Residency
  = Cluster
  | Host
  deriving stock (Eq, Show)

data InferenceMode
  = SelfInference
  | ForwardToHost
  deriving stock (Eq, Show)

data HttpListener = HttpListener
  { listenerHost :: Text
  , listenerPort :: Int
  }
  deriving stock (Eq, Show)

data BootConfig = BootConfig
  { bootSubstrate :: Substrate
  , bootResidency :: Residency
  , bootInferenceMode :: InferenceMode
  , bootPulsarServiceUrl :: Text
  , bootPulsarAdminUrl :: Text
  , bootMinioEndpoint :: Text
  , bootHarborRegistry :: Text
  , bootHttpListener :: Maybe HttpListener
  }
  deriving stock (Eq, Show)

data RawBootConfig = RawBootConfig
  { rawSubstrate :: Text
  , rawResidency :: Residency
  , rawInferenceMode :: InferenceMode
  , rawPulsarServiceUrl :: Text
  , rawPulsarAdminUrl :: Text
  , rawMinioEndpoint :: Text
  , rawHarborRegistry :: Text
  , rawHttpListener :: Maybe HttpListener
  }
  deriving stock (Eq, Show)

defaultBootConfig :: Substrate -> Residency -> BootConfig
defaultBootConfig substrate residency =
  BootConfig
    { bootSubstrate = substrate
    , bootResidency = residency
    , bootInferenceMode = defaultInferenceMode substrate residency
    , bootPulsarServiceUrl = "pulsar://pulsar-proxy.platform.svc.cluster.local:6650"
    , bootPulsarAdminUrl = "http://pulsar-proxy.platform.svc.cluster.local:80"
    , bootMinioEndpoint = "http://minio.platform.svc.cluster.local:9000"
    , bootHarborRegistry = "harbor-registry.platform.svc.cluster.local:5000/library"
    , bootHttpListener =
        case residency of
          Cluster -> Just (HttpListener "0.0.0.0" 8080)
          Host -> Nothing
    }

renderBootConfigDhall :: BootConfig -> Text
renderBootConfigDhall config =
  Text.unlines
    [ "{ substrate = \"" <> renderSubstrate (bootSubstrate config) <> "\""
    , ", residency = " <> renderResidency (bootResidency config)
    , ", inferenceMode = " <> renderInferenceMode (bootInferenceMode config)
    , ", pulsarServiceUrl = \"" <> bootPulsarServiceUrl config <> "\""
    , ", pulsarAdminUrl = \"" <> bootPulsarAdminUrl config <> "\""
    , ", minioEndpoint = \"" <> bootMinioEndpoint config <> "\""
    , ", harborRegistry = \"" <> bootHarborRegistry config <> "\""
    , ", httpListener = " <> renderListener (bootHttpListener config)
    , "}"
    ]

loadBootConfig :: FilePath -> IO BootConfig
loadBootConfig path = do
  raw <- Dhall.inputFile rawBootConfigDecoder path
  case rawToBootConfig raw of
    Right config -> pure config
    Left err -> ioError (userError (Text.unpack err))

renderResidency :: Residency -> Text
renderResidency Cluster = "< Cluster | Host >.Cluster"
renderResidency Host = "< Cluster | Host >.Host"

renderInferenceMode :: InferenceMode -> Text
renderInferenceMode SelfInference = "< SelfInference | ForwardToHost >.SelfInference"
renderInferenceMode ForwardToHost = "< SelfInference | ForwardToHost >.ForwardToHost"

defaultInferenceMode :: Substrate -> Residency -> InferenceMode
defaultInferenceMode AppleSilicon Cluster = ForwardToHost
defaultInferenceMode _ _ = SelfInference

renderListener :: Maybe HttpListener -> Text
renderListener Nothing = "None { host : Text, port : Natural }"
renderListener (Just listener) =
  "Some { host = \""
    <> listenerHost listener
    <> "\", port = "
    <> Text.pack (show (listenerPort listener))
    <> " }"

rawBootConfigDecoder :: Dhall.Decoder RawBootConfig
rawBootConfigDecoder =
  Dhall.record $
    RawBootConfig
      <$> Dhall.field "substrate" Dhall.strictText
      <*> Dhall.field "residency" residencyDecoder
      <*> Dhall.field "inferenceMode" inferenceModeDecoder
      <*> Dhall.field "pulsarServiceUrl" Dhall.strictText
      <*> Dhall.field "pulsarAdminUrl" Dhall.strictText
      <*> Dhall.field "minioEndpoint" Dhall.strictText
      <*> Dhall.field "harborRegistry" Dhall.strictText
      <*> Dhall.field "httpListener" (Dhall.maybe httpListenerDecoder)

residencyDecoder :: Dhall.Decoder Residency
residencyDecoder =
  Dhall.union $
    Dhall.constructor "Cluster" (Cluster <$ Dhall.unit)
      <> Dhall.constructor "Host" (Host <$ Dhall.unit)

inferenceModeDecoder :: Dhall.Decoder InferenceMode
inferenceModeDecoder =
  Dhall.union $
    Dhall.constructor "SelfInference" (SelfInference <$ Dhall.unit)
      <> Dhall.constructor "ForwardToHost" (ForwardToHost <$ Dhall.unit)

httpListenerDecoder :: Dhall.Decoder HttpListener
httpListenerDecoder =
  Dhall.record $
    HttpListener
      <$> Dhall.field "host" Dhall.strictText
      <*> fmap naturalToInt (Dhall.field "port" Dhall.natural)

rawToBootConfig :: RawBootConfig -> Either Text BootConfig
rawToBootConfig raw = do
  substrate <-
    maybe
      (Left ("unknown substrate in BootConfig: " <> rawSubstrate raw))
      Right
      (parseSubstrate (rawSubstrate raw))
  pure
    BootConfig
      { bootSubstrate = substrate
      , bootResidency = rawResidency raw
      , bootInferenceMode = rawInferenceMode raw
      , bootPulsarServiceUrl = rawPulsarServiceUrl raw
      , bootPulsarAdminUrl = rawPulsarAdminUrl raw
      , bootMinioEndpoint = rawMinioEndpoint raw
      , bootHarborRegistry = rawHarborRegistry raw
      , bootHttpListener = rawHttpListener raw
      }

naturalToInt :: Natural -> Int
naturalToInt = fromIntegral

_edgePortAnchor :: Substrate -> Int
_edgePortAnchor = substrateEdgePort
