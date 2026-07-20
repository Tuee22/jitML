module RegressionStandardization
  ( regressionStandardizationTests
  )
where

import Data.Either (isLeft)
import Data.Vector.Unboxed qualified as VU
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

import JitML.SL.Classifier qualified as Classifier
import JitML.SL.Regression qualified as Regression
import JitML.SL.RuntimeArtifact qualified as RuntimeArtifact
import JitML.SL.TrainingExecution qualified as TrainingExecution

regressionStandardizationTests :: TestTree
regressionStandardizationTests =
  testGroup
    "regression standardization"
    [ testCase "fits statistics from the supplied training partition only" $ do
        standardization <-
          either
            (fail . show)
            pure
            (Regression.fitRegressionStandardization trainingRows)
        Regression.regressionFeatureMeans standardization @?= [1.0, 12.0]
        Regression.regressionFeatureScales standardization @?= [1.0, 2.0]
        Regression.regressionTargetMean standardization @?= 12.0
        Regression.regressionTargetScale standardization @?= 2.0
        heldOut <-
          either
            (fail . show)
            pure
            (Regression.applyRegressionStandardization standardization heldOutRow)
        Regression.regressionFeatures heldOut @?= VU.fromList [999.0, 494.0]
        Regression.regressionTarget heldOut @?= 494.0
    , testCase "training partition transforms to zero mean" $ do
        standardization <-
          either
            (fail . show)
            pure
            (Regression.fitRegressionStandardization trainingRows)
        transformed <-
          either
            (fail . show)
            pure
            (Regression.applyRegressionStandardizationDataset standardization trainingRows)
        fmap (VU.toList . Regression.regressionFeatures) transformed
          @?= [[-1.0, -1.0], [1.0, 1.0]]
        fmap Regression.regressionTarget transformed @?= [-1.0, 1.0]
    , testCase "constant columns use scale one and inverse target restores units" $ do
        let rows = [row [3.0] 7.0, row [3.0] 7.0]
        standardization <-
          either
            (fail . show)
            pure
            (Regression.fitRegressionStandardization rows)
        Regression.regressionFeatureScales standardization @?= [1.0]
        Regression.regressionTargetScale standardization @?= 1.0
        Regression.inverseRegressionTarget standardization 2.5 @?= Right 9.5
    , testCase "rejects inconsistent widths" $
        assertBool
          "heterogeneous feature widths must fail"
          (isLeft (Regression.fitRegressionStandardization [row [1.0] 0.0, row [1.0, 2.0] 1.0]))
    , testCase "rejects non-finite rows and inverse values" $ do
        assertBool
          "NaN training input must fail"
          (isLeft (Regression.fitRegressionStandardization [row [0 / 0] 1.0]))
        standardization <-
          either
            (fail . show)
            pure
            (Regression.fitRegressionStandardization trainingRows)
        assertBool
          "infinite decoded input must fail"
          (isLeft (Regression.inverseRegressionTarget standardization (1 / 0)))
    , testCase "CIFAR-10 RGB statistics are deterministic, train-only, and full-width" $ do
        let trainingSet =
              [ cifarExample 0 [0.0, 0.25, 0.5]
              , cifarExample 1 [1.0, 0.75, 1.0]
              ]
            heldOut = cifarExample 2 [0.25, 0.5, 0.75]
        transform <-
          either
            (fail . show)
            pure
            (TrainingExecution.fitCifar10RgbInputTransform trainingSet)
        TrainingExecution.fitCifar10RgbInputTransform trainingSet @?= Right transform
        case transform of
          RuntimeArtifact.RawStandardizeInput means scales -> do
            length means @?= 3072
            length scales @?= 3072
            take 6 means @?= [0.5, 0.5, 0.75, 0.5, 0.5, 0.75]
            take 6 scales @?= [0.5, 0.25, 0.25, 0.5, 0.25, 0.25]
            assertBool "every fitted CIFAR-10 scale is positive" (all (> 0.0) scales)
          _ -> fail "CIFAR-10 fit returned a non-standardizing transform"
        leakedTransform <-
          either
            (fail . show)
            pure
            (TrainingExecution.fitCifar10RgbInputTransform (trainingSet <> [heldOut]))
        assertBool
          "held-out data would change the fit and therefore must not enter it"
          (leakedTransform /= transform)
        transformed <-
          either
            (fail . show)
            pure
            (TrainingExecution.applyCifar10RgbInputTransform transform (trainingSet <> [heldOut]))
        fmap (VU.take 3 . Classifier.exampleFeatures) transformed
          @?= fmap VU.fromList [[-1.0, -1.0, -1.0], [1.0, 1.0, 1.0], [-0.5, 0.0, 0.0]]
        Classifier.exampleFeatures heldOut
          @?= Classifier.exampleFeatures (cifarExample 2 [0.25, 0.5, 0.75])
    , testCase "CIFAR-10 RGB fitting rejects malformed decoded inputs and zero scales" $ do
        assertBool
          "empty training partition must fail"
          (isLeft (TrainingExecution.fitCifar10RgbInputTransform []))
        assertBool
          "wrong image width must fail"
          ( isLeft
              ( TrainingExecution.fitCifar10RgbInputTransform
                  [Classifier.LabeledExample (VU.fromList [0.0, 0.5, 1.0]) 0]
              )
          )
        assertBool
          "non-finite image input must fail"
          ( isLeft
              ( TrainingExecution.fitCifar10RgbInputTransform
                  [cifarExample 0 [0 / 0, 0.5, 1.0]]
              )
          )
        assertBool
          "out-of-unit-range image input must fail"
          ( isLeft
              ( TrainingExecution.fitCifar10RgbInputTransform
                  [cifarExample 0 [-0.01, 0.5, 1.0]]
              )
          )
        assertBool
          "constant channels cannot produce a positive fitted scale"
          ( isLeft
              ( TrainingExecution.fitCifar10RgbInputTransform
                  [cifarExample 0 [0.25, 0.5, 0.75]]
              )
          )
    , testCase "CIFAR-10 RGB application rejects malformed transforms and held-out inputs" $ do
        let example = cifarExample 0 [0.25, 0.5, 0.75]
            validMeans = concat (replicate 1024 [0.5, 0.5, 0.5])
            validScales = concat (replicate 1024 [0.25, 0.25, 0.25])
            apply = TrainingExecution.applyCifar10RgbInputTransform
        assertBool
          "identity input is not a fitted CIFAR transform"
          (isLeft (apply (RuntimeArtifact.RawIdentityInput 3072) [example]))
        assertBool
          "short means must fail"
          ( isLeft
              ( apply
                  (RuntimeArtifact.RawStandardizeInput (replicate 3071 0.5) validScales)
                  [example]
              )
          )
        assertBool
          "short scales must fail"
          ( isLeft
              ( apply
                  (RuntimeArtifact.RawStandardizeInput validMeans (replicate 3071 0.25))
                  [example]
              )
          )
        assertBool
          "non-finite means must fail"
          ( isLeft
              ( apply
                  ( RuntimeArtifact.RawStandardizeInput
                      ((0 / 0) : replicate 3071 0.5)
                      validScales
                  )
                  [example]
              )
          )
        assertBool
          "non-positive scales must fail"
          ( isLeft
              ( apply
                  ( RuntimeArtifact.RawStandardizeInput
                      validMeans
                      (0.0 : replicate 3071 0.25)
                  )
                  [example]
              )
          )
        assertBool
          "malformed held-out width must fail"
          ( isLeft
              ( apply
                  (RuntimeArtifact.RawStandardizeInput validMeans validScales)
                  [Classifier.LabeledExample (VU.fromList [0.0, 0.5, 1.0]) 0]
              )
          )
        assertBool
          "held-out values outside decoded unit range must fail"
          ( isLeft
              ( apply
                  (RuntimeArtifact.RawStandardizeInput validMeans validScales)
                  [cifarExample 0 [1.01, 0.5, 0.75]]
              )
          )
    ]

trainingRows :: [Regression.RegressionExample]
trainingRows =
  [ row [0.0, 10.0] 10.0
  , row [2.0, 14.0] 14.0
  ]

heldOutRow :: Regression.RegressionExample
heldOutRow = row [1000.0, 1000.0] 1000.0

row :: [Double] -> Double -> Regression.RegressionExample
row features target =
  Regression.RegressionExample
    { Regression.regressionFeatures = VU.fromList features
    , Regression.regressionTarget = target
    }

cifarExample :: Int -> [Double] -> Classifier.LabeledExample
cifarExample label rgb =
  Classifier.LabeledExample
    { Classifier.exampleFeatures =
        VU.fromList (concat (replicate 1024 rgb))
    , Classifier.exampleLabel = label
    }
