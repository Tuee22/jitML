-- Sprint 5.7 — typed worker `RunConfig` schema. The daemon writes one of
-- these (rendered to Dhall text in a per-run ConfigMap) before dispatching a
-- worker Job, and the worker decodes it via `Dhall.inputFile` from
-- `/etc/jitml/run/RunConfig.dhall` instead of reading the former `JITML_*`
-- environment variables. The three constructors mirror the three command
-- envelopes the daemon already dispatches (`StartTraining`, `StartSweep`,
-- `StartRLRun`).

let TrainingRunConfig : Type =
      { experimentHash : Text
      , substrate : Text
      , seed : Natural
      , epochs : Natural
      , batchSize : Natural
      , pulsarWsUrl : Text
      , slTrainLimit : Optional Natural
      , slEpochs : Optional Natural
      , slTestLimit : Optional Natural
      }

let TuneRunConfig : Type =
      { experimentHash : Text
      , substrate : Text
      , sweepSeed : Natural
      , trialBudget : Natural
      , budgetPerTrial : Natural
      , sampler : Text
      , scheduler : Text
      , pruner : Text
      , pulsarWsUrl : Text
      }

let RlRunConfig : Type =
      { experimentHash : Text
      , algorithm : Text
      , environment : Text
      , substrate : Text
      , seed : Natural
      , maxSteps : Natural
      , evalEpisodes : Natural
      , trainerKind : Text
      , pulsarWsUrl : Text
      }

in  { TrainingRunConfig = TrainingRunConfig
    , TuneRunConfig = TuneRunConfig
    , RlRunConfig = RlRunConfig
    }
