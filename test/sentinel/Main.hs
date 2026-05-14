module Main where

import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

main :: IO ()
main =
    defaultMain $
        testGroup
            "sentinel"
            [ testCase "phase-1.1 scaffold" $
                True @?= True
            ]
