{-# LANGUAGE OverloadedStrings #-}

-- | Definite shortest CBOR reader with length checks before list/text decoding.
-- The reader returns slices and bounded tuples; it does not expand a DAG.
module JitML.Checkpoint.NativePhase.CBOR
  ( Parser
  , runParser
  , runParserPrefix
  , parserFailure
  , liftEither
  , position
  , remainingBytes
  , withinSpan
  , ensureMinimumItems
  , getWord
  , getInt64
  , getBool
  , getBytes
  , getBytesLength
  , getText
  , getDigest
  , getBits
  , getListLength
  , expectList
  , getNull
  , nextIsNull
  , rawValueEncoding
  , encodeStrict
  , word64Bytes
  ) where

import Codec.CBOR.Encoding qualified as CBOR
import Codec.CBOR.Write qualified as CBOR
import Control.Monad (when)
import Data.Bits (shiftL, shiftR, (.&.), (.|.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Int (Int64)
import Data.Text (Text)
import Data.Text.Encoding qualified as UTF8
import Data.Word (Word64, Word8)

import JitML.Checkpoint.NativePhase.Types

data Cursor = Cursor !ByteString !Int !Int
newtype Parser a = Parser (Cursor -> Either CodecError (a, Cursor))

instance Functor Parser where
  fmap f (Parser action) = Parser $ \cursor -> do
    (value, after) <- action cursor
    pure (f value, after)

instance Applicative Parser where
  pure value = Parser $ \cursor -> Right (value, cursor)
  Parser function <*> Parser argument = Parser $ \cursor -> do
    (f, next) <- function cursor
    (value, after) <- argument next
    pure (f value, after)

instance Monad Parser where
  Parser action >>= next = Parser $ \cursor -> do
    (value, after) <- action cursor
    let Parser continuation = next value
    continuation after

runParser :: Parser a -> ByteString -> Either CodecError a
runParser (Parser action) bytes = do
  checkLimit WholePayloadBytes (toInteger (BS.length bytes))
  (value, Cursor _ offset end) <- action (Cursor bytes 0 (BS.length bytes))
  if offset == end then Right value else Left (NonCanonical "trailing CBOR bytes")

-- | Parse a bounded prefix and report its consumed byte count. The original
-- whole-input256MiB limit still applies. A containing envelope reader can pass
-- only its small fixed header window, then independently bound/slice its final
-- opaque payload; this operation confers no canonical whole-object claim.
runParserPrefix :: Parser a -> ByteString -> Either CodecError (a, Int)
runParserPrefix (Parser action) bytes = do
  checkLimit WholePayloadBytes (toInteger (BS.length bytes))
  (value, Cursor _ offset _) <- action (Cursor bytes 0 (BS.length bytes))
  pure (value, offset)

parserFailure :: CodecError -> Parser a
parserFailure errorValue = Parser $ const (Left errorValue)

liftEither :: Either CodecError a -> Parser a
liftEither = either parserFailure pure

position :: Parser Int
position = Parser $ \cursor@(Cursor _ offset _) -> Right (offset, cursor)

remainingBytes :: Parser Int
remainingBytes = Parser $ \cursor@(Cursor _ offset end) -> Right (end - offset, cursor)

withinSpan :: Resource -> Parser a -> Parser a
withinSpan resource (Parser action) = Parser $ \(Cursor bytes offset end) -> do
  let cap = nativePhaseLimit resource
      allowed = min (toInteger (end - offset)) cap
      localEnd = offset + fromInteger allowed
  case action (Cursor bytes offset localEnd) of
    Left (UnexpectedEnd _) | localEnd < end -> Left (ResourceExceeded resource cap (cap + 1))
    Left failure -> Left failure
    Right (value, Cursor _ after _) -> Right (value, Cursor bytes after end)

takeBytes :: Word64 -> Parser ByteString
takeBytes count = Parser $ \(Cursor bytes offset end) ->
  if toInteger count > toInteger (end - offset)
    then Left (UnexpectedEnd offset)
    else
      let size = fromIntegral count
       in Right (BS.take size (BS.drop offset bytes), Cursor bytes (offset + size) end)

getByte :: Parser Word8
getByte = Parser $ \(Cursor bytes offset end) ->
  if offset >= end
    then Left (UnexpectedEnd offset)
    else Right (BS.index bytes offset, Cursor bytes (offset + 1) end)

peekByte :: Parser Word8
peekByte = Parser $ \cursor@(Cursor bytes offset end) ->
  if offset >= end then Left (UnexpectedEnd offset) else Right (BS.index bytes offset, cursor)

unsignedBytes :: Int -> Parser Word64
unsignedBytes count =
  BS.foldl' (\acc byte -> (acc `shiftL` 8) .|. fromIntegral byte) 0 <$> takeBytes (fromIntegral count)

headValue :: Parser (Word8, Word64)
headValue = do
  byte <- getByte
  let major = byte `shiftR` 5
      additional = byte .&. 31
      extended count minimumValue = do
        value <- unsignedBytes count
        if value < minimumValue
          then parserFailure (NonCanonical "non-shortest CBOR argument")
          else pure (major, value)
  case additional of
    24 -> extended 1 24
    25 -> extended 2 256
    26 -> extended 4 65536
    27 -> extended 8 4294967296
    n | n < 24 -> pure (major, fromIntegral n)
    _ -> parserFailure (NonCanonical "indefinite or reserved CBOR argument")

getWord :: Parser Word64
getWord = do
  (major, value) <- headValue
  if major == 0 then pure value else parserFailure (Malformed "expected uint64")

getInt64 :: Parser Int64
getInt64 = do
  (major, value) <- headValue
  if value > fromIntegral (maxBound :: Int64)
    then parserFailure (Malformed "signed64 overflow")
    else case major of
      0 -> pure (fromIntegral value)
      1 -> pure (-1 - fromIntegral value)
      _ -> parserFailure (Malformed "expected signed64 integer")

getBool :: Parser Bool
getBool = do
  byte <- getByte
  case byte of
    244 -> pure False
    245 -> pure True
    _ -> parserFailure (NonCanonical "expected canonical Boolean")

getNull :: Parser ()
getNull = do
  byte <- getByte
  if byte == 246 then pure () else parserFailure (NonCanonical "expected canonical null")

nextIsNull :: Parser Bool
nextIsNull = (== 246) <$> peekByte

getBytes :: Resource -> Integer -> Parser ByteString
getBytes resource cap = getBytesLength resource cap >>= takeBytes

-- | Read only a shortest definite bytestring header. Declared length is checked
-- before any payload slicing/allocation. Callers must separately require the
-- actual payload and their enclosing object's exact end; getBytes still does
-- both header and slice in its original error order.
getBytesLength :: Resource -> Integer -> Parser Word64
getBytesLength resource cap = do
  requestedCap resource cap
  (major, count) <- headValue
  when (major /= 2) (parserFailure (Malformed "expected definite bytes"))
  if toInteger count > cap
    then parserFailure (ResourceExceeded resource cap (toInteger count))
    else pure count

getText :: Resource -> Integer -> Parser Text
getText resource cap = do
  requestedCap resource cap
  (major, count) <- headValue
  when (major /= 3) (parserFailure (Malformed "expected definite text"))
  if toInteger count > cap
    then parserFailure (ResourceExceeded resource cap (toInteger count))
    else do
      bytes <- takeBytes count
      case UTF8.decodeUtf8' bytes of
        Left _ -> parserFailure (Malformed "invalid UTF8")
        Right value -> pure value

getDigest :: Parser Digest
getDigest = getBytes GeneralTextBytes 32 >>= liftEither . mkDigest

getBits :: Parser Word64
getBits = do
  bytes <- getBytes TensorChunkBytes 8
  if BS.length bytes /= 8
    then parserFailure (Malformed "F64Bits requires exactly8 bytes")
    else pure (BS.foldl' (\acc byte -> (acc `shiftL` 8) .|. fromIntegral byte) 0 bytes)

-- Every array element consumes at least one byte. Refuse impossible declared
-- counts before allocating its result spine; pool entries use a stronger floor.
ensureMinimumItems :: Word64 -> Word64 -> Parser ()
ensureMinimumItems count minimumBytes = do
  available <- remainingBytes
  when
    (toInteger count * toInteger minimumBytes > toInteger available)
    (position >>= parserFailure . UnexpectedEnd)

getListLength :: Resource -> Integer -> Parser Int
getListLength resource cap = do
  requestedCap resource cap
  (major, count) <- headValue
  when (major /= 4) (parserFailure (Malformed "expected definite array"))
  if toInteger count > cap
    then parserFailure (ResourceExceeded resource cap (toInteger count))
    else do
      ensureMinimumItems count 1
      pure (fromIntegral count)

requestedCap :: Resource -> Integer -> Parser ()
requestedCap resource cap =
  when
    (cap < 0 || cap > nativePhaseLimit resource || cap > toInteger (maxBound :: Int))
    (parserFailure (Malformed "invalid bounded reader limit"))

expectList :: Int -> Parser ()
expectList expected = do
  actual <- getListLength SequenceFanout (toInteger expected)
  if actual == expected then pure () else parserFailure (Malformed "wrong fixed array arity")

word64Bytes :: Word64 -> ByteString
word64Bytes value = BS.pack [fromIntegral (value `shiftR` shift) | shift <- [56, 48 .. 0]]

-- Internal encoder primitive; callers first validate against the closed schema.
rawValueEncoding :: NodeValue -> CBOR.Encoding
rawValueEncoding value = case value of
  VWord n -> CBOR.encodeWord64 n
  VInt n -> CBOR.encodeInt64 n
  VBits n -> CBOR.encodeBytes (word64Bytes n)
  VBool n -> CBOR.encodeBool n
  VText n -> CBOR.encodeString n
  VBytes n -> CBOR.encodeBytes n
  VDigest n -> CBOR.encodeBytes (digestBytes n)
  VRef n -> CBOR.encodeBytes (digestBytes n)
  VList values -> CBOR.encodeListLen (fromIntegral (length values)) <> foldMap rawValueEncoding values
  VNull -> CBOR.encodeNull

encodeStrict :: CBOR.Encoding -> ByteString
encodeStrict = LBS.toStrict . CBOR.toLazyByteString
