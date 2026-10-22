{-# LANGUAGE OverloadedStrings #-}

-- Ordinary decoder/rule DATA controls. No parent binding, producer, trained
-- model, device witness or successful qualification capsule is fabricated.
module NativeParentPolicyData (nativeParentPolicyDataTests) where

import Codec.CBOR.Encoding qualified as CBOR
import Control.Exception (AsyncException (ThreadKilled), Exception (displayException), throw, try)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.List (find, nub, sort)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import GHC.Float (castDoubleToWord64)
import System.Timeout (timeout)
import Test.Tasty (TestTree, testGroup, withResource)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Checkpoint.NativeParentBindingData qualified as Binding
import JitML.Checkpoint.NativeParentPolicyData qualified as Parent
import JitML.Checkpoint.NativeParentPolicyData.Evaluation qualified as Decode
import JitML.Checkpoint.NativeParentPolicyData.Lineage qualified as Lineage
import JitML.Checkpoint.NativeParentPolicyData.Node qualified as Node
import JitML.Checkpoint.NativeParentPolicyData.ReturnReplay qualified as Rule
import JitML.Checkpoint.NativePhase.Builder qualified as Builder
import JitML.Checkpoint.NativePhase.CBOR qualified as Wire
import JitML.Checkpoint.NativePhase.Context qualified as Context
import JitML.Checkpoint.NativePhase.Failure qualified as Failure
import JitML.Checkpoint.NativePhase.Graph qualified as Graph
import JitML.Checkpoint.NativePhase.Producer qualified as ProducerData
import JitML.Checkpoint.NativePhase.Projection qualified as Project
import JitML.Checkpoint.NativePhase.Schema qualified as Schema
import JitML.Checkpoint.NativePhase.Types
import JitML.Execution.ProducerObservation qualified as Process
import JitML.Numerics.Mlp qualified as Mlp
import JitML.Numerics.MlpDevice (pureReferenceMlpDevice)
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.NativeArenaLearningPolicy qualified as ArenaPolicy
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.Product.SourceDigest qualified as Source
import JitML.RL.Algorithms.ArsTrainer qualified as Ars
import JitML.RL.Algorithms.ContinuousTrainer qualified as Continuous
import JitML.RL.Algorithms.DqnTrainer qualified as Dqn
import JitML.RL.Algorithms.HerTrainer qualified as Her
import JitML.RL.Algorithms.PpoTrainer qualified as Ppo
import JitML.RL.Algorithms.QrDqnTrainer qualified as Qr
import JitML.RL.AlphaZero.NativeArenaEvaluation qualified as Arena
import JitML.RL.AlphaZero.NativeArenaReferences qualified as ArenaRef
import JitML.RL.AlphaZero.PolicyValueNet qualified as Net
import JitML.RL.ArsHostTrace qualified as ArsTrace
import JitML.RL.NativeHerEvaluation qualified as HerEval
import JitML.RL.NativeHerReferences qualified as HerRef
import JitML.RL.NativeReturnEvaluation qualified as Return
import JitML.RL.NativeReturnReferences qualified as Ref
import JitML.RL.ProductBudget qualified as Product
import JitML.RL.TrainerConfiguration qualified as Config
import JitML.Substrate (Substrate (..))

data ReturnedFixture
  = ReturnedFixture
      Return.RawNativeReturnEvaluation
      Decode.ReturnConfiguration
      Digest
      Graph.NodePool
      Digest
      Digest
data Fixture
  = Fixture
      Cohort.NativeRlCohortBatch
      [ReturnedFixture]
      (HerEval.RawNativeHerEvaluation, Her.HerTrainConfig, Digest, Graph.NodePool, Digest, Digest)
data InputFault = UnicodeFault | EndlessFault | AsyncRendererFault deriving stock (Show)
instance Exception InputFault where
  displayException UnicodeFault = "parent policy input λ🙂"
  displayException EndlessFault = repeat 'x'
  displayException AsyncRendererFault = throw ThreadKilled

nativeParentPolicyDataTests :: TestTree
nativeParentPolicyDataTests =
  testGroup
    "native parent recorded policy DATA"
    [ withResource acquire (const (pure ())) $ \get ->
        testGroup
          "complete public evaluator records"
          ( [ testCase ("complete " <> name <> " ordinary evaluation decodes losslessly") $ do
                fixture <- get
                returned <- pick index fixture
                decoded <- decodeReturned returned
                (root, pool) <- projectReturn decoded
                let ReturnedFixture _ _ expected expectedPool _ _ = returned
                root @?= expected
                entries pool @?= entries expectedPool
            | (index, name) <- zip [0 ..] ["PPO", "DQN", "QR-DQN", "SAC", "ARS"]
            ]
              <> [ testCase ("recorded " <> name <> " transition audit reuses the public evaluator") $ do
                     fixture <- get
                     ReturnedFixture raw _ _ _ _ _ <- pick index fixture
                     result <- Rule.auditReturnEvaluationData raw
                     result @?= Right ()
                 | (index, name) <- zip [0 ..] ["PPO", "DQN", "QR-DQN", "SAC", "ARS"]
                 ]
              <> [ testCase "complete HER outcomes and every forward decode losslessly" $ do
                     Fixture _ _ (raw, config, root, pool, scheduleRoot, configRoot) <- get
                     actual <-
                       right
                         ( Node.runDecode
                             pool
                             (Decode.herEvaluation (HerEval.nativeHerEvaluationSchedule raw) scheduleRoot config configRoot root)
                         )
                     (observed, after) <- Project.projectHerEvaluationData Graph.emptyNodePool actual >>= right
                     observed @?= root
                     entries after @?= entries pool
                 , testCase "changed ARS case reward fails actual host policy rule replay" $ do
                     fixture <- get
                     ReturnedFixture raw _ _ _ _ _ <- pick 4 fixture
                     let changed =
                           raw
                             { Return.nativeEvaluationEpisodes = case Return.nativeEvaluationEpisodes raw of
                                 first : rest -> first {Ref.nativeReturnEpisodeReward = Ref.nativeReturnEpisodeReward first + 1} : rest
                                 [] -> []
                             }
                     result <- Rule.auditReturnEvaluationData changed
                     left result
                 , testCase "changed neural forward input fails recorded transition replay" $ do
                     fixture <- get
                     ReturnedFixture raw _ _ _ _ _ <- pick 1 fixture
                     let changed =
                           raw
                             { Return.nativeEvaluationForwards = case Return.nativeEvaluationForwards raw of
                                 first : rest -> first {Return.nativeForwardInput = VU.map (+ 1) (Return.nativeForwardInput first)} : rest
                                 [] -> []
                             }
                     assertBool "actual fixture has nonempty forwards" (not (null (Return.nativeEvaluationForwards raw)))
                     Rule.auditReturnEvaluationData changed >>= left
                 , testCase "wrong full configuration root refuses before policy reconstruction" $ do
                     fixture <- get
                     ReturnedFixture raw config root pool specRoot _ <- pick 0 fixture
                     left
                       ( Node.runDecode
                           pool
                           ( Decode.returnEvaluation
                               (Return.nativeEvaluationSpec raw)
                               specRoot
                               config
                               (hashBytes "wrong config")
                               root
                           )
                       )
                 , testCase "wrong fixed specification root refuses before case comparison" $ do
                     fixture <- get
                     ReturnedFixture raw config root pool _ configRoot <- pick 0 fixture
                     left
                       ( Node.runDecode
                           pool
                           ( Decode.returnEvaluation
                               (Return.nativeEvaluationSpec raw)
                               (hashBytes "wrong spec")
                               config
                               configRoot
                               root
                           )
                       )
                 , testCase "a genuine projected rejected evaluation never becomes complete DATA" $ do
                     fixture <- get
                     ReturnedFixture raw config _ _ specRoot configRoot <- pick 0 fixture
                     let rejected = raw {Return.nativeEvaluationStatus = Return.NativeEvaluationRejected "actual DATA refusal"}
                     (root, pool) <- projectReturn rejected
                     left
                       ( Node.runDecode
                           pool
                           (Decode.returnEvaluation (Return.nativeEvaluationSpec raw) specRoot config configRoot root)
                       )
                 , testCase "changed complete work cannot hide behind a complete status" $ do
                     fixture <- get
                     ReturnedFixture raw config _ _ specRoot configRoot <- pick 0 fixture
                     (root, pool) <- projectReturn (raw {Return.nativeEvaluationWork = Return.NativeCompleteWork 0})
                     left
                       ( Node.runDecode
                           pool
                           (Decode.returnEvaluation (Return.nativeEvaluationSpec raw) specRoot config configRoot root)
                       )
                 , testCase "all canonical neural descriptors classify exactly five continuous cold families" $ do
                     Fixture batch _ _ <- get
                     let plans =
                           [ (Matrix.rowClass (Cohort.nativeRlCohortPlanRow row), compiled)
                           | row <- Cohort.nativeRlCohortBatchPlans batch
                           , Just compiled <- [Cohort.nativeRlSeedPlanCompiledReturn (Cohort.nativeRlCohortServingChild row)]
                           , Product.compiledRlTrainerKind compiled /= "ars"
                           ]
                     observed <-
                       mapM
                         ( \(row, compiled) -> do
                             recipe <- right (Config.resolveNeuralTrainerRecipe compiled)
                             let actual = Parent.nativeParentPreparationPhaseForConfiguration (Config.neuralTrainerConfiguration recipe)
                                 expected = case row of
                                   Matrix.RlAlgorithmEnvironment name _ | name `elem` ["DDPG", "TD3", "SAC", "CrossQ", "TQC"] -> ColdSnapshotPhase
                                   _ -> EffectiveSnapshotPhase
                             actual @?= expected
                             pure actual
                         )
                         plans
                     let coldRows =
                           [ (algorithm, environment)
                           | ((Matrix.RlAlgorithmEnvironment algorithm environment, _), ColdSnapshotPhase) <- zip plans observed
                           ]
                     -- Five algorithm families occupy six canonical rows:
                     -- SAC has both lunar-lander and pendulum cohorts.
                     sort coldRows
                       @?= sort
                         [ ("DDPG", "lunar-lander")
                         , ("TD3", "lunar-lander")
                         , ("SAC", "lunar-lander")
                         , ("SAC", "pendulum")
                         , ("CrossQ", "lunar-lander")
                         , ("TQC", "lunar-lander")
                         ]
                     length (nub (fmap fst coldRows)) @?= 5
                     length observed @?= 35
                     length (filter (== ColdSnapshotPhase) observed) @?= 6
                     length (filter (== EffectiveSnapshotPhase) observed) @?= 29
                 ]
          )
    , testGroup
        "bounded node and lineage DATA"
        [ testCase "raw F64 negative zero is retained by the tensor decoder" $ do
            (root, pool) <-
              right (Builder.internTensor (Wire.word64Bytes 0x8000000000000000) Graph.emptyNodePool)
            vector <- right (Node.runDecode pool (Node.tensor 1 root))
            VU.toList (VU.map castDoubleToWord64 vector) @?= [0x8000000000000000]
        , testCase "tensor declared width refuses before materializing a larger vector" $ do
            (root, pool) <- right (Builder.internTensor (BS.replicate 32 0) Graph.emptyNodePool)
            left (Node.runDecode pool (Node.tensor 0 root))
        , testCase "shared sequence declared count refuses before occurrence expansion" $ do
            page <-
              right
                ( Schema.mkNodeData
                    NScalarPage
                    [Schema.elementKindValue (ScalarElement ScalarInt), VWord 256, VList (replicate 256 (VInt 0))]
                )
            (pageRoot, pool) <- right (Graph.internNode page Graph.emptyNodePool)
            manifest <-
              right
                ( Schema.mkNodeData
                    NSequenceManifest
                    [ Schema.elementKindValue (ScalarElement ScalarInt)
                    , VWord 65536
                    , VWord 1
                    , VList (replicate 256 (VRef pageRoot))
                    ]
                )
            (root, after) <- right (Graph.internNode manifest pool)
            length (Graph.nodePoolEntries after) @?= 2
            left (Node.runDecode after (Node.sequenceData (ScalarElement ScalarInt) 20 root))
        , testCase "ARS dedicated record accepts only the host NoMLP alternative" $ do
            Lineage.verifyDevice LinuxCPU True (deviceBytes (CBOR.encodeListLen 1 <> CBOR.encodeWord64 0))
              @?= Right Lineage.NativeHostNoMlpData
        , testCase "neural device absence remains a refusal rather than a witness" $
            left
              ( Lineage.verifyDevice
                  LinuxCPU
                  False
                  (deviceBytes (CBOR.encodeListLen 2 <> CBOR.encodeWord64 2 <> CBOR.encodeNull))
              )
        , testCase "recorded witness DATA with the wrong lane is rejected" $
            left (Lineage.verifyDevice AppleSilicon False (deviceBytes witnessBody))
        , testCase "well-shaped recorded device remains forgeable raw DATA only" $ do
            result <- right (Lineage.verifyDevice LinuxCPU False (deviceBytes witnessBody))
            case result of
              Lineage.NativeRecordedDeviceData _ -> pure ()
              _ -> assertFailure "neural record was relabeled host"
        , testCase "parent-owned executable expectation rejects equal child self-claims" $
            left
              ( Lineage.verifyProducer
                  (expectations {Lineage.nativeParentExpectedExecutable = hashBytes "other executable"})
                  recorded
              )
        , testCase "parent externally observed process IDs reject a substituted PID" $
            left (Lineage.verifyProducer expectations (recorded {Process.recordedProcessId = 456}))
        , testCase "parent original observed-source role cannot be omitted" $
            left (Lineage.verifyProducer expectations (recorded {Process.recordedObservedSource = Nothing}))
        ]
    , withResource acquireLineage (const (pure ())) $ \get ->
        testGroup
          "closed ARS lineage DATA"
          [ testCase "begun DATA retains distinct original outer and inner attempt identities" $ do
              (begun, _) <- get
              actual <- right (Lineage.decodeArsLineage False begun)
              Lineage.nativeLineageOuterAttempt actual @?= hashBytes "outer recorded attempt"
              Lineage.nativeLineageAcquisition actual @?= hashBytes "recorded acquisition"
              Lineage.nativeLineageInnerAttempt actual @?= Text.replicate 64 "1"
              Lineage.nativeLineageSource actual
                @?= Just (Lineage.NativeArsObservedSourceData "/ordinary/source" stamp)
          , testCase "origin DATA preserves full before after and native runtime descriptions" $ do
              (_, origin) <- get
              actual <- right (Lineage.decodeArsLineage True origin)
              Lineage.nativeLineageBefore actual @?= recorded
              Lineage.nativeLineageAfter actual @?= Just recorded
              Lineage.nativeLineageRuntime actual @?= Just Ars.arsNativeNumericalRuntime
          , testCase "begun payload cannot be relabeled as an origin payload" $ do
              (begun, _) <- get
              left (Lineage.decodeArsLineage True begun)
          , testCase "origin payload cannot be relabeled as begun source coverage" $ do
              (_, origin) <- get
              left (Lineage.decodeArsLineage False origin)
          , testCase "ARS lineage parser rejects trailing payload without restoring an origin" $ do
              (begun, _) <- get
              left (Lineage.decodeArsLineage False (begun <> BS.singleton 0))
          , testCase
              "matching child-supplied lineage hashes do not replace exact canonical context verification"
              $ do
                (begunBytes, originBytes) <- get
                begun <- right (Lineage.decodeArsLineage False begunBytes)
                origin <- right (Lineage.decodeArsLineage True originBytes)
                batch <- right (Cohort.mkCanonicalNativeRlCohorts LinuxCPU)
                cohort <-
                  maybe
                    (fail "canonical ARS row absent")
                    pure
                    ( find
                        ((== Matrix.RlAlgorithmEnvironment "ARS" "cartpole") . Matrix.rowClass . Cohort.nativeRlCohortPlanRow)
                        (Cohort.nativeRlCohortBatchPlans batch)
                    )
                left
                  ( Lineage.verifyArsLineage
                      expectations
                      cohort
                      (Cohort.nativeRlCohortServingChild cohort)
                      (hashBytes "outer recorded attempt")
                      (hashBytes "recorded acquisition")
                      begun
                      origin
                  )
          , testCase "ARS lineage whole bound refuses before parsing an oversized envelope" $
              left (Lineage.decodeArsLineage False (BS.replicate 65537 0))
          ]
    , testGroup
        "actual public preflight"
        [ testCase "poisoned batch becomes bounded failure without restoring parent DATA" $ do
            value <- Parent.verifyNativeParentPolicyData (error "parent batch fault") expectations absentBinding
            mustSynchronous value
        , testCase "Unicode synchronous diagnostic remains exact" $ do
            value <- Parent.verifyNativeParentPolicyData (throw UnicodeFault) expectations absentBinding
            case value of
              Left (Parent.NativeParentPolicySynchronousFailure actual) -> actual @?= Failure.CompleteNativeDiagnostic "parent policy input λ🙂"
              _ -> assertFailure "Unicode diagnostic was changed"
        , testCase "endless exception rendering is bounded without a complete prefix" $ do
            value <-
              timeout
                10000000
                (Parent.verifyNativeParentPolicyData (throw EndlessFault) expectations absentBinding)
            case value of
              Just
                ( Left
                    ( Parent.NativeParentPolicySynchronousFailure
                        (Failure.OversizeNativeDiagnostic (Failure.LowerBoundNativeSize n))
                      )
                  ) ->
                  toInteger n @?= nativePhaseLimit DiagnosticTextBytes + 1
              _ -> assertFailure "endless rendering escaped or became complete"
        , testCase "input async cancellation propagates from the public entry" $ do
            value <-
              try (Parent.verifyNativeParentPolicyData (throw ThreadKilled) expectations absentBinding)
                :: IO (Either AsyncException (Either Parent.NativeParentPolicyFailure Parent.NativeParentPolicyData))
            assertAsync value
        , testCase "diagnostic renderer async cancellation propagates" $ do
            value <-
              try (Parent.verifyNativeParentPolicyData (throw AsyncRendererFault) expectations absentBinding)
                :: IO (Either AsyncException (Either Parent.NativeParentPolicyFailure Parent.NativeParentPolicyData))
            assertAsync value
        ]
    , withResource acquireArena (const (pure ())) $ \get ->
        testGroup
          "shared arena mathematics"
          [ testCase "DATA comparison preserves actual-calibration seed median and finding results" $ do
              (calibration, observations) <- get
              old <- right (ArenaPolicy.compareNativeArenaCohort calibration observations)
              new <-
                right
                  ( ArenaPolicy.compareNativeArenaCohortData
                      (ArenaPolicy.nativeArenaCalibrationSpec calibration)
                      (ArenaPolicy.nativeArenaCalibrationTape calibration)
                      (ArenaPolicy.nativeArenaCalibrationReferences calibration)
                      observations
                  )
              ArenaPolicy.nativeArenaDataSeeds new @?= ArenaPolicy.nativeArenaComparisonSeeds old
              ArenaPolicy.nativeArenaDataJointCount new @?= ArenaPolicy.nativeArenaComparisonJointCount old
              ArenaPolicy.nativeArenaDataMedianCriteria new
                @?= ArenaPolicy.nativeArenaComparisonMedianCriteria old
              ArenaPolicy.nativeArenaDataFindings new @?= ArenaPolicy.nativeArenaComparisonFindings old
              assertBool
                "same initial and final DATA cannot claim strict learning"
                (ArenaPolicy.nativeArenaDataJointCount new == 0)
          , testCase "DATA comparison audits the complete reference inventory" $ do
              (calibration, observations) <- get
              let original = ArenaPolicy.nativeArenaCalibrationReferences calibration
                  changed =
                    original
                      { ArenaRef.nativeArenaObservedReferences = take 1 (ArenaRef.nativeArenaObservedReferences original)
                      }
              left
                ( ArenaPolicy.compareNativeArenaCohortData
                    (ArenaPolicy.nativeArenaCalibrationSpec calibration)
                    (ArenaPolicy.nativeArenaCalibrationTape calibration)
                    changed
                    observations
                )
          , testCase "DATA comparison cannot replace five outcomes with a selected subset" $ do
              (calibration, observations) <- get
              left
                ( ArenaPolicy.compareNativeArenaCohortData
                    (ArenaPolicy.nativeArenaCalibrationSpec calibration)
                    (ArenaPolicy.nativeArenaCalibrationTape calibration)
                    (ArenaPolicy.nativeArenaCalibrationReferences calibration)
                    (take 3 observations)
                )
          ]
    ]

acquire :: IO Fixture
acquire = do
  batch <- right (Cohort.mkCanonicalNativeRlCohorts LinuxCPU)
  returned <-
    mapM
      (makeReturn batch)
      [ ("PPO", "cartpole")
      , ("DQN", "cartpole")
      , ("QR-DQN", "cartpole")
      , ("SAC", "pendulum")
      , ("ARS", "cartpole")
      ]
  compiled <- compiledFor batch "HER" "goal-reaching"
  recipe <- right (Config.resolveNeuralTrainerRecipe compiled)
  config <- case Config.neuralTrainerConfiguration recipe of
    Config.HerConfiguration value -> pure value
    _ -> fail "HER fixture family"
  spec <- right HerRef.canonicalNativeHerReferenceSpec
  schedule <- right (HerRef.generateNativeHerGoalSchedule spec)
  let params =
        Mlp.mlpInit
          (Mlp.MlpShape (2 * Her.herNumBits config) (Her.herHiddenUnits config) (Her.herNumBits config))
          42
  raw <- HerEval.evaluateNativeHerPolicy pureReferenceMlpDevice schedule config params
  (root, pool) <- Project.projectHerEvaluationData Graph.emptyNodePool raw >>= right
  (scheduleRoot, configRoot) <-
    right
      ( Node.runDecode pool $ do
          actual <- Node.fields NHerEvaluation root
          case actual of VRef s : VRef c : _ -> pure (s, c); _ -> Node.reject "actual HER fixture fields"
      )
  pure (Fixture batch returned (raw, config, root, pool, scheduleRoot, configRoot))
makeReturn :: Cohort.NativeRlCohortBatch -> (Text, Text) -> IO ReturnedFixture
makeReturn batch (algorithm, environment) = do
  compiled <- compiledFor batch algorithm environment
  spec <- right (Ref.canonicalNativeReturnSpec algorithm environment)
  (raw, context) <-
    if algorithm == "ARS"
      then do
        (_, config) <- right (ArsTrace.resolveArsHostPlanData compiled)
        pure
          ( Return.evaluateNativeArsReturnPolicy
              spec
              config
              (VU.replicate (Ars.arsActionCount config * Ars.arsObsSize config) 0)
          , Decode.ArsConfiguration config
          )
      else do
        recipe <- right (Config.resolveNeuralTrainerRecipe compiled)
        let config = Config.neuralTrainerConfiguration recipe
            shape = case config of
              Config.OnPolicyConfiguration c -> Mlp.MlpShape (Ppo.ppoObsSize c) (Ppo.ppoHiddenUnits c) (Ppo.ppoActionCount c + 1)
              Config.DqnConfiguration c -> Mlp.MlpShape (Dqn.dqnObsSize c) (Dqn.dqnHiddenUnits c) (Dqn.dqnActionCount c)
              Config.QrDqnConfiguration c -> Mlp.MlpShape (Qr.qrObsSize c) (Qr.qrHiddenUnits c) (Qr.qrActionCount c * Qr.qrNumQuantiles c)
              Config.ContinuousConfiguration c -> Mlp.MlpShape (Continuous.ctObsSize c) (Continuous.ctHidden c) 1
              Config.HerConfiguration c -> Mlp.MlpShape (2 * Her.herNumBits c) (Her.herHiddenUnits c) (Her.herNumBits c)
            params = Mlp.mlpInit shape 42
        policy <- case config of
          Config.OnPolicyConfiguration c -> pure (Return.NativeOnPolicy c params)
          Config.DqnConfiguration c -> pure (Return.NativeDqn c params)
          Config.QrDqnConfiguration c -> pure (Return.NativeQrDqn c params)
          Config.ContinuousConfiguration c -> pure (Return.NativeContinuous c params)
          _ -> fail "return fixture family"
        actual <- Return.evaluateNativeNeuralReturnPolicy pureReferenceMlpDevice spec policy
        pure (actual, Decode.NeuralConfiguration config)
  (root, pool) <- projectReturn raw
  (specRoot, configRoot) <-
    right
      ( Node.runDecode pool $ do
          actual <- Node.fields NReturnEvaluation root
          case actual of
            VRef s : VRef p : _ -> do
              policy <- Node.fields NReturnPolicy p
              case policy of _ : VRef c : _ -> pure (s, c); _ -> Node.reject "actual policy config absent"
            _ -> Node.reject "actual RETURN fixture fields"
      )
  pure (ReturnedFixture raw context root pool specRoot configRoot)
compiledFor :: Cohort.NativeRlCohortBatch -> Text -> Text -> IO Product.CompiledRlPlan
compiledFor batch algorithm environment = do
  cohort <-
    maybe
      (fail "canonical fixture row absent")
      pure
      ( find
          ( ( ==
                ( if algorithm == "HER"
                    then Matrix.RlGoalConditioned environment
                    else Matrix.RlAlgorithmEnvironment algorithm environment
                )
            )
              . Matrix.rowClass
              . Cohort.nativeRlCohortPlanRow
          )
          (Cohort.nativeRlCohortBatchPlans batch)
      )
  maybe
    (fail "canonical fixture compiler absent")
    pure
    (Cohort.nativeRlSeedPlanCompiledReturn (Cohort.nativeRlCohortServingChild cohort))
pick :: Int -> Fixture -> IO ReturnedFixture
pick index (Fixture _ values _) = case drop index values of actual : _ -> pure actual; _ -> fail "fixture index absent"
decodeReturned :: ReturnedFixture -> IO Return.RawNativeReturnEvaluation
decodeReturned (ReturnedFixture raw context root pool spec config) =
  right
    ( Node.runDecode
        pool
        (Decode.returnEvaluation (Return.nativeEvaluationSpec raw) spec context config root)
    )
projectReturn :: Return.RawNativeReturnEvaluation -> IO (Digest, Graph.NodePool)
projectReturn raw = Project.projectReturnEvaluationData Graph.emptyNodePool raw >>= right
entries :: Graph.NodePool -> [(Digest, ByteString)]
entries pool = [(digest, bytes) | (digest, _, bytes) <- Graph.nodePoolEntries pool]
deviceBytes :: CBOR.Encoding -> ByteString
deviceBytes body =
  Wire.encodeStrict
    ( CBOR.encodeListLen 3
        <> CBOR.encodeString "jitml-native-device-observation-v1"
        <> CBOR.encodeWord64 1
        <> body
    )
witnessBody :: CBOR.Encoding
witnessBody =
  CBOR.encodeListLen 2
    <> CBOR.encodeWord64 2
    <> CBOR.encodeListLen 6
    <> foldMap
      CBOR.encodeString
      [ "linux-cpu"
      , "ordinary recorded backend"
      , Text.replicate 64 "a"
      , "/ordinary/recorded/artifact"
      , Text.replicate 64 "b"
      , "ordinary recorded executed identity"
      ]
stamp :: Source.SourceStamp
stamp = Source.SourceStamp 1 (Text.replicate 64 "c")
expectations :: Lineage.NativeParentExpectations
expectations =
  Lineage.NativeParentExpectations
    stamp
    (hashBytes "recorded executable")
    (Context.DirectLocalContext (hashBytes "ordinary acquisition"))
    (Context.NativeContextSources (Just stamp) Nothing)
    (123, 12)
recorded :: Process.RecordedProducerObservation
recorded =
  Process.RecordedProducerObservation
    "/ordinary/executable"
    (hex (hashBytes "recorded executable"))
    100
    123
    12
    "darwin"
    "arm64"
    "ordinary release"
    "darwin"
    "aarch64"
    "ghc"
    "9.12.4"
    (Just ("/ordinary/source", stamp))
hex :: Digest -> Text
hex =
  Text.pack
    . concatMap
      (\byte -> [digits !! fromIntegral (byte `div` 16), digits !! fromIntegral (byte `mod` 16)])
    . BS.unpack
    . digestBytes
 where
  digits = "0123456789abcdef"
absentBinding :: Binding.NativeParentBindingData
absentBinding = error "preflight must not inspect or fabricate a parent binding"
acquireArena
  :: IO (ArenaPolicy.NativeArenaReferenceCalibration, [ArenaPolicy.NativeArenaSeedObservation])
acquireArena = do
  spec <- right (ArenaRef.canonicalNativeArenaSpec "connect4")
  calibration <- ArenaPolicy.observeNativeArenaReferenceCalibration spec >>= right
  let tape = ArenaPolicy.nativeArenaCalibrationTape calibration
      net =
        Net.initPolicyValueNet
          (ArenaRef.nativeArenaSpecObservationSize spec)
          (ArenaRef.nativeArenaSpecActionCount spec)
          16
          42
  raw <- Arena.evaluateNativeArenaPolicy pureReferenceMlpDevice spec tape net
  pure
    ( calibration
    , [ArenaPolicy.NativeArenaSeedObservation index (42 + fromIntegral index) raw raw | index <- [0 .. 4]]
    )
right :: (Show failure) => Either failure value -> IO value
right value = case value of
  Right actual -> pure actual
  Left failure -> assertFailure (show failure) >> fail "unexpected refusal"
left :: Either failure value -> Assertion
left value = case value of Left _ -> pure (); Right _ -> assertFailure "unexpected DATA acceptance"
mustSynchronous
  :: Either Parent.NativeParentPolicyFailure Parent.NativeParentPolicyData -> Assertion
mustSynchronous value = case value of
  Left (Parent.NativeParentPolicySynchronousFailure _) -> pure ()
  _ -> assertFailure "poisoned input became parent policy DATA"
assertAsync :: Either AsyncException value -> Assertion
assertAsync value = case value of
  Left ThreadKilled -> pure ()
  _ -> assertFailure "async cancellation became a DATA refusal"

-- Ordinary supplied process DATA is projected, never observed or minted as a
-- process/origin cap. Both raw domains are tested independently of auth.
acquireLineage :: IO (ByteString, ByteString)
acquireLineage = do
  (before, beforePool) <-
    ProducerData.projectProducerContextData Graph.emptyNodePool (Just recorded) Nothing Nothing
      >>= right
  (after, afterPool) <-
    ProducerData.projectProducerContextData Graph.emptyNodePool (Just recorded) (Just recorded) Nothing
      >>= right
  let prefix domain producer pool =
        CBOR.encodeListLen 9
          <> CBOR.encodeString domain
          <> CBOR.encodeWord64 1
          <> CBOR.encodeBytes (digestBytes (hashBytes "outer recorded attempt"))
          <> CBOR.encodeBytes (digestBytes (hashBytes "recorded acquisition"))
          <> CBOR.encodeString (Text.replicate 64 "1")
          <> CBOR.encodeBytes (digestBytes (hashBytes "recorded context"))
          <> CBOR.encodeBytes (digestBytes producer)
          <> CBOR.encodeListLen (fromIntegral (length (entries pool)))
          <> foldMap
            ( \(digest, bytes) -> CBOR.encodeListLen 2 <> CBOR.encodeBytes (digestBytes digest) <> CBOR.encodeBytes bytes
            )
            (entries pool)
      source =
        CBOR.encodeListLen 3
          <> CBOR.encodeWord64 0
          <> CBOR.encodeString "/ordinary/source"
          <> CBOR.encodeListLen 2
          <> CBOR.encodeWord64 1
          <> CBOR.encodeString (Source.stampSha256 stamp)
      runtime = Ars.arsNativeNumericalRuntime
      runtimeFields =
        [ Ars.arsRuntimeOperatingSystem runtime
        , Ars.arsRuntimeArchitecture runtime
        , Ars.arsRuntimeCompiler runtime
        , Ars.arsRuntimeCompilerVersion runtime
        , Ars.arsRuntimeArithmeticRecipe runtime
        ]
  pure
    ( Wire.encodeStrict (prefix "jitml-native-ars-begun-lineage-v1" before beforePool <> source)
    , Wire.encodeStrict
        ( prefix "jitml-native-ars-origin-lineage-v1" after afterPool
            <> CBOR.encodeListLen 5
            <> foldMap CBOR.encodeString runtimeFields
        )
    )
