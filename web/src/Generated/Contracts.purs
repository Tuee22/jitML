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
  [ { kind: "supervised", name: "mnist-shallow-mlp", planId: "7da4faeee152de78039933a7e42500e9cbd96597e257348bf91ff5ce3c35bf70", substrate: "apple-silicon", experimentHash: "product-row-mnist-shallow-mlp", e2eTest: "e2e.product.mnist-shallow-mlp", demoPanel: "mnist-live-inference", budget: "supervised-epochs:10:epochs:seed-1001", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "mnist-shallow-mlp" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "mnist-deep-mlp", planId: "fcce4d702e8e401e579cf561d3180c2d63b32eb9a43c17f6bc1fa8ef421fd4ac", substrate: "apple-silicon", experimentHash: "product-row-mnist-deep-mlp", e2eTest: "e2e.product.mnist-deep-mlp", demoPanel: "mnist-live-inference", budget: "supervised-epochs:10:epochs:seed-1002", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "mnist-deep-mlp" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "mnist-lenet", planId: "825767c8fc3fbcd29c82cbca3b5a64fdb7d94ada466553be958d9f04312438a9", substrate: "apple-silicon", experimentHash: "product-row-mnist-lenet", e2eTest: "e2e.product.mnist-lenet", demoPanel: "mnist-live-inference", budget: "supervised-epochs:10:epochs:seed-1003", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "mnist-lenet" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "fashion-mnist-mlp", planId: "0db1451eb071cbf8402164805bb9b51162ce339498fa39e16e497af8cfa49cd5", substrate: "apple-silicon", experimentHash: "product-row-fashion-mnist-mlp", e2eTest: "e2e.product.fashion-mnist-mlp", demoPanel: "mnist-live-inference", budget: "supervised-epochs:10:epochs:seed-1004", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "fashion-mnist-mlp" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "fashion-mnist-resnet", planId: "0d0144d31841a201770c8a73fbbe04727e7c4f97ba40d25bc80f476d2d7e8eeb", substrate: "apple-silicon", experimentHash: "product-row-fashion-mnist-resnet", e2eTest: "e2e.product.fashion-mnist-resnet", demoPanel: "mnist-live-inference", budget: "supervised-epochs:10:epochs:seed-1005", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "fashion-mnist-resnet" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "cifar10-resnet20", planId: "8acc466dab1dfd454d067a5aa99a917a813cb8ed8370ade261cbe2a40277502d", substrate: "apple-silicon", experimentHash: "product-row-cifar10-resnet20", e2eTest: "e2e.product.cifar10-resnet20", demoPanel: "cifar-imagenet-upload", budget: "supervised-epochs:40:epochs:seed-1006", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "cifar10-resnet20" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "cifar10-resnet56", planId: "78c7cec5fe7c636a7611e3cbc0bb484094fc4f13b322d4dc48e6379e7166b5e7", substrate: "apple-silicon", experimentHash: "product-row-cifar10-resnet56", e2eTest: "e2e.product.cifar10-resnet56", demoPanel: "cifar-imagenet-upload", budget: "supervised-epochs:40:epochs:seed-1007", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "cifar10-resnet56" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "cifar100-wide-resnet", planId: "6a514742423d4ec693cc406b61bb3f9f1069e0803a10b19f2340b972527185e5", substrate: "apple-silicon", experimentHash: "product-row-cifar100-wide-resnet", e2eTest: "e2e.product.cifar100-wide-resnet", demoPanel: "cifar-imagenet-upload", budget: "supervised-epochs:10:epochs:seed-1008", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "cifar100-wide-resnet" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "cifar10-vit", planId: "6f74b23e005855e31b98c9e34a681ac558439defb4ed48ee473376963f5f9454", substrate: "apple-silicon", experimentHash: "product-row-cifar10-vit", e2eTest: "e2e.product.cifar10-vit", demoPanel: "cifar-imagenet-upload", budget: "supervised-epochs:40:epochs:seed-1009", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "cifar10-vit" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "tiny-imagenet-resnet50", planId: "808f353500ed56966cf246d80116ca2168cec786dc51c8ce37fbcb6e42ce7ec2", substrate: "apple-silicon", experimentHash: "product-row-tiny-imagenet-resnet50", e2eTest: "e2e.product.tiny-imagenet-resnet50", demoPanel: "cifar-imagenet-upload", budget: "supervised-epochs:15:epochs:seed-1010", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "tiny-imagenet-resnet50" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "california-housing-mlp", planId: "572c209070a570d7423c17748cbd7be61571125f7b2f6ecc5aea950b3819d14b", substrate: "apple-silicon", experimentHash: "product-row-california-housing-mlp", e2eTest: "e2e.product.california-housing-mlp", demoPanel: "generic-inference-lab", budget: "supervised-epochs:100:epochs:seed-1011", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "california-housing-mlp" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/cartpole", planId: "66ff26f1e3efeaf4cb0b7b6cb8b45c69fd9780793e428704f82b180fc11b713b", substrate: "apple-silicon", experimentHash: "product-row-PPO.cartpole", e2eTest: "e2e.product.PPO.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "PPO/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/mountain-car", planId: "21d881226609d1c25c76d71323a6271bb6009c70ffda5b21a1b05bbccefc0f09", substrate: "apple-silicon", experimentHash: "product-row-PPO.mountain-car", e2eTest: "e2e.product.PPO.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2457600:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "PPO/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/acrobot", planId: "469fdfc0a380601f913635a1656dc4d51b634875d5d4d29c6a6e53eccc217c16", substrate: "apple-silicon", experimentHash: "product-row-PPO.acrobot", e2eTest: "e2e.product.PPO.acrobot", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "PPO/acrobot" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/lunar-lander", planId: "3492799add8b166ce431798ad6df73f2dca7cfed00ac75f59a785107220444de", substrate: "apple-silicon", experimentHash: "product-row-PPO.lunar-lander", e2eTest: "e2e.product.PPO.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2400000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "PPO/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/key-door-grid", planId: "df6c00e43401011b2c59d6946d306c8ecb95dd563f2e1829d632324d997d201b", substrate: "apple-silicon", experimentHash: "product-row-PPO.key-door-grid", e2eTest: "e2e.product.PPO.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "PPO/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/gridworld-deterministic", planId: "8929bd4f8063c46b29468d00037513fa38e46cc2b400024cb2eea6669f9c30cf", substrate: "apple-silicon", experimentHash: "product-row-PPO.gridworld-deterministic", e2eTest: "e2e.product.PPO.gridworld-deterministic", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "PPO/gridworld-deterministic" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "A2C/cartpole", planId: "175fbb46c8c539b756c3841517ce21c2bfad9081bf6f9e9b6c01b86d5856a015", substrate: "apple-silicon", experimentHash: "product-row-A2C.cartpole", e2eTest: "e2e.product.A2C.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "A2C/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "A2C/mountain-car", planId: "e6f3c46364f44227e435af5c79a0e6c5640bccfb7549bd15a66d0c2156d961c2", substrate: "apple-silicon", experimentHash: "product-row-A2C.mountain-car", e2eTest: "e2e.product.A2C.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "A2C/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "A2C/lunar-lander", planId: "e0ab7366874911b3c365f44edb2d881c2afcfa92b2401fcef0bc78018bf1c6df", substrate: "apple-silicon", experimentHash: "product-row-A2C.lunar-lander", e2eTest: "e2e.product.A2C.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2400000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "A2C/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "A2C/key-door-grid", planId: "927870a09414a2290b0733b9e769f4894efb57d578400983f3eeb4d7b4f82933", substrate: "apple-silicon", experimentHash: "product-row-A2C.key-door-grid", e2eTest: "e2e.product.A2C.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "A2C/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TRPO/cartpole", planId: "64f3d41c00fc97046e50652def2eb18c0102ec12af10cc16e364595706f5c4fc", substrate: "apple-silicon", experimentHash: "product-row-TRPO.cartpole", e2eTest: "e2e.product.TRPO.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "TRPO/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TRPO/mountain-car", planId: "7b9bfbd360484e060dd7930c7c280b5dae66b5d453ba42e9ea221aa965e6ae07", substrate: "apple-silicon", experimentHash: "product-row-TRPO.mountain-car", e2eTest: "e2e.product.TRPO.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "TRPO/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TRPO/lunar-lander", planId: "c285ef2a46d8f044a3c7caa07a91cfae24e37b2c339cad400b54bb080914baf8", substrate: "apple-silicon", experimentHash: "product-row-TRPO.lunar-lander", e2eTest: "e2e.product.TRPO.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2400000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "TRPO/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TRPO/key-door-grid", planId: "1a5d4700dd7a7676e9ca5ac8337b7286675cfe6d45cea9f59be1865b6f8afb12", substrate: "apple-silicon", experimentHash: "product-row-TRPO.key-door-grid", e2eTest: "e2e.product.TRPO.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "TRPO/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "MaskablePPO/cartpole", planId: "0b227fd91cf61a6a6137338e19d1aa73e8a49175d34a49e9af5ff6064ccab876", substrate: "apple-silicon", experimentHash: "product-row-MaskablePPO.cartpole", e2eTest: "e2e.product.MaskablePPO.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "MaskablePPO/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "MaskablePPO/mountain-car", planId: "323f7b2a1c2af6a8fdb0d45febc4077b8019b2e12f4e21fa8cc840e079477f1a", substrate: "apple-silicon", experimentHash: "product-row-MaskablePPO.mountain-car", e2eTest: "e2e.product.MaskablePPO.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "MaskablePPO/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "MaskablePPO/lunar-lander", planId: "3ff30bbf32692ad80fac4f939121737ab034eff285c13e71e7f5cf33c8271bfc", substrate: "apple-silicon", experimentHash: "product-row-MaskablePPO.lunar-lander", e2eTest: "e2e.product.MaskablePPO.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2400000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "MaskablePPO/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "MaskablePPO/key-door-grid", planId: "900a30029bc6d587ad24821a4b8e96b08a7277467869e19bbd12632018bfe3f7", substrate: "apple-silicon", experimentHash: "product-row-MaskablePPO.key-door-grid", e2eTest: "e2e.product.MaskablePPO.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "MaskablePPO/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "RecurrentPPO/cartpole", planId: "78e77b75b3e4d4cfaad7fbb4f12c9110ffa5c8898c2f69e79563d0ae477329f7", substrate: "apple-silicon", experimentHash: "product-row-RecurrentPPO.cartpole", e2eTest: "e2e.product.RecurrentPPO.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "RecurrentPPO/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "RecurrentPPO/mountain-car", planId: "07ef5aafa97a4c56cc3a96b0d04f7d7fe9aba77aeaa82d9db9ad5c807e2711ca", substrate: "apple-silicon", experimentHash: "product-row-RecurrentPPO.mountain-car", e2eTest: "e2e.product.RecurrentPPO.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "RecurrentPPO/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "RecurrentPPO/lunar-lander", planId: "2e7832fba7f6007461e6605d910e2717b62a0e87b7156af5cd29d2d027d98ae2", substrate: "apple-silicon", experimentHash: "product-row-RecurrentPPO.lunar-lander", e2eTest: "e2e.product.RecurrentPPO.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2400000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "RecurrentPPO/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "RecurrentPPO/key-door-grid", planId: "3ef4586036819f29fcf0959109af2b8ef296ae627ef9c6872b2789f4ffb9246c", substrate: "apple-silicon", experimentHash: "product-row-RecurrentPPO.key-door-grid", e2eTest: "e2e.product.RecurrentPPO.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:307200:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "RecurrentPPO/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "DQN/cartpole", planId: "9accaa1e159511d9406b6620398fee2f455e5aaed52a1b544f73aa1bdcd3420a", substrate: "apple-silicon", experimentHash: "product-row-DQN.cartpole", e2eTest: "e2e.product.DQN.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "DQN/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "DQN/mountain-car", planId: "9fbfc4d264c1153c36a1af7dcfaa533a19401eb3fd33a15b7392127b327cd9b7", substrate: "apple-silicon", experimentHash: "product-row-DQN.mountain-car", e2eTest: "e2e.product.DQN.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:120000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "DQN/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "DQN/key-door-grid", planId: "aebcd29d5939a0fd88af2baef8c1849da90122877a4368d0a95e3830d7d9723f", substrate: "apple-silicon", experimentHash: "product-row-DQN.key-door-grid", e2eTest: "e2e.product.DQN.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "DQN/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "QR-DQN/cartpole", planId: "7095b8274e586b63d4c4c8898a86872597626e72219e5ebbf3c56b925fb2256d", substrate: "apple-silicon", experimentHash: "product-row-QR-DQN.cartpole", e2eTest: "e2e.product.QR-DQN.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "QR-DQN/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "QR-DQN/mountain-car", planId: "c5e78334d33b9c8fa77d79f3d56fa15bc6b5dcf6f97bef8f2917f954cee12dc4", substrate: "apple-silicon", experimentHash: "product-row-QR-DQN.mountain-car", e2eTest: "e2e.product.QR-DQN.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:120000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "QR-DQN/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "QR-DQN/key-door-grid", planId: "4cc8ea724a504fe001b6725ea61035e81e54b95a88a2887049c88bfe86f865b4", substrate: "apple-silicon", experimentHash: "product-row-QR-DQN.key-door-grid", e2eTest: "e2e.product.QR-DQN.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:120000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "QR-DQN/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "DDPG/lunar-lander", planId: "e6ceaec37946bffec4386264b381f8b85c69488a5042a1f149170c7481b4beb4", substrate: "apple-silicon", experimentHash: "product-row-DDPG.lunar-lander", e2eTest: "e2e.product.DDPG.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:120000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "DDPG/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TD3/lunar-lander", planId: "9cc8314620cf1e6d3a7f2a2c637eca9ed919babdba4d5e42969380e299c77410", substrate: "apple-silicon", experimentHash: "product-row-TD3.lunar-lander", e2eTest: "e2e.product.TD3.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "TD3/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "SAC/lunar-lander", planId: "5525a03b46e8beed32b7ca6603305524735e9cd7c5a0e2707e78511a6fbb5f03", substrate: "apple-silicon", experimentHash: "product-row-SAC.lunar-lander", e2eTest: "e2e.product.SAC.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "SAC/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "SAC/pendulum", planId: "f118b362b6fbd9c30665054947f2994a875bcd10be99c97120a1af5ed6ce417f", substrate: "apple-silicon", experimentHash: "product-row-SAC.pendulum", e2eTest: "e2e.product.SAC.pendulum", demoPanel: "rl-trajectory", budget: "rl-environment-steps:4000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "SAC/pendulum" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "CrossQ/lunar-lander", planId: "7ad337e855cedf38c1f69bdb32bb363268a93dd73e9823a953ab34715e67b465", substrate: "apple-silicon", experimentHash: "product-row-CrossQ.lunar-lander", e2eTest: "e2e.product.CrossQ.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "CrossQ/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TQC/lunar-lander", planId: "a1f17c4d4c7ed02f3a48110b16d415af3c28a77a4c920425f08bcd59129344cf", substrate: "apple-silicon", experimentHash: "product-row-TQC.lunar-lander", e2eTest: "e2e.product.TQC.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "TQC/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "ARS/cartpole", planId: "7eb4d4f2f64025dd4e30f1eeb50d6312b0b3c2a0ae6ce3311c3b382c1219816d", substrate: "apple-silicon", experimentHash: "product-row-ARS.cartpole", e2eTest: "e2e.product.ARS.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:800000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "ARS/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "ARS/mountain-car", planId: "50434967e14c04aa48aabcdad21b6a5ca6b21319810d6c419d442f66f6c09501", substrate: "apple-silicon", experimentHash: "product-row-ARS.mountain-car", e2eTest: "e2e.product.ARS.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:320000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "ARS/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "ARS/lunar-lander", planId: "d954720f048d8acbf18316a3bcbb7193bb5be653a665790565e3bcf6b63c4757", substrate: "apple-silicon", experimentHash: "product-row-ARS.lunar-lander", e2eTest: "e2e.product.ARS.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1600000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "ARS/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "ARS/key-door-grid", planId: "f568446a774cdcd9128dd57026912f7e0aef8b7e9b4863c9fe0d5692bca6099b", substrate: "apple-silicon", experimentHash: "product-row-ARS.key-door-grid", e2eTest: "e2e.product.ARS.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:320000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "ARS/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "her", name: "HER/goal-reaching", planId: "e2e959786728055df24eca72b82cee9a166f4491a2332e60af4c62b5705ae644", substrate: "apple-silicon", experimentHash: "product-row-HER.goal-reaching", e2eTest: "e2e.product.HER.goal-reaching", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2004:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "HER/goal-reaching" ], requiresTrainedArtifact: true }
  , { kind: "alphazero", name: "connect4", planId: "b4a3d416b1dd090f74b3cc91da39fd8e8b7641a0d6dbad7ffadbf570cb53015c", substrate: "apple-silicon", experimentHash: "product-row-connect4", e2eTest: "e2e.product.connect4", demoPanel: "connect4-human-vs-alphazero", budget: "alphazero-self-play-generations:64:self-play-generations:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "connect4" ], requiresTrainedArtifact: true }
  , { kind: "alphazero", name: "othello", planId: "1be0778c2da43c7acda56a4df305460d2e41da9118aadab83fbca24d2020c79f", substrate: "apple-silicon", experimentHash: "product-row-othello", e2eTest: "e2e.product.othello", demoPanel: "connect4-human-vs-alphazero", budget: "alphazero-self-play-generations:96:self-play-generations:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "othello" ], requiresTrainedArtifact: true }
  , { kind: "alphazero", name: "hex", planId: "592092f87e5bdf91da6ec0cdbe958a879075119acf4e473b80c18e52f5ca97db", substrate: "apple-silicon", experimentHash: "product-row-hex", e2eTest: "e2e.product.hex", demoPanel: "connect4-human-vs-alphazero", budget: "alphazero-self-play-generations:128:self-play-generations:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "hex" ], requiresTrainedArtifact: true }
  , { kind: "alphazero", name: "gomoku", planId: "9876668b4d1cdd74a03279e4ef811129264cdc1dfd56fabd94f1308af068a365", substrate: "apple-silicon", experimentHash: "product-row-gomoku", e2eTest: "e2e.product.gomoku", demoPanel: "connect4-human-vs-alphazero", budget: "alphazero-self-play-generations:128:self-play-generations:seed-42", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "gomoku" ], requiresTrainedArtifact: true }
  , { kind: "tuning", name: "hyperparameter-tuning", planId: "5fcef09cdaab17fdfa1fad975f49ecc7f6cbbad8c1b26cc9d40018a51bb9006a", substrate: "apple-silicon", experimentHash: "product-row-hyperparameter-tuning", e2eTest: "e2e.product.hyperparameter-tuning", demoPanel: "hyperparameter-sweep", budget: "tuning-trials:128:trials:seed-1729", command: [ "internal", "train-and-publish-product-rows", "--apple-silicon", "--row", "hyperparameter-tuning" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "mnist-shallow-mlp", planId: "8d0e685d27f8718a09aca8d9cde10246d8b46b300107a21c780a567482c1c3d2", substrate: "linux-cpu", experimentHash: "product-row-mnist-shallow-mlp", e2eTest: "e2e.product.mnist-shallow-mlp", demoPanel: "mnist-live-inference", budget: "supervised-epochs:10:epochs:seed-1001", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "mnist-shallow-mlp" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "mnist-deep-mlp", planId: "7d6c88b9b487aceff26c06d1524ed2ed43acd17e6f8087941ff22dd39228bce0", substrate: "linux-cpu", experimentHash: "product-row-mnist-deep-mlp", e2eTest: "e2e.product.mnist-deep-mlp", demoPanel: "mnist-live-inference", budget: "supervised-epochs:10:epochs:seed-1002", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "mnist-deep-mlp" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "mnist-lenet", planId: "cd822dc8fb4f572bd3afd7eb59db68cb8d855c845dcd790ed3752b2201b532d2", substrate: "linux-cpu", experimentHash: "product-row-mnist-lenet", e2eTest: "e2e.product.mnist-lenet", demoPanel: "mnist-live-inference", budget: "supervised-epochs:10:epochs:seed-1003", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "mnist-lenet" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "fashion-mnist-mlp", planId: "d9c4e4436dc9428d80a5460f51bc1f0edbf0720e8c0c615610aa138d9e0f9aad", substrate: "linux-cpu", experimentHash: "product-row-fashion-mnist-mlp", e2eTest: "e2e.product.fashion-mnist-mlp", demoPanel: "mnist-live-inference", budget: "supervised-epochs:10:epochs:seed-1004", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "fashion-mnist-mlp" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "fashion-mnist-resnet", planId: "642dcb131084debf6bccbdd8672317a05944cfc60e132cd7008e91f082e2d011", substrate: "linux-cpu", experimentHash: "product-row-fashion-mnist-resnet", e2eTest: "e2e.product.fashion-mnist-resnet", demoPanel: "mnist-live-inference", budget: "supervised-epochs:10:epochs:seed-1005", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "fashion-mnist-resnet" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "cifar10-resnet20", planId: "65c19dd44a4aca73e7edc5f3e02b8024384405f510b1eaf16b7db551dbbb7bf3", substrate: "linux-cpu", experimentHash: "product-row-cifar10-resnet20", e2eTest: "e2e.product.cifar10-resnet20", demoPanel: "cifar-imagenet-upload", budget: "supervised-epochs:40:epochs:seed-1006", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "cifar10-resnet20" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "cifar10-resnet56", planId: "89c824f4e59f96e5ab6f6f34f087be13cca712663149775ecf98a313666f1648", substrate: "linux-cpu", experimentHash: "product-row-cifar10-resnet56", e2eTest: "e2e.product.cifar10-resnet56", demoPanel: "cifar-imagenet-upload", budget: "supervised-epochs:40:epochs:seed-1007", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "cifar10-resnet56" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "cifar100-wide-resnet", planId: "13d288a249d79d2f92974df7d0b81d9a446b2be84201a9c0e38b325bc2638e7d", substrate: "linux-cpu", experimentHash: "product-row-cifar100-wide-resnet", e2eTest: "e2e.product.cifar100-wide-resnet", demoPanel: "cifar-imagenet-upload", budget: "supervised-epochs:10:epochs:seed-1008", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "cifar100-wide-resnet" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "cifar10-vit", planId: "1528574480a5d949aab8e19a29dbe8d94f5161241a3559c07ac298b78fef2268", substrate: "linux-cpu", experimentHash: "product-row-cifar10-vit", e2eTest: "e2e.product.cifar10-vit", demoPanel: "cifar-imagenet-upload", budget: "supervised-epochs:40:epochs:seed-1009", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "cifar10-vit" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "tiny-imagenet-resnet50", planId: "1bf17525109200326669ce753b27f664ab44094195d7615892813e8a28929468", substrate: "linux-cpu", experimentHash: "product-row-tiny-imagenet-resnet50", e2eTest: "e2e.product.tiny-imagenet-resnet50", demoPanel: "cifar-imagenet-upload", budget: "supervised-epochs:15:epochs:seed-1010", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "tiny-imagenet-resnet50" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "california-housing-mlp", planId: "3bdc28adc596427a05779634500773b93913ce18d35819b86f66bb04995d72d2", substrate: "linux-cpu", experimentHash: "product-row-california-housing-mlp", e2eTest: "e2e.product.california-housing-mlp", demoPanel: "generic-inference-lab", budget: "supervised-epochs:100:epochs:seed-1011", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "california-housing-mlp" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/cartpole", planId: "4738f6852ded47b1d60c0f25934bace5cb7bfe14a71726815912ae88ca5482fd", substrate: "linux-cpu", experimentHash: "product-row-PPO.cartpole", e2eTest: "e2e.product.PPO.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "PPO/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/mountain-car", planId: "b560836fd2dbe374e8e7aaa898b51bdb2096ac93e30feb690bcac1d12f97bbbd", substrate: "linux-cpu", experimentHash: "product-row-PPO.mountain-car", e2eTest: "e2e.product.PPO.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2457600:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "PPO/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/acrobot", planId: "1d2b533d9eb63b3223d1b65d11252fc8e450d617cf26c5bac7d228e5ee9e2ece", substrate: "linux-cpu", experimentHash: "product-row-PPO.acrobot", e2eTest: "e2e.product.PPO.acrobot", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "PPO/acrobot" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/lunar-lander", planId: "30e6fef48517b3aad55bd78fc9a2d11a91fea9baf3df122bbb4e778e0daa7045", substrate: "linux-cpu", experimentHash: "product-row-PPO.lunar-lander", e2eTest: "e2e.product.PPO.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2400000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "PPO/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/key-door-grid", planId: "3242bd966467db4950d9af908ca334071e692e8a13f57edacdea0d7a53f83573", substrate: "linux-cpu", experimentHash: "product-row-PPO.key-door-grid", e2eTest: "e2e.product.PPO.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "PPO/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/gridworld-deterministic", planId: "875597507848f0ff7aeb8860f1e8dc0e87cd9d78f42cc7cfe1998b369873d4e7", substrate: "linux-cpu", experimentHash: "product-row-PPO.gridworld-deterministic", e2eTest: "e2e.product.PPO.gridworld-deterministic", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "PPO/gridworld-deterministic" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "A2C/cartpole", planId: "2c9d43cc1b30281c86d0aa42a47795a0bd5e238d1f4658373271e298a8036d79", substrate: "linux-cpu", experimentHash: "product-row-A2C.cartpole", e2eTest: "e2e.product.A2C.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "A2C/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "A2C/mountain-car", planId: "0f50baac23160462ad65a037188c5c5fda1e11dd8a657449e4ac0a3ad35105f2", substrate: "linux-cpu", experimentHash: "product-row-A2C.mountain-car", e2eTest: "e2e.product.A2C.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "A2C/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "A2C/lunar-lander", planId: "e5c20d18ea819396f59413f1feb3e4d06bcf9959260935db2cd0765d44b71c88", substrate: "linux-cpu", experimentHash: "product-row-A2C.lunar-lander", e2eTest: "e2e.product.A2C.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2400000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "A2C/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "A2C/key-door-grid", planId: "edb6c13c3d2c175799714c2dcc14ae7f7e16392fbf25b83d95f961ab10c9b238", substrate: "linux-cpu", experimentHash: "product-row-A2C.key-door-grid", e2eTest: "e2e.product.A2C.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "A2C/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TRPO/cartpole", planId: "140b0d1e6a970b0261e92119288a28cb288c7ebc99ff9aa7ac0452235b885d7e", substrate: "linux-cpu", experimentHash: "product-row-TRPO.cartpole", e2eTest: "e2e.product.TRPO.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "TRPO/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TRPO/mountain-car", planId: "ea932ce8e676404c6845b4fe8fc3ef4ae851c51bc1ef1c2baa0fdcc8e8b26d6b", substrate: "linux-cpu", experimentHash: "product-row-TRPO.mountain-car", e2eTest: "e2e.product.TRPO.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "TRPO/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TRPO/lunar-lander", planId: "70462e574e19aa04a90e982d063d5801908cc358bc838f93c53da9d84e8e1dde", substrate: "linux-cpu", experimentHash: "product-row-TRPO.lunar-lander", e2eTest: "e2e.product.TRPO.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2400000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "TRPO/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TRPO/key-door-grid", planId: "dba414857f7ffead6ee377c5e5dc55c195177f980ef5af672ab3e9a88a8b0778", substrate: "linux-cpu", experimentHash: "product-row-TRPO.key-door-grid", e2eTest: "e2e.product.TRPO.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "TRPO/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "MaskablePPO/cartpole", planId: "723a2917e4935001acce8940208c4a712912c46d0a6d33c82a8dfb0ba0690330", substrate: "linux-cpu", experimentHash: "product-row-MaskablePPO.cartpole", e2eTest: "e2e.product.MaskablePPO.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "MaskablePPO/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "MaskablePPO/mountain-car", planId: "85ca26d47128af901af2a5a540e49a2396f3801ba272c04b53df012d3d45673a", substrate: "linux-cpu", experimentHash: "product-row-MaskablePPO.mountain-car", e2eTest: "e2e.product.MaskablePPO.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "MaskablePPO/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "MaskablePPO/lunar-lander", planId: "83773d586135b97df31b958d1b563c89805f6a09069d69b8e6e65fb5ac7b648b", substrate: "linux-cpu", experimentHash: "product-row-MaskablePPO.lunar-lander", e2eTest: "e2e.product.MaskablePPO.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2400000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "MaskablePPO/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "MaskablePPO/key-door-grid", planId: "95c3fde209b95c84e0983bc8a1ab15004cc4d074566c1fa568d171d173fffd6e", substrate: "linux-cpu", experimentHash: "product-row-MaskablePPO.key-door-grid", e2eTest: "e2e.product.MaskablePPO.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "MaskablePPO/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "RecurrentPPO/cartpole", planId: "e3638fbb0afa548dffcf772950aa6fc028b52bbfac49330eee1b014ad2a980fb", substrate: "linux-cpu", experimentHash: "product-row-RecurrentPPO.cartpole", e2eTest: "e2e.product.RecurrentPPO.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "RecurrentPPO/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "RecurrentPPO/mountain-car", planId: "2e22c5d7db78eed527c09923c196a92bdd96fe5f9b305fff80740661775c1426", substrate: "linux-cpu", experimentHash: "product-row-RecurrentPPO.mountain-car", e2eTest: "e2e.product.RecurrentPPO.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "RecurrentPPO/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "RecurrentPPO/lunar-lander", planId: "10124c9bdd7281ae5a3a3d1f1660b11dc64b05f26268e32a89cd2249aa03bf98", substrate: "linux-cpu", experimentHash: "product-row-RecurrentPPO.lunar-lander", e2eTest: "e2e.product.RecurrentPPO.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2400000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "RecurrentPPO/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "RecurrentPPO/key-door-grid", planId: "8db33b19f18c5d97cccaac3911f08b9e63166c44708cffc3a90c253d3c49dfa6", substrate: "linux-cpu", experimentHash: "product-row-RecurrentPPO.key-door-grid", e2eTest: "e2e.product.RecurrentPPO.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:307200:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "RecurrentPPO/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "DQN/cartpole", planId: "777e2c2422e4b2bc83fae3d8a3d3e79dba629340019c761ce9816d41c7b2346c", substrate: "linux-cpu", experimentHash: "product-row-DQN.cartpole", e2eTest: "e2e.product.DQN.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "DQN/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "DQN/mountain-car", planId: "6e45a778521cfaad1bbb4d2976dad8af8e97d6ddb3590ee24906fd07a9625e52", substrate: "linux-cpu", experimentHash: "product-row-DQN.mountain-car", e2eTest: "e2e.product.DQN.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:120000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "DQN/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "DQN/key-door-grid", planId: "b51a3c6dd97466d68bd725cde8a58958003b07c55c089aadf49720615e9ae462", substrate: "linux-cpu", experimentHash: "product-row-DQN.key-door-grid", e2eTest: "e2e.product.DQN.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "DQN/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "QR-DQN/cartpole", planId: "1af5b34cdd01a834ffdfc4b90ae61ecd56fe03111a6057e069a09732af0e0805", substrate: "linux-cpu", experimentHash: "product-row-QR-DQN.cartpole", e2eTest: "e2e.product.QR-DQN.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "QR-DQN/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "QR-DQN/mountain-car", planId: "ad3db1ff9b71ec818060329a6d1a928c5e691f33cec5aac36d25fea3e482234c", substrate: "linux-cpu", experimentHash: "product-row-QR-DQN.mountain-car", e2eTest: "e2e.product.QR-DQN.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:120000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "QR-DQN/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "QR-DQN/key-door-grid", planId: "6d460c05503090a87700a3abc41c2d2b8a44cb385dab76aeb320ca81de615527", substrate: "linux-cpu", experimentHash: "product-row-QR-DQN.key-door-grid", e2eTest: "e2e.product.QR-DQN.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:120000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "QR-DQN/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "DDPG/lunar-lander", planId: "49e0f1119a93110f6404f54e7f17c487e753dc992cd21ce23f38d2484fc8b0f0", substrate: "linux-cpu", experimentHash: "product-row-DDPG.lunar-lander", e2eTest: "e2e.product.DDPG.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:120000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "DDPG/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TD3/lunar-lander", planId: "7c467a8800795771440733dad69aa8fd34316003aa305947059a0e30539c38ec", substrate: "linux-cpu", experimentHash: "product-row-TD3.lunar-lander", e2eTest: "e2e.product.TD3.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "TD3/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "SAC/lunar-lander", planId: "8f2a49e644952b49350b70ff937b525b9d116ad2309ebe8bd82981a18a011539", substrate: "linux-cpu", experimentHash: "product-row-SAC.lunar-lander", e2eTest: "e2e.product.SAC.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "SAC/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "SAC/pendulum", planId: "17ed88f8efadb3b8373a9ba8f51478f27a3d8971215f09ff8c452b32f39f68f7", substrate: "linux-cpu", experimentHash: "product-row-SAC.pendulum", e2eTest: "e2e.product.SAC.pendulum", demoPanel: "rl-trajectory", budget: "rl-environment-steps:4000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "SAC/pendulum" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "CrossQ/lunar-lander", planId: "1e371e4cb09bfa6826436b334c600c4eee38b1e1d62b40bce0df0672c91ca2dd", substrate: "linux-cpu", experimentHash: "product-row-CrossQ.lunar-lander", e2eTest: "e2e.product.CrossQ.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "CrossQ/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TQC/lunar-lander", planId: "61459512d7eac5f5946784503562b04afc7a09eb59c7d6fb2f3504affe195caa", substrate: "linux-cpu", experimentHash: "product-row-TQC.lunar-lander", e2eTest: "e2e.product.TQC.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "TQC/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "ARS/cartpole", planId: "1b8b6067991cd505dc839a72a8eb2c2d799fb36904e7ed6efdbce8e54338cfa6", substrate: "linux-cpu", experimentHash: "product-row-ARS.cartpole", e2eTest: "e2e.product.ARS.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:800000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "ARS/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "ARS/mountain-car", planId: "8a90a9ce4a6c465c0cde3841c1eb918a0126560bbd678a681c73fee8f9545d7b", substrate: "linux-cpu", experimentHash: "product-row-ARS.mountain-car", e2eTest: "e2e.product.ARS.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:320000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "ARS/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "ARS/lunar-lander", planId: "346e16e06fd0632e205947b52e939b058de11f60330ec36bbfb057afdac78a3e", substrate: "linux-cpu", experimentHash: "product-row-ARS.lunar-lander", e2eTest: "e2e.product.ARS.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1600000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "ARS/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "ARS/key-door-grid", planId: "9e5e47efba8415453cb19fb8a1f1d3de78ff22c03977e57120bde0fac6ccb831", substrate: "linux-cpu", experimentHash: "product-row-ARS.key-door-grid", e2eTest: "e2e.product.ARS.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:320000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "ARS/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "her", name: "HER/goal-reaching", planId: "61ff4a52cb963afea5a44719466753c16bb5754a5245404f35046e2f829a7548", substrate: "linux-cpu", experimentHash: "product-row-HER.goal-reaching", e2eTest: "e2e.product.HER.goal-reaching", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2004:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "HER/goal-reaching" ], requiresTrainedArtifact: true }
  , { kind: "alphazero", name: "connect4", planId: "c2c5caf762d9b1d322d87b12ce1406a74f44d40d04b054f635814c6906338ea9", substrate: "linux-cpu", experimentHash: "product-row-connect4", e2eTest: "e2e.product.connect4", demoPanel: "connect4-human-vs-alphazero", budget: "alphazero-self-play-generations:64:self-play-generations:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "connect4" ], requiresTrainedArtifact: true }
  , { kind: "alphazero", name: "othello", planId: "e12682a93ff704f59576536fe1aa981ffdf828967b1dd0e35f7536cdc1d93c73", substrate: "linux-cpu", experimentHash: "product-row-othello", e2eTest: "e2e.product.othello", demoPanel: "connect4-human-vs-alphazero", budget: "alphazero-self-play-generations:96:self-play-generations:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "othello" ], requiresTrainedArtifact: true }
  , { kind: "alphazero", name: "hex", planId: "a44cbeba8a9cb086b88beb07f8dfd3121a94830ff37e10a19eda9d81d3c30de4", substrate: "linux-cpu", experimentHash: "product-row-hex", e2eTest: "e2e.product.hex", demoPanel: "connect4-human-vs-alphazero", budget: "alphazero-self-play-generations:128:self-play-generations:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "hex" ], requiresTrainedArtifact: true }
  , { kind: "alphazero", name: "gomoku", planId: "75437658421a71735e90f06f0ad925544be1b9d0ebe9059ba3fbabf0b2f2ca55", substrate: "linux-cpu", experimentHash: "product-row-gomoku", e2eTest: "e2e.product.gomoku", demoPanel: "connect4-human-vs-alphazero", budget: "alphazero-self-play-generations:128:self-play-generations:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "gomoku" ], requiresTrainedArtifact: true }
  , { kind: "tuning", name: "hyperparameter-tuning", planId: "4150d67ddfa20cda8b76351328560973fa713b98773cf08bb2456c2bfec56384", substrate: "linux-cpu", experimentHash: "product-row-hyperparameter-tuning", e2eTest: "e2e.product.hyperparameter-tuning", demoPanel: "hyperparameter-sweep", budget: "tuning-trials:128:trials:seed-1729", command: [ "internal", "train-and-publish-product-rows", "--linux-cpu", "--row", "hyperparameter-tuning" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "mnist-shallow-mlp", planId: "12e98286d897c2bffa211e8dd545d052ccf38c30b17cf127ab16dafe176af056", substrate: "linux-cuda", experimentHash: "product-row-mnist-shallow-mlp", e2eTest: "e2e.product.mnist-shallow-mlp", demoPanel: "mnist-live-inference", budget: "supervised-epochs:10:epochs:seed-1001", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "mnist-shallow-mlp" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "mnist-deep-mlp", planId: "e50c26ac4f22f8dc6ee88c2c101df6e00be5a95c0bdd5ad4acea8e619a765152", substrate: "linux-cuda", experimentHash: "product-row-mnist-deep-mlp", e2eTest: "e2e.product.mnist-deep-mlp", demoPanel: "mnist-live-inference", budget: "supervised-epochs:10:epochs:seed-1002", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "mnist-deep-mlp" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "mnist-lenet", planId: "99fdb2838a8bce0791aad956b292ce44b2006990565d2bb65ac1d4f19564cac0", substrate: "linux-cuda", experimentHash: "product-row-mnist-lenet", e2eTest: "e2e.product.mnist-lenet", demoPanel: "mnist-live-inference", budget: "supervised-epochs:10:epochs:seed-1003", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "mnist-lenet" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "fashion-mnist-mlp", planId: "e7af5c25ea0307b7681e17ca06e87c479c2df8e75dadf3054bb57bd2a9795d1d", substrate: "linux-cuda", experimentHash: "product-row-fashion-mnist-mlp", e2eTest: "e2e.product.fashion-mnist-mlp", demoPanel: "mnist-live-inference", budget: "supervised-epochs:10:epochs:seed-1004", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "fashion-mnist-mlp" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "fashion-mnist-resnet", planId: "9a49e054f517ab9f37cee401a3058df566b2ab64aeccb5cf39d472fb5584121d", substrate: "linux-cuda", experimentHash: "product-row-fashion-mnist-resnet", e2eTest: "e2e.product.fashion-mnist-resnet", demoPanel: "mnist-live-inference", budget: "supervised-epochs:10:epochs:seed-1005", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "fashion-mnist-resnet" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "cifar10-resnet20", planId: "24d90379e96b071da98d2245e76390e9534133c39bc1c6d22467cb4dab8bbe5b", substrate: "linux-cuda", experimentHash: "product-row-cifar10-resnet20", e2eTest: "e2e.product.cifar10-resnet20", demoPanel: "cifar-imagenet-upload", budget: "supervised-epochs:40:epochs:seed-1006", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "cifar10-resnet20" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "cifar10-resnet56", planId: "4508a75f60ecbbeab803a8de9e46e65c528d37ab8b55506dce4df95ad6c395a5", substrate: "linux-cuda", experimentHash: "product-row-cifar10-resnet56", e2eTest: "e2e.product.cifar10-resnet56", demoPanel: "cifar-imagenet-upload", budget: "supervised-epochs:40:epochs:seed-1007", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "cifar10-resnet56" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "cifar100-wide-resnet", planId: "f72fa697cc4190b48da97d278fa50531ee58d82cb1f4b2f901db4784a925ce01", substrate: "linux-cuda", experimentHash: "product-row-cifar100-wide-resnet", e2eTest: "e2e.product.cifar100-wide-resnet", demoPanel: "cifar-imagenet-upload", budget: "supervised-epochs:10:epochs:seed-1008", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "cifar100-wide-resnet" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "cifar10-vit", planId: "6434fc15428f690090d890dfe9f5135b9a58323bedaa3649fe0513e9bc11524f", substrate: "linux-cuda", experimentHash: "product-row-cifar10-vit", e2eTest: "e2e.product.cifar10-vit", demoPanel: "cifar-imagenet-upload", budget: "supervised-epochs:40:epochs:seed-1009", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "cifar10-vit" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "tiny-imagenet-resnet50", planId: "d80247123b0c95e94742d5b59808853308f7b2ca45d2d58371a1fc3d8fb11cb4", substrate: "linux-cuda", experimentHash: "product-row-tiny-imagenet-resnet50", e2eTest: "e2e.product.tiny-imagenet-resnet50", demoPanel: "cifar-imagenet-upload", budget: "supervised-epochs:15:epochs:seed-1010", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "tiny-imagenet-resnet50" ], requiresTrainedArtifact: true }
  , { kind: "supervised", name: "california-housing-mlp", planId: "97990625ee77530b993df18d8ae08a59c6571b8f2da09cbd46318cf45540953d", substrate: "linux-cuda", experimentHash: "product-row-california-housing-mlp", e2eTest: "e2e.product.california-housing-mlp", demoPanel: "generic-inference-lab", budget: "supervised-epochs:100:epochs:seed-1011", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "california-housing-mlp" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/cartpole", planId: "924c09bdef6840188d2430e2a4b232d4a99aa8d8716b605b99438b8e1cb8ed13", substrate: "linux-cuda", experimentHash: "product-row-PPO.cartpole", e2eTest: "e2e.product.PPO.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "PPO/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/mountain-car", planId: "3b42c438b9b098d6ddefe5082430e3c45a21e613d709c450930f4e2f96a799e3", substrate: "linux-cuda", experimentHash: "product-row-PPO.mountain-car", e2eTest: "e2e.product.PPO.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2457600:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "PPO/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/acrobot", planId: "b427a88808940a876c67af5015b2331f29c5997907a6fe5d24fd540482297ee4", substrate: "linux-cuda", experimentHash: "product-row-PPO.acrobot", e2eTest: "e2e.product.PPO.acrobot", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "PPO/acrobot" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/lunar-lander", planId: "37914cb981ddd15a0b07e99affc395b4f6c8d70055d855022f6db59e8d513b6c", substrate: "linux-cuda", experimentHash: "product-row-PPO.lunar-lander", e2eTest: "e2e.product.PPO.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2400000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "PPO/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/key-door-grid", planId: "65180a2523a9641f7652719388afc46c64fb4d201e24825cb52ddc36c9117d8f", substrate: "linux-cuda", experimentHash: "product-row-PPO.key-door-grid", e2eTest: "e2e.product.PPO.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "PPO/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "PPO/gridworld-deterministic", planId: "df9fc291123af632a0450a6b46d99f66e5b051b7593c57571ef2fb6d1a399ebb", substrate: "linux-cuda", experimentHash: "product-row-PPO.gridworld-deterministic", e2eTest: "e2e.product.PPO.gridworld-deterministic", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "PPO/gridworld-deterministic" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "A2C/cartpole", planId: "1774345a81c1a33445933762b3dd9d66ed985652b195785001259d8bfb866dec", substrate: "linux-cuda", experimentHash: "product-row-A2C.cartpole", e2eTest: "e2e.product.A2C.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "A2C/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "A2C/mountain-car", planId: "8a2f0d64f3960391444856315be981f73ab25cf0109665d6996b3a90db8439db", substrate: "linux-cuda", experimentHash: "product-row-A2C.mountain-car", e2eTest: "e2e.product.A2C.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "A2C/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "A2C/lunar-lander", planId: "784fd498482142f978ca7d2fde50441ea6347084cd01ac0e7dd0469a447203fe", substrate: "linux-cuda", experimentHash: "product-row-A2C.lunar-lander", e2eTest: "e2e.product.A2C.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2400000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "A2C/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "A2C/key-door-grid", planId: "8aaae5a20b6940c1b44ad2b8095e4fb64c1da88b42cad123216db27c2e93465c", substrate: "linux-cuda", experimentHash: "product-row-A2C.key-door-grid", e2eTest: "e2e.product.A2C.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "A2C/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TRPO/cartpole", planId: "8c88bf5d711da8867b138df1acd94a24e15215f37e4eb028339f9df6f944dfcd", substrate: "linux-cuda", experimentHash: "product-row-TRPO.cartpole", e2eTest: "e2e.product.TRPO.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "TRPO/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TRPO/mountain-car", planId: "5c673766bd69ab1c64c3e87c7a51759c507fa7249af4ce7b3346287a283e918d", substrate: "linux-cuda", experimentHash: "product-row-TRPO.mountain-car", e2eTest: "e2e.product.TRPO.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "TRPO/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TRPO/lunar-lander", planId: "0753f69f8af7484db399cf32074c43ab7371340987c577ec8e3fa9330f08818e", substrate: "linux-cuda", experimentHash: "product-row-TRPO.lunar-lander", e2eTest: "e2e.product.TRPO.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2400000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "TRPO/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TRPO/key-door-grid", planId: "961eb64b0bc737c5a0a42cc26bea09d9f321c71fd1c9a8ecd83e97e94bd699b8", substrate: "linux-cuda", experimentHash: "product-row-TRPO.key-door-grid", e2eTest: "e2e.product.TRPO.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "TRPO/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "MaskablePPO/cartpole", planId: "69975d618d05a428bfe9b80cab8b67b526d1c32aa59c56b58a3d12b0dbfc8c09", substrate: "linux-cuda", experimentHash: "product-row-MaskablePPO.cartpole", e2eTest: "e2e.product.MaskablePPO.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "MaskablePPO/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "MaskablePPO/mountain-car", planId: "23b2d4a4f1230a1e2ecef45756179452dfd80735cf77ed2cd743e0ed692e07b1", substrate: "linux-cuda", experimentHash: "product-row-MaskablePPO.mountain-car", e2eTest: "e2e.product.MaskablePPO.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "MaskablePPO/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "MaskablePPO/lunar-lander", planId: "e1411a7da56f93c1536250e4f4ab9fed3817c041a5c76b3b46bcc6165f7f892c", substrate: "linux-cuda", experimentHash: "product-row-MaskablePPO.lunar-lander", e2eTest: "e2e.product.MaskablePPO.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2400000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "MaskablePPO/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "MaskablePPO/key-door-grid", planId: "4fa27590841a800e72765162b4a143f9684bd9fab4eb0da90c838743a5b4e8fb", substrate: "linux-cuda", experimentHash: "product-row-MaskablePPO.key-door-grid", e2eTest: "e2e.product.MaskablePPO.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "MaskablePPO/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "RecurrentPPO/cartpole", planId: "8e4de399e9d39dc5e3ce584169c466799382e2440ef480b312f4300dc4ea574e", substrate: "linux-cuda", experimentHash: "product-row-RecurrentPPO.cartpole", e2eTest: "e2e.product.RecurrentPPO.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "RecurrentPPO/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "RecurrentPPO/mountain-car", planId: "89e9c0599311801a332dfb3747f629ca05026aaa8f3277f46b15bf60c21d4255", substrate: "linux-cuda", experimentHash: "product-row-RecurrentPPO.mountain-car", e2eTest: "e2e.product.RecurrentPPO.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1228800:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "RecurrentPPO/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "RecurrentPPO/lunar-lander", planId: "2d6ba7fc2a4fa84149af0cbea30cadad32b90d31e998afa4fd21d31060f1f851", substrate: "linux-cuda", experimentHash: "product-row-RecurrentPPO.lunar-lander", e2eTest: "e2e.product.RecurrentPPO.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2400000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "RecurrentPPO/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "RecurrentPPO/key-door-grid", planId: "23626306c9f95a081a867267a98d525db6e8864f033c5df0314cf5ab72b6149b", substrate: "linux-cuda", experimentHash: "product-row-RecurrentPPO.key-door-grid", e2eTest: "e2e.product.RecurrentPPO.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:307200:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "RecurrentPPO/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "DQN/cartpole", planId: "1ee22eef188a1060fb5b4d5cf5366d95747511837f2876b9ddd77548ab996394", substrate: "linux-cuda", experimentHash: "product-row-DQN.cartpole", e2eTest: "e2e.product.DQN.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "DQN/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "DQN/mountain-car", planId: "8673508861d21393a6c754ee5e347c603d2da70df9cdb2b5a5d20fdf1a6b87fe", substrate: "linux-cuda", experimentHash: "product-row-DQN.mountain-car", e2eTest: "e2e.product.DQN.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:120000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "DQN/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "DQN/key-door-grid", planId: "fdf761106511ed965db5d55d52b63d4fe308010b45a5199c2f66d9bf47a8a095", substrate: "linux-cuda", experimentHash: "product-row-DQN.key-door-grid", e2eTest: "e2e.product.DQN.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "DQN/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "QR-DQN/cartpole", planId: "30bcf28f392a352af26e2a410262b78e54e330901203018921004d38440a7802", substrate: "linux-cuda", experimentHash: "product-row-QR-DQN.cartpole", e2eTest: "e2e.product.QR-DQN.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "QR-DQN/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "QR-DQN/mountain-car", planId: "7c48078bad897bb56b5827239658d34793026b7c59adb8f24f33cec80236e985", substrate: "linux-cuda", experimentHash: "product-row-QR-DQN.mountain-car", e2eTest: "e2e.product.QR-DQN.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:120000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "QR-DQN/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "QR-DQN/key-door-grid", planId: "3b7d131fe3a412663f2a069b525ff6fe76aec61dc0bc1beb20074dbf70559658", substrate: "linux-cuda", experimentHash: "product-row-QR-DQN.key-door-grid", e2eTest: "e2e.product.QR-DQN.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:120000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "QR-DQN/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "DDPG/lunar-lander", planId: "1d31d8818665ff2ecc2b1efcb0ecf95f1daff75054517ed0d46d42635a26741e", substrate: "linux-cuda", experimentHash: "product-row-DDPG.lunar-lander", e2eTest: "e2e.product.DDPG.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:120000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "DDPG/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TD3/lunar-lander", planId: "3c44d873a0be47f2aebdc0fa4d419457662de8763a4d3abd7e3882d97d49bf4e", substrate: "linux-cuda", experimentHash: "product-row-TD3.lunar-lander", e2eTest: "e2e.product.TD3.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "TD3/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "SAC/lunar-lander", planId: "28d37f6be4bcc75265b7e4c17a1604f30fb37b99acbd87638a87d414f209b2f8", substrate: "linux-cuda", experimentHash: "product-row-SAC.lunar-lander", e2eTest: "e2e.product.SAC.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "SAC/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "SAC/pendulum", planId: "f6f0e1a656ea82bec956f328f36603bb57e2ae2f63c4392aa5e4cde2f1b57f8f", substrate: "linux-cuda", experimentHash: "product-row-SAC.pendulum", e2eTest: "e2e.product.SAC.pendulum", demoPanel: "rl-trajectory", budget: "rl-environment-steps:4000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "SAC/pendulum" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "CrossQ/lunar-lander", planId: "d1246d7b981ee46f5d6c72fa90d20c52fcb0a39d4abaae2d3146b2838e18bdd0", substrate: "linux-cuda", experimentHash: "product-row-CrossQ.lunar-lander", e2eTest: "e2e.product.CrossQ.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "CrossQ/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "TQC/lunar-lander", planId: "195e89f8a3739469992c6a0a0cc232269fed4f8d4c2ffe335319e06e47c2c3f3", substrate: "linux-cuda", experimentHash: "product-row-TQC.lunar-lander", e2eTest: "e2e.product.TQC.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:50000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "TQC/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "ARS/cartpole", planId: "67ee36abd17fa17cc4b9bf93f98009ad7c8447b67b868aeb74ea5bf9d44f5f14", substrate: "linux-cuda", experimentHash: "product-row-ARS.cartpole", e2eTest: "e2e.product.ARS.cartpole", demoPanel: "rl-trajectory", budget: "rl-environment-steps:800000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "ARS/cartpole" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "ARS/mountain-car", planId: "c79efc7b827b2b562c124af6c491b9ee114421b9c8f89353ac0470bbd8f22747", substrate: "linux-cuda", experimentHash: "product-row-ARS.mountain-car", e2eTest: "e2e.product.ARS.mountain-car", demoPanel: "rl-trajectory", budget: "rl-environment-steps:320000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "ARS/mountain-car" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "ARS/lunar-lander", planId: "51e201a01fa79ebadae1e7d3e10c0925a21d0b957af72aed1e063a5853d1d7b4", substrate: "linux-cuda", experimentHash: "product-row-ARS.lunar-lander", e2eTest: "e2e.product.ARS.lunar-lander", demoPanel: "rl-trajectory", budget: "rl-environment-steps:1600000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "ARS/lunar-lander" ], requiresTrainedArtifact: true }
  , { kind: "rl", name: "ARS/key-door-grid", planId: "fe3520bfbbedb158625b166ab7024b027031cddb21e722d927a4471fdb577c39", substrate: "linux-cuda", experimentHash: "product-row-ARS.key-door-grid", e2eTest: "e2e.product.ARS.key-door-grid", demoPanel: "rl-trajectory", budget: "rl-environment-steps:320000:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "ARS/key-door-grid" ], requiresTrainedArtifact: true }
  , { kind: "her", name: "HER/goal-reaching", planId: "e81255a47ee47d1b61e3699657a28ce61bd2261bbe629f14494163fa13d480db", substrate: "linux-cuda", experimentHash: "product-row-HER.goal-reaching", e2eTest: "e2e.product.HER.goal-reaching", demoPanel: "rl-trajectory", budget: "rl-environment-steps:2004:environment-steps:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "HER/goal-reaching" ], requiresTrainedArtifact: true }
  , { kind: "alphazero", name: "connect4", planId: "48dfb77931d2e665aed13b0c5d5f4adf1feb9dfa25c43b473275e1b8a10d92d0", substrate: "linux-cuda", experimentHash: "product-row-connect4", e2eTest: "e2e.product.connect4", demoPanel: "connect4-human-vs-alphazero", budget: "alphazero-self-play-generations:64:self-play-generations:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "connect4" ], requiresTrainedArtifact: true }
  , { kind: "alphazero", name: "othello", planId: "31c605d1ad490662241fc5a7d33136e1d5acaf1ae656c9ddace0b3c624bbf498", substrate: "linux-cuda", experimentHash: "product-row-othello", e2eTest: "e2e.product.othello", demoPanel: "connect4-human-vs-alphazero", budget: "alphazero-self-play-generations:96:self-play-generations:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "othello" ], requiresTrainedArtifact: true }
  , { kind: "alphazero", name: "hex", planId: "ab803756c5cdf538c31f7e669406c920a0be8bb15a0cad5b8e9b02b47140e7a1", substrate: "linux-cuda", experimentHash: "product-row-hex", e2eTest: "e2e.product.hex", demoPanel: "connect4-human-vs-alphazero", budget: "alphazero-self-play-generations:128:self-play-generations:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "hex" ], requiresTrainedArtifact: true }
  , { kind: "alphazero", name: "gomoku", planId: "585212b9e89b2f43dba525a5ab49d8b20630866a789b00787aae824b5180f621", substrate: "linux-cuda", experimentHash: "product-row-gomoku", e2eTest: "e2e.product.gomoku", demoPanel: "connect4-human-vs-alphazero", budget: "alphazero-self-play-generations:128:self-play-generations:seed-42", command: [ "internal", "train-and-publish-product-rows", "--linux-cuda", "--row", "gomoku" ], requiresTrainedArtifact: true }
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
