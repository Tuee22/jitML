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
import Panels.Cifar as Cifar
import Panels.Connect4 as Connect4
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

    it "CIFAR upload request pins the panel name and default dataset" do
      let req = Cifar.renderUploadRequest "base64"
      req.panel `shouldEqual` Cifar.panelName
      req.datasetName `shouldEqual` Cifar.defaultDataset

    it "Connect 4 move request pins the panel name and simulation budget" do
      let req = Connect4.renderMoveRequest [ 3, 4 ] 1
      req.panel `shouldEqual` Connect4.panelName
      req.humanIsPlayer `shouldEqual` 1
      req.simulationsPerMove `shouldEqual` Connect4.defaultSimulations
      length req.moves `shouldEqual` 2

    it "RL frame pins the panel name and observation hash" do
      let frame = Rl.renderFrame 0 7 1.5 false "42"
      frame.panel `shouldEqual` Rl.panelName
      frame.observationHash `shouldEqual` "42"
      frame.reward `shouldEqual` 1.5

    it "RL parser consumes generated animation-frame contracts" do
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
      Rl.parseRlFrame payload
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
      Rl.parseRlFrame "data: placeholder" `shouldEqual` Nothing

    it "Training frame pins the panel name and validation loss" do
      let frame = Training.renderFrame "sha" 4 0.5 0.25 1234
      frame.panel `shouldEqual` Training.panelName
      frame.epoch `shouldEqual` 4
      frame.validationLoss `shouldEqual` 0.25

    it "Tune trial frame pins the panel name and trial seed" do
      let frame = Tune.renderTrialFrame 7 4242 0.875 false "{}"
      frame.panel `shouldEqual` Tune.panelName
      frame.trialSeed `shouldEqual` 4242
      frame.pruned `shouldEqual` false

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
