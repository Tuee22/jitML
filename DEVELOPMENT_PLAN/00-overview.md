# jitML Development Plan — Overview

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [development_plan_standards.md](development_plan_standards.md), [system-components.md](system-components.md), [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md), [../README.md](../README.md), [../documents/engineering/run_contract.md](../documents/engineering/run_contract.md), [phase-1-canonical-plan-suite-bootstrap.md](phase-1-canonical-plan-suite-bootstrap.md), [phase-2-doctrine-driven-scheduling-audit.md](phase-2-doctrine-driven-scheduling-audit.md), [phase-3-governed-document-metadata-enforcement.md](phase-3-governed-document-metadata-enforcement.md), [phase-4-toolchain-pin-and-library-first-cabal-project.md](phase-4-toolchain-pin-and-library-first-cabal-project.md), [phase-5-commandspec-registry-and-generated-parser.md](phase-5-commandspec-registry-and-generated-parser.md), [phase-6-generated-sections-and-tracking-generated-paths.md](phase-6-generated-sections-and-tracking-generated-paths.md), [phase-7-lint-stack-fourmolu-hlint-cabal-format-forbiddenpathregistry.md](phase-7-lint-stack-fourmolu-hlint-cabal-format-forbiddenpathregistry.md), [phase-8-plan-apply-boundary-with-dry-run-and-plan-file.md](phase-8-plan-apply-boundary-with-dry-run-and-plan-file.md), [phase-9-subprocess-typed-values-runstreaming-capture-interpreter.md](phase-9-subprocess-typed-values-runstreaming-capture-interpreter.md), [phase-10-prerequisite-registry-as-typed-effects.md](phase-10-prerequisite-registry-as-typed-effects.md), [phase-11-env-record-and-readert-env-io-runner.md](phase-11-env-record-and-readert-env-io-runner.md), [phase-12-apperror-adt-rendererror-output-rules.md](phase-12-apperror-adt-rendererror-output-rules.md), [phase-13-scoped-allow-newer-retirement-gate.md](phase-13-scoped-allow-newer-retirement-gate.md), [phase-14-ghc-9-12-4-baseline-and-dependency-helper-retirement.md](phase-14-ghc-9-12-4-baseline-and-dependency-helper-retirement.md), [phase-15-cli-dhall-overrides.md](phase-15-cli-dhall-overrides.md), [phase-16-remove-verify-cross-backend-add-jitml-test-test-options-pass.md](phase-16-remove-verify-cross-backend-add-jitml-test-test-options-pass.md), [phase-17-reinstate-the-jitml-internal-vm-build-vm-command-surface.md](phase-17-reinstate-the-jitml-internal-vm-build-vm-command-surface.md), [phase-18-retire-vm-lifecycle-commands-for-fixed-bridge-apple-metal.md](phase-18-retire-vm-lifecycle-commands-for-fixed-bridge-apple-metal.md), [phase-19-remove-placeholder-top-level-cli-groups.md](phase-19-remove-placeholder-top-level-cli-groups.md), [phase-20-typed-numeric-cli-parsing-and-generated-only-command-referen.md](phase-20-typed-numeric-cli-parsing-and-generated-only-command-referen.md), [phase-21-structured-subprocess-outcomes.md](phase-21-structured-subprocess-outcomes.md), [phase-22-stage-0-bootstrap-gates-and-delegation.md](phase-22-stage-0-bootstrap-gates-and-delegation.md), [phase-23-populated-prerequisiteregistry-and-lazy-remediation.md](phase-23-populated-prerequisiteregistry-and-lazy-remediation.md), [phase-24-jit-cache-layout-and-content-addressing.md](phase-24-jit-cache-layout-and-content-addressing.md), [phase-25-outer-container-linux-builds-and-jitml-local-image.md](phase-25-outer-container-linux-builds-and-jitml-local-image.md), [phase-26-superseded-apple-silicon-vm-scaffold.md](phase-26-superseded-apple-silicon-vm-scaffold.md), [phase-27-bootstrap-script-wrappers-and-status.md](phase-27-bootstrap-script-wrappers-and-status.md), [phase-28-bootstrap-down-and-purge.md](phase-28-bootstrap-down-and-purge.md), [phase-29-dhall-cluster-resource-profile-kind-node-cap-and-host-ram-pr.md](phase-29-dhall-cluster-resource-profile-kind-node-cap-and-host-ram-pr.md), [phase-30-reconciler-sh-c-control-flow-typed-haskell.md](phase-30-reconciler-sh-c-control-flow-typed-haskell.md), [phase-31-retire-the-tart-prerequisite-and-jitml-internal-vm-commands.md](phase-31-retire-the-tart-prerequisite-and-jitml-internal-vm-commands.md), [phase-32-reinstate-the-tart-build-vm-prerequisite-and-lifecycle.md](phase-32-reinstate-the-tart-build-vm-prerequisite-and-lifecycle.md), [phase-33-replace-tart-prerequisites-with-fixed-bridge-apple-cache-pre.md](phase-33-replace-tart-prerequisites-with-fixed-bridge-apple-cache-pre.md), [phase-34-authenticated-third-party-image-pre-pull-before-kind-load.md](phase-34-authenticated-third-party-image-pre-pull-before-kind-load.md), [phase-35-in-cluster-docker-hub-imagepullsecret-authenticated-pod-pull.md](phase-35-in-cluster-docker-hub-imagepullsecret-authenticated-pod-pull.md), [phase-36-durable-state-dhall-dsl-foundation-and-jitml-project-init.md](phase-36-durable-state-dhall-dsl-foundation-and-jitml-project-init.md), [phase-37-per-substrate-kind-configs-and-extramounts.md](phase-37-per-substrate-kind-configs-and-extramounts.md), [phase-38-kubernetes-io-no-provisioner-storage-and-manual-pvs.md](phase-38-kubernetes-io-no-provisioner-storage-and-manual-pvs.md), [phase-39-envoy-gateway-and-single-127-0-0-1-edge-port-listener.md](phase-39-envoy-gateway-and-single-127-0-0-1-edge-port-listener.md), [phase-40-typed-route-registry-and-generated-httproute-manifests.md](phase-40-typed-route-registry-and-generated-httproute-manifests.md), [phase-41-cluster-lifecycle-reconciler-and-phased-deploy.md](phase-41-cluster-lifecycle-reconciler-and-phased-deploy.md), [phase-42-ha-kind-node-and-manual-pv-topology.md](phase-42-ha-kind-node-and-manual-pv-topology.md), [phase-43-live-cluster-lifecycle-and-publication-truth.md](phase-43-live-cluster-lifecycle-and-publication-truth.md), [phase-44-harbor-subchart-and-bootstrap-phase-install.md](phase-44-harbor-subchart-and-bootstrap-phase-install.md), [phase-45-percona-pg-operator-and-patroni-managed-service-postgres.md](phase-45-percona-pg-operator-and-patroni-managed-service-postgres.md), [phase-46-minio-subchart-bucket-provisioning-conditional-write-server.md](phase-46-minio-subchart-bucket-provisioning-conditional-write-server.md), [phase-47-apache-pulsar-ha-and-topic-bootstrap.md](phase-47-apache-pulsar-ha-and-topic-bootstrap.md), [phase-48-kube-prometheus-stack-and-provisioned-dashboards.md](phase-48-kube-prometheus-stack-and-provisioned-dashboards.md), [phase-49-tensorboard-with-minio-event-storage-and-checkpoint-sidecar.md](phase-49-tensorboard-with-minio-event-storage-and-checkpoint-sidecar.md), [phase-50-nvidia-runtimeclass-for-linux-cuda.md](phase-50-nvidia-runtimeclass-for-linux-cuda.md), [phase-51-per-pod-resource-limits-and-right-sized-replicas-from-the-dh.md](phase-51-per-pod-resource-limits-and-right-sized-replicas-from-the-dh.md), [phase-52-project-the-durable-state-storeregistry-over-minio-buckets.md](phase-52-project-the-durable-state-storeregistry-over-minio-buckets.md), [phase-53-ha-platform-service-topology.md](phase-53-ha-platform-service-topology.md), [phase-54-jitml-service-entry-point-and-lifecycle-summary.md](phase-54-jitml-service-entry-point-and-lifecycle-summary.md), [phase-55-bootconfig-liveconfig-dhall-and-hot-reload-schema-surface.md](phase-55-bootconfig-liveconfig-dhall-and-hot-reload-schema-surface.md), [phase-56-healthz-readyz-metrics-and-structured-logging.md](phase-56-healthz-readyz-metrics-and-structured-logging.md), [phase-57-retrypolicy-and-service-error-surface.md](phase-57-retrypolicy-and-service-error-surface.md), [phase-58-at-least-once-pulsar-consumer-with-message-hash-deduplicatio.md](phase-58-at-least-once-pulsar-consumer-with-message-hash-deduplicatio.md), [phase-59-stateless-deployment-pod-anti-affinity-per-substrate-dhall.md](phase-59-stateless-deployment-pod-anti-affinity-per-substrate-dhall.md), [phase-60-typed-dhall-runconfig-and-bootconfig-mounted-worker-dispatch.md](phase-60-typed-dhall-runconfig-and-bootconfig-mounted-worker-dispatch.md), [phase-61-retire-tart-vm-lifecycle-from-the-daemon.md](phase-61-retire-tart-vm-lifecycle-from-the-daemon.md), [phase-62-reinstate-the-dhall-configured-build-vm-block-and-daemon-acq.md](phase-62-reinstate-the-dhall-configured-build-vm-block-and-daemon-acq.md), [phase-63-replace-daemon-build-vm-acquire-with-metal-bridge-acquire.md](phase-63-replace-daemon-build-vm-acquire-with-metal-bridge-acquire.md), [phase-64-workload-placement-planner-and-apple-host-workload-dispatch.md](phase-64-workload-placement-planner-and-apple-host-workload-dispatch.md), [phase-65-reflected-dhall-schema.md](phase-65-reflected-dhall-schema.md), [phase-66-coordinator-topic-algebra.md](phase-66-coordinator-topic-algebra.md), [phase-67-one-binary-engine-coordinator-webapp-role-model.md](phase-67-one-binary-engine-coordinator-webapp-role-model.md), [phase-68-reconcile-the-pulsar-topic-family-with-the-storeregistry.md](phase-68-reconcile-the-pulsar-topic-family-with-the-storeregistry.md), [phase-69-one-numerical-worker-per-kubernetes-node.md](phase-69-one-numerical-worker-per-kubernetes-node.md), [phase-70-fail-closed-mounted-worker-runconfig.md](phase-70-fail-closed-mounted-worker-runconfig.md), [phase-71-receipt-bound-delivery-and-total-settlement.md](phase-71-receipt-bound-delivery-and-total-settlement.md), [phase-72-layer-catalog.md](phase-72-layer-catalog.md), [phase-73-activations-real-and-complex.md](phase-73-activations-real-and-complex.md), [phase-74-spectral-frequency-domain-operations.md](phase-74-spectral-frequency-domain-operations.md), [phase-75-optimizers-and-schedulers.md](phase-75-optimizers-and-schedulers.md), [phase-76-loss-functions.md](phase-76-loss-functions.md), [phase-77-dhall-schemas-and-cross-type-audit.md](phase-77-dhall-schemas-and-cross-type-audit.md), [phase-78-kernelspec-cache-key-inputs-ffi-loader-surface.md](phase-78-kernelspec-cache-key-inputs-ffi-loader-surface.md), [phase-79-engine-abi-and-engines-module-skeleton.md](phase-79-engine-abi-and-engines-module-skeleton.md), [phase-80-linux-cpu-engine-and-onednn-codegen-driver.md](phase-80-linux-cpu-engine-and-onednn-codegen-driver.md), [phase-81-linux-cuda-engine-and-cuda-codegen-driver.md](phase-81-linux-cuda-engine-and-cuda-codegen-driver.md), [phase-82-apple-silicon-engine-metal-codegen-host-forwarding-scaffoldi.md](phase-82-apple-silicon-engine-metal-codegen-host-forwarding-scaffoldi.md), [phase-83-hardware-auto-tuning-within-the-determinism-contract.md](phase-83-hardware-auto-tuning-within-the-determinism-contract.md), [phase-84-haskell-owned-runtime-jit-source-generation.md](phase-84-haskell-owned-runtime-jit-source-generation.md), [phase-85-headless-apple-metal-jit-runtime-compilation-host-swift-buil.md](phase-85-headless-apple-metal-jit-runtime-compilation-host-swift-buil.md), [phase-86-compose-gpu-service-split.md](phase-86-compose-gpu-service-split.md), [phase-87-route-the-apple-swift-build-through-the-tart-vm.md](phase-87-route-the-apple-swift-build-through-the-tart-vm.md), [phase-88-fixed-host-metal-bridge-and-source-metadata-apple-cache.md](phase-88-fixed-host-metal-bridge-and-source-metadata-apple-cache.md), [phase-89-local-supervised-canonical-summaries.md](phase-89-local-supervised-canonical-summaries.md), [phase-90-jitml-train-local-cli-summary.md](phase-90-jitml-train-local-cli-summary.md), [phase-91-rl-catalog-hook-for-canonical-tests.md](phase-91-rl-catalog-hook-for-canonical-tests.md), [phase-92-rl-metadata-primitives.md](phase-92-rl-metadata-primitives.md), [phase-93-rl-cli-summaries-and-report-hooks.md](phase-93-rl-cli-summaries-and-report-hooks.md), [phase-94-rl-training-plan-surface.md](phase-94-rl-training-plan-surface.md), [phase-95-rlrunlifecycle-gadt-retrofit.md](phase-95-rlrunlifecycle-gadt-retrofit.md), [phase-96-ale-boundary-and-rom-policy.md](phase-96-ale-boundary-and-rom-policy.md), [phase-97-copyright-free-visual-rl-demo-environment.md](phase-97-copyright-free-visual-rl-demo-environment.md), [phase-98-sl-substrate-backed-training-real-eval.md](phase-98-sl-substrate-backed-training-real-eval.md), [phase-99-rl-framework-substrate-routing.md](phase-99-rl-framework-substrate-routing.md), [phase-100-no-caveat-sl-rl-framework-runtime.md](phase-100-no-caveat-sl-rl-framework-runtime.md), [phase-101-real-sl-loss-validation-driven-selection-and-convergence-per.md](phase-101-real-sl-loss-validation-driven-selection-and-convergence-per.md), [phase-102-fixed-budget-training-witness-and-inference-ineligible-parti.md](phase-102-fixed-budget-training-witness-and-inference-ineligible-parti.md), [phase-103-typed-fail-closed-rl-device-errors.md](phase-103-typed-fail-closed-rl-device-errors.md), [phase-104-validated-runplan-and-pure-contract-algebra.md](phase-104-validated-runplan-and-pure-contract-algebra.md), [phase-105-on-policy-algorithm-metadata.md](phase-105-on-policy-algorithm-metadata.md), [phase-106-off-policy-algorithm-metadata.md](phase-106-off-policy-algorithm-metadata.md), [phase-107-specialised-algorithm-metadata.md](phase-107-specialised-algorithm-metadata.md), [phase-108-local-rl-canonical-tests.md](phase-108-local-rl-canonical-tests.md), [phase-109-alphazero-connect-4-transcript-surface.md](phase-109-alphazero-connect-4-transcript-surface.md), [phase-110-connect-4-local-game-surface.md](phase-110-connect-4-local-game-surface.md), [phase-111-hyperparameter-tuning-sampler-scheduler-pruner.md](phase-111-hyperparameter-tuning-sampler-scheduler-pruner.md), [phase-112-copyright-free-rl-matrix-retargeting.md](phase-112-copyright-free-rl-matrix-retargeting.md), [phase-113-real-rl-eval-rollout-and-per-algorithm-on-device-rollouts.md](phase-113-real-rl-eval-rollout-and-per-algorithm-on-device-rollouts.md), [phase-114-real-mcts-tree-search-with-substrate-backed-leaf-evaluation.md](phase-114-real-mcts-tree-search-with-substrate-backed-leaf-evaluation.md), [phase-115-real-hyperparameter-tuning-objective-executor.md](phase-115-real-hyperparameter-tuning-objective-executor.md), [phase-116-no-caveat-rl-alphazero-and-tuning-runtime.md](phase-116-no-caveat-rl-alphazero-and-tuning-runtime.md), [phase-117-real-rl-convergence-performance-metrics-and-the-alphazero-ar.md](phase-117-real-rl-convergence-performance-metrics-and-the-alphazero-ar.md), [phase-118-all-rl-fixed-budget-convergence-metrics.md](phase-118-all-rl-fixed-budget-convergence-metrics.md), [phase-119-typed-tuning-resume-decode-failures.md](phase-119-typed-tuning-resume-decode-failures.md), [phase-120-tuning-override-and-worker-axis-fidelity.md](phase-120-tuning-override-and-worker-axis-fidelity.md), [phase-121-resolved-alphazero-and-tuning-plans.md](phase-121-resolved-alphazero-and-tuning-plans.md), [phase-122-storage-layout-and-split-blob-schema.md](phase-122-storage-layout-and-split-blob-schema.md), [phase-123-jmw1-wire-format-and-manifest-cbor.md](phase-123-jmw1-wire-format-and-manifest-cbor.md), [phase-124-bit-determinism-contract-and-retention-reconciler.md](phase-124-bit-determinism-contract-and-retention-reconciler.md), [phase-125-inference-only-read-path.md](phase-125-inference-only-read-path.md), [phase-126-remove-the-synthetic-inference-offset.md](phase-126-remove-the-synthetic-inference-offset.md), [phase-127-exact-v2-supervised-runtime-artifact.md](phase-127-exact-v2-supervised-runtime-artifact.md), [phase-128-async-work-inference-workflow-and-ready-readiness-gate.md](phase-128-async-work-inference-workflow-and-ready-readiness-gate.md), [phase-129-typed-retentionpolicy-replaces-the-lastn-5-literal.md](phase-129-typed-retentionpolicy-replaces-the-lastn-5-literal.md), [phase-130-real-trained-demo-checkpoints-delete-the-synthetic-weight-ra.md](phase-130-real-trained-demo-checkpoints-delete-the-synthetic-weight-ra.md), [phase-131-inference-eligible-checkpoints-and-convergence-statistics.md](phase-131-inference-eligible-checkpoints-and-convergence-statistics.md), [phase-132-typed-checkpoint-object-key-validation.md](phase-132-typed-checkpoint-object-key-validation.md), [phase-133-persisted-checkpoint-proof-admission.md](phase-133-persisted-checkpoint-proof-admission.md), [phase-134-minimal-purescript-application-scaffold.md](phase-134-minimal-purescript-application-scaffold.md), [phase-135-browser-contract-adts-and-local-contract-rendering.md](phase-135-browser-contract-adts-and-local-contract-rendering.md), [phase-136-jitml-lint-purescript-generated-contract-smoke-target.md](phase-136-jitml-lint-purescript-generated-contract-smoke-target.md), [phase-137-interactive-endpoint-contract-surface.md](phase-137-interactive-endpoint-contract-surface.md), [phase-138-webapp-route-and-deployment-surface.md](phase-138-webapp-route-and-deployment-surface.md), [phase-139-playwright-e2e-suite.md](phase-139-playwright-e2e-suite.md), [phase-140-spa-portals-home-and-shared-header.md](phase-140-spa-portals-home-and-shared-header.md), [phase-141-demo-endpoints-render-real-substrate-output.md](phase-141-demo-endpoints-render-real-substrate-output.md), [phase-142-full-interactive-demo-surface.md](phase-142-full-interactive-demo-surface.md), [phase-143-webapp-role-and-websocket-driven-inference-panels.md](phase-143-webapp-role-and-websocket-driven-inference-panels.md), [phase-144-all-model-trained-artifact-ui-and-admin-navigation.md](phase-144-all-model-trained-artifact-ui-and-admin-navigation.md), [phase-145-jitml-unit-stanza.md](phase-145-jitml-unit-stanza.md), [phase-146-jitml-integration-stanza-subprocess-boundary-determinism.md](phase-146-jitml-integration-stanza-subprocess-boundary-determinism.md), [phase-147-jitml-sl-canonicals-stanza.md](phase-147-jitml-sl-canonicals-stanza.md), [phase-148-jitml-rl-canonicals-stanza.md](phase-148-jitml-rl-canonicals-stanza.md), [phase-149-jitml-hyperparameter-stanza.md](phase-149-jitml-hyperparameter-stanza.md), [phase-150-jitml-cross-backend-stanza.md](phase-150-jitml-cross-backend-stanza.md), [phase-151-jitml-daemon-lifecycle-stanza.md](phase-151-jitml-daemon-lifecycle-stanza.md), [phase-152-jitml-e2e-stanza-and-live-plan-orchestrator.md](phase-152-jitml-e2e-stanza-and-live-plan-orchestrator.md), [phase-153-jitml-test-all-orchestrator-and-report-card.md](phase-153-jitml-test-all-orchestrator-and-report-card.md), [phase-154-substrate-partitioned-test-lanes-remove-the-cross-substrate.md](phase-154-substrate-partitioned-test-lanes-remove-the-cross-substrate.md), [phase-155-dry-real-workflow-matrix-fail-closed.md](phase-155-dry-real-workflow-matrix-fail-closed.md), [phase-156-live-job-failure-observation-and-apple-placement-assertions.md](phase-156-live-job-failure-observation-and-apple-placement-assertions.md), [phase-157-playwright-no-caveat-e2e-matrix.md](phase-157-playwright-no-caveat-e2e-matrix.md), [phase-158-common-shape-workflow-topic-algebra-and-websocket-coverage.md](phase-158-common-shape-workflow-topic-algebra-and-websocket-coverage.md), [phase-159-per-model-integration-and-e2e-matrix.md](phase-159-per-model-integration-and-e2e-matrix.md), [phase-160-functional-core-live-workflow-interpreter.md](phase-160-functional-core-live-workflow-interpreter.md), [phase-161-full-canonical-model-matrix-runtime.md](phase-161-full-canonical-model-matrix-runtime.md), [phase-162-re-attest-the-no-caveat-runtime-with-real-losses-metrics.md](phase-162-re-attest-the-no-caveat-runtime-with-real-losses-metrics.md), [phase-163-fixed-budget-all-model-runtime-gate-linux-cpu.md](phase-163-fixed-budget-all-model-runtime-gate-linux-cpu.md), [phase-164-full-workflow-control-surface.md](phase-164-full-workflow-control-surface.md), [phase-165-playwright-no-caveat-product-matrix.md](phase-165-playwright-no-caveat-product-matrix.md), [phase-166-real-demo-inference-full-width-multi-layer-forward-real-inpu.md](phase-166-real-demo-inference-full-width-multi-layer-forward-real-inpu.md), [phase-167-all-model-browser-and-playwright-trained-artifact-matrix.md](phase-167-all-model-browser-and-playwright-trained-artifact-matrix.md), [phase-168-ephemeral-kind-helm-rollout.md](phase-168-ephemeral-kind-helm-rollout.md), [phase-169-live-capability-class-validation-minio-pulsar-harbor.md](phase-169-live-capability-class-validation-minio-pulsar-harbor.md), [phase-170-daemon-training-rl-tune-handlers-on-live-broker.md](phase-170-daemon-training-rl-tune-handlers-on-live-broker.md), [phase-171-live-sl-training-e2e-with-real-datasets.md](phase-171-live-sl-training-e2e-with-real-datasets.md), [phase-172-real-rl-environment-simulators-and-daemon-env-loop.md](phase-172-real-rl-environment-simulators-and-daemon-env-loop.md), [phase-173-live-rl-training-e2e-with-statistical-convergence-assertions.md](phase-173-live-rl-training-e2e-with-statistical-convergence-assertions.md), [phase-174-live-minio-checkpoint-round-trip-and-retention.md](phase-174-live-minio-checkpoint-round-trip-and-retention.md), [phase-175-real-cuda-rl-algorithm-losses-through-jit-engine.md](phase-175-real-cuda-rl-algorithm-losses-through-jit-engine.md), [phase-176-alphazero-with-real-network-priors.md](phase-176-alphazero-with-real-network-priors.md), [phase-177-live-tuning-sweep-with-minio-trial-persistence.md](phase-177-live-tuning-sweep-with-minio-trial-persistence.md), [phase-178-cuda-and-linux-cpu-production-weight-loading.md](phase-178-cuda-and-linux-cpu-production-weight-loading.md), [phase-179-live-jitml-inference-run-and-legacy-replay-helper.md](phase-179-live-jitml-inference-run-and-legacy-replay-helper.md), [phase-180-live-api-ws-websocket-proxy-and-compiled-halogen-bundle.md](phase-180-live-api-ws-websocket-proxy-and-compiled-halogen-bundle.md), [phase-181-live-playwright-on-demo-edge-route.md](phase-181-live-playwright-on-demo-edge-route.md), [phase-182-linux-cpu-full-tensor-benchmark-payloads-and-first-cache-mis.md](phase-182-linux-cpu-full-tensor-benchmark-payloads-and-first-cache-mis.md), [phase-183-re-validate-the-linux-cuda-lane-runs-for-real-with-the-skip.md](phase-183-re-validate-the-linux-cuda-lane-runs-for-real-with-the-skip.md), [phase-184-live-linux-cpu-exercise-of-the-reopened-workflows.md](phase-184-live-linux-cpu-exercise-of-the-reopened-workflows.md), [phase-185-live-linux-cuda-exercise-of-the-reopened-workflows.md](phase-185-live-linux-cuda-exercise-of-the-reopened-workflows.md), [phase-186-live-cluster-closure-of-the-reopened-workflows.md](phase-186-live-cluster-closure-of-the-reopened-workflows.md), [phase-187-linux-no-caveat-runtime-and-browser-lane.md](phase-187-linux-no-caveat-runtime-and-browser-lane.md), [phase-188-linux-cuda-all-model-trained-artifact-lane.md](phase-188-linux-cuda-all-model-trained-artifact-lane.md), [phase-189-linux-cuda-ha-cluster-revalidation.md](phase-189-linux-cuda-ha-cluster-revalidation.md), [phase-190-host-swift-toolchain-and-first-cache-miss-headless-build.md](phase-190-host-swift-toolchain-and-first-cache-miss-headless-build.md), [phase-191-metal-ffi-loading-and-host-kernel-launch.md](phase-191-metal-ffi-loading-and-host-kernel-launch.md), [phase-192-metal-benchmark-candidate-runner-live-execution.md](phase-192-metal-benchmark-candidate-runner-live-execution.md), [phase-193-apple-host-cluster-pulsar-rpc-live-flow.md](phase-193-apple-host-cluster-pulsar-rpc-live-flow.md), [phase-194-apple-metal-production-weight-loading.md](phase-194-apple-metal-production-weight-loading.md), [phase-195-re-validate-the-apple-silicon-lane-runs-for-real-with-the-sk.md](phase-195-re-validate-the-apple-silicon-lane-runs-for-real-with-the-sk.md), [phase-196-re-validate-the-apple-silicon-lane-through-the-tart-vm-built.md](phase-196-re-validate-the-apple-silicon-lane-through-the-tart-vm-built.md), [phase-197-retired-vm-path-apple-silicon-workflow-attempt.md](phase-197-retired-vm-path-apple-silicon-workflow-attempt.md), [phase-198-live-fixed-bridge-apple-silicon-workflow-closure.md](phase-198-live-fixed-bridge-apple-silicon-workflow-closure.md), [phase-199-live-apple-host-resident-workload-closure.md](phase-199-live-apple-host-resident-workload-closure.md), [phase-200-apple-no-caveat-runtime-and-browser-lane.md](phase-200-apple-no-caveat-runtime-and-browser-lane.md), [phase-201-apple-silicon-all-model-trained-artifact-lane.md](phase-201-apple-silicon-all-model-trained-artifact-lane.md), [phase-202-apple-silicon-ha-cluster-revalidation.md](phase-202-apple-silicon-ha-cluster-revalidation.md), [phase-203-cross-substrate-cohort-runs-and-in-code-tolerance-bands.md](phase-203-cross-substrate-cohort-runs-and-in-code-tolerance-bands.md), [phase-204-live-jitml-test-all-report-card-with-measured-metrics.md](phase-204-live-jitml-test-all-report-card-with-measured-metrics.md), [phase-205-empty-legacy-ledger-and-final-handoff.md](phase-205-empty-legacy-ledger-and-final-handoff.md), [phase-206-remove-the-cross-substrate-parity-surface-reframe-the-determ.md](phase-206-remove-the-cross-substrate-parity-surface-reframe-the-determ.md), [phase-207-cross-substrate-real-workflow-confirmation.md](phase-207-cross-substrate-real-workflow-confirmation.md), [phase-208-real-workflow-ledger-walk-down-and-final-handoff.md](phase-208-real-workflow-ledger-walk-down-and-final-handoff.md), [phase-209-apple-placement-ledger-walk-down-and-final-handoff.md](phase-209-apple-placement-ledger-walk-down-and-final-handoff.md), [phase-210-expanded-no-caveat-report-card-and-ledger-handoff.md](phase-210-expanded-no-caveat-report-card-and-ledger-handoff.md), [phase-211-expanded-all-model-lane-fragment-handoff.md](phase-211-expanded-all-model-lane-fragment-handoff.md), [phase-212-ha-topology-aggregation.md](phase-212-ha-topology-aggregation.md), [phase-213-three-substrate-no-caveat-handoff.md](phase-213-three-substrate-no-caveat-handoff.md), [phase-214-re-aggregate-the-no-caveat-handoff-after-the-durable-state-d.md](phase-214-re-aggregate-the-no-caveat-handoff-after-the-durable-state-d.md), [phase-215-re-aggregate-the-no-caveat-handoff-after-the-real-sl-rl-chai.md](phase-215-re-aggregate-the-no-caveat-handoff-after-the-real-sl-rl-chai.md), [phase-216-re-aggregate-after-fixed-budget-all-model-closure.md](phase-216-re-aggregate-after-fixed-budget-all-model-closure.md), [phase-217-ha-topology-product-handoff.md](phase-217-ha-topology-product-handoff.md), [phase-218-re-aggregate-after-typed-failure-and-docs-governance-remedia.md](phase-218-re-aggregate-after-typed-failure-and-docs-governance-remedia.md), [phase-219-re-aggregate-after-real-cluster-tuning-runconfig-remediation.md](phase-219-re-aggregate-after-real-cluster-tuning-runconfig-remediation.md), [phase-220-product-matrix-authority.md](phase-220-product-matrix-authority.md), [phase-221-phase-status-registry.md](phase-221-phase-status-registry.md), [phase-222-status-truth-enforcement.md](phase-222-status-truth-enforcement.md), [phase-223-product-registry-plan-and-admitted-evidence-projection.md](phase-223-product-registry-plan-and-admitted-evidence-projection.md), [phase-224-remove-fossils.md](phase-224-remove-fossils.md), [phase-225-scaffold-lint-reachability.md](phase-225-scaffold-lint-reachability.md), [phase-226-non-fabricable-training-evidence.md](phase-226-non-fabricable-training-evidence.md), [phase-227-type-state-pipeline-haskell.md](phase-227-type-state-pipeline-haskell.md), [phase-228-dhall-boundary-fail-closed-decode.md](phase-228-dhall-boundary-fail-closed-decode.md), [phase-229-phase-specific-product-evidence-payloads.md](phase-229-phase-specific-product-evidence-payloads.md), [phase-230-matrix-parity.md](phase-230-matrix-parity.md), [phase-231-per-row-runnable-dhall.md](phase-231-per-row-runnable-dhall.md), [phase-232-read-time-dataset-sha.md](phase-232-read-time-dataset-sha.md), [phase-233-typed-layer-ir-reverse-mode-autodiff.md](phase-233-typed-layer-ir-reverse-mode-autodiff.md), [phase-234-onednn-layer-kernels-for-training.md](phase-234-onednn-layer-kernels-for-training.md), [phase-235-one-self-describing-checkpoint-envelope.md](phase-235-one-self-describing-checkpoint-envelope.md), [phase-236-checkpoint-admission-single-path.md](phase-236-checkpoint-admission-single-path.md), [phase-237-supervised-serving-on-the-layer-graph-ir.md](phase-237-supervised-serving-on-the-layer-graph-ir.md), [phase-238-supervised-training-on-the-layer-graph-ir.md](phase-238-supervised-training-on-the-layer-graph-ir.md), [phase-239-checkpoint-construction-from-the-trained-graph.md](phase-239-checkpoint-construction-from-the-trained-graph.md), [phase-240-layer-graph-checkpoints-inference.md](phase-240-layer-graph-checkpoints-inference.md), [phase-241-onednn-device-training-kernels-for-correct-operators.md](phase-241-onednn-device-training-kernels-for-correct-operators.md), [phase-242-literal-architectures-dense-mlp-lenet.md](phase-242-literal-architectures-dense-mlp-lenet.md), [phase-243-literal-architectures-resnet-family.md](phase-243-literal-architectures-resnet-family.md), [phase-244-literal-architectures-vision-transformer.md](phase-244-literal-architectures-vision-transformer.md), [phase-245-convergence-and-evidence.md](phase-245-convergence-and-evidence.md), [phase-246-completedtraining-sl-manifests.md](phase-246-completedtraining-sl-manifests.md), [phase-247-real-environments.md](phase-247-real-environments.md), [phase-248-distinct-algorithms.md](phase-248-distinct-algorithms.md), [phase-249-per-row-convergence-and-evidence.md](phase-249-per-row-convergence-and-evidence.md), [phase-250-typed-rl-cohort-and-action-domain-compatibility.md](phase-250-typed-rl-cohort-and-action-domain-compatibility.md), [phase-251-trainingplan-evaluationplan-compiler-and-trainer-migration.md](phase-251-trainingplan-evaluationplan-compiler-and-trainer-migration.md), [phase-252-typed-measured-counters-and-evidence-separation.md](phase-252-typed-measured-counters-and-evidence-separation.md), [phase-253-per-game-self-play.md](phase-253-per-game-self-play.md), [phase-254-arena-convergence-evidence.md](phase-254-arena-convergence-evidence.md), [phase-255-train-and-publish-artifact-selectors.md](phase-255-train-and-publish-artifact-selectors.md), [phase-256-row-specific-renderers.md](phase-256-row-specific-renderers.md), [phase-257-browser-fail-closed.md](phase-257-browser-fail-closed.md), [phase-258-row-keyed-integration-matrix.md](phase-258-row-keyed-integration-matrix.md), [phase-259-row-complete-playwright.md](phase-259-row-complete-playwright.md), [phase-260-linux-cpu-report-card.md](phase-260-linux-cpu-report-card.md), [phase-261-contract-driven-live-execution-integration-journal.md](phase-261-contract-driven-live-execution-integration-journal.md), [phase-262-contract-driven-live-execution-browser-and-playwright.md](phase-262-contract-driven-live-execution-browser-and-playwright.md), [phase-263-contract-driven-live-execution-fragment-issuance.md](phase-263-contract-driven-live-execution-fragment-issuance.md), [phase-264-real-cudnn-cublas-kernels.md](phase-264-real-cudnn-cublas-kernels.md), [phase-265-cuda-row-device-evidence.md](phase-265-cuda-row-device-evidence.md), [phase-266-cuda-integration-e2e-and-attestation.md](phase-266-cuda-integration-e2e-and-attestation.md), [phase-267-gpu-performance-and-persistent-device-buffers.md](phase-267-gpu-performance-and-persistent-device-buffers.md), [phase-268-contract-driven-cuda-lane-revalidation.md](phase-268-contract-driven-cuda-lane-revalidation.md), [phase-270-real-metal-kernels.md](phase-270-real-metal-kernels.md), [phase-271-metal-row-device-evidence.md](phase-271-metal-row-device-evidence.md), [phase-272-apple-integration-e2e-and-attestation.md](phase-272-apple-integration-e2e-and-attestation.md), [phase-273-contract-driven-apple-lane-revalidation.md](phase-273-contract-driven-apple-lane-revalidation.md), [phase-274-attestation-join.md](phase-274-attestation-join.md), [phase-275-no-caveat-closure-guard.md](phase-275-no-caveat-closure-guard.md), [phase-276-journal-derived-product-aggregation.md](phase-276-journal-derived-product-aggregation.md), [phase-277-negative-control-suite.md](phase-277-negative-control-suite.md), [phase-278-external-bars-no-self-referential-gate-lint-and-exact-served.md](phase-278-external-bars-no-self-referential-gate-lint-and-exact-served.md), [phase-279-measured-declared-type-split-behavioral-scaffold-lint.md](phase-279-measured-declared-type-split-behavioral-scaffold-lint.md), [phase-280-runcontract-negative-controls-request-and-event-fixtures.md](phase-280-runcontract-negative-controls-request-and-event-fixtures.md), [phase-281-runcontract-negative-controls-journal-fixtures-and-reducer-p.md](phase-281-runcontract-negative-controls-journal-fixtures-and-reducer-p.md), [phase-282-runcontract-negative-controls-lifecycle-and-per-row-registra.md](phase-282-runcontract-negative-controls-lifecycle-and-per-row-registra.md), [phase-283-per-model-measured-convergence.md](phase-283-per-model-measured-convergence.md), [phase-284-inference-performance-determinism.md](phase-284-inference-performance-determinism.md), [phase-285-contract-driven-per-model-evidence.md](phase-285-contract-driven-per-model-evidence.md), [phase-286-evidence-derived-closure-guard.md](phase-286-evidence-derived-closure-guard.md), [phase-287-standing-adversarial-audit-thin-plan.md](phase-287-standing-adversarial-audit-thin-plan.md), [phase-288-journal-derived-status-registry.md](phase-288-journal-derived-status-registry.md), [phase-289-evidence-typed-report-measurements.md](phase-289-evidence-typed-report-measurements.md)
**Generated sections**: none

> **Purpose**: Capture the target architecture, current baseline, doctrine scope,
> hard constraints, and dependency chain that every jitML phase depends on.

## Vision

jitML is a Haskell-native machine learning framework that treats *the entire training
process* as a declarative, reproducible program. Models, optimizers, datasets, RL
environments, checkpoints, hardware backends, loss functions, training schedules,
hyperparameter sweeps, and cluster topology are all described in `.dhall`. jitML
JIT-compiles hardware-specific kernels on demand, builds optimized native binaries,
and executes them through Haskell FFI bindings.

The jitML runtime closes on three properties simultaneously:

- **Reproducible by construction.** Given identical inputs, seeds, and configuration,
  two runs produce identical outputs — including parameter initialization, minibatch
  ordering, optimizer state, RL trajectories, MCTS exploration paths, hyperparameter-
  trial selection, and checkpoint recovery. Reproducibility is an architectural
  requirement, not a flag.
- **Declarative end-to-end.** A `.dhall` file is the full source of truth for a
  training run, a hyperparameter sweep, an RL experiment, or a cluster deployment.
  CLI flags layered on top *override* the Dhall; they never replace it.
- **Hardware-native without an embedded Python runtime.** jitML compiles kernels on
  demand for Apple Metal, NVIDIA CUDA, and oneDNN/AVX, and executes them through
  Haskell FFI bindings. The runtime has no Python interpreter in the loop.
- **Illegal workflow state excluded at the core boundary.** Raw external values
  refine once into a dimensionally checked plan; pure protocol reducers mint
  opaque completion evidence; one scoped interpreter owns effects, delivery
  settlement, lifecycle, diagnostics, and cleanup.

## Target Outcome

One `jitml` Haskell CLI binary, built by Cabal under GHC `9.12.4` and Cabal
`3.16.1.0`, drives three substrates (`apple-silicon`, `linux-cpu`, `linux-cuda`)
behind a uniform command surface. The bundled Kubernetes workload named
`jitml-demo` is a Webapp role instance of that same binary (`jitml service` with
`activeRole = Webapp`) and serves the PureScript frontend bundle. The CLI is
library-first per [project structure doctrine](../README.md#repository-layout-target):
`app/Main.hs` is a six-line shim into `App.main`; nearly all logic lives under
`src/JitML/`.

There is **one CLI verb for the daemon — `jitml service` — parameterised entirely by
its Dhall config**. The Dhall declares substrate, residency (`Cluster | Host`),
inference mode (`SelfInference | ForwardToHost`), and host-side MinIO/Pulsar
connection info when `residency = Host`. There is no separate `host-service` CLI
verb. On Linux substrates one daemon runs in-cluster (`Cluster + SelfInference`); on
Apple Silicon two daemons run, both the same binary distinguished by Dhall
(`Cluster + ForwardToHost` in-pod and `Host + SelfInference` host-native) because
Metal cannot be containerized.

## Status Authority

Current phase state, blockers, remaining work, and closure evidence live only in
[README.md → Closure Status](README.md#closure-status). This overview defines
scope and dependency ownership and does not maintain a second current-status
ledger.

Phase `273` is Done after its full Apple lifecycle and retained journal admission.
Phase `276` is Done after its CPU-only typed journal aggregation passed the
full **198 / 198** live integration gate and the other listed validation.
[Phase 276 → Closure Evidence](phase-276-journal-derived-product-aggregation.md#closure-evidence)
records the result. Phase `278` is the first open owner and retains CPU/Apple
qualification, complete journals, local/live-daemon/backend gates and quality.
Source `79bbe30b…` passes the supported native, canonical container and Linux
root builds, all test-stanza prebuilds, exact image/root CLI comparisons and
focused CPU regression/browser-plan gates and unfiltered CPU negative/backend
gates. Initial genuine CPU Ready, all twelve uploads, complete dataset
GET/bucket checks and original fixture readbacks before down pass. The normal
down attempt is interrupted and supplies no pass. Docker's exit-event rejection
is confirmed; its timestamp-order trigger remains unproved. Controllers and
original PV data are preserved; Ready recovery and original-data readback pass.
The strict preservation comparison remains Failed on two Docker resource
differences. A separate preparatory shutdown and full selected-snapshot readback
pass, leaving the cluster stopped before the upgrade. The Docker **29.6.1** upgrade
approved on **2026-10-24** is applied and verified. The shared restart interrupted
the unrelated validation, which returned container exit **143**; no foreign
preservation pass is claimed. Source `79bbe30b…` CPU recovery passes actual Ready,
pre-service restoration manifests and all original-data readbacks. A subsequent
supported down leaves the cluster stopped with data retained; no complete
normal-cycle pass follows. Bootstrap's permission-preservation repair is
implemented: the old producer fails the metadata counterexample, and the repaired
producer passes **5 / 5** Linux projection regressions plus **1 / 1** rollout
renderer case. Four-file HLint and test-module formatter checks pass;
native shared state was restored and verified before the supported native build
passed. The retained Source605 helper export identifies Source `576d3731…` with
**605 inputs** and confirms all **110** ordered CPU/Apple contract objects are
unchanged. Fresh scoped native controls pass **61 / 61**, the typed browser-plan
case passes **1 / 1**, and the full Metal backend lane passes **30 / 30**. The
post-gate native build state is preserved and verified. Four independently
assessed prospective criterion scopes are installed and production FILE-captured
as **60 files** with unchanged **15 / 6 / 15 / 16** artifact profiles. Prior
selections remain retained. The canonical successor build and independent image
adoption pass for `4c413561…`: all **605** source files, the selected **60-file**
set and whole installed/baked CLI match. The supported Linux root CLI build and
all **10** test-stanza prebuilds pass, with whole root/image CLI equality after
both builds. Independent review verifies the complete Linux transition and
preservation. Fresh CPU focused controls pass **61 / 61**, the typed browser-plan
case **1 / 1**, and unfiltered negative/backend gates **2,703 / 2,703** and
**43 / 43**; each returns `0` within its stated scope. At that earlier boundary, shared Cabal state is Linux;
native backup `2d4166f3…` remains preserved for restoration after terminal CPU work.
Supported Source `576d3731…` recovery completes with actual Ready, checked
pre-service restoration, all twelve original object and sentinel/message
readbacks, and the closing frame. Independent scoped recovery assessment passes;
the complete fresh normal cycle returns `0`, including public up, checked
restoration, original-data and fixture readbacks, and strict preservation with
all **11** checks true. Independent assessment accepts normal closure and A1's
public wrong-target refusal; A1's guardian `1`/result `false` from an immediate-exit
observer race remains literal. B's compensated STOPPING data/preservation and Ready recovery are accepted.
The material C-only case's strict patch witness, compensation, STOPPING data and
genuine Ready recovery, plus all three isolated snapshot component controls, are
independently accepted. Prior B observer nonpasses and the original C timing miss
remain literal. Current **02777** roots without xattrs show no observed loss.
The full unfiltered CPU daemon invocation returns `0`: **64 / 64** in
**7,326.983851 seconds**. The bounded reader verifies Source **605**, whole CLI
`4244706c…` and integrity of **70** proof emissions. Independent semantic review
`770e0c7e…` and the specific preservation/owned-cleanup assessment `b7381068…` are
accepted within their stated opaque-proof limits. The literal **671-byte** daemon
record `a9d95…` is adopted; the failed full-unit record remains unchanged.
Original full twelve-object and normal-fixture Ready readback and closing frames
pass. The original strict comparison **1**/whole-Docker `false` stays literal for
removed foreign `repertoire-v42-one-r2-quality` (`5c9a90c1…`). Its owner confirms
normal completion; no machine exit is reconstructed. The exact scoped assessment
accepts all remaining **25** containers, **10** volumes, images, Kind nodes and
other protected facts, plus the reviewed owned outputs; no blanket foreign waiver
or whole-inventory pass is claimed. Corrected Source576d Linux caller compilation
and all six preparation/preservation steps return `0`: **201,304,696 bytes**,
SHA `3d875f4f…`, independently checked. It has not been invoked or admitted a lane.
Old Source79 callers remain retained. Source605 CPU **55** acquisition
`cpu55-acquisition-576d-20261025` returns **1 / 44,129.779593167 s**. Observed Tasty
**60 / 60 failed** through one shared California resource-acquisition failure,
not sixty independent training failures. Its fresh child returns `2`: all five
original **10-epoch / 70,000-example** runs complete, then the strict held-out
best-constant predicate refuses qualification. All **44** later RL/arena/tuning
rows stay NotRun; no CPU candidate or whole qualifications directory is published. The
**373-entry** parent remains retained and its signing key is absent. Original-data/
fixture Ready readback, closing frame and local-after collection return `0`.
The new strict comparison **1** has only Docker false, with all **17** other checks
true: `repertoire:local` changes `95eb…→43d8…` and volume
`repertoire_check-evidence` is added; all containers, prior volumes and owned nodes
stay exact. Assessments `93b87032…`/`d6504211…` accept only jitML-protected state
and source-bound noninterference. Selected metadata joins the changes to Compose
project/service `repertoire`; actor, intent and mechanism remain unknown. Raw
comparison `1`/whole-Docker `false` stays literal, without a daemon5c9 or blanket
waiver. Source605 retains all five negative R², **0 / 5** joint successes and
served index0 failing. Endpoint review `1ac06931…` covers **10** frozen states,
**630** batches and **80,000** visits without identifying a concrete CPU
forward/backward/transform defect or a causal learning failure. Pre-approval Source605 interim
maintenance QA passes: six actual commands and scoped preservation pass
(`74222826…`), with no full-unit, qualification or phase-closure claim.

Approved `705610b2…`/`reg-ord1` is implemented. Linked public export returns `0`
for Source `9b90cf0f…`/**606 inputs**: exactly two California PlanId/report pairs
change across the CPU/Apple vectors and the other **108 / 110** objects stay exact.
Focused Linux groups **4 / 4**, **11 / 11**, **8 / 8**, six-file format/HLint and
supported root CLI build pass; retained engineering CLI is **234,010,400 bytes**,
`d35c826a…`. Helper compile/export pass with eight selected packages/GHC9.12.4.
Four fresh prospective review scopes are installed and production-FILE-captured:
**60 files / 8,641,074 bytes**, profiles **15 / 6 / 15 / 16**; old Source605's
**60** files remain retained. These reviews qualify no training; all four evidence
guards stay Pending and both lane journals remain absent.

Approved `reg-ord1` is bound to public Source `9b90cf0f…` / **606 inputs**,
current **60** prospective criterion files and image `7700205c…`. Image/adoption,
all **10** test-stanza prebuilds, whole CLI/libraries and coherent **183-unit**
Linux plan/configuration pass. Scoped CPU controls **61 / 61**, typed browser
**1 / 1**, unfiltered negatives **2,705 / 2,705** and backends **43 / 43** return
`0`. The inspected negative/backend and daemon records are adopted literally.
CPU-epoch guard `35e941eb…` retains its closed cutoff; subsequent native build
and Apple-record changes are recorded separately. Linux caller compilation returns `0` (`8553b5c6…`); it is uninvoked.

Source9b90 recovery UP, checked restoration and full original twelve-object/
fixture readback return `0`. Review `ca54c703…` accepts only that recovery and
specific protected-state/noninterference scope. Raw strict comparison **1**
retains the own demo alias/digest move and an unattributed Repertoire v66 container
departure; actor, mechanism and exit remain unknown. No whole-Docker or fresh
normal-cycle pass follows. Fresh owned normal down/snapshot/up, pre-service restoration and full twelve-
object/new-fixture readbacks return `0`. Independent `ed689e48…` accepts the
completed owned cycle and exact **361** protected inputs. The broad environment
comparison remains literal **1**; other-workspace activity is outside the jitML
task, as the user clarified, and does not block owned validation.

Owned A1/B/strict-C outcomes and all **3** isolated snapshot controls pass.
B refuses the read-only reservation; C returns **255** after one authenticated
interrupt, **16** completed zero patches and before a later positive owner.
All **18** controllers compensate with final rollouts passing; both STOPPING
full12/original-fixture readbacks and genuine Ready recoveries pass. Original
Kind/snapshot/source/native state holds. Raw observer failures and intermediate
timeouts remain literal; no model qualification or phase closure follows.

The retained Source `9b90cf0f…` unfiltered CPU daemon returns `0`: **64 / 64**
in **7,776.734683208 s**. Reader integrity covers **70** proof emissions.
Independent physical/semantic `3eaf6928…` and owned-preservation `ced8131c…`
reviews accept their exact scopes; original-data readback and all postchecks
return `0`. The literal **671-byte** record `1017dd6e…` is adopted; CPU-epoch
guard `35e941eb…`, opaque/replay limits and raw global observations stay literal.

Retained Source9b90/reg-ord1 CPU55 returns **1 / 39,791.007070292 s**.
Observed Tasty **60 / 60 failed** through one shared California acquisition
refusal: all five original **10-epoch / 70,000-example / 550-update** runs
fail the strict held-out best constant, joint **0 / 5**. Ten earlier row DATA
artifacts are retained without admission; the later **44** rows are unexecuted.
No CPU candidate, whole qualification or lane admission publishes. California
initial weights are retained, but initial scalar assessments are not; no own-initial
gain is claimed. All four before/four after steps return `0`; review `11c0fb87…`
accepts closed owned preservation. Source605 failures remain unchanged.

Retained Source9b90 native restoration precedes its supported native
build `0`: CLI **213,138,976 bytes / 6836d517…**. Real Metal backends pass
**30 / 30**; literal **705-byte** record `f2fc11d6…` is adopted through one path,
with the other four canonical records preserved. Native helper `f60b72e9…` and
caller `b0d9360e…` compile `0`; public **110**-contract export and four-scope
**60**-file capture are byte-equal to current Linux (`bf5e7547…`). The caller
remains uninvoked. Saved native14 stay protected; current Mac build products
are intentionally changed, without a post-build original2219 preservation claim.

The user approved **one fixed California 100-epoch trial** (authorization
`26e92ac4…`, recorded 2026-10-27 UTC): **700,000 examples / 5,500 updates per
original seed**. Only California's epoch allocation changes. Original data/split,
seeds **1011..1015**, model, learning rate, Adam, `reg-ord1`, report contract,
quality bars and exact index-0 serving remain fixed. Source605 and Source9b90
failures stay retained; the private mechanical pass establishes no efficacy.
The approved three-file change now has actual public Source `8af7549a…` /
**606 inputs**: **3** changed, **603** byte-identical to9b90. Supported native
build returns `0` in **781.793632 s**, CLI **213,139,152 bytes / 5e9d886f…**.
Native unit **86 / 86**, browser **1 / 1** and real Metal **30 / 30** pass;
helper `ace02882…` and caller `d6e840d3…` compile `0` without admission.
The actual **110**-contract export (**21,726 bytes / c73823ef…**) changes only
California's CPU/Apple PlanIds (**3bdc28ad… / 572c2090…**): **108** whole objects
and all report digests, including `13c8781d…`, remain unchanged (`7237a6f1…`).
The literal **705-byte / a40a6736…** Apple backend record is adopted through
one path, preserving the other four records (`20cd36c9…`). Four new-source
prospective criterion scopes are installed: **60 files / 8,018,122 bytes**,
profiles **15 / 6 / 15 / 16** (final manifest `4573954d…`). Root delegated the
principal review to Terminal `012f9fa2…`, distinct from the Root draft author
and Plan peer `9f9bd3f4…`; Root's own assessment is supplemental, not counted.
Production FILE capture returns `0` (**3,547 bytes / 56858a02…**). Append-only
retention `1b48fc80…` adds **12** Git exceptions and **60** literal Docker paths,
preserving old605/9b DATA and all five canonical records. Canonical image
attempt1 returns **1 / 5,558.483324875 s** after compile/link: `check-code` fails
only the stale registered `web/src/Generated/Contracts.purs` catalogue.
Supported native `docs generate` returns **0 / 0.189642083 s**, updating only
three California catalogue budgets **10→100** and their PlanIds; the private
preview keeps the other **37** registered outputs exact. The corrected file is
**118,945 bytes / 77da4453…**, outside Source606; Source8af, criteria60 and native8f
remain unchanged. The second canonical build returns **0 / 3,207.332503791 s**,
including `check-code` and frontend checks. Actual image `.Id` **931a54cb…** has
FILE adoption proof **0 / 21.28366 s** (`590744da…`), binding all **606** source
inputs, current **60** criterion files, five literal records and corrected catalogue.
Whole baked/installed Linux CLI bytes match: **234,074,528 / 504b29ae…**.
The owned proof container was never started and was removed; the post-proof
native/history check returns `0` at its retained cutoff. Build1 remains failed.
Serialized Linux staging, retention, architecture-only import, supported
configuration and Root CLI build return `0`. All **10** stanza **BUILDS** return
**0 / 1,513.114247084 s**; these builds execute no tests. Whole Root/image CLI **504b29ae…**
coherence passes after both Root build and all10 (`006067fb…` settlement).
Post-all10 native **2,223 + saved14** and old-five metadata preservation return
`0`; the native8f restoration backup remains exact at that boundary. Shared
cache/DB/config transition to Linux for CPU work; the native restoration below
follows terminal CPU cleanup.
Linux helper/caller direct compiles return `0` in isolated scopes with GHC
**9.12.4**, Source606 and **22** inputs exact before/after. Whole public110
export **c73823ef…** and FILE capture **56858a02…** match native bytes.
Initial read-only metadata nonpasses remain retained; private edge-whitespace/
store-ABI corrections change no Source606 or protocol. Real unfiltered negatives
pass **2,706 / 2,706**, CPU backends **43 / 43**; inspections and independent
review `473a39b8…` accept current Source8af / whole Root ELF CLI **504b29ae…**.
Post-gate native **2,223 + saved14** and old-five metadata replay returns `0`.
Exact two-record adoption after full-five CAS installs negative **673/7976ce8a…**
and CPU backend **685/83bc9a4f…**; the other three retain full metadata, including
the failed **307,306-byte** unit and historical Source9b daemon record.
The Linux-active V5 guard passes before and after genuine recovery, preserving
native **2,223 + saved14**, all **24,894** rows, current five/60/source606 and
both retained failed parents; Linux mutable domains remain observed. The first
before-frame `1` on omitted dataset paths remains retained, with no UP then;
the corrected fresh before-frame returns `0` on Source8af/image931a/CLI504b.
Supported recovery UP, restoration, original readback and closing frame all
return `0`: **115** steps, a new lease and owned CIDs `2d4403…` / `d3522…`,
restoring `p1-1639220521425949` / `439bb…`. Actual **8 Ready**, readyz `200`,
all **12 / 629,581,277 bytes** and hashes, original **140-byte** sentinel and
**138-byte** CK8C message survive, with backlog1/ACK0/WebSocket close1000.
Raw strict comparison remains **1**: all eight owned checks and global
container/volume checks are true; only the image flag is false because the
expected `jitml-demo:local` tag/digest moves `7700… → 931a…`. No image is added
or deleted and other image fields hold; the two new owned Kind nodes and their
two var volumes are authenticated. Independent review **a8f5ec7c… / 18,474
bytes** accepts genuine recovery and finite protection, retaining raw `1`;
there is no fresh Source8af normal/fault pass. The unfiltered Source8af daemon
returns **0 / 6,759.976 s** with actual **64 / 64** (**6,751.89 s** body);
inspector/reader return `0`, checking **70** emitted proofs for integrity.
All nine operation roles return `0`; all **19** scoped protected checks and
owned/global Docker equality are true. Full12+same CK8C/sentinel/backlog1/ACK0/
WebSocket close1000 survive. The pre-adoption V5 allfive check returns `0`, preserving
all **24,894** rows/native2,223+saved14/current60/source606 and old failures.
The frozen broader comparison still raises/external-preservation is **false**
on five shared Cabal cache metadata differences; build/PV-fixture changes are
observed separately, and the raw nonpass stays literal.
Root accepts independent semantic **69,480/12652cd0…** and finite-preservation
**28,076/d6ed…** reviews. Exact daemon-only literal adoption returns `0`;
canonical daemon is now Source8af **671/3b6e9670…**. The other four retain
full bytes/mode/uid/gid/mtime, including the failed **307,306/a453…** unit;
all five prewrite literals and prior `a84c…` five remain retained unchanged.
Fresh V5 POST_DAEMON_ADOPTION capture/check returns `0`, replacing the stale
pre-adoption boundary. A NEW six-copy observer obtains genuine Ready/full12/
original CK8C readback and frame, both `0`; its POST_DAEMON_OBSERVER_EXTENSION
capture/check returns `0` across **26,421** rows. Predecessor guard checker
`ad5a73b3…`, scope `1e3aa187…`, baseline `39f9972d…` and check `742e3c59…`
bind Source8af/current60/currentfive/native2,223+saved14/retained failures;
actual post-adoption frame `33e1d52f…` and Ready `604900fc…` are now closed.
CPU55 FILE preparation and all four before-operations return `0`. The single
approved Source8af California100 whole-CPU55 trial returns **1 / 49,071.541401708 s**,
completed **2026-10-28 02:06:40 UTC**. All **60** Tasty cases fail through the same
shared-acquisition exception. The authentic child records **PPO/mountain-car
`NativeServingLearningRefusal`**: the whole-five return median and served original
index-0 final metric each fall below the unchanged quality floor. Serial acquisition
reaches row **13**; the prior **12** calls returned without independently established
partial qualification, and the later **42** are unreached. No new complete CPU
candidate, qualification, journal or admission publishes. The one fresh attempt
`ce1a1fff2f24386f` is preserved; no retry, search or splicing follows.
All four original after-operations return `0`: `data-after`, `frame-after`,
`local-after` and `compare`. Independent review accepts owned preservation:
**25** protected/**8** owned-runtime checks, **1,527** immutables, Source8af's
**606** inputs, currentfive, native **2,223 + saved14**, history and all original
**12 / 629,581,277 bytes**. The original after-operations retain **8 Ready** and
original fixtures; the comparison's global Docker booleans are true. The frozen
`all_checks_passed` remains **false** solely for five Linux Cabal cache metadata
rows. The predecessor **26,421**-row
preservation guard returns `0` at **02:17:13 UTC** and again after DOWN at
**02:44:21 UTC** on **2026-10-28**.
Supported DOWN returns **0 / 552.294531583 s**, ending **2026-10-28 02:38:02 UTC**.
The subsequent frozen Root/Linux full four-PV snapshot readback returns
**0 / 10.521077 s**, selecting new generation `p1-1755076146212073`, epoch **0**,
selected FILE **1,903,513 bytes / 72595239…**; predecessor `439bb…` is historical.
Raw readback checks both whole archives/manifests, POSIX root metadata, the same
pre-DOWN **2** node CIDs and **4** PV roots. Actual Root Stopped/claim readback
returns **0 / 0.758 s**: all **8** components stopped, evidence null, no owned nodes,
lease claim absent and permanent flock FILE present. The actual new lease
`lease-1-1755076114397047` retains its **251**-line event stream.
Root and independent review accept the new full snapshot/Stopped scope
(**5,818/5ad771…**). New preservation capture/check return `0` across **27,370**
rows, **404** roots and **389** pins, protecting the full new generation, all **3**
failed attempts, Source606/currentfive/criteria and native **2,223 + saved14**.
Actual native restoration returns **0 / 4.069188083 s**: **2,237** native entries,
**14** saved, **15** retained Linux-shared and **98** development entries, with
local Cabal config **ABSENT**. Independent current-filesystem review
(**4,091/433142b1…**) accepts these restored/retained sets and both full native/Linux
CLI identities. The same **27,370**-row guard returns **0 / 27.462185375 s** after
restoration, at **2026-10-28 03:54:35 UTC**.
The historical Source605 compatibility correction, whole-backup and inventory
protection retain their accepted scopes. Failed full-unit evidence stays literal.
The retained Source8af PPO/mountain-car failure supplies no CPU qualification/
admission or fresh Apple55 pass. On **2026-10-28**, the user approves one product-only
PPO/mountain-car **150→300-iteration** trial (**2,457,600 transitions/seed**;
**12,288,000** across original seeds **42..46**, served index **0**) and further
convergence investigation if it still fails. The one trial has now failed in shared
CIFAR/ViT setup; current state is **FAILED_CPU55_RUNTIME_STOPPED**:
Retained Source **f1381784… / 606** (**3** changed/**603** same8af) retains only
two test-file corrections from CFA; production ProductBudget **5d33151e…**, approved
PPO300, California100 and all other recipes/bars stay fixed. Format/HLint, supported
native build, **86 / 10 / 1 / 30** gate commands, Apple **705 / 81492319…**
Sourcef138 **Passed / 30** adoption and native helper/caller compilation return `0`.
The expected7-count wrapper nonpass, first CFA **85 / 86** fixture failure/Main warning/
later **NotRun**, Source8af scientific failure and failed full-unit record stay literal.
Actual public110 review confirms **108** unchanged whole objects and all **110**
report digests unchanged; only two PPO/mountain-car PlanIds change. The separate
**11** canonical C2 policy/reference source FILE pins are independently confirmed exact.
Two distinct reviewers approve the [four Sourcef138 prospective criterion scopes](attestations/phase278-20261015-mac-validation/criterion-reviews/f1381784c66bb54164c9f5f5dc7f3c908fabb8dccd5065a8ce16732a9bfbb968/);
final assembly, materialization, production capture and append-only retention return `0`.
The actual closure is **60 files / 8,189,443 bytes**, profiles **15 / 6 / 15 / 16**:
**52** artifacts, **4** receipts and **4** selectors. Exactly **12** Git exceptions and
**60** literal Docker paths append; old prefixes/closures hold and `git check-ignore`
returns **1** with empty streams. Generation comparisons and criterion status-doc pins retain their recorded cutoffs.
The observed Sourcef138 native backup is **2,237 entries = 2,223 + saved14**,
accepted by Root and independent filesystem review. Canonical native generation
returns `0` once: `Contracts.purs` **118,945 / 8703e1a2…**, exactly three PPO
metadata rows, **37** other whole files/metadata unchanged and all38 preview-equal.
Canonical V2 Docker build returns `0` (**2,578.934067375 s**), including
`check-code: ok` and the frontend build. Compose plugin verification passes;
actual image inspection returns `0`, selecting **773e5c10…**. The first V1
build's Phase-State-token failure stays literal. Bounded image FILE proof returns `0`
(**35f622…**), independently accepted **f2e0eb6b…**. Stopped staging and old-Linux
retention return `0` (**10.019608875 / 16.402652375 s**); independent **02a6…** accepts
**2,590 entries / 3,920,052,786 bytes** and the original **504b…** CLI. V4 history
check returns `0` (**57.257367416 s**), preserving original27370 and the exact old-CLI map.
All **7** supported import/configuration/build/coherence operations return `0`; all
**10** ELF test executables **build** in **1,431.422127916 s**. Two whole Root/image
CLI checks return `0`, binding actual Root CLI **234,007,416 / fd86f0ea…**.
**No test was executed by the Linux build preparation.** Current Linux helper/caller
compilation returns `0`; public110 export and selected60 capture match the whole native
outputs. Independent **87af25f2…** accepts this source606/package/metadata provenance.
The caller remains uninvoked and its inherited **532-byte** warning stays literal.
Finite **PRE_RECOVERY** Scope and the **34,906-row** first-frame mapping are independently
accepted **c6418248…**; actual first capture and reference check return `0`.
Current CPU negatives **2,706 / 2,706** and backends **43 / 43** return `0`
(**945.477048958 / 12.561796792 s**). Corrected v3 candidate inspections return `0`,
joining the original receipts/source606/whole fd86 CLI. Exact two-record literal
adoption returns `0`, independently accepted **0448bd4d…**; the other three records
and every prior-five literal remain exact, including the **Failed** full-unit.
The accepted current Scope first capture/reference check return `0`: **34,944** rows
with all **34,908** expected full-row assertions exact; peer **0a5e622f… / 062d5446…**
accepts this boundary. Recovery FILE finalization, seven-file allocation and read-only
host export/capture parity return `0`. The before-frame passes (**139.199399291 s**,
**de0bc586…**); independent packet/allocation review **217c1539…** is accepted.
Genuine recovery is independently accepted **21d6c392…**. Supported UP returns `0`
(**1,415.455668083 s**), restoring selected `p1-1755076146212073` / epoch `0` /
`72595239…` with new owned nodes and lease. Actual **8 Ready** / readyz `200`, all
**12 HTTP 200 / 629,581,277 bytes** and the exact whole bucket pass. Original sentinel
**140 bytes**, CK8C **138 bytes**, backlog **1**, unacked/ACK **0**, one pull permit
and sent/peer close `1000` remain exact. Closing raw comparison retains `1` solely
for the supported owned `jitml-demo:local`/RepoDigest move **931a→773e**; no image
IDs were added/deleted. All **8** owned checks and unrelated container/volume checks
pass. The current guard returns `0` over the same **34,944** rows; no rebaseline.
Fresh current-five retention, observer DATA allocation and daemon FILE finalization
return `0`. The unfiltered daemon target passes **64 / 64** (**7,704.399605708 s**;
Tasty body **7,692.72 s**); all nine original roles and all four after-operations return
`0`. Safe-reader **70** proof-integrity checks, corrected v3 candidate inspection and
same-Scope guard replay return `0`. Comparison records **19** protected checks true and
`jitml_owned_preservation_exact` true; broad raw external `false` and its failed marker
stay literal. Independent semantic **28a4ff85…** and owned-preservation **d6780229…**
reviews are accepted. One-path daemon adoption returns `0`, independently accepted
**b8563107…**: current daemon **951526ba…** is the only delta; the other four and all
retained prior-five literals remain exact, including **Failed** full-unit. The actual
`POST_DAEMON_ADOPTION` first capture/reference check return `0`: Scope **73f4f17d…** /
baseline **04eae09d…**, **36,192** rows, all **34,944** predecessor rows mapped exactly
and the new daemon literal verified. The fresh post-adoption observer and monotonic
`POST_DAEMON_OBSERVER_EXTENSION` capture/check return `0`, independently accepted
**d647…**: current Scope **20c7…** / checker **72a7…** / baseline **253c…**,
**36,500** rows. The criterion append's **423** old rows plus **71** authenticated
additions are physically accepted. Six fresh CPU55 observer DATA copies are prepared
at `0`; input packet **62aba…** has accepted independent binding review **3a068…**
(**47** keys / **1,364** pins / **676** roots), and strict **1,438-FILE** preflight returns
`0`. All **336** original history roots / **13,040** recorded rows now have accepted
closure; the original v7 raw `1` and two-fixture addendum `0` stay literal. Final FILE
preparation returns `0`, with distinct history **aa0ee…** / packet **386daf54…** reviews
accepted. All four before-operations return `0`. The single wholeCPU55 returns
**1 / 57,832.582448375 s**, finishing **2026-10-30 09:24:33 UTC**. All **60 / 60**
assertions fail from one shared **cifar10-vit** workflow timeout. Sequential execution
stops at supervised row **9 / 11**, before PPO300; no PPO convergence result follows.
No complete-matrix journal, qualification or admission is established. The original
coordinator is absent and all four closing labels/receipts are absent; no post-trial
preservation, normal DOWN, new four-PV snapshot or native restoration pass is claimed.
At the user's resource-stop request, Colima is stopped. Following a host kernel panic
and reboot, its automatic startup job is disabled/unloaded and the VM is stopped again.
The panic's initiating cause remains unresolved. The [local resource/restart analysis](../.build/phase278-resource-incident-20261030-a/analysis.json)
records the incident's memory recovery, uncapped training and causal limits.
The explicitly managed `jitml` VM is now prepared and **Stopped**: **4 CPUs / 16 GiB**,
no automatic startup/context activation or Kubernetes. The bounded Compose override
verifies **2 CPUs / 6 GiB / zero swap** for a job using actual cgroup readback.
The [VM setup and continuation record](../.build/phase278-managed-vm-20261031-a/summary.json)
confirms Sourcef138 is unchanged across all **606** inputs. Retain accepted builds,
caches, datasets and engineering evidence; do not regenerate merely for a VM change.
The old default profile stays offline for verified data/image recovery. Current cluster
ceilings do not fit this VM and must not be started unchanged. No qualifying aggregate
rerun occurred; the existing fresh-only issuer cannot resume the partial eight-row prefix.
A later bounded host continuity check stops at its **120 CPU-second** limit
(**136.38 s** wall, **936 MiB** maximum sampled RSS), with no preservation result.
No original closing role is replaced. The [recovery preparation record](../.build/phase278-recovery-preparation-20261031-a/summary.json)
retains that nonpass and the limited empty-VM Docker flag inspection; the old runtime
has not been started or migrated.
A separate [streamed FILE check](../.build/phase278-recovery-preparation-20261031-a/final-continuation.json)
passes all **1,971** selected pins / **1,605,723,512 bytes** in **12.41 s**, using
**28.1 MiB** peak RAM. The later [full FILE-continuity check](../.build/phase278-runtime-recovery-20261031-a/current-status-02-frame-pass.json)
passes baseline **36,500** and native **2,223 + saved14** role membership before/after,
**34,620 unique files / 26,762,668,482 bytes**, in **320.59 s / 97.8 MiB** peak RAM.
It safely reuses **9,506** prior hashes and hashes the remaining **25,114** once.
Original closing roles/runtime/PV health remain unverified. Bounded recovery uses an
independent APFS data clone; the original default stays offline. The first cloned
daemon attempt stops at a conservative summary-counter guard; its failure stays literal.
The [bounded recovery and profiling record](../.build/phase278-runtime-recovery-20261031-a/final-summary.json)
now verifies image **773e** and all **13** layers in the new VM, without a rebuild.
Actual **51** stopped-container/PID and empty-task proofs precede the official image export.
A one-update diagnostic returns `0` at **2.13 GiB** peak; a **16-update** first-epoch
prefix returns `0` in **25.30 s / 2.03 GiB**, with no OOM/limit events. Process memory
plateaus near **1.74 GiB**; warm 128-example updates have **0.964 s** median.
These are bounded diagnostics, not full-cohort/qualification or historical-timeout proof.
All VMs stop after the diagnostics. The f138 resource audit finds component CPU/memory
fields unused by production renderers and selected explicit pod limits already
**14,976 MiB**, before uncapped roles. The current unfrozen source candidate wires
explicit profile selection, runtime/client preflight, eight Helm overlays, namespace
defaults and observed node hard-cap/allocatable checks. Candidate **903c3aba… / 613**
passes the library/CLI/unit build with warnings as errors and **63** focused Linux
resource tests. A real **1 CPU / 4 GiB / zero-swap** caller passes; the old
**2 CPU / 6 GiB** allowance refuses that profile. Eight pinned Helm charts render
offline. Follow-on candidate **1d8c7301… / 615** passes its warnings-as-errors build
and **102** focused Linux resource tests. An isolated live probe verifies corrected
**1,250m / 4 GiB Allocatable** and actual admission defaults, then is deleted. The
current source adds final all-namespace admitted-Pod accounting and retained-node
reservation reconciliation. At that cutoff latest-state cold PV preservation and
normal restored application proof remain open. Follow-on candidate **d7be4ef0… / 615** applies and
observes fresh-node caps before restoration, and gives serial snapshot helpers
fixed CPU/memory/no-swap/process/tmpfs limits with actual Docker inspection before
start. Its warnings-as-errors library/CLI/unit build and **108** focused resource
tests pass. Helper overlap within the full-stack allowance still needs validation;
source-bound
engineering/criterion/qualification evidence requires corresponding refresh.
Latest candidate **e6bf71ac… / 615** adds an explicit cold-stopped adapter and
reserves the **0.5 CPU / 512 MiB** serial helper inside the existing client slot.
The lifecycle override gives the caller **0.5 CPU / 3 GiB**, and lifecycle image
discovery no longer triggers an implicit build. Its warnings-as-errors build,
**111** resource checks and **12** selected cold tests pass. A disposable actual
Docker/virtiofs bridge verifies nested read-only behavior, capped helpers and Mac
host-FD bytes; all51 retained containers stay stopped and temporary mounts are
removed. The isolated host maintenance executable builds against retained native
dependencies without restoring shared native state. The subsequent actual cold
capture commits selected generation **cold-pv-20261031-c**, containing
**6,983,567,360 bytes**, with fresh source-before/after, new scratch extraction,
final revalidation and ordinary store commit (**0 / 427.52 s**). An interrupted
staged generation supplies verified archive bytes through a private native COW
clone; its failed CPU guard remains literal. Only the two stopped source container
records in the recovery copy are removed; their volumes and the offline original
remain retained. Cleanup stops both recovery daemons and every VM and restores
the exact no-mount recovery configuration. Subsequent fresh canonical nodes pass
creation and actual **1.5 CPU / 5 GiB / no-swap** caps; both pass pre-restore Ready checks with
**1,250m / 4 GiB Allocatable**. Normal filesystem restoration of selected C
passes **0 / 90.64 s**, including all-node fresh-root preflight, archive checks,
restored-tree comparison and normal pending/completion/reuse checks. The managed
VM stops afterwards. Application readback and full-stack/scientific validation
remain open. The
[local capture checkpoint](../.build/phase278-cold-recovery-20261031-a/latest-cold-capture-summary.json)
records capture scopes, and the
[fresh-restore checkpoint](../.build/phase278-cold-recovery-20261031-a/fresh-restore-summary.json)
records restoration scopes. Neither replaces any original closing proof.
Current image preparation pins the verified Ubuntu base **24737cef…** after
observed floating-tag drift. Official pre-COPY cache export passes **0 / 36.70 s**;
all **7** toolchain RUNs are cached on export and in the smaller VM's current
canonical image build. Recovery daemons/VM stop and the original guest resolver
is restored exactly after a transient DNS binding. The managed VM runs only the
image build with the cluster stopped. The full canonical build subsequently
passes **0 / 2,320.90 s**, including source/check-code/frontend/plugin, selecting
image **b968a134…**. Independent image observation verifies exact
Source **e6bf71ac… / 615** and installed/baked CLI equality
(**236,456,816 bytes / 0e9fe0ef…**). Actual in-container **0:0** metadata,
help, public tools and socket checks pass; host controls remain **501:20**.
The earlier **501:1000** inference from SSH metadata is not used for container
operations, and no protected ownership changes. The helper-only compile passes
with warnings as errors (**0 / 8.52 s**); mapped bootstrap preflight passes
(**0 / 2.19 s**). The same restored nodes start. Initial bounded bootstrap reuse
is stopped to correct a monitoring helper's remote-process timeout;
its prepared replacement uses Service-proxy HTTP GETs without remote processes.
Retained metadata separately identifies repeated OOMs in Pulsar's **512 MiB**
`wait-zookeeper-ready` init container after restart without that observer;
the sampled worker peak remains below **2 GiB**. The startup correction still
needs live deployment validation before training. Disk-only growth to
**256 GiB** preserves **4 CPUs / 16 GiB RAM**, the same nodes/volumes and completed
restore marker. Application readback remains unexecuted. The dedicated generic
Colima autostart files are removed with preserved copies; startup stays disabled.
Retained Source **da2c5f03… / 616** carries serial Java topic observations with shared
remote admission and finite process lifetimes. A bounded pinned-image probe
passes caller-death/lock/retirement checks and separate KILL escalation, peaking
at **73,691,136 bytes** without OOM or cleanup kills. Corrected image
**01006871…** completes its canonical build/check-code/frontend/plugin in
**2,313.26 s**, reusing all seven toolchain RUNs. Fresh verification matches all
**616** source rows and whole installed/plan CLI bytes. Live rollout and
application readback remain pending. The bounded rollout exits **1 / 1,238.89 s**
at Pulsar's **900-second** readiness deadline. A read-only live mount inspection
finds the ZooKeeper Pod on the host-backed data view, while original restored
metadata remains in the separate node-local backing tree. Startup projection and
actual Pod-root admission are under repair; same-CID cold restart and original
application readback must validate that repair before training. All VMs stop after
inspection. This is not evidence of original data loss or a qualification pass. The partial
compiler cache is retained. Prior Source **5694acee…** builds its library/CLI
in **103.21 s**, recompiling **10 / 458** modules at **2.77 GiB** peak without OOM;
its test compiler refuses a type-default warning. Current source fixes that
warning and a missing direct test dependency. Current-source focused validation
passes **0 / 50.53 s**, with **31 / 31** resource and **6 / 6** signal checks,
exact component dependencies, **2.69 GiB** peak and zero OOM events. Independent
real-chart comparison proves only the intended startup memory variable changes.
The unchanged large unit entry point and Phase280's failed full-unit bar remain.
Qualifying runtime and original closing operations stay unexecuted; container docs QA is deferred.
Phase278 remains **Active**. Root's
truncated-SHA inspector invocation retains auxiliary `1`; full fd86 CLI is unchanged,
and no test retry occurred. The original v2 APFS auxiliary nonpass stays literal.
Recovery is no new normal, fault, scientific or qualification pass.
Nativef138 **2,223 + saved14** remains the restoration target; shared cache/DB/config
has deliberately transitioned to Linux. Source606/current60/policies/Purs stay unchanged;
current five add the accepted daemon replacement after the two control replacements. Local literal-preflight
ordering and unsuffixed-store metadata probes
each retain `1` as preparation nonpasses. WholeCPU55 is **Failed** from the shared
CIFAR/ViT timeout; PPO300 was not reached by this matrix. No complete-matrix
qualification/admission or Phase278 closure is claimed; four evidence guards and
final quality remain open. Runtime stays stopped at the user's request. Seen-benchmark adaptivity, unproven cause and lack of a
success guarantee remain explicit.
Fresh complete CPU55 precedes genuine Apple
context/datasets/55 if CPU qualifies; replay/Store/lane admission, four guards
and final quality stay open. Seen-held-out adaptivity/no guarantee applies;
a failed trial authorizes no automatic next search, score retry or row splicing.
Foreign Docker changes remain informational, without owner questions or actor
inference. Phase `278` stays Active; the user handles NVIDIA after278, with no279 execution.
Seen-held-out adaptivity/no guarantee and all other fixed budgets, seeds, split,
model, optimizer and bars remain binding. Freeze before training, retain every failure,
and perform no adaptive search, row reuse or splicing. Replay/Store/admission, genuine
Apple context/datasets, typed lane admission, all four evidence guards and
final quality remain open. Phase `278` stays Active; the
user takes the NVIDIA handoff after it finishes. Exact validation scopes are recorded in
[Closure Status](README.md#closure-status).
Phase `279` owns the real CUDA lane and its behavioral detector. Phase `280`
consumes those three earlier lanes on CPU and owns the aggregate plus unchanged
full CPU unit/integration gates. Every phase validates before the next begins;
no later aggregate or accelerator blocks an earlier retained surface.
### Historical Checkpoint Notes

The 2026-10-22 continuation starts from a checkout without the prior local build
or acquisition state. Supported native and container builds are being recreated;
the earlier Running acquisition is historical. Phase `278` remains Active and
later phases retain their dependency blockers. Current progress and validation
are recorded in [Closure Status](README.md#closure-status).

The following checkpoints retain their original source scopes. Current state
and open work remain owned by [Closure Status](README.md#closure-status) and
[Phase 278 current validation](phase-278-external-bars-no-self-referential-gate-lint-and-exact-served.md#current-partial-validation).

The 514-input producer checkpoint adds warning-free private compilation, focused
controls and a genuine fixed-five ARS/cartpole acquisition diagnostic with ten
matching replays and physical readback. Authentication, stored replay and
publication remain open. Historical395 native/backend/quality evidence retains
that source scope; final integrated-producer validation remains required.
The 514-input checkpoint and earlier private 577/586 failures remain retained,
including 69d98b 925/926, cd5f's two 926-case passes followed by legacy 1 failure,
6dcab6c8's compiler errors and the earlier status **253** pre-body harness failure.
Validated checkpoint `59872c11…` / **586** accepts its complete four-stage private validation:
warning-free build/HLint, both **926** scopes, legacy **1**, registry **13**,
status **253** and docs. The reviewed **110**-contract export, governed retention
and **163-file** controlled adoption include **32** installed fixed review DATA
files. Supported native `cc5fa74c…`, fresh helper rebind/synchronization and
supported CPU CLI `4699e46f…` now bind this source. Four standalone helper
compiles pass, as do the actual CPU **42 / 42** and Apple **29 / 29** backend lanes.
The unfiltered CPU negative gate fails **3 / 2,683**; three isolated fixture
corrections and their actual later-source rerun are recorded below. Earlier
failed generations retain their original outcomes.
Real CPU/Apple bootstrap, datasets, five-run qualification, eleventh Store-loaded
replay, complete journals/registration and remaining daemon/quality gates stay
open. [Closure Status](README.md#closure-status) and [Phase 278](phase-278-external-bars-no-self-referential-gate-lint-and-exact-served.md#current-partial-validation)
own the exact scope; later numerical owners do not advance.

The retained validated code epoch is `53ab7f12…` / **586** after the three test-only fixture repairs; all
other **583** inputs remain byte-identical to the validated checkpoint. `53ab`-bound review DATA is
retained. The supported native build, explicit generated-doc no-op, fresh CPU synchronization and
incremental build pass. All **3** focused repaired cases, unfiltered CPU negatives **2,683 /
2,683**, CPU backends **42 / 42** and real Metal backends **29 / 29** pass on this source ([current
runtime evidence](attestations/phase278-20261015-mac-validation/runtime-receipts/source53ab-native-owned-gates-validation/README.md)). The original source59872 failures remain failed historical
evidence. Genuine qualification, complete journals/registration, owned daemon and remaining
docs/quality gates stay open. The later canonical image attempt **FAILED** with controlled exit **130** at the **4 GiB** availability floor before application COPY; endpoint guards pass, while a current image, bootstrap and qualification remain open ([image and engineering checkpoint](attestations/phase278-20261015-mac-validation/runtime-receipts/source53ab-image-engineering-validation/README.md)). The later cold-storage operation preserves the original paths through read-only HOST mirrors and retires one pilot holding plus all **27** frozen duplicate holdings; batch VM available bytes rise from **21,060,104,192** to **98,611,441,664** (**77,551,337,472**), with three real global full guards and fresh per-root recovery proofs ([cold-storage evidence](attestations/phase278-20261015-mac-validation/runtime-receipts/source53ab-cold-storage-validation/README.md)). This supplies no new image, bootstrap, training or qualification result.

Historical Source `4f593f2b…` / **586** passes unfiltered CPU negatives **2,683 / 2,683**, the complete CPU backend lane **42 / 42**, and real Metal backends **29 / 29**. Current bootstrap remains failed after a containerd metadata panic. Both node-local PV trees have verified archives and full Linux scratch restores, while nodes remain intact and platform writers are quiesced. Phase `278` owns the newly exposed state-preserving lifecycle repair from the historical Phase `28`/`43` surfaces before final-source qualification. Fresh CPU/Apple **55-row** qualification, authenticated journals/registration, current-worker admission, the unfiltered CPU daemon proof and final standing/quality gates remain open.
`53ab7f12…` and **578** remain byte-identical. The changes format constructor
patterns and review-fixture layouts, route unit diagnostics through the CLI output boundary, and move the
fixed criterion-review root to the Phase `278` attestation home with strict
source/lane/scope checks. The supported native build exits **0** (`Up to date`), with all **19** native pins unchanged; full canonical Fourmolu and HLint checks pass ([native/style evidence](attestations/phase278-20261015-mac-validation/runtime-receipts/source6ca-native-style-validation/README.md)). The canonical `53ab` image retry **FAILED** with ordinary
exit **1** in `jitml check-code`: **15** rendered findings represent **9** distinct
metadata, taxonomy, terminal-output and formatting failures. The frontend and
image do not complete. Its original four-service guard also fails because a
historical stopped Portal test container is absent; the three surviving running
services and protected bytes are unchanged, and the removal cause is unobserved.
The [failed image and intermediate static repairs](attestations/phase278-20261015-mac-validation/runtime-receipts/source53ab-image-failure-repair-validation/README.md)
remain distinct from passing runtime evidence. Those retained repairs bind
`be58a591…`; the current formatting and style checks have separate receipts. The metadata successor preserves
the original cold-storage evidence bytes. Historical review DATA relocation preserves all **64** original files / **1,448,988** bytes locally at the [historical home](attestations/phase278-20261015-mac-validation/criterion-review-history/quality-repair-20261017/README.md); only its summary remains versioned, and `documents/validation` is absent. The actual **110**-contract export matches both prior complete **55**-row sets; four independently selected current-source reviews now bind **32** installed DATA files, and one public four-scope FILE capture exits **0** with exact expected identities ([criterion DATA evidence](attestations/phase278-20261015-mac-validation/runtime-receipts/source6ca-criterion-data-validation/README.md)). Apple full55 helper compilation exits **0**, without acquisition. Current CPU rebind/synchronization/build and three helper compilations are accepted. Unfiltered CPU negatives **2,683 / 2,683**, CPU backends **42 / 42** and real Metal backends **29 / 29** pass on Source `6ca12a83…`. That batch stops at Docs **1** on **24** stale empty private directories; HOST has no `documents/validation` category. A separate continuation removes exactly those **24** empty directories and no files, then passes docs, `check-code` and three plan scans with empty finding arrays and Closure Status at **60** lines. The original Docs failure and failed observer preflight remain retained. The Dockerfile repair persists CUDA configuration and recopies the final CLI ([owned-gates evidence](attestations/phase278-20261015-mac-validation/runtime-receipts/source6ca-cpu-owned-gates-validation/README.md)). The subsequent canonical universal image build exits **0** on Source `6ca12a83…` / Gov**58**, including `check-code`; **611** frontend modules compile with **0** errors and two retained generated-code warnings. Immutable-image checks bind the installed/default/CUDA CLI bytes, full source and current/historical DATA; image-owned docs and diagnostic plan scans exit **0** ([canonical image evidence](attestations/phase278-20261015-mac-validation/runtime-receipts/source6ca-canonical-image-validation/README.md)). A retained image-owned CPU client selection and one real streamed image-save measurement exit **0**. Four parser fixtures preserve expected exits **0 / 1 / 1 / 1**; the real stream’s **50** retained command captures all exit **0**. The full stream measures **11,231,578,112** bytes and establishes a `b2e7…` config distinct from image-target/manifest `dbb4…`, without retaining a full archive ([image-save/capacity observations](attestations/phase278-20261015-mac-validation/runtime-receipts/source6ca-image-save-capacity-observations/README.md)). The first storage preflight fails **1** before size walks; fresh read-only inventory exits **0**. The logical comparison `T + 2P + 2U + 4 GiB` is **87,642,323,062** bytes versus observed VM availability **79,029,026,816** bytes; it is not a physical minimum/peak, sufficient bound, recovery estimate or capacity approval. Node-base/platform/runtime growth remains unsized; observed Kind nodes are **0**, with the node base and **18** platform tags absent. Later Gov**60** metadata is outside baked image58 docs. Its actual client projection completed, but Docs exits **1** on four wrapper headers; scans and `check-code` are NotRun in that failed receipt. The earlier ordering-assertion failure remains failed. A metadata-only header correction retains all four original README bytes, four original manifests and both runtime entries through explicit inverse maps. A separate Gov**61** client followup copies exactly **26** metadata files and passes docs, three diagnostic plan scans and `check-code`; all **18** retained command captures exit **0**, with Source `6ca12a83…` and protected domains preserved. This pass belongs to the writable client; the immutable image remains baked Gov**58**. An independently accepted **16**-root cold-storage batch finishes at exit **0** with **2** new verified mirrors, **14** reuses, and actual per-root HOST-only recovery before controlled retirement. The original pre-mirror attempt remains failed; both narrow controller corrections and all raw failures are retained. Separate post-cold capacity and publication facts are accepted. The independently reviewed monitored canonical CPU bootstrap command exits **0** after **97** rollout steps. Separate accepted Source `6ca12a83…` observations establish the CPU context, and the image-owned test-component build, current CLI/package rebind and three helper certifications pass. All **12** canonical dataset uploads and exact live SHA readback pass. The first ARS launch fails on its absent output parent. A corrected fresh launch retains all five original seeds **42..46** and **47** phase objects, but fails completed-checkpoint publication: the admitted canonical wire orders the same metrics differently from the prepared typed manifest, and the strict Store-mirror readback refuses it. Neither failure becomes a passing qualification. The separately reviewed three-file correction was applied as historical Source `31285ae2…` / **586**, with **3** changed inputs and **583** byte-identical. Preparation retains the canonical typed manifest decoded from its exact prepared wire, with pure and filesystem-Store regressions added. This source-application/archive scope alone establishes no compiler, test, style, image or runtime pass. [Source-transition evidence](attestations/phase278-20261015-mac-validation/runtime-receipts/source31285-checkpoint-transition-validation/README.md) retains this finite source-transition scope and the literal failed attempts. A separate Source `31285ae2…` native build exits **0** and generated-doc production returns the expected **3** no-change result. The first fresh helper link fails **1** on ENOSPC, with nine finally launches failing before child start; a later independent preservation diagnostic and fresh native helper compile/export pass. Both complete **55**-row contract sets remain exact. Four newly reviewed criterion scopes bind **42** installed DATA files, and one public four-scope FILE capture exits **0** with exact expected identities ([native and criterion evidence](attestations/phase278-20261015-mac-validation/runtime-receipts/source31285-criterion-validation/README.md)). A later targeted Source `31285ae2…` style preflight retains Fourmolu **100**, with HLint **0** and protected domains unchanged. Two separately captured formatter-only changes are applied as current Source `4f593f2b…` / **586**, with **584** other inputs unchanged and no criterion-provider change. The final three-file Fourmolu/HLint checks pass; a separate current native build exits **0** and generated-doc production returns its defined **3** no-change result. A fresh **110**-contract export exactly matches both prior complete **55**-row sets, and four new independent current-source criterion reviews are selected. Separate materialization and create-only installation each retain **19** actual zero command captures and install **42** exact new DATA files; one direct public four-scope FILE capture exits **0** with **3,664** stdout bytes and exact expected identities ([current-source criterion checkpoint](attestations/phase278-20261015-mac-validation/runtime-receipts/source4f593-criterion-validation/README.md)). A fresh post-cleanup Source `4f593f2b…` / **586** identity preflight passes on HOST and the current CPU client, including CLI `df1173ac…`, selected review DATA, package files and three helpers. Current-worker rollout, current-source standing/live validation, fresh full **55-row** CPU and Apple qualification, authenticated journals/registration and the unfiltered CPU generic/daemon proof remain open.

The 2026-07-15 retained-cluster audit reopened Sprints `2.9` and `3.7`; both
have re-closed. Sprint `2.9` restored the typed Kind existence branch, retained
edge coordinate, and fail-closed recovery publication. Sprint `3.7` accepted
the retained-cluster live reconcile, including exact release/readiness evidence,
all 34 source-derived Pulsar topics proven by per-topic stats, exact image
identity proving the host OCI descriptor against every Kind-node containerd
target, uniform node/tag CRI config digests, and matching application Pod
`imageID`s, a versioned stamp written only after live publication, and exit
code `3` for an exact retained no-op. Sprint `12.16` then re-closed on immutable
descriptor
`sha256:6e0d57971bf8e6a7c996530a4b434a575237a570c745710f2a150a501da42aa0`
after its six-command canonical `linux-cpu` block, docs, code-quality, and
resource-verification gates passed. The 2026-07-18 checkpoint/runtime audit then
found that the supervised publisher's apparently eligible artifacts were
generic V1 snapshots with no executable supervised runtime payload. Its frozen
immutable-image diagnostic remains historical evidence: **54** rows were
eligible, **0** unsupported, and **1** errored, but those results do not prove
strict persisted-artifact reload. At that historical audit boundary, the
frozen V1 encoding was 134 bytes with SHA-256
`30db4da59975960c71c1e694472eca7d6b577acc2127e6381ef15e4b4949bb4b`.

Phases `266`, `267`, and `78` reopened on 2026-08-16 under rule `C`. Phase `78`
re-closed `Done` on 2026-08-19: every substrate's compiled artifact bytes are now
a function of its cache-key inputs, proven per lane by a double-compile gate.
Phase `265` re-closed `Done` on 2026-08-18 at `rows: 55`, `eligible: 55`,
`errors: 0`, retiring the `eligible: 50` / `errors: 5` shortfall that reopened
`266` and `267`. Phases `266`–`273` reached `Done`; the 2026-09-08
evidence-retention audit then reopened Phase `261` as the first executable
owner because the authenticated lane journals consumed by Phase `276` were not
committed. Its portable issuer and digest-pinned reader are implemented and
await container validation plus the fresh live `linux-cpu` gate. At that
checkpoint Phases `268`, `273`, and `276` were Blocked in numerical order;
Phases `261` and `268` have since closed. The historical Apple
validation chronology leading to this state follows. Phase `271` closed on
2026-08-28 with a corrected
Apple producer reporting 55 / 55 eligible and admitted rows, Apple backend
**25 / 25**, e2e **30 / 30**, a clean `jitml:local` image build, docs/check-code,
and the six-case phase-status guard.
Phase `272` has since passed its complete ten-stanza Apple lane (`10` passed,
`0` failed, `0` not-run) but remains Active because that run predates the shared
Pulsar batch-transport fix. Its final-source explicit live Apple e2e gate has
now exited `0`: integration passed **197 / 197**, Playwright passed **77 / 77**,
and Haskell e2e passed **30 / 30**. The complete ten-stanza Apple lane on that
final source was interrupted at the user's stop request after `jitml-unit`
passed and `jitml-integration` reached the ProductScenario `mnist-lenet` row. It
produced no terminal status and is not closing evidence; a fresh full-lane rerun
remains required. Work has resumed: formatter remediation and container
`jitml check-code` passed, the clean-host Apple bootstrap is green after **111**
live rollout steps, and the real Metal daemon reached readiness. The fresh full-
lane rerun passed `jitml-unit`, then exited `1` after `jitml-integration` failed
**73 / 197** cases because the rebuilt cluster's live canonical-dataset
inventory was empty and MinIO could not supply the required workflow input. The
later eight stanzas did not run. That runtime was stopped at the checkpoint.
Restoring and verifying the exact twelve objects preceded the next attempt: the
current-source bootstrap passed, all twelve objects passed the focused live
inventory gate, and the four-consumer Metal daemon reached readiness. The fresh
complete lane passed `jitml-unit`, completed the first five ProductScenario
rows, and reached `cifar10-resnet20` before the user's stop request. It was
intentionally interrupted without a terminal status; the lane, daemon, and Kind
cluster were stopped, and the attempt is not closing evidence. The latest
continuation rebuilt immutable image
`sha256:550cab9db6cc1f835e1b938b9a57a3ffa7d32f44d822c2d62fdbb2441b6bf5e3`,
passed all **111** bootstrap steps, restaged and focused-live-verified all twelve
objects, and restored the ready Metal daemon. Its fresh complete lane passed
`jitml-unit`, completed eight ProductScenario rows, and reached `cifar10-vit`
before the user's stop request. It was intentionally interrupted without a
terminal status; the lane, daemon, and Kind cluster were stopped, and the
attempt is not closing evidence. A fresh full-lane rerun remains open.
Attestation refresh, standalone gates, docs, code quality, and the phase-status
guard remain after it passes. The final continuation used immutable image
`sha256:55975f2ec4db8eaf9dacee5b125ea1ed4dfb028c88a44b78a1ee232a1189ea6f`:
all **111** bootstrap steps passed, all twelve exact datasets passed the focused
live gate, and the four-consumer real-Metal daemon reached readiness. Its fresh
complete lane passed `jitml-unit`, completed eight ProductScenario rows through
`cifar100-wide-resnet`, and reached `cifar10-vit` before the user's stop
request. The intentional interrupt produced terminal status `2`; it is not
closing evidence. The lane and daemon are stopped, the Kind cluster is deleted,
and a fresh full-lane rerun remains open. The latest continuation used immutable
image
`sha256:2365ac55ef5fc8accee708acba8243d95d6d8248b6a52a11d92ce19ec51f66d7`:
bootstrap passed all **111** steps, doctor passed, all seven components reported
ready, edge readiness passed, all twelve exact datasets passed the focused live gate **1 / 1** in
5.74 seconds, and the four-consumer real-Metal daemon reached readiness. The
fresh complete lane passed `jitml-unit`, completed eight ProductScenario rows
through `cifar100-wide-resnet`, and reached `cifar10-vit`. The user's stop
request intentionally interrupted it there with terminal status `2`; it is not
closing evidence. The lane and daemon are stopped, the Kind cluster is deleted,
and the complete ten-stanza rerun remains open.
The final continuation ran on immutable image
`sha256:d4094b5ac0a70b2aa7bf3748e987e48516b237394521cbf7c0effdbfd550f27e`:
the clean host build compiled **305 / 305** modules, the image build completed
in 45m26s, bootstrap passed all **111** steps, all twelve exact datasets passed
the focused live gate **1 / 1** in 5.72 seconds, and the four-consumer
real-Metal daemon reached readiness. The fresh complete lane passed
`jitml-unit`; `jitml-integration` completed the first eight ProductScenario rows
through `cifar100-wide-resnet`, then advanced to `cifar10-vit`. The user's stop
request intentionally interrupted it there with terminal status `2`; it is not
closing evidence. The lane and daemon are stopped, the Kind cluster is deleted,
and the complete ten-stanza rerun remains open.
A subsequent continuation rebuilt immutable image
`sha256:e06058d13cdc208ab3f2625fad23319c8cc1b43dd203a5a76b97ad7da204c91e`
in 45m18s, completed all **111** rollout steps, passed doctor, all seven
component statuses, edge readiness, and the exact twelve-object focused live
gate **1 / 1** in 5.70 seconds, and restored the ready four-consumer Metal
daemon. The fresh complete lane passed `jitml-unit`; `jitml-integration`
completed all ten supervised ProductScenario rows, including the 1h49m
`cifar10-vit` and 1h12m `tiny-imagenet-resnet50` rows, plus `PPO/cartpole`,
`PPO/mountain-car`, and `PPO/acrobot`, then advanced to `PPO/lunar-lander`.
The user's stop request intentionally interrupted the lane before that row
returned; the wrapper recorded terminal status `2`, so neither the partial
integration stanza nor the invocation is closing evidence. The lane and daemon
are stopped, the Kind cluster is deleted, and a fresh complete-lane rerun
remains required. At the user's subsequent direction, work resumed from the
preserved Apple host build tree as the `resume7` lifecycle. It ran from the same
final source and exited `0`: all **55 / 55** ProductScenario rows returned, the
authenticated journal re-minted the exact committed fragment, and all ten
stanzas passed with `0` failed and `0` not-run in 116,396.918861 seconds. The
standalone Apple backend gate passed **25 / 25** and non-live e2e passed **30 /
30**. The final container documentation and code-quality gates passed, the
focused phase-status registry passed **6 / 6**, and the aggregation no-rerun
scan inspected **20 / 20** mapped CPU-only validation blocks with **0**
accelerator invocations. Phase `272` closed Done on 2026-09-07. Phase `273`
subsequently closed Done on 2026-09-08 after its **10 / 10** stanza Apple
lifecycle, authenticated **55 / 55** row journal, exact fragment comparator,
and successful teardown. Its typed lane journal was not committed, so the
current numerical chain starts at reopened Phase `261`.

The next chronology paragraph is a superseded 2026-09-08 pre-audit snapshot;
the current correction follows it.

At that pre-audit checkpoint, the strict forward chain was `276 → 278 → 280 → 281 → 282 → 285 → 288 → 289`. Phases `42`, `53`, `69`, and `262` are Done. The 2026-08-12 execution-architecture reopen returned Phases `229`, `233`, `241`, `263`, `264`, `265`, `270`, and `271` to Active and moved Phase `268` to Blocked; Phases `7`, `72`, `77`, `78`, `79`, `80`, and `84` also reopened outside the registry range. Phases `229`, `7`, and `72` all re-closed `Done` on 2026-08-13 and Phases `77`, `78`, `79`, `80`, `84`, and `233` re-closed `Done` on 2026-08-14. Phase `229` **reopened `Active` on 2026-08-14** under rule `C`: its closure evidence never included a completed `jitml-sl-canonicals` run, and that lane fails on two obligations its own sprint owns — an MLP-path witness that resolves a symbol the MLP artifact never exported, and a serialised `TrainingEvidence` field added without a migration. Phase `229` re-closed `Done` on 2026-08-15 against `jitml test jitml-sl-canonicals --linux-cpu` **36 / 36**, and Phase `241` closed `Done` the same day, and Phase `78` re-closed `Done` on 2026-08-19. Phase `276` was then the first executable owner and was Planned. Intervening phases retain `Done` on their non-topology surfaces. Phase `235`
(One Self-Describing Checkpoint Envelope) closed `Done` on 2026-07-27 (jitml-unit
771/771, check-code ok, docs check ok), and Phase `236` (Checkpoint Admission
Single-Path — one classify-on-payload-variant admission path, dormant
`LayerGraph`-from-checkpoint reconstruction deleted) closed `Done` on 2026-07-27.
Phases `237` (supervised serving on the IR) and `238` (supervised training on
the IR) closed `Done` on 2026-07-28; Phase `239` (checkpoint construction from the
trained graph) closed `Done` on 2026-07-28; Phases `240`–`246` (the coupled
literal-architecture landing) closed `Done` on 2026-07-30; Phase `250` (Typed RL Cohort) closed `Done` on 2026-07-30; Phases `251` (TrainingPlan/EvaluationPlan Compiler and Trainer Migration) and `252` (Typed Measured Counters and Evidence Separation) closed `Done` on 2026-07-31. Phase `252` passed RL canonicals **47 / 47**, unit **757 / 757**, model convergence **111 / 111**, integration-target build/link, docs check, and check-code. Phase `261` closed `Done` on 2026-08-01 against immutable image `jitml:local@sha256:051ddff67e55e0d480a4ab7324cb0d5893330186451db35ef7ae81e207ddd72a`: integration passed **161 / 161**, including the Phase `261` subtree **60 / 60**; unit passed **772 / 772**; the parent authenticated the ordered version-`3` **55-row** aggregate and exactly Store-re-admitted every row; all **9** live components were Ready and the exact **12** dataset objects were present; and docs check plus check-code passed. Phase `262` (contract-driven live execution: browser and Playwright) closed `Done` on 2026-08-11 against immutable image `jitml:local@sha256:e36d6ca11f4cc75c231ac8ba2e7f238b1e1ce68623b550b55c94be075ad599e7`: the live `jitml-e2e` gate exited `0` with integration **196 / 196**, Playwright **77 / 77**, and the Haskell `jitml-e2e` suite **30 / 30**, alongside unit **828 / 828**, negative controls **3 / 3**, model convergence **111 / 111**, daemon lifecycle **54 / 54**, docs check, and check-code. Phase `263` (contract-driven live execution: fragment issuance) closed `Done` on 2026-08-12: `jitml test all --live --linux-cpu` passed **11 / 11 invocations, 0 failed, 0 NotRun** in 43,940.53s, including `jitml-integration` **197 / 197** with the standing case that re-mints the committed lane fragment from the persisted scenario journal and fails closed on drift. Phase `263` reopened the same day under rule `C`: its `DeviceEvidence` column is composed from the declared substrate and declared claim, so the standing drift gate compared a declaration against itself. Its 2026-08-12 run remains valid evidence for row identity, plan identity, and cross-process journal re-mint. Phase `229` re-closed `Done` on 2026-08-13 once device evidence was minted only from a `DeviceExecutionWitness`, then reopened `Active` on 2026-08-14 under rule `C` — its closure evidence never included a completed `jitml-sl-canonicals` run, the lane where its MLP-path witness and its unmigrated `TrainingEvidence` field both fail. Phase `229` re-closed `Done` on 2026-08-15 with that lane passing **36 / 36**, and Phase `241` closed `Done` the same day once the operator lowering became total over `LayerOp` and `jitml_op_train` returned an executed-opcode status. Phases `266`–`271` subsequently closed `Done`, with Phase `271` closing on 2026-08-28. At that checkpoint, the Phase `19`–`34` table recorded **60 Done / 1 Active / 0 Planned / 9 Blocked**, with Active Phase `273` the first executable owner and the apple-silicon hard stop on non-Apple hosts. Phase `10` validated its reopened work on `linux-cpu` only.
That registry sentence records the historical audit checkpoint described in
the chronology. The current registry is **62 Done / 1 Active / 0 Planned / 7
Blocked**. Phase `261` re-closed after its exact 55-row portable CPU journal was
retained and admitted, and Phase `268` / Sprint `29.5` closed on 2026-09-12
after its real RTX 5090 lifecycle retained and admitted the equivalent CUDA
journal. Phase `273` / Sprint `30.4` re-closed on 2026-09-17 after its
real Apple lifecycle retained and admitted the durable typed journal.
Phase `276` closed the CPU-only aggregation; Phase `278` is the first open owner.

The binding architecture is
[Typed Run Contract](../documents/engineering/run_contract.md): raw DTOs refine
to a validated plan, pure total reducers collect exact evidence, an opaque
receipt accompanies each broker delivery, one scoped interpreter joins terminal
workload state with complete evidence, and reports project actual execution
journals. At its historical 2026-07-19 boundary, completed Sprint `10.6`
restored an exact executable supervised V2 runtime artifact with one physical
JMW1 weight blob and a finite-positive, descriptor/`PlanId`-bound learning rate
passed unchanged to the selected classification or California regression
trainer. That V2 name records the pre-Phase-`235` checkpoint design; it is not
a current parallel envelope. The canonical rates are
`3e-3` for `fashion-mnist-resnet`, `1.1e-3` for `cifar10-resnet20`, `1.5e-3`
for `cifar10-vit`, and `1e-3` for the other eight rows. The current ViT plan
fixes **2,000** training examples, forty epochs, batch size 128, **80,000**
processed examples, and **640** successful optimizer updates. In the current
single-envelope design, generic supervised execution's supervised-graph body
has a composite origin comprising its canonical row identity and exact
canonical `SupervisedPlan` transport, while Product publication retains the
authoritative `ProductRow` origin. Admission re-refines the origin and
binds the exact executed seed, canonical dataset-at-read digest, runtime bytes,
exact completion metric rows, and exact TensorBoard run, prefix, and tags;
Product completion additionally binds its canonical four-row metric vector. A
writer reads the current ETag, requires its pointer CAS to return
`PointerWritten` for the exact manifest, and publishes completion only after
that result. An absent optional legacy weight projection does not gate a generic
below-bar successful miss; a supplied projection remains subject to exact
equality checks.

Sprint `10.6` closed on immutable descriptor
`sha256:0147b37fafd53c01669705a5723ce91482d0fd545da4b9da523df8dacc3e9ba8`.
At that historical boundary, its **156-step** live reconcile, **11 / 11**
exact-V2 publications, focused
latest-pointer proof **1 / 1**, unit **711 / 711**, SL **36 / 36**, integration
**155 / 155**, negative controls **3 / 3**, model convergence **111 / 111**,
docs, code-quality, whitespace, and Rule-M gates all passed. The Sprint `10.12`
implementation at its closure read pointer body `P1`, verified the exact
addressed then-V2 manifest outer/body, required exact pointer-body equality at
`P2`, and only then fetched and independently bound every referenced blob. The
current single-envelope path retains that ordering: it verifies the exact
addressed envelope and selected body, and known-address admission performs the
same manifest/blob verification without pointer reads before Store returns its
opaque `AdmittedCompletedCheckpoint` after completion revalidation. ETags
remain write-CAS tokens and are not snapshot identity. Sprint `10.12`
is Done after unit **719 / 719**, SL **36 / 36**, RL **40 / 40**,
hyperparameter **26 / 26**, docs, code-quality, whitespace, and Rule-M gates
passed. Sprint `19.4` subsequently closed the total
single-row projection and total batch projection through opaque
`projectProductRows`, whose ordered identities define the ProductRow denominator
and execution order. Each projected cell binds the exact internal
publisher/executor command, kind-indexed plan, substrate, and `PlanId`; report
admission then requires the opaque completed exact-plan join rather than a raw
handle or registry declaration.

`jitml bootstrap --apple-silicon|--linux-cpu|--linux-cuda` is the canonical
full-stack rollout entrypoint. It writes generated Dhall and runtime metadata
under `./.build/`, materializes the per-substrate Kind config from
`./kind/cluster-<substrate>.yaml`, brings up Kind, writes/exports Kind's
kubeconfig through an in-container temporary file, copies it to
`./.build/jitml.kubeconfig` (the user's `~/.kube/config` is never touched), brings
MinIO and the registered `harbor-pg` database up first, then brings Harbor up
against those dependencies, builds `jitml:local`, retags it as
`jitml-demo:local`, loads those tags explicitly into Kind, and rolls out the
remaining services using the
umbrella chart at `chart/`. The single exposed listener is one
`127.0.0.1:<edge-port>` socket on the Envoy Gateway; every HTTPRoute in the
cluster is rendered from the typed registry in `src/JitML/Routes.hs`.
The lower-level `jitml cluster up` command performs the retained-cluster live
reconcile: it proves exact Helm release state, role/public-edge readiness, all
34 source-derived Pulsar topics through individual `topics stats` probes, and
that the host OCI descriptor matches every Kind-node containerd target, each
node/tag has one uniform CRI config digest, and every application Pod `imageID`
matches that config before publishing the live cluster state. Only after that
publication succeeds does it write the versioned reconcile stamp; a subsequent
retained invocation whose fingerprint and live evidence match exactly performs
no mutation and exits `3`.

The numerical core (layer catalog, real+complex activations, optimizers,
schedulers, losses, spectral ops) ships as a Haskell catalog with a Dhall
mirror, consumed by per-substrate JIT source renderers in the Haskell binary.
Linux renderers generate compiler input source on demand under
`./.build/jit-src/<substrate>/<hash>/` and write compiled shared objects into
the content-addressed cache. The Apple target renders MSL plus launch metadata
and persists `./.build/jit/apple-silicon/<hash>.metal.json`; a fixed host Metal
bridge compiles that source with `MTLDevice.makeLibrary(source:options:)` and
dispatches on the host GPU. The Linux CPU libdnnl-linked oneDNN primitive paths
compile, load, execute, and report their exported `jitml_kernel_family_name` and
`jitml_kernel_output_count` through the Haskell FFI today; their local toolchain
fingerprint includes `artifact-abi=<os>-<arch>` and `reduction-block=256` so
host/container artifacts and fixed reduction-block changes do not collide in the
shared cache. `JitML.Engines.OneDnnRuntime` probes `pkg-config` package metadata,
readable oneDNN headers, and dynamic-linker `libdnnl` visibility through typed
subprocesses for the production Linux CPU path. CUDA and Apple Metal execution
are validated through the Phase `15` / Phase `16` live closure paths; Phase `17`
consumes their within-substrate report evidence for final handoff.

The SL/RL surfaces ship today as catalogs and partial measured summaries:
canonical SL cells, a substrate-trainable cohort, RL algorithm rows, registered
environment helpers, AlphaZero helpers, command-envelope parsers, and
hyperparameter trial sequences. These are not enough for current product
closure. Phases `21`–`28` must prove trained-artifact type-state inference
eligibility, canonical row parity and read-time dataset verification, a general
differentiable layer engine, literal SL architecture implementation, real RL
env/algorithm dispatch, real AlphaZero self-play, all-row demo rendering, and
per-row integration/e2e coverage before accelerator lanes can revalidate the
matrix.
Phase `8`
Sprint `8.8` retired the deterministic `atari-subset` stand-in and added the
runtime-loaded Haskell ALE boundary plus explicit ROM policy. The later static
foreign-source correction removed the checked-in C++ shim; any future ALE
adapter must be Haskell-generated into the build/cache tree or supplied outside
the repository. Phase `8` reopened and re-closed for Sprint `8.9`, which adds
the repo-owned `KeyDoorGrid-v0` environment so default RL demos and required
canonical examples need no copyrighted ROM material. Phase `9` reopened and
re-closed for Sprint `9.8`, which retargets the RL algorithm/convergence matrix.
The checked-in `experiments/mnist-tune.dhall` file carries the
`Some Tuning::{ ... }` fixture using a TPE sampler; the current Haskell catalog
in `src/JitML/Tune/Catalog.hs` includes the full target sampler set (`Grid`,
`Sobol`, `Random`, `TPE`, `GPBO`, `GeneticAlgorithm`, `NSGA2`, `MuLambdaES`,
`CMAES`, `EvolutionStrategies`, and `PBT`), and `jitml tune` decodes that
fixture into the local tuning ADT before rendering its deterministic plan.
`JitML.Proto.Tune` now covers the current tune command and event oneofs with
proto3-compatible byte round-trips; generated proto-lens Haskell bindings live
under `gen/Proto/Jitml/` and are exposed by the cabal library.

The retained checkpoint surface provides one self-describing
`RawCheckpointEnvelope`, a typed `RawCheckpointBody` payload choice between
weight-only and supervised-graph bodies, object-key renderers, the binary
`.jmw1` encoder/decoder, a filesystem-backed store, and MinIO
conditional-write/CAS operations. One decoder verifies the exact final outer
bytes and exact canonical body without version fall-through. Phase `235`
retired the frozen V1 and parallel V2/V3 checkpoint wires; current checkpoints
are regenerated deterministically from source rather than admitted through a
compatibility cascade. Every supervised-graph body contains exactly one
physical `supervised.weights` JMW1 blob and the executable graph,
graph-ordered virtual parameter slices, preprocessing transforms, output
decoder, row and `PlanId`, dataset provenance, and exact initial/final weight
identities actually used by training. California Housing splits raw examples
before fitting feature and target statistics from the training partition only.
The frozen pre-graph `cifar10-vit` V2 executable records patch size/stride `4/4`
over `32×32×3` and token-mixing count `64`; this is exact persistence of that
historical Mixer program, not evidence for the later single typed served graph
or literal small-ViT architecture. Those obligations subsequently closed with
the graph/checkpoint/literal-architecture chain through Phase `246`.

Admission reads stable pointer body `P1`, verifies the exact addressed manifest
outer/body, and requires exact `P1 == P2`; it does not require equal ETags.
Store then requires the exact commit, validates the sorted canonical-original →
exact-scoped → payload-SHA descriptor, reconstructs the logical manifest,
re-derives the snapshot id, and binds each scoped payload object before final
completion refinement. Known-address admission skips only the pointer reads. A
zero-payload-object manifest is admitted only by the exact commit at the id
derived from its logical manifest plus `[]`. Candidate and completed
writers/results are distinct, completed persistence requires
`CompletedTraining` directly, immutable create conflicts adopt only exact byte
identity, local `CheckpointWriteError` keeps object/pointer conflicts distinct,
and Product Pipeline consumes Store's opaque `AdmittedCompletedCheckpoint`.
Writer/GC exclusion uses the canonical versioned `ExperimentGcFence` at
`gc/coordination-fence.txt`, binding the experiment, monotonic CAS revision, a
separate monotonic writer/root-activity epoch, full active reservations, and
contiguous per-event `GcFenceDecision` histories. Every reservation register or
unregister increments that epoch; GC brackets its complete fresh root view with
matching epoch observations, and `Open`/`Cancelled` becomes `Planned` only at
that exact epoch. GC-only sibling revisions do not invalidate the witness. Live
GC converges the complete view in a bounded loop: epoch churn restarts it, while
an epoch-stable plan that discovers an absent exact durable intent persists it
and restarts the entire view. Late ready publication or published-transient
cleanup also counts as work and restarts the complete view. Only the converged
plan supplies `kept` and no-op, and exact initial/fresh intent creation counts
as work.
Writer registration atomically moves overlapping planned events to helpable
`Cancelling`, persists the stable immutable cancellation artifact, and completes
`Cancelled` before mutation without deleting the semantic intent. The artifacts
may span generations; the latest exact fence phase determines logical activity,
and delayed helpers repeat only byte-identical PUTs. Registration rejects
executing/reaped overlap before the separate marker; GC executes only from exact freshly re-read executing state
with no overlap, and permanent reaped state prevents stale reuse. Prior
generations must be complete cancelled and only the latest may be nonterminal
or destructive. Experiment scope retains cross-snapshot parent-manifest
protection; a local lock or repeated scan is not the proof.
Authorization never retires the cancellation artifact, and semantic-intent
cleanup occurs only after `Reaped` during ready/published terminal handling.
Store's sole destructive execution API is `executeAuthorizedGcIntents`; no
plan/raw-intent compatibility execution export remains. An absent target is
recoverable only under the latest byte-identical `Executing`/`Reaped` fence
decision. Generic Workload mutations first reject noncanonical bucket/key
references and then reject Store-owned `manifests/`, `pointers/`, `snapshots/`,
and `gc/` prefixes before `HasMinIO`. Each GC event names exactly one snapshot and
one `committed.cbor` plus its payload-object keys, so a zero-payload-object reap
reports `reaped-objects=1`. ETags are used only for write CAS. Sprint
`10.6`, `10.12`, and `19.4` are Done on `linux-cpu`; Phases `252` and `261` are
Done; Phases `42`, `53`, `69`, and `262` are Done. The
live HTTP MinIO capability path remains implemented by
`JitML.Service.MinIOSubprocess` and exercises write-once conflicts, pointer CAS,
read, list, and delete. The frontend surface provides a
minimal PureScript entrypoint, generated endpoint and current-panel payload
contracts from `src/JitML/Web/Contracts.hs`, typed bundle/panel/demo-route
metadata from `src/JitML/Web/Bundle.hs`, and the `jitml-demo` Webapp workload
served by `src/JitML/Web/Server.hs`; the typed demo route manifest covers the full
current local API route family including `/api/runs/{runId}/command`. Sprint
`11.9` removes current marker/default parser residue from the panels and adds
typed controls/charts for the existing browser workflows plus generated REST
request envelopes, checkpoint-backed MNIST/CIFAR/Connect 4 route injection,
generic tensor inference, and checkpoint comparison, plus the RL environment
animation, training throughput-telemetry, and rules-complete adversarial
annotations; Sprint `11.9` closed `✅ Done` on 2026-06-16 on that owned code
surface. The live all-substrate REST proof, command-state reconciliation,
expanded replay/game surfaces, and no-caveat Playwright product matrix are
closed by Sprint `14.1` / `14.2` and the Phase `15` / `16` live lanes (rule E).

`jitml test all --dry-run` renders the aggregate test plan and non-dry-run
`jitml test all` invokes every test-only Cabal test-suite stanza (`jitml-unit`,
`jitml-integration`, `jitml-sl-canonicals`, `jitml-rl-canonicals`,
`jitml-hyperparameter`, `jitml-backends`, `jitml-daemon-lifecycle`,
`jitml-e2e`) through the typed `Subprocess` boundary before printing the
report-card summary. Style and code-quality gates run separately through
`jitml lint *` and `jitml check-code`. The
report-card knobs are pinned in `cabal.project`. `jitml test all --live`
adds the live measured report-card fields; the 2026-06-04 fresh Apple
live validation passed the full aggregate and captured populated RL,
AlphaZero, tune, JIT-cache, and daemon-health measurements.
Sprint `12.11` adds `JitML.Test.WorkflowMatrix` as the single real-workflow
matrix for SL/RL/tune/inference/AlphaZero coverage. Sprint `12.15` expands that
workflow matrix into per-model cells and negative infer-before-complete checks.
Its workflow cells remain the public-CLI `Subprocess` / `ProcessOutcome` matrix;
ProductRow model cells are a separate internal exact-executor matrix derived
from the opaque `projectProductRows` batch and invoke
`jitml internal train-and-publish-product-rows --<substrate> --row <rowId>`.
Neither matrix enumeration nor a successful projection can by itself mint a
completed ProductRow report cell.
The live trained-artifact matrix is part of the HA `linux-cpu` aggregation
baseline and the Phase `15` `linux-cuda` lane (`linux-cpu`: `jitml test all
--live --linux-cpu` 8/8 and report-card `browser_product_matrix` 8/8;
`linux-cuda`: `jitml test all --linux-cuda` 8/8 and Playwright 15/15); see
[phase-12-test-stanzas-and-cross-cluster.md](README.md#legacy-to-new-phase-map).

Haskell style and code-quality execution is container-exclusive. The
`jitml:local` image is required on every substrate, including Apple Silicon for
the in-cluster daemon, so the Dockerfile owns the separate toolchain plus
pinned `fourmolu` / `hlint` binaries and runs the Haskell style/code-quality
gate during image construction. Runtime lint/check-code commands run inside that
image or fail before linting; they never install, discover, or override host
style tools.

## Execution Roadmap

The dependency-ordered execution roadmap lives in
[README.md → Execution Roadmap](README.md#execution-roadmap). Each item there
links to the owning sprint's `### Remaining Work` block, where the validation
gate lives. The roadmap closes when every Planned, Active, or Blocked phase moves to Done
and the deletion ledger has no pending rows.

## Architecture Overview

- **Haskell CLI surface.** One binary `jitml`; the `jitml-demo` workload is the
  Webapp role selected by typed Dhall. The parser is generated from a separate `CommandSpec` registry — never the
  source of truth. The same registry feeds the parser, the command tree (`jitml
  commands --tree`), the JSON command schema (`jitml commands --json`), the markdown
  command reference, the manpages, and the shell completion scripts. Sprint
  `19.4` added the exact ProductRow publisher/executor
  `jitml internal train-and-publish-product-rows --<substrate> [--row <rowId>]`.
  Owned by [phase-1-haskell-cli-surface.md](README.md#legacy-to-new-phase-map).
- **Typed run contract.** Raw workflow requests refine into kind-indexed plans;
  protocol events feed pure exact-evidence reducers; receipt-bound deliveries,
  lifecycle observation, diagnostics, and cleanup belong to one interpreter;
  append-only journals drive tests and reports. The canonical engineering shape
  lives in
  [run_contract.md](../documents/engineering/run_contract.md), with adoption
  distributed across the reopened owner sprints rather than duplicated in this
  overview.
- **Bootstrap reconciler, prerequisite DAG, JIT cache.** Three idempotent stage-0
  bootstrap scripts (`bootstrap/{apple-silicon,linux-cpu,linux-cuda}.sh`) perform
  only the minimal host gates needed to reach `jitml bootstrap --<substrate>`.
  Apple verifies macOS on Apple Silicon, Homebrew, and the source-build
  prerequisites for `./.build/jitml`, then delegates to
  `jitml bootstrap --apple-silicon`.
  Linux verifies Docker without `sudo`, CUDA additionally verifies the NVIDIA
  container runtime and a qualifying `nvidia-smi` device, then delegates through
  `docker compose run --rm jitml jitml bootstrap --linux-cpu|--linux-cuda`.
  The typed `Prerequisite` DAG consumed by the Haskell bootstrap performs lazy
  package validation/remediation, including Homebrew package installation when
  a resource is actually needed. The content-addressed JIT cache is keyed on
  `(canonical-cbor(KernelSpec), kind, substrate, toolchain-fingerprint,
  rendered-source-payload, tuning-choice)`. Linux stores compiled shared objects
  under `./.build/jit/<substrate>/<hash>.so`; Apple stores
  `./.build/jit/apple-silicon/<hash>.metal.json` source metadata and executes it
  through a fixed host Metal bridge. Core Apple cache misses require
  `apple.metal-runtime` and `apple.metal-bridge`; they do not start Tart, invoke
  SwiftPM, require full Xcode, require the offline `metal` compiler, or depend
  on unlocked keychain state. This doctrine reopened and re-closed Phases
  `1`/`2`/`5`/`7`/`16`/`17` on 2026-06-12, and the legacy deletion ledger is
  empty. Outer-container Linux
  commands run as `docker compose run --rm jitml jitml <command>` against the
  headless default service; direct CUDA tests that need device exposure use the
  `jitml-cuda` companion service. The substrate image is `jitml:local`, the
  outer container is removed after cluster bootstrap, and the cluster daemon owns
  subsequent work. Owned by
  [phase-2-bootstrap-reconciler-and-jit-cache.md](README.md#legacy-to-new-phase-map).
- **Cluster substrate and routing.** Per-substrate Kind configs at
  `./kind/cluster-<substrate>.yaml` target an HA-capable topology: one
  control-plane, worker nodes sized by the HA resource profile, NodePort 30090
  backing the single edge listener, host `./.build/` bind-mounted into every
  node that can run jitML workloads via `extraMounts`, and at most one
  numerical ML compute worker per Kubernetes node. Storage uses
  `kubernetes.io/no-provisioner` only: manual PVs against a `jitml-manual`
  StorageClass backed by hostPath under
  `./.data/<namespace>/<StatefulSet>/pv_<integer>`. The umbrella Helm chart at
  `chart/` carries subchart dependencies for Harbor, Apache Pulsar, MinIO, the
  Percona Postgres operator, Envoy Gateway, and kube-prometheus-stack, plus
  local TensorBoard/observability renderers. The exposed listener is one
  `127.0.0.1:<edge-port>` Envoy Gateway socket; the typed route registry in
  `src/JitML/Routes.hs` is the source of truth for every HTTPRoute. The CLI
  never touches `~/.kube/config`. The explicit live bootstrap path sequences
  typed Kind, Helm, Docker build / Kind image-load, repo-owned manifest apply,
  and Pulsar-topic subprocesses, writes the leased-port publication with
  Helm-status-derived component health, patches Apple host Dhall, serves `/api`
  through the single Envoy localhost socket, and tears the Kind cluster down
  through `jitml cluster down`. Sprint `3.7` accepted the retained-cluster
  reconcile against that live topology: exact release, readiness, 34-topic,
  and image-identity evidence precedes publication; the versioned reconcile
  stamp follows publication; and only an exact retained match returns no-op
  exit code `3`.
  Phase: [phase-3-cluster-substrate-and-routing.md](README.md#legacy-to-new-phase-map).
- **Stateful platform services.** Harbor as the in-cluster registry
  against dedicated PostgreSQL storage, with explicit Harbor registry/token
  edge routes and `JitML.Service.HarborSubprocess` settings for Docker/curl
  capability calls; MinIO buckets `harbor-registry`,
  `jitml-checkpoints`, `jitml-datasets`, `jitml-transcripts`,
  `jitml-trials`, `jitml-tensorboard`, `jitml-artifacts` validated through
  the typed in-pod `mc` readiness subprocess; live `harbor-pg`
  PerconaPGCluster readiness with manual `volumeName`-bound PVs; 2026-05-19
  live registry-API validation proving Harbor starts against that external
  database and writes registry objects into MinIO's `harbor-registry` S3
  bucket; 2026-05-19 live `JitML.Service.MinIOSubprocess` validation proving
  routed MinIO `If-None-Match` / `If-Match` conflicts map to `SEConflict` and
  read/list/delete works through `/minio/s3`; Apache Pulsar
  as the control-plane ↔ data-plane bus with topic
  `inference.command.apple-silicon` for Apple host↔cluster raw inference-domain
  forwarding through `JitML.Service.Runtime`, and `inference.request.<mode>` /
  `inference.result.<mode>` for the demo-facing inference flow; 2026-05-19
  live validation proving `/pulsar/admin` works through the edge,
  `/pulsar/ws` targets `pulsar-broker:8080` with
  `webSocketServiceEnabled=true`, the full typed derived topic family exists,
  2026-05-20 live validation proving the then-current 26-topic family was
  registered and `training.command.linux-cpu` published/consumed through the
  `jitml:local` WebSocket path, and the current 34-topic family derives from
  `JitML.Coordinator.Topology`;
  `JitML.Service.PulsarWebSocketSubprocess` publishes and consumes through the
  routed WebSocket endpoint; Percona
  Operator-managed PostgreSQL for every packaged service that requires
  Postgres (jitML itself has no relational DB on its data path);
  kube-prometheus-stack with live-validated `/grafana` dashboard serving and
  `/prometheus` scraping of `jitml-service` `/metrics`; TensorBoard
  deployment/shard-key rendering, Haskell scalar-event writing, checkpoint
  sidecar dispatch, routed scalars API readback, and Linux CUDA
  RuntimeClass GPU visibility. Phase:
  [phase-4-stateful-platform-services.md](README.md#legacy-to-new-phase-map).
- **`jitml service` daemon.** `BootConfig` / `LiveConfig` renderers,
  lifecycle phases, endpoint responses, structured JSON log rendering,
  service error/retry helpers, plan-bound semantic-event deduplication, SIGHUP reload
  decisions, capability-class boundaries, stateless `Deployment`
  rendering, POSIX signal/control wiring, graceful-drain readiness,
  closed role-projected client settings derived from loaded `BootConfig`, an
  opaque MinIO/Pulsar-only Engine interpreter, the full Coordinator
  orchestration interpreter, and no retained Webapp daemon clients,
  BootConfig-derived opaque daemon Pulsar subscriptions rendered under
  `pulsar_subscriptions`, persistent consumer connection state carried as
  readiness evidence,
  read-only daemon client probes rendered under `client_probe_status`,
  typed mutating workload effects for MinIO write/CAS, Harbor promotion,
  kubectl apply/status/delete, and RunInference plus byte-faithful parsed daemon
  dispatcher routing,
  bounded persistent consumption exposed by `jitml service --consume-once
  <n>`, receipt-bound settlement owned by the WebSocket interpreter, normal
  `jitml service` background consumer workers with per-subscription handler
  routers, and LiveConfig-derived dedup cache sizing,
  fully-qualified broker topic routing, required
  anti-affinity rendered for one service pod per node, and the in-binary HTTP
  listener. The standalone live MinIO
  capability client and persistent Pulsar WebSocket path are validated;
  2026-05-21 live Linux CPU service-pod validation runs
  `jitml service --consume-once 1`, dispatches Training/RL/Tune/Inference
  messages before ack, applies Training/RL/Tune Jobs, routes
  `WriteCheckpointBlob` workload effects into MinIO,
  `PromoteWorkloadImage` workload effects into Harbor same-repository tag
  promotion, and handles `RunInference` through MinIO checkpoint reads plus
  Pulsar `InferenceResult` publication; 2026-05-21 live Linux CPU validation
  also proves normal service held-open-worker `RunInference` flow without
  `--consume-once`; 2026-05-21 live Linux CPU validation proves duplicate
  payload dedup through the held-open worker path and dispatch-failure
  negative-ack redelivery after a checkpoint is seeded; 2026-05-21 live Linux
  2026-05-23 CUDA service-pod validation historically ran the actual
  `jitml-service` pod with `runtimeClassName: nvidia` on the GPU-labelled
  compact Kind node and confirmed `nvidia-smi -L` inside the service container;
  2026-05-23 live Apple
  Silicon host validation runs the generated
  `./.build/conf/host/apple-silicon.dhall` through
  `jitml service --consume-once 0`, passes routed MinIO / Harbor / kubectl
  probes, and acquires `inference.command.apple-silicon` as `jitml-host`.
  Phase:
  [phase-5-jitml-service-daemon.md](README.md#legacy-to-new-phase-map).
- **Numerical core.** Haskell layer catalog (16 constructors: Dense,
  Embedding, Conv1D, Conv2D, Conv3D, ConvTranspose, ComplexDense,
  ComplexConv2D, BatchNorm, LayerNorm, GroupNorm, Dropout, ResidualBlock,
  ScaledDotProductAttention, MultiHeadAttention,
  RotaryPositionalEmbedding); 8 real activations (Relu, LeakyRelu, Elu,
  Silu, Gelu, Tanh, Sigmoid, Softmax) plus 3 complex activations
  (ComplexModRelu, ComplexCardioid, ComplexZRelu); 10 spectral /
  frequency-domain ops (FFT, FFTAlongAxis, IFFT, IFFTAlongAxis, RFFT,
  IRFFT, STFT, DCT, ComplexConjugate, ComplexMatMul); 13 optimizers
  (SGD, MomentumSGD, NesterovSGD, RMSProp, Adagrad, Adadelta, Adam,
  AdamW, LAMB, LARS, Lion, AdaFactor, Shampoo); 9 schedulers
  (Constant, Linear, Cosine, CosineWithWarmup, Exponential, Polynomial,
  OneCycle, Piecewise, ReduceOnPlateau); 10 loss functions
  (CrossEntropy, BinaryCrossEntropy, SparseCrossEntropy, Focal, MSE,
  Huber, IoU, Dice, KLDiv, Contrastive); Dhall mirror lists; and the
  cross-type lint audit. Owned by
  [phase-6-numerical-core.md](README.md#legacy-to-new-phase-map).
- **JIT codegen and per-substrate execution.** `src/JitML/Engines/`
  records backend metadata, determinism flags, typed kernel handles,
  cache hit/miss decisions, engine envelopes, and typed compile plans;
  `src/JitML/Codegen/` renders Apple MSL, oneDNN C++, and CUDA
  runtime source bundles under
  `./.build/jit-src/<substrate>/<hash>/`. `JitML.Codegen.KernelFamily`
  defines the typed `KernelFamily` ADT (`identity`, `reduction`,
  `dense`, `conv2d`, `conv3d`, `batchnorm`, `layernorm`, `mha`,
  `embedding`) consumed by the family-aware renderers
  (`renderOneDnnFamilySource`, `renderCudaFamilySource`,
  the target `renderMetalFamilySource`). `JitML.Engines.Tuning` declares the
  per-substrate `KnobSpace` (matmul tile / block-dim / cuDNN
  deterministic algorithm pin / threadgroup size / micro-kernel /
  reduction strategy / no-TF32 / no-fast-math) with
  `selectDeterministic` choosing the deterministic default and
  `tuningChoiceForResult` emitting the cache-key payload; `benchmarkPlan`
  enumerates deterministic-only candidates in stable order, and
  `selectMeasuredTuning` ranks a fixed measurement set by lowest latency with
  stable plan-order tie-breaking. `JitML.Engines.TuningStore` persists a
  selected measured `TuningChoice` under `jit/tuning/<substrate>/<base-hash>.json`
  and `JitML.Engines.TuningBenchmark` collects candidate measurements in plan
  order with SHA-256 output digests for the first-cache-miss hardware benchmark
  loop, while its CUDA/Metal benchmark-runner entrypoints preflight runtime
  availability and fail closed before unavailable live benchmark FFI execution.
  `JitML.Engines.TuningCache` loads that persisted choice to
  derive the final
  runtime source and cache key.
  `JitML.Engines.Loader` owns cache-hit/cache-miss artifact materialization and
  compile-on-miss for the local Linux CPU FFI path, while
  `JitML.Engines.Local` loads and runs the generated Linux CPU oneDNN reorder,
  reduction, matmul, convolution, normalization, attention, and embedding
  primitive paths through the Haskell FFI, validating the exported family-name
  and output-count symbols from each loaded artifact, while
  `JitML.Engines.OneDnnRuntime` owns the typed `libdnnl` package/header/link
  visibility probe for that production Linux CPU path. Generated CUDA source
  now exports the same `jitml_kernel` / family / output-count ABI, and
  `JitML.Engines.CudaLocal` consumes a positive CUDA runtime probe before
  compile/load/launch while failing closed before compile when no CUDA runtime
  is visible. The Apple target no longer exports a generated Swift dylib per
  kernel; `JitML.Engines.MetalLocal` calls the fixed bridge with cached MSL
  source metadata and validates output shape/family metadata on the Haskell
  side.
  `JitML.Engines.CudaRuntime` owns the host-side CUDA reduction
  partial-count/finalization helper plus the typed `nvcc` / `nvidia-smi` /
  `ldconfig` CUDA runtime probe. `JitML.Engines.MetalRuntime` owns the
  corresponding host Metal runtime probe for `MTLDevice.makeLibrary` and Metal
  device visibility before host FFI execution.
  The Apple first-cache-miss path writes MSL source metadata, then compiles
  through the fixed bridge in-process on first use. The Tart VM lifecycle,
  generated Swift/Tart build path, and Apple generated-dylib symlink surface are
  deleted from the supported runtime path; the `jitml internal vm` command group
  was removed by Sprint `1.15`, the core Tart prerequisite / bootstrap cleanup
  was removed by Sprint `2.12`, the daemon build-VM acquire/config path was
  removed by Sprint `5.10`, and Sprint `7.11` removed the codegen/cache residue.
  Headless Apple Metal live validation + Metal loading, live
  CUDA GPU-host compile/load/run validation plus cuBLAS/cuDNN bindings, and
  live benchmark-driven hardware auto-tuning are closed by Phases `15` / `16` /
  `17`, preserving the determinism contract per
  [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md):
  Metal single-stream launch order, oneDNN blocked reduction with fixed
  block size, CUDA deterministic warp-shuffle reductions with no device-side
  atomics plus host canonical partial finalization, `--use_fast_math=false`,
  and cuDNN explicit algorithm-id pinning.
  Phase:
  [phase-7-jit-codegen-and-substrates.md](README.md#legacy-to-new-phase-map).
- **Supervised learning and RL framework.** `src/JitML/SL/` and
  `src/JitML/RL/` provide the canonical SL problem catalog and all-row
  device-trainable cohort, the typed dataset registry
  (`SL.Dataset.canonicalDatasets`), the substrate-backed SL architecture runtime, the RL
  algorithm catalog rows, canonical RL environment metadata, framework run-plan
  metadata, registered rollout helpers over real environment dynamics, the three
  GADT-indexed lifecycles
  (`TrainingLifecycle`, `RLRunLifecycle`, `TuneSweepLifecycle`), the
  runtime RL primitives (`Policy`, `ReplayBuffer`, `AsyncBuffer`,
  `EpisodeEnvelope`), and run-to-run determinism for real trainer rollouts (two
  fresh runs compared against each other; no committed trajectory fixture per
  [../README.md → Snapshot targets → Numerical-fixture
  prohibition](../README.md#snapshot-targets)). The typed proto
  envelopes (`proto/jitml/{training,rl,tune,inference}.proto` and
  `JitML.Proto.{Training,Rl,Tune,Inference}`) declare the substrate-scoped Pulsar
  topic family; the mirrors parse the deterministic text command envelopes
  emitted by their renderers, and the current Training/RL/Tune command and
  event oneofs plus Inference request/result envelopes also round-trip through
  proto3-compatible bytes. Live MinIO dataset fetch, daemon-backed training
  loops, and live Pulsar training/event flow are implemented and validated on
  the closed Phase `8` surface. Algorithm-specific compiled RL-plan adoption
  closed in Phase `251`; typed measured counters and separated learning/final-
  evaluation evidence closed in Phase `252`. Phase:
  [phase-8-supervised-and-rl-framework.md](README.md#legacy-to-new-phase-map).
- **RL algorithm catalog, AlphaZero, hyperparameter tuning.** Catalog
  covers PPO through AlphaZero as metadata rows with a Dhall
  mirror/audit; the 14 per-algorithm modules under
  `src/JitML/RL/Algorithms/{Ppo,A2c,Trpo,MaskablePpo,RecurrentPpo,Dqn,QrDqn,Ddpg,Td3,Sac,CrossQ,Tqc,Ars,Her}.hs`
  expose typed hyperparameter rows and deterministic per-seed rollout
  transcripts aggregated through `Registry.algorithmModuleRegistry`.
  The AlphaZero substack lives at
  `src/JitML/RL/AlphaZero/{Mcts,SelfPlay,PolicyValueNet}.hs` with persistent
  search tree (PUCT + visit-count), device-backed policy/value leaf evaluation,
  self-play buffer with content hash, and arena win-rate promotion. The
  `PerfectInformation` typeclass
  admits Connect 4 / Othello / Hex / Gomoku with per-game
  `applyMove` rules and per-game two-headed network metadata.
  `experiments/mnist-tune.dhall` renders the canonical `Some
  Tuning::{ … }` worked example from README. Real network forward/back through
  the JIT engine, live trial transcript persistence, and on-hardware reward
  thresholds are implemented on the closed Phase `9` surface; Phase `252`
  closed typed measured counters and distinct ordered-learning versus exact
  final-evaluation evidence. Phase:
  [phase-9-rl-catalog-alphazero-and-tuning.md](README.md#legacy-to-new-phase-map).
- **Checkpointing and inference-only read path.** The retained surface uses one
  self-describing `RawCheckpointEnvelope`; its typed `RawCheckpointBody`
  selects a weight-only or supervised-graph payload. The manifest includes
  the full split-blob shape (`TensorBlob`, `OptimizerBlob`, `RngBlob`,
  monotonic step, per-metric values, parent-manifest lineage SHA,
  architecture metadata, preprocessing metadata, output decoders,
  model-family identifiers, weight-layout descriptors, replay/transcript
  pointers, and per-substrate artifact identity),
  deterministic manifest CBOR codec / content hash with canonical
  ordering, split-blob object-key renderers, pointer-CAS decision
  surface, the typed `AdvancePredicate` ADT
  (`AdvanceLatest`/`AdvanceBestMaximised`/`AdvanceBestMinimised`),
  `deriveExperimentHash` computing
  `sha256(resolved-dhall || substrate-fingerprint)`, the
  binary `.jmw1` encoder/decoder, manifest pointer, filesystem-backed
  checkpoint store, split `writeCandidateCheckpointSnapshot{,WithMinIO}` and
  `writeCompletedCheckpointSnapshot{,WithMinIO}` operations with opaque
  `StoredCandidateCheckpoint` / `StoredCompletedCheckpoint` results, exact
  absent-or-byte-identical immutable writes, and exact pointer CAS. Store's
  `admitLatestCheckpoint` and `admitCheckpointAt` return opaque exact persisted
  graphs; `requireAdmittedCompletedCheckpoint` is the only completion admission
  used by `loadInferenceCheckpointWith` and
  `loadInferenceCheckpointWithWeights` before decoded `.jmw1` weights reach the
  selected runner. Admission checks manifest experiment/content addresses,
  tensor payload addresses, exact JMW1 bytes, tensor shapes, and virtual slices,
  `daemonWorkloadDispatcherWithWeightedInference` for routing self-inference
  daemon requests through generated weighted checkpoint runners, and the GC reconciler surface
  (`RetentionPolicy{KeepAll,LastN}`, `walkLiveSet`,
  `applyRetentionPolicy`, `buildGcPlan` with `gcReapEvents` and the
  `gcNoOp` second-invocation detector). The inference request/result schema
  and local byte codecs live in `proto/jitml/inference.proto` and
  `JitML.Proto.Inference`. `src/JitML/Web/Server.hs` no longer serves inline
  demo policy/value networks on the inference/image/Connect 4 routes. Those
  routes use an injected checkpoint runtime handler that calls
  `loadInferenceCheckpointWithWeights` when `jitml-demo` has a live
  publication and fails closed with `503 checkpoint-required` otherwise.
  Those mechanisms and the earlier all-lane results remain historical evidence.
  Sprint `10.6`'s exact-V2 supervised runtime artifact and strict Store-loaded
  parity are historical closure evidence from the pre-Phase-`235` wire design;
  Sprint `10.12`'s addressed-manifest admission result is historical closure
  evidence from the same lineage. Phase `235` subsequently replaced the
  multi-version wire and admission cascade with the one envelope and typed body
  variants. CUDA and Apple retest their real hardware paths in Sprints `29.5`
  and `30.4`. Sprints `10.6` and `10.12` remain Done.
  Phase:
  [phase-10-checkpointing-and-inference.md](README.md#legacy-to-new-phase-map).
- **PureScript frontend and demo.** Minimal PureScript entrypoint,
  generated contract file from `src/JitML/Web/Contracts.hs`, typed
  bundle/panel/demo-route metadata from `src/JitML/Web/Bundle.hs` (the current
  panel surfaces plus the full local API route family), the panel modules under
  `web/src/Panels/` with
  typed request/response payload shapes plus the shared API/WebSocket bridge
  modules, `web/test/Main.purs` smoke suite, the live Playwright matrix at
  `playwright/jitml-demo.spec.ts`, `src/JitML/Web/Server.hs` HTTP
  serving, and the `chart/local/jitml-demo` Webapp deployment template.
  The Halogen mount machinery, compiled bundle output, and
  `purescript-spec` execution through the Node `spec-node` runner landed in
  Sprints `11.3` / `11.4` /
  `11.5`; the live REST/WS proxy, live-edge Playwright surfaces, and
  value assertions for MNIST / CIFAR / Connect 4 later closed in Phases
  `11` / `15`, and Phase `17` removed the offline fallback paths.
  The generated PureScript contract exposes typed
  inference/generic/image/checkpoint-compare/adversarial/training/RL/tune/control
  payload decoders, browser REST request envelopes, request-aware command
  publication, and an injected checkpoint runtime handler for
  MNIST/generic/CIFAR/checkpoint-compare/Connect 4. The current panels use those
  surfaces rather than marker/default parsers and provide training/RL/tune
  command-envelope controls, training metadata, RL replay scrub summaries, and
  multi-game adversarial boards, and render non-placeholder loss/policy/MCTS/tuning
  summaries. Phases `14`–`18` retain the historical live all-substrate REST,
  command-state, replay/adversarial, and Playwright evidence they gathered; the
  current no-caveat product claim is withdrawn until the Sprint `10.6` → `34.3`
  typed-run-contract chain refreshes that evidence.
  The default `purs-tidy check 'src/**/*.purs'` invocation in `web/` lands
  through `jitml lint purescript` (Sprint `11.3`). Phase:
  [phase-11-purescript-frontend-and-demo.md](README.md#legacy-to-new-phase-map).
- **Test stanzas, lint matrix, live workflow matrix.** Ten Cabal
  test-suite stanzas, each `type: exitcode-stdio-1.0` with `tasty` as
  the in-stanza runner: `jitml-unit`, `jitml-integration`,
  `jitml-sl-canonicals`, `jitml-rl-canonicals`, `jitml-hyperparameter`,
  `jitml-backends`, `jitml-daemon-lifecycle`, `jitml-e2e`,
  `jitml-negative-controls`, and `jitml-model-convergence`.
  `jitml test all
  --dry-run` renders the Plan/Apply test plan; non-dry-run `jitml test
  all` delegates to `cabal test` through the typed `Subprocess`
  boundary and prints the report-card summary. Lint and code-quality
  commands are separate from the test orchestrator.
  `JitML.Test.LivePlan.livePhasedClusterPlan` enumerates the typed
  phased Helm rollout per substrate; `JitML.Test.LivePlan.liveE2EPlan`
  is the typed ephemeral-Kind orchestration that runs `helm dependency
  build chart` → `jitml bootstrap` → pinned Playwright browser-image run →
  `jitml cluster down`. Real-binary integration, live SL convergence, live RL
  trajectories, live hyperparameter reproducibility, and live Playwright are
  implemented and validated through the closed Phase `12` surface. Closed Phase
  `261` supplies the command-owned authenticated cross-process integration
  journal: startup consumes and clears the private key-file
  capability before Tasty, all projected ProductRows must yield exact completed
  evidence, and the parent authenticates the aggregate before Store re-admission.
  Browser/Playwright consumption is the Active Phase `262` successor.
  Within-substrate apple-silicon reproducibility is validated host-native by
  Sprint `16.6`; no cross-substrate parity path remains. The seven doctrine
  test categories (Pure Logic, Parser, Property, Snapshot (pure-renderer
  output only), Integration, Daemon Lifecycle, Ephemeral-Cluster
  Infrastructure) all map to one
  or more of these stanzas, with the four `*-canonicals`/HPO/cross-
  backend rows being project-specific Integration extensions under
  doctrine §Test Organization → project-specific stanzas. Phase:
  [phase-12-test-stanzas-and-cross-cluster.md](README.md#legacy-to-new-phase-map).

## Doctrine Scope

[../README.md](../README.md) is the authoritative project and CLI doctrine.
The project [../README.md → Doctrine scope](../README.md#doctrine-scope) declares
which sections are binding and which are informational; this plan inherits that
split verbatim. No sprint may schedule adoption of an out-of-scope section.

**In scope (binding) from `README.md`, in doctrine order:**

- Overview (toolchain pinning — instantiated by [../README.md → Toolchain
  pinning](../README.md#toolchain-pinning)): GHC `9.12.4`, Cabal `3.16.1.0`.
- Project Structure (library-first; instantiated by [../README.md → Repository
  layout (target)](../README.md#repository-layout-target)): thin `app/Main.hs`,
  role logic in `src/JitML/`.
- Command Topology — commands as ordinary Haskell ADTs.
- GADT-Indexed State Machines — training lifecycle, RL run lifecycle, tuning sweep
  lifecycle.
- Typed Run Contracts — raw-to-validated refinement, positive unit-indexed
  quantities, kind-indexed plans/protocols, pure exact evidence reducers,
  receipt-bound settlement, opaque completion evidence, and one
  functional-core/imperative-shell interpreter.
- Progressive Introspection — `jitml commands [--tree|--json]`, `jitml help
  <subcommand>`.
- Automatically Generated Documentation.
- Generated Artifacts — paired check/write for generated sections and tracked
  generated files: route tables, Grafana dashboards, PureScript contracts, CLI
  help, markdown docs, manpages, shell completions, and chart YAML rendered from
  Haskell registries; `GeneratedSectionRule` registry;
  `trackingGeneratedPaths`.
- Architecture — including Subprocesses as Typed Values: kernel-compiler
  subprocesses (`metal`, `nvcc`, `g++` over oneDNN), `kubectl`, `helm`, `kind`,
  `docker` all wrapped through the typed `Subprocess` boundary with a structured
  success-transcript/nonzero-failure result as the only IO interpreter;
  `callProcess`, `readCreateProcess`,
  `System.Process` constructors, and `typed-process` smart constructors are
  forbidden from command runners.
- Plan / Apply — `jitml bootstrap`, `jitml train`, `jitml tune`,
  `jitml rl train`, `jitml cluster up`, `jitml test all`, `jitml service`
  startup-as-plan, and `jitml internal gc` all Plan/Apply commands with `--dry-run` and
  `--plan-file <path>`.
- Output Rules — `--format json|table|plain`, default `table` on TTY else `plain`;
  `--color auto|always|never` / `--no-color`.
- Standard Flag Families — Plan/Apply, Daemon, Output families per
  [../README.md → Standard flag families](../README.md#standard-flag-families).
- Error Handling — single `AppError` ADT with `renderError :: AppError -> Text` as
  the only Text rendering at the CLI boundary; extended with exit code `3` for
  reconciler no-op-on-match per
  [../README.md → Exit codes and error rendering](../README.md#exit-codes-and-error-rendering).
- Capability Classes and Service Errors — `HasMinIO`, `HasPulsar`, `HasHarbor`,
  `HasKubectl`.
- Retry Policy as First-Class Values.
- Prerequisites as Typed Effects — stage-0 scripts only check the host gates
  required to reach `jitml bootstrap`; one `prerequisiteRegistry` spans every
  substrate's toolchain, lazy package remediation, the cluster lifecycle, the
  platform services, and the daemon's startup contract; failure emits
  `AppError PrerequisiteUnmet` carrying the failing `nodeId`, description, and
  remedy hint.
- Application Environment — `ReaderT Env IO` with a single `Env` record threaded
  through command runners.
- **Long-Running Daemons in the Same Binary** — `jitml service` has refined
  `BootConfig` / operational `LiveConfig` Dhall, actual SIGHUP reload and
  signal drain, `/healthz` / `/readyz` / `/metrics`, and closed service-error
  kinds. Sprint `12.16` completed the opted-in target with the operational
  structured stderr sink, dynamic filter/retry readers, live Coordinator
  interpreter, role-indexed client projections, and keyed host-workload
  lifecycle. Bounded role startup probes and exact substrate-indexed role/public-
  edge readiness rows prevent bootstrap from publishing a partially ready
  cluster; Apple never treats its zero-replica clustered Engine as host-daemon
  evidence. Its immutable-image canonical validation is complete.
  (Contrast: sibling projects may opt out; jitML opts in.)
- Inference batch admission captures one immutable monotonic
  handler-completion/publication-entry deadline and uses a shorter collection
  cutoff. Sparse batches stop coalescing after the smaller of one millisecond
  or one tenth of the captured latency budget, so waiting for batch capacity
  cannot make the handler unreachable. If no decision has returned by the
  captured deadline, the transport cancels the handler and Nacks every admitted
  receipt; the Engine also refuses to begin a new result publication at or
  after that deadline. A decision returned before timeout is settled as
  returned, without a retroactive deadline-based Nack, because publication may
  already be visible. The operational default is five seconds: the former
  25-millisecond value produced an endless real cold-path Nack loop, while a
  live one-second diagnostic completed at approximately 996 milliseconds from
  broker delivery to acknowledgement. This changes the configured window, not
  its monotonic handler/publication-entry enforcement or the one-millisecond
  collection cap; it does not promise that broker acknowledgement completes
  inside the window.
- Short-lived `Owned` request/reply consumers cannot return from a normal
  primary result until their worker has been cancelled and joined. Their
  bounded subscription DELETE is cancellation-safe; a secondary cleanup
  failure remains observable beside the normal primary, while exceptional
  primary exits retain their original exception identity after that secondary
  failure is reported. Inference replies match both `callId` and experiment
  hash, and a live request/reply transport failure remains `PulsarFailed`
  rather than being recast as checkpoint-missing evidence. This higher-order
  lifecycle is isolated in
  `JitML.Service.InferenceReplyScope` behind non-inlining entrypoints, keeping
  the supported heap-capped build from pulling it back into the already-large
  CLI composition module.
- Product-level Tune completion consumes the registered ProductRow and Catalog
  schedule. A reduced sweep may exercise transport, but cannot mint product
  completion or weaken the registered convergence target.
- At-Least-Once Event Processing — semantic event identity is distinct from an
  opaque broker receipt. Each completed batched command commits its semantic ID
  independently, so later cancellation preserves earlier commits without
  claiming exactly-once broker delivery. The persistent interpreter applies one
  returned handler disposition per receipt; a handler that has not returned at
  its captured deadline is cancelled and Nacked, while a returned disposition
  is never retroactively changed. Settlement, drain, child-process, and cleanup
  failures stay typed, and every private receipt admitted during a batch-drain
  race is Nacked and flushed before `Drained`.
- Reconcilers: Idempotent Mutation as a Single Command — `jitml bootstrap`,
  `jitml cluster up`, `jitml docs generate`, `jitml lint --write`,
  `jitml internal gc`.
- Lint, Format, and Code-Quality Stack — `fourmolu` + `hlint` + `cabal format`;
  pinned `fourmolu.yaml` at repo root with the thirteen doctrine-mandated settings;
  jitML adopts the doctrine with a container-exclusive code-quality domain: the
  `jitml:local` Docker image installs the same pinned GHC `9.12.4` and pinned
  `fourmolu` / `hlint` binaries, image construction runs the Haskell style gate,
  `jitml lint haskell` runs only inside the container-owned gate, and
  `jitml lint purescript` covers generated-contract, whitespace,
  panel-contract, typed frontend-tool command checks, and the `spec-node`
  `purescript-spec` smoke suite.
- Testing Doctrine.
- Standard Testing Stack — Cabal + `exitcode-stdio-1.0` + tasty + tasty-hunit +
  tasty-quickcheck + typed-process + temporary. Snapshot
  comparisons for pure-renderer output use `tasty-hunit` text/byte
  equality; `tasty-golden` is intentionally not adopted, since the
  project forbids numerical fixtures per
  [../README.md → Snapshot targets → Numerical-fixture
  prohibition](../README.md#snapshot-targets).
- Test Categories — each of the seven (Pure Logic, Parser, Property,
  Snapshot (pure-renderer output only), Integration, Daemon Lifecycle,
  Ephemeral-Cluster Infrastructure) mapped to a
  `jitml-*` stanza in
  [phase-12-test-stanzas-and-cross-cluster.md](README.md#legacy-to-new-phase-map).
- Test Organization — one `test-suite` stanza per tier; project-specific stanzas
  per [../README.md](../README.md); all live scenarios use the shared run
  interpreter and report actual invocation/journal outcomes.

**Out of scope (informational only — no sprint may schedule adoption):**

- Smart Constructors for Paired Resources — no paired infra resources at present;
  if a PV/PVC pattern emerges, this section comes back into scope.
- The Architecture (the doctrine's closing capsule) — informational summary; the
  individual sections it recaps are the binding contract.

**Stack deviations from doctrine:** None for the in-scope Haskell CLI doctrine
surface at write time. The full doctrine-mandated
standardized library set (including `dhall`, used as the configuration source for
both `BootConfig` / `LiveConfig` and every experiment / sweep / cluster-topology
file) is in scope. The PureScript stack (Halogen, `purescript-bridge`,
`purescript-spec`, `spec-node`, Playwright) is a project-specific target owned by Phase `11`
and is not a doctrine deviation because the doctrine does not address browser-side
code; the current worktree implements the PureScript shell, generated contract
file, `spec-node` smoke suite, Halogen panel modules, demo server, and live-only
Playwright scaffold.

## Hard Constraints

The supported architecture closes on the following non-negotiable rules.
Each rule maps to one or more [Exit Definition](../DEVELOPMENT_PLAN/README.md#exit-definition)
items; whether the rule is met today is the owning sprint's status. The
phase docs and `system-components.md` carry the per-component status.
Numbered for referenceability. Cross-references to
[../README.md](../README.md) name the authoritative section that pins
each constraint.

1. One Haskell CLI binary named `jitml`; the bundled `jitml-demo` workload is a
   Webapp role instance of that same binary. The binary is built by Cabal under
   GHC `9.12.4` and Cabal `3.16.1.0`.
2. Library-first layout per doctrine
   [§Project Structure](../README.md): `app/Main.hs` is a six-line shim into
   `App.main`; nearly all logic lives under `src/JitML/`.
3. Three supported substrates: `apple-silicon`, `linux-cpu`, `linux-cuda`. A
   fourth substrate `linux-opencl` (Intel GPU) is admitted as a future extension
   and is not in the current support matrix.
4. One CLI verb for the daemon — `jitml service` — parameterised entirely by its
   Dhall config. There is no separate `host-service` CLI verb. The Dhall declares
   `substrate`, `residency : Cluster | Host`, `inferenceMode : SelfInference |
   ForwardToHost`, and host-side connection info when `residency = Host`.
5. On every substrate the in-cluster `jitml-service` is a stateless `Deployment`,
   not a `StatefulSet`. Required pod anti-affinity at `topologyKey:
   kubernetes.io/hostname` enforces at most one numerical ML compute worker per
   Kubernetes node, irrespective of other replica counts. Linux Engine pods and
   daemon-spawned Linux workload Jobs share the `jitml.compute="true"`
   hard-placement contract; Apple clustered pods remain non-compute forwarders.
   Durable state lives in MinIO and Pulsar exclusively (no relational DB on
   jitML's data path).
6. The CLI never touches `~/.kube/config`. Cluster kubeconfig lives at
   `./.build/jitml.kubeconfig`. Stage-0 bootstrap scripts never write
   `~/.kube/config`, `~/.docker/config.json`, the user's Homebrew prefix, or any
   global state outside the repo. Haskell `jitml` may install Homebrew packages
   lazily through typed prerequisite remediation, with pure plan construction,
   typed `Subprocess` apply, and postcondition validation.
7. Every Plan/Apply command supports `--dry-run` (renders the plan and exits 0)
   and `--plan-file <path>` (writes the rendered plan for out-of-band review).
8. `Subprocess` is the only IO boundary for subprocess execution. `kubectl`,
   `helm`, `kind`, `docker`, `nvcc`, `g++` (over oneDNN), optional non-core Swift
   probes, and every kernel-compiler invocation goes through the typed boundary.
   The Apple core Metal path compiles MSL in-process through the fixed bridge via
   `MTLDevice.makeLibrary(source:options:)`, not through Tart, SwiftPM, full Xcode,
   or the offline `metal` compiler.
   `callProcess`, `readCreateProcess`, `System.Process` constructors, and
   `typed-process` smart constructors are hlint-forbidden outside the
   `runStreaming` / `capture` interpreter.
9. One `prerequisiteRegistry` spans every substrate's toolchain, the cluster
   lifecycle, the platform services, and the daemon's startup contract. Failure
   emits `AppError PrerequisiteUnmet` carrying the failing `nodeId`, description,
   and remedy hint, with exit code `2`.
10. Single `AppError` ADT; `renderError :: AppError -> Text` is the only Text
    rendering at the CLI boundary; `print`, `exitFailure`, and direct terminal
    formatting are hlint-forbidden outside `src/JitML/CLI/Output.hs`.
11. Exit codes follow the doctrine plus exit code `3` for reconciler no-op-on-
    match (the resource already matches the desired state; no change applied).
12. `CommandSpec` is the implementation source for the parser, the command tree
    (`jitml commands --tree`), the JSON command schema (`jitml commands --json`),
    the markdown command reference, the manpages, and the shell completion
    scripts. The parser is a renderer of the spec.
13. The route registry `src/JitML/Routes.hs` is the source of truth for every
    HTTPRoute resource emitted by the umbrella chart's renderer. Hand-edited
    HTTPRoute YAML in the chart is hlint-forbidden.
14. The single exposed listener is one `127.0.0.1:<edge-port>` socket on the
    Envoy Gateway; the in-cluster NodePort `30090` backs that listener. The edge
    port is selected starting at `9090` and incremented until available; recorded
    as the `edge_port` field of `./.build/runtime/cluster-publication.json` (the
    single file bootstrap writes).
15. Storage uses `kubernetes.io/no-provisioner` only — manual PVs against the
    `jitml-manual` StorageClass backed by hostPath under
    `./.data/<namespace>/<StatefulSet>/pv_<integer>`.
16. `./.build/` is the host root for compiled artifacts, generated Dhall,
    kubeconfig, Kind metadata, cluster publication, and JIT cache entries.
    `./.data/` is strictly for manual PV bind mounts. Both are in `.gitignore`
    and `.dockerignore`.
17. The JIT cache root is `./.build/jit/`; Linux entries are compiled shared
    objects and Apple target entries are `<hash>.metal.json` source metadata.
    Entries are content-addressed by `sha256(canonical-cbor(KernelSpec) || kind
    || substrate || toolchain-fingerprint || rendered-source-payload ||
    tuning-choice)` where `KernelSpec` is model shape and `kind` is
    `training | inference`. Training and inference kernels are separate artifacts.
18. Apple Silicon uses one fixed host bridge under `./.build/host/apple-silicon/`
    or linked into the host binary; per-kernel generated-dylib symlinks are
    legacy residue pending Sprint `7.11`.
19. `./bootstrap/{apple-silicon,linux-cpu,linux-cuda}.sh` are idempotent stage-0
    entrypoints. Apple checks macOS/arm64, Homebrew, and the source-build
    prerequisites for `./.build/jitml`, then calls
    `jitml bootstrap --apple-silicon`. Linux checks Docker without `sudo`; CUDA
    additionally checks NVIDIA runtime and device compute capability; both call
    `docker compose run --rm jitml jitml bootstrap --linux-cpu|--linux-cuda`.
    The typed `Prerequisite` DAG is consumed in-process by the Haskell bootstrap.
20. `purge` is destructive but cache-preserving (`./.build/` survives, including
    the JIT cache); `purge --full` additionally removes `./.build/` and, on Linux,
    the substrate image.
21. The substrate image is always `jitml:local`. Substrate is a runtime Dhall
    choice, never an image-name dimension. There is one Dockerfile, one image,
    and two compose service wrappers: headless `jitml` plus GPU-enabled
    `jitml-cuda`. The image build owns the style-tool bootstrap and is
    the exclusive Haskell style/code-quality gate on every substrate.
22. `jitml service` is a long-running daemon parameterised by refined Dhall
    `BootConfig` / operational `LiveConfig`. SIGHUP requests a reread; a valid
    changed live snapshot applies once, malformed live input retains last-good
    state, and immutable changes drain then exit restart-required. Endpoints
    `/healthz`, `/readyz`, `/metrics` are present. The pure structured-log
    renderer is retained, and the operational sink reads the dynamic filter for
    every stderr emission.
23. The daemon's Pulsar consumer is at-least-once. Idempotency is the consumer's
    responsibility: strict decode derives semantic identity from the resolved
    plan, command kind, and logical key rather than payload bytes or a
    client-supplied ID. The current local subscription
    plan is derived from `BootConfig`, and the normal serve path starts
    persistent scoped consumer workers with live duplicate-payload dedup and
    dispatch-failure negative-ack redelivery validated on Linux CPU. The retry
    policy is a typed value with named strategies, and every newly scheduled
    operation reads the active production policy.
24. Capability classes `HasMinIO`, `HasPulsar`, `HasHarbor`, `HasKubectl` are the
    only allowed entry into external services from the daemon. Local workload
    effects route MinIO write/CAS, Harbor promotion, kubectl
    apply/status/delete, and RunInference through those classes via
    byte-faithful parsed dispatcher payloads; live running-daemon handler
    routing is validated by Phase `5`. The runner is `ReaderT Env IO`.
25. The Apple Silicon hybrid pattern: clustered Deployment (`Cluster +
    ForwardToHost`) plus host-native binary (`Host + SelfInference`). The
    cluster daemon forwards raw inference-domain payloads on
    `inference.command.apple-silicon`; the host Engine publishes results directly
    to each request's reply topic. `JitML.Proto.Inference` owns the typed
    render/parse surface and `JitML.Service.Runtime` owns the forwarding path.
    Pulsar carries only small envelopes; large tensors travel via MinIO. Direct
    k8s API access from the host is forbidden and lint-enforced.
26. Numerical-core closure is fully Dhall-typed: every layer constructor,
    activation, optimizer, scheduler, and loss function has a Dhall type
    and a corresponding Haskell ADT. The implementation lives in
    `src/JitML/Numerics/Catalog.hs`, with constructor-name Dhall mirrors
    under `dhall/numerics/` and the cross-type audit in
    `src/JitML/Numerics/Schema.hs` / `src/JitML/Lint/DhallNumerics.hs`.
    Richer parameterized Dhall records are owned by future numerical-core
    work logged through standards rule G's Doc Requirements blocks.
27. Per-substrate determinism contract per
    [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md):
    Metal single-stream launch order; oneDNN blocked reduction with fixed block
    size; CUDA `--use_fast_math=false`, deterministic warp-shuffle reductions
    with no device-side atomics, cuDNN explicit algorithm-id pinning.
    Within-substrate equality is guaranteed bit-for-bit; cross-substrate
    equivalence is not claimed (RNG draws and float reduction order differ
    between substrates), so no cross-substrate tolerance band is asserted.
28. Target JIT compiler inputs are generated by the Haskell `jitml` binary on a
    cache miss. The repository does not use static checked-in `.cu`, `.cc` /
    `.cpp`, per-kernel MSL source files, Swift package source files, native
    adapter shims, or per-substrate JIT build `.sh` scripts as build inputs. The Haskell
    renderers emit Linux compiler inputs into
    `./.build/jit-src/<substrate>/<hash>/`; the Apple renderer emits MSL into the
    `.metal.json` cache artifact consumed by the fixed bridge. Checked-in
    native/foreign source exceptions are allowed only for the fixed non-kernel
    bridge source or Haskell Objective-C-runtime bridge, not per-kernel adapters.
29. Same-substrate bit-equality means: a transcript or checkpoint produced on
    `<substrate>` is bit-identical when reproduced on the same `<substrate>`
    against the same toolchain pin. Cross-substrate bit-equality is **not**
    guaranteed.
30. The `.jmw1` dense weight blob format is magic bytes, `header_len`, a
    canonical-CBOR `JmwHeader`, and packed little-endian tensor payload bytes.
    Manifests are typed and content-addressed against MinIO bucket
    `jitml-checkpoints`. Optimizer state (Adam moments, RMSProp accumulators)
    lives as a separate checkpoint part.
31. The PureScript browser-contract ADTs live in `src/JitML/Web/Contracts.hs`.
    The current worktree uses a local bridge-compatible renderer for
    `web/src/Generated/Contracts.purs` and `src/JitML/Web/Bundle.hs` records
    the bundle/panel/demo-route metadata. Sprint `11.9` extends the generated
    file with current-panel inference/generic/image/checkpoint-compare/
    adversarial/training/RL/tune/control
    request/render/parser surfaces. The generated contract file is protected by the active
    `trackingGeneratedPaths` registry.
32. `fourmolu.yaml` at repo root pins the thirteen doctrine-mandated settings.
    `docker/Dockerfile` installs the same pinned GHC `9.12.4` and pinned
    `fourmolu` / `hlint` binaries for `jitml:local`; the image build runs the
    Haskell style/code-quality gate; `jitml lint haskell` runs only inside
    `jitml:local`; and `cabal format` is enforced by
    temp-file round-trip byte-equality. Test commands do not run style or
    code-quality gates.
33. Ten Cabal test-suite stanzas, each `type: exitcode-stdio-1.0` with `tasty`
    as the in-stanza runner: `jitml-unit`, `jitml-integration`,
    `jitml-sl-canonicals`, `jitml-rl-canonicals`, `jitml-hyperparameter`,
    `jitml-backends`, `jitml-daemon-lifecycle`, `jitml-e2e`,
    `jitml-negative-controls`, `jitml-model-convergence`.
    A single `tasty` tree
    spanning all tiers is forbidden.
34. Target e2e closure uses the typed `JitML.Test.LivePlan.liveE2EPlan` as
    the ephemeral-Kind orchestration that the `jitml-e2e` stanza drives through
    the typed `Subprocess` boundary: `helm dependency build chart` → `jitml
    bootstrap` (ephemeral Kind + phased Helm rollout) → pinned Playwright browser-image run
    → `jitml cluster down`. The current default `jitml-e2e` body validates that
    plan shape but does not invoke the live stack.
35. Report-card knobs are pinned in `cabal.project` and surfaced through `jitml
    test all`. The exact knob list is owned by Sprint `12.9` and recorded in
    [system-components.md](system-components.md).
36. The toolchain is pinned at GHC `9.12.4` and Cabal `3.16.1.0`. `jitml.cabal`
    declares `tested-with: ghc ==9.12.4`; `cabal.project` declares
    `with-compiler: ghc-9.12.4`. CUDA/NVCC, cuDNN, Node, ALE, Playwright, and
    `kindest/node` have concrete pins in Docker, package, or Kind config files
    as documented in [../README.md → Toolchain pinning](../README.md#toolchain-pinning).
    LLVM and oneDNN currently come from the host/container package set and are
    recorded/probed, not pinned by `cabal.project`.

## Dependency Chain

Each phase is a single-session unit **blocked only by a lower-numbered phase** (forward-only DAG, standards [rule M](development_plan_standards.md)). The legacy sprint column cross-references the pre-2026-07-24 numbering (see the old→new map in [README.md](README.md)).

| Phase | Title | Status | Legacy sprint |
|---|---|---|---|
| 1 | [Canonical Plan Suite Bootstrap](phase-1-canonical-plan-suite-bootstrap.md) | ✅ Done | 0.1 |
| 2 | [Doctrine-Driven Scheduling Audit](phase-2-doctrine-driven-scheduling-audit.md) | ✅ Done | 0.2 |
| 3 | [Governed-Document Metadata Enforcement](phase-3-governed-document-metadata-enforcement.md) | ✅ Done | 0.3 |
| 4 | [Toolchain Pin and Library-First Cabal Project](phase-4-toolchain-pin-and-library-first-cabal-project.md) | ✅ Done | 1.1 |
| 5 | [`CommandSpec` Registry and Generated Parser](phase-5-commandspec-registry-and-generated-parser.md) | ✅ Done | 1.2 |
| 6 | [Generated Sections and Tracking-Generated Paths](phase-6-generated-sections-and-tracking-generated-paths.md) | ✅ Done | 1.3 |
| 7 | [Lint Stack, `fourmolu`, `hlint`, `cabal format`, `forbiddenPathRegistry`](phase-7-lint-stack-fourmolu-hlint-cabal-format-forbiddenpathregistry.md) | ✅ Done | 1.4 |
| 8 | [`Plan` / `apply` Boundary with `--dry-run` and `--plan-file`](phase-8-plan-apply-boundary-with-dry-run-and-plan-file.md) | ✅ Done | 1.5 |
| 9 | [`Subprocess` Typed Values, `runStreaming` / `capture` Interpreter](phase-9-subprocess-typed-values-runstreaming-capture-interpreter.md) | ✅ Done | 1.6 |
| 10 | [Prerequisite Registry as Typed Effects](phase-10-prerequisite-registry-as-typed-effects.md) | ✅ Done | 1.7 |
| 11 | [`Env` Record and `ReaderT Env IO` Runner](phase-11-env-record-and-readert-env-io-runner.md) | ✅ Done | 1.8 |
| 12 | [`AppError` ADT, `renderError`, Output Rules](phase-12-apperror-adt-rendererror-output-rules.md) | ✅ Done | 1.9 |
| 13 | [Scoped `allow-newer` Retirement Gate](phase-13-scoped-allow-newer-retirement-gate.md) | ✅ Done | 1.10 |
| 14 | [GHC 9.12.4 Baseline and Dependency Helper Retirement](phase-14-ghc-9-12-4-baseline-and-dependency-helper-retirement.md) | ✅ Done | 1.11 |
| 15 | [CLI Dhall Overrides](phase-15-cli-dhall-overrides.md) | ✅ Done | 1.12 |
| 16 | [Remove `verify cross-backend`, add `jitml test --test-options` passthrough](phase-16-remove-verify-cross-backend-add-jitml-test-test-options-pass.md) | ✅ Done | 1.13 |
| 17 | [Reinstate the `jitml internal vm` build-VM command surface](phase-17-reinstate-the-jitml-internal-vm-build-vm-command-surface.md) | ✅ Done | 1.14 |
| 18 | [Retire VM lifecycle commands for fixed-bridge Apple Metal](phase-18-retire-vm-lifecycle-commands-for-fixed-bridge-apple-metal.md) | ✅ Done | 1.15 |
| 19 | [Remove Placeholder Top-Level CLI Groups](phase-19-remove-placeholder-top-level-cli-groups.md) | ✅ Done | 1.16 |
| 20 | [Typed Numeric CLI Parsing and Generated-Only Command Reference](phase-20-typed-numeric-cli-parsing-and-generated-only-command-referen.md) | ✅ Done | 1.17 |
| 21 | [Structured Subprocess Outcomes](phase-21-structured-subprocess-outcomes.md) | ✅ Done | 1.18 |
| 22 | [Stage-0 Bootstrap Gates and Delegation](phase-22-stage-0-bootstrap-gates-and-delegation.md) | ✅ Done | 2.1 |
| 23 | [Populated `prerequisiteRegistry` and Lazy Remediation](phase-23-populated-prerequisiteregistry-and-lazy-remediation.md) | ✅ Done | 2.2 |
| 24 | [JIT Cache Layout and Content Addressing](phase-24-jit-cache-layout-and-content-addressing.md) | ✅ Done | 2.3 |
| 25 | [Outer-Container Linux Builds and `jitml:local` Image](phase-25-outer-container-linux-builds-and-jitml-local-image.md) | ✅ Done | 2.4 |
| 26 | [Superseded Apple Silicon VM Scaffold](phase-26-superseded-apple-silicon-vm-scaffold.md) | ✅ Done | 2.5 |
| 27 | [Bootstrap Script Wrappers and Status](phase-27-bootstrap-script-wrappers-and-status.md) | ✅ Done | 2.6 |
| 28 | [Bootstrap `down` and `purge`](phase-28-bootstrap-down-and-purge.md) | ✅ Done | 2.7 |
| 29 | [Dhall Cluster-Resource Profile, Kind-Node Cap, and Host-RAM Preflight](phase-29-dhall-cluster-resource-profile-kind-node-cap-and-host-ram-pr.md) | ✅ Done | 2.8 |
| 30 | [Reconciler `sh -c` Control-Flow → Typed Haskell](phase-30-reconciler-sh-c-control-flow-typed-haskell.md) | ✅ Done | 2.9 |
| 31 | [Retire the Tart Prerequisite and `jitml internal vm` Commands](phase-31-retire-the-tart-prerequisite-and-jitml-internal-vm-commands.md) | ✅ Done | 2.10 |
| 32 | [Reinstate the Tart build-VM prerequisite and lifecycle](phase-32-reinstate-the-tart-build-vm-prerequisite-and-lifecycle.md) | ✅ Done | 2.11 |
| 33 | [Replace Tart prerequisites with fixed-bridge Apple cache prerequisites](phase-33-replace-tart-prerequisites-with-fixed-bridge-apple-cache-pre.md) | ✅ Done | 2.12 |
| 34 | [Authenticated third-party image pre-pull before `kind load`](phase-34-authenticated-third-party-image-pre-pull-before-kind-load.md) | ✅ Done | 2.13 |
| 35 | [In-cluster Docker Hub `imagePullSecret` (authenticated pod pulls)](phase-35-in-cluster-docker-hub-imagepullsecret-authenticated-pod-pull.md) | ✅ Done | 2.14 |
| 36 | [Durable-State Dhall DSL Foundation and `jitml project init`](phase-36-durable-state-dhall-dsl-foundation-and-jitml-project-init.md) | ✅ Done | 2.15 |
| 37 | [Per-Substrate Kind Configs and `extraMounts`](phase-37-per-substrate-kind-configs-and-extramounts.md) | ✅ Done | 3.1 |
| 38 | [`kubernetes.io/no-provisioner` Storage and Manual PVs](phase-38-kubernetes-io-no-provisioner-storage-and-manual-pvs.md) | ✅ Done | 3.2 |
| 39 | [Envoy Gateway and Single `127.0.0.1:<edge-port>` Listener](phase-39-envoy-gateway-and-single-127-0-0-1-edge-port-listener.md) | ✅ Done | 3.3 |
| 40 | [Typed Route Registry and Generated `HTTPRoute` Manifests](phase-40-typed-route-registry-and-generated-httproute-manifests.md) | ✅ Done | 3.4 |
| 41 | [Cluster Lifecycle Reconciler and Phased Deploy](phase-41-cluster-lifecycle-reconciler-and-phased-deploy.md) | ✅ Done | 3.5 |
| 42 | [Single-Worker Local Kind Node and Manual-PV Topology](phase-42-ha-kind-node-and-manual-pv-topology.md) | ✅ Done | 3.6 |
| 43 | [Live Cluster Lifecycle and Publication Truth](phase-43-live-cluster-lifecycle-and-publication-truth.md) | ✅ Done | 3.7 |
| 44 | [Harbor Subchart and Bootstrap-Phase Install](phase-44-harbor-subchart-and-bootstrap-phase-install.md) | ✅ Done | 4.1 |
| 45 | [Percona PG Operator and Patroni-Managed Service Postgres](phase-45-percona-pg-operator-and-patroni-managed-service-postgres.md) | ✅ Done | 4.2 |
| 46 | [MinIO Subchart, Bucket Provisioning, Conditional-Write Server](phase-46-minio-subchart-bucket-provisioning-conditional-write-server.md) | ✅ Done | 4.3 |
| 47 | [Apache Pulsar HA and Topic Bootstrap](phase-47-apache-pulsar-ha-and-topic-bootstrap.md) | ✅ Done | 4.4 |
| 48 | [kube-prometheus-stack and Provisioned Dashboards](phase-48-kube-prometheus-stack-and-provisioned-dashboards.md) | ✅ Done | 4.5 |
| 49 | [TensorBoard with MinIO Event Storage and Checkpoint Sidecar](phase-49-tensorboard-with-minio-event-storage-and-checkpoint-sidecar.md) | ✅ Done | 4.6 |
| 50 | [NVIDIA `RuntimeClass` for Linux CUDA](phase-50-nvidia-runtimeclass-for-linux-cuda.md) | ✅ Done | 4.7 |
| 51 | [Per-Pod Resource Limits and Right-Sized Replicas from the `dhall/cluster/` Profile](phase-51-per-pod-resource-limits-and-right-sized-replicas-from-the-dh.md) | ✅ Done | 4.8 |
| 52 | [Project the Durable-State `StoreRegistry` over MinIO Buckets](phase-52-project-the-durable-state-storeregistry-over-minio-buckets.md) | ✅ Done | 4.9 |
| 53 | [Single-Instance Local Platform Service Topology](phase-53-ha-platform-service-topology.md) | ✅ Done | 4.10 |
| 54 | [`jitml service` Entry Point and Lifecycle Summary](phase-54-jitml-service-entry-point-and-lifecycle-summary.md) | ✅ Done | 5.1 |
| 55 | [`BootConfig` / `LiveConfig` Dhall and Hot-Reload Schema Surface](phase-55-bootconfig-liveconfig-dhall-and-hot-reload-schema-surface.md) | ✅ Done | 5.2 |
| 56 | [`/healthz` / `/readyz` / `/metrics` and Structured Logging](phase-56-healthz-readyz-metrics-and-structured-logging.md) | ✅ Done | 5.3 |
| 57 | [`RetryPolicy` and Service Error Surface](phase-57-retrypolicy-and-service-error-surface.md) | ✅ Done | 5.4 |
| 58 | [At-Least-Once Pulsar Consumer with Message-Hash Deduplication](phase-58-at-least-once-pulsar-consumer-with-message-hash-deduplicatio.md) | ✅ Done | 5.5 |
| 59 | [Stateless `Deployment`, Pod Anti-Affinity, Per-Substrate Dhall](phase-59-stateless-deployment-pod-anti-affinity-per-substrate-dhall.md) | ✅ Done | 5.6 |
| 60 | [Typed Dhall `RunConfig` and BootConfig-Mounted Worker Dispatch](phase-60-typed-dhall-runconfig-and-bootconfig-mounted-worker-dispatch.md) | ✅ Done | 5.7 |
| 61 | [Retire Tart VM Lifecycle from the Daemon](phase-61-retire-tart-vm-lifecycle-from-the-daemon.md) | ✅ Done | 5.8 |
| 62 | [Reinstate the Dhall-configured build-VM block and daemon acquire](phase-62-reinstate-the-dhall-configured-build-vm-block-and-daemon-acq.md) | ✅ Done | 5.9 |
| 63 | [Replace daemon build-VM acquire with Metal bridge acquire](phase-63-replace-daemon-build-vm-acquire-with-metal-bridge-acquire.md) | ✅ Done | 5.10 |
| 64 | [Workload Placement Planner and Apple Host Workload Dispatch](phase-64-workload-placement-planner-and-apple-host-workload-dispatch.md) | ✅ Done | 5.11 |
| 65 | [Reflected Dhall Schema](phase-65-reflected-dhall-schema.md) | ✅ Done | 5.12 |
| 66 | [Coordinator Topic Algebra](phase-66-coordinator-topic-algebra.md) | ✅ Done | 5.13 |
| 67 | [One-Binary Engine / Coordinator / Webapp Role Model](phase-67-one-binary-engine-coordinator-webapp-role-model.md) | ✅ Done | 5.14 |
| 68 | [Reconcile the Pulsar Topic Family with the `StoreRegistry`](phase-68-reconcile-the-pulsar-topic-family-with-the-storeregistry.md) | ✅ Done | 5.15 |
| 69 | [One Numerical Worker per Kubernetes Node](phase-69-one-numerical-worker-per-kubernetes-node.md) | ✅ Done | 5.16 |
| 70 | [Fail-Closed Mounted Worker `RunConfig`](phase-70-fail-closed-mounted-worker-runconfig.md) | ✅ Done | 5.17 |
| 71 | [Receipt-Bound Delivery and Total Settlement](phase-71-receipt-bound-delivery-and-total-settlement.md) | ✅ Done | 5.18 |
| 72 | [Layer Catalog](phase-72-layer-catalog.md) | ✅ Done | 6.1 |
| 73 | [Activations (Real and Complex)](phase-73-activations-real-and-complex.md) | ✅ Done | 6.2 |
| 74 | [Spectral / Frequency-Domain Operations](phase-74-spectral-frequency-domain-operations.md) | ✅ Done | 6.3 |
| 75 | [Optimizers and Schedulers](phase-75-optimizers-and-schedulers.md) | ✅ Done | 6.4 |
| 76 | [Loss Functions](phase-76-loss-functions.md) | ✅ Done | 6.5 |
| 77 | [Dhall Schemas and Cross-Type Audit](phase-77-dhall-schemas-and-cross-type-audit.md) | ✅ Done | 6.6 |
| 78 | [`KernelSpec`, Cache Key Inputs, FFI Loader Surface](phase-78-kernelspec-cache-key-inputs-ffi-loader-surface.md) | ✅ Done | 7.1 |
| 79 | [Engine ABI and `Engines` Module Skeleton](phase-79-engine-abi-and-engines-module-skeleton.md) | ✅ Done | 7.2 |
| 80 | [Linux CPU Engine and oneDNN Codegen Driver](phase-80-linux-cpu-engine-and-onednn-codegen-driver.md) | ✅ Done | 7.3 |
| 81 | [Linux CUDA Engine and CUDA Codegen Driver](phase-81-linux-cuda-engine-and-cuda-codegen-driver.md) | ✅ Done | 7.4 |
| 82 | [Apple Silicon Engine, Metal Codegen, Host Forwarding Scaffolding](phase-82-apple-silicon-engine-metal-codegen-host-forwarding-scaffoldi.md) | ✅ Done | 7.5 |
| 83 | [Hardware Auto-Tuning Within the Determinism Contract](phase-83-hardware-auto-tuning-within-the-determinism-contract.md) | ✅ Done | 7.6 |
| 84 | [Haskell-Owned Runtime JIT Source Generation](phase-84-haskell-owned-runtime-jit-source-generation.md) | ✅ Done | 7.7 |
| 85 | [Headless Apple Metal JIT — Runtime Compilation + Host Swift Build](phase-85-headless-apple-metal-jit-runtime-compilation-host-swift-buil.md) | ✅ Done | 7.8 |
| 86 | [Compose GPU Service Split](phase-86-compose-gpu-service-split.md) | ✅ Done | 7.9 |
| 87 | [Route the Apple `swift build` through the Tart VM](phase-87-route-the-apple-swift-build-through-the-tart-vm.md) | ✅ Done | 7.10 |
| 88 | [Fixed host Metal bridge and source-metadata Apple cache](phase-88-fixed-host-metal-bridge-and-source-metadata-apple-cache.md) | ✅ Done | 7.11 |
| 89 | [Local Supervised Canonical Summaries](phase-89-local-supervised-canonical-summaries.md) | ✅ Done | 8.1 |
| 90 | [`jitml train` Local CLI Summary](phase-90-jitml-train-local-cli-summary.md) | ✅ Done | 8.2 |
| 91 | [RL Catalog Hook for Canonical Tests](phase-91-rl-catalog-hook-for-canonical-tests.md) | ✅ Done | 8.3 |
| 92 | [RL Metadata Primitives](phase-92-rl-metadata-primitives.md) | ✅ Done | 8.4 |
| 93 | [RL CLI Summaries and Report Hooks](phase-93-rl-cli-summaries-and-report-hooks.md) | ✅ Done | 8.5 |
| 94 | [RL Training Plan Surface](phase-94-rl-training-plan-surface.md) | ✅ Done | 8.6 |
| 95 | [`RLRunLifecycle` GADT Retrofit](phase-95-rlrunlifecycle-gadt-retrofit.md) | ✅ Done | 8.7 |
| 96 | [ALE Boundary and ROM Policy](phase-96-ale-boundary-and-rom-policy.md) | ✅ Done | 8.8 |
| 97 | [Copyright-Free Visual RL Demo Environment](phase-97-copyright-free-visual-rl-demo-environment.md) | ✅ Done | 8.9 |
| 98 | [SL Substrate-Backed Training + Real Eval](phase-98-sl-substrate-backed-training-real-eval.md) | ✅ Done | 8.10 |
| 99 | [RL Framework Substrate Routing](phase-99-rl-framework-substrate-routing.md) | ✅ Done | 8.11 |
| 100 | [No-Caveat SL/RL Framework Runtime](phase-100-no-caveat-sl-rl-framework-runtime.md) | ✅ Done | 8.12 |
| 101 | [Real SL Loss, Validation-Driven Selection, and Convergence+Performance Metrics](phase-101-real-sl-loss-validation-driven-selection-and-convergence-per.md) | ✅ Done | 8.13 |
| 102 | [Fixed-Budget Training Witness and Inference-Ineligible Partial Models](phase-102-fixed-budget-training-witness-and-inference-ineligible-parti.md) | ✅ Done | 8.14 |
| 103 | [Typed Fail-Closed RL Device Errors](phase-103-typed-fail-closed-rl-device-errors.md) | ✅ Done | 8.15 |
| 104 | [Validated `RunPlan` and Pure Contract Algebra](phase-104-validated-runplan-and-pure-contract-algebra.md) | ✅ Done | 8.16 |
| 105 | [On-Policy Algorithm Metadata](phase-105-on-policy-algorithm-metadata.md) | ✅ Done | 9.1 |
| 106 | [Off-Policy Algorithm Metadata](phase-106-off-policy-algorithm-metadata.md) | ✅ Done | 9.2 |
| 107 | [Specialised Algorithm Metadata](phase-107-specialised-algorithm-metadata.md) | ✅ Done | 9.3 |
| 108 | [Local RL Canonical Tests](phase-108-local-rl-canonical-tests.md) | ✅ Done | 9.4 |
| 109 | [AlphaZero Connect 4 Transcript Surface](phase-109-alphazero-connect-4-transcript-surface.md) | ✅ Done | 9.5 |
| 110 | [Connect 4 Local Game Surface](phase-110-connect-4-local-game-surface.md) | ✅ Done | 9.6 |
| 111 | [Hyperparameter Tuning (Sampler × Scheduler × Pruner)](phase-111-hyperparameter-tuning-sampler-scheduler-pruner.md) | ✅ Done | 9.7 |
| 112 | [Copyright-Free RL Matrix Retargeting](phase-112-copyright-free-rl-matrix-retargeting.md) | ✅ Done | 9.8 |
| 113 | [Real `rl eval` / `rollout` and Per-Algorithm On-Device Rollouts](phase-113-real-rl-eval-rollout-and-per-algorithm-on-device-rollouts.md) | ✅ Done | 9.9 |
| 114 | [Real MCTS Tree Search with Substrate-Backed Leaf Evaluation](phase-114-real-mcts-tree-search-with-substrate-backed-leaf-evaluation.md) | ✅ Done | 9.10 |
| 115 | [Real Hyperparameter Tuning Objective Executor](phase-115-real-hyperparameter-tuning-objective-executor.md) | ✅ Done | 9.11 |
| 116 | [No-Caveat RL, AlphaZero, and Tuning Runtime](phase-116-no-caveat-rl-alphazero-and-tuning-runtime.md) | ✅ Done | 9.12 |
| 117 | [Real RL Convergence + Performance Metrics and the AlphaZero Arena-Win-Rate Form](phase-117-real-rl-convergence-performance-metrics-and-the-alphazero-ar.md) | ✅ Done | 9.13 |
| 118 | [All-RL Fixed-Budget Convergence Metrics](phase-118-all-rl-fixed-budget-convergence-metrics.md) | ✅ Done | 9.14 |
| 119 | [Typed Tuning Resume Decode Failures](phase-119-typed-tuning-resume-decode-failures.md) | ✅ Done | 9.15 |
| 120 | [Tuning Override and Worker Axis Fidelity](phase-120-tuning-override-and-worker-axis-fidelity.md) | ✅ Done | 9.16 |
| 121 | [Resolved AlphaZero and Tuning Plans](phase-121-resolved-alphazero-and-tuning-plans.md) | ✅ Done | 9.17 |
| 122 | [Storage Layout and Split-Blob Schema](phase-122-storage-layout-and-split-blob-schema.md) | ✅ Done | 10.1 |
| 123 | [`.jmw1` Wire Format and Manifest CBOR](phase-123-jmw1-wire-format-and-manifest-cbor.md) | ✅ Done | 10.2 |
| 124 | [Bit-Determinism Contract and Retention Reconciler](phase-124-bit-determinism-contract-and-retention-reconciler.md) | ✅ Done | 10.3 |
| 125 | [Inference-Only Read Path](phase-125-inference-only-read-path.md) | ✅ Done | 10.4 |
| 126 | [Remove the Synthetic Inference Offset](phase-126-remove-the-synthetic-inference-offset.md) | ✅ Done | 10.5 |
| 127 | [Exact V2 Supervised Runtime Artifact](phase-127-exact-v2-supervised-runtime-artifact.md) | ✅ Done | 10.6 |
| 128 | [Async `Work*` Inference Workflow and `.ready` Readiness Gate](phase-128-async-work-inference-workflow-and-ready-readiness-gate.md) | ✅ Done | 10.7 |
| 129 | [Typed `RetentionPolicy` Replaces the `LastN 5` Literal](phase-129-typed-retentionpolicy-replaces-the-lastn-5-literal.md) | ✅ Done | 10.8 |
| 130 | [Real Trained Demo Checkpoints (Delete the Synthetic Weight Ramp)](phase-130-real-trained-demo-checkpoints-delete-the-synthetic-weight-ra.md) | ✅ Done | 10.9 |
| 131 | [Inference-Eligible Checkpoints and Convergence Statistics](phase-131-inference-eligible-checkpoints-and-convergence-statistics.md) | ✅ Done | 10.10 |
| 132 | [Typed Checkpoint Object-Key Validation](phase-132-typed-checkpoint-object-key-validation.md) | ✅ Done | 10.11 |
| 133 | [Persisted Checkpoint Proof Admission](phase-133-persisted-checkpoint-proof-admission.md) | ✅ Done | 10.12 |
| 134 | [Minimal PureScript Application Scaffold](phase-134-minimal-purescript-application-scaffold.md) | ✅ Done | 11.1 |
| 135 | [Browser-Contract ADTs and Local Contract Rendering](phase-135-browser-contract-adts-and-local-contract-rendering.md) | ✅ Done | 11.2 |
| 136 | [`jitml lint purescript` Generated-Contract Smoke Target](phase-136-jitml-lint-purescript-generated-contract-smoke-target.md) | ✅ Done | 11.3 |
| 137 | [Interactive Endpoint Contract Surface](phase-137-interactive-endpoint-contract-surface.md) | ✅ Done | 11.4 |
| 138 | [Webapp Route and Deployment Surface](phase-138-webapp-route-and-deployment-surface.md) | ✅ Done | 11.5 |
| 139 | [Playwright E2E Suite](phase-139-playwright-e2e-suite.md) | ✅ Done | 11.6 |
| 140 | [SPA Portals Home and Shared Header](phase-140-spa-portals-home-and-shared-header.md) | ✅ Done | 11.7 |
| 141 | [Demo Endpoints Render Real Substrate Output](phase-141-demo-endpoints-render-real-substrate-output.md) | ✅ Done | 11.8 |
| 142 | [Full Interactive Demo Surface](phase-142-full-interactive-demo-surface.md) | ✅ Done | 11.9 |
| 143 | [Webapp Role and Websocket-Driven Inference Panels](phase-143-webapp-role-and-websocket-driven-inference-panels.md) | ✅ Done | 11.10 |
| 144 | [All-Model Trained-Artifact UI and Admin Navigation](phase-144-all-model-trained-artifact-ui-and-admin-navigation.md) | ✅ Done | 11.11 |
| 145 | [`jitml-unit` Stanza](phase-145-jitml-unit-stanza.md) | ✅ Done | 12.1 |
| 146 | [`jitml-integration` Stanza (Subprocess Boundary + Determinism)](phase-146-jitml-integration-stanza-subprocess-boundary-determinism.md) | ✅ Done | 12.2 |
| 147 | [`jitml-sl-canonicals` Stanza](phase-147-jitml-sl-canonicals-stanza.md) | ✅ Done | 12.3 |
| 148 | [`jitml-rl-canonicals` Stanza](phase-148-jitml-rl-canonicals-stanza.md) | ✅ Done | 12.4 |
| 149 | [`jitml-hyperparameter` Stanza](phase-149-jitml-hyperparameter-stanza.md) | ✅ Done | 12.5 |
| 150 | [`jitml-cross-backend` Stanza](phase-150-jitml-cross-backend-stanza.md) | ✅ Done | 12.6 |
| 151 | [`jitml-daemon-lifecycle` Stanza](phase-151-jitml-daemon-lifecycle-stanza.md) | ✅ Done | 12.7 |
| 152 | [`jitml-e2e` Stanza and Live-Plan Orchestrator](phase-152-jitml-e2e-stanza-and-live-plan-orchestrator.md) | ✅ Done | 12.8 |
| 153 | [`jitml test all` Orchestrator and Report Card](phase-153-jitml-test-all-orchestrator-and-report-card.md) | ✅ Done | 12.9 |
| 154 | [Substrate-partitioned test lanes; remove the cross-substrate parity test surface](phase-154-substrate-partitioned-test-lanes-remove-the-cross-substrate.md) | ✅ Done | 12.10 |
| 155 | [DRY Real-Workflow Matrix, Fail-Closed](phase-155-dry-real-workflow-matrix-fail-closed.md) | ✅ Done | 12.11 |
| 156 | [Live Job Failure Observation and Apple Placement Assertions](phase-156-live-job-failure-observation-and-apple-placement-assertions.md) | ✅ Done | 12.12 |
| 157 | [Playwright No-Caveat E2E Matrix](phase-157-playwright-no-caveat-e2e-matrix.md) | ✅ Done | 12.13 |
| 158 | [Common-Shape Workflow, Topic-Algebra, and Websocket Coverage](phase-158-common-shape-workflow-topic-algebra-and-websocket-coverage.md) | ✅ Done | 12.14 |
| 159 | [Per-Model Integration and E2E Matrix](phase-159-per-model-integration-and-e2e-matrix.md) | ✅ Done | 12.15 |
| 160 | [Functional-Core Live Workflow Interpreter](phase-160-functional-core-live-workflow-interpreter.md) | ✅ Done | 12.16 |
| 161 | [Full Canonical Model Matrix Runtime](phase-161-full-canonical-model-matrix-runtime.md) | ✅ Done | 13.1 |
| 162 | [Re-Attest the No-Caveat Runtime with Real Losses + Metrics](phase-162-re-attest-the-no-caveat-runtime-with-real-losses-metrics.md) | ✅ Done | 13.2 |
| 163 | [Fixed-Budget All-Model Runtime Gate (`linux-cpu`)](phase-163-fixed-budget-all-model-runtime-gate-linux-cpu.md) | ✅ Done | 13.3 |
| 164 | [Full Workflow Control Surface](phase-164-full-workflow-control-surface.md) | ✅ Done | 14.1 |
| 165 | [Playwright No-Caveat Product Matrix](phase-165-playwright-no-caveat-product-matrix.md) | ✅ Done | 14.2 |
| 166 | [Real Demo Inference — Full-Width Multi-Layer Forward, Real Input, All Families](phase-166-real-demo-inference-full-width-multi-layer-forward-real-inpu.md) | ✅ Done | 14.3 |
| 167 | [All-Model Browser and Playwright Trained-Artifact Matrix](phase-167-all-model-browser-and-playwright-trained-artifact-matrix.md) | ✅ Done | 14.4 |
| 168 | [Ephemeral Kind + Helm Rollout](phase-168-ephemeral-kind-helm-rollout.md) | ✅ Done | 15.1 |
| 169 | [Live Capability Class Validation (MinIO + Pulsar + Harbor)](phase-169-live-capability-class-validation-minio-pulsar-harbor.md) | ✅ Done | 15.2 |
| 170 | [Daemon Training/RL/Tune Handlers on Live Broker](phase-170-daemon-training-rl-tune-handlers-on-live-broker.md) | ✅ Done | 15.3 |
| 171 | [Live SL Training E2E with Real Datasets](phase-171-live-sl-training-e2e-with-real-datasets.md) | ✅ Done | 15.4 |
| 172 | [Real RL Environment Simulators and Daemon Env Loop](phase-172-real-rl-environment-simulators-and-daemon-env-loop.md) | ✅ Done | 15.5 |
| 173 | [Live RL Training E2E with Statistical Convergence Assertions](phase-173-live-rl-training-e2e-with-statistical-convergence-assertions.md) | ✅ Done | 15.6 |
| 174 | [Live MinIO Checkpoint Round-Trip and Retention](phase-174-live-minio-checkpoint-round-trip-and-retention.md) | ✅ Done | 15.7 |
| 175 | [Real CUDA RL Algorithm Losses Through JIT Engine](phase-175-real-cuda-rl-algorithm-losses-through-jit-engine.md) | ✅ Done | 15.8 |
| 176 | [AlphaZero with Real Network Priors](phase-176-alphazero-with-real-network-priors.md) | ✅ Done | 15.9 |
| 177 | [Live Tuning Sweep with MinIO Trial Persistence](phase-177-live-tuning-sweep-with-minio-trial-persistence.md) | ✅ Done | 15.10 |
| 178 | [CUDA and Linux CPU Production Weight Loading](phase-178-cuda-and-linux-cpu-production-weight-loading.md) | ✅ Done | 15.11 |
| 179 | [Live `jitml inference run` and Legacy Replay Helper](phase-179-live-jitml-inference-run-and-legacy-replay-helper.md) | ✅ Done | 15.12 |
| 180 | [Live `/api/ws` WebSocket Proxy and Compiled Halogen Bundle](phase-180-live-api-ws-websocket-proxy-and-compiled-halogen-bundle.md) | ✅ Done | 15.13 |
| 181 | [Live Playwright on Demo Edge Route](phase-181-live-playwright-on-demo-edge-route.md) | ✅ Done | 15.14 |
| 182 | [Linux CPU Full-Tensor Benchmark Payloads and First-Cache-Miss Live Execution](phase-182-linux-cpu-full-tensor-benchmark-payloads-and-first-cache-mis.md) | ✅ Done | 15.15 |
| 183 | [Re-validate the linux-cuda lane runs for real with the skip guards removed](phase-183-re-validate-the-linux-cuda-lane-runs-for-real-with-the-skip.md) | ✅ Done | 15.16 |
| 184 | [Live linux-cpu Exercise of the Reopened Workflows](phase-184-live-linux-cpu-exercise-of-the-reopened-workflows.md) | ✅ Done | 15.17 |
| 185 | [Live linux-cuda Exercise of the Reopened Workflows](phase-185-live-linux-cuda-exercise-of-the-reopened-workflows.md) | ✅ Done | 15.18 |
| 186 | [Live Cluster Closure of the Reopened Workflows](phase-186-live-cluster-closure-of-the-reopened-workflows.md) | ✅ Done | 15.19 |
| 187 | [Linux No-Caveat Runtime and Browser Lane](phase-187-linux-no-caveat-runtime-and-browser-lane.md) | ✅ Done | 15.20 |
| 188 | [Linux-CUDA All-Model Trained-Artifact Lane](phase-188-linux-cuda-all-model-trained-artifact-lane.md) | ✅ Done | 15.21 |
| 189 | [Linux-CUDA HA Cluster Revalidation](phase-189-linux-cuda-ha-cluster-revalidation.md) | ✅ Done | 15.22 |
| 190 | [Host Swift Toolchain and First-Cache-Miss Headless Build](phase-190-host-swift-toolchain-and-first-cache-miss-headless-build.md) | ✅ Done | 16.1 |
| 191 | [Metal FFI Loading and Host Kernel Launch](phase-191-metal-ffi-loading-and-host-kernel-launch.md) | ✅ Done | 16.2 |
| 192 | [Metal Benchmark Candidate Runner Live Execution](phase-192-metal-benchmark-candidate-runner-live-execution.md) | ✅ Done | 16.3 |
| 193 | [Apple Host↔Cluster Pulsar RPC Live Flow](phase-193-apple-host-cluster-pulsar-rpc-live-flow.md) | ✅ Done | 16.4 |
| 194 | [Apple Metal Production Weight Loading](phase-194-apple-metal-production-weight-loading.md) | ✅ Done | 16.5 |
| 195 | [Re-validate the apple-silicon lane runs for real with the skip guards removed](phase-195-re-validate-the-apple-silicon-lane-runs-for-real-with-the-sk.md) | ✅ Done | 16.6 |
| 196 | [Re-validate the apple-silicon lane through the Tart-VM-built path](phase-196-re-validate-the-apple-silicon-lane-through-the-tart-vm-built.md) | ✅ Done | 16.7 |
| 197 | [Retired VM-path apple-silicon Workflow Attempt](phase-197-retired-vm-path-apple-silicon-workflow-attempt.md) | ✅ Done | 16.8 |
| 198 | [Live fixed-bridge apple-silicon workflow closure](phase-198-live-fixed-bridge-apple-silicon-workflow-closure.md) | ✅ Done | 16.9 |
| 199 | [Live Apple Host-Resident Workload Closure](phase-199-live-apple-host-resident-workload-closure.md) | ✅ Done | 16.10 |
| 200 | [Apple No-Caveat Runtime and Browser Lane](phase-200-apple-no-caveat-runtime-and-browser-lane.md) | ✅ Done | 16.11 |
| 201 | [Apple-Silicon All-Model Trained-Artifact Lane](phase-201-apple-silicon-all-model-trained-artifact-lane.md) | ✅ Done | 16.13 |
| 202 | [Apple-Silicon HA Cluster Revalidation](phase-202-apple-silicon-ha-cluster-revalidation.md) | ✅ Done | 16.14 |
| 203 | [Cross-Substrate Cohort Runs and In-Code Tolerance Bands](phase-203-cross-substrate-cohort-runs-and-in-code-tolerance-bands.md) | ✅ Done | 17.1 |
| 204 | [Live `jitml test all` Report Card with Measured Metrics](phase-204-live-jitml-test-all-report-card-with-measured-metrics.md) | ✅ Done | 17.2 |
| 205 | [Empty Legacy Ledger and Final Handoff](phase-205-empty-legacy-ledger-and-final-handoff.md) | ✅ Done | 17.3 |
| 206 | [Remove the cross-substrate parity surface; reframe the determinism contract to within-substrate-only](phase-206-remove-the-cross-substrate-parity-surface-reframe-the-determ.md) | ✅ Done | 17.4 |
| 207 | [Cross-Substrate Real-Workflow Confirmation](phase-207-cross-substrate-real-workflow-confirmation.md) | ✅ Done | 17.5 |
| 208 | [Real-Workflow Ledger Walk-Down and Final Handoff](phase-208-real-workflow-ledger-walk-down-and-final-handoff.md) | ✅ Done | 17.6 |
| 209 | [Apple Placement Ledger Walk-Down and Final Handoff](phase-209-apple-placement-ledger-walk-down-and-final-handoff.md) | ✅ Done | 17.7 |
| 210 | [Expanded No-Caveat Report Card and Ledger Handoff](phase-210-expanded-no-caveat-report-card-and-ledger-handoff.md) | ✅ Done | 17.8 |
| 211 | [Expanded All-Model Lane Fragment Handoff](phase-211-expanded-all-model-lane-fragment-handoff.md) | ✅ Done | 17.9 |
| 212 | [HA Topology Aggregation](phase-212-ha-topology-aggregation.md) | ✅ Done | 17.10 |
| 213 | [Three-Substrate No-Caveat Handoff](phase-213-three-substrate-no-caveat-handoff.md) | ✅ Done | 18.1 |
| 214 | [Re-Aggregate the No-Caveat Handoff after the Durable-State DSL](phase-214-re-aggregate-the-no-caveat-handoff-after-the-durable-state-d.md) | ✅ Done | 18.2 |
| 215 | [Re-Aggregate the No-Caveat Handoff after the Real-SL/RL Chain](phase-215-re-aggregate-the-no-caveat-handoff-after-the-real-sl-rl-chai.md) | ✅ Done | 18.3 |
| 216 | [Re-Aggregate after Fixed-Budget All-Model Closure](phase-216-re-aggregate-after-fixed-budget-all-model-closure.md) | ✅ Done | 18.4 |
| 217 | [HA Topology Product Handoff](phase-217-ha-topology-product-handoff.md) | ✅ Done | 18.5 |
| 218 | [Re-Aggregate after Typed-Failure and Docs-Governance Remediation](phase-218-re-aggregate-after-typed-failure-and-docs-governance-remedia.md) | ✅ Done | 18.6 |
| 219 | [Re-Aggregate after Real Cluster/Tuning/RunConfig Remediation](phase-219-re-aggregate-after-real-cluster-tuning-runconfig-remediation.md) | ✅ Done | 18.7 |
| 220 | [Product Matrix Authority](phase-220-product-matrix-authority.md) | ✅ Done | 19.1 |
| 221 | [Phase Status Registry](phase-221-phase-status-registry.md) | ✅ Done | 19.2 |
| 222 | [Status Truth Enforcement](phase-222-status-truth-enforcement.md) | ✅ Done | 19.3 |
| 223 | [Product Registry Plan and Admitted Evidence Projection](phase-223-product-registry-plan-and-admitted-evidence-projection.md) | ✅ Done | 19.4 |
| 224 | [Remove Fossils](phase-224-remove-fossils.md) | ✅ Done | 20.1 |
| 225 | [Scaffold Lint + Reachability](phase-225-scaffold-lint-reachability.md) | ✅ Done | 20.2 |
| 226 | [Non-Fabricable Training Evidence](phase-226-non-fabricable-training-evidence.md) | ✅ Done | 21.1 |
| 227 | [Type-State Pipeline (Haskell)](phase-227-type-state-pipeline-haskell.md) | ✅ Done | 21.2 |
| 228 | [Dhall Boundary & Fail-Closed Decode](phase-228-dhall-boundary-fail-closed-decode.md) | ✅ Done | 21.3 |
| 229 | [Phase-Specific Product Evidence Payloads](phase-229-phase-specific-product-evidence-payloads.md) | ✅ Done | 21.4 |
| 230 | [Matrix Parity](phase-230-matrix-parity.md) | ✅ Done | 22.1 |
| 231 | [Per-Row Runnable Dhall](phase-231-per-row-runnable-dhall.md) | ✅ Done | 22.2 |
| 232 | [Read-Time Dataset SHA](phase-232-read-time-dataset-sha.md) | ✅ Done | 22.3 |
| 233 | [Typed Layer IR + Reverse-Mode Autodiff](phase-233-typed-layer-ir-reverse-mode-autodiff.md) | ✅ Done | 23.1 |
| 234 | [oneDNN Layer Kernels for Training](phase-234-onednn-layer-kernels-for-training.md) | ✅ Done | 23.2 |
| 235 | [One Self-Describing Checkpoint Envelope](phase-235-one-self-describing-checkpoint-envelope.md) | ✅ Done | 23.3 |
| 236 | [Checkpoint Admission Single-Path](phase-236-checkpoint-admission-single-path.md) | ✅ Done | — |
| 237 | [Supervised Serving on the Layer-Graph IR](phase-237-supervised-serving-on-the-layer-graph-ir.md) | ✅ Done | — |
| 238 | [Supervised Training on the Layer-Graph IR](phase-238-supervised-training-on-the-layer-graph-ir.md) | ✅ Done | — |
| 239 | [Checkpoint Construction from the Trained Graph](phase-239-checkpoint-construction-from-the-trained-graph.md) | ✅ Done | — |
| 240 | [Layer-Graph Checkpoints + Inference](phase-240-layer-graph-checkpoints-inference.md) | ✅ Done | 23.4 |
| 241 | [oneDNN Device Training Kernels for Correct Operators](phase-241-onednn-device-training-kernels-for-correct-operators.md) | ✅ Done | new 2026-07-28 |
| 242 | [Literal Architectures - Dense, MLP, LeNet](phase-242-literal-architectures-dense-mlp-lenet.md) | ✅ Done | 24.1 |
| 243 | [Literal Architectures - ResNet Family](phase-243-literal-architectures-resnet-family.md) | ✅ Done | 24.2 |
| 244 | [Literal Architectures - Vision Transformer](phase-244-literal-architectures-vision-transformer.md) | ✅ Done | 24.3 |
| 245 | [Convergence and Evidence](phase-245-convergence-and-evidence.md) | ✅ Done | 24.4 |
| 246 | [CompletedTraining SL Manifests](phase-246-completedtraining-sl-manifests.md) | ✅ Done | 24.5 |
| 247 | [Real Environments](phase-247-real-environments.md) | ✅ Done | 25.1 |
| 248 | [Distinct Algorithms](phase-248-distinct-algorithms.md) | ✅ Done | 25.2 |
| 249 | [Per-Row Convergence and Evidence](phase-249-per-row-convergence-and-evidence.md) | ✅ Done | 25.3 |
| 250 | [Typed RL Cohort and Action-Domain Compatibility](phase-250-typed-rl-cohort-and-action-domain-compatibility.md) | ✅ Done | 25.4 |
| 251 | [TrainingPlan/EvaluationPlan Compiler and Trainer Migration](phase-251-trainingplan-evaluationplan-compiler-and-trainer-migration.md) | ✅ Done | 25.5 |
| 252 | [Typed Measured Counters and Evidence Separation](phase-252-typed-measured-counters-and-evidence-separation.md) | ✅ Done | 25.6 |
| 253 | [Per-Game Self-Play](phase-253-per-game-self-play.md) | ✅ Done | 26.1 |
| 254 | [Arena Convergence + Evidence](phase-254-arena-convergence-evidence.md) | ✅ Done | 26.2 |
| 255 | [Train-and-Publish + Artifact Selectors](phase-255-train-and-publish-artifact-selectors.md) | ✅ Done | 27.1 |
| 256 | [Row-Specific Renderers](phase-256-row-specific-renderers.md) | ✅ Done | 27.2 |
| 257 | [Browser Fail-Closed](phase-257-browser-fail-closed.md) | ✅ Done | 27.3 |
| 258 | [Row-Keyed Integration Matrix](phase-258-row-keyed-integration-matrix.md) | ✅ Done | 28.1 |
| 259 | [Row-Complete Playwright](phase-259-row-complete-playwright.md) | ✅ Done | 28.2 |
| 260 | [linux-cpu Report Card](phase-260-linux-cpu-report-card.md) | ✅ Done | 28.3 |
| 261 | [Contract-Driven Live Execution - Integration Journal](phase-261-contract-driven-live-execution-integration-journal.md) | ✅ Done | 28.4 |
| 262 | [Contract-Driven Live Execution - Browser and Playwright](phase-262-contract-driven-live-execution-browser-and-playwright.md) | ✅ Done | 28.5 |
| 263 | [Contract-Driven Live Execution - Fragment Issuance](phase-263-contract-driven-live-execution-fragment-issuance.md) | ✅ Done | 28.6 |
| 264 | [Real cuDNN/cuBLAS Kernels](phase-264-real-cudnn-cublas-kernels.md) | ✅ Done | 29.1 |
| 265 | [CUDA Row Device Evidence](phase-265-cuda-row-device-evidence.md) | ✅ Done | 29.2 |
| 266 | [CUDA Integration, E2E, and Attestation](phase-266-cuda-integration-e2e-and-attestation.md) | ✅ Done | 29.3 |
| 267 | [GPU Performance and Persistent Device Buffers](phase-267-gpu-performance-and-persistent-device-buffers.md) | ✅ Done | 29.4 |
| 268 | [Contract-Driven CUDA Lane Revalidation](phase-268-contract-driven-cuda-lane-revalidation.md) | ✅ Done | 29.5 |
| 269 | [Registry:2 Migration and Harbor Deprecation](phase-269-registry2-migration-and-harbor-deprecation.md) | ✅ Done | new |
| 270 | [Real Metal Kernels](phase-270-real-metal-kernels.md) | ✅ Done | 30.1 |
| 271 | [Metal Row Device Evidence](phase-271-metal-row-device-evidence.md) | ✅ Done | 30.2 |
| 272 | [Apple Integration, E2E, and Attestation](phase-272-apple-integration-e2e-and-attestation.md) | ✅ Done | 30.3 |
| 273 | [Contract-Driven Apple Lane Revalidation](phase-273-contract-driven-apple-lane-revalidation.md) | ✅ Done | 30.4 |
| 274 | [Attestation Join](phase-274-attestation-join.md) | ✅ Done | 31.1 |
| 275 | [No-Caveat Closure Guard](phase-275-no-caveat-closure-guard.md) | ✅ Done | 31.2 |
| 276 | [Journal-Derived Product Aggregation](phase-276-journal-derived-product-aggregation.md) | ✅ Done | 31.3 |
| 277 | [Negative-Control Suite](phase-277-negative-control-suite.md) | ✅ Done | 32.1 |
| 278 | [External Bars, No-Self-Referential-Gate Lint, and Exact Served-Byte Provenance](phase-278-external-bars-no-self-referential-gate-lint-and-exact-served.md) | 🔄 Active | 32.2 |
| 279 | [Measured/Declared Type Split & Behavioral Scaffold Lint](phase-279-measured-declared-type-split-behavioral-scaffold-lint.md) | ⏸️ Blocked | 32.3 |
| 280 | [RunContract Negative Controls - Request and Event Fixtures](phase-280-runcontract-negative-controls-request-and-event-fixtures.md) | ⏸️ Blocked | 32.4 |
| 281 | [RunContract Negative Controls - Journal Fixtures and Reducer Properties](phase-281-runcontract-negative-controls-journal-fixtures-and-reducer-p.md) | ⏸️ Blocked | 32.5 |
| 282 | [RunContract Negative Controls - Lifecycle and Per-Row Registration](phase-282-runcontract-negative-controls-lifecycle-and-per-row-registra.md) | ⏸️ Blocked | 32.6 |
| 283 | [Per-Model Measured Convergence](phase-283-per-model-measured-convergence.md) | ✅ Done | 33.1 |
| 284 | [Inference-Performance & Determinism](phase-284-inference-performance-determinism.md) | ✅ Done | 33.2 |
| 285 | [Contract-Driven Per-Model Evidence](phase-285-contract-driven-per-model-evidence.md) | ⏸️ Blocked | 33.3 |
| 286 | [Evidence-Derived Closure Guard](phase-286-evidence-derived-closure-guard.md) | ✅ Done | 34.1 |
| 287 | [Standing Adversarial Audit & Thin Plan](phase-287-standing-adversarial-audit-thin-plan.md) | ✅ Done | 34.2 |
| 288 | [Journal-Derived Status Registry](phase-288-journal-derived-status-registry.md) | ⏸️ Blocked | 34.3 |
| 289 | [Evidence-Typed Report Measurements](phase-289-evidence-typed-report-measurements.md) | ⏸️ Blocked | 34.4 |

The 2026-07-18 checkpoint/runtime audit added sprint-level dependencies without
renumbering phases. After Sprints `10.6` and `10.12` closed, its then-open
suffix was:
`262 → 263 → 268 → 273 → 276 → 278 → 280 → 281 → 282 → 285 → 288 → 289`.
This is an ownership-chain overlay on the phase DAG: later phases that are not
named remain Done on their retained surfaces. Sprints `1.18`, `2.9`, `3.7`,
`5.18`, `8.16`, `9.17`, `10.6`, `10.12`, and `12.16` are closed. Phases
`235`–`246`, `250`, `251`, `252`, and `261` are closed `Done`; Phase `262` was
Active at that checkpoint.

The 2026-08-09 correlated request/reply audit adds two ownership transfers to
that overlay under rule `M(a)`, and no dependency edges. Phase `71` retains the
receipt-bound delivery and total-settlement contract it validated, and transfers
the **establishment** half — proving a reply cursor exists before a correlated
request is published — forward to Phase `262`, which owns the opaque
`ReplyCursor` and the Pulsar admin subscription CREATE that mints it. Phase
`160` retains the `NOINLINE`-isolated reply supervisor and transfers that
supervisor's readiness gate, which used the diagnostic `ConsumerSessionConnected`
event as proof of receivability; the same phase's note records that Phase `262`
raised the compiler heap cap the `160` narrative had preserved. Neither phase
reopens.

The 2026-08-11 fragment-issuance landing adds one further ownership transfer to
that overlay under rule `M(a)`, and no dependency edges. Phase `263` retains the
journal-derived `linux-cpu` lane-fragment issuance it validated, and transfers
the harness half of the readiness contract — publishing a correlated request
through an established reply cursor instead of the diagnostic
`ConsumerSessionConnected` event — forward to Phase `282`, which owns run
lifecycle coverage. Phase `262` already retired that shape on the production
inference client; the residue is the `JitML.Test.LiveWorkflow` publish gate and
two live integration observers, whose replacement is a transport redesign rather
than a deletion. Neither phase reopens.

The 2026-08-09 local-resource correction reopened and reclosed Phases `42`,
`53`, and `69`. The complete current chain is
`278 → 279 → 280 → 281 → 282 → 285 → 288 → 289`.
The Phase `19`–`34` product-sprint checkpoint is
**62 Done / 1 Active / 0 Planned / 7 Blocked**, counted from the 70-entry typed
registry. Phase `261` re-closed with the retained typed CPU journal, and Phase
`268` closed on 2026-09-12 with the retained typed CUDA journal after its real
RTX 5090 lifecycle passed **10 / 10** stanzas, the live browser gate, and the
every-row wall-clock comparison. Phase `273` re-closed on 2026-09-17 after
its real Apple lifecycle and retained journal admission. Phase `276` then
closed the CPU-only join of all three journals under rule `M(d)`; Phase `278`
is the first open owner. Phase `279` reopens Blocked under rule `C`: its
behavioral output-dependence detector is still a finite name scanner. Existing
opaque completion/type protections remain; no later feature work starts before
Phase `278` validates. Prior Sprint `10.12` validation and pre-V2 publisher results remain
historical evidence only.

## Status Vocabulary

| Status | Meaning | Emoji |
|--------|---------|-------|
| **Done** | Every Exit-Definition obligation the sprint owns is met in the worktree, validated by the sprint's `### Validation` commands, and the listed docs are aligned. A sprint whose entire obligation is documentation, typed scaffolding, schema/ADT, generated-section, or pure-Haskell catalog work is legitimately Done when that surface is in place and tested; a sprint whose obligation includes live runtime behaviour (cluster up, Helm apply, Pulsar subscribe, MinIO put, kernel compile-and-execute, browser interaction, etc.) is Done only after that live behaviour is exercised through the sprint's validation. | ✅ |
| **Active** | Work has started and at least one owned Exit-Definition obligation is unmet. The sprint body lists those gaps in an explicit `### Remaining Work` block. | 🔄 |
| **Planned** | All upstream sprint dependencies are Done. The sprint has not yet started. It must list no unmet blockers. | 📋 |
| **Blocked** | At least one upstream sprint or external prerequisite required for this sprint's owned obligations is not Done. The sprint body lists the blockers in a `**Blocked by**:` line. | ⏸️ |

See [development_plan_standards.md → C. Honest Completion Tracking](development_plan_standards.md#c-honest-completion-tracking)
for the governing rule.

## Historical Baseline Record

The current status lives only in
[README.md → Closure Status](README.md#closure-status). The dated records below
preserve evidence from earlier baselines without asserting current closure.

Historical status from 2026-06-30: the follow-up audit reopened that baseline
for live cluster lifecycle truth, fail-closed mounted worker `RunConfig.dhall`
decoding, tuning CLI override fidelity, and daemon tuning worker-axis fidelity.
Sprints `3.7`, `5.17`, and `9.16` closed those gaps, and Phase `18` Sprint
`18.7` re-aggregated the historical handoff with **8 / 8** stanzas and
`browser_product_matrix` **8 / 8** at edge `:9091`.

Historical status from earlier on 2026-06-30: all Phases `0`–`18` were Done
again after Phases `0`, `1`, `8`, `9`, and `10` re-closed docs-check metadata
enforcement, typed numeric CLI parsing, typed RL device failures, typed tuning
resume decode failures, and typed local checkpoint object-key validation. Phase
`18` Sprint `18.6` re-aggregated those fixes on `linux-cpu`: `jitml test all
--live --linux-cpu` passed **8 / 8** stanzas with populated report-card
measurements and `browser_product_matrix` **8 / 8** at edge `:9091`.

The 2026-06-29 HA closure remains historical evidence for the HA topology:
Phases `3`, `4`, `5`, `15`, `16`, `17`, and `18` closed the HA topology and
product handoff before this audit reopened real cluster/tuning/runtime-config
work. The 2026-06-26 all-Done closure below remains historical evidence for the
compact local topology and fixed-budget model contract.

**Historical status (2026-06-26): all Phases `0`–`18` were Done for the compact
topology.** Phases `8`–`14` were Done for the fixed-budget all-model
trained-artifact contract. Validation included `jitml test all --live
--linux-cpu` **8 / 8**, live Playwright **15 / 15**, `docker compose build
jitml` with embedded `check-code: ok`, `jitml lint purescript`, and `jitml docs
check`. Phase `15` Sprint `15.21` passed the real `linux-cuda` gate on the RTX
5090 host: live rollout 110 steps, `jitml test all --linux-cuda` **8 / 8**,
`jitml-backends` **20 / 20**, eight demo checkpoints seeded, and live Playwright
**15 / 15** at edge `:9092`. Phase `16` Sprint `16.13` passed the real
`apple-silicon` gate: live rollout 109 steps, host Metal daemon subscriptions
acquired, `bootstrap/apple-silicon.sh test` **8 / 8**, and live Playwright
**15 / 15**. Phase `17` Sprint `17.9` aggregated the lane fragments on
`linux-cpu`; Phase `18` Sprint `18.4` ran the final `linux-cpu` handoff gates
with `jitml test all --live --linux-cpu` **8 / 8**, populated report-card
measurements, `browser_product_matrix` **8 / 8** at edge `:9091`,
`check-code: ok`, and `docs check: ok`. The dated reopen/re-close narrative
below is retained as historical record only.

**Reopened + re-closed (2026-06-20 — authenticated third-party image pre-pull).**
Phase `2` reopened for **Sprint `2.13`** and re-closed `✅ Done` on its retained
surface: the bootstrap pre-pulls the `docker.io/*` third-party chart images
authenticated on the host (reading, never writing, the host `docker login`)
before `kind load`, closing the cold-host **429** (live-proven: no 429 on the host
pull; overlay2 stores close the in-cluster 429 directly via `kind load`). The
in-cluster credential closure is jitML's own, self-contained Sprint `2.14`
`imagePullSecret` (projected from the host Docker Hub credential), which
authenticates the kind node's pulls; the host-dependent containerd-image-store
`kind load` behavior (the colima `ctr import` quirk) is a known characteristic
that owned path accommodates. It is an owned project mechanism, not a transfer to
any external foundation.

**Reopened + re-closed (Pulsar ML-Workflow convergence; closed 2026-06-20 on
owned surfaces).** Phases `5`, `10`, `11`, and `12` are **all `✅ Done`** on their
owned convergence surfaces (`5.12`/`5.13`/`5.14`, `10.7`, `11.10`, `12.14`); the
live behaviours — coordinator reconcile / multi-role serving and the panels' live
Playwright product proof — are forward ownership-transfers to Sprint `12.16` and
Phase `16`
(rule M(a)). They were reopened for the cross-project
[../documents/engineering/pulsar_ml_workflow.md](../documents/engineering/pulsar_ml_workflow.md)
convergence — a one-binary **Engine / Coordinator / Webapp** role model selected by
typed Dhall, a derived **topic algebra** owned by the Coordinator (retiring the
hardcoded `PulsarBootstrap` list), a reflected Dhall schema, the `Work*` envelope
family unifying training + inference, the artifact + `.ready` readiness contract,
and websocket snapshot/patch inference. The decomposed convergence sprints are
**Phase `5`**: `5.12` (reflected Dhall schema), `5.13` (Coordinator topic algebra),
`5.14` (one-binary role model) — **all `✅ Done`** on their owned pure-logic
surfaces (validated by container `jitml check-code`, host `jitml docs check`,
`jitml-unit` 203/203, `jitml-daemon-lifecycle` 35/35; live coordinator
reconcile / multi-role serving are forward ownership-transfers to Sprint
`12.16`); **Phase `10`**: `10.7` (async `Work*` inference + `.ready` gate,
collapsing the triplicated inference path into the Engine) — **`✅ Done`** on its
retained surface (`Work*` envelope family, readiness gate, single-`engineWeightedInference`
compute collapse), validated **statically in-container** (`check-code`/`docs
check`/`jitml-unit` 206) **and live on `linux-cpu`** (clean 84-step bootstrap +
`jitml-integration` 71/71 incl. inference round-trip); the publish-only async
behavior (CLI/demo publish a `WorkCommand`) transferred to `11.10`. **Phase `11`**:
`11.10` (Webapp role + websocket-driven panels + the transferred CLI publish,
folding `jitml-demo` in and dissolving the Apple in-pod-Metal browser-forward) —
**`✅ Done`** on its owned surface (all five panels async over `/api/ws/inference`
via the typed-decode pipeline; CheckpointCompare + Connect-4 as Engine workflows;
validated `cabal build all` / `jitml-unit` 208 / `jitml-e2e` 23 / `spago test`
17/17 / `check-code`, and live on `linux-cpu` for the Webapp pod + CLI publish;
live Playwright transfers to `14.2`/`16.x`); **Phase `12`**: `12.14`
(common-shape test coverage) — **`✅ Done`** (`jitml-unit` 208 + `web/test`
snapshot frames; `-p Live` integration is the standard runtime gate). Every
convergence `Blocked by` edge references a strictly lower-numbered sprint
(forward-DAG, rule M), and each closes on the `linux-cpu` / pure-logic lane with no
dual-accelerator gate. The live `linux-cpu` convergence validation caught and fixed a real
regression (the hand-written jitml-service chart ConfigMap lacked the new
`activeRole` field). The closure narrative below predates this reopen and is retained as dated
history.

**Reopened 2026-06-14 (no-caveat end-to-end product target).** The current
worktree has re-closed Phase `8` on all-row SL trainable runtime coverage and
typed RL event payloads, but the intended product is stricter: every RL
algorithm, every AlphaZero game, every tuning workflow, every model-family
checkpoint/reload/inference path, and every browser interaction must run
end-to-end with no synthetic, placeholder, demo-only, or parser-default
stand-ins. Sprint `11.9` removes the current browser parser-default residue and
adds generic/checkpoint-comparison route surfaces plus the RL/training/adversarial
visualization surface; it closed `✅ Done` on 2026-06-16 on that owned code
surface, with live checkpoint-backed interactions, live command-state
reconciliation, and Playwright proof owned downstream by Sprint `14.1` / `14.2`
and the Phase `15`/`16` live lanes (rule E). Phase `9` has its Sprint `9.12` code surface in place and has passed
linux-cpu, apple-silicon, and linux-cuda validation, so it is `✅ Done`.
Phase `10` has its Sprint `10.6` code surface in place and has passed
linux-cpu, linux-cuda, and apple-silicon validation, so it is `✅ Done`.
The 2026-06-15 bootstrap image-rebuild blocker had a validated Dockerfile fix
on the exact bootstrap-owned legacy-builder command, and all three live
integration lanes passed 71 / 71. At this 2026-06-14/16 checkpoint, Phase `13`
was still `🔄 Active`; Phases `11`–`12` re-closed `✅ Done` on 2026-06-16 (Sprints
`11.9` / `12.13` closed on their owned code surface, with the live-runtime
obligations deduped to Phases `15`/`16`/`14` per rule E); Phases `15`–`17` were
`⏸️ Blocked` behind the remaining runtime/browser surfaces; and Phases `14` and
`18` owned interactive demo/Playwright closure and final no-caveat product
handoff. Phases `0`–`12` were `✅ Done` on their owned
foundational/framework/frontend/test surfaces.

**Reopened 2026-06-13 (Apple Silicon host-resident workload placement).** Phase
`5` reopened and re-closed for Sprint `5.11`; Phase `12` reopened and re-closed
for Sprint `12.12`; Phase `16` reopened and re-closed for Sprint `16.10`; Phase
`17` reopened and re-closed for Sprint `17.7`. The Apple fixed bridge and
device selection remain valid, and the daemon now routes Apple Metal-backed
Training/RL/Tune starts through the Apple host daemon over Pulsar and MinIO.
Phase `12` asserts that no `jitml-rl-*` or sibling Apple Metal Job is created in
focused live tests, Phase `16` validates the full Apple lane through
`bootstrap/apple-silicon.sh test`, and Phase `17` moves the ledger row to
`Completed`. Phases `8`, `9`, and `10` stay
closed on their algorithm/checkpoint surfaces.

**Reopened and re-closed 2026-06-12 (true-headless Apple Metal fixed-bridge
doctrine).** Phase `1` reopened and re-closed for Sprint `1.15`; Phase `2`
reopened and re-closed for Sprint `2.12`; Phase `5` reopened and re-closed for
Sprint `5.10`; Phase `7` reopened and re-closed for Sprint `7.11`; Phase `16`
reopened and re-closed for Sprint `16.9`; Phase `17` re-closed after the Apple
lane passed and the deletion ledger became empty.

**Reopened 2026-06-10 (real-workflow refactor — superseded by the 2026-06-12
fixed-bridge closure and the 2026-06-13 placement reopen above).** A realness
audit found that every user-facing
workload and the demo used a synthetic/echo/pure-Haskell stand-in instead of the
substrate JIT path (`MlpDevice` → real `jitml_mlp_*` kernels) that the
`jitml-backends` lane already exercises. **Phases `8`–`12` reopened `🔄 Active` on
their code surfaces and Phases `15`–`17` on their live-runtime validation
surfaces**; Phases `0`–`7` stayed `✅ Done` (the engines and the backend lane are
real). As of 2026-06-12, Phases `8`, `9`, `10`, `11`, `12`, and `15` have
re-closed, and the subsequent Apple fixed-bridge closure re-closed Phases `16`
and `17` as of 2026-06-12. Exit-Definition items `6`, `8`, and `9` remain
strengthened; item `18` reopened and re-closed on 2026-06-13 with the Apple
placement ledger row now moved to `Completed`. Full detail and the exact
phase/sprint map live once in
[README.md → Closure Status / Reopened phases (2026-06-10)](README.md#reopened-phases-2026-06-10--real-workflow-refactor);
the historical baseline below is retained as dated record of the superseded state.

**Historical baseline before the 2026-06-13 placement reopen: all Phases
`0`, `1`, `2`, `3`, `4`, `5`, `6`, `7`, `8`, `9`, `10`, `11`, `12`, `15`, `16`, and `17` were `✅ Done`.** Phases `1`, `12`, `15`, `16`, and `17`
reopened `🔄 Active` on 2026-06-08 to remove the
cross-substrate numeric parity surface after the reproducibility contract was
clarified to within-substrate bit-for-bit only (across substrates there is no
guarantee — RNG draws and float reduction order differ). The reopened sprints are
`1.13` (remove `verify cross-backend`; add the `jitml test` `--test-options`
passthrough), `12.10` (realign `jitml-backends` to within-substrate cases,
relocate the two agnostic cases to `jitml-unit`, remove the report-card
`cross_substrate_parity` field, wire substrate-partitioned test lanes with no
skips), `15.16` / `16.6` (re-validate the linux-cuda / apple-silicon lanes run
for real with the skip guards removed), and `17.4` (delete the parity surface
and reframe the determinism contract + Exit Definition to within-substrate
only). **On 2026-06-09 the full source/code removal landed and was validated** on
the `apple-silicon` lane (4 / 4 host-native) and the `linux-cpu` lane (10 / 10 in
the `jitml` container), plus `jitml-unit` 193 / 193, container `jitml check-code`,
and `jitml docs check` — all green. Sprints `1.13` and `16.6` re-closed `✅ Done`.
Sprints `12.10` / `15.16` / `17.4` then closed their one shared remaining
obligation on **2026-06-09**: the live `linux-cuda` lane was re-validated for
real on the NVIDIA GeForce RTX 5090 host (UUID
`GPU-e764ef97-32d7-4981-c348-029983c64073`) via the GPU-attached `jitml-cuda`
compose service —
`docker compose run --rm jitml-cuda cabal test -fcuda jitml-backends
--test-options '-p linux-cuda'` passed **19 / 19 (12.26s, no skip-sentinels)**,
every within-substrate CUDA case a real device PASS. (`-fcuda` is the `cabal`
build flag compiling the real cuBLAS / cuDNN bindings — off by default to keep
the headless `jitml` baseline warning-clean — so the GPU lane runs through the
GPU container's `cabal test -fcuda` form, while the flag-free `jitml test`
orchestrator owns the apple-silicon / linux-cpu lanes.) With that run, **Sprints
`12.10` / `15.16` / `17.4` re-closed `✅ Done`, the last `Pending Removal` row
(the `linux-cuda` half of the skip-guard removal) moved to `Completed`, the
legacy ledger is empty, Exit Definition item 18 is met, and final handoff is
complete.** The 2026-06-10 Apple Silicon Tart-VM build-JIT doctrine reversal
reopened Phases `1`/`2`/`5`/`7`/`16` and the final handoff; all re-closed
`✅ Done` the same day after the live apple-silicon lane ran through the
Tart-VM-built path (`jitml test jitml-backends --apple-silicon`, 17/17 through
in-VM `swift build` + host Metal execution), so the six Tart-reversal ledger
rows moved to `Completed` and the ledger was empty / item 18 met again. That VM
doctrine was superseded by the 2026-06-12 fixed-bridge closure above. The earlier
reopen history stands
as dated record: **Phase `15` (all 15 sprints) and Phase `17` Sprints
`17.1`/`17.2` reopened `🔄 Active` on 2026-06-06 and re-closed `✅ Done` the
same day** (Sprint `17.3` stayed `✅ Done`) after re-validating the live CUDA,
GPU-training, cross-substrate, and final-`jitml test all` obligations on the
current **RTX 5090** host (UUID `GPU-e764ef97-32d7-4981-c348-029983c64073`,
CUDA 12.8, driver `570.211.01`, compute capability `12.0`); the original
evidence ran on an RTX 3090 (Plan Standards rule C). The re-validation passed
`jitml-backends -fcuda` 38 / 38 (incl. `CrossSubstrate`), a fresh
`jitml bootstrap --linux-cuda` with the in-pod `nvidia-smi` reporting the
RTX 5090, the live `jitml-integration` cohort 19 / 19, live MNIST SL
convergence, PPO/cartpole RL convergence, and `jitml test all --live` 8 / 8
stanzas with a populated report card; the flagged `nvcc -arch=sm_70` →
Blackwell `sm_120` PTX forward-JIT was confirmed (no `-arch` bump). See
[README.md → Reopened phases (2026-06-06)](README.md#reopened-phases-2026-06-06).
Phase `1` reopened then re-closed on 2026-06-04 after
Sprint `1.12` landed the CLI Dhall override surface
(`train --substrate / --seed`, `rl train --substrate / --seed`,
`tune --sampler / --scheduler / --pruner / --trials / --parallelism`) honoring
[../README.md → Hyperparameter tuning, first-class](../README.md#hyperparameter-tuning-first-class)
line 1050 and pillar 2 at
[../README.md → Why this exists](../README.md#why-this-exists). The
pure `JitML.Experiment.Overrides.applyOverrides` resolver substitutes CLI
values into the parsed experiment Dhall before validation; the README
registry/tree, `documents/cli/commands.md`,
`documents/engineering/cli_command_surface.md`, the manpage, and the shell
completions were regenerated via `jitml docs generate`; the doctrine-deviation
row in [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
moved to `Completed`. Phase `1` previously also reopened and re-closed on
2026-06-04 after Sprint
`1.10` removed the scoped `allow-newer` block and Sprint `1.11` moved the
project to a single GHC `9.12.4` baseline with no source pins, no local
dependency packages, and no reopened-phase development ledger. Phase `8` and
Phase `9` re-closed on 2026-06-04 after `KeyDoorGrid-v0` landed and the
required RL matrix retargeted away from `atari-subset`. Phases `2`,
`3`, `4`, and `5`
**reopened then re-closed on 2026-05-29** after four workstreams hardening
the cluster against host exhaustion and aligning run configuration and
subprocess control-flow with project doctrine landed: the Dhall
`dhall/cluster/` resource profile + kind-node memory/CPU cap + the
`cluster.host-memory` preflight (Phase `2` Sprint `2.8`), the right-sized
manual-PV layout (Phase `3` Sprint `3.2`), the per-pod resource limits and
right-sized replicas across the platform stack (Phase `4` Sprint `4.8`), and
the typed Dhall `RunConfig` + BootConfig-mounted worker dispatch that retires
the `JITML_*` run-parameter environment-variable IPC (Phase `5` Sprint
`5.7`); the reconciler + readiness `sh -c` control-flow also moved to bounded
typed Haskell over leaf subprocess outcomes (Phases `2` Sprint `2.9` / `4`
Sprint `4.8`). Those loops retain explicit attempt/delay constants and do not
claim the daemon `RetryPolicy` reader. The
originating incident is the 2026-05-29 cluster OOM storm that froze the
host. The changes implement already-in-scope doctrine (`Application
Environment`, `Subprocesses as Typed Values`, `Retry Policy as First-Class
Values`), so [Doctrine Scope](#doctrine-scope) is unchanged. The live
re-validation of every reopened-phase obligation is owned by Phase `15`
(closed 2026-05-30 on the RTX 3090, 15 / 15 sprints Done; reopened and
re-closed 2026-06-06 after re-validation on the RTX 5090); the
doctrine-deviation removals are tracked in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md). See
[README.md → Reopened phases (2026-05-29)](README.md#reopened-phases-2026-05-29).
Sprint `1.4` closes the
container-exclusive Haskell style/code-quality rule: the mandatory
`jitml:local` image build uses the same pinned GHC `9.12.4` to build pinned
Fourmolu / HLint binaries, runs `jitml check-code`, and host lint/check-code
execution is unsupported.
Phase `4` reclosed on 2026-05-23 against a Linux CUDA validation host
(NVIDIA GeForce RTX 5090, CUDA 12.8, compute capability `12.0`) for the then
current compact topology: the CUDA Kind cluster brought up
`jitml-linux-cuda-control-plane` with the GPU node label, the containerd
`nvidia` runtime handler, the read-only `/run/nvidia/driver` mount, and the
repo-owned NVIDIA runtime config; `RuntimeClass/nvidia` applied; the
`nvidia-smi-probe` pod reached `Succeeded`; and `kubectl logs
nvidia-smi-probe` reported the RTX 5090. Phase `5` Sprint `5.6`'s Linux CPU and
Linux CUDA service-pod validations both closed the same date: the live
`jitml bootstrap --linux-cpu` rollout completed all seven platform components
ready and `kubectl rollout restart deployment/jitml-service` cleanly replaced
the pod without surge under `maxSurge: 0` / `maxUnavailable: 1` with required
hostname anti-affinity; the CUDA service-pod variant ran `nvidia-smi -L` inside
the service container, and the Apple Silicon host-Dhall path completed
`./bootstrap/apple-silicon.sh up` on `edge_port: 9090` before the host-native
`jitml service --consume-once 0` run acquired `inference.command.apple-silicon`
as `jitml-host`. Phase `3` reclosed on 2026-05-23 after live Linux CPU
bootstrap and teardown validated the compact topology. These records are
historical; the HA target is reopened under Phases `3` / `4` / `5`.
Phase `7` (JIT codegen) closed its code surface on 2026-05-24 against an
RTX 3090 + CUDA 12.8 validation host; the live CUDA execution obligation it
fed migrated to Phase `15`, which reopened 2026-06-06 for re-validation on the
RTX 5090 (the RTX 3090 record here is retained as dated history). Phases `8` (supervised learning + RL framework),
`9` (RL catalog + AlphaZero + tuning),
`10` (checkpointing + inference), `11` (PureScript frontend + demo), and
`12` (test stanzas, lint matrix, live workflow matrix) closed on
2026-05-25 — every owned code-surface obligation landed in the worktree;
each phase's live obligations migrated to Phases `15` / `16` / `17`.
Phase `8` Sprint `8.3` (lunar-lander + atari-subset simulators) originally
closed through pure-Haskell ports in `src/JitML/RL/Simulator.hs`; Sprint `8.8`
retired the deterministic `atari-subset` stand-in behind explicit ROM handling,
and the static-foreign-source correction removed the checked-in C++ shim path.
Sprint `8.9` landed the `KeyDoorGrid-v0` copyright-free default demo
replacement, and Phase `9` Sprint `9.8` retargeted the required RL matrix to
use it.
Per-sprint Remaining Work blocks list the open work; the dependency-ordered
sequence lives in
[README.md → Execution Roadmap](README.md#execution-roadmap).

| Surface | Current Repo State | Intended End State |
|---------|--------------------|--------------------|
| Repository layout | Sprints `1.1` through `12.9` have landed the library-first Haskell CLI, AppError, cache, docs, env, lint, plan, subprocess, prerequisite, bootstrap, route, cluster-renderer, service-config, numerical-catalog, engine, runtime-source, SL/RL/tuning, checkpoint, web-contract, and report modules; stage-0 scripts; generated CLI docs; `compose.yaml`, `docker/`, `chart/`, `kind/`, `dhall/`, `web/`, `infra/`, `proto/`, and `experiments/` surfaces; and dedicated test bodies for every Cabal stanza. Sprint `1.15` removed the VM command surface, Sprints `2.12` / `5.10` removed Tart prerequisite/bootstrap and daemon acquire/config residue, and Sprint `7.11` removed the generated Swift/Tart cache-miss code path. | Full library-first Haskell layout with Haskell-owned runtime JIT source generation per [../README.md → Repository layout (target)](../README.md#repository-layout-target) |
| Build artefacts | The Cabal package declares one supported executable, `jitml`; `bootstrap/apple-silicon.sh build` targets `./.build/jitml`; the `jitml-demo` image/tag/workload is a retagged Webapp role of that binary. The typed JIT cache key/layout/manifest layer is implemented; Apple uses `.metal.json` source metadata plus a fixed host bridge under `./.build/host/apple-silicon/`; `jitml build --dry-run --substrate <substrate>` renders generated-source compile plans under `./.build/jit-src/<substrate>/<hash>/`; non-dry-run `jitml build` routes the selected JIT artifact through `JitML.Engines.Loader`; `jitml-backends` validates generated Linux CPU libdnnl-linked oneDNN primitive compile/load/run paths plus exported family/output-count metadata, local Linux CPU `HasEngine` dispatch, Linux CPU benchmark candidate measurement through generated FFI output digests, and Apple fixed-bridge Metal execution in the Apple lane; `jitml-unit` validates the CUDA host-callable wrapper/source ABI and guarded local CUDA runner fail-closed path | `cabal build all`-produced `jitml` binary, generated JIT compiler inputs under `./.build/jit-src/<substrate>/<hash>/`, plus per-substrate JIT-cache artefacts under `./.build/jit/<substrate>/` |
| CLI surface | The full command family is registered and parseable from `CommandSpec`; implemented commands cover bootstrap materialization with no-op exit `3`, live Kind/Helm bootstrap, doctor/remediation, commands/help, docs, lint/check-code, Plan/Apply dry-runs, env resolution, AppError rendering, cluster status/up/down/reset summaries, typed Kind down execution, service dry-run/surface rendering plus HTTP listener startup and bounded `--consume-once` daemon batch execution, daemon workload dispatch from parsed Training/RL/Tune command envelopes into Kubernetes Job apply/delete effects, train/eval/tune/RL/inference execution paths, test report rendering, internal substrate materialization, dataset upload, generated-source build-plan rendering, local JIT cache inspection/eviction, and the exact ProductRow publisher/executor `jitml internal train-and-publish-product-rows --<substrate> [--row <rowId>]`. Sprint `5.11` replaced Apple Metal-backed Job placement with host-resident workload commands while preserving Linux Job placement. Sprint `1.15` removed the `jitml internal vm` group from the implemented command surface, and Sprint `1.16` removed placeholder top-level `verify`, `inspect`, `bench`, and user-facing `kubectl` groups. The lint stack enforces config presence, whitespace normalization, forbidden paths, generated-doc drift, chart-shape checks, forbidden subprocess/terminal primitives, static JIT source/build artefact rejection, external `fourmolu`, `hlint`, `cabal format`, and warning-clean build execution inside `jitml:local`; host lint/check-code execution fails before linting. | The complete `jitml` command family parses and runs against three substrates: `doctor`, `cluster {up,down,status,reset}`, `service`, `train`, `eval`, `tune`, `rl {train,eval,rollout}`, `inference run`, `test`, `lint`, `docs`, `check-code`, `build`, `internal {materialize-substrate,list-prereqs,upload-dataset,gc,cache}`, `internal train-and-publish-product-rows --<substrate> [--row <rowId>]`, `commands`, and `help`; the `jitml-demo` HTTP surface is the Webapp role run by `jitml service` |
| Test stanzas | Ten Cabal stanzas are declared with dedicated bodies; the original eight cover unit, integration, canonical SL/RL, tuning, substrate backends, daemon lifecycle, and e2e surfaces, while `jitml-negative-controls` and `jitml-model-convergence` provide the standing realness gates. Phase `277` is Done for the retained pure negative-control gate-soundness scope. Its production request/event, journal/reducer, lifecycle, and mandatory per-row expansion is implemented in Phases `280`–`282` (legacy Sprints `32.4`–`32.6`) and the convergence stand-in is replaced in Phase `285` (legacy Sprint `33.3`); all are Blocked only for closure behind Sprint `278.1`. | Ten Cabal stanzas: `jitml-unit`, `jitml-integration`, `jitml-sl-canonicals`, `jitml-rl-canonicals`, `jitml-hyperparameter`, `jitml-backends`, `jitml-daemon-lifecycle`, `jitml-e2e`, `jitml-negative-controls`, `jitml-model-convergence` |
| Toolchain | `jitml.cabal` pins `tested-with: ghc ==9.12.4`; `cabal.project` pins `with-compiler: ghc-9.12.4`, records the codegen-toolchain comments and report-card knobs, carries no `allow-newer`, no `source-repository-package` pins, and no local dependency packages, and `jitml doctor --scope toolchain` validates the Sprint `2.2` host toolchain prerequisites after typed remediation. Plain Hackage solves under the GHC `9.12.4` / `base-4.21` baseline. LLVM and oneDNN currently come from host/container packages; CUDA/NVCC/cuDNN are Docker package-family pins; Node, Playwright, ALE, Metal runtime/bridge ABI, and Kind node image are pinned or probed at their owning surfaces. | GHC `9.12.4`, Cabal `3.16.1.0`, LLVM supplied by the host or Ubuntu package set rather than `cabal.project`, CUDA package family `12-8` plus cuDNN 9 in `docker/Dockerfile`, optional ALE library/runtime pinned in `docker/Dockerfile`, host OS Metal runtime + fixed bridge for core Apple execution, optional `swiftc`/macOS SDK only for non-core Swift JIT modules, oneDNN from Ubuntu `libdnnl-dev`, `kindest/node` pinned in `./kind/cluster-<substrate>.yaml`, and no `allow-newer` override |
| Determinism contract | Deterministic SL curves, RL trajectories, tuning trials, checkpoint inference, engine flags, Linux CPU oneDNN primitive execution, local Linux CPU `HasEngine` dispatch, CUDA host-wrapper source ABI, and per-substrate run-to-run bit-identity (within-substrate reproducibility) are covered by dedicated Cabal stanzas. Cross-substrate equivalence is out of contract and not asserted | Enforced by the `jitml-integration` (same-substrate bit-equality), `jitml-sl-canonicals`, `jitml-rl-canonicals`, and `jitml-backends` stanzas plus the per-substrate determinism notes in [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md) |
| Frontend | `web/` contains the PureScript shell, generated browser contracts from `src/JitML/Web/Contracts.hs`, Halogen panel modules under `web/src/Panels/`, and a `spec-node` `purescript-spec` smoke suite under `web/test/`; Sprint `11.9` adds current-panel generated payload parsers and request renderers, generated training/RL/tune command-envelope controls, request-aware command publication when a live cluster publication is present, checkpoint-runtime-backed MNIST/generic/CIFAR/checkpoint-compare/Connect 4 REST route injection, training metadata, RL replay scrub summaries, multi-game adversarial boards, and non-placeholder summary charts; `src/JitML/Web/Server.hs` serves the demo/API/WebSocket surface; the live-only Playwright scaffold drives the published edge route | PureScript shell under `web/`, generated contracts from `src/JitML/Web/Contracts.hs`, panel modules under `web/src/Panels/`, Playwright scaffold under `playwright/`, demo surface served by `jitml-demo` |

## Related Documents

- [README.md](README.md)
- [development_plan_standards.md](development_plan_standards.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [../README.md](../README.md)
- [../README.md](../README.md)
