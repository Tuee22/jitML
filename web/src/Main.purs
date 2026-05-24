-- | Halogen shell entrypoint. Reads `location.hash` (without the leading
-- | `#`) and mounts the matching `Panels.*` component. Falls back to the
-- | MNIST panel when no hash is set. The hash routing keeps the demo
-- | bundle a single static artifact while the Playwright e2e matrix
-- | selects which panel each test exercises.
module Main where

import Prelude

import Data.String as String
import Effect (Effect)
import Panels.Cifar as Cifar
import Panels.Connect4 as Connect4
import Panels.Mnist as Mnist
import Panels.Rl as Rl
import Panels.Training as Training
import Panels.Tune as Tune
import Web.HTML (window)
import Web.HTML.Location as Location
import Web.HTML.Window as Window

main :: Effect Unit
main = do
  w <- window
  loc <- Window.location w
  hashRaw <- Location.hash loc
  let hash = String.drop 1 hashRaw
  case hash of
    h
      | h == Cifar.panelName -> Cifar.mount
      | h == Connect4.panelName -> Connect4.mount
      | h == Rl.panelName -> Rl.mount
      | h == Training.panelName -> Training.mount
      | h == Tune.panelName -> Tune.mount
      | otherwise -> Mnist.mount
