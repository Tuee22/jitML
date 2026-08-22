| Prefix | Service | Port | Rewrite | WebSocket |
|--------|---------|------|---------|-----------|
| `/` | `jitml-demo` | 80 | `-` | no |
| `/api` | `jitml-demo` | 80 | `-` | no |
| `/api/ws` | `jitml-demo` | 80 | `-` | yes |
| `/healthz` | `jitml-service` | 8080 | `-` | no |
| `/readyz` | `jitml-service` | 8080 | `-` | no |
| `/metrics` | `jitml-service` | 8080 | `-` | no |
| `/tensorboard` | `tensorboard` | 80 | `/` | no |
| `/grafana` | `kube-prometheus-stack-grafana` | 80 | `/` | no |
| `/prometheus` | `kube-prometheus-stack-prometheus` | 9090 | `/` | no |
| `/v2` | `registry` | 5000 | `-` | no |
| `/minio/console` | `minio` | 9001 | `/` | no |
| `/minio/s3` | `minio` | 9000 | `/` | no |
| `/pulsar/admin` | `pulsar-proxy` | 80 | `/admin` | no |
| `/pulsar/ws` | `pulsar-broker` | 8080 | `/ws` | yes |
