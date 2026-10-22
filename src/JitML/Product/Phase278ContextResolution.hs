{-# LANGUAGE OverloadedStrings #-}

-- | Pure status projection over observations made by the actual FILE loaders.
-- These records are ordinary evidence DATA, not execution or admission caps.
-- Gates match the original qualifying source epoch. Later edits affect the
-- global standing gates, rather than retrospectively changing that epoch.
module JitML.Product.Phase278ContextResolution
  ( Phase278LaneEpoch (..)
  , Phase278ReviewEvidence (..)
  , derivePhase278Contexts
  ) where

import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Product.SourceDigest (SourceStamp (..))
import JitML.Product.StatusEvidence
  ( Derived (..)
  , EvidenceRef (..)
  , Phase278Context (..)
  , TranscriptEvidence (..)
  , Unmet (..)
  )
import JitML.Product.ValidationRecord (ValidationGate (..), renderValidationGate)
import JitML.Substrate (Substrate (..), renderSubstrate)

data Phase278LaneEpoch = Phase278LaneEpoch
  { phase278EpochSource :: !SourceStamp
  , phase278EpochSupervisedSelection :: !Text
  , phase278EpochNativeSelection :: !Text
  , phase278EpochReference :: !EvidenceRef
  }
  deriving stock (Eq, Show)

data Phase278ReviewEvidence = Phase278ReviewEvidence
  { phase278ReviewSource :: !SourceStamp
  , phase278ReviewSelection :: !Text
  , phase278ReviewJudgement :: !Derived
  }
  deriving stock (Eq, Show)

type Observation value = Either (NonEmpty Unmet) value

derivePhase278Contexts
  :: Map Substrate (Observation Phase278LaneEpoch)
  -> Map Substrate Derived
  -> Map (ValidationGate, Substrate) TranscriptEvidence
  -> Map Substrate (Observation Phase278ReviewEvidence)
  -> Map Substrate (Observation Phase278ReviewEvidence)
  -> Map Phase278Context Derived
derivePhase278Contexts epochs lanes transcripts supervised native =
  Map.fromList
    [ (AppleExecutionContext, together [lane AppleSilicon, gate JitmlBackends AppleSilicon])
    , (SupervisedCriterionContext, criterion phase278EpochSupervisedSelection supervised)
    , (NativeCriterionContext, criterion phase278EpochNativeSelection native)
    , (GenericRlLiveContext, gate JitmlDaemonLifecycle LinuxCPU)
    ]
 where
  epoch substrate =
    Map.findWithDefault
      (Left (Missing (renderSubstrate substrate <> " qualifying lane registration") :| []))
      substrate
      epochs
  lane substrate =
    Map.findWithDefault
      (Unproven (Missing (renderSubstrate substrate <> " complete admitted lane") :| []))
      substrate
      lanes
  gate validation substrate =
    let expected = epoch substrate
        subject = renderValidationGate validation <> " " <> renderSubstrate substrate
        observed = Map.lookup (validation, substrate) transcripts
        result = case observed of
          Nothing -> Unproven (Missing subject :| [])
          Just transcript ->
            together
              [ transcriptJudgement transcript
              , case (expected, transcriptSource transcript) of
                  (Left errors, _) -> Unproven errors
                  (Right _, Nothing) -> Unproven (Missing (subject <> " original source stamp") :| [])
                  (Right original, Just actual)
                    | phase278EpochSource original == actual -> epochProof original
                    | otherwise ->
                        Unproven
                          ( Stale
                              (subject <> " qualifying source epoch")
                              (renderStamp (phase278EpochSource original))
                              (renderStamp actual)
                              :| []
                          )
              ]
     in result
  criterion selected reviews =
    together
      [ together
          [ lane substrate
          , observedReview selected reviews substrate
          ]
      | substrate <- [LinuxCPU, AppleSilicon]
      ]
  observedReview selected reviews substrate =
    let original = epoch substrate
        review =
          Map.findWithDefault
            (Left (Missing (renderSubstrate substrate <> " selected criterion review") :| []))
            substrate
            reviews
        observations =
          [ either Unproven epochProof original
          , either Unproven phase278ReviewJudgement review
          ]
        bindings = case (original, review) of
          (Right expected, Right actual) ->
            [ Stale
                (renderSubstrate substrate <> " criterion-review source epoch")
                (renderStamp (phase278EpochSource expected))
                (renderStamp (phase278ReviewSource actual))
            | phase278EpochSource expected /= phase278ReviewSource actual
            ]
              <> [ Stale
                     (renderSubstrate substrate <> " criterion-review selection")
                     (selected expected)
                     (phase278ReviewSelection actual)
                 | selected expected /= phase278ReviewSelection actual
                 ]
          _ -> []
     in case NonEmpty.nonEmpty bindings of
          Nothing -> together observations
          Just errors -> together (Unproven errors : observations)

epochProof :: Phase278LaneEpoch -> Derived
epochProof epoch = Proven (phase278EpochReference epoch :| [])

-- Never discards a failed component or constructs proof from no observations.
together :: [Derived] -> Derived
together values =
  case NonEmpty.nonEmpty [reason | Unproven reasons <- values, reason <- NonEmpty.toList reasons] of
    Just reasons -> Unproven reasons
    Nothing -> case NonEmpty.nonEmpty [reference | Proven references <- values, reference <- NonEmpty.toList references] of
      Just references -> Proven references
      Nothing -> Unproven (Incomplete "Phase 278 context has no observed evidence" :| [])

renderStamp :: SourceStamp -> Text
renderStamp stamp =
  -- The algorithm is part of SourceStamp equality; expose it in a mismatch.
  Text.pack (show (stampAlgorithm stamp)) <> ":" <> stampSha256 stamp
