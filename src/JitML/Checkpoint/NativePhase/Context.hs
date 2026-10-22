{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Canonical plan/transport comparison DATA. This does not authenticate an
-- invocation, observe a process, reserve an attempt or restore a capability.
module JitML.Checkpoint.NativePhase.Context
  ( NativeContextAssociation (..)
  , NativeContextSources (..)
  , nativePhaseContextValues
  , compareNativePhaseContextValues
  , digestFromCanonicalText
  ) where

import Control.Monad (unless)
import Data.ByteString qualified as BS
import Data.Char (ord)
import Data.Either.Combinators (mapLeft)
import Data.List (find)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as UTF8
import Data.Word (Word64)

import JitML.Checkpoint.NativePhase.Types
  ( CodecError (..)
  , Digest
  , NodeValue (..)
  , Resource (..)
  , checkLimit
  , mkDigest
  )
import JitML.Plan.NativeChildAssociation qualified as Association
import JitML.Plan.NativeSingletonPlan qualified as Native
import JitML.Plan.Plan qualified as Plan
import JitML.Plan.Workload qualified as Workload
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.Product.SourceDigest qualified as Source
import JitML.RL.ProductBudget qualified as ProductBudget
import JitML.Substrate (Substrate (..))
import JitML.Training.Budget qualified as Budget

data NativeContextAssociation
  = DirectLocalContext !Digest
  | SuppliedScenarioContext !Budget.ProductScenarioInvocation
  deriving stock (Eq, Show)

-- The distinction is retained even when the two ordinary values are equal.
data NativeContextSources = NativeContextSources
  { nativeContextObservedSource :: !(Maybe Source.SourceStamp)
  , nativeContextSuppliedSource :: !(Maybe Source.SourceStamp)
  }
  deriving stock (Eq, Show)

-- | The last three arguments are recorded attempt/acquisition/producer-node
-- identities. Accepting their ordinary bytes confers no fresh-origin claim.
-- The producer must generate/observe its own actual values before using this
-- DATA builder. The generic decoder never invokes a plan/capability factory.
nativePhaseContextValues
  :: Cohort.NativeRlCohortBatch
  -> Text
  -> Cohort.NativeSeedIndex
  -> NativeContextAssociation
  -> NativeContextSources
  -> Digest
  -> Digest
  -> Digest
  -> Either CodecError [NodeValue]
nativePhaseContextValues batch row index supplied sources attempt acquisition producer = do
  checked <- fromText (Cohort.refineNativeRlCohortBatch lane (Cohort.nativeRlCohortBatchPlans batch))
  unless (checked == batch) (Left (Malformed "native context complete batch differs"))
  cohort <-
    maybe
      (Left (Malformed "native context row absent from complete batch"))
      Right
      ( find
          ((== row) . Matrix.rowId . Cohort.nativeRlCohortPlanRow)
          (Cohort.nativeRlCohortBatchPlans batch)
      )
  child <-
    maybe
      (Left (Malformed "native context ordinal absent from row"))
      Right
      (find ((== index) . Cohort.nativeRlSeedPlanIndex) (Cohort.nativeRlCohortPlanChildren cohort))
  let parent = Cohort.nativeRlSeedPlanSingleton (Cohort.nativeRlCohortServingChild cohort)
      singleton = Cohort.nativeRlSeedPlanSingleton child
      projectionId = case Cohort.nativeRlCohortPlanProjection cohort of
        Matrix.SomeProductProjection _ projection -> Matrix.productProjectionPlanId projection
  checkSingleton parent
  checkSingleton singleton
  cohortText <-
    mapLeft
      (const (Malformed "native context cohort is not UTF8"))
      (UTF8.decodeUtf8' (Cohort.nativeRlCohortPlanTransport cohort))
  -- The private cohort renderer already enforces512 fields, unique names,
  -- per-field limits and a1MiB total. Compare against its exact transport;
  -- there is deliberately no invented parser for an opaque cohort.
  rowValue <- text GeneralTextBytes row
  parentValue <- text SingletonTransportBytes (Native.renderNativeSingletonPlan parent)
  cohortValue <- text CohortTransportBytes cohortText
  childValue <- text SingletonTransportBytes (Native.renderNativeSingletonPlan singleton)
  (associationValue, invocationValue, associationId) <- case supplied of
    DirectLocalContext direct -> pure (VList [VWord 0], VList [VWord 0, VDigest direct], VNull)
    SuppliedScenarioContext invocation -> do
      let rendered = Budget.renderProductScenarioInvocation invocation
      reparsed <- fromText (Budget.parseProductScenarioInvocation rendered)
      unless
        (reparsed == invocation)
        (Left (NonCanonical "native context invocation differs after public roundtrip"))
      relation <- fromText (Cohort.nativeRlSeedAssociation cohort invocation index)
      parentInvocation <- text InvocationTextBytes rendered
      relationTransport <- text AssociationTextBytes (Association.renderNativeChildAssociation relation)
      relationId <- digestFromCanonicalText (Association.nativeAssociationDigest relation)
      invocationId <- digestFromCanonicalText (Budget.productScenarioInvocationDigest invocation)
      pure
        ( VList [VWord 1, parentInvocation, relationTransport]
        , VList [VWord 1, VDigest invocationId]
        , VDigest relationId
        )
  nested <-
    traverse
      planDigest
      [ projectionId
      , Native.nativeSingletonPlanId parent
      , Native.nativeSingletonCommonPlanId parent
      , Native.nativeSingletonPlanId singleton
      , Native.nativeSingletonCommonPlanId singleton
      , Cohort.nativeRlCohortPlanId cohort
      ]
  compiledId <- case (Cohort.nativeRlSeedPlanCompiledReturn child, Cohort.nativeRlSeedPlanAlphaZero child) of
    (Just compiled, Nothing) -> digestFromCanonicalText (ProductBudget.compiledRlPlanId compiled)
    (Nothing, Just arena) -> planDigest (Workload.alphaZeroPlanId arena)
    _ -> Left (Malformed "native context child recipe alternative differs")
  observed <- sourceStamp (nativeContextObservedSource sources)
  suppliedSource <- sourceStamp (nativeContextSuppliedSource sources)
  let budget = Cohort.nativeRlSeedPlanTrainingBudget child
      budgetValue =
        VList
          [ VWord (budgetTag (Budget.trainingBudgetKind budget))
          , VWord (Budget.trainingBudgetTargetUnits budget)
          , maybe VNull VWord (Budget.trainingBudgetSeed budget)
          ]
  pure
    [ rowValue
    , VWord (substrateTag lane)
    , parentValue
    , cohortValue
    , childValue
    , VList (fmap VDigest nested <> [associationId])
    , VDigest compiledId
    , associationValue
    , VWord (fromIntegral (Cohort.nativeSeedIndexValue index))
    , VWord (Cohort.nativeRlSeedPlanSeed child)
    , budgetValue
    , VDigest attempt
    , VDigest acquisition
    , invocationValue
    , VList [observed, suppliedSource]
    , VRef producer
    ]
 where
  lane = Cohort.nativeRlCohortBatchSubstrate batch

-- | Compare complete decoded DATA with the actual selected plan context. Exact
-- text/IDs/absence must agree; successful comparison is not parent admission.
compareNativePhaseContextValues
  :: Cohort.NativeRlCohortBatch
  -> Text
  -> Cohort.NativeSeedIndex
  -> NativeContextAssociation
  -> NativeContextSources
  -> Digest
  -> Digest
  -> Digest
  -> [NodeValue]
  -> Either CodecError ()
compareNativePhaseContextValues batch row index association sources attempt acquisition producer actual = do
  expected <-
    nativePhaseContextValues batch row index association sources attempt acquisition producer
  unless
    (actual == expected)
    (Left (Malformed "decoded native context differs from complete selected context"))

checkSingleton :: Native.NativeSingletonPlan -> Either CodecError ()
checkSingleton value = do
  let rendered = Native.renderNativeSingletonPlan value
  parsed <- fromText (Native.parseNativeSingletonPlan rendered)
  unless
    (parsed == value && Native.renderNativeSingletonPlan parsed == rendered)
    (Left (NonCanonical "native context singleton public roundtrip differs"))

-- | The public PlanId refinement supplies the representation check. Neither
-- this conversion nor its digest result is an origin/plan membership proof.
-- Keep the protocol's explicit lowercase ASCII predicate.

{- HLINT ignore digestFromCanonicalText "Use isDigit" -}
digestFromCanonicalText :: Text -> Either CodecError Digest
digestFromCanonicalText value = do
  parsed <- fromText (Plan.refinePlanIdText value)
  unless
    (Plan.planIdText parsed == value)
    (Left (NonCanonical "native context digest render differs"))
  bytes <- pairs (Text.unpack value)
  mkDigest (BS.pack bytes)
 where
  nibble char
    | char >= '0' && char <= '9' = Right (ord char - ord '0')
    | char >= 'a' && char <= 'f' = Right (ord char - ord 'a' + 10)
    | otherwise = Left (NonCanonical "native context digest is not lowercase ASCII hex")
  pairs [] = Right []
  pairs (a : b : rest) = do
    high <- nibble a
    low <- nibble b
    (fromIntegral (16 * high + low) :) <$> pairs rest
  pairs _ = Left (Malformed "native context digest has odd hex width")

planDigest :: Plan.PlanId -> Either CodecError Digest
planDigest = digestFromCanonicalText . Plan.planIdText

sourceStamp :: Maybe Source.SourceStamp -> Either CodecError NodeValue
sourceStamp Nothing = Right VNull
sourceStamp (Just stamp) = do
  unless
    (Source.stampAlgorithm stamp == Source.sourceDigestAlgorithm)
    (Left (Malformed "native context source algorithm unsupported"))
  digest <- digestFromCanonicalText (Source.stampSha256 stamp)
  pure (VList [VWord (Source.stampAlgorithm stamp), VDigest digest])

text :: Resource -> Text -> Either CodecError NodeValue
text resource value = do
  let bytes = UTF8.encodeUtf8 value
  checkLimit resource (toInteger (BS.length bytes))
  pure (VText value)

substrateTag :: Substrate -> Word64
substrateTag LinuxCPU = 0
substrateTag LinuxCUDA = 1
substrateTag AppleSilicon = 2

budgetTag :: Budget.BudgetKind -> Word64
budgetTag Budget.SupervisedEpochBudget = 0
budgetTag Budget.RlEnvironmentStepBudget = 1
budgetTag Budget.AlphaZeroSelfPlayBudget = 2
budgetTag Budget.TuningTrialBudget = 3

fromText :: Either Text value -> Either CodecError value
fromText = mapLeft Malformed
