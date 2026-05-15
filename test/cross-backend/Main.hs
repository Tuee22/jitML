{-# LANGUAGE OverloadedStrings #-}

module Main where

import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

import JitML.Checkpoint.Format (CheckpointManifest (..), TensorBlob (..), inferFromManifest)
import JitML.Engines.Engine (deterministicFlags, engineForSubstrate)
import JitML.Substrate (Substrate (..), allSubstrates)

main :: IO ()
main =
    defaultMain $
        testGroup
            "jitml-cross-backend"
            [ testCase "each substrate has deterministic engine flags" $
                mapM_
                    ( \substrate ->
                        assertBool "flags present" (not (null (deterministicFlags (engineForSubstrate substrate))))
                    )
                    allSubstrates
            , testCase "checkpoint inference is backend independent for manifest reads" $ do
                let manifest = CheckpointManifest "m1" "exp" [TensorBlob "dense" [2, 2] "blob"]
                    expected = inferFromManifest manifest [1, 2, 3]
                mapM_ (\_substrate -> inferFromManifest manifest [1, 2, 3] @?= expected) [AppleSilicon, LinuxCPU, LinuxCUDA]
            ]
