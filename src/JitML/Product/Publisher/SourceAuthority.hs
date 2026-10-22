{-# LANGUAGE OverloadedStrings #-}

-- | Observe the actual producer identities before a compact cohort starts.
-- In a ProductScenario, the parent supplies its captured repository stamp and
-- independently compares/freezes it around the pinned child execution. This
-- function alone does not authenticate that parent handoff; Report does so.
module JitML.Product.Publisher.SourceAuthority
  ( captureSupervisedQualificationProducer
  , captureReviewedSupervisedQualificationProducer
  , supervisedCriterionReviewEnvironment
  , supervisedQualificationSourceEnvironment
  )
where

import Control.Exception (IOException, try)
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Either.Combinators (mapLeft)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Time.Clock (getCurrentTime)
import System.Environment (getExecutablePath)

import JitML.Checkpoint.WeightCodec qualified as WeightCodec
import JitML.Product.CriterionReview qualified as Review
import JitML.Product.CriterionReviewData qualified as ReviewData
import JitML.Product.SourceDigest qualified as SourceDigest
import JitML.Product.SupervisedQualification qualified as Qualification
import JitML.Substrate (Substrate)
import JitML.Training.Budget qualified as Budget

supervisedQualificationSourceEnvironment :: String
supervisedQualificationSourceEnvironment = "JITML_SUPERVISED_QUALIFICATION_SOURCE_SHA256"

captureSupervisedQualificationProducer
  :: Maybe Text
  -> Maybe Budget.ProductScenarioInvocation
  -> IO (Either Text Qualification.RawQualificationProducer)
captureSupervisedQualificationProducer sourceOverride invocation = do
  outcome <- tryIO observe
  pure $ case outcome of
    Left err -> Left ("supervised producer identity observation failed: " <> Text.pack (show err))
    Right observed -> observed
 where
  observe = do
    executable <- getExecutablePath
    bytes <- ByteString.readFile executable
    let executableSha = WeightCodec.jmw1ContentSha (LazyByteString.fromStrict bytes)
    source <- case (sourceOverride, invocation) of
      (Just supplied, Just _) -> pure (validateSha supplied)
      (Just _, Nothing) -> pure (Left "supervised source handoff requires a ProductScenario invocation")
      (Nothing, Just _) -> pure (Left "supervised ProductScenario is missing its parent source handoff")
      (Nothing, Nothing) -> fmap SourceDigest.stampSha256 <$> SourceDigest.computeSourceStamp
    now <- getCurrentTime
    pure $ do
      sourceSha <- source
      invocationSha <- case invocation of
        Just bound
          | Budget.productScenarioInvocationExecutableSha256 bound == executableSha ->
              Right (Budget.productScenarioInvocationDigest bound)
          | otherwise -> Left "supervised producer executable differs from its parent invocation"
        Nothing ->
          -- A fresh local attempt identity, explicitly not an authenticated
          -- scenario challenge or evidence that optimization has occurred.
          Right
            ( WeightCodec.jmw1ContentSha
                ( LazyByteString.fromStrict
                    ( Text.Encoding.encodeUtf8
                        ( Text.intercalate
                            "\NUL"
                            ["direct-supervised-attempt-v1", sourceSha, executableSha, Text.pack (show now)]
                        )
                    )
                )
            )
      Right
        Qualification.RawQualificationProducer
          { Qualification.rawQualificationSourceSha256 = sourceSha
          , Qualification.rawQualificationExecutableSha256 = executableSha
          , Qualification.rawQualificationInvocationSha256 = invocationSha
          }
  validateSha value
    | Text.length value == 64 && Text.all (`elem` ("0123456789abcdef" :: String)) value = Right value
    | otherwise = Left "supervised source handoff is not a canonical SHA-256"

tryIO :: IO value -> IO (Either IOException value)
tryIO = try

-- The scenario identity is supplied by the actual parent, not independently
-- FILE-observed by this child. Report must compare its original prelaunch FILE
-- observation with this retained producer and authenticate the whole receipt.
supervisedCriterionReviewEnvironment :: String
supervisedCriterionReviewEnvironment = "JITML_SUPERVISED_CRITERION_REVIEW_IDENTITY"
captureReviewedSupervisedQualificationProducer
  :: Substrate
  -> Text
  -> Maybe Text
  -> Maybe String
  -> Maybe Budget.ProductScenarioInvocation
  -> IO (Either Text Qualification.RawQualificationProducer)
captureReviewedSupervisedQualificationProducer lane expectedContracts sourceOverride supplied invocation = do
  original <- captureSupervisedQualificationProducer sourceOverride invocation
  case original of
    Left reason -> pure (Left reason)
    Right producer -> do
      identityResult <- case (invocation, supplied) of
        (Just _, Just encoded) -> pure (ReviewData.parseCriterionReviewIdentityData encoded)
        (Just _, Nothing) -> pure (Left "supervised scenario lacks original parent review handoff")
        (Nothing, Just _) -> pure (Left "direct supervised producer carries scenario review handoff")
        (Nothing, Nothing) ->
          fmap
            ( fmap Review.capturedCriterionReviewIdentity
                . mapLeft Review.renderCriterionReviewError
            )
            ( Review.captureCriterionReviewIn
                "."
                ( SourceDigest.SourceStamp
                    SourceDigest.sourceDigestAlgorithm
                    (Qualification.rawQualificationSourceSha256 producer)
                )
                lane
                ReviewData.SupervisedCriterionReview
            )
      pure $ do
        identity <- identityResult
        if ReviewData.criterionReviewSource identity
          == SourceDigest.SourceStamp
            SourceDigest.sourceDigestAlgorithm
            (Qualification.rawQualificationSourceSha256 producer)
          && ReviewData.criterionReviewSubstrate identity == lane
          && ReviewData.criterionReviewScope identity == ReviewData.SupervisedCriterionReview
          && ReviewData.criterionReviewContractSetSha256 identity == expectedContracts
          then Right ()
          else Left "supervised producer review handoff differs from actual source/lane/scope"
        bytes <- ReviewData.encodeCriterionReviewIdentityData identity
        let build = case invocation of
              Nothing -> Qualification.RawObservedReviewedQualificationProducer
              Just _ -> Qualification.RawSuppliedReviewedQualificationProducer
        pure
          ( build
              (Qualification.rawQualificationSourceSha256 producer)
              (Qualification.rawQualificationExecutableSha256 producer)
              (Qualification.rawQualificationInvocationSha256 producer)
              bytes
          )
