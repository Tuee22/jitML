module JitML.Lint.Chart
    ( checkChartFiles
    )
where

import System.Directory (doesDirectoryExist)

import JitML.Lint.Stack.Types (LintFinding (..))

checkChartFiles :: IO [LintFinding]
checkChartFiles = do
    exists <- doesDirectoryExist "chart"
    if exists
        then checkChartWhenPresent
        else pure []

checkChartWhenPresent :: IO [LintFinding]
checkChartWhenPresent = do
    pure []
