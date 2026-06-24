{-# LANGUAGE OverloadedStrings #-}

-- | Phase 2, Sprint 2.15 (durable-state Dhall DSL foundation) — the
-- @\<project\>.dhall@ ('jitml.dhall') runtime config shape and its generator.
--
-- This module mirrors 'JitML.Service.BootConfig' (typed record +
-- @render*Dhall@ + decoder), but for the __durable-state topology__: the closed
-- 'StoreRegistry' of MinIO buckets + Pulsar topics, the typed 'RetentionPolicy',
-- and a 'Budget' carried under an @assert : contractOK self === True@. The
-- vocabulary is the committed @dhall/project/Schema.dhall@; 'projectSchemaDhall'
-- is its in-source mirror (a @jitml-unit@ parity test holds the two judgmentally
-- equal). 'renderProjectConfigDhall' emits a self-contained, self-validating
-- 'jitml.dhall' that inlines the vocabulary plus a closed @StoreId@ selector — so
-- a write to an undeclared store is unnameable and an over-budget / over-quota /
-- write-to-@Retired@ / malformed-retention topology is a Dhall typecheck failure.
module JitML.Project.Config
  ( -- * The durable-state config shape
    ProjectConfig (..)
  , StoreEntry (..)
  , StoreRef (..)
  , StoreKind (..)
  , StorePhase (..)
  , RetentionPolicy (..)
  , Budget (..)
  , PodResources (..)

    -- * Default + (de)serialisation
  , defaultProjectConfig
  , renderProjectConfigDhall
  , decodeProjectConfig
  , projectConfigDecoder
  , lookupStoreRetention

    -- * Schema vocabulary (anti-drift mirror of dhall/project/Schema.dhall)
  , projectSchemaDhall
  , projectSchemaVocabulary
  , storeIdConstructor
  )
where

import Data.Char (toUpper)
import Data.Text (Text)
import Data.Text qualified as Text
import Dhall qualified
import Numeric.Natural (Natural)

-- | A durable store is either a MinIO bucket or a Pulsar topic.
data StoreKind = ObjectBucket | MessageTopic
  deriving stock (Eq, Show)

-- | Lifecycle phase. A write may only target a 'Live' store; 'Retired' keeps the
-- name in the registry (drain/GC may still name it) while making it unwriteable.
data StorePhase = Live | Retired
  deriving stock (Eq, Show)

-- | Typed retention policy — the Dhall lift of the former hardcoded
-- @KeepAll | LastN Int@, with 'Natural' bounds so @LastN 0@ is rejected.
data RetentionPolicy
  = KeepAll
  | LastN Natural
  | MaxAgeSeconds Natural
  | MaxBytes Natural
  | LastNWithinAge Natural Natural
  deriving stock (Eq, Show)

-- | One declared durable entity.
data StoreEntry = StoreEntry
  { storeLogicalName :: Text
  , storePhysicalName :: Text
  , storeKind :: StoreKind
  , storePhase :: StorePhase
  , storeQuotaUnits :: Natural
  , storeRetention :: RetentionPolicy
  }
  deriving stock (Eq, Show)

-- | A numeric compute + storage budget (whole CPU cores; memory + storage in MiB).
data Budget = Budget
  { budgetCpu :: Natural
  , budgetMemory :: Natural
  , budgetStorage :: Natural
  }
  deriving stock (Eq, Show)

-- | One workload's replicated request/limit footprint.
data PodResources = PodResources
  { podReplicas :: Natural
  , podCpuLimit :: Natural
  , podMemoryLimit :: Natural
  }
  deriving stock (Eq, Show)

-- | A reference to a declared store, carrying the resolved phase so liveness is
-- a structural check (no @Text@ equality, which Dhall lacks).
data StoreRef = StoreRef
  { refLogicalName :: Text
  , refKind :: StoreKind
  , refPhase :: StorePhase
  }
  deriving stock (Eq, Show)

-- | The closed @\<project\>.dhall@ shape. Every valid field is enumerated here;
-- an unknown field is a decode error and a missing field is a typecheck error.
data ProjectConfig = ProjectConfig
  { projectName :: Text
  , projectBudget :: Budget
  , projectPods :: [PodResources]
  , projectStores :: [StoreEntry]
  , projectWriters :: [StoreRef]
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------------
-- Decoders (mirroring JitML.Service.BootConfig's explicit Decoder style)
-- ---------------------------------------------------------------------------

storeKindDecoder :: Dhall.Decoder StoreKind
storeKindDecoder =
  Dhall.union $
    Dhall.constructor "ObjectBucket" (ObjectBucket <$ Dhall.unit)
      <> Dhall.constructor "MessageTopic" (MessageTopic <$ Dhall.unit)

storePhaseDecoder :: Dhall.Decoder StorePhase
storePhaseDecoder =
  Dhall.union $
    Dhall.constructor "Live" (Live <$ Dhall.unit)
      <> Dhall.constructor "Retired" (Retired <$ Dhall.unit)

retentionDecoder :: Dhall.Decoder RetentionPolicy
retentionDecoder =
  Dhall.union $
    Dhall.constructor "KeepAll" (KeepAll <$ Dhall.unit)
      <> Dhall.constructor "LastN" (LastN <$> Dhall.natural)
      <> Dhall.constructor "MaxAgeSeconds" (MaxAgeSeconds <$> Dhall.natural)
      <> Dhall.constructor "MaxBytes" (MaxBytes <$> Dhall.natural)
      <> Dhall.constructor
        "LastNWithinAge"
        ( Dhall.record
            ( LastNWithinAge
                <$> Dhall.field "keep" Dhall.natural
                <*> Dhall.field "maxAgeSeconds" Dhall.natural
            )
        )

storeEntryDecoder :: Dhall.Decoder StoreEntry
storeEntryDecoder =
  Dhall.record $
    StoreEntry
      <$> Dhall.field "logicalName" Dhall.strictText
      <*> Dhall.field "physicalName" Dhall.strictText
      <*> Dhall.field "kind" storeKindDecoder
      <*> Dhall.field "phase" storePhaseDecoder
      <*> Dhall.field "quotaUnits" Dhall.natural
      <*> Dhall.field "retention" retentionDecoder

budgetDecoder :: Dhall.Decoder Budget
budgetDecoder =
  Dhall.record $
    Budget
      <$> Dhall.field "cpu" Dhall.natural
      <*> Dhall.field "memory" Dhall.natural
      <*> Dhall.field "storage" Dhall.natural

podDecoder :: Dhall.Decoder PodResources
podDecoder =
  Dhall.record $
    PodResources
      <$> Dhall.field "replicas" Dhall.natural
      <*> Dhall.field "cpuLimit" Dhall.natural
      <*> Dhall.field "memoryLimit" Dhall.natural

storeRefDecoder :: Dhall.Decoder StoreRef
storeRefDecoder =
  Dhall.record $
    StoreRef
      <$> Dhall.field "refLogicalName" Dhall.strictText
      <*> Dhall.field "refKind" storeKindDecoder
      <*> Dhall.field "refPhase" storePhaseDecoder

projectConfigDecoder :: Dhall.Decoder ProjectConfig
projectConfigDecoder =
  Dhall.record $
    ProjectConfig
      <$> Dhall.field "project" Dhall.strictText
      <*> Dhall.field "budget" budgetDecoder
      <*> Dhall.field "pods" (Dhall.list podDecoder)
      <*> Dhall.field "stores" (Dhall.list storeEntryDecoder)
      <*> Dhall.field "writers" (Dhall.list storeRefDecoder)

-- | Decode a @jitml.dhall@ from disk (typechecks it, firing the @assert@).
decodeProjectConfig :: FilePath -> IO ProjectConfig
decodeProjectConfig = Dhall.inputFile projectConfigDecoder

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

renderNat :: Natural -> Text
renderNat = Text.pack . show

renderTextLit :: Text -> Text
renderTextLit t = "\"" <> t <> "\""

renderKind :: StoreKind -> Text
renderKind ObjectBucket = "StoreKind.ObjectBucket"
renderKind MessageTopic = "StoreKind.MessageTopic"

renderPhase :: StorePhase -> Text
renderPhase Live = "StorePhase.Live"
renderPhase Retired = "StorePhase.Retired"

renderRetention :: RetentionPolicy -> Text
renderRetention KeepAll = "RetentionPolicy.KeepAll"
renderRetention (LastN n) = "RetentionPolicy.LastN " <> renderNat n
renderRetention (MaxAgeSeconds s) = "RetentionPolicy.MaxAgeSeconds " <> renderNat s
renderRetention (MaxBytes b) = "RetentionPolicy.MaxBytes " <> renderNat b
renderRetention (LastNWithinAge keep age) =
  "RetentionPolicy.LastNWithinAge { keep = " <> renderNat keep <> ", maxAgeSeconds = " <> renderNat age <> " }"

renderBudget :: Budget -> Text
renderBudget b =
  "{ cpu = " <> renderNat (budgetCpu b) <> ", memory = " <> renderNat (budgetMemory b) <> ", storage = " <> renderNat (budgetStorage b) <> " }"

renderPod :: PodResources -> Text
renderPod p =
  "{ replicas = " <> renderNat (podReplicas p) <> ", cpuLimit = " <> renderNat (podCpuLimit p) <> ", memoryLimit = " <> renderNat (podMemoryLimit p) <> " }"

renderStoreEntry :: StoreEntry -> Text
renderStoreEntry e =
  "{ logicalName = "
    <> renderTextLit (storeLogicalName e)
    <> ", physicalName = "
    <> renderTextLit (storePhysicalName e)
    <> ", kind = "
    <> renderKind (storeKind e)
    <> ", phase = "
    <> renderPhase (storePhase e)
    <> ", quotaUnits = "
    <> renderNat (storeQuotaUnits e)
    <> ", retention = "
    <> renderRetention (storeRetention e)
    <> " }"

renderList :: [Text] -> Text -> Text
renderList [] ty = "[] : List " <> ty
renderList xs _ = "[ " <> Text.intercalate ", " xs <> " ]"

-- | Map a store's logical name to its @StoreId@ constructor: split on
-- @.@/@-@/@_@, capitalise each segment, concatenate. e.g. @"gc.event"@ ->
-- @"GcEvent"@, @"harbor-registry"@ -> @"HarborRegistry"@.
storeIdConstructor :: Text -> Text
storeIdConstructor =
  Text.concat . map capitalise . filter (not . Text.null) . Text.split (`elem` (".-_" :: String))
 where
  capitalise t = case Text.uncons t of
    Just (c, rest) -> Text.cons (toUpper c) rest
    Nothing -> t

-- | Render a self-contained, self-validating @jitml.dhall@: the schema
-- vocabulary, a closed @StoreId@ union + @storeFor@/@refFor@ selector (so an
-- undeclared store is unnameable), the data, and @assert : contractOK self ===
-- True@.
renderProjectConfigDhall :: ProjectConfig -> Text
renderProjectConfigDhall cfg =
  Text.intercalate
    "\n"
    [ "-- Generated by `jitml project init` (Phase 2 / Sprint 2.15). Self-contained:"
    , "-- typechecking this file IS its validation — the `assert` below rejects an"
    , "-- over-budget / over-quota / write-to-Retired / malformed-retention topology,"
    , "-- and the closed `StoreId` selector makes a write to an undeclared store"
    , "-- unnameable. Edit and re-run `dhall type` to re-validate."
    , projectSchemaVocabulary
    , storeIdUnion
    , storeForFn
    , refForFn
    , selfBinding
    , "let _ok = assert : contractOK self === True"
    , "in  self"
    , ""
    ]
 where
  stores = projectStores cfg
  ctorOf e = storeIdConstructor (storeLogicalName e)
  storeIdUnion =
    "let StoreId = < " <> Text.intercalate " | " (map ctorOf stores) <> " >"
  storeForFn =
    Text.intercalate
      "\n"
      [ "let storeFor"
      , "    : StoreId -> StoreEntry"
      , "    = \\(s : StoreId) ->"
      , "        merge"
      , "          { " <> Text.intercalate "\n          , " (map storeArm stores)
      , "          }"
      , "          s"
      ]
  storeArm e = ctorOf e <> " = " <> renderStoreEntry e
  refForFn =
    Text.intercalate
      "\n"
      [ "let refFor"
      , "    : StoreId -> StoreRef"
      , "    = \\(s : StoreId) ->"
      , "        let e = storeFor s"
      , "        in  { refLogicalName = e.logicalName, refKind = e.kind, refPhase = e.phase }"
      ]
  selfBinding =
    Text.intercalate
      "\n"
      [ "let self"
      , "    : ProjectConfig"
      , "    = { project = " <> renderTextLit (projectName cfg)
      , "      , budget = " <> renderBudget (projectBudget cfg)
      , "      , pods = " <> renderList (map renderPod (projectPods cfg)) "PodResources"
      , "      , stores = " <> renderList (map (\e -> "storeFor StoreId." <> ctorOf e) stores) "StoreEntry"
      , "      , writers = " <> renderList (map (\w -> "refFor StoreId." <> storeIdConstructor (refLogicalName w)) (projectWriters cfg)) "StoreRef"
      , "      }"
      ]

-- ---------------------------------------------------------------------------
-- The schema vocabulary (in-source mirror of dhall/project/Schema.dhall)
-- ---------------------------------------------------------------------------

-- | The let-chain of types + lemmas, identical (modulo comments/formatting) to
-- @dhall/project/Schema.dhall@. Shared by 'renderProjectConfigDhall' (which
-- appends the @StoreId@ selector + data + assert) and 'projectSchemaDhall' (which
-- appends the export record). The @jitml-unit@ parity test holds this and the
-- committed file judgmentally equal.
projectSchemaVocabulary :: Text
projectSchemaVocabulary =
  Text.intercalate
    "\n"
    [ "let StoreKind = < ObjectBucket | MessageTopic >"
    , "let StorePhase = < Live | Retired >"
    , "let RetentionPolicy ="
    , "      < KeepAll"
    , "      | LastN : Natural"
    , "      | MaxAgeSeconds : Natural"
    , "      | MaxBytes : Natural"
    , "      | LastNWithinAge : { keep : Natural, maxAgeSeconds : Natural }"
    , "      >"
    , "let StoreEntry ="
    , "      { logicalName : Text"
    , "      , physicalName : Text"
    , "      , kind : StoreKind"
    , "      , phase : StorePhase"
    , "      , quotaUnits : Natural"
    , "      , retention : RetentionPolicy"
    , "      }"
    , "let Budget = { cpu : Natural, memory : Natural, storage : Natural }"
    , "let PodResources = { replicas : Natural, cpuLimit : Natural, memoryLimit : Natural }"
    , "let StoreRef = { refLogicalName : Text, refKind : StoreKind, refPhase : StorePhase }"
    , "let ProjectConfig ="
    , "      { project : Text"
    , "      , budget : Budget"
    , "      , pods : List PodResources"
    , "      , stores : List StoreEntry"
    , "      , writers : List StoreRef"
    , "      }"
    , "let lessThanEqual ="
    , "      \\(a : Natural) -> \\(b : Natural) -> Natural/isZero (Natural/subtract b a)"
    , "let sumNat ="
    , "      \\(xs : List Natural) ->"
    , "        List/fold Natural xs Natural (\\(x : Natural) -> \\(acc : Natural) -> x + acc) 0"
    , "let mapNat ="
    , "      \\(A : Type) ->"
    , "      \\(f : A -> Natural) ->"
    , "      \\(xs : List A) ->"
    , "        List/fold"
    , "          A"
    , "          xs"
    , "          (List Natural)"
    , "          (\\(x : A) -> \\(acc : List Natural) -> [ f x ] # acc)"
    , "          ([] : List Natural)"
    , "let allList ="
    , "      \\(A : Type) ->"
    , "      \\(p : A -> Bool) ->"
    , "      \\(xs : List A) ->"
    , "        List/fold A xs Bool (\\(x : A) -> \\(acc : Bool) -> p x && acc) True"
    , "let totalCpu ="
    , "      \\(pods : List PodResources) ->"
    , "        sumNat (mapNat PodResources (\\(p : PodResources) -> p.replicas * p.cpuLimit) pods)"
    , "let totalMemory ="
    , "      \\(pods : List PodResources) ->"
    , "        sumNat (mapNat PodResources (\\(p : PodResources) -> p.replicas * p.memoryLimit) pods)"
    , "let fitsWithin ="
    , "      \\(b : Budget) ->"
    , "      \\(pods : List PodResources) ->"
    , "        lessThanEqual (totalCpu pods) b.cpu && lessThanEqual (totalMemory pods) b.memory"
    , "let totalQuota ="
    , "      \\(stores : List StoreEntry) ->"
    , "        sumNat (mapNat StoreEntry (\\(e : StoreEntry) -> e.quotaUnits) stores)"
    , "let storageFitsWithin ="
    , "      \\(b : Budget) ->"
    , "      \\(stores : List StoreEntry) ->"
    , "        lessThanEqual (totalQuota stores) b.storage"
    , "let retentionWellFormed ="
    , "      \\(rp : RetentionPolicy) ->"
    , "        merge"
    , "          { KeepAll = True"
    , "          , LastN = \\(n : Natural) -> lessThanEqual 1 n"
    , "          , MaxAgeSeconds = \\(s : Natural) -> lessThanEqual 1 s"
    , "          , MaxBytes = \\(b : Natural) -> lessThanEqual 1 b"
    , "          , LastNWithinAge ="
    , "              \\(r : { keep : Natural, maxAgeSeconds : Natural }) ->"
    , "                lessThanEqual 1 r.keep && lessThanEqual 1 r.maxAgeSeconds"
    , "          }"
    , "          rp"
    , "let allRetentionWellFormed ="
    , "      \\(stores : List StoreEntry) ->"
    , "        allList StoreEntry (\\(e : StoreEntry) -> retentionWellFormed e.retention) stores"
    , "let writerIsLive ="
    , "      \\(r : StoreRef) -> merge { Live = True, Retired = False } r.refPhase"
    , "let writersAreLive ="
    , "      \\(writers : List StoreRef) -> allList StoreRef writerIsLive writers"
    , "let contractOK ="
    , "      \\(c : ProjectConfig) ->"
    , "            fitsWithin c.budget c.pods"
    , "        &&  storageFitsWithin c.budget c.stores"
    , "        &&  allRetentionWellFormed c.stores"
    , "        &&  writersAreLive c.writers"
    ]

-- | The full committed-schema text: the vocabulary plus the export record. A
-- @jitml-unit@ parity test holds @inputExpr projectSchemaDhall@ judgmentally
-- equal to @inputExpr (dhall/project/Schema.dhall)@.
projectSchemaDhall :: Text
projectSchemaDhall =
  projectSchemaVocabulary
    <> "\n"
    <> Text.intercalate
      "\n"
      [ "in  { StoreKind"
      , "    , StorePhase"
      , "    , RetentionPolicy"
      , "    , StoreEntry"
      , "    , Budget"
      , "    , PodResources"
      , "    , StoreRef"
      , "    , ProjectConfig"
      , "    , fitsWithin"
      , "    , storageFitsWithin"
      , "    , retentionWellFormed"
      , "    , writersAreLive"
      , "    , contractOK"
      , "    }"
      ]

-- ---------------------------------------------------------------------------
-- Default durable-state topology
-- ---------------------------------------------------------------------------

bucket :: Text -> Text -> Natural -> RetentionPolicy -> StoreEntry
bucket logical physical quota retention =
  StoreEntry logical physical ObjectBucket Live quota retention

topic :: Text -> StoreEntry
topic logical = StoreEntry logical logical MessageTopic Live 0 KeepAll

writerTo :: StoreEntry -> StoreRef
writerTo e = StoreRef (storeLogicalName e) (storeKind e) (storePhase e)

-- | The default durable-state topology lifted from the current Haskell-only
-- surfaces: the seven MinIO buckets ('JitML.Storage.Buckets'), a representative
-- Pulsar topic family ('JitML.Coordinator.Topology'), and the checkpoint
-- retention formerly hardcoded as @LastN 5@. Budget + pods are sized so the
-- topology fits (the assert holds); migrating the real cluster
-- @dhall/cluster/resources.dhall@ onto this asserted budget is Phase 4 adoption.
defaultProjectConfig :: ProjectConfig
defaultProjectConfig =
  ProjectConfig
    { projectName = "jitml"
    , projectBudget = Budget {budgetCpu = 8, budgetMemory = 10240, budgetStorage = 20480}
    , projectPods =
        [ PodResources 1 2 2048 -- jitml-service
        , PodResources 1 2 3072 -- jitml-demo
        , PodResources 1 1 1024 -- minio
        , PodResources 1 1 1024 -- pulsar
        , PodResources 1 1 1024 -- service-postgres
        ]
    , projectStores = defaultStores
    , projectWriters =
        [ writerTo checkpointsStore
        , writerTo trainingEventTopic
        , writerTo gcEventTopic
        ]
    }
 where
  defaultStores =
    [ checkpointsStore
    , bucket "datasets" "jitml-datasets" 8192 KeepAll
    , bucket "transcripts" "jitml-transcripts" 1024 (MaxAgeSeconds 604800)
    , bucket "trials" "jitml-trials" 1024 KeepAll
    , bucket "tensorboard" "jitml-tensorboard" 1024 (MaxAgeSeconds 1209600)
    , bucket "artifacts" "jitml-artifacts" 1024 KeepAll
    , bucket "harbor-registry" "harbor-registry" 4096 KeepAll
    , topic "training.command"
    , trainingEventTopic
    , topic "tune.command"
    , topic "tune.event"
    , topic "rl.command"
    , topic "rl.event"
    , topic "inference.request"
    , topic "inference.result"
    , gcEventTopic
    , topic "inference.command"
    , topic "training.host-command"
    , topic "tune.host-command"
    , topic "rl.host-command"
    ]
  checkpointsStore = bucket "checkpoints" "jitml-checkpoints" 4096 (LastN 5)
  trainingEventTopic = topic "training.event"
  gcEventTopic = topic "gc.event"

-- | The retention policy declared for a store by logical name, if present — the
-- registry-sourced replacement for hardcoded retention literals (Sprint 10.8).
lookupStoreRetention :: Text -> ProjectConfig -> Maybe RetentionPolicy
lookupStoreRetention logical cfg =
  case filter ((== logical) . storeLogicalName) (projectStores cfg) of
    (entry : _) -> Just (storeRetention entry)
    [] -> Nothing
