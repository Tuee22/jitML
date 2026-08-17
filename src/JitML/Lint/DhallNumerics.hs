{-# LANGUAGE OverloadedStrings #-}

module JitML.Lint.DhallNumerics
  ( checkDhallNumerics
  , mlDslDhallFiles
  )
where

import Control.Exception (SomeException, try)
import Data.List qualified as List
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import System.Directory (doesDirectoryExist, listDirectory)
import System.FilePath (takeExtension, (</>))

import JitML.Lint.Stack.Types (LintFinding (..))
import JitML.Numerics.LayerDhall
  ( layerOpAuditMismatches
  , layerOpSchemaPath
  , mlDslSubstrateMentions
  , numericsTypeFileSchemas
  )
import JitML.Numerics.Schema
  ( NumericsCatalog
  , loadNumericsCatalog
  , numericsSchemaPath
  , validateNumericsCatalog
  )
import JitML.Service.DhallSchema (canonicalDhallType)

-- | The numerical Dhall drift audit run by @jitml lint haskell@. Four rules:
--
--   * the aggregate catalog decodes, and its constructor-name lists match the
--     Haskell catalog (the original Sprint `77.1` surface);
--   * the reflected /operator/ schema's alternatives are exactly the executed
--     'JitML.Numerics.LayerGraph.LayerOp' constructors, and each projects onto
--     exactly one catalog constructor (the audit extended to the executed
--     operator);
--   * each checked-in reflected type file equals what the live decoder reflects;
--   * no ML-describing Dhall file names a @substrate@ — an architecture is
--     substrate-independent and substrate selection lives on the CLI/plan seam.
checkDhallNumerics :: IO [LintFinding]
checkDhallNumerics = do
  catalogFindings <- checkCatalogDrift
  typeFileFindings <- checkReflectedTypeFiles
  dslFindings <- checkMlDslSubstrateFree
  pure (catalogFindings <> operatorFindings <> typeFileFindings <> dslFindings)

checkCatalogDrift :: IO [LintFinding]
checkCatalogDrift = do
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

operatorFindings :: [LintFinding]
operatorFindings =
  [ LintFinding
      layerOpSchemaPath
      "dhall.numerics.operator-drift"
      "reflected layer-operator schema differs from the executed LayerOp vocabulary"
      (Text.intercalate "\n" layerOpAuditMismatches)
  | not (null layerOpAuditMismatches)
  ]

checkReflectedTypeFiles :: IO [LintFinding]
checkReflectedTypeFiles =
  concat
    <$> traverse
      ( \(path, reflected) -> do
          existing <- try (Text.IO.readFile path) :: IO (Either SomeException Text.Text)
          pure $ case existing of
            Left err ->
              [ LintFinding
                  path
                  "dhall.numerics.reflected-missing"
                  "reflected numerical type file is unreadable"
                  (Text.pack (show err))
              ]
            Right contents ->
              [ LintFinding
                  path
                  "dhall.numerics.reflected-drift"
                  "checked-in numerical type file differs from the reflected decoder type"
                  "regenerate with `jitml internal dhall-schema --config <name>`"
              | canonicalDhallType contents /= canonicalDhallType reflected
              ]
      )
      numericsTypeFileSchemas

checkMlDslSubstrateFree :: IO [LintFinding]
checkMlDslSubstrateFree = do
  paths <- mlDslDhallFiles
  files <- traverse (\path -> (,) path <$> Text.IO.readFile path) paths
  pure
    [ LintFinding
        path
        "dhall.numerics.substrate-in-ml-dsl"
        "ML-describing Dhall file names a substrate"
        "substrate selection belongs on the CLI/plan seam, not in the ML DSL"
    | path <- mlDslSubstrateMentions files
    ]

-- | Every ML-describing Dhall file: the numerical schema leaves and the
-- configuration-as-code experiment fixtures. Deliberately excludes
-- @dhall/service@, @dhall/cluster@, and @dhall/run@, which are the plan/CLI
-- seam and legitimately carry a substrate.
mlDslDhallFiles :: IO [FilePath]
mlDslDhallFiles =
  fmap (List.sort . concat) (traverse dhallFilesIn ["dhall/numerics", "experiments"])

dhallFilesIn :: FilePath -> IO [FilePath]
dhallFilesIn root = do
  present <- doesDirectoryExist root
  if not present
    then pure []
    else do
      entries <- listDirectory root
      concat <$> traverse (classify . (root </>)) (List.sort entries)
 where
  classify path = do
    isDirectory <- doesDirectoryExist path
    if isDirectory
      then dhallFilesIn path
      else pure [path | takeExtension path == ".dhall"]
