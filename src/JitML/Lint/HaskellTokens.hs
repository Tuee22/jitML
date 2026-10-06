{-# LANGUAGE OverloadedStrings #-}

-- | A small, permissive tokenizer for Haskell source, sufficient for structural
-- lints that must see through formatting.
--
-- Comments (line, nested block, and pragma) are dropped; string and character
-- literals become one token; brackets, separators, and operators are kept.
-- Every token records its physical line and column and whether it opens its
-- line, which is all the layout information a lint needs to decide where an
-- expression continues. The tokenizer is total: text it cannot classify is
-- skipped rather than rejected, so a lint built on it can only under-report on
-- unusual input, never fail.
module JitML.Lint.HaskellTokens
  ( Token (..)
  , TokenKind (..)
  , tokenize
  )
where

import Data.Char
  ( isAlpha
  , isAlphaNum
  , isAscii
  , isDigit
  , isHexDigit
  , isPunctuation
  , isSpace
  , isSymbol
  , isUpper
  )
import Data.Text (Text)
import Data.Text qualified as Text

data TokenKind
  = -- | An identifier, keyword, or qualified name such as @Mod.name@.
    WordToken
  | -- | A numeric literal, including fractions, exponents, and radix forms.
    NumberToken
  | -- | A string or character literal.
    LiteralToken
  | -- | An operator run or the separators @,@, @;@, and a backtick.
    SymbolToken
  | -- | One of @(@, @[@, @{@.
    OpenToken
  | -- | One of @)@, @]@, @}@.
    CloseToken
  deriving stock (Eq, Show)

data Token = Token
  { tokenLine :: !Int
  , tokenColumn :: !Int
  , tokenFirstOnLine :: !Bool
  , tokenLineIndent :: !Int
  -- ^ Column of the first token on this token's physical line.
  , tokenKind :: !TokenKind
  , tokenText :: !Text
  }
  deriving stock (Eq, Show)

data RawToken = RawToken !Int !Int !TokenKind !Text

tokenize :: Text -> [Token]
tokenize = annotate 0 0 . scan 1 1

annotate :: Int -> Int -> [RawToken] -> [Token]
annotate _ _ [] = []
annotate previousLine indent (RawToken line column kind text : rest)
  | line /= previousLine =
      Token line column True column kind text : annotate line column rest
  | otherwise =
      Token line column False indent kind text : annotate line indent rest

scan :: Int -> Int -> Text -> [RawToken]
scan !line !column input =
  case Text.uncons input of
    Nothing -> []
    Just (char, rest)
      | char == '\n' -> scan (line + 1) 1 rest
      | char == '\t' -> scan line (nextTabStop column) rest
      | isSpace char -> scan line (column + 1) rest
      | Just (comment, remaining) <- blockComment input -> skip comment remaining
      | Just (comment, remaining) <- lineComment input -> skip comment remaining
      | char == '"' ->
          let (literal, remaining) = stringLiteral input
           in emit LiteralToken literal remaining
      | char == '\''
      , Just (literal, remaining) <- charLiteral input ->
          emit LiteralToken literal remaining
      | isDigit char ->
          let (number, remaining) = numberLiteral input
           in emit NumberToken number remaining
      | isIdentifierStart char ->
          let (word, remaining) = identifier input
           in emit WordToken word remaining
      | char `elem` ("([{" :: String) -> emit OpenToken (Text.singleton char) rest
      | char `elem` (")]}" :: String) -> emit CloseToken (Text.singleton char) rest
      | char `elem` (",;`" :: String) -> emit SymbolToken (Text.singleton char) rest
      | isSymbolChar char ->
          let (run, remaining) = Text.span isSymbolChar input
           in emit SymbolToken run remaining
      | otherwise -> scan line (column + 1) rest
 where
  emit kind text remaining = RawToken line column kind text : skip text remaining
  skip consumed remaining =
    let (nextLine, nextColumn) = advance line column consumed
     in scan nextLine nextColumn remaining

advance :: Int -> Int -> Text -> (Int, Int)
advance line column =
  Text.foldl' step (line, column)
 where
  step (currentLine, currentColumn) char
    | char == '\n' = (currentLine + 1, 1)
    | char == '\t' = (currentLine, nextTabStop currentColumn)
    | otherwise = (currentLine, currentColumn + 1)

nextTabStop :: Int -> Int
nextTabStop column = ((column - 1) `div` 8 + 1) * 8 + 1

symbolChars :: String
symbolChars = "!#$%&*+./<=>?@\\^|-~:"

isSymbolChar :: Char -> Bool
isSymbolChar char
  | isAscii char = char `elem` symbolChars
  | otherwise = isSymbol char || isPunctuation char

isIdentifierStart :: Char -> Bool
isIdentifierStart char = isAlpha char || char == '_'

isIdentifierChar :: Char -> Bool
isIdentifierChar char = isAlphaNum char || char == '_' || char == '\''

-- | A nested block comment, pragma included: @{- ... -}@.
blockComment :: Text -> Maybe (Text, Text)
blockComment input
  | "{-" `Text.isPrefixOf` input =
      Just (Text.splitAt (go (1 :: Int) 2 (Text.drop 2 input)) input)
  | otherwise = Nothing
 where
  go depth consumed remaining
    | depth == 0 = consumed
    | "-}" `Text.isPrefixOf` remaining = go (depth - 1) (consumed + 2) (Text.drop 2 remaining)
    | "{-" `Text.isPrefixOf` remaining = go (depth + 1) (consumed + 2) (Text.drop 2 remaining)
    | otherwise =
        case Text.uncons remaining of
          Nothing -> consumed
          Just (_, more) -> go depth (consumed + 1) more

-- | A line comment: two or more dashes that are not part of a longer operator.
lineComment :: Text -> Maybe (Text, Text)
lineComment input
  | Text.length dashes >= 2 && maybe True (not . isSymbolChar . fst) (Text.uncons afterDashes) =
      Just (Text.break (== '\n') input)
  | otherwise = Nothing
 where
  (dashes, afterDashes) = Text.span (== '-') input

-- | A string literal, escapes and string gaps included. An unterminated string
-- ends at its line.
stringLiteral :: Text -> (Text, Text)
stringLiteral input = Text.splitAt (body 1 (Text.drop 1 input)) input
 where
  body consumed remaining =
    case Text.uncons remaining of
      Nothing -> consumed
      Just ('"', _) -> consumed + 1
      Just ('\n', _) -> consumed
      Just ('\\', more) ->
        case Text.uncons more of
          Nothing -> consumed + 1
          Just (escaped, after)
            | isSpace escaped -> gap (consumed + 2) after
            | otherwise -> body (consumed + 2) after
      Just (_, more) -> body (consumed + 1) more
  gap consumed remaining =
    case Text.uncons remaining of
      Nothing -> consumed
      Just ('\\', after) -> body (consumed + 1) after
      Just (_, after) -> gap (consumed + 1) after

-- | A character literal. A tick that does not close as one, such as a promotion
-- tick, is not a literal.
charLiteral :: Text -> Maybe (Text, Text)
charLiteral input =
  case Text.unpack (Text.take 10 (Text.drop 1 input)) of
    '\\' : _ : rest
      | Just closing <- lookup' '\'' rest -> Just (Text.splitAt (4 + closing) input)
    char : '\'' : _
      | char /= '\'' && char /= '\\' -> Just (Text.splitAt 3 input)
    _ -> Nothing
 where
  lookup' target = go (0 :: Int)
   where
    go _ [] = Nothing
    go index (char : rest)
      | char == target = Just index
      | otherwise = go (index + 1) rest

-- | A numeric literal: radix forms, or decimal digits with an optional
-- fraction and exponent. A fraction or exponent is part of the literal only
-- when digits follow, so an enumeration @[1..5]@ keeps its @..@.
numberLiteral :: Text -> (Text, Text)
numberLiteral input =
  case Text.unpack (Text.take 3 input) of
    '0' : radix : digit : _
      | radix `elem` ("xX" :: String) && isHexDigit digit -> radixLiteral isHexDigit
      | radix `elem` ("oO" :: String) && isDigit digit -> radixLiteral isDigit
      | radix `elem` ("bB" :: String) && isDigit digit -> radixLiteral isDigit
    _ -> Text.splitAt (whole + fraction + exponentWidth) input
 where
  radixLiteral isRadixDigit =
    Text.splitAt
      (2 + Text.length (Text.takeWhile (\c -> isRadixDigit c || c == '_') (Text.drop 2 input)))
      input
  isDecimalChar char = isDigit char || char == '_'
  whole = Text.length (Text.takeWhile isDecimalChar input)
  afterWhole = Text.drop whole input
  fraction =
    case Text.uncons afterWhole of
      Just ('.', more)
        | Just (digit, _) <- Text.uncons more
        , isDigit digit ->
            1 + Text.length (Text.takeWhile isDecimalChar more)
      _ -> 0
  afterFraction = Text.drop fraction afterWhole
  exponentWidth =
    case Text.uncons afterFraction of
      Just (marker, more)
        | marker `elem` ("eE" :: String) ->
            let (sign, digits) =
                  case Text.uncons more of
                    Just (signChar, afterSign) | signChar `elem` ("+-" :: String) -> (1, afterSign)
                    _ -> (0, more)
             in case Text.uncons digits of
                  Just (digit, _)
                    | isDigit digit ->
                        1 + sign + Text.length (Text.takeWhile isDecimalChar digits)
                  _ -> 0
      _ -> 0

-- | An identifier, extended over module qualification: @Data.Text.pack@ is one
-- token, as is a qualified constructor. Qualification continues only from a
-- component that starts with a capital letter.
identifier :: Text -> (Text, Text)
identifier input = Text.splitAt (go 0 input) input
 where
  go consumed remaining =
    let width = Text.length (Text.takeWhile isIdentifierChar remaining)
        afterSegment = Text.drop width remaining
        capitalised = maybe False (isUpper . fst) (Text.uncons remaining)
     in case Text.uncons afterSegment of
          Just ('.', more)
            | capitalised
            , Just (next, _) <- Text.uncons more
            , isIdentifierStart next ->
                go (consumed + width + 1) more
          _ -> consumed + width
