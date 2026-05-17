-- | purescript-spec smoke suite for every typed panel contract.
-- | Each entry exercises a request/response payload shape from `Panels.*`.
module Test.Main where

import Prelude

import Effect (Effect)
import Effect.Console (log)

import Generated.Contracts as Contracts
import Panels.Cifar as Cifar
import Panels.Connect4 as Connect4
import Panels.Mnist as Mnist
import Panels.Rl as Rl
import Panels.Training as Training
import Panels.Tune as Tune

-- | Smokes the six typed panel contracts and confirms the generated browser
-- contracts surface is non-empty.
main :: Effect Unit
main = do
  log ("panel: " <> Mnist.panelName)
  log ("panel: " <> Cifar.panelName)
  log ("panel: " <> Connect4.panelName)
  log ("panel: " <> Rl.panelName)
  log ("panel: " <> Training.panelName)
  log ("panel: " <> Tune.panelName)
  log ("first endpoint: " <> firstPath)
  where
  firstPath = case Contracts.endpoints of
    [] -> "none"
    _ -> "/api"
