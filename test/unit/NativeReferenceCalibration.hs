{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

-- Separate reference DATA and actual reference-only calculation controls.
-- No trainer, device, parent, ACK, Store or qualifying five-model run occurs.
module NativeReferenceCalibration (nativeReferenceCalibrationTests) where

import Codec.CBOR.Encoding qualified as CBOR
import Control.Exception (AsyncException (ThreadKilled), throw, try)
import Control.Monad (forM_, void)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)
import GHC.Float (castDoubleToWord64, castWord64ToDouble)
import Test.Tasty (TestTree, testGroup, withResource)
import Test.Tasty.HUnit (Assertion, assertBool, assertEqual, assertFailure, testCase)

import JitML.Checkpoint.NativePhase.CBOR qualified as CBORData
import JitML.Checkpoint.NativePhase.Failure qualified as Failure
import JitML.Checkpoint.NativePhase.Graph qualified as Graph
import JitML.Checkpoint.NativePhase.Projection qualified as Project
import JitML.Checkpoint.NativePhase.Schema qualified as Schema
import JitML.Checkpoint.NativePhase.Types
import JitML.Checkpoint.NativeReferences qualified as Wire
import JitML.Checkpoint.NativeReferences.Body qualified as Body
import JitML.Plan.Plan qualified as Plan
import JitML.Product.NativeArenaLearningPolicy qualified as ArenaPolicy
import JitML.Product.NativePreparedAlphaZeroAttempt qualified as AZ
import JitML.Product.NativePreparedArsAttempt qualified as Ars
import JitML.Product.NativePreparedNeuralAttempt qualified as Neural
import JitML.Product.NativeReferenceCalibration qualified as Capture
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.RL.AlphaZero.ArenaTape qualified as Tape
import JitML.RL.AlphaZero.NativeArenaReferences qualified as Arena
import JitML.RL.NativeHerReferences qualified as Her
import JitML.RL.NativeReturnReferences qualified as Return
import JitML.RL.Simulator qualified as Sim
import JitML.Substrate (Substrate (LinuxCPU))

-- Each actual, complete reference calculation is acquired once and shared only
-- as immutable completed observations. No child/training stage is shared.
data Captures
  = Captures
      Capture.CapturedNativeReferences
      Capture.CapturedNativeReferences
      Capture.CapturedNativeReferences
      Capture.CapturedNativeReferences

acquireCaptures :: IO Captures
acquireCaptures = do
  batch <- right (Cohort.mkCanonicalNativeRlCohorts LinuxCPU)
  ordinary <- selection (Neural.selectNativeNeuralRowData batch "DQN/cartpole")
  ars <- selection (Ars.selectNativeArsRowData batch "ARS/mountain-car")
  her <- selection (Neural.selectNativeNeuralRowData batch "HER/goal-reaching")
  arena <- selection (AZ.selectNativeAlphaZeroRowData batch "connect4")
  Captures
    <$> actual (Capture.NativeReferenceNeuralInput ordinary)
    <*> actual (Capture.NativeReferenceArsInput ars)
    <*> actual (Capture.NativeReferenceNeuralInput her)
    <*> actual (Capture.NativeReferenceArenaInput arena)
 where
  actual input = do
    result <- Capture.captureNativeReferenceCalibration input
    case result of
      Right value -> pure value
      Left failure ->
        assertFailure (show (Capture.nativeReferenceFailureDiagnostic failure))
          >> fail "actual reference acquisition failed"

-- Keep the base-only indexed traversal and its complete finite ordering.
{- HLINT ignore nativeReferenceCalibrationTests "Use zipWithFrom" -}
nativeReferenceCalibrationTests :: TestTree
nativeReferenceCalibrationTests =
  testGroup
    "bounded complete native reference calibration DATA"
    [ withResource acquireCaptures (const (pure ())) $ \get ->
        testGroup
          "actual complete reference-only observations"
          [ testCase "RETURN capture retains exact whole cohort and every fixed outcome" $ do
              Captures captured _ _ _ <- get
              roundtrip captured
              let cohort = Capture.nativeCapturedReferenceCohort captured
                  value = Capture.nativeCapturedReferenceData captured
              assertEqual
                "whole cohort"
                (Cohort.nativeRlCohortPlanTransport cohort)
                (Wire.nativeReferenceDataCohortTransport value)
              assertEqual
                "whole cohort ID"
                (Plan.planIdText (Cohort.nativeRlCohortPlanId cohort))
                (Wire.nativeReferenceDataCohortId value)
              case Capture.nativeCapturedReferenceObservations captured of
                Capture.NativeReferenceReturnObservations refs -> do
                  assertEqual "both cartpole controls" 2 (length (Return.nativeReturnObservedReferences refs))
                  forM_ (Return.nativeReturnObservedReferences refs) $ \ref ->
                    assertEqual
                      "all20 fixed cases"
                      [0 .. 19]
                      (fmap Return.nativeReturnEpisodeId (Return.nativeReturnObservedEpisodes ref))
                _ -> assertFailure "RETURN alternative changed"
          , testCase "ARS reference capture uses same row descriptor without an MLP device" $ do
              Captures _ captured _ _ <- get
              roundtrip captured
              assertEqual
                "RETURN DATA family"
                Body.ReturnReferenceFamily
                (Wire.nativeReferenceDataFamily (Capture.nativeCapturedReferenceData captured))
              case Capture.nativeCapturedReferenceObservations captured of
                Capture.NativeReferenceReturnObservations refs ->
                  assertEqual
                    "actual ARS row"
                    "ARS/mountain-car"
                    (Return.nativeReturnSpecRowId (Return.nativeReturnObservedSpec refs))
                _ -> assertFailure "ARS reference alternative changed"
          , testCase "HER capture retains all46656 sequences and933120 outcomes" $ do
              Captures _ _ captured _ <- get
              roundtrip captured
              case Capture.nativeCapturedReferenceObservations captured of
                Capture.NativeReferenceHerObservations refs -> do
                  let observations = Her.nativeHerObservedReferences refs
                  assertEqual "whole enumeration" 46656 (length observations)
                  assertEqual "all outcomes" 933120 (sum (fmap (length . Her.nativeHerObservedOutcomes) observations))
                  assertEqual
                    "retained case IDs"
                    [0 .. 19]
                    (fmap Her.rawNativeHerCaseId (Her.nativeHerScheduleCases (Her.nativeHerObservedSchedule refs)))
                _ -> assertFailure "HER alternative changed"
          , testCase "HER first packed record independently preserves all actual raw outcome bits" $ do
              Captures _ _ captured _ <- get
              case Capture.nativeCapturedReferenceObservations captured of
                Capture.NativeReferenceHerObservations refs -> case Her.nativeHerObservedReferences refs of
                  first : _ -> do
                    let packed = BS.concat (fmap packedOutcome (Her.nativeHerObservedOutcomes first))
                        prefix =
                          CBORData.encodeStrict
                            ( CBOR.encodeListLen 3
                                <> CBOR.encodeListLen 46656
                                <> CBOR.encodeListLen 5
                                <> CBOR.encodeInt64 0
                                <> CBOR.encodeBytes packed
                            )
                    assertEqual "61bytes times20" 1220 (BS.length packed)
                    assertBool
                      "exact first record prefix"
                      (prefix `BS.isPrefixOf` Wire.nativeReferenceDataBody (Capture.nativeCapturedReferenceData captured))
                  [] -> assertFailure "actual enumeration empty"
                _ -> assertFailure "HER alternative changed"
          , testCase "arena capture retains same full actual tape and both nine-game references" $ do
              Captures _ _ _ captured <- get
              roundtrip captured
              case Capture.nativeCapturedReferenceObservations captured of
                Capture.NativeReferenceArenaObservations calibration -> do
                  let refs = Arena.nativeArenaObservedReferences (ArenaPolicy.nativeArenaCalibrationReferences calibration)
                      tape = ArenaPolicy.nativeArenaCalibrationTape calibration
                  assertEqual
                    "both references"
                    [Arena.PlainLegalUniform, Arena.NeutralLegalMcts]
                    (fmap Arena.nativeArenaObservedReference refs)
                  forM_ refs $ \ref -> do
                    assertEqual "actual same tape object" tape (Arena.nativeArenaObservedTape ref)
                    assertEqual
                      "all nine cases"
                      [0 .. 8]
                      (fmap Arena.nativeArenaEpisodeId (Arena.nativeArenaObservedEpisodes ref))
                  assertBool
                    "full retained tape bytes"
                    ( Tape.arenaTapeBytes tape
                        `BS.isInfixOf` Wire.nativeReferenceDataBody (Capture.nativeCapturedReferenceData captured)
                    )
                _ -> assertFailure "arena alternative changed"
          , testCase "actual HER multi-chunk envelope has minimal chunks and a full body checksum" $ do
              Captures _ _ captured _ <- get
              fields <- envelopeFields (Capture.nativeCapturedReferenceBytes captured)
              case fields of
                [_, _, _, _, _, _, VWord size, VList chunks, VBytes checksum] -> do
                  let parts = [part | VBytes part <- chunks]
                      body = BS.concat parts
                  assertBool "multiple chunks" (length parts > 1)
                  assertEqual "declared length" (toInteger size) (toInteger (BS.length body))
                  assertEqual "actual body checksum" (SHA256.hash body) checksum
                  forM_ (take (length parts - 1) parts) $ \part -> assertEqual "full nonfinal chunk" 1048576 (BS.length part)
                _ -> assertFailure "envelope arity changed"
          , testCase "body mutation with original checksum is refused" $ do
              Captures captured _ _ _ <- get
              fields <- envelopeFields (Capture.nativeCapturedReferenceBytes captured)
              case at 7 fields of
                VList (VBytes part : rest) ->
                  refusal
                    ( Wire.decodeNativeReferenceData
                        (encodeFields (replace 7 (VList (VBytes (flipFirst part) : rest)) fields))
                    )
                _ -> assertFailure "actual nonempty body chunk absent"
          , testCase "same-family ordinary raw copies cannot manufacture a successful calibration" $ do
              Captures captured _ _ _ <- get
              case Capture.nativeCapturedReferenceObservations captured of
                Capture.NativeReferenceReturnObservations refs -> do
                  let dataValue = Capture.nativeCapturedReferenceData captured
                      copied = refs {Return.nativeReturnTotalEvaluationTransitions = -1}
                  refusal
                    ( Wire.encodeNativeReturnReferencesData
                        (Wire.nativeReferenceDataCohortId dataValue)
                        (Wire.nativeReferenceDataCohortTransport dataValue)
                        (Wire.nativeReferenceDataSpecRoot dataValue)
                        (Wire.nativeReferenceDataSpecPool dataValue)
                        copied
                    )
                _ -> assertFailure "RETURN alternative changed"
          ]
    , testCase "all38 RETURN reference cardinalities follow actual public domains" $ do
        specs <- right Return.allCanonicalNativeReturnSpecs
        assertEqual "whole RETURN rows" 38 (length specs)
        forM_ specs $ \spec -> do
          assertEqual "frozen20 cases" 20 (Return.nativeReturnSpecEpisodeCount spec)
          case Return.nativeReturnSpecDomain spec of
            Return.NativeUnmaskedDiscrete n -> assertBool "all native actions" (n > 0 && n <= 6)
            Return.NativeMaskedDiscrete n -> assertEqual "all6 factorial preferences" 720 (product [1 .. n])
            Return.NativeContinuous _ _ -> case Sim.lookupContinuousEnvironmentByName (Return.nativeReturnSpecEnvironment spec) of
              Nothing -> assertFailure "canonical continuous environment absent"
              Just (Sim.SomeContinuousEnvironment env) -> do
                controls <- right (Return.continuousReferenceControllers env)
                assertEqual "three complete native controls" 3 (length controls)
    , testCase "minimal independent RETURN DATA body accepts exact fixed arities" $
        void (right (Body.validateBody returnShape (returnBody 0 rationalZero)))
    , testCase "raw signedzero and NaN F64 words are accepted as distinct ordinary DATA" $ do
        let words_ = [0, 0x8000000000000000, 0x7ff8000000001234, 0x7ff8000000001235]
            bodies = fmap (`returnBody` rationalZero) words_
        forM_ bodies $ \body -> void (right (Body.validateBody returnShape body))
        assertEqual "all four byte identities" 4 (length (unique bodies))
    , testCase "RETURN ordinary raw encoder refuses nonfinite derived median explicitly" $ do
        spec <- right (Return.canonicalNativeReturnSpec "DQN" "cartpole")
        let episode i = Return.NativeReturnEpisode i (castWord64ToDouble 0x7ff8000000000001) 1 False
            refs =
              Return.NativeReturnReferenceSet
                spec
                [ Return.NativeReturnReferenceObservation (Return.ConstantDiscrete action) (fmap episode [0 .. 19]) 20
                | action <- [0, 1]
                ]
                40
        refusal (Body.encodeReturnBody returnShape refs)
    , testCase "finite extreme exact median fits each272byte magnitude cap" $ do
        spec <- right (Return.canonicalNativeReturnSpec "DQN" "cartpole")
        let rewards = replicate 10 (castWord64ToDouble 1) <> replicate 10 (castWord64ToDouble 0x7fefffffffffffff)
            episodes = zipWith (\i value -> Return.NativeReturnEpisode i value 1 False) [0 ..] rewards
            refs =
              Return.NativeReturnReferenceSet
                spec
                [ Return.NativeReturnReferenceObservation (Return.ConstantDiscrete action) episodes 20
                | action <- [0, 1]
                ]
                40
        bytes <- right (Body.encodeReturnBody returnShape refs)
        void (right (Body.validateBody returnShape bytes))
    , testCase "zero denominator and unreduced exact rationals are rejected" $ do
        forM_ [rationalBytes False BS.empty BS.empty, rationalBytes False (BS.singleton 2) (BS.singleton 2)] $ \ratio ->
          refusal (Body.validateBody returnShape (returnBody 0 ratio))
    , testCase "negative rational zero and leading-zero magnitudes are rejected" $ do
        forM_
          [ rationalBytes True BS.empty (BS.singleton 1)
          , rationalBytes False (BS.pack [0, 1]) (BS.singleton 1)
          ]
          $ \ratio ->
            refusal (Body.validateBody returnShape (returnBody 0 ratio))
    , testCase "rational magnitude cap is checked before arbitrary integer reconstruction" $
        refusal
          ( Body.validateBody
              returnShape
              (returnBody 0 (rationalBytes False (BS.replicate 273 1) (BS.singleton 1)))
          )
    , testCase "unknown RETURN controller tag and short complete case list are rejected" $ do
        let valid = returnBody 0 rationalZero
            unknownTag = BS.take 4 valid <> CBORData.encodeStrict (CBOR.encodeWord64 99) <> BS.drop 5 valid
            shortCases = BS.take 6 valid <> BS.singleton 0x93 <> BS.drop 7 valid
        refusal (Body.validateBody returnShape unknownTag)
        refusal (Body.validateBody returnShape shortCases)
    , testCase "indefinite and nonshortest RETURN body arrays are rejected" $ do
        refusal (Body.validateBody returnShape (BS.pack [0x9f, 0xff]))
        refusal (Body.validateBody returnShape (BS.pack [0x98, 2] <> BS.drop 1 (returnBody 0 rationalZero)))
    , testCase "trailing RETURN body bytes and unsupported dimensions are rejected" $ do
        refusal (Body.validateBody returnShape (returnBody 0 rationalZero <> BS.singleton 0))
        refusal (Body.validateBody (Body.ReturnDimensions 2 21 500) (returnBody 0 rationalZero))
        refusal (Body.validateBody (Body.ArenaDimensions 226 225 1) BS.empty)
    , testCase "HER count claims over46656 refuse before outcome allocation" $
        refusal
          ( Body.validateBody
              Body.HerDimensions
              (CBORData.encodeStrict (CBOR.encodeListLen 3 <> CBOR.encodeListLen 46657))
          )
    , testCase "HER incomplete outcome pack cannot masquerade as complete family" $
        refusal
          ( Body.validateBody
              Body.HerDimensions
              ( CBORData.encodeStrict
                  ( CBOR.encodeListLen 3
                      <> CBOR.encodeListLen 46656
                      <> CBOR.encodeListLen 5
                      <> CBOR.encodeInt64 0
                      <> CBOR.encodeBytes (BS.replicate 1219 0)
                  )
                  <> BS.replicate 46656 0
              )
          )
    , testCase "arena body refuses a third reference before game allocation" $
        refusal (Body.validateBody (Body.ArenaDimensions 7 42 1) (BS.pack [0x83, 0x83, 0, 0, 0]))
    , testCase "spec input refuses absent transport malformed ID and foreign graph members" $ do
        (root, pool) <- returnHeader
        refusal (Wire.checkNativeReferenceInput "bad" "cohort" root pool)
        refusal (Wire.checkNativeReferenceInput identity BS.empty root pool)
        node <- right (Schema.mkNodeData NTensorLeaf [VWord 0, VBytes BS.empty])
        (_, foreignPool) <- right (Graph.internNode node pool)
        refusal (Wire.checkNativeReferenceInput identity "cohort" root foreignPool)
    , testCase "HER manifest cardinality refuses before expanding shared sequence occurrences" $ do
        (root, pool) <- largeHerHeader
        case Wire.checkNativeReferenceInput identity "ordinary-context" root pool of
          Left (Malformed reason) ->
            assertEqual "pre-expansion count boundary" "HER header case manifest must declare exactly20" reason
          Left reason -> assertFailure ("unexpected structural refusal: " <> show reason)
          Right () -> assertFailure "65536-case generic header admitted as HER20"
    , testCase "ordinary RETURN envelope roundtrip does not construct actual capture" $ do
        value <- ordinaryDocument
        decoded <- right (Wire.decodeNativeReferenceData (Wire.nativeReferenceDataBytes value))
        assertEqual
          "byte exact DATA"
          (Wire.nativeReferenceDataBytes value)
          (Wire.nativeReferenceDataBytes decoded)
        assertEqual
          "supplied context is DATA"
          "ordinary-context"
          (Wire.nativeReferenceDataCohortTransport decoded)
    , testCase "unknown envelope version family and domain are rejected" $ do
        value <- ordinaryDocument
        fields <- envelopeFields (Wire.nativeReferenceDataBytes value)
        forM_ [(0, VText "another-domain"), (1, VWord 2), (2, VWord 3)] $ \(index, field) ->
          refusal (Wire.decodeNativeReferenceData (encodeFields (replace index field fields)))
    , testCase "nonminimal envelope chunks and declared overflow are rejected" $ do
        value <- ordinaryDocument
        fields <- envelopeFields (Wire.nativeReferenceDataBytes value)
        refusal
          (Wire.decodeNativeReferenceData (encodeFields (replace 7 (VList [VBytes "a", VBytes "b"]) fields)))
        refusal (Wire.decodeNativeReferenceData (encodeFields (replace 6 (VWord 134217729) fields)))
    , testCase "envelope missing spec root and truncated trailing bytes are rejected" $ do
        value <- ordinaryDocument
        fields <- envelopeFields (Wire.nativeReferenceDataBytes value)
        let missing =
              CBORData.encodeStrict
                (CBOR.encodeListLen 2 <> CBOR.encodeBytes (BS.replicate 32 0) <> CBOR.encodeListLen 0)
        refusal (Wire.decodeNativeReferenceData (encodeFields (replace 5 (VBytes missing) fields)))
        refusal (Wire.decodeNativeReferenceData (BS.init (Wire.nativeReferenceDataBytes value)))
        refusal (Wire.decodeNativeReferenceData (Wire.nativeReferenceDataBytes value <> BS.singleton 0))
    , testCase "actual input exception retains bounded diagnostic stage absence and Unknown work" $ do
        result <- Capture.captureNativeReferenceCalibration (error "reference input marker")
        case result of
          Right _ -> assertFailure "bottom input minted capture"
          Left failure -> do
            assertEqual
              "before input"
              Capture.NativeReferenceInputStage
              (Capture.nativeReferenceFailureStage failure)
            assertEqual "no invented context" Nothing (Capture.nativeReferenceFailureCohort failure)
            assertEqual
              "unknown work"
              Capture.NativeReferenceWorkUnknown
              (Capture.nativeReferenceFailureWork failure)
            _ <- right (Wire.decodeNativeReferenceFailureData (Capture.nativeReferenceFailureBytes failure))
            case Capture.nativeReferenceFailureDiagnostic failure of
              Failure.CompleteNativeDiagnostic detail -> assertBool "actual exception marker" ("reference input marker" `Text.isInfixOf` detail)
              _ -> assertFailure "bounded exception diagnostic unavailable"
    , testCase "actual asynchronous input exception propagates without capture or failure substitution" $ do
        result <- try (Capture.captureNativeReferenceCalibration (throw ThreadKilled))
        case ( result
                 :: Either
                      AsyncException
                      (Either Capture.NativeReferenceCalibrationFailure Capture.CapturedNativeReferences)
             ) of
          Left ThreadKilled -> pure ()
          _ -> assertFailure "async cancellation was swallowed"
    , testCase "independent failure known answer preserves explicit unavailable and Unknown work" $ do
        let bytes = failureBytes 0 VNull (VList [VWord 2])
        value <- right (Wire.decodeNativeReferenceFailureData bytes)
        assertEqual "canonical failure bytes" bytes (Wire.nativeReferenceFailureDataBytes value)
        assertEqual "six exact ordinary fields" 6 (length (Wire.nativeReferenceFailureDataFields value))
    , testCase "failure complete Unicode diagnostic and bounded context survive exactly" $ do
        let detail = "λ exact observed reason 🙂"
            context = VList [VText identity, VBytes "whole-cohort-data"]
            bytes = failureBytes 2 context (VList [VWord 0, VText detail])
        value <- right (Wire.decodeNativeReferenceFailureData bytes)
        assertEqual
          "full ordered fields"
          [ VText "jitml-native-reference-failure-v1"
          , VWord 1
          , VWord 2
          , context
          , VList [VWord 0, VText detail]
          , VText "unknown-failed-reference-work"
          ]
          (Wire.nativeReferenceFailureDataFields value)
    , testCase "failure exact lowerbound and unknown size knowledge remain distinct" $ do
        let diagnostics =
              [ VList [VWord 1, VList [VWord 0, VWord 1048577]]
              , VList [VWord 1, VList [VWord 1, VWord 1048577]]
              , VList [VWord 1, VList [VWord 2]]
              ]
        forM_ diagnostics $ \diagnostic -> do
          value <- right (Wire.decodeNativeReferenceFailureData (failureBytes 1 VNull diagnostic))
          assertEqual
            "same knowledge alternative"
            diagnostic
            (at 4 (Wire.nativeReferenceFailureDataFields value))
    , testCase "failure unsupported stage diagnostic arity and trailing bytes refuse" $ do
        refusal (Wire.decodeNativeReferenceFailureData (failureBytes 3 VNull (VList [VWord 2])))
        refusal
          (Wire.decodeNativeReferenceFailureData (failureBytes 0 VNull (VList [VWord 2, VText "extra"])))
        refusal
          (Wire.decodeNativeReferenceFailureData (failureBytes 0 VNull (VList [VWord 2]) <> BS.singleton 0))
    , testCase "failure diagnostic UTF8 cap rejects instead of accepting a truncated prefix" $
        refusal
          ( Wire.decodeNativeReferenceFailureData
              (failureBytes 1 VNull (VList [VWord 0, VText (Text.replicate 524289 "λ")]))
          )
    ]

right :: (Show e) => Either e a -> IO a
right result = case result of
  Right value -> pure value
  Left reason -> assertFailure (show reason) >> fail "unexpected refusal"
selection :: Either e a -> IO a
selection result = case result of
  Right value -> pure value
  Left _ -> assertFailure "canonical row selection failed" >> fail "selection"
refusal :: Either e a -> Assertion
refusal result = case result of
  Left _ -> pure ()
  Right _ -> assertFailure "malformed or unsupported DATA was accepted"
roundtrip :: Capture.CapturedNativeReferences -> Assertion
roundtrip captured = do
  let bytes = Capture.nativeCapturedReferenceBytes captured
  value <- right (Wire.decodeNativeReferenceData bytes)
  assertEqual "complete bytes" bytes (Wire.nativeReferenceDataBytes value)
  assertBool "bounded whole retention payload" (BS.length bytes < 256 * 1024 * 1024)
packedOutcome :: Her.NativeHerReferenceOutcome -> ByteString
packedOutcome value =
  BS.singleton (fromIntegral (Her.nativeHerOutcomeCaseId value))
    <> BS.concat
      (fmap (CBORData.word64Bytes . castDoubleToWord64) (VU.toList (Her.nativeHerOutcomeFinalState value)))
    <> BS.singleton (flag (Her.nativeHerOutcomeSuccess value))
    <> CBORData.word64Bytes (castDoubleToWord64 (Her.nativeHerOutcomeNormalizedDistance value))
    <> BS.pack
      [ fromIntegral (Her.nativeHerOutcomeHammingDistance value)
      , fromIntegral (Her.nativeHerOutcomeSteps value)
      , flag (Her.nativeHerOutcomeTerminated value)
      ]
 where
  flag b = if b then 1 else 0
returnShape :: Body.ReferenceDimensions
returnShape = Body.ReturnDimensions 2 20 500
rationalBytes :: Bool -> ByteString -> ByteString -> CBOR.Encoding
rationalBytes sign n d = CBOR.encodeListLen 3 <> CBOR.encodeBool sign <> CBOR.encodeBytes n <> CBOR.encodeBytes d
rationalZero :: CBOR.Encoding
rationalZero = rationalBytes False BS.empty (BS.singleton 1)
returnBody :: Word64 -> CBOR.Encoding -> ByteString
returnBody word ratio =
  CBORData.encodeStrict
    (CBOR.encodeListLen 2 <> CBOR.encodeListLen 2 <> foldMap controller [0, 1] <> CBOR.encodeWord64 0)
 where
  controller action =
    CBOR.encodeListLen 4
      <> CBOR.encodeListLen 2
      <> CBOR.encodeWord64 0
      <> CBOR.encodeInt64 action
      <> CBOR.encodeListLen 20
      <> foldMap episode [0 .. 19]
      <> CBOR.encodeWord64 0
      <> ratio
  episode ordinal =
    CBOR.encodeListLen 4
      <> CBOR.encodeInt64 ordinal
      <> CBOR.encodeBytes (CBORData.word64Bytes word)
      <> CBOR.encodeInt64 0
      <> CBOR.encodeBool False
returnHeader :: IO (Digest, Graph.NodePool)
returnHeader = do
  spec <- right (Return.canonicalNativeReturnSpec "DQN" "cartpole")
  Project.projectNativeReturnSpecData Graph.emptyNodePool spec >>= right
largeHerHeader :: IO (Digest, Graph.NodePool)
largeHerHeader = do
  batch <- right (Cohort.mkCanonicalNativeRlCohorts LinuxCPU)
  row <- selection (Neural.selectNativeNeuralRowData batch "HER/goal-reaching")
  schedule <- case Neural.nativeNeuralRowHerSchedule row of
    Just value -> pure value
    Nothing -> assertFailure "actual HER schedule absent" >> fail "schedule"
  (root, pool) <- Project.projectNativeHerScheduleData Graph.emptyNodePool schedule >>= right
  scheduleNode <- node root pool
  case Schema.nodeFields scheduleNode of
    [VRef spec, VRef sequenceRoot] -> do
      manifest <- node sequenceRoot pool
      pageRoot <- case Schema.nodeFields manifest of
        [_, _, _, VList (VRef value : _)] -> pure value
        _ -> assertFailure "actual case manifest shape" >> fail "manifest"
      page <- node pageRoot pool
      caseRoot <- case Schema.nodeFields page of
        [_, _, VList (VRef value : _)] -> pure value
        _ -> assertFailure "actual case page shape" >> fail "page"
      let kind = Schema.elementKindValue (RefElement NHerGoalCase)
      sharedPage <-
        right (Schema.mkNodeData NReferencePage [kind, VWord 256, VList (replicate 256 (VRef caseRoot))])
      (pageDigest, pool1) <- right (Graph.internNode sharedPage pool)
      sharedManifest <-
        right
          ( Schema.mkNodeData
              NSequenceManifest
              [kind, VWord 65536, VWord 1, VList (replicate 256 (VRef pageDigest))]
          )
      (manifestDigest, pool2) <- right (Graph.internNode sharedManifest pool1)
      replacement <- right (Schema.mkNodeData NHerSchedule [VRef spec, VRef manifestDigest])
      (replacementDigest, pool3) <- right (Graph.internNode replacement pool2)
      closure <- right (Graph.reachableNodePool [replacementDigest] pool3)
      assertBool "small physical shared graph" (length (Graph.nodePoolEntries closure) < 10)
      pure (replacementDigest, closure)
    _ -> assertFailure "actual HER schedule node shape" >> fail "schedule"
 where
  node digest pool = case Graph.lookupNode digest pool of
    Just value -> pure value
    Nothing -> assertFailure "existing public header node absent" >> fail "node"
ordinaryDocument :: IO Wire.NativeReferenceData
ordinaryDocument = do
  spec <- right (Return.canonicalNativeReturnSpec "DQN" "cartpole")
  (root, pool) <- returnHeader
  let episodes = [Return.NativeReturnEpisode ordinal (fromIntegral ordinal) 1 False | ordinal <- [0 .. 19]]
      refs =
        Return.NativeReturnReferenceSet
          spec
          [ Return.NativeReturnReferenceObservation (Return.ConstantDiscrete action) episodes 20
          | action <- [0, 1]
          ]
          40
  right (Wire.encodeNativeReturnReferencesData identity "ordinary-context" root pool refs)
identity :: Text
identity = Text.replicate 64 "a"
encodeFields :: [NodeValue] -> ByteString
encodeFields = CBORData.encodeStrict . CBORData.rawValueEncoding . VList
replace :: Int -> a -> [a] -> [a]
replace index value fields = take index fields <> [value] <> drop (index + 1) fields
at :: Int -> [a] -> a
at index values = case drop index values of value : _ -> value; [] -> error "fixed independent fixture arity absent"
unique :: (Eq a) => [a] -> [a]
unique [] = []
unique (value : rest) = value : unique (filter (/= value) rest)
flipFirst :: ByteString -> ByteString
flipFirst value = case BS.uncons value of
  Nothing -> value
  Just (first, rest) -> BS.cons (if first == 0 then 1 else 0) rest
envelopeFields :: ByteString -> IO [NodeValue]
envelopeFields = right . CBORData.runParser parse
 where
  parse = do
    CBORData.expectList 9
    domain <- CBORData.getText GeneralTextBytes 64
    version <- CBORData.getWord
    family <- CBORData.getWord
    label <- CBORData.getText GeneralTextBytes 64
    context <- CBORData.getBytes WholePayloadBytes 1048576
    header <- CBORData.getBytes WholePayloadBytes 65536
    size <- CBORData.getWord
    count <- CBORData.getListLength AggregateSequenceElements 128
    chunks <- mapM (const (VBytes <$> CBORData.getBytes WholePayloadBytes 1048576)) [1 .. count]
    digest <- CBORData.getBytes GeneralTextBytes 32
    pure
      [ VText domain
      , VWord version
      , VWord family
      , VText label
      , VBytes context
      , VBytes header
      , VWord size
      , VList chunks
      , VBytes digest
      ]
failureBytes :: Word64 -> NodeValue -> NodeValue -> ByteString
failureBytes stage context diagnostic =
  encodeFields
    [ VText "jitml-native-reference-failure-v1"
    , VWord 1
    , VWord stage
    , context
    , diagnostic
    , VText "unknown-failed-reference-work"
    ]
