module Generated.AdminPortals where

type AdminPortal = { name :: String, path :: String, label :: String }

adminPortals :: Array AdminPortal
adminPortals =
  [ { name: "grafana", path: "/grafana", label: "Grafana" }
  , { name: "prometheus", path: "/prometheus", label: "Prometheus" }
  , { name: "tensorboard", path: "/tensorboard", label: "TensorBoard" }
  , { name: "harbor-portal", path: "/harbor", label: "Harbor" }
  , { name: "minio-console", path: "/minio/console", label: "MinIO console" }
  , { name: "pulsar-admin", path: "/pulsar/admin", label: "Pulsar admin" }
  ]
