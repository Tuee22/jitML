{-# LANGUAGE OverloadedStrings #-}

module JitML.Proto.TensorBoard
  ( TensorBoardEvent (..)
  , encodeTensorBoardFileVersionProto
  , encodeTensorBoardEventProto
  )
where

import Data.Bits (shiftL, shiftR, (.&.), (.|.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.Text (Text)
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word64, Word8)
import GHC.Float (castDoubleToWord64, castFloatToWord32)

data TensorBoardEvent = TensorBoardEvent
  { tbWallTime :: Double
  , tbStep :: Word64
  , tbTag :: Text
  , tbValue :: Double
  }
  deriving stock (Eq, Show)

encodeTensorBoardEventProto :: TensorBoardEvent -> ByteString
encodeTensorBoardEventProto event =
  ByteString.concat
    [ fixed64Field 1 (castDoubleToWord64 (tbWallTime event))
    , varintField 2 (tbStep event)
    , bytesField 5 (summaryPayload event)
    ]

encodeTensorBoardFileVersionProto :: Double -> ByteString
encodeTensorBoardFileVersionProto wallTime =
  ByteString.concat
    [ fixed64Field 1 (castDoubleToWord64 wallTime)
    , bytesField 3 "brain.Event:2"
    ]

summaryPayload :: TensorBoardEvent -> ByteString
summaryPayload event =
  bytesField 1 (summaryValuePayload event)

summaryValuePayload :: TensorBoardEvent -> ByteString
summaryValuePayload event =
  ByteString.concat
    [ bytesField 1 (Text.Encoding.encodeUtf8 (tbTag event))
    , fixed32Field 2 (fromIntegral (castFloatToWord32 (realToFrac (tbValue event))))
    ]

varintField :: Word64 -> Word64 -> ByteString
varintField fieldNumber value =
  ByteString.concat [fieldKey fieldNumber 0, encodeVarint value]

fixed64Field :: Word64 -> Word64 -> ByteString
fixed64Field fieldNumber value =
  ByteString.concat [fieldKey fieldNumber 1, word64Le value]

fixed32Field :: Word64 -> Word64 -> ByteString
fixed32Field fieldNumber value =
  ByteString.concat [fieldKey fieldNumber 5, word32Le value]

bytesField :: Word64 -> ByteString -> ByteString
bytesField fieldNumber payload =
  ByteString.concat
    [ fieldKey fieldNumber 2
    , encodeVarint (fromIntegral (ByteString.length payload))
    , payload
    ]

fieldKey :: Word64 -> Word64 -> ByteString
fieldKey fieldNumber wireType =
  encodeVarint ((fieldNumber `shiftL` 3) .|. wireType)

encodeVarint :: Word64 -> ByteString
encodeVarint =
  ByteString.pack . go
 where
  go value
    | value < 0x80 = [fromIntegral value]
    | otherwise =
        fromIntegral ((value .&. 0x7f) .|. 0x80) : go (value `shiftR` 7)

word64Le :: Word64 -> ByteString
word64Le word =
  ByteString.pack
    [ byteAt 0 word
    , byteAt 8 word
    , byteAt 16 word
    , byteAt 24 word
    , byteAt 32 word
    , byteAt 40 word
    , byteAt 48 word
    , byteAt 56 word
    ]

word32Le :: Word64 -> ByteString
word32Le word =
  ByteString.pack
    [ byteAt 0 word
    , byteAt 8 word
    , byteAt 16 word
    , byteAt 24 word
    ]

byteAt :: Int -> Word64 -> Word8
byteAt offset word =
  fromIntegral ((word `shiftR` offset) .&. 0xff)
