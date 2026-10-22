{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

-- Real low numerical stages with explicitly noncanonical public schedule DTO
-- boundary fixtures. No real-provider, trained-row, budget or origin claim.
module PreparedNeuralAttempt (preparedNeuralAttemptTests) where

import Control.Concurrent (forkFinally)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import Control.Exception (AsyncException (..), SomeException, throwIO, try)
import Control.Monad (forM_, void)
import Data.Bits (xor)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef, writeIORef)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)
import GHC.Float (castDoubleToWord64, castWord64ToDouble)
import Test.Tasty (TestTree, testGroup, withResource)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Numerics.Mlp qualified as Mlp
import JitML.Numerics.MlpDevice (MlpDevice (..), pureReferenceMlpDevice)
import JitML.RL.Algorithms.Common qualified as Common
import JitML.RL.Algorithms.ContinuousTrainer qualified as Continuous
import JitML.RL.Algorithms.DqnTrainer qualified as Dqn
import JitML.RL.Algorithms.HerLoss qualified as HerLoss
import JitML.RL.Algorithms.HerTrainer qualified as Her
import JitML.RL.Algorithms.PpoTrainer qualified as Ppo
import JitML.RL.Algorithms.QrDqnTrainer qualified as Qr
import JitML.RL.PreparedNeuralAttempt qualified as N
import JitML.RL.ProductBudget qualified as Plan
import JitML.RL.TrainerConfiguration qualified as Config
import JitML.RL.TrainerObservation qualified as Observation

right :: (Show error) => Either error value -> IO value
right actual = case actual of
  Right value -> pure value
  Left reason -> assertFailure (show reason) >> fail "unreachable"

prepared :: N.NeuralPreparationResult -> IO N.PreparedNeuralAttempt
prepared result = case result of
  N.NeuralPreparationReady value -> pure value
  N.NeuralPreparationFailed failure -> assertFailure (show failure) >> fail "unreachable"

effective :: N.NeuralInitializationResult -> IO N.EffectiveNeuralAttempt
effective result = case result of
  N.NeuralInitializationReady value -> pure value
  N.NeuralInitializationFailed failure -> assertFailure (show failure) >> fail "unreachable"

returned :: N.NeuralTrainingResult -> IO N.NeuralReturnedData
returned result = case result of
  N.NeuralTrainingReturned pending -> pure (N.neuralPendingReturnedData pending)
  N.NeuralTrainingFailed failure -> assertFailure (show failure) >> fail "unreachable"
  N.NeuralReturnedButUnmaterializable failure -> assertFailure (show failure) >> fail "unreachable"
  N.NeuralReturnedBindingFailed _ failure -> assertFailure (show failure) >> fail "unreachable"

bits :: Mlp.MlpParams -> [Word64]
bits = map castDoubleToWord64 . Mlp.mlpParamsToFlat

-- Compile the genuine public inputs, then mark the deliberately bounded DTO
-- mutation explicitly. This is never called a validated public-minimum plan.
boundaryPlan :: Text -> Text -> Int -> IO Plan.CompiledRlPlan
boundaryPlan kind environment steps = do
  base <-
    right
      ( Plan.compileRlPlan
          (Plan.TrainingPlan kind environment 42 1 1 (Just 1) Nothing Nothing)
          (Plan.EvaluationPlan 1)
      )
  let bounded = case Plan.compiledRlSchedule base of
        Just Plan.OnPolicyTrainingSchedule {} ->
          Plan.OnPolicyTrainingSchedule (fromIntegral steps) (if steps == 0 then 0 else 1) (max 1 steps) 1 1
        Just Plan.FixedStepTrainingSchedule {} -> Plan.FixedStepTrainingSchedule (fromIntegral steps) steps 1
        Just Plan.HerTrainingSchedule {} -> Plan.HerTrainingSchedule (fromIntegral (steps * 6)) steps 6
        _ -> error "fixture public compiler selected an unexpected family"
  pure (base {Plan.compiledRlSchedule = Just bounded})

type Event = (Text, [Word64])

recordingDevice :: IORef [Event] -> MlpDevice
recordingDevice log_ =
  pureReferenceMlpDevice
    { mlpdForward = \params input -> record "forward" params >> mlpdForward pureReferenceMlpDevice params input
    , mlpdBackward = \params forward upstream -> record "backward" params >> mlpdBackward pureReferenceMlpDevice params forward upstream
    , mlpdForwardBatch = \params inputs -> record "forward-batch" params >> mlpdForwardBatch pureReferenceMlpDevice params inputs
    , mlpdBatchGradient = \params batch -> record "batch-gradient" params >> mlpdBatchGradient pureReferenceMlpDevice params batch
    , mlpdInputGradientBatch = \params batch -> record "input-gradient" params >> mlpdInputGradientBatch pureReferenceMlpDevice params batch
    , mlpdExecutionWitness =
        modifyIORef' log_ (("witness", []) :) >> pure (Left "unexpected witness query")
    }
 where
  record name params = modifyIORef' log_ ((name, bits params) :)

data Fixture = Fixture Text N.NeuralSnapshot N.NeuralReturnedData [Event]

fixtures :: IO [Fixture]
fixtures =
  traverse
    make
    [ ("ppo", "cartpole")
    , ("dqn", "cartpole")
    , ("qrdqn", "cartpole")
    , ("ddpg", "pendulum")
    , ("her", "goal-reaching")
    ]
 where
  make (kind, environment) = do
    plan <- boundaryPlan kind environment 0
    observed <- newIORef []
    initial <- N.prepareNeuralAttempt (recordingDevice observed) plan >>= prepared
    running <- N.initializePreparedNeural initial >>= effective
    raw <- N.runPreparedNeuralRaw running >>= returned
    events <- reverse <$> readIORef observed
    pure (Fixture kind (N.neuralEffectiveSnapshot running) raw events)

rawStatsCount :: Observation.ReturnedPolicy -> Int
rawStatsCount policy = case policy of
  Observation.ReturnedOnPolicy raw -> length (Common.rawTrainerStats raw)
  Observation.ReturnedDqn raw -> length (Common.rawTrainerStats raw)
  Observation.ReturnedQrDqn raw -> length (Common.rawTrainerStats raw)
  Observation.ReturnedContinuous raw -> length (Common.rawTrainerStats raw)
  Observation.ReturnedHer raw -> length (Common.rawTrainerStats raw)
  Observation.ReturnedArs _ -> error "excluded fixture family"

withConfig
  :: Config.NeuralTrainerConfiguration -> Observation.ReturnedPolicy -> IO Observation.ReturnedPolicy
withConfig configuration policy = case (configuration, policy) of
  (Config.OnPolicyConfiguration config, Observation.ReturnedOnPolicy raw) -> pure (Observation.ReturnedOnPolicy (raw {Common.rawTrainerConfig = config}))
  (Config.DqnConfiguration config, Observation.ReturnedDqn raw) -> pure (Observation.ReturnedDqn (raw {Common.rawTrainerConfig = config}))
  (Config.QrDqnConfiguration config, Observation.ReturnedQrDqn raw) -> pure (Observation.ReturnedQrDqn (raw {Common.rawTrainerConfig = config}))
  (Config.ContinuousConfiguration config, Observation.ReturnedContinuous raw) -> pure (Observation.ReturnedContinuous (raw {Common.rawTrainerConfig = config}))
  (Config.HerConfiguration config, Observation.ReturnedHer raw) -> pure (Observation.ReturnedHer (raw {Common.rawTrainerConfig = config}))
  _ -> assertFailure "fixture configuration family mismatch" >> fail "unreachable"

alterInitial
  :: (Mlp.MlpParams -> Mlp.MlpParams) -> Observation.ReturnedPolicy -> Observation.ReturnedPolicy
alterInitial change policy = case policy of
  Observation.ReturnedOnPolicy raw ->
    Observation.ReturnedOnPolicy
      (raw {Common.rawTrainerInitialParams = change (Common.rawTrainerInitialParams raw)})
  Observation.ReturnedDqn raw ->
    Observation.ReturnedDqn
      (raw {Common.rawTrainerInitialParams = change (Common.rawTrainerInitialParams raw)})
  Observation.ReturnedQrDqn raw ->
    Observation.ReturnedQrDqn
      (raw {Common.rawTrainerInitialParams = change (Common.rawTrainerInitialParams raw)})
  Observation.ReturnedContinuous raw ->
    Observation.ReturnedContinuous
      (raw {Common.rawTrainerInitialParams = change (Common.rawTrainerInitialParams raw)})
  Observation.ReturnedHer raw ->
    Observation.ReturnedHer
      (raw {Common.rawTrainerInitialParams = change (Common.rawTrainerInitialParams raw)})
  Observation.ReturnedArs _ -> error "excluded fixture family"

getFixture :: IO [Fixture] -> Text -> IO Fixture
getFixture get kind = do
  all_ <- get
  case [value | value@(Fixture name _ _ _) <- all_, name == kind] of
    [value] -> pure value
    _ -> assertFailure "exact fixture family absent/duplicated" >> fail "unreachable"

parallel :: IO value -> IO (value, value)
parallel action = do
  first <- newEmptyMVar
  second <- newEmptyMVar
  void (forkFinally action (putMVar first))
  void (forkFinally action (putMVar second))
  one <- takeMVar first >>= finish
  two <- takeMVar second >>= finish
  pure (one, two)
 where
  finish :: Either SomeException value -> IO value
  finish = right

assertFailureDetail
  :: N.NeuralAttemptStage -> N.NeuralFailureKind -> Text -> N.NeuralAttemptFailure -> Assertion
assertFailureDetail stage kind detail failure = do
  N.neuralFailureStage failure @?= stage
  N.neuralFailureKind failure @?= kind
  assertBool "specific failure detail" (detail `Text.isInfixOf` N.neuralFailureDetail failure)
  assertBool "only safely observed optional facts are printable" (not (null (show failure)))

-- Keep the total base drop 1 expression; do not add the extra package.
{- HLINT ignore preparedNeuralAttemptTests "Use drop1" -}
preparedNeuralAttemptTests :: TestTree
preparedNeuralAttemptTests = withResource fixtures (\_ -> pure ()) $ \get ->
  testGroup
    "opaque low prepared neural numerical attempts"
    [ testCase
        "all five actual raw families retain zero updates empty statistics and unchanged weights before evaluation"
        $ do
          all_ <- get
          length all_ @?= 5
          forM_ all_ $ \(Fixture _ snapshot raw _) -> do
            let policy = N.neuralReturnedPolicy raw
                counters = Observation.returnedCounters policy
            Common.observedEnvironmentTransitionCount counters @?= 0
            Common.observedOptimizerUpdateCount counters @?= 0
            rawStatsCount policy @?= 0
            bits (N.neuralReturnedExpectedInitialParams raw) @?= bits (N.neuralSnapshotInitialParams snapshot)
            Observation.returnedInitialWeights policy @?= Observation.returnedFinalWeights policy
            N.validateNeuralReturnedBinding
              (N.neuralReturnedExpectedConfiguration raw)
              (N.neuralReturnedExpectedInitialParams raw)
              policy
              @?= Right ()
    , testCase "the only zero-return callback is the real device probe with no final evaluator or witness" $ do
        all_ <- get
        forM_ all_ $ \(Fixture _ _ _ events) -> map fst events @?= ["forward-batch"]
    , testCase "each captured actual configuration is the same full shared resolved recipe" $ do
        all_ <- get
        forM_ all_ $ \(Fixture _ snapshot raw _) -> do
          recipe <- right (Config.resolveNeuralTrainerRecipe (N.neuralReturnedPlan raw))
          N.neuralSnapshotConfiguration snapshot @?= Config.neuralTrainerConfiguration recipe
          N.neuralReturnedExpectedConfiguration raw @?= Config.neuralTrainerConfiguration recipe
    , testCase "one actual PPO update uses captured initial parameters at its first training callback" $ do
        plan <- boundaryPlan "ppo" "cartpole" 2
        events <- newIORef []
        initial <- N.prepareNeuralAttempt (recordingDevice events) plan >>= prepared
        before <- readIORef events
        map fst before @?= ["forward-batch"]
        running <- N.initializePreparedNeural initial >>= effective
        readIORef events >>= (@?= before)
        raw <- N.runPreparedNeuralRaw running >>= returned
        after <- reverse <$> readIORef events
        case drop 1 after of
          (_, actual) : _ -> actual @?= bits (N.neuralSnapshotInitialParams (N.neuralEffectiveSnapshot running))
          [] -> assertFailure "actual PPO loop never called its supplied numerical device"
        Common.observedEnvironmentTransitionCount
          (Observation.returnedCounters (N.neuralReturnedPolicy raw))
          @?= 2
        assertBool
          "actual bounded PPO loop applied an update"
          (Common.observedOptimizerUpdateCount (Observation.returnedCounters (N.neuralReturnedPolicy raw)) > 0)
        assertBool "no witness is queried" (all ((/= "witness") . fst) after)
    , testCase
        "ordinary snapshot observers retain actual targets optimizer and RNG without exposing a capsule"
        $ do
          Fixture _ snapshot _ _ <- getFixture get "dqn"
          let observed =
                N.foldNeuralSnapshot
                  (const Nothing)
                  ( \actual ->
                      Just
                        ( bits (Dqn.dqnPreparedInitialParams actual)
                        , bits (Dqn.dqnPreparedTargetParams actual)
                        , Mlp.adamStep_ (Dqn.dqnPreparedAdam actual)
                        , Dqn.dqnPreparedStep actual
                        , length (Dqn.dqnPreparedReplay actual)
                        , show (Dqn.dqnPreparedGenerator actual)
                        )
                  )
                  (const Nothing)
                  (const Nothing)
                  (const Nothing)
                  snapshot
          case observed of
            Just (initial, target, optimizer, step, replay, generator) -> do
              initial @?= target
              optimizer @?= 0
              step @?= 0
              replay @?= 0
              assertBool "actual RNG observation exists, without using Show as identity" (not (null generator))
            Nothing -> assertFailure "actual DQN snapshot was another family"
    , testCase "SAC cold and effective stages retain actual warm work separately from zero scheduled work" $ do
        plan <- boundaryPlan "sac" "pendulum" 0
        events <- newIORef []
        initial <- N.prepareNeuralAttempt (recordingDevice events) plan >>= prepared
        N.neuralPreparationStage initial @?= N.NeuralCold
        let readContinuous =
              N.foldNeuralSnapshot
                (const Nothing)
                (const Nothing)
                (const Nothing)
                ( \actual ->
                    Just
                      ( Continuous.continuousPreparedStage actual
                      , Continuous.continuousPreparedWarmUpdateCount actual
                      , fmap bits (Continuous.continuousPreparedTargetActor actual)
                      , Mlp.adamStep_ (Continuous.continuousPreparedActorAdam actual)
                      )
                )
                (const Nothing)
        readContinuous (N.neuralPreparedSnapshot initial)
          @?= Just (Continuous.ContinuousCold, 0, Nothing, 0)
        before <- readIORef events
        running <- N.initializePreparedNeural initial >>= effective
        case readContinuous (N.neuralEffectiveSnapshot running) of
          Just (stage, warm, Just target, scheduled) -> do
            stage @?= Continuous.ContinuousEffective
            warm @?= 425 * 800
            target @?= bits (N.neuralSnapshotInitialParams (N.neuralEffectiveSnapshot running))
            scheduled @?= 0
          _ -> assertFailure "actual effective warm/target state absent"
        assertBool
          "actual cold snapshot stays available separately"
          (case N.neuralEffectiveColdSnapshot running of Just _ -> True; Nothing -> False)
        readIORef events >>= (@?= before)
        raw <- N.runPreparedNeuralRaw running >>= returned
        Common.observedOptimizerUpdateCount (Observation.returnedCounters (N.neuralReturnedPolicy raw))
          @?= 0
        Common.observedEnvironmentTransitionCount
          (Observation.returnedCounters (N.neuralReturnedPolicy raw))
          @?= 0
        bits (N.neuralReturnedExpectedInitialParams raw)
          @?= bits (N.neuralSnapshotInitialParams (N.neuralEffectiveSnapshot running))
    , testCase "a second initialization fails before any additional callback" $ do
        plan <- boundaryPlan "ppo" "cartpole" 0
        events <- newIORef []
        initial <- N.prepareNeuralAttempt (recordingDevice events) plan >>= prepared
        _ <- N.initializePreparedNeural initial >>= effective
        before <- readIORef events
        again <- N.initializePreparedNeural initial
        case again of
          N.NeuralInitializationFailed failure ->
            assertFailureDetail N.NeuralInitialization N.NeuralAlreadyConsumed "already been consumed" failure
          _ -> assertFailure "second initialization minted another effective stage"
        readIORef events >>= (@?= before)
    , testCase "a second continuation fails before a callback and cannot create another pending return" $ do
        plan <- boundaryPlan "ppo" "cartpole" 0
        events <- newIORef []
        initial <- N.prepareNeuralAttempt (recordingDevice events) plan >>= prepared
        running <- N.initializePreparedNeural initial >>= effective
        _ <- N.runPreparedNeuralRaw running >>= returned
        before <- readIORef events
        again <- N.runPreparedNeuralRaw running
        case again of
          N.NeuralTrainingFailed failure -> assertFailureDetail N.NeuralContinuation N.NeuralAlreadyConsumed "already been consumed" failure
          _ -> assertFailure "second continuation created another raw return"
        readIORef events >>= (@?= before)
    , testCase "concurrent initialization claims exactly one private stage" $ do
        plan <- boundaryPlan "ppo" "cartpole" 0
        initial <- N.prepareNeuralAttempt pureReferenceMlpDevice plan >>= prepared
        (first, second) <- parallel (N.initializePreparedNeural initial)
        let success value = case value of N.NeuralInitializationReady _ -> 1 :: Int; _ -> 0
            consumed value = case value of
              N.NeuralInitializationFailed failure -> N.neuralFailureKind failure == N.NeuralAlreadyConsumed
              _ -> False
        success first + success second @?= 1
        assertBool "the other claim is specifically consumed" (consumed first || consumed second)
    , testCase "concurrent continuation exposes exactly one actual zero raw return" $ do
        plan <- boundaryPlan "ppo" "cartpole" 0
        initial <- N.prepareNeuralAttempt pureReferenceMlpDevice plan >>= prepared
        running <- N.initializePreparedNeural initial >>= effective
        (first, second) <- parallel (N.runPreparedNeuralRaw running)
        let success value = case value of N.NeuralTrainingReturned _ -> 1 :: Int; _ -> 0
            consumed value = case value of
              N.NeuralTrainingFailed failure -> N.neuralFailureKind failure == N.NeuralAlreadyConsumed
              _ -> False
        success first + success second @?= 1
        assertBool "the other run is specifically consumed" (consumed first || consumed second)
    , testCase "actual numeric Left retains only observed initial facts and consumes the stage" $ do
        plan <- boundaryPlan "ppo" "cartpole" 1
        armed <- newIORef False
        trainingBatchFaults <- newIORef (0 :: Int)
        let device =
              pureReferenceMlpDevice
                { mlpdForwardBatch = \currentParams observations -> do
                    armedNow <- readIORef armed
                    if armedNow
                      then modifyIORef' trainingBatchFaults (+ 1) >> pure (Left "explicit actual low callback Left")
                      else mlpdForwardBatch pureReferenceMlpDevice currentParams observations
                }
        initial <- N.prepareNeuralAttempt device plan >>= prepared
        running <- N.initializePreparedNeural initial >>= effective
        readIORef trainingBatchFaults >>= (@?= 0)
        writeIORef armed True
        actual <- N.runPreparedNeuralRaw running
        case actual of
          N.NeuralTrainingFailed failure -> do
            assertFailureDetail
              N.NeuralContinuation
              N.NeuralRejected
              "explicit actual low callback Left"
              failure
            assertBool
              "initial parameters were actually captured"
              (case N.neuralFailureInitialParams (N.neuralFailureFacts failure) of Just _ -> True; Nothing -> False)
            N.neuralFailureReturnedCounters (N.neuralFailureFacts failure) @?= Nothing
          _ -> assertFailure "failed numeric callback fabricated an actual raw return"
        readIORef trainingBatchFaults >>= (@?= 1)
        again <- N.runPreparedNeuralRaw running
        case again of
          N.NeuralTrainingFailed failure -> N.neuralFailureKind failure @?= N.NeuralAlreadyConsumed
          _ -> assertFailure "failed continuation retried"
        readIORef trainingBatchFaults >>= (@?= 1)
    , testCase "lazy callback outer and Left faults are caught without retaining poisonous return thunks" $ do
        forM_ [error "lazy low callback Either", Left (error "lazy low callback Left")] $ \reply -> do
          plan <- boundaryPlan "ppo" "cartpole" 1
          armed <- newIORef False
          trainingBatchFaults <- newIORef (0 :: Int)
          let device =
                pureReferenceMlpDevice
                  { mlpdForwardBatch = \currentParams observations -> do
                      armedNow <- readIORef armed
                      if armedNow
                        then modifyIORef' trainingBatchFaults (+ 1) >> pure reply
                        else mlpdForwardBatch pureReferenceMlpDevice currentParams observations
                  }
          initial <- N.prepareNeuralAttempt device plan >>= prepared
          running <- N.initializePreparedNeural initial >>= effective
          readIORef trainingBatchFaults >>= (@?= 0)
          writeIORef armed True
          actual <- N.runPreparedNeuralRaw running
          case actual of
            N.NeuralTrainingFailed failure -> assertFailureDetail N.NeuralContinuation N.NeuralSynchronousFailure "lazy low callback" failure
            _ -> assertFailure "lazy callback fabricated a safely materialized raw return"
          readIORef trainingBatchFaults >>= (@?= 1)
          again <- N.runPreparedNeuralRaw running
          case again of
            N.NeuralTrainingFailed failure -> N.neuralFailureKind failure @?= N.NeuralAlreadyConsumed
            _ -> assertFailure "failed lazy continuation retried"
          readIORef trainingBatchFaults >>= (@?= 1)
    , testCase "async numeric cancellation propagates and the same continuation stays consumed" $ do
        plan <- boundaryPlan "ppo" "cartpole" 1
        armed <- newIORef False
        trainingBatchFaults <- newIORef (0 :: Int)
        let device =
              pureReferenceMlpDevice
                { mlpdForwardBatch = \currentParams observations -> do
                    armedNow <- readIORef armed
                    if armedNow
                      then modifyIORef' trainingBatchFaults (+ 1) >> throwIO ThreadKilled
                      else mlpdForwardBatch pureReferenceMlpDevice currentParams observations
                }
        initial <- N.prepareNeuralAttempt device plan >>= prepared
        running <- N.initializePreparedNeural initial >>= effective
        readIORef trainingBatchFaults >>= (@?= 0)
        writeIORef armed True
        attempted <-
          try (N.runPreparedNeuralRaw running) :: IO (Either AsyncException N.NeuralTrainingResult)
        case attempted of
          Left ThreadKilled -> pure ()
          _ -> assertFailure "async cancellation was swallowed"
        readIORef trainingBatchFaults >>= (@?= 1)
        again <- N.runPreparedNeuralRaw running
        case again of
          N.NeuralTrainingFailed failure -> N.neuralFailureKind failure @?= N.NeuralAlreadyConsumed
          _ -> assertFailure "cancelled continuation was retried"
        readIORef trainingBatchFaults >>= (@?= 1)
    , testCase "unknown ARS and ALE cases reject before the actual device probe" $ do
        base <- boundaryPlan "ppo" "cartpole" 0
        forM_
          [ ("unknown", "cartpole", "unknown RL trainer")
          , ("ars", "cartpole", "excludes ARS")
          , ("ppo", "atari-subset", "excludes the ALE")
          ]
          $ \(kind, environment, detail) -> do
            let plan =
                  base
                    { Plan.compiledRlTraining =
                        (Plan.compiledRlTraining base)
                          { Plan.trainingPlanTrainerKind = kind
                          , Plan.trainingPlanEnvironment = environment
                          }
                    }
                device =
                  pureReferenceMlpDevice
                    { mlpdForwardBatch = \_ _ -> assertFailure "excluded context probed device" >> fail "unreachable"
                    }
            actual <- N.prepareNeuralAttempt device plan
            case actual of
              N.NeuralPreparationFailed failure -> assertFailureDetail N.NeuralAdmission N.NeuralRejected detail failure
              _ -> assertFailure "excluded context prepared"
    , testCase "incompatible HER cartpole rejects before probing or forcing a malformed schedule" $ do
        base <- boundaryPlan "ppo" "cartpole" 0
        let plan =
              base
                { Plan.compiledRlTraining = (Plan.compiledRlTraining base) {Plan.trainingPlanTrainerKind = "her"}
                , Plan.compiledRlSchedule = Just (error "schedule must remain undemanded")
                }
            device =
              pureReferenceMlpDevice
                { mlpdForwardBatch = \_ _ -> assertFailure "incompatible context probed device" >> fail "unreachable"
                }
        actual <- N.prepareNeuralAttempt device plan
        case actual of
          N.NeuralPreparationFailed failure -> do
            N.neuralFailureStage failure @?= N.NeuralAdmission
            Just (N.neuralFailureDetail failure)
              @?= Plan.rlTrainerEnvironmentCompatibilityError "her" "cartpole"
          _ -> assertFailure "incompatible context prepared"
    , testCase "probe Left precedes a bottom schedule and returns only safely observed facts" $ do
        base <- boundaryPlan "ppo" "cartpole" 0
        let plan = base {Plan.compiledRlSchedule = Just (error "schedule must remain undemanded")}
            device = pureReferenceMlpDevice {mlpdForwardBatch = \_ _ -> pure (Left "explicit probe Left")}
        actual <- N.prepareNeuralAttempt device plan
        case actual of
          N.NeuralPreparationFailed failure -> do
            assertFailureDetail N.NeuralProbe N.NeuralRejected "explicit probe Left" failure
            N.neuralFailurePlan (N.neuralFailureFacts failure) @?= Nothing
          _ -> assertFailure "failed probe prepared a capsule"
    , testCase "successful probe precedes a captured schedule exception without exposing its input thunk" $ do
        base <- boundaryPlan "ppo" "cartpole" 0
        events <- newIORef []
        actual <-
          N.prepareNeuralAttempt
            (recordingDevice events)
            (base {Plan.compiledRlSchedule = Just (error "explicit low schedule bottom")})
        case actual of
          N.NeuralPreparationFailed failure -> do
            assertFailureDetail N.NeuralRecipe N.NeuralSynchronousFailure "explicit low schedule bottom" failure
            N.neuralFailurePlan (N.neuralFailureFacts failure) @?= Nothing
          _ -> assertFailure "undefined schedule produced a prepared capsule"
        readIORef events >>= (@?= ["forward-batch"]) . map fst
    , testCase
        "undefined supplied plan reports a safe diagnostic without retaining the same strict bottom"
        $ do
          actual <- N.prepareNeuralAttempt pureReferenceMlpDevice (error "explicit undefined supplied plan")
          case actual of
            N.NeuralPreparationFailed failure -> do
              assertFailureDetail
                N.NeuralAdmission
                N.NeuralSynchronousFailure
                "explicit undefined supplied plan"
                failure
              N.neuralFailureFacts failure @?= N.NeuralFailureFacts Nothing Nothing Nothing Nothing Nothing
            _ -> assertFailure "undefined input created a prepared capability"
    , testCase
        "data-only binding rejects changed inherited fields across all five actual returned families"
        $ do
          all_ <- get
          forM_ all_ $ \(Fixture _ _ raw _) -> do
            let expected = N.neuralReturnedExpectedConfiguration raw
                changed = case expected of
                  Config.OnPolicyConfiguration config -> Config.OnPolicyConfiguration (config {Ppo.ppoClipEps = Ppo.ppoClipEps config + 1})
                  Config.DqnConfiguration config -> Config.DqnConfiguration (config {Dqn.dqnUseDouble = not (Dqn.dqnUseDouble config)})
                  Config.QrDqnConfiguration config -> Config.QrDqnConfiguration (config {Qr.qrNumQuantiles = Qr.qrNumQuantiles config + 1})
                  Config.ContinuousConfiguration config -> Config.ContinuousConfiguration (config {Continuous.ctAlphaLr = Continuous.ctAlphaLr config + 1})
                  Config.HerConfiguration config ->
                    Config.HerConfiguration
                      ( config
                          { Her.herStrategy = case Her.herStrategy config of HerLoss.HerFuture -> HerLoss.HerEpisode; _ -> HerLoss.HerFuture
                          }
                      )
            modified <- withConfig changed (N.neuralReturnedPolicy raw)
            N.validateNeuralReturnedBinding expected (N.neuralReturnedExpectedInitialParams raw) modified
              @?= Left "prepared neural actual full configuration differs from its resolved recipe"
    , testCase "binary64 configuration equality preserves signed zero and exact NaN payload as data only" $ do
        Fixture _ _ raw _ <- getFixture get "ppo"
        case N.neuralReturnedExpectedConfiguration raw of
          Config.OnPolicyConfiguration config -> do
            let zero = Config.OnPolicyConfiguration (config {Ppo.ppoCountBeta = 0.0})
                negative = Config.OnPolicyConfiguration (config {Ppo.ppoCountBeta = -0.0})
                nan = Config.OnPolicyConfiguration (config {Ppo.ppoCountBeta = castWord64ToDouble 0x7ff8000000000001})
            same <- withConfig zero (N.neuralReturnedPolicy raw)
            other <- withConfig negative (N.neuralReturnedPolicy raw)
            nanData <- withConfig nan (N.neuralReturnedPolicy raw)
            N.validateNeuralReturnedBinding zero (N.neuralReturnedExpectedInitialParams raw) same @?= Right ()
            N.validateNeuralReturnedBinding zero (N.neuralReturnedExpectedInitialParams raw) other
              @?= Left "prepared neural actual full configuration differs from its resolved recipe"
            N.validateNeuralReturnedBinding nan (N.neuralReturnedExpectedInitialParams raw) nanData @?= Right ()
          _ -> assertFailure "PPO fixture family changed"
    , testCase
        "initial tensor binding rejects shape and payload changes without constructing a pending return"
        $ do
          Fixture _ _ raw _ <- getFixture get "ppo"
          let initial = N.neuralReturnedExpectedInitialParams raw
              expected = N.neuralReturnedExpectedConfiguration raw
              policy = N.neuralReturnedPolicy raw
              toggle value = castWord64ToDouble (castDoubleToWord64 value `xor` 1)
              changed params = params {Mlp.paramB1 = VU.map toggle (Mlp.paramB1 params)}
              reshaped params =
                params
                  { Mlp.paramShape = (Mlp.paramShape params) {Mlp.mlpInputs = Mlp.mlpInputs (Mlp.paramShape params) + 1}
                  }
          forM_ [changed, reshaped] $ \mutate ->
            N.validateNeuralReturnedBinding expected initial (alterInitial mutate policy)
              @?= Left "prepared neural returned initial parameters differ from the actual effective snapshot"
    , testCase
        "materializable nonfinite final data is not silently promoted by the unit-only binding predicate"
        $ do
          Fixture _ _ raw _ <- getFixture get "ppo"
          case N.neuralReturnedPolicy raw of
            Observation.ReturnedOnPolicy actual -> do
              -- This is an explicit mutated DATA copy, not an actual producer
              -- result or a route into NeuralPendingReturn.
              let final = Common.rawTrainerFinalParams actual
                  synthetic =
                    Observation.ReturnedOnPolicy
                      ( actual
                          { Common.rawTrainerFinalParams =
                              final {Mlp.paramB2 = VU.replicate (VU.length (Mlp.paramB2 final)) (0 / 0)}
                          }
                      )
              N.validateNeuralReturnedBinding
                (N.neuralReturnedExpectedConfiguration raw)
                (N.neuralReturnedExpectedInitialParams raw)
                synthetic
                @?= Right ()
              assertBool
                "materializable NaN data is inspectable without any eligibility claim"
                (not (null (show synthetic)))
            _ -> assertFailure "PPO fixture family changed"
    ]
