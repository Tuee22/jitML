{-# LANGUAGE OverloadedStrings #-}

-- | Numerical paired-arena observations only. Raw constructors and successful
-- unit predicates grant no training, device/provider origin or qualification.
module JitML.RL.AlphaZero.NativeArenaEvaluation
  ( NativeArenaScope (..)
  , NativeArenaInput (..)
  , NativeArenaForwardOutcome (..)
  , NativeArenaForwardObservation (..)
  , NativeArenaForwardSummary (..)
  , NativeArenaCaseProgress (..)
  , NativeArenaSearchWork (..)
  , NativeArenaEvaluationWork (..)
  , NativeArenaFailureKind (..)
  , NativeArenaEvaluationStatus (..)
  , RawNativeArenaEvaluation (..)
  , nativeArenaEvaluationContract
  , evaluateNativeArenaPolicy
  , evaluateNativeArenaPolicyFixture
  , validateNativeArenaPolicyContext
  , validateNativeArenaEvaluationData
  , validateNativeArenaFixtureData
  , nativeArenaEvaluationExactScore
  , nativeArenaEvaluationScore
  ) where

import Control.Exception (SomeException, evaluate)
import Control.Exception.Safe (displayException, throwIO, tryAny)
import Control.Monad (foldM, unless, void)
import Data.ByteString qualified as BS
import Data.Either (fromRight)
import Data.Either.Combinators (mapLeft)
import Data.IORef (IORef, atomicModifyIORef', modifyIORef', newIORef, readIORef)
import Data.List (find, nub)
import Data.Maybe (isJust, isNothing)
import Data.Ratio ((%))
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import Foreign.C.Types (CInt)
import GHC.Float (castDoubleToWord64)

import JitML.Numerics.Mlp qualified as Mlp
import JitML.Numerics.MlpDevice (MlpDevice (..))
import JitML.RL.AlphaZero qualified as Game
import JitML.RL.AlphaZero.ArenaTape qualified as Tape
import JitML.RL.AlphaZero.Mcts qualified as Mcts
import JitML.RL.AlphaZero.NativeArenaReferences qualified as Ref
import JitML.RL.AlphaZero.PolicyValueNet qualified as Net

nativeArenaEvaluationContract :: Text
nativeArenaEvaluationContract = "native-learned-addressed-arena-data-v1"

data NativeArenaScope = CanonicalNativeArena | BoundedNativeArenaFixture deriving stock (Eq, Show)
data NativeArenaInput = NativeArenaInput
  { nativeArenaInputScope :: !NativeArenaScope
  , nativeArenaInputSpecification :: !(Maybe Ref.NativeArenaSpec)
  , nativeArenaInputInitialState :: !Game.GameState
  , nativeArenaInputTape :: !Tape.ArenaTape
  , nativeArenaInputPolicy :: !Net.PolicyValueNet
  }
  deriving stock (Eq, Show)
data NativeArenaForwardOutcome
  = NativeArenaForwardReturned !(Either Text (VU.Vector Double))
  | NativeArenaForwardException !Text
  deriving stock (Eq, Show)
data NativeArenaForwardObservation = NativeArenaForwardObservation
  { nativeArenaForwardGame :: !Int
  , nativeArenaForwardSlot :: !Int
  , nativeArenaForwardOrdinal :: !Integer
  , nativeArenaForwardParameters :: !Mlp.MlpParams
  , nativeArenaForwardInput :: !(VU.Vector Double)
  , nativeArenaForwardOutcome :: !NativeArenaForwardOutcome
  }
  deriving stock (Eq, Show)

-- First actual call per case plus the actual failed/malformed call, not a
-- complete leaf transcript. A malformed Right remains recorded as a Right.
data NativeArenaForwardSummary = NativeArenaForwardSummary
  { nativeArenaForwardCalls :: !Integer
  , nativeArenaFirstForwards :: ![NativeArenaForwardObservation]
  , nativeArenaFailedForward :: !(Maybe NativeArenaForwardObservation)
  }
  deriving stock (Eq, Show)
data NativeArenaCaseProgress = NativeArenaCaseProgress
  { nativeArenaProgressGame :: !Int
  , nativeArenaProgressTransitions :: !Int
  , nativeArenaProgressState :: !Game.GameState
  , nativeArenaProgressDecisions :: ![Ref.NativeArenaDecision]
  }
  deriving stock (Eq, Show)
data NativeArenaSearchWork = NoUnfinishedArenaSearch | UnknownUnfinishedArenaSearch
  deriving stock (Eq, Show)
data NativeArenaEvaluationWork = NativeArenaEvaluationWork
  { nativeArenaCompletedEpisodeTransitions :: !Integer
  , nativeArenaCurrentEpisodeTransitions :: !Integer
  , nativeArenaCompletedSearchRootVisits :: !Integer
  , nativeArenaUnfinishedSearch :: !NativeArenaSearchWork
  }
  deriving stock (Eq, Show)
data NativeArenaFailureKind
  = NativeArenaInputException
  | NativeArenaStateException
  | NativeArenaSearchRejected
  | NativeArenaSearchException
  | NativeArenaSelectionRejected
  | NativeArenaSelectionException
  | NativeArenaTransitionException
  deriving stock (Eq, Show)
data NativeArenaEvaluationStatus
  = NativeArenaEvaluationComplete
  | NativeArenaEvaluationRejected !Text
  | NativeArenaEvaluationFailed !Int !Int !NativeArenaFailureKind !Text
  deriving stock (Eq, Show)
data RawNativeArenaEvaluation = RawNativeArenaEvaluation
  { nativeArenaEvaluationInput :: !(Maybe NativeArenaInput)
  , nativeArenaEvaluationEpisodes :: ![Ref.NativeArenaEpisode]
  , nativeArenaEvaluationProgress :: !(Maybe NativeArenaCaseProgress)
  , nativeArenaEvaluationForwards :: !NativeArenaForwardSummary
  , nativeArenaEvaluationStatus :: !NativeArenaEvaluationStatus
  , nativeArenaEvaluationWork :: !NativeArenaEvaluationWork
  }
  deriving stock (Eq, Show)

data Acc = Acc
  { accInput :: !(Maybe NativeArenaInput)
  , accEpisodes :: ![Ref.NativeArenaEpisode]
  , accProgress :: !(Maybe NativeArenaCaseProgress)
  , accCurrentTransitions :: !Integer
  , accVisits :: !Integer
  , accUnfinished :: !NativeArenaSearchWork
  , accForwards :: !NativeArenaForwardSummary
  }

evaluateNativeArenaPolicy
  :: MlpDevice
  -> Ref.NativeArenaSpec
  -> Tape.ArenaTape
  -> Net.PolicyValueNet
  -> IO RawNativeArenaEvaluation
evaluateNativeArenaPolicy device spec tape net =
  evaluateInput
    device
    ( NativeArenaInput
        CanonicalNativeArena
        (Just spec)
        (Game.initialStateFor (Ref.nativeArenaSpecRowId spec))
        tape
        net
    )

evaluateNativeArenaPolicyFixture
  :: Game.GameState -> MlpDevice -> Tape.ArenaTape -> Net.PolicyValueNet -> IO RawNativeArenaEvaluation
evaluateNativeArenaPolicyFixture initial device tape net =
  evaluateInput device (NativeArenaInput BoundedNativeArenaFixture Nothing initial tape net)

-- Both public routes share this sole arena loop. Only actual game/search
-- operations supply its decisions; no arbitrary oracle/result factory exists.
evaluateInput :: MlpDevice -> NativeArenaInput -> IO RawNativeArenaEvaluation
evaluateInput device supplied = do
  ref <-
    newIORef
      (Acc Nothing [] Nothing 0 0 NoUnfinishedArenaSearch (NativeArenaForwardSummary 0 [] Nothing))
  observed <- tryAny $ do
    _ <- evaluate (forceInput supplied)
    modifyIORef' ref (\acc -> acc {accInput = Just supplied})
    forceEitherText (validateInput supplied)
  case observed of
    Left exception -> do
      detail <- exceptionText exception
      snapshot ref (NativeArenaEvaluationFailed 0 0 NativeArenaInputException detail)
    Right (Left detail) -> snapshot ref (NativeArenaEvaluationRejected detail)
    Right (Right ()) -> do
      status <- collect ref supplied 0
      snapshot ref status
 where
  collect ref input game
    | game >= gameCount input = pure NativeArenaEvaluationComplete
    | otherwise = do
        let initial = nativeArenaInputInitialState input
        started <- phase game 0 NativeArenaStateException NativeArenaStateException $ do
          let progress = NativeArenaCaseProgress game 0 initial []
          _ <- evaluate (forceProgress progress)
          modifyIORef' ref (\acc -> acc {accProgress = Just progress, accCurrentTransitions = 0})
          pure (Right ())
        case started of
          Left failure -> pure failure
          Right () -> do
            played <- loop ref input game 0 initial []
            case played of
              Left failure -> pure failure
              Right episode -> do
                modifyIORef'
                  ref
                  ( \acc -> acc {accEpisodes = episode : accEpisodes acc, accProgress = Nothing, accCurrentTransitions = 0}
                  )
                collect ref input (game + 1)
  loop ref input game slot raw decisions = do
    stateResult <- phase game slot NativeArenaStateException NativeArenaStateException $ do
      let state = Game.normaliseForcedPass raw
          outcome = Game.gameOutcome state
      _ <- evaluate (forceState state `seq` forceOutcome outcome)
      pure (Right (state, outcome))
    case stateResult of
      Left failure -> pure (Left failure)
      Right (state, ruleOutcome)
        | slot >= horizon input -> finish input game slot state ruleOutcome True Game.GameDraw decisions
        | ruleOutcome /= Game.GameInProgress ->
            finish input game slot state ruleOutcome False ruleOutcome decisions
        | otherwise -> do
            selected <- phase game slot NativeArenaSelectionRejected NativeArenaSelectionException $ do
              let allowed = Game.legalMoves state
              resolved <- forceEitherText $ do
                uniform <- Ref.nativeArenaUniformDistribution (actions input) allowed
                entry <-
                  tapeError
                    ( Tape.arenaTapeLookup
                        (nativeArenaInputTape input)
                        (fromIntegral game)
                        (fromIntegral slot)
                        (Game.gameCurrentPlayer state)
                    )
                Right (allowed, uniform, entry)
              case resolved of
                Left detail -> pure (Left detail)
                Right actual@(domain, uniform, entry) -> do
                  _ <- evaluate (forceIntList domain `seq` forceVector uniform `seq` forceTapeEntry entry)
                  pure (Right actual)
            case selected of
              Left failure -> pure (Left failure)
              Right (allowed, uniform, entry) -> do
                searched <-
                  if Game.gameCurrentPlayer state == 1
                    then do
                      modifyIORef' ref (\acc -> acc {accUnfinished = UnknownUnfinishedArenaSearch})
                      result <- phase game slot NativeArenaSearchRejected NativeArenaSearchException $ do
                        let config = (Mcts.defaultMctsConfig (actions input)) {Mcts.mctsSimulations = simulations input}
                            captured = captureForward ref game slot device
                        treeResult <-
                          Mcts.runSearchWithPriorIO
                            (Net.networkPriorOracleWithDevice captured (nativeArenaInputPolicy input) state)
                            config
                            (Tape.arenaEntryMctsSeed entry)
                        case treeResult of
                          Left detail -> pure (Left detail)
                          Right tree -> do
                            let visits = Mcts.nodeVisits tree
                                distribution = Net.visitDistributionFromTree (actions input) allowed tree
                            _ <- evaluate (visits `seq` forceVector distribution)
                            pure (Right (distribution, visits))
                      case result of
                        Left failure -> pure (Left failure)
                        Right (distribution, visits) -> do
                          modifyIORef'
                            ref
                            (\acc -> acc {accVisits = accVisits acc + toInteger visits, accUnfinished = NoUnfinishedArenaSearch})
                          pure (Right (distribution, visits))
                    else pure (Right (uniform, 0))
                case searched of
                  Left failure -> pure (Left failure)
                  Right (distribution, visits) -> do
                    chosen <- phase game slot NativeArenaSelectionRejected NativeArenaSelectionException $ forceEitherText $ do
                      require
                        (visits == (if Game.gameCurrentPlayer state == 1 then simulations input else 0))
                        "native learned arena returned search visits differ"
                      action <-
                        if Game.gameCurrentPlayer state == 1
                          then Ref.sampleNativeArenaPlayerAction (actions input) allowed distribution entry
                          else Ref.sampleNativeArenaOpponentAction (actions input) allowed entry
                      Right action
                    case chosen of
                      Left failure -> pure (Left failure)
                      Right action -> do
                        stepped <- phase game slot NativeArenaTransitionException NativeArenaTransitionException $ do
                          let next = Game.applyMove action state
                              outcome = Game.gameOutcome next
                          _ <- evaluate (forceState next `seq` forceOutcome outcome)
                          pure (Right (next, outcome))
                        case stepped of
                          Left failure -> pure (Left failure)
                          Right (next, outcome) -> do
                            -- The transition already succeeded and was fully forced.
                            -- Retain its known work even if later record materialization fails.
                            modifyIORef' ref (\acc -> acc {accCurrentTransitions = accCurrentTransitions acc + 1})
                            materialized <- phase game slot NativeArenaTransitionException NativeArenaTransitionException $ do
                              let decision =
                                    Ref.NativeArenaDecision
                                      slot
                                      raw
                                      state
                                      (raw /= state)
                                      (Game.gameCurrentPlayer state)
                                      allowed
                                      distribution
                                      action
                                      entry
                                      visits
                                      next
                                      outcome
                                  kept = decisions <> [decision]
                                  progress = NativeArenaCaseProgress game (slot + 1) next kept
                              _ <- evaluate (forceProgress progress)
                              pure (Right (kept, progress))
                            case materialized of
                              Left failure -> pure (Left failure)
                              Right (kept, progress) -> do
                                modifyIORef' ref (\acc -> acc {accProgress = Just progress})
                                case outcome of
                                  Game.GameInProgress -> loop ref input game (slot + 1) next kept
                                  _ -> finish input game (slot + 1) next outcome False outcome kept
  finish input game slot state ruleOutcome truncated scored decisions =
    phase game slot NativeArenaStateException NativeArenaStateException $ do
      let episode =
            Ref.NativeArenaEpisode
              game
              (nativeArenaInputInitialState input)
              state
              ruleOutcome
              scored
              truncated
              decisions
      _ <- evaluate (forceEpisode episode)
      pure (Right episode)

phase
  :: Int
  -> Int
  -> NativeArenaFailureKind
  -> NativeArenaFailureKind
  -> IO (Either Text value)
  -> IO (Either NativeArenaEvaluationStatus value)
phase game slot rejected failed action = do
  attempted <- tryAny (action >>= forceEitherText)
  case attempted of
    Left exception -> do
      detail <- exceptionText exception; pure (Left (NativeArenaEvaluationFailed game slot failed detail))
    Right (Left detail) -> pure (Left (NativeArenaEvaluationFailed game slot rejected detail))
    Right (Right value) -> pure (Right value)

captureForward :: IORef Acc -> Int -> Int -> MlpDevice -> MlpDevice
captureForward ref game slot device =
  device
    { mlpdForward = \params input -> do
        -- Arguments are actual observations only after safely materializing.
        _ <- evaluate (forceParams params `seq` forceVector input)
        ordinal <- atomicModifyIORef' ref $ \acc ->
          let summary = accForwards acc
              n = nativeArenaForwardCalls summary
              updated = summary {nativeArenaForwardCalls = n + 1}
           in (acc {accForwards = updated}, n)
        attempted <- tryAny (mlpdForward device params input >>= forceForward)
        case attempted of
          Left exception -> do
            detail <- exceptionText exception
            recordForward
              ref
              (NativeArenaForwardObservation game slot ordinal params input (NativeArenaForwardException detail))
              True
            throwIO exception
          Right returned -> do
            let output = Mlp.forwardOutput <$> returned
                problem = case output of
                  Left _ -> True
                  Right values -> VU.length values /= Mlp.mlpOutputs (Mlp.paramShape params) || not (floatVector values)
            recordForward
              ref
              (NativeArenaForwardObservation game slot ordinal params input (NativeArenaForwardReturned output))
              problem
            pure returned
    }

recordForward :: IORef Acc -> NativeArenaForwardObservation -> Bool -> IO ()
recordForward ref actual problem = modifyIORef' ref $ \acc ->
  let summary = accForwards acc
      firsts = nativeArenaFirstForwards summary
      kept =
        if any ((== nativeArenaForwardGame actual) . nativeArenaForwardGame) firsts
          then firsts
          else firsts <> [actual]
   in acc
        { accForwards =
            summary
              { nativeArenaFirstForwards = kept
              , nativeArenaFailedForward = if problem then Just actual else nativeArenaFailedForward summary
              }
        }

snapshot :: IORef Acc -> NativeArenaEvaluationStatus -> IO RawNativeArenaEvaluation
snapshot ref status = do
  acc <- readIORef ref
  let episodes = reverse (accEpisodes acc)
      completed = sum (map (toInteger . length . Ref.nativeArenaEpisodeDecisions) episodes)
      current = accCurrentTransitions acc
  pure
    ( RawNativeArenaEvaluation
        (accInput acc)
        episodes
        (accProgress acc)
        (accForwards acc)
        status
        (NativeArenaEvaluationWork completed current (accVisits acc) (accUnfinished acc))
    )

validateNativeArenaPolicyContext
  :: Ref.NativeArenaSpec -> Tape.ArenaTape -> Net.PolicyValueNet -> Either Text ()
validateNativeArenaPolicyContext spec tape net =
  validateInput
    ( NativeArenaInput
        CanonicalNativeArena
        (Just spec)
        (Game.initialStateFor (Ref.nativeArenaSpecRowId spec))
        tape
        net
    )

validateInput :: NativeArenaInput -> Either Text ()
validateInput input = do
  let initial = nativeArenaInputInitialState input
      game = Game.gameName initial
      tape = nativeArenaInputTape input
      descriptor = Tape.arenaTapeSpec tape
      net = nativeArenaInputPolicy input
  require
    (game `elem` ["connect4", "othello", "hex", "gomoku"])
    "native learned arena game is not exact canonical metadata"
  require (Tape.arenaTapeSpecRow descriptor == game) "native learned arena tape game differs"
  require
    ( Tape.arenaTapeSpecGames descriptor >= 1
        && Tape.arenaTapeSpecGames descriptor <= 9
        && Tape.arenaTapeSpecMaxPlies descriptor >= 1
        && toInteger (Tape.arenaTapeSpecMaxPlies descriptor) <= toInteger (Game.maxPliesFor game)
    )
    "native learned arena fixture exceeds case or horizon bounds"
  verified <- tapeError (Tape.verifyArenaTape descriptor (Tape.arenaTapeBytes tape))
  require
    (Tape.arenaTapeSha256 verified == Tape.arenaTapeSha256 tape && verified == tape)
    "native learned arena tape payload differs"
  case (nativeArenaInputScope input, nativeArenaInputSpecification input) of
    (CanonicalNativeArena, Just spec) -> do
      canonical <- Ref.canonicalNativeArenaSpec game
      require
        ( spec == canonical
            && descriptor == Ref.nativeArenaSpecTape spec
            && initial == Game.initialStateFor game
        )
        "native learned arena canonical context differs"
    (BoundedNativeArenaFixture, Nothing) -> validateReachable initial
    _ -> Left "native learned arena scope/specification differs"
  validateNet (nativeArenaInputScope input) game net

validateNet :: NativeArenaScope -> Text -> Net.PolicyValueNet -> Either Text ()
validateNet scope game net = do
  let params = Net.pvnParams net
      shape = Mlp.paramShape params
      canonicalObs = Game.observationSizeFor game
      count = Game.actionCountFor game
      obs = Net.pvnObservationSize net
      -- Current device oracle explicitly supports the full43 board encoding
      -- diagnostically; the canonical product still declares exactly8 inputs.
      allowedObservations =
        if scope == BoundedNativeArenaFixture && game == "connect4"
          then [canonicalObs, 43]
          else [canonicalObs]
  require
    ( obs `elem` allowedObservations
        && Net.pvnActionCount net == count
        && Mlp.mlpInputs shape == obs
        && Mlp.mlpOutputs shape == count + 1
        && Mlp.mlpHidden shape > 0
        && all
          ((<= toInteger (maxBound :: CInt)) . toInteger)
          [Mlp.mlpInputs shape, Mlp.mlpHidden shape, Mlp.mlpOutputs shape]
    )
    "native learned arena network dimensions differ"
  require
    ( toInteger (VU.length (Mlp.paramW1 params))
        == toInteger (Mlp.mlpInputs shape) * toInteger (Mlp.mlpHidden shape)
        && VU.length (Mlp.paramB1 params) == Mlp.mlpHidden shape
        && toInteger (VU.length (Mlp.paramW2 params))
          == toInteger (Mlp.mlpHidden shape) * toInteger (Mlp.mlpOutputs shape)
        && VU.length (Mlp.paramB2 params) == Mlp.mlpOutputs shape
        && all floatVector [Mlp.paramW1 params, Mlp.paramB1 params, Mlp.paramW2 params, Mlp.paramB2 params]
    )
    "native learned arena parameters are malformed or overflow Float32"

validateReachable :: Game.GameState -> Either Text ()
validateReachable supplied = do
  let game = Game.gameName supplied
  require
    (length (Game.gameMoves supplied) <= Game.maxPliesFor game)
    "native learned arena fixture history exceeds game bound"
  actual <- foldM one (Game.initialStateFor game) (Game.gameMoves supplied)
  require
    (supplied == actual || supplied == Game.normaliseForcedPass actual)
    "native learned arena fixture state is not the actual legal history"
 where
  one raw action = do
    let state = Game.normaliseForcedPass raw
    require
      (Game.gameOutcome state == Game.GameInProgress && action `elem` Game.legalMoves state)
      "native learned arena fixture history is illegal or continues after terminal"
    Right (Game.applyMove action state)

validateNativeArenaEvaluationData
  :: Ref.NativeArenaSpec
  -> Tape.ArenaTape
  -> Net.PolicyValueNet
  -> RawNativeArenaEvaluation
  -> Either Text ()
validateNativeArenaEvaluationData spec tape net raw = do
  input <-
    maybe
      (Left "native learned arena has no safely observed input")
      Right
      (nativeArenaEvaluationInput raw)
  require
    (nativeArenaInputScope input == CanonicalNativeArena)
    "native learned arena canonical predicate rejects fixture scope"
  validateNativeArenaPolicyContext spec tape net
  require
    ( nativeArenaInputSpecification input == Just spec
        && Tape.arenaTapeBytes (nativeArenaInputTape input) == Tape.arenaTapeBytes tape
        && sameNet (nativeArenaInputPolicy input) net
    )
    "native learned arena supplied context differs from actual input"
  validateComplete raw input

validateNativeArenaFixtureData :: RawNativeArenaEvaluation -> Either Text ()
validateNativeArenaFixtureData raw = do
  input <-
    maybe
      (Left "native learned arena has no safely observed input")
      Right
      (nativeArenaEvaluationInput raw)
  require
    (nativeArenaInputScope input == BoundedNativeArenaFixture)
    "native learned arena fixture predicate requires fixture scope"
  validateComplete raw input

validateComplete :: RawNativeArenaEvaluation -> NativeArenaInput -> Either Text ()
validateComplete raw input = do
  validateInput input
  require
    (nativeArenaEvaluationStatus raw == NativeArenaEvaluationComplete)
    "native learned arena observation is incomplete"
  let episodes = nativeArenaEvaluationEpisodes raw
  require
    (map Ref.nativeArenaEpisodeId episodes == [0 .. gameCount input - 1])
    "native learned arena complete case inventory differs"
  mapM_ (validateEpisode input) episodes
  let decisions = concatMap Ref.nativeArenaEpisodeDecisions episodes
      work =
        NativeArenaEvaluationWork
          (toInteger (length decisions))
          0
          (sum (map (toInteger . Ref.nativeArenaDecisionSearchRootVisits) decisions))
          NoUnfinishedArenaSearch
  require
    (isNothing (nativeArenaEvaluationProgress raw) && nativeArenaEvaluationWork raw == work)
    "native learned arena complete work differs"
  validateSummary input episodes (nativeArenaEvaluationForwards raw)
  require
    (isJust (nativeArenaEvaluationExactScore raw))
    "native learned arena complete scoring outcome differs"

-- Keep total base drop without adding an undeclared package for a lint alias.
{- HLINT ignore validateSummary "Use drop1" -}
validateSummary
  :: NativeArenaInput -> [Ref.NativeArenaEpisode] -> NativeArenaForwardSummary -> Either Text ()
validateSummary input episodes summary = do
  let expected =
        [ (Ref.nativeArenaEpisodeId episode, decision)
        | episode <- episodes
        , Just decision <-
            [find ((== 1) . Ref.nativeArenaDecisionPlayer) (Ref.nativeArenaEpisodeDecisions episode)]
        ]
      firsts = nativeArenaFirstForwards summary
      ordinals = map nativeArenaForwardOrdinal firsts
      calls = nativeArenaForwardCalls summary
      params = Net.pvnParams (nativeArenaInputPolicy input)
  require
    ( map nativeArenaForwardGame firsts == map fst expected
        && length firsts <= gameCount input
        && calls >= toInteger (length firsts)
        && length (nub ordinals) == length ordinals
        && and (zipWith (<) ordinals (drop 1 ordinals))
        && all (\ordinal -> ordinal >= 0 && ordinal < calls) ordinals
        && (case ordinals of [] -> calls == 0; first : _ -> first == 0)
        && isNothing (nativeArenaFailedForward summary)
    )
    "native learned arena complete callback summary differs"
  mapM_
    ( \(actual, (_, decision)) -> do
        require
          ( nativeArenaForwardSlot actual == Ref.nativeArenaDecisionSlot decision
              && sameParams (nativeArenaForwardParameters actual) params
              && sameVector
                (nativeArenaForwardInput actual)
                (Net.encodeGameState (nativeArenaInputPolicy input) (Ref.nativeArenaDecisionNormalizedState decision))
          )
          "native learned arena first callback arguments differ"
        case nativeArenaForwardOutcome actual of
          NativeArenaForwardReturned (Right values) ->
            require
              (VU.length values == Mlp.mlpOutputs (Mlp.paramShape params) && floatVector values)
              "native learned arena complete callback output differs"
          _ -> Left "native learned arena complete callback retains failure"
    )
    (zip firsts expected)

validateEpisode :: NativeArenaInput -> Ref.NativeArenaEpisode -> Either Text ()
validateEpisode input episode = do
  require
    (Ref.nativeArenaEpisodeInitialState episode == nativeArenaInputInitialState input)
    "native learned arena episode initial state differs"
  final <-
    foldM
      one
      (nativeArenaInputInitialState input)
      (zip [0 :: Int ..] (Ref.nativeArenaEpisodeDecisions episode))
  let normalized = Game.normaliseForcedPass final
      ruleOutcome = Game.gameOutcome normalized
      moves = length (Ref.nativeArenaEpisodeDecisions episode)
      truncated = Ref.nativeArenaEpisodeHorizonTruncated episode
  require
    ( moves <= horizon input
        && Ref.nativeArenaEpisodeFinalState episode == normalized
        && Ref.nativeArenaEpisodeRuleOutcome episode == ruleOutcome
    )
    "native learned arena final state or rule outcome differs"
  require
    ( if truncated
        then moves == horizon input && Ref.nativeArenaEpisodeScoredOutcome episode == Game.GameDraw
        else
          ruleOutcome /= Game.GameInProgress && Ref.nativeArenaEpisodeScoredOutcome episode == ruleOutcome
    )
    "native learned arena terminal/horizon scoring differs"
 where
  one raw (slot, decision) = do
    let state = Game.normaliseForcedPass raw
        player = Game.gameCurrentPlayer state
        allowed = Game.legalMoves state
        expectedVisits = if player == 1 then simulations input else 0
    require
      ( slot < horizon input
          && Game.gameOutcome state == Game.GameInProgress
          && Ref.nativeArenaDecisionSlot decision == slot
          && Ref.nativeArenaDecisionRawState decision == raw
          && Ref.nativeArenaDecisionNormalizedState decision == state
          && Ref.nativeArenaDecisionForcedPass decision == (raw /= state)
          && Ref.nativeArenaDecisionPlayer decision == player
          && Ref.nativeArenaDecisionLegalActions decision == allowed
      )
      "native learned arena decision state/player/legal domain differs"
    entry <-
      tapeError
        ( Tape.arenaTapeLookup
            (nativeArenaInputTape input)
            (fromIntegral (Ref.nativeArenaEpisodeId episode))
            (fromIntegral slot)
            player
        )
    require
      ( Ref.nativeArenaDecisionTapeEntry decision == entry
          && Ref.nativeArenaDecisionSearchRootVisits decision == expectedVisits
      )
      "native learned arena decision tape or actual search visits differ"
    action <-
      if player == 1
        then
          Ref.sampleNativeArenaPlayerAction
            (actions input)
            allowed
            (Ref.nativeArenaDecisionDistribution decision)
            entry
        else do
          uniform <- Ref.nativeArenaUniformDistribution (actions input) allowed
          require
            (sameVector uniform (Ref.nativeArenaDecisionDistribution decision))
            "native learned arena opponent distribution differs"
          Ref.sampleNativeArenaOpponentAction (actions input) allowed entry
    let next = Game.applyMove action state
    require
      ( Ref.nativeArenaDecisionAction decision == action
          && Ref.nativeArenaDecisionPostState decision == next
          && Ref.nativeArenaDecisionPostOutcome decision == Game.gameOutcome next
      )
      "native learned arena actual sampled action or transition differs"
    Right next

nativeArenaEvaluationExactScore :: RawNativeArenaEvaluation -> Maybe Rational
nativeArenaEvaluationExactScore raw
  | nativeArenaEvaluationStatus raw /= NativeArenaEvaluationComplete = Nothing
  | null episodes || any ((== Game.GameInProgress) . Ref.nativeArenaEpisodeScoredOutcome) episodes =
      Nothing
  | any invalid episodes = Nothing
  | otherwise = Just ((2 * toInteger wins + toInteger draws) % (2 * toInteger (length episodes)))
 where
  episodes = nativeArenaEvaluationEpisodes raw
  wins = length (filter ((== Game.GameWon 1) . Ref.nativeArenaEpisodeScoredOutcome) episodes)
  draws = length (filter ((== Game.GameDraw) . Ref.nativeArenaEpisodeScoredOutcome) episodes)
  invalid episode = case Ref.nativeArenaEpisodeScoredOutcome episode of
    Game.GameWon player -> player `notElem` [1, -1]
    _ -> False

nativeArenaEvaluationScore :: RawNativeArenaEvaluation -> Maybe Double
nativeArenaEvaluationScore = fmap fromRational . nativeArenaEvaluationExactScore

gameCount, horizon, actions, simulations :: NativeArenaInput -> Int
gameCount = fromIntegral . Tape.arenaTapeSpecGames . Tape.arenaTapeSpec . nativeArenaInputTape
horizon = fromIntegral . Tape.arenaTapeSpecMaxPlies . Tape.arenaTapeSpec . nativeArenaInputTape
actions = Game.actionCountFor . Game.gameName . nativeArenaInputInitialState
simulations input = max 48 (min 192 (2 * actions input))

sameVector :: VU.Vector Double -> VU.Vector Double -> Bool
sameVector left right =
  VU.length left == VU.length right
    && VU.and (VU.zipWith (\a b -> castDoubleToWord64 a == castDoubleToWord64 b) left right)
sameNet :: Net.PolicyValueNet -> Net.PolicyValueNet -> Bool
sameNet left right =
  Net.pvnActionCount left == Net.pvnActionCount right
    && Net.pvnObservationSize left == Net.pvnObservationSize right
    && sameParams (Net.pvnParams left) (Net.pvnParams right)
sameParams :: Mlp.MlpParams -> Mlp.MlpParams -> Bool
sameParams a b =
  Mlp.paramShape a == Mlp.paramShape b
    && and
      ( zipWith
          sameVector
          [Mlp.paramW1 a, Mlp.paramB1 a, Mlp.paramW2 a, Mlp.paramB2 a]
          [Mlp.paramW1 b, Mlp.paramB1 b, Mlp.paramW2 b, Mlp.paramB2 b]
      )
floatVector :: VU.Vector Double -> Bool
floatVector =
  VU.all
    ( \value ->
        not (isNaN value || isInfinite value)
          && let encoded = realToFrac value :: Float in not (isNaN encoded || isInfinite encoded)
    )
require :: Bool -> Text -> Either Text ()
require ok detail = unless ok (Left detail)
tapeError :: Either Tape.ArenaTapeError value -> Either Text value
tapeError = mapLeft (("native learned arena tape: " <>) . Text.pack . show)

forceInput :: NativeArenaInput -> ()
forceInput input =
  nativeArenaInputScope input
    `seq` forceState (nativeArenaInputInitialState input)
    `seq` BS.length (Tape.arenaTapeBytes (nativeArenaInputTape input))
    `seq` Text.length (Tape.arenaTapeSha256 (nativeArenaInputTape input))
    `seq` maybe
      ()
      ( \spec ->
          Text.length (Ref.nativeArenaSpecRowId spec) `seq` Ref.nativeArenaSpecArenaSimulations spec `seq` ()
      )
      (nativeArenaInputSpecification input)
    `seq` Net.pvnActionCount net
    `seq` Net.pvnObservationSize net
    `seq` forceParams (Net.pvnParams net)
 where
  net = nativeArenaInputPolicy input
forceParams :: Mlp.MlpParams -> ()
forceParams params =
  Mlp.mlpInputs shape `seq`
    Mlp.mlpHidden shape `seq`
      Mlp.mlpOutputs shape `seq`
        forceVector (Mlp.paramW1 params) `seq`
          forceVector (Mlp.paramB1 params) `seq`
            forceVector (Mlp.paramW2 params) `seq`
              forceVector (Mlp.paramB2 params)
 where
  shape = Mlp.paramShape params
forceState :: Game.GameState -> ()
forceState state =
  Text.length (Game.gameName state) `seq`
    Game.gameCurrentPlayer state `seq`
      foldr seq () (Game.gameMoves state)
forceIntList :: [Int] -> ()
forceIntList = foldr seq ()
forceTapeEntry :: Tape.ArenaTapeEntry -> ()
forceTapeEntry entry =
  Tape.arenaEntryGame entry `seq`
    Tape.arenaEntrySlot entry `seq`
      Tape.arenaEntrySignedPlayer entry `seq`
        Tape.arenaEntrySideCode entry `seq`
          Tape.arenaEntryQ entry `seq`
            castDoubleToWord64 (Tape.arenaEntryUnit entry) `seq`
              Tape.arenaEntryMctsSeed entry `seq`
                ()
forceDecision :: Ref.NativeArenaDecision -> ()
forceDecision decision =
  Ref.nativeArenaDecisionSlot decision `seq`
    forceState (Ref.nativeArenaDecisionRawState decision) `seq`
      forceState (Ref.nativeArenaDecisionNormalizedState decision) `seq`
        Ref.nativeArenaDecisionForcedPass decision `seq`
          Ref.nativeArenaDecisionPlayer decision `seq`
            forceIntList (Ref.nativeArenaDecisionLegalActions decision) `seq`
              forceVector (Ref.nativeArenaDecisionDistribution decision) `seq`
                Ref.nativeArenaDecisionAction decision `seq`
                  forceTapeEntry (Ref.nativeArenaDecisionTapeEntry decision) `seq`
                    Ref.nativeArenaDecisionSearchRootVisits decision `seq`
                      forceState (Ref.nativeArenaDecisionPostState decision) `seq`
                        forceOutcome (Ref.nativeArenaDecisionPostOutcome decision)
forceDecisions :: [Ref.NativeArenaDecision] -> ()
forceDecisions = foldr (\decision rest -> forceDecision decision `seq` rest) ()
forceProgress :: NativeArenaCaseProgress -> ()
forceProgress progress =
  nativeArenaProgressGame progress `seq`
    nativeArenaProgressTransitions progress `seq`
      forceState (nativeArenaProgressState progress) `seq`
        forceDecisions (nativeArenaProgressDecisions progress)
forceEpisode :: Ref.NativeArenaEpisode -> ()
forceEpisode episode =
  Ref.nativeArenaEpisodeId episode `seq`
    forceState (Ref.nativeArenaEpisodeInitialState episode) `seq`
      forceState (Ref.nativeArenaEpisodeFinalState episode) `seq`
        forceOutcome (Ref.nativeArenaEpisodeRuleOutcome episode) `seq`
          forceOutcome (Ref.nativeArenaEpisodeScoredOutcome episode) `seq`
            Ref.nativeArenaEpisodeHorizonTruncated episode `seq`
              forceDecisions (Ref.nativeArenaEpisodeDecisions episode)
forceOutcome :: Game.GameOutcome -> ()
forceOutcome outcome = case outcome of
  Game.GameInProgress -> ()
  Game.GameDraw -> ()
  Game.GameWon player -> player `seq` ()
forceVector :: VU.Vector Double -> ()
forceVector = VU.foldl' (\() value -> castDoubleToWord64 value `seq` ()) ()
forceText :: Text -> IO ()
forceText text = void (evaluate (Text.length text))
forceEitherText :: Either Text value -> IO (Either Text value)
forceEitherText value = do
  outer <- evaluate value
  case outer of
    Left detail -> forceText detail >> pure (Left detail)
    Right actual -> pure (Right actual)
forceForward :: Either Text Mlp.MlpForward -> IO (Either Text Mlp.MlpForward)
forceForward value = do
  outer <- forceEitherText value
  case outer of
    Left detail -> pure (Left detail)
    Right forward -> evaluate (forceVector (Mlp.forwardOutput forward)) >> pure (Right forward)
exceptionText :: SomeException -> IO Text
exceptionText exception = do
  attempted <- tryAny $ do
    let detail = Text.pack (displayException exception)
    forceText detail
    pure detail
  pure (fromRight "synchronous exception rendering failed" attempted)
