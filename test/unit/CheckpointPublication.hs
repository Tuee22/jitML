{-# LANGUAGE OverloadedStrings #-}

-- | Real temporary files, public Store transactions and the filesystem MinIO
-- interpreter exercise transport/resolution predicates. Synthetic completion
-- fixtures are not training, a live server, or real-device execution evidence.
module CheckpointPublication (checkpointPublicationTests) where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ReaderT, ask, runReaderT)
import Data.Aeson (encode)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Data.Text qualified as Text
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Posix.Files (createSymbolicLink)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Checkpoint.Store qualified as Store
import JitML.Checkpoint.WeightCodec qualified as WeightCodec
import JitML.Checkpoint.Writer qualified as Writer
import JitML.Cluster.Publication qualified as Publication
import JitML.Service.BootConfig qualified as Boot
import JitML.Service.Capabilities
  ( BucketName (..)
  , ETag (..)
  , HasMinIO (..)
  , ObjectKey (..)
  , ObjectRef (..)
  )
import JitML.Service.Clients qualified as Clients
import JitML.Service.FilesystemMinIO (runFilesystemMinIO)
import JitML.Service.MinIOSubprocess qualified as MinIO
import JitML.Service.PulsarWebSocketSubprocess qualified as Pulsar
import JitML.Service.Retry (ServiceError (..))
import JitML.Service.WorkerPublication qualified as Worker
import JitML.Substrate (Substrate (LinuxCPU))
import JitML.Test.ContractFixtures qualified as Fixtures

checkpointPublicationTests :: TestTree
checkpointPublicationTests =
  testGroup
    "worker checkpoint publication"
    [ temporary "absent mounted and host publication sources retain offline local behavior" $ \root -> do
        resolved <- expectRight =<< Worker.resolveWorkerLiveContextAt (root </> "absent-boot.dhall") root
        case resolved of
          Nothing -> pure ()
          Just _ -> assertFailure "offline resolution manufactured a remote publication"
    , temporary
        "mounted service configuration supplies actual worker coordinates without a host publication"
        $ \root -> do
          let boot =
                (Boot.defaultBootConfig LinuxCPU Boot.Cluster)
                  { Boot.bootMinioEndpoint = "http://minio.fixture.invalid:9000/actual/prefix"
                  , Boot.bootPulsarServiceUrl = "pulsar://broker.fixture.invalid:6650"
                  }
              path = root </> "BootConfig.dhall"
          writeBoot path boot
          context <- resolvedContext path root
          Worker.workerLiveUsesMountedServices context @?= True
          Worker.workerLiveMinIOSettings context
            @?= Clients.engineMinIOSettings (Clients.engineClientSettingsForBootConfig boot)
          MinIO.minioEndpoint (Worker.workerLiveMinIOSettings context) @?= "http://minio.fixture.invalid:9000"
          MinIO.minioRequestPathPrefix (Worker.workerLiveMinIOSettings context) @?= "/actual/prefix"
          Worker.workerLivePulsarSettings context
            @?= Clients.enginePulsarSettings (Clients.engineClientSettingsForBootConfig boot)
          Publication.publicationSubstrate (Worker.workerLivePublication context) @?= LinuxCPU
    , temporary "a valid mounted service source takes precedence over an invalid host publication" $ \root -> do
        let path = root </> "BootConfig.dhall"
        writeBoot path (Boot.defaultBootConfig LinuxCPU Boot.Cluster)
        writePublicationBytes root "invalid host bytes"
        context <- resolvedContext path root
        Worker.workerLiveUsesMountedServices context @?= True
    , temporary "a malformed present mount fails before any valid host fallback" $ \root -> do
        let path = root </> "BootConfig.dhall"
        writeFile path "not a BootConfig"
        writePublication root (Publication.markPublicationLive (Publication.defaultPublication LinuxCPU))
        Worker.resolveWorkerLiveContextAt path root >>= assertLeftContains path
    , temporary "a configured directory cannot be treated as an absent mount" $ \root -> do
        let path = root </> "BootConfig.dhall"
        createDirectoryIfMissing True path
        Worker.resolveWorkerLiveContextAt path root >>= assertLeftContains path
    , temporary
        "a dangling mounted configuration is present and cannot fall back to a valid host publication"
        $ \root -> do
          let path = root </> "BootConfig.dhall"
          createSymbolicLink (root </> "missing-boot-target.dhall") path
          writePublication root (Publication.markPublicationLive (Publication.defaultPublication LinuxCPU))
          Worker.resolveWorkerLiveContextAt path root >>= assertLeftContains path
    , temporary "a dangling host publication cannot become an offline success" $ \root -> do
        let directory = root </> ".build" </> "runtime"
            path = directory </> "cluster-publication.json"
        createDirectoryIfMissing True directory
        createSymbolicLink (root </> "missing-publication-target.json") path
        Worker.resolveWorkerLiveContextAt (root </> "absent.dhall") root >>= assertLeftContains path
    , temporary "a non-directory mounted path component fails instead of using a valid host fallback" $ \root -> do
        let parent = root </> "not-a-directory"
            path = parent </> "BootConfig.dhall"
        writeFile parent "ordinary file"
        writePublication root (Publication.markPublicationLive (Publication.defaultPublication LinuxCPU))
        Worker.resolveWorkerLiveContextAt path root >>= assertLeftContains path
    , temporary "a non-directory host publication path component cannot become offline" $ \root -> do
        let parent = root </> ".build"
            path = parent </> "runtime" </> "cluster-publication.json"
        writeFile parent "ordinary file"
        Worker.resolveWorkerLiveContextAt (root </> "absent.dhall") root >>= assertLeftContains path
    , temporary "valid symbolic links preserve the mounted configuration semantics" $ \root -> do
        let target = root </> "actual-boot.dhall"
            path = root </> "BootConfig.dhall"
            boot = Boot.defaultBootConfig LinuxCPU Boot.Cluster
        writeBoot target boot
        createSymbolicLink target path
        context <- resolvedContext path root
        Worker.workerLiveUsesMountedServices context @?= True
        Worker.workerLiveMinIOSettings context
          @?= Clients.engineMinIOSettings (Clients.engineClientSettingsForBootConfig boot)
    , temporary "an actual host publication preserves the leased edge endpoint and prefix" $ \root -> do
        let publication =
              (Publication.markPublicationLive (Publication.defaultPublication LinuxCPU))
                { Publication.publicationEdgePort = 18123
                }
        writePublication root publication
        context <- resolvedContext (root </> "absent.dhall") root
        Worker.workerLiveUsesMountedServices context @?= False
        Worker.workerLivePublication context @?= publication
        Worker.workerLiveMinIOSettings context @?= MinIO.minioSettingsForLocalEdge 18123
        Worker.workerLivePulsarSettings context @?= Pulsar.pulsarSettingsForLocalEdge 18123
    , temporary "malformed or non-live present host publications never become offline successes" $ \root -> do
        writePublicationBytes root "malformed publication"
        Worker.resolveWorkerLiveContextAt (root </> "absent.dhall") root
          >>= assertLeftContains "not a valid live publication"
        writePublication root (Publication.defaultPublication LinuxCPU)
        Worker.resolveWorkerLiveContextAt (root </> "absent.dhall") root
          >>= assertLeftContains "not a valid live publication"
    , temporary "candidate mirror readback binds the actual durable commit and physical JMW1 bytes" $ \root -> do
        (prepared, stored) <- candidateSnapshot root
        runFilesystemMinIO root (Writer.verifyRemoteCheckpointSnapshot prepared stored) >>= (@?= Right ())
        let pointer =
              Checkpoint.latestPointerKey
                (Checkpoint.manifestExperiment (Store.preparedSnapshotManifest prepared))
        Store.storedPointerResult stored @?= Checkpoint.PointerNotWritten pointer
    , temporary
        "completed mirror readback preserves exact serialized completion without minting product eligibility"
        $ \root ->
          Fixtures.withSupervisedProductFixture $ \row problem projection -> do
            parts <- Fixtures.productCompletionParts row problem projection Nothing
            let manifest = Fixtures.pcpManifest parts
                intent = Store.WriterLatestPointerIntent (Checkpoint.latestPointerKey (Fixtures.pcpExperiment parts))
            prepared <-
              expectRight
                ( Store.prepareCheckpointSnapshot
                    Store.WriterCompletedSnapshot
                    intent
                    manifest
                    (Fixtures.pcpPayloads parts)
                )
            written <-
              expectRight
                =<< runFilesystemMinIO
                  root
                  ( Store.writeCompletedCheckpointSnapshotWithMinIO
                      Nothing
                      (Fixtures.pcpCompleted parts)
                      manifest
                      (Fixtures.pcpPayloads parts)
                  )
            runFilesystemMinIO
              root
              (Writer.verifyRemoteCheckpointSnapshot prepared (Store.completedStoredCheckpoint written))
              >>= (@?= Right ())
            actual <-
              expectRight
                =<< runFilesystemMinIO
                  root
                  (Store.admitCheckpointAt (Fixtures.pcpExperiment parts) (Store.preparedSnapshotManifestSha prepared))
            Checkpoint.manifestCompletedTraining (Store.admittedCheckpointManifest actual)
              @?= Just (Fixtures.pcpCompleted parts)
    , temporary "substituted remote receipt addresses and namespaces fail before acceptance" $ \root -> do
        (prepared, stored) <- candidateSnapshot root
        mapM_
          ( \(changed, fragment) ->
              runFilesystemMinIO root (Writer.verifyRemoteCheckpointSnapshot prepared changed)
                >>= assertLeftContains fragment
          )
          [ (stored {Store.storedManifestSha = Text.replicate 64 "a"}, "substituted manifest address")
          ,
            ( stored {Store.storedManifestObjectKey = "jitml-checkpoints/foreign/manifest.cbor"}
            , "substituted manifest key"
            )
          ,
            ( stored {Store.storedManifestBodySha = Just (Text.replicate 64 "b")}
            , "substituted manifest body address"
            )
          ]
    , temporary "missing immutable manifest or durable commit cannot pass remote readback" $ \root -> do
        (prepared, stored) <- candidateSnapshot root
        let commitRef = Store.checkpointObjectRef (Store.writerCommitObjectKey (Store.preparedSnapshotCommit prepared))
        expectRight =<< runFilesystemMinIO root (deleteObject commitRef)
        runFilesystemMinIO root (Writer.verifyRemoteCheckpointSnapshot prepared stored)
          >>= assertLeftContains "commit"
        -- Restore through the real idempotent writer, then remove the manifest.
        (_, restored) <- candidateSnapshot root
        expectRight
          =<< runFilesystemMinIO
            root
            (deleteObject (Store.checkpointObjectRef (Store.storedManifestObjectKey restored)))
        runFilesystemMinIO root (Writer.verifyRemoteCheckpointSnapshot prepared restored)
          >>= assertLeftContains "manifest"
    , temporary "tampered physical tensor bytes fail the production Store binding" $ \root -> do
        (prepared, stored) <- candidateSnapshot root
        case Store.preparedSnapshotPayloads prepared of
          [(key, _)] -> BS.writeFile (objectPath root (Store.checkpointObjectRef key)) "tampered physical JMW1"
          _ -> assertFailure "candidate snapshot did not contain one physical tensor"
        runFilesystemMinIO root (Writer.verifyRemoteCheckpointSnapshot prepared stored)
          >>= assertLeftContains "physical readback failed"
    , temporary "binary artifacts are create-only and exact-byte readable after new or identical writes" $ \root -> do
        let ref = Store.checkpointObjectRef "jitml-checkpoints/attempt/artifacts/raw.cbor"
        runFilesystemMinIO root (Writer.writeVerifiedRemoteArtifact ref "raw retained bytes")
          >>= (@?= Right ())
        runFilesystemMinIO root (Writer.writeVerifiedRemoteArtifact ref "raw retained bytes")
          >>= (@?= Right ())
        runFilesystemMinIO root (Writer.writeVerifiedRemoteArtifact ref "different bytes")
          >>= assertLeftContains "different bytes"
        runFilesystemMinIO root (minioReadBytes ref) >>= (@?= Right "raw retained bytes")
    , testCase "a successful artifact PUT acknowledgement cannot bypass a failed exact-byte readback" $ do
        calls <- newIORef []
        result <-
          runReaderT
            ( unAcknowledgementOnly
                (Writer.writeVerifiedRemoteArtifact (Store.checkpointObjectRef "attempt/raw") "bytes")
            )
            calls
        assertLeftContains "exact-byte readback failed" result
        readIORef calls >>= (@?= ["put", "read"])
    ]

temporary :: String -> (FilePath -> Assertion) -> TestTree
temporary name body = testCase name (withSystemTempDirectory "jitml-worker-publication" body)

resolvedContext :: FilePath -> FilePath -> IO Worker.WorkerLiveContext
resolvedContext path root = do
  resolved <- expectRight =<< Worker.resolveWorkerLiveContextAt path root
  maybe (assertFailure "configured fixture returned no worker context") pure resolved

writeBoot :: FilePath -> Boot.BootConfig -> IO ()
writeBoot path = writeFile path . Text.unpack . Boot.renderBootConfigDhall

writePublication :: FilePath -> Publication.ClusterPublication -> IO ()
writePublication root = writePublicationBytes root . LBS.toStrict . encode

writePublicationBytes :: FilePath -> BS.ByteString -> IO ()
writePublicationBytes root bytes = do
  let directory = root </> ".build" </> "runtime"
  createDirectoryIfMissing True directory
  BS.writeFile (directory </> "cluster-publication.json") bytes

candidateSnapshot :: FilePath -> IO (Store.PreparedCheckpointSnapshot, Store.StoredCheckpoint)
candidateSnapshot root = do
  let experiment = "generic-mirror-candidate"
      payload = WeightCodec.encodeJmw1 [1, 2, 3, 4]
      key = Checkpoint.blobKey experiment (WeightCodec.jmw1ContentSha payload)
      manifest =
        (Checkpoint.emptyManifest "remote-mirror" experiment [Checkpoint.TensorBlob "weights" [4] key])
          { Checkpoint.manifestMetrics = [("z", 2), ("a", 1)]
          }
      payloads = [(key, payload)]
  prepared <-
    expectRight
      ( Store.prepareCheckpointSnapshot
          Store.WriterCandidateSnapshot
          Store.WriterNoPointerIntent
          manifest
          payloads
      )
  written <-
    expectRight
      =<< runFilesystemMinIO root (Store.writeCandidateCheckpointSnapshotWithMinIO manifest payloads)
  pure (prepared, Store.candidateStoredCheckpoint written)

objectPath :: FilePath -> ObjectRef -> FilePath
objectPath root ref =
  root </> Text.unpack (unBucketName (objectBucket ref)) </> Text.unpack (unObjectKey (objectKey ref))

-- Deliberately adversarial transport: it acknowledges PUT without making bytes
-- readable. This proves the production helper requires readback on success too.
newtype AcknowledgementOnly value = AcknowledgementOnly
  {unAcknowledgementOnly :: ReaderT (IORef [Text]) IO value}
  deriving newtype (Functor, Applicative, Monad)

instance HasMinIO AcknowledgementOnly where
  minioPutIfAbsent _ _ = pure (Left (SETransient "unexpected text write"))
  minioReadObject _ = pure (Left (SETransient "unexpected text read"))
  minioReadBytes _ = do
    record "read"
    pure (Left (SENotFound "acknowledgement did not persist bytes"))
  putBlobIfAbsent _ _ = pure (Left (SETransient "unexpected text blob write"))
  putBlobBytesIfAbsent _ _ = do
    record "put"
    pure (Right (ETag "acknowledged"))
  casPointer _ _ _ = pure (Left (SETransient "unexpected pointer CAS"))
  listObjects _ _ = pure (Left (SETransient "unexpected list"))
  deleteObject _ = pure (Left (SETransient "unexpected delete"))

record :: Text -> AcknowledgementOnly ()
record label = AcknowledgementOnly $ do
  calls <- ask
  liftIO (modifyIORef' calls (<> [label]))

expectRight :: (Show err) => Either err value -> IO value
expectRight = either (assertFailure . show) pure

assertLeftContains :: (Show err) => String -> Either err value -> Assertion
assertLeftContains fragment result = case result of
  Left failure ->
    assertBool
      ("wrong rejection: " <> show failure)
      (Text.pack fragment `Text.isInfixOf` Text.pack (show failure))
  Right _ -> assertFailure "adversarial input was accepted"
