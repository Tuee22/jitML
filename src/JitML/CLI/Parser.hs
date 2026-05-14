{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.CLI.Parser
    ( ParsedCommand (..)
    , ParsedOption (..)
    , commandParser
    , parseCommandPure
    , parserInfo
    )
where

import Control.Applicative (many, optional, some)
import Data.Maybe (maybeToList)
import Data.Text (Text)
import Data.Text qualified as Text
import Options.Applicative qualified as OA
import Options.Applicative
    ( CommandFields
    , FlagFields
    , Mod
    , OptionFields
    , Parser
    , ParserInfo
    , ParserResult
    )

import JitML.CLI.Spec
    ( CommandSpec (..)
    , OptionKind (..)
    , OptionSpec (..)
    , commandRegistry
    )

data ParsedCommand = ParsedCommand
    { parsedPath :: [Text]
    , parsedOptions :: [ParsedOption]
    }
    deriving stock (Eq, Show)

data ParsedOption = ParsedOption
    { parsedOptionName :: Text
    , parsedOptionValues :: [Text]
    }
    deriving stock (Eq, Show)

parserInfo :: ParserInfo ParsedCommand
parserInfo =
    OA.info
        (commandParser commandRegistry)
        ( OA.fullDesc
            <> OA.progDesc (Text.unpack (summary commandRegistry))
            <> OA.header "jitml"
        )

parseCommandPure :: [String] -> ParserResult ParsedCommand
parseCommandPure = OA.execParserPure OA.defaultPrefs parserInfo

commandParser :: CommandSpec -> Parser ParsedCommand
commandParser registry =
    OA.hsubparser (mconcat (fmap childCommand (children registry)))

childCommand :: CommandSpec -> Mod CommandFields ParsedCommand
childCommand spec =
    OA.command
        (Text.unpack (name spec))
        (OA.info (parserFromSpec [name spec] spec) (OA.progDesc (Text.unpack (summary spec))))

parserFromSpec :: [Text] -> CommandSpec -> Parser ParsedCommand
parserFromSpec path spec
    | null (children spec) =
        ParsedCommand path . concat <$> traverse optionParser (options spec)
    | otherwise =
        OA.hsubparser (mconcat (fmap nestedCommand (children spec)))
  where
    nestedCommand child =
        OA.command
            (Text.unpack (name child))
            (OA.info (parserFromSpec (path <> [name child]) child) (OA.progDesc (Text.unpack (summary child))))

optionParser :: OptionSpec -> Parser [ParsedOption]
optionParser option =
    case optionKind option of
        FlagOption -> flagOption option
        ValueOption -> valueOption option
        PositionalOption -> positionalOption option
        RemainderOption -> remainderOption option

flagOption :: OptionSpec -> Parser [ParsedOption]
flagOption option
    | required option = pure <$> OA.flag'
        (ParsedOption (longName option) [])
        (flagMods option)
    | otherwise =
        maybeToList <$> optional
            ( OA.flag'
                (ParsedOption (longName option) [])
                (flagMods option)
            )

valueOption :: OptionSpec -> Parser [ParsedOption]
valueOption option
    | required option =
        oneValue <$> OA.strOption (valueMods option)
    | otherwise =
        maybe [] oneValue <$> optional (OA.strOption (valueMods option))
  where
    oneValue value =
        [ParsedOption (longName option) [Text.pack value]]

positionalOption :: OptionSpec -> Parser [ParsedOption]
positionalOption option
    | required option =
        oneValue <$> OA.argument OA.str (OA.metavar (Text.unpack (metavarText option)) <> OA.help (Text.unpack (optionDescription option)))
    | otherwise =
        maybe [] oneValue <$> optional (OA.argument OA.str (OA.metavar (Text.unpack (metavarText option)) <> OA.help (Text.unpack (optionDescription option))))
  where
    oneValue value =
        [ParsedOption (longName option) [Text.pack value]]

remainderOption :: OptionSpec -> Parser [ParsedOption]
remainderOption option
    | required option =
        oneRemainder <$> some remainderArgument
    | otherwise =
        oneRemainder <$> manyArguments
  where
    remainderArgument =
        OA.argument OA.str (OA.metavar (Text.unpack (metavarText option)) <> OA.help (Text.unpack (optionDescription option)))

    manyArguments =
        many remainderArgument

    oneRemainder values =
        [ParsedOption (longName option) (fmap Text.pack values)]

flagMods :: OptionSpec -> Mod FlagFields ParsedOption
flagMods option =
    OA.long (Text.unpack (longName option))
        <> maybe mempty OA.short (shortName option)
        <> OA.help (Text.unpack (optionDescription option))

valueMods :: OptionSpec -> Mod OptionFields String
valueMods option =
    OA.long (Text.unpack (longName option))
        <> maybe mempty OA.short (shortName option)
        <> OA.metavar (Text.unpack (metavarText option))
        <> OA.help (Text.unpack (optionDescription option))

metavarText :: OptionSpec -> Text
metavarText option =
    case metavar option of
        Just label -> label
        Nothing -> longName option

optionDescription :: OptionSpec -> Text
optionDescription OptionSpec{description = value} = value
