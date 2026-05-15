{-# LANGUAGE OverloadedStrings #-}

module JitML.Web.Bundle
  ( BundleAsset (..)
  , PanelSurface (..)
  , bundleAssets
  , panelSurfaces
  , renderBundleManifest
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

bundleAssets :: [BundleAsset]
bundleAssets =
  [ BundleAsset "web/dist/index.html" "web/src/Main.purs"
  , BundleAsset "web/dist/app.js" "web/src/Generated/Contracts.purs"
  ]

panelSurfaces :: [PanelSurface]
panelSurfaces =
  [ PanelSurface "mnist-live-inference" "/api/inference" "MNIST inference"
  , PanelSurface "image-upload" "/api/images" "CIFAR/ImageNet upload"
  , PanelSurface "connect4-human-vs-alphazero" "/api/connect4/move" "Connect 4 moves"
  , PanelSurface "rl-trajectory" "/api/ws" "RL trajectory stream"
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
