{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.Algorithms.Common
  ( AlgorithmHyperparameter (..)
  , AlgorithmModule (..)
  , AlgorithmUpdateContract (..)
  , hyperparameterRow
  , renderAlgorithmModule
  , renderHyperparameters
  , updateContract
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.RL.Algorithms (AlgorithmFamily (..), RLAlgorithm (..))

data AlgorithmHyperparameter = AlgorithmHyperparameter
  { hyperName :: Text
  , hyperValue :: Text
  , hyperDeterministicOnly :: Bool
  }
  deriving stock (Eq, Show)

data AlgorithmModule = AlgorithmModule
  { moduleAlgorithm :: RLAlgorithm
  , moduleHyperparameters :: [AlgorithmHyperparameter]
  , moduleUpdateContract :: AlgorithmUpdateContract
  }

data AlgorithmUpdateContract = AlgorithmUpdateContract
  { updateIdentity :: Text
  , trainerEntryPoint :: Text
  , rolloutSurface :: Text
  , learnedArtifact :: Text
  , updateFeatures :: [Text]
  }
  deriving stock (Eq, Show)

hyperparameterRow :: Text -> Text -> Bool -> AlgorithmHyperparameter
hyperparameterRow = AlgorithmHyperparameter

updateContract :: Text -> Text -> Text -> Text -> [Text] -> AlgorithmUpdateContract
updateContract = AlgorithmUpdateContract

renderHyperparameters :: [AlgorithmHyperparameter] -> Text
renderHyperparameters hyperparameters =
  Text.unlines
    [ "  - " <> hyperName h <> " = " <> hyperValue h <> deterministicMarker h
    | h <- hyperparameters
    ]
 where
  deterministicMarker h
    | hyperDeterministicOnly h = "  [deterministic-only]"
    | otherwise = ""

renderAlgorithmModule :: AlgorithmModule -> Text
renderAlgorithmModule m =
  Text.unlines
    [ "algorithm: " <> algorithmName (moduleAlgorithm m)
    , "family: " <> renderFamily (algorithmFamily (moduleAlgorithm m))
    , "replay-based: " <> if algorithmReplayBased (moduleAlgorithm m) then "yes" else "no"
    , "update-identity: " <> updateIdentity (moduleUpdateContract m)
    , "trainer-entrypoint: " <> trainerEntryPoint (moduleUpdateContract m)
    , "rollout-surface: " <> rolloutSurface (moduleUpdateContract m)
    , "learned-artifact: " <> learnedArtifact (moduleUpdateContract m)
    , "update-features:"
    , renderUpdateFeatures (updateFeatures (moduleUpdateContract m))
    , "hyperparameters:"
    , renderHyperparameters (moduleHyperparameters m)
    ]
 where
  renderFamily OnPolicy = "on-policy"
  renderFamily OffPolicy = "off-policy"
  renderFamily Specialized = "specialised"
  renderFamily SelfPlay = "self-play"
  renderUpdateFeatures features =
    Text.unlines ["  - " <> feature | feature <- features]
