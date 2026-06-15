{-# LANGUAGE OverloadedStrings #-}

module JitML.SL.Archive
  ( extractTarEntries
  , extractTarEntry
  )
where

import Codec.Compression.GZip qualified as GZip
import Data.Bits (shiftL, (.|.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Char qualified as Char
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word8)

extractTarEntry :: Text -> ByteString -> Either String ByteString
extractTarEntry target archiveBytes = do
  entries <- extractTarEntries archiveBytes
  case lookup target entries of
    Just payload -> Right payload
    Nothing -> Left ("tar: missing entry " <> Text.unpack target)

-- | Extract regular file entries from a ustar-like tar or tar.gz payload.
-- This is intentionally narrow: it is enough for the canonical CIFAR and
-- California Housing archives, and it does not try to interpret symlinks,
-- sparse files, or GNU/PAX extensions.
extractTarEntries :: ByteString -> Either String [(Text, ByteString)]
extractTarEntries archiveBytes = go 0 []
 where
  tarBytes = maybeGunzip archiveBytes
  total = ByteString.length tarBytes

  go offset acc
    | offset + blockSize > total = Left "tar: truncated header"
    | ByteString.all (== 0) header = Right (reverse acc)
    | otherwise = do
        name <- parseEntryName header
        size <- parseOctalField (ByteString.take 12 (ByteString.drop 124 header))
        let dataStart = offset + blockSize
            dataEnd = dataStart + size
            nextOffset = dataStart + roundUpBlock size
        if dataEnd > total
          then Left ("tar: truncated payload for " <> Text.unpack name)
          else
            let payload = ByteString.take size (ByteString.drop dataStart tarBytes)
             in go nextOffset ((name, payload) : acc)
   where
    header = ByteString.take blockSize (ByteString.drop offset tarBytes)

blockSize :: Int
blockSize = 512

roundUpBlock :: Int -> Int
roundUpBlock n =
  ((n + blockSize - 1) `div` blockSize) * blockSize

parseEntryName :: ByteString -> Either String Text
parseEntryName header = do
  name <- decodeField (ByteString.take 100 header)
  prefix <- decodeField (ByteString.take 155 (ByteString.drop 345 header))
  let fullName =
        if Text.null prefix
          then name
          else prefix <> "/" <> name
  if Text.null fullName
    then Left "tar: empty entry name"
    else Right fullName

decodeField :: ByteString -> Either String Text
decodeField =
  firstLeft show
    . Text.Encoding.decodeUtf8'
    . ByteString.takeWhile (/= 0)

parseOctalField :: ByteString -> Either String Int
parseOctalField field =
  case foldl step (Right 0) digits of
    Right parsed -> Right parsed
    Left err -> Left err
 where
  digits =
    ByteString.unpack $
      ByteString.takeWhile
        (\b -> b /= 0 && b /= 32)
        (ByteString.dropWhile (== 32) field)
  step (Left err) _ = Left err
  step (Right acc) byte
    | byte >= ascii0 && byte <= ascii7 =
        Right ((acc `shiftL` 3) .|. fromIntegral (byte - ascii0))
    | otherwise = Left "tar: invalid octal size field"

maybeGunzip :: ByteString -> ByteString
maybeGunzip bytes
  | ByteString.length bytes >= 2
      && ByteString.index bytes 0 == 0x1f
      && ByteString.index bytes 1 == 0x8b =
      LazyByteString.toStrict (GZip.decompress (LazyByteString.fromStrict bytes))
  | otherwise = bytes

firstLeft :: (a -> b) -> Either a c -> Either b c
firstLeft f (Left value) = Left (f value)
firstLeft _ (Right value) = Right value

ascii0 :: Word8
ascii0 = fromIntegral (Char.ord '0')

ascii7 :: Word8
ascii7 = fromIntegral (Char.ord '7')
