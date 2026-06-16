{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.Http
  ( HttpRoute (..)
  , HttpRequest (..)
  , WebSocketRoute (..)
  , serveHttpRoutes
  , serveHttpRoutesOnce
  , serveHttpRoutesWithWebSockets
  , withHttpRoutesOnce
  , withHttpRoutesWithWebSockets
  )
where

import Control.Concurrent (forkFinally, killThread)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import Control.Exception (bracket)
import Control.Exception qualified
import Control.Monad (forever, void)
import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as Char8
import Data.Char qualified as Char
import Data.Maybe (fromMaybe, listToMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Text.Encoding.Error qualified as TextErr
import Network.Socket
  ( AddrInfo (..)
  , AddrInfoFlag (AI_PASSIVE)
  , Family (AF_INET)
  , HostName
  , PortNumber
  , ServiceName
  , SockAddr (SockAddrInet)
  , Socket
  , SocketOption (ReuseAddr)
  , SocketType (Stream)
  , accept
  , bind
  , close
  , defaultHints
  , getAddrInfo
  , getSocketName
  , listen
  , setSocketOption
  , socket
  , withSocketsDo
  )
import Network.Socket.ByteString (recv, sendAll)

import JitML.Service.BootConfig (HttpListener (..))
import JitML.Service.Endpoints (EndpointResponse (..))
import JitML.Service.WebSocket
  ( WebSocketUpgrade (..)
  , detectWebSocketUpgrade
  , encodeCloseFrame
  , encodeTextFrame
  , renderUpgradeAccept
  )

data HttpRoute = HttpRoute
  { httpRouteMethod :: Text
  , httpRoutePath :: Text
  , httpRouteContentType :: Text
  , httpRouteHandler :: HttpRequest -> IO EndpointResponse
  }

data HttpRequest = HttpRequest
  { httpRequestMethod :: Text
  , httpRequestPath :: Text
  , httpRequestBody :: Text
  }
  deriving stock (Eq, Show)

-- | Sprint 13.13 — a WebSocket route paired with a streaming bridge
-- callback. After the HTTP upgrade handshake the listener invokes
-- 'webSocketRouteHandler' with a typed @writeFrame :: Text -> IO Bool@
-- callback the handler uses to publish text frames downstream. The
-- callback returns 'False' when the client has disconnected so the
-- bridge can exit its consumer loop cleanly.
data WebSocketRoute = WebSocketRoute
  { webSocketRoutePath :: Text
  , webSocketRouteHandler :: (Text -> IO Bool) -> IO ()
  }

serveHttpRoutes :: HttpListener -> [HttpRoute] -> IO ()
serveHttpRoutes listener routes =
  serveHttpRoutesWithWebSockets listener routes []

-- | Sprint 13.13 — serve the demo over HTTP and bridge any matching
-- WebSocket-upgrade requests to the per-domain consumer callbacks. The
-- non-WS routes still go through the one-request-one-response path
-- the rest of the demo uses.
serveHttpRoutesWithWebSockets
  :: HttpListener -> [HttpRoute] -> [WebSocketRoute] -> IO ()
serveHttpRoutesWithWebSockets listener routes wsRoutes =
  withListener listener $ \(listenerSocket, _actualPort) ->
    forever (serveAcceptedConnectionForked listenerSocket routes wsRoutes)

serveHttpRoutesOnce :: HttpListener -> [HttpRoute] -> IO ()
serveHttpRoutesOnce listener routes =
  withListener listener $ \(listenerSocket, _actualPort) ->
    serveAcceptedConnection listenerSocket routes []

withHttpRoutesOnce :: HttpListener -> [HttpRoute] -> (Int -> IO a) -> IO a
withHttpRoutesOnce listener routes action =
  withListener listener $ \(listenerSocket, actualPort) -> do
    done <- newEmptyMVar
    void $
      forkFinally
        (serveAcceptedConnection listenerSocket routes [])
        (\_result -> putMVar done ())
    result <- action actualPort
    takeMVar done
    pure result

withHttpRoutesWithWebSockets
  :: HttpListener -> [HttpRoute] -> [WebSocketRoute] -> (Int -> IO a) -> IO a
withHttpRoutesWithWebSockets listener routes wsRoutes action =
  withListener listener $ \(listenerSocket, actualPort) ->
    bracket
      ( forkFinally
          (forever (serveAcceptedConnectionForked listenerSocket routes wsRoutes))
          (const (pure ()))
      )
      killThread
      (const (action actualPort))

withListener :: HttpListener -> ((Socket, Int) -> IO a) -> IO a
withListener listener =
  bracket (openListener listener) (close . fst)

openListener :: HttpListener -> IO (Socket, Int)
openListener listener =
  withSocketsDo $ do
    addresses <- getAddrInfo (Just hints) host service
    case addresses of
      [] -> ioError (userError "no address available for jitML HTTP listener")
      addr : _ -> do
        listenerSocket <- socket (addrFamily addr) (addrSocketType addr) (addrProtocol addr)
        setSocketOption listenerSocket ReuseAddr 1
        bind listenerSocket (addrAddress addr)
        listen listenerSocket 16
        actualPort <- socketPort listenerSocket
        pure (listenerSocket, actualPort)
 where
  hints =
    defaultHints
      { addrFlags = [AI_PASSIVE]
      , addrFamily = AF_INET
      , addrSocketType = Stream
      }

  host :: Maybe HostName
  host =
    Just (Text.unpack (listenerHost listener))

  service :: Maybe ServiceName
  service =
    Just (show (listenerPort listener))

socketPort :: Socket -> IO Int
socketPort listenerSocket = do
  socketName <- getSocketName listenerSocket
  case socketName of
    SockAddrInet port _ -> pure (portNumberToInt port)
    _ -> pure 0

portNumberToInt :: PortNumber -> Int
portNumberToInt =
  fromIntegral

serveAcceptedConnection :: Socket -> [HttpRoute] -> [WebSocketRoute] -> IO ()
serveAcceptedConnection listenerSocket routes wsRoutes =
  bracket (accept listenerSocket) (close . fst) $ \(connection, _peer) ->
    serveConnection connection routes wsRoutes

serveAcceptedConnectionForked :: Socket -> [HttpRoute] -> [WebSocketRoute] -> IO ()
serveAcceptedConnectionForked listenerSocket routes wsRoutes = do
  (connection, _peer) <- accept listenerSocket
  void $
    forkFinally
      (serveConnection connection routes wsRoutes)
      (const (close connection))

serveConnection :: Socket -> [HttpRoute] -> [WebSocketRoute] -> IO ()
serveConnection connection routes wsRoutes = do
  request <- recvHttpRequest connection
  case wsRouteFor request wsRoutes of
    Just (route, acceptKey) -> do
      sendAll connection (renderUpgradeAccept acceptKey)
      runWebSocketHandler connection route
    Nothing ->
      responseFor routes request >>= sendAll connection

wsRouteFor
  :: ByteString.ByteString -> [WebSocketRoute] -> Maybe (WebSocketRoute, ByteString.ByteString)
wsRouteFor request wsRoutes =
  case parseRequest request of
    Just parsedRequest | httpRequestMethod parsedRequest == "GET" ->
      case [route | route <- wsRoutes, webSocketRoutePath route == httpRequestPath parsedRequest] of
        route : _ ->
          case detectWebSocketUpgrade request of
            UpgradeAccepted acceptKey -> Just (route, acceptKey)
            NoUpgrade -> Nothing
        [] -> Nothing
    _ -> Nothing

-- | After the upgrade handshake, run the route's handler against a
-- @write :: Text -> IO Bool@ callback that pushes one server-side text
-- frame per call. The callback returns 'False' on a write failure
-- (client disconnected) so the bridge exits its consumer loop. A
-- close frame is sent on a clean exit.
runWebSocketHandler :: Socket -> WebSocketRoute -> IO ()
runWebSocketHandler connection route = do
  let writeFrame payload = do
        sendAllSafe connection (encodeTextFrame payload)
  webSocketRouteHandler route writeFrame
  _ <- sendAllSafe connection encodeCloseFrame
  pure ()

-- | Send all bytes through the socket; return 'True' on success,
-- 'False' on any 'IOException' so the bridge cleanly exits without
-- swallowing the error.
sendAllSafe :: Socket -> ByteString.ByteString -> IO Bool
sendAllSafe connection bytes =
  Control.Exception.catch
    (sendAll connection bytes >> pure True)
    (\(_ :: Control.Exception.IOException) -> pure False)

responseFor :: [HttpRoute] -> ByteString.ByteString -> IO ByteString.ByteString
responseFor routes request =
  case parseRequest request of
    Just parsedRequest ->
      case findRoute (httpRequestMethod parsedRequest) (httpRequestPath parsedRequest) routes of
        Just route -> do
          response <- httpRouteHandler route parsedRequest
          pure (renderResponse (httpRouteContentType route) response)
        Nothing -> pure (renderResponse "text/plain; charset=utf-8" (EndpointResponse 404 "not found\n"))
    Nothing ->
      pure (renderResponse "text/plain; charset=utf-8" (EndpointResponse 400 "bad request\n"))

findRoute :: Text -> Text -> [HttpRoute] -> Maybe HttpRoute
findRoute method path =
  firstMatch
 where
  firstMatch [] = Nothing
  firstMatch (route : rest)
    | httpRouteMethod route == method && routePathMatches (httpRoutePath route) path = Just route
    | otherwise = firstMatch rest

routePathMatches :: Text -> Text -> Bool
routePathMatches template path
  | template == path = True
  | template == "/api/runs/{runId}/command" =
      "/api/runs/" `Text.isPrefixOf` path
        && "/command" `Text.isSuffixOf` path
        && Text.length path > Text.length "/api/runs//command"
  | otherwise = False

recvHttpRequest :: Socket -> IO ByteString.ByteString
recvHttpRequest connection =
  readMore ByteString.empty
 where
  maxRequestBytes = 65536

  readMore acc = do
    chunk <- recv connection 4096
    let next = acc <> chunk
    case completeRequestLength next of
      Just expected
        | ByteString.length next >= expected -> pure next
      _ | ByteString.null chunk -> pure next
      _ | ByteString.length next >= maxRequestBytes -> pure next
      _ -> readMore next

completeRequestLength :: ByteString.ByteString -> Maybe Int
completeRequestLength bytes =
  case ByteString.breakSubstring "\r\n\r\n" bytes of
    (_headers, rest)
      | ByteString.null rest -> Nothing
    (headers, _rest) ->
      Just (ByteString.length headers + 4 + contentLength headers)

contentLength :: ByteString.ByteString -> Int
contentLength headers =
  fromMaybe 0 $
    listToMaybe
      [ lengthValue
      | line <- Char8.lines headers
      , let (name, valueWithColon) = Char8.break (== ':') line
      , lowercaseAscii name == "content-length"
      , Just lengthValue <-
          [readMaybeInt (Char8.unpack (Char8.dropWhile isHeaderSpace (Char8.drop 1 valueWithColon)))]
      ]

lowercaseAscii :: ByteString.ByteString -> ByteString.ByteString
lowercaseAscii =
  Char8.map Char.toLower

isHeaderSpace :: Char -> Bool
isHeaderSpace char =
  char == ' ' || char == '\t' || char == '\r'

readMaybeInt :: String -> Maybe Int
readMaybeInt text =
  case reads text of
    [(value, rest)] | all isHeaderSpace rest -> Just value
    _ -> Nothing

parseRequest :: ByteString.ByteString -> Maybe HttpRequest
parseRequest request =
  case Char8.words <$> firstLine request of
    Just (method : rawPath : _) ->
      Just
        HttpRequest
          { httpRequestMethod = Text.Encoding.decodeUtf8 method
          , httpRequestPath = stripQuery (Text.Encoding.decodeUtf8 rawPath)
          , httpRequestBody = requestBodyText request
          }
    _ -> Nothing
 where
  firstLine bytes =
    case Char8.lines bytes of
      line : _ -> Just line
      [] -> Nothing

requestBodyText :: ByteString.ByteString -> Text
requestBodyText request =
  case ByteString.breakSubstring "\r\n\r\n" request of
    (_headers, rest)
      | ByteString.null rest -> ""
      | otherwise ->
          Text.Encoding.decodeUtf8With TextErr.lenientDecode (ByteString.drop 4 rest)

stripQuery :: Text -> Text
stripQuery =
  Text.takeWhile (/= '?')

renderResponse :: Text -> EndpointResponse -> ByteString.ByteString
renderResponse contentType response =
  ByteString.concat
    [ Text.Encoding.encodeUtf8 statusLine
    , Text.Encoding.encodeUtf8 ("Content-Type: " <> contentType <> "\r\n")
    , Text.Encoding.encodeUtf8 ("Content-Length: " <> Text.pack (show (ByteString.length body)) <> "\r\n")
    , "Connection: close\r\n"
    , "\r\n"
    , body
    ]
 where
  statusLine =
    "HTTP/1.1 "
      <> Text.pack (show (endpointStatus response))
      <> " "
      <> statusText (endpointStatus response)
      <> "\r\n"
  body = Text.Encoding.encodeUtf8 (endpointBody response)

statusText :: Int -> Text
statusText 200 = "OK"
statusText 400 = "Bad Request"
statusText 404 = "Not Found"
statusText 503 = "Service Unavailable"
statusText _ = "OK"
