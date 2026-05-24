{- This file was auto-generated from jitml/rl.proto by the proto-lens-protoc program. -}
{-# LANGUAGE ScopedTypeVariables, DataKinds, TypeFamilies, UndecidableInstances, GeneralizedNewtypeDeriving, MultiParamTypeClasses, FlexibleContexts, FlexibleInstances, PatternSynonyms, MagicHash, NoImplicitPrelude, DataKinds, BangPatterns, TypeApplications, OverloadedStrings, DerivingStrategies#-}
{-# OPTIONS_GHC -Wno-unused-imports#-}
{-# OPTIONS_GHC -Wno-duplicate-exports#-}
{-# OPTIONS_GHC -Wno-dodgy-exports#-}
module Proto.Jitml.Rl (
        CheckpointDoneRL(), EpisodeDone(), EvalDone(), MetricUpdate(),
        RlCommand(), RlCommand'Body(..), _RlCommand'Start, _RlCommand'Stop,
        RlEvent(), RlEvent'Body(..), _RlEvent'Episode, _RlEvent'Eval,
        _RlEvent'Checkpoint, _RlEvent'Metric, StartRLRun(), StopRLRun()
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
     
         * 'Proto.Jitml.Rl_Fields.experimentHash' @:: Lens' CheckpointDoneRL Data.Text.Text@
         * 'Proto.Jitml.Rl_Fields.manifestSha' @:: Lens' CheckpointDoneRL Data.Text.Text@
         * 'Proto.Jitml.Rl_Fields.step' @:: Lens' CheckpointDoneRL Data.Word.Word64@
         * 'Proto.Jitml.Rl_Fields.pointerKey' @:: Lens' CheckpointDoneRL Data.Text.Text@ -}
data CheckpointDoneRL
  = CheckpointDoneRL'_constructor {_CheckpointDoneRL'experimentHash :: !Data.Text.Text,
                                   _CheckpointDoneRL'manifestSha :: !Data.Text.Text,
                                   _CheckpointDoneRL'step :: !Data.Word.Word64,
                                   _CheckpointDoneRL'pointerKey :: !Data.Text.Text,
                                   _CheckpointDoneRL'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show CheckpointDoneRL where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField CheckpointDoneRL "experimentHash" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CheckpointDoneRL'experimentHash
           (\ x__ y__ -> x__ {_CheckpointDoneRL'experimentHash = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CheckpointDoneRL "manifestSha" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CheckpointDoneRL'manifestSha
           (\ x__ y__ -> x__ {_CheckpointDoneRL'manifestSha = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CheckpointDoneRL "step" Data.Word.Word64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CheckpointDoneRL'step
           (\ x__ y__ -> x__ {_CheckpointDoneRL'step = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CheckpointDoneRL "pointerKey" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CheckpointDoneRL'pointerKey
           (\ x__ y__ -> x__ {_CheckpointDoneRL'pointerKey = y__}))
        Prelude.id
instance Data.ProtoLens.Message CheckpointDoneRL where
  messageName _ = Data.Text.pack "jitml.rl.CheckpointDoneRL"
  packedMessageDescriptor _
    = "\n\
      \\DLECheckpointDoneRL\DC2'\n\
      \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2!\n\
      \\fmanifest_sha\CAN\STX \SOH(\tR\vmanifestSha\DC2\DC2\n\
      \\EOTstep\CAN\ETX \SOH(\EOTR\EOTstep\DC2\US\n\
      \\vpointer_key\CAN\EOT \SOH(\tR\n\
      \pointerKey"
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
              Data.ProtoLens.FieldDescriptor CheckpointDoneRL
        manifestSha__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "manifest_sha"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"manifestSha")) ::
              Data.ProtoLens.FieldDescriptor CheckpointDoneRL
        step__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "step"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word64)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"step")) ::
              Data.ProtoLens.FieldDescriptor CheckpointDoneRL
        pointerKey__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "pointer_key"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"pointerKey")) ::
              Data.ProtoLens.FieldDescriptor CheckpointDoneRL
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, experimentHash__field_descriptor),
           (Data.ProtoLens.Tag 2, manifestSha__field_descriptor),
           (Data.ProtoLens.Tag 3, step__field_descriptor),
           (Data.ProtoLens.Tag 4, pointerKey__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _CheckpointDoneRL'_unknownFields
        (\ x__ y__ -> x__ {_CheckpointDoneRL'_unknownFields = y__})
  defMessage
    = CheckpointDoneRL'_constructor
        {_CheckpointDoneRL'experimentHash = Data.ProtoLens.fieldDefault,
         _CheckpointDoneRL'manifestSha = Data.ProtoLens.fieldDefault,
         _CheckpointDoneRL'step = Data.ProtoLens.fieldDefault,
         _CheckpointDoneRL'pointerKey = Data.ProtoLens.fieldDefault,
         _CheckpointDoneRL'_unknownFields = []}
  parseMessage
    = let
        loop ::
          CheckpointDoneRL
          -> Data.ProtoLens.Encoding.Bytes.Parser CheckpointDoneRL
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
                                       "manifest_sha"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"manifestSha") y x)
                        24
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       Data.ProtoLens.Encoding.Bytes.getVarInt "step"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"step") y x)
                        34
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "pointer_key"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"pointerKey") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "CheckpointDoneRL"
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
                      (Data.ProtoLens.Encoding.Wire.buildFieldSet
                         (Lens.Family2.view Data.ProtoLens.unknownFields _x)))))
instance Control.DeepSeq.NFData CheckpointDoneRL where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_CheckpointDoneRL'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_CheckpointDoneRL'experimentHash x__)
                (Control.DeepSeq.deepseq
                   (_CheckpointDoneRL'manifestSha x__)
                   (Control.DeepSeq.deepseq
                      (_CheckpointDoneRL'step x__)
                      (Control.DeepSeq.deepseq (_CheckpointDoneRL'pointerKey x__) ()))))
{- | Fields :
     
         * 'Proto.Jitml.Rl_Fields.experimentHash' @:: Lens' EpisodeDone Data.Text.Text@
         * 'Proto.Jitml.Rl_Fields.episode' @:: Lens' EpisodeDone Data.Word.Word32@
         * 'Proto.Jitml.Rl_Fields.reward' @:: Lens' EpisodeDone Prelude.Double@
         * 'Proto.Jitml.Rl_Fields.steps' @:: Lens' EpisodeDone Data.Word.Word32@
         * 'Proto.Jitml.Rl_Fields.timestampNs' @:: Lens' EpisodeDone Data.Word.Word64@ -}
data EpisodeDone
  = EpisodeDone'_constructor {_EpisodeDone'experimentHash :: !Data.Text.Text,
                              _EpisodeDone'episode :: !Data.Word.Word32,
                              _EpisodeDone'reward :: !Prelude.Double,
                              _EpisodeDone'steps :: !Data.Word.Word32,
                              _EpisodeDone'timestampNs :: !Data.Word.Word64,
                              _EpisodeDone'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show EpisodeDone where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField EpisodeDone "experimentHash" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _EpisodeDone'experimentHash
           (\ x__ y__ -> x__ {_EpisodeDone'experimentHash = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField EpisodeDone "episode" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _EpisodeDone'episode
           (\ x__ y__ -> x__ {_EpisodeDone'episode = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField EpisodeDone "reward" Prelude.Double where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _EpisodeDone'reward (\ x__ y__ -> x__ {_EpisodeDone'reward = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField EpisodeDone "steps" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _EpisodeDone'steps (\ x__ y__ -> x__ {_EpisodeDone'steps = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField EpisodeDone "timestampNs" Data.Word.Word64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _EpisodeDone'timestampNs
           (\ x__ y__ -> x__ {_EpisodeDone'timestampNs = y__}))
        Prelude.id
instance Data.ProtoLens.Message EpisodeDone where
  messageName _ = Data.Text.pack "jitml.rl.EpisodeDone"
  packedMessageDescriptor _
    = "\n\
      \\vEpisodeDone\DC2'\n\
      \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2\CAN\n\
      \\aepisode\CAN\STX \SOH(\rR\aepisode\DC2\SYN\n\
      \\ACKreward\CAN\ETX \SOH(\SOHR\ACKreward\DC2\DC4\n\
      \\ENQsteps\CAN\EOT \SOH(\rR\ENQsteps\DC2!\n\
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
              Data.ProtoLens.FieldDescriptor EpisodeDone
        episode__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "episode"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"episode")) ::
              Data.ProtoLens.FieldDescriptor EpisodeDone
        reward__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "reward"
              (Data.ProtoLens.ScalarField Data.ProtoLens.DoubleField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Double)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"reward")) ::
              Data.ProtoLens.FieldDescriptor EpisodeDone
        steps__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "steps"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"steps")) ::
              Data.ProtoLens.FieldDescriptor EpisodeDone
        timestampNs__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "timestamp_ns"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word64)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"timestampNs")) ::
              Data.ProtoLens.FieldDescriptor EpisodeDone
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, experimentHash__field_descriptor),
           (Data.ProtoLens.Tag 2, episode__field_descriptor),
           (Data.ProtoLens.Tag 3, reward__field_descriptor),
           (Data.ProtoLens.Tag 4, steps__field_descriptor),
           (Data.ProtoLens.Tag 5, timestampNs__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _EpisodeDone'_unknownFields
        (\ x__ y__ -> x__ {_EpisodeDone'_unknownFields = y__})
  defMessage
    = EpisodeDone'_constructor
        {_EpisodeDone'experimentHash = Data.ProtoLens.fieldDefault,
         _EpisodeDone'episode = Data.ProtoLens.fieldDefault,
         _EpisodeDone'reward = Data.ProtoLens.fieldDefault,
         _EpisodeDone'steps = Data.ProtoLens.fieldDefault,
         _EpisodeDone'timestampNs = Data.ProtoLens.fieldDefault,
         _EpisodeDone'_unknownFields = []}
  parseMessage
    = let
        loop ::
          EpisodeDone -> Data.ProtoLens.Encoding.Bytes.Parser EpisodeDone
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
                                       "episode"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"episode") y x)
                        25
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Data.ProtoLens.Encoding.Bytes.wordToDouble
                                          Data.ProtoLens.Encoding.Bytes.getFixed64)
                                       "reward"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"reward") y x)
                        32
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "steps"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"steps") y x)
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
          (do loop Data.ProtoLens.defMessage) "EpisodeDone"
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
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"episode") _x
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
                      _v = Lens.Family2.view (Data.ProtoLens.Field.field @"reward") _x
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
                         _v = Lens.Family2.view (Data.ProtoLens.Field.field @"steps") _x
                       in
                         if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                             Data.Monoid.mempty
                         else
                             (Data.Monoid.<>)
                               (Data.ProtoLens.Encoding.Bytes.putVarInt 32)
                               ((Prelude..)
                                  Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
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
instance Control.DeepSeq.NFData EpisodeDone where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_EpisodeDone'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_EpisodeDone'experimentHash x__)
                (Control.DeepSeq.deepseq
                   (_EpisodeDone'episode x__)
                   (Control.DeepSeq.deepseq
                      (_EpisodeDone'reward x__)
                      (Control.DeepSeq.deepseq
                         (_EpisodeDone'steps x__)
                         (Control.DeepSeq.deepseq (_EpisodeDone'timestampNs x__) ())))))
{- | Fields :
     
         * 'Proto.Jitml.Rl_Fields.experimentHash' @:: Lens' EvalDone Data.Text.Text@
         * 'Proto.Jitml.Rl_Fields.epoch' @:: Lens' EvalDone Data.Word.Word32@
         * 'Proto.Jitml.Rl_Fields.avgReward' @:: Lens' EvalDone Prelude.Double@
         * 'Proto.Jitml.Rl_Fields.stdReward' @:: Lens' EvalDone Prelude.Double@
         * 'Proto.Jitml.Rl_Fields.timestampNs' @:: Lens' EvalDone Data.Word.Word64@ -}
data EvalDone
  = EvalDone'_constructor {_EvalDone'experimentHash :: !Data.Text.Text,
                           _EvalDone'epoch :: !Data.Word.Word32,
                           _EvalDone'avgReward :: !Prelude.Double,
                           _EvalDone'stdReward :: !Prelude.Double,
                           _EvalDone'timestampNs :: !Data.Word.Word64,
                           _EvalDone'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show EvalDone where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField EvalDone "experimentHash" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _EvalDone'experimentHash
           (\ x__ y__ -> x__ {_EvalDone'experimentHash = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField EvalDone "epoch" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _EvalDone'epoch (\ x__ y__ -> x__ {_EvalDone'epoch = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField EvalDone "avgReward" Prelude.Double where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _EvalDone'avgReward (\ x__ y__ -> x__ {_EvalDone'avgReward = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField EvalDone "stdReward" Prelude.Double where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _EvalDone'stdReward (\ x__ y__ -> x__ {_EvalDone'stdReward = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField EvalDone "timestampNs" Data.Word.Word64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _EvalDone'timestampNs
           (\ x__ y__ -> x__ {_EvalDone'timestampNs = y__}))
        Prelude.id
instance Data.ProtoLens.Message EvalDone where
  messageName _ = Data.Text.pack "jitml.rl.EvalDone"
  packedMessageDescriptor _
    = "\n\
      \\bEvalDone\DC2'\n\
      \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2\DC4\n\
      \\ENQepoch\CAN\STX \SOH(\rR\ENQepoch\DC2\GS\n\
      \\n\
      \avg_reward\CAN\ETX \SOH(\SOHR\tavgReward\DC2\GS\n\
      \\n\
      \std_reward\CAN\EOT \SOH(\SOHR\tstdReward\DC2!\n\
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
              Data.ProtoLens.FieldDescriptor EvalDone
        epoch__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "epoch"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"epoch")) ::
              Data.ProtoLens.FieldDescriptor EvalDone
        avgReward__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "avg_reward"
              (Data.ProtoLens.ScalarField Data.ProtoLens.DoubleField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Double)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"avgReward")) ::
              Data.ProtoLens.FieldDescriptor EvalDone
        stdReward__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "std_reward"
              (Data.ProtoLens.ScalarField Data.ProtoLens.DoubleField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Double)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"stdReward")) ::
              Data.ProtoLens.FieldDescriptor EvalDone
        timestampNs__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "timestamp_ns"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word64)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"timestampNs")) ::
              Data.ProtoLens.FieldDescriptor EvalDone
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, experimentHash__field_descriptor),
           (Data.ProtoLens.Tag 2, epoch__field_descriptor),
           (Data.ProtoLens.Tag 3, avgReward__field_descriptor),
           (Data.ProtoLens.Tag 4, stdReward__field_descriptor),
           (Data.ProtoLens.Tag 5, timestampNs__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _EvalDone'_unknownFields
        (\ x__ y__ -> x__ {_EvalDone'_unknownFields = y__})
  defMessage
    = EvalDone'_constructor
        {_EvalDone'experimentHash = Data.ProtoLens.fieldDefault,
         _EvalDone'epoch = Data.ProtoLens.fieldDefault,
         _EvalDone'avgReward = Data.ProtoLens.fieldDefault,
         _EvalDone'stdReward = Data.ProtoLens.fieldDefault,
         _EvalDone'timestampNs = Data.ProtoLens.fieldDefault,
         _EvalDone'_unknownFields = []}
  parseMessage
    = let
        loop :: EvalDone -> Data.ProtoLens.Encoding.Bytes.Parser EvalDone
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
                                       "avg_reward"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"avgReward") y x)
                        33
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Data.ProtoLens.Encoding.Bytes.wordToDouble
                                          Data.ProtoLens.Encoding.Bytes.getFixed64)
                                       "std_reward"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"stdReward") y x)
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
          (do loop Data.ProtoLens.defMessage) "EvalDone"
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
                   (let
                      _v = Lens.Family2.view (Data.ProtoLens.Field.field @"avgReward") _x
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
                         _v = Lens.Family2.view (Data.ProtoLens.Field.field @"stdReward") _x
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
instance Control.DeepSeq.NFData EvalDone where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_EvalDone'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_EvalDone'experimentHash x__)
                (Control.DeepSeq.deepseq
                   (_EvalDone'epoch x__)
                   (Control.DeepSeq.deepseq
                      (_EvalDone'avgReward x__)
                      (Control.DeepSeq.deepseq
                         (_EvalDone'stdReward x__)
                         (Control.DeepSeq.deepseq (_EvalDone'timestampNs x__) ())))))
{- | Fields :
     
         * 'Proto.Jitml.Rl_Fields.experimentHash' @:: Lens' MetricUpdate Data.Text.Text@
         * 'Proto.Jitml.Rl_Fields.name' @:: Lens' MetricUpdate Data.Text.Text@
         * 'Proto.Jitml.Rl_Fields.value' @:: Lens' MetricUpdate Prelude.Double@
         * 'Proto.Jitml.Rl_Fields.timestampNs' @:: Lens' MetricUpdate Data.Word.Word64@ -}
data MetricUpdate
  = MetricUpdate'_constructor {_MetricUpdate'experimentHash :: !Data.Text.Text,
                               _MetricUpdate'name :: !Data.Text.Text,
                               _MetricUpdate'value :: !Prelude.Double,
                               _MetricUpdate'timestampNs :: !Data.Word.Word64,
                               _MetricUpdate'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show MetricUpdate where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField MetricUpdate "experimentHash" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _MetricUpdate'experimentHash
           (\ x__ y__ -> x__ {_MetricUpdate'experimentHash = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField MetricUpdate "name" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _MetricUpdate'name (\ x__ y__ -> x__ {_MetricUpdate'name = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField MetricUpdate "value" Prelude.Double where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _MetricUpdate'value (\ x__ y__ -> x__ {_MetricUpdate'value = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField MetricUpdate "timestampNs" Data.Word.Word64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _MetricUpdate'timestampNs
           (\ x__ y__ -> x__ {_MetricUpdate'timestampNs = y__}))
        Prelude.id
instance Data.ProtoLens.Message MetricUpdate where
  messageName _ = Data.Text.pack "jitml.rl.MetricUpdate"
  packedMessageDescriptor _
    = "\n\
      \\fMetricUpdate\DC2'\n\
      \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2\DC2\n\
      \\EOTname\CAN\STX \SOH(\tR\EOTname\DC2\DC4\n\
      \\ENQvalue\CAN\ETX \SOH(\SOHR\ENQvalue\DC2!\n\
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
              Data.ProtoLens.FieldDescriptor MetricUpdate
        name__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "name"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"name")) ::
              Data.ProtoLens.FieldDescriptor MetricUpdate
        value__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "value"
              (Data.ProtoLens.ScalarField Data.ProtoLens.DoubleField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Double)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"value")) ::
              Data.ProtoLens.FieldDescriptor MetricUpdate
        timestampNs__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "timestamp_ns"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word64)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"timestampNs")) ::
              Data.ProtoLens.FieldDescriptor MetricUpdate
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, experimentHash__field_descriptor),
           (Data.ProtoLens.Tag 2, name__field_descriptor),
           (Data.ProtoLens.Tag 3, value__field_descriptor),
           (Data.ProtoLens.Tag 4, timestampNs__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _MetricUpdate'_unknownFields
        (\ x__ y__ -> x__ {_MetricUpdate'_unknownFields = y__})
  defMessage
    = MetricUpdate'_constructor
        {_MetricUpdate'experimentHash = Data.ProtoLens.fieldDefault,
         _MetricUpdate'name = Data.ProtoLens.fieldDefault,
         _MetricUpdate'value = Data.ProtoLens.fieldDefault,
         _MetricUpdate'timestampNs = Data.ProtoLens.fieldDefault,
         _MetricUpdate'_unknownFields = []}
  parseMessage
    = let
        loop ::
          MetricUpdate -> Data.ProtoLens.Encoding.Bytes.Parser MetricUpdate
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
                                       "name"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"name") y x)
                        25
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Data.ProtoLens.Encoding.Bytes.wordToDouble
                                          Data.ProtoLens.Encoding.Bytes.getFixed64)
                                       "value"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"value") y x)
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
          (do loop Data.ProtoLens.defMessage) "MetricUpdate"
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
                (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"name") _x
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
                      _v = Lens.Family2.view (Data.ProtoLens.Field.field @"value") _x
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
instance Control.DeepSeq.NFData MetricUpdate where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_MetricUpdate'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_MetricUpdate'experimentHash x__)
                (Control.DeepSeq.deepseq
                   (_MetricUpdate'name x__)
                   (Control.DeepSeq.deepseq
                      (_MetricUpdate'value x__)
                      (Control.DeepSeq.deepseq (_MetricUpdate'timestampNs x__) ()))))
{- | Fields :
     
         * 'Proto.Jitml.Rl_Fields.maybe'body' @:: Lens' RlCommand (Prelude.Maybe RlCommand'Body)@
         * 'Proto.Jitml.Rl_Fields.maybe'start' @:: Lens' RlCommand (Prelude.Maybe StartRLRun)@
         * 'Proto.Jitml.Rl_Fields.start' @:: Lens' RlCommand StartRLRun@
         * 'Proto.Jitml.Rl_Fields.maybe'stop' @:: Lens' RlCommand (Prelude.Maybe StopRLRun)@
         * 'Proto.Jitml.Rl_Fields.stop' @:: Lens' RlCommand StopRLRun@ -}
data RlCommand
  = RlCommand'_constructor {_RlCommand'body :: !(Prelude.Maybe RlCommand'Body),
                            _RlCommand'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show RlCommand where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
data RlCommand'Body
  = RlCommand'Start !StartRLRun | RlCommand'Stop !StopRLRun
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.Field.HasField RlCommand "maybe'body" (Prelude.Maybe RlCommand'Body) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlCommand'body (\ x__ y__ -> x__ {_RlCommand'body = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RlCommand "maybe'start" (Prelude.Maybe StartRLRun) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlCommand'body (\ x__ y__ -> x__ {_RlCommand'body = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (RlCommand'Start x__val)) -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap RlCommand'Start y__))
instance Data.ProtoLens.Field.HasField RlCommand "start" StartRLRun where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlCommand'body (\ x__ y__ -> x__ {_RlCommand'body = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (RlCommand'Start x__val)) -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap RlCommand'Start y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField RlCommand "maybe'stop" (Prelude.Maybe StopRLRun) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlCommand'body (\ x__ y__ -> x__ {_RlCommand'body = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (RlCommand'Stop x__val)) -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap RlCommand'Stop y__))
instance Data.ProtoLens.Field.HasField RlCommand "stop" StopRLRun where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlCommand'body (\ x__ y__ -> x__ {_RlCommand'body = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (RlCommand'Stop x__val)) -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap RlCommand'Stop y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Message RlCommand where
  messageName _ = Data.Text.pack "jitml.rl.RlCommand"
  packedMessageDescriptor _
    = "\n\
      \\tRlCommand\DC2,\n\
      \\ENQstart\CAN\SOH \SOH(\v2\DC4.jitml.rl.StartRLRunH\NULR\ENQstart\DC2)\n\
      \\EOTstop\CAN\STX \SOH(\v2\DC3.jitml.rl.StopRLRunH\NULR\EOTstopB\ACK\n\
      \\EOTbody"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        start__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "start"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor StartRLRun)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'start")) ::
              Data.ProtoLens.FieldDescriptor RlCommand
        stop__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "stop"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor StopRLRun)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'stop")) ::
              Data.ProtoLens.FieldDescriptor RlCommand
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, start__field_descriptor),
           (Data.ProtoLens.Tag 2, stop__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _RlCommand'_unknownFields
        (\ x__ y__ -> x__ {_RlCommand'_unknownFields = y__})
  defMessage
    = RlCommand'_constructor
        {_RlCommand'body = Prelude.Nothing, _RlCommand'_unknownFields = []}
  parseMessage
    = let
        loop :: RlCommand -> Data.ProtoLens.Encoding.Bytes.Parser RlCommand
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
          (do loop Data.ProtoLens.defMessage) "RlCommand"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (case
                  Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'body") _x
              of
                Prelude.Nothing -> Data.Monoid.mempty
                (Prelude.Just (RlCommand'Start v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v)
                (Prelude.Just (RlCommand'Stop v))
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
instance Control.DeepSeq.NFData RlCommand where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_RlCommand'_unknownFields x__)
             (Control.DeepSeq.deepseq (_RlCommand'body x__) ())
instance Control.DeepSeq.NFData RlCommand'Body where
  rnf (RlCommand'Start x__) = Control.DeepSeq.rnf x__
  rnf (RlCommand'Stop x__) = Control.DeepSeq.rnf x__
_RlCommand'Start ::
  Data.ProtoLens.Prism.Prism' RlCommand'Body StartRLRun
_RlCommand'Start
  = Data.ProtoLens.Prism.prism'
      RlCommand'Start
      (\ p__
         -> case p__ of
              (RlCommand'Start p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_RlCommand'Stop ::
  Data.ProtoLens.Prism.Prism' RlCommand'Body StopRLRun
_RlCommand'Stop
  = Data.ProtoLens.Prism.prism'
      RlCommand'Stop
      (\ p__
         -> case p__ of
              (RlCommand'Stop p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
{- | Fields :
     
         * 'Proto.Jitml.Rl_Fields.maybe'body' @:: Lens' RlEvent (Prelude.Maybe RlEvent'Body)@
         * 'Proto.Jitml.Rl_Fields.maybe'episode' @:: Lens' RlEvent (Prelude.Maybe EpisodeDone)@
         * 'Proto.Jitml.Rl_Fields.episode' @:: Lens' RlEvent EpisodeDone@
         * 'Proto.Jitml.Rl_Fields.maybe'eval' @:: Lens' RlEvent (Prelude.Maybe EvalDone)@
         * 'Proto.Jitml.Rl_Fields.eval' @:: Lens' RlEvent EvalDone@
         * 'Proto.Jitml.Rl_Fields.maybe'checkpoint' @:: Lens' RlEvent (Prelude.Maybe CheckpointDoneRL)@
         * 'Proto.Jitml.Rl_Fields.checkpoint' @:: Lens' RlEvent CheckpointDoneRL@
         * 'Proto.Jitml.Rl_Fields.maybe'metric' @:: Lens' RlEvent (Prelude.Maybe MetricUpdate)@
         * 'Proto.Jitml.Rl_Fields.metric' @:: Lens' RlEvent MetricUpdate@ -}
data RlEvent
  = RlEvent'_constructor {_RlEvent'body :: !(Prelude.Maybe RlEvent'Body),
                          _RlEvent'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show RlEvent where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
data RlEvent'Body
  = RlEvent'Episode !EpisodeDone |
    RlEvent'Eval !EvalDone |
    RlEvent'Checkpoint !CheckpointDoneRL |
    RlEvent'Metric !MetricUpdate
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.Field.HasField RlEvent "maybe'body" (Prelude.Maybe RlEvent'Body) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlEvent'body (\ x__ y__ -> x__ {_RlEvent'body = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RlEvent "maybe'episode" (Prelude.Maybe EpisodeDone) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlEvent'body (\ x__ y__ -> x__ {_RlEvent'body = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (RlEvent'Episode x__val)) -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap RlEvent'Episode y__))
instance Data.ProtoLens.Field.HasField RlEvent "episode" EpisodeDone where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlEvent'body (\ x__ y__ -> x__ {_RlEvent'body = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (RlEvent'Episode x__val)) -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap RlEvent'Episode y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField RlEvent "maybe'eval" (Prelude.Maybe EvalDone) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlEvent'body (\ x__ y__ -> x__ {_RlEvent'body = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (RlEvent'Eval x__val)) -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap RlEvent'Eval y__))
instance Data.ProtoLens.Field.HasField RlEvent "eval" EvalDone where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlEvent'body (\ x__ y__ -> x__ {_RlEvent'body = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (RlEvent'Eval x__val)) -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap RlEvent'Eval y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField RlEvent "maybe'checkpoint" (Prelude.Maybe CheckpointDoneRL) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlEvent'body (\ x__ y__ -> x__ {_RlEvent'body = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (RlEvent'Checkpoint x__val)) -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap RlEvent'Checkpoint y__))
instance Data.ProtoLens.Field.HasField RlEvent "checkpoint" CheckpointDoneRL where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlEvent'body (\ x__ y__ -> x__ {_RlEvent'body = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (RlEvent'Checkpoint x__val)) -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap RlEvent'Checkpoint y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField RlEvent "maybe'metric" (Prelude.Maybe MetricUpdate) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlEvent'body (\ x__ y__ -> x__ {_RlEvent'body = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (RlEvent'Metric x__val)) -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap RlEvent'Metric y__))
instance Data.ProtoLens.Field.HasField RlEvent "metric" MetricUpdate where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlEvent'body (\ x__ y__ -> x__ {_RlEvent'body = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (RlEvent'Metric x__val)) -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap RlEvent'Metric y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Message RlEvent where
  messageName _ = Data.Text.pack "jitml.rl.RlEvent"
  packedMessageDescriptor _
    = "\n\
      \\aRlEvent\DC21\n\
      \\aepisode\CAN\SOH \SOH(\v2\NAK.jitml.rl.EpisodeDoneH\NULR\aepisode\DC2(\n\
      \\EOTeval\CAN\STX \SOH(\v2\DC2.jitml.rl.EvalDoneH\NULR\EOTeval\DC2<\n\
      \\n\
      \checkpoint\CAN\ETX \SOH(\v2\SUB.jitml.rl.CheckpointDoneRLH\NULR\n\
      \checkpoint\DC20\n\
      \\ACKmetric\CAN\EOT \SOH(\v2\SYN.jitml.rl.MetricUpdateH\NULR\ACKmetricB\ACK\n\
      \\EOTbody"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        episode__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "episode"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor EpisodeDone)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'episode")) ::
              Data.ProtoLens.FieldDescriptor RlEvent
        eval__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "eval"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor EvalDone)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'eval")) ::
              Data.ProtoLens.FieldDescriptor RlEvent
        checkpoint__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "checkpoint"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor CheckpointDoneRL)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'checkpoint")) ::
              Data.ProtoLens.FieldDescriptor RlEvent
        metric__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "metric"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor MetricUpdate)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'metric")) ::
              Data.ProtoLens.FieldDescriptor RlEvent
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, episode__field_descriptor),
           (Data.ProtoLens.Tag 2, eval__field_descriptor),
           (Data.ProtoLens.Tag 3, checkpoint__field_descriptor),
           (Data.ProtoLens.Tag 4, metric__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _RlEvent'_unknownFields
        (\ x__ y__ -> x__ {_RlEvent'_unknownFields = y__})
  defMessage
    = RlEvent'_constructor
        {_RlEvent'body = Prelude.Nothing, _RlEvent'_unknownFields = []}
  parseMessage
    = let
        loop :: RlEvent -> Data.ProtoLens.Encoding.Bytes.Parser RlEvent
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
                                       "episode"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"episode") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "eval"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"eval") y x)
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "checkpoint"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"checkpoint") y x)
                        34
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "metric"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"metric") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "RlEvent"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (case
                  Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'body") _x
              of
                Prelude.Nothing -> Data.Monoid.mempty
                (Prelude.Just (RlEvent'Episode v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v)
                (Prelude.Just (RlEvent'Eval v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v)
                (Prelude.Just (RlEvent'Checkpoint v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 26)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v)
                (Prelude.Just (RlEvent'Metric v))
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
instance Control.DeepSeq.NFData RlEvent where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_RlEvent'_unknownFields x__)
             (Control.DeepSeq.deepseq (_RlEvent'body x__) ())
instance Control.DeepSeq.NFData RlEvent'Body where
  rnf (RlEvent'Episode x__) = Control.DeepSeq.rnf x__
  rnf (RlEvent'Eval x__) = Control.DeepSeq.rnf x__
  rnf (RlEvent'Checkpoint x__) = Control.DeepSeq.rnf x__
  rnf (RlEvent'Metric x__) = Control.DeepSeq.rnf x__
_RlEvent'Episode ::
  Data.ProtoLens.Prism.Prism' RlEvent'Body EpisodeDone
_RlEvent'Episode
  = Data.ProtoLens.Prism.prism'
      RlEvent'Episode
      (\ p__
         -> case p__ of
              (RlEvent'Episode p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_RlEvent'Eval :: Data.ProtoLens.Prism.Prism' RlEvent'Body EvalDone
_RlEvent'Eval
  = Data.ProtoLens.Prism.prism'
      RlEvent'Eval
      (\ p__
         -> case p__ of
              (RlEvent'Eval p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_RlEvent'Checkpoint ::
  Data.ProtoLens.Prism.Prism' RlEvent'Body CheckpointDoneRL
_RlEvent'Checkpoint
  = Data.ProtoLens.Prism.prism'
      RlEvent'Checkpoint
      (\ p__
         -> case p__ of
              (RlEvent'Checkpoint p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_RlEvent'Metric ::
  Data.ProtoLens.Prism.Prism' RlEvent'Body MetricUpdate
_RlEvent'Metric
  = Data.ProtoLens.Prism.prism'
      RlEvent'Metric
      (\ p__
         -> case p__ of
              (RlEvent'Metric p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
{- | Fields :
     
         * 'Proto.Jitml.Rl_Fields.experimentHash' @:: Lens' StartRLRun Data.Text.Text@
         * 'Proto.Jitml.Rl_Fields.algorithm' @:: Lens' StartRLRun Data.Text.Text@
         * 'Proto.Jitml.Rl_Fields.environment' @:: Lens' StartRLRun Data.Text.Text@
         * 'Proto.Jitml.Rl_Fields.substrate' @:: Lens' StartRLRun Data.Text.Text@
         * 'Proto.Jitml.Rl_Fields.seed' @:: Lens' StartRLRun Data.Word.Word64@
         * 'Proto.Jitml.Rl_Fields.maxSteps' @:: Lens' StartRLRun Data.Word.Word32@
         * 'Proto.Jitml.Rl_Fields.evalEpisodes' @:: Lens' StartRLRun Data.Word.Word32@ -}
data StartRLRun
  = StartRLRun'_constructor {_StartRLRun'experimentHash :: !Data.Text.Text,
                             _StartRLRun'algorithm :: !Data.Text.Text,
                             _StartRLRun'environment :: !Data.Text.Text,
                             _StartRLRun'substrate :: !Data.Text.Text,
                             _StartRLRun'seed :: !Data.Word.Word64,
                             _StartRLRun'maxSteps :: !Data.Word.Word32,
                             _StartRLRun'evalEpisodes :: !Data.Word.Word32,
                             _StartRLRun'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show StartRLRun where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField StartRLRun "experimentHash" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartRLRun'experimentHash
           (\ x__ y__ -> x__ {_StartRLRun'experimentHash = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField StartRLRun "algorithm" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartRLRun'algorithm
           (\ x__ y__ -> x__ {_StartRLRun'algorithm = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField StartRLRun "environment" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartRLRun'environment
           (\ x__ y__ -> x__ {_StartRLRun'environment = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField StartRLRun "substrate" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartRLRun'substrate
           (\ x__ y__ -> x__ {_StartRLRun'substrate = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField StartRLRun "seed" Data.Word.Word64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartRLRun'seed (\ x__ y__ -> x__ {_StartRLRun'seed = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField StartRLRun "maxSteps" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartRLRun'maxSteps
           (\ x__ y__ -> x__ {_StartRLRun'maxSteps = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField StartRLRun "evalEpisodes" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartRLRun'evalEpisodes
           (\ x__ y__ -> x__ {_StartRLRun'evalEpisodes = y__}))
        Prelude.id
instance Data.ProtoLens.Message StartRLRun where
  messageName _ = Data.Text.pack "jitml.rl.StartRLRun"
  packedMessageDescriptor _
    = "\n\
      \\n\
      \StartRLRun\DC2'\n\
      \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2\FS\n\
      \\talgorithm\CAN\STX \SOH(\tR\talgorithm\DC2 \n\
      \\venvironment\CAN\ETX \SOH(\tR\venvironment\DC2\FS\n\
      \\tsubstrate\CAN\EOT \SOH(\tR\tsubstrate\DC2\DC2\n\
      \\EOTseed\CAN\ENQ \SOH(\EOTR\EOTseed\DC2\ESC\n\
      \\tmax_steps\CAN\ACK \SOH(\rR\bmaxSteps\DC2#\n\
      \\reval_episodes\CAN\a \SOH(\rR\fevalEpisodes"
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
              Data.ProtoLens.FieldDescriptor StartRLRun
        algorithm__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "algorithm"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"algorithm")) ::
              Data.ProtoLens.FieldDescriptor StartRLRun
        environment__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "environment"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"environment")) ::
              Data.ProtoLens.FieldDescriptor StartRLRun
        substrate__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "substrate"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"substrate")) ::
              Data.ProtoLens.FieldDescriptor StartRLRun
        seed__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "seed"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word64)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"seed")) ::
              Data.ProtoLens.FieldDescriptor StartRLRun
        maxSteps__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "max_steps"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"maxSteps")) ::
              Data.ProtoLens.FieldDescriptor StartRLRun
        evalEpisodes__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "eval_episodes"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"evalEpisodes")) ::
              Data.ProtoLens.FieldDescriptor StartRLRun
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, experimentHash__field_descriptor),
           (Data.ProtoLens.Tag 2, algorithm__field_descriptor),
           (Data.ProtoLens.Tag 3, environment__field_descriptor),
           (Data.ProtoLens.Tag 4, substrate__field_descriptor),
           (Data.ProtoLens.Tag 5, seed__field_descriptor),
           (Data.ProtoLens.Tag 6, maxSteps__field_descriptor),
           (Data.ProtoLens.Tag 7, evalEpisodes__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _StartRLRun'_unknownFields
        (\ x__ y__ -> x__ {_StartRLRun'_unknownFields = y__})
  defMessage
    = StartRLRun'_constructor
        {_StartRLRun'experimentHash = Data.ProtoLens.fieldDefault,
         _StartRLRun'algorithm = Data.ProtoLens.fieldDefault,
         _StartRLRun'environment = Data.ProtoLens.fieldDefault,
         _StartRLRun'substrate = Data.ProtoLens.fieldDefault,
         _StartRLRun'seed = Data.ProtoLens.fieldDefault,
         _StartRLRun'maxSteps = Data.ProtoLens.fieldDefault,
         _StartRLRun'evalEpisodes = Data.ProtoLens.fieldDefault,
         _StartRLRun'_unknownFields = []}
  parseMessage
    = let
        loop ::
          StartRLRun -> Data.ProtoLens.Encoding.Bytes.Parser StartRLRun
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
                                       "algorithm"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"algorithm") y x)
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "environment"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"environment") y x)
                        34
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "substrate"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"substrate") y x)
                        40
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       Data.ProtoLens.Encoding.Bytes.getVarInt "seed"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"seed") y x)
                        48
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "max_steps"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"maxSteps") y x)
                        56
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "eval_episodes"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"evalEpisodes") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "StartRLRun"
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
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"algorithm") _x
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
                      _v
                        = Lens.Family2.view (Data.ProtoLens.Field.field @"environment") _x
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
                         _v = Lens.Family2.view (Data.ProtoLens.Field.field @"substrate") _x
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
                         (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"seed") _x
                          in
                            if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                Data.Monoid.mempty
                            else
                                (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt 40)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt _v))
                         ((Data.Monoid.<>)
                            (let
                               _v = Lens.Family2.view (Data.ProtoLens.Field.field @"maxSteps") _x
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
                                  _v
                                    = Lens.Family2.view
                                        (Data.ProtoLens.Field.field @"evalEpisodes") _x
                                in
                                  if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                      Data.Monoid.mempty
                                  else
                                      (Data.Monoid.<>)
                                        (Data.ProtoLens.Encoding.Bytes.putVarInt 56)
                                        ((Prelude..)
                                           Data.ProtoLens.Encoding.Bytes.putVarInt
                                           Prelude.fromIntegral _v))
                               (Data.ProtoLens.Encoding.Wire.buildFieldSet
                                  (Lens.Family2.view Data.ProtoLens.unknownFields _x))))))))
instance Control.DeepSeq.NFData StartRLRun where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_StartRLRun'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_StartRLRun'experimentHash x__)
                (Control.DeepSeq.deepseq
                   (_StartRLRun'algorithm x__)
                   (Control.DeepSeq.deepseq
                      (_StartRLRun'environment x__)
                      (Control.DeepSeq.deepseq
                         (_StartRLRun'substrate x__)
                         (Control.DeepSeq.deepseq
                            (_StartRLRun'seed x__)
                            (Control.DeepSeq.deepseq
                               (_StartRLRun'maxSteps x__)
                               (Control.DeepSeq.deepseq (_StartRLRun'evalEpisodes x__) ())))))))
{- | Fields :
     
         * 'Proto.Jitml.Rl_Fields.experimentHash' @:: Lens' StopRLRun Data.Text.Text@
         * 'Proto.Jitml.Rl_Fields.drain' @:: Lens' StopRLRun Prelude.Bool@ -}
data StopRLRun
  = StopRLRun'_constructor {_StopRLRun'experimentHash :: !Data.Text.Text,
                            _StopRLRun'drain :: !Prelude.Bool,
                            _StopRLRun'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show StopRLRun where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField StopRLRun "experimentHash" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StopRLRun'experimentHash
           (\ x__ y__ -> x__ {_StopRLRun'experimentHash = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField StopRLRun "drain" Prelude.Bool where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StopRLRun'drain (\ x__ y__ -> x__ {_StopRLRun'drain = y__}))
        Prelude.id
instance Data.ProtoLens.Message StopRLRun where
  messageName _ = Data.Text.pack "jitml.rl.StopRLRun"
  packedMessageDescriptor _
    = "\n\
      \\tStopRLRun\DC2'\n\
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
              Data.ProtoLens.FieldDescriptor StopRLRun
        drain__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "drain"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BoolField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Bool)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"drain")) ::
              Data.ProtoLens.FieldDescriptor StopRLRun
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, experimentHash__field_descriptor),
           (Data.ProtoLens.Tag 2, drain__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _StopRLRun'_unknownFields
        (\ x__ y__ -> x__ {_StopRLRun'_unknownFields = y__})
  defMessage
    = StopRLRun'_constructor
        {_StopRLRun'experimentHash = Data.ProtoLens.fieldDefault,
         _StopRLRun'drain = Data.ProtoLens.fieldDefault,
         _StopRLRun'_unknownFields = []}
  parseMessage
    = let
        loop :: StopRLRun -> Data.ProtoLens.Encoding.Bytes.Parser StopRLRun
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
          (do loop Data.ProtoLens.defMessage) "StopRLRun"
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
instance Control.DeepSeq.NFData StopRLRun where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_StopRLRun'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_StopRLRun'experimentHash x__)
                (Control.DeepSeq.deepseq (_StopRLRun'drain x__) ()))
packedFileDescriptor :: Data.ByteString.ByteString
packedFileDescriptor
  = "\n\
    \\SOjitml/rl.proto\DC2\bjitml.rl\"\233\SOH\n\
    \\n\
    \StartRLRun\DC2'\n\
    \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2\FS\n\
    \\talgorithm\CAN\STX \SOH(\tR\talgorithm\DC2 \n\
    \\venvironment\CAN\ETX \SOH(\tR\venvironment\DC2\FS\n\
    \\tsubstrate\CAN\EOT \SOH(\tR\tsubstrate\DC2\DC2\n\
    \\EOTseed\CAN\ENQ \SOH(\EOTR\EOTseed\DC2\ESC\n\
    \\tmax_steps\CAN\ACK \SOH(\rR\bmaxSteps\DC2#\n\
    \\reval_episodes\CAN\a \SOH(\rR\fevalEpisodes\"J\n\
    \\tStopRLRun\DC2'\n\
    \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2\DC4\n\
    \\ENQdrain\CAN\STX \SOH(\bR\ENQdrain\"\161\SOH\n\
    \\vEpisodeDone\DC2'\n\
    \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2\CAN\n\
    \\aepisode\CAN\STX \SOH(\rR\aepisode\DC2\SYN\n\
    \\ACKreward\CAN\ETX \SOH(\SOHR\ACKreward\DC2\DC4\n\
    \\ENQsteps\CAN\EOT \SOH(\rR\ENQsteps\DC2!\n\
    \\ftimestamp_ns\CAN\ENQ \SOH(\EOTR\vtimestampNs\"\170\SOH\n\
    \\bEvalDone\DC2'\n\
    \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2\DC4\n\
    \\ENQepoch\CAN\STX \SOH(\rR\ENQepoch\DC2\GS\n\
    \\n\
    \avg_reward\CAN\ETX \SOH(\SOHR\tavgReward\DC2\GS\n\
    \\n\
    \std_reward\CAN\EOT \SOH(\SOHR\tstdReward\DC2!\n\
    \\ftimestamp_ns\CAN\ENQ \SOH(\EOTR\vtimestampNs\"\147\SOH\n\
    \\DLECheckpointDoneRL\DC2'\n\
    \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2!\n\
    \\fmanifest_sha\CAN\STX \SOH(\tR\vmanifestSha\DC2\DC2\n\
    \\EOTstep\CAN\ETX \SOH(\EOTR\EOTstep\DC2\US\n\
    \\vpointer_key\CAN\EOT \SOH(\tR\n\
    \pointerKey\"\132\SOH\n\
    \\fMetricUpdate\DC2'\n\
    \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2\DC2\n\
    \\EOTname\CAN\STX \SOH(\tR\EOTname\DC2\DC4\n\
    \\ENQvalue\CAN\ETX \SOH(\SOHR\ENQvalue\DC2!\n\
    \\ftimestamp_ns\CAN\EOT \SOH(\EOTR\vtimestampNs\"l\n\
    \\tRlCommand\DC2,\n\
    \\ENQstart\CAN\SOH \SOH(\v2\DC4.jitml.rl.StartRLRunH\NULR\ENQstart\DC2)\n\
    \\EOTstop\CAN\STX \SOH(\v2\DC3.jitml.rl.StopRLRunH\NULR\EOTstopB\ACK\n\
    \\EOTbody\"\222\SOH\n\
    \\aRlEvent\DC21\n\
    \\aepisode\CAN\SOH \SOH(\v2\NAK.jitml.rl.EpisodeDoneH\NULR\aepisode\DC2(\n\
    \\EOTeval\CAN\STX \SOH(\v2\DC2.jitml.rl.EvalDoneH\NULR\EOTeval\DC2<\n\
    \\n\
    \checkpoint\CAN\ETX \SOH(\v2\SUB.jitml.rl.CheckpointDoneRLH\NULR\n\
    \checkpoint\DC20\n\
    \\ACKmetric\CAN\EOT \SOH(\v2\SYN.jitml.rl.MetricUpdateH\NULR\ACKmetricB\ACK\n\
    \\EOTbodyJ\190\DC1\n\
    \\ACK\DC2\EOT\NUL\NULA\SOH\n\
    \\b\n\
    \\SOH\f\DC2\ETX\NUL\NUL\DC2\n\
    \\b\n\
    \\SOH\STX\DC2\ETX\STX\NUL\DC1\n\
    \b\n\
    \\STX\EOT\NUL\DC2\EOT\ACK\NUL\SO\SOH\SUBV Envelope sent on `rl.command.<mode>` to drive an RL run via the daemon's\n\
    \ RlHandler.\n\
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
    \'\n\
    \\EOT\EOT\NUL\STX\SOH\DC2\ETX\b\STX\GS\"\SUB PPO, DQN, AlphaZero, ...\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\ENQ\DC2\ETX\b\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\SOH\DC2\ETX\b\t\DC2\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\ETX\DC2\ETX\b\ESC\FS\n\
    \*\n\
    \\EOT\EOT\NUL\STX\STX\DC2\ETX\t\STX\GS\"\GS cartpole, mountain-car, ...\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\STX\ENQ\DC2\ETX\t\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\STX\SOH\DC2\ETX\t\t\DC4\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\STX\ETX\DC2\ETX\t\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\NUL\STX\ETX\DC2\ETX\n\
    \\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ETX\ENQ\DC2\ETX\n\
    \\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ETX\SOH\DC2\ETX\n\
    \\t\DC2\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ETX\ETX\DC2\ETX\n\
    \\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\NUL\STX\EOT\DC2\ETX\v\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\EOT\ENQ\DC2\ETX\v\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\EOT\SOH\DC2\ETX\v\t\r\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\EOT\ETX\DC2\ETX\v\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\NUL\STX\ENQ\DC2\ETX\f\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ENQ\ENQ\DC2\ETX\f\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ENQ\SOH\DC2\ETX\f\t\DC2\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ENQ\ETX\DC2\ETX\f\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\NUL\STX\ACK\DC2\ETX\r\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ACK\ENQ\DC2\ETX\r\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ACK\SOH\DC2\ETX\r\t\SYN\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ACK\ETX\DC2\ETX\r\ESC\FS\n\
    \\n\
    \\n\
    \\STX\EOT\SOH\DC2\EOT\DLE\NUL\DC3\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\SOH\SOH\DC2\ETX\DLE\b\DC1\n\
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
    \\n\
    \\n\
    \\STX\EOT\STX\DC2\EOT\NAK\NUL\ESC\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\STX\SOH\DC2\ETX\NAK\b\DC3\n\
    \\v\n\
    \\EOT\EOT\STX\STX\NUL\DC2\ETX\SYN\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\NUL\ENQ\DC2\ETX\SYN\STX\b\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\NUL\SOH\DC2\ETX\SYN\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\NUL\ETX\DC2\ETX\SYN\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\STX\STX\SOH\DC2\ETX\ETB\STX\NAK\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\SOH\ENQ\DC2\ETX\ETB\STX\b\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\SOH\SOH\DC2\ETX\ETB\t\DLE\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\SOH\ETX\DC2\ETX\ETB\DC3\DC4\n\
    \\v\n\
    \\EOT\EOT\STX\STX\STX\DC2\ETX\CAN\STX\DC4\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\STX\ENQ\DC2\ETX\CAN\STX\b\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\STX\SOH\DC2\ETX\CAN\t\SI\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\STX\ETX\DC2\ETX\CAN\DC2\DC3\n\
    \\v\n\
    \\EOT\EOT\STX\STX\ETX\DC2\ETX\EM\STX\DC3\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\ETX\ENQ\DC2\ETX\EM\STX\b\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\ETX\SOH\DC2\ETX\EM\t\SO\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\ETX\ETX\DC2\ETX\EM\DC1\DC2\n\
    \\v\n\
    \\EOT\EOT\STX\STX\EOT\DC2\ETX\SUB\STX\SUB\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\EOT\ENQ\DC2\ETX\SUB\STX\b\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\EOT\SOH\DC2\ETX\SUB\t\NAK\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\EOT\ETX\DC2\ETX\SUB\CAN\EM\n\
    \\n\
    \\n\
    \\STX\EOT\ETX\DC2\EOT\GS\NUL#\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\ETX\SOH\DC2\ETX\GS\b\DLE\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\NUL\DC2\ETX\RS\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\NUL\ENQ\DC2\ETX\RS\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\NUL\SOH\DC2\ETX\RS\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\NUL\ETX\DC2\ETX\RS\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\SOH\DC2\ETX\US\STX\DC3\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\SOH\ENQ\DC2\ETX\US\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\SOH\SOH\DC2\ETX\US\t\SO\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\SOH\ETX\DC2\ETX\US\DC1\DC2\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\STX\DC2\ETX \STX\CAN\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\STX\ENQ\DC2\ETX \STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\STX\SOH\DC2\ETX \t\DC3\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\STX\ETX\DC2\ETX \SYN\ETB\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\ETX\DC2\ETX!\STX\CAN\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ETX\ENQ\DC2\ETX!\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ETX\SOH\DC2\ETX!\t\DC3\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ETX\ETX\DC2\ETX!\SYN\ETB\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\EOT\DC2\ETX\"\STX\SUB\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\EOT\ENQ\DC2\ETX\"\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\EOT\SOH\DC2\ETX\"\t\NAK\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\EOT\ETX\DC2\ETX\"\CAN\EM\n\
    \\n\
    \\n\
    \\STX\EOT\EOT\DC2\EOT%\NUL*\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\EOT\SOH\DC2\ETX%\b\CAN\n\
    \\v\n\
    \\EOT\EOT\EOT\STX\NUL\DC2\ETX&\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\NUL\ENQ\DC2\ETX&\STX\b\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\NUL\SOH\DC2\ETX&\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\NUL\ETX\DC2\ETX&\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\EOT\STX\SOH\DC2\ETX'\STX\SUB\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\SOH\ENQ\DC2\ETX'\STX\b\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\SOH\SOH\DC2\ETX'\t\NAK\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\SOH\ETX\DC2\ETX'\CAN\EM\n\
    \\v\n\
    \\EOT\EOT\EOT\STX\STX\DC2\ETX(\STX\DC2\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\STX\ENQ\DC2\ETX(\STX\b\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\STX\SOH\DC2\ETX(\t\r\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\STX\ETX\DC2\ETX(\DLE\DC1\n\
    \\v\n\
    \\EOT\EOT\EOT\STX\ETX\DC2\ETX)\STX\EM\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\ETX\ENQ\DC2\ETX)\STX\b\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\ETX\SOH\DC2\ETX)\t\DC4\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\ETX\ETX\DC2\ETX)\ETB\CAN\n\
    \\n\
    \\n\
    \\STX\EOT\ENQ\DC2\EOT,\NUL1\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\ENQ\SOH\DC2\ETX,\b\DC4\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\NUL\DC2\ETX-\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\NUL\ENQ\DC2\ETX-\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\NUL\SOH\DC2\ETX-\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\NUL\ETX\DC2\ETX-\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\SOH\DC2\ETX.\STX\DC2\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\SOH\ENQ\DC2\ETX.\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\SOH\SOH\DC2\ETX.\t\r\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\SOH\ETX\DC2\ETX.\DLE\DC1\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\STX\DC2\ETX/\STX\DC3\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\STX\ENQ\DC2\ETX/\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\STX\SOH\DC2\ETX/\t\SO\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\STX\ETX\DC2\ETX/\DC1\DC2\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\ETX\DC2\ETX0\STX\SUB\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\ETX\ENQ\DC2\ETX0\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\ETX\SOH\DC2\ETX0\t\NAK\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\ETX\ETX\DC2\ETX0\CAN\EM\n\
    \\n\
    \\n\
    \\STX\EOT\ACK\DC2\EOT3\NUL8\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\ACK\SOH\DC2\ETX3\b\DC1\n\
    \\f\n\
    \\EOT\EOT\ACK\b\NUL\DC2\EOT4\STX7\ETX\n\
    \\f\n\
    \\ENQ\EOT\ACK\b\NUL\SOH\DC2\ETX4\b\f\n\
    \\v\n\
    \\EOT\EOT\ACK\STX\NUL\DC2\ETX5\EOT\EM\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\NUL\ACK\DC2\ETX5\EOT\SO\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\NUL\SOH\DC2\ETX5\SI\DC4\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\NUL\ETX\DC2\ETX5\ETB\CAN\n\
    \\v\n\
    \\EOT\EOT\ACK\STX\SOH\DC2\ETX6\EOT\EM\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\SOH\ACK\DC2\ETX6\EOT\r\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\SOH\SOH\DC2\ETX6\SI\DC3\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\SOH\ETX\DC2\ETX6\ETB\CAN\n\
    \\n\
    \\n\
    \\STX\EOT\a\DC2\EOT:\NULA\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\a\SOH\DC2\ETX:\b\SI\n\
    \\f\n\
    \\EOT\EOT\a\b\NUL\DC2\EOT;\STX@\ETX\n\
    \\f\n\
    \\ENQ\EOT\a\b\NUL\SOH\DC2\ETX;\b\f\n\
    \\v\n\
    \\EOT\EOT\a\STX\NUL\DC2\ETX<\EOT$\n\
    \\f\n\
    \\ENQ\EOT\a\STX\NUL\ACK\DC2\ETX<\EOT\SI\n\
    \\f\n\
    \\ENQ\EOT\a\STX\NUL\SOH\DC2\ETX<\NAK\FS\n\
    \\f\n\
    \\ENQ\EOT\a\STX\NUL\ETX\DC2\ETX<\"#\n\
    \\v\n\
    \\EOT\EOT\a\STX\SOH\DC2\ETX=\EOT$\n\
    \\f\n\
    \\ENQ\EOT\a\STX\SOH\ACK\DC2\ETX=\EOT\f\n\
    \\f\n\
    \\ENQ\EOT\a\STX\SOH\SOH\DC2\ETX=\NAK\EM\n\
    \\f\n\
    \\ENQ\EOT\a\STX\SOH\ETX\DC2\ETX=\"#\n\
    \\v\n\
    \\EOT\EOT\a\STX\STX\DC2\ETX>\EOT$\n\
    \\f\n\
    \\ENQ\EOT\a\STX\STX\ACK\DC2\ETX>\EOT\DC4\n\
    \\f\n\
    \\ENQ\EOT\a\STX\STX\SOH\DC2\ETX>\NAK\US\n\
    \\f\n\
    \\ENQ\EOT\a\STX\STX\ETX\DC2\ETX>\"#\n\
    \\v\n\
    \\EOT\EOT\a\STX\ETX\DC2\ETX?\EOT$\n\
    \\f\n\
    \\ENQ\EOT\a\STX\ETX\ACK\DC2\ETX?\EOT\DLE\n\
    \\f\n\
    \\ENQ\EOT\a\STX\ETX\SOH\DC2\ETX?\NAK\ESC\n\
    \\f\n\
    \\ENQ\EOT\a\STX\ETX\ETX\DC2\ETX?\"#b\ACKproto3"