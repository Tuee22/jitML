{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Concrete native child publishing. No trainer, evaluator, writer, reader,
-- device or result callback is accepted. The compact result is still a CHILD
-- publication, not authenticated parent/journal qualification.
module JitML.Product.Publisher.Native
  ( trainAndPublishNativeProductRow
  ) where

import Control.Exception (evaluate)
import Control.Exception.Safe (tryAny)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ask, runReaderT)
import Data.Text qualified as Text

import JitML.Checkpoint.NativePhase.Failure qualified as Failure
import JitML.Env.Env (App)
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.NativePublishedArtifact qualified as Published
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.Product.NativeRlExecution qualified as Native
import JitML.Product.NativeRlProducer qualified as Producer
import JitML.Product.Publisher.Audit
  ( ProductArtifactReceipt (..)
  , ProductPublishDisposition (..)
  , ProductPublishResult (..)
  , nativePublishedArtifactReceipt
  , renderProductPublishResult
  , validateNativePublishedProjection
  )
import JitML.Product.Publisher.Common (productPublishError)
import JitML.Product.Publisher.Projection (validateProjectionRowAssociation)
import JitML.Product.SourceDigest qualified as Source
import JitML.Training.Budget qualified as Training

trainAndPublishNativeProductRow
  :: Maybe Training.ProductScenarioInvocation
  -> Maybe Source.SourceStamp
  -> Matrix.ProductRow 'Matrix.Declared
  -> Matrix.ProductProjection kind
  -> App ProductPublishResult
trainAndPublishNativeProductRow invocation source row projection = do
  env <- ask
  attempted <- liftIO $ tryAny $ do
    result <- runReaderT program env
    _ <- evaluate (Text.length (renderProductPublishResult result))
    mapM_
      ( \receipt ->
          evaluate
            ( Text.length (productArtifactExperimentHash receipt)
                + Text.length (productArtifactKind receipt)
                + Text.length (productArtifactSha receipt)
                + Text.length (productArtifactObjectKey receipt)
            )
      )
      (productPublishArtifacts result)
    pure result
  case attempted of
    Right result -> pure result
    Left exception -> do
      diagnostic <- liftIO (Failure.captureNativeExceptionDiagnostic exception)
      let reason = case diagnostic of
            Failure.CompleteNativeDiagnostic actual -> actual
            other -> Text.pack (show other)
      pure (productPublishError projection ("native canonical child publication exception: " <> reason))
 where
  program = do
    -- Demand input DATA inside the async-safe boundary, before acquiring any
    -- trainer/session. The resolver owns the complete canonical43-row batch.
    _ <- liftIO (evaluate row)
    _ <- liftIO (evaluate projection)
    case preflight of
      Left reason -> pure (productPublishError projection reason)
      Right batch -> do
        let context = case invocation of
              Nothing -> Producer.DirectNativeProducer "."
              Just original -> Producer.ScenarioNativeProducer original $ case source of
                Nothing -> Producer.ObserveNativeProducerSource "."
                Just stamp -> Producer.SuppliedNativeProducerSource stamp
        result <- Native.executeNativeRlPublication batch (Matrix.productProjectionRowId projection) context
        case Native.nativeRlExecutionPublication result of
          Nothing ->
            pure
              ( productPublishError
                  projection
                  ( "native canonical child pipeline refused at "
                      <> Text.pack (show (Native.nativeExecutionStage (Native.nativeRlExecutionReport result)))
                  )
              )
          Just publication -> case Published.nativeChildPublishedArtifact publication of
            Left reason -> pure (productPublishError projection reason)
            Right actual -> case validateNativePublishedProjection projection actual of
              Left reason -> pure (productPublishError projection reason)
              Right () ->
                pure
                  ProductPublishResult
                    { productPublishRowId = Matrix.productProjectionRowId projection
                    , productPublishExperimentHash = Matrix.productProjectionExperimentHash projection
                    , productPublishDisposition = ProductPublishNativeEligible actual
                    , productPublishArtifacts = [nativePublishedArtifactReceipt projection actual]
                    , productPublishSupervisedQualification = Nothing
                    , productPublishMessage =
                        "actual native five-child publication, exact admitted serving0 and eleven retained replays; parent authentication remains separate"
                    }
  preflight = do
    if Matrix.productProjectionFamily projection `elem` [Matrix.ReinforcementLearning, Matrix.AlphaZero]
      then Right ()
      else Left "concrete native publisher accepts only RL/HER/AlphaZero ProductRows"
    validateProjectionRowAssociation row projection
    Cohort.mkCanonicalNativeRlCohorts (Matrix.productProjectionSubstrate projection)
{-# NOINLINE trainAndPublishNativeProductRow #-}
