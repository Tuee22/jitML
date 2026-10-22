{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- Canonical schedules run in full through explicitly OFFLINE shape-correct
-- zero-output/zero-gradient callbacks. These are phase/data controls, never
-- numerical-equivalence, provider, learning, origin or qualification evidence.
module NativePreparedNeuralAttempt (nativePreparedNeuralAttemptTests) where

import Control.Concurrent (forkFinally)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import Control.Exception (AsyncException (..), SomeException, throwIO, try)
import Control.Monad (forM, forM_, void)
import Data.IORef (IORef, atomicModifyIORef', modifyIORef', newIORef, readIORef, writeIORef)
import Data.List (find)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)
import GHC.Float (castDoubleToWord64)
import Test.Tasty (TestTree, testGroup, withResource)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Numerics.Mlp qualified as Mlp
import JitML.Numerics.MlpDevice (MlpDevice (..), pureReferenceMlpDevice)
import JitML.Plan.NativeSingletonPlan qualified as Native
import JitML.Product.Convergence qualified as Convergence
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.NativePreparedNeuralAttempt qualified as High
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.RL.Algorithms.Common qualified as Common
import JitML.RL.Algorithms.ContinuousTrainer qualified as Continuous
import JitML.RL.Algorithms.PpoTrainer qualified as Ppo
import JitML.RL.NativeHerEvaluation qualified as Her
import JitML.RL.NativeHerReferences qualified as HerRef
import JitML.RL.NativeReturnEvaluation qualified as Return
import JitML.RL.NativeReturnReferences qualified as ReturnRef
import JitML.RL.PreparedNeuralAttempt qualified as Low
import JitML.RL.ProductBudget qualified as Budget
import JitML.RL.TrainerObservation qualified as Observation
import JitML.Substrate (Substrate (..))
import JitML.Training.Budget qualified as TrainingBudget

right :: (Show error) => Either error value -> IO value
right result = case result of
  Right value -> pure value
  Left reason -> assertFailure (show reason) >> fail "unreachable"

selection :: Either High.NativeAttemptFailure value -> IO value
selection result = case result of
  Right value -> pure value
  Left failure -> failed failure

failed :: High.NativeAttemptFailure -> IO value
failed failure = assertFailure (Text.unpack (High.nativeFailureDetail failure)) >> fail "unreachable"

prepared :: High.NativePreparationResult -> IO High.NativePrepared
prepared result = case result of
  High.NativePreparationReady value -> pure value
  High.NativePreparationFailed failure -> failed failure

initialized :: High.NativeInitializationResult -> IO High.NativeEffectivePrepared
initialized result = case result of
  High.NativeInitializationReady value -> pure value
  High.NativeInitializationFailed failure -> failed failure

ready :: High.NativeInitialEvaluationResult -> IO High.NativeReadyToTrain
ready result = case result of
  High.NativeInitialEvaluationReady value -> pure value
  High.NativeInitialEvaluationFailed failure -> failed failure

pending :: High.NativeTrainingResult -> IO High.NativePendingFinalEvaluation
pending result = case result of
  High.NativeTrainingReturned value -> pure value
  High.NativeTrainingFailed failure -> failed failure
  High.NativeTrainingReturnedButUnmaterializable failure -> failed failure
  High.NativeTrainingBindingFailed _ failure -> failed failure

completed :: High.NativeFinalEvaluationResult -> IO High.NativeEvaluatedData
completed result = case result of
  High.NativeFinalEvaluationComplete value -> pure value
  High.NativeFinalEvaluationFailed _ _ failure -> failed failure

batch :: Substrate -> IO Cohort.NativeRlCohortBatch
batch = right . Cohort.mkCanonicalNativeRlCohorts

indexZero :: IO Cohort.NativeSeedIndex
indexZero = case Cohort.nativeSeedIndices of
  zero : _ -> pure zero
  [] -> assertFailure "canonical seed-index inventory is empty" >> fail "unreachable"

child :: Text -> IO High.NativeNeuralChildData
child row = do
  whole <- batch LinuxCPU
  selected <- selection (High.selectNativeNeuralRowData whole row)
  zero <- indexZero
  selection (High.selectNativeNeuralChildData selected zero)

bits :: Mlp.MlpParams -> [Word64]
bits = map castDoubleToWord64 . Mlp.mlpParamsToFlat

initialBits, finalBits :: Observation.ReturnedPolicy -> [Word64]
initialBits = map castDoubleToWord64 . Observation.returnedInitialWeights
finalBits = map castDoubleToWord64 . Observation.returnedFinalWeights

rawStatistics :: Observation.ReturnedPolicy -> Int
rawStatistics policy = case policy of
  Observation.ReturnedOnPolicy raw -> length (Common.rawTrainerStats raw)
  Observation.ReturnedDqn raw -> length (Common.rawTrainerStats raw)
  Observation.ReturnedQrDqn raw -> length (Common.rawTrainerStats raw)
  Observation.ReturnedContinuous raw -> length (Common.rawTrainerStats raw)
  Observation.ReturnedHer raw -> length (Common.rawTrainerStats raw)
  Observation.ReturnedArs raw -> length (Common.rawTrainerStats raw)

-- Only a bounded summary is retained per phase/operation/shape, rather than an
-- event allocation or parameter traversal on every canonical callback.
data Phase = Preparing | Initializing | InitialScoring | Training | FinalScoring
  deriving stock (Eq, Show)
data Operation = ScalarForward | BatchForward | Backward | BatchGradient | InputGradient | Witness
  deriving stock (Eq, Show)
data Trace = Trace
  { traceTotal :: !Integer
  , traceCounts :: ![(Phase, Operation, Integer)]
  , traceFirst :: ![(Phase, Operation, Mlp.MlpShape, Mlp.MlpParams)]
  , traceMarks :: ![(Text, Integer)]
  }

data ScalarFault
  = ScalarLeft
  | ScalarThrow
  | ScalarLazyOuter
  | ScalarLazyLeft
  | ScalarLazyForward
  | ScalarWrongShape
  | ScalarNonfinite
  | ScalarAsync
  deriving stock (Eq, Show)
data Fault
  = Clear
  | FailProbe
  | ThrowProbe
  | FailScalarAfter Integer ScalarFault
  | FailGradient
  | ThrowGradient
  | CancelGradient

data Control = Control
  { controlPhase :: IORef Phase
  , controlTrace :: IORef Trace
  , controlFault :: IORef Fault
  , controlZeroGradients :: IORef [(Mlp.MlpShape, Mlp.MlpGradient)]
  }

newControl :: IO Control
newControl = Control <$> newIORef Preparing <*> newIORef (Trace 0 [] [] []) <*> newIORef Clear <*> newIORef []

enter :: Control -> Phase -> IO ()
enter control = writeIORef (controlPhase control)

mark :: Control -> Text -> IO ()
mark control label = modifyIORef' (controlTrace control) $ \trace ->
  trace {traceMarks = traceMarks trace <> [(label, traceTotal trace)]}

count :: Phase -> Operation -> Trace -> Integer
count phase operation trace = sum [n | (p, op, n) <- traceCounts trace, p == phase, op == operation]

record :: Control -> Operation -> Maybe Mlp.MlpParams -> IO Integer
record control operation params = do
  phase <- readIORef (controlPhase control)
  atomicModifyIORef' (controlTrace control) $ \trace ->
    let ordinal = count phase operation trace + 1
        add [] = [(phase, operation, ordinal)]
        add ((p, op, n) : rest)
          | p == phase && op == operation = (p, op, ordinal) : rest
          | otherwise = (p, op, n) : add rest
        first = case params of
          Nothing -> traceFirst trace
          Just actual ->
            let shape = Mlp.paramShape actual
             in if any (\(p, op, s, _) -> p == phase && op == operation && s == shape) (traceFirst trace)
                  then traceFirst trace
                  else (phase, operation, shape, actual) : traceFirst trace
        updated =
          trace {traceTotal = traceTotal trace + 1, traceCounts = add (traceCounts trace), traceFirst = first}
     in (updated, ordinal)

firstParams :: Phase -> Operation -> Mlp.MlpShape -> Trace -> Maybe Mlp.MlpParams
firstParams phase operation shape trace = do
  (_, _, _, actual) <-
    find (\(p, op, s, _) -> p == phase && op == operation && s == shape) (traceFirst trace)
  pure actual

zeroGradient :: Control -> Mlp.MlpParams -> IO Mlp.MlpGradient
zeroGradient control params = do
  let shape = Mlp.paramShape params
  cached <- readIORef (controlZeroGradients control)
  case lookup shape cached of
    Just value -> pure value
    Nothing -> do
      let value = Mlp.mlpZeroGradient shape
      modifyIORef' (controlZeroGradients control) ((shape, value) :)
      pure value

validInput :: Mlp.MlpParams -> VU.Vector Double -> Bool
validInput params input = VU.length input == Mlp.mlpInputs (Mlp.paramShape params)

validBatch :: Mlp.MlpParams -> [(VU.Vector Double, VU.Vector Double)] -> Bool
validBatch params =
  all
    ( \(input, upstream) -> validInput params input && VU.length upstream == Mlp.mlpOutputs (Mlp.paramShape params)
    )

zeroForward :: Mlp.MlpParams -> VU.Vector Double -> Mlp.MlpForward
zeroForward params input =
  let shape = Mlp.paramShape params
   in Mlp.MlpForward
        input
        (VU.replicate (Mlp.mlpHidden shape) 0)
        (VU.replicate (Mlp.mlpHidden shape) 0)
        (VU.replicate (Mlp.mlpOutputs shape) 0)

scalarFailure :: ScalarFault -> Mlp.MlpParams -> VU.Vector Double -> IO (Either Text Mlp.MlpForward)
scalarFailure fault params input = case fault of
  ScalarLeft -> pure (Left "explicit offline scalar Left")
  ScalarThrow -> throwIO (userError "explicit offline scalar exception")
  ScalarLazyOuter -> pure (error "lazy offline scalar Either")
  ScalarLazyLeft -> pure (Left (error "lazy offline scalar Left"))
  ScalarLazyForward -> pure (Right (error "lazy offline scalar forward"))
  ScalarWrongShape -> pure (Right ((zeroForward params input) {Mlp.forwardOutput = VU.empty}))
  ScalarNonfinite ->
    pure
      ( Right
          ( (zeroForward params input)
              { Mlp.forwardOutput = VU.replicate (Mlp.mlpOutputs (Mlp.paramShape params)) (0 / 0)
              }
          )
      )
  ScalarAsync -> throwIO ThreadKilled

-- Existing callback seam only. Every successful fixture output/gradient has its
-- actual requested shape; zero numerical values are intentional offline data.
-- The warm SAC math is not intercepted by these callbacks.
device :: Control -> MlpDevice
device control =
  pureReferenceMlpDevice
    { mlpdForward = \params input -> do
        ordinal <- record control ScalarForward (Just params)
        fault <- readIORef (controlFault control)
        case fault of
          FailScalarAfter limit actual | ordinal > limit -> scalarFailure actual params input
          _ ->
            pure
              ( if validInput params input
                  then Right (zeroForward params input)
                  else Left "offline scalar shape differs"
              )
    , mlpdForwardBatch = \params inputs -> do
        _ <- record control BatchForward (Just params)
        fault <- readIORef (controlFault control)
        case fault of
          FailProbe -> pure (Left "explicit offline probe Left")
          ThrowProbe -> throwIO (userError "explicit offline probe exception")
          _ ->
            pure
              ( if all (validInput params) inputs
                  then Right (replicate (length inputs) (VU.replicate (Mlp.mlpOutputs (Mlp.paramShape params)) 0))
                  else Left "offline batch input shape differs"
              )
    , mlpdBackward = \params forward upstream -> do
        _ <- record control Backward (Just params)
        if validInput params (Mlp.forwardInput forward)
          && VU.length upstream == Mlp.mlpOutputs (Mlp.paramShape params)
          then Right <$> zeroGradient control params
          else pure (Left "offline backward shape differs")
    , mlpdBatchGradient = \params values -> do
        _ <- record control BatchGradient (Just params)
        fault <- readIORef (controlFault control)
        case fault of
          FailGradient -> pure (Left "explicit offline first gradient Left")
          ThrowGradient -> throwIO (userError "explicit offline first gradient exception")
          CancelGradient -> throwIO ThreadKilled
          _ ->
            if validBatch params values
              then Right <$> zeroGradient control params
              else pure (Left "offline gradient shape differs")
    , mlpdInputGradientBatch = \params values -> do
        _ <- record control InputGradient (Just params)
        pure
          ( if validBatch params values
              then Right (replicate (length values) (VU.replicate (Mlp.mlpInputs (Mlp.paramShape params)) 0))
              else Left "offline input-gradient shape differs"
          )
    , mlpdExecutionWitness = do
        _ <- record control Witness Nothing
        pure (Left "offline fixture must never query a witness")
    }

assertFailureDetail
  :: High.NativeAttemptStage -> High.NativeFailureKind -> Text -> High.NativeAttemptFailure -> Assertion
assertFailureDetail stage kind fragment failure = do
  High.nativeFailureStage failure @?= stage
  High.nativeFailureKind failure @?= kind
  assertBool
    "the concrete boundary diagnostic differs"
    (fragment `Text.isInfixOf` High.nativeFailureDetail failure)

assertNoWitness :: Trace -> Assertion
assertNoWitness trace = sum [n | (_, op, n) <- traceCounts trace, op == Witness] @?= 0

assertSameParams :: Mlp.MlpParams -> Maybe Mlp.MlpParams -> Assertion
assertSameParams expected actual = case actual of
  Nothing -> assertFailure "the actual injected callback was absent"
  Just value -> do
    Mlp.paramShape value @?= Mlp.paramShape expected
    bits value @?= bits expected

makeReady
  :: High.NativeNeuralChildData
  -> Control
  -> IO (High.NativePrepared, High.NativeEffectivePrepared, High.NativeReadyToTrain)
makeReady selected control = do
  enter control Preparing
  cold <- High.prepareNativeNeuralAttempt selected (device control) >>= prepared
  mark control "prepared"
  enter control Initializing
  effective <- High.completeNativeNeuralInitialization cold >>= initialized
  mark control "initialized"
  enter control InitialScoring
  initial <- High.evaluateNativeNeuralInitial effective >>= ready
  mark control "initial-ready"
  pure (cold, effective, initial)

data GuardCheck = GuardCheck High.NativeAttemptStage High.NativeAttemptFailure Integer Integer
data Fixture = Fixture
  { fixtureRow :: Text
  , fixtureChild :: High.NativeNeuralChildData
  , fixtureColdStage :: Low.NeuralPreparationStage
  , fixtureCold :: Low.NeuralSnapshot
  , fixtureEffective :: Low.NeuralSnapshot
  , fixturePriorCold :: Maybe Low.NeuralSnapshot
  , fixtureInitial :: High.NativeEvaluationData
  , fixtureRaw :: High.NativeReturnedData
  , fixtureFinal :: High.NativeEvaluatedData
  , fixtureBeforeFinal :: Trace
  , fixtureAfterFinal :: Trace
  , fixtureGuards :: [GuardCheck]
  }

guardCheck :: Control -> High.NativeAttemptStage -> IO High.NativeAttemptFailure -> IO GuardCheck
guardCheck control stage action = do
  before <- traceTotal <$> readIORef (controlTrace control)
  failure <- action
  after <- traceTotal <$> readIORef (controlTrace control)
  pure (GuardCheck stage failure before after)

makeFixture :: Text -> IO Fixture
makeFixture row = do
  selected <- child row
  control <- newControl
  (cold, effective, initial) <- makeReady selected control
  enter control Training
  actual <- High.continueNativeNeuralTraining initial >>= pending
  let raw = High.nativeReturnedData actual
  -- Force/read the public actual return before any final transition is called.
  _ <- pure $! length (finalBits (High.nativeReturnedPolicy raw))
  mark control "raw-observed"
  beforeFinal <- readIORef (controlTrace control)
  enter control FinalScoring
  final <- High.evaluateNativeNeuralFinal actual >>= completed
  mark control "final-complete"
  afterFinal <- readIORef (controlTrace control)
  guards <-
    sequence
      [ guardCheck control High.NativeInitialization $ do
          result <- High.completeNativeNeuralInitialization cold
          case result of
            High.NativeInitializationFailed failure -> pure failure
            _ -> assertFailure "duplicate initialization created a capability" >> fail "unreachable"
      , guardCheck control High.NativeInitialEvaluation $ do
          result <- High.evaluateNativeNeuralInitial effective
          case result of
            High.NativeInitialEvaluationFailed failure -> pure failure
            _ -> assertFailure "duplicate initial evaluation created Ready" >> fail "unreachable"
      , guardCheck control High.NativeTraining $ do
          result <- High.continueNativeNeuralTraining initial
          case result of
            High.NativeTrainingFailed failure -> pure failure
            _ -> assertFailure "duplicate training created another return" >> fail "unreachable"
      , guardCheck control High.NativeFinalEvaluation $ do
          result <- High.evaluateNativeNeuralFinal actual
          case result of
            High.NativeFinalEvaluationFailed _ _ failure -> pure failure
            _ -> assertFailure "duplicate final evaluation ran again" >> fail "unreachable"
      ]
  pure
    ( Fixture
        row
        selected
        (High.nativePreparedStage cold)
        (High.nativePreparedSnapshot cold)
        (High.nativeEffectiveSnapshot effective)
        (High.nativeEffectiveColdSnapshot effective)
        (High.nativeReadyInitialEvaluation initial)
        raw
        final
        beforeFinal
        afterFinal
        guards
    )

parallel :: IO value -> IO (value, value)
parallel action = do
  one <- newEmptyMVar
  two <- newEmptyMVar
  void (forkFinally action (putMVar one))
  void (forkFinally action (putMVar two))
  first <- takeMVar one >>= finish
  second <- takeMVar two >>= finish
  pure (first, second)
 where
  finish :: Either SomeException value -> IO value
  finish = either throwIO pure

data FinalFailure
  = FinalFailure
      High.NativeReturnedData
      (Maybe High.NativeEvaluationData)
      High.NativeAttemptFailure
      High.NativeAttemptFailure
      Trace
      Integer

firstSteps :: High.NativeEvaluationData -> IO Int
firstSteps observed = case observed of
  High.NativeReturnEvaluation raw -> case Return.nativeEvaluationEpisodes raw of
    first : _ -> pure (ReturnRef.nativeReturnEpisodeSteps first)
    [] -> assertFailure "complete return observation has no first episode" >> fail "unreachable"
  High.NativeHerEvaluation raw -> case Her.nativeHerEvaluationOutcomes raw of
    first : _ -> pure (HerRef.nativeHerOutcomeSteps first)
    [] -> assertFailure "complete HER observation has no first case" >> fail "unreachable"

makeFinalFailure :: IO FinalFailure
makeFinalFailure = do
  selected <- child "HER/goal-reaching"
  control <- newControl
  (_, _, initial) <- makeReady selected control
  enter control Training
  actual <- High.continueNativeNeuralTraining initial >>= pending
  let raw = High.nativeReturnedData actual
  prefix <- firstSteps (High.nativeReturnedInitialEvaluation raw)
  mark control "raw-observed"
  enter control FinalScoring
  writeIORef (controlFault control) (FailScalarAfter (toInteger prefix) ScalarLeft)
  (one, two) <- parallel (High.evaluateNativeNeuralFinal actual)
  failures <- forM [one, two] $ \case
    High.NativeFinalEvaluationFailed kept partial failure -> do
      High.nativeReturnedPolicy kept @?= High.nativeReturnedPolicy raw
      pure (partial, failure)
    High.NativeFinalEvaluationComplete _ -> assertFailure "failing final callback was bypassed" >> fail "unreachable"
  let ordinary =
        [ (partial, failure)
        | (partial, failure) <- failures
        , High.nativeFailureKind failure /= High.NativeAlreadyConsumed
        ]
      claimed =
        [failure | (_, failure) <- failures, High.nativeFailureKind failure == High.NativeAlreadyConsumed]
  case (ordinary, claimed) of
    ([(partial, failure)], [consumed]) -> do
      trace <- readIORef (controlTrace control)
      pure (FinalFailure raw partial failure consumed trace (toInteger prefix))
    _ ->
      assertFailure "concurrent final transitions did not have exactly one claim" >> fail "unreachable"

data Resources = Resources [Fixture] FinalFailure

resources :: IO Resources
resources = do
  complete <-
    traverse
      makeFixture
      ["A2C/cartpole", "DQN/cartpole", "QR-DQN/cartpole", "SAC/pendulum", "HER/goal-reaching"]
  Resources complete <$> makeFinalFailure

fixtures :: IO Resources -> IO [Fixture]
fixtures get = do Resources values _ <- get; pure values

fixture :: IO Resources -> Text -> IO Fixture
fixture get name = do
  values <- fixtures get
  case filter ((== name) . fixtureRow) values of
    [value] -> pure value
    _ -> assertFailure "exact pooled fixture is absent or duplicated" >> fail "unreachable"

expectedUnits :: High.NativeNeuralChildData -> IO Word64
expectedUnits selected = case Budget.compiledRlSchedule (High.nativeNeuralChildCompiledPlan selected) of
  Just schedule -> pure (Budget.scheduleObservedEnvironmentSteps schedule)
  Nothing -> assertFailure "selected canonical child has no schedule" >> fail "unreachable"

assertCompleteData :: High.NativeNeuralChildData -> High.NativeEvaluationData -> Assertion
assertCompleteData selected observed = High.validateNativeEvaluationData selected observed @?= Right ()

initialFailure
  :: Text
  -> Integer
  -> ScalarFault
  -> IO (High.NativeAttemptFailure, High.NativeAttemptFailure, Trace)
initialFailure row prefix fault = do
  selected <- child row
  control <- newControl
  cold <- High.prepareNativeNeuralAttempt selected (device control) >>= prepared
  effective <- High.completeNativeNeuralInitialization cold >>= initialized
  enter control InitialScoring
  writeIORef (controlFault control) (FailScalarAfter prefix fault)
  actual <- High.evaluateNativeNeuralInitial effective
  failure <- case actual of
    High.NativeInitialEvaluationFailed value -> pure value
    _ -> assertFailure "initial callback fault created Ready" >> fail "unreachable"
  before <- traceTotal <$> readIORef (controlTrace control)
  again <- High.evaluateNativeNeuralInitial effective
  consumed <- case again of
    High.NativeInitialEvaluationFailed value -> pure value
    _ -> assertFailure "initial failure exposed a retryable stage" >> fail "unreachable"
  trace <- readIORef (controlTrace control)
  traceTotal trace @?= before
  pure (failure, consumed, trace)

trainingFailure
  :: Fault -> IO (High.NativeAttemptFailure, High.NativeAttemptFailure, Trace)
trainingFailure fault = do
  selected <- child "HER/goal-reaching"
  control <- newControl
  (_, _, initial) <- makeReady selected control
  enter control Training
  writeIORef (controlFault control) fault
  actual <- High.continueNativeNeuralTraining initial
  failure <- case actual of
    High.NativeTrainingFailed value -> pure value
    _ -> assertFailure "training failure invented a numerical return" >> fail "unreachable"
  before <- traceTotal <$> readIORef (controlTrace control)
  again <- High.continueNativeNeuralTraining initial
  consumed <- case again of
    High.NativeTrainingFailed value -> pure value
    _ -> assertFailure "training failure exposed another continuation" >> fail "unreachable"
  trace <- readIORef (controlTrace control)
  traceTotal trace @?= before
  pure (failure, consumed, trace)

rejects :: Text -> Either Text () -> Assertion
rejects fragment value = case value of
  Left reason -> assertBool "specific pure data rejection boundary differs" (fragment `Text.isInfixOf` reason)
  Right () -> assertFailure "mutated observation passed its public data predicate"

-- Inspect every rendered field of retained failure data, rather than only a Show prefix.
{- HLINT ignore nativePreparedNeuralAttemptTests "Use null" -}
nativePreparedNeuralAttemptTests :: TestTree
nativePreparedNeuralAttemptTests = withResource resources (const (pure ())) $ \get ->
  testGroup
    "native canonical prepared neural phases"
    [ testCase "five canonical offline returns preserve initial raw and final phase ordering" $ do
        values <- fixtures get
        map fixtureRow values
          @?= ["A2C/cartpole", "DQN/cartpole", "QR-DQN/cartpole", "SAC/pendulum", "HER/goal-reaching"]
        forM_ values $ \value -> do
          let raw = fixtureRaw value
              before = fixtureBeforeFinal value
              after = fixtureAfterFinal value
          map fst (traceMarks before) @?= ["prepared", "initialized", "initial-ready", "raw-observed"]
          map fst (traceMarks after)
            @?= ["prepared", "initialized", "initial-ready", "raw-observed", "final-complete"]
          case map snd (traceMarks after) of
            [p, i, e, r, f] ->
              assertBool
                "actual callback prefixes do not separate the observed phase boundaries"
                (p > 0 && i >= p && e > i && r > e && f > r)
            _ -> assertFailure "complete phase boundary inventory differs"
          count FinalScoring ScalarForward before @?= 0
          assertBool
            "the explicit final stage actually used its captured device"
            (count FinalScoring ScalarForward after > 0)
          assertBool
            "the actual canonical trainer used the supplied gradient callback"
            (count Training BatchGradient before > 0)
          if fixtureRow value == "DQN/cartpole" then pure () else count Training ScalarForward before @?= 0
          High.nativeReturnedInitialEvaluation raw @?= fixtureInitial value
          High.nativeReturnedPolicy (High.nativeEvaluatedReturnedData (fixtureFinal value))
            @?= High.nativeReturnedPolicy raw
          assertCompleteData (fixtureChild value) (fixtureInitial value)
          assertCompleteData (fixtureChild value) (High.nativeEvaluatedFinalEvaluation (fixtureFinal value))
    , testCase "full raw counters equal each selected canonical budget without a shortened plan" $ do
        values <- fixtures get
        units <- forM values $ \value -> do
          let selected = fixtureChild value
              policy = High.nativeReturnedPolicy (fixtureRaw value)
              actual = Observation.returnedCounters policy
          target <- expectedUnits selected
          -- Observed work is read from the actual raw result; the separate
          -- compiled schedule remains the expected full allocation. HER's
          -- reachable collector resets-and-continues after each early goal.
          Common.observedEnvironmentTransitionCount actual @?= target
          Low.validateNeuralReturnedBinding
            (Low.neuralSnapshotConfiguration (fixtureEffective value))
            (Low.neuralSnapshotInitialParams (fixtureEffective value))
            policy
            @?= Right ()
          assertBool
            "a full actual numerical control must have applied updates"
            (Common.observedOptimizerUpdateCount actual > 0)
          Budget.renderCompiledRlPlanTransport
            (Low.neuralReturnedPlan (High.nativeReturnedLowData (fixtureRaw value)))
            @?= Budget.renderCompiledRlPlanTransport (High.nativeNeuralChildCompiledPlan selected)
          pure target
        units @?= [1228800, 50000, 50000, 4000, 2004]
        sum (map toInteger units) @?= 1334804
    , testCase "motionless raw policies and nonimproving scores remain data after the full schedules" $ do
        values <- fixtures get
        forM_ values $ \value -> do
          let policy = High.nativeReturnedPolicy (fixtureRaw value)
          initialBits policy @?= finalBits policy
          assertBool "the full actual statistics must be retained" (rawStatistics policy > 0)
          fixtureInitial value @?= High.nativeEvaluatedFinalEvaluation (fixtureFinal value)
    , testCase
        "all five effective snapshots are the parameters sent to initial training and final callbacks"
        $ do
          values <- fixtures get
          forM_ values $ \value -> do
            let params = Low.neuralSnapshotInitialParams (fixtureEffective value)
                shape = Mlp.paramShape params
                trace = fixtureAfterFinal value
            initialBits (High.nativeReturnedPolicy (fixtureRaw value)) @?= bits params
            assertSameParams params (firstParams InitialScoring ScalarForward shape trace)
            assertSameParams params (firstParams Training BatchGradient shape trace)
            assertSameParams params (firstParams FinalScoring ScalarForward shape trace)
    , testCase "the low finite cartpole initial score unlocks training without a convergence floor" $ do
        value <- fixture get "A2C/cartpole"
        case fixtureInitial value of
          High.NativeReturnEvaluation raw -> do
            let outcomes = Return.nativeEvaluationEpisodes raw
                bar =
                  Matrix.convergenceBar
                    ( Cohort.nativeRlCohortPlanRow
                        (High.nativeNeuralRowCohort (High.nativeNeuralChildRow (fixtureChild value)))
                    )
            length outcomes @?= 20
            assertBool
              "offline tie policy should actually be below the unchanged row floor"
              (all ((< Convergence.convergenceThreshold bar) . ReturnRef.nativeReturnEpisodeReward) outcomes)
          _ -> assertFailure "cartpole unexpectedly had HER observations"
    , testCase "SAC preserves actual cold warm and effective state independently of scheduled work" $ do
        value <- fixture get "SAC/pendulum"
        fixtureColdStage value @?= Low.NeuralCold
        let view =
              Low.foldNeuralSnapshot
                (const Nothing)
                (const Nothing)
                (const Nothing)
                ( \snapshot ->
                    Just
                      ( Continuous.continuousPreparedStage snapshot
                      , Continuous.continuousPreparedWarmUpdateCount snapshot
                      , fmap bits (Continuous.continuousPreparedTargetActor snapshot)
                      , Mlp.adamStep_ (Continuous.continuousPreparedActorAdam snapshot)
                      )
                )
                (const Nothing)
        view (fixtureCold value) @?= Just (Continuous.ContinuousCold, 0, Nothing, 0)
        case view (fixtureEffective value) of
          Just (stage, warm, Just target, scheduled) -> do
            stage @?= Continuous.ContinuousEffective
            warm @?= 340000
            scheduled @?= 0
            target @?= bits (Low.neuralSnapshotInitialParams (fixtureEffective value))
          _ -> assertFailure "actual effective SAC targets or warm state absent"
        case fixturePriorCold value of
          Nothing -> assertFailure "cold observation was discarded"
          Just cold ->
            bits (Low.neuralSnapshotInitialParams cold)
              @?= bits (Low.neuralSnapshotInitialParams (fixtureCold value))
        count Initializing ScalarForward (fixtureAfterFinal value) @?= 0
        count Initializing BatchGradient (fixtureAfterFinal value) @?= 0
    , testCase "raw preparation initialization training and both evaluations never query a witness" $ do
        values <- fixtures get
        forM_ values (assertNoWitness . fixtureAfterFinal)
    , testCase "all four consumed positive stages reject before any additional callback" $ do
        values <- fixtures get
        forM_ values $ \value -> forM_ (fixtureGuards value) $ \(GuardCheck stage failure before after) -> do
          assertFailureDetail stage High.NativeAlreadyConsumed "already been consumed" failure
          before @?= after
    , testCase
        "checked whole batches retain exactly thirty five neural rows and all one hundred seventy five children"
        $ do
          forM_ [LinuxCPU, LinuxCUDA, AppleSilicon] $ \lane -> do
            whole <- batch lane
            let cohorts = Cohort.nativeRlCohortBatchPlans whole
            length cohorts @?= 43
            accepted <- forM cohorts $ \cohort -> do
              let row = Matrix.rowId (Cohort.nativeRlCohortPlanRow cohort)
              case High.selectNativeNeuralRowData whole row of
                Left _ -> pure []
                Right selected -> do
                  High.nativeNeuralRowId selected @?= row
                  length (Cohort.nativeRlCohortBatchPlans (High.nativeNeuralRowBatch selected)) @?= 43
                  forM Cohort.nativeSeedIndices $ \index -> do
                    actual <- selection (High.selectNativeNeuralChildData selected index)
                    let seedPlan = High.nativeNeuralChildSeedPlan actual
                    Cohort.nativeRlSeedPlanIndex seedPlan @?= index
                    Cohort.nativeRlSeedPlanSeed seedPlan @?= fromIntegral (42 + Cohort.nativeSeedIndexValue index)
                    Native.nativeSingletonSubstrate (Cohort.nativeRlSeedPlanSingleton seedPlan) @?= lane
                    Budget.compiledRlSeed (High.nativeNeuralChildCompiledPlan actual)
                      @?= fromIntegral (Cohort.nativeRlSeedPlanSeed seedPlan)
                    pure ()
            length (filter (not . null) accepted) @?= 35
            sum (map length accepted) @?= 175
    , testCase "ARS AlphaZero and absent rows reject as selection data before any device can be supplied" $ do
        whole <- batch LinuxCPU
        let excluded =
              [ Matrix.rowId (Cohort.nativeRlCohortPlanRow cohort)
              | cohort <- Cohort.nativeRlCohortBatchPlans whole
              , case Cohort.nativeRlSeedPlanCompiledReturn (Cohort.nativeRlCohortServingChild cohort) of
                  Nothing -> True
                  Just plan -> Budget.compiledRlTrainerKind plan == "ars"
              ]
        length excluded @?= 8
        forM_ (excluded <> ["absent/canonical-row", "mnist-mlp", "ALE/atari-subset"]) $ \row ->
          case High.selectNativeNeuralRowData whole row of
            Left failure -> do
              High.nativeFailureStage failure @?= High.NativeSelection
              High.nativeFailureKind failure @?= High.NativeContextRejected
            Right _ -> assertFailure "non-neural row acquired a high selection"
    , testCase "one row-owned HER schedule stays identical across every training child seed" $ do
        whole <- batch LinuxCPU
        row <- selection (High.selectNativeNeuralRowData whole "HER/goal-reaching")
        captured <- case High.nativeNeuralRowHerSchedule row of
          Just value -> pure value
          Nothing -> assertFailure "canonical HER schedule absent" >> fail "unreachable"
        HerRef.nativeHerSpecBaseSeed (HerRef.nativeHerScheduleSpec captured) @?= 42
        HerRef.nativeHerSpecEvaluationSeed (HerRef.nativeHerScheduleSpec captured) @?= 104771
        length (HerRef.nativeHerScheduleCases captured) @?= 20
        forM_ Cohort.nativeSeedIndices $ \index -> do
          selected <- selection (High.selectNativeNeuralChildData row index)
          High.nativeNeuralRowHerSchedule (High.nativeNeuralChildRow selected) @?= Just captured
        value <- fixture get "HER/goal-reaching"
        case (fixtureInitial value, High.nativeEvaluatedFinalEvaluation (fixtureFinal value)) of
          (High.NativeHerEvaluation initial, High.NativeHerEvaluation final) -> do
            Her.nativeHerEvaluationSchedule initial @?= captured
            Her.nativeHerEvaluationSchedule final @?= captured
            map HerRef.nativeHerOutcomeGoal (Her.nativeHerEvaluationOutcomes initial)
              @?= map HerRef.rawNativeHerGoal (HerRef.nativeHerScheduleCases captured)
            map HerRef.nativeHerOutcomeGoal (Her.nativeHerEvaluationOutcomes final)
              @?= map HerRef.rawNativeHerGoal (HerRef.nativeHerScheduleCases captured)
          _ -> assertFailure "HER fixed-case family changed"
    , testCase "preparation probe Left or exception stops before initialization training and evaluation" $ do
        forM_ [(FailProbe, "explicit offline probe Left"), (ThrowProbe, "explicit offline probe exception")] $ \(fault, fragment) -> do
          selected <- child "SAC/pendulum"
          control <- newControl
          writeIORef (controlFault control) fault
          actual <- High.prepareNativeNeuralAttempt selected (device control)
          case actual of
            High.NativePreparationFailed failure -> do
              assertFailureDetail High.NativePreparation High.NativeLowRejected fragment failure
              case High.nativeFailureSnapshot failure of
                Nothing -> pure ()
                Just _ -> assertFailure "failed probe invented a prepared snapshot"
            _ -> assertFailure "failed actual preparation probe created a capsule"
          trace <- readIORef (controlTrace control)
          count Preparing BatchForward trace @?= 1
          count Training BatchGradient trace @?= 0
          count InitialScoring ScalarForward trace @?= 0
          assertNoWitness trace
    , testCase "reference seedless budgets are explicitly compared with the selected seeded budget" $ do
        values <- fixtures get
        forM_ values $ \value -> do
          let selected = fixtureChild value
              row = High.nativeNeuralChildRow selected
              actual = Cohort.nativeRlSeedPlanTrainingBudget (High.nativeNeuralChildSeedPlan selected)
          seedless <- case (High.nativeNeuralRowReturnSpec row, High.nativeNeuralRowHerSchedule row) of
            (Just spec, Nothing) -> pure (ReturnRef.nativeReturnSpecBudget spec)
            (Nothing, Just schedule) -> pure (HerRef.nativeHerSpecTrainingBudget (HerRef.nativeHerScheduleSpec schedule))
            _ -> assertFailure "closed selected row has no unique reference context" >> fail "unreachable"
          TrainingBudget.trainingBudgetSeed seedless @?= Nothing
          expected <-
            right
              ( TrainingBudget.mkTrainingBudget
                  (TrainingBudget.trainingBudgetKind seedless)
                  (TrainingBudget.trainingBudgetTargetUnits seedless)
                  (Just 42)
              )
          actual @?= expected
    , testCase "initial device Left preserves a completed case prefix and Unknown failed return work" $ do
        value <- fixture get "A2C/cartpole"
        prefix <- firstSteps (fixtureInitial value)
        (failure, consumed, trace) <- initialFailure "A2C/cartpole" (toInteger prefix) ScalarLeft
        assertFailureDetail
          High.NativeInitialEvaluation
          High.NativeEvaluationRejected
          "explicit offline scalar Left"
          failure
        assertFailureDetail
          High.NativeInitialEvaluation
          High.NativeAlreadyConsumed
          "already been consumed"
          consumed
        case High.nativeFailureEvaluation failure of
          Just (High.NativeReturnEvaluation raw) -> do
            length (Return.nativeEvaluationEpisodes raw) @?= 1
            Return.nativeEvaluationWork raw @?= Return.NativeFailedWork (toInteger prefix) Nothing
            case Return.nativeEvaluationStatus raw of
              Return.NativeEvaluationFailed 1 Return.NativeDelegatedLeft _ -> pure ()
              _ -> assertFailure "actual delegated failed-case boundary differs"
          _ -> assertFailure "actual incomplete initial observation was discarded"
        count Training BatchGradient trace @?= 0
    , testCase
        "initial synchronous callback exceptions remain inspectable failures with no Ready or retry"
        $ do
          (failure, consumed, trace) <- initialFailure "A2C/cartpole" 0 ScalarThrow
          assertFailureDetail
            High.NativeInitialEvaluation
            High.NativeEvaluationRejected
            "explicit offline scalar exception"
            failure
          High.nativeFailureKind consumed @?= High.NativeAlreadyConsumed
          count InitialScoring ScalarForward trace @?= 1
          count Training BatchGradient trace @?= 0
    , testCase "lazy initial outer Either is forced before high failure observations are retained" $ do
        (failure, _, trace) <- initialFailure "A2C/cartpole" 0 ScalarLazyOuter
        assertFailureDetail
          High.NativeInitialEvaluation
          High.NativeEvaluationRejected
          "lazy offline scalar Either"
          failure
        count InitialScoring ScalarForward trace @?= 1
        assertBool
          "a retained actual evaluation remains printable"
          (maybe False ((> 0) . length . show) (High.nativeFailureEvaluation failure))
    , testCase "lazy initial Left text and forward payload fail inside the selected evaluator boundary" $ do
        forM_
          [(ScalarLazyLeft, "lazy offline scalar Left"), (ScalarLazyForward, "lazy offline scalar forward")]
          $ \(fault, fragment) -> do
            (failure, _, trace) <- initialFailure "A2C/cartpole" 0 fault
            assertFailureDetail High.NativeInitialEvaluation High.NativeEvaluationRejected fragment failure
            count Training BatchGradient trace @?= 0
            assertBool
              "poisonous callback data escaped into the retained observation"
              (maybe False ((> 0) . length . show) (High.nativeFailureEvaluation failure))
    , testCase "wrong-shape and nonfinite initial outputs cannot create a training continuation" $ do
        forM_ [ScalarWrongShape, ScalarNonfinite] $ \fault -> do
          (failure, consumed, trace) <- initialFailure "A2C/cartpole" 0 fault
          High.nativeFailureKind failure @?= High.NativeEvaluationRejected
          High.nativeFailureKind consumed @?= High.NativeAlreadyConsumed
          count Training BatchGradient trace @?= 0
          count InitialScoring ScalarForward trace @?= 1
    , testCase "async initial cancellation propagates and consumes its sole high evaluation stage" $ do
        selected <- child "HER/goal-reaching"
        control <- newControl
        cold <- High.prepareNativeNeuralAttempt selected (device control) >>= prepared
        effective <- High.completeNativeNeuralInitialization cold >>= initialized
        enter control InitialScoring
        writeIORef (controlFault control) (FailScalarAfter 0 ScalarAsync)
        actual <-
          try (High.evaluateNativeNeuralInitial effective)
            :: IO (Either AsyncException High.NativeInitialEvaluationResult)
        case actual of
          Left ThreadKilled -> pure ()
          _ -> assertFailure "async initial cancellation was swallowed"
        before <- traceTotal <$> readIORef (controlTrace control)
        again <- High.evaluateNativeNeuralInitial effective
        case again of
          High.NativeInitialEvaluationFailed failure -> High.nativeFailureKind failure @?= High.NativeAlreadyConsumed
          _ -> assertFailure "cancelled evaluation created Ready"
        trace <- readIORef (controlTrace control)
        traceTotal trace @?= before
        count Training BatchGradient trace @?= 0
    , testCase "concurrent initialization and initial evaluation each have exactly one winner" $ do
        selected <- child "HER/goal-reaching"
        control <- newControl
        cold <- High.prepareNativeNeuralAttempt selected (device control) >>= prepared
        (one, two) <- parallel (High.completeNativeNeuralInitialization cold)
        let good = [value | High.NativeInitializationReady value <- [one, two]]
            bad = [failure | High.NativeInitializationFailed failure <- [one, two]]
        case (good, bad) of
          ([effective], [failure]) -> do
            High.nativeFailureKind failure @?= High.NativeAlreadyConsumed
            enter control InitialScoring
            (first, second) <- parallel (High.evaluateNativeNeuralInitial effective)
            length [() | High.NativeInitialEvaluationReady _ <- [first, second]] @?= 1
            case [f | High.NativeInitialEvaluationFailed f <- [first, second]] of
              [f] -> High.nativeFailureKind f @?= High.NativeAlreadyConsumed
              _ -> assertFailure "concurrent initial evaluation had no consumed loser"
          _ -> assertFailure "concurrent initialization minted zero or two effective stages"
    , testCase
        "actual first-gradient Left preserves initial observations without inventing a returned model"
        $ do
          (failure, consumed, trace) <- trainingFailure FailGradient
          assertFailureDetail
            High.NativeTraining
            High.NativeLowRejected
            "explicit offline first gradient Left"
            failure
          High.nativeFailureKind consumed @?= High.NativeAlreadyConsumed
          assertBool
            "already observed initial evaluation was discarded"
            (case High.nativeFailureInitialEvaluation failure of Just _ -> True; Nothing -> False)
          count Training BatchGradient trace @?= 1
          assertNoWitness trace
    , testCase "actual synchronous first-gradient exception leaves only the low observed failure facts" $ do
        (failure, _, trace) <- trainingFailure ThrowGradient
        assertFailureDetail
          High.NativeTraining
          High.NativeLowRejected
          "explicit offline first gradient exception"
          failure
        case High.nativeFailureLowFailure failure of
          Just low -> Low.neuralFailureKind low @?= Low.NeuralSynchronousFailure
          Nothing -> assertFailure "actual lower failure observation was discarded"
        count Training BatchGradient trace @?= 1
    , testCase "async training cancellation propagates and consumes the original Ready stage" $ do
        selected <- child "HER/goal-reaching"
        control <- newControl
        (_, _, initial) <- makeReady selected control
        enter control Training
        writeIORef (controlFault control) CancelGradient
        actual <-
          try (High.continueNativeNeuralTraining initial)
            :: IO (Either AsyncException High.NativeTrainingResult)
        case actual of
          Left ThreadKilled -> pure ()
          _ -> assertFailure "async training cancellation was swallowed"
        before <- traceTotal <$> readIORef (controlTrace control)
        again <- High.continueNativeNeuralTraining initial
        case again of
          High.NativeTrainingFailed failure -> High.nativeFailureKind failure @?= High.NativeAlreadyConsumed
          _ -> assertFailure "cancelled Ready retrained"
        trace <- readIORef (controlTrace control)
        traceTotal trace @?= before
        count Training BatchGradient trace @?= 1
    , testCase "concurrent training claims only one actual numerical prefix before its declared failure" $ do
        selected <- child "HER/goal-reaching"
        control <- newControl
        (_, _, initial) <- makeReady selected control
        enter control Training
        writeIORef (controlFault control) FailGradient
        (one, two) <- parallel (High.continueNativeNeuralTraining initial)
        let failures = [failure | High.NativeTrainingFailed failure <- [one, two]]
        length failures @?= 2
        length [() | f <- failures, High.nativeFailureKind f == High.NativeAlreadyConsumed] @?= 1
        length [() | f <- failures, High.nativeFailureKind f == High.NativeLowRejected] @?= 1
        trace <- readIORef (controlTrace control)
        count Training BatchGradient trace @?= 1
    , testCase "a full HER raw return survives final callback failure and concurrent final claiming" $ do
        Resources _ (FinalFailure raw partial failure consumed trace prefix) <- get
        assertFailureDetail
          High.NativeFinalEvaluation
          High.NativeEvaluationRejected
          "explicit offline scalar Left"
          failure
        assertFailureDetail
          High.NativeFinalEvaluation
          High.NativeAlreadyConsumed
          "already been consumed"
          consumed
        case High.nativeFailureInitialEvaluation failure of
          Just initial -> High.nativeReturnedInitialEvaluation raw @?= initial
          Nothing -> assertFailure "final failure discarded actual initial facts"
        Common.observedEnvironmentTransitionCount
          (Observation.returnedCounters (High.nativeReturnedPolicy raw))
          @?= 2004
        initialBits (High.nativeReturnedPolicy raw) @?= finalBits (High.nativeReturnedPolicy raw)
        case partial of
          Just (High.NativeHerEvaluation observed) -> do
            length (Her.nativeHerEvaluationOutcomes observed) @?= 1
            Her.nativeHerEvaluationWork observed @?= Her.NativeHerFailedWork prefix 0 (Just 0)
            case Her.nativeHerEvaluationStatus observed of
              Her.NativeHerEvaluationFailed 1 Her.NativeHerDeviceRejected _ -> pure ()
              _ -> assertFailure "actual final HER failure lost its case boundary"
          _ -> assertFailure "actual incomplete final observations were discarded"
        count FinalScoring ScalarForward trace @?= prefix + 1
        assertNoWitness trace
    , testCase
        "the public unit-only predicate rejects missing reordered duplicate and forged-complete cases"
        $ do
          value <- fixture get "A2C/cartpole"
          case fixtureInitial value of
            High.NativeReturnEvaluation raw -> case Return.nativeEvaluationEpisodes raw of
              first : rest -> do
                let wrap = High.NativeReturnEvaluation
                    selected = fixtureChild value
                rejects
                  "inventory"
                  (High.validateNativeEvaluationData selected (wrap (raw {Return.nativeEvaluationEpisodes = rest})))
                rejects
                  "inventory"
                  ( High.validateNativeEvaluationData
                      selected
                      (wrap (raw {Return.nativeEvaluationEpisodes = reverse (first : rest)}))
                  )
                rejects
                  "inventory"
                  ( High.validateNativeEvaluationData
                      selected
                      (wrap (raw {Return.nativeEvaluationEpisodes = first : first : rest}))
                  )
                rejects
                  "inventory"
                  ( High.validateNativeEvaluationData
                      selected
                      ( wrap
                          ( raw
                              { Return.nativeEvaluationEpisodes = []
                              , Return.nativeEvaluationWork = Return.NativeCompleteWork 0
                              }
                          )
                      )
                  )
              [] -> assertFailure "actual complete case inventory absent"
            _ -> assertFailure "actual cartpole observation changed family"
    , testCase
        "the public data predicate rejects nonfinite incomplete and inconsistent-work return observations"
        $ do
          value <- fixture get "A2C/cartpole"
          case fixtureInitial value of
            High.NativeReturnEvaluation raw -> case Return.nativeEvaluationEpisodes raw of
              first : rest -> do
                let selected = fixtureChild value
                    check reason episodes =
                      rejects
                        reason
                        ( High.validateNativeEvaluationData
                            selected
                            (High.NativeReturnEvaluation (raw {Return.nativeEvaluationEpisodes = episodes}))
                        )
                check "nonfinite or incomplete" (first {ReturnRef.nativeReturnEpisodeReward = 0 / 0} : rest)
                check "nonfinite or incomplete" (first {ReturnRef.nativeReturnEpisodeSteps = 0} : rest)
                rejects
                  "work differs"
                  ( High.validateNativeEvaluationData
                      selected
                      (High.NativeReturnEvaluation (raw {Return.nativeEvaluationWork = Return.NativeCompleteWork (-1)}))
                  )
              [] -> assertFailure "complete return observations absent"
            _ -> assertFailure "actual cartpole observation changed family"
    , testCase
        "the public data predicate rejects wrong fixed-case families and actual policy context substitution"
        $ do
          cart <- fixture get "A2C/cartpole"
          goals <- fixture get "HER/goal-reaching"
          rejects
            "wrong fixed-case family"
            (High.validateNativeEvaluationData (fixtureChild cart) (fixtureInitial goals))
          case fixtureInitial cart of
            High.NativeReturnEvaluation raw -> case Return.nativeEvaluationPolicy raw of
              Return.NativeNeuralEvaluation (Return.NativeOnPolicy config params) ->
                rejects
                  "dimensions differ"
                  ( High.validateNativeEvaluationData
                      (fixtureChild cart)
                      ( High.NativeReturnEvaluation
                          ( raw
                              { Return.nativeEvaluationPolicy =
                                  Return.NativeNeuralEvaluation
                                    (Return.NativeOnPolicy (config {Ppo.ppoObsSize = Ppo.ppoObsSize config + 1}) params)
                              }
                          )
                      )
                  )
              _ -> assertFailure "actual A2C policy payload absent"
            _ -> assertFailure "actual cartpole observation changed family"
    , testCase "the public HER data predicate preserves exact captured goal order and work" $ do
        value <- fixture get "HER/goal-reaching"
        case fixtureInitial value of
          High.NativeHerEvaluation raw -> case Her.nativeHerEvaluationOutcomes raw of
            first : rest -> do
              let selected = fixtureChild value
                  check reason changed = rejects reason (High.validateNativeEvaluationData selected (High.NativeHerEvaluation changed))
              check "inventory" (raw {Her.nativeHerEvaluationOutcomes = reverse (first : rest)})
              check
                "goals differ"
                ( raw
                    { Her.nativeHerEvaluationOutcomes =
                        first {HerRef.nativeHerOutcomeGoal = VU.map (1 -) (HerRef.nativeHerOutcomeGoal first)} : rest
                    }
                )
              check
                "nonfinite or incomplete"
                ( raw
                    { Her.nativeHerEvaluationOutcomes = first {HerRef.nativeHerOutcomeNormalizedDistance = 0 / 0} : rest
                    }
                )
              check "work differs" (raw {Her.nativeHerEvaluationWork = Her.NativeHerCompleteWork (-1)})
            [] -> assertFailure "complete HER observations absent"
          _ -> assertFailure "actual goal observation changed family"
    ]
