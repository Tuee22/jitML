{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

-- | In-process journal fixtures for the journal negative controls.
--
-- A journal scenario is built end to end through the production path and
-- never assembled by hand: a completed checkpoint is written and admitted by
-- the Store, a real local-executable workflow mints the completed-scenario
-- evidence from that admission, the evidence is aggregated into a report, and
-- the production writer persists the HMAC-authenticated journal.  Controls then
-- corrupt the persisted JSON, or the Store beneath it, and call the production
-- reader.  Nothing here re-derives admission: it only builds inputs and
-- perturbs them.
--
-- The one piece of logic mirrored from production is the canonical run-receipt
-- material, needed to model a holder of the journal key re-signing a rewritten
-- journal.  'resignJournalValue' is therefore always used together with an
-- identity check ('resignedIdentityReadable'): re-signing the unmodified
-- journal must still be admitted by the production reader, so a drift between
-- this mirror and the production material fails the control's fixture loudly
-- instead of silently degrading it into a plain authentication failure.
module JitML.Test.JournalFixtures
  ( JournalScenario (..)
  , dropRowField
  , foreignAdmittedManifestSha
  , laneJournalBytes
  , plantedForeignManifestSha
  , modifyFirstRow
  , readJournalValue
  , readScenarioJournal
  , resignJournalValue
  , resignedIdentityReadable
  , setJournalField
  , setRowField
  , sha256Hex
  , withJournalScenario
  , writeJournalValue
  , writeScenarioJournalValue
  , zeroDigest
  )
where

import Crypto.Hash.SHA256 qualified as SHA256
import Data.Aeson (Value)
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as AesonKey
import Data.Aeson.KeyMap qualified as AesonKeyMap
import Data.Aeson.Types qualified as AesonTypes
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.List (find)
import Data.List.NonEmpty (NonEmpty)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector qualified as Vector
import Data.Word (Word64)
import Numeric (showHex)
import System.Directory (copyFile, createDirectoryIfMissing)
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty.HUnit (assertFailure)

import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Checkpoint.Store qualified as CheckpointStore
import JitML.Plan.Plan (RunKind (..), RunKindWitness (..), Validation (..))
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.SL.Canonicals qualified as SL
import JitML.Substrate (Substrate (..))
import JitML.Test.ContractFixtures
import JitML.Test.ProductLaneJournal qualified as ProductLaneJournal
import JitML.Test.ProductScenarioAuthorization qualified as Authorization
import JitML.Test.ProductScenarioJournal qualified as ProductScenarioJournal
import JitML.Test.Report qualified as Report

-- | One completed, authenticated, persisted single-row journal and everything
-- needed to read it back.
data JournalScenario = JournalScenario
  { jsKey :: ProductScenarioJournal.ProductScenarioJournalKey
  , jsJournalPath :: FilePath
  , jsCheckpointRoot :: FilePath
  , jsRunId :: Text
  , jsExecutablePath :: FilePath
  , jsExecutableSha :: Text
  , jsBatch :: ProductMatrix.ProductProjectionBatch
  , jsRow :: ProductMatrix.ProductRow 'ProductMatrix.Declared
  , jsProjection :: ProductMatrix.ProductProjection 'SupervisedTraining
  , jsAdmitted :: CheckpointStore.AdmittedCompletedCheckpoint
  , jsReport :: Report.CompletedProductScenarioReport
  , jsLaneJournal :: ProductLaneJournal.IssuedProductLaneJournal
  }

-- | Build a scenario for @mnist-shallow-mlp@ on the linux-cpu lane and run the
-- action against it.  Fixture construction failures are raised as HUnit
-- failures, which the control harness reports as a broken fixture.
withJournalScenario :: (JournalScenario -> IO result) -> IO result
withJournalScenario action =
  withSystemTempDirectory "jitml-negative-control-journal" $ \journalDirectory ->
    withAdmittedProductProjection $ \root row projection precondition addressed admitted -> do
      let journalPath = journalDirectory </> "product-scenario-journal.json"
          runId = productScenarioFixtureRunId
          executablePath = Report.productScenarioPreconditionExecutablePath precondition
          executableSha = Report.productScenarioPreconditionExecutableSha256 precondition
          manifestSha =
            CheckpointStore.admittedCheckpointManifestSha
              (CheckpointStore.admittedCompletedCheckpoint admitted)
      batch <-
        case ProductMatrix.projectProductRows LinuxCPU [row] of
          Success value -> pure value
          Failure errors -> assertFailure ("journal fixture batch failed to project: " <> show errors)
      completion <-
        expectRight (Report.executedProductScenarioCompletion precondition projection addressed)
      liveResult <- runProductScenarioWorkflow root manifestSha projection precondition completion
      evidence <- expectRight (Report.completedProductScenarioEvidence projection liveResult)
      report <- expectRight (Report.projectCompletedProductScenarioReport batch [evidence])
      key <- expectRight =<< ProductScenarioJournal.generateProductScenarioJournalKey
      written <-
        ProductScenarioJournal.writeProductScenarioJournalAtomic
          key
          journalPath
          root
          runId
          batch
          report
      expectRight written
      authenticated <-
        expectRight
          =<< ProductScenarioJournal.readAuthenticatedProductScenarioJournal
            key
            journalPath
            root
            runId
            executablePath
            executableSha
            batch
      laneJournal <- expectRight (ProductLaneJournal.buildProductLaneJournal batch authenticated)
      action
        JournalScenario
          { jsKey = key
          , jsJournalPath = journalPath
          , jsCheckpointRoot = root
          , jsRunId = runId
          , jsExecutablePath = executablePath
          , jsExecutableSha = executableSha
          , jsBatch = batch
          , jsRow = row
          , jsProjection = projection
          , jsAdmitted = admitted
          , jsReport = report
          , jsLaneJournal = laneJournal
          }

-- | Read the scenario's journal file through the production reader.
readScenarioJournal
  :: JournalScenario
  -> IO
       ( Either
           (NonEmpty ProductScenarioJournal.ProductScenarioJournalError)
           Report.CompletedProductScenarioReport
       )
readScenarioJournal scenario =
  ProductScenarioJournal.readProductScenarioJournal
    (jsKey scenario)
    (jsJournalPath scenario)
    (jsCheckpointRoot scenario)
    (jsRunId scenario)
    (jsExecutablePath scenario)
    (jsExecutableSha scenario)
    (jsBatch scenario)

-- | The canonical bytes of the scenario's portable lane journal.
laneJournalBytes :: JournalScenario -> ByteString
laneJournalBytes = ProductLaneJournal.issuedProductLaneJournalBytes . jsLaneJournal

-- | Admit a second supervised row (@mnist-deep-mlp@) into the scenario's
-- checkpoint root and return its Store-admitted manifest identity.  The
-- identity is a genuine, admissible checkpoint — of a different row.
foreignAdmittedManifestSha :: JournalScenario -> IO Text
foreignAdmittedManifestSha scenario = do
  row <-
    maybe
      (assertFailure "missing canonical mnist-deep-mlp ProductRow")
      pure
      (find ((== "mnist-deep-mlp") . ProductMatrix.rowId) ProductMatrix.allProductRows)
  problem <-
    maybe
      (assertFailure "missing canonical mnist-deep-mlp problem")
      pure
      (find ((== "mnist-deep-mlp") . SL.problemName) SL.canonicalProblems)
  projection <-
    case ProductMatrix.projectProductRow LinuxCPU row of
      Success (ProductMatrix.SomeProductProjection SupervisedTrainingWitness supervised) ->
        pure supervised
      Success _ -> assertFailure "mnist-deep-mlp did not project as a supervised row"
      Failure errors -> assertFailure ("mnist-deep-mlp failed to project: " <> show errors)
  precondition <-
    expectRight
      =<< Report.observeProductScenarioPrecondition
        productScenarioFixtureRunId
        productScenarioFixtureExecutablePath
        (jsExecutableSha scenario)
        (jsCheckpointRoot scenario)
        projection
  admitted <-
    persistAndAdmitProductCompletion
      (jsCheckpointRoot scenario)
      row
      problem
      projection
      (Report.productScenarioPreconditionInvocation precondition)
  pure
    ( CheckpointStore.admittedCheckpointManifestSha
        (CheckpointStore.admittedCompletedCheckpoint admitted)
    )

-- | Admit the foreign row (see 'foreignAdmittedManifestSha') and then copy its
-- manifest object into the scenario row's own Store namespace, so the address
-- resolves under this row's key although the manifest records the foreign
-- row's experiment.
plantedForeignManifestSha :: JournalScenario -> IO Text
plantedForeignManifestSha scenario = do
  foreignSha <- foreignAdmittedManifestSha scenario
  foreignRow <-
    maybe
      (assertFailure "missing canonical mnist-deep-mlp ProductRow")
      pure
      (find ((== "mnist-deep-mlp") . ProductMatrix.rowId) ProductMatrix.allProductRows)
  let root = jsCheckpointRoot scenario
      ownExperiment = ProductMatrix.productProjectionExperimentHash (jsProjection scenario)
      foreignExperiment = ProductMatrix.productRowExperimentHash foreignRow
  source <-
    either
      (assertFailure . Text.unpack)
      pure
      (CheckpointStore.objectPathForKey root (Checkpoint.manifestKey foreignExperiment foreignSha))
  target <-
    either
      (assertFailure . Text.unpack)
      pure
      (CheckpointStore.objectPathForKey root (Checkpoint.manifestKey ownExperiment foreignSha))
  createDirectoryIfMissing True (takeDirectory target)
  copyFile source target
  pure foreignSha

-- JSON helpers ---------------------------------------------------------------

zeroDigest :: Text
zeroDigest = Text.replicate 64 "0"

readJournalValue :: FilePath -> IO Value
readJournalValue path = do
  payload <- ByteString.readFile path
  case Aeson.eitherDecodeStrict' payload of
    Left err -> assertFailure ("journal fixture JSON did not decode: " <> err)
    Right value -> pure value

writeJournalValue :: FilePath -> Value -> IO ()
writeJournalValue path = LazyByteString.writeFile path . Aeson.encode

writeScenarioJournalValue :: JournalScenario -> Value -> IO ()
writeScenarioJournalValue scenario = writeJournalValue (jsJournalPath scenario)

setJournalField :: Text -> Value -> Value -> Value
setJournalField name value journal =
  case journal of
    Aeson.Object record ->
      Aeson.Object (AesonKeyMap.insert (AesonKey.fromText name) value record)
    other -> other

-- | Rewrite the first row's object.
modifyFirstRow :: (Aeson.Object -> Aeson.Object) -> Value -> Value
modifyFirstRow modifyRow journal =
  case journal of
    Aeson.Object record ->
      case AesonKeyMap.lookup "rows" record of
        Just (Aeson.Array rows) ->
          case Vector.toList rows of
            Aeson.Object first' : rest ->
              Aeson.Object
                ( AesonKeyMap.insert
                    "rows"
                    (Aeson.Array (Vector.fromList (Aeson.Object (modifyRow first') : rest)))
                    record
                )
            _ -> journal
        _ -> journal
    _ -> journal

setRowField :: Text -> Value -> Value -> Value
setRowField name value =
  modifyFirstRow (AesonKeyMap.insert (AesonKey.fromText name) value)

dropRowField :: Text -> Value -> Value
dropRowField name =
  modifyFirstRow (AesonKeyMap.delete (AesonKey.fromText name))

-- | Re-sign a rewritten journal as a holder of the journal key would: replace
-- its run-receipt HMAC with the HMAC of the canonical run-receipt material.
resignJournalValue
  :: ProductScenarioJournal.ProductScenarioJournalKey
  -> Value
  -> Either Text Value
resignJournalValue key journal = do
  material <- runReceiptMaterial journal
  Right
    ( setJournalField
        "run_receipt_hmac_sha256"
        (Aeson.String (Authorization.signProductScenarioJournal key material))
        journal
    )

-- | Re-signing the untouched journal must not change what the production
-- reader thinks of it.  The fixture check that keeps 'resignJournalValue'
-- honest: a 'Left' means the mirrored receipt material has drifted.
resignedIdentityReadable :: JournalScenario -> IO (Either Text ())
resignedIdentityReadable scenario = do
  original <- readJournalValue (jsJournalPath scenario)
  case resignJournalValue (jsKey scenario) original of
    Left err -> pure (Left ("re-signing failed: " <> err))
    Right resigned -> do
      writeScenarioJournalValue scenario resigned
      outcome <- readScenarioJournal scenario
      writeScenarioJournalValue scenario original
      pure $
        case outcome of
          Right _ -> Right ()
          Left errors ->
            Left
              ( "the re-signed, unmodified journal was rejected, so the mirrored receipt material has drifted: "
                  <> Text.pack (show errors)
              )

-- | Canonical run-receipt material, mirroring the production journal's wire
-- material field for field.
runReceiptMaterial :: Value -> Either Text Text
runReceiptMaterial journal =
  case journal of
    Aeson.Object record -> do
      format <- textField "format" record
      version <- wordField "version" record
      runId <- textField "run_id" record
      substrate <- textField "substrate" record
      batchSha <- textField "projection_batch_sha256" record
      scopeSha <- textField "checkpoint_scope_sha256" record
      rows <- rowObjects record
      rowFields <- traverse rowMaterial (zip [(0 :: Int) ..] rows)
      Right
        ( Text.concat
            ( [ receiptField "domain" "jitml-product-scenario-run-receipt-hmac-v1"
              , receiptField "format" format
              , receiptField "version" (showText version)
              , receiptField "run_id" runId
              , receiptField "substrate" substrate
              , receiptField "projection_batch_sha256" batchSha
              , receiptField "checkpoint_scope_sha256" scopeSha
              , receiptField "row_count" (showText (length rows))
              ]
                <> concat rowFields
            )
        )
    _ -> Left "journal JSON is not an object"
 where
  rowMaterial (index, row) = do
    fields <- traverse (rowField row) rowFieldSchema
    Right (receiptField "row_index" (showText index) : fields)

-- | The journal keys folded into each row's receipt, in order, with the label
-- the material uses for each.
rowFieldSchema :: [(Text, Text, FieldKind)]
rowFieldSchema =
  [ ("row_id", "row_id", TextField)
  , ("run_id", "run_id", TextField)
  , ("plan_id", "plan_id", TextField)
  , ("row_substrate", "substrate", TextField)
  , ("executable_path", "executable_path", TextField)
  , ("executable_sha256", "executable_sha256", TextField)
  , ("invocation_digest", "invocation_digest", TextField)
  , ("experiment_hash", "experiment_hash", TextField)
  , ("manifest_sha256", "manifest_sha256", TextField)
  , ("projection_sha256", "projection_sha256", TextField)
  , ("command", "command", TextField)
  , ("contract_sha256", "contract_sha256", TextField)
  , ("execution_journal_receipt", "execution_journal_receipt", TextField)
  , ("execution_journal_sha256", "execution_journal_sha256", TextField)
  , ("inference_experiment_hash", "inference_experiment_hash", TextField)
  , ("inference_manifest_sha256", "inference_manifest_sha256", TextField)
  , ("precondition_rejected", "precondition_rejected", BoolField)
  , ("precondition_sequence", "precondition_sequence", WordField)
  , ("inference_sequence", "inference_sequence", WordField)
  , ("completion_sequence", "completion_sequence", WordField)
  ]

data FieldKind = TextField | BoolField | WordField

rowField :: Aeson.Object -> (Text, Text, FieldKind) -> Either Text Text
rowField row (label, key, kind) =
  case kind of
    TextField -> receiptField label <$> textField key row
    BoolField -> receiptField label . showText <$> boolField key row
    WordField -> receiptField label . showText <$> wordField key row

rowObjects :: Aeson.Object -> Either Text [Aeson.Object]
rowObjects record =
  case AesonKeyMap.lookup "rows" record of
    Just (Aeson.Array rows) ->
      traverse
        ( \case
            Aeson.Object object -> Right object
            _ -> Left "a journal row is not an object"
        )
        (Vector.toList rows)
    _ -> Left "journal JSON has no rows array"

textField :: Text -> Aeson.Object -> Either Text Text
textField = jsonField

boolField :: Text -> Aeson.Object -> Either Text Bool
boolField = jsonField

wordField :: Text -> Aeson.Object -> Either Text Word64
wordField = jsonField

jsonField :: (Aeson.FromJSON value) => Text -> Aeson.Object -> Either Text value
jsonField name object =
  first
    (\detail -> "journal field " <> name <> ": " <> Text.pack detail)
    (AesonTypes.parseEither (\record -> record Aeson..: AesonKey.fromText name) object)

receiptField :: Text -> Text -> Text
receiptField label value =
  label <> "=" <> showText (Text.length value) <> ":" <> value <> "\n"

showText :: (Show value) => value -> Text
showText = Text.pack . show

-- | Lowercase-hex SHA-256 of the exact bytes.
sha256Hex :: ByteString -> Text
sha256Hex bytes =
  Text.pack (concatMap byteHex (ByteString.unpack (SHA256.hash bytes)))
 where
  byteHex byte =
    case showHex byte "" of
      [low] -> ['0', low]
      pair -> pair
