{-# LANGUAGE OverloadedStrings #-}

-- Deliberately forgeable process/package fixtures exercise DATA preservation.
-- No fixture is an ObservedProducerProcess or a produced execution.
module NativePhaseProducer (nativePhaseProducerTests) where

import Control.Exception (AsyncException (UserInterrupt), throw, try)
import Data.ByteString qualified as BS
import Data.Text qualified as Text
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertEqual, assertFailure, testCase)

import JitML.Checkpoint.NativePhase.Graph
import JitML.Checkpoint.NativePhase.Producer
import JitML.Checkpoint.NativePhase.Projection (ProjectionFailure (..))
import JitML.Checkpoint.NativePhase.Schema
import JitML.Checkpoint.NativePhase.Types
import JitML.Execution.ProducerObservation qualified as Producer
import JitML.Product.SourceDigest qualified as Source

nativePhaseProducerTests :: TestTree
nativePhaseProducerTests =
  testGroup
    "native recorded producer DATA"
    [ testCase "all thirteen process fields retain their exact ordinary values" $ do
        d0 <- mustRight (mkDigest (BS.replicate 32 0))
        d1 <- mustRight (mkDigest (BS.replicate 32 0x11))
        (root, pool) <-
          mustRight =<< projectProducerContextData emptyNodePool (Just fixture) Nothing Nothing
        fields <- fieldsAt root pool
        before <- case fields of
          [VRef value, VNull, VNull] -> pure value
          _ -> assertFailure "producer bundle fields differ" >> fail "bad fixture"
        process <- fieldsAt before pool
        pid <- mustRight (magnitudeValue (Producer.recordedProcessId fixture))
        parent <- mustRight (magnitudeValue (Producer.recordedParentProcessId fixture))
        assertEqual
          "ordered exact process DATA"
          [ VText "/fixture/executable"
          , VDigest d0
          , VWord 123
          , pid
          , parent
          , VText "kernel"
          , VText "machine"
          , VText "release"
          , VText "build-os"
          , VText "build-arch"
          , VText "compiler"
          , VText "compiler-version"
          , VList [VText "/fixture/source", VList [VWord 1, VDigest d1]]
          ]
          process
        node <- required before pool
        decoded <- mustRight (decodeNodeData (nodeCanonicalBytes node))
        assertEqual "canonical bytes preserve every recorded field" node decoded
    , testCase "equal before and after observations share one exact node" $ do
        (root, pool) <-
          mustRight =<< projectProducerContextData emptyNodePool (Just fixture) (Just fixture) Nothing
        fields <- fieldsAt root pool
        case fields of
          [VRef before, VRef after, VNull] -> assertEqual "actual equal DATA interned" before after
          _ -> assertFailure "producer bundle fields differ"
        usage <- mustRight (validateReachableData [root] pool)
        assertEqual "bundle and one process node" 2 (usageNodes usage)
        assertEqual "two bundle edges and root" 3 (usageEdges usage)
    , testCase "all absent producer observations remain absent" $ do
        (root, pool) <- mustRight =<< projectProducerContextData emptyNodePool Nothing Nothing Nothing
        assertEqual "no nominal process or package replacement" [VNull, VNull, VNull] =<< fieldsAt root pool
    , testCase "both metadata coverage tags and optional package absence survive" $ do
        mapM_
          ( \(coverage, tag) -> do
              let actual = metadata {nativeMetadataCoverage = coverage}
              (root, pool) <- mustRight =<< projectProducerContextData emptyNodePool Nothing Nothing (Just actual)
              fields <- fieldsAt root pool
              reference <- case fields of
                [VNull, VNull, VRef value] -> pure value
                _ -> assertFailure "metadata reference differs" >> fail "bad fixture"
              assertEqual
                "exact metadata fields"
                [ VWord tag
                , VNull
                , VText "compiler-id"
                , VText "os"
                , VText "arch"
                , VText "random-package"
                , VText "random-version"
                , VNull
                , VNull
                , VWord 64
                ]
                =<< fieldsAt reference pool
          )
          [(ExternalCompiledPlanFileObservation, 0), (ExternallySuppliedPackageData, 1)]
    , testCase "UTF8 path bounds refuse the complete path without truncation" $ do
        let actual = fixture {Producer.recordedExecutableFilePath = replicate 4097 'x'}
        result <- projectProducerContextData emptyNodePool (Just actual) Nothing Nothing
        case result of
          Left (ProjectionDataRejected (ResourceExceeded PathTextBytes 4096 4097)) -> pure ()
          _ -> assertFailure "oversized path did not retain its precise refusal"
    , testCase "noncanonical executable digest refuses rather than normalizing" $ do
        let actual = fixture {Producer.recordedExecutableFileSha256 = Text.replicate 64 "A"}
        result <- projectProducerContextData emptyNodePool (Just actual) Nothing Nothing
        case result of
          Left (ProjectionDataRejected _) -> pure ()
          _ -> assertFailure "uppercase executable hash was accepted"
    , testCase "lazy process field faults remain synchronous projection failures" $ do
        let actual = fixture {Producer.recordedKernelRelease = error "fixture process field fault"}
        result <- projectProducerContextData emptyNodePool (Just actual) Nothing Nothing
        case result of
          Left (ProjectionSynchronousFailure _) -> pure ()
          _ -> assertFailure "lazy field escaped the safe materialization boundary"
    , testCase "async cancellation escapes the process DATA projection" $ do
        let actual = fixture {Producer.recordedKernelRelease = throw UserInterrupt}
        attempted <- try (projectProducerContextData emptyNodePool (Just actual) Nothing Nothing)
        case attempted of
          Left UserInterrupt -> pure ()
          Left _ -> assertFailure "unexpected asynchronous exception"
          Right _ -> assertFailure "async interruption became ordinary failure DATA"
    , testCase "whole unique producer closure independently enforces sixteen KiB" $ do
        let large =
              fixture
                { Producer.recordedExecutableFilePath = replicate 4096 'p'
                , Producer.recordedObservedSource =
                    Just (replicate 4096 's', Source.SourceStamp 1 (Text.replicate 64 "1"))
                }
            other = large {Producer.recordedProcessId = 1001}
        (root, pool) <-
          mustRight =<< projectProducerContextData emptyNodePool (Just large) (Just other) Nothing
        case producerClosureBytes root pool of
          Left (ResourceExceeded ProducerBundleBytes 16384 _) -> pure ()
          _ -> assertFailure "two complete distinct process records bypassed producer closure cap"
    ]

fixture :: Producer.RecordedProducerObservation
fixture =
  Producer.RecordedProducerObservation
    { Producer.recordedExecutableFilePath = "/fixture/executable"
    , Producer.recordedExecutableFileSha256 = Text.replicate 64 "0"
    , Producer.recordedExecutableFileByteCount = 123
    , Producer.recordedProcessId = 2 ^ (200 :: Int)
    , Producer.recordedParentProcessId = -123
    , Producer.recordedKernelOperatingSystem = "kernel"
    , Producer.recordedKernelMachine = "machine"
    , Producer.recordedKernelRelease = "release"
    , Producer.recordedBuildOperatingSystem = "build-os"
    , Producer.recordedBuildArchitecture = "build-arch"
    , Producer.recordedBuildCompiler = "compiler"
    , Producer.recordedBuildCompilerVersion = "compiler-version"
    , Producer.recordedObservedSource =
        Just ("/fixture/source", Source.SourceStamp 1 (Text.replicate 64 "1"))
    }

metadata :: NativeRuntimeMetadataData
metadata =
  NativeRuntimeMetadataData
    ExternalCompiledPlanFileObservation
    Nothing
    "compiler-id"
    "os"
    "arch"
    "random-package"
    "random-version"
    Nothing
    Nothing

fieldsAt :: Digest -> NodePool -> IO [NodeValue]
fieldsAt digest pool = nodeFields <$> required digest pool

required :: Digest -> NodePool -> IO NodeData
required digest pool = case lookupNode digest pool of
  Just node -> pure node
  Nothing -> assertFailure "missing projected node" >> fail "bad fixture"

mustRight :: (Show failure) => Either failure value -> IO value
mustRight value = case value of
  Right actual -> pure actual
  Left failure -> assertFailure (show failure) >> fail "fixture refinement failed"
