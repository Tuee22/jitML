Phase 278 Linux CPU bootstrap environment and raw diagnostic proof directory

Supported bootstrap command: /home/ubuntu/jitml-validation/phase278-cpu-runtime/start-bootstrap.sh
This delegates ./bootstrap/linux-cpu.sh up from /home/ubuntu/jitML with base COMPOSE_FILE and JITML_BOOTSTRAP_SKIP_IMAGE_BUILD=1, after verifying and aliasing the sealed current CPU runtime image. It does not modify guest .env or the existing external validation override.
Bootstrap exit 0 at 2026-10-14T23:54:18+00:00; stdout reports 115 live phased rollout steps.
Measured publication: linux-cpu, edge_port 9091, all eight components ready, evidence live-readiness. Independently measured edge /readyz HTTP 200.
Namespace platform; Kind nodes jitml-linux-cpu-control-plane and jitml-linux-cpu-worker, each 12 GiB memory and 4 CPU from checked-in resource profile.

Runtime image: jitml:phase278-cpu-3b126ee3b94b (also required jitml:local and jitml-demo:local aliases).
Docker OCI index: sha256:f709538736db832ed6e1cdec444399543f198708a570f3a61c6bcf4f97eb5b71
Linux amd64 manifest: sha256:a9241a8132a95b143d0c2a35c90685eeb894c73895c4c29de46faf0ab96125ec
Runtime image config: sha256:038da0f26ff9b8657d248e7b9fb2c56769d9dba9cc018d884dd76d0496b37c8b
Actual service/coordinator/webapp /proc/1/exe and installed jitml SHA256: 3b126ee3b94bd2853b500a3d2a506531f296fae93204b6e20febe930adc01fe5
Both Kind nodes' OCI chain and all three running role binaries were verified independently. Raw manifests, source snapshot manifest/provenance, stdout/stderr/commands/exits, readiness headers/body, and resource measures are retained alongside this file.
Current sealed tracked-source context and image build receipts: ../phase278-cpu-runtime/.

Guest has 16 vCPU, 48 GiB fixed RAM, no swap, 300 GiB maximum sparse disk. Final bootstrap resource measure showed about 167 GiB free guest disk and 40 GiB available memory; each node used less than 4 GiB RAM.

Focused daemon PPO execution is owned by plan_audit in focused-daemon-KnZ3sZvU and jitml-phase278-focused-daemon.service. Its raw Cabal diagnostic is task-specific evidence only; this directory does not assert a standing full integration record or Phase 278 completion.
