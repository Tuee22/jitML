import * as pulumi from "@pulumi/pulumi";
import { local } from "@pulumi/command";

// Ephemeral Kind orchestrator for the `jitml-e2e` stanza. The stack lifecycle is:
//
//   pulumi up:
//     1. `kind create cluster --name jitml-e2e-<stack> --config kind/cluster-linux-cpu.yaml`
//        with `--kubeconfig ./.build/jitml-e2e.kubeconfig`.
//     2. `helm dependency build chart`.
//     3. `.build/jitml bootstrap --linux-cpu` (the Haskell binary drives the
//        phased Helm rollout per JitML.Cluster.Helm.helmPhasedRolloutPlan).
//     4. The demo cohort reaches Ready behind the leased Envoy listener.
//
//   pulumi destroy:
//     5. `.build/jitml cluster down` deletes the Helm releases in reverse
//        phase order.
//     6. `kind delete cluster --name jitml-e2e-<stack>`.
//     7. The teardown assertion in `test/e2e/Main.hs` confirms no stranded
//        Kind cluster, Harbor project, MinIO bucket, or Docker volume
//        remains.
//
// Invoked explicitly by the `jitml-e2e` live orchestration path; the Cabal
// stanza validates the typed scaffold in `JitML.Test.LivePlan`.

const config = new pulumi.Config();

export const stackName = pulumi.getStack();
export const clusterName = `jitml-e2e-${stackName}`;
export const kubeconfigPath = config.get("kubeconfig") ?? `./.build/${clusterName}.kubeconfig`;
export const substrate = config.get("substrate") ?? "linux-cpu";
export const chartPath = config.get("chartPath") ?? "chart";
export const jitmlBinary = config.get("jitmlBinary") ?? ".build/jitml";

const kindConfigPath = config.get("kindConfig") ?? `kind/cluster-${substrate}.yaml`;

// Step 1 — Kind cluster create.
const kindCluster = new local.Command("kind-cluster", {
  create: pulumi.interpolate`kind create cluster --name ${clusterName} --config ${kindConfigPath} --kubeconfig ${kubeconfigPath}`,
  delete: pulumi.interpolate`kind delete cluster --name ${clusterName}`,
  triggers: [clusterName, substrate, kindConfigPath],
});

// Step 2 — `helm dependency build chart`. Sequenced after the cluster so the
// kubeconfig is present when the chart's subchart pulls reference cluster
// credentials.
const helmDeps = new local.Command(
  "helm-deps",
  {
    create: pulumi.interpolate`helm dependency build ${chartPath}`,
    triggers: [chartPath],
  },
  { dependsOn: [kindCluster] }
);

// Step 3 — `jitml bootstrap --<substrate>` drives the phased Helm rollout.
// Per `JitML.Cluster.Helm.helmPhasedRolloutPlan`, the daemon installs Harbor
// first, then the platform services, then mirrors the jitml images, then the
// final per-substrate services. The generated Kind kubeconfig path is explicit
// so the host's `~/.kube/config` is untouched.
const jitmlBootstrap = new local.Command(
  "jitml-bootstrap",
  {
    create: pulumi.interpolate`${jitmlBinary} bootstrap --${substrate}`,
    triggers: [substrate, jitmlBinary, kubeconfigPath],
  },
  { dependsOn: [helmDeps] }
);

// Step 4 — Confirm cluster publication is on disk. The `jitml bootstrap`
// reconciler writes `./.build/runtime/cluster-publication.json` after the
// final phase reaches Ready.
const publicationCheck = new local.Command(
  "publication-check",
  {
    create: `test -f ./.build/runtime/cluster-publication.json && echo "publication: ready"`,
    triggers: [substrate],
  },
  { dependsOn: [jitmlBootstrap] }
);

// Outputs the e2e stanza consumes.
export const clusterReady = publicationCheck.stdout;
export const edgePort = config.getNumber("edgePort") ?? 9090;
export const playwrightCommand = pulumi.output("npx playwright test");
