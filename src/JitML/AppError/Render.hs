{-# LANGUAGE OverloadedStrings #-}

module JitML.AppError.Render
  ( renderError
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.AppError.AppError (AppError (..))
import JitML.Sub.Outcome
  ( renderProcessAttemptFailure
  , renderProcessFailure
  )

renderError :: AppError -> Text
renderError (PrerequisiteUnmet nodeId description remedyHint) =
  Text.unlines
    ( [ "prerequisite unmet: " <> nodeId
      , "description: " <> description
      ]
        <> maybe [] (\hint -> ["remedy: " <> hint]) remedyHint
    )
renderError (SubprocessFailed failure) =
  "subprocess failed:\n" <> renderProcessFailure failure
renderError (SubprocessAttemptFailed failure) =
  "subprocess attempt failed:\n" <> renderProcessAttemptFailure failure
renderError (MinIOFailed message) =
  renderSingle "minio failed" message
renderError (PulsarFailed message) =
  renderSingle "pulsar failed" message
renderError (HarborFailed message) =
  renderSingle "harbor failed" message
renderError (KubectlFailed message) =
  renderSingle "kubectl failed" message
renderError (DocsCheckDrift message) =
  ensureFinalNewline message
renderError (UnknownCommand message) =
  ensureFinalNewline message
renderError (InvalidConfig message) =
  renderSingle "invalid config" message
renderError (DhallTypeError message) =
  renderSingle "dhall type error" message
renderError (ChartLintFailed message) =
  ensureFinalNewline message
renderError (RouteRegistryDrift message) =
  renderSingle "route registry drift" message
renderError (JitCacheMiss message) =
  renderSingle "jit cache miss" message
renderError (JitToolchainDrift message) =
  renderSingle "jit toolchain drift" message
renderError (CheckpointFormatUnsupported message) =
  renderSingle "checkpoint format unsupported" message
renderError (CheckpointWriteConflict message) =
  renderSingle "checkpoint write conflict" message
renderError (InferenceCheckpointMissing experimentHash) =
  renderSingle "inference checkpoint missing" experimentHash
renderError (InferenceManifestShaMismatch experimentHash manifestSha) =
  renderSingle
    "inference manifest sha mismatch"
    (experimentHash <> ": requested " <> manifestSha)
renderError (TrainingPrerequisiteUnmet message) =
  renderSingle "training prerequisite unmet" message
renderError (ReconcilerNoop message) =
  ensureFinalNewline message

renderSingle :: Text -> Text -> Text
renderSingle label message =
  Text.unlines [label <> ": " <> message]

ensureFinalNewline :: Text -> Text
ensureFinalNewline value
  | Text.isSuffixOf "\n" value = value
  | otherwise = value <> "\n"
