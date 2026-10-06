{-# LANGUAGE OverloadedStrings #-}

-- | Phase 288 - the journal-derived status registry.
--
-- Projection tests drive the pure model with fixtures so they never go red when
-- committed evidence goes stale. Exactly one test reads a committed lane journal
-- ("the committed linux-cuda journal admits ..."); the worktree-parity case reads
-- the phase documents and, through the production loader, the committed evidence,
-- because that is the guard rule N names as part of the standing gate.
module JournalDerivedStatus
  ( journalDerivedStatusTests
  , productPhaseStatusRegistryTests
  , closedVerdictFixture
  , refusedVerdictFixture
  , withCliWorker
  )
where

import Control.Exception (bracket)
import Control.Monad (forM_, (>=>))
import Data.Aeson (Value (..), eitherDecodeStrict', encode)
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Bifunctor qualified as Bifunctor
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (nub, sort)
import Data.List qualified as List
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust, mapMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Text.IO qualified as Text.IO
import Data.Vector qualified as Vector
import System.Directory
  ( copyFile
  , createDirectoryIfMissing
  , createFileLink
  , doesDirectoryExist
  , doesFileExist
  , getPermissions
  , listDirectory
  , removeFile
  , setOwnerExecutable
  , setPermissions
  )
import System.Environment (getExecutablePath, lookupEnv, setEnv, unsetEnv)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory, takeFileName, (</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Posix.Files (fileMode, getFileStatus, intersectFileModes)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))
import Test.Tasty.QuickCheck qualified as QuickCheck

import JitML.App qualified as App
import JitML.Docs.Check (DocsCheckEnvironment (..))
import JitML.Docs.Check qualified as DocsCheck
import JitML.Plan.Plan (Validation (..))
import JitML.Product.Matrix (ProductMatrixError (..))
import JitML.Product.Matrix qualified as Product
import JitML.Product.PhaseStatus qualified as PhaseStatus
import JitML.Product.PlanDoc qualified as PlanDoc
import JitML.Product.SourceDigest
  ( SourceStamp (..)
  , computeSourceStampIn
  , sourceDigestAlgorithm
  , sourceDigestDirectoryRoots
  , sourceDigestExtensions
  , sourceDigestFileRoots
  , sourceStampFromFiles
  )
import JitML.Product.StatusEvidence
  ( Basis (..)
  , ClosureVerdict
  , Derived (..)
  , EvidenceIndex (..)
  , EvidenceRef (..)
  , Obligation (..)
  , PhaseEntry (..)
  , Refusal (..)
  , Scope (..)
  , SprintEntry (..)
  , SprintProjection (..)
  , SprintStatus (..)
  , StatusCounts (..)
  , StatusReport
  , TranscriptEvidence (..)
  , Unmet (..)
  , WorkState (..)
  , reportProjections
  , reportVerdict
  )
import JitML.Product.StatusEvidence qualified as Evidence
import JitML.Product.StatusLoader qualified as Loader
import JitML.Product.ValidationRecord
  ( FailedEvidence (..)
  , RecordEvidence (..)
  , ValidationGate (..)
  , ValidationRecordError (..)
  )
import JitML.Product.ValidationRecord qualified as Record
import JitML.Sub.Outcome
  ( ObservedProcessFailure (..)
  , ProcessAttemptFailure (..)
  , ProcessDuration (..)
  , ProcessOutcome (..)
  , ProcessTranscript (..)
  , mkProcessFailure
  , processFailureExitCode
  , processFailureStderr
  , processFailureStdout
  )
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Stream (runStreaming, subprocessEnvOverrideAndRemove)
import JitML.Sub.Subprocess (Subprocess (..), subprocess, underNice)
import JitML.Substrate (Substrate (..), allSubstrates, renderSubstrate)
import JitML.Test.NegativeControls (pendingProductionControls)
import JitML.Test.ProductAggregation
  ( ProductAggregationError (..)
  , ProductLaneInput (..)
  )
import JitML.Test.ProductAggregation qualified as Aggregate
import JitML.Test.ProductLaneJournal qualified as Lane
import JitML.Test.Report qualified as Report
import JitML.Test.ValidationEvidence qualified as ValidationEvidence

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

zeroDigest :: Text
zeroDigest = Text.replicate 64 "0"

digestOf :: Char -> Text
digestOf = Text.replicate 64 . Text.singleton

fixtureStamp :: SourceStamp
fixtureStamp = SourceStamp {stampAlgorithm = sourceDigestAlgorithm, stampSha256 = digestOf 'a'}

otherStamp :: SourceStamp
otherStamp = SourceStamp {stampAlgorithm = sourceDigestAlgorithm, stampSha256 = digestOf 'b'}

proven :: Text -> Derived
proven subject = Proven (EvidenceRef {evidenceSubject = subject, evidenceDigest = Just (digestOf 'c')} :| [])

unproven :: Unmet -> Derived
unproven reason = Unproven (reason :| [])

-- | A one-sprint phase whose sprint id is @<number>.1@.
phaseOf :: Int -> Evidence.Closure -> PhaseEntry
phaseOf number closure =
  PhaseEntry
    { entryPhaseNumber = number
    , entryPhaseTitle = "Fixture " <> tshow number
    , entryPhaseDocument = "DEVELOPMENT_PLAN/phase-" <> show number <> "-fixture.md"
    , entrySprints =
        [ SprintEntry
            { entrySprintId = tshow number <> ".1"
            , entrySprintTitle = "Fixture " <> tshow number
            , entryClosure = closure
            }
        ]
    }

legacyOf :: Int -> PhaseEntry
legacyOf number = phaseOf number (Evidence.legacyAttested "Closure Evidence")

evidencedOf :: Int -> WorkState -> [Text] -> NonEmpty Obligation -> PhaseEntry
evidencedOf number work upstream obligations =
  phaseOf number (Evidence.evidencedSprint work upstream obligations)

tshow :: (Show a) => a -> Text
tshow = Text.pack . show

statusOf :: StatusReport -> Text -> Maybe SprintStatus
statusOf report sprint =
  projectionStatus <$> List.find ((== sprint) . projectionSprint) (reportProjections report)

statuses :: StatusReport -> [(Text, SprintStatus)]
statuses report = [(projectionSprint p, projectionStatus p) | p <- reportProjections report]

project :: [PhaseEntry] -> EvidenceIndex -> StatusReport
project phases = Evidence.projectStatusReport phases []

-- | Every laned, aggregate, transcript, ledger, and pending-control fact proven
-- and fresh: the index under which the real catalogue closes.
allProvenIndex :: EvidenceIndex
allProvenIndex =
  Evidence.emptyEvidenceIndex
    { indexLanes = Map.fromList [(lane, proven ("lane " <> renderSubstrate lane)) | lane <- allSubstrates]
    , indexAggregate = Just (proven "aggregate")
    , indexTranscripts =
        Map.fromList
          [ ((gate, lane), TranscriptEvidence (proven "transcript") (Just fixtureStamp))
          | gate <- Record.allValidationGates
          , lane <- allSubstrates
          ]
    , indexCurrentSource = Right fixtureStamp
    , indexPendingControls = Just []
    , indexLedger = Just (proven "ledger")
    }

-- | The evidence committed today, as fixtures: only the CUDA lane journal is
-- valid, the CPU and Apple journals and the aggregate are stale, no transcript
-- exists, and the ledger still has rows. The pending-control list is the real one.
todayIndex :: EvidenceIndex
todayIndex =
  Evidence.emptyEvidenceIndex
    { indexLanes =
        Map.fromList
          [ (LinuxCPU, unproven (Stale "PPO/key-door-grid contract_sha256" (digestOf '1') (digestOf '2')))
          , (LinuxCUDA, proven "cuda journal")
          , (AppleSilicon, unproven (Stale "PPO/key-door-grid contract_sha256" (digestOf '1') (digestOf '2')))
          ]
    , indexAggregate = Just (unproven (Stale "retained aggregate" (digestOf '3') (digestOf '4')))
    , indexCurrentSource = Right fixtureStamp
    , indexPendingControls = Just pendingProductionControls
    , indexLedger = Just (unproven (Incomplete "13 rows remain in Pending Removal"))
    }

-- | The real catalogue after every 'ExternalContext' obligation has been
-- deleted, which is the only way to clear one. The remaining obligations are all
-- machine-observable, so a fully proven index can close it.
withoutExternalObligations :: [PhaseEntry] -> [PhaseEntry]
withoutExternalObligations = fmap stripPhase
 where
  stripPhase phase = phase {entrySprints = fmap stripSprint (entrySprints phase)}
  stripSprint entry =
    case entryClosure entry of
      Evidence.Evidenced work upstream obligations
        | Just kept <- NonEmpty.nonEmpty (filter (not . isExternal) (NonEmpty.toList obligations)) ->
            entry {entryClosure = Evidence.Evidenced work upstream kept}
      _ -> entry
  isExternal (ExternalContext _) = True
  isExternal _ = False

-- | The projection of the external-free real catalogue over an index.
projectClosable :: EvidenceIndex -> StatusReport
projectClosable =
  Evidence.projectStatusReport
    (withoutExternalObligations PhaseStatus.productStatusCatalogue)
    PhaseStatus.productStandingObligations

-- | A closed verdict, obtained the only way one can be: a projection with nothing
-- owed. The verdict type has no public constructor, so no fixture can write one down.
closedVerdictFixture :: ClosureVerdict
closedVerdictFixture =
  reportVerdict (Evidence.projectStatusReport [] [] Evidence.emptyEvidenceIndex)

-- | A refused verdict: the standing ledger obligation with rows remaining.
refusedVerdictFixture :: ClosureVerdict
refusedVerdictFixture =
  reportVerdict
    ( Evidence.projectStatusReport
        []
        [LedgerClear]
        Evidence.emptyEvidenceIndex
          { indexLedger = Just (unproven (Incomplete "13 rows remain in Pending Removal"))
          }
    )

-- | The verdict of a one-sprint catalogue whose only obligation is @obligation@,
-- observed against @index@.
verdictFor :: Obligation -> EvidenceIndex -> ClosureVerdict
verdictFor obligation index =
  reportVerdict (project [evidencedOf 901 NotStarted [] (obligation :| [])] index)

-- | The refusals a one-obligation sprint carries, with the scope stripped.
refusalReasons :: ClosureVerdict -> [Unmet]
refusalReasons = fmap refusalReason . refusalsOf

-- | Every refusal of a verdict, none when it is closed.
refusalsOf :: ClosureVerdict -> [Refusal]
refusalsOf = either NonEmpty.toList (const []) . Evidence.closureOutcome

-- | Whether a verdict refuses closure.
isRefusedVerdict :: ClosureVerdict -> Bool
isRefusedVerdict = either (const True) (const False) . Evidence.closureOutcome

-- ---------------------------------------------------------------------------
-- The status relation
-- ---------------------------------------------------------------------------

-- | Six sprints that exercise every branch of the relation:
--
-- * 901 legacy;
-- * 902 started, depends on 901 and needs a lane journal and the aggregate;
-- * 903 not started, depends on 902 and needs an external prerequisite;
-- * 904 not started, no dependency, needs a lane journal (Planned when unmet);
-- * 905 not started, needs only an external prerequisite (Blocked when open);
-- * 906 started, needs an external prerequisite and a lane journal.
relationCatalogue :: [PhaseEntry]
relationCatalogue =
  [ legacyOf 901
  , evidencedOf 902 Started ["901.1"] (LaneJournal LinuxCPU :| [Aggregate])
  , evidencedOf 903 NotStarted ["902.1"] (ExternalContext "hardware" :| [])
  , evidencedOf 904 NotStarted [] (LaneJournal LinuxCUDA :| [])
  , evidencedOf 905 NotStarted [] (ExternalContext "other host" :| [])
  , evidencedOf 906 Started [] (ExternalContext "device" :| [LaneJournal LinuxCPU])
  ]

relationIndexProven :: EvidenceIndex
relationIndexProven =
  Evidence.emptyEvidenceIndex
    { indexLanes = Map.fromList [(lane, proven "lane") | lane <- allSubstrates]
    , indexAggregate = Just (proven "aggregate")
    }

statusRelationTests :: TestTree
statusRelationTests =
  testGroup
    "status relation"
    [ testCase "with no evidence a legacy sprint is Done and every evidenced sprint is unproven" $
        statuses (project relationCatalogue Evidence.emptyEvidenceIndex)
          @?= [ ("901.1", Done)
              , ("902.1", Active)
              , ("903.1", Blocked)
              , ("904.1", Planned)
              , ("905.1", Blocked)
              , ("906.1", Active)
              ]
    , testCase "proven obligations make a sprint Done and unblock its dependents" $ do
        let report = project relationCatalogue relationIndexProven
        statuses report
          @?= [ ("901.1", Done)
              , ("902.1", Done)
              , ("903.1", Blocked)
              , ("904.1", Done)
              , ("905.1", Blocked)
              , ("906.1", Active)
              ]
    , testCase "an open external obligation blocks a sprint that has not started" $ do
        let report = project relationCatalogue relationIndexProven
        statusOf report "905.1" @?= Just Blocked
        assertBool
          "905.1 carries an external refusal and no upstream one"
          (any isExternal (reasonsOf report "905.1") && not (any isAwaiting (reasonsOf report "905.1")))
    , testCase "an open external obligation leaves a started sprint Active, listed as remaining work" $ do
        let report = project relationCatalogue relationIndexProven
        statusOf report "906.1" @?= Just Active
        assertBool "906.1 still lists its external prerequisite" (any isExternal (reasonsOf report "906.1"))
    , testCase "an unproven upstream sprint blocks a dependent whatever it declares" $ do
        let started =
              [ legacyOf 901
              , evidencedOf 902 NotStarted [] (LaneJournal LinuxCPU :| [])
              , evidencedOf 903 Started ["902.1"] (LaneJournal LinuxCUDA :| [])
              ]
            report = project started relationIndexProven {indexLanes = Map.fromList [(LinuxCUDA, proven "lane")]}
        statusOf report "902.1" @?= Just Planned
        statusOf report "903.1" @?= Just Blocked
        assertBool "903.1 awaits 902.1" (AwaitsSprint "902.1" `elem` reasonsOf report "903.1")
    , testCase "declaring a sprint Started never makes it Done" $ do
        let catalogue =
              [ evidencedOf 902 Started [] (ExternalContext "hardware" :| [LaneJournal LinuxCPU])
              ]
            report = project catalogue Evidence.emptyEvidenceIndex
        statusOf report "902.1" @?= Just Active
        -- Even with every observable obligation proven, the external one keeps
        -- the sprint from Done: the declaration is not proof.
        statusOf (project catalogue relationIndexProven) "902.1" @?= Just Active
    , testCase "the projection does not depend on the order the catalogue is written in" $
        project (reverse relationCatalogue) Evidence.emptyEvidenceIndex
          @?= project relationCatalogue Evidence.emptyEvidenceIndex
    , testCase "the open chain and tally are derived from the projection, not written down" $ do
        let report = project relationCatalogue Evidence.emptyEvidenceIndex
        Evidence.openChain report @?= ["902.1", "903.1", "904.1", "905.1", "906.1"]
        Evidence.statusCounts report
          @?= StatusCounts {countDone = 1, countActive = 2, countPlanned = 1, countBlocked = 2}
        Evidence.renderStatusCounts (Evidence.statusCounts report)
          @?= "1 Done / 2 Active / 1 Planned / 2 Blocked"
    , testCase "an evidenced sprint with only an external obligation is never Done" $ do
        let catalogue = [evidencedOf 902 Started [] (ExternalContext "hardware" :| [])]
        statusOf (project catalogue allProvenIndex) "902.1" @?= Just Active
    , QuickCheck.testProperty "the relation invariants hold for arbitrary chains and evidence" $
        QuickCheck.forAll relationScenario $ \(catalogue, index) ->
          let report = project catalogue index
           in QuickCheck.conjoin
                [ QuickCheck.counterexample ("Done iff no open refusal: " <> show report) $
                    and
                      [ (projectionStatus p == Done) == null (Evidence.projectionOpen p)
                      | p <- reportProjections report
                      ]
                , QuickCheck.counterexample "Active and Planned are unproven and never awaiting" $
                    and
                      [ not (null (Evidence.projectionOpen p))
                          && not (any (isAwaiting . refusalReason) (Evidence.projectionOpen p))
                      | p <- reportProjections report
                      , projectionStatus p `elem` [Active, Planned]
                      ]
                , QuickCheck.counterexample "Blocked has an upstream or a not-started external cause" $
                    and
                      [ any (isAwaiting . refusalReason) open
                          || (any (isExternal . refusalReason) open && notStarted catalogue (projectionSprint p))
                      | p <- reportProjections report
                      , projectionStatus p == Blocked
                      , let open = Evidence.projectionOpen p
                      ]
                , QuickCheck.counterexample "a Done sprint has only Done upstream sprints" $
                    and
                      [ all (\upstream -> statusOf report upstream == Just Done) (upstreamOf catalogue (projectionSprint p))
                      | p <- reportProjections report
                      , projectionStatus p == Done
                      ]
                , QuickCheck.counterexample "legacy sprints are Done whatever the evidence is" $
                    and
                      [ projectionStatus p == Done
                      | p <- reportProjections report
                      , isLegacy (projectionBasis p)
                      ]
                , QuickCheck.counterexample "projection ignores catalogue order" $
                    project (reverse catalogue) index == report
                ]
    , QuickCheck.testProperty "unproven obligations never yield Done, whatever work state is declared" $
        QuickCheck.forAll (QuickCheck.elements [NotStarted, Started]) $ \work ->
          statusOf
            (project [evidencedOf 902 work [] (LaneJournal LinuxCPU :| [Aggregate])] Evidence.emptyEvidenceIndex)
            "902.1"
            /= Just Done
    ]
 where
  reasonsOf report sprint =
    maybe
      []
      (fmap refusalReason . Evidence.projectionOpen)
      (List.find ((== sprint) . projectionSprint) (reportProjections report))
  isExternal (External _) = True
  isExternal _ = False
  isAwaiting (AwaitsSprint _) = True
  isAwaiting _ = False
  isLegacy (BasisLegacy _) = True
  isLegacy _ = False
  notStarted catalogue sprint =
    or
      [ work == NotStarted
      | phase <- catalogue
      , entry <- entrySprints phase
      , entrySprintId entry == sprint
      , Evidence.Evidenced work _ _ <- [entryClosure entry]
      ]
  upstreamOf catalogue sprint =
    concat
      [ upstream
      | phase <- catalogue
      , entry <- entrySprints phase
      , entrySprintId entry == sprint
      , Evidence.Evidenced _ upstream _ <- [entryClosure entry]
      ]

-- | A random chain of up to six one-sprint phases and a random evidence index.
relationScenario :: QuickCheck.Gen ([PhaseEntry], EvidenceIndex)
relationScenario = do
  count <- QuickCheck.choose (1, 6)
  phases <- traverse phaseAt [0 .. count - 1]
  index <- randomIndex
  pure (phases, index)
 where
  phaseAt offset = do
    let number = 910 + offset
    legacy <- QuickCheck.frequency [(1, pure True), (4, pure False)]
    if legacy
      then pure (legacyOf number)
      else do
        work <- QuickCheck.elements [NotStarted, Started]
        upstream <-
          QuickCheck.sublistOf [tshow (910 + earlier) <> ".1" | earlier <- [0 .. offset - 1]]
        first <- randomObligation number
        rest <- QuickCheck.listOf (randomObligation number)
        pure (evidencedOf number work upstream (first :| take 2 rest))
  randomObligation number =
    QuickCheck.elements
      [ LaneJournal LinuxCPU
      , LaneJournal LinuxCUDA
      , Aggregate
      , NoPendingControls number
      , ExternalContext "hardware"
      , GateTranscript JitmlUnit LinuxCPU
      ]
  randomIndex = do
    lanes <- traverse (\lane -> (,) lane <$> randomDerived) allSubstrates
    aggregate <- randomDerived
    pending <-
      QuickCheck.sublistOf
        [entry | n <- [910 .. 915 :: Int], let entry = "Phase " <> tshow n <> ": pending"]
    transcript <- randomDerived
    pure
      Evidence.emptyEvidenceIndex
        { indexLanes = Map.fromList lanes
        , indexAggregate = Just aggregate
        , indexPendingControls = Just pending
        , indexTranscripts =
            Map.fromList [((JitmlUnit, LinuxCPU), TranscriptEvidence transcript Nothing)]
        }
  randomDerived =
    QuickCheck.elements
      [ proven "evidence"
      , unproven (Missing "file")
      , unproven (Stale "subject" (digestOf '1') (digestOf '2'))
      , unproven (Mismatched "detail")
      , unproven (FailedRun "detail")
      , unproven (Incomplete "detail")
      ]

-- ---------------------------------------------------------------------------
-- Each Unmet reason, produced by the code that produces it, refuses closure
-- ---------------------------------------------------------------------------

mkRecord
  :: ValidationGate
  -> Substrate
  -> Text
  -> SourceStamp
  -> RecordEvidence
  -> Record.ValidationRecord
mkRecord gate substrate command stamp evidence =
  case Record.mkValidationRecord gate substrate command (digestOf 'e') stamp evidence of
    Left err -> error ("fixture record rejected: " <> show err)
    Right record -> record

passedEvidence :: RecordEvidence
passedEvidence = EvidencePassed (digestOf '5') (digestOf '6')

standingCommand :: ValidationGate -> Substrate -> Text
standingCommand gate substrate =
  "/root/.ghcup/bin/cabal " <> Loader.standingCommandTail gate substrate

-- | The judgement of an admitted record for @(gate, substrate)@.
judgedAdmitted
  :: ValidationGate
  -> Substrate
  -> Record.ValidationRecord
  -> TranscriptEvidence
judgedAdmitted gate substrate record =
  Loader.judgeTranscriptFile
    gate
    substrate
    "DEVELOPMENT_PLAN/attestations/validation/fixture.json"
    (Loader.TranscriptAdmitted (digestOf 'd') record)

transcriptIndex :: ValidationGate -> Substrate -> TranscriptEvidence -> EvidenceIndex
transcriptIndex gate substrate evidence =
  Evidence.emptyEvidenceIndex
    { indexTranscripts = Map.singleton (gate, substrate) evidence
    , indexCurrentSource = Right fixtureStamp
    }

goodRecord :: Record.ValidationRecord
goodRecord =
  mkRecord JitmlUnit LinuxCPU (standingCommand JitmlUnit LinuxCPU) fixtureStamp passedEvidence

-- | The judgement of a passing end-to-end record that recorded @command@.
judgedE2e :: Text -> TranscriptEvidence
judgedE2e command =
  judgedAdmitted JitmlE2e LinuxCPU (mkRecord JitmlE2e LinuxCPU command fixtureStamp passedEvidence)

unmetConstructorTests :: TestTree
unmetConstructorTests =
  testGroup
    "every Unmet reason refuses closure claims"
    [ reasonCase
        "Missing: no committed transcript"
        (GateTranscript JitmlUnit LinuxCPU)
        Evidence.emptyEvidenceIndex
        (\case Missing _ -> True; _ -> False)
        (Just (transcriptIndex JitmlUnit LinuxCPU (judgedAdmitted JitmlUnit LinuxCPU goodRecord)))
    , reasonCase
        "Stale: a standing transcript recorded for another source tree"
        (StandingGate JitmlUnit LinuxCPU)
        ( transcriptIndex
            JitmlUnit
            LinuxCPU
            (judgedAdmitted JitmlUnit LinuxCPU goodRecord) {transcriptSource = Just otherStamp}
        )
        (\case Stale {} -> True; _ -> False)
        (Just (transcriptIndex JitmlUnit LinuxCPU (judgedAdmitted JitmlUnit LinuxCPU goodRecord)))
    , reasonCase
        "Mismatched: a transcript of a focused run is not the standing gate"
        (GateTranscript JitmlUnit LinuxCPU)
        ( transcriptIndex
            JitmlUnit
            LinuxCPU
            ( judgedAdmitted
                JitmlUnit
                LinuxCPU
                ( mkRecord
                    JitmlUnit
                    LinuxCPU
                    "/root/.ghcup/bin/cabal test jitml-unit --test-options '-p Journal'"
                    fixtureStamp
                    passedEvidence
                )
            )
        )
        (\case Mismatched _ -> True; _ -> False)
        (Just (transcriptIndex JitmlUnit LinuxCPU (judgedAdmitted JitmlUnit LinuxCPU goodRecord)))
    , reasonCase
        "FailedRun: a transcript that records a failing run"
        (GateTranscript JitmlUnit LinuxCPU)
        ( transcriptIndex
            JitmlUnit
            LinuxCPU
            ( judgedAdmitted
                JitmlUnit
                LinuxCPU
                ( mkRecord
                    JitmlUnit
                    LinuxCPU
                    (standingCommand JitmlUnit LinuxCPU)
                    fixtureStamp
                    ( EvidenceFailed
                        FailedEvidence
                          { failedExitCode = Just 1
                          , failedStdout = Just "1 out of 900 tests failed\n"
                          , failedStderr = Just ""
                          , failedException = Nothing
                          }
                    )
                )
            )
        )
        (\case FailedRun _ -> True; _ -> False)
        (Just (transcriptIndex JitmlUnit LinuxCPU (judgedAdmitted JitmlUnit LinuxCPU goodRecord)))
    , reasonCase
        "Incomplete: a transcript of a gate that never ran"
        (GateTranscript JitmlUnit LinuxCPU)
        ( transcriptIndex
            JitmlUnit
            LinuxCPU
            ( judgedAdmitted
                JitmlUnit
                LinuxCPU
                ( mkRecord
                    JitmlUnit
                    LinuxCPU
                    (standingCommand JitmlUnit LinuxCPU)
                    fixtureStamp
                    (EvidenceNotRun "jitml-unit" "an earlier stanza failed")
                )
            )
        )
        (\case Incomplete _ -> True; _ -> False)
        (Just (transcriptIndex JitmlUnit LinuxCPU (judgedAdmitted JitmlUnit LinuxCPU goodRecord)))
    , reasonCase
        "Incomplete: a production control is still pending for the phase"
        (NoPendingControls 901)
        Evidence.emptyEvidenceIndex {indexPendingControls = Just ["Phase 901: invalid fixtures"]}
        (\case Incomplete _ -> True; _ -> False)
        (Just Evidence.emptyEvidenceIndex {indexPendingControls = Just ["Phase 902: someone else's"]})
    , reasonCase
        "External: a prerequisite outside the repository is open"
        (ExternalContext "Apple Silicon execution context")
        Evidence.emptyEvidenceIndex
        (\case External _ -> True; _ -> False)
        Nothing
    , testCase "AwaitsSprint: an unproven upstream sprint refuses closure and blocks its dependent" $ do
        let catalogue =
              [ evidencedOf 901 NotStarted [] (ExternalContext "hardware" :| [])
              , evidencedOf 902 NotStarted ["901.1"] (LaneJournal LinuxCUDA :| [])
              ]
            report =
              project catalogue Evidence.emptyEvidenceIndex {indexLanes = Map.singleton LinuxCUDA (proven "lane")}
        statusOf report "902.1" @?= Just Blocked
        assertBool
          "the verdict names the awaited sprint"
          (AwaitsSprint "901.1" `elem` refusalReasons (reportVerdict report))
        assertClaimRefused (reportVerdict report)
    ]
 where
  reasonCase name obligation index matches positive =
    testCase name $ do
      case Evidence.observeObligation index obligation of
        Proven _ -> assertFailure "the obligation was proven, so the fixture proves nothing"
        Unproven reasons ->
          assertBool
            ("the first reason has the expected constructor: " <> show reasons)
            (matches (NonEmpty.head reasons))
      let verdict = verdictFor obligation index
      assertBool
        "the verdict carries a refusal with that constructor"
        (any matches (refusalReasons verdict))
      assertClaimRefused verdict
      -- The positive control shows the refusal is caused by the evidence, not by
      -- the shape of the fixture: with the evidence in order the same claim passes.
      forM_ positive $ \provenIndex -> do
        case Evidence.observeObligation provenIndex obligation of
          Proven _ -> pure ()
          Unproven reasons -> assertFailure ("the positive control is still unproven: " <> show reasons)
        Evidence.closureOutcome (verdictFor obligation provenIndex) @?= Right []
        DocsCheck.checkDocumentClosureClaimsText
          (verdictFor obligation provenIndex)
          "doc.md"
          productionReadyClaim
          @?= []

-- | Freshness of a standing transcript, judged by the model and not by the loader.
standingFreshnessTests :: TestTree
standingFreshnessTests =
  testGroup
    "standing gate freshness"
    [ testCase "a transcript recorded for the current tree is proven" $
        case Evidence.observeObligation
          (transcriptIndex JitmlUnit LinuxCPU (judgedAdmitted JitmlUnit LinuxCPU goodRecord))
          (StandingGate JitmlUnit LinuxCPU) of
          Proven _ -> pure ()
          Unproven reasons -> assertFailure (show reasons)
    , testCase "staleness names what the current tree requires and what the record carries" $
        Evidence.observeObligation
          ( transcriptIndex
              JitmlUnit
              LinuxCPU
              (judgedAdmitted JitmlUnit LinuxCPU goodRecord) {transcriptSource = Just otherStamp}
          )
          (StandingGate JitmlUnit LinuxCPU)
          @?= unproven (Stale "source tree" (stampSha256 fixtureStamp) (stampSha256 otherStamp))
    , testCase "a record made under another digest algorithm is never compared, it is mismatched" $
        case Evidence.observeObligation
          ( transcriptIndex
              JitmlUnit
              LinuxCPU
              (judgedAdmitted JitmlUnit LinuxCPU goodRecord)
                { transcriptSource = Just fixtureStamp {stampAlgorithm = 2}
                }
          )
          (StandingGate JitmlUnit LinuxCPU) of
          Unproven (Mismatched detail :| []) ->
            assertBool "names the algorithms" ("algorithm 2" `Text.isInfixOf` detail)
          other -> assertFailure ("expected Mismatched, got " <> show other)
    , testCase "an unavailable current digest or a stampless record cannot prove freshness" $ do
        let index = transcriptIndex JitmlUnit LinuxCPU (judgedAdmitted JitmlUnit LinuxCPU goodRecord)
        case Evidence.observeObligation
          index {indexCurrentSource = Left "no code roots"}
          (StandingGate JitmlUnit LinuxCPU) of
          Unproven (Mismatched detail :| []) ->
            assertBool "says why" ("no code roots" `Text.isInfixOf` detail)
          other -> assertFailure ("expected Mismatched, got " <> show other)
        case Evidence.observeObligation
          ( transcriptIndex
              JitmlUnit
              LinuxCPU
              (judgedAdmitted JitmlUnit LinuxCPU goodRecord) {transcriptSource = Nothing}
          )
          (StandingGate JitmlUnit LinuxCPU) of
          Unproven (Mismatched _ :| []) -> pure ()
          other -> assertFailure ("expected Mismatched, got " <> show other)
    , testCase "an unproven judgement passes through unchanged whatever the source says" $ do
        let failedRecord =
              mkRecord
                JitmlUnit
                LinuxCPU
                (standingCommand JitmlUnit LinuxCPU)
                otherStamp
                (EvidenceNotRun "jitml-unit" "blocked")
            index = transcriptIndex JitmlUnit LinuxCPU (judgedAdmitted JitmlUnit LinuxCPU failedRecord)
        Evidence.observeObligation index (StandingGate JitmlUnit LinuxCPU)
          @?= Evidence.observeObligation index (GateTranscript JitmlUnit LinuxCPU)
    , testCase "a historical transcript is not compared with the tree, however old it is" $
        Evidence.observeObligation
          ( (transcriptIndex JitmlUnit LinuxCPU (judgedAdmitted JitmlUnit LinuxCPU goodRecord))
              { indexCurrentSource = Right otherStamp
              }
          )
          (GateTranscript JitmlUnit LinuxCPU)
          @?= proven "DEVELOPMENT_PLAN/attestations/validation/fixture.json"
          `orDigest` digestOf 'd'
    ]
 where
  -- The judgement carries the file digest as its pointer.
  orDigest _ digest =
    Proven
      ( EvidenceRef
          { evidenceSubject = "DEVELOPMENT_PLAN/attestations/validation/fixture.json"
          , evidenceDigest = Just digest
          }
          :| []
      )

productionReadyClaim :: Text
productionReadyClaim = "This product is production ready."

-- | A closure claim is rejected under the verdict, with the tell-tale key and a
-- reason that names the verdict and the catalogue's phase range.
assertClaimRefused :: ClosureVerdict -> Assertion
assertClaimRefused verdict =
  case DocsCheck.checkDocumentClosureClaimsText verdict "doc.md" productionReadyClaim of
    [drift] -> do
      DocsCheck.driftKey drift @?= "closure-claim.production-ready"
      assertBool
        ("the drift reason names the verdict: " <> Text.unpack (DocsCheck.driftReason drift))
        ( "closure is refused" `Text.isInfixOf` DocsCheck.driftReason drift
            && "Phases 220-289" `Text.isInfixOf` DocsCheck.driftReason drift
        )
    other -> assertFailure ("expected exactly one closure-claim drift, got " <> show other)

closureGuardTests :: TestTree
closureGuardTests =
  testGroup
    "closure guard"
    [ testCase "with no evidence the real catalogue refuses closure and rejects a Done-sounding claim" $ do
        let report = PhaseStatus.projectProductStatus Evidence.emptyEvidenceIndex
        assertBool "closure is refused" (isRefusedVerdict (reportVerdict report))
        let claim = "The no-caveat product complete status is current."
            drifts = DocsCheck.checkDocumentClosureClaimsText (reportVerdict report) "docs.md" claim
        fmap DocsCheck.driftKey drifts @?= ["closure-claim.no-caveat-product-complete"]
    , testCase "an external obligation keeps the real catalogue open however much else is proven" $ do
        let report = PhaseStatus.projectProductStatus allProvenIndex
        Evidence.statusCounts report
          @?= StatusCounts {countDone = 63, countActive = 1, countPlanned = 0, countBlocked = 6}
        assertBool "closure is refused" (isRefusedVerdict (reportVerdict report))
        assertBool
          "every remaining refusal is an external prerequisite or a sprint awaiting one"
          ( all
              (\refusal -> isExternalReason (refusalReason refusal) || isAwaitingReason (refusalReason refusal))
              (refusalsOf (reportVerdict report))
          )
    , testCase
        "once its external obligations are deleted and the rest is proven the catalogue closes and discloses its legacy sprints"
        $ do
          let report = projectClosable allProvenIndex
          Evidence.statusCounts report
            @?= StatusCounts {countDone = 70, countActive = 0, countPlanned = 0, countBlocked = 0}
          Evidence.closureOutcome (reportVerdict report) @?= Right (Evidence.reportLegacy report)
          length (Evidence.reportLegacy report) @?= 63
          DocsCheck.checkDocumentClosureClaimsText (reportVerdict report) "docs.md" productionReadyClaim
            @?= []
          assertBool
            "the registry view reports every product phase Done"
            (PhaseStatus.productPhasesDone (PhaseStatus.productPhaseStatuses report))
    , testCase "one stale standing transcript is enough to refuse an otherwise closed catalogue" $ do
        let stale =
              allProvenIndex
                { indexTranscripts =
                    Map.insert
                      (JitmlUnit, LinuxCPU)
                      (TranscriptEvidence (proven "transcript") (Just otherStamp))
                      (indexTranscripts allProvenIndex)
                }
            report = projectClosable stale
        assertBool "closure is refused" (isRefusedVerdict (reportVerdict report))
        assertBool
          "the refusal is a standing one and stale"
          ( any
              (\refusal -> refusalScope refusal == StandingScope && isStale (refusalReason refusal))
              (refusalsOf (reportVerdict report))
          )
        -- Every sprint is still Done: staleness of a standing gate does not
        -- demote a sprint, only the closure claim.
        Evidence.statusCounts report
          @?= StatusCounts {countDone = 70, countActive = 0, countPlanned = 0, countBlocked = 0}
    , testCase "a non-empty Pending Removal ledger refuses an otherwise closed catalogue" $ do
        let report =
              projectClosable
                allProvenIndex {indexLedger = Just (unproven (Incomplete "1 row remains"))}
        assertBool "closure is refused" (isRefusedVerdict (reportVerdict report))
        assertBool
          "the refusal names the ledger"
          (any ((== LedgerClear) . refusalObligation) (refusalsOf (reportVerdict report)))
    , testCase "closure-claim scan exempts historical and prohibition blocks even when refused" $ do
        let historical =
              Text.unlines
                [ "Historical 2026-06-30 evidence:"
                , "The no-caveat product complete record is retained as history."
                ]
            prohibition =
              "No future closure may claim \"all phases done\" until evidence is current."
        DocsCheck.checkDocumentClosureClaimsText refusedVerdictFixture "docs.md" historical @?= []
        DocsCheck.checkDocumentClosureClaimsText refusedVerdictFixture "docs.md" prohibition @?= []
    , testCase "the verdict and report constructors are private to the projection module" $ do
        source <- Text.IO.readFile "src/JitML/Product/StatusEvidence.hs"
        -- The export list runs from the module header to its `where`. A closed
        -- verdict is evidence that every obligation was observed proven, so no caller
        -- may be able to write one down.
        let exportList =
              Text.unlines
                ( takeWhile
                    (/= "where")
                    (dropWhile (not . ("module JitML.Product.StatusEvidence" `Text.isPrefixOf`)) (Text.lines source))
                )
        assertBool "the export list was found" ("closureOutcome" `Text.isInfixOf` exportList)
        forM_ ["ClosureVerdict (", "StatusReport (", "Closed", "Refused"] $ \exposed ->
          assertBool
            (Text.unpack exposed <> " must not appear in the export list")
            (not (exposed `Text.isInfixOf` exportList))
    , testCase "a Closed verdict permits claims and a Refused verdict rejects them" $ do
        DocsCheck.checkDocumentClosureClaimsText closedVerdictFixture "docs.md" productionReadyClaim @?= []
        length
          (DocsCheck.checkDocumentClosureClaimsText refusedVerdictFixture "docs.md" productionReadyClaim)
          @?= 1
    ]
 where
  isStale (Stale {}) = True
  isStale _ = False
  isExternalReason (External _) = True
  isExternalReason _ = False
  isAwaitingReason (AwaitsSprint _) = True
  isAwaitingReason _ = False

-- ---------------------------------------------------------------------------
-- Phase document drift: header versus proof, and the structure rules
-- ---------------------------------------------------------------------------

-- | The parts of a phase document the rules read.
data Doc = Doc
  { docPhase :: Int
  , docTitle :: Text
  , docSprint :: Text
  , docStatus :: Text
  , docHeading :: Text
  , docPhaseState :: Text
  , docBlockedBy :: Maybe Text
  , docRemaining :: Maybe [Text]
  , docValidation :: [Text]
  , docSections :: [Text]
  }

baseDoc :: Doc
baseDoc =
  Doc
    { docPhase = 901
    , docTitle = "Fixture"
    , docSprint = "901.1"
    , docStatus = "Blocked"
    , docHeading = "Blocked"
    , docPhaseState = "Blocked"
    , docBlockedBy = Just "**Blocked by**: Sprint `900.1`"
    , docRemaining = Just ["- Blocked until Sprint `900.1` is Done."]
    , docValidation =
        [ "```bash"
        , "docker compose run --rm jitml jitml test jitml-unit --linux-cpu"
        , "```"
        ]
    , docSections = []
    }

renderDoc :: Doc -> Text
renderDoc doc =
  Text.unlines $
    [ "# Phase " <> tshow (docPhase doc) <> ": " <> docTitle doc
    , ""
    , "**Status**: Authoritative source"
    , ""
    , "## Phase State"
    , ""
    , "* **" <> docPhaseState doc <> "**."
    , ""
    , "## Sprint " <> docSprint doc <> ": " <> docTitle doc <> " [* " <> docHeading doc <> "]"
    , ""
    , "**Status**: " <> docStatus doc
    ]
      <> maybe [] pure (docBlockedBy doc)
      <> ["", "### Objective", "", "Fixture objective.", "", "### Validation", ""]
      <> docValidation doc
      <> concatMap (\section -> ["", "### " <> section, "", "Text."]) (docSections doc)
      <> maybe [] (\remaining -> ["", "### Remaining Work", ""] <> remaining) (docRemaining doc)
      <> ["", "## Documentation Requirements", "", "None."]

-- | A doc that agrees with the status: every scenario's baseline.
docFor :: SprintStatus -> Doc
docFor status =
  case status of
    Blocked -> baseDoc
    Active ->
      baseDoc
        { docStatus = "Active"
        , docHeading = "Active"
        , docPhaseState = "Active"
        , docBlockedBy = Nothing
        , docRemaining = Just ["- Land the lane journal."]
        }
    Planned ->
      baseDoc
        { docStatus = "Planned"
        , docHeading = "Planned"
        , docPhaseState = "Planned"
        , docBlockedBy = Nothing
        , docRemaining = Nothing
        }
    Done ->
      baseDoc
        { docStatus = "Done"
        , docHeading = "Done"
        , docPhaseState = "Done"
        , docBlockedBy = Nothing
        , docRemaining = Nothing
        , docSections = ["Closure Evidence"]
        }

-- | What sprint 901.1 owns in every scenario: a lane journal and the transcript of
-- the gate its fixture document's Validation block runs.
scenarioObligations :: NonEmpty Obligation
scenarioObligations = LaneJournal LinuxCPU :| [GateTranscript JitmlUnit LinuxCPU]

-- | Both obligations proven.
scenarioProvenIndex :: EvidenceIndex
scenarioProvenIndex =
  Evidence.emptyEvidenceIndex
    { indexLanes = Map.singleton LinuxCPU (proven "lane")
    , indexTranscripts =
        Map.singleton (JitmlUnit, LinuxCPU) (TranscriptEvidence (proven "transcript") Nothing)
    }

-- | Sprint 901.1 under each status the relation can derive.
scenarioFor :: SprintStatus -> (StatusReport, SprintProjection)
scenarioFor status = (report, projection)
 where
  upstream = evidencedOf 900 NotStarted [] (ExternalContext "hardware" :| [])
  report =
    case status of
      Blocked ->
        project
          [upstream, evidencedOf 901 NotStarted ["900.1"] scenarioObligations]
          scenarioProvenIndex
      Active ->
        project [evidencedOf 901 Started [] scenarioObligations] Evidence.emptyEvidenceIndex
      Planned ->
        project [evidencedOf 901 NotStarted [] scenarioObligations] Evidence.emptyEvidenceIndex
      Done ->
        project [evidencedOf 901 Started [] scenarioObligations] scenarioProvenIndex
  projection =
    case List.find ((== "901.1") . projectionSprint) (reportProjections report) of
      Just found -> found
      Nothing -> error "scenario has no sprint 901.1"

issuesFor :: SprintStatus -> Doc -> [PlanDoc.PlanIssue]
issuesFor status doc = PlanDoc.planDocumentIssues [snd (scenarioFor status)] (renderDoc doc)

issueKeys :: [PlanDoc.PlanIssue] -> [Text]
issueKeys = fmap PlanDoc.issueKey

planDocTests :: TestTree
planDocTests =
  testGroup
    "phase documents against the projection"
    [ testGroup
        "a document that agrees with the projection has no issue"
        [ testCase (show status) (issueKeys (issuesFor status (docFor status)) @?= [])
        | status <- [Blocked, Active, Planned, Done]
        ]
    , testCase "scenarios derive the statuses they are named for" $
        forM_ [Blocked, Active, Planned, Done] $ \status ->
          projectionStatus (snd (scenarioFor status)) @?= status
    , testCase "header says Done without proof" $ do
        let doc = (docFor Done) {docSections = []}
            issues = issuesFor Blocked doc
        issueKeys issues @?= ["status-projection.901.1"]
        assertBool
          "the issue says Done without proof and lists the unmet obligation"
          ( all
              (\issue -> "Done without proof" `Text.isInfixOf` PlanDoc.issueMessage issue)
              issues
              && any (\issue -> "awaits sprint 900.1" `Text.isInfixOf` PlanDoc.issueMessage issue) issues
          )
    , testCase "proof exceeds a non-Done header" $ do
        let issues = issuesFor Done (docFor Active)
        issueKeys issues @?= ["status-projection.901.1"]
        assertBool
          "the issue says the evidence proves every obligation"
          (all (\issue -> "proves every obligation" `Text.isInfixOf` PlanDoc.issueMessage issue) issues)
    , testCase "docs check reports a lying header against the phase document's own path" $ do
        let (report, _) = scenarioFor Blocked
            phase = evidencedOf 901 NotStarted ["900.1"] scenarioObligations
            path = entryPhaseDocument phase
        -- The document says Done; the evidence derives Blocked.
        case DocsCheck.statusProjectionDrifts report [(phase, Just (renderDoc (docFor Done)))] of
          [drift] -> do
            DocsCheck.driftPath drift @?= path
            DocsCheck.driftKey drift @?= "status-projection.901.1"
            assertBool
              "the drift says Done without proof"
              ("Done without proof" `Text.isInfixOf` DocsCheck.driftReason drift)
            assertBool
              "the remedy points at docs status"
              ("jitml docs status" `Text.isInfixOf` DocsCheck.docsDriftRemedy drift)
          other -> assertFailure ("expected exactly one drift, got " <> show other)
        -- The same document agreeing with the evidence is clean.
        DocsCheck.statusProjectionDrifts report [(phase, Just (renderDoc (docFor Blocked)))] @?= []
        -- A missing phase document is a drift, not a skipped check.
        case DocsCheck.statusProjectionDrifts report [(phase, Nothing)] of
          [drift] -> do
            DocsCheck.driftPath drift @?= path
            DocsCheck.driftKey drift @?= "status-projection.901.1"
          other -> assertFailure ("expected exactly one drift, got " <> show other)
    , testCase "a structure violation is reported with its own key and remedy" $ do
        let (report, _) = scenarioFor Blocked
            phase = evidencedOf 901 NotStarted ["900.1"] scenarioObligations
        case DocsCheck.statusProjectionDrifts report [(phase, Just (renderDoc baseDoc {docBlockedBy = Nothing}))] of
          [statusDrift, structureDrift] -> do
            DocsCheck.driftKey statusDrift @?= "status-projection.901.1"
            DocsCheck.driftKey structureDrift @?= "plan-structure.901.1.blocked-by-missing"
            assertBool
              "the structure remedy cites the standards rules"
              ("rules C, H, and M" `Text.isInfixOf` DocsCheck.docsDriftRemedy structureDrift)
          other -> assertFailure ("expected two drifts, got " <> show other)
    , testCase "a header that differs from the derived status names both" $ do
        let issues = issuesFor Active (docFor Planned)
        issueKeys issues @?= ["status-projection.901.1"]
        assertBool
          "the issue names the header and the derived status"
          ( all
              ( \issue ->
                  "says Planned" `Text.isInfixOf` PlanDoc.issueMessage issue
                    && "derives Active" `Text.isInfixOf` PlanDoc.issueMessage issue
              )
              issues
          )
    , testCase "a Blocked sprint must name every unproven upstream sprint" $ do
        let doc = baseDoc {docBlockedBy = Just "**Blocked by**: an external prerequisite"}
        issueKeys (issuesFor Blocked doc) @?= ["status-projection.901.1"]
        assertBool
          "the issue names the omitted upstream sprint"
          ( any
              (\issue -> "does not name upstream sprint 900.1" `Text.isInfixOf` PlanDoc.issueMessage issue)
              (issuesFor Blocked doc)
          )
    , testCase "a Blocked sprint without a Blocked by line" $
        issueKeys (issuesFor Blocked baseDoc {docBlockedBy = Nothing})
          @?= ["status-projection.901.1", "plan-structure.901.1.blocked-by-missing"]
    , testCase "a Planned or Done sprint may declare no blocker" $ do
        issueKeys
          (issuesFor Planned (docFor Planned) {docBlockedBy = Just "**Blocked by**: Sprint `900.1`"})
          @?= ["plan-structure.901.1.blockers-declared"]
        issueKeys (issuesFor Done (docFor Done) {docBlockedBy = Just "**Blocked by**: Sprint `900.1`"})
          @?= ["plan-structure.901.1.blockers-declared"]
    , testCase "an Active sprint needs a Remaining Work block that is not None." $ do
        issueKeys (issuesFor Active (docFor Active) {docRemaining = Nothing})
          @?= ["plan-structure.901.1.remaining-work-missing"]
        issueKeys (issuesFor Active (docFor Active) {docRemaining = Just ["None."]})
          @?= ["plan-structure.901.1.remaining-work-missing"]
    , testCase "a Blocked-by edge must point at a strictly lower sprint" $ do
        issueKeys
          (issuesFor Blocked baseDoc {docBlockedBy = Just "**Blocked by**: Sprint `900.1`, Sprint `902.1`"})
          @?= ["plan-structure.901.1.backward-edge"]
        issueKeys
          (issuesFor Blocked baseDoc {docBlockedBy = Just "**Blocked by**: Sprint `900.1`, Sprint `901.1`"})
          @?= ["plan-structure.901.1.backward-edge"]
    , testCase "a Blocked-by line may not name a sprint the catalogue does not list as upstream" $ do
        issueKeys
          (issuesFor Blocked baseDoc {docBlockedBy = Just "**Blocked by**: Sprint `900.1`, Sprint `899.1`"})
          @?= ["plan-structure.901.1.undeclared-edge"]
        -- An Active sprint may carry a Blocked-by line, and the same rule applies.
        issueKeys
          (issuesFor Active (docFor Active) {docBlockedBy = Just "**Blocked by**: Sprint `899.1`"})
          @?= ["plan-structure.901.1.undeclared-edge"]
        -- Only sprint ids are edges: a version number in prose is not one.
        issueKeys
          (issuesFor Blocked baseDoc {docBlockedBy = Just "**Blocked by**: Sprint `900.1` and GHC 9.12.4"})
          @?= []
        -- A backward edge is reported once, not also as undeclared.
        issueKeys
          (issuesFor Blocked baseDoc {docBlockedBy = Just "**Blocked by**: Sprint `900.1`, Sprint `902.1`"})
          @?= ["plan-structure.901.1.backward-edge"]
        -- A Done sprint that declares any blocker is reported once, as declaring one.
        case reportProjections (project [legacyOf 901] Evidence.emptyEvidenceIndex) of
          [legacy] ->
            issueKeys
              ( PlanDoc.planDocumentIssues
                  [legacy]
                  (renderDoc (docFor Done) {docBlockedBy = Just "**Blocked by**: Sprint `899.1`"})
              )
              @?= ["plan-structure.901.1.blockers-declared"]
          other -> assertFailure ("expected one projection, got " <> show other)
    , testCase "a sprint needs a concrete validation gate and never both accelerators" $ do
        issueKeys (issuesFor Blocked baseDoc {docValidation = []})
          @?= ["plan-structure.901.1.validation-gate"]
        issueKeys (issuesFor Blocked baseDoc {docValidation = ["Run the checks."]})
          @?= ["plan-structure.901.1.validation-gate"]
        issueKeys
          ( issuesFor
              Blocked
              baseDoc
                { docValidation =
                    [ "./bootstrap/linux-cuda.sh test"
                    , "./bootstrap/apple-silicon.sh test"
                    ]
                }
          )
          @?= ["plan-structure.901.1.dual-accelerator"]
    , testCase "validation lines name the gate and substrate they run" $ do
        PlanDoc.validationGatesNamed "docker compose run --rm jitml jitml test jitml-unit --linux-cpu"
          @?= [(JitmlUnit, LinuxCPU)]
        PlanDoc.validationGatesNamed
          "docker compose run --rm jitml-cuda jitml test jitml-backends --linux-cuda"
          @?= [(JitmlBackends, LinuxCUDA)]
        PlanDoc.validationGatesNamed "jitml test jitml-e2e --apple-silicon --linux-cpu"
          @?= [(JitmlE2e, AppleSilicon), (JitmlE2e, LinuxCPU)]
        -- Nothing is named when the stanza is `all`, no substrate is selected, or the
        -- line runs no gate, so the rule that reads this can be missed but never tripped.
        PlanDoc.validationGatesNamed "docker compose run --rm jitml jitml test all --linux-cpu" @?= []
        PlanDoc.validationGatesNamed "jitml test jitml-unit" @?= []
        PlanDoc.validationGatesNamed "docker compose run --rm jitml jitml docs check" @?= []
        PlanDoc.validationGatesNamed "./bootstrap/linux-cpu.sh test" @?= []
    , testCase "the Validation block's gates are the sprint's gate-transcript obligations" $ do
        -- The baseline document runs jitml-unit on linux-cpu, which the sprint owns.
        issueKeys (issuesFor Blocked baseDoc) @?= []
        -- A gate the sprint does not own is reported with the gate and substrate named.
        case issuesFor
          Blocked
          baseDoc {docValidation = ["docker compose run --rm jitml jitml test jitml-integration --linux-cpu"]} of
          [issue] -> do
            PlanDoc.issueKey issue @?= "plan-structure.901.1.validation-obligation"
            assertBool
              "the issue names the gate and the substrate"
              ("jitml-integration on linux-cpu" `Text.isInfixOf` PlanDoc.issueMessage issue)
          other -> assertFailure ("expected one issue, got " <> show other)
        -- The same gate on another substrate is another obligation.
        issueKeys
          ( issuesFor
              Blocked
              baseDoc {docValidation = ["docker compose run --rm jitml-cuda jitml test jitml-unit --linux-cuda"]}
          )
          @?= ["plan-structure.901.1.validation-obligation"]
        -- A standing gate satisfies the document just as a transcript does.
        case reportProjections
          ( project
              [evidencedOf 901 Started [] (StandingGate JitmlUnit LinuxCPU :| [])]
              Evidence.emptyEvidenceIndex
          ) of
          [standing] -> issueKeys (PlanDoc.planDocumentIssues [standing] (renderDoc (docFor Active))) @?= []
          other -> assertFailure ("expected one projection, got " <> show other)
        -- A legacy sprint owes no transcript, so its document is not held to one.
        case reportProjections (project [legacyOf 901] Evidence.emptyEvidenceIndex) of
          [legacy] ->
            issueKeys
              ( PlanDoc.planDocumentIssues
                  [legacy]
                  ( renderDoc
                      (docFor Done)
                        { docValidation = ["docker compose run --rm jitml jitml test jitml-integration --linux-cpu"]
                        }
                  )
              )
              @?= []
          other -> assertFailure ("expected one projection, got " <> show other)
    , testCase "the heading and Phase State must agree with the Status line" $ do
        issueKeys (issuesFor Blocked baseDoc {docHeading = "Active"})
          @?= ["plan-structure.901.1.heading-status"]
        issueKeys (issuesFor Blocked baseDoc {docPhaseState = "Done"})
          @?= ["plan-structure.901.1.phase-state"]
    , testCase "an unrecognised or missing Status line is reported" $ do
        issueKeys (issuesFor Blocked baseDoc {docStatus = "Authoritative source"})
          @?= ["plan-structure.901.1.status-line"]
        let withoutStatus =
              Text.unlines
                (filter (not . ("**Status**: Blocked" `Text.isPrefixOf`)) (Text.lines (renderDoc baseDoc)))
        issueKeys (PlanDoc.planDocumentIssues [snd (scenarioFor Blocked)] withoutStatus)
          @?= ["plan-structure.901.1.status-line"]
    , testCase "a sprint the document lacks and a block the catalogue lacks are both reported" $ do
        issueKeys (PlanDoc.planDocumentIssues [snd (scenarioFor Blocked)] "# nothing here\n")
          @?= ["plan-structure.901.1.sprint-missing"]
        issueKeys (PlanDoc.planDocumentIssues [] (renderDoc baseDoc))
          @?= ["plan-structure.901.1.sprint-unregistered"]
    , testCase "a legacy sprint must cite a closure section its block contains" $ do
        let report = project [legacyOf 901] Evidence.emptyEvidenceIndex
            done = docFor Done
        case reportProjections report of
          [projection] -> do
            issueKeys (PlanDoc.planDocumentIssues [projection] (renderDoc done)) @?= []
            issueKeys (PlanDoc.planDocumentIssues [projection] (renderDoc done {docSections = []}))
              @?= ["plan-structure.901.1.legacy-citation"]
          other -> assertFailure ("expected one projection, got " <> show other)
    , testCase "sprint block parsing matches the historical test-local parser" $ do
        let content = renderDoc (docFor Active)
        PlanDoc.parsePlanSprintStatuses "doc.md" content @?= Right [("901.1", Active)]
        PlanDoc.parsePlanSprintStatuses "doc.md" (renderDoc baseDoc {docStatus = "Half done"})
          @?= Left "doc.md: unknown sprint status Half done for 901.1"
        PlanDoc.parseSprintHeader "## Sprint 23.2: Name [Done]" @?= Just "23.2"
        PlanDoc.parseSprintHeader "## Sprints" @?= Nothing
        PlanDoc.extractDottedNumbers "Sprint `278.1` and 9.12.4 and Phase 3" @?= ["278.1", "9.12.4"]
        PlanDoc.compareDottedId "9.1" "10.1" @?= LT
        PlanDoc.compareDottedId "23.2" "23.2" @?= EQ
        PlanDoc.parsePhaseStateStatus (renderDoc (docFor Planned)) @?= Just Planned
        PlanDoc.parsePhaseStateStatus "# no phase state here\n" @?= Nothing
    ]

-- ---------------------------------------------------------------------------
-- The catalogue and its frozen legacy class
-- ---------------------------------------------------------------------------

-- | The legacy-attested class as it stood when Phase 288 froze it, written here
-- independently of the catalogue so growing the class means editing two files.
frozenLegacyLiteral :: [Text]
frozenLegacyLiteral =
  [ tshow phase <> ".1"
  | phase <- [220 .. 289 :: Int]
  , phase `notElem` [278, 280, 281, 282, 285, 288, 289]
  ]

-- | What every evidenced sprint owes as this phase froze it: the declared work
-- state, the upstream sprints, and the obligations.
pinnedEvidencedSprints :: [(Text, WorkState, [Text], [Obligation])]
pinnedEvidencedSprints =
  [
    ( "278.1"
    , Started
    , []
    ,
      [ LaneJournal LinuxCPU
      , LaneJournal LinuxCUDA
      , LaneJournal AppleSilicon
      , Aggregate
      , GateTranscript JitmlUnit LinuxCPU
      , ExternalContext "Apple Silicon execution context"
      ]
    )
  ,
    ( "280.1"
    , Started
    , ["278.1"]
    ,
      [ NoPendingControls 280
      , GateTranscript JitmlNegativeControls LinuxCPU
      , GateTranscript JitmlUnit LinuxCPU
      ]
    )
  ,
    ( "281.1"
    , Started
    , ["280.1"]
    ,
      [ NoPendingControls 281
      , GateTranscript JitmlNegativeControls LinuxCPU
      , GateTranscript JitmlUnit LinuxCPU
      ]
    )
  ,
    ( "282.1"
    , Started
    , ["281.1"]
    ,
      [ NoPendingControls 282
      , GateTranscript JitmlNegativeControls LinuxCPU
      , GateTranscript JitmlUnit LinuxCPU
      ]
    )
  ,
    ( "285.1"
    , Started
    , ["282.1"]
    ,
      [ GateTranscript JitmlModelConvergence LinuxCPU
      , GateTranscript JitmlNegativeControls LinuxCPU
      , GateTranscript JitmlUnit LinuxCPU
      ]
    )
  ,
    ( "288.1"
    , Started
    , ["285.1"]
    , [GateTranscript JitmlUnit LinuxCPU, GateTranscript JitmlNegativeControls LinuxCPU]
    )
  ,
    ( "289.1"
    , Started
    , ["288.1"]
    ,
      [ GateTranscript JitmlUnit LinuxCPU
      , GateTranscript JitmlNegativeControls LinuxCPU
      , GateTranscript JitmlModelConvergence LinuxCPU
      , GateTranscript JitmlE2e LinuxCPU
      ]
    )
  ]

catalogueTests :: TestTree
catalogueTests =
  testGroup
    "catalogue"
    [ testCase "enumerates product phases 220 through 289, read from the catalogue" $ do
        PhaseStatus.productPhaseNumbers @?= [220 .. 289]
        PhaseStatus.productPhaseRange @?= (220, 289)
        PhaseStatus.validateProductStatusCatalogue @?= []
    , testCase "the legacy-attested class is frozen: 63 sprints, exactly the historical Done set" $ do
        PhaseStatus.frozenLegacyAttested @?= frozenLegacyLiteral
        length frozenLegacyLiteral @?= 63
        legacyIds @?= frozenLegacyLiteral
    , testCase "the legacy class can shrink but never grow" $ do
        -- A legacy entry outside the frozen set is a catalogue problem.
        PhaseStatus.unfrozenLegacyProblems ["901.1"] [legacyOf 901, legacyOf 902]
          @?= ["legacy attestation is frozen and shrink-only: 902.1 is not in the frozen set"]
        -- Removing an entry from the class (re-proving it) is not.
        PhaseStatus.unfrozenLegacyProblems ["901.1", "902.1"] [legacyOf 901] @?= []
        assertBool
          "every legacy sprint of the real catalogue is in the test-side frozen literal"
          (all (`elem` frozenLegacyLiteral) legacyIds)
    , testCase "a phase dropped from the first product phase's run is reported, not a smaller registry" $ do
        let registry = PhaseStatus.productPhaseStatuses (PhaseStatus.projectProductStatus todayIndex)
        PhaseStatus.firstProductPhase @?= 220
        PhaseStatus.validateProductPhaseStatuses (withoutFirst registry) @?= ["missing product phase: 220"]
        PhaseStatus.validateProductPhaseStatuses (take 5 registry <> drop 6 registry)
          @?= ["missing product phase: 225"]
    , testCase "a plan document the catalogue does not list is a drift, from the first product phase on" $ do
        PlanDoc.phaseDocumentNumber "phase-278-external-bars.md" @?= Just 278
        PlanDoc.phaseDocumentNumber "phase-10-prerequisite-registry.md" @?= Just 10
        PlanDoc.phaseDocumentNumber "README.md" @?= Nothing
        PlanDoc.phaseDocumentNumber "phase-x-name.md" @?= Nothing
        PlanDoc.phaseDocumentNumber "phase-278.md" @?= Nothing
        PlanDoc.phaseDocumentNumber "phase-278-name.txt" @?= Nothing
        -- A phase dropped from the end of the catalogue leaves its document behind.
        fmap
          (Bifunctor.second PlanDoc.issueKey)
          ( PlanDoc.unregisteredPhaseDocuments
              220
              [220 .. 288]
              ["phase-289-evidence-typed-report-measurements.md", "phase-288-x.md"]
          )
          @?= [("phase-289-evidence-typed-report-measurements.md", "status-catalogue.unregistered-phase-289")]
        -- Documents below the first product phase, and files that are not phase documents, are not held to it.
        PlanDoc.unregisteredPhaseDocuments
          220
          [220]
          ["phase-219-old.md", "phase-10-x.md", "README.md", "00-overview.md"]
          @?= []
        case DocsCheck.phaseCoverageDrifts ["phase-999-new.md"] of
          [drift] -> do
            DocsCheck.driftPath drift @?= "DEVELOPMENT_PLAN/phase-999-new.md"
            DocsCheck.driftKey drift @?= "status-catalogue.unregistered-phase-999"
            assertBool
              "the remedy points at the catalogue"
              ("src/JitML/Product/PhaseStatus.hs" `Text.isInfixOf` DocsCheck.docsDriftRemedy drift)
          other -> assertFailure ("expected one drift, got " <> show other)
    , testCase
        "the phase documents on disk are exactly the catalogue's phases from the first product phase"
        $ do
          names <- sort <$> listDirectory "DEVELOPMENT_PLAN"
          DocsCheck.phaseCoverageDrifts names @?= []
          sort
            [ number
            | Just number <- fmap PlanDoc.phaseDocumentNumber names
            , number >= PhaseStatus.firstProductPhase
            ]
            @?= sort PhaseStatus.productPhaseNumbers
    , testCase "every evidenced sprint owns a machine-observable obligation" $
        forM_ evidencedEntries $ \(sprint, _, obligations) ->
          assertBool
            (Text.unpack sprint <> " has only external obligations, so it could never be Done")
            (not (all isExternalObligation (NonEmpty.toList obligations)))
    , testCase "the open sprints are exactly 278, 280, 281, 282, 285, 288, and 289" $
        fmap (\(sprint, _, _) -> sprint) evidencedEntries
          @?= ["278.1", "280.1", "281.1", "282.1", "285.1", "288.1", "289.1"]
    , testCase "every pending production control is owned by a sprint that carries its obligation" $ do
        let covered =
              [ phase
              | (_, _, obligations) <- evidencedEntries
              , NoPendingControls phase <- NonEmpty.toList obligations
              ]
        forM_ pendingProductionControls $ \entry ->
          assertBool
            ("no sprint owns the pending control: " <> Text.unpack entry)
            (maybe False (`elem` covered) (Evidence.pendingControlOwner entry))
    , testCase
        "each evidenced sprint owes exactly what is pinned here, and the standing obligations are these"
        $ do
          -- Written independently of the catalogue, like the frozen legacy literal, so
          -- changing what a sprint owes (dropping a lane journal, the aggregate, an
          -- external prerequisite, or a standing gate) needs a matching edit here.
          [ (sprint, work, upstream, sort (NonEmpty.toList obligations))
            | (sprint, work, upstream, obligations) <- evidencedSprintEntries
            ]
            @?= [ (sprint, work, upstream, sort obligations)
                | (sprint, work, upstream, obligations) <- pinnedEvidencedSprints
                ]
          PhaseStatus.productStandingObligations
            @?= [ StandingGate JitmlUnit LinuxCPU
                , StandingGate JitmlNegativeControls LinuxCPU
                , StandingGate JitmlModelConvergence LinuxCPU
                , LedgerClear
                ]
    , testCase "the catalogue's upstream edges are the phase documents' Blocked by edges" $
        forM_ evidencedEntries $ \(sprint, upstream, _) ->
          upstream
            @?= case sprint of
              "280.1" -> ["278.1"]
              "281.1" -> ["280.1"]
              "282.1" -> ["281.1"]
              "285.1" -> ["282.1"]
              "288.1" -> ["285.1"]
              "289.1" -> ["288.1"]
              _ -> []
    , testGroup
        "structural validation rejects malformed catalogues"
        [ testCase "duplicate phases and sprint ids" $
            Evidence.validateCatalogue [legacyOf 901, legacyOf 901]
              @?= [ "duplicate product phase: 901"
                  , "duplicate sprint id: 901.1"
                  ]
        , testCase "an upstream edge to itself, an unknown sprint, or a higher sprint" $
            Evidence.validateCatalogue
              [ evidencedOf 901 NotStarted ["901.1"] (Aggregate :| [])
              , evidencedOf 902 NotStarted ["999.1"] (Aggregate :| [])
              , evidencedOf 903 NotStarted ["904.1"] (Aggregate :| [])
              , legacyOf 904
              ]
              @?= [ "901.1 depends on itself"
                  , "902.1 depends on unknown sprint 999.1"
                  , "903.1 declares a backward Blocked-by edge to higher-numbered 904.1"
                  ]
        , testCase "a sprint id must belong to its phase" $
            Evidence.validateCatalogue
              [ (legacyOf 901)
                  { entrySprints =
                      [ SprintEntry
                          { entrySprintId = "902.1"
                          , entrySprintTitle = "Wrong phase"
                          , entryClosure = Evidence.legacyAttested "Closure Evidence"
                          }
                      ]
                  }
              ]
              @?= ["sprint 902.1 is listed under phase 901"]
        , testCase "a phase with no sprints" $
            Evidence.validateCatalogue [(legacyOf 901) {entrySprints = []}]
              @?= ["phase 901 has no sprints"]
        , testCase "an upstream edge written as an obligation, and a blank legacy citation" $
            Evidence.validateCatalogue
              [ evidencedOf 901 NotStarted [] (UpstreamSprint "900.1" :| [])
              , phaseOf 902 (Evidence.legacyAttested " ")
              ]
              @?= [ "901.1 declares an upstream edge as an obligation"
                  , "legacy sprint 902.1 cites no closure section"
                  ]
        ]
    ]
 where
  legacyIds =
    [ entrySprintId entry
    | phase <- PhaseStatus.productStatusCatalogue
    , entry <- entrySprints phase
    , Evidence.isLegacyClosure (entryClosure entry)
    ]
  evidencedEntries =
    [ (entrySprintId entry, upstream, obligations)
    | phase <- PhaseStatus.productStatusCatalogue
    , entry <- entrySprints phase
    , Evidence.Evidenced _ upstream obligations <- [entryClosure entry]
    ]
  evidencedSprintEntries =
    [ (entrySprintId entry, work, upstream, obligations)
    | phase <- PhaseStatus.productStatusCatalogue
    , entry <- entrySprints phase
    , Evidence.Evidenced work upstream obligations <- [entryClosure entry]
    ]
  isExternalObligation (ExternalContext _) = True
  isExternalObligation _ = False
  withoutFirst (_ : rest) = rest
  withoutFirst [] = []

-- ---------------------------------------------------------------------------
-- The loader maps production reader errors to Unmet by constructor
-- ---------------------------------------------------------------------------

-- | Which family of reason a mapped error must produce. Written as a total case
-- with no wildcard, so adding a reader constructor breaks this test until it is
-- classified, exactly as it breaks the production mapping.
data Kind = KMissing | KStale | KMismatched | KIncomplete
  deriving stock (Eq, Show)

kindOf :: Unmet -> Kind
kindOf unmet =
  case unmet of
    Missing _ -> KMissing
    Stale {} -> KStale
    Mismatched _ -> KMismatched
    FailedRun _ -> KMismatched
    Incomplete _ -> KIncomplete
    AwaitsSprint _ -> KIncomplete
    External _ -> KIncomplete

expectedLaneKind :: Lane.ProductLaneJournalError -> Kind
expectedLaneKind err =
  case err of
    Lane.ProductLaneJournalSourceRejected _ -> KMismatched
    Lane.ProductLaneJournalContractStale {} -> KStale
    Lane.ProductLaneJournalMalformed _ -> KMismatched
    Lane.ProductLaneJournalNonCanonical -> KMismatched
    Lane.ProductLaneJournalDigestMismatch _ _ -> KMismatched
    Lane.ProductLaneJournalIOFailure _ _ -> KMissing

laneErrors :: [Lane.ProductLaneJournalError]
laneErrors =
  [ Lane.ProductLaneJournalSourceRejected "row: plan_id differs from the current projection"
  , Lane.ProductLaneJournalContractStale "PPO/key-door-grid" (digestOf '1') (digestOf '2')
  , Lane.ProductLaneJournalMalformed "unexpected end of input"
  , Lane.ProductLaneJournalNonCanonical
  , Lane.ProductLaneJournalDigestMismatch (digestOf '1') (digestOf '2')
  , Lane.ProductLaneJournalIOFailure "journal.json" "does not exist"
  ]

expectedAggregateKinds :: ProductAggregationError -> [Kind]
expectedAggregateKinds err =
  case err of
    ProductAggregationLaneCoverage _ -> [KIncomplete]
    ProductAggregationUnregisteredInput _ -> [KMismatched]
    ProductAggregationProjectionRejected _ _ -> [KMismatched]
    ProductAggregationLaneRejected _ errors -> fmap expectedLaneKind (NonEmpty.toList errors)
    ProductAggregationMissingRow _ _ -> [KIncomplete]
    ProductAggregationIOFailure _ _ -> [KMissing]
    ProductAggregationReportDrift _ -> [KMismatched]

aggregateErrors :: [ProductAggregationError]
aggregateErrors =
  [ ProductAggregationLaneCoverage [(LinuxCPU, 0), (LinuxCUDA, 1), (AppleSilicon, 2)]
  , ProductAggregationUnregisteredInput AppleSilicon
  , ProductAggregationProjectionRejected LinuxCPU (EmptyProductProjectionBatch :| [])
  , ProductAggregationLaneRejected LinuxCPU (NonEmpty.fromList laneErrors)
  , ProductAggregationMissingRow LinuxCUDA "PPO/cartpole"
  , ProductAggregationIOFailure "product-aggregate.json" "does not exist"
  , ProductAggregationReportDrift "product-aggregate.json"
  ]

pinFixtures :: [ProductLaneInput]
pinFixtures =
  [ ProductLaneInput LinuxCPU "cpu.json" (digestOf '1')
  , ProductLaneInput LinuxCUDA "cuda.json" (digestOf '2')
  , ProductLaneInput AppleSilicon "apple.json" (digestOf '3')
  ]

-- | A retained aggregate that embeds exactly the fixture pins.
currentAggregate :: ByteString
currentAggregate =
  aggregateWithSources
    [("linux-cpu", digestOf '1'), ("linux-cuda", digestOf '2'), ("apple-silicon", digestOf '3')]

-- | What the reader would recompute when the retained file has gone out of date:
-- the same pins, other bytes.
recomputedAggregate :: ByteString
recomputedAggregate = currentAggregate <> " "

-- | A retained aggregate embedding a pin that is not the fixture pin for its lane.
staleAggregate :: ByteString
staleAggregate =
  aggregateWithSources
    [("linux-cpu", digestOf '1'), ("linux-cuda", digestOf '9'), ("apple-silicon", digestOf '3')]

aggregateWithSources :: [(Text, Text)] -> ByteString
aggregateWithSources sources =
  LazyByteString.toStrict . encode $
    Object
      ( KeyMap.fromList
          [
            ( Key.fromText "sources"
            , Array
                ( Vector.fromList
                    [ Object
                        ( KeyMap.fromList
                            [ (Key.fromText "substrate", String substrate)
                            , (Key.fromText "sha256", String sha)
                            ]
                        )
                    | (substrate, sha) <- sources
                    ]
                )
            )
          ]
      )

loaderMappingTests :: TestTree
loaderMappingTests =
  testGroup
    "loader"
    [ testGroup
        "lane journal reader errors map by constructor"
        ( [ testCase (take 40 (show err)) $
              kindOf (Loader.laneErrorUnmet "linux-cpu" err) @?= expectedLaneKind err
          | err <- laneErrors
          ]
            <> [ testCase "the typed contract-stale error becomes Stale carrying expected and actual" $
                   Loader.laneErrorUnmet
                     "linux-cpu"
                     (Lane.ProductLaneJournalContractStale "TRPO/cartpole" (digestOf '1') (digestOf '2'))
                     @?= Stale "linux-cpu TRPO/cartpole contract_sha256" (digestOf '1') (digestOf '2')
               , testCase "a pin that differs from the retained bytes is Mismatched, naming both digests" $
                   case Loader.laneErrorUnmet
                     "linux-cpu"
                     (Lane.ProductLaneJournalDigestMismatch (digestOf '1') (digestOf '2')) of
                     Mismatched detail ->
                       assertBool
                         "both digests appear"
                         (digestOf '1' `Text.isInfixOf` detail && digestOf '2' `Text.isInfixOf` detail)
                     other -> assertFailure ("expected Mismatched, got " <> show other)
               , testCase "an unreadable journal is Missing, naming the file" $
                   Loader.laneErrorUnmet "linux-cpu" (Lane.ProductLaneJournalIOFailure "j.json" "no such file")
                     @?= Missing "j.json"
               ]
        )
    , testGroup
        "aggregate reader errors map by constructor"
        [ testCase (take 50 (show err)) $
            fmap kindOf (Loader.aggregateErrorUnmet err) @?= expectedAggregateKinds err
        | err <- aggregateErrors
        ]
    , testGroup
        "a retained aggregate is compared with the current pins"
        [ testCase "matching pins are not stale" $
            Loader.aggregatePinDrift
              pinFixtures
              ( aggregateWithSources
                  [("linux-cpu", digestOf '1'), ("linux-cuda", digestOf '2'), ("apple-silicon", digestOf '3')]
              )
              @?= []
        , testCase "an embedded pin that is not the current pin is Stale, current pin expected" $
            Loader.aggregatePinDrift
              pinFixtures
              ( aggregateWithSources
                  [("linux-cpu", digestOf '1'), ("linux-cuda", digestOf '9'), ("apple-silicon", digestOf '3')]
              )
              @?= [Stale "linux-cuda journal pin embedded in the retained aggregate" (digestOf '2') (digestOf '9')]
        , testCase "a lane with no registered pin is Mismatched" $
            fmap kindOf (Loader.aggregatePinDrift pinFixtures (aggregateWithSources [("tpu", digestOf '1')]))
              @?= [KMismatched]
        , testCase "unreadable, sourceless, and malformed aggregates are Mismatched" $ do
            fmap kindOf (Loader.aggregatePinDrift pinFixtures "not json") @?= [KMismatched]
            fmap kindOf (Loader.aggregatePinDrift pinFixtures "{}") @?= [KMismatched]
            fmap kindOf (Loader.aggregatePinDrift pinFixtures "[]") @?= [KMismatched]
            fmap kindOf (Loader.aggregatePinDrift pinFixtures "{\"sources\":[1]}") @?= [KMismatched]
        , testCase "the judgement reports both the reader's errors and the embedded pin drift" $
            case Loader.judgeAggregate
              "product-aggregate.json"
              pinFixtures
              ( Left
                  ( ProductAggregationLaneRejected
                      LinuxCPU
                      (Lane.ProductLaneJournalContractStale "PPO/cartpole" (digestOf '1') (digestOf '2') :| [])
                      :| []
                  )
              )
              ( Right
                  ( aggregateWithSources
                      [("linux-cpu", digestOf '1'), ("linux-cuda", digestOf '9'), ("apple-silicon", digestOf '3')]
                  )
              ) of
              Unproven reasons ->
                fmap kindOf (NonEmpty.toList reasons) @?= [KStale, KStale]
              Proven _ -> assertFailure "a stale aggregate was proven"
        , testCase "a missing retained aggregate is Missing" $
            case Loader.judgeAggregate
              "product-aggregate.json"
              pinFixtures
              (Left (ProductAggregationIOFailure "cpu.json" "gone" :| []))
              (Left "does not exist") of
              Unproven reasons ->
                NonEmpty.toList reasons
                  @?= [Missing "product-aggregate.json", Missing "cpu.json"]
              Proven _ -> assertFailure "a missing aggregate was proven"
        , testGroup
            "the success path"
            [ testCase "a retained aggregate that embeds the current pins and equals the recomputation is Proven" $
                case Loader.judgeAggregate
                  "product-aggregate.json"
                  pinFixtures
                  (Right currentAggregate)
                  (Right currentAggregate) of
                  Proven (evidence :| []) -> do
                    evidenceSubject evidence @?= "product-aggregate.json"
                    evidenceDigest evidence @?= Just (Record.sha256Hex currentAggregate)
                  other -> assertFailure ("expected one proof, got " <> show other)
            , testCase "a retained aggregate that differs from the recomputation is Stale, naming both digests" $
                Loader.judgeAggregate
                  "product-aggregate.json"
                  pinFixtures
                  (Right recomputedAggregate)
                  (Right currentAggregate)
                  @?= unproven
                    ( Stale
                        "retained product aggregate"
                        (Record.sha256Hex recomputedAggregate)
                        (Record.sha256Hex currentAggregate)
                    )
            , testCase "a retained aggregate that cannot be read is Missing even when the lanes recompute" $
                Loader.judgeAggregate
                  "product-aggregate.json"
                  pinFixtures
                  (Right currentAggregate)
                  (Left "does not exist")
                  @?= unproven (Missing "product-aggregate.json")
            , testCase "the recomputation matching is not enough while the embedded pins are stale" $
                Loader.judgeAggregate
                  "product-aggregate.json"
                  pinFixtures
                  (Right staleAggregate)
                  (Right staleAggregate)
                  @?= unproven
                    ( Stale
                        "linux-cuda journal pin embedded in the retained aggregate"
                        (digestOf '2')
                        (digestOf '9')
                    )
            ]
        ]
    , testGroup
        "gate transcripts"
        [ testCase "an absent file is Missing, naming the path" $
            transcriptJudgement
              (Loader.judgeTranscriptFile JitmlUnit LinuxCPU "v/unit.json" Loader.TranscriptAbsent)
              @?= unproven (Missing "v/unit.json")
        , testCase "an unreadable file is Missing and says why" $
            case transcriptJudgement
              ( Loader.judgeTranscriptFile
                  JitmlUnit
                  LinuxCPU
                  "v/unit.json"
                  (Loader.TranscriptUnreadable "permission denied")
              ) of
              Unproven (Missing detail :| []) ->
                assertBool "the reason is retained" ("permission denied" `Text.isInfixOf` detail)
              other -> assertFailure ("expected Missing, got " <> show other)
        , testGroup
            "a rejected record is Mismatched with its typed reason"
            [ testCase (take 40 (show err)) $
                case transcriptJudgement
                  (Loader.judgeTranscriptFile JitmlUnit LinuxCPU "v/unit.json" (Loader.TranscriptRejected err)) of
                  Unproven (Mismatched detail :| []) ->
                    assertBool
                      "the record error is retained"
                      (Record.renderValidationRecordError err `Text.isInfixOf` detail)
                  other -> assertFailure ("expected Mismatched, got " <> show other)
            | err <-
                [RecordMalformed "x", RecordNonCanonical, RecordUnsupported "version 2", RecordInconsistent "y"]
            ]
        , testCase "a passing standing record is Proven with the file digest as its pointer" $
            transcriptJudgement (judgedAdmitted JitmlUnit LinuxCPU goodRecord)
              @?= Proven
                ( EvidenceRef
                    { evidenceSubject = "DEVELOPMENT_PLAN/attestations/validation/fixture.json"
                    , evidenceDigest = Just (digestOf 'd')
                    }
                    :| []
                )
        , testCase "the record's source stamp is carried for freshness" $
            transcriptSource (judgedAdmitted JitmlUnit LinuxCPU goodRecord) @?= Just fixtureStamp
        , testCase "a record filed under the wrong gate or substrate is Mismatched on each count" $ do
            let wrongGate = judgedAdmitted JitmlIntegration LinuxCPU goodRecord
                wrongLane = judgedAdmitted JitmlUnit LinuxCUDA goodRecord
            assertBool "gate" (any isMismatchedGate (reasonsOfJudgement wrongGate))
            assertBool "substrate" (any isMismatchedSubstrate (reasonsOfJudgement wrongLane))
        , testCase "a failed record retains its failure as FailedRun and never proves" $
            case transcriptJudgement
              ( judgedAdmitted
                  JitmlUnit
                  LinuxCPU
                  ( mkRecord
                      JitmlUnit
                      LinuxCPU
                      (standingCommand JitmlUnit LinuxCPU)
                      fixtureStamp
                      ( EvidenceFailed
                          FailedEvidence
                            { failedExitCode = Nothing
                            , failedStdout = Nothing
                            , failedStderr = Nothing
                            , failedException = Just "cabal: command not found"
                            }
                      )
                  )
              ) of
              Unproven (FailedRun detail :| []) ->
                assertBool "the missing exit status is stated" ("before an exit status" `Text.isInfixOf` detail)
              other -> assertFailure ("expected FailedRun, got " <> show other)
        ]
    , testGroup
        "the standing command is derived from the invocation planner"
        [ testCase "every gate on every substrate accepts its own planned command" $
            forM_ [(gate, lane) | gate <- Record.allValidationGates, lane <- allSubstrates] $ \(gate, lane) -> do
              let planned = Loader.standingCommandTail gate lane
              assertBool ("non-empty tail for " <> show (gate, lane)) (not (Text.null planned))
              assertBool
                ("plain cabal for " <> show (gate, lane))
                (Loader.commandIsStanding gate lane ("cabal " <> planned))
              assertBool
                ("absolute cabal path for " <> show (gate, lane))
                (Loader.commandIsStanding gate lane ("/root/.ghcup/bin/cabal " <> planned))
              assertBool
                ("live nice wrapper for " <> show (gate, lane))
                (Loader.commandIsStanding gate lane ("/usr/bin/nice -n 10 /root/.ghcup/bin/cabal " <> planned))
              assertBool
                ("quoted cabal path for " <> show (gate, lane))
                (Loader.commandIsStanding gate lane ("'/opt/my tools/cabal' " <> planned))
        , testCase "a versioned cabal file name, as a ghcup link resolves to, is the standing executable" $
            forM_ [(gate, lane) | gate <- Record.allValidationGates, lane <- allSubstrates] $ \(gate, lane) -> do
              let planned = Loader.standingCommandTail gate lane
              forM_
                [ "/home/matt/.ghcup/bin/cabal-3.16.1.0 "
                , "cabal-3.16.1.0 "
                , "/usr/bin/nice -n 10 /root/.ghcup/bin/cabal-3.16.1.0 "
                , "'/opt/my tools/cabal-3.16.1.0' "
                , "/opt/cabal-3 "
                ]
                $ \prefix ->
                  assertBool
                    (Text.unpack prefix <> " for " <> show (gate, lane))
                    (Loader.commandIsStanding gate lane (prefix <> planned))
        , testCase "a file name that merely starts with cabal is not cabal"
            $ forM_
              [ "cabal-"
              , "cabal-x"
              , "cabal-3..1"
              , "cabal-3.1."
              , "cabal-.1"
              , "cabal-3.1-beta"
              , "cabal-3.1.0.sh"
              , "cabalx"
              , "xcabal"
              , "my-cabal"
              , "cabal.exe"
              , "cabal_3"
              ]
            $ \name ->
              assertBool
                (name <> " is not the standing executable")
                ( not
                    ( Loader.commandIsStanding
                        JitmlUnit
                        LinuxCPU
                        (Text.pack ("/usr/bin/" <> name <> " test jitml-unit"))
                    )
                )
        , testCase "the cuda lane adds -fcuda and the backends stanza is lane-filtered" $ do
            Loader.standingCommandTail JitmlUnit LinuxCPU @?= "test jitml-unit"
            Loader.standingCommandTail JitmlUnit LinuxCUDA @?= "test -fcuda jitml-unit"
            Loader.standingCommandTail JitmlBackends LinuxCPU
              @?= "test jitml-backends --test-options '-p linux-cpu'"
        , testCase "a focused run, another stanza, another lane, or a foreign prefix is not standing" $ do
            let notStanding = not . Loader.commandIsStanding JitmlUnit LinuxCPU
            assertBool "focused" (notStanding "cabal test jitml-unit --test-options '-p Journal'")
            assertBool "other stanza" (notStanding "cabal test jitml-integration")
            assertBool "other lane" (notStanding "cabal test -fcuda jitml-unit")
            assertBool "foreign executable" (notStanding "make test jitml-unit")
            assertBool "shell prefix" (notStanding "rm -rf x; /usr/bin/cabal test jitml-unit")
            assertBool "no executable" (notStanding "test jitml-unit")
            assertBool "empty" (notStanding "")
        ]
    , testGroup
        "a gate that proves live-only code needs a live transcript"
        [ testCase "only the end-to-end stanza requires a live run" $
            [gate | gate <- Record.allValidationGates, Loader.gateRequiresLiveRun gate] @?= [JitmlE2e]
        , testCase "a live run is recognised by the nice wrapper alone" $ do
            assertBool
              "nice wrapper"
              (Loader.commandRanLive "/usr/bin/nice -n 10 /root/.ghcup/bin/cabal test jitml-e2e")
            assertBool "plain cabal" (not (Loader.commandRanLive "/root/.ghcup/bin/cabal test jitml-e2e"))
            assertBool
              "another priority"
              (not (Loader.commandRanLive "/usr/bin/nice -n 5 cabal test jitml-e2e"))
            assertBool
              "a shell prefix"
              (not (Loader.commandRanLive "echo /usr/bin/nice -n 10 cabal test jitml-e2e"))
            assertBool "empty" (not (Loader.commandRanLive ""))
        , testCase "the wrapper jitml test --live builds is exactly what the loader recognises" $
            forM_ [(gate, lane) | gate <- Record.allValidationGates, lane <- allSubstrates] $ \(gate, lane) ->
              case Report.substrateTestInvocations (Just lane) [Record.renderValidationGate gate] Nothing of
                [args] -> do
                  let plain = renderSubprocess (subprocess "/root/.ghcup/bin/cabal" args)
                      live = renderSubprocess (underNice (subprocess "/root/.ghcup/bin/cabal" args))
                  assertBool ("live run recognised for " <> show (gate, lane)) (Loader.commandRanLive live)
                  assertBool
                    ("live run is standing for " <> show (gate, lane))
                    (Loader.commandIsStanding gate lane live)
                  assertBool ("plain run is not live for " <> show (gate, lane)) (not (Loader.commandRanLive plain))
                  assertBool
                    ("plain run is standing for " <> show (gate, lane))
                    (Loader.commandIsStanding gate lane plain)
                other -> assertFailure ("expected one planned invocation, got " <> show other)
        , testCase "a passing non-live end-to-end record is Incomplete and does not prove the gate" $
            case transcriptJudgement (judgedE2e (standingCommand JitmlE2e LinuxCPU)) of
              Unproven (Incomplete detail :| []) ->
                assertBool "the non-live run is named" ("non-live" `Text.isInfixOf` detail)
              other -> assertFailure ("expected Incomplete, got " <> show other)
        , testCase "a passing live end-to-end record proves the gate" $
            case transcriptJudgement (judgedE2e ("/usr/bin/nice -n 10 " <> standingCommand JitmlE2e LinuxCPU)) of
              Proven _ -> pure ()
              other -> assertFailure ("expected Proven, got " <> show other)
        , testCase "every other gate proves on a passing run, live or not" $
            forM_ [gate | gate <- Record.allValidationGates, gate /= JitmlE2e] $ \gate ->
              forM_
                [standingCommand gate LinuxCPU, "/usr/bin/nice -n 10 " <> standingCommand gate LinuxCPU]
                $ \command ->
                  case transcriptJudgement
                    (judgedAdmitted gate LinuxCPU (mkRecord gate LinuxCPU command fixtureStamp passedEvidence)) of
                    Proven _ -> pure ()
                    other -> assertFailure (show gate <> " did not prove: " <> show other)
        , testCase "a record of another gate filed as the end-to-end transcript gets no liveness complaint" $ do
            let misfiled =
                  judgedAdmitted
                    JitmlE2e
                    LinuxCPU
                    (mkRecord JitmlUnit LinuxCPU (standingCommand JitmlUnit LinuxCPU) fixtureStamp passedEvidence)
            assertBool "the wrong gate is reported" (any isMismatchedGate (reasonsOfJudgement misfiled))
            assertBool
              "no reason claims a non-live end-to-end run"
              (not (any isNonLiveReason (reasonsOfJudgement misfiled)))
        , testCase "a failed or unfinished end-to-end run reports its own reason, not a liveness complaint" $ do
            let judgedWith evidence =
                  transcriptJudgement
                    ( judgedAdmitted
                        JitmlE2e
                        LinuxCPU
                        (mkRecord JitmlE2e LinuxCPU (standingCommand JitmlE2e LinuxCPU) fixtureStamp evidence)
                    )
            case judgedWith
              ( EvidenceFailed
                  FailedEvidence
                    { failedExitCode = Just 1
                    , failedStdout = Just ""
                    , failedStderr = Just ""
                    , failedException = Nothing
                    }
              ) of
              Unproven (FailedRun _ :| []) -> pure ()
              other -> assertFailure ("expected FailedRun alone, got " <> show other)
            case judgedWith (EvidenceNotRun "jitml-integration" "cabal test jitml-integration exited 1") of
              Unproven (Incomplete detail :| []) ->
                assertBool "the blocker is named" ("jitml-integration" `Text.isInfixOf` detail)
              other -> assertFailure ("expected the blocker alone, got " <> show other)
        ]
    , testGroup
        "the committed validation directory"
        [ testCase "exactly the <gate>.<substrate>.json names are expected" $ do
            let all30 = [Record.validationRecordFileName g s | g <- Record.allValidationGates, s <- allSubstrates]
            length all30 @?= 30
            Loader.unexpectedValidationFiles all30 @?= []
            Loader.unexpectedValidationFiles [] @?= []
        , testCase "misnamed files are reported and hidden files are not" $
            Loader.unexpectedValidationFiles
              [ ".gitkeep"
              , "jitml-unit.linux-cpu.json"
              , "jitml-unit.json"
              , "unit.linux-cpu.json"
              , "jitml-unit.linux-cpu.json.bak"
              , "README.md"
              , "jitml-unit.tpu.json"
              ]
              @?= [ "jitml-unit.json"
                  , "unit.linux-cpu.json"
                  , "jitml-unit.linux-cpu.json.bak"
                  , "README.md"
                  , "jitml-unit.tpu.json"
                  ]
        ]
    , testGroup
        "the legacy ledger"
        [ testCase "rows are counted from the Pending Removal table" $
            Loader.ledgerPendingRows (ledger ["| a | b |", "| c | d |"]) @?= Just 2
        , testCase "an empty table has no rows" $
            Loader.ledgerPendingRows (ledger []) @?= Just 0
        , testCase "prose that says None. is an empty ledger" $
            Loader.ledgerPendingRows "## Pending Removal\n\nNone.\n\n## Completed\n" @?= Just 0
        , testCase "an unreadable table is not read as empty" $ do
            Loader.ledgerPendingRows "## Pending Removal\n\nProse only.\n\n## Completed\n" @?= Nothing
            Loader.ledgerPendingRows "## Completed\n" @?= Nothing
            Loader.ledgerPendingRows "## Pending Removal\n\n| Name | Other |\n|---|---|\n| x | y |\n"
              @?= Nothing
        , testCase "the real ledger's Pending Removal table is readable" $ do
            content <- Text.IO.readFile Loader.legacyLedgerPath
            assertBool "the real ledger parses" (isJust (Loader.ledgerPendingRows content))
        , testCase "the judgement is proven only for an empty, readable table" $ do
            case Loader.judgeLedger "ledger.md" (Right (ledger [])) of
              Proven _ -> pure ()
              Unproven reasons -> assertFailure (show reasons)
            case Loader.judgeLedger "ledger.md" (Right (ledger ["| a | b |"])) of
              Unproven (Incomplete detail :| []) -> assertBool "the row count is stated" ("1 row" `Text.isInfixOf` detail)
              other -> assertFailure ("expected Incomplete, got " <> show other)
            fmap kindOf (unprovenReasons (Loader.judgeLedger "ledger.md" (Right "no section")))
              @?= [KMismatched]
            fmap kindOf (unprovenReasons (Loader.judgeLedger "ledger.md" (Left "gone"))) @?= [KMissing]
        ]
    ]
 where
  reasonsOfJudgement evidence =
    case transcriptJudgement evidence of
      Unproven reasons -> NonEmpty.toList reasons
      Proven _ -> []
  isMismatchedGate (Mismatched detail) = "records gate" `Text.isInfixOf` detail
  isMismatchedGate _ = False
  isMismatchedSubstrate (Mismatched detail) = "records substrate" `Text.isInfixOf` detail
  isMismatchedSubstrate _ = False
  isNonLiveReason (Incomplete detail) = "non-live" `Text.isInfixOf` detail
  isNonLiveReason _ = False
  unprovenReasons (Unproven reasons) = NonEmpty.toList reasons
  unprovenReasons (Proven _) = []
  ledger rows =
    Text.unlines
      ( ["## Pending Removal", "", "Prose.", "", "| Item | Location |", "|------|----------|"]
          <> rows
          <> ["", "## Completed", ""]
      )

-- ---------------------------------------------------------------------------
-- The validation record
-- ---------------------------------------------------------------------------

failedRecordFixture :: Record.ValidationRecord
failedRecordFixture =
  mkRecord
    JitmlUnit
    LinuxCPU
    "cabal test jitml-unit"
    fixtureStamp
    ( EvidenceFailed
        FailedEvidence
          { failedExitCode = Just 1
          , failedStdout = Just "All 5 tests\n  case: FAIL\n  caf\233 \8212 unicode\n"
          , failedStderr = Just ""
          , failedException = Nothing
          }
    )

attemptFailureFixture :: Record.ValidationRecord
attemptFailureFixture =
  mkRecord
    JitmlBackends
    LinuxCUDA
    "cabal test -fcuda jitml-backends"
    fixtureStamp
    ( EvidenceFailed
        FailedEvidence
          { failedExitCode = Nothing
          , failedStdout = Nothing
          , failedStderr = Just "partial"
          , failedException = Just "cabal: could not start"
          }
    )

notRunFixture :: Record.ValidationRecord
notRunFixture =
  mkRecord
    JitmlE2e
    AppleSilicon
    "cabal test jitml-e2e"
    fixtureStamp
    (EvidenceNotRun "jitml-integration" "cabal test jitml-integration exited 1")

recordFixtures :: [(String, Record.ValidationRecord)]
recordFixtures =
  [ ("passed", goodRecord)
  , ("failed with retained streams", failedRecordFixture)
  , ("failed by a runner exception with a stream unavailable", attemptFailureFixture)
  , ("not run", notRunFixture)
  ]

-- | Decode canonical bytes, change the JSON, and re-encode canonically, so a
-- tamper test exercises the record's own rejection and not JSON hygiene.
tamperWith :: (Value -> Value) -> ByteString -> ByteString
tamperWith change bytes =
  case eitherDecodeStrict' bytes of
    Left err -> error ("fixture bytes do not decode: " <> err)
    Right value -> LazyByteString.toStrict (encode (change value)) <> "\n"

setField :: Text -> Value -> Value -> Value
setField field value (Object record) = Object (KeyMap.insert (Key.fromText field) value record)
setField _ _ other = other

deleteField :: Text -> Value -> Value
deleteField field (Object record) = Object (KeyMap.delete (Key.fromText field) record)
deleteField _ other = other

fieldOf :: Text -> Value -> Maybe Value
fieldOf field (Object record) = KeyMap.lookup (Key.fromText field) record
fieldOf _ _ = Nothing

recordBytes :: Record.ValidationRecord -> ByteString
recordBytes = Record.renderValidationRecord

assertRecordError :: (ValidationRecordError -> Bool) -> String -> ByteString -> Assertion
assertRecordError matches label bytes =
  case Record.admitValidationRecord bytes of
    Left err -> assertBool (label <> ": unexpected error " <> show err) (matches err)
    Right _ -> assertFailure (label <> ": the tampered record was admitted")

isMalformed, isNonCanonical, isUnsupported, isInconsistent :: ValidationRecordError -> Bool
isMalformed (RecordMalformed _) = True
isMalformed _ = False
isNonCanonical RecordNonCanonical = True
isNonCanonical _ = False
isUnsupported (RecordUnsupported _) = True
isUnsupported _ = False
isInconsistent (RecordInconsistent _) = True
isInconsistent _ = False

inconsistentWith :: Text -> ValidationRecordError -> Bool
inconsistentWith needle (RecordInconsistent detail) = needle `Text.isInfixOf` detail
inconsistentWith _ _ = False

validationRecordTests :: TestTree
validationRecordTests =
  testGroup
    "validation record"
    [ testGroup
        "round trip"
        ( [ testCase label $ do
              Record.admitValidationRecord (recordBytes record) @?= Right record
              recordBytes record @?= recordBytes record
              assertBool "one line and a newline" (ByteString.count 10 (recordBytes record) == 1)
          | (label, record) <- recordFixtures
          ]
            <> [ testCase "distinct evidence renders distinct bytes" $
                   assertBool
                     "all four fixtures differ"
                     (length (nub (fmap (recordBytes . snd) recordFixtures)) == length recordFixtures)
               ]
        )
    , testCase "the wire carries exactly the version-1 field set" $ do
        raw <- either (assertFailure . show) pure (eitherDecodeStrict' (recordBytes goodRecord))
        case raw of
          Object record ->
            sort (fmap Key.toText (KeyMap.keys record))
              @?= sort
                [ "blocked_by_detail"
                , "blocked_by_stanza"
                , "command"
                , "exception"
                , "executable_sha256"
                , "exit_code"
                , "format"
                , "gate"
                , "outcome"
                , "source_digest_algorithm"
                , "source_sha256"
                , "stderr"
                , "stderr_sha256"
                , "stdout"
                , "stdout_sha256"
                , "substrate"
                , "version"
                ]
          _ -> assertFailure "the record is not a JSON object"
        fieldOf "format" raw @?= Just (String "jitml-validation-record")
        fieldOf "version" raw @?= Just (Number 1)
        fieldOf "gate" raw @?= Just (String "jitml-unit")
        fieldOf "substrate" raw @?= Just (String "linux-cpu")
        fieldOf "outcome" raw @?= Just (String "Passed")
        fieldOf "exit_code" raw @?= Just (Number 0)
        fieldOf "stdout" raw @?= Just Null
        fieldOf "stdout_sha256" raw @?= Just (String (digestOf '5'))
    , testCase "a failed run retains both complete streams and their digests" $ do
        raw <- either (assertFailure . show) pure (eitherDecodeStrict' (recordBytes failedRecordFixture))
        fieldOf "outcome" raw @?= Just (String "Failed")
        fieldOf "stdout" raw @?= Just (String "All 5 tests\n  case: FAIL\n  caf\233 \8212 unicode\n")
        fieldOf "stderr" raw @?= Just (String "")
        fieldOf
          "stdout_sha256"
          raw
          @?= Just
            ( String
                (Record.sha256Hex (Text.Encoding.encodeUtf8 "All 5 tests\n  case: FAIL\n  caf\233 \8212 unicode\n"))
            )
        fieldOf "stderr_sha256" raw @?= Just (String (Record.sha256Hex ""))
    , testGroup
        "the reader rejects each tamper with its typed reason"
        [ testCase "not JSON and empty input" $ do
            assertRecordError isMalformed "not json" "not json"
            assertRecordError isMalformed "empty" ""
        , testCase "an unknown field" $
            assertRecordError
              isMalformed
              "unknown field"
              (tamperWith (setField "extra" Null) (recordBytes goodRecord))
        , testCase "a missing field" $
            assertRecordError
              isMalformed
              "missing gate"
              (tamperWith (deleteField "gate") (recordBytes goodRecord))
        , testCase "a field of the wrong type" $
            assertRecordError
              isMalformed
              "string exit code"
              (tamperWith (setField "exit_code" (String "0")) (recordBytes goodRecord))
        , testCase "another format or version is unsupported, not malformed" $ do
            assertRecordError
              isUnsupported
              "format"
              (tamperWith (setField "format" (String "jitml-product-lane-journal")) (recordBytes goodRecord))
            assertRecordError
              isUnsupported
              "version"
              (tamperWith (setField "version" (Number 2)) (recordBytes goodRecord))
        , testCase "bytes that are not the canonical rendering" $ do
            assertRecordError isNonCanonical "trailing space" (recordBytes goodRecord <> " ")
            assertRecordError isNonCanonical "no newline" (ByteString.init (recordBytes goodRecord))
            assertRecordError
              isNonCanonical
              "reformatted"
              (ByteString.take 1 (recordBytes goodRecord) <> " " <> ByteString.drop 1 (recordBytes goodRecord))
        , testCase "an unknown gate, substrate, or outcome" $ do
            assertRecordError
              (inconsistentWith "unknown gate")
              "gate"
              (tamperWith (setField "gate" (String "jitml-fuzz")) (recordBytes goodRecord))
            assertRecordError
              (inconsistentWith "unknown substrate")
              "substrate"
              (tamperWith (setField "substrate" (String "tpu")) (recordBytes goodRecord))
            assertRecordError
              (inconsistentWith "unknown outcome")
              "outcome"
              (tamperWith (setField "outcome" (String "Skipped")) (recordBytes goodRecord))
        , testCase "a passed run must exit zero, retain no stream, and carry both digests" $ do
            assertRecordError
              (inconsistentWith "exit_code 0")
              "exit code"
              (tamperWith (setField "exit_code" (Number 1)) (recordBytes goodRecord))
            assertRecordError
              (inconsistentWith "must not carry stdout")
              "stream"
              (tamperWith (setField "stdout" (String "leak")) (recordBytes goodRecord))
            assertRecordError
              (inconsistentWith "must carry stdout_sha256")
              "digest"
              (tamperWith (setField "stdout_sha256" Null) (recordBytes goodRecord))
            assertRecordError
              (inconsistentWith "not canonical SHA-256")
              "hex"
              (tamperWith (setField "stderr_sha256" (String "XYZ")) (recordBytes goodRecord))
            assertRecordError
              (inconsistentWith "must not carry exception")
              "exception"
              (tamperWith (setField "exception" (String "boom")) (recordBytes goodRecord))
        , testCase "digests and the command must be canonical" $ do
            assertRecordError
              (inconsistentWith "executable_sha256")
              "executable"
              (tamperWith (setField "executable_sha256" (String "abc")) (recordBytes goodRecord))
            assertRecordError
              (inconsistentWith "source_sha256")
              "source"
              ( tamperWith
                  (setField "source_sha256" (String (Text.toUpper (digestOf 'a'))))
                  (recordBytes goodRecord)
              )
            assertRecordError
              (inconsistentWith "command is empty")
              "empty command"
              (tamperWith (setField "command" (String "")) (recordBytes goodRecord))
            assertRecordError
              (inconsistentWith "command is empty")
              "untrimmed command"
              (tamperWith (setField "command" (String " cabal test")) (recordBytes goodRecord))
            assertRecordError
              (inconsistentWith "command is empty")
              "multiline command"
              (tamperWith (setField "command" (String "cabal\ntest")) (recordBytes goodRecord))
        , testCase "a failed run's retained stream must hash to its recorded digest" $ do
            assertRecordError
              (inconsistentWith "does not hash to its recorded digest")
              "edited stdout"
              (tamperWith (setField "stdout" (String "All 5 tests passed\n")) (recordBytes failedRecordFixture))
            assertRecordError
              (inconsistentWith "does not hash to its recorded digest")
              "edited digest"
              (tamperWith (setField "stderr_sha256" (String (digestOf '7'))) (recordBytes failedRecordFixture))
            assertRecordError
              (inconsistentWith "together")
              "dropped stream"
              (tamperWith (setField "stdout" Null) (recordBytes failedRecordFixture))
        , testCase "a failed run must record a non-zero exit or an exception, never both or neither" $ do
            assertRecordError
              (inconsistentWith "zero exit code")
              "zero"
              (tamperWith (setField "exit_code" (Number 0)) (recordBytes failedRecordFixture))
            assertRecordError
              (inconsistentWith "neither")
              "neither"
              (tamperWith (setField "exit_code" Null) (recordBytes failedRecordFixture))
            assertRecordError
              (inconsistentWith "both")
              "both"
              (tamperWith (setField "exception" (String "boom")) (recordBytes failedRecordFixture))
        , testCase "flipping the outcome of a failed run cannot turn it into a pass" $
            assertRecordError
              isInconsistent
              "failed to passed"
              ( tamperWith
                  (setField "outcome" (String "Passed") . setField "exit_code" (Number 0))
                  (recordBytes failedRecordFixture)
              )
        , testCase "a not-run record carries a blocker and nothing else" $ do
            assertRecordError
              (inconsistentWith "must carry blocked_by_stanza")
              "no blocker"
              (tamperWith (setField "blocked_by_stanza" Null) (recordBytes notRunFixture))
            assertRecordError
              (inconsistentWith "must not carry exit_code")
              "exit"
              (tamperWith (setField "exit_code" (Number 0)) (recordBytes notRunFixture))
            assertRecordError
              (inconsistentWith "must not carry stdout_sha256")
              "digest"
              (tamperWith (setField "stdout_sha256" (String (digestOf '5'))) (recordBytes notRunFixture))
            assertRecordError
              isInconsistent
              "not run to passed"
              ( tamperWith
                  (setField "outcome" (String "Passed") . setField "exit_code" (Number 0))
                  (recordBytes notRunFixture)
              )
        , testCase "a not-run record cannot smuggle a blocker onto a passed or failed run" $ do
            assertRecordError
              (inconsistentWith "must not carry blocked_by_stanza")
              "passed"
              (tamperWith (setField "blocked_by_stanza" (String "x")) (recordBytes goodRecord))
            assertRecordError
              (inconsistentWith "must not carry blocked_by_detail")
              "failed"
              (tamperWith (setField "blocked_by_detail" (String "x")) (recordBytes failedRecordFixture))
        ]
    , testGroup
        "the smart constructor enforces the same rules"
        [ testCase "command shape" $ do
            forM_ ["", " padded", "line\nbreak", "tab\there"] $ \command ->
              assertBool
                ("rejects " <> show command)
                ( isLeft'
                    (Record.mkValidationRecord JitmlUnit LinuxCPU command (digestOf 'e') fixtureStamp passedEvidence)
                )
        , testCase "digest shape" $ do
            assertBool
              "executable"
              (isLeft' (Record.mkValidationRecord JitmlUnit LinuxCPU "c" "short" fixtureStamp passedEvidence))
            assertBool
              "source"
              ( isLeft'
                  ( Record.mkValidationRecord
                      JitmlUnit
                      LinuxCPU
                      "c"
                      (digestOf 'e')
                      fixtureStamp {stampSha256 = "short"}
                      passedEvidence
                  )
              )
            assertBool
              "stream"
              ( isLeft'
                  ( Record.mkValidationRecord
                      JitmlUnit
                      LinuxCPU
                      "c"
                      (digestOf 'e')
                      fixtureStamp
                      (EvidencePassed "x" (digestOf '6'))
                  )
              )
        , testCase "evidence shape" $ do
            let failed exitCode exception =
                  EvidenceFailed
                    FailedEvidence
                      { failedExitCode = exitCode
                      , failedStdout = Nothing
                      , failedStderr = Nothing
                      , failedException = exception
                      }
                build = Record.mkValidationRecord JitmlUnit LinuxCPU "c" (digestOf 'e') fixtureStamp
            assertBool "zero exit" (isLeft' (build (failed (Just 0) Nothing)))
            assertBool "no cause" (isLeft' (build (failed Nothing Nothing)))
            assertBool "both causes" (isLeft' (build (failed (Just 1) (Just "e"))))
            assertBool "blank exception" (isLeft' (build (failed Nothing (Just " "))))
            assertBool "blank blocker" (isLeft' (build (EvidenceNotRun "" "detail")))
            assertBool "valid failure" (not (isLeft' (build (failed (Just 2) Nothing))))
        ]
    , testGroup
        "gates and files"
        [ testCase "the gate enum is exactly the stanzas jitml test runs" $
            fmap Record.renderValidationGate Record.allValidationGates @?= Report.reportStanzas
        , testCase "gates parse and render as each other's inverse" $ do
            forM_ Record.allValidationGates $ \gate ->
              Record.parseValidationGate (Record.renderValidationGate gate) @?= Just gate
            Record.parseValidationGate "docs-check" @?= Nothing
            Record.parseValidationGate "check-code" @?= Nothing
        , testCase "there is one file per gate and substrate" $ do
            Record.validationRecordFileName JitmlUnit LinuxCPU @?= "jitml-unit.linux-cpu.json"
            Record.validationRecordFileName JitmlBackends AppleSilicon @?= "jitml-backends.apple-silicon.json"
            let names = [Record.validationRecordFileName g s | g <- Record.allValidationGates, s <- allSubstrates]
            length (nub names) @?= length names
        , testCase "the committed and candidate directories are the documented ones" $ do
            Record.committedValidationDirectory @?= "DEVELOPMENT_PLAN/attestations/validation"
            Record.candidateValidationDirectory @?= ".build/runtime/validation"
        , testCase "the atomic writer writes a world-readable record that admits and leaves no temporary file" $
            withSystemTempDirectory "jitml-validation-record" $ \directory -> do
              first <- Record.writeValidationRecordAtomic directory failedRecordFixture
              path <- either (assertFailure . Text.unpack) pure first
              takeFileName path @?= "jitml-unit.linux-cpu.json"
              written <- ByteString.readFile path
              Record.admitValidationRecord written @?= Right failedRecordFixture
              mode <- fileMode <$> getFileStatus path
              intersectFileModes mode 0o777 @?= 0o644
              -- Writing again replaces the record in place.
              second <- Record.writeValidationRecordAtomic directory failedRecordFixture
              second @?= Right path
              listDirectory directory >>= (@?= ["jitml-unit.linux-cpu.json"])
        ]
    ]
 where
  isLeft' (Left _) = True
  isLeft' (Right _) = False

-- ---------------------------------------------------------------------------
-- The source digest
-- ---------------------------------------------------------------------------

writeTree :: FilePath -> [(FilePath, ByteString)] -> IO ()
writeTree root files =
  forM_ files $ \(path, bytes) -> do
    createDirectoryIfMissing True (takeDirectory (root </> path))
    ByteString.writeFile (root </> path) bytes

baseTree :: [(FilePath, ByteString)]
baseTree =
  [ ("app/Main.hs", "main = pure ()\n")
  , ("gen/Proto/Jitml/Gen.hs", "module Proto.Jitml.Gen where\n")
  , ("src/JitML/A.hs", "module JitML.A where\n")
  , ("src/JitML/Deep/B.hs", "module JitML.Deep.B where\n")
  , ("test/unit/Main.hs", "main = pure ()\n")
  , ("test/snapshots/one.txt", "snapshot\n")
  , ("cabal.project", "packages: .\n")
  , ("jitml.cabal", "name: jitml\n")
  ]

stampIn :: FilePath -> IO SourceStamp
stampIn root = computeSourceStampIn root >>= either (failTest . Text.unpack) pure

-- | Fail the test and satisfy the type of the value it was going to produce.
failTest :: String -> IO a
failTest message = assertFailure message >> fail message

-- | A fixed corpus whose digest is pinned below. It has a CRLF pair (normalised
-- before hashing), a non-ASCII path (hashed as UTF-8), and paths whose sorted
-- order differs from the order written here.
goldenCorpus :: [(FilePath, ByteString)]
goldenCorpus =
  [ ("src/JitML/B.hs", "module JitML.B where\r\nb = 2\r\n")
  , ("app/Main.hs", "main = pure ()\n")
  , ("src/JitML/A.hs", "module JitML.A where\n")
  , ("cabal.project", "packages: .\n")
  , ("jitml.cabal", "name: jitml\n")
  , ("src/JitML/caf\233.hs", "caf\195\169 = 1\n")
  , ("test/unit/Main.hs", "main = pure ()\n")
  ]

-- | One file per counted extension, and one per kind of file the walk must ignore.
goldenWalkerTree :: [(FilePath, ByteString)]
goldenWalkerTree =
  [ ("app/Main.hs", "main = pure ()\n")
  , ("gen/Proto/Jitml/Gen.hs", "module Proto.Jitml.Gen where\n")
  , ("src/JitML/A.hs", "module JitML.A where\n")
  , ("src/JitML/Deep/B.hs", "module JitML.Deep.B where\n")
  , ("src/JitML/Foreign.c", "int f(void) { return 0; }\n")
  , ("src/JitML/Foreign.h", "int f(void);\n")
  , ("src/JitML/Foreign.hsc", "module F where\n")
  , ("src/JitML/Loop.hs-boot", "module JitML.Loop where\n")
  , ("test/unit/Main.hs", "main = pure ()\n")
  , ("test/data/notes.txt", "notes\n")
  , ("test/data/readme.md", "# readme\n")
  , ("test/data/settings.yaml", "a: 1\n")
  , ("test/data/settings.yml", "b: 2\n")
  , ("test/data/fixture.json", "{}\n")
  , ("test/data/schema.dhall", "{=}\n")
  , ("test/data/extra.cabal", "name: extra\n")
  , ("test/data/extra.project", "packages: .\n")
  , ("cabal.project", "packages: .\n")
  , ("jitml.cabal", "name: jitml\n")
  ]

-- | Files under the roots the digest must not see.
goldenWalkerIgnored :: [(FilePath, ByteString)]
goldenWalkerIgnored =
  [ ("src/JitML/A.o", "object")
  , ("src/JitML/A.hi", "interface")
  , ("src/JitML/gen.cc", "int g;\n")
  , ("src/JitML/kernel.cu", "kernel\n")
  , ("src/JitML/kernel.metal", "kernel\n")
  , ("src/JitML/bridge.swift", "bridge\n")
  , ("src/notes", "no extension")
  , ("src/.hidden.hs", "hidden")
  , ("src/.git/config.hs", "hidden directory")
  , ("test/data/blob.bin", "\NUL\SOH")
  , ("docs/extra.hs", "not a code root")
  ]

sourceDigestTests :: TestTree
sourceDigestTests =
  testGroup
    "source digest"
    [ testCase "the algorithm is pinned by a golden digest over a fixed corpus" $
        -- The literal was computed by an independent implementation of the documented
        -- algorithm (seed tag, path-ordered records of path, length, bytes), so
        -- changing the seed, the order, the framing, or the normalisation moves it.
        sourceStampFromFiles goldenCorpus
          @?= SourceStamp
            { stampAlgorithm = 1
            , stampSha256 = "a7a009882a24e797b528de7f8b65c95de1566496e06380f0fb7bf38c08571c05"
            }
    , testCase
        "the walk counts exactly the pinned extensions: a golden digest over a tree with one file of each kind"
        $ withSystemTempDirectory "jitml-digest"
        $ \root -> do
          writeTree root (goldenWalkerTree <> goldenWalkerIgnored)
          stampIn root
            >>= ( @?=
                    SourceStamp
                      { stampAlgorithm = 1
                      , stampSha256 = "e65a19d57fb213bb218de51427ebbbf3c435a34a9574ee5da50b056bec5c6968"
                      }
                )
    , testCase "algorithm version 1 counts exactly these extensions and reads exactly these roots" $ do
        -- Any change here changes what every committed standing transcript means, so
        -- it must come with a bump of the algorithm version and a new golden digest.
        sourceDigestAlgorithm @?= 1
        sourceDigestExtensions
          @?= [ ".hs"
              , ".hsc"
              , ".hs-boot"
              , ".c"
              , ".h"
              , ".txt"
              , ".md"
              , ".yaml"
              , ".yml"
              , ".json"
              , ".dhall"
              , ".cabal"
              , ".project"
              ]
        sourceDigestDirectoryRoots @?= ["app", "gen", "src", "test"]
        sourceDigestFileRoots @?= ["cabal.project", "jitml.cabal"]
    , testCase "the pure digest is independent of the order files are supplied in" $
        sourceStampFromFiles baseTree @?= sourceStampFromFiles (reverse baseTree)
    , testCase "the algorithm version and a 64-digit digest are recorded" $ do
        let stamp = sourceStampFromFiles baseTree
        stampAlgorithm stamp @?= 1
        assertBool
          "64 lowercase hex digits"
          ( Text.length (stampSha256 stamp) == 64
              && Text.all (`elem` ("0123456789abcdef" :: String)) (stampSha256 stamp)
          )
    , testCase "CRLF and LF checkouts of the same file digest identically, a lone CR does not" $ do
        let crlf = [("src/A.hs", "a\r\nb\r\n")]
            lf = [("src/A.hs", "a\nb\n")]
            lone = [("src/A.hs", "a\rb\r")]
        sourceStampFromFiles crlf @?= sourceStampFromFiles lf
        assertBool
          "a lone carriage return is content"
          (sourceStampFromFiles lone /= sourceStampFromFiles lf)
    , testCase "content, path, and file boundaries all move the digest" $ do
        let stamp = sourceStampFromFiles [("src/A.hs", "bc")]
        assertBool "content" (stamp /= sourceStampFromFiles [("src/A.hs", "bd")])
        assertBool "path" (stamp /= sourceStampFromFiles [("src/B.hs", "bc")])
        assertBool
          "a byte moved across a file boundary"
          (sourceStampFromFiles [("a", "bc")] /= sourceStampFromFiles [("ab", "c")])
    , testCase "the digest is the same wherever the tree is checked out and however it was created" $
        withSystemTempDirectory "jitml-digest-a" $ \first ->
          withSystemTempDirectory "jitml-digest-b" $ \second -> do
            writeTree first baseTree
            writeTree second (reverse baseTree)
            firstStamp <- stampIn first
            secondStamp <- stampIn second
            firstStamp @?= secondStamp
            firstStamp @?= sourceStampFromFiles baseTree
    , testCase "files outside the counted set cannot move the digest" $
        withSystemTempDirectory "jitml-digest" $ \root -> do
          writeTree root baseTree
          before <- stampIn root
          writeTree
            root
            [ ("src/JitML/A.o", "object")
            , ("src/.hidden.hs", "hidden")
            , ("src/.git/config.hs", "hidden dir")
            , ("src/notes", "no extension")
            , ("src/JitML/gen.cc", "excluded by dockerignore")
            , ("docs/extra.hs", "not a code root")
            ]
          after <- stampIn root
          after @?= before
    , testCase "a counted change moves the digest" $
        withSystemTempDirectory "jitml-digest" $ \root -> do
          writeTree root baseTree
          before <- stampIn root
          writeTree root [("src/JitML/Deep/B.hs", "module JitML.Deep.B where\n-- edited\n")]
          after <- stampIn root
          assertBool "the digest moved" (after /= before)
    , testCase "the generated protocol modules under gen are counted like any other source" $
        withSystemTempDirectory "jitml-digest" $ \root -> do
          writeTree root baseTree
          before <- stampIn root
          writeTree root [("gen/Proto/Jitml/Gen.hs", "module Proto.Jitml.Gen where\n-- regenerated\n")]
          after <- stampIn root
          assertBool "the digest moved" (after /= before)
    , testCase "a missing root is reported, not digested around" $ do
        withSystemTempDirectory "jitml-digest" $ \root -> do
          writeTree root (filter ((/= "app/Main.hs") . fst) baseTree)
          computeSourceStampIn root >>= (@?= Left "missing code root: app")
        withSystemTempDirectory "jitml-digest" $ \root -> do
          writeTree root (filter ((/= "gen/Proto/Jitml/Gen.hs") . fst) baseTree)
          computeSourceStampIn root >>= (@?= Left "missing code root: gen")
        withSystemTempDirectory "jitml-digest" $ \root -> do
          writeTree root (filter ((/= "jitml.cabal") . fst) baseTree)
          computeSourceStampIn root >>= (@?= Left "missing code root: jitml.cabal")
    , testCase "the roots cover every hs-source-dirs entry of the cabal package and both project files" $ do
        -- Written against the cabal file, not against the digest module, so a new
        -- source directory added to any stanza fails here until it is a root.
        cabal <- Text.IO.readFile "jitml.cabal"
        let declared =
              nub
                [ Text.unpack (Text.takeWhile (/= '/') entry)
                | line <- Text.lines cabal
                , Just rest <- [Text.stripPrefix "hs-source-dirs:" (Text.strip line)]
                , entry <- Text.words (Text.replace "," " " rest)
                ]
        assertBool "the cabal file declares source directories" (length declared >= 4)
        forM_ declared $ \root ->
          assertBool
            ("source directory " <> root <> " is compiled into a stanza but is not a digest root")
            (root `elem` sourceDigestDirectoryRoots)
        sort sourceDigestDirectoryRoots @?= sort declared
        sourceDigestFileRoots @?= ["cabal.project", "jitml.cabal"]
    , testCase "a symbolic link under a root is rejected" $
        withSystemTempDirectory "jitml-digest" $ \root -> do
          writeTree root baseTree
          createFileLink (root </> "app/Main.hs") (root </> "src/JitML/Link.hs")
          result <- computeSourceStampIn root
          case result of
            Left reason ->
              assertBool
                "names the link"
                ("symbolic link under a code root: src/JitML/Link.hs" `Text.isPrefixOf` reason)
            Right _ -> assertFailure "a symbolic link was digested"
    , testCase "the real code roots digest, and digest identically twice" $ do
        first <- computeSourceStampIn "."
        second <- computeSourceStampIn "."
        assertBool "the worktree digests" (isRight' first)
        first @?= second
    ]
 where
  isRight' (Right _) = True
  isRight' (Left _) = False

-- ---------------------------------------------------------------------------
-- What jitml test writes
-- ---------------------------------------------------------------------------

transcriptFixture :: Text -> Text -> Text -> ProcessTranscript
transcriptFixture command out err =
  ProcessTranscript
    { processTranscriptCommand = command
    , processTranscriptStdout = out
    , processTranscriptStderr = err
    , processTranscriptWorkingDirectory = Nothing
    , processTranscriptDuration = ProcessDuration 5
    }

baselineFixture :: ValidationEvidence.ValidationBaseline
baselineFixture =
  ValidationEvidence.ValidationBaseline
    { ValidationEvidence.baselineSubstrate = LinuxCPU
    , ValidationEvidence.baselineExecutableSha256 = digestOf 'e'
    , ValidationEvidence.baselineSource = fixtureStamp
    }

journalFixture :: Report.InvocationJournal
journalFixture =
  foldl
    Report.appendInvocation
    Report.emptyInvocationJournal
    [ Report.passedInvocation
        "jitml-unit"
        (transcriptFixture "cabal test jitml-unit" "All 3 tests passed\n" "")
    , case mkProcessFailure (ExitFailure 3) (transcriptFixture "cabal test jitml-integration" "out\n" "err\n") of
        Just failure -> Report.failedObservedInvocation "jitml-integration" (ObservedProcessExitFailure failure)
        Nothing -> error "a non-zero exit is a failure"
    , Report.failedObservedInvocation
        "jitml-backends"
        ( ObservedProcessAttemptFailure
            ProcessAttemptFailure
              { processAttemptFailureCommand = "cabal test jitml-backends"
              , processAttemptFailureStdout = Nothing
              , processAttemptFailureStderr = Just "partial"
              , processAttemptFailureWorkingDirectory = Nothing
              , processAttemptFailureDuration = ProcessDuration 1
              , processAttemptFailureException = "  "
              }
        )
    , Report.notRunObservedInvocation
        "jitml-e2e"
        "cabal test jitml-e2e"
        "jitml-integration"
        ( ObservedProcessExitFailure
            ( either
                (error "no failure")
                id
                ( maybe
                    (Left ())
                    Right
                    (mkProcessFailure (ExitFailure 3) (transcriptFixture "cabal test jitml-integration" "" ""))
                )
            )
        )
    , Report.notRunAfterRefinement
        "jitml-model-convergence"
        "cabal test jitml-model-convergence"
        "jitml-e2e"
        "journal"
        "no journal was produced"
    , Report.passedInvocation "not-a-gate" (transcriptFixture "cabal test not-a-gate" "" "")
    ]

-- | Run an action with a diagnostic sink and return what it reported, in order.
collectingReports :: ((Text -> IO ()) -> IO ()) -> IO [Text]
collectingReports action = do
  reported <- newIORef []
  action (\message -> modifyIORef' reported (message :))
  reverse <$> readIORef reported

jitmlTestRecordTests :: TestTree
jitmlTestRecordTests =
  testGroup
    "jitml test writes validation records"
    [ testCase "every gate invocation becomes one record and other stanzas are skipped" $ do
        let built = ValidationEvidence.invocationRecords baselineFixture journalFixture
        length built @?= 5
        forM_ built $ \entry -> assertBool ("built: " <> show entry) (either (const False) (const True) entry)
    , testCase "a passed run keeps the digests of its streams, not the streams" $ do
        records <- requireRecords
        case List.find ((== JitmlUnit) . Record.validationRecordGate) records of
          Nothing -> assertFailure "no jitml-unit record"
          Just record -> do
            Record.validationRecordCommand record @?= "cabal test jitml-unit"
            Record.validationRecordSubstrate record @?= LinuxCPU
            Record.validationRecordExecutableSha256 record @?= digestOf 'e'
            Record.validationRecordSource record @?= fixtureStamp
            Record.validationRecordEvidence record
              @?= EvidencePassed
                (Record.sha256Hex (Text.Encoding.encodeUtf8 "All 3 tests passed\n"))
                (Record.sha256Hex "")
    , testCase "a failed run retains the exit code and both complete streams" $ do
        records <- requireRecords
        fmap
          Record.validationRecordEvidence
          (List.find ((== JitmlIntegration) . Record.validationRecordGate) records)
          @?= Just
            ( EvidenceFailed
                FailedEvidence
                  { failedExitCode = Just 3
                  , failedStdout = Just "out\n"
                  , failedStderr = Just "err\n"
                  , failedException = Nothing
                  }
            )
    , testCase "a runner exception keeps its text, and an unavailable stream stays unavailable" $ do
        records <- requireRecords
        fmap
          Record.validationRecordEvidence
          (List.find ((== JitmlBackends) . Record.validationRecordGate) records)
          @?= Just
            ( EvidenceFailed
                FailedEvidence
                  { failedExitCode = Nothing
                  , failedStdout = Nothing
                  , failedStderr = Just "partial"
                  , failedException = Just "the runner raised without exception text"
                  }
            )
    , testCase "a fail-fast suffix stays NotRun with the exact command that would have run" $ do
        records <- requireRecords
        let notRun = List.find ((== JitmlE2e) . Record.validationRecordGate) records
        fmap Record.validationRecordCommand notRun @?= Just "cabal test jitml-e2e"
        fmap Record.validationRecordEvidence notRun
          @?= Just (EvidenceNotRun "jitml-integration" "cabal test jitml-integration")
        fmap
          Record.validationRecordEvidence
          (List.find ((== JitmlModelConvergence) . Record.validationRecordGate) records)
          @?= Just (EvidenceNotRun "jitml-e2e" "journal: no journal was produced")
    , testCase "an entry the record constructor refuses is reported with its stanza" $ do
        let journal =
              Report.appendInvocation
                Report.emptyInvocationJournal
                (Report.passedInvocation "jitml-unit" (transcriptFixture "line\nbreak" "" ""))
        case ValidationEvidence.invocationRecords baselineFixture journal of
          [Left reason] -> assertBool "names the stanza" ("jitml-unit:" `Text.isPrefixOf` reason)
          other -> assertFailure ("expected one refusal, got " <> show other)
    , testCase "records are written per gate and substrate, and admit, with nothing reported" $
        withSystemTempDirectory "jitml-validation-write" $ \directory -> do
          reports <- collectingReports $ \report ->
            ValidationEvidence.writeValidationRecordsWith
              report
              (pure (Right fixtureStamp))
              directory
              (Just (Right baselineFixture))
              journalFixture
          reports @?= []
          written <- sort <$> listDirectory directory
          written
            @?= [ "jitml-backends.linux-cpu.json"
                , "jitml-e2e.linux-cpu.json"
                , "jitml-integration.linux-cpu.json"
                , "jitml-model-convergence.linux-cpu.json"
                , "jitml-unit.linux-cpu.json"
                ]
          forM_ written $ \name -> do
            bytes <- ByteString.readFile (directory </> name)
            assertBool
              (name <> " admits")
              (either (const False) (const True) (Record.admitValidationRecord bytes))
    , testCase "nothing is written, and the reason is reported, when the tree changed while the gates ran" $
        withSystemTempDirectory "jitml-validation-write" $ \directory -> do
          reports <- collectingReports $ \report ->
            ValidationEvidence.writeValidationRecordsWith
              report
              (pure (Right otherStamp))
              directory
              (Just (Right baselineFixture))
              journalFixture
          reports @?= ["validation records not written: the source tree changed while the gates ran"]
          listDirectory directory >>= (@?= [])
    , testCase
        "nothing is written when the stamp cannot be recomputed, the baseline failed, or no lane was selected"
        $ withSystemTempDirectory "jitml-validation-write"
        $ \directory -> do
          unreadable <- collectingReports $ \report ->
            ValidationEvidence.writeValidationRecordsWith
              report
              (pure (Left "unreadable"))
              directory
              (Just (Right baselineFixture))
              journalFixture
          unreadable @?= ["validation records not written: unreadable"]
          failedBaseline <- collectingReports $ \report ->
            ValidationEvidence.writeValidationRecordsWith
              report
              (pure (Right fixtureStamp))
              directory
              (Just (Left "no executable digest"))
              journalFixture
          failedBaseline @?= ["validation records not written: no executable digest"]
          noLane <- collectingReports $ \report ->
            ValidationEvidence.writeValidationRecordsWith
              report
              (pure (Right fixtureStamp))
              directory
              Nothing
              journalFixture
          noLane @?= []
          listDirectory directory >>= (@?= [])
    , testCase
        "an entry the record constructor refuses is skipped with its reason and the rest are still written"
        $ withSystemTempDirectory "jitml-validation-write"
        $ \directory -> do
          let journal =
                foldl
                  Report.appendInvocation
                  Report.emptyInvocationJournal
                  [ Report.passedInvocation "jitml-integration" (transcriptFixture "line\nbreak" "" "")
                  , Report.passedInvocation "jitml-unit" (transcriptFixture "cabal test jitml-unit" "ok\n" "")
                  ]
          reports <- collectingReports $ \report ->
            ValidationEvidence.writeValidationRecordsWith
              report
              (pure (Right fixtureStamp))
              directory
              (Just (Right baselineFixture))
              journal
          fmap (Text.takeWhile (/= ':')) reports @?= ["validation record skipped"]
          listDirectory directory >>= (@?= ["jitml-unit.linux-cpu.json"])
    , testCase "a record's stamp is the one taken before the run" $ do
        records <- requireRecords
        forM_ records $ \record -> Record.validationRecordSource record @?= stampAt baselineFixture
    , testGroup
        "an environment that changes the run is not a standing invocation"
        [ testCase "variables that drop tests or weaken them are named, sorted" $ do
            ValidationEvidence.runAlteringEnvironment [("TASTY_PATTERN", "$0 !~ /x/"), ("PATH", "/bin")]
              @?= ["TASTY_PATTERN"]
            ValidationEvidence.runAlteringEnvironment
              [("TASTY_TIMEOUT", "1s"), ("TASTY_QUICKCHECK_TESTS", "1"), ("TASTY_PATTERN", "p")]
              @?= ["TASTY_PATTERN", "TASTY_QUICKCHECK_TESTS", "TASTY_TIMEOUT"]
        , testCase "presentational variables, empty values, and unrelated variables are not" $
            ValidationEvidence.runAlteringEnvironment
              [ ("TASTY_COLOR", "never")
              , ("TASTY_HIDE_SUCCESSES", "true")
              , ("TASTY_NUM_THREADS", "4")
              , ("TASTY_ANSI_TRICKS", "false")
              , ("TASTY_PATTERN", "")
              , ("JITML_SUBSTRATE", "linux-cpu")
              , ("MY_TASTY_PATTERN", "x")
              ]
              @?= []
        , testCase "the baseline refuses to start under such an environment and names the variable" $
            withEnvironmentVariable "TASTY_PATTERN" "$0 !~ /Phase 276/" $ do
              baseline <- ValidationEvidence.captureValidationBaseline (Just LinuxCPU)
              case baseline of
                Just (Left reason) ->
                  assertBool "names the variable" ("TASTY_PATTERN" `Text.isInfixOf` reason)
                other ->
                  assertFailure
                    ("expected a refused baseline, got " <> show (fmap (either Just (const Nothing)) other))
        , testCase "an unflagged run still yields no baseline under such an environment" $
            withEnvironmentVariable "TASTY_PATTERN" "x" $ do
              baseline <- ValidationEvidence.captureValidationBaseline Nothing
              assertBool "no baseline" (null baseline)
        ]
    ]
 where
  requireRecords =
    case sequence (ValidationEvidence.invocationRecords baselineFixture journalFixture) of
      Left reason -> assertFailure (Text.unpack reason) >> pure []
      Right records -> pure records
  stampAt = ValidationEvidence.baselineSource

-- | Run an action with one environment variable set, restoring its previous value
-- (or absence) afterwards. The unit stanza reads no @TASTY_*@ variable after start-up,
-- so setting one here cannot change how the surrounding tests run.
withEnvironmentVariable :: String -> String -> IO a -> IO a
withEnvironmentVariable name value action =
  bracket
    (lookupEnv name <* setEnv name value)
    (maybe (unsetEnv name) (setEnv name))
    (const action)

-- ---------------------------------------------------------------------------
-- The thin Closure Status cap and the status report
-- ---------------------------------------------------------------------------

readmeWith :: Int -> Text
readmeWith bodyLines =
  Text.unlines
    ( ["# Plan", "", "## Standards", "", "## Closure Status"]
        <> replicate bodyLines "line"
        <> ["", "## Historical Current-Status Diary", "", "old narrative"]
    )

closureStatusCapTests :: TestTree
closureStatusCapTests =
  testGroup
    "thin Closure Status"
    [ testCase "the section length counts its heading and stops at the next level-two heading" $ do
        -- heading + 4 body lines + the blank line before the next heading
        PlanDoc.closureStatusSectionLength (readmeWith 4) @?= Just 6
        PlanDoc.closureStatusSectionLength "# Plan\n\n## Other\n" @?= Nothing
    , testCase "a section over the cap is a drift naming both numbers" $
        case DocsCheck.closureStatusDrifts (Just 5) "DEVELOPMENT_PLAN/README.md" (readmeWith 4) of
          [drift] -> do
            DocsCheck.driftKey drift @?= "closure-status.length"
            DocsCheck.driftPath drift @?= "DEVELOPMENT_PLAN/README.md"
            assertBool
              "the reason states the length and the cap"
              ( "6 lines" `Text.isInfixOf` DocsCheck.driftReason drift
                  && "cap of 5" `Text.isInfixOf` DocsCheck.driftReason drift
              )
          other -> assertFailure ("expected one drift, got " <> show other)
    , testCase "a section at or under the cap is accepted" $ do
        DocsCheck.closureStatusDrifts (Just 6) "README.md" (readmeWith 4) @?= []
        DocsCheck.closureStatusDrifts (Just 60) "README.md" (readmeWith 4) @?= []
    , testCase "a README with no Closure Status section is a drift once the cap is on" $
        fmap DocsCheck.driftKey (DocsCheck.closureStatusDrifts (Just 60) "README.md" "# Plan\n\n## Other\n")
          @?= ["closure-status.length"]
    , testCase "with the cap off nothing is enforced, however long the section is" $
        DocsCheck.closureStatusDrifts Nothing "README.md" (readmeWith 5000) @?= []
    , testCase "the cap is configured in one constant and the real README is checked against it" $ do
        content <- Text.IO.readFile ("DEVELOPMENT_PLAN" </> "README.md")
        DocsCheck.closureStatusDrifts PlanDoc.closureStatusLineCap "DEVELOPMENT_PLAN/README.md" content
          @?= []
        -- Whatever the cap is today, the real section is one the check can measure, so
        -- setting the constant enforces it on this README rather than on nothing.
        assertBool
          "the real README has a measurable Closure Status section"
          (isJust (PlanDoc.closureStatusSectionLength content))
    ]

statusReportRenderTests :: TestTree
statusReportRenderTests =
  testGroup
    "docs status report"
    [ testCase "renders the tally, legacy disclosure, open chain, verdict, and every unmet obligation" $ do
        let rendered = Evidence.renderStatusReport (PhaseStatus.projectProductStatus todayIndex)
            renderedLines = Text.lines rendered
        take 5 renderedLines
          @?= [ "status: 63 Done / 1 Active / 0 Planned / 6 Blocked across 70 sprints"
              , "legacy attested: 63 sprint(s), frozen and shrink-only; legacy attestation never mints a Done"
              , "open chain: 278 -> 280 -> 281 -> 282 -> 285 -> 288 -> 289"
              , "closure: refused (" <> countText rendered <> " unmet obligations)"
              , "docs check and check-code are computed when they run, never attested"
              ]
        assertBool "278.1 is listed Active" ("sprint 278.1 Active - " `Text.isInfixOf` rendered)
        assertBool
          "proven CUDA journal is listed as proven"
          ("  proven  lane-journal linux-cuda: cuda journal" `Text.isInfixOf` rendered)
        assertBool
          "stale CPU lane is listed as unmet"
          ("  unmet   lane-journal linux-cpu: stale: " `Text.isInfixOf` rendered)
        assertBool
          "the external obligation is listed"
          ("external: Apple Silicon execution context" `Text.isInfixOf` rendered)
        assertBool
          "standing obligations are listed"
          ("standing obligations guard the closure verdict:" `Text.isInfixOf` rendered)
    , testCase "rendering is deterministic" $
        Evidence.renderStatusReport (PhaseStatus.projectProductStatus todayIndex)
          @?= Evidence.renderStatusReport (PhaseStatus.projectProductStatus todayIndex)
    , testCase "a closed report says so and still discloses its legacy sprints" $ do
        let rendered = Evidence.renderStatusReport (projectClosable allProvenIndex)
        assertBool
          "closed"
          ( "closure: closed on machine evidence (63 legacy-attested sprints disclosed)"
              `Text.isInfixOf` rendered
          )
        assertBool "no open chain" ("open chain: (none)" `Text.isInfixOf` rendered)
    ]
 where
  countText rendered =
    case [ Text.takeWhile (/= ' ') (Text.drop (Text.length "closure: refused (") line)
         | line <- Text.lines rendered
         , "closure: refused (" `Text.isPrefixOf` line
         ] of
      count : _ -> count
      [] -> "?"

-- ---------------------------------------------------------------------------
-- The one real-file admission test
-- ---------------------------------------------------------------------------

realFileTests :: TestTree
realFileTests =
  testGroup
    "committed evidence"
    [ testCase "the committed linux-cuda journal admits, and a contract-tampered copy is Stale" $ do
        input <-
          case [i | i <- Aggregate.productLaneInputs, productLaneInputSubstrate i == LinuxCUDA] of
            i : _ -> pure i
            [] -> assertFailure "no linux-cuda lane input is registered" >> fail "unreachable"
        bytes <- ByteString.readFile (productLaneInputPath input)
        case Loader.judgeLaneJournalBytes input bytes of
          Proven (evidence :| []) -> do
            evidenceSubject evidence @?= Text.pack (productLaneInputPath input)
            evidenceDigest evidence @?= Just (productLaneInputSha256 input)
          other -> assertFailure ("the committed CUDA journal did not admit: " <> show other)
        raw <- either failTest pure (eitherDecodeStrict' bytes)
        (rowId, originalDigest) <- firstRowFields raw
        let tampered = canonicalJournal (setFirstRowField "contract_sha256" (String zeroDigest) raw)
            repinned = input {productLaneInputSha256 = Record.sha256Hex tampered}
        assertBool "the mutation changed the bytes" (tampered /= bytes)
        -- The disk loader reads the same bytes from below a root and judges them the
        -- same way, and an absent journal is Missing rather than proven or skipped.
        withSystemTempDirectory "jitml-lane" $ \root -> do
          Loader.loadLaneJournalIn root input
            >>= (@?= (LinuxCUDA, unproven (Missing (Text.pack (productLaneInputPath input)))))
          writeTree root [(productLaneInputPath input, bytes)]
          Loader.loadLaneJournalIn root input
            >>= (@?= (LinuxCUDA, Loader.judgeLaneJournalBytes input bytes))
          writeTree root [(productLaneInputPath input, tampered)]
          Loader.loadLaneJournalIn root repinned
            >>= ( @?=
                    ( LinuxCUDA
                    , unproven (Stale ("linux-cuda " <> rowId <> " contract_sha256") originalDigest zeroDigest)
                    )
                )
        case Loader.judgeLaneJournalBytes repinned tampered of
          Unproven reasons ->
            -- Exactly one reason, typed Stale, carrying what the current projection
            -- requires (the untampered digest) and what the journal now carries.
            reasons
              @?= Stale ("linux-cuda " <> rowId <> " contract_sha256") originalDigest zeroDigest
              :| []
          Proven _ -> assertFailure "a journal issued under another contract was proven"
        -- The typed constructor is what the production reader produced.
        case Product.projectProductRows LinuxCUDA Product.allProductRows of
          Failure errors -> assertFailure (show errors)
          Success batch ->
            case Lane.admitProductLaneJournal (Record.sha256Hex tampered) batch tampered of
              Left errors ->
                errors
                  @?= Lane.ProductLaneJournalContractStale rowId originalDigest zeroDigest
                  :| []
              Right _ -> assertFailure "the reader admitted a contract-tampered journal"
    ]
 where
  canonicalJournal value = LazyByteString.toStrict (encode value) <> "\n"
  firstRowFields raw =
    case fieldOf "rows" raw of
      Just (Array rows) | Just row <- rows Vector.!? 0 ->
        case (fieldOf "row_id" row, fieldOf "contract_sha256" row) of
          (Just (String rowId), Just (String digest)) -> pure (rowId, digest)
          _ -> assertFailure "the first row has no row_id and contract_sha256" >> fail "unreachable"
      _ -> assertFailure "the journal has no rows" >> fail "unreachable"
  setFirstRowField field value raw =
    case fieldOf "rows" raw of
      Just (Array rows) ->
        setField
          "rows"
          (Array (Vector.imap (\index row -> if index == 0 then setField field value row else row) rows))
          raw
      _ -> raw

-- ---------------------------------------------------------------------------
-- The registry group (rewritten from the six-case test-local group)
-- ---------------------------------------------------------------------------

-- | Read each catalogue phase document, in catalogue order.
readPhaseDocuments :: IO [(PhaseEntry, Text)]
readPhaseDocuments =
  traverse
    (\phase -> (,) phase <$> Text.IO.readFile (entryPhaseDocument phase))
    PhaseStatus.productStatusCatalogue

productPhaseStatusRegistryTests :: TestTree
productPhaseStatusRegistryTests =
  testGroup
    "Product phase status registry (Phase 221)"
    [ testCase "enumerates product phases 220 through 289" $ do
        PhaseStatus.productPhaseNumbers @?= [220 .. 289]
        PhaseStatus.validateProductStatusCatalogue @?= []
        PhaseStatus.validateProductPhaseStatuses
          (PhaseStatus.productPhaseStatuses (PhaseStatus.projectProductStatus todayIndex))
          @?= []
    , testCase "the derived registry reproduces 63 Done / 1 Active / 0 Planned / 6 Blocked from evidence" $ do
        let report = PhaseStatus.projectProductStatus todayIndex
        Evidence.statusCounts report
          @?= StatusCounts {countDone = 63, countActive = 1, countPlanned = 0, countBlocked = 6}
        [ status
          | (sprint, status) <- statuses report
          , sprint `elem` ["278.1", "280.1", "281.1", "282.1", "285.1", "288.1", "289.1"]
          ]
          @?= [Active, Blocked, Blocked, Blocked, Blocked, Blocked, Blocked]
    , testCase "the open chain 278 -> 280 -> 281 -> 282 -> 285 -> 288 -> 289 is derived, not typed" $ do
        let report = PhaseStatus.projectProductStatus todayIndex
        Evidence.openChain report @?= ["278.1", "280.1", "281.1", "282.1", "285.1", "288.1", "289.1"]
        mapMaybe Evidence.sprintPhaseNumber (Evidence.openChain report)
          @?= [278, 280, 281, 282, 285, 288, 289]
        -- With no evidence at all the chain is the same: nothing typed keeps it.
        Evidence.openChain (PhaseStatus.projectProductStatus Evidence.emptyEvidenceIndex)
          @?= Evidence.openChain report
        -- And it moves with the evidence: proving 278.1 leaves 280.1 next.
        let progressed =
              PhaseStatus.projectProductStatus
                todayIndex
                  { indexLanes = Map.fromList [(lane, proven "lane") | lane <- allSubstrates]
                  , indexAggregate = Just (proven "aggregate")
                  , indexTranscripts =
                      Map.singleton (JitmlUnit, LinuxCPU) (TranscriptEvidence (proven "unit") (Just fixtureStamp))
                  }
        -- 278.1 still owns an external prerequisite, so it stays open: the chain
        -- head does not move on lane journals alone.
        take 1 (Evidence.openChain progressed) @?= ["278.1"]
    , testCase "reports incomplete while any product sprint is open" $ do
        let open = PhaseStatus.productPhaseStatuses (PhaseStatus.projectProductStatus todayIndex)
            closed = PhaseStatus.productPhaseStatuses (projectClosable allProvenIndex)
        assertBool "today's evidence leaves sprints open" (not (PhaseStatus.productPhasesDone open))
        assertBool "all-proven evidence completes every sprint" (PhaseStatus.productPhasesDone closed)
        assertBool
          "one unproven sprint again leaves the registry incomplete"
          ( not
              ( PhaseStatus.productPhasesDone
                  ( PhaseStatus.productPhaseStatuses
                      ( projectClosable
                          allProvenIndex {indexLanes = Map.delete LinuxCPU (indexLanes allProvenIndex)}
                      )
                  )
              )
          )
    , testCase
        "matches the sprint Status headers in phase documents and the evidence committed in the worktree"
        $ do
          report <- Loader.loadProductStatusReport
          documents <- readPhaseDocuments
          DocsCheck.statusProjectionDrifts report [(phase, Just content) | (phase, content) <- documents]
            @?= []
    , testCase "every dependency edge is forward-only (rule M(a))" $ do
        documents <- readPhaseDocuments
        forM_ documents $ \(_, content) ->
          forM_ (PlanDoc.parsePlanSprintFacts content) $ \facts ->
            forM_ (PlanDoc.psfBlockedBy facts) $ \reference ->
              assertBool
                ( Text.unpack (PlanDoc.psfId facts)
                    <> " declares a backward Blocked-by edge to higher-numbered "
                    <> Text.unpack reference
                )
                (PlanDoc.compareDottedId reference (PlanDoc.psfId facts) == LT)
    , testCase "every sprint declares a concrete validation gate" $ do
        documents <- readPhaseDocuments
        forM_ documents $ \(_, content) ->
          forM_ (PlanDoc.parsePlanSprintFacts content) $ \facts ->
            assertBool
              (Text.unpack (PlanDoc.psfId facts) <> " has no non-empty ### Validation gate")
              (PlanDoc.psfHasValidationGate facts)
    , testCase "no sprint validation requires both accelerators (rule M(b))" $ do
        documents <- readPhaseDocuments
        forM_ documents $ \(_, content) ->
          forM_ (PlanDoc.parsePlanSprintFacts content) $ \facts ->
            assertBool
              ( Text.unpack (PlanDoc.psfId facts)
                  <> " validation names both a linux-cuda and an apple-silicon lane"
              )
              (not (PlanDoc.psfValidationNamesCuda facts && PlanDoc.psfValidationNamesApple facts))
    , testCase
        "every phase document satisfies the plan-structure rules and cites a closure section it contains"
        $ do
          report <- Loader.loadProductStatusReport
          documents <- readPhaseDocuments
          forM_ documents $ \(phase, content) -> do
            let projections =
                  [ p | p <- reportProjections report, projectionSprint p `elem` fmap entrySprintId (entrySprints phase)
                  ]
            fmap PlanDoc.issueKey (PlanDoc.planDocumentIssues projections content) @?= []
    ]

-- ---------------------------------------------------------------------------
-- The composed docs check, run over a fixture repository
-- ---------------------------------------------------------------------------

-- | A plan document that says what a projection derives: the status word in the
-- three places the parser reads, the upstream sprints a Blocked sprint waits on,
-- remaining work when Active, the gate lines a sprint owns, and the closure section
-- a legacy sprint cites. @claimed@ is the status the document asserts, which a
-- lying-header case sets to something the evidence does not derive.
planDocumentFor :: PhaseEntry -> SprintProjection -> SprintStatus -> Text
planDocumentFor phase projection claimed =
  renderDoc
    baseDoc
      { docPhase = entryPhaseNumber phase
      , docTitle = entryPhaseTitle phase
      , docSprint = projectionSprint projection
      , docStatus = word
      , docHeading = word
      , docPhaseState = word
      , docBlockedBy =
          if claimed == Blocked
            then Just ("**Blocked by**: " <> blockers)
            else Nothing
      , docRemaining =
          if claimed == Active
            then Just ["- Land the evidence."]
            else Nothing
      , docValidation = ["```bash"] <> gateLines <> ["```"]
      , docSections = [Evidence.citedSection citation | claimed == Done, Just citation <- [legacyCitation]]
      }
 where
  word = Evidence.renderSprintStatus claimed
  checked =
    case projectionBasis projection of
      BasisEvidence _ obligations -> obligations
      BasisLegacy _ -> []
  legacyCitation =
    case projectionBasis projection of
      BasisLegacy citation -> Just citation
      BasisEvidence _ _ -> Nothing
  awaited = [upstream | (Evidence.UpstreamSprint upstream, Unproven _) <- checked]
  blockers
    | null awaited = "an external prerequisite"
    | otherwise = Text.intercalate ", " ["Sprint `" <> upstream <> "`" | upstream <- awaited]
  gateLines =
    case [ "docker compose run --rm jitml jitml test "
             <> Record.renderValidationGate gate
             <> " --"
             <> renderSubstrate lane
         | (obligation, _) <- checked
         , Just (gate, lane) <- [gateOf obligation]
         ] of
      [] -> ["docker compose run --rm jitml jitml docs check"]
      gates -> gates
  gateOf (GateTranscript gate lane) = Just (gate, lane)
  gateOf (StandingGate gate lane) = Just (gate, lane)
  gateOf _ = Nothing

-- | Every catalogue phase's document, agreeing with the report.
planTreeFor :: StatusReport -> [(FilePath, ByteString)]
planTreeFor report =
  [ ( entryPhaseDocument phase
    , Text.Encoding.encodeUtf8 (planDocumentFor phase projection (projectionStatus projection))
    )
  | phase <- PhaseStatus.productStatusCatalogue
  , projection <- reportProjections report
  , projectionSprint projection `elem` fmap entrySprintId (entrySprints phase)
  ]

-- | The catalogue entry of a product phase.
phaseEntryFor :: Int -> PhaseEntry
phaseEntryFor number =
  case [phase | phase <- PhaseStatus.productStatusCatalogue, entryPhaseNumber phase == number] of
    phase : _ -> phase
    [] -> error ("the catalogue has no phase " <> show number)

-- | The projection of one sprint of a report.
projectionOf :: StatusReport -> Text -> SprintProjection
projectionOf report sprint =
  case [p | p <- reportProjections report, projectionSprint p == sprint] of
    found : _ -> found
    [] -> error ("the report has no sprint " <> Text.unpack sprint)

-- | A fixture repository whose phase documents agree with the projection of the
-- real catalogue over the evidence committed in it (none). The action receives the
-- root and the projection.
withPlanTree :: (FilePath -> StatusReport -> IO a) -> IO a
withPlanTree action =
  withSystemTempDirectory "jitml-docs-check" $ \root -> do
    report <- Loader.loadProductStatusReportIn root
    writeTree root (planTreeFor report)
    action root report

-- | The production check pointed at a fixture root, reading that root's evidence.
fixtureEnvironment :: FilePath -> DocsCheckEnvironment
fixtureEnvironment root =
  DocsCheckEnvironment
    { docsRoot = root
    , docsClosureStatusLineCap = Nothing
    , docsCatalogueProblems = PhaseStatus.validateProductStatusCatalogue
    , docsStatusReport = Loader.loadProductStatusReportIn root
    }

-- | The drift families the status projection owns. The composed check also reports
-- generated-section, metadata, and link drifts, and a fixture tree holds none of
-- the files those compare with, so those are noise here and every assertion
-- filters them out.
statusDriftFamilies :: [Text]
statusDriftFamilies =
  [ "status-projection."
  , "plan-structure."
  , "status-catalogue."
  , "validation-record."
  , "closure-claim."
  , "closure-status."
  ]

statusDrifts :: [DocsCheck.DocsDrift] -> [DocsCheck.DocsDrift]
statusDrifts drifts =
  [ drift
  | drift <- drifts
  , any (`Text.isPrefixOf` DocsCheck.driftKey drift) statusDriftFamilies
  ]

driftKeysOf :: [DocsCheck.DocsDrift] -> [Text]
driftKeysOf = fmap DocsCheck.driftKey . statusDrifts

claimDocumentPath :: FilePath
claimDocumentPath = "documents/engineering/product_completion_contract.md"

claimDocument :: (FilePath, ByteString)
claimDocument =
  (claimDocumentPath, Text.Encoding.encodeUtf8 (Text.unlines ["# Claim", "", productionReadyClaim]))

docsCheckCompositionTests :: TestTree
docsCheckCompositionTests =
  testGroup
    "docs check composition"
    [ testCase "a tree whose plan documents agree with the projection has no status drift" $
        withPlanTree $ \root report -> do
          Evidence.statusCounts report
            @?= StatusCounts {countDone = 63, countActive = 1, countPlanned = 0, countBlocked = 6}
          length (planTreeFor report) @?= 70
          drifts <- DocsCheck.checkDocsWith (fixtureEnvironment root)
          driftKeysOf drifts @?= []
    , testCase "a closure claim is refused through the composed check while the verdict is refused" $
        withPlanTree $ \root report -> do
          assertBool "the fixture verdict refuses" (isRefusedVerdict (reportVerdict report))
          writeTree root [claimDocument]
          drifts <- DocsCheck.checkDocsWith (fixtureEnvironment root)
          case statusDrifts drifts of
            [drift] -> do
              DocsCheck.driftKey drift @?= "closure-claim.production-ready"
              DocsCheck.driftPath drift @?= claimDocumentPath
              assertBool
                "the reason names the refused verdict"
                ("closure is refused" `Text.isInfixOf` DocsCheck.driftReason drift)
            other -> assertFailure ("expected exactly one closure-claim drift, got " <> show other)
    , testCase "the same claim passes when the report the check consumes is closed" $
        withPlanTree $ \root _ -> do
          writeTree root [claimDocument]
          let closed = projectClosable allProvenIndex
          assertBool "the closed fixture closes" (not (isRefusedVerdict (reportVerdict closed)))
          drifts <-
            DocsCheck.checkDocsWith (fixtureEnvironment root) {docsStatusReport = pure closed}
          filter (Text.isPrefixOf "closure-claim." . DocsCheck.driftKey) drifts @?= []
    , testCase "a lying phase header is reported against its document through the composed check" $
        withPlanTree $ \root report -> do
          let phase = phaseEntryFor 289
              lying = planDocumentFor phase (projectionOf report "289.1") Done
          writeTree root [(entryPhaseDocument phase, Text.Encoding.encodeUtf8 lying)]
          drifts <- DocsCheck.checkDocsWith (fixtureEnvironment root)
          case statusDrifts drifts of
            [drift] -> do
              DocsCheck.driftKey drift @?= "status-projection.289.1"
              DocsCheck.driftPath drift @?= entryPhaseDocument phase
              assertBool
                "the drift says Done without proof"
                ("Done without proof" `Text.isInfixOf` DocsCheck.driftReason drift)
            other -> assertFailure ("expected exactly one status drift, got " <> show other)
    , testCase "a phase document missing from the tree is a drift, not a skipped comparison" $
        withPlanTree $ \root _ -> do
          removeFile (root </> entryPhaseDocument (phaseEntryFor 285))
          drifts <- DocsCheck.checkDocsWith (fixtureEnvironment root)
          driftKeysOf drifts @?= ["status-projection.285.1"]
    , testCase "a plan document the catalogue does not list is reported" $
        withPlanTree $ \root _ -> do
          writeTree root [("DEVELOPMENT_PLAN/phase-290-unlisted.md", "# Phase 290: Unlisted\n")]
          drifts <- DocsCheck.checkDocsWith (fixtureEnvironment root)
          case statusDrifts drifts of
            [drift] -> do
              DocsCheck.driftKey drift @?= "status-catalogue.unregistered-phase-290"
              DocsCheck.driftPath drift @?= "DEVELOPMENT_PLAN/phase-290-unlisted.md"
            other -> assertFailure ("expected exactly one coverage drift, got " <> show other)
    , testCase "a misnamed validation record is reported and a hidden file is not" $
        withPlanTree $ \root _ -> do
          writeTree
            root
            [ (Record.committedValidationDirectory </> ".gitkeep", "")
            , (Record.committedValidationDirectory </> "notes.txt", "scratch\n")
            ]
          drifts <- DocsCheck.checkDocsWith (fixtureEnvironment root)
          case statusDrifts drifts of
            [drift] -> do
              DocsCheck.driftKey drift @?= "validation-record.notes.txt"
              DocsCheck.driftPath drift @?= Record.committedValidationDirectory </> "notes.txt"
            other -> assertFailure ("expected exactly one validation-record drift, got " <> show other)
    , testCase "the Closure Status cap is enforced through the composed check only when it is set" $
        withPlanTree $ \root _ -> do
          Text.IO.writeFile (root </> "DEVELOPMENT_PLAN" </> "README.md") (readmeWith 30)
          let environmentWith cap = (fixtureEnvironment root) {docsClosureStatusLineCap = cap}
          over <- DocsCheck.checkDocsWith (environmentWith (Just 10))
          case statusDrifts over of
            [drift] -> do
              DocsCheck.driftKey drift @?= "closure-status.length"
              DocsCheck.driftPath drift @?= "DEVELOPMENT_PLAN/README.md"
            other -> assertFailure ("expected exactly one length drift, got " <> show other)
          off <- DocsCheck.checkDocsWith (environmentWith Nothing)
          driftKeysOf off @?= []
          within <- DocsCheck.checkDocsWith (environmentWith (Just 100))
          driftKeysOf within @?= []
    , testCase "a catalogue problem is reported through the composed check, against the catalogue's file" $
        withPlanTree $ \root _ -> do
          let problem = "duplicate sprint id: 901.1"
          drifts <-
            DocsCheck.checkDocsWith (fixtureEnvironment root) {docsCatalogueProblems = [problem]}
          case statusDrifts drifts of
            [drift] -> do
              DocsCheck.driftKey drift @?= "status-catalogue.duplicate-sprint-id--901-1"
              DocsCheck.driftPath drift @?= "src/JitML/Product/PhaseStatus.hs"
              DocsCheck.driftReason drift @?= problem
              assertBool
                "the remedy points at the catalogue"
                ("src/JitML/Product/PhaseStatus.hs" `Text.isInfixOf` DocsCheck.docsDriftRemedy drift)
            other -> assertFailure ("expected exactly one catalogue drift, got " <> show other)
    , testCase "catalogue problems become drifts whose key is a bounded slug of the problem" $ do
        DocsCheck.catalogueProblemDrifts [] @?= []
        let long = Text.replicate 8 "legacy attestation is frozen "
        fmap DocsCheck.driftKey (DocsCheck.catalogueProblemDrifts ["a: b", long])
          @?= [ "status-catalogue.a--b"
              , "status-catalogue." <> Text.take 60 (Text.replace " " "-" long)
              ]
    , testCase
        "the production environment reads the working directory, the configured cap, and the committed evidence"
        $ do
          docsRoot DocsCheck.productionDocsEnvironment @?= "."
          docsClosureStatusLineCap DocsCheck.productionDocsEnvironment @?= PlanDoc.closureStatusLineCap
          docsCatalogueProblems DocsCheck.productionDocsEnvironment
            @?= PhaseStatus.validateProductStatusCatalogue
          produced <- docsStatusReport DocsCheck.productionDocsEnvironment
          expected <- Loader.loadProductStatusReport
          produced @?= expected
          -- The entry point every caller uses is the composed check under that environment.
          fromEntry <- DocsCheck.checkDocs
          fromEnvironment <- DocsCheck.checkDocsWith DocsCheck.productionDocsEnvironment
          fromEntry @?= fromEnvironment
    ]

-- ---------------------------------------------------------------------------
-- The loader's disk seam, over temporary repository trees
-- ---------------------------------------------------------------------------

-- | The committed path of a validation record, relative to the repository root.
transcriptRelativePath :: ValidationGate -> Substrate -> FilePath
transcriptRelativePath gate substrate =
  Record.committedValidationDirectory </> Record.validationRecordFileName gate substrate

-- | A repository tree holding exactly the given files, plus the code roots when
-- 'baseTree' is among them.
withTree :: [(FilePath, ByteString)] -> (FilePath -> IO a) -> IO a
withTree files action =
  withSystemTempDirectory "jitml-evidence" $ \root -> writeTree root files >> action root

-- | The stamp the code roots of 'baseTree' digest to.
treeStamp :: SourceStamp
treeStamp = sourceStampFromFiles baseTree

-- | A passed record of the standing command, made against @stamp@.
standingRecordAt :: SourceStamp -> Record.ValidationRecord
standingRecordAt stamp =
  mkRecord JitmlUnit LinuxCPU (standingCommand JitmlUnit LinuxCPU) stamp passedEvidence

-- | A record file placed where the committed validation directory expects the
-- record for @(gate, substrate)@.
committedRecordAt :: ValidationGate -> Substrate -> ByteString -> (FilePath, ByteString)
committedRecordAt gate substrate bytes = (transcriptRelativePath gate substrate, bytes)

-- | The unit gate's record as the loader sees it.
unitGate :: Obligation
unitGate = GateTranscript JitmlUnit LinuxCPU

unitStanding :: Obligation
unitStanding = StandingGate JitmlUnit LinuxCPU

-- | The registered lane input of a substrate.
registeredLaneInput :: Substrate -> ProductLaneInput
registeredLaneInput lane =
  case [input | input <- Aggregate.productLaneInputs, productLaneInputSubstrate input == lane] of
    input : _ -> input
    [] -> error ("no registered lane input for " <> show lane)

loaderDiskTests :: TestTree
loaderDiskTests =
  testGroup
    "the loader reads committed evidence below a root"
    [ testCase "an empty tree: every lane, the aggregate, every transcript, and the ledger are Missing" $
        withTree [] $ \root -> do
          index <- Loader.loadEvidenceIndexIn root
          Map.toList (indexLanes index)
            @?= List.sortOn
              fst
              [ ( productLaneInputSubstrate input
                , unproven (Missing (Text.pack (productLaneInputPath input)))
                )
              | input <- Aggregate.productLaneInputs
              ]
          case indexAggregate index of
            Just (Unproven reasons) ->
              NonEmpty.toList reasons
                @?= [ Missing (Text.pack Aggregate.productAggregatePath)
                    , Missing (Text.pack (productLaneInputPath (registeredLaneInput LinuxCPU)))
                    ]
            other -> assertFailure ("expected an unproven aggregate, got " <> show other)
          Map.size (indexTranscripts index) @?= 30
          forM_ (Map.toList (indexTranscripts index)) $ \((gate, lane), evidence) -> do
            transcriptJudgement evidence
              @?= unproven (Missing (Text.pack (transcriptRelativePath gate lane)))
            transcriptSource evidence @?= Nothing
          indexCurrentSource index @?= Left "missing code root: app"
          indexPendingControls index @?= Just pendingProductionControls
          indexLedger index
            @?= Just (unproven (Missing (Text.pack Loader.legacyLedgerPath)))
    , testCase "a complete code tree is digested below the root it is read from" $
        withTree baseTree $ \root -> do
          index <- Loader.loadEvidenceIndexIn root
          indexCurrentSource index @?= Right treeStamp
    , testCase
        "a committed passed record proves its gate, and the standing gate for the tree it ran against"
        $ withTree
          (baseTree <> [committedRecordAt JitmlUnit LinuxCPU (recordBytes (standingRecordAt treeStamp))])
        $ \root -> do
          index <- Loader.loadEvidenceIndexIn root
          let expected =
                Proven
                  ( EvidenceRef
                      { evidenceSubject = Text.pack (transcriptRelativePath JitmlUnit LinuxCPU)
                      , evidenceDigest = Just (Record.sha256Hex (recordBytes (standingRecordAt treeStamp)))
                      }
                      :| []
                  )
          Evidence.observeObligation index unitGate @?= expected
          Evidence.observeObligation index unitStanding @?= expected
          fmap transcriptSource (Map.lookup (JitmlUnit, LinuxCPU) (indexTranscripts index))
            @?= Just (Just treeStamp)
          -- Only the gate that was committed is proven.
          Evidence.observeObligation index (GateTranscript JitmlNegativeControls LinuxCPU)
            @?= unproven (Missing (Text.pack (transcriptRelativePath JitmlNegativeControls LinuxCPU)))
    , testCase "a record made for another tree still proves its gate but no longer the standing gate"
        $ withTree
          (baseTree <> [committedRecordAt JitmlUnit LinuxCPU (recordBytes (standingRecordAt otherStamp))])
        $ \root -> do
          index <- Loader.loadEvidenceIndexIn root
          case Evidence.observeObligation index unitGate of
            Proven _ -> pure ()
            Unproven reasons -> assertFailure ("the historical transcript was refused: " <> show reasons)
          Evidence.observeObligation index unitStanding
            @?= unproven (Stale "source tree" (stampSha256 treeStamp) (stampSha256 otherStamp))
    , testGroup
        "a committed record that does not prove is refused with its own reason"
        [ testCase label $
            withTree (baseTree <> [committedRecordAt JitmlUnit LinuxCPU bytes]) $ \root -> do
              index <- Loader.loadEvidenceIndexIn root
              forM_ [unitGate, unitStanding] $ \obligation ->
                case Evidence.observeObligation index obligation of
                  Unproven (reason :| []) ->
                    assertBool
                      (label <> ": unexpected reason " <> show reason)
                      (matches reason)
                  other -> assertFailure (label <> ": expected one unmet reason, got " <> show other)
        | (label, bytes, matches) <- refusedRecords
        ]
    , testCase
        "a lane journal that is not the pinned one is Mismatched, never proven, and an absent one is Missing"
        $ do
          let cuda = registeredLaneInput LinuxCUDA
              cpu = registeredLaneInput LinuxCPU
          withTree [(productLaneInputPath cuda, "not the pinned journal\n")] $ \root -> do
            index <- Loader.loadEvidenceIndexIn root
            case Map.lookup LinuxCUDA (indexLanes index) of
              Just (Unproven (Mismatched detail :| [])) ->
                assertBool
                  "the pin is named"
                  (productLaneInputSha256 cuda `Text.isInfixOf` detail)
              other -> assertFailure ("expected Mismatched, got " <> show other)
            Map.lookup LinuxCPU (indexLanes index)
              @?= Just (unproven (Missing (Text.pack (productLaneInputPath cpu))))
    , testCase
        "a retained aggregate is read from the tree: another pin is Stale, and nothing is proven without the lanes"
        $ do
          let pinOf = productLaneInputSha256 . registeredLaneInput
              retained =
                aggregateWithSources
                  [ ("linux-cpu", pinOf LinuxCPU)
                  , ("linux-cuda", digestOf '9')
                  , ("apple-silicon", pinOf AppleSilicon)
                  ]
          withTree [(Aggregate.productAggregatePath, retained)] $ \root -> do
            index <- Loader.loadEvidenceIndexIn root
            case indexAggregate index of
              Just (Unproven reasons) -> do
                assertBool
                  "the embedded pin is stale against the registered one"
                  ( Stale
                      "linux-cuda journal pin embedded in the retained aggregate"
                      (pinOf LinuxCUDA)
                      (digestOf '9')
                      `elem` reasons
                  )
                assertBool
                  "the missing lane journal is reported, so the aggregate cannot be proven"
                  ( Missing (Text.pack (productLaneInputPath (registeredLaneInput LinuxCPU)))
                      `elem` reasons
                  )
                assertBool
                  "the retained file itself was found"
                  (Missing (Text.pack Aggregate.productAggregatePath) `notElem` reasons)
              other -> assertFailure ("expected an unproven aggregate, got " <> show other)
    , testGroup
        "the legacy ledger"
        [ testCase "rows in Pending Removal keep the ledger Incomplete"
            $ withTree
              [(Loader.legacyLedgerPath, Text.Encoding.encodeUtf8 (ledgerWith ["| a | b |", "| c | d |"]))]
            $ \root -> do
              index <- Loader.loadEvidenceIndexIn root
              case indexLedger index of
                Just (Unproven (Incomplete detail :| [])) ->
                  assertBool "the row count is stated" ("2 row(s)" `Text.isInfixOf` detail)
                other -> assertFailure ("expected Incomplete, got " <> show other)
        , testCase "an empty table proves the ledger, with the file digest as the pointer" $ do
            let bytes = Text.Encoding.encodeUtf8 (ledgerWith [])
            withTree [(Loader.legacyLedgerPath, bytes)] $ \root -> do
              index <- Loader.loadEvidenceIndexIn root
              indexLedger index
                @?= Just
                  ( Proven
                      ( EvidenceRef
                          { evidenceSubject = Text.pack Loader.legacyLedgerPath <> " has no Pending Removal row"
                          , evidenceDigest = Just (Record.sha256Hex bytes)
                          }
                          :| []
                      )
                  )
        ]
    , testCase "the committed validation directory is listed below the root, hidden files included" $ do
        withTree
          [ (Record.committedValidationDirectory </> "notes.txt", "x")
          , (Record.committedValidationDirectory </> ".gitkeep", "")
          ]
          (Loader.listCommittedValidationFilesIn >=> (@?= [".gitkeep", "notes.txt"]))
        withTree [] (Loader.listCommittedValidationFilesIn >=> (@?= []))
    , testCase "the rooted aggregate reader is the production reader at the working-directory root" $ do
        rooted <- Loader.loadProductAggregationIn "."
        production <- Aggregate.loadProductAggregation
        rooted @?= production
    , testCase "underRoot leaves a path untouched at the working-directory root and nests it otherwise" $ do
        Loader.underRoot "." "DEVELOPMENT_PLAN/x.json" @?= "DEVELOPMENT_PLAN/x.json"
        Loader.underRoot "/tmp/tree" "DEVELOPMENT_PLAN/x.json" @?= "/tmp/tree/DEVELOPMENT_PLAN/x.json"
    ]
 where
  ledgerWith rows =
    Text.unlines
      ( ["## Pending Removal", "", "Prose.", "", "| Item | Location |", "|------|----------|"]
          <> rows
          <> ["", "## Completed", ""]
      )

-- | Committed record files that must not prove the unit gate, each with the reason
-- constructor and text the loader must give.
refusedRecords :: [(String, ByteString, Unmet -> Bool)]
refusedRecords =
  [
    ( "a failed run is FailedRun"
    , recordBytes
        ( mkRecord
            JitmlUnit
            LinuxCPU
            (standingCommand JitmlUnit LinuxCPU)
            treeStamp
            ( EvidenceFailed
                FailedEvidence
                  { failedExitCode = Just 1
                  , failedStdout = Just "1 out of 900 tests failed\n"
                  , failedStderr = Just ""
                  , failedException = Nothing
                  }
            )
        )
    , \case FailedRun detail -> "exit 1" `Text.isInfixOf` detail; _ -> False
    )
  ,
    ( "a gate that never ran is Incomplete"
    , recordBytes
        ( mkRecord
            JitmlUnit
            LinuxCPU
            (standingCommand JitmlUnit LinuxCPU)
            treeStamp
            (EvidenceNotRun "jitml-integration" "cabal test jitml-integration exited 1")
        )
    , \case Incomplete detail -> "jitml-integration" `Text.isInfixOf` detail; _ -> False
    )
  ,
    ( "a record of another gate filed under this name is Mismatched"
    , recordBytes
        ( mkRecord
            JitmlIntegration
            LinuxCPU
            (standingCommand JitmlUnit LinuxCPU)
            treeStamp
            passedEvidence
        )
    , \case Mismatched detail -> "records gate jitml-integration" `Text.isInfixOf` detail; _ -> False
    )
  ,
    ( "a record of a focused run is Mismatched: not the standing invocation"
    , recordBytes
        ( mkRecord
            JitmlUnit
            LinuxCPU
            "cabal test jitml-unit --test-options '-p Journal'"
            treeStamp
            passedEvidence
        )
    , \case Mismatched detail -> "not the standing invocation" `Text.isInfixOf` detail; _ -> False
    )
  ,
    ( "bytes that are not JSON are Mismatched"
    , "not json\n"
    , \case Mismatched detail -> "malformed" `Text.isInfixOf` detail; _ -> False
    )
  ,
    ( "a record that is not in canonical form is Mismatched"
    , recordBytes (standingRecordAt treeStamp) <> " "
    , \case Mismatched detail -> "canonical" `Text.isInfixOf` detail; _ -> False
    )
  ]

-- ---------------------------------------------------------------------------
-- The production entry points: jitml test and jitml docs status
-- ---------------------------------------------------------------------------

-- | The environment variable that turns this test binary into a @jitml@
-- executable. The entry-point cases run the real command line as a child of this
-- binary, in a fixture repository and with a fake @cabal@ on its @PATH@, so nothing
-- about the test process (its working directory, @PATH@, or standard streams) is
-- touched and the production parse, dispatch, and command code are what run.
cliWorkerVariable :: String
cliWorkerVariable = "JITML_UNIT_CLI_WORKER"

-- | The unit driver's @main@ wrapper: as a worker the binary runs the production
-- @main@ on its own arguments, otherwise it runs the test driver.
withCliWorker :: IO () -> IO ()
withCliWorker testDriver =
  lookupEnv cliWorkerVariable >>= \case
    Just "1" -> App.main
    _ -> testDriver

-- | How a child @jitml@ ended and what it wrote.
data CliRun = CliRun
  { cliExit :: ExitCode
  , cliStdout :: Text
  , cliStderr :: Text
  }
  deriving stock (Eq, Show)

-- | Run @jitml <args>@ as a child of this binary in @root@, with @pathPrefix@ (if
-- any) first on its @PATH@.
runCliChild :: FilePath -> Maybe FilePath -> [Text] -> IO CliRun
runCliChild root pathPrefix args = do
  executable <- getExecutablePath
  original <- Text.pack . fromMaybe "" <$> lookupEnv "PATH"
  let path = maybe original (\directory -> Text.pack directory <> ":" <> original) pathPrefix
      environment =
        subprocessEnvOverrideAndRemove
          [(Text.pack cliWorkerVariable, "1"), ("PATH", path)]
          []
  outcome <-
    runStreaming
      environment
      (subprocess executable args) {subprocessWorkingDirectory = Just root}
  pure $
    case outcome of
      ProcessSucceeded transcript ->
        CliRun ExitSuccess (processTranscriptStdout transcript) (processTranscriptStderr transcript)
      ProcessFailed failure ->
        CliRun
          (processFailureExitCode failure)
          (processFailureStdout failure)
          (processFailureStderr failure)

-- | A fake @cabal@ installed the way ghcup installs the real one: a versioned
-- executable and a @cabal@ link to it, so the path @jitml test@ resolves and records
-- is the versioned file. The script runs in the repository, as cabal does. The
-- action receives the directory to put first on @PATH@.
withFakeCabal :: [Text] -> (FilePath -> IO a) -> IO a
withFakeCabal scriptLines action =
  withSystemTempDirectory "jitml-fake-cabal" $ \directory -> do
    let versioned = directory </> "cabal-9.9.9"
    Text.IO.writeFile versioned (Text.unlines ("#!/bin/sh" : scriptLines))
    permissions <- getPermissions versioned
    setPermissions versioned (setOwnerExecutable True permissions)
    createFileLink "cabal-9.9.9" (directory </> "cabal")
    action directory

-- | A repository tree @jitml test@ can run in: the code roots the source digest
-- reads, and the real @cabal.project@ because the report card reads its knobs.
withTestRepository :: (FilePath -> IO a) -> IO a
withTestRepository action = do
  cabalProject <- ByteString.readFile "cabal.project"
  withTree (filter ((/= "cabal.project") . fst) baseTree <> [("cabal.project", cabalProject)]) action

candidateRecordPath :: FilePath -> FilePath
candidateRecordPath root = root </> Record.candidateValidationDirectory </> "jitml-unit.linux-cpu.json"

-- | Read and admit the candidate record @jitml test@ left for the unit gate.
readCandidateRecord :: FilePath -> IO (ByteString, Record.ValidationRecord)
readCandidateRecord root = do
  bytes <- ByteString.readFile (candidateRecordPath root)
  record <- either (assertFailure . show) pure (Record.admitValidationRecord bytes)
  pure (bytes, record)

-- | Commit the candidate record into the tree, as the person closing a sprint does.
commitCandidateRecord :: FilePath -> IO ()
commitCandidateRecord root = do
  createDirectoryIfMissing True (root </> Record.committedValidationDirectory)
  copyFile
    (candidateRecordPath root)
    (root </> transcriptRelativePath JitmlUnit LinuxCPU)

entryPointTests :: TestTree
entryPointTests =
  testGroup
    "production entry points"
    [ testCase
        "jitml test on a lane leaves a passed record that admits, and once committed the loader proves the gate"
        $ withTestRepository
        $ \root ->
          withFakeCabal ["echo 'fake cabal ran'", "exit 0"] $ \shim -> do
            run <- runCliChild root (Just shim) ["test", "jitml-unit", "--linux-cpu"]
            cliExit run @?= ExitSuccess
            -- Writing the record leaves the report card as it was.
            forM_ ["  jitml-unit: PASS", "    status: passed", "      fake cabal ran"] $ \cardLine ->
              assertBool
                ("the report card lacks " <> show cardLine <> ": " <> Text.unpack (cliStdout run))
                (cardLine `elem` Text.lines (cliStdout run))
            (_, record) <- readCandidateRecord root
            Record.validationRecordGate record @?= JitmlUnit
            Record.validationRecordSubstrate record @?= LinuxCPU
            stamp <- stampIn root
            Record.validationRecordSource record @?= stamp
            Record.validationRecordEvidence record
              @?= EvidencePassed (Record.sha256Hex "fake cabal ran\n") (Record.sha256Hex "")
            -- The command names the versioned cabal a ghcup link resolves to.
            case Text.words (Record.validationRecordCommand record) of
              executable : arguments -> do
                takeFileName (Text.unpack executable) @?= "cabal-9.9.9"
                arguments @?= ["test", "jitml-unit"]
              [] -> assertFailure "the record has an empty command"
            -- Committed, that record proves the gate and, for this tree, the standing gate.
            commitCandidateRecord root
            index <- Loader.loadEvidenceIndexIn root
            forM_ [unitGate, unitStanding] $ \obligation ->
              case Evidence.observeObligation index obligation of
                Proven _ -> pure ()
                Unproven reasons -> assertFailure ("the committed record did not prove it: " <> show reasons)
    , testCase "a failing gate exits 1 as before, and its record keeps the exit code and both streams" $
        withTestRepository $ \root ->
          withFakeCabal ["echo 'fake stdout'", "echo 'fake stderr' >&2", "exit 7"] $ \shim -> do
            run <- runCliChild root (Just shim) ["test", "jitml-unit", "--linux-cpu"]
            cliExit run @?= ExitFailure 1
            forM_ ["  jitml-unit: FAIL", "    status: failed", "    exit: 7"] $ \cardLine ->
              assertBool
                ("the report card lacks " <> show cardLine <> ": " <> Text.unpack (cliStdout run))
                (cardLine `elem` Text.lines (cliStdout run))
            assertBool
              ("the failure is still reported on standard error: " <> Text.unpack (cliStderr run))
              ("subprocess failed:" `Text.isInfixOf` cliStderr run)
            (_, record) <- readCandidateRecord root
            Record.validationRecordEvidence record
              @?= EvidenceFailed
                FailedEvidence
                  { failedExitCode = Just 7
                  , failedStdout = Just "fake stdout\n"
                  , failedStderr = Just "fake stderr\n"
                  , failedException = Nothing
                  }
            commitCandidateRecord root
            index <- Loader.loadEvidenceIndexIn root
            case Evidence.observeObligation index unitGate of
              Unproven (FailedRun detail :| []) ->
                assertBool "the exit status is stated" ("exit 7" `Text.isInfixOf` detail)
              other -> assertFailure ("expected FailedRun, got " <> show other)
    , testCase "a run that selects no lane writes no record" $
        withTestRepository $ \root ->
          withFakeCabal ["exit 0"] $ \shim -> do
            run <- runCliChild root (Just shim) ["test", "jitml-unit"]
            cliExit run @?= ExitSuccess
            doesDirectoryExist (root </> Record.candidateValidationDirectory) >>= (@?= False)
    , testCase
        "a tree edited while the gate ran writes no record, says why, and leaves the exit status alone"
        $ withTestRepository
        $ \root ->
          withFakeCabal ["echo '-- edited while the gate ran' >> src/JitML/A.hs", "exit 0"] $ \shim -> do
            run <- runCliChild root (Just shim) ["test", "jitml-unit", "--linux-cpu"]
            cliExit run @?= ExitSuccess
            doesFileExist (candidateRecordPath root) >>= (@?= False)
            assertBool
              ("the reason is reported on standard error: " <> Text.unpack (cliStderr run))
              ( "validation records not written: the source tree changed while the gates ran"
                  `Text.isInfixOf` cliStderr run
              )
    , testCase "jitml docs status prints the derived tally, the open chain, and the unmet obligations" $
        withTree [] $ \root -> do
          run <- runCliChild root Nothing ["docs", "status"]
          cliExit run @?= ExitSuccess
          let outputLines = Text.lines (cliStdout run)
          take 1 outputLines
            @?= ["status: 63 Done / 1 Active / 0 Planned / 6 Blocked across 70 sprints"]
          assertBool
            "the open chain is derived and printed"
            ("open chain: 278 -> 280 -> 281 -> 282 -> 285 -> 288 -> 289" `elem` outputLines)
          assertBool
            "an unmet obligation carries its evidence pointer"
            ( any
                ("  unmet   gate-transcript jitml-unit linux-cpu: missing: " `Text.isPrefixOf`)
                outputLines
            )
    ]

-- ---------------------------------------------------------------------------
-- Everything
-- ---------------------------------------------------------------------------

journalDerivedStatusTests :: TestTree
journalDerivedStatusTests =
  testGroup
    "Journal-derived status registry (Phase 288)"
    [ statusRelationTests
    , unmetConstructorTests
    , standingFreshnessTests
    , closureGuardTests
    , planDocTests
    , catalogueTests
    , loaderMappingTests
    , validationRecordTests
    , sourceDigestTests
    , jitmlTestRecordTests
    , closureStatusCapTests
    , statusReportRenderTests
    , docsCheckCompositionTests
    , loaderDiskTests
    , entryPointTests
    , realFileTests
    ]
