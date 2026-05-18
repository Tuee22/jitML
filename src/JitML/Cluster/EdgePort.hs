{-# LANGUAGE OverloadedStrings #-}

module JitML.Cluster.EdgePort
  ( EdgePortLease (..)
  , defaultPortCandidates
  , leaseEdgePort
  )
where

import Control.Exception (SomeException, bracket, try)
import Network.Socket
  ( SocketType (Stream)
  , bind
  , close
  , defaultHints
  , defaultProtocol
  , getAddrInfo
  , socket
  )
import Network.Socket qualified as Socket

data EdgePortLease = EdgePortLease
  { leasedPort :: Int
  , leasedHost :: String
  }
  deriving stock (Eq, Show)

-- | The canonical port candidates the substrate publication layer walks
-- in order. The exit definition requires exactly one
-- `127.0.0.1:<edge-port>` socket per substrate; 9090 is the documented
-- default. The reconciler falls through 9091 / 9092 if 9090 is taken
-- (e.g. another local Kind cluster is up).
defaultPortCandidates :: [Int]
defaultPortCandidates = [9090, 9091, 9092]

-- | Try each candidate port in order; the first one that can be bound to
-- `127.0.0.1` wins. The returned `EdgePortLease` is then written into
-- `./.build/runtime/cluster-publication.json`. The socket is closed
-- immediately so the lease is purely a "this address is bindable right
-- now" probe; the real listener (Envoy Gateway) binds later.
leaseEdgePort :: [Int] -> IO (Maybe EdgePortLease)
leaseEdgePort = go
 where
  go [] = pure Nothing
  go (candidate : rest) = do
    result <- try (probe candidate) :: IO (Either SomeException ())
    case result of
      Left _ -> go rest
      Right () ->
        pure (Just EdgePortLease {leasedPort = candidate, leasedHost = "127.0.0.1"})

  probe port = do
    let hints = defaultHints {Socket.addrSocketType = Stream}
    addresses <- getAddrInfo (Just hints) (Just "127.0.0.1") (Just (show port))
    case addresses of
      [] -> error ("no address for 127.0.0.1:" <> show port)
      addr : _ ->
        bracket
          (socket (Socket.addrFamily addr) (Socket.addrSocketType addr) defaultProtocol)
          close
          ( \sock -> do
              bind sock (Socket.addrAddress addr)
              pure ()
          )
