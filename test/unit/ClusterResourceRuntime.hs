{-# LANGUAGE OverloadedStrings #-}

module ClusterResourceRuntime (tests) where

import Data.Aeson (Value, encode, object, (.=))
import Data.Aeson.Key qualified as Key
import Data.ByteString.Lazy qualified as Lazy
import Data.Either (isLeft)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Encoding
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Cluster.ResourceBudget
  ( ResourceEnvelope (..)
  , RuntimeCapacity (..)
  , kubeletSystemReservation
  , parseMemoryBytes
  , validateResourceEnvelope
  )
import JitML.Cluster.ResourceRuntime
  ( CallerResourceLimits (..)
  , kubeletReservationsFromNodeCapacities
  , reserveCallerForSibling
  , resolveUnifiedCgroupDirectory
  , validateCallerResourceLimits
  )
import JitML.Cluster.Resources (ClusterResources (..), defaultClusterResources)
import JitML.Substrate (Substrate (LinuxCPU))

tests :: TestTree
tests =
  testGroup
    "actual caller resource limits"
    [ testCase "finite four GiB two CPU caller matches the selected job" $ do
        envelope <- jobEnvelope
        validateCallerResourceLimits envelope (CallerResourceLimits "4294967296\n" "0\n" "200000 100000\n")
          @?= Right ()
    , testCase "the old six GiB caller refuses the four GiB profile" $ do
        envelope <- jobEnvelope
        rejected
          (validateCallerResourceLimits envelope (CallerResourceLimits "6442450944" "0" "200000 100000"))
    , testCase "CPU quota comparison is exact and does not round a slight excess down" $ do
        envelope <- jobEnvelope
        rejected
          (validateCallerResourceLimits envelope (CallerResourceLimits "4294967296" "0" "200001 100000"))
        validateCallerResourceLimits envelope (CallerResourceLimits "4294967296" "0" "1 3") @?= Right ()
    , testCase "unlimited, missing and malformed controls fail closed" $ do
        envelope <- jobEnvelope
        mapM_
          (rejected . validateCallerResourceLimits envelope)
          [ CallerResourceLimits "max" "0" "200000 100000"
          , CallerResourceLimits "4294967296" "0" "max 100000"
          , CallerResourceLimits "" "0" "200000 100000"
          , CallerResourceLimits "4Gi" "0" "200000 100000"
          , CallerResourceLimits "0" "0" "200000 100000"
          , CallerResourceLimits "4294967296" "0" "0 100000"
          , CallerResourceLimits "4294967296" "0" "200000 0"
          ]
    , testCase "any caller swap allowance refuses" $ do
        envelope <- jobEnvelope
        rejected
          (validateCallerResourceLimits envelope (CallerResourceLimits "4294967296" "1" "200000 100000"))
    , testCase "snapshot sibling splits the existing job slot without increasing VM totals" $ do
        envelope <- jobEnvelope
        split <- either (assertFailure . show) pure (reserveCallerForSibling 536870912 500 envelope)
        envelopeJobMemoryBytes split @?= 3758096384
        envelopeJobCpuMilli split @?= 1500
        envelopeHardMemoryBytes split @?= envelopeHardMemoryBytes envelope
        envelopeHardCpuMilli split @?= envelopeHardCpuMilli envelope
        envelopeNodeMemoryBytes split @?= envelopeNodeMemoryBytes envelope
        validateCallerResourceLimits split (CallerResourceLimits "3221225472" "0" "150000 100000")
          @?= Right ()
        rejected
          (validateCallerResourceLimits split (CallerResourceLimits "4294967296" "0" "150000 100000"))
        rejected
          (validateCallerResourceLimits split (CallerResourceLimits "3221225472" "0" "150001 100000"))
    , testCase "Mac lifecycle caller and helper fit the selected one CPU job together" $ do
        envelope <- jobEnvelope
        split <-
          either
            (assertFailure . show)
            pure
            (reserveCallerForSibling 536870912 500 (envelope {envelopeJobCpuMilli = 1000}))
        validateCallerResourceLimits split (CallerResourceLimits "3221225472" "0" "50000 100000")
          @?= Right ()
        rejected
          (validateCallerResourceLimits split (CallerResourceLimits "3221225472" "0" "100000 100000"))
    , testCase "invalid or exhausting sibling reservations refuse before caller observation" $ do
        envelope <- jobEnvelope
        mapM_
          (\(memory, cpu) -> rejected (reserveCallerForSibling memory cpu envelope))
          [(0, 500), (-1, 500), (536870912, 0), (536870912, -1), (4294967296, 500), (536870912, 2000)]
    , testCase "a four KiB live capacity increase changes the reserve, not the application budget" $ do
        envelope <- calibrationEnvelope
        let observedMemory = 16 * gib + 4096
            raw = nodeList "NodeList" (bothNodes "4" (Text.pack (show observedMemory)))
        actual <-
          accepted (kubeletReservationsFromNodeCapacities LinuxCPU calibrationResources envelope raw)
        actual @?= [(controlPlane, ("2750m", "12884905984")), (worker, ("2750m", "12884905984"))]
        oldMemoryReserve <- accepted (parseMemoryBytes (snd (kubeletSystemReservation envelope)))
        -- The old Docker-derived reserve admitted exactly the observed excess.
        observedMemory - oldMemoryReserve @?= 4 * gib + 4096
        mapM_
          ( \(_, (_, memory)) -> do
              reserve <- accepted (parseMemoryBytes memory)
              reserve - oldMemoryReserve @?= 4096
              observedMemory - reserve @?= 4 * gib
          )
          actual
        envelopeNodeApplicationMemoryBytes envelope @?= 4 * gib
        envelopeJobMemoryBytes envelope @?= 4 * gib
        envelopeJobCpuMilli envelope @?= 1000
    , testCase "each live node capacity is used independently in canonical node order" $ do
        envelope <- calibrationEnvelope
        kubeletReservationsFromNodeCapacities
          LinuxCPU
          calibrationResources
          envelope
          ( nodeList
              "NodeList"
              [ capacityNode worker ["cpu" .= ("4" :: Text), "memory" .= ("16Gi" :: Text)]
              , capacityNode controlPlane ["cpu" .= ("1500m" :: Text), "memory" .= ("5Gi" :: Text)]
              ]
          )
          @?= Right [(controlPlane, ("250m", "1073741824")), (worker, ("2750m", "12884901888"))]
    , testCase "matching live and Docker capacities preserve the existing reservation" $ do
        envelope <- calibrationEnvelope
        let desired = kubeletSystemReservation envelope
        kubeletReservationsFromNodeCapacities
          LinuxCPU
          calibrationResources
          envelope
          (nodeList "List" (bothNodes "4" "16Gi"))
          @?= Right [(controlPlane, desired), (worker, desired)]
    , testCase "missing, duplicate and unexpected node capacity identities refuse" $ do
        envelope <- calibrationEnvelope
        let cp = capacityNode controlPlane validCapacity
            wk = capacityNode worker validCapacity
            foreignNode = capacityNode "foreign-worker" validCapacity
        mapM_
          ( rejected
              . kubeletReservationsFromNodeCapacities LinuxCPU calibrationResources envelope
              . nodeList "NodeList"
          )
          [[], [cp], [wk], [cp, cp], [cp, wk, cp], [cp, foreignNode], [cp, wk, foreignNode]]
    , testCase "missing or malformed live capacity fields refuse without guessing" $ do
        envelope <- calibrationEnvelope
        let cp = capacityNode controlPlane validCapacity
            candidates =
              [ object ["status" .= object ["capacity" .= object validCapacity]]
              , object ["metadata" .= object [], "status" .= object ["capacity" .= object validCapacity]]
              , object ["metadata" .= object ["name" .= worker]]
              , object ["metadata" .= object ["name" .= worker], "status" .= object []]
              , capacityNode worker []
              , capacityNode worker ["cpu" .= ("4" :: Text)]
              , capacityNode worker ["memory" .= ("16Gi" :: Text)]
              , capacityNode worker ["cpu" .= (4 :: Int), "memory" .= ("16Gi" :: Text)]
              , capacityNode worker ["cpu" .= ("4" :: Text), "memory" .= (16 * gib)]
              , capacityNode worker ["cpu" .= (Nothing :: Maybe Text), "memory" .= ("16Gi" :: Text)]
              , capacityNode worker ["cpu" .= ("4" :: Text), "memory" .= (Nothing :: Maybe Text)]
              ]
        mapM_
          ( \wk ->
              rejected
                ( kubeletReservationsFromNodeCapacities
                    LinuxCPU
                    calibrationResources
                    envelope
                    (nodeList "NodeList" [cp, wk])
                )
          )
          candidates
    , testCase "invalid quantities and capacities with no positive system reservation refuse" $ do
        envelope <- calibrationEnvelope
        mapM_
          ( \cpu ->
              rejected
                ( kubeletReservationsFromNodeCapacities
                    LinuxCPU
                    calibrationResources
                    envelope
                    (nodeList "NodeList" (bothNodes cpu "16Gi"))
                )
          )
          ["0", "-1", "NaN", "4Gi", "1250m", "1000m"]
        mapM_
          ( rejected
              . kubeletReservationsFromNodeCapacities LinuxCPU calibrationResources envelope
              . nodeList "NodeList"
              . bothNodes "4"
          )
          ["0", "-1Gi", "4GB", "4Gi", "3Gi", "4.00000000001Gi"]
    , testCase "malformed or wrong-kind node inventory refuses" $ do
        envelope <- calibrationEnvelope
        mapM_
          (rejected . kubeletReservationsFromNodeCapacities LinuxCPU calibrationResources envelope)
          [ "not-json"
          , "[]"
          , "{}"
          , nodeList "PodList" (bothNodes "4" "16Gi")
          , jsonText (object ["kind" .= ("NodeList" :: Text), "items" .= bothNodes "4" "16Gi"])
          , jsonText (object ["apiVersion" .= ("v1" :: Text), "items" .= bothNodes "4" "16Gi"])
          , jsonText
              ( object
                  ["apiVersion" .= ("v2" :: Text), "kind" .= ("NodeList" :: Text), "items" .= bothNodes "4" "16Gi"]
              )
          , jsonText
              ( object
                  [ "apiVersion" .= ("v1" :: Text)
                  , "kind" .= ("NodeList" :: Text)
                  , "items" .= (Nothing :: Maybe [Value])
                  ]
              )
          ]
    , testCase "private cgroup namespace root maps to its visible mount" $
        resolveUnifiedCgroupDirectory "0::/\n" (mount "/" "/sys/fs/cgroup") @?= Right "/sys/fs/cgroup"
    , testCase "subtree mount removes the root prefix exactly once" $
        resolveUnifiedCgroupDirectory "0::/batch/job\n" (mount "/batch" "/sys/fs/cgroup")
          @?= Right "/sys/fs/cgroup/job"
    , testCase "escaped mount roots map without splitting a cgroup name" $
        resolveUnifiedCgroupDirectory "0::/batch group/job\n" (mount "/batch\\040group" "/sys/fs/cgroup")
          @?= Right "/sys/fs/cgroup/job"
    , testCase "unmatched or ambiguous views refuse rather than reading another cgroup" $ do
        rejected (resolveUnifiedCgroupDirectory "0::/other/job\n" (mount "/batch" "/sys/fs/cgroup"))
        rejected
          (resolveUnifiedCgroupDirectory "0::/\n" (mount "/" "/sys/fs/cgroup" <> mount "/" "/other/cgroup"))
    , testCase "legacy, hybrid and traversing membership refuse" $
        mapM_
          (\membership -> rejected (resolveUnifiedCgroupDirectory membership (mount "/" "/sys/fs/cgroup")))
          ["5:memory:/job\n", "0::/\n5:memory:/job\n", "0::/../other\n"]
    , testCase "a similarly prefixed mount root is not an ancestor" $
        rejected (resolveUnifiedCgroupDirectory "0::/batch-two/job\n" (mount "/batch" "/sys/fs/cgroup"))
    ]

mount :: Text -> Text -> Text
mount root point = "29 23 0:26 " <> root <> " " <> point <> " ro,nosuid,nodev,noexec,relatime - cgroup2 cgroup rw\n"

jobEnvelope :: IO ResourceEnvelope
jobEnvelope =
  either (assertFailure . show) pure $
    validateResourceEnvelope
      (RuntimeCapacity 4 (16 * 1073741824))
      ( defaultClusterResources
          { nodeMemoryMiB = 5120
          , nodeCpus = "1"
          , jobMemoryMiB = 4096
          , jobCpus = "2"
          , scheduleOnControlPlane = True
          }
      )

rejected :: Either Text value -> Assertion
rejected result = assertBool "unsafe caller limit, cgroup mapping or node capacity accepted" (isLeft result)

accepted :: Either Text value -> IO value
accepted = either (assertFailure . Text.unpack) pure

gib :: Integer
gib = 1073741824

controlPlane, worker :: Text
controlPlane = "jitml-linux-cpu-control-plane"
worker = "jitml-linux-cpu-worker"

validCapacity :: [(Key.Key, Value)]
validCapacity = ["cpu" .= ("4" :: Text), "memory" .= ("16Gi" :: Text)]

capacityNode :: Text -> [(Key.Key, Value)] -> Value
capacityNode name fields =
  object
    [ "metadata" .= object ["name" .= name]
    , "status" .= object ["capacity" .= object fields]
    ]

bothNodes :: Text -> Text -> [Value]
bothNodes cpu memory =
  fmap (\name -> capacityNode name ["cpu" .= cpu, "memory" .= memory]) [controlPlane, worker]

nodeList :: Text -> [Value] -> Text
nodeList kind nodes = jsonText (object ["apiVersion" .= ("v1" :: Text), "kind" .= kind, "items" .= nodes])

jsonText :: Value -> Text
jsonText = Encoding.decodeUtf8 . Lazy.toStrict . encode

calibrationResources :: ClusterResources
calibrationResources =
  defaultClusterResources
    { nodeMemoryMiB = 5120
    , nodeCpus = "1.5"
    , jobMemoryMiB = 4096
    , jobCpus = "1"
    , scheduleOnControlPlane = True
    }

calibrationEnvelope :: IO ResourceEnvelope
calibrationEnvelope = accepted (validateResourceEnvelope (RuntimeCapacity 4 (16 * gib)) calibrationResources)
