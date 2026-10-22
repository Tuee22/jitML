{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

module ArsRecordedEvidence (arsRecordedEvidenceTests) where

import Codec.CBOR.Encoding qualified as Cbor
import Codec.CBOR.Write qualified as CborWrite
import Codec.Serialise qualified as Serialise
import Control.Monad (forM_)
import Data.Bifunctor (first)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Char (digitToInt)
import Data.List (find)
import Data.Text (Text)
import Data.Text qualified as Text
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Checkpoint.WeightCodec qualified as WeightCodec
import JitML.Plan.Plan qualified as Plan
import JitML.Product.ArsHostReference qualified as Host
import JitML.Product.Completion qualified as Completion
import JitML.Product.Convergence qualified as Convergence
import JitML.Product.DeviceWitness qualified as Device
import JitML.Product.Evidence qualified as Evidence
import JitML.Product.ExecutionProvenance (ExecutionProvenance (..))
import JitML.Product.Matrix qualified as Matrix
import JitML.Substrate (Substrate (LinuxCPU))
import JitML.Training.Budget qualified as Budget

-- All host records are untrusted offline DTO fixtures. Historical neural bytes
-- preserve recorded wire semantics; they are not a fresh dispatch or current
-- PlanId/publication/admission. Format controls below are structural only.
arsRecordedEvidenceTests :: TestTree
arsRecordedEvidenceTests =
  testGroup
    "closed recorded neural and ARS training evidence"
    [ testCase "pinned historical neural evidence preserves exact bytes and recorded witness" $ do
        evidence <- oldEvidence
        Serialise.serialise evidence @?= LBS.fromStrict (fromHex legacyEvidenceHex)
        witness <- oldWitness
        base <- baseEvidence
        encodeNeuralRaw base (Just (Device.deviceExecutionWitnessToRaw witness))
          @?= fromHex legacyEvidenceHex
        Evidence.evidenceDeviceWitness evidence @?= Right (Just witness)
        Evidence.evidenceExecutionProvenance evidence @?= Right (Just (NeuralDeviceExecution witness))
        Evidence.evidenceInitialWeightHash evidence @?= legacyInitial
        Evidence.evidenceFinalWeightHash evidence @?= legacyFinal
        Evidence.evidenceUpdateCount evidence @?= 192000
        Evidence.evidenceDatasetShaAtRead evidence @?= legacyDataset
    , testCase
        "historical five-field absence decodes honestly and reencodes as the unchanged current absence"
        $ do
          historical <- decodeEvidence (fromHex historicalFiveHex)
          Evidence.evidenceDeviceWitness historical @?= Right Nothing
          Evidence.evidenceExecutionProvenance historical @?= Right Nothing
          Serialise.serialise historical @?= LBS.fromStrict (fromHex currentAbsenceHex)
          base <- baseEvidence
          historical @?= base
    , testCase "new canonical host six-tag1 evidence matches independent embedded bytes" $ do
        host <- hostEvidence
        reference <- hostReference
        base <- baseEvidence
        encodeHostPayload base (Host.encodeArsHostReference reference) @?= fromHex hostEvidenceHex
        Serialise.serialise host @?= LBS.fromStrict (fromHex hostEvidenceHex)
        decoded <- decodeEvidence (fromHex hostEvidenceHex)
        decoded @?= host
        Evidence.evidenceExecutionProvenance decoded @?= Right (Just (ArsHostLinearExecution reference))
        expectLeft "does not carry a neural device witness" (Evidence.evidenceDeviceWitness decoded)
    , testCase "host and neural attachment preserve every ordinary observation" $ do
        base <- baseEvidence
        host <- hostEvidence
        neural <- oldEvidence
        forM_ [host, neural] $ \evidence -> do
          Evidence.evidenceObservationsMatch base evidence @?= True
          Evidence.evidenceInitialWeightHash evidence @?= Evidence.evidenceInitialWeightHash base
          Evidence.evidenceFinalWeightHash evidence @?= Evidence.evidenceFinalWeightHash base
          Evidence.evidenceUpdateCount evidence @?= Evidence.evidenceUpdateCount base
          Evidence.evidenceDatasetShaAtRead evidence @?= Evidence.evidenceDatasetShaAtRead base
    , testCase "same neural or host attachment is idempotent and mixed kinds cannot replace each other" $ do
        neural <- oldEvidence
        witness <- oldWitness
        host <- hostEvidence
        reference <- hostReference
        Evidence.attachDeviceExecutionWitness witness neural @?= Right neural
        Evidence.attachRecordedArsHostReference reference host @?= Right host
        expectLeft "already bound to ARS host" (Evidence.attachDeviceExecutionWitness witness host)
        expectLeft
          "already bound to neural device"
          (Evidence.attachRecordedArsHostReference reference neural)
    , testCase "conflicting same-kind attachment rejects both changed neural and host observations" $ do
        neural <- oldEvidence
        witness <- oldWitness
        otherWitness <-
          expectRight
            ( Device.refineRawDeviceExecutionWitness
                (Device.deviceExecutionWitnessToRaw witness)
                  { Device.rawWitnessBackend = "different-recorded-backend"
                  }
            )
        expectLeft
          "different device execution witness"
          (Evidence.attachDeviceExecutionWitness otherWitness neural)
        host <- hostEvidence
        reference <- hostReference
        otherReference <-
          expectRight
            ( Host.refineArsHostReference
                (Host.arsHostReferenceToRaw reference) {Host.rawArsHostReferenceByteLength = 18}
            )
        expectLeft
          "different ARS host reference"
          (Evidence.attachRecordedArsHostReference otherReference host)
    , testCase "legacy neural malformed payload remains a decodeable but unrefinable witness" $ do
        base <- baseEvidence
        witness <- oldWitness
        let bad = (Device.deviceExecutionWitnessToRaw witness) {Device.rawWitnessKernelHash = "bad-cache-key"}
        decoded <- decodeEvidence (encodeNeuralRaw base (Just bad))
        case Device.refineRawDeviceExecutionWitness bad of
          Left reason -> do
            Evidence.evidenceDeviceWitness decoded @?= Left reason
            Evidence.evidenceExecutionProvenance decoded @?= Left reason
            expectSameLeft reason (completionFrom decoded)
          Right _ -> assertFailure "negative raw neural fixture unexpectedly refined"
        reference <- hostReference
        expectLeft
          "already bound to neural device"
          (Evidence.attachRecordedArsHostReference reference decoded)
    , testCase "host inner reference rejects malformed trailing and noncanonical payloads" $ do
        base <- baseEvidence
        reference <- hostReference
        let inner = Host.encodeArsHostReference reference
        expectDecodeLeft "ARS host reference rejected" (encodeHostPayload base BS.empty)
        expectDecodeLeft "trailing" (encodeHostPayload base (inner <> BS.singleton 0))
        expectDecodeLeft "noncanonical" (encodeHostPayload base (BS.pack [0x98, 11] <> BS.drop 1 inner))
    , testCase "host reference wrapper rejects indefinite nonminimal and oversized byte strings" $ do
        base <- baseEvidence
        reference <- hostReference
        let inner = Host.encodeArsHostReference reference
            prefix = evidencePrefix 1 base
            definite = encodeStrict (Cbor.encodeBytes inner)
            indefinite = prefix <> BS.singleton 0x5f <> definite <> BS.singleton 0xff
            nonminimal = prefix <> BS.pack [0x5a, 0, 0, 1, 0x95] <> inner
        expectDecodeFailure indefinite
        expectDecodeFailure nonminimal
        expectDecodeLeft "exceeds its byte limit" (encodeHostPayload base (BS.replicate 8193 0))
    , testCase "unknown tags wrong field counts and mixed neural-host payloads never fall back" $ do
        base <- baseEvidence
        reference <- hostReference
        let hostBytes = fromHex hostEvidenceHex
        expectDecodeLeft
          "unsupported encoding"
          (BS.take 1 hostBytes <> BS.singleton 2 <> BS.drop 2 hostBytes)
        expectDecodeLeft "unsupported encoding" (BS.cons 0x85 (BS.drop 1 hostBytes))
        expectDecodeFailure
          (evidencePrefix 0 base <> encodeStrict (Cbor.encodeBytes (Host.encodeArsHostReference reference)))
        witness <- oldWitness
        expectDecodeFailure
          ( evidencePrefix 1 base
              <> LBS.toStrict (Serialise.serialise (Just (Device.deviceExecutionWitnessToRaw witness)))
          )
    , testCase
        "legacy permissive outer neural normalization remains distinct from strict host inner codec"
        $ do
          let old = fromHex legacyEvidenceHex
          decoded <- decodeEvidence (BS.pack [0x98, 6] <> BS.drop 1 old)
          Serialise.serialise decoded @?= LBS.fromStrict old
    , testCase "legacy Eq and Ord behaviour remains unchanged within absence and neural variants" $ do
        base <- baseEvidence
        neural <- oldEvidence
        compare base neural @?= LT
        witness <- oldWitness
        changed <-
          expectRight
            ( Device.refineRawDeviceExecutionWitness
                (Device.deviceExecutionWitnessToRaw witness) {Device.rawWitnessBackend = "zzz-recorded-backend"}
            )
        other <- expectRight (Evidence.attachDeviceExecutionWitness changed base)
        compare neural other @?= LT
        Evidence.evidenceObservationsMatch neural other @?= True
    , testCase "public Budget completion revalidation and roundtrip retain the host branch" $ do
        host <- hostEvidence
        completed <- expectRight (completionFrom host)
        reference <- hostReference
        Budget.completedTrainingExecutionProvenance completed
          @?= Right (Just (ArsHostLinearExecution reference))
        expectLeft
          "does not carry a neural device witness"
          (Budget.completedTrainingDeviceWitness completed)
        decoded <- expectRight (Budget.decodeCompletedTraining (Budget.encodeCompletedTraining completed))
        decoded @?= completed
        Budget.completedTrainingExecutionProvenance decoded
          @?= Budget.completedTrainingExecutionProvenance completed
        Budget.rawCompletedTrainingVersion (Budget.completedTrainingToRaw decoded)
          @?= Budget.completedTrainingWireVersion
    , testCase "pinned old complete neural DTO preserves its exact original bytes after Budget refinement" $ do
        let encoded = fromHex legacyCompletedHex
        completed <- expectRight (Budget.decodeCompletedTraining encoded)
        Budget.encodeCompletedTraining completed @?= encoded
        witness <- oldWitness
        Budget.completedTrainingExecutionProvenance completed
          @?= Right (Just (NeuralDeviceExecution witness))
    , testCase "strict ordinary evidence guards and their failure order are unchanged for host data" $ do
        reference <- hostReference
        forM_
          [ ("", legacyFinal, 1, legacyDataset, "initial weight hash")
          , (legacyInitial, "", 1, legacyDataset, "final weight hash")
          , (legacyInitial, legacyInitial, 1, legacyDataset, "weight movement")
          , (legacyInitial, legacyFinal, 0, legacyDataset, "positive update count")
          , (legacyInitial, legacyFinal, 1, "", "dataset SHA observed at read")
          ]
          $ \(initial, final, updates, dataset, reason) -> do
            expectLeft reason (Evidence.mkTrainingEvidence initial final updates dataset)
            let invalid =
                  encodeStrict
                    ( Cbor.encodeListLen 6
                        <> Cbor.encodeWord 1
                        <> Serialise.encode initial
                        <> Serialise.encode final
                        <> Serialise.encode updates
                        <> Serialise.encode dataset
                        <> Cbor.encodeBytes (Host.encodeArsHostReference reference)
                    )
            decoded <- decodeEvidence invalid
            expectLeft reason (completionFrom decoded)
    , testCase "non-ARS structural checkpoint still requires neural evidence and rejects host kind" $ do
        witness <- oldWitness
        (manifest, completed) <- neuralManifest witness
        _ <- expectRightText (Checkpoint.validateCheckpointCompletion manifest)
        base <-
          expectRight
            ( Evidence.mkTrainingEvidence
                (Budget.completedTrainingInitialWeightHash completed)
                (Budget.completedTrainingFinalWeightHash completed)
                (Budget.completedTrainingUpdateCount completed)
                (Budget.completedTrainingDatasetShaAtRead completed)
            )
        absent <-
          expectRight
            ( Budget.refineCompletedTraining
                (Budget.completedTrainingToRaw completed)
                  { Budget.rawCompletedTrainingEvidence = base
                  }
            )
        expectExternalBar
          "requires its measured device substrate"
          (Checkpoint.validateCheckpointCompletion (Checkpoint.attachCompletedTraining absent manifest))
        template <- hostReference
        key <-
          expectRight
            ( Host.arsHostObjectKey
                (Checkpoint.manifestExperiment manifest)
                (Host.arsHostReferenceContentSha256 template)
            )
        -- Match unrelated recorded identity fields so only the non-ARS kind is denied.
        reference <-
          expectRight
            ( Host.refineArsHostReference
                (Host.arsHostReferenceToRaw template)
                  { Host.rawArsHostReferenceObjectKey = key
                  , Host.rawArsHostReferencePlanId = Plan.planIdText (Budget.completedTrainingPlanId completed)
                  }
            )
        host <- expectRight (Evidence.attachRecordedArsHostReference reference base)
        hosted <-
          expectRight
            ( Budget.refineCompletedTraining
                (Budget.completedTrainingToRaw completed)
                  { Budget.rawCompletedTrainingEvidence = host
                  }
            )
        Checkpoint.validateCheckpointCompletion (Checkpoint.attachCompletedTraining hosted manifest)
          @?= Left
            ( Checkpoint.CompletedTrainingExternalBarMismatch
                ["ARS host completion names a non-ARS canonical ProductRow"]
            )
    ]

oldEvidence :: IO Evidence.TrainingEvidence
oldEvidence = decodeEvidence (fromHex legacyEvidenceHex)

baseEvidence :: IO Evidence.TrainingEvidence
baseEvidence = expectRight (Evidence.mkTrainingEvidence legacyInitial legacyFinal 192000 legacyDataset)

oldWitness :: IO Device.DeviceExecutionWitness
oldWitness = do
  evidence <- oldEvidence
  result <- expectRight (Evidence.evidenceDeviceWitness evidence)
  maybe
    (assertFailure "pinned old bytes have no recorded neural witness" >> fail "unreachable")
    pure
    result

hostReference :: IO Host.ArsHostReference
hostReference = expectRight (Host.decodeArsHostReference (fromHex hostReferenceHex))

hostEvidence :: IO Evidence.TrainingEvidence
hostEvidence = do
  base <- baseEvidence
  reference <- hostReference
  expectRight (Evidence.attachRecordedArsHostReference reference base)

completionFrom :: Evidence.TrainingEvidence -> Either Text Budget.CompletedTraining
completionFrom evidence = do
  plan <- Plan.refinePlanIdText (Text.replicate 64 "1")
  budget <- Budget.mkTrainingBudget Budget.RlEnvironmentStepBudget 128 (Just 42)
  observation <- Budget.measureCriterion "offline-data-only" Budget.MetricMaximise 0 1
  Budget.completedTraining
    plan
    budget
    128
    evidence
    [observation]
    (Budget.TensorBoardRunMetadata "offline-record" "offline-record" ["offline-data-only"])

neuralManifest
  :: Device.DeviceExecutionWitness -> IO (Checkpoint.CheckpointManifest, Budget.CompletedTraining)
neuralManifest witness = do
  row <-
    maybe
      (assertFailure "canonical DQN/cartpole row missing" >> fail "unreachable")
      pure
      (find ((== "DQN/cartpole") . Matrix.rowId) Matrix.allProductRows)
  plan <- case Matrix.projectProductRow LinuxCPU row of
    Plan.Success (Matrix.SomeProductProjection _ projection) -> pure (Matrix.productProjectionPlanId projection)
    Plan.Failure errors -> assertFailure (show errors) >> fail "unreachable"
  let experiment = Matrix.productRowExperimentHash row
      budget = Matrix.trainingBudget row
      step = Budget.trainingBudgetTargetUnits budget
      initial = WeightCodec.jmw1ContentSha (WeightCodec.encodeJmw1 [0, 0])
      final = WeightCodec.jmw1ContentSha (WeightCodec.encodeJmw1 [0.25, 0.5])
      metrics =
        [
          ( Convergence.convergenceMetricName (Matrix.convergenceBar row)
          , Convergence.convergenceThreshold (Matrix.convergenceBar row)
          )
        ]
      tensor = Checkpoint.TensorBlob "rl-dqn-weights" [2] (Checkpoint.blobKey experiment final)
  completed <-
    expectRight
      ( Completion.completedTrainingForProductRowWithWeightHashes
          plan
          budget
          row
          legacyDataset
          experiment
          step
          1
          metrics
          initial
          final
          (Just witness)
      )
  let manifest =
        Checkpoint.attachCompletedTraining completed $
          (Checkpoint.emptyManifest "offline-structural-record" experiment [tensor])
            { Checkpoint.manifestModelFamily = Checkpoint.ReinforcementLearningPolicyFamily
            , Checkpoint.manifestArchitecture =
                Checkpoint.defaultArchitectureMetadata Checkpoint.ReinforcementLearningPolicyFamily
            , Checkpoint.manifestStep = step
            , Checkpoint.manifestMetrics = metrics
            }
  pure (manifest, completed)

evidencePrefix :: Word -> Evidence.TrainingEvidence -> BS.ByteString
evidencePrefix tag evidence =
  encodeStrict
    ( Cbor.encodeListLen 6
        <> Cbor.encodeWord tag
        <> Serialise.encode (Evidence.evidenceInitialWeightHash evidence)
        <> Serialise.encode (Evidence.evidenceFinalWeightHash evidence)
        <> Serialise.encode (Evidence.evidenceUpdateCount evidence)
        <> Serialise.encode (Evidence.evidenceDatasetShaAtRead evidence)
    )

encodeNeuralRaw
  :: Evidence.TrainingEvidence -> Maybe Device.RawDeviceExecutionWitness -> BS.ByteString
encodeNeuralRaw evidence raw = evidencePrefix 0 evidence <> LBS.toStrict (Serialise.serialise raw)

encodeHostPayload :: Evidence.TrainingEvidence -> BS.ByteString -> BS.ByteString
encodeHostPayload evidence payload = evidencePrefix 1 evidence <> encodeStrict (Cbor.encodeBytes payload)

encodeStrict :: Cbor.Encoding -> BS.ByteString
encodeStrict = LBS.toStrict . CborWrite.toLazyByteString

decodeResult :: BS.ByteString -> Either Text Evidence.TrainingEvidence
decodeResult = first (Text.pack . show) . Serialise.deserialiseOrFail . LBS.fromStrict

decodeEvidence :: BS.ByteString -> IO Evidence.TrainingEvidence
decodeEvidence = expectRight . decodeResult

expectDecodeLeft :: Text -> BS.ByteString -> Assertion
expectDecodeLeft fragment = expectLeft fragment . decodeResult

expectDecodeFailure :: BS.ByteString -> Assertion
expectDecodeFailure encoded = case decodeResult encoded of
  Left _ -> pure ()
  Right _ -> assertFailure "mixed or noncanonical wrapper unexpectedly decoded"

expectRight :: Either Text a -> IO a
expectRight = either (\reason -> assertFailure (Text.unpack reason) >> fail "unreachable") pure

expectRightText :: (Show e) => Either e a -> IO a
expectRightText = either (\reason -> assertFailure (show reason) >> fail "unreachable") pure

expectLeft :: Text -> Either Text a -> Assertion
expectLeft fragment result = case result of
  Left reason ->
    assertBool
      ("expected " <> Text.unpack fragment <> ", actual " <> Text.unpack reason)
      (fragment `Text.isInfixOf` reason)
  Right _ -> assertFailure ("unexpected acceptance; expected " <> Text.unpack fragment)

expectSameLeft :: Text -> Either Text a -> Assertion
expectSameLeft expected result = case result of
  Left actual -> actual @?= expected
  Right _ -> assertFailure "malformed recorded witness unexpectedly completed"

expectExternalBar :: Text -> Either Checkpoint.CheckpointCompletionValidationError a -> Assertion
expectExternalBar fragment result = case result of
  Left (Checkpoint.CompletedTrainingExternalBarMismatch reasons) ->
    assertBool
      ("expected exact external-bar identity diagnostic " <> Text.unpack fragment <> ": " <> show reasons)
      (any (fragment `Text.isInfixOf`) reasons)
  Left other -> assertFailure ("wrong structural rejection boundary: " <> show other)
  Right _ -> assertFailure "unsupported device absence/kind bypassed canonical structural completion"

fromHex :: Text -> BS.ByteString
fromHex = BS.pack . go . Text.unpack
 where
  go (a : b : rest) = fromIntegral (digitToInt a * 16 + digitToInt b) : go rest
  go _ = []

-- BEGIN PINNED CODEC FIXTURE LITERALS

legacyInitial :: Text
legacyInitial =
  Text.concat
    [ "341ba70a8fd41dd3a0a180a56214ac99352e3ee3c15d8ddf43260078609ebe1d"
    ]

legacyFinal :: Text
legacyFinal =
  Text.concat
    [ "e8de600f6d0fc2851e0b22175ad5333700e66de1943121e3aa1af605b3aebbea"
    ]

legacyDataset :: Text
legacyDataset =
  Text.concat
    [ "cd0477a3e4141b30ea9d9fb322e956a06625c6c0265693df8936f6cc0db563cd"
    ]

legacyEvidenceHex :: Text
legacyEvidenceHex =
  Text.concat
    [ "860078403334316261373061386664343164643361306131383061353632313461633939333532653365653363313564"
    , "386464663433323630303738363039656265316478406538646536303066366430666332383531653062323231373561"
    , "64353333333730306536366465313934333132316533616131616636303562336165626265611a0002ee007840636430"
    , "343737613365343134316233306561396439666233323265393536613036363235633663303236353639336466383933"
    , "36663663633064623536336364818700696c696e75782d637075666f6e65646e6e784062393435313438303533613130"
    , "323030653733616163613133313231646565623436623138346431373532346365373836396633313430626264653831"
    , "31323078582e6275696c642f6a69742f6c696e75782d6370752f62393435313438303533613130323030653733616163"
    , "6131333132316465656234366231383464313735323463653738363966333134306262646538313132302e736f784065"
    , "663765626531646333663032636262363434326635376433663665363635353863343534353734323639613836353137"
    , "34623562376135336534323539393078206d6c702d666f72776172642d6261636b776172642d74616e682d6c696e6561"
    , "72"
    ]

historicalFiveHex :: Text
historicalFiveHex =
  Text.concat
    [ "850078403334316261373061386664343164643361306131383061353632313461633939333532653365653363313564"
    , "386464663433323630303738363039656265316478406538646536303066366430666332383531653062323231373561"
    , "64353333333730306536366465313934333132316533616131616636303562336165626265611a0002ee007840636430"
    , "343737613365343134316233306561396439666233323265393536613036363235633663303236353639336466383933"
    , "36663663633064623536336364"
    ]

currentAbsenceHex :: Text
currentAbsenceHex =
  Text.concat
    [ "860078403334316261373061386664343164643361306131383061353632313461633939333532653365653363313564"
    , "386464663433323630303738363039656265316478406538646536303066366430666332383531653062323231373561"
    , "64353333333730306536366465313934333132316533616131616636303562336165626265611a0002ee007840636430"
    , "343737613365343134316233306561396439666233323265393536613036363235633663303236353639336466383933"
    , "3666366363306462353633636480"
    ]

hostReferenceHex :: Text
hostReferenceHex =
  Text.concat
    [ "8b78186a69746d6c2d6172732d686f73742d7265666572656e63650178806a69746d6c2d636865636b706f696e74732f"
    , "6f66666c696e652d6172732f6172746966616374732f6172732d686f73742d657865637574696f6e2f32323232323232"
    , "323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232"
    , "3232323232323232322e63626f7258202222222222222222222222222222222222222222222222222222222222222222"
    , "115820333333333333333333333333333333333333333333333333333333333333333378403131313131313131313131"
    , "313131313131313131313131313131313131313131313131313131313131313131313131313131313131313131313131"
    , "3131313131696c696e75782d637075582044444444444444444444444444444444444444444444444444444444444444"
    , "445820555555555555555555555555555555555555555555555555555555555555555558206666666666666666666666"
    , "666666666666666666666666666666666666666666"
    ]

hostEvidenceHex :: Text
hostEvidenceHex =
  Text.concat
    [ "860178403334316261373061386664343164643361306131383061353632313461633939333532653365653363313564"
    , "386464663433323630303738363039656265316478406538646536303066366430666332383531653062323231373561"
    , "64353333333730306536366465313934333132316533616131616636303562336165626265611a0002ee007840636430"
    , "343737613365343134316233306561396439666233323265393536613036363235633663303236353639336466383933"
    , "366636636330646235363363645901958b78186a69746d6c2d6172732d686f73742d7265666572656e63650178806a69"
    , "746d6c2d636865636b706f696e74732f6f66666c696e652d6172732f6172746966616374732f6172732d686f73742d65"
    , "7865637574696f6e2f323232323232323232323232323232323232323232323232323232323232323232323232323232"
    , "323232323232323232323232323232323232323232323232322e63626f72582022222222222222222222222222222222"
    , "222222222222222222222222222222221158203333333333333333333333333333333333333333333333333333333333"
    , "333333784031313131313131313131313131313131313131313131313131313131313131313131313131313131313131"
    , "313131313131313131313131313131313131313131696c696e75782d6370755820444444444444444444444444444444"
    , "444444444444444444444444444444444458205555555555555555555555555555555555555555555555555555555555"
    , "55555558206666666666666666666666666666666666666666666666666666666666666666"
    ]

legacyCompletedHex :: Text
legacyCompletedHex =
  Text.concat
    [ "8b0002784035366561363965316364643038386435666235336332646136646431343464333263383363306637643462"
    , "353338336336643961663263616466386363313933840081011a0012c00081182a81011a0012c00071656e7669726f6e"
    , "6d656e742d73746570738600784033343162613730613866643431646433613061313830613536323134616339393335"
    , "326533656533633135643864646634333236303037383630396562653164784065386465363030663664306663323835"
    , "316530623232313735616435333333373030653636646531393433313231653361613161663630356233616562626561"
    , "1a0002ee0078406364303437376133653431343162333065613964396662333232653935366130363632356336633032"
    , "3635363933646638393336663663633064623536336364818700696c696e75782d637075666f6e65646e6e7840623934"
    , "353134383035336131303230306537336161636131333132316465656234366231383464313735323463653738363966"
    , "3331343062626465383131323078582e6275696c642f6a69742f6c696e75782d6370752f623934353134383035336131"
    , "303230306537336161636131333132316465656234366231383464313735323463653738363966333134306262646538"
    , "313132302e736f7840656637656265316463336630326362623634343266353764336636653636353538633435343537"
    , "3432363961383635313734623562376135336534323539393078206d6c702d666f72776172642d6261636b776172642d"
    , "74616e682d6c696e6561729f8500736d656469616e5f66696e616c5f7265776172648100fb407c200000000000fb407f"
    , "400000000000ff8400781870726f647563742d726f772d50504f2e63617274706f6c65782a6a69746d6c2d74656e736f"
    , "72626f6172642f70726f647563742d726f772d50504f2e63617274706f6c659f736d656469616e5f66696e616c5f7265"
    , "77617264ff81880078276a69746d6c2d70726f647563742d7363656e6172696f2d393465663232383434393636313934"
    , "336c50504f2f63617274706f6c6578403536656136396531636464303838643566623533633264613664643134346433"
    , "3263383363306637643462353338336336643961663263616466386363313933696c696e75782d637075784036373339"
    , "666436613931396166633737326235306135356434306430616562336630656365386632313832313937613562376436"
    , "316365376230313865386130784031653531303235613463633164303135363439363439623464343632626136633231"
    , "393265386536333839656534323562646364326535346461613532323232784037323139636261653663363331366635"
    , "656361623830376633373236303333653635326130656263396436393563633936396561653738366466313733366365"
    ]
