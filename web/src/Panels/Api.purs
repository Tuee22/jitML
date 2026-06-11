module Panels.Api
  ( requestText
  ) where

import Prelude

import Effect (Effect)
import Effect.Aff.Class (class MonadAff)
import Effect.Class (liftEffect)
import Halogen as H
import Halogen.Subscription as HS

foreign import requestTextImpl
  :: String
  -> String
  -> String
  -> (String -> Effect Unit)
  -> (String -> Effect Unit)
  -> Effect Unit

requestText
  :: forall state action slots output m
   . MonadAff m
  => String
  -> String
  -> String
  -> (String -> action)
  -> (String -> action)
  -> H.HalogenM state action slots output m Unit
requestText method path body toSuccess toFailure = do
  io <- liftEffect HS.create
  _ <- H.subscribe io.emitter
  liftEffect
    ( requestTextImpl method path body
        (\payload -> HS.notify io.listener (toSuccess payload))
        (\message -> HS.notify io.listener (toFailure message))
    )
