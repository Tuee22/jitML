{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.CLI.Json
    ( renderCommandJson
    )
where

import Data.Aeson ((.=))
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy (ByteString)
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.CLI.Spec
    ( CommandSpec (..)
    , Example (..)
    , OptionKind (..)
    , OptionSpec (..)
    , commandLeaves
    , commandPathText
    , commandUsage
    )

renderCommandJson :: CommandSpec -> ByteString
renderCommandJson registry =
    Aeson.encode $
        Aeson.object
            [ "format" .= ("json" :: Text)
            , "commands" .= fmap leafObject (commandLeaves registry)
            ]

leafObject :: ([Text], CommandSpec) -> Aeson.Value
leafObject (path, spec) =
    Aeson.object
        [ "path" .= path
        , "command" .= commandPathText path
        , "usage" .= commandUsage path spec
        , "summary" .= summary spec
        , "description" .= commandDescription spec
        , "options" .= fmap optionObject (options spec)
        , "examples" .= fmap exampleObject (examples spec)
        ]

optionObject :: OptionSpec -> Aeson.Value
optionObject option =
    Aeson.object
        [ "longName" .= longName option
        , "shortName" .= fmap Text.singleton (shortName option)
        , "metavar" .= metavar option
        , "description" .= optionDescription option
        , "required" .= required option
        , "kind" .= optionKindText (optionKind option)
        ]

exampleObject :: Example -> Aeson.Value
exampleObject example =
    Aeson.object
        [ "command" .= exampleCommand example
        , "description" .= exampleDescription example
        ]

optionKindText :: OptionKind -> Text
optionKindText FlagOption = "flag"
optionKindText ValueOption = "value"
optionKindText PositionalOption = "positional"
optionKindText RemainderOption = "remainder"

commandDescription :: CommandSpec -> Text
commandDescription CommandSpec{description = value} = value

optionDescription :: OptionSpec -> Text
optionDescription OptionSpec{description = value} = value
