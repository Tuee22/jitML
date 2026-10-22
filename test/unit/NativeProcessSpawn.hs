{-# LANGUAGE OverloadedStrings #-}

-- Real subprocess controls only, written but not executed in this draft.
-- Echoed shell values test the actual child; configured argv/environment
-- getters remain configuration observations, not OS argv/environ inspection.
module NativeProcessSpawn (nativeProcessSpawnTests) where

import Control.Exception (AsyncException (ThreadKilled), IOException, bracket, throw, try)
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Text (Text)
import Data.Text qualified as Text
import System.Directory (canonicalizePath)
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.Exit (ExitCode (ExitFailure))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Posix.Process (getProcessID)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertEqual, assertFailure, testCase)
import Text.Read (readMaybe)

import JitML.Sub.Outcome qualified as Outcome
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Stream qualified as Stream
import JitML.Sub.Subprocess (Subprocess (..), subprocess, subprocessWithStdin)

nativeProcessSpawnTests :: TestTree
nativeProcessSpawnTests =
  testGroup
    "native actual subprocess spawn observation"
    [ testCase "real shell PID and PPID equal the handle observation and actual parent process" $ do
        let command = sh "printf '%s\\n' \"$$\" \"$PPID\"; /bin/sleep 1; exit 0"
        result <- Stream.runStreamingWithSpawnObservation Stream.defaultSubprocessEnv command
        observation <- mustObservation result
        transcript <- mustSuccess result
        parent <- toInteger <$> getProcessID
        case Text.lines (Outcome.processTranscriptStdout transcript) of
          [pid, ppid] -> do
            assertEqual "actual child echoed PID" (Just (Stream.nativeSpawnProcessId observation)) (integer pid)
            assertEqual "actual child echoed PPID" (Just parent) (integer ppid)
          _ -> assertFailure "actual shell did not return exactly PID and PPID"
        assertEqual "actual parent observation" parent (Stream.nativeSpawnParentProcessId observation)
        assertEqual "configured executable only" "/bin/sh" (Stream.nativeSpawnExecutablePath observation)
        assertEqual
          "configured arguments only"
          (subprocessArguments command)
          (Stream.nativeSpawnArguments observation)
        assertEqual
          "inherited cwd remains explicit absence"
          Nothing
          (Stream.nativeSpawnWorkingDirectory observation)
        assertBool
          "actual monotonic duration"
          (Outcome.processDurationNanoseconds (Outcome.processTranscriptDuration transcript) > 0)
    , testCase "real exit seven retains both complete streams with a genuine nonzero outcome" $ do
        let command = sh "printf 'actual stdout\\n'; printf 'actual stderr\\n' >&2; /bin/sleep 1; exit 7"
        result <- Stream.runStreamingWithSpawnObservation Stream.defaultSubprocessEnv command
        _ <- mustObservation result
        failure <- mustFailure result
        assertEqual "actual exit" (ExitFailure 7) (Outcome.processFailureExitCode failure)
        assertEqual "actual stdout" "actual stdout\n" (Outcome.processFailureStdout failure)
        assertEqual "actual stderr" "actual stderr\n" (Outcome.processFailureStderr failure)
        assertEqual
          "exact configured command renderer"
          (renderSubprocess command)
          (Outcome.processFailureCommand failure)
    , testCase
        "real child receives separate empty Unicode whitespace and literal shell-metacharacter arguments"
        $ do
          let args = ["", "two words", "λ🙂", "$(not-executed)", "quote'and\"double", "--leading-option"]
              command =
                subprocess
                  "/bin/sh"
                  (["-c", "printf '%s\\n' \"$@\"; /bin/sleep 1; exit 0", "spawn-argv-DATA"] <> args)
          result <- Stream.runStreamingWithSpawnObservation Stream.defaultSubprocessEnv command
          observation <- mustObservation result
          transcript <- mustSuccess result
          assertEqual
            "actual argument boundaries and exact child values"
            (Text.unlines args)
            (Outcome.processTranscriptStdout transcript)
          assertEqual
            "same proc argument configuration"
            (subprocessArguments command)
            (Stream.nativeSpawnArguments observation)
    , testCase "actual child working directory and configured cwd remain separately accurate" $
        withSystemTempDirectory "jitml-native-spawn-cwd" $ \root -> do
          let command = (sh "/bin/pwd -P; /bin/sleep 1; exit 0") {subprocessWorkingDirectory = Just root}
          result <- Stream.runStreamingWithSpawnObservation Stream.defaultSubprocessEnv command
          observation <- mustObservation result
          transcript <- mustSuccess result
          actual <- canonicalizePath root
          assertEqual
            "actual physical child cwd"
            (Text.pack actual <> "\n")
            (Outcome.processTranscriptStdout transcript)
          assertEqual "exact configured cwd" (Just root) (Stream.nativeSpawnWorkingDirectory observation)
          assertEqual
            "transcript retains configured cwd"
            (Just root)
            (Outcome.processTranscriptWorkingDirectory transcript)
    , testCase "actual UTF8 stdin reaches the child without a fabricated final newline" $ do
        let payload = "actual stdin λ🙂\nsecond line without trailing newline"
            command = subprocessWithStdin "/bin/sh" ["-c", "/bin/cat; /bin/sleep 1; exit 0"] payload
        result <- Stream.runStreamingWithSpawnObservation Stream.defaultSubprocessEnv command
        _ <- mustObservation result
        transcript <- mustSuccess result
        assertEqual
          "all actual input bytes roundtrip through UTF8"
          payload
          (Outcome.processTranscriptStdout transcript)
        assertEqual "actual empty stderr" "" (Outcome.processTranscriptStderr transcript)
    , testCase "default configuration inherits a test-only ambient value without reporting an override" $
        withDummy "JITML_NATIVE_SPAWN_TEST_INHERIT_ONLY" "actual-inherited-DATA" $ do
          result <-
            Stream.runStreamingWithSpawnObservation
              Stream.defaultSubprocessEnv
              (sh "printf '%s' \"$JITML_NATIVE_SPAWN_TEST_INHERIT_ONLY\"; /bin/sleep 1; exit 0")
          observation <- mustObservation result
          transcript <- mustSuccess result
          assertEqual
            "actual inherited dummy"
            "actual-inherited-DATA"
            (Outcome.processTranscriptStdout transcript)
          assertEqual
            "no configured overrides invented"
            []
            (Stream.nativeSpawnEnvironmentOverrideNames observation)
          assertEqual "no configured removals invented" [] (Stream.nativeSpawnEnvironmentRemovals observation)
    , testCase "explicit test-only override wins over its actual inherited value" $
        withDummy "JITML_NATIVE_SPAWN_TEST_OVERRIDE_ONLY" "actual-old-DATA" $ do
          let name = "JITML_NATIVE_SPAWN_TEST_OVERRIDE_ONLY"
              value = "actual-new-DATA"
              environment = Stream.subprocessEnvOverrideAndRemove [(name, value)] []
          result <-
            Stream.runStreamingWithSpawnObservation
              environment
              (sh "printf '%s' \"$JITML_NATIVE_SPAWN_TEST_OVERRIDE_ONLY\"; /bin/sleep 1; exit 0")
          observation <- mustObservation result
          transcript <- mustSuccess result
          assertEqual "child received actual override" value (Outcome.processTranscriptStdout transcript)
          assertEqual
            "configured override name only"
            [name]
            (Stream.nativeSpawnEnvironmentOverrideNames observation)
          assertBool
            "observation does not copy override value"
            (not (value `Text.isInfixOf` Text.pack (show observation)))
    , testCase "test-only removal wins over both inherited and explicit override values" $
        withDummy "JITML_NATIVE_SPAWN_TEST_REMOVE_ONLY" "actual-inherited-remove-DATA" $ do
          let name = "JITML_NATIVE_SPAWN_TEST_REMOVE_ONLY"
              removedValue = "actual-explicit-removed-DATA"
              keptName = "JITML_NATIVE_SPAWN_TEST_KEPT_ONLY"
              keptValue = "actual-kept-DATA"
              environment = Stream.subprocessEnvOverrideAndRemove [(name, removedValue), (keptName, keptValue)] [name]
          result <-
            Stream.runStreamingWithSpawnObservation
              environment
              ( sh
                  "printf '%s\\n' \"${JITML_NATIVE_SPAWN_TEST_REMOVE_ONLY-actual-unset-DATA}\" \"$JITML_NATIVE_SPAWN_TEST_KEPT_ONLY\"; /bin/sleep 1; exit 0"
              )
          observation <- mustObservation result
          transcript <- mustSuccess result
          assertEqual
            "actual absence plus independent retained override"
            ("actual-unset-DATA\n" <> keptValue <> "\n")
            (Outcome.processTranscriptStdout transcript)
          assertEqual "exact configured removal" [name] (Stream.nativeSpawnEnvironmentRemovals observation)
          assertEqual
            "removed name excluded from effective override-name DATA"
            [keptName]
            (Stream.nativeSpawnEnvironmentOverrideNames observation)
          assertBool
            "neither override value copied to observation"
            (all (\value -> not (value `Text.isInfixOf` Text.pack (show observation))) [removedValue, keptValue])
    , testCase
        "missing actual executable becomes an observed attempt failure with no fabricated exit or streams"
        $ withSystemTempDirectory "jitml-native-spawn-missing"
        $ \root -> do
          let command = subprocess (root </> "never-created-executable") []
          observed <-
            Stream.observeProcessAction
              command
              ( Stream.nativeSpawnResultOutcome
                  <$> Stream.runStreamingWithSpawnObservation Stream.defaultSubprocessEnv command
              )
          case observed of
            Outcome.ObservedProcessFailed failure@(Outcome.ObservedProcessAttemptFailure _) -> do
              assertEqual "no observed exit invented" Nothing (Outcome.observedProcessFailureExitCode failure)
              assertEqual "no completed stdout invented" Nothing (Outcome.observedProcessFailureStdout failure)
              assertEqual "no completed stderr invented" Nothing (Outcome.observedProcessFailureStderr failure)
            _ -> assertFailure "missing executable became a returned process outcome"
    , testCase "missing actual cwd propagates a launch exception rather than returning an observation" $
        withSystemTempDirectory "jitml-native-spawn-missing-cwd" $ \root -> do
          let command = (sh "exit 0") {subprocessWorkingDirectory = Just (root </> "never-created-directory")}
          attempted <-
            try (Stream.runStreamingWithSpawnObservation Stream.defaultSubprocessEnv command)
              :: IO (Either IOException Stream.NativeProcessSpawnResult)
          case attempted of
            Left _ -> pure ()
            Right _ -> assertFailure "invalid actual cwd fabricated a process result"
    , testCase "async input cancellation propagates without a fabricated spawn or process result" $ do
        attempted <-
          try (Stream.runStreamingWithSpawnObservation Stream.defaultSubprocessEnv (throw ThreadKilled))
            :: IO (Either AsyncException Stream.NativeProcessSpawnResult)
        case attempted of
          Left ThreadKilled -> pure ()
          _ -> assertFailure "async input cancellation became a spawn result"
    , testCase "a genuinely fast zero exit keeps empty streams and never substitutes a nominal PID" $ do
        result <- Stream.runStreamingWithSpawnObservation Stream.defaultSubprocessEnv (sh "exit 0")
        transcript <- mustSuccess result
        assertEqual "actual empty stdout" "" (Outcome.processTranscriptStdout transcript)
        assertEqual "actual empty stderr" "" (Outcome.processTranscriptStderr transcript)
        case Stream.nativeSpawnResultObservation result of
          Nothing -> pure () -- genuine handle-close race remains honest absence
          Just observation -> do
            parent <- toInteger <$> getProcessID
            assertBool
              "actual available handle PID must be positive"
              (Stream.nativeSpawnProcessId observation > 0)
            assertEqual
              "actual parent if handle observation available"
              parent
              (Stream.nativeSpawnParentProcessId observation)
    , testCase "real invalid UTF8 and NUL streams retain exact raw bytes with genuine exit seven" $ do
        let command = sh "printf '\\000\\377\\200A\\n'; printf '\\376\\000E\\n' >&2; /bin/sleep 1; exit 7"
            expectedStdout = LazyByteString.pack [0, 255, 128, 65, 10]
            expectedStderr = LazyByteString.pack [254, 0, 69, 10]
        result <- Stream.runStreamingWithSpawnObservation Stream.defaultSubprocessEnv command
        _ <- mustObservation result
        failure <- mustFailure result
        assertEqual
          "all actual stdout bytes including invalid UTF8 and NUL"
          expectedStdout
          (Stream.nativeSpawnResultStdoutBytes result)
        assertEqual
          "all actual stderr bytes including invalid UTF8 and NUL"
          expectedStderr
          (Stream.nativeSpawnResultStderrBytes result)
        assertEqual
          "existing genuine nonzero outcome remains seven"
          (ExitFailure 7)
          (Outcome.processFailureExitCode failure)
        assertEqual
          "existing lenient stdout Text is unchanged"
          (Text.pack ['\NUL', '\xfffd', '\xfffd', 'A', '\n'])
          (Outcome.processFailureStdout failure)
        assertEqual
          "existing lenient stderr Text is unchanged"
          (Text.pack ['\xfffd', '\NUL', 'E', '\n'])
          (Outcome.processFailureStderr failure)
    ]

sh :: Text -> Subprocess
sh script = subprocess "/bin/sh" ["-c", script]

integer :: Text -> Maybe Integer
integer = readMaybe . Text.unpack

mustObservation :: Stream.NativeProcessSpawnResult -> IO Stream.NativeProcessSpawnObservation
mustObservation result = case Stream.nativeSpawnResultObservation result of
  Just actual -> pure actual
  Nothing ->
    assertFailure "one-second live fixture has no actual process-handle PID observation"
      >> fail "unreachable"

mustSuccess :: Stream.NativeProcessSpawnResult -> IO Outcome.ProcessTranscript
mustSuccess result = case Stream.nativeSpawnResultOutcome result of
  Outcome.ProcessSucceeded actual -> pure actual
  Outcome.ProcessFailed failure -> assertFailure (show failure) >> fail "unreachable"

mustFailure :: Stream.NativeProcessSpawnResult -> IO Outcome.ProcessFailure
mustFailure result = case Stream.nativeSpawnResultOutcome result of
  Outcome.ProcessFailed actual -> pure actual
  Outcome.ProcessSucceeded transcript -> assertFailure (show transcript) >> fail "unreachable"

-- Unique dummy names only; never edit journal/device/worker capabilities.
-- Restore each actual previous value even on a child/expectation exception.
withDummy :: String -> String -> Assertion -> Assertion
withDummy name value action =
  bracket
    (do previous <- lookupEnv name; setEnv name value; pure previous)
    (maybe (unsetEnv name) (setEnv name))
    (const action)
