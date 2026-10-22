{-# LANGUAGE OverloadedStrings #-}

-- Ordinary codec/binding DATA only. The pooled source is the public pure ARS
-- fixed-case evaluator and projector, never five training runs or a Root cap.
-- Example RawDevice fields below are forgeable syntax, not device observations.
module NativeParentEvaluationSummaryData (nativeParentEvaluationSummaryDataTests) where

import Codec.CBOR.Encoding qualified as CBOR
import Control.Exception (evaluate)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)
import System.Timeout (timeout)
import Test.Tasty (TestTree, testGroup, withResource)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Checkpoint.NativeParentEvaluationSummaryData qualified as Summary
import JitML.Checkpoint.NativePhase.CBOR qualified as Wire
import JitML.Checkpoint.NativePhase.Graph qualified as Graph
import JitML.Checkpoint.NativePhase.Projection qualified as Project
import JitML.Checkpoint.NativePhase.Types (CodecError, Digest, digestBytes, hashBytes)
import JitML.Checkpoint.NativeReplayObjectData qualified as Replay
import JitML.Product.DeviceWitness qualified as Witness
import JitML.RL.Algorithms.ArsTrainer qualified as Ars
import JitML.RL.NativeReturnEvaluation qualified as Evaluation
import JitML.RL.NativeReturnReferences qualified as Reference

data Fixture = Fixture ![Replay.NativeReplayObjectData] !Replay.NativeReplayObjectData

-- Keep this exact base-only list traversal; no extra dependency for the hint.
{- HLINT ignore nativeParentEvaluationSummaryDataTests "Use drop1" -}
nativeParentEvaluationSummaryDataTests :: TestTree
nativeParentEvaluationSummaryDataTests = withResource acquire (const (pure ())) $ \get ->
  testGroup
    "native parent evaluation summary DATA"
    [ testCase "actual public fixed evaluator replay DATA binds all eleven host summary positions" $ do
        Fixture replays _ <- get
        let summary = summaryFor replays Nothing Nothing
        refined <- right (Summary.refineNativeParentEvaluationSummaryData summary)
        bytes <- right (Summary.encodeNativeParentEvaluationSummaryData refined)
        Summary.decodeNativeParentEvaluationSummaryData bytes @?= Right summary
        Summary.checkNativeParentEvaluationSummaryData replays (replicate 11 Nothing) Nothing summary
          @?= Right ()
        map Summary.parentSummaryOrdinal (Summary.parentSummaryMatches summary) @?= [0 .. 10]
        map
          (\value -> (Summary.parentSummaryStage value, Summary.parentSummaryIndex value))
          (Summary.parentSummaryMatches summary)
          @?= positions
    , testCase "independent ordinary wire spelling matches all retained roots and explicit host absence" $ do
        Fixture replays _ <- get
        let summary = summaryFor replays Nothing Nothing
        bytes <- right (Summary.encodeNativeParentEvaluationSummaryData summary)
        bytes @?= canonicalWire summary
        assertBool
          "summary contains metadata only under64KiB"
          (toInteger (BS.length bytes) < Summary.maximumNativeParentEvaluationSummaryBytes)
    , testCase "ordinary six-field witness DATA roundtrips without claiming a real observed device" $ do
        Fixture replays _ <- get
        let summary = summaryFor replays (Just exampleDevice) Nothing
        bytes <- right (Summary.encodeNativeParentEvaluationSummaryData summary)
        Summary.decodeNativeParentEvaluationSummaryData bytes @?= Right summary
        Summary.checkNativeParentEvaluationSummaryData
          replays
          (replicate 11 (Just exampleDevice))
          Nothing
          summary
          @?= Right ()
    , testCase "maximum accepted witness fields stay inside the proved metadata envelope" $ do
        Fixture replays _ <- get
        let raw =
              exampleDevice
                { Witness.rawWitnessBackend = Text.replicate 256 "b"
                , Witness.rawWitnessArtifactPath = Text.replicate 4096 "p"
                , Witness.rawWitnessExecutedIdentity = Text.replicate 256 "e"
                }
            summary = summaryFor replays (Just raw) (Just arenaRoot)
        bytes <- right (Summary.encodeNativeParentEvaluationSummaryData summary)
        assertBool "independent conservative55128B bound" (BS.length bytes <= 55128)
        assertBool
          "configured64KiB cap"
          (toInteger (BS.length bytes) <= Summary.maximumNativeParentEvaluationSummaryBytes)
        Summary.decodeNativeParentEvaluationSummaryData bytes @?= Right summary
    , testCase "artifact path bounds count UTF8 bytes and preserve the exact byte boundary" $ do
        Fixture replays _ <- get
        let raw = exampleDevice {Witness.rawWitnessArtifactPath = "/" <> Text.replicate 2047 "λ" <> "a"}
            summary = summaryFor replays (Just raw) Nothing
        bytes <- right (Summary.encodeNativeParentEvaluationSummaryData summary)
        Summary.decodeNativeParentEvaluationSummaryData bytes @?= Right summary
        reject
          ( Summary.encodeNativeParentEvaluationSummaryData
              ( summaryFor
                  replays
                  (Just (raw {Witness.rawWitnessArtifactPath = Witness.rawWitnessArtifactPath raw <> "λ"}))
                  Nothing
              )
          )
    , testCase "both missing and extra summary positions refuse before any incomplete encoding" $ do
        Fixture replays _ <- get
        let summary = summaryFor replays Nothing Nothing
            values = Summary.parentSummaryMatches summary
        mapM_
          ( \items -> do
              let changed = summary {Summary.parentSummaryMatches = items}
              reject (Summary.refineNativeParentEvaluationSummaryData changed)
              reject (Summary.encodeNativeParentEvaluationSummaryData changed)
          )
          [take 10 values, values <> take 1 values]
    , testCase "checked public encoder bounds infinite spines before serializing values" $ do
        let summary =
              Summary.NativeParentEvaluationSummaryData
                Nothing
                (repeat (error "bounded spine must refuse before members"))
        outcome <- timeout 1000000 (evaluate (Summary.encodeNativeParentEvaluationSummaryData summary))
        case outcome of
          Just (Left _) -> pure ()
          _ -> assertFailure "public encoder failed to bound an infinite summary spine"
    , testCase "cap plus one poisoned member and tail are not forced by public encoder or refiner" $ do
        Fixture replays _ <- get
        let summary = summaryFor replays Nothing Nothing
            changed =
              summary
                { Summary.parentSummaryMatches =
                    Summary.parentSummaryMatches summary
                      <> (error "twelfth member must stay unforced" : error "tail beyond cap plus one must stay unforced")
                }
        reject (Summary.refineNativeParentEvaluationSummaryData changed)
        reject (Summary.encodeNativeParentEvaluationSummaryData changed)
    , testCase "every original ordinal is exact and cannot be duplicated or relabelled" $ do
        Fixture replays _ <- get
        let summary = summaryFor replays Nothing Nothing
        mapM_
          ( \index ->
              reject
                ( Summary.encodeNativeParentEvaluationSummaryData
                    (editAt index (\value -> value {Summary.parentSummaryOrdinal = 99}) summary)
                )
          )
          [0 .. 10]
    , testCase "every original stage is exact including the sole stored-final slot" $ do
        Fixture replays _ <- get
        let summary = summaryFor replays Nothing Nothing
        mapM_
          ( \index ->
              reject
                ( Summary.refineNativeParentEvaluationSummaryData
                    ( editAt
                        index
                        (\value -> value {Summary.parentSummaryStage = otherStage (Summary.parentSummaryStage value)})
                        summary
                    )
                )
          )
          [0 .. 10]
    , testCase "every original child index is exact and stored-final cannot name child one" $ do
        Fixture replays _ <- get
        let summary = summaryFor replays Nothing Nothing
        mapM_
          ( \index ->
              reject
                ( Summary.encodeNativeParentEvaluationSummaryData
                    ( editAt
                        index
                        (\value -> value {Summary.parentSummaryIndex = Summary.parentSummaryIndex value + 1})
                        summary
                    )
                )
          )
          [0 .. 10]
    , testCase "different expected or actual digest refuses even when all other positions match" $ do
        Fixture replays _ <- get
        let summary = summaryFor replays Nothing Nothing
        reject
          ( Summary.refineNativeParentEvaluationSummaryData
              (editAt 0 (\value -> value {Summary.parentSummaryExpectedRoot = otherRoot}) summary)
          )
        reject
          ( Summary.encodeNativeParentEvaluationSummaryData
              (editAt 0 (\value -> value {Summary.parentSummaryActualRoot = otherRoot}) summary)
          )
    , testCase "all witness fields have explicit byte caps before the private encoder" $ do
        Fixture replays _ <- get
        let variants =
              [ exampleDevice {Witness.rawWitnessSubstrate = Text.replicate 33 "x"}
              , exampleDevice {Witness.rawWitnessBackend = Text.replicate 257 "b"}
              , exampleDevice {Witness.rawWitnessKernelHash = Text.replicate 65 "a"}
              , exampleDevice {Witness.rawWitnessArtifactPath = Text.replicate 4097 "p"}
              , exampleDevice {Witness.rawWitnessArtifactSha256 = Text.replicate 65 "b"}
              , exampleDevice {Witness.rawWitnessExecutedIdentity = Text.replicate 257 "e"}
              ]
        mapM_
          ( \raw -> reject (Summary.encodeNativeParentEvaluationSummaryData (summaryFor replays (Just raw) Nothing))
          )
          variants
    , testCase "malformed lane blank witness fields and invalid digests refuse ordinary refinement" $ do
        Fixture replays _ <- get
        let variants =
              [ exampleDevice {Witness.rawWitnessSubstrate = "not-a-lane"}
              , exampleDevice {Witness.rawWitnessBackend = " "}
              , exampleDevice {Witness.rawWitnessKernelHash = "not-hex"}
              , exampleDevice {Witness.rawWitnessArtifactPath = " "}
              , exampleDevice {Witness.rawWitnessArtifactSha256 = Text.replicate 63 "b"}
              , exampleDevice {Witness.rawWitnessExecutedIdentity = " "}
              ]
        mapM_
          ( \raw -> reject (Summary.refineNativeParentEvaluationSummaryData (summaryFor replays (Just raw) Nothing))
          )
          variants
    , testCase "all truncated prefixes of a complete small host summary refuse" $ do
        Fixture replays _ <- get
        bytes <-
          right (Summary.encodeNativeParentEvaluationSummaryData (summaryFor replays Nothing Nothing))
        mapM_
          (\size -> reject (Summary.decodeNativeParentEvaluationSummaryData (BS.take size bytes)))
          [0 .. BS.length bytes - 1]
    , testCase
        "whole payload cap plus one refuses before parsing and exact cap trailing bytes also refuse"
        $ do
          reject (Summary.decodeNativeParentEvaluationSummaryData (BS.replicate 65537 0))
          Fixture replays _ <- get
          bytes <-
            right (Summary.encodeNativeParentEvaluationSummaryData (summaryFor replays Nothing Nothing))
          reject
            (Summary.decodeNativeParentEvaluationSummaryData (bytes <> BS.replicate (65536 - BS.length bytes) 0))
    , testCase "unknown domain or version refuses closed transport" $ do
        Fixture replays _ <- get
        let summary = summaryFor replays Nothing Nothing
        reject
          ( Summary.decodeNativeParentEvaluationSummaryData
              ( wireWith
                  "another-domain"
                  (word 1)
                  nullValue
                  (listHeader 11)
                  (map matchWire (Summary.parentSummaryMatches summary))
              )
          )
        mapM_
          ( \version ->
              reject
                ( Summary.decodeNativeParentEvaluationSummaryData
                    ( wireWith
                        domain
                        (word version)
                        nullValue
                        (listHeader 11)
                        (map matchWire (Summary.parentSummaryMatches summary))
                    )
                )
          )
          [0, 2]
    , testCase "top-level maps wrong arities and indefinite arrays refuse" $ do
        Fixture replays _ <- get
        let bytes = canonicalWire (summaryFor replays Nothing Nothing)
        mapM_
          (\header -> reject (Summary.decodeNativeParentEvaluationSummaryData (header <> BS.drop 1 bytes)))
          [listHeader 3, listHeader 5, Wire.encodeStrict (CBOR.encodeMapLen 4), BS.singleton 0x9f]
    , testCase "declared missing or huge match count refuses before reading nonexistent items" $ do
        mapM_
          ( \count ->
              reject
                ( Summary.decodeNativeParentEvaluationSummaryData
                    (wireWith domain (word 1) nullValue (listHeader count) [])
                )
          )
          [0, 10, 12, maxBound]
    , testCase "unknown stage tags and wrong per-item tuple arities refuse" $ do
        Fixture replays _ <- get
        let summary = summaryFor replays Nothing Nothing
            first = headMatch summary
            items = map matchWire (Summary.parentSummaryMatches summary)
            unknown stageCode =
              itemWith
                first
                (word 0)
                (word stageCode)
                (word 0)
                (digest (Summary.parentSummaryExpectedRoot first))
                (digest (Summary.parentSummaryActualRoot first))
                nullValue
        mapM_
          ( \stageCode ->
              reject
                ( Summary.decodeNativeParentEvaluationSummaryData
                    (wireWith domain (word 1) nullValue (listHeader 11) (unknown stageCode : drop 1 items))
                )
          )
          [3, maxBound]
        firstItem <- requiredAt 0 items
        mapM_
          ( \arity ->
              reject
                ( Summary.decodeNativeParentEvaluationSummaryData
                    ( wireWith
                        domain
                        (word 1)
                        nullValue
                        (listHeader 11)
                        ((listHeader arity <> BS.drop 1 firstItem) : drop 1 items)
                    )
                )
          )
          [5, 7]
    , testCase "nonminimal version and list heads refuse canonical CBOR" $ do
        Fixture replays _ <- get
        let items = map matchWire (Summary.parentSummaryMatches (summaryFor replays Nothing Nothing))
        reject
          ( Summary.decodeNativeParentEvaluationSummaryData
              (wireWith domain (BS.pack [0x18, 1]) nullValue (listHeader 11) items)
          )
        reject
          ( Summary.decodeNativeParentEvaluationSummaryData
              (wireWith domain (word 1) nullValue (BS.pack [0x98, 11]) items)
          )
    , testCase "floating unsigned scalar substitution and tagged envelopes refuse" $ do
        Fixture replays _ <- get
        let summary = summaryFor replays Nothing Nothing
            first = headMatch summary
            bad =
              itemWith
                first
                (Wire.encodeStrict (CBOR.encodeDouble 1))
                (word 0)
                (word 0)
                (digest (Summary.parentSummaryExpectedRoot first))
                (digest (Summary.parentSummaryActualRoot first))
                nullValue
            bytes = canonicalWire summary
        reject
          ( Summary.decodeNativeParentEvaluationSummaryData
              ( wireWith
                  domain
                  (word 1)
                  nullValue
                  (listHeader 11)
                  (bad : drop 1 (map matchWire (Summary.parentSummaryMatches summary)))
              )
          )
        reject (Summary.decodeNativeParentEvaluationSummaryData (BS.singleton 0xc0 <> bytes))
    , testCase "reference and both per-item digest extents are exactly32 bytes" $ do
        Fixture replays _ <- get
        let summary = summaryFor replays Nothing Nothing
            first = headMatch summary
            good = digest (Summary.parentSummaryExpectedRoot first)
            items = map matchWire (Summary.parentSummaryMatches summary)
        mapM_
          ( \count -> do
              let wrong = Wire.encodeStrict (CBOR.encodeBytes (BS.replicate count 0))
              reject
                ( Summary.decodeNativeParentEvaluationSummaryData
                    (wireWith domain (word 1) wrong (listHeader 11) items)
                )
              reject
                ( Summary.decodeNativeParentEvaluationSummaryData
                    ( wireWith
                        domain
                        (word 1)
                        nullValue
                        (listHeader 11)
                        (itemWith first (word 0) (word 0) (word 0) wrong good nullValue : drop 1 items)
                    )
                )
              reject
                ( Summary.decodeNativeParentEvaluationSummaryData
                    ( wireWith
                        domain
                        (word 1)
                        nullValue
                        (listHeader 11)
                        (itemWith first (word 0) (word 0) (word 0) good wrong nullValue : drop 1 items)
                    )
                )
          )
          [31, 33]
    , testCase
        "optional witness has exact arity and text fields refuse invalid UTF8 before reconstruction"
        $ do
          Fixture replays _ <- get
          let summary = summaryFor replays (Just exampleDevice) Nothing
              first = headMatch summary
              fields = map text (rawFields exampleDevice)
              items = map matchWire (Summary.parentSummaryMatches summary)
              replaceDevice bytes =
                wireWith
                  domain
                  (word 1)
                  nullValue
                  (listHeader 11)
                  ( itemWith
                      first
                      (word 0)
                      (word 0)
                      (word 0)
                      (digest (Summary.parentSummaryExpectedRoot first))
                      (digest (Summary.parentSummaryActualRoot first))
                      bytes
                      : drop 1 items
                  )
          mapM_
            ( \arity ->
                reject
                  ( Summary.decodeNativeParentEvaluationSummaryData
                      (replaceDevice (listHeader arity <> BS.concat fields))
                  )
            )
            [5, 7]
          reject
            ( Summary.decodeNativeParentEvaluationSummaryData
                ( replaceDevice
                    (listHeader 6 <> BS.concat (take 3 fields) <> BS.pack [0x61, 0xff] <> BS.concat (drop 4 fields))
                )
            )
    , testCase "trailing data and optional false instead of null or digest refuse" $ do
        Fixture replays _ <- get
        let summary = summaryFor replays Nothing Nothing
        reject (Summary.decodeNativeParentEvaluationSummaryData (canonicalWire summary <> BS.singleton 0))
        reject
          ( Summary.decodeNativeParentEvaluationSummaryData
              ( wireWith
                  domain
                  (word 1)
                  (Wire.encodeStrict (CBOR.encodeBool False))
                  (listHeader 11)
                  (map matchWire (Summary.parentSummaryMatches summary))
              )
          )
    , testCase "comparison requires all eleven replay and expected device records" $ do
        Fixture replays _ <- get
        let summary = summaryFor replays Nothing Nothing
        mapM_
          ( \values ->
              reject
                (Summary.checkNativeParentEvaluationSummaryData values (replicate 11 Nothing) Nothing summary)
          )
          [take 10 replays, replays <> take 1 replays]
        mapM_
          (\values -> reject (Summary.checkNativeParentEvaluationSummaryData replays values Nothing summary))
          [replicate 10 Nothing, replicate 12 Nothing]
    , testCase "comparison bounds replay and device input spines without forcing excess DATA" $ do
        Fixture replays _ <- get
        let summary = summaryFor replays Nothing Nothing
        reject
          ( Summary.checkNativeParentEvaluationSummaryData
              (repeat (error "oversize replays never demand values"))
              (error "bad replay count precedes devices")
              Nothing
              summary
          )
        reject
          ( Summary.checkNativeParentEvaluationSummaryData
              replays
              (repeat (error "oversize devices never demand values"))
              Nothing
              summary
          )
    , testCase "independently valid different public evaluator root cannot replace original source replay" $ do
        Fixture replays alternative <- get
        let summary = summaryFor replays Nothing Nothing
        firstReplay <- requiredAt 0 replays
        assertBool
          "actual alternate policy projection differs"
          (Replay.nativeReplayObjectRoot firstReplay /= Replay.nativeReplayObjectRoot alternative)
        reject
          ( Summary.checkNativeParentEvaluationSummaryData
              (alternative : drop 1 replays)
              (replicate 11 Nothing)
              Nothing
              summary
          )
    , testCase "valid replay objects with different stage or child index cannot be reordered into a match" $ do
        Fixture replays _ <- get
        let summary = summaryFor replays Nothing Nothing
        reject
          ( Summary.checkNativeParentEvaluationSummaryData
              (reverse replays)
              (replicate 11 Nothing)
              Nothing
              summary
          )
        thirdReplay <- requiredAt 2 replays
        reject
          ( Summary.checkNativeParentEvaluationSummaryData
              (thirdReplay : drop 1 replays)
              (replicate 11 Nothing)
              Nothing
              summary
          )
    , testCase "arena reference root is exact and neither omission nor extra reference is admitted" $ do
        Fixture replays _ <- get
        let bare = summaryFor replays Nothing Nothing
            withReference = summaryFor replays Nothing (Just arenaRoot)
        Summary.checkNativeParentEvaluationSummaryData
          replays
          (replicate 11 Nothing)
          (Just arenaRoot)
          withReference
          @?= Right ()
        reject
          (Summary.checkNativeParentEvaluationSummaryData replays (replicate 11 Nothing) (Just arenaRoot) bare)
        reject
          (Summary.checkNativeParentEvaluationSummaryData replays (replicate 11 Nothing) Nothing withReference)
        reject
          ( Summary.checkNativeParentEvaluationSummaryData
              replays
              (replicate 11 Nothing)
              (Just otherRoot)
              withReference
          )
    , testCase
        "missing neural witness and unexpected witness in a host slot refuse exact expected DATA binding"
        $ do
          Fixture replays _ <- get
          reject
            ( Summary.checkNativeParentEvaluationSummaryData
                replays
                (replicate 11 (Just exampleDevice))
                Nothing
                (summaryFor replays Nothing Nothing)
            )
          reject
            ( Summary.checkNativeParentEvaluationSummaryData
                replays
                (replicate 11 Nothing)
                Nothing
                (summaryFor replays (Just exampleDevice) Nothing)
            )
    , testCase "substrate field cannot be substituted even by another valid lane DATA label" $
        changedDevice get (\raw -> raw {Witness.rawWitnessSubstrate = "apple-silicon"})
    , testCase "backend field cannot be substituted by another nonblank DATA value" $
        changedDevice get (\raw -> raw {Witness.rawWitnessBackend = "another-data-backend"})
    , testCase "kernel hash field compares every retained hexadecimal byte" $
        changedDevice get (\raw -> raw {Witness.rawWitnessKernelHash = Text.replicate 64 "c"})
    , testCase "artifact path field cannot be replaced by another valid DATA path" $
        changedDevice get (\raw -> raw {Witness.rawWitnessArtifactPath = "/ordinary/another-data.kernel"})
    , testCase "artifact SHA256 field compares all64 retained characters" $
        changedDevice get (\raw -> raw {Witness.rawWitnessArtifactSha256 = Text.replicate 64 "d"})
    , testCase "executed identity field cannot be replaced by another nonblank DATA identity" $
        changedDevice
          get
          (\raw -> raw {Witness.rawWitnessExecutedIdentity = "another-data-executed-identity"})
    ]

positions :: [(Replay.NativeReplayObjectStage, Word64)]
positions =
  [(stage, index) | index <- [0 .. 4], stage <- [Replay.InitialModelReplay, Replay.FinalModelReplay]]
    <> [(Replay.StoredFinalModelReplay, 0)]

summaryFor
  :: [Replay.NativeReplayObjectData]
  -> Maybe Witness.RawDeviceExecutionWitness
  -> Maybe Digest
  -> Summary.NativeParentEvaluationSummaryData
summaryFor replays device reference =
  Summary.NativeParentEvaluationSummaryData
    reference
    [ Summary.NativeParentEvaluationMatchData
        ordinal
        (Replay.nativeReplayObjectStage object)
        (Replay.nativeReplayObjectIndex object)
        (Replay.nativeReplayObjectRoot object)
        (Replay.nativeReplayObjectRoot object)
        device
    | (ordinal, object) <- zip [0 ..] replays
    ]

exampleDevice :: Witness.RawDeviceExecutionWitness
exampleDevice =
  Witness.RawDeviceExecutionWitness
    "linux-cpu"
    "ordinary-DATA-backend"
    (Text.replicate 64 "a")
    "/ordinary/not-observed.kernel"
    (Text.replicate 64 "b")
    "ordinary-DATA-executed-identity"

arenaRoot, otherRoot :: Digest
arenaRoot = hashBytes "ordinary arena reference metadata; no actual calibration cap"
otherRoot = hashBytes "different ordinary root DATA"

-- Keep this exact base-only list traversal; no extra dependency for the hint.
{- HLINT ignore editAt "Use zipWithFrom" -}
editAt
  :: Int
  -> (Summary.NativeParentEvaluationMatchData -> Summary.NativeParentEvaluationMatchData)
  -> Summary.NativeParentEvaluationSummaryData
  -> Summary.NativeParentEvaluationSummaryData
editAt index change value =
  value
    { Summary.parentSummaryMatches =
        zipWith
          (\position item -> if position == index then change item else item)
          [0 ..]
          (Summary.parentSummaryMatches value)
    }

headMatch :: Summary.NativeParentEvaluationSummaryData -> Summary.NativeParentEvaluationMatchData
headMatch value = case Summary.parentSummaryMatches value of
  first : _ -> first
  [] -> error "complete fixture requires eleven ordinary matches"

otherStage :: Replay.NativeReplayObjectStage -> Replay.NativeReplayObjectStage
otherStage Replay.InitialModelReplay = Replay.FinalModelReplay
otherStage Replay.FinalModelReplay = Replay.StoredFinalModelReplay
otherStage Replay.StoredFinalModelReplay = Replay.InitialModelReplay

changedDevice
  :: IO Fixture -> (Witness.RawDeviceExecutionWitness -> Witness.RawDeviceExecutionWitness) -> Assertion
changedDevice get change = do
  Fixture replays _ <- get
  let summary = summaryFor replays (Just exampleDevice) Nothing
      changed = editAt 3 (\value -> value {Summary.parentSummaryDevice = Just (change exampleDevice)}) summary
  _ <- right (Summary.refineNativeParentEvaluationSummaryData changed)
  reject
    ( Summary.checkNativeParentEvaluationSummaryData
        replays
        (replicate 11 (Just exampleDevice))
        Nothing
        changed
    )

acquire :: IO Fixture
acquire = do
  spec <- right (Reference.canonicalNativeReturnSpec "ARS" "cartpole")
  actions <- case Reference.nativeReturnSpecDomain spec of
    Reference.NativeUnmaskedDiscrete count -> pure count
    _ -> fail "actual cartpole public action domain differs"
  let config =
        Ars.defaultArsTrainConfig
          { Ars.arsObsSize = Reference.nativeReturnSpecObservationSize spec
          , Ars.arsActionCount = actions
          , Ars.arsMaxEpisodeSteps = Reference.nativeReturnSpecHorizon spec
          }
      dimensions = actions * Reference.nativeReturnSpecObservationSize spec
      theta = VU.replicate dimensions 0
  (root, entries) <- projected (Evaluation.evaluateNativeArsReturnPolicy spec config theta)
  (alternate, alternateEntries) <-
    projected
      ( Evaluation.evaluateNativeArsReturnPolicy
          spec
          config
          (VU.generate dimensions (\index -> if index == 0 then 1 else 0))
      )
  let allocation = hashBytes "ordinary summary allocation label"
      attempt = hashBytes "ordinary summary attempt label"
      one (stage, index) = right (Replay.refineNativeReplayObjectData stage index allocation attempt root entries)
  replays <- traverse one positions
  other <-
    right
      ( Replay.refineNativeReplayObjectData
          Replay.InitialModelReplay
          0
          allocation
          attempt
          alternate
          alternateEntries
      )
  pure (Fixture replays other)
 where
  projected raw = do
    Evaluation.nativeEvaluationStatus raw @?= Evaluation.NativeEvaluationComplete
    assertBool "full actual fixed-case source" (length (Evaluation.nativeEvaluationEpisodes raw) == 20)
    assertBool
      "host evaluator does not synthesize MLP forwards"
      (null (Evaluation.nativeEvaluationForwards raw))
    (root, pool) <- right =<< Project.projectReturnEvaluationData Graph.emptyNodePool raw
    pure (root, [(key, bytes) | (key, _, bytes) <- Graph.nodePoolEntries pool])

canonicalWire :: Summary.NativeParentEvaluationSummaryData -> ByteString
canonicalWire value =
  wireWith
    domain
    (word 1)
    (maybe nullValue digest (Summary.parentSummaryArenaReference value))
    (listHeader (fromIntegral (length (Summary.parentSummaryMatches value))))
    (map matchWire (Summary.parentSummaryMatches value))

wireWith :: Text -> ByteString -> ByteString -> ByteString -> [ByteString] -> ByteString
wireWith name version reference count items = listHeader 4 <> text name <> version <> reference <> count <> BS.concat items
matchWire :: Summary.NativeParentEvaluationMatchData -> ByteString
matchWire value =
  itemWith
    value
    (word (Summary.parentSummaryOrdinal value))
    (word (code (Summary.parentSummaryStage value)))
    (word (Summary.parentSummaryIndex value))
    (digest (Summary.parentSummaryExpectedRoot value))
    (digest (Summary.parentSummaryActualRoot value))
    ( maybe
        nullValue
        (\raw -> listHeader 6 <> BS.concat (map text (rawFields raw)))
        (Summary.parentSummaryDevice value)
    )
itemWith
  :: Summary.NativeParentEvaluationMatchData
  -> ByteString
  -> ByteString
  -> ByteString
  -> ByteString
  -> ByteString
  -> ByteString
  -> ByteString
itemWith _ ordinal stage index expected actual device = listHeader 6 <> ordinal <> stage <> index <> expected <> actual <> device
rawFields :: Witness.RawDeviceExecutionWitness -> [Text]
rawFields raw =
  [ Witness.rawWitnessSubstrate raw
  , Witness.rawWitnessBackend raw
  , Witness.rawWitnessKernelHash raw
  , Witness.rawWitnessArtifactPath raw
  , Witness.rawWitnessArtifactSha256 raw
  , Witness.rawWitnessExecutedIdentity raw
  ]
code :: Replay.NativeReplayObjectStage -> Word64
code Replay.InitialModelReplay = 0
code Replay.FinalModelReplay = 1
code Replay.StoredFinalModelReplay = 2
word :: Word64 -> ByteString
word = Wire.encodeStrict . CBOR.encodeWord64
listHeader :: Word64 -> ByteString
listHeader = Wire.encodeStrict . CBOR.encodeListLen . fromIntegral
text :: Text -> ByteString
text = Wire.encodeStrict . CBOR.encodeString
digest :: Digest -> ByteString
digest = Wire.encodeStrict . CBOR.encodeBytes . digestBytes
nullValue :: ByteString
nullValue = Wire.encodeStrict CBOR.encodeNull
domain :: Text
domain = "jitml-native-parent-evaluation-summary-v1"
requiredAt :: Int -> [value] -> IO value
requiredAt index values = case drop index values of
  first : _ | index >= 0 -> pure first
  _ ->
    assertFailure "complete ordinary fixture is missing its required indexed item"
      >> fail "fixture cardinality"

right :: (Show error) => Either error value -> IO value
right (Right value) = pure value
right (Left reason) = assertFailure (show reason) >> fail "expected ordinary DATA Right"
reject :: (Show value) => Either CodecError value -> Assertion
reject (Left _) = pure ()
reject (Right actual) = assertFailure ("expected ordinary DATA refusal, got " <> show actual)
