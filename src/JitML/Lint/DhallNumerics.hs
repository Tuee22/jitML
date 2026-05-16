{-# LANGUAGE OverloadedStrings #-}

module JitML.Lint.DhallNumerics
  ( checkDhallNumerics
  )
where

import Control.Exception (SomeException, try)
import Data.Text qualified as Text

import JitML.Lint.Stack.Types (LintFinding (..))
import JitML.Numerics.Schema
  ( NumericsCatalog
  , loadNumericsCatalog
  , numericsSchemaPath
  , validateNumericsCatalog
  )

checkDhallNumerics :: IO [LintFinding]
checkDhallNumerics = do
  result <- try (loadNumericsCatalog ".") :: IO (Either SomeException NumericsCatalog)
  case result of
    Left err ->
      pure
        [ LintFinding
            numericsSchemaPath
            "dhall.numerics.decode"
            "numerical Dhall schema failed to decode"
            (Text.pack (show err))
        ]
    Right catalog ->
      pure
        [ LintFinding
            numericsSchemaPath
            "dhall.numerics.drift"
            "numerical Dhall schema differs from the Haskell catalog"
            (Text.intercalate "\n" mismatches)
        | Left mismatches <- [validateNumericsCatalog catalog]
        ]
