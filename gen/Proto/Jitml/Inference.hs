{- This file was auto-generated from jitml/inference.proto by the proto-lens-protoc program. -}
{-# LANGUAGE ScopedTypeVariables, DataKinds, TypeFamilies, UndecidableInstances, GeneralizedNewtypeDeriving, MultiParamTypeClasses, FlexibleContexts, FlexibleInstances, PatternSynonyms, MagicHash, NoImplicitPrelude, DataKinds, BangPatterns, TypeApplications, OverloadedStrings, DerivingStrategies#-}
{-# OPTIONS_GHC -Wno-unused-imports#-}
{-# OPTIONS_GHC -Wno-duplicate-exports#-}
{-# OPTIONS_GHC -Wno-dodgy-exports#-}
module Proto.Jitml.Inference (
        AppleInferenceCommand(), AppleInferenceEvent(), InferenceRequest(),
        InferenceResult()
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
     
         * 'Proto.Jitml.Inference_Fields.callId' @:: Lens' AppleInferenceCommand Data.Text.Text@
         * 'Proto.Jitml.Inference_Fields.kind' @:: Lens' AppleInferenceCommand Data.Text.Text@
         * 'Proto.Jitml.Inference_Fields.modelId' @:: Lens' AppleInferenceCommand Data.Text.Text@
         * 'Proto.Jitml.Inference_Fields.startingSnapshot' @:: Lens' AppleInferenceCommand Data.Text.Text@
         * 'Proto.Jitml.Inference_Fields.replyTopic' @:: Lens' AppleInferenceCommand Data.Text.Text@
         * 'Proto.Jitml.Inference_Fields.inputs' @:: Lens' AppleInferenceCommand Data.Text.Text@ -}
data AppleInferenceCommand
  = AppleInferenceCommand'_constructor {_AppleInferenceCommand'callId :: !Data.Text.Text,
                                        _AppleInferenceCommand'kind :: !Data.Text.Text,
                                        _AppleInferenceCommand'modelId :: !Data.Text.Text,
                                        _AppleInferenceCommand'startingSnapshot :: !Data.Text.Text,
                                        _AppleInferenceCommand'replyTopic :: !Data.Text.Text,
                                        _AppleInferenceCommand'inputs :: !Data.Text.Text,
                                        _AppleInferenceCommand'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show AppleInferenceCommand where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField AppleInferenceCommand "callId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _AppleInferenceCommand'callId
           (\ x__ y__ -> x__ {_AppleInferenceCommand'callId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField AppleInferenceCommand "kind" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _AppleInferenceCommand'kind
           (\ x__ y__ -> x__ {_AppleInferenceCommand'kind = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField AppleInferenceCommand "modelId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _AppleInferenceCommand'modelId
           (\ x__ y__ -> x__ {_AppleInferenceCommand'modelId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField AppleInferenceCommand "startingSnapshot" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _AppleInferenceCommand'startingSnapshot
           (\ x__ y__ -> x__ {_AppleInferenceCommand'startingSnapshot = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField AppleInferenceCommand "replyTopic" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _AppleInferenceCommand'replyTopic
           (\ x__ y__ -> x__ {_AppleInferenceCommand'replyTopic = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField AppleInferenceCommand "inputs" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _AppleInferenceCommand'inputs
           (\ x__ y__ -> x__ {_AppleInferenceCommand'inputs = y__}))
        Prelude.id
instance Data.ProtoLens.Message AppleInferenceCommand where
  messageName _
    = Data.Text.pack "jitml.inference.AppleInferenceCommand"
  packedMessageDescriptor _
    = "\n\
      \\NAKAppleInferenceCommand\DC2\ETB\n\
      \\acall_id\CAN\SOH \SOH(\tR\ACKcallId\DC2\DC2\n\
      \\EOTkind\CAN\STX \SOH(\tR\EOTkind\DC2\EM\n\
      \\bmodel_id\CAN\ETX \SOH(\tR\amodelId\DC2+\n\
      \\DC1starting_snapshot\CAN\EOT \SOH(\tR\DLEstartingSnapshot\DC2\US\n\
      \\vreply_topic\CAN\ENQ \SOH(\tR\n\
      \replyTopic\DC2\SYN\n\
      \\ACKinputs\CAN\ACK \SOH(\tR\ACKinputs"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        callId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "call_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"callId")) ::
              Data.ProtoLens.FieldDescriptor AppleInferenceCommand
        kind__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "kind"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"kind")) ::
              Data.ProtoLens.FieldDescriptor AppleInferenceCommand
        modelId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "model_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"modelId")) ::
              Data.ProtoLens.FieldDescriptor AppleInferenceCommand
        startingSnapshot__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "starting_snapshot"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"startingSnapshot")) ::
              Data.ProtoLens.FieldDescriptor AppleInferenceCommand
        replyTopic__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "reply_topic"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"replyTopic")) ::
              Data.ProtoLens.FieldDescriptor AppleInferenceCommand
        inputs__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "inputs"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"inputs")) ::
              Data.ProtoLens.FieldDescriptor AppleInferenceCommand
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, callId__field_descriptor),
           (Data.ProtoLens.Tag 2, kind__field_descriptor),
           (Data.ProtoLens.Tag 3, modelId__field_descriptor),
           (Data.ProtoLens.Tag 4, startingSnapshot__field_descriptor),
           (Data.ProtoLens.Tag 5, replyTopic__field_descriptor),
           (Data.ProtoLens.Tag 6, inputs__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _AppleInferenceCommand'_unknownFields
        (\ x__ y__ -> x__ {_AppleInferenceCommand'_unknownFields = y__})
  defMessage
    = AppleInferenceCommand'_constructor
        {_AppleInferenceCommand'callId = Data.ProtoLens.fieldDefault,
         _AppleInferenceCommand'kind = Data.ProtoLens.fieldDefault,
         _AppleInferenceCommand'modelId = Data.ProtoLens.fieldDefault,
         _AppleInferenceCommand'startingSnapshot = Data.ProtoLens.fieldDefault,
         _AppleInferenceCommand'replyTopic = Data.ProtoLens.fieldDefault,
         _AppleInferenceCommand'inputs = Data.ProtoLens.fieldDefault,
         _AppleInferenceCommand'_unknownFields = []}
  parseMessage
    = let
        loop ::
          AppleInferenceCommand
          -> Data.ProtoLens.Encoding.Bytes.Parser AppleInferenceCommand
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
                                       "call_id"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"callId") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "kind"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"kind") y x)
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "model_id"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"modelId") y x)
                        34
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "starting_snapshot"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"startingSnapshot") y x)
                        42
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "reply_topic"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"replyTopic") y x)
                        50
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "inputs"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"inputs") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "AppleInferenceCommand"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"callId") _x
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
                (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"kind") _x
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
                      _v = Lens.Family2.view (Data.ProtoLens.Field.field @"modelId") _x
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
                           = Lens.Family2.view
                               (Data.ProtoLens.Field.field @"startingSnapshot") _x
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
                              = Lens.Family2.view (Data.ProtoLens.Field.field @"replyTopic") _x
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
                               _v = Lens.Family2.view (Data.ProtoLens.Field.field @"inputs") _x
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
instance Control.DeepSeq.NFData AppleInferenceCommand where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_AppleInferenceCommand'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_AppleInferenceCommand'callId x__)
                (Control.DeepSeq.deepseq
                   (_AppleInferenceCommand'kind x__)
                   (Control.DeepSeq.deepseq
                      (_AppleInferenceCommand'modelId x__)
                      (Control.DeepSeq.deepseq
                         (_AppleInferenceCommand'startingSnapshot x__)
                         (Control.DeepSeq.deepseq
                            (_AppleInferenceCommand'replyTopic x__)
                            (Control.DeepSeq.deepseq
                               (_AppleInferenceCommand'inputs x__) ()))))))
{- | Fields :
     
         * 'Proto.Jitml.Inference_Fields.callId' @:: Lens' AppleInferenceEvent Data.Text.Text@
         * 'Proto.Jitml.Inference_Fields.kind' @:: Lens' AppleInferenceEvent Data.Text.Text@
         * 'Proto.Jitml.Inference_Fields.outputRefs' @:: Lens' AppleInferenceEvent [Data.Text.Text]@
         * 'Proto.Jitml.Inference_Fields.vec'outputRefs' @:: Lens' AppleInferenceEvent (Data.Vector.Vector Data.Text.Text)@
         * 'Proto.Jitml.Inference_Fields.errorCode' @:: Lens' AppleInferenceEvent Data.Text.Text@
         * 'Proto.Jitml.Inference_Fields.message' @:: Lens' AppleInferenceEvent Data.Text.Text@ -}
data AppleInferenceEvent
  = AppleInferenceEvent'_constructor {_AppleInferenceEvent'callId :: !Data.Text.Text,
                                      _AppleInferenceEvent'kind :: !Data.Text.Text,
                                      _AppleInferenceEvent'outputRefs :: !(Data.Vector.Vector Data.Text.Text),
                                      _AppleInferenceEvent'errorCode :: !Data.Text.Text,
                                      _AppleInferenceEvent'message :: !Data.Text.Text,
                                      _AppleInferenceEvent'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show AppleInferenceEvent where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField AppleInferenceEvent "callId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _AppleInferenceEvent'callId
           (\ x__ y__ -> x__ {_AppleInferenceEvent'callId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField AppleInferenceEvent "kind" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _AppleInferenceEvent'kind
           (\ x__ y__ -> x__ {_AppleInferenceEvent'kind = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField AppleInferenceEvent "outputRefs" [Data.Text.Text] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _AppleInferenceEvent'outputRefs
           (\ x__ y__ -> x__ {_AppleInferenceEvent'outputRefs = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField AppleInferenceEvent "vec'outputRefs" (Data.Vector.Vector Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _AppleInferenceEvent'outputRefs
           (\ x__ y__ -> x__ {_AppleInferenceEvent'outputRefs = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField AppleInferenceEvent "errorCode" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _AppleInferenceEvent'errorCode
           (\ x__ y__ -> x__ {_AppleInferenceEvent'errorCode = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField AppleInferenceEvent "message" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _AppleInferenceEvent'message
           (\ x__ y__ -> x__ {_AppleInferenceEvent'message = y__}))
        Prelude.id
instance Data.ProtoLens.Message AppleInferenceEvent where
  messageName _
    = Data.Text.pack "jitml.inference.AppleInferenceEvent"
  packedMessageDescriptor _
    = "\n\
      \\DC3AppleInferenceEvent\DC2\ETB\n\
      \\acall_id\CAN\SOH \SOH(\tR\ACKcallId\DC2\DC2\n\
      \\EOTkind\CAN\STX \SOH(\tR\EOTkind\DC2\US\n\
      \\voutput_refs\CAN\ETX \ETX(\tR\n\
      \outputRefs\DC2\GS\n\
      \\n\
      \error_code\CAN\EOT \SOH(\tR\terrorCode\DC2\CAN\n\
      \\amessage\CAN\ENQ \SOH(\tR\amessage"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        callId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "call_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"callId")) ::
              Data.ProtoLens.FieldDescriptor AppleInferenceEvent
        kind__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "kind"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"kind")) ::
              Data.ProtoLens.FieldDescriptor AppleInferenceEvent
        outputRefs__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "output_refs"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked
                 (Data.ProtoLens.Field.field @"outputRefs")) ::
              Data.ProtoLens.FieldDescriptor AppleInferenceEvent
        errorCode__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "error_code"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"errorCode")) ::
              Data.ProtoLens.FieldDescriptor AppleInferenceEvent
        message__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "message"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"message")) ::
              Data.ProtoLens.FieldDescriptor AppleInferenceEvent
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, callId__field_descriptor),
           (Data.ProtoLens.Tag 2, kind__field_descriptor),
           (Data.ProtoLens.Tag 3, outputRefs__field_descriptor),
           (Data.ProtoLens.Tag 4, errorCode__field_descriptor),
           (Data.ProtoLens.Tag 5, message__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _AppleInferenceEvent'_unknownFields
        (\ x__ y__ -> x__ {_AppleInferenceEvent'_unknownFields = y__})
  defMessage
    = AppleInferenceEvent'_constructor
        {_AppleInferenceEvent'callId = Data.ProtoLens.fieldDefault,
         _AppleInferenceEvent'kind = Data.ProtoLens.fieldDefault,
         _AppleInferenceEvent'outputRefs = Data.Vector.Generic.empty,
         _AppleInferenceEvent'errorCode = Data.ProtoLens.fieldDefault,
         _AppleInferenceEvent'message = Data.ProtoLens.fieldDefault,
         _AppleInferenceEvent'_unknownFields = []}
  parseMessage
    = let
        loop ::
          AppleInferenceEvent
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld Data.Text.Text
             -> Data.ProtoLens.Encoding.Bytes.Parser AppleInferenceEvent
        loop x mutable'outputRefs
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'outputRefs <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                             (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                                mutable'outputRefs)
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
                              (Data.ProtoLens.Field.field @"vec'outputRefs") frozen'outputRefs
                              x))
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "call_id"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"callId") y x)
                                  mutable'outputRefs
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "kind"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"kind") y x)
                                  mutable'outputRefs
                        26
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.getText
                                              (Prelude.fromIntegral len))
                                        "output_refs"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append mutable'outputRefs y)
                                loop x v
                        34
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "error_code"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"errorCode") y x)
                                  mutable'outputRefs
                        42
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "message"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"message") y x)
                                  mutable'outputRefs
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'outputRefs
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'outputRefs <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                      Data.ProtoLens.Encoding.Growing.new
              loop Data.ProtoLens.defMessage mutable'outputRefs)
          "AppleInferenceEvent"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"callId") _x
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
                (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"kind") _x
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
                   (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                      (\ _v
                         -> (Data.Monoid.<>)
                              (Data.ProtoLens.Encoding.Bytes.putVarInt 26)
                              ((Prelude..)
                                 (\ bs
                                    -> (Data.Monoid.<>)
                                         (Data.ProtoLens.Encoding.Bytes.putVarInt
                                            (Prelude.fromIntegral (Data.ByteString.length bs)))
                                         (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                 Data.Text.Encoding.encodeUtf8 _v))
                      (Lens.Family2.view
                         (Data.ProtoLens.Field.field @"vec'outputRefs") _x))
                   ((Data.Monoid.<>)
                      (let
                         _v = Lens.Family2.view (Data.ProtoLens.Field.field @"errorCode") _x
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
                            _v = Lens.Family2.view (Data.ProtoLens.Field.field @"message") _x
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
                         (Data.ProtoLens.Encoding.Wire.buildFieldSet
                            (Lens.Family2.view Data.ProtoLens.unknownFields _x))))))
instance Control.DeepSeq.NFData AppleInferenceEvent where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_AppleInferenceEvent'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_AppleInferenceEvent'callId x__)
                (Control.DeepSeq.deepseq
                   (_AppleInferenceEvent'kind x__)
                   (Control.DeepSeq.deepseq
                      (_AppleInferenceEvent'outputRefs x__)
                      (Control.DeepSeq.deepseq
                         (_AppleInferenceEvent'errorCode x__)
                         (Control.DeepSeq.deepseq (_AppleInferenceEvent'message x__) ())))))
{- | Fields :
     
         * 'Proto.Jitml.Inference_Fields.callId' @:: Lens' InferenceRequest Data.Text.Text@
         * 'Proto.Jitml.Inference_Fields.experimentHash' @:: Lens' InferenceRequest Data.Text.Text@
         * 'Proto.Jitml.Inference_Fields.replyTopic' @:: Lens' InferenceRequest Data.Text.Text@
         * 'Proto.Jitml.Inference_Fields.input' @:: Lens' InferenceRequest [Prelude.Double]@
         * 'Proto.Jitml.Inference_Fields.vec'input' @:: Lens' InferenceRequest (Data.Vector.Unboxed.Vector Prelude.Double)@ -}
data InferenceRequest
  = InferenceRequest'_constructor {_InferenceRequest'callId :: !Data.Text.Text,
                                   _InferenceRequest'experimentHash :: !Data.Text.Text,
                                   _InferenceRequest'replyTopic :: !Data.Text.Text,
                                   _InferenceRequest'input :: !(Data.Vector.Unboxed.Vector Prelude.Double),
                                   _InferenceRequest'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show InferenceRequest where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField InferenceRequest "callId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceRequest'callId
           (\ x__ y__ -> x__ {_InferenceRequest'callId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField InferenceRequest "experimentHash" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceRequest'experimentHash
           (\ x__ y__ -> x__ {_InferenceRequest'experimentHash = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField InferenceRequest "replyTopic" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceRequest'replyTopic
           (\ x__ y__ -> x__ {_InferenceRequest'replyTopic = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField InferenceRequest "input" [Prelude.Double] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceRequest'input
           (\ x__ y__ -> x__ {_InferenceRequest'input = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField InferenceRequest "vec'input" (Data.Vector.Unboxed.Vector Prelude.Double) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceRequest'input
           (\ x__ y__ -> x__ {_InferenceRequest'input = y__}))
        Prelude.id
instance Data.ProtoLens.Message InferenceRequest where
  messageName _ = Data.Text.pack "jitml.inference.InferenceRequest"
  packedMessageDescriptor _
    = "\n\
      \\DLEInferenceRequest\DC2\ETB\n\
      \\acall_id\CAN\SOH \SOH(\tR\ACKcallId\DC2'\n\
      \\SIexperiment_hash\CAN\STX \SOH(\tR\SOexperimentHash\DC2\US\n\
      \\vreply_topic\CAN\ETX \SOH(\tR\n\
      \replyTopic\DC2\DC4\n\
      \\ENQinput\CAN\EOT \ETX(\SOHR\ENQinput"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        callId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "call_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"callId")) ::
              Data.ProtoLens.FieldDescriptor InferenceRequest
        experimentHash__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "experiment_hash"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"experimentHash")) ::
              Data.ProtoLens.FieldDescriptor InferenceRequest
        replyTopic__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "reply_topic"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"replyTopic")) ::
              Data.ProtoLens.FieldDescriptor InferenceRequest
        input__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "input"
              (Data.ProtoLens.ScalarField Data.ProtoLens.DoubleField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Double)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Packed (Data.ProtoLens.Field.field @"input")) ::
              Data.ProtoLens.FieldDescriptor InferenceRequest
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, callId__field_descriptor),
           (Data.ProtoLens.Tag 2, experimentHash__field_descriptor),
           (Data.ProtoLens.Tag 3, replyTopic__field_descriptor),
           (Data.ProtoLens.Tag 4, input__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _InferenceRequest'_unknownFields
        (\ x__ y__ -> x__ {_InferenceRequest'_unknownFields = y__})
  defMessage
    = InferenceRequest'_constructor
        {_InferenceRequest'callId = Data.ProtoLens.fieldDefault,
         _InferenceRequest'experimentHash = Data.ProtoLens.fieldDefault,
         _InferenceRequest'replyTopic = Data.ProtoLens.fieldDefault,
         _InferenceRequest'input = Data.Vector.Generic.empty,
         _InferenceRequest'_unknownFields = []}
  parseMessage
    = let
        loop ::
          InferenceRequest
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Unboxed.Vector Data.ProtoLens.Encoding.Growing.RealWorld Prelude.Double
             -> Data.ProtoLens.Encoding.Bytes.Parser InferenceRequest
        loop x mutable'input
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'input <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                        (Data.ProtoLens.Encoding.Growing.unsafeFreeze mutable'input)
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
                              (Data.ProtoLens.Field.field @"vec'input") frozen'input x))
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "call_id"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"callId") y x)
                                  mutable'input
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "experiment_hash"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"experimentHash") y x)
                                  mutable'input
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "reply_topic"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"replyTopic") y x)
                                  mutable'input
                        33
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (Prelude.fmap
                                           Data.ProtoLens.Encoding.Bytes.wordToDouble
                                           Data.ProtoLens.Encoding.Bytes.getFixed64)
                                        "input"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append mutable'input y)
                                loop x v
                        34
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
                                                                    "input"
                                                            qs' <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                                                     (Data.ProtoLens.Encoding.Growing.append
                                                                        qs q)
                                                            ploop qs'
                                            in ploop)
                                             mutable'input)
                                loop x y
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'input
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'input <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                 Data.ProtoLens.Encoding.Growing.new
              loop Data.ProtoLens.defMessage mutable'input)
          "InferenceRequest"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"callId") _x
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
                        = Lens.Family2.view (Data.ProtoLens.Field.field @"replyTopic") _x
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
                         p = Lens.Family2.view (Data.ProtoLens.Field.field @"vec'input") _x
                       in
                         if Data.Vector.Generic.null p then
                             Data.Monoid.mempty
                         else
                             (Data.Monoid.<>)
                               (Data.ProtoLens.Encoding.Bytes.putVarInt 34)
                               ((\ bs
                                   -> (Data.Monoid.<>)
                                        (Data.ProtoLens.Encoding.Bytes.putVarInt
                                           (Prelude.fromIntegral (Data.ByteString.length bs)))
                                        (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                  (Data.ProtoLens.Encoding.Bytes.runBuilder
                                     (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                                        ((Prelude..)
                                           Data.ProtoLens.Encoding.Bytes.putFixed64
                                           Data.ProtoLens.Encoding.Bytes.doubleToWord)
                                        p))))
                      (Data.ProtoLens.Encoding.Wire.buildFieldSet
                         (Lens.Family2.view Data.ProtoLens.unknownFields _x)))))
instance Control.DeepSeq.NFData InferenceRequest where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_InferenceRequest'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_InferenceRequest'callId x__)
                (Control.DeepSeq.deepseq
                   (_InferenceRequest'experimentHash x__)
                   (Control.DeepSeq.deepseq
                      (_InferenceRequest'replyTopic x__)
                      (Control.DeepSeq.deepseq (_InferenceRequest'input x__) ()))))
{- | Fields :
     
         * 'Proto.Jitml.Inference_Fields.callId' @:: Lens' InferenceResult Data.Text.Text@
         * 'Proto.Jitml.Inference_Fields.experimentHash' @:: Lens' InferenceResult Data.Text.Text@
         * 'Proto.Jitml.Inference_Fields.output' @:: Lens' InferenceResult [Prelude.Double]@
         * 'Proto.Jitml.Inference_Fields.vec'output' @:: Lens' InferenceResult (Data.Vector.Unboxed.Vector Prelude.Double)@ -}
data InferenceResult
  = InferenceResult'_constructor {_InferenceResult'callId :: !Data.Text.Text,
                                  _InferenceResult'experimentHash :: !Data.Text.Text,
                                  _InferenceResult'output :: !(Data.Vector.Unboxed.Vector Prelude.Double),
                                  _InferenceResult'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show InferenceResult where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField InferenceResult "callId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceResult'callId
           (\ x__ y__ -> x__ {_InferenceResult'callId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField InferenceResult "experimentHash" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceResult'experimentHash
           (\ x__ y__ -> x__ {_InferenceResult'experimentHash = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField InferenceResult "output" [Prelude.Double] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceResult'output
           (\ x__ y__ -> x__ {_InferenceResult'output = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField InferenceResult "vec'output" (Data.Vector.Unboxed.Vector Prelude.Double) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InferenceResult'output
           (\ x__ y__ -> x__ {_InferenceResult'output = y__}))
        Prelude.id
instance Data.ProtoLens.Message InferenceResult where
  messageName _ = Data.Text.pack "jitml.inference.InferenceResult"
  packedMessageDescriptor _
    = "\n\
      \\SIInferenceResult\DC2\ETB\n\
      \\acall_id\CAN\SOH \SOH(\tR\ACKcallId\DC2'\n\
      \\SIexperiment_hash\CAN\STX \SOH(\tR\SOexperimentHash\DC2\SYN\n\
      \\ACKoutput\CAN\ETX \ETX(\SOHR\ACKoutput"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        callId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "call_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"callId")) ::
              Data.ProtoLens.FieldDescriptor InferenceResult
        experimentHash__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "experiment_hash"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"experimentHash")) ::
              Data.ProtoLens.FieldDescriptor InferenceResult
        output__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "output"
              (Data.ProtoLens.ScalarField Data.ProtoLens.DoubleField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Double)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Packed (Data.ProtoLens.Field.field @"output")) ::
              Data.ProtoLens.FieldDescriptor InferenceResult
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, callId__field_descriptor),
           (Data.ProtoLens.Tag 2, experimentHash__field_descriptor),
           (Data.ProtoLens.Tag 3, output__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _InferenceResult'_unknownFields
        (\ x__ y__ -> x__ {_InferenceResult'_unknownFields = y__})
  defMessage
    = InferenceResult'_constructor
        {_InferenceResult'callId = Data.ProtoLens.fieldDefault,
         _InferenceResult'experimentHash = Data.ProtoLens.fieldDefault,
         _InferenceResult'output = Data.Vector.Generic.empty,
         _InferenceResult'_unknownFields = []}
  parseMessage
    = let
        loop ::
          InferenceResult
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Unboxed.Vector Data.ProtoLens.Encoding.Growing.RealWorld Prelude.Double
             -> Data.ProtoLens.Encoding.Bytes.Parser InferenceResult
        loop x mutable'output
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'output <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                         (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                            mutable'output)
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
                              (Data.ProtoLens.Field.field @"vec'output") frozen'output x))
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "call_id"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"callId") y x)
                                  mutable'output
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "experiment_hash"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"experimentHash") y x)
                                  mutable'output
                        25
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (Prelude.fmap
                                           Data.ProtoLens.Encoding.Bytes.wordToDouble
                                           Data.ProtoLens.Encoding.Bytes.getFixed64)
                                        "output"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append mutable'output y)
                                loop x v
                        26
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
                                                                    "output"
                                                            qs' <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                                                     (Data.ProtoLens.Encoding.Growing.append
                                                                        qs q)
                                                            ploop qs'
                                            in ploop)
                                             mutable'output)
                                loop x y
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'output
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'output <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                  Data.ProtoLens.Encoding.Growing.new
              loop Data.ProtoLens.defMessage mutable'output)
          "InferenceResult"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"callId") _x
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
                      p = Lens.Family2.view (Data.ProtoLens.Field.field @"vec'output") _x
                    in
                      if Data.Vector.Generic.null p then
                          Data.Monoid.mempty
                      else
                          (Data.Monoid.<>)
                            (Data.ProtoLens.Encoding.Bytes.putVarInt 26)
                            ((\ bs
                                -> (Data.Monoid.<>)
                                     (Data.ProtoLens.Encoding.Bytes.putVarInt
                                        (Prelude.fromIntegral (Data.ByteString.length bs)))
                                     (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                               (Data.ProtoLens.Encoding.Bytes.runBuilder
                                  (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                                     ((Prelude..)
                                        Data.ProtoLens.Encoding.Bytes.putFixed64
                                        Data.ProtoLens.Encoding.Bytes.doubleToWord)
                                     p))))
                   (Data.ProtoLens.Encoding.Wire.buildFieldSet
                      (Lens.Family2.view Data.ProtoLens.unknownFields _x))))
instance Control.DeepSeq.NFData InferenceResult where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_InferenceResult'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_InferenceResult'callId x__)
                (Control.DeepSeq.deepseq
                   (_InferenceResult'experimentHash x__)
                   (Control.DeepSeq.deepseq (_InferenceResult'output x__) ())))
packedFileDescriptor :: Data.ByteString.ByteString
packedFileDescriptor
  = "\n\
    \\NAKjitml/inference.proto\DC2\SIjitml.inference\"\139\SOH\n\
    \\DLEInferenceRequest\DC2\ETB\n\
    \\acall_id\CAN\SOH \SOH(\tR\ACKcallId\DC2'\n\
    \\SIexperiment_hash\CAN\STX \SOH(\tR\SOexperimentHash\DC2\US\n\
    \\vreply_topic\CAN\ETX \SOH(\tR\n\
    \replyTopic\DC2\DC4\n\
    \\ENQinput\CAN\EOT \ETX(\SOHR\ENQinput\"k\n\
    \\SIInferenceResult\DC2\ETB\n\
    \\acall_id\CAN\SOH \SOH(\tR\ACKcallId\DC2'\n\
    \\SIexperiment_hash\CAN\STX \SOH(\tR\SOexperimentHash\DC2\SYN\n\
    \\ACKoutput\CAN\ETX \ETX(\SOHR\ACKoutput\"\197\SOH\n\
    \\NAKAppleInferenceCommand\DC2\ETB\n\
    \\acall_id\CAN\SOH \SOH(\tR\ACKcallId\DC2\DC2\n\
    \\EOTkind\CAN\STX \SOH(\tR\EOTkind\DC2\EM\n\
    \\bmodel_id\CAN\ETX \SOH(\tR\amodelId\DC2+\n\
    \\DC1starting_snapshot\CAN\EOT \SOH(\tR\DLEstartingSnapshot\DC2\US\n\
    \\vreply_topic\CAN\ENQ \SOH(\tR\n\
    \replyTopic\DC2\SYN\n\
    \\ACKinputs\CAN\ACK \SOH(\tR\ACKinputs\"\156\SOH\n\
    \\DC3AppleInferenceEvent\DC2\ETB\n\
    \\acall_id\CAN\SOH \SOH(\tR\ACKcallId\DC2\DC2\n\
    \\EOTkind\CAN\STX \SOH(\tR\EOTkind\DC2\US\n\
    \\voutput_refs\CAN\ETX \ETX(\tR\n\
    \outputRefs\DC2\GS\n\
    \\n\
    \error_code\CAN\EOT \SOH(\tR\terrorCode\DC2\CAN\n\
    \\amessage\CAN\ENQ \SOH(\tR\amessageJ\143\r\n\
    \\ACK\DC2\EOT\NUL\NUL'\SOH\n\
    \\b\n\
    \\SOH\f\DC2\ETX\NUL\NUL\DC2\n\
    \\b\n\
    \\SOH\STX\DC2\ETX\STX\NUL\CAN\n\
    \\139\SOH\n\
    \\STX\EOT\NUL\DC2\EOT\ACK\NUL\v\SOH\SUB\DEL Envelope sent on `inference.request.<mode>` to run inference against a\n\
    \ checkpoint selected by the request's experiment hash.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\NUL\SOH\DC2\ETX\ACK\b\CAN\n\
    \\v\n\
    \\EOT\EOT\NUL\STX\NUL\DC2\ETX\a\STX\NAK\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\ENQ\DC2\ETX\a\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\SOH\DC2\ETX\a\t\DLE\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\ETX\DC2\ETX\a\DC3\DC4\n\
    \\v\n\
    \\EOT\EOT\NUL\STX\SOH\DC2\ETX\b\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\ENQ\DC2\ETX\b\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\SOH\DC2\ETX\b\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\ETX\DC2\ETX\b\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\NUL\STX\STX\DC2\ETX\t\STX\EM\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\STX\ENQ\DC2\ETX\t\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\STX\SOH\DC2\ETX\t\t\DC4\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\STX\ETX\DC2\ETX\t\ETB\CAN\n\
    \\v\n\
    \\EOT\EOT\NUL\STX\ETX\DC2\ETX\n\
    \\STX\FS\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ETX\EOT\DC2\ETX\n\
    \\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ETX\ENQ\DC2\ETX\n\
    \\v\DC1\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ETX\SOH\DC2\ETX\n\
    \\DC2\ETB\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ETX\ETX\DC2\ETX\n\
    \\SUB\ESC\n\
    \\DEL\n\
    \\STX\EOT\SOH\DC2\EOT\SI\NUL\DC3\SOH\SUBs Envelope published on `inference.result.<mode>` after the daemon finishes\n\
    \ the checkpoint read and inference run.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\SOH\SOH\DC2\ETX\SI\b\ETB\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\NUL\DC2\ETX\DLE\STX\NAK\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ENQ\DC2\ETX\DLE\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\SOH\DC2\ETX\DLE\t\DLE\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ETX\DC2\ETX\DLE\DC3\DC4\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\SOH\DC2\ETX\DC1\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\ENQ\DC2\ETX\DC1\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\SOH\DC2\ETX\DC1\t\CAN\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\ETX\DC2\ETX\DC1\ESC\FS\n\
    \\v\n\
    \\EOT\EOT\SOH\STX\STX\DC2\ETX\DC2\STX\GS\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\STX\EOT\DC2\ETX\DC2\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\STX\ENQ\DC2\ETX\DC2\v\DC1\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\STX\SOH\DC2\ETX\DC2\DC2\CAN\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\STX\ETX\DC2\ETX\DC2\ESC\FS\n\
    \\156\SOH\n\
    \\STX\EOT\STX\DC2\EOT\ETB\NUL\RS\SOH\SUB\143\SOH Apple-only internal RPC envelope sent on `inference.command.apple-silicon`.\n\
    \ Pulsar carries this small envelope; large tensors stay in MinIO.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\STX\SOH\DC2\ETX\ETB\b\GS\n\
    \\v\n\
    \\EOT\EOT\STX\STX\NUL\DC2\ETX\CAN\STX\NAK\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\NUL\ENQ\DC2\ETX\CAN\STX\b\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\NUL\SOH\DC2\ETX\CAN\t\DLE\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\NUL\ETX\DC2\ETX\CAN\DC3\DC4\n\
    \(\n\
    \\EOT\EOT\STX\STX\SOH\DC2\ETX\EM\STX\DC2\"\ESC \"training\" or \"inference\"\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\SOH\ENQ\DC2\ETX\EM\STX\b\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\SOH\SOH\DC2\ETX\EM\t\r\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\SOH\ETX\DC2\ETX\EM\DLE\DC1\n\
    \\v\n\
    \\EOT\EOT\STX\STX\STX\DC2\ETX\SUB\STX\SYN\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\STX\ENQ\DC2\ETX\SUB\STX\b\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\STX\SOH\DC2\ETX\SUB\t\DC1\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\STX\ETX\DC2\ETX\SUB\DC4\NAK\n\
    \\v\n\
    \\EOT\EOT\STX\STX\ETX\DC2\ETX\ESC\STX\US\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\ETX\ENQ\DC2\ETX\ESC\STX\b\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\ETX\SOH\DC2\ETX\ESC\t\SUB\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\ETX\ETX\DC2\ETX\ESC\GS\RS\n\
    \\v\n\
    \\EOT\EOT\STX\STX\EOT\DC2\ETX\FS\STX\EM\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\EOT\ENQ\DC2\ETX\FS\STX\b\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\EOT\SOH\DC2\ETX\FS\t\DC4\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\EOT\ETX\DC2\ETX\FS\ETB\CAN\n\
    \\v\n\
    \\EOT\EOT\STX\STX\ENQ\DC2\ETX\GS\STX\DC4\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\ENQ\ENQ\DC2\ETX\GS\STX\b\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\ENQ\SOH\DC2\ETX\GS\t\SI\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\ENQ\ETX\DC2\ETX\GS\DC2\DC3\n\
    \T\n\
    \\STX\EOT\ETX\DC2\EOT!\NUL'\SOH\SUBH Apple-only ACK/error envelope sent on `inference.event.apple-silicon`.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\ETX\SOH\DC2\ETX!\b\ESC\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\NUL\DC2\ETX\"\STX\NAK\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\NUL\ENQ\DC2\ETX\"\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\NUL\SOH\DC2\ETX\"\t\DLE\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\NUL\ETX\DC2\ETX\"\DC3\DC4\n\
    \%\n\
    \\EOT\EOT\ETX\STX\SOH\DC2\ETX#\STX\DC2\"\CAN \"completed\" or \"error\"\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\SOH\ENQ\DC2\ETX#\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\SOH\SOH\DC2\ETX#\t\r\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\SOH\ETX\DC2\ETX#\DLE\DC1\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\STX\DC2\ETX$\STX\"\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\STX\EOT\DC2\ETX$\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\STX\ENQ\DC2\ETX$\v\DC1\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\STX\SOH\DC2\ETX$\DC2\GS\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\STX\ETX\DC2\ETX$ !\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\ETX\DC2\ETX%\STX\CAN\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ETX\ENQ\DC2\ETX%\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ETX\SOH\DC2\ETX%\t\DC3\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\ETX\ETX\DC2\ETX%\SYN\ETB\n\
    \\v\n\
    \\EOT\EOT\ETX\STX\EOT\DC2\ETX&\STX\NAK\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\EOT\ENQ\DC2\ETX&\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\EOT\SOH\DC2\ETX&\t\DLE\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\EOT\ETX\DC2\ETX&\DC3\DC4b\ACKproto3"