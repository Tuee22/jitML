{-# LANGUAGE BangPatterns #-}

-- | Sprint 13.9 — real two-headed policy/value network for AlphaZero,
-- wired through the differentiable MLP seam in "JitML.Numerics.Mlp".
-- The network takes an encoded board observation, emits a policy
-- distribution over the game's action space, and emits a scalar value
-- estimate.
--
-- This module closes the "full policy/value network codegen" deliverable
-- for the canonical four perfect-information games. The same network
-- shape works for connect4, othello, hex, and gomoku by parameterising
-- @MlpShape@ with the game's observation size and action count.
--
-- Encoding strategy: each board cell is encoded as @+1.0@ (current
-- player's piece), @-1.0@ (opponent's piece), or @0.0@ (empty); plus a
-- final scalar for the side-to-move parity. This gives a fixed-shape
-- input tensor without needing a per-game encoder.
--
-- Training loop (Sprint 13.9):
--
--   1. Roll @selfPlayGames@ self-play games using the current network
--      as the MCTS PriorOracle.
--   2. For each game, collect (state, mcts_visit_distribution, outcome)
--      triples.
--   3. Train the network for @gradientUpdates@ steps with policy loss =
--      cross-entropy(mcts_dist, softmax(policy_head)) + value loss =
--      MSE(outcome, tanh(value_head)).
--   4. Evaluate against a previous champion in arena to decide
--      promotion (Sprint 13.9 deliverable).
--
-- Same-substrate / same-seed runs are bit-deterministic.
module JitML.RL.AlphaZero.PolicyValueNet
  ( PolicyValueNet (..)
  , initPolicyValueNet
  , initAdamFor
  , encodeConnect4Board
  , encodeGameState
  , networkPriorOracle
  , networkPriorOracleWithDevice
  , netOracleFactory
  , netOracleFactoryWithDevice
  , runNetworkSelfPlay
  , networkPolicyValue
  , mctsVisitDistribution
  , mctsVisitDistributionWithDevice
  , PolicyValueTrainingSample (..)
  , trainPolicyValueNetOnSamples
  , trainPolicyValueNetOnSamplesCuda
  , trainPolicyValueNetOnSamplesOneDnn
  , trainPolicyValueNetOnSamplesMetal
  , trainPolicyValueNetOnSamplesWithDevice
  , policyValueNetToFlat
  , loadPolicyValueNetWeights
  , generatePolicyValueSamples
  , generatePolicyValueSamplesWithDevice
  , runOneGenerationOfSelfPlay
  , GenerationResult (..)
  , arenaWinRateAgainstUniform

    -- * Re-exports for tests
  , pvPolicy
  , pvValue
  , PolicyValueOutput
  )
where

import Control.Monad (foldM)
import Data.List qualified
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU
import System.Random qualified as Random

import JitML.Env.Env (Env)
import JitML.Numerics.Mlp
  ( AdamConfig (..)
  , AdamState
  , MlpParams (..)
  , MlpShape (..)
  , PolicyValueOutput (..)
  , adamInit
  , adamStep
  , defaultAdamConfig
  , mlpInit
  , mlpOutputs
  , mlpParamsFromFlat
  , mlpParamsToFlat
  , paramShape
  , policyValueBackward
  , policyValueForward
  , policyValueFromForward
  , policyValueOutputGradient
  , sampleCategorical
  )
import JitML.Numerics.MlpCuda (cudaMlpDevice)
import JitML.Numerics.MlpDevice (MlpDevice (..))
import JitML.Numerics.MlpMetal (metalMlpDevice)
import JitML.Numerics.MlpOneDnn (oneDnnMlpDevice)
import JitML.RL.AlphaZero
  ( GameState (..)
  , applyMove
  , initialConnect4
  )
import JitML.RL.AlphaZero.Mcts
  ( MctsConfig (..)
  , MctsEdge (..)
  , MctsNode (..)
  , NodeEval (..)
  , PriorOracle
  , defaultMctsConfig
  , runSearchWithPrior
  , runSearchWithPriorIO
  )
import JitML.RL.AlphaZero.SelfPlay
  ( SelfPlayBuffer
  , SelfPlayConfig
  , runSelfPlayWithOracleFactory
  )

-- | The trained network. Carries the MLP parameters, the game's action
-- count, and the side-to-move-aware observation encoder shape.
data PolicyValueNet = PolicyValueNet
  { pvnParams :: !MlpParams
  , pvnActionCount :: !Int
  , pvnObservationSize :: !Int
  }
  deriving stock (Eq, Show)

-- | Initialise the Adam optimiser state matching the network's shape.
initAdamFor :: PolicyValueNet -> AdamState
initAdamFor net = adamInit (paramShape (pvnParams net))

-- | Initialise a freshly-seeded PolicyValueNet. The MLP shape is
-- @observationSize → hiddenUnits → actionCount + 1@; the last output
-- is the value head.
initPolicyValueNet :: Int -> Int -> Int -> Int -> PolicyValueNet
initPolicyValueNet observationSize actionCount hiddenUnits seed =
  let shape =
        MlpShape
          { mlpInputs = observationSize
          , mlpHidden = hiddenUnits
          , mlpOutputs = actionCount + 1
          }
   in PolicyValueNet
        { pvnParams = mlpInit shape seed
        , pvnActionCount = actionCount
        , pvnObservationSize = observationSize
        }

-- | Encode a Connect 4 board state as the 42-cell @{-1, 0, +1}@ vector
-- plus a side-to-move parity bit. Cell ordering is row-major. The
-- encoder simulates the game from the move history.
encodeConnect4Board :: GameState -> Vector Double
encodeConnect4Board state =
  let cols = 7
      rows = 6
      grid = simulateConnect4 (gameMoves state)
      currentPlayer = gameCurrentPlayer state
      cellAt r c = case grid !! (r * cols + c) of
        0 -> 0.0
        p
          | p == currentPlayer -> 1.0
          | otherwise -> -1.0
      cells = [cellAt r c | r <- [0 .. rows - 1], c <- [0 .. cols - 1]]
      parity = if currentPlayer == 1 then 1.0 else -1.0
   in VU.fromList (cells <> [parity])

-- | Simulate a Connect 4 game from a move list, returning a flat
-- @42-cell@ array where @+1@ = first-player piece, @-1@ = second-player
-- piece, @0@ = empty. The board is stored row-major (row 0 = top).
simulateConnect4 :: [Int] -> [Int]
simulateConnect4 moves0 =
  let cols = 7
      rows = 6
      empty = replicate (rows * cols) 0
      place player col grid =
        case [r | r <- [rows - 1, rows - 2 .. 0], grid !! (r * cols + col) == 0] of
          (r : _) ->
            let ix = r * cols + col
             in take ix grid <> [player] <> drop (ix + 1) grid
          [] -> grid
      go _player [] grid = grid
      go player (m : ms) grid =
        go (negate player) ms (place player m grid)
   in go 1 (fmap (`mod` cols) moves0) empty

-- | Generic per-game observation encoder. Falls back to Connect 4 for
-- everything else (the network's observation surface is parameterised
-- by 'pvnObservationSize'; richer encoders for othello / hex / gomoku
-- are a follow-on delta).
encodeGameState :: PolicyValueNet -> GameState -> Vector Double
encodeGameState net state =
  let encoded = encodeConnect4Board state
   in if VU.length encoded >= pvnObservationSize net
        then VU.take (pvnObservationSize net) encoded
        else encoded VU.++ VU.replicate (pvnObservationSize net - VU.length encoded) 0.0

-- | Compute the policy + value for a given board state.
networkPolicyValue :: PolicyValueNet -> GameState -> PolicyValueOutput
networkPolicyValue net state =
  policyValueForward (pvnParams net) (pvnActionCount net) (encodeGameState net state)

-- | Sprint 9.10 — build the position-aware 'PriorOracle' the real MCTS tree
-- search consumes. The oracle is rooted at @rootState@; given a move-path from
-- that root it applies the moves, and returns either the terminal value (when a
-- player has completed a line) or the network's policy-head priors plus
-- value-head estimate for the position. This is what lets the search descend
-- and back up the __value head__ at every node, not just the root prior.
networkPriorOracle :: PolicyValueNet -> GameState -> PriorOracle
networkPriorOracle net rootState moves =
  let state = Data.List.foldl' (flip applyMove) rootState moves
      terminalValue = evaluateTerminal state
   in if terminalValue /= 0.0
        then NodeEval {evalPriors = [], evalValue = terminalValue, evalTerminal = True}
        else
          let out = networkPolicyValue net state
           in NodeEval
                { evalPriors = VU.toList (pvPolicy out)
                , evalValue = pvValue out
                , evalTerminal = False
                }

-- | Device-backed variant of 'networkPriorOracle'. Leaf evaluation runs the
-- policy/value MLP forward through the supplied 'MlpDevice'; any device compile
-- or execution error is returned as 'Left' and the MCTS caller fails closed.
networkPriorOracleWithDevice
  :: MlpDevice
  -> PolicyValueNet
  -> GameState
  -> [Int]
  -> IO (Either Text NodeEval)
networkPriorOracleWithDevice device net rootState moves =
  let state = Data.List.foldl' (flip applyMove) rootState moves
      terminalValue = evaluateTerminal state
   in if terminalValue /= 0.0
        then pure (Right NodeEval {evalPriors = [], evalValue = terminalValue, evalTerminal = True})
        else do
          fwdResult <- mlpdForward device (pvnParams net) (encodeGameState net state)
          pure $
            case fwdResult of
              Left err -> Left err
              Right fwd ->
                let out = policyValueFromForward (pvnActionCount net) fwd
                 in Right
                      NodeEval
                        { evalPriors = VU.toList (pvPolicy out)
                        , evalValue = pvValue out
                        , evalTerminal = False
                        }

-- | Sprint 9.10 — the per-position oracle the production AlphaZero self-play
-- loop threads through
-- 'JitML.RL.AlphaZero.SelfPlay.runSelfPlayWithOracleFactory'. For each board
-- position the factory returns an oracle rooted at that position, so the search
-- evaluates the network at every descended node — the AlphaZero contract that
-- the prior and value depend on the position, not the search seed.
netOracleFactory :: PolicyValueNet -> GameState -> PriorOracle
netOracleFactory = networkPriorOracle

-- | Device-backed oracle factory for the effectful MCTS path.
netOracleFactoryWithDevice
  :: MlpDevice -> PolicyValueNet -> GameState -> [Int] -> IO (Either Text NodeEval)
netOracleFactoryWithDevice = networkPriorOracleWithDevice

-- | Sprint 13.9 — run AlphaZero self-play with the MCTS prior driven by the
-- real policy/value network at every position. The search tree's prior input
-- now comes from the network's forward pass rather than the synthetic stub;
-- bit-deterministic on the same substrate / same seed (fixed network weights
-- + deterministic search).
runNetworkSelfPlay :: PolicyValueNet -> SelfPlayConfig -> SelfPlayBuffer
runNetworkSelfPlay net = runSelfPlayWithOracleFactory (netOracleFactory net)

-- | Sprint 13.9 — the true MCTS visit-count distribution for a position,
-- the canonical AlphaZero policy training target. Runs @sims@ MCTS
-- simulations from @state@ with the network's per-position prior oracle
-- and value backups, then normalises the resulting per-action visit
-- counts into a distribution over the action space. This is the target
-- the policy head is trained against (replacing the earlier
-- network's-own-policy proxy): the search reshapes the raw prior through
-- UCB exploration + value backups, so the visit distribution carries the
-- search's improved policy estimate rather than echoing the network.
-- Deterministic on the same substrate / same seed (fixed weights +
-- deterministic search).
mctsVisitDistribution :: PolicyValueNet -> Int -> GameState -> Int -> Vector Double
mctsVisitDistribution net sims state seed =
  let actionCount = pvnActionCount net
      cfg = (defaultMctsConfig actionCount) {mctsSimulations = max 1 sims}
      tree = runSearchWithPrior (netOracleFactory net state) cfg seed
   in visitDistributionFromTree actionCount tree

-- | Device-backed MCTS visit-count distribution. This is the Sprint 9.10
-- runtime path where leaf policy/value evaluation runs through the selected
-- JIT MLP device instead of the pure reference net.
mctsVisitDistributionWithDevice
  :: MlpDevice
  -> PolicyValueNet
  -> Int
  -> GameState
  -> Int
  -> IO (Either Text (Vector Double))
mctsVisitDistributionWithDevice device net sims state seed = do
  let actionCount = pvnActionCount net
      cfg = (defaultMctsConfig actionCount) {mctsSimulations = max 1 sims}
  treeResult <- runSearchWithPriorIO (netOracleFactoryWithDevice device net state) cfg seed
  pure (visitDistributionFromTree actionCount <$> treeResult)

visitDistributionFromTree :: Int -> MctsNode -> Vector Double
visitDistributionFromTree actionCount tree =
  let visitFor a =
        case [edgeVisits e | e <- nodeChildren tree, edgeAction e == a] of
          (v : _) -> fromIntegral v
          [] -> 0.0
      visits = VU.generate actionCount visitFor
      total = VU.sum visits
   in if total <= 0
        then VU.replicate actionCount (1.0 / fromIntegral (max 1 actionCount))
        else VU.map (/ total) visits

-- | One labeled training sample for the policy/value loss.
data PolicyValueTrainingSample = PolicyValueTrainingSample
  { sampleState :: !GameState
  , sampleVisitDist :: !(Vector Double) -- MCTS visit-count distribution (sums to 1)
  , sampleOutcome :: !Double -- final outcome in {-1, 0, +1} from this state's POV
  }
  deriving stock (Eq, Show)

-- | Train the policy/value net on a batch of samples for @passes@
-- gradient descent passes. Uses Adam (Sprint 13.8 reused).
trainPolicyValueNetOnSamples
  :: PolicyValueNet
  -> AdamState
  -> Double -- learning rate
  -> Int -- passes
  -> [PolicyValueTrainingSample]
  -> (PolicyValueNet, AdamState)
trainPolicyValueNetOnSamples net0 adam0 lr passes samples =
  let adamConfig = defaultAdamConfig {adamLearningRate = lr}
      onePass (net, adam) =
        Data.List.foldl'
          ( \(n, a) trainingSample ->
              let pv = networkPolicyValue n (sampleState trainingSample)
                  policy = pvPolicy pv
                  -- Policy loss gradient (cross-entropy with MCTS visit dist):
                  -- d/dlogit_i CE = softmax_i - target_i
                  dLogits =
                    VU.zipWith (-) policy (sampleVisitDist trainingSample)
                  -- Value loss gradient (MSE):
                  -- d/dvalue 0.5 * (v - outcome)^2 = (v - outcome)
                  dValue = pvValue pv - sampleOutcome trainingSample
                  grad = policyValueBackward (pvnParams n) pv dLogits dValue
                  (newParams, newAdam) =
                    adamStep adamConfig a (pvnParams n) grad
               in (n {pvnParams = newParams}, newAdam)
          )
          (net, adam)
          samples
   in Data.List.foldl' (\(n, a) _ -> onePass (n, a)) (net0, adam0) [1 .. passes]

-- | Sprint 13.8 / 13.9 — the CUDA-backed analogue of
-- 'trainPolicyValueNetOnSamples'. The per-sample network forward and
-- backward passes run on the GPU through the generated nvcc MLP kernels
-- ('JitML.Numerics.MlpCuda'); the policy/value loss-gradient assembly
-- ('policyValueOutputGradient') and the Adam update stay on the host. The
-- algorithm, sample contract, and Adam math are identical to the pure
-- version — only the network forward/backward backend changes. Returns
-- 'Left' when the CUDA runtime / compile is unavailable so callers can
-- fall back to 'trainPolicyValueNetOnSamples'.
trainPolicyValueNetOnSamplesCuda
  :: Env
  -> PolicyValueNet
  -> AdamState
  -> Double -- learning rate
  -> Int -- passes
  -> [PolicyValueTrainingSample]
  -> IO (Either Text (PolicyValueNet, AdamState))
trainPolicyValueNetOnSamplesCuda env = trainPolicyValueNetOnSamplesWithDevice (cudaMlpDevice env)

-- | AlphaZero PolicyValueNet training through the oneDNN (linux-cpu) MLP device.
trainPolicyValueNetOnSamplesOneDnn
  :: Env
  -> PolicyValueNet
  -> AdamState
  -> Double
  -> Int
  -> [PolicyValueTrainingSample]
  -> IO (Either Text (PolicyValueNet, AdamState))
trainPolicyValueNetOnSamplesOneDnn env = trainPolicyValueNetOnSamplesWithDevice (oneDnnMlpDevice env)

-- | AlphaZero PolicyValueNet training through the Metal (apple-silicon) MLP device.
trainPolicyValueNetOnSamplesMetal
  :: Env
  -> PolicyValueNet
  -> AdamState
  -> Double
  -> Int
  -> [PolicyValueTrainingSample]
  -> IO (Either Text (PolicyValueNet, AdamState))
trainPolicyValueNetOnSamplesMetal env = trainPolicyValueNetOnSamplesWithDevice (metalMlpDevice env)

-- | AlphaZero PolicyValueNet training through an injected MLP device backend.
-- The per-sample network forward and backward passes run on the device through
-- the generated MLP kernels; the policy/value loss-gradient assembly
-- ('policyValueOutputGradient') and the Adam update stay on the host. The
-- algorithm, sample contract, and Adam math are identical to the pure
-- 'trainPolicyValueNetOnSamples' — only the network forward/backward backend
-- changes. Returns 'Left' when the backend runtime / compile is unavailable.
trainPolicyValueNetOnSamplesWithDevice
  :: MlpDevice
  -> PolicyValueNet
  -> AdamState
  -> Double -- learning rate
  -> Int -- passes
  -> [PolicyValueTrainingSample]
  -> IO (Either Text (PolicyValueNet, AdamState))
trainPolicyValueNetOnSamplesWithDevice device net0 adam0 lr passes samples =
  foldM onePass (Right (net0, adam0)) [1 .. passes]
 where
  adamConfig = defaultAdamConfig {adamLearningRate = lr}
  onePass acc _ = foldM stepSample acc samples
  stepSample (Left e) _ = pure (Left e)
  stepSample (Right (n, a)) trainingSample = do
    let params = pvnParams n
        actionCount = pvnActionCount n
        input = encodeGameState n (sampleState trainingSample)
        outputs = mlpOutputs (paramShape params)
    fwdResult <- fmap (policyValueFromForward actionCount) <$> mlpdForward device params input
    case fwdResult of
      Left e -> pure (Left e)
      Right pv -> do
        let dLogits = VU.zipWith (-) (pvPolicy pv) (sampleVisitDist trainingSample)
            dValue = pvValue pv - sampleOutcome trainingSample
            dLdy = policyValueOutputGradient outputs pv dLogits dValue
        gradResult <- mlpdBackward device params (pvForward pv) dLdy
        case gradResult of
          Left e -> pure (Left e)
          Right grad ->
            let (newParams, newAdam) = adamStep adamConfig a params grad
             in pure (Right (n {pvnParams = newParams}, newAdam))

-- | Sprint 13.9 — serialize a trained network's parameters to the flat
-- @Double@ list the checkpoint @.jmw1@ weight blob carries
-- (`JitML.Checkpoint.Format.encodeJmw1`). Round-trips with
-- 'loadPolicyValueNetWeights' so trained AlphaZero network weights persist
-- through the checkpoint surface.
policyValueNetToFlat :: PolicyValueNet -> [Double]
policyValueNetToFlat = mlpParamsToFlat . pvnParams

-- | Load flat checkpoint weights (decoded from a @.jmw1@ blob) into a
-- network template, reusing the template's shape / action-count /
-- observation-size. Fails when the flat list length does not match the
-- template's parameter count.
loadPolicyValueNetWeights :: PolicyValueNet -> [Double] -> Either Text PolicyValueNet
loadPolicyValueNetWeights template flat =
  case mlpParamsFromFlat (paramShape (pvnParams template)) flat of
    Left err -> Left (Text.pack err)
    Right params -> Right template {pvnParams = params}

-- | Generate one self-play game using the current network as the MCTS
-- prior. Each move runs @sims@ MCTS simulations from the current
-- position; the resulting visit-count distribution is both the move
-- the agent plays (sampled with temperature 1) and the policy training
-- target ('sampleVisitDist') — the canonical AlphaZero target, not the
-- network's raw policy. Returns the per-move (state, visit-dist,
-- outcome) samples. Deterministic given the seed.
generatePolicyValueSamples
  :: PolicyValueNet
  -> Int -- seed
  -> Int -- MCTS simulations per move
  -> Int -- max plies
  -> [PolicyValueTrainingSample]
generatePolicyValueSamples net seed0 sims maxPlies =
  let gen0 = Random.mkStdGen seed0
      go !state !gen !plies !acc
        | plies >= maxPlies = annotatePolicyValueOutcome 0.0 (reverse acc)
        | otherwise =
            let visitDist = mctsVisitDistribution net sims state (seed0 + plies * 7919)
                (u, gen') = Random.uniformR (0.0 :: Double, 1.0) gen
                action = sampleCategorical visitDist u
                nextState = applyMove action state
                sample =
                  PolicyValueTrainingSample
                    { sampleState = state
                    , sampleVisitDist = visitDist
                    , sampleOutcome = 0.0 -- filled below
                    }
                terminal = plies + 1 >= maxPlies
                outcomeFromHere =
                  if terminal
                    then evaluateTerminal nextState
                    else 0.0
             in if terminal
                  then annotatePolicyValueOutcome outcomeFromHere (reverse (sample : acc))
                  else go nextState gen' (plies + 1) (sample : acc)
   in go initialConnect4 gen0 0 []

-- | Device-backed variant of 'generatePolicyValueSamples'. The MCTS visit
-- target for each sampled position is produced through
-- 'mctsVisitDistributionWithDevice', so policy/value leaf evaluation runs on
-- the supplied JIT 'MlpDevice'. A device failure aborts sample generation with
-- 'Left' instead of falling back to the pure network path.
generatePolicyValueSamplesWithDevice
  :: MlpDevice
  -> PolicyValueNet
  -> Int -- seed
  -> Int -- MCTS simulations per move
  -> Int -- max plies
  -> IO (Either Text [PolicyValueTrainingSample])
generatePolicyValueSamplesWithDevice device net seed0 sims maxPlies =
  let gen0 = Random.mkStdGen seed0
      go !state !gen !plies !acc
        | plies >= maxPlies = pure (Right (annotatePolicyValueOutcome 0.0 (reverse acc)))
        | otherwise = do
            visitResult <- mctsVisitDistributionWithDevice device net sims state (seed0 + plies * 7919)
            case visitResult of
              Left err -> pure (Left err)
              Right visitDist -> do
                let (u, gen') = Random.uniformR (0.0 :: Double, 1.0) gen
                    action = sampleCategorical visitDist u
                    nextState = applyMove action state
                    sample =
                      PolicyValueTrainingSample
                        { sampleState = state
                        , sampleVisitDist = visitDist
                        , sampleOutcome = 0.0
                        }
                    terminal = plies + 1 >= maxPlies
                    outcomeFromHere =
                      if terminal
                        then evaluateTerminal nextState
                        else 0.0
                if terminal
                  then pure (Right (annotatePolicyValueOutcome outcomeFromHere (reverse (sample : acc))))
                  else go nextState gen' (plies + 1) (sample : acc)
   in go initialConnect4 gen0 0 []

annotatePolicyValueOutcome :: Double -> [PolicyValueTrainingSample] -> [PolicyValueTrainingSample]
annotatePolicyValueOutcome finalOutcome = annotateLoop finalOutcome (0 :: Int)
 where
  -- Alternate signs because the outcome is from each side's POV.
  -- Manual index threading instead of @zipWith@ over @[0 ..]@ so hlint's
  -- `Use zipWithFrom` hint (which would require the extra package)
  -- does not fire.
  annotateLoop _ _ [] = []
  annotateLoop outcome i (s : ss) =
    let sign = if even i then 1.0 else -1.0
     in s {sampleOutcome = sign * outcome} : annotateLoop outcome (i + 1) ss

-- | Real Connect-4 terminal evaluator: checks for any 4-in-a-row in
-- horizontals, verticals, and both diagonal directions. Returns
-- @+1@ if the side that just played has 4-in-a-row (so the side to
-- move loses), @-1@ if the side to move has 4-in-a-row (shouldn't
-- happen mid-play; defensive), or @0@ for no terminal alignment.
evaluateTerminal :: GameState -> Double
evaluateTerminal state =
  let grid = simulateConnect4 (gameMoves state)
      currentPlayer = gameCurrentPlayer state
      otherPlayer = negate currentPlayer
      cols = 7
      rows = 6
      cell r c
        | r < 0 || r >= rows || c < 0 || c >= cols = 0
        | otherwise = grid !! (r * cols + c)
      runOf p (r0, c0) (dr, dc) =
        all (\k -> cell (r0 + k * dr) (c0 + k * dc) == p) [0 .. 3]
      directions = [(0, 1), (1, 0), (1, 1), (1, -1)]
      hasLine p =
        any
          ( \(r, c) ->
              any (runOf p (r, c)) directions
          )
          [(r, c) | r <- [0 .. rows - 1], c <- [0 .. cols - 1]]
   in if hasLine otherPlayer
        then 1.0 -- the side that just moved won; from the to-move POV that is a loss-incoming, so the prior move yielded +1
        else
          if hasLine currentPlayer
            then -1.0
            else 0.0

-- | One generation = self-play games + gradient updates against the
-- collected samples + arena win-rate measurement.
data GenerationResult = GenerationResult
  { genNet :: !PolicyValueNet
  , genAdam :: !AdamState
  , genSamplesCount :: !Int
  , genArenaWinRate :: !Double
  }
  deriving stock (Eq, Show)

-- | Run one generation of AlphaZero training. Plays @selfPlayGames@
-- self-play games, trains for @gradientUpdates@ passes, and reports
-- the win rate against the uniform-random opponent in the arena.
runOneGenerationOfSelfPlay
  :: PolicyValueNet
  -> AdamState
  -> Int -- selfPlayGames
  -> Int -- maxPliesPerGame
  -> Int -- MCTS simulations per move
  -> Int -- gradientUpdates
  -> Int -- arenaGames
  -> Int -- seed
  -> GenerationResult
runOneGenerationOfSelfPlay net adam selfPlayGames maxPlies sims gradientUpdates arenaGames seed =
  let games =
        fmap
          (\g -> generatePolicyValueSamples net (seed + g) sims maxPlies)
          [0 .. selfPlayGames - 1]
      samples = concat games
      (trainedNet, trainedAdam) =
        trainPolicyValueNetOnSamples net adam 1.0e-3 gradientUpdates samples
      winRate = arenaWinRateAgainstUniform trainedNet arenaGames maxPlies (seed + 7919)
   in GenerationResult
        { genNet = trainedNet
        , genAdam = trainedAdam
        , genSamplesCount = length samples
        , genArenaWinRate = winRate
        }

-- | Play @games@ arena games against a uniform-random opponent and
-- return the network's win rate (in @[0, 1]@). Uses the network as
-- player 1 and uniform-random as player 2 in alternation by game
-- index. Outcome heuristic: side that placed the last piece wins
-- (placeholder until a real terminal evaluator is wired in).
arenaWinRateAgainstUniform :: PolicyValueNet -> Int -> Int -> Int -> Double
arenaWinRateAgainstUniform net games maxPlies seed0 =
  let gen0 = Random.mkStdGen seed0
      playOne g state gen plies =
        if plies >= maxPlies
          then (0.0 :: Double, gen) -- draw
          else
            let netToMove = even (plies + g)
                pv = networkPolicyValue net state
                policy = pvPolicy pv
                actionCount = VU.length policy
                (u, gen') = Random.uniformR (0.0 :: Double, 1.0) gen
                action =
                  if netToMove
                    then sampleCategorical policy u
                    else (floor (u * fromIntegral actionCount) :: Int) `mod` actionCount
                nextState = applyMove action state
                outcome = evaluateTerminal nextState
             in if outcome /= 0.0
                  then (if netToMove then 1.0 else -1.0, gen')
                  else playOne g nextState gen' (plies + 1)
      go !g !gen !wins !drawn !losses
        | g >= games = (wins, drawn, losses)
        | otherwise =
            let (result, gen') = playOne g initialConnect4 gen 0
             in case compare result 0.0 of
                  GT -> go (g + 1) gen' (wins + 1) drawn losses
                  EQ -> go (g + 1) gen' wins (drawn + 1) losses
                  LT -> go (g + 1) gen' wins drawn (losses + 1)
      (w, d, _l) = go (0 :: Int) gen0 (0 :: Int) (0 :: Int) (0 :: Int)
   in if games == 0
        then 0.0
        else (fromIntegral w + 0.5 * fromIntegral d) / fromIntegral games
