{-# LANGUAGE OverloadedStrings #-}

-- | Decode complete public numerical records, never an evaluation capability.
module JitML.Checkpoint.NativeParentPolicyData.Evaluation
  ( ReturnConfiguration (..)
  , returnEvaluation
  , herEvaluation
  , arenaEvaluation
  , herSchedule
  , arenaEpisode
  , arenaDecision
  , returnEpisode
  ) where

import Data.Vector.Unboxed qualified as VU

import JitML.Checkpoint.NativeParentPolicyData.Node
import JitML.Checkpoint.NativePhase.Projection.Cases qualified as Cases
import JitML.Checkpoint.NativePhase.Types
import JitML.Numerics.Mlp qualified as Mlp
import JitML.RL.Algorithms.ArsTrainer qualified as Ars
import JitML.RL.Algorithms.HerTrainer qualified as Her
import JitML.RL.AlphaZero qualified as Game
import JitML.RL.AlphaZero.ArenaTape qualified as Tape
import JitML.RL.AlphaZero.NativeArenaEvaluation qualified as Arena
import JitML.RL.AlphaZero.NativeArenaReferences qualified as ArenaRef
import JitML.RL.AlphaZero.PolicyValueNet qualified as Net
import JitML.RL.NativeHerEvaluation qualified as HerEval
import JitML.RL.NativeHerReferences qualified as HerRef
import JitML.RL.NativeReturnEvaluation qualified as Return
import JitML.RL.NativeReturnReferences qualified as ReturnRef
import JitML.RL.TrainerConfiguration qualified as Config

data ReturnConfiguration
  = NeuralConfiguration !Config.NeuralTrainerConfiguration
  | ArsConfiguration !Ars.ArsTrainConfig

-- Config identity is checked by the caller's whole typed canonical projection
-- BEFORE this existing public config value is used. A mismatch is not replaced.
returnEvaluation
  :: ReturnRef.NativeReturnReferenceSpec
  -> Digest
  -> ReturnConfiguration
  -> Digest
  -> Digest
  -> Decode Return.RawNativeReturnEvaluation
returnEvaluation spec specRoot configuration configRoot root = do
  actual <- fields NReturnEvaluation root
  case actual of
    [ VRef observedSpec
      , VRef policy
      , VRef episodes
      , VRef forwards
      , VList [VWord 0]
      , VList [VWord 0, work]
      , VNull
      ] -> do
        require
          (observedSpec == specRoot)
          "parent RETURN specification root differs from the canonical reference prelude"
        (observedPolicy, fixed) <- returnPolicy configuration configRoot policy
        episodeRoots <- referenceData (RefElement NReturnEpisode) 20 episodes
        require (length episodeRoots == 20) "parent RETURN evaluation lacks twenty ordered cases"
        cases <- traverse returnEpisode episodeRoots
        let horizon = ReturnRef.nativeReturnSpecHorizon spec
            cap = 20 * toInteger horizon
        forwardRoots <- referenceData (RefElement NReturnForward) cap forwards
        events <- case fixed of
          Nothing -> require (null forwardRoots) "parent ARS host evaluation contains neural forwards" >> pure []
          Just (digest, params) -> traverse (returnForward digest params) forwardRoots
        observedWork <- magnitude work
        require
          (observedWork == sum (map (toInteger . ReturnRef.nativeReturnEpisodeSteps) cases))
          "parent RETURN complete work differs from its actual case counters"
        require (map ReturnRef.nativeReturnEpisodeId cases == [0 .. 19]) "parent RETURN case order differs"
        case fixed of
          Nothing -> pure ()
          Just _ -> do
            let expected =
                  [ (i, toInteger ordinal)
                  | (i, episode) <- zip [0 ..] cases
                  , ordinal <- [0 .. ReturnRef.nativeReturnEpisodeSteps episode - 1]
                  ]
            require
              ( map (\event -> (Return.nativeForwardCaseIndex event, Return.nativeForwardCallIndex event)) events
                  == expected
              )
              "parent RETURN forward case/call inventory differs from complete transitions"
        let result =
              Return.RawNativeReturnEvaluation
                spec
                observedPolicy
                cases
                events
                Return.NativeEvaluationComplete
                (Return.NativeCompleteWork observedWork)
                Nothing
        case observedPolicy of
          Return.NativeNeuralEvaluation neural -> either reject pure (Return.validateNativeNeuralReturnContext spec neural)
          Return.NativeArsHostEvaluation {} -> pure ()
        pure result
    _ -> reject "parent RETURN evaluation is incomplete, failed or has noncanonical complete fields"

returnPolicy
  :: ReturnConfiguration
  -> Digest
  -> Digest
  -> Decode (Return.NativeEvaluationPolicy, Maybe (Digest, Mlp.MlpParams))
returnPolicy config configRoot root = do
  actual <- fields NReturnPolicy root
  case (config, actual) of
    (NeuralConfiguration supplied, [VWord family, VRef config_, VRef p]) -> do
      require
        (config_ == configRoot)
        "parent RETURN actual config differs from the complete canonical recipe"
      params <- parameters p
      neural <- case (supplied, family) of
        (Config.OnPolicyConfiguration value, 0) -> pure (Return.NativeOnPolicy value params)
        (Config.DqnConfiguration value, 1) -> pure (Return.NativeDqn value params)
        (Config.QrDqnConfiguration value, 2) -> pure (Return.NativeQrDqn value params)
        (Config.ContinuousConfiguration value, 3) -> pure (Return.NativeContinuous value params)
        _ -> reject "parent RETURN family disagrees with its actual canonical config"
      pure (Return.NativeNeuralEvaluation neural, Just (p, params))
    (ArsConfiguration supplied, [VWord 5, VRef config_, VRef p]) -> do
      require (config_ == configRoot) "parent ARS policy config differs from the canonical recipe"
      let width = toInteger (Ars.arsActionCount supplied) * toInteger (Ars.arsObsSize supplied)
      theta <- tensor width p
      require (toInteger (VU.length theta) == width) "parent ARS policy theta width differs"
      pure (Return.NativeArsHostEvaluation supplied theta, Nothing)
    _ -> reject "parent RETURN policy kind disagrees with its canonical family"

returnEpisode :: Digest -> Decode ReturnRef.NativeReturnEpisode
returnEpisode root = do
  actual <- fields NReturnEpisode root
  case actual of
    [identity, reward, steps, terminated] -> ReturnRef.NativeReturnEpisode <$> int identity <*> bits reward <*> int steps <*> bool terminated
    _ -> reject "parent RETURN episode fields differ"

returnForward :: Digest -> Mlp.MlpParams -> Digest -> Decode Return.NativeForwardObservation
returnForward fixed params root = do
  actual <- fields NReturnForward root
  case actual of
    [identity, ordinal, VRef p, VRef input, VList [VWord 0, VRef output]] -> do
      require (p == fixed) "parent RETURN forward changed its complete policy params"
      observedInput <- tensor (toInteger (Mlp.mlpInputs (Mlp.paramShape params))) input
      observedOutput <- tensor (toInteger (Mlp.mlpOutputs (Mlp.paramShape params))) output
      require
        ( VU.length observedInput == Mlp.mlpInputs (Mlp.paramShape params)
            && VU.length observedOutput == Mlp.mlpOutputs (Mlp.paramShape params)
            && VU.all (\x -> not (isNaN x || isInfinite x)) observedInput
            && VU.all (\x -> not (isNaN x || isInfinite x)) observedOutput
        )
        "parent RETURN forward width or finite values differ"
      Return.NativeForwardObservation
        <$> int identity
        <*> magnitude ordinal
        <*> pure params
        <*> pure observedInput
        <*> pure (Return.NativeForwardReturned (Right observedOutput))
    _ -> reject "parent complete RETURN forward was failed or has invalid fields"

herSchedule :: Digest -> Decode HerRef.NativeHerGoalSchedule
herSchedule root = do
  actual <- fields NHerSchedule root
  case actual of
    [VRef spec, VRef cases] -> do
      canonical <- either reject pure HerRef.canonicalNativeHerReferenceSpec
      observed <- fields NHerSpec spec
      let expected =
            VText (HerRef.nativeHerSpecRowId canonical)
              : map
                (VInt . fromIntegral)
                [ HerRef.nativeHerSpecBits canonical
                , HerRef.nativeHerSpecHorizon canonical
                , HerRef.nativeHerSpecEpisodeCount canonical
                , HerRef.nativeHerSpecBaseSeed canonical
                , HerRef.nativeHerSpecEvaluationSeed canonical
                ]
                <> [Cases.trainingBudget (HerRef.nativeHerSpecTrainingBudget canonical)]
      require
        (observed == expected)
        "parent HER schedule full specification differs from the current canonical declaration"
      roots <- referenceData (RefElement NHerGoalCase) 20 cases
      require (length roots == 20) "parent HER retained schedule count differs before goal expansion"
      goals <-
        traverse
          ( \digest -> do
              value <- fields NHerGoalCase digest
              case value of
                [identity, VRef goal] -> do
                  vector <- tensor 6 goal
                  require (VU.length vector == 6) "parent HER goal width differs"
                  HerRef.RawNativeHerGoalCase <$> int identity <*> pure vector
                _ -> reject "parent HER goal fields differ"
          )
          roots
      either reject pure (HerRef.refineNativeHerGoalSchedule canonical goals)
    _ -> reject "parent HER schedule fields differ"

herEvaluation
  :: HerRef.NativeHerGoalSchedule
  -> Digest
  -> Her.HerTrainConfig
  -> Digest
  -> Digest
  -> Decode HerEval.RawNativeHerEvaluation
herEvaluation schedule scheduleRoot config configRoot root = do
  actual <- fields NHerEvaluation root
  case actual of
    [ VRef s
      , VRef c
      , VRef p
      , VRef outcomes
      , VRef forwards
      , VList [VWord 0]
      , VList [VWord 0, work]
      , VNull
      ] -> do
        require
          (s == scheduleRoot && c == configRoot)
          "parent HER schedule or full canonical config differs"
        params <- parameters p
        outcomeRoots <- referenceData (RefElement NHerOutcome) 20 outcomes
        require (length outcomeRoots == 20) "parent HER evaluation lacks its exact twenty cases"
        cases <- traverse herOutcome outcomeRoots
        forwardRoots <- referenceData (RefElement NHerForward) 120 forwards
        events <- traverse (herForward p params) forwardRoots
        transitions <- magnitude work
        let raw =
              HerEval.RawNativeHerEvaluation
                schedule
                config
                params
                cases
                events
                HerEval.NativeHerEvaluationComplete
                (HerEval.NativeHerCompleteWork transitions)
                Nothing
        either reject pure (HerEval.validateNativeHerEvaluationContext schedule config params)
        pure raw
    _ -> reject "parent HER evaluation is incomplete, failed or retains failed progress"

herOutcome :: Digest -> Decode HerRef.NativeHerReferenceOutcome
herOutcome root = do
  actual <- fields NHerOutcome root
  case actual of
    [identity, VRef goal, VRef state, success, distance, hamming, steps, terminated, VRef actions] -> do
      goal_ <- tensor 6 goal
      state_ <- tensor 6 state
      require (VU.length goal_ == 6 && VU.length state_ == 6) "parent HER outcome vector width differs"
      actions_ <- sequenceData (ScalarElement ScalarInt) 6 actions >>= traverse int
      HerRef.NativeHerReferenceOutcome
        <$> int identity
        <*> pure goal_
        <*> pure state_
        <*> bool success
        <*> bits distance
        <*> int hamming
        <*> int steps
        <*> bool terminated
        <*> pure actions_
    _ -> reject "parent HER outcome fields differ"
herForward :: Digest -> Mlp.MlpParams -> Digest -> Decode HerEval.NativeHerForwardObservation
herForward fixed params root = do
  actual <- fields NHerForward root
  case actual of
    [identity, ordinal, VRef p, VRef input, VList [VWord 0, VRef output]] -> do
      require (p == fixed) "parent HER forward changed the actual full policy params"
      input_ <- tensor 12 input
      output_ <- tensor 6 output
      require (VU.length input_ == 12 && VU.length output_ == 6) "parent HER forward shape differs"
      HerEval.NativeHerForwardObservation
        <$> int identity
        <*> int ordinal
        <*> pure params
        <*> pure input_
        <*> pure (HerEval.NativeHerForwardReturned (Right output_))
    _ -> reject "parent complete HER forward was failed or has invalid fields"

arenaEvaluation
  :: ArenaRef.NativeArenaSpec
  -> Digest
  -> Tape.ArenaTape
  -> Digest
  -> Decode Arena.RawNativeArenaEvaluation
arenaEvaluation spec specRoot tape root = do
  actual <- fields NArenaEvaluation root
  case actual of
    [ VRef input
      , VRef episodes
      , VNull
      , VRef forwards
      , VList [VWord 0]
      , VList [completed, current, visits, VWord 0]
      ] -> do
        (policy, p) <- arenaInput spec specRoot tape input
        episodeRoots <- referenceData (RefElement NArenaEpisode) 9 episodes
        require (length episodeRoots == 9) "parent arena evaluation lacks its exact nine games"
        games <- traverse (arenaEpisode spec tape) episodeRoots
        summary <- arenaSummary p (Net.pvnParams policy) forwards
        work <-
          Arena.NativeArenaEvaluationWork
            <$> magnitude completed
            <*> magnitude current
            <*> magnitude visits
            <*> pure Arena.NoUnfinishedArenaSearch
        initial <- case games of
          first : _ -> pure (ArenaRef.nativeArenaEpisodeInitialState first)
          [] -> reject "parent arena episodes absent"
        let actualInput = Arena.NativeArenaInput Arena.CanonicalNativeArena (Just spec) initial tape policy
            raw =
              Arena.RawNativeArenaEvaluation
                (Just actualInput)
                games
                Nothing
                summary
                Arena.NativeArenaEvaluationComplete
                work
        either reject pure (Arena.validateNativeArenaEvaluationData spec tape policy raw)
        pure raw
    _ -> reject "parent arena evaluation is incomplete, failed or retains partial search work"
arenaInput
  :: ArenaRef.NativeArenaSpec
  -> Digest
  -> Tape.ArenaTape
  -> Digest
  -> Decode (Net.PolicyValueNet, Digest)
arenaInput spec specRoot tape root = do
  actual <- fields NArenaInput root
  case actual of
    [VWord 0, VRef s, VRef initial, VRef t, VRef policy] -> do
      require (s == specRoot) "parent arena full canonical spec differs"
      actualTape <- fields NArenaTape t
      require
        (actualTape == [VBytes (Tape.arenaTapeBytes tape)])
        "parent arena fixed addressed tape bytes differ"
      state <- gameState initial
      require
        (state == Game.initialStateFor (ArenaRef.nativeArenaSpecRowId spec))
        "parent arena initial state differs"
      net <- fields NPVN policy
      case net of
        [VRef p, a, o] -> do
          params <- parameters p
          actions <- int a
          observations <- int o
          require
            ( actions == ArenaRef.nativeArenaSpecActionCount spec
                && observations == ArenaRef.nativeArenaSpecObservationSize spec
            )
            "parent arena public policy head dimensions differ"
          pure (Net.PolicyValueNet params actions observations, p)
        _ -> reject "parent arena policy fields differ"
    _ -> reject "parent arena input is not the complete canonical input"
arenaSummary :: Digest -> Mlp.MlpParams -> Digest -> Decode Arena.NativeArenaForwardSummary
arenaSummary fixed params root = do
  actual <- fields NArenaSummary root
  case actual of
    [calls, VRef firsts, VNull] -> do
      roots <- referenceData (RefElement NArenaForward) 9 firsts
      events <- traverse one roots
      Arena.NativeArenaForwardSummary <$> magnitude calls <*> pure events <*> pure Nothing
    _ -> reject "parent complete arena summary retains failure or differs"
 where
  one digest = do
    actual <- fields NArenaForward digest
    case actual of
      [game, slot, ordinal, VRef p, VRef input, VList [VWord 0, VRef output]] -> do
        require (p == fixed) "parent arena forward changed complete policy params"
        input_ <- tensor (toInteger (Mlp.mlpInputs (Mlp.paramShape params))) input
        output_ <- tensor (toInteger (Mlp.mlpOutputs (Mlp.paramShape params))) output
        Arena.NativeArenaForwardObservation
          <$> int game
          <*> int slot
          <*> magnitude ordinal
          <*> pure params
          <*> pure input_
          <*> pure (Arena.NativeArenaForwardReturned (Right output_))
      _ -> reject "parent complete arena forward has failed or invalid fields"

arenaEpisode
  :: ArenaRef.NativeArenaSpec -> Tape.ArenaTape -> Digest -> Decode ArenaRef.NativeArenaEpisode
arenaEpisode spec tape root = do
  actual <- fields NArenaEpisode root
  case actual of
    [identity, VRef initial, VRef final, rule, scored, truncated, VRef decisions] -> do
      roots <-
        referenceData
          (RefElement NArenaDecision)
          (toInteger (ArenaRef.nativeArenaSpecMaxPlies spec))
          decisions
      history <- traverse (arenaDecision spec tape) roots
      ArenaRef.NativeArenaEpisode
        <$> int identity
        <*> gameState initial
        <*> gameState final
        <*> outcome rule
        <*> outcome scored
        <*> bool truncated
        <*> pure history
    _ -> reject "parent arena episode fields differ"
arenaDecision
  :: ArenaRef.NativeArenaSpec -> Tape.ArenaTape -> Digest -> Decode ArenaRef.NativeArenaDecision
arenaDecision spec tape root = do
  actual <- fields NArenaDecision root
  case actual of
    [ slot
      , VRef raw
      , VRef normalized
      , forced
      , player
      , VRef legal
      , VRef distribution
      , action
      , VRef entry
      , visits
      , VRef post
      , postOutcome
      ] -> do
        legal_ <-
          sequenceData (ScalarElement ScalarInt) (toInteger (ArenaRef.nativeArenaSpecActionCount spec)) legal
            >>= traverse int
        distribution_ <- tensor (toInteger (ArenaRef.nativeArenaSpecActionCount spec)) distribution
        require
          (VU.length distribution_ == ArenaRef.nativeArenaSpecActionCount spec)
          "parent arena distribution width differs"
        ArenaRef.NativeArenaDecision
          <$> int slot
          <*> gameState raw
          <*> gameState normalized
          <*> bool forced
          <*> int player
          <*> pure legal_
          <*> pure distribution_
          <*> int action
          <*> tapeEntry tape entry
          <*> int visits
          <*> gameState post
          <*> outcome postOutcome
    _ -> reject "parent arena decision fields differ"
