{-# LANGUAGE OverloadedStrings #-}

-- | Minimal RFC 6455 WebSocket server primitives sufficient for the
-- demo's @/api/ws*@ bridge.
--
-- Sprint 13.13 — the held-open broker bridge. The existing
-- @JitML.Service.Http@ socket server is one-request-one-response; this
-- module adds the WebSocket upgrade handshake plus server-side text
-- frame writer so a single TCP connection stays open for the lifetime of
-- the consumer.
--
-- Scope:
--
--   * Server-side text frames (server → client; no mask, opcode = 0x1).
--   * Single-fragment messages with FIN = 1.
--   * Close frame on disconnect (opcode = 0x8) emitted on a clean exit.
--
-- Out of scope (and tracked under
-- "DEVELOPMENT_PLAN/phase-13-linux-cuda-and-cluster-closure.md"
-- Sprint 13.13 Remaining Work):
--
--   * Client → server frames (the demo never sends; the bridge
--     forwards consumes only).
--   * Continuation frames (>125-byte messages still encode correctly,
--     but the writer never produces opcode = 0x0 continuations).
--   * Per-message compression extensions (RFC 7692).
module JitML.Service.WebSocket
  ( WebSocketUpgrade (..)
  , detectWebSocketUpgrade
  , encodeTextFrame
  , encodeCloseFrame
  , renderUpgradeAccept
  , webSocketAcceptKey
  , webSocketMagic
  )
where

import Crypto.Hash.SHA1 qualified as SHA1
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Base64 qualified as Base64
import Data.ByteString.Builder qualified as Builder
import Data.ByteString.Char8 qualified as Char8
import Data.ByteString.Lazy qualified as ByteString.Lazy
import Data.Char (toLower)
import Data.Text (Text)
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word8)

-- | The handshake result the HTTP listener forwards into the body of
-- the connection: either no upgrade was requested, or the upgrade is
-- complete and the caller must run a writer loop on the same socket.
data WebSocketUpgrade
  = NoUpgrade
  | UpgradeAccepted
      { upgradeAcceptKey :: ByteString
      -- ^ The accept value derived from the client's @Sec-WebSocket-Key@.
      }
  deriving stock (Eq, Show)

-- | RFC 6455 §1.3 magic GUID concatenated with the client's
-- @Sec-WebSocket-Key@ before SHA-1 + Base64.
webSocketMagic :: ByteString
webSocketMagic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

-- | Derive the @Sec-WebSocket-Accept@ header value from the client's
-- @Sec-WebSocket-Key@.
webSocketAcceptKey :: ByteString -> ByteString
webSocketAcceptKey clientKey =
  Base64.encode (SHA1.hash (clientKey <> webSocketMagic))

-- | Render the @HTTP/1.1 101 Switching Protocols@ response carrying
-- the accept key.
renderUpgradeAccept :: ByteString -> ByteString
renderUpgradeAccept acceptKey =
  ByteString.concat
    [ "HTTP/1.1 101 Switching Protocols\r\n"
    , "Upgrade: websocket\r\n"
    , "Connection: Upgrade\r\n"
    , "Sec-WebSocket-Accept: "
    , acceptKey
    , "\r\n\r\n"
    ]

-- | Inspect the raw request bytes for the @Upgrade: websocket@ +
-- @Sec-WebSocket-Key@ headers. Returns 'NoUpgrade' when the request is
-- a regular HTTP route.
detectWebSocketUpgrade :: ByteString -> WebSocketUpgrade
detectWebSocketUpgrade request =
  let headerLines = Char8.lines request
      hasWebSocketUpgrade =
        any
          (\line -> headerEquals "upgrade" line && Char8.map toLower (headerValue line) == "websocket")
          headerLines
      clientKey =
        ByteString.concat
          [ ByteString.dropWhile (== 0x20) (headerValue line)
          | line <- headerLines
          , headerEquals "sec-websocket-key" line
          ]
   in if hasWebSocketUpgrade && not (ByteString.null clientKey)
        then UpgradeAccepted (webSocketAcceptKey (stripCRLF clientKey))
        else NoUpgrade
 where
  stripCRLF =
    ByteString.dropWhileEnd (\b -> b == 0x0D || b == 0x0A)

  headerEquals :: ByteString -> ByteString -> Bool
  headerEquals name line =
    case Char8.break (== ':') line of
      (key, rest)
        | not (ByteString.null rest) ->
            Char8.map toLower (Char8.dropWhile (== ' ') key) == name
      _ -> False

  headerValue :: ByteString -> ByteString
  headerValue line =
    case Char8.break (== ':') line of
      (_, rest)
        | not (ByteString.null rest) ->
            stripCRLF (Char8.dropWhile (== ' ') (ByteString.drop 1 rest))
        | otherwise -> ByteString.empty

-- | Encode a UTF-8 text payload as a single-fragment server-side text
-- frame (FIN = 1, opcode = 0x1, mask = 0). The payload-length field
-- expands to the 16-bit or 64-bit extended form when the payload
-- exceeds 125 / 65535 bytes respectively.
encodeTextFrame :: Text -> ByteString
encodeTextFrame payload =
  let bytes = Text.Encoding.encodeUtf8 payload
      header = encodeFrameHeader 0x81 (ByteString.length bytes)
   in ByteString.concat [header, bytes]

-- | Encode an RFC 6455 close frame (opcode = 0x8) with no payload.
encodeCloseFrame :: ByteString
encodeCloseFrame =
  ByteString.pack [0x88, 0x00]

encodeFrameHeader :: Word8 -> Int -> ByteString
encodeFrameHeader firstByte payloadLen
  | payloadLen <= 125 =
      ByteString.pack [firstByte, fromIntegral payloadLen]
  | payloadLen <= 0xFFFF =
      ByteString.Lazy.toStrict
        ( Builder.toLazyByteString
            ( Builder.word8 firstByte
                <> Builder.word8 126
                <> Builder.word16BE (fromIntegral payloadLen)
            )
        )
  | otherwise =
      ByteString.Lazy.toStrict
        ( Builder.toLazyByteString
            ( Builder.word8 firstByte
                <> Builder.word8 127
                <> Builder.word64BE (fromIntegral payloadLen)
            )
        )
