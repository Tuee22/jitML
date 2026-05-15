{-# LANGUAGE OverloadedStrings #-}

module JitML.Web.Contracts
  ( ApiEndpoint (..)
  , apiEndpoints
  , contractGeneratorName
  , renderPureScriptContracts
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

data ApiEndpoint = ApiEndpoint
  { endpointName :: Text
  , endpointMethod :: Text
  , endpointPath :: Text
  }
  deriving stock (Eq, Show)

apiEndpoints :: [ApiEndpoint]
apiEndpoints =
  [ ApiEndpoint "RunCommand" "POST" "/api/runs/{runId}/command"
  , ApiEndpoint "InferenceRun" "POST" "/api/inference"
  , ApiEndpoint "UploadImage" "POST" "/api/images"
  , ApiEndpoint "Connect4Move" "POST" "/api/connect4/move"
  , ApiEndpoint "MetricsStream" "GET" "/api/ws"
  ]

contractGeneratorName :: Text
contractGeneratorName =
  "local-purescript-bridge-compatible-renderer"

renderPureScriptContracts :: Text
renderPureScriptContracts =
  Text.unlines $
    [ "module Generated.Contracts where"
    , ""
    , "type Endpoint = { name :: String, method :: String, path :: String }"
    , ""
    , "endpoints :: Array Endpoint"
    , "endpoints ="
    , "  [ "
    ]
      <> endpointLines
      <> ["  ]"]
 where
  endpointLines =
    case apiEndpoints of
      [] -> []
      firstEndpoint : rest ->
        renderEndpoint firstEndpoint : fmap (("  , " <>) . dropPrefix . renderEndpoint) rest

  renderEndpoint endpoint =
    "    { name: \""
      <> endpointName endpoint
      <> "\", method: \""
      <> endpointMethod endpoint
      <> "\", path: \""
      <> endpointPath endpoint
      <> "\" }"

  dropPrefix =
    Text.dropWhile (== ' ')
