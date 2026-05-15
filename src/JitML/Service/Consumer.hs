{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.Consumer
    ( EventId (..)
    , eventIdFromPayload
    , processAtLeastOnce
    )
where

import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified as ByteString
import Data.ByteString qualified as StrictByteString
import Data.Char (intToDigit)
import Data.Text (Text)
import Data.Text.Encoding qualified as Text.Encoding

newtype EventId = EventId
    { unEventId :: Text
    }
    deriving stock (Eq, Ord, Show)

eventIdFromPayload :: ByteString.ByteString -> EventId
eventIdFromPayload payload =
    EventId (Text.Encoding.decodeUtf8 (hexEncode (SHA256.hash payload)))

processAtLeastOnce :: Ord eventId => [eventId] -> [eventId]
processAtLeastOnce = reverse . foldl insertIfMissing []
  where
    insertIfMissing seen eventId
        | eventId `elem` seen = seen
        | otherwise = eventId : seen

hexEncode :: StrictByteString.ByteString -> StrictByteString.ByteString
hexEncode =
    StrictByteString.pack . concatMap byteToHex . StrictByteString.unpack
  where
    byteToHex byte =
        [ fromIntegral (fromEnum (intToDigit (fromIntegral (byte `div` 16))))
        , fromIntegral (fromEnum (intToDigit (fromIntegral (byte `mod` 16))))
        ]
