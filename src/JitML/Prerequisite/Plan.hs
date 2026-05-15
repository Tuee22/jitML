{-# LANGUAGE OverloadedStrings #-}

module JitML.Prerequisite.Plan
  ( PrerequisitePlan (..)
  , PrerequisitePlanError (..)
  , PrerequisitePlanStep (..)
  , applyPrerequisitePlan
  , buildPrerequisitePlan
  , renderPrerequisitePlan
  )
where

import Data.List (find)
import Data.Maybe (catMaybes, fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import System.Exit (ExitCode (..))

import JitML.Prerequisite.Reconcile (PrerequisiteError, transitiveClosure)
import JitML.Prerequisite.Types (NodeId (..), Prerequisite (..), PrerequisiteRemediation (..))
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Stream (SubprocessEnv, runStreaming)

data PrerequisitePlan = PrerequisitePlan
  { prerequisitePlanRoot :: NodeId
  , prerequisitePlanSteps :: [PrerequisitePlanStep]
  }
  deriving stock (Eq, Show)

data PrerequisitePlanStep = PrerequisitePlanStep
  { prerequisiteStepNodeId :: NodeId
  , prerequisiteStepDescription :: Text
  , prerequisiteStepRemedyHint :: Maybe Text
  , prerequisiteStepRemediation :: Maybe PrerequisiteRemediation
  }
  deriving stock (Eq, Show)

data PrerequisitePlanError
  = PrerequisitePlanMissingRemediation NodeId Text
  | PrerequisitePlanRemediationFailed NodeId Text ExitCode Text
  | PrerequisitePlanPostconditionFailed NodeId Text
  deriving stock (Eq, Show)

buildPrerequisitePlan :: [Prerequisite] -> NodeId -> IO (Either PrerequisiteError PrerequisitePlan)
buildPrerequisitePlan prerequisites root =
  case transitiveClosure prerequisites root of
    Left err -> pure (Left err)
    Right closure -> do
      steps <- catMaybes <$> traverse missingStep closure
      pure
        ( Right
            PrerequisitePlan
              { prerequisitePlanRoot = root
              , prerequisitePlanSteps = steps
              }
        )

missingStep :: Prerequisite -> IO (Maybe PrerequisitePlanStep)
missingStep prerequisite = do
  ok <- checkNode prerequisite
  pure $
    if ok
      then Nothing
      else
        Just
          PrerequisitePlanStep
            { prerequisiteStepNodeId = nodeId prerequisite
            , prerequisiteStepDescription = nodeDescription prerequisite
            , prerequisiteStepRemedyHint = remedyHint prerequisite
            , prerequisiteStepRemediation = remediation prerequisite
            }

renderPrerequisitePlan :: PrerequisitePlan -> Text
renderPrerequisitePlan plan =
  Text.unlines $
    [ "Prerequisite remediation plan:"
    , "root: " <> unNodeId (prerequisitePlanRoot plan)
    ]
      <> case prerequisitePlanSteps plan of
        [] -> ["  (no missing prerequisites)"]
        steps -> concatMap renderStep steps

renderStep :: PrerequisitePlanStep -> [Text]
renderStep step =
  [ "  " <> unNodeId (prerequisiteStepNodeId step)
  , "    description: " <> prerequisiteStepDescription step
  , "    remedy: " <> fromMaybe "(none)" (prerequisiteStepRemedyHint step)
  , "    remediation: " <> renderRemediation (prerequisiteStepRemediation step)
  ]

renderRemediation :: Maybe PrerequisiteRemediation -> Text
renderRemediation Nothing = "(manual)"
renderRemediation (Just remediationValue) =
  remediationDescription remediationValue
    <> " "
    <> renderSubprocess (remediationCommand remediationValue)

applyPrerequisitePlan
  :: SubprocessEnv -> [Prerequisite] -> PrerequisitePlan -> IO (Either PrerequisitePlanError ())
applyPrerequisitePlan subprocessEnv prerequisites plan =
  applySteps (prerequisitePlanSteps plan)
 where
  applySteps [] = pure (Right ())
  applySteps (step : rest) = do
    result <- applyStep step
    case result of
      Left err -> pure (Left err)
      Right () -> applySteps rest

  applyStep step =
    case prerequisiteStepRemediation step of
      Nothing ->
        pure $
          Left
            ( PrerequisitePlanMissingRemediation
                (prerequisiteStepNodeId step)
                (fromMaybe "(none)" (prerequisiteStepRemedyHint step))
            )
      Just remediationValue -> do
        let commandText = renderSubprocess (remediationCommand remediationValue)
        (exitCode, _stdoutText, stderrText) <-
          runStreaming subprocessEnv (remediationCommand remediationValue)
        case exitCode of
          ExitSuccess -> validatePostcondition step
          _ ->
            pure $
              Left
                ( PrerequisitePlanRemediationFailed
                    (prerequisiteStepNodeId step)
                    commandText
                    exitCode
                    stderrText
                )

  validatePostcondition step =
    case find ((== prerequisiteStepNodeId step) . nodeId) prerequisites of
      Nothing ->
        pure $
          Left
            ( PrerequisitePlanPostconditionFailed
                (prerequisiteStepNodeId step)
                "node disappeared from prerequisite registry"
            )
      Just prerequisite -> do
        ok <- checkNode prerequisite
        pure $
          if ok
            then Right ()
            else
              Left
                ( PrerequisitePlanPostconditionFailed
                    (prerequisiteStepNodeId step)
                    (nodeDescription prerequisite)
                )
