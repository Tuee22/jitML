{-# LANGUAGE OverloadedStrings #-}

-- Real temporary local reads only. Ordinary fixture bytes are not decoded
-- qualification, replay, parent, writer-ACK or training evidence.
module NativeDetachedArtifactRead (nativeDetachedArtifactReadTests) where

import Control.Exception (AsyncException (ThreadKilled), throw, try)
import Control.Monad.Reader (runReaderT)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Text (Text)
import Data.Text qualified as Text
import System.FilePath ((</>))
import System.IO (IOMode (ReadWriteMode), hSetFileSize, withBinaryFile)
import System.IO.Temp (withSystemTempDirectory)
import System.Timeout (timeout)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertEqual, assertFailure, testCase)

import JitML.Checkpoint.NativeRetention qualified as R
import JitML.Checkpoint.Store qualified as Store
import JitML.Checkpoint.Writer qualified as Writer
import JitML.Env.Build (GlobalFlags (..), buildEnv, defaultGlobalFlags)
import JitML.Env.Env (Env)
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.ValidationRecord (sha256Hex)

nativeDetachedArtifactReadTests :: TestTree
nativeDetachedArtifactReadTests =
  testGroup
    "native bounded detached artifact actual physical reads"
    [ temporary "actual qualification artifact reads exact local bytes and reference" $ \root env ->
        actualRead root env R.NativeQualificationArtifact
    , temporary "actual evaluation replay artifact reads exact local bytes without semantic relabeling" $ \root env ->
        actualRead root env R.NativeEvaluationReplayArtifact
    , temporary "actual loaded replay artifact reads exact local bytes without a replay factory" $ \root env ->
        actualRead root env R.NativeStoreLoadedReplayArtifact
    , testCase "closed key builder accepts actual Matrix experiment namespaces as ordinary DATA" $
        mapM_
          ( \row ->
              mapM_
                ( \kind -> do
                    let rowExperiment = Matrix.productRowExperimentHash row
                    key <- right (R.nativeDetachedArtifactKey kind rowExperiment sha)
                    assertEqual
                      "exact closed namespace"
                      ("jitml-checkpoints/" <> rowExperiment <> "/artifacts/" <> kindName kind <> "/" <> sha <> ".cbor")
                      key
                )
                kinds
          )
          Matrix.allProductRows
    , temporary "actual captured publication digest is stable for the same explicit configuration" $ \root env -> do
        first <- capture root env "absent.dhall"
        second <- capture root env "absent.dhall"
        let a = R.nativePublicationDigest (R.nativeRetentionPublication first)
            b = R.nativePublicationDigest (R.nativeRetentionPublication second)
        assertEqual "same actual descriptor digest" a b
        assertEqual "SHA256 width" 64 (Text.length a)
        assertBool "lowercase SHA256" (Text.all (`elem` ("0123456789abcdef" :: String)) a)
    , testCase "publication digest separates every ordinary descriptor field and resolution" $ do
        let a = Text.replicate 64 "a"
            b = Text.replicate 64 "b"
            original = R.NativeConfiguredPublication R.NativeDefaultPublicationResolution a b False
            changes =
              [ R.NativeConfiguredPublication (R.NativeExplicitPublicationResolution a) a b False
              , R.NativeConfiguredPublication R.NativeDefaultPublicationResolution b b False
              , R.NativeConfiguredPublication R.NativeDefaultPublicationResolution a a False
              , R.NativeConfiguredPublication R.NativeDefaultPublicationResolution a b True
              , R.NativeLocalPublication R.NativeDefaultPublicationResolution a
              ]
        mapM_
          ( \changed ->
              assertBool
                "descriptor change has another ordinary digest"
                (R.nativePublicationDigest changed /= R.nativePublicationDigest original)
          )
          changes
    , temporary "another actual explicit capture cannot borrow the recorded publication" $ \root env -> do
        original <- capture root env "first-absent.dhall"
        reference <- fixture original root env R.NativeQualificationArtifact
        changed <- capture root env "second-absent.dhall"
        rejects R.NativePhysicalReadScopeMismatch
          =<< R.readNativeDetachedArtifact changed R.NativeQualificationArtifact reference
    , temporary "publication DATA substitution refuses before fetching an existing artifact" $ \root env -> do
        session <- capture root env "absent.dhall"
        reference <- fixture session root env R.NativeQualificationArtifact
        let changed = R.NativeLocalPublication R.NativeDefaultPublicationResolution (Text.replicate 64 "0")
        rejects R.NativePhysicalReadScopeMismatch
          =<< R.readNativeDetachedArtifact
            session
            R.NativeQualificationArtifact
            (reference {R.nativeRetainedObjectPublication = changed})
    , temporary "one closed artifact class cannot borrow another class key" $ \root env -> do
        session <- capture root env "absent.dhall"
        reference <- fixture session root env R.NativeQualificationArtifact
        mapM_
          ( \kind ->
              rejects R.NativePhysicalReadAddressInvalid =<< R.readNativeDetachedArtifact session kind reference
          )
          [R.NativeEvaluationReplayArtifact, R.NativeStoreLoadedReplayArtifact]
    , temporary "traversal alternate namespace extension and trailing key segments refuse" $ \root env -> do
        session <- capture root env "absent.dhall"
        reference <- fixture session root env R.NativeQualificationArtifact
        let key = R.nativeRetainedObjectKey reference
        mapM_
          ( \changed ->
              rejects R.NativePhysicalReadAddressInvalid
                =<< R.readNativeDetachedArtifact
                  session
                  R.NativeQualificationArtifact
                  (reference {R.nativeRetainedObjectKey = changed})
          )
          [ "../" <> key
          , key <> "/extra"
          , Text.replace ".cbor" ".txt" key
          , Text.replace "native-qualification" "ordinary-artifact" key
          , Text.replace "/product-row-DATA/" "/../" key
          ]
    , temporary "malformed SHA or filename identity cannot borrow an existing key" $ \root env -> do
        session <- capture root env "absent.dhall"
        reference <- fixture session root env R.NativeQualificationArtifact
        mapM_
          ( \changed ->
              rejects R.NativePhysicalReadAddressInvalid
                =<< R.readNativeDetachedArtifact
                  session
                  R.NativeQualificationArtifact
                  (reference {R.nativeRetainedObjectSha256 = changed})
          )
          ["", Text.replicate 64 "A", Text.replicate 63 "0", Text.replicate 64 "g"]
    , temporary "all closed classes reject zero and cap plus one before missing-file access" $ \root env -> do
        session <- capture root env "absent.dhall"
        mapM_
          ( \kind -> do
              key <- right (R.nativeDetachedArtifactKey kind experiment sha)
              mapM_
                ( \count ->
                    rejects R.NativePhysicalReadSizeInvalid
                      =<< R.readNativeDetachedArtifact
                        session
                        kind
                        (R.NativeRetainedObjectData key sha count (R.nativeRetentionPublication session))
                )
                [0, R.maximumNativeDetachedArtifactBytes kind + 1]
          )
          kinds
    , temporary "exact class caps pass preflight then honestly report the missing physical file" $ \root env -> do
        session <- capture root env "absent.dhall"
        mapM_
          ( \kind -> do
              key <- right (R.nativeDetachedArtifactKey kind experiment sha)
              rejects R.NativePhysicalReadLocalFailed
                =<< R.readNativeDetachedArtifact
                  session
                  kind
                  ( R.NativeRetainedObjectData
                      key
                      sha
                      (R.maximumNativeDetachedArtifactBytes kind)
                      (R.nativeRetentionPublication session)
                  )
          )
          kinds
    , temporary "smaller recorded count reads only count plus one and refuses extra actual bytes" $ \root env -> do
        session <- capture root env "absent.dhall"
        reference <- fixture session root env R.NativeQualificationArtifact
        rejects R.NativePhysicalReadBytesMismatch
          =<< R.readNativeDetachedArtifact
            session
            R.NativeQualificationArtifact
            (reference {R.nativeRetainedObjectBytes = R.nativeRetainedObjectBytes reference - 1})
    , temporary "larger recorded count refuses a truncated actual physical object" $ \root env -> do
        session <- capture root env "absent.dhall"
        reference <- fixture session root env R.NativeQualificationArtifact
        rejects R.NativePhysicalReadBytesMismatch
          =<< R.readNativeDetachedArtifact
            session
            R.NativeQualificationArtifact
            (reference {R.nativeRetainedObjectBytes = R.nativeRetainedObjectBytes reference + 1})
    , temporary "same length actual corruption refuses the recorded SHA" $ \root env -> do
        session <- capture root env "absent.dhall"
        reference <- fixture session root env R.NativeQualificationArtifact
        checkpointRoot <- runReaderT Writer.localCheckpointRoot env
        path <- right (Store.objectPathForKey checkpointRoot (R.nativeRetainedObjectKey reference))
        bytes <- BS.readFile path
        BS.writeFile path (BS.cons 0 (BS.tail bytes))
        rejects R.NativePhysicalReadBytesMismatch
          =<< R.readNativeDetachedArtifact session R.NativeQualificationArtifact reference
    , temporary "sparse gigabyte object refuses within the small recorded cap plus one" $ \root env -> do
        session <- capture root env "absent.dhall"
        reference <- fixture session root env R.NativeQualificationArtifact
        checkpointRoot <- runReaderT Writer.localCheckpointRoot env
        path <- right (Store.objectPathForKey checkpointRoot (R.nativeRetainedObjectKey reference))
        withBinaryFile path ReadWriteMode (\handle -> hSetFileSize handle (1024 * 1024 * 1024))
        result <-
          timeout 5000000 (R.readNativeDetachedArtifact session R.NativeQualificationArtifact reference)
        case result of
          Just actual -> rejects R.NativePhysicalReadBytesMismatch actual
          Nothing -> assertFailure "small bounded physical read did not terminate"
    , temporary "missing valid detached address reports an actual local read failure" $ \root env -> do
        session <- capture root env "absent.dhall"
        key <- right (R.nativeDetachedArtifactKey R.NativeQualificationArtifact experiment sha)
        rejects R.NativePhysicalReadLocalFailed
          =<< R.readNativeDetachedArtifact
            session
            R.NativeQualificationArtifact
            (R.NativeRetainedObjectData key sha 1 (R.nativeRetentionPublication session))
    , temporary "old allocation phase reader still rejects every detached class key" $ \root env -> do
        session <- capture root env "absent.dhall"
        mapM_
          ( \kind -> do
              reference <- fixture session root env kind
              rejects R.NativePhysicalReadAddressInvalid =<< R.readNativeRetainedObject session reference
          )
          kinds
    , temporary "detached reader cannot accept an old allocation address" $ \root env -> do
        session <- capture root env "absent.dhall"
        let reference =
              R.NativeRetainedObjectData
                ("jitml-checkpoints/native-rl-allocations-v1/" <> sha <> "/claim.cbor")
                sha
                1
                (R.nativeRetentionPublication session)
        rejects R.NativePhysicalReadAddressInvalid
          =<< R.readNativeDetachedArtifact session R.NativeQualificationArtifact reference
    , temporary "poisoned ordinary reference returns only closed synchronous failure DATA" $ \root env -> do
        session <- capture root env "absent.dhall"
        rejects R.NativePhysicalReadSynchronousFailure
          =<< R.readNativeDetachedArtifact
            session
            R.NativeQualificationArtifact
            (error "actual detached reference poison")
    , temporary "actual asynchronous ordinary reference cancellation propagates" $ \root env -> do
        session <- capture root env "absent.dhall"
        actual <-
          try (R.readNativeDetachedArtifact session R.NativeQualificationArtifact (throw ThreadKilled))
        case actual of
          Left ThreadKilled -> pure ()
          Left other -> assertFailure ("unexpected async exception: " <> show other)
          Right _ -> assertFailure "detached physical reader swallowed cancellation"
    ]

actualRead :: FilePath -> Env -> R.NativeDetachedArtifactKind -> IO ()
actualRead root env kind = do
  session <- capture root env "absent.dhall"
  reference <- fixture session root env kind
  actual <- right =<< R.readNativeDetachedArtifact session kind reference
  assertEqual "same actual physical kind" kind (R.nativeReadDetachedArtifactKind actual)
  assertEqual "same actual reference" reference (R.nativeReadDetachedArtifactReference actual)
  assertEqual "same actual local bytes" payload (R.nativeReadDetachedArtifactBytes actual)

fixture
  :: R.NativeRetentionSession
  -> FilePath
  -> Env
  -> R.NativeDetachedArtifactKind
  -> IO R.NativeRetainedObjectData
fixture session _root env kind = do
  key <- right (R.nativeDetachedArtifactKey kind experiment (sha256Hex payload))
  checkpointRoot <- runReaderT Writer.localCheckpointRoot env
  _ <- right =<< Store.writeObjectIfAbsent checkpointRoot key (LBS.fromStrict payload)
  pure
    ( R.NativeRetainedObjectData
        key
        (sha256Hex payload)
        (fromIntegral (BS.length payload))
        (R.nativeRetentionPublication session)
    )

temporary :: String -> (FilePath -> Env -> IO ()) -> TestTree
temporary title action = testCase title $ withSystemTempDirectory "jitml-native-detached-read-" $ \root -> do
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
experiment :: Text
experiment = "product-row-DATA"
payload :: BS.ByteString
payload = "ordinary physically stored DATA, not qualification or replay authority"
sha :: Text
sha = Text.replicate 64 "a"
kinds :: [R.NativeDetachedArtifactKind]
kinds =
  [R.NativeQualificationArtifact, R.NativeEvaluationReplayArtifact, R.NativeStoreLoadedReplayArtifact]
kindName :: R.NativeDetachedArtifactKind -> Text
kindName kind = case kind of
  R.NativeQualificationArtifact -> "native-qualification"
  R.NativeEvaluationReplayArtifact -> "native-evaluation-replay"
  R.NativeStoreLoadedReplayArtifact -> "native-store-loaded-replay"
right :: (Show e) => Either e a -> IO a
right value = case value of
  Right actual -> pure actual
  Left failure -> assertFailure (show failure) >> fail "unreachable"
rejects :: R.NativePhysicalReadFailure -> Either R.NativePhysicalReadFailure a -> IO ()
rejects expected actual = case actual of
  Left failure -> assertEqual "actual closed read failure" expected failure
  Right _ -> assertFailure "invalid input minted physical read"
