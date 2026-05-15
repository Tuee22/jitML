{-# LANGUAGE OverloadedStrings #-}

module JitML.Prerequisite.Reconcile
  ( PrerequisiteError (..)
  , reconcilePrerequisites
  , renderPrerequisiteError
  , transitiveClosure
  )
where

import Data.List (find)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Prerequisite.Registry (NodeId (..), Prerequisite (..))

data PrerequisiteError = PrerequisiteUnmet
  { failingNodeId :: NodeId
  , failingDescription :: Text
  , failingRemedyHint :: Maybe Text
  }
  deriving stock (Eq, Show)

reconcilePrerequisites :: [Prerequisite] -> NodeId -> IO (Either PrerequisiteError ())
reconcilePrerequisites prerequisites root = do
  case transitiveClosure prerequisites root of
    Left err -> pure (Left err)
    Right closure -> checkClosure closure

transitiveClosure :: [Prerequisite] -> NodeId -> Either PrerequisiteError [Prerequisite]
transitiveClosure prerequisites root =
  reverse <$> go [] [] root
 where
  go visiting visited node
    | node `elem` visited = Right []
    | node `elem` visiting = Left (missingNodeError node)
    | otherwise =
        case find ((== node) . nodeId) prerequisites of
          Nothing -> Left (missingNodeError node)
          Just prerequisite -> do
            dependencies <- concat <$> traverse (go (node : visiting) (node : visited)) (dependsOn prerequisite)
            Right (prerequisite : dependencies)

checkClosure :: [Prerequisite] -> IO (Either PrerequisiteError ())
checkClosure [] = pure (Right ())
checkClosure (prerequisite : rest) = do
  ok <- checkNode prerequisite
  if ok
    then checkClosure rest
    else
      pure $
        Left
          PrerequisiteUnmet
            { failingNodeId = nodeId prerequisite
            , failingDescription = nodeDescription prerequisite
            , failingRemedyHint = remedyHint prerequisite
            }

renderPrerequisiteError :: PrerequisiteError -> Text
renderPrerequisiteError err =
  Text.unlines
    [ "node: " <> unNodeId (failingNodeId err)
    , "description: " <> failingDescription err
    , "remedy: " <> fromMaybe "(none)" (failingRemedyHint err)
    ]

missingNodeError :: NodeId -> PrerequisiteError
missingNodeError node =
  PrerequisiteUnmet
    { failingNodeId = node
    , failingDescription = "Prerequisite node is not registered."
    , failingRemedyHint = Just "add the node to prerequisiteRegistry"
    }
