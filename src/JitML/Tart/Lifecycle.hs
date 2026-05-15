{-# LANGUAGE OverloadedStrings #-}

module JitML.Tart.Lifecycle
  ( VmName (..)
  , ensureVmUp
  , vmStatePath
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))

newtype VmName = VmName
  { unVmName :: Text
  }
  deriving stock (Eq, Show)

ensureVmUp :: FilePath -> VmName -> IO ()
ensureVmUp root vmName = do
  createDirectoryIfMissing True (root </> ".build" </> "runtime")
  Text.IO.writeFile (vmStatePath root vmName) "up\n"

vmStatePath :: FilePath -> VmName -> FilePath
vmStatePath root vmName =
  root </> ".build" </> "runtime" </> Text.unpack (unVmName vmName) <> ".state"
