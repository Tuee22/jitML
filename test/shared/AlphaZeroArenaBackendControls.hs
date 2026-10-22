{-# LANGUAGE OverloadedStrings #-}

-- | Register this control inside each genuine selected backend lane. It runs
-- actual MCTS neural leaves and obtains the same supplied device's witness;
-- its one-move horizon draw is not a trained-policy or convergence assertion.
module AlphaZeroArenaBackendControls (assertAlphaZeroArenaOnDevice) where

import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.Vector.Unboxed qualified as VU
import JitML.Numerics.MlpDevice (MlpDevice (..))
import JitML.Product.DeviceWitness qualified as Witness
import JitML.RL.AlphaZero qualified as Game
import JitML.RL.AlphaZero.PolicyValueNet qualified as Net
import JitML.Substrate (Substrate)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, (@?=))

assertAlphaZeroArenaOnDevice :: Substrate -> MlpDevice -> Assertion
assertAlphaZeroArenaOnDevice substrate device = do
  -- These are two independently valid declared encoders. The actual canonical
  -- compact constructor remains8; the existing full-board diagnostic uses43.
  runWidth (Game.observationSizeFor "connect4")
  runWidth 43
  witness <- expectRight =<< mlpdExecutionWitness device
  case witness of
    Nothing -> assertFailure "a pure/reference arena cannot satisfy an actual backend control"
    Just observed -> Witness.witnessSubstrate observed @?= substrate
 where
  runWidth width = do
    calls <- newIORef []
    let net = Net.initPolicyValueNet width 7 2 42
        observedDevice =
          device
            { mlpdForward = \params input -> do
                params @?= Net.pvnParams net
                modifyIORef' calls (<> [input])
                mlpdForward device params input
            }
    evaluated <-
      expectRight
        =<< Net.arenaEvaluationAgainstUniformOnDeviceFrom Game.initialConnect4 observedDevice net 1 1 7919
    Net.arenaEvaluationScore evaluated @?= 0.5
    case Net.arenaEvaluationOutcomes evaluated of
      [episode] -> do
        Net.arenaEpisodeIndex episode @?= 0
        Net.arenaEpisodeOutcome episode @?= Game.GameDraw
        Net.arenaEpisodeDecisionCount episode @?= 1
        Net.arenaEpisodeHorizonTruncated episode @?= True
        length (Game.gameMoves (Net.arenaEpisodeFinalState episode)) @?= 1
      _ -> assertFailure "actual backend arena did not return its complete singleton game"
    inputs <- readIORef calls
    assertBool "actual arena never called the supplied backend" (not (null inputs))
    assertBool "actual backend received a foreign encoder width" (all ((== width) . VU.length) inputs)
    case inputs of
      first : _ -> first @?= Net.encodeGameState net Game.initialConnect4
      [] -> assertFailure "no actual backend observation"

expectRight :: (Show err) => Either err value -> IO value
expectRight = either (\failure -> assertFailure (show failure) >> fail "unreachable") pure
