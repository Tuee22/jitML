{-# LANGUAGE OverloadedStrings #-}

module JitML.AppError.AppError
    ( AppError (..)
    , exitCodeFor
    )
where

import Data.Text (Text)
import System.Exit (ExitCode (..))

data AppError
    = PrerequisiteUnmet Text Text (Maybe Text)
    | SubprocessFailed Text ExitCode Text
    | MinIOFailed Text
    | PulsarFailed Text
    | HarborFailed Text
    | KubectlFailed Text
    | DocsCheckDrift Text
    | UnknownCommand Text
    | InvalidConfig Text
    | DhallTypeError Text
    | ChartLintFailed Text
    | RouteRegistryDrift Text
    | JitCacheMiss Text
    | JitToolchainDrift Text
    | CheckpointFormatUnsupported Text
    | CheckpointWriteConflict Text
    | ReconcilerNoop Text
    deriving stock (Eq, Show)

exitCodeFor :: AppError -> ExitCode
exitCodeFor (PrerequisiteUnmet _ _ _) = ExitFailure 2
exitCodeFor (InvalidConfig _) = ExitFailure 2
exitCodeFor (ReconcilerNoop _) = ExitFailure 3
exitCodeFor _ = ExitFailure 1
