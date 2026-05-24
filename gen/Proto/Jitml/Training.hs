{- This file was auto-generated from jitml/training.proto by the proto-lens-protoc program. -}
{-# LANGUAGE ScopedTypeVariables, DataKinds, TypeFamilies, UndecidableInstances, GeneralizedNewtypeDeriving, MultiParamTypeClasses, FlexibleContexts, FlexibleInstances, PatternSynonyms, MagicHash, NoImplicitPrelude, DataKinds, BangPatterns, TypeApplications, OverloadedStrings, DerivingStrategies#-}
{-# OPTIONS_GHC -Wno-unused-imports#-}
{-# OPTIONS_GHC -Wno-duplicate-exports#-}
{-# OPTIONS_GHC -Wno-dodgy-exports#-}
module Proto.Jitml.Training (
        CheckpointDone(), EpochCompleted(), ScalarMetric(),
        StartTraining(), StopTraining(), TrainingCommand(),
        TrainingCommand'Body(..), _TrainingCommand'Start,
        _TrainingCommand'Stop, TrainingEvent(), TrainingEvent'Body(..),
        _TrainingEvent'Epoch, _TrainingEvent'Checkpoint,
        _TrainingEvent'Failure, TrainingFailed()
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
     
         * 'Proto.Jitml.Training_Fields.experimentHash' @:: Lens' CheckpointDone Data.Text.Text@
         * 'Proto.Jitml.Training_Fields.manifestSha' @:: Lens' CheckpointDone Data.Text.Text@
         * 'Proto.Jitml.Training_Fields.step' @:: Lens' CheckpointDone Data.Word.Word64@
         * 'Proto.Jitml.Training_Fields.pointerKey' @:: Lens' CheckpointDone Data.Text.Text@
         * 'Proto.Jitml.Training_Fields.epoch' @:: Lens' CheckpointDone Data.Word.Word32@
         * 'Proto.Jitml.Training_Fields.trialSha' @:: Lens' CheckpointDone Data.Text.Text@
         * 'Proto.Jitml.Training_Fields.runUuid' @:: Lens' CheckpointDone Data.Text.Text@
         * 'Proto.Jitml.Training_Fields.metricsAtStep' @:: Lens' CheckpointDone [ScalarMetric]@
         * 'Proto.Jitml.Training_Fields.vec'metricsAtStep' @:: Lens' CheckpointDone (Data.Vector.Vector ScalarMetric)@ -}
data CheckpointDone
  = CheckpointDone'_constructor {_CheckpointDone'experimentHash :: !Data.Text.Text,
                                 _CheckpointDone'manifestSha :: !Data.Text.Text,
                                 _CheckpointDone'step :: !Data.Word.Word64,
                                 _CheckpointDone'pointerKey :: !Data.Text.Text,
                                 _CheckpointDone'epoch :: !Data.Word.Word32,
                                 _CheckpointDone'trialSha :: !Data.Text.Text,
                                 _CheckpointDone'runUuid :: !Data.Text.Text,
                                 _CheckpointDone'metricsAtStep :: !(Data.Vector.Vector ScalarMetric),
                                 _CheckpointDone'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show CheckpointDone where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField CheckpointDone "experimentHash" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CheckpointDone'experimentHash
           (\ x__ y__ -> x__ {_CheckpointDone'experimentHash = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CheckpointDone "manifestSha" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CheckpointDone'manifestSha
           (\ x__ y__ -> x__ {_CheckpointDone'manifestSha = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CheckpointDone "step" Data.Word.Word64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CheckpointDone'step
           (\ x__ y__ -> x__ {_CheckpointDone'step = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CheckpointDone "pointerKey" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CheckpointDone'pointerKey
           (\ x__ y__ -> x__ {_CheckpointDone'pointerKey = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CheckpointDone "epoch" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CheckpointDone'epoch
           (\ x__ y__ -> x__ {_CheckpointDone'epoch = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CheckpointDone "trialSha" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CheckpointDone'trialSha
           (\ x__ y__ -> x__ {_CheckpointDone'trialSha = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CheckpointDone "runUuid" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CheckpointDone'runUuid
           (\ x__ y__ -> x__ {_CheckpointDone'runUuid = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CheckpointDone "metricsAtStep" [ScalarMetric] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CheckpointDone'metricsAtStep
           (\ x__ y__ -> x__ {_CheckpointDone'metricsAtStep = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField CheckpointDone "vec'metricsAtStep" (Data.Vector.Vector ScalarMetric) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CheckpointDone'metricsAtStep
           (\ x__ y__ -> x__ {_CheckpointDone'metricsAtStep = y__}))
        Prelude.id
instance Data.ProtoLens.Message CheckpointDone where
  messageName _ = Data.Text.pack "jitml.training.CheckpointDone"
  packedMessageDescriptor _
    = "\n\
      \\SOCheckpointDone\DC2'\n\
      \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2!\n\
      \\fmanifest_sha\CAN\STX \SOH(\tR\vmanifestSha\DC2\DC2\n\
      \\EOTstep\CAN\ETX \SOH(\EOTR\EOTstep\DC2\US\n\
      \\vpointer_key\CAN\EOT \SOH(\tR\n\
      \pointerKey\DC2\DC4\n\
      \\ENQepoch\CAN\ENQ \SOH(\rR\ENQepoch\DC2\ESC\n\
      \\ttrial_sha\CAN\ACK \SOH(\tR\btrialSha\DC2\EM\n\
      \\brun_uuid\CAN\a \SOH(\tR\arunUuid\DC2D\n\
      \\SImetrics_at_step\CAN\b \ETX(\v2\FS.jitml.training.ScalarMetricR\rmetricsAtStep"
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
              Data.ProtoLens.FieldDescriptor CheckpointDone
        manifestSha__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "manifest_sha"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"manifestSha")) ::
              Data.ProtoLens.FieldDescriptor CheckpointDone
        step__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "step"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word64)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"step")) ::
              Data.ProtoLens.FieldDescriptor CheckpointDone
        pointerKey__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "pointer_key"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"pointerKey")) ::
              Data.ProtoLens.FieldDescriptor CheckpointDone
        epoch__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "epoch"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"epoch")) ::
              Data.ProtoLens.FieldDescriptor CheckpointDone
        trialSha__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "trial_sha"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"trialSha")) ::
              Data.ProtoLens.FieldDescriptor CheckpointDone
        runUuid__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "run_uuid"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"runUuid")) ::
              Data.ProtoLens.FieldDescriptor CheckpointDone
        metricsAtStep__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "metrics_at_step"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor ScalarMetric)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked
                 (Data.ProtoLens.Field.field @"metricsAtStep")) ::
              Data.ProtoLens.FieldDescriptor CheckpointDone
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, experimentHash__field_descriptor),
           (Data.ProtoLens.Tag 2, manifestSha__field_descriptor),
           (Data.ProtoLens.Tag 3, step__field_descriptor),
           (Data.ProtoLens.Tag 4, pointerKey__field_descriptor),
           (Data.ProtoLens.Tag 5, epoch__field_descriptor),
           (Data.ProtoLens.Tag 6, trialSha__field_descriptor),
           (Data.ProtoLens.Tag 7, runUuid__field_descriptor),
           (Data.ProtoLens.Tag 8, metricsAtStep__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _CheckpointDone'_unknownFields
        (\ x__ y__ -> x__ {_CheckpointDone'_unknownFields = y__})
  defMessage
    = CheckpointDone'_constructor
        {_CheckpointDone'experimentHash = Data.ProtoLens.fieldDefault,
         _CheckpointDone'manifestSha = Data.ProtoLens.fieldDefault,
         _CheckpointDone'step = Data.ProtoLens.fieldDefault,
         _CheckpointDone'pointerKey = Data.ProtoLens.fieldDefault,
         _CheckpointDone'epoch = Data.ProtoLens.fieldDefault,
         _CheckpointDone'trialSha = Data.ProtoLens.fieldDefault,
         _CheckpointDone'runUuid = Data.ProtoLens.fieldDefault,
         _CheckpointDone'metricsAtStep = Data.Vector.Generic.empty,
         _CheckpointDone'_unknownFields = []}
  parseMessage
    = let
        loop ::
          CheckpointDone
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld ScalarMetric
             -> Data.ProtoLens.Encoding.Bytes.Parser CheckpointDone
        loop x mutable'metricsAtStep
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'metricsAtStep <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                                (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                                   mutable'metricsAtStep)
                      (let missing = []
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
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t)
                           (Lens.Family2.set
                              (Data.ProtoLens.Field.field @"vec'metricsAtStep")
                              frozen'metricsAtStep x))
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
                                  mutable'metricsAtStep
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "manifest_sha"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"manifestSha") y x)
                                  mutable'metricsAtStep
                        24
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       Data.ProtoLens.Encoding.Bytes.getVarInt "step"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"step") y x)
                                  mutable'metricsAtStep
                        34
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "pointer_key"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"pointerKey") y x)
                                  mutable'metricsAtStep
                        40
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "epoch"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"epoch") y x)
                                  mutable'metricsAtStep
                        50
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "trial_sha"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"trialSha") y x)
                                  mutable'metricsAtStep
                        58
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "run_uuid"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"runUuid") y x)
                                  mutable'metricsAtStep
                        66
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.isolate
                                              (Prelude.fromIntegral len)
                                              Data.ProtoLens.parseMessage)
                                        "metrics_at_step"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append
                                          mutable'metricsAtStep y)
                                loop x v
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'metricsAtStep
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'metricsAtStep <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                         Data.ProtoLens.Encoding.Growing.new
              loop Data.ProtoLens.defMessage mutable'metricsAtStep)
          "CheckpointDone"
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
                     = Lens.Family2.view (Data.ProtoLens.Field.field @"manifestSha") _x
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
                   (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"step") _x
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
                           = Lens.Family2.view (Data.ProtoLens.Field.field @"pointerKey") _x
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
                            _v = Lens.Family2.view (Data.ProtoLens.Field.field @"epoch") _x
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
                               _v = Lens.Family2.view (Data.ProtoLens.Field.field @"trialSha") _x
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
                            ((Data.Monoid.<>)
                               (let
                                  _v = Lens.Family2.view (Data.ProtoLens.Field.field @"runUuid") _x
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
                                  (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                                     (\ _v
                                        -> (Data.Monoid.<>)
                                             (Data.ProtoLens.Encoding.Bytes.putVarInt 66)
                                             ((Prelude..)
                                                (\ bs
                                                   -> (Data.Monoid.<>)
                                                        (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                           (Prelude.fromIntegral
                                                              (Data.ByteString.length bs)))
                                                        (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                                Data.ProtoLens.encodeMessage _v))
                                     (Lens.Family2.view
                                        (Data.ProtoLens.Field.field @"vec'metricsAtStep") _x))
                                  (Data.ProtoLens.Encoding.Wire.buildFieldSet
                                     (Lens.Family2.view Data.ProtoLens.unknownFields _x)))))))))
instance Control.DeepSeq.NFData CheckpointDone where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_CheckpointDone'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_CheckpointDone'experimentHash x__)
                (Control.DeepSeq.deepseq
                   (_CheckpointDone'manifestSha x__)
                   (Control.DeepSeq.deepseq
                      (_CheckpointDone'step x__)
                      (Control.DeepSeq.deepseq
                         (_CheckpointDone'pointerKey x__)
                         (Control.DeepSeq.deepseq
                            (_CheckpointDone'epoch x__)
                            (Control.DeepSeq.deepseq
                               (_CheckpointDone'trialSha x__)
                               (Control.DeepSeq.deepseq
                                  (_CheckpointDone'runUuid x__)
                                  (Control.DeepSeq.deepseq
                                     (_CheckpointDone'metricsAtStep x__) ()))))))))
{- | Fields :
     
         * 'Proto.Jitml.Training_Fields.experimentHash' @:: Lens' EpochCompleted Data.Text.Text@
         * 'Proto.Jitml.Training_Fields.epoch' @:: Lens' EpochCompleted Data.Word.Word32@
         * 'Proto.Jitml.Training_Fields.loss' @:: Lens' EpochCompleted Prelude.Double@
         * 'Proto.Jitml.Training_Fields.validationLoss' @:: Lens' EpochCompleted Prelude.Double@
         * 'Proto.Jitml.Training_Fields.timestampNs' @:: Lens' EpochCompleted Data.Word.Word64@ -}
data EpochCompleted
  = EpochCompleted'_constructor {_EpochCompleted'experimentHash :: !Data.Text.Text,
                                 _EpochCompleted'epoch :: !Data.Word.Word32,
                                 _EpochCompleted'loss :: !Prelude.Double,
                                 _EpochCompleted'validationLoss :: !Prelude.Double,
                                 _EpochCompleted'timestampNs :: !Data.Word.Word64,
                                 _EpochCompleted'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show EpochCompleted where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField EpochCompleted "experimentHash" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _EpochCompleted'experimentHash
           (\ x__ y__ -> x__ {_EpochCompleted'experimentHash = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField EpochCompleted "epoch" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _EpochCompleted'epoch
           (\ x__ y__ -> x__ {_EpochCompleted'epoch = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField EpochCompleted "loss" Prelude.Double where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _EpochCompleted'loss
           (\ x__ y__ -> x__ {_EpochCompleted'loss = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField EpochCompleted "validationLoss" Prelude.Double where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _EpochCompleted'validationLoss
           (\ x__ y__ -> x__ {_EpochCompleted'validationLoss = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField EpochCompleted "timestampNs" Data.Word.Word64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _EpochCompleted'timestampNs
           (\ x__ y__ -> x__ {_EpochCompleted'timestampNs = y__}))
        Prelude.id
instance Data.ProtoLens.Message EpochCompleted where
  messageName _ = Data.Text.pack "jitml.training.EpochCompleted"
  packedMessageDescriptor _
    = "\n\
      \\SOEpochCompleted\DC2'\n\
      \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2\DC4\n\
      \\ENQepoch\CAN\STX \SOH(\rR\ENQepoch\DC2\DC2\n\
      \\EOTloss\CAN\ETX \SOH(\SOHR\EOTloss\DC2'\n\
      \\SIvalidation_loss\CAN\EOT \SOH(\SOHR\SOvalidationLoss\DC2!\n\
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
              Data.ProtoLens.FieldDescriptor EpochCompleted
        epoch__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "epoch"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"epoch")) ::
              Data.ProtoLens.FieldDescriptor EpochCompleted
        loss__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "loss"
              (Data.ProtoLens.ScalarField Data.ProtoLens.DoubleField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Double)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"loss")) ::
              Data.ProtoLens.FieldDescriptor EpochCompleted
        validationLoss__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "validation_loss"
              (Data.ProtoLens.ScalarField Data.ProtoLens.DoubleField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Double)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"validationLoss")) ::
              Data.ProtoLens.FieldDescriptor EpochCompleted
        timestampNs__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "timestamp_ns"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word64)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"timestampNs")) ::
              Data.ProtoLens.FieldDescriptor EpochCompleted
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, experimentHash__field_descriptor),
           (Data.ProtoLens.Tag 2, epoch__field_descriptor),
           (Data.ProtoLens.Tag 3, loss__field_descriptor),
           (Data.ProtoLens.Tag 4, validationLoss__field_descriptor),
           (Data.ProtoLens.Tag 5, timestampNs__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _EpochCompleted'_unknownFields
        (\ x__ y__ -> x__ {_EpochCompleted'_unknownFields = y__})
  defMessage
    = EpochCompleted'_constructor
        {_EpochCompleted'experimentHash = Data.ProtoLens.fieldDefault,
         _EpochCompleted'epoch = Data.ProtoLens.fieldDefault,
         _EpochCompleted'loss = Data.ProtoLens.fieldDefault,
         _EpochCompleted'validationLoss = Data.ProtoLens.fieldDefault,
         _EpochCompleted'timestampNs = Data.ProtoLens.fieldDefault,
         _EpochCompleted'_unknownFields = []}
  parseMessage
    = let
        loop ::
          EpochCompleted
          -> Data.ProtoLens.Encoding.Bytes.Parser EpochCompleted
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
                                       "epoch"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"epoch") y x)
                        25
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Data.ProtoLens.Encoding.Bytes.wordToDouble
                                          Data.ProtoLens.Encoding.Bytes.getFixed64)
                                       "loss"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"loss") y x)
                        33
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Data.ProtoLens.Encoding.Bytes.wordToDouble
                                          Data.ProtoLens.Encoding.Bytes.getFixed64)
                                       "validation_loss"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"validationLoss") y x)
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
          (do loop Data.ProtoLens.defMessage) "EpochCompleted"
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
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"epoch") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 16)
                         ((Prelude..)
                            Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                ((Data.Monoid.<>)
                   (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"loss") _x
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
                         _v
                           = Lens.Family2.view
                               (Data.ProtoLens.Field.field @"validationLoss") _x
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
instance Control.DeepSeq.NFData EpochCompleted where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_EpochCompleted'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_EpochCompleted'experimentHash x__)
                (Control.DeepSeq.deepseq
                   (_EpochCompleted'epoch x__)
                   (Control.DeepSeq.deepseq
                      (_EpochCompleted'loss x__)
                      (Control.DeepSeq.deepseq
                         (_EpochCompleted'validationLoss x__)
                         (Control.DeepSeq.deepseq (_EpochCompleted'timestampNs x__) ())))))
{- | Fields :
     
         * 'Proto.Jitml.Training_Fields.tag' @:: Lens' ScalarMetric Data.Text.Text@
         * 'Proto.Jitml.Training_Fields.value' @:: Lens' ScalarMetric Prelude.Double@ -}
data ScalarMetric
  = ScalarMetric'_constructor {_ScalarMetric'tag :: !Data.Text.Text,
                               _ScalarMetric'value :: !Prelude.Double,
                               _ScalarMetric'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show ScalarMetric where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField ScalarMetric "tag" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ScalarMetric'tag (\ x__ y__ -> x__ {_ScalarMetric'tag = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ScalarMetric "value" Prelude.Double where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ScalarMetric'value (\ x__ y__ -> x__ {_ScalarMetric'value = y__}))
        Prelude.id
instance Data.ProtoLens.Message ScalarMetric where
  messageName _ = Data.Text.pack "jitml.training.ScalarMetric"
  packedMessageDescriptor _
    = "\n\
      \\fScalarMetric\DC2\DLE\n\
      \\ETXtag\CAN\SOH \SOH(\tR\ETXtag\DC2\DC4\n\
      \\ENQvalue\CAN\STX \SOH(\SOHR\ENQvalue"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        tag__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "tag"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"tag")) ::
              Data.ProtoLens.FieldDescriptor ScalarMetric
        value__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "value"
              (Data.ProtoLens.ScalarField Data.ProtoLens.DoubleField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Double)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"value")) ::
              Data.ProtoLens.FieldDescriptor ScalarMetric
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, tag__field_descriptor),
           (Data.ProtoLens.Tag 2, value__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _ScalarMetric'_unknownFields
        (\ x__ y__ -> x__ {_ScalarMetric'_unknownFields = y__})
  defMessage
    = ScalarMetric'_constructor
        {_ScalarMetric'tag = Data.ProtoLens.fieldDefault,
         _ScalarMetric'value = Data.ProtoLens.fieldDefault,
         _ScalarMetric'_unknownFields = []}
  parseMessage
    = let
        loop ::
          ScalarMetric -> Data.ProtoLens.Encoding.Bytes.Parser ScalarMetric
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
                                       "tag"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"tag") y x)
                        17
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Data.ProtoLens.Encoding.Bytes.wordToDouble
                                          Data.ProtoLens.Encoding.Bytes.getFixed64)
                                       "value"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"value") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "ScalarMetric"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"tag") _x
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
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"value") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 17)
                         ((Prelude..)
                            Data.ProtoLens.Encoding.Bytes.putFixed64
                            Data.ProtoLens.Encoding.Bytes.doubleToWord _v))
                (Data.ProtoLens.Encoding.Wire.buildFieldSet
                   (Lens.Family2.view Data.ProtoLens.unknownFields _x)))
instance Control.DeepSeq.NFData ScalarMetric where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_ScalarMetric'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_ScalarMetric'tag x__)
                (Control.DeepSeq.deepseq (_ScalarMetric'value x__) ()))
{- | Fields :
     
         * 'Proto.Jitml.Training_Fields.experimentHash' @:: Lens' StartTraining Data.Text.Text@
         * 'Proto.Jitml.Training_Fields.dhallObjectKey' @:: Lens' StartTraining Data.Text.Text@
         * 'Proto.Jitml.Training_Fields.substrate' @:: Lens' StartTraining Data.Text.Text@
         * 'Proto.Jitml.Training_Fields.seed' @:: Lens' StartTraining Data.Word.Word64@
         * 'Proto.Jitml.Training_Fields.epochs' @:: Lens' StartTraining Data.Word.Word32@
         * 'Proto.Jitml.Training_Fields.batchSize' @:: Lens' StartTraining Data.Word.Word32@ -}
data StartTraining
  = StartTraining'_constructor {_StartTraining'experimentHash :: !Data.Text.Text,
                                _StartTraining'dhallObjectKey :: !Data.Text.Text,
                                _StartTraining'substrate :: !Data.Text.Text,
                                _StartTraining'seed :: !Data.Word.Word64,
                                _StartTraining'epochs :: !Data.Word.Word32,
                                _StartTraining'batchSize :: !Data.Word.Word32,
                                _StartTraining'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show StartTraining where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField StartTraining "experimentHash" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartTraining'experimentHash
           (\ x__ y__ -> x__ {_StartTraining'experimentHash = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField StartTraining "dhallObjectKey" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartTraining'dhallObjectKey
           (\ x__ y__ -> x__ {_StartTraining'dhallObjectKey = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField StartTraining "substrate" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartTraining'substrate
           (\ x__ y__ -> x__ {_StartTraining'substrate = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField StartTraining "seed" Data.Word.Word64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartTraining'seed (\ x__ y__ -> x__ {_StartTraining'seed = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField StartTraining "epochs" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartTraining'epochs
           (\ x__ y__ -> x__ {_StartTraining'epochs = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField StartTraining "batchSize" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartTraining'batchSize
           (\ x__ y__ -> x__ {_StartTraining'batchSize = y__}))
        Prelude.id
instance Data.ProtoLens.Message StartTraining where
  messageName _ = Data.Text.pack "jitml.training.StartTraining"
  packedMessageDescriptor _
    = "\n\
      \\rStartTraining\DC2'\n\
      \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2(\n\
      \\DLEdhall_object_key\CAN\STX \SOH(\tR\SOdhallObjectKey\DC2\FS\n\
      \\tsubstrate\CAN\ETX \SOH(\tR\tsubstrate\DC2\DC2\n\
      \\EOTseed\CAN\EOT \SOH(\EOTR\EOTseed\DC2\SYN\n\
      \\ACKepochs\CAN\ENQ \SOH(\rR\ACKepochs\DC2\GS\n\
      \\n\
      \batch_size\CAN\ACK \SOH(\rR\tbatchSize"
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
              Data.ProtoLens.FieldDescriptor StartTraining
        dhallObjectKey__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "dhall_object_key"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"dhallObjectKey")) ::
              Data.ProtoLens.FieldDescriptor StartTraining
        substrate__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "substrate"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"substrate")) ::
              Data.ProtoLens.FieldDescriptor StartTraining
        seed__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "seed"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word64)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"seed")) ::
              Data.ProtoLens.FieldDescriptor StartTraining
        epochs__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "epochs"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"epochs")) ::
              Data.ProtoLens.FieldDescriptor StartTraining
        batchSize__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "batch_size"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"batchSize")) ::
              Data.ProtoLens.FieldDescriptor StartTraining
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, experimentHash__field_descriptor),
           (Data.ProtoLens.Tag 2, dhallObjectKey__field_descriptor),
           (Data.ProtoLens.Tag 3, substrate__field_descriptor),
           (Data.ProtoLens.Tag 4, seed__field_descriptor),
           (Data.ProtoLens.Tag 5, epochs__field_descriptor),
           (Data.ProtoLens.Tag 6, batchSize__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _StartTraining'_unknownFields
        (\ x__ y__ -> x__ {_StartTraining'_unknownFields = y__})
  defMessage
    = StartTraining'_constructor
        {_StartTraining'experimentHash = Data.ProtoLens.fieldDefault,
         _StartTraining'dhallObjectKey = Data.ProtoLens.fieldDefault,
         _StartTraining'substrate = Data.ProtoLens.fieldDefault,
         _StartTraining'seed = Data.ProtoLens.fieldDefault,
         _StartTraining'epochs = Data.ProtoLens.fieldDefault,
         _StartTraining'batchSize = Data.ProtoLens.fieldDefault,
         _StartTraining'_unknownFields = []}
  parseMessage
    = let
        loop ::
          StartTraining -> Data.ProtoLens.Encoding.Bytes.Parser StartTraining
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
                                       Data.ProtoLens.Encoding.Bytes.getVarInt "seed"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"seed") y x)
                        40
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "epochs"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"epochs") y x)
                        48
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "batch_size"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"batchSize") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "StartTraining"
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
                      (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"seed") _x
                       in
                         if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                             Data.Monoid.mempty
                         else
                             (Data.Monoid.<>)
                               (Data.ProtoLens.Encoding.Bytes.putVarInt 32)
                               (Data.ProtoLens.Encoding.Bytes.putVarInt _v))
                      ((Data.Monoid.<>)
                         (let
                            _v = Lens.Family2.view (Data.ProtoLens.Field.field @"epochs") _x
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
                               _v = Lens.Family2.view (Data.ProtoLens.Field.field @"batchSize") _x
                             in
                               if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                   Data.Monoid.mempty
                               else
                                   (Data.Monoid.<>)
                                     (Data.ProtoLens.Encoding.Bytes.putVarInt 48)
                                     ((Prelude..)
                                        Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral
                                        _v))
                            (Data.ProtoLens.Encoding.Wire.buildFieldSet
                               (Lens.Family2.view Data.ProtoLens.unknownFields _x)))))))
instance Control.DeepSeq.NFData StartTraining where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_StartTraining'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_StartTraining'experimentHash x__)
                (Control.DeepSeq.deepseq
                   (_StartTraining'dhallObjectKey x__)
                   (Control.DeepSeq.deepseq
                      (_StartTraining'substrate x__)
                      (Control.DeepSeq.deepseq
                         (_StartTraining'seed x__)
                         (Control.DeepSeq.deepseq
                            (_StartTraining'epochs x__)
                            (Control.DeepSeq.deepseq (_StartTraining'batchSize x__) ()))))))
{- | Fields :
     
         * 'Proto.Jitml.Training_Fields.experimentHash' @:: Lens' StopTraining Data.Text.Text@
         * 'Proto.Jitml.Training_Fields.drain' @:: Lens' StopTraining Prelude.Bool@ -}
data StopTraining
  = StopTraining'_constructor {_StopTraining'experimentHash :: !Data.Text.Text,
                               _StopTraining'drain :: !Prelude.Bool,
                               _StopTraining'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show StopTraining where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField StopTraining "experimentHash" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StopTraining'experimentHash
           (\ x__ y__ -> x__ {_StopTraining'experimentHash = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField StopTraining "drain" Prelude.Bool where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StopTraining'drain (\ x__ y__ -> x__ {_StopTraining'drain = y__}))
        Prelude.id
instance Data.ProtoLens.Message StopTraining where
  messageName _ = Data.Text.pack "jitml.training.StopTraining"
  packedMessageDescriptor _
    = "\n\
      \\fStopTraining\DC2'\n\
      \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2\DC4\n\
      \\ENQdrain\CAN\STX \SOH(\bR\ENQdrain"
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
              Data.ProtoLens.FieldDescriptor StopTraining
        drain__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "drain"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BoolField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Bool)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"drain")) ::
              Data.ProtoLens.FieldDescriptor StopTraining
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, experimentHash__field_descriptor),
           (Data.ProtoLens.Tag 2, drain__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _StopTraining'_unknownFields
        (\ x__ y__ -> x__ {_StopTraining'_unknownFields = y__})
  defMessage
    = StopTraining'_constructor
        {_StopTraining'experimentHash = Data.ProtoLens.fieldDefault,
         _StopTraining'drain = Data.ProtoLens.fieldDefault,
         _StopTraining'_unknownFields = []}
  parseMessage
    = let
        loop ::
          StopTraining -> Data.ProtoLens.Encoding.Bytes.Parser StopTraining
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
                                          ((Prelude./=) 0) Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "drain"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"drain") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "StopTraining"
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
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"drain") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 16)
                         ((Prelude..)
                            Data.ProtoLens.Encoding.Bytes.putVarInt (\ b -> if b then 1 else 0)
                            _v))
                (Data.ProtoLens.Encoding.Wire.buildFieldSet
                   (Lens.Family2.view Data.ProtoLens.unknownFields _x)))
instance Control.DeepSeq.NFData StopTraining where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_StopTraining'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_StopTraining'experimentHash x__)
                (Control.DeepSeq.deepseq (_StopTraining'drain x__) ()))
{- | Fields :
     
         * 'Proto.Jitml.Training_Fields.maybe'body' @:: Lens' TrainingCommand (Prelude.Maybe TrainingCommand'Body)@
         * 'Proto.Jitml.Training_Fields.maybe'start' @:: Lens' TrainingCommand (Prelude.Maybe StartTraining)@
         * 'Proto.Jitml.Training_Fields.start' @:: Lens' TrainingCommand StartTraining@
         * 'Proto.Jitml.Training_Fields.maybe'stop' @:: Lens' TrainingCommand (Prelude.Maybe StopTraining)@
         * 'Proto.Jitml.Training_Fields.stop' @:: Lens' TrainingCommand StopTraining@ -}
data TrainingCommand
  = TrainingCommand'_constructor {_TrainingCommand'body :: !(Prelude.Maybe TrainingCommand'Body),
                                  _TrainingCommand'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show TrainingCommand where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
data TrainingCommand'Body
  = TrainingCommand'Start !StartTraining |
    TrainingCommand'Stop !StopTraining
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.Field.HasField TrainingCommand "maybe'body" (Prelude.Maybe TrainingCommand'Body) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TrainingCommand'body
           (\ x__ y__ -> x__ {_TrainingCommand'body = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField TrainingCommand "maybe'start" (Prelude.Maybe StartTraining) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TrainingCommand'body
           (\ x__ y__ -> x__ {_TrainingCommand'body = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (TrainingCommand'Start x__val))
                     -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap TrainingCommand'Start y__))
instance Data.ProtoLens.Field.HasField TrainingCommand "start" StartTraining where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TrainingCommand'body
           (\ x__ y__ -> x__ {_TrainingCommand'body = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (TrainingCommand'Start x__val))
                        -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap TrainingCommand'Start y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField TrainingCommand "maybe'stop" (Prelude.Maybe StopTraining) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TrainingCommand'body
           (\ x__ y__ -> x__ {_TrainingCommand'body = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (TrainingCommand'Stop x__val)) -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap TrainingCommand'Stop y__))
instance Data.ProtoLens.Field.HasField TrainingCommand "stop" StopTraining where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TrainingCommand'body
           (\ x__ y__ -> x__ {_TrainingCommand'body = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (TrainingCommand'Stop x__val)) -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap TrainingCommand'Stop y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Message TrainingCommand where
  messageName _ = Data.Text.pack "jitml.training.TrainingCommand"
  packedMessageDescriptor _
    = "\n\
      \\SITrainingCommand\DC25\n\
      \\ENQstart\CAN\SOH \SOH(\v2\GS.jitml.training.StartTrainingH\NULR\ENQstart\DC22\n\
      \\EOTstop\CAN\STX \SOH(\v2\FS.jitml.training.StopTrainingH\NULR\EOTstopB\ACK\n\
      \\EOTbody"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        start__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "start"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor StartTraining)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'start")) ::
              Data.ProtoLens.FieldDescriptor TrainingCommand
        stop__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "stop"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor StopTraining)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'stop")) ::
              Data.ProtoLens.FieldDescriptor TrainingCommand
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, start__field_descriptor),
           (Data.ProtoLens.Tag 2, stop__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _TrainingCommand'_unknownFields
        (\ x__ y__ -> x__ {_TrainingCommand'_unknownFields = y__})
  defMessage
    = TrainingCommand'_constructor
        {_TrainingCommand'body = Prelude.Nothing,
         _TrainingCommand'_unknownFields = []}
  parseMessage
    = let
        loop ::
          TrainingCommand
          -> Data.ProtoLens.Encoding.Bytes.Parser TrainingCommand
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
          (do loop Data.ProtoLens.defMessage) "TrainingCommand"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (case
                  Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'body") _x
              of
                Prelude.Nothing -> Data.Monoid.mempty
                (Prelude.Just (TrainingCommand'Start v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v)
                (Prelude.Just (TrainingCommand'Stop v))
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
instance Control.DeepSeq.NFData TrainingCommand where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_TrainingCommand'_unknownFields x__)
             (Control.DeepSeq.deepseq (_TrainingCommand'body x__) ())
instance Control.DeepSeq.NFData TrainingCommand'Body where
  rnf (TrainingCommand'Start x__) = Control.DeepSeq.rnf x__
  rnf (TrainingCommand'Stop x__) = Control.DeepSeq.rnf x__
_TrainingCommand'Start ::
  Data.ProtoLens.Prism.Prism' TrainingCommand'Body StartTraining
_TrainingCommand'Start
  = Data.ProtoLens.Prism.prism'
      TrainingCommand'Start
      (\ p__
         -> case p__ of
              (TrainingCommand'Start p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_TrainingCommand'Stop ::
  Data.ProtoLens.Prism.Prism' TrainingCommand'Body StopTraining
_TrainingCommand'Stop
  = Data.ProtoLens.Prism.prism'
      TrainingCommand'Stop
      (\ p__
         -> case p__ of
              (TrainingCommand'Stop p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
{- | Fields :
     
         * 'Proto.Jitml.Training_Fields.maybe'body' @:: Lens' TrainingEvent (Prelude.Maybe TrainingEvent'Body)@
         * 'Proto.Jitml.Training_Fields.maybe'epoch' @:: Lens' TrainingEvent (Prelude.Maybe EpochCompleted)@
         * 'Proto.Jitml.Training_Fields.epoch' @:: Lens' TrainingEvent EpochCompleted@
         * 'Proto.Jitml.Training_Fields.maybe'checkpoint' @:: Lens' TrainingEvent (Prelude.Maybe CheckpointDone)@
         * 'Proto.Jitml.Training_Fields.checkpoint' @:: Lens' TrainingEvent CheckpointDone@
         * 'Proto.Jitml.Training_Fields.maybe'failure' @:: Lens' TrainingEvent (Prelude.Maybe TrainingFailed)@
         * 'Proto.Jitml.Training_Fields.failure' @:: Lens' TrainingEvent TrainingFailed@ -}
data TrainingEvent
  = TrainingEvent'_constructor {_TrainingEvent'body :: !(Prelude.Maybe TrainingEvent'Body),
                                _TrainingEvent'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show TrainingEvent where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
data TrainingEvent'Body
  = TrainingEvent'Epoch !EpochCompleted |
    TrainingEvent'Checkpoint !CheckpointDone |
    TrainingEvent'Failure !TrainingFailed
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.Field.HasField TrainingEvent "maybe'body" (Prelude.Maybe TrainingEvent'Body) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TrainingEvent'body (\ x__ y__ -> x__ {_TrainingEvent'body = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField TrainingEvent "maybe'epoch" (Prelude.Maybe EpochCompleted) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TrainingEvent'body (\ x__ y__ -> x__ {_TrainingEvent'body = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (TrainingEvent'Epoch x__val)) -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap TrainingEvent'Epoch y__))
instance Data.ProtoLens.Field.HasField TrainingEvent "epoch" EpochCompleted where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TrainingEvent'body (\ x__ y__ -> x__ {_TrainingEvent'body = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (TrainingEvent'Epoch x__val)) -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap TrainingEvent'Epoch y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField TrainingEvent "maybe'checkpoint" (Prelude.Maybe CheckpointDone) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TrainingEvent'body (\ x__ y__ -> x__ {_TrainingEvent'body = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (TrainingEvent'Checkpoint x__val))
                     -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap TrainingEvent'Checkpoint y__))
instance Data.ProtoLens.Field.HasField TrainingEvent "checkpoint" CheckpointDone where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TrainingEvent'body (\ x__ y__ -> x__ {_TrainingEvent'body = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (TrainingEvent'Checkpoint x__val))
                        -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap TrainingEvent'Checkpoint y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField TrainingEvent "maybe'failure" (Prelude.Maybe TrainingFailed) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TrainingEvent'body (\ x__ y__ -> x__ {_TrainingEvent'body = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (TrainingEvent'Failure x__val))
                     -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap TrainingEvent'Failure y__))
instance Data.ProtoLens.Field.HasField TrainingEvent "failure" TrainingFailed where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TrainingEvent'body (\ x__ y__ -> x__ {_TrainingEvent'body = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (TrainingEvent'Failure x__val))
                        -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap TrainingEvent'Failure y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Message TrainingEvent where
  messageName _ = Data.Text.pack "jitml.training.TrainingEvent"
  packedMessageDescriptor _
    = "\n\
      \\rTrainingEvent\DC26\n\
      \\ENQepoch\CAN\SOH \SOH(\v2\RS.jitml.training.EpochCompletedH\NULR\ENQepoch\DC2@\n\
      \\n\
      \checkpoint\CAN\STX \SOH(\v2\RS.jitml.training.CheckpointDoneH\NULR\n\
      \checkpoint\DC2:\n\
      \\afailure\CAN\ETX \SOH(\v2\RS.jitml.training.TrainingFailedH\NULR\afailureB\ACK\n\
      \\EOTbody"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        epoch__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "epoch"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor EpochCompleted)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'epoch")) ::
              Data.ProtoLens.FieldDescriptor TrainingEvent
        checkpoint__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "checkpoint"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor CheckpointDone)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'checkpoint")) ::
              Data.ProtoLens.FieldDescriptor TrainingEvent
        failure__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "failure"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor TrainingFailed)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'failure")) ::
              Data.ProtoLens.FieldDescriptor TrainingEvent
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, epoch__field_descriptor),
           (Data.ProtoLens.Tag 2, checkpoint__field_descriptor),
           (Data.ProtoLens.Tag 3, failure__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _TrainingEvent'_unknownFields
        (\ x__ y__ -> x__ {_TrainingEvent'_unknownFields = y__})
  defMessage
    = TrainingEvent'_constructor
        {_TrainingEvent'body = Prelude.Nothing,
         _TrainingEvent'_unknownFields = []}
  parseMessage
    = let
        loop ::
          TrainingEvent -> Data.ProtoLens.Encoding.Bytes.Parser TrainingEvent
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
                                       "epoch"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"epoch") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "checkpoint"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"checkpoint") y x)
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "failure"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"failure") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "TrainingEvent"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (case
                  Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'body") _x
              of
                Prelude.Nothing -> Data.Monoid.mempty
                (Prelude.Just (TrainingEvent'Epoch v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v)
                (Prelude.Just (TrainingEvent'Checkpoint v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v)
                (Prelude.Just (TrainingEvent'Failure v))
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
instance Control.DeepSeq.NFData TrainingEvent where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_TrainingEvent'_unknownFields x__)
             (Control.DeepSeq.deepseq (_TrainingEvent'body x__) ())
instance Control.DeepSeq.NFData TrainingEvent'Body where
  rnf (TrainingEvent'Epoch x__) = Control.DeepSeq.rnf x__
  rnf (TrainingEvent'Checkpoint x__) = Control.DeepSeq.rnf x__
  rnf (TrainingEvent'Failure x__) = Control.DeepSeq.rnf x__
_TrainingEvent'Epoch ::
  Data.ProtoLens.Prism.Prism' TrainingEvent'Body EpochCompleted
_TrainingEvent'Epoch
  = Data.ProtoLens.Prism.prism'
      TrainingEvent'Epoch
      (\ p__
         -> case p__ of
              (TrainingEvent'Epoch p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_TrainingEvent'Checkpoint ::
  Data.ProtoLens.Prism.Prism' TrainingEvent'Body CheckpointDone
_TrainingEvent'Checkpoint
  = Data.ProtoLens.Prism.prism'
      TrainingEvent'Checkpoint
      (\ p__
         -> case p__ of
              (TrainingEvent'Checkpoint p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_TrainingEvent'Failure ::
  Data.ProtoLens.Prism.Prism' TrainingEvent'Body TrainingFailed
_TrainingEvent'Failure
  = Data.ProtoLens.Prism.prism'
      TrainingEvent'Failure
      (\ p__
         -> case p__ of
              (TrainingEvent'Failure p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
{- | Fields :
     
         * 'Proto.Jitml.Training_Fields.experimentHash' @:: Lens' TrainingFailed Data.Text.Text@
         * 'Proto.Jitml.Training_Fields.errorCode' @:: Lens' TrainingFailed Data.Text.Text@
         * 'Proto.Jitml.Training_Fields.errorText' @:: Lens' TrainingFailed Data.Text.Text@
         * 'Proto.Jitml.Training_Fields.timestampNs' @:: Lens' TrainingFailed Data.Word.Word64@ -}
data TrainingFailed
  = TrainingFailed'_constructor {_TrainingFailed'experimentHash :: !Data.Text.Text,
                                 _TrainingFailed'errorCode :: !Data.Text.Text,
                                 _TrainingFailed'errorText :: !Data.Text.Text,
                                 _TrainingFailed'timestampNs :: !Data.Word.Word64,
                                 _TrainingFailed'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show TrainingFailed where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField TrainingFailed "experimentHash" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TrainingFailed'experimentHash
           (\ x__ y__ -> x__ {_TrainingFailed'experimentHash = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField TrainingFailed "errorCode" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TrainingFailed'errorCode
           (\ x__ y__ -> x__ {_TrainingFailed'errorCode = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField TrainingFailed "errorText" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TrainingFailed'errorText
           (\ x__ y__ -> x__ {_TrainingFailed'errorText = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField TrainingFailed "timestampNs" Data.Word.Word64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TrainingFailed'timestampNs
           (\ x__ y__ -> x__ {_TrainingFailed'timestampNs = y__}))
        Prelude.id
instance Data.ProtoLens.Message TrainingFailed where
  messageName _ = Data.Text.pack "jitml.training.TrainingFailed"
  packedMessageDescriptor _
    = "\n\
      \\SOTrainingFailed\DC2'\n\
      \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2\GS\n\
      \\n\
      \error_code\CAN\STX \SOH(\tR\terrorCode\DC2\GS\n\
      \\n\
      \error_text\CAN\ETX \SOH(\tR\terrorText\DC2!\n\
      \\ftimestamp_ns\CAN\EOT \SOH(\EOTR\vtimestampNs"
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
              Data.ProtoLens.FieldDescriptor TrainingFailed
        errorCode__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "error_code"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"errorCode")) ::
              Data.ProtoLens.FieldDescriptor TrainingFailed
        errorText__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "error_text"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"errorText")) ::
              Data.ProtoLens.FieldDescriptor TrainingFailed
        timestampNs__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "timestamp_ns"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word64)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"timestampNs")) ::
              Data.ProtoLens.FieldDescriptor TrainingFailed
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, experimentHash__field_descriptor),
           (Data.ProtoLens.Tag 2, errorCode__field_descriptor),
           (Data.ProtoLens.Tag 3, errorText__field_descriptor),
           (Data.ProtoLens.Tag 4, timestampNs__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _TrainingFailed'_unknownFields
        (\ x__ y__ -> x__ {_TrainingFailed'_unknownFields = y__})
  defMessage
    = TrainingFailed'_constructor
        {_TrainingFailed'experimentHash = Data.ProtoLens.fieldDefault,
         _TrainingFailed'errorCode = Data.ProtoLens.fieldDefault,
         _TrainingFailed'errorText = Data.ProtoLens.fieldDefault,
         _TrainingFailed'timestampNs = Data.ProtoLens.fieldDefault,
         _TrainingFailed'_unknownFields = []}
  parseMessage
    = let
        loop ::
          TrainingFailed
          -> Data.ProtoLens.Encoding.Bytes.Parser TrainingFailed
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
                                       "error_code"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"errorCode") y x)
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "error_text"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"errorText") y x)
                        32
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
          (do loop Data.ProtoLens.defMessage) "TrainingFailed"
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
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"errorCode") _x
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
                      _v = Lens.Family2.view (Data.ProtoLens.Field.field @"errorText") _x
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
                         _v
                           = Lens.Family2.view (Data.ProtoLens.Field.field @"timestampNs") _x
                       in
                         if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                             Data.Monoid.mempty
                         else
                             (Data.Monoid.<>)
                               (Data.ProtoLens.Encoding.Bytes.putVarInt 32)
                               (Data.ProtoLens.Encoding.Bytes.putVarInt _v))
                      (Data.ProtoLens.Encoding.Wire.buildFieldSet
                         (Lens.Family2.view Data.ProtoLens.unknownFields _x)))))
instance Control.DeepSeq.NFData TrainingFailed where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_TrainingFailed'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_TrainingFailed'experimentHash x__)
                (Control.DeepSeq.deepseq
                   (_TrainingFailed'errorCode x__)
                   (Control.DeepSeq.deepseq
                      (_TrainingFailed'errorText x__)
                      (Control.DeepSeq.deepseq (_TrainingFailed'timestampNs x__) ()))))
packedFileDescriptor :: Data.ByteString.ByteString
packedFileDescriptor
  = "\n\
    \\DC4jitml/training.proto\DC2\SOjitml.training\"\203\SOH\n\
    \\rStartTraining\DC2'\n\
    \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2(\n\
    \\DLEdhall_object_key\CAN\STX \SOH(\tR\SOdhallObjectKey\DC2\FS\n\
    \\tsubstrate\CAN\ETX \SOH(\tR\tsubstrate\DC2\DC2\n\
    \\EOTseed\CAN\EOT \SOH(\EOTR\EOTseed\DC2\SYN\n\
    \\ACKepochs\CAN\ENQ \SOH(\rR\ACKepochs\DC2\GS\n\
    \\n\
    \batch_size\CAN\ACK \SOH(\rR\tbatchSize\"M\n\
    \\fStopTraining\DC2'\n\
    \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2\DC4\n\
    \\ENQdrain\CAN\STX \SOH(\bR\ENQdrain\"\175\SOH\n\
    \\SOEpochCompleted\DC2'\n\
    \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2\DC4\n\
    \\ENQepoch\CAN\STX \SOH(\rR\ENQepoch\DC2\DC2\n\
    \\EOTloss\CAN\ETX \SOH(\SOHR\EOTloss\DC2'\n\
    \\SIvalidation_loss\CAN\EOT \SOH(\SOHR\SOvalidationLoss\DC2!\n\
    \\ftimestamp_ns\CAN\ENQ \SOH(\EOTR\vtimestampNs\"\165\STX\n\
    \\SOCheckpointDone\DC2'\n\
    \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2!\n\
    \\fmanifest_sha\CAN\STX \SOH(\tR\vmanifestSha\DC2\DC2\n\
    \\EOTstep\CAN\ETX \SOH(\EOTR\EOTstep\DC2\US\n\
    \\vpointer_key\CAN\EOT \SOH(\tR\n\
    \pointerKey\DC2\DC4\n\
    \\ENQepoch\CAN\ENQ \SOH(\rR\ENQepoch\DC2\ESC\n\
    \\ttrial_sha\CAN\ACK \SOH(\tR\btrialSha\DC2\EM\n\
    \\brun_uuid\CAN\a \SOH(\tR\arunUuid\DC2D\n\
    \\SImetrics_at_step\CAN\b \ETX(\v2\FS.jitml.training.ScalarMetricR\rmetricsAtStep\"6\n\
    \\fScalarMetric\DC2\DLE\n\
    \\ETXtag\CAN\SOH \SOH(\tR\ETXtag\DC2\DC4\n\
    \\ENQvalue\CAN\STX \SOH(\SOHR\ENQvalue\"\154\SOH\n\
    \\SOTrainingFailed\DC2'\n\
    \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2\GS\n\
    \\n\
    \error_code\CAN\STX \SOH(\tR\terrorCode\DC2\GS\n\
    \\n\
    \error_text\CAN\ETX \SOH(\tR\terrorText\DC2!\n\
    \\ftimestamp_ns\CAN\EOT \SOH(\EOTR\vtimestampNs\"\132\SOH\n\
    \\SITrainingCommand\DC25\n\
    \\ENQstart\CAN\SOH \SOH(\v2\GS.jitml.training.StartTrainingH\NULR\ENQstart\DC22\n\
    \\EOTstop\CAN\STX \SOH(\v2\FS.jitml.training.StopTrainingH\NULR\EOTstopB\ACK\n\
    \\EOTbody\"\205\SOH\n\
    \\rTrainingEvent\DC26\n\
    \\ENQepoch\CAN\SOH \SOH(\v2\RS.jitml.training.EpochCompletedH\NULR\ENQepoch\DC2@\n\
    \\n\
    \checkpoint\CAN\STX \SOH(\v2\RS.jitml.training.CheckpointDoneH\NULR\n\
    \checkpoint\DC2:\n\
    \\afailure\CAN\ETX \SOH(\v2\RS.jitml.training.TrainingFailedH\NULR\afailureB\ACK\n\
    \\EOTbodyJ\174\DC3\n\
    \\ACK\DC2\EOT\NUL\NULD\SOH\n\
    \\b\n\
    \\SOH\f\DC2\ETX\NUL\NUL\DC2\n\
    \\b\n\
    \\SOH\STX\DC2\ETX\STX\NUL\ETB\n\
    \\156\SOH\n\
    \\STX\EOT\NUL\DC2\EOT\a\NUL\SO\SOH\SUB\143\SOH Envelope sent on the substrate-scoped command topic\n\
    \ `training.command.<mode>` to drive an SL training run via the daemon's\n\
    \ TrainingHandler.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\NUL\SOH\DC2\ETX\a\b\NAK\n\
    \>\n\
    \\EOT\EOT\NUL\STX\NUL\DC2\ETX\b\STX\GS\"1 sha256(resolved-dhall || substrate-fingerprint)\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\ENQ\DC2\ETX\b\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\SOH\DC2\ETX\b\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\ETX\DC2\ETX\b\ESC\FS\n\
    \4\n\
    \\EOT\EOT\NUL\STX\SOH\DC2\ETX\t\STX\RS\"' MinIO key for the resolved Dhall blob\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\ENQ\DC2\ETX\t\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\SOH\DC2\ETX\t\t\EM\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\ETX\DC2\ETX\t\FS\GS\n\
    \;\n\
    \\EOT\EOT\NUL\STX\STX\DC2\ETX\n\
    \\STX\ETB\". \"apple-silicon\" | \"linux-cpu\" | \"linux-cuda\"\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\STX\ENQ\DC2\ETX\n\
    \\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\STX\SOH\DC2\ETX\n\
    \\t\DC2\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\STX\ETX\DC2\ETX\n\
    \\NAK\SYN\n\
    \\v\n\
    \\EOT\EOT\NUL\STX\ETX\DC2\ETX\v\STX\DC2\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ETX\ENQ\DC2\ETX\v\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ETX\SOH\DC2\ETX\v\t\r\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ETX\ETX\DC2\ETX\v\DLE\DC1\n\
    \\v\n\
    \\EOT\EOT\NUL\STX\EOT\DC2\ETX\f\STX\DC4\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\EOT\ENQ\DC2\ETX\f\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\EOT\SOH\DC2\ETX\f\t\SI\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\EOT\ETX\DC2\ETX\f\DC2\DC3\n\
    \\v\n\
    \\EOT\EOT\NUL\STX\ENQ\DC2\ETX\r\STX\CAN\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ENQ\ENQ\DC2\ETX\r\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ENQ\SOH\DC2\ETX\r\t\DC3\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ENQ\ETX\DC2\ETX\r\SYN\ETB\n\
    \\n\
    \\n\
    \\STX\EOT\SOH\DC2\EOT\DLE\NUL\DC3\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\SOH\SOH\DC2\ETX\DLE\b\DC4\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\NUL\DC2\ETX\DC1\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ENQ\DC2\ETX\DC1\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\SOH\DC2\ETX\DC1\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ETX\DC2\ETX\DC1\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\SOH\DC2\ETX\DC2\STX\DC3\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\ENQ\DC2\ETX\DC2\STX\ACK\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\SOH\DC2\ETX\DC2\t\SO\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\ETX\DC2\ETX\DC2\DC1\DC2\n\
    \=\n\
    \\STX\EOT\STX\DC2\EOT\SYN\NUL\FS\SOH\SUB1 Envelopes published on `training.event.<mode>`.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\STX\SOH\DC2\ETX\SYN\b\SYN\n\
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
    \\EOT\EOT\STX\STX\STX\DC2\ETX\EM\STX\DC2\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\STX\ENQ\DC2\ETX\EM\STX\b\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\STX\SOH\DC2\ETX\EM\t\r\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\STX\ETX\DC2\ETX\EM\DLE\DC1\n\
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
    \\STX\EOT\ETX\DC2\EOT\RS\NUL'\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\ETX\SOH\DC2\ETX\RS\b\SYN\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\NUL\DC2\ETX\US\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\NUL\ENQ\DC2\ETX\US\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\NUL\SOH\DC2\ETX\US\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\NUL\ETX\DC2\ETX\US\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\SOH\DC2\ETX \STX\SUB\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\SOH\ENQ\DC2\ETX \STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\SOH\SOH\DC2\ETX \t\NAK\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\SOH\ETX\DC2\ETX \CAN\EM\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\STX\DC2\ETX!\STX\DC2\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\STX\ENQ\DC2\ETX!\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\STX\SOH\DC2\ETX!\t\r\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\STX\ETX\DC2\ETX!\DLE\DC1\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\ETX\DC2\ETX\"\STX\EM\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ETX\ENQ\DC2\ETX\"\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ETX\SOH\DC2\ETX\"\t\DC4\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ETX\ETX\DC2\ETX\"\ETB\CAN\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\EOT\DC2\ETX#\STX\DC3\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\EOT\ENQ\DC2\ETX#\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\EOT\SOH\DC2\ETX#\t\SO\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\EOT\ETX\DC2\ETX#\DC1\DC2\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\ENQ\DC2\ETX$\STX\ETB\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ENQ\ENQ\DC2\ETX$\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ENQ\SOH\DC2\ETX$\t\DC2\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ENQ\ETX\DC2\ETX$\NAK\SYN\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\ACK\DC2\ETX%\STX\SYN\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ACK\ENQ\DC2\ETX%\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ACK\SOH\DC2\ETX%\t\DC1\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ACK\ETX\DC2\ETX%\DC4\NAK\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\a\DC2\ETX&\STX,\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\a\EOT\DC2\ETX&\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\a\ACK\DC2\ETX&\v\ETB\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\a\SOH\DC2\ETX&\CAN'\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\a\ETX\DC2\ETX&*+\n\
    \\n\
    \\n\
    \\STX\EOT\EOT\DC2\EOT)\NUL,\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\EOT\SOH\DC2\ETX)\b\DC4\n\
    \\v\n\
    \\EOT\EOT\EOT\STX\NUL\DC2\ETX*\STX\DC1\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\NUL\ENQ\DC2\ETX*\STX\b\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\NUL\SOH\DC2\ETX*\t\f\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\NUL\ETX\DC2\ETX*\SI\DLE\n\
    \\v\n\
    \\EOT\EOT\EOT\STX\SOH\DC2\ETX+\STX\DC3\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\SOH\ENQ\DC2\ETX+\STX\b\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\SOH\SOH\DC2\ETX+\t\SO\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\SOH\ETX\DC2\ETX+\DC1\DC2\n\
    \\n\
    \\n\
    \\STX\EOT\ENQ\DC2\EOT.\NUL3\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\ENQ\SOH\DC2\ETX.\b\SYN\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\NUL\DC2\ETX/\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\NUL\ENQ\DC2\ETX/\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\NUL\SOH\DC2\ETX/\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\NUL\ETX\DC2\ETX/\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\SOH\DC2\ETX0\STX\CAN\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\SOH\ENQ\DC2\ETX0\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\SOH\SOH\DC2\ETX0\t\DC3\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\SOH\ETX\DC2\ETX0\SYN\ETB\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\STX\DC2\ETX1\STX\CAN\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\STX\ENQ\DC2\ETX1\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\STX\SOH\DC2\ETX1\t\DC3\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\STX\ETX\DC2\ETX1\SYN\ETB\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\ETX\DC2\ETX2\STX\SUB\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\ETX\ENQ\DC2\ETX2\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\ETX\SOH\DC2\ETX2\t\NAK\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\ETX\ETX\DC2\ETX2\CAN\EM\n\
    \8\n\
    \\STX\EOT\ACK\DC2\EOT6\NUL;\SOH\SUB, Discriminated union for the command topic.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\ACK\SOH\DC2\ETX6\b\ETB\n\
    \\f\n\
    \\EOT\EOT\ACK\b\NUL\DC2\EOT7\STX:\ETX\n\
    \\f\n\
    \\ENQ\EOT\ACK\b\NUL\SOH\DC2\ETX7\b\f\n\
    \\v\n\
    \\EOT\EOT\ACK\STX\NUL\DC2\ETX8\EOT\FS\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\NUL\ACK\DC2\ETX8\EOT\DC1\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\NUL\SOH\DC2\ETX8\DC2\ETB\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\NUL\ETX\DC2\ETX8\SUB\ESC\n\
    \\v\n\
    \\EOT\EOT\ACK\STX\SOH\DC2\ETX9\EOT\FS\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\SOH\ACK\DC2\ETX9\EOT\DLE\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\SOH\SOH\DC2\ETX9\DC2\SYN\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\SOH\ETX\DC2\ETX9\SUB\ESC\n\
    \6\n\
    \\STX\EOT\a\DC2\EOT>\NULD\SOH\SUB* Discriminated union for the event topic.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\a\SOH\DC2\ETX>\b\NAK\n\
    \\f\n\
    \\EOT\EOT\a\b\NUL\DC2\EOT?\STXC\ETX\n\
    \\f\n\
    \\ENQ\EOT\a\b\NUL\SOH\DC2\ETX?\b\f\n\
    \\v\n\
    \\EOT\EOT\a\STX\NUL\DC2\ETX@\EOT#\n\
    \\f\n\
    \\ENQ\EOT\a\STX\NUL\ACK\DC2\ETX@\EOT\DC2\n\
    \\f\n\
    \\ENQ\EOT\a\STX\NUL\SOH\DC2\ETX@\DC3\CAN\n\
    \\f\n\
    \\ENQ\EOT\a\STX\NUL\ETX\DC2\ETX@!\"\n\
    \\v\n\
    \\EOT\EOT\a\STX\SOH\DC2\ETXA\EOT#\n\
    \\f\n\
    \\ENQ\EOT\a\STX\SOH\ACK\DC2\ETXA\EOT\DC2\n\
    \\f\n\
    \\ENQ\EOT\a\STX\SOH\SOH\DC2\ETXA\DC3\GS\n\
    \\f\n\
    \\ENQ\EOT\a\STX\SOH\ETX\DC2\ETXA!\"\n\
    \\v\n\
    \\EOT\EOT\a\STX\STX\DC2\ETXB\EOT#\n\
    \\f\n\
    \\ENQ\EOT\a\STX\STX\ACK\DC2\ETXB\EOT\DC2\n\
    \\f\n\
    \\ENQ\EOT\a\STX\STX\SOH\DC2\ETXB\DC3\SUB\n\
    \\f\n\
    \\ENQ\EOT\a\STX\STX\ETX\DC2\ETXB!\"b\ACKproto3"