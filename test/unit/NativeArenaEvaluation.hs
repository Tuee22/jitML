{-# LANGUAGE OverloadedStrings #-}

module NativeArenaEvaluation (nativeArenaEvaluationTests) where

import Control.Exception (AsyncException (..), evaluate, throwIO, try)
import Control.Monad (forM_)
import Data.Bits (xor)
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef)
import Data.List (find)
import Data.Ratio ((%))
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)
import GHC.Float (castDoubleToWord64, castWord64ToDouble)
import Test.Tasty (TestTree, testGroup, withResource)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Numerics.Mlp qualified as Mlp
import JitML.Numerics.MlpDevice (MlpDevice (..), pureReferenceMlpDevice)
import JitML.RL.AlphaZero qualified as Game
import JitML.RL.AlphaZero.ArenaTape qualified as Tape
import JitML.RL.AlphaZero.NativeArenaEvaluation qualified as Eval
import JitML.RL.AlphaZero.NativeArenaReferences qualified as Ref
import JitML.RL.AlphaZero.PolicyValueNet qualified as Net

right :: (Show error) => Either error value -> IO value
right result = case result of
  Right value -> pure value
  Left detail -> assertFailure (show detail) >> fail "unreachable"
firstValue :: [value] -> IO value
firstValue values = case values of
  value : _ -> pure value
  [] -> assertFailure "actual observation list is empty" >> fail "unreachable"
rejects :: Text -> Either Text value -> Assertion
rejects fragment result = case result of
  Left detail -> assertBool "specific rejection boundary differs" (fragment `Text.isInfixOf` detail)
  Right _ -> assertFailure "invalid raw data passed the public unit predicate"

-- Demand the complete rendered spine before the same nonempty assertion.
-- A null/show-prefix shortcut would weaken these poisonous-data controls.
assertInspectable :: (Show value) => String -> value -> Assertion
assertInspectable label value = do
  renderedLength <- evaluate (length (show value))
  assertBool label (renderedLength > 0)

makeTape :: Text -> Word64 -> Word64 -> Word64 -> IO Tape.ArenaTape
makeTape game base count horizon = Tape.materializeArenaTape <$> right (Tape.mkArenaTapeSpec game base count horizon)
network :: Text -> Net.PolicyValueNet
network game = Net.initPolicyValueNet (Game.observationSizeFor game) (Game.actionCountFor game) 2 42
{-# NOINLINE vectorBits #-}
vectorBits :: VU.Vector Double -> [Word64]
vectorBits = map castDoubleToWord64 . VU.toList
{-# NOINLINE toggleSign #-}
toggleSign :: Word64 -> Double -> Double
toggleSign mask value = castWord64ToDouble (castDoubleToWord64 value `xor` mask)
paramBits :: Mlp.MlpParams -> [Word64]
paramBits = map castDoubleToWord64 . Mlp.mlpParamsToFlat

-- Every positive call delegates to actual existing pure MLP mathematics.
-- This deliberately grants no selected-hardware or producer authority.
data Fault
  = Clear
  | LeftAt Integer
  | ThrowAt Integer
  | LazyOuter
  | LazyLeft
  | LazyForward
  | WrongShape
  | Nonfinite
  | Overflow
  | Async
observedDevice :: IORef Integer -> Fault -> MlpDevice
observedDevice calls fault =
  pureReferenceMlpDevice
    { mlpdForward = \params input -> do
        ordinal <- atomicModifyIORef' calls (\n -> (n + 1, n))
        case fault of
          LeftAt at | ordinal >= at -> pure (Left "explicit learned-arena callback Left")
          ThrowAt at | ordinal >= at -> throwIO (userError "explicit learned-arena callback exception")
          LazyOuter -> pure (error "lazy learned-arena Either")
          LazyLeft -> pure (Left (error "lazy learned-arena Left text"))
          LazyForward -> pure (Right (error "lazy learned-arena forward"))
          WrongShape -> pure (Right ((Mlp.mlpForward params input) {Mlp.forwardOutput = VU.empty}))
          Nonfinite ->
            pure
              ( Right
                  ( (Mlp.mlpForward params input)
                      { Mlp.forwardOutput = VU.replicate (Mlp.mlpOutputs (Mlp.paramShape params)) (0 / 0)
                      }
                  )
              )
          Overflow ->
            pure
              ( Right
                  ( (Mlp.mlpForward params input)
                      { Mlp.forwardOutput = VU.replicate (Mlp.mlpOutputs (Mlp.paramShape params)) 1e300
                      }
                  )
              )
          Async -> throwIO ThreadKilled
          _ -> mlpdForward pureReferenceMlpDevice params input
    , mlpdExecutionWitness = assertFailure "data-only arena queried a witness" >> fail "unreachable"
    }

data Complete
  = Complete Ref.NativeArenaSpec Tape.ArenaTape Net.PolicyValueNet Eval.RawNativeArenaEvaluation Integer
complete :: IO Complete
complete = do
  spec <- right (Ref.canonicalNativeArenaSpec "connect4")
  let tape = Ref.materializeNativeArenaTape spec; net = network "connect4"
  calls <- newIORef 0
  raw <- Eval.evaluateNativeArenaPolicy (observedDevice calls Clear) spec tape net
  count <- readIORef calls
  Eval.validateNativeArenaEvaluationData spec tape net raw @?= Right ()
  pure (Complete spec tape net raw count)

fixture :: Fault -> IO Eval.RawNativeArenaEvaluation
fixture fault = do
  tape <- makeTape "connect4" 7961 1 1
  calls <- newIORef 0
  Eval.evaluateNativeArenaPolicyFixture
    Game.initialConnect4
    (observedDevice calls fault)
    tape
    (network "connect4")

failure :: Eval.NativeArenaFailureKind -> Text -> Eval.RawNativeArenaEvaluation -> Assertion
failure kind fragment raw = case Eval.nativeArenaEvaluationStatus raw of
  Eval.NativeArenaEvaluationFailed _ _ actual detail -> do
    actual @?= kind
    assertBool "actual failure reason differs" (fragment `Text.isInfixOf` detail)
  _ -> assertFailure "actual failure was not retained"

nativeArenaEvaluationTests :: TestTree
nativeArenaEvaluationTests = withResource complete (const (pure ())) $ \get ->
  testGroup
    "native learned addressed arena observations"
    [ testCase
        "actual canonical nine game learned search observations retain exact tape callbacks and work"
        $ do
          Complete spec tape net raw count <- get
          Eval.nativeArenaEvaluationStatus raw @?= Eval.NativeArenaEvaluationComplete
          map Ref.nativeArenaEpisodeId (Eval.nativeArenaEvaluationEpisodes raw) @?= [0 .. 8]
          Eval.nativeArenaForwardCalls (Eval.nativeArenaEvaluationForwards raw) @?= count
          assertBool "real pure-NN leaf forwards did not run" (count > 0)
          Eval.nativeArenaEvaluationProgress raw @?= Nothing
          Eval.validateNativeArenaEvaluationData spec tape net raw @?= Right ()
          let decisions = concatMap Ref.nativeArenaEpisodeDecisions (Eval.nativeArenaEvaluationEpisodes raw)
          Eval.nativeArenaCompletedEpisodeTransitions (Eval.nativeArenaEvaluationWork raw)
            @?= toInteger (length decisions)
          Eval.nativeArenaCompletedSearchRootVisits (Eval.nativeArenaEvaluationWork raw)
            @?= sum (map (toInteger . Ref.nativeArenaDecisionSearchRootVisits) decisions)
          case Eval.nativeArenaEvaluationInput raw of
            Just input -> do
              Eval.nativeArenaInputScope input @?= Eval.CanonicalNativeArena
              Tape.arenaTapeBytes (Eval.nativeArenaInputTape input) @?= Tape.arenaTapeBytes tape
              paramBits (Net.pvnParams (Eval.nativeArenaInputPolicy input)) @?= paramBits (Net.pvnParams net)
            Nothing -> assertFailure "complete actual input was discarded"
    , testCase
        "one real search fixture matches the existing public device MCTS distribution and exact selector"
        $ do
          tape <- makeTape "connect4" 7961 1 1
          let net = network "connect4"
          calls <- newIORef 0
          raw <-
            Eval.evaluateNativeArenaPolicyFixture Game.initialConnect4 (observedDevice calls Clear) tape net
          Eval.validateNativeArenaFixtureData raw @?= Right ()
          episode <- firstValue (Eval.nativeArenaEvaluationEpisodes raw)
          decision <- firstValue (Ref.nativeArenaEpisodeDecisions episode)
          entry <- right (Tape.arenaTapeLookup tape 0 0 1)
          distribution <-
            right
              =<< Net.mctsVisitDistributionWithDevice
                pureReferenceMlpDevice
                net
                48
                Game.initialConnect4
                (Tape.arenaEntryMctsSeed entry)
          vectorBits (Ref.nativeArenaDecisionDistribution decision) @?= vectorBits distribution
          expected <-
            right
              (Ref.sampleNativeArenaPlayerAction 7 (Game.legalMoves Game.initialConnect4) distribution entry)
          Ref.nativeArenaDecisionAction decision @?= expected
          Ref.nativeArenaDecisionSearchRootVisits decision @?= 48
          Ref.nativeArenaEpisodeHorizonTruncated episode @?= True
          Ref.nativeArenaEpisodeScoredOutcome episode @?= Game.GameDraw
          Eval.nativeArenaEvaluationExactScore raw @?= Just (1 % 2)
    , testCase "bounded fixture observations cannot pass the canonical complete data predicate" $ do
        Complete spec tape net _ _ <- get
        raw <- fixture Clear
        rejects "rejects fixture scope" (Eval.validateNativeArenaEvaluationData spec tape net raw)
    , testCase "all four actual game contexts route to their own NN shape and signed tape before failure" $ do
        forM_ ["connect4", "othello", "hex", "gomoku"] $ \game -> do
          tape <- makeTape game 7961 1 1
          calls <- newIORef 0
          raw <-
            Eval.evaluateNativeArenaPolicyFixture
              (Game.initialStateFor game)
              (observedDevice calls (LeftAt 0))
              tape
              (network game)
          failure Eval.NativeArenaSearchRejected "explicit learned-arena callback Left" raw
          readIORef calls >>= (@?= 1)
          first <- firstValue (Eval.nativeArenaFirstForwards (Eval.nativeArenaEvaluationForwards raw))
          VU.length (Eval.nativeArenaForwardInput first) @?= Game.observationSizeFor game
          Mlp.paramShape (Eval.nativeArenaForwardParameters first)
            @?= Mlp.MlpShape (Game.observationSizeFor game) 2 (Game.actionCountFor game + 1)
    , testCase "canonical wrong base game count horizon and row reject before any callback" $ do
        Complete spec _ net _ _ <- get
        forM_
          [ ("connect4", 7962, 9, 42, "canonical context differs")
          , ("connect4", 7961, 8, 42, "canonical context differs")
          , ("connect4", 7961, 9, 41, "canonical context differs")
          , ("othello", 7961, 9, 42, "tape game differs")
          ]
          $ \(game, base, count, horizon, fragment) -> do
            tape <- makeTape game base count horizon
            calls <- newIORef 0
            raw <- Eval.evaluateNativeArenaPolicy (observedDevice calls Clear) spec tape net
            case Eval.nativeArenaEvaluationStatus raw of
              Eval.NativeArenaEvaluationRejected detail -> assertBool "wrong canonical context rejection" (fragment `Text.isInfixOf` detail)
              _ -> assertFailure "wrong canonical tape was executed"
            readIORef calls >>= (@?= 0)
    , testCase "wrong network shape malformed weights NaN and Float32 overflow reject before callback" $ do
        Complete spec tape net _ _ <- get
        let params = Net.pvnParams net
            invalid =
              [ (net {Net.pvnActionCount = 6}, "network dimensions differ")
              , (net {Net.pvnParams = params {Mlp.paramW1 = VU.empty}}, "parameters are malformed")
              ,
                ( net {Net.pvnParams = params {Mlp.paramB1 = VU.map (const (0 / 0)) (Mlp.paramB1 params)}}
                , "parameters are malformed"
                )
              ,
                ( net {Net.pvnParams = params {Mlp.paramB1 = VU.map (const 1e300) (Mlp.paramB1 params)}}
                , "parameters are malformed"
                )
              ]
        forM_ invalid $ \(bad, fragment) -> do
          calls <- newIORef 0
          raw <- Eval.evaluateNativeArenaPolicy (observedDevice calls Clear) spec tape bad
          case Eval.nativeArenaEvaluationStatus raw of
            Eval.NativeArenaEvaluationRejected detail -> assertBool "wrong actual NN context rejection" (fragment `Text.isInfixOf` detail)
            _ -> assertFailure "malformed actual NN context passed"
          readIORef calls >>= (@?= 0)
    , testCase
        "finite inexact and underflowing binary64 parameters follow the existing Float32 representation contract"
        $ do
          Complete spec tape net _ _ <- get
          let params = Net.pvnParams net
          forM_ [0.1, 1e-200] $ \value -> do
            let small = net {Net.pvnParams = params {Mlp.paramB1 = VU.replicate (VU.length (Mlp.paramB1 params)) value}}
            Eval.validateNativeArenaPolicyContext spec tape small @?= Right ()
    , testCase
        "actual first callback Left retains Unknown unfinished search rather than invented transitions"
        $ do
          raw <- fixture (LeftAt 0)
          failure Eval.NativeArenaSearchRejected "explicit learned-arena callback Left" raw
          Eval.nativeArenaEvaluationEpisodes raw @?= []
          Eval.nativeArenaEvaluationWork raw
            @?= Eval.NativeArenaEvaluationWork 0 0 0 Eval.UnknownUnfinishedArenaSearch
          Eval.nativeArenaForwardCalls (Eval.nativeArenaEvaluationForwards raw) @?= 1
          Eval.nativeArenaEvaluationExactScore raw @?= Nothing
    , testCase
        "a later case Left preserves complete episodes and their work without using callback count as transitions"
        $ do
          Complete spec tape net baseline _ <- get
          observed <-
            maybe
              (assertFailure "second actual case callback absent" >> fail "unreachable")
              pure
              ( find
                  ((== 1) . Eval.nativeArenaForwardGame)
                  (Eval.nativeArenaFirstForwards (Eval.nativeArenaEvaluationForwards baseline))
              )
          calls <- newIORef 0
          raw <-
            Eval.evaluateNativeArenaPolicy
              (observedDevice calls (LeftAt (Eval.nativeArenaForwardOrdinal observed)))
              spec
              tape
              net
          failure Eval.NativeArenaSearchRejected "explicit learned-arena callback Left" raw
          case (Eval.nativeArenaEvaluationEpisodes baseline, Eval.nativeArenaEvaluationEpisodes raw) of
            (first : _, [kept]) -> do
              kept @?= first
              Eval.nativeArenaCompletedEpisodeTransitions (Eval.nativeArenaEvaluationWork raw)
                @?= toInteger (length (Ref.nativeArenaEpisodeDecisions first))
            _ -> assertFailure "completed episode prefix was altered or lost"
          Eval.nativeArenaCurrentEpisodeTransitions (Eval.nativeArenaEvaluationWork raw) @?= 0
          Eval.nativeArenaUnfinishedSearch (Eval.nativeArenaEvaluationWork raw)
            @?= Eval.UnknownUnfinishedArenaSearch
    , testCase "synchronous callback exceptions remain safe raw failure data" $ do
        raw <- fixture (ThrowAt 0)
        failure Eval.NativeArenaSearchException "explicit learned-arena callback exception" raw
        assertInspectable "complete retained DTO rendering failed" raw
        case Eval.nativeArenaFailedForward (Eval.nativeArenaEvaluationForwards raw) of
          Just actual -> case Eval.nativeArenaForwardOutcome actual of
            Eval.NativeArenaForwardException _ -> pure ()
            _ -> assertFailure "actual callback exception was relabeled"
          Nothing -> assertFailure "actual failed callback was lost"
    , testCase "lazy outer Either Left text and forward payload are forced inside capture" $ do
        forM_
          [ (LazyOuter, "lazy learned-arena Either")
          , (LazyLeft, "lazy learned-arena Left text")
          , (LazyForward, "lazy learned-arena forward")
          ]
          $ \(fault, fragment) -> do
            raw <- fixture fault
            failure Eval.NativeArenaSearchException fragment raw
            assertInspectable "retained DTO still contains poisonous callback data" raw
    , testCase "wrong output width NaN and Float32 overflow fail through the actual guarded oracle" $ do
        forM_ [WrongShape, Nonfinite, Overflow] $ \fault -> do
          raw <- fixture fault
          failure Eval.NativeArenaSearchRejected "output has the wrong shape or is not finite Float32" raw
          Eval.nativeArenaForwardCalls (Eval.nativeArenaEvaluationForwards raw) @?= 1
          Eval.nativeArenaUnfinishedSearch (Eval.nativeArenaEvaluationWork raw)
            @?= Eval.UnknownUnfinishedArenaSearch
          case Eval.nativeArenaFailedForward (Eval.nativeArenaEvaluationForwards raw) of
            Just _ -> pure ()
            Nothing -> assertFailure "actual malformed Right output was discarded"
    , testCase
        "async callback cancellation propagates instead of becoming a completed or failed observation"
        $ do
          actual <- try (fixture Async) :: IO (Either AsyncException Eval.RawNativeArenaEvaluation)
          case actual of Left ThreadKilled -> pure (); _ -> assertFailure "async cancellation was swallowed"
    , testCase "unmaterializable input returns only safe absent input and actual exception detail" $ do
        tape <- makeTape "connect4" 7961 1 1
        calls <- newIORef 0
        raw <-
          Eval.evaluateNativeArenaPolicyFixture
            Game.initialConnect4
            (observedDevice calls Clear)
            tape
            (error "unmaterializable supplied network")
        failure Eval.NativeArenaInputException "unmaterializable supplied network" raw
        Eval.nativeArenaEvaluationInput raw @?= Nothing
        readIORef calls >>= (@?= 0)
        assertInspectable "safe absent-input failure is not inspectable" raw
    , testCase "already terminal real game fixtures score the actual winner without NN or search work" $ do
        forM_ [(winning, 1), (losing, 0)] $ \(state, score) -> do
          tape <- makeTape "connect4" 7961 2 42
          calls <- newIORef 0
          raw <-
            Eval.evaluateNativeArenaPolicyFixture state (observedDevice calls Clear) tape (network "connect4")
          Eval.validateNativeArenaFixtureData raw @?= Right ()
          Eval.nativeArenaEvaluationExactScore raw @?= Just score
          Eval.nativeArenaEvaluationWork raw
            @?= Eval.NativeArenaEvaluationWork 0 0 0 Eval.NoUnfinishedArenaSearch
          readIORef calls >>= (@?= 0)
    , testCase
        "actual Othello forced pass consumes negative signed side without an extra decision or network search"
        $ do
          tape <- makeTape "othello" 7961 1 1
          calls <- newIORef 0
          raw <-
            Eval.evaluateNativeArenaPolicyFixture
              passPosition
              (observedDevice calls Clear)
              tape
              (network "othello")
          Eval.validateNativeArenaFixtureData raw @?= Right ()
          episode <- firstValue (Eval.nativeArenaEvaluationEpisodes raw)
          decision <- firstValue (Ref.nativeArenaEpisodeDecisions episode)
          Ref.nativeArenaDecisionForcedPass decision @?= True
          Ref.nativeArenaDecisionPlayer decision @?= -1
          Tape.arenaEntrySignedPlayer (Ref.nativeArenaDecisionTapeEntry decision) @?= -1
          Ref.nativeArenaDecisionSlot decision @?= 0
          Ref.nativeArenaDecisionSearchRootVisits decision @?= 0
          length (Ref.nativeArenaEpisodeDecisions episode) @?= 1
          readIORef calls >>= (@?= 0)
    , testCase "fixture scope rejects illegal history player and row before any callback" $ do
        tape <- makeTape "connect4" 7961 1 1
        forM_
          [ (Game.GameState "connect4" [7] (-1), "history is illegal")
          , (Game.initialConnect4 {Game.gameCurrentPlayer = -1}, "not the actual legal history")
          , (Game.initialConnect4 {Game.gameName = "CONNECT4"}, "not exact canonical metadata")
          ]
          $ \(state, fragment) -> do
            calls <- newIORef 0
            raw <-
              Eval.evaluateNativeArenaPolicyFixture state (observedDevice calls Clear) tape (network "connect4")
            case Eval.nativeArenaEvaluationStatus raw of
              Eval.NativeArenaEvaluationRejected detail -> assertBool "wrong actual fixture context rejection" (fragment `Text.isInfixOf` detail)
              _ -> assertFailure "illegal fixture context executed"
            readIORef calls >>= (@?= 0)
    , testCase "complete data predicate rejects missing duplicate reordered cases and false work" $ do
        Complete spec tape net raw _ <- get
        case Eval.nativeArenaEvaluationEpisodes raw of
          first : rest -> do
            forM_ [rest, first : first : rest, reverse (first : rest)] $ \episodes ->
              rejects
                "inventory"
                ( Eval.validateNativeArenaEvaluationData
                    spec
                    tape
                    net
                    (raw {Eval.nativeArenaEvaluationEpisodes = episodes})
                )
            rejects
              "work differs"
              ( Eval.validateNativeArenaEvaluationData
                  spec
                  tape
                  net
                  ( raw
                      { Eval.nativeArenaEvaluationWork = Eval.NativeArenaEvaluationWork 0 0 0 Eval.NoUnfinishedArenaSearch
                      }
                  )
              )
          [] -> assertFailure "complete actual nine case observation absent"
    , testCase
        "complete data predicate rejects actual signed-zero parameter substitution and truncated callback evidence"
        $ do
          Complete spec tape net raw _ <- get
          let params = Net.pvnParams net
              originalBias = Mlp.paramB1 params
              signedBias = VU.map (toggleSign 0x8000000000000000) originalBias
              changed = net {Net.pvnParams = params {Mlp.paramB1 = signedBias}}
          assertBool "signed-zero original bias is nonempty" (not (VU.null originalBias))
          assertBool "signed-zero original bias is numerically zero" (VU.all (== 0) originalBias)
          signedBias @?= originalBias
          assertBool
            "signed-zero bias mutation changes actual stored bits"
            (vectorBits signedBias /= vectorBits originalBias)
          rejects "supplied context differs" (Eval.validateNativeArenaEvaluationData spec tape changed raw)
          let summary = Eval.nativeArenaEvaluationForwards raw
          rejects
            "callback summary differs"
            ( Eval.validateNativeArenaEvaluationData
                spec
                tape
                net
                (raw {Eval.nativeArenaEvaluationForwards = summary {Eval.nativeArenaFirstForwards = []}})
            )
    , testCase
        "actual legal decisions reject changed tape action player and search visits through the unit predicate"
        $ do
          raw <- fixture Clear
          case Eval.nativeArenaEvaluationEpisodes raw of
            [episode] -> case Ref.nativeArenaEpisodeDecisions episode of
              [decision] -> do
                let mutate changed =
                      raw {Eval.nativeArenaEvaluationEpisodes = [episode {Ref.nativeArenaEpisodeDecisions = [changed]}]}
                rejects
                  "state/player/legal"
                  (Eval.validateNativeArenaFixtureData (mutate (decision {Ref.nativeArenaDecisionPlayer = -1})))
                rejects
                  "tape or actual search visits"
                  ( Eval.validateNativeArenaFixtureData
                      (mutate (decision {Ref.nativeArenaDecisionSearchRootVisits = 47}))
                  )
                otherTape <- makeTape "connect4" 7961 1 2
                otherEntry <- right (Tape.arenaTapeLookup otherTape 0 1 1)
                rejects
                  "tape or actual search visits"
                  ( Eval.validateNativeArenaFixtureData
                      (mutate (decision {Ref.nativeArenaDecisionTapeEntry = otherEntry}))
                  )
                rejects
                  "sampled action or transition"
                  (Eval.validateNativeArenaFixtureData (mutate (decision {Ref.nativeArenaDecisionAction = 7})))
                rejects
                  "distribution"
                  ( Eval.validateNativeArenaFixtureData
                      (mutate (decision {Ref.nativeArenaDecisionDistribution = VU.replicate 7 0}))
                  )
              _ -> assertFailure "actual one move fixture differs"
            _ -> assertFailure "actual one case fixture differs"
    , testCase
        "exact complete score is derived from actual outcomes and incomplete observations have no score"
        $ do
          Complete _ _ _ raw _ <- get
          let outcomes = map Ref.nativeArenaEpisodeScoredOutcome (Eval.nativeArenaEvaluationEpisodes raw)
              wins = length (filter (== Game.GameWon 1) outcomes)
              draws = length (filter (== Game.GameDraw) outcomes)
          Eval.nativeArenaEvaluationExactScore raw @?= Just ((2 * toInteger wins + toInteger draws) % 18)
          Eval.nativeArenaEvaluationExactScore
            (raw {Eval.nativeArenaEvaluationStatus = Eval.NativeArenaEvaluationRejected "not complete"})
            @?= Nothing
    , testCase
        "full board43 Connect Four is explicit fixture only and matches the actual public device oracle"
        $ do
          let net = Net.initPolicyValueNet 43 7 2 42
          spec <- right (Ref.canonicalNativeArenaSpec "connect4")
          canonicalCalls <- newIORef 0
          rejected <-
            Eval.evaluateNativeArenaPolicy
              (observedDevice canonicalCalls Clear)
              spec
              (Ref.materializeNativeArenaTape spec)
              net
          case Eval.nativeArenaEvaluationStatus rejected of
            Eval.NativeArenaEvaluationRejected detail ->
              assertBool
                "canonical8 shape rejection differs"
                ("network dimensions differ" `Text.isInfixOf` detail)
            _ -> assertFailure "diagnostic43 shape passed the canonical8 route"
          readIORef canonicalCalls >>= (@?= 0)
          tape <- makeTape "connect4" 7961 1 1
          calls <- newIORef 0
          raw <-
            Eval.evaluateNativeArenaPolicyFixture Game.initialConnect4 (observedDevice calls Clear) tape net
          Eval.validateNativeArenaFixtureData raw @?= Right ()
          rejects
            "rejects fixture scope"
            ( Eval.validateNativeArenaEvaluationData
                spec
                (Ref.materializeNativeArenaTape spec)
                (network "connect4")
                raw
            )
          episode <- firstValue (Eval.nativeArenaEvaluationEpisodes raw)
          decision <- firstValue (Ref.nativeArenaEpisodeDecisions episode)
          entry <- right (Tape.arenaTapeLookup tape 0 0 1)
          distribution <-
            right
              =<< Net.mctsVisitDistributionWithDevice
                pureReferenceMlpDevice
                net
                48
                Game.initialConnect4
                (Tape.arenaEntryMctsSeed entry)
          vectorBits (Ref.nativeArenaDecisionDistribution decision) @?= vectorBits distribution
          expected <-
            right
              (Ref.sampleNativeArenaPlayerAction 7 (Game.legalMoves Game.initialConnect4) distribution entry)
          Ref.nativeArenaDecisionAction decision @?= expected
          first <- firstValue (Eval.nativeArenaFirstForwards (Eval.nativeArenaEvaluationForwards raw))
          VU.length (Eval.nativeArenaForwardInput first) @?= 43
          vectorBits (Eval.nativeArenaForwardInput first)
            @?= vectorBits (Net.encodeGameState net Game.initialConnect4)
          Mlp.paramShape (Eval.nativeArenaForwardParameters first) @?= Mlp.MlpShape 43 2 8
          assertBool "actual43 fixture never called its real MLP" . (> 0) =<< readIORef calls
          assertInspectable "complete materialized decision and episode data are not inspectable" raw
    ]

winning, losing, passPosition :: Game.GameState
winning = foldl' (flip Game.applyMove) Game.initialConnect4 [0, 1, 0, 1, 0, 1, 0]
losing = foldl' (flip Game.applyMove) Game.initialConnect4 [0, 1, 0, 1, 2, 1, 2, 1]
-- The exact existing public-rule reachable fixture, retained as fixture data.
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
