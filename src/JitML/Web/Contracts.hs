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
  , ApiEndpoint "TrainingStream" "GET" "/api/ws/training"
  , ApiEndpoint "RlStream" "GET" "/api/ws/rl"
  , ApiEndpoint "TuneStream" "GET" "/api/ws/tune"
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
    , "type RlAnimationFrame ="
    , "  { panel :: String"
    , "  , experimentHash :: String"
    , "  , environment :: String"
    , "  , episodeIndex :: Int"
    , "  , stepIndex :: Int"
    , "  , reward :: Number"
    , "  , done :: Boolean"
    , "  , action :: Int"
    , "  , observation :: Array Number"
    , "  , actionProbabilities :: Array Number"
    , "  , observationHash :: String"
    , "  , replayCursor :: String"
    , "  , timestampNs :: String"
    , "  }"
    , ""
    , "type RlReplayFrame ="
    , "  { panel :: String"
    , "  , experimentHash :: String"
    , "  , replayId :: String"
    , "  , environment :: String"
    , "  , episodeIndex :: Int"
    , "  , stepIndex :: Int"
    , "  , action :: Int"
    , "  , reward :: Number"
    , "  , done :: Boolean"
    , "  , observation :: Array Number"
    , "  , nextObservation :: Array Number"
    , "  , policyVersion :: String"
    , "  , observationHash :: String"
    , "  , timestampNs :: String"
    , "  }"
    , ""
    , "renderRlAnimationFrame :: String -> String -> Int -> Int -> Number -> Boolean -> Int -> Array Number -> Array Number -> String -> String -> String -> RlAnimationFrame"
    , "renderRlAnimationFrame experimentHash environment episodeIndex stepIndex reward done action observation actionProbabilities observationHash replayCursor timestampNs ="
    , "  { panel: \"rl-trajectory\""
    , "  , experimentHash"
    , "  , environment"
    , "  , episodeIndex"
    , "  , stepIndex"
    , "  , reward"
    , "  , done"
    , "  , action"
    , "  , observation"
    , "  , actionProbabilities"
    , "  , observationHash"
    , "  , replayCursor"
    , "  , timestampNs"
    , "  }"
    , ""
    , "renderRlReplayFrame :: String -> String -> String -> Int -> Int -> Int -> Number -> Boolean -> Array Number -> Array Number -> String -> String -> String -> RlReplayFrame"
    , "renderRlReplayFrame experimentHash replayId environment episodeIndex stepIndex action reward done observation nextObservation policyVersion observationHash timestampNs ="
    , "  { panel: \"rl-trajectory\""
    , "  , experimentHash"
    , "  , replayId"
    , "  , environment"
    , "  , episodeIndex"
    , "  , stepIndex"
    , "  , action"
    , "  , reward"
    , "  , done"
    , "  , observation"
    , "  , nextObservation"
    , "  , policyVersion"
    , "  , observationHash"
    , "  , timestampNs"
    , "  }"
    , ""
    , "endpoints :: Array Endpoint"
    , "endpoints ="
    ]
      <> endpointLines
      <> ["  ]"]
 where
  endpointLines =
    case apiEndpoints of
      [] -> ["  []"]
      firstEndpoint : rest ->
        ("  [ " <> renderEndpointBody firstEndpoint)
          : fmap (\e -> "  , " <> renderEndpointBody e) rest

  renderEndpointBody endpoint =
    "{ name: \""
      <> endpointName endpoint
      <> "\", method: \""
      <> endpointMethod endpoint
      <> "\", path: \""
      <> endpointPath endpoint
      <> "\" }"
