{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Product.Matrix
  ( DeviceClaim (..)
  , EvidenceHandle (..)
  , EvidenceKind (..)
  , MatrixFloor (..)
  , ModelState (..)
  , NonProductRow (..)
  , ProductRow (..)
  , RowClass (..)
  , RowFamily (..)
  , allProductRows
  , matrixFloor
  , matrixFloorRowCount
  , nonProductRows
  , productRowCount
  , productRowDeviceEvidenceForSubstrate
  , productRowExperimentHash
  , productRowForExperimentHash
  , productRowIds
  , renderRowClass
  , renderRowFamily
  , selectProductRows
  , validateProductMatrix
  )
where

import Data.List qualified as List
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)

import JitML.Product.Convergence
  ( ConvergenceBar
  , barFromObservation
  , classificationAccuracyBar
  , mkConvergenceBar
  , regressionRmseBar
  )
import JitML.RL.ConvergenceThresholds qualified as RLConvergence
import JitML.SL.Architecture (ArchitectureFeature)
import JitML.SL.Architecture qualified as SLArchitecture
import JitML.SL.Canonicals qualified as SL
import JitML.SL.ConvergenceThresholds qualified as SLConvergence
import JitML.Substrate (Substrate (..), renderSubstrate)
import JitML.Training.Budget
  ( BudgetKind (..)
  , MetricGoal (..)
  , TrainingBudget
  , mkTrainingBudget
  )

data ModelState
  = Declared
  | TrainingStarted
  | TrainingCompleted
  | InferenceEligible
  deriving stock (Eq, Show)

data EvidenceKind
  = TrainingEvidence
  | DeviceEvidence
  | CheckpointEvidence
  | DemoEvidence
  deriving stock (Eq, Show)

newtype EvidenceHandle (state :: ModelState) (kind :: EvidenceKind) = EvidenceHandle
  { unEvidenceHandle :: Text
  }
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
  , trainingEvidence :: Maybe (EvidenceHandle state 'TrainingEvidence)
  , deviceEvidence :: Maybe (EvidenceHandle state 'DeviceEvidence)
  , checkpointEvidence :: Maybe (EvidenceHandle state 'CheckpointEvidence)
  , demoEvidence :: Maybe (EvidenceHandle state 'DemoEvidence)
  , integrationTest :: Text
  , e2eTest :: Text
  , demoPanel :: Text
  }
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
  Text.intercalate
    ":"
    [ "device"
    , renderSubstrate substrate
    , substrateDeviceRuntime substrate
    , deviceClaimKernelSummary (deviceClaim row)
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
      ("JitML.SL.Architecture.architectureSpecForProblem/" <> SL.problemModel problem)
      ("experiments/" <> SL.problemName problem <> ".dhall")
      ( staticBudget
          SupervisedEpochBudget
          (supervisedEpochBudget (SL.problemName problem))
          (Just (fromIntegral (SL.problemSeed problem)))
      )
      bar
      SubstrateBackedANN
      (supervisedDemoPanel problem)
  )
    { rowArchitectureFeatures = SLArchitecture.architectureClaimedFeaturesForProblem problem
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
-- The compact heavy-vision rows converge under five epochs over their bounded
-- product datasets; the remaining supervised rows use the ten-epoch schedule
-- that their real convergence runs exercise.  Producers must consume this
-- value rather than independently clamping or extending it.
supervisedEpochBudget :: Text -> Word64
supervisedEpochBudget problemName =
  case problemName of
    "cifar10-resnet20" -> 5
    "cifar10-resnet56" -> 5
    "cifar10-vit" -> 5
    "tiny-imagenet-resnet50" -> 5
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
    ("experiments/" <> RLConvergence.fbrEnvironment row <> ".dhall")
    (RLConvergence.fbrBudget row)
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
   in baseRow
        ("HER/" <> RLConvergence.hgmEnvironment metric)
        ReinforcementLearning
        (RlGoalConditioned (RLConvergence.hgmEnvironment metric))
        "JitML.RL.Algorithms.HerTrainer.trainHer"
        ("experiments/" <> RLConvergence.hgmEnvironment metric <> ".dhall")
        (RLConvergence.hgmBudget metric)
        (barFromObservation 0.05 (RLConvergence.hgmSuccessRate metric))
        GoalConditionedPolicy
        "rl-trajectory"

alphaZeroRows :: [ProductRow 'Declared]
alphaZeroRows =
  fmap alphaZeroRow RLConvergence.alphaZeroGameConvergenceRows

alphaZeroRow :: RLConvergence.AlphaZeroGameConvergenceRow -> ProductRow 'Declared
alphaZeroRow row =
  ( baseRow
      game
      AlphaZero
      (AlphaZeroGame game)
      "JitML.RL.AlphaZero.SelfPlay"
      ("experiments/alphazero-" <> game <> ".dhall")
      (RLConvergence.azgBudget row)
      (barFromObservation 0.10 (RLConvergence.azgArenaWinRate row))
      SelfPlayPolicyValueNetwork
      "connect4-human-vs-alphazero"
  )
    { trainingEvidence = Just (EvidenceHandle ("training:alphazero:" <> game))
    , deviceEvidence = Just (EvidenceHandle "device:linux-cpu:oneDNN:policy-value")
    , checkpointEvidence = Just (EvidenceHandle ("checkpoint:alphazero:" <> game <> ":latest"))
    }
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
    , trainingEvidence = Nothing
    , deviceEvidence = Nothing
    , checkpointEvidence = Nothing
    , demoEvidence = Nothing
    , integrationTest = "integration.product." <> sanitizeTestId rowId'
    , e2eTest = "e2e.product." <> sanitizeTestId rowId'
    , demoPanel = panel
    }

staticBudget :: BudgetKind -> Word64 -> Maybe Word64 -> TrainingBudget
staticBudget kind target seed =
  either (error . Text.unpack) id (mkTrainingBudget kind target seed)

validateProductMatrix :: [ProductRow state] -> [Text]
validateProductMatrix rows =
  duplicateFailures
    <> missingFieldFailures
    <> nonProductFailures
    <> floorFailures
 where
  ids = fmap rowId rows
  nonProductIds = fmap nonProductRowId nonProductRows
  duplicateFailures =
    [ "duplicate row id: " <> duplicate
    | duplicate <- duplicates ids
    ]
  missingFieldFailures =
    concatMap missingFields rows
  missingFields row =
    [ rowId row <> " is missing integrationTest"
    | Text.null (integrationTest row)
    ]
      <> [ rowId row <> " is missing e2eTest"
         | Text.null (e2eTest row)
         ]
      <> [ rowId row <> " is missing demoPanel"
         | Text.null (demoPanel row)
         ]
      <> [ rowId row <> " is missing experimentConfig"
         | Text.null (experimentConfig row)
         ]
      <> [ rowId row <> " is missing rowArchitectureFeatures"
         | family row == Supervised
         , null (rowArchitectureFeatures row)
         ]
  nonProductFailures =
    [ "non-product row appears in product matrix: " <> nonProductId
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

missingFrom :: Text -> [Text] -> [Text] -> [Text]
missingFrom label required present =
  [ "missing matrix-floor " <> label <> ": " <> value
  | value <- required
  , value `notElem` present
  ]

unexpectedFrom :: Text -> [Text] -> [Text] -> [Text]
unexpectedFrom label allowed present =
  [ "undocumented matrix " <> label <> ": " <> value
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
