{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Structural execution identities, not numerical training evidence. The
-- historical fixture is an unchanged actual165-projection capture. Separate
-- actual46a and current-RL isolation captures prevent unrelated RL evolution
-- from being attributed to SL policy. Typed California10/PPO150 allocation
-- counterfactuals retain those captured identities; no fixture values are invented.
module SupervisedCohortPlan (supervisedCohortPlanTests) where

import Data.Either (isLeft)
import Data.Foldable (for_)
import Data.List (find, nub)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Data.Text.IO qualified as TextIO
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))
import Text.Read (readMaybe)

import JitML.Plan.Plan qualified as Plan
import JitML.Plan.Workload qualified as Workload
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.SupervisedCohortPlan qualified as Cohort
import JitML.Product.SupervisedQualificationPolicy qualified as Policy
import JitML.Product.ValidationRecord (sha256Hex)
import JitML.SL.Architecture qualified as Architecture
import JitML.SL.Canonicals qualified as SL
import JitML.SL.Regression qualified as Regression
import JitML.Substrate (Substrate, allSubstrates, renderSubstrate)
import JitML.Test.Report qualified as Report
import JitML.Training.Budget qualified as Budget

supervisedCohortPlanTests :: TestTree
supervisedCohortPlanTests =
  testGroup
    "supervised five-seed cohort plans"
    [ testCase
        "historical field removal and the explicit ten-epoch California counterfactual reconstruct the captured 165 identities"
        identityScope
    , testCase
        "regression order stays report-bound and the historical allocation counterfactual reconstructs captured identities"
        regressionOrderIdentityScope
    , testCase
        "regression order field removal rejects missing duplicate and incomplete descriptors"
        regressionOrderParserControls
    , testCase
        "California explicitly allocates the default hundred epochs with complete five-seed work and a distinct ten-epoch counterfactual"
        californiaDefaultHundredAllocation
    , testCase
        "every canonical row and lane has five singleton children with unchanged per-run budgets"
        childScope
    , testCase
        "index zero is exactly the canonical serving plan and other indices have explicit distinct namespaces"
        childNamespaces
    , testCase
        "parent identities are deterministic and injective across every row and lane"
        parentIdentities
    , testCase
        "a modified row with an unchanged semantic PlanId still cannot mint a canonical cohort"
        alteredMetadata
    , testCase
        "modified configuration and budget projections cannot mint a canonical cohort"
        alteredExecution
    , testCase "a child transport with a substituted lane fails its declared identity" laneSubstitution
    , testCase
        "every seed plus its architecture offset fits at the combined cohort headroom boundary"
        combinedHeadroom
    , testCase
        "the length-delimited policy removal rejects missing, duplicate and substituted fields"
        subjectParserControls
    ]

allCohorts :: IO [Cohort.SupervisedCohortPlan]
allCohorts = concat <$> traverse forLane allSubstrates
 where
  forLane lane = concat <$> traverse (forRow lane) Matrix.allProductRows
  forRow :: Substrate -> Matrix.ProductRow state -> IO [Cohort.SupervisedCohortPlan]
  forRow lane row = do
    projected <- expectSuccess (Matrix.projectProductRow lane row)
    case projected of
      Matrix.SomeProductProjection Plan.SupervisedTrainingWitness projection -> do
        cohort <- expectRight (Cohort.mkSupervisedCohortPlan projection)
        pure [cohort]
      _ -> pure []

identityScope :: Assertion
identityScope = do
  historical <- readBaseline
  slOnly <- readSlOnlyBaseline
  baseline <- readCurrentRlIsolationBaseline
  for_ [historical, slOnly, baseline] $ \entries -> do
    length entries @?= 165
    length (nub (fmap baselineKey entries)) @?= 165
    fmap baselineKey entries @?= fmap baselineKey historical
  -- The original historical fixture and isolated SL-only proof remain exact.
  -- Neither fixture below may be populated until an actual bound API capture.
  assertCapturedSlScope historical slOnly
  rlCounts <- traverse (checkCombinedRlLane slOnly) allSubstrates
  rlCounts @?= replicate 3 (17, 38)
  counts <- traverse (checkLane historical baseline) allSubstrates
  counts @?= replicate 3 (11, 44)
 where
  checkLane historical baseline lane = do
    changed <- traverse (checkRow historical baseline lane) Matrix.allProductRows
    pure (length (filter id changed), length (filter not changed))
  checkRow :: [Baseline] -> [Baseline] -> Substrate -> Matrix.ProductRow state -> IO Bool
  checkRow historical baseline lane row = do
    old <-
      expectExactlyOne
        "captured row/lane identity"
        [entry | entry@(Baseline l r _ _) <- baseline, l == renderSubstrate lane, r == Matrix.rowId row]
    let Baseline _ _ oldIdentity oldSubject = old
    projected <- expectSuccess (Matrix.projectProductRow lane row)
    case projected of
      Matrix.SomeProductProjection Plan.SupervisedTrainingWitness projection -> do
        Baseline _ _ historicalIdentity historicalSubject <- capturedFor historical lane row
        (oldIdentity, oldSubject) @?= (historicalIdentity, historicalSubject)
        let plan = Matrix.productProjectionRunPlan projection
        fields <- expectRight (parseSubject (Plan.runPlanSubjectId plan))
        base <-
          expectExactlyOne
            "canonical execution seed"
            (NonEmpty.toList (Plan.seedCohortValues (Plan.runPlanSeeds plan)))
        assertBool
          "policy subject does not bind the actual canonical base seed"
          ( [ "supervised-qualification"
            , Policy.supervisedQualificationPolicyContract
            , "cohort-base-seed"
            , Text.pack (show base)
            ]
              `isContiguous` fields
          )
        orderStripped <- stripRegressionOrderFields projection fields
        stripped <- expectRight (removePolicy orderStripped)
        renderSubject stripped @?= oldSubject
        legacy <-
          expectSuccess
            ( Workload.resolveSupervisedPlan
                (Workload.RawSupervisedPlan (requestWithHistoricalBudget projection plan oldSubject))
            )
        Plan.planIdText (Workload.supervisedPlanId legacy) @?= oldIdentity
        assertBool
          "supervised policy did not version execution identity"
          (Plan.planIdText (Matrix.productProjectionPlanId projection) /= oldIdentity)
        pure True
      Matrix.SomeProductProjection _ projection -> do
        preRegressionRevisionIdentity projection >>= (@?= (oldIdentity, oldSubject))
        pure False

-- The actual 46a capture contains the qualification policy, the pre-order
-- regression identities and the original ten-epoch California allocation.
-- This historical counterfactual removes the new order field and explicitly
-- restores only that original budget; no fixture or successor identity is made up.
regressionOrderIdentityScope :: Assertion
regressionOrderIdentityScope = do
  captured <- readSlOnlyBaseline
  contracts <- readCapturedSlReportContracts
  counts <- traverse (checkLane captured contracts) allSubstrates
  counts @?= replicate 3 (1, 10)
 where
  checkLane captured contracts lane = do
    changed <- traverse (checkRow captured contracts lane) supervisedRows
    pure (length (filter id changed), length (filter not changed))
  checkRow captured contracts lane row = do
    Baseline _ _ oldId oldSubject <- capturedFor captured lane row
    oldContract <-
      expectExactlyOne
        "captured supervised report contract"
        [ digest
        | (capturedLane, capturedRow, digest) <- contracts
        , capturedLane == renderSubstrate lane
        , capturedRow == Matrix.rowId row
        ]
    projection <- supervisedProjection lane row
    let currentId = Plan.planIdText (Matrix.productProjectionPlanId projection)
        subject = Plan.runPlanSubjectId (Matrix.productProjectionRunPlan projection)
        currentContract = Report.productScenarioProjectionContractDigest projection
    fields <- expectRight (parseSubject subject)
    case Matrix.rowClass row of
      Matrix.SupervisedRegression {} -> do
        assertBool
          "semantic subject does not bind the complete executed order recipe"
          (["regression-training-order", Regression.regressionTrainingOrderContract] `isContiguous` fields)
        length (filter (== "regression-training-order") fields) @?= 1
        preRegressionRevisionIdentity projection >>= (@?= (oldId, oldSubject))
        assertBool "regression order retained the old PlanId" (currentId /= oldId)
        currentContract
          @?= regressionOrderReportDigest oldContract Regression.regressionTrainingOrderContract
        assertBool
          "a bare recipe label can replace the complete report descriptor"
          (currentContract /= regressionOrderReportDigest oldContract approvedRegressionOrderId)
        cohort <- expectRight (Cohort.mkSupervisedCohortPlan projection)
        for_ (Cohort.supervisedCohortPlanChildren cohort) $ \child -> do
          let childPlan = Workload.supervisedPlanRunPlan (Cohort.supervisedSeedPlanWorkload child)
          childFields <- expectRight (parseSubject (Plan.runPlanSubjectId childPlan))
          assertBool
            "a prescribed child lost the complete original order recipe"
            (["regression-training-order", Regression.regressionTrainingOrderContract] `isContiguous` childFields)
        pure True
      Matrix.SupervisedClassification {} -> do
        (currentId, subject) @?= (oldId, oldSubject)
        currentContract @?= oldContract
        assertBool
          "classification acquired a regression ordering field"
          ("regression-training-order" `notElem` fields)
        pure False
      _ -> assertFailure "supervised cohort has an unrelated row class"

approvedRegressionOrderId :: Text
approvedRegressionOrderId =
  "generic-regression-training-order-v1:splitmix64-domain-reg-ord1;epoch1-based;original-training-list;sort-key-original-index;whole-example;fixed-heldout"

regressionOrderReportDigest :: Text -> Text -> Text
regressionOrderReportDigest capturedContract orderContract =
  sha256Hex
    ( TextEncoding.encodeUtf8
        ( "jitml-product-scenario-report-contract-regression-training-order-v1\NUL"
            <> capturedContract
            <> "\NUL"
            <> orderContract
        )
    )

regressionOrderParserControls :: Assertion
regressionOrderParserControls = do
  let contract = Regression.regressionTrainingOrderContract
      fields = ["row", "regression-training-order", contract, "subject", "λ:|"]
  assertBool
    "approved recipe version is missing"
    (approvedRegressionOrderId `Text.isPrefixOf` contract)
  for_
    [ "shuffle-root=deriveSplitMixSeed(SplitMixSeed(fromIntegral(execution-seed)),0x7265672d6f726431)"
    , "epoch-seed=deriveSplitMixSeed(shuffle-root,fromIntegral(one-based-epoch))"
    , "keys=splitMixWords(length(original-standardized-training-partition),epoch-seed)"
    , "ordering=ascending(key,zero-based-original-index)"
    , "epoch-input=original-standardized-training-partition"
    , "membership=every-original-training-example-once-per-epoch"
    , "record=whole-regression-example"
    , "heldout=excluded-fixed-membership-and-order"
    ]
    $ \clause ->
      assertBool "complete order descriptor lost an approved clause" (clause `Text.isInfixOf` contract)
  removeRegressionOrder fields @?= Right ["row", "subject", "λ:|"]
  assertRejected (removeRegressionOrder ["row", "subject"])
  assertRejected (removeRegressionOrder (fields <> fields))
  assertRejected (removeRegressionOrder ["regression-training-order", approvedRegressionOrderId])

stripRegressionOrderFields :: Matrix.ProductProjection kind -> [Text] -> IO [Text]
stripRegressionOrderFields projection fields = case Matrix.productProjectionRowClass projection of
  Matrix.SupervisedRegression {} -> expectRight (removeRegressionOrder fields)
  _ -> pure fields

preRegressionRevisionIdentity :: Matrix.ProductProjection kind -> IO (Text, Text)
preRegressionRevisionIdentity projection =
  case Matrix.productProjectionRowClass projection of
    Matrix.SupervisedRegression {} -> case Matrix.productProjectionResolvedPlan projection of
      Matrix.ResolvedSupervisedProductPlan workload -> do
        let plan = Workload.supervisedPlanRunPlan workload
        fields <- expectRight (parseSubject (Plan.runPlanSubjectId plan))
        stripped <- expectRight (removeRegressionOrder fields)
        let subject = renderSubject stripped
        prior <-
          expectSuccess
            ( Workload.resolveSupervisedPlan
                (Workload.RawSupervisedPlan (requestWithHistoricalBudget projection plan subject))
            )
        supervisedBudgetValues (Workload.supervisedPlanRunPlan prior)
          @?= (10, 7000, 1000, 128, 550)
        pure (Plan.planIdText (Workload.supervisedPlanId prior), subject)
      _ -> assertFailure "regression order reached an unrelated resolved run kind"
    Matrix.RlAlgorithmEnvironment "PPO" "mountain-car" ->
      case Matrix.productProjectionResolvedPlan projection of
        Matrix.ResolvedRlProductPlan plan -> do
          let (transitions, ticks, environments, horizon, episodes) = Plan.runPlanRlBudget plan
              subject = Plan.runPlanSubjectId plan
          ( quantityInteger transitions
            , quantityInteger ticks
            , quantityInteger environments
            , quantityInteger horizon
            , quantityInteger episodes
            )
            @?= (300 * 512 * 16, 512, 16, 200, 20)
          -- The authentic RL isolation captures predate only this row's
          -- approved allocation revision. Keep the complete semantic subject,
          -- seed and lane while reconstructing its original150-rollout budget.
          let budget =
                Plan.RawRlBudget
                  { Plan.rawRlEnvironmentTransitions = 150 * 512 * 16
                  , Plan.rawRlRolloutTicksPerEnv = quantityInteger ticks
                  , Plan.rawRlVectorEnvironments = quantityInteger environments
                  , Plan.rawRlEpisodeSteps = quantityInteger horizon
                  , Plan.rawRlEvaluationEpisodes = quantityInteger episodes
                  }
          prior <-
            expectSuccess
              (Plan.resolveRun (requestWithBudget Plan.ReinforcementLearningWitness plan budget subject))
          Plan.runPlanSubjectId prior @?= subject
          assertBool
            "PPO allocation counterfactual retained the current execution identity"
            (Plan.runPlanId prior /= Plan.runPlanId plan)
          pure (Plan.planIdText (Plan.runPlanId prior), Plan.runPlanSubjectId prior)
        _ -> assertFailure "PPO allocation counterfactual reached an unrelated resolved run kind"
    _ ->
      pure
        ( Plan.planIdText (Matrix.productProjectionPlanId projection)
        , Plan.runPlanSubjectId (Matrix.productProjectionRunPlan projection)
        )

removeRegressionOrder :: [Text] -> Either Text [Text]
removeRegressionOrder fields = case candidates of
  [index] -> case drop index fields of
    "regression-training-order" : actual : _
      | actual == Regression.regressionTrainingOrderContract ->
          Right (take index fields <> drop (index + 2) fields)
    _ -> Left "substituted regression order descriptor"
  _ -> Left "regression order must occur exactly once"
 where
  candidates = [index | (index, value) <- zip [0 ..] fields, value == "regression-training-order"]

readCapturedSlReportContracts :: IO [(Text, Text, Text)]
readCapturedSlReportContracts = do
  contents <- TextIO.readFile "test/fixtures/compact-supervised-46a-identities.txt"
  case filter (not . Text.isPrefixOf "#") (Text.lines contents) of
    _header : rows -> traverse parseRow rows
    [] -> assertFailure "captured supervised report contracts are empty"
 where
  parseRow line = case Text.splitOn "\t" line of
    [lane, row, _, _, contract, _, _] -> pure (lane, row, contract)
    _ -> assertFailure "captured supervised report contract has an unexpected column count"

baselineKey :: Baseline -> (Text, Text)
baselineKey (Baseline lane row _ _) = (lane, row)

capturedFor :: [Baseline] -> Substrate -> Matrix.ProductRow state -> IO Baseline
capturedFor baseline lane row =
  expectExactlyOne
    "captured row/lane identity"
    [entry | entry@(Baseline l r _ _) <- baseline, l == renderSubstrate lane, r == Matrix.rowId row]

-- Preserve the original actual pre-SL capture and its exact isolated33/132 scope.
-- This comparison is explicitly between genuine frozen captures; current RL
-- changes are checked independently rather than attributed to the SL policy.
assertCapturedSlScope :: [Baseline] -> [Baseline] -> Assertion
assertCapturedSlScope historical slOnly = do
  counts <- traverse checkLane allSubstrates
  counts @?= replicate 3 (11, 44)
 where
  checkLane lane = do
    changed <- traverse (checkRow lane) Matrix.allProductRows
    pure (length (filter id changed), length (filter not changed))
  checkRow lane row = do
    Baseline _ _ oldId oldSubject <- capturedFor historical lane row
    Baseline _ _ slId slSubject <- capturedFor slOnly lane row
    if Matrix.family row == Matrix.Supervised
      then do
        fields <- expectRight (parseSubject slSubject)
        stripped <- expectRight (removePolicy fields)
        renderSubject stripped @?= oldSubject
        assertBool "isolated SL capture did not version identity" (slId /= oldId)
        pure True
      else do
        (slId, slSubject) @?= (oldId, oldSubject)
        pure False

-- Independent closed review list, not generated from the Matrix's routing arm.
-- Preserve the original14 cycle90 rows and add ONLY the three reviewed DQN rows.
plannedRlRecipes :: [(Text, Text)]
plannedRlRecipes =
  [ ("QR-DQN/cartpole", "qrdqn-selected-device-final-evaluation-v1")
  , ("QR-DQN/mountain-car", "qrdqn-selected-device-final-evaluation-v1")
  , ("QR-DQN/key-door-grid", "qrdqn-selected-device-final-evaluation-v1")
  , ("DDPG/lunar-lander", "continuous-selected-device-final-evaluation-v1")
  , ("TD3/lunar-lander", "continuous-selected-device-final-evaluation-v1")
  , ("SAC/lunar-lander", "continuous-selected-device-final-evaluation-v1")
  , ("SAC/pendulum", "continuous-selected-device-final-evaluation-v1")
  , ("CrossQ/lunar-lander", "continuous-selected-device-final-evaluation-v1")
  , ("TQC/lunar-lander", "continuous-selected-device-final-evaluation-v1")
  , ("HER/goal-reaching", "her-selected-device-greedy-sequential-goals-v1")
  , ("connect4", "alphazero-selected-device-arena-sequential-rng-v1")
  , ("othello", "alphazero-selected-device-arena-sequential-rng-v1")
  , ("hex", "alphazero-selected-device-arena-sequential-rng-v1")
  , ("gomoku", "alphazero-selected-device-arena-sequential-rng-v1")
  , ("DQN/cartpole", "dqn-selected-device-checked-legal-final-evaluation-v1")
  , ("DQN/mountain-car", "dqn-selected-device-checked-legal-final-evaluation-v1")
  , ("DQN/key-door-grid", "dqn-selected-device-checked-legal-final-evaluation-v1")
  ]

checkCombinedRlLane :: [Baseline] -> Substrate -> IO (Int, Int)
checkCombinedRlLane slOnly lane = do
  length plannedRlRecipes @?= 17
  length (nub (fmap fst plannedRlRecipes)) @?= 17
  changed <- traverse checkRow Matrix.allProductRows
  pure (length (filter id changed), length (filter not changed))
 where
  checkRow row = do
    Baseline _ _ oldId oldSubject <- capturedFor slOnly lane row
    Matrix.SomeProductProjection _ projection <- expectSuccess (Matrix.projectProductRow lane row)
    let plan = Matrix.productProjectionRunPlan projection
        currentId = Plan.planIdText (Matrix.productProjectionPlanId projection)
    case lookup (Matrix.rowId row) plannedRlRecipes of
      Nothing -> do
        preRegressionRevisionIdentity projection >>= (@?= (oldId, oldSubject))
        pure False
      Just recipe -> do
        fields <- expectRight (parseSubject (Plan.runPlanSubjectId plan))
        stripped <- expectRight (removeEvaluationRecipe recipe fields)
        renderSubject stripped @?= oldSubject
        reconstructRlRecipeIdentity projection oldSubject >>= (@?= oldId)
        assertBool "planned RL recipe did not version identity" (currentId /= oldId)
        pure True

removeEvaluationRecipe :: Text -> [Text] -> Either Text [Text]
removeEvaluationRecipe recipe fields = case indices of
  [index] -> case drop index fields of
    "evaluation-recipe" : actual : _
      | actual == recipe -> Right (take index fields <> drop (index + 2) fields)
    _ -> Left "substituted evaluation recipe"
  _ -> Left "evaluation recipe must occur exactly once"
 where
  indices = [index | (index, value) <- zip [0 :: Int ..] fields, value == "evaluation-recipe"]

-- Preserve actual common-vs-workload identity boundaries. AlphaZero's outer
-- PlanId includes its actual game and must not be replaced by common RunPlanId.
reconstructRlRecipeIdentity :: Matrix.ProductProjection kind -> Text -> IO Text
reconstructRlRecipeIdentity projection subject =
  case Matrix.productProjectionResolvedPlan projection of
    Matrix.ResolvedRlProductPlan plan -> do
      let (steps, ticks, environments, horizon, episodes) = Plan.runPlanRlBudget plan
          budget =
            Plan.RawRlBudget
              (quantityInteger steps)
              (quantityInteger ticks)
              (quantityInteger environments)
              (quantityInteger horizon)
              (quantityInteger episodes)
      legacy <-
        expectSuccess
          (Plan.resolveRun (requestWithBudget Plan.ReinforcementLearningWitness plan budget subject))
      pure (Plan.planIdText (Plan.runPlanId legacy))
    Matrix.ResolvedAlphaZeroProductPlan workload -> do
      let plan = Workload.alphaZeroPlanRunPlan workload
          (generations, games, simulations, plies, updates, arena) = Plan.runPlanAlphaZeroBudget plan
          budget =
            Plan.RawAlphaZeroBudget
              (quantityInteger generations)
              (quantityInteger games)
              (quantityInteger simulations)
              (quantityInteger plies)
              (quantityInteger updates)
              (quantityInteger arena)
          raw =
            Workload.RawAlphaZeroPlan
              (requestWithBudget Plan.AlphaZeroSelfPlayWitness plan budget subject)
              (Workload.renderAlphaZeroGame (Workload.alphaZeroPlanGame workload))
      legacy <- expectSuccess (Workload.resolveAlphaZeroPlan raw)
      pure (Plan.planIdText (Workload.alphaZeroPlanId legacy))
    _ -> assertFailure "planned RL recipe change reached an unrelated run kind"

quantityInteger :: Plan.Quantity unit -> Integer
quantityInteger = toInteger . Plan.quantityValue

requestWithBudget
  :: Plan.RunKindWitness kind
  -> Plan.RunPlan kind
  -> Plan.RawRunBudget kind
  -> Text
  -> Plan.RawRunRequest kind
requestWithBudget witness plan budget subject =
  Plan.RawRunRequest
    { Plan.rawRunVersion = Plan.runPlanVersion plan
    , Plan.rawRunKind = witness
    , Plan.rawRunExperimentId = Plan.runPlanExperimentId plan
    , Plan.rawRunSubjectId = subject
    , Plan.rawRunArtifactId = Plan.runPlanArtifactId plan
    , Plan.rawRunTopicId = Plan.runPlanTopicId plan
    , Plan.rawRunSubstrate = Plan.runPlanSubstrate plan
    , Plan.rawRunPlacement = Plan.runPlanPlacement plan
    , Plan.rawRunSeeds = NonEmpty.toList (Plan.seedCohortValues (Plan.runPlanSeeds plan))
    , Plan.rawRunBudget = budget
    }

-- This is a structural allocation/identity test; it executes no model.
californiaDefaultHundredAllocation :: Assertion
californiaDefaultHundredAllocation = do
  Regression.regEpochs Regression.defaultRegressionConfig @?= 100
  row <-
    expectExactlyOne
      "canonical California row"
      [value | value <- supervisedRows, Matrix.rowId value == "california-housing-mlp"]
  Budget.trainingBudgetTargetUnits (Matrix.trainingBudget row) @?= 100
  expectedWork <- expectRight (Policy.supervisedExpectedWork 100 7000 128)
  Policy.supervisedExpectedEpochs expectedWork @?= 100
  Policy.supervisedExpectedExamplesProcessed expectedWork @?= 700000
  Policy.supervisedExpectedOptimizerUpdates expectedWork @?= 5500
  for_ allSubstrates $ \lane -> do
    projection <- supervisedProjection lane row
    let canonical = Matrix.productProjectionRunPlan projection
    supervisedBudgetValues canonical @?= (100, 7000, 1000, 128, 5500)
    -- Keeping the complete reg-ord1 subject but restoring only the old budget
    -- must still produce a distinct execution identity on every lane.
    previous <-
      expectSuccess
        ( Workload.resolveSupervisedPlan
            ( Workload.RawSupervisedPlan
                (requestWithHistoricalBudget projection canonical (Plan.runPlanSubjectId canonical))
            )
        )
    supervisedBudgetValues (Workload.supervisedPlanRunPlan previous)
      @?= (10, 7000, 1000, 128, 550)
    assertBool
      "allocation revision retained the ten-epoch execution identity"
      (Workload.supervisedPlanId previous /= Matrix.productProjectionPlanId projection)
    cohort <- expectRight (Cohort.mkSupervisedCohortPlan projection)
    let children = Cohort.supervisedCohortPlanChildren cohort
    fmap (Policy.supervisedSeedIndexValue . Cohort.supervisedSeedPlanIndex) children @?= [0 .. 4]
    fmap Cohort.supervisedSeedPlanSeed children @?= [1011 .. 1015]
    for_ children $ \child -> do
      let workload = Cohort.supervisedSeedPlanWorkload child
          plan = Workload.supervisedPlanRunPlan workload
      supervisedBudgetValues plan @?= (100, 7000, 1000, 128, 5500)
      fields <- expectRight (parseSubject (Plan.runPlanSubjectId plan))
      assertBool
        "allocation revision changed the complete regression order recipe"
        (["regression-training-order", Regression.regressionTrainingOrderContract] `isContiguous` fields)
      expectSuccess
        (Workload.parseSupervisedPlanTransport (Workload.renderSupervisedPlanTransport workload))
        >>= (@?= workload)

supervisedBudgetValues
  :: Plan.RunPlan 'Plan.SupervisedTraining -> (Integer, Integer, Integer, Integer, Integer)
supervisedBudgetValues plan =
  let (epochs, training, evaluation, batch, updates) = Plan.runPlanSupervisedBudget plan
   in ( quantityInteger epochs
      , quantityInteger training
      , quantityInteger evaluation
      , quantityInteger batch
      , quantityInteger updates
      )

childScope :: Assertion
childScope = do
  cohorts <- allCohorts
  length cohorts @?= 33
  for_ cohorts $ \cohort -> do
    let projection = Cohort.supervisedCohortPlanProjection cohort
        canonical = Matrix.productProjectionRunPlan projection
        children = Cohort.supervisedCohortPlanChildren cohort
        baseSeeds = NonEmpty.toList (Plan.seedCohortValues (Plan.runPlanSeeds canonical))
    base <- expectExactlyOne "canonical seed" baseSeeds
    fmap (Policy.supervisedSeedIndexValue . Cohort.supervisedSeedPlanIndex) children @?= [0 .. 4]
    fmap Cohort.supervisedSeedPlanSeed children @?= [base .. base + 4]
    for_ children $ \child -> do
      Cohort.supervisedSeedPlanBaseProjection child @?= projection
      let workload = Cohort.supervisedSeedPlanWorkload child
          plan = Workload.supervisedPlanRunPlan workload
      NonEmpty.toList (Plan.seedCohortValues (Plan.runPlanSeeds plan))
        @?= [Cohort.supervisedSeedPlanSeed child]
      Plan.runPlanSupervisedBudget plan @?= Plan.runPlanSupervisedBudget canonical
      Plan.runPlanSubstrate plan @?= Plan.runPlanSubstrate canonical
      Plan.runPlanPlacement plan @?= Plan.runPlanPlacement canonical
      Plan.runPlanTopicId plan @?= Plan.runPlanTopicId canonical
      expectSuccess
        (Workload.parseSupervisedPlanTransport (Workload.renderSupervisedPlanTransport workload))
        >>= (@?= workload)

childNamespaces :: Assertion
childNamespaces = do
  cohorts <- allCohorts
  for_ cohorts $ \cohort -> do
    let projection = Cohort.supervisedCohortPlanProjection cohort
        canonical = Matrix.productProjectionRunPlan projection
        children = Cohort.supervisedCohortPlanChildren cohort
    case children of
      serving : remaining -> do
        case Matrix.productProjectionResolvedPlan projection of
          Matrix.ResolvedSupervisedProductPlan workload -> Cohort.supervisedSeedPlanWorkload serving @?= workload
        for_ remaining $ \child -> do
          let plan = Workload.supervisedPlanRunPlan (Cohort.supervisedSeedPlanWorkload child)
              index = Policy.supervisedSeedIndexValue (Cohort.supervisedSeedPlanIndex child)
              suffix = "/supervised-qualification/" <> Text.pack (show index)
          Plan.runPlanExperimentId plan @?= Plan.runPlanExperimentId canonical <> suffix
          Plan.runPlanArtifactId plan @?= Plan.runPlanArtifactId canonical <> suffix
          assertBool
            "non-serving child reused the canonical identity"
            ( Workload.supervisedPlanId (Cohort.supervisedSeedPlanWorkload child)
                /= Matrix.productProjectionPlanId projection
            )
      [] -> assertFailure "cohort omitted serving index zero"
    length (nub (fmap (Workload.supervisedPlanId . Cohort.supervisedSeedPlanWorkload) children)) @?= 5

parentIdentities :: Assertion
parentIdentities = do
  cohorts <- allCohorts
  length (nub (fmap Cohort.supervisedCohortPlanId cohorts)) @?= 33
  length
    ( nub
        ( concatMap
            ( fmap (Workload.supervisedPlanId . Cohort.supervisedSeedPlanWorkload)
                . Cohort.supervisedCohortPlanChildren
            )
            cohorts
        )
    )
    @?= 165
  for_ cohorts $ \cohort -> do
    recreated <-
      expectRight (Cohort.mkSupervisedCohortPlan (Cohort.supervisedCohortPlanProjection cohort))
    recreated @?= cohort
    expectSuccess (Plan.planIdFromCanonicalText (Cohort.supervisedCohortPlanTransport cohort))
      >>= (@?= Cohort.supervisedCohortPlanId cohort)
    -- Independent transport assembly binds each full child, its order and seed.
    let fields =
          Policy.supervisedQualificationPolicyContract
            : Plan.planIdText (Matrix.productProjectionPlanId (Cohort.supervisedCohortPlanProjection cohort))
            : concatMap childFields (Cohort.supervisedCohortPlanChildren cohort)
        encoded = "jitml-supervised-cohort-plan-v1|" <> Text.concat (fmap field fields)
    Cohort.supervisedCohortPlanTransport cohort @?= encoded
 where
  childFields child =
    [ Text.pack (show (Policy.supervisedSeedIndexValue (Cohort.supervisedSeedPlanIndex child)))
    , Text.pack (show (Cohort.supervisedSeedPlanSeed child))
    , Workload.renderSupervisedPlanTransport (Cohort.supervisedSeedPlanWorkload child)
    ]

alteredMetadata :: Assertion
alteredMetadata =
  for_ allSubstrates $ \lane -> for_ supervisedRows $ \row -> do
    original <- supervisedProjection lane row
    changed <-
      supervisedProjection lane (row {Matrix.demoPanel = Matrix.demoPanel row <> "/substituted"})
    Matrix.productProjectionPlanId changed @?= Matrix.productProjectionPlanId original
    assertRejected (Cohort.mkSupervisedCohortPlan changed)
    changedIntegration <-
      supervisedProjection
        lane
        (row {Matrix.integrationTest = Matrix.integrationTest row <> "/substituted"})
    assertRejected (Cohort.mkSupervisedCohortPlan changedIntegration)

alteredExecution :: Assertion
alteredExecution = for_ supervisedRows $ \row -> do
  let oldBudget = Matrix.trainingBudget row
  changedBudget <-
    expectRight
      ( Budget.mkTrainingBudget
          (Budget.trainingBudgetKind oldBudget)
          (Budget.trainingBudgetTargetUnits oldBudget + 1)
          (Budget.trainingBudgetSeed oldBudget)
      )
  for_
    [ row {Matrix.experimentConfig = Matrix.experimentConfig row <> "/substituted"}
    , row {Matrix.trainingBudget = changedBudget}
    ]
    $ \changed ->
      case Matrix.projectProductRow headLane changed of
        Plan.Failure _ -> pure ()
        Plan.Success (Matrix.SomeProductProjection Plan.SupervisedTrainingWitness projection) -> assertRejected (Cohort.mkSupervisedCohortPlan projection)
        Plan.Success _ -> assertFailure "supervised mutation changed its run kind"
 where
  headLane = minBound

laneSubstitution :: Assertion
laneSubstitution = do
  cohorts <- allCohorts
  for_ cohorts $ \cohort -> for_ (Cohort.supervisedCohortPlanChildren cohort) $ \child -> do
    let workload = Cohort.supervisedSeedPlanWorkload child
        plan = Workload.supervisedPlanRunPlan workload
        current = renderSubstrate (Plan.runPlanSubstrate plan)
        other = if current == "linux-cpu" then "linux-cuda" else "linux-cpu"
        rendered = Workload.renderSupervisedPlanTransport workload
        substituted = Text.replace ("substrate=" <> current) ("substrate=" <> other) rendered
    assertBool "lane substitution did not alter transport" (substituted /= rendered)
    case Workload.parseSupervisedPlanTransport substituted of
      Plan.Failure _ -> pure ()
      Plan.Success _ -> assertFailure "foreign lane retained the declared child identity"

combinedHeadroom :: Assertion
combinedHeadroom = for_ supervisedRows $ \row -> do
  problem <-
    maybe
      (assertFailure "canonical supervised problem missing")
      pure
      (find ((== Matrix.rowId row) . SL.problemName) SL.canonicalProblems)
  let architectureOffset = case Matrix.rowClass row of
        Matrix.SupervisedRegression _ _ -> 0
        _ -> Architecture.architectureSeedHeadroomForProblem problem
      offset = 4 + architectureOffset
      boundary = fromInteger (toInteger (maxBound :: Int) - offset)
      old = Matrix.trainingBudget row
      seeded seed = do
        budget <-
          expectRight
            ( Budget.mkTrainingBudget
                (Budget.trainingBudgetKind old)
                (Budget.trainingBudgetTargetUnits old)
                (Just seed)
            )
        pure row {Matrix.trainingBudget = budget}
  safe <- seeded boundary
  _ <- expectSuccess (Matrix.projectProductRow minBound safe)
  shifted <-
    expectRight
      (traverse (Policy.supervisedSeedForIndex boundary architectureOffset) Policy.supervisedSeedIndices)
  assertBool
    "architecture initialization can overflow at a safe cohort boundary"
    (all (\seed -> toInteger seed + architectureOffset <= toInteger (maxBound :: Int)) shifted)
  unsafe <- seeded (boundary + 1)
  case Matrix.projectProductRow minBound unsafe of
    Plan.Failure errors -> assertBool "combined headroom diagnostic missing" (any (matchesOffset offset) errors)
    Plan.Success _ -> assertFailure "last prescribed seed can overflow architecture initialization"
 where
  matchesOffset offset err = case err of
    Matrix.InsufficientProductSeedHeadroom _ _ _ actual -> actual == offset
    _ -> False

subjectParserControls :: Assertion
subjectParserControls = do
  let fields =
        [ "row"
        , "supervised-qualification"
        , Policy.supervisedQualificationPolicyContract
        , "cohort-base-seed"
        , "1001"
        , "subject"
        , "λ:|"
        ]
  parseSubject (renderSubject fields) @?= Right fields
  removePolicy fields @?= Right ["row", "subject", "λ:|"]
  assertRejected (removePolicy ["row", "subject"])
  assertRejected (removePolicy (fields <> fields))
  assertRejected
    (removePolicy ["supervised-qualification", "wrong-policy", "cohort-base-seed", "1001"])
  assertRejected (parseSubject "product-row-v1|4:abc|")
  assertRejected (parseSubject "product-row-v1|x:abc|")
  let recipe = "qrdqn-selected-device-final-evaluation-v1"
      evaluated = ["row", "evaluation-recipe", recipe, "subject", "λ:|"]
  removeEvaluationRecipe recipe evaluated @?= Right ["row", "subject", "λ:|"]
  assertRejected (removeEvaluationRecipe recipe ["row", "subject"])
  assertRejected (removeEvaluationRecipe recipe (evaluated <> evaluated))
  assertRejected (removeEvaluationRecipe recipe ["evaluation-recipe", "wrong-recipe"])

supervisedRows :: [Matrix.ProductRow 'Matrix.Declared]
supervisedRows = filter ((== Matrix.Supervised) . Matrix.family) Matrix.allProductRows

supervisedProjection
  :: Substrate
  -> Matrix.ProductRow 'Matrix.Declared
  -> IO (Matrix.ProductProjection 'Plan.SupervisedTraining)
supervisedProjection lane row = do
  projected <- expectSuccess (Matrix.projectProductRow lane row)
  case projected of
    Matrix.SomeProductProjection Plan.SupervisedTrainingWitness value -> pure value
    _ -> assertFailure "expected supervised projection"

data Baseline = Baseline Text Text Text Text

-- Historical file remains untouched and retains the exact actual a145 capture.
readBaseline :: IO [Baseline]
readBaseline =
  readProjectionCapture
    "test/fixtures/compact-supervised-before-identities.txt"
    "without_on_policy_recipes_plan_id"

-- Required future actual46a capture BEFORE any cycle90 source application.
readSlOnlyBaseline :: IO [Baseline]
readSlOnlyBaseline =
  readProjectionCapture
    "test/fixtures/compact-supervised-46a-identities.txt"
    "without_supervised_policy_plan_id"

-- Preserve the genuine combined-producer historical capture. Current RL
-- fields stay intact; California's explicit historical comparison separately
-- restores its original ten-epoch budget. Captured fixture bytes stay unchanged.
readCurrentRlIsolationBaseline :: IO [Baseline]
readCurrentRlIsolationBaseline =
  readProjectionCapture
    "test/fixtures/compact-supervised-current-rl-isolation-identities.txt"
    "without_supervised_policy_plan_id"

readProjectionCapture :: FilePath -> Text -> IO [Baseline]
readProjectionCapture path lastColumn = do
  contents <- TextIO.readFile path
  case filter (not . Text.isPrefixOf "#") (Text.lines contents) of
    header : rows -> do
      header
        @?= ("substrate\trow_id\tplan_id\tcommon_plan_id\treport_contract_sha256\tsubject\t" <> lastColumn)
      traverse parseRow rows
    [] -> assertFailure "captured identity fixture is empty"
 where
  parseRow line = case Text.splitOn "\t" line of
    [lane, row, identity, _, _, subject, _] -> do
      _ <- expectRight (Plan.refinePlanIdText identity)
      pure (Baseline lane row identity subject)
    _ -> assertFailure "captured identity fixture has an unexpected column count"

-- Historical captures precede the hundred-epoch allocation. Restore only
-- California's original ten epochs and550 updates for those counterfactuals;
-- all other budget dimensions, seeds, subjects and genuine fixtures stay exact.
requestWithHistoricalBudget
  :: Matrix.ProductProjection 'Plan.SupervisedTraining
  -> Plan.RunPlan 'Plan.SupervisedTraining
  -> Text
  -> Plan.RawRunRequest 'Plan.SupervisedTraining
requestWithHistoricalBudget projection plan subject =
  let (epochs, training, evaluation, batch, updates) = Plan.runPlanSupervisedBudget plan
      quantity :: Plan.Quantity unit -> Integer
      quantity = toInteger . Plan.quantityValue
      historicalCalifornia = Matrix.productProjectionRowId projection == "california-housing-mlp"
   in Plan.RawRunRequest
        { Plan.rawRunVersion = Plan.runPlanVersion plan
        , Plan.rawRunKind = Plan.SupervisedTrainingWitness
        , Plan.rawRunExperimentId = Plan.runPlanExperimentId plan
        , Plan.rawRunSubjectId = subject
        , Plan.rawRunArtifactId = Plan.runPlanArtifactId plan
        , Plan.rawRunTopicId = Plan.runPlanTopicId plan
        , Plan.rawRunSubstrate = Plan.runPlanSubstrate plan
        , Plan.rawRunPlacement = Plan.runPlanPlacement plan
        , Plan.rawRunSeeds = NonEmpty.toList (Plan.seedCohortValues (Plan.runPlanSeeds plan))
        , Plan.rawRunBudget =
            Plan.RawSupervisedBudget
              (if historicalCalifornia then 10 else quantity epochs)
              (quantity training)
              (quantity evaluation)
              (quantity batch)
              (if historicalCalifornia then 550 else quantity updates)
        }

parseSubject :: Text -> Either Text [Text]
parseSubject input =
  maybe
    (Left "missing product subject version")
    parseFields
    (Text.stripPrefix "product-row-v1|" input)
 where
  parseFields remaining
    | Text.null remaining = Right []
    | otherwise = do
        let (digits, suffix) = Text.breakOn ":" remaining
        count <-
          maybe (Left "invalid subject field length") Right (readMaybe (Text.unpack digits) :: Maybe Int)
        if count < 0 || Text.null suffix then Left "invalid subject field boundary" else Right ()
        let (value, tailText) = Text.splitAt count (Text.drop 1 suffix)
        if Text.length value /= count then Left "short subject field" else Right ()
        rest <- maybe (Left "missing subject delimiter") Right (Text.stripPrefix "|" tailText)
        (value :) <$> parseFields rest

removePolicy :: [Text] -> Either Text [Text]
removePolicy fields = case candidates of
  [index] -> case drop index fields of
    "supervised-qualification" : policy : "cohort-base-seed" : seed : _
      | policy == Policy.supervisedQualificationPolicyContract
      , Just _ <- (readMaybe (Text.unpack seed) :: Maybe Integer) ->
          Right (take index fields <> drop (index + 4) fields)
    _ -> Left "substituted qualification policy fields"
  _ -> Left "qualification fields must occur exactly once"
 where
  candidates = [index | (index, value) <- zip [0 ..] fields, value == "supervised-qualification"]

renderSubject :: [Text] -> Text
renderSubject fields = "product-row-v1|" <> Text.concat (fmap field fields)

field :: Text -> Text
field value = Text.pack (show (Text.length value)) <> ":" <> value <> "|"

assertRejected :: (Show value) => Either Text value -> Assertion
assertRejected value = assertBool ("expected rejection, got " <> show value) (isLeft value)

expectRight :: (Show err) => Either err value -> IO value
expectRight = either (assertFailure . show) pure

expectSuccess :: (Show err) => Plan.Validation err value -> IO value
expectSuccess result = case result of
  Plan.Success value -> pure value
  Plan.Failure err -> assertFailure (show err)

expectExactlyOne :: String -> [value] -> IO value
expectExactlyOne _ [value] = pure value
expectExactlyOne label _ = assertFailure (label <> " must occur exactly once")

isContiguous :: (Eq value) => [value] -> [value] -> Bool
isContiguous needle values = any ((== needle) . take (length needle)) (tails values)
 where
  tails [] = [[]]
  tails rest@(_ : following) = rest : tails following
