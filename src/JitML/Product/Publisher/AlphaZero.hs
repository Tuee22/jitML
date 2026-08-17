{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Product.Publisher.AlphaZero
  ( trainAndPublishAlphaZeroProductRow
  )
where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ask)
import Data.Maybe (listToMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU

import JitML.Env.Env (App)
import JitML.Numerics.Mlp (AdamState)
import JitML.Numerics.MlpDevice (MlpDevice (..), probeMlpDevice)
import JitML.Numerics.MlpDeviceSelect (rlDeviceForSubstrate)
import JitML.Plan.Plan
  ( RunKind (..)
  , quantityValue
  , runPlanExperimentId
  , runPlanSubstrate
  )
import JitML.Plan.Workload qualified as WorkloadPlan
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Product.Publisher.Audit
  ( ProductPublishResult
  , productArtifactPointer
  , validateProductCompletedTrainingPlanId
  )
import JitML.Product.Publisher.Common
  ( admitPublishedProductCheckpoint
  , bindProductScenarioCompletion
  , productPublishEligible
  , productPublishError
  , writeProductTextArtifact
  )
import JitML.Product.Publisher.Projection
  ( checkedPositiveWord64FromInt
  , checkedWord64Product
  , intPlanValue
  , productTrainingBudgetForProjection
  , projectedRunSeed
  , requireProjectedValue
  , validateProjectionRowAssociation
  )
import JitML.Product.Publisher.Runtime (ProductPublisherRuntime (..))
import JitML.RL.AlphaZero qualified as AlphaZero
import JitML.RL.AlphaZero.PolicyValueNet qualified as PolicyValueNet
import JitML.Training.Budget qualified as TrainingBudget

trainAndPublishAlphaZeroProductRow
  :: Maybe TrainingBudget.ProductScenarioInvocation
  -> ProductPublisherRuntime
  -> ProductMatrix.ProductRow 'ProductMatrix.Declared
  -> ProductMatrix.ProductProjection 'AlphaZeroSelfPlay
  -> App ProductPublishResult
trainAndPublishAlphaZeroProductRow invocation runtime row projection =
  case ( ProductMatrix.productProjectionDescriptor projection
       , ProductMatrix.productProjectionResolvedPlan projection
       ) of
    ( ProductMatrix.AlphaZeroProductDescriptor
        descriptorGame
        descriptorGames
        descriptorSims
        descriptorMaxPlies
        descriptorUpdates
        descriptorArenaGames
      , ProductMatrix.ResolvedAlphaZeroProductPlan plan
      ) -> do
        let runPlan = WorkloadPlan.alphaZeroPlanRunPlan plan
            game = WorkloadPlan.renderAlphaZeroGame (WorkloadPlan.alphaZeroPlanGame plan)
            generationTargetWord = quantityValue (WorkloadPlan.alphaZeroPlanGenerations plan)
            gamesWord = quantityValue (WorkloadPlan.alphaZeroPlanSelfPlayGames plan)
            simsWord = quantityValue (WorkloadPlan.alphaZeroPlanMctsSimulations plan)
            maxPliesWord = quantityValue (WorkloadPlan.alphaZeroPlanMaxPlies plan)
            updatesWord = quantityValue (WorkloadPlan.alphaZeroPlanUpdates plan)
            arenaGamesWord = quantityValue (WorkloadPlan.alphaZeroPlanArenaGames plan)
            seedWord = projectedRunSeed runPlan
            projectionValidation = do
              validateProjectionRowAssociation row projection
              requireProjectedValue "AlphaZero game" descriptorGame game
              requireProjectedValue "AlphaZero self-play games" descriptorGames gamesWord
              requireProjectedValue "AlphaZero simulations" descriptorSims simsWord
              requireProjectedValue "AlphaZero maximum plies" descriptorMaxPlies maxPliesWord
              requireProjectedValue "AlphaZero optimizer updates" descriptorUpdates updatesWord
              requireProjectedValue "AlphaZero arena games" descriptorArenaGames arenaGamesWord
              requireProjectedValue
                "AlphaZero PlanId"
                (ProductMatrix.productProjectionPlanId projection)
                (WorkloadPlan.alphaZeroPlanId plan)
              productTrainingBudgetForProjection
                projection
                TrainingBudget.AlphaZeroSelfPlayBudget
                generationTargetWord
                seedWord
        case projectionValidation of
          Left err -> pure (productPublishError projection err)
          Right budget -> do
            generationTarget <- intPlanValue "product AlphaZero generations" generationTargetWord
            games <- intPlanValue "product AlphaZero self-play games" gamesWord
            sims <- intPlanValue "product AlphaZero simulations" simsWord
            maxPlies <- intPlanValue "product AlphaZero maximum plies" maxPliesWord
            updates <- intPlanValue "product AlphaZero optimizer updates" updatesWord
            arenaGames <- intPlanValue "product AlphaZero arena games" arenaGamesWord
            seed <- intPlanValue "product AlphaZero seed" seedWord
            env <- ask
            let substrate = runPlanSubstrate runPlan
                device = rlDeviceForSubstrate substrate env
                initialState = AlphaZero.initialStateFor game
                observationSize = AlphaZero.observationSizeFor game
                actionCount = AlphaZero.actionCountFor game
                net0 = PolicyValueNet.initPolicyValueNet observationSize actionCount 16 seed
                adam0 = PolicyValueNet.initAdamFor net0
            probe <- liftIO (probeMlpDevice device)
            case probe of
              Left err ->
                pure (productPublishError projection ("AlphaZero substrate device unavailable: " <> err))
              Right () -> do
                generationResult <-
                  liftIO $
                    trainAlphaZeroGenerationsWithDevice
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
                case generationResult of
                  Left err -> pure (productPublishError projection ("AlphaZero self-play failed: " <> err))
                  Right (trainedNet, samples, generationCount)
                    | generationCount /= generationTarget ->
                        pure
                          ( productPublishError
                              projection
                              ( "AlphaZero executor completed "
                                  <> Text.pack (show generationCount)
                                  <> " generations; resolved budget requires "
                                  <> Text.pack (show generationTarget)
                              )
                          )
                    | null samples -> pure (productPublishError projection "AlphaZero self-play produced no samples")
                    | otherwise -> do
                        -- Recorded after self-play and arena evaluation
                        -- returned: the row attests the artifact the
                        -- policy/value updates executed through.
                        azWitnessE <- liftIO (mlpdExecutionWitness device)
                        let winRate =
                              PolicyValueNet.arenaWinRateAgainstUniformFrom
                                initialState
                                trainedNet
                                arenaGames
                                maxPlies
                                (seed + 7919)
                            experimentHash = runPlanExperimentId runPlan
                            completedGenerations = fromIntegral generationCount
                            checkpointStep = completedGenerations
                            metrics =
                              [ ("arena_win_rate", winRate)
                              , ("legal_move_rate", 1.0)
                              , ("mcts_simulations_per_move", fromIntegral sims)
                              , ("self_play_games", fromIntegral games)
                              , ("self_play_generations", fromIntegral generationCount)
                              , ("self_play_samples", fromIntegral (length samples))
                              ]
                            initialWeights = PolicyValueNet.policyValueNetToFlat net0
                            finalWeights = PolicyValueNet.policyValueNetToFlat trainedNet
                            sampleDigest = PolicyValueNet.policyValueTrainingSamplesSha256 samples
                            completedTraining = do
                              deviceWitness <- azWitnessE
                              updatesPerGeneration <-
                                checkedPositiveWord64FromInt
                                  "AlphaZero optimizer updates per generation"
                                  updates
                              optimizerUpdateCount <-
                                checkedWord64Product
                                  "AlphaZero optimizer update evidence"
                                  completedGenerations
                                  updatesPerGeneration
                              completed <-
                                publisherAlphaZeroCompletedTraining
                                  runtime
                                  (WorkloadPlan.alphaZeroPlanId plan)
                                  budget
                                  experimentHash
                                  completedGenerations
                                  optimizerUpdateCount
                                  sampleDigest
                                  metrics
                                  initialWeights
                                  finalWeights
                                  deviceWitness
                              validateProductCompletedTrainingPlanId projection completed
                              bindProductScenarioCompletion invocation projection completed
                        case completedTraining of
                          Left err -> pure (productPublishError projection err)
                          Right completed -> do
                            transcript <-
                              writeProductTextArtifact
                                runtime
                                experimentHash
                                "alphazero-transcript"
                                (renderAlphaZeroTranscriptArtifact experimentHash seed sims maxPlies samples)
                            stored <-
                              publisherWriteCompletedWeightCheckpoint
                                runtime
                                completed
                                experimentHash
                                ("alphazero-" <> game <> "-policy-value-weights")
                                checkpointStep
                                metrics
                                finalWeights
                                [productArtifactPointer transcript]
                            admission <-
                              admitPublishedProductCheckpoint runtime projection completed stored
                            pure $
                              case admission of
                                Left err ->
                                  productPublishError
                                    projection
                                    ("AlphaZero checkpoint storage succeeded but exact Store admission failed: " <> err)
                                Right admitted ->
                                  productPublishEligible
                                    projection
                                    admitted
                                    [transcript]
                                    "AlphaZero policy-value artifact and transcript stored and admitted"

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
  go 0 net0 adam0 []
 where
  go generation net adam allSamples
    | generation >= generationTarget =
        pure (Right (net, allSamples, generation))
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
{-# NOINLINE trainAlphaZeroGenerationsWithDevice #-}
{-# NOINLINE trainAndPublishAlphaZeroProductRow #-}
