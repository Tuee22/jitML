{-# LANGUAGE OverloadedStrings #-}

-- Explicit numerical callback fixtures over actual bit-flip primitives. These
-- callbacks do not claim real providers, trained networks or qualification.
module NativeHerEvaluation (nativeHerEvaluationTests) where

import Control.Exception (AsyncException (..), Exception, throwIO, try)
import Control.Monad (forM_)
import Data.Bits (bit, testBit, xor)
import Data.IORef (modifyIORef', newIORef, readIORef, writeIORef)
import Data.List (find)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)
import GHC.Float (castDoubleToWord64)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Numerics.Mlp (MlpForward (..), MlpParams (..), MlpShape (..), mlpParamsToFlat)
import JitML.Numerics.MlpDevice (MlpDevice (..), pureReferenceMlpDevice)
import JitML.RL.Algorithms.HerTrainer qualified as Her
import JitML.RL.NativeHerEvaluation qualified as E
import JitML.RL.NativeHerReferences qualified as R

right :: (Show error) => Either error value -> IO value
right result = case result of
  Right value -> pure value
  Left reason -> assertFailure (show reason) >> fail "unreachable"

-- Small architecture, never a claimed canonical learner or training budget.
config :: Her.HerTrainConfig
config = Her.defaultHerTrainConfig {Her.herHiddenUnits = 2}

parameters :: MlpParams
parameters = Her.initialHerParams config

schedule :: IO R.NativeHerGoalSchedule
schedule = right R.canonicalNativeHerReferenceSpec >>= right . R.generateNativeHerGoalSchedule

rawForward :: VU.Vector Double -> VU.Vector Double -> MlpForward
rawForward input = MlpForward input VU.empty VU.empty

outputDevice :: (VU.Vector Double -> VU.Vector Double) -> MlpDevice
outputDevice output =
  pureReferenceMlpDevice
    { mlpdForward = \_ input -> pure (Right (rawForward input (output input)))
    }

-- State-dependent diagnostic Q coordinates, not a learned network.
greedyDifference :: VU.Vector Double -> VU.Vector Double
greedyDifference input =
  VU.zipWith
    (\state goal -> if state /= goal then 1 else 0)
    (VU.take 6 input)
    (VU.drop 6 input)

greedyDevice :: MlpDevice
greedyDevice = outputDevice greedyDifference

constantDevice :: Int -> MlpDevice
constantDevice action = outputDevice (const (VU.generate 6 (\index -> if index == action then 1 else 0)))

bitsOf :: VU.Vector Double -> [Int]
bitsOf vector = [index | (index, value) <- zip [0 ..] (VU.toList vector), value == 1]

flatBits :: MlpParams -> [Word64]
flatBits = map castDoubleToWord64 . mlpParamsToFlat

expectedOutcome :: R.RawNativeHerGoalCase -> IO R.NativeHerReferenceOutcome
expectedOutcome one = do
  let actions = bitsOf (R.rawNativeHerGoal one)
      full = actions <> replicate (6 - length actions) 0
  outcome <- right (R.evaluateHerSequenceFixture (R.rawNativeHerGoal one) full)
  pure (outcome {R.nativeHerOutcomeCaseId = R.rawNativeHerCaseId one})

checkComplete :: R.NativeHerGoalSchedule -> E.RawNativeHerEvaluation -> Assertion
checkComplete supplied observed = do
  E.nativeHerEvaluationStatus observed @?= E.NativeHerEvaluationComplete
  E.nativeHerEvaluationSchedule observed @?= supplied
  E.nativeHerEvaluationFailedProgress observed @?= Nothing
  map R.nativeHerOutcomeCaseId (E.nativeHerEvaluationOutcomes observed) @?= [0 .. 19]
  map R.nativeHerOutcomeGoal (E.nativeHerEvaluationOutcomes observed)
    @?= map R.rawNativeHerGoal (R.nativeHerScheduleCases supplied)
  let work = sum (map (toInteger . R.nativeHerOutcomeSteps) (E.nativeHerEvaluationOutcomes observed))
  E.nativeHerEvaluationWork observed @?= E.NativeHerCompleteWork work
  assertBool
    "canonical twenty nonzero goals bound complete transition work"
    (work >= 20 && work <= 120)
  E.nativeHerObservedForwardCalls observed @?= work

-- Fail in a later case after one actual successful flip. The fixture chooses
-- only a fault-injection location from domain shape, never a training result.
assertCallbackFailure
  :: E.NativeHerEvaluationFailureKind
  -> (Text -> Assertion)
  -> (MlpParams -> VU.Vector Double -> IO (Either Text MlpForward))
  -> Assertion
assertCallbackFailure kind checkMessage failure = do
  supplied <- schedule
  let cases = R.nativeHerScheduleCases supplied
  target <- case find (\one -> R.rawNativeHerCaseId one > 0 && length (bitsOf (R.rawNativeHerGoal one)) >= 2) cases of
    Nothing ->
      assertFailure "frozen schedule lacks the required later multi-flip injection case"
        >> fail "unreachable"
    Just one -> pure one
  let caseId = R.rawNativeHerCaseId target
      prefix = take caseId cases
      prefixSteps = sum (map (length . bitsOf . R.rawNativeHerGoal) prefix)
      trigger = prefixSteps + 2
  calls <- newIORef (0 :: Int)
  let device =
        greedyDevice
          { mlpdForward = \params input -> do
              modifyIORef' calls (+ 1)
              index <- readIORef calls
              if index == trigger then failure params input else mlpdForward greedyDevice params input
          }
  actual <- E.evaluateNativeHerPolicy device supplied config parameters
  expected <- traverse expectedOutcome prefix
  E.nativeHerEvaluationOutcomes actual @?= expected
  case E.nativeHerEvaluationStatus actual of
    E.NativeHerEvaluationFailed index actualKind message -> do
      index @?= caseId
      actualKind @?= kind
      checkMessage message
    status -> assertFailure ("expected actual later callback failure, got " <> show status)
  E.nativeHerEvaluationWork actual @?= E.NativeHerFailedWork (toInteger prefixSteps) 1 (Just 1)
  readIORef calls >>= (@?= trigger)
  E.nativeHerObservedForwardCalls actual @?= toInteger trigger
  case E.nativeHerEvaluationFailedProgress actual of
    Nothing -> assertFailure "actual failed case progress was discarded"
    Just progress -> do
      E.nativeHerProgressCaseId progress @?= caseId
      E.nativeHerProgressGoal progress @?= R.rawNativeHerGoal target
      E.nativeHerProgressTransitions progress @?= 1
      length (E.nativeHerProgressActions progress) @?= 1
      let stateCode = foldl' (\state action -> state `xor` bit action) (0 :: Int) (E.nativeHerProgressActions progress)
      E.nativeHerProgressState progress
        @?= VU.generate 6 (\index -> if testBit stateCode index then 1 else 0)
  let current = filter ((== caseId) . E.nativeHerForwardCaseId) (E.nativeHerEvaluationForwards actual)
  map E.nativeHerForwardCallIndex current @?= [0, 1]
  case reverse current of
    observed : _ -> do
      flatBits (E.nativeHerForwardParameters observed) @?= flatBits parameters
      VU.drop 6 (E.nativeHerForwardInput observed) @?= R.rawNativeHerGoal target
      case (kind, E.nativeHerForwardOutcome observed) of
        (E.NativeHerDeviceRejected, E.NativeHerForwardReturned (Left reason)) -> reason @?= "explicit diagnostic Left"
        (E.NativeHerSynchronousException, E.NativeHerForwardException reason) -> checkMessage reason
        other -> assertFailure ("actual failed callback constructor differs: " <> show other)
    [] -> assertFailure "actual failed callback observation absent"
  assertBool
    "failed raw result is safely inspectable after returned-data forcing"
    (not (null (show actual)))

messageContains :: Text -> Text -> Assertion
messageContains expected actual = assertBool "specific actual callback failure reason" (expected `Text.isInfixOf` actual)

data FailingRenderer = FailingRenderer
instance Show FailingRenderer where
  show _ = error "fixture renderer failed"
instance Exception FailingRenderer

nativeHerEvaluationTests :: TestTree
nativeHerEvaluationTests =
  testGroup
    "learned HER policies on exact frozen goals"
    [ testCase "all twenty supplied fixed goals and duplicates reach the actual scalar device in order" $ do
        supplied <- schedule
        actual <- E.evaluateNativeHerPolicy greedyDevice supplied config parameters
        checkComplete supplied actual
        expected <- traverse expectedOutcome (R.nativeHerScheduleCases supplied)
        E.nativeHerEvaluationOutcomes actual @?= expected
        let forwards = E.nativeHerEvaluationForwards actual
        forM_ (R.nativeHerScheduleCases supplied) $ \one -> do
          let matching = filter ((== R.rawNativeHerCaseId one) . E.nativeHerForwardCaseId) forwards
          assertBool "every nonzero goal needs a real first forward" (not (null matching))
          forM_ matching $ \observed -> VU.drop 6 (E.nativeHerForwardInput observed) @?= R.rawNativeHerGoal one
          case matching of
            first : _ -> VU.take 6 (E.nativeHerForwardInput first) @?= VU.replicate 6 0
            [] -> assertFailure "actual first forward absent"
    , testCase "different policy-dependent success lengths never advance or replace a later fixed goal" $ do
        supplied <- schedule
        fast <- E.evaluateNativeHerPolicy greedyDevice supplied config parameters
        cycling <- E.evaluateNativeHerPolicy (constantDevice 0) supplied config parameters
        checkComplete supplied fast
        checkComplete supplied cycling
        map R.nativeHerOutcomeGoal (E.nativeHerEvaluationOutcomes fast)
          @?= map R.nativeHerOutcomeGoal (E.nativeHerEvaluationOutcomes cycling)
        assertBool
          "the diagnostic policies actually differ on physical evaluation lengths"
          ( map R.nativeHerOutcomeSteps (E.nativeHerEvaluationOutcomes fast)
              /= map R.nativeHerOutcomeSteps (E.nativeHerEvaluationOutcomes cycling)
          )
    , testCase
        "exact initialized supplied parameters are forwarded without backward update or witness calls"
        $ do
          supplied <- schedule
          forbidden <- newIORef ([] :: [Text])
          let reject :: Text -> IO (Either Text value)
              reject label = modifyIORef' forbidden (label :) >> pure (Left label)
              device =
                pureReferenceMlpDevice
                  { mlpdBackward = \_ _ _ -> reject "backward"
                  , mlpdForwardBatch = \_ _ -> reject "forward-batch"
                  , mlpdBatchGradient = \_ _ -> reject "gradient"
                  , mlpdInputGradientBatch = \_ _ -> reject "input-gradient"
                  , mlpdExecutionWitness = reject "witness"
                  }
          actual <- E.evaluateNativeHerPolicy device supplied config parameters
          checkComplete supplied actual
          flatBits (E.nativeHerEvaluationParameters actual) @?= flatBits parameters
          forM_ (E.nativeHerEvaluationForwards actual) $ \observed -> flatBits (E.nativeHerForwardParameters observed) @?= flatBits parameters
          readIORef forbidden >>= (@?= [])
    , testCase "supplied training seed epsilon and training counts cannot alter fixed greedy cases" $ do
        supplied <- schedule
        let other = config {Her.herSeed = 999, Her.herEpsilon = 1, Her.herEpisodes = 1}
        first <- E.evaluateNativeHerPolicy greedyDevice supplied config parameters
        second <- E.evaluateNativeHerPolicy greedyDevice supplied other parameters
        checkComplete supplied second
        E.nativeHerEvaluationOutcomes second @?= E.nativeHerEvaluationOutcomes first
        E.nativeHerEvaluationForwards second @?= E.nativeHerEvaluationForwards first
        E.nativeHerEvaluationConfig second @?= other
    , testCase "finite greedy ties choose the first action without a categorical or random fallback" $ do
        supplied <- schedule
        actual <-
          E.evaluateNativeHerPolicy (outputDevice (const (VU.replicate 6 7))) supplied config parameters
        checkComplete supplied actual
        assertBool
          "the first-index tie rule is used for every actual decision"
          (all (all (== 0) . R.nativeHerOutcomeConsumedActions) (E.nativeHerEvaluationOutcomes actual))
    , testCase "retained action traces replay through an independent integer XOR state oracle" $ do
        supplied <- schedule
        actual <- E.evaluateNativeHerPolicy pureReferenceMlpDevice supplied config parameters
        checkComplete supplied actual
        forM_ (E.nativeHerEvaluationOutcomes actual) $ \outcome -> do
          let code =
                foldl'
                  (\state action -> state `xor` bit action)
                  (0 :: Int)
                  (R.nativeHerOutcomeConsumedActions outcome)
              final = VU.generate 6 (\index -> if testBit code index then 1 else 0)
              distance =
                length
                  [ ()
                  | (left, goal) <- zip (VU.toList final) (VU.toList (R.nativeHerOutcomeGoal outcome))
                  , left /= goal
                  ]
          R.nativeHerOutcomeFinalState outcome @?= final
          R.nativeHerOutcomeHammingDistance outcome @?= distance
          R.nativeHerOutcomeNormalizedDistance outcome @?= fromIntegral distance / 6
          R.nativeHerOutcomeSteps outcome @?= length (R.nativeHerOutcomeConsumedActions outcome)
          R.nativeHerOutcomeTerminated outcome @?= (distance == 0)
    , testCase "early actual success stops immediately with exact Hamming work and no extra callback" $ do
        supplied <- schedule
        actual <- E.evaluateNativeHerPolicy greedyDevice supplied config parameters
        checkComplete supplied actual
        forM_ (E.nativeHerEvaluationOutcomes actual) $ \outcome -> do
          R.nativeHerOutcomeSuccess outcome @?= True
          R.nativeHerOutcomeSteps outcome @?= length (bitsOf (R.nativeHerOutcomeGoal outcome))
          R.nativeHerOutcomeHammingDistance outcome @?= 0
        assertBool
          "frozen cases exercise an actual early success"
          (any ((< 6) . R.nativeHerOutcomeSteps) (E.nativeHerEvaluationOutcomes actual))
    , testCase "success on the sixth move remains terminal and a missed six-step goal remains truncated" $ do
        supplied <- schedule
        let makePlan one =
              let needed = bitsOf (R.rawNativeHerGoal one)
               in if even (length needed)
                    then concat (replicate ((6 - length needed) `div` 2) [0, 0]) <> needed
                    else needed
        pending <- newIORef (map makePlan (R.nativeHerScheduleCases supplied))
        let scripted =
              greedyDevice
                { mlpdForward = \_ input -> do
                    remaining <- readIORef pending
                    case dropWhile null remaining of
                      [] -> assertFailure "scripted diagnostic exhausted its exact goal plans" >> fail "unreachable"
                      (action : rest) : later -> do
                        writeIORef pending (rest : later)
                        pure (Right (rawForward input (VU.generate 6 (\index -> if index == action then 1 else 0))))
                      [] : _ -> assertFailure "unreachable empty diagnostic plan" >> fail "unreachable"
                }
        completed <- E.evaluateNativeHerPolicy scripted supplied config parameters
        checkComplete supplied completed
        assertBool
          "actual frozen even-Hamming cases exercise success exactly at the horizon"
          ( any
              (\outcome -> R.nativeHerOutcomeSteps outcome == 6 && R.nativeHerOutcomeTerminated outcome)
              (E.nativeHerEvaluationOutcomes completed)
          )
        missed <- E.evaluateNativeHerPolicy (constantDevice 0) supplied config parameters
        checkComplete supplied missed
        assertBool
          "actual frozen goals exercise six-step truncation"
          ( any
              ( \outcome ->
                  R.nativeHerOutcomeSteps outcome == 6
                    && not (R.nativeHerOutcomeTerminated outcome)
                    && not (R.nativeHerOutcomeSuccess outcome)
              )
              (E.nativeHerEvaluationOutcomes missed)
          )
    , testCase "context and ABI dimension errors reject specifically before any callback" $ do
        supplied <- schedule
        calls <- newIORef (0 :: Int)
        let device =
              greedyDevice
                { mlpdForward = \p input -> modifyIORef' calls (+ 1) >> mlpdForward greedyDevice p input
                }
        forM_
          [ config {Her.herNumBits = 5}
          , config {Her.herHiddenUnits = 0}
          , config {Her.herHiddenUnits = maxBound}
          ]
          $ \bad -> do
            actual <- E.evaluateNativeHerPolicy device supplied bad parameters
            E.nativeHerEvaluationStatus actual
              @?= E.NativeHerEvaluationRejected
                E.NativeHerContextRejected
                "native HER policy dimensions differ from the fixed context or exceed the ABI"
            E.nativeHerEvaluationWork actual @?= E.NativeHerRejectedWork
            E.nativeHerEvaluationForwards actual @?= []
        readIORef calls >>= (@?= 0)
    , testCase "parameter shape and every tensor extent reject before device execution" $ do
        supplied <- schedule
        forM_
          [ parameters {paramShape = MlpShape 13 2 6}
          , parameters {paramW1 = VU.empty}
          , parameters {paramB1 = VU.empty}
          , parameters {paramW2 = VU.empty}
          , parameters {paramB2 = VU.empty}
          ]
          $ \bad -> do
            actual <-
              E.evaluateNativeHerPolicy
                ( greedyDevice
                    { mlpdForward = \_ _ -> assertFailure "invalid tensors reached the device" >> fail "unreachable"
                    }
                )
                supplied
                config
                bad
            E.nativeHerEvaluationStatus actual
              @?= E.NativeHerEvaluationRejected
                E.NativeHerContextRejected
                "native HER policy parameter tensors differ from the declared shape"
            E.nativeHerEvaluationForwards actual @?= []
    , testCase "NaN infinity and finite binary64 overflow reject while Float32 underflow remains valid" $ do
        supplied <- schedule
        forM_ [0 / 0, 1 / 0, 1e300] $ \value -> do
          let bad = parameters {paramB2 = VU.replicate 6 value}
          actual <- E.evaluateNativeHerPolicy greedyDevice supplied config bad
          E.nativeHerEvaluationStatus actual
            @?= E.NativeHerEvaluationRejected
              E.NativeHerContextRejected
              "native HER policy parameters are nonfinite or overflow the Float32 ABI"
          E.nativeHerEvaluationForwards actual @?= []
        let underflow = parameters {paramB2 = VU.replicate 6 1e-300}
        accepted <- E.evaluateNativeHerPolicy greedyDevice supplied config underflow
        checkComplete supplied accepted
        flatBits (E.nativeHerEvaluationParameters accepted) @?= flatBits underflow
    , testCase "malformed or nonfinite actual device outputs reject before an action is applied" $ do
        supplied <- schedule
        forM_
          [ VU.empty
          , VU.replicate 5 0
          , VU.replicate 7 0
          , VU.replicate 6 (0 / 0)
          , VU.replicate 6 (1 / 0)
          , VU.replicate 6 1e300
          ]
          $ \output -> do
            actual <- E.evaluateNativeHerPolicy (outputDevice (const output)) supplied config parameters
            E.nativeHerEvaluationStatus actual
              @?= E.NativeHerEvaluationFailed
                0
                E.NativeHerInvalidOutput
                "native HER device output has the wrong shape or is not finite Float32"
            E.nativeHerEvaluationWork actual @?= E.NativeHerFailedWork 0 0 (Just 0)
            E.nativeHerObservedForwardCalls actual @?= 1
            E.nativeHerEvaluationOutcomes actual @?= []
            fmap E.nativeHerProgressActions (E.nativeHerEvaluationFailedProgress actual) @?= Just []
    , testCase
        "actual later device Left retains exact completed cases and observed failed transition prefix"
        $ assertCallbackFailure
          E.NativeHerDeviceRejected
          (@?= "native HER device forward failed: explicit diagnostic Left")
          (\_ _ -> pure (Left "explicit diagnostic Left"))
    , testCase "actual synchronous callback exception preserves the same exact prefix without retry" $
        assertCallbackFailure
          E.NativeHerSynchronousException
          (messageContains "explicit diagnostic IO failure")
          (\_ _ -> throwIO (userError "explicit diagnostic IO failure"))
    , testCase "lazy callback outer Either is forced inside the synchronous boundary" $
        assertCallbackFailure
          E.NativeHerSynchronousException
          (messageContains "lazy HER outer Either")
          (\_ _ -> pure (error "lazy HER outer Either"))
    , testCase "lazy callback Left text cannot escape in retained raw failure data" $
        assertCallbackFailure
          E.NativeHerSynchronousException
          (messageContains "lazy HER Left text")
          (\_ _ -> pure (Left (error "lazy HER Left text")))
    , testCase "lazy callback Right forward and output coordinates cannot escape in retained raw data" $ do
        assertCallbackFailure
          E.NativeHerSynchronousException
          (messageContains "lazy HER Right forward")
          (\_ _ -> pure (Right (error "lazy HER Right forward")))
        assertCallbackFailure
          E.NativeHerSynchronousException
          (messageContains "lazy HER output coordinate")
          ( \_ input ->
              pure (Right (rawForward input (VU.fromList [0, 0, 0, 0, 0, error "lazy HER output coordinate"])))
          )
    , testCase "async cancellation propagates without a fabricated raw failure or retry" $ do
        supplied <- schedule
        calls <- newIORef (0 :: Int)
        let device = greedyDevice {mlpdForward = \_ _ -> modifyIORef' calls (+ 1) >> throwIO ThreadKilled}
        attempted <-
          try (E.evaluateNativeHerPolicy device supplied config parameters)
            :: IO (Either AsyncException E.RawNativeHerEvaluation)
        case attempted of
          Left ThreadKilled -> pure ()
          other -> assertFailure ("async cancellation was swallowed: " <> show other)
        readIORef calls >>= (@?= 1)
    , testCase "a synchronous exception renderer failure retains a truthful diagnostic fallback" $
        assertCallbackFailure
          E.NativeHerSynchronousException
          (@?= "synchronous exception rendering failed")
          (\_ _ -> throwIO FailingRenderer)
    , testCase "two supplied parameter snapshots remain distinct data over the same exact goal schedule" $ do
        supplied <- schedule
        let different = parameters {paramB2 = VU.generate 6 fromIntegral}
        first <- E.evaluateNativeHerPolicy pureReferenceMlpDevice supplied config parameters
        second <- E.evaluateNativeHerPolicy pureReferenceMlpDevice supplied config different
        checkComplete supplied first
        checkComplete supplied second
        flatBits (E.nativeHerEvaluationParameters first) @?= flatBits parameters
        flatBits (E.nativeHerEvaluationParameters second) @?= flatBits different
        assertBool "snapshot fixture actually differs" (flatBits parameters /= flatBits different)
        forM_ (E.nativeHerEvaluationForwards second) $ \observed -> flatBits (E.nativeHerForwardParameters observed) @?= flatBits different
    ]
