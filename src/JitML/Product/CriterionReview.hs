{-# LANGUAGE OverloadedStrings #-}

-- | Actual bounded observations of independently selected governed review files.
-- Captured does not mean reviewer independence, execution, admission or a pass.
module JitML.Product.CriterionReview
  ( CriterionReviewError (..)
  , renderCriterionReviewError
  , CapturedCriterionReview
  , capturedCriterionReviewIdentity
  , captureCriterionReviewIn
  ) where

import Control.Exception (IOException, fromException)
import Control.Exception.Safe (tryAny)
import Control.Monad (unless, void)
import Control.Monad.Except (ExceptT, runExceptT, throwError)
import Control.Monad.IO.Class (liftIO)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as Text
import JitML.Checkpoint.NativePhase.Failure qualified as Failure
import JitML.Product.CriterionReviewData
import JitML.Product.LaneRegistrationData (SelectedLaneFileData (..))
import JitML.Product.SourceDigest (SourceStamp)
import JitML.Product.ValidationRecord (sha256Hex)
import JitML.Substrate (Substrate)
import System.Directory (canonicalizePath)
import System.FilePath (splitDirectories, (</>))
import System.IO (IOMode (ReadMode), withBinaryFile)
import System.IO.Error (isDoesNotExistError)
import System.Posix.Files (getSymbolicLinkStatus, isDirectory, isRegularFile, isSymbolicLink)

data CriterionReviewError
  = CriterionReviewMissingFile !Failure.NativeDiagnosticData
  | CriterionReviewReadFailure !Failure.NativeDiagnosticData
  | CriterionReviewRejected !Text
  | CriterionReviewIdentityMismatch !Text
  deriving stock (Eq, Show)
renderCriterionReviewError :: CriterionReviewError -> Text
renderCriterionReviewError = Text.pack . show

newtype CapturedCriterionReview = CapturedCriterionReview CriterionReviewIdentityData
  deriving stock (Eq, Show)
capturedCriterionReviewIdentity :: CapturedCriterionReview -> CriterionReviewIdentityData
capturedCriterionReviewIdentity (CapturedCriterionReview value) = value

captureCriterionReviewIn
  :: FilePath
  -> SourceStamp
  -> Substrate
  -> CriterionReviewScope
  -> IO (Either CriterionReviewError CapturedCriterionReview)
captureCriterionReviewIn root source lane scope = do
  attempted <- tryAny (runExceptT observe)
  case attempted of
    Left exception -> do
      diagnostic <- Failure.captureNativeExceptionDiagnostic exception
      pure
        ( Left
            ( case fromException exception :: Maybe IOException of
                Just io | isDoesNotExistError io -> CriterionReviewMissingFile diagnostic
                _ -> CriterionReviewReadFailure diagnostic
            )
        )
    Right actual -> pure actual
 where
  observe = do
    -- Validate expected source/path DATA before any filesystem operation.
    let selected = criterionReviewSelectionPath source lane scope
        probe = SelectedLaneFileData (Text.pack selected) (Text.replicate 64 "0") 1
        provisional =
          CriterionReviewIdentityData
            scope
            lane
            source
            probe
            ( SelectedLaneFileData
                (Text.pack (take (length selected - length ("selection.cbor" :: String)) selected <> "receipt.cbor"))
                (Text.replicate 64 "0")
                1
            )
            (Text.replicate 64 "0")
    _ <- checked (refineCriterionReviewIdentityData provisional)
    rootPrefix <- checkedPath root
    selectionBytes <- readBounded rootPrefix selected 16384
    selection <- checked (decodeCriterionReviewSelectionData selectionBytes)
    identityRequire
      ( reviewSelectionSource selection == source
          && reviewSelectionSubstrate selection == lane
          && reviewSelectionScope selection == scope
      )
      "selected criterion review differs from original source lane or scope"
    let receiptRef = reviewSelectionReceipt selection
    receiptBytes <- readPinned rootPrefix receiptRef 65536
    receipt <- checked (decodeCriterionReviewReceiptData receiptBytes)
    identityRequire
      ( reviewReceiptSource receipt == source
          && reviewReceiptSubstrate receipt == lane
          && reviewReceiptScope receipt == scope
      )
      "criterion review receipt differs from selected original source lane or scope"
    -- The actual selected receipt cannot list itself as an independent artifact.
    require
      (all ((/= selectedLaneFilePath receiptRef) . selectedLaneFilePath) (reviewReceiptArtifacts receipt))
      "criterion review artifact list contains its own receipt"
    mapM_
      (\ref -> void (readPinned rootPrefix ref (4 * 1024 * 1024)))
      (reviewReceiptArtifacts receipt)
    contracts <- checked (criterionReviewReceiptContractsSha256 receipt)
    let identity =
          CriterionReviewIdentityData
            scope
            lane
            source
            ( SelectedLaneFileData
                (Text.pack selected)
                (sha256Hex selectionBytes)
                (fromIntegral (BS.length selectionBytes))
            )
            receiptRef
            contracts
    CapturedCriterionReview <$> checked (refineCriterionReviewIdentityData identity)
  identityRequire :: Bool -> Text -> ExceptT CriterionReviewError IO ()
  identityRequire condition reason = unless condition (throwError (CriterionReviewIdentityMismatch reason))
  checked :: Either Text a -> ExceptT CriterionReviewError IO a
  checked = either (throwError . CriterionReviewRejected) pure
  require :: Bool -> Text -> ExceptT CriterionReviewError IO ()
  require condition reason = unless condition (throwError (CriterionReviewRejected reason))
  checkedPath :: FilePath -> ExceptT CriterionReviewError IO FilePath
  checkedPath path = do
    require
      (length (take 4097 path) <= 4096 && notElem '\0' (take 4097 path))
      "criterion review root path exceeds preflight or contains NUL"
    ensurePrefixes path True
    canonical <- liftIO (canonicalizePath path)
    ensurePrefixes canonical True
    pure canonical
  readPinned
    :: FilePath -> SelectedLaneFileData -> Integer -> ExceptT CriterionReviewError IO BS.ByteString
  readPinned base ref cap = do
    bytes <- readBounded base (Text.unpack (selectedLaneFilePath ref)) cap
    require
      ( toInteger (BS.length bytes) == toInteger (selectedLaneFileBytes ref)
          && sha256Hex bytes == selectedLaneFileSha256 ref
      )
      "actual criterion review file differs from independently selected byte count or SHA256"
    pure bytes
  readBounded :: FilePath -> FilePath -> Integer -> ExceptT CriterionReviewError IO BS.ByteString
  readBounded base relative cap = do
    let path = base </> relative
    ensurePrefixes path False
    bytes <- liftIO (withBinaryFile path ReadMode (\handle -> BS.hGet handle (fromInteger cap + 1)))
    require (toInteger (BS.length bytes) <= cap) "actual criterion review file exceeds role cap"
    ensurePrefixes path False
    pure bytes
  ensurePrefixes :: FilePath -> Bool -> ExceptT CriterionReviewError IO ()
  ensurePrefixes path finalDirectory = walk "" (splitDirectories path)
   where
    walk :: FilePath -> [FilePath] -> ExceptT CriterionReviewError IO ()
    walk _ [] = pure ()
    walk prefix (part : rest) = do
      let current = if null prefix then part else prefix </> part
      status <- liftIO (getSymbolicLinkStatus current)
      require (not (isSymbolicLink status)) "criterion review path has a symbolic link prefix"
      require
        (if null rest && not finalDirectory then isRegularFile status else isDirectory status)
        "criterion review path has an unsupported physical file kind"
      walk current rest
