{-# LANGUAGE OverloadedStrings #-}

module JitML.CLI.Tree
  ( renderCommandList
  , renderCommandTree
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.CLI.Spec (CommandSpec (..), commandLeaves, commandPathText)

renderCommandList :: CommandSpec -> Text
renderCommandList registry =
  Text.unlines (fmap (commandPathText . fst) (commandLeaves registry))

renderCommandTree :: CommandSpec -> Text
renderCommandTree registry =
  Text.unlines (name registry : concatMap (renderChild 1) (children registry))

renderChild :: Int -> CommandSpec -> [Text]
renderChild depth spec =
  let line = Text.replicate depth "  " <> name spec
   in line : concatMap (renderChild (depth + 1)) (children spec)
