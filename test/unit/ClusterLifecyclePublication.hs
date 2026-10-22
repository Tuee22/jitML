{-# LANGUAGE OverloadedStrings #-}

module ClusterLifecyclePublication (tests) where

import Control.Exception (IOException, try)
import Control.Monad (void, (>=>))
import Data.Aeson (eitherDecodeStrict', encode)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import System.Directory (canonicalizePath, createDirectoryIfMissing, doesDirectoryExist)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Posix.Files (createLink, createSymbolicLink)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

import JitML.Cluster.LifecycleFilesystem
import JitML.Cluster.LifecycleTarget
import JitML.Cluster.PVSnapshotPosix
import JitML.Cluster.Publication
import JitML.Substrate

temporary :: (FilePath -> IO a) -> IO a
temporary action = withSystemTempDirectory "jitml-lifecycle-authority" (canonicalizePath >=> action)

publicationPath :: FilePath -> FilePath
publicationPath root = root </> ".build/runtime/cluster-publication.json"

ready :: ClusterPublication
ready = markPublicationLive (defaultPublication LinuxCPU)

readyBytes :: BS.ByteString
readyBytes = LBS.toStrict (encode ready)

fixture :: (FilePath -> IO a) -> IO a
fixture action = temporary $ \root -> do
  createDirectoryIfMissing True (root </> ".build/runtime")
  BS.writeFile (publicationPath root) readyBytes
  action root

refuses :: IO a -> IO ()
refuses action = do
  actual <- try (void action) :: IO (Either IOException ())
  assertBool "must fail closed" (case actual of Left _ -> True; Right _ -> False)

tests :: TestTree
tests =
  testGroup
    "Actual lifecycle publication filesystem"
    [ testCase "missing authority creates no runtime tree" $ temporary $ \root -> do
        readLifecyclePublication root >>= (@?= (PublicationMissing, Nothing))
        doesDirectoryExist (root </> ".build") >>= (@?= False)
    , testCase "ready authority reads exact bytes" $
        fixture (readLifecyclePublication >=> (@?= (PublicationPresent ready, Just readyBytes)))
    , testCase "corrupt authority remains corrupt and retains literal bytes" $ fixture $ \root -> do
        BS.writeFile (publicationPath root) "invalid"
        result <- readLifecyclePublication root
        case result of
          (PublicationCorrupt _, Just bytes) -> bytes @?= "invalid"
          _ -> fail "corrupt authority became absent"
    , testCase "publication symlink refuses" $ temporary $ \root -> temporary $ \external -> do
        createDirectoryIfMissing True (root </> ".build/runtime")
        BS.writeFile (external </> "authority") readyBytes
        createSymbolicLink (external </> "authority") (publicationPath root)
        refuses (readLifecyclePublication root)
        BS.readFile (external </> "authority") >>= (@?= readyBytes)
    , testCase "build ancestor symlink refuses" $ temporary $ \root -> temporary $ \external -> do
        createDirectoryIfMissing True (external </> "runtime")
        BS.writeFile (external </> "runtime/cluster-publication.json") readyBytes
        createSymbolicLink external (root </> ".build")
        refuses (readLifecyclePublication root)
    , testCase "publication hardlink refuses" $ temporary $ \root -> temporary $ \external -> do
        createDirectoryIfMissing True (root </> ".build/runtime")
        BS.writeFile (external </> "authority") readyBytes
        createLink (external </> "authority") (publicationPath root)
        refuses (readLifecyclePublication root)
    , testCase "oversize authority refuses" $ fixture $ \root -> do
        BS.writeFile (publicationPath root) (BS.replicate 65537 65)
        refuses (readLifecyclePublication root)
    , testCase "live lease stopped CAS clears every readiness claim" $ fixture $ \root ->
        withPosixLifecycle root $ \lease -> do
          writeStoppedPublication lease root "stopped" readyBytes ready
          bytes <- BS.readFile (publicationPath root)
          eitherDecodeStrict' bytes @?= Right (stoppedPublication ready)
    , testCase "stopping transition clears evidence and cannot use stale ready CAS" $ fixture $ \root ->
        withPosixLifecycle root $ \lease -> do
          transition <- writeStoppingPublication lease root "stopping" readyBytes ready
          eitherDecodeStrict' transition @?= Right (stoppingPublication ready)
          refuses (writeStoppedPublication lease root "stale-ready" readyBytes ready)
          BS.readFile (publicationPath root) >>= (@?= transition)
    , testCase "final stopped CAS accepts only the exact stopping transition" $ fixture $ \root ->
        withPosixLifecycle root $ \lease -> do
          transition <- writeStoppingPublication lease root "stopping" readyBytes ready
          writeStoppedPublication lease root "stopped" transition ready
          bytes <- BS.readFile (publicationPath root)
          eitherDecodeStrict' bytes @?= Right (stoppedPublication ready)
    , testCase "changed authority CAS refuses and preserves current bytes" $ fixture $ \root ->
        withPosixLifecycle root $ \lease -> do
          BS.writeFile (publicationPath root) "changed authority"
          refuses (writeStoppedPublication lease root "cas-conflict" readyBytes ready)
          BS.readFile (publicationPath root) >>= (@?= "changed authority")
    , testCase "missing authority write cannot manufacture publication" $ temporary $ \root ->
        withPosixLifecycle root $ \lease -> do
          refuses (writeStoppedPublication lease root "missing" readyBytes ready)
          doesDirectoryExist (root </> ".build") >>= (@?= False)
    , testCase "expired lease cannot write stopped authority" $ fixture $ \root -> do
        expired <- withPosixLifecycle root pure
        refuses (writeStoppedPublication expired root "expired" readyBytes ready)
        BS.readFile (publicationPath root) >>= (@?= readyBytes)
    , testCase "occupied exclusive temporary file refuses before replacing authority" $ fixture $ \root ->
        withPosixLifecycle root $ \lease -> do
          BS.writeFile
            (root </> ".build/runtime/.cluster-publication-stopped-collision.tmp")
            "retained failure"
          refuses (writeStoppedPublication lease root "collision" readyBytes ready)
          BS.readFile (publicationPath root) >>= (@?= readyBytes)
    , testCase "post-full stopped write cannot recreate removed runtime" $ fixture $ \root ->
        withPosixLifecycle root $ \lease -> do
          purgeRuntimeRoots lease root "full" True
          refuses (writeStoppedPublication lease root "after-full" readyBytes ready)
          doesDirectoryExist (root </> ".build") >>= (@?= False)
    ]
