{-# LANGUAGE OverloadedStrings #-}

-- | The standing negative-control suite for the validated-plan and evidence
-- contract.
--
-- The audit's root-cause finding was that "Done" was graded by self-authored,
-- self-referential gates. A negative control inverts that: it commits a
-- KNOWN-INVALID artifact and asserts the production gate __rejects it for the
-- right reason__. A gate that cannot reject its known-invalid input is not a
-- gate — the build fails; a gate that rejects it for a different reason is
-- not the guard the control names — the build fails.
-- See the current external-truth obligations in the development-plan Exit
-- Definition and Phases 277, 280, and 281.
--
-- The suite is organised by pipeline stage ('ControlCategory'):
--
-- * 'Gate' ('gateSoundnessControls') — pure gate logic (`RowAssertions`,
--   `ExternalBars`, codegen text) against hand-built known-fakes;
-- * 'Request' ("JitML.Test.NegativeControls.Request") — raw requests driven
--   through plan refinement;
-- * 'Event' ("JitML.Test.NegativeControls.Event") — event streams driven
--   through the contract reducers;
-- * 'Journal' ("JitML.Test.NegativeControls.Journal") — storage/completion
--   journals driven through Store admission and journal refinement;
-- * 'Lifecycle' ("JitML.Test.NegativeControls.Lifecycle") — the live
--   interpreter's settlement, timeout, cleanup, and terminal ordering, driven
--   through scripted scenarios;
-- * 'PerRow' ("JitML.Test.NegativeControls.PerRow") — three controls for every
--   product workflow row, derived from the registry.
--
-- Every category is populated, so 'deferredCategories' and
-- 'pendingProductionControls' are empty and the suite carries no pass-on-pending
-- sentinel.
--
-- Pure controls stay pure; controls that need the file system or a workflow
-- interpreter use the explicit effectful constructor
-- ('JitML.Test.NegativeControls.Core.effectfulControl').
module JitML.Test.NegativeControls
  ( ControlCategory (..)
  , ControlCheck (..)
  , ControlOutcome (..)
  , NegativeControl (..)
  , allControlCategories
  , allNegativeControls
  , allNegativeControlsWith
  , categoryCoverageFailures
  , controlFailure
  , controlTestCase
  , controlsInCategory
  , deferredCategories
  , duplicateControlNames
  , eventControls
  , gateSoundnessControls
  , journalControls
  , lifecycleControls
  , pendingProductionControls
  , perRowControls
  , renderControlCategory
  , requestControls
  , runControl
  , runNegativeControls
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU

import JitML.Cache.Key qualified as Cache
import JitML.Codegen.Cuda qualified as CudaCodegen
import JitML.Codegen.KernelFamily (KernelFamily (..))
import JitML.Codegen.Metal qualified as MetalCodegen
import JitML.Codegen.SourceFile (SourceFile (..))
import JitML.Numerics.LayerGraph qualified as LayerGraph
import JitML.Product.Convergence qualified as Convergence
import JitML.Product.ExternalBars qualified as ExternalBars
import JitML.RL.Algorithms.ContinuousTrainer qualified as ContinuousTrainer
import JitML.RL.Algorithms.CrossQLoss qualified as CrossQLoss
import JitML.RL.ConvergenceThresholds qualified as RLConvergence
import JitML.Test.NegativeControls.Core
import JitML.Test.NegativeControls.Event (eventControls)
import JitML.Test.NegativeControls.Journal (journalControls)
import JitML.Test.NegativeControls.Lifecycle (lifecycleControls)
import JitML.Test.NegativeControls.Pending (pendingProductionControls)
import JitML.Test.NegativeControls.PerRow (PerRowFixture, buildPerRowFixture, perRowControls)
import JitML.Test.NegativeControls.Request (requestControls)
import JitML.Test.RowAssertions qualified as RowAssertions
import JitML.Training.Budget (MetricGoal (..))

-- | Every committed control, in category order: the list the standing stanza
-- runs, and the list the registration guards read ('realRowRegistryFacts',
-- 'lifecycleCommitmentFailures'), so a control dropped from it is reported
-- instead of vanishing silently.  A per-row foreign-admission control that is
-- run through this list builds its own Store-admitted fixture; the standing
-- stanza shares one through 'allNegativeControlsWith'.
allNegativeControls :: [NegativeControl]
allNegativeControls = allNegativeControlsWith buildPerRowFixture

-- | Every committed control, with the per-row controls reading their shared
-- Store-admitted fixture through the given action.  Enumerating the controls
-- (their names and categories) never runs the action.
allNegativeControlsWith :: IO PerRowFixture -> [NegativeControl]
allNegativeControlsWith perRowFixture =
  gateSoundnessControls
    <> requestControls
    <> eventControls
    <> journalControls
    <> lifecycleControls
    <> perRowControls perRowFixture

controlsInCategory :: ControlCategory -> [NegativeControl] -> [NegativeControl]
controlsInCategory category = filter ((== category) . ncCategory)

-- | Categories whose controls are owned by a later phase.  The coverage guard
-- ('categoryCoverageFailures') requires every category NOT listed here to have
-- at least one control, and flags a listed category that already has some, so
-- an owner cannot land controls without un-deferring the category (or the
-- reverse).  Every category is populated, so nothing is deferred.
deferredCategories :: [ControlCategory]
deferredCategories = []

-- | The pure gate-soundness controls.  Each asserts the specific failure the
-- gate must report, so a gate that rejects a fake for an unrelated reason is
-- reported as such instead of passing.
--
-- Controls 6-12 encode a property of a production surface (a Conv2D that is
-- not a Dense affine, an adaptive SAC temperature, ...) as a failure list
-- that is non-empty exactly when the property holds; the expected message
-- names the property.
gateSoundnessControls :: [NegativeControl]
gateSoundnessControls =
  [ gate
      "untrained-learned-state"
      "an init == final parameter hash (no weight movement) must be rejected"
      ["final parameter hash equals initial parameter hash"]
      (RowAssertions.assertLearnedStateChanged untrainedLearnedState)
  , gate
      "self-referential-convergence-bar"
      "a slack-0 bar built from the measured value (value >= value) must be rejected"
      ["has non-positive slack"]
      (ExternalBars.assertProductBarExternal selfReferentialBar selfReferentialMeasured)
  , gate
      "synthetic-rl-transition"
      "RL row evidence flagged as synthetic-transition must be rejected"
      ["synthetic-transition evidence is not valid product evidence"]
      (RowAssertions.assertRlRowEvidence syntheticRlEvidence)
  , gate
      "below-threshold-supervised"
      "an SL test metric below (threshold - slack) must fail convergence"
      ["test_accuracy failed convergence"]
      (RowAssertions.assertSupervisedRowEvidence belowThresholdSl)
  , gate
      "untrained-supervised-weights"
      "an SL init == final weight hash (no weight movement) must be rejected"
      ["final weight hash equals initial weight hash"]
      (RowAssertions.assertSupervisedRowEvidence untrainedSl)
  , gate
      "conv2d-not-dense"
      "a Conv2D node must not collapse to a Dense node with the same parameters"
      ["Conv2D output differs from a Dense affine"]
      conv2dNotDenseFailures
  , gate
      "sac-alpha-adaptive"
      "SAC evidence must reject a fixed-temperature actor-critic update"
      ["SAC temperature changed from the fixed initial alpha"]
      sacAlphaAdaptiveFailures
  , gate
      "tqc-drop-enabled"
      "TQC evidence must reject the drop=0 scalar-critic stand-in"
      ["TQC default drops top quantile atoms"]
      tqcDropEnabledFailures
  , gate
      "crossq-renorm-not-identity"
      "CrossQ evidence must reject identity batch-renormalization"
      ["CrossQ batch renormalization changes non-normalized Q values"]
      crossQRenormFailures
  , gate
      "alphazero-all-draw-rejected"
      "AlphaZero arena evidence must reject an all-draw 0.5 win-rate artifact"
      ["AlphaZero all-draw arena result is below the strict win-margin bar"]
      alphaZeroAllDrawFailures
  , gate
      "cuda-windowed-conv-rendered"
      "CUDA Conv2D/Conv3D evidence must reject scalar 1x1 cuDNN source"
      [ "CUDA Conv2D uses a 3x3 cuDNN filter and padded/cropped spatial tensors"
      , "CUDA Conv3D uses a 3x3x3 cuDNN filter and padded/cropped spatial tensors"
      ]
      cudaWindowedConvFailures
  , gate
      "metal-windowed-conv-rendered"
      "Metal Conv2D/Conv3D evidence must reject scalar 1x1 weighted source"
      [ "Metal Conv2D weighted source has only windowed 3x3 convolution"
      , "Metal Conv3D weighted source has only windowed 3x3x3 convolution"
      ]
      metalWindowedConvFailures
  ]
 where
  gate name description expectedFragments failures =
    pureControl Gate name description (gateRejected expectedFragments failures)

-- Known-fake fixtures -------------------------------------------------------

untrainedLearnedState :: RowAssertions.LearnedStateEvidence
untrainedLearnedState =
  RowAssertions.LearnedStateEvidence
    { RowAssertions.lseRowId = "negcontrol-untrained"
    , RowAssertions.lseInitialParamHash = "identical-hash"
    , RowAssertions.lseFinalParamHash = "identical-hash"
    , RowAssertions.lseUpdateCount = 10
    }

selfReferentialMeasured :: Double
selfReferentialMeasured = 0.42

-- | Exactly how the production path built its bar: target = measured value,
-- slack = 0 (see @convergenceObservationsForMetrics@ in
-- @JitML.Product.Completion@).
selfReferentialBar :: Convergence.ConvergenceBar
selfReferentialBar =
  Convergence.mkConvergenceBar "test_accuracy" MetricMaximise selfReferentialMeasured 0.0

syntheticRlEvidence :: RowAssertions.RlRowEvidence
syntheticRlEvidence =
  RowAssertions.RlRowEvidence
    { RowAssertions.rleRowId = "PPO/cartpole"
    , RowAssertions.rleAlgorithm = "PPO"
    , RowAssertions.rleEnvironment = "cartpole"
    , RowAssertions.rleInitialPolicyHash = "initial-policy-sha"
    , RowAssertions.rleFinalPolicyHash = "final-policy-sha"
    , RowAssertions.rleUpdateCount = 100
    , RowAssertions.rleObservedUnits = 25_600
    , RowAssertions.rleDeviceEvidence = "linux-cpu:oneDNN"
    , RowAssertions.rleMetricName = "median_final_reward"
    , RowAssertions.rleMetricGoal = MetricMaximise
    , RowAssertions.rleMetricValue = 460.0
    , RowAssertions.rleConvergenceThreshold = 475.0
    , RowAssertions.rleConvergenceSlack = 25.0
    , RowAssertions.rleSyntheticTransitionEvidence = True
    }

-- | A fully-valid supervised evidence record used as the baseline the fakes
-- perturb by a single field, so the rejection isolates one defect.
validSupervisedBase :: RowAssertions.SupervisedRowEvidence
validSupervisedBase =
  RowAssertions.SupervisedRowEvidence
    { RowAssertions.sreRowId = "mnist-shallow-mlp"
    , RowAssertions.sreInitialWeightHash = "initial-weight-sha"
    , RowAssertions.sreFinalWeightHash = "final-weight-sha"
    , RowAssertions.sreUpdateCount = 500
    , RowAssertions.sreTrainExamples = 60_000
    , RowAssertions.sreValidationExamples = 5_000
    , RowAssertions.sreTestExamples = 10_000
    , RowAssertions.sreExamplesSeen = 300_000
    , RowAssertions.sreThroughputExamples = 1200.0
    , RowAssertions.sreTrainLoss = 0.05
    , RowAssertions.sreValidationLoss = 0.06
    , RowAssertions.sreTestMetricName = "test_accuracy"
    , RowAssertions.sreTestMetricGoal = MetricMaximise
    , RowAssertions.sreTestMetricValue = 0.985
    , RowAssertions.sreConvergenceThreshold = 0.98
    , RowAssertions.sreConvergenceSlack = 0.02
    , RowAssertions.sreGradientNorm = 0.30
    , RowAssertions.sreSmokeThreshold = False
    }

belowThresholdSl :: RowAssertions.SupervisedRowEvidence
belowThresholdSl =
  validSupervisedBase {RowAssertions.sreTestMetricValue = 0.10}

untrainedSl :: RowAssertions.SupervisedRowEvidence
untrainedSl =
  validSupervisedBase
    { RowAssertions.sreFinalWeightHash =
        RowAssertions.sreInitialWeightHash validSupervisedBase
    }

conv2dNotDenseFailures :: [Text]
conv2dNotDenseFailures =
  case (denseOutput, convOutput) of
    (Right dense, Right conv)
      | maxAbsDiff dense conv > 1.0e-9 ->
          ["Conv2D output differs from a Dense affine on the same 3x3 input"]
      | otherwise -> []
    _ -> []
 where
  -- 1-channel 3x3 image; a genuine 3x3 same-padding convolution produces a
  -- length-9 output that a Dense affine on the flattened input cannot match.
  input = VU.fromList [1.0, 2.0, -1.0, 0.5, 0.3, -0.7, 1.1, -0.2, 0.9]
  n = VU.length input
  denseParams = LayerGraph.deterministicParameters 99 n n
  denseOutput = runOne denseParams input
  convSpec =
    LayerGraph.ConvSpec
      { LayerGraph.convIn = 1
      , LayerGraph.convOut = 1
      , LayerGraph.convInputDims = [3, 3]
      , LayerGraph.convKernelDims = [3, 3]
      , LayerGraph.convStride = [1, 1]
      , LayerGraph.convPadding = [1, 1]
      }
  convParams = LayerGraph.deterministicOpParameters 99 (LayerGraph.ConvOp convSpec)
  convOutput = runConv convSpec convParams input

runConv
  :: LayerGraph.ConvSpec
  -> LayerGraph.LayerParameters
  -> VU.Vector Double
  -> Either Text (VU.Vector Double)
runConv spec params input = do
  node <-
    LayerGraph.mkConvLayer
      "negative-control-conv"
      spec
      LayerGraph.LinearActivation
      LayerGraph.InferenceMode
      params
  tape <-
    LayerGraph.runLayerGraph
      LayerGraph.LayerGraph
        { LayerGraph.layerGraphName = "negative-control-conv"
        , LayerGraph.layerGraphInputShape = LayerGraph.layerInputShape node
        , LayerGraph.layerGraphOutputShape = LayerGraph.layerOutputShape node
        , LayerGraph.layerGraphNodes = [node]
        }
      input
  Right (LayerGraph.layerTapeOutput tape)

runOne
  :: LayerGraph.LayerParameters
  -> VU.Vector Double
  -> Either Text (VU.Vector Double)
runOne params input = do
  node <-
    LayerGraph.mkAffineLayer
      "negative-control"
      (VU.length input)
      (VU.length input)
      LayerGraph.LinearActivation
      LayerGraph.InferenceMode
      params
  tape <-
    LayerGraph.runLayerGraph
      LayerGraph.LayerGraph
        { LayerGraph.layerGraphName = "negative-control"
        , LayerGraph.layerGraphInputShape = LayerGraph.TensorShape [VU.length input]
        , LayerGraph.layerGraphOutputShape = LayerGraph.TensorShape [VU.length input]
        , LayerGraph.layerGraphNodes = [node]
        }
      input
  Right (LayerGraph.layerTapeOutput tape)

maxAbsDiff :: VU.Vector Double -> VU.Vector Double -> Double
maxAbsDiff a b =
  maximum (0.0 : VU.toList (VU.zipWith (\x y -> abs (x - y)) a b))

sacAlphaAdaptiveFailures :: [Text]
sacAlphaAdaptiveFailures =
  [ "SAC temperature changed from the fixed initial alpha"
  | let config = ContinuousTrainer.defaultContinuousTrainConfig ContinuousTrainer.VariantSAC
        initialLogAlpha = log (ContinuousTrainer.ctSacAlpha config)
        updatedLogAlpha =
          ContinuousTrainer.sacTemperatureUpdate
            config
            initialLogAlpha
            [-1.8, -1.5, -1.2]
  , abs (updatedLogAlpha - initialLogAlpha) > 1.0e-12
  ]

tqcDropEnabledFailures :: [Text]
tqcDropEnabledFailures =
  [ "TQC default drops top quantile atoms"
  | ContinuousTrainer.ctTqcDropPerCritic
      (ContinuousTrainer.defaultContinuousTrainConfig ContinuousTrainer.VariantTQC)
      > 0
  ]

crossQRenormFailures :: [Text]
crossQRenormFailures =
  [ "CrossQ batch renormalization changes non-normalized Q values"
  | CrossQLoss.crossQNormalise 2.0 4.0 1.0e-6 [6.0] /= [6.0]
  ]

alphaZeroAllDrawFailures :: [Text]
alphaZeroAllDrawFailures =
  [ "AlphaZero all-draw arena result is below the strict win-margin bar"
  | not (RLConvergence.passesAlphaZeroArena RLConvergence.alphaZeroArenaThreshold 0.5)
  ]

cudaWindowedConvFailures :: [Text]
cudaWindowedConvFailures =
  [ "CUDA Conv2D uses a 3x3 cuDNN filter and padded/cropped spatial tensors"
  | let source = renderedCudaSource Conv2DKernel
  , "cudnnSetFilter4dDescriptor(filterDesc, CUDNN_DATA_FLOAT, CUDNN_TENSOR_NCHW, 1, 1, 3, 3)"
      `Text.isInfixOf` source
  , "jitml_fill_filter_2d" `Text.isInfixOf` source
  , "cudaMemcpy(conv2d-crop-output)" `Text.isInfixOf` source
  , not ("jitml_fill_single_filter" `Text.isInfixOf` source)
  ]
    <> [ "CUDA Conv3D uses a 3x3x3 cuDNN filter and padded/cropped spatial tensors"
       | let source = renderedCudaSource Conv3DKernel
       , "int filterDims[5] = {1, 1, 3, 3, 3};" `Text.isInfixOf` source
       , "jitml_fill_filter_3d" `Text.isInfixOf` source
       , "cudaMemcpy(conv3d-crop-output)" `Text.isInfixOf` source
       , not ("jitml_fill_single_filter" `Text.isInfixOf` source)
       ]

renderedCudaSource :: KernelFamily -> Text
renderedCudaSource family =
  Text.concat
    [ contents
    | SourceFile _ contents <-
        CudaCodegen.renderCudaFamilySource
          family
          (Cache.KernelSpec "negative-control:cuda-windowed-conv")
          Cache.Training
          Cache.defaultTuningChoice
    ]

metalWindowedConvFailures :: [Text]
metalWindowedConvFailures =
  [ "Metal Conv2D weighted source has only windowed 3x3 convolution"
  | let source = MetalCodegen.renderMetalFamilySource Conv2DKernel
  , "3x3 windowed convolution" `Text.isInfixOf` source
  , "jitml_ceil_sqrt" `Text.isInfixOf` source
  , not ("wn <= 1u" `Text.isInfixOf` source)
  ]
    <> [ "Metal Conv3D weighted source has only windowed 3x3x3 convolution"
       | let source = MetalCodegen.renderMetalFamilySource Conv3DKernel
       , "3x3x3 windowed convolution" `Text.isInfixOf` source
       , "jitml_ceil_cuberoot" `Text.isInfixOf` source
       , not ("wn <= 1u" `Text.isInfixOf` source)
       ]
