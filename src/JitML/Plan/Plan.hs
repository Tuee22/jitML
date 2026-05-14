{-# LANGUAGE OverloadedStrings #-}

module JitML.Plan.Plan
    ( CommandInputs (..)
    , CommandResult (..)
    , Plan (..)
    , PlanStep (..)
    , buildCommandPlan
    )
where

import Data.Text (Text)
import Data.Text qualified as Text

data Plan inputs result = Plan
    { planName :: Text
    , planInputs :: inputs
    , planSteps :: [PlanStep]
    , planResult :: result
    }
    deriving stock (Eq, Show)

data PlanStep = PlanStep
    { stepName :: Text
    , stepDescription :: Text
    }
    deriving stock (Eq, Show)

data CommandInputs = CommandInputs
    { inputCommand :: Text
    , inputOptions :: [(Text, [Text])]
    }
    deriving stock (Eq, Show)

data CommandResult = CommandResult
    { resultSummary :: Text
    }
    deriving stock (Eq, Show)

buildCommandPlan :: [Text] -> [(Text, [Text])] -> Either Text (Plan CommandInputs CommandResult)
buildCommandPlan path optionPairs =
    Right
        Plan
            { planName = "command plan"
            , planInputs =
                CommandInputs
                    { inputCommand = commandText
                    , inputOptions = optionPairs
                    }
            , planSteps =
                [ PlanStep "parse-command" "Parse and validate the command surface from CommandSpec."
                , PlanStep "check-prerequisites" "Run the prerequisite gate for the command before mutation."
                , PlanStep "apply-command" "Apply the command implementation owned by its later sprint."
                ]
            , planResult =
                CommandResult
                    { resultSummary = "No side effects are performed while rendering a plan."
                    }
            }
  where
    commandText = Text.unwords ("jitml" : path)
