{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Synthetic mathematical outcomes over real Store-admitted graph/bytes.
-- These controls prove publication/authentication boundaries; they make no
-- claim of five training executions or a real converged model.
module SupervisedQualificationReceipt (supervisedQualificationReceiptTests) where

import Control.Monad (void)
import Data.Aeson (Value (..), eitherDecodeStrict', encode)
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Either (isLeft)
import Data.List (find)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Encoding
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist, removeFile)
import System.FilePath ((</>))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Checkpoint.Store qualified as Store
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.SupervisedCohortPlan qualified as Cohort
import JitML.Product.SupervisedQualification qualified as Qualification
import JitML.Product.SupervisedQualificationReceipt qualified as Receipt
import JitML.SL.Canonicals qualified as SL
import JitML.SL.RuntimeArtifact qualified as Runtime
import JitML.Substrate (Substrate (LinuxCPU))
import JitML.Test.ContractFixtures qualified as Fixtures
import JitML.Test.JournalFixtures qualified as JournalFixtures
import JitML.Test.ProductLaneJournal qualified as Lane
import JitML.Test.ProductScenarioJournal qualified as Journal
import JitML.Test.Report qualified as Report
import JitML.Training.Budget qualified as Budget

supervisedQualificationReceiptTests :: TestTree
supervisedQualificationReceiptTests =
  testGroup
    "detached supervised qualification receipts"
    [ scenario "real Store admission binds the original serving seed and exact detached bytes" $ \state -> do
        (cohort, publication, reference, bytes) <- actualPublication state
        rebound <-
          expectRight
            ( Receipt.bindSupervisedQualificationPublication
                cohort
                (Receipt.supervisedQualificationPublicationData publication)
                (Receipt.qualificationReferenceObjectKey reference)
                (JournalFixtures.jsAdmitted state)
            )
        rebound @?= publication
        expectedInvocation <- actualInvocation state
        Receipt.validateSupervisedQualificationPublication
          cohort
          fixtureSource
          (JournalFixtures.jsExecutableSha state)
          (Budget.productScenarioInvocationDigest expectedInvocation)
          reference
          bytes
          (JournalFixtures.jsAdmitted state)
          @?= Right publication
    , scenario "missing actual graph metadata is rejected by the real completed writer before admission" $ \state -> do
        invocation <- actualInvocation state
        problem <- fixtureProblem
        parts <-
          Fixtures.productCompletionParts
            (JournalFixtures.jsRow state)
            problem
            (JournalFixtures.jsProjection state)
            (Just invocation)
        payload <-
          maybe
            (assertFailure "positive fixture has no supervised runtime")
            pure
            (Checkpoint.manifestSupervisedRuntime (Fixtures.pcpManifest parts))
        missingGraph <-
          expectRight
            ( Runtime.refineSupervisedRuntimePayload
                ( (Runtime.supervisedRuntimePayloadToRaw payload)
                    { Runtime.rawRuntimePayloadLayerGraphMetadata = Nothing
                    }
                )
            )
        let root = JournalFixtures.jsCheckpointRoot state </> "missing-payload-graph"
            manifest = (Fixtures.pcpManifest parts) {Checkpoint.manifestSupervisedRuntime = Just missingGraph}
        result <-
          Store.writeCompletedCheckpointSnapshot
            root
            (Fixtures.pcpCompleted parts)
            manifest
            (Fixtures.pcpPayloads parts)
            Nothing
        assertLeftContains "missing its trained layer graph metadata" result
        doesDirectoryExist root >>= (@?= False)
    , scenario "canonical receipt roundtrips exact source invocation manifest and object identities" $ \state -> do
        (_, publication, reference, _) <- actualPublication state
        Receipt.parseSupervisedQualificationReference
          (Receipt.renderSupervisedQualificationPublication publication)
          @?= Right reference
        Receipt.qualificationReferenceRowId reference
          @?= Matrix.productProjectionRowId (JournalFixtures.jsProjection state)
        Receipt.qualificationReferenceManifestSha256 reference
          @?= Store.admittedCheckpointManifestSha
            (Store.admittedCompletedCheckpoint (JournalFixtures.jsAdmitted state))
        assertBool "scenario binding disappeared" (Receipt.qualificationReferenceIsScenarioBound reference)
    , scenario "strict receipt rejects unknown missing duplicated noncanonical and future fields" $ \state -> do
        (_, _, reference, _) <- actualPublication state
        let rendered = Receipt.renderSupervisedQualificationReference reference
        reject (Receipt.parseSupervisedQualificationReference (rendered <> " "))
        reject
          ( Receipt.parseSupervisedQualificationReference
              (changeReference [("unknown", String "x")] [] rendered)
          )
        reject
          (Receipt.parseSupervisedQualificationReference (changeReference [] ["source_sha256"] rendered))
        reject
          (Receipt.parseSupervisedQualificationReference (changeReference [("version", Number 2)] [] rendered))
        let body = Text.drop (Text.length Receipt.supervisedQualificationReceiptPrefix) rendered
        reject
          ( Receipt.parseSupervisedQualificationReference
              (Receipt.supervisedQualificationReceiptPrefix <> Text.dropEnd 1 body <> ",\"version\":1}")
          )
    , scenario "strict receipt rejects noncanonical hashes unsafe paths and unknown binding kinds" $ \state -> do
        (_, _, reference, _) <- actualPublication state
        let rendered = Receipt.renderSupervisedQualificationReference reference
        mapM_
          (reject . Receipt.parseSupervisedQualificationReference)
          [ changeReference [("source_sha256", String (Text.replicate 64 "A"))] [] rendered
          , changeReference [("qualification_object_key", String "../../escape.cbor")] [] rendered
          , changeReference [("execution_binding", String "caller-says-completed")] [] rendered
          , Text.replace "product-supervised-qualification-v1" "product-supervised-qualification-v2" rendered
          ]
    , scenario "canonical detached namespace cannot be substituted by a writer" $ \state -> do
        (cohort, publication, _, _) <- actualPublication state
        assertLeftContains
          "exact detached object key"
          ( Receipt.bindSupervisedQualificationPublication
              cohort
              (Receipt.supervisedQualificationPublicationData publication)
              "jitml-checkpoints/foreign/artifacts/supervised-qualification/wrong.cbor"
              (JournalFixtures.jsAdmitted state)
          )
    , scenario "parent source executable and invocation observations cannot be borrowed from the receipt" $ \state -> do
        (cohort, _, reference, bytes) <- actualPublication state
        invocation <- actualInvocation state
        let run source executable challenge =
              Receipt.validateSupervisedQualificationPublication
                cohort
                source
                executable
                challenge
                reference
                bytes
                (JournalFixtures.jsAdmitted state)
        assertLeftContains
          "parent source identity"
          ( run
              (digest "a")
              (JournalFixtures.jsExecutableSha state)
              (Budget.productScenarioInvocationDigest invocation)
          )
        assertLeftContains
          "parent executable identity"
          (run fixtureSource (digest "b") (Budget.productScenarioInvocationDigest invocation))
        assertLeftContains
          "parent invocation identity"
          (run fixtureSource (JournalFixtures.jsExecutableSha state) (digest "c"))
    , scenario "a readdressed source claim cannot borrow the old qualification producer" $ \state -> do
        (cohort, _, reference, bytes) <- actualPublication state
        changed <-
          expectRight
            ( Receipt.parseSupervisedQualificationReference
                ( changeReference
                    [("source_sha256", String (digest "f"))]
                    []
                    (Receipt.renderSupervisedQualificationReference reference)
                )
            )
        assertLeftContains
          "qualification source identity"
          (Receipt.replaySupervisedQualificationReference cohort changed bytes)
    , scenario "each plan runtime graph evaluation and byte address is checked against replayed data" $ \state -> do
        (cohort, _, reference, bytes) <- actualPublication state
        mapM_
          ( \field -> do
              changed <-
                expectRight
                  ( Receipt.parseSupervisedQualificationReference
                      ( changeReference
                          [(field, String (digest "f"))]
                          []
                          (Receipt.renderSupervisedQualificationReference reference)
                      )
                  )
              reject (Receipt.replaySupervisedQualificationReference cohort changed bytes)
          )
          [ "plan_id"
          , "cohort_plan_id"
          , "runtime_sha256"
          , "graph_sha256"
          , "evaluation_sha256"
          , "initial_jmw1_sha256"
          , "final_jmw1_sha256"
          ]
        let changedBytes = BS.snoc bytes 0
        reject (Receipt.replaySupervisedQualificationReference cohort reference changedBytes)
    , scenario "direct local publication cannot become authenticated scenario or portable evidence" $ \state -> do
        let projection = JournalFixtures.jsProjection state
            root = JournalFixtures.jsCheckpointRoot state </> "direct"
        problem <- fixtureProblem
        direct <-
          Fixtures.persistAndAdmitUnboundProductCompletion
            root
            (JournalFixtures.jsRow state)
            problem
            projection
        publication <- Fixtures.qualificationForAdmittedProductFixture projection direct
        let reference = Receipt.supervisedQualificationPublicationReference publication
            dataValue =
              Qualification.qualifiedSupervisedCohortData
                (Receipt.supervisedQualificationPublicationData publication)
        assertBool
          "a direct attempt claimed a scenario challenge"
          (not (Receipt.qualificationReferenceIsScenarioBound reference))
        addressed <-
          expectRight
            =<< Report.admitAddressedProductScenarioCompletion
              root
              projection
              (Receipt.qualificationReferenceManifestSha256 reference)
        assertLeftContains
          "direct local qualification"
          (Report.attachAddressedProductScenarioQualification publication addressed)
        cohort <- expectRight (Cohort.mkSupervisedCohortPlan projection)
        assertLeftContains
          "actual scenario invocation"
          ( Receipt.validateRetainedSupervisedQualification
              cohort
              reference
              (Qualification.encodeSupervisedQualification dataValue)
              (Receipt.qualificationReferenceManifestSha256 reference)
              (Receipt.qualificationReferenceExecutableSha256 reference)
              (Receipt.qualificationReferenceInvocationSha256 reference)
              (Store.admittedCompletedTraining direct)
          )
    , scenario "an admitted checkpoint with another immutable address cannot inherit the publication" $ \state -> do
        (_, publication, _, _) <- actualPublication state
        invocation <- actualInvocation state
        problem <- fixtureProblem
        parts <-
          Fixtures.productCompletionParts
            (JournalFixtures.jsRow state)
            problem
            (JournalFixtures.jsProjection state)
            (Just invocation)
        let root = JournalFixtures.jsCheckpointRoot state </> "different-manifest"
            manifest = (Fixtures.pcpManifest parts) {Checkpoint.manifestId = "another-real-address"}
        _ <-
          expectRight
            =<< Store.writeCompletedCheckpointSnapshot
              root
              (Fixtures.pcpCompleted parts)
              manifest
              (Fixtures.pcpPayloads parts)
              Nothing
        checkpoint <- expectRight =<< Store.admitLocalLatestCheckpoint root (Fixtures.pcpExperiment parts)
        admitted <- expectRight (Store.requireAdmittedCompletedCheckpoint checkpoint)
        addressed <-
          expectRight
            =<< Report.admitAddressedProductScenarioCompletion
              root
              (JournalFixtures.jsProjection state)
              (Store.admittedCheckpointManifestSha (Store.admittedCompletedCheckpoint admitted))
        reject (Report.attachAddressedProductScenarioQualification publication addressed)
    , scenario "a qualification cannot attach to the actual admission of another canonical row" $ \state -> do
        (_, publication, _, _) <- actualPublication state
        foreignSha <- JournalFixtures.foreignAdmittedManifestSha state
        foreignRow <-
          maybe
            (assertFailure "missing canonical foreign row")
            pure
            (find ((== "mnist-deep-mlp") . Matrix.rowId) Matrix.allProductRows)
        Fixtures.withProjectedRow LinuxCPU foreignRow $ \projection -> do
          addressed <-
            expectRight
              =<< Report.admitAddressedProductScenarioCompletion
                (JournalFixtures.jsCheckpointRoot state)
                projection
                foreignSha
          reject (Report.attachAddressedProductScenarioQualification publication addressed)
    , scenario
        "unsigned source-reference tampering is rejected by aggregate authentication before Store replay"
        $ \state -> do
          original <- JournalFixtures.readJournalValue (JournalFixtures.jsJournalPath state)
          (_, _, reference, _) <- actualPublication state
          let changed =
                changeReference
                  [("source_sha256", String (digest "f"))]
                  []
                  (Receipt.renderSupervisedQualificationReference reference)
          JournalFixtures.writeScenarioJournalValue
            state
            (JournalFixtures.setRowField "supervised_qualification_receipt" (String changed) original)
          result <- JournalFixtures.readScenarioJournal state
          assertLeftContains "ProductScenarioJournalAuthenticationRejected" result
    , scenario "resigned source-reference tampering still fails the exact artifact producer binding" $ \state -> do
        JournalFixtures.resignedIdentityReadable state >>= (@?= Right ())
        original <- JournalFixtures.readJournalValue (JournalFixtures.jsJournalPath state)
        (_, _, reference, _) <- actualPublication state
        let changed =
              changeReference
                [("source_sha256", String (digest "f"))]
                []
                (Receipt.renderSupervisedQualificationReference reference)
        resigned <-
          expectRight
            ( JournalFixtures.resignJournalValue
                (JournalFixtures.jsKey state)
                (JournalFixtures.setRowField "supervised_qualification_receipt" (String changed) original)
            )
        JournalFixtures.writeScenarioJournalValue state resigned
        JournalFixtures.readScenarioJournal state >>= assertLeftContains "qualification source identity"
    , scenario "per-row Authorization material independently covers the entire qualification reference" $ \state -> do
        (_, _, reference, _) <- actualPublication state
        let changedReference =
              changeReference
                [("source_sha256", String (digest "f"))]
                []
                (Receipt.renderSupervisedQualificationReference reference)
        JournalFixtures.qualificationRowAuthorizationMatches state changedReference >>= (@?= (True, False))
    , scenario "source-journal readmission requires the exact detached object even after its HMAC passes" $ \state -> do
        (_, _, reference, _) <- actualPublication state
        path <-
          expectRight
            ( Store.objectPathForKey
                (JournalFixtures.jsCheckpointRoot state)
                (Receipt.qualificationReferenceObjectKey reference)
            )
        doesFileExist path >>= (@?= True)
        removeFile path
        JournalFixtures.readScenarioJournal state >>= assertLeftContains "detached-supervised-qualification"
    , scenario
        "portable admission replays an explicit exact object map and cannot accept pointer-only evidence"
        $ \state -> do
          let bytes = JournalFixtures.laneJournalBytes state
              objects = JournalFixtures.laneJournalQualificationObjects state
          _ <-
            expectRight
              ( Lane.admitProductLaneJournalWithQualifications
                  objects
                  (JournalFixtures.sha256Hex bytes)
                  (JournalFixtures.jsBatch state)
                  bytes
              )
          assertLeftContains
            "qualification object map"
            (Lane.admitProductLaneJournal (JournalFixtures.sha256Hex bytes) (JournalFixtures.jsBatch state) bytes)
          assertLeftContains
            "qualification object map"
            ( Lane.admitProductLaneJournalWithQualifications
                (objects <> objects)
                (JournalFixtures.sha256Hex bytes)
                (JournalFixtures.jsBatch state)
                bytes
            )
          assertLeftContains
            "qualification object map"
            ( Lane.admitProductLaneJournalWithQualifications
                (("foreign", "bytes") : objects)
                (JournalFixtures.sha256Hex bytes)
                (JournalFixtures.jsBatch state)
                bytes
            )
    , scenario "portable object bytes cannot be replaced under the original reference" $ \state -> do
        let bytes = JournalFixtures.laneJournalBytes state
            changed = [(key, payload <> "x") | (key, payload) <- JournalFixtures.laneJournalQualificationObjects state]
        reject
          ( Lane.admitProductLaneJournalWithQualifications
              changed
              (JournalFixtures.sha256Hex bytes)
              (JournalFixtures.jsBatch state)
              bytes
          )
    , scenario "portable writer persists the exact binary objects beside its canonical main journal" $ \state -> do
        authenticated <- authenticatedScenario state
        let path = JournalFixtures.jsJournalPath state <> ".portable"
        issued <-
          expectRight
            =<< Lane.writeProductLaneJournalAtomic path (JournalFixtures.jsBatch state) authenticated
        BS.readFile path >>= (@?= Lane.issuedProductLaneJournalBytes issued)
        mapM_
          ( \(key, bytes) -> do
              let objectPath = path <> ".qualifications" </> Text.unpack (lastKeyComponent key)
              BS.readFile objectPath >>= (@?= bytes)
          )
          (Lane.issuedProductLaneJournalQualificationObjects issued)
    , scenario "portable writer refuses conflicting detached bytes before writing any main journal" $ \state -> do
        authenticated <- authenticatedScenario state
        (key, _) <- exactlyOne (JournalFixtures.laneJournalQualificationObjects state)
        let path = JournalFixtures.jsJournalPath state <> ".portable-conflict"
            directory = path <> ".qualifications"
            objectPath = directory </> Text.unpack (lastKeyComponent key)
        createDirectoryIfMissing True directory
        BS.writeFile objectPath "conflicting qualification bytes"
        result <- Lane.writeProductLaneJournalAtomic path (JournalFixtures.jsBatch state) authenticated
        assertLeftContains objectPath result
        doesFileExist path >>= (@?= False)
        BS.readFile objectPath >>= (@?= "conflicting qualification bytes")
    , scenario "historical source wire remains an explicit version mismatch before new row authentication" $ \state -> do
        original <- JournalFixtures.readJournalValue (JournalFixtures.jsJournalPath state)
        JournalFixtures.writeScenarioJournalValue
          state
          (JournalFixtures.setJournalField "version" (Number 3) original)
        result <- JournalFixtures.readScenarioJournal state
        void result
          @?= Left
            (Journal.ProductScenarioJournalVersionMismatch Journal.productScenarioJournalWireVersion 3 :| [])
    , scenario
        "historical lane wire is explicitly stale and never reinterpreted as malformed current proof"
        $ \state -> do
          value <- expectRight (eitherDecodeStrict' (JournalFixtures.laneJournalBytes state))
          let historical = LBS.toStrict (encode (JournalFixtures.setJournalField "version" (Number 1) value)) <> "\n"
          Lane.productLaneJournalQualificationObjectKeys historical
            @?= Left (Lane.ProductLaneJournalWireStale Lane.productLaneJournalWireVersion 1)
    , scenario
        "actual Store completion invocation cannot be replaced beneath the original qualified cohort"
        $ \state -> do
          (cohort, publication, reference, _) <- actualPublication state
          originalInvocation <- actualInvocation state
          let originalAdmitted = JournalFixtures.jsAdmitted state
              originalCompleted = Store.admittedCompletedTraining originalAdmitted
              changedChallenge =
                Text.map
                  (\character -> if character == '0' then '1' else '0')
                  (Budget.productScenarioInvocationChallenge originalInvocation)
          changedInvocation <-
            expectRight
              ( Budget.mkProductScenarioInvocation
                  (Budget.productScenarioInvocationRunId originalInvocation)
                  (Budget.productScenarioInvocationRowId originalInvocation)
                  (Budget.productScenarioInvocationPlanId originalInvocation)
                  (Budget.productScenarioInvocationSubstrate originalInvocation)
                  (Budget.productScenarioInvocationCheckpointScopeDigest originalInvocation)
                  (Budget.productScenarioInvocationExecutableSha256 originalInvocation)
                  changedChallenge
              )
          assertBool
            "the valid changed challenge retained the original invocation digest"
            ( Budget.productScenarioInvocationDigest changedInvocation
                /= Budget.productScenarioInvocationDigest originalInvocation
            )
          problem <- fixtureProblem
          different <-
            Fixtures.persistAndAdmitProductCompletion
              (JournalFixtures.jsCheckpointRoot state </> "different-completed-invocation")
              (JournalFixtures.jsRow state)
              problem
              (JournalFixtures.jsProjection state)
              changedInvocation
          let differentCompleted = Store.admittedCompletedTraining different
          Budget.completedTrainingProductScenarioInvocation differentCompleted @?= Just changedInvocation
          Budget.completedTrainingPlanId differentCompleted
            @?= Budget.completedTrainingPlanId originalCompleted
          Budget.completedTrainingBudget differentCompleted
            @?= Budget.completedTrainingBudget originalCompleted
          Budget.completedTrainingInitialWeightHash differentCompleted
            @?= Budget.completedTrainingInitialWeightHash originalCompleted
          Budget.completedTrainingFinalWeightHash differentCompleted
            @?= Budget.completedTrainingFinalWeightHash originalCompleted
          Budget.completedTrainingUpdateCount differentCompleted
            @?= Budget.completedTrainingUpdateCount originalCompleted
          Budget.completedTrainingObservedUnits differentCompleted
            @?= Budget.completedTrainingObservedUnits originalCompleted
          Budget.completedTrainingDatasetShaAtRead differentCompleted
            @?= Budget.completedTrainingDatasetShaAtRead originalCompleted
          Budget.completedTrainingMetrics differentCompleted
            @?= Budget.completedTrainingMetrics originalCompleted
          -- bindPublication takes the immutable manifest address from `different`
          -- itself. Earlier graph/work/metric predicates remain genuine; this
          -- reaches the completion-invocation check rather than address mismatch.
          Receipt.bindSupervisedQualificationPublication
            cohort
            (Receipt.supervisedQualificationPublicationData publication)
            (Receipt.qualificationReferenceObjectKey reference)
            different
            @?= Left "qualification completed invocation differs"
    ]

scenario :: String -> (JournalFixtures.JournalScenario -> Assertion) -> TestTree
scenario name body = testCase name (JournalFixtures.withJournalScenario body)

actualPublication
  :: JournalFixtures.JournalScenario
  -> IO
       ( Cohort.SupervisedCohortPlan
       , Receipt.SupervisedQualificationPublication
       , Receipt.SupervisedQualificationReference
       , BS.ByteString
       )
actualPublication state = do
  cohort <- expectRight (Cohort.mkSupervisedCohortPlan (JournalFixtures.jsProjection state))
  evidence <-
    exactlyOne (Report.completedProductScenarioReportEntries (JournalFixtures.jsReport state))
  publication <-
    maybe
      (assertFailure "positive source-journal fixture has no qualification")
      pure
      (Report.completedProductScenarioQualification evidence)
  let reference = Receipt.supervisedQualificationPublicationReference publication
  bytes <-
    expectRight
      =<< Store.readObject
        (JournalFixtures.jsCheckpointRoot state)
        (Receipt.qualificationReferenceObjectKey reference)
  pure (cohort, publication, reference, LBS.toStrict bytes)

authenticatedScenario
  :: JournalFixtures.JournalScenario -> IO Journal.AuthenticatedProductScenarioReport
authenticatedScenario state =
  expectRight
    =<< Journal.readAuthenticatedProductScenarioJournal
      (JournalFixtures.jsKey state)
      (JournalFixtures.jsJournalPath state)
      (JournalFixtures.jsCheckpointRoot state)
      (JournalFixtures.jsRunId state)
      (JournalFixtures.jsExecutablePath state)
      (JournalFixtures.jsExecutableSha state)
      (JournalFixtures.jsBatch state)

lastKeyComponent :: Text -> Text
lastKeyComponent = Text.takeWhileEnd (/= '/')

actualInvocation :: JournalFixtures.JournalScenario -> IO Budget.ProductScenarioInvocation
actualInvocation state =
  maybe
    (assertFailure "fixture has no actual stored invocation")
    pure
    ( Budget.completedTrainingProductScenarioInvocation
        (Store.admittedCompletedTraining (JournalFixtures.jsAdmitted state))
    )

fixtureProblem :: IO SL.CanonicalProblem
fixtureProblem =
  maybe
    (assertFailure "canonical fixture problem missing")
    pure
    (find ((== "mnist-shallow-mlp") . SL.problemName) SL.canonicalProblems)

fixtureSource :: Text
fixtureSource = JournalFixtures.sha256Hex (Encoding.encodeUtf8 "synthetic-qualification-fixture-source")

digest :: Text -> Text
digest = Text.replicate 64

changeReference :: [(Text, Value)] -> [Text] -> Text -> Text
changeReference changes removed rendered =
  case Text.stripPrefix Receipt.supervisedQualificationReceiptPrefix rendered
    >>= eitherToMaybe . eitherDecodeStrict' . Encoding.encodeUtf8 of
    Just (Object original) ->
      let deleted = foldr (KeyMap.delete . Key.fromText) original removed
          changed = foldr (\(key, value) -> KeyMap.insert (Key.fromText key) value) deleted changes
       in Receipt.supervisedQualificationReceiptPrefix
            <> Encoding.decodeUtf8 (LBS.toStrict (encode (Object changed)))
    _ -> error "the test's canonical reference unexpectedly failed decoding"

reject :: Either err value -> Assertion
reject value = assertBool "adversarial input was accepted" (isLeft value)

assertLeftContains :: (Show err, Show value) => String -> Either err value -> Assertion
assertLeftContains fragment result = case result of
  Left failure ->
    assertBool
      ("wrong rejection: " <> show failure)
      (Text.pack fragment `Text.isInfixOf` Text.pack (show failure))
  Right value -> assertFailure ("adversarial input accepted: " <> show value)

expectRight :: (Show err) => Either err value -> IO value
expectRight = either (assertFailure . show) pure

exactlyOne :: [value] -> IO value
exactlyOne [value] = pure value
exactlyOne _ = assertFailure "expected exactly one fixture row"

-- | Keep the raw JSON fixture conversion total without another test dependency.
eitherToMaybe :: Either err value -> Maybe value
eitherToMaybe (Left _) = Nothing
eitherToMaybe (Right value) = Just value
