{-# LANGUAGE OverloadedStrings #-}

-- | Sprint 5.12 (Pulsar ML-Workflow convergence) — the @jitml@ binary emits its
-- own __reflected__ Dhall schema. Every config surface's schema is derived from
-- the exact same 'Dhall.Decoder' its loader uses, via 'Dhall.expected', so the
-- emitted schema can never drift from the @FromDhall@ decoder types. This is the
-- convergence convention shared with the @infernix@ sister project
-- (@documents/engineering/pulsar_ml_workflow.md@ → /Configuration and roles/) and
-- the lever for the eventual @hostbootstrap@ lift.
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
  , rlRunConfigSchema
  , runSchemaDhall
  , configSchemas
  )
where

import Data.Either.Validation (Validation (..))
import Data.Text (Text)
import Data.Text qualified as Text
import Dhall qualified
import Dhall.Core (Expr, Import)
import Dhall.Core qualified as Core
import Dhall.Parser qualified as Parser
import Dhall.Src (Src)

import JitML.Service.BootConfig (rawBootConfigDecoder)
import JitML.Service.LiveConfig (liveConfigDecoder)
import JitML.Service.RunConfig
  ( rlRunConfigDecoder
  , trainingRunConfigDecoder
  , tuneRunConfigDecoder
  )

-- | Pretty-print the Dhall /type/ a decoder accepts. Because the type is read
-- back off the live decoder, it is structurally identical to what the loader
-- will accept — the schema cannot drift from the code.
reflectedSchemaText :: Dhall.Decoder a -> Text
reflectedSchemaText decoder =
  case Dhall.expected decoder of
    Success expr -> Core.pretty expr
    Failure errs -> "-- unable to reflect schema: " <> Text.pack (show errs)

-- | Canonicalise a checked-in Dhall /type/ file through the same pretty-printer
-- the reflected schema uses, with source notes stripped, so a parity assertion
-- between the file and 'reflectedSchemaText' is a plain text comparison.
-- Schema files reference no imports, so parsing is pure.
canonicalDhallType :: Text -> Either Text Text
canonicalDhallType src =
  case Parser.exprFromText "<dhall-schema>" src of
    Left err -> Left (Text.pack (show err))
    Right expr -> Right (Core.pretty (Core.denote expr :: Expr Src Import))

bootConfigSchema :: Text
bootConfigSchema = reflectedSchemaText rawBootConfigDecoder

liveConfigSchema :: Text
liveConfigSchema = reflectedSchemaText liveConfigDecoder

trainingRunConfigSchema :: Text
trainingRunConfigSchema = reflectedSchemaText trainingRunConfigDecoder

tuneRunConfigSchema :: Text
tuneRunConfigSchema = reflectedSchemaText tuneRunConfigDecoder

rlRunConfigSchema :: Text
rlRunConfigSchema = reflectedSchemaText rlRunConfigDecoder

-- | The reflected form of @dhall/run/Schema.dhall@ — the worker @RunConfig@
-- let-record built from the three reflected `RunConfig` types, so the checked-in
-- run-schema file is also derived from the decoders rather than hand-written.
-- Formatting is irrelevant to the parity check: both sides go through
-- 'canonicalDhallType'.
runSchemaDhall :: Text
runSchemaDhall =
  Text.concat
    [ "let TrainingRunConfig : Type =\n"
    , trainingRunConfigSchema
    , "\nlet TuneRunConfig : Type =\n"
    , tuneRunConfigSchema
    , "\nlet RlRunConfig : Type =\n"
    , rlRunConfigSchema
    , "\nin  { TrainingRunConfig = TrainingRunConfig"
    , "\n    , TuneRunConfig = TuneRunConfig"
    , "\n    , RlRunConfig = RlRunConfig"
    , "\n    }\n"
    ]

-- | Every reflected config surface, keyed by the name used on the
-- @jitml internal dhall-schema@ CLI leaf and in the parity check.
configSchemas :: [(Text, Text)]
configSchemas =
  [ ("BootConfig", bootConfigSchema)
  , ("LiveConfig", liveConfigSchema)
  , ("TrainingRunConfig", trainingRunConfigSchema)
  , ("TuneRunConfig", tuneRunConfigSchema)
  , ("RlRunConfig", rlRunConfigSchema)
  ]
