{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StandaloneDeriving #-}

module JitML.Product.Matrix
  ( DeviceClaim (..)
  , MatrixFloor (..)
  , ModelState (..)
  , NonProductRow (..)
  , ProductCapability (..)
  , ProductEvidenceRequirements (..)
  , ProductMatrixError (..)
  , ProductPlanDescriptor (..)
  , ProductProjection
  , ProductProjectionBatch
  , ProductProjectionError (..)
  , ProductResolvedPlan (..)
  , ProductRow (..)
  , ProductRunKind (..)
  , RowClass (..)
  , RowFamily (..)
  , SomeProductProjection (..)
  , allProductRows
  , matrixFloor
  , matrixFloorRowCount
  , nonProductRows
  , productProjectionCommand
  , productProjectionArchitectureFeatures
  , productProjectionDescriptor
  , productProjectionConvergenceBar
  , productProjectionDemoPanel
  , productProjectionDeviceClaim
  , productProjectionE2ETest
  , productProjectionEvidenceRequirements
  , productProjectionExperimentConfig
  , productProjectionExperimentHash
  , productProjectionFamily
  , productProjectionIntegrationTest
  , productProjectionImplementation
  , productProjectionPlanId
  , productProjectionResolvedPlan
  , productProjectionRowClass
  , productProjectionRowId
  , productProjectionRunKind
  , productProjectionRunPlan
  , productProjectionSubstrate
  , productProjectionTrainingBudget
  , productProjectionBatchProjections
  , productProjectionBatchRowIds
  , productProjectionBatchSubstrate
  , productRowCount
  , productRowDeviceEvidenceForSubstrate
  , deviceEvidenceForClaim
  , productExperimentConfigPath
  , productRowExperimentHash
  , productRowForExperimentHash
  , productRowIds
  , productResolvedPlanId
  , productResolvedRunPlan
  , projectProductRow
  , projectProductRows
  , renderProductMatrixError
  , renderRowClass
  , renderRowFamily
  , selectProductRows
  , validateProductMatrix
  , validateProductMatrixTyped
  )
where

import Data.Char (ord)
import Data.List qualified as List
import Data.List.NonEmpty (NonEmpty (..))
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import Numeric (showHex)

import JitML.Plan.Plan
  ( PlanError
  , PlanId
  , RawRunBudget (..)
  , RawRunRequest (..)
  , RunKind
  , RunKindWitness (..)
  , RunPlacement (..)
  , RunPlan
  , Validation (..)
  , resolveRun
  , runPlanId
  )
import JitML.Plan.Plan qualified as Plan
import JitML.Plan.Workload
  ( AlphaZeroPlan
  , RawAlphaZeroPlan (..)
  , RawSupervisedPlan (..)
  , RawTuningPlan (..)
  , SupervisedPlan
  , TuningPlan
  , WorkloadPlanError
  , alphaZeroPlanId
  , alphaZeroPlanRunPlan
  , resolveAlphaZeroPlan
  , resolveSupervisedPlan
  , resolveTuningPlanWithExecutionSpec
  , supervisedPlanId
  , supervisedPlanRunPlan
  , tuningPlanId
  , tuningPlanRunPlan
  )
import JitML.Product.Convergence
  ( ConvergenceBar
  , ConvergenceBarError
  , ValidatedConvergenceBar
  , barFromObservation
  , classificationAccuracyBar
  , mkConvergenceBar
  , regressionRmseBar
  , validateConvergenceBar
  , validatedConvergenceBar
  )
import JitML.RL.AlphaZero qualified as AlphaZero
import JitML.RL.ConvergenceThresholds qualified as RLConvergence
import JitML.RL.ProductBudget qualified as ProductBudget
import JitML.SL.Architecture (ArchitectureFeature)
import JitML.SL.Architecture qualified as SLArchitecture
import JitML.SL.Canonicals qualified as SL
import JitML.SL.ConvergenceThresholds qualified as SLConvergence
import JitML.Substrate (Substrate (..), allSubstrates, renderSubstrate)
import JitML.Training.Budget
  ( BudgetKind (..)
  , MetricGoal (..)
  , TrainingBudget
  , mkTrainingBudget
  , trainingBudgetKind
  , trainingBudgetSeed
  , trainingBudgetTargetUnits
  )
import JitML.Tune.Catalog qualified as Tune

data ModelState
  = Declared
  | TrainingStarted
  | TrainingCompleted
  | InferenceEligible
  deriving stock (Eq, Show)

data RowFamily
  = Supervised
  | ReinforcementLearning
  | AlphaZero
  | Tuning
  deriving stock (Eq, Show)

data RowClass
  = SupervisedClassification Text Text
  | SupervisedRegression Text Text
  | RlAlgorithmEnvironment Text Text
  | RlGoalConditioned Text
  | AlphaZeroGame Text
  | HyperparameterTuning Text
  deriving stock (Eq, Show)

data DeviceClaim
  = SubstrateBackedANN
  | SubstrateBackedPolicy
  | GoalConditionedPolicy
  | SelfPlayPolicyValueNetwork
  | TuningPromotedTraining
  deriving stock (Eq, Show)

-- | Runtime run-kind tag used by unindexed registry/report consumers.  The
-- corresponding descriptor and resolved plan remain indexed by 'RunKind'.
data ProductRunKind
  = ProductSupervisedRun
  | ProductRlRun
  | ProductTuningRun
  | ProductAlphaZeroRun
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | Raw, kind-indexed execution semantics carried by every executable product
-- row.  These values are deliberately constructible: ProductRow itself stays a
-- raw configuration boundary until Sprint 21.4.  'projectProductRow' is the
-- sole refinement boundary into an opaque validated projection.
data ProductPlanDescriptor (kind :: RunKind) where
  SupervisedProductDescriptor
    :: { supervisedTrainingExamples :: !Word64
       , supervisedEvaluationExamples :: !Word64
       , supervisedBatchExamples :: !Word64
       , supervisedLearningRate :: !Double
       }
    -> ProductPlanDescriptor 'Plan.SupervisedTraining
  RlProductDescriptor
    :: { rlDescriptorAlgorithm :: !Text
       , rlDescriptorEnvironment :: !Text
       , rlDescriptorRolloutTicksPerEnv :: !Word64
       , rlDescriptorVectorEnvironments :: !Word64
       , rlDescriptorEpisodeSteps :: !Word64
       , rlDescriptorEvaluationEpisodes :: !Word64
       }
    -> ProductPlanDescriptor 'Plan.ReinforcementLearning
  TuningProductDescriptor
    :: { tuningDescriptorExecutionSpec :: !Tune.TuningExecutionSpec
       , tuningDescriptorParallelTrials :: !Word64
       , tuningDescriptorPromotions :: !Word64
       , tuningDescriptorPerTrialUpdates :: !Word64
       }
    -> ProductPlanDescriptor 'Plan.HyperparameterTuning
  AlphaZeroProductDescriptor
    :: { alphaZeroDescriptorGame :: !Text
       , alphaZeroDescriptorSelfPlayGames :: !Word64
       , alphaZeroDescriptorMctsSimulations :: !Word64
       , alphaZeroDescriptorMaxPlies :: !Word64
       , alphaZeroDescriptorOptimizerUpdates :: !Word64
       , alphaZeroDescriptorArenaGames :: !Word64
       }
    -> ProductPlanDescriptor 'Plan.AlphaZeroSelfPlay

deriving instance Eq (ProductPlanDescriptor kind)
deriving instance Show (ProductPlanDescriptor kind)

-- | Closed evidence-contract witness paired with a descriptor of the same
-- kind.  The exact reducers live in the existing workload contract modules;
-- this witness prevents an executable row from omitting which reducer family
-- must eventually mint completion.
data ProductEvidenceRequirements (kind :: RunKind) where
  SupervisedProductEvidence
    :: ProductEvidenceRequirements 'Plan.SupervisedTraining
  RlProductEvidence
    :: ProductEvidenceRequirements 'Plan.ReinforcementLearning
  TuningProductEvidence
    :: ProductEvidenceRequirements 'Plan.HyperparameterTuning
  AlphaZeroProductEvidence
    :: ProductEvidenceRequirements 'Plan.AlphaZeroSelfPlay

deriving instance Eq (ProductEvidenceRequirements kind)
deriving instance Show (ProductEvidenceRequirements kind)

-- | Registry capability is a closed sum.  Unsupported declarations carry only
-- their reason; executable declarations must carry a same-kind plan descriptor
-- and evidence contract.  Measured completion is intentionally absent and is
-- supplied only by the live interpreter/report adapter.
data ProductCapability where
  ExecutableProduct
    :: ProductPlanDescriptor kind
    -> ProductEvidenceRequirements kind
    -> ProductCapability
  UnsupportedProduct :: !Text -> ProductCapability

instance Eq ProductCapability where
  UnsupportedProduct left == UnsupportedProduct right = left == right
  ExecutableProduct leftDescriptor leftEvidence
    == ExecutableProduct rightDescriptor rightEvidence =
      descriptorAndEvidenceEqual
        leftDescriptor
        leftEvidence
        rightDescriptor
        rightEvidence
  _ == _ = False

instance Show ProductCapability where
  show (UnsupportedProduct reason) = "UnsupportedProduct " <> show reason
  show (ExecutableProduct descriptor requirements) =
    "ExecutableProduct "
      <> showProductDescriptor descriptor
      <> " "
      <> showProductEvidenceRequirements requirements

descriptorAndEvidenceEqual
  :: ProductPlanDescriptor leftKind
  -> ProductEvidenceRequirements leftKind
  -> ProductPlanDescriptor rightKind
  -> ProductEvidenceRequirements rightKind
  -> Bool
descriptorAndEvidenceEqual leftDescriptor leftEvidence rightDescriptor rightEvidence =
  case (leftDescriptor, rightDescriptor, leftEvidence, rightEvidence) of
    ( SupervisedProductDescriptor {}
      , SupervisedProductDescriptor {}
      , SupervisedProductEvidence
      , SupervisedProductEvidence
      ) ->
        supervisedTrainingExamples leftDescriptor == supervisedTrainingExamples rightDescriptor
          && supervisedEvaluationExamples leftDescriptor == supervisedEvaluationExamples rightDescriptor
          && supervisedBatchExamples leftDescriptor == supervisedBatchExamples rightDescriptor
          && supervisedLearningRate leftDescriptor == supervisedLearningRate rightDescriptor
    (RlProductDescriptor {}, RlProductDescriptor {}, RlProductEvidence, RlProductEvidence) ->
      rlDescriptorAlgorithm leftDescriptor == rlDescriptorAlgorithm rightDescriptor
        && rlDescriptorEnvironment leftDescriptor == rlDescriptorEnvironment rightDescriptor
        && rlDescriptorRolloutTicksPerEnv leftDescriptor == rlDescriptorRolloutTicksPerEnv rightDescriptor
        && rlDescriptorVectorEnvironments leftDescriptor == rlDescriptorVectorEnvironments rightDescriptor
        && rlDescriptorEpisodeSteps leftDescriptor == rlDescriptorEpisodeSteps rightDescriptor
        && rlDescriptorEvaluationEpisodes leftDescriptor == rlDescriptorEvaluationEpisodes rightDescriptor
    ( TuningProductDescriptor {}
      , TuningProductDescriptor {}
      , TuningProductEvidence
      , TuningProductEvidence
      ) ->
        tuningDescriptorExecutionSpec leftDescriptor == tuningDescriptorExecutionSpec rightDescriptor
          && tuningDescriptorParallelTrials leftDescriptor == tuningDescriptorParallelTrials rightDescriptor
          && tuningDescriptorPromotions leftDescriptor == tuningDescriptorPromotions rightDescriptor
          && tuningDescriptorPerTrialUpdates leftDescriptor == tuningDescriptorPerTrialUpdates rightDescriptor
    ( AlphaZeroProductDescriptor {}
      , AlphaZeroProductDescriptor {}
      , AlphaZeroProductEvidence
      , AlphaZeroProductEvidence
      ) ->
        alphaZeroDescriptorGame leftDescriptor == alphaZeroDescriptorGame rightDescriptor
          && alphaZeroDescriptorSelfPlayGames leftDescriptor == alphaZeroDescriptorSelfPlayGames rightDescriptor
          && alphaZeroDescriptorMctsSimulations leftDescriptor
            == alphaZeroDescriptorMctsSimulations rightDescriptor
          && alphaZeroDescriptorMaxPlies leftDescriptor == alphaZeroDescriptorMaxPlies rightDescriptor
          && alphaZeroDescriptorOptimizerUpdates leftDescriptor
            == alphaZeroDescriptorOptimizerUpdates rightDescriptor
          && alphaZeroDescriptorArenaGames leftDescriptor == alphaZeroDescriptorArenaGames rightDescriptor
    _ -> False

showProductDescriptor :: ProductPlanDescriptor kind -> String
showProductDescriptor descriptor =
  case descriptor of
    SupervisedProductDescriptor {} -> show descriptor
    RlProductDescriptor {} -> show descriptor
    TuningProductDescriptor {} -> show descriptor
    AlphaZeroProductDescriptor {} -> show descriptor

showProductEvidenceRequirements :: ProductEvidenceRequirements kind -> String
showProductEvidenceRequirements requirements =
  case requirements of
    SupervisedProductEvidence -> show requirements
    RlProductEvidence -> show requirements
    TuningProductEvidence -> show requirements
    AlphaZeroProductEvidence -> show requirements

data ProductRow (state :: ModelState) = ProductRow
  { rowId :: Text
  , family :: RowFamily
  , rowClass :: RowClass
  , implementation :: Text
  , rowArchitectureFeatures :: [ArchitectureFeature]
  , experimentConfig :: Text
  , trainingBudget :: TrainingBudget
  , convergenceBar :: ConvergenceBar
  , deviceClaim :: DeviceClaim
  , productCapability :: ProductCapability
  , integrationTest :: Text
  , e2eTest :: Text
  , demoPanel :: Text
  }
  deriving stock (Eq, Show)

-- | Workload-specific resolved plans preserve the semantic identity that exact
-- completion contracts use.  In particular, tuning axes and the AlphaZero game
-- participate in their outer PlanIds rather than being discarded in favour of
-- the underlying common RunPlan identity.
data ProductResolvedPlan (kind :: RunKind) where
  ResolvedSupervisedProductPlan
    :: SupervisedPlan
    -> ProductResolvedPlan 'Plan.SupervisedTraining
  ResolvedRlProductPlan
    :: RunPlan 'Plan.ReinforcementLearning
    -> ProductResolvedPlan 'Plan.ReinforcementLearning
  ResolvedTuningProductPlan
    :: TuningPlan
    -> ProductResolvedPlan 'Plan.HyperparameterTuning
  ResolvedAlphaZeroProductPlan
    :: AlphaZeroPlan
    -> ProductResolvedPlan 'Plan.AlphaZeroSelfPlay

deriving instance Eq (ProductResolvedPlan kind)
deriving instance Show (ProductResolvedPlan kind)

productResolvedRunPlan :: ProductResolvedPlan kind -> RunPlan kind
productResolvedRunPlan resolved =
  case resolved of
    ResolvedSupervisedProductPlan plan -> supervisedPlanRunPlan plan
    ResolvedRlProductPlan plan -> plan
    ResolvedTuningProductPlan plan -> tuningPlanRunPlan plan
    ResolvedAlphaZeroProductPlan plan -> alphaZeroPlanRunPlan plan

productResolvedPlanId :: ProductResolvedPlan kind -> PlanId
productResolvedPlanId resolved =
  case resolved of
    ResolvedSupervisedProductPlan plan -> supervisedPlanId plan
    ResolvedRlProductPlan plan -> runPlanId plan
    ResolvedTuningProductPlan plan -> tuningPlanId plan
    ResolvedAlphaZeroProductPlan plan -> alphaZeroPlanId plan

-- | Opaque, validated row projection.  Callers can inspect or execute its
-- resolved plan but can obtain the row/plan association only through
-- 'projectProductRow'.
data ProductProjection (kind :: RunKind) = ProductProjection
  { projectionRowIdValue :: !Text
  , projectionFamilyValue :: !RowFamily
  , projectionRowClassValue :: !RowClass
  , projectionImplementationValue :: !Text
  , projectionArchitectureFeaturesValue :: ![ArchitectureFeature]
  , projectionExperimentHashValue :: !Text
  , projectionExperimentConfigValue :: !Text
  , projectionTrainingBudgetValue :: !TrainingBudget
  , projectionConvergenceBarValue :: !ConvergenceBar
  , projectionDeviceClaimValue :: !DeviceClaim
  , projectionIntegrationTestValue :: !Text
  , projectionE2ETestValue :: !Text
  , projectionDemoPanelValue :: !Text
  , projectionSubstrateValue :: !Substrate
  , projectionRunKindValue :: !ProductRunKind
  , projectionCommandValue :: ![Text]
  , projectionDescriptorValue :: !(ProductPlanDescriptor kind)
  , projectionEvidenceRequirementsValue :: !(ProductEvidenceRequirements kind)
  , projectionResolvedPlanValue :: !(ProductResolvedPlan kind)
  }
  deriving stock (Eq, Show)

-- These are deliberately ordinary functions rather than exported record
-- selectors.  An exported selector permits record update even when the
-- constructor is hidden, which would make the validated projection forgeable.
productProjectionRowId :: ProductProjection kind -> Text
productProjectionRowId = projectionRowIdValue

productProjectionFamily :: ProductProjection kind -> RowFamily
productProjectionFamily = projectionFamilyValue

productProjectionRowClass :: ProductProjection kind -> RowClass
productProjectionRowClass = projectionRowClassValue

productProjectionImplementation :: ProductProjection kind -> Text
productProjectionImplementation = projectionImplementationValue

productProjectionArchitectureFeatures :: ProductProjection kind -> [ArchitectureFeature]
productProjectionArchitectureFeatures = projectionArchitectureFeaturesValue

productProjectionExperimentHash :: ProductProjection kind -> Text
productProjectionExperimentHash = projectionExperimentHashValue

productProjectionExperimentConfig :: ProductProjection kind -> Text
productProjectionExperimentConfig = projectionExperimentConfigValue

productProjectionTrainingBudget :: ProductProjection kind -> TrainingBudget
productProjectionTrainingBudget = projectionTrainingBudgetValue

productProjectionConvergenceBar :: ProductProjection kind -> ConvergenceBar
productProjectionConvergenceBar = projectionConvergenceBarValue

productProjectionDeviceClaim :: ProductProjection kind -> DeviceClaim
productProjectionDeviceClaim = projectionDeviceClaimValue

productProjectionIntegrationTest :: ProductProjection kind -> Text
productProjectionIntegrationTest = projectionIntegrationTestValue

productProjectionE2ETest :: ProductProjection kind -> Text
productProjectionE2ETest = projectionE2ETestValue

productProjectionDemoPanel :: ProductProjection kind -> Text
productProjectionDemoPanel = projectionDemoPanelValue

productProjectionSubstrate :: ProductProjection kind -> Substrate
productProjectionSubstrate = projectionSubstrateValue

productProjectionRunKind :: ProductProjection kind -> ProductRunKind
productProjectionRunKind = projectionRunKindValue

productProjectionCommand :: ProductProjection kind -> [Text]
productProjectionCommand = projectionCommandValue

productProjectionDescriptor :: ProductProjection kind -> ProductPlanDescriptor kind
productProjectionDescriptor = projectionDescriptorValue

productProjectionEvidenceRequirements
  :: ProductProjection kind
  -> ProductEvidenceRequirements kind
productProjectionEvidenceRequirements = projectionEvidenceRequirementsValue

productProjectionResolvedPlan :: ProductProjection kind -> ProductResolvedPlan kind
productProjectionResolvedPlan = projectionResolvedPlanValue

productProjectionRunPlan :: ProductProjection kind -> RunPlan kind
productProjectionRunPlan = productResolvedRunPlan . productProjectionResolvedPlan

productProjectionPlanId :: ProductProjection kind -> PlanId
productProjectionPlanId = productResolvedPlanId . productProjectionResolvedPlan

-- | Existential wrapper used by the heterogeneous canonical registry.  The
-- witness refines the hidden projection kind for workload-specific consumers.
data SomeProductProjection where
  SomeProductProjection
    :: RunKindWitness kind
    -> ProductProjection kind
    -> SomeProductProjection

instance Eq SomeProductProjection where
  SomeProductProjection SupervisedTrainingWitness left
    == SomeProductProjection SupervisedTrainingWitness right = left == right
  SomeProductProjection ReinforcementLearningWitness left
    == SomeProductProjection ReinforcementLearningWitness right = left == right
  SomeProductProjection HyperparameterTuningWitness left
    == SomeProductProjection HyperparameterTuningWitness right = left == right
  SomeProductProjection AlphaZeroSelfPlayWitness left
    == SomeProductProjection AlphaZeroSelfPlayWitness right = left == right
  _ == _ = False

instance Show SomeProductProjection where
  show (SomeProductProjection witness projection) =
    case witness of
      SupervisedTrainingWitness -> show projection
      ReinforcementLearningWitness -> show projection
      HyperparameterTuningWitness -> show projection
      AlphaZeroSelfPlayWitness -> show projection

-- | A substrate-specific, order-preserving registry projection.  Its
-- constructor is hidden so duplicate row identities and unprojectable rows
-- cannot be represented as an executable batch.
data ProductProjectionBatch = ProductProjectionBatch
  { projectionBatchSubstrateValue :: !Substrate
  , projectionBatchRowIdsValue :: ![Text]
  , projectionBatchProjectionsValue :: ![SomeProductProjection]
  }
  deriving stock (Eq, Show)

productProjectionBatchSubstrate :: ProductProjectionBatch -> Substrate
productProjectionBatchSubstrate = projectionBatchSubstrateValue

productProjectionBatchRowIds :: ProductProjectionBatch -> [Text]
productProjectionBatchRowIds = projectionBatchRowIdsValue

productProjectionBatchProjections :: ProductProjectionBatch -> [SomeProductProjection]
productProjectionBatchProjections = projectionBatchProjectionsValue

data ProductProjectionError
  = UnsupportedProductRow !Text !Text
  | EmptyProductRowField !Text !Text
  | ProductFamilyRunKindMismatch !Text !RowFamily !ProductRunKind
  | ProductRowClassRunKindMismatch !Text !RowClass !ProductRunKind
  | ProductDescriptorRowClassMismatch !Text !Text
  | ProductDeviceClaimMismatch !Text !DeviceClaim !DeviceClaim
  | ProductBudgetKindMismatch !Text !BudgetKind !BudgetKind
  | MissingProductSeed !Text
  | InvalidProductSeed !Text !Word64
  | InsufficientProductSeedHeadroom !Text !Text !Word64 !Integer
  | InvalidProductExecutorQuantity !Text !Text !Word64
  | InvalidProductSupervisedLearningRate !Text !Double
  | ProductImplementationMismatch !Text !Text !Text
  | ProductArchitectureFeaturesMismatch !Text ![ArchitectureFeature] ![ArchitectureFeature]
  | ProductArchitectureResolutionFailure !Text !Text
  | InvalidProductConvergenceBar !Text !ConvergenceBarError
  | InvalidProductRunPlan !Text !PlanError
  | InvalidProductWorkloadPlan !Text !WorkloadPlanError
  | InvalidProductRlSchedule !Text !Text
  deriving stock (Eq, Show)

data ProductMatrixError
  = EmptyProductProjectionBatch
  | DuplicateProductRowId !Text
  | DuplicateProductExperimentHash !Text
  | DuplicateProductIntegrationTest !Text
  | DuplicateProductE2ETest !Text
  | NonProductRowInProductMatrix !Text
  | MissingMatrixFloorMember !Text !Text
  | UnexpectedMatrixFloorMember !Text !Text
  | UnprojectableProductRow !ProductProjectionError
  deriving stock (Eq, Show)

data NonProductRow = NonProductRow
  { nonProductRowId :: Text
  , nonProductRowClass :: RowClass
  , nonProductRowReason :: Text
  }
  deriving stock (Eq, Show)

data MatrixFloor = MatrixFloor
  { floorSupervisedRows :: [Text]
  , floorRlEnvironments :: [Text]
  , floorRlAlgorithms :: [Text]
  , floorAlphaZeroGames :: [Text]
  , floorTuningRows :: [Text]
  }
  deriving stock (Eq, Show)

matrixFloor :: MatrixFloor
matrixFloor =
  MatrixFloor
    { floorSupervisedRows =
        [ "mnist-shallow-mlp"
        , "mnist-deep-mlp"
        , "mnist-lenet"
        , "fashion-mnist-mlp"
        , "fashion-mnist-resnet"
        , "cifar10-resnet20"
        , "cifar10-resnet56"
        , "cifar100-wide-resnet"
        , "cifar10-vit"
        , "tiny-imagenet-resnet50"
        , "california-housing-mlp"
        ]
    , floorRlEnvironments =
        [ "cartpole"
        , "mountain-car"
        , "acrobot"
        , "pendulum"
        , "lunar-lander"
        , "key-door-grid"
        , "gridworld-deterministic"
        ]
    , floorRlAlgorithms =
        [ "PPO"
        , "A2C"
        , "TRPO"
        , "MaskablePPO"
        , "RecurrentPPO"
        , "DQN"
        , "QR-DQN"
        , "DDPG"
        , "TD3"
        , "SAC"
        , "CrossQ"
        , "TQC"
        , "ARS"
        , "HER"
        ]
    , floorAlphaZeroGames = ["connect4", "othello", "hex", "gomoku"]
    , floorTuningRows = ["hyperparameter-tuning"]
    }

allProductRows :: [ProductRow 'Declared]
allProductRows =
  supervisedRows
    <> rlConvergenceRows
    <> [herRow]
    <> alphaZeroRows
    <> [tuningRow]

nonProductRows :: [NonProductRow]
nonProductRows =
  [ NonProductRow
      { nonProductRowId = "tic-tac-toe"
      , nonProductRowClass = AlphaZeroGame "tic-tac-toe"
      , nonProductRowReason =
          "unit-level minimax anchor documented outside the product matrix"
      }
  , NonProductRow
      { nonProductRowId = "atari-subset"
      , nonProductRowClass = RlAlgorithmEnvironment "ALE" "atari-subset"
      , nonProductRowReason =
          "optional ROM-backed runtime support, not a required product row"
      }
  ]

productRowCount :: Int
productRowCount = length allProductRows

matrixFloorRowCount :: Int
matrixFloorRowCount =
  length (floorSupervisedRows matrixFloor)
    + length (floorRlEnvironments matrixFloor)
    + length (floorRlAlgorithms matrixFloor)
    + length (floorAlphaZeroGames matrixFloor)
    + length (floorTuningRows matrixFloor)

productRowIds :: [Text]
productRowIds = fmap rowId allProductRows

-- | Collision-safe deterministic path for the exact external configuration of
-- one canonical ProductRow.  Encoding every Unicode code point avoids both
-- separator ambiguity and case-folding collisions on Apple filesystems.
productExperimentConfigPath :: Text -> Text
productExperimentConfigPath rowIdentity =
  "experiments/product/"
    <> Text.intercalate "-" (fmap encodeCodePoint (Text.unpack rowIdentity))
    <> ".dhall"
 where
  encodeCodePoint character = Text.pack (showHex (ord character) "")

-- | Select ProductRows from the comma-separated internal-command filter.
-- Unknown and duplicate identifiers are rejected before either command starts
-- work; silently accepting the valid subset would make a misspelled matrix
-- gate look complete.
selectProductRows :: Maybe Text -> Either Text [ProductRow 'Declared]
selectProductRows rawFilter =
  case filterFailures of
    []
      | null requestedIds -> Right allProductRows
      | otherwise ->
          Right
            [ row
            | row <- allProductRows
            , rowId row `elem` requestedIds
            ]
    failures ->
      Left
        ( "JITML_PRODUCT_ROW_FILTER is invalid: "
            <> Text.intercalate "; " failures
        )
 where
  requestedIds =
    maybe
      []
      (filter (not . Text.null) . fmap Text.strip . Text.splitOn ",")
      rawFilter
  unknownIds =
    List.nub
      [ requestedId
      | requestedId <- requestedIds
      , requestedId `notElem` productRowIds
      ]
  duplicateIds = duplicates requestedIds
  filterFailures =
    [ "unknown product row ids: " <> Text.intercalate ", " unknownIds
    | not (null unknownIds)
    ]
      <> [ "duplicate product row ids: " <> Text.intercalate ", " duplicateIds
         | not (null duplicateIds)
         ]

productRowExperimentHash :: ProductRow state -> Text
productRowExperimentHash row =
  "product-row-" <> sanitizeTestId (rowId row)

productRowForExperimentHash :: Text -> Maybe (ProductRow 'Declared)
productRowForExperimentHash experimentHash =
  List.find ((== experimentHash) . productRowExperimentHash) allProductRows

productRowDeviceEvidenceForSubstrate :: Substrate -> ProductRow state -> Text
productRowDeviceEvidenceForSubstrate substrate row =
  deviceEvidenceForClaim substrate (deviceClaim row)

-- | The device-evidence cell derived from a lane and a 'DeviceClaim' alone.
--
-- Completed scenario evidence retains the claim and the lane it executed on, not
-- the declared 'ProductRow', so issuing a lane fragment from that evidence needs
-- the claim-level composer. Deriving the cell from a registry row instead would
-- put a declaration lookup back inside an evidence-only render, which is exactly
-- the substitution the fragment contract forbids.
deviceEvidenceForClaim :: Substrate -> DeviceClaim -> Text
deviceEvidenceForClaim substrate claim =
  Text.intercalate
    ":"
    [ "device"
    , renderSubstrate substrate
    , substrateDeviceRuntime substrate
    , deviceClaimKernelSummary claim
    ]

substrateDeviceRuntime :: Substrate -> Text
substrateDeviceRuntime AppleSilicon = "Metal:fixed-bridge:makeLibrary:dispatch"
substrateDeviceRuntime LinuxCPU = "oneDNN:ffi:dispatch"
substrateDeviceRuntime LinuxCUDA = "cuBLAS-cuDNN:ffi:dispatch"

deviceClaimKernelSummary :: DeviceClaim -> Text
deviceClaimKernelSummary SubstrateBackedANN =
  "dense-conv-norm-attention-update-critical"
deviceClaimKernelSummary SubstrateBackedPolicy =
  "policy-mlp-update-critical"
deviceClaimKernelSummary GoalConditionedPolicy =
  "goal-policy-mlp-update-critical"
deviceClaimKernelSummary SelfPlayPolicyValueNetwork =
  "policy-value-mlp-update-critical"
deviceClaimKernelSummary TuningPromotedTraining =
  "tuning-promoted-mlp-update-critical"

supervisedRows :: [ProductRow 'Declared]
supervisedRows = fmap supervisedRow SL.trainableCanonicalCohort

supervisedRow :: SL.CanonicalProblem -> ProductRow 'Declared
supervisedRow problem =
  ( baseRow
      (SL.problemName problem)
      Supervised
      rowClass'
      (canonicalImplementationForRowClass rowClass')
      (productExperimentConfigPath (SL.problemName problem))
      ( staticBudget
          SupervisedEpochBudget
          (supervisedEpochBudget (SL.problemName problem))
          (Just (fromIntegral (SL.problemSeed problem)))
      )
      bar
      SubstrateBackedANN
      (supervisedDemoPanel problem)
  )
    { rowArchitectureFeatures = canonicalSupervisedArchitectureFeatures rowClass' problem
    }
 where
  rowClass'
    | SL.problemName problem == "california-housing-mlp" =
        SupervisedRegression (SL.problemDataset problem) (SL.problemModel problem)
    | otherwise =
        SupervisedClassification (SL.problemDataset problem) (SL.problemModel problem)
  bar =
    case SLConvergence.slCohortThreshold (SL.problemName problem) of
      Just threshold ->
        classificationAccuracyBar "test_accuracy" threshold
      Nothing ->
        regressionRmseBar "rmse" 0.90 0.10

-- | The fixed product budget is the one source of truth for the publisher.
-- CIFAR ResNet-20/56 and ViT use forty epochs, Tiny ImageNet uses fifteen,
-- and the other seven supervised rows use ten.  Producers must consume this
-- value rather than independently clamping or extending it.
supervisedEpochBudget :: Text -> Word64
supervisedEpochBudget problemName =
  case problemName of
    "cifar10-resnet20" -> 40
    "cifar10-resnet56" -> 40
    "cifar10-vit" -> 40
    "tiny-imagenet-resnet50" -> 15
    _ -> 10

rlConvergenceRows :: [ProductRow 'Declared]
rlConvergenceRows =
  fmap rlConvergenceRow RLConvergence.fixedBudgetRlConvergenceRows

rlConvergenceRow :: RLConvergence.FixedBudgetRlConvergenceRow -> ProductRow 'Declared
rlConvergenceRow row =
  baseRow
    rowId'
    ReinforcementLearning
    (RlAlgorithmEnvironment (RLConvergence.fbrAlgorithm row) (RLConvergence.fbrEnvironment row))
    ("JitML.RL.Algorithms.Registry.moduleFor/" <> RLConvergence.fbrAlgorithm row)
    (productExperimentConfigPath rowId')
    (canonicalDeviceProductBudget (RLConvergence.fbrBudget row))
    ( barFromObservation
        (RLConvergence.slack (RLConvergence.fbrThreshold row))
        (RLConvergence.fbrConvergenceMetric row)
    )
    SubstrateBackedPolicy
    "rl-trajectory"
 where
  rowId' = rlRowId (RLConvergence.fbrAlgorithm row) (RLConvergence.fbrEnvironment row)

herRow :: ProductRow 'Declared
herRow =
  let metric = RLConvergence.herGoalMetric
      rowId' = "HER/" <> RLConvergence.hgmEnvironment metric
   in baseRow
        rowId'
        ReinforcementLearning
        (RlGoalConditioned (RLConvergence.hgmEnvironment metric))
        "JitML.RL.Algorithms.HerTrainer.trainHer"
        (productExperimentConfigPath rowId')
        (canonicalDeviceProductBudget (RLConvergence.hgmBudget metric))
        (barFromObservation 0.05 (RLConvergence.hgmSuccessRate metric))
        GoalConditionedPolicy
        "rl-trajectory"

alphaZeroRows :: [ProductRow 'Declared]
alphaZeroRows =
  fmap alphaZeroRow RLConvergence.alphaZeroGameConvergenceRows

alphaZeroRow :: RLConvergence.AlphaZeroGameConvergenceRow -> ProductRow 'Declared
alphaZeroRow row =
  baseRow
    game
    AlphaZero
    (AlphaZeroGame game)
    "JitML.RL.AlphaZero.SelfPlay"
    (productExperimentConfigPath game)
    (canonicalDeviceProductBudget (RLConvergence.azgBudget row))
    (barFromObservation 0.05 (RLConvergence.azgArenaWinRate row))
    SelfPlayPolicyValueNetwork
    "connect4-human-vs-alphazero"
 where
  game = RLConvergence.azgGame row

tuningRow :: ProductRow 'Declared
tuningRow =
  baseRow
    "hyperparameter-tuning"
    Tuning
    (HyperparameterTuning "TPE/ASHA/MedianPruner")
    "JitML.Tune.Catalog"
    "experiments/mnist-tune.dhall"
    (staticBudget TuningTrialBudget 128 (Just 1729))
    (mkConvergenceBar "best_objective" MetricMaximise 1.0 0.05)
    TuningPromotedTraining
    "hyperparameter-sweep"

baseRow
  :: Text
  -> RowFamily
  -> RowClass
  -> Text
  -> Text
  -> TrainingBudget
  -> ConvergenceBar
  -> DeviceClaim
  -> Text
  -> ProductRow 'Declared
baseRow rowId' family' rowClass' implementation' experimentConfig' budget bar claim panel =
  ProductRow
    { rowId = rowId'
    , family = family'
    , rowClass = rowClass'
    , implementation = implementation'
    , rowArchitectureFeatures = []
    , experimentConfig = experimentConfig'
    , trainingBudget = budget
    , convergenceBar = bar
    , deviceClaim = claim
    , productCapability = canonicalProductCapability rowId' rowClass' budget
    , integrationTest = "integration.product." <> sanitizeTestId rowId'
    , e2eTest = "e2e.product." <> sanitizeTestId rowId'
    , demoPanel = panel
    }

canonicalProductCapability :: Text -> RowClass -> TrainingBudget -> ProductCapability
canonicalProductCapability rowId' rowClass' _budget =
  case rowClass' of
    SupervisedClassification _ _ ->
      ExecutableProduct (supervisedDescriptor rowId') SupervisedProductEvidence
    SupervisedRegression _ _ ->
      ExecutableProduct (supervisedDescriptor rowId') SupervisedProductEvidence
    RlAlgorithmEnvironment algorithm environment ->
      rlCapability algorithm environment
    RlGoalConditioned environment ->
      rlCapability "HER" environment
    AlphaZeroGame game ->
      ExecutableProduct
        AlphaZeroProductDescriptor
          { alphaZeroDescriptorGame = game
          , alphaZeroDescriptorSelfPlayGames = alphaZeroProductGames game
          , alphaZeroDescriptorMctsSimulations = RLConvergence.alphaZeroSimulationBudget game
          , alphaZeroDescriptorMaxPlies = fromIntegral (AlphaZero.maxPliesFor game)
          , alphaZeroDescriptorOptimizerUpdates = alphaZeroProductUpdates game
          , alphaZeroDescriptorArenaGames = 9
          }
        AlphaZeroProductEvidence
    HyperparameterTuning _ ->
      ExecutableProduct
        TuningProductDescriptor
          { tuningDescriptorExecutionSpec = Tune.canonicalMnistTuningExecutionSpec
          , tuningDescriptorParallelTrials =
              fromIntegral (Tune.tuningExecutionParallelism Tune.canonicalMnistTuningExecutionSpec)
          , tuningDescriptorPromotions = 1
          , tuningDescriptorPerTrialUpdates =
              fromIntegral
                ( Tune.tuningSchedulerMaxBudget
                    (Tune.tuningExecutionScheduler Tune.canonicalMnistTuningExecutionSpec)
                )
          }
        TuningProductEvidence
 where
  rlCapability algorithm environment =
    case ProductBudget.canonicalProductRlSchedule algorithm environment of
      Left err -> UnsupportedProduct err
      Right schedule ->
        ExecutableProduct
          (rlDescriptorFromSchedule algorithm environment schedule)
          RlProductEvidence
  supervisedDescriptor name =
    SupervisedProductDescriptor
      { supervisedTrainingExamples = supervisedTrainingExampleCount name
      , supervisedEvaluationExamples = supervisedEvaluationExampleCount name
      , supervisedBatchExamples = 128
      , supervisedLearningRate = supervisedProductLearningRate name
      }

  supervisedProductLearningRate name
    | name == "fashion-mnist-resnet" = 3.0e-3
    | name == "cifar10-resnet20" = 1.1e-3
    | name == "cifar10-vit" = 1.5e-3
    | otherwise = 1.0e-3

rlDescriptorFromSchedule
  :: Text
  -> Text
  -> ProductBudget.RlTrainingSchedule
  -> ProductPlanDescriptor 'Plan.ReinforcementLearning
rlDescriptorFromSchedule algorithm environment schedule =
  case schedule of
    ProductBudget.OnPolicyTrainingSchedule {} ->
      descriptor
        (fromIntegral (ProductBudget.scheduleOnPolicyRolloutSteps schedule))
        (fromIntegral (ProductBudget.scheduleOnPolicyVectorEnvironments schedule))
        (fromIntegral (ProductBudget.scheduleOnPolicyMaxEpisodeSteps schedule))
    ProductBudget.FixedStepTrainingSchedule {} ->
      descriptor
        1
        1
        (fromIntegral (ProductBudget.scheduleFixedMaxEpisodeSteps schedule))
    ProductBudget.ArsTrainingSchedule {} ->
      descriptor
        (fromIntegral (ProductBudget.scheduleArsMaxEpisodeSteps schedule))
        1
        (fromIntegral (ProductBudget.scheduleArsMaxEpisodeSteps schedule))
    ProductBudget.HerTrainingSchedule {} ->
      descriptor
        (fromIntegral (ProductBudget.scheduleHerEnvironmentStepsPerEpisode schedule))
        1
        (fromIntegral (ProductBudget.scheduleHerEnvironmentStepsPerEpisode schedule))
 where
  descriptor rolloutTicks vectorEnvironments episodeSteps =
    RlProductDescriptor
      { rlDescriptorAlgorithm = algorithm
      , rlDescriptorEnvironment = environment
      , rlDescriptorRolloutTicksPerEnv = rolloutTicks
      , rlDescriptorVectorEnvironments = vectorEnvironments
      , rlDescriptorEpisodeSteps = episodeSteps
      , rlDescriptorEvaluationEpisodes = fromIntegral ProductBudget.productRlDefaultEvaluationEpisodes
      }

supervisedTrainingExampleCount :: Text -> Word64
supervisedTrainingExampleCount rowId' =
  case rowId' of
    "cifar10-resnet20" -> 1000
    "cifar10-resnet56" -> 1000
    "cifar10-vit" -> 2000
    "tiny-imagenet-resnet50" -> 8000
    _ -> 7000

supervisedEvaluationExampleCount :: Text -> Word64
supervisedEvaluationExampleCount "tiny-imagenet-resnet50" = 1000
supervisedEvaluationExampleCount _ = 1000

alphaZeroProductGames :: Text -> Word64
alphaZeroProductGames "othello" = 4
alphaZeroProductGames _ = 2

alphaZeroProductUpdates :: Text -> Word64
alphaZeroProductUpdates "othello" = 16
alphaZeroProductUpdates _ = 8

staticBudget :: BudgetKind -> Word64 -> Maybe Word64 -> TrainingBudget
staticBudget kind target seed =
  either (error . Text.unpack) id (mkTrainingBudget kind target seed)

-- | Checked-in RL, HER, and AlphaZero experiment configs all declare seed 42.
-- Keep that declarative authority in the ProductRow budget so projection,
-- execution, and completion evidence consume the same explicit value.
canonicalDeviceProductBudget :: TrainingBudget -> TrainingBudget
canonicalDeviceProductBudget budget =
  staticBudget
    (trainingBudgetKind budget)
    (trainingBudgetTargetUnits budget)
    (Just 42)

-- | Refine one raw registry row into its exact kind-indexed semantic plan.
-- Validation is total and accumulating: independent declaration and plan
-- errors are returned together, and an unsupported row never becomes an
-- executable projection.
projectProductRow
  :: Substrate
  -> ProductRow state
  -> Validation (NonEmpty ProductProjectionError) SomeProductProjection
projectProductRow substrate row =
  case productCapability row of
    UnsupportedProduct reason ->
      projectionFailure (UnsupportedProductRow (rowId row) reason)
    ExecutableProduct descriptor requirements ->
      case descriptor of
        supervised@SupervisedProductDescriptor {} ->
          SomeProductProjection SupervisedTrainingWitness
            <$> projectExecutableProduct
              substrate
              row
              ProductSupervisedRun
              SupervisedEpochBudget
              supervised
              requirements
        rl@RlProductDescriptor {} ->
          SomeProductProjection ReinforcementLearningWitness
            <$> projectExecutableProduct
              substrate
              row
              ProductRlRun
              RlEnvironmentStepBudget
              rl
              requirements
        tuning@TuningProductDescriptor {} ->
          SomeProductProjection HyperparameterTuningWitness
            <$> projectExecutableProduct
              substrate
              row
              ProductTuningRun
              TuningTrialBudget
              tuning
              requirements
        alphaZero@AlphaZeroProductDescriptor {} ->
          SomeProductProjection AlphaZeroSelfPlayWitness
            <$> projectExecutableProduct
              substrate
              row
              ProductAlphaZeroRun
              AlphaZeroSelfPlayBudget
              alphaZero
              requirements

-- | Project a whole registry slice for one substrate.  Duplicate identities
-- and every independent row projection failure accumulate before the opaque
-- executable batch can be constructed; successful projections retain input
-- order exactly.
projectProductRows
  :: Substrate
  -> [ProductRow state]
  -> Validation (NonEmpty ProductMatrixError) ProductProjectionBatch
projectProductRows substrate rows =
  buildBatch
    <$> validateUniqueProductIdentities rows
    <*> traverse project rows
 where
  buildBatch _ projections =
    ProductProjectionBatch
      { projectionBatchSubstrateValue = substrate
      , projectionBatchRowIdsValue = fmap rowId rows
      , projectionBatchProjectionsValue = projections
      }
  project =
    mapValidationErrors UnprojectableProductRow
      . projectProductRow substrate

validateUniqueProductIdentities
  :: [ProductRow state]
  -> Validation (NonEmpty ProductMatrixError) ()
validateUniqueProductIdentities rows =
  case identityErrors of
    [] -> Success ()
    first : rest -> Failure (first :| rest)
 where
  identityErrors =
    [EmptyProductProjectionBatch | null rows]
      <> fmap DuplicateProductRowId (duplicates (fmap rowId rows))
      <> fmap
        DuplicateProductExperimentHash
        (duplicates (fmap productRowExperimentHash rows))
      <> fmap
        DuplicateProductIntegrationTest
        (duplicates (fmap integrationTest rows))
      <> fmap
        DuplicateProductE2ETest
        (duplicates (fmap e2eTest rows))

projectExecutableProduct
  :: Substrate
  -> ProductRow state
  -> ProductRunKind
  -> BudgetKind
  -> ProductPlanDescriptor kind
  -> ProductEvidenceRequirements kind
  -> Validation (NonEmpty ProductProjectionError) (ProductProjection kind)
projectExecutableProduct substrate row runKind expectedBudget descriptor requirements =
  buildProjection
    <$> validateProductDeclaration row runKind expectedBudget descriptor
    <*> resolveProductDescriptor substrate row descriptor
 where
  buildProjection validatedBar resolvedPlan =
    ProductProjection
      { projectionRowIdValue = rowId row
      , projectionFamilyValue = family row
      , projectionRowClassValue = rowClass row
      , projectionImplementationValue = implementation row
      , projectionArchitectureFeaturesValue = rowArchitectureFeatures row
      , projectionExperimentHashValue = productRowExperimentHash row
      , projectionExperimentConfigValue = experimentConfig row
      , projectionTrainingBudgetValue = trainingBudget row
      , projectionConvergenceBarValue = validatedConvergenceBar validatedBar
      , projectionDeviceClaimValue = deviceClaim row
      , projectionIntegrationTestValue = integrationTest row
      , projectionE2ETestValue = e2eTest row
      , projectionDemoPanelValue = demoPanel row
      , projectionSubstrateValue = substrate
      , projectionRunKindValue = runKind
      , projectionCommandValue = productCommand substrate row
      , projectionDescriptorValue = descriptor
      , projectionEvidenceRequirementsValue = requirements
      , projectionResolvedPlanValue = resolvedPlan
      }

validateProductDeclaration
  :: ProductRow state
  -> ProductRunKind
  -> BudgetKind
  -> ProductPlanDescriptor kind
  -> Validation
       (NonEmpty ProductProjectionError)
       ValidatedConvergenceBar
validateProductDeclaration row runKind expectedBudget descriptor =
  keepValidatedBar
    <$> mapValidationErrors
      (InvalidProductConvergenceBar (rowId row))
      (validateConvergenceBar (convergenceBar row))
    <*> (validateRequiredProductFields row `andValidation` validateProductRegistryClaims row)
    <*> validateProductFamily row runKind
    <*> validateProductRowClass row runKind descriptor
    <*> validateProductDeviceClaim row
    <*> validateProductBudgetKind row expectedBudget
    <*> (validateProductSeed row `andValidation` validateProductSeedHeadroom row descriptor)
    <*> validateProductDescriptorSemantics row descriptor
 where
  keepValidatedBar bar _ _ _ _ _ _ _ = bar

validateRequiredProductFields
  :: ProductRow state
  -> Validation (NonEmpty ProductProjectionError) ()
validateRequiredProductFields row =
  validationFromErrors
    [ EmptyProductRowField (rowId row) field
    | (field, value) <-
        [ ("rowId", rowId row)
        , ("implementation", implementation row)
        , ("experimentConfig", experimentConfig row)
        , ("integrationTest", integrationTest row)
        , ("e2eTest", e2eTest row)
        , ("demoPanel", demoPanel row)
        ]
    , Text.null (Text.strip value)
    ]

-- | Registry claims are executable contract, not display-only metadata.  A
-- projection retains the claims only after proving that they exactly match
-- the canonical implementation and architecture surface selected by its
-- row class.
validateProductRegistryClaims
  :: ProductRow state
  -> Validation (NonEmpty ProductProjectionError) ()
validateProductRegistryClaims row =
  validateProductImplementation row
    `andValidation` validateProductArchitectureFeatures row

validateProductImplementation
  :: ProductRow state
  -> Validation (NonEmpty ProductProjectionError) ()
validateProductImplementation row =
  requireProjection
    (implementation row == expected)
    (ProductImplementationMismatch (rowId row) expected (implementation row))
 where
  expected = canonicalImplementationForRowClass (rowClass row)

canonicalImplementationForRowClass :: RowClass -> Text
canonicalImplementationForRowClass rowClass' =
  case rowClass' of
    SupervisedClassification _ model ->
      "JitML.SL.Architecture.architectureSpecForProblem/" <> model
    SupervisedRegression _ _ ->
      "JitML.SL.Regression.trainRegressorWithDevice"
    RlAlgorithmEnvironment algorithm _ ->
      "JitML.RL.Algorithms.Registry.moduleFor/" <> algorithm
    RlGoalConditioned _ -> "JitML.RL.Algorithms.HerTrainer.trainHer"
    AlphaZeroGame _ -> "JitML.RL.AlphaZero.SelfPlay"
    HyperparameterTuning _ -> "JitML.Tune.Catalog"

validateProductArchitectureFeatures
  :: ProductRow state
  -> Validation (NonEmpty ProductProjectionError) ()
validateProductArchitectureFeatures row =
  case rowClass row of
    SupervisedClassification {} -> validateSupervised
    SupervisedRegression {} -> validateSupervised
    _ ->
      requireProjection
        (null observed)
        (ProductArchitectureFeaturesMismatch (rowId row) [] observed)
 where
  observed = rowArchitectureFeatures row
  validateSupervised =
    case supervisedCanonicalProblem row of
      Left err ->
        projectionFailure (ProductArchitectureResolutionFailure (rowId row) err)
      Right problem ->
        let expected = canonicalSupervisedArchitectureFeatures (rowClass row) problem
         in requireProjection
              (observed == expected)
              (ProductArchitectureFeaturesMismatch (rowId row) expected observed)

canonicalSupervisedArchitectureFeatures
  :: RowClass
  -> SL.CanonicalProblem
  -> [ArchitectureFeature]
canonicalSupervisedArchitectureFeatures rowClass' problem =
  case rowClass' of
    SupervisedRegression _ _ -> [SLArchitecture.FeatureDense]
    _ -> SLArchitecture.architectureClaimedFeaturesForProblem problem

supervisedCanonicalProblem
  :: ProductRow state
  -> Either Text SL.CanonicalProblem
supervisedCanonicalProblem row =
  case rowClassDatasetModel (rowClass row) of
    Nothing -> Left "row class is not supervised"
    Just (dataset, model) ->
      case [ problem
           | problem <- SL.canonicalProblems
           , SL.problemDataset problem == dataset
           , SL.problemModel problem == model
           ] of
        [problem] -> Right problem
        [] ->
          Left
            ( "no canonical supervised problem has dataset/model "
                <> dataset
                <> "/"
                <> model
            )
        matches ->
          Left
            ( "multiple canonical supervised problems have dataset/model "
                <> dataset
                <> "/"
                <> model
                <> ": "
                <> Text.intercalate ", " (fmap SL.problemName matches)
            )

rowClassDatasetModel :: RowClass -> Maybe (Text, Text)
rowClassDatasetModel rowClass' =
  case rowClass' of
    SupervisedClassification dataset model -> Just (dataset, model)
    SupervisedRegression dataset model -> Just (dataset, model)
    _ -> Nothing

validateProductFamily
  :: ProductRow state
  -> ProductRunKind
  -> Validation (NonEmpty ProductProjectionError) ()
validateProductFamily row runKind =
  requireProjection
    (family row == expectedFamily runKind)
    (ProductFamilyRunKindMismatch (rowId row) (family row) runKind)

validateProductRowClass
  :: ProductRow state
  -> ProductRunKind
  -> ProductPlanDescriptor kind
  -> Validation (NonEmpty ProductProjectionError) ()
validateProductRowClass row runKind descriptor =
  requireProjection
    (rowClassMatchesRunKind runKind (rowClass row))
    (ProductRowClassRunKindMismatch (rowId row) (rowClass row) runKind)
    `andValidation` requireProjection
      (descriptorMatchesRowClass descriptor (rowClass row))
      ( ProductDescriptorRowClassMismatch
          (rowId row)
          ("descriptor=" <> renderProductDescriptor descriptor <> " rowClass=" <> renderRowClass (rowClass row))
      )

validateProductDeviceClaim
  :: ProductRow state
  -> Validation (NonEmpty ProductProjectionError) ()
validateProductDeviceClaim row =
  requireProjection
    (deviceClaim row == expected)
    (ProductDeviceClaimMismatch (rowId row) expected (deviceClaim row))
 where
  expected = expectedDeviceClaim (rowClass row)

expectedDeviceClaim :: RowClass -> DeviceClaim
expectedDeviceClaim rowClass' =
  case rowClass' of
    SupervisedClassification _ _ -> SubstrateBackedANN
    SupervisedRegression _ _ -> SubstrateBackedANN
    RlAlgorithmEnvironment _ _ -> SubstrateBackedPolicy
    RlGoalConditioned _ -> GoalConditionedPolicy
    AlphaZeroGame _ -> SelfPlayPolicyValueNetwork
    HyperparameterTuning _ -> TuningPromotedTraining

validateProductBudgetKind
  :: ProductRow state
  -> BudgetKind
  -> Validation (NonEmpty ProductProjectionError) ()
validateProductBudgetKind row expected =
  requireProjection
    (trainingBudgetKind (trainingBudget row) == expected)
    ( ProductBudgetKindMismatch
        (rowId row)
        expected
        (trainingBudgetKind (trainingBudget row))
    )

validateProductSeed
  :: ProductRow state
  -> Validation (NonEmpty ProductProjectionError) ()
validateProductSeed row =
  case trainingBudgetSeed (trainingBudget row) of
    Nothing -> projectionFailure (MissingProductSeed (rowId row))
    Just seed
      | seed > fromIntegral (maxBound :: Int) ->
          projectionFailure (InvalidProductSeed (rowId row) seed)
    _ -> Success ()

-- | Every product seed is converted to 'Int' and several exact executors then
-- derive deterministic child seeds.  Prove the largest reachable addition is
-- safe at projection time so an otherwise valid near-@maxBound@ seed cannot
-- wrap after effects have begun.
validateProductSeedHeadroom
  :: ProductRow state
  -> ProductPlanDescriptor kind
  -> Validation (NonEmpty ProductProjectionError) ()
validateProductSeedHeadroom row descriptor =
  case (trainingBudgetSeed (trainingBudget row), productSeedHeadroom row descriptor) of
    (Just seed, Just (executor, offset))
      | toInteger seed <= intMaximum
      , toInteger seed + offset > intMaximum ->
          projectionFailure
            (InsufficientProductSeedHeadroom (rowId row) executor seed offset)
    _ -> Success ()
 where
  intMaximum = toInteger (maxBound :: Int)

productSeedHeadroom
  :: ProductRow state
  -> ProductPlanDescriptor kind
  -> Maybe (Text, Integer)
productSeedHeadroom row descriptor =
  case descriptor of
    SupervisedProductDescriptor {} ->
      case supervisedCanonicalProblem row of
        Left _ -> Nothing
        Right problem ->
          case rowClass row of
            SupervisedRegression _ _ ->
              -- Regression owns one MLP initialised directly at the resolved
              -- seed and derives no child Int seed.
              Just ("supervised regression MLP", 0)
            _ ->
              Just
                ( "supervised architecture " <> SL.problemModel problem
                , SLArchitecture.architectureSeedHeadroomForProblem problem
                )
    RlProductDescriptor algorithm _ _ _ _ _ ->
      let trainer = ProductBudget.trainerKindForAlgorithm algorithm
       in case rlTrainerSeedHeadroom trainer of
            Nothing -> Nothing
            Just offset -> Just ("RL trainer " <> trainer, offset)
    TuningProductDescriptor {} ->
      -- Tuning owns a typed trial-seed cohort and validates the trial offset
      -- plus the selected supervised architecture headroom in its resolver.
      Nothing
    AlphaZeroProductDescriptor _ selfPlayGames _ maxPlies _ arenaGames ->
      Just
        ( "AlphaZero outer/self-play/arena executor"
        , alphaZeroSeedHeadroom
            (trainingBudgetTargetUnits (trainingBudget row))
            selfPlayGames
            maxPlies
            arenaGames
        )

rlTrainerSeedHeadroom :: Text -> Maybe Integer
rlTrainerSeedHeadroom trainer =
  case trainer of
    "ppo" -> Just 1
    "a2c" -> Just 1
    "trpo" -> Just 1
    "maskableppo" -> Just 1
    "recurrentppo" -> Just 1
    "dqn" -> Just 1
    "qrdqn" -> Just 1
    "ddpg" -> Just 202
    "td3" -> Just 202
    "sac" -> Just 202
    "crossq" -> Just 202
    "tqc" -> Just 202
    "ars" -> Just 0
    -- Training derives @seed + 1@; the retained greedy evaluator receives
    -- @seed + 104729@, which is the largest reachable derived seed.
    "her" -> Just 104729
    _ -> Nothing

alphaZeroSeedHeadroom :: Word64 -> Word64 -> Word64 -> Word64 -> Integer
alphaZeroSeedHeadroom generations selfPlayGames maxPlies arenaGames =
  max trainingOffset arenaOffset
 where
  lastIndex quantity = max 0 (toInteger quantity - 1)
  -- Outer generation/game derivation is followed by the inner self-play ply
  -- derivation in PolicyValueNet.
  trainingOffset =
    lastIndex generations * 7919
      + lastIndex selfPlayGames
      + lastIndex maxPlies * 7919
  -- The arena caller first adds 7919, then the arena derives a game and ply
  -- offset from that seed.
  arenaOffset =
    7919
      + lastIndex arenaGames * 1009
      + lastIndex maxPlies * 7919

-- | A positive, dimensionally valid RL budget is not yet an executable RL
-- schedule: vector width and trainer granularity can change the number of
-- observed environment transitions.  Refine that relation at the ProductRow
-- boundary so the opaque projection cannot defer a semantic mismatch to the
-- effectful publisher.
validateProductDescriptorSemantics
  :: ProductRow state
  -> ProductPlanDescriptor kind
  -> Validation (NonEmpty ProductProjectionError) ()
validateProductDescriptorSemantics row descriptor =
  validateProductExecutorQuantities row descriptor
    `andValidation` case descriptor of
      SupervisedProductDescriptor _ _ _ learningRate ->
        requireProjection
          ( learningRate > 0.0
              && not (isNaN learningRate)
              && not (isInfinite learningRate)
          )
          (InvalidProductSupervisedLearningRate (rowId row) learningRate)
      RlProductDescriptor
        algorithm
        environment
        rolloutTicks
        vectorEnvironments
        episodeSteps
        evaluationEpisodes ->
          case exactRlSchedule of
            Left err ->
              projectionFailure (InvalidProductRlSchedule (rowId row) err)
            Right schedule ->
              requireProjection
                (rlDescriptorMatchesSchedule rolloutTicks vectorEnvironments episodeSteps schedule)
                ( InvalidProductRlSchedule
                    (rowId row)
                    ( "descriptor does not match the exact resolved schedule: descriptor="
                        <> renderProductDescriptor descriptor
                        <> " schedule="
                        <> showText schedule
                    )
                )
         where
          -- Phase 251 — the descriptor is cross-checked against the compiled
          -- plan's own schedule. The evaluation episode count feeds only the
          -- plan's EvaluationPlan; the schedule is planned against the canonical
          -- training episode-budget floor, so no training dimension the
          -- descriptor is asserted against can depend on it.
          exactRlSchedule = do
            evaluationCount <- word64ToInt "RL evaluation episodes" evaluationEpisodes
            episodeCount <- word64ToInt "RL episode steps" episodeSteps
            vectorCount <- word64ToInt "RL vector environments" vectorEnvironments
            plan <-
              ProductBudget.compileRlPlan
                ProductBudget.TrainingPlan
                  { ProductBudget.trainingPlanTrainerKind =
                      ProductBudget.trainerKindForAlgorithm algorithm
                  , ProductBudget.trainingPlanEnvironment = environment
                  , ProductBudget.trainingPlanSeed = 0
                  , ProductBudget.trainingPlanMaxEpisodeSteps = episodeCount
                  , ProductBudget.trainingPlanEpisodeBudgetFloor =
                      ProductBudget.productRlDefaultTrainingEpisodeFloor
                  , ProductBudget.trainingPlanVectorEnvironments = Just vectorCount
                  , ProductBudget.trainingPlanRequestedTransitionFloor =
                      Just (trainingBudgetTargetUnits (trainingBudget row))
                  , ProductBudget.trainingPlanExactTransitionTarget =
                      Just (trainingBudgetTargetUnits (trainingBudget row))
                  }
                (ProductBudget.EvaluationPlan evaluationCount)
            maybe
              (Left "projected RL plan is missing a training schedule")
              Right
              (ProductBudget.compiledRlSchedule plan)
      _ -> Success ()

validateProductExecutorQuantities
  :: ProductRow state
  -> ProductPlanDescriptor kind
  -> Validation (NonEmpty ProductProjectionError) ()
validateProductExecutorQuantities row descriptor =
  validationFromErrors
    [ InvalidProductExecutorQuantity (rowId row) label value
    | (label, value) <-
        ("training budget target", trainingBudgetTargetUnits (trainingBudget row))
          : descriptorQuantities descriptor
    , value > fromIntegral (maxBound :: Int)
    ]

descriptorQuantities :: ProductPlanDescriptor kind -> [(Text, Word64)]
descriptorQuantities descriptor =
  case descriptor of
    SupervisedProductDescriptor trainingExamples evaluationExamples batchExamples _learningRate ->
      [ ("supervised training examples", trainingExamples)
      , ("supervised evaluation examples", evaluationExamples)
      , ("supervised batch examples", batchExamples)
      ]
    RlProductDescriptor
      _
      _
      rolloutTicks
      vectorEnvironments
      episodeSteps
      evaluationEpisodes ->
        [ ("RL rollout ticks per environment", rolloutTicks)
        , ("RL vector environments", vectorEnvironments)
        , ("RL episode steps", episodeSteps)
        , ("RL evaluation episodes", evaluationEpisodes)
        ]
    TuningProductDescriptor _ parallelTrials promotions perTrialUpdates ->
      [ ("tuning parallel trials", parallelTrials)
      , ("tuning promotions", promotions)
      , ("tuning per-trial optimizer updates", perTrialUpdates)
      ]
    AlphaZeroProductDescriptor _ selfPlayGames simulations maxPlies optimizerUpdates arenaGames ->
      [ ("AlphaZero self-play games", selfPlayGames)
      , ("AlphaZero MCTS simulations", simulations)
      , ("AlphaZero maximum plies", maxPlies)
      , ("AlphaZero optimizer updates", optimizerUpdates)
      , ("AlphaZero arena games", arenaGames)
      ]

rlDescriptorMatchesSchedule
  :: Word64
  -> Word64
  -> Word64
  -> ProductBudget.RlTrainingSchedule
  -> Bool
rlDescriptorMatchesSchedule rolloutTicks vectorEnvironments episodeSteps schedule =
  case schedule of
    ProductBudget.OnPolicyTrainingSchedule {} ->
      rolloutTicks == fromIntegral (ProductBudget.scheduleOnPolicyRolloutSteps schedule)
        && vectorEnvironments == fromIntegral (ProductBudget.scheduleOnPolicyVectorEnvironments schedule)
        && episodeSteps == fromIntegral (ProductBudget.scheduleOnPolicyMaxEpisodeSteps schedule)
    ProductBudget.FixedStepTrainingSchedule {} ->
      rolloutTicks == 1
        && vectorEnvironments == 1
        && episodeSteps == fromIntegral (ProductBudget.scheduleFixedMaxEpisodeSteps schedule)
    ProductBudget.ArsTrainingSchedule {} ->
      rolloutTicks == fromIntegral (ProductBudget.scheduleArsMaxEpisodeSteps schedule)
        && vectorEnvironments == 1
        && episodeSteps == fromIntegral (ProductBudget.scheduleArsMaxEpisodeSteps schedule)
    ProductBudget.HerTrainingSchedule {} ->
      rolloutTicks == fromIntegral (ProductBudget.scheduleHerEnvironmentStepsPerEpisode schedule)
        && vectorEnvironments == 1
        && episodeSteps == fromIntegral (ProductBudget.scheduleHerEnvironmentStepsPerEpisode schedule)

word64ToInt :: Text -> Word64 -> Either Text Int
word64ToInt label value
  | value > fromIntegral (maxBound :: Int) =
      Left (label <> " exceeds the executor Int range: " <> showText value)
  | otherwise = Right (fromIntegral value)

expectedFamily :: ProductRunKind -> RowFamily
expectedFamily runKind =
  case runKind of
    ProductSupervisedRun -> Supervised
    ProductRlRun -> ReinforcementLearning
    ProductTuningRun -> Tuning
    ProductAlphaZeroRun -> AlphaZero

rowClassMatchesRunKind :: ProductRunKind -> RowClass -> Bool
rowClassMatchesRunKind runKind rowClass' =
  case (runKind, rowClass') of
    (ProductSupervisedRun, SupervisedClassification _ _) -> True
    (ProductSupervisedRun, SupervisedRegression _ _) -> True
    (ProductRlRun, RlAlgorithmEnvironment _ _) -> True
    (ProductRlRun, RlGoalConditioned _) -> True
    (ProductTuningRun, HyperparameterTuning _) -> True
    (ProductAlphaZeroRun, AlphaZeroGame _) -> True
    _ -> False

descriptorMatchesRowClass :: ProductPlanDescriptor kind -> RowClass -> Bool
descriptorMatchesRowClass descriptor rowClass' =
  case (descriptor, rowClass') of
    (SupervisedProductDescriptor {}, SupervisedClassification _ _) -> True
    (SupervisedProductDescriptor {}, SupervisedRegression _ _) -> True
    ( RlProductDescriptor algorithm environment _ _ _ _
      , RlAlgorithmEnvironment observedAlgorithm observedEnvironment
      ) ->
        algorithm == observedAlgorithm && environment == observedEnvironment
    (RlProductDescriptor algorithm environment _ _ _ _, RlGoalConditioned observedEnvironment) ->
      Text.toCaseFold algorithm == "her" && environment == observedEnvironment
    (TuningProductDescriptor executionSpec _ _ _, HyperparameterTuning label) ->
      Text.intercalate
        "/"
        [ showText (Tune.tuningSamplerKind (Tune.tuningExecutionSampler executionSpec))
        , showText (Tune.tuningSchedulerKind (Tune.tuningExecutionScheduler executionSpec))
        , showText (Tune.tuningPrunerKind (Tune.tuningExecutionPruner executionSpec))
        ]
        == label
    (AlphaZeroProductDescriptor game _ _ _ _ _, AlphaZeroGame observedGame) ->
      game == observedGame
    _ -> False

resolveProductDescriptor
  :: Substrate
  -> ProductRow state
  -> ProductPlanDescriptor kind
  -> Validation
       (NonEmpty ProductProjectionError)
       (ProductResolvedPlan kind)
resolveProductDescriptor substrate row descriptor =
  case descriptor of
    SupervisedProductDescriptor trainingExamples evaluationExamples batchExamples _learningRate ->
      ResolvedSupervisedProductPlan
        <$> mapValidationErrors
          (InvalidProductWorkloadPlan (rowId row))
          ( resolveSupervisedPlan
              RawSupervisedPlan
                { rawSupervisedRun =
                    rawProductRunRequest
                      substrate
                      row
                      SupervisedTrainingWitness
                      "training"
                      (productSemanticSubject row descriptor (experimentConfig row))
                      (experimentConfig row)
                      ( RawSupervisedBudget
                          (toInteger targetUnits)
                          (toInteger trainingExamples)
                          (toInteger evaluationExamples)
                          (toInteger batchExamples)
                          (supervisedOptimizerUpdates targetUnits trainingExamples batchExamples)
                      )
                }
          )
    RlProductDescriptor
      _algorithm
      _environment
      rolloutTicks
      vectorEnvironments
      episodeSteps
      evaluationEpisodes ->
        ResolvedRlProductPlan
          <$> mapValidationErrors
            (InvalidProductRunPlan (rowId row))
            ( resolveRun
                ( rawProductRunRequest
                    substrate
                    row
                    ReinforcementLearningWitness
                    "rl"
                    (productSemanticSubject row descriptor (experimentConfig row))
                    (productRowExperimentHash row)
                    ( RawRlBudget
                        (toInteger targetUnits)
                        (toInteger rolloutTicks)
                        (toInteger vectorEnvironments)
                        (toInteger episodeSteps)
                        (toInteger evaluationEpisodes)
                    )
                )
            )
    TuningProductDescriptor executionSpec parallelTrials promotions perTrialUpdates ->
      ResolvedTuningProductPlan
        <$> mapValidationErrors
          (InvalidProductWorkloadPlan (rowId row))
          ( resolveTuningPlanWithExecutionSpec
              executionSpec
              RawTuningPlan
                { rawTuningRun =
                    rawProductRunRequest
                      substrate
                      row
                      HyperparameterTuningWitness
                      "tune"
                      (productSemanticSubject row descriptor (experimentConfig row))
                      (experimentConfig row)
                      ( RawTuningBudget
                          (toInteger targetUnits)
                          (toInteger parallelTrials)
                          (toInteger promotions)
                          (toInteger perTrialUpdates)
                      )
                , rawTuningSampler =
                    showText (Tune.tuningSamplerKind (Tune.tuningExecutionSampler executionSpec))
                , rawTuningScheduler =
                    showText (Tune.tuningSchedulerKind (Tune.tuningExecutionScheduler executionSpec))
                , rawTuningPruner =
                    showText (Tune.tuningPrunerKind (Tune.tuningExecutionPruner executionSpec))
                }
          )
    AlphaZeroProductDescriptor game selfPlayGames simulations maxPlies optimizerUpdates arenaGames ->
      ResolvedAlphaZeroProductPlan
        <$> mapValidationErrors
          (InvalidProductWorkloadPlan (rowId row))
          ( resolveAlphaZeroPlan
              RawAlphaZeroPlan
                { rawAlphaZeroRun =
                    rawProductRunRequest
                      substrate
                      row
                      AlphaZeroSelfPlayWitness
                      "rl"
                      (productSemanticSubject row descriptor (experimentConfig row))
                      ("alphazero/" <> productRowExperimentHash row)
                      ( RawAlphaZeroBudget
                          (toInteger targetUnits)
                          (toInteger selfPlayGames)
                          (toInteger simulations)
                          (toInteger maxPlies)
                          (toInteger optimizerUpdates)
                          (toInteger arenaGames)
                      )
                , rawAlphaZeroGame = game
                }
          )
 where
  targetUnits = trainingBudgetTargetUnits (trainingBudget row)

rawProductRunRequest
  :: Substrate
  -> ProductRow state
  -> RunKindWitness kind
  -> Text
  -> Text
  -> Text
  -> RawRunBudget kind
  -> RawRunRequest kind
rawProductRunRequest substrate row witness topicDomain subject artifact budget =
  RawRunRequest
    { rawRunVersion = 1
    , rawRunKind = witness
    , rawRunExperimentId = productRowExperimentHash row
    , rawRunSubjectId = subject
    , rawRunArtifactId = artifact
    , rawRunTopicId = topicDomain <> ".command." <> renderSubstrate substrate
    , rawRunSubstrate = substrate
    , rawRunPlacement = placementForSubstrate substrate
    , rawRunSeeds = [productPlanSeed row]
    , rawRunBudget = budget
    }

-- | Bind the registry semantics that are not dimensions of the common budget
-- into the common RunPlan identity.  Length prefixes keep the encoding
-- injective even when a raw row value contains one of the separators.
productSemanticSubject
  :: ProductRow state
  -> ProductPlanDescriptor kind
  -> Text
  -> Text
productSemanticSubject row descriptor subject =
  Text.concat
    ( "product-row-v1|"
        : fmap
          semanticField
          ( rowClassSemanticFields (rowClass row)
              <> ["row-id", rowId row]
              <> descriptorSemanticFields descriptor
              <> ["subject", subject]
          )
    )

rowClassSemanticFields :: RowClass -> [Text]
rowClassSemanticFields rowClass' =
  case rowClass' of
    SupervisedClassification dataset model ->
      ["row-class", "supervised-classification", dataset, model]
    SupervisedRegression dataset model ->
      ["row-class", "supervised-regression", dataset, model]
    RlAlgorithmEnvironment algorithm environment ->
      ["row-class", "rl-algorithm-environment", algorithm, environment]
    RlGoalConditioned environment ->
      ["row-class", "rl-goal-conditioned", environment]
    AlphaZeroGame game -> ["row-class", "alphazero-game", game]
    HyperparameterTuning label ->
      ["row-class", "hyperparameter-tuning", label]

descriptorSemanticFields :: ProductPlanDescriptor kind -> [Text]
descriptorSemanticFields descriptor =
  case descriptor of
    SupervisedProductDescriptor trainingExamples evaluationExamples batchExamples learningRate ->
      [ "descriptor"
      , "supervised"
      , showText trainingExamples
      , showText evaluationExamples
      , showText batchExamples
      , showText learningRate
      ]
    RlProductDescriptor
      algorithm
      environment
      rolloutTicks
      vectorEnvironments
      episodeSteps
      evaluationEpisodes ->
        [ "descriptor"
        , "rl"
        , algorithm
        , environment
        , showText rolloutTicks
        , showText vectorEnvironments
        , showText episodeSteps
        , showText evaluationEpisodes
        ]
    TuningProductDescriptor executionSpec parallelTrials promotions perTrialUpdates ->
      [ "descriptor"
      , "tuning"
      , Tune.renderTuningExecutionSpec executionSpec
      , showText parallelTrials
      , showText promotions
      , showText perTrialUpdates
      ]
    AlphaZeroProductDescriptor game selfPlayGames simulations maxPlies optimizerUpdates arenaGames ->
      [ "descriptor"
      , "alphazero"
      , game
      , showText selfPlayGames
      , showText simulations
      , showText maxPlies
      , showText optimizerUpdates
      , showText arenaGames
      ]

semanticField :: Text -> Text
semanticField value = showText (Text.length value) <> ":" <> value <> "|"

placementForSubstrate :: Substrate -> RunPlacement
placementForSubstrate _ = InProcessRun

productPlanSeed :: ProductRow state -> Word64
productPlanSeed row =
  fromMaybe 0 (trainingBudgetSeed (trainingBudget row))

supervisedOptimizerUpdates :: Word64 -> Word64 -> Word64 -> Integer
supervisedOptimizerUpdates epochs trainingExamples batchExamples
  | batchExamples == 0 = 0
  | otherwise =
      toInteger epochs
        * toInteger ((trainingExamples + batchExamples - 1) `div` batchExamples)

productCommand :: Substrate -> ProductRow state -> [Text]
productCommand substrate row =
  [ "internal"
  , "train-and-publish-product-rows"
  , "--" <> renderSubstrate substrate
  , "--row"
  , rowId row
  ]

renderProductDescriptor :: ProductPlanDescriptor kind -> Text
renderProductDescriptor descriptor =
  case descriptor of
    SupervisedProductDescriptor trainingExamples evaluationExamples batchExamples learningRate ->
      Text.intercalate
        ":"
        [ "supervised"
        , showText trainingExamples
        , showText evaluationExamples
        , showText batchExamples
        , showText learningRate
        ]
    RlProductDescriptor
      algorithm
      environment
      rolloutTicks
      vectorEnvironments
      episodeSteps
      evaluationEpisodes ->
        Text.intercalate
          ":"
          ( ["rl", algorithm, environment]
              <> fmap
                showText
                [ rolloutTicks
                , vectorEnvironments
                , episodeSteps
                , evaluationEpisodes
                ]
          )
    TuningProductDescriptor executionSpec parallelTrials promotions perTrialUpdates ->
      Text.intercalate
        ":"
        ( ["tuning", Tune.renderTuningExecutionSpec executionSpec]
            <> fmap showText [parallelTrials, promotions, perTrialUpdates]
        )
    AlphaZeroProductDescriptor game selfPlayGames simulations maxPlies optimizerUpdates arenaGames ->
      Text.intercalate
        ":"
        ( ["alphazero", game]
            <> fmap showText [selfPlayGames, simulations, maxPlies, optimizerUpdates, arenaGames]
        )

mapValidationErrors
  :: (leftError -> rightError)
  -> Validation (NonEmpty leftError) value
  -> Validation (NonEmpty rightError) value
mapValidationErrors transform result =
  case result of
    Success value -> Success value
    Failure errors -> Failure (fmap transform errors)

requireProjection
  :: Bool
  -> ProductProjectionError
  -> Validation (NonEmpty ProductProjectionError) ()
requireProjection True _ = Success ()
requireProjection False err = projectionFailure err

validationFromErrors
  :: [ProductProjectionError]
  -> Validation (NonEmpty ProductProjectionError) ()
validationFromErrors [] = Success ()
validationFromErrors (first : rest) = Failure (first :| rest)

andValidation
  :: Validation (NonEmpty ProductProjectionError) ()
  -> Validation (NonEmpty ProductProjectionError) ()
  -> Validation (NonEmpty ProductProjectionError) ()
andValidation left right = (\_ _ -> ()) <$> left <*> right

projectionFailure
  :: ProductProjectionError
  -> Validation (NonEmpty ProductProjectionError) value
projectionFailure err = Failure (err :| [])

showText :: (Show value) => value -> Text
showText = Text.pack . show

validateProductMatrix :: [ProductRow state] -> [Text]
validateProductMatrix = fmap renderProductMatrixError . validateProductMatrixTyped

validateProductMatrixTyped :: [ProductRow state] -> [ProductMatrixError]
validateProductMatrixTyped rows =
  List.nub
    ( batchFailures
        <> nonProductFailures
        <> floorFailures
    )
 where
  ids = fmap rowId rows
  nonProductIds = fmap nonProductRowId nonProductRows
  batchFailures =
    [ matrixError
    | substrate <- allSubstrates
    , Failure matrixErrors <- [projectProductRows substrate rows]
    , matrixError <- nonEmptyValues matrixErrors
    ]
  nonProductFailures =
    [ NonProductRowInProductMatrix nonProductId
    | nonProductId <- nonProductIds
    , nonProductId `elem` ids
    ]
  floorFailures =
    missingFrom "supervised row" (floorSupervisedRows matrixFloor) supervisedIds
      <> unexpectedFrom "supervised row" (floorSupervisedRows matrixFloor) supervisedIds
      <> missingFrom "RL environment" (floorRlEnvironments matrixFloor) rlEnvironments
      <> unexpectedFrom "RL environment" (floorRlEnvironments matrixFloor) rlEnvironments
      <> missingFrom "RL algorithm" (floorRlAlgorithms matrixFloor) rlAlgorithms
      <> unexpectedFrom "RL algorithm" (floorRlAlgorithms matrixFloor) rlAlgorithms
      <> missingFrom "AlphaZero game" (floorAlphaZeroGames matrixFloor) alphaZeroGames
      <> unexpectedFrom "AlphaZero game" (floorAlphaZeroGames matrixFloor) alphaZeroGames
      <> missingFrom "tuning row" (floorTuningRows matrixFloor) tuningIds
      <> unexpectedFrom "tuning row" (floorTuningRows matrixFloor) tuningIds
  supervisedIds =
    [ rowId row
    | row <- rows
    , family row == Supervised
    ]
  rlEnvironments =
    [ environment
    | row <- rows
    , environment <- rowRlEnvironment row
    ]
  rlAlgorithms =
    [ algorithm
    | row <- rows
    , algorithm <- rowRlAlgorithm row
    ]
  alphaZeroGames =
    [ game
    | row <- rows
    , AlphaZeroGame game <- [rowClass row]
    ]
  tuningIds =
    [ rowId row
    | row <- rows
    , family row == Tuning
    ]

renderProductMatrixError :: ProductMatrixError -> Text
renderProductMatrixError matrixError =
  case matrixError of
    EmptyProductProjectionBatch -> "product projection batch is empty"
    DuplicateProductRowId duplicate -> "duplicate row id: " <> duplicate
    DuplicateProductExperimentHash duplicate ->
      "duplicate product experiment hash: " <> duplicate
    DuplicateProductIntegrationTest duplicate ->
      "duplicate product integration test: " <> duplicate
    DuplicateProductE2ETest duplicate ->
      "duplicate product e2e test: " <> duplicate
    NonProductRowInProductMatrix nonProductId ->
      "non-product row appears in product matrix: " <> nonProductId
    MissingMatrixFloorMember label value ->
      "missing matrix-floor " <> label <> ": " <> value
    UnexpectedMatrixFloorMember label value ->
      "undocumented matrix " <> label <> ": " <> value
    UnprojectableProductRow projectionError -> renderProductProjectionError projectionError

renderProductProjectionError :: ProductProjectionError -> Text
renderProductProjectionError projectionError =
  case projectionError of
    UnsupportedProductRow rowId' reason ->
      rowId' <> " is unsupported: " <> reason
    EmptyProductRowField rowId' field ->
      rowId' <> " is missing " <> field
    ProductFamilyRunKindMismatch rowId' observed expected ->
      rowId'
        <> " family/run-kind mismatch: family="
        <> renderRowFamily observed
        <> " runKind="
        <> showText expected
    ProductRowClassRunKindMismatch rowId' observed expected ->
      rowId'
        <> " row-class/run-kind mismatch: rowClass="
        <> renderRowClass observed
        <> " runKind="
        <> showText expected
    ProductDescriptorRowClassMismatch rowId' detail ->
      rowId' <> " descriptor/row-class mismatch: " <> detail
    ProductDeviceClaimMismatch rowId' expected observed ->
      rowId'
        <> " device-claim mismatch: expected="
        <> showText expected
        <> " observed="
        <> showText observed
    ProductBudgetKindMismatch rowId' expected observed ->
      rowId'
        <> " budget-kind mismatch: expected="
        <> showText expected
        <> " observed="
        <> showText observed
    MissingProductSeed rowId' ->
      rowId' <> " is missing the explicit seed required by the exact product executor"
    InvalidProductSeed rowId' seed ->
      rowId'
        <> " seed exceeds the exact product executor Int range: "
        <> showText seed
    InsufficientProductSeedHeadroom rowId' executor seed offset ->
      rowId'
        <> " seed does not leave enough Int headroom for "
        <> executor
        <> ": seed="
        <> showText seed
        <> " maximum-derived-offset="
        <> showText offset
        <> " largest-derived-seed="
        <> showText (toInteger seed + offset)
    InvalidProductExecutorQuantity rowId' label value ->
      rowId'
        <> " "
        <> label
        <> " exceeds the exact product executor Int range: "
        <> showText value
    InvalidProductSupervisedLearningRate rowId' learningRate ->
      rowId'
        <> " has an invalid supervised learning rate (expected a finite positive value): "
        <> showText learningRate
    ProductImplementationMismatch rowId' expected observed ->
      rowId'
        <> " implementation mismatch: expected="
        <> expected
        <> " observed="
        <> observed
    ProductArchitectureFeaturesMismatch rowId' expected observed ->
      rowId'
        <> " architecture-feature mismatch: expected="
        <> showText expected
        <> " observed="
        <> showText observed
    ProductArchitectureResolutionFailure rowId' err ->
      rowId' <> " cannot resolve canonical architecture claims: " <> err
    InvalidProductConvergenceBar rowId' err ->
      rowId' <> " has invalid convergence bar: " <> showText err
    InvalidProductRunPlan rowId' err ->
      rowId' <> " has invalid run plan: " <> showText err
    InvalidProductWorkloadPlan rowId' err ->
      rowId' <> " has invalid workload plan: " <> showText err
    InvalidProductRlSchedule rowId' err ->
      rowId' <> " has invalid RL product schedule: " <> err

nonEmptyValues :: NonEmpty value -> [value]
nonEmptyValues (first :| rest) = first : rest

rowRlEnvironment :: ProductRow state -> [Text]
rowRlEnvironment row =
  case rowClass row of
    RlAlgorithmEnvironment _ environment -> [environment]
    RlGoalConditioned _ -> []
    _ -> []

rowRlAlgorithm :: ProductRow state -> [Text]
rowRlAlgorithm row =
  case rowClass row of
    RlAlgorithmEnvironment algorithm _ -> [algorithm]
    RlGoalConditioned _ -> ["HER"]
    _ -> []

missingFrom :: Text -> [Text] -> [Text] -> [ProductMatrixError]
missingFrom label required present =
  [ MissingMatrixFloorMember label value
  | value <- required
  , value `notElem` present
  ]

unexpectedFrom :: Text -> [Text] -> [Text] -> [ProductMatrixError]
unexpectedFrom label allowed present =
  [ UnexpectedMatrixFloorMember label value
  | value <- present
  , value `notElem` allowed
  ]

duplicates :: [Text] -> [Text]
duplicates values =
  [ value
  | value : _ : _ <- List.group (List.sort values)
  ]

renderRowFamily :: RowFamily -> Text
renderRowFamily rowFamily =
  case rowFamily of
    Supervised -> "supervised"
    ReinforcementLearning -> "rl"
    AlphaZero -> "alphazero"
    Tuning -> "tuning"

renderRowClass :: RowClass -> Text
renderRowClass rowClass' =
  case rowClass' of
    SupervisedClassification dataset model -> "classification:" <> dataset <> "/" <> model
    SupervisedRegression dataset model -> "regression:" <> dataset <> "/" <> model
    RlAlgorithmEnvironment algorithm environment -> "rl:" <> algorithm <> "/" <> environment
    RlGoalConditioned environment -> "rl:HER/" <> environment
    AlphaZeroGame game -> "alphazero:" <> game
    HyperparameterTuning label -> "tuning:" <> label

supervisedDemoPanel :: SL.CanonicalProblem -> Text
supervisedDemoPanel problem
  | "CIFAR" `Text.isPrefixOf` SL.problemDataset problem = "cifar-imagenet-upload"
  | SL.problemDataset problem == "Tiny ImageNet" = "cifar-imagenet-upload"
  | SL.problemDataset problem == "California Housing" = "generic-inference-lab"
  | otherwise = "mnist-live-inference"

rlRowId :: Text -> Text -> Text
rlRowId algorithm environment = algorithm <> "/" <> environment

sanitizeTestId :: Text -> Text
sanitizeTestId =
  Text.map $ \ch ->
    case ch of
      '/' -> '.'
      ' ' -> '-'
      _ -> ch
