{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

-- Pure actual public plan/recipe controls; no execution/provider/learning claim.
module NativeRlCohortPlan (nativeRlCohortPlanTests) where

import Control.Monad (forM, forM_, when, (>=>))
import Crypto.Hash.SHA256 qualified as SHA256
import Data.Bifunctor (first)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as B8
import Data.Char (intToDigit)
import Data.List (nub, sort)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Encoding
import Data.Word (Word64)
import GHC.Float (castDoubleToWord64)
import Numeric (showHex)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))
import Text.Read (readMaybe)

import JitML.Plan.NativeChildAssociation qualified as Association
import JitML.Plan.NativeSingletonPlan qualified as Native
import JitML.Plan.Plan qualified as Plan
import JitML.Plan.Workload qualified as Workload
import JitML.Product.Convergence qualified as Convergence
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.NativeRlCohortPlan qualified as C
import JitML.RL.ProductBudget qualified as ProductBudget
import JitML.Substrate (Substrate (..))
import JitML.Training.Budget qualified as Budget

right :: (Show err) => Either err value -> IO value
right result = case result of
  Right value -> pure value
  Left err -> assertFailure (show err) >> fail "unreachable"

leftContaining :: Text -> Either Text value -> IO ()
leftContaining fragment result = case result of
  Left message -> assertBool (Text.unpack message) (fragment `Text.isInfixOf` message)
  Right _ -> assertFailure ("expected rejection containing " <> Text.unpack fragment)

lanes :: [Substrate]
lanes = [LinuxCPU, LinuxCUDA, AppleSilicon]

cohortsFor :: Substrate -> IO [C.NativeRlCohortPlan]
cohortsFor lane = fmap C.nativeRlCohortBatchPlans (right (C.mkCanonicalNativeRlCohorts lane))

rowFor :: Text -> IO (Matrix.ProductRow 'Matrix.Declared)
rowFor name = case filter ((== name) . Matrix.rowId) Matrix.allProductRows of
  [row] -> pure row
  _ -> assertFailure ("canonical row absent: " <> Text.unpack name) >> fail "unreachable"

project :: Substrate -> Matrix.ProductRow state -> IO Matrix.SomeProductProjection
project lane row = case Matrix.projectProductRow lane row of
  Plan.Success value -> pure value
  Plan.Failure errors -> assertFailure (show errors) >> fail "unreachable"

cohortFor :: Substrate -> Text -> IO C.NativeRlCohortPlan
cohortFor lane row = rowFor row >>= project lane >>= right . C.mkNativeRlCohortPlan

parentOf :: C.NativeRlCohortPlan -> IO Native.NativeSingletonPlan
parentOf cohort = case C.nativeRlCohortPlanProjection cohort of
  Matrix.SomeProductProjection Plan.ReinforcementLearningWitness projection ->
    case Matrix.productProjectionResolvedPlan projection of
      Matrix.ResolvedRlProductPlan plan -> right (Native.nativeRlSingletonPlan plan)
  Matrix.SomeProductProjection Plan.AlphaZeroSelfPlayWitness projection ->
    case Matrix.productProjectionResolvedPlan projection of
      Matrix.ResolvedAlphaZeroProductPlan plan -> right (Native.nativeAlphaZeroSingletonPlan plan)
  _ -> assertFailure "non-native cohort projection escaped" >> fail "unreachable"

projectionId :: Matrix.SomeProductProjection -> Plan.PlanId
projectionId (Matrix.SomeProductProjection _ projection) = Matrix.productProjectionPlanId projection

projectionBudget :: Matrix.SomeProductProjection -> Budget.TrainingBudget
projectionBudget (Matrix.SomeProductProjection _ projection) = Matrix.productProjectionTrainingBudget projection

artifactOf :: Native.NativeSingletonPlan -> IO Text
artifactOf plan = case (Native.nativeSingletonRlPlan plan, Native.nativeSingletonAlphaZeroPlan plan) of
  (Just value, Nothing) -> pure (Plan.runPlanArtifactId value)
  (Nothing, Just value) -> pure (Plan.runPlanArtifactId (Workload.alphaZeroPlanRunPlan value))
  _ -> assertFailure "lower singleton closed kind differs" >> fail "unreachable"

invocationFor :: Text -> Native.NativeSingletonPlan -> IO Budget.ProductScenarioInvocation
invocationFor row plan =
  right
    ( Budget.mkProductScenarioInvocation
        "native-cohort-offline-data"
        row
        (Native.nativeSingletonPlanId plan)
        (Native.nativeSingletonSubstrate plan)
        (Text.replicate 64 "a")
        (Text.replicate 64 "b")
        (Text.replicate 64 "c")
    )

-- Independent byte-oriented test reader: framing lengths count UTF8 bytes,
-- never Text characters. It observes emitted fields, not producer authority.
readFields :: BS.ByteString -> Either Text [(Text, BS.ByteString)]
readFields bytes = do
  rest <-
    maybe
      (Left "renderer prefix differs")
      Right
      (BS.stripPrefix "jitml-native-rl-cohort-plan-data-v1|" bytes)
  pairs rest
 where
  pairs rest | BS.null rest = Right []
  pairs rest = do
    (key, valueAndRest) <- frame rest
    name <- first (Text.pack . show) (Encoding.decodeUtf8' key)
    (value, remaining) <- frame valueAndRest
    ((name, value) :) <$> pairs remaining
  frame input = do
    let (digits, colonAndBody) = BS.break (== 58) input
    when
      (BS.null digits || BS.null colonAndBody || not (BS.all (\c -> c >= 48 && c <= 57) digits))
      (Left "invalid field byte length")
    size <- maybe (Left "field byte length overflows") Right (readMaybe (B8.unpack digits) :: Maybe Int)
    let body = BS.drop 1 colonAndBody
    if size < 0 || size > BS.length body then Left "truncated field" else Right (BS.splitAt size body)

field :: Text -> [(Text, BS.ByteString)] -> IO BS.ByteString
field name fields =
  maybe
    (assertFailure ("missing actual field: " <> Text.unpack name) >> fail "unreachable")
    pure
    (lookup name fields)

hex :: BS.ByteString -> Text
hex =
  Text.pack
    . concatMap
      (\byte -> [intToDigit (fromIntegral byte `div` 16), intToDigit (fromIntegral byte `mod` 16)])
    . BS.unpack

bitsText :: Double -> Text
bitsText value =
  let digits = showHex (castDoubleToWord64 value) ""
   in Text.pack (replicate (16 - length digits) '0' <> digits)

assertPreservedCommon :: Native.NativeSingletonPlan -> Native.NativeSingletonPlan -> IO ()
assertPreservedCommon parent child = case (Native.nativeSingletonRlPlan parent, Native.nativeSingletonRlPlan child) of
  (Just p, Just c) -> do
    Plan.runPlanSubjectId c @?= Plan.runPlanSubjectId p
    Plan.runPlanTopicId c @?= Plan.runPlanTopicId p
    Plan.runPlanPlacement c @?= Plan.runPlanPlacement p
    Plan.runPlanVersion c @?= Plan.runPlanVersion p
    Plan.runPlanRlBudget c @?= Plan.runPlanRlBudget p
  _ -> case (Native.nativeSingletonAlphaZeroPlan parent, Native.nativeSingletonAlphaZeroPlan child) of
    (Just p, Just c) -> do
      Workload.alphaZeroPlanGame c @?= Workload.alphaZeroPlanGame p
      let pr = Workload.alphaZeroPlanRunPlan p
          cr = Workload.alphaZeroPlanRunPlan c
      Plan.runPlanSubjectId cr @?= Plan.runPlanSubjectId pr
      Plan.runPlanTopicId cr @?= Plan.runPlanTopicId pr
      Plan.runPlanPlacement cr @?= Plan.runPlanPlacement pr
      Plan.runPlanVersion cr @?= Plan.runPlanVersion pr
      Plan.runPlanAlphaZeroBudget cr @?= Plan.runPlanAlphaZeroBudget pr
    _ -> assertFailure "child changed complete workload kind"

-- Keep base's existing sorted/nubbed assertion and total drop on the mutation.
-- The suggested extra convenience helpers would add a test-only dependency.
{- HLINT ignore nativeRlCohortPlanTests "Use nubSort" -}
{- HLINT ignore nativeRlCohortPlanTests "Use drop1" -}
nativeRlCohortPlanTests :: TestTree
nativeRlCohortPlanTests =
  testGroup
    "canonical native five-child cohort plan data"
    [ testCase "all forty three rows in three lanes retain five complete singleton execution plans" $ do
        forM_ lanes $ \lane -> do
          batch <- right (C.mkCanonicalNativeRlCohorts lane)
          C.nativeRlCohortBatchSubstrate batch @?= lane
          let cohorts = C.nativeRlCohortBatchPlans batch
          length cohorts @?= 43
          length (concatMap C.nativeRlCohortPlanChildren cohorts) @?= 215
          forM_ cohorts $ \cohort -> do
            let children = C.nativeRlCohortPlanChildren cohort
            fmap (C.nativeSeedIndexValue . C.nativeRlSeedPlanIndex) children @?= [0 .. 4]
            fmap C.nativeRlSeedPlanSeed children @?= [42 .. 46]
            forM_ children $ \child -> Native.nativeSingletonSubstrate (C.nativeRlSeedPlanSingleton child) @?= lane
    , testCase "index zero is the exact whole canonical parent and independently owns its seeded budget" $ do
        forM_ lanes $
          cohortsFor
            >=> mapM_
              ( \cohort -> do
                  parent <- parentOf cohort
                  let serving = C.nativeRlCohortServingChild cohort
                  C.nativeRlSeedPlanSingleton serving @?= parent
                  C.nativeSeedIndexValue (C.nativeRlSeedPlanIndex serving) @?= 0
                  C.nativeRlSeedPlanTrainingBudget serving
                    @?= projectionBudget (C.nativeRlCohortPlanProjection cohort)
                  Native.nativeSingletonPlanId parent @?= projectionId (C.nativeRlCohortPlanProjection cohort)
              )
    , testCase "every child preserves actual game quantities subject topic placement and version" $ do
        cohorts <- cohortsFor LinuxCPU
        forM_ cohorts $ \cohort -> do
          parent <- parentOf cohort
          forM_
            (C.nativeRlCohortPlanChildren cohort)
            (assertPreservedCommon parent . C.nativeRlSeedPlanSingleton)
    , testCase "all two hundred fifteen experiments artifacts and full PlanIds are injective per lane" $ do
        forM_ lanes $ \lane -> do
          cohorts <- cohortsFor lane
          let plans = fmap C.nativeRlSeedPlanSingleton (concatMap C.nativeRlCohortPlanChildren cohorts)
          artifacts <- traverse artifactOf plans
          length (nub artifacts) @?= 215
          length (nub (fmap Native.nativeSingletonExperiment plans)) @?= 215
          length (nub (fmap Native.nativeSingletonPlanId plans)) @?= 215
    , testCase "return and HER child schedules use their actual singleton seed and exact unchanged target" $ do
        forM_ lanes $ \lane -> do
          cohorts <- cohortsFor lane
          let children = concatMap C.nativeRlCohortPlanChildren cohorts
              returns = [(child, plan) | child <- children, Just plan <- [C.nativeRlSeedPlanCompiledReturn child]]
          length returns @?= 195
          forM_ returns $ \(child, recipe) -> do
            let training = ProductBudget.compiledRlTraining recipe
                budget = C.nativeRlSeedPlanTrainingBudget child
            toInteger (ProductBudget.trainingPlanSeed training) @?= toInteger (C.nativeRlSeedPlanSeed child)
            ProductBudget.trainingPlanExactTransitionTarget training
              @?= Just (Budget.trainingBudgetTargetUnits budget)
            ProductBudget.trainingPlanEpisodeBudgetFloor training
              @?= ProductBudget.productRlDefaultTrainingEpisodeFloor
            case ProductBudget.compiledRlSchedule recipe of
              Nothing -> assertFailure "native child has no concrete schedule"
              Just schedule ->
                ProductBudget.scheduleObservedEnvironmentSteps schedule @?= Budget.trainingBudgetTargetUnits budget
            ProductBudget.parseCompiledRlPlanTransport (ProductBudget.renderCompiledRlPlanTransport recipe)
              @?= Right recipe
    , testCase "auxiliary budget seeds change without confusing seedless specifications with actual plans" $ do
        cohorts <- cohortsFor LinuxCPU
        forM_ cohorts $ \cohort -> do
          let declared = projectionBudget (C.nativeRlCohortPlanProjection cohort)
          seedless <-
            right
              ( Budget.mkTrainingBudget
                  (Budget.trainingBudgetKind declared)
                  (Budget.trainingBudgetTargetUnits declared)
                  Nothing
              )
          forM_ (C.nativeRlCohortPlanChildren cohort) $ \child -> do
            let actual = C.nativeRlSeedPlanTrainingBudget child
            Budget.trainingBudgetKind actual @?= Budget.trainingBudgetKind seedless
            Budget.trainingBudgetTargetUnits actual @?= Budget.trainingBudgetTargetUnits seedless
            Budget.trainingBudgetSeed actual @?= Just (C.nativeRlSeedPlanSeed child)
            assertBool "seedless budget falsely equals actual singleton budget" (actual /= seedless)
    , testCase
        "AlphaZero children retain all four full game workloads and their distinct outer identities"
        $ do
          cohorts <- cohortsFor LinuxCPU
          let children = concatMap C.nativeRlCohortPlanChildren cohorts
              arenas = [(child, plan) | child <- children, Just plan <- [C.nativeRlSeedPlanAlphaZero child]]
          length arenas @?= 20
          sort (nub [Workload.renderAlphaZeroGame (Workload.alphaZeroPlanGame p) | (_, p) <- arenas])
            @?= ["connect4", "gomoku", "hex", "othello"]
          forM_ arenas $ \(child, plan) -> do
            let singleton = C.nativeRlSeedPlanSingleton child
            Native.nativeSingletonPlanId singleton @?= Workload.alphaZeroPlanId plan
            Native.nativeSingletonCommonPlanId singleton @?= Plan.runPlanId (Workload.alphaZeroPlanRunPlan plan)
            assertBool
              "game outer PlanId was discarded"
              (Native.nativeSingletonPlanId singleton /= Native.nativeSingletonCommonPlanId singleton)
            C.nativeRlSeedPlanCompiledReturn child @?= Nothing
    , testCase "the renderer binds full row metadata exact metric words and complete parent transport" $ do
        cohort <- cohortFor LinuxCPU "TRPO/cartpole"
        parent <- parentOf cohort
        fields <- right (readFields (C.nativeRlCohortPlanTransport cohort))
        let row = C.nativeRlCohortPlanRow cohort
            bar = Matrix.convergenceBar row
        field "canonical-row.row-id" fields >>= (@?= Encoding.encodeUtf8 (Matrix.rowId row))
        field "canonical-row.experiment-config-path" fields
          >>= (@?= Encoding.encodeUtf8 (Matrix.experimentConfig row))
        field "canonical-row.convergence-bar.target-bits" fields
          >>= (@?= Encoding.encodeUtf8 (bitsText (Convergence.convergenceLiteratureTarget bar)))
        field "parent-projection.convergence-bar.slack-bits" fields
          >>= (@?= Encoding.encodeUtf8 (bitsText (Convergence.convergenceSlack bar)))
        field "parent-projection.convergence-bar.threshold-bits" fields
          >>= (@?= Encoding.encodeUtf8 (bitsText (Convergence.convergenceThreshold bar)))
        field "parent-projection.resolved-plan" fields
          >>= (@?= Encoding.encodeUtf8 (Native.renderNativeSingletonPlan parent))
        field "parent-projection.command.count" fields >>= (@?= "5")
        field "canonical-row.architecture-features.count" fields >>= (@?= "0")
    , testCase "every emitted data identity matches independent salted SHA256 of the exact renderer bytes" $ do
        forM_ lanes $
          cohortsFor
            >=> mapM_
              ( \cohort -> do
                  let bytes = C.nativeRlCohortPlanTransport cohort
                      expected = hex (SHA256.hash ("jitml-plan-id-v1\NUL" <> bytes))
                  Plan.planIdText (C.nativeRlCohortPlanId cohort) @?= expected
                  _ <- right (Plan.refinePlanIdText expected)
                  pure ()
              )
    , testCase
        "all canonical renderer outputs fit frozen limits and carry exactly five complete child transports"
        $ do
          forM_ lanes $
            cohortsFor
              >=> mapM_
                ( \cohort -> do
                    let bytes = C.nativeRlCohortPlanTransport cohort
                    assertBool "renderer exceeds1MiB" (BS.length bytes <= 1048576)
                    fields <- right (readFields bytes)
                    assertBool "renderer exceeds512 fields" (length fields <= 512)
                    length (nub (fmap fst fields)) @?= length fields
                    assertBool
                      "a field name exceeds its UTF8 bound"
                      (all ((<= 128) . BS.length . Encoding.encodeUtf8 . fst) fields)
                    field "child-count" fields >>= (@?= "5")
                    forM_ (C.nativeRlCohortPlanChildren cohort) $ \child -> do
                      let key =
                            "child."
                              <> Text.pack (show (C.nativeSeedIndexValue (C.nativeRlSeedPlanIndex child)))
                              <> ".complete-singleton-transport"
                      observed <- field key fields
                      observed
                        @?= Encoding.encodeUtf8 (Native.renderNativeSingletonPlan (C.nativeRlSeedPlanSingleton child))
                      assertBool "lower complete transport exceeds32768" (BS.length observed <= 32768)
                )
    , testCase "correct row and unchanged PlanId cannot hide substituted integration or demo metadata" $ do
        original <- rowFor "PPO/cartpole"
        canonical <- project LinuxCPU original
        forM_
          [ original {Matrix.integrationTest = "different-live-route"}
          , original {Matrix.e2eTest = "different-e2e-route"}
          , original {Matrix.demoPanel = "different-panel"}
          ]
          $ \mutant -> do
            supplied <- project LinuxCPU mutant
            projectionId supplied @?= projectionId canonical
            leftContaining "full canonical projection differs" (C.mkNativeRlCohortPlan supplied)
    , testCase "a successfully projected alternate config path cannot become canonical cohort data" $ do
        original <- rowFor "DQN/cartpole"
        supplied <-
          project LinuxCPU (original {Matrix.experimentConfig = "experiments/alternate-canonical-name.dhall"})
        leftContaining "full canonical projection differs" (C.mkNativeRlCohortPlan supplied)
    , testCase "an independently valid changed bar cannot replace the frozen canonical row" $ do
        original <- rowFor "TRPO/cartpole"
        let bar = Matrix.convergenceBar original
            changed =
              bar
                { Convergence.convergenceLiteratureTarget = Convergence.convergenceLiteratureTarget bar + 1
                , Convergence.convergenceThreshold = Convergence.convergenceThreshold bar + 1
                }
        supplied <- project LinuxCPU (original {Matrix.convergenceBar = changed})
        leftContaining "full canonical projection differs" (C.mkNativeRlCohortPlan supplied)
    , testCase "supervised and tuning projections reject without manufacturing a native workload" $ do
        forM_
          [row | row <- Matrix.allProductRows, Matrix.family row `elem` [Matrix.Supervised, Matrix.Tuning]]
          $ \row -> do
            supplied <- project LinuxCPU row
            leftContaining "non-native ProductRows" (C.mkNativeRlCohortPlan supplied)
    , testCase "batch refinement rejects missing and duplicated canonical cohorts" $ do
        cohorts <- cohortsFor LinuxCPU
        case cohorts of
          firstCohort : rest -> do
            leftContaining "exactly43" (C.refineNativeRlCohortBatch LinuxCPU rest)
            leftContaining
              "row order or membership"
              (C.refineNativeRlCohortBatch LinuxCPU (firstCohort : firstCohort : drop 1 rest))
          [] -> assertFailure "actual canonical cohort pool empty"
    , testCase "batch refinement rejects reordered rows and foreign lane children" $ do
        cohorts <- cohortsFor LinuxCPU
        leftContaining "row order or membership" (C.refineNativeRlCohortBatch LinuxCPU (reverse cohorts))
        otherLaneCohorts <- cohortsFor AppleSilicon
        leftContaining "child lane differs" (C.refineNativeRlCohortBatch LinuxCPU otherLaneCohorts)
    , testCase "public arithmetic data helper accepts exact Int boundary and rejects one beyond" $ do
        let boundary = toInteger (maxBound :: Int)
            base = fromInteger (boundary - 104729) :: Word64
        headroom <- right (C.checkedNativeSeedHeadroom base [("actual-HER-eval", 104729)])
        C.nativeSeedHeadroomMaximum headroom @?= boundary
        leftContaining
          "actual Int range"
          (C.checkedNativeSeedHeadroom (base + 1) [("actual-HER-eval", 104729)])
        _ <- right (C.checkedNativeSeedHeadroom (fromInteger boundary) [("initial", 0)])
        leftContaining "actual Int range" (C.checkedNativeSeedHeadroom maxBound [("initial", 0)])
    , testCase "arithmetic helper rejects negative empty duplicate and excessive offset data" $ do
        leftContaining "negative" (C.checkedNativeSeedHeadroom 42 [("bad", -1)])
        leftContaining "1..32" (C.checkedNativeSeedHeadroom 42 [])
        leftContaining "empty" (C.checkedNativeSeedHeadroom 42 [("", 0)])
        leftContaining "not injective" (C.checkedNativeSeedHeadroom 42 [("same", 0), ("same", 1)])
        leftContaining
          "1..32"
          (C.checkedNativeSeedHeadroom 42 [(Text.pack (show i), 0) | i <- [0 :: Int .. 32]])
    , testCase "all actual trainer seed families include HER evaluation and continuous critic offsets" $ do
        cohorts <- cohortsFor LinuxCPU
        forM_ cohorts $ \cohort -> forM_ (C.nativeRlCohortPlanChildren cohort) $ \child ->
          case C.nativeRlSeedPlanCompiledReturn child of
            Nothing -> pure ()
            Just recipe -> do
              let trainer = ProductBudget.compiledRlTrainerKind recipe
                  expected
                    | trainer == "ars" = 0
                    | trainer == "her" = 104729
                    | trainer `elem` ["ddpg", "td3", "sac", "crossq", "tqc"] = 202
                    | otherwise = 1
                  headroom = C.nativeRlSeedPlanHeadroom child
              C.nativeSeedHeadroomBase headroom @?= C.nativeRlSeedPlanSeed child
              C.nativeSeedHeadroomMaximum headroom @?= toInteger (C.nativeRlSeedPlanSeed child) + expected
              assertBool
                "every reported sum must equal actual seed plus offset"
                ( all
                    (\(_, offset, actual) -> actual == toInteger (C.nativeRlSeedPlanSeed child) + offset)
                    (C.nativeSeedHeadroomOffsets headroom)
                )
    , testCase "AlphaZero actual nested generation and arena seed expressions are separately retained" $ do
        cohorts <- cohortsFor LinuxCPU
        forM_ (concatMap C.nativeRlCohortPlanChildren cohorts) $ \child -> case C.nativeRlSeedPlanAlphaZero child of
          Nothing -> pure ()
          Just plan -> do
            let q = toInteger . Plan.quantityValue
                g = (q (Workload.alphaZeroPlanGenerations plan) - 1) * 7919
                j = q (Workload.alphaZeroPlanSelfPlayGames plan) - 1
                p = (q (Workload.alphaZeroPlanMaxPlies plan) - 1) * 7919
                a = (q (Workload.alphaZeroPlanArenaGames plan) - 1) * 1009
                actuals =
                  [ (name, offset) | (name, offset, _) <- C.nativeSeedHeadroomOffsets (C.nativeRlSeedPlanHeadroom child)
                  ]
            lookup "generation-product" actuals @?= Just g
            lookup "ply-product" actuals @?= Just p
            lookup "self-play-MCTS" actuals @?= Just (g + j + p)
            lookup "arena-MCTS" actuals @?= Just (7919 + a + p)
            let edge = toInteger (maxBound :: Int) - (7919 + a + p)
            _ <- right (C.checkedNativeSeedHeadroom (fromInteger edge) [("actual-arena", 7919 + a + p)])
            leftContaining
              "actual Int range"
              (C.checkedNativeSeedHeadroom (fromInteger (edge + 1)) [("actual-arena", 7919 + a + p)])
    , testCase
        "one actual supplied parent invocation associates every prescribed child without replacement"
        $ do
          cohorts <- cohortsFor LinuxCPU
          forM_ cohorts $ \cohort -> do
            parent <- parentOf cohort
            let row = Matrix.rowId (C.nativeRlCohortPlanRow cohort)
            invocation <- invocationFor row parent
            associations <- forM C.nativeSeedIndices $ \index -> do
              association <- right (C.nativeRlSeedAssociation cohort invocation index)
              Association.nativeAssociationInvocation association @?= invocation
              Association.nativeAssociationParent association @?= parent
              Association.nativeAssociationOrdinal association @?= C.nativeSeedIndexValue index
              pure association
            length (nub (fmap Association.nativeAssociationDigest associations)) @?= 5
    , testCase "an auxiliary invocation cannot impersonate the unchanged parent association" $ do
        cohort <- cohortFor LinuxCPU "connect4"
        let row = Matrix.rowId (C.nativeRlCohortPlanRow cohort)
        case C.nativeRlCohortPlanChildren cohort of
          _ : auxiliary : _ -> do
            invocation <- invocationFor row (C.nativeRlSeedPlanSingleton auxiliary)
            leftContaining
              "different parent plan"
              (C.nativeRlSeedAssociation cohort invocation (C.nativeRlSeedPlanIndex auxiliary))
          _ -> assertFailure "actual native five-child cohort malformed"
    , testCase "association rejects wrong row and lane while keeping full AlphaZero parent identity" $ do
        cohort <- cohortFor LinuxCPU "connect4"
        parent <- parentOf cohort
        case C.nativeSeedIndices of
          index : _ -> do
            wrongRow <- invocationFor "different-row" parent
            leftContaining "row differs" (C.nativeRlSeedAssociation cohort wrongRow index)
            wrongLane <-
              right
                ( Budget.mkProductScenarioInvocation
                    "native-cohort-data"
                    "connect4"
                    (Native.nativeSingletonPlanId parent)
                    AppleSilicon
                    (Text.replicate 64 "a")
                    (Text.replicate 64 "b")
                    (Text.replicate 64 "c")
                )
            leftContaining "lane differs" (C.nativeRlSeedAssociation cohort wrongLane index)
            commonId <-
              right
                ( Budget.mkProductScenarioInvocation
                    "native-cohort-data"
                    "connect4"
                    (Native.nativeSingletonCommonPlanId parent)
                    LinuxCPU
                    (Text.replicate 64 "a")
                    (Text.replicate 64 "b")
                    (Text.replicate 64 "c")
                )
            leftContaining "different parent plan" (C.nativeRlSeedAssociation cohort commonId index)
          [] -> assertFailure "prescribed indices unexpectedly empty"
    , testCase
        "rebuilding canonical plan data is byte stable while lane and row identities remain distinct"
        $ do
          allCohorts <- fmap concat (traverse cohortsFor lanes)
          length allCohorts @?= 129
          length (nub (fmap C.nativeRlCohortPlanId allCohorts)) @?= 129
          forM_ allCohorts $ \cohort -> do
            rebuilt <- right (C.mkNativeRlCohortPlan (C.nativeRlCohortPlanProjection cohort))
            C.nativeRlCohortPlanTransport rebuilt @?= C.nativeRlCohortPlanTransport cohort
            C.nativeRlCohortPlanId rebuilt @?= C.nativeRlCohortPlanId cohort
    ]
