{-# LANGUAGE OverloadedStrings #-}

module ReconcileStamp
  ( reconcileStampTests
  )
where

import Data.Aeson (decode, encode)
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import System.Directory
  ( createDirectoryIfMissing
  , createFileLink
  , removeFile
  )
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

import JitML.Cluster.ReconcileStamp
  ( DesiredInputFingerprint
  , EvidenceScope (..)
  , LivePublicationObservation (..)
  , ReconcileDecision (..)
  , ReconcileDriftReason (..)
  , ReconcileEvidence (..)
  , ReconcileObservation (..)
  , ReconcileStamp (..)
  , classifyReconcileObservation
  , fingerprintWorkspace
  , mkDesiredInputFingerprint
  , mkReconcileStamp
  , workspaceFingerprintExcludedDirectories
  )
import JitML.Substrate (Substrate (..))

reconcileStampTests :: TestTree
reconcileStampTests =
  testGroup
    "cluster reconcile stamp"
    [ testCase "versioned stamp JSON round-trips exact desired state" $
        decode (encode fixtureStamp) @?= Just fixtureStamp
    , testCase "workspace fingerprint is independent of creation order" $
        withSystemTempDirectory "jitml-reconcile-order" $ \root -> do
          let left = root </> "left"
              right = root </> "right"
          writeEquivalentWorkspace left False
          writeEquivalentWorkspace right True
          leftFingerprint <- fingerprintWorkspace left
          rightFingerprint <- fingerprintWorkspace right
          leftFingerprint @?= rightFingerprint
    , testCase "workspace fingerprint changes with included file content" $
        withSystemTempDirectory "jitml-reconcile-content" $ \root -> do
          createDirectoryIfMissing True (root </> "src")
          writeFile (root </> "src" </> "Main.hs") "main = pure ()\n"
          before <- fingerprintWorkspace root
          writeFile (root </> "src" </> "Main.hs") "main = pure (1 :: Int)\n"
          after <- fingerprintWorkspace root
          assertBool "included source change did not alter fingerprint" (before /= after)
    , testCase "workspace fingerprint excludes mutable generated-cache directories" $
        withSystemTempDirectory "jitml-reconcile-excludes" $ \root -> do
          createDirectoryIfMissing True (root </> "src")
          writeFile (root </> "src" </> "Stable.hs") "stable\n"
          before <- fingerprintWorkspace root
          mapM_ (writeExcludedNoise root) workspaceFingerprintExcludedDirectories
          after <- fingerprintWorkspace root
          after @?= before
    , testCase "workspace fingerprint hashes symlink target without following it" $
        withSystemTempDirectory "jitml-reconcile-symlink" $ \root -> do
          let workspace = root </> "workspace"
              link = workspace </> "external-link"
              outsideA = root </> "outside-a"
              outsideB = root </> "outside-b"
          createDirectoryIfMissing True workspace
          writeFile outsideA "first external bytes\n"
          writeFile outsideB "second external bytes\n"
          createFileLink "../outside-a" link
          initial <- fingerprintWorkspace workspace
          writeFile outsideA "changed external bytes\n"
          externalContentChanged <- fingerprintWorkspace workspace
          externalContentChanged @?= initial
          removeFile link
          createFileLink "../outside-b" link
          targetChanged <- fingerprintWorkspace workspace
          assertBool "symlink target change did not alter fingerprint" (targetChanged /= initial)
    , testCase "complete exact observation is already converged" $
        classifyReconcileObservation convergedObservation @?= AlreadyConverged
    , testCase "missing persisted stamp requires reconcile" $
        classifyReconcileObservation
          (convergedObservation {reconcilePersistedStamp = Nothing})
          @?= NeedsReconcile [ReconcileStampMissing]
    , testCase "classifier returns deterministic exact drift reasons" $
        classifyReconcileObservation driftObservation
          @?= NeedsReconcile expectedDriftReasons
    ]

writeEquivalentWorkspace :: FilePath -> Bool -> IO ()
writeEquivalentWorkspace root reverseOrder = do
  let firstDirectory = root </> if reverseOrder then "zeta" else "alpha"
      secondDirectory = root </> if reverseOrder then "alpha" else "zeta"
  createDirectoryIfMissing True firstDirectory
  createDirectoryIfMissing True secondDirectory
  writeFile (root </> "alpha" </> "a.txt") "alpha\n"
  writeFile (root </> "zeta" </> "z.txt") "zeta\n"
  createFileLink "alpha/a.txt" (root </> "link-to-alpha")

writeExcludedNoise :: FilePath -> FilePath -> IO ()
writeExcludedNoise root directoryName = do
  let directory = root </> directoryName
  createDirectoryIfMissing True directory
  writeFile (directory </> "changing-cache-entry") (directoryName <> "\n")

fixtureFingerprint :: DesiredInputFingerprint
fixtureFingerprint =
  either
    (error . Text.unpack)
    id
    (mkDesiredInputFingerprint (Text.replicate 64 "a"))

otherFingerprint :: DesiredInputFingerprint
otherFingerprint =
  either
    (error . Text.unpack)
    id
    (mkDesiredInputFingerprint (Text.replicate 64 "b"))

fixtureImageIds :: Map.Map Text.Text Text.Text
fixtureImageIds =
  Map.fromList
    [ ("jitml:local", "sha256:jitml")
    , ("jitml-demo:local", "sha256:demo")
    ]

fixtureStamp :: ReconcileStamp
fixtureStamp =
  either
    (error . Text.unpack)
    id
    (mkReconcileStamp LinuxCPU 9091 fixtureFingerprint fixtureImageIds)

readyEvidence :: Text.Text -> ReconcileEvidence
readyEvidence name =
  ReconcileEvidence
    { reconcileEvidenceExpected = [name]
    , reconcileEvidenceObserved = [(name, True)]
    }

convergedObservation :: ReconcileObservation
convergedObservation =
  ReconcileObservation
    { reconcileExpectedStamp = fixtureStamp
    , reconcilePersistedStamp = Just fixtureStamp
    , reconcileLivePublication = LivePublicationReady
    , reconcileReleaseEvidence = readyEvidence "jitml-service"
    , reconcileReadinessEvidence = readyEvidence "edge"
    , reconcileTopicEvidence = readyEvidence "training.command.linux-cpu"
    , reconcileNodeImageEvidence = readyEvidence "worker/jitml:local"
    , reconcileAppImageEvidence = readyEvidence "jitml-service"
    , reconcilePortAwareMaterializationUnchanged = True
    }

driftObservation :: ReconcileObservation
driftObservation =
  ReconcileObservation
    { reconcileExpectedStamp = fixtureStamp
    , reconcilePersistedStamp =
        Just
          fixtureStamp
            { reconcileStampVersion = 2
            , reconcileStampSubstrate = AppleSilicon
            , reconcileStampEdgePort = 9090
            , reconcileStampDesiredInputFingerprint = otherFingerprint
            , reconcileStampRepoAppImageIds =
                Map.singleton "jitml:local" "sha256:stale"
            }
    , reconcileLivePublication = LivePublicationNotReady "edge failed"
    , reconcileReleaseEvidence =
        ReconcileEvidence
          { reconcileEvidenceExpected = ["z-release", "a-release", "a-release"]
          , reconcileEvidenceObserved =
              [ ("z-release", False)
              , ("extra-release", True)
              , ("z-release", True)
              ]
          }
    , reconcileReadinessEvidence =
        ReconcileEvidence
          { reconcileEvidenceExpected = []
          , reconcileEvidenceObserved = []
          }
    , reconcileTopicEvidence =
        ReconcileEvidence
          { reconcileEvidenceExpected = ["topic-a"]
          , reconcileEvidenceObserved = []
          }
    , reconcileNodeImageEvidence =
        ReconcileEvidence
          { reconcileEvidenceExpected = ["node-a"]
          , reconcileEvidenceObserved = [("node-a", False)]
          }
    , reconcileAppImageEvidence =
        ReconcileEvidence
          { reconcileEvidenceExpected = ["app-a"]
          , reconcileEvidenceObserved = [("other-app", True)]
          }
    , reconcilePortAwareMaterializationUnchanged = False
    }

expectedDriftReasons :: [ReconcileDriftReason]
expectedDriftReasons =
  [ ReconcileStampVersionMismatch 1 2
  , ReconcileStampSubstrateMismatch LinuxCPU AppleSilicon
  , ReconcileStampEdgePortMismatch 9091 9090
  , ReconcileStampDesiredInputMismatch fixtureFingerprint otherFingerprint
  , ReconcileStampRepoAppImageIdsMismatch
      fixtureImageIds
      (Map.singleton "jitml:local" "sha256:stale")
  , LivePublicationDrift (LivePublicationNotReady "edge failed")
  , PortAwareMaterializationChanged
  , EvidenceExpectedDuplicate ReleaseEvidence "a-release"
  , EvidenceObservedDuplicate ReleaseEvidence "z-release"
  , EvidenceMissing ReleaseEvidence "a-release"
  , EvidenceUnexpected ReleaseEvidence "extra-release"
  , EvidenceNotReady ReleaseEvidence "z-release"
  , EvidenceExpectedFamilyEmpty ReadinessEvidence
  , EvidenceMissing TopicEvidence "topic-a"
  , EvidenceNotReady NodeImageEvidence "node-a"
  , EvidenceMissing AppImageEvidence "app-a"
  , EvidenceUnexpected AppImageEvidence "other-app"
  ]
