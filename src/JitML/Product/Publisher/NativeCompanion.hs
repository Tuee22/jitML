{-# LANGUAGE OverloadedStrings #-}

-- | The existing trajectory/transcript rendering only. These pure DATA
-- functions own no publisher, store, trainer or native-serving capability.
module JitML.Product.Publisher.NativeCompanion
  ( renderRlTrajectoryArtifact
  , renderAlphaZeroTranscriptArtifact
  ) where

import Data.Maybe (listToMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU

import JitML.RL.AlphaZero qualified as AlphaZero
import JitML.RL.AlphaZero.PolicyValueNet qualified as PolicyValueNet
import JitML.RL.EpisodeEnvelope qualified as EpisodeEnvelope

renderRlTrajectoryArtifact
  :: Text
  -> Text
  -> Text
  -> Int
  -> [EpisodeEnvelope.SimulatedEpisode]
  -> Text
renderRlTrajectoryArtifact experimentHash environment trainer seed episodes =
  Text.unlines $
    [ "kind: rl-trajectory-v1"
    , "experiment-hash: " <> experimentHash
    , "environment: " <> environment
    , "trainer: " <> trainer
    , "seed: " <> Text.pack (show seed)
    , "episodes: " <> Text.pack (show (length episodes))
    ]
      <> concatMap renderEpisode episodes
 where
  renderEpisode episode =
    [ "episode: " <> Text.pack (show (EpisodeEnvelope.simEpisodeIndex episode))
    , "episode-steps: " <> Text.pack (show (EpisodeEnvelope.simEpisodeSteps episode))
    , "episode-reward: " <> Text.pack (show (EpisodeEnvelope.simEpisodeReward episode))
    , "episode-done: " <> Text.pack (show (EpisodeEnvelope.simEpisodeDone episode))
    , "episode-frame-count: "
        <> Text.pack (show (length (EpisodeEnvelope.simEpisodeFrames episode)))
    ]
      <> concatMap renderFrame (EpisodeEnvelope.simEpisodeFrames episode)
  renderFrame frame =
    [ "frame-episode: " <> Text.pack (show (EpisodeEnvelope.simFrameEpisodeIndex frame))
    , "frame-step: " <> Text.pack (show (EpisodeEnvelope.simFrameStepIndex frame))
    , "frame-action: " <> Text.pack (show (EpisodeEnvelope.simFrameAction frame))
    , "frame-reward: " <> Text.pack (show (EpisodeEnvelope.simFrameReward frame))
    , "frame-done: " <> Text.pack (show (EpisodeEnvelope.simFrameDone frame))
    , "frame-observation: " <> Text.pack (show (EpisodeEnvelope.simFrameObservation frame))
    , "frame-next-observation: "
        <> Text.pack (show (EpisodeEnvelope.simFrameNextObservation frame))
    , "frame-action-probabilities: "
        <> Text.pack (show (EpisodeEnvelope.simFrameActionProbabilities frame))
    , "frame-caption: " <> EpisodeEnvelope.simFrameCaption frame
    ]
{-# NOINLINE renderRlTrajectoryArtifact #-}

renderAlphaZeroTranscriptArtifact
  :: Text
  -> Int
  -> Int
  -> Int
  -> [PolicyValueNet.PolicyValueTrainingSample]
  -> Text
renderAlphaZeroTranscriptArtifact experimentHash seed sims maxPlies samples =
  Text.unlines $
    [ "kind: alphazero-transcript-v1"
    , "experiment-hash: " <> experimentHash
    , "game: " <> maybe "unknown" (AlphaZero.gameName . PolicyValueNet.sampleState) (listToMaybe samples)
    , "seed: " <> Text.pack (show seed)
    , "mcts-sims: " <> Text.pack (show sims)
    , "max-plies: " <> Text.pack (show maxPlies)
    , "samples: " <> Text.pack (show (length samples))
    ]
      <> concatMap renderSample (zip [0 :: Int ..] samples)
 where
  renderSample (index, sample) =
    [ "sample: " <> Text.pack (show index)
    , "state: " <> Text.pack (show (PolicyValueNet.sampleState sample))
    , "visit-distribution: "
        <> Text.pack (show (VU.toList (PolicyValueNet.sampleVisitDist sample)))
    , "outcome: " <> Text.pack (show (PolicyValueNet.sampleOutcome sample))
    ]
{-# NOINLINE renderAlphaZeroTranscriptArtifact #-}
