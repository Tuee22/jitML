{-# LANGUAGE OverloadedStrings #-}

-- | Reflected catalog Dhall schema — the numerics and RL catalog @.dhall@
-- leaves emitted from the same Haskell catalog data their mirror decoders read
-- ('JitML.Numerics.Schema.expectedNumericsCatalog' /
-- 'JitML.RL.Schema.expectedRlCatalogSchema'), so the checked-in catalog leaves
-- cannot drift from the Haskell catalogs.
--
-- Unlike the daemon-config surfaces in 'JitML.Service.DhallSchema' (which reflect
-- a Dhall /type/ via 'Dhall.expected'), the catalog leaves are Dhall /values/ —
-- lists of layer/activation/optimizer names and algorithm records — so these are
-- emitted by rendering the catalog data to Dhall literal text. A
-- 'JitML.Service.DhallSchema.canonicalDhallType' parity check (unit test) asserts
-- /checked-in leaf ≡ emitted leaf/, complementing the existing decode-and-compare
-- mirror (which validates the reverse direction). The two aggregator
-- @dhall/{numerics,rl}/Schema.dhall@ records carry only file imports (no catalog
-- data) and stay hand-written.
module JitML.Service.CatalogSchema
  ( numericsCatalogSchemas
  , rlAlgorithmCatalogSchema
  , catalogSchemas
  , catalogFileSchemas
  , catalogGroup
  , renderDhallTextList
  , renderDhallAlgorithmList
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Numerics.Schema
  ( NumericsCatalog (..)
  , expectedNumericsCatalog
  )
import JitML.RL.Schema
  ( RlAlgorithmSchema (..)
  , RlCatalogSchema (..)
  , expectedRlCatalogSchema
  )

-- | The single source list: @(cli-name, checked-in leaf path, emitted Dhall)@,
-- one row per import-free catalog leaf. Derived entirely from the @expected*@
-- mirror data so emission, the decode-and-compare mirror, and the lint all read
-- one source of truth.
catalogLeafSchemas :: [(Text, FilePath, Text)]
catalogLeafSchemas =
  [ ("numerics.layers", "dhall/numerics/Layer.dhall", renderDhallTextList (schemaLayers numerics))
  ,
    ( "numerics.activations"
    , "dhall/numerics/Activation.dhall"
    , renderDhallTextList (schemaActivations numerics)
    )
  ,
    ( "numerics.spectral"
    , "dhall/numerics/SpectralOp.dhall"
    , renderDhallTextList (schemaSpectral numerics)
    )
  ,
    ( "numerics.optimizers"
    , "dhall/numerics/Optimizer.dhall"
    , renderDhallTextList (schemaOptimizers numerics)
    )
  ,
    ( "numerics.schedulers"
    , "dhall/numerics/Scheduler.dhall"
    , renderDhallTextList (schemaSchedulers numerics)
    )
  , ("numerics.losses", "dhall/numerics/Loss.dhall", renderDhallTextList (schemaLosses numerics))
  , ("rl.algorithms", "dhall/rl/Algorithm.dhall", rlAlgorithmCatalogSchema)
  ]
 where
  numerics = expectedNumericsCatalog

-- | The six numerics catalog leaves, keyed by CLI name.
numericsCatalogSchemas :: [(Text, Text)]
numericsCatalogSchemas =
  [(name, emitted) | (name, _, emitted) <- catalogLeafSchemas, "numerics." `Text.isPrefixOf` name]

-- | The RL algorithm catalog leaf (@dhall/rl/Algorithm.dhall@).
rlAlgorithmCatalogSchema :: Text
rlAlgorithmCatalogSchema = renderDhallAlgorithmList (schemaAlgorithms expectedRlCatalogSchema)

-- | Every emitted catalog leaf, keyed by CLI name.
catalogSchemas :: [(Text, Text)]
catalogSchemas = [(name, emitted) | (name, _, emitted) <- catalogLeafSchemas]

-- | The checked-in leaf file each emitted catalog maps to (for the parity test).
catalogFileSchemas :: [(FilePath, Text)]
catalogFileSchemas = [(path, emitted) | (_, path, emitted) <- catalogLeafSchemas]

-- | Resolve a @--catalog@ selector to a set of @(name, emitted)@ entries:
-- @numerics@, @rl@, or @all@. 'Nothing' for an unknown selector.
catalogGroup :: Text -> Maybe [(Text, Text)]
catalogGroup selector =
  case selector of
    "numerics" -> Just numericsCatalogSchemas
    "rl" -> Just [("rl.algorithms", rlAlgorithmCatalogSchema)]
    "all" -> Just catalogSchemas
    _ -> Nothing

-- | Render a Dhall list-of-Text literal in the checked-in catalog leaf format:
-- @[ "A"\n, "B"\n]@.
renderDhallTextList :: [Text] -> Text
renderDhallTextList items =
  case items of
    [] -> "[] : List Text\n"
    (firstItem : rest) ->
      Text.concat $
        ["[ ", quote firstItem, "\n"]
          <> concatMap (\item -> [", ", quote item, "\n"]) rest
          <> ["]\n"]
 where
  quote t = "\"" <> t <> "\""

-- | Render the RL algorithm catalog as a Dhall list of records, matching the
-- checked-in @dhall/rl/Algorithm.dhall@ row format.
renderDhallAlgorithmList :: [RlAlgorithmSchema] -> Text
renderDhallAlgorithmList algorithms =
  case algorithms of
    [] -> "[] : List { name : Text, family : Text, replayBased : Bool }\n"
    (firstAlgo : rest) ->
      Text.concat $
        ["[ ", renderAlgorithm firstAlgo, "\n"]
          <> concatMap (\algo -> [", ", renderAlgorithm algo, "\n"]) rest
          <> ["]\n"]

renderAlgorithm :: RlAlgorithmSchema -> Text
renderAlgorithm algorithm =
  Text.concat
    [ "{ name = \""
    , schemaAlgorithmName algorithm
    , "\", family = \""
    , schemaAlgorithmFamily algorithm
    , "\", replayBased = "
    , if schemaAlgorithmReplayBased algorithm then "True" else "False"
    , " }"
    ]
