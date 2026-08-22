{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.BootConfig
  ( BootConfig (..)
  , BootConfigError (..)
  , HttpListener (..)
  , InferenceMode (..)
  , Residency (..)
  , Role (..)
  , defaultBootConfig
  , loadBootConfig
  , renderBootConfigDhall
  , renderBootConfigError
  , renderInferenceMode
  , renderResidency
  , renderRole
  , rawBootConfigDecoder
  , validateBootConfig
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
-- role that computes; the __Coordinator__ owns the Pulsar topic lifecycle,
-- cluster placement, and readiness gating; the __Webapp__ is a thin
-- websocket/static surface. Coordinator and Engine use disjoint subscriptions
-- and effects.
-- See @documents/engineering/pulsar_ml_workflow.md@ → /The three roles/.
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
  , bootImageRegistry :: Text
  , bootHttpListener :: Maybe HttpListener
  , bootWebappPulsarWsUrl :: Maybe Text
  -- ^ Sprint 11.10 — the Pulsar __WebSocket__ endpoint the @Webapp@ role uses
  -- for its held-open @/api/ws@ bridge and its inference @WorkCommand@ publish
  -- client. Present only for @activeRole = Webapp@; the @Engine@ omits it
  -- (@None@). It cannot be derived from @pulsarServiceUrl@ (the broker WS
  -- service uses a different host/port than the binary-protocol proxy).
  }
  deriving stock (Eq, Show)

-- | Fail-closed refinement errors for the combinations that the runtime can
-- actually execute. Dhall validates each field's shape; this second boundary
-- validates the relationships between role, substrate, residency, inference
-- mode, listener ownership, and the Webapp-only broker endpoint.
data BootConfigError
  = UnknownBootConfigSubstrate Text
  | UnsupportedBootRuntime Substrate Residency InferenceMode
  | HostResidencyRequiresEngine Role
  | ClusterResidencyRequiresHttpListener Role
  | HostResidencyForbidsHttpListener
  | EmptyHttpListenerHost
  | HttpListenerPortOutOfRange Integer
  | WebappRequiresPulsarWebSocketUrl
  | NonWebappForbidsPulsarWebSocketUrl Role
  deriving stock (Eq, Show)

data RawBootConfig = RawBootConfig
  { rawActiveRole :: Role
  , rawSubstrate :: Text
  , rawResidency :: Residency
  , rawInferenceMode :: InferenceMode
  , rawPulsarServiceUrl :: Text
  , rawPulsarAdminUrl :: Text
  , rawMinioEndpoint :: Text
  , rawImageRegistry :: Text
  , rawHttpListener :: Maybe RawHttpListener
  , rawWebappPulsarWsUrl :: Maybe Text
  }
  deriving stock (Eq, Show)

data RawHttpListener = RawHttpListener
  { rawListenerHost :: Text
  , rawListenerPort :: Natural
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
    , bootImageRegistry = "registry.platform.svc.cluster.local:5000/library"
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
    , ", imageRegistry = \"" <> bootImageRegistry config <> "\""
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
    Left err -> ioError (userError (Text.unpack (renderBootConfigError err)))

-- | Accept only the three documented execution topologies:
--
-- * Linux CPU/CUDA in-cluster with self inference;
-- * Apple Silicon in-cluster forwarding to the host; or
-- * the Apple Silicon host Engine with self inference.
--
-- Coordinator is cluster-resident; it reconciles the typed topic family and
-- serves the orchestration-only command plan.
validateBootConfig :: BootConfig -> Either BootConfigError BootConfig
validateBootConfig config = do
  validateRuntimeTopology config
  validateRoleResidency config
  validateListener config
  validateWebappEndpoint config
  pure config

validateRuntimeTopology :: BootConfig -> Either BootConfigError ()
validateRuntimeTopology config =
  case (bootSubstrate config, bootResidency config, bootInferenceMode config) of
    (LinuxCPU, Cluster, SelfInference) -> Right ()
    (LinuxCUDA, Cluster, SelfInference) -> Right ()
    (AppleSilicon, Cluster, ForwardToHost) -> Right ()
    (AppleSilicon, Host, SelfInference) -> Right ()
    (substrate, residency, inferenceMode) ->
      Left (UnsupportedBootRuntime substrate residency inferenceMode)

validateRoleResidency :: BootConfig -> Either BootConfigError ()
validateRoleResidency config =
  case (bootActiveRole config, bootResidency config) of
    (Engine, _) -> Right ()
    (role, Host) -> Left (HostResidencyRequiresEngine role)
    (_, Cluster) -> Right ()

validateListener :: BootConfig -> Either BootConfigError ()
validateListener config =
  case (bootResidency config, bootHttpListener config) of
    (Cluster, Nothing) -> Left (ClusterResidencyRequiresHttpListener (bootActiveRole config))
    (Host, Just _) -> Left HostResidencyForbidsHttpListener
    (_, Nothing) -> Right ()
    (_, Just listener)
      | Text.null (Text.strip (listenerHost listener)) -> Left EmptyHttpListenerHost
      | listenerPort listener < 1 || listenerPort listener > 65535 ->
          Left (HttpListenerPortOutOfRange (fromIntegral (listenerPort listener)))
      | otherwise -> Right ()

validateWebappEndpoint :: BootConfig -> Either BootConfigError ()
validateWebappEndpoint config =
  case (bootActiveRole config, bootWebappPulsarWsUrl config) of
    (Webapp, Just endpoint)
      | not (Text.null (Text.strip endpoint)) -> Right ()
    (Webapp, _) -> Left WebappRequiresPulsarWebSocketUrl
    (_role, Nothing) -> Right ()
    (role, Just _) -> Left (NonWebappForbidsPulsarWebSocketUrl role)

renderBootConfigError :: BootConfigError -> Text
renderBootConfigError err =
  case err of
    UnknownBootConfigSubstrate substrate ->
      "unknown substrate in BootConfig: " <> substrate
    UnsupportedBootRuntime substrate residency inferenceMode ->
      "unsupported BootConfig runtime topology: substrate="
        <> renderSubstrate substrate
        <> ", residency="
        <> showText residency
        <> ", inferenceMode="
        <> showText inferenceMode
    HostResidencyRequiresEngine role ->
      "BootConfig host residency requires activeRole=Engine, received " <> showText role
    ClusterResidencyRequiresHttpListener role ->
      "BootConfig cluster residency requires an HTTP listener for activeRole=" <> showText role
    HostResidencyForbidsHttpListener ->
      "BootConfig host residency forbids an HTTP listener"
    EmptyHttpListenerHost ->
      "BootConfig HTTP listener host must be non-empty"
    HttpListenerPortOutOfRange port ->
      "BootConfig HTTP listener port must be between 1 and 65535, received " <> showText port
    WebappRequiresPulsarWebSocketUrl ->
      "BootConfig activeRole=Webapp requires a non-empty webappPulsarWsUrl"
    NonWebappForbidsPulsarWebSocketUrl role ->
      "BootConfig webappPulsarWsUrl is only legal for activeRole=Webapp, received " <> showText role

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
      <*> Dhall.field "imageRegistry" Dhall.strictText
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

httpListenerDecoder :: Dhall.Decoder RawHttpListener
httpListenerDecoder =
  Dhall.record $
    RawHttpListener
      <$> Dhall.field "host" Dhall.strictText
      <*> Dhall.field "port" Dhall.natural

rawToBootConfig :: RawBootConfig -> Either BootConfigError BootConfig
rawToBootConfig raw = do
  substrate <-
    maybe
      (Left (UnknownBootConfigSubstrate (rawSubstrate raw)))
      Right
      (parseSubstrate (rawSubstrate raw))
  listener <- traverse rawHttpListenerToHttpListener (rawHttpListener raw)
  validateBootConfig
    ( BootConfig
        { bootActiveRole = rawActiveRole raw
        , bootSubstrate = substrate
        , bootResidency = rawResidency raw
        , bootInferenceMode = rawInferenceMode raw
        , bootPulsarServiceUrl = rawPulsarServiceUrl raw
        , bootPulsarAdminUrl = rawPulsarAdminUrl raw
        , bootMinioEndpoint = rawMinioEndpoint raw
        , bootImageRegistry = rawImageRegistry raw
        , bootHttpListener = listener
        , bootWebappPulsarWsUrl = rawWebappPulsarWsUrl raw
        }
    )

rawHttpListenerToHttpListener
  :: RawHttpListener
  -> Either BootConfigError HttpListener
rawHttpListenerToHttpListener raw
  | port < 1 || port > 65535 =
      Left (HttpListenerPortOutOfRange (fromIntegral port))
  | otherwise =
      Right
        HttpListener
          { listenerHost = rawListenerHost raw
          , listenerPort = fromIntegral port
          }
 where
  port = rawListenerPort raw

showText :: (Show value) => value -> Text
showText = Text.pack . show

_edgePortAnchor :: Substrate -> Int
_edgePortAnchor = substrateEdgePort
