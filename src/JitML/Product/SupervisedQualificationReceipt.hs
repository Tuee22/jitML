{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

-- | A detached qualification is not a Store companion. This boundary couples
-- the replayed five-run data to the exact admitted index-zero checkpoint.
-- Parsing a reference authenticates nothing; the parent must compare its own
-- captured source, executable and invocation before accepting publication.
module JitML.Product.SupervisedQualificationReceipt
  ( SupervisedQualificationPublication
  , SupervisedQualificationReference
  , RetainedSupervisedQualification
  , retainedSupervisedQualificationSource
  , retainedSupervisedQualificationReviewIdentity
  , bindSupervisedQualificationPublication
  , validateSupervisedQualificationPublication
  , replaySupervisedQualificationReference
  , validateRetainedSupervisedQualification
  , supervisedQualificationObjectKey
  , supervisedQualificationPublicationReference
  , supervisedQualificationPublicationData
  , renderSupervisedQualificationPublication
  , renderSupervisedQualificationReference
  , parseSupervisedQualificationReference
  , supervisedQualificationReceiptPrefix
  , qualificationReferenceRowId
  , qualificationReferencePlanId
  , qualificationReferenceSubstrate
  , qualificationReferenceExperimentHash
  , qualificationReferenceManifestSha256
  , qualificationReferenceSourceSha256
  , qualificationReferenceExecutableSha256
  , qualificationReferenceInvocationSha256
  , qualificationReferenceArtifactSha256
  , qualificationReferenceObjectKey
  , qualificationReferenceIsScenarioBound
  )
where

import Codec.Serialise (serialise)
import Control.Monad (unless, when)
import Data.Aeson
  ( FromJSON (..)
  , ToJSON (..)
  , eitherDecodeStrict'
  , encode
  , object
  , withObject
  , (.:)
  , (.=)
  )
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString (ByteString)
import Data.ByteString.Lazy qualified as LBS
import Data.Char (isControl)
import Data.Either.Combinators (mapLeft)
import Data.List qualified as List
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Encoding
import Data.Word (Word64)

import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Checkpoint.Store qualified as Store
import JitML.Plan.Plan qualified as Plan
import JitML.Product.Convergence qualified as Convergence
import JitML.Product.CriterionReviewData qualified as Review
import JitML.Product.DeviceWitness qualified as Device
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.ServedMetric qualified as ServedMetric
import JitML.Product.SourceDigest qualified as Source
import JitML.Product.SupervisedCohortPlan qualified as Cohort
import JitML.Product.SupervisedQualification qualified as Qualification
import JitML.SL.InitialComparison qualified as Initial
import JitML.SL.RuntimeArtifact qualified as Runtime
import JitML.Substrate (parseSubstrate, renderSubstrate)
import JitML.Training.Budget qualified as Budget

data ReferenceWire = ReferenceWire
  { internalVersion :: !Word64
  , internalRow :: !Text
  , internalPlan :: !Text
  , internalLane :: !Text
  , internalExperiment :: !Text
  , internalManifest :: !Text
  , internalSource :: !Text
  , internalExecutable :: !Text
  , internalInvocation :: !Text
  , internalCohortPlan :: !Text
  , internalArtifact :: !Text
  , internalObjectKey :: !Text
  , internalInitial :: !Text
  , internalFinal :: !Text
  , internalRuntime :: !Text
  , internalGraph :: !Text
  , internalEvaluation :: !Text
  , internalBinding :: !Text
  }
  deriving stock (Eq, Show)

newtype SupervisedQualificationReference = SupervisedQualificationReference ReferenceWire
  deriving stock (Eq, Show)

-- | Original source-journal admission retained under the caller's pinned lane
-- bytes. This type never claims a new physical Store admission.
data RetainedSupervisedQualification
  = RetainedSupervisedQualification
      !SupervisedQualificationReference
      !Qualification.QualifiedSupervisedCohort
      !Budget.CompletedTraining
      !(Maybe Review.CriterionReviewIdentityData)
  deriving stock (Eq, Show)

data SupervisedQualificationPublication
  = SupervisedQualificationPublication
      !SupervisedQualificationReference
      !Qualification.QualifiedSupervisedCohort
  deriving stock (Eq, Show)

instance ToJSON ReferenceWire where
  toJSON wire =
    object
      [ "version" .= internalVersion wire
      , "row_id" .= internalRow wire
      , "plan_id" .= internalPlan wire
      , "substrate" .= internalLane wire
      , "experiment_hash" .= internalExperiment wire
      , "manifest_sha256" .= internalManifest wire
      , "source_sha256" .= internalSource wire
      , "executable_sha256" .= internalExecutable wire
      , "invocation_sha256" .= internalInvocation wire
      , "cohort_plan_id" .= internalCohortPlan wire
      , "qualification_sha256" .= internalArtifact wire
      , "qualification_object_key" .= internalObjectKey wire
      , "initial_jmw1_sha256" .= internalInitial wire
      , "final_jmw1_sha256" .= internalFinal wire
      , "runtime_sha256" .= internalRuntime wire
      , "graph_sha256" .= internalGraph wire
      , "evaluation_sha256" .= internalEvaluation wire
      , "execution_binding" .= internalBinding wire
      ]

instance FromJSON ReferenceWire where
  parseJSON = withObject "SupervisedQualificationReference" $ \record -> do
    let expected =
          [ "version"
          , "row_id"
          , "plan_id"
          , "substrate"
          , "experiment_hash"
          , "manifest_sha256"
          , "source_sha256"
          , "executable_sha256"
          , "invocation_sha256"
          , "cohort_plan_id"
          , "qualification_sha256"
          , "qualification_object_key"
          , "initial_jmw1_sha256"
          , "final_jmw1_sha256"
          , "runtime_sha256"
          , "graph_sha256"
          , "evaluation_sha256"
          , "execution_binding"
          ]
    unless
      (List.sort (fmap Key.toText (KeyMap.keys record)) == List.sort expected)
      (fail "qualification reference fields differ from its exact schema")
    ReferenceWire
      <$> record .: "version"
      <*> record .: "row_id"
      <*> record .: "plan_id"
      <*> record .: "substrate"
      <*> record .: "experiment_hash"
      <*> record .: "manifest_sha256"
      <*> record .: "source_sha256"
      <*> record .: "executable_sha256"
      <*> record .: "invocation_sha256"
      <*> record .: "cohort_plan_id"
      <*> record .: "qualification_sha256"
      <*> record .: "qualification_object_key"
      <*> record .: "initial_jmw1_sha256"
      <*> record .: "final_jmw1_sha256"
      <*> record .: "runtime_sha256"
      <*> record .: "graph_sha256"
      <*> record .: "evaluation_sha256"
      <*> record .: "execution_binding"

supervisedQualificationReceiptPrefix :: Text
supervisedQualificationReceiptPrefix = "product-supervised-qualification-v1\t"

supervisedQualificationObjectKey :: Cohort.SupervisedCohortPlan -> Text -> Text
supervisedQualificationObjectKey plan sha =
  "jitml-checkpoints/"
    <> Matrix.productProjectionExperimentHash (Cohort.supervisedCohortPlanProjection plan)
    <> "/artifacts/supervised-qualification/"
    <> sha
    <> ".cbor"

renderSupervisedQualificationReference :: SupervisedQualificationReference -> Text
renderSupervisedQualificationReference (SupervisedQualificationReference wire) =
  supervisedQualificationReceiptPrefix <> Encoding.decodeUtf8 (LBS.toStrict (encode wire))

renderSupervisedQualificationPublication :: SupervisedQualificationPublication -> Text
renderSupervisedQualificationPublication = renderSupervisedQualificationReference . supervisedQualificationPublicationReference

parseSupervisedQualificationReference :: Text -> Either Text SupervisedQualificationReference
parseSupervisedQualificationReference line = do
  body <-
    maybe
      (Left "qualification receipt has an unsupported prefix")
      Right
      (Text.stripPrefix supervisedQualificationReceiptPrefix line)
  wire <- mapLeft Text.pack (eitherDecodeStrict' (Encoding.encodeUtf8 body))
  requireEqual
    "qualification receipt canonical encoding"
    (Encoding.decodeUtf8 (LBS.toStrict (encode wire)))
    body
  requireEqual "qualification receipt version" 1 (internalVersion wire)
  mapM_
    requireSha
    [ internalPlan wire
    , internalManifest wire
    , internalSource wire
    , internalExecutable wire
    , internalInvocation wire
    , internalCohortPlan wire
    , internalArtifact wire
    , internalInitial wire
    , internalFinal wire
    , internalRuntime wire
    , internalGraph wire
    , internalEvaluation wire
    ]
  unless
    (internalBinding wire `elem` [scenarioBinding, directBinding])
    (Left "qualification receipt execution binding is unknown")
  case parseSubstrate (internalLane wire) of
    Nothing -> Left "qualification receipt substrate is unknown"
    Just _ -> Right ()
  unless
    ( not (Text.null (internalExperiment wire))
        && Text.all
          (\character -> character `elem` ("0123456789abcdefghijklmnopqrstuvwxyz-" :: String))
          (internalExperiment wire)
    )
    (Left "qualification receipt experiment namespace is not canonical")
  requireEqual
    "qualification receipt detached namespace"
    ( "jitml-checkpoints/"
        <> internalExperiment wire
        <> "/artifacts/supervised-qualification/"
        <> internalArtifact wire
        <> ".cbor"
    )
    (internalObjectKey wire)
  unless
    ( validText (internalRow wire)
        && validText (internalExperiment wire)
        && validText (internalObjectKey wire)
    )
    (Left "qualification receipt contains empty, untrimmed or control text")
  Right (SupervisedQualificationReference wire)

bindSupervisedQualificationPublication
  :: Cohort.SupervisedCohortPlan
  -> Qualification.QualifiedSupervisedCohort
  -> Text
  -> Store.AdmittedCompletedCheckpoint
  -> Either Text SupervisedQualificationPublication
bindSupervisedQualificationPublication plan qualified key admitted = do
  let qualification = Qualification.qualifiedSupervisedCohortData qualified
      raw = Qualification.supervisedQualificationToRaw qualification
      projection = Cohort.supervisedCohortPlanProjection plan
      producer = Qualification.rawQualificationProducer raw
      outcome = Qualification.supervisedQualificationIndex0Outcome qualification
      artifactSha = Qualification.supervisedQualificationSha256 qualification
      wire =
        ReferenceWire
          1
          (Matrix.productProjectionRowId projection)
          (Plan.planIdText (Matrix.productProjectionPlanId projection))
          (renderSubstrate (Matrix.productProjectionSubstrate projection))
          (Matrix.productProjectionExperimentHash projection)
          (Store.admittedCheckpointManifestSha (Store.admittedCompletedCheckpoint admitted))
          (Qualification.rawQualificationSourceSha256 producer)
          (Qualification.rawQualificationExecutableSha256 producer)
          (Qualification.rawQualificationInvocationSha256 producer)
          (Plan.planIdText (Cohort.supervisedCohortPlanId plan))
          artifactSha
          key
          (Qualification.supervisedSeedOutcomeInitialJmw1Sha256 outcome)
          (Qualification.supervisedSeedOutcomeFinalJmw1Sha256 outcome)
          ( Qualification.qualificationRuntimeSha256
              (Qualification.supervisedQualificationRuntime qualification)
          )
          ( Qualification.qualificationGraphSha256
              (Qualification.supervisedQualificationGraphMetadata qualification)
          )
          ( Qualification.qualificationEvaluationSha256
              (Qualification.supervisedQualificationEvaluation qualification)
          )
          ( case Budget.completedTrainingProductScenarioInvocation (Store.admittedCompletedTraining admitted) of
              Nothing -> directBinding
              Just _ -> scenarioBinding
          )
      reference = SupervisedQualificationReference wire
  requireEqual
    "qualification exact detached object key"
    (supervisedQualificationObjectKey plan artifactSha)
    key
  replayed <-
    replaySupervisedQualificationReference
      plan
      reference
      (Qualification.encodeSupervisedQualification qualification)
  bindAdmitted plan replayed reference admitted
  Right (SupervisedQualificationPublication reference replayed)

-- | The parent supplies identities it actually captured, never identities read
-- back from the child receipt itself. No path-scope hash substitutes for this.
validateSupervisedQualificationPublication
  :: Cohort.SupervisedCohortPlan
  -> Text
  -> Text
  -> Text
  -> SupervisedQualificationReference
  -> ByteString
  -> Store.AdmittedCompletedCheckpoint
  -> Either Text SupervisedQualificationPublication
validateSupervisedQualificationPublication plan expectedSource expectedExecutable expectedInvocation reference bytes admitted = do
  let SupervisedQualificationReference wire = reference
  requireEqual "qualification parent scenario binding" scenarioBinding (internalBinding wire)
  requireEqual "qualification parent source identity" expectedSource (internalSource wire)
  requireEqual "qualification parent executable identity" expectedExecutable (internalExecutable wire)
  requireEqual "qualification parent invocation identity" expectedInvocation (internalInvocation wire)
  qualified <- replaySupervisedQualificationReference plan reference bytes
  bindAdmitted plan qualified reference admitted
  Right (SupervisedQualificationPublication reference qualified)

-- | Replay portable mathematical evidence. This does not claim physical Store
-- re-admission or authenticate a source journal; both callers must supply those
-- independent boundaries before exposing an eligible product claim.
replaySupervisedQualificationReference
  :: Cohort.SupervisedCohortPlan
  -> SupervisedQualificationReference
  -> ByteString
  -> Either Text Qualification.QualifiedSupervisedCohort
replaySupervisedQualificationReference plan (SupervisedQualificationReference wire) bytes = do
  qualification <- Qualification.decodeSupervisedQualification plan bytes
  qualified <- Qualification.qualifySupervisedCohort qualification
  let raw = Qualification.supervisedQualificationToRaw qualification
      projection = Cohort.supervisedCohortPlanProjection plan
      producer = Qualification.rawQualificationProducer raw
      outcome = Qualification.supervisedQualificationIndex0Outcome qualification
  requireEqual
    "qualification receipt row"
    (Matrix.productProjectionRowId projection)
    (internalRow wire)
  requireEqual
    "qualification receipt plan"
    (Plan.planIdText (Matrix.productProjectionPlanId projection))
    (internalPlan wire)
  requireEqual
    "qualification receipt lane"
    (renderSubstrate (Matrix.productProjectionSubstrate projection))
    (internalLane wire)
  requireEqual
    "qualification receipt experiment"
    (Matrix.productProjectionExperimentHash projection)
    (internalExperiment wire)
  requireEqual
    "qualification receipt parent plan"
    (Plan.planIdText (Cohort.supervisedCohortPlanId plan))
    (internalCohortPlan wire)
  requireEqual
    "qualification artifact address"
    (Qualification.supervisedQualificationSha256 qualification)
    (internalArtifact wire)
  requireEqual
    "qualification detached object namespace"
    (supervisedQualificationObjectKey plan (internalArtifact wire))
    (internalObjectKey wire)
  requireEqual
    "qualification source identity"
    (Qualification.rawQualificationSourceSha256 producer)
    (internalSource wire)
  requireEqual
    "qualification executable identity"
    (Qualification.rawQualificationExecutableSha256 producer)
    (internalExecutable wire)
  requireEqual
    "qualification invocation identity"
    (Qualification.rawQualificationInvocationSha256 producer)
    (internalInvocation wire)
  requireEqual
    "qualification index0 initial bytes"
    (Qualification.supervisedSeedOutcomeInitialJmw1Sha256 outcome)
    (internalInitial wire)
  requireEqual
    "qualification index0 final bytes"
    (Qualification.supervisedSeedOutcomeFinalJmw1Sha256 outcome)
    (internalFinal wire)
  requireEqual
    "qualification runtime"
    ( Qualification.qualificationRuntimeSha256
        (Qualification.supervisedQualificationRuntime qualification)
    )
    (internalRuntime wire)
  requireEqual
    "qualification graph"
    ( Qualification.qualificationGraphSha256
        (Qualification.supervisedQualificationGraphMetadata qualification)
    )
    (internalGraph wire)
  requireEqual
    "qualification held-out bytes"
    ( Qualification.qualificationEvaluationSha256
        (Qualification.supervisedQualificationEvaluation qualification)
    )
    (internalEvaluation wire)
  Right qualified

bindAdmitted
  :: Cohort.SupervisedCohortPlan
  -> Qualification.QualifiedSupervisedCohort
  -> SupervisedQualificationReference
  -> Store.AdmittedCompletedCheckpoint
  -> Either Text ()
bindAdmitted plan qualified reference@(SupervisedQualificationReference wire) admitted = do
  let qualification = Qualification.qualifiedSupervisedCohortData qualified
      checkpoint = Store.admittedCompletedCheckpoint admitted
      manifest = Store.admittedCheckpointManifest checkpoint
      weights = Store.admittedCheckpointWeights checkpoint
      outcome = Qualification.supervisedQualificationIndex0Outcome qualification
      finalBytes = Qualification.supervisedSeedOutcomeFinalJmw1Bytes outcome
      raw = Qualification.supervisedQualificationToRaw qualification
  requireEqual
    "qualification exact admitted manifest"
    (internalManifest wire)
    (Store.admittedCheckpointManifestSha checkpoint)
  _ <-
    validateCompletedQualification
      False
      plan
      reference
      (Qualification.encodeSupervisedQualification qualification)
      (Store.admittedCompletedTraining admitted)
  requireEqual
    "qualification admitted experiment"
    (internalExperiment wire)
    (Checkpoint.manifestExperiment manifest)
  payload <-
    maybe
      (Left "qualification checkpoint has no supervised runtime")
      Right
      (Checkpoint.manifestSupervisedRuntime manifest)
  requireEqual
    "qualification admitted payload origin"
    Runtime.RawProductRowProjectionOrigin
    (Runtime.supervisedRuntimeOriginToRaw (Runtime.payloadOrigin payload))
  requireEqual "qualification admitted runtime row" (internalRow wire) (Runtime.payloadRowId payload)
  requireEqual
    "qualification admitted runtime PlanId"
    (internalPlan wire)
    (Runtime.payloadPlanIdText payload)
  requireEqual
    "qualification admitted dataset"
    (Qualification.rawQualificationDatasetSha256 raw)
    (Runtime.payloadDatasetSha256 payload)
  requireEqual
    "qualification admitted initial hash"
    (internalInitial wire)
    (Runtime.payloadInitialJmw1Sha256 payload)
  requireEqual
    "qualification admitted final hash"
    (internalFinal wire)
    (Runtime.payloadFinalJmw1Sha256 payload)
  requireEqual
    "qualification admitted runtime bytes"
    (serialise (Qualification.supervisedQualificationRuntime qualification))
    (serialise (Runtime.supervisedRuntimeToRaw (Runtime.payloadRuntime payload)))
  admittedMetadata <-
    maybe
      (Left "qualification checkpoint has no exact graph metadata")
      Right
      (Runtime.payloadLayerGraphMetadata payload)
  requireEqual
    "qualification admitted graph bytes"
    (serialise (Qualification.supervisedQualificationGraphMetadata qualification))
    (serialise admittedMetadata)
  requireEqual
    "qualification admitted physical JMW1"
    [finalBytes]
    (fmap Store.loadedWeightJmw1Bytes weights)
  requireEqual
    "qualification admitted device"
    (Qualification.rawSeedDeviceWitness (Qualification.supervisedSeedOutcomeToRaw outcome))
    (Device.deviceExecutionWitnessToRaw (Store.admittedCompletedDeviceWitness admitted))
  infer <- Store.prepareSupervisedGraphCheckpointInference manifest weights
  initial <-
    Initial.decodeInitialComparisonSnapshot
      (Qualification.supervisedSeedOutcomeInitialSnapshotBytes outcome)
  comparison <-
    Initial.prepareSupervisedComparison
      initial
      (Qualification.supervisedQualificationRuntime qualification)
      (Qualification.supervisedQualificationGraphMetadata qualification)
      finalBytes
  let inputs = case Qualification.supervisedQualificationEvaluation qualification of
        Qualification.RawClassificationEvaluation examples -> fmap fst examples
        Qualification.RawRegressionEvaluation _ examples -> fmap fst examples
  served <- traverse infer inputs
  replayed <- traverse (Initial.comparisonFinalInference comparison) inputs
  requireEqual "qualification exact Store serving replay" (serialise replayed) (serialise served)

-- | A pinned portable lane retains the source journal's authenticated reference
-- and independently replays its artifact. This check binds the original admitted
-- index-zero completion; it does not manufacture a new physical Store admission.
validateRetainedSupervisedQualification
  :: Cohort.SupervisedCohortPlan
  -> SupervisedQualificationReference
  -> ByteString
  -> Text
  -> Text
  -> Text
  -> Budget.CompletedTraining
  -> Either Text RetainedSupervisedQualification
validateRetainedSupervisedQualification plan reference bytes expectedManifest expectedExecutable expectedInvocation completed = do
  requireEqual
    "retained qualification manifest"
    expectedManifest
    (qualificationReferenceManifestSha256 reference)
  requireEqual
    "retained qualification executable"
    expectedExecutable
    (qualificationReferenceExecutableSha256 reference)
  requireEqual
    "retained qualification invocation"
    expectedInvocation
    (qualificationReferenceInvocationSha256 reference)
  qualified <- validateCompletedQualification True plan reference bytes completed
  review <-
    Qualification.qualificationProducerReviewIdentity
      ( Qualification.rawQualificationProducer
          (Qualification.supervisedQualificationToRaw (Qualification.qualifiedSupervisedCohortData qualified))
      )
  Right (RetainedSupervisedQualification reference qualified completed review)

validateCompletedQualification
  :: Bool
  -> Cohort.SupervisedCohortPlan
  -> SupervisedQualificationReference
  -> ByteString
  -> Budget.CompletedTraining
  -> Either Text Qualification.QualifiedSupervisedCohort
validateCompletedQualification requireScenario plan reference@(SupervisedQualificationReference wire) bytes completed = do
  qualified <- replaySupervisedQualificationReference plan reference bytes
  let qualification = Qualification.qualifiedSupervisedCohortData qualified
      outcome = Qualification.supervisedQualificationIndex0Outcome qualification
      rawOutcome = Qualification.supervisedSeedOutcomeToRaw outcome
      projection = Cohort.supervisedCohortPlanProjection plan
      metricName = Convergence.convergenceMetricName (Matrix.productProjectionConvergenceBar projection)
  requireEqual
    "qualification completed PlanId"
    (internalPlan wire)
    (Plan.planIdText (Budget.completedTrainingPlanId completed))
  requireEqual
    "qualification completed initial bytes"
    (internalInitial wire)
    (Budget.completedTrainingInitialWeightHash completed)
  requireEqual
    "qualification completed final bytes"
    (internalFinal wire)
    (Budget.completedTrainingFinalWeightHash completed)
  requireEqual
    "qualification completed update count"
    (Qualification.rawSeedObservedOptimizerUpdates rawOutcome)
    (Budget.completedTrainingUpdateCount completed)
  requireEqual
    "qualification completed epoch count"
    (Qualification.rawSeedObservedEpochs rawOutcome)
    (Budget.completedTrainingObservedUnits completed)
  requireEqual
    "qualification completed dataset"
    (Qualification.rawSeedDatasetSha256 rawOutcome)
    (Budget.completedTrainingDatasetShaAtRead completed)
  case [ observation
       | observation <- Budget.completedTrainingMetrics completed
       , Budget.coMetricName observation == metricName
       ] of
    [observation] ->
      let heldOut = case Qualification.supervisedQualificationEvaluation qualification of
            Qualification.RawClassificationEvaluation examples -> ServedMetric.HeldOutClassification examples
            Qualification.RawRegressionEvaluation scale examples -> ServedMetric.HeldOutRegression scale examples
       in ServedMetric.assertServedMetricProvenance
            (internalManifest wire)
            metricName
            (Budget.coMetricValue observation)
            heldOut
            (Qualification.supervisedQualificationIndex0Metric qualification)
    _ -> Left "qualification completed metric does not occur exactly once"
  case Budget.completedTrainingProductScenarioInvocation completed of
    Nothing -> do
      requireEqual "qualification direct execution binding" directBinding (internalBinding wire)
      when
        requireScenario
        (Left "qualification authenticated report requires an actual scenario invocation")
    Just invocation -> do
      requireEqual "qualification scenario execution binding" scenarioBinding (internalBinding wire)
      requireEqual
        "qualification completed invocation"
        (internalInvocation wire)
        (Budget.productScenarioInvocationDigest invocation)
      requireEqual
        "qualification completed executable"
        (internalExecutable wire)
        (Budget.productScenarioInvocationExecutableSha256 invocation)
  maybeDevice <- Budget.completedTrainingDeviceWitness completed
  completedDevice <- maybe (Left "qualification completed device is absent") Right maybeDevice
  requireEqual
    "qualification completed device"
    (Qualification.rawSeedDeviceWitness rawOutcome)
    (Device.deviceExecutionWitnessToRaw completedDevice)
  Right qualified

supervisedQualificationPublicationReference
  :: SupervisedQualificationPublication -> SupervisedQualificationReference
supervisedQualificationPublicationReference (SupervisedQualificationPublication reference _) = reference

supervisedQualificationPublicationData
  :: SupervisedQualificationPublication -> Qualification.QualifiedSupervisedCohort
supervisedQualificationPublicationData (SupervisedQualificationPublication _ qualified) = qualified

qualificationReferenceRowId
  , qualificationReferencePlanId
  , qualificationReferenceSubstrate
  , qualificationReferenceExperimentHash
  , qualificationReferenceManifestSha256
  , qualificationReferenceSourceSha256
  , qualificationReferenceExecutableSha256
  , qualificationReferenceInvocationSha256
  , qualificationReferenceArtifactSha256
  , qualificationReferenceObjectKey
    :: SupervisedQualificationReference -> Text
qualificationReferenceRowId (SupervisedQualificationReference wire) = internalRow wire
qualificationReferencePlanId (SupervisedQualificationReference wire) = internalPlan wire
qualificationReferenceSubstrate (SupervisedQualificationReference wire) = internalLane wire
qualificationReferenceExperimentHash (SupervisedQualificationReference wire) = internalExperiment wire
qualificationReferenceManifestSha256 (SupervisedQualificationReference wire) = internalManifest wire
qualificationReferenceSourceSha256 (SupervisedQualificationReference wire) = internalSource wire
qualificationReferenceExecutableSha256 (SupervisedQualificationReference wire) = internalExecutable wire
qualificationReferenceInvocationSha256 (SupervisedQualificationReference wire) = internalInvocation wire
qualificationReferenceArtifactSha256 (SupervisedQualificationReference wire) = internalArtifact wire
qualificationReferenceObjectKey (SupervisedQualificationReference wire) = internalObjectKey wire

requireEqual :: (Eq value) => Text -> value -> value -> Either Text ()
requireEqual label expected actual = unless (expected == actual) (Left (label <> " differs"))

requireSha :: Text -> Either Text ()
requireSha value =
  unless
    (Text.length value == 64 && Text.all (`elem` ("0123456789abcdef" :: String)) value)
    (Left "qualification receipt digest is not canonical SHA256")

validText :: Text -> Bool
validText value = not (Text.null value) && Text.strip value == value && not (Text.any isControl value)

qualificationReferenceIsScenarioBound :: SupervisedQualificationReference -> Bool
qualificationReferenceIsScenarioBound (SupervisedQualificationReference wire) = internalBinding wire == scenarioBinding

scenarioBinding, directBinding :: Text
scenarioBinding = "product-scenario-invocation-v1"
directBinding = "direct-local-attempt-v1"

-- Original code identity is retained under exact source-journal authentication;
-- this getter does not reinterpret the journal SHA as a source stamp.
retainedSupervisedQualificationSource :: RetainedSupervisedQualification -> Source.SourceStamp
retainedSupervisedQualificationSource (RetainedSupervisedQualification (SupervisedQualificationReference wire) _ _ _) = Source.SourceStamp Source.sourceDigestAlgorithm (internalSource wire)
retainedSupervisedQualificationReviewIdentity
  :: RetainedSupervisedQualification -> Maybe Review.CriterionReviewIdentityData
retainedSupervisedQualificationReviewIdentity (RetainedSupervisedQualification _ _ _ review) = review
