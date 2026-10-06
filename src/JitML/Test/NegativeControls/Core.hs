{-# LANGUAGE OverloadedStrings #-}

-- | The reason-aware negative-control harness shared by every control family.
--
-- A negative control commits a KNOWN-INVALID artifact (a raw request, an event
-- stream, a journal, a hand-built fake) and asserts that a production gate
-- __rejects it for the right reason__.  Three verdicts are failures:
--
-- * 'Accepted' — the gate let a known-invalid fixture through;
-- * 'RejectedForWrongReason' — the gate rejected the fixture, but for a reason
--   other than the defect the control injected, so the control proves nothing
--   about the guard it names;
-- * 'FixtureFailed' — the control's own baseline could not be built.
--
-- A control's 'Rejected' verdict must come from one of the verdict helpers
-- ('rejectedWith', 'rejectedWhere', 'rejectedOnlyWhere', 'gateRejected', and
-- 'withFixture' around them), never from a hand-built @Rejected@.  The
-- stanza's harness self-tests pin those helpers on every input they must not
-- pass, so a hand-built verdict would be an unpinned path that could silently
-- turn its control into one that passes for any reason.
--
-- Pure controls (request refinement, event reducers, gate predicates) stay
-- pure: they carry an already-computed 'ControlOutcome'.  Controls that need
-- the file system, a Store, or a workflow interpreter (journal and lifecycle
-- controls) use the explicit 'EffectfulCheck' constructor instead.  Each
-- control becomes exactly one tasty test case so a red control names itself.
module JitML.Test.NegativeControls.Core
  ( ControlCategory (..)
  , ControlCheck (..)
  , ControlOutcome (..)
  , NegativeControl (..)
  , allControlCategories
  , categoriesWithoutControls
  , categoryCoverageFailures
  , controlFailure
  , controlTestCase
  , duplicateControlNames
  , effectfulControl
  , fixtureFailed
  , gateRejected
  , pureControl
  , pureOutcome
  , renderControlCategory
  , rejectedOnlyWhere
  , rejectedWhere
  , rejectedWith
  , runControl
  , runNegativeControls
  , treeSucceeds
  , withFixture
  )
where

import Control.Concurrent.STM (atomically, readTVar, retry)
import Control.Exception (evaluate)
import Control.Exception.Safe (tryAny)
import Data.IntMap.Strict qualified as IntMap
import Data.List qualified as List
import Data.List.NonEmpty (NonEmpty (..))
import Data.Maybe (catMaybes)
import Data.Text (Text)
import Data.Text qualified as Text
import Test.Tasty (TestTree)
import Test.Tasty.HUnit (assertFailure, testCase)
import Test.Tasty.Options (OptionSet, setOption)
import Test.Tasty.Runners
  ( NumThreads (..)
  , Status (..)
  , launchTestTree
  , resultSuccessful
  )

-- | The stage of the validated-plan / evidence pipeline a control exercises.
--
-- 'Lifecycle' and 'PerRow' have no controls yet; they are owned by Phase 282
-- and are listed as deferred by 'JitML.Test.NegativeControls.deferredCategories'
-- until that phase populates them.
data ControlCategory
  = -- | Pure gate-soundness fakes (row assertions, external bars, codegen text).
    Gate
  | -- | Known-invalid raw requests driven through plan refinement.
    Request
  | -- | Known-invalid event streams driven through the contract reducers.
    Event
  | -- | Storage/completion journals that omit or corrupt the admitted identity.
    Journal
  | -- | Workflow lifecycle: settlement, timeout, cleanup, terminal order.
    Lifecycle
  | -- | The mandatory per-ProductRow registration matrix.
    PerRow
  deriving stock (Eq, Ord, Show, Enum, Bounded)

allControlCategories :: [ControlCategory]
allControlCategories = [minBound .. maxBound]

renderControlCategory :: ControlCategory -> Text
renderControlCategory category =
  case category of
    Gate -> "gate"
    Request -> "request"
    Event -> "event"
    Journal -> "journal"
    Lifecycle -> "lifecycle"
    PerRow -> "per-row"

-- | What a gate did with a known-invalid fixture.  'Rejected' is the only
-- passing verdict.
data ControlOutcome
  = -- | Rejected, and for the reason the control names.
    Rejected
  | -- | The gate ACCEPTED a known-invalid fixture: the gate is broken.
    Accepted
  | -- | Rejected, but not for the injected defect.  The first field describes
    -- the expected rejection, the second renders the observed one.
    RejectedForWrongReason Text Text
  | -- | The control's own baseline fixture could not be constructed, so the
    -- control proves nothing.
    FixtureFailed Text
  deriving stock (Eq, Show)

-- | Pure controls carry an already-computed verdict; effectful controls
-- compute theirs in 'IO'.
data ControlCheck
  = PureCheck ControlOutcome
  | EffectfulCheck (IO ControlOutcome)

-- | One named known-invalid fixture and the verdict its gate produced.  The
-- record carries no derived 'Eq' or 'Show': an effectful check is opaque.
data NegativeControl = NegativeControl
  { ncName :: Text
  , ncCategory :: ControlCategory
  , ncDescription :: Text
  , ncCheck :: ControlCheck
  }

pureControl :: ControlCategory -> Text -> Text -> ControlOutcome -> NegativeControl
pureControl category name description outcome =
  NegativeControl
    { ncName = name
    , ncCategory = category
    , ncDescription = description
    , ncCheck = PureCheck outcome
    }

effectfulControl :: ControlCategory -> Text -> Text -> IO ControlOutcome -> NegativeControl
effectfulControl category name description action =
  NegativeControl
    { ncName = name
    , ncCategory = category
    , ncDescription = description
    , ncCheck = EffectfulCheck action
    }

-- | The verdict of a pure control; 'Nothing' for an effectful one.
pureOutcome :: NegativeControl -> Maybe ControlOutcome
pureOutcome control =
  case ncCheck control of
    PureCheck outcome -> Just outcome
    EffectfulCheck _ -> Nothing

-- | The observed rejection must equal the expected one exactly.  A refinement
-- that accumulates errors is compared as a whole, so a control built from a
-- valid baseline plus one injected defect also proves no other defect was
-- reported.
rejectedWith
  :: (Eq rejection, Show rejection)
  => rejection
  -> Either rejection accepted
  -> ControlOutcome
rejectedWith expected observed =
  case observed of
    Right _ -> Accepted
    Left rejection
      | rejection == expected -> Rejected
      | otherwise -> RejectedForWrongReason (renderShown expected) (renderShown rejection)

-- | The observed rejection must satisfy a predicate that names the reason.
-- Use it where an exact comparison would pin an incidental payload (a rendered
-- I/O error, for example) rather than the guard under test.
rejectedWhere
  :: (Show rejection)
  => Text
  -> (rejection -> Bool)
  -> Either rejection accepted
  -> ControlOutcome
rejectedWhere reason matches observed =
  case observed of
    Right _ -> Accepted
    Left rejection
      | matches rejection -> Rejected
      | otherwise -> RejectedForWrongReason reason (renderShown rejection)

-- | The observed rejection must be exactly one error, and that error must
-- satisfy a predicate that names the reason.  A second reported error means a
-- further guard fired beside the one the control injects, so the control is
-- reported as 'RejectedForWrongReason' rather than passing.
rejectedOnlyWhere
  :: (Show rejection)
  => Text
  -> (rejection -> Bool)
  -> Either (NonEmpty rejection) accepted
  -> ControlOutcome
rejectedOnlyWhere reason matches =
  rejectedWhere reason $ \case
    only :| [] -> matches only
    _ -> False

-- | A pure gate that reports a list of failure messages.  An empty list is an
-- acceptance; a non-empty list is a rejection only if every expected fragment
-- is named by some message, so a gate that fails for an unrelated reason is
-- reported as 'RejectedForWrongReason' rather than passing vacuously.
gateRejected :: [Text] -> [Text] -> ControlOutcome
gateRejected expectedFragments failures
  | null failures = Accepted
  | all mentioned expectedFragments = Rejected
  | otherwise =
      RejectedForWrongReason
        ("failures mentioning: " <> Text.intercalate " | " expectedFragments)
        (Text.intercalate "; " failures)
 where
  mentioned fragment = any (fragment `Text.isInfixOf`) failures

fixtureFailed :: Text -> ControlOutcome
fixtureFailed = FixtureFailed

-- | Continue with a fixture built by an 'Either'-returning constructor, or
-- report the control as 'FixtureFailed' rather than crash.
withFixture :: Either Text fixture -> (fixture -> ControlOutcome) -> ControlOutcome
withFixture built continue =
  case built of
    Left detail -> FixtureFailed detail
    Right fixture -> continue fixture

renderShown :: (Show value) => value -> Text
renderShown = Text.pack . show

-- | Run one control.  An exception raised while evaluating a pure verdict or
-- running an effectful check is reported as 'FixtureFailed'; asynchronous
-- exceptions still propagate.
runControl :: NegativeControl -> IO ControlOutcome
runControl control = do
  attempted <-
    tryAny $
      case ncCheck control of
        PureCheck outcome -> evaluate outcome
        EffectfulCheck action -> action >>= evaluate
  pure $
    case attempted of
      Right outcome -> outcome
      Left exception ->
        FixtureFailed ("control raised an exception: " <> renderShown exception)

-- | The failure message for a non-passing verdict, or 'Nothing' when the gate
-- rejected the fixture for the expected reason.
controlFailure :: NegativeControl -> ControlOutcome -> Maybe Text
controlFailure control outcome =
  case outcome of
    Rejected -> Nothing
    Accepted ->
      Just
        ( "negative control ACCEPTED a known fake (gate is broken): "
            <> label
        )
    RejectedForWrongReason expected observed ->
      Just
        ( "negative control was rejected for the WRONG reason: "
            <> label
            <> "\n  expected: "
            <> expected
            <> "\n  observed: "
            <> observed
        )
    FixtureFailed detail ->
      Just
        ( "negative control fixture failed, so the control proves nothing: "
            <> label
            <> "\n  detail: "
            <> detail
        )
 where
  label = ncName control <> " — " <> ncDescription control

-- | One failure message per control that did not pass.  An empty list means
-- every known-invalid fixture was rejected for the reason it names.
runNegativeControls :: [NegativeControl] -> IO [Text]
runNegativeControls controls =
  catMaybes
    <$> traverse (\control -> controlFailure control <$> runControl control) controls

-- | One tasty case per control, named after it.
controlTestCase :: NegativeControl -> TestTree
controlTestCase control =
  testCase (Text.unpack (ncName control)) $ do
    outcome <- runControl control
    case controlFailure control outcome of
      Nothing -> pure ()
      Just failure -> assertFailure (Text.unpack failure)

-- | Names that occur more than once (a duplicate would let one control shadow
-- another in the report).
duplicateControlNames :: [NegativeControl] -> [Text]
duplicateControlNames controls =
  [ name
  | name : _ : _ <- List.group (List.sort (fmap ncName controls))
  ]

categoriesWithoutControls :: [NegativeControl] -> [ControlCategory]
categoriesWithoutControls controls =
  [ category
  | category <- allControlCategories
  , category `notElem` fmap ncCategory controls
  ]

-- | Every category that is not deferred must have at least one control, and a
-- deferred category must not already have one (its owner must un-defer it, so
-- the guard starts requiring coverage the moment the controls land).
categoryCoverageFailures :: [ControlCategory] -> [NegativeControl] -> [Text]
categoryCoverageFailures deferred controls =
  [ "populated control category has no controls: " <> renderControlCategory category
  | category <- empty
  , category `notElem` deferred
  ]
    <> [ "category is listed as deferred but already has controls; remove it from the deferred list: "
           <> renderControlCategory category
       | category <- deferred
       , category `notElem` empty
       ]
 where
  empty = categoriesWithoutControls controls

-- | Run a tasty tree to completion without reporting and say whether every
-- test in it passed.  The harness self-test uses it to prove that a tree
-- containing an accepted or wrong-reason control really fails.
treeSucceeds :: TestTree -> IO Bool
treeSucceeds tree =
  launchTestTree silentOptions tree $ \statuses -> do
    results <- traverse (atomically . awaitResult) (IntMap.elems statuses)
    pure (\_elapsed -> pure (all resultSuccessful results))
 where
  awaitResult statusVar = do
    status <- readTVar statusVar
    case status of
      Done result -> pure result
      _ -> retry

silentOptions :: OptionSet
silentOptions = setOption (NumThreads 1) mempty
