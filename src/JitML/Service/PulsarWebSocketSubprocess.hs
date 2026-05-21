{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.PulsarWebSocketSubprocess
  ( PulsarWebSocketSettings (..)
  , PulsarWebSocketSubprocess (..)
  , PulsarWorkerDelivery (..)
  , defaultPulsarWebSocketSettings
  , pulsarAcknowledgeSubprocess
  , pulsarConsumerWorkerSubprocess
  , pulsarConsumeSubprocess
  , pulsarPublishSubprocess
  , pulsarSubscribeSubprocess
  , pulsarSettingsForEndpoint
  , pulsarSettingsForLocalEdge
  , runPulsarConsumerWorker
  , runPulsarWebSocketSubprocess
  )
where

import Control.Exception (IOException, bracket, try)
import Control.Monad (when)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Reader (MonadReader, ReaderT (..), ask, runReaderT)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.Aeson (FromJSON (..), eitherDecodeStrict', withObject, (.:))
import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as ByteString.Char8
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Text.Encoding.Error qualified as TextErr
import Data.Word (Word8)
import System.Directory (createDirectoryIfMissing, doesFileExist, getTemporaryDirectory, removeFile)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO (Handle, hClose, hFlush, openTempFile)

import JitML.Service.Capabilities
  ( HasPulsar (..)
  , SubscriptionId (..)
  , TopicName (..)
  )
import JitML.Service.Retry (ServiceError (..))
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming, withPipedProcess)
import JitML.Sub.Subprocess (Subprocess, subprocess)

data PulsarWebSocketSettings = PulsarWebSocketSettings
  { pulsarNodeBinary :: FilePath
  , pulsarWebSocketEndpoint :: Text
  }
  deriving stock (Eq, Show)

data PulsarWorkerDelivery = PulsarWorkerDelivery
  { pulsarWorkerDeliveryTopic :: TopicName
  , pulsarWorkerDeliveryMessageId :: Text
  , pulsarWorkerDeliveryPayload :: Text
  }
  deriving stock (Eq, Show)

data WorkerMessage = WorkerMessage
  { workerMessageId :: Text
  , workerPayload :: Text
  }
  deriving stock (Eq, Show)

instance FromJSON WorkerMessage where
  parseJSON =
    withObject "WorkerMessage" $ \object ->
      WorkerMessage
        <$> object .: "messageId"
        <*> object .: "payload"

defaultPulsarWebSocketSettings :: PulsarWebSocketSettings
defaultPulsarWebSocketSettings =
  pulsarSettingsForLocalEdge 9090

pulsarSettingsForLocalEdge :: Int -> PulsarWebSocketSettings
pulsarSettingsForLocalEdge edgePort =
  pulsarSettingsForEndpoint ("pulsar://127.0.0.1:" <> Text.pack (show edgePort) <> "/pulsar")

pulsarSettingsForEndpoint :: Text -> PulsarWebSocketSettings
pulsarSettingsForEndpoint endpoint =
  PulsarWebSocketSettings
    { pulsarNodeBinary = "node"
    , pulsarWebSocketEndpoint = websocketEndpointFromServiceUrl endpoint
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

pulsarConsumerWorkerSubprocess :: PulsarWebSocketSettings -> SubscriptionId -> Subprocess
pulsarConsumerWorkerSubprocess settings subscription =
  subprocess
    (pulsarNodeBinary settings)
    [ "--eval"
    , consumerWorkerScript
    , consumerUrl settings subscription
    ]

pulsarAcknowledgeSubprocess :: PulsarWebSocketSettings -> Text -> Text -> FilePath -> Subprocess
pulsarAcknowledgeSubprocess settings ackUrl messageId outputPath =
  subprocess
    (pulsarNodeBinary settings)
    [ "--eval"
    , acknowledgeScript
    , ackUrl
    , messageId
    , Text.pack outputPath
    ]

pulsarSubscribeSubprocess :: PulsarWebSocketSettings -> TopicName -> Text -> FilePath -> Subprocess
pulsarSubscribeSubprocess settings topic subscription outputPath =
  subprocess
    (pulsarNodeBinary settings)
    [ "--eval"
    , subscribeScript
    , subscriptionProbeUrl settings (renderSubscriptionId topic subscription)
    , unTopicName topic
    , subscription
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

  pulsarAcknowledge topic payload = do
    settings <- ask
    pending <- liftIO (lookupPendingAck settings topic payload)
    case pending of
      Left err -> pure (Left err)
      Right (ackUrl, messageId, recordPath) ->
        withResponseFile $ \outputPath -> do
          result <-
            invokeNode
              "pulsarAcknowledge"
              (pulsarAcknowledgeSubprocess settings ackUrl messageId outputPath)
              outputPath
          case result of
            Left err -> pure (Left err)
            Right _ -> do
              liftIO (removeFileIfExists recordPath)
              pure (Right ())

  pulsarSubscribe topic subscription = do
    settings <- ask
    withResponseFile $ \outputPath -> do
      result <-
        invokeNode
          "pulsarSubscribe"
          (pulsarSubscribeSubprocess settings topic subscription outputPath)
          outputPath
      pure (renderSubscriptionId topic subscription <$ result)

  pulsarConsume subscription = do
    settings <- ask
    withResponseFile $ \outputPath -> do
      result <-
        invokeNode
          "pulsarConsume"
          (pulsarConsumeSubprocess settings subscription outputPath)
          outputPath
      let topicText = subscriptionTopic subscription
      case result of
        Left err -> pure (Left err)
        Right output ->
          case parseConsumedMessage output of
            Nothing ->
              pure (Left (SETransient "pulsarConsume: malformed consumer output"))
            Just (messageId, payload) -> do
              recordResult <-
                liftIO
                  ( recordPendingAck
                      settings
                      (TopicName topicText)
                      payload
                      (consumerUrl settings subscription)
                      messageId
                  )
              case recordResult of
                Left err -> pure (Left err)
                Right () -> pure (Right (topicText, payload))

  pulsarSeek _subscription _eventId =
    pure (Left (SETransient "pulsarSeek is not supported by the one-shot WebSocket subprocess client"))

runPulsarConsumerWorker
  :: PulsarWebSocketSettings
  -> SubscriptionId
  -> (PulsarWorkerDelivery -> IO (Either ServiceError ()) -> IO (Either ServiceError ()) -> IO ())
  -> IO (Either ServiceError ())
runPulsarConsumerWorker settings subscription handleDelivery =
  withPipedProcess (pulsarConsumerWorkerSubprocess settings subscription) $ \stdinHandle stdoutHandle ->
    workerLoop stdinHandle stdoutHandle
 where
  topic = TopicName (subscriptionTopic subscription)

  workerLoop stdinHandle stdoutHandle = do
    lineResult <- try (ByteString.Char8.hGetLine stdoutHandle)
    case lineResult of
      Left err ->
        pure (Left (SETransient ("pulsarConsumerWorker: " <> Text.pack (showIOException err))))
      Right line ->
        case parseWorkerDelivery topic line of
          Left _err ->
            workerLoop stdinHandle stdoutHandle
          Right delivery -> do
            handleDelivery
              delivery
              (ackWorkerDelivery stdinHandle delivery)
              (nackWorkerDelivery stdinHandle delivery)
            workerLoop stdinHandle stdoutHandle

ackWorkerDelivery :: Handle -> PulsarWorkerDelivery -> IO (Either ServiceError ())
ackWorkerDelivery stdinHandle delivery
  | Text.null (pulsarWorkerDeliveryMessageId delivery) =
      pure (Left (SETransient "pulsarConsumerWorker: broker did not return a message id"))
  | otherwise =
      writeWorkerCommand
        stdinHandle
        (pulsarWorkerDeliveryMessageId delivery <> "\n")
        "pulsarConsumerWorker ack"

nackWorkerDelivery :: Handle -> PulsarWorkerDelivery -> IO (Either ServiceError ())
nackWorkerDelivery stdinHandle delivery
  | Text.null (pulsarWorkerDeliveryMessageId delivery) =
      pure (Left (SETransient "pulsarConsumerWorker: broker did not return a message id"))
  | otherwise =
      writeWorkerCommand
        stdinHandle
        ( Text.concat
            [ "{\"type\":\"negativeAcknowledge\",\"messageId\":\""
            , pulsarWorkerDeliveryMessageId delivery
            , "\"}\n"
            ]
        )
        "pulsarConsumerWorker negative ack"

writeWorkerCommand :: Handle -> Text -> Text -> IO (Either ServiceError ())
writeWorkerCommand stdinHandle command tag = do
  writeResult <-
    try
      ( do
          ByteString.hPut stdinHandle (Text.Encoding.encodeUtf8 command)
          hFlush stdinHandle
      )
  case writeResult of
    Left err ->
      pure (Left (SETransient (tag <> ": " <> Text.pack (showIOException err))))
    Right () -> pure (Right ())

parseWorkerDelivery
  :: TopicName -> ByteString.ByteString -> Either ServiceError PulsarWorkerDelivery
parseWorkerDelivery topic line =
  case eitherDecodeStrict' line of
    Left err ->
      Left (SETransient ("pulsarConsumerWorker: malformed worker output: " <> Text.pack err))
    Right message ->
      Right
        PulsarWorkerDelivery
          { pulsarWorkerDeliveryTopic = topic
          , pulsarWorkerDeliveryMessageId = workerMessageId message
          , pulsarWorkerDeliveryPayload = workerPayload message
          }

showIOException :: IOException -> String
showIOException =
  show

invokeNode :: Text -> Subprocess -> FilePath -> PulsarWebSocketSubprocess (Either ServiceError Text)
invokeNode tag command outputPath = do
  (exitCode, _stdoutText, stderrText) <- liftIO (runStreaming defaultSubprocessEnv command)
  case exitCode of
    ExitSuccess ->
      Right . Text.Encoding.decodeUtf8With TextErr.lenientDecode
        <$> liftIO (ByteString.readFile outputPath)
    ExitFailure code
      | tag == "pulsarConsume" && code == 2 && "timeout" `Text.isInfixOf` stderrText ->
          pure (Left (SETimeout "pulsarConsume: no message before timeout"))
    ExitFailure code ->
      pure (Left (SETransient (tag <> ": node exit " <> Text.pack (show code) <> ": " <> stderrText)))

parseConsumedMessage :: Text -> Maybe (Text, Text)
parseConsumedMessage output = do
  let (header, rest) = Text.breakOn "\n" output
  messageId <- Text.stripPrefix "message-id: " header
  let payload = Text.drop 1 rest
  if Text.null messageId
    then Nothing
    else Just (messageId, payload)

recordPendingAck
  :: PulsarWebSocketSettings -> TopicName -> Text -> Text -> Text -> IO (Either ServiceError ())
recordPendingAck settings topic payload ackUrl messageId
  | Text.null messageId =
      pure (Left (SETransient "pulsarConsume: broker did not return a message id"))
  | otherwise = do
      path <- pendingAckPath settings topic payload
      createDirectoryIfMissing True =<< pendingAckDirectory
      ByteString.writeFile
        path
        ( Text.Encoding.encodeUtf8 $
            Text.unlines
              [ "ack-url: " <> ackUrl
              , "message-id: " <> messageId
              ]
        )
      pure (Right ())

lookupPendingAck
  :: PulsarWebSocketSettings -> TopicName -> Text -> IO (Either ServiceError (Text, Text, FilePath))
lookupPendingAck settings topic payload = do
  path <- pendingAckPath settings topic payload
  exists <- doesFileExist path
  if exists
    then do
      record <- Text.Encoding.decodeUtf8With TextErr.lenientDecode <$> ByteString.readFile path
      case parsePendingAckRecord record of
        Just (ackUrl, messageId) -> pure (Right (ackUrl, messageId, path))
        Nothing -> pure (Left (SETransient "pulsarAcknowledge: malformed pending ack record"))
    else pure (Left (SETransient "pulsarAcknowledge: no pending message id for payload"))

parsePendingAckRecord :: Text -> Maybe (Text, Text)
parsePendingAckRecord record = do
  let fields = fmap parseRecordField (Text.lines record)
      value key = lookup key fields
  (,) <$> value "ack-url" <*> value "message-id"

parseRecordField :: Text -> (Text, Text)
parseRecordField line =
  let (key, rest) = Text.breakOn ":" line
   in (Text.strip key, Text.strip (Text.drop 1 rest))

pendingAckPath :: PulsarWebSocketSettings -> TopicName -> Text -> IO FilePath
pendingAckPath settings topic payload = do
  directory <- pendingAckDirectory
  pure (directory </> pendingAckKey settings topic payload)

pendingAckDirectory :: IO FilePath
pendingAckDirectory = do
  tempRoot <- getTemporaryDirectory
  pure (tempRoot </> "jitml-pulsar-acks")

pendingAckKey :: PulsarWebSocketSettings -> TopicName -> Text -> FilePath
pendingAckKey settings topic payload =
  concatMap byteHexUpper (ByteString.unpack (SHA256.hash rawKey))
 where
  rawKey =
    Text.Encoding.encodeUtf8 $
      Text.intercalate
        "\n"
        [ pulsarWebSocketEndpoint settings
        , unTopicName topic
        , payload
        ]

byteHexUpper :: Word8 -> String
byteHexUpper byte =
  let value = fromIntegral byte
   in [intToHexUpper (value `div` 16), intToHexUpper (value `mod` 16)]

producerUrl :: PulsarWebSocketSettings -> TopicName -> Text
producerUrl settings topic =
  stripTrailingSlash (pulsarWebSocketEndpoint settings) <> "/v2/producer/" <> topicPath topic

consumerUrl :: PulsarWebSocketSettings -> SubscriptionId -> Text
consumerUrl settings =
  consumerUrlWithReceiverQueue settings 1

subscriptionProbeUrl :: PulsarWebSocketSettings -> SubscriptionId -> Text
subscriptionProbeUrl settings =
  consumerUrlWithReceiverQueue settings 0

consumerUrlWithReceiverQueue :: PulsarWebSocketSettings -> Int -> SubscriptionId -> Text
consumerUrlWithReceiverQueue settings receiverQueueSize subscription =
  stripTrailingSlash (pulsarWebSocketEndpoint settings)
    <> "/v2/consumer/"
    <> topicPath (TopicName (subscriptionTopic subscription))
    <> "/"
    <> pathSegment (subscriptionName subscription)
    <> "?subscriptionType=Exclusive&receiverQueueSize="
    <> Text.pack (show receiverQueueSize)
    <> "&ackTimeoutMillis=30000"
    <> "&negativeAckRedeliveryDelay=1000"

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
    Nothing
      | "/" `Text.isInfixOf` topic ->
          Text.intercalate "/" (fmap pathSegment (Text.splitOn "/" topic))
      | otherwise ->
          "persistent/public/default/" <> pathSegment topic

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

websocketEndpointFromServiceUrl :: Text -> Text
websocketEndpointFromServiceUrl =
  appendWebsocketPath . toWebsocketScheme . stripTrailingSlash

toWebsocketScheme :: Text -> Text
toWebsocketScheme endpoint
  | Just rest <- Text.stripPrefix "pulsar://" endpoint = "ws://" <> rest
  | Just rest <- Text.stripPrefix "http://" endpoint = "ws://" <> rest
  | Just rest <- Text.stripPrefix "https://" endpoint = "wss://" <> rest
  | otherwise = endpoint

appendWebsocketPath :: Text -> Text
appendWebsocketPath endpoint
  | "/ws" `Text.isSuffixOf` endpoint = endpoint
  | "/pulsar" `Text.isSuffixOf` endpoint = endpoint <> "/ws"
  | otherwise = endpoint <> "/ws"

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
    , "const WebSocketCtor = globalThis.WebSocket || require('undici').WebSocket;"
    , "const [url, payloadPath, outputPath] = process.argv.slice(1);"
    , "const payload = fs.readFileSync(payloadPath);"
    , "const ws = new WebSocketCtor(url);"
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
    , "const WebSocketCtor = globalThis.WebSocket || require('undici').WebSocket;"
    , "const [url, outputPath] = process.argv.slice(1);"
    , "const ws = new WebSocketCtor(url);"
    , "let settled = false;"
    , "const timer = setTimeout(() => { console.error('timeout'); process.exit(2); }, 15000);"
    , "ws.addEventListener('message', (event) => {"
    , "  settled = true;"
    , "  const message = JSON.parse(String(event.data));"
    , "  const payload = Buffer.from(message.payload || '', 'base64').toString('utf8');"
    , "  fs.writeFileSync(outputPath, `message-id: ${message.messageId || ''}\\n${payload}`);"
    , "  clearTimeout(timer);"
    , "  ws.close();"
    , "  process.exit(0);"
    , "});"
    , "ws.addEventListener('error', (event) => { clearTimeout(timer); console.error(event.message || 'websocket error'); process.exit(1); });"
    , "ws.addEventListener('close', (event) => {"
    , "  if (!settled) { clearTimeout(timer); console.error(`closed before message: ${event.code} ${event.reason || ''}`); process.exit(1); }"
    , "});"
    ]

consumerWorkerScript :: Text
consumerWorkerScript =
  Text.unlines
    [ "const WebSocketCtor = globalThis.WebSocket || require('undici').WebSocket;"
    , "const [url] = process.argv.slice(1);"
    , "const ws = new WebSocketCtor(url);"
    , "let ackBuffer = '';"
    , "process.stdin.setEncoding('utf8');"
    , "process.stdin.on('data', (chunk) => {"
    , "  ackBuffer += chunk;"
    , "  const lines = ackBuffer.split('\\n');"
    , "  ackBuffer = lines.pop() || '';"
    , "  for (const line of lines) {"
    , "    const raw = line.trim();"
    , "    if (raw.length === 0) { continue; }"
    , "    try {"
    , "      const command = JSON.parse(raw);"
    , "      if (command.type === 'negativeAcknowledge' && command.messageId) {"
    , "        ws.send(JSON.stringify({ type: 'negativeAcknowledge', messageId: command.messageId }));"
    , "      } else if (command.messageId) {"
    , "        ws.send(JSON.stringify({ messageId: command.messageId }));"
    , "      }"
    , "    } catch (_err) {"
    , "      const messageId = raw;"
    , "      ws.send(JSON.stringify({ messageId }));"
    , "    }"
    , "  }"
    , "});"
    , "ws.addEventListener('message', (event) => {"
    , "  const message = JSON.parse(String(event.data));"
    , "  const payload = Buffer.from(message.payload || '', 'base64').toString('utf8');"
    , "  process.stdout.write(JSON.stringify({ messageId: message.messageId || '', payload }) + '\\n');"
    , "});"
    , "ws.addEventListener('error', (event) => { console.error(event.message || 'websocket error'); process.exit(1); });"
    , "ws.addEventListener('close', (event) => { console.error(`consumer closed: ${event.code} ${event.reason || ''}`); process.exit(1); });"
    ]

acknowledgeScript :: Text
acknowledgeScript =
  Text.unlines
    [ "const fs = require('fs');"
    , "const WebSocketCtor = globalThis.WebSocket || require('undici').WebSocket;"
    , "const [url, messageId, outputPath] = process.argv.slice(1);"
    , "const ws = new WebSocketCtor(url);"
    , "let opened = false;"
    , "const timer = setTimeout(() => { console.error('timeout'); process.exit(2); }, 10000);"
    , "ws.addEventListener('open', () => {"
    , "  opened = true;"
    , "  ws.send(JSON.stringify({ messageId }));"
    , "  fs.writeFileSync(outputPath, 'ok');"
    , "  clearTimeout(timer);"
    , "  setTimeout(() => { ws.close(); process.exit(0); }, 100);"
    , "});"
    , "ws.addEventListener('error', (event) => { clearTimeout(timer); console.error(event.message || 'websocket error'); process.exit(1); });"
    , "ws.addEventListener('close', (event) => {"
    , "  if (!opened) { clearTimeout(timer); console.error(`closed before ack open: ${event.code} ${event.reason || ''}`); process.exit(1); }"
    , "});"
    ]

subscribeScript :: Text
subscribeScript =
  Text.unlines
    [ "const fs = require('fs');"
    , "const WebSocketCtor = globalThis.WebSocket || require('undici').WebSocket;"
    , "const [url, topic, subscription, outputPath] = process.argv.slice(1);"
    , "const ws = new WebSocketCtor(url);"
    , "let opened = false;"
    , "const timer = setTimeout(() => { console.error('timeout'); process.exit(2); }, 10000);"
    , "ws.addEventListener('open', () => {"
    , "  opened = true;"
    , "  fs.writeFileSync(outputPath, `${topic}\\n${subscription}`);"
    , "  clearTimeout(timer);"
    , "  ws.close();"
    , "  process.exit(0);"
    , "});"
    , "ws.addEventListener('error', (event) => { clearTimeout(timer); console.error(event.message || 'websocket error'); process.exit(1); });"
    , "ws.addEventListener('close', (event) => {"
    , "  if (!opened) { clearTimeout(timer); console.error(`closed before subscription open: ${event.code} ${event.reason || ''}`); process.exit(1); }"
    , "});"
    ]
