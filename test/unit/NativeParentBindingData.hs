{-# LANGUAGE OverloadedStrings #-}

-- Ordinary identity fixtures only. Their fake physical allocation is required
-- to fail; no trainer, actual producer, admitted completion or parent is forged.
module NativeParentBindingData (nativeParentBindingDataTests) where

import Data.ByteString qualified as BS
import Data.List (find)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertEqual, assertFailure, testCase)

import JitML.Checkpoint.NativeParentBindingData qualified as Parent
import JitML.Checkpoint.NativePhase.Context qualified as Context
import JitML.Checkpoint.NativePhase.Types (Digest)
import JitML.Checkpoint.NativeQualificationReceiptData qualified as Metadata
import JitML.Checkpoint.NativeReplayObjectData qualified as Replay
import JitML.Checkpoint.NativeRetention qualified as Retain
import JitML.Plan.NativeSingletonPlan qualified as Singleton
import JitML.Plan.Plan qualified as Plan
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.NativeQualificationReference qualified as Reference
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.Product.SourceDigest qualified as Source
import JitML.Product.ValidationRecord (sha256Hex)
import JitML.Substrate (Substrate (AppleSilicon, LinuxCPU))
import JitML.Training.Budget qualified as Training

nativeParentBindingDataTests :: TestTree
nativeParentBindingDataTests =
  testGroup
    "native parent recorded identity and topology DATA"
    [ testCase "matching ordinary identity heads still refuse the fake physical allocation" $ do
        (reference, payload) <- fixture fields
        case check expected reference payload of
          Left reason ->
            assertBool
              "actual acquisition decoder reached, no physical success invented"
              ("NativeAcquisitionDataEnvelope" `Text.isPrefixOf` reason)
          Right _ -> assertFailure "ordinary identity fixture minted complete physical DATA"
    , testCase "parent own source differs from a metadata source role" $
        original (expected {Parent.parentExpectedSource = stamp 90}) sourceError
    , testCase "parent own executable must match its original issued invocation" $
        original (expected {Parent.parentExpectedExecutable = hashId 91}) invocationError
    , testCase "different issued challenge cannot replace the original metadata association" $
        original (expected {Parent.parentExpectedInvocation = invocation (hashId 92)}) associationError
    , testCase "parent addressed manifest must equal exact metadata manifest" $
        original (expected {Parent.parentExpectedManifest = hashId 93}) completionError
    , testCase "parent admitted completion bytes must equal opaque metadata bytes exactly" $
        original
          (expected {Parent.parentExpectedCompletedBytes = "different ordinary completion"})
          completionError
    , testCase "changed reference source cannot borrow matching metadata" $
        editReference (\value -> value {Reference.nativeReferenceSource = stamp 94})
    , testCase "changed reference executable cannot borrow matching metadata" $
        editReference (\value -> value {Reference.nativeReferenceExecutable = hashId 95})
    , testCase "changed reference invocation cannot borrow matching metadata" $
        editReference (\value -> value {Reference.nativeReferenceInvocation = hashId 96})
    , testCase "changed reference allocation count cannot borrow matching metadata" $
        editReference (\value -> value {Reference.nativeReferenceAllocationBytes = 33})
    , testCase "metadata foreign row refuses against current complete canonical cohort" $
        editMetadata (\value -> value {Metadata.nativeReceiptRow = "foreign-row"}) cohortError
    , testCase "metadata foreign lane refuses against current complete canonical cohort" $
        editMetadata (\value -> value {Metadata.nativeReceiptLane = AppleSilicon}) cohortError
    , testCase "metadata lower or arbitrary plan cannot replace whole canonical plan" $
        editMetadata (\value -> value {Metadata.nativeReceiptWholePlan = dig 97}) cohortError
    , testCase "metadata exact canonical cohort transport cannot be substituted" $
        editMetadata
          (\value -> value {Metadata.nativeReceiptCohortTransport = "ordinary foreign cohort"})
          cohortError
    , testCase "direct metadata cannot stand in for an issued scenario association" $
        editMetadata
          (\value -> value {Metadata.nativeReceiptAssociation = Metadata.NativeReceiptDirectData (dig 98)})
          associationError
    , testCase "both present source roles are checked even when one matches" $
        editMetadata (\value -> value {Metadata.nativeReceiptObservedSource = Just (stamp 99)}) sourceError
    , testCase "missing phase payload refuses before any partial physical chain" $ do
        (reference, payload) <- fixture fields
        rejects
          "native metadata and actual full phase payload counts differ"
          (check expected reference (payload {Parent.parentPhaseBytes = ["one"]}))
    , testCase "short and extra replay payloads refuse before metadata or graph expansion" $ do
        (reference, payload) <- fixture fields
        rejects
          countError
          (check expected reference (payload {Parent.parentReplayBytes = replicate 10 BS.empty}))
        rejectAny
          ( check
              expected
              reference
              (payload {Parent.parentReplayBytes = replicate 12 (error "extra replay head must not be forced")})
          )
    , testCase "infinite phase spine refuses before its poisoned heads or batch" $
        rejectAny
          ( Parent.checkNativeParentBindingData
              (error "phase cap must precede batch")
              (error "phase cap must precede row")
              (error "phase cap must precede expected")
              (error "phase cap must precede reference")
              ( Parent.NativeParentPayloadData
                  BS.empty
                  BS.empty
                  (repeat (error "phase heads remain lazy"))
                  []
              )
          )
    , testCase "infinite replay spine refuses before poisoned heads or metadata" $
        rejectAny
          ( Parent.checkNativeParentBindingData
              (error "replay cap must precede batch")
              (error "replay cap must precede row")
              (error "replay cap must precede expected")
              (error "replay cap must precede reference")
              ( Parent.NativeParentPayloadData
                  BS.empty
                  BS.empty
                  [BS.empty]
                  (repeat (error "replay heads remain lazy"))
              )
          )
    ]

batch :: Cohort.NativeRlCohortBatch
batch = rightPure (Cohort.mkCanonicalNativeRlCohorts LinuxCPU)
cohort :: Cohort.NativeRlCohortPlan
cohort =
  fromMaybe
    (error "canonical ARS/cartpole row absent")
    ( find
        ((== "ARS/cartpole") . Matrix.rowId . Cohort.nativeRlCohortPlanRow)
        (Cohort.nativeRlCohortBatchPlans batch)
    )
row :: Text
row = Matrix.rowId (Cohort.nativeRlCohortPlanRow cohort)
singleton :: Singleton.NativeSingletonPlan
singleton = Cohort.nativeRlSeedPlanSingleton (Cohort.nativeRlCohortServingChild cohort)
invocation :: Text -> Training.ProductScenarioInvocation
invocation challenge =
  rightPure
    ( Training.mkProductScenarioInvocation
        "ordinary-parent-data"
        row
        (Singleton.nativeSingletonPlanId singleton)
        LinuxCPU
        (hashId 1)
        (hashId 2)
        challenge
    )
expected :: Parent.NativeParentExpectedData
expected =
  Parent.NativeParentExpectedData
    (stamp 3)
    (hashId 2)
    (invocation (hashId 4))
    (hashId 5)
    "ordinary opaque completion DATA"
publication :: Retain.NativePublicationData
publication = Retain.NativeLocalPublication Retain.NativeDefaultPublicationResolution (hashId 6)
allocation :: Retain.NativeRetainedObjectData
allocation =
  Retain.NativeRetainedObjectData
    ("jitml-checkpoints/native-rl-allocations-v1/" <> hashId 7 <> "/claim.cbor")
    (hashId 8)
    32
    publication
phase :: Int -> Retain.NativeRetainedObjectData
phase index =
  Retain.NativeRetainedObjectData
    ("jitml-checkpoints/native-rl-allocations-v1/" <> hashId 7 <> "/phases/" <> hashId index <> ".cbor")
    (hashId index)
    32
    publication

-- Keep this exact base-only list traversal; no extra dependency for the hint.
{- HLINT ignore fields "Use zipWithFrom" -}
fields :: Metadata.NativeQualificationReceiptFields
fields =
  Metadata.NativeQualificationReceiptFields
    row
    LinuxCPU
    (textDigest (Plan.planIdText (Singleton.nativeSingletonPlanId singleton)))
    (Singleton.nativeSingletonExperiment singleton)
    (textDigest (Plan.planIdText (Cohort.nativeRlCohortPlanId cohort)))
    (Cohort.nativeRlCohortPlanTransport cohort)
    (dig 5)
    "ordinary opaque completion DATA"
    publication
    ( Metadata.NativeReceiptScenarioData
        (Training.renderProductScenarioInvocation (Parent.parentExpectedInvocation expected))
    )
    (Just (stamp 3))
    (Just (stamp 3))
    allocation
    [phase 9, phase 10]
    replays
 where
  replays =
    zipWith
      replay
      [20 ..]
      ( concatMap
          (\index -> [(Replay.InitialModelReplay, index), (Replay.FinalModelReplay, index)])
          [0 .. 4]
          <> [(Replay.StoredFinalModelReplay, 0)]
      )
  replay n (stage, index) =
    let kind =
          if stage == Replay.StoredFinalModelReplay
            then Retain.NativeStoreLoadedReplayArtifact
            else Retain.NativeEvaluationReplayArtifact
        sha = hashId n
        key =
          rightPure
            (Retain.nativeDetachedArtifactKey kind (Singleton.nativeSingletonExperiment singleton) sha)
     in Metadata.NativeReceiptReplayReference
          stage
          index
          (dig (40 + fromIntegral index))
          (Retain.NativeRetainedObjectData key sha 32 publication)

fixture
  :: Metadata.NativeQualificationReceiptFields
  -> IO (Reference.NativeQualificationReference, Parent.NativeParentPayloadData)
fixture value = do
  metadata <- right (Metadata.refineNativeQualificationReceiptData value)
  let bytes = Metadata.nativeQualificationReceiptBytes metadata
      sha = sha256Hex bytes
      experiment = Singleton.nativeSingletonExperiment singleton
      raw =
        Reference.NativeQualificationReferenceData
          row
          LinuxCPU
          (Plan.planIdText (Singleton.nativeSingletonPlanId singleton))
          experiment
          (hashId 5)
          (stamp 3)
          (hashId 2)
          (Training.productScenarioInvocationDigest (Parent.parentExpectedInvocation expected))
          (Plan.planIdText (Cohort.nativeRlCohortPlanId cohort))
          sha
          ("jitml-checkpoints/" <> experiment <> "/artifacts/native-qualification/" <> sha <> ".cbor")
          (fromIntegral (BS.length bytes))
          (Retain.nativePublicationDigest publication)
          Reference.NativeReferenceScenario
          (Retain.nativeRetainedObjectKey allocation)
          (Retain.nativeRetainedObjectSha256 allocation)
          32
  reference <- right (Reference.refineNativeQualificationReference raw)
  pure
    ( reference
    , Parent.NativeParentPayloadData
        bytes
        "ordinary fake allocation"
        ["ordinary phase one", "ordinary phase two"]
        (replicate 11 BS.empty)
    )

check
  :: Parent.NativeParentExpectedData
  -> Reference.NativeQualificationReference
  -> Parent.NativeParentPayloadData
  -> Either Text Parent.NativeParentBindingData
check = Parent.checkNativeParentBindingData batch row
original :: Parent.NativeParentExpectedData -> Text -> Assertion
original value reason = do (reference, payload) <- fixture fields; rejects reason (check value reference payload)
editMetadata
  :: (Metadata.NativeQualificationReceiptFields -> Metadata.NativeQualificationReceiptFields)
  -> Text
  -> Assertion
editMetadata edit reason = do (reference, payload) <- fixture (edit fields); rejects reason (check expected reference payload)
editReference
  :: (Reference.NativeQualificationReferenceData -> Reference.NativeQualificationReferenceData)
  -> Assertion
editReference edit = do
  (reference, payload) <- fixture fields
  changed <-
    right
      ( Reference.refineNativeQualificationReference
          (edit (Reference.nativeQualificationReferenceData reference))
      )
  rejects
    "native reference differs from exact metadata and parent own expected identities"
    (check expected changed payload)
sourceError, invocationError, associationError, completionError, cohortError, countError :: Text
sourceError = "native metadata original source roles differ from parent own observation"
invocationError = "parent own issued invocation differs from current canonical serving identity"
associationError = "native metadata is not bound to the exact parent issued scenario invocation"
completionError = "native metadata differs from parent addressed manifest or exact admitted completion bytes"
cohortError = "native metadata differs from whole current canonical cohort"
countError = "parent requires full phase and exactly eleven replay payloads"
hashId :: Int -> Text
hashId = sha256Hex . BS.singleton . fromIntegral
stamp :: Int -> Source.SourceStamp
stamp = Source.SourceStamp Source.sourceDigestAlgorithm . hashId
dig :: Int -> Digest
dig = textDigest . hashId
textDigest :: Text -> Digest
textDigest = rightPure . Context.digestFromCanonicalText
rightPure :: (Show e) => Either e a -> a
rightPure = either (error . show) id
right :: (Show e) => Either e a -> IO a
right value = case value of
  Right actual -> pure actual
  Left failure -> assertFailure (show failure) >> fail "unreachable"
rejects :: Text -> Either Text a -> Assertion
rejects expectedReason result = case result of
  Left reason -> assertEqual "exact refusal" expectedReason reason
  Right _ -> assertFailure "malformed ordinary parent DATA accepted"
rejectAny :: Either Text a -> Assertion
rejectAny result = case result of
  Left _ -> pure ()
  Right _ -> assertFailure "unbounded ordinary parent input accepted"
