{-# LANGUAGE OverloadedStrings #-}

module JitML.Docs.Check
  ( DocsDrift (..)
  , checkDocs
  , renderDocsDrift
  , replaceGeneratedSection
  )
where

import Data.List (findIndex)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import System.Directory (doesFileExist)

import JitML.Generated.Paths (TrackedGeneratedPath (..), trackingGeneratedPaths)
import JitML.Generated.Registry
  ( GeneratedSectionRule (..)
  , endMarker
  , generatedSectionRules
  , startMarker
  )

data DocsDrift = DocsDrift
  { driftPath :: FilePath
  , driftKey :: Text
  , driftReason :: Text
  }
  deriving stock (Eq, Show)

checkDocs :: IO [DocsDrift]
checkDocs = do
  sectionDrifts <- concat <$> traverse checkGeneratedSection generatedSectionRules
  pathDrifts <- concat <$> traverse checkTrackedGeneratedPath trackingGeneratedPaths
  pure (sectionDrifts <> pathDrifts)

renderDocsDrift :: DocsDrift -> Text
renderDocsDrift drift =
  Text.unlines
    [ "file: " <> Text.pack (driftPath drift)
    , "key: " <> driftKey drift
    , "Run `jitml docs generate` to update."
    ]

checkGeneratedSection :: GeneratedSectionRule -> IO [DocsDrift]
checkGeneratedSection rule = do
  exists <- doesFileExist (rulePath rule)
  if exists
    then do
      current <- Text.IO.readFile (rulePath rule)
      case replaceGeneratedSection rule current of
        Left reason -> pure [sectionDrift rule reason]
        Right expected
          | expected == current -> pure []
          | otherwise -> pure [sectionDrift rule "generated section drift"]
    else pure [sectionDrift rule "file is missing"]

checkTrackedGeneratedPath :: TrackedGeneratedPath -> IO [DocsDrift]
checkTrackedGeneratedPath tracked = do
  exists <- doesFileExist (trackedPath tracked)
  if exists
    then do
      current <- Text.IO.readFile (trackedPath tracked)
      if current == ensureFinalNewline (trackedRendered tracked)
        then pure []
        else pure [pathDrift tracked "tracked-generated file drift"]
    else pure [pathDrift tracked "tracked-generated file is missing"]

replaceGeneratedSection :: GeneratedSectionRule -> Text -> Either Text Text
replaceGeneratedSection rule current = do
  startIndex <-
    maybe
      (Left "start marker is missing")
      Right
      (findIndex ((== startMarker (ruleKey rule)) . Text.strip) currentLines)
  endIndex <-
    maybe
      (Left "end marker is missing")
      Right
      (findIndex ((== endMarker (ruleKey rule)) . Text.strip) currentLines)
  if startIndex >= endIndex
    then Left "start marker appears after end marker"
    else
      Right $
        Text.unlines $
          take (startIndex + 1) currentLines
            <> Text.lines (ensureFinalNewline (ruleRendered rule))
            <> drop endIndex currentLines
 where
  currentLines = Text.lines current

sectionDrift :: GeneratedSectionRule -> Text -> DocsDrift
sectionDrift rule reason =
  DocsDrift
    { driftPath = rulePath rule
    , driftKey = ruleKey rule
    , driftReason = reason
    }

pathDrift :: TrackedGeneratedPath -> Text -> DocsDrift
pathDrift tracked reason =
  DocsDrift
    { driftPath = trackedPath tracked
    , driftKey = trackedKey tracked
    , driftReason = reason
    }

ensureFinalNewline :: Text -> Text
ensureFinalNewline value
  | Text.isSuffixOf "\n" value = value
  | otherwise = value <> "\n"
