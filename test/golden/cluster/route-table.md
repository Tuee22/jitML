| Prefix | Service | Port | Rewrite | WebSocket |
|--------|---------|------|---------|-----------|
| `/` | `jitml-demo` | 80 | `-` | no |
| `/api` | `jitml-demo` | 80 | `-` | no |
| `/api/ws` | `jitml-demo` | 80 | `-` | yes |
| `/tensorboard` | `tensorboard` | 6006 | `/` | no |
| `/grafana` | `grafana` | 3000 | `/` | no |
| `/prometheus` | `prometheus` | 9090 | `/` | no |
| `/harbor` | `jitml-harbor-portal` | 80 | `/` | no |
| `/harbor/api` | `jitml-harbor-core` | 80 | `/api` | no |
| `/minio/console` | `jitml-minio-console` | 9090 | `/` | no |
| `/minio/s3` | `jitml-minio` | 9000 | `/` | no |
| `/pulsar/admin` | `jitml-pulsar-proxy` | 80 | `/admin` | no |
| `/pulsar/ws` | `jitml-pulsar-proxy` | 80 | `/ws` | yes |
