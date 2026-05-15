{-# LANGUAGE OverloadedStrings #-}

module JitML.Plan.Plan
    ( CommandInputs (..)
    , CommandResult (..)
    , Plan (..)
    , PlanStep (..)
    , buildCommandPlan
    )
where

import Data.Text (Text)
import Data.Text qualified as Text

data Plan inputs result = Plan
    { planName :: Text
    , planInputs :: inputs
    , planSteps :: [PlanStep]
    , planResult :: result
    }
    deriving stock (Eq, Show)

data PlanStep = PlanStep
    { stepName :: Text
    , stepDescription :: Text
    }
    deriving stock (Eq, Show)

data CommandInputs = CommandInputs
    { inputCommand :: Text
    , inputOptions :: [(Text, [Text])]
    }
    deriving stock (Eq, Show)

data CommandResult = CommandResult
    { resultSummary :: Text
    }
    deriving stock (Eq, Show)

buildCommandPlan :: [Text] -> [(Text, [Text])] -> Either Text (Plan CommandInputs CommandResult)
buildCommandPlan path optionPairs =
    Right
        Plan
            { planName = "command plan"
            , planInputs =
                CommandInputs
                    { inputCommand = commandText
                    , inputOptions = optionPairs
                    }
            , planSteps =
                commandPlanSteps path
            , planResult =
                CommandResult
                    { resultSummary = "No side effects are performed while rendering a plan."
                    }
            }
  where
    commandText = Text.unwords ("jitml" : path)

commandPlanSteps :: [Text] -> [PlanStep]
commandPlanSteps ["bootstrap"] =
    [ PlanStep "check-prerequisites" "Reconcile the cluster prerequisite graph."
    , PlanStep "render-kind-config" "Write kind/cluster-<substrate>.yaml from the typed KindConfig."
    , PlanStep "render-chart" "Write the storage, gateway, route, platform-service, daemon, and demo manifests."
    , PlanStep "publish-runtime" "Write ./.build/runtime/cluster-publication.json and per-substrate Dhall."
    ]
commandPlanSteps ["cluster", "up"] =
    [ PlanStep "materialize-substrate" "Render the selected substrate's Kind and chart inputs."
    , PlanStep "create-kind-cluster" "Create the Kind cluster with ./.build/jitml.kubeconfig."
    , PlanStep "apply-chart" "Apply the umbrella Helm chart in phased order."
    ]
commandPlanSteps ["service"] =
    [ PlanStep "load-config" "Load BootConfig and LiveConfig."
    , PlanStep "acquire-capabilities" "Acquire MinIO, Pulsar, Harbor, and kubectl capabilities."
    , PlanStep "serve" "Expose health, readiness, metrics, and at-least-once consumers."
    ]
commandPlanSteps ["train"] =
    [ PlanStep "decode-experiment" "Decode supervised training Dhall into typed records."
    , PlanStep "compile-kernels" "Resolve or JIT-compile deterministic kernels."
    , PlanStep "run-training" "Run the supervised loop and emit checkpoints and TensorBoard events."
    ]
commandPlanSteps ["tune"] =
    [ PlanStep "decode-tuning" "Decode sampler, scheduler, and pruner configuration."
    , PlanStep "schedule-trials" "Produce deterministic trial candidates."
    , PlanStep "persist-frontier" "Persist trial state and Pareto frontier records."
    ]
commandPlanSteps ["rl", "train"] =
    [ PlanStep "decode-rl-experiment" "Decode environment, policy, and algorithm configuration."
    , PlanStep "run-rollouts" "Run deterministic vectorized rollouts."
    , PlanStep "update-policy" "Update the policy and checkpoint the result."
    ]
commandPlanSteps ["test", "all"] =
    [ PlanStep "run-cabal-tests" "Run every Cabal test stanza."
    , PlanStep "run-report-card" "Run the pinned report-card workloads."
    , PlanStep "render-summary" "Render the typed report card."
    ]
commandPlanSteps ["internal", "gc"] =
    [ PlanStep "load-retention-policy" "Load checkpoint retention from the experiment manifest."
    , PlanStep "list-checkpoints" "List checkpoint manifests from MinIO."
    , PlanStep "delete-expired" "Delete checkpoint blobs no longer retained by the policy."
    ]
commandPlanSteps _ =
    [ PlanStep "parse-command" "Parse and validate the command surface from CommandSpec."
    , PlanStep "check-prerequisites" "Run the prerequisite gate for the command before mutation."
    , PlanStep "apply-command" "Apply the command implementation through the typed boundary."
    ]
