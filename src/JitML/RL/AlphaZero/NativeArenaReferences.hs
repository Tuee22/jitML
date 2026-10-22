{-# LANGUAGE OverloadedStrings #-}

-- | Raw prospective native arena references. These values prove neither
-- provider execution nor learned-model qualification or a probability claim.
module JitML.RL.AlphaZero.NativeArenaReferences
  ( NativeArenaSpec
  , NativeArenaReference (..)
  , NativeArenaDecision (..)
  , NativeArenaEpisode (..)
  , NativeArenaObservation (..)
  , NativeArenaReferenceSet (..)
  , nativeArenaReferenceContract
  , canonicalNativeArenaSpec
  , mkCanonicalNativeArenaSpec
  , allCanonicalNativeArenaSpecs
  , nativeArenaSpecRowId
  , nativeArenaSpecTrainingBudget
  , nativeArenaSpecTrainingSimulations
  , nativeArenaSpecActionCount
  , nativeArenaSpecObservationSize
  , nativeArenaSpecMaxPlies
  , nativeArenaSpecArenaSimulations
  , nativeArenaSpecTape
  , materializeNativeArenaTape
  , evaluateNativeArenaReferences
  , evaluateNativeArenaReference
  , evaluateNativeArenaReferenceFixture
  , neutralNativeArenaOracle
  , nativeArenaUniformDistribution
  , sampleNativeArenaPlayerAction
  , sampleNativeArenaPlayerAtUnit
  , sampleNativeArenaOpponentAction
  ) where

import Control.Monad (foldM, unless)
import Data.Either.Combinators (mapLeft)
import Data.List (group, sort)
import Data.Ratio ((%))
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)

import JitML.Numerics.Mlp (sampleCategorical)
import JitML.RL.AlphaZero qualified as Game
import JitML.RL.AlphaZero.ArenaTape qualified as Tape
import JitML.RL.AlphaZero.Mcts qualified as Mcts
import JitML.RL.AlphaZero.PolicyValueNet qualified as Net
import JitML.RL.ConvergenceThresholds qualified as Thresholds
import JitML.Training.Budget
  ( BudgetKind (..)
  , TrainingBudget
  , trainingBudgetKind
  , trainingBudgetTargetUnits
  )

nativeArenaReferenceContract :: Text
nativeArenaReferenceContract = "native-arena-game-aware-uniform-and-neutral-mcts-addressed-tape-v1"

-- Private constructor; ordinary observers cannot update refined metadata.
data NativeArenaSpec
  = NativeArenaSpec !Thresholds.AlphaZeroGameConvergenceRow !Int !Int !Int !Int !Tape.ArenaTapeSpec
  deriving stock (Eq, Show)

data NativeArenaReference = PlainLegalUniform | NeutralLegalMcts
  deriving stock (Eq, Ord, Show, Enum, Bounded)

data NativeArenaDecision = NativeArenaDecision
  { nativeArenaDecisionSlot :: !Int
  , nativeArenaDecisionRawState :: !Game.GameState
  , nativeArenaDecisionNormalizedState :: !Game.GameState
  , nativeArenaDecisionForcedPass :: !Bool
  , nativeArenaDecisionPlayer :: !Int
  , nativeArenaDecisionLegalActions :: ![Int]
  , nativeArenaDecisionDistribution :: !(VU.Vector Double)
  , nativeArenaDecisionAction :: !Int
  , nativeArenaDecisionTapeEntry :: !Tape.ArenaTapeEntry
  , nativeArenaDecisionSearchRootVisits :: !Int
  , nativeArenaDecisionPostState :: !Game.GameState
  , nativeArenaDecisionPostOutcome :: !Game.GameOutcome
  }
  deriving stock (Eq, Show)

data NativeArenaEpisode = NativeArenaEpisode
  { nativeArenaEpisodeId :: !Int
  , nativeArenaEpisodeInitialState :: !Game.GameState
  , nativeArenaEpisodeFinalState :: !Game.GameState
  , nativeArenaEpisodeRuleOutcome :: !Game.GameOutcome
  , nativeArenaEpisodeScoredOutcome :: !Game.GameOutcome
  , nativeArenaEpisodeHorizonTruncated :: !Bool
  , nativeArenaEpisodeDecisions :: ![NativeArenaDecision]
  }
  deriving stock (Eq, Show)

data NativeArenaObservation = NativeArenaObservation
  { nativeArenaObservedReference :: !NativeArenaReference
  , nativeArenaObservedTape :: !Tape.ArenaTape
  , nativeArenaObservedEpisodes :: ![NativeArenaEpisode]
  , nativeArenaObservedWins :: !Int
  , nativeArenaObservedDraws :: !Int
  , nativeArenaObservedLosses :: !Int
  , nativeArenaObservedScore :: !Double
  , nativeArenaObservedExactScore :: !Rational
  , nativeArenaObservedEvaluationTransitions :: !Integer
  , nativeArenaObservedSearchRootVisits :: !Integer
  }
  deriving stock (Eq, Show)

data NativeArenaReferenceSet = NativeArenaReferenceSet
  { nativeArenaObservedSpec :: !NativeArenaSpec
  , nativeArenaObservedReferences :: ![NativeArenaObservation]
  , nativeArenaTotalEvaluationTransitions :: !Integer
  , nativeArenaTotalSearchRootVisits :: !Integer
  }
  deriving stock (Eq, Show)

canonicalNativeArenaSpec :: Text -> Either Text NativeArenaSpec
canonicalNativeArenaSpec game = case filter ((== game) . Thresholds.azgGame) Thresholds.alphaZeroGameConvergenceRows of
  [row] -> mkCanonicalNativeArenaSpec row
  _ -> Left "native arena reference game is not an exact canonical row"

allCanonicalNativeArenaSpecs :: Either Text [NativeArenaSpec]
allCanonicalNativeArenaSpecs = traverse mkCanonicalNativeArenaSpec Thresholds.alphaZeroGameConvergenceRows

mkCanonicalNativeArenaSpec :: Thresholds.AlphaZeroGameConvergenceRow -> Either Text NativeArenaSpec
mkCanonicalNativeArenaSpec row = do
  let game = Thresholds.azgGame row
      declared = filter ((== game) . Thresholds.azgGame) Thresholds.alphaZeroGameConvergenceRows
      actions = Game.actionCountFor game
      observations = Game.observationSizeFor game
      horizon = Game.maxPliesFor game
      simulations = fromInteger (max 48 (min 192 (2 * toInteger actions)))
  require
    (declared == [row])
    "native arena reference declaration differs from the complete canonical row"
  require
    ( game `elem` ["connect4", "othello", "hex", "gomoku"]
        && length (filter ((== game) . Game.pigName) Game.canonicalGames) == 1
    )
    "native arena reference game is outside the supported canonical family"
  require
    ( actions > 0
        && observations > 0
        && horizon > 0
        && Game.gameName (Game.initialStateFor game) == game
        && Game.gameCurrentPlayer (Game.initialStateFor game) == 1
        && Game.policyHeadSize (Game.twoHeadedNetworkFor game) == actions
        && Game.valueHeadSize (Game.twoHeadedNetworkFor game) == 1
    )
    "native arena reference game metadata differs"
  require
    ( trainingBudgetKind (Thresholds.azgBudget row) == AlphaZeroSelfPlayBudget
        && trainingBudgetTargetUnits (Thresholds.azgBudget row) == Thresholds.alphaZeroGenerationBudget game
        && Thresholds.azgMctsSimulationsPerMove row == Thresholds.alphaZeroSimulationBudget game
    )
    "native arena reference training declaration differs"
  tape <- tapeError (Tape.mkArenaTapeSpec game (42 + 7919) 9 (fromIntegral horizon))
  pure (NativeArenaSpec row actions observations horizon simulations tape)

nativeArenaSpecRowId :: NativeArenaSpec -> Text
nativeArenaSpecRowId (NativeArenaSpec row _ _ _ _ _) = Thresholds.azgGame row
nativeArenaSpecTrainingBudget :: NativeArenaSpec -> TrainingBudget
nativeArenaSpecTrainingBudget (NativeArenaSpec row _ _ _ _ _) = Thresholds.azgBudget row
nativeArenaSpecTrainingSimulations :: NativeArenaSpec -> Word64
nativeArenaSpecTrainingSimulations (NativeArenaSpec row _ _ _ _ _) = Thresholds.azgMctsSimulationsPerMove row
nativeArenaSpecActionCount :: NativeArenaSpec -> Int
nativeArenaSpecActionCount (NativeArenaSpec _ value _ _ _ _) = value
nativeArenaSpecObservationSize :: NativeArenaSpec -> Int
nativeArenaSpecObservationSize (NativeArenaSpec _ _ value _ _ _) = value
nativeArenaSpecMaxPlies :: NativeArenaSpec -> Int
nativeArenaSpecMaxPlies (NativeArenaSpec _ _ _ value _ _) = value
nativeArenaSpecArenaSimulations :: NativeArenaSpec -> Int
nativeArenaSpecArenaSimulations (NativeArenaSpec _ _ _ _ value _) = value
nativeArenaSpecTape :: NativeArenaSpec -> Tape.ArenaTapeSpec
nativeArenaSpecTape (NativeArenaSpec _ _ _ _ _ value) = value
materializeNativeArenaTape :: NativeArenaSpec -> Tape.ArenaTape
materializeNativeArenaTape = Tape.materializeArenaTape . nativeArenaSpecTape

evaluateNativeArenaReferences
  :: NativeArenaSpec -> Tape.ArenaTape -> IO (Either Text NativeArenaReferenceSet)
evaluateNativeArenaReferences spec tape = do
  observations <-
    mapEitherIO (evaluateNativeArenaReference spec tape) [PlainLegalUniform, NeutralLegalMcts]
  pure $ do
    values <- observations
    pure
      ( NativeArenaReferenceSet
          spec
          values
          (sum (fmap nativeArenaObservedEvaluationTransitions values))
          (sum (fmap nativeArenaObservedSearchRootVisits values))
      )

evaluateNativeArenaReference
  :: NativeArenaSpec -> Tape.ArenaTape -> NativeArenaReference -> IO (Either Text NativeArenaObservation)
evaluateNativeArenaReference spec tape reference = case validateCanonical spec tape of
  Left reason -> pure (Left reason)
  Right () ->
    evaluateNativeArenaReferenceFixture
      (Game.initialStateFor (nativeArenaSpecRowId spec))
      tape
      reference

validateCanonical :: NativeArenaSpec -> Tape.ArenaTape -> Either Text ()
validateCanonical spec tape = do
  canonical <- canonicalNativeArenaSpec (nativeArenaSpecRowId spec)
  require
    (spec == canonical)
    "native arena reference specification differs from the complete current declaration"
  require
    (Tape.arenaTapeSpec tape == nativeArenaSpecTape spec)
    "native arena reference requires the complete exact row-owned canonical tape descriptor"

-- | Explicit bounded raw-data fixture seam, not a canonical run declaration.
-- Uses only the actual four games and their actual game-aware rule functions.
evaluateNativeArenaReferenceFixture
  :: Game.GameState -> Tape.ArenaTape -> NativeArenaReference -> IO (Either Text NativeArenaObservation)
evaluateNativeArenaReferenceFixture initial tape reference = case validateFixture initial tape of
  Left reason -> pure (Left reason)
  Right (actions, simulations, games, horizon) -> do
    played <- mapEitherIO (playOne actions simulations horizon) [0 .. games - 1]
    pure $ do
      episodes <- played
      let wins = length [() | episode <- episodes, nativeArenaEpisodeScoredOutcome episode == Game.GameWon 1]
          draws = length [() | episode <- episodes, nativeArenaEpisodeScoredOutcome episode == Game.GameDraw]
          losses = length [() | episode <- episodes, nativeArenaEpisodeScoredOutcome episode == Game.GameWon (-1)]
          decisions = concatMap nativeArenaEpisodeDecisions episodes
      require
        (wins + draws + losses == games)
        "native arena reference has an unfinished or unknown outcome"
      pure
        ( NativeArenaObservation
            reference
            tape
            episodes
            wins
            draws
            losses
            ((fromIntegral wins + 0.5 * fromIntegral draws) / fromIntegral games)
            ((2 * toInteger wins + toInteger draws) % (2 * toInteger games))
            (toInteger (length decisions))
            (sum (fmap (toInteger . nativeArenaDecisionSearchRootVisits) decisions))
        )
 where
  finish game state truncated outcome decisions =
    Right
      (NativeArenaEpisode game initial state (Game.gameOutcome state) outcome truncated (reverse decisions))
  playOne actions simulations horizon game = loop 0 initial []
   where
    loop slot raw decisions =
      let state = Game.normaliseForcedPass raw
       in if slot >= horizon
            then pure (finish game state True Game.GameDraw decisions)
            else case Game.gameOutcome state of
              Game.GameInProgress -> case decisionInput actions game slot state of
                Left reason -> pure (Left reason)
                Right (allowed, entry) -> do
                  distribution <-
                    if Game.gameCurrentPlayer state == 1 && reference == NeutralLegalMcts
                      then neutralDistribution actions simulations state (Tape.arenaEntryMctsSeed entry)
                      else pure (fmap (,0) (nativeArenaUniformDistribution actions allowed))
                  case distribution of
                    Left reason -> pure (Left reason)
                    Right (probabilities, rootVisits) -> case choose actions allowed state probabilities entry of
                      Left reason -> pure (Left reason)
                      Right action -> do
                        let next = Game.applyMove action state
                            outcome = Game.gameOutcome next
                            observed =
                              NativeArenaDecision
                                slot
                                raw
                                state
                                (raw /= state)
                                (Game.gameCurrentPlayer state)
                                allowed
                                probabilities
                                action
                                entry
                                rootVisits
                                next
                                outcome
                            kept = observed : decisions
                        case outcome of
                          Game.GameInProgress -> loop (slot + 1) next kept
                          Game.GameDraw -> pure (finish game next False Game.GameDraw kept)
                          Game.GameWon winner -> pure (finish game next False (Game.GameWon winner) kept)
              Game.GameDraw -> pure (finish game state False Game.GameDraw decisions)
              Game.GameWon winner -> pure (finish game state False (Game.GameWon winner) decisions)
  decisionInput actions game slot state = do
    validateSignedPlayer state
    let allowed = Game.legalMoves state
    validateLegal actions allowed
    entry <-
      tapeError
        (Tape.arenaTapeLookup tape (fromIntegral game) (fromIntegral slot) (Game.gameCurrentPlayer state))
    pure (allowed, entry)
  choose actions allowed state probabilities entry
    | Game.gameCurrentPlayer state == 1 =
        sampleNativeArenaPlayerAction actions allowed probabilities entry
    | otherwise = sampleNativeArenaOpponentAction actions allowed entry

validateFixture :: Game.GameState -> Tape.ArenaTape -> Either Text (Int, Int, Int, Int)
validateFixture initial tape = do
  let game = Game.gameName initial
      descriptor = Tape.arenaTapeSpec tape
      games = Tape.arenaTapeSpecGames descriptor
      horizon = Tape.arenaTapeSpecMaxPlies descriptor
  require
    (game `elem` ["connect4", "othello", "hex", "gomoku"])
    "native arena fixture game is unsupported"
  validateSignedPlayer initial
  require
    (Tape.arenaTapeSpecRow descriptor == game)
    "native arena fixture tape row differs from its actual game"
  require
    (games >= 1 && games <= 9 && horizon >= 1 && toInteger horizon <= toInteger (Game.maxPliesFor game))
    "native arena fixture exceeds its bounded game or move counts"
  let actions = Game.actionCountFor game
      simulations = fromInteger (max 48 (min 192 (2 * toInteger actions)))
  pure (actions, simulations, fromIntegral games, fromIntegral horizon)

neutralDistribution
  :: Int -> Int -> Game.GameState -> Int -> IO (Either Text (VU.Vector Double, Int))
neutralDistribution actions simulations state seed = do
  let config = (Mcts.defaultMctsConfig actions) {Mcts.mctsSimulations = simulations}
  result <- Mcts.runSearchWithPriorIO (pure . neutralNativeArenaOracle actions state) config seed
  pure $ do
    tree <- result
    let allowed = Game.legalMoves (Game.normaliseForcedPass state)
        probabilities = Net.visitDistributionFromTree actions allowed tree
    validateDistribution actions allowed probabilities
    require
      (Mcts.nodeVisits tree == simulations)
      "native arena neutral search root visits differ from its budget"
    pure (probabilities, Mcts.nodeVisits tree)

-- A real game-aware reference oracle. No network/device or defaultPriorOracle.
-- The validation walk permits only legal real transitions, then requires the
-- exact existing production path projection to yield the same position.
neutralNativeArenaOracle :: Int -> Game.GameState -> [Int] -> Either Text Mcts.NodeEval
neutralNativeArenaOracle actions root moves = do
  require
    ( Game.gameName root `elem` ["connect4", "othello", "hex", "gomoku"]
        && actions == Game.actionCountFor (Game.gameName root)
    )
    "native arena neutral oracle game or action width differs"
  validateSignedPlayer root
  checkedState <- foldM applyChecked (Game.normaliseForcedPass root) moves
  let state = Net.applySearchPath root moves
  require (state == checkedState) "native arena neutral oracle production path differs"
  validateSignedPlayer state
  case Game.gameOutcome state of
    Game.GameInProgress -> do
      probabilities <- nativeArenaUniformDistribution actions (Game.legalMoves state)
      pure (Mcts.NodeEval (VU.toList probabilities) 0 False (Just (Game.gameCurrentPlayer state)))
    _ ->
      pure
        (Mcts.NodeEval [] (Game.terminalValueForToMove state) True (Just (Game.gameCurrentPlayer state)))
 where
  applyChecked raw action = do
    let state = Game.normaliseForcedPass raw
    require
      (Game.gameOutcome state == Game.GameInProgress)
      "native arena neutral oracle path continues after terminal"
    let allowed = Game.legalMoves state
    validateLegal actions allowed
    require (action `elem` allowed) "native arena neutral oracle path contains an illegal move"
    pure (Game.normaliseForcedPass (Game.applyMove action state))

nativeArenaUniformDistribution :: Int -> [Int] -> Either Text (VU.Vector Double)
nativeArenaUniformDistribution actions allowed = do
  validateLegal actions allowed
  pure
    ( VU.generate
        actions
        (\action -> if action `elem` allowed then 1 / fromIntegral (length allowed) else 0)
    )

sampleNativeArenaPlayerAction
  :: Int -> [Int] -> VU.Vector Double -> Tape.ArenaTapeEntry -> Either Text Int
sampleNativeArenaPlayerAction actions allowed probabilities entry =
  sampleNativeArenaPlayerAtUnit actions allowed probabilities (Tape.arenaEntryUnit entry)

-- Raw selector seam shared by the actual tape consumer and finite branch
-- controls. It confers no distribution producer, execution or qualification.
sampleNativeArenaPlayerAtUnit :: Int -> [Int] -> VU.Vector Double -> Double -> Either Text Int
sampleNativeArenaPlayerAtUnit actions allowed probabilities unit = do
  validateDistribution actions allowed probabilities
  validateUnit unit
  let chosen = sampleCategorical probabilities unit
  require
    (chosen >= 0 && chosen < actions && chosen `elem` allowed && probabilities VU.! chosen > 0)
    "native arena reference sampled an illegal or zero-mass player action"
  pure chosen

sampleNativeArenaOpponentAction :: Int -> [Int] -> Tape.ArenaTapeEntry -> Either Text Int
sampleNativeArenaOpponentAction actions allowed entry = do
  validateLegal actions allowed
  validateUnit (Tape.arenaEntryUnit entry)
  let index = (floor (Tape.arenaEntryUnit entry * fromIntegral (length allowed)) :: Int) `mod` length allowed
  case drop index allowed of
    selected : _ -> Right selected
    [] -> Left "native arena reference opponent index differs from the legal domain"

validateLegal :: Int -> [Int] -> Either Text ()
validateLegal actions allowed =
  require
    ( actions > 0
        && actions <= Game.gomokuActionCount
        && not (null allowed)
        && all (\action -> action >= 0 && action < actions) allowed
        && length (group (sort allowed)) == length allowed
    )
    "native arena reference legal-action domain is empty malformed or duplicated"

validateDistribution :: Int -> [Int] -> VU.Vector Double -> Either Text ()
validateDistribution actions allowed probabilities = do
  validateLegal actions allowed
  require
    ( VU.length probabilities == actions
        && VU.all (\value -> finite value && value >= 0) probabilities
        && finite (VU.sum probabilities)
        && VU.sum probabilities > 0
        && and
          [ probability == 0 || action `elem` allowed
          | (action, probability) <- zip [0 :: Int ..] (VU.toList probabilities)
          ]
    )
    "native arena reference distribution has invalid width finite mass or legal support"
  -- Actual reference entries are correctly-rounded 1/k or integer visits/t,
  -- with exact integer t<=192. Each division has relative error<=2^-53;
  -- summing their exact Rational values therefore differs from1 by<=2^-53.
  -- This checks representation, never a learning/quality tolerance, and does
  -- not claim an arbitrary caller supplied an actual generated distribution.
  let exactMass = sum (fmap toRational (VU.toList probabilities))
  require
    (abs (exactMass - 1) <= 1 % 9007199254740992)
    "native arena reference distribution mass is not a normalized binary64 representation"

validateUnit :: Double -> Either Text ()
validateUnit unit =
  require
    (finite unit && unit >= 0 && unit < 1)
    "native arena reference unit variate is outside [0,1)"

validateSignedPlayer :: Game.GameState -> Either Text ()
validateSignedPlayer state =
  require
    (Game.gameCurrentPlayer state `elem` [1, -1])
    "native arena reference signed player is invalid"
finite :: Double -> Bool
finite value = not (isNaN value || isInfinite value)
require :: Bool -> Text -> Either Text ()
require condition reason = unless condition (Left reason)
tapeError :: Either Tape.ArenaTapeError value -> Either Text value
tapeError = mapLeft (("native arena tape: " <>) . Text.pack . show)
mapEitherIO :: (value -> IO (Either Text result)) -> [value] -> IO (Either Text [result])
mapEitherIO _ [] = pure (Right [])
mapEitherIO action (value : rest) = do
  current <- action value
  case current of
    Left reason -> pure (Left reason)
    Right result -> fmap (fmap (result :)) (mapEitherIO action rest)
