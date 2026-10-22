{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

module NativeChildAssociation (nativeChildAssociationTests) where

import Control.Monad (forM, forM_)
import Data.List (nub)
import Data.Maybe (catMaybes)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Plan.NativeChildAssociation qualified as Association
import JitML.Plan.NativeSingletonPlan qualified as Native
import JitML.Plan.Plan qualified as Plan
import JitML.Plan.Workload qualified as Workload
import JitML.Product.Matrix qualified as Matrix
import JitML.Substrate (Substrate (..))
import JitML.Training.Budget qualified as Budget

nativeChildAssociationTests :: TestTree
nativeChildAssociationTests =
  testGroup
    "native child complete plan association"
    [ testCase "all canonical native singleton transports preserve the whole refined execution plan" $ do
        forM_ lanes $ \lane -> do
          parents <- canonicalParents lane
          length parents @?= 43
          forM_ parents $ \(_, parent) ->
            Native.parseNativeSingletonPlan (Native.renderNativeSingletonPlan parent) @?= Right parent
    , testCase "AlphaZero retains the actual game and outer identity separately from its common RunPlan" $ do
        parents <- canonicalParents LinuxCPU
        let games = [plan | (_, native) <- parents, Just plan <- [Native.nativeSingletonAlphaZeroPlan native]]
        length games @?= 4
        forM_ games $ \plan -> do
          native <- right (Native.nativeAlphaZeroSingletonPlan plan)
          Native.nativeSingletonPlanId native @?= Workload.alphaZeroPlanId plan
          Native.nativeSingletonCommonPlanId native @?= Plan.runPlanId (Workload.alphaZeroPlanRunPlan plan)
          assertBool
            "outer game identity was reduced to common identity"
            (Native.nativeSingletonPlanId native /= Native.nativeSingletonCommonPlanId native)
          parsed <- right (Native.parseNativeSingletonPlan (Native.renderNativeSingletonPlan native))
          Native.nativeSingletonAlphaZeroPlan parsed @?= Just plan
    , testCase "index zero is the exact parent and all prescribed child namespaces are injective" $ do
        forM_ lanes $ \lane -> do
          parents <- canonicalParents lane
          groups <- forM parents $ \(_, parent) -> do
            children <- traverse (right . Native.deriveNativeChildPlan parent) [0 .. 4]
            case children of
              first : _ -> first @?= parent
              [] -> assertFailure "prescribed native cohort unexpectedly has no children"
            fmap Native.nativeSingletonSeed children @?= [42 .. 46]
            forM_ children $ \child -> do
              Native.nativeSingletonSubstrate child @?= lane
              Native.parseNativeSingletonPlan (Native.renderNativeSingletonPlan child) @?= Right child
            pure children
          let experiments = fmap Native.nativeSingletonExperiment (concat groups)
          length experiments @?= 215
          length (nub experiments) @?= 215
          length (nub (fmap Native.nativeSingletonPlanId (concat groups))) @?= 215
    , testCase "child derivation preserves every unrelated common field and AlphaZero game" $ do
        parents <- canonicalParents LinuxCPU
        forM_ parents $ \(_, parent) -> forM_ [1 .. 4] $ \index -> do
          child <- right (Native.deriveNativeChildPlan parent index)
          case (Native.nativeSingletonRlPlan parent, Native.nativeSingletonRlPlan child) of
            (Just p, Just c) -> do
              Plan.runPlanSubjectId c @?= Plan.runPlanSubjectId p
              Plan.runPlanTopicId c @?= Plan.runPlanTopicId p
              Plan.runPlanVersion c @?= Plan.runPlanVersion p
              Plan.runPlanPlacement c @?= Plan.runPlanPlacement p
              Plan.runPlanRlBudget c @?= Plan.runPlanRlBudget p
            _ -> case (Native.nativeSingletonAlphaZeroPlan parent, Native.nativeSingletonAlphaZeroPlan child) of
              (Just p, Just c) -> do
                Workload.alphaZeroPlanGame c @?= Workload.alphaZeroPlanGame p
                let pr = Workload.alphaZeroPlanRunPlan p
                    cr = Workload.alphaZeroPlanRunPlan c
                Plan.runPlanSubjectId cr @?= Plan.runPlanSubjectId pr
                Plan.runPlanTopicId cr @?= Plan.runPlanTopicId pr
                Plan.runPlanVersion cr @?= Plan.runPlanVersion pr
                Plan.runPlanPlacement cr @?= Plan.runPlanPlacement pr
                Plan.runPlanAlphaZeroBudget cr @?= Plan.runPlanAlphaZeroBudget pr
              _ -> assertFailure "native child changed its run kind"
    , testCase "one unchanged full parent invocation binds all five distinct child plans" $ do
        parents <- canonicalParents LinuxCPU
        forM_ parents $ \(row, parent) -> do
          invocation <- invocationFor row parent
          associations <- forM [0 .. 4] $ \index -> do
            child <- right (Native.deriveNativeChildPlan parent index)
            association <- right (Association.mkNativeChildAssociation row parent invocation index child)
            Association.nativeAssociationParent association @?= parent
            Association.nativeAssociationChild association @?= child
            Association.nativeAssociationOrdinal association @?= index
            Association.nativeAssociationInvocation association @?= invocation
            Association.nativeAssociationRow association @?= row
            pure association
          length (nub (fmap Association.nativeAssociationDigest associations)) @?= 5
          length (nub (fmap Association.renderNativeChildAssociation associations)) @?= 5
    , testCase "a fabricated auxiliary invocation cannot replace the actually supplied parent invocation" $ do
        (row, parent) <- firstParent
        child <- right (Native.deriveNativeChildPlan parent 1)
        childInvocation <- invocationFor row child
        leftContaining
          "different parent plan"
          (Association.mkNativeChildAssociation row parent childInvocation 1 child)
    , testCase "wrong invocation row and lane fail before a child association can refine" $ do
        (row, parent) <- firstParent
        wrongRow <- invocationFor "different-row" parent
        leftContaining "row differs" (Association.mkNativeChildAssociation row parent wrongRow 0 parent)
        wrongLane <-
          right
            ( Budget.mkProductScenarioInvocation
                "native-test-run"
                row
                (Native.nativeSingletonPlanId parent)
                AppleSilicon
                (digest 'a')
                (digest 'b')
                (digest 'c')
            )
        leftContaining "lane differs" (Association.mkNativeChildAssociation row parent wrongLane 0 parent)
    , testCase "a different ordinal or sibling cannot be rebound to the same association" $ do
        (row, parent) <- firstParent
        invocation <- invocationFor row parent
        child <- right (Native.deriveNativeChildPlan parent 1)
        leftContaining
          "prescribed derivation"
          (Association.mkNativeChildAssociation row parent invocation 2 child)
        forM_ [-1, 5] $ \index -> leftContaining "ordinal" (Native.deriveNativeChildPlan parent index)
    , testCase "transport rejects a substituted identity unit trailing data and oversized input" $ do
        (_, parent) <- firstParent
        let transport = Native.renderNativeSingletonPlan parent
            identity = Plan.planIdText (Native.nativeSingletonPlanId parent)
        leftContaining
          "PlanId differs"
          (Native.parseNativeSingletonPlan (Text.replace identity (digest '0') transport))
        leftContaining
          "unit/order"
          ( Native.parseNativeSingletonPlan
              (Text.replace "environment-transitions" "environment-transitionx" transport)
          )
        rejects (Native.parseNativeSingletonPlan (transport <> "x"))
        leftContaining "32768" (Native.parseNativeSingletonPlan (Text.replicate 32769 "x"))
    , testCase "length-prefix transport preserves Unicode and separators without normalizing the tuple" $ do
        raw <- customPlan "native-unicode" "subject:λ|=\nbody" 42
        parent <- right (Native.nativeRlSingletonPlan raw)
        parsed <- right (Native.parseNativeSingletonPlan (Native.renderNativeSingletonPlan parent))
        parsed @?= parent
        assertBool
          "Unicode tuple was omitted"
          ("subject:λ|=\nbody" `Text.isInfixOf` Native.renderNativeSingletonPlan parsed)
    , testCase "flat namespace and full five-child seed headroom fail before derivation" $ do
        forM_ [".", "..", "a/b", "a\\b", "a%b", "a b", "λ"] $ \namespace -> do
          raw <- customPlan namespace "subject" 42
          parent <- right (Native.nativeRlSingletonPlan raw)
          leftContaining "flat ASCII" (Native.deriveNativeChildPlan parent 0)
        raw <- customPlan "native-boundary" "subject" (fromIntegral (maxBound :: Int) - 3)
        parent <- right (Native.nativeRlSingletonPlan raw)
        leftContaining "Int range" (Native.deriveNativeChildPlan parent 0)
    , testCase "multiple training seeds cannot be relabeled as a singleton child" $ do
        plan <- refine (request "native-multi" "subject" [42, 43])
        leftContaining "exactly one" (Native.nativeRlSingletonPlan plan)
    ]

lanes :: [Substrate]
lanes = [LinuxCPU, LinuxCUDA, AppleSilicon]

canonicalParents :: Substrate -> IO [(Text, Native.NativeSingletonPlan)]
canonicalParents lane = catMaybes <$> traverse project Matrix.allProductRows
 where
  project :: Matrix.ProductRow state -> IO (Maybe (Text, Native.NativeSingletonPlan))
  project row = case Matrix.projectProductRow lane row of
    Plan.Failure errors -> assertFailure (show errors) >> fail "unreachable"
    Plan.Success (Matrix.SomeProductProjection witness projection) -> case witness of
      Plan.ReinforcementLearningWitness ->
        fmap
          (\plan -> Just (Matrix.rowId row, plan))
          (right (Native.nativeRlSingletonPlan (Matrix.productProjectionRunPlan projection)))
      Plan.AlphaZeroSelfPlayWitness -> case Matrix.productProjectionResolvedPlan projection of
        Matrix.ResolvedAlphaZeroProductPlan plan ->
          fmap (\value -> Just (Matrix.rowId row, value)) (right (Native.nativeAlphaZeroSingletonPlan plan))
      _ -> pure Nothing

firstParent :: IO (Text, Native.NativeSingletonPlan)
firstParent = do
  parents <- canonicalParents LinuxCPU
  case parents of
    parent : _ -> pure parent
    [] -> assertFailure "canonical native registry is empty" >> fail "unreachable"

invocationFor :: Text -> Native.NativeSingletonPlan -> IO Budget.ProductScenarioInvocation
invocationFor row parent =
  right
    ( Budget.mkProductScenarioInvocation
        "native-test-run"
        row
        (Native.nativeSingletonPlanId parent)
        (Native.nativeSingletonSubstrate parent)
        (digest 'a')
        (digest 'b')
        (digest 'c')
    )

digest :: Char -> Text
digest = Text.replicate 64 . Text.singleton

customPlan :: Text -> Text -> Word64 -> IO (Plan.RunPlan 'Plan.ReinforcementLearning)
customPlan experiment subject seed = refine (request experiment subject [seed])

request :: Text -> Text -> [Word64] -> Plan.RawRunRequest 'Plan.ReinforcementLearning
request experiment subject seeds =
  Plan.RawRunRequest
    { Plan.rawRunVersion = 1
    , Plan.rawRunKind = Plan.ReinforcementLearningWitness
    , Plan.rawRunExperimentId = experiment
    , Plan.rawRunSubjectId = subject
    , Plan.rawRunArtifactId = "experiments/capture.dhall"
    , Plan.rawRunTopicId = "training.command.linux-cpu"
    , Plan.rawRunSubstrate = LinuxCPU
    , Plan.rawRunPlacement = Plan.ClusterRun
    , Plan.rawRunSeeds = seeds
    , Plan.rawRunBudget = Plan.RawRlBudget 10 10 1 10 1
    }

refine :: Plan.RawRunRequest kind -> IO (Plan.RunPlan kind)
refine raw = case Plan.resolveRun raw of
  Plan.Success plan -> pure plan
  Plan.Failure errors -> assertFailure (show errors) >> fail "unreachable"

right :: (Show e) => Either e a -> IO a
right result = case result of
  Right value -> pure value
  Left err -> assertFailure (show err) >> fail "unreachable"

rejects :: Either Text a -> Assertion
rejects result = case result of
  Left _ -> pure ()
  Right _ -> assertFailure "malformed native plan was accepted"

leftContaining :: Text -> Either Text a -> Assertion
leftContaining expected result = case result of
  Left err -> assertBool ("wrong rejection: " <> Text.unpack err) (expected `Text.isInfixOf` err)
  Right _ -> assertFailure "expected the specific native association rejection"
