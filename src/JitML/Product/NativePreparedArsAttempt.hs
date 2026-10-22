{-# LANGUAGE OverloadedStrings #-}

-- | Actual local host-linear execution and fixed-case observations. No legacy
-- ARS wire/reference, parent authentication, loaded-code/build coherence,
-- hardware witness, durability, completion, quality or qualification is minted.
module JitML.Product.NativePreparedArsAttempt
  ( NativeArsRowData
  , NativeArsChildData
  , selectNativeArsRowData
  , selectNativeArsChildData
  , nativeArsRowId
  , nativeArsRowBatch
  , nativeArsRowCohort
  , nativeArsRowReference
  , nativeArsChildRow
  , nativeArsChildSeedPlan
  , nativeArsChildCompiledPlan
  , NativeArsSourceInput (..)
  , NativeArsContextInput (..)
  , NativeArsSourceCoverage (..)
  , NativeArsContextData
  , nativeArsContextAssociation
  , nativeArsContextSourceInput
  , NativeArsBegun
  , NativeArsPrepared
  , NativeArsReadyToTrain
  , NativeArsPendingFinal
  , NativeArsReturnedData
  , NativeArsFinalObservation
  , NativeArsExecutionOrigin
  , NativeArsBeginResult (..)
  , NativeArsPreparationResult (..)
  , NativeArsInitialResult (..)
  , NativeArsTrainingResult (..)
  , NativeArsFinalResult (..)
  , NativeArsStage (..)
  , NativeArsFailureKind (..)
  , NativeArsFailure
  , beginNativeArsAttempt
  , prepareNativeArsAttempt
  , evaluateNativeArsInitial
  , continueNativeArsTraining
  , finishNativeArsAttempt
  , nativeArsBegunChild
  , nativeArsBegunContext
  , nativeArsBegunAttemptId
  , nativeArsBegunContextDigest
  , nativeArsBegunBeforeProcess
  , nativeArsBegunSourceCoverage
  , nativeArsPreparedSnapshot
  , nativeArsReadySnapshot
  , nativeArsReadyInitialEvaluation
  , nativeArsPendingReturned
  , nativeArsReturnedChild
  , nativeArsReturnedSnapshot
  , nativeArsReturnedPolicy
  , nativeArsReturnedInitialEvaluation
  , nativeArsFinalReturned
  , nativeArsFinalEvaluation
  , nativeArsFinalEvaluationFailure
  , nativeArsFinalOrigin
  , nativeArsOriginChild
  , nativeArsOriginContext
  , nativeArsOriginAttemptId
  , nativeArsOriginContextDigest
  , nativeArsOriginSourceCoverage
  , nativeArsOriginBeforeProcess
  , nativeArsOriginAfterProcess
  , nativeArsOriginSnapshot
  , nativeArsOriginPolicy
  , nativeArsOriginNumericalRuntime
  , nativeArsFailureStage
  , nativeArsFailureKind
  , nativeArsFailureDetail
  , nativeArsFailureChild
  , nativeArsFailureSnapshot
  , nativeArsFailureInitialEvaluation
  , nativeArsFailureEvaluation
  , validateNativeArsReturnedBinding
  , validateNativeArsEvaluationData
  , observeNativeArsFailureBoundary
  ) where

import Control.Exception (SomeException, evaluate)
import Control.Exception.Safe (displayException, tryAny)
import Control.Monad (unless, void)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified as BS
import Data.Char (intToDigit)
import Data.Either (fromRight)
import Data.Either.Combinators (mapLeft)
import Data.List (find)
import Data.Maybe (isNothing)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Encoding
import Data.Vector.Unboxed qualified as VU
import GHC.Float (castDoubleToWord64)
import System.IO (IOMode (ReadMode), withBinaryFile)

import JitML.Execution.ProducerObservation qualified as Producer
import JitML.Execution.SingleUse qualified as SingleUse
import JitML.Plan.NativeChildAssociation qualified as Association
import JitML.Plan.NativeSingletonPlan qualified as Native
import JitML.Plan.Plan qualified as Plan
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.Product.SourceDigest qualified as Source
import JitML.RL.Algorithms.ArsTrainer qualified as Ars
import JitML.RL.Algorithms.Common qualified as Common
import JitML.RL.ArsHostTrace qualified as Trace
import JitML.RL.NativeReturnEvaluation qualified as Return
import JitML.RL.NativeReturnReferences qualified as Ref
import JitML.RL.ProductBudget qualified as Budget
import JitML.Substrate (renderSubstrate)
import JitML.Training.Budget qualified as TrainingBudget

-- Checked membership DATA; neither type is an execution capability.
data NativeArsRowData
  = NativeArsRowData Cohort.NativeRlCohortBatch Cohort.NativeRlCohortPlan Ref.NativeReturnReferenceSpec
  deriving stock (Eq, Show)
data NativeArsChildData
  = NativeArsChildData NativeArsRowData Cohort.NativeRlSeedPlan Budget.CompiledRlPlan
  deriving stock (Eq, Show)

data NativeArsSourceInput
  = ObserveNativeArsSourceRoot !FilePath
  | SuppliedNativeArsParentSource !Source.SourceStamp
  deriving stock (Eq, Show)
data NativeArsContextInput
  = DirectNativeArsLocal !FilePath
  | SuppliedNativeArsParent !TrainingBudget.ProductScenarioInvocation !NativeArsSourceInput
  deriving stock (Eq, Show)
data NativeArsSourceCoverage
  = NativeArsObservedLocal !FilePath !Source.SourceStamp
  | NativeArsUnauthenticatedParentSource !Source.SourceStamp
  deriving stock (Eq, Show)

-- The association is supplied checked DATA, not App receipt or authentication.
data NativeArsContextData
  = NativeArsContextData NativeArsSourceInput (Maybe Association.NativeChildAssociation)
  deriving stock (Eq, Show)
data Meta
  = Meta
      NativeArsChildData
      NativeArsContextData
      NativeArsSourceCoverage
      Text
      Text
      Producer.ObservedProducerProcess

-- No action-bearing constructor, record label, restore, codec or callback input.
data NativeArsBegun = NativeArsBegun Meta SingleUse.SingleUse
data NativeArsPrepared
  = NativeArsPrepared Meta Ars.PreparedArsTraining Ars.ArsPreparedSnapshot SingleUse.SingleUse
data NativeArsReadyToTrain
  = NativeArsReadyToTrain
      Meta
      Ars.PreparedArsTraining
      Ars.ArsPreparedSnapshot
      Return.RawNativeReturnEvaluation
      SingleUse.SingleUse
data NativeArsReturnedData
  = NativeArsReturnedData
      Meta
      Ars.ArsPreparedSnapshot
      Return.RawNativeReturnEvaluation
      Ars.ArsTrainObservation
data NativeArsPendingFinal = NativeArsPendingFinal NativeArsReturnedData SingleUse.SingleUse
data NativeArsFinalObservation
  = NativeArsFinalObservation
      NativeArsReturnedData
      (Maybe Return.RawNativeReturnEvaluation)
      (Maybe NativeArsFailure)
      (Either NativeArsFailure NativeArsExecutionOrigin)

-- Distinct in-memory origin only. No old15-field context/reference is made.
data NativeArsExecutionOrigin
  = NativeArsExecutionOrigin
      Meta
      Ars.ArsPreparedSnapshot
      Ars.ArsTrainObservation
      Ars.ArsNumericalRuntime
      Producer.ObservedProducerProcess

data NativeArsBeginResult = NativeArsBeginFailed NativeArsFailure | NativeArsBegunReady NativeArsBegun
data NativeArsPreparationResult
  = NativeArsPreparationFailed NativeArsFailure
  | NativeArsPreparationReady NativeArsPrepared
data NativeArsInitialResult
  = NativeArsInitialFailed NativeArsFailure
  | NativeArsInitialReady NativeArsReadyToTrain
data NativeArsTrainingResult
  = NativeArsTrainingFailed NativeArsFailure
  | NativeArsReturnedButUnmaterializable NativeArsFailure
  | NativeArsReturnedBindingFailed NativeArsReturnedData NativeArsFailure
  | NativeArsTrainingReturned NativeArsPendingFinal
data NativeArsFinalResult
  = NativeArsFinishRejected NativeArsReturnedData NativeArsFailure
  | NativeArsFinished NativeArsFinalObservation

data NativeArsStage
  = NativeArsSelection
  | NativeArsBeginning
  | NativeArsPreparation
  | NativeArsInitialEvaluation
  | NativeArsTraining
  | NativeArsReturnMaterialization
  | NativeArsReturnBinding
  | NativeArsFinalEvaluation
  | NativeArsLineage
  | NativeArsAfterProcess
  deriving stock (Eq, Show)
data NativeArsFailureKind
  = NativeArsRejected
  | NativeArsSynchronousFailure
  | NativeArsAlreadyConsumed
  | NativeArsUnmaterializable
  deriving stock (Eq, Show)
data Known
  = Known
      (Maybe NativeArsChildData)
      (Maybe Ars.ArsPreparedSnapshot)
      (Maybe Return.RawNativeReturnEvaluation)
      (Maybe Return.RawNativeReturnEvaluation)
data NativeArsFailure = NativeArsFailure NativeArsStage NativeArsFailureKind Text Known

selectNativeArsRowData
  :: Cohort.NativeRlCohortBatch -> Text -> Either NativeArsFailure NativeArsRowData
selectNativeArsRowData batch row = mapSelection $ do
  cohort <-
    maybe
      (Left "native ARS row is absent from the checked whole Batch")
      Right
      ( find
          ((== row) . Matrix.rowId . Cohort.nativeRlCohortPlanRow)
          (Cohort.nativeRlCohortBatchPlans batch)
      )
  compiled <-
    maybe
      (Left "native ARS row is not a compiled return workload")
      Right
      (Cohort.nativeRlSeedPlanCompiledReturn (Cohort.nativeRlCohortServingChild cohort))
  require (Budget.compiledRlTrainerKind compiled == "ars") "native ARS row is not ARS"
  require
    ( row == "ARS/" <> Budget.compiledRlEnvironment compiled
        && row `elem` ["ARS/cartpole", "ARS/mountain-car", "ARS/lunar-lander", "ARS/key-door-grid"]
    )
    "native ARS row differs from its supported environment"
  spec <- Ref.canonicalNativeReturnSpec "ARS" (Budget.compiledRlEnvironment compiled)
  pure (NativeArsRowData batch cohort spec)

selectNativeArsChildData
  :: NativeArsRowData -> Cohort.NativeSeedIndex -> Either NativeArsFailure NativeArsChildData
selectNativeArsChildData row index = mapSelection $ do
  child <-
    maybe
      (Left "native ARS child is absent from the stored canonical row")
      Right
      ( find
          ((== index) . Cohort.nativeRlSeedPlanIndex)
          (Cohort.nativeRlCohortPlanChildren (nativeArsRowCohort row))
      )
  compiled <-
    maybe
      (Left "native ARS child is not a compiled return workload")
      Right
      (Cohort.nativeRlSeedPlanCompiledReturn child)
  require (Budget.compiledRlTrainerKind compiled == "ars") "native ARS child trainer differs"
  pure (NativeArsChildData row child compiled)

nativeArsRowId :: NativeArsRowData -> Text
nativeArsRowId = Matrix.rowId . Cohort.nativeRlCohortPlanRow . nativeArsRowCohort
nativeArsRowBatch :: NativeArsRowData -> Cohort.NativeRlCohortBatch
nativeArsRowBatch (NativeArsRowData batch _ _) = batch
nativeArsRowCohort :: NativeArsRowData -> Cohort.NativeRlCohortPlan
nativeArsRowCohort (NativeArsRowData _ cohort _) = cohort
nativeArsRowReference :: NativeArsRowData -> Ref.NativeReturnReferenceSpec
nativeArsRowReference (NativeArsRowData _ _ spec) = spec
nativeArsChildRow :: NativeArsChildData -> NativeArsRowData
nativeArsChildRow (NativeArsChildData row _ _) = row
nativeArsChildSeedPlan :: NativeArsChildData -> Cohort.NativeRlSeedPlan
nativeArsChildSeedPlan (NativeArsChildData _ child _) = child
nativeArsChildCompiledPlan :: NativeArsChildData -> Budget.CompiledRlPlan
nativeArsChildCompiledPlan (NativeArsChildData _ _ compiled) = compiled
nativeArsContextAssociation :: NativeArsContextData -> Maybe Association.NativeChildAssociation
nativeArsContextAssociation (NativeArsContextData _ association) = association
nativeArsContextSourceInput :: NativeArsContextData -> NativeArsSourceInput
nativeArsContextSourceInput (NativeArsContextData source _) = source

beginNativeArsAttempt :: NativeArsChildData -> NativeArsContextInput -> IO NativeArsBeginResult
beginNativeArsAttempt child supplied = do
  -- No supplied value is retained after a failed materialization.
  attempted <- at NativeArsBeginning emptyKnown $ do
    forceChild child
    context <- forceEither (makeContext child supplied)
    case context of
      Left detail -> pure (Left detail)
      Right actualContext -> do
        forceContext actualContext
        before <- observeProcess (nativeArsContextSourceInput actualContext)
        case before of
          Left detail -> pure (Left detail)
          Right process -> do
            coverage <- forceEither (sourceCoverage (nativeArsContextSourceInput actualContext) process)
            case coverage of
              Left detail -> pure (Left detail)
              Right actualCoverage -> do
                checked <- forceEither (checkSuppliedExecutable actualContext process)
                case checked of
                  Left detail -> pure (Left detail)
                  Right () -> do
                    nonce <- actualNonce
                    case nonce of
                      Left detail -> pure (Left detail)
                      Right actualNonceValue -> do
                        let bindingDigest = contextDigest child actualContext actualCoverage actualNonceValue process
                        forceText bindingDigest
                        Right
                          . NativeArsBegun (Meta child actualContext actualCoverage actualNonceValue bindingDigest process)
                          <$> SingleUse.newSingleUse
  pure (either NativeArsBeginFailed NativeArsBegunReady attempted)

prepareNativeArsAttempt :: NativeArsBegun -> IO NativeArsPreparationResult
prepareNativeArsAttempt (NativeArsBegun meta token) = do
  claimed <- SingleUse.tryConsumeSingleUse token
  if not claimed
    then pure (NativeArsPreparationFailed (consumed NativeArsPreparation (metaKnown meta)))
    else do
      attempted <- at NativeArsPreparation (metaKnown meta) $ do
        resolved <- forceEither (Trace.resolveArsHostPlanData (nativeArsChildCompiledPlan (metaChild meta)))
        case resolved of
          Left detail -> pure (Left detail)
          Right (environment, config) -> do
            lower <- Ars.prepareArsOnEnvironment environment config
            let snapshot = Ars.preparedArsSnapshot lower
            forceSnapshot snapshot
            checked <-
              forceEither
                ( Trace.validateArsHostConfigForPlan
                    (nativeArsChildCompiledPlan (metaChild meta))
                    (Ars.arsPreparedConfig snapshot)
                )
            case checked of
              Left detail -> pure (Left detail)
              Right () -> Right . NativeArsPrepared meta lower snapshot <$> SingleUse.newSingleUse
      pure (either NativeArsPreparationFailed NativeArsPreparationReady attempted)

evaluateNativeArsInitial :: NativeArsPrepared -> IO NativeArsInitialResult
evaluateNativeArsInitial (NativeArsPrepared meta lower snapshot token) = do
  let known = snapshotKnown meta snapshot
  claimed <- SingleUse.tryConsumeSingleUse token
  if not claimed
    then pure (NativeArsInitialFailed (consumed NativeArsInitialEvaluation known))
    else do
      evaluated <-
        evaluatePolicy
          NativeArsInitialEvaluation
          known
          (metaChild meta)
          (Ars.arsPreparedConfig snapshot)
          (Ars.arsPreparedInitialParams snapshot)
      case evaluated of
        (Nothing, Just failure) -> pure (NativeArsInitialFailed failure)
        (Just _, Just failure) -> pure (NativeArsInitialFailed failure)
        (Just raw, Nothing) -> do
          attempted <-
            at NativeArsInitialEvaluation (withInitial raw known) $
              Right . NativeArsReadyToTrain meta lower snapshot raw <$> SingleUse.newSingleUse
          pure (either NativeArsInitialFailed NativeArsInitialReady attempted)
        (Nothing, Nothing) ->
          pure
            ( NativeArsInitialFailed
                (rejected NativeArsInitialEvaluation known "native ARS initial observation is unavailable")
            )

continueNativeArsTraining :: NativeArsReadyToTrain -> IO NativeArsTrainingResult
continueNativeArsTraining (NativeArsReadyToTrain meta lower snapshot initial token) = do
  let known = withInitial initial (snapshotKnown meta snapshot)
  claimed <- SingleUse.tryConsumeSingleUse token
  if not claimed
    then pure (NativeArsTrainingFailed (consumed NativeArsTraining known))
    else do
      outer <- at NativeArsTraining known (Ars.continuePreparedArsRaw lower)
      case outer of
        Left failure -> pure (NativeArsTrainingFailed failure)
        Right raw -> do
          -- Materialize every actual raw field, without finite/counter/quality
          -- refinement, before publishing a data handle or running final scoring.
          materialized <- at NativeArsReturnMaterialization known $ forceShown raw >> pure (Right ())
          case materialized of
            Left failure -> pure (NativeArsReturnedButUnmaterializable (asUnmaterializable failure))
            Right () -> do
              let actual = NativeArsReturnedData meta snapshot initial raw
              bound <- at NativeArsReturnBinding known $ do
                checked <- forceEither (validateNativeArsReturnedBinding snapshot raw)
                case checked of
                  Left detail -> pure (Left detail)
                  Right () -> Right . NativeArsPendingFinal actual <$> SingleUse.newSingleUse
              pure (either (NativeArsReturnedBindingFailed actual) NativeArsTrainingReturned bound)

finishNativeArsAttempt :: NativeArsPendingFinal -> IO NativeArsFinalResult
finishNativeArsAttempt (NativeArsPendingFinal actual@(NativeArsReturnedData meta snapshot initial raw) token) = do
  let known = withInitial initial (snapshotKnown meta snapshot)
  claimed <- SingleUse.tryConsumeSingleUse token
  if not claimed
    then pure (NativeArsFinishRejected actual (consumed NativeArsFinalEvaluation known))
    else do
      (evaluated, failure) <-
        evaluatePolicy
          NativeArsFinalEvaluation
          known
          (metaChild meta)
          (Common.rawTrainerConfig raw)
          (Common.rawTrainerFinalParams raw)
      let finalKnown = withEvaluation evaluated known
      -- A real origin is independent of final metric eligibility and no legacy
      -- positive-counter/evidence/refinement gate precedes these observations.
      origin <- at NativeArsLineage finalKnown $ do
        checked <- forceEither $ do
          Trace.validateArsHostConfigForPlan
            (nativeArsChildCompiledPlan (metaChild meta))
            (Common.rawTrainerConfig raw)
          validateNativeArsReturnedBinding snapshot raw
          _ <- Trace.arsHostTraceCoordinateCount (Common.rawTrainerConfig raw)
          Ars.validateArsTrainObservation raw
        pure (void checked)
      actualOrigin <- case origin of
        Left problem -> pure (Left problem)
        Right () -> at NativeArsAfterProcess finalKnown $ do
          observed <- observeProcess (nativeArsContextSourceInput (metaContext meta))
          case observed of
            Left detail -> pure (Left detail)
            Right after -> do
              checked <- forceEither $ case Producer.compareProducerProcessObservations (metaBefore meta) after of
                Left mismatch -> Left (Text.pack (show mismatch))
                Right () -> Right ()
              case checked of
                Left detail -> pure (Left detail)
                Right () -> pure (Right (NativeArsExecutionOrigin meta snapshot raw Ars.arsNativeNumericalRuntime after))
      pure (NativeArsFinished (NativeArsFinalObservation actual evaluated failure actualOrigin))

-- Data-only predicates; neither can create a stage or a local origin.
validateNativeArsReturnedBinding
  :: Ars.ArsPreparedSnapshot -> Ars.ArsTrainObservation -> Either Text ()
validateNativeArsReturnedBinding snapshot raw = do
  require
    (configKey (Ars.arsPreparedConfig snapshot) == configKey (Common.rawTrainerConfig raw))
    "native ARS actual returned configuration differs from prepared configuration bits"
  require
    (sameVector (Ars.arsPreparedInitialParams snapshot) (Common.rawTrainerInitialParams raw))
    "native ARS actual returned initial parameters differ from the prepared snapshot bits"

validateNativeArsEvaluationData
  :: NativeArsChildData -> Return.RawNativeReturnEvaluation -> Either Text ()
validateNativeArsEvaluationData child raw = do
  let spec = nativeArsRowReference (nativeArsChildRow child)
      episodes = Return.nativeEvaluationEpisodes raw
      horizon = Ref.nativeReturnSpecHorizon spec
      count = Ref.nativeReturnSpecEpisodeCount spec
  require (Return.nativeEvaluationSpec raw == spec) "native ARS fixed specification differs"
  case Return.nativeEvaluationPolicy raw of
    Return.NativeArsHostEvaluation config theta -> do
      Trace.validateArsHostConfigForPlan (nativeArsChildCompiledPlan child) config
      require
        ( toInteger (VU.length theta)
            == toInteger (Ars.arsActionCount config) * toInteger (Ars.arsObsSize config)
            && VU.all finite theta
        )
        "native ARS observed policy dimensions or finite parameters differ"
    Return.NativeNeuralEvaluation {} -> Left "native ARS observation contains a neural policy"
  case Return.nativeEvaluationStatus raw of
    Return.NativeEvaluationComplete -> pure ()
    Return.NativeEvaluationRejected reason -> Left reason
    Return.NativeEvaluationFailed index _ reason -> Left ("native ARS case " <> Text.pack (show index) <> ": " <> reason)
  require
    (map Ref.nativeReturnEpisodeId episodes == [0 .. count - 1])
    "native ARS complete case inventory differs"
  require
    ( all
        ( \episode ->
            finite (Ref.nativeReturnEpisodeReward episode)
              && Ref.nativeReturnEpisodeSteps episode > 0
              && Ref.nativeReturnEpisodeSteps episode <= horizon
              && (Ref.nativeReturnEpisodeTerminated episode || Ref.nativeReturnEpisodeSteps episode == horizon)
        )
        episodes
    )
    "native ARS complete observation is nonfinite or incomplete"
  require
    ( Return.nativeEvaluationWork raw
        == Return.NativeCompleteWork (sum (map (toInteger . Ref.nativeReturnEpisodeSteps) episodes))
    )
    "native ARS complete work differs"
  require
    ( null (Return.nativeEvaluationForwards raw)
        && isNothing (Return.nativeEvaluationFailedReturnedEpisodes raw)
    )
    "native ARS host observation contains neural or failed-return payloads"

evaluatePolicy
  :: NativeArsStage
  -> Known
  -> NativeArsChildData
  -> Ars.ArsTrainConfig
  -> VU.Vector Double
  -> IO (Maybe Return.RawNativeReturnEvaluation, Maybe NativeArsFailure)
evaluatePolicy stage known child config theta = do
  attempted <- at stage known $ do
    let raw =
          Return.evaluateNativeArsReturnPolicy (nativeArsRowReference (nativeArsChildRow child)) config theta
    forceShown raw
    pure (Right raw)
  case attempted of
    Left failure -> pure (Nothing, Just failure)
    Right raw -> do
      let actualKnown = withEvaluation (Just raw) known
      checked <- at stage actualKnown $ forceEither $ do
        validateNativeArsEvaluationData child raw
        case Return.nativeEvaluationPolicy raw of
          Return.NativeArsHostEvaluation actualConfig actualTheta -> do
            require
              (configKey actualConfig == configKey config)
              "native ARS evaluator changed the actual supplied configuration"
            require (sameVector actualTheta theta) "native ARS evaluator changed the actual supplied parameters"
          Return.NativeNeuralEvaluation {} -> Left "native ARS evaluator returned a neural policy"
      pure (Just raw, either Just (const Nothing) checked)

makeContext :: NativeArsChildData -> NativeArsContextInput -> Either Text NativeArsContextData
makeContext child supplied = do
  let row = nativeArsChildRow child
      cohort = nativeArsRowCohort row
      parent = Cohort.nativeRlSeedPlanSingleton (Cohort.nativeRlCohortServingChild cohort)
      selected = nativeArsChildSeedPlan child
      actualChild = Cohort.nativeRlSeedPlanSingleton selected
      ordinal = Cohort.nativeSeedIndexValue (Cohort.nativeRlSeedPlanIndex selected)
  expected <- Native.deriveNativeChildPlan parent ordinal
  require
    (actualChild == expected)
    "native ARS actual child differs from its complete prescribed derivation"
  case supplied of
    DirectNativeArsLocal root -> pure (NativeArsContextData (ObserveNativeArsSourceRoot root) Nothing)
    SuppliedNativeArsParent invocation source -> do
      validateSourceRequest source
      association <-
        Association.mkNativeChildAssociation (nativeArsRowId row) parent invocation ordinal actualChild
      require
        ( Association.nativeAssociationParent association == parent
            && Association.nativeAssociationChild association == actualChild
            && Association.nativeAssociationOrdinal association == ordinal
            && Association.nativeAssociationRow association == nativeArsRowId row
            && Association.nativeAssociationInvocation association == invocation
        )
        "native ARS supplied complete association differs from selected child"
      pure (NativeArsContextData source (Just association))

validateSourceRequest :: NativeArsSourceInput -> Either Text ()
validateSourceRequest (ObserveNativeArsSourceRoot _) = Right ()
validateSourceRequest (SuppliedNativeArsParentSource stamp) = do
  require
    (Source.stampAlgorithm stamp == Source.sourceDigestAlgorithm)
    "native ARS supplied source algorithm differs"
  require
    ( Text.length (Source.stampSha256 stamp) == 64
        && Text.all (`elem` ("0123456789abcdef" :: String)) (Source.stampSha256 stamp)
    )
    "native ARS supplied source SHA is not canonical"

observeProcess :: NativeArsSourceInput -> IO (Either Text Producer.ObservedProducerProcess)
observeProcess source = do
  actual <- Producer.observeProducerProcess $ case source of
    ObserveNativeArsSourceRoot root -> Producer.ObserveSourceAt root
    SuppliedNativeArsParentSource _ -> Producer.NoSourceObservation
  case actual of
    Left reason -> do
      let detail = Text.pack (show reason)
      forceText detail
      pure (Left detail)
    Right observed -> pure (Right observed)

sourceCoverage
  :: NativeArsSourceInput -> Producer.ObservedProducerProcess -> Either Text NativeArsSourceCoverage
sourceCoverage (ObserveNativeArsSourceRoot root) actual = case Producer.producerObservedSource actual of
  Just (actualRoot, stamp) | actualRoot == root -> Right (NativeArsObservedLocal root stamp)
  _ -> Left "native ARS actual requested source observation is absent or differs"
sourceCoverage (SuppliedNativeArsParentSource stamp) actual = do
  require
    (case Producer.producerObservedSource actual of Nothing -> True; Just _ -> False)
    "native ARS handed source was relabelled as locally observed"
  pure (NativeArsUnauthenticatedParentSource stamp)

checkSuppliedExecutable
  :: NativeArsContextData -> Producer.ObservedProducerProcess -> Either Text ()
checkSuppliedExecutable context actual = case nativeArsContextAssociation context of
  Nothing -> Right ()
  Just association ->
    require
      ( TrainingBudget.productScenarioInvocationExecutableSha256
          (Association.nativeAssociationInvocation association)
          == Producer.producerExecutableFileSha256 actual
      )
      "native ARS supplied parent executable differs from actual process FILE observation"

-- The same fail-closed OS source as the existing singleton route; no clock,
-- PID, installed CLI or trainer RNG supplies nominal entropy.
actualNonce :: IO (Either Text Text)
actualNonce = withBinaryFile "/dev/urandom" ReadMode $ \handle -> do
  actual <- BS.hGet handle 32
  if BS.length actual /= 32
    then pure (Left "native ARS actual OS nonce read was short")
    else do
      let nonce = digest actual
      forceText nonce
      pure (Right nonce)

-- This address names supplied context plus an actual nonce/FILE observation.
-- It authenticates neither the supplied parent nor any source-build relationship.
contextDigest
  :: NativeArsChildData
  -> NativeArsContextData
  -> NativeArsSourceCoverage
  -> Text
  -> Producer.ObservedProducerProcess
  -> Text
contextDigest child context coverage nonce before = digest (BS.concat (map field values))
 where
  selected = nativeArsChildSeedPlan child
  singleton = Cohort.nativeRlSeedPlanSingleton selected
  cohort = nativeArsRowCohort (nativeArsChildRow child)
  values =
    [ "jitml-native-ars-observed-context-v1"
    , nonce
    , nativeArsRowId (nativeArsChildRow child)
    , Plan.planIdText (Cohort.nativeRlCohortPlanId cohort)
    , Native.renderNativeSingletonPlan singleton
    , Budget.renderCompiledRlPlanTransport (nativeArsChildCompiledPlan child)
    , renderSubstrate (Native.nativeSingletonSubstrate singleton)
    , Text.pack (show (Cohort.nativeSeedIndexValue (Cohort.nativeRlSeedPlanIndex selected)))
    , Ref.nativeReturnReferenceContract
    , Return.nativeReturnEvaluationContract
    , Producer.producerExecutableFileSha256 before
    ]
      <> coverageFields coverage
      <> case nativeArsContextAssociation context of
        Nothing ->
          [ "direct-native-local-observation"
          , Native.renderNativeSingletonPlan
              (Cohort.nativeRlSeedPlanSingleton (Cohort.nativeRlCohortServingChild cohort))
          ]
        Just association ->
          [ "supplied-native-parent-association-data"
          , Association.renderNativeChildAssociation association
          , Association.nativeAssociationDigest association
          ]
  field value =
    let bytes = Encoding.encodeUtf8 value
     in Encoding.encodeUtf8 (Text.pack (show (BS.length bytes))) <> ":" <> bytes

coverageFields :: NativeArsSourceCoverage -> [Text]
coverageFields coverage = case coverage of
  NativeArsObservedLocal root stamp ->
    [ "locally-observed-source"
    , Text.pack root
    , Text.pack (show (Source.stampAlgorithm stamp))
    , Source.stampSha256 stamp
    ]
  NativeArsUnauthenticatedParentSource stamp ->
    [ "unobserved-supplied-parent-source"
    , Text.pack (show (Source.stampAlgorithm stamp))
    , Source.stampSha256 stamp
    ]

digest :: BS.ByteString -> Text
digest =
  Text.pack
    . concatMap
      (\byte -> [intToDigit (fromIntegral byte `div` 16), intToDigit (fromIntegral byte `mod` 16)])
    . BS.unpack
    . SHA256.hash

-- Positional constructor pattern is intentionally exhaustive over all nine
-- current config fields; both Doubles use their exact binary64 words.
configKey :: Ars.ArsTrainConfig -> ([Int], [Integer])
configKey (Ars.ArsTrainConfig seed iterations directions topB stepSize noise horizon actions observations) =
  ( [seed, iterations, directions, topB, horizon, actions, observations]
  , map (toInteger . castDoubleToWord64) [stepSize, noise]
  )
sameVector :: VU.Vector Double -> VU.Vector Double -> Bool
sameVector left right =
  VU.length left == VU.length right
    && VU.toList (VU.map castDoubleToWord64 left) == VU.toList (VU.map castDoubleToWord64 right)
finite :: Double -> Bool
finite value = not (isNaN value || isInfinite value)
require :: Bool -> Text -> Either Text ()
require condition reason = unless condition (Left reason)

forceChild :: NativeArsChildData -> IO ()
forceChild child = do
  forceText (nativeArsRowId (nativeArsChildRow child))
  forceText (Budget.renderCompiledRlPlanTransport (nativeArsChildCompiledPlan child))
  forceText
    (Native.renderNativeSingletonPlan (Cohort.nativeRlSeedPlanSingleton (nativeArsChildSeedPlan child)))
  void
    ( evaluate
        (BS.length (Cohort.nativeRlCohortPlanTransport (nativeArsRowCohort (nativeArsChildRow child))))
    )
  forceShown (nativeArsRowReference (nativeArsChildRow child))
forceContext :: NativeArsContextData -> IO ()
forceContext context = do
  case nativeArsContextSourceInput context of
    ObserveNativeArsSourceRoot root -> forceShown root
    SuppliedNativeArsParentSource stamp -> forceShown stamp
  case nativeArsContextAssociation context of
    Nothing -> pure ()
    Just association -> forceText (Association.renderNativeChildAssociation association)
forceSnapshot :: Ars.ArsPreparedSnapshot -> IO ()
forceSnapshot snapshot = do
  forceShown (configKey (Ars.arsPreparedConfig snapshot))
  forceVector (Ars.arsPreparedInitialParams snapshot)
  forceVector (Ars.arsPreparedInitialFrame snapshot)
  forceShown (Ars.arsPreparedGenerator snapshot)
forceVector :: VU.Vector Double -> IO ()
forceVector values = void (evaluate (VU.foldl' (\() value -> value `seq` ()) () values))
forceText :: Text -> IO ()
forceText value = void (evaluate (Text.length value))
forceShown :: (Show value) => value -> IO ()
forceShown value = void (evaluate (foldr seq () (show value)))
forceEither :: Either Text value -> IO (Either Text value)
forceEither actual = do
  outer <- evaluate actual
  case outer of
    Left reason -> forceText reason
    Right _ -> pure ()
  pure outer

emptyKnown :: Known
emptyKnown = Known Nothing Nothing Nothing Nothing
metaKnown :: Meta -> Known
metaKnown meta = Known (Just (metaChild meta)) Nothing Nothing Nothing
snapshotKnown :: Meta -> Ars.ArsPreparedSnapshot -> Known
snapshotKnown meta snapshot = Known (Just (metaChild meta)) (Just snapshot) Nothing Nothing
withInitial :: Return.RawNativeReturnEvaluation -> Known -> Known
withInitial actual (Known child snapshot _ evaluation) = Known child snapshot (Just actual) evaluation
withEvaluation :: Maybe Return.RawNativeReturnEvaluation -> Known -> Known
withEvaluation actual (Known child snapshot initial _) = Known child snapshot initial actual
rejected :: NativeArsStage -> Known -> Text -> NativeArsFailure
rejected stage known detail = NativeArsFailure stage NativeArsRejected detail known
consumed :: NativeArsStage -> Known -> NativeArsFailure
consumed stage =
  NativeArsFailure stage NativeArsAlreadyConsumed "native ARS stage has already been consumed"
asUnmaterializable :: NativeArsFailure -> NativeArsFailure
asUnmaterializable (NativeArsFailure stage _ detail known) = NativeArsFailure stage NativeArsUnmaterializable detail known
mapSelection :: Either Text value -> Either NativeArsFailure value
mapSelection = mapLeft (rejected NativeArsSelection emptyKnown)

-- Exactly the closed phase catcher, with outer Either and Left text forced
-- inside safe tryAny. Async exceptions propagate; no arbitrary Right payload
-- is claimed forced unless the phase does it explicitly.
at :: NativeArsStage -> Known -> IO (Either Text value) -> IO (Either NativeArsFailure value)
at stage known action = do
  attempted <- tryAny (action >>= forceEither)
  case attempted of
    Right result -> pure (mapLeft (rejected stage known) result)
    Left exception -> Left <$> exceptionFailure stage known exception
exceptionFailure :: NativeArsStage -> Known -> SomeException -> IO NativeArsFailure
exceptionFailure stage known exception = do
  rendered <- tryAny $ do
    let detail = Text.pack (displayException exception)
    forceText detail
    pure detail
  pure
    ( NativeArsFailure
        stage
        NativeArsSynchronousFailure
        (fromRight "native ARS exception rendering failed" rendered)
        known
    )

-- Unit/data only; this adapter cannot create an actual observation or stage.
observeNativeArsFailureBoundary
  :: NativeArsStage -> IO (Either Text ()) -> IO (Either NativeArsFailure ())
observeNativeArsFailureBoundary stage = at stage emptyKnown

metaChild :: Meta -> NativeArsChildData
metaChild (Meta child _ _ _ _ _) = child
metaContext :: Meta -> NativeArsContextData
metaContext (Meta _ context _ _ _ _) = context
metaCoverage :: Meta -> NativeArsSourceCoverage
metaCoverage (Meta _ _ coverage _ _ _) = coverage
metaAttempt :: Meta -> Text
metaAttempt (Meta _ _ _ nonce _ _) = nonce
metaDigest :: Meta -> Text
metaDigest (Meta _ _ _ _ context _) = context
metaBefore :: Meta -> Producer.ObservedProducerProcess
metaBefore (Meta _ _ _ _ _ before) = before

nativeArsBegunChild :: NativeArsBegun -> NativeArsChildData
nativeArsBegunChild (NativeArsBegun meta _) = metaChild meta
nativeArsBegunContext :: NativeArsBegun -> NativeArsContextData
nativeArsBegunContext (NativeArsBegun meta _) = metaContext meta
nativeArsBegunAttemptId :: NativeArsBegun -> Text
nativeArsBegunAttemptId (NativeArsBegun meta _) = metaAttempt meta
nativeArsBegunContextDigest :: NativeArsBegun -> Text
nativeArsBegunContextDigest (NativeArsBegun meta _) = metaDigest meta
nativeArsBegunBeforeProcess :: NativeArsBegun -> Producer.ObservedProducerProcess
nativeArsBegunBeforeProcess (NativeArsBegun meta _) = metaBefore meta
nativeArsBegunSourceCoverage :: NativeArsBegun -> NativeArsSourceCoverage
nativeArsBegunSourceCoverage (NativeArsBegun meta _) = metaCoverage meta
nativeArsPreparedSnapshot :: NativeArsPrepared -> Ars.ArsPreparedSnapshot
nativeArsPreparedSnapshot (NativeArsPrepared _ _ snapshot _) = snapshot
nativeArsReadySnapshot :: NativeArsReadyToTrain -> Ars.ArsPreparedSnapshot
nativeArsReadySnapshot (NativeArsReadyToTrain _ _ snapshot _ _) = snapshot
nativeArsReadyInitialEvaluation :: NativeArsReadyToTrain -> Return.RawNativeReturnEvaluation
nativeArsReadyInitialEvaluation (NativeArsReadyToTrain _ _ _ initial _) = initial
nativeArsPendingReturned :: NativeArsPendingFinal -> NativeArsReturnedData
nativeArsPendingReturned (NativeArsPendingFinal actual _) = actual
nativeArsReturnedChild :: NativeArsReturnedData -> NativeArsChildData
nativeArsReturnedChild (NativeArsReturnedData meta _ _ _) = metaChild meta
nativeArsReturnedSnapshot :: NativeArsReturnedData -> Ars.ArsPreparedSnapshot
nativeArsReturnedSnapshot (NativeArsReturnedData _ snapshot _ _) = snapshot
nativeArsReturnedPolicy :: NativeArsReturnedData -> Ars.ArsTrainObservation
nativeArsReturnedPolicy (NativeArsReturnedData _ _ _ raw) = raw
nativeArsReturnedInitialEvaluation :: NativeArsReturnedData -> Return.RawNativeReturnEvaluation
nativeArsReturnedInitialEvaluation (NativeArsReturnedData _ _ initial _) = initial
nativeArsFinalReturned :: NativeArsFinalObservation -> NativeArsReturnedData
nativeArsFinalReturned (NativeArsFinalObservation raw _ _ _) = raw
nativeArsFinalEvaluation :: NativeArsFinalObservation -> Maybe Return.RawNativeReturnEvaluation
nativeArsFinalEvaluation (NativeArsFinalObservation _ evaluation _ _) = evaluation
nativeArsFinalEvaluationFailure :: NativeArsFinalObservation -> Maybe NativeArsFailure
nativeArsFinalEvaluationFailure (NativeArsFinalObservation _ _ failure _) = failure
nativeArsFinalOrigin
  :: NativeArsFinalObservation -> Either NativeArsFailure NativeArsExecutionOrigin
nativeArsFinalOrigin (NativeArsFinalObservation _ _ _ origin) = origin
nativeArsOriginChild :: NativeArsExecutionOrigin -> NativeArsChildData
nativeArsOriginChild (NativeArsExecutionOrigin meta _ _ _ _) = metaChild meta
nativeArsOriginContext :: NativeArsExecutionOrigin -> NativeArsContextData
nativeArsOriginContext (NativeArsExecutionOrigin meta _ _ _ _) = metaContext meta
nativeArsOriginAttemptId :: NativeArsExecutionOrigin -> Text
nativeArsOriginAttemptId (NativeArsExecutionOrigin meta _ _ _ _) = metaAttempt meta
nativeArsOriginContextDigest :: NativeArsExecutionOrigin -> Text
nativeArsOriginContextDigest (NativeArsExecutionOrigin meta _ _ _ _) = metaDigest meta
nativeArsOriginSourceCoverage :: NativeArsExecutionOrigin -> NativeArsSourceCoverage
nativeArsOriginSourceCoverage (NativeArsExecutionOrigin meta _ _ _ _) = metaCoverage meta
nativeArsOriginBeforeProcess :: NativeArsExecutionOrigin -> Producer.ObservedProducerProcess
nativeArsOriginBeforeProcess (NativeArsExecutionOrigin meta _ _ _ _) = metaBefore meta
nativeArsOriginAfterProcess :: NativeArsExecutionOrigin -> Producer.ObservedProducerProcess
nativeArsOriginAfterProcess (NativeArsExecutionOrigin _ _ _ _ after) = after
nativeArsOriginSnapshot :: NativeArsExecutionOrigin -> Ars.ArsPreparedSnapshot
nativeArsOriginSnapshot (NativeArsExecutionOrigin _ snapshot _ _ _) = snapshot
nativeArsOriginPolicy :: NativeArsExecutionOrigin -> Ars.ArsTrainObservation
nativeArsOriginPolicy (NativeArsExecutionOrigin _ _ raw _ _) = raw
nativeArsOriginNumericalRuntime :: NativeArsExecutionOrigin -> Ars.ArsNumericalRuntime
nativeArsOriginNumericalRuntime (NativeArsExecutionOrigin _ _ _ runtime _) = runtime
nativeArsFailureStage :: NativeArsFailure -> NativeArsStage
nativeArsFailureStage (NativeArsFailure stage _ _ _) = stage
nativeArsFailureKind :: NativeArsFailure -> NativeArsFailureKind
nativeArsFailureKind (NativeArsFailure _ kind _ _) = kind
nativeArsFailureDetail :: NativeArsFailure -> Text
nativeArsFailureDetail (NativeArsFailure _ _ detail _) = detail
nativeArsFailureChild :: NativeArsFailure -> Maybe NativeArsChildData
nativeArsFailureChild (NativeArsFailure _ _ _ (Known child _ _ _)) = child
nativeArsFailureSnapshot :: NativeArsFailure -> Maybe Ars.ArsPreparedSnapshot
nativeArsFailureSnapshot (NativeArsFailure _ _ _ (Known _ snapshot _ _)) = snapshot
nativeArsFailureInitialEvaluation :: NativeArsFailure -> Maybe Return.RawNativeReturnEvaluation
nativeArsFailureInitialEvaluation (NativeArsFailure _ _ _ (Known _ _ initial _)) = initial
nativeArsFailureEvaluation :: NativeArsFailure -> Maybe Return.RawNativeReturnEvaluation
nativeArsFailureEvaluation (NativeArsFailure _ _ _ (Known _ _ _ evaluation)) = evaluation
