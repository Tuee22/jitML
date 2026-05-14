{-# LANGUAGE OverloadedStrings #-}

module JitML.Lint.Stack.Types
    ( LintFinding (..)
    , LintMode (..)
    , LintTarget (..)
    )
where

import Data.Text (Text)

data LintTarget
    = LintFiles
    | LintDocs
    | LintProto
    | LintChart
    | LintHaskell
    | LintPurescript
    | LintAll
    deriving stock (Eq, Show)

data LintMode
    = LintCheck
    | LintWrite
    deriving stock (Eq, Show)

data LintFinding = LintFinding
    { findingPath :: FilePath
    , findingKey :: Text
    , findingMessage :: Text
    , findingRemedy :: Text
    }
    deriving stock (Eq, Show)
