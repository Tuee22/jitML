{-# LANGUAGE OverloadedStrings #-}

module Main where

import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import System.Directory (doesFileExist)
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..))
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (subprocess)
import JitML.Sub.Subprocess qualified
import JitML.Web.Bundle (panelEndpoint, panelSurfaces)
import JitML.Web.Contracts (renderPureScriptContracts)
import JitML.Web.Contracts qualified as Contracts

main :: IO ()
main =
  defaultMain $
    testGroup
      "jitml-purescript-style"
      [ testCase "generated contracts file exists and names endpoints" $ do
          exists <- doesFileExist "web/src/Generated/Contracts.purs"
          assertBool "generated contracts missing" exists
          content <- Text.IO.readFile "web/src/Generated/Contracts.purs"
          assertBool "InferenceRun missing" ("InferenceRun" `Text.isInfixOf` content)
      , testCase "renderer produces PureScript module header" $
          assertBool
            "module header"
            ("module Generated.Contracts where" `Text.isInfixOf` renderPureScriptContracts)
      , testCase "PureScript sources are whitespace-normalized" $ do
          mainSource <- Text.IO.readFile "web/src/Main.purs"
          testSource <- Text.IO.readFile "web/test/Main.purs"
          assertBool "no tabs in Main.purs" (not ("\t" `Text.isInfixOf` mainSource))
          assertBool "no tabs in test/Main.purs" (not ("\t" `Text.isInfixOf` testSource))
          assertBool "Main.purs final newline" ("\n" `Text.isSuffixOf` mainSource)
          assertBool "test/Main.purs final newline" ("\n" `Text.isSuffixOf` testSource)
      , testCase "frontend panel endpoints are covered by generated contracts" $
          fmap panelEndpoint panelSurfaces
            @?= fmap Contracts.endpointPath panelContractEndpoints
      , testCase "spago test runs through typed Subprocess (JITML_LIVE_E2E=1)" $ do
          liveGate <- lookupEnv "JITML_LIVE_E2E"
          case liveGate of
            Just enabled
              | Text.toLower (Text.pack enabled) `elem` ["1", "true", "yes", "on"] -> do
                  -- Live path: invokes the installed local spago via the typed
                  -- Subprocess boundary. Requires `web/node_modules/.bin/spago`
                  -- to be present (installed by `npm install` in the repo).
                  let cmd =
                        (subprocess "node_modules/.bin/spago" ["test"])
                          { JitML.Sub.Subprocess.subprocessWorkingDirectory = Just "web"
                          }
                  (exitCode, stdoutText, _stderrText) <-
                    runStreaming defaultSubprocessEnv cmd
                  assertBool
                    "spago test exits zero"
                    (case exitCode of ExitSuccess -> True; _ -> False)
                  assertBool
                    "spago test prints panel name from smoke suite"
                    ("mnist-live-inference" `Text.isInfixOf` stdoutText)
            _ -> pure () -- default path: skip when not gated by JITML_LIVE_E2E=1
      , testCase "purs-tidy check runs through typed Subprocess (JITML_LIVE_E2E=1)" $ do
          liveGate <- lookupEnv "JITML_LIVE_E2E"
          case liveGate of
            Just enabled
              | Text.toLower (Text.pack enabled) `elem` ["1", "true", "yes", "on"] -> do
                  -- Live path: invokes `purs-tidy check 'src/**/*.purs'`
                  -- through the typed Subprocess in the web/ workdir.
                  let cmd =
                        (subprocess "node_modules/.bin/purs-tidy" ["check", "src/**/*.purs"])
                          { JitML.Sub.Subprocess.subprocessWorkingDirectory = Just "web"
                          }
                  (exitCode, stdoutText, stderrText) <-
                    runStreaming defaultSubprocessEnv cmd
                  case exitCode of
                    ExitSuccess ->
                      assertBool
                        "purs-tidy reports all files formatted"
                        ("All files are formatted" `Text.isInfixOf` stdoutText)
                    ExitFailure _ ->
                      assertFailure
                        ("purs-tidy check failed: " <> Text.unpack (stdoutText <> stderrText))
            _ -> pure ()
      ]

panelContractEndpoints :: [Contracts.ApiEndpoint]
panelContractEndpoints =
  case Contracts.apiEndpoints of
    _runCommandEndpoint : rest -> rest
    [] -> []
