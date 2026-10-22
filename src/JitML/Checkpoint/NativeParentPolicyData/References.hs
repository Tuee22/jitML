{-# LANGUAGE OverloadedStrings #-}

-- | Ordinary retained reference records. No actual calibration is restored.
module JitML.Checkpoint.NativeParentPolicyData.References (returnReferences, arenaReferences, verifyHerReferences) where

import Control.Monad (replicateM, unless)
import Data.Bits (shiftL, (.|.))
import Data.ByteString qualified as BS
import Data.Either.Combinators (mapLeft)
import Data.Ratio ((%))
import Data.Vector.Unboxed qualified as VU
import GHC.Float (castDoubleToWord64, castWord64ToDouble)

import JitML.Checkpoint.NativePhase.CBOR qualified as Wire
import JitML.Checkpoint.NativePhase.Types
import JitML.Checkpoint.NativeReferences qualified as Document
import JitML.RL.AlphaZero qualified as Game
import JitML.RL.AlphaZero.ArenaTape qualified as Tape
import JitML.RL.AlphaZero.NativeArenaReferences qualified as Arena
import JitML.RL.NativeHerReferences qualified as Her
import JitML.RL.NativeReturnReferences qualified as Return

signed :: Wire.Parser Int
signed = do
  value <- Wire.getInt64
  unless
    (toInteger value >= toInteger (minBound :: Int) && toInteger value <= toInteger (maxBound :: Int))
    (Wire.parserFailure (Malformed "parent reference integer exceeds this host Int"))
  pure (fromIntegral value)
double :: Wire.Parser Double
double = castWord64ToDouble <$> Wire.getBits
natural :: Wire.Parser Integer
natural = toInteger <$> Wire.getWord
ratio :: Wire.Parser Rational
ratio = do
  Wire.expectList 3
  negative <- Wire.getBool
  a <- Wire.getBytes GeneralTextBytes 272
  b <- Wire.getBytes GeneralTextBytes 272
  let integer = BS.foldl' (\x y -> 256 * x + toInteger y) 0
      n = integer a
      d = integer b
  unless
    ( (BS.null a || BS.head a /= 0)
        && not (BS.null b)
        && BS.head b /= 0
        && d > 0
        && gcd n d == 1
        && (not negative || n > 0)
    )
    (Wire.parserFailure (NonCanonical "parent reference rational is not minimal"))
  pure ((if negative then negate n else n) % d)

-- The exact encoder compares EVERY retained field, including the stored exact
-- median that the public reference record derives rather than stores itself.
returnReferences
  :: Return.NativeReturnReferenceSpec
  -> Document.NativeReferenceData
  -> Either CodecError Return.NativeReturnReferenceSet
returnReferences spec document = do
  unless
    (Document.nativeReferenceDataFamily document == Document.ReturnReferenceFamily)
    (Left (Malformed "parent RETURN reference family differs"))
  actual <- Wire.runParser parser (Document.nativeReferenceDataBody document)
  encoded <-
    Document.encodeNativeReturnReferencesData
      (Document.nativeReferenceDataCohortId document)
      (Document.nativeReferenceDataCohortTransport document)
      (Document.nativeReferenceDataSpecRoot document)
      (Document.nativeReferenceDataSpecPool document)
      actual
  unless
    (Document.nativeReferenceDataBytes encoded == Document.nativeReferenceDataBytes document)
    (Left (Malformed "parent RETURN lossless reference re-encoding differs"))
  replayed <- mapLeft Malformed (Return.evaluateCanonicalNativeReturnReferences spec)
  replayedBytes <-
    Document.encodeNativeReturnReferencesData
      (Document.nativeReferenceDataCohortId document)
      (Document.nativeReferenceDataCohortTransport document)
      (Document.nativeReferenceDataSpecRoot document)
      (Document.nativeReferenceDataSpecPool document)
      replayed
  unless
    (Document.nativeReferenceDataBytes replayedBytes == Document.nativeReferenceDataBytes document)
    ( Left
        (Malformed "parent RETURN complete fixed references differ from current public simulator replay")
    )
  pure actual
 where
  parser = do
    Wire.expectList 2
    count <- Wire.getListLength AggregateSequenceElements 720
    Wire.ensureMinimumItems (fromIntegral count) 10
    rows <- replicateM count $ do
      Wire.expectList 4
      controller <- control
      Wire.expectList 20
      episodes <-
        replicateM
          20
          (Wire.expectList 4 >> (Return.NativeReturnEpisode <$> signed <*> double <*> signed <*> Wire.getBool))
      work <- natural
      _ <- ratio
      pure (Return.NativeReturnReferenceObservation controller episodes work)
    Return.NativeReturnReferenceSet spec rows <$> natural
  control = do
    count <- Wire.getListLength SequenceFanout 3
    tag <- Wire.getWord
    case (tag, count) of
      (0, 2) -> Return.ConstantDiscrete <$> signed
      (1, 2) -> do
        n <- Wire.getListLength SequenceFanout 6
        Return.FixedMaskedPreference <$> replicateM n signed
      (2, 3) -> do
        kind <- Wire.getWord
        selected <- case kind of
          0 -> pure Return.NativeZero
          1 -> pure Return.NativeLowerEndpoint
          2 -> pure Return.NativeUpperEndpoint
          _ -> Wire.parserFailure (Malformed "parent continuous controller tag differs")
        Return.ConstantContinuous selected <$> double
      _ -> Wire.parserFailure (Malformed "parent RETURN controller arity/tag differs")

-- Exact complete public rule enumeration over the RETAINED supplied schedule.
-- No replacement sampler or selected learner seed enters this calculation.
-- Explicit finite cost:46656 sequences x20 cases, up to6 bit transitions each.
verifyHerReferences
  :: Her.NativeHerGoalSchedule
  -> Document.NativeReferenceData
  -> Either CodecError Her.NativeHerReferenceFamily
verifyHerReferences schedule document = do
  unless
    (Document.nativeReferenceDataFamily document == Document.HerReferenceFamily)
    (Left (Malformed "parent HER reference family differs"))
  actual <- mapLeft Malformed (Her.evaluateNativeHerReferenceFamily schedule)
  encoded <-
    Document.encodeNativeHerReferencesData
      (Document.nativeReferenceDataCohortId document)
      (Document.nativeReferenceDataCohortTransport document)
      (Document.nativeReferenceDataSpecRoot document)
      (Document.nativeReferenceDataSpecPool document)
      actual
  unless
    (Document.nativeReferenceDataBytes encoded == Document.nativeReferenceDataBytes document)
    ( Left
        (Malformed "parent HER complete retained reference records differ from exact public rule replay")
    )
  pure actual

arenaReferences
  :: Arena.NativeArenaSpec
  -> Tape.ArenaTape
  -> Document.NativeReferenceData
  -> Either CodecError Arena.NativeArenaReferenceSet
arenaReferences spec tape document = do
  unless
    (Document.nativeReferenceDataFamily document == Document.ArenaReferenceFamily)
    (Left (Malformed "parent arena reference family differs"))
  actual <- Wire.runParser parser (Document.nativeReferenceDataBody document)
  encoded <-
    Document.encodeNativeArenaReferencesData
      (Document.nativeReferenceDataCohortId document)
      (Document.nativeReferenceDataCohortTransport document)
      (Document.nativeReferenceDataSpecRoot document)
      (Document.nativeReferenceDataSpecPool document)
      actual
  unless
    (Document.nativeReferenceDataBytes encoded == Document.nativeReferenceDataBytes document)
    (Left (Malformed "parent arena lossless retained reference re-encoding differs"))
  pure actual
 where
  horizon = Arena.nativeArenaSpecMaxPlies spec
  width = Arena.nativeArenaSpecActionCount spec
  parser = do
    Wire.expectList 3
    Wire.expectList 2
    rows <- traverse observation [Arena.PlainLegalUniform, Arena.NeutralLegalMcts]
    Arena.NativeArenaReferenceSet spec rows <$> natural <*> natural
  observation expected = do
    Wire.expectList 10
    tag <- Wire.getWord
    unless
      (tag == if expected == Arena.PlainLegalUniform then 0 else 1)
      (Wire.parserFailure (Malformed "parent arena reference order differs"))
    bytes <- Wire.getBytes WholePayloadBytes 262144
    unless
      (bytes == Tape.arenaTapeBytes tape)
      (Wire.parserFailure (Malformed "parent arena reference addressed tape differs"))
    Wire.expectList 9
    episodes <- replicateM 9 episode
    Arena.NativeArenaObservation expected tape episodes
      <$> count9
      <*> count9
      <*> count9
      <*> double
      <*> ratio
      <*> natural
      <*> natural
  count9 = do
    n <- Wire.getWord
    if n <= 9
      then pure (fromIntegral n)
      else Wire.parserFailure (Malformed "parent arena WDL exceeds nine")
  episode = do
    Wire.expectList 7
    identity <- signed
    initial <- state
    final <- state
    rule <- gameOutcome
    scored <- gameOutcome
    truncated <- Wire.getBool
    count <- Wire.getListLength AggregateSequenceElements (toInteger horizon)
    Wire.ensureMinimumItems (fromIntegral count) 30
    decisions <- replicateM count decision
    pure (Arena.NativeArenaEpisode identity initial final rule scored truncated decisions)
  state = do
    Wire.expectList 3
    name <- Wire.getText GeneralTextBytes 16
    unless
      (name == Arena.nativeArenaSpecRowId spec)
      (Wire.parserFailure (Malformed "parent arena state game differs"))
    count <- Wire.getListLength AggregateSequenceElements (2 * toInteger horizon + 1)
    history <- replicateM count signed
    Game.GameState name history <$> signed
  gameOutcome = do
    count <- Wire.getListLength SequenceFanout 2
    tag <- Wire.getWord
    case (tag, count) of
      (0, 1) -> pure Game.GameInProgress
      (1, 1) -> pure Game.GameDraw
      (2, 2) -> do
        player <- signed
        if player == 1 || player == -1
          then pure (Game.GameWon player)
          else Wire.parserFailure (Malformed "parent arena winner is invalid")
      _ -> Wire.parserFailure (Malformed "parent arena outcome tag/arity differs")
  decision = do
    Wire.expectList 12
    slot <- signed
    raw <- state
    normalized <- state
    forced <- Wire.getBool
    player <- signed
    count <- Wire.getListLength AggregateSequenceElements (toInteger width)
    legal <- replicateM count signed
    bytes <- Wire.getBytes WholePayloadBytes (8 * toInteger width)
    unless
      (BS.length bytes == 8 * width)
      (Wire.parserFailure (Malformed "parent arena distribution byte width differs"))
    let distribution =
          VU.generate
            width
            ( \i ->
                castWord64ToDouble
                  (BS.foldl' (\a b -> (a `shiftL` 8) .|. fromIntegral b) 0 (BS.take 8 (BS.drop (8 * i) bytes)))
            )
    action <- signed
    entry <- addressed
    visits <- signed
    post <- state
    Arena.NativeArenaDecision
      slot
      raw
      normalized
      forced
      player
      legal
      distribution
      action
      entry
      visits
      post
      <$> gameOutcome
  addressed = do
    Wire.expectList 7
    game <- Wire.getWord
    slot <- Wire.getWord
    player <- signed
    side <- Wire.getWord
    q <- Wire.getWord
    unit <- Wire.getBits
    seed <- signed
    entry <-
      either
        (const (Wire.parserFailure (Malformed "parent arena reference tape address differs")))
        pure
        (Tape.arenaTapeLookup tape game slot player)
    unless
      ( side == Tape.arenaEntrySideCode entry
          && q == Tape.arenaEntryQ entry
          && unit == castDoubleToWord64 (Tape.arenaEntryUnit entry)
          && seed == Tape.arenaEntryMctsSeed entry
      )
      (Wire.parserFailure (Malformed "parent arena reference full tape entry differs"))
    pure entry
