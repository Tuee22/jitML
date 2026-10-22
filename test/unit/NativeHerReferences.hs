{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

module NativeHerReferences (nativeHerReferencesTests) where

import Control.Monad (forM_, replicateM)
import Data.Bits (popCount, setBit, testBit, xor)
import Data.List (find, group, sort)
import Data.List.NonEmpty qualified as NE
import Data.Text (Text)
import Data.Vector.Unboxed qualified as VU
import System.Random qualified as Random
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Plan.Plan qualified as Plan
import JitML.Product.Matrix qualified as Matrix
import JitML.RL.Algorithms.HerTrainer qualified as Her
import JitML.RL.ConvergenceThresholds qualified as Thresholds
import JitML.RL.NativeHerReferences qualified as Ref
import JitML.RL.ProductBudget qualified as ProductBudget
import JitML.Substrate (Substrate (..))
import JitML.Training.Budget qualified as Budget

-- Raw simulator fixtures and complete reference data only. No trained network,
-- selected-device/provider/authentication/quality or five-model cohort claim.
nativeHerReferencesTests :: TestTree
nativeHerReferencesTests =
  testGroup
    "paired native HER goals and complete goal-blind references"
    [ testCase "canonical specification binds actual six-bit twenty-case schedule and seed headroom" $ do
        spec <- expectRight Ref.canonicalNativeHerReferenceSpec
        Ref.nativeHerSpecRowId spec @?= "HER/goal-reaching"
        Ref.nativeHerSpecBits spec @?= Her.herNumBits Her.defaultHerTrainConfig
        Ref.nativeHerSpecBits spec @?= 6
        Ref.nativeHerSpecHorizon spec @?= 6
        Ref.nativeHerSpecEpisodeCount spec @?= ProductBudget.productRlDefaultEvaluationEpisodes
        Ref.nativeHerSpecEpisodeCount spec @?= 20
        Ref.nativeHerSpecBaseSeed spec @?= Her.herSeed Her.defaultHerTrainConfig
        Ref.nativeHerSpecBaseSeed spec @?= 42
        toInteger (Ref.nativeHerSpecEvaluationSeed spec) @?= toInteger (Ref.nativeHerSpecBaseSeed spec)
          + 104729
        schedule <- expectRight (ProductBudget.canonicalProductRlSchedule "HER" "goal-reaching")
        Budget.trainingBudgetTargetUnits (Ref.nativeHerSpecTrainingBudget spec)
          @?= ProductBudget.scheduleObservedEnvironmentSteps schedule
        case schedule of
          ProductBudget.HerTrainingSchedule {} -> ProductBudget.scheduleHerEnvironmentStepsPerEpisode schedule @?= 6
          _ -> assertFailure "actual schedule was not HER"
    , testCase
        "actual Matrix projections agree on canonical row budget six-step horizon twenty cases and base seed"
        $ do
          spec <- expectRight Ref.canonicalNativeHerReferenceSpec
          row <-
            maybe
              (assertFailure "actual HER ProductRow absent")
              pure
              (find ((== Ref.nativeHerSpecRowId spec) . Matrix.rowId) Matrix.allProductRows)
          forM_ [AppleSilicon, LinuxCPU, LinuxCUDA] $ \lane -> case Matrix.projectProductRow lane row of
            Plan.Failure reasons -> assertFailure (show reasons)
            Plan.Success (Matrix.SomeProductProjection _ projection) -> do
              Matrix.productProjectionRowId projection @?= Ref.nativeHerSpecRowId spec
              let seedlessBudget = Ref.nativeHerSpecTrainingBudget spec
              Budget.trainingBudgetSeed seedlessBudget @?= Nothing
              expectedSeededBudget <-
                expectRight
                  ( Budget.mkTrainingBudget
                      (Budget.trainingBudgetKind seedlessBudget)
                      (Budget.trainingBudgetTargetUnits seedlessBudget)
                      (Just 42)
                  )
              Matrix.productProjectionTrainingBudget projection @?= expectedSeededBudget
              fmap
                toInteger
                (NE.toList (Plan.seedCohortValues (Plan.runPlanSeeds (Matrix.productProjectionRunPlan projection))))
                @?= [42]
              case Matrix.productProjectionDescriptor projection of
                Matrix.RlProductDescriptor algorithm environment _ _ horizon count -> do
                  (algorithm, environment) @?= ("HER", "goal-reaching")
                  toInteger horizon @?= toInteger (Ref.nativeHerSpecHorizon spec)
                  toInteger count @?= toInteger (Ref.nativeHerSpecEpisodeCount spec)
                _ -> assertFailure "HER row did not retain an RL descriptor"
    , testCase "altered canonical environment or budget cannot refine as the reference specification" $ do
        let row = Thresholds.herGoalMetric
        expectLeft
          "native HER reference declaration differs from the exact canonical row"
          (Ref.mkCanonicalNativeHerReferenceSpec row {Thresholds.hgmEnvironment = "foreign-goal"})
        budget <-
          expectRight
            ( Budget.mkTrainingBudget
                Budget.RlEnvironmentStepBudget
                (Budget.trainingBudgetTargetUnits (Thresholds.hgmBudget row) + 1)
                Nothing
            )
        expectLeft
          "native HER reference declaration differs from the exact canonical row"
          (Ref.mkCanonicalNativeHerReferenceSpec row {Thresholds.hgmBudget = budget})
    , testCase "twenty keyed nonzero goals exactly match sampler-only actual production advancement" $ do
        spec <- expectRight Ref.canonicalNativeHerReferenceSpec
        schedule <- expectRight (Ref.generateNativeHerGoalSchedule spec)
        Ref.nativeHerScheduleSpec schedule @?= spec
        let actual = Ref.nativeHerScheduleCases schedule
            expected = directGoals 20 6 (Random.mkStdGen (Ref.nativeHerSpecEvaluationSeed spec))
        fmap Ref.rawNativeHerCaseId actual @?= [0 .. 19]
        fmap Ref.rawNativeHerGoal actual @?= expected
        length actual @?= 20
        forM_ actual $ \one -> do
          VU.length (Ref.rawNativeHerGoal one) @?= 6
          assertBool
            "sampled goals retain nonzero binary domain"
            ( VU.all (\value -> value == 0 || value == 1) (Ref.rawNativeHerGoal one)
                && VU.any (== 1) (Ref.rawNativeHerGoal one)
            )
        -- Exact ordered equality preserves every generated duplicate; there is no
        -- set conversion or uniqueness requirement on the goal values.
        Ref.refineNativeHerGoalSchedule spec actual @?= Right schedule
    , testCase "goal schedule is unchanged after controllers with different success lengths" $ do
        spec <- expectRight Ref.canonicalNativeHerReferenceSpec
        before <- expectRight (Ref.generateNativeHerGoalSchedule spec)
        left <- expectRight (Ref.refineNativeHerGoalBlindSequence spec [0, 0, 0, 0, 0, 0])
        right <- expectRight (Ref.refineNativeHerGoalBlindSequence spec [0, 1, 2, 3, 4, 5])
        _ <- expectRight (Ref.evaluateNativeHerGoalBlindSequence before left)
        _ <- expectRight (Ref.evaluateNativeHerGoalBlindSequence before right)
        after <- expectRight (Ref.generateNativeHerGoalSchedule spec)
        before @?= after
        fmap Ref.rawNativeHerGoal (Ref.nativeHerScheduleCases after)
          @?= directGoals 20 6 (Random.mkStdGen (Ref.nativeHerSpecEvaluationSeed spec))
    , testCase "missing duplicate foreign-order and nonbinary goal data reject specifically" $ do
        spec <- expectRight Ref.canonicalNativeHerReferenceSpec
        schedule <- expectRight (Ref.generateNativeHerGoalSchedule spec)
        let actual = Ref.nativeHerScheduleCases schedule
        expectLeft "native HER goal case count differs" (Ref.refineNativeHerGoalSchedule spec [])
        expectLeft
          "native HER goal case count differs"
          (Ref.refineNativeHerGoalSchedule spec (actual <> actual))
        expectLeft
          "native HER goal case IDs or order differ"
          (Ref.refineNativeHerGoalSchedule spec (reverse actual))
        let duplicate = mapAt 1 (\one -> one {Ref.rawNativeHerCaseId = 0}) actual
        expectLeft
          "native HER goal case IDs or order differ"
          (Ref.refineNativeHerGoalSchedule spec duplicate)
        forM_ [VU.empty, VU.replicate 6 0.5, VU.fromList [0 / 0, 0, 0, 0, 0, 1]] $ \bad ->
          expectLeft
            "native HER goal has an invalid bit shape or nonbinary value"
            (Ref.refineNativeHerGoalSchedule spec (mapAt 0 (\one -> one {Ref.rawNativeHerGoal = bad}) actual))
        expectLeft
          "native HER goal is the initial all-zero state"
          ( Ref.refineNativeHerGoalSchedule
              spec
              (mapAt 0 (\one -> one {Ref.rawNativeHerGoal = VU.replicate 6 0}) actual)
          )
    , testCase "a valid different nonzero binary goal cannot replace the fixed sampler result" $ do
        spec <- expectRight Ref.canonicalNativeHerReferenceSpec
        schedule <- expectRight (Ref.generateNativeHerGoalSchedule spec)
        let changed =
              mapAt
                0
                (\one -> one {Ref.rawNativeHerGoal = otherNonzeroGoal (Ref.rawNativeHerGoal one)})
                (Ref.nativeHerScheduleCases schedule)
        expectLeft
          "native HER goals differ from the sampler-only canonical schedule"
          (Ref.refineNativeHerGoalSchedule spec changed)
    , testCase "all six-to-six controllers are complete unique and lexicographically ordered" $ do
        spec <- expectRight Ref.canonicalNativeHerReferenceSpec
        let sequences = Ref.allNativeHerGoalBlindSequences spec
            actions = fmap Ref.nativeHerSequenceActions sequences
        length sequences @?= 6 ^ (6 :: Int)
        actions @?= replicateM 6 [0 .. 5]
        actions @?= sort actions
        length (group actions) @?= length actions
        forM_ sequences $ \goalBlindSequence -> do
          Ref.refineNativeHerGoalBlindSequence spec (Ref.nativeHerSequenceActions goalBlindSequence)
            @?= Right goalBlindSequence
          length (Ref.nativeHerSequenceActions goalBlindSequence) @?= 6
    , testCase "complete sequence validation rejects hidden malformed suffixes before early success" $ do
        spec <- expectRight Ref.canonicalNativeHerReferenceSpec
        forM_ [[], [0], [0, 1, 2, 3, 4], [0, 1, 2, 3, 4, 5, 0], [-1, 1, 2, 3, 4, 5], [0, 1, 2, 3, 4, 6]] $ \bad ->
          expectLeft
            "native HER sequence must contain the complete horizon of in-domain actions"
            (Ref.refineNativeHerGoalBlindSequence spec bad)
        expectLeft
          "native HER sequence must contain the complete horizon of in-domain actions"
          (Ref.evaluateHerSequenceFixture (VU.fromList [1, 0]) [0, 2])
    , testCase
        "actual bit-flip primitive stops at early success and retains terminal state and consumed prefix"
        $ do
          actual <- expectRight (Ref.evaluateHerSequenceFixture (VU.fromList [1, 0]) [0, 0])
          Ref.nativeHerOutcomeSuccess actual @?= True
          Ref.nativeHerOutcomeTerminated actual @?= True
          Ref.nativeHerOutcomeSteps actual @?= 1
          Ref.nativeHerOutcomeConsumedActions actual @?= [0]
          Ref.nativeHerOutcomeFinalState actual @?= VU.fromList [1, 0]
          Ref.nativeHerOutcomeHammingDistance actual @?= 0
          Ref.nativeHerOutcomeNormalizedDistance actual @?= 0
    , testCase "success on the last allowed flip stays terminal and missed horizon stays truncated" $ do
        success <- expectRight (Ref.evaluateHerSequenceFixture (VU.fromList [1, 1]) [0, 1])
        miss <- expectRight (Ref.evaluateHerSequenceFixture (VU.fromList [1, 1]) [0, 0])
        ( Ref.nativeHerOutcomeSteps success
          , Ref.nativeHerOutcomeSuccess success
          , Ref.nativeHerOutcomeTerminated success
          )
          @?= (2, True, True)
        ( Ref.nativeHerOutcomeSteps miss
          , Ref.nativeHerOutcomeSuccess miss
          , Ref.nativeHerOutcomeTerminated miss
          )
          @?= (2, False, False)
        Ref.nativeHerOutcomeNormalizedDistance miss
          @?= Her.bitDistance (Ref.nativeHerOutcomeFinalState miss) (VU.fromList [1, 1])
          / 2
    , testCase "independent integer-state oracle agrees on actual fixed-goal outcomes" $ do
        spec <- expectRight Ref.canonicalNativeHerReferenceSpec
        schedule <- expectRight (Ref.generateNativeHerGoalSchedule spec)
        forM_
          [[0, 0, 0, 0, 0, 0], [5, 5, 5, 5, 5, 5], [0, 1, 2, 3, 4, 5], [5, 4, 3, 2, 1, 0], [0, 1, 0, 2, 0, 3]]
          $ \actions -> do
            goalBlindSequence <- expectRight (Ref.refineNativeHerGoalBlindSequence spec actions)
            reference <- expectRight (Ref.evaluateNativeHerGoalBlindSequence schedule goalBlindSequence)
            forM_ (Ref.nativeHerObservedOutcomes reference) $ \outcome ->
              outcomeSummary outcome
                @?= directIntegerOracle (VU.toList (Ref.nativeHerOutcomeGoal outcome)) actions
    , testCase "each reference retains all twenty keys exact normalized binary64 means and actual work" $ do
        spec <- expectRight Ref.canonicalNativeHerReferenceSpec
        schedule <- expectRight (Ref.generateNativeHerGoalSchedule spec)
        goalBlindSequence <- expectRight (Ref.refineNativeHerGoalBlindSequence spec [0, 1, 2, 3, 4, 5])
        reference <- expectRight (Ref.evaluateNativeHerGoalBlindSequence schedule goalBlindSequence)
        let outcomes = Ref.nativeHerObservedOutcomes reference
        fmap Ref.nativeHerOutcomeCaseId outcomes @?= [0 .. 19]
        fmap Ref.nativeHerOutcomeGoal outcomes
          @?= fmap Ref.rawNativeHerGoal (Ref.nativeHerScheduleCases schedule)
        Ref.nativeHerObservedSuccessCount reference @?= length (filter Ref.nativeHerOutcomeSuccess outcomes)
        Ref.nativeHerObservedExactMeanDistance reference
          @?= sum (fmap (toRational . Ref.nativeHerOutcomeNormalizedDistance) outcomes)
          / 20
        Ref.nativeHerObservedEvaluationTransitions reference
          @?= sum (fmap (toInteger . Ref.nativeHerOutcomeSteps) outcomes)
        forM_ outcomes $ \outcome -> do
          Ref.nativeHerOutcomeNormalizedDistance outcome
            @?= Her.bitDistance (Ref.nativeHerOutcomeFinalState outcome) (Ref.nativeHerOutcomeGoal outcome)
            / 6
          Ref.nativeHerOutcomeSteps outcome @?= length (Ref.nativeHerOutcomeConsumedActions outcome)
    , testCase "complete family retains every sequence every outcome all extrema ties and whole work" $ do
        spec <- expectRight Ref.canonicalNativeHerReferenceSpec
        schedule <- expectRight (Ref.generateNativeHerGoalSchedule spec)
        family <- expectRight (Ref.evaluateNativeHerReferenceFamily schedule)
        let references = Ref.nativeHerObservedReferences family
            expected = Ref.allNativeHerGoalBlindSequences spec
            summary = Ref.nativeHerObservedExtrema family
        length references @?= 46656
        fmap Ref.nativeHerObservedSequence references @?= expected
        Ref.nativeHerObservedSchedule family @?= schedule
        forM_ references $ \reference -> do
          let outcomes = Ref.nativeHerObservedOutcomes reference
          fmap Ref.nativeHerOutcomeCaseId outcomes @?= [0 .. 19]
          Ref.nativeHerObservedSuccessCount reference @?= length (filter Ref.nativeHerOutcomeSuccess outcomes)
          Ref.nativeHerObservedExactMeanDistance reference
            @?= sum (fmap (toRational . Ref.nativeHerOutcomeNormalizedDistance) outcomes)
            / 20
        first <- firstValue references
        let maximumSuccess =
              foldl'
                max
                (Ref.nativeHerObservedSuccessCount first)
                (fmap Ref.nativeHerObservedSuccessCount references)
            minimumDistance =
              foldl'
                min
                (Ref.nativeHerObservedExactMeanDistance first)
                (fmap Ref.nativeHerObservedExactMeanDistance references)
        Ref.nativeHerMaximumSuccessCount summary @?= maximumSuccess
        Ref.nativeHerMinimumExactMeanDistance summary @?= minimumDistance
        Ref.nativeHerMaximumSuccessSequenceIds summary
          @?= [ Ref.nativeHerSequenceId (Ref.nativeHerObservedSequence r)
              | r <- references
              , Ref.nativeHerObservedSuccessCount r == maximumSuccess
              ]
        Ref.nativeHerMinimumDistanceSequenceIds summary
          @?= [ Ref.nativeHerSequenceId (Ref.nativeHerObservedSequence r)
              | r <- references
              , Ref.nativeHerObservedExactMeanDistance r == minimumDistance
              ]
        Ref.nativeHerTotalEvaluationTransitions family
          @?= sum (fmap Ref.nativeHerObservedEvaluationTransitions references)
        assertBool
          "all complete canonical reference work is separately represented"
          ( Ref.nativeHerTotalEvaluationTransitions family >= 46656 * 20
              && Ref.nativeHerTotalEvaluationTransitions family <= 46656 * 20 * 6
          )
    , testCase
        "fixture boundary rejects empty zero nonbinary goals and wrong action domain without learning authority"
        $ do
          expectLeft
            "HER sequence fixture requires a positive bit dimension"
            (Ref.evaluateHerSequenceFixture VU.empty [])
          expectLeft
            "native HER goal is the initial all-zero state"
            (Ref.evaluateHerSequenceFixture (VU.fromList [0, 0]) [0, 1])
          forM_ [VU.fromList [0.5, 1], VU.fromList [1 / 0, 1], VU.fromList [0 / 0, 1]] $ \goal ->
            expectLeft
              "native HER goal has an invalid bit shape or nonbinary value"
              (Ref.evaluateHerSequenceFixture goal [0, 1])
          expectLeft
            "native HER sequence must contain the complete horizon of in-domain actions"
            (Ref.evaluateHerSequenceFixture (VU.fromList [1, 0]) [-1, 1])
    ]

-- A different implementation: integer XOR dynamics and popcount rather than
-- the production Vector flipBit/bitDistance helpers used by the module.
directIntegerOracle :: [Double] -> [Int] -> (Bool, Double, Int, Bool, [Double], [Int])
directIntegerOracle goal = go (0 :: Integer) 0 []
 where
  bits = length goal
  target =
    foldl'
      (\value (index, bit) -> if bit == 1 then setBit value index else value)
      (0 :: Integer)
      (zip [0 :: Int ..] goal)
  go state steps consumed remaining
    | steps >= bits || state == target =
        let success = state == target
            distance = fromIntegral (popCount (state `xor` target)) / fromIntegral bits
            final = [if testBit state index then 1 else 0 | index <- [0 .. bits - 1]]
         in (success, distance, steps, success, final, reverse consumed)
    | otherwise = case remaining of
        action : rest -> go (state `xor` setBit (0 :: Integer) action) (steps + 1) (action : consumed) rest
        [] -> error "independent complete fixture sequence ended early"

outcomeSummary :: Ref.NativeHerReferenceOutcome -> (Bool, Double, Int, Bool, [Double], [Int])
outcomeSummary result =
  ( Ref.nativeHerOutcomeSuccess result
  , Ref.nativeHerOutcomeNormalizedDistance result
  , Ref.nativeHerOutcomeSteps result
  , Ref.nativeHerOutcomeTerminated result
  , VU.toList (Ref.nativeHerOutcomeFinalState result)
  , Ref.nativeHerOutcomeConsumedActions result
  )

directGoals :: Int -> Int -> Random.StdGen -> [VU.Vector Double]
directGoals 0 _ _ = []
directGoals count bits generator =
  let (goal, next) = Her.randomNonInitialGoal bits generator
   in goal : directGoals (count - 1) bits next

otherNonzeroGoal :: VU.Vector Double -> VU.Vector Double
otherNonzeroGoal goal = case VU.findIndex (== 0) goal of
  Just index -> goal VU.// [(index, 1)]
  Nothing -> goal VU.// [(0, 0)]
mapAt :: Int -> (value -> value) -> [value] -> [value]
mapAt selected change values = [if index == selected then change value else value | (index, value) <- zip [0 :: Int ..] values]
firstValue :: [value] -> IO value
firstValue values = case values of
  first : _ -> pure first
  [] -> assertFailure "required complete reference fixture was empty"
expectRight :: (Show error) => Either error value -> IO value
expectRight actual = case actual of Right value -> pure value; Left reason -> assertFailure (show reason)
expectLeft :: (Show value) => Text -> Either Text value -> Assertion
expectLeft expected actual = case actual of
  Left reason -> reason @?= expected
  Right value -> assertFailure ("expected exact rejection " <> show expected <> "; got " <> show value)
