{- This file was auto-generated from jitml/tune.proto by the proto-lens-protoc program. -}
{-# LANGUAGE ScopedTypeVariables, DataKinds, TypeFamilies, UndecidableInstances, GeneralizedNewtypeDeriving, MultiParamTypeClasses, FlexibleContexts, FlexibleInstances, PatternSynonyms, MagicHash, NoImplicitPrelude, DataKinds, BangPatterns, TypeApplications, OverloadedStrings, DerivingStrategies#-}
{-# OPTIONS_GHC -Wno-unused-imports#-}
{-# OPTIONS_GHC -Wno-duplicate-exports#-}
{-# OPTIONS_GHC -Wno-dodgy-exports#-}
module Proto.Jitml.Tune (
        StartSweep(), StopSweep(), SweepCompleted(), SweepFinished(),
        TrialFinished(), TrialStarted(), TuneCommand(),
        TuneCommand'Body(..), _TuneCommand'Start, _TuneCommand'Stop,
        TuneEvent(), TuneEvent'Body(..), _TuneEvent'Started,
        _TuneEvent'Finished, _TuneEvent'SweepFinished,
        _TuneEvent'SweepCompleted
    ) where
import qualified Data.ProtoLens.Runtime.Control.DeepSeq as Control.DeepSeq
import qualified Data.ProtoLens.Runtime.Data.ProtoLens.Prism as Data.ProtoLens.Prism
import qualified Data.ProtoLens.Runtime.Prelude as Prelude
import qualified Data.ProtoLens.Runtime.Data.Int as Data.Int
import qualified Data.ProtoLens.Runtime.Data.Monoid as Data.Monoid
import qualified Data.ProtoLens.Runtime.Data.Word as Data.Word
import qualified Data.ProtoLens.Runtime.Data.ProtoLens as Data.ProtoLens
import qualified Data.ProtoLens.Runtime.Data.ProtoLens.Encoding.Bytes as Data.ProtoLens.Encoding.Bytes
import qualified Data.ProtoLens.Runtime.Data.ProtoLens.Encoding.Growing as Data.ProtoLens.Encoding.Growing
import qualified Data.ProtoLens.Runtime.Data.ProtoLens.Encoding.Parser.Unsafe as Data.ProtoLens.Encoding.Parser.Unsafe
import qualified Data.ProtoLens.Runtime.Data.ProtoLens.Encoding.Wire as Data.ProtoLens.Encoding.Wire
import qualified Data.ProtoLens.Runtime.Data.ProtoLens.Field as Data.ProtoLens.Field
import qualified Data.ProtoLens.Runtime.Data.ProtoLens.Message.Enum as Data.ProtoLens.Message.Enum
import qualified Data.ProtoLens.Runtime.Data.ProtoLens.Service.Types as Data.ProtoLens.Service.Types
import qualified Data.ProtoLens.Runtime.Lens.Family2 as Lens.Family2
import qualified Data.ProtoLens.Runtime.Lens.Family2.Unchecked as Lens.Family2.Unchecked
import qualified Data.ProtoLens.Runtime.Data.Text as Data.Text
import qualified Data.ProtoLens.Runtime.Data.Map as Data.Map
import qualified Data.ProtoLens.Runtime.Data.ByteString as Data.ByteString
import qualified Data.ProtoLens.Runtime.Data.ByteString.Char8 as Data.ByteString.Char8
import qualified Data.ProtoLens.Runtime.Data.Text.Encoding as Data.Text.Encoding
import qualified Data.ProtoLens.Runtime.Data.Vector as Data.Vector
import qualified Data.ProtoLens.Runtime.Data.Vector.Generic as Data.Vector.Generic
import qualified Data.ProtoLens.Runtime.Data.Vector.Unboxed as Data.Vector.Unboxed
import qualified Data.ProtoLens.Runtime.Text.Read as Text.Read
{- | Fields :

         * 'Proto.Jitml.Tune_Fields.experimentHash' @:: Lens' StartSweep Data.Text.Text@
         * 'Proto.Jitml.Tune_Fields.dhallObjectKey' @:: Lens' StartSweep Data.Text.Text@
         * 'Proto.Jitml.Tune_Fields.substrate' @:: Lens' StartSweep Data.Text.Text@
         * 'Proto.Jitml.Tune_Fields.sweepSeed' @:: Lens' StartSweep Data.Word.Word64@
         * 'Proto.Jitml.Tune_Fields.trialBudget' @:: Lens' StartSweep Data.Word.Word32@
         * 'Proto.Jitml.Tune_Fields.budgetPerTrial' @:: Lens' StartSweep Data.Word.Word32@
         * 'Proto.Jitml.Tune_Fields.sampler' @:: Lens' StartSweep Data.Text.Text@
         * 'Proto.Jitml.Tune_Fields.scheduler' @:: Lens' StartSweep Data.Text.Text@
         * 'Proto.Jitml.Tune_Fields.pruner' @:: Lens' StartSweep Data.Text.Text@
         * 'Proto.Jitml.Tune_Fields.parallelism' @:: Lens' StartSweep Data.Word.Word32@
         * 'Proto.Jitml.Tune_Fields.promotions' @:: Lens' StartSweep Data.Word.Word32@
         * 'Proto.Jitml.Tune_Fields.planId' @:: Lens' StartSweep Data.Text.Text@
         * 'Proto.Jitml.Tune_Fields.resolvedPlan' @:: Lens' StartSweep Data.Text.Text@ -}
data StartSweep
  = StartSweep'_constructor {_StartSweep'experimentHash :: !Data.Text.Text,
                             _StartSweep'dhallObjectKey :: !Data.Text.Text,
                             _StartSweep'substrate :: !Data.Text.Text,
                             _StartSweep'sweepSeed :: !Data.Word.Word64,
                             _StartSweep'trialBudget :: !Data.Word.Word32,
                             _StartSweep'budgetPerTrial :: !Data.Word.Word32,
                             _StartSweep'sampler :: !Data.Text.Text,
                             _StartSweep'scheduler :: !Data.Text.Text,
                             _StartSweep'pruner :: !Data.Text.Text,
                             _StartSweep'parallelism :: !Data.Word.Word32,
                             _StartSweep'promotions :: !Data.Word.Word32,
                             _StartSweep'planId :: !Data.Text.Text,
                             _StartSweep'resolvedPlan :: !Data.Text.Text,
                             _StartSweep'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show StartSweep where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField StartSweep "experimentHash" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartSweep'experimentHash
           (\ x__ y__ -> x__ {_StartSweep'experimentHash = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField StartSweep "dhallObjectKey" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartSweep'dhallObjectKey
           (\ x__ y__ -> x__ {_StartSweep'dhallObjectKey = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField StartSweep "substrate" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartSweep'substrate
           (\ x__ y__ -> x__ {_StartSweep'substrate = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField StartSweep "sweepSeed" Data.Word.Word64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartSweep'sweepSeed
           (\ x__ y__ -> x__ {_StartSweep'sweepSeed = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField StartSweep "trialBudget" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartSweep'trialBudget
           (\ x__ y__ -> x__ {_StartSweep'trialBudget = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField StartSweep "budgetPerTrial" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartSweep'budgetPerTrial
           (\ x__ y__ -> x__ {_StartSweep'budgetPerTrial = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField StartSweep "sampler" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartSweep'sampler (\ x__ y__ -> x__ {_StartSweep'sampler = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField StartSweep "scheduler" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartSweep'scheduler
           (\ x__ y__ -> x__ {_StartSweep'scheduler = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField StartSweep "pruner" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartSweep'pruner (\ x__ y__ -> x__ {_StartSweep'pruner = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField StartSweep "parallelism" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartSweep'parallelism
           (\ x__ y__ -> x__ {_StartSweep'parallelism = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField StartSweep "promotions" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartSweep'promotions
           (\ x__ y__ -> x__ {_StartSweep'promotions = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField StartSweep "planId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartSweep'planId (\ x__ y__ -> x__ {_StartSweep'planId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField StartSweep "resolvedPlan" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartSweep'resolvedPlan
           (\ x__ y__ -> x__ {_StartSweep'resolvedPlan = y__}))
        Prelude.id
instance Data.ProtoLens.Message StartSweep where
  messageName _ = Data.Text.pack "jitml.tune.StartSweep"
  packedMessageDescriptor _
    = "\n\
      \\n\
      \StartSweep\DC2'\n\
      \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2(\n\
      \\DLEdhall_object_key\CAN\STX \SOH(\tR\SOdhallObjectKey\DC2\FS\n\
      \\tsubstrate\CAN\ETX \SOH(\tR\tsubstrate\DC2\GS\n\
      \\n\
      \sweep_seed\CAN\EOT \SOH(\EOTR\tsweepSeed\DC2!\n\
      \\ftrial_budget\CAN\ENQ \SOH(\rR\vtrialBudget\DC2(\n\
      \\DLEbudget_per_trial\CAN\ACK \SOH(\rR\SObudgetPerTrial\DC2\CAN\n\
      \\asampler\CAN\a \SOH(\tR\asampler\DC2\FS\n\
      \\tscheduler\CAN\b \SOH(\tR\tscheduler\DC2\SYN\n\
      \\ACKpruner\CAN\t \SOH(\tR\ACKpruner\DC2 \n\
      \\vparallelism\CAN\n\
      \ \SOH(\rR\vparallelism\DC2\RS\n\
      \\n\
      \promotions\CAN\v \SOH(\rR\n\
      \promotions\DC2\ETB\n\
      \\aplan_id\CAN\f \SOH(\tR\ACKplanId\DC2#\n\
      \\rresolved_plan\CAN\r \SOH(\tR\fresolvedPlan"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        experimentHash__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "experiment_hash"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"experimentHash")) ::
              Data.ProtoLens.FieldDescriptor StartSweep
        dhallObjectKey__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "dhall_object_key"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"dhallObjectKey")) ::
              Data.ProtoLens.FieldDescriptor StartSweep
        substrate__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "substrate"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"substrate")) ::
              Data.ProtoLens.FieldDescriptor StartSweep
        sweepSeed__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "sweep_seed"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word64)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"sweepSeed")) ::
              Data.ProtoLens.FieldDescriptor StartSweep
        trialBudget__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "trial_budget"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"trialBudget")) ::
              Data.ProtoLens.FieldDescriptor StartSweep
        budgetPerTrial__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "budget_per_trial"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"budgetPerTrial")) ::
              Data.ProtoLens.FieldDescriptor StartSweep
        sampler__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "sampler"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"sampler")) ::
              Data.ProtoLens.FieldDescriptor StartSweep
        scheduler__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "scheduler"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"scheduler")) ::
              Data.ProtoLens.FieldDescriptor StartSweep
        pruner__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "pruner"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"pruner")) ::
              Data.ProtoLens.FieldDescriptor StartSweep
        parallelism__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "parallelism"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"parallelism")) ::
              Data.ProtoLens.FieldDescriptor StartSweep
        promotions__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "promotions"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"promotions")) ::
              Data.ProtoLens.FieldDescriptor StartSweep
        planId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "plan_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"planId")) ::
              Data.ProtoLens.FieldDescriptor StartSweep
        resolvedPlan__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "resolved_plan"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"resolvedPlan")) ::
              Data.ProtoLens.FieldDescriptor StartSweep
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, experimentHash__field_descriptor),
           (Data.ProtoLens.Tag 2, dhallObjectKey__field_descriptor),
           (Data.ProtoLens.Tag 3, substrate__field_descriptor),
           (Data.ProtoLens.Tag 4, sweepSeed__field_descriptor),
           (Data.ProtoLens.Tag 5, trialBudget__field_descriptor),
           (Data.ProtoLens.Tag 6, budgetPerTrial__field_descriptor),
           (Data.ProtoLens.Tag 7, sampler__field_descriptor),
           (Data.ProtoLens.Tag 8, scheduler__field_descriptor),
           (Data.ProtoLens.Tag 9, pruner__field_descriptor),
           (Data.ProtoLens.Tag 10, parallelism__field_descriptor),
           (Data.ProtoLens.Tag 11, promotions__field_descriptor),
           (Data.ProtoLens.Tag 12, planId__field_descriptor),
           (Data.ProtoLens.Tag 13, resolvedPlan__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _StartSweep'_unknownFields
        (\ x__ y__ -> x__ {_StartSweep'_unknownFields = y__})
  defMessage
    = StartSweep'_constructor
        {_StartSweep'experimentHash = Data.ProtoLens.fieldDefault,
         _StartSweep'dhallObjectKey = Data.ProtoLens.fieldDefault,
         _StartSweep'substrate = Data.ProtoLens.fieldDefault,
         _StartSweep'sweepSeed = Data.ProtoLens.fieldDefault,
         _StartSweep'trialBudget = Data.ProtoLens.fieldDefault,
         _StartSweep'budgetPerTrial = Data.ProtoLens.fieldDefault,
         _StartSweep'sampler = Data.ProtoLens.fieldDefault,
         _StartSweep'scheduler = Data.ProtoLens.fieldDefault,
         _StartSweep'pruner = Data.ProtoLens.fieldDefault,
         _StartSweep'parallelism = Data.ProtoLens.fieldDefault,
         _StartSweep'promotions = Data.ProtoLens.fieldDefault,
         _StartSweep'planId = Data.ProtoLens.fieldDefault,
         _StartSweep'resolvedPlan = Data.ProtoLens.fieldDefault,
         _StartSweep'_unknownFields = []}
  parseMessage
    = let
        loop ::
          StartSweep -> Data.ProtoLens.Encoding.Bytes.Parser StartSweep
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "experiment_hash"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"experimentHash") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "dhall_object_key"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"dhallObjectKey") y x)
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "substrate"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"substrate") y x)
                        32
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       Data.ProtoLens.Encoding.Bytes.getVarInt "sweep_seed"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"sweepSeed") y x)
                        40
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "trial_budget"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"trialBudget") y x)
                        48
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "budget_per_trial"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"budgetPerTrial") y x)
                        58
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "sampler"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"sampler") y x)
                        66
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "scheduler"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"scheduler") y x)
                        74
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "pruner"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"pruner") y x)
                        80
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "parallelism"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"parallelism") y x)
                        88
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "promotions"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"promotions") y x)
                        98
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "plan_id"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"planId") y x)
                        106
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "resolved_plan"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"resolvedPlan") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "StartSweep"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v
                  = Lens.Family2.view
                      (Data.ProtoLens.Field.field @"experimentHash") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             ((Data.Monoid.<>)
                (let
                   _v
                     = Lens.Family2.view
                         (Data.ProtoLens.Field.field @"dhallObjectKey") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                         ((Prelude..)
                            (\ bs
                               -> (Data.Monoid.<>)
                                    (Data.ProtoLens.Encoding.Bytes.putVarInt
                                       (Prelude.fromIntegral (Data.ByteString.length bs)))
                                    (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                            Data.Text.Encoding.encodeUtf8 _v))
                ((Data.Monoid.<>)
                   (let
                      _v = Lens.Family2.view (Data.ProtoLens.Field.field @"substrate") _x
                    in
                      if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                          Data.Monoid.mempty
                      else
                          (Data.Monoid.<>)
                            (Data.ProtoLens.Encoding.Bytes.putVarInt 26)
                            ((Prelude..)
                               (\ bs
                                  -> (Data.Monoid.<>)
                                       (Data.ProtoLens.Encoding.Bytes.putVarInt
                                          (Prelude.fromIntegral (Data.ByteString.length bs)))
                                       (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                               Data.Text.Encoding.encodeUtf8 _v))
                   ((Data.Monoid.<>)
                      (let
                         _v = Lens.Family2.view (Data.ProtoLens.Field.field @"sweepSeed") _x
                       in
                         if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                             Data.Monoid.mempty
                         else
                             (Data.Monoid.<>)
                               (Data.ProtoLens.Encoding.Bytes.putVarInt 32)
                               (Data.ProtoLens.Encoding.Bytes.putVarInt _v))
                      ((Data.Monoid.<>)
                         (let
                            _v
                              = Lens.Family2.view (Data.ProtoLens.Field.field @"trialBudget") _x
                          in
                            if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                Data.Monoid.mempty
                            else
                                (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt 40)
                                  ((Prelude..)
                                     Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral
                                     _v))
                         ((Data.Monoid.<>)
                            (let
                               _v
                                 = Lens.Family2.view
                                     (Data.ProtoLens.Field.field @"budgetPerTrial") _x
                             in
                               if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                   Data.Monoid.mempty
                               else
                                   (Data.Monoid.<>)
                                     (Data.ProtoLens.Encoding.Bytes.putVarInt 48)
                                     ((Prelude..)
                                        Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral
                                        _v))
                            ((Data.Monoid.<>)
                               (let
                                  _v = Lens.Family2.view (Data.ProtoLens.Field.field @"sampler") _x
                                in
                                  if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                      Data.Monoid.mempty
                                  else
                                      (Data.Monoid.<>)
                                        (Data.ProtoLens.Encoding.Bytes.putVarInt 58)
                                        ((Prelude..)
                                           (\ bs
                                              -> (Data.Monoid.<>)
                                                   (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                      (Prelude.fromIntegral
                                                         (Data.ByteString.length bs)))
                                                   (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                           Data.Text.Encoding.encodeUtf8 _v))
                               ((Data.Monoid.<>)
                                  (let
                                     _v
                                       = Lens.Family2.view
                                           (Data.ProtoLens.Field.field @"scheduler") _x
                                   in
                                     if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                         Data.Monoid.mempty
                                     else
                                         (Data.Monoid.<>)
                                           (Data.ProtoLens.Encoding.Bytes.putVarInt 66)
                                           ((Prelude..)
                                              (\ bs
                                                 -> (Data.Monoid.<>)
                                                      (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                         (Prelude.fromIntegral
                                                            (Data.ByteString.length bs)))
                                                      (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                              Data.Text.Encoding.encodeUtf8 _v))
                                  ((Data.Monoid.<>)
                                     (let
                                        _v
                                          = Lens.Family2.view
                                              (Data.ProtoLens.Field.field @"pruner") _x
                                      in
                                        if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                            Data.Monoid.mempty
                                        else
                                            (Data.Monoid.<>)
                                              (Data.ProtoLens.Encoding.Bytes.putVarInt 74)
                                              ((Prelude..)
                                                 (\ bs
                                                    -> (Data.Monoid.<>)
                                                         (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                            (Prelude.fromIntegral
                                                               (Data.ByteString.length bs)))
                                                         (Data.ProtoLens.Encoding.Bytes.putBytes
                                                            bs))
                                                 Data.Text.Encoding.encodeUtf8 _v))
                                     ((Data.Monoid.<>)
                                        (let
                                           _v
                                             = Lens.Family2.view
                                                 (Data.ProtoLens.Field.field @"parallelism") _x
                                         in
                                           if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                               Data.Monoid.mempty
                                           else
                                               (Data.Monoid.<>)
                                                 (Data.ProtoLens.Encoding.Bytes.putVarInt 80)
                                                 ((Prelude..)
                                                    Data.ProtoLens.Encoding.Bytes.putVarInt
                                                    Prelude.fromIntegral _v))
                                        ((Data.Monoid.<>)
                                           (let
                                              _v
                                                = Lens.Family2.view
                                                    (Data.ProtoLens.Field.field @"promotions") _x
                                            in
                                              if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                                  Data.Monoid.mempty
                                              else
                                                  (Data.Monoid.<>)
                                                    (Data.ProtoLens.Encoding.Bytes.putVarInt 88)
                                                    ((Prelude..)
                                                       Data.ProtoLens.Encoding.Bytes.putVarInt
                                                       Prelude.fromIntegral _v))
                                           ((Data.Monoid.<>)
                                              (let
                                                 _v
                                                   = Lens.Family2.view
                                                       (Data.ProtoLens.Field.field @"planId") _x
                                               in
                                                 if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                                     Data.Monoid.mempty
                                                 else
                                                     (Data.Monoid.<>)
                                                       (Data.ProtoLens.Encoding.Bytes.putVarInt 98)
                                                       ((Prelude..)
                                                          (\ bs
                                                             -> (Data.Monoid.<>)
                                                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                     (Prelude.fromIntegral
                                                                        (Data.ByteString.length
                                                                           bs)))
                                                                  (Data.ProtoLens.Encoding.Bytes.putBytes
                                                                     bs))
                                                          Data.Text.Encoding.encodeUtf8 _v))
                                              ((Data.Monoid.<>)
                                                 (let
                                                    _v
                                                      = Lens.Family2.view
                                                          (Data.ProtoLens.Field.field
                                                             @"resolvedPlan")
                                                          _x
                                                  in
                                                    if (Prelude.==)
                                                         _v Data.ProtoLens.fieldDefault then
                                                        Data.Monoid.mempty
                                                    else
                                                        (Data.Monoid.<>)
                                                          (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                             106)
                                                          ((Prelude..)
                                                             (\ bs
                                                                -> (Data.Monoid.<>)
                                                                     (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                        (Prelude.fromIntegral
                                                                           (Data.ByteString.length
                                                                              bs)))
                                                                     (Data.ProtoLens.Encoding.Bytes.putBytes
                                                                        bs))
                                                             Data.Text.Encoding.encodeUtf8 _v))
                                                 (Data.ProtoLens.Encoding.Wire.buildFieldSet
                                                    (Lens.Family2.view
                                                       Data.ProtoLens.unknownFields _x))))))))))))))
instance Control.DeepSeq.NFData StartSweep where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_StartSweep'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_StartSweep'experimentHash x__)
                (Control.DeepSeq.deepseq
                   (_StartSweep'dhallObjectKey x__)
                   (Control.DeepSeq.deepseq
                      (_StartSweep'substrate x__)
                      (Control.DeepSeq.deepseq
                         (_StartSweep'sweepSeed x__)
                         (Control.DeepSeq.deepseq
                            (_StartSweep'trialBudget x__)
                            (Control.DeepSeq.deepseq
                               (_StartSweep'budgetPerTrial x__)
                               (Control.DeepSeq.deepseq
                                  (_StartSweep'sampler x__)
                                  (Control.DeepSeq.deepseq
                                     (_StartSweep'scheduler x__)
                                     (Control.DeepSeq.deepseq
                                        (_StartSweep'pruner x__)
                                        (Control.DeepSeq.deepseq
                                           (_StartSweep'parallelism x__)
                                           (Control.DeepSeq.deepseq
                                              (_StartSweep'promotions x__)
                                              (Control.DeepSeq.deepseq
                                                 (_StartSweep'planId x__)
                                                 (Control.DeepSeq.deepseq
                                                    (_StartSweep'resolvedPlan x__) ())))))))))))))
{- | Fields :

         * 'Proto.Jitml.Tune_Fields.experimentHash' @:: Lens' StopSweep Data.Text.Text@ -}
data StopSweep
  = StopSweep'_constructor {_StopSweep'experimentHash :: !Data.Text.Text,
                            _StopSweep'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show StopSweep where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField StopSweep "experimentHash" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StopSweep'experimentHash
           (\ x__ y__ -> x__ {_StopSweep'experimentHash = y__}))
        Prelude.id
instance Data.ProtoLens.Message StopSweep where
  messageName _ = Data.Text.pack "jitml.tune.StopSweep"
  packedMessageDescriptor _
    = "\n\
      \\tStopSweep\DC2'\n\
      \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        experimentHash__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "experiment_hash"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"experimentHash")) ::
              Data.ProtoLens.FieldDescriptor StopSweep
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, experimentHash__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _StopSweep'_unknownFields
        (\ x__ y__ -> x__ {_StopSweep'_unknownFields = y__})
  defMessage
    = StopSweep'_constructor
        {_StopSweep'experimentHash = Data.ProtoLens.fieldDefault,
         _StopSweep'_unknownFields = []}
  parseMessage
    = let
        loop :: StopSweep -> Data.ProtoLens.Encoding.Bytes.Parser StopSweep
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "experiment_hash"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"experimentHash") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "StopSweep"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v
                  = Lens.Family2.view
                      (Data.ProtoLens.Field.field @"experimentHash") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             (Data.ProtoLens.Encoding.Wire.buildFieldSet
                (Lens.Family2.view Data.ProtoLens.unknownFields _x))
instance Control.DeepSeq.NFData StopSweep where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_StopSweep'_unknownFields x__)
             (Control.DeepSeq.deepseq (_StopSweep'experimentHash x__) ())
{- | Fields :

         * 'Proto.Jitml.Tune_Fields.protocolVersion' @:: Lens' SweepCompleted Data.Word.Word32@
         * 'Proto.Jitml.Tune_Fields.finished' @:: Lens' SweepCompleted SweepFinished@
         * 'Proto.Jitml.Tune_Fields.maybe'finished' @:: Lens' SweepCompleted (Prelude.Maybe SweepFinished)@
         * 'Proto.Jitml.Tune_Fields.completedTraining' @:: Lens' SweepCompleted Data.ByteString.ByteString@ -}
data SweepCompleted
  = SweepCompleted'_constructor {_SweepCompleted'protocolVersion :: !Data.Word.Word32,
                                 _SweepCompleted'finished :: !(Prelude.Maybe SweepFinished),
                                 _SweepCompleted'completedTraining :: !Data.ByteString.ByteString,
                                 _SweepCompleted'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show SweepCompleted where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField SweepCompleted "protocolVersion" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SweepCompleted'protocolVersion
           (\ x__ y__ -> x__ {_SweepCompleted'protocolVersion = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SweepCompleted "finished" SweepFinished where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SweepCompleted'finished
           (\ x__ y__ -> x__ {_SweepCompleted'finished = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage)
instance Data.ProtoLens.Field.HasField SweepCompleted "maybe'finished" (Prelude.Maybe SweepFinished) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SweepCompleted'finished
           (\ x__ y__ -> x__ {_SweepCompleted'finished = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SweepCompleted "completedTraining" Data.ByteString.ByteString where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SweepCompleted'completedTraining
           (\ x__ y__ -> x__ {_SweepCompleted'completedTraining = y__}))
        Prelude.id
instance Data.ProtoLens.Message SweepCompleted where
  messageName _ = Data.Text.pack "jitml.tune.SweepCompleted"
  packedMessageDescriptor _
    = "\n\
      \\SOSweepCompleted\DC2)\n\
      \\DLEprotocol_version\CAN\SOH \SOH(\rR\SIprotocolVersion\DC25\n\
      \\bfinished\CAN\STX \SOH(\v2\EM.jitml.tune.SweepFinishedR\bfinished\DC2-\n\
      \\DC2completed_training\CAN\ETX \SOH(\fR\DC1completedTraining"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        protocolVersion__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "protocol_version"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"protocolVersion")) ::
              Data.ProtoLens.FieldDescriptor SweepCompleted
        finished__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "finished"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor SweepFinished)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'finished")) ::
              Data.ProtoLens.FieldDescriptor SweepCompleted
        completedTraining__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "completed_training"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BytesField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.ByteString.ByteString)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"completedTraining")) ::
              Data.ProtoLens.FieldDescriptor SweepCompleted
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, protocolVersion__field_descriptor),
           (Data.ProtoLens.Tag 2, finished__field_descriptor),
           (Data.ProtoLens.Tag 3, completedTraining__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _SweepCompleted'_unknownFields
        (\ x__ y__ -> x__ {_SweepCompleted'_unknownFields = y__})
  defMessage
    = SweepCompleted'_constructor
        {_SweepCompleted'protocolVersion = Data.ProtoLens.fieldDefault,
         _SweepCompleted'finished = Prelude.Nothing,
         _SweepCompleted'completedTraining = Data.ProtoLens.fieldDefault,
         _SweepCompleted'_unknownFields = []}
  parseMessage
    = let
        loop ::
          SweepCompleted
          -> Data.ProtoLens.Encoding.Bytes.Parser SweepCompleted
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        8 -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "protocol_version"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"protocolVersion") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "finished"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"finished") y x)
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getBytes
                                             (Prelude.fromIntegral len))
                                       "completed_training"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"completedTraining") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "SweepCompleted"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v
                  = Lens.Family2.view
                      (Data.ProtoLens.Field.field @"protocolVersion") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 8)
                      ((Prelude..)
                         Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
             ((Data.Monoid.<>)
                (case
                     Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'finished") _x
                 of
                   Prelude.Nothing -> Data.Monoid.mempty
                   (Prelude.Just _v)
                     -> (Data.Monoid.<>)
                          (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                          ((Prelude..)
                             (\ bs
                                -> (Data.Monoid.<>)
                                     (Data.ProtoLens.Encoding.Bytes.putVarInt
                                        (Prelude.fromIntegral (Data.ByteString.length bs)))
                                     (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                             Data.ProtoLens.encodeMessage _v))
                ((Data.Monoid.<>)
                   (let
                      _v
                        = Lens.Family2.view
                            (Data.ProtoLens.Field.field @"completedTraining") _x
                    in
                      if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                          Data.Monoid.mempty
                      else
                          (Data.Monoid.<>)
                            (Data.ProtoLens.Encoding.Bytes.putVarInt 26)
                            ((\ bs
                                -> (Data.Monoid.<>)
                                     (Data.ProtoLens.Encoding.Bytes.putVarInt
                                        (Prelude.fromIntegral (Data.ByteString.length bs)))
                                     (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                               _v))
                   (Data.ProtoLens.Encoding.Wire.buildFieldSet
                      (Lens.Family2.view Data.ProtoLens.unknownFields _x))))
instance Control.DeepSeq.NFData SweepCompleted where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_SweepCompleted'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_SweepCompleted'protocolVersion x__)
                (Control.DeepSeq.deepseq
                   (_SweepCompleted'finished x__)
                   (Control.DeepSeq.deepseq
                      (_SweepCompleted'completedTraining x__) ())))
{- | Fields :

         * 'Proto.Jitml.Tune_Fields.experimentHash' @:: Lens' SweepFinished Data.Text.Text@
         * 'Proto.Jitml.Tune_Fields.trialsCompleted' @:: Lens' SweepFinished Data.Word.Word32@
         * 'Proto.Jitml.Tune_Fields.trialsPruned' @:: Lens' SweepFinished Data.Word.Word32@
         * 'Proto.Jitml.Tune_Fields.bestObjective' @:: Lens' SweepFinished Prelude.Double@
         * 'Proto.Jitml.Tune_Fields.planId' @:: Lens' SweepFinished Data.Text.Text@
         * 'Proto.Jitml.Tune_Fields.trialsPromoted' @:: Lens' SweepFinished Data.Word.Word32@
         * 'Proto.Jitml.Tune_Fields.protocolVersion' @:: Lens' SweepFinished Data.Word.Word32@ -}
data SweepFinished
  = SweepFinished'_constructor {_SweepFinished'experimentHash :: !Data.Text.Text,
                                _SweepFinished'trialsCompleted :: !Data.Word.Word32,
                                _SweepFinished'trialsPruned :: !Data.Word.Word32,
                                _SweepFinished'bestObjective :: !Prelude.Double,
                                _SweepFinished'planId :: !Data.Text.Text,
                                _SweepFinished'trialsPromoted :: !Data.Word.Word32,
                                _SweepFinished'protocolVersion :: !Data.Word.Word32,
                                _SweepFinished'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show SweepFinished where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField SweepFinished "experimentHash" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SweepFinished'experimentHash
           (\ x__ y__ -> x__ {_SweepFinished'experimentHash = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SweepFinished "trialsCompleted" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SweepFinished'trialsCompleted
           (\ x__ y__ -> x__ {_SweepFinished'trialsCompleted = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SweepFinished "trialsPruned" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SweepFinished'trialsPruned
           (\ x__ y__ -> x__ {_SweepFinished'trialsPruned = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SweepFinished "bestObjective" Prelude.Double where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SweepFinished'bestObjective
           (\ x__ y__ -> x__ {_SweepFinished'bestObjective = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SweepFinished "planId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SweepFinished'planId
           (\ x__ y__ -> x__ {_SweepFinished'planId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SweepFinished "trialsPromoted" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SweepFinished'trialsPromoted
           (\ x__ y__ -> x__ {_SweepFinished'trialsPromoted = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SweepFinished "protocolVersion" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SweepFinished'protocolVersion
           (\ x__ y__ -> x__ {_SweepFinished'protocolVersion = y__}))
        Prelude.id
instance Data.ProtoLens.Message SweepFinished where
  messageName _ = Data.Text.pack "jitml.tune.SweepFinished"
  packedMessageDescriptor _
    = "\n\
      \\rSweepFinished\DC2'\n\
      \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2)\n\
      \\DLEtrials_completed\CAN\STX \SOH(\rR\SItrialsCompleted\DC2#\n\
      \\rtrials_pruned\CAN\ETX \SOH(\rR\ftrialsPruned\DC2%\n\
      \\SObest_objective\CAN\EOT \SOH(\SOHR\rbestObjective\DC2\ETB\n\
      \\aplan_id\CAN\ACK \SOH(\tR\ACKplanId\DC2'\n\
      \\SItrials_promoted\CAN\a \SOH(\rR\SOtrialsPromoted\DC2)\n\
      \\DLEprotocol_version\CAN\b \SOH(\rR\SIprotocolVersionJ\EOT\b\ENQ\DLE\ACK"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        experimentHash__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "experiment_hash"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"experimentHash")) ::
              Data.ProtoLens.FieldDescriptor SweepFinished
        trialsCompleted__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "trials_completed"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"trialsCompleted")) ::
              Data.ProtoLens.FieldDescriptor SweepFinished
        trialsPruned__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "trials_pruned"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"trialsPruned")) ::
              Data.ProtoLens.FieldDescriptor SweepFinished
        bestObjective__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "best_objective"
              (Data.ProtoLens.ScalarField Data.ProtoLens.DoubleField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Double)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"bestObjective")) ::
              Data.ProtoLens.FieldDescriptor SweepFinished
        planId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "plan_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"planId")) ::
              Data.ProtoLens.FieldDescriptor SweepFinished
        trialsPromoted__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "trials_promoted"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"trialsPromoted")) ::
              Data.ProtoLens.FieldDescriptor SweepFinished
        protocolVersion__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "protocol_version"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"protocolVersion")) ::
              Data.ProtoLens.FieldDescriptor SweepFinished
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, experimentHash__field_descriptor),
           (Data.ProtoLens.Tag 2, trialsCompleted__field_descriptor),
           (Data.ProtoLens.Tag 3, trialsPruned__field_descriptor),
           (Data.ProtoLens.Tag 4, bestObjective__field_descriptor),
           (Data.ProtoLens.Tag 6, planId__field_descriptor),
           (Data.ProtoLens.Tag 7, trialsPromoted__field_descriptor),
           (Data.ProtoLens.Tag 8, protocolVersion__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _SweepFinished'_unknownFields
        (\ x__ y__ -> x__ {_SweepFinished'_unknownFields = y__})
  defMessage
    = SweepFinished'_constructor
        {_SweepFinished'experimentHash = Data.ProtoLens.fieldDefault,
         _SweepFinished'trialsCompleted = Data.ProtoLens.fieldDefault,
         _SweepFinished'trialsPruned = Data.ProtoLens.fieldDefault,
         _SweepFinished'bestObjective = Data.ProtoLens.fieldDefault,
         _SweepFinished'planId = Data.ProtoLens.fieldDefault,
         _SweepFinished'trialsPromoted = Data.ProtoLens.fieldDefault,
         _SweepFinished'protocolVersion = Data.ProtoLens.fieldDefault,
         _SweepFinished'_unknownFields = []}
  parseMessage
    = let
        loop ::
          SweepFinished -> Data.ProtoLens.Encoding.Bytes.Parser SweepFinished
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "experiment_hash"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"experimentHash") y x)
                        16
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "trials_completed"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"trialsCompleted") y x)
                        24
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "trials_pruned"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"trialsPruned") y x)
                        33
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Data.ProtoLens.Encoding.Bytes.wordToDouble
                                          Data.ProtoLens.Encoding.Bytes.getFixed64)
                                       "best_objective"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"bestObjective") y x)
                        50
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "plan_id"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"planId") y x)
                        56
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "trials_promoted"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"trialsPromoted") y x)
                        64
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "protocol_version"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"protocolVersion") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "SweepFinished"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v
                  = Lens.Family2.view
                      (Data.ProtoLens.Field.field @"experimentHash") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             ((Data.Monoid.<>)
                (let
                   _v
                     = Lens.Family2.view
                         (Data.ProtoLens.Field.field @"trialsCompleted") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 16)
                         ((Prelude..)
                            Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                ((Data.Monoid.<>)
                   (let
                      _v
                        = Lens.Family2.view (Data.ProtoLens.Field.field @"trialsPruned") _x
                    in
                      if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                          Data.Monoid.mempty
                      else
                          (Data.Monoid.<>)
                            (Data.ProtoLens.Encoding.Bytes.putVarInt 24)
                            ((Prelude..)
                               Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                   ((Data.Monoid.<>)
                      (let
                         _v
                           = Lens.Family2.view
                               (Data.ProtoLens.Field.field @"bestObjective") _x
                       in
                         if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                             Data.Monoid.mempty
                         else
                             (Data.Monoid.<>)
                               (Data.ProtoLens.Encoding.Bytes.putVarInt 33)
                               ((Prelude..)
                                  Data.ProtoLens.Encoding.Bytes.putFixed64
                                  Data.ProtoLens.Encoding.Bytes.doubleToWord _v))
                      ((Data.Monoid.<>)
                         (let
                            _v = Lens.Family2.view (Data.ProtoLens.Field.field @"planId") _x
                          in
                            if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                Data.Monoid.mempty
                            else
                                (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt 50)
                                  ((Prelude..)
                                     (\ bs
                                        -> (Data.Monoid.<>)
                                             (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                (Prelude.fromIntegral (Data.ByteString.length bs)))
                                             (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                     Data.Text.Encoding.encodeUtf8 _v))
                         ((Data.Monoid.<>)
                            (let
                               _v
                                 = Lens.Family2.view
                                     (Data.ProtoLens.Field.field @"trialsPromoted") _x
                             in
                               if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                   Data.Monoid.mempty
                               else
                                   (Data.Monoid.<>)
                                     (Data.ProtoLens.Encoding.Bytes.putVarInt 56)
                                     ((Prelude..)
                                        Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral
                                        _v))
                            ((Data.Monoid.<>)
                               (let
                                  _v
                                    = Lens.Family2.view
                                        (Data.ProtoLens.Field.field @"protocolVersion") _x
                                in
                                  if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                      Data.Monoid.mempty
                                  else
                                      (Data.Monoid.<>)
                                        (Data.ProtoLens.Encoding.Bytes.putVarInt 64)
                                        ((Prelude..)
                                           Data.ProtoLens.Encoding.Bytes.putVarInt
                                           Prelude.fromIntegral _v))
                               (Data.ProtoLens.Encoding.Wire.buildFieldSet
                                  (Lens.Family2.view Data.ProtoLens.unknownFields _x))))))))
instance Control.DeepSeq.NFData SweepFinished where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_SweepFinished'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_SweepFinished'experimentHash x__)
                (Control.DeepSeq.deepseq
                   (_SweepFinished'trialsCompleted x__)
                   (Control.DeepSeq.deepseq
                      (_SweepFinished'trialsPruned x__)
                      (Control.DeepSeq.deepseq
                         (_SweepFinished'bestObjective x__)
                         (Control.DeepSeq.deepseq
                            (_SweepFinished'planId x__)
                            (Control.DeepSeq.deepseq
                               (_SweepFinished'trialsPromoted x__)
                               (Control.DeepSeq.deepseq
                                  (_SweepFinished'protocolVersion x__) ())))))))
{- | Fields :

         * 'Proto.Jitml.Tune_Fields.experimentHash' @:: Lens' TrialFinished Data.Text.Text@
         * 'Proto.Jitml.Tune_Fields.trial' @:: Lens' TrialFinished Data.Word.Word32@
         * 'Proto.Jitml.Tune_Fields.objective' @:: Lens' TrialFinished Prelude.Double@
         * 'Proto.Jitml.Tune_Fields.pruned' @:: Lens' TrialFinished Prelude.Bool@
         * 'Proto.Jitml.Tune_Fields.transcriptObjectKey' @:: Lens' TrialFinished Data.Text.Text@
         * 'Proto.Jitml.Tune_Fields.timestampNs' @:: Lens' TrialFinished Data.Word.Word64@
         * 'Proto.Jitml.Tune_Fields.planId' @:: Lens' TrialFinished Data.Text.Text@ -}
data TrialFinished
  = TrialFinished'_constructor {_TrialFinished'experimentHash :: !Data.Text.Text,
                                _TrialFinished'trial :: !Data.Word.Word32,
                                _TrialFinished'objective :: !Prelude.Double,
                                _TrialFinished'pruned :: !Prelude.Bool,
                                _TrialFinished'transcriptObjectKey :: !Data.Text.Text,
                                _TrialFinished'timestampNs :: !Data.Word.Word64,
                                _TrialFinished'planId :: !Data.Text.Text,
                                _TrialFinished'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show TrialFinished where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField TrialFinished "experimentHash" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TrialFinished'experimentHash
           (\ x__ y__ -> x__ {_TrialFinished'experimentHash = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField TrialFinished "trial" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TrialFinished'trial
           (\ x__ y__ -> x__ {_TrialFinished'trial = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField TrialFinished "objective" Prelude.Double where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TrialFinished'objective
           (\ x__ y__ -> x__ {_TrialFinished'objective = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField TrialFinished "pruned" Prelude.Bool where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TrialFinished'pruned
           (\ x__ y__ -> x__ {_TrialFinished'pruned = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField TrialFinished "transcriptObjectKey" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TrialFinished'transcriptObjectKey
           (\ x__ y__ -> x__ {_TrialFinished'transcriptObjectKey = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField TrialFinished "timestampNs" Data.Word.Word64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TrialFinished'timestampNs
           (\ x__ y__ -> x__ {_TrialFinished'timestampNs = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField TrialFinished "planId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TrialFinished'planId
           (\ x__ y__ -> x__ {_TrialFinished'planId = y__}))
        Prelude.id
instance Data.ProtoLens.Message TrialFinished where
  messageName _ = Data.Text.pack "jitml.tune.TrialFinished"
  packedMessageDescriptor _
    = "\n\
      \\rTrialFinished\DC2'\n\
      \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2\DC4\n\
      \\ENQtrial\CAN\STX \SOH(\rR\ENQtrial\DC2\FS\n\
      \\tobjective\CAN\ETX \SOH(\SOHR\tobjective\DC2\SYN\n\
      \\ACKpruned\CAN\EOT \SOH(\bR\ACKpruned\DC22\n\
      \\NAKtranscript_object_key\CAN\ENQ \SOH(\tR\DC3transcriptObjectKey\DC2!\n\
      \\ftimestamp_ns\CAN\ACK \SOH(\EOTR\vtimestampNs\DC2\ETB\n\
      \\aplan_id\CAN\a \SOH(\tR\ACKplanId"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        experimentHash__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "experiment_hash"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"experimentHash")) ::
              Data.ProtoLens.FieldDescriptor TrialFinished
        trial__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "trial"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"trial")) ::
              Data.ProtoLens.FieldDescriptor TrialFinished
        objective__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "objective"
              (Data.ProtoLens.ScalarField Data.ProtoLens.DoubleField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Double)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"objective")) ::
              Data.ProtoLens.FieldDescriptor TrialFinished
        pruned__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "pruned"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BoolField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Bool)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"pruned")) ::
              Data.ProtoLens.FieldDescriptor TrialFinished
        transcriptObjectKey__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "transcript_object_key"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"transcriptObjectKey")) ::
              Data.ProtoLens.FieldDescriptor TrialFinished
        timestampNs__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "timestamp_ns"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word64)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"timestampNs")) ::
              Data.ProtoLens.FieldDescriptor TrialFinished
        planId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "plan_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"planId")) ::
              Data.ProtoLens.FieldDescriptor TrialFinished
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, experimentHash__field_descriptor),
           (Data.ProtoLens.Tag 2, trial__field_descriptor),
           (Data.ProtoLens.Tag 3, objective__field_descriptor),
           (Data.ProtoLens.Tag 4, pruned__field_descriptor),
           (Data.ProtoLens.Tag 5, transcriptObjectKey__field_descriptor),
           (Data.ProtoLens.Tag 6, timestampNs__field_descriptor),
           (Data.ProtoLens.Tag 7, planId__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _TrialFinished'_unknownFields
        (\ x__ y__ -> x__ {_TrialFinished'_unknownFields = y__})
  defMessage
    = TrialFinished'_constructor
        {_TrialFinished'experimentHash = Data.ProtoLens.fieldDefault,
         _TrialFinished'trial = Data.ProtoLens.fieldDefault,
         _TrialFinished'objective = Data.ProtoLens.fieldDefault,
         _TrialFinished'pruned = Data.ProtoLens.fieldDefault,
         _TrialFinished'transcriptObjectKey = Data.ProtoLens.fieldDefault,
         _TrialFinished'timestampNs = Data.ProtoLens.fieldDefault,
         _TrialFinished'planId = Data.ProtoLens.fieldDefault,
         _TrialFinished'_unknownFields = []}
  parseMessage
    = let
        loop ::
          TrialFinished -> Data.ProtoLens.Encoding.Bytes.Parser TrialFinished
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "experiment_hash"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"experimentHash") y x)
                        16
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "trial"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"trial") y x)
                        25
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Data.ProtoLens.Encoding.Bytes.wordToDouble
                                          Data.ProtoLens.Encoding.Bytes.getFixed64)
                                       "objective"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"objective") y x)
                        32
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          ((Prelude./=) 0) Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "pruned"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"pruned") y x)
                        42
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "transcript_object_key"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"transcriptObjectKey") y x)
                        48
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       Data.ProtoLens.Encoding.Bytes.getVarInt "timestamp_ns"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"timestampNs") y x)
                        58
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "plan_id"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"planId") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "TrialFinished"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v
                  = Lens.Family2.view
                      (Data.ProtoLens.Field.field @"experimentHash") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             ((Data.Monoid.<>)
                (let
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"trial") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 16)
                         ((Prelude..)
                            Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                ((Data.Monoid.<>)
                   (let
                      _v = Lens.Family2.view (Data.ProtoLens.Field.field @"objective") _x
                    in
                      if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                          Data.Monoid.mempty
                      else
                          (Data.Monoid.<>)
                            (Data.ProtoLens.Encoding.Bytes.putVarInt 25)
                            ((Prelude..)
                               Data.ProtoLens.Encoding.Bytes.putFixed64
                               Data.ProtoLens.Encoding.Bytes.doubleToWord _v))
                   ((Data.Monoid.<>)
                      (let
                         _v = Lens.Family2.view (Data.ProtoLens.Field.field @"pruned") _x
                       in
                         if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                             Data.Monoid.mempty
                         else
                             (Data.Monoid.<>)
                               (Data.ProtoLens.Encoding.Bytes.putVarInt 32)
                               ((Prelude..)
                                  Data.ProtoLens.Encoding.Bytes.putVarInt
                                  (\ b -> if b then 1 else 0) _v))
                      ((Data.Monoid.<>)
                         (let
                            _v
                              = Lens.Family2.view
                                  (Data.ProtoLens.Field.field @"transcriptObjectKey") _x
                          in
                            if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                Data.Monoid.mempty
                            else
                                (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt 42)
                                  ((Prelude..)
                                     (\ bs
                                        -> (Data.Monoid.<>)
                                             (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                (Prelude.fromIntegral (Data.ByteString.length bs)))
                                             (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                     Data.Text.Encoding.encodeUtf8 _v))
                         ((Data.Monoid.<>)
                            (let
                               _v
                                 = Lens.Family2.view (Data.ProtoLens.Field.field @"timestampNs") _x
                             in
                               if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                   Data.Monoid.mempty
                               else
                                   (Data.Monoid.<>)
                                     (Data.ProtoLens.Encoding.Bytes.putVarInt 48)
                                     (Data.ProtoLens.Encoding.Bytes.putVarInt _v))
                            ((Data.Monoid.<>)
                               (let
                                  _v = Lens.Family2.view (Data.ProtoLens.Field.field @"planId") _x
                                in
                                  if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                      Data.Monoid.mempty
                                  else
                                      (Data.Monoid.<>)
                                        (Data.ProtoLens.Encoding.Bytes.putVarInt 58)
                                        ((Prelude..)
                                           (\ bs
                                              -> (Data.Monoid.<>)
                                                   (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                      (Prelude.fromIntegral
                                                         (Data.ByteString.length bs)))
                                                   (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                           Data.Text.Encoding.encodeUtf8 _v))
                               (Data.ProtoLens.Encoding.Wire.buildFieldSet
                                  (Lens.Family2.view Data.ProtoLens.unknownFields _x))))))))
instance Control.DeepSeq.NFData TrialFinished where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_TrialFinished'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_TrialFinished'experimentHash x__)
                (Control.DeepSeq.deepseq
                   (_TrialFinished'trial x__)
                   (Control.DeepSeq.deepseq
                      (_TrialFinished'objective x__)
                      (Control.DeepSeq.deepseq
                         (_TrialFinished'pruned x__)
                         (Control.DeepSeq.deepseq
                            (_TrialFinished'transcriptObjectKey x__)
                            (Control.DeepSeq.deepseq
                               (_TrialFinished'timestampNs x__)
                               (Control.DeepSeq.deepseq (_TrialFinished'planId x__) ())))))))
{- | Fields :

         * 'Proto.Jitml.Tune_Fields.experimentHash' @:: Lens' TrialStarted Data.Text.Text@
         * 'Proto.Jitml.Tune_Fields.trial' @:: Lens' TrialStarted Data.Word.Word32@
         * 'Proto.Jitml.Tune_Fields.trialSeed' @:: Lens' TrialStarted Data.Word.Word64@
         * 'Proto.Jitml.Tune_Fields.parametersJson' @:: Lens' TrialStarted Data.Text.Text@
         * 'Proto.Jitml.Tune_Fields.timestampNs' @:: Lens' TrialStarted Data.Word.Word64@
         * 'Proto.Jitml.Tune_Fields.planId' @:: Lens' TrialStarted Data.Text.Text@ -}
data TrialStarted
  = TrialStarted'_constructor {_TrialStarted'experimentHash :: !Data.Text.Text,
                               _TrialStarted'trial :: !Data.Word.Word32,
                               _TrialStarted'trialSeed :: !Data.Word.Word64,
                               _TrialStarted'parametersJson :: !Data.Text.Text,
                               _TrialStarted'timestampNs :: !Data.Word.Word64,
                               _TrialStarted'planId :: !Data.Text.Text,
                               _TrialStarted'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show TrialStarted where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField TrialStarted "experimentHash" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TrialStarted'experimentHash
           (\ x__ y__ -> x__ {_TrialStarted'experimentHash = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField TrialStarted "trial" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TrialStarted'trial (\ x__ y__ -> x__ {_TrialStarted'trial = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField TrialStarted "trialSeed" Data.Word.Word64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TrialStarted'trialSeed
           (\ x__ y__ -> x__ {_TrialStarted'trialSeed = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField TrialStarted "parametersJson" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TrialStarted'parametersJson
           (\ x__ y__ -> x__ {_TrialStarted'parametersJson = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField TrialStarted "timestampNs" Data.Word.Word64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TrialStarted'timestampNs
           (\ x__ y__ -> x__ {_TrialStarted'timestampNs = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField TrialStarted "planId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TrialStarted'planId
           (\ x__ y__ -> x__ {_TrialStarted'planId = y__}))
        Prelude.id
instance Data.ProtoLens.Message TrialStarted where
  messageName _ = Data.Text.pack "jitml.tune.TrialStarted"
  packedMessageDescriptor _
    = "\n\
      \\fTrialStarted\DC2'\n\
      \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2\DC4\n\
      \\ENQtrial\CAN\STX \SOH(\rR\ENQtrial\DC2\GS\n\
      \\n\
      \trial_seed\CAN\ETX \SOH(\EOTR\ttrialSeed\DC2'\n\
      \\SIparameters_json\CAN\EOT \SOH(\tR\SOparametersJson\DC2!\n\
      \\ftimestamp_ns\CAN\ENQ \SOH(\EOTR\vtimestampNs\DC2\ETB\n\
      \\aplan_id\CAN\ACK \SOH(\tR\ACKplanId"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        experimentHash__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "experiment_hash"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"experimentHash")) ::
              Data.ProtoLens.FieldDescriptor TrialStarted
        trial__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "trial"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"trial")) ::
              Data.ProtoLens.FieldDescriptor TrialStarted
        trialSeed__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "trial_seed"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word64)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"trialSeed")) ::
              Data.ProtoLens.FieldDescriptor TrialStarted
        parametersJson__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "parameters_json"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"parametersJson")) ::
              Data.ProtoLens.FieldDescriptor TrialStarted
        timestampNs__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "timestamp_ns"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word64)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"timestampNs")) ::
              Data.ProtoLens.FieldDescriptor TrialStarted
        planId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "plan_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"planId")) ::
              Data.ProtoLens.FieldDescriptor TrialStarted
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, experimentHash__field_descriptor),
           (Data.ProtoLens.Tag 2, trial__field_descriptor),
           (Data.ProtoLens.Tag 3, trialSeed__field_descriptor),
           (Data.ProtoLens.Tag 4, parametersJson__field_descriptor),
           (Data.ProtoLens.Tag 5, timestampNs__field_descriptor),
           (Data.ProtoLens.Tag 6, planId__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _TrialStarted'_unknownFields
        (\ x__ y__ -> x__ {_TrialStarted'_unknownFields = y__})
  defMessage
    = TrialStarted'_constructor
        {_TrialStarted'experimentHash = Data.ProtoLens.fieldDefault,
         _TrialStarted'trial = Data.ProtoLens.fieldDefault,
         _TrialStarted'trialSeed = Data.ProtoLens.fieldDefault,
         _TrialStarted'parametersJson = Data.ProtoLens.fieldDefault,
         _TrialStarted'timestampNs = Data.ProtoLens.fieldDefault,
         _TrialStarted'planId = Data.ProtoLens.fieldDefault,
         _TrialStarted'_unknownFields = []}
  parseMessage
    = let
        loop ::
          TrialStarted -> Data.ProtoLens.Encoding.Bytes.Parser TrialStarted
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "experiment_hash"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"experimentHash") y x)
                        16
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "trial"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"trial") y x)
                        24
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       Data.ProtoLens.Encoding.Bytes.getVarInt "trial_seed"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"trialSeed") y x)
                        34
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "parameters_json"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"parametersJson") y x)
                        40
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       Data.ProtoLens.Encoding.Bytes.getVarInt "timestamp_ns"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"timestampNs") y x)
                        50
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "plan_id"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"planId") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "TrialStarted"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v
                  = Lens.Family2.view
                      (Data.ProtoLens.Field.field @"experimentHash") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             ((Data.Monoid.<>)
                (let
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"trial") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 16)
                         ((Prelude..)
                            Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                ((Data.Monoid.<>)
                   (let
                      _v = Lens.Family2.view (Data.ProtoLens.Field.field @"trialSeed") _x
                    in
                      if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                          Data.Monoid.mempty
                      else
                          (Data.Monoid.<>)
                            (Data.ProtoLens.Encoding.Bytes.putVarInt 24)
                            (Data.ProtoLens.Encoding.Bytes.putVarInt _v))
                   ((Data.Monoid.<>)
                      (let
                         _v
                           = Lens.Family2.view
                               (Data.ProtoLens.Field.field @"parametersJson") _x
                       in
                         if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                             Data.Monoid.mempty
                         else
                             (Data.Monoid.<>)
                               (Data.ProtoLens.Encoding.Bytes.putVarInt 34)
                               ((Prelude..)
                                  (\ bs
                                     -> (Data.Monoid.<>)
                                          (Data.ProtoLens.Encoding.Bytes.putVarInt
                                             (Prelude.fromIntegral (Data.ByteString.length bs)))
                                          (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                  Data.Text.Encoding.encodeUtf8 _v))
                      ((Data.Monoid.<>)
                         (let
                            _v
                              = Lens.Family2.view (Data.ProtoLens.Field.field @"timestampNs") _x
                          in
                            if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                Data.Monoid.mempty
                            else
                                (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt 40)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt _v))
                         ((Data.Monoid.<>)
                            (let
                               _v = Lens.Family2.view (Data.ProtoLens.Field.field @"planId") _x
                             in
                               if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                   Data.Monoid.mempty
                               else
                                   (Data.Monoid.<>)
                                     (Data.ProtoLens.Encoding.Bytes.putVarInt 50)
                                     ((Prelude..)
                                        (\ bs
                                           -> (Data.Monoid.<>)
                                                (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                   (Prelude.fromIntegral
                                                      (Data.ByteString.length bs)))
                                                (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                        Data.Text.Encoding.encodeUtf8 _v))
                            (Data.ProtoLens.Encoding.Wire.buildFieldSet
                               (Lens.Family2.view Data.ProtoLens.unknownFields _x)))))))
instance Control.DeepSeq.NFData TrialStarted where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_TrialStarted'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_TrialStarted'experimentHash x__)
                (Control.DeepSeq.deepseq
                   (_TrialStarted'trial x__)
                   (Control.DeepSeq.deepseq
                      (_TrialStarted'trialSeed x__)
                      (Control.DeepSeq.deepseq
                         (_TrialStarted'parametersJson x__)
                         (Control.DeepSeq.deepseq
                            (_TrialStarted'timestampNs x__)
                            (Control.DeepSeq.deepseq (_TrialStarted'planId x__) ()))))))
{- | Fields :

         * 'Proto.Jitml.Tune_Fields.maybe'body' @:: Lens' TuneCommand (Prelude.Maybe TuneCommand'Body)@
         * 'Proto.Jitml.Tune_Fields.maybe'start' @:: Lens' TuneCommand (Prelude.Maybe StartSweep)@
         * 'Proto.Jitml.Tune_Fields.start' @:: Lens' TuneCommand StartSweep@
         * 'Proto.Jitml.Tune_Fields.maybe'stop' @:: Lens' TuneCommand (Prelude.Maybe StopSweep)@
         * 'Proto.Jitml.Tune_Fields.stop' @:: Lens' TuneCommand StopSweep@ -}
data TuneCommand
  = TuneCommand'_constructor {_TuneCommand'body :: !(Prelude.Maybe TuneCommand'Body),
                              _TuneCommand'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show TuneCommand where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
data TuneCommand'Body
  = TuneCommand'Start !StartSweep | TuneCommand'Stop !StopSweep
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.Field.HasField TuneCommand "maybe'body" (Prelude.Maybe TuneCommand'Body) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TuneCommand'body (\ x__ y__ -> x__ {_TuneCommand'body = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField TuneCommand "maybe'start" (Prelude.Maybe StartSweep) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TuneCommand'body (\ x__ y__ -> x__ {_TuneCommand'body = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (TuneCommand'Start x__val)) -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap TuneCommand'Start y__))
instance Data.ProtoLens.Field.HasField TuneCommand "start" StartSweep where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TuneCommand'body (\ x__ y__ -> x__ {_TuneCommand'body = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (TuneCommand'Start x__val)) -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap TuneCommand'Start y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField TuneCommand "maybe'stop" (Prelude.Maybe StopSweep) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TuneCommand'body (\ x__ y__ -> x__ {_TuneCommand'body = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (TuneCommand'Stop x__val)) -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap TuneCommand'Stop y__))
instance Data.ProtoLens.Field.HasField TuneCommand "stop" StopSweep where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TuneCommand'body (\ x__ y__ -> x__ {_TuneCommand'body = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (TuneCommand'Stop x__val)) -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap TuneCommand'Stop y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Message TuneCommand where
  messageName _ = Data.Text.pack "jitml.tune.TuneCommand"
  packedMessageDescriptor _
    = "\n\
      \\vTuneCommand\DC2.\n\
      \\ENQstart\CAN\SOH \SOH(\v2\SYN.jitml.tune.StartSweepH\NULR\ENQstart\DC2+\n\
      \\EOTstop\CAN\STX \SOH(\v2\NAK.jitml.tune.StopSweepH\NULR\EOTstopB\ACK\n\
      \\EOTbody"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        start__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "start"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor StartSweep)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'start")) ::
              Data.ProtoLens.FieldDescriptor TuneCommand
        stop__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "stop"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor StopSweep)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'stop")) ::
              Data.ProtoLens.FieldDescriptor TuneCommand
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, start__field_descriptor),
           (Data.ProtoLens.Tag 2, stop__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _TuneCommand'_unknownFields
        (\ x__ y__ -> x__ {_TuneCommand'_unknownFields = y__})
  defMessage
    = TuneCommand'_constructor
        {_TuneCommand'body = Prelude.Nothing,
         _TuneCommand'_unknownFields = []}
  parseMessage
    = let
        loop ::
          TuneCommand -> Data.ProtoLens.Encoding.Bytes.Parser TuneCommand
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "start"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"start") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "stop"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"stop") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "TuneCommand"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (case
                  Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'body") _x
              of
                Prelude.Nothing -> Data.Monoid.mempty
                (Prelude.Just (TuneCommand'Start v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v)
                (Prelude.Just (TuneCommand'Stop v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v))
             (Data.ProtoLens.Encoding.Wire.buildFieldSet
                (Lens.Family2.view Data.ProtoLens.unknownFields _x))
instance Control.DeepSeq.NFData TuneCommand where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_TuneCommand'_unknownFields x__)
             (Control.DeepSeq.deepseq (_TuneCommand'body x__) ())
instance Control.DeepSeq.NFData TuneCommand'Body where
  rnf (TuneCommand'Start x__) = Control.DeepSeq.rnf x__
  rnf (TuneCommand'Stop x__) = Control.DeepSeq.rnf x__
_TuneCommand'Start ::
  Data.ProtoLens.Prism.Prism' TuneCommand'Body StartSweep
_TuneCommand'Start
  = Data.ProtoLens.Prism.prism'
      TuneCommand'Start
      (\ p__
         -> case p__ of
              (TuneCommand'Start p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_TuneCommand'Stop ::
  Data.ProtoLens.Prism.Prism' TuneCommand'Body StopSweep
_TuneCommand'Stop
  = Data.ProtoLens.Prism.prism'
      TuneCommand'Stop
      (\ p__
         -> case p__ of
              (TuneCommand'Stop p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
{- | Fields :

         * 'Proto.Jitml.Tune_Fields.maybe'body' @:: Lens' TuneEvent (Prelude.Maybe TuneEvent'Body)@
         * 'Proto.Jitml.Tune_Fields.maybe'started' @:: Lens' TuneEvent (Prelude.Maybe TrialStarted)@
         * 'Proto.Jitml.Tune_Fields.started' @:: Lens' TuneEvent TrialStarted@
         * 'Proto.Jitml.Tune_Fields.maybe'finished' @:: Lens' TuneEvent (Prelude.Maybe TrialFinished)@
         * 'Proto.Jitml.Tune_Fields.finished' @:: Lens' TuneEvent TrialFinished@
         * 'Proto.Jitml.Tune_Fields.maybe'sweepFinished' @:: Lens' TuneEvent (Prelude.Maybe SweepFinished)@
         * 'Proto.Jitml.Tune_Fields.sweepFinished' @:: Lens' TuneEvent SweepFinished@
         * 'Proto.Jitml.Tune_Fields.maybe'sweepCompleted' @:: Lens' TuneEvent (Prelude.Maybe SweepCompleted)@
         * 'Proto.Jitml.Tune_Fields.sweepCompleted' @:: Lens' TuneEvent SweepCompleted@ -}
data TuneEvent
  = TuneEvent'_constructor {_TuneEvent'body :: !(Prelude.Maybe TuneEvent'Body),
                            _TuneEvent'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show TuneEvent where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
data TuneEvent'Body
  = TuneEvent'Started !TrialStarted |
    TuneEvent'Finished !TrialFinished |
    TuneEvent'SweepFinished !SweepFinished |
    TuneEvent'SweepCompleted !SweepCompleted
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.Field.HasField TuneEvent "maybe'body" (Prelude.Maybe TuneEvent'Body) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TuneEvent'body (\ x__ y__ -> x__ {_TuneEvent'body = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField TuneEvent "maybe'started" (Prelude.Maybe TrialStarted) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TuneEvent'body (\ x__ y__ -> x__ {_TuneEvent'body = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (TuneEvent'Started x__val)) -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap TuneEvent'Started y__))
instance Data.ProtoLens.Field.HasField TuneEvent "started" TrialStarted where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TuneEvent'body (\ x__ y__ -> x__ {_TuneEvent'body = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (TuneEvent'Started x__val)) -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap TuneEvent'Started y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField TuneEvent "maybe'finished" (Prelude.Maybe TrialFinished) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TuneEvent'body (\ x__ y__ -> x__ {_TuneEvent'body = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (TuneEvent'Finished x__val)) -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap TuneEvent'Finished y__))
instance Data.ProtoLens.Field.HasField TuneEvent "finished" TrialFinished where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TuneEvent'body (\ x__ y__ -> x__ {_TuneEvent'body = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (TuneEvent'Finished x__val)) -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap TuneEvent'Finished y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField TuneEvent "maybe'sweepFinished" (Prelude.Maybe SweepFinished) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TuneEvent'body (\ x__ y__ -> x__ {_TuneEvent'body = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (TuneEvent'SweepFinished x__val))
                     -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap TuneEvent'SweepFinished y__))
instance Data.ProtoLens.Field.HasField TuneEvent "sweepFinished" SweepFinished where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TuneEvent'body (\ x__ y__ -> x__ {_TuneEvent'body = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (TuneEvent'SweepFinished x__val))
                        -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap TuneEvent'SweepFinished y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField TuneEvent "maybe'sweepCompleted" (Prelude.Maybe SweepCompleted) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TuneEvent'body (\ x__ y__ -> x__ {_TuneEvent'body = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (TuneEvent'SweepCompleted x__val))
                     -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap TuneEvent'SweepCompleted y__))
instance Data.ProtoLens.Field.HasField TuneEvent "sweepCompleted" SweepCompleted where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TuneEvent'body (\ x__ y__ -> x__ {_TuneEvent'body = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (TuneEvent'SweepCompleted x__val))
                        -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap TuneEvent'SweepCompleted y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Message TuneEvent where
  messageName _ = Data.Text.pack "jitml.tune.TuneEvent"
  packedMessageDescriptor _
    = "\n\
      \\tTuneEvent\DC24\n\
      \\astarted\CAN\SOH \SOH(\v2\CAN.jitml.tune.TrialStartedH\NULR\astarted\DC27\n\
      \\bfinished\CAN\STX \SOH(\v2\EM.jitml.tune.TrialFinishedH\NULR\bfinished\DC2B\n\
      \\SOsweep_finished\CAN\ETX \SOH(\v2\EM.jitml.tune.SweepFinishedH\NULR\rsweepFinished\DC2E\n\
      \\SIsweep_completed\CAN\EOT \SOH(\v2\SUB.jitml.tune.SweepCompletedH\NULR\SOsweepCompletedB\ACK\n\
      \\EOTbody"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        started__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "started"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor TrialStarted)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'started")) ::
              Data.ProtoLens.FieldDescriptor TuneEvent
        finished__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "finished"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor TrialFinished)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'finished")) ::
              Data.ProtoLens.FieldDescriptor TuneEvent
        sweepFinished__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "sweep_finished"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor SweepFinished)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'sweepFinished")) ::
              Data.ProtoLens.FieldDescriptor TuneEvent
        sweepCompleted__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "sweep_completed"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor SweepCompleted)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'sweepCompleted")) ::
              Data.ProtoLens.FieldDescriptor TuneEvent
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, started__field_descriptor),
           (Data.ProtoLens.Tag 2, finished__field_descriptor),
           (Data.ProtoLens.Tag 3, sweepFinished__field_descriptor),
           (Data.ProtoLens.Tag 4, sweepCompleted__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _TuneEvent'_unknownFields
        (\ x__ y__ -> x__ {_TuneEvent'_unknownFields = y__})
  defMessage
    = TuneEvent'_constructor
        {_TuneEvent'body = Prelude.Nothing, _TuneEvent'_unknownFields = []}
  parseMessage
    = let
        loop :: TuneEvent -> Data.ProtoLens.Encoding.Bytes.Parser TuneEvent
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "started"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"started") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "finished"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"finished") y x)
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "sweep_finished"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"sweepFinished") y x)
                        34
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "sweep_completed"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"sweepCompleted") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "TuneEvent"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (case
                  Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'body") _x
              of
                Prelude.Nothing -> Data.Monoid.mempty
                (Prelude.Just (TuneEvent'Started v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v)
                (Prelude.Just (TuneEvent'Finished v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v)
                (Prelude.Just (TuneEvent'SweepFinished v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 26)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v)
                (Prelude.Just (TuneEvent'SweepCompleted v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 34)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v))
             (Data.ProtoLens.Encoding.Wire.buildFieldSet
                (Lens.Family2.view Data.ProtoLens.unknownFields _x))
instance Control.DeepSeq.NFData TuneEvent where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_TuneEvent'_unknownFields x__)
             (Control.DeepSeq.deepseq (_TuneEvent'body x__) ())
instance Control.DeepSeq.NFData TuneEvent'Body where
  rnf (TuneEvent'Started x__) = Control.DeepSeq.rnf x__
  rnf (TuneEvent'Finished x__) = Control.DeepSeq.rnf x__
  rnf (TuneEvent'SweepFinished x__) = Control.DeepSeq.rnf x__
  rnf (TuneEvent'SweepCompleted x__) = Control.DeepSeq.rnf x__
_TuneEvent'Started ::
  Data.ProtoLens.Prism.Prism' TuneEvent'Body TrialStarted
_TuneEvent'Started
  = Data.ProtoLens.Prism.prism'
      TuneEvent'Started
      (\ p__
         -> case p__ of
              (TuneEvent'Started p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_TuneEvent'Finished ::
  Data.ProtoLens.Prism.Prism' TuneEvent'Body TrialFinished
_TuneEvent'Finished
  = Data.ProtoLens.Prism.prism'
      TuneEvent'Finished
      (\ p__
         -> case p__ of
              (TuneEvent'Finished p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_TuneEvent'SweepFinished ::
  Data.ProtoLens.Prism.Prism' TuneEvent'Body SweepFinished
_TuneEvent'SweepFinished
  = Data.ProtoLens.Prism.prism'
      TuneEvent'SweepFinished
      (\ p__
         -> case p__ of
              (TuneEvent'SweepFinished p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_TuneEvent'SweepCompleted ::
  Data.ProtoLens.Prism.Prism' TuneEvent'Body SweepCompleted
_TuneEvent'SweepCompleted
  = Data.ProtoLens.Prism.prism'
      TuneEvent'SweepCompleted
      (\ p__
         -> case p__ of
              (TuneEvent'SweepCompleted p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
packedFileDescriptor :: Data.ByteString.ByteString
packedFileDescriptor
  = "\n\
    \\DLEjitml/tune.proto\DC2\n\
    \jitml.tune\"\185\ETX\n\
    \\n\
    \StartSweep\DC2'\n\
    \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2(\n\
    \\DLEdhall_object_key\CAN\STX \SOH(\tR\SOdhallObjectKey\DC2\FS\n\
    \\tsubstrate\CAN\ETX \SOH(\tR\tsubstrate\DC2\GS\n\
    \\n\
    \sweep_seed\CAN\EOT \SOH(\EOTR\tsweepSeed\DC2!\n\
    \\ftrial_budget\CAN\ENQ \SOH(\rR\vtrialBudget\DC2(\n\
    \\DLEbudget_per_trial\CAN\ACK \SOH(\rR\SObudgetPerTrial\DC2\CAN\n\
    \\asampler\CAN\a \SOH(\tR\asampler\DC2\FS\n\
    \\tscheduler\CAN\b \SOH(\tR\tscheduler\DC2\SYN\n\
    \\ACKpruner\CAN\t \SOH(\tR\ACKpruner\DC2 \n\
    \\vparallelism\CAN\n\
    \ \SOH(\rR\vparallelism\DC2\RS\n\
    \\n\
    \promotions\CAN\v \SOH(\rR\n\
    \promotions\DC2\ETB\n\
    \\aplan_id\CAN\f \SOH(\tR\ACKplanId\DC2#\n\
    \\rresolved_plan\CAN\r \SOH(\tR\fresolvedPlan\"4\n\
    \\tStopSweep\DC2'\n\
    \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\"\209\SOH\n\
    \\fTrialStarted\DC2'\n\
    \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2\DC4\n\
    \\ENQtrial\CAN\STX \SOH(\rR\ENQtrial\DC2\GS\n\
    \\n\
    \trial_seed\CAN\ETX \SOH(\EOTR\ttrialSeed\DC2'\n\
    \\SIparameters_json\CAN\EOT \SOH(\tR\SOparametersJson\DC2!\n\
    \\ftimestamp_ns\CAN\ENQ \SOH(\EOTR\vtimestampNs\DC2\ETB\n\
    \\aplan_id\CAN\ACK \SOH(\tR\ACKplanId\"\244\SOH\n\
    \\rTrialFinished\DC2'\n\
    \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2\DC4\n\
    \\ENQtrial\CAN\STX \SOH(\rR\ENQtrial\DC2\FS\n\
    \\tobjective\CAN\ETX \SOH(\SOHR\tobjective\DC2\SYN\n\
    \\ACKpruned\CAN\EOT \SOH(\bR\ACKpruned\DC22\n\
    \\NAKtranscript_object_key\CAN\ENQ \SOH(\tR\DC3transcriptObjectKey\DC2!\n\
    \\ftimestamp_ns\CAN\ACK \SOH(\EOTR\vtimestampNs\DC2\ETB\n\
    \\aplan_id\CAN\a \SOH(\tR\ACKplanId\"\162\STX\n\
    \\rSweepFinished\DC2'\n\
    \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2)\n\
    \\DLEtrials_completed\CAN\STX \SOH(\rR\SItrialsCompleted\DC2#\n\
    \\rtrials_pruned\CAN\ETX \SOH(\rR\ftrialsPruned\DC2%\n\
    \\SObest_objective\CAN\EOT \SOH(\SOHR\rbestObjective\DC2\ETB\n\
    \\aplan_id\CAN\ACK \SOH(\tR\ACKplanId\DC2'\n\
    \\SItrials_promoted\CAN\a \SOH(\rR\SOtrialsPromoted\DC2)\n\
    \\DLEprotocol_version\CAN\b \SOH(\rR\SIprotocolVersionJ\EOT\b\ENQ\DLE\ACK\"\161\SOH\n\
    \\SOSweepCompleted\DC2)\n\
    \\DLEprotocol_version\CAN\SOH \SOH(\rR\SIprotocolVersion\DC25\n\
    \\bfinished\CAN\STX \SOH(\v2\EM.jitml.tune.SweepFinishedR\bfinished\DC2-\n\
    \\DC2completed_training\CAN\ETX \SOH(\fR\DC1completedTraining\"r\n\
    \\vTuneCommand\DC2.\n\
    \\ENQstart\CAN\SOH \SOH(\v2\SYN.jitml.tune.StartSweepH\NULR\ENQstart\DC2+\n\
    \\EOTstop\CAN\STX \SOH(\v2\NAK.jitml.tune.StopSweepH\NULR\EOTstopB\ACK\n\
    \\EOTbody\"\141\STX\n\
    \\tTuneEvent\DC24\n\
    \\astarted\CAN\SOH \SOH(\v2\CAN.jitml.tune.TrialStartedH\NULR\astarted\DC27\n\
    \\bfinished\CAN\STX \SOH(\v2\EM.jitml.tune.TrialFinishedH\NULR\bfinished\DC2B\n\
    \\SOsweep_finished\CAN\ETX \SOH(\v2\EM.jitml.tune.SweepFinishedH\NULR\rsweepFinished\DC2E\n\
    \\SIsweep_completed\CAN\EOT \SOH(\v2\SUB.jitml.tune.SweepCompletedH\NULR\SOsweepCompletedB\ACK\n\
    \\EOTbodyJ\250\ETB\n\
    \\ACK\DC2\EOT\NUL\NULN\SOH\n\
    \\b\n\
    \\SOH\f\DC2\ETX\NUL\NUL\DC2\n\
    \\b\n\
    \\SOH\STX\DC2\ETX\STX\NUL\DC3\n\
    \s\n\
    \\STX\EOT\NUL\DC2\EOT\ACK\NUL\DC4\SOH\SUBg Envelope sent on `tune.command.<mode>` to drive a hyperparameter sweep\n\
    \ via the daemon's TuneHandler.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\NUL\SOH\DC2\ETX\ACK\b\DC2\n\
    \\v\n\
    \\EOT\EOT\NUL\STX\NUL\DC2\ETX\a\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\ENQ\DC2\ETX\a\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\SOH\DC2\ETX\a\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\ETX\DC2\ETX\a\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\NUL\STX\SOH\DC2\ETX\b\STX\RS\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\ENQ\DC2\ETX\b\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\SOH\DC2\ETX\b\t\EM\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\ETX\DC2\ETX\b\FS\GS\n\
    \\v\n\
    \\EOT\EOT\NUL\STX\STX\DC2\ETX\t\STX\ETB\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\STX\ENQ\DC2\ETX\t\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\STX\SOH\DC2\ETX\t\t\DC2\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\STX\ETX\DC2\ETX\t\NAK\SYN\n\
    \\v\n\
    \\EOT\EOT\NUL\STX\ETX\DC2\ETX\n\
    \\STX\CAN\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ETX\ENQ\DC2\ETX\n\
    \\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ETX\SOH\DC2\ETX\n\
    \\t\DC3\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ETX\ETX\DC2\ETX\n\
    \\SYN\ETB\n\
    \\v\n\
    \\EOT\EOT\NUL\STX\EOT\DC2\ETX\v\STX\SUB\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\EOT\ENQ\DC2\ETX\v\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\EOT\SOH\DC2\ETX\v\t\NAK\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\EOT\ETX\DC2\ETX\v\CAN\EM\n\
    \\v\n\
    \\EOT\EOT\NUL\STX\ENQ\DC2\ETX\f\STX\RS\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ENQ\ENQ\DC2\ETX\f\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ENQ\SOH\DC2\ETX\f\t\EM\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ENQ\ETX\DC2\ETX\f\FS\GS\n\
    \>\n\
    \\EOT\EOT\NUL\STX\ACK\DC2\ETX\r\STX\NAK\"1 sobol, latin-hypercube, grid, genetic-algorithm\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ACK\ENQ\DC2\ETX\r\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ACK\SOH\DC2\ETX\r\t\DLE\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ACK\ETX\DC2\ETX\r\DC3\DC4\n\
    \1\n\
    \\EOT\EOT\NUL\STX\a\DC2\ETX\SO\STX\ETB\"$ constant, asha, successive-halving\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\a\ENQ\DC2\ETX\SO\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\a\SOH\DC2\ETX\SO\t\DC2\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\a\ETX\DC2\ETX\SO\NAK\SYN\n\
    \*\n\
    \\EOT\EOT\NUL\STX\b\DC2\ETX\SI\STX\DC4\"\GS none, percentile, hyperband\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\b\ENQ\DC2\ETX\SI\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\b\SOH\DC2\ETX\SI\t\SI\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\b\ETX\DC2\ETX\SI\DC2\DC3\n\
    \\v\n\
    \\EOT\EOT\NUL\STX\t\DC2\ETX\DLE\STX\SUB\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\t\ENQ\DC2\ETX\DLE\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\t\SOH\DC2\ETX\DLE\t\DC4\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\t\ETX\DC2\ETX\DLE\ETB\EM\n\
    \\v\n\
    \\EOT\EOT\NUL\STX\n\
    \\DC2\ETX\DC1\STX\EM\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\n\
    \\ENQ\DC2\ETX\DC1\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\n\
    \\SOH\DC2\ETX\DC1\t\DC3\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\n\
    \\ETX\DC2\ETX\DC1\SYN\CAN\n\
    \\v\n\
    \\EOT\EOT\NUL\STX\v\DC2\ETX\DC2\STX\SYN\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\v\ENQ\DC2\ETX\DC2\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\v\SOH\DC2\ETX\DC2\t\DLE\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\v\ETX\DC2\ETX\DC2\DC3\NAK\n\
    \\v\n\
    \\EOT\EOT\NUL\STX\f\DC2\ETX\DC3\STX\FS\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\f\ENQ\DC2\ETX\DC3\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\f\SOH\DC2\ETX\DC3\t\SYN\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\f\ETX\DC2\ETX\DC3\EM\ESC\n\
    \\n\
    \\n\
    \\STX\EOT\SOH\DC2\EOT\SYN\NUL\CAN\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\SOH\SOH\DC2\ETX\SYN\b\DC1\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\NUL\DC2\ETX\ETB\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ENQ\DC2\ETX\ETB\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\SOH\DC2\ETX\ETB\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ETX\DC2\ETX\ETB\ESC\FS\n\
    \\n\
    \\n\
    \\STX\EOT\STX\DC2\EOT\SUB\NUL!\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\STX\SOH\DC2\ETX\SUB\b\DC4\n\
    \\v\n\
    \\EOT\EOT\STX\STX\NUL\DC2\ETX\ESC\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\NUL\ENQ\DC2\ETX\ESC\STX\b\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\NUL\SOH\DC2\ETX\ESC\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\NUL\ETX\DC2\ETX\ESC\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\STX\STX\SOH\DC2\ETX\FS\STX\DC3\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\SOH\ENQ\DC2\ETX\FS\STX\b\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\SOH\SOH\DC2\ETX\FS\t\SO\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\SOH\ETX\DC2\ETX\FS\DC1\DC2\n\
    \\v\n\
    \\EOT\EOT\STX\STX\STX\DC2\ETX\GS\STX\CAN\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\STX\ENQ\DC2\ETX\GS\STX\b\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\STX\SOH\DC2\ETX\GS\t\DC3\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\STX\ETX\DC2\ETX\GS\SYN\ETB\n\
    \\v\n\
    \\EOT\EOT\STX\STX\ETX\DC2\ETX\RS\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\ETX\ENQ\DC2\ETX\RS\STX\b\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\ETX\SOH\DC2\ETX\RS\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\ETX\ETX\DC2\ETX\RS\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\STX\STX\EOT\DC2\ETX\US\STX\SUB\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\EOT\ENQ\DC2\ETX\US\STX\b\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\EOT\SOH\DC2\ETX\US\t\NAK\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\EOT\ETX\DC2\ETX\US\CAN\EM\n\
    \\v\n\
    \\EOT\EOT\STX\STX\ENQ\DC2\ETX \STX\NAK\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\ENQ\ENQ\DC2\ETX \STX\b\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\ENQ\SOH\DC2\ETX \t\DLE\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\ENQ\ETX\DC2\ETX \DC3\DC4\n\
    \\n\
    \\n\
    \\STX\EOT\ETX\DC2\EOT#\NUL+\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\ETX\SOH\DC2\ETX#\b\NAK\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\NUL\DC2\ETX$\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\NUL\ENQ\DC2\ETX$\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\NUL\SOH\DC2\ETX$\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\NUL\ETX\DC2\ETX$\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\SOH\DC2\ETX%\STX\DC3\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\SOH\ENQ\DC2\ETX%\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\SOH\SOH\DC2\ETX%\t\SO\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\SOH\ETX\DC2\ETX%\DC1\DC2\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\STX\DC2\ETX&\STX\ETB\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\STX\ENQ\DC2\ETX&\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\STX\SOH\DC2\ETX&\t\DC2\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\STX\ETX\DC2\ETX&\NAK\SYN\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\ETX\DC2\ETX'\STX\DC2\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ETX\ENQ\DC2\ETX'\STX\ACK\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ETX\SOH\DC2\ETX'\a\r\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ETX\ETX\DC2\ETX'\DLE\DC1\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\EOT\DC2\ETX(\STX#\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\EOT\ENQ\DC2\ETX(\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\EOT\SOH\DC2\ETX(\t\RS\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\EOT\ETX\DC2\ETX(!\"\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\ENQ\DC2\ETX)\STX\SUB\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ENQ\ENQ\DC2\ETX)\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ENQ\SOH\DC2\ETX)\t\NAK\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ENQ\ETX\DC2\ETX)\CAN\EM\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\ACK\DC2\ETX*\STX\NAK\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ACK\ENQ\DC2\ETX*\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ACK\SOH\DC2\ETX*\t\DLE\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ACK\ETX\DC2\ETX*\DC3\DC4\n\
    \\156\SOH\n\
    \\STX\EOT\EOT\DC2\EOT/\NUL8\SOH\SUB\143\SOH Operational termination without a proof-bearing completion. This variant is\n\
    \ inspectable but cannot satisfy checkpoint/inference eligibility.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\EOT\SOH\DC2\ETX/\b\NAK\n\
    \\v\n\
    \\EOT\EOT\EOT\STX\NUL\DC2\ETX0\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\NUL\ENQ\DC2\ETX0\STX\b\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\NUL\SOH\DC2\ETX0\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\NUL\ETX\DC2\ETX0\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\EOT\STX\SOH\DC2\ETX1\STX\RS\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\SOH\ENQ\DC2\ETX1\STX\b\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\SOH\SOH\DC2\ETX1\t\EM\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\SOH\ETX\DC2\ETX1\FS\GS\n\
    \\v\n\
    \\EOT\EOT\EOT\STX\STX\DC2\ETX2\STX\ESC\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\STX\ENQ\DC2\ETX2\STX\b\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\STX\SOH\DC2\ETX2\t\SYN\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\STX\ETX\DC2\ETX2\EM\SUB\n\
    \\v\n\
    \\EOT\EOT\EOT\STX\ETX\DC2\ETX3\STX\FS\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\ETX\ENQ\DC2\ETX3\STX\b\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\ETX\SOH\DC2\ETX3\t\ETB\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\ETX\ETX\DC2\ETX3\SUB\ESC\n\
    \\n\
    \\n\
    \\ETX\EOT\EOT\t\DC2\ETX4\STX\r\n\
    \\v\n\
    \\EOT\EOT\EOT\t\NUL\DC2\ETX4\v\f\n\
    \\f\n\
    \\ENQ\EOT\EOT\t\NUL\SOH\DC2\ETX4\v\f\n\
    \\f\n\
    \\ENQ\EOT\EOT\t\NUL\STX\DC2\ETX4\v\f\n\
    \\v\n\
    \\EOT\EOT\EOT\STX\EOT\DC2\ETX5\STX\NAK\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\EOT\ENQ\DC2\ETX5\STX\b\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\EOT\SOH\DC2\ETX5\t\DLE\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\EOT\ETX\DC2\ETX5\DC3\DC4\n\
    \\v\n\
    \\EOT\EOT\EOT\STX\ENQ\DC2\ETX6\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\ENQ\ENQ\DC2\ETX6\STX\b\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\ENQ\SOH\DC2\ETX6\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\ENQ\ETX\DC2\ETX6\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\EOT\STX\ACK\DC2\ETX7\STX\RS\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\ACK\ENQ\DC2\ETX7\STX\b\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\ACK\SOH\DC2\ETX7\t\EM\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\ACK\ETX\DC2\ETX7\FS\GS\n\
    \\n\
    \\n\
    \\STX\EOT\ENQ\DC2\EOT:\NUL>\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\ENQ\SOH\DC2\ETX:\b\SYN\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\NUL\DC2\ETX;\STX\RS\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\NUL\ENQ\DC2\ETX;\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\NUL\SOH\DC2\ETX;\t\EM\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\NUL\ETX\DC2\ETX;\FS\GS\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\SOH\DC2\ETX<\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\SOH\ACK\DC2\ETX<\STX\SI\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\SOH\SOH\DC2\ETX<\DLE\CAN\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\SOH\ETX\DC2\ETX<\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\STX\DC2\ETX=\STX\US\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\STX\ENQ\DC2\ETX=\STX\a\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\STX\SOH\DC2\ETX=\b\SUB\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\STX\ETX\DC2\ETX=\GS\RS\n\
    \\n\
    \\n\
    \\STX\EOT\ACK\DC2\EOT@\NULE\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\ACK\SOH\DC2\ETX@\b\DC3\n\
    \\f\n\
    \\EOT\EOT\ACK\b\NUL\DC2\EOTA\STXD\ETX\n\
    \\f\n\
    \\ENQ\EOT\ACK\b\NUL\SOH\DC2\ETXA\b\f\n\
    \\v\n\
    \\EOT\EOT\ACK\STX\NUL\DC2\ETXB\EOT\EM\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\NUL\ACK\DC2\ETXB\EOT\SO\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\NUL\SOH\DC2\ETXB\SI\DC4\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\NUL\ETX\DC2\ETXB\ETB\CAN\n\
    \\v\n\
    \\EOT\EOT\ACK\STX\SOH\DC2\ETXC\EOT\EM\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\SOH\ACK\DC2\ETXC\EOT\r\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\SOH\SOH\DC2\ETXC\SI\DC3\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\SOH\ETX\DC2\ETXC\ETB\CAN\n\
    \\n\
    \\n\
    \\STX\EOT\a\DC2\EOTG\NULN\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\a\SOH\DC2\ETXG\b\DC1\n\
    \\f\n\
    \\EOT\EOT\a\b\NUL\DC2\EOTH\STXM\ETX\n\
    \\f\n\
    \\ENQ\EOT\a\b\NUL\SOH\DC2\ETXH\b\f\n\
    \\v\n\
    \\EOT\EOT\a\STX\NUL\DC2\ETXI\EOT'\n\
    \\f\n\
    \\ENQ\EOT\a\STX\NUL\ACK\DC2\ETXI\EOT\DLE\n\
    \\f\n\
    \\ENQ\EOT\a\STX\NUL\SOH\DC2\ETXI\DC3\SUB\n\
    \\f\n\
    \\ENQ\EOT\a\STX\NUL\ETX\DC2\ETXI%&\n\
    \\v\n\
    \\EOT\EOT\a\STX\SOH\DC2\ETXJ\EOT'\n\
    \\f\n\
    \\ENQ\EOT\a\STX\SOH\ACK\DC2\ETXJ\EOT\DC1\n\
    \\f\n\
    \\ENQ\EOT\a\STX\SOH\SOH\DC2\ETXJ\DC3\ESC\n\
    \\f\n\
    \\ENQ\EOT\a\STX\SOH\ETX\DC2\ETXJ%&\n\
    \\v\n\
    \\EOT\EOT\a\STX\STX\DC2\ETXK\EOT'\n\
    \\f\n\
    \\ENQ\EOT\a\STX\STX\ACK\DC2\ETXK\EOT\DC1\n\
    \\f\n\
    \\ENQ\EOT\a\STX\STX\SOH\DC2\ETXK\DC3!\n\
    \\f\n\
    \\ENQ\EOT\a\STX\STX\ETX\DC2\ETXK%&\n\
    \\v\n\
    \\EOT\EOT\a\STX\ETX\DC2\ETXL\EOT'\n\
    \\f\n\
    \\ENQ\EOT\a\STX\ETX\ACK\DC2\ETXL\EOT\DC2\n\
    \\f\n\
    \\ENQ\EOT\a\STX\ETX\SOH\DC2\ETXL\DC3\"\n\
    \\f\n\
    \\ENQ\EOT\a\STX\ETX\ETX\DC2\ETXL%&b\ACKproto3"