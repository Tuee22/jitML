module Support.DeterministicStep
  ( deterministicStep
  )
where

import Data.Text qualified as Text

import JitML.RL.Environments (EnvStep (..), RLEnvironment (..))

deterministicStep :: RLEnvironment -> Int -> Int -> EnvStep
deterministicStep environment seed action =
  EnvStep
    { stepObservationHash = observationHash
    , stepReward = reward
    , stepDone = observationHash `mod` 17 == 0
    }
 where
  observationHash =
    (seed * 1103515245 + action * 97 + environmentActionCount environment) `mod` 65521
  reward =
    fromIntegral (observationHash `mod` 100) / 100.0
      + fromIntegral (Text.length (environmentName environment)) / 1000.0
