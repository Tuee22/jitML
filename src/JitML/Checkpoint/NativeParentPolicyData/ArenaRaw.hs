{-# LANGUAGE OverloadedStrings #-}

-- | Ordinary decoded AlphaZero return DATA, never AlphaZeroTrainObservation.
module JitML.Checkpoint.NativeParentPolicyData.ArenaRaw (NativeArenaRawData (..), arenaRaw) where

import Data.Vector.Unboxed qualified as VU
import JitML.Checkpoint.NativeParentPolicyData.Node
import JitML.Checkpoint.NativePhase.Types
import JitML.Numerics.Mlp qualified as Mlp
import JitML.Plan.Plan qualified as Plan
import JitML.Plan.Workload qualified as Workload
import JitML.Product.NativePreparedAlphaZeroAttempt qualified as Child
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.RL.AlphaZero qualified as Game
import JitML.RL.AlphaZero.PolicyValueNet qualified as Net
import JitML.RL.AlphaZero.PreparedTrainer qualified as Recipe

data NativeArenaRawData = NativeArenaRawData
  { nativeParentArenaInitialState :: !Game.GameState
  , nativeParentArenaInitialPolicy :: !Net.PolicyValueNet
  , nativeParentArenaInitialAdam :: !Mlp.AdamState
  , nativeParentArenaFinalPolicy :: !Net.PolicyValueNet
  , nativeParentArenaFinalAdam :: !Mlp.AdamState
  , nativeParentArenaSamples :: ![Net.PolicyValueTrainingSample]
  , nativeParentArenaGenerationCount :: !Int
  , nativeParentArenaGenerationTarget :: !Int
  , nativeParentArenaGames :: !Int
  , nativeParentArenaSimulations :: !Int
  , nativeParentArenaMaxPlies :: !Int
  , nativeParentArenaUpdates :: !Int
  , nativeParentArenaSeed :: !Int
  }
  deriving stock (Eq, Show)

arenaRaw :: Child.NativeAlphaZeroChildData -> [NodeValue] -> Digest -> Decode NativeArenaRawData
arenaRaw child snapshot root = do
  actual <- fields NRawAlphaZero root
  case (snapshot, actual) of
    ( [ VText game
        , VRef preparedState
        , VRef preparedNet
        , VRef preparedAdam
        , hidden
        , seed_
        , target_
        , games_
        , sims_
        , plies_
        , updates_
        ]
      , [ VRef initialState
          , VRef initialNet
          , VRef initialAdam
          , VRef finalNet
          , VRef finalAdam
          , VRef samples
          , count
          , target
          , games
          , sims
          , plies
          , updates
          , seed
          ]
      ) -> do
        let plan = Child.nativeAlphaZeroChildPlan child
            expectedGame = Workload.renderAlphaZeroGame (Workload.alphaZeroPlanGame plan)
            expected =
              [ toInteger (Cohort.nativeRlSeedPlanSeed (Child.nativeAlphaZeroChildSeedPlan child))
              , toInteger (Plan.quantityValue (Workload.alphaZeroPlanGenerations plan))
              , toInteger (Plan.quantityValue (Workload.alphaZeroPlanSelfPlayGames plan))
              , toInteger (Plan.quantityValue (Workload.alphaZeroPlanMctsSimulations plan))
              , toInteger (Plan.quantityValue (Workload.alphaZeroPlanMaxPlies plan))
              , toInteger (Plan.quantityValue (Workload.alphaZeroPlanUpdates plan))
              ]
        snapshotValues <- traverse int [seed_, target_, games_, sims_, plies_, updates_]
        rawValues <- traverse int [seed, target, games, sims, plies, updates]
        hidden_ <- int hidden
        require
          ( game == expectedGame
              && map toInteger snapshotValues == expected
              && map toInteger rawValues == expected
              && hidden_ == Recipe.canonicalAlphaZeroHiddenUnits
          )
          "parent arena prepared/returned whole schedule or shared hidden recipe differs"
        require
          (initialState == preparedState && initialNet == preparedNet && initialAdam == preparedAdam)
          "parent arena actual raw initial state/net/Adam differs from the same prepared snapshot"
        state <- gameState initialState
        require (state == Game.initialStateFor expectedGame) "parent arena prepared initial state differs"
        net0 <- policy initialNet
        net1 <- policy finalNet
        let shape = Mlp.paramShape (Net.pvnParams net0)
        require
          ( Mlp.mlpHidden shape == hidden_
              && Net.pvnActionCount net0 == Game.actionCountFor expectedGame
              && Net.pvnObservationSize net0 == Game.observationSizeFor expectedGame
              && Net.pvnActionCount net1 == Net.pvnActionCount net0
              && Net.pvnObservationSize net1 == Net.pvnObservationSize net0
              && Mlp.paramShape (Net.pvnParams net1) == shape
          )
          "parent arena returned network shape differs"
        adam0 <- adam shape initialAdam
        adam1 <- adam shape finalAdam
        require
          (Mlp.adamStep_ adam0 == 0 && Mlp.adamStep_ adam1 >= Mlp.adamStep_ adam0)
          "parent arena prepared/final Adam indices differ"
        generations <- int count
        targetValue <- int target
        require
          (generations == targetValue)
          "parent arena actual generation count does not complete its schedule"
        gamesValue <- int games
        simsValue <- int sims
        pliesValue <- int plies
        updatesValue <- int updates
        seedValue <- int seed
        roots <-
          referenceData
            (RefElement NPolicyValueSample)
            (toInteger targetValue * toInteger gamesValue * toInteger pliesValue)
            samples
        records <- traverse sample roots
        mapM_ (either reject pure . Child.validateNativeAlphaZeroTrainingSampleData child) records
        pure
          ( NativeArenaRawData
              state
              net0
              adam0
              net1
              adam1
              records
              generations
              targetValue
              gamesValue
              simsValue
              pliesValue
              updatesValue
              seedValue
          )
    _ -> reject "parent arena prepared/raw typed field matrix differs"
 where
  policy digest = do
    actual <- fields NPVN digest
    case actual of
      [VRef p, actions, observations] -> Net.PolicyValueNet <$> parameters p <*> int actions <*> int observations
      _ -> reject "parent arena raw public network fields differ"
  adam shape digest = do
    actual <- fields NAdam digest
    case actual of
      [step, VRef m, VRef v] -> Mlp.AdamState <$> int step <*> gradient shape m <*> gradient shape v
      _ -> reject "parent arena raw Adam fields differ"
  gradient shape digest = do
    actual <- fields NGradient digest
    let sizes =
          [ toInteger (Mlp.mlpInputs shape) * toInteger (Mlp.mlpHidden shape)
          , toInteger (Mlp.mlpHidden shape)
          , toInteger (Mlp.mlpHidden shape) * toInteger (Mlp.mlpOutputs shape)
          , toInteger (Mlp.mlpOutputs shape)
          ]
    require (length actual == 4) "parent arena gradient field count differs"
    values <-
      traverse
        ( \(size, value) -> do
            vector <- ref value >>= tensor size
            require
              (toInteger (VU.length vector) == size && VU.all (\x -> not (isNaN x || isInfinite x)) vector)
              "parent arena Adam moments have invalid widths or nonfinite values"
            pure vector
        )
        (zip sizes actual)
    case values of
      [w1, b1, w2, b2] -> pure (Mlp.MlpGradient w1 b1 w2 b2)
      _ -> reject "parent arena gradient inventory differs"
  sample digest = do
    actual <- fields NPolicyValueSample digest
    case actual of
      [VRef state, VRef visits, value] -> do
        state_ <- gameState state
        distribution <- tensor (toInteger (Game.actionCountFor (Game.gameName state_))) visits
        Net.PolicyValueTrainingSample state_ distribution <$> bits value
      _ -> reject "parent arena training sample fields differ"
