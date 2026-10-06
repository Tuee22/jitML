{-# LANGUAGE OverloadedStrings #-}

-- | Report measurements projected from completed-training evidence.
--
-- Every value in this module is a pure projection of 'CompletedTraining'
-- values that a validated ProductScenario journal already holds.  Nothing here
-- launches a probe, retrains a model, or accepts a caller-supplied number:
--
-- * a family's report line is the family's rows' own
--   'completedTrainingMetrics', in journal order;
-- * every count is derived from the rows the journal contains, and the
--   eligible denominator is the registry's own row count for the family, so
--   neither side can be a literal;
-- * the evidence types keep their constructors private, so a report cannot be
--   handed a total that no journal row produced.
--
-- Rows are grouped by the 'RowFamily' the admitted completion's budget kind
-- proves.  The registry's projection already requires that budget kind to match
-- the row's family before a completion can be admitted, and the unit tests
-- check the two agree for every registry row.
module JitML.Test.TrainingMeasurement
  ( CompletedRowView (..)
  , FamilyCount
  , FamilyMetrics
  , FamilyRowMetrics (..)
  , MetricReading (..)
  , ProductRowCounts
  , completedRowFamily
  , deriveFamilyMetrics
  , deriveProductRowCounts
  , familyCountCompleted
  , familyCountEligible
  , familyCountFamily
  , familyMetricsFamily
  , familyMetricsRows
  , familyOfBudgetKind
  , productRowCountsByFamily
  , productRowCountsCompleted
  , productRowCountsEligible
  , productRowCountsMeasurement
  , renderFamilyMetrics
  , renderProductRowCounts
  , reportFamilies
  , trainingFamilyMeasurements
  )
where

import Data.Foldable (toList)
import Data.Function (on)
import Data.List qualified as List
import Data.List.NonEmpty (NonEmpty)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Product.Matrix (RowFamily (..))
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Test.Measurement
  ( Measurement (..)
  , UnavailableReason (..)
  )
import JitML.Training.Budget
  ( BudgetKind (..)
  , CompletedTraining
  , MetricGoal
  , coMetricGoal
  , coMetricName
  , coMetricValue
  , coThreshold
  , completedTrainingBudget
  , completedTrainingMetrics
  , trainingBudgetKind
  )

-- | One completed product row as an admitted journal states it: the registry
-- row identity and the refined completion.  Adapters from the live report and
-- from portable lane journals both produce this shape, so one derivation
-- serves every validated source.
data CompletedRowView = CompletedRowView
  { completedRowId :: !Text
  , completedRowTraining :: !CompletedTraining
  }
  deriving stock (Eq, Show)

-- | One finite, criterion-evaluated observation of a completed row.
data MetricReading = MetricReading
  { metricReadingName :: !Text
  , metricReadingGoal :: !MetricGoal
  , metricReadingThreshold :: !Double
  , metricReadingValue :: !Double
  }
  deriving stock (Eq, Show)

-- | The observations of one completed row.  A 'CompletedTraining' carries at
-- least one passed observation by construction.
data FamilyRowMetrics = FamilyRowMetrics
  { familyRowMetricsRowId :: !Text
  , familyRowMetricsReadings :: ![MetricReading]
  }
  deriving stock (Eq, Show)

-- | Metrics of every completed row of one family, in journal order.  The
-- constructor is private and the rows are non-empty: a family with no completed
-- row has no 'FamilyMetrics' and is reported as unavailable instead.
data FamilyMetrics = FamilyMetrics !RowFamily !(NonEmpty FamilyRowMetrics)
  deriving stock (Eq, Show)

familyMetricsFamily :: FamilyMetrics -> RowFamily
familyMetricsFamily (FamilyMetrics family _) = family

familyMetricsRows :: FamilyMetrics -> NonEmpty FamilyRowMetrics
familyMetricsRows (FamilyMetrics _ rows) = rows

-- | Completed and eligible row counts of one family.
data FamilyCount = FamilyCount !RowFamily !Int !Int
  deriving stock (Eq, Show)

familyCountFamily :: FamilyCount -> RowFamily
familyCountFamily (FamilyCount family _ _) = family

familyCountCompleted :: FamilyCount -> Int
familyCountCompleted (FamilyCount _ completed _) = completed

familyCountEligible :: FamilyCount -> Int
familyCountEligible (FamilyCount _ _ eligible) = eligible

-- | Row counts derived from journal rows.  The constructor is private: the
-- only producer is 'deriveProductRowCounts', so no caller-supplied total can
-- construct one.
newtype ProductRowCounts = ProductRowCounts [FamilyCount]
  deriving stock (Eq, Show)

productRowCountsByFamily :: ProductRowCounts -> [FamilyCount]
productRowCountsByFamily (ProductRowCounts counts) = counts

-- | Completed rows across every family, summed from the derived family counts.
productRowCountsCompleted :: ProductRowCounts -> Int
productRowCountsCompleted =
  sum . fmap familyCountCompleted . productRowCountsByFamily

-- | Registry rows eligible to complete across every family.
productRowCountsEligible :: ProductRowCounts -> Int
productRowCountsEligible =
  sum . fmap familyCountEligible . productRowCountsByFamily

-- | The family a completion's budget kind proves.
familyOfBudgetKind :: BudgetKind -> RowFamily
familyOfBudgetKind kind =
  case kind of
    SupervisedEpochBudget -> Supervised
    RlEnvironmentStepBudget -> ReinforcementLearning
    AlphaZeroSelfPlayBudget -> AlphaZero
    TuningTrialBudget -> Tuning

completedRowFamily :: CompletedRowView -> RowFamily
completedRowFamily =
  familyOfBudgetKind
    . trainingBudgetKind
    . completedTrainingBudget
    . completedRowTraining

-- | The report's training-derived lines, in report order, with the label each
-- family has always rendered under.
reportFamilies :: [(RowFamily, Text)]
reportFamilies =
  [ (Supervised, "sl_final_loss")
  , (ReinforcementLearning, "rl_final_reward")
  , (AlphaZero, "alphazero_arena_win_rate")
  , (Tuning, "tune_best_objective")
  ]

-- | Project one family's metrics from journal rows.  A family the journal
-- holds no completed row for is 'Unavailable', never an empty 'Available'.
deriveFamilyMetrics :: RowFamily -> [CompletedRowView] -> Measurement FamilyMetrics
deriveFamilyMetrics family views =
  case NonEmpty.nonEmpty (fmap rowMetrics familyRows) of
    Just rows -> Available (FamilyMetrics family rows)
    Nothing ->
      Unavailable
        ( NotJournaled
            ( "no completed "
                <> ProductMatrix.renderRowFamily family
                <> " row in the ProductScenario journal"
            )
        )
 where
  familyRows =
    [ view
    | view <- uniqueRows views
    , completedRowFamily view == family
    ]

-- | The four family lines of a report, each a projection of the one
-- product-row journal measurement.  An unrequested journal requests no line;
-- an unavailable journal makes every line unavailable for the same reason.
trainingFamilyMeasurements
  :: Measurement [CompletedRowView]
  -> [(Text, Measurement FamilyMetrics)]
trainingFamilyMeasurements journal =
  [ (label, familyMeasurement family)
  | (family, label) <- reportFamilies
  ]
 where
  familyMeasurement family =
    case journal of
      NotRequested -> NotRequested
      Unavailable reason -> Unavailable reason
      Available views -> deriveFamilyMetrics family views

-- | Count completed rows per family from journal rows.  The eligible side is
-- the registry's own row count for the family.
deriveProductRowCounts :: [CompletedRowView] -> ProductRowCounts
deriveProductRowCounts views =
  ProductRowCounts
    [ FamilyCount
        family
        (length (filter ((== family) . completedRowFamily) completed))
        (registryEligibleRows family)
    | (family, _label) <- reportFamilies
    ]
 where
  completed = uniqueRows views

productRowCountsMeasurement
  :: Measurement [CompletedRowView]
  -> Measurement ProductRowCounts
productRowCountsMeasurement = fmap deriveProductRowCounts

registryEligibleRows :: RowFamily -> Int
registryEligibleRows family =
  length
    [ ()
    | row <- ProductMatrix.allProductRows
    , ProductMatrix.family row == family
    ]

-- | A row is counted once however many times a source repeats it.
uniqueRows :: [CompletedRowView] -> [CompletedRowView]
uniqueRows = List.nubBy ((==) `on` completedRowId)

rowMetrics :: CompletedRowView -> FamilyRowMetrics
rowMetrics view =
  FamilyRowMetrics
    { familyRowMetricsRowId = completedRowId view
    , familyRowMetricsReadings =
        [ MetricReading
            { metricReadingName = coMetricName observation
            , metricReadingGoal = coMetricGoal observation
            , metricReadingThreshold = coThreshold observation
            , metricReadingValue = coMetricValue observation
            }
        | observation <- completedTrainingMetrics (completedRowTraining view)
        ]
    }

-- | @row:metric=value@ for every observation of every row, in journal order.
-- Values use Haskell's round-trippable @show@, exactly as
-- 'JitML.Test.Report.canonicalCompletedTrainingSummary' does.
renderFamilyMetrics :: FamilyMetrics -> Text
renderFamilyMetrics (FamilyMetrics _ rows) =
  Text.intercalate
    ", "
    [ familyRowMetricsRowId row
        <> ":"
        <> metricReadingName reading
        <> "="
        <> Text.pack (show (metricReadingValue reading))
    | row <- toList rows
    , reading <- familyRowMetricsReadings row
    ]

-- | @completed=<n>/<eligible>@ followed by one @<family>=<n>/<eligible>@ per
-- family.
renderProductRowCounts :: ProductRowCounts -> Text
renderProductRowCounts counts =
  Text.unwords
    ( ( "completed="
          <> ratio (productRowCountsCompleted counts) (productRowCountsEligible counts)
      )
        : [ ProductMatrix.renderRowFamily (familyCountFamily familyCount)
              <> "="
              <> ratio (familyCountCompleted familyCount) (familyCountEligible familyCount)
          | familyCount <- productRowCountsByFamily counts
          ]
    )
 where
  ratio completed eligible = Text.pack (show completed) <> "/" <> Text.pack (show eligible)
