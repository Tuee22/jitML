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
import Effect.Class (liftEffect)
import Halogen as H
import Halogen.Subscription as HS

-- | Open a WebSocket to `path` (resolved against the current page origin,
-- | upgrading `http`→`ws` / `https`→`wss`) and invoke the callback with
-- | each text-frame payload. Best-effort: connection failures are
-- | swallowed so the demo keeps rendering its deterministic shell.
foreign import openWebSocket :: String -> (String -> Effect Unit) -> Effect Unit

-- | Subscribe the calling component to a `/api/ws/<domain>` stream. Each
-- | received frame payload is mapped to a typed `Action` via `toAction`
-- | and dispatched into the component's action queue.
subscribeStream
  :: forall state action slots output m
   . MonadAff m
  => String
  -> (String -> action)
  -> H.HalogenM state action slots output m Unit
subscribeStream path toAction = do
  io <- liftEffect HS.create
  _ <- H.subscribe io.emitter
  liftEffect (openWebSocket path (\payload -> HS.notify io.listener (toAction payload)))
