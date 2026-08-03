{-# LANGUAGE OverloadedStrings #-}

module JitML.Test.Command
  ( TestCommandRuntime (..)
  , runTest
  )
where

import Control.Exception.Safe
  ( bracket
  , displayException
  , generalBracket
  , throwIO
  , tryAny
  )
import Control.Monad (unless, when)
import Control.Monad.Reader (ask, liftIO, runReaderT)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified
import Data.ByteString.Char8 qualified as ByteString.Char8
import Data.Foldable qualified as Foldable
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Maybe (fromMaybe, listToMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import System.Directory
  ( canonicalizePath
  , copyFile
  , createDirectoryIfMissing
  , doesFileExist
  , findExecutable
  , makeAbsolute
  , removeFile
  )
import System.Environment (getExecutablePath)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory, takeFileName, (</>))
import System.IO.Temp (withSystemTempDirectory, withTempDirectory)
import System.Posix.IO
  ( OpenFileFlags (cloexec, creat, exclusive)
  , OpenMode (WriteOnly)
  , closeFd
  , defaultFileFlags
  , fdWrite
  , openFd
  )
import Text.Read (readMaybe)

import Network.Socket
  ( AddrInfo (..)
  , Socket
  , SocketType (Stream)
  , close
  , connect
  , defaultHints
  , getAddrInfo
  , socket
  , withSocketsDo
  )
import Network.Socket.ByteString (recv, sendAll)

import JitML.AppError.AppError (AppError (..))
import JitML.Bootstrap (readExistingLivePublication)
import JitML.CLI.Output (exitWithError, writeLine, writeText)
import JitML.CLI.Parser (ParsedOption)
import JitML.CLI.Spec (commandPathText)
import JitML.Cluster.Publication qualified as Publication
import JitML.Engines.CudaRuntime (cudaRuntimeAvailable, probeCudaRuntime)
import JitML.Engines.MetalRuntime (metalRuntimeAvailable, probeMetalRuntime)
import JitML.Engines.OneDnnRuntime
  ( oneDnnRuntimeAvailable
  , probeOneDnnRuntime
  )
import JitML.Env.Env (App, Env)
import JitML.Numerics.MlpDeviceSelect (mlpDeviceForSubstrate)
import JitML.Plan.Plan (Validation (..))
import JitML.Product.BrowserCatalogue qualified as BrowserCatalogue
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.RL.AlphaZero qualified as AlphaZero
import JitML.RL.AlphaZero.PolicyValueNet qualified as PolicyValueNet
import JitML.Sub.Outcome
  ( ObservedProcessFailure (..)
  , ObservedProcessOutcome (..)
  , ProcessOutcome (..)
  , processFailureExitCode
  )
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Stream
  ( SubprocessEnv
  , runStreaming
  , runStreamingObserved
  , subprocessEnvOverrideAndRemove
  )
import JitML.Sub.Subprocess (Subprocess (..), subprocess)
import JitML.Substrate (Substrate (..), parseSubstrate, renderSubstrate)
import JitML.Test.BrowserEvidenceJournal qualified as BrowserEvidenceJournal
import JitML.Test.LiveE2EScope qualified as LiveE2EScope
import JitML.Test.LivePlan
  ( BrowserEvidencePlanPaths (..)
  , LivePlanStep (..)
  , LiveResourceOwnership (..)
  , ScopedLivePlan (..)
  , scopedLiveE2EPlanFor
  , scopedLiveE2EPlanForBrowserEvidence
  )
import JitML.Test.ProductScenarioAuthorization qualified as ProductScenarioAuthorization
import JitML.Test.ProductScenarioJournal qualified as ProductScenarioJournal
import JitML.Test.Report
  ( CompletedProductScenarioReport
  , InvocationJournal
  , ReportCard (..)
  , ReportMeasurement (..)
  , ReportMeasurements (..)
  , appendInvocation
  , emptyInvocationJournal
  , emptyReportMeasurements
  , failedObservedInvocation
  , firstObservedInvocationFailure
  , loadReportCardKnobs
  , notRunObservedInvocation
  , passedInvocation
  , renderReportCardWithKnobs
  , reportStanzas
  , substrateRuntimeStanzas
  , substrateTestInvocations
  )
import JitML.Tune.Catalog qualified as Tune

-- | App-owned option resolution and worker measurements consumed by the test
-- command. Keeping these effects explicit lets the command/report orchestration
-- compile independently without importing "JitML.App".
data TestCommandRuntime = TestCommandRuntime
  { testCommandBootstrapSubstrates :: [ParsedOption] -> [Text]
  , testCommandHasOption :: Text -> [ParsedOption] -> Bool
  , testCommandSelectedValue :: Text -> Text -> [ParsedOption] -> Text
  , testCommandMeasureSlFinalLossText :: App (Maybe Text)
  , testCommandMeasureRlFinalRewardText :: App (Maybe Text)
  , testCommandPublishBrowserCatalogue
      :: ProductMatrix.ProductProjectionBatch
      -> ProductScenarioJournal.AuthenticatedProductScenarioReport
      -> App (Either Text BrowserCatalogue.ProductBrowserCatalogue)
  }

-- | One command-owned cross-process evidence scope.  The constructor remains
-- private so child environment variables, the reader's immutable checkpoint
-- root, and the expected projection batch cannot drift independently.
data ProductScenarioCommandScope = ProductScenarioCommandScope
  { productScenarioRunId :: !Text
  , productScenarioJournalPath :: !FilePath
  , productScenarioJournalKey :: !ProductScenarioAuthorization.ProductScenarioJournalKey
  , productScenarioJournalKeyPath :: !FilePath
  , productScenarioExecutablePath :: !FilePath
  , productScenarioExecutableSha256 :: !Text
  , productScenarioCheckpointRoot :: !FilePath
  , productScenarioProjectionBatch :: !ProductMatrix.ProductProjectionBatch
  }

-- | Fresh browser-only authority and host-visible handoff paths.  The browser
-- scope contains neither the ProductScenario key nor its checkpoint root.  Its
-- expected row set is installed only after the parent has authenticated,
-- re-admitted, and published the current ProductScenario aggregate.
data BrowserEvidenceCommandScope = BrowserEvidenceCommandScope
  { browserEvidenceCatalogueInputPath :: !FilePath
  , browserEvidencePublicationInputPath :: !FilePath
  , browserEvidenceLivePublicationPath :: !FilePath
  , browserEvidenceWritableScopePath :: !FilePath
  , browserEvidenceResultPath :: !FilePath
  , browserEvidenceFallbackResultPath :: !FilePath
  , browserEvidenceResultKeyPath :: !FilePath
  , browserEvidenceResultKey :: !BrowserEvidenceJournal.BrowserEvidenceJournalKey
  , browserEvidencePreparedEvidence
      :: !( IORef
              ( Maybe
                  ( BrowserEvidenceJournal.BrowserEvidenceExpectation
                  , ProductScenarioJournal.AuthenticatedProductScenarioReport
                  )
              )
          )
  }

runTest :: TestCommandRuntime -> [Text] -> [ParsedOption] -> App ()
runTest runtime ["test", "all"] parsedOptions =
  runCabalTest runtime parsedOptions reportStanzas
runTest runtime ["test", stanza] parsedOptions
  | stanza `elem` reportStanzas =
      runCabalTest runtime parsedOptions [stanza]
  | otherwise =
      exitWithError (UnknownCommand ("unknown test stanza: " <> stanza))
runTest _runtime path _ =
  exitWithError (UnknownCommand ("unknown test command: " <> commandPathText path))
{-# NOINLINE runTest #-}

liveE2ESubstrate :: TestCommandRuntime -> [ParsedOption] -> App Substrate
liveE2ESubstrate runtime parsedOptions =
  case testCommandBootstrapSubstrates runtime parsedOptions of
    [substrateName] ->
      case parseSubstrate substrateName of
        Just substrate -> pure substrate
        Nothing -> exitWithError (InvalidConfig ("unknown substrate: " <> substrateName))
    [] -> do
      publication <- liftIO (readExistingLivePublication ".")
      case publication of
        Just existing
          | Publication.publicationHasLiveEvidence existing ->
              pure (Publication.publicationSubstrate existing)
        _ ->
          exitWithError
            ( InvalidConfig
                "test --live requires one substrate flag when no live cluster publication exists"
            )
    _ -> exitWithError (InvalidConfig "test --live accepts at most one substrate flag")

-- | Run the requested Cabal test stanzas, optionally restricted to one
-- substrate's lane. Every stanza receives its own process invocation so its
-- outcome is exact and a fail-fast suffix can be retained as @NotRun@. With
-- exactly one substrate flag the
-- 'substratePartitionedStanzas' run under @-p \<substrate\>@ (and @-fcuda@ on
-- @linux-cuda@), while non-partitioned stanzas run in full, one invocation at a
-- time, so live substrate tests do not contend over the same cluster/device.
-- The canonical SL/RL/tuning stanzas still contain selected-substrate device
-- cases, so a precondition probe first asserts the substrate's runtime is
-- really present and the child test process receives @JITML_SUBSTRATE@. A
-- missing-hardware run fails by design instead of silently degrading.
runCabalTest :: TestCommandRuntime -> [ParsedOption] -> [Text] -> App ()
runCabalTest runtime parsedOptions targets =
  case testCommandBootstrapSubstrates runtime parsedOptions of
    []
      | testCommandHasOption runtime "live" parsedOptions -> do
          substrate <- liveE2ESubstrate runtime parsedOptions
          ensureSubstrateRuntimeFor substrate targets
          runCabalInvocations
            runtime
            parsedOptions
            targets
            (Just substrate)
            (substrateTestInvocations (Just substrate) targets userOptions)
      | otherwise ->
          runCabalInvocations
            runtime
            parsedOptions
            targets
            Nothing
            (substrateTestInvocations Nothing targets userOptions)
    [substrateName] ->
      case parseSubstrate substrateName of
        Nothing -> exitWithError (InvalidConfig ("unknown substrate: " <> substrateName))
        Just substrate -> do
          ensureSubstrateRuntimeFor substrate targets
          runCabalInvocations
            runtime
            parsedOptions
            targets
            (Just substrate)
            (substrateTestInvocations (Just substrate) targets userOptions)
    _ -> exitWithError (InvalidConfig "test accepts at most one substrate flag")
 where
  -- `--test-options` is an opaque passthrough forwarded verbatim to
  -- `cabal test`; under a substrate flag it is appended after the synthesized
  -- `-p <substrate>` lane selector.
  userOptions =
    case testCommandSelectedValue runtime "test-options" "" parsedOptions of
      "" -> Nothing
      opts -> Just opts

-- | Fail fast when a substrate lane is requested but its runtime is absent,
-- but only when the run actually includes a stanza with substrate-backed
-- device work.
ensureSubstrateRuntimeFor :: Substrate -> [Text] -> App ()
ensureSubstrateRuntimeFor substrate targets
  | not
      ( any (`elem` substrateRuntimeStanzas) targets
          || "jitml-e2e" `elem` targets
      ) =
      pure ()
  | otherwise =
      case substrate of
        LinuxCUDA ->
          guardRuntime
            (cudaRuntimeAvailable <$> probeCudaRuntime)
            "test --linux-cuda requires an NVIDIA GPU and the CUDA toolkit (nvcc + libcublas/libcudnn); none detected"
        LinuxCPU ->
          guardRuntime
            (oneDnnRuntimeAvailable <$> probeOneDnnRuntime)
            "test --linux-cpu requires oneDNN (libdnnl plus headers); none detected"
        AppleSilicon ->
          guardRuntime
            (metalRuntimeAvailable <$> probeMetalRuntime)
            "test --apple-silicon requires a visible Apple Metal device; the core path uses the fixed jitML Metal bridge and does not require swiftc, xcrun metal, Tart, or keychain state"
 where
  guardRuntime probe message = do
    available <- liftIO probe
    unless available (exitWithError (InvalidConfig message))

-- | Run each planned @cabal test@ invocation in order. On the first failure,
-- retain the failed outcome and append @NotRun@ rows for the fail-fast suffix;
-- render the complete journal before propagating that original failure.
runCabalInvocations
  :: TestCommandRuntime
  -> [ParsedOption]
  -> [Text]
  -> Maybe Substrate
  -> [[Text]]
  -> App ()
runCabalInvocations runtime parsedOptions targets selectedTestSubstrate invocations = do
  cabalExecutable <- resolveCabalExecutable
  loadedKnobs <- liftIO (loadReportCardKnobs "cabal.project")
  case loadedKnobs of
    Left err -> exitWithError (InvalidConfig err)
    Right knobs -> do
      planned <-
        case pairPlannedInvocations targets invocations of
          Nothing ->
            exitWithError
              (InvalidConfig "internal test plan mismatch between stanzas and Cabal invocations")
          Just paired -> pure paired
      (journal, scenarioJournals, measurements, liveFailure) <-
        if testCommandHasOption runtime "live" parsedOptions
          then
            runScopedLiveInvocations
              cabalExecutable
              targets
              selectedTestSubstrate
              planned
          else do
            scenarioBatch <-
              productScenarioBatchFor targets selectedTestSubstrate
            env <- ask
            (observed, verification) <-
              liftIO
                ( withProductScenarioCommandScope scenarioBatch $ \scenarioScope ->
                    do
                      observed <-
                        runReaderT
                          ( runPlannedInvocations
                              cabalExecutable
                              scenarioScope
                              emptyInvocationJournal
                              planned
                          )
                          env
                      verification <-
                        verifyGreenProductScenarioJournal
                          targets
                          scenarioScope
                          observed
                      pure (observed, verification)
                )
            case verification of
              Left detail -> exitWithError (InvalidConfig detail)
              Right () ->
                pure (observed, [], emptyReportMeasurements, Nothing)
      writeText
        ( renderReportCardWithKnobs
            knobs
            ReportCard
              { reportInvocationJournal = journal
              , reportMeasurements = measurements
              , reportScenarioJournals = scenarioJournals
              }
        )
      case liveFailure of
        Just err -> exitWithError err
        Nothing ->
          Foldable.for_
            (firstObservedInvocationFailure journal)
            (exitWithError . observedProcessAppError)
 where
  pairPlannedInvocations [] [] = Just []
  pairPlannedInvocations (target : remainingTargets) (args : remainingInvocations) =
    ((target, args) :) <$> pairPlannedInvocations remainingTargets remainingInvocations
  pairPlannedInvocations _ _ = Nothing

  runPlannedInvocations _cabalExecutable _scenarioScope journal [] = pure journal
  runPlannedInvocations cabalExecutable scenarioScope journal ((target, args) : remaining) = do
    let command =
          commandFor
            cabalExecutable
            args
        environment =
          testInvocationEnvironment
            selectedTestSubstrate
            target
            scenarioScope
    (outcome, keyRemoval) <-
      liftIO
        ( generalBracket
            (pure ())
            ( \() _exitCase ->
                if target == "jitml-integration"
                  then tryAny (removeProductScenarioJournalKeyFileIfPresent scenarioScope)
                  else pure (Right ())
            )
            (\() -> runStreamingObserved environment command)
        )
    case outcome of
      ObservedProcessSucceeded transcript ->
        case keyRemoval of
          Left _cleanupException ->
            exitWithError
              ( InvalidConfig
                  "could not remove the ProductScenario journal key file"
              )
          Right () ->
            runPlannedInvocations
              cabalExecutable
              scenarioScope
              (appendInvocation journal (passedInvocation target transcript))
              remaining
      ObservedProcessFailed failure ->
        pure
          ( Foldable.foldl'
              ( \observed (notRunTarget, notRunArgs) ->
                  appendInvocation
                    observed
                    ( notRunObservedInvocation
                        notRunTarget
                        ( renderSubprocess
                            ( commandFor
                                cabalExecutable
                                notRunArgs
                            )
                        )
                        target
                        failure
                    )
              )
              (appendInvocation journal (failedObservedInvocation target failure))
              remaining
          )

  runScopedLiveInvocations cabalExecutable selectedTargets substrateMaybe planned =
    case substrateMaybe of
      Nothing ->
        exitWithError
          (InvalidConfig "internal live test plan is missing its selected substrate")
      Just substrate -> do
        existing <- liftIO (readExistingLivePublication ".")
        ownership <- liveResourceOwnership substrate existing
        let browserRequested = "jitml-e2e" `elem` selectedTargets
            scenarioTargets
              | browserRequested && "jitml-integration" `notElem` selectedTargets =
                  "jitml-integration" : selectedTargets
              | otherwise = selectedTargets
        scenarioBatch <-
          productScenarioBatchFor scenarioTargets (Just substrate)
        producerPair <-
          if browserRequested
            then case [ pair
                      | pair@(target, _args) <- planned
                      , target == "jitml-integration"
                      ] of
              [pair] -> pure (Just pair)
              [] ->
                case substrateTestInvocations (Just substrate) ["jitml-integration"] Nothing of
                  [args] -> pure (Just ("jitml-integration", args))
                  _ ->
                    exitWithError
                      ( InvalidConfig
                          "internal live e2e plan could not construct its integration producer"
                      )
              _ ->
                exitWithError
                  ( InvalidConfig
                      "internal live e2e plan contains multiple integration producers"
                  )
            else pure Nothing
        env <- ask
        scoped <-
          liftIO
            ( withProductScenarioCommandScope scenarioBatch $ \scenarioScope -> do
                if browserRequested
                  then withBrowserEvidenceCommandScope $ \browserScope -> do
                    let scopePlan =
                          scopedLiveE2EPlanForBrowserEvidence
                            (browserEvidencePlanPaths browserScope)
                            ownership
                            substrate
                        playwrightSteps =
                          [ step
                          | step <- scopedLivePlanBody scopePlan
                          , livePlanStepName step == "playwright"
                          ]
                        selectedE2EPairs =
                          [ pair
                          | pair@(target, _args) <- planned
                          , target == "jitml-e2e"
                          ]
                        remainingPairs =
                          [ pair
                          | pair@(target, _args) <- planned
                          , target /= "jitml-integration"
                          , target /= "jitml-e2e"
                          ]
                    case (producerPair, playwrightSteps, selectedE2EPairs) of
                      (Just producer, [playwrightStep], [e2ePair]) -> do
                        let producerInvocation =
                              cabalInvocationFor
                                cabalExecutable
                                substrate
                                scenarioScope
                                producer
                            playwrightInvocation =
                              LiveE2EScope.PlannedTestInvocation
                                { LiveE2EScope.plannedTestStanza = "jitml-e2e-playwright"
                                , LiveE2EScope.plannedTestCommand =
                                    livePlanStepCommand playwrightStep
                                , LiveE2EScope.plannedTestEnvironment =
                                    testInvocationEnvironment
                                      (Just substrate)
                                      "jitml-e2e-playwright"
                                      scenarioScope
                                }
                            postRefinementInvocations =
                              fmap
                                ( cabalInvocationFor
                                    cabalExecutable
                                    substrate
                                    scenarioScope
                                )
                                (e2ePair : remainingPairs)
                            producerRefinement =
                              LiveE2EScope.LiveE2ERefinement
                                { LiveE2EScope.liveE2ERefinementSourceStanza =
                                    "jitml-integration"
                                , LiveE2EScope.liveE2ERefinementName =
                                    "product-browser-catalogue"
                                , LiveE2EScope.liveE2ERefinementAction =
                                    prepareBrowserEvidence
                                      env
                                      runtime
                                      scenarioScope
                                      browserScope
                                }
                            browserRefinement =
                              LiveE2EScope.LiveE2ERefinement
                                { LiveE2EScope.liveE2ERefinementSourceStanza =
                                    "jitml-e2e-playwright"
                                , LiveE2EScope.liveE2ERefinementName =
                                    "browser-result-journal"
                                , LiveE2EScope.liveE2ERefinementAction =
                                    refineBrowserEvidenceAndMeasurements
                                      env
                                      runtime
                                      selectedTargets
                                      scenarioScope
                                      browserScope
                                }
                        LiveE2EScope.runStagedLiveE2EScope
                          ( liveE2EScopeBackend
                              substrate
                              scenarioScope
                              (Just browserScope)
                          )
                          scopePlan
                          [producerInvocation]
                          producerRefinement
                          [playwrightInvocation]
                          browserRefinement
                          postRefinementInvocations
                      _ ->
                        ioError
                          ( userError
                              "live e2e plan requires exactly one integration producer, Playwright step, and Haskell e2e invocation"
                          )
                  else do
                    let scopePlan = scopedLiveE2EPlanFor ownership substrate
                        cabalInvocations =
                          fmap
                            ( cabalInvocationFor
                                cabalExecutable
                                substrate
                                scenarioScope
                            )
                            planned
                    LiveE2EScope.runLiveE2EScope
                      (liveE2EScopeBackend substrate scenarioScope Nothing)
                      scopePlan
                      cabalInvocations
                      (collectMeasurements env selectedTargets scenarioScope Nothing)
            )
        pure
          ( LiveE2EScope.liveE2EInvocationJournal scoped
          , [LiveE2EScope.liveE2EScenarioJournal scoped]
          , fromMaybe emptyReportMeasurements (LiveE2EScope.liveE2EPostBodyResult scoped)
          , liveScopeAppError scoped
          )

  cabalInvocationFor cabalExecutable substrate scenarioScope (target, args) =
    LiveE2EScope.PlannedTestInvocation
      { LiveE2EScope.plannedTestStanza = target
      , LiveE2EScope.plannedTestCommand = commandFor cabalExecutable args
      , LiveE2EScope.plannedTestEnvironment =
          testInvocationEnvironment
            (Just substrate)
            target
            scenarioScope
      }

  collectMeasurements env selectedTargets scenarioScope browserEvidence = do
    keyRemoval <-
      tryAny (removeProductScenarioJournalKeyFileIfPresent scenarioScope)
    case keyRemoval of
      Left _cleanupException ->
        pure (Left "could not remove the ProductScenario journal key file")
      Right () -> do
        measured <-
          tryAny
            ( runReaderT
                ( collectLiveReportMeasurements
                    runtime
                    selectedTargets
                    scenarioScope
                    browserEvidence
                )
                env
            )
        pure $
          case measured of
            Left exception ->
              Left
                ( "live report measurement collection failed: "
                    <> Text.pack (displayException exception)
                )
            Right values -> Right values

  productScenarioBatchFor selectedTargets substrateMaybe
    | not (productScenarioAcquisitionRequired selectedTargets) = pure Nothing
    | otherwise =
        case substrateMaybe of
          Nothing ->
            exitWithError
              ( InvalidConfig
                  "product scenario integration acquisition requires one selected substrate"
              )
          Just substrate ->
            case ProductMatrix.projectProductRows
              substrate
              ProductMatrix.allProductRows of
              Failure errors ->
                exitWithError
                  ( InvalidConfig
                      ( "product scenario projection failed: "
                          <> Text.pack (show (NonEmpty.toList errors))
                      )
                  )
              Success batch -> pure (Just batch)

  liveResourceOwnership substrate existing =
    case existing of
      Nothing -> pure OwnedEphemeralCluster
      Just publication
        | Publication.publicationSubstrate publication /= substrate ->
            exitWithError
              ( InvalidConfig
                  ( "test --live requested "
                      <> renderSubstrate substrate
                      <> " but cluster-publication.json is for "
                      <> renderSubstrate (Publication.publicationSubstrate publication)
                  )
              )
        | Publication.publicationHasLiveEvidence publication -> do
            writeLine
              ( "test --live: borrowing existing "
                  <> renderSubstrate substrate
                  <> " publication at edge :"
                  <> Text.pack (show (Publication.publicationEdgePort publication))
              )
            pure BorrowedLiveCluster
        | otherwise -> pure OwnedEphemeralCluster

  liveE2EScopeBackend substrate scenarioScope browserScope =
    LiveE2EScope.LiveE2EScopeBackend
      { LiveE2EScope.liveE2ERunStep =
          \environment step -> do
            (attemptedOutcome, keyRemoval) <-
              generalBracket
                (pure ())
                ( \() _exitCase ->
                    tryAny (removeStepCapabilityFiles step)
                )
                ( \() ->
                    tryAny (runStreaming environment (livePlanStepCommand step))
                )
            case attemptedOutcome of
              Left processException -> throwIO processException
              Right outcome ->
                case (outcome, keyRemoval) of
                  (ProcessSucceeded _transcript, Left _cleanupException) ->
                    throwIO
                      (userError "could not remove a completed test step capability file")
                  _ -> pure outcome
      , LiveE2EScope.liveE2ELifecycleEnvironment =
          testInvocationEnvironment
            (Just substrate)
            "live-e2e-lifecycle"
            scenarioScope
      , LiveE2EScope.liveE2EDiagnosticSteps =
          [ LivePlanStep
              "cluster-pods"
              ( subprocess
                  "kubectl"
                  [ "--kubeconfig"
                  , "./.build/jitml.kubeconfig"
                  , "get"
                  , "pods"
                  , "--all-namespaces"
                  , "-o"
                  , "wide"
                  ]
              )
          ]
      , LiveE2EScope.liveE2EAcceptReleaseFailure =
          (== ExitFailure 3) . processFailureExitCode
      }
   where
    removeStepCapabilityFiles step = do
      when
        (livePlanStepName step == "jitml-integration")
        (removeProductScenarioJournalKeyFileIfPresent scenarioScope)
      when
        (livePlanStepName step == "jitml-e2e-playwright")
        (removeBrowserEvidenceResultKeyFileIfPresent browserScope)

  liveScopeAppError scoped =
    case LiveE2EScope.liveE2EScopeFailure scoped of
      Just (LiveE2EScope.LiveE2EProcessFailure failure) ->
        Just
          ( observedProcessAppError
              (LiveE2EScope.liveE2EFailureProcess failure)
          )
      Just (LiveE2EScope.LiveE2EPostBodyIssue failure) ->
        Just (InvalidConfig failure)
      Nothing -> Nothing

  observedProcessAppError failure =
    case failure of
      ObservedProcessExitFailure processFailure ->
        SubprocessFailed processFailure
      ObservedProcessAttemptFailure attemptFailure ->
        SubprocessAttemptFailed attemptFailure

  commandFor cabalExecutable args =
    prioritizeLiveCabal
      (testCommandHasOption runtime "live" parsedOptions)
      (subprocess cabalExecutable args)

  prioritizeLiveCabal live command
    | not live = command
    | otherwise =
        ( subprocess
            "/usr/bin/nice"
            ( "-n"
                : "10"
                : Text.pack (subprocessPath command)
                : subprocessArguments command
            )
        )
          { subprocessWorkingDirectory = subprocessWorkingDirectory command
          , subprocessStdin = subprocessStdin command
          }
{-# NOINLINE runCabalInvocations #-}

productScenarioEvidenceRequired :: [Text] -> Bool
productScenarioEvidenceRequired targets =
  "jitml-integration" `elem` targets || "jitml-e2e" `elem` targets

productScenarioAcquisitionRequired :: [Text] -> Bool
productScenarioAcquisitionRequired = elem "jitml-integration"

-- | Resolve the Cabal driver once in the already-established trusted
-- container toolchain context.  Every planned transcript and execution then
-- retains that exact canonical path instead of performing a child-side PATH
-- lookup.
resolveCabalExecutable :: App FilePath
resolveCabalExecutable = do
  resolved <-
    liftIO
      ( tryAny $ do
          discovered <- findExecutable "cabal"
          case discovered of
            Nothing -> ioError (userError "cabal is absent from the trusted toolchain PATH")
            Just path -> canonicalizePath path
      )
  case resolved of
    Left exception ->
      exitWithError
        ( InvalidConfig
            ( "could not resolve the trusted Cabal executable: "
                <> Text.pack (displayException exception)
            )
        )
    Right path -> pure path

verifyGreenProductScenarioJournal
  :: [Text]
  -> Maybe ProductScenarioCommandScope
  -> InvocationJournal
  -> IO (Either Text ())
verifyGreenProductScenarioJournal targets scenarioScope journal
  | not (productScenarioAcquisitionRequired targets) = pure (Right ())
  | Just _childFailure <- firstObservedInvocationFailure journal = pure (Right ())
  | otherwise =
      case scenarioScope of
        Nothing ->
          pure
            ( Left
                "green integration acquisition has no command-owned ProductScenario scope"
            )
        Just scope -> do
          loaded <-
            ProductScenarioJournal.readProductScenarioJournal
              (productScenarioJournalKey scope)
              (productScenarioJournalPath scope)
              (productScenarioCheckpointRoot scope)
              (productScenarioRunId scope)
              (productScenarioExecutablePath scope)
              (productScenarioExecutableSha256 scope)
              (productScenarioProjectionBatch scope)
          pure $
            case loaded of
              Left errors ->
                Left
                  ( "green integration acquisition did not produce an authenticated "
                      <> "ProductScenario journal: "
                      <> Text.pack (show (NonEmpty.toList errors))
                  )
              Right _report -> Right ()

-- | Allocate one fresh parent that outlives the child invocations and the
-- post-body journal read, then disappears after live diagnostics and release.
-- The integration writer owns creation of @workspace@ and its checkpoint
-- objects; observing a pre-existing journal or checkpoint root is therefore
-- impossible for a command-created scope.
withProductScenarioCommandScope
  :: Maybe ProductMatrix.ProductProjectionBatch
  -> (Maybe ProductScenarioCommandScope -> IO value)
  -> IO value
withProductScenarioCommandScope Nothing action = action Nothing
withProductScenarioCommandScope (Just batch) action =
  withSystemTempDirectory "jitml-product-scenario" $ \rawParent -> do
    parent <- makeAbsolute rawParent
    executablePath <- getExecutablePath >>= canonicalizePath
    executableSha256 <- productScenarioFileSha256 executablePath
    generatedKey <- ProductScenarioAuthorization.generateProductScenarioJournalKey
    journalKey <-
      case generatedKey of
        Left keyError ->
          ioError
            ( userError
                ( "product scenario journal key generation failed: "
                    <> show keyError
                )
            )
        Right key -> pure key
    let journalPath = parent </> "journal.json"
        journalKeyPath = parent </> "journal.key"
        checkpointRoot =
          takeDirectory journalPath
            </> "workspace"
            </> ".build"
            </> "checkpoints"
        runId = Text.pack (takeFileName parent)
    writeProductScenarioJournalKeyFile journalKeyPath journalKey
    action
      ( Just
          ProductScenarioCommandScope
            { productScenarioRunId = runId
            , productScenarioJournalPath = journalPath
            , productScenarioJournalKey = journalKey
            , productScenarioJournalKeyPath = journalKeyPath
            , productScenarioExecutablePath = executablePath
            , productScenarioExecutableSha256 = executableSha256
            , productScenarioCheckpointRoot = checkpointRoot
            , productScenarioProjectionBatch = batch
            }
      )

-- | Allocate browser-only authority below the repository's host-visible
-- runtime directory.  The nested Playwright Docker command receives only the
-- two exact read-only files and this fresh writable scope; the ProductScenario
-- key, checkpoint root, and executable challenge remain in their independent
-- system-temporary scope.
withBrowserEvidenceCommandScope
  :: (BrowserEvidenceCommandScope -> IO value)
  -> IO value
withBrowserEvidenceCommandScope action = do
  runtimeRoot <- makeAbsolute (".build" </> "runtime")
  createDirectoryIfMissing True runtimeRoot
  withSystemTempDirectory "jitml-browser-parent" $ \rawParentOnly ->
    withTempDirectory runtimeRoot "jitml-browser-evidence-" $ \rawParent -> do
      parent <- makeAbsolute rawParent
      parentOnly <- makeAbsolute rawParentOnly
      let catalogueRoot = parent </> "input"
          writableRoot = parent </> "scope"
          cataloguePath = catalogueRoot </> "catalogue.json"
          publicationInputPath = catalogueRoot </> "cluster-publication.json"
          resultPath = writableRoot </> "result.json"
          fallbackResultPath = parentOnly </> "fallback-result.json"
          resultKeyPath = writableRoot </> "result.key"
      createDirectoryIfMissing True catalogueRoot
      createDirectoryIfMissing True writableRoot
      livePublicationPath <-
        makeAbsolute (".build" </> "runtime" </> "cluster-publication.json")
      generatedKey <- BrowserEvidenceJournal.generateBrowserEvidenceJournalKey
      resultKey <-
        case generatedKey of
          Left keyError ->
            ioError
              ( userError
                  ( "browser evidence journal key generation failed: "
                      <> show keyError
                  )
              )
          Right key -> pure key
      preparedEvidence <- newIORef Nothing
      action
        BrowserEvidenceCommandScope
          { browserEvidenceCatalogueInputPath = cataloguePath
          , browserEvidencePublicationInputPath = publicationInputPath
          , browserEvidenceLivePublicationPath = livePublicationPath
          , browserEvidenceWritableScopePath = writableRoot
          , browserEvidenceResultPath = resultPath
          , browserEvidenceFallbackResultPath = fallbackResultPath
          , browserEvidenceResultKeyPath = resultKeyPath
          , browserEvidenceResultKey = resultKey
          , browserEvidencePreparedEvidence = preparedEvidence
          }

browserEvidencePlanPaths
  :: BrowserEvidenceCommandScope
  -> BrowserEvidencePlanPaths
browserEvidencePlanPaths scope =
  BrowserEvidencePlanPaths
    { browserEvidenceCataloguePath = browserEvidenceCatalogueInputPath scope
    , browserEvidencePublicationPath = browserEvidencePublicationInputPath scope
    , browserEvidenceScopePath = browserEvidenceWritableScopePath scope
    }

-- | Authenticate the exact current integration aggregate, publish it through
-- the live MinIO admission/CAS transaction, then materialize the browser-safe
-- input and an authenticated all-NotRun seed.  No browser process starts until
-- this entire parent-owned refinement succeeds.
prepareBrowserEvidence
  :: Env
  -> TestCommandRuntime
  -> Maybe ProductScenarioCommandScope
  -> BrowserEvidenceCommandScope
  -> IO (LiveE2EScope.LiveE2ERefinementOutcome ())
prepareBrowserEvidence _env _runtime Nothing _browserScope =
  pure
    ( LiveE2EScope.LiveE2ERefinementRejected
        "browser evidence preparation has no command-owned ProductScenario scope"
    )
prepareBrowserEvidence env runtime (Just scenarioScope) browserScope = do
  authenticated <-
    ProductScenarioJournal.readAuthenticatedProductScenarioJournal
      (productScenarioJournalKey scenarioScope)
      (productScenarioJournalPath scenarioScope)
      (productScenarioCheckpointRoot scenarioScope)
      (productScenarioRunId scenarioScope)
      (productScenarioExecutablePath scenarioScope)
      (productScenarioExecutableSha256 scenarioScope)
      (productScenarioProjectionBatch scenarioScope)
  case authenticated of
    Left errors ->
      pure
        ( LiveE2EScope.LiveE2ERefinementRejected
            ( "authenticated ProductScenario refinement failed: "
                <> Text.pack (show (NonEmpty.toList errors))
            )
        )
    Right authenticatedReport -> do
      published <-
        runReaderT
          ( testCommandPublishBrowserCatalogue
              runtime
              (productScenarioProjectionBatch scenarioScope)
              authenticatedReport
          )
          env
      case published of
        Left failure ->
          pure
            ( LiveE2EScope.LiveE2ERefinementRejected
                ("browser catalogue publication failed: " <> failure)
            )
        Right catalogue ->
          case browserExpectationFromCatalogue catalogue of
            Left errors ->
              pure
                ( LiveE2EScope.LiveE2ERefinementRejected
                    ( "published browser catalogue identity refinement failed: "
                        <> Text.pack (show (NonEmpty.toList errors))
                    )
                )
            Right expectation -> do
              livePublication <- readExistingLivePublication "."
              case livePublication of
                Just publication
                  | Publication.publicationSubstrate publication
                      == BrowserCatalogue.productBrowserCatalogueSubstrate catalogue -> do
                      copyFile
                        (browserEvidenceLivePublicationPath browserScope)
                        (browserEvidencePublicationInputPath browserScope)
                      Text.IO.writeFile
                        (browserEvidenceCatalogueInputPath browserScope)
                        (BrowserCatalogue.renderProductBrowserCatalogueInput catalogue)
                      initialized <-
                        BrowserEvidenceJournal.writeInitialBrowserEvidenceJournalAtomic
                          (browserEvidenceResultKey browserScope)
                          (browserEvidenceFallbackResultPath browserScope)
                          expectation
                      case initialized of
                        Left errors ->
                          pure
                            ( LiveE2EScope.LiveE2ERefinementRejected
                                ( "could not initialize browser result journal: "
                                    <> Text.pack (show (NonEmpty.toList errors))
                                )
                            )
                        Right () -> do
                          writeBrowserEvidenceResultKeyFile
                            (browserEvidenceResultKeyPath browserScope)
                            (browserEvidenceResultKey browserScope)
                          writeIORef
                            (browserEvidencePreparedEvidence browserScope)
                            (Just (expectation, authenticatedReport))
                          pure (LiveE2EScope.LiveE2ERefined ())
                _ ->
                  pure
                    ( LiveE2EScope.LiveE2ERefinementRejected
                        "browser catalogue was published without an exact matching live cluster publication"
                    )

browserExpectationFromCatalogue
  :: BrowserCatalogue.ProductBrowserCatalogue
  -> Either
       (NonEmpty.NonEmpty BrowserEvidenceJournal.BrowserEvidenceJournalError)
       BrowserEvidenceJournal.BrowserEvidenceExpectation
browserExpectationFromCatalogue catalogue =
  BrowserEvidenceJournal.browserEvidenceExpectation
    (BrowserCatalogue.productBrowserCatalogueRunId catalogue)
    (BrowserCatalogue.productBrowserCatalogueSubstrate catalogue)
    (BrowserCatalogue.productBrowserCatalogueSha256 catalogue)
    (BrowserCatalogue.productBrowserCatalogueSourceJournalDigest catalogue)
    (fmap expectedRow (BrowserCatalogue.productBrowserCatalogueRows catalogue))
 where
  expectedRow row =
    BrowserEvidenceJournal.BrowserEvidenceExpectedRow
      { BrowserEvidenceJournal.expectedBrowserOrdinal =
          BrowserCatalogue.productBrowserCatalogueRowOrdinal row
      , BrowserEvidenceJournal.expectedBrowserRowId =
          BrowserCatalogue.productBrowserCatalogueRowRowId row
      , BrowserEvidenceJournal.expectedBrowserPlanId =
          BrowserCatalogue.productBrowserCatalogueRowPlanId row
      , BrowserEvidenceJournal.expectedBrowserExperimentHash =
          BrowserCatalogue.productBrowserCatalogueRowExperimentHash row
      , BrowserEvidenceJournal.expectedBrowserManifestSha256 =
          BrowserCatalogue.productBrowserCatalogueRowManifestSha row
      , BrowserEvidenceJournal.expectedBrowserE2ETest =
          BrowserCatalogue.productBrowserCatalogueRowE2ETest row
      }

-- | Consume the browser key before parsing the untrusted result, authenticate
-- and join all 55 rows to the published catalogue expectation, then retain the
-- exact row report even when explicit Failed/NotRun statuses make the gate
-- non-green.  Measurement failures likewise keep both authenticated row sets.
refineBrowserEvidenceAndMeasurements
  :: Env
  -> TestCommandRuntime
  -> [Text]
  -> Maybe ProductScenarioCommandScope
  -> BrowserEvidenceCommandScope
  -> IO (LiveE2EScope.LiveE2ERefinementOutcome ReportMeasurements)
refineBrowserEvidenceAndMeasurements
  env
  runtime
  targets
  scenarioScope
  browserScope = do
    removeBrowserEvidenceResultKeyFileIfPresent (Just browserScope)
    prepared <- readIORef (browserEvidencePreparedEvidence browserScope)
    case prepared of
      Nothing ->
        pure
          ( LiveE2EScope.LiveE2ERefinementRejected
              "browser result refinement has no authenticated published expectation"
          )
      Just (expectation, authenticatedSource) -> do
        resultExists <- doesFileExist (browserEvidenceResultPath browserScope)
        let journalPath
              | resultExists = browserEvidenceResultPath browserScope
              | otherwise = browserEvidenceFallbackResultPath browserScope
        refined <-
          BrowserEvidenceJournal.readBrowserEvidenceJournal
            (browserEvidenceResultKey browserScope)
            journalPath
            expectation
        case refined of
          Left errors ->
            pure
              ( LiveE2EScope.LiveE2ERefinementRejected
                  ( "browser result journal refinement failed: "
                      <> Text.pack (show (NonEmpty.toList errors))
                  )
              )
          Right browserReport -> do
            measured <-
              tryAny
                ( runReaderT
                    ( collectLiveReportMeasurements
                        runtime
                        targets
                        scenarioScope
                        (Just browserReport)
                    )
                    env
                )
            case measured of
              Left exception ->
                pure
                  ( LiveE2EScope.LiveE2ERefinedWithIssue
                      ( retainedBrowserMeasurements
                          authenticatedSource
                          browserReport
                      )
                      ( "live report measurement collection failed after browser refinement: "
                          <> Text.pack (displayException exception)
                      )
                  )
              Right measurements
                | BrowserEvidenceJournal.browserEvidenceReportAllPassed browserReport ->
                    pure (LiveE2EScope.LiveE2ERefined measurements)
                | otherwise ->
                    pure
                      ( LiveE2EScope.LiveE2ERefinedWithIssue
                          measurements
                          (browserEvidenceGateFailure browserReport)
                      )

retainedBrowserMeasurements
  :: ProductScenarioJournal.AuthenticatedProductScenarioReport
  -> BrowserEvidenceJournal.BrowserEvidenceReport
  -> ReportMeasurements
retainedBrowserMeasurements authenticatedSource browserReport =
  emptyReportMeasurements
    { measuredBrowserProductEvidence = Just browserReport
    , measuredProductRowEvidence =
        Just
          ( ProductScenarioJournal.authenticatedProductScenarioReport
              authenticatedSource
          )
    }

browserEvidenceGateFailure
  :: BrowserEvidenceJournal.BrowserEvidenceReport
  -> Text
browserEvidenceGateFailure report =
  "browser evidence gate requires exactly 55 Passed rows; observed Passed="
    <> count BrowserEvidenceJournal.BrowserPassed
    <> ", Failed="
    <> count BrowserEvidenceJournal.BrowserFailed
    <> ", NotRun="
    <> count BrowserEvidenceJournal.BrowserNotRun
 where
  entries = BrowserEvidenceJournal.browserEvidenceReportEntries report
  count status =
    Text.pack
      ( show
          ( length
              ( filter
                  ((== status) . BrowserEvidenceJournal.browserEvidenceResultStatus)
                  entries
              )
          )
      )

-- | Only the integration acquisition process receives the signing capability.
-- The parent retains its in-memory key for the optional post-body read; the E2E
-- process and unrelated child stanzas never receive the key-file path.
productScenarioEnvironment
  :: Text
  -> Maybe ProductScenarioCommandScope
  -> [(Text, Text)]
productScenarioEnvironment target scenarioScope
  | target /= "jitml-integration" = []
  | otherwise =
      case scenarioScope of
        Nothing -> []
        Just scope ->
          [
            ( "JITML_PRODUCT_SCENARIO_JOURNAL_PATH"
            , Text.pack (productScenarioJournalPath scope)
            )
          , ("JITML_PRODUCT_SCENARIO_RUN_ID", productScenarioRunId scope)
          ,
            ( "JITML_PRODUCT_SCENARIO_JOURNAL_KEY_FILE"
            , Text.pack (productScenarioJournalKeyPath scope)
            )
          ,
            ( "JITML_PRODUCT_SCENARIO_EXECUTABLE"
            , Text.pack (productScenarioExecutablePath scope)
            )
          ,
            ( "JITML_PRODUCT_SCENARIO_EXECUTABLE_SHA256"
            , productScenarioExecutableSha256 scope
            )
          ]

-- | Carry test-only capabilities out of band from the rendered command.  An
-- override replaces an ambient value of the same name; every capability that
-- is not deliberately installed for this stanza is removed before launch.
-- In particular, unrelated stanzas cannot inherit either the command-owned
-- journal authority or a stale per-scenario invocation.
testInvocationEnvironment
  :: Maybe Substrate
  -> Text
  -> Maybe ProductScenarioCommandScope
  -> SubprocessEnv
testInvocationEnvironment substrateMaybe target scenarioScope =
  subprocessEnvOverrideAndRemove overrides removals
 where
  overrides =
    maybe
      []
      (\substrate -> [("JITML_SUBSTRATE", renderSubstrate substrate)])
      substrateMaybe
      <> productScenarioEnvironment target scenarioScope
  overriddenNames = fmap fst overrides
  removals =
    filter
      (`notElem` overriddenNames)
      ( "JITML_SUBSTRATE"
          : productScenarioEnvironmentVariableNames
            <> browserEvidenceEnvironmentVariableNames
      )

productScenarioEnvironmentVariableNames :: [Text]
productScenarioEnvironmentVariableNames =
  [ "JITML_PRODUCT_SCENARIO_JOURNAL_PATH"
  , "JITML_PRODUCT_SCENARIO_RUN_ID"
  , "JITML_PRODUCT_SCENARIO_JOURNAL_KEY_FILE"
  , "JITML_PRODUCT_SCENARIO_EXECUTABLE"
  , "JITML_PRODUCT_SCENARIO_EXECUTABLE_SHA256"
  , "JITML_PRODUCT_SCENARIO_INVOCATION"
  ]

browserEvidenceEnvironmentVariableNames :: [Text]
browserEvidenceEnvironmentVariableNames =
  [ "JITML_BROWSER_CATALOGUE_PATH"
  , "JITML_BROWSER_PUBLICATION_PATH"
  , "JITML_BROWSER_RESULT_PATH"
  , "JITML_BROWSER_RESULT_KEY_FILE"
  , "PLAYWRIGHT_TEST_RESULTS_DIR"
  ]

collectLiveReportMeasurements
  :: TestCommandRuntime
  -> [Text]
  -> Maybe ProductScenarioCommandScope
  -> Maybe BrowserEvidenceJournal.BrowserEvidenceReport
  -> App ReportMeasurements
collectLiveReportMeasurements runtime targets scenarioScope browserEvidence = do
  productRowEvidence <-
    collectProductScenarioEvidence targets scenarioScope
  slLoss <- measureSlFinalLoss runtime
  rlReward <- measureRlFinalReward runtime
  alphaZeroWinRate <- measureAlphaZeroArenaWinRate
  tuneObjective <- measureTuneBestObjective
  cacheHitRate <- measureJitCacheHitRate
  daemonHealth <- measureDaemonHealthz
  pure
    ReportMeasurements
      { measuredSlFinalLoss = Just slLoss
      , measuredRlFinalReward = Just rlReward
      , measuredAlphaZeroArenaWinRate = Just alphaZeroWinRate
      , measuredTuneBestObjective = Just tuneObjective
      , measuredJitCacheHitRate = Just cacheHitRate
      , measuredDaemonHealthz = Just daemonHealth
      , measuredBrowserProductEvidence = browserEvidence
      , measuredProductRowEvidence = productRowEvidence
      }
{-# NOINLINE collectLiveReportMeasurements #-}

-- | Every green integration run must yield product evidence, whether or not an
-- E2E stanza follows it.  Read and fully refine the untrusted cross-process
-- receipt before any metric probe runs, so stale, missing, or foreign evidence
-- fails closed without producing a partially measured report card.
collectProductScenarioEvidence
  :: [Text]
  -> Maybe ProductScenarioCommandScope
  -> App (Maybe CompletedProductScenarioReport)
collectProductScenarioEvidence targets scenarioScope
  | not (productScenarioEvidenceRequired targets) = pure Nothing
  | otherwise =
      case scenarioScope of
        Nothing ->
          exitWithError
            ( InvalidConfig
                "live product evidence requires an initialized command-owned scenario scope"
            )
        Just scope -> do
          loaded <-
            liftIO
              ( ProductScenarioJournal.readProductScenarioJournal
                  (productScenarioJournalKey scope)
                  (productScenarioJournalPath scope)
                  (productScenarioCheckpointRoot scope)
                  (productScenarioRunId scope)
                  (productScenarioExecutablePath scope)
                  (productScenarioExecutableSha256 scope)
                  (productScenarioProjectionBatch scope)
              )
          case loaded of
            Left errors ->
              exitWithError
                ( InvalidConfig
                    ( "live product scenario journal refinement failed: "
                        <> Text.pack (show (NonEmpty.toList errors))
                    )
                )
            Right report -> pure (Just report)

writeProductScenarioJournalKeyFile
  :: FilePath
  -> ProductScenarioAuthorization.ProductScenarioJournalKey
  -> IO ()
writeProductScenarioJournalKeyFile path key =
  bracket
    ( openFd
        path
        WriteOnly
        defaultFileFlags
          { creat = Just 0o600
          , exclusive = True
          , cloexec = True
          }
    )
    closeFd
    (`writeAll` encodedKey)
 where
  encodedKey =
    Text.unpack (ProductScenarioAuthorization.renderProductScenarioJournalKey key)

  writeAll _fileDescriptor [] = pure ()
  writeAll fileDescriptor remaining = do
    written <- fdWrite fileDescriptor remaining
    if written <= 0
      then ioError (userError "product scenario journal key file write made no progress")
      else writeAll fileDescriptor (drop (fromIntegral written) remaining)

writeBrowserEvidenceResultKeyFile
  :: FilePath
  -> BrowserEvidenceJournal.BrowserEvidenceJournalKey
  -> IO ()
writeBrowserEvidenceResultKeyFile path key =
  bracket
    ( openFd
        path
        WriteOnly
        defaultFileFlags
          { creat = Just 0o600
          , exclusive = True
          , cloexec = True
          }
    )
    closeFd
    (`writeAll` encodedKey)
 where
  encodedKey =
    Text.unpack (BrowserEvidenceJournal.renderBrowserEvidenceJournalKey key)

  writeAll _fileDescriptor [] = pure ()
  writeAll fileDescriptor remaining = do
    written <- fdWrite fileDescriptor remaining
    if written <= 0
      then ioError (userError "browser result journal key file write made no progress")
      else writeAll fileDescriptor (drop (fromIntegral written) remaining)

removeProductScenarioJournalKeyFileIfPresent
  :: Maybe ProductScenarioCommandScope
  -> IO ()
removeProductScenarioJournalKeyFileIfPresent Nothing = pure ()
removeProductScenarioJournalKeyFileIfPresent (Just scope) = do
  let keyPath = productScenarioJournalKeyPath scope
  exists <- doesFileExist keyPath
  when exists (removeFile keyPath)

removeBrowserEvidenceResultKeyFileIfPresent
  :: Maybe BrowserEvidenceCommandScope
  -> IO ()
removeBrowserEvidenceResultKeyFileIfPresent Nothing = pure ()
removeBrowserEvidenceResultKeyFileIfPresent (Just scope) = do
  let keyPath = browserEvidenceResultKeyPath scope
  exists <- doesFileExist keyPath
  when exists (removeFile keyPath)

productScenarioFileSha256 :: FilePath -> IO Text
productScenarioFileSha256 path =
  productScenarioHexBytes . SHA256.hash <$> Data.ByteString.readFile path

productScenarioHexBytes :: Data.ByteString.ByteString -> Text
productScenarioHexBytes = Text.pack . concatMap byteHex . Data.ByteString.unpack
 where
  byteHex byte =
    let alphabet = "0123456789abcdef"
        value = fromIntegral byte
     in [ alphabet !! (value `div` 16)
        , alphabet !! (value `mod` 16)
        ]

measureSlFinalLoss :: TestCommandRuntime -> App ReportMeasurement
measureSlFinalLoss runtime =
  maybe MeasurementUnavailable MeasurementAvailable
    <$> testCommandMeasureSlFinalLossText runtime

measureRlFinalReward :: TestCommandRuntime -> App ReportMeasurement
measureRlFinalReward runtime =
  maybe MeasurementUnavailable MeasurementAvailable
    <$> testCommandMeasureRlFinalRewardText runtime

measureAlphaZeroArenaWinRate :: App ReportMeasurement
measureAlphaZeroArenaWinRate =
  let net = PolicyValueNet.initPolicyValueNet 43 7 16 31
      adam = PolicyValueNet.initAdamFor net
      result =
        PolicyValueNet.runOneGenerationOfSelfPlay
          net
          adam
          2
          (AlphaZero.maxPliesFor "connect4")
          8
          4
          4
          99
   in pure (measuredShow "connect4/gen0=" (PolicyValueNet.genArenaWinRate result))

measureTuneBestObjective :: App ReportMeasurement
measureTuneBestObjective = do
  env <- ask
  cluster <- liftIO (readExistingLivePublication ".")
  loaded <- liftIO (Tune.loadTuningExperiment "experiments/mnist-tune.dhall")
  case (cluster, loaded >>= maybe (Left "missing tuning block") Right . Tune.tuningExperimentConfig) of
    (Just publication, Right config) -> do
      let sampler = Tune.tuningSamplerKind (Tune.tuningConfigSampler config)
          scheduler = Tune.tuningSchedulerKind (Tune.tuningConfigScheduler config)
          pruner = Tune.tuningPrunerKind (Tune.tuningConfigPruner config)
          trialCount = fromIntegral (Tune.tuningConfigTrials config)
          device = mlpDeviceForSubstrate (Publication.publicationSubstrate publication) env
      valuesE <-
        liftIO
          ( fmap
              (fmap (fmap Tune.trialResultObjective))
              (Tune.trialObjectiveResultsWithDeviceForAxes device sampler scheduler pruner trialCount)
          )
      pure $
        case valuesE of
          Left _ -> MeasurementUnavailable
          Right [] -> MeasurementUnavailable
          Right values -> measuredShow (Text.pack (show sampler) <> "=") (maximum values)
    _ -> pure MeasurementUnavailable

measureJitCacheHitRate :: App ReportMeasurement
measureJitCacheHitRate = do
  cluster <- liftIO (readExistingLivePublication ".")
  case cluster of
    Nothing -> pure MeasurementUnavailable
    Just publication -> do
      response <- liftIO (httpGetLocal (Publication.publicationEdgePort publication) "/metrics")
      pure $
        case response >>= httpOkBody >>= readCacheHitRate of
          Left _ -> MeasurementUnavailable
          Right rendered -> MeasurementAvailable rendered

measureDaemonHealthz :: App ReportMeasurement
measureDaemonHealthz = do
  cluster <- liftIO (readExistingLivePublication ".")
  case cluster of
    Nothing -> pure MeasurementUnavailable
    Just publication -> do
      let edgePort = Publication.publicationEdgePort publication
      response <- liftIO (httpGetLocal edgePort "/healthz")
      pure $
        case response >>= httpOkBody of
          Right body
            | Text.strip body == "ok" ->
                MeasurementAvailable
                  ("http://127.0.0.1:" <> Text.pack (show edgePort) <> "/healthz status=200")
          _ -> MeasurementUnavailable

measuredShow :: (Show a) => Text -> a -> ReportMeasurement
measuredShow prefix value =
  MeasurementAvailable (prefix <> Text.pack (show value))

httpGetLocal :: Int -> Text -> IO (Either Text Text)
httpGetLocal port path = do
  result <-
    tryAny $
      withSocketsDo $ do
        addresses <-
          getAddrInfo
            (Just defaultHints {addrSocketType = Stream})
            (Just "127.0.0.1")
            (Just (show port))
        case addresses of
          [] -> ioError (userError "no address for jitml live report probe")
          addr : _ ->
            bracket (openLocalSocket addr) close $ \client -> do
              sendAll client (httpGetRequest path)
              Text.pack . ByteString.Char8.unpack <$> recvAll client
  pure $
    case result of
      Left err -> Left (Text.pack (displayException err))
      Right response -> Right response

openLocalSocket :: AddrInfo -> IO Socket
openLocalSocket addr = do
  client <- socket (addrFamily addr) (addrSocketType addr) (addrProtocol addr)
  connect client (addrAddress addr)
  pure client

httpGetRequest :: Text -> Data.ByteString.ByteString
httpGetRequest path =
  ByteString.Char8.pack $
    "GET "
      <> Text.unpack path
      <> " HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"

recvAll :: Socket -> IO Data.ByteString.ByteString
recvAll client = do
  chunk <- recv client 65536
  if Data.ByteString.null chunk
    then pure Data.ByteString.empty
    else (chunk <>) <$> recvAll client

httpOkBody :: Text -> Either Text Text
httpOkBody response =
  case httpResponseStatus response of
    Just 200 -> Right (httpResponseBody response)
    Just status -> Left ("HTTP status " <> Text.pack (show status))
    Nothing -> Left "HTTP response missing status"

httpResponseStatus :: Text -> Maybe Int
httpResponseStatus response =
  case Text.words <$> listToMaybe (Text.lines response) of
    Just (_version : statusText : _) -> readMaybe (Text.unpack statusText)
    _ -> Nothing

httpResponseBody :: Text -> Text
httpResponseBody response =
  case Text.splitOn "\r\n\r\n" response of
    _headers : bodyParts -> Text.intercalate "\r\n\r\n" bodyParts
    [] -> ""

readCacheHitRate :: Text -> Either Text Text
readCacheHitRate body = do
  hits <-
    maybe (Left "jitml_jit_cache_hits missing") Right (prometheusMetricInt "jitml_jit_cache_hits" body)
  misses <-
    maybe
      (Left "jitml_jit_cache_misses missing")
      Right
      (prometheusMetricInt "jitml_jit_cache_misses" body)
  let total = hits + misses
  if total <= 0
    then Left "jit cache counters are empty"
    else
      let rate = fromIntegral hits / (fromIntegral total :: Double)
       in Right $
            "prometheus="
              <> Text.pack (show rate)
              <> " hits="
              <> Text.pack (show hits)
              <> " misses="
              <> Text.pack (show misses)

prometheusMetricInt :: Text -> Text -> Maybe Int
prometheusMetricInt metricName body =
  firstMatch (Text.lines body)
 where
  firstMatch [] = Nothing
  firstMatch (line : rest)
    | "#" `Text.isPrefixOf` Text.stripStart line = firstMatch rest
    | otherwise =
        case Text.words line of
          metric : value : _
            | metric == metricName -> readMaybe (Text.unpack value)
          _ -> firstMatch rest
