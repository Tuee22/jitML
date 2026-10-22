{-# LANGUAGE DataKinds #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- Ordinary transport/HMAC controls and the existing genuine supervised fixture.
-- No positive native receipt, Root certificate or retained qualification is made.
module NativeSourceJournalV5 (nativeSourceJournalV5Tests) where

import Data.Aeson (Value (..))
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as Map
import Data.List (find)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector qualified as Vector
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Plan.Plan qualified as Plan
import JitML.Product.Matrix qualified as Matrix
import JitML.Substrate (Substrate (LinuxCPU))
import JitML.Test.JournalFixtures qualified as Fixture
import JitML.Test.NativeScenarioJournalBindingData qualified as Binding
import JitML.Test.NativeScenarioReceiptData qualified as Receipt
import JitML.Test.ProductScenarioJournal qualified as Journal
import JitML.Test.Report qualified as Report

nativeSourceJournalV5Tests :: TestTree
nativeSourceJournalV5Tests =
  testGroup
    "native source journal v5 and binding DATA"
    [ testCase "empty native scalar preserves the exact previous nineteen-field v2 semantic transport" $ do
        Binding.nativeScenarioJournalBindingMaterial binding "" @?= oldMaterial binding
    , testCase "nonempty native scalar wraps the entire previous material without dropping fields" $ do
        let native = "ordinary opaque scalar DATA"
        Binding.nativeScenarioJournalBindingMaterial binding native
          @?= Text.concat
            [ field "domain" "jitml-product-scenario-native-authenticated-row-v1"
            , field "previous_semantic_row" (oldMaterial binding)
            , field "native_qualification_receipt" native
            ]
    , testCase "each of all nineteen semantic fields changes native and empty-native binding material" $ do
        length bindingMutations @?= 19
        mapM_
          ( \(label, change) -> do
              assertBool
                (Text.unpack label <> " empty-native omitted")
                (Binding.nativeScenarioJournalBindingMaterial (change binding) "" /= oldMaterial binding)
              assertBool
                (Text.unpack label <> " native omitted")
                ( Binding.nativeScenarioJournalBindingMaterial (change binding) "ordinary"
                    /= Binding.nativeScenarioJournalBindingMaterial binding "ordinary"
                )
          )
          bindingMutations
    , testCase "native scalar exact Unicode NUL and delimiter content remains length-delimited DATA" $ do
        let scalar = "λ\NUL\nprevious_semantic_row=3:bad"
            material = Binding.nativeScenarioJournalBindingMaterial binding scalar
        assertBool
          "exact native text included"
          (field "native_qualification_receipt" scalar `Text.isSuffixOf` material)
        assertBool
          "native empty is a distinct legacy material"
          (material /= Binding.nativeScenarioJournalBindingMaterial binding "")
    , testCase "semantic delimiter-shaped values cannot collide by moving text between fields" $ do
        let left =
              binding
                { Binding.nativeScenarioBindingRowId = "a\nrun_id=1:b"
                , Binding.nativeScenarioBindingRunId = "c"
                }
            rightBinding = binding {Binding.nativeScenarioBindingRowId = "a", Binding.nativeScenarioBindingRunId = "b\nc"}
        assertBool
          "full length-delimited material differs"
          ( Binding.nativeScenarioJournalBindingMaterial left "ordinary"
              /= Binding.nativeScenarioJournalBindingMaterial rightBinding "ordinary"
          )
    , testCase
        "existing genuine supervised fixture writes version five with mandatory empty native scalar"
        $ withOriginal
        $ \scenario original -> do
          rootField "version" original @?= Just (Number 5)
          rowField "native_qualification_receipt" original @?= Just (String "")
          _ <- right =<< Fixture.readScenarioJournal scenario
          pure ()
    , testCase "old version four rejects before an invalid HMAC could be considered" $
        withOriginal $ \scenario original -> do
          write scenario (Fixture.setJournalField "version" (Number 4) (badTag original))
          result <- Fixture.readScenarioJournal scenario
          firstError
            (\case Journal.ProductScenarioJournalVersionMismatch 5 4 -> True; _ -> False)
            result
    , testCase "version five cannot omit the native scalar even on a supervised row" $
        withOriginal $ \scenario original -> do
          write scenario (Fixture.dropRowField "native_qualification_receipt" (badTag original))
          malformed =<< Fixture.readScenarioJournal scenario
    , testCase "native scalar null number or array is a malformed envelope before authentication" $
        withOriginal $ \scenario original ->
          mapM_
            ( \value -> do
                write scenario (Fixture.setRowField "native_qualification_receipt" value (badTag original))
                malformed =<< Fixture.readScenarioJournal scenario
            )
            [Null, Number 1, Array Vector.empty]
    , testCase "unknown row fields cannot silently extend version five" $
        withOriginal $ \scenario original -> do
          write
            scenario
            (Fixture.setRowField "native_qualification_receipt_typo" (String "") (badTag original))
          malformed =<< Fixture.readScenarioJournal scenario
    , testCase "native scalar cap plus one refuses before HMAC or Store admission" $
        withOriginal $ \scenario original -> do
          let oversized = Text.replicate (fromInteger Receipt.maximumNativeScenarioReceiptTextCharacters + 1) "x"
          write
            scenario
            (Fixture.setRowField "native_qualification_receipt" (String oversized) (badTag original))
          result <- Fixture.readScenarioJournal scenario
          firstError (nativeReason "character cap") result
    , testCase "exact native scalar character cap reaches authentication and is not called oversize" $
        withOriginal $ \scenario original -> do
          let exact = Text.replicate (fromInteger Receipt.maximumNativeScenarioReceiptTextCharacters) "x"
          write scenario (Fixture.setRowField "native_qualification_receipt" (String exact) (badTag original))
          authentication =<< Fixture.readScenarioJournal scenario
    , testCase "native scalar preflight counts characters rather than claiming an UTF8 allocation cap" $
        withOriginal $ \scenario original -> do
          let exact = Text.replicate (fromInteger Receipt.maximumNativeScenarioReceiptTextCharacters) "λ"
          write scenario (Fixture.setRowField "native_qualification_receipt" (String exact) (badTag original))
          authentication =<< Fixture.readScenarioJournal scenario
    , testCase "unsigned native scalar substitution changes aggregate HMAC material" $
        withOriginal $ \scenario original -> do
          let changed = Fixture.setRowField "native_qualification_receipt" (String "ordinary not a receipt") original
          assertResignedTagChanged scenario original changed
          write scenario changed
          authentication =<< Fixture.readScenarioJournal scenario
    , testCase
        "every nineteen-field semantic mutation changes the actual tag and refuses the original authentication"
        $ withOriginal
        $ \scenario original -> do
          length semanticWireMutations @?= 19
          mapM_
            ( \(label, change) -> do
                let changed = change original
                assertBool (Text.unpack label <> " mutation must change fixture") (changed /= original)
                assertResignedTagChanged scenario original changed
                write scenario changed
                authentication =<< Fixture.readScenarioJournal scenario
            )
            semanticWireMutations
    , testCase "resigned supervised row still refuses a nonempty native receipt scalar" $
        withOriginal $ \scenario original -> do
          resigned <-
            right
              ( Fixture.resignJournalValue
                  (Fixture.jsKey scenario)
                  (Fixture.setRowField "native_qualification_receipt" (String "ordinary not a receipt") original)
              )
          write scenario resigned
          containsError (nativeReason "non-native source row") =<< Fixture.readScenarioJournal scenario
    , testCase "resigned tuning row refuses native qualification without fabricating a tuning completion" $
        withOriginal $ \scenario original -> do
          row <- requiredRow "hyperparameter-tuning"
          result <-
            readSelected
              scenario
              row
              (Fixture.setRowField "native_qualification_receipt" (String "ordinary not a receipt") original)
          containsError (nativeReason "non-native source row") result
    , testCase "current DQN HER and AlphaZero row shapes require a parsed native scalar" $
        withOriginal $ \scenario original -> do
          rows <- selectedNativeRows
          mapM_
            ( \row -> do
                result <-
                  readSelected
                    scenario
                    row
                    (Fixture.setRowField "supervised_qualification_receipt" (String "") original)
                containsError (nativeReason "prefix differs") result
            )
            rows
    , testCase "current native row shapes refuse any supervised qualification scalar" $
        withOriginal $ \scenario original -> do
          case rowField "supervised_qualification_receipt" original of
            Just (String actual) -> assertBool "actual supervised fixture has a qualification" (not (Text.null actual))
            _ -> assertFailure "actual supervised fixture has no qualification scalar"
          rows <- selectedNativeRows
          mapM_
            ( \row -> do
                result <- readSelected scenario row original
                containsError (nativeReason "carries a supervised qualification") result
            )
            rows
    , testCase "resigning bounded malformed native receipt DATA cannot bypass its complete parser" $
        withOriginal $ \scenario original -> do
          row <- requiredRow "DQN/cartpole"
          let changed =
                Fixture.setRowField
                  "supervised_qualification_receipt"
                  (String "")
                  ( Fixture.setRowField
                      "native_qualification_receipt"
                      (String "native-parent-qualification-v1: 00")
                      original
                  )
          result <- readSelected scenario row changed
          containsError isNativeFailure result
    ]

-- Unique ordinary values make omissions visible; no current Matrix/cap claim.
binding :: Binding.NativeScenarioJournalBindingData
binding =
  Binding.NativeScenarioJournalBindingData
    "row"
    "run"
    "plan"
    "lane"
    "/exe"
    "exe-sha"
    "invocation"
    "experiment"
    "manifest"
    "command"
    "contract"
    "scope"
    "receipt"
    "journal"
    "inference"
    True
    3
    7
    9

bindingMutations
  :: [(Text, Binding.NativeScenarioJournalBindingData -> Binding.NativeScenarioJournalBindingData)]
bindingMutations =
  [ ("row", \x -> x {Binding.nativeScenarioBindingRowId = "changed"})
  , ("run", \x -> x {Binding.nativeScenarioBindingRunId = "changed"})
  , ("plan", \x -> x {Binding.nativeScenarioBindingPlanId = "changed"})
  , ("lane", \x -> x {Binding.nativeScenarioBindingSubstrate = "changed"})
  , ("executable", \x -> x {Binding.nativeScenarioBindingExecutablePath = "/changed"})
  , ("exe-sha", \x -> x {Binding.nativeScenarioBindingExecutableSha256 = "changed"})
  , ("invocation", \x -> x {Binding.nativeScenarioBindingInvocationDigest = "changed"})
  , ("experiment", \x -> x {Binding.nativeScenarioBindingExperimentHash = "changed"})
  , ("manifest", \x -> x {Binding.nativeScenarioBindingManifestSha256 = "changed"})
  , ("command", \x -> x {Binding.nativeScenarioBindingCommand = "changed"})
  , ("contract", \x -> x {Binding.nativeScenarioBindingContractSha256 = "changed"})
  , ("scope", \x -> x {Binding.nativeScenarioBindingCheckpointScopeSha256 = "changed"})
  , ("receipt", \x -> x {Binding.nativeScenarioBindingExecutionJournalReceipt = "changed"})
  , ("journal", \x -> x {Binding.nativeScenarioBindingExecutionJournalSha256 = "changed"})
  , ("inference", \x -> x {Binding.nativeScenarioBindingInferenceManifestSha256 = "changed"})
  , ("precondition", \x -> x {Binding.nativeScenarioBindingPreconditionRejected = False})
  , ("pre-sequence", \x -> x {Binding.nativeScenarioBindingPreconditionSequence = 4})
  , ("inference-sequence", \x -> x {Binding.nativeScenarioBindingInferenceSequence = 8})
  , ("completion-sequence", \x -> x {Binding.nativeScenarioBindingCompletionSequence = 10})
  ]

oldMaterial :: Binding.NativeScenarioJournalBindingData -> Text
oldMaterial x =
  Text.concat
    ( map
        (uncurry field)
        [ ("domain", "jitml-product-scenario-authenticated-row-v2")
        , ("row_id", Binding.nativeScenarioBindingRowId x)
        , ("run_id", Binding.nativeScenarioBindingRunId x)
        , ("plan_id", Binding.nativeScenarioBindingPlanId x)
        , ("substrate", Binding.nativeScenarioBindingSubstrate x)
        , ("executable_path", Text.pack (Binding.nativeScenarioBindingExecutablePath x))
        , ("executable_sha256", Binding.nativeScenarioBindingExecutableSha256 x)
        , ("invocation_digest", Binding.nativeScenarioBindingInvocationDigest x)
        , ("experiment_hash", Binding.nativeScenarioBindingExperimentHash x)
        , ("manifest_sha256", Binding.nativeScenarioBindingManifestSha256 x)
        , ("command", Binding.nativeScenarioBindingCommand x)
        , ("contract_sha256", Binding.nativeScenarioBindingContractSha256 x)
        , ("checkpoint_scope_sha256", Binding.nativeScenarioBindingCheckpointScopeSha256 x)
        , ("execution_journal_receipt", Binding.nativeScenarioBindingExecutionJournalReceipt x)
        , ("execution_journal_sha256", Binding.nativeScenarioBindingExecutionJournalSha256 x)
        , ("inference_manifest_sha256", Binding.nativeScenarioBindingInferenceManifestSha256 x)
        , ("precondition_rejected", showText (Binding.nativeScenarioBindingPreconditionRejected x))
        , ("precondition_sequence", showText (Binding.nativeScenarioBindingPreconditionSequence x))
        , ("inference_sequence", showText (Binding.nativeScenarioBindingInferenceSequence x))
        , ("completion_sequence", showText (Binding.nativeScenarioBindingCompletionSequence x))
        , ("supervised_qualification_receipt", "")
        ]
    )

field :: Text -> Text -> Text
field label value = label <> "=" <> showText (Text.length value) <> ":" <> value <> "\n"
showText :: (Show a) => a -> Text
showText = Text.pack . show

withOriginal :: (Fixture.JournalScenario -> Value -> Assertion) -> Assertion
withOriginal action = Fixture.withJournalScenario $ \scenario -> do
  _ <- right =<< Fixture.resignedIdentityReadable scenario
  original <- Fixture.readJournalValue (Fixture.jsJournalPath scenario)
  action scenario original

write :: Fixture.JournalScenario -> Value -> IO ()
write = Fixture.writeScenarioJournalValue
badTag :: Value -> Value
badTag = Fixture.setJournalField "run_receipt_hmac_sha256" (String "not-a-canonical-hmac")
rootField :: Text -> Value -> Maybe Value
rootField name (Object record) = Map.lookup (Key.fromText name) record
rootField _ _ = Nothing
rowField :: Text -> Value -> Maybe Value
rowField name value = case rootField "rows" value of
  Just (Array values) -> case Vector.toList values of
    Object record : _ -> Map.lookup (Key.fromText name) record
    _ -> Nothing
  _ -> Nothing
alter :: (Text -> Value -> Value -> Value) -> Text -> Value -> Value
alter setter name value = case getter name value of
  Just (String old) -> setter name (String (old <> "-changed")) value
  Just (Number old) -> setter name (Number (old + 1)) value
  Just (Bool old) -> setter name (Bool (not old)) value
  _ -> value
 where
  getter = if name == "checkpoint_scope_sha256" then rootField else rowField

semanticWireMutations :: [(Text, Value -> Value)]
semanticWireMutations =
  [ ( name
    , alter
        (if name == "checkpoint_scope_sha256" then Fixture.setJournalField else Fixture.setRowField)
        name
    )
  | name <-
      [ "row_id"
      , "run_id"
      , "plan_id"
      , "substrate"
      , "executable_path"
      , "executable_sha256"
      , "invocation_digest"
      , "experiment_hash"
      , "manifest_sha256"
      , "command"
      , "contract_sha256"
      , "checkpoint_scope_sha256"
      , "execution_journal_receipt"
      , "execution_journal_sha256"
      , "inference_manifest_sha256"
      , "precondition_rejected"
      , "precondition_sequence"
      , "inference_sequence"
      , "completion_sequence"
      ]
  ]

assertResignedTagChanged :: Fixture.JournalScenario -> Value -> Value -> Assertion
assertResignedTagChanged scenario original changed = do
  resigned <- right (Fixture.resignJournalValue (Fixture.jsKey scenario) changed)
  let old = rootField "run_receipt_hmac_sha256" original
      new = rootField "run_receipt_hmac_sha256" resigned
  assertBool
    "actual production helper produces a changed HMAC"
    (isJust old && isJust new && old /= new)

requiredRow :: Text -> IO (Matrix.ProductRow 'Matrix.Declared)
requiredRow name =
  maybe
    (assertFailure ("canonical row missing: " <> Text.unpack name) >> fail "row")
    pure
    (find ((== name) . Matrix.rowId) Matrix.allProductRows)
selectedNativeRows :: IO [Matrix.ProductRow 'Matrix.Declared]
selectedNativeRows = do
  dqn <- requiredRow "DQN/cartpole"
  her <- requiredRow "HER/goal-reaching"
  arena <-
    maybe
      (assertFailure "canonical AlphaZero row missing" >> fail "row")
      pure
      (find ((== Matrix.AlphaZero) . Matrix.family) Matrix.allProductRows)
  pure [dqn, her, arena]
readSelected
  :: Fixture.JournalScenario
  -> Matrix.ProductRow 'Matrix.Declared
  -> Value
  -> IO
       (Either (NonEmpty.NonEmpty Journal.ProductScenarioJournalError) Report.CompletedProductScenarioReport)
readSelected scenario row original = do
  -- Deliberately stale nonnative labels cannot be positive native evidence.
  -- Only the precise matched-row shape refusal below is asserted.
  batch <- right (Plan.validationToEither (Matrix.projectProductRows LinuxCPU [row]))
  let changed = Fixture.setRowField "row_id" (String (Matrix.rowId row)) original
  resigned <- right (Fixture.resignJournalValue (Fixture.jsKey scenario) changed)
  write scenario resigned
  Journal.readProductScenarioJournal
    (Fixture.jsKey scenario)
    (Fixture.jsJournalPath scenario)
    (Fixture.jsCheckpointRoot scenario)
    (Fixture.jsRunId scenario)
    (Fixture.jsExecutablePath scenario)
    (Fixture.jsExecutableSha scenario)
    batch

firstError
  :: (Journal.ProductScenarioJournalError -> Bool)
  -> Either (NonEmpty.NonEmpty Journal.ProductScenarioJournalError) a
  -> Assertion
firstError predicate value = case value of
  Left (actual NonEmpty.:| _) -> assertBool (show actual) (predicate actual)
  Right _ -> assertFailure "source journal unexpectedly accepted"
containsError
  :: (Journal.ProductScenarioJournalError -> Bool)
  -> Either (NonEmpty.NonEmpty Journal.ProductScenarioJournalError) a
  -> Assertion
containsError predicate value = case value of
  Left errors -> assertBool (show errors) (any predicate (NonEmpty.toList errors))
  Right _ -> assertFailure "source journal unexpectedly accepted"
malformed :: Either (NonEmpty.NonEmpty Journal.ProductScenarioJournalError) a -> Assertion
malformed =
  firstError
    (\case Journal.ProductScenarioJournalMalformed {} -> True; _ -> False)
authentication :: Either (NonEmpty.NonEmpty Journal.ProductScenarioJournalError) a -> Assertion
authentication =
  firstError
    (\case Journal.ProductScenarioJournalAuthenticationRejected {} -> True; _ -> False)
nativeReason :: Text -> Journal.ProductScenarioJournalError -> Bool
nativeReason fragment actual = case actual of
  Journal.ProductScenarioJournalNativeQualificationRejected _ reason -> fragment `Text.isInfixOf` reason
  _ -> False
isNativeFailure :: Journal.ProductScenarioJournalError -> Bool
isNativeFailure actual = case actual of Journal.ProductScenarioJournalNativeQualificationRejected {} -> True; _ -> False
right :: (Show e) => Either e a -> IO a
right (Right value) = pure value
right (Left reason) = assertFailure (show reason) >> fail "fixture"
