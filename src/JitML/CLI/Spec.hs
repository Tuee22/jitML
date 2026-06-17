{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.CLI.Spec
  ( CommandSpec (..)
  , Example (..)
  , OptionKind (..)
  , OptionSpec (..)
  , commandLeaves
  , commandPathText
  , commandRegistry
  , commandUsage
  , findCommand
  , leafCount
  , leafPaths
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

data CommandSpec = CommandSpec
  { name :: Text
  , summary :: Text
  , description :: Text
  , children :: [CommandSpec]
  , options :: [OptionSpec]
  , examples :: [Example]
  }
  deriving stock (Eq, Show)

data OptionKind
  = FlagOption
  | ValueOption
  | PositionalOption
  | RemainderOption
  deriving stock (Eq, Show)

data OptionSpec = OptionSpec
  { longName :: Text
  , shortName :: Maybe Char
  , metavar :: Maybe Text
  , description :: Text
  , required :: Bool
  , optionKind :: OptionKind
  }
  deriving stock (Eq, Show)

data Example = Example
  { exampleCommand :: Text
  , exampleDescription :: Text
  }
  deriving stock (Eq, Show)

commandRegistry :: CommandSpec
commandRegistry =
  group
    "jitml"
    "jitML command registry"
    "Registry-backed command surface for the jitML binary."
    [ bootstrapCommand
    , doctorCommand
    , serviceCommand
    , clusterCommand
    , trainCommand
    , evalCommand
    , tuneCommand
    , rlCommand
    , verifyCommand
    , inspectCommand
    , benchCommand
    , inferenceCommand
    , testCommand
    , lintCommand
    , docsCommand
    , checkCodeCommand
    , buildCommand
    , kubectlCommand
    , internalCommand
    , commandsCommand
    , helpCommand
    ]

commandLeaves :: CommandSpec -> [([Text], CommandSpec)]
commandLeaves rootSpec =
  concatMap (go []) (children rootSpec)
 where
  go path spec =
    let nextPath = path <> [name spec]
     in if null (children spec)
          then [(nextPath, spec)]
          else concatMap (go nextPath) (children spec)

leafPaths :: CommandSpec -> [[Text]]
leafPaths = fmap fst . commandLeaves

leafCount :: CommandSpec -> Int
leafCount = length . commandLeaves

findCommand :: [Text] -> Maybe CommandSpec
findCommand [] = Just commandRegistry
findCommand path = go path (children commandRegistry)
 where
  go [] _ = Nothing
  go (part : rest) specs =
    case filter ((== part) . name) specs of
      [spec]
        | null rest -> Just spec
        | otherwise -> go rest (children spec)
      _ -> Nothing

commandPathText :: [Text] -> Text
commandPathText path = Text.unwords ("jitml" : path)

commandUsage :: [Text] -> CommandSpec -> Text
commandUsage path spec =
  Text.unwords (("jitml" : path) <> fmap optionUsage (options spec))

-- | The explicit substrate selector flags shared by @bootstrap@ and @test@.
-- Exactly one must be supplied; callers reject zero or many. Keeping a single
-- definition keeps the two command surfaces in lockstep.
substrateFlags :: [OptionSpec]
substrateFlags =
  [ flag "apple-silicon" Nothing False "Select the Apple Silicon substrate."
  , flag "linux-cpu" Nothing False "Select the Linux CPU substrate."
  , flag "linux-cuda" Nothing False "Select the Linux CUDA substrate."
  ]

bootstrapCommand :: CommandSpec
bootstrapCommand =
  leaf
    "bootstrap"
    "Bootstrap a substrate stack."
    "Plans and applies full substrate bootstrap: generated Dhall, Kind, Harbor-first rollout, platform services, cluster daemon, demo, and Apple host-daemon handoff."
    ( substrateFlags
        <> [ dryRunOption
           , planFileOption
           ]
    )
    [ Example "jitml bootstrap --apple-silicon" "Bootstrap the Apple Silicon stack."
    , Example "jitml bootstrap --linux-cpu" "Bootstrap the Linux CPU stack."
    , Example "jitml bootstrap --linux-cuda" "Bootstrap the Linux CUDA stack."
    ]

serviceCommand :: CommandSpec
serviceCommand =
  leaf
    "service"
    "Run the jitML daemon."
    "Runs the long-lived daemon using Dhall boot and live configuration."
    [ value "config" (Just 'c') "path" False "Path to the daemon Dhall config."
    , value
        "consume-once"
        Nothing
        "n"
        False
        "Acquire daemon subscriptions, drain n messages per subscription, dispatch them, and exit."
    , dryRunOption
    , planFileOption
    ]
    [ Example
        "jitml service --config ./.build/conf/host/apple-silicon.dhall"
        "Run the host daemon using the Apple Silicon host config."
    , Example
        "jitml service --config /etc/jitml/BootConfig.dhall --consume-once 1"
        "Run one bounded daemon consumer batch from a service pod."
    ]

doctorCommand :: CommandSpec
doctorCommand =
  leaf
    "doctor"
    "Check host prerequisites."
    "Checks the typed prerequisite registry for the selected scope."
    [ value "scope" Nothing "toolchain|container|cluster" False "Prerequisite scope to reconcile."
    , flag "remediate" Nothing False "Apply typed remediation actions for missing prerequisites."
    ]
    [Example "jitml doctor --scope toolchain" "Check toolchain prerequisites."]

clusterCommand :: CommandSpec
clusterCommand =
  group
    "cluster"
    "Manage the local jitML cluster."
    "Plans, applies, inspects, and resets the local substrate cluster."
    [ leaf
        "up"
        "Bring the cluster up."
        "Materializes the selected substrate and reconciles the local cluster."
        [ value "substrate" Nothing "substrate" False "apple-silicon, linux-cpu, or linux-cuda."
        , dryRunOption
        , planFileOption
        ]
        [Example "jitml cluster up --substrate apple-silicon" "Start the Apple Silicon substrate cluster."]
    , leaf
        "down"
        "Bring the cluster down."
        "Preserves stateful data while stopping the local cluster."
        []
        [Example "jitml cluster down" "Stop the local cluster."]
    , leaf
        "status"
        "Report cluster status."
        "Prints the publication state and health of the local cluster."
        []
        [Example "jitml cluster status" "Inspect the local cluster publication."]
    , leaf
        "reset"
        "Destructively reset cluster state."
        "Removes local cluster state after an explicit confirmation flag."
        [flag "yes" Nothing True "Confirm destructive reset."]
        [Example "jitml cluster reset --yes" "Reset all local cluster state."]
    ]

trainCommand :: CommandSpec
trainCommand =
  leaf
    "train"
    "Run a supervised training job."
    "Plans and applies a training job described by an experiment Dhall file."
    [ positional "experiment-dhall" True "Experiment Dhall file."
    , value "resume" Nothing "checkpoint-id" False "Checkpoint identifier to resume from."
    , value
        "substrate"
        Nothing
        "substrate"
        False
        "Override the experiment Dhall's substrate (apple-silicon, linux-cpu, or linux-cuda)."
    , value "seed" Nothing "word64" False "Override the experiment Dhall's seed."
    , dryRunOption
    , planFileOption
    ]
    [ Example "jitml train experiments/mnist.dhall" "Run a supervised training experiment."
    , Example
        "jitml train experiments/mnist.dhall --substrate linux-cpu --seed 42"
        "Run with a CLI substrate/seed override of the experiment Dhall."
    ]

evalCommand :: CommandSpec
evalCommand =
  leaf
    "eval"
    "Run deterministic evaluation."
    "Evaluates a trained model or policy against a deterministic cohort."
    [ positional "experiment-dhall" True "Experiment Dhall file."
    , value "checkpoint" Nothing "checkpoint-id" False "Checkpoint identifier to evaluate."
    ]
    [Example "jitml eval experiments/mnist.dhall --checkpoint latest" "Evaluate the latest checkpoint."]

tuneCommand :: CommandSpec
tuneCommand =
  leaf
    "tune"
    "Run a hyperparameter sweep."
    "Plans and applies a hyperparameter sweep described by a tuning Dhall file."
    [ positional "tune-dhall" True "Tuning Dhall file."
    , value "resume" Nothing "sweep-id" False "Sweep identifier to resume."
    , value
        "sampler"
        Nothing
        "name"
        False
        "Override the tuning sampler axis (Grid, Sobol, Random, TPE, GPBO, GeneticAlgorithm, NSGA2, MuLambdaES, CMAES, EvolutionStrategies, PBT)."
    , value
        "scheduler"
        Nothing
        "name"
        False
        "Override the tuning scheduler axis (Fifo, SuccessiveHalving, Hyperband, ASHA)."
    , value
        "pruner"
        Nothing
        "name"
        False
        "Override the tuning pruner axis (NoPruner, MedianPruner, PercentilePruner)."
    , value "trials" Nothing "natural" False "Override the tuning trial budget."
    , value "parallelism" Nothing "natural" False "Override the tuning parallelism."
    , dryRunOption
    , planFileOption
    ]
    [ Example "jitml tune experiments/mnist-tune.dhall" "Run a tuning sweep."
    , Example
        "jitml tune experiments/mnist-tune.dhall --sampler Sobol --trials 64 --parallelism 8"
        "Override sampler, trial budget, and parallelism from the CLI."
    , Example
        "jitml tune experiments/mnist-tune.dhall --sampler TPE --scheduler ASHA --pruner MedianPruner"
        "Override every tuning axis from the CLI."
    ]

rlCommand :: CommandSpec
rlCommand =
  group
    "rl"
    "Run reinforcement learning workflows."
    "Training, deterministic evaluation, and rollout commands for RL workloads."
    [ leaf
        "train"
        "Train an RL policy."
        "Plans and applies an RL training job."
        [ positional "rl-experiment-dhall" True "RL experiment Dhall file."
        , value "resume" Nothing "checkpoint-id" False "Checkpoint identifier to resume from."
        , value
            "substrate"
            Nothing
            "substrate"
            False
            "Override the RL experiment Dhall's substrate (apple-silicon, linux-cpu, or linux-cuda)."
        , value "seed" Nothing "word64" False "Override the RL experiment Dhall's seed."
        , dryRunOption
        , planFileOption
        ]
        [ Example "jitml rl train experiments/cartpole.dhall" "Train an RL policy."
        , Example
            "jitml rl train experiments/cartpole.dhall --substrate apple-silicon --seed 1729"
            "Train with a CLI substrate/seed override of the RL Dhall."
        ]
    , leaf
        "eval"
        "Evaluate an RL policy."
        "Runs deterministic policy evaluation."
        [ positional "rl-experiment-dhall" True "RL experiment Dhall file."
        , value "checkpoint" Nothing "checkpoint-id" False "Checkpoint identifier to evaluate."
        ]
        [Example "jitml rl eval experiments/cartpole.dhall --checkpoint latest" "Evaluate an RL policy."]
    , leaf
        "rollout"
        "Run a fixed-seed rollout."
        "Runs a deterministic rollout cohort for an RL experiment."
        [ positional "rl-experiment-dhall" True "RL experiment Dhall file."
        , value "seed" Nothing "word64" False "Rollout seed."
        ]
        [Example "jitml rl rollout experiments/cartpole.dhall --seed 42" "Run a fixed-seed rollout."]
    , group
        "alphazero"
        "Run AlphaZero workflows."
        "Self-play and policy/value training commands for AlphaZero workloads."
        [ leaf
            "self-play"
            "Run AlphaZero self-play."
            "Runs a bounded AlphaZero self-play generation through the selected substrate MLP device."
            [ value
                "substrate"
                Nothing
                "substrate"
                False
                "Override the self-play substrate (apple-silicon, linux-cpu, or linux-cuda)."
            , value "seed" Nothing "word64" False "Self-play seed."
            , value "games" Nothing "n" False "Number of self-play games."
            , value "sims" Nothing "n" False "MCTS simulations per move."
            , value "max-plies" Nothing "n" False "Maximum plies per self-play game."
            , value "updates" Nothing "n" False "Policy/value gradient updates."
            , value "arena-games" Nothing "n" False "Arena games for win-rate reporting."
            ]
            [ Example
                "jitml rl alphazero self-play --substrate linux-cpu --seed 31"
                "Run a bounded AlphaZero generation through the Linux CPU device."
            ]
        ]
    ]

verifyCommand :: CommandSpec
verifyCommand =
  group
    "verify"
    "Verify determinism."
    "Determinism and replay verification commands."
    [ leaf
        "same-run"
        "Verify same-run determinism."
        "Runs the same experiment repeatedly and checks byte-equivalent outputs."
        [ value "experiment" Nothing "experiment-dhall" True "Experiment Dhall file."
        , value "runs" Nothing "int" True "Number of same-run repetitions."
        ]
        [ Example
            "jitml verify same-run --experiment experiments/mnist.dhall --runs 2"
            "Verify same-run determinism."
        ]
    , leaf
        "replay"
        "Verify checkpoint replay."
        "Replays a checkpoint transcript and checks deterministic reproduction."
        [ value "experiment" Nothing "experiment-dhall" True "Experiment Dhall file."
        , value "checkpoint" Nothing "checkpoint-id" True "Checkpoint identifier to replay."
        ]
        [ Example
            "jitml verify replay --experiment experiments/mnist.dhall --checkpoint latest"
            "Replay a checkpoint."
        ]
    ]

inspectCommand :: CommandSpec
inspectCommand =
  group
    "inspect"
    "Inspect cached run state."
    "Inspects cached transcripts, checkpoints, trials, and frontiers."
    [ leaf
        "list"
        "List cached manifests."
        "Lists cached transcripts and checkpoints."
        []
        [Example "jitml inspect list" "List cached manifests."]
    , leaf
        "show"
        "Show a manifest."
        "Shows a cached manifest, optionally with equity details."
        [ positional "manifest-sha" True "Manifest SHA."
        , flag "with-equity" Nothing False "Include equity details."
        ]
        [Example "jitml inspect show abc123 --with-equity" "Show a manifest with equity details."]
    , leaf
        "replay"
        "Replay a manifest."
        "Replays a cached manifest transcript."
        [ positional "manifest-sha" False "Manifest SHA (omit when using --manifest-sha + --experiment-hash)."
        , value "manifest-sha" Nothing "manifest-sha" False "Manifest SHA (alternative to the positional)."
        , value
            "experiment-hash"
            Nothing
            "experiment-hash"
            False
            "Override the experiment hash directly (live MinIO lookup)."
        ]
        [ Example
            "jitml inspect replay abc123"
            "Replay a cached manifest from the local store."
        , Example
            "jitml inspect replay --manifest-sha abc123 --experiment-hash live-test-1"
            "Replay a live-MinIO manifest by SHA."
        ]
    , leaf
        "trial"
        "Inspect a trial."
        "Shows a cached hyperparameter trial."
        [positional "trial-hash" True "Trial hash."]
        [Example "jitml inspect trial trial123" "Inspect a tuning trial."]
    , leaf
        "frontier"
        "Inspect a tuning frontier."
        "Shows the Pareto frontier for a sweep."
        [positional "sweep-id" True "Sweep identifier."]
        [Example "jitml inspect frontier sweep123" "Inspect a sweep frontier."]
    ]

benchCommand :: CommandSpec
benchCommand =
  group
    "bench"
    "Run benchmark harnesses."
    "Reproducible benchmark harnesses for training, inference, and environment stepping."
    [ leaf
        "train"
        "Benchmark training."
        "Runs the training benchmark harness."
        [positional "experiment-dhall" True "Experiment Dhall file."]
        [Example "jitml bench train experiments/mnist.dhall" "Benchmark training throughput."]
    , leaf
        "inference"
        "Benchmark inference."
        "Runs the inference benchmark harness."
        [ positional "experiment-dhall" True "Experiment Dhall file."
        , value "checkpoint" Nothing "checkpoint-id" True "Checkpoint identifier to load."
        ]
        [ Example
            "jitml bench inference experiments/mnist.dhall --checkpoint latest"
            "Benchmark inference throughput."
        ]
    , leaf
        "env"
        "Benchmark environment stepping."
        "Runs the RL environment-step benchmark harness."
        [positional "rl-experiment-dhall" True "RL experiment Dhall file."]
        [Example "jitml bench env experiments/cartpole.dhall" "Benchmark environment steps."]
    ]

inferenceCommand :: CommandSpec
inferenceCommand =
  group
    "inference"
    "Run inference."
    "Inference commands for trained checkpoints."
    [ leaf
        "run"
        "Run inference at any point."
        "Runs inference against latest, best/<metric>, or a manifest SHA checkpoint."
        [ positional "experiment-dhall" False "Experiment Dhall file."
        , value "checkpoint" Nothing "latest|best/<metric>|manifest-sha" False "Checkpoint selector."
        , value "trial" Nothing "trial-hash" False "Optional tuning trial hash."
        , value
            "experiment-hash"
            Nothing
            "experiment-hash"
            False
            "Override the experiment hash directly (live MinIO lookup)."
        ]
        [ Example
            "jitml inference run experiments/mnist.dhall --checkpoint latest"
            "Run inference using the latest checkpoint."
        , Example
            "jitml inference run --experiment-hash abc123"
            "Live-MinIO inference run against a known experiment hash."
        ]
    ]

testCommand :: CommandSpec
testCommand =
  group
    "test"
    "Run test suites."
    "Runs all or selected Cabal test stanzas through the jitML test orchestrator; code style and quality gates live under lint/check-code."
    (allTestCommand : fmap testStanzaCommand testStanzas)

lintCommand :: CommandSpec
lintCommand =
  group
    "lint"
    "Run lint checks."
    "Runs source, docs, Haskell, chart, proto, PureScript, or aggregate lint checks."
    [ lintLeaf "files" "Run file hygiene checks."
    , lintLeaf "docs" "Run generated documentation checks."
    , lintLeaf "proto" "Run protobuf schema lint checks."
    , lintLeaf "chart" "Run Helm chart shape checks."
    , lintLeaf "haskell" "Run Haskell lint configuration and primitive checks."
    , lintLeaf "purescript" "Run PureScript contract and format checks."
    , leaf
        "all"
        "Run every currently implemented lint check."
        "Runs every current lint target."
        [flag "write" Nothing False "Rewrite files for checks that support it."]
        [Example "jitml lint all --write" "Run every current lint target and apply supported rewrites."]
    ]

docsCommand :: CommandSpec
docsCommand =
  group
    "docs"
    "Check or generate tracked documentation."
    "Generated-section reconciler commands."
    [ leaf
        "check"
        "Check generated docs."
        "Fails if generated documentation has drifted."
        []
        [Example "jitml docs check" "Check generated documentation drift."]
    , leaf
        "generate"
        "Generate docs."
        "Updates tracked generated documentation."
        []
        [Example "jitml docs generate" "Regenerate tracked documentation."]
    ]

checkCodeCommand :: CommandSpec
checkCodeCommand =
  leaf
    "check-code"
    "Run the code quality gate."
    "Runs the current in-repo hygiene, generated-doc drift, forbidden-path, chart, and Haskell primitive checks."
    []
    [Example "jitml check-code" "Run the aggregate code quality gate."]

buildCommand :: CommandSpec
buildCommand =
  leaf
    "build"
    "Build inside the substrate container."
    "Builds the inner binary and renders the selected substrate JIT compile plan."
    [ value "substrate" Nothing "substrate" False "apple-silicon, linux-cpu, or linux-cuda."
    , dryRunOption
    , planFileOption
    ]
    [ Example "jitml build --substrate linux-cpu" "Build the inner binary."
    , Example
        "jitml build --dry-run --substrate linux-cuda"
        "Render the CUDA generated-source build plan."
    ]

kubectlCommand :: CommandSpec
kubectlCommand =
  leaf
    "kubectl"
    "Run kubectl against the jitML kubeconfig."
    "Passes arguments to kubectl with ./.build/jitml.kubeconfig pre-bound."
    [remainder "kubectl-args" False "Arguments passed through to kubectl."]
    [Example "jitml kubectl get pods" "List pods using the jitML kubeconfig."]

internalCommand :: CommandSpec
internalCommand =
  group
    "internal"
    "Run internal support commands."
    "Internal commands used by bootstrap, substrate, dataset upload, cache, and GC workflows."
    [ leaf
        "materialize-substrate"
        "Materialize substrate files."
        "Internal helper that materializes substrate-specific bootstrap files."
        [value "substrate" Nothing "substrate" False "Substrate to materialize."]
        [ Example
            "jitml internal materialize-substrate --substrate linux-cpu"
            "Materialize Linux CPU substrate files."
        ]
    , leaf
        "list-prereqs"
        "List prerequisite checks."
        "Prints the prerequisite registry for the current substrate."
        []
        [Example "jitml internal list-prereqs" "List prerequisite checks."]
    , leaf
        "install-metal-bridge"
        "Build the fixed Apple Metal bridge."
        "Builds the process-stable Apple Metal bridge dylib from jitML-generated source under ./.build/host/apple-silicon/."
        []
        [Example "jitml internal install-metal-bridge" "Build and probe the fixed Apple Metal bridge."]
    , leaf
        "upload-dataset"
        "Upload a real dataset blob to MinIO."
        "Sprint 13.4 / 8.12 — reads a local file, verifies its SHA-256 against the canonical SHA from JitML.SL.Dataset, and uploads it to jitml-datasets/<name>/<split>/{data.bin,labels.bin,archive.tar.gz} via the routed MinIOSubprocess. The canonical SHA is the one returned by `JitML.SL.Dataset.canonicalArtifactSha256For`; mismatches abort the upload. --artifact selects images (data.bin), labels (labels.bin), or archive (archive.tar.gz)."
        [ value "name" Nothing "name" False "Dataset name (e.g., MNIST)."
        , value "split" Nothing "split" False "Dataset split (train/validation/test)."
        , value
            "artifact"
            Nothing
            "artifact"
            False
            "Artifact kind (images/labels/archive); defaults to images."
        , value "path" Nothing "path" False "Local file path to upload."
        , dryRunOption
        , planFileOption
        ]
        [ Example
            "jitml internal upload-dataset --name MNIST --split train --path /tmp/train-images-idx3-ubyte.gz"
            "Upload the canonical MNIST training images to the live MinIO bucket."
        , Example
            "jitml internal upload-dataset --name MNIST --split train --artifact labels --path /tmp/train-labels-idx1-ubyte.gz"
            "Upload the canonical MNIST training labels alongside the images."
        , Example
            "jitml internal upload-dataset --name CIFAR-10 --split train --artifact archive --path /tmp/cifar-10-binary.tar.gz"
            "Upload the canonical CIFAR-10 binary archive for later train/test materialization."
        ]
    , leaf
        "seed-demo-checkpoints"
        "Seed demo inference checkpoints into MinIO."
        "Writes a small Dense2D weight checkpoint (manifest + .jmw1 + latest-pointer) at each of the five demo browser-panel experiment hashes (mnist-deep-mlp, generic-tensor-demo, generic-tensor-demo-candidate, cifar-imagenet, connect4-alphazero) through the routed MinIOSubprocess, so the live jitml-demo checkpoint-backed panels (MNIST / generic / CIFAR / checkpoint-compare / Connect 4) serve a real InferenceResult. The Dense2D weighted kernel zero-pads the weights to the request's input size, so one fixed weight vector serves every panel. Requires a live cluster."
        []
        [ Example
            "jitml internal seed-demo-checkpoints"
            "Seed the five demo panel checkpoints into live MinIO."
        ]
    , leaf
        "gc"
        "Apply checkpoint retention."
        "Reconciles the experiment retention policy against the checkpoint store."
        [ positional "experiment-hash" True "Experiment hash."
        , dryRunOption
        , planFileOption
        ]
        [Example "jitml internal gc exp123" "Apply retention to an experiment."]
    , cacheCommand
    ]

commandsCommand :: CommandSpec
commandsCommand =
  leaf
    "commands"
    "Print the command registry."
    "Prints a flat list, tree rendering, or JSON schema for the command registry."
    [ flag "tree" Nothing False "Render the command tree."
    , flag "json" Nothing False "Render the JSON command schema."
    ]
    [Example "jitml commands --tree" "Print the command tree."]

helpCommand :: CommandSpec
helpCommand =
  leaf
    "help"
    "Print focused command help."
    "Prints the same help text as passing --help to a subcommand."
    [remainder "subcommand" False "Subcommand path to show help for."]
    [Example "jitml help cluster up" "Print help for cluster up."]

cacheCommand :: CommandSpec
cacheCommand =
  group
    "cache"
    "Inspect the JIT cache."
    "JIT cache stat, list, and eviction commands."
    [ leaf
        "stat"
        "Print cache stats."
        "Prints JIT cache statistics."
        []
        [Example "jitml internal cache stat" "Print JIT cache stats."]
    , leaf
        "list"
        "List cache entries."
        "Lists JIT cache entries."
        []
        [Example "jitml internal cache list" "List cache entries."]
    , leaf
        "evict"
        "Evict a cache entry."
        "Evicts a JIT cache entry by hash."
        [positional "hash" True "JIT cache hash."]
        [Example "jitml internal cache evict abc123" "Evict one cache entry."]
    ]

allTestCommand :: CommandSpec
allTestCommand =
  leaf
    "all"
    "Run all test stanzas."
    "Runs every test-only Cabal stanza and renders the report card. With a substrate flag, substrate-partitioned stanzas run only that substrate's lane (and linux-cuda builds with -fcuda); pure-logic stanzas always run in full."
    ( [flag "live" Nothing False "Collect live report-card measurements after the Cabal stanzas pass."]
        <> substrateFlags
        <> [ testOptionsOption
           , dryRunOption
           , planFileOption
           ]
    )
    [ Example "jitml test all --dry-run" "Print the aggregate test plan."
    , Example
        "jitml test all --linux-cuda"
        "Run the linux-cuda lane (auto -fcuda); pure-logic stanzas run in full."
    , Example "jitml test all --linux-cpu" "Run the linux-cpu lane."
    , Example "jitml test all --live" "Run the stanzas and append live report-card measurements."
    ]

testStanzaCommand :: Text -> CommandSpec
testStanzaCommand stanzaName =
  leaf
    stanzaName
    ("Run " <> stanzaName <> ".")
    ("Runs the " <> stanzaName <> " Cabal test stanza.")
    (substrateFlags <> [testOptionsOption])
    [ Example ("jitml test " <> stanzaName) ("Run " <> stanzaName <> ".")
    , Example
        ("jitml test " <> stanzaName <> " --linux-cuda")
        "Run the stanza's linux-cuda lane (substrate-partitioned stanzas filter to that lane; linux-cuda adds -fcuda)."
    ]

-- | Optional passthrough that forwards an opaque argument string to
-- @cabal test@ (for example @-p linux-cuda@ to select a substrate lane).
-- The value is opaque to jitML and is forwarded verbatim.
testOptionsOption :: OptionSpec
testOptionsOption =
  value
    "test-options"
    Nothing
    "text"
    False
    "Forward an opaque argument string to cabal test (e.g. -p linux-cuda)."

testStanzas :: [Text]
testStanzas =
  [ "jitml-unit"
  , "jitml-integration"
  , "jitml-sl-canonicals"
  , "jitml-rl-canonicals"
  , "jitml-hyperparameter"
  , "jitml-backends"
  , "jitml-daemon-lifecycle"
  , "jitml-e2e"
  ]

lintLeaf :: Text -> Text -> CommandSpec
lintLeaf commandName commandSummary =
  leaf
    commandName
    commandSummary
    commandSummary
    [writeOption]
    [Example ("jitml lint " <> commandName) commandSummary]

dryRunOption :: OptionSpec
dryRunOption = flag "dry-run" Nothing False "Print the plan without applying it."

planFileOption :: OptionSpec
planFileOption = value "plan-file" Nothing "path" False "Write the plan to a file."

writeOption :: OptionSpec
writeOption = flag "write" Nothing False "Rewrite files for checks that support it."

group :: Text -> Text -> Text -> [CommandSpec] -> CommandSpec
group commandName commandSummary commandDescription commandChildren =
  CommandSpec
    { name = commandName
    , summary = commandSummary
    , description = commandDescription
    , children = commandChildren
    , options = []
    , examples = []
    }

leaf :: Text -> Text -> Text -> [OptionSpec] -> [Example] -> CommandSpec
leaf commandName commandSummary commandDescription commandOptions commandExamples =
  CommandSpec
    { name = commandName
    , summary = commandSummary
    , description = commandDescription
    , children = []
    , options = commandOptions
    , examples = commandExamples
    }

flag :: Text -> Maybe Char -> Bool -> Text -> OptionSpec
flag optionName optionShortName optionRequired optionDescription =
  OptionSpec
    { longName = optionName
    , shortName = optionShortName
    , metavar = Nothing
    , description = optionDescription
    , required = optionRequired
    , optionKind = FlagOption
    }

value :: Text -> Maybe Char -> Text -> Bool -> Text -> OptionSpec
value optionName optionShortName optionMetavar optionRequired optionDescription =
  OptionSpec
    { longName = optionName
    , shortName = optionShortName
    , metavar = Just optionMetavar
    , description = optionDescription
    , required = optionRequired
    , optionKind = ValueOption
    }

positional :: Text -> Bool -> Text -> OptionSpec
positional optionMetavar optionRequired optionDescription =
  OptionSpec
    { longName = optionMetavar
    , shortName = Nothing
    , metavar = Just optionMetavar
    , description = optionDescription
    , required = optionRequired
    , optionKind = PositionalOption
    }

remainder :: Text -> Bool -> Text -> OptionSpec
remainder optionMetavar optionRequired optionDescription =
  OptionSpec
    { longName = optionMetavar
    , shortName = Nothing
    , metavar = Just optionMetavar
    , description = optionDescription
    , required = optionRequired
    , optionKind = RemainderOption
    }

optionUsage :: OptionSpec -> Text
optionUsage option =
  wrapOptional $
    case optionKind option of
      FlagOption -> "--" <> longName option
      ValueOption -> "--" <> longName option <> " <" <> metavarText option <> ">"
      PositionalOption -> "<" <> metavarText option <> ">"
      RemainderOption -> "-- <" <> metavarText option <> "...>"
 where
  wrapOptional token
    | required option = token
    | otherwise = "[" <> token <> "]"

  metavarText optionSpec =
    case metavar optionSpec of
      Just label -> label
      Nothing -> longName optionSpec
