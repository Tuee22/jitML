{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}

-- Actual temporary filesystem/configuration/Store controls only. The supplied
-- allocation scope is fixture DATA, not authenticated parent/training evidence.
-- No configured remote server or producer/hardware authority is exercised here.
module NativeRetention (nativeRetentionTests) where

import Codec.CBOR.Decoding qualified as CBOR
import Codec.CBOR.Read qualified as CBOR
import Control.Concurrent (forkFinally)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import Control.Exception (AsyncException (ThreadKilled), throw, throwIO, try)
import Control.Monad (forM_, void)
import Control.Monad.Reader (runReaderT)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Char (intToDigit)
import Data.Either (lefts)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import System.Directory (doesFileExist, getCurrentDirectory)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Checkpoint.NativeRetention qualified as R
import JitML.Checkpoint.Store qualified as Store
import JitML.Checkpoint.Writer qualified as Writer
import JitML.Env.Build (GlobalFlags (..), buildEnv, defaultGlobalFlags)
import JitML.Env.Env (Env)
import JitML.Product.SourceDigest qualified as Source

right :: (Show error) => Either error value -> IO value
right value = case value of
  Right actual -> pure actual
  Left reason -> assertFailure (show reason) >> fail "unreachable"
reject
  :: R.NativeRetentionStage
  -> R.NativeRetentionReason
  -> Either R.NativeRetentionFailure value
  -> Assertion
reject stage reason value = case value of
  Left actual -> actual @?= R.NativeRetentionFailure stage reason
  Right _ -> assertFailure "retention unexpectedly returned an acknowledgement/cursor"

scope :: R.NativeAllocationScope
scope =
  R.NativeAllocationScope
    (R.NativeDirectLocalAcquisition "fixture-run")
    "DQN/cartpole"
    (Source.SourceStamp Source.sourceDigestAlgorithm (Text.replicate 64 "a"))
    (Text.replicate 64 "b")
    "fixed-five-pool"

temporary :: String -> (FilePath -> Env -> IO ()) -> TestTree
temporary title action = testCase title $ withSystemTempDirectory "jitml-native-retention-" $ \root -> do
  env <-
    buildEnv
      defaultGlobalFlags
        { globalCacheDir = Just (root </> "cache")
        , globalDataDir = Just (root </> "data")
        }
  action root env
capture :: FilePath -> Env -> IO R.NativeRetentionSession
capture root env =
  right
    =<< runReaderT
      (R.captureNativeRetentionSessionAt R.AllowLocalNativeRetention (root </> "absent-boot.dhall") root)
      env
allocation
  :: FilePath -> Env -> LBS.ByteString -> IO (R.RetainedNativeAllocation, R.NativeRetentionCursor)
allocation root env payload = do
  session <- capture root env
  address <- right (R.mkNativeAllocationAddress scope)
  right =<< R.claimNativeAllocation session address payload
label :: IO R.NativeRetentionPhaseLabel
label = right (R.mkNativeRetentionPhaseLabel "child-0.initial")
readActual :: Env -> R.NativeRetainedObjectData -> IO BS.ByteString
readActual env object = do
  root <- runReaderT Writer.localCheckpointRoot env
  bytes <- right =<< Store.readObject root (R.nativeRetainedObjectKey object)
  let actual = LBS.toStrict bytes
  BS.length actual @?= fromIntegral (R.nativeRetainedObjectBytes object)
  digest actual @?= R.nativeRetainedObjectSha256 object
  pure actual
digest :: BS.ByteString -> Text
digest =
  Text.pack
    . concatMap
      (\byte -> [intToDigit (fromIntegral byte `div` 16), intToDigit (fromIntegral byte `mod` 16)])
    . BS.unpack
    . SHA256.hash

-- Independent test decoders inspect actual bytes without minting capabilities.
decode :: (forall state. CBOR.Decoder state value) -> BS.ByteString -> IO value
decode parser bytes = do
  (remaining, actual) <- right (CBOR.deserialiseFromBytes parser (LBS.fromStrict bytes))
  assertBool "actual envelope has trailing bytes" (LBS.null remaining)
  pure actual
claimDecoder :: CBOR.Decoder state (Text, BS.ByteString, BS.ByteString, BS.ByteString)
claimDecoder = do
  CBOR.decodeListLenOf 4
  (,,,) <$> CBOR.decodeString <*> CBOR.decodeBytes <*> CBOR.decodeBytes <*> CBOR.decodeBytes

-- Nested bytes are decoded independently, rather than merely checked nonempty.
data ScopeFields = ScopeFields Text Text Text Text Word64 Text Text Text deriving stock (Eq, Show)
scopeDecoder :: CBOR.Decoder state ScopeFields
scopeDecoder = do
  CBOR.decodeListLenOf 8
  ScopeFields
    <$> CBOR.decodeString
    <*> CBOR.decodeString
    <*> CBOR.decodeString
    <*> CBOR.decodeString
    <*> CBOR.decodeWord64
    <*> CBOR.decodeString
    <*> CBOR.decodeString
    <*> CBOR.decodeString
data PublicationFields = PublicationFields Text Text BS.ByteString Text Text Text Bool
  deriving stock (Eq, Show)
publicationDecoder :: CBOR.Decoder state PublicationFields
publicationDecoder = do
  CBOR.decodeListLenOf 7
  PublicationFields
    <$> CBOR.decodeString
    <*> CBOR.decodeString
    <*> CBOR.decodeBytes
    <*> CBOR.decodeString
    <*> CBOR.decodeString
    <*> CBOR.decodeString
    <*> CBOR.decodeBool
resolutionDecoder :: CBOR.Decoder state (Text, Text)
resolutionDecoder = do
  CBOR.decodeListLenOf 2
  (,) <$> CBOR.decodeString <*> CBOR.decodeString

data Phase = Phase Text Text Text BS.ByteString Word64 Text Text Text BS.ByteString
  deriving stock (Eq, Show)
phaseDecoder :: CBOR.Decoder state Phase
phaseDecoder = do
  CBOR.decodeListLenOf 9
  Phase
    <$> CBOR.decodeString
    <*> CBOR.decodeString
    <*> CBOR.decodeString
    <*> CBOR.decodeBytes
    <*> CBOR.decodeWord64
    <*> CBOR.decodeString
    <*> CBOR.decodeString
    <*> CBOR.decodeString
    <*> CBOR.decodeBytes

parallel :: IO value -> IO value -> IO (value, value)
parallel one two = do
  a <- newEmptyMVar
  b <- newEmptyMVar
  void (forkFinally one (putMVar a))
  void (forkFinally two (putMVar b))
  first <- takeMVar a >>= either throwIO pure
  second <- takeMVar b >>= either throwIO pure
  pure (first, second)

nativeRetentionTests :: TestTree
nativeRetentionTests =
  testGroup
    "native allocation object retention"
    [ testCase "fixed allocation address binds every scope field and is independent of claim payload" $ do
        original <- right (R.mkNativeAllocationAddress scope)
        again <- right (R.mkNativeAllocationAddress scope)
        original @?= again
        R.nativeAllocationAddressScope original @?= scope
        assertBool
          "fixed key uses content-artifact addressing"
          ( "jitml-checkpoints/native-rl-allocations-v1/"
              `Text.isPrefixOf` R.nativeAllocationAddressKey original
          )
        forM_
          [ scope {R.nativeAllocationContext = R.NativeSuppliedScenarioDigest (Text.replicate 64 "c")}
          , scope {R.nativeAllocationRow = "DQN/mountain-car"}
          , scope
              { R.nativeAllocationSource = Source.SourceStamp Source.sourceDigestAlgorithm (Text.replicate 64 "d")
              }
          , scope {R.nativeAllocationRecipeSha256 = Text.replicate 64 "e"}
          , scope {R.nativeAllocationAcquisitionId = "another-five-pool"}
          ]
          $ \changed -> do
            actual <- right (R.mkNativeAllocationAddress changed)
            assertBool
              "changed scope reused the same allocation slot"
              (R.nativeAllocationAddressKey actual /= R.nativeAllocationAddressKey original)
    , testCase "invalid scope and phase labels reject before any filesystem operation" $ do
        forM_
          [ scope {R.nativeAllocationRow = ""}
          , scope {R.nativeAllocationRow = Text.replicate 129 "x"}
          , scope {R.nativeAllocationAcquisitionId = "with whitespace"}
          , scope {R.nativeAllocationRecipeSha256 = Text.replicate 64 "Z"}
          , scope {R.nativeAllocationSource = Source.SourceStamp 0 (Text.replicate 64 "a")}
          , scope {R.nativeAllocationContext = R.NativeSuppliedScenarioDigest "short"}
          ]
          $ \bad ->
            case R.mkNativeAllocationAddress bad of
              Left _ -> pure ()
              Right _ -> assertFailure "invalid allocation scope accepted"
        forM_ ["", "Uppercase", "slash/name", Text.replicate 65 "a"] $ \bad ->
          case R.mkNativeRetentionPhaseLabel bad of
            Left _ -> pure ()
            Right _ -> assertFailure "invalid phase label accepted"
    , temporary "explicit absent configuration captures local coverage without changing cwd" $ \root env -> do
        cwdBefore <- getCurrentDirectory
        session <- capture root env
        cwdAfter <- getCurrentDirectory
        cwdAfter @?= cwdBefore
        case R.nativeRetentionPublication session of
          R.NativeLocalPublication (R.NativeExplicitPublicationResolution identity) localRoot -> do
            Text.length identity @?= 64
            Text.length localRoot @?= 64
          _ -> assertFailure "explicit absent configuration was relabelled as default or remote"
    , temporary "required live publication rejects actual absence without local fallback" $ \root env -> do
        result <-
          runReaderT
            (R.captureNativeRetentionSessionAt R.RequireLiveNativeRetention (root </> "absent.dhall") root)
            env
        reject R.NativePublicationCapture R.NativePublicationRequired result
    , temporary "malformed actual configuration fails with safe tags and no parser contents" $ \root env -> do
        let path = root </> "invalid.dhall"
        BS.writeFile path "sensitive-parser-control not-a-BootConfig"
        result <- runReaderT (R.captureNativeRetentionSessionAt R.AllowLocalNativeRetention path root) env
        reject R.NativePublicationCapture R.NativePublicationConfigurationInvalid result
        case result of
          Left reason ->
            assertBool
              "raw configuration contents leaked"
              (not ("sensitive-parser-control" `Text.isInfixOf` Text.pack (show reason)))
          Right _ -> assertFailure "invalid configuration created a session"
    , temporary "actual claim stores a complete scope publication and supplied payload envelope" $ \root env -> do
        session <- capture root env
        address <- right (R.mkNativeAllocationAddress scope)
        (claimed, _) <- right =<< R.claimNativeAllocation session address "five-child-fixture-data"
        actual <- readActual env (R.nativeRetainedAllocationData claimed)
        (domain, scopeBytes, publicationBytes, payload) <- decode claimDecoder actual
        domain @?= "jitml-native-allocation-claim-v1"
        assertBool "claim discarded scope encoding" (not (BS.null scopeBytes))
        assertBool "claim discarded actual publication encoding" (not (BS.null publicationBytes))
        observedScope <- decode scopeDecoder scopeBytes
        observedScope
          @?= ScopeFields
            "jitml-native-allocation-scope-v1"
            "direct-local"
            "fixture-run"
            (R.nativeAllocationRow scope)
            (Source.stampAlgorithm (R.nativeAllocationSource scope))
            (Source.stampSha256 (R.nativeAllocationSource scope))
            (R.nativeAllocationRecipeSha256 scope)
            (R.nativeAllocationAcquisitionId scope)
        PublicationFields publicationDomain bucket resolutionBytes mode actualRoot endpoint fromBootConfig <-
          decode publicationDecoder publicationBytes
        resolution <- decode resolutionDecoder resolutionBytes
        case R.nativeRetentionPublication session of
          R.NativeLocalPublication (R.NativeExplicitPublicationResolution identity) capturedRoot -> do
            (publicationDomain, bucket, mode, actualRoot, endpoint, fromBootConfig)
              @?= ("jitml-native-retention-publication-v1", "jitml-checkpoints", "local", capturedRoot, "", False)
            resolution @?= ("explicit-filesystem", identity)
          _ -> assertFailure "claim did not bind the actual explicit local capture descriptor"
        payload @?= "five-child-fixture-data"
    , temporary "a fresh session cannot reacquire an identical existing local claim" $ \root env -> do
        _ <- allocation root env "same"
        session <- capture root env
        address <- right (R.mkNativeAllocationAddress scope)
        R.claimNativeAllocation session address "same"
          >>= reject R.NativeAllocationClaim R.NativeRetentionAlreadyClaimedLocally
    , temporary "new nonce bytes conflict at the same fixed allocation slot" $ \root env -> do
        (original, _) <- allocation root env "attempt-nonce-one"
        session <- capture root env
        address <- right (R.mkNativeAllocationAddress scope)
        R.claimNativeAllocation session address "attempt-nonce-two"
          >>= reject R.NativeAllocationClaim R.NativeRetentionLocalConflict
        actual <- readActual env (R.nativeRetainedAllocationData original)
        (_, _, _, payload) <- decode claimDecoder actual
        payload @?= "attempt-nonce-one"
    , temporary "one session cannot acquire a second allocation after its first claim" $ \root env -> do
        session <- capture root env
        address <- right (R.mkNativeAllocationAddress scope)
        _ <- right =<< R.claimNativeAllocation session address "first"
        other <- right (R.mkNativeAllocationAddress (scope {R.nativeAllocationAcquisitionId = "second"}))
        R.claimNativeAllocation session other "second"
          >>= reject R.NativeAllocationClaim R.NativeRetentionAlreadyConsumed
    , temporary "concurrent fresh sessions permit exactly one actual claim in the fixed slot" $ \root env -> do
        one <- capture root env
        two <- capture root env
        address <- right (R.mkNativeAllocationAddress scope)
        (a, b) <-
          parallel (R.claimNativeAllocation one address "same") (R.claimNativeAllocation two address "same")
        length [() | Right _ <- [a, b]] @?= 1
        case lefts [a, b] of
          [failure] ->
            failure @?= R.NativeRetentionFailure R.NativeAllocationClaim R.NativeRetentionAlreadyClaimedLocally
          _ -> assertFailure "claim race did not reject exactly one caller"
    , temporary "actual phase chain binds ordinal claim predecessor label and exact bytes" $ \root env -> do
        (claimed, cursor) <- allocation root env "claim"
        phaseLabel <- label
        (first, next) <- right =<< R.appendNativeRetentionPhase cursor phaseLabel "initial-one"
        (second, _) <- right =<< R.appendNativeRetentionPhase next phaseLabel "raw-two"
        let claim = R.nativeRetainedAllocationData claimed
            one = R.nativeRetainedPhaseData first
            two = R.nativeRetainedPhaseData second
        Phase domain allocationKey claimSha publication ordinal previousKey previousSha actualLabel payload <-
          decode phaseDecoder =<< readActual env one
        domain @?= "jitml-native-retention-phase-v1"
        allocationKey @?= R.nativeRetainedObjectKey claim
        claimSha @?= R.nativeRetainedObjectSha256 claim
        ordinal @?= 0
        previousKey @?= R.nativeRetainedObjectKey claim
        previousSha @?= R.nativeRetainedObjectSha256 claim
        actualLabel @?= "child-0.initial"
        payload @?= "initial-one"
        Phase
          _
          allocationAgain
          claimAgain
          publicationAgain
          ordinalAgain
          previousAgain
          previousShaAgain
          _
          payloadAgain <-
          decode phaseDecoder =<< readActual env two
        ( allocationAgain
          , claimAgain
          , publicationAgain
          , ordinalAgain
          , previousAgain
          , previousShaAgain
          , payloadAgain
          )
          @?= ( allocationKey
              , claimSha
              , publication
              , 1
              , R.nativeRetainedObjectKey one
              , R.nativeRetainedObjectSha256 one
              , "raw-two"
              )
        assertBool
          "phase key is not content addressed"
          ( ("/phases/" <> R.nativeRetainedObjectSha256 one <> ".cbor")
              `Text.isSuffixOf` R.nativeRetainedObjectKey one
          )
    , temporary "concurrent cursor reuse permits one append and cannot restore the spent cursor" $ \root env -> do
        (_, cursor) <- allocation root env "claim"
        phaseLabel <- label
        (a, b) <-
          parallel
            (R.appendNativeRetentionPhase cursor phaseLabel "phase")
            (R.appendNativeRetentionPhase cursor phaseLabel "phase")
        length [() | Right _ <- [a, b]] @?= 1
        case lefts [a, b] of
          [failure] -> failure @?= R.NativeRetentionFailure R.NativePhaseAppend R.NativeRetentionAlreadyConsumed
          _ -> assertFailure "cursor race did not reject exactly one caller"
        R.appendNativeRetentionPhase cursor phaseLabel "again"
          >>= reject R.NativePhaseAppend R.NativeRetentionAlreadyConsumed
    , temporary "lazy synchronous payload exceptions return safe tags and permanently spend the cursor" $ \root env -> do
        (_, cursor) <- allocation root env "claim"
        phaseLabel <- label
        result <- R.appendNativeRetentionPhase cursor phaseLabel (error "sensitive-payload-control")
        reject R.NativePhaseAppend R.NativeRetentionSynchronousFailure result
        case result of
          Left reason ->
            assertBool
              "exception text leaked"
              (not ("sensitive-payload-control" `Text.isInfixOf` Text.pack (show reason)))
          Right _ -> assertFailure "poisonous payload produced a retained phase"
        R.appendNativeRetentionPhase cursor phaseLabel "again"
          >>= reject R.NativePhaseAppend R.NativeRetentionAlreadyConsumed
    , temporary "async exception class during request forcing propagates and spends the cursor" $ \root env -> do
        (_, cursor) <- allocation root env "claim"
        phaseLabel <- label
        actual <-
          try (R.appendNativeRetentionPhase cursor phaseLabel (throw ThreadKilled))
            :: IO
                 ( Either
                     AsyncException
                     (Either R.NativeRetentionFailure (R.RetainedNativePhase, R.NativeRetentionCursor))
                 )
        case actual of
          Left ThreadKilled -> pure ()
          _ -> assertFailure "async exception class was swallowed"
        R.appendNativeRetentionPhase cursor phaseLabel "again"
          >>= reject R.NativePhaseAppend R.NativeRetentionAlreadyConsumed
    , temporary "bounded forcing rejects an infinite request before creating its claim object" $ \root env -> do
        session <- capture root env
        address <- right (R.mkNativeAllocationAddress scope)
        R.claimNativeAllocation session address (LBS.repeat 0)
          >>= reject R.NativeAllocationClaim R.NativeRetentionPayloadTooLarge
        cache <- runReaderT Writer.localCheckpointRoot env
        path <- right (Store.objectPathForKey cache (R.nativeAllocationAddressKey address))
        doesFileExist path >>= (@?= False)
        R.claimNativeAllocation session address "again"
          >>= reject R.NativeAllocationClaim R.NativeRetentionAlreadyConsumed
    ]
