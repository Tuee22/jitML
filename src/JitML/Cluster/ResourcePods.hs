{-# LANGUAGE OverloadedStrings #-}

-- | Account for the CPU and RAM of actually admitted Pods. This is a final
-- observed-resource gate, not a prediction of operator-created workloads or a
-- replacement for controller/readiness coverage, Docker caps or CUDA checks.
module JitML.Cluster.ResourcePods
  ( NodePodBudget (..)
  , PodBudgetReport (..)
  , validateAdmittedPodBudgets
  , renderPodBudgetReport
  )
where

import Control.Monad (foldM, unless, when)
import Data.Aeson (FromJSON (..), Object, Value (..), withObject, (.:))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key (Key)
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Aeson.Types (Parser)
import Data.Bifunctor (first)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Encoding

import JitML.Cluster.ResourceBudget (ResourceEnvelope (..), parseCpuMilli, parseMemoryBytes)
import JitML.Cluster.ResourceNodes (validateNodeAllocatable)
import JitML.Cluster.Resources (ClusterResources)
import JitML.Substrate (Substrate)

data NodePodBudget = NodePodBudget
  { nodePodAllocatableCpuMilli :: Integer
  , nodePodAllocatableMemoryBytes :: Integer
  , nodePodRequestedCpuMilli :: Integer
  , nodePodRequestedMemoryBytes :: Integer
  , nodePodPlatformMemoryLimitsBytes :: Integer
  }
  deriving stock (Eq, Show)

data PodBudgetReport = PodBudgetReport
  { podBudgetObservedPodUids :: [Text]
  , podBudgetTerminalPodUids :: [Text]
  , podBudgetPerNode :: Map Text NodePodBudget
  , podBudgetSystemContainersBoundedOnlyByNode :: [Text]
  , podBudgetExtendedResourcesOutsideScope :: [Text]
  , podBudgetLimitsOvercommitNodes :: Bool
  }
  deriving stock (Eq, Show)

data Amounts = Amounts {amountCpu :: Integer, amountMemory :: Integer}
  deriving stock (Eq, Show)

data Fields = Fields {fieldRequests :: Map Text Text, fieldLimits :: Map Text Text}

data Container = Container
  { containerName :: Text
  , containerFields :: Fields
  , containerRestartable :: Bool
  }

data ContainerObservation = ContainerObservation Text (Maybe Fields) (Maybe (Map Text Text))
data Condition = Condition Text Text
data Owner = Owner Text Bool

data Pod = Pod
  { podName :: Text
  , podNamespace :: Text
  , podUid :: Text
  , podNode :: Text
  , podPhase :: Text
  , podTerminating :: Bool
  , podConditions :: [Condition]
  , podOwners :: [Owner]
  , podContainers :: [Container]
  , podInitContainers :: [Container]
  , podOverhead :: Map Text Text
  , podSelector :: Map Text Text
  , podStatuses :: [ContainerObservation]
  , podUnsupported :: [Text]
  , podOutsideScope :: [Text]
  }

data Node = Node Text (Map Text Text) Text Text
newtype Nodes = Nodes [Node]
newtype Pods = Pods [Pod]

instance FromJSON Fields where
  parseJSON = withObject "container resources" $ \value ->
    Fields <$> optional value "requests" Map.empty <*> optional value "limits" Map.empty

instance FromJSON Container where
  parseJSON = withObject "container" $ \value -> do
    name <- value .: "name" >>= identifier "container name"
    fields <- optional value "resources" (Fields Map.empty Map.empty)
    restart <- optional value "restartPolicy" ("" :: Text)
    unless (restart `elem` ["", "Always"]) (fail "unsupported container restartPolicy")
    pure (Container name fields (restart == "Always"))

instance FromJSON ContainerObservation where
  parseJSON = withObject "container status resources" $ \value ->
    ContainerObservation
      <$> (value .: "name" >>= identifier "container status name")
      <*> present value "resources"
      <*> present value "allocatedResources"

instance FromJSON Condition where
  parseJSON = withObject "Pod condition" $ \value -> do
    name <- value .: "type" >>= identifier "condition type"
    status <- value .: "status"
    unless
      (status `elem` (["True", "False", "Unknown"] :: [Text]))
      (fail "invalid Pod condition status")
    pure (Condition name status)

instance FromJSON Owner where
  parseJSON = withObject "Pod owner reference" $ \value -> do
    kind <- value .: "kind" >>= identifier "owner kind"
    _ <- value .: "name" >>= identifier "owner name"
    _ <- value .: "uid" >>= identifier "owner uid"
    Owner kind <$> optional value "controller" False

instance FromJSON Pod where
  parseJSON = withObject "admitted Pod" $ \value -> do
    version <- value .: "apiVersion"
    kind <- value .: "kind"
    unless (version == ("v1" :: Text) && kind == ("Pod" :: Text)) (fail "expected a v1 Pod")
    metadata <- value .: "metadata"
    name <- metadata .: "name" >>= identifier "Pod name"
    namespace <- metadata .: "namespace" >>= identifier "Pod namespace"
    uid <- metadata .: "uid" >>= identifier "Pod uid"
    owners <- optional metadata "ownerReferences" []
    terminating <- case KeyMap.lookup "deletionTimestamp" metadata of
      Nothing -> pure False
      Just Null -> pure False
      Just raw -> True <$ (parseJSON raw >>= identifier "deletion timestamp")
    spec <- value .: "spec"
    status <- value .: "status"
    node <- optional spec "nodeName" ""
    phase <- status .: "phase"
    unless (phase `elem` (["Pending", "Running", "Succeeded", "Failed", "Unknown"] :: [Text])) $
      fail "invalid Pod phase"
    containers <- spec .: "containers"
    initContainers <- optional spec "initContainers" []
    overhead <- optional spec "overhead" Map.empty
    selector <- optional spec "nodeSelector" Map.empty
    conditions <- optional status "conditions" []
    statuses <-
      (<>) <$> optional status "containerStatuses" [] <*> optional status "initContainerStatuses" []
    podResources <- optional spec "resources" (Fields Map.empty Map.empty)
    ephemeral <- optional spec "ephemeralContainers" ([] :: [Value])
    claims <- optional spec "resourceClaims" ([] :: [Value])
    resize <- optional status "resize" ("" :: Text)
    pure
      Pod
        { podName = name
        , podNamespace = namespace
        , podUid = uid
        , podNode = node
        , podPhase = phase
        , podTerminating = terminating
        , podConditions = conditions
        , podOwners = owners
        , podContainers = containers
        , podInitContainers = initContainers
        , podOverhead = overhead
        , podSelector = selector
        , podStatuses = statuses
        , podUnsupported =
            [ "Pod-level resources"
            | not (Map.null (fieldRequests podResources) && Map.null (fieldLimits podResources))
            ]
              <> ["ephemeral containers" | not (null ephemeral)]
              <> ["in-place resize" | not (Text.null resize) || any resizeCondition conditions]
        , podOutsideScope = ["resourceClaims" | not (null claims)]
        }
   where
    resizeCondition (Condition name status) = name `elem` ["PodResizePending", "PodResizeInProgress"] && status /= "False"

instance FromJSON Node where
  parseJSON = withObject "node budget" $ \value -> do
    metadata <- value .: "metadata"
    name <- metadata .: "name"
    labels <- metadata .: "labels"
    status <- value .: "status"
    allocatable <- status .: "allocatable"
    Node name labels <$> allocatable .: "cpu" <*> allocatable .: "memory"

instance FromJSON Nodes where
  parseJSON = withObject "Nodes" $ \value -> Nodes <$> value .: "items"

instance FromJSON Pods where
  parseJSON = withObject "admitted Pod inventory" $ \value -> do
    version <- value .: "apiVersion"
    kind <- value .: "kind"
    unless (version == ("v1" :: Text) && kind `elem` (["List", "PodList"] :: [Text])) $
      fail "expected a v1 List or PodList"
    Pods <$> value .: "items"

optional :: (FromJSON value) => Object -> Key -> value -> Parser value
optional object key fallback = maybe (pure fallback) parseJSON (KeyMap.lookup key object)

present :: (FromJSON value) => Object -> Key -> Parser (Maybe value)
present object key = traverse parseJSON (KeyMap.lookup key object)

identifier :: String -> Text -> Parser Text
identifier label value
  | Text.null value || Text.strip value /= value = fail ("invalid " <> label)
  | otherwise = pure value

-- | Both inputs are actual API inventories. All assigned active Pods count,
-- including mirror Pods, init Jobs and terminating old replicas. Every active
-- Pod must be assigned, Running and Ready for final acceptance. A succeeded
-- platform Job Pod is excluded only with an actual controller Job owner;
-- failed platform Pods refuse, including failed Job attempts.
--
-- Nonempty Pod-level resources, ephemeral containers and divergent/in-progress
-- resize observations refuse explicitly. Extended resources are reported as
-- outside this CPU/RAM check. No expected controller inventory is synthesized.
validateAdmittedPodBudgets
  :: Substrate -> ClusterResources -> ResourceEnvelope -> Text -> Text -> Either Text PodBudgetReport
validateAdmittedPodBudgets substrate resources envelope nodesRaw podsRaw = do
  require
    (Text.length nodesRaw <= 1048576 && Text.length podsRaw <= 8388608)
    "resource inventory exceeds its metadata read cap"
  validateNodeAllocatable substrate resources envelope nodesRaw
  Nodes nodes <- decode "node budgets" nodesRaw
  Pods pods <- decode "admitted Pods" podsRaw
  require (not (null pods)) "admitted Pod inventory is empty"
  unique "Pod UIDs" (fmap podUid pods)
  unique "Pod namespace/name coordinates" (fmap coordinate pods)
  mapM_ terminalPolicy pods
  let active = filter (not . terminal) pods
      excluded = filter terminal pods
  require
    (any platform active)
    "admitted inventory has no active platform Pods; workload coverage is unproved"
  nodeBudgets <- Map.fromList <$> traverse initialNode nodes
  parsed <- traverse (parsePod envelope nodes) active
  finalBudgets <- foldM addPod nodeBudgets (zip active parsed)
  mapM_ checkNode (Map.toList finalBudgets)
  mapM_ finalReadiness active
  pure
    PodBudgetReport
      { podBudgetObservedPodUids = fmap podUid active
      , podBudgetTerminalPodUids = fmap podUid excluded
      , podBudgetPerNode = finalBudgets
      , podBudgetSystemContainersBoundedOnlyByNode = concatMap parsedUncapped parsed
      , podBudgetExtendedResourcesOutsideScope = concatMap parsedOutsideScope parsed
      , podBudgetLimitsOvercommitNodes =
          any
            ( \budget ->
                nodePodPlatformMemoryLimitsBytes budget
                  > min (envelopeNodeApplicationMemoryBytes envelope) (nodePodAllocatableMemoryBytes budget)
            )
            (Map.elems finalBudgets)
      }
 where
  initialNode (Node name _ cpu memory) = do
    parsedCpu <- parseCpuMilli cpu
    parsedMemory <- parseMemoryBytes memory
    pure (name, NodePodBudget parsedCpu parsedMemory 0 0 0)
  addPod budgets (pod, parsed) = do
    require
      (not (Text.null (podNode pod)))
      (coordinate pod <> ": unassigned nonterminal Pod has unscheduled demand")
    budget <-
      maybe
        (Left (coordinate pod <> ": Pod is assigned to an unexpected node"))
        Right
        (Map.lookup (podNode pod) budgets)
    let request = parsedRequests parsed
        memoryLimit = if platform pod then parsedPlatformMemoryLimit parsed else 0
    pure $
      Map.insert
        (podNode pod)
        ( budget
            { nodePodRequestedCpuMilli = nodePodRequestedCpuMilli budget + amountCpu request
            , nodePodRequestedMemoryBytes = nodePodRequestedMemoryBytes budget + amountMemory request
            , nodePodPlatformMemoryLimitsBytes = nodePodPlatformMemoryLimitsBytes budget + memoryLimit
            }
        )
        budgets
  checkNode (name, budget) = do
    require
      (nodePodRequestedCpuMilli budget <= nodePodAllocatableCpuMilli budget)
      (name <> ": admitted Pod CPU requests exceed observed Allocatable")
    require
      (nodePodRequestedMemoryBytes budget <= nodePodAllocatableMemoryBytes budget)
      (name <> ": admitted Pod memory requests exceed observed Allocatable")

data ParsedPod = ParsedPod
  { parsedRequests :: Amounts
  , parsedPlatformMemoryLimit :: Integer
  , parsedUncapped :: [Text]
  , parsedOutsideScope :: [Text]
  }

parsePod :: ResourceEnvelope -> [Node] -> Pod -> Either Text ParsedPod
parsePod envelope nodes pod = first ((coordinate pod <> ": ") <>) $ do
  require (not (Text.null (podNode pod))) "unassigned nonterminal Pod has unscheduled demand"
  assignedMemory <- case [raw | Node name _ _ raw <- nodes, name == podNode pod] of
    [raw] -> parseMemoryBytes raw
    _ -> Left "Pod is assigned to an unexpected node"
  require
    (null (podUnsupported pod))
    ("unsupported observed feature: " <> Text.intercalate ", " (podUnsupported pod))
  require (not (null (podContainers pod))) "Pod has no regular containers"
  let containers = podContainers pod <> podInitContainers pod
  unique "container names" (fmap containerName containers)
  unique "container status names" [name | ContainerObservation name _ _ <- podStatuses pod]
  require
    (not (any containerRestartable (podContainers pod)))
    "regular-container restartPolicy is unsupported"
  mapM_ (checkStatus containers) (podStatuses pod)
  regular <- traverse parseContainer (podContainers pod)
  initial <- traverse parseContainer (podInitContainers pod)
  overhead <- mapAmounts (podOverhead pod)
  let request = plus overhead (effective fmapRequests regular initial)
      limit = effective fmapLimits regular initial
      limitMemory = amountMemory limit + amountMemory overhead
      computeOnly = Map.lookup "jitml.node-role/compute" (podSelector pod) == Just "true"
      labels = [labelsForNode | Node name labelsForNode _ _ <- nodes, name == podNode pod]
  when computeOnly $
    require
      (any ((== Just "true") . Map.lookup "jitml.node-role/compute") labels)
      "compute-selected Pod is not assigned to a compute worker"
  when (platform pod) $
    require
      (limitMemory <= min (envelopeNodeApplicationMemoryBytes envelope) assignedMemory)
      "effective Pod memory limit exceeds eligible per-node application capacity"
  pure
    ParsedPod
      { parsedRequests = request
      , parsedPlatformMemoryLimit = if platform pod then limitMemory else 0
      , parsedUncapped =
          [ coordinate pod <> "/" <> containerName c
          | (c, (budget, _)) <- zip containers (regular <> initial)
          , not (parsedFinite budget)
          ]
      , parsedOutsideScope =
          [ coordinate pod <> "/" <> key
          | key <-
              Set.toList
                ( Set.fromList
                    (podOutsideScope pod <> outside (podOverhead pod) <> concatMap containerOutside containers)
                )
          ]
      }
 where
  parseContainer c = do
    parsed <- parseFields (platform pod) (containerFields c)
    pure (parsed, containerRestartable c)
  checkStatus containers (ContainerObservation name observed allocated) = do
    c <- case filter ((== name) . containerName) containers of
      [value] -> Right value
      _ -> Left "container resource status names an unknown container"
    declared <- parseFields False (containerFields c)
    case observed of
      Nothing -> pure ()
      Just fields -> do
        current <- parseFields False fields
        require
          (current == declared)
          "divergent container status resources require unsupported in-place resize accounting"
    case allocated of
      Nothing -> pure ()
      Just fields -> do
        current <- mapAmounts fields
        require
          (current == parsedFieldRequests declared)
          "divergent allocated resources require unsupported in-place resize accounting"

data ParsedFields = ParsedFields
  { parsedFieldRequests :: Amounts
  , parsedFieldLimits :: Amounts
  , parsedFinite :: Bool
  }
  deriving stock (Eq, Show)

parseFields :: Bool -> Fields -> Either Text ParsedFields
parseFields managed fields = do
  requests <- resourceValues managed (fieldRequests fields)
  limits <- resourceValues managed (fieldLimits fields)
  let complete =
        all (`Map.member` fieldLimits fields) ["cpu", "memory"]
          && amountCpu limits > 0
          && amountMemory limits > 0
  require
    (not managed || complete)
    "platform container requires positive finite CPU and memory limits"
  require
    (amountCpu limits == 0 || amountCpu requests <= amountCpu limits)
    "container CPU request exceeds limit"
  require
    (amountMemory limits == 0 || amountMemory requests <= amountMemory limits)
    "container memory request exceeds limit"
  pure (ParsedFields requests limits complete)

resourceValues :: Bool -> Map Text Text -> Either Text Amounts
resourceValues positive fields =
  Amounts <$> value "cpu" parseCpuMilli <*> value "memory" parseMemoryBytes
 where
  value name parser = case Map.lookup name fields of
    Nothing | not positive -> Right 0
    Nothing -> Left ("platform container is missing admitted " <> name <> " request or limit")
    Just raw | not positive && raw == "0" -> Right 0
    Just raw -> first ((name <> ": ") <>) (parser raw)

mapAmounts :: Map Text Text -> Either Text Amounts
mapAmounts = resourceValues False

-- Resource-wise maxima reflect sequential init containers. Restartable init
-- sidecars remain active during subsequent init stages and normal app work.
-- Mirrors Kubernetes v1.34 component-helpers/resource/helpers.go aggregation.
effective
  :: (ParsedFields -> Amounts) -> [(ParsedFields, Bool)] -> [(ParsedFields, Bool)] -> Amounts
effective select regular initial = largest app peak
 where
  (sidecars, peak) = foldl' stage (zero, zero) initial
  app = foldl' plus sidecars (fmap (select . fst) regular)
  stage (running, previous) (budget, restartable) =
    let current = plus running (select budget)
     in (if restartable then current else running, largest previous current)

fmapRequests, fmapLimits :: ParsedFields -> Amounts
fmapRequests = parsedFieldRequests
fmapLimits = parsedFieldLimits

zero :: Amounts
zero = Amounts 0 0

plus, largest :: Amounts -> Amounts -> Amounts
plus (Amounts cpu memory) (Amounts otherCpu otherMemory) = Amounts (cpu + otherCpu) (memory + otherMemory)
largest (Amounts cpu memory) (Amounts otherCpu otherMemory) = Amounts (max cpu otherCpu) (max memory otherMemory)

outside :: Map Text Text -> [Text]
outside = filter (`notElem` ["cpu", "memory"]) . Map.keys

containerOutside :: Container -> [Text]
containerOutside c = outside (fieldRequests fields) <> outside (fieldLimits fields)
 where
  fields = containerFields c

terminal :: Pod -> Bool
terminal pod = podPhase pod `elem` ["Succeeded", "Failed"]

platform :: Pod -> Bool
platform = (== "platform") . podNamespace

coordinate :: Pod -> Text
coordinate pod = podNamespace pod <> "/" <> podName pod

terminalPolicy :: Pod -> Either Text ()
terminalPolicy pod = when (platform pod && terminal pod) $ do
  require
    (podPhase pod /= "Failed")
    (coordinate pod <> ": failed platform Pod is not a successful convergence")
  require
    ([kind | Owner kind True <- podOwners pod] == ["Job"])
    (coordinate pod <> ": succeeded platform Pod requires an actual controller Job owner")

finalReadiness :: Pod -> Either Text ()
finalReadiness pod = first ((coordinate pod <> ": ") <>) $ do
  require (podPhase pod == "Running") "nonterminal infrastructure Pod is not Running"
  require (not (podTerminating pod)) "terminating nonterminal Pod still consumes resource demand"
  require
    ([status | Condition "Ready" status <- podConditions pod] == ["True"])
    "nonterminal infrastructure Pod must have exactly one Ready=True condition"

unique :: (Ord value) => Text -> [value] -> Either Text ()
unique label values = require (Set.size (Set.fromList values) == length values) ("duplicate " <> label)

decode :: (FromJSON value) => Text -> Text -> Either Text value
decode label =
  first ((("invalid " <> label <> " JSON: ") <>) . Text.pack)
    . Aeson.eitherDecodeStrict'
    . Encoding.encodeUtf8

require :: Bool -> Text -> Either Text ()
require condition reason = unless condition (Left reason)

renderPodBudgetReport :: PodBudgetReport -> Text
renderPodBudgetReport report =
  Text.unlines $
    [ "Observed active admitted Pods: " <> shown (length (podBudgetObservedPodUids report))
    , "Excluded terminal Pods: " <> shown (length (podBudgetTerminalPodUids report))
    , "System containers relying on hard node parents for missing inner limits: "
        <> shown (length (podBudgetSystemContainersBoundedOnlyByNode report))
    , "Extended resource fields outside CPU/RAM scope: "
        <> shown (length (podBudgetExtendedResourcesOutsideScope report))
    , "Platform nominal Pod memory limits overcommit node application capacity: "
        <> shown (podBudgetLimitsOvercommitNodes report)
    , "This snapshot does not establish expected controller coverage, future scheduling, no OOM or scientific acceptance."
    ]
      <> [name <> ": " <> shown budget | (name, budget) <- Map.toAscList (podBudgetPerNode report)]
 where
  shown :: (Show value) => value -> Text
  shown = Text.pack . show
