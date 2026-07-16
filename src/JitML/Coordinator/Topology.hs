{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

-- | The Coordinator-owned Pulsar topology.
--
-- A protocol route fixes both the broker address and the payload type.  The
-- @Topic event@ constructor and its decoder are private, so callers can obtain
-- (for example) a @Topic TrainingCommand@ only through
-- @TrainingCommandRoute@.  Bootstrap uses 'AnyTopic' solely to forget the
-- payload parameter while reconciling addresses.
module JitML.Coordinator.Topology
  ( Topic
  , AnyTopic
  , TopicAddress
  , TopicError (..)
  , TopicDecodeError (..)
  , InferenceResultMessage
  , WorkflowStatusMessage
  , Workflow (..)
  , Phase (..)
  , ProtocolRoute (..)
  , RouteEntry (..)
  , topicFor
  , resolveTopic
  , decodeTopicPayload
  , encodeTopicPayload
  , topicName
  , topicLogicalName
  , topicSubstrate
  , topicWorkflow
  , topicPhase
  , anyTopicName
  , anyTopicLogicalName
  , anyTopicSubstrate
  , topicAddressName
  , mkInferenceResultMessage
  , mkWorkflowStatusMessage
  , inferenceResultMessagePayload
  , workflowStatusMessagePayload
  , jitmlTopology
  , topologyTopics
  , coordinatorTopics
  , validateTopology
  , topologyLogicalNames
  )
where

import Data.Foldable (traverse_)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Text.Read (readMaybe)

import JitML.Proto.Gc
  ( GcReapedEvent
  , gcEventSubstrate
  , parseGcReapedEvent
  , renderGcReapedEvent
  )
import JitML.Proto.Inference
  ( AdversarialMoveCommand (amcReplyTopic)
  , CheckpointCompareCommand (cccReplyTopic)
  , InferenceCommand (..)
  , InferenceRequest (irReplyTopic)
  , ListCheckpointsCommand (lccReplyTopic)
  , LoadTranscriptCommand (ltcReplyTopic)
  , parseInferenceCommand
  , renderInferenceCommand
  )
import JitML.Proto.Rl
  ( RlCommand (..)
  , RlEvent
  , StartAlphaZeroRun (sazSubstrate)
  , StartRLRun (srlSubstrate)
  , parseRlCommand
  , parseRlEvent
  , renderRlCommand
  , renderRlEvent
  )
import JitML.Proto.Training
  ( StartTraining (stSubstrate)
  , TrainingCommand (..)
  , TrainingEvent
  , parseTrainingCommand
  , parseTrainingEvent
  , renderTrainingCommand
  , renderTrainingEvent
  )
import JitML.Proto.Tune
  ( StartSweep (ssSubstrate)
  , TuneCommand (..)
  , TuneEvent
  , parseTuneCommand
  , parseTuneEvent
  , renderTuneCommand
  , renderTuneEvent
  )
import JitML.Substrate (Substrate (..), allSubstrates, renderSubstrate)

-- | A validated address.  This type deliberately carries no codec and is used
-- only by topology validation, never by publication or consumption.
data TopicAddress = TopicAddress
  { addressName :: Text
  , addressLogicalName :: Text
  , addressWorkflow :: Workflow
  , addressPhase :: Phase
  , addressSubstrate :: Substrate
  }
  deriving stock (Eq, Ord, Show)

-- | A validated route whose phantom parameter is the only payload the route
-- can decode.  The constructor is private.
data Topic event = Topic
  { typedTopicAddress :: TopicAddress
  , typedTopicDecoder :: Text -> Either TopicDecodeError event
  , typedTopicEncoder :: event -> Text
  }

instance Eq (Topic event) where
  left == right = typedTopicAddress left == typedTopicAddress right

instance Ord (Topic event) where
  compare left right = compare (typedTopicAddress left) (typedTopicAddress right)

instance Show (Topic event) where
  showsPrec precedence = showsPrec precedence . typedTopicAddress

-- | Existential address used by the Coordinator bootstrap.  It cannot be used
-- to create a typed subscription without first selecting a protocol route.
data AnyTopic where
  AnyTopic :: Topic event -> AnyTopic

instance Eq AnyTopic where
  left == right = anyTopicName left == anyTopicName right

instance Ord AnyTopic where
  compare left right = compare (anyTopicName left) (anyTopicName right)

instance Show AnyTopic where
  showsPrec precedence = showsPrec precedence . anyTopicName

data TopicError
  = TopicRouteNotRegistered Workflow Phase Substrate
  | TopicTextDoesNotMatch Text Text
  deriving stock (Eq, Show)

data TopicDecodeError = TopicDecodeError
  { topicDecodeErrorTopic :: Text
  , topicDecodeErrorDetail :: Text
  }
  deriving stock (Eq, Show)

-- | A validated member of the heterogeneous inference-result wire family.
-- Consumers that expect a narrower result may refine its retained payload
-- further; unknown or malformed result kinds never reach the handler.
newtype InferenceResultMessage = InferenceResultMessage Text
  deriving stock (Eq, Show)

-- | A validated browser workflow-status frame.
newtype WorkflowStatusMessage = WorkflowStatusMessage Text
  deriving stock (Eq, Show)

inferenceResultMessagePayload :: InferenceResultMessage -> Text
inferenceResultMessagePayload (InferenceResultMessage payload) = payload

workflowStatusMessagePayload :: WorkflowStatusMessage -> Text
workflowStatusMessagePayload (WorkflowStatusMessage payload) = payload

-- | Refine a rendered member of the heterogeneous inference-result family.
-- The wrapper remains opaque, so arbitrary text cannot be published through a
-- @Topic InferenceResultMessage@. Repeated @checkpoint-summary@ and
-- @row-selector@ fields remain legal for the checkpoint-list member; all
-- required scalar fields are unique.
mkInferenceResultMessage :: Text -> Either Text InferenceResultMessage
mkInferenceResultMessage payload = do
  fields <- parsePayloadFields payload
  kind <- requireNonEmptyPayloadField "kind" fields
  _ <- requireNonEmptyPayloadField "call-id" fields
  case kind of
    "InferenceResult" -> validateInferenceResult fields
    "CheckpointCompareResult" -> validateCheckpointCompareResult fields
    "AdversarialMoveResult" -> validateAdversarialMoveResult fields
    "CheckpointList" -> validateCheckpointListResult fields
    "TranscriptReplay" -> validateTranscriptReplayResult fields
    _ -> Left "unknown inference result kind"
  pure (InferenceResultMessage payload)

validateInferenceResult :: [(Text, Text)] -> Either Text ()
validateInferenceResult fields = do
  _ <- requireNonEmptyPayloadField "experiment-hash" fields
  validateFiniteDoubleListField "output" fields
  case payloadFieldValues "decoded-kind" fields of
    [] -> requireOnlyPayloadFields inferenceResultBaseFields fields
    [_decodedKind] -> validateDecodedInferenceResult fields
    _ -> Left "duplicate payload field: decoded-kind"

inferenceResultBaseFields :: [Text]
inferenceResultBaseFields = ["kind", "call-id", "experiment-hash", "output"]

validateDecodedInferenceResult :: [(Text, Text)] -> Either Text ()
validateDecodedInferenceResult fields = do
  decodedKind <- requireNonEmptyPayloadField "decoded-kind" fields
  case decodedKind of
    "classification" -> do
      requireOnlyPayloadFields
        ( inferenceResultBaseFields
            <> [ "decoded-kind"
               , "decoded-top-class"
               , "decoded-confidence"
               , "decoded-probabilities"
               , "decoded-labels"
               ]
        )
        fields
      _ <- requireParsedPayloadField "decoded-top-class" parseIntText fields
      validateFiniteDoubleField "decoded-confidence" fields
      validateFiniteDoubleListField "decoded-probabilities" fields
      _ <- requirePayloadField "decoded-labels" fields
      Right ()
    "regression" -> do
      requireOnlyPayloadFields
        (inferenceResultBaseFields <> ["decoded-kind", "decoded-values", "decoded-units"])
        fields
      validateFiniteDoubleListField "decoded-values" fields
      _ <- requirePayloadField "decoded-units" fields
      Right ()
    "policy" -> do
      requireOnlyPayloadFields
        (inferenceResultBaseFields <> ["decoded-kind", "decoded-probabilities", "decoded-labels"])
        fields
      validateFiniteDoubleListField "decoded-probabilities" fields
      _ <- requirePayloadField "decoded-labels" fields
      Right ()
    "value" -> do
      requireOnlyPayloadFields
        (inferenceResultBaseFields <> ["decoded-kind", "decoded-value"])
        fields
      validateFiniteDoubleField "decoded-value" fields
    "mcts" -> do
      requireOnlyPayloadFields
        (inferenceResultBaseFields <> ["decoded-kind", "decoded-visits"])
        fields
      validateFiniteDoubleListField "decoded-visits" fields
    "replay" -> validateDecodedOutput fields
    "generic" -> validateDecodedOutput fields
    _ -> Left "unknown decoded inference result kind"
 where
  validateDecodedOutput decodedFields = do
    requireOnlyPayloadFields
      (inferenceResultBaseFields <> ["decoded-kind", "decoded-output"])
      decodedFields
    validateFiniteDoubleListField "decoded-output" decodedFields

validateCheckpointCompareResult :: [(Text, Text)] -> Either Text ()
validateCheckpointCompareResult fields = do
  requireOnlyPayloadFields
    [ "kind"
    , "call-id"
    , "baseline-experiment-hash"
    , "candidate-experiment-hash"
    , "baseline-output"
    , "candidate-output"
    , "max-abs-delta"
    , "mean-abs-delta"
    ]
    fields
  _ <- requireNonEmptyPayloadField "baseline-experiment-hash" fields
  _ <- requireNonEmptyPayloadField "candidate-experiment-hash" fields
  validateFiniteDoubleListField "baseline-output" fields
  validateFiniteDoubleListField "candidate-output" fields
  validateFiniteDoubleField "max-abs-delta" fields
  validateFiniteDoubleField "mean-abs-delta" fields

validateAdversarialMoveResult :: [(Text, Text)] -> Either Text ()
validateAdversarialMoveResult fields = do
  requireOnlyPayloadFields
    [ "kind"
    , "call-id"
    , "experiment-hash"
    , "game"
    , "chosen-column"
    , "legal-moves"
    , "visit-counts"
    , "policy-priors"
    , "value-estimate"
    , "game-over"
    , "transcript-id"
    ]
    fields
  _ <- requireNonEmptyPayloadField "experiment-hash" fields
  _ <- requireNonEmptyPayloadField "game" fields
  _ <- requireParsedPayloadField "chosen-column" parseIntText fields
  validateIntListField "legal-moves" fields
  validateIntListField "visit-counts" fields
  validateFiniteDoubleListField "policy-priors" fields
  validateFiniteDoubleField "value-estimate" fields
  _ <- requireParsedPayloadField "game-over" parseBoolText fields
  _ <- requireNonEmptyPayloadField "transcript-id" fields
  Right ()

validateCheckpointListResult :: [(Text, Text)] -> Either Text ()
validateCheckpointListResult fields = do
  requireOnlyPayloadFields
    [ "kind"
    , "call-id"
    , "panel"
    , "status"
    , "count"
    , "selector-state"
    , "row-selector"
    , "checkpoint-summary"
    ]
    fields
  requirePayloadFieldEquals "panel" "checkpoint-browse" fields
  requirePayloadFieldEquals "status" "published" fields
  count <- requireParsedPayloadField "count" parseNonNegativeIntText fields
  _ <- requireNonEmptyPayloadField "selector-state" fields
  traverse_ requireNonEmptyRepeatedField (payloadFieldValues "row-selector" fields)
  traverse_ requireNonEmptyRepeatedField (payloadFieldValues "checkpoint-summary" fields)
  if count == length (payloadFieldValues "checkpoint-summary" fields)
    then Right ()
    else Left "checkpoint result count does not match checkpoint-summary fields"

validateTranscriptReplayResult :: [(Text, Text)] -> Either Text ()
validateTranscriptReplayResult fields = do
  requireOnlyPayloadFields
    [ "kind"
    , "call-id"
    , "panel"
    , "transcript-id"
    , "game"
    , "experiment-hash"
    , "moves"
    , "analysis"
    ]
    fields
  requirePayloadFieldEquals "panel" "transcript-replay" fields
  _ <- requireNonEmptyPayloadField "transcript-id" fields
  _ <- requirePayloadField "game" fields
  _ <- requirePayloadField "experiment-hash" fields
  validateIntListField "moves" fields
  _ <- requirePayloadField "analysis" fields
  Right ()

-- | Refine the exact workflow-status frame consumed by the browser bridge.
-- Detail is deliberately a single scalar line; embedded newlines are rejected
-- rather than being reinterpreted as additional fields.
mkWorkflowStatusMessage :: Text -> Either Text WorkflowStatusMessage
mkWorkflowStatusMessage payload = do
  fields <- parsePayloadFields payload
  requireOnlyPayloadFields ["kind", "panel", "run-id", "status", "detail"] fields
  requirePayloadFieldEquals "kind" "WorkflowStatus" fields
  requirePayloadFieldEquals "panel" "workflow-status" fields
  _ <- requireNonEmptyPayloadField "run-id" fields
  status <- requireNonEmptyPayloadField "status" fields
  if status `elem` ["queued", "running", "done", "failed"]
    then Right ()
    else Left "unknown workflow status"
  detail <- requireNonEmptyPayloadField "detail" fields
  if Text.any (`elem` ['\n', '\r']) detail
    then Left "workflow status detail must be a single line"
    else Right (WorkflowStatusMessage payload)

data Workflow
  = Train
  | Tune
  | Rl
  | Infer
  | Gc
  | WorkflowState
  deriving stock (Eq, Ord, Show, Enum, Bounded)

data Phase
  = Command
  | Event
  | Result
  | Request
  | HostCommand
  | Status
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | Closed protocol witness.  Unlike 'RouteEntry', each constructor fixes the
-- decoded payload type and codec.  'RouteEntry' remains the independently
-- constructible descriptor used by graph-validation tests.
data ProtocolRoute event where
  TrainingCommandRoute :: ProtocolRoute TrainingCommand
  TrainingEventRoute :: ProtocolRoute TrainingEvent
  TrainingHostCommandRoute :: ProtocolRoute TrainingCommand
  TuneCommandRoute :: ProtocolRoute TuneCommand
  TuneEventRoute :: ProtocolRoute TuneEvent
  TuneHostCommandRoute :: ProtocolRoute TuneCommand
  RlCommandRoute :: ProtocolRoute RlCommand
  RlEventRoute :: ProtocolRoute RlEvent
  RlHostCommandRoute :: ProtocolRoute RlCommand
  InferenceRequestRoute :: ProtocolRoute InferenceCommand
  InferenceHostCommandRoute :: ProtocolRoute InferenceCommand
  InferenceResultRoute :: ProtocolRoute InferenceResultMessage
  GcEventRoute :: ProtocolRoute GcReapedEvent
  WorkflowStatusRoute :: ProtocolRoute WorkflowStatusMessage

data RouteEntry = RouteEntry
  { reWorkflow :: Workflow
  , rePhase :: Phase
  , reLanes :: [Substrate]
  }
  deriving stock (Eq, Show)

topicFor :: ProtocolRoute event -> Substrate -> Either TopicError (Topic event)
topicFor route lane
  | routeRegistered workflow phase lane =
      Right
        Topic
          { typedTopicAddress = renderAddress workflow phase lane
          , typedTopicDecoder = decoderFor route (addressName (renderAddress workflow phase lane)) lane
          , typedTopicEncoder = encoderFor route
          }
  | otherwise = Left (TopicRouteNotRegistered workflow phase lane)
 where
  workflow = routeWorkflow route
  phase = routePhase route

resolveTopic
  :: ProtocolRoute event
  -> Substrate
  -> Text
  -> Either TopicError (Topic event)
resolveTopic route lane supplied = do
  expected <- topicFor route lane
  let stripped = Text.strip supplied
  if stripped == topicName expected || stripped == topicLogicalName expected
    then Right expected
    else Left (TopicTextDoesNotMatch stripped (topicName expected))

decodeTopicPayload :: Topic event -> Text -> Either TopicDecodeError event
decodeTopicPayload = typedTopicDecoder

encodeTopicPayload :: Topic event -> event -> Text
encodeTopicPayload = typedTopicEncoder

topicName :: Topic event -> Text
topicName = addressName . typedTopicAddress

topicLogicalName :: Topic event -> Text
topicLogicalName = addressLogicalName . typedTopicAddress

topicWorkflow :: Topic event -> Workflow
topicWorkflow = addressWorkflow . typedTopicAddress

topicPhase :: Topic event -> Phase
topicPhase = addressPhase . typedTopicAddress

topicSubstrate :: Topic event -> Substrate
topicSubstrate = addressSubstrate . typedTopicAddress

anyTopicName :: AnyTopic -> Text
anyTopicName (AnyTopic topic) = topicName topic

anyTopicLogicalName :: AnyTopic -> Text
anyTopicLogicalName (AnyTopic topic) = topicLogicalName topic

anyTopicSubstrate :: AnyTopic -> Substrate
anyTopicSubstrate (AnyTopic topic) = topicSubstrate topic

topicAddressName :: TopicAddress -> Text
topicAddressName = addressName

renderAddress :: Workflow -> Phase -> Substrate -> TopicAddress
renderAddress workflow phase lane =
  TopicAddress
    { addressName = "persistent://public/default/" <> logical
    , addressLogicalName = logical
    , addressWorkflow = workflow
    , addressPhase = phase
    , addressSubstrate = lane
    }
 where
  logical = workflowSegment workflow <> "." <> phaseSegment phase <> "." <> renderSubstrate lane

routeRegistered :: Workflow -> Phase -> Substrate -> Bool
routeRegistered workflow phase lane =
  any
    (\entry -> reWorkflow entry == workflow && rePhase entry == phase && lane `elem` reLanes entry)
    jitmlTopology

routeWorkflow :: ProtocolRoute event -> Workflow
routeWorkflow TrainingCommandRoute = Train
routeWorkflow TrainingEventRoute = Train
routeWorkflow TrainingHostCommandRoute = Train
routeWorkflow TuneCommandRoute = Tune
routeWorkflow TuneEventRoute = Tune
routeWorkflow TuneHostCommandRoute = Tune
routeWorkflow RlCommandRoute = Rl
routeWorkflow RlEventRoute = Rl
routeWorkflow RlHostCommandRoute = Rl
routeWorkflow InferenceRequestRoute = Infer
routeWorkflow InferenceHostCommandRoute = Infer
routeWorkflow InferenceResultRoute = Infer
routeWorkflow GcEventRoute = Gc
routeWorkflow WorkflowStatusRoute = WorkflowState

routePhase :: ProtocolRoute event -> Phase
routePhase TrainingCommandRoute = Command
routePhase TrainingEventRoute = Event
routePhase TrainingHostCommandRoute = HostCommand
routePhase TuneCommandRoute = Command
routePhase TuneEventRoute = Event
routePhase TuneHostCommandRoute = HostCommand
routePhase RlCommandRoute = Command
routePhase RlEventRoute = Event
routePhase RlHostCommandRoute = HostCommand
routePhase InferenceRequestRoute = Request
routePhase InferenceHostCommandRoute = Command
routePhase InferenceResultRoute = Result
routePhase GcEventRoute = Event
routePhase WorkflowStatusRoute = Status

decoderFor
  :: ProtocolRoute event
  -> Text
  -> Substrate
  -> Text
  -> Either TopicDecodeError event
decoderFor route address lane payload =
  case route of
    TrainingCommandRoute -> decodeTrainingCommandMessage address lane payload
    TrainingEventRoute -> fromMaybeDecode address "TrainingEvent" (parseTrainingEvent payload)
    TrainingHostCommandRoute -> decodeTrainingCommandMessage address lane payload
    TuneCommandRoute -> decodeTuneCommandMessage address lane payload
    TuneEventRoute -> fromMaybeDecode address "TuneEvent" (parseTuneEvent payload)
    TuneHostCommandRoute -> decodeTuneCommandMessage address lane payload
    RlCommandRoute -> decodeRlCommandMessage address lane payload
    RlEventRoute -> fromMaybeDecode address "RlEvent" (parseRlEvent payload)
    RlHostCommandRoute -> decodeRlCommandMessage address lane payload
    InferenceRequestRoute -> decodeInferenceCommandMessage address lane payload
    InferenceHostCommandRoute -> decodeInferenceCommandMessage address lane payload
    InferenceResultRoute -> decodeInferenceResultMessage address payload
    GcEventRoute -> decodeGcReapedEventMessage address lane payload
    WorkflowStatusRoute -> decodeWorkflowStatusMessage address payload

encoderFor :: ProtocolRoute event -> event -> Text
encoderFor route =
  case route of
    TrainingCommandRoute -> renderTrainingCommand
    TrainingEventRoute -> renderTrainingEvent
    TrainingHostCommandRoute -> renderTrainingCommand
    TuneCommandRoute -> renderTuneCommand
    TuneEventRoute -> renderTuneEvent
    TuneHostCommandRoute -> renderTuneCommand
    RlCommandRoute -> renderRlCommand
    RlEventRoute -> renderRlEvent
    RlHostCommandRoute -> renderRlCommand
    InferenceRequestRoute -> renderInferenceCommand
    InferenceHostCommandRoute -> renderInferenceCommand
    InferenceResultRoute -> inferenceResultMessagePayload
    GcEventRoute -> renderGcReapedEvent
    WorkflowStatusRoute -> workflowStatusMessagePayload

fromMaybeDecode :: Text -> Text -> Maybe event -> Either TopicDecodeError event
fromMaybeDecode address expected =
  maybe
    (Left (TopicDecodeError address ("malformed " <> expected <> " payload")))
    Right

decodeTrainingCommandMessage
  :: Text
  -> Substrate
  -> Text
  -> Either TopicDecodeError TrainingCommand
decodeTrainingCommandMessage address lane payload = do
  command <- fromMaybeDecode address "TrainingCommand" (parseTrainingCommand payload)
  case command of
    TrainingStart start -> requirePayloadLane address "training command" lane (stSubstrate start) command
    TrainingStop _ -> Right command

decodeTuneCommandMessage
  :: Text
  -> Substrate
  -> Text
  -> Either TopicDecodeError TuneCommand
decodeTuneCommandMessage address lane payload = do
  command <- fromMaybeDecode address "TuneCommand" (parseTuneCommand payload)
  case command of
    TuneStart start -> requirePayloadLane address "tune command" lane (ssSubstrate start) command
    TuneStop _ -> Right command

decodeRlCommandMessage
  :: Text
  -> Substrate
  -> Text
  -> Either TopicDecodeError RlCommand
decodeRlCommandMessage address lane payload = do
  command <- fromMaybeDecode address "RlCommand" (parseRlCommand payload)
  case command of
    RlStart start -> requirePayloadLane address "rl command" lane (srlSubstrate start) command
    RlStartAlphaZero start ->
      requirePayloadLane address "rl command" lane (sazSubstrate start) command
    RlStop _ -> Right command

decodeInferenceCommandMessage
  :: Text
  -> Substrate
  -> Text
  -> Either TopicDecodeError InferenceCommand
decodeInferenceCommandMessage address lane payload = do
  command <- fromMaybeDecode address "InferenceCommand" (parseInferenceCommand payload)
  case resolveTopic InferenceResultRoute lane (inferenceCommandReplyTopic command) of
    Right _ -> Right command
    Left err ->
      Left
        ( TopicDecodeError
            address
            ( "inference reply topic does not match input topic lane: "
                <> Text.pack (show err)
            )
        )

inferenceCommandReplyTopic :: InferenceCommand -> Text
inferenceCommandReplyTopic command =
  case command of
    RunInference request -> irReplyTopic request
    CompareCheckpoints request -> cccReplyTopic request
    SelectAdversarialMove request -> amcReplyTopic request
    ListCheckpoints request -> lccReplyTopic request
    LoadTranscript request -> ltcReplyTopic request

requirePayloadLane
  :: Text
  -> Text
  -> Substrate
  -> Substrate
  -> event
  -> Either TopicDecodeError event
requirePayloadLane address family expected actual event
  | actual == expected = Right event
  | otherwise =
      Left
        ( TopicDecodeError
            address
            ( family
                <> " substrate does not match topic lane: "
                <> renderSubstrate actual
                <> " /= "
                <> renderSubstrate expected
            )
        )

decodeInferenceResultMessage :: Text -> Text -> Either TopicDecodeError InferenceResultMessage
decodeInferenceResultMessage address payload =
  case mkInferenceResultMessage payload of
    Right message -> Right message
    Left detail -> Left (TopicDecodeError address detail)

decodeWorkflowStatusMessage :: Text -> Text -> Either TopicDecodeError WorkflowStatusMessage
decodeWorkflowStatusMessage address payload =
  case mkWorkflowStatusMessage payload of
    Right message -> Right message
    Left detail -> Left (TopicDecodeError address detail)

decodeGcReapedEventMessage
  :: Text
  -> Substrate
  -> Text
  -> Either TopicDecodeError GcReapedEvent
decodeGcReapedEventMessage address lane payload =
  case parseGcReapedEvent payload of
    Left detail -> Left (TopicDecodeError address detail)
    Right event
      | gcEventSubstrate event == lane -> Right event
      | otherwise ->
          Left
            ( TopicDecodeError
                address
                ( "gc event substrate does not match topic lane: "
                    <> renderSubstrate (gcEventSubstrate event)
                    <> " /= "
                    <> renderSubstrate lane
                )
            )

parsePayloadFields :: Text -> Either Text [(Text, Text)]
parsePayloadFields payload =
  traverse parseField (Text.lines payload)
 where
  parseField line =
    let (key, rest) = Text.breakOn ":" line
        strippedKey = Text.strip key
     in if Text.null rest || Text.null strippedKey
          then Left "malformed payload field"
          else Right (strippedKey, Text.strip (Text.drop 1 rest))

payloadFieldValues :: Text -> [(Text, Text)] -> [Text]
payloadFieldValues wanted fields =
  [value | (key, value) <- fields, key == wanted]

requirePayloadField :: Text -> [(Text, Text)] -> Either Text Text
requirePayloadField wanted fields =
  case payloadFieldValues wanted fields of
    [value] -> Right value
    [] -> Left ("missing payload field: " <> wanted)
    _ -> Left ("duplicate payload field: " <> wanted)

requireNonEmptyPayloadField :: Text -> [(Text, Text)] -> Either Text Text
requireNonEmptyPayloadField wanted fields = do
  value <- requirePayloadField wanted fields
  if Text.null value
    then Left ("empty payload field: " <> wanted)
    else Right value

requirePayloadFieldEquals
  :: Text
  -> Text
  -> [(Text, Text)]
  -> Either Text ()
requirePayloadFieldEquals wanted expected fields = do
  actual <- requirePayloadField wanted fields
  if actual == expected
    then Right ()
    else Left ("unexpected payload field: " <> wanted)

requireOnlyPayloadFields :: [Text] -> [(Text, Text)] -> Either Text ()
requireOnlyPayloadFields allowed fields
  | all ((`elem` allowed) . fst) fields = Right ()
  | otherwise = Left "unknown payload field"

requireParsedPayloadField
  :: Text
  -> (Text -> Maybe value)
  -> [(Text, Text)]
  -> Either Text value
requireParsedPayloadField wanted parseValue fields = do
  encoded <- requirePayloadField wanted fields
  case parseValue encoded of
    Just value -> Right value
    Nothing -> Left ("invalid payload field: " <> wanted)

validateFiniteDoubleField :: Text -> [(Text, Text)] -> Either Text ()
validateFiniteDoubleField wanted fields = do
  _ <- requireParsedPayloadField wanted parseFiniteDoubleText fields
  Right ()

validateFiniteDoubleListField :: Text -> [(Text, Text)] -> Either Text ()
validateFiniteDoubleListField wanted fields = do
  _ <- requireParsedPayloadField wanted (parseCommaList parseFiniteDoubleText) fields
  Right ()

validateIntListField :: Text -> [(Text, Text)] -> Either Text ()
validateIntListField wanted fields = do
  _ <- requireParsedPayloadField wanted (parseCommaList parseIntText) fields
  Right ()

parseCommaList :: (Text -> Maybe value) -> Text -> Maybe [value]
parseCommaList parseValue encoded
  | Text.null (Text.strip encoded) = Just []
  | otherwise = traverse (parseValue . Text.strip) (Text.splitOn "," encoded)

parseFiniteDoubleText :: Text -> Maybe Double
parseFiniteDoubleText encoded = do
  value <- readMaybe (Text.unpack encoded)
  if isNaN value || isInfinite value then Nothing else Just value

parseIntText :: Text -> Maybe Int
parseIntText = readMaybe . Text.unpack

parseNonNegativeIntText :: Text -> Maybe Int
parseNonNegativeIntText encoded = do
  value <- parseIntText encoded
  if value < 0 then Nothing else Just value

parseBoolText :: Text -> Maybe Bool
parseBoolText "true" = Just True
parseBoolText "false" = Just False
parseBoolText _ = Nothing

requireNonEmptyRepeatedField :: Text -> Either Text ()
requireNonEmptyRepeatedField value
  | Text.null value = Left "empty repeated payload field"
  | otherwise = Right ()

workflowSegment :: Workflow -> Text
workflowSegment Train = "training"
workflowSegment Tune = "tune"
workflowSegment Rl = "rl"
workflowSegment Infer = "inference"
workflowSegment Gc = "gc"
workflowSegment WorkflowState = "workflow"

phaseSegment :: Phase -> Text
phaseSegment Command = "command"
phaseSegment Event = "event"
phaseSegment Result = "result"
phaseSegment Request = "request"
phaseSegment HostCommand = "host-command"
phaseSegment Status = "status"

jitmlTopology :: [RouteEntry]
jitmlTopology =
  [ RouteEntry Train Command allSubstrates
  , RouteEntry Train Event allSubstrates
  , RouteEntry Tune Command allSubstrates
  , RouteEntry Tune Event allSubstrates
  , RouteEntry Rl Command allSubstrates
  , RouteEntry Rl Event allSubstrates
  , RouteEntry Infer Request allSubstrates
  , RouteEntry Infer Result allSubstrates
  , RouteEntry Gc Event allSubstrates
  , RouteEntry Infer Command [AppleSilicon]
  , RouteEntry Train HostCommand [AppleSilicon]
  , RouteEntry Tune HostCommand [AppleSilicon]
  , RouteEntry Rl HostCommand [AppleSilicon]
  , RouteEntry WorkflowState Status allSubstrates
  ]

-- | Render raw graph entries for validation.  These addresses cannot be used
-- as typed publication or subscription handles.
topologyTopics :: [RouteEntry] -> [TopicAddress]
topologyTopics entries =
  [ renderAddress (reWorkflow entry) (rePhase entry) lane
  | entry <- entries
  , lane <- reLanes entry
  ]

-- | Exact typed topic set reconciled by the Coordinator.
coordinatorTopics :: [AnyTopic]
coordinatorTopics =
  [ topic
  | entry <- jitmlTopology
  , lane <- reLanes entry
  , topic <- maybeToList (anyTopicFor (reWorkflow entry) (rePhase entry) lane)
  ]

anyTopicFor :: Workflow -> Phase -> Substrate -> Maybe AnyTopic
anyTopicFor workflow phase lane =
  case (workflow, phase) of
    (Train, Command) -> AnyTopic <$> eitherToMaybe (topicFor TrainingCommandRoute lane)
    (Train, Event) -> AnyTopic <$> eitherToMaybe (topicFor TrainingEventRoute lane)
    (Train, HostCommand) -> AnyTopic <$> eitherToMaybe (topicFor TrainingHostCommandRoute lane)
    (Tune, Command) -> AnyTopic <$> eitherToMaybe (topicFor TuneCommandRoute lane)
    (Tune, Event) -> AnyTopic <$> eitherToMaybe (topicFor TuneEventRoute lane)
    (Tune, HostCommand) -> AnyTopic <$> eitherToMaybe (topicFor TuneHostCommandRoute lane)
    (Rl, Command) -> AnyTopic <$> eitherToMaybe (topicFor RlCommandRoute lane)
    (Rl, Event) -> AnyTopic <$> eitherToMaybe (topicFor RlEventRoute lane)
    (Rl, HostCommand) -> AnyTopic <$> eitherToMaybe (topicFor RlHostCommandRoute lane)
    (Infer, Request) -> AnyTopic <$> eitherToMaybe (topicFor InferenceRequestRoute lane)
    (Infer, Command) -> AnyTopic <$> eitherToMaybe (topicFor InferenceHostCommandRoute lane)
    (Infer, Result) -> AnyTopic <$> eitherToMaybe (topicFor InferenceResultRoute lane)
    (Gc, Event) -> AnyTopic <$> eitherToMaybe (topicFor GcEventRoute lane)
    (WorkflowState, Status) -> AnyTopic <$> eitherToMaybe (topicFor WorkflowStatusRoute lane)
    _ -> Nothing

eitherToMaybe :: Either error value -> Maybe value
eitherToMaybe = either (const Nothing) Just

maybeToList :: Maybe value -> [value]
maybeToList = maybe [] pure

topologyLogicalNames :: [RouteEntry] -> [Text]
topologyLogicalNames entries =
  nubOrd
    [ workflowSegment (reWorkflow entry) <> "." <> phaseSegment (rePhase entry)
    | entry <- entries
    ]

validateTopology :: [RouteEntry] -> Either [Text] ()
validateTopology entries =
  case duplicateErrors <> emptyLaneErrors <> oneSidedErrors of
    [] -> Right ()
    errs -> Left errs
 where
  names = fmap topicAddressName (topologyTopics entries)
  duplicateErrors =
    [ "duplicate topic: " <> name
    | (name, count) <- Map.toList (Map.fromListWith (+) [(value, 1 :: Int) | value <- names])
    , count > 1
    ]
  emptyLaneErrors =
    [ "routing entry has no lanes: "
        <> workflowSegment (reWorkflow entry)
        <> "."
        <> phaseSegment (rePhase entry)
    | entry <- entries
    , null (reLanes entry)
    ]
  pairs =
    [ (reWorkflow entry, lane, rePhase entry)
    | entry <- entries
    , lane <- reLanes entry
    ]
  workflowLanes = nubOrd [(workflow, lane) | (workflow, lane, _) <- pairs]
  phasesFor workflow lane =
    [ phase
    | (candidateWorkflow, candidateLane, phase) <- pairs
    , candidateWorkflow == workflow
    , candidateLane == lane
    ]
  oneSidedErrors =
    concat
      [ checkPair workflow lane (phasesFor workflow lane)
      | (workflow, lane) <- workflowLanes
      ]
  checkPair workflow lane phases =
    let inputs = filter isInput phases
        reports = filter isReport phases
        label = workflowSegment workflow <> ".*." <> renderSubstrate lane
     in ["one-sided routing (input with no event/result): " <> label | not (null inputs) && null reports]
          <> [ "one-sided routing (report with no command/request): " <> label
             | null inputs && not (null reports) && not (emitOnlyWorkflow workflow)
             ]
  isInput phase = phase `elem` [Command, Request, HostCommand]
  isReport phase = phase `elem` [Event, Result, Status]
  emitOnlyWorkflow workflow = workflow `elem` [Gc, WorkflowState]

nubOrd :: (Ord value) => [value] -> [value]
nubOrd = Set.toList . Set.fromList
