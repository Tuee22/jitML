{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.Algorithms
  ( AlgorithmFamily (..)
  , RLAlgorithm (..)
  , algorithmCatalog
  , deterministicTrajectory
  , renderAlgorithmCatalog
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

data AlgorithmFamily
  = OnPolicy
  | OffPolicy
  | Specialized
  | SelfPlay
  deriving stock (Eq, Show)

data RLAlgorithm = RLAlgorithm
  { algorithmName :: Text
  , algorithmFamily :: AlgorithmFamily
  , algorithmReplayBased :: Bool
  }
  deriving stock (Eq, Show)

algorithmCatalog :: [RLAlgorithm]
algorithmCatalog =
  [ RLAlgorithm "PPO" OnPolicy False
  , RLAlgorithm "A2C" OnPolicy False
  , RLAlgorithm "TRPO" OnPolicy False
  , RLAlgorithm "MaskablePPO" OnPolicy False
  , RLAlgorithm "RecurrentPPO" OnPolicy False
  , RLAlgorithm "DQN" OffPolicy True
  , RLAlgorithm "QR-DQN" OffPolicy True
  , RLAlgorithm "DDPG" OffPolicy True
  , RLAlgorithm "TD3" OffPolicy True
  , RLAlgorithm "SAC" OffPolicy True
  , RLAlgorithm "CrossQ" Specialized True
  , RLAlgorithm "TQC" Specialized True
  , RLAlgorithm "ARS" Specialized False
  , RLAlgorithm "HER" Specialized True
  , RLAlgorithm "AlphaZero" SelfPlay False
  ]

deterministicTrajectory :: Text -> Int -> [Int]
deterministicTrajectory algorithm seed =
  take 8 $
    iterate (\value -> (value * 1103515245 + 12345 + Text.length algorithm) `mod` 9973) seed

renderAlgorithmCatalog :: Text
renderAlgorithmCatalog =
  Text.unlines $
    [ "| Algorithm | Family | Replay |"
    , "|-----------|--------|--------|"
    ]
      <> fmap renderRow algorithmCatalog
 where
  renderRow algorithm =
    "| `"
      <> algorithmName algorithm
      <> "` | "
      <> Text.pack (show (algorithmFamily algorithm))
      <> " | "
      <> if algorithmReplayBased algorithm then "yes |" else "no |"
