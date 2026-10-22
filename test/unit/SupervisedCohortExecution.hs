{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

module SupervisedCohortExecution (supervisedCohortExecutionTests) where

import Codec.Serialise (Serialise, deserialiseOrFail)
import Control.Exception (IOException, try)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (runReaderT)
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Either (isLeft)
import Data.Foldable (for_)
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef)
import Data.List qualified as List
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

import JitML.Checkpoint.WeightCodec qualified as WeightCodec
import JitML.Env.Build (buildEnv, defaultGlobalFlags)
import JitML.Numerics.LayerGraph qualified as Graph
import JitML.Numerics.LayerGraphMetadata qualified as Metadata
import JitML.Plan.Plan qualified as Plan
import JitML.Plan.Workload qualified as Workload
import JitML.Product.DeviceWitness qualified as Device
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.Publisher qualified as Publisher
import JitML.Product.ServedMetric qualified as Served
import JitML.Product.SupervisedCohortPlan qualified as Cohort
import JitML.Product.SupervisedQualification qualified as Qualification
import JitML.Product.SupervisedQualificationPolicy qualified as Policy
import JitML.Product.SupervisedQualificationReceipt qualified as Receipt
import JitML.SL.Canonicals qualified as Canonicals
import JitML.SL.Dataset qualified as Dataset
import JitML.SL.RuntimeArtifact qualified as Runtime
import JitML.Substrate (Substrate (LinuxCPU))
import JitML.Test.DeviceWitnessFixture qualified as DeviceFixture

-- Synthetic raw runs exercise the actual production five-child executor and
-- its binary writer boundary. The witness is the existing offline fixture;
-- these controls do not claim real canonical training, authenticated producer
-- provenance, Store admission, or an eligible publication.
supervisedCohortExecutionTests :: TestTree
supervisedCohortExecutionTests =
  testGroup
    "prescribed supervised cohort execution"
    [ testCase "executes all five exact ordered singleton plans once and never a sixth" $
        withHarness (replicate 5 True) $ \harness -> do
          result <- execute harness (harnessRuntime harness)
          (primary, qualification, sha, key) <- expectRight result
          calls <- readIORef (harnessCalls harness)
          fmap childIdentity calls
            @?= fmap childIdentity (Cohort.supervisedCohortPlanChildren (harnessPlan harness))
          length calls @?= 5
          primary @?= expectedRun harness 0
          sha @?= Qualification.supervisedQualificationSha256 qualification
          key @?= Receipt.supervisedQualificationObjectKey (harnessPlan harness) sha
          Qualification.supervisedQualificationIndex0Metric qualification @?= 1
          readIORef (harnessProducerCalls harness) >>= (@?= 1)
    , testCase
        "the actual predetermined index-zero result is returned even when all auxiliaries score higher"
        $ withHarness [False, True, True, True, True]
        $ \harness -> do
          (primary, qualification, _, _) <- expectRight =<< execute harness (harnessRuntime harness)
          primary @?= expectedRun harness 0
          Publisher.supervisedPublishHeldOutMetric primary @?= Just ("test_accuracy", 0.5)
          Policy.supervisedCohortMedian (Qualification.supervisedQualificationAssessment qualification) @?= 1
          Qualification.supervisedQualificationIndex0Metric qualification @?= 0.5
          assertBool
            "auxiliaries replaced the index-zero eligibility requirement"
            (isLeft (Qualification.qualifySupervisedCohort qualification))
    , testCase "finite below-floor unchanged children survive both raw records and the assembled artifact" $
        withHarness [True, True, False, False, False] $ \harness -> do
          (_, qualification, _, _) <- expectRight =<< execute harness (harnessRuntime harness)
          Policy.supervisedCohortJointSuccessCount
            (Qualification.supervisedQualificationAssessment qualification)
            @?= 2
          assertBool
            "a failing whole-five cohort was silently accepted"
            (isLeft (Qualification.qualifySupervisedCohort qualification))
          outcomes <- decodedOutcomes harness
          fmap Qualification.rawSeedIndex outcomes @?= [0 .. 4]
          length outcomes @?= 5
          for_ (drop 2 (Qualification.supervisedQualificationOutcomes qualification)) $ \outcome ->
            Qualification.supervisedSeedOutcomeInitialJmw1Sha256 outcome
              @?= Qualification.supervisedSeedOutcomeFinalJmw1Sha256 outcome
          fmap
            Qualification.supervisedSeedOutcomeToRaw
            (Qualification.supervisedQualificationOutcomes qualification)
            @?= outcomes
    , testCase
        "records start, every raw return and outcome, one shared evaluation and the exact portable artifact"
        $ withHarness (replicate 5 True)
        $ \harness -> do
          (_, qualification, _, _) <- expectRight =<< execute harness (harnessRuntime harness)
          writes <- readIORef (harnessWrites harness)
          fmap capturedKind writes
            @?= "supervised-qualification-attempt"
            : concat
              [ ["supervised-seed-return"]
                  <> ["supervised-qualification-evaluation" | index == 0]
                  <> ["supervised-seed-outcome"]
              | index <- [0 :: Int .. 4]
              ]
              <> ["supervised-qualification"]
          first <- expectFirst writes
          started <- decodeCaptured first
          started
            @?= (1 :: Int, "started" :: Text, Cohort.supervisedCohortPlanTransport (harnessPlan harness), producer)
          for_ writes $ \captured -> do
            actual <- LazyByteString.readFile (capturedPath captured)
            actual @?= capturedBytes captured
            WeightCodec.jmw1ContentSha actual @?= capturedSha captured
          payload <- exactlyOne "supervised-qualification" writes
          LazyByteString.toStrict (capturedBytes payload)
            @?= Qualification.encodeSupervisedQualification qualification
    , testCase
        "a training infrastructure Left stops before the next child and records its prescribed failed attempt"
        $ withHarness (replicate 5 True)
        $ \harness -> do
          let base = harnessRuntime harness
              injected =
                base
                  { Publisher.publisherRunSupervisedTraining = \child ->
                      if childIndex child == 2
                        then
                          liftIO (appendRef (harnessCalls harness) child)
                            >> pure (Left "injected trainer infrastructure failure")
                        else Publisher.publisherRunSupervisedTraining base child
                  }
          result <- execute harness injected
          expectLeftContains "injected trainer infrastructure failure" result
          readIORef (harnessCalls harness) >>= ((@?= [0, 1, 2]) . fmap childIndex)
          outcomes <- decodedOutcomes harness
          fmap Qualification.rawSeedIndex outcomes @?= [0, 1]
          assertNoCohortArtifact harness
          assertFailedChild harness 2 "injected trainer infrastructure failure"
    , testCase "malformed and nonfinite returned observations are retained before refinement rejects them" $
        for_ [MissingGraph, NonfiniteMetric, MalformedWeights, WrongCounter] $ \defect ->
          withHarness (replicate 5 True) $ \harness -> do
            let base = harnessRuntime harness
                invalid = corruptRun defect (expectedRun harness 1)
                injected =
                  base
                    { Publisher.publisherRunSupervisedTraining = \child ->
                        if childIndex child == 1
                          then liftIO (appendRef (harnessCalls harness) child) >> pure (Right invalid)
                          else Publisher.publisherRunSupervisedTraining base child
                    }
            result <- execute harness injected
            assertBool "invalid run was accepted" (isLeft result)
            readIORef (harnessCalls harness) >>= ((@?= [0, 1]) . fmap childIndex)
            writes <- readIORef (harnessWrites harness)
            returned <- expectLast [entry | entry <- writes, capturedKind entry == "supervised-seed-return"]
            raw <- decodeCaptured returned :: IO ReturnedRun
            assertRawDefect defect raw
            decodedOutcomes harness >>= (@?= [0]) . fmap Qualification.rawSeedIndex
            assertNoCohortArtifact harness
            assertFailedChildContains harness 1
    , testCase "a producer authority failure executes and writes nothing" $
        withHarness (replicate 5 True) $ \harness -> do
          let runtime =
                (harnessRuntime harness)
                  { Publisher.publisherSupervisedQualificationProducer = \_ -> pure (Left "source authority unavailable")
                  }
          expectLeftContains "source authority unavailable" =<< execute harness runtime
          readIORef (harnessCalls harness) >>= ((@?= []) . fmap childIndex)
          readIORef (harnessWrites harness) >>= ((@?= []) . fmap capturedKind)
    , testCase "substituting the start ledger digest fails before the first child" $
        withHarness (replicate 5 True) $ \harness -> do
          runtime <- substituteWriter harness "supervised-qualification-attempt" 0 False
          expectLeftContains "substituted payload identity" =<< execute harness runtime
          readIORef (harnessCalls harness) >>= ((@?= []) . fmap childIndex)
          readIORef (harnessWrites harness)
            >>= ((@?= ["supervised-qualification-attempt"]) . fmap capturedKind)
    , testCase "substituting a raw outcome digest retains the prefix and stops subsequent training" $
        withHarness (replicate 5 True) $ \harness -> do
          runtime <- substituteWriter harness "supervised-seed-outcome" 1 False
          expectLeftContains "substituted payload identity" =<< execute harness runtime
          readIORef (harnessCalls harness) >>= ((@?= [0, 1]) . fmap childIndex)
          assertNoCohortArtifact harness
          assertFailedChild
            harness
            1
            "supervised qualification raw writer returned a substituted payload identity"
    , testCase "a noncanonical final object address retains all raw children and records assembly failure" $
        withHarness (replicate 5 True) $ \harness -> do
          runtime <- substituteWriter harness "supervised-qualification" 0 True
          expectLeftContains "noncanonical detached object address" =<< execute harness runtime
          readIORef (harnessCalls harness) >>= ((@?= [0 .. 4]) . fmap childIndex)
          decodedOutcomes harness >>= ((@?= [0 .. 4]) . fmap Qualification.rawSeedIndex)
          writes <- readIORef (harnessWrites harness)
          failed <-
            expectLast [entry | entry <- writes, capturedKind entry == "supervised-qualification-attempt"]
          (version, fields, observedProducer) <-
            decodeCaptured failed :: IO (Int, [Text], Qualification.RawQualificationProducer)
          version @?= 1
          observedProducer @?= producer
          fields
            @?= [ "failed"
                , Cohort.supervisedCohortPlanTransport (harnessPlan harness)
                , "supervised qualification writer returned a noncanonical detached object address"
                ]
    , testCase
        "inconsistent child evaluation data is fully retained but cannot assemble a shared-data artifact"
        $ withHarness (replicate 5 True)
        $ \harness -> do
          let base = harnessRuntime harness
              injected =
                base
                  { Publisher.publisherRunSupervisedTraining = \child -> do
                      result <- Publisher.publisherRunSupervisedTraining base child
                      pure (if childIndex child == 4 then fmap reverseExamples result else result)
                  }
          expectLeftContains "evaluation SHA" =<< execute harness injected
          readIORef (harnessCalls harness) >>= ((@?= [0 .. 4]) . fmap childIndex)
          decodedOutcomes harness >>= ((@?= [0 .. 4]) . fmap Qualification.rawSeedIndex)
          assertNoCohortArtifact harness
          writes <- readIORef (harnessWrites harness)
          failed <-
            expectLast [entry | entry <- writes, capturedKind entry == "supervised-qualification-attempt"]
          (_, fields, _) <- decodeCaptured failed :: IO (Int, [Text], Qualification.RawQualificationProducer)
          case fields of
            ["failed", transport, reason] -> do
              transport @?= Cohort.supervisedCohortPlanTransport (harnessPlan harness)
              assertBool "shared-data failure reason was lost" ("evaluation SHA" `Text.isInfixOf` reason)
            _ -> fail "assembly failure was not retained in the raw cohort ledger"
    , testCase
        "unexpected trainer IO failure propagates without an eligible result or invented completed outcome"
        $ withHarness (replicate 5 True)
        $ \harness -> do
          let base = harnessRuntime harness
              injected =
                base
                  { Publisher.publisherRunSupervisedTraining = \child ->
                      if childIndex child == 1
                        then
                          liftIO
                            ( appendRef (harnessCalls harness) child
                                >> ioError (userError "injected unexpected trainer IO failure")
                            )
                        else Publisher.publisherRunSupervisedTraining base child
                  }
          result <- try (execute harness injected) :: IO (Either IOException CohortResult)
          case result of
            Left exception ->
              assertBool
                "wrong unexpected failure"
                ("injected unexpected trainer IO failure" `Text.isInfixOf` Text.pack (show exception))
            Right _ -> fail "unexpected trainer IO failure was converted into success"
          readIORef (harnessCalls harness) >>= ((@?= [0, 1]) . fmap childIndex)
          decodedOutcomes harness >>= ((@?= [0]) . fmap Qualification.rawSeedIndex)
          assertNoCohortArtifact harness
    ]

type CohortResult =
  Either Text (Publisher.SupervisedPublishRun, Qualification.SupervisedQualification, Text, Text)

data CapturedArtifact = CapturedArtifact
  { capturedKind :: !Text
  , capturedBytes :: !LazyByteString.ByteString
  , capturedSha :: !Text
  , capturedPath :: !FilePath
  }

data Harness = Harness
  { harnessRow :: !(Matrix.ProductRow 'Matrix.Declared)
  , harnessProblem :: !Canonicals.CanonicalProblem
  , harnessPlan :: !Cohort.SupervisedCohortPlan
  , harnessRuns :: ![Publisher.SupervisedPublishRun]
  , harnessRuntime :: !Publisher.ProductPublisherRuntime
  , harnessCalls :: !(IORef [Cohort.SupervisedSeedPlan])
  , harnessWrites :: !(IORef [CapturedArtifact])
  , harnessProducerCalls :: !(IORef Int)
  }

withHarness :: [Bool] -> (Harness -> IO value) -> IO value
withHarness successes action =
  withSystemTempDirectory "jitml-prescribed-cohort-execution" $ \directory -> do
    row <-
      expectJust
        "missing canonical row"
        (List.find ((== "mnist-shallow-mlp") . Matrix.rowId) Matrix.allProductRows)
    projection <- case Matrix.projectProductRow LinuxCPU row of
      Plan.Success (Matrix.SomeProductProjection Plan.SupervisedTrainingWitness value) -> pure value
      _ -> fail "canonical supervised row did not project"
    cohort <- expectRight (Cohort.mkSupervisedCohortPlan projection)
    problem <-
      expectJust
        "missing canonical problem"
        (List.find ((== Matrix.rowId row) . Canonicals.problemName) Canonicals.canonicalProblems)
    witness <-
      expectRight =<< DeviceFixture.fixtureClassificationDeviceExecutionWitnessFor LinuxCPU
    datasetSha <- expectRight (Dataset.canonicalDatasetReadShaForProblem problem)
    node <-
      expectRight
        ( Graph.mkAffineLayer
            "synthetic execution comparison"
            1
            10
            Graph.LinearActivation
            Graph.InferenceMode
            (Graph.LayerParameters (VU.replicate 10 0) (VU.replicate 10 0))
        )
    let graph =
          Graph.LayerGraph
            "synthetic execution fixture"
            (Graph.TensorShape [1])
            (Graph.TensorShape [10])
            [node]
        metadata = Metadata.layerGraphMetadataFromGraph graph
        runs =
          zipWith (makeRun witness datasetSha metadata) (Cohort.supervisedCohortPlanChildren cohort) successes
    length runs @?= 5
    calls <- newIORef []
    writes <- newIORef []
    producerCalls <- newIORef 0
    let runtime =
          unusedRuntime
            { Publisher.publisherRunSupervisedTraining = \child -> liftIO $ do
                appendRef calls child
                pure $ maybe (Left "unprescribed child invoked") Right (lookup (childIndex child) (zip [0 ..] runs))
            , Publisher.publisherSupervisedQualificationProducer = \_ -> liftIO $ do
                atomicModifyIORef' producerCalls (\count -> (count + 1, ()))
                pure (Right producer)
            , Publisher.publisherWriteBinaryArtifact = \experiment kind bytes -> liftIO $ do
                captured <- readIORef writes
                let sha = WeightCodec.jmw1ContentSha bytes
                    path =
                      directory
                        </> (show (length captured) <> "-" <> Text.unpack kind <> "-" <> Text.unpack sha <> ".cbor")
                    key = "jitml-checkpoints/" <> experiment <> "/artifacts/" <> kind <> "/" <> sha <> ".cbor"
                LazyByteString.writeFile path bytes
                appendRef writes (CapturedArtifact kind bytes sha path)
                pure (sha, key)
            }
    action (Harness row problem cohort runs runtime calls writes producerCalls)

makeRun
  :: Device.DeviceExecutionWitness
  -> Text
  -> Metadata.LayerGraphMetadata
  -> Cohort.SupervisedSeedPlan
  -> Bool
  -> Publisher.SupervisedPublishRun
makeRun witness datasetSha metadata child improves =
  let plan = Cohort.supervisedSeedPlanWorkload child
      epochs = Plan.quantityValue (Workload.supervisedPlanEpochs plan)
      examples = Plan.quantityValue (Workload.supervisedPlanTrainingExamples plan)
      heldOutCount = fromIntegral (Plan.quantityValue (Workload.supervisedPlanEvaluationExamples plan))
      initial = WeightCodec.encodeJmw1 (replicate 20 0)
      final = if improves then WeightCodec.encodeJmw1 ([-1, 1] <> replicate 18 0) else initial
   in Publisher.SupervisedPublishRun
        { Publisher.supervisedPublishTrainLoss = 1 + fromIntegral (childIndex child)
        , Publisher.supervisedPublishValidationLoss = 2 + fromIntegral (childIndex child)
        , Publisher.supervisedPublishExamplesProcessed = fromIntegral (epochs * examples)
        , Publisher.supervisedPublishHeldOutMetric = Just ("test_accuracy", if improves then 1 else 0.5)
        , Publisher.supervisedPublishHeldOutExamples =
            Served.HeldOutClassification (take heldOutCount (cycle [([-1], 0), ([1], 1)]))
        , Publisher.supervisedPublishCompletedUnits = epochs
        , Publisher.supervisedPublishOptimizerUpdatesExecuted =
            Plan.quantityValue (Workload.supervisedPlanOptimizerUpdates plan)
        , Publisher.supervisedPublishRuntimeProgram =
            Runtime.RawSupervisedRuntime
              (Runtime.RawClassificationRuntimeTask 10)
              (Runtime.RawIdentityInput 1)
              (Runtime.RawSemanticPrefixOutput 10)
        , Publisher.supervisedPublishLayerGraphMetadata = Just metadata
        , Publisher.supervisedPublishInitialLayerGraphMetadata = metadata
        , Publisher.supervisedPublishInitialJmw1Bytes = initial
        , Publisher.supervisedPublishFinalJmw1Bytes = final
        , Publisher.supervisedPublishVerifiedDatasetShaAtRead = datasetSha
        , Publisher.supervisedPublishDeviceWitness = Just witness
        , Publisher.supervisedPublishInitialWeights = Nothing
        , Publisher.supervisedPublishCheckpointWeights = Nothing
        , Publisher.supervisedPublishDatasetShaAtRead = Nothing
        }

unusedRuntime :: Publisher.ProductPublisherRuntime
unusedRuntime =
  Publisher.ProductPublisherRuntime
    { Publisher.publisherRunSupervisedTraining = error "unconfigured supervised trainer"
    , Publisher.publisherSupervisedQualificationProducer = error "unconfigured producer authority"
    , Publisher.publisherRunRlTraining = error "cohort execution called RL trainer"
    , Publisher.publisherCompleteProductRow = error "raw cohort minted generic completion"
    , Publisher.publisherCompleteSupervisedProductRowWithWeightHashes =
        error "raw cohort minted supervised completion"
    , Publisher.publisherRlCompletionMetrics = error "cohort execution called RL metrics"
    , Publisher.publisherRlCompletedTraining = error "raw cohort minted RL completion"
    , Publisher.publisherRlCompletionFailure = error "cohort execution called RL failure"
    , Publisher.publisherAlphaZeroCompletedTraining = error "raw cohort minted AlphaZero completion"
    , Publisher.publisherWriteCompletedWeightCheckpoint =
        error "raw cohort wrote a completed weight checkpoint"
    , Publisher.publisherWriteCompletedSupervisedCheckpoint =
        error "raw cohort wrote a supervised checkpoint"
    , Publisher.publisherAdmitCompletedCheckpoint = error "raw cohort invoked Store admission"
    , Publisher.publisherWriteTextArtifact = error "cohort execution used text artifact writer"
    , Publisher.publisherWriteBinaryArtifact = error "unconfigured binary artifact writer"
    , Publisher.publisherLoadTuningDataset = error "cohort execution loaded tuning dataset"
    , Publisher.publisherReuseAdmittedCheckpoint = error "raw cohort reused a checkpoint"
    }

execute :: Harness -> Publisher.ProductPublisherRuntime -> IO CohortResult
execute harness runtime = do
  environment <- buildEnv defaultGlobalFlags
  runReaderT
    ( Publisher.trainSupervisedCohort
        Nothing
        runtime
        (harnessRow harness)
        (harnessProblem harness)
        (harnessPlan harness)
    )
    environment

substituteWriter :: Harness -> Text -> Int -> Bool -> IO Publisher.ProductPublisherRuntime
substituteWriter harness target occurrence substituteKey = do
  seen <- newIORef (0 :: Int)
  let base = harnessRuntime harness
  pure
    base
      { Publisher.publisherWriteBinaryArtifact = \experiment kind bytes -> do
          honest@(sha, key) <- Publisher.publisherWriteBinaryArtifact base experiment kind bytes
          shouldSubstitute <-
            liftIO $
              if kind == target
                then atomicModifyIORef' seen (\count -> (count + 1, count == occurrence))
                else pure False
          pure $
            if shouldSubstitute
              then if substituteKey then (sha, key <> "/substituted") else (Text.replicate 64 "f", key)
              else honest
      }

producer :: Qualification.RawQualificationProducer
producer =
  Qualification.RawQualificationProducer
    (Text.replicate 64 "1")
    (Text.replicate 64 "2")
    (Text.replicate 64 "3")

childIndex :: Cohort.SupervisedSeedPlan -> Int
childIndex = Policy.supervisedSeedIndexValue . Cohort.supervisedSeedPlanIndex

childIdentity :: Cohort.SupervisedSeedPlan -> (Int, Word64, Text, Text)
childIdentity child =
  ( childIndex child
  , Cohort.supervisedSeedPlanSeed child
  , Plan.planIdText (Workload.supervisedPlanId plan)
  , Workload.renderSupervisedPlanTransport plan
  )
 where
  plan = Cohort.supervisedSeedPlanWorkload child

expectedRun :: Harness -> Int -> Publisher.SupervisedPublishRun
expectedRun harness index =
  case lookup index (zip [0 ..] (harnessRuns harness)) of
    Just value -> value
    Nothing -> error "test requested a run outside the prescribed five"

appendRef :: IORef [value] -> value -> IO ()
appendRef reference value = atomicModifyIORef' reference (\previous -> (previous <> [value], ()))

decodedOutcomes :: Harness -> IO [Qualification.RawSupervisedSeedOutcome]
decodedOutcomes harness = do
  writes <- readIORef (harnessWrites harness)
  traverse decodeCaptured [entry | entry <- writes, capturedKind entry == "supervised-seed-outcome"]

decodeCaptured :: (Serialise value) => CapturedArtifact -> IO value
decodeCaptured captured =
  either (fail . show) pure (deserialiseOrFail (capturedBytes captured))

assertNoCohortArtifact :: Harness -> IO ()
assertNoCohortArtifact harness = do
  writes <- readIORef (harnessWrites harness)
  assertBool
    "failure produced a portable cohort artifact"
    (all ((/= "supervised-qualification") . capturedKind) writes)

assertFailedChild :: Harness -> Int -> Text -> IO ()
assertFailedChild harness index reason = do
  writes <- readIORef (harnessWrites harness)
  failed <-
    expectLast [entry | entry <- writes, capturedKind entry == "supervised-qualification-attempt"]
  event <- decodeCaptured failed
  child <-
    expectJust
      "missing expected failed child"
      (List.find ((== index) . childIndex) (Cohort.supervisedCohortPlanChildren (harnessPlan harness)))
  event
    @?= ( 1 :: Int
        , "failed" :: Text
        , Qualification.prescribedSupervisedChildAttempt
            (Qualification.rawQualificationInvocationSha256 producer)
            child
        , reason
        )

assertFailedChildContains :: Harness -> Int -> IO ()
assertFailedChildContains harness index = do
  writes <- readIORef (harnessWrites harness)
  failed <-
    expectLast [entry | entry <- writes, capturedKind entry == "supervised-qualification-attempt"]
  (version, state, attempt, reason) <- decodeCaptured failed :: IO (Int, Text, Text, Text)
  child <-
    expectJust
      "missing expected failed child"
      (List.find ((== index) . childIndex) (Cohort.supervisedCohortPlanChildren (harnessPlan harness)))
  version @?= 1
  state @?= "failed"
  attempt
    @?= Qualification.prescribedSupervisedChildAttempt
      (Qualification.rawQualificationInvocationSha256 producer)
      child
  assertBool "failed refinement lost its diagnostic" (not (Text.null reason))

data RunDefect = MissingGraph | NonfiniteMetric | MalformedWeights | WrongCounter

corruptRun :: RunDefect -> Publisher.SupervisedPublishRun -> Publisher.SupervisedPublishRun
corruptRun defect run = case defect of
  MissingGraph -> run {Publisher.supervisedPublishLayerGraphMetadata = Nothing}
  NonfiniteMetric -> run {Publisher.supervisedPublishHeldOutMetric = Just ("test_accuracy", 0 / 0)}
  MalformedWeights -> run {Publisher.supervisedPublishFinalJmw1Bytes = "malformed-final-jmw1"}
  WrongCounter -> run {Publisher.supervisedPublishOptimizerUpdatesExecuted = 0}

type ReturnedRun =
  ( Int
  , Text
  , ( (Word64, Int, Word64)
    , ( (Double, Double, Maybe (Text, Double))
      , ( (Runtime.RawSupervisedRuntime, Metadata.LayerGraphMetadata, Maybe Metadata.LayerGraphMetadata)
        , ( (LazyByteString.ByteString, LazyByteString.ByteString)
          , (Text, Maybe Device.RawDeviceExecutionWitness, Qualification.RawQualificationEvaluation)
          )
        )
      )
    )
  )

assertRawDefect :: RunDefect -> ReturnedRun -> IO ()
assertRawDefect
  defect
  ( version
    , _transport
    , ( (_epochs, _examples, updates)
        , ( (_trainLoss, _validationLoss, heldOut)
            , ((_runtime, _initialGraph, finalGraph), ((_initial, final), _data))
            )
        )
    ) = do
    version @?= 1
    case defect of
      MissingGraph -> finalGraph @?= Nothing
      NonfiniteMetric -> case heldOut of
        Just ("test_accuracy", value) -> assertBool "raw nonfinite observation was normalized or dropped" (isNaN value)
        _ -> fail "nonfinite raw metric was omitted"
      MalformedWeights -> final @?= "malformed-final-jmw1"
      WrongCounter -> updates @?= 0

reverseExamples :: Publisher.SupervisedPublishRun -> Publisher.SupervisedPublishRun
reverseExamples run = case Publisher.supervisedPublishHeldOutExamples run of
  Served.HeldOutClassification examples ->
    run {Publisher.supervisedPublishHeldOutExamples = Served.HeldOutClassification (reverse examples)}
  Served.HeldOutRegression scale examples ->
    run {Publisher.supervisedPublishHeldOutExamples = Served.HeldOutRegression scale (reverse examples)}

exactlyOne :: Text -> [CapturedArtifact] -> IO CapturedArtifact
exactlyOne kind entries = case filter ((== kind) . capturedKind) entries of
  [entry] -> pure entry
  _ -> fail ("expected exactly one captured artifact of kind " <> Text.unpack kind)

expectFirst :: [value] -> IO value
expectFirst (first : _) = pure first
expectFirst [] = fail "expected a retained prefix"

expectLast :: [value] -> IO value
expectLast values = expectFirst (reverse values)

expectRight :: Either Text value -> IO value
expectRight = either (fail . Text.unpack) pure

expectJust :: String -> Maybe value -> IO value
expectJust reason = maybe (fail reason) pure

expectLeftContains :: Text -> Either Text value -> IO ()
expectLeftContains fragment result = case result of
  Left message -> assertBool (Text.unpack message) (fragment `Text.isInfixOf` message)
  Right _ -> fail ("expected rejection containing " <> Text.unpack fragment)
