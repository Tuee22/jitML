module Generated.Contracts where

import Prelude

import Data.Array as Array
import Data.Either (Either(..))
import Data.Enum (fromEnum)
import Data.Foldable (all)
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
  { ordinal :: Int
  , rowId :: String
  , planId :: String
  , experimentHash :: String
  , sha :: String
  , step :: Int
  , modelFamily :: String
  , tensorCount :: Int
  , eligibility :: String
  , completedBudget :: String
  , measuredResult :: String
  , tensorboardPrefix :: String
  }

type ProductRowSelector =
  { ordinal :: Int
  , rowId :: String
  , planId :: String
  , experimentHash :: String
  , manifestSha :: String
  , family :: String
  , evidenceStatus :: String
  , evidenceReason :: String
  , demoPanel :: String
  }

-- The Engine-listed product-row checkpoint catalogue, including per-row
-- selector state and inference-eligible manifests listed from MinIO.
type CheckpointList =
  { kind :: String
  , callId :: String
  , panel :: String
  , publicationStatus :: String
  , runId :: String
  , substrate :: String
  , catalogueSha256 :: String
  , sourceJournalSha256 :: String
  , count :: Int
  , selectorState :: String
  , rowSelectors :: Array ProductRowSelector
  , checkpoints :: Array CheckpointSummary
  }

-- Phase 262 — browser-visible product matrix, generated through
-- `JitML.Test.WorkflowMatrix.modelCellMatrix` from
-- `JitML.Product.Matrix.allProductRows` so the PureScript app,
-- and Haskell tests consume one substrate-specific product registry.
type ModelMatrixRow =
  { kind :: String
  , name :: String
  , planId :: String
  , substrate :: String
  , experimentHash :: String
  , e2eTest :: String
  , demoPanel :: String
  , budget :: String
  , command :: Array String
  , requiresTrainedArtifact :: Boolean
  }

allModelMatrixRows :: Array ModelMatrixRow
allModelMatrixRows = allModelMatrixRowsForSubstrate "linux-cpu"

allModelMatrixRowsForSubstrate :: String -> Array ModelMatrixRow
allModelMatrixRowsForSubstrate substrate =
  Array.filter (\row -> row.substrate == substrate) allSubstrateModelMatrixRows

allSubstrateModelMatrixRows :: Array ModelMatrixRow
allSubstrateModelMatrixRows =
  [ { kind: "supervised", name: "mnist-shallow-mlp", planId: "6d97fd41fec883305f3f3812892145e17dc364d0c84d6a0e2ba9e5afc335e637", substrate: "apple-silicon", experimentHash: "product-row-mnist-shallow-mlp", e2eTest: "e2e.product.mnist-shallow-mlp", demoPanel: "mnist-live-inference", budget: "supervised-epochs:10:epochs:seed-1001", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "mnist-shallow-mlp" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "mnist-deep-mlp", planId: "7fe017408c0aa0ebb6f131637a2cc98817e11999933c6ef44869c3bab8de886e", substrate: "apple-silicon", experimentHash: "product-row-mnist-deep-mlp", e2eTest: "e2e.product.mnist-deep-mlp", demoPanel: "mnist-live-inference", budget: "supervised-epochs:10:epochs:seed-1002", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "mnist-deep-mlp" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "mnist-lenet", planId: "ca52acc9ca7ff273fa747a46891fa48d82ffa292fd7add8eaa330c402a5c2b21", substrate: "apple-silicon", experimentHash: "product-row-mnist-lenet", e2eTest: "e2e.product.mnist-lenet", demoPanel: "mnist-live-inference", budget: "supervised-epochs:10:epochs:seed-1003", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "mnist-lenet" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "fashion-mnist-mlp", planId: "b9c08fe4f4bfd389a7fa0f081e4c8bd93eb0130520f5678e0c1f673f7b0cc01a", substrate: "apple-silicon", experimentHash: "product-row-fashion-mnist-mlp", e2eTest: "e2e.product.fashion-mnist-mlp", demoPanel: "mnist-live-inference", budget: "supervised-epochs:10:epochs:seed-1004", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "fashion-mnist-mlp" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "fashion-mnist-resnet", planId: "65661b845559f46c0c6e431aacc9a3374f68c81ad4474e861e9fc5d1a4c7d824", substrate: "apple-silicon", experimentHash: "product-row-fashion-mnist-resnet", e2eTest: "e2e.product.fashion-mnist-resnet", demoPanel: "mnist-live-inference", budget: "supervised-epochs:10:epochs:seed-1005", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "fashion-mnist-resnet" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "cifar10-resnet20", planId: "88d3fc715fefd50f7d28d71fede4a9ed5fcc7ca748b84150ea6ecde1cd3430d4", substrate: "apple-silicon", experimentHash: "product-row-cifar10-resnet20", e2eTest: "e2e.product.cifar10-resnet20", demoPanel: "cifar-imagenet-upload", budget: "supervised-epochs:40:epochs:seed-1006", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "cifar10-resnet20" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "cifar10-resnet56", planId: "78882c769ad09884d754d6f5446abb37c97ceecf576cd35db0e8d1a734c9ffad", substrate: "apple-silicon", experimentHash: "product-row-cifar10-resnet56", e2eTest: "e2e.product.cifar10-resnet56", demoPanel: "cifar-imagenet-upload", budget: "supervised-epochs:40:epochs:seed-1007", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "cifar10-resnet56" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "cifar100-wide-resnet", planId: "ce7c011cd28aed5067fbc93371241cb6d949a2c1fb90b1f07ce98756954079fa", substrate: "apple-silicon", experimentHash: "product-row-cifar100-wide-resnet", e2eTest: "e2e.product.cifar100-wide-resnet", demoPanel: "cifar-imagenet-upload", budget: "supervised-epochs:10:epochs:seed-1008", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "cifar100-wide-resnet" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "cifar10-vit", planId: "2087d747538063482a541aef0c44ae0f3a249f159f1604bb2cd33b785b3d9c8e", substrate: "apple-silicon", experimentHash: "product-row-cifar10-vit", e2eTest: "e2e.product.cifar10-vit", demoPanel: "cifar-imagenet-upload", budget: "supervised-epochs:40:epochs:seed-1009", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "cifar10-vit" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "tiny-imagenet-resnet50", planId: "50f927bb83458c08b62d6aaac44797e34dd36ba94bf09beb3822f8c08f7c4949", substrate: "apple-silicon", experimentHash: "product-row-tiny-imagenet-resnet50", e2eTest: "e2e.product.tiny-imagenet-resnet50", demoPanel: "cifar-imagenet-upload", budget: "supervised-epochs:15:epochs:seed-1010", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "tiny-imagenet-resnet50" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "california-housing-mlp", planId: "64bb8c654db05e9b2115d8b3c7200e1de35024bb8fc4b763ad31b266d80d0774", substrate: "apple-silicon", experimentHash: "product-row-california-housing-mlp", e2eTest: "e2e.product.california-housing-mlp", demoPanel: "generic-inference-lab", budget: "supervised-epochs:10:epochs:seed-1011", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "california-housing-mlp" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/cartpole", planId: "bb0c9e378027e3884f5ba4f22d9ee5232147e28eccb8721789739e81486efb52", substrate: "apple-silicon", experimentHash: "product-row-PPO.cartpole", e2eTest: "e2e.product.PPO.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "PPO/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/mountain-car", planId: "eb00656fd30199aea9669d2eb3d9d9bafcf825b398eb210c86ce646cf81f6652", substrate: "apple-silicon", experimentHash: "product-row-PPO.mountain-car", e2eTest: "e2e.product.PPO.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "PPO/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/acrobot", planId: "ceb456f2079c5c4149a3d49b3c782010ddbc2289ac294a242fad5966792089a7", substrate: "apple-silicon", experimentHash: "product-row-PPO.acrobot", e2eTest: "e2e.product.PPO.acrobot", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "PPO/acrobot" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/lunar-lander", planId: "372b0a428cb47b87b21424a5886a3838be78c57db0263b55e8196502dd89a5d2", substrate: "apple-silicon", experimentHash: "product-row-PPO.lunar-lander", e2eTest: "e2e.product.PPO.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2400000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "PPO/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/key-door-grid", planId: "d672dd1f583df04c413b37dd8c3ace9f22eda5d7b3a0f0c10bc6db930795231e", substrate: "apple-silicon", experimentHash: "product-row-PPO.key-door-grid", e2eTest: "e2e.product.PPO.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "PPO/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/gridworld-deterministic", planId: "86bf5c8171d3626099c3fb383a99d1d5431bf2fb9b97926e6c89a9e430b4f508", substrate: "apple-silicon", experimentHash: "product-row-PPO.gridworld-deterministic", e2eTest: "e2e.product.PPO.gridworld-deterministic", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "PPO/gridworld-deterministic" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "A2C/cartpole", planId: "3133afe2a4639e60777bedd9ca5aed64df10d22d84e24b14a2ae3da4771145c5", substrate: "apple-silicon", experimentHash: "product-row-A2C.cartpole", e2eTest: "e2e.product.A2C.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "A2C/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "A2C/mountain-car", planId: "e147eee79d9872bae23c66cf6dd6c3d11ec8fc6d62a0557002afc1e348a62625", substrate: "apple-silicon", experimentHash: "product-row-A2C.mountain-car", e2eTest: "e2e.product.A2C.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "A2C/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "A2C/lunar-lander", planId: "764273758fc6de59d378bb328260fad9d5100db473f3bc75b6550b5d19e63906", substrate: "apple-silicon", experimentHash: "product-row-A2C.lunar-lander", e2eTest: "e2e.product.A2C.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2400000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "A2C/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "A2C/key-door-grid", planId: "3aaa1d9a17309e5ce444a85739b61d065435c1afa21721b848ef2b34b9f39ffc", substrate: "apple-silicon", experimentHash: "product-row-A2C.key-door-grid", e2eTest: "e2e.product.A2C.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "A2C/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TRPO/cartpole", planId: "3c4c66e7fe68d5a88f7783039538dd0315467829fc6a9330dc6174ff9c626dea", substrate: "apple-silicon", experimentHash: "product-row-TRPO.cartpole", e2eTest: "e2e.product.TRPO.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "TRPO/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TRPO/mountain-car", planId: "ee8bb438b0d1809f0586ddaaefbb1ed059992eeb61970a2f0ad7aa8b39f106c7", substrate: "apple-silicon", experimentHash: "product-row-TRPO.mountain-car", e2eTest: "e2e.product.TRPO.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "TRPO/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TRPO/lunar-lander", planId: "e597a0f6825eef498138bf25128ab03f89a53d355f4d0942c006cf2e15ca3aab", substrate: "apple-silicon", experimentHash: "product-row-TRPO.lunar-lander", e2eTest: "e2e.product.TRPO.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2400000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "TRPO/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TRPO/key-door-grid", planId: "6ca09fa78a77c7f61a07d90690acd295f374e0a3dadf11c21a90b5feb25a0ba4", substrate: "apple-silicon", experimentHash: "product-row-TRPO.key-door-grid", e2eTest: "e2e.product.TRPO.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "TRPO/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "MaskablePPO/cartpole", planId: "b43fc7da76d55d2f990fee76e9d7e5b13519c2642b54355727ef6bf9d7a46a8c", substrate: "apple-silicon", experimentHash: "product-row-MaskablePPO.cartpole", e2eTest: "e2e.product.MaskablePPO.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "MaskablePPO/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "MaskablePPO/mountain-car", planId: "d9841d3f5b738efa0b4c38b3e0d389b99fd9ed0327600ed9913bc2abea26e9d2", substrate: "apple-silicon", experimentHash: "product-row-MaskablePPO.mountain-car", e2eTest: "e2e.product.MaskablePPO.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "MaskablePPO/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "MaskablePPO/lunar-lander", planId: "dcd35320f31056171477e5f8e764f07933108d7cdf64ecc85ebcfeeb1bbe5d2e", substrate: "apple-silicon", experimentHash: "product-row-MaskablePPO.lunar-lander", e2eTest: "e2e.product.MaskablePPO.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2400000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "MaskablePPO/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "MaskablePPO/key-door-grid", planId: "0b70bb8c29a93d6281235e8be349b8e9b9a0f0b3a6d3b52a923d36489176e64b", substrate: "apple-silicon", experimentHash: "product-row-MaskablePPO.key-door-grid", e2eTest: "e2e.product.MaskablePPO.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "MaskablePPO/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "RecurrentPPO/cartpole", planId: "306f92f7fc46326e973fe8b1d4ff173ead36fac821a11fd7f005fb8569564706", substrate: "apple-silicon", experimentHash: "product-row-RecurrentPPO.cartpole", e2eTest: "e2e.product.RecurrentPPO.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "RecurrentPPO/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "RecurrentPPO/mountain-car", planId: "b9eb81f61cf6c77d70dd3eafe95bbb859b44df2bb959f938c3cfcb229fb94241", substrate: "apple-silicon", experimentHash: "product-row-RecurrentPPO.mountain-car", e2eTest: "e2e.product.RecurrentPPO.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "RecurrentPPO/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "RecurrentPPO/lunar-lander", planId: "c3f9cee851c40e4dcbc40b8b21b5592e929ed4c11e8473b8c8ca2644a9e1f550", substrate: "apple-silicon", experimentHash: "product-row-RecurrentPPO.lunar-lander", e2eTest: "e2e.product.RecurrentPPO.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2400000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "RecurrentPPO/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "RecurrentPPO/key-door-grid", planId: "49e1107bfdcc5a78622d2dea8d9eb202e44c50e6515668f0fd63f9487a256d40", substrate: "apple-silicon", experimentHash: "product-row-RecurrentPPO.key-door-grid", e2eTest: "e2e.product.RecurrentPPO.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:307200:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "RecurrentPPO/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "DQN/cartpole", planId: "ec04a30110e861e3652d8ee212699de50cf6aa659a5b89ed6a565eb78dd49198", substrate: "apple-silicon", experimentHash: "product-row-DQN.cartpole", e2eTest: "e2e.product.DQN.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "DQN/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "DQN/mountain-car", planId: "ae8e690df40351aabc1e459e7aa6c5aaceea49c7f0044403fa4afe49325201e6", substrate: "apple-silicon", experimentHash: "product-row-DQN.mountain-car", e2eTest: "e2e.product.DQN.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:120000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "DQN/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "DQN/key-door-grid", planId: "748de8541c46e6a081f93a0aab1478ee6fc5632bbe1121b1067288421a9d7ef2", substrate: "apple-silicon", experimentHash: "product-row-DQN.key-door-grid", e2eTest: "e2e.product.DQN.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "DQN/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "QR-DQN/cartpole", planId: "28065782db3bdf625378c1130193feb04fa5c44626514240cb023731de2ae4fc", substrate: "apple-silicon", experimentHash: "product-row-QR-DQN.cartpole", e2eTest: "e2e.product.QR-DQN.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "QR-DQN/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "QR-DQN/mountain-car", planId: "352cf79649a73b7d639031c94c9811c621f37edc618d03d7c354e6ac7ab5874b", substrate: "apple-silicon", experimentHash: "product-row-QR-DQN.mountain-car", e2eTest: "e2e.product.QR-DQN.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:120000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "QR-DQN/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "QR-DQN/key-door-grid", planId: "72ebb7fc5adc10221e6db5d9ee61eb149d558b649bf318706206ba85208ccba8", substrate: "apple-silicon", experimentHash: "product-row-QR-DQN.key-door-grid", e2eTest: "e2e.product.QR-DQN.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:120000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "QR-DQN/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "DDPG/lunar-lander", planId: "b7f9e2b5c3fe3028408904a11f8bfb297c34a0fc1b0f430d1dbfe66b385b6f2c", substrate: "apple-silicon", experimentHash: "product-row-DDPG.lunar-lander", e2eTest: "e2e.product.DDPG.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:120000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "DDPG/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TD3/lunar-lander", planId: "58490a08d1db2258ad22aafbd1a257290b28cfea4abab3ff4aa6006e9fcfed62", substrate: "apple-silicon", experimentHash: "product-row-TD3.lunar-lander", e2eTest: "e2e.product.TD3.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "TD3/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "SAC/lunar-lander", planId: "929d83d29807904f3abc359270b2201e7feb50b7b3b391edf1641214c4313fa3", substrate: "apple-silicon", experimentHash: "product-row-SAC.lunar-lander", e2eTest: "e2e.product.SAC.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "SAC/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "SAC/pendulum", planId: "8dbb8f637feff945a09ed00f03115a54e2ee43e6a2543a21c6e550d9b9ea819a", substrate: "apple-silicon", experimentHash: "product-row-SAC.pendulum", e2eTest: "e2e.product.SAC.pendulum", demoPanel: "rl-trajectory", budget: "rl-environment-steps:4000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "SAC/pendulum" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "CrossQ/lunar-lander", planId: "70ee699e0b18e9b99ba163d45fd8bcaf07a07120f4398974b32efe8df96b8daf", substrate: "apple-silicon", experimentHash: "product-row-CrossQ.lunar-lander", e2eTest: "e2e.product.CrossQ.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "CrossQ/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TQC/lunar-lander", planId: "6ae57811d46f7053a5837c96fe69218d5059648a503ffda25b5a7fb6fa4401d8", substrate: "apple-silicon", experimentHash: "product-row-TQC.lunar-lander", e2eTest: "e2e.product.TQC.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "TQC/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "ARS/cartpole", planId: "7eb4d4f2f64025dd4e30f1eeb50d6312b0b3c2a0ae6ce3311c3b382c1219816d", substrate: "apple-silicon", experimentHash: "product-row-ARS.cartpole", e2eTest: "e2e.product.ARS.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:800000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "ARS/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "ARS/mountain-car", planId: "50434967e14c04aa48aabcdad21b6a5ca6b21319810d6c419d442f66f6c09501", substrate: "apple-silicon", experimentHash: "product-row-ARS.mountain-car", e2eTest: "e2e.product.ARS.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:320000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "ARS/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "ARS/lunar-lander", planId: "d954720f048d8acbf18316a3bcbb7193bb5be653a665790565e3bcf6b63c4757", substrate: "apple-silicon", experimentHash: "product-row-ARS.lunar-lander", e2eTest: "e2e.product.ARS.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1600000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "ARS/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "ARS/key-door-grid", planId: "f568446a774cdcd9128dd57026912f7e0aef8b7e9b4863c9fe0d5692bca6099b", substrate: "apple-silicon", experimentHash: "product-row-ARS.key-door-grid", e2eTest: "e2e.product.ARS.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:320000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "ARS/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "her", name: "HER/goal-reaching", planId: "215b603c0a512fa2e4f16308a49ff800529b692e8037d5eb55a733e5ba3844f4", substrate: "apple-silicon", experimentHash: "product-row-HER.goal-reaching", e2eTest: "e2e.product.HER.goal-reaching", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2004:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "HER/goal-reaching" ], requiresTrainedArtifact: true }
  , { kind: "alphazero", name: "connect4", planId: "a966451502b6cb37a06e01d536fed665d9bf4436b63b63a127f43573d59f8e38", substrate: "apple-silicon", experimentHash: "product-row-connect4", e2eTest: "e2e.product.connect4", demoPanel: "connect4-human-vs-alphazero", budget: "alphazero-self-play-generations:64:self-play-generations:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "connect4" ], requiresTrainedArtifact: true }
  , { kind: "alphazero", name: "othello", planId: "9c0aaf5006f30153e932c7b4f765bc111c067592856583850651bf06b62dfa3b", substrate: "apple-silicon", experimentHash: "product-row-othello", e2eTest: "e2e.product.othello", demoPanel: "connect4-human-vs-alphazero", budget: "alphazero-self-play-generations:96:self-play-generations:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "othello" ], requiresTrainedArtifact: true }
  , { kind: "alphazero", name: "hex", planId: "d8c0038c38309e1f531067c08f79e6d481dc124c2ecce2900986d69395e3a380", substrate: "apple-silicon", experimentHash: "product-row-hex", e2eTest: "e2e.product.hex", demoPanel: "connect4-human-vs-alphazero", budget: "alphazero-self-play-generations:128:self-play-generations:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "hex" ], requiresTrainedArtifact: true }
  , { kind: "alphazero", name: "gomoku", planId: "d56f8c1a18f9e80b9160232a773a1ad6b79dc7da67c0fe782b499dccc6883b1b", substrate: "apple-silicon", experimentHash: "product-row-gomoku", e2eTest: "e2e.product.gomoku", demoPanel: "connect4-human-vs-alphazero", budget: "alphazero-self-play-generations:128:self-play-generations:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "gomoku" ], requiresTrainedArtifact: true }
  , { kind: "tuning", name: "hyperparameter-tuning", planId: "5fcef09cdaab17fdfa1fad975f49ecc7f6cbbad8c1b26cc9d40018a51bb9006a", substrate: "apple-silicon", experimentHash: "product-row-hyperparameter-tuning", e2eTest: "e2e.product.hyperparameter-tuning", demoPanel: "hyperparameter-sweep", budget: "tuning-trials:128:trials:seed-1729", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "hyperparameter-tuning" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "mnist-shallow-mlp", planId: "374e1606c3f0accff486b4cfbad37f2c5a28f59fa3572bf3a1d9d3392e4d7661", substrate: "linux-cpu", experimentHash: "product-row-mnist-shallow-mlp", e2eTest: "e2e.product.mnist-shallow-mlp", demoPanel: "mnist-live-inference", budget: "supervised-epochs:10:epochs:seed-1001", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "mnist-shallow-mlp" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "mnist-deep-mlp", planId: "fcec2c1df488136b9aab1234c01eadfa62698e5351442ae65b45e009d2dbfbbc", substrate: "linux-cpu", experimentHash: "product-row-mnist-deep-mlp", e2eTest: "e2e.product.mnist-deep-mlp", demoPanel: "mnist-live-inference", budget: "supervised-epochs:10:epochs:seed-1002", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "mnist-deep-mlp" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "mnist-lenet", planId: "d3d8e69d94c06c9d7875d7997418d359d7a4d6e3e464d4db6b441007a8d2b344", substrate: "linux-cpu", experimentHash: "product-row-mnist-lenet", e2eTest: "e2e.product.mnist-lenet", demoPanel: "mnist-live-inference", budget: "supervised-epochs:10:epochs:seed-1003", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "mnist-lenet" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "fashion-mnist-mlp", planId: "acbccd5ba32612041b9d4601a90c4b32a632917dbf21df468b689880bfcf4449", substrate: "linux-cpu", experimentHash: "product-row-fashion-mnist-mlp", e2eTest: "e2e.product.fashion-mnist-mlp", demoPanel: "mnist-live-inference", budget: "supervised-epochs:10:epochs:seed-1004", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "fashion-mnist-mlp" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "fashion-mnist-resnet", planId: "794e1ac866192daa38107dd392ad67c40b587fbf2c9404dfcf151634cf8b5868", substrate: "linux-cpu", experimentHash: "product-row-fashion-mnist-resnet", e2eTest: "e2e.product.fashion-mnist-resnet", demoPanel: "mnist-live-inference", budget: "supervised-epochs:10:epochs:seed-1005", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "fashion-mnist-resnet" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "cifar10-resnet20", planId: "958b1c5a5720033ef2d5dd7ac7e4ab98471d1240a76085f0022e8a3d898e526e", substrate: "linux-cpu", experimentHash: "product-row-cifar10-resnet20", e2eTest: "e2e.product.cifar10-resnet20", demoPanel: "cifar-imagenet-upload", budget: "supervised-epochs:40:epochs:seed-1006", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "cifar10-resnet20" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "cifar10-resnet56", planId: "31c2eea1f95ee06590ccd2834fd4fadf073a84dde73b5dbbb46458627f0ac98b", substrate: "linux-cpu", experimentHash: "product-row-cifar10-resnet56", e2eTest: "e2e.product.cifar10-resnet56", demoPanel: "cifar-imagenet-upload", budget: "supervised-epochs:40:epochs:seed-1007", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "cifar10-resnet56" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "cifar100-wide-resnet", planId: "d3c21ed43832946492e1af6cea15b4f956eab96f059e1187a51c84d01d822087", substrate: "linux-cpu", experimentHash: "product-row-cifar100-wide-resnet", e2eTest: "e2e.product.cifar100-wide-resnet", demoPanel: "cifar-imagenet-upload", budget: "supervised-epochs:10:epochs:seed-1008", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "cifar100-wide-resnet" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "cifar10-vit", planId: "779db15f67398f3bf09e2a40e208952871e667e0e8e827b42fa4bddb1e4442b9", substrate: "linux-cpu", experimentHash: "product-row-cifar10-vit", e2eTest: "e2e.product.cifar10-vit", demoPanel: "cifar-imagenet-upload", budget: "supervised-epochs:40:epochs:seed-1009", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "cifar10-vit" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "tiny-imagenet-resnet50", planId: "876bc0bdaa7f6f29b6f4f9d3f7c1b34121867c48c9b6218cad062b5397c3d149", substrate: "linux-cpu", experimentHash: "product-row-tiny-imagenet-resnet50", e2eTest: "e2e.product.tiny-imagenet-resnet50", demoPanel: "cifar-imagenet-upload", budget: "supervised-epochs:15:epochs:seed-1010", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "tiny-imagenet-resnet50" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "california-housing-mlp", planId: "c7289b49e0872e80a8e107169c658453bf7714be8d5e22a86ad7382bb327a690", substrate: "linux-cpu", experimentHash: "product-row-california-housing-mlp", e2eTest: "e2e.product.california-housing-mlp", demoPanel: "generic-inference-lab", budget: "supervised-epochs:10:epochs:seed-1011", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "california-housing-mlp" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/cartpole", planId: "56ea69e1cdd088d5fb53c2da6dd144d32c83c0f7d4b5383c6d9af2cadf8cc193", substrate: "linux-cpu", experimentHash: "product-row-PPO.cartpole", e2eTest: "e2e.product.PPO.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "PPO/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/mountain-car", planId: "3f9bcadd9c8618a976ee1662faa69f8138b8c5bc677912e5b3814ab38cb1d0c5", substrate: "linux-cpu", experimentHash: "product-row-PPO.mountain-car", e2eTest: "e2e.product.PPO.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "PPO/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/acrobot", planId: "42731920be15efe01746777f993920029f0ebb7b5afa04faf6aaecef07c3e765", substrate: "linux-cpu", experimentHash: "product-row-PPO.acrobot", e2eTest: "e2e.product.PPO.acrobot", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "PPO/acrobot" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/lunar-lander", planId: "454aab3dfe154f53744b9e8226a6bdd67bcd80c36e6855b354e956932ea47db3", substrate: "linux-cpu", experimentHash: "product-row-PPO.lunar-lander", e2eTest: "e2e.product.PPO.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2400000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "PPO/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/key-door-grid", planId: "261eedd0e38438b3162af56325d06fde2a703683647679035e510d270a2ee72b", substrate: "linux-cpu", experimentHash: "product-row-PPO.key-door-grid", e2eTest: "e2e.product.PPO.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "PPO/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/gridworld-deterministic", planId: "6c4fb4edf1c5683a3c27739167a05ed82263a5ce49a201fa0e707eedc432c917", substrate: "linux-cpu", experimentHash: "product-row-PPO.gridworld-deterministic", e2eTest: "e2e.product.PPO.gridworld-deterministic", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "PPO/gridworld-deterministic" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "A2C/cartpole", planId: "2f42f9f130e4dea8d362e586ccc00859c167bd086057b7a1c032756cd5edbd98", substrate: "linux-cpu", experimentHash: "product-row-A2C.cartpole", e2eTest: "e2e.product.A2C.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "A2C/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "A2C/mountain-car", planId: "c5713b5153856084efeb9130bebc97aadfb2b6a36cae63e9de9c008d109b8f28", substrate: "linux-cpu", experimentHash: "product-row-A2C.mountain-car", e2eTest: "e2e.product.A2C.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "A2C/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "A2C/lunar-lander", planId: "590bc06f39bec901fc6c82c6039c748231f036efba3f5f21aeba6f6513373584", substrate: "linux-cpu", experimentHash: "product-row-A2C.lunar-lander", e2eTest: "e2e.product.A2C.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2400000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "A2C/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "A2C/key-door-grid", planId: "3a2885856500e160b579809db7c1655a10efda9d8f28a87ee875f0ec8afd313e", substrate: "linux-cpu", experimentHash: "product-row-A2C.key-door-grid", e2eTest: "e2e.product.A2C.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "A2C/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TRPO/cartpole", planId: "9ccd86f316e5d29992044162ffebdbdaee4b1da14c020a996ee89240c4bce4e4", substrate: "linux-cpu", experimentHash: "product-row-TRPO.cartpole", e2eTest: "e2e.product.TRPO.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "TRPO/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TRPO/mountain-car", planId: "7f31f17a628610d534bde3893dd10eec7d56c82f15e1553dc40f336640a45d41", substrate: "linux-cpu", experimentHash: "product-row-TRPO.mountain-car", e2eTest: "e2e.product.TRPO.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "TRPO/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TRPO/lunar-lander", planId: "7eeb8c2016539142ebd59a00c4a84df73ca676130e480cf11be1dac4c9637739", substrate: "linux-cpu", experimentHash: "product-row-TRPO.lunar-lander", e2eTest: "e2e.product.TRPO.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2400000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "TRPO/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TRPO/key-door-grid", planId: "e97da8c79998cf6c4a0704b7d070880f56f6392983d8abe0bfc108df989d6a76", substrate: "linux-cpu", experimentHash: "product-row-TRPO.key-door-grid", e2eTest: "e2e.product.TRPO.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "TRPO/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "MaskablePPO/cartpole", planId: "499a7c306eba52a86a2a473ab56600ba965562cf881be6578de0cf6739aa1b42", substrate: "linux-cpu", experimentHash: "product-row-MaskablePPO.cartpole", e2eTest: "e2e.product.MaskablePPO.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "MaskablePPO/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "MaskablePPO/mountain-car", planId: "73706a656782aa06ebc0ac9356d2d3ebb0803fdd351d09751080737658828775", substrate: "linux-cpu", experimentHash: "product-row-MaskablePPO.mountain-car", e2eTest: "e2e.product.MaskablePPO.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "MaskablePPO/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "MaskablePPO/lunar-lander", planId: "d1ddcb8801458f0e43f130187fe9337c92ad847e020dd63ec33208f60e300862", substrate: "linux-cpu", experimentHash: "product-row-MaskablePPO.lunar-lander", e2eTest: "e2e.product.MaskablePPO.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2400000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "MaskablePPO/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "MaskablePPO/key-door-grid", planId: "23df2e6694d40c0416c03822a34093dafca70f84e8200c44172d3c60445cbca5", substrate: "linux-cpu", experimentHash: "product-row-MaskablePPO.key-door-grid", e2eTest: "e2e.product.MaskablePPO.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "MaskablePPO/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "RecurrentPPO/cartpole", planId: "a585780e108fa5f5cae45c3253870854ad07c64334cfb52f4f17ba35e7de8d46", substrate: "linux-cpu", experimentHash: "product-row-RecurrentPPO.cartpole", e2eTest: "e2e.product.RecurrentPPO.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "RecurrentPPO/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "RecurrentPPO/mountain-car", planId: "98c70ee4eef8beb4166831d1207598719df9e40829a55049289499d4a00d5b4e", substrate: "linux-cpu", experimentHash: "product-row-RecurrentPPO.mountain-car", e2eTest: "e2e.product.RecurrentPPO.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "RecurrentPPO/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "RecurrentPPO/lunar-lander", planId: "e1dc9042d4072822dd4d38324d920806e87837ee150e001ca0ab33c7a267d693", substrate: "linux-cpu", experimentHash: "product-row-RecurrentPPO.lunar-lander", e2eTest: "e2e.product.RecurrentPPO.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2400000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "RecurrentPPO/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "RecurrentPPO/key-door-grid", planId: "402b13f33b823480620408abc8fdc7edfcdd20eb8977d7fe642b301d3f19b076", substrate: "linux-cpu", experimentHash: "product-row-RecurrentPPO.key-door-grid", e2eTest: "e2e.product.RecurrentPPO.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:307200:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "RecurrentPPO/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "DQN/cartpole", planId: "e64222984ea6b764c46012195c6d37df2f5db034f1a38ae8760c748542a54c17", substrate: "linux-cpu", experimentHash: "product-row-DQN.cartpole", e2eTest: "e2e.product.DQN.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "DQN/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "DQN/mountain-car", planId: "584adf8d6330d381239a6cfffecc1f7a210461ec55cd46708f730162fc39bee2", substrate: "linux-cpu", experimentHash: "product-row-DQN.mountain-car", e2eTest: "e2e.product.DQN.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:120000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "DQN/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "DQN/key-door-grid", planId: "7f62198b248f10d38cfe410a5ed39814896dfed71824a82e31254eff70145487", substrate: "linux-cpu", experimentHash: "product-row-DQN.key-door-grid", e2eTest: "e2e.product.DQN.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "DQN/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "QR-DQN/cartpole", planId: "532b3d27106f04578176122a4f563ac06c15ec9aa86d50824435e6152b83a695", substrate: "linux-cpu", experimentHash: "product-row-QR-DQN.cartpole", e2eTest: "e2e.product.QR-DQN.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "QR-DQN/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "QR-DQN/mountain-car", planId: "2dc674e7fba6f16270921f37ae704725281969ceceea5d1a01de1ddea4cfb737", substrate: "linux-cpu", experimentHash: "product-row-QR-DQN.mountain-car", e2eTest: "e2e.product.QR-DQN.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:120000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "QR-DQN/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "QR-DQN/key-door-grid", planId: "470b8ae9a333b2dc0f1d79e8abecbe159f2d45e5b126431ce7585c55daf2d4bd", substrate: "linux-cpu", experimentHash: "product-row-QR-DQN.key-door-grid", e2eTest: "e2e.product.QR-DQN.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:120000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "QR-DQN/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "DDPG/lunar-lander", planId: "4f6e9a214fd74d5c0e9270cfcccc6c001efeef6620802c4c2b329d4828221d04", substrate: "linux-cpu", experimentHash: "product-row-DDPG.lunar-lander", e2eTest: "e2e.product.DDPG.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:120000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "DDPG/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TD3/lunar-lander", planId: "839b71e894d97f6594a4d5b013ad908300791125a571a6ebdda38cc3d19aa98d", substrate: "linux-cpu", experimentHash: "product-row-TD3.lunar-lander", e2eTest: "e2e.product.TD3.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "TD3/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "SAC/lunar-lander", planId: "71d6449ec23b4b9960bb0a4db49d6f5149ce0a4f0d74efc01ad7de0891a24be4", substrate: "linux-cpu", experimentHash: "product-row-SAC.lunar-lander", e2eTest: "e2e.product.SAC.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "SAC/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "SAC/pendulum", planId: "c11d0aec7b6d946004f69d311e8323ecccf09ebf7b06eec68d3c2896ffb72768", substrate: "linux-cpu", experimentHash: "product-row-SAC.pendulum", e2eTest: "e2e.product.SAC.pendulum", demoPanel: "rl-trajectory", budget: "rl-environment-steps:4000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "SAC/pendulum" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "CrossQ/lunar-lander", planId: "483148da2d3338e68f96d7338cacd20fbdd84f9d69c0b0e979838650d2402e29", substrate: "linux-cpu", experimentHash: "product-row-CrossQ.lunar-lander", e2eTest: "e2e.product.CrossQ.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "CrossQ/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TQC/lunar-lander", planId: "de04d96439f40fb4fb7c06c5faba4cc2ab8b0180333c78dc920d76951191fe72", substrate: "linux-cpu", experimentHash: "product-row-TQC.lunar-lander", e2eTest: "e2e.product.TQC.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "TQC/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "ARS/cartpole", planId: "1b8b6067991cd505dc839a72a8eb2c2d799fb36904e7ed6efdbce8e54338cfa6", substrate: "linux-cpu", experimentHash: "product-row-ARS.cartpole", e2eTest: "e2e.product.ARS.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:800000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "ARS/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "ARS/mountain-car", planId: "8a90a9ce4a6c465c0cde3841c1eb918a0126560bbd678a681c73fee8f9545d7b", substrate: "linux-cpu", experimentHash: "product-row-ARS.mountain-car", e2eTest: "e2e.product.ARS.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:320000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "ARS/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "ARS/lunar-lander", planId: "346e16e06fd0632e205947b52e939b058de11f60330ec36bbfb057afdac78a3e", substrate: "linux-cpu", experimentHash: "product-row-ARS.lunar-lander", e2eTest: "e2e.product.ARS.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1600000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "ARS/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "ARS/key-door-grid", planId: "9e5e47efba8415453cb19fb8a1f1d3de78ff22c03977e57120bde0fac6ccb831", substrate: "linux-cpu", experimentHash: "product-row-ARS.key-door-grid", e2eTest: "e2e.product.ARS.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:320000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "ARS/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "her", name: "HER/goal-reaching", planId: "f6f6af08743d9cb62930a10730797b38f568a51faadfd45044e935e0010f5a98", substrate: "linux-cpu", experimentHash: "product-row-HER.goal-reaching", e2eTest: "e2e.product.HER.goal-reaching", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2004:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "HER/goal-reaching" ], requiresTrainedArtifact: true }
  , { kind: "alphazero", name: "connect4", planId: "c1c7a5571e64ce8711a83cb771662c65219123aa7cb2ea7927106d0258b6c74e", substrate: "linux-cpu", experimentHash: "product-row-connect4", e2eTest: "e2e.product.connect4", demoPanel: "connect4-human-vs-alphazero", budget: "alphazero-self-play-generations:64:self-play-generations:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "connect4" ], requiresTrainedArtifact: true }
  , { kind: "alphazero", name: "othello", planId: "81fd8d5b29ec17023673f79e7600298465aeef00ddae50cf6b499fde9d95ee4f", substrate: "linux-cpu", experimentHash: "product-row-othello", e2eTest: "e2e.product.othello", demoPanel: "connect4-human-vs-alphazero", budget: "alphazero-self-play-generations:96:self-play-generations:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "othello" ], requiresTrainedArtifact: true }
  , { kind: "alphazero", name: "hex", planId: "31b00ae6f3b52a133a1bac13434dcd04eaae541ccf43db321416bd1db8342ecb", substrate: "linux-cpu", experimentHash: "product-row-hex", e2eTest: "e2e.product.hex", demoPanel: "connect4-human-vs-alphazero", budget: "alphazero-self-play-generations:128:self-play-generations:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "hex" ], requiresTrainedArtifact: true }
  , { kind: "alphazero", name: "gomoku", planId: "b6d86ca20e7fb08ad2a09f1ca5c0085758df1f48dd967f60589ee86b822bcb18", substrate: "linux-cpu", experimentHash: "product-row-gomoku", e2eTest: "e2e.product.gomoku", demoPanel: "connect4-human-vs-alphazero", budget: "alphazero-self-play-generations:128:self-play-generations:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "gomoku" ], requiresTrainedArtifact: true }
  , { kind: "tuning", name: "hyperparameter-tuning", planId: "4150d67ddfa20cda8b76351328560973fa713b98773cf08bb2456c2bfec56384", substrate: "linux-cpu", experimentHash: "product-row-hyperparameter-tuning", e2eTest: "e2e.product.hyperparameter-tuning", demoPanel: "hyperparameter-sweep", budget: "tuning-trials:128:trials:seed-1729", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "hyperparameter-tuning" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "mnist-shallow-mlp", planId: "e2cede27867023e454cbfb0a5f48a28ef745e1856808a27dc1ef861f5b786b85", substrate: "linux-cuda", experimentHash: "product-row-mnist-shallow-mlp", e2eTest: "e2e.product.mnist-shallow-mlp", demoPanel: "mnist-live-inference", budget: "supervised-epochs:10:epochs:seed-1001", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "mnist-shallow-mlp" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "mnist-deep-mlp", planId: "008ca38f330cf5fab718bbf91fef2f8149a12d9025499d63a70a95a47f203dc4", substrate: "linux-cuda", experimentHash: "product-row-mnist-deep-mlp", e2eTest: "e2e.product.mnist-deep-mlp", demoPanel: "mnist-live-inference", budget: "supervised-epochs:10:epochs:seed-1002", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "mnist-deep-mlp" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "mnist-lenet", planId: "9d5076075a351253692ab5a48e795a0d61df590e58320147f056dbeb3f097b38", substrate: "linux-cuda", experimentHash: "product-row-mnist-lenet", e2eTest: "e2e.product.mnist-lenet", demoPanel: "mnist-live-inference", budget: "supervised-epochs:10:epochs:seed-1003", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "mnist-lenet" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "fashion-mnist-mlp", planId: "d269efb807699dbd0977cda852d719c29bec757e49f2f80d3b5506616de2f5ba", substrate: "linux-cuda", experimentHash: "product-row-fashion-mnist-mlp", e2eTest: "e2e.product.fashion-mnist-mlp", demoPanel: "mnist-live-inference", budget: "supervised-epochs:10:epochs:seed-1004", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "fashion-mnist-mlp" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "fashion-mnist-resnet", planId: "40eb67c8778b0fa7c1b4d8b1b7e0a907290a61369e9d660504e802d6a4bb9148", substrate: "linux-cuda", experimentHash: "product-row-fashion-mnist-resnet", e2eTest: "e2e.product.fashion-mnist-resnet", demoPanel: "mnist-live-inference", budget: "supervised-epochs:10:epochs:seed-1005", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "fashion-mnist-resnet" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "cifar10-resnet20", planId: "4aedd09e16ba05e2c360fe22c8db3763350108b65635fe077c7f121419786954", substrate: "linux-cuda", experimentHash: "product-row-cifar10-resnet20", e2eTest: "e2e.product.cifar10-resnet20", demoPanel: "cifar-imagenet-upload", budget: "supervised-epochs:40:epochs:seed-1006", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "cifar10-resnet20" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "cifar10-resnet56", planId: "5ea977962a31b3f514b796df799cea05cf1cca700e33943ad1565b9be297f177", substrate: "linux-cuda", experimentHash: "product-row-cifar10-resnet56", e2eTest: "e2e.product.cifar10-resnet56", demoPanel: "cifar-imagenet-upload", budget: "supervised-epochs:40:epochs:seed-1007", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "cifar10-resnet56" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "cifar100-wide-resnet", planId: "198cd1a9db83dc0fb78deca59b896d2db5d3cffd28a05717982bc79b80dd4371", substrate: "linux-cuda", experimentHash: "product-row-cifar100-wide-resnet", e2eTest: "e2e.product.cifar100-wide-resnet", demoPanel: "cifar-imagenet-upload", budget: "supervised-epochs:10:epochs:seed-1008", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "cifar100-wide-resnet" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "cifar10-vit", planId: "6ca6d12f92d73b58fd4730537295a601afb3965615f48361e25ef7c3812ba70a", substrate: "linux-cuda", experimentHash: "product-row-cifar10-vit", e2eTest: "e2e.product.cifar10-vit", demoPanel: "cifar-imagenet-upload", budget: "supervised-epochs:40:epochs:seed-1009", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "cifar10-vit" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "tiny-imagenet-resnet50", planId: "a3283ceb6ea8f8023cb2a24a9838e4a2b858fe49aac7a114dd2ea6087339d432", substrate: "linux-cuda", experimentHash: "product-row-tiny-imagenet-resnet50", e2eTest: "e2e.product.tiny-imagenet-resnet50", demoPanel: "cifar-imagenet-upload", budget: "supervised-epochs:15:epochs:seed-1010", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "tiny-imagenet-resnet50" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "california-housing-mlp", planId: "b19e2f5cae8239cd0cbb47b184f7978c409cc8b82b0b34469feece15e4290fea", substrate: "linux-cuda", experimentHash: "product-row-california-housing-mlp", e2eTest: "e2e.product.california-housing-mlp", demoPanel: "generic-inference-lab", budget: "supervised-epochs:10:epochs:seed-1011", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "california-housing-mlp" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/cartpole", planId: "9237c8850b754aadc4603e2067303f4fc0daec21f0916e4deb03c7102d5cdb2e", substrate: "linux-cuda", experimentHash: "product-row-PPO.cartpole", e2eTest: "e2e.product.PPO.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "PPO/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/mountain-car", planId: "461f6a6ccf3e97e6c810e5fb7249856bf248d28b33616133ee1f0ca6ea331e99", substrate: "linux-cuda", experimentHash: "product-row-PPO.mountain-car", e2eTest: "e2e.product.PPO.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "PPO/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/acrobot", planId: "17dd770f138660dbd98fa718d31e1e997eadc73fba7687da3ddf3d0698a8d570", substrate: "linux-cuda", experimentHash: "product-row-PPO.acrobot", e2eTest: "e2e.product.PPO.acrobot", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "PPO/acrobot" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/lunar-lander", planId: "33c3e17931b4e34abecc5bc7e8c6ff98c0e9d23d8f8f64fdc0a3dc2fa14d91bc", substrate: "linux-cuda", experimentHash: "product-row-PPO.lunar-lander", e2eTest: "e2e.product.PPO.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2400000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "PPO/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/key-door-grid", planId: "ddc5de5e34dc4e5930e80c4c89ee388ebc5d609c65820557d1d3e43e9a077f21", substrate: "linux-cuda", experimentHash: "product-row-PPO.key-door-grid", e2eTest: "e2e.product.PPO.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "PPO/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/gridworld-deterministic", planId: "2c7e51d89cf1d0a8d67457f440492ad5332e8e75eff7a40ec74ac5e84ab99248", substrate: "linux-cuda", experimentHash: "product-row-PPO.gridworld-deterministic", e2eTest: "e2e.product.PPO.gridworld-deterministic", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "PPO/gridworld-deterministic" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "A2C/cartpole", planId: "fbf38c8c5aa3ed7e2d02370d6174f90c744418d7a9fb5a701e31cc7af3c0f492", substrate: "linux-cuda", experimentHash: "product-row-A2C.cartpole", e2eTest: "e2e.product.A2C.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "A2C/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "A2C/mountain-car", planId: "8a0d0b1b15f6d9dd7c6f016d3eb9c8c8eb06a00abec78bd66d68ec1d08441a3c", substrate: "linux-cuda", experimentHash: "product-row-A2C.mountain-car", e2eTest: "e2e.product.A2C.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "A2C/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "A2C/lunar-lander", planId: "d6eea5d113df35888a05c749a9839749c28f8724dc5768b06f11f9f2aa69ecc6", substrate: "linux-cuda", experimentHash: "product-row-A2C.lunar-lander", e2eTest: "e2e.product.A2C.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2400000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "A2C/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "A2C/key-door-grid", planId: "7e58b7dfe634faa86d1480ff8e3b9f23b0e8c68919ed03170eac8081478a40ee", substrate: "linux-cuda", experimentHash: "product-row-A2C.key-door-grid", e2eTest: "e2e.product.A2C.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "A2C/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TRPO/cartpole", planId: "522dba417b94fb422e178f67f062a7618ac482cf30a37389e08faeaecc702b29", substrate: "linux-cuda", experimentHash: "product-row-TRPO.cartpole", e2eTest: "e2e.product.TRPO.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "TRPO/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TRPO/mountain-car", planId: "d67c4babaf2344d475946bdbeafadbf4dcd74a532f4d46f15ea87784f4d30504", substrate: "linux-cuda", experimentHash: "product-row-TRPO.mountain-car", e2eTest: "e2e.product.TRPO.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "TRPO/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TRPO/lunar-lander", planId: "d3a9775bce1d884f10a9a3cf58e9e608f22c271a4099c94c44788ebaada1700b", substrate: "linux-cuda", experimentHash: "product-row-TRPO.lunar-lander", e2eTest: "e2e.product.TRPO.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2400000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "TRPO/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TRPO/key-door-grid", planId: "ff0074acbb5d3414c808a63d3b3649ec2bed9e4dff5289e8631f837b0cef43f7", substrate: "linux-cuda", experimentHash: "product-row-TRPO.key-door-grid", e2eTest: "e2e.product.TRPO.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "TRPO/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "MaskablePPO/cartpole", planId: "6f12c88e87c8f0d881336b8736ca5813b02fff48c33539fac11ab4870087f713", substrate: "linux-cuda", experimentHash: "product-row-MaskablePPO.cartpole", e2eTest: "e2e.product.MaskablePPO.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "MaskablePPO/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "MaskablePPO/mountain-car", planId: "b52dbc12bac7b2c89cb4f8caf70d4050b1e3c891c3507f86b520e6f400c7e2c0", substrate: "linux-cuda", experimentHash: "product-row-MaskablePPO.mountain-car", e2eTest: "e2e.product.MaskablePPO.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "MaskablePPO/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "MaskablePPO/lunar-lander", planId: "213b8f06b2d3632ab7e11dd6cb664c1cf25cc1ca8fef244951731237d5d9b5f7", substrate: "linux-cuda", experimentHash: "product-row-MaskablePPO.lunar-lander", e2eTest: "e2e.product.MaskablePPO.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2400000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "MaskablePPO/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "MaskablePPO/key-door-grid", planId: "09baf8421d308fe791768ee296f56dd8eeaa91455810354ea1381b8b13de3170", substrate: "linux-cuda", experimentHash: "product-row-MaskablePPO.key-door-grid", e2eTest: "e2e.product.MaskablePPO.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "MaskablePPO/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "RecurrentPPO/cartpole", planId: "e0a9375677953f48e1c0612a452ea9fb89bfec23083254ea15f3548159307f41", substrate: "linux-cuda", experimentHash: "product-row-RecurrentPPO.cartpole", e2eTest: "e2e.product.RecurrentPPO.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "RecurrentPPO/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "RecurrentPPO/mountain-car", planId: "dca180b7502259258f2b50294c6c94db417cd4405a36c9334df6ae682045a1c2", substrate: "linux-cuda", experimentHash: "product-row-RecurrentPPO.mountain-car", e2eTest: "e2e.product.RecurrentPPO.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "RecurrentPPO/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "RecurrentPPO/lunar-lander", planId: "1e401d922cc68206e4aaed4fe13ed59ad8943157b11618cffab3c85e0a0c735a", substrate: "linux-cuda", experimentHash: "product-row-RecurrentPPO.lunar-lander", e2eTest: "e2e.product.RecurrentPPO.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2400000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "RecurrentPPO/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "RecurrentPPO/key-door-grid", planId: "8524a33a6ddeb9e4e0bac78239efd54a07da13088d58295cbfe85047de1a8b8e", substrate: "linux-cuda", experimentHash: "product-row-RecurrentPPO.key-door-grid", e2eTest: "e2e.product.RecurrentPPO.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:307200:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "RecurrentPPO/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "DQN/cartpole", planId: "5740a22ce24f046005d0f04570d576c0d5eaaa7a5fb2a7fb82003e6e389a61d2", substrate: "linux-cuda", experimentHash: "product-row-DQN.cartpole", e2eTest: "e2e.product.DQN.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "DQN/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "DQN/mountain-car", planId: "c20c920c8b4d775a3509b0d9d21f30ae3ea14263cc24ae1ce2365c5e40fe256c", substrate: "linux-cuda", experimentHash: "product-row-DQN.mountain-car", e2eTest: "e2e.product.DQN.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:120000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "DQN/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "DQN/key-door-grid", planId: "b3dd9523fb6eada68c254534964e81d563c3063934d7f69a9e9af4aad7aa9390", substrate: "linux-cuda", experimentHash: "product-row-DQN.key-door-grid", e2eTest: "e2e.product.DQN.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "DQN/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "QR-DQN/cartpole", planId: "1954e23cade48ad2cfedcb6a14c6daa6eb5afa70ba2ea24f3ec38a2129415a98", substrate: "linux-cuda", experimentHash: "product-row-QR-DQN.cartpole", e2eTest: "e2e.product.QR-DQN.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "QR-DQN/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "QR-DQN/mountain-car", planId: "446288976ad8dd3310ee635ec6f80859f42f9ab1d1ce28bdd14be6482a66057f", substrate: "linux-cuda", experimentHash: "product-row-QR-DQN.mountain-car", e2eTest: "e2e.product.QR-DQN.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:120000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "QR-DQN/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "QR-DQN/key-door-grid", planId: "6732cb468bcb3ad8abf74f940fbf6f10140b4a1cc18580b2b42b04e77c6ea29b", substrate: "linux-cuda", experimentHash: "product-row-QR-DQN.key-door-grid", e2eTest: "e2e.product.QR-DQN.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:120000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "QR-DQN/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "DDPG/lunar-lander", planId: "be13e78492948d51db4e05d70d03de7e513a831d6c4c39240352378917352aab", substrate: "linux-cuda", experimentHash: "product-row-DDPG.lunar-lander", e2eTest: "e2e.product.DDPG.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:120000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "DDPG/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TD3/lunar-lander", planId: "550e27dfc505b31e7e511baeab7a263858f18985b9c6ae163a564a8f4ac58e39", substrate: "linux-cuda", experimentHash: "product-row-TD3.lunar-lander", e2eTest: "e2e.product.TD3.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "TD3/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "SAC/lunar-lander", planId: "86324fbdd7394dd1aa6ee1f3538eb3230b2906fa70cd09509e8ffbb754d3f620", substrate: "linux-cuda", experimentHash: "product-row-SAC.lunar-lander", e2eTest: "e2e.product.SAC.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "SAC/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "SAC/pendulum", planId: "1802bc9af72cdc08a75baff1e5e4da635761ff18194320961eba2dfcd0124cda", substrate: "linux-cuda", experimentHash: "product-row-SAC.pendulum", e2eTest: "e2e.product.SAC.pendulum", demoPanel: "rl-trajectory", budget: "rl-environment-steps:4000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "SAC/pendulum" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "CrossQ/lunar-lander", planId: "55a761de03886a57974d8bb0a9d7832ec0d2e5cde5aab61e83ca15da4c878996", substrate: "linux-cuda", experimentHash: "product-row-CrossQ.lunar-lander", e2eTest: "e2e.product.CrossQ.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "CrossQ/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TQC/lunar-lander", planId: "d79783bc15638f4357df291d88b807e3ec65e6e37fdbb5b9ecdfd1acd71879a0", substrate: "linux-cuda", experimentHash: "product-row-TQC.lunar-lander", e2eTest: "e2e.product.TQC.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "TQC/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "ARS/cartpole", planId: "67ee36abd17fa17cc4b9bf93f98009ad7c8447b67b868aeb74ea5bf9d44f5f14", substrate: "linux-cuda", experimentHash: "product-row-ARS.cartpole", e2eTest: "e2e.product.ARS.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:800000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "ARS/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "ARS/mountain-car", planId: "c79efc7b827b2b562c124af6c491b9ee114421b9c8f89353ac0470bbd8f22747", substrate: "linux-cuda", experimentHash: "product-row-ARS.mountain-car", e2eTest: "e2e.product.ARS.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:320000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "ARS/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "ARS/lunar-lander", planId: "51e201a01fa79ebadae1e7d3e10c0925a21d0b957af72aed1e063a5853d1d7b4", substrate: "linux-cuda", experimentHash: "product-row-ARS.lunar-lander", e2eTest: "e2e.product.ARS.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1600000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "ARS/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "ARS/key-door-grid", planId: "fe3520bfbbedb158625b166ab7024b027031cddb21e722d927a4471fdb577c39", substrate: "linux-cuda", experimentHash: "product-row-ARS.key-door-grid", e2eTest: "e2e.product.ARS.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:320000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "ARS/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "her", name: "HER/goal-reaching", planId: "fd04912df38fc130d060b2e9d8c8fe285a089418c9c5376e607e8427e5e626b0", substrate: "linux-cuda", experimentHash: "product-row-HER.goal-reaching", e2eTest: "e2e.product.HER.goal-reaching", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2004:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "HER/goal-reaching" ], requiresTrainedArtifact: true }
  , { kind: "alphazero", name: "connect4", planId: "2ed82af6d0b5281591ffc747087b802ee72552644e0d4b213c77139f3410dd6d", substrate: "linux-cuda", experimentHash: "product-row-connect4", e2eTest: "e2e.product.connect4", demoPanel: "connect4-human-vs-alphazero", budget: "alphazero-self-play-generations:64:self-play-generations:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "connect4" ], requiresTrainedArtifact: true }
  , { kind: "alphazero", name: "othello", planId: "ebd3ace5c9b39125f56e3aa1797ab8d9eec33aa12f804c9527939e444614aa79", substrate: "linux-cuda", experimentHash: "product-row-othello", e2eTest: "e2e.product.othello", demoPanel: "connect4-human-vs-alphazero", budget: "alphazero-self-play-generations:96:self-play-generations:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "othello" ], requiresTrainedArtifact: true }
  , { kind: "alphazero", name: "hex", planId: "ac5441c35111970a9aba30da937dcc7bc3e12452b47a72948c5dd232fdf7b921", substrate: "linux-cuda", experimentHash: "product-row-hex", e2eTest: "e2e.product.hex", demoPanel: "connect4-human-vs-alphazero", budget: "alphazero-self-play-generations:128:self-play-generations:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "hex" ], requiresTrainedArtifact: true }
  , { kind: "alphazero", name: "gomoku", planId: "5b4a85c313b1b3e1879c64f153f429e0fb3889f65f92688dd82a97d8a8da06c8", substrate: "linux-cuda", experimentHash: "product-row-gomoku", e2eTest: "e2e.product.gomoku", demoPanel: "connect4-human-vs-alphazero", budget: "alphazero-self-play-generations:128:self-play-generations:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "gomoku" ], requiresTrainedArtifact: true }
  , { kind: "tuning", name: "hyperparameter-tuning", planId: "617fb9df165ce1bbca71c987e03d67a5d94911a230658dfc1aaa539d3d56452b", substrate: "linux-cuda", experimentHash: "product-row-hyperparameter-tuning", e2eTest: "e2e.product.hyperparameter-tuning", demoPanel: "hyperparameter-sweep", budget: "tuning-trials:128:trials:seed-1729", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "hyperparameter-tuning" ], requiresTrainedArtifact: true }
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

parseCheckpointList :: String -> Either String CheckpointList
parseCheckpointList payload =
  case parseCheckpointListFields payload of
    Nothing -> Left "malformed CheckpointList frame"
    Just response ->
      case checkpointListValidationError response of
        Just detail -> Left detail
        Nothing -> Right response

parseCheckpointListFields :: String -> Maybe CheckpointList
parseCheckpointListFields payload
  | not (all validCheckpointFieldLine (checkpointFieldLines payload)) = Nothing
  | checkpointUniqueFieldValue "kind" payload == Just "CheckpointList" =
      ( \callId panel publicationStatus runId substrate catalogueSha256 sourceJournalSha256 count selectorState rowSelectors checkpoints ->
          { kind: "CheckpointList", callId, panel, publicationStatus, runId, substrate, catalogueSha256, sourceJournalSha256, count, selectorState, rowSelectors, checkpoints }
      )
        <$> checkpointUniqueFieldValue "call-id" payload
        <*> checkpointUniqueFieldValue "panel" payload
        <*> checkpointUniqueFieldValue "status" payload
        <*> checkpointUniqueFieldValue "run-id" payload
        <*> checkpointUniqueFieldValue "substrate" payload
        <*> checkpointUniqueFieldValue "catalogue-sha256" payload
        <*> checkpointUniqueFieldValue "source-journal-sha256" payload
        <*> checkpointUniqueIntField "count" payload
        <*> checkpointUniqueFieldValue "selector-state" payload
        <*> traverse parseProductRowSelector (checkpointFieldValues "row-selector" payload)
        <*> traverse parseCheckpointSummary (checkpointFieldValues "checkpoint-summary" payload)
  | otherwise = Nothing

checkpointFieldLines :: String -> Array String
checkpointFieldLines payload =
  Array.filter (_ /= "") (String.split (Pattern "\n") payload)

validCheckpointFieldLine :: String -> Boolean
validCheckpointFieldLine line =
  case Array.head (String.split (Pattern ": ") line) of
    Just key -> String.contains (Pattern ": ") line && Array.elem key checkpointFieldNames
    Nothing -> false

checkpointFieldNames :: Array String
checkpointFieldNames =
  [ "kind"
  , "call-id"
  , "panel"
  , "status"
  , "run-id"
  , "substrate"
  , "catalogue-sha256"
  , "source-journal-sha256"
  , "count"
  , "selector-state"
  , "row-selector"
  , "checkpoint-summary"
  ]

checkpointFieldValues :: String -> String -> Array String
checkpointFieldValues key payload =
  Array.mapMaybe
    (String.stripPrefix (Pattern (key <> ": ")))
    (String.split (Pattern "\n") payload)

checkpointUniqueFieldValue :: String -> String -> Maybe String
checkpointUniqueFieldValue key payload =
  case checkpointFieldValues key payload of
    [ value ] -> Just value
    _ -> Nothing

checkpointUniqueIntField :: String -> String -> Maybe Int
checkpointUniqueIntField key payload =
  checkpointUniqueFieldValue key payload >>= Int.fromString

parseProductRowSelector :: String -> Maybe ProductRowSelector
parseProductRowSelector raw =
  case String.split (Pattern "\t") raw of
    [ ordinalRaw, rowId, planId, experimentHash, manifestSha, family, evidenceStatus, evidenceReason, demoPanel ] ->
      (\ordinal -> { ordinal, rowId, planId, experimentHash, manifestSha, family, evidenceStatus, evidenceReason, demoPanel })
        <$> Int.fromString ordinalRaw
    _ -> Nothing

parseCheckpointSummary :: String -> Maybe CheckpointSummary
parseCheckpointSummary raw =
  case String.split (Pattern "\t") raw of
    [ ordinalRaw, rowId, planId, experimentHash, sha, stepRaw, modelFamily, tensorCountRaw, eligibility, completedBudget, measuredResult, tensorboardPrefix ] ->
      (\ordinal step tensorCount -> { ordinal, rowId, planId, experimentHash, sha, step, modelFamily, tensorCount, eligibility, completedBudget, measuredResult, tensorboardPrefix })
        <$> Int.fromString ordinalRaw
        <*> Int.fromString stepRaw
        <*> Int.fromString tensorCountRaw
    _ -> Nothing

checkpointListValidationError :: CheckpointList -> Maybe String
checkpointListValidationError response
  | response.panel /= "checkpoint-browse" = Just "CheckpointList panel is not checkpoint-browse"
  | response.publicationStatus /= "published" = Just "CheckpointList publication status is not published"
  | not (canonicalIdentity response.callId) = Just "CheckpointList call-id is invalid"
  | not (canonicalIdentity response.runId) = Just "CheckpointList run-id is invalid"
  | not (validSubstrate response.substrate) = Just "CheckpointList substrate is invalid"
  | not (canonicalSha256 response.catalogueSha256) = Just "CheckpointList catalogue SHA is invalid"
  | not (canonicalSha256 response.sourceJournalSha256) = Just "CheckpointList source journal SHA is invalid"
  | response.count /= expectedProductRowCount response.substrate = Just "CheckpointList count is not the canonical ProductRow denominator"
  | Array.length response.rowSelectors /= expectedProductRowCount response.substrate = Just "CheckpointList selector coverage is partial"
  | Array.length response.checkpoints /= expectedProductRowCount response.substrate = Just "CheckpointList summary coverage is partial"
  | map _.ordinal response.rowSelectors /= expectedProductOrdinals response.substrate = Just "CheckpointList selector order is invalid"
  | map _.ordinal response.checkpoints /= expectedProductOrdinals response.substrate = Just "CheckpointList summary order is invalid"
  | map _.rowId response.rowSelectors /= expectedProductRowIds response.substrate = Just "CheckpointList selector rows differ from the canonical registry order"
  | map _.rowId response.checkpoints /= expectedProductRowIds response.substrate = Just "CheckpointList summary rows differ from the canonical registry order"
  | map _.planId response.rowSelectors /= expectedProductPlanIds response.substrate = Just "CheckpointList selector PlanIds differ from the canonical substrate registry"
  | map _.planId response.checkpoints /= expectedProductPlanIds response.substrate = Just "CheckpointList summary PlanIds differ from the canonical substrate registry"
  | map _.experimentHash response.rowSelectors /= expectedProductExperiments response.substrate = Just "CheckpointList selector experiments differ from the canonical registry"
  | map _.experimentHash response.checkpoints /= expectedProductExperiments response.substrate = Just "CheckpointList summary experiments differ from the canonical registry"
  | map _.family response.rowSelectors /= expectedProductFamilies response.substrate = Just "CheckpointList selector families differ from the canonical registry"
  | map _.modelFamily response.checkpoints /= expectedProductFamilies response.substrate = Just "CheckpointList summary families differ from the canonical registry"
  | map _.demoPanel response.rowSelectors /= expectedProductDemoPanels response.substrate = Just "CheckpointList demo panels differ from the canonical registry"
  | hasDuplicates (map (\row -> row.rowId <> "\n" <> row.planId) response.rowSelectors) = Just "CheckpointList contains a duplicate rowId/PlanId selector"
  | hasDuplicates (map (\row -> row.rowId <> "\n" <> row.planId) response.checkpoints) = Just "CheckpointList contains a duplicate rowId/PlanId summary"
  | not (all validProductRowSelector response.rowSelectors) = Just "CheckpointList contains an invalid selector"
  | not (all validCheckpointSummary response.checkpoints) = Just "CheckpointList contains an invalid summary"
  | not (all identity (Array.zipWith selectorMatchesSummary response.rowSelectors response.checkpoints)) = Just "CheckpointList selectors and summaries are not an exact identity bijection"
  | not (all (\row -> row.evidenceStatus == "Passed") response.rowSelectors) = Just "CheckpointList contains non-Passed source evidence"
  | response.selectorState /= "ready" = Just "CheckpointList complete Passed evidence is not ready"
  | otherwise = Nothing

validProductRowSelector :: ProductRowSelector -> Boolean
validProductRowSelector row =
  canonicalIdentity row.rowId
    && canonicalSha256 row.planId
    && canonicalIdentity row.experimentHash
    && canonicalSha256 row.manifestSha
    && canonicalIdentity row.family
    && canonicalIdentity row.demoPanel
    && validEvidenceStatus row.evidenceStatus row.evidenceReason

validCheckpointSummary :: CheckpointSummary -> Boolean
validCheckpointSummary row =
  canonicalIdentity row.rowId
    && canonicalSha256 row.planId
    && canonicalIdentity row.experimentHash
    && canonicalSha256 row.sha
    && row.step >= 0
    && canonicalIdentity row.modelFamily
    && row.tensorCount > 0
    && (row.eligibility == "eligible" || row.eligibility == "unavailable")
    && canonicalIdentity row.completedBudget
    && canonicalIdentity row.measuredResult
    && canonicalIdentity row.tensorboardPrefix

selectorMatchesSummary :: ProductRowSelector -> CheckpointSummary -> Boolean
selectorMatchesSummary selector summary =
  selector.ordinal == summary.ordinal
    && selector.rowId == summary.rowId
    && selector.planId == summary.planId
    && selector.experimentHash == summary.experimentHash
    && selector.manifestSha == summary.sha
    && selector.family == summary.modelFamily
    && ((selector.evidenceStatus == "Passed") == (summary.eligibility == "eligible"))

validEvidenceStatus :: String -> String -> Boolean
validEvidenceStatus status reason =
  case status of
    "Passed" -> reason == ""
    "Failed" -> canonicalIdentity reason
    "NotRun" -> canonicalIdentity reason
    _ -> false

validSubstrate :: String -> Boolean
validSubstrate value = value == "linux-cpu" || value == "linux-cuda" || value == "apple-silicon"

canonicalIdentity :: String -> Boolean
canonicalIdentity value =
  value /= ""
    && Array.length (String.toCodePointArray value) <= 4096
    && String.trim value == value
    && all (not <<< isControlCodePoint) (String.toCodePointArray value)

isControlCodePoint codePoint =
  let
    value = fromEnum codePoint
  in
    (value >= 0 && value <= 31) || (value >= 127 && value <= 159)

canonicalSha256 :: String -> Boolean
canonicalSha256 value =
  String.length value == 64
    && all isLowerHex (String.toCodePointArray value)

isLowerHex codePoint =
  let
    value = String.singleton codePoint
  in
    String.contains (Pattern value) "0123456789abcdef"

hasDuplicates :: Array String -> Boolean
hasDuplicates values = Array.length (Array.nub values) /= Array.length values

expectedProductRowCount :: String -> Int
expectedProductRowCount substrate = Array.length (allModelMatrixRowsForSubstrate substrate)

expectedProductOrdinals :: String -> Array Int
expectedProductOrdinals substrate = Array.range 0 (expectedProductRowCount substrate - 1)

expectedProductRowIds :: String -> Array String
expectedProductRowIds substrate = map _.name (allModelMatrixRowsForSubstrate substrate)

expectedProductPlanIds :: String -> Array String
expectedProductPlanIds substrate = map _.planId (allModelMatrixRowsForSubstrate substrate)

expectedProductExperiments :: String -> Array String
expectedProductExperiments substrate = map _.experimentHash (allModelMatrixRowsForSubstrate substrate)

expectedProductFamilies :: String -> Array String
expectedProductFamilies substrate =
  map (\row -> if row.kind == "her" then "rl" else row.kind) (allModelMatrixRowsForSubstrate substrate)

expectedProductDemoPanels :: String -> Array String
expectedProductDemoPanels substrate = map _.demoPanel (allModelMatrixRowsForSubstrate substrate)

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

uniqueFieldValue :: String -> String -> Maybe String
uniqueFieldValue key payload =
  case fieldValues key payload of
    [ value ] -> Just value
    _ -> Nothing

uniqueIntField :: String -> String -> Maybe Int
uniqueIntField key payload =
  uniqueFieldValue key payload >>= Int.fromString

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
