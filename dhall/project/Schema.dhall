-- jitML durable-state DSL vocabulary (Phase 2, Sprint 2.15).
--
-- Self-contained: NO Prelude import, NO network — evaluates in-process via the
-- Haskell `dhall` library and via `dhall type`. Mirrors the hostbootstrap
-- Core.dhall idiom (typed-pointer + `assert`-carried budget lemma) but is jitML's
-- own standalone vocabulary (it does not import hostbootstrap).
--
-- This committed file is the canonical anti-drift mirror of the constant rendered
-- by `JitML.Project.Config` (`projectSchemaDhall`); a `jitml-unit` parity test
-- holds the two judgmentally equal. The generated `jitml.dhall` (`jitml project
-- init`) inlines this same vocabulary plus a closed `StoreId` selector, the data,
-- and `assert : contractOK self === True`, so an illegal durable-state topology is
-- a typecheck failure.

let StoreKind = < ObjectBucket | MessageTopic >

let StorePhase = < Live | Retired >

let RetentionPolicy =
      < KeepAll
      | LastN : Natural
      | MaxAgeSeconds : Natural
      | MaxBytes : Natural
      | LastNWithinAge : { keep : Natural, maxAgeSeconds : Natural }
      >

let StoreEntry =
      { logicalName : Text
      , physicalName : Text
      , kind : StoreKind
      , phase : StorePhase
      , quotaUnits : Natural
      , retention : RetentionPolicy
      }

let Budget = { cpu : Natural, memory : Natural, storage : Natural }

let PodResources = { replicas : Natural, cpuLimit : Natural, memoryLimit : Natural }

let StoreRef = { refLogicalName : Text, refKind : StoreKind, refPhase : StorePhase }

let ProjectConfig =
      { project : Text
      , budget : Budget
      , pods : List PodResources
      , stores : List StoreEntry
      , writers : List StoreRef
      }

let lessThanEqual =
      \(a : Natural) -> \(b : Natural) -> Natural/isZero (Natural/subtract b a)

let sumNat =
      \(xs : List Natural) ->
        List/fold Natural xs Natural (\(x : Natural) -> \(acc : Natural) -> x + acc) 0

let mapNat =
      \(A : Type) ->
      \(f : A -> Natural) ->
      \(xs : List A) ->
        List/fold
          A
          xs
          (List Natural)
          (\(x : A) -> \(acc : List Natural) -> [ f x ] # acc)
          ([] : List Natural)

let allList =
      \(A : Type) ->
      \(p : A -> Bool) ->
      \(xs : List A) ->
        List/fold A xs Bool (\(x : A) -> \(acc : Bool) -> p x && acc) True

let totalCpu =
      \(pods : List PodResources) ->
        sumNat (mapNat PodResources (\(p : PodResources) -> p.replicas * p.cpuLimit) pods)

let totalMemory =
      \(pods : List PodResources) ->
        sumNat (mapNat PodResources (\(p : PodResources) -> p.replicas * p.memoryLimit) pods)

let fitsWithin =
      \(b : Budget) ->
      \(pods : List PodResources) ->
        lessThanEqual (totalCpu pods) b.cpu && lessThanEqual (totalMemory pods) b.memory

let totalQuota =
      \(stores : List StoreEntry) ->
        sumNat (mapNat StoreEntry (\(e : StoreEntry) -> e.quotaUnits) stores)

let storageFitsWithin =
      \(b : Budget) ->
      \(stores : List StoreEntry) ->
        lessThanEqual (totalQuota stores) b.storage

let retentionWellFormed =
      \(rp : RetentionPolicy) ->
        merge
          { KeepAll = True
          , LastN = \(n : Natural) -> lessThanEqual 1 n
          , MaxAgeSeconds = \(s : Natural) -> lessThanEqual 1 s
          , MaxBytes = \(b : Natural) -> lessThanEqual 1 b
          , LastNWithinAge =
              \(r : { keep : Natural, maxAgeSeconds : Natural }) ->
                lessThanEqual 1 r.keep && lessThanEqual 1 r.maxAgeSeconds
          }
          rp

let allRetentionWellFormed =
      \(stores : List StoreEntry) ->
        allList StoreEntry (\(e : StoreEntry) -> retentionWellFormed e.retention) stores

let writerIsLive =
      \(r : StoreRef) -> merge { Live = True, Retired = False } r.refPhase

let writersAreLive =
      \(writers : List StoreRef) -> allList StoreRef writerIsLive writers

let contractOK =
      \(c : ProjectConfig) ->
            fitsWithin c.budget c.pods
        &&  storageFitsWithin c.budget c.stores
        &&  allRetentionWellFormed c.stores
        &&  writersAreLive c.writers

in  { StoreKind
    , StorePhase
    , RetentionPolicy
    , StoreEntry
    , Budget
    , PodResources
    , StoreRef
    , ProjectConfig
    , fitsWithin
    , storageFitsWithin
    , retentionWellFormed
    , writersAreLive
    , contractOK
    }
