{-# LANGUAGE OverloadedStrings #-}

module JitML.Web.Server
  ( bundleEntryPath
  , demoHttpRoutes
  , demoHttpRoutesWithBundle
  , demoListener
  , loadBundleEntry
  , renderDemoIndex
  , renderDemoIndexWithBundle
  , serveDemo
  , serveDemoOnce
  )
where

import Control.Exception qualified
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import System.Directory (doesFileExist)

import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.RL.Algorithms qualified as RL
import JitML.RL.AlphaZero qualified as AlphaZero
import JitML.SL.Canonicals qualified as SL
import JitML.Service.BootConfig (HttpListener (..))
import JitML.Service.Endpoints (EndpointResponse (..))
import JitML.Service.Http (HttpRoute (..), serveHttpRoutes, serveHttpRoutesOnce)
import JitML.Web.Bundle qualified as Bundle
import JitML.Web.Contracts qualified as Contracts

demoListener :: Text -> Int -> HttpListener
demoListener =
  HttpListener

serveDemo :: Text -> Int -> IO ()
serveDemo host port = do
  bundle <- loadBundleEntry
  serveHttpRoutes (demoListener host port) (demoHttpRoutesWithBundle bundle)

serveDemoOnce :: Text -> Int -> IO ()
serveDemoOnce host port = do
  bundle <- loadBundleEntry
  serveHttpRoutesOnce (demoListener host port) (demoHttpRoutesWithBundle bundle)

-- | Canonical path to the compiled Halogen entry bundle. `spago build
-- --output web/dist` writes the per-module CoreFn JS under
-- `web/dist/<Module>/index.js`; the demo serves the Main module's entry
-- at `/bundle/main.js`.
bundleEntryPath :: FilePath
bundleEntryPath = "web/dist/Main/index.js"

-- | Read the compiled Halogen bundle if `spago build` has produced it;
-- returns Nothing otherwise so the demo falls back to the placeholder
-- HTML shell.
loadBundleEntry :: IO (Maybe Text)
loadBundleEntry = do
  exists <- doesFileExist bundleEntryPath
  if exists
    then
      (Just <$> Text.IO.readFile bundleEntryPath)
        `Control.Exception.catch` \(_ :: Control.Exception.SomeException) -> pure Nothing
    else pure Nothing

demoHttpRoutes :: [HttpRoute]
demoHttpRoutes = demoHttpRoutesWithBundle Nothing

-- | Build the demo HTTP route table, optionally embedding the compiled
-- Halogen bundle. When `Just <js>` is passed, `/` serves an HTML shell
-- that script-tags `/bundle/main.js`, and `/bundle/main.js` serves the
-- bundle bytes; otherwise the route table falls back to the placeholder
-- HTML shell.
demoHttpRoutesWithBundle :: Maybe Text -> [HttpRoute]
demoHttpRoutesWithBundle bundle =
  [ htmlRoute "GET" "/" (EndpointResponse 200 (renderDemoIndexWithBundle bundle))
  , textRoute "GET" "/api" (EndpointResponse 200 renderApiIndex)
  , textRoute "POST" "/api/inference" (EndpointResponse 200 renderInferenceResponse)
  , textRoute "POST" "/api/images" (EndpointResponse 200 "accepted image upload contract\n")
  , textRoute "POST" "/api/connect4/move" (EndpointResponse 200 renderConnect4Response)
  , textRoute "GET" "/api/ws" (EndpointResponse 200 renderMetricsStream)
  ]
    <> case bundle of
      Just js ->
        [ HttpRoute
            { httpRouteMethod = "GET"
            , httpRoutePath = "/bundle/main.js"
            , httpRouteContentType = "application/javascript; charset=utf-8"
            , httpRouteResponse = EndpointResponse 200 js
            }
        ]
      Nothing -> []

renderDemoIndex :: Text
renderDemoIndex = renderDemoIndexWithBundle Nothing

-- | HTML shell for the demo `/` route. When `Just <js>` is supplied, a
-- `<script src="/bundle/main.js">` tag is included that loads the
-- compiled Halogen bundle; otherwise the page renders the placeholder
-- bundle manifest.
renderDemoIndexWithBundle :: Maybe Text -> Text
renderDemoIndexWithBundle bundle =
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
    , case bundle of
        Just _ -> "<script type=\"module\" src=\"/bundle/main.js\"></script>"
        Nothing -> "<!-- bundle not built: run `spago build --output web/dist/` -->"
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
        Checkpoint.emptyManifest
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
