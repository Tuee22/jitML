{-# LANGUAGE OverloadedStrings #-}

module BootstrapLifecycle (tests) where

import Control.Monad (forM_, unless)
import Data.ByteString.Char8 qualified as BS
import Data.List (elemIndex, isPrefixOf)
import Data.Text qualified as Text
import System.Directory
  ( canonicalizePath
  , copyFile
  , createDirectory
  , doesFileExist
  , getCurrentDirectory
  )
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Posix.Files (setFileMode)
import System.Timeout (timeout)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertEqual, assertFailure, testCase, (@?=))

import JitML.Sub.Outcome
  ( ProcessOutcome (..)
  , ProcessTranscript (..)
  , processFailureExitCode
  , processFailureTranscript
  )
import JitML.Sub.Stream (runStreaming, subprocessEnvOverrideAndRemove)
import JitML.Sub.Subprocess (Subprocess (..), subprocessWithStdin)

-- Every command runs against fresh copied scripts and stub-only tool paths.
-- No Docker, Kind, Cabal, GPU, data purge or real jitml operation is invoked.
tests :: TestTree
tests = testGroup "bootstrap lifecycle delegation" (fmap laneTests lanes)
 where
  laneTests lane =
    testGroup
      lane
      [ testCase "down delegates exact implemented target after build" $ checkSuccess lane ["down"]
      , testCase "ordinary purge delegates exact reset target" $ checkSuccess lane ["purge"]
      , testCase "full purge delegates the implemented full flag exactly once" $
          checkSuccess lane ["purge", "--full"]
      , testCase "unknown/extra lifecycle arguments refuse before build or mutation" $
          forM_ [["down", "--full"], ["purge", "--unknown"], ["purge", "--full", "extra"], ["down", "extra"]] $ \args ->
            withFixture lane 0 $ \fixture -> do
              outcome <- invoke fixture args
              assertExit fixture args (ExitFailure 64) outcome
              trace fixture >>= (@?= [])
              assertMarkers fixture
      , testCase "CLI failure17 propagates for down and both purges without fallback" $
          forM_ [["down"], ["purge"], ["purge", "--full"]] $ \args ->
            withFixture lane 17 $ \fixture -> do
              outcome <- invoke fixture args
              assertExit fixture args (ExitFailure 17) outcome
              observed <- trace fixture
              cliCalls lane observed @?= [expectedCall lane args]
              assertNoFallback observed
              assertMarkers fixture
      ]

lanes :: [String]
lanes = ["apple-silicon", "linux-cpu", "linux-cuda"]

data Fixture = Fixture
  { fixtureRoot :: FilePath
  , fixtureLane :: String
  , fixtureTools :: FilePath
  , fixtureEnv :: [(String, String)]
  }

withFixture :: String -> Int -> (Fixture -> IO a) -> IO a
withFixture lane cliExit action = do
  scriptsRoot <- (</> "bootstrap") <$> getCurrentDirectory
  withSystemTempDirectory "jitml-bootstrap-lifecycle-" $ \temporary -> do
    root <- canonicalizePath temporary
    let tools = root </> "stub-tools"
        scripts = root </> "bootstrap"
        binary = root </> "fixture-jitml"
        tracePath = root </> "calls"
        custom =
          [ ("JITML_FIXTURE_TRACE", tracePath)
          , ("JITML_FIXTURE_BINARY", binary)
          , ("JITML_FIXTURE_CLI_EXIT", show cliExit)
          , ("PATH", tools <> ":/usr/bin:/bin")
          ]
    createDirectory tools
    createDirectory scripts
    forM_ ["_lib.sh", "apple-silicon.sh", "linux-cpu.sh", "linux-cuda.sh"] $ \name ->
      copyFile (scriptsRoot </> name) (scripts </> name)
    forM_ [".build", ".data"] $ \name -> do
      createDirectory (root </> name)
      BS.writeFile (root </> name </> "must-survive-stub-delegation") "fixture marker"
    BS.writeFile tracePath ""
    writeExecutable binary $
      unlines
        [ "#!/bin/bash"
        , "set -eu"
        , "printf 'jitml' >> \"$JITML_FIXTURE_TRACE\""
        , "printf ' <%s>' \"$@\" >> \"$JITML_FIXTURE_TRACE\""
        , "printf '\\n' >> \"$JITML_FIXTURE_TRACE\""
        , "exit \"$JITML_FIXTURE_CLI_EXIT\""
        ]
    forM_ ["docker", "cabal", "uname", "brew", "xcode-select", "codesign", "opt", "llc", "kind", "rm"] $ \name ->
      writeExecutable (tools </> name) (stub name)
    action (Fixture root lane tools custom)

writeExecutable :: FilePath -> String -> IO ()
writeExecutable path content = writeFile path content >> setFileMode path 0o755

stub :: String -> String
stub name =
  unlines $
    [ "#!/bin/bash"
    , "set -eu"
    , "printf '%s' '" <> name <> "' >> \"$JITML_FIXTURE_TRACE\""
    , "printf ' <%s>' \"$@\" >> \"$JITML_FIXTURE_TRACE\""
    , "printf '\\n' >> \"$JITML_FIXTURE_TRACE\""
    ]
      <> body
 where
  body = case name of
    "docker" ->
      [ "if [ \"$*\" = 'info' ] || [ \"$*\" = 'compose build jitml' ]; then exit 0; fi"
      , "if [ \"${1:-}\" = compose ] && [ \"${2:-}\" = run ] && [ \"${3:-}\" = --rm ] && [ \"${4:-}\" = jitml ] && [ \"${5:-}\" = jitml ]; then exit \"$JITML_FIXTURE_CLI_EXIT\"; fi"
      , "exit 99"
      ]
    "cabal" ->
      [ "case \"$*\" in"
      , "  'build exe:jitml') exit 0 ;;"
      , "  'list-bin exe:jitml') printf '%s\\n' \"$JITML_FIXTURE_BINARY\" ;;"
      , "  *) exit 99 ;;"
      , "esac"
      ]
    "uname" ->
      ["case \"$*\" in -s) echo Darwin ;; -m) echo arm64 ;; *) exit 99 ;; esac"]
    "brew" -> ["[ \"$*\" = --version ] || exit 99", "echo 'Homebrew fixture'"]
    "xcode-select" -> ["[ \"$*\" = -p ] || exit 99", "echo /fixture/CommandLineTools"]
    "codesign" -> ["exit 0"]
    "opt" -> ["[ \"$*\" = --version ] || exit 99", "echo 'LLVM version 19.1.7'"]
    "llc" -> ["[ \"$*\" = --version ] || exit 99", "echo 'LLVM version 19.1.7'"]
    _ -> ["echo 'forbidden lifecycle fallback' >&2", "exit 99"]

invoke :: Fixture -> [String] -> IO (ExitCode, String, String)
invoke fixture args = do
  let spec =
        ( subprocessWithStdin
            "/bin/bash"
            ( fmap
                Text.pack
                ( [ fixtureRoot fixture </> "bootstrap" </> fixtureLane fixture <> ".sh"
                  , "--command-dir"
                  , fixtureTools fixture
                  ]
                    <> args
                )
            )
            ""
        )
          { subprocessWorkingDirectory = Just (fixtureRoot fixture)
          }
      environment =
        subprocessEnvOverrideAndRemove
          [(Text.pack name, Text.pack value) | (name, value) <- fixtureEnv fixture]
          []
  result <- timeout 20000000 (runStreaming environment spec)
  outcome <-
    maybe (assertFailure "stub-only bootstrap command timed out" >> fail "unreachable") pure result
  let (code, transcript) = case outcome of
        ProcessSucceeded actual -> (ExitSuccess, actual)
        ProcessFailed actual -> (processFailureExitCode actual, processFailureTranscript actual)
  pure
    ( code
    , Text.unpack (processTranscriptStdout transcript)
    , Text.unpack (processTranscriptStderr transcript)
    )

trace :: Fixture -> IO [String]
trace fixture = fmap (fmap BS.unpack . BS.lines) (BS.readFile (fixtureRoot fixture </> "calls"))

expectedCall :: String -> [String] -> String
expectedCall lane args = render prefix <> concatMap (\arg -> " <" <> arg <> ">") operation
 where
  operation = case args of
    ["down"] -> ["cluster", "down", "--substrate", lane]
    ["purge"] -> ["cluster", "reset", "--yes", "--substrate", lane]
    ["purge", "--full"] -> ["cluster", "reset", "--yes", "--substrate", lane, "--full"]
    _ -> error "test used an unknown lifecycle command"
  prefix =
    if lane == "apple-silicon"
      then ["jitml"]
      else ["docker", "compose", "run", "--rm", "jitml", "jitml"]
  render [] = error "empty expected prefix"
  render (tool : argv) = tool <> concatMap (\arg -> " <" <> arg <> ">") argv

cliCalls :: String -> [String] -> [String]
cliCalls lane = filter (isPrefixOf prefix)
 where
  prefix = if lane == "apple-silicon" then "jitml <" else "docker <compose> <run>"

assertNoFallback :: [String] -> IO ()
assertNoFallback observed = do
  assertBool "no kind fallback" (not (any (isPrefixOf "kind <") observed))
  assertBool "no rm fallback" (not (any (isPrefixOf "rm <") observed))
  assertBool
    "no Docker deletion fallback"
    ( not
        ( any
            ( \entry ->
                any
                  (`isPrefixOf` entry)
                  ["docker <rm>", "docker <volume>", "docker <compose> <down>"]
            )
            observed
        )
    )

assertMarkers :: Fixture -> IO ()
assertMarkers fixture = forM_ [".data", ".build"] $ \name -> do
  let path = fixtureRoot fixture </> name </> "must-survive-stub-delegation"
  present <- doesFileExist path
  unless present (assertFailure ("wrapper removed fixture marker under " <> name))
  BS.readFile path >>= (@?= "fixture marker")

checkSuccess :: String -> [String] -> IO ()
checkSuccess lane args = withFixture lane 0 $ \fixture -> do
  outcome <- invoke fixture args
  assertExit fixture args ExitSuccess outcome
  observed <- trace fixture
  cliCalls lane observed @?= [expectedCall lane args]
  let build =
        if lane == "apple-silicon" then "cabal <build> <exe:jitml>" else "docker <compose> <build> <jitml>"
  case (elemIndex build observed, elemIndex (expectedCall lane args) observed) of
    (Just built, Just delegated) -> assertBool "build precedes delegated CLI" (built < delegated)
    _ -> assertFailure "missing build or exact CLI delegation"
  assertNoFallback observed
  assertMarkers fixture

assertExit :: Fixture -> [String] -> ExitCode -> (ExitCode, String, String) -> IO ()
assertExit fixture args expected (actual, childOut, childErr) =
  assertEqual
    ( unlines
        [ "lane=" <> fixtureLane fixture
        , "args=" <> show args
        , "stdout=" <> childOut
        , "stderr=" <> childErr
        ]
    )
    expected
    actual
