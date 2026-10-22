{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- Ordinary captured DATA only. Public checked-batch selection failures below
-- perform no initialization, device query, training, process or durable write.
module NativePhaseFailure (nativePhaseFailureTests) where

import Control.Exception
  ( AsyncException (ThreadKilled)
  , Exception (displayException)
  , throw
  , toException
  , try
  )
import Control.Monad (forM_, (>=>))
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as Text
import System.Timeout (timeout)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

import JitML.Checkpoint.NativePhase.Failure
import JitML.Checkpoint.NativePhase.Graph qualified as Graph
import JitML.Checkpoint.NativePhase.Projection
  ( ProjectionDiagnostic (..)
  , ProjectionFailure (..)
  , projectReturnEvaluationData
  )
import JitML.Checkpoint.NativePhase.Schema qualified as Schema
import JitML.Checkpoint.NativePhase.Types
import JitML.Product.NativePreparedAlphaZeroAttempt qualified as Arena
import JitML.Product.NativePreparedArsAttempt qualified as Ars
import JitML.Product.NativePreparedNeuralAttempt qualified as Neural
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.Substrate (Substrate (LinuxCPU))

-- Ordinary hostile exception renderers; no producer or execution capsule.
data DiagnosticRenderer = ExactRenderer | EndlessRenderer | LazyRenderer | AsyncRenderer
instance Show DiagnosticRenderer where
  show _ = "diagnostic renderer control"
instance Exception DiagnosticRenderer where
  displayException ExactRenderer = "actual diagnostic \x1f642"
  displayException EndlessRenderer = repeat 'x'
  displayException LazyRenderer = "actual prefix" <> error "renderer tail failed"
  displayException AsyncRenderer = throw ThreadKilled

right :: (Show e) => Either e a -> IO a
right value = case value of
  Right actual -> pure actual
  Left reason -> assertFailure (show reason) >> fail "unreachable"

nodeAt :: Graph.NodePool -> Digest -> IO Schema.NodeData
nodeAt pool digest = case Graph.lookupNode digest pool of
  Just actual -> pure actual
  Nothing -> assertFailure "node missing" >> fail "unreachable"

field :: Schema.NodeData -> Text -> IO NodeValue
field node name = case lookup name (zip (Schema.nodeFieldNames (Schema.nodeKind node)) (Schema.nodeFields node)) of
  Just actual -> pure actual
  Nothing -> assertFailure ("missing field " <> Text.unpack name) >> fail "unreachable"

captured
  :: NativeFailureOrigin
  -> NativeReturnMaterialization
  -> NativeFailureCaptureStatus
  -> NativeFailurePayloads
  -> IO Schema.NodeData
captured origin returned status payloads = do
  (root, pool) <- projectSafeFailureData Graph.emptyNodePool origin returned status payloads >>= right
  nodeAt pool root

phaseOrigin :: NativeAttemptFamily -> NativeFailureOrigin
phaseOrigin family =
  NativePhaseCaptureFailure
    family
    RawReturnPhase
    CompleteNativeFailureCapture
    UnmaterializableNativeDiagnostic

nativePhaseFailureTests :: TestTree
nativePhaseFailureTests =
  testGroup
    "complete native phase failure DATA"
    [ testCase "all seven family tags remain exact ordinary values"
        $ forM_
          ( zip
              [ NativeOnPolicyFamily
              , NativeDqnFamily
              , NativeQrFamily
              , NativeContinuousFamily
              , NativeHerFamily
              , NativeArsFamily
              , NativeArenaFamily
              ]
              [0 .. 6]
          )
        $ \(family, tag) -> do
          node <-
            captured
              (phaseOrigin family)
              NoReturnObserved
              CompleteNativeFailureCapture
              emptyNativeFailurePayloads
          field node "family" >>= (@?= VWord tag)
    , testCase "four actual return-materialization classifications remain distinct"
        $ forM_
          ( zip
              [NoReturnObserved, ReturnedButUnmaterializable, MaterializedBindingRejected, MaterializedReturned]
              [0 .. 3]
          )
        $ \(returned, tag) -> do
          node <-
            captured
              (phaseOrigin NativeHerFamily)
              returned
              CompleteNativeFailureCapture
              emptyNativeFailurePayloads
          field node "returnMaterialization" >>= (@?= VWord tag)
    , testCase "initial payload coverage is explicitly not attempted rather than guessed absent" $ do
        node <-
          captured
            (phaseOrigin NativeArsFamily)
            NoReturnObserved
            CompleteNativeFailureCapture
            emptyNativeFailurePayloads
        field node "payloadCoverage" >>= (@?= VList (replicate 6 (VList [VWord 5])))
        forM_ ["snapshot", "coldSnapshot", "raw", "initialEvaluation", "currentEvaluation", "lowFailure"] $
          field node >=> (@?= VNull)
    , testCase
        "all six payload statuses retain independent slot order and only Present carries a reference"
        $ do
          facts <- right (Schema.mkNodeData NLowNeuralFailureFacts (replicate 5 VNull))
          (factsId, p1) <- right (Graph.internNode facts Graph.emptyNodePool)
          failure <-
            right
              (Schema.mkNodeData NLowNeuralFailure [VWord 0, VWord 0, VText "ordinary wire fixture", VRef factsId])
          (failureId, p2) <- right (Graph.internNode failure p1)
          let payloads =
                NativeFailurePayloads
                  NativePayloadAbsent
                  NativePayloadUnavailable
                  NativePayloadUnmaterializable
                  (NativePayloadRefused WholePayloadBytes 268435456 UnknownNativeSize)
                  NativePayloadNotAttempted
                  (NativePayloadPresent failureId)
          (root, pool) <-
            projectSafeFailureData
              p2
              (phaseOrigin NativeDqnFamily)
              ReturnedButUnmaterializable
              CompleteNativeFailureCapture
              payloads
              >>= right
          node <- nodeAt pool root
          field node "payloadCoverage"
            >>= ( @?=
                    VList
                      [ VList [VWord 1]
                      , VList [VWord 2]
                      , VList [VWord 3]
                      , VList [VWord 4, VWord 0, VWord 268435456, VList [VWord 2]]
                      , VList [VWord 5]
                      , VList [VWord 0]
                      ]
                )
          field node "lowFailure" >>= (@?= VRef failureId)
          closure <- right (Graph.reachableNodePool [root] pool)
          _ <- right (Graph.validateReachableData [root] closure)
          pure ()
    , testCase "a caller reference to the wrong payload kind is rejected by the real graph boundary" $ do
        tensor <- right (Schema.mkNodeData NTensorLeaf [VWord 0, VBytes BS.empty])
        (digest, pool) <- right (Graph.internNode tensor Graph.emptyNodePool)
        result <-
          projectSafeFailureData
            pool
            (phaseOrigin NativeArsFamily)
            MaterializedReturned
            CompleteNativeFailureCapture
            (emptyNativeFailurePayloads {nativeFailureRawPayload = NativePayloadPresent digest})
        case result of
          Left (ProjectionDataRejected (WrongReferenceType _ _)) -> pure ()
          _ -> assertFailure "wrong raw payload type entered failure graph"
    , testCase "duplicated Unsupported status retains both complete path-reason pairs" $ do
        let path = Text.replicate 1024 "p"
            reason = Text.replicate 1024 "r"
            status = UnsupportedNativeCapture path reason
        node <-
          captured
            ( NativePhaseCaptureFailure
                NativeArsFamily
                FinalEvaluationPhase
                status
                UnmaterializableNativeDiagnostic
            )
            MaterializedReturned
            status
            emptyNativeFailurePayloads
        let encoded = VList [VWord 1, VText path, VText reason]
        field node "kind" >>= (@?= VList [VWord 1, encoded])
        field node "captureStatus" >>= (@?= encoded)
        field node "stage" >>= (@?= VList [VWord 1, VWord 5])
        decoded <- right (Schema.decodeNodeData (Schema.nodeCanonicalBytes node))
        Schema.nodeFields decoded @?= Schema.nodeFields node
    , testCase "exact lower-bound and unknown resource-size knowledge remain separate DATA"
        $ forM_
          [ (ExactNativeSize 9, VList [VWord 0, VWord 9])
          , (LowerBoundNativeSize 9, VList [VWord 1, VWord 9])
          , (UnknownNativeSize, VList [VWord 2])
          ]
        $ \(known, wire) -> do
          let status = RefusedNativeCapture FrameBytes 8388608 known
          node <-
            captured
              ( NativePhaseCaptureFailure
                  NativeHerFamily
                  EffectiveSnapshotPhase
                  status
                  UnmaterializableNativeDiagnostic
              )
              ReturnedButUnmaterializable
              status
              emptyNativeFailurePayloads
          field node "captureStatus" >>= (@?= VList [VWord 2, VWord 21, VWord 8388608, wire])
    , testCase "a finite diagnostic is completely materialized without truncation" $ do
        let detail = Text.replicate 2000 "\x10000"
        captureNativeDiagnostic detail >>= (@?= CompleteNativeDiagnostic detail)
    , testCase "an oversized character count records only its truthful byte lower bound" $ do
        let n = 1048577
        captureNativeDiagnostic (Text.replicate n "a")
          >>= (@?= OversizeNativeDiagnostic (LowerBoundNativeSize (fromIntegral n)))
    , testCase "an oversized multibyte diagnostic records actual complete encoded length" $ do
        captureNativeDiagnostic (Text.replicate 262145 "\x10000")
          >>= (@?= OversizeNativeDiagnostic (ExactNativeSize 1048580))
    , testCase
        "a diagnostic materialization fault is explicit absence without exposing a poisonous payload"
        $ captureNativeDiagnostic (error "diagnostic bottom") >>= (@?= UnmaterializableNativeDiagnostic)
    , testCase "async diagnostic cancellation propagates instead of becoming absent DATA" $ do
        result <-
          try (captureNativeDiagnostic (throw ThreadKilled))
            :: IO (Either AsyncException NativeDiagnosticData)
        case result of
          Left ThreadKilled -> pure ()
          _ -> assertFailure "async cancellation swallowed"
    , testCase "a lazy capture-status failure is handled by the projection safe boundary" $ do
        let status = SynchronousNativeCaptureFailure (error "capture path bottom")
        result <-
          projectSafeFailureData
            Graph.emptyNodePool
            (NativePhaseCaptureFailure NativeOnPolicyFamily StartedPhase status UnmaterializableNativeDiagnostic)
            NoReturnObserved
            status
            emptyNativeFailurePayloads
        case result of
          Left (ProjectionSynchronousFailure _) -> pure ()
          _ -> assertFailure "lazy capture status escaped or manufactured data"
    , testCase "public three-family selection failures preserve actual observed stage and kind nesting" $ do
        batch <- right (Cohort.mkCanonicalNativeRlCohorts LinuxCPU)
        neural <- case Neural.selectNativeNeuralRowData batch "absent-fixture-row" of
          Left actual -> pure actual
          Right _ -> assertFailure "unknown neural row selected" >> fail "unreachable"
        ars <- case Ars.selectNativeArsRowData batch "absent-fixture-row" of
          Left actual -> pure actual
          Right _ -> assertFailure "unknown ARS row selected" >> fail "unreachable"
        arena <- case Arena.selectNativeAlphaZeroRowData batch "absent-fixture-row" of
          Left actual -> pure actual
          Right _ -> assertFailure "unknown arena row selected" >> fail "unreachable"
        forM_
          [ (NativeNeuralStageFailure NativeOnPolicyFamily neural, 0)
          , (NativeArsStageFailure ars, 1)
          , (NativeArenaStageFailure arena, 2)
          ]
          $ \(origin, category) -> do
            node <- captured origin NoReturnObserved CompleteNativeFailureCapture emptyNativeFailurePayloads
            field node "stage" >>= (@?= VList [VWord 0, VList [VWord category, VWord 0]])
            field node "kind" >>= (@?= VList [VWord 0, VList [VWord category, VWord 0]])
            field node "diagnostic" >>= \case
              VList [VWord 0, VText detail] -> assertBool "actual supplied failure detail retained" (Text.length detail > 0)
              _ -> assertFailure "actual selection diagnostic missing"
    , testCase "an actual complete projection-failure diagnostic survives failure DATA assembly exactly" $ do
        observed <-
          projectReturnEvaluationData Graph.emptyNodePool (error "projection diagnostic preservation fixture")
        detail <- case observed of
          Left (ProjectionSynchronousFailure (ProjectionDiagnosticComplete actual)) -> pure actual
          _ -> assertFailure "fixture did not yield a complete bounded diagnostic" >> fail "unreachable"
        node <-
          captured
            ( NativePhaseCaptureFailure
                NativeDqnFamily
                RawReturnPhase
                CompleteNativeFailureCapture
                (CompleteNativeDiagnostic detail)
            )
            ReturnedButUnmaterializable
            CompleteNativeFailureCapture
            emptyNativeFailurePayloads
        field node "diagnostic" >>= (@?= VList [VWord 0, VText detail])
    , testCase
        "explicit unavailable and unknown-oversize diagnostics remain distinct without generic replacement"
        $ do
          unavailable <-
            captured
              ( NativePhaseCaptureFailure
                  NativeHerFamily
                  InitialEvaluationPhase
                  CompleteNativeFailureCapture
                  UnmaterializableNativeDiagnostic
              )
              NoReturnObserved
              CompleteNativeFailureCapture
              emptyNativeFailurePayloads
          field unavailable "diagnostic" >>= (@?= VList [VWord 2])
          oversize <-
            captured
              ( NativePhaseCaptureFailure
                  NativeHerFamily
                  InitialEvaluationPhase
                  CompleteNativeFailureCapture
                  (OversizeNativeDiagnostic UnknownNativeSize)
              )
              NoReturnObserved
              CompleteNativeFailureCapture
              emptyNativeFailurePayloads
          field oversize "diagnostic" >>= (@?= VList [VWord 1, VList [VWord 2]])
    , testCase "lazy supplied diagnostic alternatives refuse safely while async alternatives propagate" $ do
        -- NativeFailureOrigin's diagnostic field is strict. A wholly bottom
        -- origin cannot retain its stage/header; the exact result is a safe Left.
        let origin =
              NativePhaseCaptureFailure
                NativeArsFamily
                FinalEvaluationPhase
                CompleteNativeFailureCapture
                (error "lazy diagnostic alternative")
        refused <-
          projectSafeFailureData
            Graph.emptyNodePool
            origin
            NoReturnObserved
            CompleteNativeFailureCapture
            emptyNativeFailurePayloads
        case refused of
          Left (ProjectionSynchronousFailure _) -> pure ()
          _ -> assertFailure "lazy diagnostic alternative escaped or fabricated retained header"
        let interrupted =
              NativePhaseCaptureFailure
                NativeArsFamily
                FinalEvaluationPhase
                CompleteNativeFailureCapture
                (throw ThreadKilled)
        result <-
          try
            ( projectSafeFailureData
                Graph.emptyNodePool
                interrupted
                NoReturnObserved
                CompleteNativeFailureCapture
                emptyNativeFailurePayloads
            )
            :: IO (Either AsyncException (Either ProjectionFailure (Digest, Graph.NodePool)))
        case result of
          Left ThreadKilled -> pure ()
          _ -> assertFailure "async diagnostic alternative was swallowed"
    , testCase "exception diagnostic preserves an actual complete Unicode renderer" $ do
        capturedDiagnostic <- captureNativeExceptionDiagnostic (toException ExactRenderer)
        capturedDiagnostic @?= CompleteNativeDiagnostic "actual diagnostic \x1f642"
    , testCase "endless exception renderer refuses at a bounded character prefix" $ do
        observed <- timeout 10000000 (captureNativeExceptionDiagnostic (toException EndlessRenderer))
        case observed of
          Just (OversizeNativeDiagnostic (LowerBoundNativeSize lower)) ->
            toInteger lower @?= nativePhaseLimit DiagnosticTextBytes + 1
          _ -> assertFailure "endless renderer escaped its bound or fabricated a complete prefix"
    , testCase "lazy exception renderer tail yields unavailable without a complete prefix" $ do
        capturedDiagnostic <- captureNativeExceptionDiagnostic (toException LazyRenderer)
        capturedDiagnostic @?= UnmaterializableNativeDiagnostic
    , testCase "asynchronous exception renderer cancellation propagates" $ do
        observed <-
          try (captureNativeExceptionDiagnostic (toException AsyncRenderer))
            :: IO (Either AsyncException NativeDiagnosticData)
        case observed of
          Left ThreadKilled -> pure ()
          _ -> assertFailure "async exception renderer cancellation was swallowed"
    ]
