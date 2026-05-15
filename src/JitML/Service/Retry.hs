{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.Retry
    ( RetryPolicy (..)
    , ServiceError (..)
    , renderRetryPolicyDhall
    , retryServiceAction
    , serviceErrorToAppError
    )
where

import Data.Text (Text)
import Data.Text qualified as Text

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

retryServiceAction :: RetryPolicy -> (env -> IO (Either ServiceError a)) -> env -> IO (Either AppError a)
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

showText :: Show a => a -> Text
showText = Text.pack . show
