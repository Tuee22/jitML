{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.InferenceReplyScope
  ( runInferenceReplyScope
  , runInferenceReplyScopeObserved
  )
where

import Control.Concurrent.Async (AsyncCancelled (..), async, cancel, waitCatch)
import Control.Exception qualified as Exception
import Control.Exception.Safe
  ( SomeException
  , displayException
  , fromException
  , generalBracket
  )
import Control.Monad (void)
import Data.Foldable (for_)
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.CLI.Output (writeErrorLineIO)
import JitML.Service.Capabilities qualified as Capabilities

-- | Supervise a correlated reply consumer through every primary exit. The
-- release sends cancellation and then joins the worker, so an Owned
-- subscription DELETE finishes (or reports its typed failure) before the CLI
-- process can return from a timeout or publication failure.
runInferenceReplyScope
  :: IO (Either Capabilities.ConsumerFailure result)
  -> IO (Either Text result)
  -> IO (Either Text result)
{-# NOINLINE runInferenceReplyScope #-}
runInferenceReplyScope =
  runInferenceReplyScopeObserved
    (writeErrorLineIO . ("inference reply scope exceptional exit: " <>))

-- | Testable form of 'runInferenceReplyScope'. Exceptional primary exits keep
-- their original exception identity after the joined release; any secondary
-- consumer/cleanup failure is observed before that exception is rethrown.
runInferenceReplyScopeObserved
  :: (Text -> IO ())
  -> IO (Either Capabilities.ConsumerFailure result)
  -> IO (Either Text result)
  -> IO (Either Text result)
{-# NOINLINE runInferenceReplyScopeObserved #-}
runInferenceReplyScopeObserved observeExceptionalRelease consumerAction primaryAction = do
  (primaryAttempt, releaseResult) <-
    generalBracket
      (async consumerAction)
      ( \consumerThread _exitCase -> do
          cancel consumerThread
          waitCatch consumerThread
      )
      (const (tryInferenceReplyPrimary primaryAction))
  case primaryAttempt of
    Left exception -> do
      for_
        (inferenceReplyReleaseIssue releaseResult)
        ( void
            . tryInferenceReplyPrimary
            . observeExceptionalRelease
            . renderInferenceReplyReleaseIssue
        )
      Exception.throwIO exception
    Right primaryResult ->
      pure (mergeInferenceReplyRelease primaryResult releaseResult)

tryInferenceReplyPrimary :: IO value -> IO (Either SomeException value)
tryInferenceReplyPrimary = Exception.try

data InferenceReplyReleaseIssue
  = InferenceReplyCleanupIssue Text
  | InferenceReplyConsumerIssue Text
  | InferenceReplyExceptionIssue Text

mergeInferenceReplyRelease
  :: Either Text result
  -> Either SomeException (Either Capabilities.ConsumerFailure result)
  -> Either Text result
mergeInferenceReplyRelease primaryResult releaseResult =
  case inferenceReplyReleaseIssue releaseResult of
    Nothing -> primaryResult
    Just releaseIssue
      | releaseIssueAlreadyPrimary primaryResult releaseIssue -> primaryResult
      | otherwise ->
          case primaryResult of
            Left primaryFailure ->
              Left
                ( primaryFailure
                    <> "\n"
                    <> renderInferenceReplyReleaseIssue releaseIssue
                )
            Right _ -> Left (renderInferenceReplyReleaseIssue releaseIssue)

inferenceReplyReleaseIssue
  :: Either SomeException (Either Capabilities.ConsumerFailure result)
  -> Maybe InferenceReplyReleaseIssue
inferenceReplyReleaseIssue releaseResult =
  case releaseResult of
    Left exception
      | Just AsyncCancelled <- fromException exception -> Nothing
      | otherwise -> Just (InferenceReplyExceptionIssue (Text.pack (displayException exception)))
    Right (Left failure) ->
      Just
        ( case failure of
            Capabilities.ConsumerCleanupFailure {} -> cleanupIssue
            Capabilities.ConsumerCleanupContextFailure {} -> cleanupIssue
            _ -> InferenceReplyConsumerIssue detail
        )
     where
      detail = Text.pack (show failure)
      cleanupIssue = InferenceReplyCleanupIssue detail
    Right (Right _) -> Nothing

releaseIssueAlreadyPrimary :: Either Text result -> InferenceReplyReleaseIssue -> Bool
releaseIssueAlreadyPrimary primaryResult releaseIssue =
  case primaryResult of
    Left primaryFailure -> inferenceReplyReleaseIssueDetail releaseIssue `Text.isInfixOf` primaryFailure
    Right _ -> False

inferenceReplyReleaseIssueDetail :: InferenceReplyReleaseIssue -> Text
inferenceReplyReleaseIssueDetail releaseIssue =
  case releaseIssue of
    InferenceReplyCleanupIssue detail -> detail
    InferenceReplyConsumerIssue detail -> detail
    InferenceReplyExceptionIssue detail -> detail

renderInferenceReplyReleaseIssue :: InferenceReplyReleaseIssue -> Text
renderInferenceReplyReleaseIssue releaseIssue =
  case releaseIssue of
    InferenceReplyCleanupIssue detail -> "inference reply cleanup failed: " <> detail
    InferenceReplyConsumerIssue detail -> "inference reply consumer failed while closing: " <> detail
    InferenceReplyExceptionIssue detail -> "inference reply consumer release threw: " <> detail
