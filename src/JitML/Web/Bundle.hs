{-# LANGUAGE OverloadedStrings #-}

module JitML.Web.Bundle
  ( BundleAsset (..)
  , DemoRoute (..)
  , PanelSurface (..)
  , bundleAssets
  , demoRoutes
  , demoStatusLine
  , panelSurfaces
  , renderBundleManifest
  , renderDemoRouteManifest
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

data BundleAsset = BundleAsset
  { bundleAssetPath :: FilePath
  , bundleAssetSource :: FilePath
  }
  deriving stock (Eq, Show)

data PanelSurface = PanelSurface
  { panelName :: Text
  , panelEndpoint :: Text
  , panelPurpose :: Text
  }
  deriving stock (Eq, Show)

data DemoRoute = DemoRoute
  { demoRoutePath :: Text
  , demoRouteSurface :: Text
  , demoRouteSource :: Text
  }
  deriving stock (Eq, Show)

bundleAssets :: [BundleAsset]
bundleAssets =
  [ BundleAsset "web/dist/index.html" "web/src/Main.purs"
  , BundleAsset "web/dist/app.js" "web/src/Generated/Contracts.purs"
  ]

panelSurfaces :: [PanelSurface]
panelSurfaces =
  [ PanelSurface "mnist-live-inference" "/api/inference" "MNIST inference"
  , PanelSurface "generic-inference-lab" "/api/inference/generic" "Generic tensor inference"
  , PanelSurface "checkpoint-compare-lab" "/api/checkpoints/compare" "Checkpoint comparison"
  , PanelSurface "cifar-imagenet-upload" "/api/images" "CIFAR/ImageNet upload"
  , PanelSurface "connect4-human-vs-alphazero" "/api/connect4/move" "Connect 4 moves"
  , PanelSurface "rl-trajectory" "/api/ws/rl" "RL trajectory stream"
  , PanelSurface "training-progress" "/api/ws/training" "Training metric stream"
  , PanelSurface "hyperparameter-sweep" "/api/ws/tune" "Tuner trial stream"
  ]

demoStatusLine :: Text
demoStatusLine =
  "jitml-demo: serving generated frontend contract surface"

demoRoutes :: [DemoRoute]
demoRoutes =
  [ DemoRoute "/" "static-shell" "web/src/Main.purs"
  , DemoRoute "/api" "contract-index" "src/JitML/Web/Contracts.hs"
  , DemoRoute "/api/runs/{runId}/command" "workflow-command-contract" "src/JitML/Web/Contracts.hs"
  , DemoRoute "/api/inference" "inference-contract" "src/JitML/Web/Contracts.hs"
  , DemoRoute "/api/inference/generic" "generic-inference-contract" "src/JitML/Web/Contracts.hs"
  , DemoRoute "/api/images" "image-upload-contract" "src/JitML/Web/Contracts.hs"
  , DemoRoute "/api/checkpoints/compare" "checkpoint-compare-contract" "src/JitML/Web/Contracts.hs"
  , DemoRoute "/api/connect4/move" "connect4-contract" "src/JitML/Web/Contracts.hs"
  , DemoRoute "/api/ws" "metrics-stream-contract" "src/JitML/Web/Contracts.hs"
  , DemoRoute "/api/ws/training" "training-stream-contract" "src/JitML/Web/Contracts.hs"
  , DemoRoute "/api/ws/rl" "rl-stream-contract" "src/JitML/Web/Contracts.hs"
  , DemoRoute "/api/ws/tune" "tune-stream-contract" "src/JitML/Web/Contracts.hs"
  ]

renderBundleManifest :: Text
renderBundleManifest =
  Text.unlines $
    [ "assets:"
    ]
      <> fmap renderAsset bundleAssets
      <> [ "panels:"
         ]
      <> fmap renderPanel panelSurfaces
 where
  renderAsset asset =
    "- " <> Text.pack (bundleAssetPath asset) <> " <- " <> Text.pack (bundleAssetSource asset)

  renderPanel panel =
    "- " <> panelName panel <> " " <> panelEndpoint panel <> " (" <> panelPurpose panel <> ")"

renderDemoRouteManifest :: Text
renderDemoRouteManifest =
  Text.unlines $
    [ "demo-routes:"
    ]
      <> fmap renderRoute demoRoutes
 where
  renderRoute route =
    "- "
      <> demoRoutePath route
      <> " "
      <> demoRouteSurface route
      <> " <- "
      <> demoRouteSource route
