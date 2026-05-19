{-# LANGUAGE OverloadedStrings #-}

module Main where

import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import System.Directory (doesFileExist)
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

import JitML.Sub.Subprocess (Subprocess (..), subprocess)
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
      , testCase "PureScript tool checks are explicit typed Subprocess values" $ do
          let spagoCmd =
                (subprocess "node_modules/.bin/spago" ["test"])
                  { subprocessWorkingDirectory = Just "web"
                  }
              tidyCmd =
                (subprocess "node_modules/.bin/purs-tidy" ["check", "src/**/*.purs"])
                  { subprocessWorkingDirectory = Just "web"
                  }
          subprocessPath spagoCmd @?= "node_modules/.bin/spago"
          subprocessArguments spagoCmd @?= ["test"]
          subprocessWorkingDirectory spagoCmd @?= Just "web"
          subprocessPath tidyCmd @?= "node_modules/.bin/purs-tidy"
          subprocessArguments tidyCmd @?= ["check", "src/**/*.purs"]
          subprocessWorkingDirectory tidyCmd @?= Just "web"
      ]

panelContractEndpoints :: [Contracts.ApiEndpoint]
panelContractEndpoints =
  case Contracts.apiEndpoints of
    _runCommandEndpoint : rest -> rest
    [] -> []
