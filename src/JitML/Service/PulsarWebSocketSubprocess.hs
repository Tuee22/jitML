{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TupleSections #-}

module JitML.Service.PulsarWebSocketSubprocess
  ( PulsarWebSocketSettings (..)
  , PulsarWebSocketSubprocess (..)
  , defaultPulsarWebSocketSettings
  , pulsarConsumeSubprocess
  , pulsarPublishSubprocess
  , pulsarSettingsForLocalEdge
  , runPulsarWebSocketSubprocess
  )
where

import Control.Exception (bracket)
import Control.Monad (when)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Reader (MonadReader, ReaderT (..), ask, runReaderT)
import Data.ByteString qualified as ByteString
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Text.Encoding.Error qualified as TextErr
import System.Directory (doesFileExist, getTemporaryDirectory, removeFile)
import System.Exit (ExitCode (..))
import System.IO (hClose, openTempFile)

import JitML.Service.Capabilities
  ( HasPulsar (..)
  , SubscriptionId (..)
  , TopicName (..)
  )
import JitML.Service.Retry (ServiceError (..))
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (Subprocess, subprocess)

data PulsarWebSocketSettings = PulsarWebSocketSettings
  { pulsarNodeBinary :: FilePath
  , pulsarWebSocketEndpoint :: Text
  }
  deriving stock (Eq, Show)

defaultPulsarWebSocketSettings :: PulsarWebSocketSettings
defaultPulsarWebSocketSettings =
  pulsarSettingsForLocalEdge 9090

pulsarSettingsForLocalEdge :: Int -> PulsarWebSocketSettings
pulsarSettingsForLocalEdge edgePort =
  PulsarWebSocketSettings
    { pulsarNodeBinary = "node"
    , pulsarWebSocketEndpoint = "ws://127.0.0.1:" <> Text.pack (show edgePort) <> "/pulsar/ws"
    }

newtype PulsarWebSocketSubprocess a = PulsarWebSocketSubprocess
  { unPulsarWebSocketSubprocess :: ReaderT PulsarWebSocketSettings IO a
  }
  deriving newtype
    ( Functor
    , Applicative
    , Monad
    , MonadIO
    , MonadReader PulsarWebSocketSettings
    )

runPulsarWebSocketSubprocess :: PulsarWebSocketSettings -> PulsarWebSocketSubprocess a -> IO a
runPulsarWebSocketSubprocess settings action =
  runReaderT (unPulsarWebSocketSubprocess action) settings

pulsarPublishSubprocess
  :: PulsarWebSocketSettings -> TopicName -> FilePath -> FilePath -> Subprocess
pulsarPublishSubprocess settings topic payloadPath outputPath =
  subprocess
    (pulsarNodeBinary settings)
    [ "--eval"
    , producerScript
    , producerUrl settings topic
    , Text.pack payloadPath
    , Text.pack outputPath
    ]

pulsarConsumeSubprocess :: PulsarWebSocketSettings -> SubscriptionId -> FilePath -> Subprocess
pulsarConsumeSubprocess settings subscription outputPath =
  subprocess
    (pulsarNodeBinary settings)
    [ "--eval"
    , consumerScript
    , consumerUrl settings subscription
    , Text.pack outputPath
    ]

instance HasPulsar PulsarWebSocketSubprocess where
  pulsarPublish topic payload = do
    settings <- ask
    withPayloadFile (Text.Encoding.encodeUtf8 payload) $ \payloadPath ->
      withResponseFile $ \outputPath -> do
        result <-
          invokeNode
            "pulsarPublish"
            (pulsarPublishSubprocess settings topic payloadPath outputPath)
            outputPath
        pure (Text.strip <$> result)

  -- The one-shot WebSocket consumer acks on the same session before closing.
  pulsarAcknowledge _topic _payload =
    pure (Right ())

  pulsarSubscribe topic subscription =
    pure (Right (renderSubscriptionId topic subscription))

  pulsarConsume subscription = do
    settings <- ask
    withResponseFile $ \outputPath -> do
      result <-
        invokeNode
          "pulsarConsume"
          (pulsarConsumeSubprocess settings subscription outputPath)
          outputPath
      let topicText = subscriptionTopic subscription
      pure ((topicText,) <$> result)

  pulsarSeek _subscription _eventId =
    pure (Left (SETransient "pulsarSeek is not supported by the one-shot WebSocket subprocess client"))

invokeNode :: Text -> Subprocess -> FilePath -> PulsarWebSocketSubprocess (Either ServiceError Text)
invokeNode tag command outputPath = do
  (exitCode, _stdoutText, stderrText) <- liftIO (runStreaming defaultSubprocessEnv command)
  case exitCode of
    ExitSuccess ->
      Right . Text.Encoding.decodeUtf8With TextErr.lenientDecode
        <$> liftIO (ByteString.readFile outputPath)
    ExitFailure code ->
      pure (Left (SETransient (tag <> ": node exit " <> Text.pack (show code) <> ": " <> stderrText)))

producerUrl :: PulsarWebSocketSettings -> TopicName -> Text
producerUrl settings topic =
  stripTrailingSlash (pulsarWebSocketEndpoint settings) <> "/v2/producer/" <> topicPath topic

consumerUrl :: PulsarWebSocketSettings -> SubscriptionId -> Text
consumerUrl settings subscription =
  stripTrailingSlash (pulsarWebSocketEndpoint settings)
    <> "/v2/consumer/"
    <> topicPath (TopicName (subscriptionTopic subscription))
    <> "/"
    <> pathSegment (subscriptionName subscription)
    <> "?subscriptionType=Exclusive&receiverQueueSize=1&ackTimeoutMillis=30000"

renderSubscriptionId :: TopicName -> Text -> SubscriptionId
renderSubscriptionId topic subscription =
  SubscriptionId (unTopicName topic <> "\n" <> subscription)

subscriptionTopic :: SubscriptionId -> Text
subscriptionTopic (SubscriptionId encoded) =
  fst (Text.breakOn "\n" encoded)

subscriptionName :: SubscriptionId -> Text
subscriptionName (SubscriptionId encoded) =
  Text.drop 1 (snd (Text.breakOn "\n" encoded))

topicPath :: TopicName -> Text
topicPath (TopicName topic) =
  case Text.stripPrefix "persistent://" topic of
    Just rest -> "persistent/" <> Text.intercalate "/" (fmap pathSegment (Text.splitOn "/" rest))
    Nothing -> Text.intercalate "/" (fmap pathSegment (Text.splitOn "/" topic))

pathSegment :: Text -> Text
pathSegment =
  Text.concatMap encodeChar
 where
  encodeChar char
    | isPathSafe char = Text.singleton char
    | otherwise = percentEncodeUtf8 char

isPathSafe :: Char -> Bool
isPathSafe char =
  char `elem` safeChars

safeChars :: [Char]
safeChars =
  ['a' .. 'z']
    <> ['A' .. 'Z']
    <> ['0' .. '9']
    <> "-._~"

percentEncodeUtf8 :: Char -> Text
percentEncodeUtf8 =
  Text.concatMap (Text.pack . bytePercentHex)
    . Text.Encoding.decodeLatin1
    . Text.Encoding.encodeUtf8
    . Text.singleton

bytePercentHex :: Char -> String
bytePercentHex char =
  let byte = fromEnum char
   in [ '%'
      , intToHexUpper (byte `div` 16)
      , intToHexUpper (byte `mod` 16)
      ]

intToHexUpper :: Int -> Char
intToHexUpper digit
  | digit < 10 = toEnum (fromEnum '0' + digit)
  | otherwise = toEnum (fromEnum 'A' + digit - 10)

stripTrailingSlash :: Text -> Text
stripTrailingSlash value
  | "/" `Text.isSuffixOf` value = stripTrailingSlash (Text.dropEnd 1 value)
  | otherwise = value

withPayloadFile
  :: ByteString.ByteString -> (FilePath -> PulsarWebSocketSubprocess a) -> PulsarWebSocketSubprocess a
withPayloadFile payload action =
  withTempFile "jitml-pulsar-payload" $ \path -> do
    liftIO (ByteString.writeFile path payload)
    action path

withResponseFile :: (FilePath -> PulsarWebSocketSubprocess a) -> PulsarWebSocketSubprocess a
withResponseFile =
  withTempFile "jitml-pulsar-response"

withTempFile :: String -> (FilePath -> PulsarWebSocketSubprocess a) -> PulsarWebSocketSubprocess a
withTempFile prefix action =
  PulsarWebSocketSubprocess $
    ReaderT $ \settings -> do
      tempRoot <- getTemporaryDirectory
      bracket
        (openTempFile tempRoot prefix)
        (\(path, handle) -> hClose handle >> removeFileIfExists path)
        ( \(path, handle) -> do
            hClose handle
            runReaderT (unPulsarWebSocketSubprocess (action path)) settings
        )

removeFileIfExists :: FilePath -> IO ()
removeFileIfExists path = do
  exists <- doesFileExist path
  when exists (removeFile path)

producerScript :: Text
producerScript =
  Text.unlines
    [ "const fs = require('fs');"
    , "const [url, payloadPath, outputPath] = process.argv.slice(1);"
    , "const payload = fs.readFileSync(payloadPath);"
    , "const ws = new WebSocket(url);"
    , "let settled = false;"
    , "const timer = setTimeout(() => { console.error('timeout'); process.exit(2); }, 10000);"
    , "ws.addEventListener('open', () => {"
    , "  ws.send(JSON.stringify({ payload: Buffer.from(payload).toString('base64'), properties: {}, context: 'jitml' }));"
    , "});"
    , "ws.addEventListener('message', (event) => {"
    , "  settled = true;"
    , "  const message = JSON.parse(String(event.data));"
    , "  if (message.result && message.result !== 'ok') { console.error(String(event.data)); process.exit(1); }"
    , "  fs.writeFileSync(outputPath, message.messageId || message.context || String(event.data));"
    , "  clearTimeout(timer);"
    , "  ws.close();"
    , "  process.exit(0);"
    , "});"
    , "ws.addEventListener('error', (event) => { clearTimeout(timer); console.error(event.message || 'websocket error'); process.exit(1); });"
    , "ws.addEventListener('close', (event) => {"
    , "  if (!settled) { clearTimeout(timer); console.error(`closed before publish ack: ${event.code} ${event.reason || ''}`); process.exit(1); }"
    , "});"
    ]

consumerScript :: Text
consumerScript =
  Text.unlines
    [ "const fs = require('fs');"
    , "const [url, outputPath] = process.argv.slice(1);"
    , "const ws = new WebSocket(url);"
    , "let settled = false;"
    , "const timer = setTimeout(() => { console.error('timeout'); process.exit(2); }, 15000);"
    , "ws.addEventListener('message', (event) => {"
    , "  settled = true;"
    , "  const message = JSON.parse(String(event.data));"
    , "  const payload = Buffer.from(message.payload || '', 'base64');"
    , "  if (message.messageId) { ws.send(JSON.stringify({ messageId: message.messageId })); }"
    , "  fs.writeFileSync(outputPath, payload);"
    , "  clearTimeout(timer);"
    , "  ws.close();"
    , "  process.exit(0);"
    , "});"
    , "ws.addEventListener('error', (event) => { clearTimeout(timer); console.error(event.message || 'websocket error'); process.exit(1); });"
    , "ws.addEventListener('close', (event) => {"
    , "  if (!settled) { clearTimeout(timer); console.error(`closed before message: ${event.code} ${event.reason || ''}`); process.exit(1); }"
    , "});"
    ]
