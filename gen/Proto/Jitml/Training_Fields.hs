{- This file was auto-generated from jitml/training.proto by the proto-lens-protoc program. -}
{-# LANGUAGE ScopedTypeVariables, DataKinds, TypeFamilies, UndecidableInstances, GeneralizedNewtypeDeriving, MultiParamTypeClasses, FlexibleContexts, FlexibleInstances, PatternSynonyms, MagicHash, NoImplicitPrelude, DataKinds, BangPatterns, TypeApplications, OverloadedStrings, DerivingStrategies#-}
{-# OPTIONS_GHC -Wno-unused-imports#-}
{-# OPTIONS_GHC -Wno-duplicate-exports#-}
{-# OPTIONS_GHC -Wno-dodgy-exports#-}
module Proto.Jitml.Training_Fields where
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
batchSize ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "batchSize" a) =>
  Lens.Family2.LensLike' f s a
batchSize = Data.ProtoLens.Field.field @"batchSize"
checkpoint ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "checkpoint" a) =>
  Lens.Family2.LensLike' f s a
checkpoint = Data.ProtoLens.Field.field @"checkpoint"
completedCheckpoint ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "completedCheckpoint" a) =>
  Lens.Family2.LensLike' f s a
completedCheckpoint
  = Data.ProtoLens.Field.field @"completedCheckpoint"
completedTraining ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "completedTraining" a) =>
  Lens.Family2.LensLike' f s a
completedTraining = Data.ProtoLens.Field.field @"completedTraining"
dhallObjectKey ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "dhallObjectKey" a) =>
  Lens.Family2.LensLike' f s a
dhallObjectKey = Data.ProtoLens.Field.field @"dhallObjectKey"
drain ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "drain" a) =>
  Lens.Family2.LensLike' f s a
drain = Data.ProtoLens.Field.field @"drain"
epoch ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "epoch" a) =>
  Lens.Family2.LensLike' f s a
epoch = Data.ProtoLens.Field.field @"epoch"
epochs ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "epochs" a) =>
  Lens.Family2.LensLike' f s a
epochs = Data.ProtoLens.Field.field @"epochs"
errorCode ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "errorCode" a) =>
  Lens.Family2.LensLike' f s a
errorCode = Data.ProtoLens.Field.field @"errorCode"
errorText ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "errorText" a) =>
  Lens.Family2.LensLike' f s a
errorText = Data.ProtoLens.Field.field @"errorText"
evaluationExamples ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "evaluationExamples" a) =>
  Lens.Family2.LensLike' f s a
evaluationExamples
  = Data.ProtoLens.Field.field @"evaluationExamples"
experimentHash ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "experimentHash" a) =>
  Lens.Family2.LensLike' f s a
experimentHash = Data.ProtoLens.Field.field @"experimentHash"
failure ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "failure" a) =>
  Lens.Family2.LensLike' f s a
failure = Data.ProtoLens.Field.field @"failure"
loss ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "loss" a) =>
  Lens.Family2.LensLike' f s a
loss = Data.ProtoLens.Field.field @"loss"
manifestSha ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "manifestSha" a) =>
  Lens.Family2.LensLike' f s a
manifestSha = Data.ProtoLens.Field.field @"manifestSha"
maybe'body ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'body" a) =>
  Lens.Family2.LensLike' f s a
maybe'body = Data.ProtoLens.Field.field @"maybe'body"
maybe'checkpoint ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'checkpoint" a) =>
  Lens.Family2.LensLike' f s a
maybe'checkpoint = Data.ProtoLens.Field.field @"maybe'checkpoint"
maybe'completedCheckpoint ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'completedCheckpoint" a) =>
  Lens.Family2.LensLike' f s a
maybe'completedCheckpoint
  = Data.ProtoLens.Field.field @"maybe'completedCheckpoint"
maybe'epoch ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'epoch" a) =>
  Lens.Family2.LensLike' f s a
maybe'epoch = Data.ProtoLens.Field.field @"maybe'epoch"
maybe'failure ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'failure" a) =>
  Lens.Family2.LensLike' f s a
maybe'failure = Data.ProtoLens.Field.field @"maybe'failure"
maybe'start ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'start" a) =>
  Lens.Family2.LensLike' f s a
maybe'start = Data.ProtoLens.Field.field @"maybe'start"
maybe'stop ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'stop" a) =>
  Lens.Family2.LensLike' f s a
maybe'stop = Data.ProtoLens.Field.field @"maybe'stop"
metricsAtStep ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "metricsAtStep" a) =>
  Lens.Family2.LensLike' f s a
metricsAtStep = Data.ProtoLens.Field.field @"metricsAtStep"
planId ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "planId" a) =>
  Lens.Family2.LensLike' f s a
planId = Data.ProtoLens.Field.field @"planId"
pointerKey ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "pointerKey" a) =>
  Lens.Family2.LensLike' f s a
pointerKey = Data.ProtoLens.Field.field @"pointerKey"
protocolVersion ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "protocolVersion" a) =>
  Lens.Family2.LensLike' f s a
protocolVersion = Data.ProtoLens.Field.field @"protocolVersion"
resolvedPlan ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "resolvedPlan" a) =>
  Lens.Family2.LensLike' f s a
resolvedPlan = Data.ProtoLens.Field.field @"resolvedPlan"
runUuid ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "runUuid" a) =>
  Lens.Family2.LensLike' f s a
runUuid = Data.ProtoLens.Field.field @"runUuid"
seed ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "seed" a) =>
  Lens.Family2.LensLike' f s a
seed = Data.ProtoLens.Field.field @"seed"
start ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "start" a) =>
  Lens.Family2.LensLike' f s a
start = Data.ProtoLens.Field.field @"start"
step ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "step" a) =>
  Lens.Family2.LensLike' f s a
step = Data.ProtoLens.Field.field @"step"
stop ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "stop" a) =>
  Lens.Family2.LensLike' f s a
stop = Data.ProtoLens.Field.field @"stop"
substrate ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "substrate" a) =>
  Lens.Family2.LensLike' f s a
substrate = Data.ProtoLens.Field.field @"substrate"
tag ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "tag" a) =>
  Lens.Family2.LensLike' f s a
tag = Data.ProtoLens.Field.field @"tag"
timestampNs ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "timestampNs" a) =>
  Lens.Family2.LensLike' f s a
timestampNs = Data.ProtoLens.Field.field @"timestampNs"
trainingExamples ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "trainingExamples" a) =>
  Lens.Family2.LensLike' f s a
trainingExamples = Data.ProtoLens.Field.field @"trainingExamples"
trialSha ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "trialSha" a) =>
  Lens.Family2.LensLike' f s a
trialSha = Data.ProtoLens.Field.field @"trialSha"
validationLoss ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "validationLoss" a) =>
  Lens.Family2.LensLike' f s a
validationLoss = Data.ProtoLens.Field.field @"validationLoss"
value ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "value" a) =>
  Lens.Family2.LensLike' f s a
value = Data.ProtoLens.Field.field @"value"
vec'metricsAtStep ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'metricsAtStep" a) =>
  Lens.Family2.LensLike' f s a
vec'metricsAtStep = Data.ProtoLens.Field.field @"vec'metricsAtStep"