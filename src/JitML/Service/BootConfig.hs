{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.BootConfig
  ( BootConfig (..)
  , HttpListener (..)
  , InferenceMode (..)
  , Residency (..)
  , Role (..)
  , defaultBootConfig
  , loadBootConfig
  , renderBootConfigDhall
  , renderInferenceMode
  , renderResidency
  , renderRole
  , rawBootConfigDecoder
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Dhall qualified
import Numeric.Natural (Natural)

import JitML.Substrate (Substrate (..), parseSubstrate, renderSubstrate, substrateEdgePort)

-- | Sprint 5.14 (Pulsar ML-Workflow convergence) — the one-binary role. The
-- same @jitml service@ binary runs as exactly one of these, selected by typed
-- Dhall @activeRole@ (no env-var role selection). The __Engine__ is the only
-- role that computes (training + inference); the __Coordinator__ owns the Pulsar
-- topic lifecycle + readiness gating; the __Webapp__ is a thin websocket/static
-- surface. See @documents/engineering/pulsar_ml_workflow.md@ → /The three roles/.
data Role
  = Engine
  | Coordinator
  | Webapp
  deriving stock (Eq, Show)

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
  { bootActiveRole :: Role
  , bootSubstrate :: Substrate
  , bootResidency :: Residency
  , bootInferenceMode :: InferenceMode
  , bootPulsarServiceUrl :: Text
  , bootPulsarAdminUrl :: Text
  , bootMinioEndpoint :: Text
  , bootHarborRegistry :: Text
  , bootHttpListener :: Maybe HttpListener
  , bootWebappPulsarWsUrl :: Maybe Text
  -- ^ Sprint 11.10 — the Pulsar __WebSocket__ endpoint the @Webapp@ role uses
  -- for its held-open @/api/ws@ bridge and its inference @WorkCommand@ publish
  -- client. Present only for @activeRole = Webapp@; the @Engine@ omits it
  -- (@None@). It cannot be derived from @pulsarServiceUrl@ (the broker WS
  -- service uses a different host/port than the binary-protocol proxy).
  }
  deriving stock (Eq, Show)

data RawBootConfig = RawBootConfig
  { rawActiveRole :: Role
  , rawSubstrate :: Text
  , rawResidency :: Residency
  , rawInferenceMode :: InferenceMode
  , rawPulsarServiceUrl :: Text
  , rawPulsarAdminUrl :: Text
  , rawMinioEndpoint :: Text
  , rawHarborRegistry :: Text
  , rawHttpListener :: Maybe HttpListener
  , rawWebappPulsarWsUrl :: Maybe Text
  }
  deriving stock (Eq, Show)

defaultBootConfig :: Substrate -> Residency -> BootConfig
defaultBootConfig substrate residency =
  BootConfig
    { bootActiveRole = Engine
    , bootSubstrate = substrate
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
    , bootWebappPulsarWsUrl = Nothing
    }

renderBootConfigDhall :: BootConfig -> Text
renderBootConfigDhall config =
  Text.unlines
    [ "{ activeRole = " <> renderRole (bootActiveRole config)
    , ", substrate = \"" <> renderSubstrate (bootSubstrate config) <> "\""
    , ", residency = " <> renderResidency (bootResidency config)
    , ", inferenceMode = " <> renderInferenceMode (bootInferenceMode config)
    , ", pulsarServiceUrl = \"" <> bootPulsarServiceUrl config <> "\""
    , ", pulsarAdminUrl = \"" <> bootPulsarAdminUrl config <> "\""
    , ", minioEndpoint = \"" <> bootMinioEndpoint config <> "\""
    , ", harborRegistry = \"" <> bootHarborRegistry config <> "\""
    , ", httpListener = " <> renderListener (bootHttpListener config)
    , ", webappPulsarWsUrl = " <> renderOptionalText (bootWebappPulsarWsUrl config)
    , "}"
    ]

renderOptionalText :: Maybe Text -> Text
renderOptionalText Nothing = "None Text"
renderOptionalText (Just value) = "Some \"" <> value <> "\""

loadBootConfig :: FilePath -> IO BootConfig
loadBootConfig path = do
  raw <- Dhall.inputFile rawBootConfigDecoder path
  case rawToBootConfig raw of
    Right config -> pure config
    Left err -> ioError (userError (Text.unpack err))

renderRole :: Role -> Text
renderRole Engine = "< Engine | Coordinator | Webapp >.Engine"
renderRole Coordinator = "< Engine | Coordinator | Webapp >.Coordinator"
renderRole Webapp = "< Engine | Coordinator | Webapp >.Webapp"

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
      <$> Dhall.field "activeRole" roleDecoder
      <*> Dhall.field "substrate" Dhall.strictText
      <*> Dhall.field "residency" residencyDecoder
      <*> Dhall.field "inferenceMode" inferenceModeDecoder
      <*> Dhall.field "pulsarServiceUrl" Dhall.strictText
      <*> Dhall.field "pulsarAdminUrl" Dhall.strictText
      <*> Dhall.field "minioEndpoint" Dhall.strictText
      <*> Dhall.field "harborRegistry" Dhall.strictText
      <*> Dhall.field "httpListener" (Dhall.maybe httpListenerDecoder)
      <*> Dhall.field "webappPulsarWsUrl" (Dhall.maybe Dhall.strictText)

roleDecoder :: Dhall.Decoder Role
roleDecoder =
  Dhall.union $
    Dhall.constructor "Engine" (Engine <$ Dhall.unit)
      <> Dhall.constructor "Coordinator" (Coordinator <$ Dhall.unit)
      <> Dhall.constructor "Webapp" (Webapp <$ Dhall.unit)

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
      { bootActiveRole = rawActiveRole raw
      , bootSubstrate = substrate
      , bootResidency = rawResidency raw
      , bootInferenceMode = rawInferenceMode raw
      , bootPulsarServiceUrl = rawPulsarServiceUrl raw
      , bootPulsarAdminUrl = rawPulsarAdminUrl raw
      , bootMinioEndpoint = rawMinioEndpoint raw
      , bootHarborRegistry = rawHarborRegistry raw
      , bootHttpListener = rawHttpListener raw
      , bootWebappPulsarWsUrl = rawWebappPulsarWsUrl raw
      }

naturalToInt :: Natural -> Int
naturalToInt = fromIntegral

_edgePortAnchor :: Substrate -> Int
_edgePortAnchor = substrateEdgePort
