{-# LANGUAGE OverloadedStrings #-}

-- | CPU-only aggregation of the exact, independently issued lane journals.
-- Raw bytes refine through the production lane reader before the join. Neither
-- Markdown cells nor a caller-supplied total can construct the opaque result.
module JitML.Test.ProductAggregation
  ( ProductAggregation
  , ProductAggregationError (..)
  , ProductAggregateRow
  , ProductLaneInput (..)
  , admitProductAggregation
  , admitProductAggregationWithQualifications
  , aggregateProductLaneJournals
  , aggregateProductLaneJournalsWithQualifications
  , aggregateProductLaneJournalsWithNativeBundles
  , loadProductAggregation
  , loadRegisteredProductAggregationIn
  , aggregateRegisteredProductLaneEvidence
  , loadProductAggregationFrom
  , readRetainedProductAggregation
  , productAggregationBytes
  , productAggregationRows
  , productAggregationCellCount
  , productAggregateRowId
  , productAggregateRowLanes
  , productAggregatePath
  , productLaneInputs
  )
where

import Control.Exception (IOException, try)
import Control.Monad (unless)
import Data.Aeson (Value, encode, object, (.=))
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Either.Combinators (mapLeft)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Plan.Plan (Validation (..), planIdText)
import JitML.Product.LaneRegistration qualified as Registration
import JitML.Product.LaneRegistrationData qualified as RegistrationData
import JitML.Product.Matrix qualified as Product
import JitML.Product.QualificationObjects (readProductLaneQualificationObjects)
import JitML.Product.ValidationRecord (sha256Hex)
import JitML.Substrate (Substrate (..), renderSubstrate)
import JitML.Test.ProductLaneJournal qualified as Lane
import JitML.Test.RegisteredLaneEvidence qualified as Registered
import JitML.Training.Budget qualified as Budget

data ProductLaneInput = ProductLaneInput
  { productLaneInputSubstrate :: !Substrate
  , productLaneInputPath :: !FilePath
  , productLaneInputSha256 :: !Text
  }
  deriving stock (Eq, Show)

-- | Historical owner pins, retained for the explicit historical/pure readers.
-- Current production loading uses separately governed append-only registrations;
-- these older literals never satisfy a missing current registration.
productLaneInputs :: [ProductLaneInput]
productLaneInputs =
  [ ProductLaneInput
      LinuxCPU
      "DEVELOPMENT_PLAN/attestations/linux-cpu-product-lane-journal.json"
      "438931ad8c49e1e7365e441ae519fc02df4443895416c80b599c50f89dac05ff"
  , ProductLaneInput
      LinuxCUDA
      "DEVELOPMENT_PLAN/attestations/linux-cuda-product-lane-journal.json"
      "5637c4dc37fdbbecc639572e75ef46887541a0769856289611f2d130faf7dd48"
  , ProductLaneInput
      AppleSilicon
      "DEVELOPMENT_PLAN/attestations/apple-silicon-product-lane-journal.json"
      "1496c8632bb62d616ea99990774b2c5c2e2d95e148834a3932b6aae5e31d7621"
  ]

productAggregatePath :: FilePath
productAggregatePath = "DEVELOPMENT_PLAN/attestations/product-aggregate.json"

data ProductAggregation
  = ProductAggregation
      ![(ProductLaneInput, Lane.AdmittedProductLaneJournal)]
      ![ProductAggregateRow]
  deriving stock (Eq, Show)

-- | Three required cells, rather than a possibly incomplete list of lanes.
-- PlanIds are lane-specific and are checked against each lane's projection;
-- row identity is the join key, not equality of plans across substrates.
data ProductAggregateRow
  = ProductAggregateRow
      !Text
      !Product.RowFamily
      !Lane.ProductLaneJournalRow
      !Lane.ProductLaneJournalRow
      !Lane.ProductLaneJournalRow
  deriving stock (Eq, Show)

data ProductAggregationError
  = ProductAggregationLaneCoverage ![(Substrate, Int)]
  | ProductAggregationUnregisteredInput !Substrate
  | ProductAggregationProjectionRejected !Substrate !(NonEmpty Product.ProductMatrixError)
  | ProductAggregationLaneRejected !Substrate !(NonEmpty Lane.ProductLaneJournalError)
  | ProductAggregationMissingRow !Substrate !Text
  | ProductAggregationIOFailure !FilePath !Text
  | ProductAggregationReportDrift !FilePath
  | ProductAggregationRegisteredLaneRejected !Substrate !Registered.RegisteredLaneError
  deriving stock (Eq, Show)

-- | Admit every input against the complete current projection, then join in
-- registry order. Input order cannot alter the canonical aggregate.
aggregateProductLaneJournals
  :: [(ProductLaneInput, ByteString)]
  -> Either (NonEmpty ProductAggregationError) ProductAggregation
aggregateProductLaneJournals =
  aggregateProductLaneJournalsWithQualifications . fmap (\(input, bytes) -> (input, bytes, []))

-- | Explicit object bytes accompany each pinned lane journal. The legacy pure
-- entrypoint supplies no objects and therefore cannot attest current supervised
-- qualification. No caller-provided summaries replace the production reader.
aggregateProductLaneJournalsWithQualifications
  :: [(ProductLaneInput, ByteString, [(Text, ByteString)])]
  -> Either (NonEmpty ProductAggregationError) ProductAggregation
aggregateProductLaneJournalsWithQualifications inputs = do
  let counts =
        [ (lane, length [() | (input, _, _) <- inputs, productLaneInputSubstrate input == lane])
        | lane <- [LinuxCPU, LinuxCUDA, AppleSilicon]
        ]
  unless (all ((== 1) . snd) counts) $
    Left (ProductAggregationLaneCoverage counts :| [])
  admitted <- traverse admitLane inputs
  finishAdmittedProductLaneJournals admitted
 where
  admitLane (input, bytes, qualifications) = do
    let lane = productLaneInputSubstrate input
    unless (input `elem` productLaneInputs) $
      Left (ProductAggregationUnregisteredInput lane :| [])
    batch <-
      case Product.projectProductRows lane Product.allProductRows of
        Failure errors -> Left (ProductAggregationProjectionRejected lane errors :| [])
        Success value -> Right value
    journal <-
      case Lane.admitProductLaneJournalWithQualifications
        qualifications
        (productLaneInputSha256 input)
        batch
        bytes of
        Left errors -> Left (ProductAggregationLaneRejected lane errors :| [])
        Right value -> Right value
    pure (input, journal)

-- Actual native file audit is required in addition to the unchanged pure
-- supervised path. This accepts no arbitrary execution or validation callback.
aggregateProductLaneJournalsWithNativeBundles
  :: [(ProductLaneInput, FilePath, ByteString, [(Text, ByteString)])]
  -> IO (Either (NonEmpty ProductAggregationError) ProductAggregation)
aggregateProductLaneJournalsWithNativeBundles inputs = do
  let counts =
        [ (lane, length [() | (input, _, _, _) <- inputs, productLaneInputSubstrate input == lane])
        | lane <- [LinuxCPU, LinuxCUDA, AppleSilicon]
        ]
  if not (all ((== 1) . snd) counts)
    then pure (Left (ProductAggregationLaneCoverage counts :| []))
    else do
      captured <- traverse auditLane inputs
      pure (sequence captured >>= finishAdmittedProductLaneJournals)
 where
  auditLane (input, path, bytes, objects)
    | input `notElem` productLaneInputs =
        pure (Left (ProductAggregationUnregisteredInput (productLaneInputSubstrate input) :| []))
    | otherwise = case Product.projectProductRows (productLaneInputSubstrate input) Product.allProductRows of
        Failure errors ->
          pure (Left (ProductAggregationProjectionRejected (productLaneInputSubstrate input) errors :| []))
        Success batch -> do
          actual <-
            Lane.admitProductLaneJournalWithNativeBundles
              path
              objects
              (productLaneInputSha256 input)
              batch
              bytes
          pure
            ( case actual of
                Left errors -> Left (ProductAggregationLaneRejected (productLaneInputSubstrate input) errors :| [])
                Right journal -> Right (input, journal)
            )

finishAdmittedProductLaneJournals
  :: [(ProductLaneInput, Lane.AdmittedProductLaneJournal)]
  -> Either (NonEmpty ProductAggregationError) ProductAggregation
finishAdmittedProductLaneJournals admitted = do
  let cells =
        Map.fromList
          [ ((Lane.productLaneJournalRowSubstrate row, Lane.productLaneJournalRowRowId row), row)
          | (_, journal) <- admitted
          , row <- Lane.admittedProductLaneJournalRows journal
          ]
      requireRow lane rowId =
        maybe
          (Left (ProductAggregationMissingRow lane rowId :| []))
          Right
          (Map.lookup (lane, rowId) cells)
      joinRow row =
        ProductAggregateRow (Product.rowId row) (Product.family row)
          <$> requireRow LinuxCPU (Product.rowId row)
          <*> requireRow LinuxCUDA (Product.rowId row)
          <*> requireRow AppleSilicon (Product.rowId row)
  rows <- traverse joinRow Product.allProductRows
  let orderedSources =
        [ source
        | lane <- [LinuxCPU, LinuxCUDA, AppleSilicon]
        , source@(input, _) <- admitted
        , productLaneInputSubstrate input == lane
        ]
  pure (ProductAggregation orderedSources rows)

loadProductAggregation :: IO (Either (NonEmpty ProductAggregationError) ProductAggregation)
loadProductAggregation = loadRegisteredProductAggregationIn "."

-- | Join only opaque values produced by the actual fixed registration loader
-- and full current native lane admission. No caller-chosen DATA pin replaces
-- the old allowlist in this current production path.
aggregateRegisteredProductLaneEvidence
  :: [Registered.RegisteredLaneEvidence]
  -> Either (NonEmpty ProductAggregationError) ProductAggregation
aggregateRegisteredProductLaneEvidence lanes = do
  let admitted = fmap one lanes
      counts =
        [ (lane, length [() | (input, _) <- admitted, productLaneInputSubstrate input == lane])
        | lane <- [LinuxCPU, LinuxCUDA, AppleSilicon]
        ]
  unless (all ((== 1) . snd) counts) $
    Left (ProductAggregationLaneCoverage counts :| [])
  finishAdmittedProductLaneJournals admitted
 where
  one loaded =
    let generation = Registration.loadedLaneGeneration (Registered.registeredLaneRegistration loaded)
        selected = RegistrationData.laneGenerationJournal generation
     in ( ProductLaneInput
            (RegistrationData.laneGenerationSubstrate generation)
            (Text.unpack (RegistrationData.selectedLaneFilePath selected))
            (RegistrationData.selectedLaneFileSha256 selected)
        , Registered.registeredLaneJournal loaded
        )

loadRegisteredProductAggregationIn
  :: FilePath
  -> IO (Either (NonEmpty ProductAggregationError) ProductAggregation)
loadRegisteredProductAggregationIn root = do
  loaded <- traverse loadLane [LinuxCPU, LinuxCUDA, AppleSilicon]
  pure (sequence loaded >>= aggregateRegisteredProductLaneEvidence)
 where
  loadLane lane = do
    actual <- Registered.loadRegisteredLaneEvidenceIn root lane
    pure (mapLeft ((:| []) . ProductAggregationRegisteredLaneRejected lane) actual)

loadProductAggregationFrom
  :: [ProductLaneInput]
  -> IO (Either (NonEmpty ProductAggregationError) ProductAggregation)
loadProductAggregationFrom inputs = do
  loaded <- traverse readInput inputs
  case sequence loaded of
    Left failures -> pure (Left failures)
    Right actual -> aggregateProductLaneJournalsWithNativeBundles actual
 where
  readInput input = do
    captured <- readBytes (productLaneInputPath input)
    case captured of
      Left errors -> pure (Left errors)
      Right bytes
        | sha256Hex bytes /= productLaneInputSha256 input ->
            pure
              ( Left
                  ( ProductAggregationLaneRejected
                      (productLaneInputSubstrate input)
                      (Lane.ProductLaneJournalDigestMismatch (productLaneInputSha256 input) (sha256Hex bytes) :| [])
                      :| []
                  )
              )
      Right bytes -> do
        qualifications <- readProductLaneQualificationObjects (productLaneInputPath input) bytes
        pure $
          case qualifications of
            Left err -> Left (ProductAggregationLaneRejected (productLaneInputSubstrate input) (err :| []) :| [])
            Right objects -> Right (input, productLaneInputPath input, bytes, objects)

-- | The retained report is a projection, never an independent evidence source.
-- Recompute it from admitted pinned inputs and reject any byte-level drift,
-- including version changes, altered measurements, counts, or source bindings.
admitProductAggregation
  :: [(ProductLaneInput, ByteString)]
  -> ByteString
  -> Either (NonEmpty ProductAggregationError) ProductAggregation
admitProductAggregation inputs =
  admitProductAggregationWithQualifications
    (fmap (\(input, journal) -> (input, journal, [])) inputs)

admitProductAggregationWithQualifications
  :: [(ProductLaneInput, ByteString, [(Text, ByteString)])]
  -> ByteString
  -> Either (NonEmpty ProductAggregationError) ProductAggregation
admitProductAggregationWithQualifications inputs bytes = do
  aggregate <- aggregateProductLaneJournalsWithQualifications inputs
  unless (productAggregationBytes aggregate == bytes) $
    Left (ProductAggregationReportDrift productAggregatePath :| [])
  pure aggregate

readRetainedProductAggregation
  :: IO (Either (NonEmpty ProductAggregationError) ProductAggregation)
readRetainedProductAggregation = do
  aggregate <- loadProductAggregation
  bytes <- readBytes productAggregatePath
  pure $ do
    value <- aggregate
    retained <- bytes
    unless (productAggregationBytes value == retained) $
      Left (ProductAggregationReportDrift productAggregatePath :| [])
    pure value

readBytes :: FilePath -> IO (Either (NonEmpty ProductAggregationError) ByteString)
readBytes path = do
  result <- try (ByteString.readFile path) :: IO (Either IOException ByteString)
  pure $ case result of
    Left exception -> Left (ProductAggregationIOFailure path (Text.pack (show exception)) :| [])
    Right bytes -> Right bytes

productAggregationRows :: ProductAggregation -> [ProductAggregateRow]
productAggregationRows (ProductAggregation _ rows) = rows

productAggregationCellCount :: ProductAggregation -> Int
productAggregationCellCount = sum . fmap (length . productAggregateRowLanes) . productAggregationRows

productAggregateRowId :: ProductAggregateRow -> Text
productAggregateRowId (ProductAggregateRow rowId _ _ _ _) = rowId

productAggregateRowLanes :: ProductAggregateRow -> [Lane.ProductLaneJournalRow]
productAggregateRowLanes (ProductAggregateRow _ _ cpu cuda apple) = [cpu, cuda, apple]

productAggregationBytes :: ProductAggregation -> ByteString
productAggregationBytes (ProductAggregation sources rows) =
  LazyByteString.toStrict
    ( encode $
        object
          [ "format" .= ("jitml-product-aggregate" :: Text)
          , "version" .= (1 :: Int)
          , "row_count" .= length rows
          , "lane_count" .= length sources
          , "completed_cell_count" .= sum (fmap (length . productAggregateRowLanes) rows)
          , "sources" .= fmap sourceValue sources
          , "rows" .= fmap rowValue rows
          ]
    )
    <> "\n"
 where
  sourceValue (input, journal) =
    object
      [ "substrate" .= renderSubstrate (Lane.admittedProductLaneJournalSubstrate journal)
      , "path" .= productLaneInputPath input
      , "sha256" .= productLaneInputSha256 input
      , "run_id" .= Lane.admittedProductLaneJournalRunId journal
      , "source_journal_sha256" .= Lane.admittedProductLaneJournalSourceDigest journal
      ]
  rowValue row@(ProductAggregateRow rowId family _ _ _) =
    object
      [ "row_id" .= rowId
      , "family" .= Product.renderRowFamily family
      , "lanes" .= fmap laneValue (productAggregateRowLanes row)
      ]

laneValue :: Lane.ProductLaneJournalRow -> Value
laneValue row =
  object
    [ "substrate" .= renderSubstrate (Lane.productLaneJournalRowSubstrate row)
    , "plan_id" .= planIdText (Lane.productLaneJournalRowPlanId row)
    , "experiment_hash" .= Lane.productLaneJournalRowExperimentHash row
    , "admitted_manifest_sha256" .= Lane.productLaneJournalRowManifestSha row
    , "contract_sha256" .= Lane.productLaneJournalRowContractDigest row
    , "completion_journal_sha256" .= Lane.productLaneJournalRowJournalDigest row
    , "measured_sha256" .= Lane.productLaneJournalRowMeasuredDigest row
    , "device_witness"
        .= Lane.renderProductLaneJournalRowExecutionProvenance row
    , "completed_training" .= Budget.renderCompletedTraining completed
    , "observed_units" .= Budget.completedTrainingObservedUnits completed
    , "update_count" .= Budget.completedTrainingUpdateCount completed
    , "initial_weight_sha256" .= Budget.completedTrainingInitialWeightHash completed
    , "final_weight_sha256" .= Budget.completedTrainingFinalWeightHash completed
    , "dataset_sha256_at_read" .= Budget.completedTrainingDatasetShaAtRead completed
    , "metrics" .= fmap metricValue (Budget.completedTrainingMetrics completed)
    ]
 where
  completed = Lane.productLaneJournalRowCompletedTraining row
  metricValue observation =
    object
      [ "name" .= Budget.coMetricName observation
      , "value" .= Budget.coMetricValue observation
      , "goal" .= Text.pack (show (Budget.coMetricGoal observation))
      , "threshold" .= Budget.coThreshold observation
      , "passed" .= Budget.convergencePassed observation
      ]
