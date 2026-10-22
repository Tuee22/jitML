{-# LANGUAGE OverloadedStrings #-}

-- The pooled fixture uses an existing physically admitted SL contract fixture
-- only to obtain real immutable manifest/completion DATA. Its native receipt
-- references below are ordinary DATA, not native execution/qualification caps.
module NativeQualificationGc (nativeQualificationGcTests) where

import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.List (sort)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word8)
import System.Directory
  ( createDirectoryIfMissing
  , createDirectoryLink
  , createFileLink
  , listDirectory
  )
import System.FilePath (takeDirectory, (</>))
import System.IO (IOMode (WriteMode), hSetFileSize, withBinaryFile)
import System.IO.Temp (withSystemTempDirectory)
import System.Timeout (timeout)
import Test.Tasty (TestTree, testGroup, withResource)
import Test.Tasty.HUnit (Assertion, assertBool, assertEqual, assertFailure, testCase)

import JitML.Checkpoint.Format qualified as Format
import JitML.Checkpoint.NativePhase.Context qualified as Context
import JitML.Checkpoint.NativePhase.Types (Digest, hashBytes)
import JitML.Checkpoint.NativeQualificationGc qualified as Gc
import JitML.Checkpoint.NativeQualificationReceiptData qualified as Metadata
import JitML.Checkpoint.NativeReplayObjectData qualified as Replay
import JitML.Checkpoint.NativeRetention qualified as Retain
import JitML.Checkpoint.Store qualified as Store
import JitML.Plan.Plan qualified as Plan
import JitML.Product.SourceDigest qualified as Source
import JitML.Product.ValidationRecord (sha256Hex)
import JitML.Service.FilesystemMinIO (runFilesystemMinIO)
import JitML.Substrate (Substrate (LinuxCPU))
import JitML.Test.ContractFixtures qualified as Fixtures
import JitML.Training.Budget qualified as Training

data Fixture = Fixture
  { fixtureManifest :: Format.CheckpointManifest
  , fixtureFields :: Metadata.NativeQualificationReceiptFields
  , fixtureObject :: (Text, BS.ByteString)
  }

nativeQualificationGcTests :: TestTree
nativeQualificationGcTests = withResource acquire (const (pure ())) $ \getFixture ->
  testGroup
    "native qualification GC reachability DATA"
    [ testCase "live metadata retains its allocation ordered phases and all eleven replay objects" $ do
        f <- getFixture
        actual <- refine f [fixtureObject f]
        assertEqual
          "all fifteen exact physical names"
          (expectedKeys f)
          (Gc.nativeGcProtectedObjectKeys actual)
        assertEqual
          "selected metadata itself is retained"
          [fst (fixtureObject f)]
          (Gc.nativeGcSelectedMetadataKeys actual)
    , testCase "distinct metadata for one live manifest contributes a deterministic union" $ do
        f <- getFixture
        second <- objectFor ((fixtureFields f) {Metadata.nativeReceiptRow = "another-ordinary-DATA-label"})
        forward <- refine f [fixtureObject f, second]
        backward <- refine f [second, fixtureObject f]
        assertEqual "input order does not alter the closure" forward backward
        assertEqual
          "both content addresses retained"
          (sort [fst (fixtureObject f), fst second])
          (Gc.nativeGcSelectedMetadataKeys forward)
        assertEqual
          "only one shared ordinary dependency set"
          16
          (length (Gc.nativeGcProtectedObjectKeys forward))
    , testCase "valid metadata for a nonlive manifest confers no protection" $ do
        f <- getFixture
        value <- right (Gc.refineNativeQualificationGcReachability (experiment f) [] [fixtureObject f])
        assertEqual "no live anchor" [] (Gc.nativeGcProtectedObjectKeys value)
        assertEqual "no selected object" [] (Gc.nativeGcSelectedMetadataKeys value)
    , testCase "a malformed relevant object refuses even with no live manifests" $ do
        f <- getFixture
        let bytes = BS.pack [0, 255]
        key <- metadataKey (experiment f) bytes
        rejects (Gc.refineNativeQualificationGcReachability (experiment f) [] [(key, bytes)])
    , testCase "actual physical SHA mismatch refuses before canonical body decoding" $ do
        f <- getFixture
        let (key, bytes) = fixtureObject f
        rejectsReason
          "native GC metadata physical SHA differs from its exact key"
          ( Gc.refineNativeQualificationGcReachability
              (experiment f)
              [fixtureManifest f]
              [(key, bytes <> BS.singleton 0)]
          )
    , testCase "closed metadata namespace extension and digest spelling must match" $ do
        f <- getFixture
        let (key, bytes) = fixtureObject f
        mapM_
          ( \bad ->
              rejects
                (Gc.refineNativeQualificationGcReachability (experiment f) [fixtureManifest f] [(bad, bytes)])
          )
          [ Text.replace "/native-qualification/" "/native-evaluation-replay/" key
          , Text.dropEnd 5 key <> ".json"
          , key <> "/extra"
          , Text.replace "/artifacts/" "/../artifacts/" key
          , Text.replace (sha256Hex bytes) (Text.replicate 64 "A") key
          ]
    , testCase "duplicate physical metadata inputs refuse rather than silently disappear" $ do
        f <- getFixture
        rejectsReason
          "native GC metadata object is duplicated"
          ( Gc.refineNativeQualificationGcReachability
              (experiment f)
              [fixtureManifest f]
              [fixtureObject f, fixtureObject f]
          )
    , testCase "valid metadata with different whole completion bytes refuses at the live anchor" $ do
        f <- getFixture
        changed <-
          objectFor
            ( (fixtureFields f)
                { Metadata.nativeReceiptCompletedTrainingBytes = "different opaque completion DATA"
                }
            )
        rejectsReason
          "native GC metadata whole completion differs from its live manifest"
          (Gc.refineNativeQualificationGcReachability (experiment f) [fixtureManifest f] [changed])
    , testCase "valid metadata with another whole plan refuses without relabeling the compiled plan" $ do
        f <- getFixture
        changed <- objectFor ((fixtureFields f) {Metadata.nativeReceiptWholePlan = dig 220})
        rejectsReason
          "native GC metadata whole plan differs from its live manifest"
          (Gc.refineNativeQualificationGcReachability (experiment f) [fixtureManifest f] [changed])
    , testCase "foreign live manifest experiment refuses before any metadata is needed" $ do
        f <- getFixture
        rejectsReason
          "native GC live manifest belongs to another experiment"
          ( Gc.refineNativeQualificationGcReachability
              (experiment f)
              [(fixtureManifest f) {Format.manifestExperiment = "another-experiment"}]
              []
          )
    , testCase "a live manifest without completion cannot use opaque metadata as an admission substitute" $ do
        f <- getFixture
        let manifest = (fixtureManifest f) {Format.manifestCompletedTraining = Nothing}
        -- The content-addressed manifest changed, so bind the ordinary label to
        -- that actual changed manifest instead of borrowing its old address.
        digest <- right (Context.digestFromCanonicalText (Format.manifestContentSha manifest))
        object <- objectFor ((fixtureFields f) {Metadata.nativeReceiptManifest = digest})
        rejectsReason
          "native GC live native receipt has no completed training"
          (Gc.refineNativeQualificationGcReachability (experiment f) [manifest] [object])
    , testCase "all128 ordered phase names remain reachable with all eleven replay names" $ do
        f <- getFixture
        let fields = (fixtureFields f) {Metadata.nativeReceiptPhases = map phase [0 .. 127]}
        object <- objectFor fields
        value <- refine f [object]
        assertEqual
          "metadata allocation128phases11replays"
          141
          (length (Gc.nativeGcProtectedObjectKeys value))
        assertBool
          "every original phase remains"
          ( all
              ((`elem` Gc.nativeGcProtectedObjectKeys value) . Retain.nativeRetainedObjectKey)
              (Metadata.nativeReceiptPhases fields)
          )
    , testCase "four MiB plus one ordinary bytes refuse before hashing or decoding" $ do
        f <- getFixture
        rejectsReason
          "native GC metadata exceeds its four MiB bound"
          ( Gc.refineNativeQualificationGcReachability
              (experiment f)
              [fixtureManifest f]
              [(fst (fixtureObject f), BS.replicate (4 * 1024 * 1024 + 1) 0)]
          )
    , testCase
        "empty additional protection preserves the exact original plan including validation failures"
        $ assertEqual "literal old path" (Right samplePlan) (Store.protectGcPlanObjectKeys [] samplePlan)
    , testCase "additional protection filters exact object keys and preserves all other plan DATA" $ do
        let protected = "jitml-checkpoints/gc-DATA/weights/keep.bin"
        actual <- right (Store.protectGcPlanObjectKeys [protected, protected] samplePlan)
        assertEqual
          "all other plan fields and event order"
          ( samplePlan
              { Store.gcReapEvents =
                  map
                    (\event -> event {Store.gcReapedObjectKeys = filter (/= protected) (Store.gcReapedObjectKeys event)})
                    (Store.gcReapEvents samplePlan)
              }
          )
          actual
    , testCase "invalid protected full keys fail closed instead of poisoning the plan" $
        mapM_
          (\key -> rejects (Store.protectGcPlanObjectKeys [key] samplePlan))
          [ "gc-DATA/weights/keep.bin"
          , "jitml-checkpoints/gc-DATA/../keep.bin"
          , "/jitml-checkpoints/gc-DATA/keep.bin"
          , "jitml-checkpoints/gc-DATA//keep.bin"
          , "jitml-checkpoints/gc-DATA/gc/commit.cbor"
          ]
    , testCase "kept manifest expansion uses exactly the existing plan SHA selection" $ do
        f <- getFixture
        let manifest = fixtureManifest f
            other = manifest {Format.manifestStep = Format.manifestStep manifest + 1}
            plan = samplePlan {Store.gcKeptManifestShas = [Format.manifestContentSha manifest]}
        assertEqual
          "duplicate input canonicalization and exact membership"
          [manifest]
          (Gc.nativeGcKeptManifests [other, manifest, manifest] plan)
    , testCase "missing local closed prefix gives empty reachability without creating it" $ do
        f <- getFixture
        withSystemTempDirectory "jitml-native-gc-missing" $ \root -> do
          value <-
            right =<< Gc.loadLocalNativeQualificationGcReachability root (experiment f) [fixtureManifest f]
          assertEqual "no new ordinary keys" [] (Gc.nativeGcProtectedObjectKeys value)
          assertEqual "read-only missing route" [] =<< listDirectory root
    , testCase "real local metadata bytes produce the same closure without writes or deletion" $ do
        f <- getFixture
        withSystemTempDirectory "jitml-native-gc-local" $ \root -> do
          path <- writeObject root (fixtureObject f)
          before <- BS.readFile path
          expected <- refine f [fixtureObject f]
          actual <-
            right =<< Gc.loadLocalNativeQualificationGcReachability root (experiment f) [fixtureManifest f]
          assertEqual "physical local result" expected actual
          assertEqual "unchanged original object bytes" before =<< BS.readFile path
    , testCase "multiple real local objects retain their exact distinct metadata addresses" $ do
        f <- getFixture
        second <-
          objectFor ((fixtureFields f) {Metadata.nativeReceiptCohortTransport = "another opaque cohort DATA"})
        withSystemTempDirectory "jitml-native-gc-multiple" $ \root -> do
          _ <- writeObject root second
          _ <- writeObject root (fixtureObject f)
          expected <- refine f [second, fixtureObject f]
          actual <-
            right =<< Gc.loadLocalNativeQualificationGcReachability root (experiment f) [fixtureManifest f]
          assertEqual "same sorted union" expected actual
    , testCase "local invalid filename refuses before body parsing" $ do
        f <- getFixture
        withSystemTempDirectory "jitml-native-gc-name" $ \root -> do
          let key = Text.dropEnd 69 (fst (fixtureObject f)) <> "bad.cbor"
          path <- right (Store.objectPathForKey root key)
          createDirectoryIfMissing True (takeDirectory path)
          BS.writeFile path BS.empty
          rejects =<< Gc.loadLocalNativeQualificationGcReachability root (experiment f) [fixtureManifest f]
    , testCase "local corruption refuses against the actual content-addressed filename" $ do
        f <- getFixture
        withSystemTempDirectory "jitml-native-gc-corrupt" $ \root -> do
          path <- writeObject root (fixtureObject f)
          BS.appendFile path (BS.singleton 0)
          rejectsReason "native GC metadata physical SHA differs from its exact key"
            =<< Gc.loadLocalNativeQualificationGcReachability root (experiment f) [fixtureManifest f]
    , testCase "a sparse one GiB object is refused after the bounded four MiB plus one read" $ do
        f <- getFixture
        withSystemTempDirectory "jitml-native-gc-sparse" $ \root -> do
          path <- right (Store.objectPathForKey root (fst (fixtureObject f)))
          createDirectoryIfMissing True (takeDirectory path)
          withBinaryFile path WriteMode $ \handle -> hSetFileSize handle (1024 * 1024 * 1024)
          completed <-
            timeout
              10000000
              (Gc.loadLocalNativeQualificationGcReachability root (experiment f) [fixtureManifest f])
          case completed of
            Just actual -> rejectsReason "native GC metadata exceeds its four MiB bound" actual
            Nothing -> assertFailure "bounded local sparse read did not finish"
    , testCase "local metadata object symlinks are refused without following their body" $ do
        f <- getFixture
        withSystemTempDirectory "jitml-native-gc-symlink" $ \root -> do
          let target = root </> "outside-DATA.cbor"
          BS.writeFile target (snd (fixtureObject f))
          path <- right (Store.objectPathForKey root (fst (fixtureObject f)))
          createDirectoryIfMissing True (takeDirectory path)
          createFileLink target path
          rejectsReason "native GC metadata object is not a regular non-symlink file"
            =<< Gc.loadLocalNativeQualificationGcReachability root (experiment f) [fixtureManifest f]
    , testCase "local closed-prefix symlinks are refused as a separate directory boundary" $ do
        f <- getFixture
        withSystemTempDirectory "jitml-native-gc-dirlink" $ \root -> do
          path <- right (Store.objectPathForKey root (fst (fixtureObject f)))
          let directory = takeDirectory path
              target = root </> "outside-DATA"
          createDirectoryIfMissing True target
          createDirectoryIfMissing True (takeDirectory directory)
          createDirectoryLink target directory
          rejectsReason "native GC metadata directory is a symlink"
            =<< Gc.loadLocalNativeQualificationGcReachability root (experiment f) [fixtureManifest f]
    , testCase "filesystem HasMinIO listing and byte fetch agree with the local closure" $ do
        f <- getFixture
        withSystemTempDirectory "jitml-native-gc-minio" $ \root -> do
          path <- writeObject root (fixtureObject f)
          before <- BS.readFile path
          expected <- refine f [fixtureObject f]
          actual <-
            right
              =<< runFilesystemMinIO
                root
                (Gc.loadNativeQualificationGcReachability (experiment f) [fixtureManifest f])
          assertEqual "real filesystem adapter only no network allocation claim" expected actual
          assertEqual "the adapter did not rewrite metadata" before =<< BS.readFile path
    , testCase "filesystem HasMinIO refuses a corrupt relevant body even without live metadata" $ do
        f <- getFixture
        withSystemTempDirectory "jitml-native-gc-minio-corrupt" $ \root -> do
          path <- writeObject root (fixtureObject f)
          BS.writeFile path "not canonical metadata"
          rejects =<< runFilesystemMinIO root (Gc.loadNativeQualificationGcReachability (experiment f) [])
    , testCase "filesystem HasMinIO refuses foreign nested names within the closed prefix" $ do
        f <- getFixture
        withSystemTempDirectory "jitml-native-gc-minio-nested" $ \root -> do
          path <- right (Store.objectPathForKey root (fst (fixtureObject f) <> "/nested"))
          createDirectoryIfMissing True (takeDirectory path)
          BS.writeFile path BS.empty
          rejects
            =<< runFilesystemMinIO
              root
              (Gc.loadNativeQualificationGcReachability (experiment f) [fixtureManifest f])
    , testCase "a dangling local metadata-prefix symlink refuses rather than becoming an empty inventory" $ do
        f <- getFixture
        withSystemTempDirectory "jitml-native-gc-dangling" $ \root -> do
          path <- right (Store.objectPathForKey root (fst (fixtureObject f)))
          let directory = takeDirectory path
              absentTarget = root </> "absent-target-DATA"
          createDirectoryIfMissing True (takeDirectory directory)
          createDirectoryLink absentTarget directory
          rejectsReason "native GC metadata directory is a symlink"
            =<< Gc.loadLocalNativeQualificationGcReachability root (experiment f) [fixtureManifest f]
    , testCase "the complete141-key closure protects every derived address through the Store plan seam" $ do
        f <- getFixture
        object <- objectFor ((fixtureFields f) {Metadata.nativeReceiptPhases = map phase [0 .. 127]})
        closure <- refine f [object]
        let protected = Gc.nativeGcProtectedObjectKeys closure
            other = "jitml-checkpoints/ordinary-GC-DATA/weights/independent.bin"
            event = Store.GcEvent "ordinary-reaped-DATA" (protected <> [other]) (experiment f) 1
            plan = Store.GcPlan [Format.manifestContentSha (fixtureManifest f)] [event] [] False
        assertEqual "all141 prescribed physical addresses" 141 (length protected)
        actual <- right (Store.protectGcPlanObjectKeys protected plan)
        assertEqual
          "only unrelated candidate remains and every other plan field is exact"
          (plan {Store.gcReapEvents = [event {Store.gcReapedObjectKeys = [other]}]})
          actual
    ]

acquire :: IO Fixture
acquire = Fixtures.withAdmittedProductProjection $ \_ _ _ _ _ admitted -> do
  let manifest = Store.admittedCheckpointManifest (Store.admittedCompletedCheckpoint admitted)
      completed = Store.admittedCompletedTraining admitted
      experimentHash = Format.manifestExperiment manifest
  whole <-
    right
      (Context.digestFromCanonicalText (Plan.planIdText (Training.completedTrainingPlanId completed)))
  manifestDigest <- right (Context.digestFromCanonicalText (Format.manifestContentSha manifest))
  let fields =
        Metadata.NativeQualificationReceiptFields
          "ordinary-GC-contract-DATA"
          LinuxCPU
          whole
          experimentHash
          (dig 2)
          "opaque ordinary cohort DATA not a canonical native cohort"
          manifestDigest
          (Training.encodeCompletedTraining completed)
          publication
          (Metadata.NativeReceiptDirectData (dig 3))
          (Just stamp)
          (Just stamp)
          allocation
          [phase 1, phase 2]
          (replays experimentHash)
  object <- objectFor fields
  pure (Fixture manifest fields object)

experiment :: Fixture -> Text
experiment = Format.manifestExperiment . fixtureManifest

refine :: Fixture -> [(Text, BS.ByteString)] -> IO Gc.NativeQualificationGcReachability
refine f objects = right (Gc.refineNativeQualificationGcReachability (experiment f) [fixtureManifest f] objects)

expectedKeys :: Fixture -> [Text]
expectedKeys f =
  Set.toAscList (Set.fromList (fst (fixtureObject f) : map Retain.nativeRetainedObjectKey references))
 where
  fields = fixtureFields f
  references =
    Metadata.nativeReceiptAllocation fields
      : Metadata.nativeReceiptPhases fields
        <> map Metadata.nativeReceiptReplayObject (Metadata.nativeReceiptReplays fields)

objectFor :: Metadata.NativeQualificationReceiptFields -> IO (Text, BS.ByteString)
objectFor fields = do
  value <- right (Metadata.refineNativeQualificationReceiptData fields)
  let bytes = Metadata.nativeQualificationReceiptBytes value
  key <- metadataKey (Metadata.nativeReceiptExperiment fields) bytes
  pure (key, bytes)

metadataKey :: Text -> BS.ByteString -> IO Text
metadataKey experimentHash bytes =
  right
    (Retain.nativeDetachedArtifactKey Retain.NativeQualificationArtifact experimentHash (sha256Hex bytes))

writeObject :: FilePath -> (Text, BS.ByteString) -> IO FilePath
writeObject root (key, bytes) = do
  _ <- right =<< Store.writeObjectIfAbsent root key (BL.fromStrict bytes)
  right (Store.objectPathForKey root key)

publication :: Retain.NativePublicationData
publication = Retain.NativeLocalPublication Retain.NativeDefaultPublicationResolution (hashId 1)
stamp :: Source.SourceStamp
stamp = Source.SourceStamp Source.sourceDigestAlgorithm (hashId 2)
scope :: Text
scope = hashId 3
allocation :: Retain.NativeRetainedObjectData
allocation =
  Retain.NativeRetainedObjectData
    ("jitml-checkpoints/native-rl-allocations-v1/" <> scope <> "/claim.cbor")
    (hashId 4)
    256
    publication
phase :: Word8 -> Retain.NativeRetainedObjectData
phase n =
  Retain.NativeRetainedObjectData
    ("jitml-checkpoints/native-rl-allocations-v1/" <> scope <> "/phases/" <> hashId n <> ".cbor")
    (hashId n)
    256
    publication

-- Keep this exact base-only list traversal; no extra dependency for the hint.
{- HLINT ignore replays "Use zipWithFrom" -}
replays :: Text -> [Metadata.NativeReceiptReplayReference]
replays experimentHash =
  zipWith
    entry
    [20 ..]
    ( concatMap
        (\index -> [(Replay.InitialModelReplay, index), (Replay.FinalModelReplay, index)])
        [0 .. 4]
        <> [(Replay.StoredFinalModelReplay, 0)]
    )
 where
  entry n (stage, index) =
    let kind =
          if stage == Replay.StoredFinalModelReplay
            then Retain.NativeStoreLoadedReplayArtifact
            else Retain.NativeEvaluationReplayArtifact
        sha = hashId n
        key = either (error . show) id (Retain.nativeDetachedArtifactKey kind experimentHash sha)
     in Metadata.NativeReceiptReplayReference
          stage
          index
          (dig (10 + fromIntegral index))
          (Retain.NativeRetainedObjectData key sha 256 publication)
dig :: Word8 -> Digest
dig = hashBytes . BS.singleton
hashId :: Word8 -> Text
hashId = sha256Hex . BS.singleton

samplePlan :: Store.GcPlan
samplePlan =
  Store.GcPlan
    ["ordinary-kept-sha"]
    [ Store.GcEvent
        "ordinary-reaped-one"
        ["jitml-checkpoints/gc-DATA/weights/keep.bin", "jitml-checkpoints/gc-DATA/weights/reap.bin"]
        "gc-DATA"
        1
    , Store.GcEvent "ordinary-reaped-two" ["jitml-checkpoints/gc-DATA/weights/keep.bin"] "gc-DATA" 2
    ]
    ["ordinary preexisting validation failure"]
    False

right :: (Show e) => Either e a -> IO a
right result = case result of
  Right value -> pure value
  Left failure -> assertFailure (show failure) >> fail "unreachable"
rejects :: (Show e) => Either e a -> Assertion
rejects result = case result of Left _ -> pure (); Right _ -> assertFailure "invalid ordinary GC DATA accepted"
rejectsReason :: Text -> Either Text a -> Assertion
rejectsReason reason result = case result of
  Left actual -> assertEqual "exact refusal" reason actual
  Right _ -> assertFailure "invalid ordinary GC DATA accepted"
