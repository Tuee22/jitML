{-# LANGUAGE OverloadedStrings #-}

-- Complete mathematical DATA controls only. One real canonical offline arena
-- result is reused under five supplied labels; this is never five models or
-- qualifying training. DTO mutations below are rejection controls only.
module NativeArenaLearningPolicy (nativeArenaLearningPolicyTests) where

import Control.Exception (AsyncException (ThreadKilled), evaluate, throw, try)
import Control.Monad (foldM, forM_)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (find, sort)
import Data.Ratio ((%))
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import GHC.Float (castDoubleToWord64)
import Test.Tasty (TestTree, testGroup, withResource)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Numerics.Mlp qualified as Mlp
import JitML.Numerics.MlpDevice (MlpDevice (..), pureReferenceMlpDevice)
import JitML.Product.NativeArenaLearningPolicy qualified as Policy
import JitML.RL.AlphaZero qualified as Game
import JitML.RL.AlphaZero.ArenaTape qualified as Tape
import JitML.RL.AlphaZero.NativeArenaEvaluation qualified as Arena
import JitML.RL.AlphaZero.NativeArenaReferences qualified as Ref
import JitML.RL.AlphaZero.PolicyValueNet qualified as Net
import JitML.RL.ConvergenceThresholds qualified as Thresholds
import JitML.Training.Budget qualified as Budget

right :: (Show error) => Either error value -> IO value
right result = case result of
  Right value -> pure value
  Left detail -> assertFailure (show detail) >> fail "required observed result unavailable"

rejects :: Text -> Either Text value -> Assertion
rejects fragment result = case result of
  Left detail -> assertBool "specific comparison boundary differs" (fragment `Text.isInfixOf` detail)
  Right _ -> assertFailure "invalid comparison DATA was accepted"

inspectAll :: (Show value) => String -> value -> Assertion
inspectAll label value = do
  renderedLength <- evaluate (length (show value))
  assertBool label (renderedLength > 0)

data Fixture = Fixture
  { fixtureCalibrations :: ![(Text, Policy.NativeArenaReferenceCalibration)]
  , fixtureC4 :: !Policy.NativeArenaReferenceCalibration
  , fixtureNet :: !Net.PolicyValueNet
  , fixtureRaw :: !Arena.RawNativeArenaEvaluation
  , fixtureFailed :: !Arena.RawNativeArenaEvaluation
  , fixtureForwardCalls :: !Integer
  , fixtureFailureCalls :: !Integer
  , fixtureWitnessCalls :: !Integer
  }

acquire :: IO Fixture
acquire = do
  specs <- right Ref.allCanonicalNativeArenaSpecs
  calibrations <-
    mapM
      ( \spec -> do
          observed <- Policy.observeNativeArenaReferenceCalibration spec >>= right
          pure (Ref.nativeArenaSpecRowId spec, observed)
      )
      specs
  calibration <- case lookup "connect4" calibrations of
    Just value -> pure value
    Nothing ->
      assertFailure "actual canonical calibration inventory lacks connect4" >> fail "missing calibration"
  let spec = Policy.nativeArenaCalibrationSpec calibration
      tape = Policy.nativeArenaCalibrationTape calibration
      net =
        Net.initPolicyValueNet
          (Ref.nativeArenaSpecObservationSize spec)
          (Ref.nativeArenaSpecActionCount spec)
          16
          42
  calls <- newIORef (0 :: Integer)
  witnesses <- newIORef (0 :: Integer)
  let device =
        pureReferenceMlpDevice
          { mlpdForward = \params input -> do
              modifyIORef' calls (+ 1)
              mlpdForward pureReferenceMlpDevice params input
          , mlpdExecutionWitness = modifyIORef' witnesses (+ 1) >> pure (Right Nothing)
          }
  raw <- Arena.evaluateNativeArenaPolicy device spec tape net
  _ <- right (Arena.validateNativeArenaEvaluationData spec tape net raw)
  _ <- evaluate (length (show raw))
  failureCalls <- newIORef (0 :: Integer)
  let failedDevice =
        device
          { mlpdForward = \_ _ ->
              modifyIORef' failureCalls (+ 1) >> pure (Left "explicit mathematical arena first-forward failure")
          }
  failed <- Arena.evaluateNativeArenaPolicy failedDevice spec tape net
  _ <- evaluate (length (show failed))
  observedCalls <- readIORef calls
  observedFailures <- readIORef failureCalls
  observedWitnesses <- readIORef witnesses
  pure
    (Fixture calibrations calibration net raw failed observedCalls observedFailures observedWitnesses)

observations :: Arena.RawNativeArenaEvaluation -> [Policy.NativeArenaSeedObservation]
observations raw = [Policy.NativeArenaSeedObservation index (42 + fromIntegral index) raw raw | index <- [0 .. 4]]

compareRaw
  :: Fixture -> Arena.RawNativeArenaEvaluation -> Either Text Policy.NativeArenaCohortComparison
compareRaw fixture raw = Policy.compareNativeArenaCohort (fixtureC4 fixture) (observations raw)

brokenFinal
  :: Fixture -> Arena.RawNativeArenaEvaluation -> Either Text Policy.NativeArenaCohortComparison
brokenFinal fixture raw = case observations (fixtureRaw fixture) of
  original : rest ->
    Policy.compareNativeArenaCohort
      (fixtureC4 fixture)
      (original {Policy.nativeArenaObservedFinal = raw} : rest)
  [] -> Left "written five-member fixture unexpectedly empty"

brokenInitial
  :: Fixture -> Arena.RawNativeArenaEvaluation -> Either Text Policy.NativeArenaCohortComparison
brokenInitial fixture raw = case observations (fixtureRaw fixture) of
  original : rest ->
    Policy.compareNativeArenaCohort
      (fixtureC4 fixture)
      (original {Policy.nativeArenaObservedInitial = raw} : rest)
  [] -> Left "written five-member fixture unexpectedly empty"

inputOf :: Arena.RawNativeArenaEvaluation -> IO Arena.NativeArenaInput
inputOf raw = case Arena.nativeArenaEvaluationInput raw of
  Just input -> pure input
  Nothing -> assertFailure "actual complete evaluator lost its observed input" >> fail "missing input"

firstEpisode
  :: Arena.RawNativeArenaEvaluation -> IO (Ref.NativeArenaEpisode, [Ref.NativeArenaEpisode])
firstEpisode raw = case Arena.nativeArenaEvaluationEpisodes raw of
  first : rest -> pure (first, rest)
  [] -> assertFailure "actual complete evaluator lost its cases" >> fail "missing cases"

firstDecision :: Ref.NativeArenaEpisode -> IO (Ref.NativeArenaDecision, [Ref.NativeArenaDecision])
firstDecision episode = case Ref.nativeArenaEpisodeDecisions episode of
  first : rest -> pure (first, rest)
  [] -> assertFailure "canonical nonterminal case has no actual decisions" >> fail "missing decisions"

currentRow :: Ref.NativeArenaSpec -> IO Thresholds.AlphaZeroGameConvergenceRow
currentRow spec = case find
  ((== Ref.nativeArenaSpecRowId spec) . Thresholds.azgGame)
  Thresholds.alphaZeroGameConvergenceRows of
  Just row -> pure row
  Nothing -> assertFailure "actual canonical game lacks a quality declaration" >> fail "missing row"

scoreCounts :: Int -> Int -> Int -> IO Policy.NativeArenaScoreCounts
scoreCounts wins draws losses = right (Policy.mkNativeArenaScoreCounts wins draws losses)

requireCriteria
  :: [Budget.ConvergenceObservation] -> IO (Budget.ConvergenceObservation, Budget.ConvergenceObservation)
requireCriteria values = case values of
  [arena, legal] -> pure (arena, legal)
  _ ->
    assertFailure "actual comparison did not retain both ordered criteria" >> fail "missing criteria"

median :: [Double] -> IO Double
median values = case sort values of
  [_, _, value, _, _] -> pure value
  _ -> assertFailure "actual comparison lost one of the five values" >> fail "missing median inputs"

nativeArenaLearningPolicyTests :: TestTree
nativeArenaLearningPolicyTests = withResource acquire (\_ -> pure ()) $ \get ->
  testGroup
    "native paired arena mathematical comparison"
    [ testCase
        "all four actual calibrations retain exact canonical spec tape and two reference inventories"
        $ do
          fixture <- get
          map fst (fixtureCalibrations fixture) @?= ["connect4", "othello", "hex", "gomoku"]
          forM_ (fixtureCalibrations fixture) $ \(game, calibration) -> do
            expected <- right (Ref.canonicalNativeArenaSpec game)
            let spec = Policy.nativeArenaCalibrationSpec calibration
                tape = Policy.nativeArenaCalibrationTape calibration
                family = Policy.nativeArenaCalibrationReferences calibration
            spec @?= expected
            Tape.arenaTapeSpec tape @?= Ref.nativeArenaSpecTape spec
            Tape.arenaTapeSpecBase (Tape.arenaTapeSpec tape) @?= 42 + 7919
            Tape.arenaTapeSpecGames (Tape.arenaTapeSpec tape) @?= 9
            Ref.nativeArenaObservedSpec family @?= spec
            map Ref.nativeArenaObservedReference (Ref.nativeArenaObservedReferences family)
              @?= [Ref.PlainLegalUniform, Ref.NeutralLegalMcts]
            map fst (Policy.nativeArenaCalibrationCounts calibration)
              @?= [Ref.PlainLegalUniform, Ref.NeutralLegalMcts]
    , testCase
        "actual reference scores and work derive from every retained nine-case outcome and decision"
        $ do
          fixture <- get
          forM_ (fixtureCalibrations fixture) $ \(_, calibration) -> do
            let family = Policy.nativeArenaCalibrationReferences calibration
                values = Ref.nativeArenaObservedReferences family
            Ref.nativeArenaTotalEvaluationTransitions family
              @?= sum (map Ref.nativeArenaObservedEvaluationTransitions values)
            Ref.nativeArenaTotalSearchRootVisits family
              @?= sum (map Ref.nativeArenaObservedSearchRootVisits values)
            forM_ (zip values (Policy.nativeArenaCalibrationCounts calibration)) $ \(actual, (_, counts)) -> do
              let episodes = Ref.nativeArenaObservedEpisodes actual
                  decisions = concatMap Ref.nativeArenaEpisodeDecisions episodes
              map Ref.nativeArenaEpisodeId episodes @?= [0 .. 8]
              Policy.nativeArenaCountsWins counts @?= Ref.nativeArenaObservedWins actual
              Policy.nativeArenaCountsDraws counts @?= Ref.nativeArenaObservedDraws actual
              Policy.nativeArenaCountsLosses counts @?= Ref.nativeArenaObservedLosses actual
              Policy.nativeArenaCountsExactScore counts @?= Ref.nativeArenaObservedExactScore actual
              Ref.nativeArenaObservedEvaluationTransitions actual @?= toInteger (length decisions)
              Ref.nativeArenaObservedSearchRootVisits actual
                @?= sum (map (toInteger . Ref.nativeArenaDecisionSearchRootVisits) decisions)
              assertBool
                "actual canonical reference exceeded universal bound"
                ( Ref.nativeArenaObservedExactScore actual >= 0
                    && Ref.nativeArenaObservedExactScore actual <= Policy.nativeArenaCalibrationMaximum calibration
                )
              inspectAll "complete actual calibration fields could not be inspected" actual
    , testCase
        "an actual terminal-rule reference fixture attains the universal nine-case maximum without search"
        $ do
          terminal <-
            foldM
              ( \state action -> do
                  assertBool "terminal fixture move was illegal" (action `elem` Game.legalMoves state)
                  pure (Game.applyMove action state)
              )
              (Game.initialStateFor "connect4")
              [0, 1, 0, 1, 0, 1, 0]
          Game.gameOutcome terminal @?= Game.GameWon 1
          descriptor <- right (Tape.mkArenaTapeSpec "connect4" 0 9 1)
          actual <-
            Ref.evaluateNativeArenaReferenceFixture
              terminal
              (Tape.materializeArenaTape descriptor)
              Ref.PlainLegalUniform
              >>= right
          Ref.nativeArenaObservedWins actual @?= 9
          Ref.nativeArenaObservedDraws actual @?= 0
          Ref.nativeArenaObservedLosses actual @?= 0
          Ref.nativeArenaObservedExactScore actual @?= 1
          Ref.nativeArenaObservedEvaluationTransitions actual @?= 0
          Ref.nativeArenaObservedSearchRootVisits actual @?= 0
    , -- This is an explicitly bounded terminal DATA fixture, not calibration
      -- from a canonical initial state or a learned/qualifying result.
      testCase "bounded WDL data retain every valid nine-case partition and exact rational score" $ do
        forM_ [(wins, draws, 9 - wins - draws) | wins <- [0 .. 9], draws <- [0 .. 9 - wins]] $ \(wins, draws, losses) -> do
          counts <- scoreCounts wins draws losses
          ( Policy.nativeArenaCountsWins counts
            , Policy.nativeArenaCountsDraws counts
            , Policy.nativeArenaCountsLosses counts
            )
            @?= (wins, draws, losses)
          Policy.nativeArenaCountsExactScore counts @?= (toInteger (2 * wins + draws) % 18)
    , testCase "negative empty overfull and overflow-sized count data reject without Int-sum wrap" $ do
        forM_ [(-1, 1, 9), (1, -1, 9), (1, 9, -1)] $ \(wins, draws, losses) -> rejects "nonnegative" (Policy.mkNativeArenaScoreCounts wins draws losses)
        forM_ [(0, 0, 0), (9, 1, 0), (maxBound, maxBound, 11)] $ \(wins, draws, losses) -> rejects "exactly nine" (Policy.mkNativeArenaScoreCounts wins draws losses)
    , testCase "reference comparison accepts strict gains and rejects scores below either fixed reference" $ do
        final <- scoreCounts 7 0 2
        lower <- scoreCounts 6 0 3
        higher <- scoreCounts 8 0 1
        Policy.nativeArenaCountsBeatReference final lower @?= True
        Policy.nativeArenaCountsBeatReference final higher @?= False
        Policy.nativeArenaCountsBeatReference lower final @?= False
    , testCase "arithmetic equality below maximum fails across every whole-win count" $ do
        forM_ [0 .. 8] $ \wins -> do
          counts <- scoreCounts wins 0 (9 - wins)
          Policy.nativeArenaCountsBeatReference counts counts @?= False
    , testCase "maximum-only equality is available independently for each reference and no lower final" $ do
        maximumCounts <- scoreCounts 9 0 0
        below <- scoreCounts 8 1 0
        map (Policy.nativeArenaCountsBeatReference maximumCounts) [below, maximumCounts] @?= [True, True]
        map (Policy.nativeArenaCountsBeatReference below) [below, maximumCounts] @?= [False, False]
    , -- These are only arithmetic comparisons, not a three/five cohort pass.
      testCase "a valid nonlearning full cohort retains all five raw DATA labels and original ordering" $ do
        fixture <- get
        compared <- right (compareRaw fixture (fixtureRaw fixture))
        Policy.nativeArenaComparisonCalibration compared @?= fixtureC4 fixture
        Policy.nativeArenaComparisonObservations compared @?= observations (fixtureRaw fixture)
        map Policy.nativeArenaSeedComparisonIndex (Policy.nativeArenaComparisonSeeds compared) @?= [0 .. 4]
        length (Policy.nativeArenaComparisonSeeds compared) @?= 5
        inspectAll "complete finite failed cohort did not retain inspectable DATA" compared
    , testCase "strict actual initial gain remains mandatory even when final values are otherwise valid" $ do
        fixture <- get
        compared <- right (compareRaw fixture (fixtureRaw fixture))
        Policy.nativeArenaComparisonJointCount compared @?= 0
        forM_ (Policy.nativeArenaComparisonSeeds compared) $ \seed -> do
          Policy.nativeArenaSeedComparisonInitialCounts seed
            @?= Policy.nativeArenaSeedComparisonFinalCounts seed
          Policy.nativeArenaSeedComparisonJointLearning seed @?= False
          assertBool
            "strict initial failure disappeared"
            (any (Text.isInfixOf "does not strictly exceed") (Policy.nativeArenaSeedComparisonFindings seed))
        assertBool
          "joint count failure disappeared"
          (any (Text.isInfixOf "fewer than three") (Policy.nativeArenaComparisonFindings compared))
    , testCase "both unchanged metric criteria and all five median inputs remain observable" $ do
        fixture <- get
        compared <- right (compareRaw fixture (fixtureRaw fixture))
        row <- currentRow (Policy.nativeArenaCalibrationSpec (fixtureC4 fixture))
        metricPairs <-
          mapM
            (requireCriteria . Policy.nativeArenaSeedComparisonLegacyCriteria)
            (Policy.nativeArenaComparisonSeeds compared)
        forM_ metricPairs $ \(arena, legal) -> do
          Budget.sameConvergenceCriterion arena (Thresholds.azgArenaWinRate row) @?= True
          Budget.sameConvergenceCriterion legal (Thresholds.azgLegalMoveRate row) @?= True
          Budget.coMetricName arena @?= "arena_win_rate"
          Budget.coMetricName legal @?= "legal_move_rate"
          Budget.coMetricValue legal @?= 1
        arenaMedian <- median (map (Budget.coMetricValue . fst) metricPairs)
        legalMedian <- median (map (Budget.coMetricValue . snd) metricPairs)
        (actualArena, actualLegal) <- requireCriteria (Policy.nativeArenaComparisonMedianCriteria compared)
        Budget.coMetricValue actualArena @?= arenaMedian
        Budget.coMetricValue actualLegal @?= legalMedian
        Budget.sameConvergenceCriterion actualArena (Thresholds.azgArenaWinRate row) @?= True
        Budget.sameConvergenceCriterion actualLegal (Thresholds.azgLegalMoveRate row) @?= True
    , testCase "fixed served index0 retains its own failed initial comparison independently of medians" $ do
        fixture <- get
        compared <- right (compareRaw fixture (fixtureRaw fixture))
        case Policy.nativeArenaComparisonSeeds compared of
          served : _ -> do
            Policy.nativeArenaSeedComparisonIndex served @?= 0
            forM_ (Policy.nativeArenaSeedComparisonFindings served) $ \finding ->
              assertBool
                "served0 finding was omitted"
                ( ("native arena served index0 fails: " <> finding)
                    `elem` Policy.nativeArenaComparisonFindings compared
                )
          [] -> assertFailure "valid comparison lost served0"
    , testCase
        "the retained actual arena criterion still excludes the all-draw score and legal-rate shortfall"
        $ do
          fixture <- get
          compared <- right (compareRaw fixture (fixtureRaw fixture))
          (arena, legal) <- requireCriteria (Policy.nativeArenaComparisonMedianCriteria compared)
          allDraw <- right (Budget.remeasureCriterion 0.5 arena)
          illegal <- right (Budget.remeasureCriterion 0.99 legal)
          Budget.convergencePassed allDraw @?= False
          Budget.convergencePassed illegal @?= False
    , -- Criterion DATA refinement only; no fabricated raw episodes are used.
      testCase "missing duplicate reordered and extra supplied seed indices reject before evaluation data" $ do
        fixture <- get
        let good = observations (fixtureRaw fixture)
        case good of
          first : second : rest -> forM_ [second : rest, first : first : rest, second : first : rest, good <> [first]] $ \bad ->
            rejects "all five indices" (Policy.compareNativeArenaCohort (fixtureC4 fixture) bad)
          _ -> assertFailure "written label fixture lacks five entries"
    , testCase "changed prescribed seed labels cannot be repaired by the retained complete raw result" $ do
        fixture <- get
        let good = observations (fixtureRaw fixture)
        forM_ [0 .. 4] $ \index -> do
          let bad =
                map
                  ( \entry ->
                      if Policy.nativeArenaObservedSeedIndex entry == index
                        then entry {Policy.nativeArenaObservedSeed = 47}
                        else entry
                  )
                  good
          rejects "seeds differ" (Policy.compareNativeArenaCohort (fixtureC4 fixture) bad)
    , testCase "an actual first-forward failed evaluator result cannot stand in for either complete phase" $ do
        fixture <- get
        fixtureFailureCalls fixture @?= 1
        rejects "observation is incomplete" (brokenInitial fixture (fixtureFailed fixture))
        rejects "observation is incomplete" (brokenFinal fixture (fixtureFailed fixture))
    , testCase "missing observed input and bounded fixture scope reject at their exact full-data boundary" $ do
        fixture <- get
        let raw = fixtureRaw fixture
        input <- inputOf raw
        rejects
          "no safely observed policy input"
          (brokenFinal fixture (raw {Arena.nativeArenaEvaluationInput = Nothing}))
        rejects
          "canonical predicate rejects fixture scope"
          ( brokenFinal
              fixture
              ( raw
                  { Arena.nativeArenaEvaluationInput =
                      Just (input {Arena.nativeArenaInputScope = Arena.BoundedNativeArenaFixture})
                  }
              )
          )
    , testCase "a different opaque canonical game specification cannot be relabelled as this row" $ do
        fixture <- get
        input <- inputOf (fixtureRaw fixture)
        otherSpec <- right (Ref.canonicalNativeArenaSpec "othello")
        let bad =
              (fixtureRaw fixture)
                { Arena.nativeArenaEvaluationInput =
                    Just (input {Arena.nativeArenaInputSpecification = Just otherSpec})
                }
        rejects "supplied context differs" (brokenFinal fixture bad)
    , testCase "a newly addressed tape with changed base cannot replace the single calibrated schedule" $ do
        fixture <- get
        input <- inputOf (fixtureRaw fixture)
        let spec = Policy.nativeArenaCalibrationSpec (fixtureC4 fixture)
        descriptor <-
          right
            (Tape.mkArenaTapeSpec "connect4" (42 + 7919 + 1) 9 (fromIntegral (Ref.nativeArenaSpecMaxPlies spec)))
        let bad =
              (fixtureRaw fixture)
                { Arena.nativeArenaEvaluationInput =
                    Just (input {Arena.nativeArenaInputTape = Tape.materializeArenaTape descriptor})
                }
        rejects "supplied context differs" (brokenFinal fixture bad)
    , testCase
        "missing duplicate reordered and extra actual episode IDs reject before scores are compared"
        $ do
          fixture <- get
          let raw = fixtureRaw fixture
          case Arena.nativeArenaEvaluationEpisodes raw of
            first : second : rest -> forM_
              [ second : rest
              , first : first : rest
              , second : first : rest
              , Arena.nativeArenaEvaluationEpisodes raw <> [first]
              ]
              $ \episodes ->
                rejects
                  "complete case inventory differs"
                  (brokenFinal fixture (raw {Arena.nativeArenaEvaluationEpisodes = episodes}))
            _ -> assertFailure "actual complete evaluation lacks nine cases"
    , testCase "changing a scored outcome without its real terminal or horizon history is rejected" $ do
        fixture <- get
        (first, rest) <- firstEpisode (fixtureRaw fixture)
        let changed = case Ref.nativeArenaEpisodeScoredOutcome first of
              Game.GameDraw -> Game.GameWon 1
              _ -> Game.GameDraw
            bad =
              (fixtureRaw fixture)
                { Arena.nativeArenaEvaluationEpisodes = first {Ref.nativeArenaEpisodeScoredOutcome = changed} : rest
                }
        rejects "terminal/horizon scoring differs" (brokenFinal fixture bad)
    , testCase "complete work cannot hide changed transition visits unfinished search or progress" $ do
        fixture <- get
        let raw = fixtureRaw fixture
            work = Arena.nativeArenaEvaluationWork raw
        (first, _) <- firstEpisode raw
        let changes =
              [ raw
                  { Arena.nativeArenaEvaluationWork =
                      work
                        { Arena.nativeArenaCompletedEpisodeTransitions = Arena.nativeArenaCompletedEpisodeTransitions work + 1
                        }
                  }
              , raw
                  { Arena.nativeArenaEvaluationWork =
                      work
                        { Arena.nativeArenaCompletedSearchRootVisits = Arena.nativeArenaCompletedSearchRootVisits work + 1
                        }
                  }
              , raw
                  { Arena.nativeArenaEvaluationWork =
                      work {Arena.nativeArenaUnfinishedSearch = Arena.UnknownUnfinishedArenaSearch}
                  }
              , raw
                  { Arena.nativeArenaEvaluationProgress =
                      Just (Arena.NativeArenaCaseProgress 0 0 (Ref.nativeArenaEpisodeInitialState first) [])
                  }
              ]
        forM_ changes (rejects "complete work differs" . brokenFinal fixture)
    , testCase "an illegal recorded action or altered actual search count fails real decision replay" $ do
        fixture <- get
        (episode, rest) <- firstEpisode (fixtureRaw fixture)
        (decision, tailDecisions) <- firstDecision episode
        let mutate changed =
              (fixtureRaw fixture)
                { Arena.nativeArenaEvaluationEpisodes =
                    episode {Ref.nativeArenaEpisodeDecisions = changed : tailDecisions} : rest
                }
        rejects
          "actual sampled action or transition differs"
          (brokenFinal fixture (mutate (decision {Ref.nativeArenaDecisionAction = -1})))
        rejects
          "actual search visits differ"
          ( brokenFinal
              fixture
              ( mutate
                  ( decision
                      { Ref.nativeArenaDecisionSearchRootVisits = Ref.nativeArenaDecisionSearchRootVisits decision + 1
                      }
                  )
              )
          )
    , testCase
        "malformed supplied net parameters and first-forward observations cannot survive the shared validator"
        $ do
          fixture <- get
          let raw = fixtureRaw fixture
          input <- inputOf raw
          let net = fixtureNet fixture
              params = Net.pvnParams net
              poison =
                net {Net.pvnParams = params {Mlp.paramW1 = VU.replicate (VU.length (Mlp.paramW1 params)) (0 / 0)}}
          rejects
            "parameters are malformed or overflow Float32"
            ( brokenFinal
                fixture
                (raw {Arena.nativeArenaEvaluationInput = Just (input {Arena.nativeArenaInputPolicy = poison})})
            )
          let summary = Arena.nativeArenaEvaluationForwards raw
          case Arena.nativeArenaFirstForwards summary of
            first : rest -> do
              let badOutput = first {Arena.nativeArenaForwardOutcome = Arena.NativeArenaForwardReturned (Right VU.empty)}
                  bad =
                    raw
                      { Arena.nativeArenaEvaluationForwards = summary {Arena.nativeArenaFirstForwards = badOutput : rest}
                      }
              rejects "complete callback output differs" (brokenFinal fixture bad)
              let badOrdinal =
                    raw
                      { Arena.nativeArenaEvaluationForwards =
                          summary {Arena.nativeArenaFirstForwards = first {Arena.nativeArenaForwardOrdinal = -1} : rest}
                      }
              rejects "complete callback summary differs" (brokenFinal fixture badOrdinal)
            [] -> assertFailure "actual canonical evaluator has no first callback"
    , testCase
        "calibration catches a lazy supplied specification without exposing it or renderer contents"
        $ do
          result <- Policy.observeNativeArenaReferenceCalibration (error "sensitive-specification-control")
          case result of
            Left detail -> do
              detail @?= "native arena reference calibration synchronous failure"
              assertBool
                "renderer contents leaked"
                (not ("sensitive-specification-control" `Text.isInfixOf` detail))
            Right _ -> assertFailure "poisonous supplied specification minted calibration DATA"
    , testCase
        "async cancellation while forcing a specification propagates instead of minting calibration"
        $ do
          result <-
            try (Policy.observeNativeArenaReferenceCalibration (throw ThreadKilled))
              :: IO (Either AsyncException (Either Text Policy.NativeArenaReferenceCalibration))
          case result of
            Left ThreadKilled -> pure ()
            _ -> assertFailure "asynchronous exception class was swallowed"
    , testCase "actual canonical learned evaluation keeps its supplied net and never queries a witness" $ do
        fixture <- get
        input <- inputOf (fixtureRaw fixture)
        let params = Net.pvnParams (Arena.nativeArenaInputPolicy input)
        map castDoubleToWord64 (Mlp.mlpParamsToFlat params)
          @?= map castDoubleToWord64 (Mlp.mlpParamsToFlat (Net.pvnParams (fixtureNet fixture)))
        fixtureWitnessCalls fixture @?= 0
        assertBool "actual scalar callbacks were not observed" (fixtureForwardCalls fixture > 0)
        let reported = Arena.nativeArenaForwardCalls (Arena.nativeArenaEvaluationForwards (fixtureRaw fixture))
        reported @?= fixtureForwardCalls fixture
        -- Offline public MLP callback/evaluator execution only. No training,
        -- real device witness or complete leaf-transcript authority is claimed.
    ]
