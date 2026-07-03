-- Sprint 5.7 — typed worker `RunConfig` schema. The daemon writes one of
-- these (rendered to Dhall text in a per-run ConfigMap) before dispatching a
-- worker Job, and the worker decodes it via `Dhall.inputFile` from
-- `/etc/jitml/run/RunConfig.dhall` instead of reading the former `JITML_*`
-- environment variables. The worker records mirror the three command envelopes
-- the daemon already dispatches (`StartTraining`, `StartSweep`, `StartRLRun`).
-- The inference-selector records mirror the Phase 21 type-state boundary: a
-- browser or worker inference selector names completed-training evidence rather
-- than a declared or partial experiment.

let TrainingEvidence : Type =
      { initialWeightHash : Text
      , finalWeightHash : Text
      , updateCount : Natural
      , datasetShaAtRead : Text
      }

let CompletedTrainingWitness : Type =
      { experimentHash : Text
      , manifestSha : Text
      , provenanceKind : Text
      , evidence :
          { initialWeightHash : Text
          , finalWeightHash : Text
          , updateCount : Natural
          , datasetShaAtRead : Text
          }
      , convergencePassed : Bool
      }

let InferenceSelector : Type =
      { experimentHash : Text
      , manifestSha : Text
      , completedTraining :
          { experimentHash : Text
          , manifestSha : Text
          , provenanceKind : Text
          , evidence :
              { initialWeightHash : Text
              , finalWeightHash : Text
              , updateCount : Natural
              , datasetShaAtRead : Text
              }
          , convergencePassed : Bool
          }
      }

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
      , atariRomPath : Optional Text
      , pulsarWsUrl : Text
      }

in  { TrainingEvidence = TrainingEvidence
    , CompletedTrainingWitness = CompletedTrainingWitness
    , InferenceSelector = InferenceSelector
    , TrainingRunConfig = TrainingRunConfig
    , TuneRunConfig = TuneRunConfig
    , RlRunConfig = RlRunConfig
    }
