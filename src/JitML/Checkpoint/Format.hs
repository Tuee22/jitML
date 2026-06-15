{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Checkpoint.Format
  ( AdvancePredicate (..)
  , ArtifactPointer (..)
  , ArchitectureMetadata (..)
  , CheckpointManifest (..)
  , CheckpointPartKind (..)
  , MetricDirection (..)
  , ModelFamily (..)
  , OptimizerBlob (..)
  , OutputDecoder (..)
  , OutputDecoderKind (..)
  , PointerWrite (..)
  , PointerWriteResult (..)
  , PreprocessingMetadata (..)
  , RngBlob (..)
  , SubstrateArtifact (..)
  , TensorBlob (..)
  , TensorSpec (..)
  , WeightLayout (..)
  , advanceBestMaximised
  , advanceBestMinimised
  , advanceLatest
  , applyAdvancePredicate
  , applyPointerWrite
  , bestPointerKey
  , blobKey
  , decodeJmw1
  , decodeManifestCbor
  , defaultArchitectureMetadata
  , deriveExperimentHash
  , emptyManifest
  , encodeJmw1
  , encodeManifestCbor
  , latestPointerKey
  , manifestContentSha
  , manifestKey
  , manifestPointer
  , tensorSpecFromBlob
  , trialPointerKey
  , weightOnlyTensors
  )
where

import Codec.Serialise (Serialise, deserialiseOrFail, serialise)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.Bits (Bits, shiftL, shiftR, (.&.))
import Data.ByteString qualified as StrictByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Char (intToDigit)
import Data.List (sortOn)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word32, Word64, Word8)
import GHC.Float (castDoubleToWord64, castWord64ToDouble)
import GHC.Generics (Generic)

data CheckpointPartKind
  = WeightPart
  | OptimizerPart
  | RngPart
  deriving stock (Eq, Generic, Show, Ord)
  deriving anyclass (Serialise)

data TensorBlob = TensorBlob
  { tensorName :: Text
  , tensorShape :: [Int]
  , tensorBlobKey :: Text
  }
  deriving stock (Eq, Generic, Show, Ord)
  deriving anyclass (Serialise)

data OptimizerBlob = OptimizerBlob
  { optimizerKind :: Text
  , optimizerBlobKey :: Text
  , optimizerStateSize :: Int
  }
  deriving stock (Eq, Generic, Show, Ord)
  deriving anyclass (Serialise)

data RngBlob = RngBlob
  { rngStreamId :: Text
  , rngBlobKey :: Text
  , rngWordCount :: Int
  }
  deriving stock (Eq, Generic, Show, Ord)
  deriving anyclass (Serialise)

data ModelFamily
  = GenericModelFamily
  | SupervisedModelFamily
  | ReinforcementLearningPolicyFamily
  | AlphaZeroPolicyValueFamily
  | HyperparameterTuningFamily
  deriving stock (Eq, Generic, Show, Ord)
  deriving anyclass (Serialise)

data TensorSpec = TensorSpec
  { tensorSpecName :: Text
  , tensorSpecShape :: [Int]
  , tensorSpecDtype :: Text
  }
  deriving stock (Eq, Generic, Show, Ord)
  deriving anyclass (Serialise)

data ArchitectureMetadata = ArchitectureMetadata
  { architectureName :: Text
  , architectureModelFamily :: ModelFamily
  , architectureInputs :: [TensorSpec]
  , architectureOutputs :: [TensorSpec]
  }
  deriving stock (Eq, Generic, Show, Ord)
  deriving anyclass (Serialise)

data PreprocessingMetadata = PreprocessingMetadata
  { preprocessingName :: Text
  , preprocessingSteps :: [Text]
  , preprocessingInputs :: [TensorSpec]
  }
  deriving stock (Eq, Generic, Show, Ord)
  deriving anyclass (Serialise)

data OutputDecoderKind
  = ClassificationOutput
  | RegressionOutput
  | PolicyDistributionOutput
  | ValueEstimateOutput
  | MctsVisitDistributionOutput
  | ReplayArtifactOutput
  | GenericOutput
  deriving stock (Eq, Generic, Show, Ord)
  deriving anyclass (Serialise)

data OutputDecoder = OutputDecoder
  { outputDecoderName :: Text
  , outputDecoderKind :: OutputDecoderKind
  , outputDecoderLabels :: [Text]
  , outputDecoderUnits :: Maybe Text
  , outputDecoderArtifactKind :: Maybe Text
  }
  deriving stock (Eq, Generic, Show, Ord)
  deriving anyclass (Serialise)

data WeightLayout
  = FlatWeightLayout [TensorSpec]
  | NamedTensorWeightLayout [TensorSpec]
  deriving stock (Eq, Generic, Show, Ord)
  deriving anyclass (Serialise)

data ArtifactPointer = ArtifactPointer
  { artifactPointerKind :: Text
  , artifactPointerObjectKey :: Text
  , artifactPointerSha :: Maybe Text
  }
  deriving stock (Eq, Generic, Show, Ord)
  deriving anyclass (Serialise)

data SubstrateArtifact = SubstrateArtifact
  { substrateArtifactSubstrate :: Text
  , substrateArtifactKind :: Text
  , substrateArtifactCacheKey :: Text
  , substrateArtifactObjectKey :: Maybe Text
  }
  deriving stock (Eq, Generic, Show, Ord)
  deriving anyclass (Serialise)

data CheckpointManifest = CheckpointManifest
  { manifestId :: Text
  , manifestExperiment :: Text
  , manifestModelFamily :: ModelFamily
  , manifestArchitecture :: ArchitectureMetadata
  , manifestPreprocessing :: [PreprocessingMetadata]
  , manifestOutputDecoders :: [OutputDecoder]
  , manifestWeightLayout :: WeightLayout
  , manifestReplayPointers :: [ArtifactPointer]
  , manifestTranscriptPointers :: [ArtifactPointer]
  , manifestSubstrateArtifacts :: [SubstrateArtifact]
  , manifestTensors :: [TensorBlob]
  , manifestOptimizer :: [OptimizerBlob]
  , manifestRng :: [RngBlob]
  , manifestStep :: Word64
  , manifestMetrics :: [(Text, Double)]
  , manifestParentManifestSha :: Maybe Text
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

data PointerWrite = PointerWrite
  { pointerWriteKey :: Text
  , pointerWriteExpectedETag :: Maybe Text
  , pointerWriteManifestSha :: Text
  }
  deriving stock (Eq, Show)

data PointerWriteResult
  = PointerWritten Text
  | PointerConflict Text
  deriving stock (Eq, Show)

data Jmw1Header = Jmw1Header
  { jmw1Dtype :: Text
  , jmw1TensorCount :: Int
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

data MetricDirection
  = Maximise
  | Minimise
  deriving stock (Eq, Show)

-- | Typed advance predicates for the pointer-CAS step. The trainer picks the
-- predicate from the experiment Dhall's `metrics[i].direction` field per
-- README → Concurrency model.
data AdvancePredicate
  = AdvanceLatest
  | -- | metric name
    AdvanceBestMaximised Text
  | -- | metric name
    AdvanceBestMinimised Text
  deriving stock (Eq, Show)

advanceLatest :: AdvancePredicate
advanceLatest = AdvanceLatest

advanceBestMaximised :: Text -> AdvancePredicate
advanceBestMaximised = AdvanceBestMaximised

advanceBestMinimised :: Text -> AdvancePredicate
advanceBestMinimised = AdvanceBestMinimised

-- | Evaluate the advance predicate against the current and proposed manifests.
-- True means the pointer should advance to the proposed manifest.
applyAdvancePredicate
  :: AdvancePredicate
  -> Maybe CheckpointManifest
  -- ^ current pointer target
  -> CheckpointManifest
  -- ^ proposed
  -> Bool
applyAdvancePredicate _ Nothing _ = True
applyAdvancePredicate predicate (Just current) proposed =
  case predicate of
    AdvanceLatest ->
      manifestStep proposed > manifestStep current
    AdvanceBestMaximised metric ->
      lookupMetric metric proposed > lookupMetric metric current
    AdvanceBestMinimised metric ->
      lookupMetric metric proposed < lookupMetric metric current

lookupMetric :: Text -> CheckpointManifest -> Maybe Double
lookupMetric metric manifest =
  lookup metric (manifestMetrics manifest)

-- | Convenience builder. Use record syntax on the result to fill richer
-- manifests with optimizer / RNG / metric details.
emptyManifest :: Text -> Text -> [TensorBlob] -> CheckpointManifest
emptyManifest mid experiment tensors =
  CheckpointManifest
    { manifestId = mid
    , manifestExperiment = experiment
    , manifestModelFamily = GenericModelFamily
    , manifestArchitecture = defaultArchitectureMetadata GenericModelFamily
    , manifestPreprocessing = []
    , manifestOutputDecoders = []
    , manifestWeightLayout = NamedTensorWeightLayout (fmap tensorSpecFromBlob tensors)
    , manifestReplayPointers = []
    , manifestTranscriptPointers = []
    , manifestSubstrateArtifacts = []
    , manifestTensors = tensors
    , manifestOptimizer = []
    , manifestRng = []
    , manifestStep = 0
    , manifestMetrics = []
    , manifestParentManifestSha = Nothing
    }

defaultArchitectureMetadata :: ModelFamily -> ArchitectureMetadata
defaultArchitectureMetadata family =
  ArchitectureMetadata
    { architectureName = "unspecified"
    , architectureModelFamily = family
    , architectureInputs = []
    , architectureOutputs = []
    }

tensorSpecFromBlob :: TensorBlob -> TensorSpec
tensorSpecFromBlob tensor =
  TensorSpec
    { tensorSpecName = tensorName tensor
    , tensorSpecShape = tensorShape tensor
    , tensorSpecDtype = "F64"
    }

-- | The experiment hash: `sha256(resolved-dhall || substrate-fingerprint)`.
deriveExperimentHash :: Text -> Text -> Text
deriveExperimentHash resolvedDhall substrateFingerprint =
  hexBytes $
    SHA256.hash $
      Text.Encoding.encodeUtf8 (resolvedDhall <> "||" <> substrateFingerprint)

encodeJmw1 :: [Double] -> LazyByteString.ByteString
encodeJmw1 values =
  LazyByteString.fromStrict $
    StrictByteString.concat
      [ Text.Encoding.encodeUtf8 "JMW1"
      , word32Le (fromIntegral (LazyByteString.length header))
      , LazyByteString.toStrict header
      , StrictByteString.concat (fmap doubleLe values)
      ]
 where
  header =
    serialise
      Jmw1Header
        { jmw1Dtype = "F64"
        , jmw1TensorCount = length values
        }

decodeJmw1 :: LazyByteString.ByteString -> Either Text [Double]
decodeJmw1 payload = do
  let strict = LazyByteString.toStrict payload
      (magic, afterMagic) = StrictByteString.splitAt 4 strict
      (headerLengthBytes, afterHeaderLength) = StrictByteString.splitAt 4 afterMagic
  if magic /= Text.Encoding.encodeUtf8 "JMW1"
    then Left "unsupported .jmw1 magic"
    else do
      headerLength <- maybeToEither "truncated .jmw1 header length" (word32FromLe headerLengthBytes)
      let requestedHeaderLength = fromIntegral headerLength
          (headerBytes, tensorBytes) =
            StrictByteString.splitAt requestedHeaderLength afterHeaderLength
      if StrictByteString.length headerBytes /= requestedHeaderLength
        then Left "truncated .jmw1 header"
        else do
          header <- decodeJmw1Header (LazyByteString.fromStrict headerBytes)
          if jmw1Dtype header /= "F64"
            then Left ("unsupported .jmw1 dtype: " <> jmw1Dtype header)
            else decodeJmw1Doubles (jmw1TensorCount header) tensorBytes

decodeJmw1Header :: LazyByteString.ByteString -> Either Text Jmw1Header
decodeJmw1Header bytes =
  case deserialiseOrFail bytes of
    Left failure -> Left ("invalid .jmw1 header: " <> Text.pack (show failure))
    Right header -> Right header

decodeJmw1Doubles :: Int -> StrictByteString.ByteString -> Either Text [Double]
decodeJmw1Doubles count bytes
  | count < 0 = Left "invalid .jmw1 tensor count"
  | StrictByteString.length bytes /= count * 8 =
      Left "unexpected .jmw1 tensor payload length"
  | otherwise =
      traverse decodeDoubleAt [0 .. count - 1]
 where
  decodeDoubleAt index =
    castWord64ToDouble
      <$> maybeToEither
        "truncated .jmw1 double payload"
        (word64FromLe (StrictByteString.take 8 (StrictByteString.drop (index * 8) bytes)))

encodeManifestCbor :: CheckpointManifest -> LazyByteString.ByteString
encodeManifestCbor =
  serialise . canonicalManifest

decodeManifestCbor :: LazyByteString.ByteString -> Either Text CheckpointManifest
decodeManifestCbor payload =
  case deserialiseOrFail payload of
    Left failure -> Left (Text.pack (show failure))
    Right manifest -> Right manifest

manifestContentSha :: CheckpointManifest -> Text
manifestContentSha =
  hexBytes . SHA256.hashlazy . encodeManifestCbor

blobKey :: Text -> Text -> Text
blobKey experimentHash blobSha =
  "jitml-checkpoints/" <> experimentHash <> "/blobs/" <> blobSha

manifestKey :: Text -> Text -> Text
manifestKey experimentHash manifestSha =
  "jitml-checkpoints/" <> experimentHash <> "/manifests/" <> manifestSha <> ".cbor"

latestPointerKey :: Text -> Text
latestPointerKey experimentHash =
  "jitml-checkpoints/" <> experimentHash <> "/pointers/latest"

bestPointerKey :: Text -> Text -> Text
bestPointerKey experimentHash metricName =
  "jitml-checkpoints/" <> experimentHash <> "/pointers/best/" <> metricName

trialPointerKey :: Text -> Text -> Text
trialPointerKey experimentHash trialId =
  "jitml-checkpoints/" <> experimentHash <> "/pointers/trial/" <> trialId

manifestPointer :: CheckpointManifest -> Text
manifestPointer manifest =
  "jitml-checkpoints/"
    <> manifestExperiment manifest
    <> "/"
    <> manifestId manifest
    <> ".manifest.cbor"

-- | The inference path loads only weight-only blobs and skips optimizer/RNG
-- parts.
weightOnlyTensors :: CheckpointManifest -> [TensorBlob]
weightOnlyTensors = manifestTensors

applyPointerWrite :: Maybe Text -> PointerWrite -> PointerWriteResult
applyPointerWrite currentETag write
  | currentETag == pointerWriteExpectedETag write =
      PointerWritten (pointerWriteManifestSha write)
  | otherwise =
      PointerConflict (pointerWriteKey write)

canonicalManifest :: CheckpointManifest -> CheckpointManifest
canonicalManifest manifest =
  manifest
    { manifestTensors = sortOn tensorName (manifestTensors manifest)
    , manifestOptimizer = sortOn optimizerKind (manifestOptimizer manifest)
    , manifestRng = sortOn rngStreamId (manifestRng manifest)
    , manifestMetrics = sortOn fst (manifestMetrics manifest)
    , manifestArchitecture = canonicalArchitecture (manifestArchitecture manifest)
    , manifestPreprocessing =
        sortOn preprocessingName (fmap canonicalPreprocessing (manifestPreprocessing manifest))
    , manifestOutputDecoders = sortOn outputDecoderName (manifestOutputDecoders manifest)
    , manifestWeightLayout = canonicalWeightLayout (manifestWeightLayout manifest)
    , manifestReplayPointers = sortOn artifactPointerSortKey (manifestReplayPointers manifest)
    , manifestTranscriptPointers = sortOn artifactPointerSortKey (manifestTranscriptPointers manifest)
    , manifestSubstrateArtifacts =
        sortOn substrateArtifactSortKey (manifestSubstrateArtifacts manifest)
    }

canonicalArchitecture :: ArchitectureMetadata -> ArchitectureMetadata
canonicalArchitecture architecture =
  architecture
    { architectureInputs = sortOn tensorSpecName (architectureInputs architecture)
    , architectureOutputs = sortOn tensorSpecName (architectureOutputs architecture)
    }

canonicalPreprocessing :: PreprocessingMetadata -> PreprocessingMetadata
canonicalPreprocessing preprocessing =
  preprocessing
    { preprocessingInputs = sortOn tensorSpecName (preprocessingInputs preprocessing)
    }

canonicalWeightLayout :: WeightLayout -> WeightLayout
canonicalWeightLayout layout =
  case layout of
    FlatWeightLayout tensors ->
      FlatWeightLayout (sortOn tensorSpecName tensors)
    NamedTensorWeightLayout tensors ->
      NamedTensorWeightLayout (sortOn tensorSpecName tensors)

artifactPointerSortKey :: ArtifactPointer -> (Text, Text, Maybe Text)
artifactPointerSortKey pointer =
  (artifactPointerKind pointer, artifactPointerObjectKey pointer, artifactPointerSha pointer)

substrateArtifactSortKey :: SubstrateArtifact -> (Text, Text, Text, Maybe Text)
substrateArtifactSortKey artifact =
  ( substrateArtifactSubstrate artifact
  , substrateArtifactKind artifact
  , substrateArtifactCacheKey artifact
  , substrateArtifactObjectKey artifact
  )

hexBytes :: StrictByteString.ByteString -> Text
hexBytes =
  Text.pack . concatMap hexWord8 . StrictByteString.unpack

doubleLe :: Double -> StrictByteString.ByteString
doubleLe =
  word64Le . castDoubleToWord64

word32Le :: Word32 -> StrictByteString.ByteString
word32Le word =
  StrictByteString.pack
    [ byteAt 0 word
    , byteAt 8 word
    , byteAt 16 word
    , byteAt 24 word
    ]

word64Le :: Word64 -> StrictByteString.ByteString
word64Le word =
  StrictByteString.pack
    [ byteAt 0 word
    , byteAt 8 word
    , byteAt 16 word
    , byteAt 24 word
    , byteAt 32 word
    , byteAt 40 word
    , byteAt 48 word
    , byteAt 56 word
    ]

byteAt :: (Integral a, Bits a) => Int -> a -> Word8
byteAt offset word =
  fromIntegral ((word `shiftR` offset) .&. 0xff)

word32FromLe :: StrictByteString.ByteString -> Maybe Word32
word32FromLe bytes =
  case StrictByteString.unpack bytes of
    [b0, b1, b2, b3] ->
      Just
        ( fromIntegral b0
            + (fromIntegral b1 `shiftL` 8)
            + (fromIntegral b2 `shiftL` 16)
            + (fromIntegral b3 `shiftL` 24)
        )
    _ -> Nothing

word64FromLe :: StrictByteString.ByteString -> Maybe Word64
word64FromLe bytes =
  case StrictByteString.unpack bytes of
    [b0, b1, b2, b3, b4, b5, b6, b7] ->
      Just
        ( fromIntegral b0
            + (fromIntegral b1 `shiftL` 8)
            + (fromIntegral b2 `shiftL` 16)
            + (fromIntegral b3 `shiftL` 24)
            + (fromIntegral b4 `shiftL` 32)
            + (fromIntegral b5 `shiftL` 40)
            + (fromIntegral b6 `shiftL` 48)
            + (fromIntegral b7 `shiftL` 56)
        )
    _ -> Nothing

maybeToEither :: Text -> Maybe a -> Either Text a
maybeToEither message =
  maybe (Left message) Right

hexWord8 :: Word8 -> String
hexWord8 byte =
  [ intToDigit (fromIntegral byte `div` 16)
  , intToDigit (fromIntegral byte `mod` 16)
  ]
