{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

module NativeArenaReferences (nativeArenaReferencesTests) where

import Control.Monad (forM_)
import Data.List (find)
import Data.List.NonEmpty qualified as NE
import Data.Ratio ((%))
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)
import JitML.Numerics.Mlp qualified as Mlp
import JitML.Plan.Plan qualified as Plan
import JitML.Product.Matrix qualified as Matrix
import JitML.RL.AlphaZero qualified as Game
import JitML.RL.AlphaZero.ArenaTape qualified as Tape
import JitML.RL.AlphaZero.Mcts qualified as Mcts
import JitML.RL.AlphaZero.NativeArenaReferences qualified as Ref
import JitML.RL.AlphaZero.PolicyValueNet qualified as Net
import JitML.RL.ConvergenceThresholds qualified as Thresholds
import JitML.Substrate (Substrate (..))
import JitML.Training.Budget qualified as Budget
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

-- Actual pure game/search controls and raw synthetic boundary fixtures only.
-- No provider, learned-model, paired learner or convergence claim follows.
nativeArenaReferencesTests :: TestTree
nativeArenaReferencesTests =
  testGroup
    "native addressed game-aware arena references"
    [ testCase "all four exact row specifications retain actual arena search budgets and declared shapes" $ do
        specs <- expectRight Ref.allCanonicalNativeArenaSpecs
        fmap Ref.nativeArenaSpecRowId specs @?= ["connect4", "othello", "hex", "gomoku"]
        fmap Ref.nativeArenaSpecArenaSimulations specs @?= [48, 128, 192, 192]
        forM_ specs $ \spec -> do
          let game = Ref.nativeArenaSpecRowId spec; tape = Ref.nativeArenaSpecTape spec
          Ref.nativeArenaSpecActionCount spec @?= Game.actionCountFor game
          Ref.nativeArenaSpecObservationSize spec @?= Game.observationSizeFor game
          Ref.nativeArenaSpecMaxPlies spec @?= Game.maxPliesFor game
          Tape.arenaTapeSpecRow tape @?= game
          Tape.arenaTapeSpecBase tape @?= 42 + 7919
          Tape.arenaTapeSpecGames tape @?= 9
          toInteger (Tape.arenaTapeSpecMaxPlies tape) @?= toInteger (Game.maxPliesFor game)
          Budget.trainingBudgetTargetUnits (Ref.nativeArenaSpecTrainingBudget spec)
            @?= Thresholds.alphaZeroGenerationBudget game
          Ref.nativeArenaSpecTrainingSimulations spec @?= Thresholds.alphaZeroSimulationBudget game
        connect4 <- expectRight (Ref.canonicalNativeArenaSpec "connect4")
        Ref.nativeArenaSpecObservationSize connect4 @?= 8
        VU.length (Net.encodeConnect4Board Game.initialConnect4) @?= 43
    , testCase
        "all twelve actual projected descriptors budgets and seed agree without importing Matrix into the lower module"
        $ do
          specs <- expectRight Ref.allCanonicalNativeArenaSpecs
          forM_ specs $ \spec -> do
            row <-
              maybe
                (assertFailure "actual AlphaZero row absent")
                pure
                (find ((== Ref.nativeArenaSpecRowId spec) . Matrix.rowId) Matrix.allProductRows)
            forM_ [AppleSilicon, LinuxCPU, LinuxCUDA] $ \lane -> case Matrix.projectProductRow lane row of
              Plan.Failure reasons -> assertFailure (show reasons)
              Plan.Success (Matrix.SomeProductProjection _ projection) -> do
                let seedlessBudget = Ref.nativeArenaSpecTrainingBudget spec
                Budget.trainingBudgetSeed seedlessBudget @?= Nothing
                expectedSeededBudget <-
                  expectRight
                    ( Budget.mkTrainingBudget
                        (Budget.trainingBudgetKind seedlessBudget)
                        (Budget.trainingBudgetTargetUnits seedlessBudget)
                        (Just 42)
                    )
                Matrix.productProjectionTrainingBudget projection @?= expectedSeededBudget
                fmap
                  toInteger
                  (NE.toList (Plan.seedCohortValues (Plan.runPlanSeeds (Matrix.productProjectionRunPlan projection))))
                  @?= [42]
                case Matrix.productProjectionDescriptor projection of
                  Matrix.AlphaZeroProductDescriptor game _ simulations horizon _ count -> do
                    game @?= Ref.nativeArenaSpecRowId spec
                    simulations @?= Ref.nativeArenaSpecTrainingSimulations spec
                    toInteger horizon @?= toInteger (Ref.nativeArenaSpecMaxPlies spec)
                    count @?= 9
                  _ -> assertFailure "actual AlphaZero row has a non-AlphaZero descriptor"
    , testCase "unknown aliases and altered complete canonical declarations reject without fallback" $ do
        forM_ ["CONNECT4", "AlphaZero/connect4", "connect-4", "unknown", ""] $ \game ->
          expectLeft "not an exact canonical row" (Ref.canonicalNativeArenaSpec game)
        forM_ Thresholds.alphaZeroGameConvergenceRows $ \row -> do
          expectLeft
            "complete canonical row"
            ( Ref.mkCanonicalNativeArenaSpec
                row {Thresholds.azgMctsSimulationsPerMove = Thresholds.azgMctsSimulationsPerMove row + 1}
            )
          budget <-
            expectRight
              ( Budget.mkTrainingBudget
                  Budget.AlphaZeroSelfPlayBudget
                  (Budget.trainingBudgetTargetUnits (Thresholds.azgBudget row) + 1)
                  Nothing
              )
          expectLeft
            "complete canonical row"
            (Ref.mkCanonicalNativeArenaSpec row {Thresholds.azgBudget = budget})
    , testCase "canonical evaluation rejects another row base game count and move-count tape before play" $ do
        spec <- expectRight (Ref.canonicalNativeArenaSpec "connect4")
        forM_
          [ ("othello", 7961, 9, 42)
          , ("connect4", 7962, 9, 42)
          , ("connect4", 7961, 8, 42)
          , ("connect4", 7961, 9, 41)
          ]
          $ \(row, base, games, plies) -> do
            tape <- makeTape row base games plies
            Ref.evaluateNativeArenaReference spec tape Ref.PlainLegalUniform
              >>= expectLeft "complete exact row-owned canonical tape descriptor"
    , testCase
        "actual neutral oracle uses current-player legal priors zero nonterminal value and real path transitions"
        $ forM_ ["connect4", "othello", "hex", "gomoku"]
        $ \game -> do
          let root = Game.initialStateFor game; actions = Game.actionCountFor game
          action <- firstValue (Game.legalMoves root)
          forM_ [[], [action]] $ \path -> do
            let state = Net.applySearchPath root path; legal = Game.legalMoves state
            actual <- expectRight (Ref.neutralNativeArenaOracle actions root path)
            Mcts.evalPlayerToMove actual @?= Just (Game.gameCurrentPlayer state)
            Mcts.evalTerminal actual @?= False
            Mcts.evalValue actual @?= 0
            Mcts.evalPriors actual
              @?= [if index `elem` legal then 1 / fromIntegral (length legal) else 0 | index <- [0 .. actions - 1]]
    , testCase
        "neutral search follows actual MCTS root noise terminal backup and canonical simulation budget"
        $ forM_ ["connect4", "othello", "hex", "gomoku"]
        $ \game -> do
          tape <- makeTape game 7961 1 1
          actual <-
            expectRight
              =<< Ref.evaluateNativeArenaReferenceFixture (Game.initialStateFor game) tape Ref.NeutralLegalMcts
          episode <- firstValue (Ref.nativeArenaObservedEpisodes actual)
          decision <- firstValue (Ref.nativeArenaEpisodeDecisions episode)
          let actions = Game.actionCountFor game
              simulations = max 48 (min 192 (2 * actions))
              config = (Mcts.defaultMctsConfig actions) {Mcts.mctsSimulations = simulations}
              tree =
                Mcts.runSearchWithPrior
                  (independentNeutral (Game.initialStateFor game) actions)
                  config
                  (Tape.arenaEntryMctsSeed (Ref.nativeArenaDecisionTapeEntry decision))
          Ref.nativeArenaDecisionDistribution decision
            @?= Net.visitDistributionFromTree actions (Game.legalMoves (Game.initialStateFor game)) tree
          Ref.nativeArenaDecisionSearchRootVisits decision @?= simulations
          Ref.nativeArenaObservedSearchRootVisits actual @?= toInteger simulations
          Ref.nativeArenaObservedEvaluationTransitions actual @?= 1
    , testCase "terminal game values and signed-player backup differ from a fake always-live zero oracle" $
        forM_ [(winningState, 1), (losingState, -1)] $ \(state, winner) -> do
          Game.gameOutcome state @?= Game.GameWon winner
          oracle <- expectRight (Ref.neutralNativeArenaOracle 7 state [])
          Mcts.evalTerminal oracle @?= True
          Mcts.evalPriors oracle @?= []
          Mcts.evalValue oracle @?= Game.terminalValueForToMove state
          Mcts.evalPlayerToMove oracle @?= Just (Game.gameCurrentPlayer state)
          tape <- makeTape "connect4" 7961 2 2
          actual <- expectRight =<< Ref.evaluateNativeArenaReferenceFixture state tape Ref.NeutralLegalMcts
          fmap Ref.nativeArenaEpisodeScoredOutcome (Ref.nativeArenaObservedEpisodes actual)
            @?= replicate 2 (Game.GameWon winner)
          Ref.nativeArenaObservedEvaluationTransitions actual @?= 0
          Ref.nativeArenaObservedSearchRootVisits actual @?= 0
          Ref.nativeArenaObservedScore actual @?= if winner == 1 then 1 else 0
          expectLeft "continues after terminal" (Ref.neutralNativeArenaOracle 7 state [2])
    , testCase "forced Othello pass consumes the normalized signed-side slot without an extra decision" $ do
        let playable = Game.normaliseForcedPass passPosition
        Game.legalMoves passPosition @?= []
        Game.gameCurrentPlayer playable @?= -1
        tape <- makeTape "othello" 7961 1 1
        oracle <- expectRight (Ref.neutralNativeArenaOracle 64 passPosition [])
        Mcts.evalPlayerToMove oracle @?= Just (-1)
        forM_ [Ref.PlainLegalUniform, Ref.NeutralLegalMcts] $ \reference -> do
          actual <- expectRight =<< Ref.evaluateNativeArenaReferenceFixture passPosition tape reference
          episode <- firstValue (Ref.nativeArenaObservedEpisodes actual)
          decision <- firstValue (Ref.nativeArenaEpisodeDecisions episode)
          Ref.nativeArenaDecisionRawState decision @?= passPosition
          Ref.nativeArenaDecisionNormalizedState decision @?= playable
          Ref.nativeArenaDecisionForcedPass decision @?= True
          Ref.nativeArenaDecisionSlot decision @?= 0
          Ref.nativeArenaDecisionPlayer decision @?= -1
          Tape.arenaEntrySignedPlayer (Ref.nativeArenaDecisionTapeEntry decision) @?= -1
          Tape.arenaEntrySideCode (Ref.nativeArenaDecisionTapeEntry decision) @?= 2
          Tape.arenaEntrySlot (Ref.nativeArenaDecisionTapeEntry decision) @?= 0
          Ref.nativeArenaDecisionSearchRootVisits decision @?= 0
          Ref.nativeArenaObservedEvaluationTransitions actual @?= 1
    , testCase
        "uniform player uses current categorical sampling while uniform opponent retains its actual legal-index rule"
        $ do
          tape <- makeTape "connect4" 7961 1 2
          positive <- expectRight (Tape.arenaTapeLookup tape 0 0 1)
          negative <- expectRight (Tape.arenaTapeLookup tape 0 1 (-1))
          let legal = [1, 3, 6]
          distribution <- expectRight (Ref.nativeArenaUniformDistribution 7 legal)
          Ref.sampleNativeArenaPlayerAction 7 legal distribution positive
            @?= Right (Mlp.sampleCategorical distribution (Tape.arenaEntryUnit positive))
          let opponentIndex = (floor (Tape.arenaEntryUnit negative * 3) :: Int) `mod` 3
          expected <- firstValue (drop opponentIndex legal)
          Ref.sampleNativeArenaOpponentAction 7 legal negative @?= Right expected
          Ref.sampleNativeArenaPlayerAction 7 legal (VU.fromList [0, 0, 0, 1, 0, 0, 0]) positive @?= Right 3
    , testCase
        "malformed legal domains and nonfinite illegal or missing distribution mass reject specifically"
        $ do
          tape <- makeTape "connect4" 7961 1 1
          entry <- expectRight (Tape.arenaTapeLookup tape 0 0 1)
          expectLeft "legal-action domain" (Ref.nativeArenaUniformDistribution maxBound [0])
          expectLeft "legal-action domain" (Ref.nativeArenaUniformDistribution 0 [0])
          forM_ [[], [0, 0], [-1], [7]] $ \bad -> do
            expectLeft "legal-action domain" (Ref.nativeArenaUniformDistribution 7 bad)
            expectLeft "legal-action domain" (Ref.sampleNativeArenaOpponentAction 7 bad entry)
          forM_
            [ VU.empty
            , VU.replicate 7 0
            , VU.fromList [0, 0 / 0, 0, 0, 0, 0, 0]
            , VU.fromList [0, 1 / 0, 0, 0, 0, 0, 0]
            , VU.fromList [0, -1, 0, 0, 0, 0, 0]
            , VU.fromList [1, 0, 0, 0, 0, 0, 0]
            , VU.fromList [0, 1e308, 0, 1e308, 0, 0, 0]
            ]
            $ \bad ->
              expectLeft "distribution has invalid" (Ref.sampleNativeArenaPlayerAction 7 [1, 3, 6] bad entry)
          let underweight = VU.fromList [0, 0.01, 0, 0, 0, 0, 0]
              overweight = VU.fromList [0, 2, 0, 0, 0, 0, 0]
          forM_ [underweight, overweight] $ \bad ->
            expectLeft "distribution mass" (Ref.sampleNativeArenaPlayerAction 7 [1, 6] bad entry)
          -- Valid finite u plus mass at the exact representation bound can expose
          -- sampleCategorical's zero-tail fallback. The production shared selector
          -- must still require positive mass at its actual chosen action.
          let nearOne = 1 - 1 / 9007199254740992
              zeroTail = VU.fromList [0, nearOne, 0, 0, 0, 0, 0]
          Mlp.sampleCategorical zeroTail nearOne @?= 6
          expectLeft "zero-mass player action" (Ref.sampleNativeArenaPlayerAtUnit 7 [1, 6] zeroTail nearOne)
          forM_ [0 / 0, 1 / 0, negate (1 / 0), -0.1, 1, 2] $ \badUnit ->
            expectLeft
              "unit variate is outside"
              (Ref.sampleNativeArenaPlayerAtUnit 7 [1, 6] (VU.fromList [0, 1, 0, 0, 0, 0, 0]) badUnit)
    , testCase "unsupported games signed players row and oversized fixture dimensions fail before search" $ do
        tape <- makeTape "connect4" 7961 1 1
        Ref.evaluateNativeArenaReferenceFixture
          (Game.initialConnect4 {Game.gameName = "foreign"})
          tape
          Ref.NeutralLegalMcts
          >>= expectLeft "fixture game is unsupported"
        Ref.evaluateNativeArenaReferenceFixture
          (Game.initialConnect4 {Game.gameCurrentPlayer = 0})
          tape
          Ref.NeutralLegalMcts
          >>= expectLeft "signed player is invalid"
        otherRowTape <- makeTape "othello" 7961 1 1
        Ref.evaluateNativeArenaReferenceFixture Game.initialConnect4 otherRowTape Ref.PlainLegalUniform
          >>= expectLeft "tape row differs"
        forM_ [(10, 1), (1, 43)] $ \(games, horizon) -> do
          oversized <- makeTape "connect4" 7961 games horizon
          Ref.evaluateNativeArenaReferenceFixture Game.initialConnect4 oversized Ref.NeutralLegalMcts
            >>= expectLeft "bounded game or move counts"
        expectLeft "game or action width differs" (Ref.neutralNativeArenaOracle 6 Game.initialConnect4 [])
        expectLeft "illegal move" (Ref.neutralNativeArenaOracle 7 Game.initialConnect4 [7])
    , testCase "unfinished horizon draws retain the real rule outcome and every actually consumed action" $ do
        tape <- makeTape "connect4" 7961 3 2
        forM_ [Ref.PlainLegalUniform, Ref.NeutralLegalMcts] $ \reference -> do
          observed <-
            expectRight =<< Ref.evaluateNativeArenaReferenceFixture Game.initialConnect4 tape reference
          fmap Ref.nativeArenaEpisodeId (Ref.nativeArenaObservedEpisodes observed) @?= [0, 1, 2]
          forM_ (Ref.nativeArenaObservedEpisodes observed) $ \episode -> do
            Ref.nativeArenaEpisodeHorizonTruncated episode @?= True
            Ref.nativeArenaEpisodeRuleOutcome episode @?= Game.GameInProgress
            Ref.nativeArenaEpisodeScoredOutcome episode @?= Game.GameDraw
            length (Ref.nativeArenaEpisodeDecisions episode) @?= 2
            assertEpisodeTrace tape episode
          Ref.nativeArenaObservedWins observed @?= 0
          Ref.nativeArenaObservedDraws observed @?= 3
          Ref.nativeArenaObservedLosses observed @?= 0
          Ref.nativeArenaObservedScore observed @?= 0.5
          Ref.nativeArenaObservedExactScore observed @?= 1 % 2
          Ref.nativeArenaObservedEvaluationTransitions observed @?= 6
    , testCase "actual terminal on the last allowed move outranks horizon truncation" $ do
        let nearWin = foldl' (flip Game.applyMove) Game.initialConnect4 [0, 1, 0, 1, 0, 2]
        -- Explicit noncanonical branch fixture: addressed base3 has its first
        -- q in [0,1/7), selecting the actual winning column0. No trained score,
        -- canonical base7961, seed pool or qualification is selected here.
        tape <- makeTape "connect4" 3 1 1
        entry <- expectRight (Tape.arenaTapeLookup tape 0 0 1)
        Tape.arenaEntryQ entry @?= 1257367802227214
        assertBool "fixed branch fixture must select column zero" (Tape.arenaEntryUnit entry < 1 / 7)
        actual <- expectRight =<< Ref.evaluateNativeArenaReferenceFixture nearWin tape Ref.PlainLegalUniform
        episode <- firstValue (Ref.nativeArenaObservedEpisodes actual)
        decision <- firstValue (Ref.nativeArenaEpisodeDecisions episode)
        Ref.nativeArenaDecisionAction decision @?= 0
        Ref.nativeArenaEpisodeRuleOutcome episode @?= Game.GameWon 1
        Ref.nativeArenaEpisodeScoredOutcome episode @?= Game.GameWon 1
        Ref.nativeArenaEpisodeHorizonTruncated episode @?= False
        Ref.nativeArenaObservedEvaluationTransitions actual @?= 1
        Ref.nativeArenaObservedScore actual @?= 1
        assertEpisodeTrace tape episode
    , testCase "different earlier game lengths cannot shift any later consumed address or variate" $ do
        tape <- makeTape "connect4" 7961 2 2
        early <-
          expectRight =<< Ref.evaluateNativeArenaReferenceFixture winningState tape Ref.PlainLegalUniform
        longer <-
          expectRight
            =<< Ref.evaluateNativeArenaReferenceFixture Game.initialConnect4 tape Ref.PlainLegalUniform
        Ref.nativeArenaObservedEvaluationTransitions early @?= 0
        Ref.nativeArenaObservedEvaluationTransitions longer @?= 4
        episode <- case Ref.nativeArenaObservedEpisodes longer of
          _ : value : _ -> pure value
          _ -> assertFailure "required actual game fixture was empty"
        decision <- firstValue (Ref.nativeArenaEpisodeDecisions episode)
        let consumed = Ref.nativeArenaDecisionTapeEntry decision
        Tape.arenaEntryGame consumed @?= 1
        Tape.arenaEntrySlot consumed @?= 0
        Tape.arenaTapeLookup (Ref.nativeArenaObservedTape early) 1 0 1 @?= Right consumed
        Tape.arenaTapeSha256 (Ref.nativeArenaObservedTape early)
          @?= Tape.arenaTapeSha256 (Ref.nativeArenaObservedTape longer)
    , testCase
        "complete canonical connect4 references retain all nine games raw outcomes and exact whole work"
        $ do
          spec <- expectRight (Ref.canonicalNativeArenaSpec "connect4")
          let tape = Ref.materializeNativeArenaTape spec
          family <- expectRight =<< Ref.evaluateNativeArenaReferences spec tape
          Ref.nativeArenaObservedSpec family @?= spec
          fmap Ref.nativeArenaObservedReference (Ref.nativeArenaObservedReferences family)
            @?= [Ref.PlainLegalUniform, Ref.NeutralLegalMcts]
          forM_ (Ref.nativeArenaObservedReferences family) $ \reference -> do
            fmap Ref.nativeArenaEpisodeId (Ref.nativeArenaObservedEpisodes reference) @?= [0 .. 8]
            Ref.nativeArenaObservedTape reference @?= tape
            let outcomes = Ref.nativeArenaObservedEpisodes reference
                wins = length [() | outcome <- outcomes, Ref.nativeArenaEpisodeScoredOutcome outcome == Game.GameWon 1]
                draws = length [() | outcome <- outcomes, Ref.nativeArenaEpisodeScoredOutcome outcome == Game.GameDraw]
                losses =
                  length [() | outcome <- outcomes, Ref.nativeArenaEpisodeScoredOutcome outcome == Game.GameWon (-1)]
            ( Ref.nativeArenaObservedWins reference
              , Ref.nativeArenaObservedDraws reference
              , Ref.nativeArenaObservedLosses reference
              )
              @?= (wins, draws, losses)
            wins + draws + losses @?= 9
            Ref.nativeArenaObservedScore reference @?= (fromIntegral wins + 0.5 * fromIntegral draws) / 9
            Ref.nativeArenaObservedExactScore reference @?= (2 * toInteger wins + toInteger draws) % 18
            Ref.nativeArenaObservedEvaluationTransitions reference
              @?= sum (fmap (toInteger . length . Ref.nativeArenaEpisodeDecisions) outcomes)
            Ref.nativeArenaObservedSearchRootVisits reference
              @?= sum
                [ toInteger (Ref.nativeArenaDecisionSearchRootVisits decision)
                | outcome <- outcomes
                , decision <- Ref.nativeArenaEpisodeDecisions outcome
                ]
            forM_ outcomes (assertEpisodeTrace tape)
          Ref.nativeArenaTotalEvaluationTransitions family
            @?= sum (fmap Ref.nativeArenaObservedEvaluationTransitions (Ref.nativeArenaObservedReferences family))
          Ref.nativeArenaTotalSearchRootVisits family
            @?= sum (fmap Ref.nativeArenaObservedSearchRootVisits (Ref.nativeArenaObservedReferences family))
    ]

-- Independent neutral game oracle for actual pure-vs-IO search mechanics.
-- It uses real terminal/legal/current-player semantics, not defaultPriorOracle.
independentNeutral :: Game.GameState -> Int -> Mcts.PriorOracle
independentNeutral root actions path =
  let state =
        foldl'
          (\raw action -> Game.normaliseForcedPass (Game.applyMove action (Game.normaliseForcedPass raw)))
          (Game.normaliseForcedPass root)
          path
   in case Game.gameOutcome state of
        Game.GameInProgress ->
          Mcts.NodeEval
            [ if action `elem` Game.legalMoves state then 1 / fromIntegral (length (Game.legalMoves state)) else 0
            | action <- [0 .. actions - 1]
            ]
            0
            False
            (Just (Game.gameCurrentPlayer state))
        _ -> Mcts.NodeEval [] (Game.terminalValueForToMove state) True (Just (Game.gameCurrentPlayer state))

assertEpisodeTrace :: Tape.ArenaTape -> Ref.NativeArenaEpisode -> Assertion
assertEpisodeTrace tape episode = do
  let decisions = Ref.nativeArenaEpisodeDecisions episode
  fmap Ref.nativeArenaDecisionSlot decisions @?= [0 .. length decisions - 1]
  final <- foldActions (Ref.nativeArenaEpisodeInitialState episode) decisions
  Game.normaliseForcedPass final
    @?= Game.normaliseForcedPass (Ref.nativeArenaEpisodeFinalState episode)
  Ref.nativeArenaEpisodeRuleOutcome episode
    @?= Game.gameOutcome (Ref.nativeArenaEpisodeFinalState episode)
 where
  foldActions state [] = pure state
  foldActions raw (decision : rest) = do
    Ref.nativeArenaDecisionRawState decision @?= raw
    let state = Game.normaliseForcedPass raw
        action = Ref.nativeArenaDecisionAction decision
        entry = Ref.nativeArenaDecisionTapeEntry decision
    Ref.nativeArenaDecisionNormalizedState decision @?= state
    Ref.nativeArenaDecisionForcedPass decision @?= (raw /= state)
    Ref.nativeArenaDecisionPlayer decision @?= Game.gameCurrentPlayer state
    Ref.nativeArenaDecisionLegalActions decision @?= Game.legalMoves state
    assertBool "actual selected reference action must be legal" (action `elem` Game.legalMoves state)
    Tape.arenaTapeLookup
      tape
      (fromIntegral (Ref.nativeArenaEpisodeId episode))
      (fromIntegral (Ref.nativeArenaDecisionSlot decision))
      (Game.gameCurrentPlayer state)
      @?= Right entry
    Ref.nativeArenaDecisionPostState decision @?= Game.applyMove action state
    Ref.nativeArenaDecisionPostOutcome decision @?= Game.gameOutcome (Game.applyMove action state)
    case Game.gameOutcome (Game.applyMove action state) of
      Game.GameInProgress -> pure ()
      _ -> rest @?= []
    foldActions (Game.applyMove action state) rest

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

makeTape :: Text -> Word64 -> Word64 -> Word64 -> IO Tape.ArenaTape
makeTape row base games horizon = Tape.materializeArenaTape <$> expectRight (Tape.mkArenaTapeSpec row base games horizon)
firstValue :: [value] -> IO value
firstValue values = case values of first : _ -> pure first; [] -> assertFailure "required actual game fixture was empty"
expectRight :: (Show error) => Either error value -> IO value
expectRight actual = case actual of Right value -> pure value; Left reason -> assertFailure (show reason)
expectLeft :: Text -> Either Text value -> Assertion
expectLeft fragment actual = case actual of
  Left reason -> assertBool ("wrong rejection: " <> Text.unpack reason) (fragment `Text.isInfixOf` reason)
  Right _ -> assertFailure "invalid native arena raw input was accepted"
