{-# LANGUAGE OverloadedStrings #-}

module JitML.Test.PipedProcess
  ( pipedProcessTests
  )
where

import Control.Exception (try)
import Data.Text qualified as Text
import System.Exit (ExitCode (..))
import System.Timeout (timeout)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

import JitML.Sub.Outcome
  ( ProcessDuration (..)
  , ProcessOutcome (..)
  , ProcessTranscript (..)
  , processFailureCommand
  , processFailureDuration
  , processFailureExitCode
  , processFailureStderr
  , processFailureStdout
  , processFailureWorkingDirectory
  , renderProcessOutcome
  )
import JitML.Sub.Piped
  ( PipedActionException (..)
  , PipedSessionError (..)
  , closePipedStdin
  , readPipedStdoutLine
  , runPipedProcess
  , writePipedStdin
  )
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Subprocess (Subprocess (..), subprocess)
import System.IO.Temp (withSystemTempDirectory)

pipedProcessTests :: TestTree
pipedProcessTests =
  testGroup
    "PipedProcess"
    [ testCase "file-backed stderr retains more than 64KiB on failure without deadlock" $
        withSystemTempDirectory "jitml-piped-failure" $ \workingDirectory -> do
          let command =
                ( subprocess
                    "/bin/sh"
                    [ "-c"
                    , "printf 'frame\\n'; head -c 70000 /dev/zero | tr '\\000' x >&2; exit 17"
                    ]
                )
                  { subprocessWorkingDirectory = Just workingDirectory
                  }
          maybeResult <-
            timeout fixtureTimeoutMicroseconds $
              runPipedProcess command $ \session ->
                readPipedStdoutLine session
          case maybeResult of
            Nothing -> assertFailure "piped failure fixture deadlocked"
            Just (actionResult, outcome) -> do
              actionResult @?= Just "frame\n"
              case outcome of
                ProcessSucceeded _transcript ->
                  assertFailure
                    ( "expected exit 17, got success:\n"
                        <> Text.unpack (renderProcessOutcome outcome)
                    )
                ProcessFailed failure -> do
                  processFailureExitCode failure @?= ExitFailure 17
                  processFailureCommand failure @?= renderSubprocess command
                  processFailureStdout failure @?= "frame\n"
                  processFailureStderr failure @?= Text.replicate 70000 "x"
                  processFailureWorkingDirectory failure @?= Just workingDirectory
                  assertPositiveDuration (processFailureDuration failure)
    , testCase "action result and successful exit remain independent" $ do
        let command =
              subprocess
                "/bin/sh"
                [ "-c"
                , "IFS= read -r line; printf 'echo:%s\\ntrailer\\n' \"$line\""
                ]
        (actionResult, outcome) <-
          runPipedProcess command $ \session -> do
            writeResult <- writePipedStdin session "hello\n"
            closePipedStdin session
            closedWriteResult <- writePipedStdin session "too-late\n"
            firstLine <- readPipedStdoutLine session
            pure (writeResult, closedWriteResult, firstLine)
        actionResult
          @?= (Right (), Left PipedStdinClosed, Just "echo:hello\n")
        case outcome of
          ProcessFailed _failure ->
            assertFailure
              ( "expected successful exit, got failure:\n"
                  <> Text.unpack (renderProcessOutcome outcome)
              )
          ProcessSucceeded transcript -> do
            processTranscriptCommand transcript @?= renderSubprocess command
            processTranscriptStdout transcript @?= "echo:hello\ntrailer\n"
            processTranscriptStderr transcript @?= ""
            processTranscriptWorkingDirectory transcript @?= Nothing
            assertPositiveDuration (processTranscriptDuration transcript)
    , testCase "child-side pipe closure is returned as a typed write failure" $ do
        let command = subprocess "/bin/sh" ["-c", "exec 0<&-; printf 'closed\\n'"]
        (writeResult, _outcome) <-
          runPipedProcess command $ \session -> do
            _closedSignal <- readPipedStdoutLine session
            writePipedStdin session "settle\n"
        case writeResult of
          Left (PipedWriteFailed detail) ->
            assertBool "pipe failure omitted its OS detail" (not (Text.null detail))
          other -> assertFailure ("expected PipedWriteFailed, got " <> show other)
    , testCase "synchronous protocol-action failure retains the complete child outcome" $ do
        let command =
              subprocess
                "/bin/sh"
                [ "-c"
                , "printf 'frame\\n'; IFS= read -r ignored || true; printf 'tail\\n'; printf 'action-stderr' >&2; exit 23"
                ]
        failureResult <-
          ( try
              ( runPipedProcess command $ \session -> do
                  _firstFrame <- readPipedStdoutLine session
                  ioError (userError "protocol action exploded")
              )
              :: IO (Either PipedActionException ((), ProcessOutcome))
          )
        case failureResult of
          Right _ -> assertFailure "synchronous protocol exception escaped its typed context"
          Left actionException -> do
            assertBool
              "protocol exception detail was lost"
              ("protocol action exploded" `Text.isInfixOf` pipedActionExceptionDetail actionException)
            case pipedActionExceptionOutcome actionException of
              ProcessSucceeded _transcript ->
                assertFailure "expected the action fixture child to exit 23"
              ProcessFailed failure -> do
                processFailureExitCode failure @?= ExitFailure 23
                processFailureCommand failure @?= renderSubprocess command
                processFailureStdout failure @?= "frame\ntail\n"
                processFailureStderr failure @?= "action-stderr"
                processFailureWorkingDirectory failure @?= Nothing
                assertPositiveDuration (processFailureDuration failure)
    ]

assertPositiveDuration :: ProcessDuration -> IO ()
assertPositiveDuration (ProcessDuration nanoseconds) =
  assertBool "process duration must be positive" (nanoseconds > 0)

fixtureTimeoutMicroseconds :: Int
fixtureTimeoutMicroseconds = 10 * 1000 * 1000
