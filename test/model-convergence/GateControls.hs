{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-x-model-evidence-raw #-}

-- | Phase 285 — controls for the evidence gate's own fail-closed guards.
--
-- "Controls" corrupts one field of a row that was already admitted. The guards
-- here stand in front of that step (loading and admitting a lane's journal,
-- looking up a row's independent criterion) and behind it (binding a
-- performance receipt to the journal row it came from). No real journal can trip
-- them, so a guard turned fail-open would leave every other control green. Each
-- is offered a defective input by hand, after proving that the same input made
-- well-formed is accepted, and must answer with its specific typed failure:
--
-- * loading a lane: no registered input, an unreadable journal, a registry that
--   does not project, a journal the pinned production reader rejects (a wrong
--   pin, a non-canonical pin, a copy altered by one byte), and an admitted
--   journal that does not join into the projection;
-- * the criterion lookup: every table-miss arm of
--   'ExternalBars.externalCriteriaFor', and a row with no canonical criterion
--   reaching 'assertModelConvergence';
-- * the receipt-to-journal-row binding, one identity dimension at a time, plus a
--   row with no receipt and a defect on only one of several receipts.
module GateControls
  ( gateTests
  )
where

import Control.Exception (bracket)
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.List (find, sort)
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text
import System.Directory (getTemporaryDirectory, removeFile)
import System.IO (hClose, openBinaryTempFile)
import Test.Tasty (TestTree, testGroup, withResource)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

import ControlSupport
import JitML.Plan.Plan qualified as Plan
import JitML.Product.ExternalBars qualified as ExternalBars
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Substrate (Substrate (..))
import JitML.Test.ModelConvergence (RowCheck (..), rowCheckFailures)
import JitML.Test.ModelEvidence
import JitML.Test.ModelEvidence.Raw
import JitML.Test.ProductAggregation (ProductLaneInput (..), productLaneInputs)
import JitML.Test.ProductLaneJournal qualified as Lane
import JitML.Training.Budget qualified as Budget

gateTests :: TestTree
gateTests =
  withResource loadBaseline (const (pure ())) $ \loaded ->
    testGroup
      "evidence gate fail-closed controls"
      [ loaderControls loaded
      , loaderDiagnosticControls
      , criterionControls loaded
      , receiptControls loaded
      ]

-- ---------------------------------------------------------------------------
-- Loading and admitting a lane's journal

-- | The committed, pinned input of the baseline lane.
registeredInput :: IO ProductLaneInput
registeredInput =
  maybe
    (assertFailure "no registered linux-cuda journal input")
    pure
    (find ((== LinuxCUDA) . productLaneInputSubstrate) productLaneInputs)

loadFrom :: [ProductLaneInput] -> IO (Either ModelEvidenceLoadError LoadedLane)
loadFrom inputs = loadLaneJournalIn inputs ProductMatrix.allProductRows LinuxCUDA

-- | The unaltered input is admitted: every defect below is therefore the only
-- reason its variant is refused.
assertAdmitted :: [ProductLaneInput] -> IO ()
assertAdmitted inputs = do
  result <- loadFrom inputs
  case result of
    Left err ->
      assertFailure
        ("the well-formed baseline was refused: " <> Text.unpack (renderModelEvidenceLoadError err))
    Right _ -> pure ()

-- | The typed reason a load was refused.
refusal :: [ProductLaneInput] -> IO ModelEvidenceLoadError
refusal inputs = do
  result <- loadFrom inputs
  case result of
    Left err -> pure err
    Right _ -> assertFailure "a defective journal input was admitted"

journalRowIds :: LoadedLane -> [Text]
journalRowIds =
  sort
    . fmap Lane.productLaneJournalRowRowId
    . Lane.admittedProductLaneJournalRows
    . loadedLaneJournal

-- | The journal with one hex digit of the first row's admitted manifest digest
-- changed to another hex digit: still canonical JSON of the same length, so only
-- the pin can tell it from the retained journal.
alterManifestDigest :: ByteString -> Maybe ByteString
alterManifestDigest bytes =
  case ByteString.breakSubstring key bytes of
    (before, fromKey)
      | Just (digit, rest) <- ByteString.uncons (ByteString.drop (ByteString.length key) fromKey) ->
          Just (before <> key <> ByteString.cons (swapped digit) rest)
    _ -> Nothing
 where
  key = "\"admitted_manifest_sha256\":\""
  -- ASCII 'f' <-> 'e'
  swapped digit = if digit == 0x66 then 0x65 else 0x66

-- | Run an action on a temporary file holding the given bytes.
withTempJournal :: ByteString -> (FilePath -> IO result) -> IO result
withTempJournal bytes action = do
  directory <- getTemporaryDirectory
  bracket
    (openBinaryTempFile directory "model-evidence-journal.json")
    (\(path, handle) -> hClose handle >> removeFile path)
    ( \(path, handle) -> do
        ByteString.hPut handle bytes
        hClose handle
        action path
    )

loaderControls :: IO (Either String Baseline) -> TestTree
loaderControls loaded =
  testGroup
    "loading a lane's pinned journal"
    [ testCase "the registered input loads through the seam exactly as loadLaneJournal does" $ do
        input <- registeredInput
        seam <- loadFrom [input] >>= either (assertFailure . show) pure
        production <- loadLaneJournal LinuxCUDA >>= either (assertFailure . show) pure
        journalRowIds seam @?= sort ProductMatrix.productRowIds
        journalRowIds production @?= journalRowIds seam
    , testCase "a lane with no registered input is LaneJournalNotRegistered, never an empty pass" $ do
        input <- registeredInput
        assertAdmitted [input]
        refusal [] >>= (@?= LaneJournalNotRegistered LinuxCUDA)
        refusal [other | other <- productLaneInputs, productLaneInputSubstrate other /= LinuxCUDA]
          >>= (@?= LaneJournalNotRegistered LinuxCUDA)
    , testCase "a journal path that cannot be read is LaneJournalUnreadable and names the file" $ do
        input <- registeredInput
        assertAdmitted [input]
        let missing = "DEVELOPMENT_PLAN/attestations/no-such-product-lane-journal.json"
        err <- refusal [input {productLaneInputPath = missing}]
        case err of
          LaneJournalUnreadable path detail -> do
            path @?= missing
            assertBool
              ("the diagnostic does not name the file: " <> Text.unpack detail)
              (Text.pack missing `Text.isInfixOf` detail)
          other -> assertFailure ("expected LaneJournalUnreadable, observed " <> show other)
    , testCase "a wrong pin over the retained bytes is a typed digest mismatch" $ do
        input <- registeredInput
        assertAdmitted [input]
        let wrong = Text.replicate 64 "0"
        refusal [input {productLaneInputSha256 = wrong}]
          >>= ( @?=
                  LaneJournalRejected
                    LinuxCUDA
                    (productLaneInputPath input)
                    wrong
                    (Lane.ProductLaneJournalDigestMismatch wrong (productLaneInputSha256 input) :| [])
              )
    , testCase "a pin that is not a canonical SHA-256 is a typed malformed rejection" $ do
        input <- registeredInput
        assertAdmitted [input]
        err <- refusal [input {productLaneInputSha256 = "abc"}]
        case err of
          LaneJournalRejected LinuxCUDA path "abc" (Lane.ProductLaneJournalMalformed _ :| []) ->
            path @?= productLaneInputPath input
          other -> assertFailure ("expected a malformed pin rejection, observed " <> show other)
    , testCase "a copy altered by one byte is a typed digest mismatch under the retained pin" $ do
        input <- registeredInput
        bytes <- ByteString.readFile (productLaneInputPath input)
        altered <-
          maybe
            (assertFailure "the retained journal has no admitted manifest digest to alter")
            pure
            (alterManifestDigest bytes)
        ByteString.length altered @?= ByteString.length bytes
        length (filter id (ByteString.zipWith (/=) bytes altered)) @?= 1
        -- The same bytes, unaltered, are admitted from the same temporary place,
        -- so the one altered byte is the only reason the copy below is refused.
        withTempJournal bytes $ \copy ->
          assertAdmitted [input {productLaneInputPath = copy}]
        withTempJournal altered $ \tampered -> do
          err <- refusal [input {productLaneInputPath = tampered}]
          case err of
            LaneJournalRejected
              LinuxCUDA
              path
              pinned
              (Lane.ProductLaneJournalDigestMismatch expected observed :| []) -> do
                path @?= tampered
                pinned @?= productLaneInputSha256 input
                expected @?= productLaneInputSha256 input
                assertBool "the altered copy still carries the pinned digest" (observed /= expected)
            other -> assertFailure ("expected a digest mismatch, observed " <> show other)
    , testCase "a registry that does not project is LaneProjectionRejected and names the row" $ do
        input <- registeredInput
        assertAdmitted [input]
        row <- registryRow "PPO/cartpole"
        err <-
          do
            result <-
              loadLaneJournalIn [input] (ProductMatrix.allProductRows <> [row]) LinuxCUDA
            case result of
              Left failure -> pure failure
              Right _ -> assertFailure "a registry with a duplicated row was admitted"
        case err of
          LaneProjectionRejected LinuxCUDA errors ->
            assertBool
              ("the duplicated row was not named: " <> show errors)
              (ProductMatrix.DuplicateProductRowId "PPO/cartpole" `elem` NonEmpty.toList errors)
          other -> assertFailure ("expected LaneProjectionRejected, observed " <> show other)
    , testCase "an admitted journal that does not join into its projection is LaneEvidenceRejected" $
        withBaseline loaded $ \baseline -> do
          assertBool
            "the well-formed lane did not join"
            (either (const False) (const True) (admitLaneEvidence (baselineLane baseline)))
          case ProductMatrix.projectProductRows LinuxCPU ProductMatrix.allProductRows of
            Plan.Failure errors -> assertFailure ("linux-cpu projection failed: " <> show errors)
            Plan.Success cpuBatch -> do
              let crossed = (baselineLane baseline) {loadedLaneBatch = cpuBatch}
              -- The typed join the admission wraps, run directly on the same inputs.
              joinErrors <-
                case joinModelEvidence cpuBatch (rawModelEvidenceFromJournal (loadedLaneJournal crossed)) of
                  Left errors -> pure errors
                  Right _ -> assertFailure "the reference join accepted cross-lane evidence"
              case admitLaneEvidence crossed of
                Left (LaneEvidenceRejected lane errors) -> do
                  lane @?= LinuxCPU
                  errors @?= joinErrors
                Left other ->
                  assertFailure ("expected LaneEvidenceRejected, observed " <> show other)
                Right _ -> assertFailure "cross-lane evidence was admitted"
    ]

-- | The rendered diagnostics are what the stanza prints when a lane is stale,
-- so each must name what failed and where.
loaderDiagnosticControls :: TestTree
loaderDiagnosticControls =
  testGroup
    "load diagnostics"
    [ testCase "an unregistered lane is named in both forms" $ do
        let err = LaneJournalNotRegistered LinuxCUDA
        renderModelEvidenceLoadError err @?= "no lane journal is registered for linux-cuda"
        renderModelEvidenceLoadHeadline err @?= renderModelEvidenceLoadError err
    , testCase "a rejected journal names the lane, the file, both digests, and the count" $ do
        input <- registeredInput
        let wrong = Text.replicate 64 "0"
        err <- refusal [input {productLaneInputSha256 = wrong}]
        let full = renderModelEvidenceLoadError err
            headline = renderModelEvidenceLoadHeadline err
        mapM_
          ( \fact ->
              assertBool
                ("the full diagnostic omits " <> Text.unpack fact <> ": " <> Text.unpack full)
                (fact `Text.isInfixOf` full)
          )
          [ "the pinned linux-cuda lane journal is inadmissible"
          , Text.pack (productLaneInputPath input)
          , wrong
          , productLaneInputSha256 input
          ]
        mapM_
          ( \fact ->
              assertBool
                ("the headline omits " <> Text.unpack fact <> ": " <> Text.unpack headline)
                (fact `Text.isInfixOf` headline)
          )
          [ "no admitted linux-cuda evidence: the pinned lane journal is inadmissible (1 error(s); first: "
          , productLaneInputSha256 input
          ]
    , testCase "an unreadable journal names the file, and a registry that does not project names the row" $ do
        input <- registeredInput
        let missing = "DEVELOPMENT_PLAN/attestations/no-such-product-lane-journal.json"
        unreadable <- refusal [input {productLaneInputPath = missing}]
        assertBool
          "the unreadable diagnostic does not name the file"
          (Text.pack missing `Text.isInfixOf` renderModelEvidenceLoadError unreadable)
        row <- registryRow "PPO/cartpole"
        result <- loadLaneJournalIn [input] (ProductMatrix.allProductRows <> [row]) LinuxCUDA
        case result of
          Left err@(LaneProjectionRejected LinuxCUDA _) ->
            mapM_
              ( \fact ->
                  assertBool
                    ("the projection diagnostic omits " <> Text.unpack fact)
                    (fact `Text.isInfixOf` renderModelEvidenceLoadError err)
              )
              ["does not project for linux-cuda", "duplicate row id: PPO/cartpole"]
          Left other -> assertFailure ("expected LaneProjectionRejected, observed " <> show other)
          Right _ -> assertFailure "a registry with a duplicated row was admitted"
    ]

-- ---------------------------------------------------------------------------
-- The independent criterion lookup

criterionControls :: IO (Either String Baseline) -> TestTree
criterionControls loaded =
  testGroup
    "independent criterion lookup"
    [ testCase "a supervised row missing from the cohort table is a typed Left naming the row" $ do
        let classification = ProductMatrix.SupervisedClassification "any-dataset" "any-model"
        ExternalBars.externalCriteriaFor "mnist-shallow-mlp" classification
          @?= Right (criterion "test_accuracy" Budget.RawCriterionAtLeast (0.97 - 0.07) :| [])
        ExternalBars.externalCriteriaFor "not-a-supervised-row" classification
          @?= Left "no supervised cohort threshold for row not-a-supervised-row"
    , testCase "an RL algorithm and environment pair missing from the cohort table is a typed Left" $ do
        ExternalBars.externalCriteriaFor "row" (ProductMatrix.RlAlgorithmEnvironment "PPO" "cartpole")
          @?= Right (ppoCartpoleCriterion :| [])
        ExternalBars.externalCriteriaFor "row" (ProductMatrix.RlAlgorithmEnvironment "PPO" "no-env")
          @?= Left "no RL cohort threshold for PPO/no-env"
        ExternalBars.externalCriteriaFor
          "row"
          (ProductMatrix.RlAlgorithmEnvironment "NoAlgorithm" "cartpole")
          @?= Left "no RL cohort threshold for NoAlgorithm/cartpole"
    , testCase "a goal-conditioned environment missing from the HER metric is a typed Left" $ do
        herRow <- registryRow "HER/goal-reaching"
        environment <-
          case ProductMatrix.rowClass herRow of
            ProductMatrix.RlGoalConditioned name -> pure name
            other -> assertFailure ("HER/goal-reaching has class " <> show other)
        fmap
          NonEmpty.toList
          (ExternalBars.externalCriteriaFor "row" (ProductMatrix.RlGoalConditioned environment))
          @?= Right
            [ criterion "goal_success_rate" Budget.RawCriterionAtLeast (0.90 - 0.05)
            , criterion "achieved_goal_distance" Budget.RawCriterionAtMost 0.05
            ]
        ExternalBars.externalCriteriaFor "row" (ProductMatrix.RlGoalConditioned "no-env")
          @?= Left "no HER goal metric for environment no-env"
    , testCase "an AlphaZero game missing from the arena table is a typed Left" $ do
        ExternalBars.externalCriteriaFor "row" (ProductMatrix.AlphaZeroGame "connect4")
          @?= Right (alphaZeroCriterion :| [])
        ExternalBars.externalCriteriaFor "row" (ProductMatrix.AlphaZeroGame "chess")
          @?= Left "no AlphaZero arena threshold for game chess"
    , testCase "evidence of a row with no canonical criterion is NoIndependentCriterion, not a pass" $
        withBaseline loaded $ \baseline -> do
          -- The same forging technique on the unedited row grades clean, so the
          -- missing table entry is the only thing that differs below.
          unedited <- editedEvidence baseline "mnist-shallow-mlp" id
          convergenceOf unedited @?= []
          renamed <-
            editedEvidence
              baseline
              "mnist-shallow-mlp"
              (\row -> row {ProductMatrix.rowId = "mnist-shallow-mlp-x"})
          convergenceOf renamed
            @?= [NoIndependentCriterion "no supervised cohort threshold for row mnist-shallow-mlp-x"]
          case renamed of
            SomeModelRowEvidence _ evidence ->
              modelEvidenceRowId evidence @?= "mnist-shallow-mlp-x"
    ]
 where
  convergenceOf (SomeModelRowEvidence _ evidence) = assertModelConvergence evidence

-- ---------------------------------------------------------------------------
-- Receipt-to-journal-row binding

journalRowOf :: Baseline -> Text -> IO Lane.ProductLaneJournalRow
journalRowOf baseline rowId =
  maybe
    (assertFailure ("the admitted journal has no row " <> Text.unpack rowId))
    pure
    ( find
        ((== rowId) . Lane.productLaneJournalRowRowId)
        (Lane.admittedProductLaneJournalRows (loadedLaneJournal (baselineLane baseline)))
    )

-- | The performance receipts the joined baseline evidence of one row produces.
receiptsOf :: Baseline -> Text -> IO [PerformanceReceipt]
receiptsOf baseline rowId = do
  set <- joinedSet baseline (baselineRaw baseline)
  case lookupModelEvidence rowId set of
    Just (SomeModelRowEvidence _ evidence) -> pure (modelPerformanceReceipts evidence)
    Nothing -> assertFailure ("joined evidence has no row " <> Text.unpack rowId)

-- | Each case changes exactly one identity of a receipt of PPO/cartpole to the
-- value of another real journal row and states the one typed failure that must
-- follow. Expected values come from the two journal rows, never from the
-- receipt under test.
dimensionCases
  :: [(String, Baseline -> IO (PerformanceReceipt -> PerformanceReceipt, ReceiptBindingFailure))]
dimensionCases =
  [
    ( "row id"
    , \_ ->
        pure
          ( \receipt -> receipt {receiptRowId = "A2C/cartpole"}
          , ReceiptNotBound BindingRowId "PPO/cartpole" "A2C/cartpole"
          )
    )
  ,
    ( "PlanId"
    , \baseline -> do
        expected <- Lane.productLaneJournalRowPlanId <$> journalRowOf baseline "PPO/cartpole"
        other <- Lane.productLaneJournalRowPlanId <$> journalRowOf baseline "A2C/cartpole"
        pure
          ( \receipt -> receipt {receiptPlanId = other}
          , ReceiptNotBound BindingJournalPlan (Plan.planIdText expected) (Plan.planIdText other)
          )
    )
  ,
    ( "experiment hash"
    , \baseline -> do
        expected <- Lane.productLaneJournalRowExperimentHash <$> journalRowOf baseline "PPO/cartpole"
        pure
          ( \receipt -> receipt {receiptExperimentHash = "product-row-other"}
          , ReceiptNotBound BindingJournalExperiment expected "product-row-other"
          )
    )
  ,
    ( "admitted manifest"
    , \baseline -> do
        expected <- Lane.productLaneJournalRowManifestSha <$> journalRowOf baseline "PPO/cartpole"
        other <- Lane.productLaneJournalRowManifestSha <$> journalRowOf baseline "A2C/cartpole"
        pure
          ( \receipt -> receipt {receiptManifestSha = other}
          , ReceiptNotBound BindingAdmittedManifest expected other
          )
    )
  ]

receiptControls :: IO (Either String Baseline) -> TestTree
receiptControls loaded =
  testGroup
    "performance receipt binding to the admitted journal row"
    ( testCase "every row's own receipts are bound to its own admitted journal row" ownReceipts
        : [ testCase ("a receipt with another " <> label <> " is one typed unbound receipt and nothing else") $
              withBaseline loaded $ \baseline -> do
                row <- journalRowOf baseline "PPO/cartpole"
                receipts <- receiptsOf baseline "PPO/cartpole"
                assertBool "PPO/cartpole produced no receipt" (not (null receipts))
                assertReceiptBinding row receipts @?= []
                (mutation, expected) <- expectation baseline
                assertReceiptBinding row (fmap mutation receipts) @?= [expected]
          | (label, expectation) <- dimensionCases
          ]
          <> [ testCase "another row's receipts are unbound in all four identities, in order" otherRowReceipts
             , testCase "a row with no receipt at all is NoPerformanceReceipt" noReceipt
             , testCase
                 "a defect on one of several receipts is found, and a shared defect is one failure"
                 severalReceipts
             , testCase "a receipt for another PlanId is caught through the per-row performance check" planWiring
             , testCase
                 "evidence for a row the admitted journal does not hold has no journal row to bind to"
                 missingJournalRow
             ]
    )
 where
  ownReceipts =
    withBaseline loaded $ \baseline -> do
      set <- joinedSet baseline (baselineRaw baseline)
      mapM_
        ( \(SomeModelRowEvidence _ evidence) -> do
            let rowId = modelEvidenceRowId evidence
                receipts = modelPerformanceReceipts evidence
            row <- journalRowOf baseline rowId
            assertBool ("no performance receipt for " <> Text.unpack rowId) (not (null receipts))
            assertReceiptBinding row receipts @?= []
        )
        (modelEvidenceSetRows set)
  otherRowReceipts =
    withBaseline loaded $ \baseline -> do
      row <- journalRowOf baseline "PPO/cartpole"
      other <- journalRowOf baseline "A2C/cartpole"
      foreign' <- receiptsOf baseline "A2C/cartpole"
      assertReceiptBinding other foreign' @?= []
      assertReceiptBinding row foreign'
        @?= [ ReceiptNotBound BindingRowId "PPO/cartpole" "A2C/cartpole"
            , ReceiptNotBound
                BindingJournalPlan
                (Plan.planIdText (Lane.productLaneJournalRowPlanId row))
                (Plan.planIdText (Lane.productLaneJournalRowPlanId other))
            , ReceiptNotBound
                BindingJournalExperiment
                (Lane.productLaneJournalRowExperimentHash row)
                (Lane.productLaneJournalRowExperimentHash other)
            , ReceiptNotBound
                BindingAdmittedManifest
                (Lane.productLaneJournalRowManifestSha row)
                (Lane.productLaneJournalRowManifestSha other)
            ]
  noReceipt =
    withBaseline loaded $ \baseline -> do
      row <- journalRowOf baseline "PPO/cartpole"
      receipts <- receiptsOf baseline "PPO/cartpole"
      assertReceiptBinding row receipts @?= []
      assertReceiptBinding row [] @?= [NoPerformanceReceipt "PPO/cartpole"]
  severalReceipts =
    withBaseline loaded $ \baseline -> do
      row <- journalRowOf baseline "hyperparameter-tuning"
      other <- journalRowOf baseline "PPO/cartpole"
      receipts <- receiptsOf baseline "hyperparameter-tuning"
      -- Tuning is graded on an at-least and an at-most bound: two receipts.
      length receipts @?= 2
      assertReceiptBinding row receipts @?= []
      let foreignManifest = Lane.productLaneJournalRowManifestSha other
          expected =
            [ ReceiptNotBound
                BindingAdmittedManifest
                (Lane.productLaneJournalRowManifestSha row)
                foreignManifest
            ]
          foreignised receipt = receipt {receiptManifestSha = foreignManifest}
      let (leading, trailing) = splitAt 1 receipts
      assertReceiptBinding row (fmap foreignised leading <> trailing) @?= expected
      assertReceiptBinding row (leading <> fmap foreignised trailing) @?= expected
      assertReceiptBinding row (fmap foreignised receipts) @?= expected
  missingJournalRow =
    withBaseline loaded $ \baseline -> do
      let rename row
            | ProductMatrix.rowId row == "PPO/cartpole" =
                row {ProductMatrix.rowId = "PPO/cartpole-renamed"}
            | otherwise = row
          laneWith editedBatch =
            LaneEvidence ((baselineLane baseline) {loadedLaneBatch = editedBatch})
          check = rowCheckFailures PerformanceCheck
      unedited <- projectedBatch id
      uneditedSet <- forgedSet unedited "PPO/cartpole" "PPO/cartpole" (baselineRaw baseline)
      -- With the row unrenamed the same construction grades clean, so the renamed
      -- row's absence from the journal is the only difference below.
      check (laneWith unedited uneditedSet) "PPO/cartpole" @?= []
      renamed <- projectedBatch rename
      renamedSet <- forgedSet renamed "PPO/cartpole" "PPO/cartpole-renamed" (baselineRaw baseline)
      check (laneWith renamed renamedSet) "PPO/cartpole-renamed"
        @?= ["no admitted journal row for PPO/cartpole-renamed"]
  -- The registry with one edit applied, projected for the baseline lane.
  projectedBatch edit =
    case ProductMatrix.projectProductRows LinuxCUDA (fmap edit ProductMatrix.allProductRows) of
      Plan.Failure errors -> assertFailure ("the edited registry did not project: " <> show errors)
      Plan.Success batch -> pure batch
  planWiring =
    withBaseline loaded $ \baseline -> do
      realRow <- journalRowOf baseline "PPO/cartpole"
      let editConfig row
            | ProductMatrix.rowId row == "PPO/cartpole" =
                row {ProductMatrix.experimentConfig = ProductMatrix.experimentConfig row <> ".alternate"}
            | otherwise = row
      editedBatch <- projectedBatch editConfig
      editedPlan <-
        case find
          ((== "PPO/cartpole") . someProjectionRowId)
          (ProductMatrix.productProjectionBatchProjections editedBatch) of
          Just projection -> pure (someProjectionPlanId projection)
          Nothing -> assertFailure "the edited registry has no PPO/cartpole projection"
      let realPlan = Lane.productLaneJournalRowPlanId realRow
      assertBool "editing the experiment configuration did not change the PlanId" (editedPlan /= realPlan)
      -- The real evidence, wired to the real journal, has nothing to report.
      real <- joinedSet baseline (baselineRaw baseline)
      rowCheckFailures PerformanceCheck (LaneEvidence (baselineLane baseline) real) "PPO/cartpole" @?= []
      -- Evidence minted for the edited plan but graded against the real journal
      -- row carries receipts for a PlanId that journal row never recorded.
      forged <-
        forgedSet editedBatch "PPO/cartpole" "PPO/cartpole" (baselineRaw baseline)
      rowCheckFailures PerformanceCheck (LaneEvidence (baselineLane baseline) forged) "PPO/cartpole"
        @?= [ renderReceiptBindingFailure
                ( ReceiptNotBound
                    BindingJournalPlan
                    (Plan.planIdText realPlan)
                    (Plan.planIdText editedPlan)
                )
            ]
  -- The real raw view of @sourceRowId@ re-anchored to the edited batch's
  -- projection of @editedRowId@, joined against the edited batch.
  forgedSet editedBatch sourceRowId editedRowId raws =
    let reanchored raw =
          case find
            ((== editedRowId) . someProjectionRowId)
            (ProductMatrix.productProjectionBatchProjections editedBatch) of
            Just (ProductMatrix.SomeProductProjection _ projection)
              | rmeRowId raw == sourceRowId -> reanchorTo projection raw
            _ -> raw
     in case joinModelEvidence editedBatch (fmap reanchored raws) of
          Left errors ->
            assertFailure
              ( "the forged evidence was refused: "
                  <> Text.unpack (Text.intercalate "; " (fmap renderModelEvidenceError (NonEmpty.toList errors)))
              )
          Right set -> pure set
