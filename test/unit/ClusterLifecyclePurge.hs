{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE OverloadedStrings #-}

module ClusterLifecyclePurge (tests) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Foreign.C.String (CString, withCString)
import Foreign.C.Types (CInt (..))
import System.Directory
  ( canonicalizePath
  , createDirectory
  , createDirectoryIfMissing
  , doesDirectoryExist
  , doesFileExist
  )
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Posix.Files (createLink, createSymbolicLink, getSymbolicLinkStatus, isSymbolicLink)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

foreign import ccall safe "jitml_lifecycle_purge" cPurge :: CString -> CString -> CInt -> IO CInt

purge :: FilePath -> String -> Bool -> IO CInt
purge root token full = withCString root $ \r -> withCString token $ \t -> cPurge r t (if full then 1 else 0)

fixture :: (FilePath -> IO a) -> IO a
fixture action = withSystemTempDirectory "jitml-lifecycle-purge" $ \temporary -> do
  root <- canonicalizePath temporary
  forM_ [".data/platform/minio/pv_0", ".build/jit/apple-silicon"] $ \path -> createDirectoryIfMissing True (root </> path)
  BS.writeFile (root </> ".data/platform/minio/pv_0/object") "actual retained bytes"
  BS.writeFile (root </> ".build/jit/apple-silicon/kernel") "cached kernel"
  BS.writeFile (root </> ".jitml-pv-lifecycle.lock") "lock inode"
  BS.writeFile (root </> "source.hs") "source marker"
  action root

outside :: (FilePath -> IO a) -> IO a
outside action = withSystemTempDirectory "jitml-purge-outside" $ \temporary -> do
  root <- canonicalizePath temporary
  BS.writeFile (root </> "protected") "must survive"
  action root

tests :: TestTree
tests =
  testGroup
    "Actual descriptor-relative purge filesystem"
    [ testCase "ordinary purge removes data and preserves cache, source and permanent lock" $ fixture $ \root -> do
        purge root "ordinary" False >>= (@?= 0)
        doesDirectoryExist (root </> ".data") >>= (@?= False)
        BS.readFile (root </> ".build/jit/apple-silicon/kernel") >>= (@?= "cached kernel")
        BS.readFile (root </> "source.hs") >>= (@?= "source marker")
        BS.readFile (root </> ".jitml-pv-lifecycle.lock") >>= (@?= "lock inode")
    , testCase "full purge removes both canonical roots while preserving source and lock" $ fixture $ \root -> do
        purge root "full" True >>= (@?= 0)
        doesDirectoryExist (root </> ".data") >>= (@?= False)
        doesDirectoryExist (root </> ".build") >>= (@?= False)
        doesFileExist (root </> "source.hs") >>= (@?= True)
        doesFileExist (root </> ".jitml-pv-lifecycle.lock") >>= (@?= True)
    , testCase "a descendant directory symlink never purges its external target" $ fixture $ \root -> outside $ \external -> do
        createSymbolicLink external (root </> ".data/platform/external")
        purge root "descendant-link" False >>= (@?= 0)
        BS.readFile (external </> "protected") >>= (@?= "must survive")
    , testCase "hardlink removal preserves the external file" $ fixture $ \root -> outside $ \external -> do
        createLink (external </> "protected") (root </> ".data/shared")
        purge root "hardlink" False >>= (@?= 0)
        BS.readFile (external </> "protected") >>= (@?= "must survive")
    , testCase "an occupied quarantine refuses before detaching data" $ fixture $ \root -> do
        createDirectory (root </> ".data-preserved-purge-collision-data")
        result <- purge root "collision" True
        assertBool "must fail" (result /= 0)
        BS.readFile (root </> ".data/platform/minio/pv_0/object") >>= (@?= "actual retained bytes")
        doesDirectoryExist (root </> ".build") >>= (@?= True)
    , testCase "unsafe token refuses without mutation" $ fixture $ \root -> do
        result <- purge root "../other" True
        assertBool "must fail" (result /= 0)
        doesDirectoryExist (root </> ".data") >>= (@?= True)
        doesDirectoryExist (root </> ".build") >>= (@?= True)
    , testCase "empty token refuses without mutation" $ fixture $ \root -> do
        result <- purge root "" True
        assertBool "must fail" (result /= 0)
        doesDirectoryExist (root </> ".data") >>= (@?= True)
    , testCase "repeated absent-root purge preserves the lock and creates no canonical state" $ fixture $ \root -> do
        purge root "first" True >>= (@?= 0)
        purge root "second" True >>= (@?= 0)
        doesDirectoryExist (root </> ".data") >>= (@?= False)
        doesDirectoryExist (root </> ".build") >>= (@?= False)
        doesFileExist (root </> ".jitml-pv-lifecycle.lock") >>= (@?= True)
    , testCase "workspace symlink refuses before accessing its target" $ fixture $ \root -> outside $ \external -> do
        let link = external </> "workspace"
        createSymbolicLink root link
        result <- purge link "workspace-link" True
        assertBool "must fail" (result /= 0)
        doesDirectoryExist (root </> ".data") >>= (@?= True)
    , testCase "canonical data symlink refuses and preserves cache" $ outside $ \root -> outside $ \external -> do
        createSymbolicLink external (root </> ".data")
        createDirectory (root </> ".build")
        result <- purge root "data-link" True
        assertBool "must fail" (result /= 0)
        BS.readFile (external </> "protected") >>= (@?= "must survive")
        doesDirectoryExist (root </> ".build") >>= (@?= True)
    , testCase "full purge build-link failure cannot resurrect already discarded data" $ outside $ \root -> outside $ \external -> do
        createDirectory (root </> ".data")
        createSymbolicLink external (root </> ".build")
        result <- purge root "build-link" True
        assertBool "must fail" (result /= 0)
        doesDirectoryExist (root </> ".data") >>= (@?= False)
        getSymbolicLinkStatus (root </> ".build") >>= (assertBool "build link retained" . isSymbolicLink)
        BS.readFile (external </> "protected") >>= (@?= "must survive")
    , testCase "canonical regular data file refuses without deleting it" $ outside $ \root -> do
        BS.writeFile (root </> ".data") "foreign file"
        result <- purge root "data-file" True
        assertBool "must fail" (result /= 0)
        BS.readFile (root </> ".data") >>= (@?= "foreign file")
    ]
