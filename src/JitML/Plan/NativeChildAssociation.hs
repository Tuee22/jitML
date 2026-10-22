{-# LANGUAGE OverloadedStrings #-}

-- | Checked association data. One unchanged supplied parent invocation names
-- five different singleton execution plans. This does not establish that the
-- invocation was received, the parent is canonical, or any child executed.
module JitML.Plan.NativeChildAssociation
  ( NativeChildAssociation
  , mkNativeChildAssociation
  , nativeAssociationRow
  , nativeAssociationParent
  , nativeAssociationChild
  , nativeAssociationOrdinal
  , nativeAssociationInvocation
  , nativeAssociationDigest
  , renderNativeChildAssociation
  )
where

import Control.Monad (unless, when)
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Plan.NativeSingletonPlan qualified as Native
import JitML.Plan.Plan qualified as Plan
import JitML.Training.Budget qualified as Budget

-- No record selectors, Read/Generic/Serialise or producer constructors.
data NativeChildAssociation
  = NativeChildAssociation
      !Text
      !Native.NativeSingletonPlan
      !Native.NativeSingletonPlan
      !Int
      !Budget.ProductScenarioInvocation
      !Text
  deriving stock (Eq, Show)

mkNativeChildAssociation
  :: Text
  -> Native.NativeSingletonPlan
  -> Budget.ProductScenarioInvocation
  -> Int
  -> Native.NativeSingletonPlan
  -> Either Text NativeChildAssociation
mkNativeChildAssociation row parent invocation index child = do
  when (Text.null row) (Left "native association row is empty")
  parsedInvocation <-
    Budget.parseProductScenarioInvocation (Budget.renderProductScenarioInvocation invocation)
  unless
    (parsedInvocation == invocation)
    (Left "native association parent invocation roundtrip differs")
  unless
    (Budget.productScenarioInvocationRowId invocation == row)
    (Left "native association parent invocation row differs")
  unless
    (Budget.productScenarioInvocationPlanId invocation == Native.nativeSingletonPlanId parent)
    (Left "native association invocation names a different parent plan")
  unless
    (Budget.productScenarioInvocationSubstrate invocation == Native.nativeSingletonSubstrate parent)
    (Left "native association parent invocation lane differs")
  expected <- Native.deriveNativeChildPlan parent index
  unless
    (child == expected)
    (Left "native association child differs from complete prescribed derivation")
  let payload = associationPayload row parent child index invocation
  identity <- case Plan.planIdFromCanonicalText payload of
    Plan.Success value -> Right value
    Plan.Failure errors -> Left ("native association digest did not refine: " <> Text.pack (show errors))
  pure (NativeChildAssociation row parent child index invocation (Plan.planIdText identity))

nativeAssociationRow :: NativeChildAssociation -> Text
nativeAssociationRow (NativeChildAssociation row _ _ _ _ _) = row

nativeAssociationParent :: NativeChildAssociation -> Native.NativeSingletonPlan
nativeAssociationParent (NativeChildAssociation _ parent _ _ _ _) = parent

nativeAssociationChild :: NativeChildAssociation -> Native.NativeSingletonPlan
nativeAssociationChild (NativeChildAssociation _ _ child _ _ _) = child

nativeAssociationOrdinal :: NativeChildAssociation -> Int
nativeAssociationOrdinal (NativeChildAssociation _ _ _ index _ _) = index

nativeAssociationInvocation :: NativeChildAssociation -> Budget.ProductScenarioInvocation
nativeAssociationInvocation (NativeChildAssociation _ _ _ _ invocation _) = invocation

nativeAssociationDigest :: NativeChildAssociation -> Text
nativeAssociationDigest (NativeChildAssociation _ _ _ _ _ digest) = digest

renderNativeChildAssociation :: NativeChildAssociation -> Text
renderNativeChildAssociation (NativeChildAssociation row parent child index invocation _) =
  associationPayload row parent child index invocation

associationPayload
  :: Text
  -> Native.NativeSingletonPlan
  -> Native.NativeSingletonPlan
  -> Int
  -> Budget.ProductScenarioInvocation
  -> Text
associationPayload row parent child index invocation =
  Text.concat
    ( fmap
        field
        [ "jitml-native-child-association-v1"
        , Native.nativeChildNamespaceContract
        , row
        , Native.renderNativeSingletonPlan parent
        , Native.renderNativeSingletonPlan child
        , Text.pack (show index)
        , Budget.renderProductScenarioInvocation invocation
        ]
    )
 where
  field value = Text.pack (show (Text.length value)) <> ":" <> value
