{-# LANGUAGE OverloadedStrings #-}

module JitML.Plan.Render
  ( renderPlan
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Plan.Plan (CommandInputs (..), CommandResult (..), Plan (..), PlanStep (..))

renderPlan :: Plan CommandInputs CommandResult -> Text
renderPlan plan =
  Text.unlines $
    [ "Plan: " <> planName plan
    , "Command: " <> inputCommand (planInputs plan)
    , "Options:"
    ]
      <> optionLines (inputOptions (planInputs plan))
      <> [ "Steps:"
         ]
      <> fmap stepLine (zip [(1 :: Int) ..] (planSteps plan))
      <> [ "Result: " <> resultSummary (planResult plan)
         ]

optionLines :: [(Text, [Text])] -> [Text]
optionLines [] = ["  (none)"]
optionLines options =
  fmap optionLine options

optionLine :: (Text, [Text]) -> Text
optionLine (name, values) =
  "  " <> name <> valueText
 where
  valueText
    | null values = ""
    | otherwise = ": " <> Text.intercalate ", " values

stepLine :: (Int, PlanStep) -> Text
stepLine (index, step) =
  "  " <> Text.pack (show index) <> ". " <> stepName step <> " - " <> stepDescription step
