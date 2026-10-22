-- | Public fixed-case/spec observations only. No sampler, renderer, initializer
-- or evaluator is called; supplied opaque schedules are never regenerated.
module JitML.Checkpoint.NativePhase.Projection.Cases
  ( returnSpec
  , herSchedule
  , arenaSpec
  , arenaTape
  , trainingBudget
  ) where

import Data.ByteString qualified as BS

import JitML.Checkpoint.NativePhase.Projection.Build
import JitML.Checkpoint.NativePhase.Types
import JitML.RL.AlphaZero.ArenaTape qualified as Tape
import JitML.RL.AlphaZero.NativeArenaReferences qualified as Arena
import JitML.RL.NativeHerReferences qualified as Her
import JitML.RL.NativeReturnReferences qualified as Return
import JitML.RL.ProductBudget qualified as Plan
import JitML.Training.Budget qualified as Budget

-- This is the named public-getter projection, not the private threshold row.
-- The whole canonical row remains independently bound by parent/cohort data.
returnSpec :: Return.NativeReturnReferenceSpec -> Build Digest
returnSpec actual = do
  identity <- textValue GeneralTextBytes (Return.nativeReturnSpecRowId actual)
  algorithm <- textValue GeneralTextBytes (Return.nativeReturnSpecAlgorithm actual)
  environment <- textValue GeneralTextBytes (Return.nativeReturnSpecEnvironment actual)
  trainer <- textValue GeneralTextBytes (Return.nativeReturnSpecTrainer actual)
  schedule <- trainingSchedule (Return.nativeReturnSpecSchedule actual)
  count <- intValue (Return.nativeReturnSpecEpisodeCount actual)
  horizon <- intValue (Return.nativeReturnSpecHorizon actual)
  observations <- intValue (Return.nativeReturnSpecObservationSize actual)
  domain <- case Return.nativeReturnSpecDomain actual of
    Return.NativeUnmaskedDiscrete n -> do
      countValue <- intValue n
      pure (VList [VWord 0, countValue])
    Return.NativeMaskedDiscrete n -> do
      countValue <- intValue n
      pure (VList [VWord 1, countValue])
    Return.NativeContinuous low high -> pure (VList [VWord 2, bitValue low, bitValue high])
  emit
    NReturnSpec
    [ identity
    , algorithm
    , environment
    , trainer
    , trainingBudget (Return.nativeReturnSpecBudget actual)
    , schedule
    , count
    , horizon
    , observations
    , domain
    ]

trainingBudget :: Budget.TrainingBudget -> NodeValue
trainingBudget actual =
  VList
    [ VWord $ case Budget.trainingBudgetKind actual of
        Budget.SupervisedEpochBudget -> 0
        Budget.RlEnvironmentStepBudget -> 1
        Budget.AlphaZeroSelfPlayBudget -> 2
        Budget.TuningTrialBudget -> 3
    , VWord (Budget.trainingBudgetTargetUnits actual)
    , maybe VNull VWord (Budget.trainingBudgetSeed actual)
    ]

trainingSchedule :: Plan.RlTrainingSchedule -> Build NodeValue
trainingSchedule actual = case actual of
  Plan.OnPolicyTrainingSchedule observed iterations rollout slots horizon -> do
    fields <- traverse intValue [iterations, rollout, slots, horizon]
    pure (VList ([VWord 0, VWord observed] <> fields))
  Plan.FixedStepTrainingSchedule observed steps horizon -> do
    fields <- traverse intValue [steps, horizon]
    pure (VList ([VWord 1, VWord observed] <> fields))
  Plan.ArsTrainingSchedule observed iterations directions horizon -> do
    fields <- traverse intValue [iterations, directions, horizon]
    pure (VList ([VWord 2, VWord observed] <> fields))
  Plan.HerTrainingSchedule observed episodes steps -> do
    fields <- traverse intValue [episodes, steps]
    pure (VList ([VWord 3, VWord observed] <> fields))

herSchedule :: Her.NativeHerGoalSchedule -> Build Digest
herSchedule actual = do
  spec <- herSpec (Her.nativeHerScheduleSpec actual)
  cases <- referenceSequence (RefElement NHerGoalCase) herCase (Her.nativeHerScheduleCases actual)
  emit NHerSchedule [VRef spec, VRef cases]

herSpec :: Her.NativeHerReferenceSpec -> Build Digest
herSpec actual = do
  identity <- textValue GeneralTextBytes (Her.nativeHerSpecRowId actual)
  fields <-
    traverse
      intValue
      [ Her.nativeHerSpecBits actual
      , Her.nativeHerSpecHorizon actual
      , Her.nativeHerSpecEpisodeCount actual
      , Her.nativeHerSpecBaseSeed actual
      , Her.nativeHerSpecEvaluationSeed actual
      ]
  emit NHerSpec ([identity] <> fields <> [trainingBudget (Her.nativeHerSpecTrainingBudget actual)])

herCase :: Her.RawNativeHerGoalCase -> Build Digest
herCase (Her.RawNativeHerGoalCase identity goal) = do
  caseId <- intValue identity
  vector <- tensor goal
  emit NHerGoalCase [caseId, VRef vector]

arenaSpec :: Arena.NativeArenaSpec -> Build Digest
arenaSpec actual = do
  identity <- textValue GeneralTextBytes (Arena.nativeArenaSpecRowId actual)
  fields <-
    traverse
      intValue
      [ Arena.nativeArenaSpecActionCount actual
      , Arena.nativeArenaSpecObservationSize actual
      , Arena.nativeArenaSpecMaxPlies actual
      , Arena.nativeArenaSpecArenaSimulations actual
      ]
  tape <- tapeSpec (Arena.nativeArenaSpecTape actual)
  emit
    NArenaSpec
    ( [ identity
      , trainingBudget (Arena.nativeArenaSpecTrainingBudget actual)
      , VWord (Arena.nativeArenaSpecTrainingSimulations actual)
      ]
        <> fields
        <> [tape]
    )

tapeSpec :: Tape.ArenaTapeSpec -> Build NodeValue
tapeSpec actual = do
  identity <- textValue GeneralTextBytes (Tape.arenaTapeSpecRow actual)
  entries <- wordValue (Tape.arenaTapeSpecEntryCount actual)
  bytes <- wordValue (Tape.arenaTapeSpecEncodedLength actual)
  pure
    ( VList
        [ identity
        , VWord (Tape.arenaTapeSpecBase actual)
        , VWord (Tape.arenaTapeSpecGames actual)
        , VWord (Tape.arenaTapeSpecMaxPlies actual)
        , entries
        , bytes
        ]
    )

arenaTape :: Tape.ArenaTape -> Build Digest
arenaTape actual = do
  let bytes = Tape.arenaTapeBytes actual
  dataEither (checkLimit TensorChunkBytes (toInteger (BS.length bytes)))
  emit NArenaTape [VBytes bytes]
