{-# LANGUAGE OverloadedStrings #-}

-- | Ordinary immutable selection DATA. Parsing or constructing these records
-- confers no lane admission, execution, review or publication authority.
module JitML.Product.LaneRegistrationData
  ( SelectedLaneFileData (..)
  , LaneReviewIdentityData (..)
  , LaneRowContractData (..)
  , LaneGenerationData (..)
  , LaneRegistrationEntryData (..)
  , LaneRegistrationData (..)
  , LaneRegistrationDataError (..)
  , maximumLaneGenerationBytes
  , maximumLaneRegistrationBytes
  , maximumRegisteredJournalBytes
  , laneRegistrationPath
  , laneGenerationPath
  , laneGenerationJournalPath
  , refineLaneGenerationData
  , refineLaneRegistrationData
  , encodeLaneGenerationData
  , decodeLaneGenerationData
  , encodeLaneRegistrationData
  , decodeLaneRegistrationData
  , laneRegistrationEntrySha256
  , laneRowContractsSha256
  )
where

import Control.Monad (unless)
import Data.Aeson (FromJSON (parseJSON), Value (..), eitherDecodeStrict', encode, toJSON)
import Data.Aeson.Types (Parser, parseEither)
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Char (isControl, ord)
import Data.Either.Combinators (mapLeft)
import Data.List qualified as List
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Vector qualified as Vector
import Data.Word (Word64)

import JitML.Product.SourceDigest (SourceStamp (..), sourceDigestAlgorithm)
import JitML.Product.ValidationRecord (sha256Hex)
import JitML.Substrate (Substrate, parseSubstrate, renderSubstrate)

data SelectedLaneFileData = SelectedLaneFileData
  { selectedLaneFilePath :: !Text
  , selectedLaneFileSha256 :: !Text
  , selectedLaneFileBytes :: !Word64
  }
  deriving stock (Eq, Show)

data LaneReviewIdentityData = LaneReviewIdentityData
  { laneReviewSelection :: !SelectedLaneFileData
  , laneReviewReceipt :: !SelectedLaneFileData
  , laneReviewContractSetSha256 :: !Text
  }
  deriving stock (Eq, Show)

data LaneRowContractData = LaneRowContractData
  { laneRowId :: !Text
  , laneRowPlanId :: !Text
  , laneRowContractSha256 :: !Text
  }
  deriving stock (Eq, Show)

data LaneGenerationData = LaneGenerationData
  { laneGenerationSubstrate :: !Substrate
  , laneGenerationSource :: !SourceStamp
  , laneGenerationJournal :: !SelectedLaneFileData
  , laneGenerationRows :: ![LaneRowContractData]
  , laneGenerationSupervisedReview :: !LaneReviewIdentityData
  , laneGenerationNativeReview :: !LaneReviewIdentityData
  }
  deriving stock (Eq, Show)

data LaneRegistrationEntryData = LaneRegistrationEntryData
  { laneRegistrationOrdinal :: !Word64
  , laneRegistrationPreviousSha256 :: !(Maybe Text)
  , laneRegistrationGeneration :: !SelectedLaneFileData
  }
  deriving stock (Eq, Show)

data LaneRegistrationData = LaneRegistrationData
  { laneRegistrationSubstrate :: !Substrate
  , laneRegistrationEntries :: ![LaneRegistrationEntryData]
  }
  deriving stock (Eq, Show)

newtype LaneRegistrationDataError = LaneRegistrationDataError Text
  deriving stock (Eq, Show)

maximumLaneGenerationBytes, maximumLaneRegistrationBytes, maximumRegisteredJournalBytes :: Integer
maximumLaneGenerationBytes = 1024 * 1024
maximumLaneRegistrationBytes = 4 * 1024 * 1024
maximumRegisteredJournalBytes = 256 * 1024 * 1024

registrationRoot :: Text
registrationRoot = "DEVELOPMENT_PLAN/attestations/product-lane-registrations/"

laneRegistrationPath :: Substrate -> FilePath
laneRegistrationPath lane = Text.unpack (registrationRoot <> renderSubstrate lane <> ".json")

laneGenerationPath :: Text -> Text
laneGenerationPath sha = registrationRoot <> "snapshots/" <> sha <> ".json"

laneGenerationJournalPath :: Substrate -> Text -> Text
laneGenerationJournalPath lane sha =
  registrationRoot <> "generations/" <> renderSubstrate lane <> "/" <> sha <> "/journal.json"

refineLaneGenerationData
  :: LaneGenerationData -> Either LaneRegistrationDataError LaneGenerationData
refineLaneGenerationData value = do
  let source = laneGenerationSource value
      journal = laneGenerationJournal value
      rows = laneGenerationRows value
  require (stampAlgorithm source == sourceDigestAlgorithm) "unsupported original source algorithm"
  require (canonicalSha (stampSha256 source)) "invalid original source SHA256"
  checkFile maximumRegisteredJournalBytes journal
  require
    ( selectedLaneFilePath journal
        == laneGenerationJournalPath (laneGenerationSubstrate value) (selectedLaneFileSha256 journal)
    )
    "journal path must be its immutable lane/SHA destination"
  require (length (take 56 rows) == 55) "generation must contain exactly55 ordered row contracts"
  mapM_ checkRow rows
  require (unique (fmap laneRowId rows)) "duplicate generation row identity"
  checkReview (laneGenerationSupervisedReview value)
  checkReview (laneGenerationNativeReview value)
  contracts <- laneRowContractsSha256 rows
  require
    ( all
        ((== contracts) . laneReviewContractSetSha256)
        [laneGenerationSupervisedReview value, laneGenerationNativeReview value]
    )
    "review contract-set SHA256 differs from the complete ordered55 contracts"
  pure value
 where
  checkRow row = do
    checkText 256 (laneRowId row)
    require (not (Text.null (laneRowId row))) "empty generation row identity"
    require (canonicalSha (laneRowPlanId row)) "invalid generation PlanId"
    require (canonicalSha (laneRowContractSha256 row)) "invalid generation contract SHA256"
  checkReview review = do
    checkFile maximumLaneRegistrationBytes (laneReviewSelection review)
    checkFile maximumLaneRegistrationBytes (laneReviewReceipt review)
    require (canonicalSha (laneReviewContractSetSha256 review)) "invalid review contract-set SHA256"

refineLaneRegistrationData
  :: LaneRegistrationData -> Either LaneRegistrationDataError LaneRegistrationData
refineLaneRegistrationData value = do
  let entries = laneRegistrationEntries value
      count = length (take 4097 entries)
  require (count > 0 && count <= 4096) "registration history must contain1..4096 entries"
  checkEntries 0 Nothing entries
  require
    (unique (fmap (selectedLaneFileSha256 . laneRegistrationGeneration) entries))
    "duplicate selected generation in registration history"
  pure value
 where
  checkEntries _ _ [] = Right ()
  checkEntries ordinal previous (entry : rest) = do
    require (laneRegistrationOrdinal entry == ordinal) "registration ordinal is not contiguous"
    require (laneRegistrationPreviousSha256 entry == previous) "registration predecessor digest differs"
    let selected = laneRegistrationGeneration entry
    checkFile maximumLaneGenerationBytes selected
    require
      (selectedLaneFilePath selected == laneGenerationPath (selectedLaneFileSha256 selected))
      "selected generation path is not SHA-derived"
    checkEntries (ordinal + 1) (Just (entrySha entry)) rest

encodeLaneGenerationData :: LaneGenerationData -> Either LaneRegistrationDataError ByteString
encodeLaneGenerationData value = do
  checked <- refineLaneGenerationData value
  boundedEncoded maximumLaneGenerationBytes (generationValue checked)

decodeLaneGenerationData :: ByteString -> Either LaneRegistrationDataError LaneGenerationData
decodeLaneGenerationData bytes = do
  value <- decodeValue maximumLaneGenerationBytes bytes parseGeneration
  checked <- refineLaneGenerationData value
  canonical <- encodeLaneGenerationData checked
  require (bytes == canonical) "generation JSON is not canonical"
  pure checked

encodeLaneRegistrationData :: LaneRegistrationData -> Either LaneRegistrationDataError ByteString
encodeLaneRegistrationData value = do
  checked <- refineLaneRegistrationData value
  boundedEncoded maximumLaneRegistrationBytes (registrationValue checked)

decodeLaneRegistrationData :: ByteString -> Either LaneRegistrationDataError LaneRegistrationData
decodeLaneRegistrationData bytes = do
  value <- decodeValue maximumLaneRegistrationBytes bytes parseRegistration
  checked <- refineLaneRegistrationData value
  canonical <- encodeLaneRegistrationData checked
  require (bytes == canonical) "registration JSON is not canonical"
  pure checked

-- | Hash only an individually valid entry. The full registration refiner checks
-- contiguous ordinals and predecessor linkage against the surrounding history.
laneRegistrationEntrySha256 :: LaneRegistrationEntryData -> Either LaneRegistrationDataError Text
laneRegistrationEntrySha256 entry = do
  let selected = laneRegistrationGeneration entry
  checkFile maximumLaneGenerationBytes selected
  require
    (selectedLaneFilePath selected == laneGenerationPath (selectedLaneFileSha256 selected))
    "selected generation path is not SHA-derived"
  case laneRegistrationPreviousSha256 entry of
    Nothing -> require (laneRegistrationOrdinal entry == 0) "only initial entry may omit predecessor"
    Just sha -> do
      require (laneRegistrationOrdinal entry > 0) "initial entry cannot have predecessor"
      require (canonicalSha sha) "invalid predecessor SHA256"
  pure (entrySha entry)

-- | Domain-separated digest of the complete ordered55 canonical contracts.
-- Both independently reviewed scopes bind the same epoch; scope coverage itself
-- remains in the review receipt and authenticated execution chain.
laneRowContractsSha256 :: [LaneRowContractData] -> Either LaneRegistrationDataError Text
laneRowContractsSha256 rows = do
  require (length (take 56 rows) == 55) "contract set must contain exactly55 ordered rows"
  mapM_ check rows
  require (unique (fmap laneRowId rows)) "duplicate contract-set row identity"
  pure
    ( sha256Hex
        ( "jitml-product-lane-contract-set-v1\NUL"
            <> LazyByteString.toStrict (encode (array (fmap rowValue rows)))
        )
    )
 where
  check row = do
    checkText 256 (laneRowId row)
    require (not (Text.null (laneRowId row))) "empty contract-set row identity"
    require
      (canonicalSha (laneRowPlanId row) && canonicalSha (laneRowContractSha256 row))
      "invalid contract-set digest"

entrySha :: LaneRegistrationEntryData -> Text
entrySha = sha256Hex . LazyByteString.toStrict . encode . entryValue

array :: [Value] -> Value
array = toJSON

fileValue :: SelectedLaneFileData -> Value
fileValue value =
  array
    [ String (selectedLaneFilePath value)
    , String (selectedLaneFileSha256 value)
    , toJSON (selectedLaneFileBytes value)
    ]

reviewValue :: LaneReviewIdentityData -> Value
reviewValue value =
  array
    [ fileValue (laneReviewSelection value)
    , fileValue (laneReviewReceipt value)
    , String (laneReviewContractSetSha256 value)
    ]

rowValue :: LaneRowContractData -> Value
rowValue value =
  array [String (laneRowId value), String (laneRowPlanId value), String (laneRowContractSha256 value)]

generationValue :: LaneGenerationData -> Value
generationValue value =
  array
    [ String "jitml-product-lane-generation"
    , toJSON (1 :: Word64)
    , String (renderSubstrate (laneGenerationSubstrate value))
    , array
        [ toJSON (stampAlgorithm (laneGenerationSource value))
        , String (stampSha256 (laneGenerationSource value))
        ]
    , fileValue (laneGenerationJournal value)
    , array (fmap rowValue (laneGenerationRows value))
    , reviewValue (laneGenerationSupervisedReview value)
    , reviewValue (laneGenerationNativeReview value)
    ]

entryValue :: LaneRegistrationEntryData -> Value
entryValue value =
  array
    [ toJSON (laneRegistrationOrdinal value)
    , maybe Null String (laneRegistrationPreviousSha256 value)
    , fileValue (laneRegistrationGeneration value)
    ]

registrationValue :: LaneRegistrationData -> Value
registrationValue value =
  array
    [ String "jitml-product-lane-registration"
    , toJSON (1 :: Word64)
    , String (renderSubstrate (laneRegistrationSubstrate value))
    , array (fmap entryValue (laneRegistrationEntries value))
    ]

parseGeneration :: Value -> Parser LaneGenerationData
parseGeneration raw = do
  fields <- exactArray 8 raw
  case fields of
    [domain, version, lane, source, journal, rows, supervised, native] -> do
      domainVersion "jitml-product-lane-generation" domain version
      LaneGenerationData
        <$> parseLane lane
        <*> parseSource source
        <*> parseFile journal
        <*> boundedArray 55 parseRow rows
        <*> parseReview supervised
        <*> parseReview native
    _ -> fail "generation arity"

parseRegistration :: Value -> Parser LaneRegistrationData
parseRegistration raw = do
  fields <- exactArray 4 raw
  case fields of
    [domain, version, lane, entries] -> do
      domainVersion "jitml-product-lane-registration" domain version
      LaneRegistrationData <$> parseLane lane <*> boundedArray 4096 parseEntry entries
    _ -> fail "registration arity"

parseSource :: Value -> Parser SourceStamp
parseSource value = do
  fields <- exactArray 2 value
  case fields of
    [algorithm, sha] -> SourceStamp <$> parseJSON algorithm <*> parseJSON sha
    _ -> fail "source arity"

parseFile :: Value -> Parser SelectedLaneFileData
parseFile value = do
  fields <- exactArray 3 value
  case fields of
    [path, sha, count] -> SelectedLaneFileData <$> parseJSON path <*> parseJSON sha <*> parseJSON count
    _ -> fail "selected file arity"

parseReview :: Value -> Parser LaneReviewIdentityData
parseReview value = do
  fields <- exactArray 3 value
  case fields of
    [selection, receipt, contracts] -> LaneReviewIdentityData <$> parseFile selection <*> parseFile receipt <*> parseJSON contracts
    _ -> fail "review identity arity"

parseRow :: Value -> Parser LaneRowContractData
parseRow value = do
  fields <- exactArray 3 value
  case fields of
    [row, plan, contract] -> LaneRowContractData <$> parseJSON row <*> parseJSON plan <*> parseJSON contract
    _ -> fail "row identity arity"

parseEntry :: Value -> Parser LaneRegistrationEntryData
parseEntry value = do
  fields <- exactArray 3 value
  case fields of
    [ordinal, previous, selected] -> LaneRegistrationEntryData <$> parseJSON ordinal <*> parseJSON previous <*> parseFile selected
    _ -> fail "entry arity"

parseLane :: Value -> Parser Substrate
parseLane value = do
  name <- parseJSON value
  maybe (fail "unknown substrate") pure (parseSubstrate name)

domainVersion :: Text -> Value -> Value -> Parser ()
domainVersion expected domain version = do
  actualDomain <- parseJSON domain
  actualVersion <- parseJSON version :: Parser Word64
  unless (actualDomain == expected && actualVersion == 1) (fail "unsupported domain/version")

exactArray :: Int -> Value -> Parser [Value]
exactArray count (Array values)
  | Vector.length values == count = pure (Vector.toList values)
exactArray _ _ = fail "closed array arity differs"

boundedArray :: Int -> (Value -> Parser a) -> Value -> Parser [a]
boundedArray cap parser (Array values)
  | Vector.length values <= cap = traverse parser (Vector.toList values)
boundedArray _ _ _ = fail "array exceeds its cap or is not an array"

decodeValue :: Integer -> ByteString -> (Value -> Parser a) -> Either LaneRegistrationDataError a
decodeValue cap bytes parser = do
  require (toInteger (ByteString.length bytes) <= cap) "JSON bytes exceed their cap"
  value <- mapLeft (LaneRegistrationDataError . Text.pack) (eitherDecodeStrict' bytes)
  mapLeft (LaneRegistrationDataError . Text.pack) (parseEither parser value)

boundedEncoded :: Integer -> Value -> Either LaneRegistrationDataError ByteString
boundedEncoded cap value = do
  let bytes = LazyByteString.toStrict (encode value)
  require (toInteger (ByteString.length bytes) <= cap) "encoded JSON exceeds its cap"
  pure bytes

checkFile :: Integer -> SelectedLaneFileData -> Either LaneRegistrationDataError ()
checkFile cap value = do
  let path = selectedLaneFilePath value
  checkText 4096 path
  require
    (Text.isPrefixOf "DEVELOPMENT_PLAN/attestations/" path)
    "selected path is outside governed attestations or criterion reviews"
  require
    (all safeComponent (Text.splitOn "/" path))
    "selected path contains traversal or empty component"
  require (not (Text.any (== '\\') path)) "selected path contains backslash"
  require (canonicalSha (selectedLaneFileSha256 value)) "invalid selected file SHA256"
  require
    (selectedLaneFileBytes value > 0 && toInteger (selectedLaneFileBytes value) <= cap)
    "selected file count exceeds its cap or is zero"
 where
  safeComponent component = not (Text.null component) && component `notElem` [".", ".."]

checkText :: Int -> Text -> Either LaneRegistrationDataError ()
checkText cap value = do
  require (Text.length value <= cap) "text characters exceed their cap"
  require
    (not (Text.any (\c -> isControl c || (ord c >= 0xd800 && ord c <= 0xdfff)) value))
    "text contains control/non-scalar characters"
  require
    (ByteString.length (Text.Encoding.encodeUtf8 value) <= cap)
    "text UTF8 bytes exceed their cap"

canonicalSha :: Text -> Bool
canonicalSha value = Text.length value == 64 && Text.all (`elem` ("0123456789abcdef" :: String)) value

unique :: (Ord a) => [a] -> Bool
unique = all ((== 1) . length) . List.group . List.sort

require :: Bool -> Text -> Either LaneRegistrationDataError ()
require condition reason = unless condition (Left (LaneRegistrationDataError reason))
