{-# LANGUAGE OverloadedStrings #-}

module JitML.SL.Dataset
  ( DatasetFetchResult (..)
  , DatasetRef (..)
  , DatasetSplit (..)
  , canonicalDatasets
  , datasetForProblem
  , datasetFixtureBytes
  , datasetObjectKey
  , datasetObjectRef
  , datasetRefHash
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
        (computeExpectedSha256 name split sz)
    | split <- [TrainSplit, ValidationSplit, TestSplit]
    ]

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
