{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module ProductExperimentExactness
  ( productExperimentExactnessTests
  )
where

import Data.Foldable (traverse_)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (find, nub)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

import JitML.App qualified as App
import JitML.Experiment.Product qualified as ProductExperiment
import JitML.Numerics.LayerGraph qualified as LayerGraph
import JitML.Numerics.Mlp qualified as Mlp
import JitML.Numerics.MlpDevice (MlpDevice (..), pureReferenceMlpDevice)
import JitML.Plan.Plan qualified as Plan
import JitML.Product.Evidence qualified as ProductEvidence
import JitML.Product.Matrix qualified as Product
import JitML.RL.Algorithms.ContinuousTrainer qualified as ContinuousTrainer
import JitML.RL.AlphaZero qualified as AlphaZero
import JitML.RL.AlphaZero.PolicyValueNet qualified as PolicyValueNet
import JitML.RL.EpisodeEnvelope qualified as EpisodeEnvelope
import JitML.SL.Architecture qualified as Architecture
import JitML.SL.Canonicals qualified as SL
import JitML.SL.Classifier qualified as Classifier
import JitML.Substrate (Substrate (LinuxCPU))
import JitML.Training.Budget qualified as Budget

productExperimentExactnessTests :: TestTree
productExperimentExactnessTests =
  testGroup
    "ProductExperimentExactness"
    [ testCase "all non-tuning ProductRows load one exact checked-in config" $ do
        results <-
          traverse
            ( \row -> do
                loaded <- ProductExperiment.loadProductExperimentForRow row
                pure (Product.rowId row, loaded)
            )
            nonTuningRows
        [rowId <> ": " <> err | (rowId, Left err) <- results] @?= []
        let paths = fmap Product.experimentConfig nonTuningRows
        paths @?= fmap (Product.productExperimentConfigPath . Product.rowId) nonTuningRows
        assertBool "exact ProductRow config paths collide" (length paths == length (nub paths))
    , testCase "whole-batch preflight accumulates later failures with zero runner effects" $ do
        preparedInputs <- newIORef ([] :: [Int])
        runnerInputs <- newIORef ([] :: [Int])
        result <-
          ProductExperiment.preflightAllThenExecute
            ( \input -> do
                modifyIORef' preparedInputs (<> [input])
                pure $
                  if input `elem` [2, 4]
                    then Left ("malformed-" <> Text.pack (show input))
                    else Right (input * 10)
            )
            ( \prepared -> do
                modifyIORef' runnerInputs (<> [prepared])
                pure (prepared + 1)
            )
            [1, 2, 3, 4]
        result @?= Left ["malformed-2", "malformed-4"]
        readIORef preparedInputs >>= (@?= [1, 2, 3, 4])
        readIORef runnerInputs >>= (@?= [])
    , testCase "whole-batch preflight executes retained values once in input order" $ do
        runnerInputs <- newIORef ([] :: [Int])
        result <-
          ProductExperiment.preflightAllThenExecute
            (\input -> pure (Right (input * 10) :: Either Text Int))
            ( \prepared -> do
                modifyIORef' runnerInputs (<> [prepared])
                pure (prepared + 1)
            )
            [1, 2, 3]
        result @?= Right [11, 21, 31]
        readIORef runnerInputs >>= (@?= [10, 20, 30])
    , testCase "opaque proof APIs expose functions, never record-update labels" $
        traverse_ (uncurry assertOpaqueReadAccessors) opaqueReadAccessorContracts
    , testCase "AlphaZero completion data hash covers exact ordered samples" $ do
        let sample state visits outcome =
              PolicyValueNet.PolicyValueTrainingSample
                { PolicyValueNet.sampleState = state
                , PolicyValueNet.sampleVisitDist = VU.fromList visits
                , PolicyValueNet.sampleOutcome = outcome
                }
            baseState = AlphaZero.GameState "connect4" [] 1
            movedState = AlphaZero.GameState "connect4" [0] 2
            baseSample = sample baseState [0.75, 0.25] 1.0
            movedSample = sample movedState [0.75, 0.25] 1.0
            variants =
              [ [sample (AlphaZero.GameState "hex" [] 1) [0.75, 0.25] 1.0]
              , [movedSample]
              , [sample (AlphaZero.GameState "connect4" [] 2) [0.75, 0.25] 1.0]
              , [sample baseState [0.25, 0.75] 1.0]
              , [sample baseState [0.75, 0.25] (-1.0)]
              , [baseSample, movedSample]
              , [movedSample, baseSample]
              ]
            digest = PolicyValueNet.policyValueTrainingSamplesSha256
            evidence samples =
              either
                (error . Text.unpack)
                id
                ( ProductEvidence.mkTrainingEvidence
                    "alpha-initial"
                    "alpha-final"
                    1
                    (digest samples)
                )
            baseDigest = ProductEvidence.evidenceDatasetShaAtRead (evidence [baseSample])
            observedDigests = fmap (ProductEvidence.evidenceDatasetShaAtRead . evidence) variants
        assertBool
          "a changed AlphaZero state, target, outcome, cardinality, or order reused completion data evidence"
          (baseDigest `notElem` observedDigests && length observedDigests == length (nub observedDigests))
    , testCase "AlphaZero declared updates are exact averaged-batch Adam steps" $ do
        let net0 = PolicyValueNet.initPolicyValueNet 43 7 4 91
            adam0 = PolicyValueNet.initAdamFor net0
            baseState = AlphaZero.initialConnect4
            nextState = AlphaZero.applyMove 0 baseState
            sample state target outcome =
              PolicyValueNet.PolicyValueTrainingSample
                { PolicyValueNet.sampleState = state
                , PolicyValueNet.sampleVisitDist = VU.fromList target
                , PolicyValueNet.sampleOutcome = outcome
                }
            samples =
              [ sample baseState [1, 0, 0, 0, 0, 0, 0] 1
              , sample nextState [0, 1, 0, 0, 0, 0, 0] (-1)
              ]
            train updates net adam =
              PolicyValueNet.trainPolicyValueNetOnSamples
                net
                adam
                1.0e-3
                updates
                samples
            expectTraining label result =
              case result of
                Left err ->
                  assertFailure (label <> ": " <> Text.unpack err)
                    >> fail "unreachable AlphaZero training failure"
                Right trained -> pure trained
        batchThree@(_, batchAdam) <- expectTraining "three-update batch" (train 3 net0 adam0)
        stepOne <- expectTraining "first replay update" (train 1 net0 adam0)
        stepTwo <- expectTraining "second replay update" (uncurry (train 1) stepOne)
        stepThree <- expectTraining "third replay update" (uncurry (train 1) stepTwo)
        replay <- expectTraining "deterministic replay" (train 3 net0 adam0)
        deviceResult <-
          PolicyValueNet.trainPolicyValueNetOnSamplesWithDevice
            pureReferenceMlpDevice
            net0
            adam0
            1.0e-3
            3
            samples
        device <- expectTraining "reference-device replay" deviceResult
        Mlp.adamStep_ batchAdam - Mlp.adamStep_ adam0 @?= 3
        assertBool "three exact AlphaZero updates did not move parameters" (fst batchThree /= net0)
        batchThree @?= stepThree
        batchThree @?= replay
        batchThree @?= device
    , testCase "AlphaZero optimiser rejects empty data and non-positive updates" $ do
        let net = PolicyValueNet.initPolicyValueNet 43 7 4 91
            adam = PolicyValueNet.initAdamFor net
            sample =
              PolicyValueNet.PolicyValueTrainingSample
                AlphaZero.initialConnect4
                (VU.fromList [1, 0, 0, 0, 0, 0, 0])
                1
            train = PolicyValueNet.trainPolicyValueNetOnSamples net adam 1.0e-3
        train 0 [sample] @?= Left "AlphaZero optimiser update count must be positive"
        train (-1) [sample] @?= Left "AlphaZero optimiser update count must be positive"
        train 1 [] @?= Left "AlphaZero optimiser requires non-empty training samples"
        deviceZero <-
          PolicyValueNet.trainPolicyValueNetOnSamplesWithDevice
            pureReferenceMlpDevice
            net
            adam
            1.0e-3
            0
            [sample]
        deviceEmpty <-
          PolicyValueNet.trainPolicyValueNetOnSamplesWithDevice
            pureReferenceMlpDevice
            net
            adam
            1.0e-3
            1
            []
        deviceZero @?= Left "AlphaZero optimiser update count must be positive"
        deviceEmpty @?= Left "AlphaZero optimiser requires non-empty training samples"
    , testCase "completion proof keeps budget units distinct from optimiser updates at Word64 bounds" $ do
        let maximumWord = maxBound :: Word64
            planId =
              either
                (error . Text.unpack)
                id
                (Plan.refinePlanIdText (Text.replicate 64 "a"))
            budget =
              either
                (error . Text.unpack)
                id
                (Budget.mkTrainingBudget Budget.TuningTrialBudget maximumWord Nothing)
            evidence updates =
              either
                (error . Text.unpack)
                id
                ( ProductEvidence.mkTrainingEvidence
                    "boundary-initial"
                    "boundary-final"
                    updates
                    "boundary-dataset-sha"
                )
            observation =
              either
                (error . Text.unpack)
                id
                (Budget.measureCriterion "best_objective" Budget.MetricMaximise 0 1)
            complete updates =
              Budget.completedTraining
                planId
                budget
                maximumWord
                (evidence updates)
                [observation]
                Budget.TensorBoardRunMetadata
                  { Budget.tbrRunId = "boundary-run"
                  , Budget.tbrLogPrefix = "tensorboard/boundary-run"
                  , Budget.tbrScalarTags = ["best_objective"]
                  }
        case complete 1 of
          Left err -> assertFailure (Text.unpack err)
          Right completed -> do
            Budget.completedTrainingObservedUnits completed @?= maximumWord
            Budget.completedTrainingUpdateCount completed @?= 1
        case complete maximumWord of
          Left err -> assertFailure (Text.unpack err)
          Right completed -> Budget.completedTrainingUpdateCount completed @?= maximumWord
        Budget.mkTrainingBudget Budget.TuningTrialBudget 0 Nothing
          @?= Left "training budget must have a positive target"
        ProductEvidence.mkTrainingEvidence "initial" "final" 0 "dataset-sha"
          @?= Left "training evidence requires a positive update count"
        ProductEvidence.mkTrainingEvidence "initial" "final" 1 ""
          @?= Left "training evidence requires a dataset SHA observed at read"
    , testCase "RL completion proof rejects zero updates and observed units" $ do
        App.validateTrainerEvidenceCounters 0 1
          @?= Left "RL training evidence requires a positive update count"
        App.validateTrainerEvidenceCounters 1 0
          @?= Left "RL training evidence requires positive observed budget units"
        App.validateTrainerEvidenceCounters 0 0
          @?= Left "RL training evidence requires a positive update count"
        App.validateTrainerEvidenceCounters 1 1 @?= Right ()
    , testCase "RL completion inputs reject zero rather than repairing evidence" $ do
        let episode index steps =
              EpisodeEnvelope.SimulatedEpisode
                { EpisodeEnvelope.simEpisodeIndex = index
                , EpisodeEnvelope.simEpisodeSteps = steps
                , EpisodeEnvelope.simEpisodeReward = 0
                , EpisodeEnvelope.simEpisodeDone = True
                , EpisodeEnvelope.simEpisodeFrames = []
                }
        App.rlObservedBudgetUnits []
          @?= Left "RL observed environment-step count must be positive"
        App.rlObservedBudgetUnits [episode 7 0]
          @?= Left "RL episode 7 must report positive observed steps"
        App.rlObservedBudgetUnits [episode 8 (-1)]
          @?= Left "RL episode 8 must report positive observed steps"
        App.rlObservedBudgetUnits [episode 0 2, episode 1 3] @?= Right 5
        App.checkpointTrainingBudgetForTensor "rl-ppo-weights" 0
          @?= Left "training budget must have a positive target"
        case App.checkpointTrainingBudgetForTensor "rl-ppo-weights" 5 of
          Left err -> assertFailure (Text.unpack err)
          Right budget -> do
            Budget.trainingBudgetKind budget @?= Budget.RlEnvironmentStepBudget
            Budget.trainingBudgetTargetUnits budget @?= 5
    , testCase "SAC warm-start actor consumes the exact projected seed" $ do
        let actor seed =
              ContinuousTrainer.initialContinuousActor
                ( (ContinuousTrainer.defaultContinuousTrainConfig ContinuousTrainer.VariantSAC)
                    { ContinuousTrainer.ctSeed = seed
                    , ContinuousTrainer.ctHidden = 4
                    }
                )
            first = actor 17
            replay = actor 17
            different = actor 18
        first @?= replay
        assertBool "distinct SAC seeds produced the same warm-start actor" (first /= different)
    , testCase "tuning ProductRow loads only its exact checked-in config" $ do
        row <- requireRow "hyperparameter-tuning"
        loaded <- ProductExperiment.loadProductExperimentForRow row
        case loaded of
          Right (ProductExperiment.ProductTuningExperiment _) -> pure ()
          Right _ -> assertFailure "tuning ProductRow loaded a different experiment kind"
          Left err -> assertFailure ("exact tuning config was rejected: " <> Text.unpack err)
    , testCase "tuning config mutations fail before a prepared proof is minted" $ do
        row <- requireRow "hyperparameter-tuning"
        traverse_
          (uncurry (assertCheckedInConfigMutationRejected row))
          [
            ( Text.replace "name = \"mnist-tune\"" "name = \"other-tune\""
            , "tuning experiment execution spec mismatch"
            )
          ,
            ( Text.replace ", seed = 1729\n, tuning" ", seed = 1730\n, tuning"
            , "tuning experiment seed mismatch"
            )
          ,
            ( Text.replace "          , seed = 1729" "          , seed = 1730"
            , "tuning experiment execution spec mismatch"
            )
          ]
    , testCase "opaque projections retain exact validated registry claims" $
        traverse_ assertProjectionRetainsClaims Product.allProductRows
    , testCase "stale implementation and architecture claims are rejected" $ do
        supervised <- requireRow "mnist-deep-mlp"
        regression <- requireRow "california-housing-mlp"
        rl <- requireRow "PPO/cartpole"
        assertProjectionRejectedWith
          supervised {Product.implementation = Product.implementation supervised <> ".stale"}
          ( \case
              Product.ProductImplementationMismatch {} -> True
              _ -> False
          )
        assertProjectionRejectedWith
          supervised
            { Product.rowArchitectureFeatures =
                case Product.rowArchitectureFeatures supervised of
                  [] -> []
                  _ : features -> features
            }
          ( \case
              Product.ProductArchitectureFeaturesMismatch {} -> True
              _ -> False
          )
        assertProjectionRejectedWith
          rl {Product.rowArchitectureFeatures = [Architecture.FeatureDense]}
          ( \case
              Product.ProductArchitectureFeaturesMismatch {} -> True
              _ -> False
          )
        Product.implementation regression
          @?= "JitML.SL.Regression.trainRegressorWithDevice"
        Product.rowArchitectureFeatures regression @?= [Architecture.FeatureDense]
        assertProjectionRejectedWith
          regression
            { Product.implementation =
                "JitML.SL.Architecture.architectureSpecForProblem/Dense"
            }
          ( \case
              Product.ProductImplementationMismatch {} -> True
              _ -> False
          )
        assertProjectionRejectedWith
          regression
            { Product.rowArchitectureFeatures =
                [Architecture.FeatureDense, Architecture.FeatureDropout]
            }
          ( \case
              Product.ProductArchitectureFeaturesMismatch {} -> True
              _ -> False
          )
    , testCase "architecture seed headroom follows the realised topology" $
        traverse_ assertArchitectureSeedHeadroomTopology SL.canonicalProblems
    , testCase "exact-update graph optimizer averages the gradient by outer example count" $ do
        -- Sprint 238.1 — the retired [LayerState] patch-expansion normalization
        -- check, migrated onto the typed-graph optimizer step. One SGD update over
        -- a batch of @n@ examples with an all-ones batch-summed gradient must move
        -- every parameter by @lr * (1 / n)@: the gradient is averaged by the
        -- number of outer examples, never by an expanded device-row count.
        node <-
          either (assertFailure . Text.unpack) pure $
            LayerGraph.mkAffineLayer
              "exact-normalization"
              LayerGraph.DenseLayer
              2
              2
              LayerGraph.LinearActivation
              LayerGraph.TrainingMode
              (LayerGraph.deterministicParameters 1 2 2)
        let graph =
              LayerGraph.LayerGraph
                { LayerGraph.layerGraphName = "exact-normalization"
                , LayerGraph.layerGraphInputShape = LayerGraph.TensorShape [2]
                , LayerGraph.layerGraphOutputShape = LayerGraph.TensorShape [2]
                , LayerGraph.layerGraphNodes = [node]
                }
            st0 = LayerGraph.initGraphClassifierAdam graph
            params0 = LayerGraph.graphParameterVector graph
            paramCount = VU.length params0
            learningRate = 0.1 :: Double
            batchLen = 2 :: Int
            summed = VU.replicate paramCount 1.0
            expectedDelta = learningRate / fromIntegral batchLen
        st1 <-
          either (assertFailure . Text.unpack) pure $
            Architecture.applyGraphOptimizerStep
              (Architecture.SgdOptimizer learningRate)
              st0
              summed
              batchLen
        let deltas =
              VU.toList
                ( VU.zipWith
                    (-)
                    params0
                    (LayerGraph.graphParameterVector (LayerGraph.gcaGraph st1))
                )
        assertBool
          "every parameter moves by learning-rate * (summed gradient / outer example count)"
          (paramCount > 0 && all (\delta -> abs (delta - expectedDelta) < 1.0e-12) deltas)
    , testCase "supervised seed headroom follows each exact architecture" $
        traverse_ assertSupervisedSeedBoundary supervisedRows
    , testCase "RL seed headroom follows each exact trainer" $
        traverse_ assertRlSeedBoundary rlRows
    , testCase "AlphaZero seed headroom covers outer, ply, and arena offsets" $
        traverse_ assertAlphaZeroSeedBoundary alphaZeroRows
    , testCase "every non-tuning config path participates in PlanId" $
        traverse_ assertConfigPathChangesPlanId nonTuningRows
    , testCase "supervised config mutations fail before execution" $ do
        row <- requireRow "mnist-shallow-mlp"
        traverse_
          (uncurry (assertConfigMutationRejected row))
          [
            ( Text.replace "name = \"mnist-shallow-mlp\"" "name = \"other-row\""
            , "supervised experiment name mismatch"
            )
          ,
            ( Text.replace "dataset = \"MNIST\"" "dataset = \"Fashion-MNIST\""
            , "supervised experiment dataset mismatch"
            )
          ,
            ( Text.replace "model = \"Dense\"" "model = \"DeepDense\""
            , "supervised experiment model mismatch"
            )
          , (Text.replace "seed = 1001" "seed = 0", "supervised experiment seed mismatch")
          ]
    , testCase "RL config algorithm/environment/name/seed cannot be overwritten" $ do
        row <- requireRow "PPO/cartpole"
        traverse_
          (uncurry (assertConfigMutationRejected row))
          [
            ( Text.replace "name = \"PPO/cartpole\"" "name = \"A2C/cartpole\""
            , "RL experiment name mismatch"
            )
          , (Text.replace "algorithm = \"PPO\"" "algorithm = \"A2C\"", "RL experiment algorithm mismatch")
          ,
            ( Text.replace "environment = \"cartpole\"" "environment = \"mountain-car\""
            , "RL experiment environment mismatch"
            )
          , (Text.replace "seed = 42" "seed = 0", "RL experiment seed mismatch")
          ]
    , testCase "shared cartpole example cannot be rewritten into DQN ProductRow semantics" $ do
        row <- requireRow "DQN/cartpole"
        projection <-
          project
            row
              { Product.experimentConfig = "experiments/cartpole.dhall"
              }
        loaded <- loadProjection projection
        case loaded of
          Left err ->
            assertBool
              ("unexpected shared-config rejection: " <> Text.unpack err)
              ( "RL experiment name mismatch" `Text.isInfixOf` err
                  || "RL experiment algorithm mismatch" `Text.isInfixOf` err
                  || "RL experiment environment mismatch" `Text.isInfixOf` err
              )
          Right (ProductExperiment.ProductRlExperiment experiment) ->
            assertFailure
              ( "shared PPO config was rewritten into "
                  <> Text.unpack (ProductExperiment.rlExperimentAlgorithm experiment)
              )
          Right _ -> assertFailure "shared RL config decoded as a different ProductExperiment kind"
    , testCase "AlphaZero config game/simulations/name/seed cannot drift" $ do
        row <- requireRow "connect4"
        traverse_
          (uncurry (assertConfigMutationRejected row))
          [ (Text.replace "name = \"connect4\"" "name = \"othello\"", "AlphaZero experiment name mismatch")
          , (Text.replace "game = \"connect4\"" "game = \"othello\"", "AlphaZero experiment game mismatch")
          ,
            ( Text.replace "simulationsPerMove = 128" "simulationsPerMove = 192"
            , "AlphaZero experiment simulationsPerMove mismatch"
            )
          , (Text.replace "seed = 42" "seed = 0", "AlphaZero experiment seed mismatch")
          ]
    ]

nonTuningRows :: [Product.ProductRow 'Product.Declared]
nonTuningRows =
  filter
    ( \row ->
        case Product.rowClass row of
          Product.HyperparameterTuning _ -> False
          _ -> True
    )
    Product.allProductRows

supervisedRows :: [Product.ProductRow 'Product.Declared]
supervisedRows =
  [ row
  | row <- Product.allProductRows
  , case Product.rowClass row of
      Product.SupervisedClassification _ _ -> True
      Product.SupervisedRegression _ _ -> True
      _ -> False
  ]

rlRows :: [Product.ProductRow 'Product.Declared]
rlRows =
  [ row
  | row <- Product.allProductRows
  , case Product.rowClass row of
      Product.RlAlgorithmEnvironment _ _ -> True
      Product.RlGoalConditioned _ -> True
      _ -> False
  ]

alphaZeroRows :: [Product.ProductRow 'Product.Declared]
alphaZeroRows =
  [ row
  | row <- Product.allProductRows
  , case Product.rowClass row of
      Product.AlphaZeroGame _ -> True
      _ -> False
  ]

opaqueReadAccessorContracts :: [(FilePath, [Text])]
opaqueReadAccessorContracts =
  [
    ( "src/JitML/Plan/Plan.hs"
    ,
      [ "runPlanVersion"
      , "runPlanExperimentId"
      , "runPlanSubjectId"
      , "runPlanArtifactId"
      , "runPlanTopicId"
      , "runPlanSubstrate"
      , "runPlanPlacement"
      , "runPlanSeeds"
      , "runPlanId"
      , "runPlanBudgetSummary"
      , "runPlanSupervisedBudget"
      , "runPlanRlBudget"
      , "runPlanTuningBudget"
      , "runPlanAlphaZeroBudget"
      ]
    )
  ,
    ( "src/JitML/Plan/Workload.hs"
    ,
      [ "supervisedPlanRunPlan"
      , "supervisedPlanId"
      , "supervisedPlanEpochs"
      , "supervisedPlanTrainingExamples"
      , "supervisedPlanEvaluationExamples"
      , "supervisedPlanBatchExamples"
      , "supervisedPlanOptimizerUpdates"
      , "tuningPlanRunPlan"
      , "tuningPlanSampler"
      , "tuningPlanScheduler"
      , "tuningPlanPruner"
      , "tuningPlanExecutionSpec"
      , "tuningPlanId"
      , "tuningPlanTrials"
      , "tuningPlanParallelism"
      , "tuningPlanPromotions"
      , "tuningPlanPerTrialUpdates"
      , "tuningPlanMaxPerTrialUpdates"
      , "alphaZeroPlanRunPlan"
      , "alphaZeroPlanGame"
      , "alphaZeroPlanId"
      , "alphaZeroPlanGenerations"
      , "alphaZeroPlanSelfPlayGames"
      , "alphaZeroPlanMctsSimulations"
      , "alphaZeroPlanMaxPlies"
      , "alphaZeroPlanUpdates"
      , "alphaZeroPlanArenaGames"
      ]
    )
  ,
    ( "src/JitML/Product/Matrix.hs"
    ,
      [ "productProjectionRowId"
      , "productProjectionFamily"
      , "productProjectionRowClass"
      , "productProjectionImplementation"
      , "productProjectionArchitectureFeatures"
      , "productProjectionExperimentHash"
      , "productProjectionExperimentConfig"
      , "productProjectionTrainingBudget"
      , "productProjectionConvergenceBar"
      , "productProjectionDeviceClaim"
      , "productProjectionIntegrationTest"
      , "productProjectionE2ETest"
      , "productProjectionDemoPanel"
      , "productProjectionSubstrate"
      , "productProjectionRunKind"
      , "productProjectionCommand"
      , "productProjectionDescriptor"
      , "productProjectionEvidenceRequirements"
      , "productProjectionResolvedPlan"
      , "productProjectionRunPlan"
      , "productProjectionPlanId"
      , "productProjectionBatchSubstrate"
      , "productProjectionBatchRowIds"
      , "productProjectionBatchProjections"
      ]
    )
  ,
    ( "src/JitML/Experiment/Product.hs"
    ,
      [ "preparedSupervisedProductExperiment"
      , "preparedRlProductExperiment"
      , "preparedTuningProductExperiment"
      , "preparedAlphaZeroProductExperiment"
      ]
    )
  ,
    ( "src/JitML/Tune/Catalog.hs"
    ,
      [ "trialLearningRate"
      , "trialBatchSize"
      , "trialDropout"
      , "trialOptimizer"
      , "trialResultIndex"
      , "trialResultHyperparameters"
      , "trialResultObjective"
      , "trialResultInitialWeights"
      , "trialResultWeights"
      , "trialResultUpdatesExecuted"
      , "trialResultObservations"
      , "trialResultDisposition"
      , "trialObservationUpdates"
      , "trialObservationObjective"
      , "trialExecutionResult"
      , "trialExecutionPruned"
      , "trialExecutionPromoted"
      , "transcriptExperimentHash"
      , "transcriptTrialSeed"
      , "transcriptValues"
      , "transcriptUpdatesExecuted"
      , "transcriptDisposition"
      , "transcriptObservations"
      ]
    )
  ,
    ( "src/JitML/Run/Contract.hs"
    ,
      [ "evidenceEventPlanId"
      , "evidenceEventId"
      , "evidenceEventKey"
      , "evidenceEventValue"
      ]
    )
  ,
    ( "src/JitML/Test/LiveWorkflow.hs"
    ,
      [ "jobHandlePlanId"
      , "jobHandleName"
      , "hostRunHandlePlanId"
      , "hostRunHandleKey"
      , "requestHandlePlanId"
      , "requestHandleKey"
      , "completedRunPlanId"
      , "completedRunPlacement"
      , "completedRunTerminal"
      , "completedRunEvidence"
      , "completedRunDiagnostics"
      , "completedRunJournal"
      ]
    )
  ,
    ( "src/JitML/Test/Report.hs"
    ,
      [ "blockedByStanza"
      , "blockedByFailure"
      , "invocationStanza"
      , "invocationCommand"
      , "invocationResult"
      , "invocationJournalEntries"
      , "suiteStatus"
      , "suitePassed"
      , "suiteFailed"
      , "suiteNotRun"
      , "suiteDuration"
      , "completedProductScenarioRowId"
      , "completedProductScenarioPlanId"
      , "completedProductScenarioLane"
      ]
    )
  ,
    ( "src/JitML/Training/Budget.hs"
    ,
      [ "tbKind"
      , "tbTargetUnits"
      , "tbSeed"
      , "trainingBudgetKind"
      , "trainingBudgetTargetUnits"
      , "trainingBudgetSeed"
      , "trainingBudgetUnitLabel"
      , "tbUnitLabel"
      , "completedTrainingBudget"
      , "completedTrainingPlanId"
      , "completedTrainingObservedUnits"
      , "completedTrainingEvidence"
      , "completedTrainingMetrics"
      , "completedTrainingTensorBoard"
      , "completedTrainingInitialWeightHash"
      , "completedTrainingFinalWeightHash"
      , "completedTrainingUpdateCount"
      , "completedTrainingDatasetShaAtRead"
      ]
    )
  ,
    ( "src/JitML/Product/Evidence.hs"
    ,
      [ "evidenceInitialWeightHash"
      , "evidenceFinalWeightHash"
      , "evidenceUpdateCount"
      , "evidenceDatasetShaAtRead"
      ]
    )
  ]

assertOpaqueReadAccessors :: FilePath -> [Text] -> IO ()
assertOpaqueReadAccessors path accessors = do
  source <- Text.IO.readFile path
  traverse_ (assertOpaqueReadAccessor path source) accessors

assertOpaqueReadAccessor :: FilePath -> Text -> Text -> IO ()
assertOpaqueReadAccessor path source accessor = do
  let topLevelSignatures =
        [ "\n" <> accessor <> " ::"
        , "\n" <> accessor <> "\n  ::"
        ]
      recordLabels =
        [ "\n  { " <> accessor <> " ::"
        , "\n  , " <> accessor <> " ::"
        , "{ " <> accessor <> " ::"
        , ", " <> accessor <> " ::"
        ]
      context = Text.unpack accessor <> " in " <> path
  assertBool
    ("missing top-level opaque read accessor signature: " <> context)
    (any (`Text.isInfixOf` source) topLevelSignatures)
  assertBool
    ("opaque read accessor is still a forgeable record label: " <> context)
    (not (any (`Text.isInfixOf` source) recordLabels))

requireRow :: Text -> IO (Product.ProductRow 'Product.Declared)
requireRow identity =
  case find ((== identity) . Product.rowId) Product.allProductRows of
    Nothing -> assertFailure ("missing ProductRow " <> Text.unpack identity)
    Just row -> pure row

assertConfigPathChangesPlanId :: Product.ProductRow 'Product.Declared -> IO ()
assertConfigPathChangesPlanId row = do
  canonical <- project row
  changed <-
    project
      row
        { Product.experimentConfig = Product.experimentConfig row <> ".alternate"
        }
  assertBool
    ("config path did not change PlanId for " <> Text.unpack (Product.rowId row))
    (projectionPlanId canonical /= projectionPlanId changed)

assertConfigMutationRejected
  :: Product.ProductRow 'Product.Declared
  -> (Text -> Text)
  -> Text
  -> IO ()
assertConfigMutationRejected row mutate expectedError =
  withSystemTempDirectory "jitml-product-config-exactness" $ \temporary -> do
    rendered <- ProductExperiment.renderProductExperimentDhall row >>= expectRight
    let path = temporary </> "mutated.dhall"
        mutated = mutate rendered
        changedRow = row {Product.experimentConfig = Text.pack path}
    assertBool "config mutation did not change rendered content" (mutated /= rendered)
    Text.IO.writeFile path mutated
    projection <- project changedRow
    loaded <- loadProjection projection
    case loaded of
      Left err ->
        assertBool
          ( "unexpected config rejection for "
              <> Text.unpack (Product.rowId row)
              <> ": "
              <> Text.unpack err
          )
          (expectedError `Text.isInfixOf` err)
      Right _ ->
        assertFailure
          ( "mutated config executed for "
              <> Text.unpack (Product.rowId row)
              <> "; expected "
              <> Text.unpack expectedError
          )

assertCheckedInConfigMutationRejected
  :: Product.ProductRow 'Product.Declared
  -> (Text -> Text)
  -> Text
  -> IO ()
assertCheckedInConfigMutationRejected row mutate expectedError =
  withSystemTempDirectory "jitml-product-config-exactness" $ \temporary -> do
    rendered <- Text.IO.readFile (Text.unpack (Product.experimentConfig row))
    let path = temporary </> "mutated.dhall"
        mutated = mutate rendered
        changedRow = row {Product.experimentConfig = Text.pack path}
    assertBool "config mutation did not change checked-in content" (mutated /= rendered)
    Text.IO.writeFile path mutated
    loaded <- ProductExperiment.loadProductExperimentForRow changedRow
    case loaded of
      Left err ->
        assertBool
          ("unexpected tuning config rejection: " <> Text.unpack err)
          (expectedError `Text.isInfixOf` err)
      Right _ ->
        assertFailure
          ( "mutated checked-in config produced a prepared experiment for "
              <> Text.unpack (Product.rowId row)
          )

assertProjectionRetainsClaims :: Product.ProductRow 'Product.Declared -> IO ()
assertProjectionRetainsClaims row =
  case Product.projectProductRow LinuxCPU row of
    Plan.Failure errors ->
      assertFailure
        ( "canonical ProductRow projection failed for "
            <> Text.unpack (Product.rowId row)
            <> ": "
            <> show errors
        )
    Plan.Success (Product.SomeProductProjection _ projection) -> do
      Product.productProjectionImplementation projection @?= Product.implementation row
      Product.productProjectionArchitectureFeatures projection
        @?= Product.rowArchitectureFeatures row

assertProjectionRejectedWith
  :: Product.ProductRow 'Product.Declared
  -> (Product.ProductProjectionError -> Bool)
  -> IO ()
assertProjectionRejectedWith row expected =
  case Product.projectProductRow LinuxCPU row of
    Plan.Success _ ->
      assertFailure
        ("invalid registry claim projected for " <> Text.unpack (Product.rowId row))
    Plan.Failure errors ->
      assertBool
        ("unexpected projection errors: " <> show errors)
        (any expected errors)

assertArchitectureSeedHeadroomTopology :: SL.CanonicalProblem -> IO ()
assertArchitectureSeedHeadroomTopology problem = do
  let spec = Architecture.architectureSpecForProblem Classifier.defaultClassifierConfig problem
      layerOffset =
        max 0 (toInteger (length (Architecture.archLayers spec)) - 1) * 1009
      graphOffset =
        max
          0
          ( toInteger
              (length (LayerGraph.layerGraphNodes (Architecture.archLayerGraph spec)))
              - 1
          )
  Architecture.architectureSeedHeadroomForProblem problem
    @?= max layerOffset graphOffset

assertSupervisedSeedBoundary :: Product.ProductRow 'Product.Declared -> IO ()
assertSupervisedSeedBoundary row = do
  problem <-
    case find ((== Product.rowId row) . SL.problemName) SL.canonicalProblems of
      Nothing -> assertFailure ("missing canonical problem for " <> Text.unpack (Product.rowId row))
      Just value -> pure value
  assertExactSeedBoundary
    row
    ( case Product.rowClass row of
        Product.SupervisedRegression _ _ -> 0
        _ -> Architecture.architectureSeedHeadroomForProblem problem
    )

assertRlSeedBoundary :: Product.ProductRow 'Product.Declared -> IO ()
assertRlSeedBoundary row =
  assertExactSeedBoundary row (expectedRlSeedHeadroom (Product.rowClass row))

expectedRlSeedHeadroom :: Product.RowClass -> Integer
expectedRlSeedHeadroom rowClass' =
  case rowClass' of
    Product.RlGoalConditioned _ -> 104729
    Product.RlAlgorithmEnvironment algorithm _ ->
      case Text.toUpper algorithm of
        "DDPG" -> 202
        "TD3" -> 202
        "SAC" -> 202
        "CROSSQ" -> 202
        "TQC" -> 202
        "ARS" -> 0
        _ -> 1
    _ -> error "expectedRlSeedHeadroom: non-RL row"

assertAlphaZeroSeedBoundary :: Product.ProductRow 'Product.Declared -> IO ()
assertAlphaZeroSeedBoundary row =
  case Product.productCapability row of
    Product.ExecutableProduct
      (Product.AlphaZeroProductDescriptor _ selfPlayGames _ maxPlies _ arenaGames)
      Product.AlphaZeroProductEvidence ->
        assertExactSeedBoundary
          row
          ( expectedAlphaZeroSeedHeadroom
              (Budget.trainingBudgetTargetUnits (Product.trainingBudget row))
              selfPlayGames
              maxPlies
              arenaGames
          )
    _ -> assertFailure ("AlphaZero row has wrong capability: " <> Text.unpack (Product.rowId row))

expectedAlphaZeroSeedHeadroom :: Word64 -> Word64 -> Word64 -> Word64 -> Integer
expectedAlphaZeroSeedHeadroom generations selfPlayGames maxPlies arenaGames =
  max
    (lastIndex generations * 7919 + lastIndex selfPlayGames + lastIndex maxPlies * 7919)
    (7919 + lastIndex arenaGames * 1009 + lastIndex maxPlies * 7919)
 where
  lastIndex quantity = max 0 (toInteger quantity - 1)

assertExactSeedBoundary
  :: Product.ProductRow 'Product.Declared
  -> Integer
  -> IO ()
assertExactSeedBoundary row offset = do
  let maximumSeed = toInteger (maxBound :: Int)
      boundarySeed = fromInteger (maximumSeed - offset)
  assertProjects (withProductSeed boundarySeed row)
  if offset == 0
    then boundarySeed @?= fromIntegral (maxBound :: Int)
    else
      assertProjectionRejectedWith
        (withProductSeed (boundarySeed + 1) row)
        ( \case
            Product.InsufficientProductSeedHeadroom rowId' _ seed observedOffset ->
              rowId' == Product.rowId row
                && seed == boundarySeed + 1
                && observedOffset == offset
            _ -> False
        )

withProductSeed
  :: Word64
  -> Product.ProductRow state
  -> Product.ProductRow state
withProductSeed seed row =
  row
    { Product.trainingBudget =
        case Budget.mkTrainingBudget
          (Budget.trainingBudgetKind budget)
          (Budget.trainingBudgetTargetUnits budget)
          (Just seed) of
          Left err -> error (Text.unpack err)
          Right changed -> changed
    }
 where
  budget = Product.trainingBudget row

assertProjects :: Product.ProductRow 'Product.Declared -> IO ()
assertProjects row =
  case Product.projectProductRow LinuxCPU row of
    Plan.Success _ -> pure ()
    Plan.Failure errors ->
      assertFailure
        ( "boundary seed failed projection for "
            <> Text.unpack (Product.rowId row)
            <> ": "
            <> show errors
        )

data AnyProjection where
  AnyProjection :: Product.ProductProjection kind -> AnyProjection

project :: Product.ProductRow 'Product.Declared -> IO AnyProjection
project row =
  case Product.projectProductRow LinuxCPU row of
    Plan.Failure errors -> assertFailure ("ProductRow projection failed: " <> show errors)
    Plan.Success (Product.SomeProductProjection _ projection) -> pure (AnyProjection projection)

projectionPlanId :: AnyProjection -> Plan.PlanId
projectionPlanId (AnyProjection projection) = Product.productProjectionPlanId projection

loadProjection :: AnyProjection -> IO (Either Text ProductExperiment.ProductExperiment)
loadProjection (AnyProjection projection) =
  ProductExperiment.loadProductExperimentForProjection projection

expectRight :: Either Text value -> IO value
expectRight result =
  case result of
    Left err -> assertFailure (Text.unpack err)
    Right value -> pure value
