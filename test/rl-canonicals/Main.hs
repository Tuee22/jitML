{-# LANGUAGE OverloadedStrings #-}

module Main where

import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

import JitML.Proto.Rl
  ( RlCommand (..)
  , StartRLRun (..)
  , StopRLRun (..)
  , parseRlCommand
  , renderRlCommand
  )
import JitML.RL.Algorithms (algorithmCatalog, algorithmName, deterministicTrajectory)
import JitML.RL.AlphaZero (gameMoves, selfPlayTranscript, selfPlayTranscriptFor)
import JitML.RL.Buffer (bufferSize)
import JitML.RL.Environments
  ( canonicalEnvironments
  , environmentActionCount
  , environmentObservationSize
  )
import JitML.RL.Loop
  ( RLConfig (..)
  , RLLoop (..)
  , defaultRLConfig
  , resultBuffer
  , resultEpisodes
  , runRLLoop
  )
import JitML.RL.Policy (defaultPolicy)
import JitML.Substrate (Substrate (..))

main :: IO ()
main =
  defaultMain $
    testGroup
      "jitml-rl-canonicals"
      [ testCase "algorithm catalog covers PPO through AlphaZero" $ do
          let names = fmap algorithmName algorithmCatalog
          assertContains "PPO" names
          assertContains "SAC" names
          assertContains "HER" names
          assertContains "AlphaZero" names
      , testCase "trajectory generator is deterministic" $
          deterministicTrajectory "PPO" 42 @?= deterministicTrajectory "PPO" 42
      , testCase "PPO CartPole trajectory matches the golden fixture" $ do
          fixture <- Text.IO.readFile "test/golden/rl/ppo/cartpole/trajectory.txt"
          Text.lines fixture @?= fmap (Text.pack . show) (deterministicTrajectory "PPO" 42)
      , testCase "deterministic RL loop records rollout transitions in the replay buffer" $
          case (algorithmCatalog, canonicalEnvironments) of
            (algorithm : _, environment : _) -> do
              let policy =
                    defaultPolicy
                      "ppo-cartpole"
                      (environmentObservationSize environment)
                      (environmentActionCount environment)
                      LinuxCPU
                  config =
                    defaultRLConfig
                      { rlMaxEpisodes = 2
                      , rlMaxStepsPerEpisode = 8
                      , rlBufferCapacity = 32
                      }
                  loop = RLLoop algorithm policy environment config
                  first = runRLLoop loop
                  second = runRLLoop loop
              resultEpisodes first @?= resultEpisodes second
              assertBool "rollout transitions are recorded" (bufferSize (resultBuffer first) > 0)
            _ -> assertBool "missing RL catalog/environment fixture" False
      , testCase "AlphaZero self-play records legal Connect 4 columns" $
          mapM_
            (assertBool "column is legal" . all (\column -> column >= 0 && column < 7) . gameMoves)
            (selfPlayTranscript 3)
      , testCase "AlphaZero Connect 4 transcript matches golden fixture" $ do
          fixture <- Text.IO.readFile "test/golden/alphazero/connect4-transcript.txt"
          Text.lines fixture @?= fmap (Text.pack . show . gameMoves) (selfPlayTranscript 3)
      , testCase "AlphaZero Othello transcript matches golden fixture" $ do
          fixture <- Text.IO.readFile "test/golden/alphazero/othello-transcript.txt"
          Text.lines fixture
            @?= fmap (Text.pack . show . gameMoves) (selfPlayTranscriptFor "othello" 3)
      , testCase "AlphaZero Hex transcript matches golden fixture" $ do
          fixture <- Text.IO.readFile "test/golden/alphazero/hex-transcript.txt"
          Text.lines fixture
            @?= fmap (Text.pack . show . gameMoves) (selfPlayTranscriptFor "hex" 3)
      , testCase "AlphaZero Gomoku transcript matches golden fixture" $ do
          fixture <- Text.IO.readFile "test/golden/alphazero/gomoku-transcript.txt"
          Text.lines fixture
            @?= fmap (Text.pack . show . gameMoves) (selfPlayTranscriptFor "gomoku" 3)
      , testCase "RL command envelopes parse after render" $ do
          let start =
                RlStart
                  StartRLRun
                    { srlExperimentHash = "sha256:cartpole"
                    , srlAlgorithm = "PPO"
                    , srlEnvironment = "cartpole"
                    , srlSubstrate = LinuxCUDA
                    , srlSeed = 42
                    , srlMaxSteps = 1024
                    , srlEvalEpisodes = 8
                    }
              stop =
                RlStop
                  StopRLRun
                    { srStopExperimentHash = "sha256:cartpole"
                    , srStopDrain = False
                    }
          parseRlCommand (renderRlCommand start) @?= Just start
          parseRlCommand (renderRlCommand stop) @?= Just stop
          parseRlCommand "kind: UnknownRlCommand\n" @?= Nothing
      ]

assertContains :: Text -> [Text] -> IO ()
assertContains value values =
  assertBool ("missing " <> show value) (value `elem` values)
