{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module ArsSingletonProducer (arsSingletonProducerTests) where

import Control.Concurrent (forkIO, newEmptyMVar, putMVar, takeMVar)
import Control.Exception
  ( AsyncException (ThreadKilled)
  , IOException
  , SomeException
  , bracketOnError
  , evaluate
  , throwIO
  , try
  )
import Control.Monad (forM_)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified as BS
import Data.Char (intToDigit)
import Data.Either (isLeft, isRight)
import Data.IORef (newIORef, readIORef, writeIORef)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)
import System.Directory (createDirectoryIfMissing, getTemporaryDirectory, removePathForcibly)
import System.FilePath ((</>))
import System.IO.Temp (createTempDirectory)
import Test.Tasty (TestTree, testGroup, withResource)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Execution.ProducerObservation qualified as Producer
import JitML.Numerics.MlpDevice (MlpDevice (..), pureReferenceMlpDevice)
import JitML.Plan.Plan qualified as Plan
import JitML.Product.ArsHostReference qualified as Reference
import JitML.Product.Evidence qualified as Evidence
import JitML.Product.ExecutionProvenance (ExecutionProvenance (..))
import JitML.Product.SourceDigest qualified as Source
import JitML.RL.Algorithms.ArsTrainer qualified as Ars
import JitML.RL.Algorithms.Common qualified as Common
import JitML.RL.ArsHostTrace qualified as Trace
import JitML.RL.EpisodeEnvelope qualified as Episode
import JitML.RL.ProductBudget qualified as Budget
import JitML.RL.Simulator qualified as Sim
import JitML.RL.TrainerExecution qualified as Execution
import JitML.RL.TrainerObservation qualified as Observation
import JitML.Substrate (Substrate (..), renderSubstrate)
import JitML.Training.Budget qualified as Completion

-- These are actual bounded host-linear executions and supplied-context controls.
-- Lane labels are routing data, never Metal/CUDA/oneDNN execution claims. The
-- temporary source fixture is actually observed but did not build this program.
-- This family makes no convergence, Store, parent-auth or durable barrier claim.
arsSingletonProducerTests :: TestTree
arsSingletonProducerTests =
  withResource acquire release $ \getResource ->
    testGroup
      "actual singleton ARS producer origin"
      ( [ testCase "real public compiled minimum yields an actual host-only lexical origin" $ do
            resource <- getResource
            let input = fixtureInput resource
                compiled = fixtureCompiled resource
            raw <- returned resource
            origin <- actualOrigin resource
            Budget.compiledRlTrainerKind compiled @?= "ars"
            Budget.compiledRlEvaluationEpisodes compiled @?= 1
            -- This is the compiler's noncanonical minimum, not a canonical
            -- 20-episode product execution or a five-training-seed cohort.
            let config = Common.rawTrainerConfig raw
            Ars.arsIterations config @?= 50
            assertBool "actual compiler horizon floor retained" (Ars.arsMaxEpisodeSteps config >= 200)
            Common.observedEnvironmentTransitionCount (Common.rawTrainerCounters raw)
              @?= expectedSteps compiled
            Common.observedOptimizerUpdateCount (Common.rawTrainerCounters raw) @?= 50
            Execution.producedArsHostRunPlan origin @?= Execution.arsBoundInputRunPlan input
            Execution.producedArsHostCompiledPlan origin @?= compiled
            Execution.producedArsHostRowId origin @?= "ARS/mountain-car"
            Execution.producedArsHostSubstrate origin @?= LinuxCPU
            Execution.producedArsHostSuppliedInvocation origin @?= Nothing
        , testCase
            "same-runtime old entrypoint preserves every actual raw bit statistic counter and final episode"
            $ do
              resource <- getResource
              raw <- returned resource
              let independent = fixtureOldRaw resource
              encodeRaw raw @?= encodeRaw independent
              origin <- actualOrigin resource
              let actualEvaluation = evaluations independent (Budget.compiledRlEvaluationEpisodes (fixtureCompiled resource))
              Execution.producedArsHostEvaluation origin @?= actualEvaluation
              Execution.arsProductAttemptEvaluation (fixtureAttempt resource) @?= Just actualEvaluation
        , testCase "complete actual trace matches initial final steps transport and same-runtime replay" $ do
            resource <- getResource
            raw <- returned resource
            origin <- actualOrigin resource
            let trace = Execution.producedArsHostTrace origin
                reference = Execution.producedArsHostReference origin
            Trace.validateArsHostTracePlan (fixtureCompiled resource) trace @?= Right ()
            Trace.validateArsHostTraceLocal trace @?= Right ()
            Trace.validateArsHostTraceReference reference trace @?= Right ()
            encodeRaw (Trace.arsHostTraceObservation trace) @?= encodeRaw raw
            Reference.arsHostReferencePlanId reference
              @?= Plan.runPlanId (Execution.producedArsHostRunPlan origin)
            Reference.arsHostReferenceByteLength reference
              @?= fromIntegral (BS.length (Trace.encodeArsHostTrace trace))
        , testCase "direct context records real source process executable and an OS attempt id" $ do
            resource <- getResource
            origin <- actualOrigin resource
            let before = Execution.producedArsHostBeforeProcess origin
                after = Execution.producedArsHostAfterProcess origin
                context = Trace.arsHostContextToRaw (Trace.arsHostTraceContext (Execution.producedArsHostTrace origin))
                attempt = Execution.producedArsHostAttemptId origin
            stamp <- Source.computeSourceStampIn (fixtureRoot resource) >>= expectRight
            Execution.producedArsHostSourceCoverage origin
              @?= Execution.ObservedArsLocalSource (fixtureRoot resource) stamp
            Producer.producerObservedSource before @?= Just (fixtureRoot resource, stamp)
            Producer.compareProducerProcessObservations before after @?= Right ()
            Trace.rawArsHostSourceSha256 context @?= Source.stampSha256 stamp
            Trace.rawArsHostExecutableSha256 context @?= Producer.producerExecutableFileSha256 before
            Trace.rawArsHostProcessId context @?= Text.pack (show (Producer.producerProcessId before))
            Trace.rawArsHostKernelOS context @?= Producer.producerKernelOperatingSystem before
            Trace.rawArsHostKernelMachine context @?= Producer.producerKernelMachine before
            Trace.rawArsHostKernelRelease context @?= Producer.producerKernelRelease before
            Trace.rawArsHostExecutionBinding context @?= "direct-local-attempt-v1"
            assertBool "actual nonce digest is canonical" (canonicalDigest attempt)
            Trace.rawArsHostAttemptId context @?= attempt
            Trace.rawArsHostInvocationSha256 context @?= expectedDirectDigest origin
            assertBool
              "direct invocation is context bound rather than the nonce itself"
              (Trace.rawArsHostInvocationSha256 context /= attempt)
        , testCase "strict learning or evidence denial never discards actual returned state or origin" $ do
            resource <- getResource
            raw <- returned resource
            _ <- actualOrigin resource
            -- Either actual outcome is valid: never choose a seed or retry to
            -- obtain motion. This verifies exact retention for the observed verdict.
            case Execution.arsProductAttemptStrictResult (fixtureAttempt resource) of
              Left detail -> do
                assertBool "strict denial has its actual detail" (not (Text.null detail))
                Execution.arsProductAttemptFailure (fixtureAttempt resource)
                  @?= Just (Execution.ArsAttemptFailure Execution.ArsStrictRefinement detail)
                encodeRaw raw @?= encodeRaw (fixtureOldRaw resource)
              Right (Execution.EvaluationOnly _) -> assertFailure "actual ARS was reduced to evaluation-only"
              Right (Execution.Trained artifact) -> do
                Execution.arsProductAttemptFailure (fixtureAttempt resource) @?= Nothing
                Checkpoint.encodeJmw1 (Execution.trainedArtifactWeights artifact)
                  @?= Checkpoint.encodeJmw1 (VU.toList (Common.rawTrainerFinalParams raw))
                origin <- actualOrigin resource
                recorded <-
                  expectRight (Evidence.evidenceExecutionProvenance (Execution.trainedArtifactEvidence artifact))
                case recorded of
                  Just (ArsHostLinearExecution reference) -> reference @?= Execution.producedArsHostReference origin
                  _ -> assertFailure "actual strict artifact did not retain its exact host reference"
                Evidence.evidenceDeviceWitness (Execution.trainedArtifactEvidence artifact)
                  @?= Left
                    "training evidence records ARS host linear execution and does not carry a neural device witness"
        , testCase "legacy actual dispatcher remains independent of all neural callbacks" $ do
            resource <- getResource
            attempt <-
              Execution.runRawTrainerObservationForPlan LinuxCPU poisonDevice Nothing (fixtureCompiled resource)
            case attempt of
              Observation.TrainerReturned observed -> do
                case Observation.observedPolicy observed of
                  Observation.ReturnedArs raw -> encodeRaw raw @?= encodeRaw (fixtureOldRaw resource)
                  _ -> assertFailure "legacy ARS dispatch used another trainer"
                Observation.observedEvaluation observed
                  @?= evaluations
                    (fixtureOldRaw resource)
                    (Budget.compiledRlEvaluationEpisodes (fixtureCompiled resource))
              _ -> assertFailure (show attempt)
        , testCase
            "supplied invocation binds actual execution but remains explicitly unauthenticated source data"
            $ do
              resource <- getResource
              process <- Producer.observeProducerProcess Producer.NoSourceObservation >>= expectRight
              let suppliedStamp = Source.SourceStamp Source.sourceDigestAlgorithm (Text.replicate 64 "7")
              -- Deliberately alter all three semantic text fields while retaining
              -- numeric dimensions. The lower origin proves the actual compiled
              -- ARS execution bound to supplied context, never Matrix eligibility.
              run <-
                expectRight
                  ( Plan.validationToEither
                      ( Plan.resolveRun
                          ( (rawRequest (fixtureCompiled resource))
                              { Plan.rawRunSubjectId = "supplied-different-subject"
                              , Plan.rawRunArtifactId = "supplied-different-artifact"
                              , Plan.rawRunTopicId = "supplied-different-topic"
                              }
                          )
                      )
                  )
              invocation <- suppliedInvocation run (Producer.producerExecutableFileSha256 process)
              input <-
                expectRight
                  ( Execution.prepareArsBoundExecutionInput
                      "ARS/mountain-car"
                      run
                      (fixtureCompiled resource)
                      LinuxCPU
                      (Just invocation)
                      (Execution.SuppliedArsParentSource suppliedStamp)
                  )
              attempt <- Execution.runArsProductAttempt input
              origin <- expectJust "actual supplied-context origin" (Execution.arsProductAttemptOrigin attempt)
              raw <- expectJust "actual supplied-context return" (Execution.arsProductAttemptRawReturn attempt)
              Execution.producedArsHostRunPlan origin @?= run
              Plan.runPlanSubjectId (Execution.producedArsHostRunPlan origin) @?= "supplied-different-subject"
              Plan.runPlanArtifactId (Execution.producedArsHostRunPlan origin) @?= "supplied-different-artifact"
              Plan.runPlanTopicId (Execution.producedArsHostRunPlan origin) @?= "supplied-different-topic"
              Execution.producedArsHostCompiledPlan origin @?= fixtureCompiled resource
              Execution.producedArsHostSuppliedInvocation origin @?= Just invocation
              Execution.producedArsHostSourceCoverage origin
                @?= Execution.UnauthenticatedArsSuppliedParentSource suppliedStamp
              Producer.producerObservedSource (Execution.producedArsHostBeforeProcess origin) @?= Nothing
              Producer.producerObservedSource (Execution.producedArsHostAfterProcess origin) @?= Nothing
              let context = Trace.arsHostContextToRaw (Trace.arsHostTraceContext (Execution.producedArsHostTrace origin))
              Trace.rawArsHostInvocationSha256 context @?= Completion.productScenarioInvocationDigest invocation
              Trace.rawArsHostExecutionBinding context @?= "product-scenario-invocation-v1"
              Trace.rawArsHostSourceSha256 context @?= Source.stampSha256 suppliedStamp
              encodeRaw raw @?= encodeRaw (fixtureOldRaw resource)
        , testCase "wrong actual executable claim fails before preparation without invented returned data" $ do
            resource <- getResource
            process <- Producer.observeProducerProcess Producer.NoSourceObservation >>= expectRight
            let actual = Producer.producerExecutableFileSha256 process
                changed = Text.map (\c -> if c == '0' then '1' else '0') actual
                run = Execution.arsBoundInputRunPlan (fixtureInput resource)
            invocation <- suppliedInvocation run changed
            input <-
              expectRight
                ( Execution.prepareArsBoundExecutionInput
                    "ARS/mountain-car"
                    run
                    (fixtureCompiled resource)
                    LinuxCPU
                    (Just invocation)
                    ( Execution.SuppliedArsParentSource
                        (Source.SourceStamp Source.sourceDigestAlgorithm (Text.replicate 64 "7"))
                    )
                )
            attempt <- Execution.runArsProductAttempt input
            absentReturned attempt
            Execution.arsProductAttemptFailure attempt
              @?= Just
                ( Execution.ArsAttemptFailure
                    Execution.ArsSuppliedContext
                    "ARS supplied invocation executable differs from actual process FILE observation"
                )
        , testCase "missing actual source fails before training with no supplied-source fallback" $ do
            resource <- getResource
            let input0 = fixtureInput resource
                missing = fixtureRoot resource </> "absent-source"
            input <-
              expectRight
                ( Execution.prepareArsBoundExecutionInput
                    "ARS/mountain-car"
                    (Execution.arsBoundInputRunPlan input0)
                    (fixtureCompiled resource)
                    LinuxCPU
                    Nothing
                    (Execution.ObserveArsSourceRoot missing)
                )
            attempt <- Execution.runArsProductAttempt input
            absentReturned attempt
            case Execution.arsProductAttemptFailure attempt of
              Just (Execution.ArsAttemptFailure Execution.ArsBeforeProcess detail) ->
                assertBool "actual source diagnostic retained" ("missing code root" `Text.isInfixOf` detail)
              _ -> assertFailure "missing source did not fail at actual before observation"
        , testCase "full input seed lane row and every budget dimension reject specific mismatches" $ do
            resource <- getResource
            let compiled = fixtureCompiled resource
                original = rawRequest compiled
                cases =
                  [ ("singleton seed", original {Plan.rawRunSeeds = [43]})
                  , ("singleton seed", original {Plan.rawRunSeeds = [42, 43]})
                  , ("lane", original {Plan.rawRunSubstrate = LinuxCUDA})
                  , ("transition budget", original {Plan.rawRunBudget = budget compiled 1 0 0 0 0})
                  , ("rollout ticks", original {Plan.rawRunBudget = budget compiled 0 1 0 0 0})
                  , ("vector width", original {Plan.rawRunBudget = budget compiled 0 0 1 0 0})
                  , ("horizon", original {Plan.rawRunBudget = budget compiled 0 0 0 1 0})
                  , ("evaluation count", original {Plan.rawRunBudget = budget compiled 0 0 0 0 1})
                  ]
            forM_ cases $ \(reason, request) -> do
              run <- expectRight (Plan.validationToEither (Plan.resolveRun request))
              expectInputLeft reason (prepare resource run compiled LinuxCPU Nothing)
            expectInputLeft
              "row differs"
              ( Execution.prepareArsBoundExecutionInput
                  "ARS/cartpole"
                  (Execution.arsBoundInputRunPlan (fixtureInput resource))
                  compiled
                  LinuxCPU
                  Nothing
                  (Execution.ObserveArsSourceRoot (fixtureRoot resource))
              )
        , testCase "public compiler reparse trainer schedule and resource checks precede execution" $ do
            resource <- getResource
            let compiled = fixtureCompiled resource
                run = Execution.arsBoundInputRunPlan (fixtureInput resource)
            forM_ [compiled {Budget.compiledRlSchedule = Nothing}] $ \changed ->
              expectInputLeft "public compiler projection" (prepare resource run changed LinuxCPU Nothing)
            expectInputLeft
              "evaluation count"
              ( prepare
                  resource
                  run
                  (compiled {Budget.compiledRlEvaluation = Budget.EvaluationPlan 2})
                  LinuxCPU
                  Nothing
              )
            let tooMany = compiled {Budget.compiledRlEvaluation = Budget.EvaluationPlan 21}
            tooManyRun <- expectRight (Plan.validationToEither (Plan.resolveRun (rawRequest tooMany)))
            expectInputLeft "1..20 resource scope" (prepare resource tooManyRun tooMany LinuxCPU Nothing)
            wrongTrainer <- compiledPlan "dqn" "mountain-car"
            expectInputLeft "trainer is not ARS" (prepare resource run wrongTrainer LinuxCPU Nothing)
            let schedule = Budget.compiledRlSchedule compiled
            case schedule of
              Just value@Budget.ArsTrainingSchedule {} -> do
                let oversized = compiled {Budget.compiledRlSchedule = Just value {Budget.scheduleArsIterations = maxBound}}
                expectInputLeft "public compiler projection" (prepare resource run oversized LinuxCPU Nothing)
              _ -> assertFailure "actual public compiler did not return ARS schedule"
        , testCase "supplied context rejects auxiliary plan aliases row lane source and namespace escapes" $ do
            resource <- getResource
            let run = Execution.arsBoundInputRunPlan (fixtureInput resource)
                compiled = fixtureCompiled resource
                source =
                  Execution.SuppliedArsParentSource
                    (Source.SourceStamp Source.sourceDigestAlgorithm (Text.replicate 64 "7"))
            invocation <- suppliedInvocation run (Text.replicate 64 "4")
            changedRun <-
              expectRight
                ( Plan.validationToEither
                    ( Plan.resolveRun
                        ((rawRequest compiled) {Plan.rawRunExperimentId = "offline-ars.native-rl-qualification-v1.1"})
                    )
                )
            expectInputLeft
              "auxiliary child association is unsupported"
              ( Execution.prepareArsBoundExecutionInput
                  "ARS/mountain-car"
                  changedRun
                  compiled
                  LinuxCPU
                  (Just invocation)
                  source
              )
            wrongRow <-
              expectRight
                ( Completion.mkProductScenarioInvocation
                    "offline-singleton-context"
                    "ARS/cartpole"
                    (Plan.runPlanId run)
                    LinuxCPU
                    (Text.replicate 64 "2")
                    (Text.replicate 64 "4")
                    (Text.replicate 64 "3")
                )
            expectInputLeft "invocation row differs" (prepare resource run compiled LinuxCPU (Just wrongRow))
            wrongLane <-
              expectRight
                ( Completion.mkProductScenarioInvocation
                    "offline-singleton-context"
                    "ARS/mountain-car"
                    (Plan.runPlanId run)
                    LinuxCUDA
                    (Text.replicate 64 "2")
                    (Text.replicate 64 "4")
                    (Text.replicate 64 "3")
                )
            expectInputLeft "invocation lane differs" (prepare resource run compiled LinuxCPU (Just wrongLane))
            expectInputLeft
              "requires a supplied scenario invocation"
              (Execution.prepareArsBoundExecutionInput "ARS/mountain-car" run compiled LinuxCPU Nothing source)
            forM_ [Source.SourceStamp 2 (Text.replicate 64 "7"), Source.SourceStamp 1 "bad"] $ \stamp ->
              expectInputLeft
                "supplied source"
                ( Execution.prepareArsBoundExecutionInput
                    "ARS/mountain-car"
                    run
                    compiled
                    LinuxCPU
                    (Just invocation)
                    (Execution.SuppliedArsParentSource stamp)
                )
            escaped <-
              expectRight
                ( Plan.validationToEither
                    (Plan.resolveRun ((rawRequest compiled) {Plan.rawRunExperimentId = "offline-ars/aux"}))
                )
            expectInputLeft
              "experiment namespace is not canonical"
              (prepare resource escaped compiled LinuxCPU Nothing)
        , testCase
            "old zero-counter strict boundary still fails before an evaluator and raw data remains available"
            $ do
              resource <- getResource
              let config = (Common.rawTrainerConfig (fixtureOldRaw resource)) {Ars.arsIterations = 0}
              raw <- Ars.trainArsOnEnvironmentRaw environment config
              calls <- newIORef False
              result <-
                try
                  ( Execution.evaluateStrictTrainerReturn
                      (Observation.ReturnedArs raw)
                      (writeIORef calls True >> pure (Right ()))
                  )
                  :: IO (Either IOException (Either Text ()))
              case result of
                Left detail ->
                  assertBool
                    "real positive-counter diagnostic"
                    ("must be positive" `Text.isInfixOf` Text.pack (show detail))
                Right _ -> assertFailure "old ARS zero-counter boundary unexpectedly passed"
              readIORef calls >>= (@?= False)
              Common.observedOptimizerUpdateCount (Common.rawTrainerCounters raw) @?= 0
              VU.length (Common.rawTrainerInitialParams raw) @?= VU.length (Common.rawTrainerFinalParams raw)
        , testCase
            "recorded trace refinement cannot mint an execution and changed tuples fail exact validation"
            $ do
              resource <- getResource
              origin <- actualOrigin resource
              let original = Execution.producedArsHostTrace origin
              recorded <- expectRight (Trace.decodeArsHostTrace (Trace.encodeArsHostTrace original))
              Trace.encodeArsHostTrace recorded @?= Trace.encodeArsHostTrace original
              let referenceRaw = Reference.arsHostReferenceToRaw (Execution.producedArsHostReference origin)
              changed <-
                expectRight
                  ( Reference.refineArsHostReference
                      referenceRaw {Reference.rawArsHostReferenceInvocationSha256 = Text.replicate 64 "8"}
                  )
              expectTextLeft "reference invocation differs" (Trace.validateArsHostTraceReference changed recorded)
              -- No function accepts recorded/decoded data as ProducedArsHostExecution;
              -- external constructor/record/Read/coerce probes are supplied separately.
        ]
          <> stagedArsProducerControls getResource
      )

data Fixture
  = Fixture
      FilePath
      Budget.CompiledRlPlan
      Execution.ArsBoundExecutionInput
      Execution.ArsProductAttempt
      Ars.ArsTrainObservation
fixtureRoot :: Fixture -> FilePath
fixtureRoot (Fixture root _ _ _ _) = root
fixtureCompiled :: Fixture -> Budget.CompiledRlPlan
fixtureCompiled (Fixture _ compiled _ _ _) = compiled
fixtureInput :: Fixture -> Execution.ArsBoundExecutionInput
fixtureInput (Fixture _ _ input _ _) = input
fixtureAttempt :: Fixture -> Execution.ArsProductAttempt
fixtureAttempt (Fixture _ _ _ attempt _) = attempt
fixtureOldRaw :: Fixture -> Ars.ArsTrainObservation
fixtureOldRaw (Fixture _ _ _ _ raw) = raw

acquire :: IO Fixture
acquire = do
  tmp <- getTemporaryDirectory
  bracketOnError (createTempDirectory tmp "jitml-ars-singleton-") removePathForcibly $ \root -> do
    forM_ Source.sourceDigestDirectoryRoots (createDirectoryIfMissing True . (root </>))
    forM_
      Source.sourceDigestFileRoots
      (\path -> BS.writeFile (root </> path) "actual observer fixture\n")
    compiled <- compiledPlan "ars" "mountain-car"
    run <- expectRight (Plan.validationToEither (Plan.resolveRun (rawRequest compiled)))
    input <-
      expectRight
        ( Execution.prepareArsBoundExecutionInput
            "ARS/mountain-car"
            run
            compiled
            LinuxCPU
            Nothing
            (Execution.ObserveArsSourceRoot root)
        )
    attempt <- Execution.runArsProductAttempt input
    raw <- expectJust "actual returned ARS result" (Execution.arsProductAttemptRawReturn attempt)
    _ <- expectJust "actual observed ARS origin" (Execution.arsProductAttemptOrigin attempt)
    old <- Ars.trainArsOnEnvironmentRaw environment (Common.rawTrainerConfig raw)
    pure (Fixture root compiled input attempt old)

release :: Fixture -> IO ()
release = removePathForcibly . fixtureRoot

returned :: Fixture -> IO Ars.ArsTrainObservation
returned = expectJust "actual lexical raw return" . Execution.arsProductAttemptRawReturn . fixtureAttempt
actualOrigin :: Fixture -> IO Execution.ProducedArsHostExecution
actualOrigin = expectJust "actual lexical origin" . Execution.arsProductAttemptOrigin . fixtureAttempt

environment :: Sim.SomeSimulatedEnvironment
environment = case Sim.lookupSimulatedEnvironmentByName "mountain-car" of
  Just value -> value
  Nothing -> error "actual production mountain-car environment is absent"

compiledPlan :: Text -> Text -> IO Budget.CompiledRlPlan
compiledPlan trainer env =
  expectRight
    ( Budget.compileRlPlan
        (Budget.TrainingPlan trainer env 42 1 1 (Just 1) Nothing Nothing)
        (Budget.EvaluationPlan 1)
    )

rawRequest :: Budget.CompiledRlPlan -> Plan.RawRunRequest 'Plan.ReinforcementLearning
rawRequest compiled =
  Plan.RawRunRequest
    1
    Plan.ReinforcementLearningWitness
    "offline-ars"
    "rl:ARS/mountain-car"
    "actual-singleton-control"
    "offline-topic"
    LinuxCPU
    Plan.InProcessRun
    [42]
    (budget compiled 0 0 0 0 0)

budget
  :: Budget.CompiledRlPlan
  -> Integer
  -> Integer
  -> Integer
  -> Integer
  -> Integer
  -> Plan.RawRunBudget 'Plan.ReinforcementLearning
budget compiled dTransitions dTicks dVectors dHorizon dEvaluations =
  Plan.RawRlBudget
    (toInteger (expectedSteps compiled) + dTransitions)
    (toInteger (arsHorizon compiled) + dTicks)
    (1 + dVectors)
    (toInteger (arsHorizon compiled) + dHorizon)
    (toInteger (Budget.compiledRlEvaluationEpisodes compiled) + dEvaluations)

arsHorizon :: Budget.CompiledRlPlan -> Int
arsHorizon compiled = case Budget.compiledRlSchedule compiled of
  Just schedule@Budget.ArsTrainingSchedule {} -> Budget.scheduleArsMaxEpisodeSteps schedule
  _ -> error "actual public compiler ARS schedule absent"

expectedSteps :: Budget.CompiledRlPlan -> Word64
expectedSteps compiled = case Budget.compiledRlSchedule compiled of
  Just schedule -> Budget.scheduleObservedEnvironmentSteps schedule
  Nothing -> error "actual public compiler schedule absent"

prepare
  :: Fixture
  -> Plan.RunPlan 'Plan.ReinforcementLearning
  -> Budget.CompiledRlPlan
  -> Substrate
  -> Maybe Completion.ProductScenarioInvocation
  -> Either Text Execution.ArsBoundExecutionInput
prepare resource run compiled lane invocation =
  Execution.prepareArsBoundExecutionInput
    "ARS/mountain-car"
    run
    compiled
    lane
    invocation
    (Execution.ObserveArsSourceRoot (fixtureRoot resource))

suppliedInvocation
  :: Plan.RunPlan 'Plan.ReinforcementLearning -> Text -> IO Completion.ProductScenarioInvocation
suppliedInvocation run exe =
  expectRight
    ( Completion.mkProductScenarioInvocation
        "offline-singleton-context"
        "ARS/mountain-car"
        (Plan.runPlanId run)
        LinuxCPU
        (Text.replicate 64 "2")
        exe
        (Text.replicate 64 "3")
    )

encodeRaw :: Ars.ArsTrainObservation -> Text
encodeRaw raw =
  Text.pack
    ( show
        ( Checkpoint.encodeJmw1 (VU.toList (Common.rawTrainerInitialParams raw))
        , Checkpoint.encodeJmw1 (VU.toList (Common.rawTrainerFinalParams raw))
        , fmap
            ( \observation ->
                ( statBits (Ars.arsObservationStatistic observation)
                , appliedBits (Ars.arsObservationAppliedStep observation)
                )
            )
            (Common.rawTrainerStats raw)
        , Common.rawTrainerCounters raw
        , Common.rawTrainerConfig raw
        )
    )
 where
  statBits stat =
    ( Ars.arsIterIndex stat
    , Checkpoint.encodeJmw1 [Ars.arsIterMeanReturn stat, Ars.arsIterBestReturn stat]
    )
  appliedBits step =
    ( Checkpoint.encodeJmw1 (VU.toList (Ars.arsStepThetaBefore step))
    , Checkpoint.encodeJmw1 (VU.toList (Ars.arsStepThetaAfter step))
    , fmap (Checkpoint.encodeJmw1 . VU.toList) (Ars.arsStepSampledDirections step)
    , Checkpoint.encodeJmw1
        ( concatMap
            ( \((plus, psteps), (minus, msteps), delta) -> [plus, fromIntegral psteps, minus, fromIntegral msteps] <> delta
            )
            (Ars.arsStepEvaluatedPerturbations step)
        )
    , Checkpoint.encodeJmw1
        (concatMap (\(plus, minus, delta) -> [plus, minus] <> delta) (Ars.arsStepKeptDirections step))
    , Checkpoint.encodeJmw1
        ( [Ars.arsStepNoiseStd step, Ars.arsStepReturnStdDev step, Ars.arsStepScale step]
            <> Ars.arsStepUpdateDirection step
        )
    , Ars.arsStepIndex step
    , Ars.arsStepObservedTransitions step
    , Ars.arsStepConfig step
    , Ars.arsStepNumericalRuntime step
    )

evaluations :: Ars.ArsTrainObservation -> Int -> Observation.RawEvaluation
evaluations raw count =
  Observation.EvaluationReturned
    [ Episode.SimulatedEpisode
        index
        (Common.evaluationEpisodeSteps value)
        (Common.evaluationEpisodeReward value)
        (Common.evaluationEpisodeTerminated value)
        []
    | (index, value) <-
        zip
          [0 ..]
          ( Ars.evaluateArsPolicyWithEnvironment
              environment
              (Common.rawTrainerConfig raw)
              (Common.rawTrainerFinalParams raw)
              count
          )
    ]

poisonDevice :: MlpDevice
poisonDevice =
  pureReferenceMlpDevice
    { mlpdForward = \_ _ -> fail "ARS unexpectedly called MLP forward"
    , mlpdBackward = \_ _ _ -> fail "ARS unexpectedly called MLP backward"
    , mlpdForwardBatch = \_ _ -> fail "ARS unexpectedly called MLP batch forward"
    , mlpdBatchGradient = \_ _ -> fail "ARS unexpectedly called MLP gradient"
    , mlpdInputGradientBatch = \_ _ -> fail "ARS unexpectedly called MLP input gradient"
    , mlpdExecutionWitness = fail "ARS unexpectedly queried a neural witness"
    }

absentReturned :: Execution.ArsProductAttempt -> Assertion
absentReturned attempt = do
  case Execution.arsProductAttemptRawReturn attempt of
    Nothing -> pure ()
    Just _ -> assertFailure "invented raw return"
  Execution.arsProductAttemptEvaluation attempt @?= Nothing
  case Execution.arsProductAttemptOrigin attempt of
    Nothing -> pure ()
    Just _ -> assertFailure "invented actual origin"

canonicalDigest :: Text -> Bool
canonicalDigest value = Text.length value == 64 && Text.all (`elem` ("0123456789abcdef" :: String)) value
expectJust :: String -> Maybe value -> IO value
expectJust label = maybe (assertFailure label) pure
expectRight :: (Show err) => Either err value -> IO value
expectRight = either (assertFailure . show) pure
expectInputLeft :: Text -> Either Text value -> Assertion
expectInputLeft fragment result = case result of
  Left detail -> assertBool (Text.unpack detail) (fragment `Text.isInfixOf` detail)
  Right _ -> assertFailure "unexpected accepted ARS input"
expectTextLeft :: (Show value) => Text -> Either Text value -> Assertion
expectTextLeft = expectInputLeft

-- Actual closed stages only. These tests cannot inject an initializer,
-- trainer/evaluator callback or raw-to-capability constructor.
stagedArsProducerControls :: IO Fixture -> [TestTree]
stagedArsProducerControls getResource =
  [ testCase "begin exposes actual reserved context before the one actual preparation" $ do
      resource <- getResource
      begun <- Execution.beginArsProductAttempt (fixtureInput resource) >>= expectRight
      Execution.begunArsInput begun `sameInput` fixtureInput resource
      assertBool
        "actual attempt id is present before initializer"
        (canonicalDigest (Execution.begunArsAttemptId begun))
      stamp <- Source.computeSourceStampIn (fixtureRoot resource) >>= expectRight
      Execution.begunArsSourceCoverage begun
        @?= Execution.ObservedArsLocalSource (fixtureRoot resource) stamp
      Producer.producerObservedSource (Execution.begunArsBeforeProcess begun)
        @?= Just (fixtureRoot resource, stamp)
      prepared <- Execution.prepareBegunArsProductAttempt begun >>= expectRight
      let snapshot = Execution.preparedArsProductSnapshot prepared
      Execution.preparedArsProductInput prepared `sameInput` fixtureInput resource
      Execution.preparedArsProductAttemptId prepared @?= Execution.begunArsAttemptId begun
      Ars.arsPreparedConfig snapshot @?= Common.rawTrainerConfig (fixtureOldRaw resource)
      Checkpoint.encodeJmw1 (VU.toList (Ars.arsPreparedInitialParams snapshot))
        @?= Checkpoint.encodeJmw1 (VU.toList (Common.rawTrainerInitialParams (fixtureOldRaw resource)))
      -- Force actual captured snapshot as a coordinator would before its own
      -- durable write; this test itself does not claim such a write occurred.
      _ <-
        evaluate
          ( length
              ( show
                  ( Ars.arsPreparedConfig snapshot
                  , VU.toList (Ars.arsPreparedInitialParams snapshot)
                  , show (Ars.arsPreparedGenerator snapshot)
                  , VU.toList (Ars.arsPreparedInitialFrame snapshot)
                  )
              )
          )
      pure ()
  , testCase "concurrent preparation claims permit exactly one actual prepared capability" $ do
      resource <- getResource
      begun <- Execution.beginArsProductAttempt (fixtureInput resource) >>= expectRight
      (a, b) <- raceTwo (Execution.prepareBegunArsProductAttempt begun)
      length (filter isRight [a, b]) @?= 1
      length (filter isLeft [a, b]) @?= 1
      forM_ [a, b] $ \case
        Left failure ->
          failure
            @?= Execution.ArsAttemptFailure Execution.ArsPreparation "ARS begun preparation was already consumed"
        Right prepared -> Execution.preparedArsProductAttemptId prepared @?= Execution.begunArsAttemptId begun
  , testCase "actual raw return is inspectable before finish and finish consumes exactly once" $ do
      resource <- getResource
      prepared <- freshPrepared resource
      pending <- Execution.runPreparedArsProductAttempt prepared >>= expectRight
      raw <- expectJust "actual raw is available before finish" (Execution.pendingArsRawReturn pending)
      Execution.pendingArsReturnFailure pending @?= Nothing
      encodeRaw raw @?= encodeRaw (fixtureOldRaw resource)
      let snapshot = Execution.pendingArsPreparedSnapshot pending
      Checkpoint.encodeJmw1 (VU.toList (Common.rawTrainerInitialParams raw))
        @?= Checkpoint.encodeJmw1 (VU.toList (Ars.arsPreparedInitialParams snapshot))
      final <- Execution.finishArsProductAttempt pending >>= expectRight
      origin <- expectJust "actual finish origin" (Execution.arsProductAttemptOrigin final)
      Execution.producedArsHostAttemptId origin @?= Execution.pendingArsProductAttemptId pending
      Execution.arsProductAttemptEvaluation final @?= Just (evaluations raw 1)
      kept <-
        expectJust
          "final attempt retains actual prepared snapshot"
          (Execution.arsProductAttemptPreparedSnapshot final)
      Checkpoint.encodeJmw1 (VU.toList (Ars.arsPreparedInitialParams kept))
        @?= Checkpoint.encodeJmw1 (VU.toList (Common.rawTrainerInitialParams raw))
      case Execution.arsProductAttemptStrictResult final of
        Left detail ->
          Execution.arsProductAttemptFailure final
            @?= Just (Execution.ArsAttemptFailure Execution.ArsStrictRefinement detail)
        Right _ -> pure ()
      Execution.finishArsProductAttempt pending
        >>= expectStageLeft Execution.ArsEvaluation "ARS pending finish was already consumed"
      -- Consuming finish never destroys the immutable raw observation.
      keptRaw <- expectJust "raw remains inspectable after finish" (Execution.pendingArsRawReturn pending)
      encodeRaw keptRaw @?= encodeRaw raw
  , testCase "concurrent run claims execute one numerical return with its exact prepared initial state" $ do
      resource <- getResource
      prepared <- freshPrepared resource
      (a, b) <- raceTwo (Execution.runPreparedArsProductAttempt prepared)
      length (filter isRight [a, b]) @?= 1
      length (filter isLeft [a, b]) @?= 1
      forM_ [a, b] $ \case
        Left failure ->
          failure
            @?= Execution.ArsAttemptFailure Execution.ArsTraining "ARS prepared run was already consumed"
        Right pending -> do
          raw <- expectJust "one actual completed raw return" (Execution.pendingArsRawReturn pending)
          encodeRaw raw @?= encodeRaw (fixtureOldRaw resource)
          Execution.pendingArsProductAttemptId pending @?= Execution.preparedArsProductAttemptId prepared
          Common.observedEnvironmentTransitionCount (Common.rawTrainerCounters raw)
            @?= expectedSteps (fixtureCompiled resource)
  , testCase "concurrent finish claims yield one actual evaluation and origin result" $ do
      resource <- getResource
      prepared <- freshPrepared resource
      pending <- Execution.runPreparedArsProductAttempt prepared >>= expectRight
      (a, b) <- raceTwo (Execution.finishArsProductAttempt pending)
      length (filter isRight [a, b]) @?= 1
      length (filter isLeft [a, b]) @?= 1
      forM_ [a, b] $ \case
        Left failure ->
          failure
            @?= Execution.ArsAttemptFailure Execution.ArsEvaluation "ARS pending finish was already consumed"
        Right final -> do
          origin <- expectJust "winning actual finish origin" (Execution.arsProductAttemptOrigin final)
          Execution.producedArsHostAttemptId origin @?= Execution.pendingArsProductAttemptId pending
          raw <- expectJust "winning actual raw" (Execution.arsProductAttemptRawReturn final)
          Execution.producedArsHostEvaluation origin @?= evaluations raw 1
  , testCase
      "explicit stage composition preserves actual raw evaluation and prepared data of convenience path"
      $ do
        resource <- getResource
        prepared <- freshPrepared resource
        pending <- Execution.runPreparedArsProductAttempt prepared >>= expectRight
        final <- Execution.finishArsProductAttempt pending >>= expectRight
        raw <- expectJust "staged actual return" (Execution.arsProductAttemptRawReturn final)
        encodeRaw raw @?= encodeRaw (fixtureOldRaw resource)
        Execution.arsProductAttemptEvaluation final
          @?= Execution.arsProductAttemptEvaluation (fixtureAttempt resource)
        origin <- expectJust "actual staged origin" (Execution.arsProductAttemptOrigin final)
        let snapshot = Execution.producedArsHostPreparedSnapshot origin
        Checkpoint.encodeJmw1 (VU.toList (Ars.arsPreparedInitialParams snapshot))
          @?= Checkpoint.encodeJmw1 (VU.toList (Common.rawTrainerInitialParams raw))
        Execution.producedArsHostRunPlan origin @?= Execution.arsBoundInputRunPlan (fixtureInput resource)
  , -- Fresh OS nonce/context are intentionally different actual attempts;
    -- they are not normalized away or compared as source/build proof.
    testCase "closed stage catcher observes lazy outer Left text and synchronous IO at the actual stage" $ do
      let boundary = Execution.observeArsStageFailureBoundary Execution.ArsRawReturnForcing
      forM_
        [ ("lazy outer sentinel", pure (error "lazy outer sentinel"))
        , ("lazy Left sentinel", pure (Left (error "lazy Left sentinel")))
        , ("sync IO sentinel", throwIO (userError "sync IO sentinel"))
        ]
        $ \(fragment, action) -> do
          result <- boundary action
          case result of
            Left (Execution.ArsAttemptFailure stage detail) -> do
              stage @?= Execution.ArsRawReturnForcing
              assertBool (Text.unpack detail) (fragment `Text.isInfixOf` detail)
            Right () -> assertFailure "actual closed catcher missed its promised force/IO boundary"
      boundary (pure (Left "actual explicit Left"))
        >>= expectStageLeft Execution.ArsRawReturnForcing "actual explicit Left"
      boundary (pure (Right ())) >>= (@?= Right ())
  , testCase "closed stage catcher preserves asynchronous cancellation without forging a failed result" $ do
      result <-
        try (Execution.observeArsStageFailureBoundary Execution.ArsTraining (throwIO ThreadKilled))
          :: IO (Either AsyncException (Either Execution.ArsAttemptFailure ()))
      case result of
        Left ThreadKilled -> pure ()
        _ -> assertFailure "async cancellation was converted into stage data"
  ]

freshPrepared :: Fixture -> IO Execution.PreparedArsProductAttempt
freshPrepared resource = do
  begun <- Execution.beginArsProductAttempt (fixtureInput resource) >>= expectRight
  Execution.prepareBegunArsProductAttempt begun >>= expectRight

sameInput :: Execution.ArsBoundExecutionInput -> Execution.ArsBoundExecutionInput -> Assertion
sameInput actual expected = do
  Execution.arsBoundInputRunPlan actual @?= Execution.arsBoundInputRunPlan expected
  Execution.arsBoundInputCompiledPlan actual @?= Execution.arsBoundInputCompiledPlan expected
  Execution.arsBoundInputRowId actual @?= Execution.arsBoundInputRowId expected
  Execution.arsBoundInputSubstrate actual @?= Execution.arsBoundInputSubstrate expected
  Execution.arsBoundInputSuppliedInvocation actual
    @?= Execution.arsBoundInputSuppliedInvocation expected
  Execution.arsBoundInputSourceInput actual @?= Execution.arsBoundInputSourceInput expected

tryAnyForControl :: IO value -> IO (Either SomeException value)
tryAnyForControl = try

raceTwo :: IO value -> IO (value, value)
raceTwo action = do
  output <- newEmptyMVar
  let worker = tryAnyForControl action >>= putMVar output
  _ <- forkIO worker
  _ <- forkIO worker
  a <- takeMVar output >>= expectRight
  b <- takeMVar output >>= expectRight
  pure (a, b)

expectStageLeft
  :: Execution.ArsAttemptStage -> Text -> Either Execution.ArsAttemptFailure value -> Assertion
expectStageLeft stage expected result = case result of
  Left failure -> failure @?= Execution.ArsAttemptFailure stage expected
  Right _ -> assertFailure "unexpected successful second stage claim"

-- Independent wire-digest expectation over observed/supplied DATA only. This
-- does not create a producer origin, invocation receipt or durable barrier.
expectedDirectDigest :: Execution.ProducedArsHostExecution -> Text
expectedDirectDigest origin =
  contextDigest
    [ "jitml-ars-direct-invocation-context-v1"
    , Execution.producedArsHostAttemptId origin
    , Plan.planIdText (Plan.runPlanId (Execution.producedArsHostRunPlan origin))
    , Budget.renderCompiledRlPlanTransport (Execution.producedArsHostCompiledPlan origin)
    , Execution.producedArsHostRowId origin
    , renderSubstrate (Execution.producedArsHostSubstrate origin)
    , Text.pack (show (Source.stampAlgorithm stamp))
    , Source.stampSha256 stamp
    , Producer.producerExecutableFileSha256 (Execution.producedArsHostBeforeProcess origin)
    ]
 where
  stamp = case Execution.producedArsHostSourceCoverage origin of
    Execution.ObservedArsLocalSource _ value -> value
    Execution.UnauthenticatedArsSuppliedParentSource value -> value

contextDigest :: [Text] -> Text
contextDigest fields =
  Text.pack
    ( concatMap
        hexByte
        ( BS.unpack
            ( SHA256.hash
                ( TextEncoding.encodeUtf8
                    (Text.concat [Text.pack (show (Text.length value)) <> ":" <> value | value <- fields])
                )
            )
        )
    )
 where
  hexByte byte = [intToDigit (fromIntegral byte `div` 16), intToDigit (fromIntegral byte `mod` 16)]
