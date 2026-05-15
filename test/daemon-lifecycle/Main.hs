{-# LANGUAGE OverloadedStrings #-}

module Main where

import Data.ByteString.Char8 qualified as ByteString
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

import JitML.AppError.AppError (AppError (..))
import JitML.Service.Consumer (eventIdFromPayload, processAtLeastOnce)
import JitML.Service.Endpoints (MetricsSnapshot (..), endpointStatus, healthz, metrics, readyz)
import JitML.Service.Lifecycle (LifecyclePhase (..), lifecyclePlan)
import JitML.Service.Retry (RetryPolicy (..), ServiceError (..), retryServiceAction)

main :: IO ()
main =
    defaultMain $
        testGroup
            "jitml-daemon-lifecycle"
            [ testCase "lifecycle order reaches ready before serve" $
                lifecyclePlan @?= [Load, Prereq, Acquire, Ready, Serve, Drain, Exit]
            , testCase "endpoint status codes follow readiness" $ do
                endpointStatus healthz @?= 200
                endpointStatus (readyz False) @?= 503
                endpointStatus (readyz True) @?= 200
                endpointStatus (metrics (MetricsSnapshot 0 1 0)) @?= 200
            , testCase "retry policy retries transient errors" $ do
                result <- retryServiceAction (LinearN 2 0) (\() -> pure (Left (SETimeout "timeout"))) () :: IO (Either AppError ())
                result @?= Left (PulsarFailed "timeout: timeout")
            , testCase "message hash dedup collapses repeated messages" $ do
                let first = eventIdFromPayload (ByteString.pack "payload")
                    second = eventIdFromPayload (ByteString.pack "payload")
                first @?= second
                assertBool "one side effect" (length (processAtLeastOnce [first, second]) == 1)
            ]
