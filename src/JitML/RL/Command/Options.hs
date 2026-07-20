{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.Command.Options
  ( envWithDefault
  , mountedRunConfigDecodeError
  , parsePositiveAppInt
  , rejectMissingMountedRunConfigInKubernetes
  , requirePositiveAppInt
  , requireUserIntOptionAtLeast
  , selectedValue
  )
where

import Control.Monad (when)
import Control.Monad.Reader (liftIO)
import Data.Text (Text)
import Data.Text qualified as Text
import System.Environment (lookupEnv)
import Text.Read (readMaybe)

import JitML.AppError.AppError (AppError (..))
import JitML.CLI.Output (exitWithError)
import JitML.CLI.Parser (ParsedOption (..))
import JitML.Env.Env (App)

optionValues :: Text -> [ParsedOption] -> [Text]
optionValues expected =
  concatMap selectedValues
 where
  selectedValues option
    | parsedOptionName option == expected = parsedOptionValues option
    | otherwise = []

selectedValue :: Text -> Text -> [ParsedOption] -> Text
selectedValue optionName fallback parsedOptions =
  case optionValues optionName parsedOptions of
    [] -> fallback
    value : _ -> value

parseUserIntOptionAtLeast :: Text -> Int -> Int -> [ParsedOption] -> Either AppError Int
parseUserIntOptionAtLeast optionName fallback minimumValue parsedOptions =
  let raw = selectedValue optionName (Text.pack (show fallback)) parsedOptions
   in case readMaybe (Text.unpack raw) of
        Just parsed | parsed >= minimumValue -> Right parsed
        _ ->
          Left
            ( InvalidConfig
                ( "invalid --"
                    <> optionName
                    <> " value: \""
                    <> raw
                    <> "\"; expected an integer >= "
                    <> Text.pack (show minimumValue)
                )
            )

requireUserIntOptionAtLeast :: Text -> Int -> Int -> [ParsedOption] -> App Int
requireUserIntOptionAtLeast optionName fallback minimumValue parsedOptions =
  either exitWithError pure (parseUserIntOptionAtLeast optionName fallback minimumValue parsedOptions)

requirePositiveAppInt :: Text -> Int -> App Int
requirePositiveAppInt label value
  | value <= 0 = exitWithError (InvalidConfig (label <> " must be positive"))
  | otherwise = pure value

parsePositiveAppInt :: Text -> Text -> App Int
parsePositiveAppInt label raw =
  case readMaybe (Text.unpack raw) of
    Nothing ->
      exitWithError
        (InvalidConfig (label <> " must be a positive integer, received " <> raw))
    Just value -> requirePositiveAppInt label value

envWithDefault :: String -> Text -> IO Text
envWithDefault name fallback = do
  raw <- lookupEnv name
  pure $ case raw of
    Just value | not (null value) -> Text.pack value
    _ -> fallback

mountedRunConfigDecodeError :: FilePath -> Text -> Text -> AppError
mountedRunConfigDecodeError runConfigPath configName detail =
  InvalidConfig
    ( "failed to decode mounted "
        <> configName
        <> " at "
        <> Text.pack runConfigPath
        <> ": "
        <> detail
    )

rejectMissingMountedRunConfigInKubernetes :: FilePath -> Text -> App ()
rejectMissingMountedRunConfigInKubernetes runConfigPath configName = do
  kubernetesHost <- liftIO (lookupEnv "KUBERNETES_SERVICE_HOST")
  when (maybe False (not . null) kubernetesHost) $
    exitWithError
      ( mountedRunConfigDecodeError
          runConfigPath
          configName
          "required resolved-plan mount is missing in a Kubernetes workload"
      )
