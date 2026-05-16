{-# LANGUAGE OverloadedStrings #-}

module JitML.Numerics.Schema
  ( NumericsCatalog (..)
  , expectedNumericsCatalog
  , loadNumericsCatalog
  , numericsCatalogMismatches
  , numericsSchemaPath
  , validateNumericsCatalog
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Dhall qualified
import System.FilePath ((</>))

import JitML.Numerics.Catalog qualified as Catalog

data NumericsCatalog = NumericsCatalog
  { schemaLayers :: [Text]
  , schemaActivations :: [Text]
  , schemaSpectral :: [Text]
  , schemaOptimizers :: [Text]
  , schemaSchedulers :: [Text]
  , schemaLosses :: [Text]
  }
  deriving stock (Eq, Show)

numericsSchemaPath :: FilePath
numericsSchemaPath = "dhall/numerics/Schema.dhall"

expectedNumericsCatalog :: NumericsCatalog
expectedNumericsCatalog =
  NumericsCatalog
    { schemaLayers = showNames Catalog.layerCatalog
    , schemaActivations = showNames Catalog.activationCatalog
    , schemaSpectral = showNames Catalog.spectralCatalog
    , schemaOptimizers = showNames Catalog.optimizerCatalog
    , schemaSchedulers = showNames Catalog.schedulerCatalog
    , schemaLosses = showNames Catalog.lossCatalog
    }

loadNumericsCatalog :: FilePath -> IO NumericsCatalog
loadNumericsCatalog repoRoot =
  Dhall.inputFile numericsCatalogDecoder (repoRoot </> numericsSchemaPath)

validateNumericsCatalog :: NumericsCatalog -> Either [Text] ()
validateNumericsCatalog catalog =
  case numericsCatalogMismatches catalog of
    [] -> Right ()
    mismatches -> Left mismatches

numericsCatalogMismatches :: NumericsCatalog -> [Text]
numericsCatalogMismatches actual =
  concat
    [ checkList "layers" (schemaLayers expectedNumericsCatalog) (schemaLayers actual)
    , checkList "activations" (schemaActivations expectedNumericsCatalog) (schemaActivations actual)
    , checkList "spectral" (schemaSpectral expectedNumericsCatalog) (schemaSpectral actual)
    , checkList "optimizers" (schemaOptimizers expectedNumericsCatalog) (schemaOptimizers actual)
    , checkList "schedulers" (schemaSchedulers expectedNumericsCatalog) (schemaSchedulers actual)
    , checkList "losses" (schemaLosses expectedNumericsCatalog) (schemaLosses actual)
    ]

numericsCatalogDecoder :: Dhall.Decoder NumericsCatalog
numericsCatalogDecoder =
  Dhall.record $
    NumericsCatalog
      <$> Dhall.field "layers" textListDecoder
      <*> Dhall.field "activations" textListDecoder
      <*> Dhall.field "spectral" textListDecoder
      <*> Dhall.field "optimizers" textListDecoder
      <*> Dhall.field "schedulers" textListDecoder
      <*> Dhall.field "losses" textListDecoder

textListDecoder :: Dhall.Decoder [Text]
textListDecoder = Dhall.list Dhall.strictText

checkList :: Text -> [Text] -> [Text] -> [Text]
checkList label expected actual =
  [ label <> " mismatch: expected [" <> renderList expected <> "], got [" <> renderList actual <> "]"
  | expected /= actual
  ]

renderList :: [Text] -> Text
renderList = Text.intercalate ", "

showNames :: (Show value) => [value] -> [Text]
showNames = fmap (Text.pack . show)
