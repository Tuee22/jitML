{-# LANGUAGE OverloadedStrings #-}

-- | The standing negative-control stanza.
--
-- Each committed control is one tasty case named after it, grouped by the
-- pipeline stage it exercises.  A control fails the stanza if its gate accepts
-- the known-invalid fixture, rejects it for a different reason than the one the
-- control names, or the control's own baseline cannot be built.  The harness
-- self-tests below prove that each of those verdicts really does fail a tasty
-- run, so a silently vacuous harness cannot pass.
--
-- Every product workflow row registers its negative controls, and a guard fails
-- the stanza when a row, a registration, or a control names something the
-- others do not.  The controls the guard reads are the committed list this
-- stanza runs ('allNegativeControls'), not the list the per-row module derives
-- for itself, so a control dropped from the stanza fails it.  The lifecycle
-- controls must cover every constructor of the interpreter's failure vocabulary,
-- the lifecycle specs must all be committed to that list, and a guard fails the
-- stanza when a constructor has no control or a spec has no committed control.
module Main where

import Control.Monad (unless)
import Data.List (sort)
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NonEmpty
import Data.Maybe (fromMaybe)
import Data.Text qualified as Text
import Test.Tasty (TestTree, defaultMain, testGroup, withResource)
import Test.Tasty.HUnit (assertBool, assertEqual, assertFailure, testCase)

import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Test.NegativeControls
  ( ControlCategory (..)
  , ControlOutcome (..)
  , NegativeControl (..)
  , allControlCategories
  , allNegativeControls
  , allNegativeControlsWith
  , categoryCoverageFailures
  , controlTestCase
  , controlsInCategory
  , deferredCategories
  , duplicateControlNames
  , gateSoundnessControls
  , pendingProductionControls
  , renderControlCategory
  , runNegativeControls
  )
import JitML.Test.NegativeControls.Core
  ( effectfulControl
  , gateRejected
  , pureControl
  , pureOutcome
  , rejectedOnlyWhere
  , rejectedWhere
  , rejectedWith
  , treeSucceeds
  , withFixture
  )
import JitML.Test.NegativeControls.Journal (journalBaselineFailures)
import JitML.Test.NegativeControls.Lifecycle
  ( LifecycleSpec (..)
  , allCoverage
  , lifecycleBaselineFailures
  , lifecycleCommitmentFailures
  , lifecycleCoverageFailures
  , lifecycleHarnessFailures
  , lifecycleOrderingFailures
  , lifecycleSpecs
  , renderCoverage
  )
import JitML.Test.NegativeControls.PerRow
  ( RowRegistration (..)
  , RowRegistryFacts (..)
  , RowSpec (..)
  , RowSpecKind (..)
  , buildPerRowFixture
  , perRowFixtureBaselineFailures
  , realRowRegistryFacts
  , renderRowSpecKind
  , rowBaselineFailures
  , rowRegistrationFailures
  , rowRegistrationFailuresFor
  , withoutFirst
  )
import JitML.Test.NegativeControls.Request (baselineFailures)
import JitML.Test.ReducerProperties (reducerPropertySubset)

main :: IO ()
main =
  defaultMain $
    testGroup
      "jitml-negative-controls"
      ( [ testCase "every committed known-fake is rejected by its gate" $ do
            failures <- runNegativeControls gateSoundnessControls
            assertBool (Text.unpack (Text.intercalate "\n" failures)) (null failures)
        , testCase "at least one gate-soundness control is committed" $
            assertBool "no negative controls committed" (not (null gateSoundnessControls))
        , testCase "no production-path control is pending and no control category is deferred" $ do
            assertEqual "pending production controls" [] pendingProductionControls
            assertEqual "deferred control categories" [] deferredCategories
        , testCase "every product row registers its negative controls, and nothing else does" $
            assertEqual "row registration failures" [] (rowRegistrationFailures allNegativeControls)
        ]
          <> [ categoryGroup category
             | category <- allControlCategories
             , not (null (controlsInCategory category allNegativeControls))
             ]
          <> [ guards
             , registrationGuards
             , lifecycleGuards
             , harnessSelfTests
             , reducerPropertySubset
             ]
      )

-- | One tasty group per populated category.  The per-row foreign-admission
-- controls share one real Store-admitted fixture, built once for the whole
-- group and released after it.
categoryGroup :: ControlCategory -> TestTree
categoryGroup category
  | category == PerRow =
      withResource buildPerRowFixture (const (pure ())) (groupOf . allNegativeControlsWith)
  | otherwise = groupOf allNegativeControls
 where
  groupOf controls =
    testGroup (Text.unpack (renderControlCategory category) <> " controls") $
      fmap controlTestCase (controlsInCategory category controls)

-- | Structural guards over the control registry itself.
guards :: TestTree
guards =
  testGroup
    "control registry guards"
    [ testCase "control names are unique" $
        assertEqual "duplicate control names" [] (duplicateControlNames allNegativeControls)
    , testCase "every populated control category has at least one control" $
        assertEqual
          "category coverage"
          []
          (categoryCoverageFailures deferredCategories allNegativeControls)
    , testCase "every request baseline refines, so no request control is vacuous" $
        assertEqual "request baselines that failed to refine" [] baselineFailures
    , testCase
        "the journal baseline is admitted by the production reader, so no journal control is vacuous"
        $ do
          failures <- journalBaselineFailures
          assertEqual "journal baseline failures" [] failures
    ]

-- | Guards over the per-row registration: the registry rows are sound baselines,
-- the Store-admitted fixture is accepted by its own rows, and the registration
-- guard itself flags every way a row can escape its controls.
registrationGuards :: TestTree
registrationGuards =
  testGroup
    "per-row registration guards"
    [ testCase "every registry row is a sound baseline for its controls" $
        assertEqual "row baseline failures" [] rowBaselineFailures
    , withResource buildPerRowFixture (const (pure ())) $ \fixture ->
        testCase
          "the Store-admitted fixture is accepted by its own rows, so a foreign admission is rejected for being foreign"
          $ do
            admitted <- fixture
            assertEqual "per-row fixture failures" [] (perRowFixtureBaselineFailures admitted)
    , testGroup
        "the registration guard flags each way a row can escape its controls"
        [ flags
            "a row without a registration"
            facts {factRegistrations = withoutFirst registrations, factControlNames = drop 3 controlNames}
            ["product row has no registered negative control: " <> firstId]
        , flags
            "a row registered twice"
            facts {factRegistrations = registrations <> take 1 registrations}
            ["product row is registered more than once: " <> firstId]
        , flags
            "a registration that names no product row"
            facts {factRegistrations = registrations <> [ghostRegistration]}
            [ "registration names no product row: ghost-row"
            , "a registration names a row absent from the projection batch: ghost-row"
            , "registered spec has no control: row-ghost-row-invalid-request"
            ]
        , flags
            "a spec for a family that is not the row's"
            facts
              { factRegistrations =
                  mapFirst
                    ( \registration ->
                        registration
                          { registeredSpecs =
                              fmap (\spec -> spec {specFamily = ProductMatrix.AlphaZero}) (registeredSpecs registration)
                          }
                    )
                    registrations
              }
            ["spec invalid-request of row " <> firstId <> " is for family AlphaZero but the row is Supervised"]
        , flags
            "a spec for another run kind than its row's registration"
            facts
              { factRegistrations =
                  mapFirst
                    ( \registration ->
                        registration
                          { registeredSpecs =
                              fmap
                                (\spec -> spec {specRunKind = ProductMatrix.ProductRlRun})
                                (registeredSpecs registration)
                          }
                    )
                    registrations
              }
            [ "spec invalid-request of row "
                <> firstId
                <> " is for run kind ProductRlRun but the row is registered as ProductSupervisedRun"
            ]
        , flags
            "a row registered as the wrong run kind"
            facts
              { factRegistrations =
                  mapFirst
                    (\registration -> registration {registeredRunKind = ProductMatrix.ProductRlRun})
                    registrations
              }
            ["row " <> firstId <> " is registered as run kind ProductRlRun but its family is Supervised"]
        , flags
            "a spec registered twice"
            facts
              { factRegistrations =
                  mapFirst
                    ( \registration -> registration {registeredSpecs = registeredSpecs registration <> registeredSpecs registration}
                    )
                    registrations
              }
            ["row " <> firstId <> " registers spec invalid-request twice"]
        , flags
            "a registered spec whose control is missing"
            facts {factControlNames = withoutFirst controlNames}
            ["registered spec has no control: " <> renderControlName firstId InvalidRequest]
        , flags
            "a control that names no registered spec"
            facts {factControlNames = "row-ghost-row-invalid-request" : controlNames}
            ["control names no registered spec: row-ghost-row-invalid-request"]
        , flags
            "a control committed twice"
            facts {factControlNames = controlNames <> take 1 controlNames}
            ["control name is committed more than once: " <> renderControlName firstId InvalidRequest]
        , flags
            "a registry that does not project as a batch"
            facts {factBatch = Left "the registry is broken"}
            ["the product registry does not project as a batch: the registry is broken"]
        , flags
            "a projection batch that omits a row"
            facts {factBatch = fmap withoutFirst (factBatch facts)}
            [ "product row is in the registry but absent from the projection batch: " <> firstId
            , "a registration names a row absent from the projection batch: " <> firstId
            ]
        , flags
            "a projection batch that names a row the registry lacks"
            facts {factBatch = fmap (<> ["ghost-row"]) (factBatch facts)}
            ["the projection batch names a row absent from the registry: ghost-row"]
        , flags
            "a registry that lists a row twice"
            facts {factRegistry = factRegistry facts <> take 1 (factRegistry facts)}
            ["the product registry lists a row twice: " <> firstId]
        , flags
            "a run kind with no registered row"
            facts
              { factRegistrations =
                  filter ((/= ProductMatrix.ProductAlphaZeroRun) . registeredRunKind) registrations
              , factControlNames = filter (not . isAlphaZeroControl) controlNames
              }
            ["no registered row has run kind ProductAlphaZeroRun"]
        , flags
            "a run kind that registers no spec of some kind"
            facts
              { factRegistrations =
                  [ registration {registeredSpecs = withoutSpec ForeignAdmission (registeredSpecs registration)}
                  | registration <- registrations
                  ]
              , factControlNames = filter (not . isForeignAdmissionControl) controlNames
              }
            ["run kind ProductSupervisedRun registers no foreign-admission spec"]
        ]
    , testGroup
        "the registration guard reads the list the stanza runs"
        [ flagsCommitted
            "per-row controls dropped from the committed list"
            (filter (not . isForeignAdmission) allNegativeControls)
            [ "registered spec has no control: " <> renderControlName identity ForeignAdmission
            | (identity, _family) <- factRegistry facts
            ]
        , flagsCommitted
            "a per-row control filed under another category"
            (recategoriseFirst PerRow allNegativeControls)
            ["registered spec has no control: " <> renderControlName firstId InvalidRequest]
        , flagsCommitted
            "a per-row control committed twice"
            (allNegativeControls <> take 1 (controlsInCategory PerRow allNegativeControls))
            ["control name is committed more than once: " <> renderControlName firstId InvalidRequest]
        ]
    ]
 where
  facts = realRowRegistryFacts allNegativeControls
  registrations = factRegistrations facts
  controlNames = factControlNames facts
  firstId =
    case factRegistry facts of
      (identity, _family) : _ -> identity
      [] -> "the-empty-registry"
  ghostRegistration =
    RowRegistration
      { registeredRowId = "ghost-row"
      , registeredRunKind = ProductMatrix.ProductSupervisedRun
      , registeredSpecs =
          RowSpec InvalidRequest ProductMatrix.ProductSupervisedRun ProductMatrix.Supervised
            :| []
      }
  mapFirst change registrationList =
    case registrationList of
      first' : rest -> change first' : rest
      [] -> []
  renderControlName identity kind = "row-" <> identity <> "-" <> renderRowSpecKind kind
  isForeignAdmission control =
    ncCategory control == PerRow && Text.isSuffixOf "-foreign-admission" (ncName control)
  -- Corrupting the committed list, never the facts derived from it, changes only
  -- the control view, so the guard must report exactly the named failures.
  flagsCommitted label committed expected =
    testCase label $
      assertEqual "row registration failures" (sort expected) (sort (rowRegistrationFailures committed))
  isAlphaZeroControl name =
    any
      (\identity -> ("row-" <> identity <> "-") `Text.isPrefixOf` name)
      [identity | (identity, ProductMatrix.AlphaZero) <- factRegistry facts]
  isForeignAdmissionControl = Text.isSuffixOf "-foreign-admission"
  withoutSpec kind specs =
    fromMaybe specs (NonEmpty.nonEmpty (NonEmpty.filter ((/= kind) . specKind) specs))
  -- Each corrupted registration is reported, and every named failure is among the reports.
  flags label corrupted expected =
    testCase label $ do
      let failures = rowRegistrationFailuresFor corrupted
      assertBool
        ("the corrupted registration was not reported at all: " <> label)
        (not (null failures))
      unless (all (`elem` failures) expected) $
        assertFailure
          ( "expected failures "
              <> show expected
              <> " but the guard reported "
              <> show failures
          )

-- | Guards over the lifecycle controls: every constructor of the interpreter's
-- failure vocabulary has a control, the baselines the controls perturb
-- complete, both arrival orders of the terminal and the evidence mint the same
-- completion, and the guards themselves flag what they must.
lifecycleGuards :: TestTree
lifecycleGuards =
  testGroup
    "lifecycle guards"
    [ testCase
        "every closed-sum constructor of the interpreter's failure vocabulary has a lifecycle control"
        $ assertEqual "lifecycle coverage failures" [] (lifecycleCoverageFailures lifecycleSpecs)
    , testCase "the coverage guard names every constructor whose controls are removed" $
        assertEqual
          "constructors the guard failed to flag once their controls were removed"
          []
          [ renderCoverage coverage
          | coverage <- allCoverage
          , let remaining = [spec | spec <- lifecycleSpecs, coverage `notElem` specCovers spec]
          , ("no lifecycle control covers " <> renderCoverage coverage)
              `notElem` lifecycleCoverageFailures remaining
          ]
    , testCase "the lifecycle baselines complete, so no lifecycle control is vacuous" $ do
        failures <- lifecycleBaselineFailures
        assertEqual "lifecycle baseline failures" [] failures
    , testCase "the terminal-first and evidence-first orders mint the same completion" $ do
        failures <- lifecycleOrderingFailures
        assertEqual "lifecycle ordering failures" [] failures
    , testCase "the lifecycle verdict reports a completed run as accepted and a wrong reason as wrong" $ do
        failures <- lifecycleHarnessFailures
        assertEqual "lifecycle harness failures" [] failures
    , testCase "every lifecycle spec is committed to the list the stanza runs, and nothing else is" $
        assertEqual "lifecycle commitment failures" [] (lifecycleCommitmentFailures allNegativeControls)
    , testGroup
        "the commitment guard reads the list the stanza runs"
        [ testCase "a lifecycle control dropped from the committed list is reported" $
            assertEqual
              "lifecycle commitment failures"
              ["lifecycle spec has no committed control: " <> name | name <- take 1 specNames]
              (lifecycleCommitmentFailures (drop1Lifecycle allNegativeControls))
        , testCase "a lifecycle control filed under another category is reported" $
            assertEqual
              "lifecycle commitment failures"
              ["lifecycle spec has no committed control: " <> name | name <- take 1 specNames]
              (lifecycleCommitmentFailures (recategoriseFirst Lifecycle allNegativeControls))
        , testCase "a committed lifecycle control that no spec describes is reported" $
            assertEqual
              "lifecycle commitment failures"
              ["committed lifecycle control names no spec: lifecycle-ghost"]
              ( lifecycleCommitmentFailures
                  ( pureControl Lifecycle "lifecycle-ghost" "a control no spec describes" Rejected
                      : allNegativeControls
                  )
              )
        ]
    ]
 where
  specNames = fmap specName lifecycleSpecs
  drop1Lifecycle controls =
    case break ((== Lifecycle) . ncCategory) controls of
      (before, _dropped : after) -> before <> after
      (before, []) -> before

-- | The committed list with the first control of a category filed under another
-- category, so the stanza no longer runs it as a control of the original one.
recategoriseFirst :: ControlCategory -> [NegativeControl] -> [NegativeControl]
recategoriseFirst category controls =
  case break ((== category) . ncCategory) controls of
    (before, control : after) -> before <> [control {ncCategory = otherCategory}] <> after
    (before, []) -> before
 where
  otherCategory = if category == Gate then Request else Gate

-- | The harness must fail loudly on every verdict that is not an expected-reason
-- rejection.  Each self-test builds a control with the same helpers the real
-- controls use, then proves both that the failure list names it and that a
-- tasty tree containing it does not pass.  'verdictHelperSelfTests' pins the
-- helpers themselves on every input they must not pass.
harnessSelfTests :: TestTree
harnessSelfTests =
  testGroup
    "harness self-test"
    [ testCase "a control rejected for its expected reason passes" $ do
        let control = expectedReasonControl
        assertEqual "verdict" Rejected (verdictOf control)
        failures <- runNegativeControls [control]
        assertEqual "failures" [] failures
        passes <- treeSucceeds (controlTestCase control)
        assertBool "a correctly rejected control failed the tree" passes
    , testCase "an ACCEPTED known-invalid fixture fails the stanza" $ do
        let control = acceptedControl
        assertEqual "verdict" Accepted (verdictOf control)
        failures <- runNegativeControls [control]
        assertBool
          "the accepted control is not named in the failure list"
          (any (Text.isInfixOf "ACCEPTED a known fake") failures)
        passes <- treeSucceeds (controlTestCase control)
        assertBool "an accepted control did not fail the tree" (not passes)
    , testCase "a rejection for the WRONG reason fails the stanza" $ do
        let control = wrongReasonControl
        assertBool "verdict is not RejectedForWrongReason" (isWrongReason (verdictOf control))
        failures <- runNegativeControls [control]
        assertBool
          "the wrong-reason control is not named in the failure list"
          (any (Text.isInfixOf "WRONG reason") failures)
        passes <- treeSucceeds (controlTestCase control)
        assertBool "a wrong-reason control did not fail the tree" (not passes)
    , testCase "a gate that fails for an unrelated message is a wrong-reason rejection" $ do
        let control =
              pureControl
                Gate
                "self-test-gate-unrelated-message"
                "self-test"
                (gateRejected ["the expected defect"] ["some unrelated defect"])
        assertBool "verdict is not RejectedForWrongReason" (isWrongReason (verdictOf control))
    , testCase "a control whose fixture cannot be built fails the stanza" $ do
        let control =
              effectfulControl
                Journal
                "self-test-fixture-failure"
                "self-test"
                (pure (FixtureFailed "baseline could not be built"))
        failures <- runNegativeControls [control]
        assertBool
          "the broken-fixture control is not named in the failure list"
          (any (Text.isInfixOf "fixture failed") failures)
        passes <- treeSucceeds (controlTestCase control)
        assertBool "a broken-fixture control did not fail the tree" (not passes)
    , testCase "an effectful control that throws fails the stanza instead of crashing it" $ do
        let control =
              effectfulControl
                Journal
                "self-test-effectful-exception"
                "self-test"
                (ioError (userError "effectful fixture exploded"))
        failures <- runNegativeControls [control]
        assertBool
          "the throwing control is not named in the failure list"
          (any (Text.isInfixOf "raised an exception") failures)
    , testCase "an effectful control is judged by the same verdicts as a pure one" $ do
        let control =
              effectfulControl
                Journal
                "self-test-effectful-accepted"
                "self-test"
                (pure (rejectedWith ("boom" :: Text.Text) (Right ())))
        failures <- runNegativeControls [control]
        assertBool
          "an accepted effectful control is not reported"
          (any (Text.isInfixOf "ACCEPTED a known fake") failures)
    , testCase "the coverage guard flags an unpopulated, non-deferred category" $
        assertBool
          "an empty Request category was not flagged"
          ( not
              ( null
                  ( categoryCoverageFailures
                      [Lifecycle, PerRow]
                      [pureControl Gate "self-test-only-gate" "self-test" Rejected]
                  )
              )
          )
    , testCase "the coverage guard flags a deferred category that already has controls" $
        assertBool
          "a populated but deferred Lifecycle category was not flagged"
          ( any
              (Text.isInfixOf "listed as deferred")
              ( categoryCoverageFailures
                  [Lifecycle, PerRow]
                  ( fmap
                      (\category -> pureControl category (Text.pack (show category)) "self-test" Rejected)
                      [Gate, Request, Event, Journal, Lifecycle]
                  )
              )
          )
    , testCase "the duplicate-name guard flags a repeated control name" $
        assertEqual
          "duplicate names"
          ["self-test-duplicate"]
          ( duplicateControlNames
              [ pureControl Gate "self-test-duplicate" "first" Rejected
              , pureControl Gate "self-test-duplicate" "second" Rejected
              ]
          )
    , verdictHelperSelfTests
    ]
 where
  verdictOf control =
    fromMaybe (FixtureFailed "self-test control is effectful") (pureOutcome control)

isAccepted :: ControlOutcome -> Bool
isAccepted outcome =
  case outcome of
    Accepted -> True
    Rejected -> False
    RejectedForWrongReason _ _ -> False
    FixtureFailed _ -> False

isWrongReason :: ControlOutcome -> Bool
isWrongReason outcome =
  case outcome of
    RejectedForWrongReason _ _ -> True
    Rejected -> False
    Accepted -> False
    FixtureFailed _ -> False

isFixtureFailed :: ControlOutcome -> Bool
isFixtureFailed outcome =
  case outcome of
    FixtureFailed _ -> True
    Rejected -> False
    Accepted -> False
    RejectedForWrongReason _ _ -> False

-- | The verdict helpers every real control is built from.
--
-- A helper that waved a known-invalid fixture through would silently turn
-- every control built on it into a control that passes for any reason (or
-- never fails), and no real control would notice: each real control is
-- rejected for the reason it names, so it passes either way.  The helpers are
-- therefore pinned on every input they must NOT pass, both by the verdict they
-- return and by a real tasty run of a control that carries that verdict, and
-- on the inputs they must pass, so a helper cannot be made trivially strict
-- either.
verdictHelperSelfTests :: TestTree
verdictHelperSelfTests =
  testGroup
    "verdict helpers"
    [ testGroup
        "must fail the stanza"
        [ failsAs
            "rejectedWith: the gate accepted the fixture"
            isAccepted
            (rejectedWith expectedReason (Right () :: Either Text.Text ()))
        , failsAs
            "rejectedWith: the gate rejected it for a different reason"
            isWrongReason
            (rejectedWith expectedReason (Left "some other rejection" :: Either Text.Text ()))
        , failsAs
            "rejectedWith: the expected rejection plus a second defect is compared whole"
            isWrongReason
            (rejectedWith ["first defect"] (Left ["first defect", "second defect"] :: Either [Text.Text] ()))
        , failsAs
            "rejectedWith: a part of the expected rejection is not the expected rejection"
            isWrongReason
            (rejectedWith ["first defect", "second defect"] (Left ["first defect"] :: Either [Text.Text] ()))
        , failsAs
            "rejectedWhere: the gate accepted the fixture"
            isAccepted
            (rejectedWhere "a named reason" (const True) (Right () :: Either Text.Text ()))
        , failsAs
            "rejectedWhere: the rejection does not satisfy the named reason"
            isWrongReason
            ( rejectedWhere
                "a named reason"
                (== expectedReason)
                (Left "some other rejection" :: Either Text.Text ())
            )
        , failsAs
            "rejectedOnlyWhere: the gate accepted the fixture"
            isAccepted
            (rejectedOnlyWhere "a named reason" (const True) (Right () :: Either (NonEmpty Text.Text) ()))
        , failsAs
            "rejectedOnlyWhere: the one reported error does not satisfy the named reason"
            isWrongReason
            ( rejectedOnlyWhere
                "a named reason"
                (== expectedReason)
                (Left ("some other rejection" :| []) :: Either (NonEmpty Text.Text) ())
            )
        , failsAs
            "rejectedOnlyWhere: a second error was reported beside the expected one"
            isWrongReason
            ( rejectedOnlyWhere
                "a named reason"
                (== expectedReason)
                (Left (expectedReason :| ["a second error"]) :: Either (NonEmpty Text.Text) ())
            )
        , failsAs
            "withFixture: the baseline could not be built"
            isFixtureFailed
            (withFixture (Left "no baseline" :: Either Text.Text ()) (const Rejected))
        , failsAs
            "withFixture: the continuation's verdict is returned, not replaced"
            isAccepted
            (withFixture (Right () :: Either Text.Text ()) (const Accepted))
        , failsAs
            "withFixture: the built fixture is what the continuation judges"
            isWrongReason
            ( withFixture
                (Right (7 :: Int) :: Either Text.Text Int)
                (\built -> rejectedWith (8 :: Int) (Left built :: Either Int ()))
            )
        , failsAs
            "gateRejected: the gate reported no failure"
            isAccepted
            (gateRejected ["the expected defect"] [])
        , failsAs
            "gateRejected: the gate failed only for an unrelated reason"
            isWrongReason
            (gateRejected ["the expected defect"] ["some unrelated defect"])
        , failsAs
            "gateRejected: only one of two expected failures was reported"
            isWrongReason
            (gateRejected ["first defect", "second defect"] ["the first defect was found"])
        ]
    , testGroup
        "must pass the stanza"
        [ passesAs
            "rejectedWith: the expected rejection"
            (rejectedWith expectedReason (Left expectedReason :: Either Text.Text ()))
        , passesAs
            "rejectedWith: the whole expected rejection, in order"
            ( rejectedWith
                ["first defect", "second defect"]
                (Left ["first defect", "second defect"] :: Either [Text.Text] ())
            )
        , passesAs
            "rejectedWhere: the rejection satisfies the named reason"
            (rejectedWhere "a named reason" (== expectedReason) (Left expectedReason :: Either Text.Text ()))
        , passesAs
            "rejectedOnlyWhere: the one reported error satisfies the named reason"
            ( rejectedOnlyWhere
                "a named reason"
                (== expectedReason)
                (Left (expectedReason :| []) :: Either (NonEmpty Text.Text) ())
            )
        , passesAs
            "withFixture: a built fixture is judged by the continuation"
            ( withFixture
                (Right (7 :: Int) :: Either Text.Text Int)
                (\built -> rejectedWith (7 :: Int) (Left built :: Either Int ()))
            )
        , passesAs
            "gateRejected: every expected failure is named by some message"
            ( gateRejected
                ["first defect", "second defect"]
                ["the first defect was found", "and the second defect"]
            )
        , passesAs
            "gateRejected: one message may name several expected failures"
            (gateRejected ["first defect", "second defect"] ["the first defect and the second defect"])
        ]
    ]
 where
  expectedReason = "bad quantity" :: Text.Text

-- | The helper produced a verdict of the expected kind, and a tasty tree that
-- holds a control carrying that verdict really fails.
failsAs :: String -> (ControlOutcome -> Bool) -> ControlOutcome -> TestTree
failsAs label verdictIs outcome =
  testCase label $ do
    assertBool ("unexpected verdict: " <> show outcome) (verdictIs outcome)
    passed <- treeSucceeds (controlTestCase (pureControl Request (Text.pack label) "self-test" outcome))
    assertBool "a control carrying this verdict did not fail the tree" (not passed)

-- | The helper produced 'Rejected', and a tasty tree that holds a control
-- carrying that verdict really passes.
passesAs :: String -> ControlOutcome -> TestTree
passesAs label outcome =
  testCase label $ do
    assertEqual "verdict" Rejected outcome
    passed <- treeSucceeds (controlTestCase (pureControl Request (Text.pack label) "self-test" outcome))
    assertBool "a control carrying this verdict did not pass the tree" passed

-- | A control whose (simulated) gate rejects with exactly the expected reason.
expectedReasonControl :: NegativeControl
expectedReasonControl =
  pureControl
    Request
    "self-test-expected-reason"
    "rejected for the reason it names"
    (rejectedWith ("bad quantity" :: Text.Text) (Left "bad quantity" :: Either Text.Text ()))

-- | A control whose (simulated) gate accepts the known-invalid fixture.
acceptedControl :: NegativeControl
acceptedControl =
  pureControl
    Request
    "self-test-accepted"
    "a gate that accepts a known-invalid fixture"
    (rejectedWith ("bad quantity" :: Text.Text) (Right ()))

-- | A control whose (simulated) gate rejects, but not for the injected defect.
wrongReasonControl :: NegativeControl
wrongReasonControl =
  pureControl
    Request
    "self-test-wrong-reason"
    "a gate that rejects for an unrelated reason"
    ( rejectedWhere
        "a non-positive quantity"
        (== ("an unrelated failure" :: Text.Text))
        (Left "something else entirely" :: Either Text.Text ())
    )
