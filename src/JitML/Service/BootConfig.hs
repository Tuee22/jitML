{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.BootConfig
  ( BootConfig (..)
  , HttpListener (..)
  , InferenceMode (..)
  , Residency (..)
  , defaultBootConfig
  , renderBootConfigDhall
  , renderInferenceMode
  , renderResidency
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Substrate (Substrate (..), renderSubstrate, substrateEdgePort)

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

defaultBootConfig :: Substrate -> Residency -> BootConfig
defaultBootConfig substrate residency =
  BootConfig
    { bootSubstrate = substrate
    , bootResidency = residency
    , bootInferenceMode = defaultInferenceMode substrate residency
    , bootPulsarServiceUrl = "pulsar://jitml-pulsar-proxy.platform.svc.cluster.local:6650"
    , bootPulsarAdminUrl = "http://jitml-pulsar-proxy.platform.svc.cluster.local:8080"
    , bootMinioEndpoint = "http://jitml-minio.platform.svc.cluster.local:9000"
    , bootHarborRegistry = "harbor.platform.svc.cluster.local/jitml"
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

renderResidency :: Residency -> Text
renderResidency Cluster = "Cluster"
renderResidency Host = "Host"

renderInferenceMode :: InferenceMode -> Text
renderInferenceMode SelfInference = "SelfInference"
renderInferenceMode ForwardToHost = "ForwardToHost"

defaultInferenceMode :: Substrate -> Residency -> InferenceMode
defaultInferenceMode AppleSilicon Cluster = ForwardToHost
defaultInferenceMode _ _ = SelfInference

renderListener :: Maybe HttpListener -> Text
renderListener Nothing = "None HttpListener"
renderListener (Just listener) =
  "Some { host = \""
    <> listenerHost listener
    <> "\", port = "
    <> Text.pack (show (listenerPort listener))
    <> " }"

_edgePortAnchor :: Substrate -> Int
_edgePortAnchor = substrateEdgePort
