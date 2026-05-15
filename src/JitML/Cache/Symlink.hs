module JitML.Cache.Symlink
  ( repointSymlink
  )
where

import Path (Abs, Dir, File, Path, toFilePath)
import System.Directory (createDirectoryIfMissing, removeFile, renameFile)
import System.FilePath (takeDirectory)
import System.IO (hClose, openTempFile)
import System.Posix.Files (createSymbolicLink)

import JitML.Cache.Key (Extension, Hash, ModelId, Substrate (AppleSilicon))
import JitML.Cache.Layout (appleSymlinkPath, cachePath)

repointSymlink :: Path Abs Dir -> ModelId -> Hash -> Extension -> IO (Path Abs File)
repointSymlink buildRoot modelId hash extension = do
  target <- cachePath buildRoot AppleSilicon hash extension
  link <- appleSymlinkPath buildRoot modelId extension
  let linkPath = toFilePath link
      linkDir = takeDirectory linkPath
  createDirectoryIfMissing True linkDir
  (tmpPath, handle) <- openTempFile linkDir ".jitml-link"
  hClose handle
  removeFile tmpPath
  createSymbolicLink (toFilePath target) tmpPath
  renameFile tmpPath linkPath
  pure link
