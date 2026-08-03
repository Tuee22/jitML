{-# LANGUAGE OverloadedStrings #-}

-- | Per-run authentication for the ProductScenario cross-process journal.
--
-- The raw key is deliberately opaque and has no 'Show' instance.  It is
-- generated from the operating-system CSPRNG, rendered only for the
-- command-owned 0600 handoff file, and never persisted in a journal or
-- diagnostic.  Successful authentication returns a second opaque value that
-- binds the caller's run identity to the digest of the exact signed material.
module JitML.Test.ProductScenarioAuthorization
  ( AuthenticatedProductScenarioJournal
  , AuthenticatedProductScenarioJournalRow
  , ProductScenarioAuthorizationError (..)
  , ProductScenarioJournalKey
  , authenticateProductScenarioJournal
  , authenticateProductScenarioJournalRow
  , authenticatedProductScenarioJournalMaterialDigest
  , authenticatedProductScenarioJournalRunId
  , authenticatedProductScenarioJournalRowMaterialMatches
  , authenticatedProductScenarioJournalRowRunId
  , generateProductScenarioJournalKey
  , parseProductScenarioJournalKey
  , productScenarioJournalEvidenceMaterial
  , renderProductScenarioJournalKey
  , signProductScenarioJournal
  )
where

import Control.Exception (IOException, try)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.Bits (xor, (.|.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.Char (ord)
import Data.List qualified as List
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word64, Word8)
import System.IO (IOMode (ReadMode), withBinaryFile)

newtype ProductScenarioJournalKey = ProductScenarioJournalKey ByteString
  deriving stock (Eq)

data AuthenticatedProductScenarioJournal
  = AuthenticatedProductScenarioJournal !Text !Text
  deriving stock (Eq, Show)

data AuthenticatedProductScenarioJournalRow
  = AuthenticatedProductScenarioJournalRow !Text !Text !Text
  deriving stock (Eq, Show)

data ProductScenarioAuthorizationError
  = ProductScenarioJournalKeyReadFailed !Text
  | ProductScenarioJournalKeyLengthInvalid !Int
  | ProductScenarioJournalKeyEncodingInvalid !Text
  | ProductScenarioJournalAuthenticationTagInvalid !Text
  | ProductScenarioJournalAuthenticationFailed
  | ProductScenarioJournalAuthenticatedMaterialMismatch
  deriving stock (Eq, Show)

generateProductScenarioJournalKey
  :: IO (Either ProductScenarioAuthorizationError ProductScenarioJournalKey)
generateProductScenarioJournalKey = do
  generated <-
    try
      ( withBinaryFile "/dev/urandom" ReadMode $ \handle ->
          ByteString.hGet handle productScenarioJournalKeyBytes
      )
  pure $
    case generated of
      Left exception ->
        Left
          ( ProductScenarioJournalKeyReadFailed
              (Text.pack (show (exception :: IOException)))
          )
      Right bytes
        | ByteString.length bytes == productScenarioJournalKeyBytes ->
            Right (ProductScenarioJournalKey bytes)
        | otherwise ->
            Left (ProductScenarioJournalKeyLengthInvalid (ByteString.length bytes))

renderProductScenarioJournalKey :: ProductScenarioJournalKey -> Text
renderProductScenarioJournalKey (ProductScenarioJournalKey bytes) = hexBytes bytes

parseProductScenarioJournalKey
  :: Text
  -> Either ProductScenarioAuthorizationError ProductScenarioJournalKey
parseProductScenarioJournalKey encoded
  | Text.length encoded /= productScenarioJournalKeyBytes * 2 =
      Left (ProductScenarioJournalKeyLengthInvalid (Text.length encoded))
  | not (Text.all isLowerHex encoded) =
      Left
        ( ProductScenarioJournalKeyEncodingInvalid
            "journal key must contain only lowercase hexadecimal characters"
        )
  | otherwise =
      ProductScenarioJournalKey . ByteString.pack
        <$> traverse decodePair (pairs (Text.unpack encoded))
 where
  decodePair [high, low] =
    Right (hexNibble high * 16 + hexNibble low)
  decodePair _ =
    Left
      ( ProductScenarioJournalKeyEncodingInvalid
          "journal key contains an incomplete hexadecimal byte"
      )

signProductScenarioJournal :: ProductScenarioJournalKey -> Text -> Text
signProductScenarioJournal (ProductScenarioJournalKey key) material =
  hexBytes
    ( hmacSha256
        key
        (Text.Encoding.encodeUtf8 material)
    )

authenticateProductScenarioJournal
  :: ProductScenarioJournalKey
  -> Text
  -> Text
  -> Text
  -> Either
       ProductScenarioAuthorizationError
       AuthenticatedProductScenarioJournal
authenticateProductScenarioJournal key runId material observedTag
  | Text.length observedTag /= sha256HexCharacters
      || not (Text.all isLowerHex observedTag) =
      Left
        ( ProductScenarioJournalAuthenticationTagInvalid
            "journal HMAC must be exactly 64 lowercase hexadecimal characters"
        )
  | constantTimeEqual expectedBytes observedBytes =
      Right
        ( AuthenticatedProductScenarioJournal
            runId
            (sha256Text material)
        )
  | otherwise = Left ProductScenarioJournalAuthenticationFailed
 where
  expectedBytes = Text.Encoding.encodeUtf8 (signProductScenarioJournal key material)
  observedBytes = Text.Encoding.encodeUtf8 observedTag

authenticatedProductScenarioJournalRunId
  :: AuthenticatedProductScenarioJournal
  -> Text
authenticatedProductScenarioJournalRunId
  (AuthenticatedProductScenarioJournal runId _materialDigest) = runId

authenticatedProductScenarioJournalMaterialDigest
  :: AuthenticatedProductScenarioJournal
  -> Text
authenticatedProductScenarioJournalMaterialDigest
  (AuthenticatedProductScenarioJournal _runId materialDigest) = materialDigest

authenticateProductScenarioJournalRow
  :: AuthenticatedProductScenarioJournal
  -> Text
  -> Text
  -> Either
       ProductScenarioAuthorizationError
       AuthenticatedProductScenarioJournalRow
authenticateProductScenarioJournalRow
  (AuthenticatedProductScenarioJournal runId authenticatedMaterialDigest)
  aggregateMaterial
  rowMaterial
    | constantTimeTextDigestEqual
        authenticatedMaterialDigest
        (sha256Text aggregateMaterial) =
        Right
          ( AuthenticatedProductScenarioJournalRow
              runId
              authenticatedMaterialDigest
              (sha256Text rowMaterial)
          )
    | otherwise = Left ProductScenarioJournalAuthenticatedMaterialMismatch

authenticatedProductScenarioJournalRowRunId
  :: AuthenticatedProductScenarioJournalRow
  -> Text
authenticatedProductScenarioJournalRowRunId
  (AuthenticatedProductScenarioJournalRow runId _aggregateDigest _rowDigest) = runId

authenticatedProductScenarioJournalRowMaterialMatches
  :: AuthenticatedProductScenarioJournalRow
  -> Text
  -> Bool
authenticatedProductScenarioJournalRowMaterialMatches
  (AuthenticatedProductScenarioJournalRow _runId _aggregateDigest rowDigest)
  rowMaterial =
    constantTimeTextDigestEqual rowDigest (sha256Text rowMaterial)

-- | Canonical semantic material shared by the journal boundary and Report's
-- final row refinement.  The aggregate token separately binds wire shape,
-- order, projection digest, and inference-experiment identity; this material
-- binds every value that Report consumes while minting one opaque row.
productScenarioJournalEvidenceMaterial
  :: Text
  -> Text
  -> Text
  -> Text
  -> FilePath
  -> Text
  -> Text
  -> Text
  -> Text
  -> Text
  -> Text
  -> Text
  -> Text
  -> Text
  -> Text
  -> Bool
  -> Word64
  -> Word64
  -> Word64
  -> Text
productScenarioJournalEvidenceMaterial
  rowId
  runId
  planId
  substrate
  executablePath
  executableSha256
  invocationDigest
  experimentHash
  manifestSha256
  command
  contractSha256
  checkpointScopeSha256
  executionJournalReceipt
  executionJournalSha256
  inferenceManifestSha256
  preconditionRejected
  preconditionSequence
  inferenceSequence
  completionSequence =
    Text.concat
      [ materialField "domain" "jitml-product-scenario-authenticated-row-v1"
      , materialField "row_id" rowId
      , materialField "run_id" runId
      , materialField "plan_id" planId
      , materialField "substrate" substrate
      , materialField "executable_path" (Text.pack executablePath)
      , materialField "executable_sha256" executableSha256
      , materialField "invocation_digest" invocationDigest
      , materialField "experiment_hash" experimentHash
      , materialField "manifest_sha256" manifestSha256
      , materialField "command" command
      , materialField "contract_sha256" contractSha256
      , materialField "checkpoint_scope_sha256" checkpointScopeSha256
      , materialField "execution_journal_receipt" executionJournalReceipt
      , materialField "execution_journal_sha256" executionJournalSha256
      , materialField "inference_manifest_sha256" inferenceManifestSha256
      , materialField "precondition_rejected" (showText preconditionRejected)
      , materialField "precondition_sequence" (showText preconditionSequence)
      , materialField "inference_sequence" (showText inferenceSequence)
      , materialField "completion_sequence" (showText completionSequence)
      ]

materialField :: Text -> Text -> Text
materialField label value =
  label
    <> "="
    <> showText (Text.length value)
    <> ":"
    <> value
    <> "\n"

showText :: (Show value) => value -> Text
showText = Text.pack . show

productScenarioJournalKeyBytes :: Int
productScenarioJournalKeyBytes = 32

sha256BlockBytes :: Int
sha256BlockBytes = 64

sha256HexCharacters :: Int
sha256HexCharacters = 64

hmacSha256 :: ByteString -> ByteString -> ByteString
hmacSha256 key message =
  SHA256.hash (outerPad <> SHA256.hash (innerPad <> message))
 where
  blockKey =
    ByteString.take
      sha256BlockBytes
      (key <> ByteString.replicate sha256BlockBytes 0)
  innerPad = ByteString.map (`xor` 0x36) blockKey
  outerPad = ByteString.map (`xor` 0x5c) blockKey

-- Both inputs are fixed-size canonical hexadecimal tags before this function
-- is called.  Folding every byte avoids an equality check that exits at the
-- first mismatch and would expose a tag-prefix timing oracle.
constantTimeEqual :: ByteString -> ByteString -> Bool
constantTimeEqual left right =
  List.foldl' (.|.) (0 :: Word8) (ByteString.zipWith xor left right) == 0
{-# NOINLINE constantTimeEqual #-}

constantTimeTextDigestEqual :: Text -> Text -> Bool
constantTimeTextDigestEqual left right =
  constantTimeEqual
    (Text.Encoding.encodeUtf8 left)
    (Text.Encoding.encodeUtf8 right)
{-# NOINLINE constantTimeTextDigestEqual #-}

sha256Text :: Text -> Text
sha256Text = hexBytes . SHA256.hash . Text.Encoding.encodeUtf8

hexBytes :: ByteString -> Text
hexBytes = Text.pack . concatMap byteHex . ByteString.unpack
 where
  byteHex byte =
    let alphabet = "0123456789abcdef"
        value = fromIntegral byte
     in [ alphabet !! (value `div` 16)
        , alphabet !! (value `mod` 16)
        ]

isLowerHex :: Char -> Bool
isLowerHex character =
  isAsciiDecimalDigit character
    || (character >= 'a' && character <= 'f')

isAsciiDecimalDigit :: Char -> Bool
isAsciiDecimalDigit character =
  let codepoint = ord character
   in codepoint >= ord '0' && codepoint <= ord '9'

hexNibble :: Char -> Word8
hexNibble character
  | isAsciiDecimalDigit character =
      fromIntegral (ord character - ord '0')
  | otherwise = fromIntegral (ord character - ord 'a' + 10)

pairs :: [value] -> [[value]]
pairs [] = []
pairs (first : second : remaining) = [first, second] : pairs remaining
pairs remaining = [remaining]
