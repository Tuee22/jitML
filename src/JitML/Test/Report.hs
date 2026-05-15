{-# LANGUAGE OverloadedStrings #-}

module JitML.Test.Report
  ( ReportCard (..)
  , reportStanzas
  , renderReportCard
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

data ReportCard = ReportCard
  { reportPassed :: Int
  , reportFailed :: Int
  , reportDurationSeconds :: Int
  }
  deriving stock (Eq, Show)

reportStanzas :: [Text]
reportStanzas =
  [ "jitml-unit"
  , "jitml-integration"
  , "jitml-sl-canonicals"
  , "jitml-rl-canonicals"
  , "jitml-hyperparameter"
  , "jitml-cross-backend"
  , "jitml-daemon-lifecycle"
  , "jitml-e2e"
  , "jitml-haskell-style"
  , "jitml-purescript-style"
  ]

renderReportCard :: ReportCard -> Text
renderReportCard report =
  Text.unlines
    [ "passed: " <> Text.pack (show (reportPassed report))
    , "failed: " <> Text.pack (show (reportFailed report))
    , "duration_seconds: " <> Text.pack (show (reportDurationSeconds report))
    ]
