{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.Retry
  ( RetryPolicy (..)
  , ServiceError (..)
  , renderRetryPolicyDhall
  , retryPolicyDecoder
  , retryScheduleMillis
  , retryServiceAction
  , retryServiceActionEither
  , retryServiceActionWith
  , serviceErrorPermanent
  , serviceErrorToAppError
  )
where

import Control.Concurrent (threadDelay)
import Data.Either.Combinators (mapLeft)
import Data.Text (Text)
import Data.Text qualified as Text
import Dhall qualified
import GHC.Clock (getMonotonicTimeNSec)
import Numeric.Natural (Natural)

import JitML.AppError.AppError (AppError (..))

data RetryPolicy
  = Once
  | LinearN Natural Natural
  | ExponentialN Natural Natural Natural
  | RetryUntil Natural
  deriving stock (Eq, Show)

data ServiceError
  = SEConflict Text
  | SEUnauthorized Text
  | SETimeout Text
  | SETransient Text
  | -- | The addressed object does not exist. Distinct from 'SEUnauthorized'
    -- because absence is terminal: retrying or redelivering cannot make an
    -- object appear, whereas a 401/403 can clear once credentials or clock
    -- skew resolve. Callers that settle work use 'serviceErrorPermanent' to
    -- tell those apart.
    SENotFound Text
  deriving stock (Eq, Show)

renderRetryPolicyDhall :: RetryPolicy -> Text
renderRetryPolicyDhall Once = retryPolicyDhallType <> ".Once"
renderRetryPolicyDhall (LinearN attempts delayMillis) =
  retryPolicyDhallType
    <> ".LinearN { attempts = "
    <> showText attempts
    <> ", delayMillis = "
    <> showText delayMillis
    <> " }"
renderRetryPolicyDhall (ExponentialN attempts baseMillis capMillis) =
  retryPolicyDhallType
    <> ".ExponentialN { attempts = "
    <> showText attempts
    <> ", baseMillis = "
    <> showText baseMillis
    <> ", capMillis = "
    <> showText capMillis
    <> " }"
renderRetryPolicyDhall (RetryUntil deadlineMillis) =
  retryPolicyDhallType
    <> ".RetryUntil { deadlineMillis = "
    <> showText deadlineMillis
    <> " }"

retryPolicyDhallType :: Text
retryPolicyDhallType =
  Text.intercalate
    " "
    [ "< Once"
    , "| LinearN : { attempts : Natural, delayMillis : Natural }"
    , "| ExponentialN : { attempts : Natural, baseMillis : Natural, capMillis : Natural }"
    , "| RetryUntil : { deadlineMillis : Natural }"
    , ">"
    ]

-- | Decoder shared by the reflected LiveConfig schema and the real SIGHUP
-- loader. Keeping the Dhall Naturals as Naturals prevents an oversized value
-- from wrapping through an unchecked @Natural -> Int@ conversion.
retryPolicyDecoder :: Dhall.Decoder RetryPolicy
retryPolicyDecoder =
  Dhall.union $
    Dhall.constructor "Once" (Once <$ Dhall.unit)
      <> Dhall.constructor "LinearN" linearN
      <> Dhall.constructor "ExponentialN" exponentialN
      <> Dhall.constructor "RetryUntil" retryUntil
 where
  linearN =
    Dhall.record
      ( LinearN
          <$> Dhall.field "attempts" Dhall.natural
          <*> Dhall.field "delayMillis" Dhall.natural
      )
  exponentialN =
    Dhall.record
      ( ExponentialN
          <$> Dhall.field "attempts" Dhall.natural
          <*> Dhall.field "baseMillis" Dhall.natural
          <*> Dhall.field "capMillis" Dhall.natural
      )
  retryUntil =
    Dhall.record (RetryUntil <$> Dhall.field "deadlineMillis" Dhall.natural)

-- | Delays before each bounded retry. This makes the production scheduler
-- independently testable without sleeping. @attempts@ retains the historical
-- meaning used by the service: total attempts, including the first call.
retryScheduleMillis :: RetryPolicy -> [Natural]
retryScheduleMillis policy =
  case policy of
    Once -> []
    LinearN attempts delayMillis ->
      replicateNatural (attempts `minusNatural` 1) delayMillis
    ExponentialN attempts baseMillis capMillis ->
      takeNatural
        (attempts `minusNatural` 1)
        (iterate (cappedDouble capMillis) (min baseMillis capMillis))
    RetryUntil _deadlineMillis -> []

retryServiceAction
  :: RetryPolicy -> (env -> IO (Either ServiceError a)) -> env -> IO (Either AppError a)
retryServiceAction policy action env =
  mapLeft serviceErrorToAppError
    <$> retryServiceActionEither policy action env

-- | Run a retryable service operation while preserving its typed service
-- error. This is the boundary used by Coordinator reconciliation, where the
-- caller must retain the exact failed operation in its readiness evidence.
retryServiceActionEither
  :: RetryPolicy -> (env -> IO (Either ServiceError a)) -> env -> IO (Either ServiceError a)
retryServiceActionEither =
  retryServiceActionWith monotonicMillis sleepMillis

-- | Testable retry interpreter. The injected monotonic clock is measured in
-- milliseconds and the sleeper receives milliseconds, so schedule tests never
-- need wall-clock sleeps. Non-retryable errors always stop immediately.
retryServiceActionWith
  :: IO Natural
  -> (Natural -> IO ())
  -> RetryPolicy
  -> (env -> IO (Either ServiceError a))
  -> env
  -> IO (Either ServiceError a)
retryServiceActionWith currentMillis sleep policy action env = do
  startedMillis <- currentMillis
  go startedMillis (retryScheduleMillis policy)
 where
  go startedMillis delays = do
    result <- action env
    case result of
      Right value -> pure (Right value)
      Left err
        | not (retryableServiceError err) ->
            pure (Left err)
        | otherwise -> do
            retryDelay <- nextRetryDelay startedMillis delays
            case retryDelay of
              Nothing -> pure (Left err)
              Just (delayMillis, remainingDelays) -> do
                sleep delayMillis
                retryStillWithinDeadline <- retryAllowed startedMillis
                if retryStillWithinDeadline
                  then go startedMillis remainingDelays
                  else pure (Left err)
  nextRetryDelay startedMillis delays =
    case policy of
      RetryUntil deadlineMillis -> do
        nowMillis <- currentMillis
        let elapsedMillis = nowMillis `minusNatural` startedMillis
            remainingMillis = deadlineMillis `minusNatural` elapsedMillis
        pure $
          if remainingMillis == 0
            then Nothing
            else Just (min retryUntilPollMillis remainingMillis, [])
      _ ->
        pure $
          case delays of
            [] -> Nothing
            delayMillis : rest -> Just (delayMillis, rest)
  retryAllowed startedMillis =
    case policy of
      RetryUntil deadlineMillis -> do
        nowMillis <- currentMillis
        pure (nowMillis `minusNatural` startedMillis < deadlineMillis)
      _ -> pure True

monotonicMillis :: IO Natural
monotonicMillis =
  fromIntegral . (`div` 1000000) <$> getMonotonicTimeNSec

retryUntilPollMillis :: Natural
retryUntilPollMillis = 10

sleepMillis :: Natural -> IO ()
sleepMillis delayMillis =
  threadDelay (boundedMicros delayMillis)

boundedMicros :: Natural -> Int
boundedMicros millis =
  fromInteger
    ( min
        (toInteger (maxBound :: Int))
        (toInteger millis * 1000)
    )

cappedDouble :: Natural -> Natural -> Natural
cappedDouble cap value =
  min cap (value * 2)

minusNatural :: Natural -> Natural -> Natural
minusNatural left right
  | left <= right = 0
  | otherwise = left - right

replicateNatural :: Natural -> value -> [value]
replicateNatural count value =
  takeNatural count (repeat value)

takeNatural :: Natural -> [value] -> [value]
takeNatural count values
  | count == 0 = []
  | otherwise =
      case values of
        [] -> []
        value : rest -> value : takeNatural (count - 1) rest

retryableServiceError :: ServiceError -> Bool
retryableServiceError (SEConflict _) = True
retryableServiceError (SETimeout _) = True
retryableServiceError (SETransient _) = True
retryableServiceError (SEUnauthorized _) = False
retryableServiceError (SENotFound _) = False

-- | Is this failure permanent for the addressed resource?
--
-- Only absence qualifies. An authorization failure is deliberately excluded:
-- 401/403 can clear on their own (credential reload, clock skew, an edge route
-- programmed after the request), so treating it as permanent would discard work
-- that a redelivery would have completed. Settlement decisions must use this
-- rather than @not . retryableServiceError@, which conflates the two.
serviceErrorPermanent :: ServiceError -> Bool
serviceErrorPermanent (SENotFound _) = True
serviceErrorPermanent (SEConflict _) = False
serviceErrorPermanent (SEUnauthorized _) = False
serviceErrorPermanent (SETimeout _) = False
serviceErrorPermanent (SETransient _) = False

serviceErrorToAppError :: ServiceError -> AppError
serviceErrorToAppError (SEConflict message) = MinIOFailed ("conflict: " <> message)
serviceErrorToAppError (SEUnauthorized message) = MinIOFailed ("unauthorized: " <> message)
serviceErrorToAppError (SETimeout message) = PulsarFailed ("timeout: " <> message)
serviceErrorToAppError (SETransient message) = PulsarFailed ("transient: " <> message)
serviceErrorToAppError (SENotFound message) = MinIOFailed ("not-found: " <> message)

showText :: (Show a) => a -> Text
showText = Text.pack . show
