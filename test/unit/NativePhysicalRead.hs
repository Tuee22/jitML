{-# LANGUAGE OverloadedStrings #-}

-- Actual temporary filesystem/configuration reads. Fixture scope/payload DATA
-- establish no training, parent authentication, remote ACK or qualification.
module NativePhysicalRead (nativePhysicalReadTests) where

import Control.Exception (AsyncException (ThreadKilled), throw, try)
import Control.Monad.Reader (runReaderT)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Text qualified as Text
import System.FilePath ((</>))
import System.IO (IOMode (ReadWriteMode), hSetFileSize, withBinaryFile)
import System.IO.Temp (withSystemTempDirectory)
import System.Timeout (timeout)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertEqual, assertFailure, testCase)

import JitML.Checkpoint.NativeRetention qualified as R
import JitML.Checkpoint.NativeRetentionReader qualified as Reader
import JitML.Checkpoint.Store qualified as Store
import JitML.Checkpoint.Writer qualified as Writer
import JitML.Env.Build (GlobalFlags (..), buildEnv, defaultGlobalFlags)
import JitML.Env.Env (Env)
import JitML.Product.SourceDigest qualified as Source
import JitML.Product.ValidationRecord (sha256Hex)

nativePhysicalReadTests :: TestTree
nativePhysicalReadTests =
  testGroup
    "native concrete physical read controls"
    [ temporary "actual claim is fetched through the same captured session and ordinary decoder" $ \root env -> do
        session <- capture root env "absent-boot.dhall"
        reference <- claim session
        actual <- right =<< R.readNativeRetainedObject session reference
        assertEqual "same actual physical reference" reference (R.nativeReadObjectReference actual)
        decoded <- right (Reader.decodeNativeAllocationEnvelope reference (R.nativeReadObjectBytes actual))
        assertEqual
          "actual complete opaque payload"
          "physical-fixture-payload"
          (Reader.decodedAllocationPayload decoded)
        assertEqual "actual scope DATA" scope (Reader.decodedAllocationScope decoded)
    , temporary "actual appended phase is fetched and linked to its exact claim" $ \root env -> do
        session <- capture root env "absent-boot.dhall"
        address <- right (R.mkNativeAllocationAddress scope)
        (allocation, cursor) <- right =<< R.claimNativeAllocation session address "five-DATA"
        label <- right (R.mkNativeRetentionPhaseLabel "child0.started")
        (phase, _) <- right =<< R.appendNativeRetentionPhase cursor label "actual-phase-DATA"
        a <- right =<< R.readNativeRetainedObject session (R.nativeRetainedAllocationData allocation)
        b <- right =<< R.readNativeRetainedObject session (R.nativeRetainedPhaseData phase)
        decodedA <-
          right
            (Reader.decodeNativeAllocationEnvelope (R.nativeReadObjectReference a) (R.nativeReadObjectBytes a))
        decodedB <-
          right
            ( Reader.decodeNativeRetentionPhaseEnvelope
                (R.nativeReadObjectReference b)
                (R.nativeReadObjectBytes b)
            )
        _ <-
          right (Reader.validateNativeRetentionPhaseLink decodedA (R.nativeReadObjectReference a) 0 decodedB)
        assertEqual "same actual phase DATA" "actual-phase-DATA" (Reader.decodedPhasePayload decodedB)
    , temporary "recorded physical SHA substitution refuses actual existing claim bytes" $ \root env -> do
        session <- capture root env "absent-boot.dhall"
        reference <- claim session
        rejects R.NativePhysicalReadBytesMismatch
          =<< R.readNativeRetainedObject
            session
            (reference {R.nativeRetainedObjectSha256 = Text.replicate 64 "0"})
    , temporary "smaller recorded byte count refuses the actual complete existing object" $ \root env -> do
        session <- capture root env "absent-boot.dhall"
        reference <- claim session
        rejects R.NativePhysicalReadBytesMismatch
          =<< R.readNativeRetainedObject
            session
            (reference {R.nativeRetainedObjectBytes = R.nativeRetainedObjectBytes reference - 1})
    , temporary "publication relabeling refuses before fetching existing bytes" $ \root env -> do
        session <- capture root env "absent-boot.dhall"
        reference <- claim session
        let publication = R.NativeLocalPublication R.NativeDefaultPublicationResolution (Text.replicate 64 "0")
        rejects R.NativePhysicalReadScopeMismatch
          =<< R.readNativeRetainedObject
            session
            (reference {R.nativeRetainedObjectPublication = publication})
    , temporary "another explicit captured resolution cannot borrow the original physical reference" $ \root env -> do
        original <- capture root env "first-absent-boot.dhall"
        reference <- claim original
        changed <- capture root env "second-absent-boot.dhall"
        rejects R.NativePhysicalReadScopeMismatch =<< R.readNativeRetainedObject changed reference
    , temporary "traversal and foreign phase filenames refuse before object reads" $ \root env -> do
        session <- capture root env "absent-boot.dhall"
        reference <- claim session
        mapM_
          ( \key ->
              rejects R.NativePhysicalReadAddressInvalid
                =<< R.readNativeRetainedObject
                  session
                  (reference {R.nativeRetainedObjectKey = key})
          )
          [ "jitml-checkpoints/native-rl-allocations-v1/../claim.cbor"
          , R.nativeRetainedObjectKey reference <> "/extra"
          ]
    , temporary "outer payload plus header size bound refuses oversized recorded count" $ \root env -> do
        session <- capture root env "absent-boot.dhall"
        reference <- claim session
        rejects R.NativePhysicalReadSizeInvalid
          =<< R.readNativeRetainedObject
            session
            (reference {R.nativeRetainedObjectBytes = fromIntegral R.maximumNativeRetentionPayloadBytes + 4097})
    , temporary "missing valid physical address reports an actual local read failure" $ \root env -> do
        session <- capture root env "absent-boot.dhall"
        address <- right (R.mkNativeAllocationAddress scope)
        let reference =
              R.NativeRetainedObjectData
                (R.nativeAllocationAddressKey address)
                (sha256Hex BS.empty)
                0
                (R.nativeRetentionPublication session)
        rejects R.NativePhysicalReadLocalFailed =<< R.readNativeRetainedObject session reference
    , temporary "same-length actual disk byte corruption cannot retain its old digest" $ \root env -> do
        session <- capture root env "absent-boot.dhall"
        reference <- claim session
        checkpointRoot <- runReaderT Writer.localCheckpointRoot env
        path <- right (Store.objectPathForKey checkpointRoot (R.nativeRetainedObjectKey reference))
        bytes <- BS.readFile path
        BS.writeFile path (BS.cons 0 (BS.tail bytes))
        rejects R.NativePhysicalReadBytesMismatch =<< R.readNativeRetainedObject session reference
    , temporary "sparse oversized file refuses after the recorded zero-byte cap plus one" $ \root env -> do
        session <- capture root env "absent-boot.dhall"
        checkpointRoot <- runReaderT Writer.localCheckpointRoot env
        address <- right (R.mkNativeAllocationAddress scope)
        let key = R.nativeAllocationAddressKey address
            reference = R.NativeRetainedObjectData key (sha256Hex BS.empty) 0 (R.nativeRetentionPublication session)
        _ <- right =<< Store.writeObjectIfAbsent checkpointRoot key LBS.empty
        path <- right (Store.objectPathForKey checkpointRoot key)
        withBinaryFile path ReadWriteMode (\handle -> hSetFileSize handle (1024 * 1024 * 1024))
        actual <- timeout 5000000 (R.readNativeRetainedObject session reference)
        case actual of
          Nothing -> assertFailure "bounded actual file read did not terminate"
          Just result -> rejects R.NativePhysicalReadBytesMismatch result
    , temporary "poisoned ordinary reference reports the closed synchronous failure tag" $ \root env -> do
        session <- capture root env "absent-boot.dhall"
        rejects R.NativePhysicalReadSynchronousFailure
          =<< R.readNativeRetainedObject session (error "physical reference poison")
    , temporary "async reference forcing propagates cancellation through the safe physical catcher" $ \root env -> do
        session <- capture root env "absent-boot.dhall"
        actual <- try (R.readNativeRetainedObject session (throw ThreadKilled))
        case actual of
          Left ThreadKilled -> pure ()
          Left other -> assertFailure ("unexpected async exception: " <> show other)
          Right _ -> assertFailure "physical reader swallowed actual cancellation"
    , temporary "missing exact checkpoint refuses without fabricating a physical completion" $ \root env -> do
        session <- capture root env "absent-boot.dhall"
        rejects R.NativePhysicalReadCheckpointRefused
          =<< R.readNativeExecutionCheckpoint session "absent-experiment" (Text.replicate 64 "0")
    ]

temporary :: String -> (FilePath -> Env -> IO ()) -> TestTree
temporary title action = testCase title $ withSystemTempDirectory "jitml-native-physical-read-" $ \root -> do
  env <-
    buildEnv
      defaultGlobalFlags
        { globalCacheDir = Just (root </> "cache")
        , globalDataDir = Just (root </> "data")
        }
  action root env

capture :: FilePath -> Env -> FilePath -> IO R.NativeRetentionSession
capture root env boot =
  right
    =<< runReaderT
      (R.captureNativeRetentionSessionAt R.AllowLocalNativeRetention (root </> boot) root)
      env

claim :: R.NativeRetentionSession -> IO R.NativeRetainedObjectData
claim session = do
  address <- right (R.mkNativeAllocationAddress scope)
  (actual, _) <- right =<< R.claimNativeAllocation session address "physical-fixture-payload"
  pure (R.nativeRetainedAllocationData actual)

scope :: R.NativeAllocationScope
scope =
  R.NativeAllocationScope
    (R.NativeDirectLocalAcquisition "actual-filesystem-fixture")
    "DQN/cartpole"
    (Source.SourceStamp Source.sourceDigestAlgorithm (Text.replicate 64 "a"))
    (Text.replicate 64 "b")
    "fixed-five-DATA"

right :: (Show e) => Either e a -> IO a
right value = case value of
  Right actual -> pure actual
  Left failure -> assertFailure (show failure) >> fail "unreachable"

rejects :: R.NativePhysicalReadFailure -> Either R.NativePhysicalReadFailure a -> IO ()
rejects expected result = case result of
  Left actual -> assertEqual "actual closed physical failure" expected actual
  Right _ -> assertFailure "invalid physical input created a read capsule"
