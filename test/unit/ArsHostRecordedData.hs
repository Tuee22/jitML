{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

module ArsHostRecordedData (arsHostRecordedDataTests) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.Char (digitToInt)
import Data.List (find)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)
import GHC.Float (castDoubleToWord64, castWord64ToDouble)
import Test.Tasty (TestTree, testGroup, withResource)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Plan.Plan qualified as Plan
import JitML.Product.ArsHostReference qualified as Reference
import JitML.Product.Matrix qualified as Matrix
import JitML.RL.Algorithms.ArsTrainer qualified as Ars
import JitML.RL.Algorithms.Common qualified as Common
import JitML.RL.ArsHostTrace qualified as Trace
import JitML.RL.ProductBudget qualified as Budget
import JitML.RL.Simulator qualified as Sim
import JitML.Substrate (Substrate (LinuxCPU))

-- Every context is an explicitly untrusted offline record. Actual bounded raw
-- trainer output exercises numerical capture/codec/replay, not publication,
-- canonical full-budget execution, accepted steps or producer authentication.
arsHostRecordedDataTests :: TestTree
arsHostRecordedDataTests =
  withResource (Ars.trainArsOnCartpoleRaw smallConfig) (const (pure ())) $ \getRaw ->
    testGroup
      "ARS host recorded provenance data and lossless replay"
      [ testCase "actual bounded ARS raw return roundtrips every recorded bit and replays locally" $ do
          raw <- getRaw
          Common.observedEnvironmentTransitionCount (Common.rawTrainerCounters raw) @?= 128
          Common.observedOptimizerUpdateCount (Common.rawTrainerCounters raw) @?= 2
          trace <- traceFrom raw
          Trace.validateArsHostTraceLocal trace @?= Right ()
          decoded <- expectRight (Trace.decodeArsHostTrace (Trace.encodeArsHostTrace trace))
          Trace.encodeArsHostTrace decoded @?= Trace.encodeArsHostTrace trace
          Trace.arsHostTraceSha256 decoded @?= Trace.arsHostTraceSha256 trace
          parameterBits (Common.rawTrainerInitialParams (Trace.arsHostTraceObservation decoded))
            @?= parameterBits (Common.rawTrainerInitialParams raw)
          parameterBits (Common.rawTrainerFinalParams (Trace.arsHostTraceObservation decoded))
            @?= parameterBits (Common.rawTrainerFinalParams raw)
      , testCase "recorded reference roundtrips and matches the exact trace and context tuple" $ do
          trace <- getRaw >>= traceFrom
          reference <- expectRight (Trace.arsHostTraceRecordedReference trace)
          decoded <-
            expectRight (Reference.decodeArsHostReference (Reference.encodeArsHostReference reference))
          decoded @?= reference
          Trace.validateArsHostTraceReference decoded trace @?= Right ()
          Reference.arsHostReferenceByteLength decoded
            @?= fromIntegral (BS.length (Trace.encodeArsHostTrace trace))
          Plan.planIdText (Reference.arsHostReferencePlanId decoded) @?= Text.replicate 64 "1"
      , testCase "reference encoding agrees with independent Python canonical known answer" $ do
          reference <- expectRight (Reference.refineArsHostReference knownReference)
          Reference.encodeArsHostReference reference @?= fromHex knownReferenceHex
          Reference.decodeArsHostReference (fromHex knownReferenceHex) @?= Right reference
      , testCase "all recorded reference identity substitutions reject at their specific tuple field" $ do
          trace <- getRaw >>= traceFrom
          reference <- expectRight (Trace.arsHostTraceRecordedReference trace)
          let original = Reference.arsHostReferenceToRaw reference
              substitutions =
                [
                  ( "byte length"
                  , original
                      { Reference.rawArsHostReferenceByteLength = Reference.rawArsHostReferenceByteLength original + 1
                      }
                  )
                , ("context SHA", original {Reference.rawArsHostReferenceContextSha256 = Text.replicate 64 "7"})
                , ("plan", original {Reference.rawArsHostReferencePlanId = Text.replicate 64 "7"})
                , ("lane", original {Reference.rawArsHostReferenceLane = "apple-silicon"})
                , ("source", original {Reference.rawArsHostReferenceSourceSha256 = Text.replicate 64 "7"})
                , ("executable", original {Reference.rawArsHostReferenceExecutableSha256 = Text.replicate 64 "7"})
                , ("invocation", original {Reference.rawArsHostReferenceInvocationSha256 = Text.replicate 64 "7"})
                ]
          forM_ substitutions $ \(field, changed) -> do
            checked <- expectRight (Reference.refineArsHostReference changed)
            expectLeft ("reference " <> field <> " differs") (Trace.validateArsHostTraceReference checked trace)
      , testCase "reference grammar uses the actual PlanId parser and rejects path and SHA aliases" $ do
          let invalidPlan = knownReference {Reference.rawArsHostReferencePlanId = "not-a-plan"}
          case Plan.refinePlanIdText "not-a-plan" of
            Left reason -> Reference.refineArsHostReference invalidPlan @?= Left reason
            Right _ -> assertFailure "actual public PlanId parser unexpectedly accepted the negative fixture"
          expectLeft
            "exact content address"
            ( Reference.refineArsHostReference
                knownReference
                  { Reference.rawArsHostReferenceObjectKey =
                      "jitml-checkpoints/offline-ars/artifacts/ars-host-execution/" <> Text.replicate 64 "7" <> ".cbor"
                  }
            )
          expectLeft
            "wrong structure"
            ( Reference.refineArsHostReference
                knownReference
                  { Reference.rawArsHostReferenceObjectKey =
                      "jitml-checkpoints/../offline-ars/artifacts/ars-host-execution/file.cbor"
                  }
            )
          expectLeft
            "SHA-256 is not canonical"
            ( Reference.refineArsHostReference
                knownReference
                  { Reference.rawArsHostReferenceContentSha256 = Text.replicate 64 "A"
                  }
            )
          expectLeft
            "byte length"
            (Reference.refineArsHostReference knownReference {Reference.rawArsHostReferenceByteLength = 0})
      , testCase "reference parser rejects trailing indefinite noncanonical and oversized wire inputs" $ do
          reference <- expectRight (Reference.refineArsHostReference knownReference)
          let encoded = Reference.encodeArsHostReference reference
          expectLeft "trailing" (Reference.decodeArsHostReference (encoded <> BS.singleton 0))
          expectLeft "indefinite" (Reference.decodeArsHostReference (BS.cons 0x9f (BS.drop 1 encoded)))
          expectLeft
            "noncanonical"
            (Reference.decodeArsHostReference (BS.pack [0x98, 11] <> BS.drop 1 encoded))
          expectLeft "byte limit" (Reference.decodeArsHostReference (BS.replicate 8193 0))
      , testCase "foreign numerical runtime decodes as data and cannot pass local exact replay" $ do
          raw <- getRaw
          context <- recordedContext
          let foreignRuntime = Ars.arsNativeNumericalRuntime {Ars.arsRuntimeOperatingSystem = "recorded-foreign-os"}
              changed =
                raw
                  { Common.rawTrainerStats =
                      fmap (mapStep (\s -> s {Ars.arsStepNumericalRuntime = foreignRuntime})) (Common.rawTrainerStats raw)
                  }
          trace <-
            expectRight (Trace.refineArsHostTrace (Trace.RawArsHostTrace context foreignRuntime changed))
          decoded <- expectRight (Trace.decodeArsHostTrace (Trace.encodeArsHostTrace trace))
          Trace.arsHostTraceRuntime decoded @?= foreignRuntime
          expectLeft "numerical runtime differs" (Trace.validateArsHostTraceLocal decoded)
      , testCase "structural data refinement does not assert exact aggregate-step arithmetic" $ do
          raw <- getRaw
          trace <- traceFrom (modifyFirstStep (\s -> s {Ars.arsStepScale = Ars.arsStepScale s + 1}) raw)
          decoded <- expectRight (Trace.decodeArsHostTrace (Trace.encodeArsHostTrace trace))
          expectLeft "ARS applied-step scale differs" (Trace.validateArsHostTraceLocal decoded)
      , testCase "negative zero survives portable bytes and fails a mismatched exact initial chain" $ do
          raw <- getRaw
          let negativeInitial = Common.rawTrainerInitialParams raw VU.// [(0, -0.0)]
          trace <- traceFrom raw {Common.rawTrainerInitialParams = negativeInitial}
          decoded <- expectRight (Trace.decodeArsHostTrace (Trace.encodeArsHostTrace trace))
          let bits = parameterBits (Common.rawTrainerInitialParams (Trace.arsHostTraceObservation decoded))
          case bits of
            first : _ -> first @?= 0x8000000000000000
            [] -> assertFailure "actual initial vector was empty"
          assertBool
            "negative-zero wire payload is explicitly little-endian IEEE64"
            (BS.pack [0x58, 0x40, 0, 0, 0, 0, 0, 0, 0, 0x80] `BS.isInfixOf` Trace.encodeArsHostTrace trace)
          positive <- traceFrom raw
          assertBool
            "signed zero changes exact recorded bytes"
            (Trace.encodeArsHostTrace trace /= Trace.encodeArsHostTrace positive)
          expectLeft "initial parameters differ" (Trace.validateArsHostTraceLocal decoded)
      , testCase "actual finite no-op and zero-iteration returns remain data without eligibility" $ do
          forM_ [smallConfig {Ars.arsStepSize = 0}, smallConfig {Ars.arsIterations = 0}] $ \config -> do
            raw <- Ars.trainArsOnCartpoleRaw config
            trace <- traceFrom raw
            Trace.validateArsHostTraceLocal trace @?= Right ()
            decoded <- expectRight (Trace.decodeArsHostTrace (Trace.encodeArsHostTrace trace))
            parameterBits (Common.rawTrainerInitialParams (Trace.arsHostTraceObservation decoded))
              @?= parameterBits (Common.rawTrainerFinalParams (Trace.arsHostTraceObservation decoded))
      , testCase "raw finite shape refinement rejects dropped duplicate and reordered applications" $ do
          raw <- getRaw
          context <- recordedContext
          let check changed = Trace.refineArsHostTrace (Trace.RawArsHostTrace context Ars.arsNativeNumericalRuntime changed)
              observations = Common.rawTrainerStats raw
          expectLeft "observation count differs" (check raw {Common.rawTrainerStats = []})
          expectLeft
            "observation count differs"
            (check raw {Common.rawTrainerStats = observations <> observations})
          expectLeft "iteration index differs" (check raw {Common.rawTrainerStats = reverse observations})
      , testCase "nonfinite initial final and step scalars fail recorded finite refinement" $ do
          raw <- getRaw
          context <- recordedContext
          let check changed = Trace.refineArsHostTrace (Trace.RawArsHostTrace context Ars.arsNativeNumericalRuntime changed)
          forM_ [0 / 0, 1 / 0, -(1 / 0)] $ \bad -> do
            expectLeft
              "nonfinite F64"
              (check raw {Common.rawTrainerInitialParams = Common.rawTrainerInitialParams raw VU.// [(0, bad)]})
            expectLeft
              "nonfinite F64"
              (check raw {Common.rawTrainerFinalParams = Common.rawTrainerFinalParams raw VU.// [(0, bad)]})
            expectLeft "nonfinite F64" (check (modifyFirstStep (\s -> s {Ars.arsStepScale = bad}) raw))
      , testCase "direction perturbation kept and vector counts reject at their actual raw boundaries" $ do
          raw <- getRaw
          context <- recordedContext
          let check change =
                Trace.refineArsHostTrace
                  (Trace.RawArsHostTrace context Ars.arsNativeNumericalRuntime (modifyFirstStep change raw))
          expectLeft
            "sampled direction count differs"
            (check (\step -> step {Ars.arsStepSampledDirections = []}))
          expectLeft
            "evaluated perturbation count differs"
            (check (\step -> step {Ars.arsStepEvaluatedPerturbations = []}))
          expectLeft "kept direction count differs" (check (\step -> step {Ars.arsStepKeptDirections = []}))
          expectLeft "vector dimension differs" (check (\step -> step {Ars.arsStepUpdateDirection = []}))
      , testCase "full Word64 observed counters remain recorded data and exact replay rejects substitutions" $ do
          raw <- getRaw
          transitions <- expectRight (Common.mkObservedTrainerCounters (toInteger (maxBound :: Word64)) 2)
          trace <- traceFrom raw {Common.rawTrainerCounters = transitions}
          decoded <- expectRight (Trace.decodeArsHostTrace (Trace.encodeArsHostTrace trace))
          Common.observedEnvironmentTransitionCount
            (Common.rawTrainerCounters (Trace.arsHostTraceObservation decoded))
            @?= maxBound
          expectLeft "observed physical transition count differs" (Trace.validateArsHostTraceLocal decoded)
          updates <- expectRight (Common.mkObservedTrainerCounters 128 3)
          changed <- traceFrom raw {Common.rawTrainerCounters = updates}
          expectLeft "observed optimizer update count differs" (Trace.validateArsHostTraceLocal changed)
      , testCase "overflow and aggregate resource counts reject without constructing trace vectors" $ do
          expectLeft
            "configuration exceeds"
            (Trace.arsHostTraceCoordinateCount smallConfig {Ars.arsActionCount = maxBound, Ars.arsObsSize = 2})
          expectLeft
            "vector-coordinate budget"
            ( Trace.arsHostTraceCoordinateCount
                smallConfig
                  { Ars.arsIterations = 4096
                  , Ars.arsNumDirections = 16
                  , Ars.arsTopB = 8
                  , Ars.arsActionCount = 6
                  , Ars.arsObsSize = 127
                  }
            )
          expectLeft
            "configuration exceeds"
            (Trace.arsHostTraceCoordinateCount smallConfig {Ars.arsIterations = 4097})
          expectLeft
            "input exceeds"
            (Trace.decodeArsHostTrace (BS.replicate (fromInteger Trace.arsHostTraceMaxBytes + 1) 0))
      , testCase "trace parser rejects truncated trailing indefinite and noncanonical headers" $ do
          encoded <- Trace.encodeArsHostTrace <$> (getRaw >>= traceFrom)
          expectLeft "truncated" (Trace.decodeArsHostTrace (BS.take (BS.length encoded - 1) encoded))
          expectLeft "trailing" (Trace.decodeArsHostTrace (encoded <> BS.singleton 0))
          expectLeft "indefinite" (Trace.decodeArsHostTrace (BS.cons 0x9f (BS.drop 1 encoded)))
          expectLeft "noncanonical" (Trace.decodeArsHostTrace (BS.pack [0x98, 10] <> BS.drop 1 encoded))
          expectLeft
            "field or byte count"
            (Trace.decodeArsHostTrace (BS.singleton 0x9b <> BS.replicate 8 0xff <> BS.drop 1 encoded))
      , testCase "trace vector preflight rejects huge declared byte lengths and nonfinite payloads" $ do
          encoded <- Trace.encodeArsHostTrace <$> (getRaw >>= traceFrom)
          offset <- initialVectorOffset encoded
          let huge =
                BS.take offset encoded <> BS.singleton 0x5b <> BS.replicate 8 0xff <> BS.drop (offset + 2) encoded
              nanBits = BS.pack [0, 0, 0, 0, 0, 0, 0xf8, 0x7f]
              nonfinite = BS.take (offset + 2) encoded <> nanBits <> BS.drop (offset + 10) encoded
          expectLeft "field or byte count" (Trace.decodeArsHostTrace huge)
          expectLeft "nonfinite F64" (Trace.decodeArsHostTrace nonfinite)
      , testCase "context uses exact public compiled transport without normalising malformed text" $ do
          context <- recordedContext
          let bad = Trace.rawArsHostCompiledTransport context <> "\n"
          case Budget.parseCompiledRlPlanTransport bad of
            Left reason -> Trace.refineArsHostContext context {Trace.rawArsHostCompiledTransport = bad} @?= Left reason
            Right _ -> assertFailure "actual public transport parser unexpectedly accepted altered canonical text"
          expectLeft
            "row differs"
            (Trace.refineArsHostContext context {Trace.rawArsHostRowId = "ARS/mountain-car"})
          expectLeft
            "execution binding"
            (Trace.refineArsHostContext context {Trace.rawArsHostExecutionBinding = "verified-true"})
      , testCase "small actual observation cannot masquerade as the canonical compiled full run" $ do
          raw <- getRaw
          trace <- traceFrom raw
          plan <- canonicalPlan "cartpole"
          expectLeft "exact supplied compiled recipe" (Trace.validateArsHostTracePlan plan trace)
      , testCase "all four actual canonical compiled configurations fit frozen limits and bind exactly" $ do
          forM_
            [ ("cartpole", 8, 800000, 17216)
            , ("mountain-car", 6, 320000, 12912)
            , ("lunar-lander", 32, 1600000, 68864)
            , ("key-door-grid", 762, 320000, 1639824)
            ]
            $ \(environment, dimension, transitions, coordinates) -> do
              plan <- canonicalPlan environment
              config <- canonicalConfig plan
              Trace.validateArsHostConfigForPlan plan config @?= Right ()
              Ars.arsIterations config @?= 50
              Ars.arsActionCount config * Ars.arsObsSize config @?= dimension
              Trace.arsHostTraceCoordinateCount config @?= Right coordinates
              schedule <- expectRight (Budget.canonicalProductRlSchedule "ARS" environment)
              Budget.scheduleObservedEnvironmentSteps schedule @?= transitions
              Budget.compiledRlSchedule plan @?= Just schedule
              assertBool
                "full vector payload plus conservative metadata fits byte cap"
                ( 65536 + 4096 + 16 * toInteger dimension + 50 * (8 * 43 * toInteger dimension + 8192)
                    <= Trace.arsHostTraceMaxBytes
                )
      , testCase "typed plan binder rejects actual recipe parameter and plan schedule substitutions" $ do
          plan <- canonicalPlan "cartpole"
          config <- canonicalConfig plan
          forM_
            [ config {Ars.arsSeed = 43}
            , config {Ars.arsTopB = 1}
            , config {Ars.arsStepSize = 0}
            , config {Ars.arsNoiseStd = 0.2}
            , config {Ars.arsIterations = 49}
            ]
            $ \changed ->
              expectLeft "exact supplied compiled recipe" (Trace.validateArsHostConfigForPlan plan changed)
          expectLeft
            "public compiler projection"
            (Trace.validateArsHostConfigForPlan plan {Budget.compiledRlSchedule = Nothing} config)
      , testCase "trace domain version and replay contract substitutions fail their exact wire boundary" $ do
          encoded <- Trace.encodeArsHostTrace <$> (getRaw >>= traceFrom)
          let versionOffset = 3 + Text.length ("jitml-ars-host-linear-trace" :: Text)
              changedDomain = BS.take 3 encoded <> BS.singleton 0x78 <> BS.drop 4 encoded
              changedVersion = BS.take versionOffset encoded <> BS.singleton 2 <> BS.drop (versionOffset + 1) encoded
              changedContract = BS.take (BS.length encoded - 1) encoded <> BS.singleton 0x32
          expectLeft "domain differs" (Trace.decodeArsHostTrace changedDomain)
          expectLeft "field or byte count" (Trace.decodeArsHostTrace changedVersion)
          expectLeft "replay contract differs" (Trace.decodeArsHostTrace changedContract)
      , testCase "finite minimum subnormal and largest binary64 payloads remain bit exact as data" $ do
          raw <- getRaw
          let expectedBits = [1, 0x7fefffffffffffff, 0x8000000000000000]
              changedInitial = Common.rawTrainerInitialParams raw VU.// zip [0 ..] (fmap castWord64ToDouble expectedBits)
          trace <- traceFrom raw {Common.rawTrainerInitialParams = changedInitial}
          decoded <- expectRight (Trace.decodeArsHostTrace (Trace.encodeArsHostTrace trace))
          take 3 (parameterBits (Common.rawTrainerInitialParams (Trace.arsHostTraceObservation decoded)))
            @?= expectedBits
          expectLeft "initial parameters differ" (Trace.validateArsHostTraceLocal decoded)
      , testCase "flat canonical reference namespaces explicitly reject slash child and generic path IDs" $ do
          forM_
            [ "ARS/cartpole"
            , "offline-ars/seed-1"
            , "../offline-ars"
            , "offline_ars"
            , ""
            , "."
            , ".."
            , "a/b"
            , "a\\b"
            , "a%2Fb"
            , "a%2fb"
            , "offline ars"
            , "λ"
            ]
            $ \experiment ->
              expectLeft
                "experiment namespace is not canonical"
                (Reference.arsHostObjectKey experiment (Text.replicate 64 "2"))
          Reference.arsHostObjectKey "offline-ars-seed-1" (Text.replicate 64 "2")
            @?= Right
              ( "jitml-checkpoints/offline-ars-seed-1/artifacts/ars-host-execution/"
                  <> Text.replicate 64 "2"
                  <> ".cbor"
              )
          actualCanonicalNamespaceControls
      ]

-- Actual registry-derived namespace positives, not actual training/admission.
actualCanonicalNamespaceControls :: Assertion
actualCanonicalNamespaceControls =
  forM_ ["cartpole", "mountain-car", "lunar-lander", "key-door-grid"] $ \environment -> do
    row <-
      maybe
        (assertFailure "actual canonical ARS row missing" >> fail "unreachable")
        pure
        (find ((== "ARS/" <> environment) . Matrix.rowId) Matrix.allProductRows)
    currentPlanId <- case Matrix.projectProductRow LinuxCPU row of
      Plan.Success (Matrix.SomeProductProjection _ projection) ->
        pure (Plan.planIdText (Matrix.productProjectionPlanId projection))
      Plan.Failure errors -> assertFailure (show errors) >> fail "unreachable"
    let experiment = Matrix.productRowExperimentHash row
        digest = Reference.rawArsHostReferenceContentSha256 knownReference
    experiment @?= "product-row-ARS." <> environment
    key <- expectRight (Reference.arsHostObjectKey experiment digest)
    key @?= "jitml-checkpoints/" <> experiment <> "/artifacts/ars-host-execution/" <> digest <> ".cbor"
    reference <-
      expectRight
        ( Reference.refineArsHostReference
            knownReference
              { Reference.rawArsHostReferenceObjectKey = key
              , Reference.rawArsHostReferencePlanId = currentPlanId
              }
        )
    Reference.decodeArsHostReference (Reference.encodeArsHostReference reference) @?= Right reference
    compiled <- canonicalPlan environment
    context <- recordedContext
    let current =
          context
            { Trace.rawArsHostRowId = Matrix.rowId row
            , Trace.rawArsHostExperiment = experiment
            , Trace.rawArsHostPlanId = currentPlanId
            , Trace.rawArsHostCompiledTransport = Budget.renderCompiledRlPlanTransport compiled
            }
    checkedContext <- expectRight (Trace.refineArsHostContext current)
    Trace.arsHostContextToRaw checkedContext @?= current

smallConfig :: Ars.ArsTrainConfig
smallConfig =
  Ars.defaultArsTrainConfig
    { Ars.arsIterations = 2
    , Ars.arsNumDirections = 4
    , Ars.arsTopB = 2
    , Ars.arsMaxEpisodeSteps = 8
    }

traceFrom :: Ars.ArsTrainObservation -> IO Trace.ArsHostTrace
traceFrom observed = do
  context <- recordedContext
  expectRight
    (Trace.refineArsHostTrace (Trace.RawArsHostTrace context Ars.arsNativeNumericalRuntime observed))

recordedContext :: IO Trace.RawArsHostContext
recordedContext = do
  plan <- canonicalPlan "cartpole"
  pure
    Trace.RawArsHostContext
      { Trace.rawArsHostRowId = "ARS/cartpole"
      , Trace.rawArsHostExperiment = "offline-ars"
      , Trace.rawArsHostPlanId = Text.replicate 64 "1"
      , Trace.rawArsHostCompiledTransport = Budget.renderCompiledRlPlanTransport plan
      , Trace.rawArsHostLane = "linux-cpu"
      , Trace.rawArsHostSourceSha256 = Text.replicate 64 "4"
      , Trace.rawArsHostExecutableSha256 = Text.replicate 64 "5"
      , Trace.rawArsHostInvocationSha256 = Text.replicate 64 "6"
      , Trace.rawArsHostExecutionBinding = "direct-local-attempt-v1"
      , Trace.rawArsHostKernelOS = "offline-record"
      , Trace.rawArsHostKernelMachine = "offline-record"
      , Trace.rawArsHostKernelRelease = "offline-record"
      , Trace.rawArsHostSimulatorContract = "offline-cartpole-fixture-v1"
      , Trace.rawArsHostProcessId = "123"
      , Trace.rawArsHostAttemptId = "offline-fixture-not-authority"
      }

canonicalPlan :: Text -> IO Budget.CompiledRlPlan
canonicalPlan environment =
  expectRight
    ( Budget.compileRlPlan
        Budget.TrainingPlan
          { Budget.trainingPlanTrainerKind = "ars"
          , Budget.trainingPlanEnvironment = environment
          , Budget.trainingPlanSeed = 42
          , Budget.trainingPlanMaxEpisodeSteps = Budget.productRlDefaultMaxEpisodeSteps
          , Budget.trainingPlanEpisodeBudgetFloor = Budget.productRlDefaultTrainingEpisodeFloor
          , Budget.trainingPlanVectorEnvironments = Nothing
          , Budget.trainingPlanRequestedTransitionFloor = Just Budget.productRlRequestedStepFloor
          , Budget.trainingPlanExactTransitionTarget = Nothing
          }
        (Budget.EvaluationPlan Budget.productRlDefaultEvaluationEpisodes)
    )

-- Config-only canonical check: no fabricated or executed full training result.
canonicalConfig :: Budget.CompiledRlPlan -> IO Ars.ArsTrainConfig
canonicalConfig plan = case ( Budget.compiledRlSchedule plan
                            , Sim.lookupSimulatedEnvironmentByName (Budget.compiledRlEnvironment plan)
                            ) of
  (Just schedule@Budget.ArsTrainingSchedule {}, Just (Sim.SomeSimulatedEnvironment environment)) ->
    pure
      Ars.defaultArsTrainConfig
        { Ars.arsSeed = Budget.compiledRlSeed plan
        , Ars.arsIterations = Budget.scheduleArsIterations schedule
        , Ars.arsNumDirections = Budget.scheduleArsDirections schedule
        , Ars.arsMaxEpisodeSteps = Budget.scheduleArsMaxEpisodeSteps schedule
        , Ars.arsActionCount = Sim.envActionCount environment
        , Ars.arsObsSize = Sim.envObservationSize environment
        }
  _ ->
    assertFailure "canonical public ARS plan/environment unavailable" >> fail "unreachable assertion"

mapStep
  :: (Ars.ArsAppliedStep -> Ars.ArsAppliedStep)
  -> Ars.ArsIterationObservation
  -> Ars.ArsIterationObservation
mapStep change observation = observation {Ars.arsObservationAppliedStep = change (Ars.arsObservationAppliedStep observation)}

modifyFirstStep
  :: (Ars.ArsAppliedStep -> Ars.ArsAppliedStep) -> Ars.ArsTrainObservation -> Ars.ArsTrainObservation
modifyFirstStep change raw =
  raw
    { Common.rawTrainerStats = case Common.rawTrainerStats raw of
        first : rest -> mapStep change first : rest
        [] -> []
    }

parameterBits :: VU.Vector Double -> [Word64]
parameterBits = fmap castDoubleToWord64 . VU.toList

initialVectorOffset :: BS.ByteString -> IO Int
initialVectorOffset encoded = do
  -- Actual bounded fixture initial state is8 F64 zeroes. The first such exact
  -- byte-string marker is its initial vector, before final state/directions.
  let marker = BS.pack [0x58, 0x40] <> BS.replicate 64 0
      (prefix, suffix) = BS.breakSubstring marker encoded
  assertBool "actual initial F64 vector marker is present" (not (BS.null suffix))
  pure (BS.length prefix)

expectRight :: Either Text a -> IO a
expectRight = either (\reason -> assertFailure (Text.unpack reason) >> fail "unreachable assertion") pure

expectLeft :: Text -> Either Text a -> Assertion
expectLeft fragment result = case result of
  Left reason ->
    assertBool
      ("expected reason " <> Text.unpack fragment <> ", actual " <> Text.unpack reason)
      (fragment `Text.isInfixOf` reason)
  Right _ -> assertFailure ("unexpected acceptance; expected " <> Text.unpack fragment)

knownReference :: Reference.RawArsHostReference
knownReference =
  Reference.RawArsHostReference
    { Reference.rawArsHostReferenceObjectKey =
        "jitml-checkpoints/offline-ars/artifacts/ars-host-execution/" <> Text.replicate 64 "2" <> ".cbor"
    , Reference.rawArsHostReferenceContentSha256 = Text.replicate 64 "2"
    , Reference.rawArsHostReferenceByteLength = 17
    , Reference.rawArsHostReferenceContextSha256 = Text.replicate 64 "3"
    , Reference.rawArsHostReferencePlanId = Text.replicate 64 "1"
    , Reference.rawArsHostReferenceLane = "linux-cpu"
    , Reference.rawArsHostReferenceSourceSha256 = Text.replicate 64 "4"
    , Reference.rawArsHostReferenceExecutableSha256 = Text.replicate 64 "5"
    , Reference.rawArsHostReferenceInvocationSha256 = Text.replicate 64 "6"
    }

fromHex :: Text -> BS.ByteString
fromHex = BS.pack . pairs . Text.unpack
 where
  pairs (a : b : rest) = fromIntegral (digitToInt a * 16 + digitToInt b) : pairs rest
  pairs _ = []

knownReferenceHex :: Text
knownReferenceHex =
  Text.concat
    [ "8b78186a69746d6c2d6172732d686f73742d7265666572656e63650178806a69746d6c2d636865636b706f696e74732f6f66"
    , "666c696e652d6172732f6172746966616374732f6172732d686f73742d657865637574696f6e2f3232323232323232323232"
    , "3232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232"
    , "3232322e63626f72582022222222222222222222222222222222222222222222222222222222222222221158203333333333"
    , "3333333333333333333333333333333333333333333333333333337840313131313131313131313131313131313131313131"
    , "31313131313131313131313131313131313131313131313131313131313131313131313131313131313131696c696e75782d"
    , "6370755820444444444444444444444444444444444444444444444444444444444444444458205555555555555555555555"
    , "5555555555555555555555555555555555555555555820666666666666666666666666666666666666666666666666666666"
    , "6666666666"
    ]
