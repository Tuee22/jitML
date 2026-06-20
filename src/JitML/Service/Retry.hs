{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.Retry
  ( RetryPolicy (..)
  , ServiceError (..)
  , renderRetryPolicyDhall
  , retryPolicyDecoder
  , retryServiceAction
  , serviceErrorToAppError
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Dhall qualified
import Numeric.Natural (Natural)

import JitML.AppError.AppError (AppError (..))

data RetryPolicy
  = Once
  | LinearN Int Int
  | ExponentialN Int Int Int
  | RetryUntil Int
  deriving stock (Eq, Show)

data ServiceError
  = SEConflict Text
  | SEUnauthorized Text
  | SETimeout Text
  | SETransient Text
  deriving stock (Eq, Show)

renderRetryPolicyDhall :: RetryPolicy -> Text
renderRetryPolicyDhall Once = "Once"
renderRetryPolicyDhall (LinearN attempts delayMillis) =
  "LinearN { attempts = " <> showText attempts <> ", delayMillis = " <> showText delayMillis <> " }"
renderRetryPolicyDhall (ExponentialN attempts baseMillis capMillis) =
  "ExponentialN { attempts = "
    <> showText attempts
    <> ", baseMillis = "
    <> showText baseMillis
    <> ", capMillis = "
    <> showText capMillis
    <> " }"
renderRetryPolicyDhall (RetryUntil deadlineMillis) =
  "RetryUntil { deadlineMillis = " <> showText deadlineMillis <> " }"

-- | Sprint 5.12 — decode the @retryPolicy@ union so 'JitML.Service.LiveConfig'
-- is loadable from Dhall (real SIGHUP hot-reload) and so the reflected schema in
-- 'JitML.Service.DhallSchema' is derived from this decoder, not hand-written.
-- Constructor and field order mirror @dhall/service/LiveConfig.dhall@.
retryPolicyDecoder :: Dhall.Decoder RetryPolicy
retryPolicyDecoder =
  Dhall.union $
    Dhall.constructor "Once" (Once <$ Dhall.unit)
      <> Dhall.constructor "LinearN" linearN
      <> Dhall.constructor "ExponentialN" exponentialN
      <> Dhall.constructor "RetryUntil" retryUntil
 where
  linearN =
    Dhall.record (LinearN <$> natField "attempts" <*> natField "delayMillis")
  exponentialN =
    Dhall.record
      ( ExponentialN
          <$> natField "attempts"
          <*> natField "baseMillis"
          <*> natField "capMillis"
      )
  retryUntil =
    Dhall.record (RetryUntil <$> natField "deadlineMillis")
  natField name = fmap naturalToInt (Dhall.field name Dhall.natural)

naturalToInt :: Natural -> Int
naturalToInt = fromIntegral

retryServiceAction
  :: RetryPolicy -> (env -> IO (Either ServiceError a)) -> env -> IO (Either AppError a)
retryServiceAction policy action env = go (attemptBudget policy)
 where
  go attemptsRemaining = do
    result <- action env
    case result of
      Right value -> pure (Right value)
      Left err
        | not (retryableServiceError err) ->
            pure (Left (serviceErrorToAppError err))
        | attemptsRemaining <= 1 ->
            pure (Left (serviceErrorToAppError err))
        | otherwise ->
            go (attemptsRemaining - 1)

attemptBudget :: RetryPolicy -> Int
attemptBudget Once = 1
attemptBudget (LinearN attempts _) = max 1 attempts
attemptBudget (ExponentialN attempts _ _) = max 1 attempts
attemptBudget (RetryUntil _) = 2

retryableServiceError :: ServiceError -> Bool
retryableServiceError (SEConflict _) = True
retryableServiceError (SETimeout _) = True
retryableServiceError (SETransient _) = True
retryableServiceError (SEUnauthorized _) = False

serviceErrorToAppError :: ServiceError -> AppError
serviceErrorToAppError (SEConflict message) = MinIOFailed ("conflict: " <> message)
serviceErrorToAppError (SEUnauthorized message) = MinIOFailed ("unauthorized: " <> message)
serviceErrorToAppError (SETimeout message) = PulsarFailed ("timeout: " <> message)
serviceErrorToAppError (SETransient message) = PulsarFailed ("transient: " <> message)

showText :: (Show a) => a -> Text
showText = Text.pack . show
