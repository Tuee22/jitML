{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Phase 278 unit coverage for the exact served-byte metric check
-- ('JitML.Product.ServedMetric') and for its post-admission wiring in the
-- supervised publisher.
--
-- Every served-metric case runs against a real Store-admitted checkpoint built
-- by 'SupervisedCheckpointV2', so the serving graph, the physical weight tensor,
-- and the admission path are the production ones. Most fixtures serve a constant
-- function of the input (all weights zero except the output bias), and two serve
-- a function of it (one class or value per kind of input); either way the served
-- accuracy or RMSE of an evidence set is exactly computable by hand, so nothing
-- here compares the check against itself. The constant fixtures cannot tell a
-- replay of each example's own input from a replay that reuses one input or
-- misaligns labels and targets; the input-dependent ones can.
module ServedMetricVerification (servedMetricVerificationTests) where

import Control.Exception (SomeException, fromException, try)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (runReaderT)
import Data.List (isInfixOf, isPrefixOf, isSuffixOf)
import Data.Text (Text)
import Data.Text qualified as Text
import Path (parseAbsDir)
import System.Directory (removeDirectoryRecursive)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp
  ( createTempDirectory
  , getCanonicalTemporaryDirectory
  , withSystemTempDirectory
  )
import Test.Tasty (TestTree, testGroup, withResource)
import Test.Tasty.HUnit
  ( Assertion
  , assertBool
  , assertFailure
  , testCase
  , (@?=)
  )

import JitML.Checkpoint.Store qualified as CheckpointStore
import JitML.Checkpoint.WeightCodec qualified as WeightCodec
import JitML.Checkpoint.Writer qualified as CheckpointWriter
import JitML.Env.Build (buildEnv, defaultGlobalFlags)
import JitML.Env.Env (Env (..))
import JitML.Product.Completion qualified as ProductCompletion
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Product.Publisher qualified as ProductPublisher
import JitML.Product.ServedMetric qualified as ServedMetric
import JitML.Substrate qualified as Substrate

import SupervisedCheckpointV2
  ( Fixture
  , admitCompletedFixture
  , authoritativeSupervisedProjection
  , californiaFixtureRow
  , expectRight
  , makeFixtureForRowAndBytes
  , makeTrainingCompletionFixture
  , mnistFixtureRow
  , substitutedSupervisedPublisherRuntime
  , supervisedPublishRunFixture
  )

servedMetricVerificationTests :: TestTree
servedMetricVerificationTests =
  testGroup
    "Served-metric verification (Phase 278)"
    [ classificationToleranceTests
    , smallHeldOutSetTests
    , regressionTests
    , rejectionTests
    , inputDependentClassificationTests
    , featureDependentRegressionTests
    , publisherWiringTests
    ]

-- ---------------------------------------------------------------------------
-- Fixtures

type Admitted = IO CheckpointStore.AdmittedCompletedCheckpoint

-- | One Store-admitted checkpoint shared by a group of read-only assertions.
-- The temporary Store root outlives every test of the group and is removed
-- when the group finishes.
withAdmitted :: IO (Either Text Fixture) -> (Admitted -> TestTree) -> TestTree
withAdmitted build inner =
  withResource acquire (removeDirectoryRecursive . fst) (inner . fmap snd)
 where
  acquire = do
    parent <- getCanonicalTemporaryDirectory
    root <- createTempDirectory parent "jitml-served-metric"
    fixture <- expectRight =<< build
    admitted <- admitCompletedFixture root fixture
    pure (root, admitted)

-- | A classification checkpoint that serves class 1 for every input: all
-- weights are zero except the output bias of class 1. Its served accuracy on
-- any evidence set is therefore the fraction of examples labelled 1.
--
-- The final dense layer emits 'rawOutputWidth' values (the ten classes plus one
-- padding output that the semantic-prefix transform slices off), and its bias is
-- the last block of the graph-ordered flat weights.
classOneCheckpoint :: IO (Either Text Fixture)
classOneCheckpoint =
  makeFixtureForRowAndBytes mnistFixtureRow 1.0 $ \parameterCount ->
    WeightCodec.encodeJmw1
      ( replicate (parameterCount - rawOutputWidth) 0.0
          <> [if cls == 1 then 10.0 else 0.0 | cls <- [0 .. rawOutputWidth - 1]]
      )

rawOutputWidth :: Int
rawOutputWidth = 11

-- | A regression checkpoint whose served output is the constant @bias@: all
-- weights are zero except the single output bias, which is the last parameter
-- of the graph-ordered flat layout. The runtime destandardizes with mean 100
-- and scale 5, so the served value is @100 + 5 * bias@ for every input. The
-- manifest metric is a passing RMSE; the served check never reads it.
constantRegressionCheckpoint :: Double -> IO (Either Text Fixture)
constantRegressionCheckpoint bias =
  makeFixtureForRowAndBytes californiaFixtureRow 0.5 $ \parameterCount ->
    WeightCodec.encodeJmw1 (replicate (parameterCount - 1) 0.0 <> [bias])

nan :: Double
nan = 0 / 0

positiveInfinity :: Double
positiveInfinity = 1 / 0

negativeInfinity :: Double
negativeInfinity = negate positiveInfinity

blankImage :: [Double]
blankImage = replicate 784 0.0

blankFeatures :: [Double]
blankFeatures = replicate 8 0.0

-- | @total@ examples of which @correct@ are labelled 1. Against the class-one
-- checkpoint the served accuracy is exactly @correct / total@.
classOneEvidence :: Int -> Int -> ServedMetric.HeldOutExamples
classOneEvidence total correct =
  ServedMetric.HeldOutClassification
    (replicate correct (blankImage, 1) <> replicate (total - correct) (blankImage, 0))

accuracy :: Int -> Int -> Double
accuracy total correct = fromIntegral correct / fromIntegral total

-- | One example per target, all with the same blank features. The constant
-- served output makes the standardized RMSE a function of the targets alone.
regressionEvidence :: Double -> [Double] -> ServedMetric.HeldOutExamples
regressionEvidence scale targets =
  ServedMetric.HeldOutRegression scale [(blankFeatures, target) | target <- targets]

-- | 500 targets 2.5 above and 500 below the served value 105 of the bias-1
-- checkpoint. Errors are exactly +/-0.5 in units of the model's scale 5, so
-- the standardized RMSE is exactly 0.5.
halfScaleTargets :: [Double]
halfScaleTargets = concat (replicate 500 [107.5, 102.5])

-- | Targets 10 above and below 105: errors of +/-2 model scales, RMSE 2.0.
twoScaleTargets :: [Double]
twoScaleTargets = concat (replicate 500 [115.0, 95.0])

-- ---------------------------------------------------------------------------
-- Assertions

served
  :: Admitted
  -> Text
  -> Double
  -> ServedMetric.HeldOutExamples
  -> IO (Either Text ())
served getAdmitted metricName reported evidence = do
  admitted <- getAdmitted
  ServedMetric.assertAdmittedHeldOutMetric admitted metricName reported evidence

accepts :: Admitted -> Text -> Double -> ServedMetric.HeldOutExamples -> Assertion
accepts getAdmitted metricName reported evidence =
  served getAdmitted metricName reported evidence >>= (@?= Right ())

-- | The rejection must be the served-versus-reported diagnostic carrying
-- exactly the reported and the recomputed values, not any other failure.
rejectsMismatch
  :: Admitted
  -> Text
  -> Double
  -> Double
  -> ServedMetric.HeldOutExamples
  -> Assertion
rejectsMismatch getAdmitted metricName reported servedValue evidence = do
  result <- served getAdmitted metricName reported evidence
  case result of
    Right () ->
      assertFailure
        ( "reported "
            <> Text.unpack metricName
            <> " "
            <> show reported
            <> " was accepted although the admitted bytes serve "
            <> show servedValue
        )
    Left err -> do
      let text = Text.unpack err
      assertBool
        ("not the served-versus-reported diagnostic: " <> text)
        ( ("reported " <> Text.unpack metricName <> " does not match exact admitted served bytes (manifest=")
            `isPrefixOf` text
        )
      assertBool
        ("diagnostic must carry the reported and served values: " <> text)
        ((", reported=" <> show reported <> ", served=" <> show servedValue <> ")") `isSuffixOf` text)

rejectsWith :: Admitted -> Text -> Double -> ServedMetric.HeldOutExamples -> Text -> Assertion
rejectsWith getAdmitted metricName reported evidence expected =
  served getAdmitted metricName reported evidence >>= (@?= Left expected)

-- ---------------------------------------------------------------------------
-- Classification tolerance

-- | The accuracy allowance is @min 0.01 (1 / n + 1e-9)@: at most one borderline
-- class decision, never more than a hundredth. Every canonical supervised row
-- is evaluated on exactly 1,000 held-out examples, where the allowance is one
-- decision (0.001) plus a nano-slack that absorbs float rounding of the
-- difference.
classificationToleranceTests :: TestTree
classificationToleranceTests =
  withAdmitted classOneCheckpoint $ \admitted ->
    let n1000 = classOneEvidence 1000 900
        base = accuracy 1000 900
     in testGroup
          "classification tolerance (canonical n = 1000, served accuracy 0.9)"
          [ testCase "the recomputed accuracy is the served fraction" $ do
              checkpoint <- admitted
              ServedMetric.recomputeAdmittedHeldOutMetric checkpoint n1000 >>= (@?= Right 0.9)
          , testCase "a reported accuracy equal to the served one is accepted" $
              accepts admitted "test_accuracy" 0.9 n1000
          , testCase "one flipped decision is accepted in either direction" $ do
              accepts admitted "test_accuracy" 0.901 n1000
              accepts admitted "test_accuracy" 0.899 n1000
          , testCase "two flipped decisions are rejected in either direction" $ do
              rejectsMismatch admitted "test_accuracy" 0.902 0.9 n1000
              rejectsMismatch admitted "test_accuracy" 0.898 0.9 n1000
          , testCase "the slack above one decision is a nano-slack, not a rounding hole" $ do
              accepts admitted "test_accuracy" (base + 0.001 + 5.0e-10) n1000
              accepts admitted "test_accuracy" (base - 0.001 - 5.0e-10) n1000
              rejectsMismatch admitted "test_accuracy" (base + 0.001 + 2.0e-9) (0.9 :: Double) n1000
              rejectsMismatch admitted "test_accuracy" (base - 0.001 - 2.0e-9) (0.9 :: Double) n1000
          , testCase "the one-decision rule holds at both accuracy extremes" $ do
              accepts admitted "test_accuracy" 0.999 (classOneEvidence 1000 1000)
              rejectsMismatch admitted "test_accuracy" 0.998 1.0 (classOneEvidence 1000 1000)
              accepts admitted "test_accuracy" 0.001 (classOneEvidence 1000 0)
              rejectsMismatch admitted "test_accuracy" 0.002 0.0 (classOneEvidence 1000 0)
          ]

-- | For a held-out set smaller than 100 examples one decision is worth more than
-- 0.01, so the cap makes the check reject even a one-example skew. This is
-- intentional and fails closed: the cap was added because the uncapped
-- @1 / n + 1e-9@ allowed a one-example set to accept a reported accuracy a whole
-- point away from the served one (the Phase 278 plan document records that
-- failed attempt). It costs nothing on the canonical rows, which all evaluate
-- on 1,000 examples (pinned by the evaluation example count group below).
-- (At exactly n = 100 the cap and one decision coincide, so whether a single
-- flip passes depends on float rounding of the difference; that knife edge is
-- deliberately not pinned here.)
smallHeldOutSetTests :: TestTree
smallHeldOutSetTests =
  withAdmitted classOneCheckpoint $ \admitted ->
    testGroup
      "small held-out sets (intentional fail-closed cap of 0.01)"
      [ testCase "a one-example set cannot accept a whole-point difference" $ do
          accepts admitted "test_accuracy" 1.0 (classOneEvidence 1 1)
          rejectsMismatch admitted "test_accuracy" 0.0 1.0 (classOneEvidence 1 1)
      , testCase "n = 50: one decision (0.02) exceeds the cap and is rejected" $ do
          accepts admitted "test_accuracy" 0.5 (classOneEvidence 50 25)
          rejectsMismatch admitted "test_accuracy" (accuracy 50 26) (accuracy 50 25) (classOneEvidence 50 25)
          rejectsMismatch admitted "test_accuracy" (accuracy 50 24) (accuracy 50 25) (classOneEvidence 50 25)
      , testCase "n = 50: the allowance is exactly the 0.01 cap, in absolute terms" $ do
          accepts admitted "test_accuracy" 0.5099 (classOneEvidence 50 25)
          rejectsMismatch admitted "test_accuracy" 0.5101 0.5 (classOneEvidence 50 25)
      , testCase "n = 99: one decision (1/99 > 0.01) is still above the cap" $
          rejectsMismatch
            admitted
            "test_accuracy"
            (accuracy 99 51)
            (accuracy 99 50)
            (classOneEvidence 99 50)
      , testCase "n = 101 is the smallest set where one decision fits inside the cap" $ do
          accepts admitted "test_accuracy" (accuracy 101 51) (classOneEvidence 101 50)
          accepts admitted "test_accuracy" (accuracy 101 49) (classOneEvidence 101 50)
          rejectsMismatch
            admitted
            "test_accuracy"
            (accuracy 101 52)
            (accuracy 101 50)
            (classOneEvidence 101 50)
      , testCase "n = 200: one decision (0.005) is accepted, two (0.01) are rejected" $ do
          accepts admitted "test_accuracy" (accuracy 200 151) (classOneEvidence 200 150)
          rejectsMismatch
            admitted
            "test_accuracy"
            (accuracy 200 152)
            (accuracy 200 150)
            (classOneEvidence 200 150)
      ]

-- ---------------------------------------------------------------------------
-- Regression

-- | Regression is checked in the standardized RMSE unit the trainer reports:
-- the raw served-versus-target error is divided by the positive @scale@ carried
-- with the evidence. The allowance is @0.005 * max 1 |reported|@: an absolute
-- half-hundredth up to a reported RMSE of 1, and half a percent above it.
regressionTests :: TestTree
regressionTests =
  testGroup
    "regression path"
    [ withAdmitted (constantRegressionCheckpoint 1.0) $ \matching ->
        let half = regressionEvidence 5.0 halfScaleTargets
            two = regressionEvidence 5.0 twoScaleTargets
         in testGroup
              "checkpoint serving 105 (bias 1.0)"
              [ testCase "the recomputed value is the standardized RMSE" $ do
                  checkpoint <- matching
                  ServedMetric.recomputeAdmittedHeldOutMetric checkpoint half >>= (@?= Right 0.5)
                  ServedMetric.recomputeAdmittedHeldOutMetric checkpoint two >>= (@?= Right 2.0)
              , testCase "the positive scale converts raw error to standardized units" $ do
                  checkpoint <- matching
                  -- The same raw errors of 2.5 are 0.25 standardized errors at
                  -- scale 10 and 1.0 standardized errors at scale 2.5.
                  ServedMetric.recomputeAdmittedHeldOutMetric
                    checkpoint
                    (regressionEvidence 10.0 halfScaleTargets)
                    >>= (@?= Right 0.25)
                  ServedMetric.recomputeAdmittedHeldOutMetric
                    checkpoint
                    (regressionEvidence 2.5 halfScaleTargets)
                    >>= (@?= Right 1.0)
              , testCase "a reported RMSE equal to the served one is accepted" $
                  accepts matching "rmse" 0.5 half
              , testCase "an RMSE reported under a different scale is rejected" $
                  -- 0.5 is the RMSE at scale 5; at scale 10 the same bytes serve 0.25.
                  rejectsMismatch matching "rmse" 0.5 0.25 (regressionEvidence 10.0 halfScaleTargets)
              , testCase "below a reported RMSE of 1 the allowance is the absolute 0.005" $ do
                  accepts matching "rmse" 0.5049 half
                  accepts matching "rmse" 0.4951 half
                  rejectsMismatch matching "rmse" 0.5051 0.5 half
                  rejectsMismatch matching "rmse" 0.4949 0.5 half
              , testCase "above a reported RMSE of 1 the allowance is relative (0.5 percent)" $ do
                  accepts matching "rmse" 2.0099 two
                  accepts matching "rmse" 1.9901 two
                  rejectsMismatch matching "rmse" 2.0101 2.0 two
                  rejectsMismatch matching "rmse" 1.9899 2.0 two
              , testCase "the relative allowance scales with the reported value, not the served one" $ do
                  -- The allowance is 0.005 * |reported|, so a value reported above
                  -- the served 2.0 gets slightly more than 0.01 and one reported
                  -- below it slightly less. Each probe sits between the allowance
                  -- computed from the reported value and the one computed from the
                  -- served value, so scaling by the served value flips both verdicts.
                  accepts matching "rmse" 2.01002 two
                  rejectsMismatch matching "rmse" 1.99002 2.0 two
              ]
    , withAdmitted (constantRegressionCheckpoint 3.0) $ \substituted ->
        let half = regressionEvidence 5.0 halfScaleTargets
            -- Errors of 1.5 and 2.5 model scales against the served value 115.
            substitutedRmse = sqrt ((1.5 * 1.5 + 2.5 * 2.5) / 2.0) :: Double
         in testGroup
              "checkpoint serving 115 (bias 3.0, substituted weights)"
              [ testCase "weights that serve a different function fail the honest metric" $
                  rejectsMismatch substituted "rmse" 0.5 substitutedRmse half
              , testCase "the check is consistency, not quality: its own RMSE is accepted" $
                  accepts substituted "rmse" substitutedRmse half
              ]
    ]

-- ---------------------------------------------------------------------------
-- Rejections

rejectionTests :: TestTree
rejectionTests =
  testGroup
    "typed rejections"
    [ withAdmitted classOneCheckpoint $ \classification ->
        let evidence = classOneEvidence 1000 900
         in testGroup
              "classification evidence"
              [ testCase "the metric name must be test_accuracy" $ do
                  accepts classification "test_accuracy" 0.9 evidence
                  rejectsWith
                    classification
                    "rmse"
                    0.9
                    evidence
                    "classification held-out examples require test_accuracy"
              , testCase "a label at the output width is outside the runtime output" $ do
                  -- The runtime output is the 10-class semantic prefix: label 9 is
                  -- the last valid class, 10 is one past it.
                  accepts
                    classification
                    "test_accuracy"
                    0.0
                    (ServedMetric.HeldOutClassification [(blankImage, 9)])
                  rejectsWith
                    classification
                    "test_accuracy"
                    0.0
                    (ServedMetric.HeldOutClassification [(blankImage, 10)])
                    "held-out classification label lies outside the admitted runtime output"
              , testCase "a negative label is outside the runtime output" $
                  rejectsWith
                    classification
                    "test_accuracy"
                    0.0
                    (ServedMetric.HeldOutClassification [(blankImage, -1)])
                    "held-out classification label lies outside the admitted runtime output"
              , testCase "one out-of-range label rejects an otherwise honest set" $
                  rejectsWith
                    classification
                    "test_accuracy"
                    0.9
                    ( ServedMetric.HeldOutClassification
                        ( replicate 900 (blankImage, 1)
                            <> replicate 99 (blankImage, 0)
                            <> [(blankImage, 10)]
                        )
                    )
                    "held-out classification label lies outside the admitted runtime output"
              , testCase "an empty example set is rejected" $
                  rejectsWith
                    classification
                    "test_accuracy"
                    0.9
                    (ServedMetric.HeldOutClassification [])
                    "held-out classification examples are empty"
              , testCase "a non-finite reported accuracy is rejected" $
                  mapM_
                    ( \reported ->
                        rejectsWith
                          classification
                          "test_accuracy"
                          reported
                          evidence
                          "reported held-out metric is non-finite"
                    )
                    [nan, positiveInfinity, negativeInfinity]
              , testCase "an input outside the runtime's unit-image range is a typed error" $
                  rejectsWith
                    classification
                    "test_accuracy"
                    0.0
                    (ServedMetric.HeldOutClassification [(replicate 784 2.0, 1)])
                    "unit-image input values must be in [0,1]"
              , testCase "regression evidence cannot be replayed through a ten-class checkpoint" $
                  rejectsWith
                    classification
                    "rmse"
                    0.5
                    (ServedMetric.HeldOutRegression 5.0 [(blankImage, 1.0)])
                    "admitted regression output is not one finite scalar"
              ]
    , withAdmitted (constantRegressionCheckpoint 1.0) $ \regression ->
        let evidence = regressionEvidence 5.0 halfScaleTargets
         in testGroup
              "regression evidence"
              [ testCase "the metric name must be rmse" $ do
                  accepts regression "rmse" 0.5 evidence
                  rejectsWith
                    regression
                    "test_accuracy"
                    0.5
                    evidence
                    "regression held-out examples require rmse"
              , testCase "an empty example set is rejected" $
                  rejectsWith
                    regression
                    "rmse"
                    0.5
                    (ServedMetric.HeldOutRegression 5.0 [])
                    "held-out regression examples are empty"
              , testCase "a non-finite target is rejected, wherever it sits in the set" $
                  mapM_
                    ( \target ->
                        rejectsWith
                          regression
                          "rmse"
                          0.5
                          ( ServedMetric.HeldOutRegression
                              5.0
                              ( [(blankFeatures, 107.5), (blankFeatures, target)]
                                  <> [(blankFeatures, 102.5)]
                              )
                          )
                          "held-out regression target is non-finite"
                    )
                    [nan, positiveInfinity, negativeInfinity]
              , testCase "a scale that is not positive and finite is rejected" $
                  mapM_
                    ( \scale ->
                        rejectsWith
                          regression
                          "rmse"
                          0.5
                          (regressionEvidence scale halfScaleTargets)
                          "held-out regression target scale must be positive and finite"
                    )
                    [0.0, -5.0, nan, positiveInfinity, negativeInfinity]
              , testCase "an invalid scale is reported even when the set is empty" $
                  rejectsWith
                    regression
                    "rmse"
                    0.5
                    (ServedMetric.HeldOutRegression 0.0 [])
                    "held-out regression target scale must be positive and finite"
              , testCase "a non-finite reported RMSE is rejected" $
                  mapM_
                    ( \reported ->
                        rejectsWith
                          regression
                          "rmse"
                          reported
                          evidence
                          "reported held-out metric is non-finite"
                    )
                    [nan, positiveInfinity, negativeInfinity]
              , testCase "a scale so small that the squared error overflows is a typed error" $
                  -- The served output and every target are finite, but the error
                  -- divided by this scale is not, so the recomputed RMSE is not a
                  -- measurement and is refused rather than compared.
                  rejectsWith
                    regression
                    "rmse"
                    0.5
                    (regressionEvidence 1.0e-300 halfScaleTargets)
                    "admitted regression metric is non-finite"
              ]
    , withAdmitted (constantRegressionCheckpoint 1.0e308) $ \overflowing ->
        testCase "a served output that overflows is a typed error, never a measured RMSE" $
          rejectsWith
            overflowing
            "rmse"
            0.5
            (regressionEvidence 5.0 halfScaleTargets)
            "destandardized runtime output must be finite"
    ]

-- ---------------------------------------------------------------------------
-- Replay of each example's own input

-- The constant-function checkpoints above cannot tell a replay that serves every
-- example from its own input from one that reuses a single input, nor a replay
-- that pairs each prediction with its own label from one that misaligns them:
-- every example there is the same blank input and the served value never
-- changes. The checkpoints and evidence below make the served value a function
-- of the input and interleave three kinds of example, in a sequence that is not
-- its own reverse and whose neighbours differ, so a replay that reuses the first
-- input, reverses the labels or targets, or shifts them by one cannot reproduce
-- the honest metric.

-- | The three kinds of image the input-dependent classification checkpoint
-- tells apart.
data ImageKind
  = BlankImage
  | PixelZeroLit
  | PixelOneLit

-- | The class the input-dependent checkpoint serves for each kind of image.
servedClass :: ImageKind -> Int
servedClass kind =
  case kind of
    BlankImage -> 1
    PixelZeroLit -> 0
    PixelOneLit -> 2

imageOf :: ImageKind -> [Double]
imageOf kind =
  case kind of
    BlankImage -> blankImage
    PixelZeroLit -> 1.0 : replicate 783 0.0
    PixelOneLit -> 0.0 : 1.0 : replicate 782 0.0

-- | The kinds interleave with period three, so neighbouring examples differ, the
-- sequence is not its own reverse, and a shift by one changes every label.
kindAt :: Int -> ImageKind
kindAt index =
  case index `mod` 3 of
    0 -> BlankImage
    1 -> PixelZeroLit
    _ -> PixelOneLit

-- | A classification checkpoint that serves a class that depends on the image.
-- Its graph is one affine layer @logits = W x + b@ with @W@ of shape 11 by 784
-- (row-major), followed by the 11 biases. Class 1 has bias 5, so a blank image
-- serves class 1; pixel 0 feeds class 0 with weight 10 and pixel 1 feeds class 2
-- with weight 10, so an image lit at pixel 0 serves class 0 and one lit at
-- pixel 1 serves class 2. The honest-set tests below fail if this layout is not
-- the one the runtime serves.
inputDependentCheckpoint :: IO (Either Text Fixture)
inputDependentCheckpoint =
  makeFixtureForRowAndBytes mnistFixtureRow 1.0 $ \parameterCount ->
    let weight index
          | index == 0 = 10.0
          | index == 2 * 784 + 1 = 10.0
          | index == parameterCount - rawOutputWidth + 1 = 5.0
          | otherwise = 0.0
     in WeightCodec.encodeJmw1 (weight <$> [0 .. parameterCount - 1])

-- | @total@ examples of the interleaved kinds, each labelled by @label@ applied
-- to the class its own input serves and its position.
interleavedEvidence
  :: Int
  -> (Int -> Int -> Int)
  -> ServedMetric.HeldOutExamples
interleavedEvidence total label =
  ServedMetric.HeldOutClassification
    [ (imageOf kind, label index (servedClass kind))
    | index <- [0 .. total - 1]
    , let kind = kindAt index
    ]

inputDependentClassificationTests :: TestTree
inputDependentClassificationTests =
  withAdmitted inputDependentCheckpoint $ \admitted ->
    let honest = interleavedEvidence 1000 (\_ own -> own)
        -- Every label is one class off the class its own input serves.
        offByOne = interleavedEvidence 1000 (\_ own -> (own + 1) `mod` 3)
        -- The first 700 examples are labelled honestly, the last 300 are off.
        seventy =
          interleavedEvidence 1000 (\index own -> if index < 700 then own else (own + 1) `mod` 3)
     in testGroup
          "input-dependent classification replay"
          [ testCase "the served accuracy follows each example's own input" $ do
              checkpoint <- admitted
              ServedMetric.recomputeAdmittedHeldOutMetric checkpoint honest >>= (@?= Right 1.0)
          , testCase "a label that disagrees with its own input serves accuracy zero" $ do
              checkpoint <- admitted
              ServedMetric.recomputeAdmittedHeldOutMetric checkpoint offByOne >>= (@?= Right 0.0)
          , testCase "the accuracy is the exact fraction of examples whose own input serves the label" $ do
              checkpoint <- admitted
              ServedMetric.recomputeAdmittedHeldOutMetric checkpoint seventy
                >>= (@?= Right (accuracy 1000 700))
          , testCase "an honest report is accepted and an inflated one is rejected" $ do
              accepts admitted "test_accuracy" 1.0 honest
              rejectsMismatch admitted "test_accuracy" 0.9 1.0 honest
          , testCase "the mixed set is accepted at its own accuracy and rejected above it" $ do
              accepts admitted "test_accuracy" (accuracy 1000 700) seventy
              rejectsMismatch admitted "test_accuracy" 1.0 (accuracy 1000 700) seventy
          ]

-- | A regression checkpoint whose served value depends on feature 0. Hidden unit
-- 0 reads feature 0 with weight 1 and the output reads hidden unit 0 with weight
-- 1; every other weight and bias is zero. The model is @y = tanh x0@, so the
-- served value is @100 + 5 * tanh x0@, and features -100, 0, and 100 (which
-- saturate the tanh exactly) serve 95, 100, and 105. The flat layout is @W1@ (32
-- by 8, row-major), @b1@ (32), @W2@ (1 by 32), then @b2@.
featureDependentCheckpoint :: IO (Either Text Fixture)
featureDependentCheckpoint =
  makeFixtureForRowAndBytes californiaFixtureRow 0.5 $ \parameterCount ->
    let outputWeightBase = 32 * 8 + 32
        weight index
          | index == 0 || index == outputWeightBase = 1.0
          | otherwise = 0.0 :: Double
     in WeightCodec.encodeJmw1 (weight <$> [0 .. parameterCount - 1])

-- | The value feature 0 takes for each kind of example and the value the
-- checkpoint serves for it.
featureAt :: Int -> (Double, Double)
featureAt index =
  case index `mod` 3 of
    0 -> (-100.0, 95.0)
    1 -> (0.0, 100.0)
    _ -> (100.0, 105.0)

-- | How far each kind's served value lies above its target, in raw units. The
-- offsets 2.5, 0, and -5 are standardized errors of exactly 0.5, 0, and -1 at the
-- checkpoint's scale of 5. They are not symmetric, so neither the order of the
-- targets nor the pairing of features with targets can change unnoticed, and
-- every squared error is an exact binary fraction.
targetOffsetAt :: Int -> Double
targetOffsetAt index =
  case index `mod` 3 of
    0 -> 2.5
    1 -> 0.0
    _ -> -5.0

-- | @total@ examples whose feature 0 and target follow the kinds above, with
-- the target built from the served value and the offset.
featureEvidence
  :: Int
  -> (Int -> (Double, Double))
  -> ServedMetric.HeldOutExamples
featureEvidence total featureFor =
  ServedMetric.HeldOutRegression
    5.0
    [ (feature : replicate 7 0.0, servedValue - targetOffsetAt index)
    | index <- [0 .. total - 1]
    , let (feature, servedValue) = featureFor index
    ]

featureDependentRegressionTests :: TestTree
featureDependentRegressionTests =
  withAdmitted featureDependentCheckpoint $ \admitted ->
    let honest = featureEvidence 1000 featureAt
        -- 334 examples at standardized error 0.5, 333 at 0, and 333 at -1. Every
        -- squared error is exact, so the RMSE is exactly this value.
        honestRmse = sqrt ((334 * 0.25 + 333 * 0.0 + 333 * 1.0) / 1000.0) :: Double
        -- The same targets with every feature blank: the checkpoint serves 100
        -- for all of them, so the errors are 1.5, 0, and -2.
        blank = featureEvidence 1000 (\index -> (0.0, snd (featureAt index)))
        blankRmse = sqrt ((334 * 2.25 + 333 * 0.0 + 333 * 4.0) / 1000.0) :: Double
     in testGroup
          "feature-dependent regression replay"
          [ testCase "the served RMSE follows each example's own features" $ do
              checkpoint <- admitted
              ServedMetric.recomputeAdmittedHeldOutMetric checkpoint honest >>= (@?= Right honestRmse)
          , testCase "the same targets over blank features are graded against a constant served value" $ do
              checkpoint <- admitted
              ServedMetric.recomputeAdmittedHeldOutMetric checkpoint blank >>= (@?= Right blankRmse)
          , testCase "an honest report is accepted and one from another replay is rejected" $ do
              accepts admitted "rmse" honestRmse honest
              rejectsMismatch admitted "rmse" blankRmse honestRmse honest
              rejectsMismatch admitted "rmse" honestRmse blankRmse blank
          ]

-- ---------------------------------------------------------------------------
-- Publisher wiring

-- | The post-admission branch of the supervised publisher, extracted as
-- 'ProductPublisher.verifyAdmittedSupervisedServedMetric', and the evaluation
-- example count check that precedes the checkpoint write.
publisherWiringTests :: TestTree
publisherWiringTests =
  testGroup
    "supervised publisher wiring"
    [ withAdmitted classOneCheckpoint $ \admittedIO ->
        let evidence = classOneEvidence 1000 900
            projectionFor = do
              row <-
                maybe
                  (assertFailure "missing mnist-shallow-mlp ProductRow")
                  pure
                  (lookupRow "mnist-shallow-mlp")
              expectRight (authoritativeSupervisedProjection Substrate.LinuxCPU row)
         in testGroup
              "post-admission served-metric gate"
              [ testCase "a reported metric equal to the served one makes the row eligible" $ do
                  admitted <- admittedIO
                  projection <- projectionFor
                  result <-
                    ProductPublisher.verifyAdmittedSupervisedServedMetric
                      projection
                      admitted
                      ("test_accuracy", 0.9)
                      evidence
                  disposition result @?= Eligible
                  case ProductPublisher.productPublishDisposition result of
                    ProductPublisher.ProductPublishEligible carried ->
                      assertBool "the eligible result carries the admitted checkpoint" (carried == admitted)
                    ProductPublisher.ProductPublishUnsupported _ -> assertFailure "the row was reported unsupported"
                    ProductPublisher.ProductPublishError _ -> assertFailure "the row was reported as an error"
                  ProductPublisher.productPublishRowId result @?= "mnist-shallow-mlp"
                  ProductPublisher.productPublishExperimentHash result
                    @?= ProductMatrix.productProjectionExperimentHash projection
                  ProductPublisher.productPublishArtifacts result @?= []
                  ProductPublisher.productPublishMessage result
                    @?= "supervised V2 runtime artifact stored, admitted, and held-out metric recomputed from served bytes"
              , testCase "a mismatch is rejected with the served-versus-reported diagnostic" $ do
                  admitted <- admittedIO
                  projection <- projectionFor
                  result <-
                    ProductPublisher.verifyAdmittedSupervisedServedMetric
                      projection
                      admitted
                      ("test_accuracy", 0.95)
                      evidence
                  let manifestSha =
                        CheckpointStore.admittedCheckpointManifestSha
                          (CheckpointStore.admittedCompletedCheckpoint admitted)
                      expected =
                        "supervised held-out metric failed exact admitted served-byte verification: "
                          <> "reported test_accuracy does not match exact admitted served bytes (manifest="
                          <> manifestSha
                          <> ", reported=0.95, served=0.9)"
                  disposition result @?= Rejected expected
                  ProductPublisher.productPublishMessage result @?= expected
              , testCase "the rejected row is not eligible and carries no artifacts" $ do
                  admitted <- admittedIO
                  projection <- projectionFor
                  result <-
                    ProductPublisher.verifyAdmittedSupervisedServedMetric
                      projection
                      admitted
                      ("test_accuracy", 0.95)
                      evidence
                  assertBool "a rejected row must not be eligible" (not (isEligible result))
                  ProductPublisher.productPublishArtifacts result @?= []
                  ProductPublisher.productPublishRowId result @?= "mnist-shallow-mlp"
                  ProductPublisher.productPublishExperimentHash result
                    @?= ProductMatrix.productProjectionExperimentHash projection
              , testCase "a wrong metric name is rejected by the same gate" $ do
                  admitted <- admittedIO
                  projection <- projectionFor
                  result <-
                    ProductPublisher.verifyAdmittedSupervisedServedMetric
                      projection
                      admitted
                      ("rmse", 0.9)
                      evidence
                  disposition result
                    @?= Rejected
                      "supervised held-out metric failed exact admitted served-byte verification: classification held-out examples require test_accuracy"
              ]
    , testGroup
        "evaluation example count"
        [ testCase "every canonical supervised row is planned with exactly 1000 evaluation examples" $ do
            -- 1000 is the size at which the accuracy allowance is one class
            -- decision (0.001), so the documented tolerance is the one that
            -- applies to every row the publisher can serve-check.
            planned <-
              traverse
                ( \row -> do
                    projection <-
                      expectRight (authoritativeSupervisedProjection Substrate.LinuxCPU row)
                    pure
                      ( ProductMatrix.rowId row
                      , ProductMatrix.supervisedEvaluationExamples
                          (ProductMatrix.productProjectionDescriptor projection)
                      )
                )
                [ row
                | row <- ProductMatrix.allProductRows
                , ProductMatrix.family row == ProductMatrix.Supervised
                ]
            length planned @?= 11
            filter ((/= 1000) . snd) planned @?= []
        , testCase "the fixture's held-out evidence is the size of the plan it is checked against" $
            plannedEvaluationExamples >>= (@?= 1000)
        , testCase "an evidence set of exactly the plan's size is accepted" $
            ProductPublisher.validateSupervisedServedMetricExampleCount
              1000
              (classOneEvidence 1000 900)
              @?= Right ()
        , testCase "one example fewer or more than the plan is rejected with both counts" $ do
            ProductPublisher.validateSupervisedServedMetricExampleCount
              1000
              (classOneEvidence 999 900)
              @?= Left "supervised exact served-metric evaluation examples mismatch: projected 1000, resolved 999"
            ProductPublisher.validateSupervisedServedMetricExampleCount
              1000
              (classOneEvidence 1001 900)
              @?= Left "supervised exact served-metric evaluation examples mismatch: projected 1000, resolved 1001"
        , testCase "regression evidence is counted the same way" $ do
            ProductPublisher.validateSupervisedServedMetricExampleCount
              1000
              (regressionEvidence 5.0 halfScaleTargets)
              @?= Right ()
            ProductPublisher.validateSupervisedServedMetricExampleCount
              1000
              (regressionEvidence 5.0 (take 999 halfScaleTargets))
              @?= Left "supervised exact served-metric evaluation examples mismatch: projected 1000, resolved 999"
        , testCase "an empty evidence set never matches a positive plan" $
            ProductPublisher.validateSupervisedServedMetricExampleCount
              1000
              (ServedMetric.HeldOutClassification [])
              @?= Left "supervised exact served-metric evaluation examples mismatch: projected 1000, resolved 0"
        ]
    , publisherBoundaryTests
    , postAdmissionBoundaryTests
    ]

-- | The disposition without the admitted checkpoint an eligible result
-- carries, so a failing comparison prints a line rather than a whole manifest
-- and weight tensor.
data Disposition
  = Eligible
  | Unsupported Text
  | Rejected Text
  deriving stock (Eq, Show)

disposition :: ProductPublisher.ProductPublishResult -> Disposition
disposition result =
  case ProductPublisher.productPublishDisposition result of
    ProductPublisher.ProductPublishEligible _ -> Eligible
    ProductPublisher.ProductPublishUnsupported reason -> Unsupported reason
    ProductPublisher.ProductPublishError reason -> Rejected reason

isEligible :: ProductPublisher.ProductPublishResult -> Bool
isEligible result =
  case ProductPublisher.productPublishDisposition result of
    ProductPublisher.ProductPublishEligible _ -> True
    ProductPublisher.ProductPublishUnsupported _ -> False
    ProductPublisher.ProductPublishError _ -> False

lookupRow :: Text -> Maybe (ProductMatrix.ProductRow 'ProductMatrix.Declared)
lookupRow name =
  case filter ((== name) . ProductMatrix.rowId) ProductMatrix.allProductRows of
    row : _ -> Just row
    [] -> Nothing

plannedEvaluationExamples :: IO Int
plannedEvaluationExamples = do
  (_, _, metrics, _, _) <- expectRight makeTrainingCompletionFixture
  case ProductPublisher.supervisedPublishHeldOutExamples (supervisedPublishRunFixture metrics) of
    ServedMetric.HeldOutClassification examples -> pure (length examples)
    ServedMetric.HeldOutRegression _ examples -> pure (length examples)

-- | What the row boundary did with a substituted training run.
data BoundaryOutcome
  = -- | Every validation passed, the checkpoint was written, admitted, and the
    -- row was eligible: the command returned normally.
    RowPublished
  | -- | The row was rejected and the command exited non-zero.
    RowRejected
  | -- | Every validation before the write passed and the run reached the
    -- (forbidden, stubbed) completion callback.
    ReachedCompletionCallback
  | Unexpected String
  deriving stock (Eq, Show)

-- | Run the real row boundary over @runtime@ with the checkpoint cache rooted
-- in @cacheRoot@, so a run can never touch the developer's own cache.
runBoundary :: FilePath -> ProductPublisher.ProductPublisherRuntime -> IO BoundaryOutcome
runBoundary cacheRoot runtime = do
  row <-
    maybe
      (assertFailure "missing mnist-shallow-mlp ProductRow")
      pure
      (lookupRow "mnist-shallow-mlp")
  cacheDir <- either (assertFailure . show) pure (parseAbsDir cacheRoot)
  env <- (\base -> base {envCacheDir = cacheDir}) <$> buildEnv defaultGlobalFlags
  outcome <-
    ( try
        ( runReaderT
            ( ProductPublisher.runTrainAndPublishProductRows
                runtime
                Substrate.LinuxCPU
                [row]
            )
            env
        )
        :: IO (Either SomeException ())
    )
  pure $
    case outcome of
      Right () -> RowPublished
      Left exception
        | Just (ExitFailure _) <- fromException exception -> RowRejected
        | Just ExitSuccess <- fromException exception -> Unexpected "exited successfully"
        | "substituted supervised row invoked the supervised completion callback"
            `isInfixOf` show exception ->
            ReachedCompletionCallback
        | otherwise -> Unexpected (show exception)

-- | The count check runs through the real row boundary, before the completion
-- and write callbacks, so a mismatch never reaches Store. The untouched run is
-- the control: it passes every pre-write validation and stops at the stubbed
-- completion callback, which proves the substituted runs are rejected by the
-- example count and not by some unrelated defect of the shared fixture.
publisherBoundaryTests :: TestTree
publisherBoundaryTests =
  testGroup
    "row boundary (pre-write)"
    [ testCase "the control run passes validation and reaches the completion callback" $
        withBoundary $ \boundary -> do
          (_, _, metrics, _, _) <- expectRight makeTrainingCompletionFixture
          boundary (substitutedSupervisedPublisherRuntime (supervisedPublishRunFixture metrics))
            >>= (@?= ReachedCompletionCallback)
    , testCase "a held-out set one example short of the plan is rejected before completion" $
        withBoundary $ \boundary -> do
          (_, _, metrics, _, _) <- expectRight makeTrainingCompletionFixture
          let control = supervisedPublishRunFixture metrics
          case ProductPublisher.supervisedPublishHeldOutExamples control of
            ServedMetric.HeldOutClassification examples ->
              boundary
                ( substitutedSupervisedPublisherRuntime
                    control
                      { ProductPublisher.supervisedPublishHeldOutExamples =
                          ServedMetric.HeldOutClassification (take (length examples - 1) examples)
                      }
                )
                >>= (@?= RowRejected)
            ServedMetric.HeldOutRegression _ _ ->
              assertFailure "the mnist fixture carries classification evidence"
    , testCase "a held-out set one example over the plan is rejected before completion" $
        withBoundary $ \boundary -> do
          (_, _, metrics, _, _) <- expectRight makeTrainingCompletionFixture
          let control = supervisedPublishRunFixture metrics
          case ProductPublisher.supervisedPublishHeldOutExamples control of
            ServedMetric.HeldOutClassification examples ->
              boundary
                ( substitutedSupervisedPublisherRuntime
                    control
                      { ProductPublisher.supervisedPublishHeldOutExamples =
                          ServedMetric.HeldOutClassification (take 1 examples <> examples)
                      }
                )
                >>= (@?= RowRejected)
            ServedMetric.HeldOutRegression _ _ ->
              assertFailure "the mnist fixture carries classification evidence"
    , testCase "a run without a held-out metric is rejected before completion" $
        withBoundary $ \boundary -> do
          (_, _, metrics, _, _) <- expectRight makeTrainingCompletionFixture
          boundary
            ( substitutedSupervisedPublisherRuntime
                (supervisedPublishRunFixture metrics)
                  { ProductPublisher.supervisedPublishHeldOutMetric = Nothing
                  }
            )
            >>= (@?= RowRejected)
    ]

withBoundary :: ((ProductPublisher.ProductPublisherRuntime -> IO BoundaryOutcome) -> IO a) -> IO a
withBoundary action =
  withSystemTempDirectory "jitml-served-boundary" $ \root -> action (runBoundary root)

-- | The real supervised publisher over the real local Store, with only training
-- substituted: completion, the checkpoint writer's snapshot builder, Store
-- write, and Store admission are the production functions, rooted in the
-- private cache directory of the run. (The production writer also mirrors to a
-- live cluster when one is published, so its snapshot builder is used directly
-- instead of the writer, keeping the case hermetic.)
storeBackedRuntime
  :: ProductPublisher.SupervisedPublishRun
  -> ProductPublisher.ProductPublisherRuntime
storeBackedRuntime run =
  (substitutedSupervisedPublisherRuntime run)
    { ProductPublisher.publisherCompleteSupervisedProductRowWithWeightHashes =
        ProductCompletion.completedTrainingForProductRowWithWeightHashes
    , ProductPublisher.publisherWriteCompletedSupervisedCheckpoint =
        \completed experimentHash metrics artifact -> do
          (manifest, payloads) <-
            either
              (liftIO . assertFailure . Text.unpack)
              pure
              ( CheckpointWriter.buildCompletedSupervisedCheckpointSnapshot
                  completed
                  experimentHash
                  metrics
                  artifact
              )
          root <- CheckpointWriter.localCheckpointRoot
          written <-
            liftIO
              (CheckpointStore.writeCompletedCheckpointSnapshot root completed manifest payloads Nothing)
          liftIO (expectRight written)
    , ProductPublisher.publisherAdmitCompletedCheckpoint =
        CheckpointWriter.admitLocalStoredCompletedCheckpoint
    }

-- | The post-admission gate reached through the real publisher. The reported
-- metric is the only difference between the two runs: an honest report makes
-- the row eligible and the command returns; the same run reporting a metric its
-- own admitted bytes do not serve is rejected, so nothing but the served-byte
-- check can be what stopped it (the reported value still clears the bar and
-- agrees with the completion that was written). The rejected checkpoint stays
-- in Store because the gate runs after admission.
postAdmissionBoundaryTests :: TestTree
postAdmissionBoundaryTests =
  testGroup
    "row boundary (post-admission, real local Store)"
    [ testCase "an honest reported metric publishes the row" $
        withSystemTempDirectory "jitml-served-e2e" $ \root -> do
          (_, _, metrics, _, _) <- expectRight makeTrainingCompletionFixture
          runBoundary root (storeBackedRuntime (supervisedPublishRunFixture metrics))
            >>= (@?= RowPublished)
    , testCase "a reported metric the admitted bytes do not serve rejects the row" $
        withSystemTempDirectory "jitml-served-e2e" $ \root -> do
          (_, _, metrics, _, _) <- expectRight makeTrainingCompletionFixture
          let honest = supervisedPublishRunFixture metrics
          metricName <-
            maybe
              (assertFailure "the fixture reports no held-out metric")
              (pure . fst)
              (ProductPublisher.supervisedPublishHeldOutMetric honest)
          runBoundary
            root
            ( storeBackedRuntime
                honest
                  { ProductPublisher.supervisedPublishHeldOutMetric = Just (metricName, 0.95)
                  }
            )
            >>= (@?= RowRejected)
    , testCase "the rejected checkpoint remains admissible in Store" $
        withSystemTempDirectory "jitml-served-e2e" $ \root -> do
          (_, _, metrics, _, _) <- expectRight makeTrainingCompletionFixture
          let honest = supervisedPublishRunFixture metrics
          metricName <-
            maybe
              (assertFailure "the fixture reports no held-out metric")
              (pure . fst)
              (ProductPublisher.supervisedPublishHeldOutMetric honest)
          row <-
            maybe
              (assertFailure "missing mnist-shallow-mlp ProductRow")
              pure
              (lookupRow "mnist-shallow-mlp")
          projection <- expectRight (authoritativeSupervisedProjection Substrate.LinuxCPU row)
          outcome <-
            runBoundary
              root
              ( storeBackedRuntime
                  honest
                    { ProductPublisher.supervisedPublishHeldOutMetric = Just (metricName, 0.95)
                    }
              )
          outcome @?= RowRejected
          -- The gate denied the row its eligibility; it did not unwrite the
          -- checkpoint it had just admitted.
          readmitted <-
            CheckpointStore.admitLocalLatestCheckpoint
              (root </> "checkpoints")
              (ProductMatrix.productProjectionExperimentHash projection)
          case readmitted of
            Left err -> assertFailure ("the rejected checkpoint left Store: " <> show err)
            Right _ -> pure ()
    ]
