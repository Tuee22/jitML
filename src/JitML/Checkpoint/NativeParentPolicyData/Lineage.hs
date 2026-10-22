{-# LANGUAGE OverloadedStrings #-}

-- | Semantic recorded device/process/ARS lineage DATA only. No witness, actual
-- observed process, ARS origin or parent-authentication capability is returned.
module JitML.Checkpoint.NativeParentPolicyData.Lineage
  ( NativeParentExpectations (..)
  , NativeDeviceObservationData (..)
  , NativeArsLineageData (..)
  , NativeArsSourceData (..)
  , decodeProducerBundle
  , verifyProducer
  , verifyDevice
  , decodeArsLineage
  , verifyArsLineage
  ) where

import Control.Monad (unless)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Either.Combinators (mapLeft)
import Data.Maybe (isNothing)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as UTF8

import JitML.Checkpoint.NativeParentPolicyData.Node qualified as Node
import JitML.Checkpoint.NativePhase.CBOR qualified as Wire
import JitML.Checkpoint.NativePhase.Context qualified as Context
import JitML.Checkpoint.NativePhase.Graph qualified as Graph
import JitML.Checkpoint.NativePhase.Schema qualified as Schema
import JitML.Checkpoint.NativePhase.Types
import JitML.Execution.ProducerObservation qualified as Process
import JitML.Plan.NativeChildAssociation qualified as Association
import JitML.Plan.NativeSingletonPlan qualified as Singleton
import JitML.Plan.Plan qualified as Plan
import JitML.Product.DeviceWitness qualified as Witness
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.Product.SourceDigest qualified as Source
import JitML.RL.Algorithms.ArsTrainer qualified as Ars
import JitML.RL.NativeReturnEvaluation qualified as Return
import JitML.RL.NativeReturnReferences qualified as References
import JitML.RL.ProductBudget qualified as Budget
import JitML.Substrate (Substrate, renderSubstrate)

data NativeParentExpectations = NativeParentExpectations
  { nativeParentExpectedSource :: !Source.SourceStamp
  , nativeParentExpectedExecutable :: !Digest
  , nativeParentExpectedAssociation :: !Context.NativeContextAssociation
  , nativeParentExpectedSources :: !Context.NativeContextSources
  , nativeParentExpectedProcessIds :: !(Integer, Integer)
  }
  deriving stock (Eq, Show)
data NativeDeviceObservationData
  = NativeHostNoMlpData
  | NativeRecordedDeviceData !Witness.RawDeviceExecutionWitness
  deriving stock (Eq, Show)
data NativeArsSourceData
  = NativeArsObservedSourceData !Text !Source.SourceStamp
  | NativeArsSuppliedSourceData !Source.SourceStamp
  deriving stock (Eq, Show)
data NativeArsLineageData = NativeArsLineageData
  { nativeLineageOuterAttempt :: !Digest
  , nativeLineageAcquisition :: !Digest
  , nativeLineageInnerAttempt :: !Text
  , nativeLineageContext :: !Digest
  , nativeLineageBefore :: !Process.RecordedProducerObservation
  , nativeLineageAfter :: !(Maybe Process.RecordedProducerObservation)
  , nativeLineageSource :: !(Maybe NativeArsSourceData)
  , nativeLineageRuntime :: !(Maybe Ars.ArsNumericalRuntime)
  }
  deriving stock (Eq, Show)

check :: Bool -> Text -> Either CodecError ()
check condition message = unless condition (Left (Malformed message))
hex :: Digest -> Text
hex =
  Text.pack
    . concatMap
      (\byte -> [digits !! fromIntegral (byte `div` 16), digits !! fromIntegral (byte `mod` 16)])
    . BS.unpack
    . digestBytes
 where
  digits = "0123456789abcdef"

decodeProducerBundle
  :: Graph.NodePool
  -> Digest
  -> Either
       CodecError
       (Maybe Process.RecordedProducerObservation, Maybe Process.RecordedProducerObservation)
decodeProducerBundle pool root = do
  _ <- Graph.producerClosureBytes root pool
  Node.runDecode pool $ do
    actual <- Node.fields NProducerContextBundle root
    case actual of
      [before, after, _metadata] -> (,) <$> optional before <*> optional after
      _ -> Node.reject "parent producer bundle fields differ"
 where
  optional VNull = pure Nothing
  optional (VRef digest) = Just <$> recorded digest
  optional _ = Node.reject "parent producer optional record differs"
  recorded root_ = do
    actual <- Node.fields NRecordedProducer root_
    case actual of
      [ path
        , VDigest executable
        , bytes
        , pid
        , ppid
        , kernel
        , machine
        , release
        , os
        , arch
        , compiler
        , version
        , source
        ] -> do
          observed <- case source of
            VNull -> pure Nothing
            VList [VText sourceRoot, VList [VWord algorithm, VDigest stamp]] ->
              pure (Just (Text.unpack sourceRoot, Source.SourceStamp algorithm (hex stamp)))
            _ -> Node.reject "parent producer observed-source record differs"
          Process.RecordedProducerObservation . Text.unpack
            <$> Node.text path
            <*> pure (hex executable)
            <*> Node.word bytes
            <*> Node.magnitude pid
            <*> Node.magnitude ppid
            <*> Node.text kernel
            <*> Node.text machine
            <*> Node.text release
            <*> Node.text os
            <*> Node.text arch
            <*> Node.text compiler
            <*> Node.text version
            <*> pure observed
      _ -> Node.reject "parent recorded producer fields differ"

verifyProducer
  :: NativeParentExpectations -> Process.RecordedProducerObservation -> Either CodecError ()
verifyProducer expected actual = do
  check
    ( Process.recordedExecutableFileSha256 actual == hex (nativeParentExpectedExecutable expected)
        && Process.recordedExecutableFileByteCount actual > 0
        && not (null (Process.recordedExecutableFilePath actual))
    )
    "parent recorded executable differs from independently supplied expected FILE identity"
  check
    ( (Process.recordedProcessId actual, Process.recordedParentProcessId actual)
        == nativeParentExpectedProcessIds expected
        && fst (nativeParentExpectedProcessIds expected) > 0
        && snd (nativeParentExpectedProcessIds expected) > 0
    )
    "parent recorded PID/PPID differs from the externally observed child process"
  case ( Context.nativeContextObservedSource (nativeParentExpectedSources expected)
       , Process.recordedObservedSource actual
       ) of
    (Nothing, Nothing) -> pure ()
    (Just stamp, Just (_, recorded)) ->
      check
        (stamp == recorded && stamp == nativeParentExpectedSource expected)
        "parent recorded source differs from parent-owned expected observed source"
    _ -> Left (Malformed "parent observed-source presence differs from original role")

verifyDevice :: Substrate -> Bool -> ByteString -> Either CodecError NativeDeviceObservationData
verifyDevice lane host bytes = do
  check (BS.length bytes <= 16384) "parent device record exceeds its closed bound"
  Wire.runParser parser bytes
 where
  parser = do
    Wire.expectList 3
    domain <- Wire.getText GeneralTextBytes 64
    version <- Wire.getWord
    Wire.liftEither
      ( check
          (domain == "jitml-native-device-observation-v1" && version == 1)
          "parent device domain/version differs"
      )
    count <- Wire.getListLength SequenceFanout 2
    tag <- Wire.getWord
    case (host, tag, count) of
      (True, 0, 1) -> pure NativeHostNoMlpData
      (False, 2, 2) -> do
        absent <- Wire.nextIsNull
        Wire.liftEither (check (not absent) "parent device witness is absent")
        Wire.expectList 6
        substrate <- Wire.getText GeneralTextBytes 1024
        backend <- Wire.getText GeneralTextBytes 1024
        kernel <- Wire.getText GeneralTextBytes 1024
        path <- Wire.getText PathTextBytes 4096
        artifact <- Wire.getText GeneralTextBytes 1024
        identity <- Wire.getText GeneralTextBytes 1024
        let raw = Witness.RawDeviceExecutionWitness substrate backend kernel path artifact identity
        -- This existing refiner only checks recorded shape; discard its result
        -- and return raw DATA, never a restored execution witness.
        refined <-
          Wire.liftEither (mapLeft Malformed (Witness.refineRawDeviceExecutionWitness raw))
        Wire.liftEither
          ( check
              (Witness.witnessSubstrate refined == lane && Witness.deviceExecutionWitnessToRaw refined == raw)
              "parent recorded device lane or exact canonical fields differ"
          )
        pure (NativeRecordedDeviceData raw)
      _ ->
        Wire.parserFailure
          (Malformed "parent device record is failed, unqueried or disagrees with host/neural family")

decodeArsLineage :: Bool -> ByteString -> Either CodecError NativeArsLineageData
decodeArsLineage origin bytes = do
  check (BS.length bytes <= 65536) "parent ARS lineage exceeds64KiB"
  Wire.runParser parser bytes
 where
  parser = do
    Wire.expectList 9
    domain <- Wire.getText GeneralTextBytes 64
    version <- Wire.getWord
    Wire.liftEither
      ( check
          ( domain
              == (if origin then "jitml-native-ars-origin-lineage-v1" else "jitml-native-ars-begun-lineage-v1")
              && version == 1
          )
          "parent ARS lineage domain/version differs"
      )
    outer <- Wire.getDigest
    acquisition <- Wire.getDigest
    inner <- Wire.getText GeneralTextBytes 64
    _ <- Wire.liftEither (Context.digestFromCanonicalText inner)
    context <- Wire.getDigest
    producer <- Wire.getDigest
    count <- Wire.getListLength PoolNodes 64
    Wire.ensureMinimumItems (fromIntegral count) 40
    pool <- readPool count Nothing Graph.emptyNodePool 0
    (before, after) <- Wire.liftEither (decodeProducerBundle pool producer)
    selected <- Wire.liftEither (Graph.reachableNodePool [producer] pool)
    Wire.liftEither
      ( check
          (Graph.nodePoolEntries selected == Graph.nodePoolEntries pool)
          "parent ARS producer pool has foreign nodes"
      )
    actualBefore <-
      maybe
        (Wire.parserFailure (Malformed "parent ARS lineage lacks original before-process"))
        pure
        before
    if origin
      then do
        Wire.expectList 5
        runtime <-
          Ars.ArsNumericalRuntime
            <$> component
            <*> component
            <*> component
            <*> component
            <*> Wire.getText GeneralTextBytes 1024
        actualAfter <-
          maybe (Wire.parserFailure (Malformed "parent ARS origin lacks after-process")) pure after
        pure
          ( NativeArsLineageData
              outer
              acquisition
              inner
              context
              actualBefore
              (Just actualAfter)
              Nothing
              (Just runtime)
          )
      else do
        Wire.liftEither
          ( check
              (case after of Nothing -> True; _ -> False)
              "parent begun lineage unexpectedly contains after-process"
          )
        fields_ <- Wire.getListLength SequenceFanout 3
        tag <- Wire.getWord
        source <- case (tag, fields_) of
          (0, 3) -> NativeArsObservedSourceData <$> Wire.getText PathTextBytes 4096 <*> sourceStamp
          (1, 2) -> NativeArsSuppliedSourceData <$> sourceStamp
          _ -> Wire.parserFailure (Malformed "parent ARS source coverage role/arity differs")
        pure
          (NativeArsLineageData outer acquisition inner context actualBefore Nothing (Just source) Nothing)
  component = Wire.getText ProducerComponentBytes 256
  sourceStamp = do
    Wire.expectList 2
    algorithm <- Wire.getWord
    sha <- Wire.getText GeneralTextBytes 64
    _ <- Wire.liftEither (Context.digestFromCanonicalText sha)
    Wire.liftEither
      (check (algorithm == Source.sourceDigestAlgorithm) "parent ARS source algorithm differs")
    pure (Source.SourceStamp algorithm sha)
  readPool 0 _ pool _ = pure pool
  readPool count previous pool owned = do
    Wire.expectList 2
    expected <- Wire.getDigest
    Wire.liftEither
      (check (maybe True (< expected) previous) "parent ARS producer nodes are not ordered unique")
    raw <- Wire.getBytes ProducerBundleBytes 16384
    let nextOwned = owned + toInteger (BS.length raw)
    Wire.liftEither (check (nextOwned <= 16384) "parent ARS producer bytes exceed16KiB")
    node <- Wire.liftEither (Schema.decodeNodeData raw)
    (actual, next) <- Wire.liftEither (Graph.internNode node pool)
    Wire.liftEither
      ( check
          (expected == actual && Schema.nodeCanonicalBytes node == raw)
          "parent ARS producer node checksum differs"
      )
    readPool (count - 1) (Just expected) next nextOwned

verifyArsLineage
  :: NativeParentExpectations
  -> Cohort.NativeRlCohortPlan
  -> Cohort.NativeRlSeedPlan
  -> Digest
  -> Digest
  -> NativeArsLineageData
  -> NativeArsLineageData
  -> Either CodecError Ars.ArsNumericalRuntime
verifyArsLineage expected cohort child outer acquisition begun origin = do
  let shared actual = nativeLineageOuterAttempt actual == outer && nativeLineageAcquisition actual == acquisition
  check
    ( shared begun
        && shared origin
        && nativeLineageInnerAttempt begun == nativeLineageInnerAttempt origin
        && nativeLineageContext begun == nativeLineageContext origin
    )
    "parent ARS outer/inner original lineage differs"
  verifyProducer expected (nativeLineageBefore begun)
  verifyProducer expected (nativeLineageBefore origin)
  check
    ( Process.compareRecordedProducerObservationData
        (nativeLineageBefore begun)
        (nativeLineageBefore origin)
        == Right ()
    )
    "parent ARS begun/origin before-process fields differ"
  after <-
    maybe (Left (Malformed "parent ARS after-process is absent")) Right (nativeLineageAfter origin)
  verifyProducer expected after
  check
    (Process.compareRecordedProducerObservationData (nativeLineageBefore origin) after == Right ())
    "parent ARS before/after executable/process/source fields differ"
  coverage <-
    maybe (Left (Malformed "parent ARS begun source role is absent")) Right (nativeLineageSource begun)
  sourceFields <- case coverage of
    NativeArsObservedSourceData root stamp -> do
      check
        ( Process.recordedObservedSource (nativeLineageBefore begun) == Just (Text.unpack root, stamp)
            && stamp == nativeParentExpectedSource expected
        )
        "parent ARS observed source coverage differs"
      pure
        [ "locally-observed-source"
        , root
        , Text.pack (show (Source.stampAlgorithm stamp))
        , Source.stampSha256 stamp
        ]
    NativeArsSuppliedSourceData stamp -> do
      check
        ( isNothing (Context.nativeContextObservedSource (nativeParentExpectedSources expected))
            && Context.nativeContextSuppliedSource (nativeParentExpectedSources expected) == Just stamp
            && stamp == nativeParentExpectedSource expected
        )
        "parent ARS supplied source coverage differs"
      pure
        [ "unobserved-supplied-parent-source"
        , Text.pack (show (Source.stampAlgorithm stamp))
        , Source.stampSha256 stamp
        ]
  compiled <-
    maybe
      (Left (Malformed "parent ARS canonical compiled recipe is absent"))
      Right
      (Cohort.nativeRlSeedPlanCompiledReturn child)
  associationFields <- case nativeParentExpectedAssociation expected of
    Context.DirectLocalContext _ ->
      pure
        [ "direct-native-local-observation"
        , Singleton.renderNativeSingletonPlan
            (Cohort.nativeRlSeedPlanSingleton (Cohort.nativeRlCohortServingChild cohort))
        ]
    Context.SuppliedScenarioContext invocation -> do
      association <-
        mapLeft
          Malformed
          (Cohort.nativeRlSeedAssociation cohort invocation (Cohort.nativeRlSeedPlanIndex child))
      pure
        [ "supplied-native-parent-association-data"
        , Association.renderNativeChildAssociation association
        , Association.nativeAssociationDigest association
        ]
  let singleton = Cohort.nativeRlSeedPlanSingleton child
      values =
        [ "jitml-native-ars-observed-context-v1"
        , nativeLineageInnerAttempt begun
        , Matrix.rowId (Cohort.nativeRlCohortPlanRow cohort)
        , Plan.planIdText (Cohort.nativeRlCohortPlanId cohort)
        , Singleton.renderNativeSingletonPlan singleton
        , Budget.renderCompiledRlPlanTransport compiled
        , renderSubstrate (Singleton.nativeSingletonSubstrate singleton)
        , Text.pack (show (Cohort.nativeSeedIndexValue (Cohort.nativeRlSeedPlanIndex child)))
        , References.nativeReturnReferenceContract
        , Return.nativeReturnEvaluationContract
        , Process.recordedExecutableFileSha256 (nativeLineageBefore begun)
        ]
          <> sourceFields
          <> associationFields
      frame value =
        let raw = UTF8.encodeUtf8 value in UTF8.encodeUtf8 (Text.pack (show (BS.length raw))) <> ":" <> raw
  check
    (hashBytes (BS.concat (map frame values)) == nativeLineageContext begun)
    "parent ARS context digest differs from exact child/association/source/executable data"
  runtime <-
    maybe
      (Left (Malformed "parent ARS numerical runtime is absent"))
      Right
      (nativeLineageRuntime origin)
  let before = nativeLineageBefore origin
  check
    ( Ars.arsRuntimeOperatingSystem runtime == Process.recordedBuildOperatingSystem before
        && Ars.arsRuntimeArchitecture runtime == Process.recordedBuildArchitecture before
        && Ars.arsRuntimeCompiler runtime == Process.recordedBuildCompiler before
        && Ars.arsRuntimeCompilerVersion runtime == Process.recordedBuildCompilerVersion before
    )
    "parent ARS lineage runtime differs from original producer build fields"
  pure runtime
