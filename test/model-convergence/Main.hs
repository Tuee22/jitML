{-# LANGUAGE OverloadedStrings #-}

-- | Phase 285 — the @jitml-model-convergence@ stanza.
--
-- The stanza reads @JITML_SUBSTRATE@ (default @linux-cpu@), loads that lane's
-- pinned, retained ProductScenario journal through the production reader,
-- admits it against the current validated projection, and grades every
-- ProductRow's opaque completed-run evidence: final-quality convergence
-- against the independent external criterion, learning telemetry, committed
-- deterministic performance bounds bound to the artifact identity, and
-- plan/experiment/manifest/cohort binding. A stale, missing, or inadmissible
-- journal fails every lane case closed with the typed diagnostic; a lane is
-- only green where its retained journal is current.
--
-- The mutation, wiring, and gate controls ("Controls", "WiringControls",
-- "GateControls") run on the retained @linux-cuda@ journal regardless of the
-- selected lane, so a stale lane fails only the cases that depend on that lane's
-- evidence.
--
-- Container validation:
-- @docker compose run --rm jitml jitml test jitml-model-convergence --linux-cpu@
module Main where

import Control.Monad (unless, void)
import Data.Bifunctor (first)
import Data.Text (Text)
import Data.Text qualified as Text
import Test.Tasty (TestTree, defaultMain, testGroup, withResource)
import Test.Tasty.HUnit (Assertion, assertFailure, testCase)

import Controls (controlTests, independentTests)
import GateControls (gateTests)
import JitML.Substrate (Substrate, renderSubstrate)
import JitML.Test.ModelConvergence
  ( allRowChecks
  , assertLaneEvidenceCoverage
  , assertRegistryCoverage
  , modelConvergenceRowIds
  , renderRowCheck
  , rowCheckFailures
  , selectedModelConvergenceSubstrate
  )
import JitML.Test.ModelEvidence
  ( LaneEvidence
  , admitModelEvidence
  , renderModelEvidenceLoadError
  , renderModelEvidenceLoadHeadline
  )
import WiringControls (wiringTests)

main :: IO ()
main = do
  selected <- selectedModelConvergenceSubstrate
  defaultMain (suite selected)

suite :: Either Text Substrate -> TestTree
suite selected =
  testGroup
    "jitml-model-convergence"
    [ laneTests selected
    , independentTests
    , controlTests
    , wiringTests
    , gateTests
    ]

-- | Why a lane's evidence is unavailable: the full typed diagnostic (reported
-- once, by the admission and join cases) and its one-line headline (reported
-- by every case that depends on the lane).
data LaneUnavailable = LaneUnavailable
  { unavailableFull :: Text
  , unavailableHeadline :: Text
  }

-- | The lane's admitted evidence, or the rendered typed reason it cannot be
-- admitted. Loading never throws, so every dependent case reports the same
-- diagnostic rather than an opaque resource failure.
loadSelected :: Either Text Substrate -> IO (Either LaneUnavailable LaneEvidence)
loadSelected selection =
  case selection of
    Left reason -> pure (Left (LaneUnavailable reason reason))
    Right lane -> do
      admitted <- admitModelEvidence lane
      pure
        ( first
            (\err -> LaneUnavailable (renderModelEvidenceLoadError err) (renderModelEvidenceLoadHeadline err))
            admitted
        )

-- | Fail with the full diagnostic.
requireLaneFull :: IO (Either LaneUnavailable LaneEvidence) -> IO LaneEvidence
requireLaneFull loaded =
  loaded >>= either (assertFailure . Text.unpack . unavailableFull) pure

-- | Fail with the headline; the full diagnostic is the admission case's.
requireLane :: IO (Either LaneUnavailable LaneEvidence) -> IO LaneEvidence
requireLane loaded =
  loaded >>= either (assertFailure . Text.unpack . unavailableHeadline) pure

assertNoFailures :: [Text] -> Assertion
assertNoFailures failures =
  unless (null failures) $
    assertFailure (Text.unpack (Text.intercalate "\n" failures))

laneTests :: Either Text Substrate -> TestTree
laneTests selection =
  withResource (loadSelected selection) (const (pure ())) $ \loaded ->
    testGroup
      ("lane evidence (" <> laneLabel <> ")")
      ( testGroup
          "lane admission and coverage"
          [ testCase "the pinned lane journal is admitted against the current projection" $
              void (requireLaneFull loaded)
          , testCase "the registry projects to exactly its ProductRows" $
              either (assertFailure . Text.unpack) (assertNoFailures . assertRegistryCoverage) selection
          , testCase "every ProductRow has exactly one bound evidence row (typed join)" $
              requireLaneFull loaded >>= assertNoFailures . assertLaneEvidenceCoverage
          ]
          : [ testGroup
                (Text.unpack (renderRowCheck check))
                [ testCase (Text.unpack rowId) $ do
                    laneEvidence <- requireLane loaded
                    assertNoFailures (rowCheckFailures check laneEvidence rowId)
                | rowId <- modelConvergenceRowIds
                ]
            | check <- allRowChecks
            ]
      )
 where
  laneLabel =
    case selection of
      Left _ -> "unselected"
      Right lane -> Text.unpack (renderSubstrate lane)
