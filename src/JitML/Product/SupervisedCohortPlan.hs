{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Five prescribed singleton plans for one compact supervised qualification.
-- These plans establish execution identity; they do not assert that any run
-- happened or that its measured result passed.
module JitML.Product.SupervisedCohortPlan
  ( SupervisedCohortPlan
  , SupervisedSeedPlan
  , mkSupervisedCohortPlan
  , supervisedCohortPlanChildren
  , supervisedCohortPlanId
  , supervisedCohortPlanProjection
  , supervisedCohortPlanTransport
  , supervisedSeedPlanBaseProjection
  , supervisedSeedPlanIndex
  , supervisedSeedPlanSeed
  , supervisedSeedPlanWorkload
  )
where

import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)

import JitML.Plan.Plan (PlanId, RunKind (SupervisedTraining), Validation (..))
import JitML.Plan.Plan qualified as Plan
import JitML.Plan.Workload qualified as Workload
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.SupervisedQualificationPolicy qualified as Policy

data SupervisedSeedPlan
  = SupervisedSeedPlan
      !(Matrix.ProductProjection 'SupervisedTraining)
      !Policy.SupervisedSeedIndex
      !Word64
      !Workload.SupervisedPlan
  deriving stock (Eq, Show)

data SupervisedCohortPlan
  = SupervisedCohortPlan
      !(Matrix.ProductProjection 'SupervisedTraining)
      ![SupervisedSeedPlan]
      !Text
      !PlanId
  deriving stock (Eq, Show)

mkSupervisedCohortPlan
  :: Matrix.ProductProjection 'SupervisedTraining
  -> Either Text SupervisedCohortPlan
mkSupervisedCohortPlan projection = do
  children <- traverse makeChild Policy.supervisedSeedIndices
  let transport =
        "jitml-supervised-cohort-plan-v1|"
          <> Text.concat
            ( fmap
                field
                ( Policy.supervisedQualificationPolicyContract
                    : Plan.planIdText (Matrix.productProjectionPlanId projection)
                    : concatMap childFields children
                )
            )
  identity <-
    case Plan.planIdFromCanonicalText transport of
      Success value -> Right value
      Failure errors -> Left ("supervised cohort identity did not refine: " <> Text.pack (show errors))
  Right (SupervisedCohortPlan projection children transport identity)
 where
  makeChild index = do
    plan <- Matrix.projectSupervisedSeedPlan projection index
    case NonEmpty.toList (Plan.seedCohortValues (Plan.runPlanSeeds (Workload.supervisedPlanRunPlan plan))) of
      [seed] -> Right (SupervisedSeedPlan projection index seed plan)
      _ -> Left "supervised cohort child does not have exactly one execution seed"
  childFields child =
    [ Text.pack (show (Policy.supervisedSeedIndexValue (supervisedSeedPlanIndex child)))
    , Text.pack (show (supervisedSeedPlanSeed child))
    , Workload.renderSupervisedPlanTransport (supervisedSeedPlanWorkload child)
    ]
  field value = Text.pack (show (Text.length value)) <> ":" <> value <> "|"

supervisedCohortPlanProjection
  :: SupervisedCohortPlan
  -> Matrix.ProductProjection 'SupervisedTraining
supervisedCohortPlanProjection (SupervisedCohortPlan projection _ _ _) = projection

supervisedCohortPlanChildren :: SupervisedCohortPlan -> [SupervisedSeedPlan]
supervisedCohortPlanChildren (SupervisedCohortPlan _ children _ _) = children

supervisedCohortPlanTransport :: SupervisedCohortPlan -> Text
supervisedCohortPlanTransport (SupervisedCohortPlan _ _ transport _) = transport

supervisedCohortPlanId :: SupervisedCohortPlan -> PlanId
supervisedCohortPlanId (SupervisedCohortPlan _ _ _ identity) = identity

supervisedSeedPlanBaseProjection
  :: SupervisedSeedPlan
  -> Matrix.ProductProjection 'SupervisedTraining
supervisedSeedPlanBaseProjection (SupervisedSeedPlan projection _ _ _) = projection

supervisedSeedPlanIndex :: SupervisedSeedPlan -> Policy.SupervisedSeedIndex
supervisedSeedPlanIndex (SupervisedSeedPlan _ index _ _) = index

supervisedSeedPlanSeed :: SupervisedSeedPlan -> Word64
supervisedSeedPlanSeed (SupervisedSeedPlan _ _ seed _) = seed

supervisedSeedPlanWorkload :: SupervisedSeedPlan -> Workload.SupervisedPlan
supervisedSeedPlanWorkload (SupervisedSeedPlan _ _ _ plan) = plan
