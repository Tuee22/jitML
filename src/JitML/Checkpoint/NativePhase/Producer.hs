-- | Ordinary process/package DATA only. A decoded or caller-supplied record
-- never constructs an observed process, origin or acknowledged phase.
module JitML.Checkpoint.NativePhase.Producer
  ( NativeRuntimeMetadataData (..)
  , NativeRuntimeMetadataCoverage (..)
  , projectProducerContextData
  ) where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Checkpoint.NativePhase.Context (digestFromCanonicalText)
import JitML.Checkpoint.NativePhase.Graph (NodePool)
import JitML.Checkpoint.NativePhase.Projection.Build
import JitML.Checkpoint.NativePhase.Types
import JitML.Execution.ProducerObservation qualified as Producer
import JitML.Product.SourceDigest qualified as Source

data NativeRuntimeMetadataCoverage
  = ExternalCompiledPlanFileObservation
  | ExternallySuppliedPackageData
  deriving stock (Eq, Show)

-- This deliberately forgeable record describes external observations. Neither
-- package IDs nor a plan FILE hash establish which code the process loaded.
data NativeRuntimeMetadataData = NativeRuntimeMetadataData
  { nativeMetadataCoverage :: !NativeRuntimeMetadataCoverage
  , nativeMetadataPlanSha :: !(Maybe Digest)
  , nativeMetadataCompilerId :: !Text
  , nativeMetadataOperatingSystem :: !Text
  , nativeMetadataArchitecture :: !Text
  , nativeMetadataRandomPackageId :: !Text
  , nativeMetadataRandomVersion :: !Text
  , nativeMetadataSplitmixPackageId :: !(Maybe Text)
  , nativeMetadataSplitmixVersion :: !(Maybe Text)
  }
  deriving stock (Eq, Show)

-- | The phase codec independently charges the complete unique producer bundle
-- against16KiB. Keep actual absence; no nominal process/package data is filled
-- in when the producer has not made an observation.
projectProducerContextData
  :: NodePool
  -> Maybe Producer.RecordedProducerObservation
  -> Maybe Producer.RecordedProducerObservation
  -> Maybe NativeRuntimeMetadataData
  -> IO (Either ProjectionFailure (Digest, NodePool))
projectProducerContextData pool before after metadata = projectSafely pool $ do
  beforeRef <- optional recordedProducer before
  afterRef <- optional recordedProducer after
  metadataRef <- optional runtimeMetadata metadata
  emit NProducerContextBundle [beforeRef, afterRef, metadataRef]

recordedProducer :: Producer.RecordedProducerObservation -> Build Digest
recordedProducer actual = do
  path <- textValue PathTextBytes (Text.pack (Producer.recordedExecutableFilePath actual))
  executable <- dataEither (digestFromCanonicalText (Producer.recordedExecutableFileSha256 actual))
  pid <- integerValue (Producer.recordedProcessId actual)
  parent <- integerValue (Producer.recordedParentProcessId actual)
  components <-
    traverse
      (textValue ProducerComponentBytes)
      [ Producer.recordedKernelOperatingSystem actual
      , Producer.recordedKernelMachine actual
      , Producer.recordedKernelRelease actual
      , Producer.recordedBuildOperatingSystem actual
      , Producer.recordedBuildArchitecture actual
      , Producer.recordedBuildCompiler actual
      , Producer.recordedBuildCompilerVersion actual
      ]
  observedSource <- case Producer.recordedObservedSource actual of
    Nothing -> pure VNull
    Just (root, stamp) -> do
      sourceRoot <- textValue PathTextBytes (Text.pack root)
      sourceSha <- dataEither (digestFromCanonicalText (Source.stampSha256 stamp))
      pure (VList [sourceRoot, VList [VWord (Source.stampAlgorithm stamp), VDigest sourceSha]])
  emit
    NRecordedProducer
    ( [path, VDigest executable, VWord (Producer.recordedExecutableFileByteCount actual), pid, parent]
        <> components
        <> [observedSource]
    )

runtimeMetadata :: NativeRuntimeMetadataData -> Build Digest
runtimeMetadata actual = do
  components <-
    traverse
      (textValue ProducerComponentBytes)
      [ nativeMetadataCompilerId actual
      , nativeMetadataOperatingSystem actual
      , nativeMetadataArchitecture actual
      ]
  randomPackage <- textValue GeneralTextBytes (nativeMetadataRandomPackageId actual)
  randomVersion <- textValue ProducerComponentBytes (nativeMetadataRandomVersion actual)
  splitmixPackage <-
    maybe (pure VNull) (textValue GeneralTextBytes) (nativeMetadataSplitmixPackageId actual)
  splitmixVersion <-
    maybe (pure VNull) (textValue ProducerComponentBytes) (nativeMetadataSplitmixVersion actual)
  let coverage = case nativeMetadataCoverage actual of
        ExternalCompiledPlanFileObservation -> 0
        ExternallySuppliedPackageData -> 1
      plan = maybe VNull VDigest (nativeMetadataPlanSha actual)
  emit
    NRuntimeMetadata
    ( [VWord coverage, plan]
        <> components
        <> [randomPackage, randomVersion, splitmixPackage, splitmixVersion, VWord 64]
    )
