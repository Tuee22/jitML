{-# LANGUAGE OverloadedStrings #-}

-- | Separate closed reference DATA bodies. No environment, simulator, sampler,
-- evaluator or action-bearing capability is called/constructed by this module.
module JitML.Checkpoint.NativeReferences.Body
  ( ReferenceFamily (..)
  , ReferenceDimensions (..)
  , encodeReturnBody
  , encodeHerBody
  , encodeArenaBody
  , validateBody
  ) where

import Codec.CBOR.Encoding qualified as CBOR
import Control.Monad (replicateM_, unless, void, when)
import Data.Bits (shiftR, (.&.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Builder qualified as Builder
import Data.ByteString.Lazy qualified as LBS
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Ratio (denominator, numerator)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as UTF8
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)
import GHC.Float (castDoubleToWord64)

import JitML.Checkpoint.NativePhase.CBOR qualified as Wire
import JitML.Checkpoint.NativePhase.Types
import JitML.RL.AlphaZero qualified as Game
import JitML.RL.AlphaZero.ArenaTape qualified as Tape
import JitML.RL.AlphaZero.NativeArenaReferences qualified as Arena
import JitML.RL.NativeHerReferences qualified as Her
import JitML.RL.NativeReturnReferences qualified as Return

-- These are ordinary DATA tags, deliberately outside the child73 grammar.
data ReferenceFamily = ReturnReferenceFamily | HerReferenceFamily | ArenaReferenceFamily
  deriving stock (Eq, Show, Enum, Bounded)
data ReferenceDimensions
  = ReturnDimensions !Int !Int !Int
  | HerDimensions
  | ArenaDimensions !Int !Int !Int
  deriving stock (Eq, Show)

bodyLimit :: Integer
bodyLimit = 128 * 1024 * 1024

require :: Bool -> Text -> Either CodecError ()
require predicate detail = unless predicate (Left (Malformed detail))
exact :: Int -> [a] -> Either CodecError [a]
exact expected values = do
  n <- boundedLength AggregateSequenceElements (toInteger expected) values
  require (n == expected) "reference collection has wrong complete cardinality"
  pure values
word :: Integer -> Either CodecError CBOR.Encoding
word value = do
  require
    (value >= 0 && value <= toInteger (maxBound :: Word64))
    "reference integer is outside uint64 DATA scope"
  pure (CBOR.encodeWord64 (fromInteger value))
signed :: Int -> CBOR.Encoding
signed = CBOR.encodeInt64 . fromIntegral
bits :: Double -> CBOR.Encoding
bits = CBOR.encodeBytes . Wire.word64Bytes . castDoubleToWord64
blob :: ByteString -> CBOR.Encoding
blob = CBOR.encodeBytes
array :: [CBOR.Encoding] -> CBOR.Encoding
array fields = CBOR.encodeListLen (fromIntegral (length fields)) <> mconcat fields
list :: [CBOR.Encoding] -> CBOR.Encoding
list = array

-- At most273 scratch bytes are formed before refusing an arbitrary huge
-- supplied Integer. The complete-ratio cap is272 per magnitude, not combined.
magnitude :: Integer -> Either CodecError ByteString
magnitude value = do
  let (bytes, remainder) =
        BS.unfoldrN
          273
          (\n -> if n == 0 then Nothing else Just (fromIntegral (n .&. 255), n `shiftR` 8))
          value
  require
    (BS.length bytes <= 272 && maybe True (== 0) remainder)
    "reference magnitude exceeds272 bytes"
  pure (BS.reverse bytes)
rational :: Rational -> Either CodecError CBOR.Encoding
rational value = do
  let n = numerator value
      d = denominator value
  require (d > 0) "reference rational denominator is nonpositive"
  a <- magnitude (abs n)
  b <- magnitude d
  pure (array [CBOR.encodeBool (n < 0), blob a, blob b])

shapeBound :: Integer -> Either CodecError ()
shapeBound upper = when (upper > bodyLimit) (Left (ResourceExceeded WholePayloadBytes bodyLimit upper))

finish :: CBOR.Encoding -> Either CodecError ByteString
finish encoding = do
  let bytes = Wire.encodeStrict encoding
  require (toInteger (BS.length bytes) <= bodyLimit) "reference body exceeds128MiB"
  pure bytes

encodeReturnBody
  :: ReferenceDimensions -> Return.NativeReturnReferenceSet -> Either CodecError ByteString
encodeReturnBody (ReturnDimensions controls cases horizon) actual = do
  require
    (controls > 0 && controls <= 720 && cases == 20 && horizon > 0 && horizon <= 1000)
    "RETURN encoding dimensions exceed scope"
  shapeBound (65536 + toInteger controls * 1536)
  refs <- exact controls (Return.nativeReturnObservedReferences actual)
  records <- traverse one refs
  total <- word (Return.nativeReturnTotalEvaluationTransitions actual)
  finish (array [list records, total])
 where
  one observed = do
    controller <- control (Return.nativeReturnObservedController observed)
    episodes <- exact cases (Return.nativeReturnObservedEpisodes observed)
    records <- traverse episode (zip [0 ..] episodes)
    work <- word (Return.nativeReturnObservedEvaluationTransitions observed)
    let rewards = fmap Return.nativeReturnEpisodeReward episodes
    require
      (all (\x -> not (isNaN x || isInfinite x)) rewards)
      "reference exact median is unavailable for nonfinite rewards"
    let ordered = sort (fmap toRational rewards)
        half = cases `div` 2
    median <- case drop (half - 1) ordered of
      lower : upper : _ | even cases -> rational ((lower + upper) / 2)
      _ | odd cases -> case drop half ordered of
        value : _ -> rational value
        [] -> Left (Malformed "reference median has no middle value")
      _ -> Left (Malformed "reference median has no pair")
    pure (array [controller, list records, work, median])
  episode (ordinal, value) = do
    require (Return.nativeReturnEpisodeId value == ordinal) "reference episode order differs"
    require
      (Return.nativeReturnEpisodeSteps value >= 0 && Return.nativeReturnEpisodeSteps value <= horizon)
      "reference steps exceed declared horizon"
    pure
      ( array
          [ signed ordinal
          , bits (Return.nativeReturnEpisodeReward value)
          , signed (Return.nativeReturnEpisodeSteps value)
          , CBOR.encodeBool (Return.nativeReturnEpisodeTerminated value)
          ]
      )
  control value = case value of
    Return.ConstantDiscrete action -> pure (array [CBOR.encodeWord64 0, signed action])
    Return.FixedMaskedPreference actions -> do
      n <- boundedLength AggregateSequenceElements 6 actions
      require (n > 0) "reference preference is empty"
      pure (array [CBOR.encodeWord64 1, list (fmap signed actions)])
    Return.ConstantContinuous kind value_ ->
      pure
        ( array
            [ CBOR.encodeWord64 2
            , CBOR.encodeWord64
                ( case kind of
                    Return.NativeZero -> 0
                    Return.NativeLowerEndpoint -> 1
                    Return.NativeUpperEndpoint -> 2
                )
            , bits value_
            ]
        )
encodeReturnBody _ _ = Left (Malformed "RETURN dimensions differ")

-- Complete source-proven sharing only: goals and action prefixes are checked
-- against the actual record before being represented by schedule/ordinal.
encodeHerBody :: Her.NativeHerReferenceFamily -> Either CodecError ByteString
encodeHerBody actual = do
  shapeBound 95852462
  let schedule = Her.nativeHerObservedSchedule actual
  goals <- exact 20 (Her.nativeHerScheduleCases schedule)
  mapM_
    ( \(i, g) ->
        require
          (Her.rawNativeHerCaseId g == i && VU.length (Her.rawNativeHerGoal g) == 6)
          "HER schedule shape/order differs"
    )
    (zip [0 ..] goals)
  refs <- exact 46656 (Her.nativeHerObservedReferences actual)
  let spec = Her.nativeHerScheduleSpec schedule
      sequences = Her.allNativeHerGoalBlindSequences spec
  expected <- exact 46656 sequences
  records <- traverse (one goals) (zip3 [0 ..] expected refs)
  extrema <- extremaData expected (Her.nativeHerObservedExtrema actual)
  total <- word (Her.nativeHerTotalEvaluationTransitions actual)
  finish (array [list records, extrema, total])
 where
  one goals (ordinal, expected, observed) = do
    let actions = Her.nativeHerSequenceActions (Her.nativeHerObservedSequence observed)
    require (actions == Her.nativeHerSequenceActions expected) "HER actual sequence order differs"
    let wireId = "goal-blind-sequence/" <> Text.intercalate "," (fmap (Text.pack . show) actions)
    require (Her.nativeHerSequenceId expected == wireId) "HER sequence ID renderer differs from wire-v1"
    outcomes <- exact 20 (Her.nativeHerObservedOutcomes observed)
    packed <- traverse (outcome actions) (zip3 [0 ..] goals outcomes)
    success <- word (toInteger (Her.nativeHerObservedSuccessCount observed))
    mean <- rational (Her.nativeHerObservedExactMeanDistance observed)
    transitions <- word (Her.nativeHerObservedEvaluationTransitions observed)
    pure (array [signed ordinal, blob (BS.concat packed), success, mean, transitions])
  outcome actions (ordinal, goal, value) = do
    let state = Her.nativeHerOutcomeFinalState value
        steps = Her.nativeHerOutcomeSteps value
        distance = Her.nativeHerOutcomeHammingDistance value
        actualGoal = Her.nativeHerOutcomeGoal value
    require (Her.nativeHerOutcomeCaseId value == ordinal) "HER actual outcome order differs"
    require (VU.length actualGoal == 6 && VU.length state == 6) "HER actual vector width differs"
    require
      (sameVector actualGoal (Her.rawNativeHerGoal goal))
      "HER actual outcome goal differs from retained schedule"
    require
      (steps >= 0 && steps <= 6 && distance >= 0 && distance <= 6)
      "HER actual count is outside canonical scope"
    consumed <- exact steps (Her.nativeHerOutcomeConsumedActions value)
    require (consumed == take steps actions) "HER consumed action prefix differs"
    pure
      ( BS.singleton (fromIntegral ordinal)
          <> vectorBytes state
          <> BS.singleton (boolean (Her.nativeHerOutcomeSuccess value))
          <> Wire.word64Bytes (castDoubleToWord64 (Her.nativeHerOutcomeNormalizedDistance value))
          <> BS.pack [fromIntegral distance, fromIntegral steps, boolean (Her.nativeHerOutcomeTerminated value)]
      )
  extremaData sequences value = do
    let ids = Map.fromList (zip (fmap Her.nativeHerSequenceId sequences) [0 :: Int ..])
        locate label = case Map.lookup label ids of
          Nothing -> Left (Malformed "HER extrema sequence is outside full enumeration")
          Just ordinal -> Right ordinal
        encodeIds names = do
          _ <- boundedLength AggregateSequenceElements 46656 names
          indices <- traverse locate names
          require (strictAscending indices) "HER extrema IDs are duplicated or out of order"
          pure (list (fmap signed indices))
    success <- word (toInteger (Her.nativeHerMaximumSuccessCount value))
    successes <- encodeIds (Her.nativeHerMaximumSuccessSequenceIds value)
    distance <- rational (Her.nativeHerMinimumExactMeanDistance value)
    distances <- encodeIds (Her.nativeHerMinimumDistanceSequenceIds value)
    pure (array [success, successes, distance, distances])
  boolean value = if value then 1 else 0
  sameVector a b =
    VU.length a == VU.length b
      && VU.ifoldl' (\ok i x -> ok && castDoubleToWord64 x == castDoubleToWord64 (b VU.! i)) True a

vectorBytes :: VU.Vector Double -> ByteString
vectorBytes =
  LBS.toStrict
    . Builder.toLazyByteString
    . VU.foldl' (\builder value -> builder <> Builder.word64BE (castDoubleToWord64 value)) mempty

-- Keep the total base-only tail operation.
{- HLINT ignore strictAscending "Use drop1" -}
strictAscending :: (Ord a) => [a] -> Bool
strictAscending values = and (zipWith (<) values (drop 1 values))

encodeArenaBody
  :: ReferenceDimensions -> Arena.NativeArenaReferenceSet -> Either CodecError ByteString
encodeArenaBody (ArenaDimensions actions horizon tapeBytes) actual = do
  require
    ( actions > 0
        && actions <= 225
        && horizon > 0
        && horizon <= 225
        && tapeBytes > 0
        && tapeBytes <= 262144
    )
    "arena encoding dimensions exceed scope"
  let stateUpper = 128 + 9 * (2 * toInteger horizon + 1)
      decisionUpper = 3 * stateUpper + 17 * toInteger actions + 256
      episodeUpper = 2 * stateUpper + toInteger horizon * decisionUpper + 128
  shapeBound (2 * (9 * episodeUpper + toInteger tapeBytes + 4096) + toInteger tapeBytes + 65536)
  refs <- exact 2 (Arena.nativeArenaObservedReferences actual)
  require
    (fmap Arena.nativeArenaObservedReference refs == [Arena.PlainLegalUniform, Arena.NeutralLegalMcts])
    "arena reference order differs"
  records <- traverse observation refs
  transitions <- word (Arena.nativeArenaTotalEvaluationTransitions actual)
  visits <- word (Arena.nativeArenaTotalSearchRootVisits actual)
  finish (array [list records, transitions, visits])
 where
  observation value = do
    let tape = Tape.arenaTapeBytes (Arena.nativeArenaObservedTape value)
    require (BS.length tape == tapeBytes) "arena actual tape length differs"
    episodes <- exact 9 (Arena.nativeArenaObservedEpisodes value)
    encoded <- traverse episode (zip [0 ..] episodes)
    counts <-
      traverse
        (word . toInteger)
        [ Arena.nativeArenaObservedWins value
        , Arena.nativeArenaObservedDraws value
        , Arena.nativeArenaObservedLosses value
        ]
    score <- rational (Arena.nativeArenaObservedExactScore value)
    transitions <- word (Arena.nativeArenaObservedEvaluationTransitions value)
    visits <- word (Arena.nativeArenaObservedSearchRootVisits value)
    pure
      ( array
          ( [ CBOR.encodeWord64
                (if Arena.nativeArenaObservedReference value == Arena.PlainLegalUniform then 0 else 1)
            , blob tape
            , list encoded
            ]
              <> counts
              <> [bits (Arena.nativeArenaObservedScore value), score, transitions, visits]
          )
      )
  episode (ordinal, value) = do
    require (Arena.nativeArenaEpisodeId value == ordinal) "arena episode order differs"
    initial <- state (Arena.nativeArenaEpisodeInitialState value)
    final <- state (Arena.nativeArenaEpisodeFinalState value)
    decisions <- bounded horizon (Arena.nativeArenaEpisodeDecisions value) >>= traverse decision
    pure
      ( array
          [ signed ordinal
          , initial
          , final
          , outcome (Arena.nativeArenaEpisodeRuleOutcome value)
          , outcome (Arena.nativeArenaEpisodeScoredOutcome value)
          , CBOR.encodeBool (Arena.nativeArenaEpisodeHorizonTruncated value)
          , list decisions
          ]
      )
  decision value = do
    raw <- state (Arena.nativeArenaDecisionRawState value)
    normalized <- state (Arena.nativeArenaDecisionNormalizedState value)
    post <- state (Arena.nativeArenaDecisionPostState value)
    legal <- bounded actions (Arena.nativeArenaDecisionLegalActions value)
    let distribution = Arena.nativeArenaDecisionDistribution value
    require (VU.length distribution == actions) "arena actual distribution width differs"
    pure
      ( array
          [ signed (Arena.nativeArenaDecisionSlot value)
          , raw
          , normalized
          , CBOR.encodeBool (Arena.nativeArenaDecisionForcedPass value)
          , signed (Arena.nativeArenaDecisionPlayer value)
          , list (fmap signed legal)
          , blob (vectorBytes distribution)
          , signed (Arena.nativeArenaDecisionAction value)
          , entry (Arena.nativeArenaDecisionTapeEntry value)
          , signed (Arena.nativeArenaDecisionSearchRootVisits value)
          , post
          , outcome (Arena.nativeArenaDecisionPostOutcome value)
          ]
      )
  state value = do
    history <- bounded (2 * horizon + 1) (Game.gameMoves value)
    require
      (BS.length (UTF8.encodeUtf8 (Game.gameName value)) <= 16)
      "arena actual state name exceeds canonical scope"
    pure
      ( array
          [ CBOR.encodeString (Game.gameName value)
          , list (fmap signed history)
          , signed (Game.gameCurrentPlayer value)
          ]
      )
  entry value =
    array
      [ CBOR.encodeWord64 (Tape.arenaEntryGame value)
      , CBOR.encodeWord64 (Tape.arenaEntrySlot value)
      , signed (Tape.arenaEntrySignedPlayer value)
      , CBOR.encodeWord64 (Tape.arenaEntrySideCode value)
      , CBOR.encodeWord64 (Tape.arenaEntryQ value)
      , bits (Tape.arenaEntryUnit value)
      , signed (Tape.arenaEntryMctsSeed value)
      ]
  outcome value = case value of
    Game.GameInProgress -> array [CBOR.encodeWord64 0]
    Game.GameDraw -> array [CBOR.encodeWord64 1]
    Game.GameWon player -> array [CBOR.encodeWord64 2, signed player]
encodeArenaBody _ _ = Left (Malformed "arena dimensions differ")

bounded :: Int -> [a] -> Either CodecError [a]
bounded cap values = boundedLength AggregateSequenceElements (toInteger cap) values >> pure values

-- Parsers inspect and discard bounded tuples. The returned DATA document keeps
-- exact canonical body bytes, avoiding an expanded copy of933120 HER outcomes.
validateBody :: ReferenceDimensions -> ByteString -> Either CodecError ()
validateBody dimensions bytes = do
  case dimensions of
    ReturnDimensions n c h ->
      require (n > 0 && n <= 720 && c == 20 && h > 0 && h <= 1000) "RETURN parser dimensions exceed scope"
    HerDimensions -> pure ()
    ArenaDimensions a h t ->
      require
        (a > 0 && a <= 225 && h > 0 && h <= 225 && t > 0 && t <= 262144)
        "arena parser dimensions exceed scope"
  when
    (toInteger (BS.length bytes) > bodyLimit)
    (Left (ResourceExceeded WholePayloadBytes bodyLimit (toInteger (BS.length bytes))))
  Wire.runParser
    ( case dimensions of
        ReturnDimensions n c h -> parseReturn n c h
        HerDimensions -> parseHer
        ArenaDimensions a h t -> parseArena a h t
    )
    bytes

parseRational :: Wire.Parser ()
parseRational = do
  Wire.expectList 3
  negative <- Wire.getBool
  n <- Wire.getBytes GeneralTextBytes 272
  d <- Wire.getBytes GeneralTextBytes 272
  let integer = BS.foldl' (\accumulator octet -> accumulator * 256 + toInteger octet) 0
      a = integer n
      b = integer d
      minimal x = BS.null x || BS.head x /= 0
  Wire.liftEither
    ( require
        (minimal n && minimal d && b > 0 && gcd a b == 1 && (not (BS.null n) || not negative))
        "noncanonical reference rational"
    )
parseExactList :: Int -> Wire.Parser () -> Wire.Parser ()
parseExactList n action = expectCount n >> replicateM_ n action
expectCount :: Int -> Wire.Parser ()
expectCount expected = do
  actual <- Wire.getListLength AggregateSequenceElements (toInteger expected)
  Wire.liftEither (require (actual == expected) "reference list has wrong complete cardinality")
parseCount :: Int -> Wire.Parser Int
parseCount cap = do
  n <- Wire.getWord
  if toInteger n <= toInteger cap
    then pure (fromIntegral n)
    else Wire.parserFailure (ResourceExceeded AggregateSequenceElements (toInteger cap) (toInteger n))
parseReturn :: Int -> Int -> Int -> Wire.Parser ()
parseReturn controls cases horizon = do
  Wire.expectList 2
  parseExactList controls $ do
    Wire.expectList 4
    n <- Wire.getListLength SequenceFanout 3
    tag <- Wire.getWord
    case (tag, n) of
      (0, 2) -> void Wire.getInt64
      (1, 2) -> do
        count <- Wire.getListLength SequenceFanout 6
        replicateM_ count (void Wire.getInt64)
      (2, 3) -> do
        control <- Wire.getWord
        Wire.liftEither (require (control <= 2) "unknown continuous reference kind")
        void Wire.getBits
      _ -> Wire.parserFailure (Malformed "unknown reference controller/arity")
    Wire.expectList cases
    mapM_
      ( \ordinal -> do
          Wire.expectList 4
          actual <- Wire.getInt64
          Wire.liftEither (require (actual == fromIntegral ordinal) "reference episode IDs differ")
          _ <- Wire.getBits
          steps <- Wire.getInt64
          Wire.liftEither
            (require (steps >= 0 && toInteger steps <= toInteger horizon) "reference steps exceed horizon")
          void Wire.getBool
      )
      [0 .. cases - 1]
    _ <- Wire.getWord
    parseRational
  void Wire.getWord
parseHer :: Wire.Parser ()
parseHer = do
  Wire.expectList 3
  expectCount 46656
  mapM_
    ( \ordinal -> do
        Wire.expectList 5
        actual <- Wire.getInt64
        Wire.liftEither (require (actual == fromIntegral ordinal) "HER sequence ordinals differ")
        packed <- Wire.getBytes WholePayloadBytes 1220
        Wire.liftEither (require (BS.length packed == 1220) "HER complete outcome pack must be1220 bytes")
        mapM_
          ( \i -> do
              let offset = i * 61
              Wire.liftEither
                ( require
                    ( BS.index packed offset == fromIntegral i
                        && BS.index packed (offset + 49) <= 1
                        && BS.index packed (offset + 58) <= 6
                        && BS.index packed (offset + 59) <= 6
                        && BS.index packed (offset + 60) <= 1
                    )
                    "HER outcome pack flags/counts differ"
                )
          )
          [0 .. 19]
        _ <- parseCount 20
        parseRational
        void Wire.getWord
    )
    [0 :: Int .. 46655]
  Wire.expectList 4
  _ <- parseCount 20
  ids
  parseRational
  ids
  void Wire.getWord
 where
  ids = do
    count <- Wire.getListLength AggregateSequenceElements 46656
    let loop 0 _ = pure ()
        loop remaining previous = do
          ordinal <- Wire.getInt64
          Wire.liftEither
            ( require
                (ordinal >= 0 && ordinal < 46656 && maybe True (< ordinal) previous)
                "HER extrema indices differ"
            )
          loop (remaining - 1) (Just ordinal)
    loop count Nothing
parseArena :: Int -> Int -> Int -> Wire.Parser ()
parseArena actions horizon tapeBytes = do
  Wire.expectList 3
  Wire.expectList 2
  mapM_
    ( \reference -> do
        Wire.expectList 10
        actual <- Wire.getWord
        Wire.liftEither (require (actual == reference) "arena reference tags differ")
        tape <- Wire.getBytes WholePayloadBytes (toInteger tapeBytes)
        Wire.liftEither (require (BS.length tape == tapeBytes) "arena tape bytes differ")
        Wire.expectList 9
        mapM_
          ( \ordinal -> do
              Wire.expectList 7
              actualEpisode <- Wire.getInt64
              Wire.liftEither (require (actualEpisode == fromIntegral ordinal) "arena episode IDs differ")
              state
              state
              outcome
              outcome
              _ <- Wire.getBool
              count <- Wire.getListLength AggregateSequenceElements (toInteger horizon)
              replicateM_ count decision
          )
          [0 :: Int .. 8]
        replicateM_ 3 (void (parseCount 9))
        _ <- Wire.getBits
        parseRational
        _ <- Wire.getWord
        _ <- Wire.getWord
        pure ()
    )
    [0, 1]
  _ <- Wire.getWord
  _ <- Wire.getWord
  pure ()
 where
  state = do
    Wire.expectList 3
    _ <- Wire.getText GeneralTextBytes 16
    count <- Wire.getListLength AggregateSequenceElements (toInteger (2 * horizon + 1))
    replicateM_ count (void Wire.getInt64)
    void Wire.getInt64
  outcome = do
    n <- Wire.getListLength SequenceFanout 2
    tag <- Wire.getWord
    case (tag, n) of
      (0, 1) -> pure ()
      (1, 1) -> pure ()
      (2, 2) -> void Wire.getInt64
      _ -> Wire.parserFailure (Malformed "unknown arena outcome/arity")
  decision = do
    Wire.expectList 12
    _ <- Wire.getInt64
    state
    state
    _ <- Wire.getBool
    _ <- Wire.getInt64
    count <- Wire.getListLength AggregateSequenceElements (toInteger actions)
    replicateM_ count (void Wire.getInt64)
    distribution <- Wire.getBytes WholePayloadBytes (8 * toInteger actions)
    Wire.liftEither
      (require (BS.length distribution == 8 * actions) "arena distribution byte width differs")
    _ <- Wire.getInt64
    Wire.expectList 7
    _ <- Wire.getWord
    _ <- Wire.getWord
    _ <- Wire.getInt64
    _ <- Wire.getWord
    _ <- Wire.getWord
    _ <- Wire.getBits
    _ <- Wire.getInt64
    _ <- Wire.getInt64
    state
    outcome
