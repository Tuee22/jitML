{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Current production lane admission under a separately selected generation.
-- The constructor is private. Raw selection DATA and passing flags cannot mint
-- this value; every instance comes from the fixed governed selection FILE path
-- and the unchanged full portable lane admission boundary.
module JitML.Test.RegisteredLaneEvidence
  ( RegisteredLaneEvidence
  , RegisteredLaneError (..)
  , loadRegisteredLaneEvidence
  , loadRegisteredLaneEvidenceIn
  , registeredLaneRegistration
  , registeredLaneBatch
  , registeredLaneJournal
  , currentLaneRowContracts
  , checkRegisteredLaneGeneration
  , checkRegisteredLaneReviewBindings
  )
where

import Control.Monad (unless)
import Data.Either.Combinators (mapLeft)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Text (Text)
import Data.Text qualified as Text
import System.FilePath ((</>))

import JitML.Plan.Plan (Validation (..), planIdText)
import JitML.Product.LaneRegistration qualified as Registration
import JitML.Product.LaneRegistrationData
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.QualificationObjects (readProductLaneQualificationObjects)
import JitML.Product.SourceDigest (SourceStamp)
import JitML.Substrate (Substrate)
import JitML.Test.ProductLaneJournal qualified as Lane
import JitML.Test.Report qualified as Report

data RegisteredLaneEvidence = RegisteredLaneEvidence
  { registeredRegistrationValue :: !Registration.LoadedLaneRegistration
  , registeredBatchValue :: !Matrix.ProductProjectionBatch
  , registeredJournalValue :: !Lane.AdmittedProductLaneJournal
  }
  deriving stock (Eq, Show)

registeredLaneRegistration :: RegisteredLaneEvidence -> Registration.LoadedLaneRegistration
registeredLaneRegistration = registeredRegistrationValue

registeredLaneBatch :: RegisteredLaneEvidence -> Matrix.ProductProjectionBatch
registeredLaneBatch = registeredBatchValue

registeredLaneJournal :: RegisteredLaneEvidence -> Lane.AdmittedProductLaneJournal
registeredLaneJournal = registeredJournalValue

data RegisteredLaneError
  = RegisteredLaneSelectionRejected !Registration.LaneRegistrationError
  | RegisteredLaneProjectionRejected !(NonEmpty Matrix.ProductMatrixError)
  | RegisteredLaneContractsStale !Text !Text
  | RegisteredLaneBindingRejected !Text
  | RegisteredLaneJournalRejected !(NonEmpty Lane.ProductLaneJournalError)
  deriving stock (Eq, Show)

loadRegisteredLaneEvidence :: Substrate -> IO (Either RegisteredLaneError RegisteredLaneEvidence)
loadRegisteredLaneEvidence = loadRegisteredLaneEvidenceIn "."

loadRegisteredLaneEvidenceIn
  :: FilePath -> Substrate -> IO (Either RegisteredLaneError RegisteredLaneEvidence)
loadRegisteredLaneEvidenceIn root lane = do
  selected <- Registration.loadLaneRegistrationIn root lane
  case selected of
    Left err -> pure (Left (RegisteredLaneSelectionRejected err))
    Right registration ->
      case Matrix.projectProductRows lane Matrix.allProductRows of
        Failure errors -> pure (Left (RegisteredLaneProjectionRejected errors))
        Success batch -> do
          let generation = Registration.loadedLaneGeneration registration
              journalFile = laneGenerationJournal generation
              relative = Text.unpack (selectedLaneFilePath journalFile)
              path = root </> relative
          case checkRegisteredLaneGeneration generation batch of
            Left err -> pure (Left err)
            Right () -> do
              captured <- Registration.readSelectedLaneFileIn root maximumRegisteredJournalBytes journalFile
              case captured of
                Left err -> pure (Left (RegisteredLaneSelectionRejected err))
                Right bytes -> do
                  qualifications <- readProductLaneQualificationObjects path bytes
                  case qualifications of
                    Left err -> pure (Left (RegisteredLaneJournalRejected (err :| [])))
                    Right objects -> do
                      actual <-
                        Lane.admitProductLaneJournalWithNativeBundles
                          path
                          objects
                          (selectedLaneFileSha256 journalFile)
                          batch
                          bytes
                      pure $ do
                        admitted <- mapLeft RegisteredLaneJournalRejected actual
                        -- These getters are derived only from the admitted
                        -- original authenticated SL/native chains, including
                        -- their prelaunch review selection. JournalSHA is not
                        -- substituted for the original code SourceStamp.
                        checkRegisteredLaneReviewBindings
                          generation
                          (Lane.admittedProductLaneJournalReviewBindings admitted)
                        pure (RegisteredLaneEvidence registration batch admitted)

-- | Ordinary current projection DATA, useful to independent reviewers and
-- mutation controls. No selected expected pin or admitted capability is made.
currentLaneRowContracts :: Matrix.ProductProjectionBatch -> [LaneRowContractData]
currentLaneRowContracts batch = fmap one (Matrix.productProjectionBatchProjections batch)
 where
  one (Matrix.SomeProductProjection _ projection) =
    LaneRowContractData
      (Matrix.productProjectionRowId projection)
      (planIdText (Matrix.productProjectionPlanId projection))
      (Report.productScenarioProjectionContractDigest projection)

checkRegisteredLaneGeneration
  :: LaneGenerationData
  -> Matrix.ProductProjectionBatch
  -> Either RegisteredLaneError ()
checkRegisteredLaneGeneration generation batch = do
  _ <-
    mapLeft
      (RegisteredLaneBindingRejected . Text.pack . show)
      (refineLaneGenerationData generation)
  unless (laneGenerationSubstrate generation == Matrix.productProjectionBatchSubstrate batch) $
    Left (RegisteredLaneBindingRejected "selected generation lane differs from the current projection")
  let expected = laneGenerationRows generation
      actual = currentLaneRowContracts batch
  unless (expected == actual) $ do
    expectedSha <- contractDigest expected
    actualSha <- contractDigest actual
    Left (RegisteredLaneContractsStale actualSha expectedSha)
 where
  contractDigest = mapLeft (RegisteredLaneBindingRejected . Text.pack . show) . laneRowContractsSha256

-- | Compare-only ordinary DATA seam. Production calls it only AFTER actual
-- full lane admission; supplying forged tuples here cannot construct either
-- the admitted lane or RegisteredLaneEvidence.
checkRegisteredLaneReviewBindings
  :: LaneGenerationData
  -> [(Text, Maybe SourceStamp, Maybe (Text, Text, Text), Maybe (Text, Text, Text))]
  -> Either RegisteredLaneError ()
checkRegisteredLaneReviewBindings generation bindings = do
  _ <-
    mapLeft
      (RegisteredLaneBindingRejected . Text.pack . show)
      (refineLaneGenerationData generation)
  let expectedRows = fmap Matrix.rowId Matrix.allProductRows
  unless (fmap firstOf4 bindings == expectedRows) $
    Left
      ( RegisteredLaneBindingRejected
          "authenticated review bindings do not cover all55 ordered current rows"
      )
  mapM_ check (zip Matrix.allProductRows bindings)
 where
  expectedSource = laneGenerationSource generation
  expectedSL = identity (laneGenerationSupervisedReview generation)
  expectedNative = identity (laneGenerationNativeReview generation)
  identity review =
    ( selectedLaneFileSha256 (laneReviewSelection review)
    , selectedLaneFileSha256 (laneReviewReceipt review)
    , laneReviewContractSetSha256 review
    )
  firstOf4 (row, _, _, _) = row
  check (row, (name, source, supervised, native)) = do
    -- Tuning has no original code SourceStamp in its retained wire. Do not
    -- relabel journalSHA or borrow a sibling source; its full current contract,
    -- original HMAC and ordinary admission remain mandatory in the lane reader.
    let expected = case Matrix.family row of
          Matrix.Supervised -> (Just expectedSource, Just expectedSL, Nothing)
          Matrix.ReinforcementLearning -> (Just expectedSource, Nothing, Just expectedNative)
          Matrix.AlphaZero -> (Just expectedSource, Nothing, Just expectedNative)
          Matrix.Tuning -> (Nothing, Nothing, Nothing)
    unless ((source, supervised, native) == expected) $
      Left
        ( RegisteredLaneBindingRejected
            (name <> ": original authenticated review selection/receipt/contract-set identity differs")
        )
