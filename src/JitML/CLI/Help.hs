{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.CLI.Help
    ( renderCommandHelp
    , renderHelp
    )
where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.CLI.Spec
    ( CommandSpec (..)
    , Example (..)
    , OptionKind (..)
    , OptionSpec (..)
    , commandPathText
    , commandUsage
    , findCommand
    )

renderHelp :: [Text] -> Either Text Text
renderHelp path =
    case findCommand path of
        Just spec -> Right (renderCommandHelp path spec)
        Nothing -> Left ("unknown command: " <> commandPathText path)

renderCommandHelp :: [Text] -> CommandSpec -> Text
renderCommandHelp path spec =
    Text.intercalate
        "\n"
        [ commandPathText path
        , ""
        , summary spec
        , ""
        , commandDescription spec
        , ""
        , "Usage:"
        , "  " <> commandUsage path spec
        , renderOptions (options spec)
        , renderSubcommands (children spec)
        , renderExamples (examples spec)
        ]

renderOptions :: [OptionSpec] -> Text
renderOptions [] = ""
renderOptions commandOptions =
    Text.intercalate
        "\n"
        ( ""
            : "Options:"
            : fmap renderOption commandOptions
        )
  where
    width = maximum (fmap (Text.length . optionLabel) commandOptions)

    renderOption option =
        "  " <> padRight width (optionLabel option) <> "  " <> optionDescription option

renderSubcommands :: [CommandSpec] -> Text
renderSubcommands [] = ""
renderSubcommands specs =
    Text.intercalate
        "\n"
        ( ""
            : "Subcommands:"
            : fmap renderSubcommand specs
        )
  where
    width = maximum (fmap (Text.length . name) specs)

    renderSubcommand spec =
        "  " <> padRight width (name spec) <> "  " <> summary spec

renderExamples :: [Example] -> Text
renderExamples [] = ""
renderExamples commandExamples =
    Text.intercalate
        "\n"
        ( ""
            : "Examples:"
            : concatMap renderExample commandExamples
        )
  where
    renderExample example =
        [ "  " <> exampleCommand example
        , "      " <> exampleDescription example
        ]

optionLabel :: OptionSpec -> Text
optionLabel option =
    case optionKind option of
        FlagOption -> dashedOption option
        ValueOption -> dashedOption option <> " <" <> metavarText option <> ">"
        PositionalOption -> "<" <> metavarText option <> ">"
        RemainderOption -> "-- <" <> metavarText option <> "...>"

dashedOption :: OptionSpec -> Text
dashedOption option =
    case shortName option of
        Just short ->
            "-" <> Text.singleton short <> ", --" <> longName option
        Nothing ->
            "--" <> longName option

metavarText :: OptionSpec -> Text
metavarText option =
    case metavar option of
        Just label -> label
        Nothing -> longName option

padRight :: Int -> Text -> Text
padRight width value =
    value <> Text.replicate (max 0 (width - Text.length value)) " "

commandDescription :: CommandSpec -> Text
commandDescription CommandSpec{description = value} = value

optionDescription :: OptionSpec -> Text
optionDescription OptionSpec{description = value} = value
