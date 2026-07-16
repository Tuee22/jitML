module Generated.Contracts where

import Prelude

import Data.Array as Array
import Data.Int as Int
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Number as Number
import Data.String as String
import Data.String.Pattern (Pattern(..))
import Data.Traversable (traverse)

type Endpoint = { name :: String, method :: String, path :: String }

type TunePlanBudget =
  { trials :: Int
  , parallelism :: Int
  , promotions :: Int
  , optimizerUpdatesPerTrial :: Int
  }

type BrowserInferenceRequest =
  { panel :: String
  , modelId :: String
  , experimentHash :: String
  , input :: Array Number
  }

type BrowserImageRequest =
  { panel :: String
  , datasetName :: String
  , experimentHash :: String
  , imageBase64 :: String
  , input :: Array Number
  }

type BrowserGenericInferenceRequest =
  { panel :: String
  , experimentHash :: String
  , input :: Array Number
  }

type BrowserCheckpointCompareRequest =
  { panel :: String
  , baselineExperimentHash :: String
  , candidateExperimentHash :: String
  , input :: Array Number
  }

type BrowserAdversarialMoveRequest =
  { panel :: String
  , game :: String
  , experimentHash :: String
  , moves :: Array Int
  , humanIsPlayer :: Int
  , simulationsPerMove :: Int
  }

type InferenceResult =
  { panel :: String
  , modelId :: String
  , checkpointSha :: String
  , topClass :: Int
  , confidence :: Number
  , latencyMs :: Number
  , probabilities :: Array Number
  , output :: Array Number
  , status :: String
  }

type ImageInferenceResult =
  { panel :: String
  , datasetName :: String
  , checkpointSha :: String
  , topK :: Array Int
  , probabilities :: Array Number
  , preprocessingMs :: Number
  , inferenceMs :: Number
  , status :: String
  }

type GenericInferenceResult =
  { panel :: String
  , experimentHash :: String
  , checkpointSha :: String
  , latencyMs :: Number
  , output :: Array Number
  , status :: String
  }

type CheckpointCompareResult =
  { panel :: String
  , baselineCheckpointSha :: String
  , candidateCheckpointSha :: String
  , baselineOutput :: Array Number
  , candidateOutput :: Array Number
  , maxAbsDelta :: Number
  , meanAbsDelta :: Number
  , latencyMs :: Number
  , status :: String
  }

type AdversarialMoveResult =
  { panel :: String
  , game :: String
  , chosenColumn :: Int
  , legalMoves :: Array Int
  , visitCounts :: Array Int
  , policyPriors :: Array Number
  , valueEstimate :: Number
  , gameOver :: Boolean
  , transcriptId :: String
  }

type TrainingEventFrame =
  { panel :: String
  , experimentHash :: String
  , epoch :: Int
  , step :: Int
  , trainingLoss :: Number
  , validationLoss :: Number
  , throughput :: Number
  , device :: String
  , checkpointSha :: String
  , tensorboardUrl :: String
  , timestampNs :: String
  }

type RlAnimationFrame =
  { panel :: String
  , experimentHash :: String
  , environment :: String
  , episodeIndex :: Int
  , stepIndex :: Int
  , reward :: Number
  , done :: Boolean
  , action :: Int
  , observation :: Array Number
  , actionProbabilities :: Array Number
  , observationHash :: String
  , replayCursor :: String
  , timestampNs :: String
  }

type RlReplayFrame =
  { panel :: String
  , experimentHash :: String
  , replayId :: String
  , environment :: String
  , episodeIndex :: Int
  , stepIndex :: Int
  , action :: Int
  , reward :: Number
  , done :: Boolean
  , observation :: Array Number
  , nextObservation :: Array Number
  , policyVersion :: String
  , observationHash :: String
  , timestampNs :: String
  }

type TuneTrialFrame =
  { panel :: String
  , sweepId :: String
  , trialIndex :: Int
  , trialSeed :: Int
  , objective :: Number
  , pruned :: Boolean
  , sampler :: String
  , scheduler :: String
  , pruner :: String
  , parametersJson :: String
  , checkpointSha :: String
  }

type TuneSweepDoneFrame =
  { panel :: String
  , sweepId :: String
  , trialsCompleted :: Int
  , trialsPruned :: Int
  , bestObjective :: Number
  , promotedCheckpointSha :: String
  }

type WorkflowCommandAck =
  { runId :: String
  , command :: String
  , status :: String
  }

type WorkflowStatus =
  { panel :: String
  , runId :: String
  , status :: String
  , detail :: String
  }

-- Sprint 11.10 — the Engine-decoded inference result (one discriminated
-- record over OutputDecoderKind). The panels render its fields directly; no
-- browser-side decode (argmax/softmax) happens.
type DecodedInference =
  { kind :: String
  , topClass :: Int
  , confidence :: Number
  , probabilities :: Array Number
  , labels :: Array String
  , values :: Array Number
  , value :: Number
  , output :: Array Number
  }

-- Sprint 11.10 — the Engine-computed checkpoint-compare frame (two
-- inferences + delta, all in the daemon).
type CompareFrame =
  { baselineExperimentHash :: String
  , candidateExperimentHash :: String
  , baselineOutput :: Array Number
  , candidateOutput :: Array Number
  , maxAbsDelta :: Number
  , meanAbsDelta :: Number
  }

-- Sprint 11.10 — the Engine-computed adversarial-move frame (inference +
-- MCTS, all in the daemon).
type MoveFrame =
  { experimentHash :: String
  , game :: String
  , chosenColumn :: Int
  , legalMoves :: Array Int
  , visitCounts :: Array Int
  , policyPriors :: Array Number
  , valueEstimate :: Number
  , gameOver :: Boolean
  , transcriptId :: String
  }

-- One product-row checkpoint manifest summary, parsed
-- from a tab-separated `checkpoint-summary:` line of the Engine's
-- `CheckpointList` frame.
type CheckpointSummary =
  { rowId :: String
  , experimentHash :: String
  , sha :: String
  , step :: Int
  , modelFamily :: String
  , tensorCount :: Int
  , eligibility :: String
  , completedBudget :: String
  , convergenceMetrics :: String
  , tensorboardPrefix :: String
  }

type ProductRowSelector =
  { rowId :: String
  , experimentHash :: String
  , family :: String
  , selectorState :: String
  , checkpointCount :: Int
  , demoPanel :: String
  }

-- The Engine-listed product-row checkpoint catalogue, including per-row
-- selector state and inference-eligible manifests listed from MinIO.
type CheckpointList =
  { kind :: String
  , panel :: String
  , selectorState :: String
  , rowSelectors :: Array ProductRowSelector
  , checkpoints :: Array CheckpointSummary
  }

-- Sprint 19.1 — browser-visible product matrix, generated through
-- `JitML.Test.WorkflowMatrix.allModelCells` from
-- `JitML.Product.Matrix.allProductRows` so the PureScript app,
-- Playwright suite, and Haskell tests consume one product registry.
type ModelMatrixRow =
  { kind :: String
  , name :: String
  , experimentHash :: String
  , e2eTest :: String
  , demoPanel :: String
  , budget :: String
  , command :: Array String
  , requiresTrainedArtifact :: Boolean
  }

allModelMatrixRows :: Array ModelMatrixRow
allModelMatrixRows =
  [ { kind: "supervised", name: "mnist-shallow-mlp", experimentHash: "product-row-mnist-shallow-mlp", e2eTest: "e2e.product.mnist-shallow-mlp", demoPanel: "mnist-live-inference", budget: "supervised-epochs:10:epochs:seed-1001", command: [ "train", "experiments/mnist-shallow-mlp.dhall" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "mnist-deep-mlp", experimentHash: "product-row-mnist-deep-mlp", e2eTest: "e2e.product.mnist-deep-mlp", demoPanel: "mnist-live-inference", budget: "supervised-epochs:10:epochs:seed-1002", command: [ "train", "experiments/mnist-deep-mlp.dhall" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "mnist-lenet", experimentHash: "product-row-mnist-lenet", e2eTest: "e2e.product.mnist-lenet", demoPanel: "mnist-live-inference", budget: "supervised-epochs:10:epochs:seed-1003", command: [ "train", "experiments/mnist-lenet.dhall" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "fashion-mnist-mlp", experimentHash: "product-row-fashion-mnist-mlp", e2eTest: "e2e.product.fashion-mnist-mlp", demoPanel: "mnist-live-inference", budget: "supervised-epochs:10:epochs:seed-1004", command: [ "train", "experiments/fashion-mnist-mlp.dhall" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "fashion-mnist-resnet", experimentHash: "product-row-fashion-mnist-resnet", e2eTest: "e2e.product.fashion-mnist-resnet", demoPanel: "mnist-live-inference", budget: "supervised-epochs:10:epochs:seed-1005", command: [ "train", "experiments/fashion-mnist-resnet.dhall" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "cifar10-resnet20", experimentHash: "product-row-cifar10-resnet20", e2eTest: "e2e.product.cifar10-resnet20", demoPanel: "cifar-imagenet-upload", budget: "supervised-epochs:5:epochs:seed-1006", command: [ "train", "experiments/cifar10-resnet20.dhall" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "cifar10-resnet56", experimentHash: "product-row-cifar10-resnet56", e2eTest: "e2e.product.cifar10-resnet56", demoPanel: "cifar-imagenet-upload", budget: "supervised-epochs:5:epochs:seed-1007", command: [ "train", "experiments/cifar10-resnet56.dhall" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "cifar100-wide-resnet", experimentHash: "product-row-cifar100-wide-resnet", e2eTest: "e2e.product.cifar100-wide-resnet", demoPanel: "cifar-imagenet-upload", budget: "supervised-epochs:10:epochs:seed-1008", command: [ "train", "experiments/cifar100-wide-resnet.dhall" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "cifar10-vit", experimentHash: "product-row-cifar10-vit", e2eTest: "e2e.product.cifar10-vit", demoPanel: "cifar-imagenet-upload", budget: "supervised-epochs:5:epochs:seed-1009", command: [ "train", "experiments/cifar10-vit.dhall" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "tiny-imagenet-resnet50", experimentHash: "product-row-tiny-imagenet-resnet50", e2eTest: "e2e.product.tiny-imagenet-resnet50", demoPanel: "cifar-imagenet-upload", budget: "supervised-epochs:5:epochs:seed-1010", command: [ "train", "experiments/tiny-imagenet-resnet50.dhall" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "california-housing-mlp", experimentHash: "product-row-california-housing-mlp", e2eTest: "e2e.product.california-housing-mlp", demoPanel: "generic-inference-lab", budget: "supervised-epochs:10:epochs:seed-1011", command: [ "train", "experiments/california-housing-mlp.dhall" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/cartpole", experimentHash: "product-row-PPO.cartpole", e2eTest: "e2e.product.PPO.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seedless", command: [ "rl", "train", "experiments/cartpole.dhall", "--algorithm", "PPO" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/mountain-car", experimentHash: "product-row-PPO.mountain-car", e2eTest: "e2e.product.PPO.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seedless", command: [ "rl", "train", "experiments/mountain-car.dhall", "--algorithm", "PPO" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/acrobot", experimentHash: "product-row-PPO.acrobot", e2eTest: "e2e.product.PPO.acrobot", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seedless", command: [ "rl", "train", "experiments/acrobot.dhall", "--algorithm", "PPO" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/lunar-lander", experimentHash: "product-row-PPO.lunar-lander", e2eTest: "e2e.product.PPO.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2400000:environment-steps:seedless", command: [ "rl", "train", "experiments/lunar-lander.dhall", "--algorithm", "PPO" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/key-door-grid", experimentHash: "product-row-PPO.key-door-grid", e2eTest: "e2e.product.PPO.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seedless", command: [ "rl", "train", "experiments/key-door-grid.dhall", "--algorithm", "PPO" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/gridworld-deterministic", experimentHash: "product-row-PPO.gridworld-deterministic", e2eTest: "e2e.product.PPO.gridworld-deterministic", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seedless", command: [ "rl", "train", "experiments/gridworld-deterministic.dhall", "--algorithm", "PPO" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "A2C/cartpole", experimentHash: "product-row-A2C.cartpole", e2eTest: "e2e.product.A2C.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seedless", command: [ "rl", "train", "experiments/cartpole.dhall", "--algorithm", "A2C" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "A2C/mountain-car", experimentHash: "product-row-A2C.mountain-car", e2eTest: "e2e.product.A2C.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seedless", command: [ "rl", "train", "experiments/mountain-car.dhall", "--algorithm", "A2C" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "A2C/lunar-lander", experimentHash: "product-row-A2C.lunar-lander", e2eTest: "e2e.product.A2C.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2400000:environment-steps:seedless", command: [ "rl", "train", "experiments/lunar-lander.dhall", "--algorithm", "A2C" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "A2C/key-door-grid", experimentHash: "product-row-A2C.key-door-grid", e2eTest: "e2e.product.A2C.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seedless", command: [ "rl", "train", "experiments/key-door-grid.dhall", "--algorithm", "A2C" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TRPO/cartpole", experimentHash: "product-row-TRPO.cartpole", e2eTest: "e2e.product.TRPO.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seedless", command: [ "rl", "train", "experiments/cartpole.dhall", "--algorithm", "TRPO" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TRPO/mountain-car", experimentHash: "product-row-TRPO.mountain-car", e2eTest: "e2e.product.TRPO.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seedless", command: [ "rl", "train", "experiments/mountain-car.dhall", "--algorithm", "TRPO" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TRPO/lunar-lander", experimentHash: "product-row-TRPO.lunar-lander", e2eTest: "e2e.product.TRPO.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2400000:environment-steps:seedless", command: [ "rl", "train", "experiments/lunar-lander.dhall", "--algorithm", "TRPO" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TRPO/key-door-grid", experimentHash: "product-row-TRPO.key-door-grid", e2eTest: "e2e.product.TRPO.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seedless", command: [ "rl", "train", "experiments/key-door-grid.dhall", "--algorithm", "TRPO" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "MaskablePPO/cartpole", experimentHash: "product-row-MaskablePPO.cartpole", e2eTest: "e2e.product.MaskablePPO.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seedless", command: [ "rl", "train", "experiments/cartpole.dhall", "--algorithm", "MaskablePPO" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "MaskablePPO/mountain-car", experimentHash: "product-row-MaskablePPO.mountain-car", e2eTest: "e2e.product.MaskablePPO.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seedless", command: [ "rl", "train", "experiments/mountain-car.dhall", "--algorithm", "MaskablePPO" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "MaskablePPO/lunar-lander", experimentHash: "product-row-MaskablePPO.lunar-lander", e2eTest: "e2e.product.MaskablePPO.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2400000:environment-steps:seedless", command: [ "rl", "train", "experiments/lunar-lander.dhall", "--algorithm", "MaskablePPO" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "MaskablePPO/key-door-grid", experimentHash: "product-row-MaskablePPO.key-door-grid", e2eTest: "e2e.product.MaskablePPO.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seedless", command: [ "rl", "train", "experiments/key-door-grid.dhall", "--algorithm", "MaskablePPO" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "RecurrentPPO/cartpole", experimentHash: "product-row-RecurrentPPO.cartpole", e2eTest: "e2e.product.RecurrentPPO.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seedless", command: [ "rl", "train", "experiments/cartpole.dhall", "--algorithm", "RecurrentPPO" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "RecurrentPPO/mountain-car", experimentHash: "product-row-RecurrentPPO.mountain-car", e2eTest: "e2e.product.RecurrentPPO.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seedless", command: [ "rl", "train", "experiments/mountain-car.dhall", "--algorithm", "RecurrentPPO" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "RecurrentPPO/lunar-lander", experimentHash: "product-row-RecurrentPPO.lunar-lander", e2eTest: "e2e.product.RecurrentPPO.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2400000:environment-steps:seedless", command: [ "rl", "train", "experiments/lunar-lander.dhall", "--algorithm", "RecurrentPPO" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "RecurrentPPO/key-door-grid", experimentHash: "product-row-RecurrentPPO.key-door-grid", e2eTest: "e2e.product.RecurrentPPO.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:307200:environment-steps:seedless", command: [ "rl", "train", "experiments/key-door-grid.dhall", "--algorithm", "RecurrentPPO" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "DQN/cartpole", experimentHash: "product-row-DQN.cartpole", e2eTest: "e2e.product.DQN.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seedless", command: [ "rl", "train", "experiments/cartpole.dhall", "--algorithm", "DQN" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "DQN/mountain-car", experimentHash: "product-row-DQN.mountain-car", e2eTest: "e2e.product.DQN.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:120000:environment-steps:seedless", command: [ "rl", "train", "experiments/mountain-car.dhall", "--algorithm", "DQN" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "DQN/key-door-grid", experimentHash: "product-row-DQN.key-door-grid", e2eTest: "e2e.product.DQN.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seedless", command: [ "rl", "train", "experiments/key-door-grid.dhall", "--algorithm", "DQN" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "QR-DQN/cartpole", experimentHash: "product-row-QR-DQN.cartpole", e2eTest: "e2e.product.QR-DQN.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seedless", command: [ "rl", "train", "experiments/cartpole.dhall", "--algorithm", "QR-DQN" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "QR-DQN/mountain-car", experimentHash: "product-row-QR-DQN.mountain-car", e2eTest: "e2e.product.QR-DQN.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:120000:environment-steps:seedless", command: [ "rl", "train", "experiments/mountain-car.dhall", "--algorithm", "QR-DQN" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "QR-DQN/key-door-grid", experimentHash: "product-row-QR-DQN.key-door-grid", e2eTest: "e2e.product.QR-DQN.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:120000:environment-steps:seedless", command: [ "rl", "train", "experiments/key-door-grid.dhall", "--algorithm", "QR-DQN" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "DDPG/lunar-lander", experimentHash: "product-row-DDPG.lunar-lander", e2eTest: "e2e.product.DDPG.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:120000:environment-steps:seedless", command: [ "rl", "train", "experiments/lunar-lander.dhall", "--algorithm", "DDPG" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TD3/lunar-lander", experimentHash: "product-row-TD3.lunar-lander", e2eTest: "e2e.product.TD3.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seedless", command: [ "rl", "train", "experiments/lunar-lander.dhall", "--algorithm", "TD3" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "SAC/lunar-lander", experimentHash: "product-row-SAC.lunar-lander", e2eTest: "e2e.product.SAC.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seedless", command: [ "rl", "train", "experiments/lunar-lander.dhall", "--algorithm", "SAC" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "SAC/pendulum", experimentHash: "product-row-SAC.pendulum", e2eTest: "e2e.product.SAC.pendulum", demoPanel: "rl-trajectory", budget: "rl-environment-steps:4000:environment-steps:seedless", command: [ "rl", "train", "experiments/pendulum.dhall", "--algorithm", "SAC" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "CrossQ/lunar-lander", experimentHash: "product-row-CrossQ.lunar-lander", e2eTest: "e2e.product.CrossQ.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seedless", command: [ "rl", "train", "experiments/lunar-lander.dhall", "--algorithm", "CrossQ" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TQC/lunar-lander", experimentHash: "product-row-TQC.lunar-lander", e2eTest: "e2e.product.TQC.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seedless", command: [ "rl", "train", "experiments/lunar-lander.dhall", "--algorithm", "TQC" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "ARS/cartpole", experimentHash: "product-row-ARS.cartpole", e2eTest: "e2e.product.ARS.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:800000:environment-steps:seedless", command: [ "rl", "train", "experiments/cartpole.dhall", "--algorithm", "ARS" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "ARS/mountain-car", experimentHash: "product-row-ARS.mountain-car", e2eTest: "e2e.product.ARS.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:320000:environment-steps:seedless", command: [ "rl", "train", "experiments/mountain-car.dhall", "--algorithm", "ARS" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "ARS/lunar-lander", experimentHash: "product-row-ARS.lunar-lander", e2eTest: "e2e.product.ARS.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1600000:environment-steps:seedless", command: [ "rl", "train", "experiments/lunar-lander.dhall", "--algorithm", "ARS" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "ARS/key-door-grid", experimentHash: "product-row-ARS.key-door-grid", e2eTest: "e2e.product.ARS.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:320000:environment-steps:seedless", command: [ "rl", "train", "experiments/key-door-grid.dhall", "--algorithm", "ARS" ], requiresTrainedArtifact: true }
  , { kind: "her", name: "HER/goal-reaching", experimentHash: "product-row-HER.goal-reaching", e2eTest: "e2e.product.HER.goal-reaching", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2004:environment-steps:seedless", command: [ "rl", "train", "experiments/goal-reaching.dhall", "--algorithm", "HER" ], requiresTrainedArtifact: true }
  , { kind: "alphazero", name: "connect4", experimentHash: "product-row-connect4", e2eTest: "e2e.product.connect4", demoPanel: "connect4-human-vs-alphazero", budget: "alphazero-self-play-generations:64:self-play-generations:seedless", command: [ "rl", "alphazero", "self-play", "--game", "connect4", "--sims", "128" ], requiresTrainedArtifact: true }
  , { kind: "alphazero", name: "othello", experimentHash: "product-row-othello", e2eTest: "e2e.product.othello", demoPanel: "connect4-human-vs-alphazero", budget: "alphazero-self-play-generations:96:self-play-generations:seedless", command: [ "rl", "alphazero", "self-play", "--game", "othello", "--sims", "192" ], requiresTrainedArtifact: true }
  , { kind: "alphazero", name: "hex", experimentHash: "product-row-hex", e2eTest: "e2e.product.hex", demoPanel: "connect4-human-vs-alphazero", budget: "alphazero-self-play-generations:128:self-play-generations:seedless", command: [ "rl", "alphazero", "self-play", "--game", "hex", "--sims", "256" ], requiresTrainedArtifact: true }
  , { kind: "alphazero", name: "gomoku", experimentHash: "product-row-gomoku", e2eTest: "e2e.product.gomoku", demoPanel: "connect4-human-vs-alphazero", budget: "alphazero-self-play-generations:128:self-play-generations:seedless", command: [ "rl", "alphazero", "self-play", "--game", "gomoku", "--sims", "256" ], requiresTrainedArtifact: true }
  , { kind: "tuning", name: "hyperparameter-tuning", experimentHash: "product-row-hyperparameter-tuning", e2eTest: "e2e.product.hyperparameter-tuning", demoPanel: "hyperparameter-sweep", budget: "tuning-trials:128:trials:seed-1729", command: [ "tune", "experiments/mnist-tune.dhall" ], requiresTrainedArtifact: true }
  ]

-- Sprint 14.1 (Feature B) — a persisted adversarial-game transcript replayed
-- from the `jitml-transcripts` bucket (read back in the daemon).
type TranscriptReplay =
  { kind :: String
  , game :: String
  , experimentHash :: String
  , moves :: Array Int
  , analysis :: String
  }

renderStartTrainingCommand :: String -> String -> Int -> Int -> Int -> String
renderStartTrainingCommand experimentHash dhallObjectKey seed epochs batchSize =
  String.joinWith "\n"
    [ "kind: StartTraining"
    , "experiment-hash: " <> experimentHash
    , "dhall-object-key: " <> dhallObjectKey
    , "substrate: live"
    , "seed: " <> show seed
    , "epochs: " <> show epochs
    , "batch-size: " <> show batchSize
    , "plan-id: browser-unresolved"
    , "resolved-plan: browser-unresolved"
    , "training-examples: 2000"
    , "evaluation-examples: 1000"
    , ""
    ]

renderStopTrainingCommand :: String -> Boolean -> String
renderStopTrainingCommand experimentHash drain =
  String.joinWith "\n"
    [ "kind: StopTraining"
    , "experiment-hash: " <> experimentHash
    , "drain: " <> renderBoolFlag drain
    , ""
    ]

renderStartRlCommand :: String -> String -> String -> Int -> Int -> Int -> String
renderStartRlCommand experimentHash algorithm environment seed maxSteps evalEpisodes =
  String.joinWith "\n"
    [ "kind: StartRLRun"
    , "experiment-hash: " <> experimentHash
    , "algorithm: " <> algorithm
    , "environment: " <> environment
    , "substrate: live"
    , "seed: " <> show seed
    , "max-steps: " <> show maxSteps
    , "eval-episodes: " <> show evalEpisodes
    , ""
    ]

renderStopRlCommand :: String -> Boolean -> String
renderStopRlCommand experimentHash drain =
  String.joinWith "\n"
    [ "kind: StopRLRun"
    , "experiment-hash: " <> experimentHash
    , "drain: " <> renderBoolFlag drain
    , ""
    ]

renderStartTuneCommand :: String -> String -> Int -> TunePlanBudget -> String -> String -> String -> String
renderStartTuneCommand experimentHash dhallObjectKey sweepSeed budget sampler scheduler pruner =
  String.joinWith "\n"
    [ "kind: StartSweep"
    , "experiment-hash: " <> experimentHash
    , "dhall-object-key: " <> dhallObjectKey
    , "substrate: live"
    , "sweep-seed: " <> show sweepSeed
    , "trial-budget: " <> show budget.trials
    , "budget-per-trial: " <> show budget.optimizerUpdatesPerTrial
    , "sampler: " <> sampler
    , "scheduler: " <> scheduler
    , "pruner: " <> pruner
    , "parallelism: " <> show budget.parallelism
    , "promotions: " <> show budget.promotions
    , "plan-id: browser-unresolved"
    , "resolved-plan: browser-unresolved"
    , ""
    ]

renderStopTuneCommand :: String -> String
renderStopTuneCommand experimentHash =
  String.joinWith "\n"
    [ "kind: StopSweep"
    , "experiment-hash: " <> experimentHash
    , ""
    ]

renderBrowserInferenceRequest :: String -> String -> String -> Array Number -> String
renderBrowserInferenceRequest panel modelId experimentHash input =
  String.joinWith "\n"
    [ "kind: BrowserInferenceRequest"
    , "panel: " <> panel
    , "model-id: " <> modelId
    , "experiment-hash: " <> experimentHash
    , "input: " <> renderNumberList input
    , ""
    ]

renderBrowserImageRequest :: String -> String -> String -> String -> Array Number -> String
renderBrowserImageRequest panel datasetName experimentHash imageBase64 input =
  String.joinWith "\n"
    [ "kind: BrowserImageRequest"
    , "panel: " <> panel
    , "dataset: " <> datasetName
    , "experiment-hash: " <> experimentHash
    , "image-base64: " <> imageBase64
    , "input: " <> renderNumberList input
    , ""
    ]

renderBrowserGenericInferenceRequest :: String -> String -> Array Number -> String
renderBrowserGenericInferenceRequest panel experimentHash input =
  String.joinWith "\n"
    [ "kind: BrowserGenericInferenceRequest"
    , "panel: " <> panel
    , "experiment-hash: " <> experimentHash
    , "input: " <> renderNumberList input
    , ""
    ]

renderBrowserCheckpointCompareRequest :: String -> String -> String -> Array Number -> String
renderBrowserCheckpointCompareRequest panel baselineExperimentHash candidateExperimentHash input =
  String.joinWith "\n"
    [ "kind: BrowserCheckpointCompareRequest"
    , "panel: " <> panel
    , "baseline-experiment-hash: " <> baselineExperimentHash
    , "candidate-experiment-hash: " <> candidateExperimentHash
    , "input: " <> renderNumberList input
    , ""
    ]

renderBrowserAdversarialMoveRequest :: String -> String -> String -> Array Int -> Int -> Int -> String
renderBrowserAdversarialMoveRequest panel game experimentHash moves humanIsPlayer simulationsPerMove =
  String.joinWith "\n"
    [ "kind: BrowserAdversarialMoveRequest"
    , "panel: " <> panel
    , "game: " <> game
    , "experiment-hash: " <> experimentHash
    , "moves: " <> renderIntList moves
    , "human-is-player: " <> show humanIsPlayer
    , "simulations-per-move: " <> show simulationsPerMove
    , ""
    ]

renderInferenceResult :: String -> String -> String -> Int -> Number -> Number -> Array Number -> Array Number -> String -> InferenceResult
renderInferenceResult panel modelId checkpointSha topClass confidence latencyMs probabilities output status =
  { panel
  , modelId
  , checkpointSha
  , topClass
  , confidence
  , latencyMs
  , probabilities
  , output
  , status
  }

renderImageInferenceResult :: String -> String -> String -> Array Int -> Array Number -> Number -> Number -> String -> ImageInferenceResult
renderImageInferenceResult panel datasetName checkpointSha topK probabilities preprocessingMs inferenceMs status =
  { panel
  , datasetName
  , checkpointSha
  , topK
  , probabilities
  , preprocessingMs
  , inferenceMs
  , status
  }

renderGenericInferenceResult :: String -> String -> String -> Number -> Array Number -> String -> GenericInferenceResult
renderGenericInferenceResult panel experimentHash checkpointSha latencyMs output status =
  { panel
  , experimentHash
  , checkpointSha
  , latencyMs
  , output
  , status
  }

renderCheckpointCompareResult :: String -> String -> String -> Array Number -> Array Number -> Number -> Number -> Number -> String -> CheckpointCompareResult
renderCheckpointCompareResult panel baselineCheckpointSha candidateCheckpointSha baselineOutput candidateOutput maxAbsDelta meanAbsDelta latencyMs status =
  { panel
  , baselineCheckpointSha
  , candidateCheckpointSha
  , baselineOutput
  , candidateOutput
  , maxAbsDelta
  , meanAbsDelta
  , latencyMs
  , status
  }

renderAdversarialMoveResult :: String -> String -> Int -> Array Int -> Array Int -> Array Number -> Number -> Boolean -> String -> AdversarialMoveResult
renderAdversarialMoveResult panel game chosenColumn legalMoves visitCounts policyPriors valueEstimate gameOver transcriptId =
  { panel
  , game
  , chosenColumn
  , legalMoves
  , visitCounts
  , policyPriors
  , valueEstimate
  , gameOver
  , transcriptId
  }

renderTrainingEventFrame :: String -> Int -> Int -> Number -> Number -> Number -> String -> String -> String -> String -> TrainingEventFrame
renderTrainingEventFrame experimentHash epoch step trainingLoss validationLoss throughput device checkpointSha tensorboardUrl timestampNs =
  { panel: "training-progress"
  , experimentHash
  , epoch
  , step
  , trainingLoss
  , validationLoss
  , throughput
  , device
  , checkpointSha
  , tensorboardUrl
  , timestampNs
  }

renderRlAnimationFrame :: String -> String -> Int -> Int -> Number -> Boolean -> Int -> Array Number -> Array Number -> String -> String -> String -> RlAnimationFrame
renderRlAnimationFrame experimentHash environment episodeIndex stepIndex reward done action observation actionProbabilities observationHash replayCursor timestampNs =
  { panel: "rl-trajectory"
  , experimentHash
  , environment
  , episodeIndex
  , stepIndex
  , reward
  , done
  , action
  , observation
  , actionProbabilities
  , observationHash
  , replayCursor
  , timestampNs
  }

renderRlReplayFrame :: String -> String -> String -> Int -> Int -> Int -> Number -> Boolean -> Array Number -> Array Number -> String -> String -> String -> RlReplayFrame
renderRlReplayFrame experimentHash replayId environment episodeIndex stepIndex action reward done observation nextObservation policyVersion observationHash timestampNs =
  { panel: "rl-trajectory"
  , experimentHash
  , replayId
  , environment
  , episodeIndex
  , stepIndex
  , action
  , reward
  , done
  , observation
  , nextObservation
  , policyVersion
  , observationHash
  , timestampNs
  }

renderTuneTrialFrame :: String -> Int -> Int -> Number -> Boolean -> String -> String -> String -> String -> String -> TuneTrialFrame
renderTuneTrialFrame sweepId trialIndex trialSeed objective pruned sampler scheduler pruner parametersJson checkpointSha =
  { panel: "hyperparameter-sweep"
  , sweepId
  , trialIndex
  , trialSeed
  , objective
  , pruned
  , sampler
  , scheduler
  , pruner
  , parametersJson
  , checkpointSha
  }

renderTuneSweepDoneFrame :: String -> Int -> Int -> Number -> String -> TuneSweepDoneFrame
renderTuneSweepDoneFrame sweepId trialsCompleted trialsPruned bestObjective promotedCheckpointSha =
  { panel: "hyperparameter-sweep"
  , sweepId
  , trialsCompleted
  , trialsPruned
  , bestObjective
  , promotedCheckpointSha
  }

renderWorkflowCommandAck :: String -> String -> String -> WorkflowCommandAck
renderWorkflowCommandAck runId command status =
  { runId, command, status }

renderWorkflowStatus :: String -> String -> String -> String -> WorkflowStatus
renderWorkflowStatus panel runId status detail =
  { panel, runId, status, detail }

parseWorkflowCommandAck :: String -> Maybe WorkflowCommandAck
parseWorkflowCommandAck payload
  | fieldValue "kind" payload == Just "WorkflowCommandAck" =
      renderWorkflowCommandAck
        <$> fieldValue "run-id" payload
        <*> fieldValue "command" payload
        <*> fieldValue "status" payload
  | otherwise = Nothing

parseWorkflowStatus :: String -> Maybe WorkflowStatus
parseWorkflowStatus payload
  | fieldValue "kind" payload == Just "WorkflowStatus" =
      renderWorkflowStatus
        <$> fieldValue "panel" payload
        <*> fieldValue "run-id" payload
        <*> fieldValue "status" payload
        <*> fieldValue "detail" payload
  | otherwise = Nothing

parseInferenceResult :: String -> Maybe InferenceResult
parseInferenceResult payload
  | fieldValue "kind" payload == Just "InferenceResult" =
      renderInferenceResult
        <$> fieldValue "panel" payload
        <*> fieldValue "model-id" payload
        <*> fieldValue "checkpoint-sha" payload
        <*> intField "top-class" payload
        <*> numberField "confidence" payload
        <*> numberField "latency-ms" payload
        <*> numberListField "probabilities" payload
        <*> numberListField "output" payload
        <*> fieldValue "status" payload
  | otherwise = Nothing

parseDecodedInference :: String -> Maybe DecodedInference
parseDecodedInference payload =
  case fieldValue "decoded-kind" payload of
    Nothing -> Nothing
    Just decodedKind -> Just
      { kind: decodedKind
      , topClass: fromMaybe 0 (intField "decoded-top-class" payload)
      , confidence: fromMaybe 0.0 (numberField "decoded-confidence" payload)
      , probabilities: fromMaybe [] (numberListField "decoded-probabilities" payload)
      , labels: fromMaybe [] (stringListField "decoded-labels" payload)
      , values: fromMaybe [] (numberListField "decoded-values" payload)
      , value: fromMaybe 0.0 (numberField "decoded-value" payload)
      , output: fromMaybe [] (numberListField "decoded-output" payload)
      }

parseCompareFrame :: String -> Maybe CompareFrame
parseCompareFrame payload
  | fieldValue "kind" payload == Just "CheckpointCompareResult" =
      (\baselineExperimentHash candidateExperimentHash baselineOutput candidateOutput maxAbsDelta meanAbsDelta -> { baselineExperimentHash, candidateExperimentHash, baselineOutput, candidateOutput, maxAbsDelta, meanAbsDelta })
        <$> fieldValue "baseline-experiment-hash" payload
        <*> fieldValue "candidate-experiment-hash" payload
        <*> numberListField "baseline-output" payload
        <*> numberListField "candidate-output" payload
        <*> numberField "max-abs-delta" payload
        <*> numberField "mean-abs-delta" payload
  | otherwise = Nothing

parseMoveFrame :: String -> Maybe MoveFrame
parseMoveFrame payload
  | fieldValue "kind" payload == Just "AdversarialMoveResult" =
      (\experimentHash game chosenColumn legalMoves visitCounts policyPriors valueEstimate gameOver transcriptId -> { experimentHash, game, chosenColumn, legalMoves, visitCounts, policyPriors, valueEstimate, gameOver, transcriptId })
        <$> fieldValue "experiment-hash" payload
        <*> fieldValue "game" payload
        <*> intField "chosen-column" payload
        <*> intListField "legal-moves" payload
        <*> intListField "visit-counts" payload
        <*> numberListField "policy-priors" payload
        <*> numberField "value-estimate" payload
        <*> Just (fieldValue "game-over" payload == Just "true")
        <*> fieldValue "transcript-id" payload
  | otherwise = Nothing

parseCheckpointList :: String -> Maybe CheckpointList
parseCheckpointList payload
  | fieldValue "kind" payload == Just "CheckpointList" =
      Just
        { kind: "CheckpointList"
        , panel: fromMaybe "checkpoint-browse" (fieldValue "panel" payload)
        , selectorState: fromMaybe "ready" (fieldValue "selector-state" payload)
        , rowSelectors: Array.mapMaybe parseProductRowSelector (fieldValues "row-selector" payload)
        , checkpoints: Array.mapMaybe parseCheckpointSummary (fieldValues "checkpoint-summary" payload)
        }
  | otherwise = Nothing

parseProductRowSelector :: String -> Maybe ProductRowSelector
parseProductRowSelector raw =
  case String.split (Pattern "\t") raw of
    [ rowId, experimentHash, family, selectorState, checkpointCountRaw, demoPanel ] ->
      (\checkpointCount -> { rowId, experimentHash, family, selectorState, checkpointCount, demoPanel })
        <$> Int.fromString (String.trim checkpointCountRaw)
    _ -> Nothing

parseCheckpointSummary :: String -> Maybe CheckpointSummary
parseCheckpointSummary raw =
  case String.split (Pattern "\t") raw of
    [ rowId, experimentHash, sha, stepRaw, modelFamily, tensorCountRaw, eligibility, completedBudget, convergenceMetrics, tensorboardPrefix ] ->
      (\step tensorCount -> { rowId, experimentHash, sha, step, modelFamily, tensorCount, eligibility, completedBudget, convergenceMetrics, tensorboardPrefix })
        <$> Int.fromString (String.trim stepRaw)
        <*> Int.fromString (String.trim tensorCountRaw)
    _ -> Nothing

parseTranscriptReplay :: String -> Maybe TranscriptReplay
parseTranscriptReplay payload
  | fieldValue "kind" payload == Just "TranscriptReplay" =
      (\game experimentHash moves analysis -> { kind: "TranscriptReplay", game, experimentHash, moves, analysis })
        <$> fieldValue "game" payload
        <*> fieldValue "experiment-hash" payload
        <*> intListField "moves" payload
        <*> Just (fromMaybe "" (fieldValue "analysis" payload))
  | otherwise = Nothing

parseImageInferenceResult :: String -> Maybe ImageInferenceResult
parseImageInferenceResult payload
  | fieldValue "kind" payload == Just "ImageInferenceResult" =
      renderImageInferenceResult
        <$> fieldValue "panel" payload
        <*> fieldValue "dataset" payload
        <*> fieldValue "checkpoint-sha" payload
        <*> intListField "top-k" payload
        <*> numberListField "probabilities" payload
        <*> numberField "preprocessing-ms" payload
        <*> numberField "inference-ms" payload
        <*> fieldValue "status" payload
  | otherwise = Nothing

parseGenericInferenceResult :: String -> Maybe GenericInferenceResult
parseGenericInferenceResult payload
  | fieldValue "kind" payload == Just "GenericInferenceResult" =
      renderGenericInferenceResult
        <$> fieldValue "panel" payload
        <*> fieldValue "experiment-hash" payload
        <*> fieldValue "checkpoint-sha" payload
        <*> numberField "latency-ms" payload
        <*> numberListField "output" payload
        <*> fieldValue "status" payload
  | otherwise = Nothing

parseCheckpointCompareResult :: String -> Maybe CheckpointCompareResult
parseCheckpointCompareResult payload
  | fieldValue "kind" payload == Just "CheckpointCompareResult" =
      renderCheckpointCompareResult
        <$> fieldValue "panel" payload
        <*> fieldValue "baseline-checkpoint-sha" payload
        <*> fieldValue "candidate-checkpoint-sha" payload
        <*> numberListField "baseline-output" payload
        <*> numberListField "candidate-output" payload
        <*> numberField "max-abs-delta" payload
        <*> numberField "mean-abs-delta" payload
        <*> numberField "latency-ms" payload
        <*> fieldValue "status" payload
  | otherwise = Nothing

parseAdversarialMoveResult :: String -> Maybe AdversarialMoveResult
parseAdversarialMoveResult payload
  | fieldValue "kind" payload == Just "AdversarialMoveResult" =
      renderAdversarialMoveResult
        <$> fieldValue "panel" payload
        <*> fieldValue "game" payload
        <*> intField "chosen-column" payload
        <*> intListField "legal-moves" payload
        <*> intListField "visit-counts" payload
        <*> numberListField "policy-priors" payload
        <*> numberField "value-estimate" payload
        <*> boolField "game-over" payload
        <*> fieldValue "transcript-id" payload
  | otherwise = Nothing

parseTrainingEventFrame :: String -> Maybe TrainingEventFrame
parseTrainingEventFrame payload
  | fieldValue "kind" payload == Just "TrainingEventFrame" =
      renderTrainingEventFrame
        <$> fieldValue "experiment-hash" payload
        <*> intField "epoch" payload
        <*> intField "step" payload
        <*> numberField "training-loss" payload
        <*> numberField "validation-loss" payload
        <*> numberField "throughput" payload
        <*> fieldValue "device" payload
        <*> fieldValue "checkpoint-sha" payload
        <*> fieldValue "tensorboard-url" payload
        <*> fieldValue "timestamp-ns" payload
  | otherwise = Nothing

parseRlAnimationFrame :: String -> Maybe RlAnimationFrame
parseRlAnimationFrame payload
  | fieldValue "kind" payload == Just "RlAnimationFrame" =
      renderRlAnimationFrame
        <$> fieldValue "experiment-hash" payload
        <*> fieldValue "environment" payload
        <*> intField "episode" payload
        <*> intField "step" payload
        <*> numberField "reward" payload
        <*> boolField "done" payload
        <*> intField "action" payload
        <*> numberListField "observation" payload
        <*> numberListField "action-probabilities" payload
        <*> fieldValue "observation-hash" payload
        <*> fieldValue "replay-cursor" payload
        <*> fieldValue "timestamp-ns" payload
  | otherwise = Nothing

parseRlReplayFrame :: String -> Maybe RlReplayFrame
parseRlReplayFrame payload
  | fieldValue "kind" payload == Just "RlReplayFrame" =
      renderRlReplayFrame
        <$> fieldValue "experiment-hash" payload
        <*> fieldValue "replay-id" payload
        <*> fieldValue "environment" payload
        <*> intField "episode" payload
        <*> intField "step" payload
        <*> intField "action" payload
        <*> numberField "reward" payload
        <*> boolField "done" payload
        <*> numberListField "observation" payload
        <*> numberListField "next-observation" payload
        <*> fieldValue "policy-version" payload
        <*> fieldValue "observation-hash" payload
        <*> fieldValue "timestamp-ns" payload
  | otherwise = Nothing

parseTuneTrialFrame :: String -> Maybe TuneTrialFrame
parseTuneTrialFrame payload
  | fieldValue "kind" payload == Just "TuneTrialFrame" =
      renderTuneTrialFrame
        <$> fieldValue "sweep-id" payload
        <*> intField "trial-index" payload
        <*> intField "trial-seed" payload
        <*> numberField "objective" payload
        <*> boolField "pruned" payload
        <*> fieldValue "sampler" payload
        <*> fieldValue "scheduler" payload
        <*> fieldValue "pruner" payload
        <*> fieldValue "parameters-json" payload
        <*> fieldValue "checkpoint-sha" payload
  | otherwise = Nothing

parseTuneSweepDoneFrame :: String -> Maybe TuneSweepDoneFrame
parseTuneSweepDoneFrame payload
  | fieldValue "kind" payload == Just "TuneSweepDoneFrame" =
      renderTuneSweepDoneFrame
        <$> fieldValue "sweep-id" payload
        <*> intField "trials-completed" payload
        <*> intField "trials-pruned" payload
        <*> numberField "best-objective" payload
        <*> fieldValue "promoted-checkpoint-sha" payload
  | otherwise = Nothing

fieldValue :: String -> String -> Maybe String
fieldValue key payload =
  Array.head (fieldValues key payload)

fieldValues :: String -> String -> Array String
fieldValues key payload =
  Array.mapMaybe
    (String.stripPrefix (Pattern (key <> ": ")) <<< String.trim)
    (String.split (Pattern "\n") payload)

intField :: String -> String -> Maybe Int
intField key payload =
  fieldValue key payload >>= Int.fromString

numberField :: String -> String -> Maybe Number
numberField key payload =
  fieldValue key payload >>= Number.fromString

intListField :: String -> String -> Maybe (Array Int)
intListField key payload =
  case fieldValue key payload of
    Just raw | String.trim raw == "" -> Just []
    Just raw -> traverse (Int.fromString <<< String.trim) (String.split (Pattern ",") raw)
    Nothing -> Nothing

numberListField :: String -> String -> Maybe (Array Number)
numberListField key payload =
  case fieldValue key payload of
    Just raw | String.trim raw == "" -> Just []
    Just raw -> traverse (Number.fromString <<< String.trim) (String.split (Pattern ",") raw)
    Nothing -> Nothing

stringListField :: String -> String -> Maybe (Array String)
stringListField key payload =
  case fieldValue key payload of
    Just raw | String.trim raw == "" -> Just []
    Just raw -> Just (map String.trim (String.split (Pattern ",") raw))
    Nothing -> Nothing

boolField :: String -> String -> Maybe Boolean
boolField key payload =
  case fieldValue key payload of
    Just "True" -> Just true
    Just "False" -> Just false
    Just "true" -> Just true
    Just "false" -> Just false
    _ -> Nothing

renderBoolFlag :: Boolean -> String
renderBoolFlag flag =
  if flag then "True" else "False"

renderIntList :: Array Int -> String
renderIntList values =
  String.joinWith "," (map show values)

renderNumberList :: Array Number -> String
renderNumberList values =
  String.joinWith "," (map show values)

endpoints :: Array Endpoint
endpoints =
  [ { name: "RunCommand", method: "POST", path: "/api/runs/{runId}/command" }
  , { name: "InferenceRun", method: "POST", path: "/api/inference" }
  , { name: "GenericInference", method: "POST", path: "/api/inference/generic" }
  , { name: "UploadImage", method: "POST", path: "/api/images" }
  , { name: "CheckpointCompare", method: "POST", path: "/api/checkpoints/compare" }
  , { name: "Connect4Move", method: "POST", path: "/api/connect4/move" }
  , { name: "MetricsStream", method: "GET", path: "/api/ws" }
  , { name: "TrainingStream", method: "GET", path: "/api/ws/training" }
  , { name: "RlStream", method: "GET", path: "/api/ws/rl" }
  , { name: "TuneStream", method: "GET", path: "/api/ws/tune" }
  , { name: "InferenceStream", method: "GET", path: "/api/ws/inference" }
  , { name: "CheckpointList", method: "POST", path: "/api/checkpoints" }
  , { name: "WorkflowStream", method: "GET", path: "/api/ws/workflow" }
  , { name: "TranscriptReplay", method: "POST", path: "/api/transcripts/replay" }
  ]
