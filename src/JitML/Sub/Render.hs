{-# LANGUAGE OverloadedStrings #-}

module JitML.Sub.Render
  ( renderBool
  , renderSubprocess
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Sub.Subprocess (Subprocess (..))

-- | The one @yes@/@no@ rendering used by every runtime-probe summary. Sprint
-- `79.1` folded six byte-identical copies into this definition.
renderBool :: Bool -> Text
renderBool True = "yes"
renderBool False = "no"

renderSubprocess :: Subprocess -> Text
renderSubprocess subprocessValue =
  Text.unwords $
    cwdPrefix
      <> fmap quoteShell (Text.pack (subprocessPath subprocessValue) : subprocessArguments subprocessValue)
 where
  cwdPrefix =
    case subprocessWorkingDirectory subprocessValue of
      Nothing -> []
      Just cwd -> ["cd", quoteShell (Text.pack cwd), "&&"]

quoteShell :: Text -> Text
quoteShell value
  | value == "" = "''"
  | Text.all isShellSafe value = value
  | otherwise = "'" <> Text.replace "'" "'\\''" value <> "'"

isShellSafe :: Char -> Bool
isShellSafe char =
  char `elem` safeChars

safeChars :: [Char]
safeChars =
  ['a' .. 'z']
    <> ['A' .. 'Z']
    <> ['0' .. '9']
    <> "-_./:=+@%,"
