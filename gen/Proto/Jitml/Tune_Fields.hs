{- This file was auto-generated from jitml/tune.proto by the proto-lens-protoc program. -}
{-# LANGUAGE ScopedTypeVariables, DataKinds, TypeFamilies, UndecidableInstances, GeneralizedNewtypeDeriving, MultiParamTypeClasses, FlexibleContexts, FlexibleInstances, PatternSynonyms, MagicHash, NoImplicitPrelude, DataKinds, BangPatterns, TypeApplications, OverloadedStrings, DerivingStrategies#-}
{-# OPTIONS_GHC -Wno-unused-imports#-}
{-# OPTIONS_GHC -Wno-duplicate-exports#-}
{-# OPTIONS_GHC -Wno-dodgy-exports#-}
module Proto.Jitml.Tune_Fields where
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
bestObjective ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "bestObjective" a) =>
  Lens.Family2.LensLike' f s a
bestObjective = Data.ProtoLens.Field.field @"bestObjective"
budgetPerTrial ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "budgetPerTrial" a) =>
  Lens.Family2.LensLike' f s a
budgetPerTrial = Data.ProtoLens.Field.field @"budgetPerTrial"
dhallObjectKey ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "dhallObjectKey" a) =>
  Lens.Family2.LensLike' f s a
dhallObjectKey = Data.ProtoLens.Field.field @"dhallObjectKey"
done ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "done" a) =>
  Lens.Family2.LensLike' f s a
done = Data.ProtoLens.Field.field @"done"
experimentHash ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "experimentHash" a) =>
  Lens.Family2.LensLike' f s a
experimentHash = Data.ProtoLens.Field.field @"experimentHash"
finished ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "finished" a) =>
  Lens.Family2.LensLike' f s a
finished = Data.ProtoLens.Field.field @"finished"
maybe'body ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'body" a) =>
  Lens.Family2.LensLike' f s a
maybe'body = Data.ProtoLens.Field.field @"maybe'body"
maybe'done ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'done" a) =>
  Lens.Family2.LensLike' f s a
maybe'done = Data.ProtoLens.Field.field @"maybe'done"
maybe'finished ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'finished" a) =>
  Lens.Family2.LensLike' f s a
maybe'finished = Data.ProtoLens.Field.field @"maybe'finished"
maybe'start ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'start" a) =>
  Lens.Family2.LensLike' f s a
maybe'start = Data.ProtoLens.Field.field @"maybe'start"
maybe'started ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'started" a) =>
  Lens.Family2.LensLike' f s a
maybe'started = Data.ProtoLens.Field.field @"maybe'started"
maybe'stop ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'stop" a) =>
  Lens.Family2.LensLike' f s a
maybe'stop = Data.ProtoLens.Field.field @"maybe'stop"
objective ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "objective" a) =>
  Lens.Family2.LensLike' f s a
objective = Data.ProtoLens.Field.field @"objective"
parametersJson ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "parametersJson" a) =>
  Lens.Family2.LensLike' f s a
parametersJson = Data.ProtoLens.Field.field @"parametersJson"
pruned ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "pruned" a) =>
  Lens.Family2.LensLike' f s a
pruned = Data.ProtoLens.Field.field @"pruned"
pruner ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "pruner" a) =>
  Lens.Family2.LensLike' f s a
pruner = Data.ProtoLens.Field.field @"pruner"
sampler ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "sampler" a) =>
  Lens.Family2.LensLike' f s a
sampler = Data.ProtoLens.Field.field @"sampler"
scheduler ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "scheduler" a) =>
  Lens.Family2.LensLike' f s a
scheduler = Data.ProtoLens.Field.field @"scheduler"
start ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "start" a) =>
  Lens.Family2.LensLike' f s a
start = Data.ProtoLens.Field.field @"start"
started ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "started" a) =>
  Lens.Family2.LensLike' f s a
started = Data.ProtoLens.Field.field @"started"
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
sweepSeed ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "sweepSeed" a) =>
  Lens.Family2.LensLike' f s a
sweepSeed = Data.ProtoLens.Field.field @"sweepSeed"
timestampNs ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "timestampNs" a) =>
  Lens.Family2.LensLike' f s a
timestampNs = Data.ProtoLens.Field.field @"timestampNs"
transcriptObjectKey ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "transcriptObjectKey" a) =>
  Lens.Family2.LensLike' f s a
transcriptObjectKey
  = Data.ProtoLens.Field.field @"transcriptObjectKey"
trial ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "trial" a) =>
  Lens.Family2.LensLike' f s a
trial = Data.ProtoLens.Field.field @"trial"
trialBudget ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "trialBudget" a) =>
  Lens.Family2.LensLike' f s a
trialBudget = Data.ProtoLens.Field.field @"trialBudget"
trialSeed ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "trialSeed" a) =>
  Lens.Family2.LensLike' f s a
trialSeed = Data.ProtoLens.Field.field @"trialSeed"
trialsCompleted ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "trialsCompleted" a) =>
  Lens.Family2.LensLike' f s a
trialsCompleted = Data.ProtoLens.Field.field @"trialsCompleted"
trialsPruned ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "trialsPruned" a) =>
  Lens.Family2.LensLike' f s a
trialsPruned = Data.ProtoLens.Field.field @"trialsPruned"