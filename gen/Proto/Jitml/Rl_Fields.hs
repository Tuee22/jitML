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
action ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "action" a) =>
  Lens.Family2.LensLike' f s a
action = Data.ProtoLens.Field.field @"action"
actionProbabilities ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "actionProbabilities" a) =>
  Lens.Family2.LensLike' f s a
actionProbabilities
  = Data.ProtoLens.Field.field @"actionProbabilities"
algorithm ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "algorithm" a) =>
  Lens.Family2.LensLike' f s a
algorithm = Data.ProtoLens.Field.field @"algorithm"
animation ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "animation" a) =>
  Lens.Family2.LensLike' f s a
animation = Data.ProtoLens.Field.field @"animation"
arenaCompleted ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "arenaCompleted" a) =>
  Lens.Family2.LensLike' f s a
arenaCompleted = Data.ProtoLens.Field.field @"arenaCompleted"
arenaGames ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "arenaGames" a) =>
  Lens.Family2.LensLike' f s a
arenaGames = Data.ProtoLens.Field.field @"arenaGames"
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
done ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "done" a) =>
  Lens.Family2.LensLike' f s a
done = Data.ProtoLens.Field.field @"done"
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
game ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "game" a) =>
  Lens.Family2.LensLike' f s a
game = Data.ProtoLens.Field.field @"game"
generation ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "generation" a) =>
  Lens.Family2.LensLike' f s a
generation = Data.ProtoLens.Field.field @"generation"
generationCompleted ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "generationCompleted" a) =>
  Lens.Family2.LensLike' f s a
generationCompleted
  = Data.ProtoLens.Field.field @"generationCompleted"
generations ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "generations" a) =>
  Lens.Family2.LensLike' f s a
generations = Data.ProtoLens.Field.field @"generations"
manifestSha ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "manifestSha" a) =>
  Lens.Family2.LensLike' f s a
manifestSha = Data.ProtoLens.Field.field @"manifestSha"
maxPlies ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maxPlies" a) =>
  Lens.Family2.LensLike' f s a
maxPlies = Data.ProtoLens.Field.field @"maxPlies"
maxSteps ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maxSteps" a) =>
  Lens.Family2.LensLike' f s a
maxSteps = Data.ProtoLens.Field.field @"maxSteps"
maybe'animation ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'animation" a) =>
  Lens.Family2.LensLike' f s a
maybe'animation = Data.ProtoLens.Field.field @"maybe'animation"
maybe'arenaCompleted ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'arenaCompleted" a) =>
  Lens.Family2.LensLike' f s a
maybe'arenaCompleted
  = Data.ProtoLens.Field.field @"maybe'arenaCompleted"
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
maybe'generationCompleted ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'generationCompleted" a) =>
  Lens.Family2.LensLike' f s a
maybe'generationCompleted
  = Data.ProtoLens.Field.field @"maybe'generationCompleted"
maybe'metric ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'metric" a) =>
  Lens.Family2.LensLike' f s a
maybe'metric = Data.ProtoLens.Field.field @"maybe'metric"
maybe'replay ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'replay" a) =>
  Lens.Family2.LensLike' f s a
maybe'replay = Data.ProtoLens.Field.field @"maybe'replay"
maybe'start ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'start" a) =>
  Lens.Family2.LensLike' f s a
maybe'start = Data.ProtoLens.Field.field @"maybe'start"
maybe'startAlphaZero ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'startAlphaZero" a) =>
  Lens.Family2.LensLike' f s a
maybe'startAlphaZero
  = Data.ProtoLens.Field.field @"maybe'startAlphaZero"
maybe'stop ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'stop" a) =>
  Lens.Family2.LensLike' f s a
maybe'stop = Data.ProtoLens.Field.field @"maybe'stop"
mctsSimulationsPerMove ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "mctsSimulationsPerMove" a) =>
  Lens.Family2.LensLike' f s a
mctsSimulationsPerMove
  = Data.ProtoLens.Field.field @"mctsSimulationsPerMove"
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
nextObservation ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "nextObservation" a) =>
  Lens.Family2.LensLike' f s a
nextObservation = Data.ProtoLens.Field.field @"nextObservation"
observation ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "observation" a) =>
  Lens.Family2.LensLike' f s a
observation = Data.ProtoLens.Field.field @"observation"
observationHash ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "observationHash" a) =>
  Lens.Family2.LensLike' f s a
observationHash = Data.ProtoLens.Field.field @"observationHash"
optimizerUpdates ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "optimizerUpdates" a) =>
  Lens.Family2.LensLike' f s a
optimizerUpdates = Data.ProtoLens.Field.field @"optimizerUpdates"
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
policyVersion ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "policyVersion" a) =>
  Lens.Family2.LensLike' f s a
policyVersion = Data.ProtoLens.Field.field @"policyVersion"
protocolVersion ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "protocolVersion" a) =>
  Lens.Family2.LensLike' f s a
protocolVersion = Data.ProtoLens.Field.field @"protocolVersion"
replay ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "replay" a) =>
  Lens.Family2.LensLike' f s a
replay = Data.ProtoLens.Field.field @"replay"
replayCursor ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "replayCursor" a) =>
  Lens.Family2.LensLike' f s a
replayCursor = Data.ProtoLens.Field.field @"replayCursor"
replayId ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "replayId" a) =>
  Lens.Family2.LensLike' f s a
replayId = Data.ProtoLens.Field.field @"replayId"
resolvedPlan ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "resolvedPlan" a) =>
  Lens.Family2.LensLike' f s a
resolvedPlan = Data.ProtoLens.Field.field @"resolvedPlan"
reward ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "reward" a) =>
  Lens.Family2.LensLike' f s a
reward = Data.ProtoLens.Field.field @"reward"
samples ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "samples" a) =>
  Lens.Family2.LensLike' f s a
samples = Data.ProtoLens.Field.field @"samples"
seed ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "seed" a) =>
  Lens.Family2.LensLike' f s a
seed = Data.ProtoLens.Field.field @"seed"
selfPlayGames ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "selfPlayGames" a) =>
  Lens.Family2.LensLike' f s a
selfPlayGames = Data.ProtoLens.Field.field @"selfPlayGames"
start ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "start" a) =>
  Lens.Family2.LensLike' f s a
start = Data.ProtoLens.Field.field @"start"
startAlphaZero ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "startAlphaZero" a) =>
  Lens.Family2.LensLike' f s a
startAlphaZero = Data.ProtoLens.Field.field @"startAlphaZero"
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
vec'actionProbabilities ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'actionProbabilities" a) =>
  Lens.Family2.LensLike' f s a
vec'actionProbabilities
  = Data.ProtoLens.Field.field @"vec'actionProbabilities"
vec'nextObservation ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'nextObservation" a) =>
  Lens.Family2.LensLike' f s a
vec'nextObservation
  = Data.ProtoLens.Field.field @"vec'nextObservation"
vec'observation ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'observation" a) =>
  Lens.Family2.LensLike' f s a
vec'observation = Data.ProtoLens.Field.field @"vec'observation"
winRate ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "winRate" a) =>
  Lens.Family2.LensLike' f s a
winRate = Data.ProtoLens.Field.field @"winRate"