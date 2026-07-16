-- | Sprint 13.13 — browser-side WebSocket subscription glue. Opens a
-- | held-open `/api/ws/<domain>` connection to the demo server's
-- | Pulsar→WebSocket bridge and feeds each received text frame into the
-- | calling Halogen component's action queue via a `Halogen.Subscription`
-- | emitter. The demo server (`JitML.Web.Server.serveDemoWithBridge`)
-- | forwards each broker delivery as a WebSocket text frame; this module
-- | is the matching `onmessage`→typed-`Action` bridge on the client.
module Panels.Stream
  ( subscribeStream
  , openWebSocket
  ) where

import Prelude

import Effect (Effect)
import Effect.Aff.Class (class MonadAff)
import Halogen as H
import Halogen.Subscription as HS

-- | Open a WebSocket to `path` (resolved against the current page origin,
-- | upgrading `http`→`ws` / `https`→`wss`) and invoke the callbacks with
-- | text-frame payloads or connection failures. The returned cleanup closes
-- | the socket and detaches its callbacks.
foreign import openWebSocket :: String -> (String -> Effect Unit) -> (String -> Effect Unit) -> Effect (Effect Unit)

-- | Subscribe the calling component to a `/api/ws/<domain>` stream. Each
-- | received frame payload is mapped to a typed `Action` via `toAction`
-- | and dispatched into the component's action queue.
subscribeStream
  :: forall state action slots output m
   . MonadAff m
  => String
  -> (String -> action)
  -> (String -> action)
  -> H.HalogenM state action slots output m Unit
subscribeStream path toAction toFailure = do
  _ <-
    H.subscribe $ HS.makeEmitter \notify ->
      openWebSocket path
        (notify <<< toAction)
        (notify <<< toFailure)
  pure unit
