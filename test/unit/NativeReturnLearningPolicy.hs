{-# LANGUAGE OverloadedStrings #-}

module NativeReturnLearningPolicy (nativeReturnLearningPolicyTests) where

import Control.Monad (forM_, (>=>))
import Data.Text (Text)
import Data.Text qualified as Text
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Product.NativeReturnLearningPolicy qualified as Policy
import JitML.RL.ConvergenceThresholds qualified as Thresholds
import JitML.RL.Framework qualified as Framework
import JitML.RL.NativeReturnReferences qualified as References

-- Explicit raw arithmetic fixtures. No synthetic observation here represents
-- a trainer/device/checkpoint/producer result or an actual qualification.
nativeReturnLearningPolicyTests :: TestTree
nativeReturnLearningPolicyTests =
  testGroup
    "native return five-member mathematical comparison"
    [ testCase
        "three joint successes retain both finite failed members and the original serving observation"
        $ do
          references <- actualReferences
          let seeds = seedScores [500, 500, 500, 0, 0]
          actual <- compareCohort references seeds >>= expectRight
          Policy.nativeReturnComparisonObservations actual @?= seeds
          Policy.nativeReturnComparisonReferences actual @?= references
          Policy.nativeReturnComparisonJointCount actual @?= 3
          Policy.nativeReturnComparisonMedianQuality actual @?= 500
          Policy.nativeReturnComparisonFailures actual @?= []
          fmap Policy.nativeReturnSeedComparisonIndex (Policy.nativeReturnComparisonSeeds actual) @?= [0 .. 4]
          fmap Policy.nativeReturnSeedComparisonJointLearning (Policy.nativeReturnComparisonSeeds actual)
            @?= [True, True, True, False, False]
    , testCase "two successes cannot replace the whole-five median with a selected successful subset" $ do
        references <- actualReferences
        actual <- compareCohort references (seedScores [500, 500, 0, 0, 0]) >>= expectRight
        Policy.nativeReturnComparisonJointCount actual @?= 2
        Policy.nativeReturnComparisonMedianQuality actual @?= 0
        requireFailure "fewer than three" actual
        requireFailure "whole-five median" actual
        length (Policy.nativeReturnComparisonObservations actual) @?= 5
    , testCase "four auxiliary successes cannot replace a failed original serving seed" $ do
        references <- actualReferences
        actual <- compareCohort references (seedScores [0, 500, 500, 500, 500]) >>= expectRight
        Policy.nativeReturnComparisonJointCount actual @?= 4
        Policy.nativeReturnComparisonMedianQuality actual @?= 500
        requireFailure "served index0 fails" actual
    , testCase "passing every unchanged quality floor cannot replace strict initialization improvement" $ do
        references <- actualReferences
        let seeds =
              fmap
                (\seed -> seed {Policy.nativeReturnObservedInitialEpisodes = episodes 500})
                (seedScores (replicate 5 500))
        actual <- compareCohort references seeds >>= expectRight
        Policy.nativeReturnComparisonJointCount actual @?= 0
        requireFailure "initial observation" actual
        Policy.nativeReturnComparisonMedianQuality actual @?= 500
    , testCase "improvement over a weak initializer cannot replace beating every task reference" $ do
        references <- actualReferences
        let seeds =
              fmap
                (\seed -> seed {Policy.nativeReturnObservedInitialEpisodes = episodes (-1)})
                (seedScores (replicate 5 0))
        actual <- compareCohort references seeds >>= expectRight
        Policy.nativeReturnComparisonJointCount actual @?= 0
        requireFailure "every fixed task reference" actual
    , testCase "equality with one named reference defeats strict learning despite all other references" $ do
        references <- actualReferences
        let tied =
              changeFirstReference
                ( \observed ->
                    observed
                      { References.nativeReturnObservedEpisodes = episodes 500
                      , References.nativeReturnObservedEvaluationTransitions = 10000
                      }
                )
                references
            tiedComplete =
              tied
                { References.nativeReturnTotalEvaluationTransitions =
                    sum
                      ( fmap
                          References.nativeReturnObservedEvaluationTransitions
                          (References.nativeReturnObservedReferences tied)
                      )
                }
        actual <- compareCohort tiedComplete (seedScores (replicate 5 500)) >>= expectRight
        Policy.nativeReturnComparisonJointCount actual @?= 0
        requireFailure "every fixed task reference" actual
    , testCase "all five joint improvements retain a failing historical quality floor" $ do
        references <- actualReferences
        maximumReference <- case [ References.nativeReturnEpisodeReward episode
                                 | observed <- References.nativeReturnObservedReferences references
                                 , episode <- References.nativeReturnObservedEpisodes observed
                                 ] of
          [] -> assertFailure "actual canonical reference episodes absent"
          first : rest -> pure (foldr max first rest)
        let score = maximumReference + 1
        threshold <-
          maybe
            (assertFailure "actual PPO/cartpole quality declaration absent")
            pure
            (Thresholds.cohortThreshold "PPO" "cartpole")
        assertBool
          "fixture reference unexpectedly reaches the strong quality floor"
          (not (Thresholds.passesConvergence threshold score))
        actual <- compareCohort references (seedScores (replicate 5 score)) >>= expectRight
        Policy.nativeReturnComparisonJointCount actual @?= 5
        requireFailure "whole-five median" actual
        requireFailure "served index0 fails: final primary metric" actual
    , testCase "joint successes count conjunctions within the same seed" $ do
        references <- actualReferences
        let seeds =
              [ seed
                  { Policy.nativeReturnObservedInitialEpisodes = episodes (if even index then 500 else (-1))
                  , Policy.nativeReturnObservedFinalEpisodes = episodes (if even index then 500 else 0)
                  }
              | (index, seed) <- zip [0 :: Int ..] (seedScores (replicate 5 500))
              ]
        actual <- compareCohort references seeds >>= expectRight
        Policy.nativeReturnComparisonJointCount actual @?= 0
    , testCase "all finite failed outcomes remain a complete assessable failed cohort" $ do
        references <- actualReferences
        let seeds = seedScores (replicate 5 0)
        actual <- compareCohort references seeds >>= expectRight
        Policy.nativeReturnComparisonObservations actual @?= seeds
        Policy.nativeReturnComparisonJointCount actual @?= 0
        requireFailure "fewer than three" actual
    , testCase "missing extra duplicated and reordered seed indices are invalid inputs" $ do
        references <- actualReferences
        let seeds = seedScores (replicate 5 500)
        forM_
          [ take 4 seeds
          , seeds <> take 1 seeds
          , reverse seeds
          , fmap (\seed -> seed {Policy.nativeReturnObservedSeedIndex = 0}) seeds
          ]
          (compareCohort references >=> expectLeft "exactly five ordered indices0..4")
    , testCase "a replacement seed cannot occupy an original prescribed member" $ do
        references <- actualReferences
        let seeds =
              fmap
                (\seed -> seed {Policy.nativeReturnObservedSeed = Policy.nativeReturnObservedSeed seed + 1})
                (seedScores (replicate 5 500))
        compareCohort references seeds >>= expectLeft "prescribed42+index"
    , testCase "missing duplicated foreign or reordered evaluation keys invalidate the complete input" $ do
        references <- actualReferences
        let complete = episodes 500
            change selected =
              fmap
                (\seed -> seed {Policy.nativeReturnObservedFinalEpisodes = selected})
                (seedScores (replicate 5 500))
        forM_
          [ take 19 complete
          , reverse complete
          , fmap (\episode -> episode {References.nativeReturnEpisodeId = 0}) complete
          , fmap
              ( \episode -> episode {References.nativeReturnEpisodeId = References.nativeReturnEpisodeId episode + 1}
              )
              complete
          ]
          $ \bad ->
            compareCohort references (change bad) >>= expectLeft "every case exactly once in canonical order"
    , testCase "zero steps incomplete truncations and excess horizon reject before comparison" $ do
        references <- actualReferences
        forM_ [(0, True), (1, False), (501, True)] $ \(steps, done) -> do
          let badEpisodes =
                fmap
                  ( \episode ->
                      episode
                        { References.nativeReturnEpisodeSteps = steps
                        , References.nativeReturnEpisodeTerminated = done
                        }
                  )
                  (episodes 500)
              seeds =
                fmap
                  (\seed -> seed {Policy.nativeReturnObservedFinalEpisodes = badEpisodes})
                  (seedScores (replicate 5 500))
          compareCohort references seeds >>= expectLeft "termination or horizon is incomplete"
    , testCase "nonfinite observations are invalid rather than dropped from five" $ do
        references <- actualReferences
        forM_ [0 / 0, 1 / 0, negate (1 / 0)] $ \bad -> do
          let seeds =
                fmap
                  (\seed -> seed {Policy.nativeReturnObservedFinalEpisodes = episodes bad})
                  (seedScores (replicate 5 500))
          compareCohort references seeds >>= expectLeft "finite"
    , testCase "reference controllers cannot be omitted duplicated relabelled or reordered" $ do
        references <- actualReferences
        let controllers = References.nativeReturnObservedReferences references
            substitute selected = references {References.nativeReturnObservedReferences = selected}
        forM_
          [ take 1 controllers
          , controllers <> take 1 controllers
          , reverse controllers
          , fmap
              (\observed -> observed {References.nativeReturnObservedController = References.ConstantDiscrete 0})
              controllers
          ]
          $ \bad ->
            compareCohort (substitute bad) (seedScores (replicate 5 500))
              >>= expectLeft "every prescribed controller exactly once"
    , testCase "per-controller and total reference work are independently checked" $ do
        references <- actualReferences
        let wrongOne =
              changeFirstReference
                ( \observed ->
                    observed
                      { References.nativeReturnObservedEvaluationTransitions =
                          References.nativeReturnObservedEvaluationTransitions observed + 1
                      }
                )
                references
            wrongTotal =
              references
                { References.nativeReturnTotalEvaluationTransitions =
                    References.nativeReturnTotalEvaluationTransitions references + 1
                }
        compareCohort wrongOne (seedScores (replicate 5 500))
          >>= expectLeft "controller transition count differs"
        compareCohort wrongTotal (seedScores (replicate 5 500))
          >>= expectLeft "whole reference transition count differs"
    , testCase "canonical native-zero controller identity preserves its actual signed-zero bits" $ do
        spec <- expectRight (References.canonicalNativeReturnSpec "SAC" "pendulum")
        references <- expectRight (References.evaluateCanonicalNativeReturnReferences spec)
        let episodeValues reward =
              [ References.NativeReturnEpisode index reward (References.nativeReturnSpecHorizon spec) False
              | index <- [0 .. 19]
              ]
            seeds =
              [ Policy.NativeReturnSeedObservation
                  index
                  (42 + fromIntegral index)
                  (episodeValues 0)
                  (episodeValues 500)
              | index <- [0 .. 4]
              ]
            wrong =
              changeFirstReference
                ( \observed ->
                    observed
                      { References.nativeReturnObservedController =
                          References.ConstantContinuous References.NativeZero (-0.0)
                      }
                )
                references
        compareCohort references seeds >>= expectRight >> pure ()
        compareCohort wrong seeds >>= expectLeft "every prescribed controller exactly once"
    , testCase "new exact comparisons cannot borrow rounded legacy Double medians" $ do
        references <- actualReferences
        let value = 9007199254740992 :: Double
            finalEpisodes =
              zipWith
                (\episode score -> episode {References.nativeReturnEpisodeReward = score})
                (episodes value)
                (replicate 10 value <> replicate 10 (value + 2))
            seeds =
              fmap
                ( \seed ->
                    seed
                      { Policy.nativeReturnObservedInitialEpisodes = episodes value
                      , Policy.nativeReturnObservedFinalEpisodes = finalEpisodes
                      }
                )
                (seedScores (replicate 5 value))
        actual <- compareCohort references seeds >>= expectRight
        forM_ (Policy.nativeReturnComparisonSeeds actual) $ \seed -> do
          Policy.nativeReturnSeedComparisonInitialMedian seed @?= toRational value
          Policy.nativeReturnSeedComparisonFinalMedian seed @?= toRational value + 1
          Policy.nativeReturnSeedComparisonLegacyQuality seed @?= value
          Policy.nativeReturnSeedComparisonJointLearning seed @?= True
    , testCase "legacy quality uses the actual existing Framework summary including finite large values" $ do
        references <- actualReferences
        let values = replicate 20 (1e308 :: Double)
            finalEpisodes =
              zipWith
                (\episode score -> episode {References.nativeReturnEpisodeReward = score})
                (episodes 500)
                values
            seeds =
              fmap
                (\seed -> seed {Policy.nativeReturnObservedFinalEpisodes = finalEpisodes})
                (seedScores (replicate 5 500))
        framework <-
          expectRight
            ( Framework.mkEvaluationSet
                20
                [(fromIntegral index, value, 500, False) | (index, value) <- zip [0 :: Int ..] values]
            )
        actual <- compareCohort references seeds >>= expectRight
        fmap Policy.nativeReturnSeedComparisonLegacyQuality (Policy.nativeReturnComparisonSeeds actual)
          @?= replicate 5 (Framework.evaluationSetMedianReward framework)
    ]

actualReferences :: IO References.NativeReturnReferenceSet
actualReferences = do
  spec <- expectRight (References.canonicalNativeReturnSpec "PPO" "cartpole")
  expectRight (References.evaluateCanonicalNativeReturnReferences spec)

episodes :: Double -> [References.NativeReturnEpisode]
episodes reward = [References.NativeReturnEpisode index reward 500 False | index <- [0 .. 19]]

seedScores :: [Double] -> [Policy.NativeReturnSeedObservation]
seedScores scores =
  [ Policy.NativeReturnSeedObservation index (42 + fromIntegral index) (episodes 0) (episodes score)
  | (index, score) <- zip [0 ..] scores
  ]

changeFirstReference
  :: (References.NativeReturnReferenceObservation -> References.NativeReturnReferenceObservation)
  -> References.NativeReturnReferenceSet
  -> References.NativeReturnReferenceSet
changeFirstReference change references =
  references
    { References.nativeReturnObservedReferences = case References.nativeReturnObservedReferences references of
        first : rest -> change first : rest
        [] -> []
    }

requireFailure :: Text -> Policy.NativeReturnCohortComparison -> Assertion
requireFailure fragment actual =
  assertBool
    ("missing expected failure: " <> Text.unpack fragment)
    (any (Text.isInfixOf fragment) (Policy.nativeReturnComparisonFailures actual))

expectLeft :: Text -> Either Text value -> Assertion
expectLeft fragment actual = case actual of
  Left reason -> assertBool ("wrong failure: " <> Text.unpack reason) (fragment `Text.isInfixOf` reason)
  Right _ -> assertFailure "structurally invalid raw cohort was compared"
expectRight :: (Show error) => Either error value -> IO value
expectRight actual = case actual of Left reason -> assertFailure (show reason); Right value -> pure value

compareCohort
  :: References.NativeReturnReferenceSet
  -> [Policy.NativeReturnSeedObservation]
  -> IO (Either Text Policy.NativeReturnCohortComparison)
compareCohort references observations = pure (Policy.compareNativeReturnCohort references observations)
