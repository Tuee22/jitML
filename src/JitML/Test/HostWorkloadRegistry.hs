{-# LANGUAGE OverloadedStrings #-}

module JitML.Test.HostWorkloadRegistry
  ( hostWorkloadRegistryTests
  )
where

import Control.Concurrent
  ( MVar
  , newEmptyMVar
  , putMVar
  , takeMVar
  , threadDelay
  )
import Control.Concurrent.Async (AsyncCancelled, async, wait)
import Control.Exception (finally, throwIO, try)
import Control.Monad (forM)
import Data.Either (lefts)
import Data.Foldable (traverse_)
import Data.IORef
  ( IORef
  , atomicModifyIORef'
  , newIORef
  , readIORef
  , writeIORef
  )
import Data.List qualified as List
import Data.Text qualified as Text
import System.Timeout qualified as Timeout
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit
  ( assertBool
  , assertFailure
  , testCase
  , (@?=)
  )

import JitML.App (waitForConsumeOnceHostWorkloads)
import JitML.AppError.AppError (AppError (..))
import JitML.Plan.Plan (EventId, validationToEither)
import JitML.Proto.Inference qualified as Inference
import JitML.Proto.Rl qualified as Rl
import JitML.Proto.Training qualified as Training
import JitML.Proto.Tune qualified as Tune
import JitML.Service.Consumer (DaemonCommand (..), daemonCommandEventId)
import JitML.Service.HostWorkloadRegistry
  ( HostWorkloadDrainReport (..)
  , HostWorkloadFamily (..)
  , HostWorkloadKey
  , HostWorkloadOutcome (..)
  , HostWorkloadRegistry
  , HostWorkloadRegistryError (..)
  , HostWorkloadSnapshot (..)
  , activeHostWorkloadCount
  , beginHostWorkloadStop
  , completeHostWorkloadDrain
  , completeHostWorkloadStop
  , drainHostWorkload
  , drainHostWorkloadForEvent
  , drainHostWorkloadRegistry
  , hostWorkloadExperimentHash
  , hostWorkloadFamily
  , joinedHostWorkloadOutcome
  , lookupHostWorkload
  , newHostWorkloadRegistry
  , refineHostWorkloadKey
  , startHostWorkload
  , stopHostWorkload
  , stopHostWorkloadForEvent
  , waitHostWorkload
  )
import JitML.Service.Retry (ServiceError (..))
import JitML.Service.Runtime qualified as Runtime
import JitML.Substrate (Substrate (..))

hostWorkloadRegistryTests :: TestTree
hostWorkloadRegistryTests =
  testGroup
    "HostWorkloadRegistry"
    [ testCase "keys reject empty and whitespace-aliased experiment hashes" $ do
        refineHostWorkloadKey TrainingWorkload ""
          @?= Left (InvalidHostWorkloadExperimentHash TrainingWorkload "")
        refineHostWorkloadKey TuneWorkload " hash "
          @?= Left (InvalidHostWorkloadExperimentHash TuneWorkload " hash ")
        let trainingKey = key TrainingWorkload "same-hash"
            rlKey = key RlWorkload "same-hash"
        assertBool "family is part of the key" (trainingKey /= rlKey)
        hostWorkloadFamily trainingKey @?= TrainingWorkload
        hostWorkloadExperimentHash trainingKey @?= "same-hash"
    , testCase "Runtime preserves Training/RL drain intent and makes Tune Stops cancel" $ do
        let cases =
              [
                ( TrainingDaemonCommand
                    AppleSilicon
                    (Training.TrainingStop (Training.StopTraining "stop-training" True))
                , Runtime.DrainAppleHostWorkload
                , key TrainingWorkload "stop-training"
                )
              ,
                ( TrainingDaemonCommand
                    AppleSilicon
                    (Training.TrainingStop (Training.StopTraining "cancel-training" False))
                , Runtime.CancelAppleHostWorkload
                , key TrainingWorkload "cancel-training"
                )
              ,
                ( TuneDaemonCommand
                    AppleSilicon
                    (Tune.TuneStop (Tune.StopSweep "stop-tune"))
                , Runtime.CancelAppleHostWorkload
                , key TuneWorkload "stop-tune"
                )
              ,
                ( RlDaemonCommand
                    AppleSilicon
                    (Rl.RlStop (Rl.StopRLRun "drain-rl" True))
                , Runtime.DrainAppleHostWorkload
                , key RlWorkload "drain-rl"
                )
              ,
                ( RlDaemonCommand
                    AppleSilicon
                    (Rl.RlStop (Rl.StopRLRun "cancel-rl" False))
                , Runtime.CancelAppleHostWorkload
                , key RlWorkload "cancel-rl"
                )
              ]
        traverse_
          ( \(command, expectedMode, expectedKey) -> do
              let action = expectRight "planned host Stop" (Runtime.planAppleHostWorkloadAction command)
              case action of
                Runtime.StopAppleHostWorkload observedMode observedKey -> do
                  observedMode @?= expectedMode
                  observedKey @?= expectedKey
                other ->
                  assertFailure ("expected a planned host Stop, got " <> show other)
              Runtime.appleHostWorkloadActionKey action @?= Right (Just expectedKey)
          )
          cases
        Runtime.planAppleHostWorkloadAction
          (TrainingDaemonCommand AppleSilicon (Training.TrainingStop (Training.StopTraining " " True)))
          @?= Left
            ( SEConflict
                "host Apple workload key refinement failed: invalid training host workload experiment hash: \" \""
            )
    , testCase "AlphaZero starts use the RL cancellation family" $ do
        let alphaZeroCommandStart =
              Rl.StartAlphaZeroRun
                { Rl.sazSubstrate = AppleSilicon
                , Rl.sazExperimentHash = "alpha-zero-key"
                , Rl.sazPlanId = "plan"
                , Rl.sazResolvedPlan = "resolved"
                , Rl.sazGame = "hex"
                , Rl.sazGenerations = 1
                , Rl.sazSelfPlayGames = 1
                , Rl.sazMctsSimulationsPerMove = 1
                , Rl.sazMaxPlies = 1
                , Rl.sazOptimizerUpdates = 1
                , Rl.sazArenaGames = 1
                , Rl.sazSeed = 1
                }
            action =
              expectRight
                "planned AlphaZero Start"
                ( Runtime.planAppleHostWorkloadAction
                    (RlDaemonCommand AppleSilicon (Rl.RlStartAlphaZero alphaZeroCommandStart))
                )
        Runtime.appleHostWorkloadActionKey action
          @?= Right (Just (key RlWorkload "alpha-zero-key"))
    , testCase "Runtime production Start registers and runs every host workload family" $ do
        traverse_
          ( \(label, family, experimentHash, action) -> do
              registry <- newHostWorkloadRegistry
              ran <- newIORef False
              Runtime.executeAppleHostWorkloadStart
                (Just registry)
                action
                (writeIORef ran True)
                >>= (@?= Right ())
              let workloadKey = key family experimentHash
              within
                ("Runtime " <> Text.unpack label <> " Start completion")
                (waitHostWorkload registry workloadKey)
                >>= (@?= Right HostWorkloadSucceeded)
              readIORef ran >>= (@?= True)
              lookupHostWorkload registry workloadKey
                >>= (@?= Just (HostWorkloadTerminal HostWorkloadSucceeded))
          )
          hostStartActionCases
    , testCase "Runtime production Start rejects a missing registry without running user code" $ do
        ran <- newIORef False
        let action =
              Runtime.RunAppleHostTraining
                (trainingStart "runtime-start-missing-registry")
        Runtime.executeAppleHostWorkloadStart
          Nothing
          action
          (writeIORef ran True)
          >>= ( @?=
                  Left
                    ( SEConflict
                        "host workload Start requires the persistent Apple host registry"
                    )
              )
        readIORef ran >>= (@?= False)
    , testCase "Runtime production Start rejects duplicate and terminal keys without running them" $ do
        registry <- newHostWorkloadRegistry
        let experimentHash = "runtime-start-duplicate"
            action = Runtime.RunAppleHostTraining (trainingStart experimentHash)
            workloadKey = key TrainingWorkload experimentHash
        started <- newEmptyMVar
        release <- newEmptyMVar
        Runtime.executeAppleHostWorkloadStart
          (Just registry)
          action
          (putMVar started () >> takeMVar release)
          >>= (@?= Right ())
        within "Runtime duplicate fixture Start" (takeMVar started)
        duplicateRan <- newIORef False
        duplicate <-
          Runtime.executeAppleHostWorkloadStart
            (Just registry)
            action
            (writeIORef duplicateRan True)
        assertServiceConflictContains "duplicate" duplicate
        readIORef duplicateRan >>= (@?= False)
        putMVar release ()
        within "Runtime duplicate fixture completion" (waitHostWorkload registry workloadKey)
          >>= (@?= Right HostWorkloadSucceeded)
        terminalRan <- newIORef False
        terminal <-
          Runtime.executeAppleHostWorkloadStart
            (Just registry)
            action
            (writeIORef terminalRan True)
        assertServiceConflictContains "duplicate" terminal
        readIORef terminalRan >>= (@?= False)
    , testCase "Runtime production Start rejects non-Start and invalid actions without running them" $ do
        registry <- newHostWorkloadRegistry
        let inferenceAction =
              Runtime.RunAppleHostInference
                ( Inference.RunInference
                    Inference.InferenceRequest
                      { Inference.irCallId = "host-start-no-key"
                      , Inference.irExperimentHash = "host-start-no-key"
                      , Inference.irReplyTopic = "persistent://jitml/platform/reply"
                      , Inference.irInput = [1]
                      }
                )
            stopAction =
              Runtime.StopAppleHostWorkload
                Runtime.CancelAppleHostWorkload
                (key TrainingWorkload "host-start-stop-action")
            invalidAction =
              Runtime.RunAppleHostTraining
                (trainingStart "")
        traverse_
          ( \action -> do
              ran <- newIORef False
              rejected <-
                Runtime.executeAppleHostWorkloadStart
                  (Just registry)
                  action
                  (writeIORef ran True)
              assertServiceConflictContains "no registry key" rejected
              readIORef ran >>= (@?= False)
          )
          [inferenceAction, stopAction]
        invalidRan <- newIORef False
        invalid <-
          Runtime.executeAppleHostWorkloadStart
            (Just registry)
            invalidAction
            (writeIORef invalidRan True)
        assertServiceConflictContains "invalid training" invalid
        readIORef invalidRan >>= (@?= False)
    , testCase "Runtime production Stop cancels every host workload family and replays the same event" $ do
        let runFamily (family, label) = do
              registry <- newHostWorkloadRegistry
              let experimentHash = "runtime-cancel-" <> label
                  workloadKey = key family experimentHash
                  originalEvent = hostStopEvent family AppleSilicon experimentHash False
                  distinctEvent = hostStopEvent family LinuxCPU experimentHash False
              started <- newEmptyMVar
              never <- newEmptyMVar
              finalized <- newIORef False
              registered <-
                startHostWorkload registry workloadKey $
                  (putMVar started () >> takeMVar never)
                    `finally` writeIORef finalized True
              assertRight "Runtime cancel Start" registered
              within "Runtime cancel workload start" (takeMVar started)
              within
                "Runtime cancel decision"
                ( Runtime.executeAppleHostWorkloadStop
                    (Just registry)
                    originalEvent
                    Runtime.CancelAppleHostWorkload
                    workloadKey
                )
                >>= (@?= Right ())
              readIORef finalized >>= (@?= True)
              lookupHostWorkload registry workloadKey
                >>= (@?= Just (HostWorkloadTerminal HostWorkloadCancelled))
              Runtime.executeAppleHostWorkloadStop
                (Just registry)
                originalEvent
                Runtime.CancelAppleHostWorkload
                workloadKey
                >>= (@?= Right ())
              distinct <-
                Runtime.executeAppleHostWorkloadStop
                  (Just registry)
                  distinctEvent
                  Runtime.CancelAppleHostWorkload
                  workloadKey
              assertServiceConflictContains "already terminal" distinct
        traverse_ runFamily hostWorkloadFamilies
    , testCase "Runtime production Stop drains every host workload family and replays the same event" $ do
        let runFamily (family, label) = do
              registry <- newHostWorkloadRegistry
              let experimentHash = "runtime-drain-" <> label
                  workloadKey = key family experimentHash
                  originalEvent = hostStopEvent family AppleSilicon experimentHash True
                  distinctEvent = hostStopEvent family LinuxCPU experimentHash True
              started <- newEmptyMVar
              completeNaturally <- newEmptyMVar
              finalized <- newIORef False
              registered <-
                startHostWorkload registry workloadKey $
                  (putMVar started () >> takeMVar completeNaturally)
                    `finally` writeIORef finalized True
              assertRight "Runtime drain Start" registered
              within "Runtime drain workload start" (takeMVar started)
              stopper <-
                async
                  ( Runtime.executeAppleHostWorkloadStop
                      (Just registry)
                      originalEvent
                      Runtime.DrainAppleHostWorkload
                      workloadKey
                  )
              within
                "Runtime drain claim"
                (awaitSnapshot registry workloadKey HostWorkloadStopping)
              Timeout.timeout 25_000 (wait stopper) >>= (@?= Nothing)
              readIORef finalized >>= (@?= False)
              putMVar completeNaturally ()
              within "Runtime drain decision" (wait stopper)
                >>= (@?= Right ())
              readIORef finalized >>= (@?= True)
              lookupHostWorkload registry workloadKey
                >>= (@?= Just (HostWorkloadTerminal HostWorkloadSucceeded))
              Runtime.executeAppleHostWorkloadStop
                (Just registry)
                originalEvent
                Runtime.DrainAppleHostWorkload
                workloadKey
                >>= (@?= Right ())
              distinct <-
                Runtime.executeAppleHostWorkloadStop
                  (Just registry)
                  distinctEvent
                  Runtime.DrainAppleHostWorkload
                  workloadKey
              assertServiceConflictContains "already terminal" distinct
        traverse_ runFamily hostWorkloadFamilies
    , testCase "Runtime production Stop rejects missing, unknown, and already-terminal handles" $ do
        let modes =
              [ (Runtime.CancelAppleHostWorkload, False, "cancel")
              , (Runtime.DrainAppleHostWorkload, True, "drain")
              ]
            runCase (family, familyLabel) (mode, drain, modeLabel) = do
              registry <- newHostWorkloadRegistry
              let unknownHash = "runtime-unknown-" <> familyLabel <> "-" <> modeLabel
                  unknownKey = key family unknownHash
                  unknownEvent = hostStopEvent family AppleSilicon unknownHash drain
              unknown <-
                Runtime.executeAppleHostWorkloadStop
                  (Just registry)
                  unknownEvent
                  mode
                  unknownKey
              assertServiceConflictContains "unknown" unknown
              let terminalHash = "runtime-terminal-" <> familyLabel <> "-" <> modeLabel
                  terminalKey = key family terminalHash
                  terminalEvent = hostStopEvent family AppleSilicon terminalHash drain
              registered <- startHostWorkload registry terminalKey (pure ())
              assertRight "Runtime terminal Start" registered
              within "Runtime terminal completion" (waitHostWorkload registry terminalKey)
                >>= (@?= Right HostWorkloadSucceeded)
              terminal <-
                Runtime.executeAppleHostWorkloadStop
                  (Just registry)
                  terminalEvent
                  mode
                  terminalKey
              assertServiceConflictContains "already terminal" terminal
        traverse_ (\family -> traverse_ (runCase family) modes) hostWorkloadFamilies
        let missingKey = key TrainingWorkload "runtime-missing-registry"
            missingEvent = hostStopEvent TrainingWorkload AppleSilicon "runtime-missing-registry" False
        Runtime.executeAppleHostWorkloadStop
          Nothing
          missingEvent
          Runtime.CancelAppleHostWorkload
          missingKey
          >>= ( @?=
                  Left
                    ( SEConflict
                        "host workload Stop requires the persistent Apple host registry"
                    )
              )
    , testCase "a worker observes its registered handle before user code starts" $ do
        registry <- newHostWorkloadRegistry
        let workloadKey = key TrainingWorkload "registered-before-run"
        observed <- newEmptyMVar
        registered <-
          startHostWorkload registry workloadKey $ do
            lookupHostWorkload registry workloadKey >>= putMVar observed
        assertRight "Start registration" registered
        within "worker registration observation" (takeMVar observed)
          >>= (@?= Just HostWorkloadRunning)
        within "natural completion" (waitHostWorkload registry workloadKey)
          >>= (@?= Right HostWorkloadSucceeded)
    , testCase "duplicate Start never executes and a terminal key is never reusable" $ do
        registry <- newHostWorkloadRegistry
        let workloadKey = key TuneWorkload "duplicate"
        started <- newEmptyMVar
        release <- newEmptyMVar
        duplicateRan <- newIORef False
        first <-
          startHostWorkload registry workloadKey $ do
            putMVar started ()
            takeMVar release
        assertRight "first Start" first
        within "first workload start" (takeMVar started)
        duplicate <-
          startHostWorkload registry workloadKey (writeIORef duplicateRan True)
        duplicate @?= Left (DuplicateHostWorkloadStart workloadKey)
        stopped <- within "duplicate fixture Stop" (stopHostWorkload registry workloadKey)
        joinedHostWorkloadOutcome (expectRight "first Stop" stopped)
          @?= HostWorkloadCancelled
        readIORef duplicateRan >>= (@?= False)
        afterTerminal <- startHostWorkload registry workloadKey (pure ())
        afterTerminal @?= Left (DuplicateHostWorkloadStart workloadKey)
    , testCase "Stop returns success only after cancellation finalizers and join" $ do
        registry <- newHostWorkloadRegistry
        let workloadKey = key RlWorkload "joined-stop"
        started <- newEmptyMVar
        never <- newEmptyMVar
        finalized <- newIORef False
        registered <-
          startHostWorkload registry workloadKey $
            (putMVar started () >> takeMVar never)
              `finally` writeIORef finalized True
        assertRight "cancellable Start" registered
        within "cancellable workload start" (takeMVar started)
        stopped <- within "joined Stop" (stopHostWorkload registry workloadKey)
        joinedHostWorkloadOutcome (expectRight "joined Stop" stopped)
          @?= HostWorkloadCancelled
        readIORef finalized >>= (@?= True)
        lookupHostWorkload registry workloadKey
          >>= (@?= Just (HostWorkloadTerminal HostWorkloadCancelled))
        activeHostWorkloadCount registry >>= (@?= 0)
    , testCase "unknown and naturally terminal Stops fail closed with tombstone outcome" $ do
        registry <- newHostWorkloadRegistry
        let unknown = key TrainingWorkload "unknown"
            completed = key TrainingWorkload "naturally-completed"
        stopHostWorkload registry unknown
          >>= (@?= Left (UnknownHostWorkload unknown))
        registered <- startHostWorkload registry completed (pure ())
        assertRight "natural Start" registered
        within "natural terminal tombstone" (waitHostWorkload registry completed)
          >>= (@?= Right HostWorkloadSucceeded)
        stopHostWorkload registry completed
          >>= (@?= Left (HostWorkloadAlreadyTerminal completed HostWorkloadSucceeded))
        lookupHostWorkload registry completed
          >>= (@?= Just (HostWorkloadTerminal HostWorkloadSucceeded))
    , testCase "natural completion can win after the exact-once Stop claim" $ do
        registry <- newHostWorkloadRegistry
        let workloadKey = key TuneWorkload "completion-race"
        started <- newEmptyMVar
        completeNaturally <- newEmptyMVar
        registered <-
          startHostWorkload registry workloadKey $ do
            putMVar started ()
            takeMVar completeNaturally
        assertRight "race Start" registered
        within "race workload start" (takeMVar started)
        pendingResult <- beginHostWorkloadStop registry workloadKey
        let pending = expectRight "Stop claim" pendingResult
        lookupHostWorkload registry workloadKey
          >>= (@?= Just HostWorkloadStopping)
        putMVar completeNaturally ()
        within "race natural completion" (waitHostWorkload registry workloadKey)
          >>= (@?= Right HostWorkloadSucceeded)
        completeHostWorkloadStop pending
          >>= (@?= Left (HostWorkloadCancellationLostRace workloadKey HostWorkloadSucceeded))
    , testCase "one Stop claim excludes every concurrent Stop follower" $ do
        registry <- newHostWorkloadRegistry
        let workloadKey = key RlWorkload "concurrent-stops"
        started <- newEmptyMVar
        never <- newEmptyMVar
        registered <-
          startHostWorkload registry workloadKey $ do
            putMVar started ()
            takeMVar never
        assertRight "concurrent Stop Start" registered
        within "concurrent Stop workload start" (takeMVar started)
        pendingResult <- beginHostWorkloadStop registry workloadKey
        let pending = expectRight "leader Stop claim" pendingResult
        followers <-
          forM [1 .. 8 :: Int] $ \_index ->
            async (stopHostWorkload registry workloadKey)
        followerResults <- traverse (within "concurrent Stop follower" . wait) followers
        lefts followerResults
          @?= replicate 8 (HostWorkloadStopAlreadyRequested workloadKey)
        completed <- within "leader Stop completion" (completeHostWorkloadStop pending)
        joinedHostWorkloadOutcome (expectRight "leader Stop completion" completed)
          @?= HostWorkloadCancelled
    , testCase "required publication failure lets only the same Stop event replay its joined receipt" $ do
        registry <- newHostWorkloadRegistry
        let workloadKey = key TrainingWorkload "event-bound-cancel"
            originalEvent = trainingStopEvent AppleSilicon "event-bound-cancel" False
            distinctEvent = trainingStopEvent LinuxCPU "event-bound-cancel" False
        started <- newEmptyMVar
        never <- newEmptyMVar
        registered <-
          startHostWorkload registry workloadKey $ do
            putMVar started ()
            takeMVar never
        assertRight "event-bound cancellable Start" registered
        within "event-bound cancellable workload start" (takeMVar started)
        first <-
          within
            "event-bound cancellation"
            (stopHostWorkloadForEvent registry originalEvent workloadKey)
        let joined = expectRight "event-bound cancellation" first
        joinedHostWorkloadOutcome joined @?= HostWorkloadCancelled
        let publicationFailure = Left (SETransient "terminal status unavailable")
        Runtime.applyWorkflowStatusProjectionResult
          Runtime.RequireWorkflowStatusProjection
          publicationFailure
          @?= publicationFailure
        stopHostWorkloadForEvent registry originalEvent workloadKey
          >>= (@?= Right joined)
        Runtime.applyWorkflowStatusProjectionResult
          Runtime.RequireWorkflowStatusProjection
          (Right ())
          @?= Right ()
        stopHostWorkloadForEvent registry distinctEvent workloadKey
          >>= (@?= Left (HostWorkloadAlreadyTerminal workloadKey HostWorkloadCancelled))
        drainHostWorkloadForEvent registry originalEvent workloadKey
          >>= (@?= Left (HostWorkloadAlreadyTerminal workloadKey HostWorkloadCancelled))
    , testCase "drain Stop claims exactly once and joins natural success without cancelling" $ do
        registry <- newHostWorkloadRegistry
        let workloadKey = key TrainingWorkload "joined-drain"
            originalEvent = trainingStopEvent AppleSilicon "joined-drain" True
            distinctEvent = trainingStopEvent LinuxCPU "joined-drain" True
        started <- newEmptyMVar
        completeNaturally <- newEmptyMVar
        finalized <- newIORef False
        registered <-
          startHostWorkload registry workloadKey $
            (putMVar started () >> takeMVar completeNaturally)
              `finally` writeIORef finalized True
        assertRight "drainable Start" registered
        within "drainable workload start" (takeMVar started)
        leader <- async (drainHostWorkloadForEvent registry originalEvent workloadKey)
        within
          "drain Stop claim"
          (awaitSnapshot registry workloadKey HostWorkloadStopping)
        followers <-
          forM [1 .. 8 :: Int] $ \_index ->
            async (drainHostWorkload registry workloadKey)
        followerResults <- traverse (within "drain Stop follower" . wait) followers
        lefts followerResults
          @?= replicate 8 (HostWorkloadStopAlreadyRequested workloadKey)
        premature <- Timeout.timeout 25_000 (wait leader)
        premature @?= Nothing
        readIORef finalized >>= (@?= False)
        putMVar completeNaturally ()
        completed <- within "joined drain Stop" (wait leader)
        let joined = expectRight "joined drain Stop" completed
        joinedHostWorkloadOutcome joined @?= HostWorkloadSucceeded
        drainHostWorkloadForEvent registry originalEvent workloadKey
          >>= (@?= Right joined)
        drainHostWorkloadForEvent registry distinctEvent workloadKey
          >>= (@?= Left (HostWorkloadAlreadyTerminal workloadKey HostWorkloadSucceeded))
        readIORef finalized >>= (@?= True)
        lookupHostWorkload registry workloadKey
          >>= (@?= Just (HostWorkloadTerminal HostWorkloadSucceeded))
        activeHostWorkloadCount registry >>= (@?= 0)
    , testCase "drain Stop fails closed when natural completion fails" $ do
        registry <- newHostWorkloadRegistry
        let workloadKey = key RlWorkload "failed-drain"
        started <- newEmptyMVar
        failNaturally <- newEmptyMVar
        registered <-
          startHostWorkload registry workloadKey $ do
            putMVar started ()
            takeMVar failNaturally
            throwIO (userError "drain-fixture-boom")
        assertRight "failing drain Start" registered
        within "failing drain workload start" (takeMVar started)
        pendingResult <- beginHostWorkloadStop registry workloadKey
        let pending = expectRight "failing drain Stop claim" pendingResult
        putMVar failNaturally ()
        drained <- within "failed drain join" (completeHostWorkloadDrain pending)
        case drained of
          Left (HostWorkloadDrainDidNotSucceed observedKey (HostWorkloadFailed failure)) -> do
            observedKey @?= workloadKey
            assertBool "drain failure text retained" ("drain-fixture-boom" `Text.isInfixOf` failure)
          other -> assertFailure ("expected a retained drain failure, got " <> show other)
    , testCase "workload exceptions become retained failure tombstones" $ do
        registry <- newHostWorkloadRegistry
        let workloadKey = key TrainingWorkload "failed-workload"
        registered <-
          startHostWorkload registry workloadKey (throwIO (userError "fixture-boom"))
        assertRight "failing Start" registered
        terminal <- within "failed workload" (waitHostWorkload registry workloadKey)
        case terminal of
          Right (HostWorkloadFailed failure) ->
            assertBool "failure text retained" ("fixture-boom" `Text.isInfixOf` failure)
          other -> assertFailure ("expected a failure tombstone, got " <> show other)
        consumeOnceFailure <- waitForConsumeOnceHostWorkloads (Just registry)
        case consumeOnceFailure of
          Just (PrerequisiteUnmet operation detail _recovery) -> do
            operation @?= "service.apple-host-workload.consume-once"
            assertBool
              "consume-once surfaces the retained worker failure"
              ( "training/failed-workload" `Text.isInfixOf` detail
                  && "fixture-boom" `Text.isInfixOf` detail
              )
          other ->
            assertFailure
              ("expected consume-once to surface a retained failure, got " <> show other)
    , testCase "consume-once waits for every registered Start before succeeding" $ do
        registry <- newHostWorkloadRegistry
        let workloadKey = key TuneWorkload "consume-once-wait"
        started <- newEmptyMVar
        completeNaturally <- newEmptyMVar
        registered <-
          startHostWorkload registry workloadKey $ do
            putMVar started ()
            takeMVar completeNaturally
        assertRight "consume-once Start" registered
        within "consume-once workload start" (takeMVar started)
        waiter <- async (waitForConsumeOnceHostWorkloads (Just registry))
        premature <- Timeout.timeout 25_000 (wait waiter)
        premature @?= Nothing
        putMVar completeNaturally ()
        within "consume-once workload completion" (wait waiter)
          >>= (@?= Nothing)
    , testCase "bounded drain cancels and joins every family without leaked handles" $ do
        registry <- newHostWorkloadRegistry
        cleanupCount <- newIORef (0 :: Int)
        startedSignals <- traverse (const newEmptyMVar) workloadKeys
        never <- newEmptyMVar
        traverse_
          (uncurry (startBlocking registry cleanupCount never))
          (zip workloadKeys startedSignals)
        traverse_ (within "drain workload start" . takeMVar) startedSignals
        drained <- within "registry drain" (drainHostWorkloadRegistry registry 2_000_000)
        let report = expectRight "registry drain" drained
        fmap fst (drainedHostWorkloads report)
          @?= List.sort workloadKeys
        fmap snd (drainedHostWorkloads report)
          @?= replicate 3 HostWorkloadCancelled
        readIORef cleanupCount >>= (@?= 3)
        activeHostWorkloadCount registry >>= (@?= 0)
        let rejectedKey = key TrainingWorkload "after-drain"
        ranAfterDrain <- newIORef False
        rejected <-
          startHostWorkload registry rejectedKey (writeIORef ranAfterDrain True)
        rejected @?= Left (HostWorkloadRegistryNotAcceptingStarts rejectedKey)
        readIORef ranAfterDrain >>= (@?= False)
        drainHostWorkloadRegistry registry 2_000_000
          >>= (@?= Right (HostWorkloadDrainReport []))
    , testCase "drain has one total deadline and can be safely retried" $ do
        registry <- newHostWorkloadRegistry
        let workloadKey = key RlWorkload "bounded-drain"
        started <- newEmptyMVar
        cancellationObserved <- newEmptyMVar
        allowCompletion <- newEmptyMVar
        never <- newEmptyMVar
        registered <-
          startHostWorkload registry workloadKey $ do
            putMVar started ()
            cancellation <- try @AsyncCancelled (takeMVar never)
            case cancellation of
              Left _cancelled -> do
                putMVar cancellationObserved ()
                takeMVar allowCompletion
              Right impossible -> pure impossible
        assertRight "bounded drain Start" registered
        within "bounded drain workload start" (takeMVar started)
        firstDrain <- async (drainHostWorkloadRegistry registry 100_000)
        within "bounded drain cancellation" (takeMVar cancellationObserved)
        within "bounded drain deadline" (wait firstDrain)
          >>= (@?= Left (HostWorkloadDrainTimedOut [workloadKey]))
        activeHostWorkloadCount registry >>= (@?= 1)
        putMVar allowCompletion ()
        within "post-timeout completion" (waitHostWorkload registry workloadKey)
          >>= (@?= Right HostWorkloadSucceeded)
        drainHostWorkloadRegistry registry 2_000_000
          >>= (@?= Right (HostWorkloadDrainReport []))
        activeHostWorkloadCount registry >>= (@?= 0)
    , testCase "zero drain deadlines fail without changing registry admission" $ do
        registry <- newHostWorkloadRegistry
        drainHostWorkloadRegistry registry 0
          >>= (@?= Left HostWorkloadDrainDeadlineMustBePositive)
        let workloadKey = key TrainingWorkload "after-invalid-drain"
        registered <- startHostWorkload registry workloadKey (pure ())
        assertRight "Start after invalid drain" registered
        within "Start after invalid drain completion" (waitHostWorkload registry workloadKey)
          >>= (@?= Right HostWorkloadSucceeded)
    ]

workloadKeys :: [HostWorkloadKey]
workloadKeys =
  [ key TrainingWorkload "drain-training"
  , key TuneWorkload "drain-tune"
  , key RlWorkload "drain-rl"
  ]

hostStartActionCases
  :: [(Text.Text, HostWorkloadFamily, Text.Text, Runtime.AppleHostWorkloadAction)]
hostStartActionCases =
  [
    ( "training"
    , TrainingWorkload
    , "runtime-start-training"
    , Runtime.RunAppleHostTraining (trainingStart "runtime-start-training")
    )
  ,
    ( "tune"
    , TuneWorkload
    , "runtime-start-tune"
    , Runtime.RunAppleHostTune (tuneStart "runtime-start-tune")
    )
  ,
    ( "rl"
    , RlWorkload
    , "runtime-start-rl"
    , Runtime.RunAppleHostRl (rlStart "runtime-start-rl")
    )
  ,
    ( "alphazero"
    , RlWorkload
    , "runtime-start-alphazero"
    , Runtime.RunAppleHostAlphaZero (alphaZeroStart "runtime-start-alphazero")
    )
  ]

trainingStart :: Text.Text -> Training.StartTraining
trainingStart experimentHash =
  Training.StartTraining
    { Training.stExperimentHash = experimentHash
    , Training.stDhallObjectKey = "experiments/runtime-start.dhall"
    , Training.stSubstrate = AppleSilicon
    , Training.stSeed = 1
    , Training.stEpochs = 1
    , Training.stBatchSize = 1
    , Training.stPlanId = "runtime-start-plan"
    , Training.stResolvedPlan = "runtime-start-resolved-plan"
    , Training.stTrainingExamples = 1
    , Training.stEvaluationExamples = 1
    }

tuneStart :: Text.Text -> Tune.StartSweep
tuneStart experimentHash =
  Tune.StartSweep
    { Tune.ssExperimentHash = experimentHash
    , Tune.ssDhallObjectKey = "experiments/runtime-start-tune.dhall"
    , Tune.ssSubstrate = AppleSilicon
    , Tune.ssSweepSeed = 1
    , Tune.ssTrialBudget = 1
    , Tune.ssBudgetPerTrial = 1
    , Tune.ssSampler = "random"
    , Tune.ssScheduler = "fifo"
    , Tune.ssPruner = "none"
    , Tune.ssParallelism = 1
    , Tune.ssPromotions = 1
    , Tune.ssPlanId = "runtime-start-tune-plan"
    , Tune.ssResolvedPlan = "runtime-start-tune-resolved-plan"
    }

rlStart :: Text.Text -> Rl.StartRLRun
rlStart experimentHash =
  Rl.StartRLRun
    { Rl.srlExperimentHash = experimentHash
    , Rl.srlAlgorithm = "ppo"
    , Rl.srlEnvironment = "cartpole"
    , Rl.srlSubstrate = AppleSilicon
    , Rl.srlSeed = 1
    , Rl.srlMaxSteps = 1
    , Rl.srlEvalEpisodes = 1
    }

alphaZeroStart :: Text.Text -> Rl.StartAlphaZeroRun
alphaZeroStart experimentHash =
  Rl.StartAlphaZeroRun
    { Rl.sazSubstrate = AppleSilicon
    , Rl.sazExperimentHash = experimentHash
    , Rl.sazPlanId = "runtime-start-alphazero-plan"
    , Rl.sazResolvedPlan = "runtime-start-alphazero-resolved-plan"
    , Rl.sazGame = "hex"
    , Rl.sazGenerations = 1
    , Rl.sazSelfPlayGames = 1
    , Rl.sazMctsSimulationsPerMove = 1
    , Rl.sazMaxPlies = 1
    , Rl.sazOptimizerUpdates = 1
    , Rl.sazArenaGames = 1
    , Rl.sazSeed = 1
    }

hostWorkloadFamilies :: [(HostWorkloadFamily, Text.Text)]
hostWorkloadFamilies =
  [ (TrainingWorkload, "training")
  , (TuneWorkload, "tune")
  , (RlWorkload, "rl")
  ]

startBlocking
  :: HostWorkloadRegistry
  -> IORef Int
  -> MVar ()
  -> HostWorkloadKey
  -> MVar ()
  -> IO ()
startBlocking registry cleanupCount never workloadKey started = do
  registered <-
    startHostWorkload registry workloadKey $
      (putMVar started () >> takeMVar never)
        `finally` atomicModifyIORef' cleanupCount (\count -> (count + 1, ()))
  assertRight "drain fixture Start" registered

key
  :: HostWorkloadFamily
  -> Text.Text
  -> HostWorkloadKey
key family experimentHash =
  expectRight
    "valid host workload key fixture"
    (refineHostWorkloadKey family experimentHash)

expectRight :: (Show errorValue) => String -> Either errorValue value -> value
expectRight label result =
  case result of
    Left registryError -> error (label <> " failed: " <> show registryError)
    Right value -> value

assertRight :: (Show errorValue) => String -> Either errorValue value -> IO ()
assertRight label result =
  case result of
    Left registryError ->
      assertFailure (label <> " failed: " <> show registryError)
    Right _value -> pure ()

assertServiceConflictContains
  :: (Show value)
  => Text.Text
  -> Either ServiceError value
  -> IO ()
assertServiceConflictContains expected result =
  case result of
    Left (SEConflict detail) ->
      assertBool
        ("expected ServiceError conflict to contain " <> show expected <> ", got " <> show detail)
        (expected `Text.isInfixOf` Text.toLower detail)
    other ->
      assertFailure
        ("expected SEConflict containing " <> show expected <> ", got " <> show other)

within :: String -> IO value -> IO value
within label action = do
  result <- Timeout.timeout fixtureTimeoutMicroseconds action
  case result of
    Nothing -> throwIO (userError (label <> " timed out"))
    Just value -> pure value

fixtureTimeoutMicroseconds :: Int
fixtureTimeoutMicroseconds = 3_000_000

awaitSnapshot
  :: HostWorkloadRegistry
  -> HostWorkloadKey
  -> HostWorkloadSnapshot
  -> IO ()
awaitSnapshot registry workloadKey expected = do
  observed <- lookupHostWorkload registry workloadKey
  if observed == Just expected
    then pure ()
    else threadDelay 1_000 >> awaitSnapshot registry workloadKey expected

trainingStopEvent :: Substrate -> Text.Text -> Bool -> EventId
trainingStopEvent substrate experimentHash drain =
  expectRight
    "valid Stop event fixture"
    ( validationToEither
        ( daemonCommandEventId
            ( TrainingDaemonCommand
                substrate
                (Training.TrainingStop (Training.StopTraining experimentHash drain))
            )
        )
    )

hostStopEvent
  :: HostWorkloadFamily
  -> Substrate
  -> Text.Text
  -> Bool
  -> EventId
hostStopEvent family substrate experimentHash drain =
  expectRight
    "valid family Stop event fixture"
    ( validationToEither
        ( daemonCommandEventId
            ( case family of
                TrainingWorkload ->
                  TrainingDaemonCommand
                    substrate
                    (Training.TrainingStop (Training.StopTraining experimentHash drain))
                TuneWorkload ->
                  TuneDaemonCommand
                    substrate
                    (Tune.TuneStop (Tune.StopSweep experimentHash))
                RlWorkload ->
                  RlDaemonCommand
                    substrate
                    (Rl.RlStop (Rl.StopRLRun experimentHash drain))
            )
        )
    )
