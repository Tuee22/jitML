{-# LANGUAGE OverloadedStrings #-}

-- Genuine local filesystem controls. No ML/parent policy cap,
-- launch receipt, journal authorization or successful training is fabricated.
module NativeParentAttemptRetention (nativeParentAttemptRetentionTests) where

import Codec.CBOR.Encoding qualified as CBOR
import Codec.CBOR.Write qualified as CBOR
import Control.Concurrent (forkIO, killThread)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import Control.Exception
  ( AsyncException (ThreadKilled)
  , Exception (displayException)
  , IOException
  , throw
  , try
  )
import Control.Monad ((>=>))
import Crypto.Hash.SHA256 qualified as SHA256
import Data.Bits ((.&.))
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Char (intToDigit)
import Data.List (sort)
import Data.Maybe (isNothing)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as UTF8
import System.Directory
  ( canonicalizePath
  , createDirectory
  , createDirectoryLink
  , createFileLink
  , doesDirectoryExist
  , doesFileExist
  , doesPathExist
  , listDirectory
  , removeFile
  )
import System.FilePath (takeDirectory, (</>))
import System.IO (IOMode (WriteMode), hClose, withBinaryFile)
import System.IO.Error (ioeGetErrorString, isIllegalOperation)
import System.IO.Temp (withSystemTempDirectory)
import System.Posix.Files (fileMode, getSymbolicLinkStatus, setFileMode)
import System.Timeout (timeout)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertEqual, assertFailure, testCase)

import JitML.Checkpoint.NativePhase.Failure qualified as Diagnostic
import JitML.Checkpoint.NativePhase.Types (Resource (DiagnosticTextBytes), nativePhaseLimit)
import JitML.Execution.NativeParentAttemptRetention qualified as Retain
import JitML.Plan.Plan qualified as Plan
import JitML.Substrate (Substrate (AppleSilicon, LinuxCPU))
import JitML.Test.Command qualified as Command
import JitML.Training.Budget qualified as Training

data InputFault = UnicodeFault | EndlessFault | AsyncRendererFault
  deriving stock (Show)
instance Exception InputFault where
  displayException UnicodeFault = "actual parent retention input λ🙂"
  displayException EndlessFault = repeat 'x'
  displayException AsyncRendererFault = throw ThreadKilled

nativeParentAttemptRetentionTests :: TestTree
nativeParentAttemptRetentionTests =
  testGroup
    "native parent attempt filesystem retention"
    [ testCase "actual reservation retains exact issued bytes and canonical run row lane slot" $
        withRoot $ \root -> do
          let issued = BS.pack [0, 255, 128, 1, 10]
              slotInvocation = fixture "run-one" "row-one" LinuxCPU 'a' 'b' 'c' 'd'
          reserved <- reserve root slotInvocation issued
          let expected =
                hex
                  ( SHA256.hash
                      ( encode $
                          CBOR.encodeListLen 4
                            <> CBOR.encodeString "jitml-native-parent-attempt-slot-v1"
                            <> CBOR.encodeString "run-one"
                            <> CBOR.encodeString "row-one"
                            <> CBOR.encodeString "linux-cpu"
                      )
                  )
          assertEqual
            "domain-separated canonical slot digest"
            expected
            (Retain.reservedNativeParentAttemptScopeSha256 reserved)
          assertEqual
            "fixed child scope path"
            (root </> ".build" </> "native-parent-attempts" </> Text.unpack expected)
            (Retain.reservedNativeParentAttemptDirectory reserved)
          verifyFile Retain.IssuedRecordFile issued (Retain.reservedNativeParentAttemptIssued reserved)
          assertEqual "only real issued file" ["issued.cbor"]
            =<< listDirectory (Retain.reservedNativeParentAttemptDirectory reserved)
    , testCase
        "changed challenge plan scope executable and issued bytes cannot replace the same reserved slot"
        $ withRoot
        $ \root -> do
          first <- reserve root (fixture "same-run" "same-row" LinuxCPU 'a' 'b' 'c' 'd') "original"
          refused <-
            Retain.reserveNativeParentAttempt
              root
              (fixture "same-run" "same-row" LinuxCPU 'e' 'f' '1' '2')
              "replacement"
          _ <- failure refused
          assertEqual "original physically retained" "original"
            =<< BS.readFile (Retain.nativeParentAttemptFilePath (Retain.reservedNativeParentAttemptIssued first))
          assertEqual "one stable slot only" 1 . length
            =<< listDirectory (root </> ".build" </> "native-parent-attempts")
    , testCase "distinct run row or lane occupies a different genuine fixed slot" $
        withRoot $ \root -> do
          values <-
            mapM
              (\(run, row, lane) -> reserve root (fixture run row lane 'a' 'b' 'c' 'd') "issued")
              [ ("run", "row", LinuxCPU)
              , ("run2", "row", LinuxCPU)
              , ("run", "row2", LinuxCPU)
              , ("run", "row", AppleSilicon)
              ]
          assertEqual "four physical slots" 4 . length
            =<< listDirectory (root </> ".build" </> "native-parent-attempts")
          assertEqual
            "all scope digests differ"
            4
            (length (unique (map Retain.reservedNativeParentAttemptScopeSha256 values)))
    , testCase "concurrent actual reservations allow exactly one exclusive winner" $
        withRoot $ \root -> do
          -- Create parent dirs first via another row; the shared target still does
          -- not exist, so this exercises exclusive target creation independently.
          _ <- reserve root (fixture "parent-seed" "row" LinuxCPU 'a' 'b' 'c' 'd') "parent"
          let action = Retain.reserveNativeParentAttempt root invocation "same-issued"
          leftResult <- newEmptyMVar
          rightResult <- newEmptyMVar
          _ <- forkIO (action >>= putMVar leftResult)
          _ <- forkIO (action >>= putMVar rightResult)
          left <- takeMVar leftResult
          right <- takeMVar rightResult
          assertEqual "one actual IO reservation" 1 (length [() | Right _ <- [left, right]])
          assertEqual "one concrete refusal" 1 (length [() | Left _ <- [left, right]])
    , testCase "issued cap plus one refuses before path invocation or filesystem access" $
        withRoot $ \root -> do
          actual <-
            Retain.reserveNativeParentAttempt
              (error "oversize must precede path")
              (error "oversize must precede invocation")
              (BS.replicate 65537 0)
          denied <- failure actual
          assertEqual
            "input stage"
            Retain.AttemptReservationInput
            (Retain.nativeParentAttemptFailureStage denied)
          assertEqual "no slot path invented" Nothing (Retain.nativeParentAttemptFailureDirectory denied)
          assertBool "no child .build created" . not =<< doesPathExist (root </> ".build")
    , testCase "issued exact 64 KiB is physically retained without truncation" $
        withRoot $ \root -> do
          let issued = BS.replicate 65536 0xff
          reserved <- reserve root invocation issued
          verifyFile Retain.IssuedRecordFile issued (Retain.reservedNativeParentAttemptIssued reserved)
    , testCase "relative and non-normalized child paths refuse before reservation" $
        withRoot $ \root -> do
          _ <- failure =<< Retain.reserveNativeParentAttempt "relative-child" invocation "issued"
          _ <-
            failure
              =<< Retain.reserveNativeParentAttempt (root </> ".." </> "not-a-canonical-path") invocation "issued"
          assertBool "actual child remains untouched" . not =<< doesPathExist (root </> ".build")
    , testCase "symlink child directory is rejected rather than canonicalized into another scope" $
        withRoot $ \root -> withRoot $ \target -> do
          let alias = root </> "child-link"
          createDirectoryLink target alias
          _ <- failure =<< Retain.reserveNativeParentAttempt alias invocation "issued"
          assertBool "target not written" . not =<< doesPathExist (target </> ".build")
    , testCase "existing symlink parent prefix refuses without writing its target" $
        withRoot $ \root -> withRoot $ \target -> do
          createDirectoryLink target (root </> ".build")
          _ <- failure =<< Retain.reserveNativeParentAttempt root invocation "issued"
          assertEqual "target remains empty" [] =<< listDirectory target
    , testCase "dangling symlink parent prefix is not treated as a missing directory" $
        withRoot $ \root -> do
          createFileLink (root </> "missing-target") (root </> ".build")
          _ <- failure =<< Retain.reserveNativeParentAttempt root invocation "issued"
          assertBool "missing target is not materialized" . not =<< doesPathExist (root </> "missing-target")
    , testCase "actual Unicode report and binary invalid UTF8 NUL streams roundtrip exact physical hashes" $
        withRoot $ \root -> do
          reserved <- reserve root invocation "issued"
          let report = "actual report λ🙂\NUL\nwithout a fabricated final newline"
              stdoutBytes = LBS.pack [0, 255, 128, 65, 10]
              stderrBytes = LBS.pack [254, 0, 69]
          retained <-
            retainedResult
              =<< Retain.retainNativeParentAttemptResult reserved report (Just (stdoutBytes, stderrBytes))
          verifyInventory retained report (Just (stdoutBytes, stderrBytes))
          assertEqual
            "same original reservation"
            (Retain.reservedNativeParentAttemptDirectory reserved)
            (Retain.reservedNativeParentAttemptDirectory (Retain.retainedNativeParentAttemptReserved retained))
    , testCase "unavailable raw streams have absent inventory slots and no placeholder files" $
        withRoot $ \root -> do
          reserved <- reserve root invocation "issued"
          retained <- retainedResult =<< Retain.retainNativeParentAttemptResult reserved "report" Nothing
          verifyInventory retained "report" Nothing
          let inventory = Retain.retainedNativeParentAttemptInventory retained
          assertBool "stdout absent" (isNothing (Retain.nativeParentAttemptStdoutFile inventory))
          assertBool "stderr absent" (isNothing (Retain.nativeParentAttemptStderrFile inventory))
          assertEqual "only two actual result files" ["availability.cbor", "report.utf8"] . sort
            =<< listDirectory (Retain.retainedNativeParentAttemptDirectory retained)
    , testCase "actual empty raw streams create zero byte files distinct from unavailable streams" $
        withRoot $ \root -> do
          reserved <- reserve root invocation ""
          retained <-
            retainedResult =<< Retain.retainNativeParentAttemptResult reserved "" (Just (LBS.empty, LBS.empty))
          verifyInventory retained "" (Just (LBS.empty, LBS.empty))
          assertEqual
            "all four actual result files"
            ["availability.cbor", "report.utf8", "stderr.bin", "stdout.bin"]
            . sort
            =<< listDirectory (Retain.retainedNativeParentAttemptDirectory retained)
    , testCase "second terminal retention cannot force replacement inputs or overwrite prior files" $
        withRoot $ \root -> do
          reserved <- reserve root invocation "issued"
          retained <-
            retainedResult =<< Retain.retainNativeParentAttemptResult reserved "first report" Nothing
          denied <-
            failure
              =<< Retain.retainNativeParentAttemptResult
                reserved
                (error "spent report must stay unforced")
                (error "spent raw must stay unforced")
          assertEqual
            "exclusive terminal claim refused"
            Retain.AttemptResultClaim
            (Retain.nativeParentAttemptFailureStage denied)
          verifyInventory retained "first report" Nothing
    , testCase "lazy report fault preserves its partial physical file and consumes terminal slot" $
        withRoot $ \root -> do
          reserved <- reserve root invocation "issued"
          denied <-
            failure
              =<< Retain.retainNativeParentAttemptResult
                reserved
                (replicate 4096 'x' <> error "actual report suffix fault")
                Nothing
          assertEqual "write stage" Retain.AttemptResultWrite (Retain.nativeParentAttemptFailureStage denied)
          let result = Retain.reservedNativeParentAttemptDirectory reserved </> "result"
          assertEqual "already written prefix is neither erased nor called complete" (BS.replicate 4096 120)
            =<< BS.readFile (result </> "report.utf8")
          _ <- failure =<< Retain.retainNativeParentAttemptResult reserved "retry forbidden" Nothing
          assertBool "no availability success record invented" . not
            =<< doesFileExist (result </> "availability.cbor")
    , testCase "lazy raw fault is forced after claim and before any report or raw file write" $
        withRoot $ \root -> do
          reserved <- reserve root invocation "issued"
          let bytes = LBS.fromChunks [BS.singleton 1, error "actual raw chunk fault"]
          denied <-
            failure
              =<< Retain.retainNativeParentAttemptResult
                reserved
                (error "raw precount must precede report")
                (Just (bytes, LBS.empty))
          assertEqual
            "input precount stage"
            Retain.AttemptResultInput
            (Retain.nativeParentAttemptFailureStage denied)
          assertEqual "claimed empty result dir remains" []
            =<< listDirectory (Retain.reservedNativeParentAttemptDirectory reserved </> "result")
          _ <- failure =<< Retain.retainNativeParentAttemptResult reserved "no retry" Nothing
          pure ()
    , testCase "surrogate report refuses lossy replacement after consuming terminal attempt" $
        withRoot $ \root -> do
          reserved <- reserve root invocation "issued"
          _ <- failure =<< Retain.retainNativeParentAttemptResult reserved ['\xd800'] Nothing
          assertEqual "no replacement UTF8 bytes written" BS.empty
            =<< BS.readFile (Retain.reservedNativeParentAttemptDirectory reserved </> "result" </> "report.utf8")
          _ <- failure =<< Retain.retainNativeParentAttemptResult reserved "retry forbidden" Nothing
          pure ()
    , testCase "tampered issued physical bytes prevent a retained result capability" $
        withRoot $ \root -> do
          reserved <- reserve root invocation "original issued"
          BS.writeFile
            (Retain.nativeParentAttemptFilePath (Retain.reservedNativeParentAttemptIssued reserved))
            "tampered issued"
          denied <- failure =<< Retain.retainNativeParentAttemptResult reserved "actual report" Nothing
          assertEqual
            "physical final readback stage"
            Retain.AttemptResultReadback
            (Retain.nativeParentAttemptFailureStage denied)
          assertBool "attempt remains consumed"
            =<< doesDirectoryExist (Retain.reservedNativeParentAttemptDirectory reserved </> "result")
    , testCase
        "role count caps admit exact maxima and refuse plus one or negative without huge allocations"
        $ do
          mapM_
            ( \(kind, cap) -> do
                assertEqual "exact boundary" (Right ()) (Retain.checkNativeParentAttemptByteCount kind cap)
                assertLeft (Retain.checkNativeParentAttemptByteCount kind (cap + 1))
                assertLeft (Retain.checkNativeParentAttemptByteCount kind (-1))
            )
            [ (Retain.IssuedRecordFile, 65536)
            , (Retain.ParentReportFile, 4294967296)
            , (Retain.ParentStdoutFile, 1073741824)
            , (Retain.ParentStderrFile, 1073741824)
            , (Retain.RawAvailabilityFile, 4096)
            ]
    , testCase "poisoned issued input refuses without filesystem effects or a reservation" $
        withRoot $ \root -> do
          denied <-
            failure =<< Retain.reserveNativeParentAttempt root invocation (error "actual issued input fault")
          assertEqual
            "preflight stage"
            Retain.AttemptReservationInput
            (Retain.nativeParentAttemptFailureStage denied)
          assertBool "no .build" . not =<< doesPathExist (root </> ".build")
    , testCase "exact Unicode synchronous input diagnostic is retained before filesystem access" $ do
        denied <- failure =<< Retain.reserveNativeParentAttempt (throw UnicodeFault) invocation "issued"
        assertEqual
          "exact bounded diagnostic"
          (Diagnostic.CompleteNativeDiagnostic "actual parent retention input λ🙂")
          (Retain.nativeParentAttemptFailureDiagnostic denied)
        assertEqual
          "no safely observed path fabricated"
          Nothing
          (Retain.nativeParentAttemptFailureDirectory denied)
    , testCase "endless synchronous input renderer refuses within bounded diagnostic capture" $ do
        result <-
          timeout 10000000 (Retain.reserveNativeParentAttempt (throw EndlessFault) invocation "issued")
        case result of
          Just (Left denied) ->
            assertEqual
              "only cap plus one lower bound"
              ( Diagnostic.OversizeNativeDiagnostic
                  (Diagnostic.LowerBoundNativeSize (fromInteger (nativePhaseLimit DiagnosticTextBytes + 1)))
              )
              (Retain.nativeParentAttemptFailureDiagnostic denied)
          _ -> assertFailure "endless diagnostic escaped its bound or fabricated a reserved attempt"
    , testCase "input asynchronous cancellation propagates before any filesystem effect" $
        withRoot $ \root -> do
          result <-
            try (Retain.reserveNativeParentAttempt root invocation (throw ThreadKilled))
              :: IO
                   (Either AsyncException (Either Retain.NativeParentAttemptFailure Retain.ReservedNativeParentAttempt))
          assertAsync result
          assertBool "no reservation created" . not =<< doesPathExist (root </> ".build")
    , testCase "diagnostic renderer asynchronous cancellation propagates without a refusal substitute" $ do
        result <-
          try (Retain.reserveNativeParentAttempt (throw AsyncRendererFault) invocation "issued")
            :: IO
                 (Either AsyncException (Either Retain.NativeParentAttemptFailure Retain.ReservedNativeParentAttempt))
        assertAsync result
    , testCase "raw asynchronous cancellation leaves actual terminal directory claimed and forbids retry" $
        withRoot $ \root -> do
          reserved <- reserve root invocation "issued"
          result <-
            try
              (Retain.retainNativeParentAttemptResult reserved "report" (Just (throw ThreadKilled, LBS.empty)))
              :: IO
                   (Either AsyncException (Either Retain.NativeParentAttemptFailure Retain.RetainedNativeParentAttempt))
          assertAsync result
          assertEqual "no files written before raw pre-count" []
            =<< listDirectory (Retain.reservedNativeParentAttemptDirectory reserved </> "result")
          _ <- failure =<< Retain.retainNativeParentAttemptResult reserved "retry forbidden" Nothing
          pure ()
    , testCase "report asynchronous cancellation propagates while preserving consumed terminal attempt" $
        withRoot $ \root -> do
          reserved <- reserve root invocation "issued"
          result <-
            try (Retain.retainNativeParentAttemptResult reserved (throw ThreadKilled) Nothing)
              :: IO
                   (Either AsyncException (Either Retain.NativeParentAttemptFailure Retain.RetainedNativeParentAttempt))
          assertAsync result
          assertBool "terminal directory remains"
            =<< doesDirectoryExist (Retain.reservedNativeParentAttemptDirectory reserved </> "result")
          _ <- failure =<< Retain.retainNativeParentAttemptResult reserved "retry forbidden" Nothing
          pure ()
    , commandAttemptDirectoryTests
    ]

commandAttemptDirectoryTests :: TestTree
commandAttemptDirectoryTests =
  testGroup
    "command attempt directory lifetime"
    [ testCase
        "successful fresh private canonical scopes retain real attempt bytes and never reuse prior names"
        $ withRoot
        $ \root -> do
          let retainedRoot = root </> "attempts"
              alias = root </> "attempts-alias"
          createDirectory retainedRoot
          setFileMode retainedRoot 0o750
          createDirectoryLink retainedRoot alias
          first <- Command.withProductScenarioAttemptDirectory alias writeCommandAttempt
          second <-
            Command.withProductScenarioAttemptDirectory retainedRoot $ \parent -> do
              actual <- writeCommandAttempt parent
              -- Existing per-step release may already have removed the key.
              removeFile (parent </> "journal.key")
              pure actual
          assertBool "new run namespace on every call" (fst first /= fst second)
          assertEqual "first parent uses the physical canonical root" retainedRoot (takeDirectory (fst first))
          assertEqual
            "second parent uses the physical canonical root"
            retainedRoot
            (takeDirectory (fst second))
          assertEqual "existing runtime root permissions remain unchanged" 0o750
            . (.&. 0o777)
            . fileMode
            =<< getSymbolicLinkStatus retainedRoot
          mapM_ verifyCommandAttempt [first, second]
    , testCase
        "synchronous failed body preserves the actual original report and binary streams and erases key"
        $ withRoot
        $ \root -> do
          observed <- newEmptyMVar
          result <-
            try
              ( Command.withProductScenarioAttemptDirectory root $ \parent -> do
                  actual <- writeCommandAttempt parent
                  putMVar observed actual
                  ioError (userError "actual command body failure")
              )
              :: IO (Either IOException ())
          case result of
            Left exception ->
              assertEqual
                "original failure propagates"
                "actual command body failure"
                (ioeGetErrorString exception)
            Right () -> assertFailure "failed body became successful"
          verifyCommandAttempt =<< takeMVar observed
    , testCase
        "external ThreadKilled propagates while preserving the actual report and streams and erasing key"
        $ withRoot
        $ \root -> do
          observed <- newEmptyMVar
          never <- newEmptyMVar
          finished <- newEmptyMVar
          worker <- forkIO $ do
            result <-
              try
                ( Command.withProductScenarioAttemptDirectory root $ \parent -> do
                    actual <- writeCommandAttempt parent
                    putMVar observed actual
                    takeMVar never
                )
                :: IO (Either AsyncException ())
            putMVar finished result
          actual <- takeMVar observed
          killThread worker
          outcome <- timeout 10000000 (takeMVar finished)
          case outcome of
            Just result -> assertAsync result
            Nothing -> assertFailure "cancelled command scope did not release its key"
          verifyCommandAttempt actual
    , testCase "setup failure before key creation retains its diagnostic file without inventing a key" $
        withRoot $ \root -> do
          observed <- newEmptyMVar
          result <-
            try
              ( Command.withProductScenarioAttemptDirectory root $ \parent -> do
                  BS.writeFile (parent </> "setup.started") "actual setup bytes"
                  putMVar observed parent
                  ioError (userError "actual command setup failure")
              )
              :: IO (Either IOException ())
          case result of
            Left exception ->
              assertEqual "setup failure propagates" "actual command setup failure" (ioeGetErrorString exception)
            Right () -> assertFailure "failed setup became successful"
          parent <- takeMVar observed
          assertEqual "setup file survives" "actual setup bytes" =<< BS.readFile (parent </> "setup.started")
          assertBool "no signing key survives" . not =<< doesPathExist (parent </> "journal.key")
    , testCase "real partial key write failure removes exact key and preserves other setup bytes" $
        withRoot $ \root -> do
          observed <- newEmptyMVar
          result <-
            try
              ( Command.withProductScenarioAttemptDirectory root $ \parent -> do
                  BS.writeFile (parent </> "setup.started") "actual setup bytes"
                  putMVar observed parent
                  withBinaryFile (parent </> "journal.key") WriteMode $ \handle -> do
                    BS.hPut handle "actual partial key bytes"
                    hClose handle
                    BS.hPut handle "write to closed handle must fail"
              )
              :: IO (Either IOException ())
          case result of
            Left exception -> assertBool "real handle write failure propagates" (isIllegalOperation exception)
            Right () -> assertFailure "closed-handle key write unexpectedly succeeded"
          parent <- takeMVar observed
          assertEqual "other setup bytes survive" "actual setup bytes"
            =<< BS.readFile (parent </> "setup.started")
          assertBool "partial signing key is removed" . not =<< doesPathExist (parent </> "journal.key")
    , testCase "key release propagates filesystem errors other than genuine absence" $
        withRoot $ \root -> do
          observed <- newEmptyMVar
          result <-
            try
              ( Command.withProductScenarioAttemptDirectory root $ \parent -> do
                  BS.writeFile (parent </> "setup.started") "actual setup bytes"
                  createDirectory (parent </> "journal.key")
                  putMVar observed parent
              )
              :: IO (Either IOException ())
          case result of
            Left _ -> pure ()
            Right () -> assertFailure "non-file key cleanup failure was silently ignored"
          parent <- takeMVar observed
          assertBool "scope remains retained" =<< doesDirectoryExist parent
          assertBool "cleanup did not delete a directory recursively"
            =<< doesDirectoryExist (parent </> "journal.key")
          assertEqual "unrelated file remains exact" "actual setup bytes"
            =<< BS.readFile (parent </> "setup.started")
    ]

writeCommandAttempt :: FilePath -> IO (FilePath, Retain.RetainedNativeParentAttempt)
writeCommandAttempt parent = do
  -- These bytes are ordinary test data, never a journal authorization key.
  BS.writeFile (parent </> "journal.key") "ordinary signing-key placeholder"
  BS.writeFile (parent </> "journal.json") "ordinary journal bytes"
  let workspace = parent </> "workspace"
  createDirectory workspace
  reserved <- reserve workspace invocation "actual issued bytes"
  retained <-
    retainedResult
      =<< Retain.retainNativeParentAttemptResult reserved commandReport (Just commandRaw)
  pure (parent, retained)

verifyCommandAttempt :: (FilePath, Retain.RetainedNativeParentAttempt) -> Assertion
verifyCommandAttempt (parent, retained) = do
  assertEqual "parent remains physically canonical" parent =<< canonicalizePath parent
  assertEqual "fresh parent is private mode 0700" 0o700
    . (.&. 0o777)
    . fileMode
    =<< getSymbolicLinkStatus parent
  assertBool "exact signing key is removed" . not =<< doesPathExist (parent </> "journal.key")
  assertEqual "journal bytes remain retained" "ordinary journal bytes"
    =<< BS.readFile (parent </> "journal.json")
  verifyFile
    Retain.IssuedRecordFile
    "actual issued bytes"
    (Retain.nativeParentAttemptIssuedFile (Retain.retainedNativeParentAttemptInventory retained))
  verifyInventory retained commandReport (Just commandRaw)

commandReport :: String
commandReport = "actual command-scoped report λ🙂"

commandRaw :: (LBS.ByteString, LBS.ByteString)
commandRaw = (LBS.pack [0, 255, 128, 10], LBS.pack [254, 0, 69])

withRoot :: (FilePath -> IO a) -> IO a
withRoot action = withSystemTempDirectory "jitml-native-parent-retention" (canonicalizePath >=> action)

invocation :: Training.ProductScenarioInvocation
invocation = fixture "actual-test-run" "actual-test-row" LinuxCPU 'a' 'b' 'c' 'd'

fixture
  :: Text -> Text -> Substrate -> Char -> Char -> Char -> Char -> Training.ProductScenarioInvocation
fixture run row lane plan scope executable challenge = either (error . Text.unpack) id $ do
  planId <- Plan.refinePlanIdText (Text.replicate 64 (Text.singleton plan))
  Training.mkProductScenarioInvocation
    run
    row
    planId
    lane
    (sha scope)
    (sha executable)
    (sha challenge)
 where
  sha value = Text.replicate 64 (Text.singleton value)

reserve
  :: FilePath
  -> Training.ProductScenarioInvocation
  -> BS.ByteString
  -> IO Retain.ReservedNativeParentAttempt
reserve root scope issued =
  Retain.reserveNativeParentAttempt root scope issued >>= \case
    Right actual -> pure actual
    Left denied -> assertFailure (show denied) >> fail "unreachable"

retainedResult
  :: Either Retain.NativeParentAttemptFailure Retain.RetainedNativeParentAttempt
  -> IO Retain.RetainedNativeParentAttempt
retainedResult = \case
  Right actual -> pure actual
  Left denied -> assertFailure (show denied) >> fail "unreachable"

failure :: Either Retain.NativeParentAttemptFailure a -> IO Retain.NativeParentAttemptFailure
failure = \case
  Left actual -> pure actual
  Right _ -> assertFailure "filesystem refusal fabricated an attempt capability" >> fail "unreachable"

verifyInventory
  :: Retain.RetainedNativeParentAttempt -> String -> Maybe (LBS.ByteString, LBS.ByteString) -> Assertion
verifyInventory retained report raw = do
  let inventory = Retain.retainedNativeParentAttemptInventory retained
      present = case raw of Nothing -> False; Just _ -> True
      availability =
        encode
          ( CBOR.encodeListLen 4
              <> CBOR.encodeString "jitml-native-parent-raw-availability-v1"
              <> CBOR.encodeWord 1
              <> CBOR.encodeBool present
              <> CBOR.encodeBool present
          )
  verifyFile
    Retain.ParentReportFile
    (UTF8.encodeUtf8 (Text.pack report))
    (Retain.nativeParentAttemptReportFile inventory)
  verifyFile
    Retain.RawAvailabilityFile
    availability
    (Retain.nativeParentAttemptAvailabilityFile inventory)
  case ( raw
       , Retain.nativeParentAttemptStdoutFile inventory
       , Retain.nativeParentAttemptStderrFile inventory
       ) of
    (Nothing, Nothing, Nothing) -> pure ()
    (Just (stdoutBytes, stderrBytes), Just stdoutFile, Just stderrFile) -> do
      verifyFile Retain.ParentStdoutFile (LBS.toStrict stdoutBytes) stdoutFile
      verifyFile Retain.ParentStderrFile (LBS.toStrict stderrBytes) stderrFile
    _ -> assertFailure "raw absence/empty/actual physical slots were conflated"
  let issued = Retain.nativeParentAttemptIssuedFile inventory
  assertEqual
    "same issued DATA preserved"
    (Retain.reservedNativeParentAttemptIssued (Retain.retainedNativeParentAttemptReserved retained))
    issued
  assertEqual
    "issued regular file in slot"
    (Retain.reservedNativeParentAttemptDirectory (Retain.retainedNativeParentAttemptReserved retained))
    (takeDirectory (Retain.nativeParentAttemptFilePath issued))

verifyFile
  :: Retain.NativeParentAttemptFileKind
  -> BS.ByteString
  -> Retain.NativeParentAttemptFileData
  -> Assertion
verifyFile kind expected actual = do
  assertEqual "exact role" kind (Retain.nativeParentAttemptFileKind actual)
  bytes <- BS.readFile (Retain.nativeParentAttemptFilePath actual)
  assertEqual "exact physical bytes" expected bytes
  assertEqual
    "independent physical count"
    (fromIntegral (BS.length bytes))
    (Retain.nativeParentAttemptFileBytes actual)
  assertEqual
    "independent physical SHA256"
    (hex (SHA256.hash bytes))
    (Retain.nativeParentAttemptFileSha256 actual)

assertLeft :: Either a b -> Assertion
assertLeft (Left _) = pure ()
assertLeft (Right _) = assertFailure "out-of-bound ordinary count was accepted"

assertAsync :: Either AsyncException a -> Assertion
assertAsync (Left ThreadKilled) = pure ()
assertAsync _ = assertFailure "asynchronous cancellation became a filesystem result"

encode :: CBOR.Encoding -> BS.ByteString
encode = LBS.toStrict . CBOR.toLazyByteString
hex :: BS.ByteString -> Text
hex =
  Text.pack
    . concatMap
      (\byte -> [intToDigit (fromIntegral byte `div` 16), intToDigit (fromIntegral byte `mod` 16)])
    . BS.unpack
unique :: (Eq a) => [a] -> [a]
unique = foldr (\value rest -> if value `elem` rest then rest else value : rest) []
