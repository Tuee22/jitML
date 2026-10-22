{-# LANGUAGE OverloadedStrings #-}

-- | Ordinary historical native-parent receipt DATA. Parsing does not restore
-- an owned process, evaluated result, Store admission or parent certificate.
module JitML.Test.NativeScenarioReceiptData
  ( NativeScenarioReceiptData (..)
  , nativeScenarioReceiptFromActualCertificate
  , refineNativeScenarioReceiptData
  , encodeNativeScenarioReceiptData
  , decodeNativeScenarioReceiptData
  , renderNativeScenarioReceiptData
  , parseNativeScenarioReceiptData
  , maximumNativeScenarioReceiptBytes
  , maximumNativeScenarioReceiptTextCharacters
  , nativeScenarioAttemptScopeData
  ) where

import Codec.CBOR.Encoding qualified as CBOR
import Control.Monad (replicateM, unless)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Char (intToDigit, ord)
import Data.Either.Combinators (mapLeft)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as UTF8
import Data.Word (Word64, Word8)
import System.FilePath (isAbsolute, normalise, (</>))

import JitML.Checkpoint.NativeParentEvaluationSummaryData qualified as Summary
import JitML.Checkpoint.NativePhase.CBOR qualified as Wire
import JitML.Checkpoint.NativePhase.Types
import JitML.Execution.NativeParentAttemptRetention qualified as Attempt
import JitML.Plan.Plan qualified as Plan
import JitML.Product.CriterionReviewData qualified as Review
import JitML.Product.NativeParentExecution qualified as Parent
import JitML.Product.NativeQualificationReference qualified as Reference
import JitML.Product.Publisher.SourceAuthority (supervisedQualificationSourceEnvironment)
import JitML.Product.ValidationRecord (sha256Hex)
import JitML.Sub.Stream qualified as Stream
import JitML.Substrate (renderSubstrate)
import JitML.Training.Budget qualified as Training

-- Every constructor is public ordinary DATA; only the separate authenticated
-- physical re-audit boundary may turn this into a retained qualification.
data NativeScenarioReceiptData = NativeScenarioReceiptData
  { nativeScenarioReceiptRequest :: !Parent.NativeParentExecutionRequest
  , nativeScenarioReceiptReference :: !Reference.NativeQualificationReference
  , nativeScenarioReceiptProcessId :: !Integer
  , nativeScenarioReceiptParentProcessId :: !Integer
  , nativeScenarioReceiptExecutablePath :: !FilePath
  , nativeScenarioReceiptArguments :: ![Text]
  , nativeScenarioReceiptWorkingDirectory :: !(Maybe FilePath)
  , nativeScenarioReceiptEnvironmentRemovals :: ![Text]
  , nativeScenarioReceiptEnvironmentOverrideNames :: ![Text]
  , nativeScenarioReceiptAttemptScope :: !Text
  , nativeScenarioReceiptAttemptInventory :: !Attempt.NativeParentAttemptInventory
  , nativeScenarioReceiptEvaluationSummary :: !Summary.NativeParentEvaluationSummaryData
  , nativeScenarioReceiptCriterionReview :: !(Maybe Review.CriterionReviewIdentityData)
  }
  deriving stock (Eq, Show)

maximumNativeScenarioReceiptBytes, maximumNativeScenarioReceiptTextCharacters :: Integer
maximumNativeScenarioReceiptBytes = 131072
maximumNativeScenarioReceiptTextCharacters = toInteger (Text.length receiptPrefix) + 2 * maximumNativeScenarioReceiptBytes
receiptPrefix :: Text
receiptPrefix = "native-parent-qualification-v1: "

nativeScenarioReceiptFromActualCertificate
  :: Parent.NativeParentExecutionCertificate -> NativeScenarioReceiptData
nativeScenarioReceiptFromActualCertificate certificate =
  let spawn = Parent.nativeParentCertificateSpawn certificate
   in NativeScenarioReceiptData
        (Parent.nativeParentCertificateRequest certificate)
        (Parent.nativeParentCertificateReference certificate)
        (Stream.nativeSpawnProcessId spawn)
        (Stream.nativeSpawnParentProcessId spawn)
        (Stream.nativeSpawnExecutablePath spawn)
        (Stream.nativeSpawnArguments spawn)
        (Stream.nativeSpawnWorkingDirectory spawn)
        (Stream.nativeSpawnEnvironmentRemovals spawn)
        (Stream.nativeSpawnEnvironmentOverrideNames spawn)
        (Parent.nativeParentCertificateAttemptScope certificate)
        (Parent.nativeParentCertificateAttemptInventory certificate)
        (Parent.nativeParentCertificateEvaluationSummary certificate)
        (Just (Parent.nativeParentCertificateCriterionReview certificate))

refineNativeScenarioReceiptData
  :: NativeScenarioReceiptData -> Either CodecError NativeScenarioReceiptData
refineNativeScenarioReceiptData value = do
  let request = nativeScenarioReceiptRequest value
      reference = Reference.nativeQualificationReferenceData (nativeScenarioReceiptReference value)
      invocation = Parent.nativeParentRequestInvocation request
      workdir = Parent.nativeParentRequestWorkdir request
      scope = nativeScenarioReceiptAttemptScope value
      directory = workdir </> ".build" </> "native-parent-attempts" </> Text.unpack scope
      inventory = nativeScenarioReceiptAttemptInventory value
  mapM_
    canonicalPath
    [ Parent.nativeParentRequestSourceRoot request
    , workdir
    , Parent.nativeParentRequestPinnedExecutable request
    , nativeScenarioReceiptExecutablePath value
    ]
  _ <- Reference.refineNativeQualificationReference reference
  require
    ( Reference.nativeReferenceBinding reference == Reference.NativeReferenceScenario
        && Parent.nativeParentRequestSource request == Reference.nativeReferenceSource reference
        && Training.productScenarioInvocationRowId invocation == Reference.nativeReferenceRow reference
        && Training.productScenarioInvocationSubstrate invocation == Reference.nativeReferenceLane reference
        && Plan.planIdText (Training.productScenarioInvocationPlanId invocation)
          == Reference.nativeReferencePlan reference
        && Training.productScenarioInvocationDigest invocation == Reference.nativeReferenceInvocation reference
        && Training.productScenarioInvocationExecutableSha256 invocation
          == Reference.nativeReferenceExecutable reference
    )
    "native parent receipt original request differs from its exact scenario reference"
  case nativeScenarioReceiptCriterionReview value of
    Nothing -> pure () -- Explicit historical unreviewed receipt; current registered admission refuses it.
    Just review -> do
      _ <- mapLeft Malformed (Review.refineCriterionReviewIdentityData review)
      require
        ( Review.criterionReviewScope review == Review.NativeCriterionReview
            && Review.criterionReviewSource review == Parent.nativeParentRequestSource request
            && Review.criterionReviewSubstrate review == Training.productScenarioInvocationSubstrate invocation
        )
        "native receipt review identity differs from original source lane or scope"
  boundedText 4096 (Training.renderProductScenarioInvocation invocation)
  require
    ( nativeScenarioReceiptExecutablePath value == Parent.nativeParentRequestPinnedExecutable request
        && nativeScenarioReceiptWorkingDirectory value == Just workdir
    )
    "native parent receipt actual launch configuration differs from original request"
  require
    (scope == nativeScenarioAttemptScopeData invocation)
    "native parent receipt differs from original fixed run row lane slot"
  mapM_
    ( \pid ->
        require
          (pid > 0 && pid <= toInteger (maxBound :: Word64))
          "native parent receipt PID is not a positive bounded original observation"
    )
    [nativeScenarioReceiptProcessId value, nativeScenarioReceiptParentProcessId value]
  boundedTexts 64 4096 (nativeScenarioReceiptArguments value)
  boundedTexts 8 256 (nativeScenarioReceiptEnvironmentRemovals value)
  boundedTexts 8 256 (nativeScenarioReceiptEnvironmentOverrideNames value)
  require
    ( nativeScenarioReceiptEnvironmentRemovals value == journalEnvironmentRemovals
        && nativeScenarioReceiptEnvironmentOverrideNames value
          == ["JITML_PRODUCT_SCENARIO_INVOCATION", Text.pack supervisedQualificationSourceEnvironment]
    )
    "native parent receipt launch environment edit names differ"
  file
    directory
    Attempt.IssuedRecordFile
    "issued.cbor"
    (Attempt.nativeParentAttemptIssuedFile inventory)
  file
    (directory </> "result")
    Attempt.ParentReportFile
    "report.utf8"
    (Attempt.nativeParentAttemptReportFile inventory)
  file
    (directory </> "result")
    Attempt.RawAvailabilityFile
    "availability.cbor"
    (Attempt.nativeParentAttemptAvailabilityFile inventory)
  case (Attempt.nativeParentAttemptStdoutFile inventory, Attempt.nativeParentAttemptStderrFile inventory) of
    (Just stdoutFile, Just stderrFile) -> do
      file (directory </> "result") Attempt.ParentStdoutFile "stdout.bin" stdoutFile
      file (directory </> "result") Attempt.ParentStderrFile "stderr.bin" stderrFile
    _ -> require False "successful native parent receipt requires both actual raw stream files"
  _ <- Summary.refineNativeParentEvaluationSummaryData (nativeScenarioReceiptEvaluationSummary value)
  bytes <- encodeUnchecked value
  require
    (toInteger (BS.length bytes) <= maximumNativeScenarioReceiptBytes)
    "native parent receipt exceeds128KiB"
  pure value
 where
  file directory kind name actual = do
    canonicalPath (Attempt.nativeParentAttemptFilePath actual)
    require
      ( Attempt.nativeParentAttemptFileKind actual == kind
          && Attempt.nativeParentAttemptFilePath actual == directory </> name
      )
      "native parent receipt file role or exact fixed path differs"
    require
      (canonicalSha (Attempt.nativeParentAttemptFileSha256 actual))
      "native parent receipt file SHA differs"
    mapLeft
      Malformed
      ( Attempt.checkNativeParentAttemptByteCount
          kind
          (toInteger (Attempt.nativeParentAttemptFileBytes actual))
      )

nativeScenarioAttemptScopeData :: Training.ProductScenarioInvocation -> Text
nativeScenarioAttemptScopeData invocation =
  sha256Hex
    ( Wire.encodeStrict
        ( CBOR.encodeListLen 4
            <> CBOR.encodeString "jitml-native-parent-attempt-slot-v1"
            <> CBOR.encodeString (Training.productScenarioInvocationRunId invocation)
            <> CBOR.encodeString (Training.productScenarioInvocationRowId invocation)
            <> CBOR.encodeString (renderSubstrate (Training.productScenarioInvocationSubstrate invocation))
        )
    )

encodeNativeScenarioReceiptData :: NativeScenarioReceiptData -> Either CodecError ByteString
encodeNativeScenarioReceiptData value = refineNativeScenarioReceiptData value >>= encodeUnchecked

encodeUnchecked :: NativeScenarioReceiptData -> Either CodecError ByteString
encodeUnchecked value = do
  summary <-
    Summary.encodeNativeParentEvaluationSummaryData (nativeScenarioReceiptEvaluationSummary value)
  reviewBytes <-
    traverse
      (mapLeft Malformed . Review.encodeCriterionReviewIdentityData)
      (nativeScenarioReceiptCriterionReview value)
  let request = nativeScenarioReceiptRequest value
      inventory = nativeScenarioReceiptAttemptInventory value
  pure
    ( Wire.encodeStrict
        ( CBOR.encodeListLen (case reviewBytes of Nothing -> 17; Just _ -> 18)
            <> CBOR.encodeString
              ( case reviewBytes of
                  Nothing -> "jitml-native-scenario-parent-receipt-v1"
                  Just _ -> "jitml-native-scenario-parent-receipt-v2"
              )
            <> CBOR.encodeWord (case reviewBytes of Nothing -> 1; Just _ -> 2)
            <> path (Parent.nativeParentRequestSourceRoot request)
            <> path (Parent.nativeParentRequestWorkdir request)
            <> path (Parent.nativeParentRequestPinnedExecutable request)
            <> CBOR.encodeString
              (Training.renderProductScenarioInvocation (Parent.nativeParentRequestInvocation request))
            <> CBOR.encodeBytes
              (Reference.nativeQualificationReferenceBytes (nativeScenarioReceiptReference value))
            <> CBOR.encodeWord64 (fromInteger (nativeScenarioReceiptProcessId value))
            <> CBOR.encodeWord64 (fromInteger (nativeScenarioReceiptParentProcessId value))
            <> path (nativeScenarioReceiptExecutablePath value)
            <> texts (nativeScenarioReceiptArguments value)
            <> maybe CBOR.encodeNull path (nativeScenarioReceiptWorkingDirectory value)
            <> texts (nativeScenarioReceiptEnvironmentRemovals value)
            <> texts (nativeScenarioReceiptEnvironmentOverrideNames value)
            <> CBOR.encodeString (nativeScenarioReceiptAttemptScope value)
            <> CBOR.encodeListLen 5
            <> file (Attempt.nativeParentAttemptIssuedFile inventory)
            <> file (Attempt.nativeParentAttemptReportFile inventory)
            <> maybe CBOR.encodeNull file (Attempt.nativeParentAttemptStdoutFile inventory)
            <> maybe CBOR.encodeNull file (Attempt.nativeParentAttemptStderrFile inventory)
            <> file (Attempt.nativeParentAttemptAvailabilityFile inventory)
            <> CBOR.encodeBytes summary
            <> maybe mempty CBOR.encodeBytes reviewBytes
        )
    )
 where
  path = CBOR.encodeString . Text.pack
  texts values = CBOR.encodeListLen (fromIntegral (length values)) <> foldMap CBOR.encodeString values
  file actual =
    CBOR.encodeListLen 4
      <> CBOR.encodeWord64 (kindCode (Attempt.nativeParentAttemptFileKind actual))
      <> path (Attempt.nativeParentAttemptFilePath actual)
      <> CBOR.encodeWord64 (Attempt.nativeParentAttemptFileBytes actual)
      <> CBOR.encodeString (Attempt.nativeParentAttemptFileSha256 actual)

decodeNativeScenarioReceiptData :: ByteString -> Either CodecError NativeScenarioReceiptData
decodeNativeScenarioReceiptData bytes = do
  require
    (toInteger (BS.length bytes) <= maximumNativeScenarioReceiptBytes)
    "native parent receipt exceeds128KiB"
  value <- Wire.runParser parser bytes >>= refineNativeScenarioReceiptData
  canonical <- encodeUnchecked value
  require (canonical == bytes) "native parent receipt encoding is not canonical"
  pure value
 where
  parser = do
    arity <- Wire.getListLength AggregateSequenceElements 18
    domain <- Wire.getText GeneralTextBytes 64
    version <- Wire.getWord
    Wire.liftEither
      ( require
          ( (domain == "jitml-native-scenario-parent-receipt-v1" && version == 1 && arity == 17)
              || (domain == "jitml-native-scenario-parent-receipt-v2" && version == 2 && arity == 18)
          )
          "native parent receipt domain/version differs"
      )
    sourceRoot <- path
    workdir <- path
    pinned <- path
    invocation <-
      Wire.getText InvocationTextBytes 4096
        >>= Wire.liftEither . mapLeft Malformed . Training.parseProductScenarioInvocation
    reference <-
      Wire.getBytes WholePayloadBytes 16384
        >>= Wire.liftEither . Reference.decodeNativeQualificationReference
    pid <- toInteger <$> Wire.getWord
    ppid <- toInteger <$> Wire.getWord
    executable <- path
    arguments <- texts InvocationTextBytes 64 4096
    cwd <- optional path
    removals <- texts GeneralTextBytes 8 256
    overrides <- texts GeneralTextBytes 8 256
    scope <- Wire.getText GeneralTextBytes 64
    Wire.expectList 5
    inventory <-
      Attempt.NativeParentAttemptInventory <$> file <*> file <*> optional file <*> optional file <*> file
    summary <-
      Wire.getBytes WholePayloadBytes Summary.maximumNativeParentEvaluationSummaryBytes
        >>= Wire.liftEither . Summary.decodeNativeParentEvaluationSummaryData
    review <-
      if version == 1
        then pure Nothing
        else
          Just
            <$> ( Wire.getBytes WholePayloadBytes 16384
                    >>= Wire.liftEither . mapLeft Malformed . Review.decodeCriterionReviewIdentityData
                )
    let request =
          Parent.NativeParentExecutionRequest
            sourceRoot
            (Reference.nativeReferenceSource (Reference.nativeQualificationReferenceData reference))
            workdir
            pinned
            invocation
    pure
      ( NativeScenarioReceiptData
          request
          reference
          pid
          ppid
          executable
          arguments
          cwd
          removals
          overrides
          scope
          inventory
          summary
          review
      )
  path = Text.unpack <$> Wire.getText PathTextBytes 4096
  texts resource count cap = do
    size <- Wire.getListLength AggregateSequenceElements count
    replicateM size (Wire.getText resource cap)
  file = do
    Wire.expectList 4
    kind <- Wire.getWord >>= Wire.liftEither . kindFromCode
    Attempt.NativeParentAttemptFileData kind
      <$> path
      <*> Wire.getWord
      <*> Wire.getText GeneralTextBytes 64
  optional action = do
    absent <- Wire.nextIsNull
    if absent then Wire.getNull >> pure Nothing else Just <$> action

renderNativeScenarioReceiptData :: NativeScenarioReceiptData -> Either CodecError Text
renderNativeScenarioReceiptData value = (receiptPrefix <>) . hex <$> encodeNativeScenarioReceiptData value

parseNativeScenarioReceiptData :: Text -> Either CodecError NativeScenarioReceiptData
parseNativeScenarioReceiptData line = do
  require
    (toInteger (Text.length line) <= maximumNativeScenarioReceiptTextCharacters)
    "native parent receipt scalar exceeds its bound"
  body <-
    maybe
      (Left (Malformed "native parent receipt prefix differs"))
      Right
      (Text.stripPrefix receiptPrefix line)
  require (even (Text.length body)) "native parent receipt hex length is odd"
  pairs (Text.unpack body) >>= decodeNativeScenarioReceiptData . BS.pack
 where
  pairs = go []
  go accumulated [] = Right (reverse accumulated)
  go accumulated (high : low : rest) = do
    first <- digit high
    second <- digit low
    go ((first * 16 + second) : accumulated) rest
  go _ _ = Left (Malformed "native parent receipt hex length is odd")
  digit :: Char -> Either CodecError Word8
  digit value
    | isAsciiDecimalDigit value = Right (fromIntegral (ord value - ord '0'))
    | value >= 'a' && value <= 'f' = Right (fromIntegral (ord value - ord 'a' + 10))
    | otherwise = Left (Malformed "native parent receipt hex is not canonical lowercase ASCII")

-- Keep canonical lowercase hexadecimal checked by explicit ASCII code-point bounds.
isAsciiDecimalDigit :: Char -> Bool
isAsciiDecimalDigit value =
  let code = ord value
   in code >= 48 && code <= 57

journalEnvironmentRemovals :: [Text]
journalEnvironmentRemovals =
  [ "JITML_PRODUCT_SCENARIO_JOURNAL_KEY_FILE"
  , "JITML_PRODUCT_SCENARIO_JOURNAL_PATH"
  , "JITML_PRODUCT_SCENARIO_RUN_ID"
  , "JITML_PRODUCT_SCENARIO_EXECUTABLE"
  , "JITML_PRODUCT_SCENARIO_EXECUTABLE_SHA256"
  ]

kindCode :: Attempt.NativeParentAttemptFileKind -> Word64
kindCode Attempt.IssuedRecordFile = 0
kindCode Attempt.ParentReportFile = 1
kindCode Attempt.ParentStdoutFile = 2
kindCode Attempt.ParentStderrFile = 3
kindCode Attempt.RawAvailabilityFile = 4
kindFromCode :: Word64 -> Either CodecError Attempt.NativeParentAttemptFileKind
kindFromCode 0 = Right Attempt.IssuedRecordFile
kindFromCode 1 = Right Attempt.ParentReportFile
kindFromCode 2 = Right Attempt.ParentStdoutFile
kindFromCode 3 = Right Attempt.ParentStderrFile
kindFromCode 4 = Right Attempt.RawAvailabilityFile
kindFromCode _ = Left (Malformed "native parent receipt file kind differs")

canonicalPath :: FilePath -> Either CodecError ()
canonicalPath value = do
  _ <- boundedLength PathTextBytes 4096 value
  boundedText 4096 (Text.pack value)
  require
    ( isAbsolute value
        && normalise value == value
        && all (\c -> c /= '\NUL' && (c < '\xd800' || c > '\xdfff')) value
    )
    "native parent receipt path is not canonical absolute scalar text"
boundedTexts :: Integer -> Integer -> [Text] -> Either CodecError ()
boundedTexts count cap values = do
  _ <- boundedLength AggregateSequenceElements count values
  mapM_ (boundedText cap) values
boundedText :: Integer -> Text -> Either CodecError ()
boundedText cap value =
  require
    (toInteger (Text.length value) <= cap && toInteger (BS.length (UTF8.encodeUtf8 value)) <= cap)
    "native parent receipt text exceeds its byte limit"
canonicalSha :: Text -> Bool
canonicalSha value = Text.length value == 64 && Text.all (`elem` ("0123456789abcdef" :: String)) value
hex :: ByteString -> Text
hex =
  Text.pack
    . concatMap
      (\byte -> [intToDigit (fromIntegral byte `div` 16), intToDigit (fromIntegral byte `mod` 16)])
    . BS.unpack
require :: Bool -> Text -> Either CodecError ()
require condition detail = unless condition (Left (Malformed detail))
