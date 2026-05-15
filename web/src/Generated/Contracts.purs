module Generated.Contracts where

type Endpoint = { name :: String, method :: String, path :: String }

endpoints :: Array Endpoint
endpoints =
  [ { name: "RunCommand", method: "POST", path: "/api/runs/{runId}/command" }
  , { name: "InferenceRun", method: "POST", path: "/api/inference" }
  , { name: "UploadImage", method: "POST", path: "/api/images" }
  , { name: "Connect4Move", method: "POST", path: "/api/connect4/move" }
  , { name: "MetricsStream", method: "GET", path: "/api/ws" }
  ]
