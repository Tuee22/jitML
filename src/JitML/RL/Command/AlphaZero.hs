{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.Command.AlphaZero
  ( runAlphaZeroSelfPlay
  )
where

import Control.Monad (unless, when)
import Control.Monad.Reader (ask, liftIO)
import Data.Foldable (for_)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Maybe (isNothing, listToMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word32, Word64)

import JitML.AppError.AppError (AppError (..))
import JitML.CLI.Output (exitWithError, writeText)
import JitML.CLI.Parser (ParsedOption)
import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Checkpoint.Store qualified as CheckpointStore
import JitML.Checkpoint.Writer qualified as CheckpointWriter
import JitML.Env.Env (App)
import JitML.Experiment.Overrides qualified as Overrides
import JitML.Experiment.Product qualified as ProductExperiment
import JitML.Numerics.Mlp (AdamState)
import JitML.Numerics.MlpDevice (MlpDevice (..), probeMlpDevice)
import JitML.Numerics.MlpDeviceSelect (rlDeviceForSubstrate)
import JitML.Plan.Command qualified as PlanCommand
import JitML.Plan.Plan
  ( planIdText
  , quantityValue
  , runPlanExperimentId
  , runPlanSeeds
  , runPlanSubstrate
  , seedCohortValues
  )
import JitML.Plan.Workload qualified as WorkloadPlan
import JitML.Product.Completion qualified as ProductCompletion
import JitML.Proto.Rl qualified as ProtoRl
import JitML.RL.AlphaZero qualified as AlphaZero
import JitML.RL.AlphaZero.PolicyValueNet qualified as PolicyValueNet
import JitML.RL.Command.Options
  ( mountedRunConfigDecodeError
  , rejectMissingMountedRunConfigInKubernetes
  , requireUserIntOptionAtLeast
  , selectedValue
  )
import JitML.RL.Command.Types
  ( RlCommandRuntime (..)
  , RlWorkerServices (..)
  )
import JitML.Service.RunConfig qualified as RunConfig
import JitML.Substrate (Substrate, renderSubstrate)

runAlphaZeroSelfPlay :: RlCommandRuntime -> FilePath -> [ParsedOption] -> App ()
runAlphaZeroSelfPlay runtime runConfigPath parsedOptions = do
  mounted <- liftIO (RunConfig.tryLoadAlphaZeroRunConfig runConfigPath)
  case mounted of
    RunConfig.RunConfigLoaded config ->
      case RunConfig.alphaZeroPlanFromRunConfig config of
        Left err ->
          exitWithError (mountedRunConfigDecodeError runConfigPath "AlphaZeroRunConfig" err)
        Right plan -> runResolvedAlphaZeroPlan runtime True plan
    RunConfig.RunConfigDecodeFailed err ->
      exitWithError (mountedRunConfigDecodeError runConfigPath "AlphaZeroRunConfig" err)
    RunConfig.RunConfigMissing -> do
      rejectMissingMountedRunConfigInKubernetes runConfigPath "AlphaZeroRunConfig"
      plan <- prepareLocalAlphaZeroPlan runtime parsedOptions
      runResolvedAlphaZeroPlan runtime False plan
{-# NOINLINE runAlphaZeroSelfPlay #-}

prepareLocalAlphaZeroPlan :: RlCommandRuntime -> [ParsedOption] -> App WorkloadPlan.AlphaZeroPlan
prepareLocalAlphaZeroPlan runtime parsedOptions = do
  overrides <- case Overrides.parseExperimentOverrides parsedOptions of
    Left err -> exitWithError (InvalidConfig (Overrides.renderOverrideError err))
    Right ovr -> pure ovr
  baseSubstrate <- rlCommandWorkerSubstrateBase runtime
  generations <- requireUserIntOptionAtLeast "generations" 1 1 parsedOptions
  games <- requireUserIntOptionAtLeast "games" 2 1 parsedOptions
  sims <- requireUserIntOptionAtLeast "sims" 4 1 parsedOptions
  maxPlies <- requireUserIntOptionAtLeast "max-plies" 6 1 parsedOptions
  updates <- requireUserIntOptionAtLeast "updates" 1 1 parsedOptions
  arenaGames <- requireUserIntOptionAtLeast "arena-games" 4 1 parsedOptions
  let gameName = ProductExperiment.normalizeAlphaZeroGame (selectedValue "game" "connect4" parsedOptions)
      canonicalGameNames = fmap AlphaZero.pigName AlphaZero.canonicalGames
  unless (gameName `elem` canonicalGameNames) $
    exitWithError
      ( InvalidConfig
          ( "unknown AlphaZero game: "
              <> gameName
              <> " (expected one of "
              <> Text.intercalate ", " canonicalGameNames
              <> ")"
          )
      )
  generationsWord <- word32PlanValue "AlphaZero generations" (toInteger generations)
  gamesWord <- word32PlanValue "AlphaZero self-play games" (toInteger games)
  simsWord <- word32PlanValue "AlphaZero MCTS simulations" (toInteger sims)
  maxPliesWord <- word32PlanValue "AlphaZero max plies" (toInteger maxPlies)
  updatesWord <- word32PlanValue "AlphaZero optimizer updates" (toInteger updates)
  arenaGamesWord <- word32PlanValue "AlphaZero arena games" (toInteger arenaGames)
  let substrate = Overrides.overrideSubstrate overrides baseSubstrate
      seed = Overrides.overrideSeed overrides 31
      experimentHash =
        Checkpoint.deriveExperimentHash
          "alphazero-self-play"
          ( Text.intercalate
              ":"
              [ renderSubstrate substrate
              , gameName
              , Text.pack (show generations)
              , Text.pack (show games)
              , Text.pack (show sims)
              , Text.pack (show maxPlies)
              , Text.pack (show updates)
              , Text.pack (show arenaGames)
              , Text.pack (show seed)
              ]
          )
      raw =
        ProtoRl.StartAlphaZeroRun
          { ProtoRl.sazSubstrate = substrate
          , ProtoRl.sazExperimentHash = experimentHash
          , ProtoRl.sazPlanId = ""
          , ProtoRl.sazResolvedPlan = ""
          , ProtoRl.sazGame = gameName
          , ProtoRl.sazGenerations = generationsWord
          , ProtoRl.sazSelfPlayGames = gamesWord
          , ProtoRl.sazMctsSimulationsPerMove = simsWord
          , ProtoRl.sazMaxPlies = maxPliesWord
          , ProtoRl.sazOptimizerUpdates = updatesWord
          , ProtoRl.sazArenaGames = arenaGamesWord
          , ProtoRl.sazSeed = seed
          }
  case PlanCommand.prepareStartAlphaZeroRun raw of
    Left err -> exitWithError (InvalidConfig ("AlphaZero plan refinement failed: " <> err))
    Right (_, plan) -> pure plan

runResolvedAlphaZeroPlan :: RlCommandRuntime -> Bool -> WorkloadPlan.AlphaZeroPlan -> App ()
runResolvedAlphaZeroPlan runtime requireLiveContext plan = do
  env <- ask
  generations <-
    intPlanValue "AlphaZero generations" (quantityValue (WorkloadPlan.alphaZeroPlanGenerations plan))
  games <-
    intPlanValue
      "AlphaZero self-play games"
      (quantityValue (WorkloadPlan.alphaZeroPlanSelfPlayGames plan))
  sims <-
    intPlanValue
      "AlphaZero MCTS simulations"
      (quantityValue (WorkloadPlan.alphaZeroPlanMctsSimulations plan))
  maxPlies <-
    intPlanValue "AlphaZero max plies" (quantityValue (WorkloadPlan.alphaZeroPlanMaxPlies plan))
  updates <-
    intPlanValue "AlphaZero optimizer updates" (quantityValue (WorkloadPlan.alphaZeroPlanUpdates plan))
  arenaGames <-
    intPlanValue "AlphaZero arena games" (quantityValue (WorkloadPlan.alphaZeroPlanArenaGames plan))
  seed <-
    intPlanValue
      "AlphaZero seed"
      (NonEmpty.head (seedCohortValues (runPlanSeeds (WorkloadPlan.alphaZeroPlanRunPlan plan))))
  contextMaybe <- rlCommandAlphaZeroWorkerServices runtime
  when (requireLiveContext && isNothing contextMaybe) $
    exitWithError (InvalidConfig "resolved AlphaZero worker requires mounted service configuration")
  let substrate = runPlanSubstrate (WorkloadPlan.alphaZeroPlanRunPlan plan)
      experimentHash = runPlanExperimentId (WorkloadPlan.alphaZeroPlanRunPlan plan)
      planId = planIdText (WorkloadPlan.alphaZeroPlanId plan)
      gameName = WorkloadPlan.renderAlphaZeroGame (WorkloadPlan.alphaZeroPlanGame plan)
      device = rlDeviceForSubstrate substrate env
      initialState = AlphaZero.initialStateFor gameName
      observationSize = AlphaZero.observationSizeFor gameName
      actionCount = AlphaZero.actionCountFor gameName
      net0 = PolicyValueNet.initPolicyValueNet observationSize actionCount 16 seed
      adam0 = PolicyValueNet.initAdamFor net0
  for_ contextMaybe $ \context ->
    unless (rlWorkerServiceSubstrate context == substrate) $
      exitWithError
        ( InvalidConfig
            ( "resolved AlphaZero plan substrate "
                <> renderSubstrate substrate
                <> " does not match worker substrate "
                <> renderSubstrate (rlWorkerServiceSubstrate context)
            )
        )
  probe <- liftIO (probeMlpDevice device)
  case probe of
    Left err -> exitWithError (InvalidConfig ("AlphaZero substrate device unavailable: " <> err))
    Right () -> do
      (trainedNet, samples) <-
        trainResolvedAlphaZeroGenerations
          runtime
          contextMaybe
          substrate
          experimentHash
          planId
          initialState
          device
          net0
          adam0
          generations
          games
          sims
          maxPlies
          updates
          seed
      -- Recorded after the self-play/update loop returned successfully.
      azDeviceWitnessE <- liftIO (mlpdExecutionWitness device)
      let winRate =
            PolicyValueNet.arenaWinRateAgainstUniformFrom
              initialState
              trainedNet
              arenaGames
              maxPlies
              (seed + 7919)
          completedGenerations = fromIntegral generations
          checkpointStep =
            ProductCompletion.alphaZeroArtifactStep completedGenerations (length samples)
          alphaZeroMetrics =
            [ ("arena_win_rate", winRate)
            , ("legal_move_rate", 1.0)
            , ("mcts_simulations_per_move", fromIntegral sims)
            , ("self_play_games", fromIntegral games)
            , ("self_play_generations", fromIntegral generations)
            , ("self_play_samples", fromIntegral (length samples))
            ]
          initialAlphaZeroWeights = PolicyValueNet.policyValueNetToFlat net0
          alphaZeroWeights = PolicyValueNet.policyValueNetToFlat trainedNet
          alphaZeroCompleted =
            do
              deviceWitness <- eitherToMaybe azDeviceWitnessE
              budget <- eitherToMaybe (ProductCompletion.alphaZeroCompletionBudget plan)
              updatesPerGeneration <-
                eitherToMaybe
                  ( ProductCompletion.checkedPositiveWord64FromInt
                      "AlphaZero optimizer updates per generation"
                      updates
                  )
              optimizerUpdateCount <-
                eitherToMaybe
                  ( ProductCompletion.checkedWord64Product
                      "AlphaZero optimizer update evidence"
                      completedGenerations
                      updatesPerGeneration
                  )
              eitherToMaybe
                ( ProductCompletion.alphaZeroCompletedTraining
                    (WorkloadPlan.alphaZeroPlanId plan)
                    budget
                    experimentHash
                    completedGenerations
                    optimizerUpdateCount
                    (PolicyValueNet.policyValueTrainingSamplesSha256 samples)
                    alphaZeroMetrics
                    initialAlphaZeroWeights
                    alphaZeroWeights
                    deviceWitness
                )
      stored <-
        case alphaZeroCompleted of
          Nothing ->
            CheckpointStore.candidateStoredCheckpoint
              <$> CheckpointWriter.writeLocalCandidateWeightCheckpoint
                experimentHash
                ("alphazero-" <> gameName <> "-policy-value-weights")
                checkpointStep
                alphaZeroMetrics
                alphaZeroWeights
          Just completed ->
            CheckpointStore.completedStoredCheckpoint
              <$> CheckpointWriter.writeLocalCompletedWeightCheckpoint
                completed
                experimentHash
                ("alphazero-" <> gameName <> "-policy-value-weights")
                checkpointStep
                alphaZeroMetrics
                alphaZeroWeights
      transcriptArtifact <-
        CheckpointWriter.writeTextArtifact
          experimentHash
          "alphazero-transcript"
          (renderAlphaZeroTranscriptArtifact experimentHash seed sims maxPlies samples)
      writeText $
        Text.unlines
          ( [ "rl alphazero self-play: substrate=" <> renderSubstrate substrate
            , "game: " <> gameName
            , "generations: " <> Text.pack (show generations)
            , "games: " <> Text.pack (show games)
            , "samples: " <> Text.pack (show (length samples))
            , "arena-win-rate: " <> Text.pack (show winRate)
            , "legal-move-rate: 1.0"
            , "mcts-simulations-per-move: " <> Text.pack (show sims)
            ]
              <> CheckpointWriter.renderStoredCheckpointLines experimentHash stored
              <> CheckpointWriter.renderStoredArtifactLines "alphazero-transcript" transcriptArtifact
          )
      publishResolvedAlphaZeroEvent
        runtime
        contextMaybe
        substrate
        ( ProtoRl.RlArenaCompleted
            ProtoRl.ArenaCompleted
              { ProtoRl.acPlanId = planId
              , ProtoRl.acExperimentHash = experimentHash
              , ProtoRl.acArenaGames = fromIntegral arenaGames
              , ProtoRl.acWinRate = winRate
              }
        )

trainResolvedAlphaZeroGenerations
  :: RlCommandRuntime
  -> Maybe RlWorkerServices
  -> Substrate
  -> Text
  -> Text
  -> AlphaZero.GameState
  -> MlpDevice
  -> PolicyValueNet.PolicyValueNet
  -> AdamState
  -> Int
  -> Int
  -> Int
  -> Int
  -> Int
  -> Int
  -> App (PolicyValueNet.PolicyValueNet, [PolicyValueNet.PolicyValueTrainingSample])
trainResolvedAlphaZeroGenerations runtime context substrate experimentHash planId initialState device = go 0
 where
  go generation net adam generationTarget games sims maxPlies updates seed
    | generation >= generationTarget = pure (net, [])
    | otherwise = do
        sampleResults <-
          liftIO $
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
        generationSamples <- case sequence sampleResults of
          Left err -> exitWithError (InvalidConfig ("AlphaZero self-play failed: " <> err))
          Right batches -> pure (concat batches)
        when (null generationSamples) $
          exitWithError (InvalidConfig "AlphaZero self-play produced no samples")
        trainedE <-
          liftIO $
            PolicyValueNet.trainPolicyValueNetOnSamplesWithDevice
              device
              net
              adam
              1.0e-3
              updates
              generationSamples
        (trainedNet, trainedAdam) <- case trainedE of
          Left err -> exitWithError (InvalidConfig ("AlphaZero device training failed: " <> err))
          Right trained -> pure trained
        publishResolvedAlphaZeroEvent
          runtime
          context
          substrate
          ( ProtoRl.RlGenerationCompleted
              ProtoRl.GenerationCompleted
                { ProtoRl.gcPlanId = planId
                , ProtoRl.gcExperimentHash = experimentHash
                , ProtoRl.gcGeneration = fromIntegral generation
                , ProtoRl.gcSelfPlayGames = fromIntegral games
                , ProtoRl.gcSamples = fromIntegral (length generationSamples)
                }
          )
        (finalNet, laterSamples) <-
          go
            (generation + 1)
            trainedNet
            trainedAdam
            generationTarget
            games
            sims
            maxPlies
            updates
            seed
        pure (finalNet, generationSamples <> laterSamples)

publishResolvedAlphaZeroEvent
  :: RlCommandRuntime
  -> Maybe RlWorkerServices
  -> Substrate
  -> ProtoRl.RlEvent
  -> App ()
publishResolvedAlphaZeroEvent _ Nothing _ _ = pure ()
publishResolvedAlphaZeroEvent runtime (Just context) substrate event = do
  result <-
    liftIO
      ( rlCommandPublishEvent
          runtime
          (rlWorkerServicePulsarSettings context)
          substrate
          event
      )
  case result of
    Left err -> exitWithError (InvalidConfig ("publish AlphaZero event: " <> Text.pack (show err)))
    Right _ -> pure ()

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

word32PlanValue :: Text -> Integer -> App Word32
word32PlanValue label value
  | value < 0 || value > toInteger (maxBound :: Word32) =
      exitWithError (InvalidConfig (label <> " is outside the Word32 protocol range"))
  | otherwise = pure (fromInteger value)

intPlanValue :: Text -> Word64 -> App Int
intPlanValue label value
  | toInteger value > toInteger (maxBound :: Int) =
      exitWithError (InvalidConfig (label <> " exceeds the platform Int range"))
  | otherwise = pure (fromIntegral value)

eitherToMaybe :: Either a b -> Maybe b
eitherToMaybe (Right value) = Just value
eitherToMaybe (Left _) = Nothing
