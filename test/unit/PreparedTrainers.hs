{-# LANGUAGE OverloadedStrings #-}

module PreparedTrainers (preparedTrainerTests, capturePreparedRuns, capturePreparedArsRuns) where

import Control.Concurrent (MVar, forkIO, killThread, newEmptyMVar, putMVar, takeMVar)
import Control.Exception
  ( AsyncException (ThreadKilled)
  , IOException
  , SomeException
  , bracket
  , evaluate
  , fromException
  , try
  )
import Control.Monad (replicateM, void)
import Data.Aeson (Value (..), object, (.=))
import Data.Aeson.KeyMap qualified as KeyMap
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.List (find)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import GHC.Float (castDoubleToWord64)
import System.Random qualified as Random
import System.Timeout (timeout)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Execution.SingleUse qualified as SingleUse
import JitML.Numerics.Mlp qualified as Mlp
import JitML.Numerics.MlpDevice (MlpDevice (..), pureReferenceMlpDevice)
import JitML.RL.Algorithms.ArsTrainer qualified as Ars
import JitML.RL.Algorithms.Common qualified as Common
import JitML.RL.Algorithms.DqnTrainer qualified as Dqn
import JitML.RL.Algorithms.HerTrainer qualified as Her
import JitML.RL.Algorithms.PpoTrainer qualified as Ppo
import JitML.RL.Algorithms.QrDqnTrainer qualified as Qr
import JitML.RL.Simulator qualified as Sim
import JitML.RL.VecEnv qualified as Vec
import PreparedTrainerCapture qualified as Capture

preparedTrainerTests :: TestTree
preparedTrainerTests =
  testGroup
    "actual prepared trainer continuations"
    [ testCase "atomic single-use guard grants exactly one concurrent claim" $ do
        guard <- SingleUse.newSingleUse
        slots <- replicateM 16 newEmptyMVar
        mapM_ (\slot -> void (forkIO (SingleUse.tryConsumeSingleUse guard >>= putMVar slot))) slots
        answers <- traverse takeMVar slots
        length (filter id answers) @?= 1
        SingleUse.tryConsumeSingleUse guard >>= (@?= False)
    , testCase "DQN snapshot retains actual online target Adam RNG replay and simulator state" $ do
        prepared <- Dqn.prepareDqnOnCartpole Capture.dqnConfig
        let snapshot = Dqn.preparedDqnSnapshot prepared
        forceSnapshot snapshot
        Dqn.dqnPreparedConfig snapshot @?= Capture.dqnConfig
        Dqn.dqnPreparedInitialParams snapshot @?= Dqn.dqnPreparedOnlineParams snapshot
        Dqn.dqnPreparedTargetParams snapshot @?= Dqn.dqnPreparedOnlineParams snapshot
        Dqn.dqnPreparedAdam snapshot
          @?= Mlp.adamInit (Mlp.paramShape (Dqn.dqnPreparedInitialParams snapshot))
        Dqn.dqnPreparedGenerator snapshot @?= Random.mkStdGen (Dqn.dqnSeed Capture.dqnConfig + 1)
        Dqn.dqnPreparedReplay snapshot @?= []
        Dqn.dqnPreparedStep snapshot @?= 0
        Dqn.dqnPreparedState snapshot @?= Sim.envInitial Sim.cartPoleEnvironment
        Dqn.dqnPreparedEpisodeLength snapshot @?= 0
        Dqn.dqnPreparedEpisodeReturn snapshot @?= 0
        Dqn.dqnPreparedRecentReturns snapshot @?= []
        Dqn.dqnPreparedStatistics snapshot @?= []
        Dqn.dqnPreparedEnvironmentName snapshot @?= Sim.envName Sim.cartPoleEnvironment
        Dqn.dqnPreparedObservationWidth snapshot @?= Sim.envObservationSize Sim.cartPoleEnvironment
        Dqn.dqnPreparedActionCount snapshot @?= Sim.envActionCount Sim.cartPoleEnvironment
    , testCase "QR-DQN snapshot retains actual quantile target optimizer RNG and empty rollout state" $ do
        prepared <- Qr.prepareQrDqnOnCartpole Capture.qrConfig
        let snapshot = Qr.preparedQrDqnSnapshot prepared
        forceSnapshot snapshot
        Qr.qrDqnPreparedConfig snapshot @?= Capture.qrConfig
        Qr.qrDqnPreparedInitialParams snapshot @?= Qr.qrDqnPreparedOnlineParams snapshot
        Qr.qrDqnPreparedTargetParams snapshot @?= Qr.qrDqnPreparedOnlineParams snapshot
        Qr.qrDqnPreparedAdam snapshot
          @?= Mlp.adamInit (Mlp.paramShape (Qr.qrDqnPreparedInitialParams snapshot))
        Qr.qrDqnPreparedGenerator snapshot @?= Random.mkStdGen (Qr.qrSeed Capture.qrConfig + 1)
        Qr.qrDqnPreparedReplay snapshot @?= []
        Qr.qrDqnPreparedStep snapshot @?= 0
        Qr.qrDqnPreparedState snapshot @?= Sim.envInitial Sim.cartPoleEnvironment
        Qr.qrDqnPreparedEpisodeLength snapshot @?= 0
        Qr.qrDqnPreparedEpisodeReturn snapshot @?= 0
        Qr.qrDqnPreparedRecentReturns snapshot @?= []
        Qr.qrDqnPreparedStatistics snapshot @?= []
    , testCase "HER snapshot precedes goal sampling and retains actual replay optimizer and generator" $ do
        prepared <- Her.prepareHerOnBitFlip Capture.herConfig
        let snapshot = Her.preparedHerSnapshot prepared
        forceSnapshot snapshot
        Her.herPreparedConfig snapshot @?= Capture.herConfig
        Her.herPreparedInitialParams snapshot @?= Her.herPreparedOnlineParams snapshot
        Her.herPreparedTargetParams snapshot @?= Her.herPreparedOnlineParams snapshot
        Her.herPreparedAdam snapshot
          @?= Mlp.adamInit (Mlp.paramShape (Her.herPreparedInitialParams snapshot))
        Her.herPreparedGenerator snapshot @?= Random.mkStdGen (Her.herSeed Capture.herConfig + 1)
        Her.herPreparedReplay snapshot @?= []
        Her.herPreparedEpisode snapshot @?= 0
        Her.herPreparedObservedTransitions snapshot @?= 0
        Her.herPreparedRecentSuccesses snapshot @?= []
        Her.herPreparedStatistics snapshot @?= []
    , testCase "pure PPO snapshot records the actual fresh visitation table without mutable access" $ do
        prepared <- Ppo.preparePpoInEnvironment Sim.cartPoleEnvironment (Capture.ppoConfig Ppo.VariantPPO)
        let snapshot = Ppo.preparedPpoSnapshot prepared
        forceSnapshot snapshot
        Ppo.ppoPreparedSingleState snapshot @?= Just (Sim.envInitial Sim.cartPoleEnvironment)
        Ppo.ppoPreparedVectorSlots snapshot @?= []
        Ppo.ppoPreparedCountEntries snapshot @?= []
        Ppo.ppoPreparedActorSteps snapshot @?= 0
        Ppo.ppoPreparedTransitions snapshot @?= 0
        Ppo.ppoPreparedStatistics snapshot @?= []
        void (Ppo.continuePreparedPpoRaw prepared >>= expectRight)
        -- Initial data stays the originally observed data after real execution.
        Ppo.ppoPreparedCountEntries (Ppo.preparedPpoSnapshot prepared) @?= []
    , testCase "vector PPO snapshot carries actual reset slots and post-reset RNG into continuation" $ do
        let config = Capture.ppoConfig Ppo.VariantRecurrentPPO
            (expected, gen) =
              Vec.mkVecEnv
                Sim.cartPoleEnvironment
                (max 1 (Ppo.ppoVectorEnvCount config))
                (Random.mkStdGen (Ppo.ppoSeed config + 1))
        prepared <-
          Ppo.preparePpoOnDeviceWithEnvironment pureReferenceMlpDevice Sim.cartPoleEnvironment config
        let snapshot = Ppo.preparedPpoSnapshot prepared
        forceSnapshot snapshot
        Ppo.ppoPreparedSingleState snapshot @?= Nothing
        Ppo.ppoPreparedVectorSlots snapshot
          @?= [ (Vec.vecSlotState slot, Vec.vecSlotEpisodeReturn slot, Vec.vecSlotEpisodeLength slot)
              | slot <- Vec.vecEnvSlots expected
              ]
        Ppo.ppoPreparedFrames snapshot @?= Vec.vecEnvObservations expected
        Ppo.ppoPreparedGenerator snapshot @?= gen
        Ppo.ppoPreparedCountEntries snapshot @?= []
        Ppo.ppoPreparedAdam snapshot
          @?= Mlp.adamInit (Mlp.paramShape (Ppo.ppoPreparedInitialParams snapshot))
    , testCase "PPO first real callback uses the captured prepared parameters and cannot execute twice" $ do
        calls <- newIORef []
        prepared <-
          Ppo.preparePpoOnDeviceWithEnvironment
            (Capture.recordingDevice calls)
            Sim.cartPoleEnvironment
            (Capture.ppoConfig Ppo.VariantPPO)
        let snapshot = Ppo.preparedPpoSnapshot prepared
        forceSnapshot snapshot
        readIORef calls >>= (@?= [])
        actual <- Ppo.continuePreparedPpoRaw prepared >>= expectRight
        Common.rawTrainerInitialParams actual @?= Ppo.ppoPreparedInitialParams snapshot
        assertFirstParams calls (Ppo.ppoPreparedInitialParams snapshot)
        before <- readIORef calls
        Ppo.continuePreparedPpoRaw prepared
          >>= expectLeftExactly "prepared Ppo continuation has already been consumed"
        readIORef calls >>= (@?= before)
    , testCase "DQN first real callback uses the captured prepared parameters and cannot execute twice" $ do
        calls <- newIORef []
        prepared <-
          Dqn.prepareDqnOnDeviceWithEnvironment
            (Capture.recordingDevice calls)
            Sim.cartPoleEnvironment
            Capture.dqnConfig
        let snapshot = Dqn.preparedDqnSnapshot prepared
        forceSnapshot snapshot
        readIORef calls >>= (@?= [])
        actual <- Dqn.continuePreparedDqnRaw prepared >>= expectRight
        Common.rawTrainerInitialParams actual @?= Dqn.dqnPreparedInitialParams snapshot
        assertFirstParams calls (Dqn.dqnPreparedInitialParams snapshot)
        before <- readIORef calls
        Dqn.continuePreparedDqnRaw prepared
          >>= expectLeftExactly "prepared Dqn continuation has already been consumed"
        readIORef calls >>= (@?= before)
    , testCase "QR-DQN first real callback uses the captured prepared parameters and cannot execute twice" $ do
        calls <- newIORef []
        prepared <-
          Qr.prepareQrDqnOnDeviceWithEnvironment
            (Capture.recordingDevice calls)
            Sim.cartPoleEnvironment
            Capture.qrConfig
        let snapshot = Qr.preparedQrDqnSnapshot prepared
        forceSnapshot snapshot
        readIORef calls >>= (@?= [])
        actual <- Qr.continuePreparedQrDqnRaw prepared >>= expectRight
        Common.rawTrainerInitialParams actual @?= Qr.qrDqnPreparedInitialParams snapshot
        assertFirstParams calls (Qr.qrDqnPreparedInitialParams snapshot)
        before <- readIORef calls
        Qr.continuePreparedQrDqnRaw prepared
          >>= expectLeftExactly "prepared QrDqn continuation has already been consumed"
        readIORef calls >>= (@?= before)
    , testCase "HER first real update uses the captured prepared parameters and cannot execute twice" $ do
        calls <- newIORef []
        prepared <- Her.prepareHerOnDevice (Capture.recordingDevice calls) Capture.herConfig
        let snapshot = Her.preparedHerSnapshot prepared
        forceSnapshot snapshot
        readIORef calls >>= (@?= [])
        actual <- Her.continuePreparedHerRaw prepared >>= expectRight
        Common.rawTrainerInitialParams actual @?= Her.herPreparedInitialParams snapshot
        assertFirstParams calls (Her.herPreparedInitialParams snapshot)
        before <- readIORef calls
        Her.continuePreparedHerRaw prepared
          >>= expectLeftExactly "prepared Her continuation has already been consumed"
        readIORef calls >>= (@?= before)
    , testCase "PPO zero-iteration raw return stays finite data while strict counters reject" $ do
        let config = (Capture.ppoConfig Ppo.VariantPPO) {Ppo.ppoNumIterations = 0}
        prepared <- Ppo.preparePpoInEnvironment Sim.cartPoleEnvironment config
        observed <- Ppo.continuePreparedPpoRaw prepared >>= expectRight
        assertZeroCounters observed
        expectLeftPrefix "RL measured environment-transition count" (Ppo.refinePpoTrainObservation observed)
        assertIOException (Ppo.trainPpoOnCartpole config)
    , testCase "DQN zero-step raw return preserves strict rejection and performs no device work" $ do
        let config = Capture.dqnConfig {Dqn.dqnNumSteps = 0}
        calls <- newIORef []
        prepared <-
          Dqn.prepareDqnOnDeviceWithEnvironment (Capture.recordingDevice calls) Sim.cartPoleEnvironment config
        observed <- Dqn.continuePreparedDqnRaw prepared >>= expectRight
        assertZeroCounters observed
        expectLeftPrefix "RL measured environment-transition count" (Dqn.refineDqnTrainObservation observed)
        readIORef calls >>= (@?= [])
        assertIOException (Dqn.trainDqnOnCartpole config)
    , testCase "QR-DQN zero-step raw return preserves strict rejection and performs no device work" $ do
        let config = Capture.qrConfig {Qr.qrNumSteps = 0}
        calls <- newIORef []
        prepared <-
          Qr.prepareQrDqnOnDeviceWithEnvironment
            (Capture.recordingDevice calls)
            Sim.cartPoleEnvironment
            config
        observed <- Qr.continuePreparedQrDqnRaw prepared >>= expectRight
        assertZeroCounters observed
        expectLeftPrefix
          "RL measured environment-transition count"
          (Qr.refineQrDqnTrainObservation observed)
        readIORef calls >>= (@?= [])
        assertIOException (Qr.trainQrDqnOnCartpole config)
    , testCase "HER zero-episode raw return preserves strict rejection and does not sample a goal" $ do
        let config = Capture.herConfig {Her.herEpisodes = 0}
        calls <- newIORef []
        prepared <- Her.prepareHerOnDevice (Capture.recordingDevice calls) config
        observed <- Her.continuePreparedHerRaw prepared >>= expectRight
        assertZeroCounters observed
        expectLeftPrefix "RL measured environment-transition count" (Her.refineHerTrainObservation observed)
        readIORef calls >>= (@?= [])
        assertIOException (Her.trainHerOnBitFlip config)
    , testCase "PPO device failure consumes the continuation without retrying callbacks" $ do
        calls <- newIORef (0 :: Int)
        prepared <-
          Ppo.preparePpoOnDeviceWithEnvironment
            (failingDevice calls)
            Sim.cartPoleEnvironment
            (Capture.ppoConfig Ppo.VariantPPO)
        Ppo.continuePreparedPpoRaw prepared >>= expectLeftPrefix "prepared sentinel"
        before <- readIORef calls
        assertBool "real failure callback was not reached" (before > 0)
        Ppo.continuePreparedPpoRaw prepared
          >>= expectLeftExactly "prepared Ppo continuation has already been consumed"
        readIORef calls >>= (@?= before)
    , testCase "DQN device failure consumes the continuation without retrying callbacks" $ do
        calls <- newIORef (0 :: Int)
        prepared <-
          Dqn.prepareDqnOnDeviceWithEnvironment
            (failingDevice calls)
            Sim.cartPoleEnvironment
            Capture.dqnConfig
        Dqn.continuePreparedDqnRaw prepared >>= expectLeftPrefix "prepared sentinel"
        before <- readIORef calls
        assertBool "real failure callback was not reached" (before > 0)
        Dqn.continuePreparedDqnRaw prepared
          >>= expectLeftExactly "prepared Dqn continuation has already been consumed"
        readIORef calls >>= (@?= before)
    , testCase "QR-DQN device failure consumes the continuation without retrying callbacks" $ do
        calls <- newIORef (0 :: Int)
        prepared <-
          Qr.prepareQrDqnOnDeviceWithEnvironment
            (failingDevice calls)
            Sim.cartPoleEnvironment
            Capture.qrConfig
        Qr.continuePreparedQrDqnRaw prepared >>= expectLeftPrefix "prepared sentinel"
        before <- readIORef calls
        assertBool "real failure callback was not reached" (before > 0)
        Qr.continuePreparedQrDqnRaw prepared
          >>= expectLeftExactly "prepared QrDqn continuation has already been consumed"
        readIORef calls >>= (@?= before)
    , testCase "HER device failure consumes the continuation without retrying callbacks" $ do
        calls <- newIORef (0 :: Int)
        prepared <- Her.prepareHerOnDevice (failingDevice calls) Capture.herConfig
        Her.continuePreparedHerRaw prepared >>= expectLeftPrefix "prepared sentinel"
        before <- readIORef calls
        assertBool "real failure callback was not reached" (before > 0)
        Her.continuePreparedHerRaw prepared
          >>= expectLeftExactly "prepared Her continuation has already been consumed"
        readIORef calls >>= (@?= before)
    , testCase "an interrupted actual continuation stays consumed and propagates cancellation" $ do
        entered <- newEmptyMVar
        blocker <- newEmptyMVar :: IO (MVar ())
        finished <- newEmptyMVar
        let device =
              pureReferenceMlpDevice
                { mlpdForward = \_ _ -> do
                    putMVar entered ()
                    void (takeMVar blocker)
                    pure (Left "unexpectedly released cancellation fixture")
                }
        prepared <- Dqn.prepareDqnOnDeviceWithEnvironment device Sim.cartPoleEnvironment Capture.dqnConfig
        bracket
          ( forkIO $ do
              result <-
                try (Dqn.continuePreparedDqnRaw prepared)
                  :: IO (Either SomeException (Either Text Dqn.DqnTrainObservation))
              putMVar finished result
          )
          killThread
          ( \worker -> do
              await entered
              killThread worker
              result <- await finished
              case result of
                Left err -> (fromException err :: Maybe AsyncException) @?= Just ThreadKilled
                Right _ -> assertFailure "continuation swallowed actual asynchronous cancellation"
              Dqn.continuePreparedDqnRaw prepared
                >>= expectLeftExactly "prepared Dqn continuation has already been consumed"
          )
    , testCase "ARS snapshot retains the actual host-linear initial values generator and frame" $ do
        let config = arsConfig 2
        prepared <- Ars.prepareArsOnEnvironment arsEnvironment config
        let snapshot = Ars.preparedArsSnapshot prepared
        Ars.arsPreparedConfig snapshot @?= config
        Ars.arsPreparedInitialParams snapshot @?= Ars.initialArsParams config
        Ars.arsPreparedGenerator snapshot @?= Random.mkStdGen (Ars.arsSeed config)
        Ars.arsPreparedInitialFrame snapshot
          @?= VU.fromList
            ( Sim.renderObservation
                (Sim.envRenderFrame Sim.cartPoleEnvironment (Sim.envInitial Sim.cartPoleEnvironment))
            )
    , testCase "ARS actual first applied-step trace begins at the captured theta and retains every step" $ do
        prepared <- Ars.prepareArsOnEnvironment arsEnvironment (arsConfig 2)
        let snapshot = Ars.preparedArsSnapshot prepared
        observed <- Ars.continuePreparedArsRaw prepared >>= expectRight
        Common.rawTrainerInitialParams observed @?= Ars.arsPreparedInitialParams snapshot
        Common.rawTrainerConfig observed @?= Ars.arsPreparedConfig snapshot
        let steps = fmap Ars.arsObservationAppliedStep (Common.rawTrainerStats observed)
        case steps of
          first : _ -> Ars.arsStepThetaBefore first @?= Ars.arsPreparedInitialParams snapshot
          [] -> assertFailure "actual bounded ARS run omitted its first step"
        length steps @?= 2
        fmap Ars.arsStepIndex steps @?= [0, 1]
        Common.observedEnvironmentTransitionCount (Common.rawTrainerCounters observed)
          @?= fromInteger (sum (fmap Ars.arsStepObservedTransitions steps))
        case reverse steps of
          lastStep : _ -> Ars.arsStepThetaAfter lastStep @?= Common.rawTrainerFinalParams observed
          [] -> assertFailure "actual bounded ARS run omitted its final step"
        Ars.continuePreparedArsRaw prepared
          >>= expectLeftExactly "ARS prepared training was already consumed"
    , testCase "ARS concurrent continuations allow one actual raw return and reject all other claims" $ do
        prepared <- Ars.prepareArsOnEnvironment arsEnvironment (arsConfig 1)
        slots <- replicateM 8 newEmptyMVar
        mapM_ (\slot -> void (forkIO (Ars.continuePreparedArsRaw prepared >>= putMVar slot))) slots
        results <- traverse await slots
        length [() | Right _ <- results] @?= 1
        mapM_
          ( \case
              Left err -> err @?= "ARS prepared training was already consumed"
              Right observed -> length (Common.rawTrainerStats observed) @?= 1
          )
          results
    , testCase "ARS zero-iteration raw data preserves the original strict counter rejection" $ do
        let config = arsConfig 0
        prepared <- Ars.prepareArsOnEnvironment arsEnvironment config
        observed <- Ars.continuePreparedArsRaw prepared >>= expectRight
        assertZeroCounters observed
        Common.rawTrainerInitialParams observed @?= Common.rawTrainerFinalParams observed
        Common.rawTrainerStats observed @?= []
        expectLeftPrefix "RL measured environment-transition count" (Ars.refineArsTrainObservation observed)
        assertIOException (Ars.trainArsOnEnvironment arsEnvironment config)
    , testCase "legacy wrappers and explicit prepared routes preserve all ten complete numerical traces" $ do
        wrapper <- Capture.captureLegacyRuns
        prepared <- capturePreparedRuns
        -- This checks the two current entry routes. The independent old-API baseline at actual02849d generation
        -- comparison is an external, source/ELF-bound pending check.
        prepared @?= wrapper
    ]

await :: MVar a -> IO a
await slot = do
  result <- timeout 5000000 (takeMVar slot)
  case result of
    Just value -> pure value
    Nothing -> assertFailure "bounded cancellation fixture timed out" >> fail "unreachable"

forceSnapshot :: (Show a) => a -> IO ()
forceSnapshot snapshot = void (evaluate (length (show snapshot)))

assertFirstParams :: IORef [Value] -> Mlp.MlpParams -> Assertion
assertFirstParams trace params = do
  entries <- reverse <$> readIORef trace
  let actual = find hasParams entries
  case actual of
    Just (Object outer) -> case KeyMap.lookup "value" outer of
      Just (Object payload) -> KeyMap.lookup "params" payload @?= Just (Capture.paramsValue params)
      _ -> assertFailure "first numerical callback had no captured payload"
    _ -> assertFailure "no actual numerical callback was captured"
 where
  hasParams (Object outer) = case KeyMap.lookup "value" outer of
    Just (Object payload) -> KeyMap.member "params" payload
    _ -> False
  hasParams _ = False

failingDevice :: IORef Int -> MlpDevice
failingDevice calls =
  pureReferenceMlpDevice
    { mlpdForward = \_ _ -> failure
    , mlpdForwardBatch = \_ _ -> failure
    }
 where
  failure :: IO (Either Text a)
  failure = modifyIORef' calls (+ 1) >> pure (Left "prepared sentinel")

assertZeroCounters :: Common.RawTrainerResult params stat config -> Assertion
assertZeroCounters observed = do
  Common.observedEnvironmentTransitionCount (Common.rawTrainerCounters observed) @?= 0
  Common.observedOptimizerUpdateCount (Common.rawTrainerCounters observed) @?= 0

expectRight :: (Show err) => Either err a -> IO a
expectRight result = case result of
  Right value -> pure value
  Left err -> assertFailure ("expected real numerical return: " <> show err) >> fail "unreachable"
expectLeftExactly :: (Eq err, Show err) => err -> Either err a -> Assertion
expectLeftExactly expected result = case result of
  Left err -> err @?= expected
  Right _ -> assertFailure "expected the specific rejection"
expectLeftPrefix :: Text -> Either Text a -> Assertion
expectLeftPrefix expected result = case result of
  Left err -> assertBool ("wrong rejection: " <> Text.unpack err) (expected `Text.isInfixOf` err)
  Right _ -> assertFailure "expected the specific rejection"
assertIOException :: IO a -> Assertion
assertIOException action = do
  result <- try (void action) :: IO (Either IOException ())
  case result of
    Left _ -> pure ()
    Right () -> assertFailure "legacy strict counter rejection became success"

capturePreparedRuns :: IO [(Text, Value)]
capturePreparedRuns =
  sequence
    [ pureCapture
        "ppo-pure"
        Capture.ppoStatValue
        (Ppo.preparePpoInEnvironment Sim.cartPoleEnvironment (Capture.ppoConfig Ppo.VariantPPO))
        Ppo.continuePreparedPpoRaw
    , deviceCapture
        "ppo-device"
        Capture.ppoStatValue
        ( \device ->
            Ppo.preparePpoOnDeviceWithEnvironment
              device
              Sim.cartPoleEnvironment
              (Capture.ppoConfig Ppo.VariantPPO)
        )
        Ppo.continuePreparedPpoRaw
    , deviceCapture
        "trpo-device"
        Capture.ppoStatValue
        ( \device ->
            Ppo.preparePpoOnDeviceWithEnvironment
              device
              Sim.cartPoleEnvironment
              (Capture.ppoConfig Ppo.VariantTRPO)
        )
        Ppo.continuePreparedPpoRaw
    , deviceCapture
        "recurrent-device"
        Capture.ppoStatValue
        ( \device ->
            Ppo.preparePpoOnDeviceWithEnvironment
              device
              Sim.cartPoleEnvironment
              (Capture.ppoConfig Ppo.VariantRecurrentPPO)
        )
        Ppo.continuePreparedPpoRaw
    , pureCapture
        "dqn-pure"
        Capture.dqnStatValue
        (Dqn.prepareDqnOnCartpole Capture.dqnConfig)
        Dqn.continuePreparedDqnRaw
    , deviceCapture
        "dqn-device"
        Capture.dqnStatValue
        (\device -> Dqn.prepareDqnOnDeviceWithEnvironment device Sim.cartPoleEnvironment Capture.dqnConfig)
        Dqn.continuePreparedDqnRaw
    , pureCapture
        "qr-pure"
        Capture.qrStatValue
        (Qr.prepareQrDqnOnCartpole Capture.qrConfig)
        Qr.continuePreparedQrDqnRaw
    , deviceCapture
        "qr-device"
        Capture.qrStatValue
        (\device -> Qr.prepareQrDqnOnDeviceWithEnvironment device Sim.cartPoleEnvironment Capture.qrConfig)
        Qr.continuePreparedQrDqnRaw
    , pureCapture
        "her-pure"
        Capture.herStatValue
        (Her.prepareHerOnBitFlip Capture.herConfig)
        Her.continuePreparedHerRaw
    , deviceCapture
        "her-device"
        Capture.herStatValue
        (`Her.prepareHerOnDevice` Capture.herConfig)
        Her.continuePreparedHerRaw
    ]
 where
  pureCapture
    :: (Show config)
    => Text
    -> (stat -> Value)
    -> IO prepared
    -> (prepared -> IO (Either Text (Common.RawTrainerResult Mlp.MlpParams stat config)))
    -> IO (Text, Value)
  pureCapture name render prepare continue = do
    prepared <- prepare
    result <- continue prepared >>= expectRight
    pure (name, object ["raw" .= Capture.rawValue render result, "callbacks" .= ([] :: [Value])])
  deviceCapture
    :: (Show config)
    => Text
    -> (stat -> Value)
    -> (MlpDevice -> IO prepared)
    -> (prepared -> IO (Either Text (Common.RawTrainerResult Mlp.MlpParams stat config)))
    -> IO (Text, Value)
  deviceCapture name render prepare continue = do
    calls <- newIORef []
    prepared <- prepare (Capture.recordingDevice calls)
    result <- continue prepared
    trace <- reverse <$> readIORef calls
    let rendered = case result of
          Left err -> object ["left" .= err]
          Right value -> object ["right" .= Capture.rawValue render value]
    pure (name, object ["result" .= rendered, "callbacks" .= trace])

-- These are lower API diagnostics, not canonical ProductBudget executions.
arsEnvironment :: Sim.SomeSimulatedEnvironment
arsEnvironment = Sim.SomeSimulatedEnvironment Sim.cartPoleEnvironment

arsConfig :: Int -> Ars.ArsTrainConfig
arsConfig iterations =
  Ars.defaultArsTrainConfig
    { Ars.arsIterations = iterations
    , Ars.arsNumDirections = 2
    , Ars.arsTopB = 1
    , Ars.arsMaxEpisodeSteps = 2
    }

-- Same old-format data projection as CaptureFrozenBaseline, with the old
-- statistics explicitly extracted from the new actual applied-step wrapper.
-- This is for external same-runtime old/new comparison, not a unit golden.
capturePreparedArsRuns :: IO [Value]
capturePreparedArsRuns = traverse capture [0, 1, 2]
 where
  capture iterations = do
    prepared <- Ars.prepareArsOnEnvironment arsEnvironment (arsConfig iterations)
    observed <- Ars.continuePreparedArsRaw prepared >>= expectRight
    pure
      ( object
          [ "iterations" .= iterations
          , "actual_config_show" .= show (Common.rawTrainerConfig observed)
          , "initial_f64_bits" .= fmap castDoubleToWord64 (VU.toList (Common.rawTrainerInitialParams observed))
          , "final_f64_bits" .= fmap castDoubleToWord64 (VU.toList (Common.rawTrainerFinalParams observed))
          , "transitions" .= Common.observedEnvironmentTransitionCount (Common.rawTrainerCounters observed)
          , "updates" .= Common.observedOptimizerUpdateCount (Common.rawTrainerCounters observed)
          , "legacy_statistics"
              .= fmap (statValue . Ars.arsObservationStatistic) (Common.rawTrainerStats observed)
          , "legacy_refinement" .= case Ars.refineArsTrainObservation observed of
              Left err -> object ["left" .= err]
              Right result ->
                object
                  [ "statistics" .= fmap statValue (Ars.arsResultStats result)
                  , "transitions" .= Common.measuredEnvironmentTransitionCount (Ars.arsResultMeasuredCounters result)
                  , "updates" .= Common.measuredOptimizerUpdateCount (Ars.arsResultMeasuredCounters result)
                  ]
          ]
      )
  statValue stat =
    object
      [ "index" .= Ars.arsIterIndex stat
      , "mean_f64_bits" .= castDoubleToWord64 (Ars.arsIterMeanReturn stat)
      , "best_f64_bits" .= castDoubleToWord64 (Ars.arsIterBestReturn stat)
      ]
