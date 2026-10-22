{-# LANGUAGE OverloadedStrings #-}

-- | Prospective addressed arena variates, with no provider, training, policy,
-- row-allocation or durable-publication authority. Existing arenas do not use
-- this module until a separately reviewed recipe integration is adopted.
module JitML.RL.AlphaZero.ArenaTape
  ( ArenaTapeSpec
  , ArenaTape
  , ArenaTapeEntry
  , ArenaTapeError (..)
  , ArenaTapeBound (..)
  , arenaTapeProtocol
  , arenaScheduleProtocol
  , mkArenaTapeSpec
  , arenaTapeSpecRow
  , arenaTapeSpecBase
  , arenaTapeSpecGames
  , arenaTapeSpecMaxPlies
  , arenaTapeSpecEntryCount
  , arenaTapeSpecEncodedLength
  , materializeArenaTape
  , arenaTapeSpec
  , arenaTapeEntries
  , arenaTapeBytes
  , arenaTapeSha256
  , arenaTapeLookup
  , arenaTapeDigestInput
  , arenaUnitFromQ
  , decodeArenaTape
  , verifyArenaTape
  , arenaEntryGame
  , arenaEntrySlot
  , arenaEntrySignedPlayer
  , arenaEntrySideCode
  , arenaEntryQ
  , arenaEntryUnit
  , arenaEntryMctsSeed
  ) where

import Control.Monad (unless, when)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.Bits (shiftL, shiftR, (.|.))
import Data.ByteString qualified as BS
import Data.ByteString.Builder qualified as Builder
import Data.ByteString.Lazy qualified as LBS
import Data.Char (intToDigit)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Encoding
import Data.Vector qualified as V
import Data.Word (Word64)

arenaTapeProtocol :: Text
arenaTapeProtocol = "jitml-native-arena-tape-v1"

-- This is the durable schedule encoding, not the per-address digest input.
arenaScheduleProtocol :: Text
arenaScheduleProtocol = "jitml-native-arena-schedule-v1"

data ArenaTapeBound = BaseSeed | Games | MaxPlies | MctsSeed | EntryCount | ScheduleBytes
  deriving stock (Eq, Show)

data ArenaTapeError
  = EmptyRowIdentity
  | NonPositiveGames
  | NonPositiveMaxPlies
  | BoundExceeded !ArenaTapeBound !Integer !Integer
  | InvalidSignedPlayer !Int
  | AddressOutOfBounds !Word64 !Word64
  | QOutOfRange !Word64
  | InvalidScheduleEncoding !Text
  | ScheduleDescriptorMismatch
  | SchedulePayloadMismatch
  deriving stock (Eq, Show)

-- Private constructors and internal labels; exported observers are ordinary
-- functions, so external record updates cannot bypass the arithmetic checks.
data ArenaTapeSpec = ArenaTapeSpec !Text !Word64 !Word64 !Word64 !Int !Int
  deriving stock (Eq, Show)

data ArenaTapeEntry = ArenaTapeEntry !Word64 !Word64 !Int !Word64 !Word64 !Double !Int
  deriving stock (Eq, Show)

data ArenaTape = ArenaTape !ArenaTapeSpec !(V.Vector ArenaTapeEntry) !BS.ByteString !Text
  deriving stock (Eq, Show)

-- Check all declared dimensions, maximal addressed MCTS arithmetic, and full
-- schedule/index lengths using Integer before any actual Int use/allocation.
-- This is representation safety; it does not promise available RAM or runtime.
mkArenaTapeSpec :: Text -> Word64 -> Word64 -> Word64 -> Either ArenaTapeError ArenaTapeSpec
mkArenaTapeSpec row base games maxPlies = do
  when (Text.null row) (Left EmptyRowIdentity)
  unless (games > 0) (Left NonPositiveGames)
  unless (maxPlies > 0) (Left NonPositiveMaxPlies)
  checkBoth BaseSeed (toInteger base)
  checkBoth Games (toInteger games)
  checkBoth MaxPlies (toInteger maxPlies)
  checkBoth MctsSeed (toInteger base + (toInteger games - 1) * 1009 + (toInteger maxPlies - 1) * 7919)
  let count = 2 * toInteger games * toInteger maxPlies
      -- magic+NUL, row-length+UTF8, base/games/plies/count, then 48-byte entries.
      size =
        toInteger (BS.length scheduleMagic)
          + 8
          + toInteger (BS.length (Encoding.encodeUtf8 row))
          + 32
          + 48 * count
  checkBoth EntryCount count
  checkBoth ScheduleBytes size
  pure (ArenaTapeSpec row base games maxPlies (fromInteger count) (fromInteger size))
 where
  checkBoth bound value = do
    check bound (toInteger (maxBound :: Word64)) value
    check bound (toInteger (maxBound :: Int)) value
  check bound limit value = unless (value <= limit) (Left (BoundExceeded bound value limit))

arenaTapeSpecRow :: ArenaTapeSpec -> Text
arenaTapeSpecRow (ArenaTapeSpec row _ _ _ _ _) = row
arenaTapeSpecBase :: ArenaTapeSpec -> Word64
arenaTapeSpecBase (ArenaTapeSpec _ base _ _ _ _) = base
arenaTapeSpecGames :: ArenaTapeSpec -> Word64
arenaTapeSpecGames (ArenaTapeSpec _ _ games _ _ _) = games
arenaTapeSpecMaxPlies :: ArenaTapeSpec -> Word64
arenaTapeSpecMaxPlies (ArenaTapeSpec _ _ _ plies _ _) = plies
arenaTapeSpecEntryCount :: ArenaTapeSpec -> Int
arenaTapeSpecEntryCount (ArenaTapeSpec _ _ _ _ count _) = count
arenaTapeSpecEncodedLength :: ArenaTapeSpec -> Int
arenaTapeSpecEncodedLength (ArenaTapeSpec _ _ _ _ _ size) = size

arenaTapeSpec :: ArenaTape -> ArenaTapeSpec
arenaTapeSpec (ArenaTape spec _ _ _) = spec
arenaTapeEntries :: ArenaTape -> V.Vector ArenaTapeEntry
arenaTapeEntries (ArenaTape _ entries _ _) = entries
arenaTapeBytes :: ArenaTape -> BS.ByteString
arenaTapeBytes (ArenaTape _ _ bytes _) = bytes
arenaTapeSha256 :: ArenaTape -> Text
arenaTapeSha256 (ArenaTape _ _ _ digest) = digest
arenaEntryGame :: ArenaTapeEntry -> Word64
arenaEntryGame (ArenaTapeEntry game _ _ _ _ _ _) = game
arenaEntrySlot :: ArenaTapeEntry -> Word64
arenaEntrySlot (ArenaTapeEntry _ slot _ _ _ _ _) = slot
arenaEntrySignedPlayer :: ArenaTapeEntry -> Int
arenaEntrySignedPlayer (ArenaTapeEntry _ _ signed _ _ _ _) = signed
arenaEntrySideCode :: ArenaTapeEntry -> Word64
arenaEntrySideCode (ArenaTapeEntry _ _ _ side _ _ _) = side
arenaEntryQ :: ArenaTapeEntry -> Word64
arenaEntryQ (ArenaTapeEntry _ _ _ _ q _ _) = q
arenaEntryUnit :: ArenaTapeEntry -> Double
arenaEntryUnit (ArenaTapeEntry _ _ _ _ _ u _) = u
arenaEntryMctsSeed :: ArenaTapeEntry -> Int
arenaEntryMctsSeed (ArenaTapeEntry _ _ _ _ _ _ seed) = seed

sideCode :: Int -> Either ArenaTapeError Word64
sideCode signed = case signed of
  1 -> Right 1
  -1 -> Right 2
  _ -> Left (InvalidSignedPlayer signed)

checkedAddress :: ArenaTapeSpec -> Word64 -> Word64 -> Int -> Either ArenaTapeError Word64
checkedAddress spec game slot signed = do
  side <- sideCode signed
  unless
    (game < arenaTapeSpecGames spec && slot < arenaTapeSpecMaxPlies spec)
    (Left (AddressOutOfBounds game slot))
  pure side

-- Exact b6dd digest input, deliberately distinct from the complete schedule:
-- ASCII domain+NUL; UTF8 byte length/u64BE+row bytes; base/game/slot/side u64BE.
arenaTapeDigestInput
  :: ArenaTapeSpec -> Word64 -> Word64 -> Int -> Either ArenaTapeError BS.ByteString
arenaTapeDigestInput spec game slot signed = do
  side <- checkedAddress spec game slot signed
  pure $
    strictBuilder $
      Builder.byteString tapeMagic
        <> rowBuilder (arenaTapeSpecRow spec)
        <> Builder.word64BE (arenaTapeSpecBase spec)
        <> Builder.word64BE game
        <> Builder.word64BE slot
        <> Builder.word64BE side

arenaUnitFromQ :: Word64 -> Either ArenaTapeError Double
arenaUnitFromQ q
  | q >= 9007199254740992 = Left (QOutOfRange q)
  -- Every permitted integer is represented exactly; division by 2^53 is exact
  -- binary64 scaling. No Int cast, modulo or platform RNG participates.
  | otherwise = Right (fromIntegral q / 9007199254740992.0)

materializeArenaTape :: ArenaTapeSpec -> ArenaTape
materializeArenaTape spec =
  let entries =
        V.fromList
          [ entry game slot signed side
          | game <- [0 .. arenaTapeSpecGames spec - 1]
          , slot <- [0 .. arenaTapeSpecMaxPlies spec - 1]
          , (signed, side) <- [(1, 1), (-1, 2)]
          ]
      bytes =
        strictBuilder $
          Builder.byteString scheduleMagic
            <> rowBuilder (arenaTapeSpecRow spec)
            <> Builder.word64BE (arenaTapeSpecBase spec)
            <> Builder.word64BE (arenaTapeSpecGames spec)
            <> Builder.word64BE (arenaTapeSpecMaxPlies spec)
            <> Builder.word64BE (fromIntegral (arenaTapeSpecEntryCount spec))
            <> foldMap encodeEntry entries
      digest = hex (SHA256.hash bytes)
   in ArenaTape spec entries bytes digest
 where
  entry game slot signed side =
    -- The checked spec and this bounded enumeration already establish these
    -- conditions. Keep all arithmetic in Integer until the proven Int cast.
    let input =
          strictBuilder $
            Builder.byteString tapeMagic
              <> rowBuilder (arenaTapeSpecRow spec)
              <> Builder.word64BE (arenaTapeSpecBase spec)
              <> Builder.word64BE game
              <> Builder.word64BE slot
              <> Builder.word64BE side
        q = unsignedFirstEight (SHA256.hash input) `shiftR` 11
        u = fromIntegral q / 9007199254740992.0
        seed = fromInteger (toInteger (arenaTapeSpecBase spec) + toInteger game * 1009 + toInteger slot * 7919)
     in ArenaTapeEntry game slot signed side q u seed

arenaTapeLookup :: ArenaTape -> Word64 -> Word64 -> Int -> Either ArenaTapeError ArenaTapeEntry
arenaTapeLookup tape game slot signed = do
  let spec = arenaTapeSpec tape
  side <- checkedAddress spec game slot signed
  let index =
        (toInteger game * toInteger (arenaTapeSpecMaxPlies spec) + toInteger slot) * 2 + toInteger side - 1
  -- checkedAddress+spec entry-count bounds prove index fits actual Int.
  case arenaTapeEntries tape V.!? fromInteger index of
    Just value -> Right value
    Nothing -> Left (InvalidScheduleEncoding "internal bounded tape index mismatch")

-- Durable schedule: ASCII schedule-domain+NUL; row length/u64BE+UTF8;
-- base/games/maxPlies/entryCount u64BE; lexicographic game,slot,side(1 then2)
-- entries each game/u64BE,slot/u64BE,signedPlayer/i64BE,side/u64BE,q/u64BE,
-- MCTSseed/u64BE. The signed player is actual +1/-1, never an Int enum cast.
encodeEntry :: ArenaTapeEntry -> Builder.Builder
encodeEntry entry =
  Builder.word64BE (arenaEntryGame entry)
    <> Builder.word64BE (arenaEntrySlot entry)
    <> Builder.int64BE (fromIntegral (arenaEntrySignedPlayer entry))
    <> Builder.word64BE (arenaEntrySideCode entry)
    <> Builder.word64BE (arenaEntryQ entry)
    <> Builder.word64BE (fromIntegral (arenaEntryMctsSeed entry))

decodeArenaTape :: BS.ByteString -> Either ArenaTapeError ArenaTape
decodeArenaTape bytes = do
  (_, afterMagic) <- takeExact (BS.length scheduleMagic) bytes
  unless
    (BS.take (BS.length scheduleMagic) bytes == scheduleMagic)
    (Left (InvalidScheduleEncoding "wrong schedule domain/version"))
  (rowLength, afterLength) <- takeWord64 afterMagic
  unless
    (toInteger rowLength <= toInteger (maxBound :: Int))
    (Left (InvalidScheduleEncoding "row byte length exceeds actual Int"))
  (rowBytes, afterRow) <- takeExact (fromIntegral rowLength) afterLength
  row <- case Encoding.decodeUtf8' rowBytes of
    Left _ -> Left (InvalidScheduleEncoding "row is not UTF8")
    Right value -> Right value
  (base, afterBase) <- takeWord64 afterRow
  (games, afterGames) <- takeWord64 afterBase
  (plies, afterPlies) <- takeWord64 afterGames
  (declaredCount, _) <- takeWord64 afterPlies
  spec <- mkArenaTapeSpec row base games plies
  unless
    (toInteger declaredCount == toInteger (arenaTapeSpecEntryCount spec))
    (Left (InvalidScheduleEncoding "declared entry count mismatch"))
  unless
    (BS.length bytes == arenaTapeSpecEncodedLength spec)
    (Left (InvalidScheduleEncoding "schedule byte length mismatch"))
  let expected = materializeArenaTape spec
  -- Rederive all q/sides/actual signed players/seeds. No stored q or digest is
  -- trusted, and alternate encodings or trailing bytes cannot be canonical.
  unless (bytes == arenaTapeBytes expected) (Left SchedulePayloadMismatch)
  pure expected

verifyArenaTape :: ArenaTapeSpec -> BS.ByteString -> Either ArenaTapeError ArenaTape
verifyArenaTape expected bytes = do
  observed <- decodeArenaTape bytes
  unless (arenaTapeSpec observed == expected) (Left ScheduleDescriptorMismatch)
  pure observed

rowBuilder :: Text -> Builder.Builder
rowBuilder row =
  let bytes = Encoding.encodeUtf8 row
   in Builder.word64BE (fromIntegral (BS.length bytes)) <> Builder.byteString bytes

strictBuilder :: Builder.Builder -> BS.ByteString
strictBuilder = LBS.toStrict . Builder.toLazyByteString

tapeMagic, scheduleMagic :: BS.ByteString
tapeMagic = Encoding.encodeUtf8 arenaTapeProtocol <> BS.singleton 0
scheduleMagic = Encoding.encodeUtf8 arenaScheduleProtocol <> BS.singleton 0

unsignedFirstEight :: BS.ByteString -> Word64
unsignedFirstEight = BS.foldl' (\value byte -> (value `shiftL` 8) .|. fromIntegral byte) 0 . BS.take 8

takeWord64 :: BS.ByteString -> Either ArenaTapeError (Word64, BS.ByteString)
takeWord64 bytes = do
  (prefix, rest) <- takeExact 8 bytes
  pure (unsignedFirstEight prefix, rest)

takeExact :: Int -> BS.ByteString -> Either ArenaTapeError (BS.ByteString, BS.ByteString)
takeExact count bytes
  | count < 0 || BS.length bytes < count = Left (InvalidScheduleEncoding "truncated schedule")
  | otherwise = Right (BS.splitAt count bytes)

hex :: BS.ByteString -> Text
hex =
  Text.pack
    . concatMap
      (\byte -> [intToDigit (fromIntegral byte `div` 16), intToDigit (fromIntegral byte `mod` 16)])
    . BS.unpack
