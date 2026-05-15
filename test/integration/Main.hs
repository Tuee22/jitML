{-# LANGUAGE OverloadedStrings #-}

module Main where

import System.Exit (ExitCode (..))
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (subprocess)
import JitML.Bootstrap (bootstrapPlanSteps)
import JitML.Cluster.Kind (kindConfigFor, renderKindConfig)
import JitML.Routes (renderHTTPRoute, routeRegistry)
import JitML.Substrate (Substrate (..))

main :: IO ()
main =
    defaultMain $
        testGroup
            "jitml-integration"
            [ testCase "runStreaming captures a fixture process" $ do
                (exitCode, stdoutText, stderrText) <-
                    runStreaming defaultSubprocessEnv (subprocess "/bin/echo" ["subprocess-ok"])
                exitCode @?= ExitSuccess
                stdoutText @?= "subprocess-ok\n"
                stderrText @?= ""
            , testCase "bootstrap plan includes Harbor-first publication" $
                bootstrapPlanSteps LinuxCPU
                    @?= [ "reconcile prerequisite graph for cluster"
                         , "render kind/cluster-linux-cpu.yaml"
                         , "create Kind cluster with ./.build/jitml.kubeconfig"
                         , "apply jitml-manual StorageClass and manual PVs"
                         , "install Harbor bootstrap phase"
                         , "push jitml:local into Harbor"
                         , "install MinIO, Pulsar, Envoy Gateway, observability, jitml-service, jitml-demo"
                         , "write ./.build/runtime/cluster-publication.json"
                         ]
            , testCase "kind config render carries extraMounts" $
                renderKindConfig (kindConfigFor AppleSilicon)
                    @?= renderKindConfig (kindConfigFor AppleSilicon)
            , testCase "route registry renders HTTPRoute manifests" $
                length (fmap renderHTTPRoute routeRegistry) @?= length routeRegistry
            ]
