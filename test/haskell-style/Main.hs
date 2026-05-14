module Main where

import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertFailure, testCase)

import JitML.Lint.Stack (LintMode (..), LintTarget (..), renderLintFinding, runLint)

main :: IO ()
main =
    defaultMain $
        testGroup
            "jitml-haskell-style"
            [ testCase "lint stack passes" $ do
                findings <- runLint LintAll LintCheck
                case findings of
                    [] -> pure ()
                    _ -> assertFailure (show (fmap renderLintFinding findings))
            ]
