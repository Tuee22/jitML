{-# LANGUAGE OverloadedStrings #-}

module ArsAppliedStep (arsAppliedStepTests) where

import Control.Monad (forM_, (>=>))
import Data.Text (Text)
import Data.Vector.Unboxed qualified as VU
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.RL.Algorithms.ArsTrainer qualified as Ars
import JitML.RL.Algorithms.Common qualified as Common
import JitML.RL.Simulator qualified as Sim
import JitML.RL.TrainerObservation qualified as Observation

-- Raw numerical fixture observations do not attest process/device authority,
-- accepted directions, return improvement, convergence, or a five-seed cohort.
arsAppliedStepTests :: TestTree
arsAppliedStepTests =
  testGroup
    "raw ARS applied-step trace and exact replay"
    [ testCase "actual lower ARS return replays every applied step from actual initial to final" $ withTrace $ \raw -> do
        Ars.validateArsTrainObservation raw @?= Right ()
        let observations = Common.rawTrainerStats raw
        length observations @?= Ars.arsIterations config
        forM_ observations $ \observation ->
          Ars.validateArsAppliedStep (Ars.arsObservationAppliedStep observation) @?= Right ()
        Common.rawTrainerInitialParams raw @?= Ars.initialArsParams config
        Common.observedEnvironmentTransitionCount (Common.rawTrainerCounters raw) @?= 960
        Common.observedOptimizerUpdateCount (Common.rawTrainerCounters raw) @?= 3
    , testCase
        "legacy strict result preserves its original statistics parameters configuration and counters"
        $ withTrace
        $ \raw -> do
          refined <- expectRight (Ars.refineArsTrainObservation raw)
          strict <- Ars.trainArsOnCartpole config
          refined @?= strict
          Ars.arsResultStats refined @?= fmap Ars.arsObservationStatistic (Common.rawTrainerStats raw)
          Ars.arsResultInitialParams refined @?= Common.rawTrainerInitialParams raw
          Ars.arsResultFinalParams refined @?= Common.rawTrainerFinalParams raw
          Ars.arsResultConfig refined @?= config
    , testCase "actual sampled perturbation returns and physical steps are captured before the update" $ do
        let tiny = config {Ars.arsIterations = 2, Ars.arsObsSize = 1, Ars.arsMaxEpisodeSteps = 3}
        raw <- Ars.trainArsOnEnvironmentRaw (Sim.SomeSimulatedEnvironment actionEnvironment) tiny
        Ars.validateArsTrainObservation raw @?= Right ()
        forM_ (Common.rawTrainerStats raw) $ \observation -> do
          let step = Ars.arsObservationAppliedStep observation
              before = Ars.arsStepThetaBefore step
              noise = Ars.arsStepNoiseStd step
          forM_ (Ars.arsStepEvaluatedPerturbations step) $ \((plus, plusSteps), (minus, minusSteps), delta) -> do
            let thetaPlus = VU.zipWith (\theta direction -> theta + noise * direction) before (VU.fromList delta)
                thetaMinus = VU.zipWith (\theta direction -> theta - noise * direction) before (VU.fromList delta)
                reward theta = if theta VU.! 0 >= theta VU.! 1 then 0 else 1
            plus @?= reward thetaPlus
            minus @?= reward thetaMinus
            plusSteps @?= 3
            minusSteps @?= 3
          Ars.arsStepObservedTransitions step @?= 24
    , testCase "finite no-op applications remain present without an accepted or learning flag" $ do
        let noMotion = config {Ars.arsStepSize = 0}
        raw <- Ars.trainArsOnCartpoleRaw noMotion
        Ars.validateArsTrainObservation raw @?= Right ()
        length (Common.rawTrainerStats raw) @?= 3
        Common.rawTrainerFinalParams raw @?= Common.rawTrainerInitialParams raw
        Common.observedOptimizerUpdateCount (Common.rawTrainerCounters raw) @?= 3
        forM_ (Common.rawTrainerStats raw) $ \observation -> do
          let step = Ars.arsObservationAppliedStep observation
          Ars.arsStepThetaBefore step @?= Ars.arsStepThetaAfter step
          Ars.arsStepScale step @?= 0
    , testCase "theta arithmetic is exact and rejects a changed finite after value" $ withFirstStep $ \step -> do
        expectLeft
          "ARS applied-step theta arithmetic differs"
          (Ars.validateArsAppliedStep step {Ars.arsStepThetaAfter = bumpVector (Ars.arsStepThetaAfter step)})
    , testCase "theta and sampled direction dimensions and nonfinite values fail specifically" $ withFirstStep $ \step -> do
        forM_ [VU.empty, VU.singleton (0 / 0)] $ \bad ->
          expectLeft
            "ARS applied-step theta shape or finite values differ"
            (Ars.validateArsAppliedStep step {Ars.arsStepThetaBefore = bad})
        expectLeft
          "ARS applied-step sampled direction shape or finite values differ"
          ( Ars.validateArsAppliedStep
              step {Ars.arsStepSampledDirections = mapFirst (const VU.empty) (Ars.arsStepSampledDirections step)}
          )
    , testCase "sampled direction count and evaluated direction identity cannot be substituted" $ withFirstStep $ \step -> do
        expectLeft
          "ARS applied-step sampled direction count differs"
          (Ars.validateArsAppliedStep step {Ars.arsStepSampledDirections = []})
        expectLeft
          "ARS applied-step perturbation count differs"
          (Ars.validateArsAppliedStep step {Ars.arsStepEvaluatedPerturbations = []})
        expectLeft
          "ARS applied-step evaluated direction differs from sampled direction"
          ( Ars.validateArsAppliedStep
              step
                { Ars.arsStepEvaluatedPerturbations =
                    mapFirst
                      (\(plus, minus, delta) -> (plus, minus, bumpList delta))
                      (Ars.arsStepEvaluatedPerturbations step)
                }
          )
    , testCase "nonfinite plus and minus returns fail before update replay" $ withFirstStep $ \step -> do
        let mutations =
              [ \((_, steps), minus, delta) -> ((0 / 0, steps), minus, delta)
              , \(plus, (_, steps), delta) -> (plus, (1 / 0, steps), delta)
              ]
        forM_ mutations $ \mutate ->
          expectLeft
            "ARS applied-step perturbation return is nonfinite"
            ( Ars.validateArsAppliedStep
                step {Ars.arsStepEvaluatedPerturbations = mapFirst mutate (Ars.arsStepEvaluatedPerturbations step)}
            )
    , testCase "finite plus or minus substitution cannot retain the original kept returns" $ withFirstStep $ \step -> do
        let mutations =
              [ \((value, steps), minus, delta) -> ((value + 1, steps), minus, delta)
              , \(plus, (value, steps), delta) -> (plus, (value + 1, steps), delta)
              ]
        forM_ mutations $ \mutate ->
          expectLeft
            "ARS applied-step kept directions or order differ"
            ( Ars.validateArsAppliedStep
                step {Ars.arsStepEvaluatedPerturbations = fmap mutate (Ars.arsStepEvaluatedPerturbations step)}
            )
    , testCase "each paired physical step count and total are independently checked" $ withFirstStep $ \step -> do
        let mutations =
              [ \((value, steps), minus, delta) -> ((value, steps + 1), minus, delta)
              , \(plus, (value, steps), delta) -> (plus, (value, steps - 1), delta)
              ]
        forM_ mutations $ \mutate ->
          expectLeft
            "ARS applied-step perturbation physical steps differ"
            ( Ars.validateArsAppliedStep
                step {Ars.arsStepEvaluatedPerturbations = mapFirst mutate (Ars.arsStepEvaluatedPerturbations step)}
            )
        expectLeft
          "ARS applied-step physical transition count differs"
          ( Ars.validateArsAppliedStep
              step {Ars.arsStepObservedTransitions = Ars.arsStepObservedTransitions step + 1}
          )
    , testCase "kept direction rank order and aggregate vector are exact" $ withFirstStep $ \step -> do
        expectLeft
          "ARS applied-step kept directions or order differ"
          ( Ars.validateArsAppliedStep
              step {Ars.arsStepKeptDirections = reverse (Ars.arsStepKeptDirections step)}
          )
        expectLeft
          "ARS applied-step aggregate update differs"
          ( Ars.validateArsAppliedStep
              step {Ars.arsStepUpdateDirection = bumpList (Ars.arsStepUpdateDirection step)}
          )
    , testCase "noise return standard deviation and scale have no tolerance allowance" $ withFirstStep $ \step -> do
        let cases =
              [
                ( "ARS applied-step noise standard deviation differs"
                , step {Ars.arsStepNoiseStd = Ars.arsStepNoiseStd step + 1}
                )
              ,
                ( "ARS applied-step return standard deviation differs"
                , step {Ars.arsStepReturnStdDev = Ars.arsStepReturnStdDev step + 1}
                )
              , ("ARS applied-step scale differs", step {Ars.arsStepScale = Ars.arsStepScale step + 1})
              ]
        forM_ cases $ \(reason, changed) -> expectLeft reason (Ars.validateArsAppliedStep changed)
    , testCase "binary64 signed zero cannot replace an exactly replayed after value" $ do
        raw <- Ars.trainArsOnCartpoleRaw config {Ars.arsStepSize = 0}
        observation <- firstObservation raw
        let step = Ars.arsObservationAppliedStep observation
            after = Ars.arsStepThetaAfter step
        assertBool "actual zero step is represented by finite positive zero" (VU.all (== 0) after)
        expectLeft
          "ARS applied-step theta arithmetic differs"
          (Ars.validateArsAppliedStep step {Ars.arsStepThetaAfter = after VU.// [(0, -0.0)]})
    , testCase "invalid configuration and out-of-range index reject before numerical replay" $ withFirstStep $ \step -> do
        let original = Ars.arsStepConfig step
        forM_
          [ original {Ars.arsNoiseStd = 0}
          , original {Ars.arsStepSize = 0 / 0}
          , original {Ars.arsTopB = 0}
          , original {Ars.arsObsSize = maxBound, Ars.arsActionCount = 2}
          ]
          $ \bad ->
            expectLeft
              "ARS trace configuration is invalid"
              (Ars.validateArsAppliedStep step {Ars.arsStepConfig = bad})
        expectLeft
          "ARS applied-step index is outside its configuration"
          (Ars.validateArsAppliedStep step {Ars.arsStepIndex = Ars.arsIterations original})
    , testCase "trace binds every actual configuration and ordered iteration index" $ withTrace $ \raw -> do
        let mutateConfig step = step {Ars.arsStepConfig = (Ars.arsStepConfig step) {Ars.arsSeed = 999}}
        expectLeft
          "ARS trace applied-step configuration differs"
          (Ars.validateArsTrainObservation (modifyStepAt 0 mutateConfig raw))
        expectLeft
          "ARS trace iteration index differs"
          (Ars.validateArsTrainObservation (modifyStepAt 0 (\step -> step {Ars.arsStepIndex = 1}) raw))
    , testCase "seed substitution cannot reuse the old sampled RNG sequence" $ withTrace $ \raw -> do
        let changedConfig = (Common.rawTrainerConfig raw) {Ars.arsSeed = Ars.arsSeed config + 1}
            changed =
              raw
                { Common.rawTrainerConfig = changedConfig
                , Common.rawTrainerStats =
                    fmap
                      ( \observation ->
                          observation
                            { Ars.arsObservationAppliedStep =
                                (Ars.arsObservationAppliedStep observation) {Ars.arsStepConfig = changedConfig}
                            }
                      )
                      (Common.rawTrainerStats raw)
                }
        expectLeft
          "ARS trace sampled directions differ from its configured RNG sequence"
          (Ars.validateArsTrainObservation changed)
    , testCase "trace rejects initial discontinuity intermediate discontinuity and final substitution" $ withTrace $ \raw -> do
        expectLeft
          "ARS trace initial parameters differ from the configured initializer"
          ( Ars.validateArsTrainObservation
              raw {Common.rawTrainerInitialParams = bumpVector (Common.rawTrainerInitialParams raw)}
          )
        expectLeft
          "ARS trace applied-step chain is discontinuous"
          ( Ars.validateArsTrainObservation
              ( modifyStepAt
                  1
                  (\step -> step {Ars.arsStepThetaBefore = bumpVector (Ars.arsStepThetaBefore step)})
                  raw
              )
          )
        expectLeft
          "ARS trace final parameters differ from its applied-step chain"
          ( Ars.validateArsTrainObservation
              raw {Common.rawTrainerFinalParams = bumpVector (Common.rawTrainerFinalParams raw)}
          )
    , testCase "trace cannot drop duplicate or reorder applications or substitute legacy summaries" $ withTrace $ \raw -> do
        let observations = Common.rawTrainerStats raw
        expectLeft
          "ARS trace iteration count differs"
          (Ars.validateArsTrainObservation raw {Common.rawTrainerStats = []})
        expectLeft
          "ARS trace iteration count differs"
          (Ars.validateArsTrainObservation raw {Common.rawTrainerStats = observations <> observations})
        expectLeft
          "ARS trace iteration index differs"
          (Ars.validateArsTrainObservation raw {Common.rawTrainerStats = reverse observations})
        let mutations =
              [ \stat -> stat {Ars.arsIterMeanReturn = 0 / 0}
              , \stat -> stat {Ars.arsIterMeanReturn = Ars.arsIterMeanReturn stat + 1}
              , \stat -> stat {Ars.arsIterBestReturn = Ars.arsIterBestReturn stat + 1}
              ]
        forM_ mutations $ \mutate -> do
          let bad =
                mapFirst
                  ( \observation -> observation {Ars.arsObservationStatistic = mutate (Ars.arsObservationStatistic observation)}
                  )
                  observations
          expectLeft
            "ARS trace legacy perturbation statistics differ"
            (Ars.validateArsTrainObservation raw {Common.rawTrainerStats = bad})
    , testCase "actual measured physical and optimizer totals bind the complete trace" $ withTrace $ \raw -> do
        let actual = Common.rawTrainerCounters raw
        wrongTransitions <-
          expectRight
            ( Common.mkObservedTrainerCounters
                (toInteger (Common.observedEnvironmentTransitionCount actual) + 1)
                (toInteger (Common.observedOptimizerUpdateCount actual))
            )
        wrongUpdates <-
          expectRight
            ( Common.mkObservedTrainerCounters
                (toInteger (Common.observedEnvironmentTransitionCount actual))
                (toInteger (Common.observedOptimizerUpdateCount actual) + 1)
            )
        expectLeft
          "ARS trace observed physical transition count differs"
          (Ars.validateArsTrainObservation raw {Common.rawTrainerCounters = wrongTransitions})
        expectLeft
          "ARS trace observed optimizer update count differs"
          (Ars.validateArsTrainObservation raw {Common.rawTrainerCounters = wrongUpdates})
    , testCase "zero-iteration raw return remains inspectable without weakening strict positive counters" $ do
        raw <- Ars.trainArsOnCartpoleRaw config {Ars.arsIterations = 0}
        Ars.validateArsTrainObservation raw @?= Right ()
        Common.rawTrainerStats raw @?= []
        Common.rawTrainerInitialParams raw @?= Common.rawTrainerFinalParams raw
        expectLeft
          "RL measured environment-transition count must be positive"
          (Ars.refineArsTrainObservation raw)
    , testCase "raw ARS adapter exposes unchanged summaries without replacing the retained step trace" $ withTrace $ \raw -> do
        let policy = Observation.ReturnedArs raw
        Observation.returnedLearningStatistics policy
          @?= ( "training_mean_reward"
              , [ (Ars.arsIterIndex stat, Ars.arsIterMeanReturn stat)
                | item <- Common.rawTrainerStats raw
                , let stat = Ars.arsObservationStatistic item
                ]
              )
        Observation.returnedCounters policy @?= Common.rawTrainerCounters raw
        Observation.returnedInitialWeights policy @?= VU.toList (Common.rawTrainerInitialParams raw)
        Observation.returnedFinalWeights policy @?= VU.toList (Common.rawTrainerFinalParams raw)
        let changed = modifyStepAt 0 (\step -> step {Ars.arsStepScale = Ars.arsStepScale step + 1}) raw
        expectLeft "ARS applied-step scale differs" (Ars.validateArsTrainObservation changed)
        -- The learning-statistics projection does not erase or repair raw data.
        Observation.returnedLearningStatistics (Observation.ReturnedArs changed)
          @?= Observation.returnedLearningStatistics policy
    , testCase "actual runtime metadata is retained and a different replay tuple fails explicitly" $ withFirstStep $ \step -> do
        Ars.arsStepNumericalRuntime step @?= Ars.arsNativeNumericalRuntime
        let runtime = Ars.arsStepNumericalRuntime step
            mutations =
              [ runtime {Ars.arsRuntimeOperatingSystem = Ars.arsRuntimeOperatingSystem runtime <> "-different"}
              , runtime {Ars.arsRuntimeArchitecture = Ars.arsRuntimeArchitecture runtime <> "-different"}
              , runtime {Ars.arsRuntimeCompilerVersion = Ars.arsRuntimeCompilerVersion runtime <> "-different"}
              , runtime {Ars.arsRuntimeArithmeticRecipe = Ars.arsRuntimeArithmeticRecipe runtime <> "-different"}
              ]
        forM_ mutations $ \changed ->
          expectLeft
            "ARS applied-step numerical runtime differs from the current replay runtime"
            (Ars.validateArsAppliedStep step {Ars.arsStepNumericalRuntime = changed})
    ]

config :: Ars.ArsTrainConfig
config =
  Ars.defaultArsTrainConfig
    { Ars.arsSeed = 13
    , Ars.arsIterations = 3
    , Ars.arsNumDirections = 4
    , Ars.arsTopB = 2
    , Ars.arsMaxEpisodeSteps = 40
    }

withTrace :: (Ars.ArsTrainObservation -> Assertion) -> Assertion
withTrace action = Ars.trainArsOnCartpoleRaw config >>= action

withFirstStep :: (Ars.ArsAppliedStep -> Assertion) -> Assertion
withFirstStep action = withTrace (firstObservation >=> (action . Ars.arsObservationAppliedStep))

firstObservation :: Ars.ArsTrainObservation -> IO Ars.ArsIterationObservation
firstObservation raw = case Common.rawTrainerStats raw of
  first : _ -> pure first
  [] -> assertFailure "actual lower ARS run returned no observation"

modifyStepAt
  :: Int
  -> (Ars.ArsAppliedStep -> Ars.ArsAppliedStep)
  -> Ars.ArsTrainObservation
  -> Ars.ArsTrainObservation
modifyStepAt target mutate raw =
  raw
    { Common.rawTrainerStats =
        [ if index == target
            then
              observation {Ars.arsObservationAppliedStep = mutate (Ars.arsObservationAppliedStep observation)}
            else observation
        | (index, observation) <- zip [0 :: Int ..] (Common.rawTrainerStats raw)
        ]
    }

mapFirst :: (a -> a) -> [a] -> [a]
mapFirst _ [] = []
mapFirst change (first : rest) = change first : rest

bumpList :: [Double] -> [Double]
bumpList = mapFirst (+ 1)

bumpVector :: VU.Vector Double -> VU.Vector Double
bumpVector = VU.fromList . bumpList . VU.toList

expectRight :: (Show error) => Either error value -> IO value
expectRight value = case value of Right result -> pure result; Left reason -> assertFailure (show reason)

expectLeft :: (Show value) => Text -> Either Text value -> Assertion
expectLeft reason actual = case actual of
  Left detail -> detail @?= reason
  Right value -> assertFailure ("expected exact rejection " <> show reason <> "; got " <> show value)

-- Every action ends a genuine simulated episode with its literal action as
-- reward. This is offline numerical fixture data, not provider/convergence proof.
actionEnvironment :: Sim.SimulatedEnvironment ()
actionEnvironment =
  Sim.SimulatedEnvironment
    { Sim.envName = "offline-ARS-action-reward"
    , Sim.envInitial = ()
    , Sim.envStep = \() action -> Sim.SimStep () (fromIntegral action) True
    , Sim.envRenderFrame = \() -> Sim.RenderFrame [1] "offline-action"
    , Sim.envActionCount = 2
    , Sim.envObservationSize = 1
    , Sim.envMaxEpisodeSteps = 3
    , Sim.envActionMask = Nothing
    , Sim.envTrainingStart = Nothing
    }
