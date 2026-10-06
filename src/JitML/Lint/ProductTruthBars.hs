{-# LANGUAGE OverloadedStrings #-}

-- | Source-level guard against a product convergence bar that is derived from
-- the value it grades.
--
-- Runtime equality between a measurement and a literature target cannot
-- establish provenance: a valid run may land exactly on the target. The
-- declaration must therefore never take its target from a measurement, and the
-- scan looks at the declaration as a token stream, so the layout of the source
-- (a field split over lines, an argument on its own line, a value bound in a
-- @let@ or @where@ block) cannot hide a violation.
--
-- Two rules apply outside test-support code:
--
-- * /Measured-derived/ ('measuredBarMessage'): no target, slack, or threshold
--   expression may mention a measured value, directly or through any chain of
--   simple bindings ('taintedAliases').
-- * /Unsourced/ ('nonLiteralBarMessage'): every numeric argument of a bar or
--   cohort-threshold constructor (the smart constructors, the positional bar
--   constructor, and the fields of a bar record) must be a numeric literal or a
--   projection of the canonical threshold tables ('approvedProjections'),
--   possibly through a binding of one. A projection must be the whole argument,
--   a selector applied to plain arguments with nothing added to it, and a
--   cohort-threshold constructor accepts literals only. This is deliberately
--   fail-closed: a helper-wrapped or renamed value, or a table value with a
--   helper's value added to it, has no provenance the scan can see, so it is
--   rejected rather than trusted.
--
-- Test-support code under @src/JitML/Test/@ is exempt from both rules, because
-- it builds known-fake bars on purpose so the gates can prove they reject them;
-- the module that defines the bar record is exempt from the unsourced rule, as
-- its definitions pass their parameters through by construction.
--
-- An application is read from the constructor's own arguments up to the first
-- operator, so every numeric position present there is checked whether or not
-- the application is saturated, and a @$@ hands the rest of the expression over
-- as the last argument. An occurrence in a pattern or a definition head is
-- excused ('inBindingHead'): on the line where its arguments end, only
-- pattern-shaped tokens lead to an @=@, @->@, or @<-@. That covers constructor
-- and record patterns in function heads, case alternatives, lambdas, @let@
-- patterns, bind statements, and generators.
--
-- Known limits: a bar built through a partially applied or aliased constructor
-- (@uncurry@, an operator section, an applicative chain, @mk =
-- mkConvergenceBar@) is not followed past the arguments the constructor names.
-- A pattern whose arrow or guard bar is on a later line, or that has a guard
-- bar after it on its own line, is read as an application, so a threshold is
-- best taken apart with its field selectors. A binding is read only when its
-- @=@ or @<-@ shares the binder's line, which is the layout fourmolu (part of
-- @check-code@) produces; a binder whose @=@ opens its own line is not seen.
-- The lint is one gate among several; the external-bar predicates and the
-- registry cross-check are the others.
module JitML.Lint.ProductTruthBars
  ( barSourceFindings
  )
where

import Data.Char (isLower)
import Data.List qualified as List
import Data.Map.Strict qualified as Map
import Data.Maybe (listToMaybe)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import System.FilePath qualified as FilePath

import JitML.Lint.HaskellTokens (Token (..), TokenKind (..), tokenize)
import JitML.Lint.Stack.Types (LintFinding (..))

-- | A function or constructor that declares a bar or a cohort threshold.
data BarShape = BarShape
  { shapeName :: !Text
  , shapeArity :: !Int
  , shapeNumeric :: ![Int]
  -- ^ Zero-based positions of the target and slack arguments.
  , shapeAllowsProjection :: !Bool
  -- ^ Whether a canonical-table projection may stand in for a literal.
  }

-- | The positional constructor of the bar record is a shape too: the record is
-- exported with its constructor, so @ConvergenceBar name goal target slack
-- threshold@ declares a bar without going through the smart constructor.
barShapes :: [BarShape]
barShapes =
  [ BarShape "mkConvergenceBar" 4 [2, 3] True
  , BarShape "regressionRmseBar" 3 [1, 2] True
  , BarShape "ConvergenceBar" 5 [2, 3, 4] True
  , BarShape "ConvergenceThreshold" 2 [0, 1] False
  , BarShape "SlConvergenceThreshold" 2 [0, 1] False
  , BarShape "AlphaZeroArenaThreshold" 2 [0, 1] False
  ]

-- | Assigned names whose value may never be measured-derived, in a record or a
-- binding.
targetFields :: [Text]
targetFields =
  [ "convergenceLiteratureTarget"
  , "convergenceThreshold"
  , "threshold"
  , "literatureTarget"
  , "slLiteratureTarget"
  ]

-- | Fields of a bar or threshold record whose value, when assigned in record
-- syntax, must also be sourced (a literal or a table projection).
barRecordFields :: [Text]
barRecordFields =
  [ "convergenceLiteratureTarget"
  , "convergenceSlack"
  , "convergenceThreshold"
  , "literatureTarget"
  , "slack"
  , "slLiteratureTarget"
  , "slSlack"
  ]

-- | Field selectors of the canonical threshold tables: the only non-literal
-- source a bar target or slack may be read from.
approvedProjections :: [Text]
approvedProjections =
  [ "literatureTarget"
  , "slack"
  , "slLiteratureTarget"
  , "slSlack"
  , "azTargetWinRate"
  , "azSlack"
  ]

-- | Names that make a file worth tokenizing at all.
triggerNames :: [Text]
triggerNames =
  fmap shapeName barShapes <> targetFields <> barRecordFields

-- | The module that defines the smart constructor and the bar record. It cannot
-- know any measurement, and its own definitions are parameter-passing by
-- construction, so only the measured-derived rule applies to it.
convergenceModulePath :: FilePath
convergenceModulePath = "src/JitML/Product/Convergence.hs"

-- | Test-support code builds deliberately self-referential bars as known fakes
-- so the gates can prove they reject them.
testSupportPrefix :: FilePath
testSupportPrefix = "src/JitML/Test/"

data Binding = Binding
  { bindingName :: !Text
  , bindingRhs :: ![Token]
  , bindingInRecord :: !Bool
  , bindingTopLevel :: !Bool
  -- ^ Visible from every item of the file rather than only its own.
  , bindingLine :: !Int
  , bindingColumn :: !Int
  }

data Context = Context
  { contextTainted :: !(Set Text)
  , contextLiteralAliases :: !(Set Text)
  , contextSourcedAliases :: !(Set Text)
  }

data Verdict
  = Sourced
  | Measured
  | Unsourced
  deriving stock (Eq)

barSourceFindings :: FilePath -> Text -> [LintFinding]
barSourceFindings path content
  | testSupportPrefix `List.isPrefixOf` normalized = []
  | not (any (`Text.isInfixOf` content) triggerNames) = []
  | otherwise = concat (zipWith itemFindings items itemBindings)
 where
  normalized = FilePath.normalise path
  requireSourced = normalized /= convergenceModulePath
  tokens = dropDeclarations (tokenize content)
  topColumn = topLevelColumn tokens
  items = splitItems topColumn tokens
  itemBindings = fmap (bindingsOf topColumn) items
  -- Names are scoped by top-level item: a local binding never explains a name
  -- used in another declaration, but a top-level binding is visible everywhere.
  topLevelBindings = concatMap (filter bindingTopLevel) itemBindings
  itemFindings item bindings =
    siteFindings context item <> assignmentFindings context (patternFields item) bindings
   where
    scope =
      [ binding
      | binding <- topLevelBindings <> bindings
      , not (bindingInRecord binding)
      , not ("." `Text.isInfixOf` bindingName binding)
      ]
    tainted = taintedAliases scope
    context =
      Context
        { contextTainted = tainted
        , contextLiteralAliases = sourcedAliases tainted False scope
        , contextSourcedAliases = sourcedAliases tainted True scope
        }
  -- Every numeric position that is present before the application ends is
  -- checked, saturated or not: an application cut short by an operator (the
  -- first argument of a flipped or piped call) still names its target.
  siteFindings context item =
    [ finding
    | (guarded, token, following) <- occurrences item
    , tokenKind token == WordToken
    , Just shape <- [List.find ((== baseName (tokenText token)) . shapeName) barShapes]
    , let (atoms, remaining) = takeAtoms (shapeArity shape) (tokenLineIndent token) following
    , not (startsRecord atoms)
    , not (inBindingHead guarded (lastLine token atoms) remaining)
    , (index, atom) <- zip [0 :: Int ..] atoms
    , index `elem` shapeNumeric shape
    , Just finding <-
        [ verdictFinding
            path
            (maybe (tokenLine token) tokenLine (listToMaybe atom))
            requireSourced
            (verdictOf context (shapeAllowsProjection shape) atom)
        ]
    ]
  assignmentFindings context excused bindings =
    [ finding
    | binding <- bindings
    , let base = baseName (bindingName binding)
    , base `elem` targetFields || (bindingInRecord binding && base `elem` barRecordFields)
    , (bindingLine binding, bindingColumn binding) `Set.notMember` excused
    , Just finding <-
        [ verdictFinding
            path
            (bindingLine binding)
            requireSourced
            (assignmentVerdict context binding base)
        ]
    ]

assignmentVerdict :: Context -> Binding -> Text -> Verdict
assignmentVerdict context binding base
  | any (taintedToken (contextTainted context)) rhs = Measured
  | bindingInRecord binding && base `elem` barRecordFields = verdictOf context True rhs
  | otherwise = Sourced
 where
  rhs = bindingRhs binding

verdictFinding :: FilePath -> Int -> Bool -> Verdict -> Maybe LintFinding
verdictFinding path line requireSourced verdict =
  case verdict of
    Measured -> Just (measuredBarFinding path line)
    Unsourced
      | requireSourced -> Just (nonLiteralBarFinding path line)
      | otherwise -> Nothing
    Sourced -> Nothing

measuredBarFinding :: FilePath -> Int -> LintFinding
measuredBarFinding path line =
  LintFinding
    path
    "product-truth.measured-bar"
    (measuredBarMessage <> " (line " <> Text.pack (show line) <> ")")
    "use a reviewed external target and project-calibrated slack"

nonLiteralBarFinding :: FilePath -> Int -> LintFinding
nonLiteralBarFinding path line =
  LintFinding
    path
    "product-truth.nonliteral-bar"
    (nonLiteralBarMessage <> " (line " <> Text.pack (show line) <> ")")
    nonLiteralBarRemedy

measuredBarMessage :: Text
measuredBarMessage = "a product convergence threshold is derived from a measured value"

nonLiteralBarMessage :: Text
nonLiteralBarMessage =
  "a convergence bar or cohort threshold is not declared with a literal or canonical-table target and slack"

nonLiteralBarRemedy :: Text
nonLiteralBarRemedy =
  "declare reviewed numeric target and slack constants, or read them from the canonical threshold tables "
    <> "with a selector as the whole argument (to take a threshold apart, use its field selectors "
    <> "rather than a multi-line pattern)"

-- ---------------------------------------------------------------------------
-- Provenance

verdictOf :: Context -> Bool -> [Token] -> Verdict
verdictOf context allowProjection tokens
  | any (taintedToken (contextTainted context)) tokens = Measured
  | literalExpression tokens = Sourced
  | allowProjection && projectionExpression tokens = Sourced
  | aliasReference aliases tokens = Sourced
  | otherwise = Unsourced
 where
  aliases =
    if allowProjection
      then contextSourcedAliases context
      else contextLiteralAliases context

-- | A value name that refers to a measurement: anything called @measured@, or
-- one of the accessors that read a measurement out of an observation.
measuredName :: Text -> Bool
measuredName name =
  "measured" `Text.isInfixOf` lowered
    || lowered `elem` ["cometricvalue", "metricvalue", "observedvalue"]
 where
  lowered = Text.toLower name

taintedToken :: Set Text -> Token -> Bool
taintedToken aliases token =
  tokenKind token == WordToken
    && (measuredName (baseName (tokenText token)) || tokenText token `Set.member` aliases)

-- | Names bound, anywhere in the file, to an expression that mentions a
-- measurement or another such name. The closure runs to a fixed point so a
-- measurement hidden behind several bindings is still seen.
taintedAliases :: [Binding] -> Set Text
taintedAliases bindings = close Set.empty
 where
  close known =
    let next =
          Set.union
            known
            ( Set.fromList
                [ bindingName binding
                | binding <- bindings
                , any (taintedToken known) (bindingRhs binding)
                ]
            )
     in if Set.size next == Set.size known then known else close next

-- | Names all of whose bindings are literals, table projections (when allowed),
-- or references to other such names.
sourcedAliases :: Set Text -> Bool -> [Binding] -> Set Text
sourcedAliases tainted allowProjection bindings = grow Set.empty
 where
  byName = Map.fromListWith (<>) [(bindingName binding, [bindingRhs binding]) | binding <- bindings]
  grow known =
    let next = Map.keysSet (Map.filter (all (sourced known)) byName)
     in if next == known then known else grow next
  sourced known rhs =
    not (any (taintedToken tainted) rhs)
      && ( literalExpression rhs
             || (allowProjection && projectionExpression rhs)
             || aliasReference known rhs
         )

-- | Numbers and the arithmetic between them, parenthesised or not, such as
-- @0.05@, @(-110.0)@, or @(0.9 - 0.05)@.
literalExpression :: [Token] -> Bool
literalExpression tokens =
  any ((== NumberToken) . tokenKind) tokens && all literalToken tokens
 where
  literalToken token =
    case tokenKind token of
      NumberToken -> True
      OpenToken -> tokenText token == "("
      CloseToken -> tokenText token == ")"
      SymbolToken -> tokenText token `elem` ["-", "+", "*", "/"]
      WordToken -> False
      LiteralToken -> False

-- | An application whose head is a canonical-table field selector and that is
-- the whole expression: the selector applied to plain arguments (words,
-- literals, bracketed groups) and nothing else. The selector must be applied to
-- something, since a bare variable that happens to be called @slack@ is a name
-- with no provenance, not a projection. Anything that follows the arguments at
-- the top level (an operator, including @$@) means the selector is no longer the
-- outermost operation, so @literatureTarget t + finalize obs@ is a helper's
-- value with a table value added to it, not a table value.
projectionExpression :: [Token] -> Bool
projectionExpression tokens =
  case unparenthesised tokens of
    token : arguments@(_ : _) ->
      tokenKind token == WordToken
        && baseName (tokenText token) `elem` approvedProjections
        && applicationOnly arguments
    _ -> False
 where
  applicationOnly [] = True
  applicationOnly remaining@(token : rest)
    | tokenKind token == OpenToken = applicationOnly (snd (balancedGroup remaining))
    | isAtom token = applicationOnly rest
    | otherwise = False

-- | The expression inside any parentheses that enclose all of it.
unparenthesised :: [Token] -> [Token]
unparenthesised tokens =
  case tokens of
    open : _
      | isOpenParen open
      , (_ : body, []) <- balancedGroup tokens
      , Just (inner, closing) <- List.unsnoc body
      , isCloseParen closing ->
          unparenthesised inner
    _ -> tokens
 where
  isCloseParen token = tokenKind token == CloseToken && tokenText token == ")"

aliasReference :: Set Text -> [Token] -> Bool
aliasReference aliases tokens =
  case filter (not . isParen) tokens of
    [token] -> tokenKind token == WordToken && tokenText token `Set.member` aliases
    _ -> False

-- ---------------------------------------------------------------------------
-- Structure

-- | The unqualified part of a possibly qualified name.
baseName :: Text -> Text
baseName = snd . Text.breakOnEnd "."

isParen :: Token -> Bool
isParen token =
  case tokenKind token of
    OpenToken -> tokenText token == "("
    CloseToken -> tokenText token == ")"
    WordToken -> False
    NumberToken -> False
    LiteralToken -> False
    SymbolToken -> False

isOpenParen :: Token -> Bool
isOpenParen token = tokenKind token == OpenToken && tokenText token == "("

isSymbolText :: Text -> Token -> Bool
isSymbolText text token = tokenKind token == SymbolToken && tokenText token == text

isWordText :: Text -> Token -> Bool
isWordText text token = tokenKind token == WordToken && tokenText token == text

-- | Every token with whether a guard or comprehension bar precedes it on its own
-- line, and the tokens after it.
occurrences :: [Token] -> [(Bool, Token, [Token])]
occurrences tokens = go (barsBefore tokens) tokens
 where
  go (guarded : guards) (token : rest) = (guarded, token, rest) : go guards rest
  go _ _ = []

-- | For each token, whether a @|@ occurs earlier on its physical line.
barsBefore :: [Token] -> [Bool]
barsBefore = go False
 where
  go _ [] = []
  go seen (token : rest) =
    let here = not (tokenFirstOnLine token) && seen
     in here : go (here || isSymbolText "|" token) rest

reservedWords :: [Text]
reservedWords =
  [ "case"
  , "class"
  , "data"
  , "default"
  , "deriving"
  , "do"
  , "else"
  , "foreign"
  , "if"
  , "import"
  , "in"
  , "infix"
  , "infixl"
  , "infixr"
  , "instance"
  , "let"
  , "module"
  , "newtype"
  , "of"
  , "then"
  , "type"
  , "where"
  , "_"
  ]

declarationKeywords :: [Text]
declarationKeywords =
  ["module", "import", "data", "newtype", "type", "deriving", "foreign"]

-- | Remove every declaration whose text only mentions a constructor as a type or
-- an export: the module header, imports, @data@/@newtype@/@type@ declarations,
-- and type signatures. A declaration extends to the next line that starts at or
-- before its own column.
dropDeclarations :: [Token] -> [Token]
dropDeclarations [] = []
dropDeclarations (token : rest)
  | tokenFirstOnLine token && startsDeclaration token rest =
      dropDeclarations (dropWhile (not . closesItem) rest)
  | otherwise = token : dropDeclarations rest
 where
  closesItem next = tokenFirstOnLine next && tokenColumn next <= tokenColumn token

startsDeclaration :: Token -> [Token] -> Bool
startsDeclaration token rest =
  (tokenKind token == WordToken && tokenText token `elem` declarationKeywords)
    || signatureHead token rest

-- | @name ::@ or @name1, name2 ::@ at the start of a line.
signatureHead :: Token -> [Token] -> Bool
signatureHead token rest =
  isBinderName token
    && case rest of
      next : _ | isSymbolText "::" next -> True
      comma : name : more | isSymbolText "," comma -> signatureHead name more
      _ -> False

-- | A lowercase, unqualified, non-reserved word: a value name.
isBinderName :: Token -> Bool
isBinderName token =
  tokenKind token == WordToken
    && tokenText token `notElem` reservedWords
    && not ("." `Text.isInfixOf` tokenText token)
    && maybe False (\(first, _) -> isLower first || first == '_') (Text.uncons (tokenText token))

-- | The column at which top-level declarations start: the leftmost column of
-- any line.
topLevelColumn :: [Token] -> Int
topLevelColumn tokens =
  case [tokenColumn token | token <- tokens, tokenFirstOnLine token] of
    column : columns -> List.foldl' min column columns
    [] -> 1

-- | The top-level items of a file: each starts at a token that opens a line at
-- the top-level column.
splitItems :: Int -> [Token] -> [[Token]]
splitItems topColumn = go
 where
  go [] = []
  go (token : rest) =
    let (body, next) = break startsItem rest
     in (token : body) : go next
  startsItem token = tokenFirstOnLine token && tokenColumn token == topColumn

-- | Every @name = rhs@, @name args = rhs@, @name <- rhs@, and record field
-- assignment @{ field = rhs@ / @, field = rhs@. The parameters and the @=@ or
-- @<-@ must share the binder's line: a word that opens a continuation line, such
-- as the last argument of a multi-line application, is not a binder.
bindingsOf :: Int -> [Token] -> [Binding]
bindingsOf topColumn = go Nothing
 where
  go _ [] = []
  go previous (token : rest) =
    case binderRhs previous token rest of
      Just (inRecord, afterEquals) ->
        Binding
          { bindingName = tokenText token
          , bindingRhs = expressionExtent (tokenColumn token) afterEquals
          , bindingInRecord = inRecord
          , bindingTopLevel = topLevel previous token
          , bindingLine = tokenLine token
          , bindingColumn = tokenColumn token
          }
          : go (Just token) rest
      Nothing -> go (Just token) rest
  -- A top-level binding, or one introduced by a @let@ that itself opens a
  -- top-level line (which only appears in snippets, but is scoped as written).
  topLevel previous token =
    (tokenFirstOnLine token && tokenColumn token == topColumn)
      || maybe
        False
        (\before -> isWordText "let" before && tokenFirstOnLine before && tokenColumn before == topColumn)
        previous

binderRhs :: Maybe Token -> Token -> [Token] -> Maybe (Bool, [Token])
binderRhs previous token rest
  | tokenKind token /= WordToken = Nothing
  | tokenText token `elem` reservedWords = Nothing
  | inRecord = recordField
  | isBinderName token && binderPosition = functionBinding
  | otherwise = Nothing
 where
  inRecord = maybe False opensField previous
  opensField before =
    (tokenKind before == OpenToken && tokenText before == "{") || isSymbolText "," before
  binderPosition =
    tokenFirstOnLine token
      || maybe
        False
        (\before -> isWordText "let" before || isWordText "where" before || isSymbolText ";" before)
        previous
  sameLine other = tokenLine other == tokenLine token
  recordField =
    case rest of
      next : afterEquals | sameLine next && isSymbolText "=" next -> Just (True, afterEquals)
      _ -> Nothing
  functionBinding = (,) False <$> bindingHead token rest

-- | The tokens after the @=@ or @<-@ of @name params =@ or @name params <-@,
-- when the parameters and the arrow share the name's line.
bindingHead :: Token -> [Token] -> Maybe [Token]
bindingHead token rest =
  case span isParameter rest of
    (_, next : afterEquals)
      | sameLine next && (isSymbolText "=" next || isSymbolText "<-" next) -> Just afterEquals
    _ -> Nothing
 where
  sameLine other = tokenLine other == tokenLine token
  isParameter parameter =
    sameLine parameter && (isBinderName parameter || isWordText "_" parameter)

-- | Whether the line that this token opens carries an @=@, @<-@, @->@, or @::@
-- of its own outside every bracket: it starts a binding, a bind statement, a
-- case alternative, or a signature, not a continuation of the application above
-- it. An application must not run on into such a line: in a @let@ or @where@
-- block whose first binding shares the keyword's line, its siblings start
-- further right than that line and would otherwise read as arguments.
startsBinding :: Token -> [Token] -> Bool
startsBinding token rest =
  tokenFirstOnLine token
    && go (nextDepth 0 token) (takeWhile ((== tokenLine token) . tokenLine) rest)
 where
  go depth tokens =
    case tokens of
      [] -> False
      next : more
        | depth == 0 && any (`isSymbolText` next) ["=", "<-", "->", "::"] -> True
        | otherwise -> go (nextDepth depth next) more

-- | The tokens of an expression that starts at the head of the list and ends at
-- the first layout or separator boundary: a line that starts at or before the
-- binding's own column, an unmatched closing bracket, or a separator or @in@
-- outside every bracket.
expressionExtent :: Int -> [Token] -> [Token]
expressionExtent = expressionExtentUntil (\_ _ -> False)

-- | 'expressionExtent' with a further terminator, tried outside every bracket
-- on each token and the tokens after it.
expressionExtentUntil :: (Token -> [Token] -> Bool) -> Int -> [Token] -> [Token]
expressionExtentUntil terminator bindingColumn = go (0 :: Int)
 where
  go _ [] = []
  go depth (token : rest)
    | tokenFirstOnLine token && tokenColumn token <= bindingColumn = []
    | depth == 0 && (endsExpression token || terminator token rest) = []
    | otherwise = token : go (nextDepth depth token) rest
  endsExpression token =
    tokenKind token == CloseToken
      || isSymbolText "," token
      || isSymbolText ";" token
      || isWordText "in" token

-- | The bracket depth after a token.
nextDepth :: Int -> Token -> Int
nextDepth depth token =
  case tokenKind token of
    OpenToken -> depth + 1
    CloseToken -> depth - 1
    WordToken -> depth
    NumberToken -> depth
    LiteralToken -> depth
    SymbolToken -> depth

-- | Up to @count@ juxtaposed arguments after a constructor, and what follows
-- them. An argument is a word, a wildcard, a literal, or a balanced bracket
-- group. The list ends at an operator, a keyword, a closing bracket, or a line
-- that starts at or before the constructor's own line indent or that starts a
-- binding of its own. A @$@ hands the rest of the expression over as the last
-- argument, so @f a b $ c d@ is read as @f a b (c d)@, up to a further @$@.
takeAtoms :: Int -> Int -> [Token] -> ([[Token]], [Token])
takeAtoms count indent remaining
  | count <= 0 = ([], remaining)
  | otherwise =
      case remaining of
        token : rest
          | not (continues token rest) -> ([], remaining)
          | tokenKind token == OpenToken ->
              let (group, after) = balancedGroup remaining
                  (atoms, final) = takeAtoms (count - 1) indent after
               in (group : atoms, final)
          | isSymbolText "$" token ->
              let argument = expressionExtentUntil endsArgument indent rest
               in if null argument
                    then ([], remaining)
                    else ([argument], drop (length argument) rest)
          | isAtom token ->
              let (atoms, final) = takeAtoms (count - 1) indent rest
               in ([token] : atoms, final)
        _ -> ([], remaining)
 where
  continues token rest =
    not (tokenFirstOnLine token && (tokenColumn token <= indent || startsBinding token rest))
  -- The argument ends where the expression around it does. It also ends at a
  -- further @$@: a chain of applications is read one link at a time, each site
  -- being checked as its own.
  endsArgument token rest =
    any (`isWordText` token) ["then", "else", "of", "where"]
      || isSymbolText "$" token
      || startsBinding token rest

-- | A juxtaposed argument that is a single token: a value or constructor name, a
-- wildcard, or a literal.
isAtom :: Token -> Bool
isAtom token =
  case tokenKind token of
    WordToken -> tokenText token `notElem` reservedWords || tokenText token == "_"
    NumberToken -> True
    LiteralToken -> True
    OpenToken -> False
    CloseToken -> False
    SymbolToken -> False

balancedGroup :: [Token] -> ([Token], [Token])
balancedGroup = go (0 :: Int) []
 where
  go _ acc [] = (reverse acc, [])
  go depth acc (token : rest) =
    case tokenKind token of
      OpenToken -> go (depth + 1) (token : acc) rest
      CloseToken
        | depth <= 1 -> (reverse (token : acc), rest)
        | otherwise -> go (depth - 1) (token : acc) rest
      WordToken -> go depth (token : acc) rest
      NumberToken -> go depth (token : acc) rest
      LiteralToken -> go depth (token : acc) rest
      SymbolToken -> go depth (token : acc) rest

-- | A constructor used with record syntax carries its fields as assignments,
-- which are checked as such.
startsRecord :: [[Token]] -> Bool
startsRecord atoms =
  case atoms of
    (token : _) : _ -> tokenKind token == OpenToken && tokenText token == "{"
    _ -> False

-- | The line on which an occurrence and its arguments end.
lastLine :: Token -> [[Token]] -> Int
lastLine token atoms = foldr (max . tokenLine) (tokenLine token) (concat atoms)

-- | Whether an occurrence stands in a definition head, a pattern, a case
-- alternative, a lambda, or a bind statement rather than in an expression. On
-- the line where it ends, only pattern-shaped tokens (names, wildcards,
-- literals, bracketed groups, and the separators of a tuple, list, or record)
-- may lead to an @=@, @->@, or @<-@. The arguments of @mkConvergenceBar metricName
-- goal target slack =@ and of @f (ConvergenceThreshold target slack) =@ are then
-- variables that a definition binds, not values that a bar is declared with.
--
-- The proof must sit on that line. The next line may hold the arrow of an
-- unrelated alternative or binding or, after a guard's @=@, a sibling guard, and
-- a head whose arrow is elsewhere is read as an application. After a guard bar
-- on the same line an @=@ or @->@ closes a condition, not a head, so only @<-@
-- (a pattern guard or a comprehension generator) proves it there.
inBindingHead :: Bool -> Int -> [Token] -> Bool
inBindingHead guarded endLine =
  go . take headLimit . takeWhile ((== endLine) . tokenLine)
 where
  proves token
    | guarded = isSymbolText "<-" token
    | otherwise = any (`isSymbolText` token) ["=", "->", "<-"]
  go tokens =
    case tokens of
      [] -> False
      token : rest
        | proves token -> True
        | tokenKind token == OpenToken -> go (snd (balancedGroup tokens))
        | tokenKind token == CloseToken -> go rest
        -- The siblings of a tuple, list, or record element are skipped up to the
        -- bracket that closes it, so a field's own @=@ is never taken for a head.
        | isSymbolText "," token -> go (untilEnclosingClose rest)
        | any (`isSymbolText` token) [":", "@", "!", "~"] -> go rest
        | isAtom token -> go rest
        | otherwise -> False
  untilEnclosingClose tokens =
    case tokens of
      [] -> []
      token : rest
        | tokenKind token == CloseToken -> tokens
        | tokenKind token == OpenToken -> untilEnclosingClose (snd (balancedGroup tokens))
        | otherwise -> untilEnclosingClose rest

-- | How many tokens of a line 'inBindingHead' reads. A head is short, and the
-- bound keeps the scan of a pathological line linear.
headLimit :: Int
headLimit = 256

-- | Coordinates of every token inside a record brace group that stands in a
-- pattern. Its @field = variable@ pairs bind variables and declare nothing.
patternFields :: [Token] -> Set (Int, Int)
patternFields item =
  Set.fromList
    [ (tokenLine inner, tokenColumn inner)
    | (guarded, brace, rest) <- occurrences item
    , tokenKind brace == OpenToken
    , tokenText brace == "{"
    , let (group, after) = balancedGroup (brace : rest)
    , inBindingHead guarded (foldr (max . tokenLine) (tokenLine brace) group) after
    , inner <- group
    ]
