{-# LANGUAGE OverloadedStrings #-}

module JitML.SL.Dataset
  ( DatasetFetchResult (..)
  , DatasetRef (..)
  , DatasetSplit (..)
  , canonicalDatasets
  , canonicalSha256For
  , datasetForProblem
  , datasetFixtureBytes
  , datasetObjectKey
  , datasetObjectRef
  , datasetRefHash
  , datasetSplitText
  , fetchDatasetRef
  , renderDatasetCatalog
  , verifyDatasetBytes
  )
where

import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
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
datasetObjectRef ref =
  ObjectRef
    (BucketName "jitml-datasets")
    (ObjectKey (datasetName ref <> "/" <> datasetSplitText (datasetSplit ref) <> "/data.bin"))

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
canonicalSha256For "MNIST" TrainSplit =
  -- train-images-idx3-ubyte (60000 × 28×28 + 16-byte header)
  Just "440fcabf73cc546fa21475e81ea370265605f56be210a4024d2ca8f203523609"
canonicalSha256For "MNIST" TestSplit =
  -- t10k-images-idx3-ubyte (10000 × 28×28 + 16-byte header)
  Just "8d422c7b0a1c1c79245a5bcf07fe86e33eeafee792b84584aec276f5a2dbc4e6"
canonicalSha256For _ _ = Nothing

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
