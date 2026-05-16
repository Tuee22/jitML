{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.Schema
  ( RlAlgorithmSchema (..)
  , RlCatalogSchema (..)
  , expectedRlCatalogSchema
  , loadRlCatalogSchema
  , rlCatalogMismatches
  , rlSchemaPath
  , validateRlCatalogSchema
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Dhall qualified
import System.FilePath ((</>))

import JitML.RL.Algorithms qualified as Algorithms

data RlAlgorithmSchema = RlAlgorithmSchema
  { schemaAlgorithmName :: Text
  , schemaAlgorithmFamily :: Text
  , schemaAlgorithmReplayBased :: Bool
  }
  deriving stock (Eq, Show)

newtype RlCatalogSchema = RlCatalogSchema
  { schemaAlgorithms :: [RlAlgorithmSchema]
  }
  deriving stock (Eq, Show)

rlSchemaPath :: FilePath
rlSchemaPath = "dhall/rl/Schema.dhall"

expectedRlCatalogSchema :: RlCatalogSchema
expectedRlCatalogSchema =
  RlCatalogSchema
    { schemaAlgorithms =
        fmap
          ( \algorithm ->
              RlAlgorithmSchema
                { schemaAlgorithmName = Algorithms.algorithmName algorithm
                , schemaAlgorithmFamily = Text.pack (show (Algorithms.algorithmFamily algorithm))
                , schemaAlgorithmReplayBased = Algorithms.algorithmReplayBased algorithm
                }
          )
          Algorithms.algorithmCatalog
    }

loadRlCatalogSchema :: FilePath -> IO RlCatalogSchema
loadRlCatalogSchema repoRoot =
  Dhall.inputFile rlCatalogDecoder (repoRoot </> rlSchemaPath)

validateRlCatalogSchema :: RlCatalogSchema -> Either [Text] ()
validateRlCatalogSchema catalog =
  case rlCatalogMismatches catalog of
    [] -> Right ()
    mismatches -> Left mismatches

rlCatalogMismatches :: RlCatalogSchema -> [Text]
rlCatalogMismatches actual =
  [ "algorithms mismatch: expected ["
      <> renderAlgorithms expected
      <> "], got ["
      <> renderAlgorithms found
      <> "]"
  | let expected = schemaAlgorithms expectedRlCatalogSchema
        found = schemaAlgorithms actual
  , expected /= found
  ]

rlCatalogDecoder :: Dhall.Decoder RlCatalogSchema
rlCatalogDecoder =
  Dhall.record $
    RlCatalogSchema
      <$> Dhall.field "algorithms" (Dhall.list rlAlgorithmDecoder)

rlAlgorithmDecoder :: Dhall.Decoder RlAlgorithmSchema
rlAlgorithmDecoder =
  Dhall.record $
    RlAlgorithmSchema
      <$> Dhall.field "name" Dhall.strictText
      <*> Dhall.field "family" Dhall.strictText
      <*> Dhall.field "replayBased" Dhall.bool

renderAlgorithms :: [RlAlgorithmSchema] -> Text
renderAlgorithms =
  Text.intercalate ", " . fmap renderAlgorithm

renderAlgorithm :: RlAlgorithmSchema -> Text
renderAlgorithm algorithm =
  schemaAlgorithmName algorithm
    <> ":"
    <> schemaAlgorithmFamily algorithm
    <> ":"
    <> if schemaAlgorithmReplayBased algorithm then "replay" else "no-replay"
