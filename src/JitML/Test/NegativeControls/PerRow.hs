{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

-- | Phase 282 — mandatory per-row registration of negative controls.
--
-- Every product workflow row must register at least one known-invalid fixture,
-- and the standing stanza fails when any of them is accepted.  Registration is
-- /derived/, not hand-authored: 'registerRow' maps a registry row to its
-- 'RowRegistration' by its family, and the family is a closed sum, so a new
-- 'ProductMatrix.ProductRunKind' or 'ProductMatrix.RowFamily' does not compile
-- until it has specs.  A new row added to 'ProductMatrix.allProductRows' is
-- registered, and gets its three controls, without anyone remembering to add
-- them.
--
-- Each registered row runs three controls, all against production gates:
--
-- * @row-\<id\>-invalid-request@ — the row's own request with a zeroed
--   quantity of its budget must be rejected by 'ProductMatrix.projectProductRow'
--   (a zeroed training-example count, evaluation-episode count, parallel-trial
--   count, or arena-game count, by kind), with exactly the rejection the kind
--   yields;
-- * @row-\<id\>-wrong-plan-event@ — the row's own plan identity is fed into its
--   kind's live evidence contract, the row's own event is accepted, and the same
--   event stamped with another row's plan is rejected with the kind's specific
--   plan-mismatch violation;
-- * @row-\<id\>-foreign-admission@ — a completed checkpoint that the Store
--   admitted for another row must not satisfy this row's completion
--   ('Report.productScenarioCompletion'), and the rejection names the four
--   identity mismatches.
--
-- The guard 'rowRegistrationFailuresFor' checks four views against each other:
-- the registry ('ProductMatrix.allProductRows'), the projection batch
-- ('ProductMatrix.projectProductRows'), the registrations, and the per-row
-- controls of the /committed control list/ the caller passes
-- ('realRowRegistryFacts').  The standing stanza and the unit twin pass the list
-- the stanza really runs ('JitML.Test.NegativeControls.allNegativeControls'),
-- never 'perRowControls' itself: the registrations and 'perRowControls' are both
-- derived from the registry, so only the committed list can notice a per-row
-- control that was dropped from, or never added to, what the stanza runs.  It
-- reports a row without a registration, a row registered twice, a registration
-- or control that names no row, a run kind without specs, a spec whose family is
-- not its row's, and a registered spec whose control the committed list lacks.
module JitML.Test.NegativeControls.PerRow
  ( PerRowFixture (..)
  , AdmittedRow (..)
  , RowRegistration (..)
  , RowRegistryFacts (..)
  , RowSpec (..)
  , RowSpecKind (..)
  , allRowRegistrations
  , buildPerRowFixture
  , familyRunKind
  , perRowControlName
  , perRowControls
  , perRowFixtureBaselineFailures
  , perRowRegistrationTests
  , realRowRegistryFacts
  , registerRow
  , renderRowSpecKind
  , rowBaselineFailures
  , rowRegistrationFailures
  , rowRegistrationFailuresFor
  , runKindFamily
  , specsForRunKind
  , withoutFirst
  )
where

import Control.Exception (evaluate)
import Data.Bifunctor (first)
import Data.Foldable (toList)
import Data.Functor (void)
import Data.List (find, group, sort)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word32, Word64)
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertEqual, testCase)

import JitML.Checkpoint.Store qualified as CheckpointStore
import JitML.Plan.Plan
  ( PlanError (..)
  , PlanId
  , RunKind (..)
  , RunKindWitness (..)
  , Validation (..)
  , planIdText
  , quantityValue
  )
import JitML.Plan.Workload
  ( WorkloadPlanError (..)
  , alphaZeroPlanId
  , alphaZeroPlanSelfPlayGames
  , tuningPlanId
  )
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Proto.Rl qualified as Rl
import JitML.Proto.Tune qualified as Tune
import JitML.Run.Contract (initialProgress)
import JitML.Run.WorkloadContract
  ( WorkloadContractViolation (..)
  , alphaZeroCompletionContract
  , ingestAlphaZeroEvent
  , ingestTuneEvent
  , tuningCompletionContract
  )
import JitML.SL.Canonicals qualified as SL
import JitML.Substrate (Substrate (..))
import JitML.Test.ContractFixtures (persistAndAdmitUnboundProductCompletion)
import JitML.Test.ControlFixtures
  ( alphaZeroGenerationEvent
  , rlEvaluationEvent
  , supervisedCompletedCheckpointFor
  , tuneTrialFinishedEvent
  )
import JitML.Test.LiveEvidence qualified as LiveEvidence
import JitML.Test.NegativeControls.Core
import JitML.Test.Report qualified as Report
import JitML.Training.Budget qualified as TrainingBudget

-- Registration -----------------------------------------------------------------

-- | What a row's controls try to break.
data RowSpecKind
  = InvalidRequest
  | WrongPlanEvent
  | ForeignAdmission
  deriving stock (Eq, Ord, Show, Enum, Bounded)

renderRowSpecKind :: RowSpecKind -> Text
renderRowSpecKind kind =
  case kind of
    InvalidRequest -> "invalid-request"
    WrongPlanEvent -> "wrong-plan-event"
    ForeignAdmission -> "foreign-admission"

-- | One control a row registers: what it breaks, for which run kind and family.
data RowSpec = RowSpec
  { specKind :: RowSpecKind
  , specRunKind :: ProductMatrix.ProductRunKind
  , specFamily :: ProductMatrix.RowFamily
  }
  deriving stock (Eq, Show)

-- | A row's registration: the row and the non-empty list of controls it
-- registers.  The list cannot be empty.
data RowRegistration = RowRegistration
  { registeredRowId :: Text
  , registeredRunKind :: ProductMatrix.ProductRunKind
  , registeredSpecs :: NonEmpty RowSpec
  }
  deriving stock (Eq, Show)

-- | Total over the closed family.
familyRunKind :: ProductMatrix.RowFamily -> ProductMatrix.ProductRunKind
familyRunKind family =
  case family of
    ProductMatrix.Supervised -> ProductMatrix.ProductSupervisedRun
    ProductMatrix.ReinforcementLearning -> ProductMatrix.ProductRlRun
    ProductMatrix.Tuning -> ProductMatrix.ProductTuningRun
    ProductMatrix.AlphaZero -> ProductMatrix.ProductAlphaZeroRun

-- | Total over the closed run kind.
runKindFamily :: ProductMatrix.ProductRunKind -> ProductMatrix.RowFamily
runKindFamily kind =
  case kind of
    ProductMatrix.ProductSupervisedRun -> ProductMatrix.Supervised
    ProductMatrix.ProductRlRun -> ProductMatrix.ReinforcementLearning
    ProductMatrix.ProductTuningRun -> ProductMatrix.Tuning
    ProductMatrix.ProductAlphaZeroRun -> ProductMatrix.AlphaZero

-- | The controls every row of a run kind registers.  Total over the run kinds
-- (with the library's @-Werror=incomplete-patterns@), so a kind added to the
-- registry cannot be left without specs.
specsForRunKind :: ProductMatrix.ProductRunKind -> NonEmpty RowSpec
specsForRunKind kind =
  case kind of
    ProductMatrix.ProductSupervisedRun -> specsOf ProductMatrix.Supervised
    ProductMatrix.ProductRlRun -> specsOf ProductMatrix.ReinforcementLearning
    ProductMatrix.ProductTuningRun -> specsOf ProductMatrix.Tuning
    ProductMatrix.ProductAlphaZeroRun -> specsOf ProductMatrix.AlphaZero
 where
  specsOf family =
    fmap
      (\specKind' -> RowSpec {specKind = specKind', specRunKind = kind, specFamily = family})
      (InvalidRequest :| [WrongPlanEvent, ForeignAdmission])

-- | Derive a row's registration from its family.
registerRow :: ProductMatrix.ProductRow 'ProductMatrix.Declared -> RowRegistration
registerRow row =
  RowRegistration
    { registeredRowId = ProductMatrix.rowId row
    , registeredRunKind = kind
    , registeredSpecs = specsForRunKind kind
    }
 where
  kind = familyRunKind (ProductMatrix.family row)

-- | One registration per registry row, in registry order.
allRowRegistrations :: [RowRegistration]
allRowRegistrations = fmap registerRow ProductMatrix.allProductRows

perRowControlName :: Text -> RowSpecKind -> Text
perRowControlName rowIdentity kind = "row-" <> rowIdentity <> "-" <> renderRowSpecKind kind

-- The registration guard ------------------------------------------------------------

-- | What the guard compares: four views of the rows.
data RowRegistryFacts = RowRegistryFacts
  { factRegistry :: [(Text, ProductMatrix.RowFamily)]
  -- ^ The registry: each row's identity and family.
  , factBatch :: Either Text [Text]
  -- ^ The identities of the projection batch, or why the registry does not project.
  , factRegistrations :: [RowRegistration]
  , factControlNames :: [Text]
  -- ^ The names of the 'PerRow' controls in the committed control list.
  }

-- | The facts of the real registry and registrations against a committed control
-- list.  The caller passes the list the standing stanza runs, so the control view
-- is not derived from 'perRowControls' (as the registrations are): a per-row
-- control that was dropped from that list, or filed under another category, is
-- missing from 'factControlNames' and reported by the guard.
realRowRegistryFacts :: [NegativeControl] -> RowRegistryFacts
realRowRegistryFacts committed =
  RowRegistryFacts
    { factRegistry =
        [(ProductMatrix.rowId row, ProductMatrix.family row) | row <- ProductMatrix.allProductRows]
    , factBatch =
        case ProductMatrix.projectProductRows LinuxCPU ProductMatrix.allProductRows of
          Success batch -> Right (ProductMatrix.productProjectionBatchRowIds batch)
          Failure errors -> Left (Text.pack (show (toList errors)))
    , factRegistrations = allRowRegistrations
    , factControlNames =
        [ncName control | control <- committed, ncCategory control == PerRow]
    }

-- | The guard over the real registry and a committed control list.
rowRegistrationFailures :: [NegativeControl] -> [Text]
rowRegistrationFailures = rowRegistrationFailuresFor . realRowRegistryFacts

-- | Everything wrong with a registration, against the registry, the projection
-- batch, and the controls.  Empty means every row registers its controls and
-- nothing else does.
rowRegistrationFailuresFor :: RowRegistryFacts -> [Text]
rowRegistrationFailuresFor facts =
  registryFailures
    <> registrationFailures
    <> batchFailures
    <> kindFailures
    <> familyFailures
    <> specFailures
    <> controlFailures
 where
  registryIds = fmap fst (factRegistry facts)
  registrations = factRegistrations facts
  registeredIds = fmap registeredRowId registrations

  registryFailures =
    [ "the product registry lists a row twice: " <> identity
    | identity <- duplicated registryIds
    ]

  registrationFailures =
    [ "product row has no registered negative control: " <> identity
    | identity <- registryIds
    , identity `notElem` registeredIds
    ]
      <> [ "product row is registered more than once: " <> identity
         | identity <- duplicated registeredIds
         ]
      <> [ "registration names no product row: " <> identity
         | identity <- distinct registeredIds
         , identity `notElem` registryIds
         ]

  batchFailures =
    case factBatch facts of
      Left detail -> ["the product registry does not project as a batch: " <> detail]
      Right batchIds ->
        [ "product row is in the registry but absent from the projection batch: " <> identity
        | identity <- registryIds
        , identity `notElem` batchIds
        ]
          <> [ "the projection batch names a row absent from the registry: " <> identity
             | identity <- batchIds
             , identity `notElem` registryIds
             ]
          <> [ "a registration names a row absent from the projection batch: " <> identity
             | identity <- distinct registeredIds
             , identity `notElem` batchIds
             ]

  kindFailures =
    concat
      [ [ "no registered row has run kind " <> renderShown kind
        | null ofKind
        ]
          <> [ "run kind "
                 <> renderShown kind
                 <> " registers no "
                 <> renderRowSpecKind specKind'
                 <> " spec"
             | not (null ofKind)
             , specKind' <- [minBound .. maxBound]
             , not (any (any ((== specKind') . specKind) . registeredSpecs) ofKind)
             ]
      | kind <- [minBound .. maxBound]
      , let ofKind = [registration | registration <- registrations, registeredRunKind registration == kind]
      ]

  familyFailures =
    concat
      [ case lookup (registeredRowId registration) (factRegistry facts) of
          Nothing -> []
          Just family ->
            [ "row "
                <> registeredRowId registration
                <> " is registered as run kind "
                <> renderShown (registeredRunKind registration)
                <> " but its family is "
                <> renderShown family
            | familyRunKind family /= registeredRunKind registration
            ]
              <> [ "spec "
                     <> renderRowSpecKind (specKind spec)
                     <> " of row "
                     <> registeredRowId registration
                     <> " is for family "
                     <> renderShown (specFamily spec)
                     <> " but the row is "
                     <> renderShown family
                 | spec <- toList (registeredSpecs registration)
                 , specFamily spec /= family
                 ]
              <> [ "spec "
                     <> renderRowSpecKind (specKind spec)
                     <> " of row "
                     <> registeredRowId registration
                     <> " is for run kind "
                     <> renderShown (specRunKind spec)
                     <> " but the row is registered as "
                     <> renderShown (registeredRunKind registration)
                 | spec <- toList (registeredSpecs registration)
                 , specRunKind spec /= registeredRunKind registration
                 ]
      | registration <- registrations
      ]

  specFailures =
    [ "row " <> registeredRowId registration <> " registers spec " <> renderRowSpecKind kind <> " twice"
    | registration <- registrations
    , kind <- duplicated (fmap specKind (toList (registeredSpecs registration)))
    ]

  expectedControls =
    [ perRowControlName (registeredRowId registration) (specKind spec)
    | registration <- registrations
    , spec <- toList (registeredSpecs registration)
    ]
  controlNames = factControlNames facts

  controlFailures =
    [ "registered spec has no control: " <> name
    | name <- distinct expectedControls
    , name `notElem` controlNames
    ]
      <> [ "control name is committed more than once: " <> name
         | name <- duplicated controlNames
         ]
      <> [ "control names no registered spec: " <> name
         | name <- distinct controlNames
         , name `notElem` expectedControls
         ]

-- | The list without its first element.
withoutFirst :: [value] -> [value]
withoutFirst values =
  case values of
    _ : rest -> rest
    [] -> []

-- | Names that occur more than once, each reported once.
duplicated :: (Ord value) => [value] -> [value]
duplicated values = [value | value : _ : _ <- group (sort values)]

distinct :: (Ord value) => [value] -> [value]
distinct values = [value | value : _ <- group (sort values)]

renderShown :: (Show value) => value -> Text
renderShown = Text.pack . show

-- Row contexts --------------------------------------------------------------------------

-- | A row with its validated projection on the linux-cpu lane and another row's
-- plan identity, taken cyclically, to stamp on foreign evidence.
data RowContext = RowContext
  { contextRow :: ProductMatrix.ProductRow 'ProductMatrix.Declared
  , contextProjection :: ProductMatrix.SomeProductProjection
  , contextForeignPlan :: PlanId
  }

-- | The registry rows with their contexts.  A registry that does not project is
-- reported by each row as an unbuildable baseline, never as a passing control.
rowContexts
  :: [(ProductMatrix.ProductRow 'ProductMatrix.Declared, Either Text RowContext)]
rowContexts =
  case traverse projectRow ProductMatrix.allProductRows of
    Left detail -> [(row, Left detail) | row <- ProductMatrix.allProductRows]
    Right projections ->
      let planIds = fmap (someProjectionPlanId . snd) projections
          foreignIds = withoutFirst planIds <> take 1 planIds
       in [ (row, context)
          | ((row, projection), foreignId) <- zip projections foreignIds
          , let context =
                  if someProjectionPlanId projection == foreignId
                    then
                      Left
                        ( "row "
                            <> ProductMatrix.rowId row
                            <> " has the same plan identity as the row whose plan is stamped on its foreign evidence"
                        )
                    else
                      Right
                        RowContext
                          { contextRow = row
                          , contextProjection = projection
                          , contextForeignPlan = foreignId
                          }
          ]
 where
  projectRow row =
    case ProductMatrix.projectProductRow LinuxCPU row of
      Success projection -> Right (row, projection)
      Failure errors ->
        Left
          ( "row "
              <> ProductMatrix.rowId row
              <> " does not project: "
              <> renderShown (toList errors)
          )

someProjectionPlanId :: ProductMatrix.SomeProductProjection -> PlanId
someProjectionPlanId (ProductMatrix.SomeProductProjection _witness projection) =
  ProductMatrix.productProjectionPlanId projection

-- | Whether every row is a sound baseline for its controls: it projects, and no
-- two rows share a plan identity or an experiment, which would make a foreign
-- fixture indistinguishable from the row's own.  A non-empty result means the
-- per-row controls could be passing only because their baseline was broken.
rowBaselineFailures :: [Text]
rowBaselineFailures =
  [detail | (_row, Left detail) <- rowContexts]
    <> [ "two rows share the plan identity " <> planIdText planId
       | planId <- duplicated planIds
       ]
    <> [ "two rows share the experiment hash " <> experiment
       | experiment <- duplicated experiments
       ]
 where
  projections = [projection | (_row, Right context) <- rowContexts, let projection = contextProjection context]
  planIds = fmap someProjectionPlanId projections
  experiments =
    [ ProductMatrix.productProjectionExperimentHash projection
    | ProductMatrix.SomeProductProjection _witness projection <- projections
    ]

-- Controls ------------------------------------------------------------------------------

-- | A completed checkpoint the Store admitted for one row.
data AdmittedRow = AdmittedRow
  { admittedRowId :: Text
  , admittedExperiment :: Text
  , admittedPlanId :: PlanId
  , admittedCheckpoint :: CheckpointStore.AdmittedCompletedCheckpoint
  , admittedOwnRowAccepts :: Bool
  -- ^ Whether the row's own completion admits its own checkpoint.
  }

-- | Real Store-admitted checkpoints of two different rows, so every row has an
-- admission that is not its own.
newtype PerRowFixture = PerRowFixture
  { fixtureAdmissions :: [AdmittedRow]
  }

-- | Build the fixture through the production Store: write a completed snapshot,
-- admit it through the latest pointer, and require exact completion admission.
-- The admissions are in-memory values, so the Store's scratch directory is not
-- needed once they are built; their acceptance by their own rows is forced
-- inside it.
buildPerRowFixture :: IO PerRowFixture
buildPerRowFixture =
  withSystemTempDirectory "jitml-negative-control-per-row" $ \root -> do
    shallow <- admitSupervisedRow root "mnist-shallow-mlp"
    deep <- admitSupervisedRow root "mnist-deep-mlp"
    pure (PerRowFixture [shallow, deep])

admitSupervisedRow :: FilePath -> Text -> IO AdmittedRow
admitSupervisedRow root identity = do
  row <-
    maybe
      (ioError (userError ("missing canonical ProductRow " <> Text.unpack identity)))
      pure
      (find ((== identity) . ProductMatrix.rowId) ProductMatrix.allProductRows)
  problem <-
    maybe
      (ioError (userError ("missing canonical problem " <> Text.unpack identity)))
      pure
      (find ((== identity) . SL.problemName) SL.canonicalProblems)
  projection <-
    case ProductMatrix.projectProductRow LinuxCPU row of
      Success (ProductMatrix.SomeProductProjection SupervisedTrainingWitness supervised) -> pure supervised
      Success _ -> ioError (userError (Text.unpack identity <> " did not project as a supervised row"))
      Failure errors ->
        ioError (userError (Text.unpack identity <> " failed to project: " <> show (toList errors)))
  admitted <- persistAndAdmitUnboundProductCompletion root row problem projection
  accepts <-
    evaluate $
      case Report.productScenarioCompletion projection admitted of
        Right _completion -> True
        Left _errors -> False
  pure
    AdmittedRow
      { admittedRowId = identity
      , admittedExperiment = ProductMatrix.productProjectionExperimentHash projection
      , admittedPlanId = ProductMatrix.productProjectionPlanId projection
      , admittedCheckpoint = admitted
      , admittedOwnRowAccepts = accepts
      }

-- | Whether the fixture's admissions are themselves sound: each row's own
-- completion accepts its own admitted checkpoint, so a foreign admission is
-- rejected for being foreign and not because the admission was broken.
perRowFixtureBaselineFailures :: PerRowFixture -> [Text]
perRowFixtureBaselineFailures fixture =
  [ "the admitted checkpoint of " <> admittedRowId admission <> " is rejected by its own row"
  | admission <- fixtureAdmissions fixture
  , not (admittedOwnRowAccepts admission)
  ]
    <> [ "the per-row fixture admits fewer than two rows"
       | length (fixtureAdmissions fixture) < 2
       ]

-- | Every per-row control, in registry order.  The foreign-admission controls
-- read the shared Store-admitted fixture through the given action, which the
-- standing stanza backs with one 'buildPerRowFixture' for all of them.
perRowControls :: IO PerRowFixture -> [NegativeControl]
perRowControls provider =
  [ perRowControl provider row context registration spec
  | (row, context) <- rowContexts
  , let registration = registerRow row
  , spec <- toList (registeredSpecs registration)
  ]

perRowControl
  :: IO PerRowFixture
  -> ProductMatrix.ProductRow 'ProductMatrix.Declared
  -> Either Text RowContext
  -> RowRegistration
  -> RowSpec
  -> NegativeControl
perRowControl provider row context registration spec =
  NegativeControl
    { ncName = perRowControlName identity (specKind spec)
    , ncCategory = PerRow
    , ncDescription = description
    , ncCheck =
        case specKind spec of
          InvalidRequest -> PureCheck (invalidRequestOutcome (specRunKind spec) row)
          WrongPlanEvent -> PureCheck (withFixture context wrongPlanEventOutcome)
          ForeignAdmission ->
            EffectfulCheck (withFixture context . foreignAdmissionOutcome <$> provider)
    }
 where
  identity = registeredRowId registration
  description =
    case specKind spec of
      InvalidRequest ->
        "the row's own request with a zeroed budget quantity must be rejected by the ProductRow projection: "
          <> identity
      WrongPlanEvent ->
        "the row's own plan fed into its kind's live contract must reject an event stamped with another row's plan: "
          <> identity
      ForeignAdmission ->
        "a completed checkpoint the Store admitted for another row must not satisfy this row's completion: "
          <> identity

-- Invalid request -----------------------------------------------------------------------

-- | The row's own request with one quantity of its budget zeroed: the first
-- quantity of the run kind's request that is not the run-total (a run total
-- cannot be zeroed through the row, whose budget is refined).
invalidRequestOutcome
  :: ProductMatrix.ProductRunKind
  -> ProductMatrix.ProductRow 'ProductMatrix.Declared
  -> ControlOutcome
invalidRequestOutcome kind row =
  withFixture baseline $ \() ->
    withFixture (zeroBudget row) $ \zeroed ->
      rejectedWith
        (expectedInvalidRequest kind (ProductMatrix.rowId row))
        ( case ProductMatrix.projectProductRow LinuxCPU zeroed of
            Failure errors -> Left errors
            Success _ -> Right ()
        )
 where
  -- The unmodified row must project, or the rejection below proves nothing.
  baseline =
    case ProductMatrix.projectProductRow LinuxCPU row of
      Success _ -> Right ()
      Failure errors ->
        Left
          ( "the unmodified row does not project: "
              <> renderShown (toList errors)
          )

zeroBudget
  :: ProductMatrix.ProductRow 'ProductMatrix.Declared
  -> Either Text (ProductMatrix.ProductRow 'ProductMatrix.Declared)
zeroBudget row =
  case ProductMatrix.productCapability row of
    ProductMatrix.ExecutableProduct descriptor requirements ->
      Right
        row
          { ProductMatrix.productCapability =
              ProductMatrix.ExecutableProduct (zeroedDescriptor descriptor) requirements
          }
    ProductMatrix.UnsupportedProduct reason ->
      Left ("the row is not executable: " <> reason)

-- | Zero one quantity of the request, chosen per kind.  Total over the four
-- descriptor kinds.
zeroedDescriptor
  :: ProductMatrix.ProductPlanDescriptor kind -> ProductMatrix.ProductPlanDescriptor kind
zeroedDescriptor descriptor =
  case descriptor of
    ProductMatrix.SupervisedProductDescriptor _ evaluation batch rate ->
      ProductMatrix.SupervisedProductDescriptor 0 evaluation batch rate
    ProductMatrix.RlProductDescriptor algorithm environment rollout vectors episode _ ->
      ProductMatrix.RlProductDescriptor algorithm environment rollout vectors episode 0
    ProductMatrix.TuningProductDescriptor spec _ promotions updates ->
      ProductMatrix.TuningProductDescriptor spec 0 promotions updates
    ProductMatrix.AlphaZeroProductDescriptor game games simulations plies updates _ ->
      ProductMatrix.AlphaZeroProductDescriptor game games simulations plies updates 0

-- | The rejection a zeroed request yields, by kind.  Total over the run kinds.
expectedInvalidRequest
  :: ProductMatrix.ProductRunKind
  -> Text
  -> NonEmpty ProductMatrix.ProductProjectionError
expectedInvalidRequest kind identity =
  case kind of
    -- A zero training-example count also zeroes the update count derived from it.
    ProductMatrix.ProductSupervisedRun ->
      workload "training-examples" :| [workload "optimizer-updates"]
    ProductMatrix.ProductRlRun ->
      ProductMatrix.InvalidProductRlSchedule identity "RL evaluation episodes must be positive"
        :| [ProductMatrix.InvalidProductRunPlan identity (NonPositiveQuantity "evaluation-episodes")]
    ProductMatrix.ProductTuningRun -> workload "parallel-trials" :| []
    ProductMatrix.ProductAlphaZeroRun -> workload "arena-games" :| []
 where
  workload label =
    ProductMatrix.InvalidProductWorkloadPlan identity (CommonRunPlanError (NonPositiveQuantity label))

-- Wrong plan event ------------------------------------------------------------------------

-- | The row's own plan identity fed into its kind's live contract: the row's own
-- event must be accepted, and the same event stamped with another row's plan
-- must be rejected with the kind's specific plan-mismatch violation.
wrongPlanEventOutcome :: RowContext -> ControlOutcome
wrongPlanEventOutcome context =
  case contextProjection context of
    ProductMatrix.SomeProductProjection witness projection ->
      case witness of
        SupervisedTrainingWitness -> supervisedWrongPlan projection foreignPlanId
        ReinforcementLearningWitness -> rlWrongPlan projection foreignPlanId
        HyperparameterTuningWitness -> tuningWrongPlan projection foreignPlanId
        AlphaZeroSelfPlayWitness -> alphaZeroWrongPlan projection foreignPlanId
 where
  foreignPlanId = contextForeignPlan context

supervisedWrongPlan
  :: ProductMatrix.ProductProjection 'SupervisedTraining -> PlanId -> ControlOutcome
supervisedWrongPlan projection foreignPlanId =
  withFixture fixture $ \(ingest, ownEvent, foreignEvent) ->
    case ingest ownEvent of
      Left violation ->
        fixtureFailed ("the row's own completed checkpoint was rejected: " <> renderShown violation)
      Right _progress ->
        rejectedWith
          (LiveEvidence.LiveEvidencePlanMismatch planId foreignPlanId)
          (void (ingest foreignEvent))
 where
  planId = ProductMatrix.productProjectionPlanId projection
  experiment = ProductMatrix.productProjectionExperimentHash projection
  epochs =
    TrainingBudget.trainingBudgetTargetUnits (ProductMatrix.productProjectionTrainingBudget projection)
  fixture = do
    epochCount <- word32 "epochs" epochs
    contract <-
      first
        (\violation -> "the supervised contract could not be built: " <> renderShown violation)
        (LiveEvidence.supervisedLiveContract planId epochCount)
    ownEvent <-
      supervisedCompletedCheckpointFor planId TrainingBudget.SupervisedEpochBudget epochs experiment
    foreignEvent <-
      supervisedCompletedCheckpointFor
        foreignPlanId
        TrainingBudget.SupervisedEpochBudget
        epochs
        experiment
    pure
      ( LiveEvidence.ingestSupervisedLiveEvent planId experiment contract (initialProgress contract)
      , ownEvent
      , foreignEvent
      )

rlWrongPlan :: ProductMatrix.ProductProjection 'ReinforcementLearning -> PlanId -> ControlOutcome
rlWrongPlan projection foreignPlanId =
  withFixture fixture $ \ingest ->
    case ingest (evaluation planId) of
      Left violation ->
        fixtureFailed ("the row's own evaluation outcome was rejected: " <> renderShown violation)
      Right _progress ->
        rejectedWith
          (LiveEvidence.LiveEvidenceRlPlanMismatch (planIdText planId) (planIdText foreignPlanId))
          (void (ingest (evaluation foreignPlanId)))
 where
  planId = ProductMatrix.productProjectionPlanId projection
  experiment = ProductMatrix.productProjectionExperimentHash projection
  evaluation stamped = rlEvaluationEvent (planIdText stamped) experiment 0 1.0 4
  episodes =
    case ProductMatrix.productProjectionDescriptor projection of
      ProductMatrix.RlProductDescriptor _ _ _ _ _ evaluationEpisodes -> evaluationEpisodes
  fixture = do
    episodeCount <- word32 "evaluation episodes" episodes
    contract <-
      first
        (\violation -> "the RL contract could not be built: " <> renderShown violation)
        (LiveEvidence.rlLiveContract planId episodeCount)
    pure (LiveEvidence.ingestRlLiveEvent planId experiment contract (initialProgress contract))

tuningWrongPlan :: ProductMatrix.ProductProjection 'HyperparameterTuning -> PlanId -> ControlOutcome
tuningWrongPlan projection foreignPlanId =
  case ProductMatrix.productProjectionResolvedPlan projection of
    ProductMatrix.ResolvedTuningProductPlan plan ->
      let ingest = ingestTuneEvent plan (initialProgress (tuningCompletionContract plan))
          ownEvent = tuneTrialFinishedEvent plan 0 1.0
          foreignEvent =
            case ownEvent of
              Tune.TuneTrialFinished finished ->
                Tune.TuneTrialFinished finished {Tune.tfTunePlanId = planIdText foreignPlanId}
              Tune.TuneTrialStarted _ -> ownEvent
              Tune.TuneSweepFinished _ -> ownEvent
              Tune.TuneSweepCompleted _ -> ownEvent
       in case ingest ownEvent of
            Left violation ->
              fixtureFailed ("the row's own trial result was rejected: " <> renderShown violation)
            Right _progress ->
              rejectedWith
                ( WorkloadEventPlanMismatch
                    "tuning-trial-finished"
                    (planIdText (tuningPlanId plan))
                    (planIdText foreignPlanId)
                )
                (void (ingest foreignEvent))

alphaZeroWrongPlan :: ProductMatrix.ProductProjection 'AlphaZeroSelfPlay -> PlanId -> ControlOutcome
alphaZeroWrongPlan projection foreignPlanId =
  case ProductMatrix.productProjectionResolvedPlan projection of
    ProductMatrix.ResolvedAlphaZeroProductPlan plan ->
      withFixture (word32 "self-play games" (quantityValue (alphaZeroPlanSelfPlayGames plan))) $ \games ->
        let ingest = ingestAlphaZeroEvent plan (initialProgress (alphaZeroCompletionContract plan))
            ownEvent = alphaZeroGenerationEvent plan 0 games 1000
            foreignEvent =
              case ownEvent of
                Rl.RlGenerationCompleted generation ->
                  Rl.RlGenerationCompleted generation {Rl.gcPlanId = planIdText foreignPlanId}
                other -> other
         in case ingest ownEvent of
              Left violation ->
                fixtureFailed ("the row's own generation was rejected: " <> renderShown violation)
              Right _progress ->
                rejectedWith
                  ( WorkloadEventPlanMismatch
                      "alphazero-generation-completed"
                      (planIdText (alphaZeroPlanId plan))
                      (planIdText foreignPlanId)
                  )
                  (void (ingest foreignEvent))

word32 :: Text -> Word64 -> Either Text Word32
word32 label value
  | value > fromIntegral (maxBound :: Word32) =
      Left (label <> " exceed the live contract's range: " <> renderShown value)
  | otherwise = Right (fromIntegral value)

-- Foreign admission -------------------------------------------------------------------------

-- | A checkpoint the Store admitted for another row must not satisfy this row's
-- completion, and the rejection must name the four identity mismatches: the
-- experiment, the plan, the canonical row the manifest belongs to, and the
-- manifest's plan.  Other rejections (the budget kind, for example) may
-- accompany them, but the identity mismatches are what a foreign admission is.
foreignAdmissionOutcome :: PerRowFixture -> RowContext -> ControlOutcome
foreignAdmissionOutcome fixture context =
  case find ((/= identity) . admittedRowId) (fixtureAdmissions fixture) of
    Nothing -> fixtureFailed "the per-row fixture holds no admission of another row"
    Just other ->
      case contextProjection context of
        ProductMatrix.SomeProductProjection _witness projection ->
          let expected = expectedIdentityMismatches projection other
           in rejectedWhere
                ("the four identity mismatches with the admission of " <> admittedRowId other)
                (\errors -> identityMismatches errors == expected)
                (Report.productScenarioCompletion projection (admittedCheckpoint other))
 where
  identity = ProductMatrix.rowId (contextRow context)

expectedIdentityMismatches
  :: ProductMatrix.ProductProjection kind
  -> AdmittedRow
  -> [Report.ProductScenarioCompletionError]
expectedIdentityMismatches projection other =
  [ Report.ProductCompletionExperimentMismatch
      identity
      (ProductMatrix.productProjectionExperimentHash projection)
      (admittedExperiment other)
  , Report.ProductCompletionPlanMismatch
      identity
      (ProductMatrix.productProjectionPlanId projection)
      (admittedPlanId other)
  , Report.ProductCompletionCanonicalRowMismatch
      identity
      (admittedRowId other)
      (admittedExperiment other)
  , Report.ProductCompletionManifestPlanMismatch
      identity
      (ProductMatrix.productProjectionPlanId projection)
      (Just (admittedPlanId other))
  ]
 where
  identity = ProductMatrix.productProjectionRowId projection

-- | The identity mismatches among a completion's rejections, in reported order.
identityMismatches
  :: NonEmpty Report.ProductScenarioCompletionError -> [Report.ProductScenarioCompletionError]
identityMismatches errors = filter isIdentityMismatch (toList errors)
 where
  isIdentityMismatch failure =
    case failure of
      Report.ProductCompletionExperimentMismatch {} -> True
      Report.ProductCompletionPlanMismatch {} -> True
      Report.ProductCompletionCanonicalRowMismatch {} -> True
      Report.ProductCompletionManifestPlanMismatch {} -> True
      _ -> False

-- The unit-tree twin --------------------------------------------------------------------------

-- | The registration guards, for the unit stanza, over the committed control
-- list the standing stanza runs ('JitML.Test.NegativeControls.allNegativeControls'):
-- the standing negative-control stanza runs the same guard beside the controls it
-- guards, and this twin keeps the always-on unit gate failing when a product row
-- is added to the registry without its negative controls, or when a per-row
-- control disappears from the list the stanza runs.
perRowRegistrationTests :: [NegativeControl] -> TestTree
perRowRegistrationTests committed =
  testGroup
    "per-row negative-control registration (Phase 282)"
    [ testCase "every product row registers its negative controls, and nothing else does" $
        assertEqual "row registration failures" [] (rowRegistrationFailures committed)
    , testCase "every registry row is a sound baseline for its controls" $
        assertEqual "row baseline failures" [] rowBaselineFailures
    , testCase "each registered row commits one control per spec kind" $
        assertEqual
          "committed control count"
          (length ProductMatrix.allProductRows * length [minBound .. maxBound :: RowSpecKind])
          (length (factControlNames facts))
    , testCase "the guard is not vacuous: a row without a registration is reported" $
        assertEqual
          "failures for a registry with its first registration dropped"
          [ "product row has no registered negative control: " <> identity
          | identity <- take 1 (fmap fst (factRegistry facts))
          ]
          ( rowRegistrationFailuresFor
              facts
                { factRegistrations = withoutFirst allRowRegistrations
                , factControlNames =
                    drop
                      (length (specsForRunKind ProductMatrix.ProductSupervisedRun))
                      (factControlNames facts)
                }
          )
    , testCase "the guard reads the committed list: per-row controls dropped from it are reported" $
        assertEqual
          "failures for a committed list without its foreign-admission controls"
          ( sort
              [ "registered spec has no control: " <> perRowControlName identity ForeignAdmission
              | identity <- fmap fst (factRegistry facts)
              ]
          )
          (rowRegistrationFailures (filter (not . isForeignAdmission) committed))
    , testCase
        "the guard reads the committed list: a per-row control filed under another category is reported"
        $ assertEqual
          "failures for a committed list whose first per-row control is a request control"
          [ "registered spec has no control: " <> name
          | name <- take 1 (factControlNames facts)
          ]
          (rowRegistrationFailures (recategoriseFirst committed))
    ]
 where
  facts = realRowRegistryFacts committed
  isForeignAdmission control =
    ncCategory control == PerRow
      && ("-" <> renderRowSpecKind ForeignAdmission) `Text.isSuffixOf` ncName control
  recategoriseFirst controls =
    case break ((== PerRow) . ncCategory) controls of
      (before, control : after) -> before <> [control {ncCategory = Request}] <> after
      (before, []) -> before
