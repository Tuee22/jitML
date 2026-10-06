{-# LANGUAGE OverloadedStrings #-}

-- | Phase 278 unit controls for the ProductTruth bar scanner.
--
-- The scanner reads a declaration as a token stream, so these controls vary the
-- /layout/ of a violation (a field split over lines, an argument on its own
-- line, a value bound in a @let@ or @where@ block, a helper around the target,
-- an operator before the last argument) and pair every rejected shape with a
-- benign twin in the same layout that must stay quiet. Patterns get the same
-- treatment: constructor and record patterns are excused, and every expression
-- that merely resembles one stays rejected. The last group runs the gate
-- itself: over a temporary repository tree (so the file walk, the relative
-- paths, and the import walk are exercised by findings rather than by their
-- absence) and over the repository, whose own file set must produce nothing
-- while the real registry and table sources are analysed (rather than skipped)
-- by mutating them.
module ProductTruthScanner (productTruthScannerTests) where

import Data.Foldable (for_)
import Data.List (sort)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath (takeDirectory, takeExtension, (</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit
  ( Assertion
  , assertBool
  , assertFailure
  , testCase
  , (@?=)
  )

import JitML.Lint.HaskellTokens (Token (..), TokenKind (..), tokenize)
import JitML.Lint.ProductTruth qualified as ProductTruth
import JitML.Lint.Stack.Types (LintFinding (..))

productTruthScannerTests :: TestTree
productTruthScannerTests =
  testGroup
    "ProductTruth bar scanner (Phase 278)"
    [ tokenizerTests
    , layoutShapeTests
    , applicationTests
    , projectionTests
    , positionalBarTests
    , cohortConstructorTests
    , patternTests
    , scopeAndDeclarationTests
    , exemptionTests
    , repositoryTests
    ]

-- ---------------------------------------------------------------------------
-- Helpers

measured :: Text
measured = "product-truth.measured-bar"

nonLiteral :: Text
nonLiteral = "product-truth.nonliteral-bar"

-- | The finding keys the scanner reports for a source file, in order.
keys :: FilePath -> [Text] -> [Text]
keys path sourceLines =
  fmap findingKey (ProductTruth.scanProductTruthSourceText path (Text.unlines sourceLines))

productPath :: FilePath
productPath = "src/JitML/Product/Example.hs"

rlTablePath :: FilePath
rlTablePath = "src/JitML/RL/ConvergenceThresholds.hs"

-- | Exactly the given findings, so a benign twin and its violation cannot both
-- pass by reporting something unrelated.
expect :: [Text] -> FilePath -> [Text] -> Assertion
expect expected path sourceLines = keys path sourceLines @?= expected

-- ---------------------------------------------------------------------------
-- Tokenizer

kinds :: Text -> [(TokenKind, Text)]
kinds source = [(tokenKind token, tokenText token) | token <- tokenize source]

tokenizerTests :: TestTree
tokenizerTests =
  testGroup
    "tokenizer"
    [ testCase "line, block, nested block, pragma, and haddock comments are dropped" $
        kinds
          ( Text.unlines
              [ "{-# LANGUAGE OverloadedStrings #-}"
              , "-- a comment mentioning mkConvergenceBar"
              , "-- | haddock"
              , "x = 1 {- inline {- nested -} still comment -} + 2"
              , "{- block"
              , "   spanning lines -}"
              , "y = 3"
              ]
          )
          @?= [ (WordToken, "x")
              , (SymbolToken, "=")
              , (NumberToken, "1")
              , (SymbolToken, "+")
              , (NumberToken, "2")
              , (WordToken, "y")
              , (SymbolToken, "=")
              , (NumberToken, "3")
              ]
    , testCase "dashes that continue into an operator are not a comment" $
        kinds "a --> b --| c -- d"
          @?= [ (WordToken, "a")
              , (SymbolToken, "-->")
              , (WordToken, "b")
              , (SymbolToken, "--|")
              , (WordToken, "c")
              ]
    , testCase "string and character literals are single tokens and hide their contents" $
        kinds "s = \"mkConvergenceBar -- {- \\\" x\" ; c = 'x' ; e = '\\n' ; q = '\\''"
          @?= [ (WordToken, "s")
              , (SymbolToken, "=")
              , (LiteralToken, "\"mkConvergenceBar -- {- \\\" x\"")
              , (SymbolToken, ";")
              , (WordToken, "c")
              , (SymbolToken, "=")
              , (LiteralToken, "'x'")
              , (SymbolToken, ";")
              , (WordToken, "e")
              , (SymbolToken, "=")
              , (LiteralToken, "'\\n'")
              , (SymbolToken, ";")
              , (WordToken, "q")
              , (SymbolToken, "=")
              , (LiteralToken, "'\\''")
              ]
    , testCase "a tick that does not close is dropped, and primes stay in identifiers" $
        kinds "f :: Row 'Declared ; rowClass' = x'"
          @?= [ (WordToken, "f")
              , (SymbolToken, "::")
              , (WordToken, "Row")
              , (WordToken, "Declared")
              , (SymbolToken, ";")
              , (WordToken, "rowClass'")
              , (SymbolToken, "=")
              , (WordToken, "x'")
              ]
    , testCase "numeric literals keep fractions, exponents, radix forms, and underscores whole" $
        kinds "475.0 4.75e2 1.0e-12 2E+3 0x1F 0b101 1_000 7"
          @?= [ (NumberToken, "475.0")
              , (NumberToken, "4.75e2")
              , (NumberToken, "1.0e-12")
              , (NumberToken, "2E+3")
              , (NumberToken, "0x1F")
              , (NumberToken, "0b101")
              , (NumberToken, "1_000")
              , (NumberToken, "7")
              ]
    , testCase "an enumeration keeps its dots and a negative literal keeps its sign apart" $ do
        kinds "[1..5]"
          @?= [ (OpenToken, "[")
              , (NumberToken, "1")
              , (SymbolToken, "..")
              , (NumberToken, "5")
              , (CloseToken, "]")
              ]
        kinds "(-110.0)"
          @?= [(OpenToken, "("), (SymbolToken, "-"), (NumberToken, "110.0"), (CloseToken, ")")]
    , testCase "qualified names are one token and composition with spaces is not qualification" $ do
        kinds "Data.Text.pack RLConvergence.ConvergenceThreshold f . g"
          @?= [ (WordToken, "Data.Text.pack")
              , (WordToken, "RLConvergence.ConvergenceThreshold")
              , (WordToken, "f")
              , (SymbolToken, ".")
              , (WordToken, "g")
              ]
    , testCase "tokens record their line, column, and whether they open a line" $
        [ (tokenText token, tokenLine token, tokenColumn token, tokenFirstOnLine token, tokenLineIndent token)
        | token <- tokenize "bar =\n  f x\n    y"
        ]
          @?= [ ("bar", 1, 1, True, 1)
              , ("=", 1, 5, False, 1)
              , ("f", 2, 3, True, 3)
              , ("x", 2, 5, False, 3)
              , ("y", 3, 5, True, 5)
              ]
    , testCase "an unterminated string ends at its line and an unterminated comment at the end of input" $ do
        kinds "a = \"unterminated\nb = 1"
          @?= [ (WordToken, "a")
              , (SymbolToken, "=")
              , (LiteralToken, "\"unterminated")
              , (WordToken, "b")
              , (SymbolToken, "=")
              , (NumberToken, "1")
              ]
        kinds "a {- never closed\nb" @?= [(WordToken, "a")]
    ]

-- ---------------------------------------------------------------------------
-- The four shapes a line-based scan could not see

layoutShapeTests :: TestTree
layoutShapeTests =
  testGroup
    "layout shapes"
    [ testGroup
        "a record target split over lines"
        [ testCase "measured value on the continuation line is rejected" $
            expect [measured] productPath (splitField "coMetricValue x")
        , testCase "the same layout with a literal is accepted" $
            expect [] productPath (splitField "0.9")
        , testCase "an aliased measurement on the continuation line is rejected" $
            expect
              [measured]
              productPath
              ( [ "observedTarget = coMetricValue observation"
                , ""
                ]
                  <> splitField "observedTarget"
              )
        , testCase "a bar record slack that is not sourced is rejected in the same layout" $
            expect
              [nonLiteral]
              productPath
              [ "bar ="
              , "  ConvergenceBar"
              , "    { convergenceLiteratureTarget = 0.9"
              , "    , convergenceSlack ="
              , "        slackFor obs"
              , "    }"
              ]
        ]
    , testGroup
        "a helper around the target"
        [ testCase "an unknown helper is rejected: its provenance is invisible" $
            expect
              [nonLiteral]
              productPath
              ["bar = mkConvergenceBar name MetricMaximise (finalize obs) 0.05"]
        , testCase "a helper around a measurement is rejected as measured" $
            expect
              [measured]
              productPath
              ["bar = mkConvergenceBar name MetricMaximise (finalize (coMetricValue obs)) 0.05"]
        , testCase "a non-literal slack is rejected too" $
            expect
              [nonLiteral]
              productPath
              ["bar = mkConvergenceBar name MetricMaximise 0.9 (slackFor obs)"]
        , testCase "a canonical-table projection is accepted, in one line or split" $ do
            expect
              []
              productPath
              [ "bar = mkConvergenceBar name MetricMaximise"
              , "  (RLConvergence.literatureTarget (RLConvergence.fbrThreshold row))"
              , "  (RLConvergence.slack (RLConvergence.fbrThreshold row))"
              ]
            expect
              []
              productPath
              [ "bar = mkConvergenceBar name MetricMaximise (slLiteratureTarget t) (slSlack t)"
              ]
        , testCase "a bare variable named like a table selector is not a projection" $ do
            expect
              [nonLiteral]
              productPath
              ["bar = mkConvergenceBar name MetricMaximise 0.9 slack"]
            expect
              [nonLiteral]
              productPath
              ["bar = mkConvergenceBar name MetricMaximise (literatureTarget) 0.05"]
        , testCase "literals, including negative and exponent forms, are accepted" $
            expect
              []
              productPath
              [ "a = mkConvergenceBar name MetricMaximise 0.90 0.05"
              , "b = regressionRmseBar \"rmse\" 0.90 0.10"
              , "c = mkConvergenceBar name MetricMinimise (-110.0) 4.5e1"
              , "d = mkConvergenceBar name MetricMaximise (0.9 - 0.05) 1.0e-2"
              ]
        , testCase "a regression bar with an unsourced target is rejected" $
            expect [nonLiteral] productPath ["bar = regressionRmseBar \"rmse\" (target obs) 0.10"]
        ]
    , testGroup
        "a renamed measured value"
        [ testCase "a let-bound alias of a measurement is rejected" $
            expect
              [measured]
              productPath
              [ "let result = coMetricValue observation"
              , "    bar = mkConvergenceBar name MetricMaximise result 0.05"
              ]
        , testCase "an alias whose right-hand side is on the next line is rejected" $
            expect
              [measured]
              productPath
              [ "result ="
              , "  coMetricValue observation"
              , "bar = mkConvergenceBar name MetricMaximise result 0.05"
              ]
        , testCase "a where-bound alias declared after its use is rejected" $
            expect
              [measured]
              productPath
              [ "bar = mkConvergenceBar name MetricMaximise result 0.05"
              , "  where"
              , "    result ="
              , "      coMetricValue observation"
              ]
        , testCase "an alias through several bindings is rejected" $
            expect
              [measured]
              productPath
              [ "bar = go observation"
              , "  where"
              , "    go obs = mkConvergenceBar name MetricMaximise third 0.05"
              , "    first = coMetricValue observation"
              , "    second ="
              , "      first"
              , "    third = second"
              ]
        , testCase "a helper defined from a measurement taints its call" $
            expect
              [measured]
              productPath
              [ "observedTarget obs = coMetricValue obs"
              , "bar = mkConvergenceBar name MetricMaximise (observedTarget observation) 0.05"
              ]
        , testCase "a name with no visible binding is rejected: it has no provenance" $
            expect
              [nonLiteral]
              productPath
              ["bar = mkConvergenceBar name MetricMaximise result 0.05"]
        , testCase "an alias of a literal is accepted" $
            expect
              []
              productPath
              [ "let result = 0.9"
              , "    bar = mkConvergenceBar name MetricMaximise result 0.05"
              ]
        , testCase "an alias of a canonical-table projection is accepted for a bar" $
            expect
              []
              productPath
              [ "bar = mkConvergenceBar name MetricMaximise target slack"
              , "  where"
              , "    target = RLConvergence.literatureTarget threshold"
              , "    slack = RLConvergence.slack threshold"
              ]
        , testCase "a name bound by a monadic bind from a measurement is rejected" $
            expect
              [measured]
              productPath
              [ "build = do"
              , "  result <- pure (coMetricValue observation)"
              , "  pure (mkConvergenceBar name MetricMaximise result 0.05)"
              ]
        ]
    ]

-- | A bar record whose literature target is @value@, written over several lines.
splitField :: Text -> [Text]
splitField value =
  [ "bar ="
  , "  ConvergenceBar"
  , "    { convergenceLiteratureTarget ="
  , "        " <> value
  , "    , convergenceSlack = 0.05"
  , "    }"
  ]

-- ---------------------------------------------------------------------------
-- Applications an operator cuts short

-- | An operator can end an application before its last argument, or leave it
-- short of its last argument altogether. Every numeric position that is present
-- must still be checked, and what follows a @$@ is the last argument.
applicationTests :: TestTree
applicationTests =
  testGroup
    "applications and operators"
    [ testGroup
        "a dollar before the last argument"
        [ testCase "a measured target is found, on one line or split" $ do
            expect [measured] productPath ["bar = mkConvergenceBar name MetricMaximise measuredValue $ 0.05"]
            expect
              [measured]
              productPath
              [ "bar ="
              , "  mkConvergenceBar"
              , "    name"
              , "    MetricMaximise"
              , "    measuredValue"
              , "    $ 0.05"
              ]
        , testCase "the same layouts with a literal target are accepted" $ do
            expect [] productPath ["bar = mkConvergenceBar name MetricMaximise 0.9 $ 0.05"]
            expect
              []
              productPath
              [ "bar ="
              , "  mkConvergenceBar"
              , "    name"
              , "    MetricMaximise"
              , "    0.9"
              , "    $ 0.05"
              ]
        , testCase "a helper target is rejected as unsourced" $
            expect
              [nonLiteral]
              productPath
              ["bar = mkConvergenceBar name MetricMaximise (finalize obs) $ 0.05"]
        , testCase "what follows the dollar is checked as the last argument" $ do
            expect [nonLiteral] productPath ["bar = mkConvergenceBar name MetricMaximise 0.9 $ slackFor obs"]
            expect [measured] productPath ["bar = mkConvergenceBar name MetricMaximise 0.9 $ coMetricValue obs"]
            expect [nonLiteral] productPath ["bar = regressionRmseBar \"rmse\" 0.9 $ slackFor obs"]
            expect
              [nonLiteral]
              productPath
              [ "bar ="
              , "  mkConvergenceBar"
              , "    name"
              , "    MetricMaximise"
              , "    0.9"
              , "    $ slackFor obs"
              ]
            expect [] productPath ["bar = mkConvergenceBar name MetricMaximise 0.9 $ (0.1 - 0.05)"]
        , testCase "a measured target and an unsourced slack are both reported, in order" $
            expect
              [measured, nonLiteral]
              productPath
              ["bar = mkConvergenceBar name MetricMaximise measuredValue $ slackFor obs"]
        , testCase "the last argument ends where the surrounding expression does" $ do
            -- What follows belongs to something else: a measured fallback in the
            -- other branch, a sibling tuple element, an enclosing call.
            expect
              []
              productPath
              ["bar = if cond then mkConvergenceBar name MetricMaximise 0.9 $ 0.05 else measuredFallback"]
            expect
              []
              productPath
              ["pair = (mkConvergenceBar name MetricMaximise 0.9 $ 0.05, measuredValue)"]
            expect
              []
              productPath
              ["wrapped = wrap (mkConvergenceBar name MetricMaximise 0.9 $ 0.05) measuredValue"]
        , testCase "a chain of dollars is read one link at a time and stays rejected" $
            expect
              [nonLiteral]
              productPath
              ["bar = mkConvergenceBar name MetricMaximise 0.9 $ pick $ measuredValue"]
        ]
    , testGroup
        "an application that ends before its last argument"
        [ testCase "a flipped application still names its target" $ do
            expect [measured] productPath ["bar = 0.05 & mkConvergenceBar name MetricMaximise measuredValue"]
            expect [nonLiteral] productPath ["bar = 0.05 & mkConvergenceBar name MetricMaximise (finalize obs)"]
            expect
              [measured]
              productPath
              [ "bar ="
              , "  0.05"
              , "    & mkConvergenceBar name MetricMaximise measuredValue"
              ]
            expect [] productPath ["bar = 0.05 & mkConvergenceBar name MetricMaximise 0.9"]
            expect
              []
              productPath
              [ "bar ="
              , "  0.05"
              , "    & mkConvergenceBar name MetricMaximise 0.9"
              ]
        , testCase "a partial application is rejected for an unsourced target and accepted for a literal" $ do
            expect
              [nonLiteral]
              productPath
              ["minimiseFrom target = mkConvergenceBar name MetricMinimise target"]
            expect [] productPath ["minimiseFrom = mkConvergenceBar name MetricMinimise 0.9"]
        , testCase
            "a partial application on the first line of a let or where block does not swallow its sibling"
            $ do
              -- The sibling starts further right than the keyword's line, so it
              -- once read as the missing argument (a helper, hence unsourced).
              expect
                []
                productPath
                [ "build ="
                , "  let minimise = mkConvergenceBar name MetricMinimise"
                , "      other = helper 3"
                , "   in minimise"
                ]
              expect
                []
                productPath
                [ "build = go"
                , "  where minimise = mkConvergenceBar name MetricMinimise"
                , "        other = helper 3"
                ]
        , testCase "the sibling may be a pattern binding, a bind, or a case alternative" $ do
            expect
              []
              productPath
              [ "build ="
              , "  let minimise = mkConvergenceBar name MetricMinimise"
              , "      (a, b) = pair"
              , "   in minimise"
              ]
            expect
              []
              productPath
              [ "pick k = case k of A -> mkConvergenceBar name MetricMinimise"
              , "                   B -> other"
              ]
        , testCase "an application in such a block is still checked, saturated or not" $ do
            -- A sibling that was swallowed as the next argument made the head
            -- rule excuse the whole application, hiding the target before it.
            expect
              [nonLiteral]
              productPath
              [ "build ="
              , "  let bar = mkConvergenceBar name MetricMinimise hidden 0.05"
              , "      other = 0.5"
              , "   in bar"
              ]
            expect
              [nonLiteral]
              productPath
              [ "build ="
              , "  let minimise = mkConvergenceBar name MetricMinimise hidden"
              , "      other = 0.5"
              , "   in minimise"
              ]
            expect
              [nonLiteral]
              productPath
              [ "build ="
              , "  let minimise = mkConvergenceBar name MetricMinimise hidden"
              , "      Just other = lookup key table"
              , "   in minimise"
              ]
        , testCase "whatever the sibling is (an alternative, a bind, an operator signature)" $ do
            -- Each sibling opens a line that carries its own -> , <- , or ::
            -- outside brackets, so it ends the application before it.
            expect
              [nonLiteral]
              productPath
              [ "pick k = case k of A -> mkConvergenceBar name MetricMinimise hidden"
              , "                   B -> other"
              ]
            expect
              [nonLiteral]
              productPath
              [ "build = do minimise <- pure $ mkConvergenceBar name MetricMinimise hidden"
              , "           other <- helper 3"
              ]
            expect
              [nonLiteral]
              productPath
              [ "build = go"
              , "  where minimise = mkConvergenceBar name MetricMinimise hidden"
              , "        (<+>) :: Combine"
              ]
        , testCase "a continuation line with an = inside brackets is still an argument" $
            expect
              [nonLiteral]
              productPath
              [ "bar ="
              , "  mkConvergenceBar name MetricMaximise"
              , "    (target {a = 1})"
              , "    0.05"
              ]
        ]
    ]

-- ---------------------------------------------------------------------------
-- A projection is the whole argument

projectionTests :: TestTree
projectionTests =
  testGroup
    "a table projection is the whole argument"
    [ testCase "a helper's value added to a projection is rejected, in the target and in the slack" $ do
        for_
          [ "RLConvergence.literatureTarget t + finalize obs"
          , "RLConvergence.literatureTarget t * fudge obs"
          , "RLConvergence.literatureTarget t - gap"
          , "finalize obs + RLConvergence.literatureTarget t"
          ]
          ( \argument ->
              expect
                [nonLiteral]
                productPath
                ["bar = mkConvergenceBar name MetricMaximise (" <> argument <> ") 0.05"]
          )
        for_
          [ "RLConvergence.slack t + helper obs"
          , "slSlack t + adjust"
          ]
          ( \argument ->
              expect
                [nonLiteral]
                productPath
                ["bar = mkConvergenceBar name MetricMaximise (slLiteratureTarget t) (" <> argument <> ")"]
          )
    , testCase "the same holds in record syntax and through a bound alias" $ do
        expect
          [nonLiteral]
          productPath
          ["bar = ConvergenceBar {convergenceLiteratureTarget = slLiteratureTarget t + helper obs}"]
        expect
          [nonLiteral]
          productPath
          [ "bar = mkConvergenceBar name MetricMaximise target 0.05"
          , "  where"
          , "    target = RLConvergence.literatureTarget t + finalize obs"
          ]
        expect
          [nonLiteral]
          productPath
          [ "bar = mkConvergenceBar name MetricMaximise target slack"
          , "  where"
          , "    target = RLConvergence.literatureTarget threshold"
          , "    slack = RLConvergence.slack threshold * 2"
          ]
    , testCase "a selector after a dollar is not the whole argument" $
        expect
          [nonLiteral]
          productPath
          ["bar = mkConvergenceBar name MetricMaximise (RLConvergence.literatureTarget $ pick t) 0.05"]
    , testCase "a selector applied to plain arguments or to a computed row is accepted" $ do
        expect
          []
          productPath
          [ "bar = mkConvergenceBar name MetricMaximise"
          , "  (RLConvergence.literatureTarget table key)"
          , "  (RLConvergence.slack table key)"
          ]
        expect
          []
          productPath
          [ "bar = mkConvergenceBar name MetricMaximise"
          , "  (RLConvergence.literatureTarget (pick a + b))"
          , "  (RLConvergence.slack (pick a + b))"
          ]
        expect
          []
          productPath
          [ "bar = mkConvergenceBar name MetricMaximise ((RLConvergence.literatureTarget t)) (RLConvergence.slack t)"
          ]
    , testCase "aliases of bare projections are accepted" $
        expect
          []
          productPath
          [ "bar = mkConvergenceBar name MetricMaximise target slack"
          , "  where"
          , "    target = RLConvergence.literatureTarget threshold"
          , "    slack = RLConvergence.slack threshold"
          ]
    ]

-- ---------------------------------------------------------------------------
-- The positional bar constructor

-- | The bar record is exported with its constructor, so declaring a bar
-- positionally bypasses the smart constructor and must meet the same rules.
positionalBarTests :: TestTree
positionalBarTests =
  testGroup
    "the positional bar constructor"
    [ testCase "a measured target is rejected, on one line or split" $ do
        expect [measured] productPath ["bar = ConvergenceBar \"m\" MetricMaximise measuredValue 0.05 0.85"]
        expect
          [measured]
          productPath
          ["bar = ConvergenceBar \"m\" MetricMaximise (coMetricValue o) 0.05 0.85"]
        expect
          [measured]
          productPath
          [ "bar ="
          , "  ConvergenceBar"
          , "    \"m\""
          , "    MetricMaximise"
          , "    (coMetricValue o)"
          , "    0.05"
          , "    0.85"
          ]
    , testCase "a measured threshold is rejected too" $
        expect [measured] productPath ["bar = ConvergenceBar \"m\" MetricMaximise 0.9 0.05 measuredValue"]
    , testCase "an unsourced target, slack, or threshold is rejected" $ do
        expect [nonLiteral] productPath ["bar = ConvergenceBar \"m\" MetricMaximise (helper o) 0.05 0.85"]
        expect [nonLiteral] productPath ["bar = ConvergenceBar \"m\" MetricMaximise 0.9 (helper o) 0.85"]
        expect [nonLiteral] productPath ["bar = ConvergenceBar \"m\" MetricMaximise 0.9 0.05 (helper o)"]
    , testCase "literals and table projections are accepted" $ do
        expect [] productPath ["bar = ConvergenceBar \"m\" MetricMaximise 0.9 0.05 0.85"]
        expect
          []
          productPath
          ["bar = ConvergenceBar \"m\" MetricMaximise (slLiteratureTarget t) (slSlack t) 0.85"]
    , testCase "the name and the goal are not numeric positions" $
        expect [] productPath ["bar = ConvergenceBar name goal 0.9 0.05 0.85"]
    ]

cohortConstructorTests :: TestTree
cohortConstructorTests =
  testGroup
    "cohort and threshold constructors"
    [ testCase "a cohort constructor split across lines is checked, not skipped" $ do
        expect
          [nonLiteral]
          rlTablePath
          [ "rows = [ ((\"PPO\", \"cartpole\"), ConvergenceThreshold"
          , "      hidden 0.5) ]"
          ]
        expect
          [nonLiteral]
          rlTablePath
          [ "row ="
          , "  ConvergenceThreshold"
          , "    target"
          , "    0.5"
          ]
    , testCase "the same layouts with literals are accepted" $ do
        expect
          []
          rlTablePath
          [ "rows = [ ((\"PPO\", \"cartpole\"), ConvergenceThreshold"
          , "      475.0 25.0) ]"
          ]
        expect
          []
          rlTablePath
          [ "row ="
          , "  ConvergenceThreshold"
          , "    (-110.0)"
          , "    4.5e1"
          ]
    , testCase "a non-literal argument is rejected in any file, not only the cohort tables" $
        expect [nonLiteral] "src/JitML/RL/Other.hs" ["row = ConvergenceThreshold (helper x) 0.5"]
    , testCase "the SL and AlphaZero threshold constructors are cohort constructors too" $ do
        expect [nonLiteral] productPath ["row = SlConvergenceThreshold hidden 0.07"]
        expect [nonLiteral] productPath ["row = AlphaZeroArenaThreshold 0.45 hidden"]
        expect [] productPath ["row = SlConvergenceThreshold 0.97 0.07"]
        expect [] productPath ["row = AlphaZeroArenaThreshold 0.45 0.05"]
    , testCase "a cohort constructor accepts literals only, not a table projection or its alias" $ do
        expect
          [nonLiteral]
          productPath
          ["row = ConvergenceThreshold (RLConvergence.literatureTarget t) 0.5"]
        expect
          [nonLiteral]
          productPath
          [ "row = ConvergenceThreshold target 0.5"
          , "  where"
          , "    target = RLConvergence.literatureTarget t"
          ]
    , testCase "a measured cohort argument is rejected as measured, split or not" $ do
        expect [measured] productPath ["row = ConvergenceThreshold measuredValue 0.5"]
        expect
          [measured]
          productPath
          [ "row ="
          , "  ConvergenceThreshold"
          , "    (coMetricValue observation)"
          , "    0.5"
          ]
    , testCase "record syntax is checked field by field" $ do
        expect
          []
          productPath
          ["row = ConvergenceThreshold {literatureTarget = 475.0, slack = 25.0}"]
        expect
          [measured]
          productPath
          [ "row ="
          , "  ConvergenceThreshold"
          , "    { literatureTarget ="
          , "        coMetricValue observation"
          , "    , slack = 25.0"
          , "    }"
          ]
        expect
          [nonLiteral]
          productPath
          ["row = ConvergenceThreshold {literatureTarget = 475.0, slack = slackFor obs}"]
    ]

-- ---------------------------------------------------------------------------
-- Patterns

-- | A constructor or record pattern binds variables; it declares no bar. It is
-- recognised by an @=@, @->@, or @<-@ on the line where its arguments end, and
-- nothing that merely resembles one may be excused.
patternTests :: TestTree
patternTests =
  testGroup
    "constructor and record patterns"
    [ testCase "a constructor pattern in a function head binds variables and declares nothing" $ do
        expect [] productPath ["targetOf (ConvergenceThreshold t s) = t"]
        expect [] productPath ["unpack (SlConvergenceThreshold target slack) = (target, slack)"]
        expect [] productPath ["armOf (AlphaZeroArenaThreshold win slack) = win"]
        expect [] productPath ["barTarget (ConvergenceBar n g t s th) = t"]
        expect [] productPath ["first x (RLConvergence.ConvergenceThreshold t _) y = t"]
    , testCase "a pattern nested in a tuple or a cons, or followed by bang, lazy, and as-patterns" $ do
        expect [] productPath ["f (ConvergenceThreshold t s, other) = t"]
        expect [] productPath ["f (other, ConvergenceThreshold t s) = t"]
        expect [] productPath ["f (ConvergenceThreshold t s : rest) = t"]
        expect [] productPath ["f !acc x@(ConvergenceThreshold t s) = t"]
        expect [] productPath ["f (ConvergenceThreshold t s) !acc = t"]
        expect [] productPath ["f (ConvergenceThreshold t s) ~lazy = t"]
        expect [] productPath ["f (ConvergenceThreshold t s) whole@(Just _) = t"]
    , testCase "a guard bar on an earlier line does not turn a later head into a guard line" $
        expect
          []
          productPath
          [ "outer x = go x"
          , "  where"
          , "    go y"
          , "      | y > 1 = 1"
          , "      | otherwise = 2"
          , "    targetOf (ConvergenceThreshold t s) = t"
          ]
    , testCase "a pattern in a case alternative, a lambda, a let, a bind, or a generator" $ do
        expect [] productPath ["f th = case th of ConvergenceThreshold t _ -> t"]
        expect [] productPath ["f th = case th of", "  ConvergenceThreshold t s -> t"]
        expect [] productPath ["g = map (\\(ConvergenceThreshold t s) -> t) xs"]
        expect [] productPath ["k th = let ConvergenceThreshold t s = th in t"]
        expect
          []
          productPath
          [ "m = do"
          , "  ConvergenceThreshold t s <- lookupThreshold key"
          , "  pure t"
          ]
        expect [] productPath ["rows = [t | ConvergenceThreshold t _ <- thresholds]"]
        expect [] productPath ["rows = [f x | ConvergenceThreshold t s <- ts, let x = t]"]
    , testCase "a record pattern binds its fields" $ do
        expect [] productPath ["targetOf ConvergenceBar {convergenceLiteratureTarget = target} = target"]
        expect
          []
          productPath
          ["f th = case th of ConvergenceThreshold {literatureTarget = t, slack = s} -> t"]
        expect [] productPath ["g = \\ConvergenceBar {convergenceThreshold = th} -> th"]
        expect [] productPath ["slackOf Example {slack = s} = s"]
        expect [] productPath ["f Row {rowThreshold = ConvergenceThreshold t s} = t"]
        expect
          []
          productPath
          [ "targetOf"
          , "  ConvergenceBar"
          , "    { convergenceLiteratureTarget = target"
          , "    , convergenceSlack = slack"
          , "    } = target"
          ]
    , testCase "a pattern whose arguments span lines is a head when its arrow is on their last line" $ do
        expect
          []
          productPath
          [ "targetOf (ConvergenceThreshold"
          , "            t s) = t"
          ]
        expect
          []
          productPath
          [ "f th = case th of"
          , "  ConvergenceThreshold"
          , "    t s -> t"
          ]
    , testCase "a pattern guard is a pattern even on a guard line" $
        expect
          []
          productPath
          [ "pick x"
          , "  | Just (ConvergenceThreshold t s) <- lookup x table = t"
          ]
    , testGroup
        "an expression is not excused because something follows it"
        [ testCase "a guarded row, with the target on its own line or beside the guard" $ do
            -- The next line's guard bar once made the constructor look like a
            -- definition head, so the hidden target of the first row was skipped.
            expect
              [nonLiteral]
              productPath
              [ "threshold x"
              , "  | x > 1 ="
              , "      ConvergenceThreshold hidden 0.5"
              , "  | otherwise = ConvergenceThreshold 1.0 0.5"
              ]
            expect
              [nonLiteral]
              productPath
              [ "threshold x"
              , "  | x > 1 = ConvergenceThreshold hidden 0.5"
              , "  | otherwise = ConvergenceThreshold 1.0 0.5"
              ]
        , testCase "the body of a case alternative, before the next alternative" $
            expect
              [nonLiteral]
              productPath
              [ "pick k = case k of"
              , "  A -> ConvergenceThreshold hidden 0.5"
              , "  B -> ConvergenceThreshold 1.0 0.5"
              ]
        , testCase "a record field followed by another field, and a tuple element followed by a lambda" $ do
            expect
              [nonLiteral]
              productPath
              ["row = Row {rowThreshold = ConvergenceThreshold hidden 0.5, rowOther = 1.0}"]
            expect
              [nonLiteral]
              productPath
              ["row = Row {a = ConvergenceBar {slack = hidden}, b = 1}"]
            expect [nonLiteral] productPath ["pair = (ConvergenceThreshold hidden 0.5, \\y -> y)"]
        , testCase "a comprehension element, before its bar" $ do
            expect [nonLiteral] productPath ["rows = [ConvergenceThreshold t 0.5 | t <- ts]"]
            expect [nonLiteral] productPath ["rows = [(ConvergenceThreshold t 0.5) | t <- ts]"]
            expect
              [nonLiteral]
              productPath
              [ "rows ="
              , "  [ ConvergenceThreshold t 0.5"
              , "  | t <- ts"
              , "  ]"
              ]
        , testCase "a value built in a guard condition, whose = or -> ends the condition" $ do
            expect
              [nonLiteral]
              productPath
              [ "pick x"
              , "  | isOk (ConvergenceThreshold hidden 0.5) = 1"
              , "  | otherwise = 2"
              ]
            expect
              [nonLiteral]
              productPath
              [ "pick x = case x of"
              , "  _ | ok (ConvergenceThreshold hidden 0.5) -> 1"
              ]
        , testCase "a value followed by a keyword, a separator, or a multi-way alternative" $ do
            expect [nonLiteral] productPath ["x = ConvergenceThreshold hidden 0.5 where y = 1"]
            expect [nonLiteral] productPath ["x = let a = ConvergenceThreshold hidden 0.5 in a"]
            expect
              [nonLiteral]
              productPath
              ["x = let { a = ConvergenceThreshold hidden 0.5; b = 2 } in a"]
            expect
              [nonLiteral]
              productPath
              ["pick c = if | c -> ConvergenceThreshold hidden 0.5 | otherwise -> other"]
            expect
              [nonLiteral]
              productPath
              ["xs = [ConvergenceThreshold hidden 0.5, ConvergenceThreshold 1.0 0.5]"]
        , testCase "an argument of a call that is followed by more arguments" $ do
            expect [nonLiteral] productPath ["x = foo (ConvergenceThreshold hidden 0.5) bar baz"]
            expect [nonLiteral] productPath ["x = foo (ConvergenceThreshold hidden 0.5) (\\y -> y)"]
        , testCase "a record construction and a record update are declarations" $ do
            expect [nonLiteral] productPath ["bar = ConvergenceBar {convergenceLiteratureTarget = hidden}"]
            expect
              [nonLiteral]
              productPath
              ["n bar = bar {convergenceThreshold = convergenceThreshold bar - 0.1}"]
        ]
    , testCase
        "a head whose arrow is on a later line, or that has a guard bar after it, is read as an application"
        $ do
          -- Documented limit: the proof of a head must sit on the line where the
          -- pattern ends, because a later line may hold an unrelated alternative,
          -- so a guarded head is best written with the threshold's selectors.
          expect
            [nonLiteral, nonLiteral]
            productPath
            [ "targetOf (ConvergenceThreshold t s)"
            , "  | t > 0 = t"
            , "  | otherwise = 0"
            ]
          expect
            [nonLiteral, nonLiteral]
            productPath
            ["targetOf (ConvergenceThreshold t s) | t > 0 = t"]
    ]

-- ---------------------------------------------------------------------------
-- Scope, declarations, and the false positives found on the real tree

scopeAndDeclarationTests :: TestTree
scopeAndDeclarationTests =
  testGroup
    "scope and declarations"
    [ testCase "comments and string literals never count" $
        expect
          []
          productPath
          [ "-- bar = mkConvergenceBar name MetricMaximise measuredValue 0.0"
          , "{- threshold = measuredValue -}"
          , "note = \"mkConvergenceBar name MetricMaximise measuredValue 0.0; threshold = measuredValue\""
          ]
    , testCase "exports, imports, data declarations, signatures, and instance heads are not applications" $
        expect
          []
          productPath
          [ "module JitML.Product.Example (ConvergenceThreshold (..), mkConvergenceBar) where"
          , "import JitML.RL.ConvergenceThresholds (ConvergenceThreshold (..))"
          , "data Row = Row"
          , "  { rowThreshold :: ConvergenceThreshold"
          , "  , rowOther :: Double"
          , "  }"
          , "cohort, other :: Text -> Maybe ConvergenceThreshold"
          , "instance Serialise ConvergenceThreshold where"
          , "  encode = encodeThreshold"
          ]
    , testCase "a definition head and a partial application are not saturated applications" $ do
        expect [] productPath ["mkConvergenceBar metricName goal target slack ="]
        expect [] productPath ["minimiseBar metricName = mkConvergenceBar metricName MetricMinimise"]
    , testCase "a word that opens a continuation line is not a binder of the next statement" $
        -- The last argument of a multi-line application, followed by a monadic
        -- bind, was once read as a binding named like a target field whose
        -- right-hand side was the bind's.
        expect
          []
          productPath
          [ "measureCriterion name goal threshold value = do"
          , "  criterion <-"
          , "    mkMetricCriterion"
          , "      name"
          , "      threshold"
          , "  measurement <- mkFiniteMeasurement value"
          , "  pure (ConvergenceObservation criterion measurement)"
          , "convergencePassed observation ="
          , "  let value = coMetricValue observation"
          , "   in value"
          ]
    , testCase "a target-named argument ending a multi-line application binds nothing" $
        -- 'threshold' is only the last argument of 'limitsFor'; the statement
        -- below it has its own binder. Reading the two as one binding
        -- ('threshold observed <- ...') would make a target field of a
        -- measurement that it never received.
        expect
          []
          productPath
          [ "build obs = do"
          , "  bounds <-"
          , "    limitsFor"
          , "      obs"
          , "      threshold"
          , "  observed <- pure (coMetricValue obs)"
          , "  pure (bounds, observed)"
          ]
    , testCase "a positional constructor declaration is a definition, not an application" $ do
        -- The declared field types are not arguments: `Double` is neither a
        -- literal nor a table projection, so reading the declaration as a
        -- saturated application would report it as an unsourced bar.
        expect [] productPath ["data Cohort = ConvergenceThreshold Double Double"]
        expect
          []
          productPath
          [ "data Cohort"
          , "  = ConvergenceThreshold Double Double"
          , "  | SlConvergenceThreshold Double Double"
          ]
    , testCase "a measurement bound in one declaration does not taint the same name in another" $
        -- 'objective' is a measurement in the first declaration and an ordinary
        -- name in the second; a file-wide alias table read the second as measured.
        expect
          []
          productPath
          [ "first spec ="
          , "  do"
          , "    objective <- measuredRungObjective spec"
          , "    pure objective"
          , "second runtime ="
          , "  do"
          , "    objective <- latestObjective runtime"
          , "    let threshold ="
          , "          case kind of"
          , "            Median -> median prior"
          , "            NoPruner -> objective"
          , "    pure threshold"
          ]
    , testCase "a top-level measured binding is visible from every declaration" $
        expect
          [measured]
          productPath
          [ "observedTarget = coMetricValue observation"
          , "bar = mkConvergenceBar name MetricMaximise observedTarget 0.05"
          ]
    , testCase "a threshold binding that mentions a measurement is rejected wherever it sits" $
        expect
          [measured]
          productPath
          [ "check obs = passes"
          , "  where"
          , "    threshold ="
          , "      coMetricValue obs"
          , "    passes = value >= threshold"
          ]
    ]

exemptionTests :: TestTree
exemptionTests =
  testGroup
    "exemptions"
    [ testCase "test-support code may build the deliberately self-referential known fake" $
        expect
          []
          "src/JitML/Test/NegativeControls.hs"
          ["fake = mkConvergenceBar \"test_accuracy\" MetricMaximise selfReferentialMeasured 0.0"]
    , testCase "the scanner's own source is not scanned" $
        expect
          []
          "src/JitML/Lint/ProductTruth.hs"
          ["fake = mkConvergenceBar \"test_accuracy\" MetricMaximise measuredValue 0.0"]
    , testCase "the module that defines the bar constructor is exempt from the sourced rule only" $ do
        let application = ["bar = mkConvergenceBar metricName goal target slack"]
            record = ["rec = ConvergenceBar {convergenceLiteratureTarget = target}"]
            positional = ["pos = ConvergenceBar metricName goal target slack threshold"]
        expect [] "src/JitML/Product/Convergence.hs" (application <> record <> positional)
        -- The same source anywhere else has neither a literal nor a table
        -- projection to show for its target and slack.
        expect [nonLiteral, nonLiteral] productPath application
        expect [nonLiteral] productPath record
        expect [nonLiteral, nonLiteral, nonLiteral] productPath positional
        expect
          [measured]
          "src/JitML/Product/Convergence.hs"
          ["bar = mkConvergenceBar metricName goal measuredValue slack"]
        expect
          [measured]
          "src/JitML/Product/Convergence.hs"
          ["pos = ConvergenceBar metricName goal measuredValue slack threshold"]
    ]

-- ---------------------------------------------------------------------------
-- The repository itself

-- | Every Haskell source under a directory, or nothing when it is absent.
haskellSources :: FilePath -> IO [FilePath]
haskellSources root = do
  exists <- doesDirectoryExist root
  if not exists
    then pure []
    else do
      entries <- listDirectory root
      concat
        <$> traverse
          ( \entry -> do
              let path = root </> entry
              isDirectory <- doesDirectoryExist path
              if isDirectory
                then haskellSources path
                else pure [path | takeExtension path == ".hs"]
          )
          entries

sourceOf :: FilePath -> IO Text
sourceOf path = do
  present <- doesFileExist path
  assertBool (path <> " must exist: run the suite from the repository root") present
  Text.IO.readFile path

-- | Replace the one occurrence of @needle@ that a mutation targets, failing
-- when the source no longer contains it exactly once, so a mutation can never
-- silently stop exercising the file it is meant to.
replaceOnce :: Text -> Text -> Text -> IO Text
replaceOnce needle replacement source =
  case Text.breakOnAll needle source of
    [_] -> pure (Text.replace needle replacement source)
    occurrences ->
      assertFailure
        ( "expected exactly one occurrence of "
            <> show needle
            <> ", found "
            <> show (length occurrences)
        )

-- | A repository tree in a private temporary directory: each entry is a path
-- relative to the root and the lines of the file there.
withTree :: [(FilePath, [Text])] -> (FilePath -> IO a) -> IO a
withTree files action =
  withSystemTempDirectory "jitml-product-truth" $ \root -> do
    for_ files $ \(relative, sourceLines) -> do
      createDirectoryIfMissing True (takeDirectory (root </> relative))
      Text.IO.writeFile (root </> relative) (Text.unlines sourceLines)
    action root

-- | What the gate reports for a tree, as path and key, in report order.
gateFindings :: FilePath -> IO [(FilePath, Text)]
gateFindings root = do
  findings <- ProductTruth.checkProductTruthIn root
  pure [(findingPath finding, findingKey finding) | finding <- findings]

repositoryTests :: TestTree
repositoryTests =
  testGroup
    "repository"
    [ gateWalkTests
    , testCase "the gate's own file set (src) produces no findings" $ do
        -- The count is taken from the gate's own walk, not from a walk of the
        -- test's own: a gate that read nothing (or one file) produces no
        -- findings either, and only the size of what it read can tell.
        sources <- ProductTruth.productTruthSourceFiles "."
        assertBool
          ("the gate walks the src tree; found only " <> show (length sources) <> " sources")
          (length sources > 250)
        -- Findings are reported in path order, whatever order the file system lists.
        sources @?= sort sources
        assertBool
          "the gate walks the registry and the cohort tables"
          ( all
              (`elem` sources)
              [ "src/JitML/Product/Matrix.hs"
              , "src/JitML/RL/ConvergenceThresholds.hs"
              , "src/JitML/SL/ConvergenceThresholds.hs"
              ]
          )
        findings <- ProductTruth.checkProductTruth
        [(findingPath finding, findingKey finding) | finding <- findings] @?= []
    , testCase "app produces no findings either" $ do
        sources <- haskellSources "app"
        assertBool "app has sources" (not (null sources))
        for_ sources $ \path -> do
          source <- Text.IO.readFile path
          fmap findingKey (ProductTruth.scanProductTruthSourceText path source) @?= []
    , testCase "the real registry is analysed: a measured tuning target is found" $ do
        let path = "src/JitML/Product/Matrix.hs"
        source <- sourceOf path
        fmap findingKey (ProductTruth.scanProductTruthSourceText path source) @?= []
        mutated <-
          replaceOnce
            "(mkConvergenceBar \"best_objective\" MetricMaximise 1.0 0.05)"
            "(mkConvergenceBar \"best_objective\" MetricMaximise measuredObjective 0.05)"
            source
        fmap findingKey (ProductTruth.scanProductTruthSourceText path mutated) @?= [measured]
    , testCase "the real registry is analysed: a helper-wrapped RL target is found" $ do
        let path = "src/JitML/Product/Matrix.hs"
        source <- sourceOf path
        mutated <-
          replaceOnce
            "(RLConvergence.literatureTarget RLConvergence.herGoalSuccessThreshold)"
            "(finalize (RLConvergence.hgmSuccessRate metric))"
            source
        fmap findingKey (ProductTruth.scanProductTruthSourceText path mutated) @?= [nonLiteral]
    , testCase "the real registry is analysed: a multi-line row bar with a measured slack is found" $ do
        let path = "src/JitML/Product/Matrix.hs"
        source <- sourceOf path
        mutated <-
          replaceOnce
            "(RLConvergence.slack (RLConvergence.fbrThreshold row))"
            "(RLConvergence.measuredSlack (RLConvergence.fbrThreshold row))"
            source
        fmap findingKey (ProductTruth.scanProductTruthSourceText path mutated) @?= [measured]
    , testCase "the real RL cohort table is analysed: a split, hidden target is found" $ do
        source <- sourceOf rlTablePath
        fmap findingKey (ProductTruth.scanProductTruthSourceText rlTablePath source) @?= []
        mutated <-
          replaceOnce
            "ConvergenceThreshold 475.0 75.0)\n  , ((\"TRPO\", \"mountain-car\")"
            "ConvergenceThreshold\n      hiddenTarget 75.0)\n  , ((\"TRPO\", \"mountain-car\")"
            source
        fmap findingKey (ProductTruth.scanProductTruthSourceText rlTablePath mutated) @?= [nonLiteral]
    , testCase "the real SL cohort table is analysed: a measured accuracy target is found" $ do
        let path = "src/JitML/SL/ConvergenceThresholds.hs"
        source <- sourceOf path
        fmap findingKey (ProductTruth.scanProductTruthSourceText path source) @?= []
        mutated <-
          replaceOnce
            "SlConvergenceThreshold 0.99 0.69"
            "SlConvergenceThreshold measuredAccuracy 0.69"
            source
        fmap findingKey (ProductTruth.scanProductTruthSourceText path mutated) @?= [measured]
    ]

-- | The gate itself, run over a temporary repository tree. Each violating file
-- yields a finding, so a walk that skips a directory, reads a single file, or
-- looks in the wrong place is seen by the findings it fails to produce.
gateWalkTests :: TestTree
gateWalkTests =
  testGroup
    "the gate's walk (checkProductTruthIn)"
    [ testCase "it reads every Haskell source below src, at any depth, and nothing else" $
        gateReports
          [ ("src/JitML/Product/Measured.hs", [measuredBarLine])
          , ("src/JitML/Deep/Er/Still/Hidden.hs", [helperBarLine])
          , ("src/JitML/Product/Clean.hs", [literalBarLine])
          , ("src/JitML/Product/Notes.txt", [measuredBarLine])
          , ("docs/Outside.hs", [measuredBarLine])
          ]
          [ ("src/JitML/Deep/Er/Still/Hidden.hs", nonLiteral)
          , ("src/JitML/Product/Measured.hs", measured)
          ]
    , testCase "the exemptions apply by repository-relative path, wherever the root is" $
        gateReports
          [ ("src/JitML/Test/Fake.hs", [measuredFakeLine])
          , ("src/JitML/Product/Convergence.hs", ["bar = mkConvergenceBar metricName goal target slack"])
          ]
          []
    , testCase "the import walk runs over the same files and reports repository-relative paths" $
        gateReports
          [ ("src/JitML/App.hs", ["module JitML.App where", "import JitML.RL.Loop (loop)"])
          , ("src/JitML/RL/Loop.hs", ["module JitML.RL.Loop where", "loop = 1"])
          ]
          [("src/JitML/App.hs", "product-truth.reachable-import")]
    , testCase "the scaffold needles are reported per file through the same walk" $
        gateReports
          [ ("src/JitML/Sub/Scaffold.hs", ["x = deterministicStep"])
          , ("src/JitML/Clean.hs", ["x = 1"])
          ]
          [("src/JitML/Sub/Scaffold.hs", "product-truth.scaffold.deterministicStep")]
    ]

measuredBarLine :: Text
measuredBarLine = "bar = mkConvergenceBar name MetricMaximise measuredValue 0.05"

helperBarLine :: Text
helperBarLine = "bar = mkConvergenceBar name MetricMaximise (finalize obs) 0.05"

literalBarLine :: Text
literalBarLine = "bar = mkConvergenceBar name MetricMaximise 0.9 0.05"

measuredFakeLine :: Text
measuredFakeLine =
  "fake = mkConvergenceBar \"test_accuracy\" MetricMaximise selfReferentialMeasured 0.0"

-- | The gate reports exactly the given findings (path and key) for a tree.
gateReports :: [(FilePath, [Text])] -> [(FilePath, Text)] -> Assertion
gateReports files expected =
  withTree files $ \root -> do
    found <- gateFindings root
    found @?= expected
