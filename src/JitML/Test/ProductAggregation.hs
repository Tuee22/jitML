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
  , aggregateProductLaneJournals
  , loadProductAggregation
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
import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Plan.Plan (Validation (..), planIdText)
import JitML.Product.DeviceWitness qualified as DeviceWitness
import JitML.Product.Matrix qualified as Product
import JitML.Substrate (Substrate (..), renderSubstrate)
import JitML.Test.ProductLaneJournal qualified as Lane
import JitML.Training.Budget qualified as Budget

data ProductLaneInput = ProductLaneInput
  { productLaneInputSubstrate :: !Substrate
  , productLaneInputPath :: !FilePath
  , productLaneInputSha256 :: !Text
  }
  deriving stock (Eq, Show)

-- | These pins are the retained outputs of the independent real lane owners,
-- not digests calculated from whichever bytes happen to be present at read time.
productLaneInputs :: [ProductLaneInput]
productLaneInputs =
  [ ProductLaneInput
      LinuxCPU
      "DEVELOPMENT_PLAN/attestations/linux-cpu-product-lane-journal.json"
      "f1bdb6d7941327e44ab9045c45d6f73dfaa96aa37e01234eb4f3969f8e5eb273"
  , ProductLaneInput
      LinuxCUDA
      "DEVELOPMENT_PLAN/attestations/linux-cuda-product-lane-journal.json"
      "e90dd1cdd633050987775e9566099ea7307abfdd8e2dd0f3a3d0326c85e4e6ea"
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
  deriving stock (Eq, Show)

-- | Admit every input against the complete current projection, then join in
-- registry order. Input order cannot alter the canonical aggregate.
aggregateProductLaneJournals
  :: [(ProductLaneInput, ByteString)]
  -> Either (NonEmpty ProductAggregationError) ProductAggregation
aggregateProductLaneJournals inputs = do
  let counts =
        [ (lane, length (filter ((== lane) . productLaneInputSubstrate . fst) inputs))
        | lane <- [LinuxCPU, LinuxCUDA, AppleSilicon]
        ]
  unless (all ((== 1) . snd) counts) $
    Left (ProductAggregationLaneCoverage counts :| [])
  admitted <- traverse admitLane inputs
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
 where
  admitLane (input, bytes) = do
    let lane = productLaneInputSubstrate input
    unless (input `elem` productLaneInputs) $
      Left (ProductAggregationUnregisteredInput lane :| [])
    batch <-
      case Product.projectProductRows lane Product.allProductRows of
        Failure errors -> Left (ProductAggregationProjectionRejected lane errors :| [])
        Success value -> Right value
    journal <-
      case Lane.admitProductLaneJournal (productLaneInputSha256 input) batch bytes of
        Left errors -> Left (ProductAggregationLaneRejected lane errors :| [])
        Right value -> Right value
    pure (input, journal)

loadProductAggregation :: IO (Either (NonEmpty ProductAggregationError) ProductAggregation)
loadProductAggregation = loadProductAggregationFrom productLaneInputs

loadProductAggregationFrom
  :: [ProductLaneInput]
  -> IO (Either (NonEmpty ProductAggregationError) ProductAggregation)
loadProductAggregationFrom inputs = do
  loaded <- traverse readInput inputs
  pure (sequence loaded >>= aggregateProductLaneJournals)
 where
  readInput input =
    fmap ((input,) <$>) (readBytes (productLaneInputPath input))

-- | The retained report is a projection, never an independent evidence source.
-- Recompute it from admitted pinned inputs and reject any byte-level drift,
-- including version changes, altered measurements, counts, or source bindings.
admitProductAggregation
  :: [(ProductLaneInput, ByteString)]
  -> ByteString
  -> Either (NonEmpty ProductAggregationError) ProductAggregation
admitProductAggregation inputs bytes = do
  aggregate <- aggregateProductLaneJournals inputs
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
        .= DeviceWitness.renderDeviceExecutionWitness (Lane.productLaneJournalRowDeviceWitness row)
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
