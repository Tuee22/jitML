{-# LANGUAGE OverloadedStrings #-}

module Main where

import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

import JitML.Cluster.Publication (defaultPublication, publicationEdgePort)
import JitML.Routes (routeRegistry, routeServiceName)
import JitML.Storage.Buckets (bucketNames)
import JitML.Substrate (Substrate (..))
import JitML.Test.Report (ReportCard (..), renderReportCard, reportStanzas)
import JitML.Web.Contracts (apiEndpoints)

main :: IO ()
main =
  defaultMain $
    testGroup
      "jitml-e2e"
      [ testCase "edge route registry includes demo and platform services" $ do
          let services = fmap routeServiceName routeRegistry
          assertBool "demo route present" ("jitml-demo" `elem` services)
          assertBool "grafana route present" ("grafana" `elem` services)
          assertBool "pulsar route present" ("jitml-pulsar-proxy" `elem` services)
      , testCase "bucket registry includes checkpoint and tuning buckets" $ do
          assertBool "checkpoints bucket" ("jitml-checkpoints" `elem` bucketNames)
          assertBool "trials bucket" ("jitml-trials" `elem` bucketNames)
      , testCase "publication leases stable per-substrate edge ports" $
          publicationEdgePort (defaultPublication LinuxCUDA) @?= 9092
      , testCase "browser contracts expose interactive surfaces" $
          length apiEndpoints @?= 5
      , testCase "report card renders aggregate suite summary" $ do
          length reportStanzas @?= 10
          renderReportCard (ReportCard 10 0 0) @?= "passed: 10\nfailed: 0\nduration_seconds: 0\n"
      ]
