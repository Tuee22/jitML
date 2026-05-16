{-# LANGUAGE OverloadedStrings #-}

module JitML.Lint.DhallRL
  ( checkDhallRL
  )
where

import Control.Exception (SomeException, try)
import Data.Text qualified as Text

import JitML.Lint.Stack.Types (LintFinding (..))
import JitML.RL.Schema
  ( RlCatalogSchema
  , loadRlCatalogSchema
  , rlSchemaPath
  , validateRlCatalogSchema
  )

checkDhallRL :: IO [LintFinding]
checkDhallRL = do
  result <- try (loadRlCatalogSchema ".") :: IO (Either SomeException RlCatalogSchema)
  case result of
    Left err ->
      pure
        [ LintFinding
            rlSchemaPath
            "dhall.rl.decode"
            "RL Dhall schema failed to decode"
            (Text.pack (show err))
        ]
    Right catalog ->
      pure
        [ LintFinding
            rlSchemaPath
            "dhall.rl.drift"
            "RL Dhall schema differs from the Haskell catalog"
            (Text.intercalate "\n" mismatches)
        | Left mismatches <- [validateRlCatalogSchema catalog]
        ]
