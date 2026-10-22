{-# LANGUAGE OverloadedStrings #-}

-- | Lossless recorded numerical data. Portable decode is structural only;
-- exact native numerical replay and typed plan binding are explicit operations.
-- None of these operations authenticates a producer or admits a checkpoint.
module JitML.RL.ArsHostTrace
  ( RawArsHostContext (..)
  , ArsHostContext
  , RawArsHostTrace (..)
  , ArsHostTrace
  , arsHostTraceContract
  , arsHostTraceMaxBytes
  , arsHostTraceMaxVectorCoordinates
  , refineArsHostContext
  , arsHostContextToRaw
  , arsHostContextPlanId
  , arsHostContextLane
  , refineArsHostTrace
  , arsHostTraceToRaw
  , arsHostTraceContext
  , arsHostTraceObservation
  , arsHostTraceRuntime
  , encodeArsHostTrace
  , decodeArsHostTrace
  , arsHostTraceSha256
  , arsHostTraceContextSha256
  , arsHostTraceRecordedReference
  , validateArsHostTraceReference
  , arsHostTraceCoordinateCount
  , validateArsHostConfigForPlan
  , resolveArsHostPlanData
  , validateArsHostTracePlan
  , validateArsHostTraceLocal
  ) where

import Control.Monad (unless, when, zipWithM_)
import Control.Monad.State.Strict (StateT (StateT), get, put, runStateT)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.Bits (shiftL, shiftR, (.&.), (.|.))
import Data.ByteString qualified as BS
import Data.ByteString.Builder qualified as B
import Data.ByteString.Lazy qualified as LBS
import Data.Char (intToDigit)
import Data.Foldable (traverse_)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as UTF8
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64, Word8)
import GHC.Float (castDoubleToWord64, castWord64ToDouble)

import JitML.Plan.Plan (PlanId, refinePlanIdText)
import JitML.Product.ArsHostReference qualified as Reference
import JitML.RL.Algorithms.ArsTrainer qualified as Ars
import JitML.RL.Algorithms.Common qualified as Common
import JitML.RL.ProductBudget qualified as Budget
import JitML.RL.Simulator qualified as Sim
import JitML.Substrate (Substrate, parseSubstrate, renderSubstrate)

arsHostTraceContract :: Text
arsHostTraceContract = "ars-host-linear-recorded-trace-native-replay-v1"

arsHostTraceMaxBytes, arsHostTraceMaxVectorCoordinates :: Integer
arsHostTraceMaxBytes = 67108864
arsHostTraceMaxVectorCoordinates = 4000000

-- These are recorded claims, never an actual origin capability.
data RawArsHostContext = RawArsHostContext
  { rawArsHostRowId :: !Text
  , rawArsHostExperiment :: !Text
  , rawArsHostPlanId :: !Text
  , rawArsHostCompiledTransport :: !Text
  , rawArsHostLane :: !Text
  , rawArsHostSourceSha256 :: !Text
  , rawArsHostExecutableSha256 :: !Text
  , rawArsHostInvocationSha256 :: !Text
  , rawArsHostExecutionBinding :: !Text
  , rawArsHostKernelOS :: !Text
  , rawArsHostKernelMachine :: !Text
  , rawArsHostKernelRelease :: !Text
  , rawArsHostSimulatorContract :: !Text
  , rawArsHostProcessId :: !Text
  , rawArsHostAttemptId :: !Text
  }
  deriving stock (Eq, Show)

data ArsHostContext = ArsHostContext !RawArsHostContext !PlanId !Substrate
  deriving stock (Eq, Show)

arsHostContextToRaw :: ArsHostContext -> RawArsHostContext
arsHostContextToRaw (ArsHostContext raw _ _) = raw

arsHostContextPlanId :: ArsHostContext -> PlanId
arsHostContextPlanId (ArsHostContext _ plan _) = plan

arsHostContextLane :: ArsHostContext -> Substrate
arsHostContextLane (ArsHostContext _ _ lane) = lane

data RawArsHostTrace = RawArsHostTrace
  { rawArsHostTraceContext :: !RawArsHostContext
  , rawArsHostTraceRuntime :: !Ars.ArsNumericalRuntime
  , rawArsHostTraceObservation :: !Ars.ArsTrainObservation
  }
  deriving stock (Eq, Show)

-- Equality is wire equality, including every signed-zero bit.
data ArsHostTrace = ArsHostTrace !ArsHostContext !RawArsHostTrace !BS.ByteString
  deriving stock (Show)

instance Eq ArsHostTrace where
  left == right = encodeArsHostTrace left == encodeArsHostTrace right

arsHostTraceToRaw :: ArsHostTrace -> RawArsHostTrace
arsHostTraceToRaw (ArsHostTrace _ raw _) = raw

arsHostTraceContext :: ArsHostTrace -> ArsHostContext
arsHostTraceContext (ArsHostTrace context _ _) = context

arsHostTraceObservation :: ArsHostTrace -> Ars.ArsTrainObservation
arsHostTraceObservation = rawArsHostTraceObservation . arsHostTraceToRaw

arsHostTraceRuntime :: ArsHostTrace -> Ars.ArsNumericalRuntime
arsHostTraceRuntime = rawArsHostTraceRuntime . arsHostTraceToRaw

encodeArsHostTrace :: ArsHostTrace -> BS.ByteString
encodeArsHostTrace (ArsHostTrace _ _ encoded) = encoded

arsHostTraceSha256 :: ArsHostTrace -> Text
arsHostTraceSha256 = hex . SHA256.hash . encodeArsHostTrace

arsHostTraceContextSha256 :: ArsHostTrace -> Text
arsHostTraceContextSha256 = hex . SHA256.hash . build . encodeContext . arsHostContextToRaw . arsHostTraceContext

refineArsHostContext :: RawArsHostContext -> Either Text ArsHostContext
refineArsHostContext raw = do
  traverse_
    (boundedText 1024)
    [ rawArsHostRowId raw
    , rawArsHostExperiment raw
    , rawArsHostLane raw
    , rawArsHostExecutionBinding raw
    , rawArsHostKernelOS raw
    , rawArsHostKernelMachine raw
    , rawArsHostKernelRelease raw
    , rawArsHostSimulatorContract raw
    , rawArsHostProcessId raw
    , rawArsHostAttemptId raw
    ]
  boundedText 32768 (rawArsHostCompiledTransport raw)
  plan <- refinePlanIdText (rawArsHostPlanId raw)
  compiled <- Budget.parseCompiledRlPlanTransport (rawArsHostCompiledTransport raw)
  ensure
    (Budget.renderCompiledRlPlanTransport compiled == rawArsHostCompiledTransport raw)
    "ARS host context compiled transport is not canonical"
  if rawArsHostExecutionBinding raw == "generic-compiled-plan-attempt-v1"
    then do
      ensure
        ( Budget.compiledRlTrainerKind compiled == "ars"
            && rawArsHostRowId raw == "generic-ars/" <> Budget.compiledRlEnvironment compiled
            && rawArsHostPlanId raw == Budget.compiledRlPlanId compiled
        )
        "generic ARS host context differs from its exact compiled identity"
    else do
      ensure
        ( Budget.compiledRlTrainerKind compiled == "ars"
            && rawArsHostRowId raw == "ARS/" <> Budget.compiledRlEnvironment compiled
        )
        "ARS host context row differs from its recorded compiled ARS plan"
      ensure
        ( rawArsHostRowId raw
            `elem` ["ARS/cartpole", "ARS/mountain-car", "ARS/lunar-lander", "ARS/key-door-grid"]
        )
        "ARS host context row is outside the supported ARS product domain"
  lane <- maybe (Left "ARS host context lane is unknown") Right (parseSubstrate (rawArsHostLane raw))
  ensure (renderSubstrate lane == rawArsHostLane raw) "ARS host context lane is not canonical"
  traverse_
    checkedSha
    [rawArsHostSourceSha256 raw, rawArsHostExecutableSha256 raw, rawArsHostInvocationSha256 raw]
  ensure
    ( rawArsHostExecutionBinding raw
        `elem` ["product-scenario-invocation-v1", "direct-local-attempt-v1", "generic-compiled-plan-attempt-v1"]
    )
    "ARS host context execution binding is unknown"
  _ <- Reference.arsHostObjectKey (rawArsHostExperiment raw) (Text.replicate 64 "0")
  ensure
    (toInteger (BS.length (build (encodeContext raw))) <= 65536)
    "ARS host context exceeds its encoded byte limit"
  pure (ArsHostContext raw plan lane)

refineArsHostTrace :: RawArsHostTrace -> Either Text ArsHostTrace
refineArsHostTrace raw = do
  context <- refineArsHostContext (rawArsHostTraceContext raw)
  validateRuntime (rawArsHostTraceRuntime raw)
  validateStructure raw
  let encoded = build (encodeRawTrace raw)
  ensure
    (toInteger (BS.length encoded) <= arsHostTraceMaxBytes)
    "ARS host trace exceeds its byte limit"
  pure (ArsHostTrace context raw encoded)

-- Portable data refinement deliberately does not regenerate Gaussian samples.
validateStructure :: RawArsHostTrace -> Either Text ()
validateStructure raw = do
  let observed = rawArsHostTraceObservation raw
      config = Common.rawTrainerConfig observed
      dimensions = Ars.arsActionCount config * Ars.arsObsSize config
      runtime = rawArsHostTraceRuntime raw
  _ <- arsHostTraceCoordinateCount config
  exactLength
    "ARS host trace observation count differs"
    (Ars.arsIterations config)
    (Common.rawTrainerStats observed)
  vectorShape dimensions (Common.rawTrainerInitialParams observed)
  vectorShape dimensions (Common.rawTrainerFinalParams observed)
  zipWithM_ (observationShape config runtime dimensions) [0 ..] (Common.rawTrainerStats observed)

observationShape
  :: Ars.ArsTrainConfig
  -> Ars.ArsNumericalRuntime
  -> Int
  -> Int
  -> Ars.ArsIterationObservation
  -> Either Text ()
observationShape config runtime dimensions index observation = do
  let step = Ars.arsObservationAppliedStep observation
      stat = Ars.arsObservationStatistic observation
  ensure
    (build (encodeConfig (Ars.arsStepConfig step)) == build (encodeConfig config))
    "ARS host trace step configuration differs"
  ensure (Ars.arsStepNumericalRuntime step == runtime) "ARS host trace step runtime differs"
  ensure
    (Ars.arsStepIndex step == index && Ars.arsIterIndex stat == index)
    "ARS host trace iteration index differs"
  vectorShape dimensions (Ars.arsStepThetaBefore step)
  vectorShape dimensions (Ars.arsStepThetaAfter step)
  exactLength
    "ARS host trace sampled direction count differs"
    (Ars.arsNumDirections config)
    (Ars.arsStepSampledDirections step)
  traverse_ (vectorShape dimensions) (Ars.arsStepSampledDirections step)
  exactLength
    "ARS host trace evaluated perturbation count differs"
    (Ars.arsNumDirections config)
    (Ars.arsStepEvaluatedPerturbations step)
  traverse_
    ( \((plus, psteps), (minus, msteps), delta) -> do
        finiteValues [plus, minus]
        ensure
          ( psteps >= 0
              && psteps <= Ars.arsMaxEpisodeSteps config
              && msteps >= 0
              && msteps <= Ars.arsMaxEpisodeSteps config
          )
          "ARS host trace perturbation step count is outside its horizon"
        listVectorShape dimensions delta
    )
    (Ars.arsStepEvaluatedPerturbations step)
  exactLength
    "ARS host trace kept direction count differs"
    (Ars.arsTopB config)
    (Ars.arsStepKeptDirections step)
  traverse_
    (\(plus, minus, delta) -> finiteValues [plus, minus] >> listVectorShape dimensions delta)
    (Ars.arsStepKeptDirections step)
  listVectorShape dimensions (Ars.arsStepUpdateDirection step)
  finiteValues
    [ Ars.arsIterMeanReturn stat
    , Ars.arsIterBestReturn stat
    , Ars.arsStepNoiseStd step
    , Ars.arsStepReturnStdDev step
    , Ars.arsStepScale step
    ]
  ensure
    ( Ars.arsStepObservedTransitions step >= 0
        && Ars.arsStepObservedTransitions step <= toInteger (maxBound :: Word64)
    )
    "ARS host trace step transitions exceed Word64"

arsHostTraceCoordinateCount :: Ars.ArsTrainConfig -> Either Text Integer
arsHostTraceCoordinateCount config = do
  let iterations = toInteger (Ars.arsIterations config)
      directions = toInteger (Ars.arsNumDirections config)
      topB = toInteger (Ars.arsTopB config)
      dimension = toInteger (Ars.arsActionCount config) * toInteger (Ars.arsObsSize config)
      coordinates = 2 * dimension + iterations * (3 + 2 * directions + topB) * dimension
  ensure
    ( iterations >= 0
        && iterations <= 4096
        && directions > 0
        && directions <= 1024
        && topB > 0
        && topB <= directions
        && Ars.arsActionCount config > 0
        && Ars.arsObsSize config > 0
        && dimension <= 4096
        && dimension <= toInteger (maxBound :: Int)
        && Ars.arsMaxEpisodeSteps config > 0
        && Ars.arsMaxEpisodeSteps config <= 10000000
    )
    "ARS host trace configuration exceeds its resource limits"
  finiteValues [Ars.arsStepSize config, Ars.arsNoiseStd config]
  ensure
    (Ars.arsStepSize config >= 0 && Ars.arsNoiseStd config > 0)
    "ARS host trace configuration has invalid scales"
  ensure
    (coordinates <= arsHostTraceMaxVectorCoordinates)
    "ARS host trace vector-coordinate budget exceeded"
  pure coordinates

validateArsHostTraceLocal :: ArsHostTrace -> Either Text ()
validateArsHostTraceLocal trace = do
  ensure
    (arsHostTraceRuntime trace == Ars.arsNativeNumericalRuntime)
    "ARS host trace numerical runtime differs from the current replay runtime"
  Ars.validateArsTrainObservation (arsHostTraceObservation trace)

validateArsHostConfigForPlan :: Budget.CompiledRlPlan -> Ars.ArsTrainConfig -> Either Text ()
validateArsHostConfigForPlan plan config = do
  reparsed <- Budget.parseCompiledRlPlanTransport (Budget.renderCompiledRlPlanTransport plan)
  ensure
    (reparsed == plan)
    "ARS host supplied compiled plan differs from its public compiler projection"
  ensure (Budget.compiledRlTrainerKind plan == "ars") "ARS host typed plan is not ARS"
  schedule <- case Budget.compiledRlSchedule plan of
    Just value@Budget.ArsTrainingSchedule {} -> Right value
    _ -> Left "ARS host typed plan has no ARS schedule"
  case Sim.lookupSimulatedEnvironmentByName (Budget.compiledRlEnvironment plan) of
    Nothing -> Left "ARS host typed plan environment is unavailable"
    Just (Sim.SomeSimulatedEnvironment environment) -> do
      let expected = arsHostExpectedConfig plan schedule environment
      ensure
        (build (encodeConfig config) == build (encodeConfig expected))
        "ARS host configuration differs from the exact supplied compiled recipe"
      _ <- arsHostTraceCoordinateCount config
      pure ()

-- | Exact compiled recipe DATA only. No canonical Matrix membership,
-- execution, prepared state, producer origin or completion is constructed.
resolveArsHostPlanData
  :: Budget.CompiledRlPlan -> Either Text (Sim.SomeSimulatedEnvironment, Ars.ArsTrainConfig)
resolveArsHostPlanData plan = do
  reparsed <- Budget.parseCompiledRlPlanTransport (Budget.renderCompiledRlPlanTransport plan)
  ensure
    (reparsed == plan)
    "ARS host supplied compiled plan differs from its public compiler projection"
  ensure (Budget.compiledRlTrainerKind plan == "ars") "ARS host typed plan is not ARS"
  schedule <- case Budget.compiledRlSchedule plan of
    Just value@Budget.ArsTrainingSchedule {} -> Right value
    _ -> Left "ARS host typed plan has no ARS schedule"
  case Sim.lookupSimulatedEnvironmentByName (Budget.compiledRlEnvironment plan) of
    Nothing -> Left "ARS host typed plan environment is unavailable"
    Just actual@(Sim.SomeSimulatedEnvironment environment) -> do
      let config = arsHostExpectedConfig plan schedule environment
      _ <- arsHostTraceCoordinateCount config
      pure (actual, config)

-- One shared expression; the existing validator keeps its original guard order.
arsHostExpectedConfig
  :: Budget.CompiledRlPlan
  -> Budget.RlTrainingSchedule
  -> Sim.SimulatedEnvironment state
  -> Ars.ArsTrainConfig
arsHostExpectedConfig plan schedule environment =
  Ars.defaultArsTrainConfig
    { Ars.arsSeed = Budget.compiledRlSeed plan
    , Ars.arsIterations = Budget.scheduleArsIterations schedule
    , Ars.arsNumDirections = Budget.scheduleArsDirections schedule
    , Ars.arsMaxEpisodeSteps = Budget.scheduleArsMaxEpisodeSteps schedule
    , Ars.arsActionCount = Sim.envActionCount environment
    , Ars.arsObsSize = Sim.envObservationSize environment
    }

validateArsHostTracePlan :: Budget.CompiledRlPlan -> ArsHostTrace -> Either Text ()
validateArsHostTracePlan plan trace = do
  let observed = arsHostTraceObservation trace
      rawContext = arsHostContextToRaw (arsHostTraceContext trace)
  ensure
    (Budget.renderCompiledRlPlanTransport plan == rawArsHostCompiledTransport rawContext)
    "ARS host trace transport differs from the supplied compiled plan"
  validateArsHostConfigForPlan plan (Common.rawTrainerConfig observed)
  schedule <-
    maybe (Left "ARS host supplied plan schedule is absent") Right (Budget.compiledRlSchedule plan)
  ensure
    ( Common.observedEnvironmentTransitionCount (Common.rawTrainerCounters observed)
        == Budget.scheduleObservedEnvironmentSteps schedule
    )
    "ARS host trace physical counter differs from the supplied plan budget"
  ensure
    ( toInteger (Common.observedOptimizerUpdateCount (Common.rawTrainerCounters observed))
        == toInteger (Ars.arsIterations (Common.rawTrainerConfig observed))
    )
    "ARS host trace update counter differs from its supplied plan"

arsHostTraceRecordedReference :: ArsHostTrace -> Either Text Reference.ArsHostReference
arsHostTraceRecordedReference trace = do
  let context = arsHostContextToRaw (arsHostTraceContext trace)
      content = arsHostTraceSha256 trace
  key <- Reference.arsHostObjectKey (rawArsHostExperiment context) content
  Reference.refineArsHostReference
    Reference.RawArsHostReference
      { Reference.rawArsHostReferenceObjectKey = key
      , Reference.rawArsHostReferenceContentSha256 = content
      , Reference.rawArsHostReferenceByteLength = fromIntegral (BS.length (encodeArsHostTrace trace))
      , Reference.rawArsHostReferenceContextSha256 = arsHostTraceContextSha256 trace
      , Reference.rawArsHostReferencePlanId = rawArsHostPlanId context
      , Reference.rawArsHostReferenceLane = rawArsHostLane context
      , Reference.rawArsHostReferenceSourceSha256 = rawArsHostSourceSha256 context
      , Reference.rawArsHostReferenceExecutableSha256 = rawArsHostExecutableSha256 context
      , Reference.rawArsHostReferenceInvocationSha256 = rawArsHostInvocationSha256 context
      }

-- Exact recorded tuple equality, not producer authentication or Store proof.
validateArsHostTraceReference :: Reference.ArsHostReference -> ArsHostTrace -> Either Text ()
validateArsHostTraceReference reference trace = do
  expected <- arsHostTraceRecordedReference trace
  let left = Reference.arsHostReferenceToRaw expected
      right = Reference.arsHostReferenceToRaw reference
  traverse_
    (\(label, agrees) -> ensure agrees ("ARS host trace reference " <> label <> " differs"))
    [
      ( "object key"
      , Reference.rawArsHostReferenceObjectKey left == Reference.rawArsHostReferenceObjectKey right
      )
    ,
      ( "content SHA"
      , Reference.rawArsHostReferenceContentSha256 left == Reference.rawArsHostReferenceContentSha256 right
      )
    ,
      ( "byte length"
      , Reference.rawArsHostReferenceByteLength left == Reference.rawArsHostReferenceByteLength right
      )
    ,
      ( "context SHA"
      , Reference.rawArsHostReferenceContextSha256 left == Reference.rawArsHostReferenceContextSha256 right
      )
    , ("plan", Reference.rawArsHostReferencePlanId left == Reference.rawArsHostReferencePlanId right)
    , ("lane", Reference.rawArsHostReferenceLane left == Reference.rawArsHostReferenceLane right)
    ,
      ( "source"
      , Reference.rawArsHostReferenceSourceSha256 left == Reference.rawArsHostReferenceSourceSha256 right
      )
    ,
      ( "executable"
      , Reference.rawArsHostReferenceExecutableSha256 left
          == Reference.rawArsHostReferenceExecutableSha256 right
      )
    ,
      ( "invocation"
      , Reference.rawArsHostReferenceInvocationSha256 left
          == Reference.rawArsHostReferenceInvocationSha256 right
      )
    ]

-- Encoder: only canonical definite arrays/integers/text/bytes. Every Double is
-- an eight-byte raw F64 payload, including negative zero.
encodeRawTrace :: RawArsHostTrace -> B.Builder
encodeRawTrace raw =
  array 10
    <> text "jitml-ars-host-linear-trace"
    <> unsigned 1
    <> encodeContext (rawArsHostTraceContext raw)
    <> encodeConfig (Common.rawTrainerConfig observed)
    <> encodeRuntime (rawArsHostTraceRuntime raw)
    <> vector (Common.rawTrainerInitialParams observed)
    <> vector (Common.rawTrainerFinalParams observed)
    <> array 2
    <> unsigned (Common.observedEnvironmentTransitionCount counters)
    <> unsigned (Common.observedOptimizerUpdateCount counters)
    <> sequenceOf encodeObservation (Common.rawTrainerStats observed)
    <> text arsHostTraceContract
 where
  observed = rawArsHostTraceObservation raw
  counters = Common.rawTrainerCounters observed

encodeContext :: RawArsHostContext -> B.Builder
encodeContext raw =
  array 15
    <> text (rawArsHostRowId raw)
    <> text (rawArsHostExperiment raw)
    <> text (rawArsHostPlanId raw)
    <> text (rawArsHostCompiledTransport raw)
    <> text (rawArsHostLane raw)
    <> digest (rawArsHostSourceSha256 raw)
    <> digest (rawArsHostExecutableSha256 raw)
    <> digest (rawArsHostInvocationSha256 raw)
    <> text (rawArsHostExecutionBinding raw)
    <> text (rawArsHostKernelOS raw)
    <> text (rawArsHostKernelMachine raw)
    <> text (rawArsHostKernelRelease raw)
    <> text (rawArsHostSimulatorContract raw)
    <> text (rawArsHostProcessId raw)
    <> text (rawArsHostAttemptId raw)

encodeConfig :: Ars.ArsTrainConfig -> B.Builder
encodeConfig c =
  array 9
    <> integer (toInteger (Ars.arsSeed c))
    <> int (Ars.arsIterations c)
    <> int (Ars.arsNumDirections c)
    <> int (Ars.arsTopB c)
    <> scalar (Ars.arsStepSize c)
    <> scalar (Ars.arsNoiseStd c)
    <> int (Ars.arsMaxEpisodeSteps c)
    <> int (Ars.arsActionCount c)
    <> int (Ars.arsObsSize c)

encodeRuntime :: Ars.ArsNumericalRuntime -> B.Builder
encodeRuntime r =
  array 5
    <> text (Ars.arsRuntimeOperatingSystem r)
    <> text (Ars.arsRuntimeArchitecture r)
    <> text (Ars.arsRuntimeCompiler r)
    <> text (Ars.arsRuntimeCompilerVersion r)
    <> text (Ars.arsRuntimeArithmeticRecipe r)

encodeObservation :: Ars.ArsIterationObservation -> B.Builder
encodeObservation observation =
  array 2
    <> array 3
    <> int (Ars.arsIterIndex stat)
    <> scalar (Ars.arsIterMeanReturn stat)
    <> scalar (Ars.arsIterBestReturn stat)
    <> array 13
    <> encodeConfig (Ars.arsStepConfig s)
    <> encodeRuntime (Ars.arsStepNumericalRuntime s)
    <> int (Ars.arsStepIndex s)
    <> vector (Ars.arsStepThetaBefore s)
    <> vector (Ars.arsStepThetaAfter s)
    <> sequenceOf vector (Ars.arsStepSampledDirections s)
    <> sequenceOf
      ( \((p, ps), (m, ms), d) -> array 3 <> array 2 <> scalar p <> int ps <> array 2 <> scalar m <> int ms <> listVector d
      )
      (Ars.arsStepEvaluatedPerturbations s)
    <> sequenceOf
      (\(p, m, d) -> array 3 <> scalar p <> scalar m <> listVector d)
      (Ars.arsStepKeptDirections s)
    <> scalar (Ars.arsStepNoiseStd s)
    <> scalar (Ars.arsStepReturnStdDev s)
    <> listVector (Ars.arsStepUpdateDirection s)
    <> scalar (Ars.arsStepScale s)
    <> integer (Ars.arsStepObservedTransitions s)
 where
  stat = Ars.arsObservationStatistic observation
  s = Ars.arsObservationAppliedStep observation

build :: B.Builder -> BS.ByteString
build = LBS.toStrict . B.toLazyByteString

array :: Word64 -> B.Builder
array = header 4

unsigned :: Word64 -> B.Builder
unsigned = header 0

int :: Int -> B.Builder
int = integer . toInteger

integer :: Integer -> B.Builder
integer n
  | n >= 0 = unsigned (fromInteger n)
  | otherwise = header 1 (fromInteger (-1 - n))

header :: Word8 -> Word64 -> B.Builder
header major value
  | value < 24 = B.word8 (major * 32 + fromIntegral value)
  | value <= 255 = B.word8 (major * 32 + 24) <> B.word8 (fromIntegral value)
  | value <= 65535 = B.word8 (major * 32 + 25) <> B.word16BE (fromIntegral value)
  | value <= 4294967295 = B.word8 (major * 32 + 26) <> B.word32BE (fromIntegral value)
  | otherwise = B.word8 (major * 32 + 27) <> B.word64BE value

bytes :: BS.ByteString -> B.Builder
bytes value = header 2 (fromIntegral (BS.length value)) <> B.byteString value

text :: Text -> B.Builder
text value =
  let encoded = UTF8.encodeUtf8 value
   in header 3 (fromIntegral (BS.length encoded)) <> B.byteString encoded

scalar :: Double -> B.Builder
scalar value = header 2 8 <> B.word64LE (castDoubleToWord64 value)

vector :: VU.Vector Double -> B.Builder
vector values =
  header 2 (fromIntegral (VU.length values) * 8)
    <> VU.foldr (\value rest -> B.word64LE (castDoubleToWord64 value) <> rest) mempty values

listVector :: [Double] -> B.Builder
listVector values = header 2 (fromIntegral (length values) * 8) <> foldMap (B.word64LE . castDoubleToWord64) values

sequenceOf :: (a -> B.Builder) -> [a] -> B.Builder
sequenceOf encode values = array (fromIntegral (length values)) <> foldMap encode values

digest :: Text -> B.Builder
digest = bytes . unhex

unhex :: Text -> BS.ByteString
unhex = BS.pack . pairs . Text.unpack
 where
  pairs (a : b : rest) = (nibble a * 16 + nibble b) : pairs rest
  pairs _ = []
  nibble c = fromIntegral (fromEnum c - if c <= '9' then fromEnum '0' else fromEnum 'a' - 10)

hex :: BS.ByteString -> Text
hex =
  Text.pack
    . concatMap (\v -> [intToDigit (fromIntegral v `div` 16), intToDigit (fromIntegral v `mod` 16)])
    . BS.unpack

ensure :: Bool -> Text -> Either Text ()
ensure condition reason = unless condition (Left reason)

checkedSha :: Text -> Either Text ()
checkedSha value =
  ensure
    (Text.length value == 64 && Text.all (`elem` ("0123456789abcdef" :: String)) value)
    "ARS host context SHA-256 is not canonical"

boundedText :: Int -> Text -> Either Text ()
boundedText bound value =
  ensure
    (not (Text.null value) && Text.length value <= bound && BS.length (UTF8.encodeUtf8 value) <= bound)
    "ARS host metadata text is empty or exceeds its byte limit"

validateRuntime :: Ars.ArsNumericalRuntime -> Either Text ()
validateRuntime r =
  traverse_
    (boundedText 256)
    [ Ars.arsRuntimeOperatingSystem r
    , Ars.arsRuntimeArchitecture r
    , Ars.arsRuntimeCompiler r
    , Ars.arsRuntimeCompilerVersion r
    , Ars.arsRuntimeArithmeticRecipe r
    ]

finiteValues :: [Double] -> Either Text ()
finiteValues =
  traverse_
    (\v -> ensure (not (isNaN v || isInfinite v)) "ARS host trace contains nonfinite F64 data")

exactLength :: Text -> Int -> [a] -> Either Text ()
exactLength reason = go
 where
  go 0 [] = Right ()
  go n (_ : rest) | n > 0 = go (n - 1) rest
  go _ _ = Left reason

vectorShape :: Int -> VU.Vector Double -> Either Text ()
vectorShape dimensions values = do
  ensure (VU.length values == dimensions) "ARS host trace vector dimension differs"
  ensure
    (VU.all (\v -> not (isNaN v || isInfinite v)) values)
    "ARS host trace contains nonfinite F64 data"

listVectorShape :: Int -> [Double] -> Either Text ()
listVectorShape dimensions values = exactLength "ARS host trace vector dimension differs" dimensions values >> finiteValues values

-- Full preflight happens before any observation/direction list or vector is
-- materialised. Both passes enforce identical canonical tokens/schema/bounds.
decodeArsHostTrace :: BS.ByteString -> Either Text ArsHostTrace
decodeArsHostTrace input = do
  ensure
    (toInteger (BS.length input) <= arsHostTraceMaxBytes)
    "ARS host trace input exceeds its byte limit"
  _ <- runStateT (readRawTrace False) (input, 0)
  (raw, _) <- runStateT (readRawTrace True) (input, 0)
  trace <- refineArsHostTrace raw
  ensure (encodeArsHostTrace trace == input) "ARS host trace is not canonical CBOR"
  pure trace

type Reader = StateT (BS.ByteString, Int) (Either Text)

checked :: Either Text a -> Reader a
checked result = StateT (\state -> fmap (,state) result)

reject :: Text -> Reader a
reject = checked . Left

readRawTrace :: Bool -> Reader RawArsHostTrace
readRawTrace collect = do
  expectHead 4 10
  domain <- readText 64
  unless (domain == "jitml-ars-host-linear-trace") (reject "ARS host trace domain differs")
  expectHead 0 1
  context <- readContext
  _ <- checked (refineArsHostContext context)
  config <- readConfig
  _ <- checked (arsHostTraceCoordinateCount config)
  runtime <- readRuntime
  let dimensions = Ars.arsActionCount config * Ars.arsObsSize config
  initial <- readVector collect dimensions
  final <- readVector collect dimensions
  expectHead 4 2
  transitions <- readHead 0
  updates <- readHead 0
  counters <- checked (Common.mkObservedTrainerCounters (toInteger transitions) (toInteger updates))
  observations <-
    readMany collect (Ars.arsIterations config) (readObservation collect config runtime dimensions)
  contract <- readText 128
  unless (contract == arsHostTraceContract) (reject "ARS host trace replay contract differs")
  (input, offset) <- get
  unless (offset == BS.length input) (reject "ARS host trace has trailing bytes")
  pure
    RawArsHostTrace
      { rawArsHostTraceContext = context
      , rawArsHostTraceRuntime = runtime
      , rawArsHostTraceObservation = Common.RawTrainerResult initial final observations counters config
      }

readContext :: Reader RawArsHostContext
readContext = do
  expectHead 4 15
  RawArsHostContext
    <$> readText 1024
    <*> readText 1024
    <*> readText 256
    <*> readText 32768
    <*> readText 1024
    <*> readDigest
    <*> readDigest
    <*> readDigest
    <*> readText 1024
    <*> readText 1024
    <*> readText 1024
    <*> readText 1024
    <*> readText 1024
    <*> readText 1024
    <*> readText 1024

readConfig :: Reader Ars.ArsTrainConfig
readConfig = do
  expectHead 4 9
  Ars.ArsTrainConfig
    <$> readSignedInt
    <*> readBoundedInt 4096
    <*> readBoundedInt 1024
    <*> readBoundedInt 1024
    <*> readScalar
    <*> readScalar
    <*> readBoundedInt 10000000
    <*> readBoundedInt 4096
    <*> readBoundedInt 4096

readRuntime :: Reader Ars.ArsNumericalRuntime
readRuntime = do
  expectHead 4 5
  runtime <-
    Ars.ArsNumericalRuntime
      <$> readText 256
      <*> readText 256
      <*> readText 256
      <*> readText 256
      <*> readText 256
  checked (validateRuntime runtime)
  pure runtime

readObservation
  :: Bool
  -> Ars.ArsTrainConfig
  -> Ars.ArsNumericalRuntime
  -> Int
  -> Int
  -> Reader Ars.ArsIterationObservation
readObservation collect config runtime dimensions index = do
  expectHead 4 2
  expectHead 4 3
  statIndex <- readBoundedInt 4096
  unless (statIndex == index) (reject "ARS host trace iteration index differs")
  mean <- readScalar
  best <- readScalar
  expectHead 4 13
  stepConfig <- readConfig
  unless
    (build (encodeConfig stepConfig) == build (encodeConfig config))
    (reject "ARS host trace step configuration differs")
  stepRuntime <- readRuntime
  unless (stepRuntime == runtime) (reject "ARS host trace step runtime differs")
  stepIndex <- readBoundedInt 4096
  unless (stepIndex == index) (reject "ARS host trace iteration index differs")
  before <- readVector collect dimensions
  after <- readVector collect dimensions
  directions <- readMany collect (Ars.arsNumDirections config) (const (readVector collect dimensions))
  evaluated <- readMany collect (Ars.arsNumDirections config) (const readPerturbation)
  kept <- readMany collect (Ars.arsTopB config) (const readKept)
  noise <- readScalar
  sigma <- readScalar
  update <- VU.toList <$> readVector collect dimensions
  scale <- readScalar
  transitions <- readHead 0
  pure
    Ars.ArsIterationObservation
      { Ars.arsObservationStatistic = Ars.ArsIterationStat statIndex mean best
      , Ars.arsObservationAppliedStep =
          Ars.ArsAppliedStep
            { Ars.arsStepConfig = stepConfig
            , Ars.arsStepNumericalRuntime = stepRuntime
            , Ars.arsStepIndex = stepIndex
            , Ars.arsStepThetaBefore = before
            , Ars.arsStepThetaAfter = after
            , Ars.arsStepSampledDirections = directions
            , Ars.arsStepEvaluatedPerturbations = evaluated
            , Ars.arsStepKeptDirections = kept
            , Ars.arsStepNoiseStd = noise
            , Ars.arsStepReturnStdDev = sigma
            , Ars.arsStepUpdateDirection = update
            , Ars.arsStepScale = scale
            , Ars.arsStepObservedTransitions = toInteger transitions
            }
      }
 where
  readPerturbation = do
    expectHead 4 3
    expectHead 4 2
    plus <- readScalar
    plusSteps <- readBoundedInt (Ars.arsMaxEpisodeSteps config)
    expectHead 4 2
    minus <- readScalar
    minusSteps <- readBoundedInt (Ars.arsMaxEpisodeSteps config)
    delta <- VU.toList <$> readVector collect dimensions
    pure ((plus, plusSteps), (minus, minusSteps), delta)
  readKept = do
    expectHead 4 3
    plus <- readScalar
    minus <- readScalar
    delta <- VU.toList <$> readVector collect dimensions
    pure (plus, minus, delta)

readMany :: Bool -> Int -> (Int -> Reader a) -> Reader [a]
readMany collect count action = do
  expectHead 4 (fromIntegral count)
  if collect then traverse action [0 .. count - 1] else go 0 >> pure []
 where
  go index
    | index >= count = pure ()
    | otherwise = action index >> go (index + 1)

-- Raw slices share the bounded input; the preflight scans finite bits without
-- allocating a Double list/vector. The materialisation pass starts after EOF.
readVector :: Bool -> Int -> Reader (VU.Vector Double)
readVector collect dimensions = do
  let count = toInteger dimensions * 8
  unless
    (count >= 0 && count <= toInteger (maxBound :: Int))
    (reject "ARS host vector byte length overflows Int")
  expectHead 2 (fromInteger count)
  encoded <- takeBytes (fromInteger count)
  checkFinite encoded 0
  pure $
    if collect
      then VU.generate dimensions (\index -> castWord64ToDouble (word64LEAt encoded (index * 8)))
      else VU.empty
 where
  checkFinite encoded offset
    | offset >= BS.length encoded = pure ()
    | otherwise = do
        let value = castWord64ToDouble (word64LEAt encoded offset)
        when (isNaN value || isInfinite value) (reject "ARS host trace contains nonfinite F64 data")
        checkFinite encoded (offset + 8)

readScalar :: Reader Double
readScalar = do
  expectHead 2 8
  encoded <- takeBytes 8
  let value = castWord64ToDouble (word64LEAt encoded 0)
  when (isNaN value || isInfinite value) (reject "ARS host trace contains nonfinite F64 data")
  pure value

word64LEAt :: BS.ByteString -> Int -> Word64
word64LEAt encoded offset = go 0 0
 where
  go index acc
    | index >= 8 = acc
    | otherwise =
        go (index + 1) (acc .|. (fromIntegral (BS.index encoded (offset + index)) `shiftL` (8 * index)))

readSignedInt :: Reader Int
readSignedInt = do
  (input, offset) <- get
  unless (offset < BS.length input) (reject "ARS host trace is truncated")
  let major = BS.index input offset `shiftR` 5
  value <- case major of
    0 -> toInteger <$> readHead 0
    1 -> (\n -> -1 - toInteger n) <$> readHead 1
    _ -> reject "ARS host trace expected a signed integer"
  unless
    (value >= toInteger (minBound :: Int) && value <= toInteger (maxBound :: Int))
    (reject "ARS host trace signed integer exceeds actual Int bounds")
  pure (fromInteger value)

readBoundedInt :: Int -> Reader Int
readBoundedInt bound = do
  value <- readHead 0
  unless
    (toInteger value <= min (toInteger bound) (toInteger (maxBound :: Int)))
    (reject "ARS host trace count exceeds its resource or actual Int limit")
  pure (fromIntegral value)

takeBytes :: Word64 -> Reader BS.ByteString
takeBytes count = do
  (input, offset) <- get
  unless
    (toInteger count <= toInteger (BS.length input - offset))
    (reject "ARS host trace is truncated")
  let n = fromIntegral count
  put (input, offset + n)
  pure (BS.take n (BS.drop offset input))

readHead :: Word8 -> Reader Word64
readHead expected = do
  first <- BS.head <$> takeBytes 1
  unless (first `shiftR` 5 == expected) (reject "ARS host trace CBOR type differs")
  let additional = first .&. 31
  if additional < 24
    then pure (fromIntegral additional)
    else do
      (width, minimumValue) <- case additional of
        24 -> pure (1, 24)
        25 -> pure (2, 256)
        26 -> pure (4, 65536)
        27 -> pure (8, 4294967296)
        _ -> reject "ARS host trace indefinite or reserved CBOR header"
      value <- BS.foldl' (\acc byte -> (acc `shiftL` 8) .|. fromIntegral byte) 0 <$> takeBytes width
      unless (value >= minimumValue) (reject "ARS host trace noncanonical CBOR width")
      pure value

expectHead :: Word8 -> Word64 -> Reader ()
expectHead major count = do
  actual <- readHead major
  unless (actual == count) (reject "ARS host trace CBOR field or byte count differs")

readText :: Word64 -> Reader Text
readText bound = do
  count <- readHead 3
  unless (count <= bound) (reject "ARS host trace text exceeds its byte limit")
  encoded <- takeBytes count
  either (const (reject "ARS host trace UTF-8 is invalid")) pure (UTF8.decodeUtf8' encoded)

readDigest :: Reader Text
readDigest = do
  expectHead 2 32
  hex <$> takeBytes 32
