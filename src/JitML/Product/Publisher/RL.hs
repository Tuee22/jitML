{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Product.Publisher.RL
  ( trainAndPublishRlProductRow
  )
where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ask)
import Data.Text qualified as Text

import JitML.Env.Env (App)
import JitML.Numerics.MlpDevice (MlpDevice (..))
import JitML.Numerics.MlpDeviceSelect (rlDeviceForSubstrate)
import JitML.Plan.Plan (RunKind (..), runPlanExperimentId)
import JitML.Product.Evidence qualified as ProductEvidence
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
  , productPublishUnsupported
  , writeProductTextArtifact
  )
import JitML.Product.Publisher.NativeCompanion (renderRlTrajectoryArtifact)
import JitML.Product.Publisher.Projection
  ( ProjectedRlExecution (..)
  , projectedRlExecution
  )
import JitML.Product.Publisher.Runtime (ProductPublisherRuntime (..))
import JitML.RL.Algorithms.Common qualified as AlgorithmCommon
import JitML.RL.ProductBudget qualified as ProductBudget
import JitML.RL.TrainerExecution qualified as TrainerExecution
import JitML.Training.Budget qualified as TrainingBudget

trainAndPublishRlProductRow
  :: Maybe TrainingBudget.ProductScenarioInvocation
  -> ProductPublisherRuntime
  -> ProductMatrix.ProductRow 'ProductMatrix.Declared
  -> ProductMatrix.ProductProjection 'ReinforcementLearning
  -> App ProductPublishResult
trainAndPublishRlProductRow invocation runtime row projection =
  case ( ProductMatrix.productProjectionDescriptor projection
       , ProductMatrix.productProjectionResolvedPlan projection
       ) of
    ( descriptor@ProductMatrix.RlProductDescriptor {}
      , ProductMatrix.ResolvedRlProductPlan runPlan
      ) ->
        case projectedRlExecution row projection descriptor runPlan of
          Left err -> pure (productPublishError projection err)
          Right execution ->
            let trainerKind = projectedRlTrainerKind execution
                environment = projectedRlEnvironment execution
                substrate = projectedRlSubstrate execution
                seed = projectedRlSeed execution
                plan = projectedRlPlan execution
                budget = projectedRlTrainingBudget execution
             in case ProductBudget.rlTrainerEnvironmentCompatibilityError trainerKind environment of
                  Just err -> pure (productPublishUnsupported projection err)
                  Nothing -> do
                    env <- ask
                    trainerRunE <-
                      liftIO
                        ( publisherRunRlTraining
                            runtime
                            substrate
                            (rlDeviceForSubstrate substrate env)
                            plan
                        )
                    case trainerRunE of
                      Left err -> pure (productPublishError projection err)
                      Right (TrainerExecution.EvaluationOnly _) ->
                        pure
                          ( productPublishError
                              projection
                              "product RL training returned evaluation-only evidence"
                          )
                      Right (TrainerExecution.Trained artifact) -> do
                        -- Recorded after the trainer returned: the row's
                        -- device-evidence cell is minted from the artifact the
                        -- rollout/update loop executed through.
                        witnessE <-
                          liftIO (mlpdExecutionWitness (rlDeviceForSubstrate substrate env))
                        let counters = TrainerExecution.trainedArtifactCounters artifact
                            evaluationSet =
                              TrainerExecution.trainedArtifactEvaluationSet artifact
                            episodes = TrainerExecution.evaluationSetEpisodes evaluationSet
                            weights = TrainerExecution.trainedArtifactWeights artifact
                            evidence = TrainerExecution.trainedArtifactEvidence artifact
                            observedTransitions =
                              AlgorithmCommon.measuredEnvironmentTransitionCount counters
                        let experimentHash = runPlanExperimentId runPlan
                            tensorName = "rl-" <> Text.toLower trainerKind <> "-weights"
                        case publisherRlCompletionMetrics
                          runtime
                          trainerKind
                          counters
                          evaluationSet of
                          Left err -> pure (productPublishError projection err)
                          Right metrics -> do
                            let checkpointStep = observedTransitions
                                completedTraining = do
                                  deviceWitness <- witnessE
                                  witnessedEvidence <-
                                    maybe
                                      ( Left
                                          "product RL row requires a device execution witness from the training run"
                                      )
                                      (`ProductEvidence.attachDeviceExecutionWitness` evidence)
                                      deviceWitness
                                  completed <-
                                    maybe
                                      ( Left
                                          ( publisherRlCompletionFailure
                                              runtime
                                              trainerKind
                                              environment
                                              metrics
                                          )
                                      )
                                      Right
                                      ( publisherRlCompletedTraining
                                          runtime
                                          (ProductMatrix.productProjectionPlanId projection)
                                          budget
                                          trainerKind
                                          environment
                                          experimentHash
                                          tensorName
                                          checkpointStep
                                          metrics
                                          witnessedEvidence
                                      )
                                  validateProductCompletedTrainingPlanId projection completed
                                  bindProductScenarioCompletion invocation projection completed
                            case completedTraining of
                              Left err -> pure (productPublishError projection err)
                              Right completed -> do
                                trajectory <-
                                  writeProductTextArtifact
                                    runtime
                                    experimentHash
                                    "rl-trajectory"
                                    ( renderRlTrajectoryArtifact
                                        experimentHash
                                        environment
                                        trainerKind
                                        seed
                                        episodes
                                    )
                                stored <-
                                  publisherWriteCompletedWeightCheckpoint
                                    runtime
                                    completed
                                    experimentHash
                                    tensorName
                                    checkpointStep
                                    metrics
                                    weights
                                    [productArtifactPointer trajectory]
                                admission <-
                                  admitPublishedProductCheckpoint runtime projection completed stored
                                pure $
                                  case admission of
                                    Left err ->
                                      productPublishError
                                        projection
                                        ("RL checkpoint storage succeeded but exact Store admission failed: " <> err)
                                    Right admitted ->
                                      productPublishEligible
                                        projection
                                        admitted
                                        [trajectory]
                                        "RL policy artifact and trajectory stored and admitted"
{-# NOINLINE trainAndPublishRlProductRow #-}
