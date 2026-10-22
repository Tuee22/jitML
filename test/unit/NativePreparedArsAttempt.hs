{-# LANGUAGE OverloadedStrings #-}

-- Real full canonical host-linear numerical executions, not MLP/provider,
-- parent-authentication, durable publication, convergence or qualification proof.
-- The temporary source is actually observed and did not build this executable.
module NativePreparedArsAttempt (nativePreparedArsAttemptTests) where

import Control.Concurrent (forkFinally)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import Control.Exception (AsyncException (ThreadKilled), bracketOnError, throwIO, try)
import Control.Monad (forM, forM_, void)
import Data.ByteString qualified as BS
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (find)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)
import GHC.Float (castDoubleToWord64)
import System.Directory (createDirectoryIfMissing, getTemporaryDirectory, removePathForcibly)
import System.FilePath ((</>))
import System.IO.Temp (createTempDirectory)
import Test.Tasty (TestTree, testGroup, withResource)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Execution.ProducerObservation qualified as Producer
import JitML.Numerics.MlpDevice (MlpDevice (..), pureReferenceMlpDevice)
import JitML.Plan.NativeChildAssociation qualified as Association
import JitML.Plan.NativeSingletonPlan qualified as Native
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.NativePreparedArsAttempt qualified as High
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.Product.SourceDigest qualified as Source
import JitML.RL.Algorithms.ArsTrainer qualified as Ars
import JitML.RL.Algorithms.Common qualified as Common
import JitML.RL.EpisodeEnvelope qualified as Episode
import JitML.RL.NativeReturnEvaluation qualified as Return
import JitML.RL.NativeReturnReferences qualified as Ref
import JitML.RL.ProductBudget qualified as Budget
import JitML.RL.TrainerExecution qualified as Legacy
import JitML.RL.TrainerObservation qualified as Observation
import JitML.Substrate (Substrate (..))
import JitML.Training.Budget qualified as Completion

right :: (Show error) => Either error value -> IO value
right result = case result of
  Right value -> pure value
  Left detail -> assertFailure (show detail) >> fail "unreachable"
failed :: High.NativeArsFailure -> IO value
failed problem = assertFailure (Text.unpack (High.nativeArsFailureDetail problem)) >> fail "unreachable"
selected :: Either High.NativeArsFailure value -> IO value
selected = either failed pure
begun :: High.NativeArsBeginResult -> IO High.NativeArsBegun
begun result = case result of
  High.NativeArsBegunReady value -> pure value
  High.NativeArsBeginFailed failure -> failed failure
prepared :: High.NativeArsPreparationResult -> IO High.NativeArsPrepared
prepared result = case result of
  High.NativeArsPreparationReady value -> pure value
  High.NativeArsPreparationFailed failure -> failed failure
ready :: High.NativeArsInitialResult -> IO High.NativeArsReadyToTrain
ready result = case result of
  High.NativeArsInitialReady value -> pure value
  High.NativeArsInitialFailed failure -> failed failure
pending :: High.NativeArsTrainingResult -> IO High.NativeArsPendingFinal
pending result = case result of
  High.NativeArsTrainingReturned value -> pure value
  High.NativeArsTrainingFailed failure -> failed failure
  High.NativeArsReturnedButUnmaterializable failure -> failed failure
  High.NativeArsReturnedBindingFailed _ failure -> failed failure
finished :: High.NativeArsFinalResult -> IO High.NativeArsFinalObservation
finished result = case result of
  High.NativeArsFinished value -> pure value
  High.NativeArsFinishRejected _ failure -> failed failure
origin :: High.NativeArsFinalObservation -> IO High.NativeArsExecutionOrigin
origin = either failed pure . High.nativeArsFinalOrigin

index :: Int -> IO Cohort.NativeSeedIndex
index number = case find ((== number) . Cohort.nativeSeedIndexValue) Cohort.nativeSeedIndices of
  Just value -> pure value
  Nothing -> assertFailure "canonical seed index absent" >> fail "unreachable"
batch :: Substrate -> IO Cohort.NativeRlCohortBatch
batch = right . Cohort.mkCanonicalNativeRlCohorts
child :: Int -> IO High.NativeArsChildData
child ordinal = do
  whole <- batch LinuxCPU
  row <- selected (High.selectNativeArsRowData whole "ARS/mountain-car")
  actualIndex <- index ordinal
  selected (High.selectNativeArsChildData row actualIndex)

canonicalSha :: Text -> Bool
canonicalSha value = Text.length value == 64 && Text.all (`elem` ("0123456789abcdef" :: String)) value
bits :: VU.Vector Double -> [Word64]
bits = map castDoubleToWord64 . VU.toList
configBits :: Ars.ArsTrainConfig -> ([Int], [Word64])
configBits (Ars.ArsTrainConfig seed iterations directions topB alpha noise horizon actions observations) =
  ( [seed, iterations, directions, topB, horizon, actions, observations]
  , map castDoubleToWord64 [alpha, noise]
  )

-- Lossless observed-field projection only, not a duplicate training algorithm.
-- All Double leaves become Word64; sizes/counts/indices stay integral.
rawProjection :: Ars.ArsTrainObservation -> Text
rawProjection (Common.RawTrainerResult initial final statistics counters config) =
  Text.pack
    ( show
        ( bits initial
        , bits final
        , map observationBits statistics
        , (Common.observedEnvironmentTransitionCount counters, Common.observedOptimizerUpdateCount counters)
        , configBits config
        )
    )
 where
  observationBits observation =
    let stat = Ars.arsObservationStatistic observation
        step = Ars.arsObservationAppliedStep observation
     in (
          ( Ars.arsIterIndex stat
          , map castDoubleToWord64 [Ars.arsIterMeanReturn stat, Ars.arsIterBestReturn stat]
          )
        ,
          ( configBits (Ars.arsStepConfig step)
          , Ars.arsStepNumericalRuntime step
          , Ars.arsStepIndex step
          , bits (Ars.arsStepThetaBefore step)
          , bits (Ars.arsStepThetaAfter step)
          , map bits (Ars.arsStepSampledDirections step)
          , [ ( (castDoubleToWord64 plus, psteps)
              , (castDoubleToWord64 minus, msteps)
              , map castDoubleToWord64 delta
              )
            | ((plus, psteps), (minus, msteps), delta) <- Ars.arsStepEvaluatedPerturbations step
            ]
          , [ (castDoubleToWord64 plus, castDoubleToWord64 minus, map castDoubleToWord64 delta)
            | (plus, minus, delta) <- Ars.arsStepKeptDirections step
            ]
          , map
              castDoubleToWord64
              [Ars.arsStepNoiseStd step, Ars.arsStepReturnStdDev step, Ars.arsStepScale step]
          , map castDoubleToWord64 (Ars.arsStepUpdateDirection step)
          , Ars.arsStepObservedTransitions step
          )
        )

data Run = Run
  { runChild :: High.NativeArsChildData
  , runBegun :: High.NativeArsBegun
  , runPrepared :: High.NativeArsPrepared
  , runReady :: High.NativeArsReadyToTrain
  , runPending :: High.NativeArsPendingFinal
  , runFinal :: High.NativeArsFinalObservation
  }
data Concurrent = Concurrent Run High.NativeArsFailure

data Resources = Resources
  { fixtureRoot :: FilePath
  , fixtureDirect :: Run
  , fixtureConcurrent :: Concurrent
  , fixtureOldRaw :: Ars.ArsTrainObservation
  , fixtureOldEvaluation :: Observation.RawEvaluation
  , fixtureOldMlpCalls :: Int
  , fixtureAuxiliary :: Run
  , fixtureParentInvocation :: Completion.ProductScenarioInvocation
  }

makeReady
  :: High.NativeArsChildData
  -> High.NativeArsContextInput
  -> IO (High.NativeArsBegun, High.NativeArsPrepared, High.NativeArsReadyToTrain)
makeReady selectedChild context = do
  start <- High.beginNativeArsAttempt selectedChild context >>= begun
  actualPrepared <- High.prepareNativeArsAttempt start >>= prepared
  let snapshot = High.nativeArsPreparedSnapshot actualPrepared
  -- Actually inspect the prepared fields before calling the same continuation.
  void (pure $! length (bits (Ars.arsPreparedInitialParams snapshot)))
  actualReady <- High.evaluateNativeArsInitial actualPrepared >>= ready
  pure (start, actualPrepared, actualReady)
makeRun :: High.NativeArsChildData -> High.NativeArsContextInput -> IO Run
makeRun selectedChild context = do
  (start, actualPrepared, actualReady) <- makeReady selectedChild context
  actualPending <- High.continueNativeArsTraining actualReady >>= pending
  let raw = High.nativeArsReturnedPolicy (High.nativeArsPendingReturned actualPending)
  void (pure $! Text.length (rawProjection raw))
  actualFinal <- High.finishNativeArsAttempt actualPending >>= finished
  _ <- origin actualFinal
  pure (Run selectedChild start actualPrepared actualReady actualPending actualFinal)

parallel :: IO value -> IO (value, value)
parallel action = do
  one <- newEmptyMVar
  two <- newEmptyMVar
  void (forkFinally action (putMVar one))
  void (forkFinally action (putMVar two))
  first <- takeMVar one >>= either throwIO pure
  second <- takeMVar two >>= either throwIO pure
  pure (first, second)

makeConcurrent :: FilePath -> High.NativeArsChildData -> IO Concurrent
makeConcurrent root selectedChild = do
  (start, actualPrepared, actualReady) <- makeReady selectedChild (High.DirectNativeArsLocal root)
  (one, two) <- parallel (High.continueNativeArsTraining actualReady)
  let good = [value | High.NativeArsTrainingReturned value <- [one, two]]
      bad = [failure | High.NativeArsTrainingFailed failure <- [one, two]]
  case (good, bad) of
    ([actualPending], [failure]) -> do
      High.nativeArsFailureKind failure @?= High.NativeArsAlreadyConsumed
      -- Real controlled source observation mismatch after an actual raw return;
      -- no fabricated evaluator or numerical result enters a capability.
      let sourceFile = root </> "jitml.cabal"
      before <- BS.readFile sourceFile
      BS.writeFile sourceFile (before <> "changed after actual return\n")
      actualFinal <- High.finishNativeArsAttempt actualPending >>= finished
      BS.writeFile sourceFile before
      pure
        (Concurrent (Run selectedChild start actualPrepared actualReady actualPending actualFinal) failure)
    _ ->
      assertFailure "concurrent continuation did not have exactly one actual run" >> fail "unreachable"

makeInvocation :: High.NativeArsChildData -> Text -> IO Completion.ProductScenarioInvocation
makeInvocation selectedChild executable = do
  let row = High.nativeArsChildRow selectedChild
      parent =
        Cohort.nativeRlSeedPlanSingleton (Cohort.nativeRlCohortServingChild (High.nativeArsRowCohort row))
  right
    ( Completion.mkProductScenarioInvocation
        "offline-native-ars-controls"
        (High.nativeArsRowId row)
        (Native.nativeSingletonPlanId parent)
        LinuxCPU
        (Text.replicate 64 "3")
        executable
        (Text.replicate 64 "4")
    )

acquire :: IO Resources
acquire = do
  temporary <- getTemporaryDirectory
  bracketOnError (createTempDirectory temporary "jitml-native-ars-controls-") removePathForcibly $ \root -> do
    forM_ Source.sourceDigestDirectoryRoots (createDirectoryIfMissing True . (root </>))
    forM_
      Source.sourceDigestFileRoots
      ( \name -> BS.writeFile (root </> name) "actual observed source fixture, not executable build source\n"
      )
    selectedChild <- child 0
    direct <- makeRun selectedChild (High.DirectNativeArsLocal root)
    concurrent <- makeConcurrent root selectedChild
    calls <- newIORef (0 :: Int)
    let forbidden :: IO value
        forbidden = modifyIORef' calls (+ 1) >> fail "actual ARS dispatcher unexpectedly used a neural operation"
        poison =
          pureReferenceMlpDevice
            { mlpdForward = \_ _ -> forbidden
            , mlpdForwardBatch = \_ _ -> forbidden
            , mlpdBackward = \_ _ _ -> forbidden
            , mlpdBatchGradient = \_ _ -> forbidden
            , mlpdInputGradientBatch = \_ _ -> forbidden
            , mlpdExecutionWitness = forbidden
            }
    old <-
      Legacy.runRawTrainerObservationForPlan
        LinuxCPU
        poison
        Nothing
        (High.nativeArsChildCompiledPlan selectedChild)
    (oldRaw, oldEvaluation) <- case old of
      Observation.TrainerReturned observed -> case Observation.observedPolicy observed of
        Observation.ReturnedArs raw -> pure (raw, Observation.observedEvaluation observed)
        _ -> assertFailure "actual canonical old dispatcher changed trainer" >> fail "unreachable"
      Observation.TrainerDidNotReturn failure -> assertFailure (show failure) >> fail "unreachable"
      Observation.TrainerEvaluationOnly _ -> assertFailure "actual ARS dispatcher returned evaluation only" >> fail "unreachable"
    countCalls <- readIORef calls
    selectedAux <- child 1
    invocation <-
      makeInvocation
        selectedAux
        (Producer.producerExecutableFileSha256 (High.nativeArsBegunBeforeProcess (runBegun direct)))
    auxiliary <-
      makeRun selectedAux (High.SuppliedNativeArsParent invocation (High.ObserveNativeArsSourceRoot root))
    pure (Resources root direct concurrent oldRaw oldEvaluation countCalls auxiliary invocation)

release :: Resources -> IO ()
release = removePathForcibly . fixtureRoot

actualRaw :: Run -> Ars.ArsTrainObservation
actualRaw = High.nativeArsReturnedPolicy . High.nativeArsPendingReturned . runPending
initialEvaluation :: Run -> Return.RawNativeReturnEvaluation
initialEvaluation = High.nativeArsReadyInitialEvaluation . runReady
finalEvaluation :: Run -> IO Return.RawNativeReturnEvaluation
finalEvaluation actual = case High.nativeArsFinalEvaluation (runFinal actual) of
  Just value -> pure value
  Nothing -> assertFailure "actual final evaluation unavailable" >> fail "unreachable"
assertLeft :: Text -> Either Text value -> Assertion
assertLeft fragment actual = case actual of
  Left detail -> assertBool (Text.unpack detail) (fragment `Text.isInfixOf` detail)
  Right _ -> assertFailure "data predicate accepted the exact mutation"
assertFailureAt
  :: High.NativeArsStage -> High.NativeArsFailureKind -> Text -> High.NativeArsFailure -> Assertion
assertFailureAt stage kind fragment actual = do
  High.nativeArsFailureStage actual @?= stage
  High.nativeArsFailureKind actual @?= kind
  assertBool
    (Text.unpack (High.nativeArsFailureDetail actual))
    (fragment `Text.isInfixOf` High.nativeArsFailureDetail actual)

nativePreparedArsAttemptTests :: TestTree
nativePreparedArsAttemptTests = withResource acquire release $ \get ->
  testGroup
    "native canonical prepared host ARS phases"
    [ testCase "four actual canonical rows preserve twenty full singleton children in every lane" $ do
        forM_ [LinuxCPU, LinuxCUDA, AppleSilicon] $ \lane -> do
          whole <- batch lane
          selectedRows <- forM (Cohort.nativeRlCohortBatchPlans whole) $ \cohort -> do
            let rowName = Matrix.rowId (Cohort.nativeRlCohortPlanRow cohort)
            case High.selectNativeArsRowData whole rowName of
              Left failure -> do
                High.nativeArsFailureStage failure @?= High.NativeArsSelection
                pure []
              Right row -> do
                High.nativeArsRowId row @?= rowName
                High.nativeArsRowBatch row @?= whole
                forM Cohort.nativeSeedIndices $ \ordinal -> do
                  actual <- selected (High.selectNativeArsChildData row ordinal)
                  let plan = High.nativeArsChildSeedPlan actual
                  Cohort.nativeRlSeedPlanIndex plan @?= ordinal
                  Native.nativeSingletonSubstrate (Cohort.nativeRlSeedPlanSingleton plan) @?= lane
                  Budget.compiledRlSeed (High.nativeArsChildCompiledPlan actual)
                    @?= 42
                    + Cohort.nativeSeedIndexValue ordinal
          length (filter (not . null) selectedRows) @?= 4
          sum (map length selectedRows) @?= 20
    , testCase
        "actual begin retains executable process source and fresh context before numerical preparation"
        $ do
          resource <- get
          let actual = fixtureDirect resource
              start = runBegun actual
              before = High.nativeArsBegunBeforeProcess start
          assertBool
            "actual FILE SHA is not canonical"
            (canonicalSha (Producer.producerExecutableFileSha256 before))
          assertBool "actual process ID absent" (Producer.producerProcessId before > 0)
          assertBool
            "actual executable byte count absent"
            (Producer.producerExecutableFileByteCount before > 0)
          assertBool
            "actual kernel observation absent"
            (not (Text.null (Producer.producerKernelMachine before)))
          assertBool "OS attempt identity absent" (canonicalSha (High.nativeArsBegunAttemptId start))
          assertBool "bound context digest absent" (canonicalSha (High.nativeArsBegunContextDigest start))
          stamp <- Source.computeSourceStampIn (fixtureRoot resource) >>= right
          High.nativeArsBegunSourceCoverage start @?= High.NativeArsObservedLocal (fixtureRoot resource) stamp
          Producer.producerObservedSource before @?= Just (fixtureRoot resource, stamp)
          High.nativeArsContextAssociation (High.nativeArsBegunContext start) @?= Nothing
    , testCase "the actual prepared snapshot is the raw initial state and first applied theta" $ do
        resource <- get
        let actual = fixtureDirect resource
            snapshot = High.nativeArsPreparedSnapshot (runPrepared actual)
            raw = actualRaw actual
        bits (Ars.arsPreparedInitialParams snapshot) @?= bits (Common.rawTrainerInitialParams raw)
        configBits (Ars.arsPreparedConfig snapshot) @?= configBits (Common.rawTrainerConfig raw)
        case Common.rawTrainerStats raw of
          first : _ ->
            bits (Ars.arsStepThetaBefore (Ars.arsObservationAppliedStep first))
              @?= bits (Ars.arsPreparedInitialParams snapshot)
          [] -> assertFailure "full canonical ARS returned no actual step"
        High.validateNativeArsReturnedBinding snapshot raw @?= Right ()
        Ars.validateArsTrainObservation raw @?= Right ()
    , testCase
        "one full canonical return retains all perturbations applied steps and measured physical work"
        $ do
          resource <- get
          let actual = fixtureDirect resource
              raw = actualRaw actual
              config = Common.rawTrainerConfig raw
              counters = Common.rawTrainerCounters raw
          Ars.arsIterations config @?= 50
          Ars.arsNumDirections config @?= 16
          Ars.arsMaxEpisodeSteps config @?= 200
          length (Common.rawTrainerStats raw) @?= 50
          expected <- case Budget.compiledRlSchedule (High.nativeArsChildCompiledPlan (runChild actual)) of
            Just schedule -> pure (Budget.scheduleObservedEnvironmentSteps schedule)
            Nothing -> assertFailure "canonical child schedule absent" >> fail "unreachable"
          Common.observedEnvironmentTransitionCount counters @?= expected
          expected @?= 320000
          Common.observedOptimizerUpdateCount counters @?= 50
          forM_ (zip [0 :: Int ..] (Common.rawTrainerStats raw)) $ \(ordinal, observation) -> do
            let step = Ars.arsObservationAppliedStep observation
            Ars.arsStepIndex step @?= ordinal
            length (Ars.arsStepSampledDirections step) @?= 16
            length (Ars.arsStepEvaluatedPerturbations step) @?= 16
            length (Ars.arsStepKeptDirections step) @?= Ars.arsTopB config
            Ars.validateArsAppliedStep step @?= Right ()
    , testCase "same runtime old public dispatcher preserves every raw bit without touching any MLP seam" $ do
        resource <- get
        rawProjection (fixtureOldRaw resource) @?= rawProjection (actualRaw (fixtureDirect resource))
        fixtureOldMlpCalls resource @?= 0
        final <- finalEvaluation (fixtureDirect resource)
        case fixtureOldEvaluation resource of
          Observation.EvaluationReturned episodes -> do
            let old =
                  [ ( Episode.simEpisodeIndex ep
                    , Episode.simEpisodeSteps ep
                    , castDoubleToWord64 (Episode.simEpisodeReward ep)
                    , Episode.simEpisodeDone ep
                    )
                  | ep <- episodes
                  ]
                current =
                  [ ( Ref.nativeReturnEpisodeId ep
                    , Ref.nativeReturnEpisodeSteps ep
                    , castDoubleToWord64 (Ref.nativeReturnEpisodeReward ep)
                    , Ref.nativeReturnEpisodeTerminated ep
                    )
                  | ep <- Return.nativeEvaluationEpisodes final
                  ]
            old @?= current
          _ -> assertFailure "actual full old ARS dispatcher did not retain return evaluations"
    , testCase "raw policy precedes final scoring and both evaluations bind its exact actual parameters" $ do
        resource <- get
        let actual = fixtureDirect resource
            raw = actualRaw actual
            initial = initialEvaluation actual
        final <- finalEvaluation actual
        High.validateNativeArsEvaluationData (runChild actual) initial @?= Right ()
        High.validateNativeArsEvaluationData (runChild actual) final @?= Right ()
        case (Return.nativeEvaluationPolicy initial, Return.nativeEvaluationPolicy final) of
          ( Return.NativeArsHostEvaluation initialConfig theta0
            , Return.NativeArsHostEvaluation finalConfig thetaN
            ) -> do
              configBits initialConfig @?= configBits (Common.rawTrainerConfig raw)
              configBits finalConfig @?= configBits (Common.rawTrainerConfig raw)
              bits theta0 @?= bits (Common.rawTrainerInitialParams raw)
              bits thetaN @?= bits (Common.rawTrainerFinalParams raw)
          _ -> assertFailure "actual host evaluation changed policy family"
        forM_ [initial, final] $ \evaluated -> do
          length (Return.nativeEvaluationEpisodes evaluated) @?= 20
          Return.nativeEvaluationForwards evaluated @?= []
          Return.nativeEvaluationWork evaluated
            @?= Return.NativeCompleteWork
              (sum (map (toInteger . Ref.nativeReturnEpisodeSteps) (Return.nativeEvaluationEpisodes evaluated)))
    , testCase "unit-only completeness accepts finite low scores without creating a stage or origin" $ do
        resource <- get
        let actual = fixtureDirect resource
            observed = initialEvaluation actual
            changed =
              observed
                { Return.nativeEvaluationEpisodes =
                    [ep {Ref.nativeReturnEpisodeReward = -1.0e100} | ep <- Return.nativeEvaluationEpisodes observed]
                }
        High.validateNativeArsEvaluationData (runChild actual) changed @?= Right ()
        -- This copy has no path to Ready/Pending/Origin; actual observed data
        -- remains unchanged, without any required movement or reward target.
        Return.nativeEvaluationEpisodes observed
          @?= Return.nativeEvaluationEpisodes
            (High.nativeArsReturnedInitialEvaluation (High.nativeArsPendingReturned (runPending actual)))
    , testCase "all consumed actual stages reject reuse instead of repeating work" $ do
        resource <- get
        let actual = fixtureDirect resource
        a <- High.prepareNativeArsAttempt (runBegun actual)
        case a of
          High.NativeArsPreparationFailed failure ->
            assertFailureAt
              High.NativeArsPreparation
              High.NativeArsAlreadyConsumed
              "already been consumed"
              failure
          _ -> assertFailure "preparation reran"
        b <- High.evaluateNativeArsInitial (runPrepared actual)
        case b of
          High.NativeArsInitialFailed failure ->
            assertFailureAt
              High.NativeArsInitialEvaluation
              High.NativeArsAlreadyConsumed
              "already been consumed"
              failure
          _ -> assertFailure "initial scoring reran"
        c <- High.continueNativeArsTraining (runReady actual)
        case c of
          High.NativeArsTrainingFailed failure ->
            assertFailureAt High.NativeArsTraining High.NativeArsAlreadyConsumed "already been consumed" failure
          _ -> assertFailure "actual numerical run repeated"
        d <- High.finishNativeArsAttempt (runPending actual)
        case d of
          High.NativeArsFinishRejected kept failure -> do
            rawProjection (High.nativeArsReturnedPolicy kept) @?= rawProjection (actualRaw actual)
            assertFailureAt
              High.NativeArsFinalEvaluation
              High.NativeArsAlreadyConsumed
              "already been consumed"
              failure
          _ -> assertFailure "final observation reran"
    , testCase "a genuine missing source path fails before any prepared or returned state exists" $ do
        resource <- get
        selectedChild <- child 0
        result <-
          High.beginNativeArsAttempt
            selectedChild
            (High.DirectNativeArsLocal (fixtureRoot resource </> "genuinely-absent-source-root"))
        case result of
          High.NativeArsBeginFailed failure -> do
            assertFailureAt High.NativeArsBeginning High.NativeArsRejected "missing code root" failure
            case High.nativeArsFailureSnapshot failure of
              Nothing -> pure ()
              Just _ -> assertFailure "source failure invented initial state"
            High.nativeArsFailureInitialEvaluation failure @?= Nothing
            High.nativeArsFailureEvaluation failure @?= Nothing
          _ -> assertFailure "missing actual source root created a capability"
    , testCase "concurrent stages allow one actual run and source denial retains its complete raw data" $ do
        resource <- get
        let Concurrent actual consumedFailure = fixtureConcurrent resource
        High.nativeArsFailureKind consumedFailure @?= High.NativeArsAlreadyConsumed
        rawProjection (actualRaw actual) @?= rawProjection (actualRaw (fixtureDirect resource))
        case High.nativeArsFinalOrigin (runFinal actual) of
          Left failure -> assertFailureAt High.NativeArsAfterProcess High.NativeArsRejected "SourceObservation" failure
          Right _ -> assertFailure "changed actual source was accepted as a stable origin"
        final <- finalEvaluation actual
        Return.nativeEvaluationStatus final @?= Return.NativeEvaluationComplete
        -- Cheap actual stage races do not shorten or add a numerical run.
        selectedChild <- child 0
        start <-
          High.beginNativeArsAttempt selectedChild (High.DirectNativeArsLocal (fixtureRoot resource))
            >>= begun
        (one, two) <- parallel (High.prepareNativeArsAttempt start)
        case ( [x | High.NativeArsPreparationReady x <- [one, two]]
             , [f | High.NativeArsPreparationFailed f <- [one, two]]
             ) of
          ([p], [f]) -> do
            High.nativeArsFailureKind f @?= High.NativeArsAlreadyConsumed
            (first, second) <- parallel (High.evaluateNativeArsInitial p)
            length [() | High.NativeArsInitialReady _ <- [first, second]] @?= 1
            case [bad | High.NativeArsInitialFailed bad <- [first, second]] of
              [bad] -> High.nativeArsFailureKind bad @?= High.NativeArsAlreadyConsumed
              _ -> assertFailure "initial race did not reject one claim"
          _ -> assertFailure "preparation race minted zero or two capsules"
    , testCase "supplied source remains explicitly unobserved and a parsed context alone is not execution" $ do
        resource <- get
        selectedChild <- child 0
        stamp <- Source.computeSourceStampIn (fixtureRoot resource) >>= right
        start <-
          High.beginNativeArsAttempt
            selectedChild
            ( High.SuppliedNativeArsParent
                (fixtureParentInvocation resource)
                (High.SuppliedNativeArsParentSource stamp)
            )
            >>= begun
        High.nativeArsBegunSourceCoverage start @?= High.NativeArsUnauthenticatedParentSource stamp
        Producer.producerObservedSource (High.nativeArsBegunBeforeProcess start) @?= Nothing
        case High.nativeArsContextAssociation (High.nativeArsBegunContext start) of
          Just association -> Association.nativeAssociationInvocation association @?= fixtureParentInvocation resource
          Nothing -> assertFailure "supplied association data was discarded"
    , testCase
        "actual auxiliary seed forty three origin preserves the unchanged parent invocation association"
        $ do
          resource <- get
          let actual = fixtureAuxiliary resource
              selectedChild = runChild actual
              seedPlan = High.nativeArsChildSeedPlan selectedChild
              singleton = Cohort.nativeRlSeedPlanSingleton seedPlan
          actualOrigin <- origin (runFinal actual)
          High.nativeArsOriginChild actualOrigin @?= selectedChild
          High.nativeArsOriginAttemptId actualOrigin @?= High.nativeArsBegunAttemptId (runBegun actual)
          High.nativeArsOriginContextDigest actualOrigin
            @?= High.nativeArsBegunContextDigest (runBegun actual)
          High.nativeArsOriginSourceCoverage actualOrigin
            @?= High.nativeArsBegunSourceCoverage (runBegun actual)
          High.nativeArsOriginNumericalRuntime actualOrigin @?= Ars.arsNativeNumericalRuntime
          Budget.compiledRlSeed (High.nativeArsChildCompiledPlan selectedChild) @?= 43
          Ars.arsSeed (Common.rawTrainerConfig (actualRaw actual)) @?= 43
          case High.nativeArsContextAssociation (High.nativeArsOriginContext actualOrigin) of
            Nothing -> assertFailure "actual auxiliary execution lacks its parent association data"
            Just association -> do
              Association.nativeAssociationOrdinal association @?= 1
              Association.nativeAssociationChild association @?= singleton
              Association.nativeAssociationInvocation association @?= fixtureParentInvocation resource
              Native.nativeSingletonPlanId (Association.nativeAssociationParent association)
                @?= Completion.productScenarioInvocationPlanId (fixtureParentInvocation resource)
              assertBool
                "auxiliary child was relabelled as the supplied parent"
                ( Native.nativeSingletonPlanId singleton
                    /= Completion.productScenarioInvocationPlanId (fixtureParentInvocation resource)
                )
          Ars.validateArsTrainObservation (High.nativeArsOriginPolicy actualOrigin) @?= Right ()
          rawProjection (High.nativeArsOriginPolicy actualOrigin) @?= rawProjection (actualRaw actual)
          Producer.compareProducerProcessObservations
            (High.nativeArsOriginBeforeProcess actualOrigin)
            (High.nativeArsOriginAfterProcess actualOrigin)
            @?= Right ()
    , testCase "different supplied parent row plan lane and executable reject at their exact boundaries" $ do
        resource <- get
        selectedChild <- child 0
        otherRow <- batch LinuxCPU >>= \whole -> selected (High.selectNativeArsRowData whole "ARS/cartpole")
        let original = fixtureParentInvocation resource
            parentOther =
              Cohort.nativeRlSeedPlanSingleton
                (Cohort.nativeRlCohortServingChild (High.nativeArsRowCohort otherRow))
            originalExe = Completion.productScenarioInvocationExecutableSha256 original
        changedExe <- case Text.uncons originalExe of
          Just (first, rest) -> pure (Text.cons (if first == '0' then '1' else '0') rest)
          Nothing -> assertFailure "actual executable FILE SHA is empty" >> fail "unreachable"
        let variants =
              [
                ( "ARS/cartpole"
                , Completion.productScenarioInvocationPlanId original
                , LinuxCPU
                , originalExe
                , "invocation row differs"
                )
              ,
                ( "ARS/mountain-car"
                , Native.nativeSingletonPlanId parentOther
                , LinuxCPU
                , originalExe
                , "different parent plan"
                )
              ,
                ( "ARS/mountain-car"
                , Completion.productScenarioInvocationPlanId original
                , LinuxCUDA
                , originalExe
                , "lane differs"
                )
              ,
                ( "ARS/mountain-car"
                , Completion.productScenarioInvocationPlanId original
                , LinuxCPU
                , changedExe
                , "executable differs"
                )
              ]
        forM_ variants $ \(row, plan, lane, exe, fragment) -> do
          wrong <-
            right
              ( Completion.mkProductScenarioInvocation
                  (Completion.productScenarioInvocationRunId original)
                  row
                  plan
                  lane
                  (Completion.productScenarioInvocationCheckpointScopeDigest original)
                  exe
                  (Completion.productScenarioInvocationChallenge original)
              )
          result <-
            High.beginNativeArsAttempt
              selectedChild
              (High.SuppliedNativeArsParent wrong (High.ObserveNativeArsSourceRoot (fixtureRoot resource)))
          case result of
            High.NativeArsBeginFailed failure -> assertFailureAt High.NativeArsBeginning High.NativeArsRejected fragment failure
            _ -> assertFailure "changed supplied context created an actual preparation route"
    , testCase "data-only binding checks every config and signed-zero initial parameter identity" $ do
        resource <- get
        let actual = fixtureDirect resource
            raw = actualRaw actual
            snapshot = High.nativeArsPreparedSnapshot (runPrepared actual)
            config = Common.rawTrainerConfig raw
            changedConfigs =
              [ config {Ars.arsSeed = Ars.arsSeed config + 1}
              , config {Ars.arsIterations = Ars.arsIterations config + 1}
              , config {Ars.arsNumDirections = Ars.arsNumDirections config + 1}
              , config {Ars.arsTopB = Ars.arsTopB config + 1}
              , config {Ars.arsStepSize = Ars.arsStepSize config + 1}
              , config {Ars.arsNoiseStd = Ars.arsNoiseStd config + 1}
              , config {Ars.arsMaxEpisodeSteps = Ars.arsMaxEpisodeSteps config + 1}
              , config {Ars.arsActionCount = Ars.arsActionCount config + 1}
              , config {Ars.arsObsSize = Ars.arsObsSize config + 1}
              ]
        forM_ changedConfigs $ \changed ->
          assertLeft
            "configuration differs"
            (High.validateNativeArsReturnedBinding snapshot (raw {Common.rawTrainerConfig = changed}))
        case VU.uncons (Common.rawTrainerInitialParams raw) of
          Nothing -> assertFailure "actual canonical initial parameter vector empty"
          Just (first, rest) -> do
            first @?= 0
            assertBool
              "signed-zero mutation did not alter actual bits"
              (castDoubleToWord64 (negate first) /= castDoubleToWord64 first)
            assertLeft
              "initial parameters differ"
              ( High.validateNativeArsReturnedBinding
                  snapshot
                  (raw {Common.rawTrainerInitialParams = VU.cons (negate first) rest})
              )
        assertLeft
          "initial parameters differ"
          ( High.validateNativeArsReturnedBinding
              snapshot
              (raw {Common.rawTrainerInitialParams = VU.drop 1 (Common.rawTrainerInitialParams raw)})
          )
    , testCase "actual complete trace mutations fail exact scale index count and chain validation" $ do
        resource <- get
        let raw = actualRaw (fixtureDirect resource)
        case Common.rawTrainerStats raw of
          first : rest -> do
            let step = Ars.arsObservationAppliedStep first
                changed altered = raw {Common.rawTrainerStats = first {Ars.arsObservationAppliedStep = altered} : rest}
            assertLeft
              "scale differs"
              (Ars.validateArsTrainObservation (changed (step {Ars.arsStepScale = Ars.arsStepScale step + 1})))
            assertLeft
              "iteration index differs"
              (Ars.validateArsTrainObservation (changed (step {Ars.arsStepIndex = 1})))
            assertLeft
              "sampled direction count differs"
              (Ars.validateArsTrainObservation (changed (step {Ars.arsStepSampledDirections = []})))
            case VU.uncons (Ars.arsStepThetaBefore step) of
              Just (value, tailValues) ->
                assertLeft
                  "chain is discontinuous"
                  ( Ars.validateArsTrainObservation
                      (changed (step {Ars.arsStepThetaBefore = VU.cons (value + 1) tailValues}))
                  )
              Nothing -> assertFailure "actual thetaBefore empty"
          [] -> assertFailure "actual canonical trace empty"
    , testCase
        "fixed-case data predicates reject missing reordered nonfinite and inconsistent-work observations"
        $ do
          resource <- get
          let actual = fixtureDirect resource
              raw = initialEvaluation actual
              check fragment changed = assertLeft fragment (High.validateNativeArsEvaluationData (runChild actual) changed)
          case Return.nativeEvaluationEpisodes raw of
            first : rest -> do
              check "inventory differs" (raw {Return.nativeEvaluationEpisodes = rest})
              check "inventory differs" (raw {Return.nativeEvaluationEpisodes = reverse (first : rest)})
              check
                "nonfinite or incomplete"
                (raw {Return.nativeEvaluationEpisodes = first {Ref.nativeReturnEpisodeReward = 0 / 0} : rest})
              check
                "nonfinite or incomplete"
                (raw {Return.nativeEvaluationEpisodes = first {Ref.nativeReturnEpisodeSteps = 0} : rest})
              check "work differs" (raw {Return.nativeEvaluationWork = Return.NativeCompleteWork (-1)})
            [] -> assertFailure "actual canonical initial cases empty"
    , testCase "the data-only closed catcher forces outer and error text while async still propagates" $ do
        let failures =
              [ ("actual lazy outer control", pure (error "actual lazy outer control"))
              , ("actual lazy Left control", pure (Left (error "actual lazy Left control")))
              , ("actual synchronous IO control", throwIO (userError "actual synchronous IO control"))
              ]
        forM_ failures $ \(fragment, action) -> do
          result <- High.observeNativeArsFailureBoundary High.NativeArsTraining action
          case result of
            Left failure -> assertFailureAt High.NativeArsTraining High.NativeArsSynchronousFailure fragment failure
            Right () -> assertFailure "synchronous bottom escaped the shared catcher"
        interrupted <-
          try (High.observeNativeArsFailureBoundary High.NativeArsTraining (throwIO ThreadKilled))
            :: IO (Either AsyncException (Either High.NativeArsFailure ()))
        case interrupted of
          Left ThreadKilled -> pure ()
          _ -> assertFailure "async cancellation was swallowed"
    ]
