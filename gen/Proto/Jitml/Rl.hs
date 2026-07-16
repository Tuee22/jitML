{- This file was auto-generated from jitml/rl.proto by the proto-lens-protoc program. -}
{-# LANGUAGE ScopedTypeVariables, DataKinds, TypeFamilies, UndecidableInstances, GeneralizedNewtypeDeriving, MultiParamTypeClasses, FlexibleContexts, FlexibleInstances, PatternSynonyms, MagicHash, NoImplicitPrelude, DataKinds, BangPatterns, TypeApplications, OverloadedStrings, DerivingStrategies#-}
{-# OPTIONS_GHC -Wno-unused-imports#-}
{-# OPTIONS_GHC -Wno-duplicate-exports#-}
{-# OPTIONS_GHC -Wno-dodgy-exports#-}
module Proto.Jitml.Rl (
        ArenaCompleted(), CheckpointDoneRL(), CompletedCheckpointDoneRL(),
        EpisodeDone(), EvalDone(), GenerationCompleted(), MetricUpdate(),
        RlAnimationFrame(), RlCommand(), RlCommand'Body(..),
        _RlCommand'Start, _RlCommand'Stop, _RlCommand'StartAlphaZero,
        RlEvent(), RlEvent'Body(..), _RlEvent'Episode, _RlEvent'Eval,
        _RlEvent'Checkpoint, _RlEvent'Metric, _RlEvent'Animation,
        _RlEvent'Replay, _RlEvent'GenerationCompleted,
        _RlEvent'ArenaCompleted, _RlEvent'CompletedCheckpoint,
        RlReplayFrame(), StartAlphaZeroRun(), StartRLRun(), StopRLRun()
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

         * 'Proto.Jitml.Rl_Fields.planId' @:: Lens' ArenaCompleted Data.Text.Text@
         * 'Proto.Jitml.Rl_Fields.experimentHash' @:: Lens' ArenaCompleted Data.Text.Text@
         * 'Proto.Jitml.Rl_Fields.arenaGames' @:: Lens' ArenaCompleted Data.Word.Word32@
         * 'Proto.Jitml.Rl_Fields.winRate' @:: Lens' ArenaCompleted Prelude.Double@ -}
data ArenaCompleted
  = ArenaCompleted'_constructor {_ArenaCompleted'planId :: !Data.Text.Text,
                                 _ArenaCompleted'experimentHash :: !Data.Text.Text,
                                 _ArenaCompleted'arenaGames :: !Data.Word.Word32,
                                 _ArenaCompleted'winRate :: !Prelude.Double,
                                 _ArenaCompleted'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show ArenaCompleted where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField ArenaCompleted "planId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ArenaCompleted'planId
           (\ x__ y__ -> x__ {_ArenaCompleted'planId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ArenaCompleted "experimentHash" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ArenaCompleted'experimentHash
           (\ x__ y__ -> x__ {_ArenaCompleted'experimentHash = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ArenaCompleted "arenaGames" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ArenaCompleted'arenaGames
           (\ x__ y__ -> x__ {_ArenaCompleted'arenaGames = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ArenaCompleted "winRate" Prelude.Double where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ArenaCompleted'winRate
           (\ x__ y__ -> x__ {_ArenaCompleted'winRate = y__}))
        Prelude.id
instance Data.ProtoLens.Message ArenaCompleted where
  messageName _ = Data.Text.pack "jitml.rl.ArenaCompleted"
  packedMessageDescriptor _
    = "\n\
      \\SOArenaCompleted\DC2\ETB\n\
      \\aplan_id\CAN\SOH \SOH(\tR\ACKplanId\DC2'\n\
      \\SIexperiment_hash\CAN\STX \SOH(\tR\SOexperimentHash\DC2\US\n\
      \\varena_games\CAN\ETX \SOH(\rR\n\
      \arenaGames\DC2\EM\n\
      \\bwin_rate\CAN\EOT \SOH(\SOHR\awinRate"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        planId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "plan_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"planId")) ::
              Data.ProtoLens.FieldDescriptor ArenaCompleted
        experimentHash__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "experiment_hash"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"experimentHash")) ::
              Data.ProtoLens.FieldDescriptor ArenaCompleted
        arenaGames__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "arena_games"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"arenaGames")) ::
              Data.ProtoLens.FieldDescriptor ArenaCompleted
        winRate__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "win_rate"
              (Data.ProtoLens.ScalarField Data.ProtoLens.DoubleField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Double)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"winRate")) ::
              Data.ProtoLens.FieldDescriptor ArenaCompleted
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, planId__field_descriptor),
           (Data.ProtoLens.Tag 2, experimentHash__field_descriptor),
           (Data.ProtoLens.Tag 3, arenaGames__field_descriptor),
           (Data.ProtoLens.Tag 4, winRate__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _ArenaCompleted'_unknownFields
        (\ x__ y__ -> x__ {_ArenaCompleted'_unknownFields = y__})
  defMessage
    = ArenaCompleted'_constructor
        {_ArenaCompleted'planId = Data.ProtoLens.fieldDefault,
         _ArenaCompleted'experimentHash = Data.ProtoLens.fieldDefault,
         _ArenaCompleted'arenaGames = Data.ProtoLens.fieldDefault,
         _ArenaCompleted'winRate = Data.ProtoLens.fieldDefault,
         _ArenaCompleted'_unknownFields = []}
  parseMessage
    = let
        loop ::
          ArenaCompleted
          -> Data.ProtoLens.Encoding.Bytes.Parser ArenaCompleted
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
                                       "plan_id"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"planId") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "experiment_hash"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"experimentHash") y x)
                        24
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "arena_games"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"arenaGames") y x)
                        33
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Data.ProtoLens.Encoding.Bytes.wordToDouble
                                          Data.ProtoLens.Encoding.Bytes.getFixed64)
                                       "win_rate"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"winRate") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "ArenaCompleted"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"planId") _x
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
                         (Data.ProtoLens.Field.field @"experimentHash") _x
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
                        = Lens.Family2.view (Data.ProtoLens.Field.field @"arenaGames") _x
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
                         _v = Lens.Family2.view (Data.ProtoLens.Field.field @"winRate") _x
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
instance Control.DeepSeq.NFData ArenaCompleted where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_ArenaCompleted'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_ArenaCompleted'planId x__)
                (Control.DeepSeq.deepseq
                   (_ArenaCompleted'experimentHash x__)
                   (Control.DeepSeq.deepseq
                      (_ArenaCompleted'arenaGames x__)
                      (Control.DeepSeq.deepseq (_ArenaCompleted'winRate x__) ()))))
{- | Fields :

         * 'Proto.Jitml.Rl_Fields.experimentHash' @:: Lens' CheckpointDoneRL Data.Text.Text@
         * 'Proto.Jitml.Rl_Fields.manifestSha' @:: Lens' CheckpointDoneRL Data.Text.Text@
         * 'Proto.Jitml.Rl_Fields.step' @:: Lens' CheckpointDoneRL Data.Word.Word64@
         * 'Proto.Jitml.Rl_Fields.pointerKey' @:: Lens' CheckpointDoneRL Data.Text.Text@
         * 'Proto.Jitml.Rl_Fields.protocolVersion' @:: Lens' CheckpointDoneRL Data.Word.Word32@ -}
data CheckpointDoneRL
  = CheckpointDoneRL'_constructor {_CheckpointDoneRL'experimentHash :: !Data.Text.Text,
                                   _CheckpointDoneRL'manifestSha :: !Data.Text.Text,
                                   _CheckpointDoneRL'step :: !Data.Word.Word64,
                                   _CheckpointDoneRL'pointerKey :: !Data.Text.Text,
                                   _CheckpointDoneRL'protocolVersion :: !Data.Word.Word32,
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
instance Data.ProtoLens.Field.HasField CheckpointDoneRL "protocolVersion" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CheckpointDoneRL'protocolVersion
           (\ x__ y__ -> x__ {_CheckpointDoneRL'protocolVersion = y__}))
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
      \pointerKey\DC2)\n\
      \\DLEprotocol_version\CAN\ENQ \SOH(\rR\SIprotocolVersion"
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
        protocolVersion__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "protocol_version"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"protocolVersion")) ::
              Data.ProtoLens.FieldDescriptor CheckpointDoneRL
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, experimentHash__field_descriptor),
           (Data.ProtoLens.Tag 2, manifestSha__field_descriptor),
           (Data.ProtoLens.Tag 3, step__field_descriptor),
           (Data.ProtoLens.Tag 4, pointerKey__field_descriptor),
           (Data.ProtoLens.Tag 5, protocolVersion__field_descriptor)]
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
         _CheckpointDoneRL'protocolVersion = Data.ProtoLens.fieldDefault,
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
                        40
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
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt 40)
                                  ((Prelude..)
                                     Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral
                                     _v))
                         (Data.ProtoLens.Encoding.Wire.buildFieldSet
                            (Lens.Family2.view Data.ProtoLens.unknownFields _x))))))
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
                      (Control.DeepSeq.deepseq
                         (_CheckpointDoneRL'pointerKey x__)
                         (Control.DeepSeq.deepseq
                            (_CheckpointDoneRL'protocolVersion x__) ())))))
{- | Fields :

         * 'Proto.Jitml.Rl_Fields.protocolVersion' @:: Lens' CompletedCheckpointDoneRL Data.Word.Word32@
         * 'Proto.Jitml.Rl_Fields.checkpoint' @:: Lens' CompletedCheckpointDoneRL CheckpointDoneRL@
         * 'Proto.Jitml.Rl_Fields.maybe'checkpoint' @:: Lens' CompletedCheckpointDoneRL (Prelude.Maybe CheckpointDoneRL)@
         * 'Proto.Jitml.Rl_Fields.completedTraining' @:: Lens' CompletedCheckpointDoneRL Data.ByteString.ByteString@ -}
data CompletedCheckpointDoneRL
  = CompletedCheckpointDoneRL'_constructor {_CompletedCheckpointDoneRL'protocolVersion :: !Data.Word.Word32,
                                            _CompletedCheckpointDoneRL'checkpoint :: !(Prelude.Maybe CheckpointDoneRL),
                                            _CompletedCheckpointDoneRL'completedTraining :: !Data.ByteString.ByteString,
                                            _CompletedCheckpointDoneRL'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show CompletedCheckpointDoneRL where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField CompletedCheckpointDoneRL "protocolVersion" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CompletedCheckpointDoneRL'protocolVersion
           (\ x__ y__
              -> x__ {_CompletedCheckpointDoneRL'protocolVersion = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CompletedCheckpointDoneRL "checkpoint" CheckpointDoneRL where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CompletedCheckpointDoneRL'checkpoint
           (\ x__ y__ -> x__ {_CompletedCheckpointDoneRL'checkpoint = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage)
instance Data.ProtoLens.Field.HasField CompletedCheckpointDoneRL "maybe'checkpoint" (Prelude.Maybe CheckpointDoneRL) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CompletedCheckpointDoneRL'checkpoint
           (\ x__ y__ -> x__ {_CompletedCheckpointDoneRL'checkpoint = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CompletedCheckpointDoneRL "completedTraining" Data.ByteString.ByteString where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CompletedCheckpointDoneRL'completedTraining
           (\ x__ y__
              -> x__ {_CompletedCheckpointDoneRL'completedTraining = y__}))
        Prelude.id
instance Data.ProtoLens.Message CompletedCheckpointDoneRL where
  messageName _ = Data.Text.pack "jitml.rl.CompletedCheckpointDoneRL"
  packedMessageDescriptor _
    = "\n\
      \\EMCompletedCheckpointDoneRL\DC2)\n\
      \\DLEprotocol_version\CAN\SOH \SOH(\rR\SIprotocolVersion\DC2:\n\
      \\n\
      \checkpoint\CAN\STX \SOH(\v2\SUB.jitml.rl.CheckpointDoneRLR\n\
      \checkpoint\DC2-\n\
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
              Data.ProtoLens.FieldDescriptor CompletedCheckpointDoneRL
        checkpoint__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "checkpoint"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor CheckpointDoneRL)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'checkpoint")) ::
              Data.ProtoLens.FieldDescriptor CompletedCheckpointDoneRL
        completedTraining__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "completed_training"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BytesField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.ByteString.ByteString)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"completedTraining")) ::
              Data.ProtoLens.FieldDescriptor CompletedCheckpointDoneRL
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, protocolVersion__field_descriptor),
           (Data.ProtoLens.Tag 2, checkpoint__field_descriptor),
           (Data.ProtoLens.Tag 3, completedTraining__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _CompletedCheckpointDoneRL'_unknownFields
        (\ x__ y__
           -> x__ {_CompletedCheckpointDoneRL'_unknownFields = y__})
  defMessage
    = CompletedCheckpointDoneRL'_constructor
        {_CompletedCheckpointDoneRL'protocolVersion = Data.ProtoLens.fieldDefault,
         _CompletedCheckpointDoneRL'checkpoint = Prelude.Nothing,
         _CompletedCheckpointDoneRL'completedTraining = Data.ProtoLens.fieldDefault,
         _CompletedCheckpointDoneRL'_unknownFields = []}
  parseMessage
    = let
        loop ::
          CompletedCheckpointDoneRL
          -> Data.ProtoLens.Encoding.Bytes.Parser CompletedCheckpointDoneRL
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
                                       "checkpoint"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"checkpoint") y x)
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
          (do loop Data.ProtoLens.defMessage) "CompletedCheckpointDoneRL"
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
                     Lens.Family2.view
                       (Data.ProtoLens.Field.field @"maybe'checkpoint") _x
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
instance Control.DeepSeq.NFData CompletedCheckpointDoneRL where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_CompletedCheckpointDoneRL'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_CompletedCheckpointDoneRL'protocolVersion x__)
                (Control.DeepSeq.deepseq
                   (_CompletedCheckpointDoneRL'checkpoint x__)
                   (Control.DeepSeq.deepseq
                      (_CompletedCheckpointDoneRL'completedTraining x__) ())))
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

         * 'Proto.Jitml.Rl_Fields.planId' @:: Lens' GenerationCompleted Data.Text.Text@
         * 'Proto.Jitml.Rl_Fields.experimentHash' @:: Lens' GenerationCompleted Data.Text.Text@
         * 'Proto.Jitml.Rl_Fields.generation' @:: Lens' GenerationCompleted Data.Word.Word32@
         * 'Proto.Jitml.Rl_Fields.selfPlayGames' @:: Lens' GenerationCompleted Data.Word.Word32@
         * 'Proto.Jitml.Rl_Fields.samples' @:: Lens' GenerationCompleted Data.Word.Word64@ -}
data GenerationCompleted
  = GenerationCompleted'_constructor {_GenerationCompleted'planId :: !Data.Text.Text,
                                      _GenerationCompleted'experimentHash :: !Data.Text.Text,
                                      _GenerationCompleted'generation :: !Data.Word.Word32,
                                      _GenerationCompleted'selfPlayGames :: !Data.Word.Word32,
                                      _GenerationCompleted'samples :: !Data.Word.Word64,
                                      _GenerationCompleted'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show GenerationCompleted where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField GenerationCompleted "planId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GenerationCompleted'planId
           (\ x__ y__ -> x__ {_GenerationCompleted'planId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GenerationCompleted "experimentHash" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GenerationCompleted'experimentHash
           (\ x__ y__ -> x__ {_GenerationCompleted'experimentHash = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GenerationCompleted "generation" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GenerationCompleted'generation
           (\ x__ y__ -> x__ {_GenerationCompleted'generation = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GenerationCompleted "selfPlayGames" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GenerationCompleted'selfPlayGames
           (\ x__ y__ -> x__ {_GenerationCompleted'selfPlayGames = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GenerationCompleted "samples" Data.Word.Word64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GenerationCompleted'samples
           (\ x__ y__ -> x__ {_GenerationCompleted'samples = y__}))
        Prelude.id
instance Data.ProtoLens.Message GenerationCompleted where
  messageName _ = Data.Text.pack "jitml.rl.GenerationCompleted"
  packedMessageDescriptor _
    = "\n\
      \\DC3GenerationCompleted\DC2\ETB\n\
      \\aplan_id\CAN\SOH \SOH(\tR\ACKplanId\DC2'\n\
      \\SIexperiment_hash\CAN\STX \SOH(\tR\SOexperimentHash\DC2\RS\n\
      \\n\
      \generation\CAN\ETX \SOH(\rR\n\
      \generation\DC2&\n\
      \\SIself_play_games\CAN\EOT \SOH(\rR\rselfPlayGames\DC2\CAN\n\
      \\asamples\CAN\ENQ \SOH(\EOTR\asamples"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        planId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "plan_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"planId")) ::
              Data.ProtoLens.FieldDescriptor GenerationCompleted
        experimentHash__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "experiment_hash"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"experimentHash")) ::
              Data.ProtoLens.FieldDescriptor GenerationCompleted
        generation__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "generation"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"generation")) ::
              Data.ProtoLens.FieldDescriptor GenerationCompleted
        selfPlayGames__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "self_play_games"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"selfPlayGames")) ::
              Data.ProtoLens.FieldDescriptor GenerationCompleted
        samples__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "samples"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word64)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"samples")) ::
              Data.ProtoLens.FieldDescriptor GenerationCompleted
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, planId__field_descriptor),
           (Data.ProtoLens.Tag 2, experimentHash__field_descriptor),
           (Data.ProtoLens.Tag 3, generation__field_descriptor),
           (Data.ProtoLens.Tag 4, selfPlayGames__field_descriptor),
           (Data.ProtoLens.Tag 5, samples__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _GenerationCompleted'_unknownFields
        (\ x__ y__ -> x__ {_GenerationCompleted'_unknownFields = y__})
  defMessage
    = GenerationCompleted'_constructor
        {_GenerationCompleted'planId = Data.ProtoLens.fieldDefault,
         _GenerationCompleted'experimentHash = Data.ProtoLens.fieldDefault,
         _GenerationCompleted'generation = Data.ProtoLens.fieldDefault,
         _GenerationCompleted'selfPlayGames = Data.ProtoLens.fieldDefault,
         _GenerationCompleted'samples = Data.ProtoLens.fieldDefault,
         _GenerationCompleted'_unknownFields = []}
  parseMessage
    = let
        loop ::
          GenerationCompleted
          -> Data.ProtoLens.Encoding.Bytes.Parser GenerationCompleted
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
                                       "plan_id"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"planId") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "experiment_hash"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"experimentHash") y x)
                        24
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "generation"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"generation") y x)
                        32
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "self_play_games"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"selfPlayGames") y x)
                        40
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       Data.ProtoLens.Encoding.Bytes.getVarInt "samples"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"samples") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "GenerationCompleted"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"planId") _x
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
                         (Data.ProtoLens.Field.field @"experimentHash") _x
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
                        = Lens.Family2.view (Data.ProtoLens.Field.field @"generation") _x
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
                               (Data.ProtoLens.Field.field @"selfPlayGames") _x
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
                            _v = Lens.Family2.view (Data.ProtoLens.Field.field @"samples") _x
                          in
                            if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                Data.Monoid.mempty
                            else
                                (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt 40)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt _v))
                         (Data.ProtoLens.Encoding.Wire.buildFieldSet
                            (Lens.Family2.view Data.ProtoLens.unknownFields _x))))))
instance Control.DeepSeq.NFData GenerationCompleted where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_GenerationCompleted'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_GenerationCompleted'planId x__)
                (Control.DeepSeq.deepseq
                   (_GenerationCompleted'experimentHash x__)
                   (Control.DeepSeq.deepseq
                      (_GenerationCompleted'generation x__)
                      (Control.DeepSeq.deepseq
                         (_GenerationCompleted'selfPlayGames x__)
                         (Control.DeepSeq.deepseq (_GenerationCompleted'samples x__) ())))))
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

         * 'Proto.Jitml.Rl_Fields.experimentHash' @:: Lens' RlAnimationFrame Data.Text.Text@
         * 'Proto.Jitml.Rl_Fields.environment' @:: Lens' RlAnimationFrame Data.Text.Text@
         * 'Proto.Jitml.Rl_Fields.episode' @:: Lens' RlAnimationFrame Data.Word.Word32@
         * 'Proto.Jitml.Rl_Fields.step' @:: Lens' RlAnimationFrame Data.Word.Word32@
         * 'Proto.Jitml.Rl_Fields.reward' @:: Lens' RlAnimationFrame Prelude.Double@
         * 'Proto.Jitml.Rl_Fields.done' @:: Lens' RlAnimationFrame Prelude.Bool@
         * 'Proto.Jitml.Rl_Fields.action' @:: Lens' RlAnimationFrame Data.Word.Word32@
         * 'Proto.Jitml.Rl_Fields.observation' @:: Lens' RlAnimationFrame [Prelude.Double]@
         * 'Proto.Jitml.Rl_Fields.vec'observation' @:: Lens' RlAnimationFrame (Data.Vector.Unboxed.Vector Prelude.Double)@
         * 'Proto.Jitml.Rl_Fields.actionProbabilities' @:: Lens' RlAnimationFrame [Prelude.Double]@
         * 'Proto.Jitml.Rl_Fields.vec'actionProbabilities' @:: Lens' RlAnimationFrame (Data.Vector.Unboxed.Vector Prelude.Double)@
         * 'Proto.Jitml.Rl_Fields.observationHash' @:: Lens' RlAnimationFrame Data.Word.Word32@
         * 'Proto.Jitml.Rl_Fields.replayCursor' @:: Lens' RlAnimationFrame Data.Word.Word64@
         * 'Proto.Jitml.Rl_Fields.timestampNs' @:: Lens' RlAnimationFrame Data.Word.Word64@ -}
data RlAnimationFrame
  = RlAnimationFrame'_constructor {_RlAnimationFrame'experimentHash :: !Data.Text.Text,
                                   _RlAnimationFrame'environment :: !Data.Text.Text,
                                   _RlAnimationFrame'episode :: !Data.Word.Word32,
                                   _RlAnimationFrame'step :: !Data.Word.Word32,
                                   _RlAnimationFrame'reward :: !Prelude.Double,
                                   _RlAnimationFrame'done :: !Prelude.Bool,
                                   _RlAnimationFrame'action :: !Data.Word.Word32,
                                   _RlAnimationFrame'observation :: !(Data.Vector.Unboxed.Vector Prelude.Double),
                                   _RlAnimationFrame'actionProbabilities :: !(Data.Vector.Unboxed.Vector Prelude.Double),
                                   _RlAnimationFrame'observationHash :: !Data.Word.Word32,
                                   _RlAnimationFrame'replayCursor :: !Data.Word.Word64,
                                   _RlAnimationFrame'timestampNs :: !Data.Word.Word64,
                                   _RlAnimationFrame'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show RlAnimationFrame where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField RlAnimationFrame "experimentHash" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlAnimationFrame'experimentHash
           (\ x__ y__ -> x__ {_RlAnimationFrame'experimentHash = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RlAnimationFrame "environment" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlAnimationFrame'environment
           (\ x__ y__ -> x__ {_RlAnimationFrame'environment = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RlAnimationFrame "episode" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlAnimationFrame'episode
           (\ x__ y__ -> x__ {_RlAnimationFrame'episode = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RlAnimationFrame "step" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlAnimationFrame'step
           (\ x__ y__ -> x__ {_RlAnimationFrame'step = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RlAnimationFrame "reward" Prelude.Double where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlAnimationFrame'reward
           (\ x__ y__ -> x__ {_RlAnimationFrame'reward = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RlAnimationFrame "done" Prelude.Bool where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlAnimationFrame'done
           (\ x__ y__ -> x__ {_RlAnimationFrame'done = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RlAnimationFrame "action" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlAnimationFrame'action
           (\ x__ y__ -> x__ {_RlAnimationFrame'action = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RlAnimationFrame "observation" [Prelude.Double] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlAnimationFrame'observation
           (\ x__ y__ -> x__ {_RlAnimationFrame'observation = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField RlAnimationFrame "vec'observation" (Data.Vector.Unboxed.Vector Prelude.Double) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlAnimationFrame'observation
           (\ x__ y__ -> x__ {_RlAnimationFrame'observation = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RlAnimationFrame "actionProbabilities" [Prelude.Double] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlAnimationFrame'actionProbabilities
           (\ x__ y__ -> x__ {_RlAnimationFrame'actionProbabilities = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField RlAnimationFrame "vec'actionProbabilities" (Data.Vector.Unboxed.Vector Prelude.Double) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlAnimationFrame'actionProbabilities
           (\ x__ y__ -> x__ {_RlAnimationFrame'actionProbabilities = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RlAnimationFrame "observationHash" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlAnimationFrame'observationHash
           (\ x__ y__ -> x__ {_RlAnimationFrame'observationHash = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RlAnimationFrame "replayCursor" Data.Word.Word64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlAnimationFrame'replayCursor
           (\ x__ y__ -> x__ {_RlAnimationFrame'replayCursor = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RlAnimationFrame "timestampNs" Data.Word.Word64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlAnimationFrame'timestampNs
           (\ x__ y__ -> x__ {_RlAnimationFrame'timestampNs = y__}))
        Prelude.id
instance Data.ProtoLens.Message RlAnimationFrame where
  messageName _ = Data.Text.pack "jitml.rl.RlAnimationFrame"
  packedMessageDescriptor _
    = "\n\
      \\DLERlAnimationFrame\DC2'\n\
      \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2 \n\
      \\venvironment\CAN\STX \SOH(\tR\venvironment\DC2\CAN\n\
      \\aepisode\CAN\ETX \SOH(\rR\aepisode\DC2\DC2\n\
      \\EOTstep\CAN\EOT \SOH(\rR\EOTstep\DC2\SYN\n\
      \\ACKreward\CAN\ENQ \SOH(\SOHR\ACKreward\DC2\DC2\n\
      \\EOTdone\CAN\ACK \SOH(\bR\EOTdone\DC2\SYN\n\
      \\ACKaction\CAN\a \SOH(\rR\ACKaction\DC2 \n\
      \\vobservation\CAN\b \ETX(\SOHR\vobservation\DC21\n\
      \\DC4action_probabilities\CAN\t \ETX(\SOHR\DC3actionProbabilities\DC2)\n\
      \\DLEobservation_hash\CAN\n\
      \ \SOH(\rR\SIobservationHash\DC2#\n\
      \\rreplay_cursor\CAN\v \SOH(\EOTR\freplayCursor\DC2!\n\
      \\ftimestamp_ns\CAN\f \SOH(\EOTR\vtimestampNs"
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
              Data.ProtoLens.FieldDescriptor RlAnimationFrame
        environment__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "environment"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"environment")) ::
              Data.ProtoLens.FieldDescriptor RlAnimationFrame
        episode__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "episode"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"episode")) ::
              Data.ProtoLens.FieldDescriptor RlAnimationFrame
        step__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "step"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"step")) ::
              Data.ProtoLens.FieldDescriptor RlAnimationFrame
        reward__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "reward"
              (Data.ProtoLens.ScalarField Data.ProtoLens.DoubleField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Double)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"reward")) ::
              Data.ProtoLens.FieldDescriptor RlAnimationFrame
        done__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "done"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BoolField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Bool)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"done")) ::
              Data.ProtoLens.FieldDescriptor RlAnimationFrame
        action__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "action"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"action")) ::
              Data.ProtoLens.FieldDescriptor RlAnimationFrame
        observation__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "observation"
              (Data.ProtoLens.ScalarField Data.ProtoLens.DoubleField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Double)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Packed
                 (Data.ProtoLens.Field.field @"observation")) ::
              Data.ProtoLens.FieldDescriptor RlAnimationFrame
        actionProbabilities__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "action_probabilities"
              (Data.ProtoLens.ScalarField Data.ProtoLens.DoubleField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Double)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Packed
                 (Data.ProtoLens.Field.field @"actionProbabilities")) ::
              Data.ProtoLens.FieldDescriptor RlAnimationFrame
        observationHash__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "observation_hash"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"observationHash")) ::
              Data.ProtoLens.FieldDescriptor RlAnimationFrame
        replayCursor__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "replay_cursor"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word64)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"replayCursor")) ::
              Data.ProtoLens.FieldDescriptor RlAnimationFrame
        timestampNs__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "timestamp_ns"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word64)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"timestampNs")) ::
              Data.ProtoLens.FieldDescriptor RlAnimationFrame
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, experimentHash__field_descriptor),
           (Data.ProtoLens.Tag 2, environment__field_descriptor),
           (Data.ProtoLens.Tag 3, episode__field_descriptor),
           (Data.ProtoLens.Tag 4, step__field_descriptor),
           (Data.ProtoLens.Tag 5, reward__field_descriptor),
           (Data.ProtoLens.Tag 6, done__field_descriptor),
           (Data.ProtoLens.Tag 7, action__field_descriptor),
           (Data.ProtoLens.Tag 8, observation__field_descriptor),
           (Data.ProtoLens.Tag 9, actionProbabilities__field_descriptor),
           (Data.ProtoLens.Tag 10, observationHash__field_descriptor),
           (Data.ProtoLens.Tag 11, replayCursor__field_descriptor),
           (Data.ProtoLens.Tag 12, timestampNs__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _RlAnimationFrame'_unknownFields
        (\ x__ y__ -> x__ {_RlAnimationFrame'_unknownFields = y__})
  defMessage
    = RlAnimationFrame'_constructor
        {_RlAnimationFrame'experimentHash = Data.ProtoLens.fieldDefault,
         _RlAnimationFrame'environment = Data.ProtoLens.fieldDefault,
         _RlAnimationFrame'episode = Data.ProtoLens.fieldDefault,
         _RlAnimationFrame'step = Data.ProtoLens.fieldDefault,
         _RlAnimationFrame'reward = Data.ProtoLens.fieldDefault,
         _RlAnimationFrame'done = Data.ProtoLens.fieldDefault,
         _RlAnimationFrame'action = Data.ProtoLens.fieldDefault,
         _RlAnimationFrame'observation = Data.Vector.Generic.empty,
         _RlAnimationFrame'actionProbabilities = Data.Vector.Generic.empty,
         _RlAnimationFrame'observationHash = Data.ProtoLens.fieldDefault,
         _RlAnimationFrame'replayCursor = Data.ProtoLens.fieldDefault,
         _RlAnimationFrame'timestampNs = Data.ProtoLens.fieldDefault,
         _RlAnimationFrame'_unknownFields = []}
  parseMessage
    = let
        loop ::
          RlAnimationFrame
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Unboxed.Vector Data.ProtoLens.Encoding.Growing.RealWorld Prelude.Double
             -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Unboxed.Vector Data.ProtoLens.Encoding.Growing.RealWorld Prelude.Double
                -> Data.ProtoLens.Encoding.Bytes.Parser RlAnimationFrame
        loop x mutable'actionProbabilities mutable'observation
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'actionProbabilities <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                                      (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                                         mutable'actionProbabilities)
                      frozen'observation <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                              (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                                 mutable'observation)
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
                              (Data.ProtoLens.Field.field @"vec'actionProbabilities")
                              frozen'actionProbabilities
                              (Lens.Family2.set
                                 (Data.ProtoLens.Field.field @"vec'observation") frozen'observation
                                 x)))
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
                                  mutable'actionProbabilities mutable'observation
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "environment"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"environment") y x)
                                  mutable'actionProbabilities mutable'observation
                        24
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "episode"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"episode") y x)
                                  mutable'actionProbabilities mutable'observation
                        32
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "step"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"step") y x)
                                  mutable'actionProbabilities mutable'observation
                        41
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Data.ProtoLens.Encoding.Bytes.wordToDouble
                                          Data.ProtoLens.Encoding.Bytes.getFixed64)
                                       "reward"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"reward") y x)
                                  mutable'actionProbabilities mutable'observation
                        48
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          ((Prelude./=) 0) Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "done"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"done") y x)
                                  mutable'actionProbabilities mutable'observation
                        56
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "action"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"action") y x)
                                  mutable'actionProbabilities mutable'observation
                        65
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (Prelude.fmap
                                           Data.ProtoLens.Encoding.Bytes.wordToDouble
                                           Data.ProtoLens.Encoding.Bytes.getFixed64)
                                        "observation"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append
                                          mutable'observation y)
                                loop x mutable'actionProbabilities v
                        66
                          -> do y <- do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                        Data.ProtoLens.Encoding.Bytes.isolate
                                          (Prelude.fromIntegral len)
                                          ((let
                                              ploop qs
                                                = do packedEnd <- Data.ProtoLens.Encoding.Bytes.atEnd
                                                     if packedEnd then
                                                         Prelude.return qs
                                                     else
                                                         do !q <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                                                    (Prelude.fmap
                                                                       Data.ProtoLens.Encoding.Bytes.wordToDouble
                                                                       Data.ProtoLens.Encoding.Bytes.getFixed64)
                                                                    "observation"
                                                            qs' <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                                                     (Data.ProtoLens.Encoding.Growing.append
                                                                        qs q)
                                                            ploop qs'
                                            in ploop)
                                             mutable'observation)
                                loop x mutable'actionProbabilities y
                        73
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (Prelude.fmap
                                           Data.ProtoLens.Encoding.Bytes.wordToDouble
                                           Data.ProtoLens.Encoding.Bytes.getFixed64)
                                        "action_probabilities"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append
                                          mutable'actionProbabilities y)
                                loop x v mutable'observation
                        74
                          -> do y <- do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                        Data.ProtoLens.Encoding.Bytes.isolate
                                          (Prelude.fromIntegral len)
                                          ((let
                                              ploop qs
                                                = do packedEnd <- Data.ProtoLens.Encoding.Bytes.atEnd
                                                     if packedEnd then
                                                         Prelude.return qs
                                                     else
                                                         do !q <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                                                    (Prelude.fmap
                                                                       Data.ProtoLens.Encoding.Bytes.wordToDouble
                                                                       Data.ProtoLens.Encoding.Bytes.getFixed64)
                                                                    "action_probabilities"
                                                            qs' <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                                                     (Data.ProtoLens.Encoding.Growing.append
                                                                        qs q)
                                                            ploop qs'
                                            in ploop)
                                             mutable'actionProbabilities)
                                loop x y mutable'observation
                        80
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "observation_hash"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"observationHash") y x)
                                  mutable'actionProbabilities mutable'observation
                        88
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       Data.ProtoLens.Encoding.Bytes.getVarInt "replay_cursor"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"replayCursor") y x)
                                  mutable'actionProbabilities mutable'observation
                        96
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       Data.ProtoLens.Encoding.Bytes.getVarInt "timestamp_ns"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"timestampNs") y x)
                                  mutable'actionProbabilities mutable'observation
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'actionProbabilities mutable'observation
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'actionProbabilities <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                               Data.ProtoLens.Encoding.Growing.new
              mutable'observation <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       Data.ProtoLens.Encoding.Growing.new
              loop
                Data.ProtoLens.defMessage mutable'actionProbabilities
                mutable'observation)
          "RlAnimationFrame"
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
                     = Lens.Family2.view (Data.ProtoLens.Field.field @"environment") _x
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
                      _v = Lens.Family2.view (Data.ProtoLens.Field.field @"episode") _x
                    in
                      if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                          Data.Monoid.mempty
                      else
                          (Data.Monoid.<>)
                            (Data.ProtoLens.Encoding.Bytes.putVarInt 24)
                            ((Prelude..)
                               Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                   ((Data.Monoid.<>)
                      (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"step") _x
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
                            _v = Lens.Family2.view (Data.ProtoLens.Field.field @"reward") _x
                          in
                            if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                Data.Monoid.mempty
                            else
                                (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt 41)
                                  ((Prelude..)
                                     Data.ProtoLens.Encoding.Bytes.putFixed64
                                     Data.ProtoLens.Encoding.Bytes.doubleToWord _v))
                         ((Data.Monoid.<>)
                            (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"done") _x
                             in
                               if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                   Data.Monoid.mempty
                               else
                                   (Data.Monoid.<>)
                                     (Data.ProtoLens.Encoding.Bytes.putVarInt 48)
                                     ((Prelude..)
                                        Data.ProtoLens.Encoding.Bytes.putVarInt
                                        (\ b -> if b then 1 else 0) _v))
                            ((Data.Monoid.<>)
                               (let
                                  _v = Lens.Family2.view (Data.ProtoLens.Field.field @"action") _x
                                in
                                  if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                      Data.Monoid.mempty
                                  else
                                      (Data.Monoid.<>)
                                        (Data.ProtoLens.Encoding.Bytes.putVarInt 56)
                                        ((Prelude..)
                                           Data.ProtoLens.Encoding.Bytes.putVarInt
                                           Prelude.fromIntegral _v))
                               ((Data.Monoid.<>)
                                  (let
                                     p = Lens.Family2.view
                                           (Data.ProtoLens.Field.field @"vec'observation") _x
                                   in
                                     if Data.Vector.Generic.null p then
                                         Data.Monoid.mempty
                                     else
                                         (Data.Monoid.<>)
                                           (Data.ProtoLens.Encoding.Bytes.putVarInt 66)
                                           ((\ bs
                                               -> (Data.Monoid.<>)
                                                    (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                       (Prelude.fromIntegral
                                                          (Data.ByteString.length bs)))
                                                    (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                              (Data.ProtoLens.Encoding.Bytes.runBuilder
                                                 (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                                                    ((Prelude..)
                                                       Data.ProtoLens.Encoding.Bytes.putFixed64
                                                       Data.ProtoLens.Encoding.Bytes.doubleToWord)
                                                    p))))
                                  ((Data.Monoid.<>)
                                     (let
                                        p = Lens.Family2.view
                                              (Data.ProtoLens.Field.field
                                                 @"vec'actionProbabilities")
                                              _x
                                      in
                                        if Data.Vector.Generic.null p then
                                            Data.Monoid.mempty
                                        else
                                            (Data.Monoid.<>)
                                              (Data.ProtoLens.Encoding.Bytes.putVarInt 74)
                                              ((\ bs
                                                  -> (Data.Monoid.<>)
                                                       (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                          (Prelude.fromIntegral
                                                             (Data.ByteString.length bs)))
                                                       (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                                 (Data.ProtoLens.Encoding.Bytes.runBuilder
                                                    (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                                                       ((Prelude..)
                                                          Data.ProtoLens.Encoding.Bytes.putFixed64
                                                          Data.ProtoLens.Encoding.Bytes.doubleToWord)
                                                       p))))
                                     ((Data.Monoid.<>)
                                        (let
                                           _v
                                             = Lens.Family2.view
                                                 (Data.ProtoLens.Field.field @"observationHash") _x
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
                                                    (Data.ProtoLens.Field.field @"replayCursor") _x
                                            in
                                              if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                                  Data.Monoid.mempty
                                              else
                                                  (Data.Monoid.<>)
                                                    (Data.ProtoLens.Encoding.Bytes.putVarInt 88)
                                                    (Data.ProtoLens.Encoding.Bytes.putVarInt _v))
                                           ((Data.Monoid.<>)
                                              (let
                                                 _v
                                                   = Lens.Family2.view
                                                       (Data.ProtoLens.Field.field @"timestampNs")
                                                       _x
                                               in
                                                 if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                                     Data.Monoid.mempty
                                                 else
                                                     (Data.Monoid.<>)
                                                       (Data.ProtoLens.Encoding.Bytes.putVarInt 96)
                                                       (Data.ProtoLens.Encoding.Bytes.putVarInt _v))
                                              (Data.ProtoLens.Encoding.Wire.buildFieldSet
                                                 (Lens.Family2.view
                                                    Data.ProtoLens.unknownFields _x)))))))))))))
instance Control.DeepSeq.NFData RlAnimationFrame where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_RlAnimationFrame'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_RlAnimationFrame'experimentHash x__)
                (Control.DeepSeq.deepseq
                   (_RlAnimationFrame'environment x__)
                   (Control.DeepSeq.deepseq
                      (_RlAnimationFrame'episode x__)
                      (Control.DeepSeq.deepseq
                         (_RlAnimationFrame'step x__)
                         (Control.DeepSeq.deepseq
                            (_RlAnimationFrame'reward x__)
                            (Control.DeepSeq.deepseq
                               (_RlAnimationFrame'done x__)
                               (Control.DeepSeq.deepseq
                                  (_RlAnimationFrame'action x__)
                                  (Control.DeepSeq.deepseq
                                     (_RlAnimationFrame'observation x__)
                                     (Control.DeepSeq.deepseq
                                        (_RlAnimationFrame'actionProbabilities x__)
                                        (Control.DeepSeq.deepseq
                                           (_RlAnimationFrame'observationHash x__)
                                           (Control.DeepSeq.deepseq
                                              (_RlAnimationFrame'replayCursor x__)
                                              (Control.DeepSeq.deepseq
                                                 (_RlAnimationFrame'timestampNs x__) ()))))))))))))
{- | Fields :

         * 'Proto.Jitml.Rl_Fields.maybe'body' @:: Lens' RlCommand (Prelude.Maybe RlCommand'Body)@
         * 'Proto.Jitml.Rl_Fields.maybe'start' @:: Lens' RlCommand (Prelude.Maybe StartRLRun)@
         * 'Proto.Jitml.Rl_Fields.start' @:: Lens' RlCommand StartRLRun@
         * 'Proto.Jitml.Rl_Fields.maybe'stop' @:: Lens' RlCommand (Prelude.Maybe StopRLRun)@
         * 'Proto.Jitml.Rl_Fields.stop' @:: Lens' RlCommand StopRLRun@
         * 'Proto.Jitml.Rl_Fields.maybe'startAlphaZero' @:: Lens' RlCommand (Prelude.Maybe StartAlphaZeroRun)@
         * 'Proto.Jitml.Rl_Fields.startAlphaZero' @:: Lens' RlCommand StartAlphaZeroRun@ -}
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
  = RlCommand'Start !StartRLRun |
    RlCommand'Stop !StopRLRun |
    RlCommand'StartAlphaZero !StartAlphaZeroRun
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
instance Data.ProtoLens.Field.HasField RlCommand "maybe'startAlphaZero" (Prelude.Maybe StartAlphaZeroRun) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlCommand'body (\ x__ y__ -> x__ {_RlCommand'body = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (RlCommand'StartAlphaZero x__val))
                     -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap RlCommand'StartAlphaZero y__))
instance Data.ProtoLens.Field.HasField RlCommand "startAlphaZero" StartAlphaZeroRun where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlCommand'body (\ x__ y__ -> x__ {_RlCommand'body = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (RlCommand'StartAlphaZero x__val))
                        -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap RlCommand'StartAlphaZero y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Message RlCommand where
  messageName _ = Data.Text.pack "jitml.rl.RlCommand"
  packedMessageDescriptor _
    = "\n\
      \\tRlCommand\DC2,\n\
      \\ENQstart\CAN\SOH \SOH(\v2\DC4.jitml.rl.StartRLRunH\NULR\ENQstart\DC2)\n\
      \\EOTstop\CAN\STX \SOH(\v2\DC3.jitml.rl.StopRLRunH\NULR\EOTstop\DC2G\n\
      \\DLEstart_alpha_zero\CAN\ETX \SOH(\v2\ESC.jitml.rl.StartAlphaZeroRunH\NULR\SOstartAlphaZeroB\ACK\n\
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
        startAlphaZero__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "start_alpha_zero"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor StartAlphaZeroRun)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'startAlphaZero")) ::
              Data.ProtoLens.FieldDescriptor RlCommand
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, start__field_descriptor),
           (Data.ProtoLens.Tag 2, stop__field_descriptor),
           (Data.ProtoLens.Tag 3, startAlphaZero__field_descriptor)]
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
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "start_alpha_zero"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"startAlphaZero") y x)
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
                          Data.ProtoLens.encodeMessage v)
                (Prelude.Just (RlCommand'StartAlphaZero v))
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
instance Control.DeepSeq.NFData RlCommand where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_RlCommand'_unknownFields x__)
             (Control.DeepSeq.deepseq (_RlCommand'body x__) ())
instance Control.DeepSeq.NFData RlCommand'Body where
  rnf (RlCommand'Start x__) = Control.DeepSeq.rnf x__
  rnf (RlCommand'Stop x__) = Control.DeepSeq.rnf x__
  rnf (RlCommand'StartAlphaZero x__) = Control.DeepSeq.rnf x__
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
_RlCommand'StartAlphaZero ::
  Data.ProtoLens.Prism.Prism' RlCommand'Body StartAlphaZeroRun
_RlCommand'StartAlphaZero
  = Data.ProtoLens.Prism.prism'
      RlCommand'StartAlphaZero
      (\ p__
         -> case p__ of
              (RlCommand'StartAlphaZero p__val) -> Prelude.Just p__val
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
         * 'Proto.Jitml.Rl_Fields.metric' @:: Lens' RlEvent MetricUpdate@
         * 'Proto.Jitml.Rl_Fields.maybe'animation' @:: Lens' RlEvent (Prelude.Maybe RlAnimationFrame)@
         * 'Proto.Jitml.Rl_Fields.animation' @:: Lens' RlEvent RlAnimationFrame@
         * 'Proto.Jitml.Rl_Fields.maybe'replay' @:: Lens' RlEvent (Prelude.Maybe RlReplayFrame)@
         * 'Proto.Jitml.Rl_Fields.replay' @:: Lens' RlEvent RlReplayFrame@
         * 'Proto.Jitml.Rl_Fields.maybe'generationCompleted' @:: Lens' RlEvent (Prelude.Maybe GenerationCompleted)@
         * 'Proto.Jitml.Rl_Fields.generationCompleted' @:: Lens' RlEvent GenerationCompleted@
         * 'Proto.Jitml.Rl_Fields.maybe'arenaCompleted' @:: Lens' RlEvent (Prelude.Maybe ArenaCompleted)@
         * 'Proto.Jitml.Rl_Fields.arenaCompleted' @:: Lens' RlEvent ArenaCompleted@
         * 'Proto.Jitml.Rl_Fields.maybe'completedCheckpoint' @:: Lens' RlEvent (Prelude.Maybe CompletedCheckpointDoneRL)@
         * 'Proto.Jitml.Rl_Fields.completedCheckpoint' @:: Lens' RlEvent CompletedCheckpointDoneRL@ -}
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
    RlEvent'Metric !MetricUpdate |
    RlEvent'Animation !RlAnimationFrame |
    RlEvent'Replay !RlReplayFrame |
    RlEvent'GenerationCompleted !GenerationCompleted |
    RlEvent'ArenaCompleted !ArenaCompleted |
    RlEvent'CompletedCheckpoint !CompletedCheckpointDoneRL
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
instance Data.ProtoLens.Field.HasField RlEvent "maybe'animation" (Prelude.Maybe RlAnimationFrame) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlEvent'body (\ x__ y__ -> x__ {_RlEvent'body = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (RlEvent'Animation x__val)) -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap RlEvent'Animation y__))
instance Data.ProtoLens.Field.HasField RlEvent "animation" RlAnimationFrame where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlEvent'body (\ x__ y__ -> x__ {_RlEvent'body = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (RlEvent'Animation x__val)) -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap RlEvent'Animation y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField RlEvent "maybe'replay" (Prelude.Maybe RlReplayFrame) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlEvent'body (\ x__ y__ -> x__ {_RlEvent'body = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (RlEvent'Replay x__val)) -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap RlEvent'Replay y__))
instance Data.ProtoLens.Field.HasField RlEvent "replay" RlReplayFrame where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlEvent'body (\ x__ y__ -> x__ {_RlEvent'body = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (RlEvent'Replay x__val)) -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap RlEvent'Replay y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField RlEvent "maybe'generationCompleted" (Prelude.Maybe GenerationCompleted) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlEvent'body (\ x__ y__ -> x__ {_RlEvent'body = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (RlEvent'GenerationCompleted x__val))
                     -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap RlEvent'GenerationCompleted y__))
instance Data.ProtoLens.Field.HasField RlEvent "generationCompleted" GenerationCompleted where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlEvent'body (\ x__ y__ -> x__ {_RlEvent'body = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (RlEvent'GenerationCompleted x__val))
                        -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap RlEvent'GenerationCompleted y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField RlEvent "maybe'arenaCompleted" (Prelude.Maybe ArenaCompleted) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlEvent'body (\ x__ y__ -> x__ {_RlEvent'body = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (RlEvent'ArenaCompleted x__val))
                     -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap RlEvent'ArenaCompleted y__))
instance Data.ProtoLens.Field.HasField RlEvent "arenaCompleted" ArenaCompleted where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlEvent'body (\ x__ y__ -> x__ {_RlEvent'body = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (RlEvent'ArenaCompleted x__val))
                        -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap RlEvent'ArenaCompleted y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField RlEvent "maybe'completedCheckpoint" (Prelude.Maybe CompletedCheckpointDoneRL) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlEvent'body (\ x__ y__ -> x__ {_RlEvent'body = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (RlEvent'CompletedCheckpoint x__val))
                     -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap RlEvent'CompletedCheckpoint y__))
instance Data.ProtoLens.Field.HasField RlEvent "completedCheckpoint" CompletedCheckpointDoneRL where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlEvent'body (\ x__ y__ -> x__ {_RlEvent'body = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (RlEvent'CompletedCheckpoint x__val))
                        -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap RlEvent'CompletedCheckpoint y__))
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
      \\ACKmetric\CAN\EOT \SOH(\v2\SYN.jitml.rl.MetricUpdateH\NULR\ACKmetric\DC2:\n\
      \\tanimation\CAN\ENQ \SOH(\v2\SUB.jitml.rl.RlAnimationFrameH\NULR\tanimation\DC21\n\
      \\ACKreplay\CAN\ACK \SOH(\v2\ETB.jitml.rl.RlReplayFrameH\NULR\ACKreplay\DC2R\n\
      \\DC4generation_completed\CAN\a \SOH(\v2\GS.jitml.rl.GenerationCompletedH\NULR\DC3generationCompleted\DC2C\n\
      \\SIarena_completed\CAN\b \SOH(\v2\CAN.jitml.rl.ArenaCompletedH\NULR\SOarenaCompleted\DC2X\n\
      \\DC4completed_checkpoint\CAN\t \SOH(\v2#.jitml.rl.CompletedCheckpointDoneRLH\NULR\DC3completedCheckpointB\ACK\n\
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
        animation__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "animation"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor RlAnimationFrame)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'animation")) ::
              Data.ProtoLens.FieldDescriptor RlEvent
        replay__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "replay"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor RlReplayFrame)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'replay")) ::
              Data.ProtoLens.FieldDescriptor RlEvent
        generationCompleted__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "generation_completed"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor GenerationCompleted)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'generationCompleted")) ::
              Data.ProtoLens.FieldDescriptor RlEvent
        arenaCompleted__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "arena_completed"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor ArenaCompleted)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'arenaCompleted")) ::
              Data.ProtoLens.FieldDescriptor RlEvent
        completedCheckpoint__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "completed_checkpoint"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor CompletedCheckpointDoneRL)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'completedCheckpoint")) ::
              Data.ProtoLens.FieldDescriptor RlEvent
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, episode__field_descriptor),
           (Data.ProtoLens.Tag 2, eval__field_descriptor),
           (Data.ProtoLens.Tag 3, checkpoint__field_descriptor),
           (Data.ProtoLens.Tag 4, metric__field_descriptor),
           (Data.ProtoLens.Tag 5, animation__field_descriptor),
           (Data.ProtoLens.Tag 6, replay__field_descriptor),
           (Data.ProtoLens.Tag 7, generationCompleted__field_descriptor),
           (Data.ProtoLens.Tag 8, arenaCompleted__field_descriptor),
           (Data.ProtoLens.Tag 9, completedCheckpoint__field_descriptor)]
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
                        42
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "animation"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"animation") y x)
                        50
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "replay"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"replay") y x)
                        58
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "generation_completed"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"generationCompleted") y x)
                        66
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "arena_completed"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"arenaCompleted") y x)
                        74
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "completed_checkpoint"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"completedCheckpoint") y x)
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
                          Data.ProtoLens.encodeMessage v)
                (Prelude.Just (RlEvent'Animation v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 42)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v)
                (Prelude.Just (RlEvent'Replay v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 50)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v)
                (Prelude.Just (RlEvent'GenerationCompleted v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 58)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v)
                (Prelude.Just (RlEvent'ArenaCompleted v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 66)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v)
                (Prelude.Just (RlEvent'CompletedCheckpoint v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 74)
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
  rnf (RlEvent'Animation x__) = Control.DeepSeq.rnf x__
  rnf (RlEvent'Replay x__) = Control.DeepSeq.rnf x__
  rnf (RlEvent'GenerationCompleted x__) = Control.DeepSeq.rnf x__
  rnf (RlEvent'ArenaCompleted x__) = Control.DeepSeq.rnf x__
  rnf (RlEvent'CompletedCheckpoint x__) = Control.DeepSeq.rnf x__
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
_RlEvent'Animation ::
  Data.ProtoLens.Prism.Prism' RlEvent'Body RlAnimationFrame
_RlEvent'Animation
  = Data.ProtoLens.Prism.prism'
      RlEvent'Animation
      (\ p__
         -> case p__ of
              (RlEvent'Animation p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_RlEvent'Replay ::
  Data.ProtoLens.Prism.Prism' RlEvent'Body RlReplayFrame
_RlEvent'Replay
  = Data.ProtoLens.Prism.prism'
      RlEvent'Replay
      (\ p__
         -> case p__ of
              (RlEvent'Replay p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_RlEvent'GenerationCompleted ::
  Data.ProtoLens.Prism.Prism' RlEvent'Body GenerationCompleted
_RlEvent'GenerationCompleted
  = Data.ProtoLens.Prism.prism'
      RlEvent'GenerationCompleted
      (\ p__
         -> case p__ of
              (RlEvent'GenerationCompleted p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_RlEvent'ArenaCompleted ::
  Data.ProtoLens.Prism.Prism' RlEvent'Body ArenaCompleted
_RlEvent'ArenaCompleted
  = Data.ProtoLens.Prism.prism'
      RlEvent'ArenaCompleted
      (\ p__
         -> case p__ of
              (RlEvent'ArenaCompleted p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_RlEvent'CompletedCheckpoint ::
  Data.ProtoLens.Prism.Prism' RlEvent'Body CompletedCheckpointDoneRL
_RlEvent'CompletedCheckpoint
  = Data.ProtoLens.Prism.prism'
      RlEvent'CompletedCheckpoint
      (\ p__
         -> case p__ of
              (RlEvent'CompletedCheckpoint p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
{- | Fields :

         * 'Proto.Jitml.Rl_Fields.experimentHash' @:: Lens' RlReplayFrame Data.Text.Text@
         * 'Proto.Jitml.Rl_Fields.replayId' @:: Lens' RlReplayFrame Data.Text.Text@
         * 'Proto.Jitml.Rl_Fields.environment' @:: Lens' RlReplayFrame Data.Text.Text@
         * 'Proto.Jitml.Rl_Fields.episode' @:: Lens' RlReplayFrame Data.Word.Word32@
         * 'Proto.Jitml.Rl_Fields.step' @:: Lens' RlReplayFrame Data.Word.Word32@
         * 'Proto.Jitml.Rl_Fields.action' @:: Lens' RlReplayFrame Data.Word.Word32@
         * 'Proto.Jitml.Rl_Fields.reward' @:: Lens' RlReplayFrame Prelude.Double@
         * 'Proto.Jitml.Rl_Fields.done' @:: Lens' RlReplayFrame Prelude.Bool@
         * 'Proto.Jitml.Rl_Fields.observation' @:: Lens' RlReplayFrame [Prelude.Double]@
         * 'Proto.Jitml.Rl_Fields.vec'observation' @:: Lens' RlReplayFrame (Data.Vector.Unboxed.Vector Prelude.Double)@
         * 'Proto.Jitml.Rl_Fields.nextObservation' @:: Lens' RlReplayFrame [Prelude.Double]@
         * 'Proto.Jitml.Rl_Fields.vec'nextObservation' @:: Lens' RlReplayFrame (Data.Vector.Unboxed.Vector Prelude.Double)@
         * 'Proto.Jitml.Rl_Fields.policyVersion' @:: Lens' RlReplayFrame Data.Word.Word64@
         * 'Proto.Jitml.Rl_Fields.observationHash' @:: Lens' RlReplayFrame Data.Word.Word32@
         * 'Proto.Jitml.Rl_Fields.timestampNs' @:: Lens' RlReplayFrame Data.Word.Word64@ -}
data RlReplayFrame
  = RlReplayFrame'_constructor {_RlReplayFrame'experimentHash :: !Data.Text.Text,
                                _RlReplayFrame'replayId :: !Data.Text.Text,
                                _RlReplayFrame'environment :: !Data.Text.Text,
                                _RlReplayFrame'episode :: !Data.Word.Word32,
                                _RlReplayFrame'step :: !Data.Word.Word32,
                                _RlReplayFrame'action :: !Data.Word.Word32,
                                _RlReplayFrame'reward :: !Prelude.Double,
                                _RlReplayFrame'done :: !Prelude.Bool,
                                _RlReplayFrame'observation :: !(Data.Vector.Unboxed.Vector Prelude.Double),
                                _RlReplayFrame'nextObservation :: !(Data.Vector.Unboxed.Vector Prelude.Double),
                                _RlReplayFrame'policyVersion :: !Data.Word.Word64,
                                _RlReplayFrame'observationHash :: !Data.Word.Word32,
                                _RlReplayFrame'timestampNs :: !Data.Word.Word64,
                                _RlReplayFrame'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show RlReplayFrame where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField RlReplayFrame "experimentHash" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlReplayFrame'experimentHash
           (\ x__ y__ -> x__ {_RlReplayFrame'experimentHash = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RlReplayFrame "replayId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlReplayFrame'replayId
           (\ x__ y__ -> x__ {_RlReplayFrame'replayId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RlReplayFrame "environment" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlReplayFrame'environment
           (\ x__ y__ -> x__ {_RlReplayFrame'environment = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RlReplayFrame "episode" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlReplayFrame'episode
           (\ x__ y__ -> x__ {_RlReplayFrame'episode = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RlReplayFrame "step" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlReplayFrame'step (\ x__ y__ -> x__ {_RlReplayFrame'step = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RlReplayFrame "action" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlReplayFrame'action
           (\ x__ y__ -> x__ {_RlReplayFrame'action = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RlReplayFrame "reward" Prelude.Double where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlReplayFrame'reward
           (\ x__ y__ -> x__ {_RlReplayFrame'reward = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RlReplayFrame "done" Prelude.Bool where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlReplayFrame'done (\ x__ y__ -> x__ {_RlReplayFrame'done = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RlReplayFrame "observation" [Prelude.Double] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlReplayFrame'observation
           (\ x__ y__ -> x__ {_RlReplayFrame'observation = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField RlReplayFrame "vec'observation" (Data.Vector.Unboxed.Vector Prelude.Double) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlReplayFrame'observation
           (\ x__ y__ -> x__ {_RlReplayFrame'observation = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RlReplayFrame "nextObservation" [Prelude.Double] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlReplayFrame'nextObservation
           (\ x__ y__ -> x__ {_RlReplayFrame'nextObservation = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField RlReplayFrame "vec'nextObservation" (Data.Vector.Unboxed.Vector Prelude.Double) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlReplayFrame'nextObservation
           (\ x__ y__ -> x__ {_RlReplayFrame'nextObservation = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RlReplayFrame "policyVersion" Data.Word.Word64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlReplayFrame'policyVersion
           (\ x__ y__ -> x__ {_RlReplayFrame'policyVersion = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RlReplayFrame "observationHash" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlReplayFrame'observationHash
           (\ x__ y__ -> x__ {_RlReplayFrame'observationHash = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RlReplayFrame "timestampNs" Data.Word.Word64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RlReplayFrame'timestampNs
           (\ x__ y__ -> x__ {_RlReplayFrame'timestampNs = y__}))
        Prelude.id
instance Data.ProtoLens.Message RlReplayFrame where
  messageName _ = Data.Text.pack "jitml.rl.RlReplayFrame"
  packedMessageDescriptor _
    = "\n\
      \\rRlReplayFrame\DC2'\n\
      \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2\ESC\n\
      \\treplay_id\CAN\STX \SOH(\tR\breplayId\DC2 \n\
      \\venvironment\CAN\ETX \SOH(\tR\venvironment\DC2\CAN\n\
      \\aepisode\CAN\EOT \SOH(\rR\aepisode\DC2\DC2\n\
      \\EOTstep\CAN\ENQ \SOH(\rR\EOTstep\DC2\SYN\n\
      \\ACKaction\CAN\ACK \SOH(\rR\ACKaction\DC2\SYN\n\
      \\ACKreward\CAN\a \SOH(\SOHR\ACKreward\DC2\DC2\n\
      \\EOTdone\CAN\b \SOH(\bR\EOTdone\DC2 \n\
      \\vobservation\CAN\t \ETX(\SOHR\vobservation\DC2)\n\
      \\DLEnext_observation\CAN\n\
      \ \ETX(\SOHR\SInextObservation\DC2%\n\
      \\SOpolicy_version\CAN\v \SOH(\EOTR\rpolicyVersion\DC2)\n\
      \\DLEobservation_hash\CAN\f \SOH(\rR\SIobservationHash\DC2!\n\
      \\ftimestamp_ns\CAN\r \SOH(\EOTR\vtimestampNs"
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
              Data.ProtoLens.FieldDescriptor RlReplayFrame
        replayId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "replay_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"replayId")) ::
              Data.ProtoLens.FieldDescriptor RlReplayFrame
        environment__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "environment"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"environment")) ::
              Data.ProtoLens.FieldDescriptor RlReplayFrame
        episode__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "episode"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"episode")) ::
              Data.ProtoLens.FieldDescriptor RlReplayFrame
        step__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "step"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"step")) ::
              Data.ProtoLens.FieldDescriptor RlReplayFrame
        action__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "action"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"action")) ::
              Data.ProtoLens.FieldDescriptor RlReplayFrame
        reward__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "reward"
              (Data.ProtoLens.ScalarField Data.ProtoLens.DoubleField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Double)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"reward")) ::
              Data.ProtoLens.FieldDescriptor RlReplayFrame
        done__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "done"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BoolField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Bool)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"done")) ::
              Data.ProtoLens.FieldDescriptor RlReplayFrame
        observation__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "observation"
              (Data.ProtoLens.ScalarField Data.ProtoLens.DoubleField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Double)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Packed
                 (Data.ProtoLens.Field.field @"observation")) ::
              Data.ProtoLens.FieldDescriptor RlReplayFrame
        nextObservation__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "next_observation"
              (Data.ProtoLens.ScalarField Data.ProtoLens.DoubleField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Double)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Packed
                 (Data.ProtoLens.Field.field @"nextObservation")) ::
              Data.ProtoLens.FieldDescriptor RlReplayFrame
        policyVersion__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "policy_version"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word64)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"policyVersion")) ::
              Data.ProtoLens.FieldDescriptor RlReplayFrame
        observationHash__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "observation_hash"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"observationHash")) ::
              Data.ProtoLens.FieldDescriptor RlReplayFrame
        timestampNs__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "timestamp_ns"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word64)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"timestampNs")) ::
              Data.ProtoLens.FieldDescriptor RlReplayFrame
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, experimentHash__field_descriptor),
           (Data.ProtoLens.Tag 2, replayId__field_descriptor),
           (Data.ProtoLens.Tag 3, environment__field_descriptor),
           (Data.ProtoLens.Tag 4, episode__field_descriptor),
           (Data.ProtoLens.Tag 5, step__field_descriptor),
           (Data.ProtoLens.Tag 6, action__field_descriptor),
           (Data.ProtoLens.Tag 7, reward__field_descriptor),
           (Data.ProtoLens.Tag 8, done__field_descriptor),
           (Data.ProtoLens.Tag 9, observation__field_descriptor),
           (Data.ProtoLens.Tag 10, nextObservation__field_descriptor),
           (Data.ProtoLens.Tag 11, policyVersion__field_descriptor),
           (Data.ProtoLens.Tag 12, observationHash__field_descriptor),
           (Data.ProtoLens.Tag 13, timestampNs__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _RlReplayFrame'_unknownFields
        (\ x__ y__ -> x__ {_RlReplayFrame'_unknownFields = y__})
  defMessage
    = RlReplayFrame'_constructor
        {_RlReplayFrame'experimentHash = Data.ProtoLens.fieldDefault,
         _RlReplayFrame'replayId = Data.ProtoLens.fieldDefault,
         _RlReplayFrame'environment = Data.ProtoLens.fieldDefault,
         _RlReplayFrame'episode = Data.ProtoLens.fieldDefault,
         _RlReplayFrame'step = Data.ProtoLens.fieldDefault,
         _RlReplayFrame'action = Data.ProtoLens.fieldDefault,
         _RlReplayFrame'reward = Data.ProtoLens.fieldDefault,
         _RlReplayFrame'done = Data.ProtoLens.fieldDefault,
         _RlReplayFrame'observation = Data.Vector.Generic.empty,
         _RlReplayFrame'nextObservation = Data.Vector.Generic.empty,
         _RlReplayFrame'policyVersion = Data.ProtoLens.fieldDefault,
         _RlReplayFrame'observationHash = Data.ProtoLens.fieldDefault,
         _RlReplayFrame'timestampNs = Data.ProtoLens.fieldDefault,
         _RlReplayFrame'_unknownFields = []}
  parseMessage
    = let
        loop ::
          RlReplayFrame
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Unboxed.Vector Data.ProtoLens.Encoding.Growing.RealWorld Prelude.Double
             -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Unboxed.Vector Data.ProtoLens.Encoding.Growing.RealWorld Prelude.Double
                -> Data.ProtoLens.Encoding.Bytes.Parser RlReplayFrame
        loop x mutable'nextObservation mutable'observation
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'nextObservation <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                                  (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                                     mutable'nextObservation)
                      frozen'observation <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                              (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                                 mutable'observation)
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
                              (Data.ProtoLens.Field.field @"vec'nextObservation")
                              frozen'nextObservation
                              (Lens.Family2.set
                                 (Data.ProtoLens.Field.field @"vec'observation") frozen'observation
                                 x)))
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
                                  mutable'nextObservation mutable'observation
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "replay_id"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"replayId") y x)
                                  mutable'nextObservation mutable'observation
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "environment"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"environment") y x)
                                  mutable'nextObservation mutable'observation
                        32
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "episode"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"episode") y x)
                                  mutable'nextObservation mutable'observation
                        40
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "step"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"step") y x)
                                  mutable'nextObservation mutable'observation
                        48
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "action"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"action") y x)
                                  mutable'nextObservation mutable'observation
                        57
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Data.ProtoLens.Encoding.Bytes.wordToDouble
                                          Data.ProtoLens.Encoding.Bytes.getFixed64)
                                       "reward"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"reward") y x)
                                  mutable'nextObservation mutable'observation
                        64
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          ((Prelude./=) 0) Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "done"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"done") y x)
                                  mutable'nextObservation mutable'observation
                        73
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (Prelude.fmap
                                           Data.ProtoLens.Encoding.Bytes.wordToDouble
                                           Data.ProtoLens.Encoding.Bytes.getFixed64)
                                        "observation"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append
                                          mutable'observation y)
                                loop x mutable'nextObservation v
                        74
                          -> do y <- do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                        Data.ProtoLens.Encoding.Bytes.isolate
                                          (Prelude.fromIntegral len)
                                          ((let
                                              ploop qs
                                                = do packedEnd <- Data.ProtoLens.Encoding.Bytes.atEnd
                                                     if packedEnd then
                                                         Prelude.return qs
                                                     else
                                                         do !q <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                                                    (Prelude.fmap
                                                                       Data.ProtoLens.Encoding.Bytes.wordToDouble
                                                                       Data.ProtoLens.Encoding.Bytes.getFixed64)
                                                                    "observation"
                                                            qs' <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                                                     (Data.ProtoLens.Encoding.Growing.append
                                                                        qs q)
                                                            ploop qs'
                                            in ploop)
                                             mutable'observation)
                                loop x mutable'nextObservation y
                        81
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (Prelude.fmap
                                           Data.ProtoLens.Encoding.Bytes.wordToDouble
                                           Data.ProtoLens.Encoding.Bytes.getFixed64)
                                        "next_observation"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append
                                          mutable'nextObservation y)
                                loop x v mutable'observation
                        82
                          -> do y <- do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                        Data.ProtoLens.Encoding.Bytes.isolate
                                          (Prelude.fromIntegral len)
                                          ((let
                                              ploop qs
                                                = do packedEnd <- Data.ProtoLens.Encoding.Bytes.atEnd
                                                     if packedEnd then
                                                         Prelude.return qs
                                                     else
                                                         do !q <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                                                    (Prelude.fmap
                                                                       Data.ProtoLens.Encoding.Bytes.wordToDouble
                                                                       Data.ProtoLens.Encoding.Bytes.getFixed64)
                                                                    "next_observation"
                                                            qs' <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                                                     (Data.ProtoLens.Encoding.Growing.append
                                                                        qs q)
                                                            ploop qs'
                                            in ploop)
                                             mutable'nextObservation)
                                loop x y mutable'observation
                        88
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       Data.ProtoLens.Encoding.Bytes.getVarInt "policy_version"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"policyVersion") y x)
                                  mutable'nextObservation mutable'observation
                        96
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "observation_hash"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"observationHash") y x)
                                  mutable'nextObservation mutable'observation
                        104
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       Data.ProtoLens.Encoding.Bytes.getVarInt "timestamp_ns"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"timestampNs") y x)
                                  mutable'nextObservation mutable'observation
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'nextObservation mutable'observation
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'nextObservation <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                           Data.ProtoLens.Encoding.Growing.new
              mutable'observation <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       Data.ProtoLens.Encoding.Growing.new
              loop
                Data.ProtoLens.defMessage mutable'nextObservation
                mutable'observation)
          "RlReplayFrame"
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
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"replayId") _x
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
                         _v = Lens.Family2.view (Data.ProtoLens.Field.field @"episode") _x
                       in
                         if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                             Data.Monoid.mempty
                         else
                             (Data.Monoid.<>)
                               (Data.ProtoLens.Encoding.Bytes.putVarInt 32)
                               ((Prelude..)
                                  Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                      ((Data.Monoid.<>)
                         (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"step") _x
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
                               _v = Lens.Family2.view (Data.ProtoLens.Field.field @"action") _x
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
                                  _v = Lens.Family2.view (Data.ProtoLens.Field.field @"reward") _x
                                in
                                  if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                      Data.Monoid.mempty
                                  else
                                      (Data.Monoid.<>)
                                        (Data.ProtoLens.Encoding.Bytes.putVarInt 57)
                                        ((Prelude..)
                                           Data.ProtoLens.Encoding.Bytes.putFixed64
                                           Data.ProtoLens.Encoding.Bytes.doubleToWord _v))
                               ((Data.Monoid.<>)
                                  (let
                                     _v = Lens.Family2.view (Data.ProtoLens.Field.field @"done") _x
                                   in
                                     if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                         Data.Monoid.mempty
                                     else
                                         (Data.Monoid.<>)
                                           (Data.ProtoLens.Encoding.Bytes.putVarInt 64)
                                           ((Prelude..)
                                              Data.ProtoLens.Encoding.Bytes.putVarInt
                                              (\ b -> if b then 1 else 0) _v))
                                  ((Data.Monoid.<>)
                                     (let
                                        p = Lens.Family2.view
                                              (Data.ProtoLens.Field.field @"vec'observation") _x
                                      in
                                        if Data.Vector.Generic.null p then
                                            Data.Monoid.mempty
                                        else
                                            (Data.Monoid.<>)
                                              (Data.ProtoLens.Encoding.Bytes.putVarInt 74)
                                              ((\ bs
                                                  -> (Data.Monoid.<>)
                                                       (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                          (Prelude.fromIntegral
                                                             (Data.ByteString.length bs)))
                                                       (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                                 (Data.ProtoLens.Encoding.Bytes.runBuilder
                                                    (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                                                       ((Prelude..)
                                                          Data.ProtoLens.Encoding.Bytes.putFixed64
                                                          Data.ProtoLens.Encoding.Bytes.doubleToWord)
                                                       p))))
                                     ((Data.Monoid.<>)
                                        (let
                                           p = Lens.Family2.view
                                                 (Data.ProtoLens.Field.field @"vec'nextObservation")
                                                 _x
                                         in
                                           if Data.Vector.Generic.null p then
                                               Data.Monoid.mempty
                                           else
                                               (Data.Monoid.<>)
                                                 (Data.ProtoLens.Encoding.Bytes.putVarInt 82)
                                                 ((\ bs
                                                     -> (Data.Monoid.<>)
                                                          (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                             (Prelude.fromIntegral
                                                                (Data.ByteString.length bs)))
                                                          (Data.ProtoLens.Encoding.Bytes.putBytes
                                                             bs))
                                                    (Data.ProtoLens.Encoding.Bytes.runBuilder
                                                       (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                                                          ((Prelude..)
                                                             Data.ProtoLens.Encoding.Bytes.putFixed64
                                                             Data.ProtoLens.Encoding.Bytes.doubleToWord)
                                                          p))))
                                        ((Data.Monoid.<>)
                                           (let
                                              _v
                                                = Lens.Family2.view
                                                    (Data.ProtoLens.Field.field @"policyVersion") _x
                                            in
                                              if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                                  Data.Monoid.mempty
                                              else
                                                  (Data.Monoid.<>)
                                                    (Data.ProtoLens.Encoding.Bytes.putVarInt 88)
                                                    (Data.ProtoLens.Encoding.Bytes.putVarInt _v))
                                           ((Data.Monoid.<>)
                                              (let
                                                 _v
                                                   = Lens.Family2.view
                                                       (Data.ProtoLens.Field.field
                                                          @"observationHash")
                                                       _x
                                               in
                                                 if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                                     Data.Monoid.mempty
                                                 else
                                                     (Data.Monoid.<>)
                                                       (Data.ProtoLens.Encoding.Bytes.putVarInt 96)
                                                       ((Prelude..)
                                                          Data.ProtoLens.Encoding.Bytes.putVarInt
                                                          Prelude.fromIntegral _v))
                                              ((Data.Monoid.<>)
                                                 (let
                                                    _v
                                                      = Lens.Family2.view
                                                          (Data.ProtoLens.Field.field
                                                             @"timestampNs")
                                                          _x
                                                  in
                                                    if (Prelude.==)
                                                         _v Data.ProtoLens.fieldDefault then
                                                        Data.Monoid.mempty
                                                    else
                                                        (Data.Monoid.<>)
                                                          (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                             104)
                                                          (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                             _v))
                                                 (Data.ProtoLens.Encoding.Wire.buildFieldSet
                                                    (Lens.Family2.view
                                                       Data.ProtoLens.unknownFields _x))))))))))))))
instance Control.DeepSeq.NFData RlReplayFrame where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_RlReplayFrame'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_RlReplayFrame'experimentHash x__)
                (Control.DeepSeq.deepseq
                   (_RlReplayFrame'replayId x__)
                   (Control.DeepSeq.deepseq
                      (_RlReplayFrame'environment x__)
                      (Control.DeepSeq.deepseq
                         (_RlReplayFrame'episode x__)
                         (Control.DeepSeq.deepseq
                            (_RlReplayFrame'step x__)
                            (Control.DeepSeq.deepseq
                               (_RlReplayFrame'action x__)
                               (Control.DeepSeq.deepseq
                                  (_RlReplayFrame'reward x__)
                                  (Control.DeepSeq.deepseq
                                     (_RlReplayFrame'done x__)
                                     (Control.DeepSeq.deepseq
                                        (_RlReplayFrame'observation x__)
                                        (Control.DeepSeq.deepseq
                                           (_RlReplayFrame'nextObservation x__)
                                           (Control.DeepSeq.deepseq
                                              (_RlReplayFrame'policyVersion x__)
                                              (Control.DeepSeq.deepseq
                                                 (_RlReplayFrame'observationHash x__)
                                                 (Control.DeepSeq.deepseq
                                                    (_RlReplayFrame'timestampNs x__) ())))))))))))))
{- | Fields :

         * 'Proto.Jitml.Rl_Fields.substrate' @:: Lens' StartAlphaZeroRun Data.Text.Text@
         * 'Proto.Jitml.Rl_Fields.experimentHash' @:: Lens' StartAlphaZeroRun Data.Text.Text@
         * 'Proto.Jitml.Rl_Fields.planId' @:: Lens' StartAlphaZeroRun Data.Text.Text@
         * 'Proto.Jitml.Rl_Fields.resolvedPlan' @:: Lens' StartAlphaZeroRun Data.Text.Text@
         * 'Proto.Jitml.Rl_Fields.game' @:: Lens' StartAlphaZeroRun Data.Text.Text@
         * 'Proto.Jitml.Rl_Fields.generations' @:: Lens' StartAlphaZeroRun Data.Word.Word32@
         * 'Proto.Jitml.Rl_Fields.selfPlayGames' @:: Lens' StartAlphaZeroRun Data.Word.Word32@
         * 'Proto.Jitml.Rl_Fields.mctsSimulationsPerMove' @:: Lens' StartAlphaZeroRun Data.Word.Word32@
         * 'Proto.Jitml.Rl_Fields.maxPlies' @:: Lens' StartAlphaZeroRun Data.Word.Word32@
         * 'Proto.Jitml.Rl_Fields.optimizerUpdates' @:: Lens' StartAlphaZeroRun Data.Word.Word32@
         * 'Proto.Jitml.Rl_Fields.arenaGames' @:: Lens' StartAlphaZeroRun Data.Word.Word32@
         * 'Proto.Jitml.Rl_Fields.seed' @:: Lens' StartAlphaZeroRun Data.Word.Word64@ -}
data StartAlphaZeroRun
  = StartAlphaZeroRun'_constructor {_StartAlphaZeroRun'substrate :: !Data.Text.Text,
                                    _StartAlphaZeroRun'experimentHash :: !Data.Text.Text,
                                    _StartAlphaZeroRun'planId :: !Data.Text.Text,
                                    _StartAlphaZeroRun'resolvedPlan :: !Data.Text.Text,
                                    _StartAlphaZeroRun'game :: !Data.Text.Text,
                                    _StartAlphaZeroRun'generations :: !Data.Word.Word32,
                                    _StartAlphaZeroRun'selfPlayGames :: !Data.Word.Word32,
                                    _StartAlphaZeroRun'mctsSimulationsPerMove :: !Data.Word.Word32,
                                    _StartAlphaZeroRun'maxPlies :: !Data.Word.Word32,
                                    _StartAlphaZeroRun'optimizerUpdates :: !Data.Word.Word32,
                                    _StartAlphaZeroRun'arenaGames :: !Data.Word.Word32,
                                    _StartAlphaZeroRun'seed :: !Data.Word.Word64,
                                    _StartAlphaZeroRun'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show StartAlphaZeroRun where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField StartAlphaZeroRun "substrate" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartAlphaZeroRun'substrate
           (\ x__ y__ -> x__ {_StartAlphaZeroRun'substrate = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField StartAlphaZeroRun "experimentHash" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartAlphaZeroRun'experimentHash
           (\ x__ y__ -> x__ {_StartAlphaZeroRun'experimentHash = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField StartAlphaZeroRun "planId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartAlphaZeroRun'planId
           (\ x__ y__ -> x__ {_StartAlphaZeroRun'planId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField StartAlphaZeroRun "resolvedPlan" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartAlphaZeroRun'resolvedPlan
           (\ x__ y__ -> x__ {_StartAlphaZeroRun'resolvedPlan = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField StartAlphaZeroRun "game" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartAlphaZeroRun'game
           (\ x__ y__ -> x__ {_StartAlphaZeroRun'game = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField StartAlphaZeroRun "generations" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartAlphaZeroRun'generations
           (\ x__ y__ -> x__ {_StartAlphaZeroRun'generations = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField StartAlphaZeroRun "selfPlayGames" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartAlphaZeroRun'selfPlayGames
           (\ x__ y__ -> x__ {_StartAlphaZeroRun'selfPlayGames = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField StartAlphaZeroRun "mctsSimulationsPerMove" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartAlphaZeroRun'mctsSimulationsPerMove
           (\ x__ y__
              -> x__ {_StartAlphaZeroRun'mctsSimulationsPerMove = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField StartAlphaZeroRun "maxPlies" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartAlphaZeroRun'maxPlies
           (\ x__ y__ -> x__ {_StartAlphaZeroRun'maxPlies = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField StartAlphaZeroRun "optimizerUpdates" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartAlphaZeroRun'optimizerUpdates
           (\ x__ y__ -> x__ {_StartAlphaZeroRun'optimizerUpdates = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField StartAlphaZeroRun "arenaGames" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartAlphaZeroRun'arenaGames
           (\ x__ y__ -> x__ {_StartAlphaZeroRun'arenaGames = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField StartAlphaZeroRun "seed" Data.Word.Word64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartAlphaZeroRun'seed
           (\ x__ y__ -> x__ {_StartAlphaZeroRun'seed = y__}))
        Prelude.id
instance Data.ProtoLens.Message StartAlphaZeroRun where
  messageName _ = Data.Text.pack "jitml.rl.StartAlphaZeroRun"
  packedMessageDescriptor _
    = "\n\
      \\DC1StartAlphaZeroRun\DC2\FS\n\
      \\tsubstrate\CAN\SOH \SOH(\tR\tsubstrate\DC2'\n\
      \\SIexperiment_hash\CAN\STX \SOH(\tR\SOexperimentHash\DC2\ETB\n\
      \\aplan_id\CAN\ETX \SOH(\tR\ACKplanId\DC2#\n\
      \\rresolved_plan\CAN\EOT \SOH(\tR\fresolvedPlan\DC2\DC2\n\
      \\EOTgame\CAN\ENQ \SOH(\tR\EOTgame\DC2 \n\
      \\vgenerations\CAN\ACK \SOH(\rR\vgenerations\DC2&\n\
      \\SIself_play_games\CAN\a \SOH(\rR\rselfPlayGames\DC29\n\
      \\EMmcts_simulations_per_move\CAN\b \SOH(\rR\SYNmctsSimulationsPerMove\DC2\ESC\n\
      \\tmax_plies\CAN\t \SOH(\rR\bmaxPlies\DC2+\n\
      \\DC1optimizer_updates\CAN\n\
      \ \SOH(\rR\DLEoptimizerUpdates\DC2\US\n\
      \\varena_games\CAN\v \SOH(\rR\n\
      \arenaGames\DC2\DC2\n\
      \\EOTseed\CAN\f \SOH(\EOTR\EOTseed"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        substrate__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "substrate"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"substrate")) ::
              Data.ProtoLens.FieldDescriptor StartAlphaZeroRun
        experimentHash__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "experiment_hash"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"experimentHash")) ::
              Data.ProtoLens.FieldDescriptor StartAlphaZeroRun
        planId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "plan_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"planId")) ::
              Data.ProtoLens.FieldDescriptor StartAlphaZeroRun
        resolvedPlan__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "resolved_plan"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"resolvedPlan")) ::
              Data.ProtoLens.FieldDescriptor StartAlphaZeroRun
        game__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "game"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"game")) ::
              Data.ProtoLens.FieldDescriptor StartAlphaZeroRun
        generations__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "generations"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"generations")) ::
              Data.ProtoLens.FieldDescriptor StartAlphaZeroRun
        selfPlayGames__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "self_play_games"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"selfPlayGames")) ::
              Data.ProtoLens.FieldDescriptor StartAlphaZeroRun
        mctsSimulationsPerMove__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "mcts_simulations_per_move"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"mctsSimulationsPerMove")) ::
              Data.ProtoLens.FieldDescriptor StartAlphaZeroRun
        maxPlies__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "max_plies"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"maxPlies")) ::
              Data.ProtoLens.FieldDescriptor StartAlphaZeroRun
        optimizerUpdates__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "optimizer_updates"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"optimizerUpdates")) ::
              Data.ProtoLens.FieldDescriptor StartAlphaZeroRun
        arenaGames__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "arena_games"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"arenaGames")) ::
              Data.ProtoLens.FieldDescriptor StartAlphaZeroRun
        seed__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "seed"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word64)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"seed")) ::
              Data.ProtoLens.FieldDescriptor StartAlphaZeroRun
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, substrate__field_descriptor),
           (Data.ProtoLens.Tag 2, experimentHash__field_descriptor),
           (Data.ProtoLens.Tag 3, planId__field_descriptor),
           (Data.ProtoLens.Tag 4, resolvedPlan__field_descriptor),
           (Data.ProtoLens.Tag 5, game__field_descriptor),
           (Data.ProtoLens.Tag 6, generations__field_descriptor),
           (Data.ProtoLens.Tag 7, selfPlayGames__field_descriptor),
           (Data.ProtoLens.Tag 8, mctsSimulationsPerMove__field_descriptor),
           (Data.ProtoLens.Tag 9, maxPlies__field_descriptor),
           (Data.ProtoLens.Tag 10, optimizerUpdates__field_descriptor),
           (Data.ProtoLens.Tag 11, arenaGames__field_descriptor),
           (Data.ProtoLens.Tag 12, seed__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _StartAlphaZeroRun'_unknownFields
        (\ x__ y__ -> x__ {_StartAlphaZeroRun'_unknownFields = y__})
  defMessage
    = StartAlphaZeroRun'_constructor
        {_StartAlphaZeroRun'substrate = Data.ProtoLens.fieldDefault,
         _StartAlphaZeroRun'experimentHash = Data.ProtoLens.fieldDefault,
         _StartAlphaZeroRun'planId = Data.ProtoLens.fieldDefault,
         _StartAlphaZeroRun'resolvedPlan = Data.ProtoLens.fieldDefault,
         _StartAlphaZeroRun'game = Data.ProtoLens.fieldDefault,
         _StartAlphaZeroRun'generations = Data.ProtoLens.fieldDefault,
         _StartAlphaZeroRun'selfPlayGames = Data.ProtoLens.fieldDefault,
         _StartAlphaZeroRun'mctsSimulationsPerMove = Data.ProtoLens.fieldDefault,
         _StartAlphaZeroRun'maxPlies = Data.ProtoLens.fieldDefault,
         _StartAlphaZeroRun'optimizerUpdates = Data.ProtoLens.fieldDefault,
         _StartAlphaZeroRun'arenaGames = Data.ProtoLens.fieldDefault,
         _StartAlphaZeroRun'seed = Data.ProtoLens.fieldDefault,
         _StartAlphaZeroRun'_unknownFields = []}
  parseMessage
    = let
        loop ::
          StartAlphaZeroRun
          -> Data.ProtoLens.Encoding.Bytes.Parser StartAlphaZeroRun
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
                                       "substrate"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"substrate") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "experiment_hash"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"experimentHash") y x)
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "plan_id"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"planId") y x)
                        34
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "resolved_plan"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"resolvedPlan") y x)
                        42
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "game"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"game") y x)
                        48
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "generations"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"generations") y x)
                        56
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "self_play_games"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"selfPlayGames") y x)
                        64
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "mcts_simulations_per_move"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"mctsSimulationsPerMove") y x)
                        72
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "max_plies"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"maxPlies") y x)
                        80
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "optimizer_updates"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"optimizerUpdates") y x)
                        88
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "arena_games"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"arenaGames") y x)
                        96
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       Data.ProtoLens.Encoding.Bytes.getVarInt "seed"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"seed") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "StartAlphaZeroRun"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"substrate") _x
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
                         (Data.ProtoLens.Field.field @"experimentHash") _x
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
                      _v = Lens.Family2.view (Data.ProtoLens.Field.field @"planId") _x
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
                           = Lens.Family2.view (Data.ProtoLens.Field.field @"resolvedPlan") _x
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
                         (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"game") _x
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
                                 = Lens.Family2.view (Data.ProtoLens.Field.field @"generations") _x
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
                                        (Data.ProtoLens.Field.field @"selfPlayGames") _x
                                in
                                  if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                      Data.Monoid.mempty
                                  else
                                      (Data.Monoid.<>)
                                        (Data.ProtoLens.Encoding.Bytes.putVarInt 56)
                                        ((Prelude..)
                                           Data.ProtoLens.Encoding.Bytes.putVarInt
                                           Prelude.fromIntegral _v))
                               ((Data.Monoid.<>)
                                  (let
                                     _v
                                       = Lens.Family2.view
                                           (Data.ProtoLens.Field.field @"mctsSimulationsPerMove") _x
                                   in
                                     if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                         Data.Monoid.mempty
                                     else
                                         (Data.Monoid.<>)
                                           (Data.ProtoLens.Encoding.Bytes.putVarInt 64)
                                           ((Prelude..)
                                              Data.ProtoLens.Encoding.Bytes.putVarInt
                                              Prelude.fromIntegral _v))
                                  ((Data.Monoid.<>)
                                     (let
                                        _v
                                          = Lens.Family2.view
                                              (Data.ProtoLens.Field.field @"maxPlies") _x
                                      in
                                        if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                            Data.Monoid.mempty
                                        else
                                            (Data.Monoid.<>)
                                              (Data.ProtoLens.Encoding.Bytes.putVarInt 72)
                                              ((Prelude..)
                                                 Data.ProtoLens.Encoding.Bytes.putVarInt
                                                 Prelude.fromIntegral _v))
                                     ((Data.Monoid.<>)
                                        (let
                                           _v
                                             = Lens.Family2.view
                                                 (Data.ProtoLens.Field.field @"optimizerUpdates") _x
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
                                                    (Data.ProtoLens.Field.field @"arenaGames") _x
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
                                                       (Data.ProtoLens.Field.field @"seed") _x
                                               in
                                                 if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                                     Data.Monoid.mempty
                                                 else
                                                     (Data.Monoid.<>)
                                                       (Data.ProtoLens.Encoding.Bytes.putVarInt 96)
                                                       (Data.ProtoLens.Encoding.Bytes.putVarInt _v))
                                              (Data.ProtoLens.Encoding.Wire.buildFieldSet
                                                 (Lens.Family2.view
                                                    Data.ProtoLens.unknownFields _x)))))))))))))
instance Control.DeepSeq.NFData StartAlphaZeroRun where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_StartAlphaZeroRun'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_StartAlphaZeroRun'substrate x__)
                (Control.DeepSeq.deepseq
                   (_StartAlphaZeroRun'experimentHash x__)
                   (Control.DeepSeq.deepseq
                      (_StartAlphaZeroRun'planId x__)
                      (Control.DeepSeq.deepseq
                         (_StartAlphaZeroRun'resolvedPlan x__)
                         (Control.DeepSeq.deepseq
                            (_StartAlphaZeroRun'game x__)
                            (Control.DeepSeq.deepseq
                               (_StartAlphaZeroRun'generations x__)
                               (Control.DeepSeq.deepseq
                                  (_StartAlphaZeroRun'selfPlayGames x__)
                                  (Control.DeepSeq.deepseq
                                     (_StartAlphaZeroRun'mctsSimulationsPerMove x__)
                                     (Control.DeepSeq.deepseq
                                        (_StartAlphaZeroRun'maxPlies x__)
                                        (Control.DeepSeq.deepseq
                                           (_StartAlphaZeroRun'optimizerUpdates x__)
                                           (Control.DeepSeq.deepseq
                                              (_StartAlphaZeroRun'arenaGames x__)
                                              (Control.DeepSeq.deepseq
                                                 (_StartAlphaZeroRun'seed x__) ()))))))))))))
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
    \\reval_episodes\CAN\a \SOH(\rR\fevalEpisodes\"\176\ETX\n\
    \\DC1StartAlphaZeroRun\DC2\FS\n\
    \\tsubstrate\CAN\SOH \SOH(\tR\tsubstrate\DC2'\n\
    \\SIexperiment_hash\CAN\STX \SOH(\tR\SOexperimentHash\DC2\ETB\n\
    \\aplan_id\CAN\ETX \SOH(\tR\ACKplanId\DC2#\n\
    \\rresolved_plan\CAN\EOT \SOH(\tR\fresolvedPlan\DC2\DC2\n\
    \\EOTgame\CAN\ENQ \SOH(\tR\EOTgame\DC2 \n\
    \\vgenerations\CAN\ACK \SOH(\rR\vgenerations\DC2&\n\
    \\SIself_play_games\CAN\a \SOH(\rR\rselfPlayGames\DC29\n\
    \\EMmcts_simulations_per_move\CAN\b \SOH(\rR\SYNmctsSimulationsPerMove\DC2\ESC\n\
    \\tmax_plies\CAN\t \SOH(\rR\bmaxPlies\DC2+\n\
    \\DC1optimizer_updates\CAN\n\
    \ \SOH(\rR\DLEoptimizerUpdates\DC2\US\n\
    \\varena_games\CAN\v \SOH(\rR\n\
    \arenaGames\DC2\DC2\n\
    \\EOTseed\CAN\f \SOH(\EOTR\EOTseed\"J\n\
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
    \\ftimestamp_ns\CAN\ENQ \SOH(\EOTR\vtimestampNs\"\190\SOH\n\
    \\DLECheckpointDoneRL\DC2'\n\
    \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2!\n\
    \\fmanifest_sha\CAN\STX \SOH(\tR\vmanifestSha\DC2\DC2\n\
    \\EOTstep\CAN\ETX \SOH(\EOTR\EOTstep\DC2\US\n\
    \\vpointer_key\CAN\EOT \SOH(\tR\n\
    \pointerKey\DC2)\n\
    \\DLEprotocol_version\CAN\ENQ \SOH(\rR\SIprotocolVersion\"\177\SOH\n\
    \\EMCompletedCheckpointDoneRL\DC2)\n\
    \\DLEprotocol_version\CAN\SOH \SOH(\rR\SIprotocolVersion\DC2:\n\
    \\n\
    \checkpoint\CAN\STX \SOH(\v2\SUB.jitml.rl.CheckpointDoneRLR\n\
    \checkpoint\DC2-\n\
    \\DC2completed_training\CAN\ETX \SOH(\fR\DC1completedTraining\"\132\SOH\n\
    \\fMetricUpdate\DC2'\n\
    \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2\DC2\n\
    \\EOTname\CAN\STX \SOH(\tR\EOTname\DC2\DC4\n\
    \\ENQvalue\CAN\ETX \SOH(\SOHR\ENQvalue\DC2!\n\
    \\ftimestamp_ns\CAN\EOT \SOH(\EOTR\vtimestampNs\"\185\SOH\n\
    \\DC3GenerationCompleted\DC2\ETB\n\
    \\aplan_id\CAN\SOH \SOH(\tR\ACKplanId\DC2'\n\
    \\SIexperiment_hash\CAN\STX \SOH(\tR\SOexperimentHash\DC2\RS\n\
    \\n\
    \generation\CAN\ETX \SOH(\rR\n\
    \generation\DC2&\n\
    \\SIself_play_games\CAN\EOT \SOH(\rR\rselfPlayGames\DC2\CAN\n\
    \\asamples\CAN\ENQ \SOH(\EOTR\asamples\"\142\SOH\n\
    \\SOArenaCompleted\DC2\ETB\n\
    \\aplan_id\CAN\SOH \SOH(\tR\ACKplanId\DC2'\n\
    \\SIexperiment_hash\CAN\STX \SOH(\tR\SOexperimentHash\DC2\US\n\
    \\varena_games\CAN\ETX \SOH(\rR\n\
    \arenaGames\DC2\EM\n\
    \\bwin_rate\CAN\EOT \SOH(\SOHR\awinRate\"\151\ETX\n\
    \\DLERlAnimationFrame\DC2'\n\
    \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2 \n\
    \\venvironment\CAN\STX \SOH(\tR\venvironment\DC2\CAN\n\
    \\aepisode\CAN\ETX \SOH(\rR\aepisode\DC2\DC2\n\
    \\EOTstep\CAN\EOT \SOH(\rR\EOTstep\DC2\SYN\n\
    \\ACKreward\CAN\ENQ \SOH(\SOHR\ACKreward\DC2\DC2\n\
    \\EOTdone\CAN\ACK \SOH(\bR\EOTdone\DC2\SYN\n\
    \\ACKaction\CAN\a \SOH(\rR\ACKaction\DC2 \n\
    \\vobservation\CAN\b \ETX(\SOHR\vobservation\DC21\n\
    \\DC4action_probabilities\CAN\t \ETX(\SOHR\DC3actionProbabilities\DC2)\n\
    \\DLEobservation_hash\CAN\n\
    \ \SOH(\rR\SIobservationHash\DC2#\n\
    \\rreplay_cursor\CAN\v \SOH(\EOTR\freplayCursor\DC2!\n\
    \\ftimestamp_ns\CAN\f \SOH(\EOTR\vtimestampNs\"\171\ETX\n\
    \\rRlReplayFrame\DC2'\n\
    \\SIexperiment_hash\CAN\SOH \SOH(\tR\SOexperimentHash\DC2\ESC\n\
    \\treplay_id\CAN\STX \SOH(\tR\breplayId\DC2 \n\
    \\venvironment\CAN\ETX \SOH(\tR\venvironment\DC2\CAN\n\
    \\aepisode\CAN\EOT \SOH(\rR\aepisode\DC2\DC2\n\
    \\EOTstep\CAN\ENQ \SOH(\rR\EOTstep\DC2\SYN\n\
    \\ACKaction\CAN\ACK \SOH(\rR\ACKaction\DC2\SYN\n\
    \\ACKreward\CAN\a \SOH(\SOHR\ACKreward\DC2\DC2\n\
    \\EOTdone\CAN\b \SOH(\bR\EOTdone\DC2 \n\
    \\vobservation\CAN\t \ETX(\SOHR\vobservation\DC2)\n\
    \\DLEnext_observation\CAN\n\
    \ \ETX(\SOHR\SInextObservation\DC2%\n\
    \\SOpolicy_version\CAN\v \SOH(\EOTR\rpolicyVersion\DC2)\n\
    \\DLEobservation_hash\CAN\f \SOH(\rR\SIobservationHash\DC2!\n\
    \\ftimestamp_ns\CAN\r \SOH(\EOTR\vtimestampNs\"\181\SOH\n\
    \\tRlCommand\DC2,\n\
    \\ENQstart\CAN\SOH \SOH(\v2\DC4.jitml.rl.StartRLRunH\NULR\ENQstart\DC2)\n\
    \\EOTstop\CAN\STX \SOH(\v2\DC3.jitml.rl.StopRLRunH\NULR\EOTstop\DC2G\n\
    \\DLEstart_alpha_zero\CAN\ETX \SOH(\v2\ESC.jitml.rl.StartAlphaZeroRunH\NULR\SOstartAlphaZeroB\ACK\n\
    \\EOTbody\"\192\EOT\n\
    \\aRlEvent\DC21\n\
    \\aepisode\CAN\SOH \SOH(\v2\NAK.jitml.rl.EpisodeDoneH\NULR\aepisode\DC2(\n\
    \\EOTeval\CAN\STX \SOH(\v2\DC2.jitml.rl.EvalDoneH\NULR\EOTeval\DC2<\n\
    \\n\
    \checkpoint\CAN\ETX \SOH(\v2\SUB.jitml.rl.CheckpointDoneRLH\NULR\n\
    \checkpoint\DC20\n\
    \\ACKmetric\CAN\EOT \SOH(\v2\SYN.jitml.rl.MetricUpdateH\NULR\ACKmetric\DC2:\n\
    \\tanimation\CAN\ENQ \SOH(\v2\SUB.jitml.rl.RlAnimationFrameH\NULR\tanimation\DC21\n\
    \\ACKreplay\CAN\ACK \SOH(\v2\ETB.jitml.rl.RlReplayFrameH\NULR\ACKreplay\DC2R\n\
    \\DC4generation_completed\CAN\a \SOH(\v2\GS.jitml.rl.GenerationCompletedH\NULR\DC3generationCompleted\DC2C\n\
    \\SIarena_completed\CAN\b \SOH(\v2\CAN.jitml.rl.ArenaCompletedH\NULR\SOarenaCompleted\DC2X\n\
    \\DC4completed_checkpoint\CAN\t \SOH(\v2#.jitml.rl.CompletedCheckpointDoneRLH\NULR\DC3completedCheckpointB\ACK\n\
    \\EOTbodyJ\130/\n\
    \\a\DC2\ENQ\NUL\NUL\146\SOH\SOH\n\
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
    \\148\STX\n\
    \\STX\EOT\SOH\DC2\EOT\DC4\NUL!\SOH\SUB\135\STX AlphaZero uses generation-, game-, search-, and update-indexed budgets that\n\
    \ are not interchangeable with StartRLRun's environment-step budget. Keeping\n\
    \ it as a distinct command body prevents workers from reinterpreting a generic\n\
    \ max_steps value for self-play.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\SOH\SOH\DC2\ETX\DC4\b\EM\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\NUL\DC2\ETX\NAK\STX'\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ENQ\DC2\ETX\NAK\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\SOH\DC2\ETX\NAK\t\DC2\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ETX\DC2\ETX\NAK%&\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\SOH\DC2\ETX\SYN\STX'\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\ENQ\DC2\ETX\SYN\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\SOH\DC2\ETX\SYN\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\ETX\DC2\ETX\SYN%&\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\STX\DC2\ETX\ETB\STX'\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\STX\ENQ\DC2\ETX\ETB\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\STX\SOH\DC2\ETX\ETB\t\DLE\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\STX\ETX\DC2\ETX\ETB%&\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\ETX\DC2\ETX\CAN\STX'\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\ETX\ENQ\DC2\ETX\CAN\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\ETX\SOH\DC2\ETX\CAN\t\SYN\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\ETX\ETX\DC2\ETX\CAN%&\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\EOT\DC2\ETX\EM\STX'\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\EOT\ENQ\DC2\ETX\EM\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\EOT\SOH\DC2\ETX\EM\t\r\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\EOT\ETX\DC2\ETX\EM%&\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\ENQ\DC2\ETX\SUB\STX'\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\ENQ\ENQ\DC2\ETX\SUB\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\ENQ\SOH\DC2\ETX\SUB\t\DC4\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\ENQ\ETX\DC2\ETX\SUB%&\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\ACK\DC2\ETX\ESC\STX'\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\ACK\ENQ\DC2\ETX\ESC\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\ACK\SOH\DC2\ETX\ESC\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\ACK\ETX\DC2\ETX\ESC%&\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\a\DC2\ETX\FS\STX'\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\a\ENQ\DC2\ETX\FS\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\a\SOH\DC2\ETX\FS\t\"\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\a\ETX\DC2\ETX\FS%&\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\b\DC2\ETX\GS\STX'\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\b\ENQ\DC2\ETX\GS\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\b\SOH\DC2\ETX\GS\t\DC2\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\b\ETX\DC2\ETX\GS%&\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\t\DC2\ETX\RS\STX(\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\t\ENQ\DC2\ETX\RS\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\t\SOH\DC2\ETX\RS\t\SUB\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\t\ETX\DC2\ETX\RS%'\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\n\
    \\DC2\ETX\US\STX(\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\n\
    \\ENQ\DC2\ETX\US\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\n\
    \\SOH\DC2\ETX\US\t\DC4\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\n\
    \\ETX\DC2\ETX\US%'\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\v\DC2\ETX \STX(\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\v\ENQ\DC2\ETX \STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\v\SOH\DC2\ETX \t\r\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\v\ETX\DC2\ETX %'\n\
    \\n\
    \\n\
    \\STX\EOT\STX\DC2\EOT#\NUL&\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\STX\SOH\DC2\ETX#\b\DC1\n\
    \\v\n\
    \\EOT\EOT\STX\STX\NUL\DC2\ETX$\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\NUL\ENQ\DC2\ETX$\STX\b\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\NUL\SOH\DC2\ETX$\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\NUL\ETX\DC2\ETX$\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\STX\STX\SOH\DC2\ETX%\STX\DC3\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\SOH\ENQ\DC2\ETX%\STX\ACK\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\SOH\SOH\DC2\ETX%\t\SO\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\SOH\ETX\DC2\ETX%\DC1\DC2\n\
    \\n\
    \\n\
    \\STX\EOT\ETX\DC2\EOT(\NUL.\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\ETX\SOH\DC2\ETX(\b\DC3\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\NUL\DC2\ETX)\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\NUL\ENQ\DC2\ETX)\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\NUL\SOH\DC2\ETX)\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\NUL\ETX\DC2\ETX)\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\SOH\DC2\ETX*\STX\NAK\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\SOH\ENQ\DC2\ETX*\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\SOH\SOH\DC2\ETX*\t\DLE\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\SOH\ETX\DC2\ETX*\DC3\DC4\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\STX\DC2\ETX+\STX\DC4\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\STX\ENQ\DC2\ETX+\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\STX\SOH\DC2\ETX+\t\SI\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\STX\ETX\DC2\ETX+\DC2\DC3\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\ETX\DC2\ETX,\STX\DC3\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ETX\ENQ\DC2\ETX,\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ETX\SOH\DC2\ETX,\t\SO\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ETX\ETX\DC2\ETX,\DC1\DC2\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\EOT\DC2\ETX-\STX\SUB\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\EOT\ENQ\DC2\ETX-\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\EOT\SOH\DC2\ETX-\t\NAK\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\EOT\ETX\DC2\ETX-\CAN\EM\n\
    \\n\
    \\n\
    \\STX\EOT\EOT\DC2\EOT0\NUL6\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\EOT\SOH\DC2\ETX0\b\DLE\n\
    \\v\n\
    \\EOT\EOT\EOT\STX\NUL\DC2\ETX1\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\NUL\ENQ\DC2\ETX1\STX\b\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\NUL\SOH\DC2\ETX1\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\NUL\ETX\DC2\ETX1\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\EOT\STX\SOH\DC2\ETX2\STX\DC3\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\SOH\ENQ\DC2\ETX2\STX\b\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\SOH\SOH\DC2\ETX2\t\SO\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\SOH\ETX\DC2\ETX2\DC1\DC2\n\
    \\v\n\
    \\EOT\EOT\EOT\STX\STX\DC2\ETX3\STX\CAN\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\STX\ENQ\DC2\ETX3\STX\b\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\STX\SOH\DC2\ETX3\t\DC3\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\STX\ETX\DC2\ETX3\SYN\ETB\n\
    \\v\n\
    \\EOT\EOT\EOT\STX\ETX\DC2\ETX4\STX\CAN\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\ETX\ENQ\DC2\ETX4\STX\b\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\ETX\SOH\DC2\ETX4\t\DC3\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\ETX\ETX\DC2\ETX4\SYN\ETB\n\
    \\v\n\
    \\EOT\EOT\EOT\STX\EOT\DC2\ETX5\STX\SUB\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\EOT\ENQ\DC2\ETX5\STX\b\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\EOT\SOH\DC2\ETX5\t\NAK\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\EOT\ETX\DC2\ETX5\CAN\EM\n\
    \\n\
    \\n\
    \\STX\EOT\ENQ\DC2\EOT8\NUL>\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\ENQ\SOH\DC2\ETX8\b\CAN\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\NUL\DC2\ETX9\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\NUL\ENQ\DC2\ETX9\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\NUL\SOH\DC2\ETX9\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\NUL\ETX\DC2\ETX9\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\SOH\DC2\ETX:\STX\SUB\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\SOH\ENQ\DC2\ETX:\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\SOH\SOH\DC2\ETX:\t\NAK\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\SOH\ETX\DC2\ETX:\CAN\EM\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\STX\DC2\ETX;\STX\DC2\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\STX\ENQ\DC2\ETX;\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\STX\SOH\DC2\ETX;\t\r\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\STX\ETX\DC2\ETX;\DLE\DC1\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\ETX\DC2\ETX<\STX\EM\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\ETX\ENQ\DC2\ETX<\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\ETX\SOH\DC2\ETX<\t\DC4\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\ETX\ETX\DC2\ETX<\ETB\CAN\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\EOT\DC2\ETX=\STX\RS\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\EOT\ENQ\DC2\ETX=\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\EOT\SOH\DC2\ETX=\t\EM\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\EOT\ETX\DC2\ETX=\FS\GS\n\
    \\n\
    \\n\
    \\STX\EOT\ACK\DC2\EOT@\NULD\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\ACK\SOH\DC2\ETX@\b!\n\
    \\v\n\
    \\EOT\EOT\ACK\STX\NUL\DC2\ETXA\STX\RS\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\NUL\ENQ\DC2\ETXA\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\NUL\SOH\DC2\ETXA\t\EM\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\NUL\ETX\DC2\ETXA\FS\GS\n\
    \\v\n\
    \\EOT\EOT\ACK\STX\SOH\DC2\ETXB\STX\"\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\SOH\ACK\DC2\ETXB\STX\DC2\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\SOH\SOH\DC2\ETXB\DC3\GS\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\SOH\ETX\DC2\ETXB !\n\
    \\v\n\
    \\EOT\EOT\ACK\STX\STX\DC2\ETXC\STX\US\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\STX\ENQ\DC2\ETXC\STX\a\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\STX\SOH\DC2\ETXC\b\SUB\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\STX\ETX\DC2\ETXC\GS\RS\n\
    \\n\
    \\n\
    \\STX\EOT\a\DC2\EOTF\NULK\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\a\SOH\DC2\ETXF\b\DC4\n\
    \\v\n\
    \\EOT\EOT\a\STX\NUL\DC2\ETXG\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\a\STX\NUL\ENQ\DC2\ETXG\STX\b\n\
    \\f\n\
    \\ENQ\EOT\a\STX\NUL\SOH\DC2\ETXG\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\a\STX\NUL\ETX\DC2\ETXG\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\a\STX\SOH\DC2\ETXH\STX\DC2\n\
    \\f\n\
    \\ENQ\EOT\a\STX\SOH\ENQ\DC2\ETXH\STX\b\n\
    \\f\n\
    \\ENQ\EOT\a\STX\SOH\SOH\DC2\ETXH\t\r\n\
    \\f\n\
    \\ENQ\EOT\a\STX\SOH\ETX\DC2\ETXH\DLE\DC1\n\
    \\v\n\
    \\EOT\EOT\a\STX\STX\DC2\ETXI\STX\DC3\n\
    \\f\n\
    \\ENQ\EOT\a\STX\STX\ENQ\DC2\ETXI\STX\b\n\
    \\f\n\
    \\ENQ\EOT\a\STX\STX\SOH\DC2\ETXI\t\SO\n\
    \\f\n\
    \\ENQ\EOT\a\STX\STX\ETX\DC2\ETXI\DC1\DC2\n\
    \\v\n\
    \\EOT\EOT\a\STX\ETX\DC2\ETXJ\STX\SUB\n\
    \\f\n\
    \\ENQ\EOT\a\STX\ETX\ENQ\DC2\ETXJ\STX\b\n\
    \\f\n\
    \\ENQ\EOT\a\STX\ETX\SOH\DC2\ETXJ\t\NAK\n\
    \\f\n\
    \\ENQ\EOT\a\STX\ETX\ETX\DC2\ETXJ\CAN\EM\n\
    \\185\SOH\n\
    \\STX\EOT\b\DC2\EOTP\NULV\SOH\SUB\172\SOH Plan-correlated AlphaZero evidence. Generic RL events remain unchanged;\n\
    \ these shapes carry the exact generation and arena keys needed by the\n\
    \ AlphaZero contract reducer.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\b\SOH\DC2\ETXP\b\ESC\n\
    \\v\n\
    \\EOT\EOT\b\STX\NUL\DC2\ETXQ\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\b\STX\NUL\ENQ\DC2\ETXQ\STX\b\n\
    \\f\n\
    \\ENQ\EOT\b\STX\NUL\SOH\DC2\ETXQ\t\DLE\n\
    \\f\n\
    \\ENQ\EOT\b\STX\NUL\ETX\DC2\ETXQ\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\b\STX\SOH\DC2\ETXR\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\b\STX\SOH\ENQ\DC2\ETXR\STX\b\n\
    \\f\n\
    \\ENQ\EOT\b\STX\SOH\SOH\DC2\ETXR\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\b\STX\SOH\ETX\DC2\ETXR\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\b\STX\STX\DC2\ETXS\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\b\STX\STX\ENQ\DC2\ETXS\STX\b\n\
    \\f\n\
    \\ENQ\EOT\b\STX\STX\SOH\DC2\ETXS\t\DC3\n\
    \\f\n\
    \\ENQ\EOT\b\STX\STX\ETX\DC2\ETXS\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\b\STX\ETX\DC2\ETXT\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\b\STX\ETX\ENQ\DC2\ETXT\STX\b\n\
    \\f\n\
    \\ENQ\EOT\b\STX\ETX\SOH\DC2\ETXT\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\b\STX\ETX\ETX\DC2\ETXT\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\b\STX\EOT\DC2\ETXU\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\b\STX\EOT\ENQ\DC2\ETXU\STX\b\n\
    \\f\n\
    \\ENQ\EOT\b\STX\EOT\SOH\DC2\ETXU\t\DLE\n\
    \\f\n\
    \\ENQ\EOT\b\STX\EOT\ETX\DC2\ETXU\ESC\FS\n\
    \\n\
    \\n\
    \\STX\EOT\t\DC2\EOTX\NUL]\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\t\SOH\DC2\ETXX\b\SYN\n\
    \\v\n\
    \\EOT\EOT\t\STX\NUL\DC2\ETXY\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\t\STX\NUL\ENQ\DC2\ETXY\STX\b\n\
    \\f\n\
    \\ENQ\EOT\t\STX\NUL\SOH\DC2\ETXY\t\DLE\n\
    \\f\n\
    \\ENQ\EOT\t\STX\NUL\ETX\DC2\ETXY\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\t\STX\SOH\DC2\ETXZ\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\t\STX\SOH\ENQ\DC2\ETXZ\STX\b\n\
    \\f\n\
    \\ENQ\EOT\t\STX\SOH\SOH\DC2\ETXZ\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\t\STX\SOH\ETX\DC2\ETXZ\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\t\STX\STX\DC2\ETX[\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\t\STX\STX\ENQ\DC2\ETX[\STX\b\n\
    \\f\n\
    \\ENQ\EOT\t\STX\STX\SOH\DC2\ETX[\t\DC4\n\
    \\f\n\
    \\ENQ\EOT\t\STX\STX\ETX\DC2\ETX[\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\t\STX\ETX\DC2\ETX\\\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\t\STX\ETX\ENQ\DC2\ETX\\\STX\b\n\
    \\f\n\
    \\ENQ\EOT\t\STX\ETX\SOH\DC2\ETX\\\t\DC1\n\
    \\f\n\
    \\ENQ\EOT\t\STX\ETX\ETX\DC2\ETX\\\ESC\FS\n\
    \\n\
    \\n\
    \\STX\EOT\n\
    \\DC2\EOT_\NULl\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\n\
    \\SOH\DC2\ETX_\b\CAN\n\
    \\v\n\
    \\EOT\EOT\n\
    \\STX\NUL\DC2\ETX`\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\NUL\ENQ\DC2\ETX`\STX\b\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\NUL\SOH\DC2\ETX`\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\NUL\ETX\DC2\ETX`\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\n\
    \\STX\SOH\DC2\ETXa\STX\EM\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\SOH\ENQ\DC2\ETXa\STX\b\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\SOH\SOH\DC2\ETXa\t\DC4\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\SOH\ETX\DC2\ETXa\ETB\CAN\n\
    \\v\n\
    \\EOT\EOT\n\
    \\STX\STX\DC2\ETXb\STX\NAK\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\STX\ENQ\DC2\ETXb\STX\b\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\STX\SOH\DC2\ETXb\t\DLE\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\STX\ETX\DC2\ETXb\DC3\DC4\n\
    \\v\n\
    \\EOT\EOT\n\
    \\STX\ETX\DC2\ETXc\STX\DC2\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\ETX\ENQ\DC2\ETXc\STX\b\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\ETX\SOH\DC2\ETXc\t\r\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\ETX\ETX\DC2\ETXc\DLE\DC1\n\
    \\v\n\
    \\EOT\EOT\n\
    \\STX\EOT\DC2\ETXd\STX\DC4\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\EOT\ENQ\DC2\ETXd\STX\b\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\EOT\SOH\DC2\ETXd\t\SI\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\EOT\ETX\DC2\ETXd\DC2\DC3\n\
    \\v\n\
    \\EOT\EOT\n\
    \\STX\ENQ\DC2\ETXe\STX\DLE\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\ENQ\ENQ\DC2\ETXe\STX\ACK\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\ENQ\SOH\DC2\ETXe\a\v\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\ENQ\ETX\DC2\ETXe\SO\SI\n\
    \\v\n\
    \\EOT\EOT\n\
    \\STX\ACK\DC2\ETXf\STX\DC4\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\ACK\ENQ\DC2\ETXf\STX\b\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\ACK\SOH\DC2\ETXf\t\SI\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\ACK\ETX\DC2\ETXf\DC2\DC3\n\
    \\v\n\
    \\EOT\EOT\n\
    \\STX\a\DC2\ETXg\STX\"\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\a\EOT\DC2\ETXg\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\a\ENQ\DC2\ETXg\v\DC1\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\a\SOH\DC2\ETXg\DC2\GS\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\a\ETX\DC2\ETXg !\n\
    \\v\n\
    \\EOT\EOT\n\
    \\STX\b\DC2\ETXh\STX+\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\b\EOT\DC2\ETXh\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\b\ENQ\DC2\ETXh\v\DC1\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\b\SOH\DC2\ETXh\DC2&\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\b\ETX\DC2\ETXh)*\n\
    \\v\n\
    \\EOT\EOT\n\
    \\STX\t\DC2\ETXi\STX\US\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\t\ENQ\DC2\ETXi\STX\b\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\t\SOH\DC2\ETXi\t\EM\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\t\ETX\DC2\ETXi\FS\RS\n\
    \\v\n\
    \\EOT\EOT\n\
    \\STX\n\
    \\DC2\ETXj\STX\FS\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\n\
    \\ENQ\DC2\ETXj\STX\b\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\n\
    \\SOH\DC2\ETXj\t\SYN\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\n\
    \\ETX\DC2\ETXj\EM\ESC\n\
    \\v\n\
    \\EOT\EOT\n\
    \\STX\v\DC2\ETXk\STX\ESC\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\v\ENQ\DC2\ETXk\STX\b\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\v\SOH\DC2\ETXk\t\NAK\n\
    \\f\n\
    \\ENQ\EOT\n\
    \\STX\v\ETX\DC2\ETXk\CAN\SUB\n\
    \\n\
    \\n\
    \\STX\EOT\v\DC2\EOTn\NUL|\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\v\SOH\DC2\ETXn\b\NAK\n\
    \\v\n\
    \\EOT\EOT\v\STX\NUL\DC2\ETXo\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\v\STX\NUL\ENQ\DC2\ETXo\STX\b\n\
    \\f\n\
    \\ENQ\EOT\v\STX\NUL\SOH\DC2\ETXo\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\v\STX\NUL\ETX\DC2\ETXo\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\v\STX\SOH\DC2\ETXp\STX\ETB\n\
    \\f\n\
    \\ENQ\EOT\v\STX\SOH\ENQ\DC2\ETXp\STX\b\n\
    \\f\n\
    \\ENQ\EOT\v\STX\SOH\SOH\DC2\ETXp\t\DC2\n\
    \\f\n\
    \\ENQ\EOT\v\STX\SOH\ETX\DC2\ETXp\NAK\SYN\n\
    \\v\n\
    \\EOT\EOT\v\STX\STX\DC2\ETXq\STX\EM\n\
    \\f\n\
    \\ENQ\EOT\v\STX\STX\ENQ\DC2\ETXq\STX\b\n\
    \\f\n\
    \\ENQ\EOT\v\STX\STX\SOH\DC2\ETXq\t\DC4\n\
    \\f\n\
    \\ENQ\EOT\v\STX\STX\ETX\DC2\ETXq\ETB\CAN\n\
    \\v\n\
    \\EOT\EOT\v\STX\ETX\DC2\ETXr\STX\NAK\n\
    \\f\n\
    \\ENQ\EOT\v\STX\ETX\ENQ\DC2\ETXr\STX\b\n\
    \\f\n\
    \\ENQ\EOT\v\STX\ETX\SOH\DC2\ETXr\t\DLE\n\
    \\f\n\
    \\ENQ\EOT\v\STX\ETX\ETX\DC2\ETXr\DC3\DC4\n\
    \\v\n\
    \\EOT\EOT\v\STX\EOT\DC2\ETXs\STX\DC2\n\
    \\f\n\
    \\ENQ\EOT\v\STX\EOT\ENQ\DC2\ETXs\STX\b\n\
    \\f\n\
    \\ENQ\EOT\v\STX\EOT\SOH\DC2\ETXs\t\r\n\
    \\f\n\
    \\ENQ\EOT\v\STX\EOT\ETX\DC2\ETXs\DLE\DC1\n\
    \\v\n\
    \\EOT\EOT\v\STX\ENQ\DC2\ETXt\STX\DC4\n\
    \\f\n\
    \\ENQ\EOT\v\STX\ENQ\ENQ\DC2\ETXt\STX\b\n\
    \\f\n\
    \\ENQ\EOT\v\STX\ENQ\SOH\DC2\ETXt\t\SI\n\
    \\f\n\
    \\ENQ\EOT\v\STX\ENQ\ETX\DC2\ETXt\DC2\DC3\n\
    \\v\n\
    \\EOT\EOT\v\STX\ACK\DC2\ETXu\STX\DC4\n\
    \\f\n\
    \\ENQ\EOT\v\STX\ACK\ENQ\DC2\ETXu\STX\b\n\
    \\f\n\
    \\ENQ\EOT\v\STX\ACK\SOH\DC2\ETXu\t\SI\n\
    \\f\n\
    \\ENQ\EOT\v\STX\ACK\ETX\DC2\ETXu\DC2\DC3\n\
    \\v\n\
    \\EOT\EOT\v\STX\a\DC2\ETXv\STX\DLE\n\
    \\f\n\
    \\ENQ\EOT\v\STX\a\ENQ\DC2\ETXv\STX\ACK\n\
    \\f\n\
    \\ENQ\EOT\v\STX\a\SOH\DC2\ETXv\a\v\n\
    \\f\n\
    \\ENQ\EOT\v\STX\a\ETX\DC2\ETXv\SO\SI\n\
    \\v\n\
    \\EOT\EOT\v\STX\b\DC2\ETXw\STX\"\n\
    \\f\n\
    \\ENQ\EOT\v\STX\b\EOT\DC2\ETXw\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\v\STX\b\ENQ\DC2\ETXw\v\DC1\n\
    \\f\n\
    \\ENQ\EOT\v\STX\b\SOH\DC2\ETXw\DC2\GS\n\
    \\f\n\
    \\ENQ\EOT\v\STX\b\ETX\DC2\ETXw !\n\
    \\v\n\
    \\EOT\EOT\v\STX\t\DC2\ETXx\STX(\n\
    \\f\n\
    \\ENQ\EOT\v\STX\t\EOT\DC2\ETXx\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\v\STX\t\ENQ\DC2\ETXx\v\DC1\n\
    \\f\n\
    \\ENQ\EOT\v\STX\t\SOH\DC2\ETXx\DC2\"\n\
    \\f\n\
    \\ENQ\EOT\v\STX\t\ETX\DC2\ETXx%'\n\
    \\v\n\
    \\EOT\EOT\v\STX\n\
    \\DC2\ETXy\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\v\STX\n\
    \\ENQ\DC2\ETXy\STX\b\n\
    \\f\n\
    \\ENQ\EOT\v\STX\n\
    \\SOH\DC2\ETXy\t\ETB\n\
    \\f\n\
    \\ENQ\EOT\v\STX\n\
    \\ETX\DC2\ETXy\SUB\FS\n\
    \\v\n\
    \\EOT\EOT\v\STX\v\DC2\ETXz\STX\US\n\
    \\f\n\
    \\ENQ\EOT\v\STX\v\ENQ\DC2\ETXz\STX\b\n\
    \\f\n\
    \\ENQ\EOT\v\STX\v\SOH\DC2\ETXz\t\EM\n\
    \\f\n\
    \\ENQ\EOT\v\STX\v\ETX\DC2\ETXz\FS\RS\n\
    \\v\n\
    \\EOT\EOT\v\STX\f\DC2\ETX{\STX\ESC\n\
    \\f\n\
    \\ENQ\EOT\v\STX\f\ENQ\DC2\ETX{\STX\b\n\
    \\f\n\
    \\ENQ\EOT\v\STX\f\SOH\DC2\ETX{\t\NAK\n\
    \\f\n\
    \\ENQ\EOT\v\STX\f\ETX\DC2\ETX{\CAN\SUB\n\
    \\v\n\
    \\STX\EOT\f\DC2\ENQ~\NUL\132\SOH\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\f\SOH\DC2\ETX~\b\DC1\n\
    \\r\n\
    \\EOT\EOT\f\b\NUL\DC2\ENQ\DEL\STX\131\SOH\ETX\n\
    \\f\n\
    \\ENQ\EOT\f\b\NUL\SOH\DC2\ETX\DEL\b\f\n\
    \\f\n\
    \\EOT\EOT\f\STX\NUL\DC2\EOT\128\SOH\EOT*\n\
    \\r\n\
    \\ENQ\EOT\f\STX\NUL\ACK\DC2\EOT\128\SOH\EOT\SO\n\
    \\r\n\
    \\ENQ\EOT\f\STX\NUL\SOH\DC2\EOT\128\SOH\NAK\SUB\n\
    \\r\n\
    \\ENQ\EOT\f\STX\NUL\ETX\DC2\EOT\128\SOH()\n\
    \\f\n\
    \\EOT\EOT\f\STX\SOH\DC2\EOT\129\SOH\EOT*\n\
    \\r\n\
    \\ENQ\EOT\f\STX\SOH\ACK\DC2\EOT\129\SOH\EOT\r\n\
    \\r\n\
    \\ENQ\EOT\f\STX\SOH\SOH\DC2\EOT\129\SOH\NAK\EM\n\
    \\r\n\
    \\ENQ\EOT\f\STX\SOH\ETX\DC2\EOT\129\SOH()\n\
    \\f\n\
    \\EOT\EOT\f\STX\STX\DC2\EOT\130\SOH\EOT+\n\
    \\r\n\
    \\ENQ\EOT\f\STX\STX\ACK\DC2\EOT\130\SOH\EOT\NAK\n\
    \\r\n\
    \\ENQ\EOT\f\STX\STX\SOH\DC2\EOT\130\SOH\SYN&\n\
    \\r\n\
    \\ENQ\EOT\f\STX\STX\ETX\DC2\EOT\130\SOH)*\n\
    \\f\n\
    \\STX\EOT\r\DC2\ACK\134\SOH\NUL\146\SOH\SOH\n\
    \\v\n\
    \\ETX\EOT\r\SOH\DC2\EOT\134\SOH\b\SI\n\
    \\SO\n\
    \\EOT\EOT\r\b\NUL\DC2\ACK\135\SOH\STX\145\SOH\ETX\n\
    \\r\n\
    \\ENQ\EOT\r\b\NUL\SOH\DC2\EOT\135\SOH\b\f\n\
    \\f\n\
    \\EOT\EOT\r\STX\NUL\DC2\EOT\136\SOH\EOT$\n\
    \\r\n\
    \\ENQ\EOT\r\STX\NUL\ACK\DC2\EOT\136\SOH\EOT\SI\n\
    \\r\n\
    \\ENQ\EOT\r\STX\NUL\SOH\DC2\EOT\136\SOH\NAK\FS\n\
    \\r\n\
    \\ENQ\EOT\r\STX\NUL\ETX\DC2\EOT\136\SOH\"#\n\
    \\f\n\
    \\EOT\EOT\r\STX\SOH\DC2\EOT\137\SOH\EOT$\n\
    \\r\n\
    \\ENQ\EOT\r\STX\SOH\ACK\DC2\EOT\137\SOH\EOT\f\n\
    \\r\n\
    \\ENQ\EOT\r\STX\SOH\SOH\DC2\EOT\137\SOH\NAK\EM\n\
    \\r\n\
    \\ENQ\EOT\r\STX\SOH\ETX\DC2\EOT\137\SOH\"#\n\
    \\f\n\
    \\EOT\EOT\r\STX\STX\DC2\EOT\138\SOH\EOT$\n\
    \\r\n\
    \\ENQ\EOT\r\STX\STX\ACK\DC2\EOT\138\SOH\EOT\DC4\n\
    \\r\n\
    \\ENQ\EOT\r\STX\STX\SOH\DC2\EOT\138\SOH\NAK\US\n\
    \\r\n\
    \\ENQ\EOT\r\STX\STX\ETX\DC2\EOT\138\SOH\"#\n\
    \\f\n\
    \\EOT\EOT\r\STX\ETX\DC2\EOT\139\SOH\EOT$\n\
    \\r\n\
    \\ENQ\EOT\r\STX\ETX\ACK\DC2\EOT\139\SOH\EOT\DLE\n\
    \\r\n\
    \\ENQ\EOT\r\STX\ETX\SOH\DC2\EOT\139\SOH\NAK\ESC\n\
    \\r\n\
    \\ENQ\EOT\r\STX\ETX\ETX\DC2\EOT\139\SOH\"#\n\
    \\f\n\
    \\EOT\EOT\r\STX\EOT\DC2\EOT\140\SOH\EOT$\n\
    \\r\n\
    \\ENQ\EOT\r\STX\EOT\ACK\DC2\EOT\140\SOH\EOT\DC4\n\
    \\r\n\
    \\ENQ\EOT\r\STX\EOT\SOH\DC2\EOT\140\SOH\NAK\RS\n\
    \\r\n\
    \\ENQ\EOT\r\STX\EOT\ETX\DC2\EOT\140\SOH\"#\n\
    \\f\n\
    \\EOT\EOT\r\STX\ENQ\DC2\EOT\141\SOH\EOT$\n\
    \\r\n\
    \\ENQ\EOT\r\STX\ENQ\ACK\DC2\EOT\141\SOH\EOT\DC1\n\
    \\r\n\
    \\ENQ\EOT\r\STX\ENQ\SOH\DC2\EOT\141\SOH\NAK\ESC\n\
    \\r\n\
    \\ENQ\EOT\r\STX\ENQ\ETX\DC2\EOT\141\SOH\"#\n\
    \\f\n\
    \\EOT\EOT\r\STX\ACK\DC2\EOT\142\SOH\EOT1\n\
    \\r\n\
    \\ENQ\EOT\r\STX\ACK\ACK\DC2\EOT\142\SOH\EOT\ETB\n\
    \\r\n\
    \\ENQ\EOT\r\STX\ACK\SOH\DC2\EOT\142\SOH\CAN,\n\
    \\r\n\
    \\ENQ\EOT\r\STX\ACK\ETX\DC2\EOT\142\SOH/0\n\
    \\f\n\
    \\EOT\EOT\r\STX\a\DC2\EOT\143\SOH\EOT1\n\
    \\r\n\
    \\ENQ\EOT\r\STX\a\ACK\DC2\EOT\143\SOH\EOT\DC2\n\
    \\r\n\
    \\ENQ\EOT\r\STX\a\SOH\DC2\EOT\143\SOH\CAN'\n\
    \\r\n\
    \\ENQ\EOT\r\STX\a\ETX\DC2\EOT\143\SOH/0\n\
    \\f\n\
    \\EOT\EOT\r\STX\b\DC2\EOT\144\SOH\EOT7\n\
    \\r\n\
    \\ENQ\EOT\r\STX\b\ACK\DC2\EOT\144\SOH\EOT\GS\n\
    \\r\n\
    \\ENQ\EOT\r\STX\b\SOH\DC2\EOT\144\SOH\RS2\n\
    \\r\n\
    \\ENQ\EOT\r\STX\b\ETX\DC2\EOT\144\SOH56b\ACKproto3"