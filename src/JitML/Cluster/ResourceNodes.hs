{-# LANGUAGE OverloadedStrings #-}

-- | Check the scheduler's observed node inventory after hard runtime caps and
-- before workload rollout. This does not infer capacity from the VM size or
-- rewrite a kubelet's advertised resources to make an unsafe plan pass.
module JitML.Cluster.ResourceNodes
  ( validateNodeAllocatable
  , validateNodeHardCaps
  )
where

import Control.Monad (unless)
import Data.Aeson (FromJSON (..), Object, withObject, (.:))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key (Key)
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Aeson.Types (Parser)
import Data.Bifunctor (first)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding

import JitML.Cluster.Kind (substrateKindNodeContainerNames)
import JitML.Cluster.ResourceBudget
  ( ResourceEnvelope (..)
  , parseCpuMilli
  , parseMemoryBytes
  )
import JitML.Cluster.Resources (ClusterResources (..), nodeMemoryBytes)
import JitML.Substrate (Substrate, substrateClusterName)

newtype NodeInventory = NodeInventory [ObservedNode]

data ObservedNode = ObservedNode
  { observedName :: Text
  , observedLabels :: Map.Map Text Text
  , observedUnschedulable :: Bool
  , observedTaints :: [ObservedTaint]
  , observedCpu :: Text
  , observedMemory :: Text
  , observedConditions :: [ObservedCondition]
  }

newtype ObservedTaint = ObservedTaint {observedTaintEffect :: Text}

data ObservedCondition = ObservedCondition Text Text

data ObservedHardCaps = ObservedHardCaps
  { hardCapsName :: Text
  , hardCapsMemory :: Integer
  , hardCapsMemorySwap :: Integer
  , hardCapsNanoCpus :: Integer
  , hardCapsRunning :: Bool
  , hardCapsPaused :: Bool
  , hardCapsRestarting :: Bool
  , hardCapsPid :: Integer
  }

instance FromJSON ObservedHardCaps where
  parseJSON = withObject "selected Docker node inspect" $ \value ->
    ObservedHardCaps
      <$> value .: "Name"
      <*> value .: "Memory"
      <*> value .: "MemorySwap"
      <*> value .: "NanoCpus"
      <*> value .: "Running"
      <*> value .: "Paused"
      <*> value .: "Restarting"
      <*> value .: "Pid"

instance FromJSON NodeInventory where
  parseJSON = withObject "kubectl node inventory" $ \value -> do
    version <- value .: "apiVersion"
    kind <- value .: "kind"
    unless (version == ("v1" :: Text) && kind `elem` (["List", "NodeList"] :: [Text])) $
      fail "expected a v1 List or NodeList"
    NodeInventory <$> value .: "items"

instance FromJSON ObservedNode where
  parseJSON = withObject "node" $ \value -> do
    metadata <- value .: "metadata"
    name <- metadata .: "name"
    labels <- metadata .: "labels"
    spec <- value .: "spec"
    unschedulable <- optionalField spec "unschedulable" False
    taints <- optionalField spec "taints" []
    status <- value .: "status"
    allocatable <- status .: "allocatable"
    ObservedNode name labels unschedulable taints
      <$> allocatable .: "cpu"
      <*> allocatable .: "memory"
      <*> status .: "conditions"

instance FromJSON ObservedTaint where
  parseJSON = withObject "node taint" $ \value -> do
    key <- value .: "key"
    effect <- value .: "effect"
    unless (not (Text.null key) && effect `elem` ["NoSchedule", "PreferNoSchedule", "NoExecute"]) $
      fail "invalid node taint key or effect"
    -- The optional Kubernetes taint value is a string, including when empty.
    _ <- optionalField value "value" ("" :: Text)
    pure (ObservedTaint effect)

instance FromJSON ObservedCondition where
  parseJSON = withObject "node condition" $ \value -> do
    kind <- value .: "type"
    status <- value .: "status"
    unless (not (Text.null kind) && status `elem` ["True", "False", "Unknown"]) $
      fail "invalid node condition type or status"
    pure (ObservedCondition kind status)

-- Unlike .:?, a present null does not silently become a safe-looking default.
optionalField :: (FromJSON value) => Object -> Key -> value -> Parser value
optionalField object key fallback =
  maybe (pure fallback) parseJSON (KeyMap.lookup key object)

-- | A necessary scheduler-capacity and placement check for a validated
-- envelope. A successful result is not a complete workload scheduling proof.
validateNodeAllocatable
  :: Substrate -> ClusterResources -> ResourceEnvelope -> Text -> Either Text ()
validateNodeAllocatable substrate resources envelope raw = do
  NodeInventory nodes <-
    first
      (("invalid node inventory JSON: " <>) . Text.pack)
      (Aeson.eitherDecodeStrict' (Text.Encoding.encodeUtf8 raw))
  let expected = substrateKindNodeContainerNames substrate (workerCount resources)
      actual = fmap observedName nodes
      controlPlane = substrateClusterName substrate <> "-control-plane"
  require (workerCount resources >= 1) "node inventory requires at least one compute worker"
  require
    (toInteger (length expected) == envelopeNodeCount envelope)
    "node inventory profile does not match the validated envelope node count"
  require (length actual == Set.size (Set.fromList actual)) "node inventory contains duplicate names"
  require
    (Set.fromList actual == Set.fromList expected)
    "node inventory names do not match the exact selected Kind topology"
  require
    (envelopeNodeApplicationCpuMilli envelope > 0 && envelopeNodeApplicationMemoryBytes envelope > 0)
    "validated envelope has no positive per-node application capacity"
  mapM_ (validateNode controlPlane) nodes
 where
  validateNode controlPlane node = first ((observedName node <> ": ") <>) $ do
    cpu <- first ("allocatable CPU: " <>) (parseCpuMilli (observedCpu node))
    memory <- first ("allocatable memory: " <>) (parseMemoryBytes (observedMemory node))
    require
      (cpu <= envelopeNodeApplicationCpuMilli envelope)
      "allocatable CPU exceeds planned per-node application capacity"
    require
      (memory <= envelopeNodeApplicationMemoryBytes envelope)
      "allocatable memory exceeds planned per-node application capacity"
    let ready = [status | ObservedCondition "Ready" status <- observedConditions node]
        compute = Map.lookup "jitml.node-role/compute" (observedLabels node) == Just "true"
        blocked = any ((`elem` ["NoSchedule", "NoExecute"]) . observedTaintEffect) (observedTaints node)
        schedulable = not (observedUnschedulable node) && not blocked
    require (ready == ["True"]) "node must have exactly one Ready=True condition"
    if observedName node == controlPlane
      then do
        require (not compute) "control-plane must not carry the compute-worker label"
        require
          (schedulable == scheduleOnControlPlane resources)
          "control-plane scheduling eligibility differs from the selected profile"
      else do
        require compute "worker must carry jitml.node-role/compute=true"
        require schedulable "worker is cordoned or has a NoSchedule/NoExecute taint"

-- | Check selected, live Docker inspect evidence for every expected Kind node.
-- Kubernetes Allocatable is not evidence that these hard parent caps remain
-- present. Input is one selected JSON object per line, with Docker's exact
-- leading-slash Name, integer HostConfig memory/swap/NanoCpus fields and
-- selected live State fields. Kubernetes Ready may briefly outlive a container.
validateNodeHardCaps :: Substrate -> ClusterResources -> Text -> Either Text ()
validateNodeHardCaps substrate resources raw = do
  require (workerCount resources >= 1) "Docker node caps require at least one compute worker"
  cpuMilli <- first ("nodeCpus: " <>) (parseCpuMilli (nodeCpus resources))
  let expectedMemory = nodeMemoryBytes resources
      expectedNanoCpus = cpuMilli * 1000000
      expectedNames = fmap ("/" <>) (substrateKindNodeContainerNames substrate (workerCount resources))
      linesOfEvidence = Text.lines raw
  require (expectedMemory > 0) "Docker node memory cap must be positive"
  require (not (null linesOfEvidence)) "Docker node cap evidence is empty"
  require
    (not (any (Text.null . Text.strip) linesOfEvidence))
    "Docker node cap evidence contains blank lines"
  caps <- mapM parseLine (zip [1 :: Int ..] linesOfEvidence)
  let names = fmap hardCapsName caps
  require
    (length names == Set.size (Set.fromList names))
    "Docker node cap evidence contains duplicate names"
  require
    (Set.fromList names == Set.fromList expectedNames)
    "Docker node cap names do not match the exact selected Kind topology"
  mapM_ (checkCaps expectedMemory expectedNanoCpus) caps
 where
  parseLine (lineNumber, line) =
    first
      ( (("invalid Docker node inspect JSON on line " <> Text.pack (show lineNumber) <> ": ") <>)
          . Text.pack
      )
      (Aeson.eitherDecodeStrict' (Text.Encoding.encodeUtf8 line))
  checkCaps memory nanoCpus caps = first ((hardCapsName caps <> ": ") <>) $ do
    require
      ( hardCapsRunning caps
          && not (hardCapsPaused caps)
          && not (hardCapsRestarting caps)
          && hardCapsPid caps > 0
      )
      "Docker node must be running, unpaused, not restarting and have a positive PID"
    require (hardCapsMemory caps == memory) "Docker Memory differs from the selected node cap"
    require (hardCapsMemorySwap caps == memory) "Docker MemorySwap must equal Memory to disable swap"
    require (hardCapsNanoCpus caps == nanoCpus) "Docker NanoCpus differs from the selected node cap"

require :: Bool -> Text -> Either Text ()
require condition reason = unless condition (Left reason)
