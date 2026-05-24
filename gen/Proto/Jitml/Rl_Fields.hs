{- This file was auto-generated from jitml/rl.proto by the proto-lens-protoc program. -}
{-# LANGUAGE ScopedTypeVariables, DataKinds, TypeFamilies, UndecidableInstances, GeneralizedNewtypeDeriving, MultiParamTypeClasses, FlexibleContexts, FlexibleInstances, PatternSynonyms, MagicHash, NoImplicitPrelude, DataKinds, BangPatterns, TypeApplications, OverloadedStrings, DerivingStrategies#-}
{-# OPTIONS_GHC -Wno-unused-imports#-}
{-# OPTIONS_GHC -Wno-duplicate-exports#-}
{-# OPTIONS_GHC -Wno-dodgy-exports#-}
module Proto.Jitml.Rl_Fields where
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
algorithm ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "algorithm" a) =>
  Lens.Family2.LensLike' f s a
algorithm = Data.ProtoLens.Field.field @"algorithm"
avgReward ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "avgReward" a) =>
  Lens.Family2.LensLike' f s a
avgReward = Data.ProtoLens.Field.field @"avgReward"
checkpoint ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "checkpoint" a) =>
  Lens.Family2.LensLike' f s a
checkpoint = Data.ProtoLens.Field.field @"checkpoint"
drain ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "drain" a) =>
  Lens.Family2.LensLike' f s a
drain = Data.ProtoLens.Field.field @"drain"
environment ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "environment" a) =>
  Lens.Family2.LensLike' f s a
environment = Data.ProtoLens.Field.field @"environment"
episode ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "episode" a) =>
  Lens.Family2.LensLike' f s a
episode = Data.ProtoLens.Field.field @"episode"
epoch ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "epoch" a) =>
  Lens.Family2.LensLike' f s a
epoch = Data.ProtoLens.Field.field @"epoch"
eval ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "eval" a) =>
  Lens.Family2.LensLike' f s a
eval = Data.ProtoLens.Field.field @"eval"
evalEpisodes ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "evalEpisodes" a) =>
  Lens.Family2.LensLike' f s a
evalEpisodes = Data.ProtoLens.Field.field @"evalEpisodes"
experimentHash ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "experimentHash" a) =>
  Lens.Family2.LensLike' f s a
experimentHash = Data.ProtoLens.Field.field @"experimentHash"
manifestSha ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "manifestSha" a) =>
  Lens.Family2.LensLike' f s a
manifestSha = Data.ProtoLens.Field.field @"manifestSha"
maxSteps ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maxSteps" a) =>
  Lens.Family2.LensLike' f s a
maxSteps = Data.ProtoLens.Field.field @"maxSteps"
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
maybe'episode ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'episode" a) =>
  Lens.Family2.LensLike' f s a
maybe'episode = Data.ProtoLens.Field.field @"maybe'episode"
maybe'eval ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'eval" a) =>
  Lens.Family2.LensLike' f s a
maybe'eval = Data.ProtoLens.Field.field @"maybe'eval"
maybe'metric ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'metric" a) =>
  Lens.Family2.LensLike' f s a
maybe'metric = Data.ProtoLens.Field.field @"maybe'metric"
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
metric ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "metric" a) =>
  Lens.Family2.LensLike' f s a
metric = Data.ProtoLens.Field.field @"metric"
name ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "name" a) =>
  Lens.Family2.LensLike' f s a
name = Data.ProtoLens.Field.field @"name"
pointerKey ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "pointerKey" a) =>
  Lens.Family2.LensLike' f s a
pointerKey = Data.ProtoLens.Field.field @"pointerKey"
reward ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "reward" a) =>
  Lens.Family2.LensLike' f s a
reward = Data.ProtoLens.Field.field @"reward"
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
stdReward ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "stdReward" a) =>
  Lens.Family2.LensLike' f s a
stdReward = Data.ProtoLens.Field.field @"stdReward"
step ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "step" a) =>
  Lens.Family2.LensLike' f s a
step = Data.ProtoLens.Field.field @"step"
steps ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "steps" a) =>
  Lens.Family2.LensLike' f s a
steps = Data.ProtoLens.Field.field @"steps"
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
timestampNs ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "timestampNs" a) =>
  Lens.Family2.LensLike' f s a
timestampNs = Data.ProtoLens.Field.field @"timestampNs"
value ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "value" a) =>
  Lens.Family2.LensLike' f s a
value = Data.ProtoLens.Field.field @"value"