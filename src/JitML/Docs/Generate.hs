{-# LANGUAGE OverloadedStrings #-}

module JitML.Docs.Generate
    ( GenerateResult (..)
    , generateDocs
    )
where

import Control.Exception (IOException, try)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import System.Directory (createDirectoryIfMissing, doesFileExist, renameFile)
import System.FilePath (takeDirectory)
import System.IO.Error (isDoesNotExistError)

import JitML.Docs.Check (DocsDrift (..), replaceGeneratedSection)
import JitML.Generated.Paths (TrackedGeneratedPath (..), trackingGeneratedPaths)
import JitML.Generated.Registry (GeneratedSectionRule (..), generatedSectionRules)

data GenerateResult
    = GeneratedChanged
    | GeneratedNoop
    deriving stock (Eq, Show)

generateDocs :: IO (Either [DocsDrift] GenerateResult)
generateDocs = do
    sectionResults <- traverse generateSection generatedSectionRules
    pathResults <- traverse generateTrackedGeneratedPath trackingGeneratedPaths
    let errors = [err | Left err <- sectionResults]
    if null errors
        then
            pure $
                Right $
                    if or (rights sectionResults <> pathResults)
                        then GeneratedChanged
                        else GeneratedNoop
        else pure (Left errors)

generateSection :: GeneratedSectionRule -> IO (Either DocsDrift Bool)
generateSection rule = do
    readResult <- tryReadTextFile (rulePath rule)
    case readResult of
        Left reason ->
            pure $
                Left
                    DocsDrift
                        { driftPath = rulePath rule
                        , driftKey = ruleKey rule
                        , driftReason = reason
                        }
        Right current ->
            case replaceGeneratedSection rule current of
                Left reason ->
                    pure $
                        Left
                            DocsDrift
                                { driftPath = rulePath rule
                                , driftKey = ruleKey rule
                                , driftReason = reason
                                }
                Right expected ->
                    Right <$> writeTextFileIfChanged (rulePath rule) expected

generateTrackedGeneratedPath :: TrackedGeneratedPath -> IO Bool
generateTrackedGeneratedPath tracked =
    writeTextFileIfChanged (trackedPath tracked) (ensureFinalNewline (trackedRendered tracked))

writeTextFileIfChanged :: FilePath -> Text -> IO Bool
writeTextFileIfChanged path expected = do
    exists <- doesFileExist path
    current <-
        if exists
            then Text.IO.readFile path
            else pure ""
    if current == expected
        then pure False
        else do
            createDirectoryIfMissing True (takeDirectory path)
            let tmpPath = path <> ".tmp"
            Text.IO.writeFile tmpPath expected
            renameFile tmpPath path
            pure True

tryReadTextFile :: FilePath -> IO (Either Text Text)
tryReadTextFile path = do
    result <- try (Text.IO.readFile path) :: IO (Either IOException Text)
    case result of
        Right content -> pure (Right content)
        Left err
            | isDoesNotExistError err -> pure (Left "file is missing")
            | otherwise -> pure (Left (Text.pack (show err)))

rights :: [Either left right] -> [right]
rights [] = []
rights (Right value : rest) = value : rights rest
rights (Left _ : rest) = rights rest

ensureFinalNewline :: Text -> Text
ensureFinalNewline value
    | Text.isSuffixOf "\n" value = value
    | otherwise = value <> "\n"
