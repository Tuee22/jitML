{-# LANGUAGE OverloadedStrings #-}

module Main where

import System.Exit (ExitCode (..))
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (subprocess)

main :: IO ()
main =
    defaultMain $
        testGroup
            "jitml-integration"
            [ testCase "runStreaming captures a sentinel process" $ do
                (exitCode, stdoutText, stderrText) <-
                    runStreaming defaultSubprocessEnv (subprocess "/bin/echo" ["subprocess-ok"])
                exitCode @?= ExitSuccess
                stdoutText @?= "subprocess-ok\n"
                stderrText @?= ""
            ]
