-- | purescript-spec smoke suite for every typed panel contract. Each
-- | describe block exercises the payload-shape contracts the panel will
-- | exchange with the daemon once `/api/inference`, `/api/ws`, and
-- | `/api/connect4/move` are wired through Phase 13 Sprint 13.13.
module Test.Main where

import Prelude

import Data.Array (any, length)
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Generated.AdminPortals as AdminPortals
import Generated.Contracts as Contracts
import Panels.CheckpointCompare as CheckpointCompare
import Panels.Cifar as Cifar
import Panels.Connect4 as Connect4
import Panels.GenericInference as GenericInference
import Panels.Mnist as Mnist
import Panels.Rl as Rl
import Panels.Training as Training
import Panels.Tune as Tune
import Test.Spec (describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)
import Test.Spec.Reporter (consoleReporter)
import Test.Spec.Runner.Node (runSpecAndExitProcess)

main :: Effect Unit
main = runSpecAndExitProcess [ consoleReporter ] do
  describe "panel typed contracts" do
    it "MNIST renderRequest pins the panel name and model id" do
      let req = Mnist.renderRequest [ 1, 2, 3 ]
      req.panel `shouldEqual` Mnist.panelName
      req.modelId `shouldEqual` Mnist.defaultModelId
      length req.canvasPixels `shouldEqual` 3

    it "generated REST request renderers emit stable browser envelopes" do
      Contracts.renderBrowserInferenceRequest Mnist.panelName Mnist.defaultModelId Mnist.defaultExperimentHash [ 1.0, 2.0 ]
        `shouldEqual`
          ( "kind: BrowserInferenceRequest\n"
              <> "panel: mnist-live-inference\n"
              <> "model-id: mnist-deep-mlp\n"
              <> "experiment-hash: mnist-deep-mlp\n"
              <> "input: 1.0,2.0\n"
          )
      Contracts.renderBrowserImageRequest Cifar.panelName Cifar.defaultDataset Cifar.defaultExperimentHash "" [ 1.0, 2.0 ]
        `shouldEqual`
          ( "kind: BrowserImageRequest\n"
              <> "panel: cifar-imagenet-upload\n"
              <> "dataset: CIFAR-10\n"
              <> "experiment-hash: cifar-imagenet\n"
              <> "image-base64: \n"
              <> "input: 1.0,2.0\n"
          )
      Contracts.renderBrowserGenericInferenceRequest GenericInference.panelName GenericInference.defaultExperimentHash [ 1.0, 2.0 ]
        `shouldEqual`
          ( "kind: BrowserGenericInferenceRequest\n"
              <> "panel: generic-inference-lab\n"
              <> "experiment-hash: generic-tensor-demo\n"
              <> "input: 1.0,2.0\n"
          )
      Contracts.renderBrowserCheckpointCompareRequest
        CheckpointCompare.panelName
        CheckpointCompare.defaultBaselineExperimentHash
        CheckpointCompare.defaultCandidateExperimentHash
        [ 1.0, 2.0 ]
        `shouldEqual`
          ( "kind: BrowserCheckpointCompareRequest\n"
              <> "panel: checkpoint-compare-lab\n"
              <> "baseline-experiment-hash: generic-tensor-demo\n"
              <> "candidate-experiment-hash: generic-tensor-demo-candidate\n"
              <> "input: 1.0,2.0\n"
          )
      Contracts.renderBrowserAdversarialMoveRequest Connect4.panelName "connect4" Connect4.defaultExperimentHash [ 3, 4 ] 1 Connect4.defaultSimulations
        `shouldEqual`
          ( "kind: BrowserAdversarialMoveRequest\n"
              <> "panel: connect4-human-vs-alphazero\n"
              <> "game: connect4\n"
              <> "experiment-hash: connect4-alphazero\n"
              <> "moves: 3,4\n"
              <> "human-is-player: 1\n"
              <> "simulations-per-move: 400\n"
          )

    it "CIFAR upload request pins the panel name and default dataset" do
      let req = Cifar.renderUploadRequest "base64"
      req.panel `shouldEqual` Cifar.panelName
      req.datasetName `shouldEqual` Cifar.defaultDataset

    it "Generic inference request pins the panel name and experiment hash" do
      let req = GenericInference.renderRequest [ 1.0, 2.0 ]
      req.panel `shouldEqual` GenericInference.panelName
      req.experimentHash `shouldEqual` GenericInference.defaultExperimentHash
      length req.input `shouldEqual` 2

    it "Checkpoint compare request pins both experiment hashes" do
      let req = CheckpointCompare.renderRequest [ 1.0, 2.0 ]
      req.panel `shouldEqual` CheckpointCompare.panelName
      req.baselineExperimentHash `shouldEqual` CheckpointCompare.defaultBaselineExperimentHash
      req.candidateExperimentHash `shouldEqual` CheckpointCompare.defaultCandidateExperimentHash
      length req.input `shouldEqual` 2

    it "Connect 4 move request pins the panel name and simulation budget" do
      let req = Connect4.renderMoveRequest [ 3, 4 ] 1
      req.panel `shouldEqual` Connect4.panelName
      req.game `shouldEqual` "connect4"
      req.experimentHash `shouldEqual` Connect4.defaultExperimentHash
      req.humanIsPlayer `shouldEqual` 1
      req.simulationsPerMove `shouldEqual` Connect4.defaultSimulations
      length req.moves `shouldEqual` 2
      length Connect4.canonicalGames `shouldEqual` 4

    it "RL frame pins the panel name and observation hash" do
      let frame = Rl.renderFrame 0 7 1.5 false "42"
      frame.panel `shouldEqual` Rl.panelName
      frame.observationHash `shouldEqual` "42"
      frame.reward `shouldEqual` 1.5

    it "generated RL parser consumes animation-frame contracts" do
      let
        payload =
          "kind: RlAnimationFrame\n"
            <> "experiment-hash: sha256:cartpole\n"
            <> "environment: cartpole\n"
            <> "episode: 2\n"
            <> "step: 7\n"
            <> "reward: 1.5\n"
            <> "done: False\n"
            <> "action: 1\n"
            <> "observation: 0.0,0.1,0.2,0.3\n"
            <> "action-probabilities: 0.25,0.75\n"
            <> "observation-hash: 42\n"
            <> "replay-cursor: 207\n"
            <> "timestamp-ns: 1234\n"
        replayPayload =
          "kind: RlReplayFrame\n"
            <> "experiment-hash: sha256:cartpole\n"
            <> "replay-id: replay-1\n"
            <> "environment: cartpole\n"
            <> "episode: 2\n"
            <> "step: 8\n"
            <> "action: 0\n"
            <> "reward: 1.25\n"
            <> "done: false\n"
            <> "observation: 0.0,0.1\n"
            <> "next-observation: 0.2,0.3\n"
            <> "policy-version: 44\n"
            <> "observation-hash: 43\n"
            <> "timestamp-ns: 1235\n"
      Contracts.parseRlAnimationFrame payload
        `shouldEqual` Just
          ( Contracts.renderRlAnimationFrame
              "sha256:cartpole"
              "cartpole"
              2
              7
              1.5
              false
              1
              [ 0.0, 0.1, 0.2, 0.3 ]
              [ 0.25, 0.75 ]
              "42"
              "207"
              "1234"
          )
      Contracts.parseRlReplayFrame replayPayload
        `shouldEqual` Just
          ( Contracts.renderRlReplayFrame
              "sha256:cartpole"
              "replay-1"
              "cartpole"
              2
              8
              0
              1.25
              false
              [ 0.0, 0.1 ]
              [ 0.2, 0.3 ]
              "44"
              "43"
              "1235"
          )
      Contracts.parseRlAnimationFrame "data: placeholder" `shouldEqual` Nothing
      Contracts.parseRlReplayFrame "data: placeholder" `shouldEqual` Nothing

    it "generated REST parsers reject marker responses and decode typed payloads" do
      let
        inferencePayload =
          "kind: InferenceResult\n"
            <> "panel: mnist-live-inference\n"
            <> "model-id: mnist-deep-mlp\n"
            <> "checkpoint-sha: sha256:mnist\n"
            <> "top-class: 7\n"
            <> "confidence: 0.91\n"
            <> "latency-ms: 4.5\n"
            <> "probabilities: 0.01,0.09,0.90\n"
            <> "output: 0.1,0.2\n"
            <> "status: ok\n"
        imagePayload =
          "kind: ImageInferenceResult\n"
            <> "panel: cifar-imagenet-upload\n"
            <> "dataset: CIFAR-10\n"
            <> "checkpoint-sha: sha256:cifar\n"
            <> "top-k: 3,5,8\n"
            <> "probabilities: 0.5,0.3,0.2\n"
            <> "preprocessing-ms: 1.0\n"
            <> "inference-ms: 2.0\n"
            <> "status: ok\n"
        movePayload =
          "kind: AdversarialMoveResult\n"
            <> "panel: connect4-human-vs-alphazero\n"
            <> "game: connect4\n"
            <> "chosen-column: 4\n"
            <> "legal-moves: 0,1,2,3,4,5,6\n"
            <> "visit-counts: 1,2,3,4,5,6,7\n"
            <> "policy-priors: 0.1,0.1,0.1,0.2,0.3,0.1,0.1\n"
            <> "value-estimate: 0.42\n"
            <> "game-over: false\n"
            <> "transcript-id: transcript-1\n"
        genericPayload =
          "kind: GenericInferenceResult\n"
            <> "panel: generic-inference-lab\n"
            <> "experiment-hash: generic-tensor-demo\n"
            <> "checkpoint-sha: sha256:generic\n"
            <> "latency-ms: 2.25\n"
            <> "output: 0.1,0.2,0.3\n"
            <> "status: ok\n"
        comparePayload =
          "kind: CheckpointCompareResult\n"
            <> "panel: checkpoint-compare-lab\n"
            <> "baseline-checkpoint-sha: sha256:baseline\n"
            <> "candidate-checkpoint-sha: sha256:candidate\n"
            <> "baseline-output: 0.1,0.2\n"
            <> "candidate-output: 0.3,0.2\n"
            <> "max-abs-delta: 0.2\n"
            <> "mean-abs-delta: 0.1\n"
            <> "latency-ms: 4.5\n"
            <> "status: ok\n"
      Contracts.parseInferenceResult inferencePayload
        `shouldEqual` Just
          ( Contracts.renderInferenceResult
              Mnist.panelName
              Mnist.defaultModelId
              "sha256:mnist"
              7
              0.91
              4.5
              [ 0.01, 0.09, 0.90 ]
              [ 0.1, 0.2 ]
              "ok"
          )
      Contracts.parseImageInferenceResult imagePayload
        `shouldEqual` Just
          ( Contracts.renderImageInferenceResult
              Cifar.panelName
              Cifar.defaultDataset
              "sha256:cifar"
              [ 3, 5, 8 ]
              [ 0.5, 0.3, 0.2 ]
              1.0
              2.0
              "ok"
          )
      Contracts.parseAdversarialMoveResult movePayload
        `shouldEqual` Just
          ( Contracts.renderAdversarialMoveResult
              Connect4.panelName
              "connect4"
              4
              [ 0, 1, 2, 3, 4, 5, 6 ]
              [ 1, 2, 3, 4, 5, 6, 7 ]
              [ 0.1, 0.1, 0.1, 0.2, 0.3, 0.1, 0.1 ]
              0.42
              false
              "transcript-1"
          )
      Contracts.parseGenericInferenceResult genericPayload
        `shouldEqual` Just
          ( Contracts.renderGenericInferenceResult
              GenericInference.panelName
              GenericInference.defaultExperimentHash
              "sha256:generic"
              2.25
              [ 0.1, 0.2, 0.3 ]
              "ok"
          )
      Contracts.parseCheckpointCompareResult comparePayload
        `shouldEqual` Just
          ( Contracts.renderCheckpointCompareResult
              CheckpointCompare.panelName
              "sha256:baseline"
              "sha256:candidate"
              [ 0.1, 0.2 ]
              [ 0.3, 0.2 ]
              0.2
              0.1
              4.5
              "ok"
          )
      Contracts.parseInferenceResult "prediction: value=0" `shouldEqual` Nothing
      Contracts.parseImageInferenceResult "image: topK=0,1,2" `shouldEqual` Nothing
      Contracts.parseAdversarialMoveResult "move: 3" `shouldEqual` Nothing
      Contracts.parseGenericInferenceResult "prediction: generic" `shouldEqual` Nothing
      Contracts.parseCheckpointCompareResult "compare: generic" `shouldEqual` Nothing

    it "Training frame pins the panel name and validation loss" do
      let frame = Training.renderFrame "sha" 4 0.5 0.25 1234
      frame.panel `shouldEqual` Training.panelName
      frame.epoch `shouldEqual` 4
      frame.validationLoss `shouldEqual` 0.25

    it "generated training parser rejects default stream placeholders" do
      let
        payload =
          "kind: TrainingEventFrame\n"
            <> "experiment-hash: sha256:train\n"
            <> "epoch: 4\n"
            <> "step: 44\n"
            <> "training-loss: 0.5\n"
            <> "validation-loss: 0.25\n"
            <> "throughput: 128.0\n"
            <> "device: linux-cpu\n"
            <> "checkpoint-sha: sha256:ckpt\n"
            <> "tensorboard-url: /tensorboard\n"
            <> "timestamp-ns: 1234\n"
      Contracts.parseTrainingEventFrame payload
        `shouldEqual` Just
          ( Contracts.renderTrainingEventFrame
              "sha256:train"
              4
              44
              0.5
              0.25
              128.0
              "linux-cpu"
              "sha256:ckpt"
              "/tensorboard"
              "1234"
          )
      Contracts.parseTrainingEventFrame "data: placeholder" `shouldEqual` Nothing

    it "Tune trial frame pins the panel name and trial seed" do
      let frame = Tune.renderTrialFrame 7 4242 0.875 false "{}"
      frame.panel `shouldEqual` Tune.panelName
      frame.trialSeed `shouldEqual` 4242
      frame.pruned `shouldEqual` false

    it "generated tuning parser rejects default stream placeholders" do
      let
        payload =
          "kind: TuneTrialFrame\n"
            <> "sweep-id: sweep-1\n"
            <> "trial-index: 7\n"
            <> "trial-seed: 4242\n"
            <> "objective: 0.875\n"
            <> "pruned: false\n"
            <> "sampler: TPE\n"
            <> "scheduler: median\n"
            <> "pruner: none\n"
            <> "parameters-json: {}\n"
            <> "checkpoint-sha: sha256:tune\n"
        donePayload =
          "kind: TuneSweepDoneFrame\n"
            <> "sweep-id: sweep-1\n"
            <> "trials-completed: 8\n"
            <> "trials-pruned: 1\n"
            <> "best-objective: 0.91\n"
            <> "promoted-checkpoint-sha: sha256:best\n"
      Contracts.parseTuneTrialFrame payload
        `shouldEqual` Just
          ( Contracts.renderTuneTrialFrame
              "sweep-1"
              7
              4242
              0.875
              false
              "TPE"
              "median"
              "none"
              "{}"
              "sha256:tune"
          )
      Contracts.parseTuneSweepDoneFrame donePayload
        `shouldEqual` Just
          (Contracts.renderTuneSweepDoneFrame "sweep-1" 8 1 0.91 "sha256:best")
      Contracts.parseTuneTrialFrame "data: placeholder" `shouldEqual` Nothing

    it "generated workflow commands render daemon command envelopes" do
      Contracts.renderStartTrainingCommand "training-demo" "experiments/mnist.dhall" 1 2 32
        `shouldEqual`
          ( "kind: StartTraining\n"
              <> "experiment-hash: training-demo\n"
              <> "dhall-object-key: experiments/mnist.dhall\n"
              <> "substrate: live\n"
              <> "seed: 1\n"
              <> "epochs: 2\n"
              <> "batch-size: 32\n"
          )
      Contracts.renderStopTrainingCommand "training-demo" false
        `shouldEqual`
          ( "kind: StopTraining\n"
              <> "experiment-hash: training-demo\n"
              <> "drain: False\n"
          )
      Contracts.renderStartRlCommand "rl-demo" "ppo" "cartpole" 1 128 4
        `shouldEqual`
          ( "kind: StartRLRun\n"
              <> "experiment-hash: rl-demo\n"
              <> "algorithm: ppo\n"
              <> "environment: cartpole\n"
              <> "substrate: live\n"
              <> "seed: 1\n"
              <> "max-steps: 128\n"
              <> "eval-episodes: 4\n"
          )
      Contracts.renderStartTuneCommand "tune-demo" "experiments/mnist-tune.dhall" 1 8 100 "TPE" "median" "none"
        `shouldEqual`
          ( "kind: StartSweep\n"
              <> "experiment-hash: tune-demo\n"
              <> "dhall-object-key: experiments/mnist-tune.dhall\n"
              <> "substrate: live\n"
              <> "sweep-seed: 1\n"
              <> "trial-budget: 8\n"
              <> "budget-per-trial: 100\n"
              <> "sampler: TPE\n"
              <> "scheduler: median\n"
              <> "pruner: none\n"
          )
      Contracts.parseWorkflowCommandAck
        "kind: WorkflowCommandAck\nrun-id: training-demo\ncommand: StopTraining\nstatus: published\n"
        `shouldEqual` Just (Contracts.renderWorkflowCommandAck "training-demo" "StopTraining" "published")
      Contracts.parseWorkflowStatus
        "kind: WorkflowStatus\npanel: training-progress\nrun-id: training-demo\nstatus: running\ndetail: epoch 1\n"
        `shouldEqual` Just (Contracts.renderWorkflowStatus Training.panelName "training-demo" "running" "epoch 1")

  describe "generated browser contracts" do
    it "generated endpoints catalog is non-empty" do
      Contracts.endpoints `shouldSatisfy` (\eps -> length eps > 0)

    it "generated admin portals catalog covers the six bundled portals" do
      length AdminPortals.adminPortals `shouldEqual` 6
      AdminPortals.adminPortals `shouldSatisfy`
        any (\p -> p.name == "grafana" && p.path == "/grafana")
      AdminPortals.adminPortals `shouldSatisfy`
        any (\p -> p.name == "prometheus" && p.path == "/prometheus")
      AdminPortals.adminPortals `shouldSatisfy`
        any (\p -> p.name == "tensorboard" && p.path == "/tensorboard")
      AdminPortals.adminPortals `shouldSatisfy`
        any (\p -> p.name == "harbor-portal" && p.path == "/harbor")
      AdminPortals.adminPortals `shouldSatisfy`
        any (\p -> p.name == "minio-console" && p.path == "/minio/console")
      AdminPortals.adminPortals `shouldSatisfy`
        any (\p -> p.name == "pulsar-admin" && p.path == "/pulsar/admin")
