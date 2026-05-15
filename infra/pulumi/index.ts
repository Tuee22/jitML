import * as pulumi from "@pulumi/pulumi";

export const stackName = pulumi.getStack();
export const clusterName = `jitml-e2e-${stackName}`;
