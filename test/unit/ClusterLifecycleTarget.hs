{-# LANGUAGE OverloadedStrings #-}

module ClusterLifecycleTarget (tests) where

import Data.Either (isLeft)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

import JitML.Cluster.LifecycleTarget
import JitML.Cluster.Publication
import JitML.Substrate

tests :: TestTree
tests =
  testGroup
    "Lifecycle exact target and purge policy"
    [ testCase "missing authority requires explicit target" $
        assertBool "must refuse" (isLeft (selectLifecycleTarget Nothing PublicationMissing))
    , testCase "explicit CPU target recovers missing authority without Apple default" $
        selectLifecycleTarget (Just LinuxCPU) PublicationMissing
          @?= Right (LifecycleTarget LinuxCPU Nothing)
    , testCase "corrupt authority refuses despite explicit target" $
        assertBool
          "must refuse"
          (isLeft (selectLifecycleTarget (Just LinuxCPU) (PublicationCorrupt "invalid")))
    , testCase "conflicting explicit target refuses" $
        assertBool "must refuse" (isLeft (selectLifecycleTarget (Just AppleSilicon) cpu))
    , testCase "persisted exact target is selected" $
        selectLifecycleTarget Nothing cpu
          @?= Right (LifecycleTarget LinuxCPU (Just (defaultPublication LinuxCPU)))
    , testCase "reconciling authority supplies target without readiness" $ do
        let publication =
              (defaultPublication LinuxCPU)
                { publicationComponents = [("minio", "reconciling")]
                , publicationEvidence = Nothing
                }
        selectLifecycleTarget (Just LinuxCPU) (PublicationPresent publication)
          @?= Right (LifecycleTarget LinuxCPU (Just publication))
        publicationHasLiveEvidence publication @?= False
    , testCase "invalid port refuses" $
        assertBool
          "must refuse"
          ( isLeft
              ( selectLifecycleTarget
                  Nothing
                  (PublicationPresent ((defaultPublication LinuxCPU) {publicationEdgePort = 65536}))
              )
          )
    , testCase "foreign MinIO endpoint refuses" $
        assertBool
          "must refuse"
          ( isLeft
              ( selectLifecycleTarget
                  Nothing
                  (PublicationPresent ((defaultPublication LinuxCPU) {publicationMinioUrl = "http://other/minio/s3"}))
              )
          )
    , testCase "wrong Pulsar port refuses" $
        assertBool
          "must refuse"
          ( isLeft
              ( selectLifecycleTarget
                  Nothing
                  ( PublicationPresent
                      ((defaultPublication LinuxCPU) {publicationPulsarUrl = "pulsar://127.0.0.1:1/pulsar"})
                  )
              )
          )
    , testCase "stopping clears live evidence and every component" $ do
        let stopped = stoppedPublication (markPublicationLive (defaultPublication LinuxCPU))
        publicationHasLiveEvidence stopped @?= False
        publicationEvidence stopped @?= Nothing
        assertBool "all stopped" (all ((== "stopped") . snd) (publicationComponents stopped))
    , testCase "duplicate substrate operands refuse" $
        assertBool "must refuse" (isLeft (parseLifecycleSubstrate ["linux-cpu", "linux-cpu"]))
    , testCase "unknown substrate refuses" $
        assertBool "must refuse" (isLeft (parseLifecycleSubstrate ["cpu"]))
    , testCase "all supported exact substrate operands parse" $
        mapM_ (\s -> parseLifecycleSubstrate [renderSubstrate s] @?= Right (Just s)) allSubstrates
    , testCase "purge refuses another lane that shares data" $
        assertBool
          "must refuse"
          (isLeft (requireExclusivePurgeTarget LinuxCPU ["jitml-linux-cpu", "jitml-apple-silicon"]))
    , testCase "purge accepts exact lane and absent lane" $ do
        requireExclusivePurgeTarget LinuxCPU ["jitml-linux-cpu"] @?= Right ()
        requireExclusivePurgeTarget LinuxCPU [] @?= Right ()
    ]
 where
  cpu = PublicationPresent (defaultPublication LinuxCPU)
