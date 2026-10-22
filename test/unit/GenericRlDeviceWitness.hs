{-# LANGUAGE OverloadedStrings #-}

-- | Offline callback controls for the actual generic trainer producer. Plans
-- come from the public compiler, including its real minimum schedules. The
-- shape-correct fixed-output/gradient device and disk-backed fixture witnesses
-- test metadata flow, not real hardware execution or learned convergence.
module GenericRlDeviceWitness (genericRlDeviceWitnessTests) where

import Control.Exception (IOException, try)
import Control.Monad (forM_)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Numerics.Mlp qualified as Mlp
import JitML.Numerics.MlpDevice (MlpDevice (..), pureReferenceMlpDevice)
import JitML.Product.DeviceWitness qualified as Witness
import JitML.Product.Evidence qualified as Evidence
import JitML.RL.Algorithms.Common qualified as Common
import JitML.RL.Framework qualified as Framework
import JitML.RL.ProductBudget qualified as Plan
import JitML.RL.TrainerExecution qualified as Execution
import JitML.Substrate (Substrate (..))
import JitML.Test.DeviceWitnessFixture (fixtureDeviceExecutionWitnessFor)

genericRlDeviceWitnessTests :: TestTree
genericRlDeviceWitnessTests =
  testGroup
    "generic RL selected-device witness propagation"
    [ testCase "successful PPO dispatch binds the same device witness after training and final evaluation" $ do
        plan <- compiledPlan "ppo" "cartpole"
        witness <- fixtureDeviceExecutionWitnessFor LinuxCPU >>= expectRight
        calls <- newIORef []
        artifact <-
          run plan (fixtureDevice calls NoFailure (pure (Right (Just witness))))
            >>= expectTrained
        Evidence.evidenceDeviceWitness (Execution.trainedArtifactEvidence artifact)
          @?= Right (Just witness)
        assertActualBudget plan artifact
        trace <- reverse <$> readIORef calls
        assertSuccessfulTrace trace
        -- PPO's production final evaluator uses single forwards, after the
        -- training-only batch-gradient operations have finished.
        assertBool
          "the final selected-device evaluation completed before witness capture"
          (case reverse trace of "witness" : "forward" : _ -> True; _ -> False)
    , testCase
        "changing only returned witness location leaves numerical results and all observed evidence fields identical"
        $ do
          plan <- compiledPlan "her" "goal-reaching"
          leftWitness <- fixtureDeviceExecutionWitnessFor LinuxCPU >>= expectRight
          rightWitness <- fixtureDeviceExecutionWitnessFor LinuxCPU >>= expectRight
          assertBool "independent fixture artifact locations differ" (leftWitness /= rightWitness)
          leftCalls <- newIORef []
          rightCalls <- newIORef []
          left <-
            run plan (fixtureDevice leftCalls NoFailure (pure (Right (Just leftWitness)))) >>= expectTrained
          right <-
            run plan (fixtureDevice rightCalls NoFailure (pure (Right (Just rightWitness)))) >>= expectTrained
          Execution.trainedArtifactWeights left @?= Execution.trainedArtifactWeights right
          Execution.trainedArtifactCounters left @?= Execution.trainedArtifactCounters right
          Execution.trainedArtifactLearningCurve left @?= Execution.trainedArtifactLearningCurve right
          Execution.trainedArtifactEvaluationSet left @?= Execution.trainedArtifactEvaluationSet right
          Evidence.evidenceObservationsMatch
            (Execution.trainedArtifactEvidence left)
            (Execution.trainedArtifactEvidence right)
            @?= True
          Evidence.evidenceDeviceWitness (Execution.trainedArtifactEvidence left) @?= Right (Just leftWitness)
          Evidence.evidenceDeviceWitness (Execution.trainedArtifactEvidence right)
            @?= Right (Just rightWitness)
          assertActualBudget plan left
          readIORef leftCalls >>= assertSuccessfulTrace . reverse
          readIORef rightCalls >>= assertSuccessfulTrace . reverse
    , testCase
        "missing failed or wrong-substrate returned witnesses discard successful raw trainer results"
        $ do
          plan <- compiledPlan "her" "goal-reaching"
          wrongLane <- fixtureDeviceExecutionWitnessFor AppleSilicon >>= expectRight
          forM_
            [ (Right Nothing, "returned no execution witness")
            , (Left "witness artifact read sentinel", "witness artifact read sentinel")
            , (Right (Just wrongLane), "witness substrate differs")
            ]
            $ \(answer, expected) -> do
              calls <- newIORef []
              actual <- run plan (fixtureDevice calls NoFailure (pure answer))
              expectLeft expected actual
              readIORef calls >>= assertSuccessfulTrace . reverse
    , testCase "probe failure is propagated before training or witness lookup" $ do
        plan <- compiledPlan "ppo" "cartpole"
        calls <- newIORef []
        actual <- run plan (fixtureDevice calls ProbeFailure (fail "unexpected witness lookup"))
        expectLeft "probe sentinel" actual
        readIORef calls >>= (@?= ["probe"]) . reverse
    , testCase "training device failure is propagated without a witness or partial result" $ do
        plan <- compiledPlan "ppo" "cartpole"
        calls <- newIORef []
        actual <- run plan (fixtureDevice calls TrainingFailure (fail "unexpected witness lookup"))
        expectLeft "training sentinel" actual
        readIORef calls >>= (@?= ["probe", "batch-forward"]) . reverse
    , testCase "failed final device evaluation cannot mint a training witness" $ do
        plan <- compiledPlan "ppo" "cartpole"
        calls <- newIORef []
        actual <- run plan (fixtureDevice calls EvaluationFailure (fail "unexpected witness lookup"))
        expectLeft "evaluation sentinel" actual
        trace <- reverse <$> readIORef calls
        assertBool
          "successful training performed optimizer callbacks before final evaluation failed"
          ("batch-gradient" `elem` trace)
        assertBool "the actual final evaluator was reached" (not (null trace) && last trace == "forward")
        length (filter (== "witness") trace) @?= 0
    , testCase "witness IO failure propagates without returning a successful artifact" $ do
        plan <- compiledPlan "her" "goal-reaching"
        calls <- newIORef []
        actual <-
          try (run plan (fixtureDevice calls NoFailure (ioError (userError "witness IO sentinel"))))
            :: IO (Either IOException (Either Text Execution.TrainerRun))
        case actual of
          Left err ->
            assertBool
              "original IO error remains visible"
              ("witness IO sentinel" `Text.isInfixOf` Text.pack (show err))
          Right value -> assertFailure ("witness IO failure became a trainer result: " <> show value)
        readIORef calls >>= assertSuccessfulTrace . reverse
    , testCase "ALE missing-ROM failure keeps the non-MLP branch outside device witness capture" $
        withSystemTempDirectory "jitml-ale-witness-boundary" $ \directory -> do
          plan <- compiledPlan "ppo" "atari-subset"
          calls <- newIORef []
          actual <-
            Execution.runTrainerEpisodesForPlan
              LinuxCPU
              (fixtureDevice calls NoFailure (fail "unexpected ALE witness lookup"))
              (Just (Text.pack (directory </> "absent.rom")))
              plan
          case actual of
            Left _ -> pure ()
            Right value -> assertFailure ("missing ROM unexpectedly produced a trainer result: " <> show value)
          readIORef calls >>= (@?= [])
    ]

-- These are raw public compiler inputs, never forged/record-updated compiled
-- plans. Public schedule floors remain in effect. The selected CPU name is an
-- expectation for the offline fixture witness, not a hardware assertion.
compiledPlan :: Text -> Text -> IO Plan.CompiledRlPlan
compiledPlan trainer environment =
  expectRight
    ( Plan.compileRlPlan
        Plan.TrainingPlan
          { Plan.trainingPlanTrainerKind = trainer
          , Plan.trainingPlanEnvironment = environment
          , Plan.trainingPlanSeed = 11
          , Plan.trainingPlanMaxEpisodeSteps = 1
          , Plan.trainingPlanEpisodeBudgetFloor = 1
          , Plan.trainingPlanVectorEnvironments = Just 1
          , Plan.trainingPlanRequestedTransitionFloor = Nothing
          , Plan.trainingPlanExactTransitionTarget = Nothing
          }
        (Plan.EvaluationPlan 2)
    )

run :: Plan.CompiledRlPlan -> MlpDevice -> IO (Either Text Execution.TrainerRun)
run plan device = Execution.runTrainerEpisodesForPlan LinuxCPU device Nothing plan

data FailurePoint = NoFailure | ProbeFailure | TrainingFailure | EvaluationFailure
  deriving stock (Eq)

fixtureDevice
  :: IORef [Text]
  -> FailurePoint
  -> IO (Either Text (Maybe Witness.DeviceExecutionWitness))
  -> MlpDevice
fixtureDevice calls failure witnessAction =
  pureReferenceMlpDevice
    { mlpdForward = \params observation -> do
        record "forward"
        pure $
          if failure == EvaluationFailure
            then Left "evaluation sentinel"
            else Right (fixedForward params observation)
    , mlpdBackward = \params _ _ -> do
        record "backward"
        pure (Right (fixedGradient params))
    , mlpdForwardBatch = \params observations -> do
        let probe = Mlp.paramShape params == Mlp.MlpShape 1 1 1
        record (if probe then "probe" else "batch-forward")
        pure $
          if probe && failure == ProbeFailure
            then Left "probe sentinel"
            else
              if not probe && failure == TrainingFailure
                then Left "training sentinel"
                else Right (fmap (Mlp.forwardOutput . fixedForward params) observations)
    , mlpdBatchGradient = \params _ -> do
        record "batch-gradient"
        pure (Right (fixedGradient params))
    , mlpdInputGradientBatch = \params pairs -> do
        record "input-gradient"
        pure (Right (replicate (length pairs) (VU.replicate (Mlp.mlpInputs (Mlp.paramShape params)) 0)))
    , mlpdExecutionWitness = record "witness" >> witnessAction
    }
 where
  record event = modifyIORef' calls (event :)

fixedForward :: Mlp.MlpParams -> VU.Vector Double -> Mlp.MlpForward
fixedForward params observation =
  Mlp.MlpForward
    { Mlp.forwardInput = observation
    , Mlp.forwardHiddenPre = VU.replicate (Mlp.mlpHidden shape) 0
    , Mlp.forwardHiddenAct = VU.replicate (Mlp.mlpHidden shape) 0
    , Mlp.forwardOutput = VU.replicate (Mlp.mlpOutputs shape) 0
    }
 where
  shape = Mlp.paramShape params

fixedGradient :: Mlp.MlpParams -> Mlp.MlpGradient
fixedGradient params =
  (Mlp.mlpZeroGradient (Mlp.paramShape params))
    { Mlp.gradB2 = VU.replicate (Mlp.mlpOutputs (Mlp.paramShape params)) 0.001
    }

assertActualBudget :: Plan.CompiledRlPlan -> Execution.TrainedArtifact -> Assertion
assertActualBudget plan artifact = do
  schedule <-
    maybe
      (assertFailure "fixture lost its compiled training schedule")
      pure
      (Plan.compiledRlSchedule plan)
  let counters = Execution.trainedArtifactCounters artifact
      evidence = Execution.trainedArtifactEvidence artifact
  Common.measuredEnvironmentTransitionCount counters
    @?= Plan.scheduleObservedEnvironmentSteps schedule
  assertBool
    "actual trainer counted positive optimizer applications"
    (Common.measuredOptimizerUpdateCount counters > 0)
  Evidence.evidenceUpdateCount evidence @?= Common.measuredOptimizerUpdateCount counters
  -- Reproduce the exact prepatch public evidence construction from the
  -- observed initial/final identities, actual counters and read identity. This
  -- comparison is evidence-field parity, not execution of the old trainer.
  unwitnessed <-
    expectRight
      ( Evidence.mkTrainingEvidence
          (Evidence.evidenceInitialWeightHash evidence)
          (Evidence.evidenceFinalWeightHash evidence)
          (Common.measuredOptimizerUpdateCount counters)
          (Evidence.evidenceDatasetShaAtRead evidence)
      )
  Evidence.evidenceDeviceWitness unwitnessed @?= Right Nothing
  Evidence.evidenceObservationsMatch evidence unwitnessed @?= True
  case Evidence.evidenceDeviceWitness evidence of
    Right (Just witness) -> Evidence.attachDeviceExecutionWitness witness unwitnessed @?= Right evidence
    other -> assertFailure ("successful fixture lost its returned witness: " <> show other)
  assertBool
    "the device callback changed actual trained parameter bytes"
    (Evidence.evidenceInitialWeightHash evidence /= Evidence.evidenceFinalWeightHash evidence)
  length (Framework.evaluationSetOutcomes (Execution.trainedArtifactEvaluationSet artifact))
    @?= Plan.compiledRlEvaluationEpisodes plan

assertSuccessfulTrace :: [Text] -> Assertion
assertSuccessfulTrace trace = do
  length (filter (== "witness") trace) @?= 1
  assertBool
    "training gradient callbacks happened before witness capture"
    ("batch-gradient" `elem` takeWhile (/= "witness") trace)
  assertBool
    "witness was captured after all numerical callbacks"
    (not (null trace) && last trace == "witness")

expectTrained :: Either Text Execution.TrainerRun -> IO Execution.TrainedArtifact
expectTrained answer = do
  result <- expectRight answer
  case result of
    Execution.Trained artifact -> pure artifact
    Execution.EvaluationOnly _ -> assertFailure "expected a successful raw trained artifact"

expectRight :: (Show err) => Either err value -> IO value
expectRight = either (assertFailure . show) pure

expectLeft :: Text -> Either Text Execution.TrainerRun -> Assertion
expectLeft expected answer =
  case answer of
    Left err ->
      assertBool
        ("expected " <> Text.unpack expected <> " in " <> Text.unpack err)
        (expected `Text.isInfixOf` err)
    Right result -> assertFailure ("expected producer failure, got " <> show result)
