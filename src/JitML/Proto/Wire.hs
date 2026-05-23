{-# LANGUAGE OverloadedStrings #-}

module JitML.Proto.Wire
  ( ProtoField (..)
  , ProtoValue (..)
  , boolField
  , decodeMessage
  , doubleField
  , fieldBool
  , fieldDouble
  , fieldDoubles
  , fieldMessage
  , fieldMessages
  , fieldString
  , fieldWord32
  , fieldWord64
  , encodeMessage
  , fixed64Field
  , messageField
  , packedDoubleField
  , stringField
  , uint32Field
  , uint64Field
  )
where

import Data.Bits (shiftL, shiftR, (.&.), (.|.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word32, Word64)
import GHC.Float (castDoubleToWord64, castWord64ToDouble)

data ProtoValue
  = Varint Word64
  | Fixed64 Word64
  | LengthDelimited ByteString
  deriving stock (Eq, Show)

data ProtoField = ProtoField
  { protoFieldNumber :: Word64
  , protoFieldValue :: ProtoValue
  }
  deriving stock (Eq, Show)

encodeMessage :: [ProtoField] -> ByteString
encodeMessage =
  ByteString.concat . fmap encodeField

decodeMessage :: ByteString -> Either Text [ProtoField]
decodeMessage bytes
  | ByteString.null bytes = Right []
  | otherwise = do
      (key, afterKey) <- decodeVarint bytes
      let fieldNumber = key `shiftR` 3
          decodedWireType = key .&. 0x7
      (value, rest) <- decodeValue decodedWireType afterKey
      (ProtoField fieldNumber value :) <$> decodeMessage rest

stringField :: Word64 -> Text -> ProtoField
stringField fieldNumber =
  ProtoField fieldNumber . LengthDelimited . Text.Encoding.encodeUtf8

fixed64Field :: Word64 -> Word64 -> ProtoField
fixed64Field fieldNumber =
  ProtoField fieldNumber . Fixed64

doubleField :: Word64 -> Double -> ProtoField
doubleField fieldNumber =
  fixed64Field fieldNumber . castDoubleToWord64

packedDoubleField :: Word64 -> [Double] -> ProtoField
packedDoubleField fieldNumber values =
  ProtoField fieldNumber $
    LengthDelimited $
      ByteString.concat (fmap (word64Le . castDoubleToWord64) values)

uint64Field :: Word64 -> Word64 -> ProtoField
uint64Field fieldNumber =
  ProtoField fieldNumber . Varint

uint32Field :: Word64 -> Word32 -> ProtoField
uint32Field fieldNumber =
  ProtoField fieldNumber . Varint . fromIntegral

boolField :: Word64 -> Bool -> ProtoField
boolField fieldNumber value =
  ProtoField fieldNumber (Varint (if value then 1 else 0))

messageField :: Word64 -> ByteString -> ProtoField
messageField fieldNumber =
  ProtoField fieldNumber . LengthDelimited

fieldString :: Word64 -> [ProtoField] -> Maybe Text
fieldString fieldNumber fields = do
  LengthDelimited bytes <- lookupField fieldNumber fields
  eitherToMaybe (Text.Encoding.decodeUtf8' bytes)

fieldWord64 :: Word64 -> [ProtoField] -> Maybe Word64
fieldWord64 fieldNumber fields = do
  Varint value <- lookupField fieldNumber fields
  pure value

fieldWord32 :: Word64 -> [ProtoField] -> Maybe Word32
fieldWord32 fieldNumber fields = do
  value <- fieldWord64 fieldNumber fields
  if value <= fromIntegral (maxBound :: Word32)
    then Just (fromIntegral value)
    else Nothing

fieldBool :: Word64 -> [ProtoField] -> Maybe Bool
fieldBool fieldNumber fields = do
  Varint value <- lookupField fieldNumber fields
  case value of
    0 -> Just False
    1 -> Just True
    _ -> Nothing

fieldDouble :: Word64 -> [ProtoField] -> Maybe Double
fieldDouble fieldNumber fields = do
  Fixed64 value <- lookupField fieldNumber fields
  pure (castWord64ToDouble value)

fieldDoubles :: Word64 -> [ProtoField] -> Maybe [Double]
fieldDoubles fieldNumber fields =
  let values = fieldValues fieldNumber fields
   in if null values
        then Nothing
        else fmap concat (traverse decodeDoubleValue values)

fieldMessage :: Word64 -> [ProtoField] -> Maybe ByteString
fieldMessage fieldNumber fields = do
  LengthDelimited bytes <- lookupField fieldNumber fields
  pure bytes

fieldMessages :: Word64 -> [ProtoField] -> Maybe [ByteString]
fieldMessages fieldNumber =
  traverse decodeMessageField . fieldValues fieldNumber
 where
  decodeMessageField :: ProtoValue -> Maybe ByteString
  decodeMessageField (LengthDelimited bytes) = Just bytes
  decodeMessageField _ = Nothing

encodeField :: ProtoField -> ByteString
encodeField (ProtoField fieldNumber value) =
  encodeVarint ((fieldNumber `shiftL` 3) .|. wireType value)
    <> encodeValue value

wireType :: ProtoValue -> Word64
wireType (Varint _) = 0
wireType (Fixed64 _) = 1
wireType (LengthDelimited _) = 2

encodeValue :: ProtoValue -> ByteString
encodeValue (Varint value) = encodeVarint value
encodeValue (Fixed64 value) = word64Le value
encodeValue (LengthDelimited bytes) =
  encodeVarint (fromIntegral (ByteString.length bytes)) <> bytes

decodeValue :: Word64 -> ByteString -> Either Text (ProtoValue, ByteString)
decodeValue 0 bytes = do
  (value, rest) <- decodeVarint bytes
  pure (Varint value, rest)
decodeValue 1 bytes =
  case word64FromLe bytes of
    Nothing -> Left "truncated fixed64 protobuf field"
    Just (value, rest) -> pure (Fixed64 value, rest)
decodeValue 2 bytes = do
  (len, rest) <- decodeVarint bytes
  let requested = fromIntegral len
      (payload, afterPayload) = ByteString.splitAt requested rest
  if ByteString.length payload == requested
    then Right (LengthDelimited payload, afterPayload)
    else Left "length-delimited field exceeds available protobuf bytes"
decodeValue wire _ =
  Left ("unsupported protobuf wire type: " <> Text.pack (show wire))

encodeVarint :: Word64 -> ByteString
encodeVarint value
  | value < 0x80 = ByteString.singleton (fromIntegral value)
  | otherwise =
      ByteString.cons
        (fromIntegral ((value .&. 0x7f) .|. 0x80))
        (encodeVarint (value `shiftR` 7))

decodeVarint :: ByteString -> Either Text (Word64, ByteString)
decodeVarint =
  go 0 0
 where
  go :: Int -> Word64 -> ByteString -> Either Text (Word64, ByteString)
  go shift acc bytes =
    case ByteString.uncons bytes of
      Nothing -> Left "truncated protobuf varint"
      Just (byte, rest)
        | shift >= 64 -> Left "protobuf varint exceeds 64 bits"
        | byte .&. 0x80 == 0 ->
            Right (acc .|. (fromIntegral byte `shiftL` shift), rest)
        | otherwise ->
            go
              (shift + 7)
              (acc .|. (fromIntegral (byte .&. 0x7f) `shiftL` shift))
              rest

lookupField :: Word64 -> [ProtoField] -> Maybe ProtoValue
lookupField fieldNumber =
  fmap protoFieldValue . findLast . filter ((== fieldNumber) . protoFieldNumber)

eitherToMaybe :: Either error value -> Maybe value
eitherToMaybe (Right value) = Just value
eitherToMaybe (Left _) = Nothing

fieldValues :: Word64 -> [ProtoField] -> [ProtoValue]
fieldValues fieldNumber =
  fmap protoFieldValue . filter ((== fieldNumber) . protoFieldNumber)

findLast :: [a] -> Maybe a
findLast [] = Nothing
findLast [x] = Just x
findLast (_ : xs) = findLast xs

decodeDoubleValue :: ProtoValue -> Maybe [Double]
decodeDoubleValue (Fixed64 value) =
  Just [castWord64ToDouble value]
decodeDoubleValue (LengthDelimited bytes) =
  fmap (fmap castWord64ToDouble) (word64ListFromLe bytes)
decodeDoubleValue (Varint _) =
  Nothing

word64ListFromLe :: ByteString -> Maybe [Word64]
word64ListFromLe bytes
  | ByteString.null bytes = Just []
  | otherwise = do
      (value, rest) <- word64FromLe bytes
      (value :) <$> word64ListFromLe rest

word64FromLe :: ByteString -> Maybe (Word64, ByteString)
word64FromLe bytes =
  case ByteString.splitAt 8 bytes of
    (payload, rest)
      | ByteString.length payload == 8 ->
          Just (foldWord64Le payload, rest)
      | otherwise ->
          Nothing

foldWord64Le :: ByteString -> Word64
foldWord64Le =
  go 0 0 . ByteString.unpack
 where
  go _ acc [] = acc
  go shift acc (byte : rest) =
    go (shift + 8) (acc .|. (fromIntegral byte `shiftL` shift)) rest

word64Le :: Word64 -> ByteString
word64Le word =
  ByteString.pack
    [ fromIntegral ((word `shiftR` shift) .&. 0xff)
    | shift <- [0, 8 .. 56]
    ]
