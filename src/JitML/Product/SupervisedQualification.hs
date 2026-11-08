{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Portable, replayable data for five prescribed supervised runs. Refinement
-- checks structure, identities, counters and exact serving comparisons. It does
-- not attest that a producer executed the runs or that embedded examples came
-- from the named archive. Source/invocation authentication and verified loader
-- provenance are separate mandatory boundaries. No value here is a completed
-- or admitted checkpoint; finite non-improving/below-floor runs remain valid.
module JitML.Product.SupervisedQualification
  ( RawQualificationEvaluation (..)
  , RawQualificationProducer (..)
  , qualificationProducerReviewIdentity
  , qualificationProducerReviewWasSupplied
  , RawSupervisedSeedOutcome (..)
  , RawSupervisedQualification (..)
  , BudgetCompleteSupervisedSeedOutcome
  , SupervisedQualification
  , QualifiedSupervisedCohort
  , buildSupervisedQualification
  , refineSupervisedQualification
  , encodeSupervisedQualification
  , decodeSupervisedQualification
  , supervisedQualificationToRaw
  , supervisedQualificationSha256
  , qualificationEvaluationSha256
  , qualificationRuntimeSha256
  , qualificationGraphSha256
  , prescribedSupervisedChildAttempt
  , qualifySupervisedCohort
  , qualifiedSupervisedCohortData
  , supervisedQualificationAssessment
  , supervisedQualificationOutcomes
  , supervisedQualificationEvaluation
  , supervisedQualificationEvaluationBytes
  , supervisedQualificationRuntime
  , supervisedQualificationGraphMetadata
  , supervisedQualificationIndex0Metric
  , supervisedQualificationIndex0Outcome
  , supervisedSeedOutcomeToRaw
  , supervisedSeedOutcomeObservation
  , supervisedSeedOutcomeInitialSnapshotBytes
  , supervisedSeedOutcomeFinalJmw1Bytes
  , supervisedSeedOutcomeInitialJmw1Sha256
  , supervisedSeedOutcomeFinalJmw1Sha256
  )
where

import Codec.Serialise (Serialise, deserialiseOrFail, serialise)
import Control.Monad (zipWithM)
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.List qualified as List
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)
import GHC.Generics (Generic)

import JitML.Checkpoint.WeightCodec qualified as WeightCodec
import JitML.Engines.Engine qualified as Engine
import JitML.Numerics.LayerGraphDevice qualified as LayerGraphDevice
import JitML.Numerics.LayerGraphMetadata (LayerGraphMetadata)
import JitML.Plan.Plan qualified as Plan
import JitML.Plan.Workload qualified as Workload
import JitML.Product.Convergence (convergenceThreshold)
import JitML.Product.CriterionReviewData qualified as Review
import JitML.Product.DeviceWitness qualified as DeviceWitness
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.SourceDigest qualified as Source
import JitML.Product.SupervisedCohortPlan qualified as Cohort
import JitML.Product.SupervisedQualificationPolicy qualified as Policy
import JitML.SL.Architecture qualified as Architecture
import JitML.SL.Canonicals qualified as Canonicals
import JitML.SL.ConvergenceThresholds qualified as Thresholds
import JitML.SL.Dataset qualified as Dataset
import JitML.SL.InitialComparison qualified as Initial
import JitML.SL.RuntimeArtifact qualified as Runtime
import JitML.Substrate (renderSubstrate)

-- | Shared evaluation data appears once. Serialise's Double representation
-- retains binary64 values; exact re-encoding is required at the wire boundary.
data RawQualificationEvaluation
  = RawClassificationEvaluation ![([Double], Int)]
  | RawRegressionEvaluation !Double ![([Double], Double)]
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

-- | Already available identifiers, not a claim of authenticated provenance.
-- No future checkpoint, snapshot or source-journal hash belongs here.
data RawQualificationProducer
  = RawQualificationProducer
      { rawQualificationSourceSha256 :: !Text
      , rawQualificationExecutableSha256 :: !Text
      , rawQualificationInvocationSha256 :: !Text
      }
  | RawObservedReviewedQualificationProducer
      { rawQualificationSourceSha256 :: !Text
      , rawQualificationExecutableSha256 :: !Text
      , rawQualificationInvocationSha256 :: !Text
      , rawQualificationReviewIdentityBytes :: !ByteString
      }
  | RawSuppliedReviewedQualificationProducer
      { rawQualificationSourceSha256 :: !Text
      , rawQualificationExecutableSha256 :: !Text
      , rawQualificationInvocationSha256 :: !Text
      , rawQualificationReviewIdentityBytes :: !ByteString
      }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

-- Original constructor0 remains explicit historical DATA. New constructor tags
-- distinguish direct FILE observation from parent-supplied scenario identity.
qualificationProducerReviewIdentity
  :: RawQualificationProducer -> Either Text (Maybe Review.CriterionReviewIdentityData)
qualificationProducerReviewIdentity producer = case producer of
  RawQualificationProducer {} -> Right Nothing
  RawObservedReviewedQualificationProducer {} -> decode
  RawSuppliedReviewedQualificationProducer {} -> decode
 where
  decode = do
    identity <- Review.decodeCriterionReviewIdentityData (rawQualificationReviewIdentityBytes producer)
    if Review.criterionReviewScope identity == Review.SupervisedCriterionReview
      && Source.stampSha256 (Review.criterionReviewSource identity) == rawQualificationSourceSha256 producer
      then Right (Just identity)
      else Left "supervised producer review differs from its original source or scope"
qualificationProducerReviewWasSupplied :: RawQualificationProducer -> Bool
qualificationProducerReviewWasSupplied RawSuppliedReviewedQualificationProducer {} = True
qualificationProducerReviewWasSupplied _ = False

data RawSupervisedSeedOutcome = RawSupervisedSeedOutcome
  { rawSeedIndex :: !Int
  , rawSeedValue :: !Word64
  , rawSeedPlanId :: !Text
  , rawSeedPlanTransport :: !Text
  , rawSeedAttemptIdentity :: !Text
  , rawSeedObservedEpochs :: !Word64
  , rawSeedObservedExamples :: !Word64
  , rawSeedObservedOptimizerUpdates :: !Word64
  , rawSeedDatasetSha256 :: !Text
  , rawSeedEvaluationSha256 :: !Text
  , rawSeedFinalRuntimeSha256 :: !Text
  , rawSeedFinalGraphSha256 :: !Text
  , rawSeedDeviceWitness :: !DeviceWitness.RawDeviceExecutionWitness
  , rawSeedInitialSnapshotBytes :: !ByteString
  , rawSeedFinalJmw1Bytes :: !ByteString
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

data RawSupervisedQualification = RawSupervisedQualification
  { rawQualificationVersion :: !Word64
  , rawQualificationPolicy :: !Text
  , rawQualificationRowId :: !Text
  , rawQualificationSubstrate :: !Text
  , rawQualificationCohortPlanId :: !Text
  , rawQualificationCohortTransport :: !Text
  , rawQualificationDatasetSha256 :: !Text
  , rawQualificationProducer :: !RawQualificationProducer
  , rawQualificationEvaluation :: !RawQualificationEvaluation
  , rawQualificationEvaluationSha256 :: !Text
  , rawQualificationRuntime :: !Runtime.RawSupervisedRuntime
  , rawQualificationGraphMetadata :: !LayerGraphMetadata
  , rawQualificationSeeds :: ![RawSupervisedSeedOutcome]
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

-- Positional opaque constructors prevent external record-update forgery.
data BudgetCompleteSupervisedSeedOutcome
  = BudgetCompleteSupervisedSeedOutcome
      !RawSupervisedSeedOutcome
      !Policy.SupervisedSeedObservation
      !Text
      !Text
  deriving stock (Eq, Show)

-- The refined value owns compact evaluation storage, rather than retaining the
-- decoded raw DTO and its boxed feature lists. Core fields are independent:
-- selecting one cannot keep a raw qualification alive through a lazy selector.
data QualificationCore = QualificationCore
  { coreVersion :: !Word64
  , corePolicy :: !Text
  , coreRowId :: !Text
  , coreSubstrate :: !Text
  , coreCohortPlanId :: !Text
  , coreCohortTransport :: !Text
  , coreDatasetSha256 :: !Text
  , coreProducer :: !RawQualificationProducer
  , coreEvaluationSha256 :: !Text
  , coreRuntime :: !Runtime.RawSupervisedRuntime
  , coreGraphMetadata :: !LayerGraphMetadata
  }
  deriving stock (Eq)

-- Row boundaries remain explicit; reconstruction preserves the exact original
-- row order and binary64 values without assuming a uniform row width.
data PackedQualificationEvaluation
  = PackedClassificationEvaluation
      !(VU.Vector Int)
      !(VU.Vector Double)
      !(VU.Vector Int)
  | PackedRegressionEvaluation
      !Double
      !(VU.Vector Int)
      !(VU.Vector Double)
      !(VU.Vector Double)
  deriving stock (Eq)

data SupervisedQualification
  = SupervisedQualification
      !QualificationCore
      !PackedQualificationEvaluation
      !(NonEmpty.NonEmpty BudgetCompleteSupervisedSeedOutcome)
      !Policy.SupervisedCohortAssessment
  deriving stock (Eq)

-- Preserve the existing opaque value's diagnostic rendering. Reconstruction is
-- demanded only by this explicit projection; no raw value is cached inside it.
instance Show SupervisedQualification where
  showsPrec precedence value@(SupervisedQualification _ _ outcomes assessment) =
    showParen (precedence > 10) $
      showString "SupervisedQualification "
        . showsPrec 11 (supervisedQualificationToRaw value)
        . showChar ' '
        . showsPrec 11 outcomes
        . showChar ' '
        . showsPrec 11 assessment

-- | Mathematical qualification only. Producer authentication, actual initial
-- capture and physical Store admission are still required by the publisher.
newtype QualifiedSupervisedCohort = QualifiedSupervisedCohort SupervisedQualification
  deriving stock (Eq, Show)

qualificationCoreFromRaw :: RawSupervisedQualification -> QualificationCore
qualificationCoreFromRaw raw =
  QualificationCore
    { coreVersion = rawQualificationVersion raw
    , corePolicy = rawQualificationPolicy raw
    , coreRowId = rawQualificationRowId raw
    , coreSubstrate = rawQualificationSubstrate raw
    , coreCohortPlanId = rawQualificationCohortPlanId raw
    , coreCohortTransport = rawQualificationCohortTransport raw
    , coreDatasetSha256 = rawQualificationDatasetSha256 raw
    , coreProducer = detachProducer (rawQualificationProducer raw)
    , coreEvaluationSha256 = rawQualificationEvaluationSha256 raw
    , coreRuntime = rawQualificationRuntime raw
    , coreGraphMetadata = rawQualificationGraphMetadata raw
    }

-- Small decoded opaque byte fields may be slices of the whole CBOR input.
-- Copy each retained field once, so it cannot pin that larger backing buffer.
detachProducer :: RawQualificationProducer -> RawQualificationProducer
detachProducer producer = case producer of
  RawQualificationProducer {} -> producer
  RawObservedReviewedQualificationProducer source executable invocation identity ->
    RawObservedReviewedQualificationProducer source executable invocation (ByteString.copy identity)
  RawSuppliedReviewedQualificationProducer source executable invocation identity ->
    RawSuppliedReviewedQualificationProducer source executable invocation (ByteString.copy identity)

detachSeed :: RawSupervisedSeedOutcome -> RawSupervisedSeedOutcome
detachSeed raw =
  raw
    { rawSeedInitialSnapshotBytes = ByteString.copy (rawSeedInitialSnapshotBytes raw)
    , rawSeedFinalJmw1Bytes = ByteString.copy (rawSeedFinalJmw1Bytes raw)
    }

packEvaluation :: RawQualificationEvaluation -> PackedQualificationEvaluation
packEvaluation evaluation = case evaluation of
  RawClassificationEvaluation examples ->
    PackedClassificationEvaluation
      (VU.fromList (fmap (length . fst) examples))
      (VU.fromList (concatMap fst examples))
      (VU.fromList (fmap snd examples))
  RawRegressionEvaluation scale examples ->
    PackedRegressionEvaluation
      scale
      (VU.fromList (fmap (length . fst) examples))
      (VU.fromList (concatMap fst examples))
      (VU.fromList (fmap snd examples))

unpackEvaluation :: PackedQualificationEvaluation -> RawQualificationEvaluation
unpackEvaluation packed = case packed of
  PackedClassificationEvaluation lengths features labels ->
    RawClassificationEvaluation (zip (unpackRows lengths features) (VU.toList labels))
  PackedRegressionEvaluation scale lengths features targets ->
    RawRegressionEvaluation scale (zip (unpackRows lengths features) (VU.toList targets))

unpackRows :: VU.Vector Int -> VU.Vector Double -> [[Double]]
unpackRows lengths features = go 0 0
 where
  go row offset
    | row == VU.length lengths = []
    | otherwise =
        let width = lengths VU.! row
         in VU.toList (VU.slice offset width features) : go (row + 1) (offset + width)

-- Fully settle every retained list and scalar. Merely forcing an outer record
-- or list constructor could leave prediction or policy tails closing over the
-- original evaluation, even after its feature vectors have been copied.
forceDoubles :: [Double] -> ()
forceDoubles = List.foldl' (\() value -> value `seq` ()) ()

forceTexts :: [Text] -> ()
forceTexts = List.foldl' (\() value -> value `seq` ()) ()

forceObservation :: Policy.SupervisedSeedObservation -> ()
forceObservation observation = case Policy.observationPredictions observation of
  Policy.ClassificationPredictionPair initial final -> initial `seq` final `seq` ()
  Policy.RegressionPredictionPair initial final -> forceDoubles initial `seq` forceDoubles final

forceOutcome :: BudgetCompleteSupervisedSeedOutcome -> ()
forceOutcome (BudgetCompleteSupervisedSeedOutcome raw observation initialSha finalSha) =
  raw `seq` forceObservation observation `seq` initialSha `seq` finalSha `seq` ()

forceAssessment :: Policy.SupervisedCohortAssessment -> ()
forceAssessment assessment =
  List.foldl'
    (\() observation -> forceObservation observation)
    ()
    (Policy.supervisedCohortObservations assessment)
    `seq` Policy.supervisedCohortJointSuccessCount assessment
    `seq` Policy.supervisedCohortMedian assessment
    `seq` Policy.supervisedCohortServedMetric assessment
    `seq` List.foldl'
      (\() (index, messages) -> index `seq` forceTexts messages)
      ()
      (Policy.supervisedCohortSeedFindings assessment)
    `seq` forceTexts (Policy.supervisedCohortFailures assessment)

qualificationEvaluationSha256 :: RawQualificationEvaluation -> Text
qualificationEvaluationSha256 = hashCanonical

qualificationRuntimeSha256 :: Runtime.RawSupervisedRuntime -> Text
qualificationRuntimeSha256 = hashCanonical

qualificationGraphSha256 :: LayerGraphMetadata -> Text
qualificationGraphSha256 = hashCanonical

-- | A prescribed in-process child identity, not an invented execution receipt.
prescribedSupervisedChildAttempt :: Text -> Cohort.SupervisedSeedPlan -> Text
prescribedSupervisedChildAttempt invocation child =
  "supervised-child-attempt-v1|"
    <> Text.concat
      ( fmap
          field
          [ invocation
          , Text.pack (show (Policy.supervisedSeedIndexValue (Cohort.supervisedSeedPlanIndex child)))
          , Plan.planIdText (Workload.supervisedPlanId (Cohort.supervisedSeedPlanWorkload child))
          ]
      )
 where
  field value = Text.pack (show (Text.length value)) <> ":" <> value <> "|"

-- | Construct the deterministic envelope around actual returned raw child
-- observations. Producer identifiers are supplied by the authenticated caller;
-- this pure builder never invents or authenticates them.
buildSupervisedQualification
  :: Cohort.SupervisedCohortPlan
  -> RawQualificationProducer
  -> RawQualificationEvaluation
  -> Runtime.RawSupervisedRuntime
  -> LayerGraphMetadata
  -> [RawSupervisedSeedOutcome]
  -> Either Text SupervisedQualification
buildSupervisedQualification plan producer evaluation runtime metadata seeds = do
  let projection = Cohort.supervisedCohortPlanProjection plan
  problem <- canonicalProblem (Matrix.productProjectionRowId projection)
  datasetSha <- Dataset.canonicalDatasetReadShaForProblem problem
  refineSupervisedQualification
    plan
    RawSupervisedQualification
      { rawQualificationVersion = 1
      , rawQualificationPolicy = Policy.supervisedQualificationPolicyContract
      , rawQualificationRowId = Matrix.productProjectionRowId projection
      , rawQualificationSubstrate = renderSubstrate (Matrix.productProjectionSubstrate projection)
      , rawQualificationCohortPlanId = Plan.planIdText (Cohort.supervisedCohortPlanId plan)
      , rawQualificationCohortTransport = Cohort.supervisedCohortPlanTransport plan
      , rawQualificationDatasetSha256 = datasetSha
      , rawQualificationProducer = producer
      , rawQualificationEvaluation = evaluation
      , rawQualificationEvaluationSha256 = qualificationEvaluationSha256 evaluation
      , rawQualificationRuntime = runtime
      , rawQualificationGraphMetadata = metadata
      , rawQualificationSeeds = seeds
      }

refineSupervisedQualification
  :: Cohort.SupervisedCohortPlan
  -> RawSupervisedQualification
  -> Either Text SupervisedQualification
refineSupervisedQualification plan raw = do
  requireEqual "qualification wire version" 1 (rawQualificationVersion raw)
  requireEqual
    "qualification policy"
    Policy.supervisedQualificationPolicyContract
    (rawQualificationPolicy raw)
  requireEqual
    "qualification row"
    (Matrix.productProjectionRowId projection)
    (rawQualificationRowId raw)
  requireEqual "qualification substrate" (renderSubstrate substrate) (rawQualificationSubstrate raw)
  requireEqual
    "qualification cohort PlanId"
    (Plan.planIdText (Cohort.supervisedCohortPlanId plan))
    (rawQualificationCohortPlanId raw)
  requireEqual
    "qualification cohort transport"
    (Cohort.supervisedCohortPlanTransport plan)
    (rawQualificationCohortTransport raw)
  problem <- canonicalProblem (Matrix.productProjectionRowId projection)
  datasetSha <- Dataset.canonicalDatasetReadShaForProblem problem
  requireEqual
    "qualification canonical dataset-at-read SHA"
    datasetSha
    (rawQualificationDatasetSha256 raw)
  validateProducer (rawQualificationProducer raw)
  review <- qualificationProducerReviewIdentity (rawQualificationProducer raw)
  case review of
    Nothing -> Right () -- Historical ordinary qualification, refused by current registered boundary.
    Just identity -> requireEqual "qualification reviewed lane" substrate (Review.criterionReviewSubstrate identity)
  let evaluation = rawQualificationEvaluation raw
      evaluationSha = qualificationEvaluationSha256 evaluation
  requireEqual
    "qualification evaluation bytes SHA"
    evaluationSha
    (rawQualificationEvaluationSha256 raw)
  children <- exactlyFiveChildren (Cohort.supervisedCohortPlanChildren plan)
  firstChild <- firstOfFive children
  work <- expectedWork firstChild
  let expectedEvaluationCount =
        Plan.quantityValue
          (Workload.supervisedPlanEvaluationExamples (Cohort.supervisedSeedPlanWorkload firstChild))
  policyEvaluation <-
    evaluationForProjection projection expectedEvaluationCount evaluation (rawQualificationRuntime raw)
  if fmap rawSeedIndex (rawQualificationSeeds raw) == [0 .. 4]
    then Right ()
    else Left "qualification requires exactly five ordered raw seed outcomes 0..4"
  let core = qualificationCoreFromRaw raw
  outcomes <- zipWithM (refineSeed core evaluation work) children (rawQualificationSeeds raw)
  let base = Cohort.supervisedSeedPlanSeed firstChild
      headroom =
        case Matrix.productProjectionRowClass projection of
          Matrix.SupervisedRegression _ _ -> 0
          _ -> Architecture.architectureSeedHeadroomForProblem problem
  assessment <-
    Policy.assessSupervisedCohort
      base
      headroom
      work
      policyEvaluation
      (fmap supervisedSeedOutcomeObservation outcomes)
  case NonEmpty.nonEmpty outcomes of
    Just complete ->
      let value = SupervisedQualification core (packEvaluation evaluation) complete assessment
       in List.foldl' (\() outcome -> forceOutcome outcome) () outcomes `seq`
            forceAssessment assessment `seq`
              value `seq`
                Right value
    Nothing -> Left "qualification has no index0 outcome"
 where
  projection = Cohort.supervisedCohortPlanProjection plan
  substrate = Matrix.productProjectionSubstrate projection

refineSeed
  :: QualificationCore
  -> RawQualificationEvaluation
  -> Policy.SupervisedExpectedWork
  -> Cohort.SupervisedSeedPlan
  -> RawSupervisedSeedOutcome
  -> Either Text BudgetCompleteSupervisedSeedOutcome
refineSeed common evaluation work child raw = do
  let workload = Cohort.supervisedSeedPlanWorkload child
      expectedIndex = Policy.supervisedSeedIndexValue (Cohort.supervisedSeedPlanIndex child)
      projection = Cohort.supervisedSeedPlanBaseProjection child
      substrate = Matrix.productProjectionSubstrate projection
      producer = coreProducer common
      runtime = coreRuntime common
      metadata = coreGraphMetadata common
  requireEqual "qualification child index" expectedIndex (rawSeedIndex raw)
  requireEqual "qualification child seed" (Cohort.supervisedSeedPlanSeed child) (rawSeedValue raw)
  requireEqual
    "qualification child PlanId"
    (Plan.planIdText (Workload.supervisedPlanId workload))
    (rawSeedPlanId raw)
  requireEqual
    "qualification child transport"
    (Workload.renderSupervisedPlanTransport workload)
    (rawSeedPlanTransport raw)
  requireEqual
    "qualification child attempt identity"
    (prescribedSupervisedChildAttempt (rawQualificationInvocationSha256 producer) child)
    (rawSeedAttemptIdentity raw)
  requireEqual
    "qualification child dataset-at-read SHA"
    (coreDatasetSha256 common)
    (rawSeedDatasetSha256 raw)
  requireEqual
    "qualification child evaluation SHA"
    (coreEvaluationSha256 common)
    (rawSeedEvaluationSha256 raw)
  requireEqual
    "qualification child final runtime SHA"
    (qualificationRuntimeSha256 runtime)
    (rawSeedFinalRuntimeSha256 raw)
  requireEqual
    "qualification child final graph SHA"
    (qualificationGraphSha256 metadata)
    (rawSeedFinalGraphSha256 raw)
  childWork <- expectedWork child
  requireEqual "qualification child unchanged work" work childWork
  requireEqual
    "qualification observed epochs"
    (Policy.supervisedExpectedEpochs work)
    (rawSeedObservedEpochs raw)
  requireEqual
    "qualification observed examples"
    (Policy.supervisedExpectedExamplesProcessed work)
    (rawSeedObservedExamples raw)
  requireEqual
    "qualification observed optimizer updates"
    (Policy.supervisedExpectedOptimizerUpdates work)
    (rawSeedObservedOptimizerUpdates raw)
  witness <- DeviceWitness.refineRawDeviceExecutionWitness (rawSeedDeviceWitness raw)
  requireEqual
    "qualification device witness substrate"
    substrate
    (DeviceWitness.witnessSubstrate witness)
  backend <- expectedBackend projection
  requireEqual
    "qualification device witness backend"
    backend
    (DeviceWitness.witnessBackend witness)
  initial <- Initial.decodeInitialComparisonSnapshot (rawSeedInitialSnapshotBytes raw)
  comparison <-
    Initial.prepareSupervisedComparison initial runtime metadata (rawSeedFinalJmw1Bytes raw)
  predictions <- replayEvaluation comparison evaluation
  let observation =
        Policy.SupervisedSeedObservation
          { Policy.observationSeedIndex = rawSeedIndex raw
          , Policy.observationSeed = rawSeedValue raw
          , Policy.observationCompletedEpochs = rawSeedObservedEpochs raw
          , Policy.observationExamplesProcessed = rawSeedObservedExamples raw
          , Policy.observationOptimizerUpdates = rawSeedObservedOptimizerUpdates raw
          , Policy.observationPredictions = predictions
          }
  Right
    ( BudgetCompleteSupervisedSeedOutcome
        (detachSeed raw)
        observation
        (Initial.initialComparisonJmw1Sha256 initial)
        (hashBytes (rawSeedFinalJmw1Bytes raw))
    )

evaluationForProjection
  :: Matrix.ProductProjection 'Plan.SupervisedTraining
  -> Word64
  -> RawQualificationEvaluation
  -> Runtime.RawSupervisedRuntime
  -> Either Text Policy.SupervisedEvaluation
evaluationForProjection projection expectedCount evaluation runtime = do
  refinedRuntime <- Runtime.refineSupervisedRuntime runtime
  let floorValue = convergenceThreshold (Matrix.productProjectionConvergenceBar projection)
  case (Matrix.productProjectionRowClass projection, evaluation) of
    (Matrix.SupervisedClassification _ _, RawClassificationEvaluation examples) -> do
      classes <-
        maybe
          (Left "qualification row has no canonical semantic class count")
          Right
          (Thresholds.slClassCount (Matrix.productProjectionRowId projection))
      requireEqual
        "qualification classification task"
        (Runtime.RawClassificationRuntimeTask classes)
        (Runtime.runtimeTaskToRaw (Runtime.supervisedRuntimeTask refinedRuntime))
      requireCount expectedCount examples
      if all (\(_, label) -> label >= 0 && label < classes) examples
        then Right ()
        else Left "qualification classification label lies outside its canonical classes"
      Right (Policy.ClassificationEvaluation classes (fmap snd examples) floorValue)
    (Matrix.SupervisedRegression _ _, RawRegressionEvaluation scale examples) -> do
      requireEqual
        "qualification regression task"
        (Runtime.RawRegressionRuntimeTask 1)
        (Runtime.runtimeTaskToRaw (Runtime.supervisedRuntimeTask refinedRuntime))
      requireCount expectedCount examples
      if finite scale && scale > 0 && all (finite . snd) examples
        then Right ()
        else Left "qualification regression scale/target is not finite and valid"
      case Runtime.rawSupervisedRuntimeOutputTransform runtime of
        Runtime.RawDestandardizeOutput [_mean] [runtimeScale]
          | serialise runtimeScale == serialise scale -> Right ()
        _ -> Left "qualification regression scale differs from the actual runtime target transform"
      Right (Policy.RegressionEvaluation scale (fmap snd examples) floorValue)
    _ -> Left "qualification evaluation kind differs from the canonical supervised row"

replayEvaluation
  :: Initial.SupervisedComparison
  -> RawQualificationEvaluation
  -> Either Text Policy.SupervisedPredictionPair
replayEvaluation comparison evaluation =
  case evaluation of
    RawClassificationEvaluation examples -> do
      classes <-
        case Runtime.rawSupervisedRuntimeTask
          ( Initial.rawInitialComparisonRuntime
              (Initial.initialComparisonSnapshotToRaw (Initial.comparisonInitialSnapshot comparison))
          ) of
          Runtime.RawClassificationRuntimeTask count -> Right count
          _ -> Left "qualification classification replay has a nonclassification runtime"
      initial <-
        traverse (classificationDecision classes (Initial.comparisonInitialInference comparison)) examples
      final <-
        traverse (classificationDecision classes (Initial.comparisonFinalInference comparison)) examples
      Right
        ( Policy.ClassificationPredictionPair
            (length (filter id initial))
            (length (filter id final))
        )
    RawRegressionEvaluation _scale examples -> do
      initial <-
        traverse (regressionPrediction (Initial.comparisonInitialInference comparison) . fst) examples
      final <-
        traverse (regressionPrediction (Initial.comparisonFinalInference comparison) . fst) examples
      Right (Policy.RegressionPredictionPair initial final)

classificationDecision
  :: Int
  -> ([Double] -> Either Text [Double])
  -> ([Double], Int)
  -> Either Text Bool
classificationDecision classes infer (features, label) = do
  if all finite features
    then Right ()
    else Left "qualification classification input is non-finite"
  output <- infer features
  if length output /= classes || not (all finite output) || label < 0 || label >= classes
    then Left "qualification classification replay has invalid output/label"
    else Right (VU.maxIndex (VU.fromList output) == label)

regressionPrediction
  :: ([Double] -> Either Text [Double])
  -> [Double]
  -> Either Text Double
regressionPrediction infer features = do
  if all finite features
    then Right ()
    else Left "qualification regression input is non-finite"
  output <- infer features
  case output of
    [prediction] | finite prediction -> Right prediction
    _ -> Left "qualification regression replay did not produce one finite scalar"

expectedWork :: Cohort.SupervisedSeedPlan -> Either Text Policy.SupervisedExpectedWork
expectedWork child = do
  let plan = Cohort.supervisedSeedPlanWorkload child
  work <-
    Policy.supervisedExpectedWork
      (Plan.quantityValue (Workload.supervisedPlanEpochs plan))
      (Plan.quantityValue (Workload.supervisedPlanTrainingExamples plan))
      (Plan.quantityValue (Workload.supervisedPlanBatchExamples plan))
  requireEqual
    "qualification planned optimizer updates"
    (Policy.supervisedExpectedOptimizerUpdates work)
    (Plan.quantityValue (Workload.supervisedPlanOptimizerUpdates plan))
  Right work

validateProducer :: RawQualificationProducer -> Either Text ()
validateProducer producer =
  mapM_
    ( \(name, value) ->
        if canonicalSha value
          then Right ()
          else Left ("qualification " <> name <> " must be a canonical SHA256")
    )
    [ ("source identity", rawQualificationSourceSha256 producer)
    , ("executable identity", rawQualificationExecutableSha256 producer)
    , ("invocation identity", rawQualificationInvocationSha256 producer)
    ]

canonicalProblem :: Text -> Either Text Canonicals.CanonicalProblem
canonicalProblem row =
  maybe
    (Left "qualification row is not an exact canonical supervised problem")
    Right
    (List.find ((== row) . Canonicals.problemName) Canonicals.canonicalProblems)

exactlyFiveChildren :: [child] -> Either Text [child]
exactlyFiveChildren values@[_a, _b, _c, _d, _e] = Right values
exactlyFiveChildren _ = Left "qualification plan must own exactly five children"

firstOfFive :: [value] -> Either Text value
firstOfFive [first, _, _, _, _] = Right first
firstOfFive _ = Left "qualification requires an index0 child"

requireCount :: Word64 -> [value] -> Either Text ()
requireCount expected examples
  | toInteger (length examples) == toInteger expected && expected > 0 = Right ()
  | otherwise = Left "qualification held-out count differs from the exact plan"

encodeSupervisedQualification :: SupervisedQualification -> ByteString
encodeSupervisedQualification = LazyByteString.toStrict . serialise . supervisedQualificationToRaw

decodeSupervisedQualification
  :: Cohort.SupervisedCohortPlan
  -> ByteString
  -> Either Text SupervisedQualification
decodeSupervisedQualification plan bytes = do
  raw <-
    case deserialiseOrFail (LazyByteString.fromStrict bytes) of
      Left err -> Left ("qualification CBOR decode failed: " <> Text.pack (show err))
      Right value -> Right value
  refined <- refineSupervisedQualification plan raw
  if encodeSupervisedQualification refined == bytes
    then Right refined
    else Left "qualification CBOR encoding is not canonical"

supervisedQualificationToRaw :: SupervisedQualification -> RawSupervisedQualification
supervisedQualificationToRaw (SupervisedQualification core evaluation outcomes _) =
  RawSupervisedQualification
    { rawQualificationVersion = coreVersion core
    , rawQualificationPolicy = corePolicy core
    , rawQualificationRowId = coreRowId core
    , rawQualificationSubstrate = coreSubstrate core
    , rawQualificationCohortPlanId = coreCohortPlanId core
    , rawQualificationCohortTransport = coreCohortTransport core
    , rawQualificationDatasetSha256 = coreDatasetSha256 core
    , rawQualificationProducer = coreProducer core
    , rawQualificationEvaluation = unpackEvaluation evaluation
    , rawQualificationEvaluationSha256 = coreEvaluationSha256 core
    , rawQualificationRuntime = coreRuntime core
    , rawQualificationGraphMetadata = coreGraphMetadata core
    , rawQualificationSeeds = fmap supervisedSeedOutcomeToRaw (NonEmpty.toList outcomes)
    }

supervisedQualificationSha256 :: SupervisedQualification -> Text
supervisedQualificationSha256 = hashBytes . encodeSupervisedQualification

qualifySupervisedCohort :: SupervisedQualification -> Either Text QualifiedSupervisedCohort
qualifySupervisedCohort value =
  case Policy.supervisedCohortFailures (supervisedQualificationAssessment value) of
    [] -> Right (QualifiedSupervisedCohort value)
    failures -> Left ("supervised cohort did not qualify: " <> Text.intercalate "; " failures)

qualifiedSupervisedCohortData :: QualifiedSupervisedCohort -> SupervisedQualification
qualifiedSupervisedCohortData (QualifiedSupervisedCohort value) = value

supervisedQualificationAssessment :: SupervisedQualification -> Policy.SupervisedCohortAssessment
supervisedQualificationAssessment (SupervisedQualification _ _ _ value) = value

supervisedQualificationOutcomes :: SupervisedQualification -> [BudgetCompleteSupervisedSeedOutcome]
supervisedQualificationOutcomes (SupervisedQualification _ _ values _) = NonEmpty.toList values

supervisedQualificationEvaluation :: SupervisedQualification -> RawQualificationEvaluation
supervisedQualificationEvaluation (SupervisedQualification _ evaluation _ _) = unpackEvaluation evaluation

supervisedQualificationEvaluationBytes :: SupervisedQualification -> ByteString
supervisedQualificationEvaluationBytes = LazyByteString.toStrict . serialise . supervisedQualificationEvaluation

supervisedQualificationRuntime :: SupervisedQualification -> Runtime.RawSupervisedRuntime
supervisedQualificationRuntime (SupervisedQualification core _ _ _) = coreRuntime core

supervisedQualificationGraphMetadata :: SupervisedQualification -> LayerGraphMetadata
supervisedQualificationGraphMetadata (SupervisedQualification core _ _ _) = coreGraphMetadata core

supervisedQualificationIndex0Metric :: SupervisedQualification -> Double
supervisedQualificationIndex0Metric = Policy.supervisedCohortServedMetric . supervisedQualificationAssessment

supervisedQualificationIndex0Outcome
  :: SupervisedQualification -> BudgetCompleteSupervisedSeedOutcome
supervisedQualificationIndex0Outcome (SupervisedQualification _ _ values _) = NonEmpty.head values

supervisedSeedOutcomeToRaw :: BudgetCompleteSupervisedSeedOutcome -> RawSupervisedSeedOutcome
supervisedSeedOutcomeToRaw (BudgetCompleteSupervisedSeedOutcome raw _ _ _) = raw

supervisedSeedOutcomeObservation
  :: BudgetCompleteSupervisedSeedOutcome -> Policy.SupervisedSeedObservation
supervisedSeedOutcomeObservation (BudgetCompleteSupervisedSeedOutcome _ value _ _) = value

supervisedSeedOutcomeInitialSnapshotBytes :: BudgetCompleteSupervisedSeedOutcome -> ByteString
supervisedSeedOutcomeInitialSnapshotBytes = rawSeedInitialSnapshotBytes . supervisedSeedOutcomeToRaw

supervisedSeedOutcomeFinalJmw1Bytes :: BudgetCompleteSupervisedSeedOutcome -> ByteString
supervisedSeedOutcomeFinalJmw1Bytes = rawSeedFinalJmw1Bytes . supervisedSeedOutcomeToRaw

supervisedSeedOutcomeInitialJmw1Sha256 :: BudgetCompleteSupervisedSeedOutcome -> Text
supervisedSeedOutcomeInitialJmw1Sha256 (BudgetCompleteSupervisedSeedOutcome _ _ value _) = value

supervisedSeedOutcomeFinalJmw1Sha256 :: BudgetCompleteSupervisedSeedOutcome -> Text
supervisedSeedOutcomeFinalJmw1Sha256 (BudgetCompleteSupervisedSeedOutcome _ _ _ value) = value

requireEqual :: (Eq value) => Text -> value -> value -> Either Text ()
requireEqual field expected observed
  | expected == observed = Right ()
  | otherwise = Left (field <> " mismatch")

-- Classification executes the layer graph; regression executes the MLP ABI.
-- Select the exact expected identity from the projection, never the witness.
expectedBackend :: Matrix.ProductProjection 'Plan.SupervisedTraining -> Either Text Text
expectedBackend projection =
  case Matrix.productProjectionRowClass projection of
    Matrix.SupervisedClassification _ _ ->
      LayerGraphDevice.layerTrainingBackendIdentity
        <$> LayerGraphDevice.layerTrainingBackendFor substrate
    Matrix.SupervisedRegression _ _ ->
      Right (Engine.engineBackend (Engine.engineForSubstrate substrate))
    _ -> Left "qualification requires a supervised execution family"
 where
  substrate = Matrix.productProjectionSubstrate projection

canonicalSha :: Text -> Bool
canonicalSha value =
  Text.length value == 64
    && Text.all (\character -> character `elem` ("0123456789abcdef" :: String)) value

hashCanonical :: (Serialise value) => value -> Text
hashCanonical = WeightCodec.jmw1ContentSha . serialise

hashBytes :: ByteString -> Text
hashBytes = WeightCodec.jmw1ContentSha . LazyByteString.fromStrict

finite :: Double -> Bool
finite value = not (isNaN value || isInfinite value)
