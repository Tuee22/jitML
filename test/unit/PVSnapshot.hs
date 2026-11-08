{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- Clean-checkout protocol tests with authored ordinary metadata; no live data.
module PVSnapshot (tests) where

import Control.Exception (AsyncException (ThreadKilled), SomeException, bracket_, throwIO, try)
import Control.Monad (unless)
import Data.Aeson (Value (..), eitherDecodeStrict', encode, object, (.=))
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Either (isLeft)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef, writeIORef)
import Data.List (mapAccumL)
import Data.Text (Text)
import Data.Vector qualified as Vector
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

import JitML.Cluster.PVSnapshot
import JitML.Cluster.PVSnapshotDocker (validateColdSnapshotNode, validateSnapshotHelperResources)
import PVSnapshotFixture (restoredManifest, sourceManifest)

tests :: TestTree
tests =
  let before = sourceManifest
      after = sourceManifest
      scratch = restoredManifest
      raw = NodeCandidate oldNode "generations/new-generation/worker.pax" digest before after scratch
      request = SnapshotRequest "linux-cpu" "jitml-linux-cpu" [oldNode] roots
      changed = raw {candidateAfter = editFirstFile "uid" (Number 12345) after}
      badRestore = raw {candidateScratch = editFirstFile "mtime_ns" (Number 0) scratch}
   in testMain request raw changed badRestore

testMain :: SnapshotRequest -> NodeCandidate -> NodeCandidate -> NodeCandidate -> TestTree
testMain request raw changed badRestore =
  testGroup
    "node-local PV durable lifecycle protocol"
    [ testCase "authored scratch fixture preserves portable tree; identity is separate" $ do
        left <- right (decodeTreeManifest request (candidateBefore raw))
        rightTree <- right (decodeTreeManifest request (candidateScratch raw))
        assertBool "source physical identities differ from scratch" (left /= rightTree)
        assertBool "full portable metadata/content matches" (sameRestoredTree left rightTree)
    , testCase "authored source fixture before/after stays full-identity exact" $ do
        left <- right (decodeTreeManifest request (candidateBefore raw))
        rightTree <- right (decodeTreeManifest request (candidateAfter raw))
        left @?= rightTree
    , testCase "snapshot codec roundtrip retains original manifest bytes" $ do
        let selected = selection request raw
        decodeSelection (encodeSelection selected) @?= Right selected
    , testCase "source changed after archive: no commit/delete, prior selection retained" $ do
        fixture <- setup request changed
        expectFailure (preserveBeforeDelete (backend fixture) (store fixture) request (delete fixture))
        readIORef (current fixture) >>= (@?= Just (oldSelection fixture))
        readIORef (events fixture) >>= (@?= ["quiesce", "capture", "release"])
    , testCase "scratch mtime mismatch: no commit/delete, original selection retained" $ do
        fixture <- setup request badRestore
        expectFailure (preserveBeforeDelete (backend fixture) (store fixture) request (delete fixture))
        readIORef (current fixture) >>= (@?= Just (oldSelection fixture))
        readIORef (events fixture) >>= (@?= ["quiesce", "capture", "release"])
    , testCase "cancellation while capturing: no deletion, compensation boundary reached" $ do
        fixture <- setup request raw
        let cancelled = (backend fixture) {captureAndScratchRestore = \_ _ -> throwIO ThreadKilled}
        result <-
          try (preserveBeforeDelete cancelled (store fixture) request (delete fixture))
            :: IO (Either AsyncException VerifiedSnapshot)
        case result of Left ThreadKilled -> pure (); _ -> fail "first async exception lost"
        readIORef (current fixture) >>= (@?= Just (oldSelection fixture))
        readIORef (events fixture) >>= (@?= ["quiesce", "release"])
    , testCase "ENOSPC-like staging failure: old selection and cluster retained" $ do
        fixture <- setup request raw
        let broken = (store fixture) {stageGeneration = \_ _ -> fail "ENOSPC injected"}
        expectFailure (preserveBeforeDelete (backend fixture) broken request (delete fixture))
        readIORef (current fixture) >>= (@?= Just (oldSelection fixture))
        readIORef (events fixture) >>= (@?= ["quiesce", "capture", "release"])
    , testCase "commit CAS failure never reaches Kind delete" $ do
        fixture <- setup request raw
        let broken = (store fixture) {commitSelection = \_ _ -> fail "selection changed"}
        expectFailure (preserveBeforeDelete (backend fixture) broken request (delete fixture))
        readIORef (current fixture) >>= (@?= Just (oldSelection fixture))
        readIORef (events fixture) >>= (@?= ["quiesce", "capture", "stage", "revalidate", "release"])
    , testCase "verified commit precedes sole delete while writers remain quiesced" $ do
        fixture <- setup request raw
        accepted <- preserveBeforeDelete (backend fixture) (store fixture) request (delete fixture)
        readIORef (current fixture) >>= (@?= Just (verifiedSelection accepted))
        readIORef (events fixture)
          >>= (@?= ["quiesce", "capture", "stage", "revalidate", "commit", "delete", "release"])
    , testCase "delete failure retains NEW snapshot, never rolls back to stale data" $ do
        fixture <- setup request raw
        expectFailure
          (preserveBeforeDelete (backend fixture) (store fixture) request (\_ -> fail "Kind delete uncertain"))
        readIORef (current fixture) >>= (@?= Just (selection request raw))
    , testCase "fresh node CID is role-mapped; portable metadata checked before mount" $ do
        fixture <- setup request raw
        writeIORef (current fixture) (Just (selection request raw))
        outcome <-
          restoreBeforeMounts (backend fixture) (store fixture) (request {snapshotNodes = [newNode]})
        outcome @?= RestoredSnapshot "new-generation"
        readIORef (events fixture) >>= (@?= ["empty-roots", "verify-archive", "restore-new-cid"])
    , testCase "nonempty current root refuses extraction with no overwrite" $ do
        fixture <- setup request raw
        let nonempty = (backend fixture) {requireFreshEmptyRoots = \_ -> fail "nonempty retained root"}
        expectFailure (restoreBeforeMounts nonempty (store fixture) request)
        readIORef (events fixture) >>= (@?= [])
    , testCase "corrupt selected archive refuses extraction" $ do
        fixture <- setup request raw
        let corrupt = (backend fixture) {verifySelectedArchive = \_ -> fail "archive SHA mismatch"}
        expectFailure (restoreBeforeMounts corrupt (store fixture) request)
        readIORef (events fixture) >>= (@?= ["empty-roots"])
    , testCase "registry change refuses restore instead of merging arbitrary paths" $ do
        fixture <- setup request raw
        expectFailure
          (restoreBeforeMounts (backend fixture) (store fixture) (request {registeredRoots = ["other/pv_0"]}))
        readIORef (events fixture) >>= (@?= [])
    , testCase "purge invalidates selection; retained generations cannot auto-resurrect" $ do
        fixture <- setup request raw
        invalidateForPurge (store fixture)
        outcome <- restoreBeforeMounts (backend fixture) (store fixture) request
        outcome @?= NoSelectedSnapshot
        readIORef (events fixture) >>= (@?= ["invalidate"])
    , snapshotHelperResourceTests
    , coldSnapshotNodeTests
    ]

coldSnapshotNodeTests :: TestTree
coldSnapshotNodeTests =
  testGroup
    "cold snapshot physical source admission"
    [ testCase "exact full source CID and stopped physical state pass" $
        validateColdSnapshotNode expected stopped @?= Right ()
    , testCase "running paused restarting and nonzero PID refuse independently" $
        mapM_
          rejected
          [ stateField "Running" (Bool True)
          , stateField "Paused" (Bool True)
          , stateField "Restarting" (Bool True)
          , stateField "Pid" (Number 42)
          , stateField "Pid" (Number (-1))
          ]
    , testCase "stopped replacement and shortened source CID refuse" $ do
        rejected
          (case stopped of Object value -> Object (KM.insert "Id" (String otherCID) value); _ -> Null)
        assertBool "short expected CID accepted" (isLeft (validateColdSnapshotNode "abcd" stopped))
    , testCase "all physical state fields are mandatory with real API types" $
        mapM_
          rejected
          [ object []
          , object ["Id" .= expected, "State" .= object []]
          , stateField "Running" (String "false")
          , stateField "Paused" Null
          , stateField "Restarting" (Number 0)
          , stateField "Pid" (String "0")
          , stateField "Pid" (Number 0.5)
          ]
    ]
 where
  expected = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  otherCID = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  stopped =
    object
      [ "Id" .= (expected :: Text)
      , "State"
          .= object
            [ "Running" .= False
            , "Paused" .= False
            , "Restarting" .= False
            , "Pid" .= (0 :: Integer)
            ]
      ]
  stateField key replacement = case stopped of
    Object value -> case KM.lookup "State" value of
      Just (Object state) -> Object (KM.insert "State" (Object (KM.insert key replacement state)) value)
      _ -> Null
    _ -> Null
  rejected value =
    assertBool "unsafe cold source state accepted" (isLeft (validateColdSnapshotNode expected value))

-- Authored Docker inspection metadata exercises refusal of absent/unlimited
-- bounds. No Docker runner, source program, live volume or CLI-argv mirror is
-- involved in these resource-admission cases.
snapshotHelperResourceTests :: TestTree
snapshotHelperResourceTests =
  testGroup
    "snapshot helper resource admission"
    [ testCase "fixed observed bounds pass independent of tmpfs option order" $ do
        validateSnapshotHelperResources helperInspection @?= Right ()
        validateSnapshotHelperResources
          (hostField "Tmpfs" (object ["/tmp" .= ("size=67108864,nodev,rw,nosuid" :: Text)]))
          @?= Right ()
    , testCase "missing or changed memory and CPU bounds refuse before helper start" $
        mapM_
          rejectedHelper
          [ hostField "Memory" (Number 0)
          , hostField "Memory" (Number 1073741824)
          , hostField "Memory" (Number 268435456)
          , hostField "NanoCpus" (Number 0)
          , hostField "NanoCpus" (Number 1000000000)
          ]
    , testCase "swap and unlimited or changed process allowances refuse" $
        mapM_
          rejectedHelper
          [ hostField "MemorySwap" (Number (-1))
          , hostField "MemorySwap" (Number 0)
          , hostField "MemorySwap" (Number 1073741824)
          , hostField "PidsLimit" (Number 0)
          , hostField "PidsLimit" (Number (-1))
          , hostField "PidsLimit" (Number 128)
          ]
    , testCase "unbounded enlarged or additional tmpfs mounts refuse" $
        mapM_
          rejectedHelper
          [ hostField "Tmpfs" (object ["/tmp" .= ("rw,nosuid,nodev" :: Text)])
          , hostField "Tmpfs" (object ["/tmp" .= ("rw,nosuid,nodev,size=134217728" :: Text)])
          , hostField
              "Tmpfs"
              (object ["/tmp" .= ("rw,nosuid,nodev,size=67108864" :: Text), "/extra" .= ("rw" :: Text)])
          , hostField "Tmpfs" (object ["/tmp" .= ("rw,nosuid,nodev,size=67108864,size=67108864" :: Text)])
          ]
    , testCase "mandatory inspection fields must have their real API types" $
        mapM_
          rejectedHelper
          [ object []
          , object ["HostConfig" .= object []]
          , hostField "Memory" Null
          , hostField "Memory" (String "536870912")
          , hostField "NanoCpus" (Number 500000000.5)
          , hostField "PidsLimit" (Bool False)
          , hostField "Tmpfs" (String "rw,size=67108864")
          ]
    ]
 where
  rejectedHelper value =
    assertBool
      "unbounded or malformed helper configuration was accepted"
      (isLeft (validateSnapshotHelperResources value))

helperInspection :: Value
helperInspection =
  object
    [ "HostConfig"
        .= object
          [ "Memory" .= (536870912 :: Integer)
          , "MemorySwap" .= (536870912 :: Integer)
          , "NanoCpus" .= (500000000 :: Integer)
          , "PidsLimit" .= (64 :: Integer)
          , "Tmpfs" .= object ["/tmp" .= ("rw,nosuid,nodev,size=67108864" :: Text)]
          ]
    ]

hostField :: Key.Key -> Value -> Value
hostField key replacement = case helperInspection of
  Object outer -> case KM.lookup "HostConfig" outer of
    Just (Object host) -> Object (KM.insert "HostConfig" (Object (KM.insert key replacement host)) outer)
    _ -> Null
  _ -> Null

data Fixture = Fixture
  { backend :: SnapshotBackend
  , store :: SnapshotStore
  , events :: IORef [Text]
  , current :: IORef (Maybe SnapshotSelection)
  , oldSelection :: SnapshotSelection
  , delete :: SnapshotRequest -> IO ()
  }

setup :: SnapshotRequest -> NodeCandidate -> IO Fixture
setup request raw = do
  logRef <- newIORef []
  let note event = modifyIORef' logRef (<> [event])
      previous =
        (selection request raw)
          { selectionGeneration = "old-generation"
          , selectionNodes =
              [NodeSnapshot oldNode "generations/old-generation/worker.pax" digest (candidateBefore raw)]
          }
  selected <- newIORef (Just previous)
  let snapshotStore =
        SnapshotStore
          { withLifecycleLock = id
          , readSelection = readIORef selected
          , stageGeneration = \value nodes -> note "stage" >> pure (SnapshotSelection value "new-generation" nodes)
          , commitSelection = \expected value -> do
              actual <- readIORef selected
              unless (expected == actual) (fail "CAS failed")
              note "commit"
              writeIORef selected (Just value)
          , clearSelection = note "invalidate" >> writeIORef selected Nothing
          }
      snapshotBackend =
        SnapshotBackend
          { withQuiesced = \_ action -> bracket_ (note "quiesce") (note "release") action
          , captureAndScratchRestore = \_ _ -> note "capture" >> pure raw
          , revalidateSourceNodes = \_ _ -> note "revalidate"
          , requireFreshEmptyRoots = \_ -> note "empty-roots"
          , verifySelectedArchive = \_ -> note "verify-archive"
          , restoreNode = \node _ -> note ("restore-" <> nodeContainerId node) >> pure (candidateScratch raw)
          }
  pure (Fixture snapshotBackend snapshotStore logRef selected previous (\_ -> note "delete"))

selection :: SnapshotRequest -> NodeCandidate -> SnapshotSelection
selection request raw =
  SnapshotSelection
    request
    "new-generation"
    [NodeSnapshot oldNode "generations/new-generation/worker.pax" digest (candidateBefore raw)]

roots :: [Text]
roots =
  fmap
    ("jitml/.data/platform/" <>)
    [ "minio/pv_0"
    , "pulsar-bookie-journal/pv_0"
    , "pulsar-bookie-ledgers/pv_0"
    , "pulsar-zookeeper-data/pv_0"
    ]

oldNode, newNode :: NodeIdentity
oldNode = NodeIdentity "worker" "old-cid"
newNode = NodeIdentity "worker" "new-cid"

digest :: FileDigest
digest = FileDigest 12345 "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

right :: Either String a -> IO a
right = either fail pure

expectFailure :: IO a -> IO ()
expectFailure action = do
  result <- try action
  case result of Left (_ :: SomeException) -> pure (); Right _ -> fail "unexpected success"

editFirstFile :: Key.Key -> Value -> BS.ByteString -> BS.ByteString
editFirstFile key replacement bytes =
  case eitherDecodeStrict' bytes of
    Right (Object value) -> case KM.lookup "records" value of
      Just (Array rows) ->
        LBS.toStrict $
          encode $
            Object $
              KM.insert
                "records"
                (Array (Vector.fromList (snd (mapAccumL change False (Vector.toList rows)))))
                value
      _ -> error "fixture rows"
    _ -> error "fixture JSON"
 where
  change seen row@(Object fields)
    | not seen && KM.lookup "type" fields == Just (String "file") =
        (True, Object (KM.insert key replacement fields))
    | otherwise = (seen, row)
  change seen row = (seen, row)
