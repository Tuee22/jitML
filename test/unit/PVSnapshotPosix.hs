{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- Real temp-filesystem storage tests; no Docker or live state access.
module PVSnapshotPosix (tests) where

import Control.Concurrent (forkIO, newEmptyMVar, putMVar, takeMVar, threadDelay)
import Control.Exception (AsyncException (ThreadKilled), SomeException, throwIO, try)
import Control.Monad (void, (>=>))
import Crypto.Hash.SHA256 qualified as SHA
import Data.Aeson (object, (.=))
import Data.ByteString qualified as BS
import Data.IORef (newIORef, readIORef, writeIORef)
import Data.Text (Text)
import Data.Text qualified as Text
import Numeric (showHex)
import System.Directory
  ( canonicalizePath
  , createDirectory
  , doesFileExist
  , removeFile
  , renameDirectory
  )
import System.Exit (ExitCode (ExitSuccess))
import System.FilePath ((</>))
import System.IO (hClose)
import System.IO.Temp (withSystemTempDirectory)
import System.Posix.Files (createLink, createSymbolicLink, setFileMode)
import System.Posix.IO
  ( OpenMode (WriteOnly)
  , creat
  , defaultFileFlags
  , exclusive
  , fdToHandle
  , openFd
  )
import System.Posix.Process (ProcessStatus (Exited), exitImmediately, forkProcess, getProcessStatus)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

import JitML.Cluster.PVSnapshot
import JitML.Cluster.PVSnapshotPosix
import PVSnapshotFixture (sourceManifest)

tests :: TestTree
tests =
  let fixture = sourceManifest
   in testGroup
        "POSIX durable selection store (real temp filesystem)"
        [ testCase "reserve/stage/CAS/read exact immutable selection and archive" $ temporary $ \root ->
            withPosixLifecycle root $ \lease -> do
              handle <- fresh root lease "one"
              saved <- prepare root handle "one" fixture
              commitSelection (snapshotStore handle) Nothing saved
              readSelection (snapshotStore handle) >>= (@?= Just saved)
              verifyHostArchive handle (archive "one") payloadDigest
        , testCase "existing exclusive generation is refused, never resumed" $ temporary $ \root ->
            withPosixLifecycle root $ \lease -> do
              first <- fresh root lease "one"
              reserveOwnedGeneration first
              second <- fresh root lease "one"
              expectFailure (reserveOwnedGeneration second)
        , testCase "new capture token verifies OLD selected generation without substitution" $ temporary $ \root ->
            withPosixLifecycle root $ \lease -> do
              old <- fresh root lease "one"
              saved <- prepare root old "one" fixture
              commitSelection (snapshotStore old) Nothing saved
              new <- fresh root lease "two"
              readSelection (snapshotStore new) >>= (@?= Just saved)
              verifyHostArchive new (archive "one") payloadDigest
        , testCase "CAS mismatch leaves current bytes and original generation unchanged" $ temporary $ \root ->
            withPosixLifecycle root $ \lease -> do
              handle <- fresh root lease "one"
              saved <- prepare root handle "one" fixture
              commitSelection (snapshotStore handle) Nothing saved
              original <- BS.readFile (lane root </> "current.json")
              expectFailure (commitSelection (snapshotStore handle) Nothing saved)
              BS.readFile (lane root </> "current.json") >>= (@?= original)
              verifyHostArchive handle (archive "one") payloadDigest
        , testCase "archive tamper after staging refuses commit; no selection appears" $ temporary $ \root ->
            withPosixLifecycle root $ \lease -> do
              handle <- fresh root lease "one"
              saved <- prepare root handle "one" fixture
              BS.writeFile (lane root </> archive "one") "changed"
              expectFailure (commitSelection (snapshotStore handle) Nothing saved)
              readSelection (snapshotStore handle) >>= (@?= Nothing)
        , testCase "symlink ancestor is rejected before payload reservation" $ temporary $ \root -> do
            createDirectory (root </> "other")
            createSymbolicLink (root </> "other") (root </> ".data")
            withPosixLifecycle root $ \lease -> do
              handle <- fresh root lease "one"
              expectFailure (reserveOwnedGeneration handle)
        , testCase "archive symlink rejected without following it" $ temporary $ \root ->
            withPosixLifecycle root $ \lease -> do
              handle <- fresh root lease "one"
              reserveOwnedGeneration handle
              writePrivate (root </> "external") payload
              createSymbolicLink (root </> "external") (lane root </> archive "one")
              expectFailure (verifyHostArchive handle (archive "one") payloadDigest)
        , testCase "archive hardlink nlink2 and broad mode are independently rejected" $ temporary $ \root ->
            withPosixLifecycle root $ \lease -> do
              handle <- fresh root lease "one"
              reserveOwnedGeneration handle
              let path = lane root </> archive "one"
              writePrivate path payload
              createLink path (root </> "alias")
              expectFailure (verifyHostArchive handle (archive "one") payloadDigest)
              removeFile (root </> "alias")
              setFileMode path 0o644
              expectFailure (verifyHostArchive handle (archive "one") payloadDigest)
        , testCase "selected generation/manifest missing is corruption, not no selection" $ temporary $ \root ->
            withPosixLifecycle root $ \lease -> do
              handle <- fresh root lease "one"
              saved <- prepare root handle "one" fixture
              commitSelection (snapshotStore handle) Nothing saved
              removeFile (lane root </> "generations/one/worker.manifest.json")
              expectFailure (readSelection (snapshotStore handle))
        , testCase "absent selector does not scan or resurrect immutable generations" $ temporary $ \root ->
            withPosixLifecycle root $ \lease -> do
              handle <- fresh root lease "one"
              saved <- prepare root handle "one" fixture
              commitSelection (snapshotStore handle) Nothing saved
              removeFile (lane root </> "current.json")
              readSelection (snapshotStore handle) >>= (@?= Nothing)
        , testCase "corrupt selection fails closed, no fallback to a generation" $ temporary $ \root ->
            withPosixLifecycle root $ \lease -> do
              handle <- fresh root lease "one"
              _ <- prepare root handle "one" fixture
              writePrivate (lane root </> "current.json") "{broken"
              expectFailure (readSelection (snapshotStore handle))
        , testCase "archive path cannot escape/mismatch generation" $ temporary $ \root ->
            withPosixLifecycle root $ \lease -> do
              handle <- fresh root lease "one"
              reserveOwnedGeneration handle
              mapM_
                (\path -> expectFailure (verifyHostArchive handle path payloadDigest))
                ["../outside.pax", "generations/one/../worker.pax", "generations/one/worker.pax/extra"]
        , testCase "cancellation before stage leaves original selector and partial data" $ temporary $ \root ->
            withPosixLifecycle root $ \lease -> do
              handle <- fresh root lease "one"
              reserveOwnedGeneration handle
              result <-
                try (writePrivate (lane root </> archive "one") payload >> throwIO ThreadKilled)
                  :: IO (Either AsyncException ())
              case result of Left ThreadKilled -> pure (); _ -> fail "async failure lost"
              readSelection (snapshotStore handle) >>= (@?= Nothing)
              doesFileExist (lane root </> archive "one") >>= assertBool "partial payload was cleaned"
        , testCase "invalidation remains effective if stale selector survives purge failure" $ temporary $ \root ->
            withPosixLifecycle root $ \lease -> do
              handle <- fresh root lease "one"
              saved <- prepare root handle "one" fixture
              commitSelection (snapshotStore handle) Nothing saved
              original <- BS.readFile (lane root </> "current.json")
              clearSelection (snapshotStore handle)
              BS.writeFile (lane root </> "current.json") original
              readSelection (snapshotStore handle) >>= (@?= Nothing)
              verifyHostArchive handle (archive "one") payloadDigest
        , testCase "missing external epoch with surviving data is refused" $ temporary $ \root ->
            withPosixLifecycle root $ \lease -> do
              handle <- fresh root lease "one"
              saved <- prepare root handle "one" fixture
              commitSelection (snapshotStore handle) Nothing saved
              removeFile (root </> ".build/runtime/pv-snapshot-control/linux-cpu/epoch")
              expectFailure (readSelection (snapshotStore handle))
        , testCase "lease scope rejects wrong roots, expires and cannot cross threads" $ temporary $ \root -> do
            (escaped, oldLease) <- withPosixLifecycle root $ \lease -> do
              validateLifecycleScope lease root
              expectFailure (validateLifecycleScope lease (root </> "other"))
              handle <- fresh root lease "one"
              scopeDone <- newEmptyMVar
              void $ forkIO $ try (validateLifecycleScope lease root) >>= putMVar scopeDone
              scopeAttempted <- takeMVar scopeDone :: IO (Either SomeException ())
              case scopeAttempted of Left _ -> pure (); Right _ -> fail "cross-thread scope accepted"
              done <- newEmptyMVar
              void $ forkIO $ try (readSelection (snapshotStore handle)) >>= putMVar done
              attempted <- takeMVar done :: IO (Either SomeException (Maybe SnapshotSelection))
              case attempted of Left _ -> pure (); Right _ -> fail "cross-thread lease accepted"
              pure (handle, lease)
            expectFailure (validateLifecycleScope oldLease root)
            expectFailure (readSelection (snapshotStore escaped))
        , testCase "append-only events are fsynced/read back; tamper is refused" $ temporary $ \root ->
            withPosixLifecycle root $ \lease -> do
              recordLifecycleEvent lease (object ["stage" .= ("before" :: Text)])
              before <- BS.readFile (lifecycleEventPath lease)
              recordLifecycleEvent lease (object ["stage" .= ("after" :: Text)])
              actual <- BS.readFile (lifecycleEventPath lease)
              assertBool
                "event prefix changed"
                (before `BS.isPrefixOf` actual && BS.length actual > BS.length before)
              BS.writeFile (lifecycleEventPath lease) "tampered\n"
              expectFailure (recordLifecycleEvent lease (object []))
        , testCase "different fresh CIDs without restore marker cannot enter Reuse" $ temporary $ \root ->
            withPosixLifecycle root $ \lease -> do
              handle <- fresh root lease "one"
              saved <- prepare root handle "one" fixture
              commitSelection (snapshotStore handle) Nothing saved
              assertReusableCluster lease "linux-cpu" [node]
              expectFailure (assertReusableCluster lease "linux-cpu" [newNode])
        , testCase "pending restore survives failure/cancel and cannot be retried" $ temporary $ \root ->
            withPosixLifecycle root $ \lease -> do
              handle <- fresh root lease "one"
              saved <- prepare root handle "one" fixture
              commitSelection (snapshotStore handle) Nothing saved
              _ <- beginSnapshotRestore handle newRequest saved
              before <- BS.readFile (root </> ".build/runtime/pv-snapshot-control/linux-cpu/restore.json")
              expectFailure (throwIO ThreadKilled :: IO ())
              expectFailure (assertReusableCluster lease "linux-cpu" [newNode])
              expectFailure
                (assertReusableCluster lease "linux-cpu" [node {nodeContainerId = "unexpected-other-cid"}])
              expectFailure (beginSnapshotRestore handle newRequest saved)
              BS.readFile (root </> ".build/runtime/pv-snapshot-control/linux-cpu/restore.json") >>= (@?= before)
        , testCase "only exact completed all-node marker admits Reuse; token single-use" $ temporary $ \root ->
            withPosixLifecycle root $ \lease -> do
              handle <- fresh root lease "one"
              saved <- prepare root handle "one" fixture
              commitSelection (snapshotStore handle) Nothing saved
              token <- beginSnapshotRestore handle newRequest saved
              completeSnapshotRestore token
              assertReusableCluster lease "linux-cpu" [newNode]
              expectFailure (assertReusableCluster lease "linux-cpu" [node {nodeContainerId = "other-cid"}])
              expectFailure (completeSnapshotRestore token)
        , testCase "cancelled purge cannot admit its surviving partially restored CIDs" $ temporary $ \root ->
            withPosixLifecycle root $ \lease -> do
              handle <- fresh root lease "one"
              saved <- prepare root handle "one" fixture
              commitSelection (snapshotStore handle) Nothing saved
              _ <- beginSnapshotRestore handle newRequest saved
              invalidateAllSnapshotSelections lease
              expectFailure (assertReusableCluster lease "linux-cpu" [newNode])
              -- After intentional purge/delete, an unrelated brand-new cluster with
              -- no selected snapshot does not resurrect the invalidated generation.
              assertReusableCluster lease "linux-cpu" [node {nodeContainerId = "after-purge-cid"}]
        , testCase "permanent cross-process lock survives atomic data detach" $ temporary $ \root -> do
            childRef <- newIORef Nothing
            withPosixLifecycle root $ \lease -> do
              handle <- fresh root lease "one"
              reserveOwnedGeneration handle
              renameDirectory (root </> ".data") (root </> ".data-preserved-purge-test")
              pid <-
                forkProcess $
                  withPosixLifecycle root (\_ -> writePrivate (root </> "child-acquired") "yes")
                    >> exitImmediately ExitSuccess
              writeIORef childRef (Just pid)
              threadDelay 100000
              acquired <- doesFileExist (root </> "child-acquired")
              assertBool "other process acquired while outer lease held" (not acquired)
            pid <- readIORef childRef >>= maybe (fail "missing child") pure
            status <- getProcessStatus True False pid
            status @?= Just (Exited ExitSuccess)
            doesFileExist (root </> "child-acquired") >>= assertBool "child never acquired after release"
        ]

temporary :: (FilePath -> IO a) -> IO a
temporary action = withSystemTempDirectory "jitml-pv-store-private" (canonicalizePath >=> action)

fresh :: FilePath -> LifecycleLease -> Text -> IO PosixSnapshotStore
fresh root lease token = openPosixSnapshotStore lease (PosixSnapshotConfig root "linux-cpu" token)

prepare :: FilePath -> PosixSnapshotStore -> Text -> BS.ByteString -> IO SnapshotSelection
prepare root handle token manifest = do
  reserveOwnedGeneration handle
  writePrivate (lane root </> archive token) payload
  stageGeneration
    (snapshotStore handle)
    request
    [NodeSnapshot node (archive token) payloadDigest manifest]

lane :: FilePath -> FilePath
lane root = root </> ".data/.jitml-pv-snapshots/linux-cpu"

archive :: Text -> FilePath
archive token = "generations/" <> Text.unpack token <> "/worker.pax"

payload :: BS.ByteString
payload = "private storage fixture, NOT a tar or restore claim\n"

payloadDigest :: FileDigest
payloadDigest =
  FileDigest
    (toInteger (BS.length payload))
    ( Text.pack
        ( concatMap
            (\n -> let s = showHex n "" in if length s == 1 then '0' : s else s)
            (BS.unpack (SHA.hash payload))
        )
    )

request :: SnapshotRequest
request =
  SnapshotRequest
    "linux-cpu"
    "jitml-linux-cpu"
    [node]
    ( fmap
        ("jitml/.data/platform/" <>)
        [ "minio/pv_0"
        , "pulsar-bookie-journal/pv_0"
        , "pulsar-bookie-ledgers/pv_0"
        , "pulsar-zookeeper-data/pv_0"
        ]
    )

node :: NodeIdentity
node = NodeIdentity "worker" "fixture-cid"

newNode :: NodeIdentity
newNode = NodeIdentity "worker" "fresh-cid"

newRequest :: SnapshotRequest
newRequest = request {snapshotNodes = [newNode]}

writePrivate :: FilePath -> BS.ByteString -> IO ()
writePrivate path bytes = do
  fd <- openFd path WriteOnly defaultFileFlags {exclusive = True, creat = Just 0o600}
  stream <- fdToHandle fd
  BS.hPut stream bytes
  hClose stream

expectFailure :: IO a -> IO ()
expectFailure action = do
  attempted <- try action
  case attempted of Left (_ :: SomeException) -> pure (); Right _ -> fail "unexpected success"
