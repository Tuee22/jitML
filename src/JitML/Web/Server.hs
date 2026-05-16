{-# LANGUAGE OverloadedStrings #-}

module JitML.Web.Server
  ( demoHttpRoutes
  , demoListener
  , renderDemoIndex
  , serveDemo
  , serveDemoOnce
  )
where

import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import System.Environment (lookupEnv)

import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.RL.Algorithms qualified as RL
import JitML.RL.AlphaZero qualified as AlphaZero
import JitML.SL.Canonicals qualified as SL
import JitML.Service.BootConfig (HttpListener (..))
import JitML.Service.Endpoints (EndpointResponse (..))
import JitML.Service.Http (HttpRoute (..), serveHttpRoutes, serveHttpRoutesOnce)
import JitML.Web.Bundle qualified as Bundle
import JitML.Web.Contracts qualified as Contracts

demoListener :: Int -> HttpListener
demoListener =
  HttpListener "127.0.0.1"

serveDemo :: IO ()
serveDemo = do
  port <- demoPort
  serveHttpRoutes (demoListener port) demoHttpRoutes

serveDemoOnce :: IO ()
serveDemoOnce = do
  port <- demoPort
  serveHttpRoutesOnce (demoListener port) demoHttpRoutes

demoHttpRoutes :: [HttpRoute]
demoHttpRoutes =
  [ htmlRoute "GET" "/" (EndpointResponse 200 renderDemoIndex)
  , textRoute "GET" "/api" (EndpointResponse 200 renderApiIndex)
  , textRoute "POST" "/api/inference" (EndpointResponse 200 renderInferenceResponse)
  , textRoute "POST" "/api/images" (EndpointResponse 200 "accepted image upload contract\n")
  , textRoute "POST" "/api/connect4/move" (EndpointResponse 200 renderConnect4Response)
  , textRoute "GET" "/api/ws" (EndpointResponse 200 renderMetricsStream)
  ]

renderDemoIndex :: Text
renderDemoIndex =
  Text.unlines
    [ "<!doctype html>"
    , "<html lang=\"en\">"
    , "<head><meta charset=\"utf-8\"><title>jitML Demo</title></head>"
    , "<body>"
    , "<main id=\"app\">"
    , "<h1>jitML Demo</h1>"
    , "<pre>"
    , Bundle.renderBundleManifest
    , "</pre>"
    , "</main>"
    , "</body>"
    , "</html>"
    ]

renderApiIndex :: Text
renderApiIndex =
  Text.unlines $
    [ "endpoints:"
    ]
      <> fmap renderEndpoint Contracts.apiEndpoints
 where
  renderEndpoint endpoint =
    "- "
      <> Contracts.endpointMethod endpoint
      <> " "
      <> Contracts.endpointPath endpoint
      <> " "
      <> Contracts.endpointName endpoint

renderInferenceResponse :: Text
renderInferenceResponse =
  let manifest =
        Checkpoint.CheckpointManifest
          "demo"
          "experiments/mnist.dhall"
          [Checkpoint.TensorBlob "dense.weight" [2, 2] "blob-demo"]
   in "prediction: " <> Text.pack (show (Checkpoint.inferFromManifest manifest [0.2, 0.8])) <> "\n"

renderConnect4Response :: Text
renderConnect4Response =
  "move: "
    <> Text.pack (show firstDemoMove)
    <> "\n"
 where
  firstDemoMove =
    case AlphaZero.gameMoves (AlphaZero.applyMove 0 AlphaZero.initialConnect4) of
      move : _ -> move
      [] -> 0

renderMetricsStream :: Text
renderMetricsStream =
  Text.unlines
    [ "event: metrics"
    , "data: algorithms=" <> Text.pack (show (length RL.algorithmCatalog))
    , "data: canonicalProblems=" <> Text.pack (show (length SL.canonicalProblems))
    ]

textRoute :: Text -> Text -> EndpointResponse -> HttpRoute
textRoute method path response =
  HttpRoute
    { httpRouteMethod = method
    , httpRoutePath = path
    , httpRouteContentType = "text/plain; charset=utf-8"
    , httpRouteResponse = response
    }

htmlRoute :: Text -> Text -> EndpointResponse -> HttpRoute
htmlRoute method path response =
  HttpRoute
    { httpRouteMethod = method
    , httpRoutePath = path
    , httpRouteContentType = "text/html; charset=utf-8"
    , httpRouteResponse = response
    }

demoPort :: IO Int
demoPort = do
  value <- lookupEnv "PORT"
  pure (fromMaybe 8080 (value >>= readMaybeInt))

readMaybeInt :: String -> Maybe Int
readMaybeInt value =
  case reads value of
    [(parsed, "")] -> Just parsed
    _ -> Nothing
