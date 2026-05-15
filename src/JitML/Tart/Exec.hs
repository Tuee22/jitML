{-# LANGUAGE OverloadedStrings #-}

module JitML.Tart.Exec
  ( tartSshSubprocess
  )
where

import Data.Text (Text)

import JitML.Sub.Subprocess (Subprocess, subprocess)
import JitML.Tart.Lifecycle (VmName (..))

tartSshSubprocess :: VmName -> [Text] -> Subprocess
tartSshSubprocess vmName command =
  subprocess "tart" (["ssh", unVmName vmName, "--"] <> command)
