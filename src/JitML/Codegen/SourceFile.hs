module JitML.Codegen.SourceFile
  ( SourceFile (..)
  )
where

import Data.Text (Text)

data SourceFile = SourceFile
  { sourceRelativePath :: FilePath
  , sourceContents :: Text
  }
  deriving stock (Eq, Show)
