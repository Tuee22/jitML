{-# LANGUAGE OverloadedStrings #-}

-- | A small, total scanner over this repository's Haskell sources, used by the
-- guards that assert which modules may import (or opt out of the warning of)
-- the raw evidence boundary.
--
-- It tokenises rather than matching lines, so the import forms a line matcher
-- misses are found: the keywords split across lines, a package string, a
-- @SOURCE@ pragma, @safe@, and the post-positive @qualified@. Comments,
-- pragmas, string literals and character literals are lexed and skipped, so
-- neither a commented-out import nor an import-looking string is one. Sources
-- are read as UTF-8 whatever the locale, because a locale-encoded read fails
-- on the non-ASCII characters the sources contain when @LC_ALL=C@.
module SourceScan
  ( Lexeme (..)
  , importedModules
  , lexSource
  , optionsGhcFlags
  , pragmaBodies
  , readSourceUtf8
  , sourceFiles
  )
where

import Data.Char (isAlphaNum, isSpace)
import Data.List (sort)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO.Utf8 qualified as Utf8
import System.Directory (doesDirectoryExist, listDirectory)
import System.FilePath (takeExtension, (</>))

-- | One significant token of a Haskell source. Comments never appear.
data Lexeme
  = -- | A pragma: its upper-cased name and its remaining body.
    PragmaLexeme Text Text
  | -- | An identifier, a keyword, or a dotted module name.
    WordLexeme Text
  | -- | A string or character literal; its contents are never inspected.
    LiteralLexeme
  | -- | Any other single character.
    SymbolLexeme Char
  deriving stock (Eq, Show)

-- | Tokenise a Haskell source. Total: an unterminated comment, string, or
-- pragma ends the token stream instead of failing.
lexSource :: Text -> [Lexeme]
lexSource text =
  case Text.uncons text of
    Nothing -> []
    Just (char, rest)
      | isSpace char -> lexSource rest
      | Just body <- Text.stripPrefix "{-#" text -> pragma body
      | Just body <- Text.stripPrefix "{-" text -> lexSource (skipBlockComment (1 :: Int) body)
      | isLineComment text -> lexSource (Text.dropWhile (/= '\n') text)
      | char == '"' -> LiteralLexeme : lexSource (skipString rest)
      | char == '\''
      , Just afterLiteral <- characterLiteral rest ->
          LiteralLexeme : lexSource afterLiteral
      | isWordChar char ->
          let (word, remainder) = Text.span isWordChar text
           in WordLexeme word : lexSource remainder
      | otherwise -> SymbolLexeme char : lexSource rest
 where
  pragma afterOpen =
    let (inner, afterInner) = Text.breakOn "#-}" afterOpen
        (name, body) = Text.break isSpace (Text.stripStart inner)
     in PragmaLexeme (Text.toUpper name) (Text.strip body)
          : lexSource (Text.drop 3 afterInner)

isWordChar :: Char -> Bool
isWordChar char = isAlphaNum char || char == '_' || char == '\'' || char == '.'

-- | A run of two or more dashes that is not part of a longer operator starts a
-- comment that ends at the newline.
isLineComment :: Text -> Bool
isLineComment text =
  case Text.span (== '-') text of
    (dashes, afterDashes)
      | Text.length dashes >= 2 -> maybe True (not . isSymbolChar . fst) (Text.uncons afterDashes)
    _ -> False
 where
  isSymbolChar char = char `elem` ("!#$%&*+./<=>?@\\^|~:" :: String)

skipBlockComment :: Int -> Text -> Text
skipBlockComment depth text
  | depth <= 0 = text
  | otherwise =
      case Text.uncons text of
        Nothing -> ""
        Just ('-', afterDash)
          | Just afterClose <- Text.stripPrefix "}" afterDash -> skipBlockComment (depth - 1) afterClose
        Just ('{', afterBrace)
          | Just afterOpen <- Text.stripPrefix "-" afterBrace -> skipBlockComment (depth + 1) afterOpen
        Just (_, rest) -> skipBlockComment depth rest

-- | The text after a string literal whose opening quote was just consumed.
skipString :: Text -> Text
skipString text =
  case Text.uncons text of
    Nothing -> ""
    Just ('"', rest) -> rest
    Just ('\\', rest) -> skipString (Text.drop 1 rest)
    Just (_, rest) -> skipString rest

-- | The text after a character literal whose opening quote was just consumed,
-- or 'Nothing' when the quote is not a literal's (a promoted constructor, for
-- example @'Declared@, has no closing quote one character on).
characterLiteral :: Text -> Maybe Text
characterLiteral text =
  case Text.uncons text of
    Just ('\\', afterEscape) ->
      Just (Text.drop 1 (Text.dropWhile (/= '\'') (Text.drop 1 afterEscape)))
    Just (_, afterChar) -> Text.stripPrefix "'" afterChar
    Nothing -> Nothing

-- | The modules a source imports, in order. A module name is the first word
-- after @import@ once the optional @SOURCE@ pragma, @safe@, @qualified@, and
-- package string are skipped, wherever the layout puts them.
importedModules :: Text -> [Text]
importedModules = go . lexSource
 where
  go lexemes =
    case lexemes of
      WordLexeme "import" : rest ->
        case dropWhile isQualifier rest of
          WordLexeme moduleName : afterName -> moduleName : go afterName
          afterQualifiers -> go afterQualifiers
      _ : rest -> go rest
      [] -> []
  isQualifier lexeme =
    case lexeme of
      WordLexeme "qualified" -> True
      WordLexeme "safe" -> True
      LiteralLexeme -> True
      PragmaLexeme "SOURCE" _ -> True
      _ -> False

-- | The bodies of every pragma with the given upper-case name, in order.
pragmaBodies :: Text -> Text -> [Text]
pragmaBodies name source = [body | PragmaLexeme found body <- lexSource source, found == name]

-- | Every flag any @OPTIONS_GHC@ (or legacy @OPTIONS@) pragma of a source sets.
optionsGhcFlags :: Text -> [Text]
optionsGhcFlags source =
  concatMap Text.words (pragmaBodies "OPTIONS_GHC" source <> pragmaBodies "OPTIONS" source)

-- | Every @.hs@ file under the given roots, as a sorted list of relative paths.
-- A root that does not exist contributes nothing.
sourceFiles :: [FilePath] -> IO [FilePath]
sourceFiles roots = sort . concat <$> mapM walk roots
 where
  walk root = do
    exists <- doesDirectoryExist root
    if exists
      then do
        entries <- listDirectory root
        concat <$> mapM (visit . (root </>)) entries
      else pure []
  visit path = do
    isDirectory <- doesDirectoryExist path
    if isDirectory
      then walk path
      else pure [path | takeExtension path == ".hs"]

-- | Read a source as UTF-8, independent of the process locale.
readSourceUtf8 :: FilePath -> IO Text
readSourceUtf8 = Utf8.readFile
