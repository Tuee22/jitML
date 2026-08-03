# Development Plan Standards

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md), [../documents/documentation_standards.md](../documents/documentation_standards.md), [../README.md](../README.md), [phase-1-canonical-plan-suite-bootstrap.md](phase-1-canonical-plan-suite-bootstrap.md), [phase-2-doctrine-driven-scheduling-audit.md](phase-2-doctrine-driven-scheduling-audit.md), [phase-3-governed-document-metadata-enforcement.md](phase-3-governed-document-metadata-enforcement.md), [phase-4-toolchain-pin-and-library-first-cabal-project.md](phase-4-toolchain-pin-and-library-first-cabal-project.md), [phase-5-commandspec-registry-and-generated-parser.md](phase-5-commandspec-registry-and-generated-parser.md), [phase-6-generated-sections-and-tracking-generated-paths.md](phase-6-generated-sections-and-tracking-generated-paths.md), [phase-7-lint-stack-fourmolu-hlint-cabal-format-forbiddenpathregistry.md](phase-7-lint-stack-fourmolu-hlint-cabal-format-forbiddenpathregistry.md), [phase-8-plan-apply-boundary-with-dry-run-and-plan-file.md](phase-8-plan-apply-boundary-with-dry-run-and-plan-file.md), [phase-9-subprocess-typed-values-runstreaming-capture-interpreter.md](phase-9-subprocess-typed-values-runstreaming-capture-interpreter.md), [phase-10-prerequisite-registry-as-typed-effects.md](phase-10-prerequisite-registry-as-typed-effects.md), [phase-11-env-record-and-readert-env-io-runner.md](phase-11-env-record-and-readert-env-io-runner.md), [phase-12-apperror-adt-rendererror-output-rules.md](phase-12-apperror-adt-rendererror-output-rules.md), [phase-13-scoped-allow-newer-retirement-gate.md](phase-13-scoped-allow-newer-retirement-gate.md), [phase-14-ghc-9-12-4-baseline-and-dependency-helper-retirement.md](phase-14-ghc-9-12-4-baseline-and-dependency-helper-retirement.md), [phase-15-cli-dhall-overrides.md](phase-15-cli-dhall-overrides.md), [phase-16-remove-verify-cross-backend-add-jitml-test-test-options-pass.md](phase-16-remove-verify-cross-backend-add-jitml-test-test-options-pass.md), [phase-17-reinstate-the-jitml-internal-vm-build-vm-command-surface.md](phase-17-reinstate-the-jitml-internal-vm-build-vm-command-surface.md), [phase-18-retire-vm-lifecycle-commands-for-fixed-bridge-apple-metal.md](phase-18-retire-vm-lifecycle-commands-for-fixed-bridge-apple-metal.md), [phase-19-remove-placeholder-top-level-cli-groups.md](phase-19-remove-placeholder-top-level-cli-groups.md), [phase-20-typed-numeric-cli-parsing-and-generated-only-command-referen.md](phase-20-typed-numeric-cli-parsing-and-generated-only-command-referen.md), [phase-21-structured-subprocess-outcomes.md](phase-21-structured-subprocess-outcomes.md), [phase-22-stage-0-bootstrap-gates-and-delegation.md](phase-22-stage-0-bootstrap-gates-and-delegation.md), [phase-23-populated-prerequisiteregistry-and-lazy-remediation.md](phase-23-populated-prerequisiteregistry-and-lazy-remediation.md), [phase-24-jit-cache-layout-and-content-addressing.md](phase-24-jit-cache-layout-and-content-addressing.md), [phase-25-outer-container-linux-builds-and-jitml-local-image.md](phase-25-outer-container-linux-builds-and-jitml-local-image.md), [phase-26-superseded-apple-silicon-vm-scaffold.md](phase-26-superseded-apple-silicon-vm-scaffold.md), [phase-27-bootstrap-script-wrappers-and-status.md](phase-27-bootstrap-script-wrappers-and-status.md), [phase-28-bootstrap-down-and-purge.md](phase-28-bootstrap-down-and-purge.md), [phase-29-dhall-cluster-resource-profile-kind-node-cap-and-host-ram-pr.md](phase-29-dhall-cluster-resource-profile-kind-node-cap-and-host-ram-pr.md), [phase-30-reconciler-sh-c-control-flow-typed-haskell.md](phase-30-reconciler-sh-c-control-flow-typed-haskell.md), [phase-31-retire-the-tart-prerequisite-and-jitml-internal-vm-commands.md](phase-31-retire-the-tart-prerequisite-and-jitml-internal-vm-commands.md), [phase-32-reinstate-the-tart-build-vm-prerequisite-and-lifecycle.md](phase-32-reinstate-the-tart-build-vm-prerequisite-and-lifecycle.md), [phase-33-replace-tart-prerequisites-with-fixed-bridge-apple-cache-pre.md](phase-33-replace-tart-prerequisites-with-fixed-bridge-apple-cache-pre.md), [phase-34-authenticated-third-party-image-pre-pull-before-kind-load.md](phase-34-authenticated-third-party-image-pre-pull-before-kind-load.md), [phase-35-in-cluster-docker-hub-imagepullsecret-authenticated-pod-pull.md](phase-35-in-cluster-docker-hub-imagepullsecret-authenticated-pod-pull.md), [phase-36-durable-state-dhall-dsl-foundation-and-jitml-project-init.md](phase-36-durable-state-dhall-dsl-foundation-and-jitml-project-init.md), [phase-37-per-substrate-kind-configs-and-extramounts.md](phase-37-per-substrate-kind-configs-and-extramounts.md), [phase-38-kubernetes-io-no-provisioner-storage-and-manual-pvs.md](phase-38-kubernetes-io-no-provisioner-storage-and-manual-pvs.md), [phase-39-envoy-gateway-and-single-127-0-0-1-edge-port-listener.md](phase-39-envoy-gateway-and-single-127-0-0-1-edge-port-listener.md), [phase-40-typed-route-registry-and-generated-httproute-manifests.md](phase-40-typed-route-registry-and-generated-httproute-manifests.md), [phase-41-cluster-lifecycle-reconciler-and-phased-deploy.md](phase-41-cluster-lifecycle-reconciler-and-phased-deploy.md), [phase-42-ha-kind-node-and-manual-pv-topology.md](phase-42-ha-kind-node-and-manual-pv-topology.md), [phase-43-live-cluster-lifecycle-and-publication-truth.md](phase-43-live-cluster-lifecycle-and-publication-truth.md), [phase-44-harbor-subchart-and-bootstrap-phase-install.md](phase-44-harbor-subchart-and-bootstrap-phase-install.md), [phase-45-percona-pg-operator-and-patroni-managed-service-postgres.md](phase-45-percona-pg-operator-and-patroni-managed-service-postgres.md), [phase-46-minio-subchart-bucket-provisioning-conditional-write-server.md](phase-46-minio-subchart-bucket-provisioning-conditional-write-server.md), [phase-47-apache-pulsar-ha-and-topic-bootstrap.md](phase-47-apache-pulsar-ha-and-topic-bootstrap.md), [phase-48-kube-prometheus-stack-and-provisioned-dashboards.md](phase-48-kube-prometheus-stack-and-provisioned-dashboards.md), [phase-49-tensorboard-with-minio-event-storage-and-checkpoint-sidecar.md](phase-49-tensorboard-with-minio-event-storage-and-checkpoint-sidecar.md), [phase-50-nvidia-runtimeclass-for-linux-cuda.md](phase-50-nvidia-runtimeclass-for-linux-cuda.md), [phase-51-per-pod-resource-limits-and-right-sized-replicas-from-the-dh.md](phase-51-per-pod-resource-limits-and-right-sized-replicas-from-the-dh.md), [phase-52-project-the-durable-state-storeregistry-over-minio-buckets.md](phase-52-project-the-durable-state-storeregistry-over-minio-buckets.md), [phase-53-ha-platform-service-topology.md](phase-53-ha-platform-service-topology.md), [phase-54-jitml-service-entry-point-and-lifecycle-summary.md](phase-54-jitml-service-entry-point-and-lifecycle-summary.md), [phase-55-bootconfig-liveconfig-dhall-and-hot-reload-schema-surface.md](phase-55-bootconfig-liveconfig-dhall-and-hot-reload-schema-surface.md), [phase-56-healthz-readyz-metrics-and-structured-logging.md](phase-56-healthz-readyz-metrics-and-structured-logging.md), [phase-57-retrypolicy-and-service-error-surface.md](phase-57-retrypolicy-and-service-error-surface.md), [phase-58-at-least-once-pulsar-consumer-with-message-hash-deduplicatio.md](phase-58-at-least-once-pulsar-consumer-with-message-hash-deduplicatio.md), [phase-59-stateless-deployment-pod-anti-affinity-per-substrate-dhall.md](phase-59-stateless-deployment-pod-anti-affinity-per-substrate-dhall.md), [phase-60-typed-dhall-runconfig-and-bootconfig-mounted-worker-dispatch.md](phase-60-typed-dhall-runconfig-and-bootconfig-mounted-worker-dispatch.md), [phase-61-retire-tart-vm-lifecycle-from-the-daemon.md](phase-61-retire-tart-vm-lifecycle-from-the-daemon.md), [phase-62-reinstate-the-dhall-configured-build-vm-block-and-daemon-acq.md](phase-62-reinstate-the-dhall-configured-build-vm-block-and-daemon-acq.md), [phase-63-replace-daemon-build-vm-acquire-with-metal-bridge-acquire.md](phase-63-replace-daemon-build-vm-acquire-with-metal-bridge-acquire.md), [phase-64-workload-placement-planner-and-apple-host-workload-dispatch.md](phase-64-workload-placement-planner-and-apple-host-workload-dispatch.md), [phase-65-reflected-dhall-schema.md](phase-65-reflected-dhall-schema.md), [phase-66-coordinator-topic-algebra.md](phase-66-coordinator-topic-algebra.md), [phase-67-one-binary-engine-coordinator-webapp-role-model.md](phase-67-one-binary-engine-coordinator-webapp-role-model.md), [phase-68-reconcile-the-pulsar-topic-family-with-the-storeregistry.md](phase-68-reconcile-the-pulsar-topic-family-with-the-storeregistry.md), [phase-69-one-numerical-worker-per-kubernetes-node.md](phase-69-one-numerical-worker-per-kubernetes-node.md), [phase-70-fail-closed-mounted-worker-runconfig.md](phase-70-fail-closed-mounted-worker-runconfig.md), [phase-71-receipt-bound-delivery-and-total-settlement.md](phase-71-receipt-bound-delivery-and-total-settlement.md), [phase-72-layer-catalog.md](phase-72-layer-catalog.md), [phase-73-activations-real-and-complex.md](phase-73-activations-real-and-complex.md), [phase-74-spectral-frequency-domain-operations.md](phase-74-spectral-frequency-domain-operations.md), [phase-75-optimizers-and-schedulers.md](phase-75-optimizers-and-schedulers.md), [phase-76-loss-functions.md](phase-76-loss-functions.md), [phase-77-dhall-schemas-and-cross-type-audit.md](phase-77-dhall-schemas-and-cross-type-audit.md), [phase-78-kernelspec-cache-key-inputs-ffi-loader-surface.md](phase-78-kernelspec-cache-key-inputs-ffi-loader-surface.md), [phase-79-engine-abi-and-engines-module-skeleton.md](phase-79-engine-abi-and-engines-module-skeleton.md), [phase-80-linux-cpu-engine-and-onednn-codegen-driver.md](phase-80-linux-cpu-engine-and-onednn-codegen-driver.md), [phase-81-linux-cuda-engine-and-cuda-codegen-driver.md](phase-81-linux-cuda-engine-and-cuda-codegen-driver.md), [phase-82-apple-silicon-engine-metal-codegen-host-forwarding-scaffoldi.md](phase-82-apple-silicon-engine-metal-codegen-host-forwarding-scaffoldi.md), [phase-83-hardware-auto-tuning-within-the-determinism-contract.md](phase-83-hardware-auto-tuning-within-the-determinism-contract.md), [phase-84-haskell-owned-runtime-jit-source-generation.md](phase-84-haskell-owned-runtime-jit-source-generation.md), [phase-85-headless-apple-metal-jit-runtime-compilation-host-swift-buil.md](phase-85-headless-apple-metal-jit-runtime-compilation-host-swift-buil.md), [phase-86-compose-gpu-service-split.md](phase-86-compose-gpu-service-split.md), [phase-87-route-the-apple-swift-build-through-the-tart-vm.md](phase-87-route-the-apple-swift-build-through-the-tart-vm.md), [phase-88-fixed-host-metal-bridge-and-source-metadata-apple-cache.md](phase-88-fixed-host-metal-bridge-and-source-metadata-apple-cache.md), [phase-89-local-supervised-canonical-summaries.md](phase-89-local-supervised-canonical-summaries.md), [phase-90-jitml-train-local-cli-summary.md](phase-90-jitml-train-local-cli-summary.md), [phase-91-rl-catalog-hook-for-canonical-tests.md](phase-91-rl-catalog-hook-for-canonical-tests.md), [phase-92-rl-metadata-primitives.md](phase-92-rl-metadata-primitives.md), [phase-93-rl-cli-summaries-and-report-hooks.md](phase-93-rl-cli-summaries-and-report-hooks.md), [phase-94-rl-training-plan-surface.md](phase-94-rl-training-plan-surface.md), [phase-95-rlrunlifecycle-gadt-retrofit.md](phase-95-rlrunlifecycle-gadt-retrofit.md), [phase-96-ale-boundary-and-rom-policy.md](phase-96-ale-boundary-and-rom-policy.md), [phase-97-copyright-free-visual-rl-demo-environment.md](phase-97-copyright-free-visual-rl-demo-environment.md), [phase-98-sl-substrate-backed-training-real-eval.md](phase-98-sl-substrate-backed-training-real-eval.md), [phase-99-rl-framework-substrate-routing.md](phase-99-rl-framework-substrate-routing.md), [phase-100-no-caveat-sl-rl-framework-runtime.md](phase-100-no-caveat-sl-rl-framework-runtime.md), [phase-101-real-sl-loss-validation-driven-selection-and-convergence-per.md](phase-101-real-sl-loss-validation-driven-selection-and-convergence-per.md), [phase-102-fixed-budget-training-witness-and-inference-ineligible-parti.md](phase-102-fixed-budget-training-witness-and-inference-ineligible-parti.md), [phase-103-typed-fail-closed-rl-device-errors.md](phase-103-typed-fail-closed-rl-device-errors.md), [phase-104-validated-runplan-and-pure-contract-algebra.md](phase-104-validated-runplan-and-pure-contract-algebra.md), [phase-105-on-policy-algorithm-metadata.md](phase-105-on-policy-algorithm-metadata.md), [phase-106-off-policy-algorithm-metadata.md](phase-106-off-policy-algorithm-metadata.md), [phase-107-specialised-algorithm-metadata.md](phase-107-specialised-algorithm-metadata.md), [phase-108-local-rl-canonical-tests.md](phase-108-local-rl-canonical-tests.md), [phase-109-alphazero-connect-4-transcript-surface.md](phase-109-alphazero-connect-4-transcript-surface.md), [phase-110-connect-4-local-game-surface.md](phase-110-connect-4-local-game-surface.md), [phase-111-hyperparameter-tuning-sampler-scheduler-pruner.md](phase-111-hyperparameter-tuning-sampler-scheduler-pruner.md), [phase-112-copyright-free-rl-matrix-retargeting.md](phase-112-copyright-free-rl-matrix-retargeting.md), [phase-113-real-rl-eval-rollout-and-per-algorithm-on-device-rollouts.md](phase-113-real-rl-eval-rollout-and-per-algorithm-on-device-rollouts.md), [phase-114-real-mcts-tree-search-with-substrate-backed-leaf-evaluation.md](phase-114-real-mcts-tree-search-with-substrate-backed-leaf-evaluation.md), [phase-115-real-hyperparameter-tuning-objective-executor.md](phase-115-real-hyperparameter-tuning-objective-executor.md), [phase-116-no-caveat-rl-alphazero-and-tuning-runtime.md](phase-116-no-caveat-rl-alphazero-and-tuning-runtime.md), [phase-117-real-rl-convergence-performance-metrics-and-the-alphazero-ar.md](phase-117-real-rl-convergence-performance-metrics-and-the-alphazero-ar.md), [phase-118-all-rl-fixed-budget-convergence-metrics.md](phase-118-all-rl-fixed-budget-convergence-metrics.md), [phase-119-typed-tuning-resume-decode-failures.md](phase-119-typed-tuning-resume-decode-failures.md), [phase-120-tuning-override-and-worker-axis-fidelity.md](phase-120-tuning-override-and-worker-axis-fidelity.md), [phase-121-resolved-alphazero-and-tuning-plans.md](phase-121-resolved-alphazero-and-tuning-plans.md), [phase-122-storage-layout-and-split-blob-schema.md](phase-122-storage-layout-and-split-blob-schema.md), [phase-123-jmw1-wire-format-and-manifest-cbor.md](phase-123-jmw1-wire-format-and-manifest-cbor.md), [phase-124-bit-determinism-contract-and-retention-reconciler.md](phase-124-bit-determinism-contract-and-retention-reconciler.md), [phase-125-inference-only-read-path.md](phase-125-inference-only-read-path.md), [phase-126-remove-the-synthetic-inference-offset.md](phase-126-remove-the-synthetic-inference-offset.md), [phase-127-exact-v2-supervised-runtime-artifact.md](phase-127-exact-v2-supervised-runtime-artifact.md), [phase-128-async-work-inference-workflow-and-ready-readiness-gate.md](phase-128-async-work-inference-workflow-and-ready-readiness-gate.md), [phase-129-typed-retentionpolicy-replaces-the-lastn-5-literal.md](phase-129-typed-retentionpolicy-replaces-the-lastn-5-literal.md), [phase-130-real-trained-demo-checkpoints-delete-the-synthetic-weight-ra.md](phase-130-real-trained-demo-checkpoints-delete-the-synthetic-weight-ra.md), [phase-131-inference-eligible-checkpoints-and-convergence-statistics.md](phase-131-inference-eligible-checkpoints-and-convergence-statistics.md), [phase-132-typed-checkpoint-object-key-validation.md](phase-132-typed-checkpoint-object-key-validation.md), [phase-133-persisted-checkpoint-proof-admission.md](phase-133-persisted-checkpoint-proof-admission.md), [phase-134-minimal-purescript-application-scaffold.md](phase-134-minimal-purescript-application-scaffold.md), [phase-135-browser-contract-adts-and-local-contract-rendering.md](phase-135-browser-contract-adts-and-local-contract-rendering.md), [phase-136-jitml-lint-purescript-generated-contract-smoke-target.md](phase-136-jitml-lint-purescript-generated-contract-smoke-target.md), [phase-137-interactive-endpoint-contract-surface.md](phase-137-interactive-endpoint-contract-surface.md), [phase-138-webapp-route-and-deployment-surface.md](phase-138-webapp-route-and-deployment-surface.md), [phase-139-playwright-e2e-suite.md](phase-139-playwright-e2e-suite.md), [phase-140-spa-portals-home-and-shared-header.md](phase-140-spa-portals-home-and-shared-header.md), [phase-141-demo-endpoints-render-real-substrate-output.md](phase-141-demo-endpoints-render-real-substrate-output.md), [phase-142-full-interactive-demo-surface.md](phase-142-full-interactive-demo-surface.md), [phase-143-webapp-role-and-websocket-driven-inference-panels.md](phase-143-webapp-role-and-websocket-driven-inference-panels.md), [phase-144-all-model-trained-artifact-ui-and-admin-navigation.md](phase-144-all-model-trained-artifact-ui-and-admin-navigation.md), [phase-145-jitml-unit-stanza.md](phase-145-jitml-unit-stanza.md), [phase-146-jitml-integration-stanza-subprocess-boundary-determinism.md](phase-146-jitml-integration-stanza-subprocess-boundary-determinism.md), [phase-147-jitml-sl-canonicals-stanza.md](phase-147-jitml-sl-canonicals-stanza.md), [phase-148-jitml-rl-canonicals-stanza.md](phase-148-jitml-rl-canonicals-stanza.md), [phase-149-jitml-hyperparameter-stanza.md](phase-149-jitml-hyperparameter-stanza.md), [phase-150-jitml-cross-backend-stanza.md](phase-150-jitml-cross-backend-stanza.md), [phase-151-jitml-daemon-lifecycle-stanza.md](phase-151-jitml-daemon-lifecycle-stanza.md), [phase-152-jitml-e2e-stanza-and-live-plan-orchestrator.md](phase-152-jitml-e2e-stanza-and-live-plan-orchestrator.md), [phase-153-jitml-test-all-orchestrator-and-report-card.md](phase-153-jitml-test-all-orchestrator-and-report-card.md), [phase-154-substrate-partitioned-test-lanes-remove-the-cross-substrate.md](phase-154-substrate-partitioned-test-lanes-remove-the-cross-substrate.md), [phase-155-dry-real-workflow-matrix-fail-closed.md](phase-155-dry-real-workflow-matrix-fail-closed.md), [phase-156-live-job-failure-observation-and-apple-placement-assertions.md](phase-156-live-job-failure-observation-and-apple-placement-assertions.md), [phase-157-playwright-no-caveat-e2e-matrix.md](phase-157-playwright-no-caveat-e2e-matrix.md), [phase-158-common-shape-workflow-topic-algebra-and-websocket-coverage.md](phase-158-common-shape-workflow-topic-algebra-and-websocket-coverage.md), [phase-159-per-model-integration-and-e2e-matrix.md](phase-159-per-model-integration-and-e2e-matrix.md), [phase-160-functional-core-live-workflow-interpreter.md](phase-160-functional-core-live-workflow-interpreter.md), [phase-161-full-canonical-model-matrix-runtime.md](phase-161-full-canonical-model-matrix-runtime.md), [phase-162-re-attest-the-no-caveat-runtime-with-real-losses-metrics.md](phase-162-re-attest-the-no-caveat-runtime-with-real-losses-metrics.md), [phase-163-fixed-budget-all-model-runtime-gate-linux-cpu.md](phase-163-fixed-budget-all-model-runtime-gate-linux-cpu.md), [phase-164-full-workflow-control-surface.md](phase-164-full-workflow-control-surface.md), [phase-165-playwright-no-caveat-product-matrix.md](phase-165-playwright-no-caveat-product-matrix.md), [phase-166-real-demo-inference-full-width-multi-layer-forward-real-inpu.md](phase-166-real-demo-inference-full-width-multi-layer-forward-real-inpu.md), [phase-167-all-model-browser-and-playwright-trained-artifact-matrix.md](phase-167-all-model-browser-and-playwright-trained-artifact-matrix.md), [phase-168-ephemeral-kind-helm-rollout.md](phase-168-ephemeral-kind-helm-rollout.md), [phase-169-live-capability-class-validation-minio-pulsar-harbor.md](phase-169-live-capability-class-validation-minio-pulsar-harbor.md), [phase-170-daemon-training-rl-tune-handlers-on-live-broker.md](phase-170-daemon-training-rl-tune-handlers-on-live-broker.md), [phase-171-live-sl-training-e2e-with-real-datasets.md](phase-171-live-sl-training-e2e-with-real-datasets.md), [phase-172-real-rl-environment-simulators-and-daemon-env-loop.md](phase-172-real-rl-environment-simulators-and-daemon-env-loop.md), [phase-173-live-rl-training-e2e-with-statistical-convergence-assertions.md](phase-173-live-rl-training-e2e-with-statistical-convergence-assertions.md), [phase-174-live-minio-checkpoint-round-trip-and-retention.md](phase-174-live-minio-checkpoint-round-trip-and-retention.md), [phase-175-real-cuda-rl-algorithm-losses-through-jit-engine.md](phase-175-real-cuda-rl-algorithm-losses-through-jit-engine.md), [phase-176-alphazero-with-real-network-priors.md](phase-176-alphazero-with-real-network-priors.md), [phase-177-live-tuning-sweep-with-minio-trial-persistence.md](phase-177-live-tuning-sweep-with-minio-trial-persistence.md), [phase-178-cuda-and-linux-cpu-production-weight-loading.md](phase-178-cuda-and-linux-cpu-production-weight-loading.md), [phase-179-live-jitml-inference-run-and-legacy-replay-helper.md](phase-179-live-jitml-inference-run-and-legacy-replay-helper.md), [phase-180-live-api-ws-websocket-proxy-and-compiled-halogen-bundle.md](phase-180-live-api-ws-websocket-proxy-and-compiled-halogen-bundle.md), [phase-181-live-playwright-on-demo-edge-route.md](phase-181-live-playwright-on-demo-edge-route.md), [phase-182-linux-cpu-full-tensor-benchmark-payloads-and-first-cache-mis.md](phase-182-linux-cpu-full-tensor-benchmark-payloads-and-first-cache-mis.md), [phase-183-re-validate-the-linux-cuda-lane-runs-for-real-with-the-skip.md](phase-183-re-validate-the-linux-cuda-lane-runs-for-real-with-the-skip.md), [phase-184-live-linux-cpu-exercise-of-the-reopened-workflows.md](phase-184-live-linux-cpu-exercise-of-the-reopened-workflows.md), [phase-185-live-linux-cuda-exercise-of-the-reopened-workflows.md](phase-185-live-linux-cuda-exercise-of-the-reopened-workflows.md), [phase-186-live-cluster-closure-of-the-reopened-workflows.md](phase-186-live-cluster-closure-of-the-reopened-workflows.md), [phase-187-linux-no-caveat-runtime-and-browser-lane.md](phase-187-linux-no-caveat-runtime-and-browser-lane.md), [phase-188-linux-cuda-all-model-trained-artifact-lane.md](phase-188-linux-cuda-all-model-trained-artifact-lane.md), [phase-189-linux-cuda-ha-cluster-revalidation.md](phase-189-linux-cuda-ha-cluster-revalidation.md), [phase-190-host-swift-toolchain-and-first-cache-miss-headless-build.md](phase-190-host-swift-toolchain-and-first-cache-miss-headless-build.md), [phase-191-metal-ffi-loading-and-host-kernel-launch.md](phase-191-metal-ffi-loading-and-host-kernel-launch.md), [phase-192-metal-benchmark-candidate-runner-live-execution.md](phase-192-metal-benchmark-candidate-runner-live-execution.md), [phase-193-apple-host-cluster-pulsar-rpc-live-flow.md](phase-193-apple-host-cluster-pulsar-rpc-live-flow.md), [phase-194-apple-metal-production-weight-loading.md](phase-194-apple-metal-production-weight-loading.md), [phase-195-re-validate-the-apple-silicon-lane-runs-for-real-with-the-sk.md](phase-195-re-validate-the-apple-silicon-lane-runs-for-real-with-the-sk.md), [phase-196-re-validate-the-apple-silicon-lane-through-the-tart-vm-built.md](phase-196-re-validate-the-apple-silicon-lane-through-the-tart-vm-built.md), [phase-197-retired-vm-path-apple-silicon-workflow-attempt.md](phase-197-retired-vm-path-apple-silicon-workflow-attempt.md), [phase-198-live-fixed-bridge-apple-silicon-workflow-closure.md](phase-198-live-fixed-bridge-apple-silicon-workflow-closure.md), [phase-199-live-apple-host-resident-workload-closure.md](phase-199-live-apple-host-resident-workload-closure.md), [phase-200-apple-no-caveat-runtime-and-browser-lane.md](phase-200-apple-no-caveat-runtime-and-browser-lane.md), [phase-201-apple-silicon-all-model-trained-artifact-lane.md](phase-201-apple-silicon-all-model-trained-artifact-lane.md), [phase-202-apple-silicon-ha-cluster-revalidation.md](phase-202-apple-silicon-ha-cluster-revalidation.md), [phase-203-cross-substrate-cohort-runs-and-in-code-tolerance-bands.md](phase-203-cross-substrate-cohort-runs-and-in-code-tolerance-bands.md), [phase-204-live-jitml-test-all-report-card-with-measured-metrics.md](phase-204-live-jitml-test-all-report-card-with-measured-metrics.md), [phase-205-empty-legacy-ledger-and-final-handoff.md](phase-205-empty-legacy-ledger-and-final-handoff.md), [phase-206-remove-the-cross-substrate-parity-surface-reframe-the-determ.md](phase-206-remove-the-cross-substrate-parity-surface-reframe-the-determ.md), [phase-207-cross-substrate-real-workflow-confirmation.md](phase-207-cross-substrate-real-workflow-confirmation.md), [phase-208-real-workflow-ledger-walk-down-and-final-handoff.md](phase-208-real-workflow-ledger-walk-down-and-final-handoff.md), [phase-209-apple-placement-ledger-walk-down-and-final-handoff.md](phase-209-apple-placement-ledger-walk-down-and-final-handoff.md), [phase-210-expanded-no-caveat-report-card-and-ledger-handoff.md](phase-210-expanded-no-caveat-report-card-and-ledger-handoff.md), [phase-211-expanded-all-model-lane-fragment-handoff.md](phase-211-expanded-all-model-lane-fragment-handoff.md), [phase-212-ha-topology-aggregation.md](phase-212-ha-topology-aggregation.md), [phase-213-three-substrate-no-caveat-handoff.md](phase-213-three-substrate-no-caveat-handoff.md), [phase-214-re-aggregate-the-no-caveat-handoff-after-the-durable-state-d.md](phase-214-re-aggregate-the-no-caveat-handoff-after-the-durable-state-d.md), [phase-215-re-aggregate-the-no-caveat-handoff-after-the-real-sl-rl-chai.md](phase-215-re-aggregate-the-no-caveat-handoff-after-the-real-sl-rl-chai.md), [phase-216-re-aggregate-after-fixed-budget-all-model-closure.md](phase-216-re-aggregate-after-fixed-budget-all-model-closure.md), [phase-217-ha-topology-product-handoff.md](phase-217-ha-topology-product-handoff.md), [phase-218-re-aggregate-after-typed-failure-and-docs-governance-remedia.md](phase-218-re-aggregate-after-typed-failure-and-docs-governance-remedia.md), [phase-219-re-aggregate-after-real-cluster-tuning-runconfig-remediation.md](phase-219-re-aggregate-after-real-cluster-tuning-runconfig-remediation.md), [phase-220-product-matrix-authority.md](phase-220-product-matrix-authority.md), [phase-221-phase-status-registry.md](phase-221-phase-status-registry.md), [phase-222-status-truth-enforcement.md](phase-222-status-truth-enforcement.md), [phase-223-product-registry-plan-and-admitted-evidence-projection.md](phase-223-product-registry-plan-and-admitted-evidence-projection.md), [phase-224-remove-fossils.md](phase-224-remove-fossils.md), [phase-225-scaffold-lint-reachability.md](phase-225-scaffold-lint-reachability.md), [phase-226-non-fabricable-training-evidence.md](phase-226-non-fabricable-training-evidence.md), [phase-227-type-state-pipeline-haskell.md](phase-227-type-state-pipeline-haskell.md), [phase-228-dhall-boundary-fail-closed-decode.md](phase-228-dhall-boundary-fail-closed-decode.md), [phase-229-phase-specific-product-evidence-payloads.md](phase-229-phase-specific-product-evidence-payloads.md), [phase-230-matrix-parity.md](phase-230-matrix-parity.md), [phase-231-per-row-runnable-dhall.md](phase-231-per-row-runnable-dhall.md), [phase-232-read-time-dataset-sha.md](phase-232-read-time-dataset-sha.md), [phase-233-typed-layer-ir-reverse-mode-autodiff.md](phase-233-typed-layer-ir-reverse-mode-autodiff.md), [phase-234-onednn-layer-kernels-for-training.md](phase-234-onednn-layer-kernels-for-training.md), [phase-235-one-self-describing-checkpoint-envelope.md](phase-235-one-self-describing-checkpoint-envelope.md), [phase-236-checkpoint-admission-single-path.md](phase-236-checkpoint-admission-single-path.md), [phase-237-supervised-serving-on-the-layer-graph-ir.md](phase-237-supervised-serving-on-the-layer-graph-ir.md), [phase-238-supervised-training-on-the-layer-graph-ir.md](phase-238-supervised-training-on-the-layer-graph-ir.md), [phase-239-checkpoint-construction-from-the-trained-graph.md](phase-239-checkpoint-construction-from-the-trained-graph.md), [phase-240-layer-graph-checkpoints-inference.md](phase-240-layer-graph-checkpoints-inference.md), [phase-241-onednn-device-training-kernels-for-correct-operators.md](phase-241-onednn-device-training-kernels-for-correct-operators.md), [phase-242-literal-architectures-dense-mlp-lenet.md](phase-242-literal-architectures-dense-mlp-lenet.md), [phase-243-literal-architectures-resnet-family.md](phase-243-literal-architectures-resnet-family.md), [phase-244-literal-architectures-vision-transformer.md](phase-244-literal-architectures-vision-transformer.md), [phase-245-convergence-and-evidence.md](phase-245-convergence-and-evidence.md), [phase-246-completedtraining-sl-manifests.md](phase-246-completedtraining-sl-manifests.md), [phase-247-real-environments.md](phase-247-real-environments.md), [phase-248-distinct-algorithms.md](phase-248-distinct-algorithms.md), [phase-249-per-row-convergence-and-evidence.md](phase-249-per-row-convergence-and-evidence.md), [phase-250-typed-rl-cohort-and-action-domain-compatibility.md](phase-250-typed-rl-cohort-and-action-domain-compatibility.md), [phase-251-trainingplan-evaluationplan-compiler-and-trainer-migration.md](phase-251-trainingplan-evaluationplan-compiler-and-trainer-migration.md), [phase-252-typed-measured-counters-and-evidence-separation.md](phase-252-typed-measured-counters-and-evidence-separation.md), [phase-253-per-game-self-play.md](phase-253-per-game-self-play.md), [phase-254-arena-convergence-evidence.md](phase-254-arena-convergence-evidence.md), [phase-255-train-and-publish-artifact-selectors.md](phase-255-train-and-publish-artifact-selectors.md), [phase-256-row-specific-renderers.md](phase-256-row-specific-renderers.md), [phase-257-browser-fail-closed.md](phase-257-browser-fail-closed.md), [phase-258-row-keyed-integration-matrix.md](phase-258-row-keyed-integration-matrix.md), [phase-259-row-complete-playwright.md](phase-259-row-complete-playwright.md), [phase-260-linux-cpu-report-card.md](phase-260-linux-cpu-report-card.md), [phase-261-contract-driven-live-execution-integration-journal.md](phase-261-contract-driven-live-execution-integration-journal.md), [phase-262-contract-driven-live-execution-browser-and-playwright.md](phase-262-contract-driven-live-execution-browser-and-playwright.md), [phase-263-contract-driven-live-execution-fragment-issuance.md](phase-263-contract-driven-live-execution-fragment-issuance.md), [phase-264-real-cudnn-cublas-kernels.md](phase-264-real-cudnn-cublas-kernels.md), [phase-265-cuda-row-device-evidence.md](phase-265-cuda-row-device-evidence.md), [phase-266-cuda-integration-e2e-and-attestation.md](phase-266-cuda-integration-e2e-and-attestation.md), [phase-267-gpu-performance-and-persistent-device-buffers.md](phase-267-gpu-performance-and-persistent-device-buffers.md), [phase-268-contract-driven-cuda-lane-revalidation.md](phase-268-contract-driven-cuda-lane-revalidation.md), [phase-269-real-metal-kernels.md](phase-269-real-metal-kernels.md), [phase-270-metal-row-device-evidence.md](phase-270-metal-row-device-evidence.md), [phase-271-apple-integration-e2e-and-attestation.md](phase-271-apple-integration-e2e-and-attestation.md), [phase-272-contract-driven-apple-lane-revalidation.md](phase-272-contract-driven-apple-lane-revalidation.md), [phase-273-attestation-join.md](phase-273-attestation-join.md), [phase-274-no-caveat-closure-guard.md](phase-274-no-caveat-closure-guard.md), [phase-275-journal-derived-product-aggregation.md](phase-275-journal-derived-product-aggregation.md), [phase-276-negative-control-suite.md](phase-276-negative-control-suite.md), [phase-277-external-bars-no-self-referential-gate-lint-and-exact-served.md](phase-277-external-bars-no-self-referential-gate-lint-and-exact-served.md), [phase-278-measured-declared-type-split-behavioral-scaffold-lint.md](phase-278-measured-declared-type-split-behavioral-scaffold-lint.md), [phase-279-runcontract-negative-controls-request-and-event-fixtures.md](phase-279-runcontract-negative-controls-request-and-event-fixtures.md), [phase-280-runcontract-negative-controls-journal-fixtures-and-reducer-p.md](phase-280-runcontract-negative-controls-journal-fixtures-and-reducer-p.md), [phase-281-runcontract-negative-controls-lifecycle-and-per-row-registra.md](phase-281-runcontract-negative-controls-lifecycle-and-per-row-registra.md), [phase-282-per-model-measured-convergence.md](phase-282-per-model-measured-convergence.md), [phase-283-inference-performance-determinism.md](phase-283-inference-performance-determinism.md), [phase-284-contract-driven-per-model-evidence.md](phase-284-contract-driven-per-model-evidence.md), [phase-285-evidence-derived-closure-guard.md](phase-285-evidence-derived-closure-guard.md), [phase-286-standing-adversarial-audit-thin-plan.md](phase-286-standing-adversarial-audit-thin-plan.md), [phase-287-journal-derived-status-registry.md](phase-287-journal-derived-status-registry.md), [phase-288-evidence-typed-report-measurements.md](phase-288-evidence-typed-report-measurements.md)
**Generated sections**: none

> **Purpose**: Define the maintenance rules for the jitML development plan so the
> repository keeps one coherent, execution-ordered plan plus an explicit cleanup
> ledger across the CLI bootstrap, the three-substrate cluster buildout, the
> training and inference workloads, and the within-substrate test surface.

## Core Principles

### A. Continuous Clean-Room Narrative

The plan must read as one sequential buildout from an empty checkout to the intended
repository end state — one Haskell CLI driving three substrates (`apple-silicon`,
`linux-cpu`, `linux-cuda`) behind a uniform command surface, the `jitml service`
daemon as the single Pulsar-subscribed worker, deterministic JIT-compiled execution
on each substrate, supervised and reinforcement learning training pipelines including
AlphaZero-style self-play, and a PureScript frontend driven from generated browser
contracts. Every workload crosses a raw-to-validated `RunPlan` boundary, executes
through a pure protocol/evidence contract plus one resource-safe interpreter, and
publishes reports derived from append-only execution journals.

- Every phase assumes the previous phase has already closed.
- The plan flows from documentation topology to the CLI surface, to bootstrap
  reconcilers and JIT cache discipline, to cluster substrate and stateful platform
  services, to the long-running daemon, then through the numerical core and per-
  substrate JIT codegen, the SL/RL framework and algorithm catalog, AlphaZero and
  hyperparameter tuning, checkpointing and the inference-only read path, the
  PureScript frontend, and finally the test stanzas, live workflow matrix, and
  final handoff surface.
- A reader unfamiliar with the repository must be able to follow the plan top to
  bottom without reconstructing hidden dependencies from multiple documents.
- If a previously closed phase reopens because the repository end state expands later,
  the top-level docs must say exactly which earlier phase reopened, which later phases
  remain closed on their owned surfaces, and why the overall handoff is still
  incomplete.

### B. Detailed, Implementation-Oriented Content

The plan is intentionally specific. It should not collapse into vague milestones or
project management summaries.

- Include concrete deliverables, canonical commands, validation gates, and exact
  blocked prerequisites when they materially clarify closure.
- Examples do not need to be verbatim copies of implementation files, but they must
  not contradict the supported architecture or command surface.
- Command examples must use the canonical binary name `jitml`. `jitml-demo`
  names only the Kubernetes Webapp workload, service, Helm release, and image
  tag for that same binary.
- Substrate identifiers are `apple-silicon`, `linux-cpu`, and `linux-cuda` on the CLI
  and in Dhall configuration. Substrate identifiers may not be renamed, abbreviated,
  or pluralised in plan or doctrine prose.
- JIT build source is not checked in as static substrate files. Any source code
  artefact needed to compile a JIT kernel, including CUDA `.cu`, C/C++ `.cc` /
  `.cpp`, generated Metal Shading Language, optional Swift package sources,
  native adapter shims, and per-substrate build `.sh` scripts, is generated on
  demand by the Haskell `jitml` binary into the content-addressed build/cache
  tree. Checked-in code may contain Haskell renderers, typed templates, the
  source for a fixed non-kernel host bridge, and tests for those renderers, but
  not ready-to-run per-kernel native/JIT source files, adapter shims, or build
  scripts. If a runtime path needs a per-kernel native adapter, it belongs in a
  Haskell renderer and is materialized under the generated build/cache tree;
  otherwise file lint rejects it. On `apple-silicon`, the core JIT cache-miss
  path renders MSL plus launch metadata into a content-addressed
  `<hash>.metal.json` source artifact and invokes a fixed host Metal bridge that
  calls `MTLDevice.makeLibrary(source:options:)` with fast math disabled before
  dispatching on the host GPU. The core path does **not** start Tart, require an
  unlocked keychain, invoke SwiftPM, require the offline `metal` compiler, or
  install full Xcode on the host. Optional generated Swift modules, if later
  enabled, are a separate capability gated by explicit `swiftc` + macOS SDK
  probes and are not the training/inference cache-miss path. Full detail lives in
  [../documents/engineering/apple_silicon_metal_headless_builds.md](../documents/engineering/apple_silicon_metal_headless_builds.md).
- Deprecated aliases or legacy command paths belong only in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

### C. Honest Completion Tracking

Status describes reality against the project's Exit Definition, not against an
intermediate scaffold layer. The Exit Definition is the numbered list in
[README.md → Exit Definition](README.md#exit-definition). Each sprint owns a
subset of those Exit Definition obligations; that subset is named in the
sprint's `### Objective` and `### Deliverables` blocks.

| Status | Meaning | Emoji |
|--------|---------|-------|
| **Done** | Every Exit-Definition obligation the sprint owns is met in the worktree, validated by the sprint's `### Validation` commands, and the listed docs are aligned. A sprint whose entire obligation is documentation, typed scaffolding, schema/ADT, generated-section, or pure-Haskell catalog work is legitimately Done when that surface is in place and tested; a sprint whose obligation includes live runtime behaviour (cluster up, Helm apply, Pulsar subscribe, MinIO put, kernel compile-and-execute, browser interaction, etc.) is Done only after that live behaviour is exercised through the sprint's validation. | ✅ |
| **Active** | Work has started and at least one owned Exit-Definition obligation is unmet. The sprint body lists those gaps in an explicit `### Remaining Work` block. | 🔄 |
| **Planned** | All upstream sprint dependencies are Done. The sprint has not yet started. It must list no unmet blockers. | 📋 |
| **Blocked** | At least one upstream sprint or external prerequisite required for this sprint's owned obligations is not Done. The sprint body lists the blockers in a `**Blocked by**:` line. | ⏸️ |

- `Done` requires passing validation, aligned docs, and zero remaining
  sprint-owned obligations against the Exit Definition.
- `Active` requires a `### Remaining Work` block that enumerates the unmet
  Exit-Definition obligations the sprint still owns and the validation commands
  that would close them.
- `Blocked` requires a `**Blocked by**:` line naming the upstream sprint id(s)
  or external prerequisite.
- `Planned` means dependencies are already satisfied; it must not list unmet
  blockers.
- Status applies to the full obligation, not to a checked-in scaffold layer.
  The plan does not distinguish a "local surface" Done from a "live runtime"
  Done — there is one Done bar, and it is the Exit Definition obligation.
- Primary unmet obligations do not flow into
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md); they
  remain in the owning sprint's `### Remaining Work` until closed. The legacy
  ledger tracks only doctrine deviations and temporary compatibility helpers
  per rule I.
- If Phase `0` is still open, later code-writing phases (Phases `1`–`12`) use
  `Blocked`, not `Planned`, since their owned surfaces depend on the
  doctrine-citation contract and the documentation-topology baseline that
  Phase `0` provides.
- Evidence gathered before a newly discovered or expanded obligation remains
  historical evidence for the surface it actually exercised; it cannot close
  the new obligation or be relabelled as current validation. The owning sprint
  reopens to `Active` only when all of its prerequisites are Done, otherwise it
  reopens to `Blocked`. `README.md` and `00-overview.md` call the reopening and
  the first executable owner out explicitly.

### D. Declarative Plan Language

Phase documents describe the intended architecture in present-tense declarative
language.

- Say what the repository uses, owns, validates, and removes.
- Do not turn phase docs into migration diaries.
- Cleanup history and compatibility residue belong in the explicit legacy-removal
  ledger, not as the main narrative of a phase.
- Active sprint bodies describe the end state in present tense; only the
  `### Remaining Work` subsection uses future/incomplete language.

### E. One Canonical Phase Model

The development plan uses exactly this document structure:

```text
DEVELOPMENT_PLAN/
├── development_plan_standards.md
├── README.md
├── 00-overview.md
├── system-components.md
├── legacy-tracking-for-deletion.md
├── phase-1-canonical-plan-suite-bootstrap.md
├── phase-2-doctrine-driven-scheduling-audit.md
├── phase-3-governed-document-metadata-enforcement.md
├── phase-4-toolchain-pin-and-library-first-cabal-project.md
├── phase-5-commandspec-registry-and-generated-parser.md
├── phase-6-generated-sections-and-tracking-generated-paths.md
├── phase-7-lint-stack-fourmolu-hlint-cabal-format-forbiddenpathregistry.md
├── phase-8-plan-apply-boundary-with-dry-run-and-plan-file.md
├── phase-9-subprocess-typed-values-runstreaming-capture-interpreter.md
├── phase-10-prerequisite-registry-as-typed-effects.md
├── phase-11-env-record-and-readert-env-io-runner.md
├── phase-12-apperror-adt-rendererror-output-rules.md
├── phase-13-scoped-allow-newer-retirement-gate.md
├── phase-14-ghc-9-12-4-baseline-and-dependency-helper-retirement.md
├── phase-15-cli-dhall-overrides.md
├── phase-16-remove-verify-cross-backend-add-jitml-test-test-options-pass.md
├── phase-17-reinstate-the-jitml-internal-vm-build-vm-command-surface.md
├── phase-18-retire-vm-lifecycle-commands-for-fixed-bridge-apple-metal.md
├── phase-19-remove-placeholder-top-level-cli-groups.md
├── phase-20-typed-numeric-cli-parsing-and-generated-only-command-referen.md
├── phase-21-structured-subprocess-outcomes.md
├── phase-22-stage-0-bootstrap-gates-and-delegation.md
├── phase-23-populated-prerequisiteregistry-and-lazy-remediation.md
├── phase-24-jit-cache-layout-and-content-addressing.md
├── phase-25-outer-container-linux-builds-and-jitml-local-image.md
├── phase-26-superseded-apple-silicon-vm-scaffold.md
├── phase-27-bootstrap-script-wrappers-and-status.md
├── phase-28-bootstrap-down-and-purge.md
├── phase-29-dhall-cluster-resource-profile-kind-node-cap-and-host-ram-pr.md
├── phase-30-reconciler-sh-c-control-flow-typed-haskell.md
├── phase-31-retire-the-tart-prerequisite-and-jitml-internal-vm-commands.md
├── phase-32-reinstate-the-tart-build-vm-prerequisite-and-lifecycle.md
├── phase-33-replace-tart-prerequisites-with-fixed-bridge-apple-cache-pre.md
├── phase-34-authenticated-third-party-image-pre-pull-before-kind-load.md
├── phase-35-in-cluster-docker-hub-imagepullsecret-authenticated-pod-pull.md
├── phase-36-durable-state-dhall-dsl-foundation-and-jitml-project-init.md
├── phase-37-per-substrate-kind-configs-and-extramounts.md
├── phase-38-kubernetes-io-no-provisioner-storage-and-manual-pvs.md
├── phase-39-envoy-gateway-and-single-127-0-0-1-edge-port-listener.md
├── phase-40-typed-route-registry-and-generated-httproute-manifests.md
├── phase-41-cluster-lifecycle-reconciler-and-phased-deploy.md
├── phase-42-ha-kind-node-and-manual-pv-topology.md
├── phase-43-live-cluster-lifecycle-and-publication-truth.md
├── phase-44-harbor-subchart-and-bootstrap-phase-install.md
├── phase-45-percona-pg-operator-and-patroni-managed-service-postgres.md
├── phase-46-minio-subchart-bucket-provisioning-conditional-write-server.md
├── phase-47-apache-pulsar-ha-and-topic-bootstrap.md
├── phase-48-kube-prometheus-stack-and-provisioned-dashboards.md
├── phase-49-tensorboard-with-minio-event-storage-and-checkpoint-sidecar.md
├── phase-50-nvidia-runtimeclass-for-linux-cuda.md
├── phase-51-per-pod-resource-limits-and-right-sized-replicas-from-the-dh.md
├── phase-52-project-the-durable-state-storeregistry-over-minio-buckets.md
├── phase-53-ha-platform-service-topology.md
├── phase-54-jitml-service-entry-point-and-lifecycle-summary.md
├── phase-55-bootconfig-liveconfig-dhall-and-hot-reload-schema-surface.md
├── phase-56-healthz-readyz-metrics-and-structured-logging.md
├── phase-57-retrypolicy-and-service-error-surface.md
├── phase-58-at-least-once-pulsar-consumer-with-message-hash-deduplicatio.md
├── phase-59-stateless-deployment-pod-anti-affinity-per-substrate-dhall.md
├── phase-60-typed-dhall-runconfig-and-bootconfig-mounted-worker-dispatch.md
├── phase-61-retire-tart-vm-lifecycle-from-the-daemon.md
├── phase-62-reinstate-the-dhall-configured-build-vm-block-and-daemon-acq.md
├── phase-63-replace-daemon-build-vm-acquire-with-metal-bridge-acquire.md
├── phase-64-workload-placement-planner-and-apple-host-workload-dispatch.md
├── phase-65-reflected-dhall-schema.md
├── phase-66-coordinator-topic-algebra.md
├── phase-67-one-binary-engine-coordinator-webapp-role-model.md
├── phase-68-reconcile-the-pulsar-topic-family-with-the-storeregistry.md
├── phase-69-one-numerical-worker-per-kubernetes-node.md
├── phase-70-fail-closed-mounted-worker-runconfig.md
├── phase-71-receipt-bound-delivery-and-total-settlement.md
├── phase-72-layer-catalog.md
├── phase-73-activations-real-and-complex.md
├── phase-74-spectral-frequency-domain-operations.md
├── phase-75-optimizers-and-schedulers.md
├── phase-76-loss-functions.md
├── phase-77-dhall-schemas-and-cross-type-audit.md
├── phase-78-kernelspec-cache-key-inputs-ffi-loader-surface.md
├── phase-79-engine-abi-and-engines-module-skeleton.md
├── phase-80-linux-cpu-engine-and-onednn-codegen-driver.md
├── phase-81-linux-cuda-engine-and-cuda-codegen-driver.md
├── phase-82-apple-silicon-engine-metal-codegen-host-forwarding-scaffoldi.md
├── phase-83-hardware-auto-tuning-within-the-determinism-contract.md
├── phase-84-haskell-owned-runtime-jit-source-generation.md
├── phase-85-headless-apple-metal-jit-runtime-compilation-host-swift-buil.md
├── phase-86-compose-gpu-service-split.md
├── phase-87-route-the-apple-swift-build-through-the-tart-vm.md
├── phase-88-fixed-host-metal-bridge-and-source-metadata-apple-cache.md
├── phase-89-local-supervised-canonical-summaries.md
├── phase-90-jitml-train-local-cli-summary.md
├── phase-91-rl-catalog-hook-for-canonical-tests.md
├── phase-92-rl-metadata-primitives.md
├── phase-93-rl-cli-summaries-and-report-hooks.md
├── phase-94-rl-training-plan-surface.md
├── phase-95-rlrunlifecycle-gadt-retrofit.md
├── phase-96-ale-boundary-and-rom-policy.md
├── phase-97-copyright-free-visual-rl-demo-environment.md
├── phase-98-sl-substrate-backed-training-real-eval.md
├── phase-99-rl-framework-substrate-routing.md
├── phase-100-no-caveat-sl-rl-framework-runtime.md
├── phase-101-real-sl-loss-validation-driven-selection-and-convergence-per.md
├── phase-102-fixed-budget-training-witness-and-inference-ineligible-parti.md
├── phase-103-typed-fail-closed-rl-device-errors.md
├── phase-104-validated-runplan-and-pure-contract-algebra.md
├── phase-105-on-policy-algorithm-metadata.md
├── phase-106-off-policy-algorithm-metadata.md
├── phase-107-specialised-algorithm-metadata.md
├── phase-108-local-rl-canonical-tests.md
├── phase-109-alphazero-connect-4-transcript-surface.md
├── phase-110-connect-4-local-game-surface.md
├── phase-111-hyperparameter-tuning-sampler-scheduler-pruner.md
├── phase-112-copyright-free-rl-matrix-retargeting.md
├── phase-113-real-rl-eval-rollout-and-per-algorithm-on-device-rollouts.md
├── phase-114-real-mcts-tree-search-with-substrate-backed-leaf-evaluation.md
├── phase-115-real-hyperparameter-tuning-objective-executor.md
├── phase-116-no-caveat-rl-alphazero-and-tuning-runtime.md
├── phase-117-real-rl-convergence-performance-metrics-and-the-alphazero-ar.md
├── phase-118-all-rl-fixed-budget-convergence-metrics.md
├── phase-119-typed-tuning-resume-decode-failures.md
├── phase-120-tuning-override-and-worker-axis-fidelity.md
├── phase-121-resolved-alphazero-and-tuning-plans.md
├── phase-122-storage-layout-and-split-blob-schema.md
├── phase-123-jmw1-wire-format-and-manifest-cbor.md
├── phase-124-bit-determinism-contract-and-retention-reconciler.md
├── phase-125-inference-only-read-path.md
├── phase-126-remove-the-synthetic-inference-offset.md
├── phase-127-exact-v2-supervised-runtime-artifact.md
├── phase-128-async-work-inference-workflow-and-ready-readiness-gate.md
├── phase-129-typed-retentionpolicy-replaces-the-lastn-5-literal.md
├── phase-130-real-trained-demo-checkpoints-delete-the-synthetic-weight-ra.md
├── phase-131-inference-eligible-checkpoints-and-convergence-statistics.md
├── phase-132-typed-checkpoint-object-key-validation.md
├── phase-133-persisted-checkpoint-proof-admission.md
├── phase-134-minimal-purescript-application-scaffold.md
├── phase-135-browser-contract-adts-and-local-contract-rendering.md
├── phase-136-jitml-lint-purescript-generated-contract-smoke-target.md
├── phase-137-interactive-endpoint-contract-surface.md
├── phase-138-webapp-route-and-deployment-surface.md
├── phase-139-playwright-e2e-suite.md
├── phase-140-spa-portals-home-and-shared-header.md
├── phase-141-demo-endpoints-render-real-substrate-output.md
├── phase-142-full-interactive-demo-surface.md
├── phase-143-webapp-role-and-websocket-driven-inference-panels.md
├── phase-144-all-model-trained-artifact-ui-and-admin-navigation.md
├── phase-145-jitml-unit-stanza.md
├── phase-146-jitml-integration-stanza-subprocess-boundary-determinism.md
├── phase-147-jitml-sl-canonicals-stanza.md
├── phase-148-jitml-rl-canonicals-stanza.md
├── phase-149-jitml-hyperparameter-stanza.md
├── phase-150-jitml-cross-backend-stanza.md
├── phase-151-jitml-daemon-lifecycle-stanza.md
├── phase-152-jitml-e2e-stanza-and-live-plan-orchestrator.md
├── phase-153-jitml-test-all-orchestrator-and-report-card.md
├── phase-154-substrate-partitioned-test-lanes-remove-the-cross-substrate.md
├── phase-155-dry-real-workflow-matrix-fail-closed.md
├── phase-156-live-job-failure-observation-and-apple-placement-assertions.md
├── phase-157-playwright-no-caveat-e2e-matrix.md
├── phase-158-common-shape-workflow-topic-algebra-and-websocket-coverage.md
├── phase-159-per-model-integration-and-e2e-matrix.md
├── phase-160-functional-core-live-workflow-interpreter.md
├── phase-161-full-canonical-model-matrix-runtime.md
├── phase-162-re-attest-the-no-caveat-runtime-with-real-losses-metrics.md
├── phase-163-fixed-budget-all-model-runtime-gate-linux-cpu.md
├── phase-164-full-workflow-control-surface.md
├── phase-165-playwright-no-caveat-product-matrix.md
├── phase-166-real-demo-inference-full-width-multi-layer-forward-real-inpu.md
├── phase-167-all-model-browser-and-playwright-trained-artifact-matrix.md
├── phase-168-ephemeral-kind-helm-rollout.md
├── phase-169-live-capability-class-validation-minio-pulsar-harbor.md
├── phase-170-daemon-training-rl-tune-handlers-on-live-broker.md
├── phase-171-live-sl-training-e2e-with-real-datasets.md
├── phase-172-real-rl-environment-simulators-and-daemon-env-loop.md
├── phase-173-live-rl-training-e2e-with-statistical-convergence-assertions.md
├── phase-174-live-minio-checkpoint-round-trip-and-retention.md
├── phase-175-real-cuda-rl-algorithm-losses-through-jit-engine.md
├── phase-176-alphazero-with-real-network-priors.md
├── phase-177-live-tuning-sweep-with-minio-trial-persistence.md
├── phase-178-cuda-and-linux-cpu-production-weight-loading.md
├── phase-179-live-jitml-inference-run-and-legacy-replay-helper.md
├── phase-180-live-api-ws-websocket-proxy-and-compiled-halogen-bundle.md
├── phase-181-live-playwright-on-demo-edge-route.md
├── phase-182-linux-cpu-full-tensor-benchmark-payloads-and-first-cache-mis.md
├── phase-183-re-validate-the-linux-cuda-lane-runs-for-real-with-the-skip.md
├── phase-184-live-linux-cpu-exercise-of-the-reopened-workflows.md
├── phase-185-live-linux-cuda-exercise-of-the-reopened-workflows.md
├── phase-186-live-cluster-closure-of-the-reopened-workflows.md
├── phase-187-linux-no-caveat-runtime-and-browser-lane.md
├── phase-188-linux-cuda-all-model-trained-artifact-lane.md
├── phase-189-linux-cuda-ha-cluster-revalidation.md
├── phase-190-host-swift-toolchain-and-first-cache-miss-headless-build.md
├── phase-191-metal-ffi-loading-and-host-kernel-launch.md
├── phase-192-metal-benchmark-candidate-runner-live-execution.md
├── phase-193-apple-host-cluster-pulsar-rpc-live-flow.md
├── phase-194-apple-metal-production-weight-loading.md
├── phase-195-re-validate-the-apple-silicon-lane-runs-for-real-with-the-sk.md
├── phase-196-re-validate-the-apple-silicon-lane-through-the-tart-vm-built.md
├── phase-197-retired-vm-path-apple-silicon-workflow-attempt.md
├── phase-198-live-fixed-bridge-apple-silicon-workflow-closure.md
├── phase-199-live-apple-host-resident-workload-closure.md
├── phase-200-apple-no-caveat-runtime-and-browser-lane.md
├── phase-201-apple-silicon-all-model-trained-artifact-lane.md
├── phase-202-apple-silicon-ha-cluster-revalidation.md
├── phase-203-cross-substrate-cohort-runs-and-in-code-tolerance-bands.md
├── phase-204-live-jitml-test-all-report-card-with-measured-metrics.md
├── phase-205-empty-legacy-ledger-and-final-handoff.md
├── phase-206-remove-the-cross-substrate-parity-surface-reframe-the-determ.md
├── phase-207-cross-substrate-real-workflow-confirmation.md
├── phase-208-real-workflow-ledger-walk-down-and-final-handoff.md
├── phase-209-apple-placement-ledger-walk-down-and-final-handoff.md
├── phase-210-expanded-no-caveat-report-card-and-ledger-handoff.md
├── phase-211-expanded-all-model-lane-fragment-handoff.md
├── phase-212-ha-topology-aggregation.md
├── phase-213-three-substrate-no-caveat-handoff.md
├── phase-214-re-aggregate-the-no-caveat-handoff-after-the-durable-state-d.md
├── phase-215-re-aggregate-the-no-caveat-handoff-after-the-real-sl-rl-chai.md
├── phase-216-re-aggregate-after-fixed-budget-all-model-closure.md
├── phase-217-ha-topology-product-handoff.md
├── phase-218-re-aggregate-after-typed-failure-and-docs-governance-remedia.md
├── phase-219-re-aggregate-after-real-cluster-tuning-runconfig-remediation.md
├── phase-220-product-matrix-authority.md
├── phase-221-phase-status-registry.md
├── phase-222-status-truth-enforcement.md
├── phase-223-product-registry-plan-and-admitted-evidence-projection.md
├── phase-224-remove-fossils.md
├── phase-225-scaffold-lint-reachability.md
├── phase-226-non-fabricable-training-evidence.md
├── phase-227-type-state-pipeline-haskell.md
├── phase-228-dhall-boundary-fail-closed-decode.md
├── phase-229-phase-specific-product-evidence-payloads.md
├── phase-230-matrix-parity.md
├── phase-231-per-row-runnable-dhall.md
├── phase-232-read-time-dataset-sha.md
├── phase-233-typed-layer-ir-reverse-mode-autodiff.md
├── phase-234-onednn-layer-kernels-for-training.md
├── phase-235-one-self-describing-checkpoint-envelope.md
├── phase-236-checkpoint-admission-single-path.md
├── phase-237-supervised-serving-on-the-layer-graph-ir.md
├── phase-238-supervised-training-on-the-layer-graph-ir.md
├── phase-239-checkpoint-construction-from-the-trained-graph.md
├── phase-240-layer-graph-checkpoints-inference.md
├── phase-241-onednn-device-training-kernels-for-correct-operators.md
├── phase-242-literal-architectures-dense-mlp-lenet.md
├── phase-243-literal-architectures-resnet-family.md
├── phase-244-literal-architectures-vision-transformer.md
├── phase-245-convergence-and-evidence.md
├── phase-246-completedtraining-sl-manifests.md
├── phase-247-real-environments.md
├── phase-248-distinct-algorithms.md
├── phase-249-per-row-convergence-and-evidence.md
├── phase-250-typed-rl-cohort-and-action-domain-compatibility.md
├── phase-251-trainingplan-evaluationplan-compiler-and-trainer-migration.md
├── phase-252-typed-measured-counters-and-evidence-separation.md
├── phase-253-per-game-self-play.md
├── phase-254-arena-convergence-evidence.md
├── phase-255-train-and-publish-artifact-selectors.md
├── phase-256-row-specific-renderers.md
├── phase-257-browser-fail-closed.md
├── phase-258-row-keyed-integration-matrix.md
├── phase-259-row-complete-playwright.md
├── phase-260-linux-cpu-report-card.md
├── phase-261-contract-driven-live-execution-integration-journal.md
├── phase-262-contract-driven-live-execution-browser-and-playwright.md
├── phase-263-contract-driven-live-execution-fragment-issuance.md
├── phase-264-real-cudnn-cublas-kernels.md
├── phase-265-cuda-row-device-evidence.md
├── phase-266-cuda-integration-e2e-and-attestation.md
├── phase-267-gpu-performance-and-persistent-device-buffers.md
├── phase-268-contract-driven-cuda-lane-revalidation.md
├── phase-269-real-metal-kernels.md
├── phase-270-metal-row-device-evidence.md
├── phase-271-apple-integration-e2e-and-attestation.md
├── phase-272-contract-driven-apple-lane-revalidation.md
├── phase-273-attestation-join.md
├── phase-274-no-caveat-closure-guard.md
├── phase-275-journal-derived-product-aggregation.md
├── phase-276-negative-control-suite.md
├── phase-277-external-bars-no-self-referential-gate-lint-and-exact-served.md
├── phase-278-measured-declared-type-split-behavioral-scaffold-lint.md
├── phase-279-runcontract-negative-controls-request-and-event-fixtures.md
├── phase-280-runcontract-negative-controls-journal-fixtures-and-reducer-p.md
├── phase-281-runcontract-negative-controls-lifecycle-and-per-row-registra.md
├── phase-282-per-model-measured-convergence.md
├── phase-283-inference-performance-determinism.md
├── phase-284-contract-driven-per-model-evidence.md
├── phase-285-evidence-derived-closure-guard.md
├── phase-286-standing-adversarial-audit-thin-plan.md
├── phase-287-journal-derived-status-registry.md
├── phase-288-evidence-typed-report-measurements.md
```

No phase may be skipped. No sprint may exist in two phases. CLI-surface ownership,
bootstrap-reconciler ownership, cluster-substrate ownership, platform-services
ownership, daemon ownership, numerical-core ownership, per-substrate JIT-codegen
ownership, SL/RL-framework ownership, RL-algorithm/AlphaZero/tuning ownership,
checkpointing ownership, frontend ownership, test-stanza ownership, no-caveat
model-runtime closure ownership, interactive-demo/Playwright closure ownership,
Linux-CUDA/cluster-closure ownership, Apple-Silicon-closure ownership,
cross-substrate-handoff ownership, historical no-caveat product-handoff
ownership, product-truth gate ownership, de-fossilization/scaffold-lint
ownership, type-state/inference-eligibility ownership, canonical
matrix/dataset-integrity ownership, general differentiable-layer-engine
ownership, real supervised-architecture ownership, real
RL-algorithm/environment ownership, AlphaZero real-self-play ownership,
all-model demo-rendering ownership, per-model integration/e2e ownership,
linux-cuda product-lane ownership, apple-silicon product-lane ownership, and
final no-caveat aggregation ownership each live in one place only.

The 2026-07-12 typed-run-contract audit reopened existing owners instead of
adding a Phase `35`; its completed process, delivery, plan, and interpreter
prefix remains historical evidence for those retained surfaces. The 2026-07-18
checkpoint/runtime audit found that supervised publisher artifacts were written
through a name-derived generic checkpoint path, carried no executable runtime
payload, and could be labelled eligible without exact persisted-byte admission.
It therefore reopens the existing Phase `10`, `19`, `23`, `24`, and `32` owners.
The strict forward chain runs `1 → … → 288` in the single-session numbering.
The 2026-07-26 IR-single-owner `+4` renumber inserted Phases `236`–`239` and
shifted the former tail `236`–`283` to `240`–`287`; Phase `288` is the later
evidence-typed report-measurement owner. The current open suffix (the phases not
yet Done) is `262 → 263 → 268 → 272 → 275 → 277 → 279 → 280 → 281 → 284 → 287 → 288`. Sprint `23.1` is Done — its correct reverse-mode autodiff node
library over the typed `LayerGraph` IR is finite-difference-validated, its
`cifar10-vit` convergence go/no-go returned GO, and the vacuous convergence bars
are resolved (served-path Tier-2 wiring and the attention residual add are now
handled by the IR redesign in Phases `235`–`239`). Phases `234` (oneDNN layer
kernels for training, including the batched IR kernels), `235` (the one
self-describing checkpoint envelope collapsing the V1/V2/V3 wire versions), and
`236` (the checkpoint admission single-path collapsing the version-gated store
admission) all closed `Done` on 2026-07-27. Phases `237` (supervised serving on
the IR) and `238` (supervised training on the IR) closed `Done` on 2026-07-28;
Phase `239` (checkpoint construction from the trained graph) closed `Done` on
2026-07-28; Phases `240`–`246` (the coupled literal-architecture landing) closed
`Done` on 2026-07-30; Phase `250` (Typed RL Cohort) closed `Done` on 2026-07-30; Phases `251` (TrainingPlan/EvaluationPlan Compiler and Trainer Migration) and `252` (Typed Measured Counters and Evidence Separation) closed `Done` on 2026-07-31. Phase `261` closed `Done` on 2026-08-01 after immutable-image integration **161 / 161** (Phase `261` subtree **60 / 60**), unit **772 / 772**, authenticated ordered version-`3` **55-row** aggregate plus exact Store re-admission, live **9-component** and **12-dataset-object** checks, docs check, and check-code passed. The Phase `19`–`34` status checkpoint is **57 Done / 1 Active / 0 Planned / 11 Blocked**. Phase `262` is Active; every later phase in that chain is Blocked by its immediate predecessor, and the apple-silicon wall at Phase `272` remains the hard stop on non-Apple hosts. Untouched
phases remain Done on their retained surfaces, but the overall product handoff
is incomplete until this chain closes. Sprints `29.5` and `30.4` independently
refresh the `linux-cuda` and `apple-silicon` evidence; Sprint `31.3` aggregates
their committed journals on `linux-cpu` without re-running an accelerator.

The 2026-07-15 retained-cluster audit additionally reopened Sprint `2.9` and
Sprint `3.7` after the typed bootstrap migration proved to have dropped its
Kind existence branch. Sprint `2.9` has re-closed on the typed retained-cluster
recovery branch, and Sprint `3.7` has re-closed after two supported
`linux-cpu` reconciles proved durable topic convergence, retained identity,
exact image authority, publication/stamp stability, and the steady-state
exit-`3` no-op result. Sprint `12.16` has also re-closed after its immutable-
image six-command `linux-cpu` block, docs/code-quality gates, and independent
resource checks passed. Those retained-cluster and shared-interpreter closures
precede the current numerical open suffix above. They do not override the
closed Phase `10` checkpoint/runtime owner or invalidate unrelated closed
owners.

The closure phases form a **forward chain** (renumbered 2026-06-16 per the
forward-DAG doctrine in rule M): Phase `13` owns the full no-caveat model runtime
(consuming the reopened Phases `8`–`10`), Phase `14` owns the browser product
surface plus Playwright assertions for that runtime, and both close on the
always-available `linux-cpu` lane. Phases `15`–`17` then carry every live-runtime
obligation extracted from Phases `7`–`14` and consolidate it by machine-affinity
so each phase is independently closeable on a single host with **at most one**
accelerator plus `linux-cpu`: Phase `15` is the `linux-cuda` live lane (NVIDIA
host), Phase `16` is the `apple-silicon` live lane (Mac host, independent of Phase
`15`), and Phase `17` aggregates within-substrate reproducibility from the
committed per-lane artifacts on `linux-cpu`. Phase `18` is the final
`linux-cpu`-only handoff that merges the per-lane evidence into one no-caveat
report card. Every Blocked-by and dependency edge references a strictly
lower-numbered phase (rule M), so the plan is workable in numerical order.

The 2026-07-01 product-truth reopen extends that forward chain without
modifying the owned closure of Phases `0`–`18`, and the user elected to
implement every row **for real** — the plan narrows nothing by documentation;
each obligation is closed by real training, real inference, and real kernels.
Phase `19` installs the typed product-truth gates, the single `ProductRow`
registry, a matrix floor, per-row convergence bars, and the typed Phase `19`–`34`
sprint-status registry that downstream closure gates consume. Phase `20`
removes the legacy fake-ML fossils and installs the forbidden-scaffold +
import-edge lint. Phase `21` makes inference eligibility a type-state property
and training evidence non-fabricable. Phase `22` makes the canonical matrix and
dataset-integrity boundary singular. Phase `23` builds the general
differentiable layer engine — reverse-mode autodiff over the full layer catalog
wired to real oneDNN. Phase `24` closes the real, literal supervised
architectures. Phase `25` closes the real, genuinely-distinct RL algorithms and
environments. Phase `26` closes real AlphaZero self-play per game. Phase `27`
renders every row from real artifacts in the demo. Phase `28` gives every row
integration and e2e coverage on `linux-cpu`. Phase `29` validates the product
matrix on the `linux-cuda` lane with real cuDNN/cuBLAS kernels. Phase `30`
validates it on the `apple-silicon` lane with real Metal kernels. Phase `31` is
the `linux-cpu`-only aggregation and handoff. Phases `19`–`28` and `31` are
`linux-cpu` only; Phase `29` may require `linux-cuda`; Phase `30` may require
`apple-silicon`; no phase may require both accelerators.

### F. System Component Inventory

[system-components.md](system-components.md) is the authoritative component inventory
for:

- substrates and their JIT-cache homes
- CLI surfaces and runtime controls (subcommand families)
- stateful platform services (Harbor, MinIO, Pulsar, PostgreSQL, observability)
- the `jitml service` daemon (BootConfig / LiveConfig surfaces, capability classes)
- numerical-core ADTs (layer catalog, optimizers, schedulers, losses) and Dhall types
- per-substrate JIT source renderers, generated-on-demand codegen artefacts, and
  content-addressed cache layout
- training-workload surfaces (SL loops, RL framework, RL catalog, AlphaZero, tuning)
- validated kind-indexed run plans, dimensional budgets, protocol event/evidence
  reducers, receipt-bound broker delivery, lifecycle state, scenario journals,
  structured process/suite outcomes, and report projections
- checkpoint format and inference-only read path
- frontend bundle and generated browser-contract surfaces
- test stanzas, lint matrix, and ephemeral-cluster infrastructure surfaces
- toolchain prerequisites and pinned versions
- state locations (cache root, kubeconfig, Kind metadata, runtime metadata,
  manual PV root, snapshot roots)

When a phase changes the supported architecture, update the inventory in the same
change.

### G. Phase Documentation Requirements

Every phase document must contain a `Documentation Requirements` section that lists
which governed documents need creation or update under
[../documents/documentation_standards.md](../documents/documentation_standards.md).

Use this format:

```markdown
## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/X.md` — [description]

**Product docs to create/update:**
- None.

**Cross-references to add:**
- Add backlink from Z.md
```

Rules:

- Architecture, command-surface, determinism-contract, daemon-architecture,
  cluster-topology, JIT-codegen, numerical-core, training-workload, checkpoint-format,
  and frontend changes require engineering-document updates.
- The plan must not claim a sprint is done if the listed docs are stale.
- If the repository has no product-doc ownership for a phase, say `None.` explicitly.

### H. Sprint Status Format

Every sprint uses the same basic structure:

```markdown
## Sprint X.Y: Name [STATUS]

**Status**: Done | Active | Planned | Blocked
**Implementation**: `path/to/file` (required for Done, recommended otherwise)
**Blocked by**: sprint id(s) or external prerequisite (required for Blocked)
**Docs to update**: `file.md`, `other.md`

### Objective

### Deliverables

### Validation

### Remaining Work
```

Additional sections such as `Current Validation State`, `Current Blockers`,
`Architecture`, `Schema`, or `Substrate Notes` are encouraged when they clarify
design or closure.

### I. Explicit Cleanup and Removal Ledger

[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) is mandatory and
comprehensive. It is the authoritative list of all known compatibility helpers,
deprecated paths, duplicate surfaces, and stale tooling residue that still need
removal.

- If a deprecated or compatibility feature exists anywhere in the repository, it must
  appear in the ledger.
- Each ledger item must name its location, why it is slated for removal, and the
  sprint that owns the cleanup.
- When the cleanup lands, move the item from `Pending Removal` to `Completed`.
- Phase docs reference the owning sprint, not duplicate the full cleanup ledger.
- The ledger began empty during the clean-room planning pass. Once source code
  exists, the ledger must reflect the actual worktree: pending compatibility
  helpers, deprecated paths, and stand-ins are listed under `Pending Removal`, and
  completed removals are moved to `Completed`.

### J. Documentation Harmony

The plan and governed documents must agree.

- [README.md](README.md), [00-overview.md](00-overview.md), every phase file, and
  [system-components.md](system-components.md) must use the same phase names, sprint
  statuses, substrate identifiers, and dependency model.
- Governed docs under `documents/engineering/` must match the current architecture
  described by the plan.
- Root guidance docs `README.md`, `AGENTS.md`, and `CLAUDE.md` must point to the
  project [../README.md](../README.md) and
  [DEVELOPMENT_PLAN/README.md](README.md).

### K. Mermaid Rendering Contract

Mermaid diagrams in `DEVELOPMENT_PLAN/` must follow the repository-safe subset and
authoring rules defined in
[../documents/documentation_standards.md](../documents/documentation_standards.md).

If a change adds or edits a Mermaid block in this directory, closure requires:

1. Rendering every Mermaid block in `DEVELOPMENT_PLAN/` through a standalone
   renderer.
2. Failing the change on any render error.
3. Verifying the edited diagram in the repository's target Markdown viewer.
4. Running `jitml check-code` inside `jitml:local` after the documentation change
   (once Phase 1 lands the command; until then, the lint stack is run manually
   inside the container through `fourmolu --mode check`, `hlint`, and
   `cabal format`).

This standards document describes Mermaid rules with prose, inline code, or
`markdown` examples only. Do not add live Mermaid blocks here.

### L. Project Doctrine Alignment

[../README.md](../README.md) is the authoritative project and CLI doctrine.
Phase documents and sprint blocks that schedule adoption work must cite the doctrine
sections they implement by name (for example, `CommandSpec`, `Plan / Apply`,
`Subprocesses as Typed Values`, `Prerequisites as Typed Effects`, `Application
Environment`, `Long-Running Daemons in the Same Binary`, `Reconcilers: Idempotent
Mutation as a Single Command`, `At-Least-Once Event Processing`, `Capability Classes
and Service Errors`, `Retry Policy as First-Class Values`, `Lint, Format, and
Code-Quality Stack`, `Generated Artifacts → The generated-section registry`,
`Test Organization`, `Output Rules`, `Error Handling`, `Typed Run Contracts`,
`Toolchain pinning`, `Project Structure`).

- Governed engineering docs under `documents/engineering/` referenced from the
  README's `Referenced by` line must defer to the README for the patterns it owns
  and retain only project-specific elaborations such as substrate identifiers,
  Pulsar topic names, the Envoy Gateway socket convention, JIT-cache content-
  addressing, RL-algorithm identifiers, AlphaZero loop, or the checkpoint wire
  format.
- The jitML adoption envelope of the doctrine is bounded: the in-scope and
  out-of-scope splits live in [00-overview.md](00-overview.md) `Doctrine Scope` and
  are inherited verbatim from the project [../README.md](../README.md) `Doctrine
  scope` section. No sprint may schedule adoption of an out-of-scope doctrine
  section.
- When the doctrine prescribes a behavior that the implemented worktree does not yet
  honor and the section is in scope, the gap is scheduled through a sprint
  deliverable in the appropriate phase. Closing the gap silently without a sprint
  binding is forbidden.
- Doctrine-driven removals — superseded helpers, deprecated CLI flags, parallel
  workflow surfaces — flow through
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) like any other
  cleanup.
- If a doctrine section changes, the same change updates every governed doc that
  references it.

### M. Forward-Only, Single-Accelerator, Numerically-Ordered Phases

This rule is the binding form of the project doctrine
[Substrate-Affinity Phasing](../README.md#substrate-affinity-phasing) (in the
[../README.md](../README.md) `Doctrine scope` registry). Its two primary
invariants are **(a) Forward-Only Phase Dependencies** and **(b)
Single-Accelerator Phase Validation**; **(c) numerical-order execution** and
**(d) single-host closeability** are corollaries. The phase graph is a strict
forward DAG that is workable in numerical order, and every phase closes on one
host with at most one accelerator. These four invariants are mandatory; any plan
change that would violate one is rejected, and the `### M. Enforcement` checks
below make the plan self-policing. Invariants (a) and (b) are shared verbatim with
the `infernix` sister project as the cross-project
[Pulsar ML-Workflow Contract](../documents/engineering/pulsar_ml_workflow.md)
(`Phasing rules`), so both repos converge on one forward-only,
single-accelerator-per-phase shape.

- **(a) Forward-only dependencies.** A phase's owned obligations, its sprints'
  `**Blocked by**:` lines, and every dependency edge it declares may reference
  only **equal-or-lower-numbered** phases and sprints. A later phase must never
  appear in an earlier phase's `Blocked by`. A later phase *may* own an obligation
  migrated out of an earlier phase — that is an ownership transfer (the earlier
  phase's `Done` is then defined on its retained surface only), not a blocker.
  Phases `0`–`12` retain forward "deferral" prose only as ownership transfers to
  the downstream owner, never as blockers.
- **(b) Single accelerator per phase.** No single phase's closure may require both
  `apple-silicon` and `linux-cuda`. A phase that needs an accelerator selects
  **exactly one** of `{linux-cuda, apple-silicon}` plus `linux-cpu`. A contract
  that must hold on both accelerators is split into two sibling phases (one per
  accelerator) or attested per-lane in independent sessions and aggregated by a
  later `linux-cpu`-only phase. A phase's `### Validation` block must not list a
  single must-pass-together gate spanning both accelerators.
- **(c) Numerical-order execution.** The plan is workable strictly in numerical
  order: every `Depends-On`/`Blocked by` edge references a strictly lower number
  (a consequence of (a)), and each phase is **fully validated** — its owned
  Exit-Definition obligations met per rule C — before the next phase begins.
- **(d) Single-host closeability.** Each phase is fully closeable in a single
  machine session on a single host: a `linux-cpu`-only phase closes on any Docker
  host; a `linux-cuda` phase closes on the NVIDIA host (which also provides
  `linux-cpu`); an `apple-silicon` phase closes on the Mac host (which also
  provides `linux-cpu`). No phase requires two hosts. Cross-substrate
  reproducibility and final handoff are therefore `linux-cpu`-only **aggregation**
  phases that consume per-lane artifacts committed by the earlier
  single-accelerator phases — they never re-run an accelerator lane.

Already-`Done` phases whose historical Validation listed all three substrates in
one block (for example, the per-lane SL/RL/e2e gates) are re-documented as
**validated per-lane in separate single-host sessions** to satisfy (b)/(d); this
is a documentation note, not a code change, and does not reopen them. When the
closure phases are renumbered to honor (a)–(d), the renumbering is recorded at the
top of [README.md](README.md) `Closure Status` with an explicit old→new map.

#### M. Enforcement

Invariants (a) and (b) are machine-checkable, so the plan polices itself rather
than relying on reviewer vigilance. Scans 1 and 2 below are **automated** in the
`jitml-unit` "Product phase status registry" group (the
`every dependency edge is forward-only`,
`every sprint declares a concrete validation gate`, and
`no sprint validation requires both accelerators` cases parse every registered
phase document); scan 3 remains a documented deterministic scan run alongside
`jitml check-code` / `jitml docs check` in the maintenance pass. A plan change
closes only when all three report their zero-tolerance count. Each check is a
deterministic scan over `phase-*.md` (no model judgement required):

1. **Zero backward edges — enforces (a)/(c).** Build the dependency graph from
   every sprint `**Blocked by**:` line and every declared dependency edge; the
   pass condition is **0 edges** pointing from a lower-numbered phase/sprint to a
   higher-numbered one. Ownership-transfer prose is not an edge and is excluded by
   construction. (Reference scan: for each `phase-N-*.md`, every `N'.M` and
   `Phase N'` named in a `**Blocked by**:` line satisfies `N' <= N`.)
2. **No dual-accelerator validation gate — enforces (b).** For every phase, **no
   single `### Validation` gate** names both an `apple-silicon` lane
   (`--apple-silicon` / `apple-silicon.sh`) and a `linux-cuda` lane
   (`--linux-cuda` / `linux-cuda.sh` / `-fcuda`). A phase may name both
   accelerators only across *separate* per-lane gates, or as historical /
   aggregation prose — never in one must-pass-together gate. Pass condition:
   dual-accelerator-gate count == 0.
3. **Aggregation-phase no-rerun — enforces (d).** A `linux-cpu`-aggregation
   phase's `### Validation` contains only `--linux-cpu` invocations plus
   "merge committed per-lane fragment" steps — no `-fcuda` / `--apple-silicon`
   lane re-runs. Pass condition: per such phase, accelerator-invocation count == 0.

Scans 1 and 2 are implemented as the `jitml-unit` phase-status guards named
above (`test/unit/Main.hs`, parsing `**Blocked by**:` edges and `### Validation`
blocks per registered phase document); a plan change that introduces a backward
edge, a sprint with no validation gate, or a dual-accelerator gate fails
`jitml-unit`. Scan 3 (aggregation no-rerun) remains the documented deterministic
scan run before closing a plan change.

### N. Evidence-Derived Product Status and Thin Closure Narrative

Product closure status is derived from executable evidence, not from narrative
prose. A phase or sprint in the product chain may be marked `Done` only when its
validation stanza(s), docs check, and code-quality gate have passed in the
container lane named by that phase. The standing realness gate consists of
`jitml-negative-controls`, `jitml-model-convergence`, typed-run-contract reducer
negative controls, the product phase-status guard in `jitml-unit`, exact
per-lane scenario journals, `jitml docs check`, and `jitml check-code`.

Closure evidence is the structured result of the execution it claims. A later
probe, declared target list, hand-maintained status literal, or reconstructed
pass count cannot substitute for an invocation transcript or completed scenario
journal. Fail-fast targets remain `NotRun`; unavailable measurements carry a
reason; failed process evidence retains both output streams.

`README.md → Closure Status` stays thin: it names the current status, the
validation commands and pass counts, and links to the historical audit narrative
instead of accumulating a per-commit closure diary. If a recurring adversarial
realness audit finds a contradiction between status and evidence, the audit
finding defines status and the owning phase moves back to `Active` until its
standing gate passes again.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [../README.md](../README.md)
- [../documents/documentation_standards.md](../documents/documentation_standards.md)

## Cross-Reference Conventions

- Links inside `DEVELOPMENT_PLAN/` use relative paths.
- Links to governed docs under `documents/` use repository-relative paths
  (`../documents/...`).
- Links to project doctrine use `../README.md`.
- File renames require same-change link updates everywhere the file is referenced.

## Maintenance Guidelines

1. Update the global control documents first: `README.md`, `00-overview.md`, and
   `system-components.md`.
2. Update the affected phase document next.
3. Update the governed engineering docs listed in `Docs to update`.
4. Update [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) whenever
   cleanup scope changes.
5. Run the three `### M. Enforcement` deterministic scans over `phase-*.md` and
   confirm each reports its zero-tolerance count (0 backward edges; 0
   dual-accelerator validation gates; 0 accelerator re-runs in an aggregation
   phase). A non-zero count blocks closure.
6. Run `jitml check-code` inside `jitml:local` before closing the work (once Phase
   1 lands the command; until then, run `fourmolu --mode check`, `hlint`, and
   `cabal format` manually inside the container).
7. If the change touched Mermaid, render every Mermaid block in `DEVELOPMENT_PLAN/`
   and verify the edited diagram in the target viewer before closing the work.
