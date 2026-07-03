module JitML.RL.EpisodeEnvelope
  ( SimulatedEpisode (..)
  , SimulatedFrame (..)
  )
where

import Data.Text (Text)

data SimulatedEpisode = SimulatedEpisode
  { simEpisodeIndex :: Int
  , simEpisodeSteps :: Int
  , simEpisodeReward :: Double
  , simEpisodeDone :: Bool
  , simEpisodeFrames :: [SimulatedFrame]
  }
  deriving stock (Eq, Show)

data SimulatedFrame = SimulatedFrame
  { simFrameEpisodeIndex :: Int
  , simFrameStepIndex :: Int
  , simFrameAction :: Int
  , simFrameReward :: Double
  , simFrameDone :: Bool
  , simFrameObservation :: [Double]
  , simFrameNextObservation :: [Double]
  , simFrameActionProbabilities :: [Double]
  , simFrameCaption :: Text
  }
  deriving stock (Eq, Show)
