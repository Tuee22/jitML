{-# LANGUAGE OverloadedStrings #-}

module NativeArenaTape (nativeArenaTapeTests) where

import Control.Monad (forM_)
import Data.Bits (xor)
import Data.ByteString qualified as BS
import Data.Ratio ((%))
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Encoding
import Data.Vector qualified as V
import Data.Word (Word64, Word8)
import JitML.Product.ValidationRecord (hexBytes, sha256Hex)
import JitML.RL.AlphaZero.ArenaTape qualified as Tape
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

-- Pure prospective protocol controls. Synthetic consumption is not an actual
-- arena/game rollout, actual signed-player observation, provider or P claim.
nativeArenaTapeTests :: TestTree
nativeArenaTapeTests =
  testGroup
    "native addressed arena tape"
    [ testCase "independent SHA256 byte-encoding known answers bind addresses and signed sides" $
        forM_ knownCases $ \(row, game, slot, signed, inputHex, digest, q, seed) -> do
          spec <- expectRight (Tape.mkArenaTapeSpec row 7961 9 42)
          input <- expectRight (Tape.arenaTapeDigestInput spec game slot signed)
          hexBytes input @?= inputHex
          sha256Hex input @?= digest
          actual <- expectRight (Tape.arenaTapeLookup (Tape.materializeArenaTape spec) game slot signed)
          Tape.arenaEntryQ actual @?= q
          Tape.arenaEntryMctsSeed actual @?= seed
          toRational (Tape.arenaEntryUnit actual) @?= toInteger q % 9007199254740992
    , testCase "UTF8 row byte length is explicit and preserves Unicode without normalization" $ do
        let row = "AlphaZero/棋🙂"
            bytes = Encoding.encodeUtf8 row
        spec <- expectRight (Tape.mkArenaTapeSpec row 7961 2 3)
        input <- expectRight (Tape.arenaTapeDigestInput spec 1 2 (-1))
        BS.length bytes @?= 17
        assertBool "UTF8 length differs from Text character count" (BS.length bytes /= Text.length row)
        BS.take 8 (BS.drop 27 input) @?= BS.pack [0, 0, 0, 0, 0, 0, 0, 17]
        BS.take 17 (BS.drop 35 input) @?= bytes
        Tape.arenaTapeSpecRow spec @?= row
        a <- expectRight (Tape.mkArenaTapeSpec "é" 7961 1 1)
        b <- expectRight (Tape.mkArenaTapeSpec "e\x0301" 7961 1 1)
        left <- expectRight (Tape.arenaTapeDigestInput a 0 0 1)
        right <- expectRight (Tape.arenaTapeDigestInput b 0 0 1)
        assertBool "different exact row bytes remain different" (left /= right)
    , testCase "actual signed players map only plus one to side one and minus one to side two" $ do
        spec <- smallSpec
        let tape = Tape.materializeArenaTape spec
        positive <- expectRight (Tape.arenaTapeLookup tape 0 0 1)
        negative <- expectRight (Tape.arenaTapeLookup tape 0 0 (-1))
        (Tape.arenaEntrySignedPlayer positive, Tape.arenaEntrySideCode positive) @?= (1, 1)
        (Tape.arenaEntrySignedPlayer negative, Tape.arenaEntrySideCode negative) @?= (-1, 2)
        forM_ [0, 2, -2, minBound, maxBound] $ \signed -> do
          Tape.arenaTapeLookup tape 0 0 signed @?= Left (Tape.InvalidSignedPlayer signed)
          Tape.arenaTapeDigestInput spec 0 0 signed @?= Left (Tape.InvalidSignedPlayer signed)
    , testCase "q scaling is exact binary64 in the half open unit interval" $ do
        forM_ [0, 1, 2, 4503599627370495, 4503599627370496, 9007199254740991] $ \q -> do
          u <- expectRight (Tape.arenaUnitFromQ q)
          assertBool "finite half-open uniform variate" (not (isNaN u || isInfinite u) && u >= 0 && u < 1)
          toRational u @?= toInteger q % 9007199254740992
        Tape.arenaUnitFromQ 0 @?= Right 0
        Tape.arenaUnitFromQ 9007199254740991 @?= Right (1 - (1 / 9007199254740992))
        forM_ [9007199254740992, maxBound] $ \q -> Tape.arenaUnitFromQ q @?= Left (Tape.QOutOfRange q)
    , testCase "complete ordering lookup q and MCTS seeds cover every declared slot and both sides" $ do
        spec <- expectRight (Tape.mkArenaTapeSpec "fixture/complete" 7961 3 5)
        let tape = Tape.materializeArenaTape spec
            entries = V.toList (Tape.arenaTapeEntries tape)
        Tape.arenaTapeSpecEntryCount spec @?= 30
        length entries @?= 30
        [(Tape.arenaEntryGame e, Tape.arenaEntrySlot e, Tape.arenaEntrySignedPlayer e) | e <- entries]
          @?= [(game, slot, signed) | game <- [0 .. 2], slot <- [0 .. 4], signed <- [1, -1]]
        forM_ entries $ \entry -> do
          found <-
            expectRight
              ( Tape.arenaTapeLookup
                  tape
                  (Tape.arenaEntryGame entry)
                  (Tape.arenaEntrySlot entry)
                  (Tape.arenaEntrySignedPlayer entry)
              )
          found @?= entry
          Tape.arenaEntryMctsSeed entry @?= 7961
            + fromIntegral (Tape.arenaEntryGame entry) * 1009
            + fromIntegral (Tape.arenaEntrySlot entry) * 7919
          assertBool "every addressed q is bounded" (Tape.arenaEntryQ entry < 9007199254740992)
          toRational (Tape.arenaEntryUnit entry) @?= toInteger (Tape.arenaEntryQ entry) % 9007199254740992
    , testCase "out of range unsigned addresses fail before any Int lookup cast" $ do
        spec <- smallSpec
        let tape = Tape.materializeArenaTape spec
        forM_ [(2, 0), (0, 2), (maxBound, 0), (0, maxBound)] $ \(game, slot) -> do
          Tape.arenaTapeLookup tape game slot 1 @?= Left (Tape.AddressOutOfBounds game slot)
          Tape.arenaTapeDigestInput spec game slot 1 @?= Left (Tape.AddressOutOfBounds game slot)
    , testCase "spec checks actual host Int and unsigned MCTS arithmetic before use" $ do
        Tape.mkArenaTapeSpec "" 0 1 1 @?= Left Tape.EmptyRowIdentity
        Tape.mkArenaTapeSpec "row" 0 0 1 @?= Left Tape.NonPositiveGames
        Tape.mkArenaTapeSpec "row" 0 1 0 @?= Left Tape.NonPositiveMaxPlies
        let host = toInteger (maxBound :: Int)
            unsigned = toInteger (maxBound :: Word64)
            over = fromInteger (host + 1)
        Tape.mkArenaTapeSpec "row" over 1 1 @?= Left (Tape.BoundExceeded Tape.BaseSeed (host + 1) host)
        Tape.mkArenaTapeSpec "row" 0 over 1 @?= Left (Tape.BoundExceeded Tape.Games (host + 1) host)
        Tape.mkArenaTapeSpec "row" 0 1 over @?= Left (Tape.BoundExceeded Tape.MaxPlies (host + 1) host)
        edge <- expectRight (Tape.mkArenaTapeSpec "row" (fromInteger (host - 7919)) 1 2)
        lastEntry <- expectRight (Tape.arenaTapeLookup (Tape.materializeArenaTape edge) 0 1 (-1))
        Tape.arenaEntryMctsSeed lastEntry @?= maxBound
        Tape.mkArenaTapeSpec "row" (fromInteger (host - 7918)) 1 2
          @?= Left (Tape.BoundExceeded Tape.MctsSeed (host + 1) host)
        let maximumSeed = (host - 1) * 1009
            firstExceeded = if maximumSeed > unsigned then unsigned else host
        Tape.mkArenaTapeSpec "row" 0 (fromInteger host) 1
          @?= Left (Tape.BoundExceeded Tape.MctsSeed maximumSeed firstExceeded)
    , testCase "complete entry and byte lengths reject representational overflow without allocation" $ do
        let host = toInteger (maxBound :: Int)
            games = 1000000
            countPlies = host `div` (2 * games) + 1
            count = 2 * games * countPlies
            bytePlies = host `div` (96 * games) + 1
            byteCount = 2 * games * bytePlies
            prefix = 31 + 8 + 3 + 32
        Tape.mkArenaTapeSpec "row" 0 (fromInteger games) (fromInteger countPlies)
          @?= Left (Tape.BoundExceeded Tape.EntryCount count host)
        Tape.mkArenaTapeSpec "row" 0 (fromInteger games) (fromInteger bytePlies)
          @?= Left (Tape.BoundExceeded Tape.ScheduleBytes (prefix + 48 * byteCount) host)
    , testCase "different length synthetic early games cannot shift any later input slot" $ do
        spec <- expectRight (Tape.mkArenaTapeSpec "fixture/lengths" 7961 3 5)
        let tape = Tape.materializeArenaTape spec
            trace count =
              mapM
                (\(game, slot, signed) -> Tape.arenaTapeLookup tape game slot signed)
                ([(0, slot, if even slot then 1 else -1) | slot <- [0 .. count - 1]] <> [(2, 3, -1)])
        short <- expectRight (trace 1)
        long <- expectRight (trace 4)
        length short @?= 2
        length long @?= 5
        -- Real public lookups consume different synthetic request prefixes.
        -- There are no arena/game outcomes or actual side-to-move claims here.
        let afterShort = last short
            afterLong = last long
        afterShort @?= afterLong
        Tape.arenaEntryQ afterShort @?= 2751257939873091
        Tape.arenaEntryQ afterLong @?= 2751257939873091
        otherSpec <- expectRight (Tape.mkArenaTapeSpec "fixture/lengths" 7961 4 7)
        Tape.arenaTapeDigestInput spec 2 3 (-1) @?= Tape.arenaTapeDigestInput otherSpec 2 3 (-1)
        assertBool
          "changed descriptor creates a different complete schedule"
          (Tape.arenaTapeBytes tape /= Tape.arenaTapeBytes (Tape.materializeArenaTape otherSpec))
    , testCase "independent complete schedule bytes hash and canonical decode round trip match" $ do
        spec <- smallSpec
        let tape = Tape.materializeArenaTape spec
        BS.length (Tape.arenaTapeBytes tape) @?= 468
        Tape.arenaTapeSpecEncodedLength spec @?= 468
        hexBytes (Tape.arenaTapeBytes tape) @?= knownScheduleHex
        Tape.arenaTapeSha256 tape @?= "cf208ba3a1b5ab32226c216bfad53aa25e176278018d5479d6082c8fff324f84"
        Tape.arenaTapeSha256 tape @?= sha256Hex (Tape.arenaTapeBytes tape)
        Tape.decodeArenaTape (Tape.arenaTapeBytes tape) @?= Right tape
        Tape.verifyArenaTape spec (Tape.arenaTapeBytes tape) @?= Right tape
        assertBool
          "digest and durable domains are distinct"
          (Tape.arenaTapeProtocol /= Tape.arenaScheduleProtocol)
    , testCase "altered address signed side q and MCTS payloads never become authoritative" $ do
        spec <- smallSpec
        let bytes = Tape.arenaTapeBytes (Tape.materializeArenaTape spec)
            body = 31 + 8 + 13 + 32
        forM_ [body + 7, body + 15, body + 23, body + 31, body + 39, body + 47] $ \offset ->
          Tape.decodeArenaTape (flipByte offset bytes) @?= Left Tape.SchedulePayloadMismatch
    , testCase "descriptor substitution noncanonical lengths UTF8 and trailing bytes reject specifically" $ do
        spec <- smallSpec
        let bytes = Tape.arenaTapeBytes (Tape.materializeArenaTape spec)
        Tape.decodeArenaTape (flipByte 0 bytes)
          @?= Left (Tape.InvalidScheduleEncoding "wrong schedule domain/version")
        Tape.decodeArenaTape (BS.take 10 bytes) @?= Left (Tape.InvalidScheduleEncoding "truncated schedule")
        Tape.decodeArenaTape (BS.take (BS.length bytes - 1) bytes)
          @?= Left (Tape.InvalidScheduleEncoding "schedule byte length mismatch")
        Tape.decodeArenaTape (bytes <> BS.singleton 0)
          @?= Left (Tape.InvalidScheduleEncoding "schedule byte length mismatch")
        Tape.decodeArenaTape (replaceByte 39 255 bytes)
          @?= Left (Tape.InvalidScheduleEncoding "row is not UTF8")
        Tape.decodeArenaTape (flipByte (31 + 8 + 13 + 31) bytes)
          @?= Left (Tape.InvalidScheduleEncoding "declared entry count mismatch")
        foreignSpec <- expectRight (Tape.mkArenaTapeSpec "fixture/other" 7961 2 2)
        let foreignBytes = Tape.arenaTapeBytes (Tape.materializeArenaTape foreignSpec)
        Tape.decodeArenaTape foreignBytes @?= Right (Tape.materializeArenaTape foreignSpec)
        Tape.verifyArenaTape spec foreignBytes @?= Left Tape.ScheduleDescriptorMismatch
    ]

smallSpec :: IO Tape.ArenaTapeSpec
smallSpec = expectRight (Tape.mkArenaTapeSpec "fixture/arena" 7961 2 2)

flipByte :: Int -> BS.ByteString -> BS.ByteString
flipByte offset bytes = replaceByte offset (BS.index bytes offset `xor` 1) bytes

replaceByte :: Int -> Word8 -> BS.ByteString -> BS.ByteString
replaceByte offset byte bytes = BS.take offset bytes <> BS.singleton byte <> BS.drop (offset + 1) bytes

expectRight :: (Show e) => Either e a -> IO a
expectRight = either (\err -> assertFailure (show err) >> fail "unreachable") pure

knownCases :: [(Text, Word64, Word64, Int, Text, Text, Word64, Int)]
knownCases =
  [
    ( "AlphaZero/connect4"
    , 0
    , 0
    , 1
    , "6a69746d6c2d6e61746976652d6172656e612d746170652d7631000000000000000012416c7068615a65726f2f636f6e6e656374340000000000001f19000000000000000000000000000000000000000000000001"
    , "4a1532b20b2cd987fd098b77ff473b6d7d420fb8874da68ec618349ef4a58b15"
    , 2606556969526683
    , 7961
    )
  ,
    ( "AlphaZero/connect4"
    , 0
    , 0
    , -1
    , "6a69746d6c2d6e61746976652d6172656e612d746170652d7631000000000000000012416c7068615a65726f2f636f6e6e656374340000000000001f19000000000000000000000000000000000000000000000002"
    , "0b7ad781a1290f8e00d9c388dc6a8852f651b0d07c30a17bc22c7f55b7633a07"
    , 403911344399649
    , 7961
    )
  ,
    ( "AlphaZero/connect4"
    , 8
    , 41
    , 1
    , "6a69746d6c2d6e61746976652d6172656e612d746170652d7631000000000000000012416c7068615a65726f2f636f6e6e656374340000000000001f19000000000000000800000000000000290000000000000001"
    , "fcd2b96a5c51bd7bef85401208b798f3e0db6b330e4069e0ffe70fbe2f2eeb53"
    , 8895423490787895
    , 340712
    )
  ,
    ( "AlphaZero/connect4"
    , 8
    , 41
    , -1
    , "6a69746d6c2d6e61746976652d6172656e612d746170652d7631000000000000000012416c7068615a65726f2f636f6e6e656374340000000000001f19000000000000000800000000000000290000000000000002"
    , "bfc3e2259527ab6a2bd6ac9bf40709e576c62bdf2cda4ac8b15ab763d40a3c89"
    , 6747137076536565
    , 340712
    )
  ,
    ( "AlphaZero/棋🙂"
    , 1
    , 2
    , 1
    , "6a69746d6c2d6e61746976652d6172656e612d746170652d7631000000000000000011416c7068615a65726f2fe6a38bf09f99820000000000001f19000000000000000100000000000000020000000000000001"
    , "fc138aa2e4ec4a4cf62a2c68094f1a5a77bb71b347976d9e5a8c80c2cfe21ca0"
    , 8869147536301449
    , 24808
    )
  ,
    ( "AlphaZero/棋🙂"
    , 1
    , 2
    , -1
    , "6a69746d6c2d6e61746976652d6172656e612d746170652d7631000000000000000011416c7068615a65726f2fe6a38bf09f99820000000000001f19000000000000000100000000000000020000000000000002"
    , "f78afe325e9252ed65f2d60fd5e19409db0d87475832f99908f399dfae60d5b2"
    , 8709642952364618
    , 24808
    )
  ,
    ( "fixture/lengths"
    , 2
    , 3
    , -1
    , "6a69746d6c2d6e61746976652d6172656e612d746170652d763100000000000000000f666978747572652f6c656e677468730000000000001f19000000000000000200000000000000030000000000000002"
    , "4e320941886a1d5d882c2d511178a171618541d9c6512925b2b47a6a82c3abc2"
    , 2751257939873091
    , 33736
    )
  ]

knownScheduleHex :: Text
knownScheduleHex =
  "6a69746d6c2d6e61746976652d6172656e612d7363686564756c652d763100000000000000000d666978747572652f6172656e610000000000001f190000000000000002000000000000000200000000000000080000000000000000000000000000000000000000000000010000000000000001001d0142286b2ac40000000000001f1900000000000000000000000000000000ffffffffffffffff000000000000000200197a0b4754a8dc0000000000001f190000000000000000000000000000000100000000000000010000000000000001000840b8c2f959330000000000003e0800000000000000000000000000000001ffffffffffffffff000000000000000200110f98de72fb6d0000000000003e080000000000000001000000000000000000000000000000010000000000000001001252f55b683da2000000000000230a00000000000000010000000000000000ffffffffffffffff0000000000000002000e180e5b32f70a000000000000230a00000000000000010000000000000001000000000000000100000000000000010002f0164ac1306700000000000041f900000000000000010000000000000001ffffffffffffffff0000000000000002000833acc8aa8c2d00000000000041f9"
