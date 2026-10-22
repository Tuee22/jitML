{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

-- Public writer-prepared ordinary DATA only. No write/admission, actual device,
-- trained/native/Root cap or authenticated parent is fabricated. Native fixture
-- completions are explicitly synthetic self-consistent recorded claims.
module NativeRecordedCheckpointData (nativeRecordedCheckpointDataTests) where

import Data.Bifunctor (second)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.IORef (newIORef, readIORef)
import Data.List (find)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import GHC.Float (castDoubleToWord64, castWord64ToDouble)
import Test.Tasty (TestTree, testGroup, withResource)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Checkpoint.Format qualified as Format
import JitML.Checkpoint.Store qualified as Store
import JitML.Checkpoint.WeightCodec qualified as Weight
import JitML.Plan.Plan qualified as Plan
import JitML.Product.Completion qualified as Completion
import JitML.Product.Convergence qualified as Convergence
import JitML.Product.DeviceWitness qualified as Witness
import JitML.Product.Matrix qualified as Matrix
import JitML.RL.ArsHostTrace qualified as ArsTrace
import JitML.Substrate (Substrate (LinuxCPU))
import JitML.Training.Budget qualified as Budget

data Fixture = Fixture
  { candidate :: !Store.PreparedCheckpointSnapshot
  , alternateCandidate :: !Store.PreparedCheckpointSnapshot
  , nativePrepared :: !Store.PreparedCheckpointSnapshot
  , nativeLogical :: !Format.CheckpointManifest
  , nativeLogicalPayloads :: ![(Text, LBS.ByteString)]
  , nativeWeightBits :: ![Word64]
  }

-- Keep this exact base-only list traversal; no extra dependency for the hint.
{- HLINT ignore nativeRecordedCheckpointDataTests "Use drop1" -}
nativeRecordedCheckpointDataTests :: TestTree
nativeRecordedCheckpointDataTests = withResource acquire (const (pure ())) $ \get ->
  testGroup
    "native recorded checkpoint DATA"
    [ testCase "public writer-prepared candidate commit returns the exact ordinary manifest and commit" $ do
        f <- get
        let prepared = candidate f
        checkCommit prepared
          @?= Right (Store.preparedSnapshotManifest prepared, Store.preparedSnapshotCommit prepared)
    , testCase "public writer-prepared completed native record retains exact canonical commit bytes" $ do
        f <- get
        let prepared = nativePrepared f
        (manifest, commit) <- right (checkCommit prepared)
        Format.encodeManifestCbor manifest @?= Store.preparedSnapshotManifestBytes prepared
        Store.encodeWriterCommit commit @?= Store.encodeWriterCommit (Store.preparedSnapshotCommit prepared)
    , testCase "wrong requested experiment refuses before returning recorded snapshot DATA" $ do
        f <- get
        let p = candidate f
        reject
          ( Store.checkNativeRecordedSnapshotCommitData
              "another-experiment"
              (Store.preparedSnapshotManifestSha p)
              (Store.preparedSnapshotManifestBytes p)
              (Store.encodeWriterCommit (Store.preparedSnapshotCommit p))
          )
    , testCase "wrong requested manifest address cannot relabel exact supplied bytes" $ do
        f <- get
        let p = candidate f
        reject
          ( Store.checkNativeRecordedSnapshotCommitData
              (experiment p)
              (sha "f")
              (Store.preparedSnapshotManifestBytes p)
              (Store.encodeWriterCommit (Store.preparedSnapshotCommit p))
          )
    , testCase "empty corrupt and trailing manifest bytes cannot reuse the original commit" $ do
        f <- get
        let p = candidate f
            bytes = Store.preparedSnapshotManifestBytes p
        mapM_
          ( \changed ->
              reject
                ( Store.checkNativeRecordedSnapshotCommitData
                    (experiment p)
                    (Store.preparedSnapshotManifestSha p)
                    changed
                    (Store.encodeWriterCommit (Store.preparedSnapshotCommit p))
                )
          )
          [LBS.empty, LBS.pack [255], bytes <> LBS.singleton 0]
    , testCase "every truncated commit prefix refuses canonical writer decoding" $ do
        f <- get
        let p = candidate f
            bytes = Store.encodeWriterCommit (Store.preparedSnapshotCommit p)
        mapM_ (\count -> reject (checkCommitBytes p (BS.take count bytes))) [0 .. BS.length bytes - 1]
    , testCase "writer commit trailing bytes do not form another canonical commit" $ do
        f <- get
        let p = candidate f
        reject
          (checkCommitBytes p (Store.encodeWriterCommit (Store.preparedSnapshotCommit p) <> BS.singleton 0))
    , testCase "another valid writer transaction cannot stand in for this snapshot" $ do
        f <- get
        reject (checkCommitWith (candidate f) (Store.preparedSnapshotCommit (alternateCandidate f)))
    , testCase "changed commit experiment refuses exact recorded binding" $
        commitChange get (\commit -> commit {Store.writerCommitExperimentHash = "another-experiment"})
    , testCase "changed commit snapshot id refuses its original physical namespace" $
        commitChange get (\commit -> commit {Store.writerCommitSnapshotId = sha "e"})
    , testCase "changed commit reservation id refuses canonical derived reservation identity" $
        commitChange get (\commit -> commit {Store.writerCommitReservationId = sha "e"})
    , testCase "changed commit manifest SHA cannot address the original manifest bytes" $
        commitChange get (\commit -> commit {Store.writerCommitManifestSha = sha "e"})
    , testCase "completed snapshot kind cannot be changed to candidate kind" $
        commitChange get (\commit -> commit {Store.writerCommitKind = Store.WriterCandidateSnapshot})
    , testCase "missing physical table entries refuse complete manifest graph agreement" $
        commitChange
          get
          ( \commit -> commit {Store.writerCommitPhysicalObjects = drop 1 (Store.writerCommitPhysicalObjects commit)}
          )
    , testCase "duplicate or reversed physical table entries refuse canonical uniqueness and order" $ do
        f <- get
        let p = nativePrepared f
            commit = Store.preparedSnapshotCommit p
            objects = Store.writerCommitPhysicalObjects commit
        assertBool "native record supplies distinct weight and companion objects" (length objects == 2)
        reject (checkCommitWith p (commit {Store.writerCommitPhysicalObjects = objects <> take 1 objects}))
        reject (checkCommitWith p (commit {Store.writerCommitPhysicalObjects = reverse objects}))
    , testCase "changed physical object SHA cannot preserve the derived snapshot descriptor" $
        commitObjectChange get (\item -> item {Store.writerPhysicalObjectSha = sha "e"})
    , testCase "changed original logical key cannot preserve its scoped physical key" $
        commitObjectChange
          get
          ( \item ->
              item
                { Store.writerPhysicalObjectOriginalKey = Store.writerPhysicalObjectOriginalKey item <> "-changed"
                }
          )
    , testCase "changed physical key cannot preserve its original snapshot namespace" $
        commitObjectChange
          get
          (\item -> item {Store.writerPhysicalObjectKey = Store.writerPhysicalObjectKey item <> "-changed"})
    , testCase "rehashed different manifest DATA still cannot reuse an old writer commit" $ do
        f <- get
        let p = nativePrepared f
            manifest = (Store.preparedSnapshotManifest p) {Format.manifestId = "different-ordinary-manifest"}
            bytes = Format.encodeManifestCbor manifest
            addressed = Weight.jmw1ContentSha bytes
            commit = (Store.preparedSnapshotCommit p) {Store.writerCommitManifestSha = addressed}
        reject
          ( Store.checkNativeRecordedSnapshotCommitData
              (experiment p)
              addressed
              bytes
              (Store.encodeWriterCommit commit)
          )
    , testCase "complete current native recorded payload DATA retains all exact decoded JMW1 bits" $ do
        f <- get
        let p = nativePrepared f
        (manifest, commit, weights, completed, host) <- right (checkPayload p (strictPayloads p))
        manifest @?= Store.preparedSnapshotManifest p
        commit @?= Store.preparedSnapshotCommit p
        Just completed @?= Format.manifestCompletedTraining manifest
        host @?= Nothing
        case weights of
          [loaded] -> do
            map castDoubleToWord64 (Store.loadedWeightValues loaded) @?= nativeWeightBits f
            Store.loadedWeightJmw1Bytes loaded
              @?= LBS.toStrict (Weight.encodeJmw1 (map castWord64ToDouble (nativeWeightBits f)))
          _ -> assertFailure "current native record did not retain one exact final tensor"
    , testCase "payload table input order is DATA only and does not change validated output" $ do
        f <- get
        let p = nativePrepared f
        checkPayload p (reverse (strictPayloads p)) @?= checkPayload p (strictPayloads p)
    , testCase "generic candidate DATA never becomes a current native completed payload result" $ do
        f <- get
        let p = candidate f
        reject (checkPayload p (strictPayloads p))
    , testCase "duplicate missing and extra payload map keys refuse complete physical closure" $ do
        f <- get
        let p = nativePrepared f
            payloads = strictPayloads p
        reject (checkPayload p (payloads <> take 1 payloads))
        reject (checkPayload p (drop 1 payloads))
        reject (checkPayload p (payloads <> [("ordinary-foreign-key", BS.empty)]))
    , testCase "payload map cap plus one refuses before demanding poisoned members or metadata decode" $ do
        f <- get
        let p = nativePrepared f
        reject
          ( Store.checkNativeRecordedCheckpointPayloadData
              (experiment p)
              (Store.preparedSnapshotManifestSha p)
              (LBS.singleton 0)
              BS.empty
              (replicate 4 (error "oversize map must not inspect members"))
          )
    , testCase "infinite payload map spine is bounded before its member values" $ do
        f <- get
        let p = nativePrepared f
        reject
          ( Store.checkNativeRecordedCheckpointPayloadData
              (experiment p)
              (Store.preparedSnapshotManifestSha p)
              (LBS.singleton 0)
              BS.empty
              (repeat (error "infinite map members must stay unforced"))
          )
    , testCase "manifest operational cap bounds an infinite shared chunk source before commit access" $ do
        let bytes = LBS.fromChunks (repeat (BS.replicate 4096 0))
        rejectContains
          "manifest exceeds"
          ( Store.checkNativeRecordedCheckpointPayloadData
              "ordinary"
              (sha "a")
              bytes
              (error "manifest cap must precede commit")
              (error "manifest cap must precede payloads")
          )
    , testCase "commit operational cap refuses before any payload map access" $ do
        f <- get
        let p = nativePrepared f
        rejectContains
          "commit exceeds"
          ( Store.checkNativeRecordedCheckpointPayloadData
              (experiment p)
              (Store.preparedSnapshotManifestSha p)
              (Store.preparedSnapshotManifestBytes p)
              (BS.replicate 65537 0)
              (error "commit cap precedes payloads")
          )
    , testCase "payload key cap checks exact UTF8 bytes before metadata decoding" $ do
        let keys = ["", Text.replicate 4097 "p", Text.replicate 2049 "λ"]
        mapM_
          ( \key ->
              rejectContains
                "payload key"
                ( Store.checkNativeRecordedCheckpointPayloadData
                    "ordinary"
                    (sha "a")
                    (LBS.singleton 0)
                    BS.empty
                    [(key, BS.empty)]
                )
          )
          keys
    , testCase "changed raw companion content cannot satisfy the original physical SHA table" $ do
        f <- get
        let p = nativePrepared f
            pointers = Format.manifestTranscriptPointers (Store.preparedSnapshotManifest p)
        pointer <- one pointers
        reject
          ( checkPayload
              p
              (replacePayload (Format.artifactPointerObjectKey pointer) "different raw bytes" (strictPayloads p))
          )
    , testCase "changed final JMW1 bytes cannot satisfy the original physical SHA table" $ do
        f <- get
        let p = nativePrepared f
        tensor <- one (Format.manifestTensors (Store.preparedSnapshotManifest p))
        reject
          ( checkPayload
              p
              ( replacePayload
                  (Format.tensorBlobKey tensor)
                  (LBS.toStrict (Weight.encodeJmw1 [0.125, 0.5]))
                  (strictPayloads p)
              )
          )
    , testCase "a freshly prepared altered weight table still must match completed final hash" $ do
        f <- get
        tensor <- one (Format.manifestTensors (nativeLogical f))
        let bytes = Weight.encodeJmw1 [0.125, 0.5]
            key = Format.blobKey (Format.manifestExperiment (nativeLogical f)) (Weight.jmw1ContentSha bytes)
            changed = tensor {Format.tensorBlobKey = key}
            manifest = (nativeLogical f) {Format.manifestTensors = [changed]}
            payloads = (key, bytes) : filter ((/= Format.tensorBlobKey tensor) . fst) (nativeLogicalPayloads f)
        p <- prepare manifest payloads
        reject (checkPayload p (strictPayloads p))
    , testCase "missing or wrong companion kind cannot be rescued by a valid writer commit" $ do
        f <- get
        let manifest = nativeLogical f
        pointer <- one (Format.manifestTranscriptPointers manifest)
        without <-
          prepare
            (manifest {Format.manifestTranscriptPointers = []})
            (filter ((/= Format.artifactPointerObjectKey pointer) . fst) (nativeLogicalPayloads f))
        reject (checkPayload without (strictPayloads without))
        wrong <-
          prepare
            ( manifest
                { Format.manifestTranscriptPointers = [pointer {Format.artifactPointerKind = "another-kind"}]
                }
            )
            (nativeLogicalPayloads f)
        reject (checkPayload wrong (strictPayloads wrong))
    , testCase
        "otherwise valid native writer snapshot with optimizer object refuses unsupported portable layout"
        $ do
          f <- get
          let manifest = nativeLogical f
              bytes = "ordinary optimizer bytes"
              key = Format.blobKey (Format.manifestExperiment manifest) (Weight.jmw1ContentSha bytes)
              optimizer = Format.OptimizerBlob "ordinary" key (fromIntegral (LBS.length bytes))
          p <-
            prepare (manifest {Format.manifestOptimizer = [optimizer]}) ((key, bytes) : nativeLogicalPayloads f)
          rejectContains "unsupported optimizer" (checkPayload p (strictPayloads p))
    , testCase
        "otherwise valid native writer snapshot with RNG object refuses unsupported portable layout"
        $ do
          f <- get
          let manifest = nativeLogical f
              bytes = LBS.replicate 8 0
              key = Format.blobKey (Format.manifestExperiment manifest) (Weight.jmw1ContentSha bytes)
              rng = Format.RngBlob "ordinary" key 1
          p <- prepare (manifest {Format.manifestRng = [rng]}) ((key, bytes) : nativeLogicalPayloads f)
          rejectContains "unsupported optimizer" (checkPayload p (strictPayloads p))
    ]

acquire :: IO Fixture
acquire = do
  let generic values = do
        let experimentId = "ordinary-recorded-candidate"
            bytes = Weight.encodeJmw1 values
            key = Format.blobKey experimentId (Weight.jmw1ContentSha bytes)
            manifest =
              Format.emptyManifest
                "ordinary-candidate"
                experimentId
                [Format.TensorBlob "weights" [length values] key]
        Store.prepareCheckpointSnapshot
          Store.WriterCandidateSnapshot
          Store.WriterNoPointerIntent
          manifest
          [(key, bytes)]
  candidateValue <- right (generic [1, 2])
  otherCandidate <- right (generic [3, 4])
  row <-
    maybe
      (assertFailure "canonical DQN cartpole row missing" >> fail "row")
      pure
      (find ((== "DQN/cartpole") . Matrix.rowId) Matrix.allProductRows)
  projection <- right (Plan.validationToEither (Matrix.projectProductRow LinuxCPU row))
  case projection of
    Matrix.SomeProductProjection _ exact -> do
      -- Runtime IORef/NOINLINE boundary proves the signed-zero fixture edit is
      -- actual raw bits; no literal negative-zero/CSE premise is assumed.
      source <- newIORef (0x8000000000000000 :: Word64)
      sign <- readIORef source
      let negative = fromBits sign
          finalWeights = [negative, 0.5]
          finalBytes = Weight.encodeJmw1 finalWeights
          initialBytes = Weight.encodeJmw1 [1, 2]
          finalSha = Weight.jmw1ContentSha finalBytes
          experimentId = Matrix.productProjectionExperimentHash exact
          bar = Matrix.productProjectionConvergenceBar exact
          metrics = [(Convergence.convergenceMetricName bar, Convergence.convergenceThreshold bar)]
          budget = Matrix.productProjectionTrainingBudget exact
          step = Budget.trainingBudgetTargetUnits budget
      assertBool
        "actual nonempty runtime signed-zero premise"
        (negative == 0 && castDoubleToWord64 negative == sign)
      recordedWitness <-
        right
          ( Witness.refineRawDeviceExecutionWitness
              ( Witness.RawDeviceExecutionWitness
                  "linux-cpu"
                  "ordinary-recorded-DATA"
                  (sha "a")
                  "/ordinary/not-observed.kernel"
                  (sha "b")
                  "ordinary-recorded-DATA"
              )
          )
      completed <-
        right
          ( Completion.completedTrainingForProductRowWithWeightHashes
              (Matrix.productProjectionPlanId exact)
              budget
              row
              (sha "c")
              experimentId
              step
              1
              metrics
              (Weight.jmw1ContentSha initialBytes)
              finalSha
              (Just recordedWitness)
          )
      let tensor = Format.TensorBlob "ordinary-recorded-weights" [2] (Format.blobKey experimentId finalSha)
          companion = "ordinary synthetic recorded companion DATA; no actual native training"
          companionSha = Weight.jmw1ContentSha companion
          companionKey = Store.canonicalProductCompanionObjectKey experimentId "rl-trajectory" companionSha
          pointer = Format.ArtifactPointer "rl-trajectory" companionKey (Just companionSha)
          base = Format.emptyManifest "ordinary-native-recorded-claim" experimentId [tensor]
          manifest =
            Format.attachCompletedTraining
              completed
              ( base
                  { Format.manifestModelFamily = Format.ReinforcementLearningPolicyFamily
                  , Format.manifestArchitecture =
                      Format.defaultArchitectureMetadata Format.ReinforcementLearningPolicyFamily
                  , Format.manifestStep = step
                  , Format.manifestMetrics = metrics
                  , Format.manifestTranscriptPointers = [pointer]
                  }
              )
          payloads = [(Format.tensorBlobKey tensor, finalBytes), (companionKey, companion)]
      prepared <- prepare manifest payloads
      pure
        ( Fixture
            candidateValue
            otherCandidate
            prepared
            manifest
            payloads
            (map castDoubleToWord64 finalWeights)
        )

{-# NOINLINE fromBits #-}
fromBits :: Word64 -> Double
fromBits = castWord64ToDouble

checkCommit
  :: Store.PreparedCheckpointSnapshot -> Either Text (Format.CheckpointManifest, Store.WriterCommit)
checkCommit p = checkCommitWith p (Store.preparedSnapshotCommit p)
checkCommitWith
  :: Store.PreparedCheckpointSnapshot
  -> Store.WriterCommit
  -> Either Text (Format.CheckpointManifest, Store.WriterCommit)
checkCommitWith p commit = checkCommitBytes p (Store.encodeWriterCommit commit)
checkCommitBytes
  :: Store.PreparedCheckpointSnapshot
  -> BS.ByteString
  -> Either Text (Format.CheckpointManifest, Store.WriterCommit)
checkCommitBytes p =
  Store.checkNativeRecordedSnapshotCommitData
    (experiment p)
    (Store.preparedSnapshotManifestSha p)
    (Store.preparedSnapshotManifestBytes p)
checkPayload
  :: Store.PreparedCheckpointSnapshot
  -> [(Text, BS.ByteString)]
  -> Either
       Text
       ( Format.CheckpointManifest
       , Store.WriterCommit
       , [Store.LoadedWeightTensor]
       , Budget.CompletedTraining
       , Maybe ArsTrace.ArsHostTrace
       )
checkPayload p =
  Store.checkNativeRecordedCheckpointPayloadData
    (experiment p)
    (Store.preparedSnapshotManifestSha p)
    (Store.preparedSnapshotManifestBytes p)
    (Store.encodeWriterCommit (Store.preparedSnapshotCommit p))
strictPayloads :: Store.PreparedCheckpointSnapshot -> [(Text, BS.ByteString)]
-- Preserve the original strict tuple pattern before the lazier second helper.
strictPayloads = map (\pair -> pair `seq` second LBS.toStrict pair) . Store.preparedSnapshotPayloads
experiment :: Store.PreparedCheckpointSnapshot -> Text
experiment = Format.manifestExperiment . Store.preparedSnapshotManifest
prepare
  :: Format.CheckpointManifest -> [(Text, LBS.ByteString)] -> IO Store.PreparedCheckpointSnapshot
prepare manifest payloads =
  right
    ( Store.prepareCheckpointSnapshot
        Store.WriterCompletedSnapshot
        (Store.WriterLatestPointerIntent (Format.latestPointerKey (Format.manifestExperiment manifest)))
        manifest
        payloads
    )
commitChange :: IO Fixture -> (Store.WriterCommit -> Store.WriterCommit) -> Assertion
commitChange get change = do
  f <- get
  let p = nativePrepared f
  reject (checkCommitWith p (change (Store.preparedSnapshotCommit p)))
commitObjectChange
  :: IO Fixture -> (Store.WriterPhysicalObject -> Store.WriterPhysicalObject) -> Assertion
commitObjectChange get change = commitChange get $ \commit ->
  commit
    { Store.writerCommitPhysicalObjects = case Store.writerCommitPhysicalObjects commit of
        first : rest -> change first : rest
        [] -> []
    }
replacePayload :: Text -> BS.ByteString -> [(Text, BS.ByteString)] -> [(Text, BS.ByteString)]
replacePayload key bytes = map (\(actual, value) -> if actual == key then (actual, bytes) else (actual, value))
sha :: Text -> Text
sha = Text.replicate 64
one :: [value] -> IO value
one [value] = pure value
one _ = assertFailure "ordinary fixture requires exactly one value" >> fail "cardinality"
right :: (Show error) => Either error value -> IO value
right (Right value) = pure value
right (Left reason) = assertFailure (show reason) >> fail "ordinary fixture"
reject :: (Show value) => Either Text value -> Assertion
reject (Left _) = pure ()
reject (Right value) = assertFailure ("ordinary invalid recorded DATA accepted: " <> show value)
rejectContains :: (Show value) => Text -> Either Text value -> Assertion
rejectContains expected value = case value of
  Left reason -> assertBool (Text.unpack reason) (expected `Text.isInfixOf` reason)
  Right actual -> assertFailure ("ordinary invalid recorded DATA accepted: " <> show actual)
