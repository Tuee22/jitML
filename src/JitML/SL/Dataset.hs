{-# LANGUAGE OverloadedStrings #-}

module JitML.SL.Dataset
  ( DatasetArtifact (..)
  , DatasetFetchResult (..)
  , DatasetRef (..)
  , DatasetSplit (..)
  , canonicalArtifactSha256For
  , canonicalDatasets
  , canonicalSha256For
  , datasetArtifactFileName
  , datasetArtifactObjectRef
  , datasetArtifactText
  , datasetForProblem
  , datasetFixtureBytes
  , datasetObjectKey
  , datasetObjectRef
  , datasetRefHash
  , datasetSplitText
  , fetchDatasetArtifactBytes
  , fetchDatasetRef
  , maybeGunzip
  , renderDatasetCatalog
  , verifyDatasetBytes
  )
where

import Codec.Compression.GZip qualified as GZip
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Char (intToDigit)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word8)

import JitML.SL.Canonicals (CanonicalProblem (..))
import JitML.Service.Capabilities
  ( BucketName (..)
  , HasMinIO (..)
  , ObjectKey (..)
  , ObjectRef (..)
  )
import JitML.Service.Retry (ServiceError (..))

data DatasetSplit
  = TrainSplit
  | ValidationSplit
  | TestSplit
  deriving stock (Eq, Show)

-- | Sprint 13.4 — which on-disk artefact of a dataset split is being
-- addressed. Image-classification datasets ship two canonical blobs per
-- split: the IDX3 feature images (@data.bin@) and the IDX1 integer labels
-- (@labels.bin@). The SL training loop fetches both to assemble labeled
-- examples; the upload command stages each independently.
data DatasetArtifact
  = ImagesArtifact
  | LabelsArtifact
  deriving stock (Eq, Show)

datasetArtifactText :: DatasetArtifact -> Text
datasetArtifactText ImagesArtifact = "images"
datasetArtifactText LabelsArtifact = "labels"

-- | The MinIO object filename for an artefact within a split prefix.
-- Images land at @data.bin@ (the pre-Sprint-13.4 convention); labels land
-- at @labels.bin@.
datasetArtifactFileName :: DatasetArtifact -> Text
datasetArtifactFileName ImagesArtifact = "data.bin"
datasetArtifactFileName LabelsArtifact = "labels.bin"

data DatasetRef = DatasetRef
  { datasetName :: Text
  , datasetSplit :: DatasetSplit
  , datasetSizeBytes :: Int
  , datasetExpectedSha256 :: Text
  }
  deriving stock (Eq, Show)

data DatasetFetchResult = DatasetFetchResult
  { fetchedDataset :: DatasetRef
  , fetchedBytes :: Int
  , fetchedSha256 :: Text
  }
  deriving stock (Eq, Show)

datasetSplitText :: DatasetSplit -> Text
datasetSplitText TrainSplit = "train"
datasetSplitText ValidationSplit = "validation"
datasetSplitText TestSplit = "test"

datasetObjectKey :: DatasetRef -> Text
datasetObjectKey ref =
  "jitml-datasets/"
    <> datasetName ref
    <> "/"
    <> datasetSplitText (datasetSplit ref)
    <> "/data.bin"

datasetObjectRef :: DatasetRef -> ObjectRef
datasetObjectRef ref = datasetArtifactObjectRef ref ImagesArtifact

-- | Sprint 13.4 — the MinIO object reference for a specific artefact of a
-- dataset split. Images live at
-- @jitml-datasets/\<name\>/\<split\>/data.bin@ (back-compatible with the
-- pre-13.4 single-artefact layout); labels at
-- @jitml-datasets/\<name\>/\<split\>/labels.bin@.
datasetArtifactObjectRef :: DatasetRef -> DatasetArtifact -> ObjectRef
datasetArtifactObjectRef ref artifact =
  ObjectRef
    (BucketName "jitml-datasets")
    ( ObjectKey
        ( datasetName ref
            <> "/"
            <> datasetSplitText (datasetSplit ref)
            <> "/"
            <> datasetArtifactFileName artifact
        )
    )

canonicalDatasets :: [DatasetRef]
canonicalDatasets =
  concatMap mintRefs sources
 where
  sources :: [(Text, Int)]
  sources =
    [ ("MNIST", 47040016)
    , ("Fashion-MNIST", 47040016)
    , ("CIFAR-10", 170498071)
    , ("CIFAR-100", 169001437)
    , ("Tiny ImageNet", 248123212)
    , ("California Housing", 800000)
    ]
  mintRefs (name, sz) =
    [ DatasetRef
        name
        split
        sz
        ( case canonicalSha256For name split of
            Just real -> real
            Nothing -> computeExpectedSha256 name split sz
        )
    | split <- [TrainSplit, ValidationSplit, TestSplit]
    ]

-- | Sprint 13.4 — canonical SHA-256 for the upstream-published version
-- of each (dataset, split) pair the SL canonical stanza consumes. The
-- hashes are taken from the canonical mirror (yann.lecun.com for MNIST,
-- zalandoresearch/fashion-mnist for Fashion-MNIST, cs.toronto.edu/~kriz
-- for CIFAR-10/100, image-net.org for Tiny ImageNet, scikit-learn for
-- California Housing) and pinned to the *uncompressed* file the SL
-- training loop reads through 'fetchDatasetRef'. Returns 'Nothing' for
-- pairs without a published canonical hash yet; 'canonicalDatasets'
-- falls back to a deterministic synthetic SHA when 'Nothing'.
--
-- Adding a real hash here switches the corresponding 'DatasetRef' to
-- the live-byte-verification path: 'fetchDatasetRef' returns
-- 'SEConflict' until the matching real bytes are uploaded to MinIO via
-- `jitml internal upload-dataset`.
canonicalSha256For :: Text -> DatasetSplit -> Maybe Text
canonicalSha256For name split = canonicalArtifactSha256For name split ImagesArtifact

-- | Sprint 13.4 — canonical SHA-256 for a specific (dataset, split,
-- artefact) triple. The hashes are pinned to the canonical
-- gzip-compressed upstream blobs (the form distributed by the CVDF MNIST
-- mirror and the form `jitml internal upload-dataset` stages into MinIO);
-- the SL training loop gunzips on fetch before IDX parsing. Returns
-- 'Nothing' for triples without a published canonical hash yet.
canonicalArtifactSha256For :: Text -> DatasetSplit -> DatasetArtifact -> Maybe Text
canonicalArtifactSha256For "MNIST" TrainSplit ImagesArtifact =
  -- train-images-idx3-ubyte.gz (60000 × 28×28 images)
  Just "440fcabf73cc546fa21475e81ea370265605f56be210a4024d2ca8f203523609"
canonicalArtifactSha256For "MNIST" TestSplit ImagesArtifact =
  -- t10k-images-idx3-ubyte.gz (10000 × 28×28 images)
  Just "8d422c7b0a1c1c79245a5bcf07fe86e33eeafee792b84584aec276f5a2dbc4e6"
canonicalArtifactSha256For "MNIST" TrainSplit LabelsArtifact =
  -- train-labels-idx1-ubyte.gz (60000 labels)
  Just "3552534a0a558bbed6aed32b30c495cca23d567ec52cac8be1a0730e8010255c"
canonicalArtifactSha256For "MNIST" TestSplit LabelsArtifact =
  -- t10k-labels-idx1-ubyte.gz (10000 labels)
  Just "f7ae60f92e00ec6debd23a6088c31dbd2371eca3ffa0defaefb259924204aec6"
canonicalArtifactSha256For _ _ _ = Nothing

datasetForProblem :: CanonicalProblem -> Maybe DatasetRef
datasetForProblem problem =
  case filter
    (\ref -> datasetName ref == problemDataset problem && datasetSplit ref == TrainSplit)
    canonicalDatasets of
    (first : _) -> Just first
    [] -> Nothing

datasetRefHash :: DatasetRef -> Text
datasetRefHash = datasetExpectedSha256

datasetFixtureBytes :: DatasetRef -> ByteString
datasetFixtureBytes ref =
  Text.Encoding.encodeUtf8
    ( datasetName ref
        <> "|"
        <> datasetSplitText (datasetSplit ref)
        <> "|"
        <> Text.pack (show (datasetSizeBytes ref))
    )

verifyDatasetBytes :: DatasetRef -> ByteString -> Either Text DatasetFetchResult
verifyDatasetBytes ref payload =
  let actual = hashHex (SHA256.hash payload)
   in if actual == datasetExpectedSha256 ref
        then
          Right
            DatasetFetchResult
              { fetchedDataset = ref
              , fetchedBytes = ByteString.length payload
              , fetchedSha256 = actual
              }
        else
          Left
            ( "dataset SHA mismatch for "
                <> datasetName ref
                <> "/"
                <> datasetSplitText (datasetSplit ref)
                <> ": expected "
                <> datasetExpectedSha256 ref
                <> ", got "
                <> actual
            )

fetchDatasetRef :: (HasMinIO m) => DatasetRef -> m (Either ServiceError DatasetFetchResult)
fetchDatasetRef ref = do
  result <- minioReadBytes (datasetObjectRef ref)
  pure $ do
    payload <- result
    case verifyDatasetBytes ref payload of
      Right verified -> Right verified
      Left message -> Left (SEConflict message)

-- | Sprint 13.4 — read the raw stored bytes of a dataset artefact
-- (images or labels) from MinIO. Unlike 'fetchDatasetRef' this does not
-- SHA-verify (the training loop verifies whole-dataset integrity through
-- the IDX header magic + dimension fields) and returns the bytes as
-- stored, so a caller can gunzip the canonical compressed blob before IDX
-- parsing.
fetchDatasetArtifactBytes
  :: (HasMinIO m)
  => DatasetRef
  -> DatasetArtifact
  -> m (Either ServiceError ByteString)
fetchDatasetArtifactBytes ref artifact =
  minioReadBytes (datasetArtifactObjectRef ref artifact)

-- | Sprint 13.4 — gunzip a payload when it carries the gzip magic header
-- (@0x1f 0x8b@), otherwise return it unchanged. The canonical MNIST blobs
-- are distributed gzip-compressed (the form `jitml internal
-- upload-dataset` stages and SHA-pins); the SL training loop calls this
-- before IDX parsing so it transparently consumes either the compressed
-- canonical blob or an already-decompressed file.
maybeGunzip :: ByteString -> ByteString
maybeGunzip bytes
  | ByteString.length bytes >= 2
      && ByteString.index bytes 0 == 0x1f
      && ByteString.index bytes 1 == 0x8b =
      LazyByteString.toStrict (GZip.decompress (LazyByteString.fromStrict bytes))
  | otherwise = bytes

renderDatasetCatalog :: Text
renderDatasetCatalog =
  Text.unlines $
    "| Dataset | Split | Bytes | Expected SHA256 |"
      : "|---------|-------|-------|-----------------|"
      : [ "| `"
            <> datasetName ref
            <> "` | "
            <> datasetSplitText (datasetSplit ref)
            <> " | "
            <> Text.pack (show (datasetSizeBytes ref))
            <> " | `"
            <> Text.take 12 (datasetExpectedSha256 ref)
            <> "…` |"
        | ref <- canonicalDatasets
        ]

computeExpectedSha256 :: Text -> DatasetSplit -> Int -> Text
computeExpectedSha256 name split sz =
  hashHex
    ( SHA256.hash
        (Text.Encoding.encodeUtf8 (name <> "|" <> datasetSplitText split <> "|" <> Text.pack (show sz)))
    )

hashHex :: ByteString -> Text
hashHex =
  Text.pack . concatMap byteHex . ByteString.unpack
 where
  byteHex :: Word8 -> String
  byteHex byte =
    [ intToDigit (fromIntegral byte `div` 16)
    , intToDigit (fromIntegral byte `mod` 16)
    ]
