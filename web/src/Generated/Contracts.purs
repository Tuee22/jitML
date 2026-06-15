module Generated.Contracts where

type Endpoint = { name :: String, method :: String, path :: String }

type RlAnimationFrame =
  { panel :: String
  , experimentHash :: String
  , environment :: String
  , episodeIndex :: Int
  , stepIndex :: Int
  , reward :: Number
  , done :: Boolean
  , action :: Int
  , observation :: Array Number
  , actionProbabilities :: Array Number
  , observationHash :: String
  , replayCursor :: String
  , timestampNs :: String
  }

type RlReplayFrame =
  { panel :: String
  , experimentHash :: String
  , replayId :: String
  , environment :: String
  , episodeIndex :: Int
  , stepIndex :: Int
  , action :: Int
  , reward :: Number
  , done :: Boolean
  , observation :: Array Number
  , nextObservation :: Array Number
  , policyVersion :: String
  , observationHash :: String
  , timestampNs :: String
  }

renderRlAnimationFrame :: String -> String -> Int -> Int -> Number -> Boolean -> Int -> Array Number -> Array Number -> String -> String -> String -> RlAnimationFrame
renderRlAnimationFrame experimentHash environment episodeIndex stepIndex reward done action observation actionProbabilities observationHash replayCursor timestampNs =
  { panel: "rl-trajectory"
  , experimentHash
  , environment
  , episodeIndex
  , stepIndex
  , reward
  , done
  , action
  , observation
  , actionProbabilities
  , observationHash
  , replayCursor
  , timestampNs
  }

renderRlReplayFrame :: String -> String -> String -> Int -> Int -> Int -> Number -> Boolean -> Array Number -> Array Number -> String -> String -> String -> RlReplayFrame
renderRlReplayFrame experimentHash replayId environment episodeIndex stepIndex action reward done observation nextObservation policyVersion observationHash timestampNs =
  { panel: "rl-trajectory"
  , experimentHash
  , replayId
  , environment
  , episodeIndex
  , stepIndex
  , action
  , reward
  , done
  , observation
  , nextObservation
  , policyVersion
  , observationHash
  , timestampNs
  }

endpoints :: Array Endpoint
endpoints =
  [ { name: "RunCommand", method: "POST", path: "/api/runs/{runId}/command" }
  , { name: "InferenceRun", method: "POST", path: "/api/inference" }
  , { name: "UploadImage", method: "POST", path: "/api/images" }
  , { name: "Connect4Move", method: "POST", path: "/api/connect4/move" }
  , { name: "MetricsStream", method: "GET", path: "/api/ws" }
  , { name: "TrainingStream", method: "GET", path: "/api/ws/training" }
  , { name: "RlStream", method: "GET", path: "/api/ws/rl" }
  , { name: "TuneStream", method: "GET", path: "/api/ws/tune" }
  ]
