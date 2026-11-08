{-# LANGUAGE OverloadedStrings #-}

-- | Validate the hard VM envelope independently of nominal pod limits.
-- Kind nodes contain their pods, so pod limits are not added to node limits.
-- Passing this check contains resource use; it does not promise that pods will
-- avoid OOM or that an unobserved rendered workload inventory will schedule.
module JitML.Cluster.ResourceBudget
  ( RuntimeCapacity (..)
  , ResourceEnvelope (..)
  , WorkloadPlacement (..)
  , WorkloadBudget (..)
  , parseCpuMilli
  , parseMemoryBytes
  , kubeletSystemReservation
  , validateResourceEnvelope
  , validateNumericalWorkloadBudget
  , validateWorkloadRequests
  , renderResourceEnvelope
  )
where

import Control.Monad (unless)
import Data.Bifunctor (first)
import Data.Char (isAscii, isDigit)
import Data.Maybe (fromMaybe)
import Data.Ratio (denominator, numerator, (%))
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Cluster.Resources
  ( ClusterResources (..)
  , ComponentBudget (..)
  , validateEngineTopology
  , validateLocalPlatformTopology
  )

-- | Capacity observed from the explicitly selected Docker runtime, not the
-- configured VM size or host physical memory.
data RuntimeCapacity = RuntimeCapacity
  { runtimeCpuCount :: Int
  , runtimeMemoryBytes :: Integer
  }
  deriving stock (Eq, Show)

data ResourceEnvelope = ResourceEnvelope
  { envelopeRuntimeCapacity :: RuntimeCapacity
  , envelopeNodeCount :: Integer
  , envelopeWorkerCount :: Integer
  , envelopeSchedulableNodeCount :: Integer
  , envelopeNodeMemoryBytes :: Integer
  , envelopeNodeCpuMilli :: Integer
  , envelopeNodeSystemMemoryBytes :: Integer
  , envelopeNodeSystemCpuMilli :: Integer
  , envelopeNodeApplicationMemoryBytes :: Integer
  , envelopeNodeApplicationCpuMilli :: Integer
  , envelopeJobMemoryBytes :: Integer
  , envelopeJobCpuMilli :: Integer
  , envelopeSystemReserveBytes :: Integer
  , envelopeHardMemoryBytes :: Integer
  , envelopeHardCpuMilli :: Integer
  , envelopeMemoryHeadroomBytes :: Integer
  , envelopeCpuHeadroomMilli :: Integer
  , envelopePodLimitsMayOvercommit :: Bool
  }
  deriving stock (Eq, Show)

-- | Render reservations for a validated envelope when the kubelet reports
-- the observed Docker runtime capacity rather than its hard parent-node cap.
-- Exclude capacity outside that node, then reserve its declared system share.
-- This is scheduler accounting, not a claim that OS daemons use the excluded
-- capacity. Callers must still verify actual live node Allocatable.
kubeletSystemReservation :: ResourceEnvelope -> (Text, Text)
kubeletSystemReservation envelope =
  ( Text.pack (show cpuMilli) <> "m"
  , Text.pack (show memoryBytes)
  )
 where
  capacity = envelopeRuntimeCapacity envelope
  cpuMilli =
    toInteger (runtimeCpuCount capacity) * 1000
      - envelopeNodeCpuMilli envelope
      + envelopeNodeSystemCpuMilli envelope
  memoryBytes =
    runtimeMemoryBytes capacity
      - envelopeNodeMemoryBytes envelope
      + envelopeNodeSystemMemoryBytes envelope

data WorkloadPlacement = AnySchedulableNode | ComputeWorkerNodes
  deriving stock (Eq, Show)

-- | An explicit supplied workload inventory. Callers must derive its entries
-- from the rendered manifests; this module does not claim registry coverage.
data WorkloadBudget = WorkloadBudget
  { workloadName :: Text
  , workloadPlacement :: WorkloadPlacement
  , workloadResources :: ComponentBudget
  }
  deriving stock (Eq, Show)

data ParsedBudget = ParsedBudget
  { parsedReplicas :: Integer
  , parsedCpuRequest :: Integer
  , parsedMemoryRequest :: Integer
  , parsedMemoryLimit :: Integer
  }

-- | CPU quantities resolve to exact millicores. Sub-millicore quantities
-- refuse instead of silently rounding or using floating-point arithmetic.
parseCpuMilli :: Text -> Either Text Integer
parseCpuMilli raw = quantity decimalSuffixes raw >>= integralQuantity "CPU millicores" . (* 1000)

-- | Binary and decimal Kubernetes memory suffixes resolve to exact bytes.
-- Fractional-byte quantities refuse rather than rounding a budget upwards.
parseMemoryBytes :: Text -> Either Text Integer
parseMemoryBytes raw = quantity (binarySuffixes <> decimalSuffixes) raw >>= integralQuantity "memory bytes"

integralQuantity :: Text -> Rational -> Either Text Integer
integralQuantity label value = do
  require (value > 0 && denominator value == 1) (label <> " must be positive and exactly integral")
  let result = numerator value
  require (result <= 9223372036854775807) (label <> " exceeds the supported integer range")
  pure result

quantity :: [(Text, Rational)] -> Text -> Either Text Rational
quantity suffixes raw = do
  require
    (not (Text.null raw) && Text.length raw <= 128 && Text.strip raw == raw)
    "invalid resource quantity"
  let unsigned = fromMaybe raw (Text.stripPrefix "+" raw)
      (number, suffix) = Text.span (\c -> asciiDigit c || c == '.') unsigned
      pieces = Text.splitOn "." number
  value <- case pieces of
    [whole] | digits whole -> pure (integer whole % 1)
    [whole, fraction]
      | (not (Text.null whole) || not (Text.null fraction))
          && Text.all asciiDigit whole
          && Text.all asciiDigit fraction ->
          pure (integer (whole <> fraction) % (10 ^ Text.length fraction))
    _ -> Left "invalid resource quantity number"
  scale <- case lookup suffix suffixes of
    Just multiplier -> pure multiplier
    Nothing -> exponentScale suffix
  pure (value * scale)
 where
  digits text = not (Text.null text) && Text.all asciiDigit text
  integer = Text.foldl' (\n c -> n * 10 + toInteger (fromEnum c - fromEnum '0')) 0

asciiDigit :: Char -> Bool
asciiDigit c = isAscii c && isDigit c

exponentScale :: Text -> Either Text Rational
exponentScale suffix = do
  rest <- case Text.uncons suffix of
    Just (e, value) | e == 'e' || e == 'E' -> pure value
    _ -> Left "unsupported resource quantity suffix"
  let (sign, digits) = case Text.uncons rest of
        Just ('-', value) -> (-1, value)
        Just ('+', value) -> (1, value)
        _ -> (1, rest)
  require
    (not (Text.null digits) && Text.length digits <= 2 && Text.all asciiDigit digits)
    "invalid resource quantity exponent"
  let power = sign * Text.foldl' (\n c -> n * 10 + fromEnum c - fromEnum '0') 0 digits
  require (abs power <= 63) "resource quantity exponent outside supported range"
  pure $ if power < 0 then 1 % (10 ^ negate power) else (10 ^ power) % 1

decimalSuffixes :: [(Text, Rational)]
decimalSuffixes =
  [ ("n", 1 % 1000000000)
  , ("u", 1 % 1000000)
  , ("m", 1 % 1000)
  , ("", 1)
  , ("k", 1000)
  , ("M", 1000000)
  , ("G", 1000000000)
  , ("T", 1000000000000)
  , ("P", 1000000000000000)
  , ("E", 1000000000000000000)
  ]

binarySuffixes :: [(Text, Rational)]
binarySuffixes = zip ["Ki", "Mi", "Gi", "Ti", "Pi", "Ei"] (fmap (1024 ^) [1 :: Int .. 6])

require :: Bool -> Text -> Either Text ()
require condition reason = unless condition (Left reason)

positiveMiB :: Text -> Int -> Either Text Integer
positiveMiB label value = do
  require (value > 0) (label <> " must be positive")
  pure (toInteger value * 1048576)

parseBudget :: Text -> ComponentBudget -> Either Text ParsedBudget
parseBudget name budget = first ((name <> ": ") <>) $ do
  require (budgetReplicas budget > 0) "replicas must be positive"
  cpuRequest <- parseCpuMilli (budgetCpuRequest budget)
  cpuLimit <- parseCpuMilli (budgetCpuLimit budget)
  memoryRequest <- parseMemoryBytes (budgetMemoryRequest budget)
  memoryLimit <- parseMemoryBytes (budgetMemoryLimit budget)
  require (cpuRequest <= cpuLimit) "CPU request exceeds limit"
  require (memoryRequest <= memoryLimit) "memory request exceeds limit"
  pure (ParsedBudget (toInteger (budgetReplicas budget)) cpuRequest memoryRequest memoryLimit)

validateNumericalWorkloadBudget :: ComponentBudget -> Either Text ()
validateNumericalWorkloadBudget budget = do
  _ <- parseBudget "numericalWorkload" budget
  require (budgetReplicas budget == 1) "numericalWorkload requires exactly one serial worker per node"

validateResourceEnvelope :: RuntimeCapacity -> ClusterResources -> Either Text ResourceEnvelope
validateResourceEnvelope capacity resources = do
  require
    (runtimeCpuCount capacity > 0 && runtimeMemoryBytes capacity > 0)
    "Docker runtime capacity must be positive"
  validateEngineTopology resources
  validateLocalPlatformTopology resources
  validateNumericalWorkloadBudget (numericalWorkload resources)
  nodeMemory <- positiveMiB "nodeMemoryMiB" (nodeMemoryMiB resources)
  jobMemory <- positiveMiB "jobMemoryMiB" (jobMemoryMiB resources)
  systemMemory <- positiveMiB "systemReserveMiB" (systemReserveMiB resources)
  nodeSystemMemory <- positiveMiB "nodeSystemMemoryMiB" (nodeSystemMemoryMiB resources)
  nodeCpu <- first ("nodeCpus: " <>) (parseCpuMilli (nodeCpus resources))
  jobCpu <- first ("jobCpus: " <>) (parseCpuMilli (jobCpus resources))
  nodeSystemCpu <- first ("nodeSystemCpus: " <>) (parseCpuMilli (nodeSystemCpus resources))
  require (nodeSystemMemory < nodeMemory) "node-system memory reserve leaves no application capacity"
  require (nodeSystemCpu < nodeCpu) "node-system CPU reserve leaves no application capacity"
  let workers = toInteger (workerCount resources)
      nodes = workers + 1
      eligible = workers + if scheduleOnControlPlane resources then 1 else 0
      hardMemory = nodes * nodeMemory + jobMemory + systemMemory
      hardCpu = nodes * nodeCpu + jobCpu
      availableMemory = nodeMemory - nodeSystemMemory
      availableCpu = nodeCpu - nodeSystemCpu
  require
    (hardMemory <= runtimeMemoryBytes capacity)
    "hard Kind-node + job + system memory exceeds Docker runtime MemTotal"
  require
    (hardCpu <= toInteger (runtimeCpuCount capacity) * 1000)
    "hard Kind-node + job CPU exceeds Docker runtime NCPU"
  mapM_
    ( \(name, budget) -> do
        parsed <- parseBudget name budget
        require
          (parsedMemoryRequest parsed <= availableMemory)
          (name <> ": request exceeds per-node application memory capacity")
        require
          (parsedMemoryLimit parsed <= availableMemory)
          (name <> ": memory limit exceeds per-node application memory capacity")
        require
          (parsedCpuRequest parsed <= availableCpu)
          (name <> ": request exceeds per-node application CPU capacity")
    )
    (componentBudgets resources)
  pure
    ResourceEnvelope
      { envelopeRuntimeCapacity = capacity
      , envelopeNodeCount = nodes
      , envelopeWorkerCount = workers
      , envelopeSchedulableNodeCount = eligible
      , envelopeNodeMemoryBytes = nodeMemory
      , envelopeNodeCpuMilli = nodeCpu
      , envelopeNodeSystemMemoryBytes = nodeSystemMemory
      , envelopeNodeSystemCpuMilli = nodeSystemCpu
      , envelopeNodeApplicationMemoryBytes = availableMemory
      , envelopeNodeApplicationCpuMilli = availableCpu
      , envelopeJobMemoryBytes = jobMemory
      , envelopeJobCpuMilli = jobCpu
      , envelopeSystemReserveBytes = systemMemory
      , envelopeHardMemoryBytes = hardMemory
      , envelopeHardCpuMilli = hardCpu
      , envelopeMemoryHeadroomBytes = runtimeMemoryBytes capacity - hardMemory
      , envelopeCpuHeadroomMilli = toInteger (runtimeCpuCount capacity) * 1000 - hardCpu
      , envelopePodLimitsMayOvercommit = True
      }

componentBudgets :: ClusterResources -> [(Text, ComponentBudget)]
componentBudgets resources =
  [ ("registry", registry resources)
  , ("minio", minio resources)
  , ("pulsar", pulsar resources)
  , ("postgres", postgres resources)
  , ("prometheus", prometheus resources)
  , ("grafana", grafana resources)
  , ("jitmlService", jitmlService resources)
  , ("jitmlDemo", jitmlDemo resources)
  , ("tensorboard", tensorboard resources)
  , ("supporting", supporting resources)
  , ("gateway", gateway resources)
  , ("numericalWorkload", numericalWorkload resources)
  ]

-- | Necessary request-capacity checks for the supplied rendered inventory.
-- These are not a complete multidimensional scheduling/bin-packing proof and
-- cannot establish coverage of workloads the caller did not supply.
validateWorkloadRequests :: ResourceEnvelope -> [WorkloadBudget] -> Either Text ()
validateWorkloadRequests envelope workloads = do
  require (not (null workloads)) "rendered workload inventory must be nonempty"
  let names = fmap workloadName workloads
  require
    (all (\name -> not (Text.null name) && Text.strip name == name) names)
    "invalid rendered workload name"
  require (Set.size (Set.fromList names) == length names) "duplicate rendered workload name"
  parsed <- traverse parseWorkload workloads
  let memory = sum [parsedReplicas budget * parsedMemoryRequest budget | (_, budget) <- parsed]
      cpu = sum [parsedReplicas budget * parsedCpuRequest budget | (_, budget) <- parsed]
      workerMemory = sum [parsedReplicas budget * parsedMemoryRequest budget | (ComputeWorkerNodes, budget) <- parsed]
      workerCpu = sum [parsedReplicas budget * parsedCpuRequest budget | (ComputeWorkerNodes, budget) <- parsed]
  require
    (memory <= envelopeSchedulableNodeCount envelope * envelopeNodeApplicationMemoryBytes envelope)
    "rendered workload requests exceed schedulable-node memory capacity"
  require
    (cpu <= envelopeSchedulableNodeCount envelope * envelopeNodeApplicationCpuMilli envelope)
    "rendered workload requests exceed schedulable-node CPU capacity"
  require
    (workerMemory <= envelopeWorkerCount envelope * envelopeNodeApplicationMemoryBytes envelope)
    "worker-only requests exceed compute-worker memory capacity"
  require
    (workerCpu <= envelopeWorkerCount envelope * envelopeNodeApplicationCpuMilli envelope)
    "worker-only requests exceed compute-worker CPU capacity"
 where
  parseWorkload workload = do
    parsed <- parseBudget (workloadName workload) (workloadResources workload)
    require
      (parsedMemoryRequest parsed <= envelopeNodeApplicationMemoryBytes envelope)
      (workloadName workload <> ": request cannot fit one eligible node's memory")
    require
      (parsedMemoryLimit parsed <= envelopeNodeApplicationMemoryBytes envelope)
      (workloadName workload <> ": memory limit cannot fit one eligible node's application capacity")
    require
      (parsedCpuRequest parsed <= envelopeNodeApplicationCpuMilli envelope)
      (workloadName workload <> ": request cannot fit one eligible node's CPU")
    pure (workloadPlacement workload, parsed)

renderResourceEnvelope :: ResourceEnvelope -> Text
renderResourceEnvelope envelope =
  Text.unlines
    [ "Hard VM memory envelope (bytes): " <> shown (envelopeHardMemoryBytes envelope)
    , "Hard VM CPU envelope (millicores): " <> shown (envelopeHardCpuMilli envelope)
    , "Runtime memory headroom (bytes): " <> shown (envelopeMemoryHeadroomBytes envelope)
    , "Runtime CPU headroom (millicores): " <> shown (envelopeCpuHeadroomMilli envelope)
    , "Kind nodes / application-eligible nodes: "
        <> shown (envelopeNodeCount envelope)
        <> " / "
        <> shown (envelopeSchedulableNodeCount envelope)
    , "Application memory per node after system reserve (bytes): "
        <> shown (envelopeNodeApplicationMemoryBytes envelope)
    , "Application CPU per node after system reserve (millicores): "
        <> shown (envelopeNodeApplicationCpuMilli envelope)
    , "Nominal pod limits may overcommit their hard parent nodes; OOM remains possible."
    , "Rendered workload coverage and scheduler placement require separate verification."
    ]
 where
  shown = Text.pack . show
