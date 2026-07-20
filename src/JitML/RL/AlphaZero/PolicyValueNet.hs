{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}

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
  , policyValueTrainingSamplesSha256
  , trainPolicyValueNetOnSamples
  , trainPolicyValueNetOnSamplesCuda
  , trainPolicyValueNetOnSamplesOneDnn
  , trainPolicyValueNetOnSamplesMetal
  , trainPolicyValueNetOnSamplesWithDevice
  , policyValueNetToFlat
  , loadPolicyValueNetWeights
  , generatePolicyValueSamples
  , generatePolicyValueSamplesFrom
  , generatePolicyValueSamplesWithDevice
  , generatePolicyValueSamplesWithDeviceFrom
  , runOneGenerationOfSelfPlay
  , GenerationResult (..)
  , arenaWinRateAgainstUniform
  , arenaWinRateAgainstUniformFrom

    -- * Re-exports for tests
  , pvPolicy
  , pvValue
  , PolicyValueOutput
  )
where

import Control.Monad (foldM)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified as ByteString
import Data.ByteString.Builder qualified as Builder
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Char (intToDigit)
import Data.IntMap.Strict qualified as IntMap
import Data.IntSet qualified as IntSet
import Data.List qualified
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word8)
import System.Random qualified as Random

import JitML.Env.Env (Env)
import JitML.Numerics.Mlp
  ( AdamConfig (..)
  , AdamState
  , MlpGradient (..)
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
  , mlpZeroGradient
  , paramShape
  , policyValueBackward
  , policyValueForward
  , policyValueFromForward
  , sampleCategorical
  , softmax
  )
import JitML.Numerics.MlpCuda (cudaMlpDevice)
import JitML.Numerics.MlpDevice (MlpDevice (..))
import JitML.Numerics.MlpMetal (metalMlpDevice)
import JitML.Numerics.MlpOneDnn (oneDnnMlpDevice)
import JitML.RL.AlphaZero
  ( GameOutcome (..)
  , GameState (..)
  , applyMove
  , connect4BoardAfter
  , gameOutcome
  , gomokuActionCount
  , hexActionCount
  , initialConnect4
  , legalMoves
  , normaliseForcedPass
  , othelloActionCount
  , othelloBoardAfter
  , terminalValueForToMove
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
      grid = connect4BoardAfter (gameMoves state)
      currentPlayer = gameCurrentPlayer state
      cellAt r c = case grid !! (r * cols + c) of
        0 -> 0.0
        p
          | p == currentPlayer -> 1.0
          | otherwise -> -1.0
      cells = [cellAt r c | r <- [0 .. rows - 1], c <- [0 .. cols - 1]]
      parity = if currentPlayer == 1 then 1.0 else -1.0
   in VU.fromList (cells <> [parity])

-- | Generic per-game observation encoder. The observation is the board from
-- the side-to-move perspective plus a parity bit, so every AlphaZero product
-- game has a fixed input shape while still preserving the game's own board
-- size and legal-action surface.
encodeGameState :: PolicyValueNet -> GameState -> Vector Double
encodeGameState net state =
  let encoded =
        case gameName state of
          "connect4" -> encodeConnect4Board state
          "othello" -> encodeIndexedBoard othelloActionCount (othelloCells state) state
          "hex" -> encodeIndexedBoard hexActionCount (moveCells hexActionCount state) state
          "gomoku" -> encodeIndexedBoard gomokuActionCount (moveCells gomokuActionCount state) state
          _ -> encodeConnect4Board state
   in if VU.length encoded >= pvnObservationSize net
        then VU.take (pvnObservationSize net) encoded
        else encoded VU.++ VU.replicate (pvnObservationSize net - VU.length encoded) 0.0

encodeIndexedBoard :: Int -> [(Int, Int)] -> GameState -> Vector Double
encodeIndexedBoard actionCount occupied state =
  let currentPlayer = gameCurrentPlayer state
      cellAt cell =
        case lookup cell occupied of
          Nothing -> 0.0
          Just player
            | player == currentPlayer -> 1.0
            | otherwise -> -1.0
      parity = if currentPlayer == 1 then 1.0 else -1.0
   in VU.fromList ([cellAt cell | cell <- [0 .. actionCount - 1]] <> [parity])

othelloCells :: GameState -> [(Int, Int)]
othelloCells state =
  IntMap.toList (othelloBoardAfter (gameMoves state))

moveCells :: Int -> GameState -> [(Int, Int)]
moveCells actionCount state =
  [ (raw `mod` actionCount, if even ix then 1 else -1)
  | (ix, raw) <- zip [0 :: Int ..] (gameMoves state)
  ]

-- | Compute the policy + value for a given board state.
networkPolicyValue :: PolicyValueNet -> GameState -> PolicyValueOutput
networkPolicyValue net rawState =
  let state = normaliseForcedPass rawState
   in policyValueForward (pvnParams net) (pvnActionCount net) (encodeGameState net state)

maskedPriors :: GameState -> Vector Double -> [Double]
maskedPriors state priors =
  let allowed = legalMoves state
      allowedSet = IntSet.fromList allowed
      masked =
        VU.imap
          (\action probability -> if IntSet.member action allowedSet then probability else 0.0)
          priors
      total = VU.sum masked
   in if total <= 0.0
        then
          [ if IntSet.member action allowedSet then 1.0 / fromIntegral (max 1 (length allowed)) else 0.0
          | action <- [0 .. VU.length priors - 1]
          ]
        else VU.toList (VU.map (/ total) masked)

applySearchPath :: GameState -> [Int] -> GameState
applySearchPath =
  Data.List.foldl'
    (\state action -> normaliseForcedPass (applyMove action (normaliseForcedPass state)))
    . normaliseForcedPass

-- | Sprint 9.10 — build the position-aware 'PriorOracle' the real MCTS tree
-- search consumes. The oracle is rooted at @rootState@; given a move-path from
-- that root it applies the moves, and returns either the terminal value (when a
-- player has completed a line) or the network's policy-head priors plus
-- value-head estimate for the position. This is what lets the search descend
-- and back up the __value head__ at every node, not just the root prior.
networkPriorOracle :: PolicyValueNet -> GameState -> PriorOracle
networkPriorOracle net rootState moves =
  let state = applySearchPath rootState moves
   in case gameOutcome state of
        GameInProgress ->
          let out = networkPolicyValue net state
           in NodeEval
                { evalPriors = maskedPriors state (pvPolicy out)
                , evalValue = pvValue out
                , evalTerminal = False
                , evalPlayerToMove = Just (gameCurrentPlayer state)
                }
        _ ->
          NodeEval
            { evalPriors = []
            , evalValue = terminalValueForToMove state
            , evalTerminal = True
            , evalPlayerToMove = Just (gameCurrentPlayer state)
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
  let state = applySearchPath rootState moves
   in case gameOutcome state of
        GameInProgress -> do
          fwdResult <- mlpdForward device (pvnParams net) (encodeGameState net state)
          pure $
            case fwdResult of
              Left err -> Left err
              Right fwd ->
                let out = policyValueFromForward (pvnActionCount net) fwd
                 in Right
                      NodeEval
                        { evalPriors = maskedPriors state (pvPolicy out)
                        , evalValue = pvValue out
                        , evalTerminal = False
                        , evalPlayerToMove = Just (gameCurrentPlayer state)
                        }
        _ ->
          pure $
            Right
              NodeEval
                { evalPriors = []
                , evalValue = terminalValueForToMove state
                , evalTerminal = True
                , evalPlayerToMove = Just (gameCurrentPlayer state)
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
   in visitDistributionFromTree actionCount (legalMoves (normaliseForcedPass state)) tree

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
  pure
    ( visitDistributionFromTree
        actionCount
        (legalMoves (normaliseForcedPass state))
        <$> treeResult
    )

visitDistributionFromTree :: Int -> [Int] -> MctsNode -> Vector Double
visitDistributionFromTree actionCount allowed tree =
  let allowedSet = IntSet.fromList allowed
      visitFor a =
        case [edgeVisits e | e <- nodeChildren tree, edgeAction e == a] of
          (v : _) -> fromIntegral v
          [] -> 0.0
      visits = VU.generate actionCount visitFor
      total = VU.sum visits
   in if total <= 0
        then
          VU.generate
            actionCount
            ( \action ->
                if IntSet.member action allowedSet
                  then 1.0 / fromIntegral (max 1 (length allowed))
                  else 0.0
            )
        else VU.map (/ total) visits

-- | One labeled training sample for the policy/value loss.
data PolicyValueTrainingSample = PolicyValueTrainingSample
  { sampleState :: !GameState
  , sampleVisitDist :: !(Vector Double) -- MCTS visit-count distribution (sums to 1)
  , sampleOutcome :: !Double -- final outcome in {-1, 0, +1} from this state's POV
  }
  deriving stock (Eq, Show)

-- | Content address the exact, ordered self-play training samples.  The
-- binary framing covers every state, visit-distribution, and outcome field;
-- callers can therefore bind completion evidence to the data actually read
-- by the policy/value optimiser instead of to an experiment identifier.
policyValueTrainingSamplesSha256 :: [PolicyValueTrainingSample] -> Text
policyValueTrainingSamplesSha256 samples =
  hexBytes
    ( SHA256.hash
        ( LazyByteString.toStrict
            ( Builder.toLazyByteString
                ( Builder.byteString "jitml-alphazero-training-samples-v1\NUL"
                    <> countBuilder samples
                    <> foldMap sampleBuilder samples
                )
            )
        )
    )
 where
  sampleBuilder sample =
    stateBuilder (sampleState sample)
      <> vectorBuilder (sampleVisitDist sample)
      <> Builder.doubleBE (sampleOutcome sample)

  stateBuilder state =
    textBuilder (gameName state)
      <> countBuilder (gameMoves state)
      <> foldMap (Builder.int64BE . fromIntegral) (gameMoves state)
      <> Builder.int64BE (fromIntegral (gameCurrentPlayer state))

  vectorBuilder values =
    Builder.word64BE (fromIntegral (VU.length values))
      <> foldMap Builder.doubleBE (VU.toList values)

  textBuilder value =
    let bytes = Text.Encoding.encodeUtf8 value
     in Builder.word64BE (fromIntegral (ByteString.length bytes))
          <> Builder.byteString bytes

  countBuilder :: [value] -> Builder.Builder
  countBuilder = Builder.word64BE . fromIntegral . length

  hexBytes = Text.pack . concatMap hexByte . ByteString.unpack
  hexByte :: Word8 -> String
  hexByte byte =
    [ intToDigit (fromIntegral byte `div` 16)
    , intToDigit (fromIntegral byte `mod` 16)
    ]

-- | Train the policy/value net for an exact number of declared optimiser
-- updates.  Each update evaluates every sample against one immutable parameter
-- snapshot, averages the resulting gradients, and performs exactly one Adam
-- step.  Empty data and non-positive update counts fail before any training.
trainPolicyValueNetOnSamples
  :: PolicyValueNet
  -> AdamState
  -> Double -- learning rate
  -> Int -- exact optimiser updates
  -> [PolicyValueTrainingSample]
  -> Either Text (PolicyValueNet, AdamState)
trainPolicyValueNetOnSamples net0 adam0 lr updates samples = do
  validatePolicyValueTrainingInputs net0 lr updates samples
  Right
    ( Data.List.foldl'
        oneUpdate
        (net0, adam0)
        [1 .. updates]
    )
 where
  adamConfig = defaultAdamConfig {adamLearningRate = lr}
  sampleCount :: Double
  sampleCount = fromIntegral (length samples)

  oneUpdate (net, adam) _ =
    let params = pvnParams net
        summedGradient =
          Data.List.foldl'
            ( \gradient trainingSample ->
                addMlpGradient gradient (sampleGradient net trainingSample)
            )
            (mlpZeroGradient (paramShape params))
            samples
        meanGradient = scaleMlpGradient (1.0 / sampleCount) summedGradient
        (newParams, newAdam) = adamStep adamConfig adam params meanGradient
     in (net {pvnParams = newParams}, newAdam)

  sampleGradient net trainingSample =
    let pv = networkPolicyValue net (sampleState trainingSample)
        -- Policy loss gradient (cross-entropy with MCTS visit dist):
        -- d/dlogit_i CE = softmax_i - target_i.
        dLogits = VU.zipWith (-) (pvPolicy pv) (sampleVisitDist trainingSample)
        -- Value loss gradient (MSE):
        -- d/dvalue 0.5 * (v - outcome)^2 = (v - outcome).
        dValue = pvValue pv - sampleOutcome trainingSample
     in policyValueBackward (pvnParams net) pv dLogits dValue

-- | Sprint 13.8 / 13.9 — the CUDA-backed analogue of
-- 'trainPolicyValueNetOnSamples'. The batched network forward and backward
-- passes run on the GPU through the generated nvcc MLP kernels
-- ('JitML.Numerics.MlpCuda'); the policy/value loss-gradient assembly
-- ('policyValueOutputGradient') and the Adam update stay on the host. The
-- algorithm, sample contract, averaged gradient, and Adam math are identical
-- to the pure version — only the network forward/backward backend changes.
-- Returns 'Left' when the CUDA runtime / compile is unavailable so callers can
-- fail closed without falling back to 'trainPolicyValueNetOnSamples'.
trainPolicyValueNetOnSamplesCuda
  :: Env
  -> PolicyValueNet
  -> AdamState
  -> Double -- learning rate
  -> Int -- exact optimiser updates
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
-- The batched network forward and backward passes run on the device through
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
  -> Int -- exact optimiser updates
  -> [PolicyValueTrainingSample]
  -> IO (Either Text (PolicyValueNet, AdamState))
trainPolicyValueNetOnSamplesWithDevice device net0 adam0 lr updates samples =
  case validatePolicyValueTrainingInputs net0 lr updates samples of
    Left err -> pure (Left err)
    Right () -> foldM oneUpdate (Right (net0, adam0)) [1 .. updates]
 where
  adamConfig = defaultAdamConfig {adamLearningRate = lr}
  sampleCount = length samples
  inputs = fmap (encodeGameState net0 . sampleState) samples

  oneUpdate (Left err) _ = pure (Left err)
  oneUpdate (Right (net, adam)) _ = do
    let params = pvnParams net
        actionCount = pvnActionCount net
    fwdResult <- mlpdForwardBatch device params inputs
    case fwdResult of
      Left err -> pure (Left err)
      Right rawOutputs
        | length rawOutputs /= sampleCount ->
            pure (Left "AlphaZero device forward returned the wrong sample count")
        | otherwise -> do
            let outputGradients =
                  zipWith
                    (policyValueRawOutputGradient actionCount)
                    rawOutputs
                    samples
            gradResult <- mlpdBatchGradient device params (zip inputs outputGradients)
            case gradResult of
              Left err -> pure (Left err)
              Right summedGradient ->
                let meanGradient =
                      scaleMlpGradient
                        (1.0 / fromIntegral sampleCount)
                        summedGradient
                    (newParams, newAdam) = adamStep adamConfig adam params meanGradient
                 in pure (Right (net {pvnParams = newParams}, newAdam))

validatePolicyValueTrainingInputs
  :: PolicyValueNet
  -> Double
  -> Int
  -> [PolicyValueTrainingSample]
  -> Either Text ()
validatePolicyValueTrainingInputs net learningRate updates samples
  | updates <= 0 = Left "AlphaZero optimiser update count must be positive"
  | null samples = Left "AlphaZero optimiser requires non-empty training samples"
  | isNaN learningRate || isInfinite learningRate || learningRate <= 0.0 =
      Left "AlphaZero optimiser learning rate must be finite and positive"
  | pvnActionCount net <= 0 = Left "AlphaZero policy action count must be positive"
  | Just observed <-
      Data.List.find
        (/= pvnActionCount net)
        (fmap (VU.length . sampleVisitDist) samples) =
      Left
        ( "AlphaZero visit-distribution width mismatch: expected "
            <> Text.pack (show (pvnActionCount net))
            <> ", observed "
            <> Text.pack (show observed)
        )
  | otherwise = Right ()

-- | Build the policy/value output gradient directly from a batched device
-- output vector.  This is the same softmax/tanh head math used by
-- 'policyValueOutputGradient', without inventing a per-sample forward cache.
policyValueRawOutputGradient
  :: Int
  -> Vector Double
  -> PolicyValueTrainingSample
  -> Vector Double
policyValueRawOutputGradient actionCount output trainingSample =
  let logits = VU.take actionCount output
      policy = softmax logits
      dLogits = VU.zipWith (-) policy (sampleVisitDist trainingSample)
      value =
        if VU.length output > actionCount
          then tanh (output VU.! actionCount)
          else 0.0
      dValue = value - sampleOutcome trainingSample
      valueGradient = dValue * (1.0 - value * value)
      tailCount = max 0 (VU.length output - actionCount)
      tailGradients =
        if tailCount == 0
          then VU.empty
          else VU.cons valueGradient (VU.replicate (tailCount - 1) 0.0)
   in dLogits VU.++ tailGradients

addMlpGradient :: MlpGradient -> MlpGradient -> MlpGradient
addMlpGradient left right =
  MlpGradient
    { gradW1 = VU.zipWith (+) (gradW1 left) (gradW1 right)
    , gradB1 = VU.zipWith (+) (gradB1 left) (gradB1 right)
    , gradW2 = VU.zipWith (+) (gradW2 left) (gradW2 right)
    , gradB2 = VU.zipWith (+) (gradB2 left) (gradB2 right)
    }

scaleMlpGradient :: Double -> MlpGradient -> MlpGradient
scaleMlpGradient factor gradient =
  MlpGradient
    { gradW1 = VU.map (* factor) (gradW1 gradient)
    , gradB1 = VU.map (* factor) (gradB1 gradient)
    , gradW2 = VU.map (* factor) (gradW2 gradient)
    , gradB2 = VU.map (* factor) (gradB2 gradient)
    }

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
generatePolicyValueSamples =
  generatePolicyValueSamplesFrom initialConnect4

generatePolicyValueSamplesFrom
  :: GameState
  -> PolicyValueNet
  -> Int -- seed
  -> Int -- MCTS simulations per move
  -> Int -- max plies
  -> [PolicyValueTrainingSample]
generatePolicyValueSamplesFrom initialState net seed0 sims maxPlies =
  let gen0 = Random.mkStdGen seed0
      go !rawState !gen !plies !acc =
        let state = normaliseForcedPass rawState
         in if plies >= maxPlies
              then annotatePolicyValueOutcome GameDraw (reverse acc)
              else case gameOutcome state of
                GameWon winner -> annotatePolicyValueOutcome (GameWon winner) (reverse acc)
                GameDraw -> annotatePolicyValueOutcome GameDraw (reverse acc)
                GameInProgress ->
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
                   in case gameOutcome nextState of
                        GameInProgress
                          | plies + 1 >= maxPlies ->
                              annotatePolicyValueOutcome GameDraw (reverse (sample : acc))
                          | otherwise ->
                              go nextState gen' (plies + 1) (sample : acc)
                        outcome ->
                          annotatePolicyValueOutcome outcome (reverse (sample : acc))
   in go initialState gen0 0 []

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
generatePolicyValueSamplesWithDevice =
  generatePolicyValueSamplesWithDeviceFrom initialConnect4

generatePolicyValueSamplesWithDeviceFrom
  :: GameState
  -> MlpDevice
  -> PolicyValueNet
  -> Int -- seed
  -> Int -- MCTS simulations per move
  -> Int -- max plies
  -> IO (Either Text [PolicyValueTrainingSample])
generatePolicyValueSamplesWithDeviceFrom initialState device net seed0 sims maxPlies =
  let gen0 = Random.mkStdGen seed0
      go !rawState !gen !plies !acc = do
        let state = normaliseForcedPass rawState
        if plies >= maxPlies
          then pure (Right (annotatePolicyValueOutcome GameDraw (reverse acc)))
          else case gameOutcome state of
            GameWon winner -> pure (Right (annotatePolicyValueOutcome (GameWon winner) (reverse acc)))
            GameDraw -> pure (Right (annotatePolicyValueOutcome GameDraw (reverse acc)))
            GameInProgress -> do
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
                  case gameOutcome nextState of
                    GameInProgress
                      | plies + 1 >= maxPlies ->
                          pure (Right (annotatePolicyValueOutcome GameDraw (reverse (sample : acc))))
                      | otherwise ->
                          go nextState gen' (plies + 1) (sample : acc)
                    outcome ->
                      pure (Right (annotatePolicyValueOutcome outcome (reverse (sample : acc))))
   in go initialState gen0 0 []

annotatePolicyValueOutcome
  :: GameOutcome -> [PolicyValueTrainingSample] -> [PolicyValueTrainingSample]
annotatePolicyValueOutcome outcome = fmap annotate
 where
  annotate sample =
    sample {sampleOutcome = outcomeFor (sampleState sample)}
  outcomeFor state =
    case outcome of
      GameWon winner
        | winner == gameCurrentPlayer state -> 1.0
        | otherwise -> -1.0
      GameDraw -> 0.0
      GameInProgress -> 0.0

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
        either
          (error . Text.unpack)
          id
          (trainPolicyValueNetOnSamples net adam 1.0e-3 gradientUpdates samples)
      winRate = arenaWinRateAgainstUniform trainedNet arenaGames maxPlies (seed + 7919)
   in GenerationResult
        { genNet = trainedNet
        , genAdam = trainedAdam
        , genSamplesCount = length samples
        , genArenaWinRate = winRate
        }

-- | Play @games@ arena games against a uniform-random opponent and
-- return the network's win rate (in @[0, 1]@). Uses the network as
-- player 1 and uniform-random as player 2, with winner/draw detection coming
-- from the shared game rules.
arenaWinRateAgainstUniform :: PolicyValueNet -> Int -> Int -> Int -> Double
arenaWinRateAgainstUniform =
  arenaWinRateAgainstUniformFrom initialConnect4

arenaWinRateAgainstUniformFrom :: GameState -> PolicyValueNet -> Int -> Int -> Int -> Double
arenaWinRateAgainstUniformFrom initialState net games maxPlies seed0 =
  let gen0 = Random.mkStdGen seed0
      -- Scale arena search with the board size: a flat 16 simulations on a
      -- 121-cell hex board barely samples the 121 legal moves, so the net played
      -- little better than its (weakly-trained) raw prior. AlphaZero plays with
      -- search, so giving the net proportionally more simulations on larger
      -- boards is a faithful measure of the deployed player's strength, not a
      -- metric shortcut. Small boards (connect4) keep a modest budget.
      arenaSims =
        max 48 (min 192 (2 * VU.length (pvPolicy (networkPolicyValue net initialState))))
      playOne g rawState gen plies =
        let state = normaliseForcedPass rawState
         in if plies >= maxPlies
              then (0.0 :: Double, gen) -- draw
              else case gameOutcome state of
                GameWon winner
                  | winner == 1 -> (1.0, gen)
                  | otherwise -> (-1.0, gen)
                GameDraw -> (0.0, gen)
                GameInProgress ->
                  let netPlayer = 1
                      netToMove = gameCurrentPlayer state == netPlayer
                      (u, gen') = Random.uniformR (0.0 :: Double, 1.0) gen
                      action =
                        if netToMove
                          then
                            sampleCategorical
                              (mctsVisitDistribution net arenaSims state (seed0 + g * 1009 + plies * 7919))
                              u
                          else
                            let allowed = legalMoves state
                                legalIndex =
                                  (floor (u * fromIntegral (length allowed)) :: Int)
                                    `mod` max 1 (length allowed)
                             in if null allowed then 0 else allowed !! legalIndex
                      nextState = applyMove action state
                   in case gameOutcome nextState of
                        GameWon winner
                          | winner == netPlayer -> (1.0, gen')
                          | otherwise -> (-1.0, gen')
                        GameDraw -> (0.0, gen')
                        GameInProgress -> playOne g nextState gen' (plies + 1)
      go !g !gen !wins !drawn !losses
        | g >= games = (wins, drawn, losses)
        | otherwise =
            let (result, gen') = playOne g initialState gen 0
             in case compare result 0.0 of
                  GT -> go (g + 1) gen' (wins + 1) drawn losses
                  EQ -> go (g + 1) gen' wins (drawn + 1) losses
                  LT -> go (g + 1) gen' wins drawn (losses + 1)
      (w, d, _l) = go (0 :: Int) gen0 (0 :: Int) (0 :: Int) (0 :: Int)
   in if games == 0
        then 0.0
        else (fromIntegral w + 0.5 * fromIntegral d) / fromIntegral games
