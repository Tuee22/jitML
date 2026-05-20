{-# LANGUAGE OverloadedStrings #-}

module Main where

import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
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
          sources <- purescriptSources
          assertBool "PureScript source set is non-empty" (not (null sources))
          mapM_
            ( \path -> do
                source <- Text.IO.readFile path
                assertBool (path <> " has no tabs") (not ("\t" `Text.isInfixOf` source))
                assertBool (path <> " has a final newline") ("\n" `Text.isSuffixOf` source)
            )
            sources
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

purescriptSources :: IO [FilePath]
purescriptSources =
  concat <$> traverse listPursFiles ["web/src", "web/test"]

listPursFiles :: FilePath -> IO [FilePath]
listPursFiles root = do
  exists <- doesDirectoryExist root
  if exists
    then do
      entries <- listDirectory root
      concat
        <$> traverse
          ( \entry -> do
              let path = root <> "/" <> entry
              isDirectory <- doesDirectoryExist path
              if isDirectory
                then listPursFiles path
                else pure [path | ".purs" `Text.isSuffixOf` Text.pack path]
          )
          entries
    else pure []
