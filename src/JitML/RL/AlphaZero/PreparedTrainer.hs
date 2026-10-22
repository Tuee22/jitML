{-# LANGUAGE OverloadedStrings #-}

-- | Lower initialization data and single-use continuation for the unchanged
-- policy/value generation loop. No producer, durability or qualification claim.
module JitML.RL.AlphaZero.PreparedTrainer
  ( canonicalAlphaZeroHiddenUnits
  , PreparedAlphaZero
  , AlphaZeroPreparedSnapshot
  , prepareAlphaZeroWithDevice
  , preparedAlphaZeroSnapshot
  , continuePreparedAlphaZeroRaw
  , alphaZeroPreparedGame
  , alphaZeroPreparedInitialState
  , alphaZeroPreparedInitialNet
  , alphaZeroPreparedInitialAdam
  , alphaZeroPreparedHiddenUnits
  , alphaZeroPreparedSeed
  , alphaZeroPreparedGenerationTarget
  , alphaZeroPreparedGames
  , alphaZeroPreparedSimulations
  , alphaZeroPreparedMaxPlies
  , alphaZeroPreparedUpdates
  , trainAlphaZeroGenerationsWithDevice
  , AlphaZeroTrainObservation
  , trainAlphaZeroGenerationsWithDeviceRaw
  , alphaZeroObservationLegacyResult
  , alphaZeroObservedOptimizerApplicationDelta
  , alphaZeroObservedInitialState
  , alphaZeroObservedInitialNet
  , alphaZeroObservedInitialAdam
  , alphaZeroObservedFinalNet
  , alphaZeroObservedFinalAdam
  , alphaZeroObservedSamples
  , alphaZeroObservedGenerationCount
  , alphaZeroObservedGenerationTarget
  , alphaZeroObservedGames
  , alphaZeroObservedSimulations
  , alphaZeroObservedMaxPlies
  , alphaZeroObservedUpdates
  , alphaZeroObservedSeed
  ) where

import Data.Text (Text)
import JitML.Execution.SingleUse qualified as SingleUse
import JitML.Numerics.Mlp (AdamState (..))
import JitML.Numerics.MlpDevice (MlpDevice)
import JitML.RL.AlphaZero qualified as AlphaZero
import JitML.RL.AlphaZero.PolicyValueNet qualified as PolicyValueNet

-- | Shared numerical architecture value only; no canonical/producer authority.
canonicalAlphaZeroHiddenUnits :: Int
canonicalAlphaZeroHiddenUnits = 16

-- Fields remain lazy to preserve the legacy loop's zero-generation behavior.
data AlphaZeroPreparedSnapshot = AlphaZeroPreparedSnapshot
  { internalAlphaZeroGame :: Text
  , internalAlphaZeroInitialState :: AlphaZero.GameState
  , internalAlphaZeroInitialNet :: PolicyValueNet.PolicyValueNet
  , internalAlphaZeroInitialAdam :: AdamState
  , internalAlphaZeroHiddenUnits :: Int
  , internalAlphaZeroSeed :: Int
  , internalAlphaZeroGenerationTarget :: Int
  , internalAlphaZeroGames :: Int
  , internalAlphaZeroSimulations :: Int
  , internalAlphaZeroMaxPlies :: Int
  , internalAlphaZeroUpdates :: Int
  }
  deriving stock (Eq, Show)

data PreparedAlphaZero
  = PreparedAlphaZero
      AlphaZeroPreparedSnapshot
      SingleUse.SingleUse
      (IO (Either Text AlphaZeroTrainObservation))

preparedAlphaZeroSnapshot :: PreparedAlphaZero -> AlphaZeroPreparedSnapshot
preparedAlphaZeroSnapshot (PreparedAlphaZero snapshot _ _) = snapshot

continuePreparedAlphaZeroRaw :: PreparedAlphaZero -> IO (Either Text AlphaZeroTrainObservation)
continuePreparedAlphaZeroRaw (PreparedAlphaZero _ guard action) = do
  consumed <- SingleUse.tryConsumeSingleUse guard
  if consumed then action else pure (Left "prepared AlphaZero continuation has already been consumed")

-- | Initializes the actual recipe-owned game/network/Adam, not caller-supplied
-- state. Values are recorded data, not canonical-row or process admission.
prepareAlphaZeroWithDevice
  :: MlpDevice -> Text -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> IO PreparedAlphaZero
prepareAlphaZeroWithDevice device game hidden seed generationTarget games sims maxPlies updates = do
  let initialState = AlphaZero.initialStateFor game
      net0 =
        PolicyValueNet.initPolicyValueNet
          (AlphaZero.observationSizeFor game)
          (AlphaZero.actionCountFor game)
          hidden
          seed
      adam0 = PolicyValueNet.initAdamFor net0
      snapshot =
        AlphaZeroPreparedSnapshot
          game
          initialState
          net0
          adam0
          hidden
          seed
          generationTarget
          games
          sims
          maxPlies
          updates
  guard <- SingleUse.newSingleUse
  pure
    ( PreparedAlphaZero
        snapshot
        guard
        ( trainAlphaZeroGenerationsWithDeviceRaw
            device
            initialState
            net0
            adam0
            generationTarget
            games
            sims
            maxPlies
            updates
            seed
        )
    )

alphaZeroPreparedGame :: AlphaZeroPreparedSnapshot -> Text
alphaZeroPreparedGame = internalAlphaZeroGame

alphaZeroPreparedInitialState :: AlphaZeroPreparedSnapshot -> AlphaZero.GameState
alphaZeroPreparedInitialState = internalAlphaZeroInitialState

alphaZeroPreparedInitialNet :: AlphaZeroPreparedSnapshot -> PolicyValueNet.PolicyValueNet
alphaZeroPreparedInitialNet = internalAlphaZeroInitialNet

alphaZeroPreparedInitialAdam :: AlphaZeroPreparedSnapshot -> AdamState
alphaZeroPreparedInitialAdam = internalAlphaZeroInitialAdam

alphaZeroPreparedHiddenUnits :: AlphaZeroPreparedSnapshot -> Int
alphaZeroPreparedHiddenUnits = internalAlphaZeroHiddenUnits

alphaZeroPreparedSeed :: AlphaZeroPreparedSnapshot -> Int
alphaZeroPreparedSeed = internalAlphaZeroSeed

alphaZeroPreparedGenerationTarget :: AlphaZeroPreparedSnapshot -> Int
alphaZeroPreparedGenerationTarget = internalAlphaZeroGenerationTarget

alphaZeroPreparedGames :: AlphaZeroPreparedSnapshot -> Int
alphaZeroPreparedGames = internalAlphaZeroGames

alphaZeroPreparedSimulations :: AlphaZeroPreparedSnapshot -> Int
alphaZeroPreparedSimulations = internalAlphaZeroSimulations

alphaZeroPreparedMaxPlies :: AlphaZeroPreparedSnapshot -> Int
alphaZeroPreparedMaxPlies = internalAlphaZeroMaxPlies

alphaZeroPreparedUpdates :: AlphaZeroPreparedSnapshot -> Int
alphaZeroPreparedUpdates = internalAlphaZeroUpdates

-- | Data-only actual return from one generation loop. It is not producer
-- origin, a physical-work transcript, canonical admission or qualification.
-- Inputs are retained exactly; even the legacy compatibility caller may pass a
-- nonzero initial Adam. The raw optimizer difference is therefore an Integer,
-- without rounding, unsigned wrap or invented configured-work multiplication.
data AlphaZeroTrainObservation = AlphaZeroTrainObservation
  { internalAlphaZeroObservedInitialState :: AlphaZero.GameState
  , internalAlphaZeroObservedInitialNet :: PolicyValueNet.PolicyValueNet
  , internalAlphaZeroObservedInitialAdam :: AdamState
  , internalAlphaZeroObservedFinalNet :: PolicyValueNet.PolicyValueNet
  , internalAlphaZeroObservedFinalAdam :: AdamState
  , internalAlphaZeroObservedSamples :: [PolicyValueNet.PolicyValueTrainingSample]
  , internalAlphaZeroObservedGenerationCount :: Int
  , internalAlphaZeroObservedGenerationTarget :: Int
  , internalAlphaZeroObservedGames :: Int
  , internalAlphaZeroObservedSimulations :: Int
  , internalAlphaZeroObservedMaxPlies :: Int
  , internalAlphaZeroObservedUpdates :: Int
  , internalAlphaZeroObservedSeed :: Int
  }
  deriving stock (Eq, Show)

alphaZeroObservedInitialState :: AlphaZeroTrainObservation -> AlphaZero.GameState
alphaZeroObservedInitialState = internalAlphaZeroObservedInitialState

alphaZeroObservedInitialNet :: AlphaZeroTrainObservation -> PolicyValueNet.PolicyValueNet
alphaZeroObservedInitialNet = internalAlphaZeroObservedInitialNet

alphaZeroObservedInitialAdam :: AlphaZeroTrainObservation -> AdamState
alphaZeroObservedInitialAdam = internalAlphaZeroObservedInitialAdam

alphaZeroObservedFinalNet :: AlphaZeroTrainObservation -> PolicyValueNet.PolicyValueNet
alphaZeroObservedFinalNet = internalAlphaZeroObservedFinalNet

alphaZeroObservedFinalAdam :: AlphaZeroTrainObservation -> AdamState
alphaZeroObservedFinalAdam = internalAlphaZeroObservedFinalAdam

alphaZeroObservedSamples :: AlphaZeroTrainObservation -> [PolicyValueNet.PolicyValueTrainingSample]
alphaZeroObservedSamples = internalAlphaZeroObservedSamples

alphaZeroObservedGenerationCount :: AlphaZeroTrainObservation -> Int
alphaZeroObservedGenerationCount = internalAlphaZeroObservedGenerationCount

alphaZeroObservedGenerationTarget :: AlphaZeroTrainObservation -> Int
alphaZeroObservedGenerationTarget = internalAlphaZeroObservedGenerationTarget

alphaZeroObservedGames :: AlphaZeroTrainObservation -> Int
alphaZeroObservedGames = internalAlphaZeroObservedGames

alphaZeroObservedSimulations :: AlphaZeroTrainObservation -> Int
alphaZeroObservedSimulations = internalAlphaZeroObservedSimulations

alphaZeroObservedMaxPlies :: AlphaZeroTrainObservation -> Int
alphaZeroObservedMaxPlies = internalAlphaZeroObservedMaxPlies

alphaZeroObservedUpdates :: AlphaZeroTrainObservation -> Int
alphaZeroObservedUpdates = internalAlphaZeroObservedUpdates

alphaZeroObservedSeed :: AlphaZeroTrainObservation -> Int
alphaZeroObservedSeed = internalAlphaZeroObservedSeed

alphaZeroObservedOptimizerApplicationDelta :: AlphaZeroTrainObservation -> Integer
alphaZeroObservedOptimizerApplicationDelta observed =
  toInteger (adamStep_ (alphaZeroObservedFinalAdam observed))
    - toInteger (adamStep_ (alphaZeroObservedInitialAdam observed))

alphaZeroObservationLegacyResult
  :: AlphaZeroTrainObservation
  -> (PolicyValueNet.PolicyValueNet, [PolicyValueNet.PolicyValueTrainingSample], Int)
alphaZeroObservationLegacyResult observed =
  ( alphaZeroObservedFinalNet observed
  , alphaZeroObservedSamples observed
  , alphaZeroObservedGenerationCount observed
  )

-- The legacy API projects the one raw loop; there is no second generation
-- implementation. Its high publisher remains an unchanged thin delegate.
trainAlphaZeroGenerationsWithDevice
  :: MlpDevice
  -> AlphaZero.GameState
  -> PolicyValueNet.PolicyValueNet
  -> AdamState
  -> Int
  -> Int
  -> Int
  -> Int
  -> Int
  -> Int
  -> IO (Either Text (PolicyValueNet.PolicyValueNet, [PolicyValueNet.PolicyValueTrainingSample], Int))
trainAlphaZeroGenerationsWithDevice device initialState net0 adam0 generationTarget games sims maxPlies updates seed =
  fmap
    (fmap alphaZeroObservationLegacyResult)
    ( trainAlphaZeroGenerationsWithDeviceRaw
        device
        initialState
        net0
        adam0
        generationTarget
        games
        sims
        maxPlies
        updates
        seed
    )

-- Apart from the terminal constructor which retains actual lexical Adam and
-- inputs, the actual old generation-loop body is byte-identical.
trainAlphaZeroGenerationsWithDeviceRaw
  :: MlpDevice
  -> AlphaZero.GameState
  -> PolicyValueNet.PolicyValueNet
  -> AdamState
  -> Int
  -> Int
  -> Int
  -> Int
  -> Int
  -> Int
  -> IO (Either Text AlphaZeroTrainObservation)
trainAlphaZeroGenerationsWithDeviceRaw device initialState net0 adam0 generationTarget games sims maxPlies updates seed =
  go 0 net0 adam0 []
 where
  go generation net adam allSamples
    | generation >= generationTarget =
        pure
          ( Right
              ( AlphaZeroTrainObservation
                  initialState
                  net0
                  adam0
                  net
                  adam
                  allSamples
                  generation
                  generationTarget
                  games
                  sims
                  maxPlies
                  updates
                  seed
              )
          )
    | otherwise = do
        sampleResults <-
          traverse
            ( \gameIndex ->
                PolicyValueNet.generatePolicyValueSamplesWithDeviceFrom
                  initialState
                  device
                  net
                  (seed + generation * 7919 + gameIndex)
                  sims
                  maxPlies
            )
            [0 .. games - 1]
        case sequence sampleResults of
          Left err -> pure (Left err)
          Right batches -> do
            let generationSamples = concat batches
            trainedE <-
              PolicyValueNet.trainPolicyValueNetOnSamplesWithDevice
                device
                net
                adam
                1.0e-3
                updates
                generationSamples
            case trainedE of
              Left err -> pure (Left err)
              Right (trainedNet, trainedAdam) ->
                go (generation + 1) trainedNet trainedAdam (allSamples <> generationSamples)
