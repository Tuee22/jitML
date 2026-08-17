{-# LANGUAGE OverloadedStrings #-}

-- | Sprint 5.12 (Pulsar ML-Workflow convergence) — the @jitml@ binary emits its
-- own __reflected__ Dhall schema. Every config surface's schema is derived from
-- the exact same 'Dhall.Decoder' its loader uses, via 'Dhall.expected', so the
-- emitted schema can never drift from the @FromDhall@ decoder types. This is the
-- convergence convention shared with the @infernix@ sister project
-- (@documents/engineering/pulsar_ml_workflow.md@ → /Configuration and roles/).
--
-- The checked-in @dhall/**@ schema files are a generated section emitted from
-- these reflected types: 'canonicalDhallType' canonicalises a checked-in schema
-- file through the same pretty-printer so a parity check (unit test +
-- @jitml docs check@) can assert /file ≡ reflected output/.
module JitML.Service.DhallSchema
  ( reflectedSchemaText
  , canonicalDhallType
  , bootConfigSchema
  , liveConfigSchema
  , trainingRunConfigSchema
  , tuneRunConfigSchema
  , alphaZeroRunConfigSchema
  , rlRunConfigSchema
  , trainingEvidenceConfigSchema
  , completedTrainingWitnessConfigSchema
  , inferenceSelectorConfigSchema
  , runSchemaDhall
  , configSchemas
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Dhall.Reflect (canonicalDhallType, reflectedSchemaText)
import JitML.Numerics.LayerDhall qualified as LayerDhall
import JitML.Service.BootConfig (rawBootConfigDecoder)
import JitML.Service.LiveConfig (liveConfigDecoder)
import JitML.Service.RunConfig
  ( alphaZeroRunConfigDecoder
  , completedTrainingWitnessConfigDecoder
  , inferenceSelectorConfigDecoder
  , rlRunConfigDecoder
  , trainingEvidenceConfigDecoder
  , trainingRunConfigDecoder
  , tuneRunConfigDecoder
  )

bootConfigSchema :: Text
bootConfigSchema = reflectedSchemaText rawBootConfigDecoder

liveConfigSchema :: Text
liveConfigSchema = reflectedSchemaText liveConfigDecoder

trainingRunConfigSchema :: Text
trainingRunConfigSchema = reflectedSchemaText trainingRunConfigDecoder

tuneRunConfigSchema :: Text
tuneRunConfigSchema = reflectedSchemaText tuneRunConfigDecoder

alphaZeroRunConfigSchema :: Text
alphaZeroRunConfigSchema = reflectedSchemaText alphaZeroRunConfigDecoder

rlRunConfigSchema :: Text
rlRunConfigSchema = reflectedSchemaText rlRunConfigDecoder

trainingEvidenceConfigSchema :: Text
trainingEvidenceConfigSchema = reflectedSchemaText trainingEvidenceConfigDecoder

completedTrainingWitnessConfigSchema :: Text
completedTrainingWitnessConfigSchema =
  reflectedSchemaText completedTrainingWitnessConfigDecoder

inferenceSelectorConfigSchema :: Text
inferenceSelectorConfigSchema = reflectedSchemaText inferenceSelectorConfigDecoder

-- | The reflected form of @dhall/run/Schema.dhall@ — the worker @RunConfig@
-- records plus the inference-selector records built from the same decoders the
-- loaders use. Formatting is irrelevant to the parity check: both sides go
-- through 'canonicalDhallType'.
runSchemaDhall :: Text
runSchemaDhall =
  Text.concat
    [ "let TrainingEvidence : Type =\n"
    , trainingEvidenceConfigSchema
    , "\nlet CompletedTrainingWitness : Type =\n"
    , completedTrainingWitnessConfigSchema
    , "\nlet InferenceSelector : Type =\n"
    , inferenceSelectorConfigSchema
    , "\nlet TrainingRunConfig : Type =\n"
    , trainingRunConfigSchema
    , "\nlet TuneRunConfig : Type =\n"
    , tuneRunConfigSchema
    , "\nlet AlphaZeroRunConfig : Type =\n"
    , alphaZeroRunConfigSchema
    , "\nlet RlRunConfig : Type =\n"
    , rlRunConfigSchema
    , "\nin  { TrainingEvidence = TrainingEvidence"
    , "\n    , CompletedTrainingWitness = CompletedTrainingWitness"
    , "\n    , InferenceSelector = InferenceSelector"
    , "\n    , TrainingRunConfig = TrainingRunConfig"
    , "\n    , TuneRunConfig = TuneRunConfig"
    , "\n    , AlphaZeroRunConfig = AlphaZeroRunConfig"
    , "\n    , RlRunConfig = RlRunConfig"
    , "\n    }\n"
    ]

-- | Every reflected schema surface, keyed by the name used on the
-- @jitml internal dhall-schema@ CLI leaf and in the parity check. The
-- @LayerOp@ / @LayerGraph@ entries are the numerical ML DSL (Sprint `77.1`):
-- the layer vocabulary as parameterised Dhall constructors, reflected off the
-- same decoder the architecture loader uses.
configSchemas :: [(Text, Text)]
configSchemas =
  [ ("BootConfig", bootConfigSchema)
  , ("LiveConfig", liveConfigSchema)
  , ("TrainingRunConfig", trainingRunConfigSchema)
  , ("TuneRunConfig", tuneRunConfigSchema)
  , ("AlphaZeroRunConfig", alphaZeroRunConfigSchema)
  , ("RlRunConfig", rlRunConfigSchema)
  , ("InferenceSelector", inferenceSelectorConfigSchema)
  ]
    <> LayerDhall.numericsTypeSchemas
