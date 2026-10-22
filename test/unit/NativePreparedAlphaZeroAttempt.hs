{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

-- Full canonical schedules through explicitly OFFLINE shape-correct zero
-- outputs/gradients. Real game/search/trainer loops execute; these controls
-- claim no provider, learning, numerical equivalence, origin or qualification.
module NativePreparedAlphaZeroAttempt (nativePreparedAlphaZeroAttemptTests) where

import Control.Concurrent (forkFinally)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import Control.Exception (AsyncException (..), SomeException, throwIO, try)
import Control.Monad (forM, forM_, void)
import Data.Bits (xor)
import Data.IORef (IORef, atomicModifyIORef', modifyIORef', newIORef, readIORef, writeIORef)
import Data.List (find)
import Data.List.NonEmpty qualified as NE
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)
import GHC.Float (castDoubleToWord64, castWord64ToDouble)
import Test.Tasty (TestTree, testGroup, withResource)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Numerics.Mlp qualified as Mlp
import JitML.Numerics.MlpDevice (MlpDevice (..), pureReferenceMlpDevice)
import JitML.Plan.NativeSingletonPlan qualified as Native
import JitML.Plan.Plan qualified as Plan
import JitML.Plan.Workload qualified as Workload
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.NativePreparedAlphaZeroAttempt qualified as High
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.RL.AlphaZero qualified as Game
import JitML.RL.AlphaZero.ArenaTape qualified as Tape
import JitML.RL.AlphaZero.NativeArenaEvaluation qualified as Arena
import JitML.RL.AlphaZero.NativeArenaReferences qualified as Ref
import JitML.RL.AlphaZero.PolicyValueNet qualified as Net
import JitML.RL.AlphaZero.PreparedTrainer qualified as Low
import JitML.Substrate (Substrate (..))
import JitML.Training.Budget qualified as Budget

right :: (Show error) => Either error value -> IO value
right value = case value of
  Right actual -> pure actual
  Left detail -> assertFailure (show detail) >> fail "unreachable"
selection :: Either High.NativeArenaFailure value -> IO value
selection value = case value of Right actual -> pure actual; Left failure -> failed failure
failed :: High.NativeArenaFailure -> IO value
failed failure = assertFailure (Text.unpack (High.nativeAlphaZeroFailureDetail failure)) >> fail "unreachable"
prepared :: High.NativeArenaPreparationResult -> IO High.NativeArenaPrepared
prepared value = case value of
  High.NativeArenaPreparationReady actual -> pure actual
  High.NativeArenaPreparationFailed failure -> failed failure
ready :: High.NativeArenaInitialResult -> IO High.NativeArenaReadyToTrain
ready value = case value of
  High.NativeArenaInitialReady actual -> pure actual
  High.NativeArenaInitialFailed failure -> failed failure
pending :: High.NativeArenaTrainingResult -> IO High.NativeArenaPendingFinal
pending value = case value of
  High.NativeArenaTrainingReturned actual -> pure actual
  High.NativeArenaTrainingFailed failure -> failed failure
  High.NativeArenaTrainingReturnedButUnmaterializable failure -> failed failure
  High.NativeArenaTrainingBindingFailed _ failure -> failed failure
completed :: High.NativeArenaFinalResult -> IO High.NativeAlphaZeroEvaluatedData
completed value = case value of
  High.NativeArenaFinalComplete actual -> pure actual
  High.NativeArenaFinalFailed _ _ failure -> failed failure
firstValue :: [value] -> IO value
firstValue values = case values of
  actual : _ -> pure actual
  [] -> assertFailure "required actual observation is absent" >> fail "unreachable"
rejects :: Text -> Either Text value -> Assertion
rejects fragment value = case value of
  Left detail -> assertBool "specific data rejection differs" (fragment `Text.isInfixOf` detail)
  Right _ -> assertFailure "invalid data passed its public unit predicate"
indexZero :: IO Cohort.NativeSeedIndex
indexZero = firstValue Cohort.nativeSeedIndices
batch :: Substrate -> IO Cohort.NativeRlCohortBatch
batch = right . Cohort.mkCanonicalNativeRlCohorts
child :: Text -> IO High.NativeAlphaZeroChildData
child rowId = do
  whole <- batch LinuxCPU
  row <- selection (High.selectNativeAlphaZeroRowData whole rowId)
  zero <- indexZero
  selection (High.selectNativeAlphaZeroChildData row zero)

{-# NOINLINE vectorBits #-}
vectorBits :: VU.Vector Double -> [Word64]
vectorBits = map castDoubleToWord64 . VU.toList
{-# NOINLINE toggleSign #-}
toggleSign :: Word64 -> Double -> Double
toggleSign mask value = castWord64ToDouble (castDoubleToWord64 value `xor` mask)
paramsBits :: Mlp.MlpParams -> [Word64]
paramsBits = map castDoubleToWord64 . Mlp.mlpParamsToFlat
netBits :: Net.PolicyValueNet -> (Int, Int, Mlp.MlpShape, [Word64])
netBits net =
  ( Net.pvnObservationSize net
  , Net.pvnActionCount net
  , Mlp.paramShape (Net.pvnParams net)
  , paramsBits (Net.pvnParams net)
  )
adamBits :: Mlp.AdamState -> (Int, [[Word64]])
adamBits adam = (Mlp.adamStep_ adam, concatMap gradientBits [Mlp.adamM adam, Mlp.adamV adam])
 where
  gradientBits gradient =
    map vectorBits [Mlp.gradW1 gradient, Mlp.gradB1 gradient, Mlp.gradW2 gradient, Mlp.gradB2 gradient]

-- Bounded first-observation/operation counts, not a full kernel transcript.
data Phase = Preparing | InitialScoring | Training | FinalScoring deriving stock (Eq, Show)
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
  | ScalarOverflow
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
  , controlZeroGradient :: IORef [(Mlp.MlpShape, Mlp.MlpGradient)]
  }
newControl :: IO Control
newControl = Control <$> newIORef Preparing <*> newIORef (Trace 0 [] [] []) <*> newIORef Clear <*> newIORef []
enter :: Control -> Phase -> IO ()
enter control = writeIORef (controlPhase control)
mark :: Control -> Text -> IO ()
mark control label = modifyIORef' (controlTrace control) $ \value -> value {traceMarks = traceMarks value <> [(label, traceTotal value)]}
count :: Phase -> Operation -> Trace -> Integer
count phase operation value = sum [n | (p, op, n) <- traceCounts value, p == phase, op == operation]
record :: Control -> Operation -> Maybe Mlp.MlpParams -> IO Integer
record control operation params = do
  phase <- readIORef (controlPhase control)
  atomicModifyIORef' (controlTrace control) $ \value ->
    let ordinal = count phase operation value + 1
        add [] = [(phase, operation, ordinal)]
        add ((p, op, n) : rest)
          | p == phase && op == operation = (p, op, ordinal) : rest
          | otherwise = (p, op, n) : add rest
        firsts = case params of
          Nothing -> traceFirst value
          Just actual ->
            let shape = Mlp.paramShape actual
             in if any (\(p, op, s, _) -> p == phase && op == operation && s == shape) (traceFirst value)
                  then traceFirst value
                  else (phase, operation, shape, actual) : traceFirst value
        updated =
          value
            { traceTotal = traceTotal value + 1
            , traceCounts = add (traceCounts value)
            , traceFirst = firsts
            }
     in (updated, ordinal)
firstParams :: Phase -> Operation -> Mlp.MlpShape -> Trace -> Maybe Mlp.MlpParams
firstParams phase operation shape value = do
  (_, _, _, actual) <-
    find (\(p, op, s, _) -> p == phase && op == operation && s == shape) (traceFirst value)
  pure actual
zeroGradient :: Control -> Mlp.MlpParams -> IO Mlp.MlpGradient
zeroGradient control params = do
  let shape = Mlp.paramShape params
  values <- readIORef (controlZeroGradient control)
  case lookup shape values of
    Just actual -> pure actual
    Nothing -> do
      let actual = Mlp.mlpZeroGradient shape
      modifyIORef' (controlZeroGradient control) ((shape, actual) :)
      pure actual
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
  ScalarLeft -> pure (Left "explicit offline AlphaZero scalar Left")
  ScalarThrow -> throwIO (userError "explicit offline AlphaZero scalar exception")
  ScalarLazyOuter -> pure (error "lazy offline AlphaZero Either")
  ScalarLazyLeft -> pure (Left (error "lazy offline AlphaZero Left text"))
  ScalarLazyForward -> pure (Right (error "lazy offline AlphaZero forward"))
  ScalarWrongShape -> pure (Right ((zeroForward params input) {Mlp.forwardOutput = VU.empty}))
  ScalarNonfinite ->
    pure
      ( Right
          ( (zeroForward params input)
              { Mlp.forwardOutput = VU.replicate (Mlp.mlpOutputs (Mlp.paramShape params)) (0 / 0)
              }
          )
      )
  ScalarOverflow ->
    pure
      ( Right
          ( (zeroForward params input)
              { Mlp.forwardOutput = VU.replicate (Mlp.mlpOutputs (Mlp.paramShape params)) 1e300
              }
          )
      )
  ScalarAsync -> throwIO ThreadKilled

-- Existing public MlpDevice injection only; no arbitrary raw/search/result or
-- capability factory. Successful zero numerics are explicitly offline data.
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
                  else Left "offline AlphaZero scalar shape differs"
              )
    , mlpdForwardBatch = \params inputs -> do
        _ <- record control BatchForward (Just params)
        fault <- readIORef (controlFault control)
        case fault of
          FailProbe -> pure (Left "explicit offline AlphaZero probe Left")
          ThrowProbe -> throwIO (userError "explicit offline AlphaZero probe exception")
          _ ->
            pure
              ( if all (validInput params) inputs
                  then Right (replicate (length inputs) (VU.replicate (Mlp.mlpOutputs (Mlp.paramShape params)) 0))
                  else Left "offline AlphaZero batch shape differs"
              )
    , mlpdBackward = \params forward upstream -> do
        _ <- record control Backward (Just params)
        if validInput params (Mlp.forwardInput forward)
          && VU.length upstream == Mlp.mlpOutputs (Mlp.paramShape params)
          then Right <$> zeroGradient control params
          else pure (Left "offline AlphaZero backward shape differs")
    , mlpdBatchGradient = \params values -> do
        _ <- record control BatchGradient (Just params)
        fault <- readIORef (controlFault control)
        case fault of
          FailGradient -> pure (Left "explicit offline AlphaZero gradient Left")
          ThrowGradient -> throwIO (userError "explicit offline AlphaZero gradient exception")
          CancelGradient -> throwIO ThreadKilled
          _ ->
            if validBatch params values
              then Right <$> zeroGradient control params
              else pure (Left "offline AlphaZero gradient shape differs")
    , mlpdInputGradientBatch = \params values -> do
        _ <- record control InputGradient (Just params)
        pure
          ( if validBatch params values
              then Right (replicate (length values) (VU.replicate (Mlp.mlpInputs (Mlp.paramShape params)) 0))
              else Left "offline AlphaZero input-gradient shape differs"
          )
    , mlpdExecutionWitness = do
        _ <- record control Witness Nothing
        pure (Left "offline AlphaZero data must never query a witness")
    }

assertFailureDetail
  :: High.NativeArenaAttemptStage
  -> High.NativeArenaFailureKind
  -> Text
  -> High.NativeArenaFailure
  -> Assertion
assertFailureDetail stage kind fragment failure = do
  High.nativeAlphaZeroFailureStage failure @?= stage
  High.nativeAlphaZeroFailureKind failure @?= kind
  assertBool
    "specific high boundary diagnostic differs"
    (fragment `Text.isInfixOf` High.nativeAlphaZeroFailureDetail failure)
assertNoWitness :: Trace -> Assertion
assertNoWitness value = sum [n | (_, op, n) <- traceCounts value, op == Witness] @?= 0
assertSameParams :: Mlp.MlpParams -> Maybe Mlp.MlpParams -> Assertion
assertSameParams expected actual = case actual of
  Nothing -> assertFailure "actual supplied-device callback was absent"
  Just value -> do Mlp.paramShape value @?= Mlp.paramShape expected; paramsBits value @?= paramsBits expected
assertComplete
  :: High.NativeAlphaZeroChildData -> Net.PolicyValueNet -> Arena.RawNativeArenaEvaluation -> Assertion
assertComplete selected net actual = do
  High.validateNativeAlphaZeroEvaluationData selected net actual @?= Right ()
  Arena.nativeArenaEvaluationStatus actual @?= Arena.NativeArenaEvaluationComplete
  map Ref.nativeArenaEpisodeId (Arena.nativeArenaEvaluationEpisodes actual) @?= [0 .. 8]

makeReady
  :: High.NativeAlphaZeroChildData
  -> Control
  -> IO (High.NativeArenaPrepared, High.NativeArenaReadyToTrain)
makeReady selected control = do
  enter control Preparing
  initial <- High.prepareNativeAlphaZeroAttempt selected (device control) >>= prepared
  mark control "prepared"
  enter control InitialScoring
  actual <- High.evaluateNativeAlphaZeroInitial initial >>= ready
  mark control "initial-ready"
  pure (initial, actual)

data GuardCheck = GuardCheck High.NativeArenaAttemptStage High.NativeArenaFailure Integer Integer
guardCheck :: Control -> High.NativeArenaAttemptStage -> IO High.NativeArenaFailure -> IO GuardCheck
guardCheck control stage action = do
  before <- traceTotal <$> readIORef (controlTrace control)
  failure <- action
  after <- traceTotal <$> readIORef (controlTrace control)
  pure (GuardCheck stage failure before after)
data Fixture = Fixture
  { fixtureChild :: High.NativeAlphaZeroChildData
  , fixtureSnapshot :: Low.AlphaZeroPreparedSnapshot
  , fixtureInitial :: Arena.RawNativeArenaEvaluation
  , fixtureReturned :: High.NativeAlphaZeroReturnedData
  , fixtureFinal :: High.NativeAlphaZeroEvaluatedData
  , fixtureBeforeFinal :: Trace
  , fixtureAfterFinal :: Trace
  , fixtureGuards :: [GuardCheck]
  }
makeFixture :: IO Fixture
makeFixture = do
  selected <- child "connect4"
  control <- newControl
  (initial, enabled) <- makeReady selected control
  enter control Training
  actual <- High.continueNativeAlphaZeroTraining enabled >>= pending
  let returned = High.nativeAlphaZeroReturnedData actual
      raw = High.nativeAlphaZeroReturnedRawObservation returned
  _ <- pure $! length (paramsBits (Net.pvnParams (Low.alphaZeroObservedFinalNet raw)))
  mark control "raw-observed"
  beforeFinal <- readIORef (controlTrace control)
  enter control FinalScoring
  final <- High.evaluateNativeAlphaZeroFinal actual >>= completed
  mark control "final-complete"
  afterFinal <- readIORef (controlTrace control)
  guards <-
    sequence
      [ guardCheck control High.NativeArenaInitialEvaluation $ do
          result <- High.evaluateNativeAlphaZeroInitial initial
          case result of
            High.NativeArenaInitialFailed failure -> pure failure
            _ -> assertFailure "duplicate initial scoring enabled another Ready" >> fail "unreachable"
      , guardCheck control High.NativeArenaTraining $ do
          result <- High.continueNativeAlphaZeroTraining enabled
          case result of
            High.NativeArenaTrainingFailed failure -> pure failure
            _ -> assertFailure "duplicate training created another return" >> fail "unreachable"
      , guardCheck control High.NativeArenaFinalEvaluation $ do
          result <- High.evaluateNativeAlphaZeroFinal actual
          case result of
            High.NativeArenaFinalFailed _ _ failure -> pure failure
            _ -> assertFailure "duplicate final scoring ran again" >> fail "unreachable"
      ]
  pure
    ( Fixture
        selected
        (High.nativeAlphaZeroPreparedSnapshot initial)
        (High.nativeAlphaZeroReadyInitialEvaluation enabled)
        returned
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

-- A second full canonical return, not a shortened or restored raw fixture.
-- Finish its Pending exactly once (two concurrent claimants, one winner), then
-- retain only immutable observations so Tasty leaf order cannot consume a stage.
data FinalFailure
  = FinalFailure
      High.NativeAlphaZeroReturnedData
      High.NativeAlphaZeroReturnedData
      Arena.RawNativeArenaEvaluation
      High.NativeArenaFailure
      High.NativeArenaFailure
      High.NativeArenaFailure
      Trace
      Integer
      Integer
makeFinalFailure :: IO FinalFailure
makeFinalFailure = do
  selected <- child "connect4"
  control <- newControl
  (_, enabled) <- makeReady selected control
  enter control Training
  actual <- High.continueNativeAlphaZeroTraining enabled >>= pending
  let returned = High.nativeAlphaZeroReturnedData actual
      initial = High.nativeAlphaZeroReturnedInitialEvaluation returned
  firstSecond <-
    maybe
      (assertFailure "complete second case callback absent" >> fail "unreachable")
      pure
      ( find
          ((== 1) . Arena.nativeArenaForwardGame)
          (Arena.nativeArenaFirstForwards (Arena.nativeArenaEvaluationForwards initial))
      )
  let prefix = Arena.nativeArenaForwardOrdinal firstSecond
  _ <-
    pure $!
      length
        ( paramsBits
            (Net.pvnParams (Low.alphaZeroObservedFinalNet (High.nativeAlphaZeroReturnedRawObservation returned)))
        )
  mark control "raw-observed"
  enter control FinalScoring
  writeIORef (controlFault control) (FailScalarAfter prefix ScalarLeft)
  (one, two) <- parallel (High.evaluateNativeAlphaZeroFinal actual)
  (kept, partial, winner, loser) <- classify one two
  before <- traceTotal <$> readIORef (controlTrace control)
  duplicate <- High.evaluateNativeAlphaZeroFinal actual
  duplicateFailure <- case duplicate of
    High.NativeArenaFinalFailed _ _ failure -> pure failure
    _ -> assertFailure "third final scoring unexpectedly ran" >> fail "unreachable"
  after <- traceTotal <$> readIORef (controlTrace control)
  value <- readIORef (controlTrace control)
  pure (FinalFailure returned kept partial winner loser duplicateFailure value before after)
 where
  classify
    :: High.NativeArenaFinalResult
    -> High.NativeArenaFinalResult
    -> IO
         ( High.NativeAlphaZeroReturnedData
         , Arena.RawNativeArenaEvaluation
         , High.NativeArenaFailure
         , High.NativeArenaFailure
         )
  classify one two = case (one, two) of
    ( High.NativeArenaFinalFailed raw (Just observed) failure
      , High.NativeArenaFinalFailed _ Nothing duplicate
      )
        | High.nativeAlphaZeroFailureKind duplicate == High.NativeArenaAlreadyConsumed ->
            pure (raw, observed, failure, duplicate)
    ( High.NativeArenaFinalFailed _ Nothing duplicate
      , High.NativeArenaFinalFailed raw (Just observed) failure
      )
        | High.nativeAlphaZeroFailureKind duplicate == High.NativeArenaAlreadyConsumed ->
            pure (raw, observed, failure, duplicate)
    _ ->
      assertFailure "final race did not have exactly one real failed evaluation and one consumed loser"
        >> fail "unreachable"

data Resources = Resources Fixture FinalFailure
resources :: IO Resources
resources = Resources <$> makeFixture <*> makeFinalFailure
getFixture :: IO Resources -> IO Fixture
getFixture get = do Resources actual _ <- get; pure actual
getFinalFailure :: IO Resources -> IO FinalFailure
getFinalFailure get = do Resources _ actual <- get; pure actual

initialFailure
  :: ScalarFault -> IO (High.NativeArenaFailure, High.NativeArenaFailure, Trace, Integer, Integer)
initialFailure fault = do
  selected <- child "connect4"
  control <- newControl
  initial <- High.prepareNativeAlphaZeroAttempt selected (device control) >>= prepared
  enter control InitialScoring
  writeIORef (controlFault control) (FailScalarAfter 0 fault)
  first <- High.evaluateNativeAlphaZeroInitial initial
  actual <- case first of
    High.NativeArenaInitialFailed failure -> pure failure
    _ -> assertFailure "bad initial evaluation enabled training" >> fail "unreachable"
  before <- traceTotal <$> readIORef (controlTrace control)
  duplicate <- High.evaluateNativeAlphaZeroInitial initial
  again <- case duplicate of
    High.NativeArenaInitialFailed failure -> pure failure
    _ -> assertFailure "failed initial evaluation retried" >> fail "unreachable"
  after <- traceTotal <$> readIORef (controlTrace control)
  value <- readIORef (controlTrace control)
  pure (actual, again, value, before, after)

trainingFailure
  :: Fault -> IO (High.NativeArenaFailure, High.NativeArenaFailure, Trace, Integer, Integer)
trainingFailure fault = do
  selected <- child "connect4"
  control <- newControl
  (_, enabled) <- makeReady selected control
  enter control Training
  writeIORef (controlFault control) fault
  result <- High.continueNativeAlphaZeroTraining enabled
  actual <- case result of
    High.NativeArenaTrainingFailed failure -> pure failure
    _ -> assertFailure "first gradient failure invented a raw return" >> fail "unreachable"
  before <- traceTotal <$> readIORef (controlTrace control)
  duplicate <- High.continueNativeAlphaZeroTraining enabled
  again <- case duplicate of
    High.NativeArenaTrainingFailed failure -> pure failure
    _ -> assertFailure "failed training was retried" >> fail "unreachable"
  after <- traceTotal <$> readIORef (controlTrace control)
  value <- readIORef (controlTrace control)
  pure (actual, again, value, before, after)

failureArena :: High.NativeArenaFailure -> IO Arena.RawNativeArenaEvaluation
failureArena actual =
  maybe
    (assertFailure "actual partial arena data was lost" >> fail "unreachable")
    pure
    (High.nativeAlphaZeroFailureEvaluation actual)
assertNestedFailure
  :: Arena.NativeArenaFailureKind -> Text -> Arena.RawNativeArenaEvaluation -> Assertion
assertNestedFailure expected fragment actual = case Arena.nativeArenaEvaluationStatus actual of
  Arena.NativeArenaEvaluationFailed _ _ kind detail -> do
    kind @?= expected
    assertBool "specific actual lower failure differs" (fragment `Text.isInfixOf` detail)
  _ -> assertFailure "actual failed arena status was lost"

-- This assertion intentionally demands every rendered field, not just a Show
-- prefix. Replacing it by not.null.show would stop materializing retained data.
{- HLINT ignore assertInspectable "Use null" -}
assertInspectable :: (Show value) => value -> Assertion
assertInspectable value = assertBool "retained actual data still contains a poisonous thunk" (length (show value) > 0)

nativePreparedAlphaZeroAttemptTests :: TestTree
nativePreparedAlphaZeroAttemptTests = withResource resources (const (pure ())) $ \get ->
  testGroup
    "native canonical prepared AlphaZero phases"
    [ testCase "two canonical offline returns preserve initial raw and final phase ordering" $ do
        value <- getFixture get
        FinalFailure second _ _ _ _ _ secondTrace _ _ <- getFinalFailure get
        let before = fixtureBeforeFinal value; after = fixtureAfterFinal value
        map fst (traceMarks before) @?= ["prepared", "initial-ready", "raw-observed"]
        map fst (traceMarks after) @?= ["prepared", "initial-ready", "raw-observed", "final-complete"]
        case map snd (traceMarks after) of
          [p, i, r, f] -> assertBool "actual phase callback prefixes differ" (p > 0 && i > p && r > i && f > r)
          _ -> assertFailure "phase marker inventory differs"
        count FinalScoring ScalarForward before @?= 0
        assertBool
          "separate final actually called the captured device"
          (count FinalScoring ScalarForward after > 0)
        assertBool
          "actual self-play called the captured scalar device"
          (count Training ScalarForward before > 0)
        count Training BatchGradient before @?= 512
        let firstRaw = High.nativeAlphaZeroReturnedRawObservation (fixtureReturned value)
            secondRaw = High.nativeAlphaZeroReturnedRawObservation second
        firstRaw @?= secondRaw
        netBits (Low.alphaZeroObservedFinalNet firstRaw)
          @?= netBits (Low.alphaZeroObservedFinalNet secondRaw)
        adamBits (Low.alphaZeroObservedFinalAdam firstRaw)
          @?= adamBits (Low.alphaZeroObservedFinalAdam secondRaw)
        map fst (traceMarks secondTrace) @?= ["prepared", "initial-ready", "raw-observed"]
    , testCase
        "actual returned generations optimizer state and samples keep the full canonical allocation"
        $ do
          value <- getFixture get
          let selected = fixtureChild value
              plan = High.nativeAlphaZeroChildPlan selected
              snapshot = fixtureSnapshot value
              raw = High.nativeAlphaZeroReturnedRawObservation (fixtureReturned value)
          Plan.quantityValue (Workload.alphaZeroPlanGenerations plan) @?= 64
          Low.alphaZeroObservedGenerationCount raw @?= 64
          Low.alphaZeroObservedGenerationTarget raw @?= 64
          Low.alphaZeroObservedGames raw @?= 2
          Low.alphaZeroObservedSimulations raw @?= 128
          Low.alphaZeroObservedMaxPlies raw @?= 42
          Low.alphaZeroObservedUpdates raw @?= 8
          Low.alphaZeroObservedSeed raw @?= 42
          Mlp.adamStep_ (Low.alphaZeroObservedInitialAdam raw) @?= 0
          Mlp.adamStep_ (Low.alphaZeroObservedFinalAdam raw) @?= 512
          Low.alphaZeroObservedOptimizerApplicationDelta raw @?= 512
          assertBool "full actual sample return was discarded" (not (null (Low.alphaZeroObservedSamples raw)))
          assertBool
            "returned samples exceed the actual declared game and ply allocation"
            (length (Low.alphaZeroObservedSamples raw) <= 64 * 2 * 42)
          High.validateNativeAlphaZeroReturnedData selected snapshot raw @?= Right ()
    , testCase "finite motionless parameters and equal initial final scores remain uncensored data" $ do
        value <- getFixture get
        let returned = fixtureReturned value
            raw = High.nativeAlphaZeroReturnedRawObservation returned
            final = High.nativeAlphaZeroEvaluatedFinalEvaluation (fixtureFinal value)
        netBits (Low.alphaZeroObservedInitialNet raw) @?= netBits (Low.alphaZeroObservedFinalNet raw)
        fixtureInitial value @?= final
        Arena.nativeArenaEvaluationExactScore (fixtureInitial value)
          @?= Arena.nativeArenaEvaluationExactScore final
        High.nativeAlphaZeroReturnedRawObservation
          (High.nativeAlphaZeroEvaluatedReturnedData (fixtureFinal value))
          @?= raw
        assertComplete (fixtureChild value) (Low.alphaZeroObservedFinalNet raw) final
    , testCase "actual prepared tensors and Adam bind initial self play update and final callbacks" $ do
        value <- getFixture get
        let snapshot = fixtureSnapshot value
            params = Net.pvnParams (Low.alphaZeroPreparedInitialNet snapshot)
            shape = Mlp.paramShape params
            actual = fixtureAfterFinal value
            raw = High.nativeAlphaZeroReturnedRawObservation (fixtureReturned value)
        netBits (Low.alphaZeroPreparedInitialNet snapshot) @?= netBits (Low.alphaZeroObservedInitialNet raw)
        adamBits (Low.alphaZeroPreparedInitialAdam snapshot)
          @?= adamBits (Low.alphaZeroObservedInitialAdam raw)
        forM_
          [ (InitialScoring, ScalarForward)
          , (Training, ScalarForward)
          , (Training, BatchForward)
          , (Training, BatchGradient)
          , (FinalScoring, ScalarForward)
          ]
          $ \(phase, operation) ->
            assertSameParams params (firstParams phase operation shape actual)
        assertComplete
          (fixtureChild value)
          (Low.alphaZeroPreparedInitialNet snapshot)
          (fixtureInitial value)
    , testCase "all data phases avoid witness queries and unrelated callback routes" $ do
        value <- getFixture get
        FinalFailure _ _ _ _ _ _ finalTrace _ _ <- getFinalFailure get
        forM_ [fixtureAfterFinal value, finalTrace] $ \actual -> do
          assertNoWitness actual
          forM_ [Preparing, InitialScoring, Training, FinalScoring] $ \phase -> do
            count phase Backward actual @?= 0
            count phase InputGradient actual @?= 0
          count Preparing BatchForward actual @?= 1
          count Preparing ScalarForward actual @?= 0
    , testCase "all three consumed positive stages reject before additional callbacks" $ do
        value <- getFixture get
        forM_ (fixtureGuards value) $ \(GuardCheck stage failure before after) -> do
          assertFailureDetail stage High.NativeArenaAlreadyConsumed "already been consumed" failure
          before @?= after
    , testCase
        "whole checked batches select exactly four AlphaZero rows and twenty full children per lane"
        $ do
          forM_ [LinuxCPU, LinuxCUDA, AppleSilicon] $ \lane -> do
            whole <- batch lane
            length (Cohort.nativeRlCohortBatchPlans whole) @?= 43
            accepted <- forM (Cohort.nativeRlCohortBatchPlans whole) $ \cohort -> do
              let name = Matrix.rowId (Cohort.nativeRlCohortPlanRow cohort)
              case High.selectNativeAlphaZeroRowData whole name of
                Left _ -> pure []
                Right row -> do
                  High.nativeAlphaZeroRowId row @?= name
                  High.nativeAlphaZeroRowBatch row @?= whole
                  forM Cohort.nativeSeedIndices $ \index -> do
                    actual <- selection (High.selectNativeAlphaZeroChildData row index)
                    let seedPlan = High.nativeAlphaZeroChildSeedPlan actual
                        plan = High.nativeAlphaZeroChildPlan actual
                        singleton = Cohort.nativeRlSeedPlanSingleton seedPlan
                    Cohort.nativeRlSeedPlanIndex seedPlan @?= index
                    Cohort.nativeRlSeedPlanSeed seedPlan @?= fromIntegral (42 + Cohort.nativeSeedIndexValue index)
                    Native.nativeSingletonSubstrate singleton @?= lane
                    Native.nativeSingletonAlphaZeroPlan singleton @?= Just plan
                    Native.nativeSingletonPlanId singleton @?= Workload.alphaZeroPlanId plan
                    pure ()
            length (filter (not . null) accepted) @?= 4
            sum (map length accepted) @?= 20
    , testCase "all thirty nine non AlphaZero rows and absent names reject before a device is supplied" $ do
        whole <- batch LinuxCPU
        let excluded =
              [ Matrix.rowId (Cohort.nativeRlCohortPlanRow cohort)
              | cohort <- Cohort.nativeRlCohortBatchPlans whole
              , case Cohort.nativeRlSeedPlanAlphaZero (Cohort.nativeRlCohortServingChild cohort) of
                  Nothing -> True
                  Just _ -> False
              ]
        length excluded @?= 39
        forM_ (excluded <> ["absent-native-row"]) $ \name -> case High.selectNativeAlphaZeroRowData whole name of
          Left failure -> do
            High.nativeAlphaZeroFailureStage failure @?= High.NativeArenaSelection
            High.nativeAlphaZeroFailureKind failure @?= High.NativeArenaContextRejected
          Right _ -> assertFailure "nonarena row acquired a high AlphaZero selection"
    , testCase "child zero retains the full game workload identity transport and serving association" $ do
        whole <- batch LinuxCPU
        zero <- indexZero
        forM_ ["connect4", "othello", "hex", "gomoku"] $ \game -> do
          row <- selection (High.selectNativeAlphaZeroRowData whole game)
          selected <- selection (High.selectNativeAlphaZeroChildData row zero)
          let seedPlan = High.nativeAlphaZeroChildSeedPlan selected; plan = High.nativeAlphaZeroChildPlan selected
          seedPlan @?= Cohort.nativeRlCohortServingChild (High.nativeAlphaZeroRowCohort row)
          Workload.renderAlphaZeroGame (Workload.alphaZeroPlanGame plan) @?= game
          Native.nativeSingletonPlanId (Cohort.nativeRlSeedPlanSingleton seedPlan)
            @?= Workload.alphaZeroPlanId plan
          case Workload.parseAlphaZeroPlanTransport (Workload.renderAlphaZeroPlanTransport plan) of
            Plan.Success actual -> do
              Workload.alphaZeroPlanId actual @?= Workload.alphaZeroPlanId plan
              Workload.renderAlphaZeroGame (Workload.alphaZeroPlanGame actual) @?= game
            Plan.Failure _ -> assertFailure "actual full AlphaZero transport did not re-admit as data"
          case Cohort.nativeRlCohortPlanProjection (High.nativeAlphaZeroRowCohort row) of
            Matrix.SomeProductProjection Plan.AlphaZeroSelfPlayWitness projection -> Matrix.productProjectionPlanId projection @?= Workload.alphaZeroPlanId plan
            _ -> assertFailure "arena selection lost full workload kind"
    , testCase "one row tape is shared unchanged across all five independent training seeds" $ do
        whole <- batch LinuxCPU
        row <- selection (High.selectNativeAlphaZeroRowData whole "connect4")
        actual <- forM Cohort.nativeSeedIndices $ \index -> do
          selected <- selection (High.selectNativeAlphaZeroChildData row index)
          let retained = High.nativeAlphaZeroChildRow selected; tape = High.nativeAlphaZeroRowTape retained
          Tape.arenaTapeBytes tape @?= Tape.arenaTapeBytes (High.nativeAlphaZeroRowTape row)
          Tape.arenaTapeSha256 tape @?= Tape.arenaTapeSha256 (High.nativeAlphaZeroRowTape row)
          Tape.arenaTapeSpecBase (Tape.arenaTapeSpec tape) @?= 7961
          Tape.arenaTapeSpecGames (Tape.arenaTapeSpec tape) @?= 9
          Tape.arenaTapeSpecMaxPlies (Tape.arenaTapeSpec tape) @?= 42
          pure (Cohort.nativeRlSeedPlanSeed (High.nativeAlphaZeroChildSeedPlan selected))
        actual @?= [42, 43, 44, 45, 46]
    , testCase "seedless reference declarations rebuild actual seeded child budgets without conflation" $ do
        whole <- batch LinuxCPU
        forM_ ["connect4", "othello", "hex", "gomoku"] $ \game -> do
          row <- selection (High.selectNativeAlphaZeroRowData whole game)
          let declared = Ref.nativeArenaSpecTrainingBudget (High.nativeAlphaZeroRowSpec row)
          Budget.trainingBudgetSeed declared @?= Nothing
          forM_ Cohort.nativeSeedIndices $ \index -> do
            selected <- selection (High.selectNativeAlphaZeroChildData row index)
            let seedPlan = High.nativeAlphaZeroChildSeedPlan selected
                plan = High.nativeAlphaZeroChildPlan selected
                seed = Cohort.nativeRlSeedPlanSeed seedPlan
            expected <-
              right
                ( Budget.mkTrainingBudget
                    (Budget.trainingBudgetKind declared)
                    (Budget.trainingBudgetTargetUnits declared)
                    (Just seed)
                )
            Cohort.nativeRlSeedPlanTrainingBudget seedPlan @?= expected
            Plan.quantityValue (Workload.alphaZeroPlanGenerations plan)
              @?= Budget.trainingBudgetTargetUnits declared
            NE.toList (Plan.seedCohortValues (Plan.runPlanSeeds (Workload.alphaZeroPlanRunPlan plan)))
              @?= [seed]
    , testCase "all actual prepared recipe fields match the full public child plan" $ do
        value <- getFixture get
        let selected = fixtureChild value
            snapshot = fixtureSnapshot value
            plan = High.nativeAlphaZeroChildPlan selected
            asInt = fromIntegral :: Word64 -> Int
        High.validateNativeAlphaZeroPreparedData selected snapshot @?= Right ()
        Low.alphaZeroPreparedGame snapshot
          @?= Workload.renderAlphaZeroGame (Workload.alphaZeroPlanGame plan)
        Low.alphaZeroPreparedInitialState snapshot
          @?= Game.initialStateFor (Low.alphaZeroPreparedGame snapshot)
        Low.alphaZeroPreparedHiddenUnits snapshot @?= Low.canonicalAlphaZeroHiddenUnits
        Low.alphaZeroPreparedGenerationTarget snapshot
          @?= asInt (Plan.quantityValue (Workload.alphaZeroPlanGenerations plan))
        Low.alphaZeroPreparedGames snapshot
          @?= asInt (Plan.quantityValue (Workload.alphaZeroPlanSelfPlayGames plan))
        Low.alphaZeroPreparedSimulations snapshot
          @?= asInt (Plan.quantityValue (Workload.alphaZeroPlanMctsSimulations plan))
        Low.alphaZeroPreparedMaxPlies snapshot
          @?= asInt (Plan.quantityValue (Workload.alphaZeroPlanMaxPlies plan))
        Low.alphaZeroPreparedUpdates snapshot
          @?= asInt (Plan.quantityValue (Workload.alphaZeroPlanUpdates plan))
        Low.alphaZeroPreparedSeed snapshot
          @?= asInt (Cohort.nativeRlSeedPlanSeed (High.nativeAlphaZeroChildSeedPlan selected))
        Mlp.paramShape (Net.pvnParams (Low.alphaZeroPreparedInitialNet snapshot))
          @?= Mlp.MlpShape 8 Low.canonicalAlphaZeroHiddenUnits 8
    , testCase "an actual snapshot cannot be rebound to another game or auxiliary seed" $ do
        value <- getFixture get
        whole <- batch LinuxCPU
        row <- selection (High.selectNativeAlphaZeroRowData whole "connect4")
        next <- case Cohort.nativeSeedIndices of
          _ : second : _ -> pure second
          _ -> assertFailure "canonical second index absent" >> fail "unreachable"
        auxiliary <- selection (High.selectNativeAlphaZeroChildData row next)
        other <- child "othello"
        forM_ [auxiliary, other] $ \selected -> do
          rejects
            "prepared schedule differs"
            (High.validateNativeAlphaZeroPreparedData selected (fixtureSnapshot value))
          rejects
            "prepared schedule differs"
            ( High.validateNativeAlphaZeroReturnedData
                selected
                (fixtureSnapshot value)
                (High.nativeAlphaZeroReturnedRawObservation (fixtureReturned value))
            )
    , testCase "actual probe Left and exception stop before snapshot initial arena or training" $ do
        forM_
          [ (FailProbe, High.NativeArenaLowRejected, "probe Left")
          , (ThrowProbe, High.NativeArenaSynchronousFailure, "probe exception")
          ]
          $ \(fault, kind, fragment) -> do
            selected <- child "connect4"
            control <- newControl
            writeIORef (controlFault control) fault
            result <- High.prepareNativeAlphaZeroAttempt selected (device control)
            case result of
              High.NativeArenaPreparationFailed failure -> do
                assertFailureDetail High.NativeArenaPreparation kind fragment failure
                High.nativeAlphaZeroFailureSnapshot failure @?= Nothing
                High.nativeAlphaZeroFailureEvaluation failure @?= Nothing
              _ -> assertFailure "failed actual probe created a prepared stage"
            actual <- readIORef (controlTrace control)
            count Preparing BatchForward actual @?= 1
            count Preparing ScalarForward actual @?= 0
            count Training BatchGradient actual @?= 0
            assertNoWitness actual
    , testCase
        "unmaterializable child input retains no unsafe selection or snapshot and makes no callback"
        $ do
          control <- newControl
          result <-
            High.prepareNativeAlphaZeroAttempt (error "unmaterializable AlphaZero child") (device control)
          case result of
            High.NativeArenaPreparationFailed failure -> do
              assertFailureDetail
                High.NativeArenaPreparation
                High.NativeArenaSynchronousFailure
                "unmaterializable AlphaZero child"
                failure
              case High.nativeAlphaZeroFailureChild failure of
                Nothing -> pure ()
                Just _ -> assertFailure "poisoned child was retained"
              High.nativeAlphaZeroFailureSnapshot failure @?= Nothing
            _ -> assertFailure "poisoned child created a stage"
          readIORef (controlTrace control) >>= (@?= 0) . traceTotal
    , testCase
        "initial callback Left retains actual partial search and prevents every training continuation"
        $ do
          (failure, duplicate, actual, before, after) <- initialFailure ScalarLeft
          assertFailureDetail
            High.NativeArenaInitialEvaluation
            High.NativeArenaEvaluationRejected
            "observation is incomplete"
            failure
          assertFailureDetail
            High.NativeArenaInitialEvaluation
            High.NativeArenaAlreadyConsumed
            "already been consumed"
            duplicate
          observed <- failureArena failure
          assertNestedFailure
            Arena.NativeArenaSearchRejected
            "explicit offline AlphaZero scalar Left"
            observed
          Arena.nativeArenaEvaluationWork observed
            @?= Arena.NativeArenaEvaluationWork 0 0 0 Arena.UnknownUnfinishedArenaSearch
          Arena.nativeArenaEvaluationEpisodes observed @?= []
          High.nativeAlphaZeroFailureInitialEvaluation failure @?= Nothing
          count InitialScoring ScalarForward actual @?= 1
          count Training ScalarForward actual @?= 0
          count Training BatchGradient actual @?= 0
          before @?= after
          assertInspectable observed
    , testCase "initial synchronous and lazy callback failures retain fully inspectable actual data" $ do
        forM_
          [ (ScalarThrow, "scalar exception")
          , (ScalarLazyOuter, "lazy offline AlphaZero Either")
          , (ScalarLazyLeft, "lazy offline AlphaZero Left text")
          , (ScalarLazyForward, "lazy offline AlphaZero forward")
          ]
          $ \(fault, fragment) -> do
            (failure, duplicate, actual, before, after) <- initialFailure fault
            assertFailureDetail
              High.NativeArenaInitialEvaluation
              High.NativeArenaEvaluationRejected
              "observation is incomplete"
              failure
            observed <- failureArena failure
            assertNestedFailure Arena.NativeArenaSearchException fragment observed
            assertInspectable observed
            assertFailureDetail
              High.NativeArenaInitialEvaluation
              High.NativeArenaAlreadyConsumed
              "already been consumed"
              duplicate
            before @?= after
            count Training BatchGradient actual @?= 0
    , testCase "wrong shape NaN and Float32 overflow fail through the actual initial guarded oracle" $ do
        forM_ [ScalarWrongShape, ScalarNonfinite, ScalarOverflow] $ \fault -> do
          (failure, _, actual, _, _) <- initialFailure fault
          observed <- failureArena failure
          assertNestedFailure
            Arena.NativeArenaSearchRejected
            "output has the wrong shape or is not finite Float32"
            observed
          case Arena.nativeArenaFailedForward (Arena.nativeArenaEvaluationForwards observed) of
            Just forward -> case Arena.nativeArenaForwardOutcome forward of
              Arena.NativeArenaForwardReturned (Right _) -> pure ()
              _ -> assertFailure "actual malformed Right was relabeled"
            Nothing -> assertFailure "malformed actual callback observation was discarded"
          count InitialScoring ScalarForward actual @?= 1
          count Training BatchGradient actual @?= 0
    , testCase "initial asynchronous cancellation propagates and its claim stays consumed" $ do
        selected <- child "connect4"
        control <- newControl
        initial <- High.prepareNativeAlphaZeroAttempt selected (device control) >>= prepared
        enter control InitialScoring
        writeIORef (controlFault control) (FailScalarAfter 0 ScalarAsync)
        result <-
          try (High.evaluateNativeAlphaZeroInitial initial)
            :: IO (Either AsyncException High.NativeArenaInitialResult)
        case result of
          Left ThreadKilled -> pure ()
          _ -> assertFailure "initial async was swallowed or relabeled"
        before <- traceTotal <$> readIORef (controlTrace control)
        duplicate <- High.evaluateNativeAlphaZeroInitial initial
        case duplicate of
          High.NativeArenaInitialFailed failure ->
            assertFailureDetail
              High.NativeArenaInitialEvaluation
              High.NativeArenaAlreadyConsumed
              "already been consumed"
              failure
          _ -> assertFailure "cancelled initial was retried"
        after <- traceTotal <$> readIORef (controlTrace control)
        before @?= after
        actual <- readIORef (controlTrace control)
        count InitialScoring ScalarForward actual @?= 1
        count Training BatchGradient actual @?= 0
    , testCase "concurrent initial claims have one actual callback and one consumed loser" $ do
        selected <- child "connect4"
        control <- newControl
        initial <- High.prepareNativeAlphaZeroAttempt selected (device control) >>= prepared
        enter control InitialScoring
        writeIORef (controlFault control) (FailScalarAfter 0 ScalarLeft)
        (one, two) <- parallel (High.evaluateNativeAlphaZeroInitial initial)
        kinds <- forM [one, two] $ \case
          High.NativeArenaInitialFailed failure -> pure (High.nativeAlphaZeroFailureKind failure)
          _ -> assertFailure "bad concurrent initial scoring created a Ready" >> fail "unreachable"
        length (filter (== High.NativeArenaEvaluationRejected) kinds) @?= 1
        length (filter (== High.NativeArenaAlreadyConsumed) kinds) @?= 1
        actual <- readIORef (controlTrace control)
        count InitialScoring ScalarForward actual @?= 1
        count Training BatchGradient actual @?= 0
    , testCase
        "first actual optimizer Left retains initial observations without inventing raw state or retrying"
        $ do
          (failure, duplicate, actual, before, after) <- trainingFailure FailGradient
          assertFailureDetail High.NativeArenaTraining High.NativeArenaLowRejected "gradient Left" failure
          assertFailureDetail
            High.NativeArenaTraining
            High.NativeArenaAlreadyConsumed
            "already been consumed"
            duplicate
          case High.nativeAlphaZeroFailureInitialEvaluation failure of
            Just initial -> Arena.nativeArenaEvaluationStatus initial @?= Arena.NativeArenaEvaluationComplete
            Nothing -> assertFailure "accepted initial observations were lost"
          count Training BatchGradient actual @?= 1
          count Training BatchForward actual @?= 1
          assertBool "the real first generation was skipped" (count Training ScalarForward actual > 0)
          count FinalScoring ScalarForward actual @?= 0
          before @?= after
    , testCase "first actual optimizer exception preserves prior data and cannot restart the schedule" $ do
        (failure, duplicate, actual, before, after) <- trainingFailure ThrowGradient
        assertFailureDetail
          High.NativeArenaTraining
          High.NativeArenaSynchronousFailure
          "gradient exception"
          failure
        assertFailureDetail
          High.NativeArenaTraining
          High.NativeArenaAlreadyConsumed
          "already been consumed"
          duplicate
        case High.nativeAlphaZeroFailureSnapshot failure of
          Just snapshot -> Low.alphaZeroPreparedGenerationTarget snapshot @?= 64
          Nothing -> assertFailure "actual snapshot was lost"
        count Training BatchGradient actual @?= 1
        count FinalScoring ScalarForward actual @?= 0
        before @?= after
    , testCase
        "training asynchronous cancellation propagates after the actual first generation and consumes Ready"
        $ do
          selected <- child "connect4"
          control <- newControl
          (_, enabled) <- makeReady selected control
          enter control Training
          writeIORef (controlFault control) CancelGradient
          result <-
            try (High.continueNativeAlphaZeroTraining enabled)
              :: IO (Either AsyncException High.NativeArenaTrainingResult)
          case result of
            Left ThreadKilled -> pure ()
            _ -> assertFailure "training async became a returned or failed model"
          before <- traceTotal <$> readIORef (controlTrace control)
          duplicate <- High.continueNativeAlphaZeroTraining enabled
          case duplicate of
            High.NativeArenaTrainingFailed failure ->
              assertFailureDetail
                High.NativeArenaTraining
                High.NativeArenaAlreadyConsumed
                "already been consumed"
                failure
            _ -> assertFailure "cancelled Ready retrained"
          after <- traceTotal <$> readIORef (controlTrace control)
          before @?= after
          actual <- readIORef (controlTrace control)
          count Training BatchGradient actual @?= 1
          count FinalScoring ScalarForward actual @?= 0
    , testCase
        "concurrent Ready claims start only one genuine first generation and one optimizer callback"
        $ do
          selected <- child "connect4"
          control <- newControl
          (_, enabled) <- makeReady selected control
          enter control Training
          writeIORef (controlFault control) FailGradient
          (one, two) <- parallel (High.continueNativeAlphaZeroTraining enabled)
          kinds <- forM [one, two] $ \case
            High.NativeArenaTrainingFailed failure -> pure (High.nativeAlphaZeroFailureKind failure)
            _ -> assertFailure "concurrent first gradient failure invented a raw return" >> fail "unreachable"
          length (filter (== High.NativeArenaLowRejected) kinds) @?= 1
          length (filter (== High.NativeArenaAlreadyConsumed) kinds) @?= 1
          actual <- readIORef (controlTrace control)
          count Training BatchGradient actual @?= 1
          count Training BatchForward actual @?= 1
          assertBool "actual self-play prefix was absent" (count Training ScalarForward actual > 0)
    , testCase "a separate full return remains bit exact before and after actual final evaluation failure" $ do
        FinalFailure before after partial failure _ _ actual _ _ <- getFinalFailure get
        let raw = High.nativeAlphaZeroReturnedRawObservation before
        High.nativeAlphaZeroReturnedRawObservation after @?= raw
        netBits (Low.alphaZeroObservedInitialNet (High.nativeAlphaZeroReturnedRawObservation after))
          @?= netBits (Low.alphaZeroObservedInitialNet raw)
        netBits (Low.alphaZeroObservedFinalNet (High.nativeAlphaZeroReturnedRawObservation after))
          @?= netBits (Low.alphaZeroObservedFinalNet raw)
        adamBits (Low.alphaZeroObservedFinalAdam (High.nativeAlphaZeroReturnedRawObservation after))
          @?= adamBits (Low.alphaZeroObservedFinalAdam raw)
        High.nativeAlphaZeroReturnedInitialEvaluation after
          @?= High.nativeAlphaZeroReturnedInitialEvaluation before
        assertFailureDetail
          High.NativeArenaFinalEvaluation
          High.NativeArenaEvaluationRejected
          "observation is incomplete"
          failure
        assertNestedFailure Arena.NativeArenaSearchRejected "explicit offline AlphaZero scalar Left" partial
        count Training BatchGradient actual @?= 512
        assertInspectable raw
        assertInspectable partial
    , testCase "final failure preserves exact complete case prefix and Unknown unfinished search work" $ do
        FinalFailure returned _ partial _ _ _ _ _ _ <- getFinalFailure get
        let initial = High.nativeAlphaZeroReturnedInitialEvaluation returned
        case (Arena.nativeArenaEvaluationEpisodes initial, Arena.nativeArenaEvaluationEpisodes partial) of
          (first : _, [kept]) -> do
            kept @?= first
            Arena.nativeArenaCompletedEpisodeTransitions (Arena.nativeArenaEvaluationWork partial)
              @?= toInteger (length (Ref.nativeArenaEpisodeDecisions first))
            Arena.nativeArenaCompletedSearchRootVisits (Arena.nativeArenaEvaluationWork partial)
              @?= sum
                (map (toInteger . Ref.nativeArenaDecisionSearchRootVisits) (Ref.nativeArenaEpisodeDecisions first))
          _ -> assertFailure "actual complete first case was lost or changed"
        Arena.nativeArenaCurrentEpisodeTransitions (Arena.nativeArenaEvaluationWork partial) @?= 0
        Arena.nativeArenaUnfinishedSearch (Arena.nativeArenaEvaluationWork partial)
          @?= Arena.UnknownUnfinishedArenaSearch
        Arena.nativeArenaEvaluationExactScore partial @?= Nothing
    , testCase
        "concurrent and duplicate final claims consume only one real final attempt without retraining"
        $ do
          FinalFailure _ _ partial winner loser duplicate actual before after <- getFinalFailure get
          assertFailureDetail
            High.NativeArenaFinalEvaluation
            High.NativeArenaEvaluationRejected
            "observation is incomplete"
            winner
          assertFailureDetail
            High.NativeArenaFinalEvaluation
            High.NativeArenaAlreadyConsumed
            "already been consumed"
            loser
          assertFailureDetail
            High.NativeArenaFinalEvaluation
            High.NativeArenaAlreadyConsumed
            "already been consumed"
            duplicate
          count FinalScoring ScalarForward actual
            @?= Arena.nativeArenaForwardCalls (Arena.nativeArenaEvaluationForwards partial)
          count Training BatchGradient actual @?= 512
          before @?= after
    , testCase "public high data predicates reject missing duplicate reordered cases and false work" $ do
        value <- getFixture get
        let selected = fixtureChild value
            net = Low.alphaZeroPreparedInitialNet (fixtureSnapshot value)
            raw = fixtureInitial value
        case Arena.nativeArenaEvaluationEpisodes raw of
          first : rest -> forM_ [rest, first : first : rest, reverse (first : rest)] $ \episodes ->
            rejects
              "case inventory differs"
              ( High.validateNativeAlphaZeroEvaluationData
                  selected
                  net
                  (raw {Arena.nativeArenaEvaluationEpisodes = episodes})
              )
          [] -> assertFailure "canonical complete nine cases absent"
        rejects
          "complete work differs"
          ( High.validateNativeAlphaZeroEvaluationData
              selected
              net
              ( raw
                  { Arena.nativeArenaEvaluationWork =
                      Arena.NativeArenaEvaluationWork 0 0 0 Arena.NoUnfinishedArenaSearch
                  }
              )
          )
    , testCase
        "public high data predicates retain exact tensor and tape binding rather than Eq signed zero"
        $ do
          value <- getFixture get
          let selected = fixtureChild value
              net = Low.alphaZeroPreparedInitialNet (fixtureSnapshot value)
              raw = fixtureInitial value
              params = Net.pvnParams net
              originalBias = Mlp.paramB1 params
              signedBias = VU.map (toggleSign 0x8000000000000000) originalBias
              changed = net {Net.pvnParams = params {Mlp.paramB1 = signedBias}}
          assertBool "signed-zero original bias is nonempty" (not (VU.null originalBias))
          assertBool "signed-zero original bias is numerically zero" (VU.all (== 0) originalBias)
          signedBias @?= originalBias
          assertBool
            "signed-zero bias mutation changes actual stored bits"
            (vectorBits signedBias /= vectorBits originalBias)
          rejects "supplied context differs" (High.validateNativeAlphaZeroEvaluationData selected changed raw)
          otherTape <- Tape.materializeArenaTape <$> right (Tape.mkArenaTapeSpec "connect4" 7962 9 42)
          case Arena.nativeArenaEvaluationInput raw of
            Just input ->
              rejects
                "supplied context differs"
                ( High.validateNativeAlphaZeroEvaluationData
                    selected
                    net
                    (raw {Arena.nativeArenaEvaluationInput = Just (input {Arena.nativeArenaInputTape = otherTape})})
                )
            Nothing -> assertFailure "actual complete input absent"
    , testCase "actual decision action and visit substitutions cannot pass the high unit predicate" $ do
        value <- getFixture get
        let raw = fixtureInitial value
            selected = fixtureChild value
            net = Low.alphaZeroPreparedInitialNet (fixtureSnapshot value)
        case Arena.nativeArenaEvaluationEpisodes raw of
          episode : rest -> case Ref.nativeArenaEpisodeDecisions episode of
            decision : later -> do
              let mutate changed =
                    raw
                      { Arena.nativeArenaEvaluationEpisodes =
                          episode {Ref.nativeArenaEpisodeDecisions = changed : later} : rest
                      }
              rejects
                "sampled action or transition differs"
                ( High.validateNativeAlphaZeroEvaluationData
                    selected
                    net
                    (mutate (decision {Ref.nativeArenaDecisionAction = 7}))
                )
              rejects
                "tape or actual search visits differ"
                ( High.validateNativeAlphaZeroEvaluationData
                    selected
                    net
                    (mutate (decision {Ref.nativeArenaDecisionSearchRootVisits = 47}))
                )
            [] -> assertFailure "actual first decision absent"
          [] -> assertFailure "actual first case absent"
    , testCase
        "actual Othello pass history beyond sixty tokens counts placements and remains valid sample data"
        $ do
          selected <- child "othello"
          let before = othelloPlacement58
              passed = Game.normaliseForcedPass before
              state = othelloPlacement59
              sample = Net.PolicyValueTrainingSample state (VU.generate 64 (\i -> if i == 62 then 1 else 0)) 0
          placementCount before @?= 58
          Game.legalMoves before @?= []
          length (Game.gameMoves passed) @?= length (Game.gameMoves before) + 1
          placementCount passed @?= 58
          Game.gameMoves state @?= retainedOthelloHistory61
          Game.gameCurrentPlayer state @?= -1
          Game.gameOutcome state @?= Game.GameInProgress
          Game.legalMoves state @?= [62]
          length (Game.gameMoves state) @?= 61
          placementCount state @?= 59
          length (filter (== (-1)) (Game.gameMoves state)) @?= 2
          High.validateNativeAlphaZeroTrainingSampleData selected sample @?= Right ()
          placementCount (Game.applyMove 62 state) @?= 60
    , testCase
        "missing spurious and non Othello pass markers reject through the same actual binder predicate"
        $ do
          selected <- child "othello"
          let state = othelloPlacement59
              distribution = VU.generate 64 (\i -> if i == 62 then 1 else 0)
              make actual = Net.PolicyValueTrainingSample actual distribution 0
          rejects
            "omits a forced pass marker"
            ( High.validateNativeAlphaZeroTrainingSampleData
                selected
                (make (state {Game.gameMoves = removeFirstPass (Game.gameMoves state)}))
            )
          rejects
            "spurious or non-Othello pass marker"
            ( High.validateNativeAlphaZeroTrainingSampleData
                selected
                (make (state {Game.gameMoves = (-1) : Game.gameMoves state}))
            )
          rejects
            "placement is illegal"
            ( High.validateNativeAlphaZeroTrainingSampleData
                selected
                (make (state {Game.gameMoves = replaceFirstPass (Game.gameMoves state)}))
            )
          rejects
            "state differs from its legal transcript"
            (High.validateNativeAlphaZeroTrainingSampleData selected (make (state {Game.gameCurrentPlayer = 1})))
          c4 <- child "connect4"
          rejects
            "spurious or non-Othello pass marker"
            ( High.validateNativeAlphaZeroTrainingSampleData
                c4
                ( Net.PolicyValueTrainingSample
                    (Game.initialConnect4 {Game.gameMoves = [-1]})
                    (VU.replicate 7 (1 / 7))
                    0
                )
            )
    , testCase "actual returned sample shape finite fields row and placement bounds remain strict" $ do
        value <- getFixture get
        let selected = fixtureChild value
            raw = High.nativeAlphaZeroReturnedRawObservation (fixtureReturned value)
        sample <- firstValue (Low.alphaZeroObservedSamples raw)
        High.validateNativeAlphaZeroTrainingSampleData selected sample @?= Right ()
        forM_
          [ sample {Net.sampleVisitDist = VU.empty}
          , sample {Net.sampleVisitDist = VU.replicate 7 (0 / 0)}
          , sample {Net.sampleOutcome = 1 / 0}
          , sample {Net.sampleState = (Net.sampleState sample) {Game.gameName = "hex"}}
          ]
          $ \bad ->
            rejects
              "fields are malformed or nonfinite"
              (High.validateNativeAlphaZeroTrainingSampleData selected bad)
        othello <- child "othello"
        rejects
          "fields are malformed or nonfinite"
          ( High.validateNativeAlphaZeroTrainingSampleData
              othello
              ( Net.PolicyValueTrainingSample
                  (othelloPlacement59 {Game.gameMoves = retainedOthelloHistory61 <> [62, 62]})
                  (VU.replicate 64 (1 / 64))
                  0
              )
          )
    ]

-- Fixture DATA pinned from the previously retained actual neutral-reference
-- trace; every control reconstructs it with the public game rules, never a
-- duplicated board implementation or a fabricated training return.
othelloPlacement58, othelloPlacement59 :: Game.GameState
othelloPlacement58 =
  foldl'
    (flip Game.applyMove)
    Game.initialOthello
    [ 26
    , 18
    , 19
    , 34
    , 25
    , 32
    , 10
    , 11
    , 12
    , 17
    , 33
    , 41
    , 24
    , 5
    , 40
    , 1
    , 3
    , 29
    , 21
    , 14
    , 50
    , 4
    , 37
    , 9
    , 2
    , 20
    , 16
    , 44
    , 7
    , 13
    , 0
    , 43
    , 38
    , 48
    , 42
    , 8
    , 6
    , 46
    , 54
    , 57
    , 22
    , 39
    , 52
    , 23
    , 47
    , 53
    , 15
    , 51
    , 59
    , 30
    , 56
    , 55
    , 60
    , 45
    , 49
    , 61
    , 58
    , 31
    ]
othelloPlacement59 = Game.applyMove 63 (Game.normaliseForcedPass othelloPlacement58)
retainedOthelloHistory61 :: [Int]
retainedOthelloHistory61 =
  [ 26
  , 18
  , 19
  , 34
  , 25
  , 32
  , 10
  , 11
  , 12
  , 17
  , 33
  , 41
  , 24
  , 5
  , 40
  , 1
  , 3
  , 29
  , 21
  , 14
  , 50
  , 4
  , 37
  , 9
  , 2
  , 20
  , 16
  , 44
  , 7
  , 13
  , 0
  , 43
  , 38
  , 48
  , 42
  , 8
  , 6
  , 46
  , 54
  , 57
  , 22
  , 39
  , 52
  , 23
  , 47
  , 53
  , 15
  , 51
  , 59
  , 30
  , 56
  , 55
  , 60
  , 45
  , 49
  , 61
  , 58
  , -1
  , 31
  , -1
  , 63
  ]
placementCount :: Game.GameState -> Int
placementCount = length . filter (>= 0) . Game.gameMoves
removeFirstPass :: [Int] -> [Int]
removeFirstPass values = case values of [] -> []; (-1) : rest -> rest; value : rest -> value : removeFirstPass rest
replaceFirstPass :: [Int] -> [Int]
replaceFirstPass values = case values of [] -> []; (-1) : rest -> (-2) : rest; value : rest -> value : replaceFirstPass rest
