module JitML.Plan.Apply
  ( apply
  , writePlanFile
  )
where

import Data.Text (Text)
import Data.Text.IO qualified as Text.IO
import System.Directory (createDirectoryIfMissing)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory)

import JitML.Plan.Plan (Plan)

apply :: Plan inputs result -> IO ExitCode
apply _plan =
  pure ExitSuccess

writePlanFile :: FilePath -> Text -> IO ()
writePlanFile path rendered = do
  createDirectoryIfMissing True (takeDirectory path)
  Text.IO.writeFile path rendered
