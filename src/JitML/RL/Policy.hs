{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.Policy
  ( ParamRef (..)
  , Policy (..)
  , PolicyShape (..)
  , defaultPolicy
  , policyArity
  , policyDescription
  , renderPolicyShape
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Cache.Key (ModelId (..))
import JitML.RL.Framework (ActionDistribution (..))
import JitML.Substrate (Substrate (..))

newtype ParamRef = ParamRef
  { unParamRef :: Text
  }
  deriving stock (Eq, Show)

data PolicyShape = PolicyShape
  { policyObservationSize :: Int
  , policyActionCount :: Int
  , policyHiddenSizes :: [Int]
  , policyDistribution :: ActionDistribution
  }
  deriving stock (Eq, Show)

data Policy = Policy
  { policyName :: Text
  , policyShape :: PolicyShape
  , policyParams :: [ParamRef]
  , policySubstrate :: Substrate
  , policyKernelModelId :: ModelId
  }
  deriving stock (Eq, Show)

defaultPolicy :: Text -> Int -> Int -> Substrate -> Policy
defaultPolicy name obsSize actionCount substrate =
  Policy
    { policyName = name
    , policyShape =
        PolicyShape
          { policyObservationSize = obsSize
          , policyActionCount = actionCount
          , policyHiddenSizes = [64, 64]
          , policyDistribution =
              if actionCount > 0 then Categorical else DeterministicPolicy
          }
    , policyParams = [ParamRef "actor.fc1", ParamRef "actor.fc2", ParamRef "value.fc"]
    , policySubstrate = substrate
    , policyKernelModelId = ModelId name
    }

policyArity :: Policy -> Int
policyArity policy = policyActionCount (policyShape policy)

policyDescription :: Policy -> Text
policyDescription policy =
  Text.unlines
    [ "policy: " <> policyName policy
    , renderPolicyShape (policyShape policy)
    , "kernel-model-id: " <> unModelId (policyKernelModelId policy)
    ]

renderPolicyShape :: PolicyShape -> Text
renderPolicyShape shape =
  Text.unlines
    [ "  observation-size: " <> Text.pack (show (policyObservationSize shape))
    , "  action-count:     " <> Text.pack (show (policyActionCount shape))
    , "  hidden-sizes:     " <> Text.pack (show (policyHiddenSizes shape))
    , "  distribution:     " <> Text.pack (show (policyDistribution shape))
    ]
