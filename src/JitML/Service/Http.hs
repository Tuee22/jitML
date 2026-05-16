{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.Http
  ( HttpRoute (..)
  , serveHttpRoutes
  , serveHttpRoutesOnce
  , withHttpRoutesOnce
  )
where

import Control.Concurrent (forkFinally)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import Control.Exception (bracket)
import Control.Monad (forever, void)
import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as Char8
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
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

data HttpRoute = HttpRoute
  { httpRouteMethod :: Text
  , httpRoutePath :: Text
  , httpRouteContentType :: Text
  , httpRouteResponse :: EndpointResponse
  }
  deriving stock (Eq, Show)

serveHttpRoutes :: HttpListener -> [HttpRoute] -> IO ()
serveHttpRoutes listener routes =
  withListener listener $ \(listenerSocket, _actualPort) ->
    forever (serveAcceptedConnection listenerSocket routes)

serveHttpRoutesOnce :: HttpListener -> [HttpRoute] -> IO ()
serveHttpRoutesOnce listener routes =
  withListener listener $ \(listenerSocket, _actualPort) ->
    serveAcceptedConnection listenerSocket routes

withHttpRoutesOnce :: HttpListener -> [HttpRoute] -> (Int -> IO a) -> IO a
withHttpRoutesOnce listener routes action =
  withListener listener $ \(listenerSocket, actualPort) -> do
    done <- newEmptyMVar
    void $
      forkFinally
        (serveAcceptedConnection listenerSocket routes)
        (\_result -> putMVar done ())
    result <- action actualPort
    takeMVar done
    pure result

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

serveAcceptedConnection :: Socket -> [HttpRoute] -> IO ()
serveAcceptedConnection listenerSocket routes =
  bracket (accept listenerSocket) (close . fst) $ \(connection, _peer) -> do
    request <- recv connection 4096
    sendAll connection (responseFor routes request)

responseFor :: [HttpRoute] -> ByteString.ByteString -> ByteString.ByteString
responseFor routes request =
  case parseRequest request of
    Just (method, path) ->
      case findRoute method path routes of
        Just route -> renderResponse (httpRouteContentType route) (httpRouteResponse route)
        Nothing -> renderResponse "text/plain; charset=utf-8" (EndpointResponse 404 "not found\n")
    Nothing ->
      renderResponse "text/plain; charset=utf-8" (EndpointResponse 400 "bad request\n")

findRoute :: Text -> Text -> [HttpRoute] -> Maybe HttpRoute
findRoute method path =
  firstMatch
 where
  firstMatch [] = Nothing
  firstMatch (route : rest)
    | httpRouteMethod route == method && httpRoutePath route == path = Just route
    | otherwise = firstMatch rest

parseRequest :: ByteString.ByteString -> Maybe (Text, Text)
parseRequest request =
  case Char8.words <$> firstLine request of
    Just (method : rawPath : _) ->
      Just
        ( Text.Encoding.decodeUtf8 method
        , stripQuery (Text.Encoding.decodeUtf8 rawPath)
        )
    _ -> Nothing
 where
  firstLine bytes =
    case Char8.lines bytes of
      line : _ -> Just line
      [] -> Nothing

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
