{-# LANGUAGE OverloadedStrings #-}

module JitML.Lint.ForbiddenPaths
  ( ForbiddenPathRule (..)
  , forbiddenPathRegistry
  , matchForbiddenPath
  )
where

import Data.List (isPrefixOf, isSuffixOf)
import Data.Text (Text)

data ForbiddenPathRule = ForbiddenPathRule
  { forbiddenKey :: Text
  , forbiddenPattern :: FilePath
  , forbiddenCanonicalCommand :: Text
  }
  deriving stock (Eq, Show)

forbiddenPathRegistry :: [ForbiddenPathRule]
forbiddenPathRegistry =
  [ ForbiddenPathRule ".github/workflows" ".github/workflows/" "jitml lint all"
  , ForbiddenPathRule ".husky" ".husky/" "jitml lint all"
  , ForbiddenPathRule ".githooks" ".githooks/" "jitml lint all"
  , ForbiddenPathRule ".pre-commit-config.yaml" ".pre-commit-config.yaml" "jitml lint all"
  , ForbiddenPathRule "pre-commit-*.yaml" "pre-commit-*.yaml" "jitml lint all"
  , ForbiddenPathRule "Makefile" "Makefile" "jitml build"
  , ForbiddenPathRule "justfile" "justfile" "jitml commands"
  , ForbiddenPathRule "Taskfile.yml" "Taskfile.yml" "jitml commands"
  ]

matchForbiddenPath :: FilePath -> Maybe ForbiddenPathRule
matchForbiddenPath path =
  firstMatch (filter (matchesRule path) forbiddenPathRegistry)

matchesRule :: FilePath -> ForbiddenPathRule -> Bool
matchesRule path rule
  | forbiddenPattern rule == "pre-commit-*.yaml" =
      "pre-commit-" `isPrefixOf` path && ".yaml" `isSuffixOf` path
  | "/" `isSuffixOf` forbiddenPattern rule =
      forbiddenPattern rule `isPrefixOf` path
  | otherwise =
      path == forbiddenPattern rule

firstMatch :: [a] -> Maybe a
firstMatch [] = Nothing
firstMatch (value : _) = Just value
