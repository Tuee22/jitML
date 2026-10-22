{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- Local filesystem control fixtures only; no incident logs, Docker or PV data.
module PVSnapshotClaim (tests) where

import Control.Exception (AsyncException (ThreadKilled), SomeException, throwIO, try)
import Control.Monad ((>=>))
import Data.ByteString qualified as BS
import Data.IORef (newIORef, readIORef, writeIORef)
import System.Directory
  ( canonicalizePath
  , createDirectory
  , doesDirectoryExist
  , doesFileExist
  , renameDirectory
  )
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

import JitML.Cluster.PVSnapshotPosix (withPosixLifecycle)

tests :: TestTree
tests =
  testGroup
    "atomic workspace lifecycle claim"
    [ testCase "foreign/stale claim refuses callback and is never reclaimed" $ temporary $ \root -> do
        createDirectory (claim root)
        BS.writeFile (claim root </> "owner") "foreign-owner\n"
        called <- newIORef False
        expectFailure (withPosixLifecycle root (\_ -> writeIORef called True))
        readIORef called >>= (@?= False)
        BS.readFile (claim root </> "owner") >>= (@?= "foreign-owner\n")
    , testCase "healthy held claim exists only within scope; permanent local lock remains" $ temporary $ \root -> do
        withPosixLifecycle root $ \_ -> do
          doesDirectoryExist (claim root) >>= assertBool "claim absent within callback"
          bytes <- BS.readFile (claim root </> "owner")
          assertBool "owner token missing" ("lease-" `BS.isPrefixOf` bytes)
        doesDirectoryExist (claim root) >>= (@?= False)
        doesFileExist (root </> ".jitml-pv-lifecycle.lock") >>= assertBool "permanent lock removed"
        withPosixLifecycle root (\_ -> pure ())
    , testCase "changed owner token refuses cleanup; next process cannot auto-reclaim" $ temporary $ \root -> do
        expectFailure
          (withPosixLifecycle root (\_ -> BS.writeFile (claim root </> "owner") "changed-token\n"))
        BS.readFile (claim root </> "owner") >>= (@?= "changed-token\n")
        expectFailure (withPosixLifecycle root (\_ -> pure ()))
    , testCase "claim path replacement never deletes foreign or held original directory" $ temporary $ \root -> do
        expectFailure $ withPosixLifecycle root $ \_ -> do
          renameDirectory (claim root) (root </> "held-original")
          createDirectory (claim root)
          BS.writeFile (claim root </> "owner") "foreign\n"
        BS.readFile (claim root </> "owner") >>= (@?= "foreign\n")
        doesFileExist (root </> "held-original/owner") >>= assertBool "original claim was deleted"
    , testCase "unexpected entry retains both it and owner instead of broad cleanup" $ temporary $ \root -> do
        expectFailure (withPosixLifecycle root (\_ -> BS.writeFile (claim root </> "extra") "retained"))
        BS.readFile (claim root </> "extra") >>= (@?= "retained")
        doesFileExist (claim root </> "owner") >>= assertBool "owner removed before extra-member refusal"
    , testCase "callback async remains primary and releases exact healthy claim" $ temporary $ \root -> do
        result <-
          try (withPosixLifecycle root (\_ -> throwIO ThreadKilled)) :: IO (Either AsyncException ())
        case result of Left ThreadKilled -> pure (); _ -> fail "async failure changed"
        doesDirectoryExist (claim root) >>= (@?= False)
        withPosixLifecycle root (\_ -> pure ())
    ]

temporary :: (FilePath -> IO a) -> IO a
temporary action = withSystemTempDirectory "jitml-pv-claim-private" (canonicalizePath >=> action)

claim :: FilePath -> FilePath
claim root = root </> ".jitml-pv-lifecycle.claim.lock"

expectFailure :: IO a -> IO ()
expectFailure action = do
  actual <- try action
  case actual of Left (_ :: SomeException) -> pure (); Right _ -> fail "unexpected success"
