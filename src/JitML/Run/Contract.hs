{-# LANGUAGE DataKinds #-}
{-# LANGUAGE KindSignatures #-}

-- | Pure, total workflow-evidence contracts.
--
-- A 'Contract' has no effectful operations: callers supply already-decoded,
-- plan-bound events, receive either a typed ingest violation or new immutable
-- progress, and may ask for accumulated completion diagnostics at any time.
-- The cardinality combinators key evidence by both its semantic 'EventId' and
-- its logical key.  Only an identical redelivery carrying the same event id,
-- key, and value is idempotent; all conflicting duplicates fail closed.
module JitML.Run.Contract
  ( AtLeastOne
  , Contract
  , ContractViolation (..)
  , EvidenceEvent
  , ExactKeyed
  , ExactlyOne
  , FinalEvaluationObservation
  , LearningCurveObservation
  , MissingEvidence (..)
  , RequirementState
  , TrainingProgress
  , atLeastOne
  , atLeastOneValues
  , evidenceEvent
  , evidenceEventId
  , evidenceEventKey
  , evidenceEventPlanId
  , evidenceEventValue
  , exactKeyedRange
  , exactKeyedValues
  , exactlyOne
  , exactlyOneValue
  , finalEvaluationEventId
  , finalEvaluationMeasurement
  , finalEvaluationObservation
  , finishContract
  , ingestEvent
  , initialProgress
  , learningCurveEventId
  , learningCurveMeasurement
  , learningCurveObservation
  , mapContract
  , productContract
  , refineContract
  , selectContract
  , trainingProgress
  , trainingProgressEventId
  , trainingProgressQuantity
  )
where

import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Plan.Plan
  ( EventId
  , FiniteMeasurement
  , PlanError
  , PlanId
  , Quantity
  , Unit
  , Validation (..)
  , deriveEventIdForPlanId
  )

-- | A pure workflow contract.  The constructor stays private so contracts are
-- assembled from the total combinators in this module.
data Contract event progress evidence = Contract
  { contractInitial :: progress
  , contractIngest :: progress -> event -> Either ContractViolation progress
  , contractFinish :: progress -> Validation (NonEmpty MissingEvidence) evidence
  }

initialProgress :: Contract event progress evidence -> progress
initialProgress = contractInitial

ingestEvent
  :: Contract event progress evidence
  -> progress
  -> event
  -> Either ContractViolation progress
ingestEvent = contractIngest

finishContract
  :: Contract event progress evidence
  -> progress
  -> Validation (NonEmpty MissingEvidence) evidence
finishContract = contractFinish

-- | Transform only completed evidence; ingest semantics and progress are
-- unchanged.
mapContract
  :: (leftEvidence -> rightEvidence)
  -> Contract event progress leftEvidence
  -> Contract event progress rightEvidence
mapContract transform contract =
  Contract
    { contractInitial = contractInitial contract
    , contractIngest = contractIngest contract
    , contractFinish = fmap transform . contractFinish contract
    }

-- | Validate or refine completed evidence without weakening the underlying
-- ingest contract.  A refinement failure remains typed completion evidence:
-- the workflow cannot report success merely because every cardinality
-- requirement was present when those values disagree semantically.
refineContract
  :: (leftEvidence -> Either Text rightEvidence)
  -> Contract event progress leftEvidence
  -> Contract event progress rightEvidence
refineContract refine contract =
  Contract
    { contractInitial = contractInitial contract
    , contractIngest = contractIngest contract
    , contractFinish = \progress ->
        case contractFinish contract progress of
          Failure missing -> Failure missing
          Success evidence ->
            case refine evidence of
              Left reason -> Failure (InvalidEvidence reason :| [])
              Right refined -> Success refined
    }

-- | Lift a contract into a larger event sum.  An unrelated event is a total
-- no-op, allowing independently typed requirements to be composed without
-- treating each other's events as extras.
selectContract
  :: (outerEvent -> Maybe innerEvent)
  -> Contract innerEvent progress evidence
  -> Contract outerEvent progress evidence
selectContract select contract =
  Contract
    { contractInitial = contractInitial contract
    , contractIngest = \progress event ->
        case select event of
          Nothing -> Right progress
          Just selected -> contractIngest contract progress selected
    , contractFinish = contractFinish contract
    }

-- | Product composition feeds every event to both requirements and accumulates
-- all missing-evidence diagnostics when finishing.
productContract
  :: Contract event leftProgress leftEvidence
  -> Contract event rightProgress rightEvidence
  -> Contract event (leftProgress, rightProgress) (leftEvidence, rightEvidence)
productContract left right =
  Contract
    { contractInitial = (contractInitial left, contractInitial right)
    , contractIngest = \(leftProgress, rightProgress) event -> do
        nextLeft <- contractIngest left leftProgress event
        nextRight <- contractIngest right rightProgress event
        Right (nextLeft, nextRight)
    , contractFinish = \(leftProgress, rightProgress) ->
        (,)
          <$> contractFinish left leftProgress
          <*> contractFinish right rightProgress
    }

-- | Evidence stamped with its resolved-plan identity and opaque semantic event
-- identity.  The smart constructor deliberately accepts only opaque plan/event
-- ids supplied by "JitML.Plan.Plan".
data EvidenceEvent key value = EvidenceEvent
  { eventPlanIdValue :: PlanId
  , eventIdValue :: EventId
  , eventKeyValue :: key
  , eventPayloadValue :: value
  }
  deriving stock (Eq, Show)

evidenceEvent
  :: (Show key)
  => PlanId
  -> Text
  -> key
  -> value
  -> Validation (NonEmpty PlanError) (EvidenceEvent key value)
evidenceEvent planId eventKind key value =
  (\eventId -> EvidenceEvent planId eventId key value)
    <$> deriveEventIdForPlanId planId eventKind (renderKey key)

-- Keep the constructor and record labels private.  Exported record labels can
-- be used in record-update syntax even when their constructor is hidden,
-- allowing callers to desynchronise a validated EventId from its plan/key.
evidenceEventPlanId :: EvidenceEvent key value -> PlanId
evidenceEventPlanId = eventPlanIdValue

evidenceEventId :: EvidenceEvent key value -> EventId
evidenceEventId = eventIdValue

evidenceEventKey :: EvidenceEvent key value -> key
evidenceEventKey = eventKeyValue

evidenceEventValue :: EvidenceEvent key value -> value
evidenceEventValue = eventPayloadValue

data ContractViolation
  = WrongPlan
      { violationRequirement :: Text
      , violationExpectedPlan :: PlanId
      , violationObservedPlan :: PlanId
      }
  | ConflictingDuplicate
      { violationRequirement :: Text
      , violationKey :: Text
      , violationExistingEventId :: EventId
      , violationIncomingEventId :: EventId
      }
  | OutOfRangeKey
      { violationRequirement :: Text
      , violationKey :: Text
      }
  deriving stock (Eq, Show)

data MissingEvidence
  = MissingExactlyOne Text
  | MissingAtLeastOne Text
  | MissingKeys Text (NonEmpty Text)
  | InvalidEvidence Text
  deriving stock (Eq, Show)

-- | The two indexes make the duplicate rules explicit: a semantic event id may
-- name only one keyed value, and a logical key may be populated by only one
-- semantic event id.
data RequirementState key value = RequirementState
  { requirementByKey :: Map key (EventId, value)
  , requirementByEventId :: Map EventId (key, value)
  }
  deriving stock (Eq, Show)

emptyRequirementState :: RequirementState key value
emptyRequirementState = RequirementState Map.empty Map.empty

newtype ExactlyOne value = ExactlyOne value
  deriving stock (Eq, Show)

newtype AtLeastOne key value = AtLeastOne (NonEmpty (key, value))
  deriving stock (Eq, Show)

newtype ExactKeyed key value = ExactKeyed (Map key value)
  deriving stock (Eq, Show)

exactlyOneValue :: ExactlyOne value -> value
exactlyOneValue (ExactlyOne value) = value

atLeastOneValues :: AtLeastOne key value -> NonEmpty (key, value)
atLeastOneValues (AtLeastOne values) = values

exactKeyedValues :: ExactKeyed key value -> Map key value
exactKeyedValues (ExactKeyed values) = values

exactlyOne
  :: (Eq value)
  => Text
  -> PlanId
  -> Contract
       (EvidenceEvent () value)
       (RequirementState () value)
       (ExactlyOne value)
exactlyOne label expectedPlan =
  Contract
    { contractInitial = emptyRequirementState
    , contractIngest =
        recordEvidence label expectedPlan Nothing
    , contractFinish = \progress ->
        case Map.elems (requirementByKey progress) of
          [] -> Failure (MissingExactlyOne label :| [])
          [(_eventId, value)] -> Success (ExactlyOne value)
          -- The unit key and duplicate rules make this branch unreachable, but
          -- retaining a total case keeps completion independent of invariants
          -- hidden in partial pattern matches.
          _ -> Failure (MissingExactlyOne label :| [])
    }

atLeastOne
  :: (Ord key, Show key, Eq value)
  => Text
  -> PlanId
  -> Contract
       (EvidenceEvent key value)
       (RequirementState key value)
       (AtLeastOne key value)
atLeastOne label expectedPlan =
  Contract
    { contractInitial = emptyRequirementState
    , contractIngest = recordEvidence label expectedPlan Nothing
    , contractFinish = \progress ->
        case Map.toAscList (fmap snd (requirementByKey progress)) of
          [] -> Failure (MissingAtLeastOne label :| [])
          first : rest -> Success (AtLeastOne (first :| rest))
    }

exactKeyedRange
  :: (Ord key, Show key, Eq value)
  => Text
  -> PlanId
  -> NonEmpty key
  -> Contract
       (EvidenceEvent key value)
       (RequirementState key value)
       (ExactKeyed key value)
exactKeyedRange label expectedPlan expectedKeys =
  Contract
    { contractInitial = emptyRequirementState
    , contractIngest =
        recordEvidence label expectedPlan (Just expectedSet)
    , contractFinish = \progress ->
        let missing = Set.toAscList (expectedSet `Set.difference` Map.keysSet (requirementByKey progress))
         in case fmap renderKey missing of
              [] ->
                Success
                  (ExactKeyed (fmap snd (requirementByKey progress)))
              first : rest -> Failure (MissingKeys label (first :| rest) :| [])
    }
 where
  expectedSet = Set.fromList (nonEmptyToList expectedKeys)

recordEvidence
  :: (Ord key, Show key, Eq value)
  => Text
  -> PlanId
  -> Maybe (Set key)
  -> RequirementState key value
  -> EvidenceEvent key value
  -> Either ContractViolation (RequirementState key value)
recordEvidence label expectedPlan allowedKeys progress event
  | evidenceEventPlanId event /= expectedPlan =
      Left
        WrongPlan
          { violationRequirement = label
          , violationExpectedPlan = expectedPlan
          , violationObservedPlan = evidenceEventPlanId event
          }
  | Just allowed <- allowedKeys
  , evidenceEventKey event `Set.notMember` allowed =
      Left
        OutOfRangeKey
          { violationRequirement = label
          , violationKey = renderKey (evidenceEventKey event)
          }
  | Just (existingKey, existingValue) <-
      Map.lookup (evidenceEventId event) (requirementByEventId progress) =
      if existingKey == evidenceEventKey event && existingValue == evidenceEventValue event
        then Right progress
        else
          Left
            ( duplicateViolation
                label
                (evidenceEventKey event)
                (evidenceEventId event)
                (evidenceEventId event)
            )
  | Just (existingEventId, _existingValue) <-
      Map.lookup (evidenceEventKey event) (requirementByKey progress) =
      Left
        ( duplicateViolation
            label
            (evidenceEventKey event)
            existingEventId
            (evidenceEventId event)
        )
  | otherwise =
      Right
        RequirementState
          { requirementByKey =
              Map.insert
                (evidenceEventKey event)
                (evidenceEventId event, evidenceEventValue event)
                (requirementByKey progress)
          , requirementByEventId =
              Map.insert
                (evidenceEventId event)
                (evidenceEventKey event, evidenceEventValue event)
                (requirementByEventId progress)
          }

duplicateViolation :: (Show key) => Text -> key -> EventId -> EventId -> ContractViolation
duplicateViolation label key existing incoming =
  ConflictingDuplicate
    { violationRequirement = label
    , violationKey = renderKey key
    , violationExistingEventId = existing
    , violationIncomingEventId = incoming
    }

renderKey :: (Show key) => key -> Text
renderKey = Text.pack . show

nonEmptyToList :: NonEmpty value -> [value]
nonEmptyToList (first :| rest) = first : rest

-- | Nominally distinct evidence wrappers prevent a learning-curve sample or a
-- final-policy evaluation from being substituted for execution progress.
data TrainingProgress (unit :: Unit) = TrainingProgress
  { trainingProgressEventId :: EventId
  , trainingProgressQuantity :: Quantity unit
  }
  deriving stock (Eq, Show)

trainingProgress :: EventId -> Quantity unit -> TrainingProgress unit
trainingProgress = TrainingProgress

data LearningCurveObservation = LearningCurveObservation
  { learningCurveEventId :: EventId
  , learningCurveMeasurement :: FiniteMeasurement
  }
  deriving stock (Eq, Show)

learningCurveObservation
  :: EventId
  -> FiniteMeasurement
  -> LearningCurveObservation
learningCurveObservation = LearningCurveObservation

data FinalEvaluationObservation = FinalEvaluationObservation
  { finalEvaluationEventId :: EventId
  , finalEvaluationMeasurement :: FiniteMeasurement
  }
  deriving stock (Eq, Show)

finalEvaluationObservation
  :: EventId
  -> FiniteMeasurement
  -> FinalEvaluationObservation
finalEvaluationObservation = FinalEvaluationObservation
