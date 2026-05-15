{-# LANGUAGE OverloadedStrings #-}

module Main where

import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import System.Directory (doesFileExist)
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, testCase)

import JitML.Web.Contracts (renderPureScriptContracts)

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
      ]
