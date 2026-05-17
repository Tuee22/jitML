-- Canonical hyperparameter-tuning Dhall mirror of the worked example in
-- ../README.md → Concrete `Some Tuning::{ … }` example.
{ name = "mnist-tune"
, dataset = "MNIST"
, model = "DeepDense"
, seed = 1729
, tuning =
    Some
      { sampler =
          { kind = "TPE"
          , seed = 1729
          , nStartupTrials = 16
          }
      , scheduler =
          { kind = "ASHA"
          , eta = 3
          , maxBudget = 50000
          , parallelism = 8
          }
      , pruner =
          { kind = "MedianPruner"
          , warmupTrials = 8
          , evalAtPercentile = 50
          }
      , space =
          { learningRate =
              { kind = "Float"
              , min = 1.0e-5
              , max = 1.0e-2
              , scale = "Log"
              }
          , batchSize =
              { kind = "Categorical"
              , values = [32, 64, 128, 256]
              }
          , dropout =
              { kind = "Float"
              , min = 0.0
              , max = 0.5
              , scale = "Linear"
              }
          , optimizer =
              { kind = "Categorical"
              , values = ["Adam", "AdamW", "SGD"]
              }
          }
      , trials = 128
      , parallelism = 8
      , objectives =
          [ { metric = "valAcc"
            , direction = "Maximise"
            }
          ]
      }
}
