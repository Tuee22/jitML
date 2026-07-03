{-# LANGUAGE OverloadedStrings #-}

module JitML.Lint.Docs
  ( ClosureClaim (..)
  , closureClaimKey
  , scanClosureClaims
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

data ClosureClaim = ClosureClaim
  { closureClaimPath :: FilePath
  , closureClaimLineNumber :: Int
  , closureClaimPhrase :: Text
  , closureClaimLine :: Text
  }
  deriving stock (Eq, Show)

scanClosureClaims :: Bool -> FilePath -> Text -> [ClosureClaim]
scanClosureClaims productPhasesDone path content
  | productPhasesDone = []
  | otherwise =
      concatMap scanBlock (markdownBlocks content)
 where
  scanBlock block
    | closureClaimBlockExempt block = []
    | otherwise = concatMap scanLine block
  scanLine (lineNumber, line) =
    [ ClosureClaim
        { closureClaimPath = path
        , closureClaimLineNumber = lineNumber
        , closureClaimPhrase = phrase
        , closureClaimLine = Text.strip line
        }
    | phrase <- closureClaimPhrases
    , phrase `Text.isInfixOf` normalize line
    ]

closureClaimKey :: ClosureClaim -> Text
closureClaimKey claim =
  "closure-claim." <> Text.replace " " "-" (closureClaimPhrase claim)

closureClaimPhrases :: [Text]
closureClaimPhrases =
  [ "all phases done"
  , "all phases are done"
  , "no-caveat product complete"
  , "no-caveat product is complete"
  , "no-caveat product handoff completed"
  , "production ready"
  , "production-ready"
  ]

closureClaimBlockExempt :: [(Int, Text)] -> Bool
closureClaimBlockExempt block =
  any
    blockContains
    [ "historical"
    , "for example"
    , "such as"
    , "may claim"
    , "must not claim"
    , "cannot claim"
    ]
 where
  blockText = normalize (Text.unlines (fmap snd block))
  blockContains phrase = phrase `Text.isInfixOf` blockText

markdownBlocks :: Text -> [[(Int, Text)]]
markdownBlocks =
  reverse . finish . foldl step ([], []) . zip [1 :: Int ..] . Text.lines
 where
  step (blocks, current) numberedLine@(_, line)
    | Text.null (Text.strip line) = (finishCurrent blocks current, [])
    | otherwise = (blocks, numberedLine : current)
  finish (blocks, current) = finishCurrent blocks current
  finishCurrent blocks [] = blocks
  finishCurrent blocks current = reverse current : blocks

normalize :: Text -> Text
normalize =
  Text.toCaseFold
