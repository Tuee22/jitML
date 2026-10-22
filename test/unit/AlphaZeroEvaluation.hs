{-# LANGUAGE OverloadedStrings #-}

-- | Offline controls for the real arena/oracle entry points. Injected devices
-- are structural controls, not provider/hardware or convergence evidence.
module AlphaZeroEvaluation (alphaZeroEvaluationTests) where

import Control.Exception (IOException, try)
import Control.Monad (forM_)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import JitML.Numerics.Mlp qualified as Mlp
import JitML.Numerics.MlpDevice (MlpDevice (..), pureReferenceMlpDevice)
import JitML.RL.AlphaZero qualified as Game
import JitML.RL.AlphaZero.Mcts qualified as Mcts
import JitML.RL.AlphaZero.PolicyValueNet qualified as Net
import System.Random qualified as Random
import System.Timeout (timeout)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

alphaZeroEvaluationTests :: TestTree
alphaZeroEvaluationTests =
  testGroup
    "selected-device AlphaZero arena evaluation"
    [ testCase
        "actual canonical eight-input and diagnostic forty-three-input networks use supplied leaf callbacks"
        $ forM_ [Game.observationSizeFor "connect4", 43]
        $ \width -> do
          calls <- newIORef []
          let net = Net.initPolicyValueNet width 7 2 17
              device =
                pureReferenceMlpDevice
                  { mlpdForward = \params input -> do
                      params @?= Net.pvnParams net
                      modifyIORef' calls (<> [input])
                      mlpdForward pureReferenceMlpDevice params input
                  }
          observed <-
            expectRight =<< Net.arenaEvaluationAgainstUniformOnDeviceFrom Game.initialConnect4 device net 2 2 91
          Net.arenaEvaluationScore observed
            @?= Net.arenaWinRateAgainstUniformFrom Game.initialConnect4 net 2 2 91
          Net.arenaEvaluationOutcomes observed @?= expectedTwoMoveGames net 91
          inputs <- readIORef calls
          assertBool "arena did not execute real supplied oracle callbacks" (length inputs > 2)
          assertBool
            "oracle input width did not use the actual declared encoder"
            (all ((== width) . VU.length) inputs)
          case inputs of
            first : _ -> first @?= Net.encodeGameState net Game.initialConnect4
            [] -> assertFailure "no observed leaf input"
          Game.observationSizeFor "connect4" @?= 8
          VU.length (Net.encodeConnect4Board Game.initialConnect4) @?= 43
    , testCase "all four actual canonical initializers retain valid shape masks and scalar value heads" $
        forM_ ["connect4", "othello", "hex", "gomoku"] $ \game -> do
          calls <- newIORef (0 :: Int)
          let state = Game.initialStateFor game
              net = Net.initPolicyValueNet (Game.observationSizeFor game) (Game.actionCountFor game) 2 42
              device = countingDevice calls pureReferenceMlpDevice
          actual <- expectRight =<< Net.networkPriorOracleWithDevice device net state []
          actual @?= Net.networkPriorOracle net state []
          Mcts.evalPlayerToMove actual @?= Just 1
          length (Mcts.evalPriors actual) @?= Game.actionCountFor game
          assertBool "legal masked prior has no mass" (sum (Mcts.evalPriors actual) > 0)
          readIORef calls >>= (@?= 1)
    , testCase "device logits and value drive the oracle instead of a pure network fallback" $ do
        let net = diagnosticNet
            output = [0, 0, 0, 9, 0, 0, 0, 0.75]
            device = outputDevice output
        actual <- expectRight =<< Net.networkPriorOracleWithDevice device net Game.initialConnect4 []
        Mcts.evalValue actual @?= tanh 0.75
        assertBool "injected logit did not dominate the prior" (Mcts.evalPriors actual !! 3 > 0.99)
        assertBool
          "oracle silently used the pure network"
          (actual /= Net.networkPriorOracle net Game.initialConnect4 [])
    , testCase "sequential RNG state flows across games with exact current role and horizon score" $ do
        actual <-
          expectRight
            =<< Net.arenaEvaluationAgainstUniformOnDeviceFrom
              Game.initialConnect4
              pureReferenceMlpDevice
              diagnosticNet
              3
              2
              104
        Net.arenaEvaluationOutcomes actual @?= expectedGames diagnosticNet 3 104
        Net.arenaEvaluationScore actual @?= 0.5
        map Net.arenaEpisodeIndex (Net.arenaEvaluationOutcomes actual) @?= [0, 1, 2]
        assertBool
          "horizon draw was reported as natural termination"
          (all Net.arenaEpisodeHorizonTruncated (Net.arenaEvaluationOutcomes actual))
    , testCase "bounded played arenas match the unchanged pure recipe beyond the two-move horizon" $ do
        let nearWin = foldl' (flip Game.applyMove) Game.initialConnect4 [0, 1, 0, 1, 0, 2]
            positions = [Game.initialConnect4, nearWin]
        forM_ positions $ \initial -> do
          observed <-
            expectRight
              =<< Net.arenaEvaluationAgainstUniformOnDeviceFrom initial pureReferenceMlpDevice diagnosticNet 2 8 23
          Net.arenaEvaluationScore observed
            @?= Net.arenaWinRateAgainstUniformFrom initial diagnosticNet 2 8 23
          length (Net.arenaEvaluationOutcomes observed) @?= 2
          forM_ (Net.arenaEvaluationOutcomes observed) $ \episode -> do
            let final = Net.arenaEpisodeFinalState episode
            final @?= foldl' (flip Game.applyMove) Game.initialConnect4 (Game.gameMoves final)
            if Net.arenaEpisodeHorizonTruncated episode
              then do
                Net.arenaEpisodeDecisionCount episode @?= 8
                Net.arenaEpisodeOutcome episode @?= Game.GameDraw
              else Net.arenaEpisodeOutcome episode @?= Game.gameOutcome final
    , testCase "later device failures reject partial searches and partial evaluation cohorts" $ do
        baselineCalls <- newIORef (0 :: Int)
        _ <-
          expectRight
            =<< Net.arenaEvaluationAgainstUniformOnDeviceFrom
              Game.initialConnect4
              (countingDevice baselineCalls pureReferenceMlpDevice)
              diagnosticNet
              1
              1
              33
        oneGameCalls <- readIORef baselineCalls
        assertBool "first game unexpectedly had no neural evaluation" (oneGameCalls > 1)
        forM_ [2, oneGameCalls + 1] $ \failureAt -> do
          calls <- newIORef (0 :: Int)
          let device =
                pureReferenceMlpDevice
                  { mlpdForward = \params input -> do
                      modifyIORef' calls (+ 1)
                      index <- readIORef calls
                      if index == failureAt
                        then pure (Left "arena selected device failed")
                        else mlpdForward pureReferenceMlpDevice params input
                  }
          Net.arenaEvaluationAgainstUniformOnDeviceFrom Game.initialConnect4 device diagnosticNet 2 1 33
            >>= (@?= Left "arena selected device failed")
          readIORef calls >>= (@?= failureAt)
    , testCase "IO failures propagate without pure fallback or fabricated draw outcomes" $ do
        calls <- newIORef (0 :: Int)
        let device =
              pureReferenceMlpDevice
                { mlpdForward = \_ _ -> modifyIORef' calls (+ 1) >> ioError (userError "arena IO failure")
                }
        actual <-
          try (Net.arenaEvaluationAgainstUniformOnDeviceFrom Game.initialConnect4 device diagnosticNet 1 1 7)
            :: IO (Either IOException (Either Text Net.ArenaEvaluationResult))
        case actual of
          Left failure -> assertBool "wrong IO failure" ("arena IO failure" `Text.isInfixOf` Text.pack (show failure))
          Right _ -> assertFailure "IO error became an arena result"
        readIORef calls >>= (@?= 1)
    , testCase "missing extra nonfinite or Float32-overflow heads fail before value defaults and masking"
        $ forM_
          [ replicate 7 0
          , replicate 9 0
          , [0 / 0, 0, 0, 0, 0, 0, 0, 0]
          , [0, 0, 0, 0, 0, 0, 0, 1 / 0]
          , [0, 0, 0, 0, 0, 0, 0, 1e300]
          ]
        $ \output -> do
          calls <- newIORef (0 :: Int)
          let device = countingDevice calls (outputDevice output)
          Net.networkPriorOracleWithDevice device diagnosticNet Game.initialConnect4 []
            >>= (@?= Left "AlphaZero device oracle output has the wrong shape or is not finite Float32")
          readIORef calls >>= (@?= 1)
    , testCase "malformed parameter buffers nonfinite values and invalid dimensions fail before dispatch" $ do
        calls <- newIORef (0 :: Int)
        let params = Net.pvnParams diagnosticNet
            shape = Mlp.paramShape params
            paramsCases =
              [ params {Mlp.paramW1 = VU.empty}
              , params {Mlp.paramB1 = VU.empty}
              , params {Mlp.paramW2 = VU.empty}
              , params {Mlp.paramB2 = VU.empty}
              , params {Mlp.paramW1 = VU.cons (0 / 0) (VU.drop 1 (Mlp.paramW1 params))}
              , params {Mlp.paramB2 = VU.replicate 8 1e300}
              ]
            dimensionCases =
              [ diagnosticNet {Net.pvnActionCount = 0}
              , diagnosticNet {Net.pvnObservationSize = 0}
              , diagnosticNet {Net.pvnObservationSize = 8}
              , diagnosticNet {Net.pvnActionCount = 8}
              , diagnosticNet {Net.pvnParams = params {Mlp.paramShape = shape {Mlp.mlpHidden = 0}}}
              , diagnosticNet
                  { Net.pvnObservationSize = maxBound
                  , Net.pvnParams = params {Mlp.paramShape = shape {Mlp.mlpInputs = maxBound}}
                  }
              ]
            device = countingDevice calls pureReferenceMlpDevice
        forM_ paramsCases $ \bad ->
          Net.networkPriorOracleWithDevice
            device
            (diagnosticNet {Net.pvnParams = bad})
            Game.initialConnect4
            []
            >>= (@?= Left "AlphaZero device oracle parameters are malformed or overflow the Float32 ABI")
        forM_ dimensionCases $ \bad ->
          Net.networkPriorOracleWithDevice device bad Game.initialConnect4 []
            >>= (@?= Left "AlphaZero device oracle network dimensions are malformed")
        readIORef calls >>= (@?= 0)
    , testCase "finite conversion rounding and subnormal underflow remain valid device inputs and outputs" $ do
        let params = Net.pvnParams diagnosticNet
            tiny = diagnosticNet {Net.pvnParams = params {Mlp.paramW1 = VU.map (const 1e-310) (Mlp.paramW1 params)}}
        actual <-
          expectRight
            =<< Net.networkPriorOracleWithDevice (outputDevice (replicate 8 1e-310)) tiny Game.initialConnect4 []
        assertBool
          "finite underflow input was rejected or poisoned priors"
          (all (\value -> not (isNaN value || isInfinite value)) (Mcts.evalPriors actual))
        Mcts.evalValue actual @?= tanh 1e-310
    , testCase "invalid game counts move counts and overflowing search seeds fail before device IO" $ do
        calls <- newIORef (0 :: Int)
        let device = countingDevice calls pureReferenceMlpDevice
        forM_ [(0, 1), (1, 0), (-1, 1), (1, -1)] $ \(games, plies) ->
          Net.arenaEvaluationAgainstUniformOnDeviceFrom
            Game.initialConnect4
            device
            diagnosticNet
            games
            plies
            7
            >>= (@?= Left "AlphaZero device arena requires positive game and move counts")
        Net.arenaEvaluationAgainstUniformOnDeviceFrom Game.initialConnect4 device diagnosticNet 2 2 maxBound
          >>= (@?= Left "AlphaZero device arena search seed arithmetic overflows Int")
        readIORef calls >>= (@?= 0)
    , testCase "terminal oracle and terminal initial arenas retain exact outcomes without neural calls" $ do
        calls <- newIORef (0 :: Int)
        let device = countingDevice calls pureReferenceMlpDevice
        forM_ [(winningState, 1), (losingState, -1)] $ \(state, winner) -> do
          Game.gameOutcome state @?= Game.GameWon winner
          oracle <- expectRight =<< Net.networkPriorOracleWithDevice device diagnosticNet state []
          Mcts.evalTerminal oracle @?= True
          Mcts.evalValue oracle @?= Game.terminalValueForToMove state
          Mcts.evalPriors oracle @?= []
          arena <-
            expectRight =<< Net.arenaEvaluationAgainstUniformOnDeviceFrom state device diagnosticNet 2 2 7
          map Net.arenaEpisodeOutcome (Net.arenaEvaluationOutcomes arena)
            @?= replicate 2 (Game.GameWon winner)
          map Net.arenaEpisodeDecisionCount (Net.arenaEvaluationOutcomes arena) @?= [0, 0]
          Net.arenaEvaluationScore arena @?= if winner == 1 then 1 else 0
        readIORef calls >>= (@?= 0)
    , testCase "Othello forced pass preserves actual player legal mask and opponent-only arena decisions" $ do
        let playable = Game.normaliseForcedPass passPosition
            net = Net.initPolicyValueNet 65 64 2 31
        Game.gameOutcome passPosition @?= Game.GameInProgress
        Game.legalMoves passPosition @?= []
        Game.gameCurrentPlayer playable @?= -1
        Game.legalMoves playable @?= [0, 1]
        calls <- newIORef []
        let device =
              pureReferenceMlpDevice
                { mlpdForward = \params input -> modifyIORef' calls (<> [input]) >> mlpdForward pureReferenceMlpDevice params input
                }
        oracle <- expectRight =<< Net.networkPriorOracleWithDevice device net passPosition []
        oracle @?= Net.networkPriorOracle net passPosition []
        Mcts.evalPlayerToMove oracle @?= Just (-1)
        inputs <- readIORef calls
        inputs @?= [Net.encodeGameState net playable]
        let failDevice = pureReferenceMlpDevice {mlpdForward = \_ _ -> pure (Left "opponent must not call a network")}
        actual <-
          expectRight =<< Net.arenaEvaluationAgainstUniformOnDeviceFrom passPosition failDevice net 1 1 7
        let (u, _) = Random.uniformR (0 :: Double, 1) (Random.mkStdGen 7)
            next = Game.applyMove ([0, 1] !! ((floor (u * 2) :: Int) `mod` 2)) playable
            (final, outcome, truncated) = case Game.gameOutcome next of
              Game.GameInProgress -> (Game.normaliseForcedPass next, Game.GameDraw, True)
              outcomeValue -> (next, outcomeValue, False)
        Net.arenaEvaluationOutcomes actual @?= [Net.ArenaEpisodeResult 0 outcome final 1 truncated]
    , testCase "full columns are excluded from actual device priors without remapping legal moves" $ do
        let state = foldl' (flip Game.applyMove) Game.initialConnect4 (replicate 6 0)
        Game.gameOutcome state @?= Game.GameInProgress
        assertBool "test column is not full" (0 `notElem` Game.legalMoves state)
        oracle <-
          expectRight
            =<< Net.networkPriorOracleWithDevice
              (outputDevice [1000, -1000, -1000, -1000, -1000, -1000, -1000, 0])
              diagnosticNet
              state
              []
        case Mcts.evalPriors oracle of
          illegal : legal -> do
            illegal @?= 0
            legal @?= replicate 6 (1 / 6)
          [] -> assertFailure "masked priors were empty"
        let tooFewHeads = Net.initPolicyValueNet 43 1 2 7
        Net.networkPriorOracleWithDevice pureReferenceMlpDevice tooFewHeads Game.initialConnect4 []
          >>= (@?= Left "AlphaZero device oracle has no valid nonempty legal-action domain")
    , testCase "negative seed cancellation cannot hide oversized intermediate search offsets" $ do
        calls <- newIORef (0 :: Int)
        let device = countingDevice calls pureReferenceMlpDevice
            oversizedGames = maxBound `div` 1009 + 2
            oversizedPlies = maxBound `div` 7919 + 2
            minimumSeed = minBound :: Int
        forM_ [(oversizedGames, 1), (1, oversizedPlies)] $ \(games, plies) -> do
          let gameOffset = (toInteger games - 1) * 1009
              plyOffset = (toInteger plies - 1) * 7919
              finalSeed = toInteger minimumSeed + gameOffset + plyOffset
          assertBool
            "fixture did not exceed an intermediate Int product"
            (max gameOffset plyOffset > toInteger (maxBound :: Int))
          assertBool
            "fixture no longer cancels to a representable final seed"
            (finalSeed >= toInteger (minBound :: Int) && finalSeed <= toInteger (maxBound :: Int))
          -- A regression must not iterate a huge terminal-game count or pretend
          -- that an unvisited horizon validated its impossible intermediate ABI.
          actual <-
            timeout
              1000000
              ( Net.arenaEvaluationAgainstUniformOnDeviceFrom
                  winningState
                  device
                  diagnosticNet
                  games
                  plies
                  minimumSeed
              )
          actual @?= Just (Left "AlphaZero device arena search seed arithmetic overflows Int")
        readIORef calls >>= (@?= 0)
    ]

diagnosticNet :: Net.PolicyValueNet
diagnosticNet = Net.initPolicyValueNet 43 7 2 17

winningState, losingState, passPosition :: Game.GameState
winningState = foldl' (flip Game.applyMove) Game.initialConnect4 [0, 1, 0, 1, 0, 1, 0]
losingState = foldl' (flip Game.applyMove) Game.initialConnect4 [0, 1, 0, 1, 2, 1, 2, 1]
passPosition =
  foldl'
    (flip Game.applyMove)
    Game.initialOthello
    [ 19
    , 18
    , 17
    , 20
    , 21
    , 34
    , 45
    , 14
    , 33
    , 42
    , 29
    , 32
    , 7
    , 37
    , 43
    , 52
    , 51
    , 44
    , 59
    , 26
    , 50
    , 49
    , 56
    , 41
    , 24
    , 61
    , 30
    , 25
    , 60
    , 16
    , 48
    , 38
    , 62
    , 10
    , 31
    , 22
    , 8
    , 23
    , 2
    , 3
    , 11
    , 4
    , 5
    , 53
    , 40
    , 47
    , 12
    , 57
    , 54
    , 58
    , 39
    , 46
    , 15
    , 55
    , 63
    , 6
    , 9
    , 13
    ]

countingDevice :: IORef Int -> MlpDevice -> MlpDevice
countingDevice calls device =
  device {mlpdForward = \params input -> modifyIORef' calls (+ 1) >> mlpdForward device params input}

outputDevice :: [Double] -> MlpDevice
outputDevice output =
  pureReferenceMlpDevice
    { mlpdForward = \params input -> do
        actual <- mlpdForward pureReferenceMlpDevice params input
        pure (fmap (\forward -> forward {Mlp.forwardOutput = VU.fromList output}) actual)
    }

-- Independent fixed two-decision cases use the old pure MCTS and a single
-- sequential StdGen. They detect changed cross-game RNG, role, search budget,
-- action sampling, move transcript and horizon behavior; no trained scores.
expectedTwoMoveGames :: Net.PolicyValueNet -> Int -> [Net.ArenaEpisodeResult]
expectedTwoMoveGames net = expectedGames net 2

expectedGames :: Net.PolicyValueNet -> Int -> Int -> [Net.ArenaEpisodeResult]
expectedGames net count seed = go 0 (Random.mkStdGen seed)
 where
  sims = max 48 (min 192 (2 * Net.pvnActionCount net))
  go game generator
    | game >= count = []
    | otherwise =
        let (u, g1) = Random.uniformR (0 :: Double, 1) generator
            distribution = Net.mctsVisitDistribution net sims Game.initialConnect4 (seed + game * 1009)
            first = Game.applyMove (Mlp.sampleCategorical distribution u) Game.initialConnect4
            (v, g2) = Random.uniformR (0 :: Double, 1) g1
            allowed = Game.legalMoves first
            second =
              Game.applyMove
                (allowed !! ((floor (v * fromIntegral (length allowed)) :: Int) `mod` max 1 (length allowed)))
                first
         in Net.ArenaEpisodeResult game Game.GameDraw second 2 True : go (game + 1) g2

expectRight :: (Show err) => Either err value -> IO value
expectRight = either (\failure -> assertFailure (show failure) >> fail "unreachable") pure
