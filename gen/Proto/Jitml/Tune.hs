{- This file was auto-generated from jitml/tune.proto by the proto-lens-protoc program. -}
{-# LANGUAGE ScopedTypeVariables, DataKinds, TypeFamilies, UndecidableInstances, GeneralizedNewtypeDeriving, MultiParamTypeClasses, FlexibleContexts, FlexibleInstances, PatternSynonyms, MagicHash, NoImplicitPrelude, DataKinds, BangPatterns, TypeApplications, OverloadedStrings, DerivingStrategies#-}
{-# OPTIONS_GHC -Wno-unused-imports#-}
{-# OPTIONS_GHC -Wno-duplicate-exports#-}
{-# OPTIONS_GHC -Wno-dodgy-exports#-}
module Proto.Jitml.Tune (
        StartSweep(), StopSweep(), SweepDone(), TrialFinished(),
        TrialStarted(), TuneCommand(), TuneCommand'Body(..),
        _TuneCommand'Start, _TuneCommand'Stop, TuneEvent(),
        TuneEvent'Body(..), _TuneEvent'Started, _TuneEvent'Finished,
        _TuneEvent'Done
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
         * 'Proto.Jitml.Tune_Fields.pruner' @:: Lens' StartSweep Data.Text.Text@ -}
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
      \\ACKpruner\CAN\t \SOH(\tR\ACKpruner"
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
           (Data.ProtoLens.Tag 9, pruner__field_descriptor)]
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
                                     (Data.ProtoLens.Encoding.Wire.buildFieldSet
                                        (Lens.Family2.view Data.ProtoLens.unknownFields _x))))))))))
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
                                     (Control.DeepSeq.deepseq (_StartSweep'pruner x__) ())))))))))
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
     
         * 'Proto.Jitml.Tune_Fields.experimentHash' @:: Lens' SweepDone Data.Text.Text@
         * 'Proto.Jitml.Tune_Fields.trialsCompleted' @:: Lens' SweepDone Data.Word.Word32@
         * 'Proto.Jitml.Tune_Fields.trialsPruned' @:: Lens' SweepDone Data.Word.Word32@
         * 'Proto.Jitml.Tune_Fields.bestObjective' @:: Lens' SweepDone Prelude.Double@ -}
data SweepDone
  = SweepDone'_constructor {_SweepDone'experimentHash :: !Data.Text.Text,
                            _SweepDone'trialsCompleted :: !Data.Word.Word32,
                            _SweepDone'trialsPruned :: !Data.Word.Word32,
                            _SweepDone'bestObjective :: !Prelude.Double,
                            _SweepDone'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show SweepDone where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField SweepDone "experimentHash" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SweepDone'experimentHash
           (\ x__ y__ -> x__ {_SweepDone'experimentHash = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SweepDone "trialsCompleted" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SweepDone'trialsCompleted
           (\ x__ y__ -> x__ {_SweepDone'trialsCompleted = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SweepDone "trialsPruned" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SweepDone'trialsPruned
           (\ x__ y__ -> x__ {_SweepDone'trialsPruned = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SweepDone "bestObjective" Prelude.Double where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SweepDone'bestObjective
           (\ x__ y__ -> x__ {_SweepDone'bestObjective = y__}))
        Prelude.id
instance Data.ProtoLens.Message SweepDone where
  messageName _ = Data.Text.pack "jitml.tune.SweepDone"
  packedMessageDescriptor _
    = "\n\
      \\tSweepDone\DC2'\n\
      \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2)\n\
      \\DLEtrials_completed\CAN\STX \SOH(\rR\SItrialsCompleted\DC2#\n\
      \\rtrials_pruned\CAN\ETX \SOH(\rR\ftrialsPruned\DC2%\n\
      \\SObest_objective\CAN\EOT \SOH(\SOHR\rbestObjective"
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
              Data.ProtoLens.FieldDescriptor SweepDone
        trialsCompleted__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "trials_completed"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"trialsCompleted")) ::
              Data.ProtoLens.FieldDescriptor SweepDone
        trialsPruned__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "trials_pruned"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"trialsPruned")) ::
              Data.ProtoLens.FieldDescriptor SweepDone
        bestObjective__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "best_objective"
              (Data.ProtoLens.ScalarField Data.ProtoLens.DoubleField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Double)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"bestObjective")) ::
              Data.ProtoLens.FieldDescriptor SweepDone
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, experimentHash__field_descriptor),
           (Data.ProtoLens.Tag 2, trialsCompleted__field_descriptor),
           (Data.ProtoLens.Tag 3, trialsPruned__field_descriptor),
           (Data.ProtoLens.Tag 4, bestObjective__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _SweepDone'_unknownFields
        (\ x__ y__ -> x__ {_SweepDone'_unknownFields = y__})
  defMessage
    = SweepDone'_constructor
        {_SweepDone'experimentHash = Data.ProtoLens.fieldDefault,
         _SweepDone'trialsCompleted = Data.ProtoLens.fieldDefault,
         _SweepDone'trialsPruned = Data.ProtoLens.fieldDefault,
         _SweepDone'bestObjective = Data.ProtoLens.fieldDefault,
         _SweepDone'_unknownFields = []}
  parseMessage
    = let
        loop :: SweepDone -> Data.ProtoLens.Encoding.Bytes.Parser SweepDone
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
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "SweepDone"
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
                      (Data.ProtoLens.Encoding.Wire.buildFieldSet
                         (Lens.Family2.view Data.ProtoLens.unknownFields _x)))))
instance Control.DeepSeq.NFData SweepDone where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_SweepDone'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_SweepDone'experimentHash x__)
                (Control.DeepSeq.deepseq
                   (_SweepDone'trialsCompleted x__)
                   (Control.DeepSeq.deepseq
                      (_SweepDone'trialsPruned x__)
                      (Control.DeepSeq.deepseq (_SweepDone'bestObjective x__) ()))))
{- | Fields :
     
         * 'Proto.Jitml.Tune_Fields.experimentHash' @:: Lens' TrialFinished Data.Text.Text@
         * 'Proto.Jitml.Tune_Fields.trial' @:: Lens' TrialFinished Data.Word.Word32@
         * 'Proto.Jitml.Tune_Fields.objective' @:: Lens' TrialFinished Prelude.Double@
         * 'Proto.Jitml.Tune_Fields.pruned' @:: Lens' TrialFinished Prelude.Bool@
         * 'Proto.Jitml.Tune_Fields.transcriptObjectKey' @:: Lens' TrialFinished Data.Text.Text@
         * 'Proto.Jitml.Tune_Fields.timestampNs' @:: Lens' TrialFinished Data.Word.Word64@ -}
data TrialFinished
  = TrialFinished'_constructor {_TrialFinished'experimentHash :: !Data.Text.Text,
                                _TrialFinished'trial :: !Data.Word.Word32,
                                _TrialFinished'objective :: !Prelude.Double,
                                _TrialFinished'pruned :: !Prelude.Bool,
                                _TrialFinished'transcriptObjectKey :: !Data.Text.Text,
                                _TrialFinished'timestampNs :: !Data.Word.Word64,
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
      \\ftimestamp_ns\CAN\ACK \SOH(\EOTR\vtimestampNs"
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
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, experimentHash__field_descriptor),
           (Data.ProtoLens.Tag 2, trial__field_descriptor),
           (Data.ProtoLens.Tag 3, objective__field_descriptor),
           (Data.ProtoLens.Tag 4, pruned__field_descriptor),
           (Data.ProtoLens.Tag 5, transcriptObjectKey__field_descriptor),
           (Data.ProtoLens.Tag 6, timestampNs__field_descriptor)]
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
                            (Data.ProtoLens.Encoding.Wire.buildFieldSet
                               (Lens.Family2.view Data.ProtoLens.unknownFields _x)))))))
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
                            (Control.DeepSeq.deepseq (_TrialFinished'timestampNs x__) ()))))))
{- | Fields :
     
         * 'Proto.Jitml.Tune_Fields.experimentHash' @:: Lens' TrialStarted Data.Text.Text@
         * 'Proto.Jitml.Tune_Fields.trial' @:: Lens' TrialStarted Data.Word.Word32@
         * 'Proto.Jitml.Tune_Fields.trialSeed' @:: Lens' TrialStarted Data.Word.Word64@
         * 'Proto.Jitml.Tune_Fields.parametersJson' @:: Lens' TrialStarted Data.Text.Text@
         * 'Proto.Jitml.Tune_Fields.timestampNs' @:: Lens' TrialStarted Data.Word.Word64@ -}
data TrialStarted
  = TrialStarted'_constructor {_TrialStarted'experimentHash :: !Data.Text.Text,
                               _TrialStarted'trial :: !Data.Word.Word32,
                               _TrialStarted'trialSeed :: !Data.Word.Word64,
                               _TrialStarted'parametersJson :: !Data.Text.Text,
                               _TrialStarted'timestampNs :: !Data.Word.Word64,
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
      \\ftimestamp_ns\CAN\ENQ \SOH(\EOTR\vtimestampNs"
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
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, experimentHash__field_descriptor),
           (Data.ProtoLens.Tag 2, trial__field_descriptor),
           (Data.ProtoLens.Tag 3, trialSeed__field_descriptor),
           (Data.ProtoLens.Tag 4, parametersJson__field_descriptor),
           (Data.ProtoLens.Tag 5, timestampNs__field_descriptor)]
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
                         (Data.ProtoLens.Encoding.Wire.buildFieldSet
                            (Lens.Family2.view Data.ProtoLens.unknownFields _x))))))
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
                         (Control.DeepSeq.deepseq (_TrialStarted'timestampNs x__) ())))))
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
         * 'Proto.Jitml.Tune_Fields.maybe'done' @:: Lens' TuneEvent (Prelude.Maybe SweepDone)@
         * 'Proto.Jitml.Tune_Fields.done' @:: Lens' TuneEvent SweepDone@ -}
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
    TuneEvent'Done !SweepDone
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
instance Data.ProtoLens.Field.HasField TuneEvent "maybe'done" (Prelude.Maybe SweepDone) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TuneEvent'body (\ x__ y__ -> x__ {_TuneEvent'body = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (TuneEvent'Done x__val)) -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap TuneEvent'Done y__))
instance Data.ProtoLens.Field.HasField TuneEvent "done" SweepDone where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TuneEvent'body (\ x__ y__ -> x__ {_TuneEvent'body = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (TuneEvent'Done x__val)) -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap TuneEvent'Done y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Message TuneEvent where
  messageName _ = Data.Text.pack "jitml.tune.TuneEvent"
  packedMessageDescriptor _
    = "\n\
      \\tTuneEvent\DC24\n\
      \\astarted\CAN\SOH \SOH(\v2\CAN.jitml.tune.TrialStartedH\NULR\astarted\DC27\n\
      \\bfinished\CAN\STX \SOH(\v2\EM.jitml.tune.TrialFinishedH\NULR\bfinished\DC2+\n\
      \\EOTdone\CAN\ETX \SOH(\v2\NAK.jitml.tune.SweepDoneH\NULR\EOTdoneB\ACK\n\
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
        done__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "done"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor SweepDone)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'done")) ::
              Data.ProtoLens.FieldDescriptor TuneEvent
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, started__field_descriptor),
           (Data.ProtoLens.Tag 2, finished__field_descriptor),
           (Data.ProtoLens.Tag 3, done__field_descriptor)]
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
                                       "done"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"done") y x)
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
                (Prelude.Just (TuneEvent'Done v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 26)
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
  rnf (TuneEvent'Done x__) = Control.DeepSeq.rnf x__
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
_TuneEvent'Done ::
  Data.ProtoLens.Prism.Prism' TuneEvent'Body SweepDone
_TuneEvent'Done
  = Data.ProtoLens.Prism.prism'
      TuneEvent'Done
      (\ p__
         -> case p__ of
              (TuneEvent'Done p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
packedFileDescriptor :: Data.ByteString.ByteString
packedFileDescriptor
  = "\n\
    \\DLEjitml/tune.proto\DC2\n\
    \jitml.tune\"\185\STX\n\
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
    \\ACKpruner\CAN\t \SOH(\tR\ACKpruner\"4\n\
    \\tStopSweep\DC2'\n\
    \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\"\184\SOH\n\
    \\fTrialStarted\DC2'\n\
    \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2\DC4\n\
    \\ENQtrial\CAN\STX \SOH(\rR\ENQtrial\DC2\GS\n\
    \\n\
    \trial_seed\CAN\ETX \SOH(\EOTR\ttrialSeed\DC2'\n\
    \\SIparameters_json\CAN\EOT \SOH(\tR\SOparametersJson\DC2!\n\
    \\ftimestamp_ns\CAN\ENQ \SOH(\EOTR\vtimestampNs\"\219\SOH\n\
    \\rTrialFinished\DC2'\n\
    \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2\DC4\n\
    \\ENQtrial\CAN\STX \SOH(\rR\ENQtrial\DC2\FS\n\
    \\tobjective\CAN\ETX \SOH(\SOHR\tobjective\DC2\SYN\n\
    \\ACKpruned\CAN\EOT \SOH(\bR\ACKpruned\DC22\n\
    \\NAKtranscript_object_key\CAN\ENQ \SOH(\tR\DC3transcriptObjectKey\DC2!\n\
    \\ftimestamp_ns\CAN\ACK \SOH(\EOTR\vtimestampNs\"\171\SOH\n\
    \\tSweepDone\DC2'\n\
    \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2)\n\
    \\DLEtrials_completed\CAN\STX \SOH(\rR\SItrialsCompleted\DC2#\n\
    \\rtrials_pruned\CAN\ETX \SOH(\rR\ftrialsPruned\DC2%\n\
    \\SObest_objective\CAN\EOT \SOH(\SOHR\rbestObjective\"r\n\
    \\vTuneCommand\DC2.\n\
    \\ENQstart\CAN\SOH \SOH(\v2\SYN.jitml.tune.StartSweepH\NULR\ENQstart\DC2+\n\
    \\EOTstop\CAN\STX \SOH(\v2\NAK.jitml.tune.StopSweepH\NULR\EOTstopB\ACK\n\
    \\EOTbody\"\175\SOH\n\
    \\tTuneEvent\DC24\n\
    \\astarted\CAN\SOH \SOH(\v2\CAN.jitml.tune.TrialStartedH\NULR\astarted\DC27\n\
    \\bfinished\CAN\STX \SOH(\v2\EM.jitml.tune.TrialFinishedH\NULR\bfinished\DC2+\n\
    \\EOTdone\CAN\ETX \SOH(\v2\NAK.jitml.tune.SweepDoneH\NULR\EOTdoneB\ACK\n\
    \\EOTbodyJ\207\DLE\n\
    \\ACK\DC2\EOT\NUL\NUL;\SOH\n\
    \\b\n\
    \\SOH\f\DC2\ETX\NUL\NUL\DC2\n\
    \\b\n\
    \\SOH\STX\DC2\ETX\STX\NUL\DC3\n\
    \s\n\
    \\STX\EOT\NUL\DC2\EOT\ACK\NUL\DLE\SOH\SUBg Envelope sent on `tune.command.<mode>` to drive a hyperparameter sweep\n\
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
    \\n\
    \\n\
    \\STX\EOT\SOH\DC2\EOT\DC2\NUL\DC4\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\SOH\SOH\DC2\ETX\DC2\b\DC1\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\NUL\DC2\ETX\DC3\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ENQ\DC2\ETX\DC3\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\SOH\DC2\ETX\DC3\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ETX\DC2\ETX\DC3\ESC\FS\n\
    \\n\
    \\n\
    \\STX\EOT\STX\DC2\EOT\SYN\NUL\FS\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\STX\SOH\DC2\ETX\SYN\b\DC4\n\
    \\v\n\
    \\EOT\EOT\STX\STX\NUL\DC2\ETX\ETB\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\NUL\ENQ\DC2\ETX\ETB\STX\b\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\NUL\SOH\DC2\ETX\ETB\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\NUL\ETX\DC2\ETX\ETB\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\STX\STX\SOH\DC2\ETX\CAN\STX\DC3\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\SOH\ENQ\DC2\ETX\CAN\STX\b\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\SOH\SOH\DC2\ETX\CAN\t\SO\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\SOH\ETX\DC2\ETX\CAN\DC1\DC2\n\
    \\v\n\
    \\EOT\EOT\STX\STX\STX\DC2\ETX\EM\STX\CAN\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\STX\ENQ\DC2\ETX\EM\STX\b\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\STX\SOH\DC2\ETX\EM\t\DC3\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\STX\ETX\DC2\ETX\EM\SYN\ETB\n\
    \\v\n\
    \\EOT\EOT\STX\STX\ETX\DC2\ETX\SUB\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\ETX\ENQ\DC2\ETX\SUB\STX\b\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\ETX\SOH\DC2\ETX\SUB\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\ETX\ETX\DC2\ETX\SUB\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\STX\STX\EOT\DC2\ETX\ESC\STX\SUB\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\EOT\ENQ\DC2\ETX\ESC\STX\b\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\EOT\SOH\DC2\ETX\ESC\t\NAK\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\EOT\ETX\DC2\ETX\ESC\CAN\EM\n\
    \\n\
    \\n\
    \\STX\EOT\ETX\DC2\EOT\RS\NUL%\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\ETX\SOH\DC2\ETX\RS\b\NAK\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\NUL\DC2\ETX\US\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\NUL\ENQ\DC2\ETX\US\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\NUL\SOH\DC2\ETX\US\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\NUL\ETX\DC2\ETX\US\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\SOH\DC2\ETX \STX\DC3\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\SOH\ENQ\DC2\ETX \STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\SOH\SOH\DC2\ETX \t\SO\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\SOH\ETX\DC2\ETX \DC1\DC2\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\STX\DC2\ETX!\STX\ETB\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\STX\ENQ\DC2\ETX!\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\STX\SOH\DC2\ETX!\t\DC2\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\STX\ETX\DC2\ETX!\NAK\SYN\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\ETX\DC2\ETX\"\STX\DC2\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ETX\ENQ\DC2\ETX\"\STX\ACK\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ETX\SOH\DC2\ETX\"\a\r\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ETX\ETX\DC2\ETX\"\DLE\DC1\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\EOT\DC2\ETX#\STX#\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\EOT\ENQ\DC2\ETX#\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\EOT\SOH\DC2\ETX#\t\RS\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\EOT\ETX\DC2\ETX#!\"\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\ENQ\DC2\ETX$\STX\SUB\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ENQ\ENQ\DC2\ETX$\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ENQ\SOH\DC2\ETX$\t\NAK\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ENQ\ETX\DC2\ETX$\CAN\EM\n\
    \\n\
    \\n\
    \\STX\EOT\EOT\DC2\EOT'\NUL,\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\EOT\SOH\DC2\ETX'\b\DC1\n\
    \\v\n\
    \\EOT\EOT\EOT\STX\NUL\DC2\ETX(\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\NUL\ENQ\DC2\ETX(\STX\b\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\NUL\SOH\DC2\ETX(\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\NUL\ETX\DC2\ETX(\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\EOT\STX\SOH\DC2\ETX)\STX\RS\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\SOH\ENQ\DC2\ETX)\STX\b\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\SOH\SOH\DC2\ETX)\t\EM\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\SOH\ETX\DC2\ETX)\FS\GS\n\
    \\v\n\
    \\EOT\EOT\EOT\STX\STX\DC2\ETX*\STX\ESC\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\STX\ENQ\DC2\ETX*\STX\b\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\STX\SOH\DC2\ETX*\t\SYN\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\STX\ETX\DC2\ETX*\EM\SUB\n\
    \\v\n\
    \\EOT\EOT\EOT\STX\ETX\DC2\ETX+\STX\FS\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\ETX\ENQ\DC2\ETX+\STX\b\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\ETX\SOH\DC2\ETX+\t\ETB\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\ETX\ETX\DC2\ETX+\SUB\ESC\n\
    \\n\
    \\n\
    \\STX\EOT\ENQ\DC2\EOT.\NUL3\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\ENQ\SOH\DC2\ETX.\b\DC3\n\
    \\f\n\
    \\EOT\EOT\ENQ\b\NUL\DC2\EOT/\STX2\ETX\n\
    \\f\n\
    \\ENQ\EOT\ENQ\b\NUL\SOH\DC2\ETX/\b\f\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\NUL\DC2\ETX0\EOT\EM\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\NUL\ACK\DC2\ETX0\EOT\SO\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\NUL\SOH\DC2\ETX0\SI\DC4\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\NUL\ETX\DC2\ETX0\ETB\CAN\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\SOH\DC2\ETX1\EOT\EM\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\SOH\ACK\DC2\ETX1\EOT\r\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\SOH\SOH\DC2\ETX1\SI\DC3\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\SOH\ETX\DC2\ETX1\ETB\CAN\n\
    \\n\
    \\n\
    \\STX\EOT\ACK\DC2\EOT5\NUL;\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\ACK\SOH\DC2\ETX5\b\DC1\n\
    \\f\n\
    \\EOT\EOT\ACK\b\NUL\DC2\EOT6\STX:\ETX\n\
    \\f\n\
    \\ENQ\EOT\ACK\b\NUL\SOH\DC2\ETX6\b\f\n\
    \\v\n\
    \\EOT\EOT\ACK\STX\NUL\DC2\ETX7\EOT!\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\NUL\ACK\DC2\ETX7\EOT\DLE\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\NUL\SOH\DC2\ETX7\DC3\SUB\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\NUL\ETX\DC2\ETX7\US \n\
    \\v\n\
    \\EOT\EOT\ACK\STX\SOH\DC2\ETX8\EOT!\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\SOH\ACK\DC2\ETX8\EOT\DC1\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\SOH\SOH\DC2\ETX8\DC3\ESC\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\SOH\ETX\DC2\ETX8\US \n\
    \\v\n\
    \\EOT\EOT\ACK\STX\STX\DC2\ETX9\EOT!\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\STX\ACK\DC2\ETX9\EOT\r\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\STX\SOH\DC2\ETX9\DC3\ETB\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\STX\ETX\DC2\ETX9\US b\ACKproto3"