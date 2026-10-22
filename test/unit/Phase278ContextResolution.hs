{-# LANGUAGE OverloadedStrings #-}

module Phase278ContextResolution (phase278ContextResolutionTests) where

import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, testCase, (@?=))

import JitML.Product.Phase278ContextResolution qualified as Context
import JitML.Product.SourceDigest (SourceStamp (..))
import JitML.Product.StatusEvidence
  ( Derived (..)
  , EvidenceRef (..)
  , Phase278Context (..)
  , TranscriptEvidence (..)
  , Unmet (..)
  )
import JitML.Product.StatusEvidence qualified as Evidence
import JitML.Product.ValidationRecord (ValidationGate (..))
import JitML.Substrate (Substrate (..))

phase278ContextResolutionTests :: TestTree
phase278ContextResolutionTests =
  testGroup
    "Phase278ContextResolution"
    [ testCase "missing observations leave every named prerequisite unproven" $
        mapM_
          unproven
          (Map.elems (Context.derivePhase278Contexts Map.empty Map.empty Map.empty Map.empty Map.empty))
    , testCase "the complete selected generation resolves all four prerequisites" $
        mapM_ proven (Map.elems complete)
    , testCase "an empty index cannot infer any selected context" $
        mapM_
          (unproven . Evidence.observeObligation Evidence.emptyEvidenceIndex . Evidence.Phase278Prerequisite)
          [minBound .. maxBound]
    , testCase "a selected observation resolves only its named context" $ do
        let index =
              Evidence.emptyEvidenceIndex
                { Evidence.indexPhase278Contexts = Map.singleton AppleExecutionContext proof
                }
        Evidence.observeObligation index (Evidence.Phase278Prerequisite AppleExecutionContext) @?= proof
        unproven (Evidence.observeObligation index (Evidence.Phase278Prerequisite NativeCriterionContext))
    , testCase "a stale CUDA epoch cannot poison the two Phase 278 lanes" $
        Context.derivePhase278Contexts
          (Map.insert LinuxCUDA (Left (Stale "CUDA" "new" "old" :| [])) epochs)
          lanes
          gates
          reviews
          reviews
          @?= complete
    , testCase "an Apple backend from another source epoch remains stale" $
        unproven
          ( derive
              epochs
              lanes
              (Map.insert (JitmlBackends, AppleSilicon) (TranscriptEvidence proof (Just otherSource)) gates)
              reviews
              reviews
              AppleExecutionContext
          )
    , testCase "a failed daemon gate cannot resolve even with the right source" $
        unproven
          ( derive
              epochs
              lanes
              (Map.insert (JitmlDaemonLifecycle, LinuxCPU) (TranscriptEvidence failure (Just source)) gates)
              reviews
              reviews
              GenericRlLiveContext
          )
    , testCase "a backend pass cannot stand for the unfiltered daemon invocation" $
        unproven
          ( derive
              epochs
              lanes
              (Map.delete (JitmlDaemonLifecycle, LinuxCPU) gates)
              reviews
              reviews
              GenericRlLiveContext
          )
    , testCase "an absent gate source is not inferred from lane metadata" $
        unproven
          ( derive
              epochs
              lanes
              (Map.insert (JitmlBackends, AppleSilicon) (TranscriptEvidence proof Nothing) gates)
              reviews
              reviews
              AppleExecutionContext
          )
    , testCase "a source algorithm mismatch is stale even with the same SHA" $
        unproven
          ( derive
              epochs
              lanes
              ( Map.insert
                  (JitmlBackends, AppleSilicon)
                  (TranscriptEvidence proof (Just (source {stampAlgorithm = 2})))
                  gates
              )
              reviews
              reviews
              AppleExecutionContext
          )
    , testCase "a substituted review cannot be attached to an admitted lane" $
        unproven
          ( derive
              epochs
              lanes
              gates
              (Map.insert LinuxCPU (Right (review {Context.phase278ReviewSelection = digest "b"})) reviews)
              reviews
              SupervisedCriterionContext
          )
    , testCase "a failed review remains failed despite matching identity" $
        unproven
          ( derive
              epochs
              lanes
              gates
              reviews
              (Map.insert AppleSilicon (Right (review {Context.phase278ReviewJudgement = failure})) reviews)
              NativeCriterionContext
          )
    , testCase "a review for another original source does not resolve" $
        unproven
          ( derive
              epochs
              lanes
              gates
              (Map.insert LinuxCPU (Right (review {Context.phase278ReviewSource = otherSource})) reviews)
              reviews
              SupervisedCriterionContext
          )
    , testCase "review selections alone cannot qualify missing training evidence" $
        unproven (derive epochs Map.empty gates reviews reviews NativeCriterionContext)
    , testCase "one admitted lane cannot replace the missing Apple cohort" $
        unproven
          (derive epochs (Map.delete AppleSilicon lanes) gates reviews reviews SupervisedCriterionContext)
    , testCase "later current source changes do not rewrite a historical qualifying epoch" $ do
        let index =
              Evidence.emptyEvidenceIndex
                { Evidence.indexCurrentSource = Right otherSource
                , Evidence.indexPhase278Contexts = complete
                }
        mapM_
          (proven . Evidence.observeObligation index . Evidence.Phase278Prerequisite)
          [minBound .. maxBound]
    ]
 where
  derive selected admitted transcripts sl native context =
    Map.findWithDefault
      failure
      context
      (Context.derivePhase278Contexts selected admitted transcripts sl native)
  complete = Context.derivePhase278Contexts epochs lanes gates reviews reviews
  epochs = Map.fromList [(lane, Right epoch) | lane <- [LinuxCPU, AppleSilicon]]
  lanes = Map.fromList [(lane, proof) | lane <- [LinuxCPU, AppleSilicon]]
  gates =
    Map.fromList
      [ ((JitmlBackends, AppleSilicon), TranscriptEvidence proof (Just source))
      , ((JitmlDaemonLifecycle, LinuxCPU), TranscriptEvidence proof (Just source))
      ]
  reviews = Map.fromList [(lane, Right review) | lane <- [LinuxCPU, AppleSilicon]]
  epoch = Context.Phase278LaneEpoch source (digest "a") (digest "a") reference
  review = Context.Phase278ReviewEvidence source (digest "a") proof

source :: SourceStamp
source = SourceStamp 1 (digest "c")

otherSource :: SourceStamp
otherSource = SourceStamp 1 (digest "d")

digest :: Text -> Text
digest = Text.replicate 64

reference :: EvidenceRef
reference = EvidenceRef "actual selected fixture observation" (Just (digest "e"))

proof :: Derived
proof = Proven (reference :| [])

failure :: Derived
failure = Unproven (FailedRun "retained failed fixture" :| [])

proven :: Derived -> Assertion
proven value = assertBool ("expected proven observation: " <> show value) $ case value of
  Proven _ -> True
  Unproven _ -> False

unproven :: Derived -> Assertion
unproven value = assertBool ("expected unresolved observation: " <> show value) $ case value of
  Unproven _ -> True
  Proven _ -> False
