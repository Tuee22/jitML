{-# LANGUAGE OverloadedStrings #-}

module JitML.Tart.Exec
  ( tartExecSubprocess
  )
where

import Data.Text (Text)

import JitML.Sub.Subprocess (Subprocess, subprocess)
import JitML.Tart.Lifecycle (VmName (..))

tartExecSubprocess :: VmName -> [Text] -> Subprocess
tartExecSubprocess vmName command =
  subprocess "tart" (["exec", unVmName vmName] <> command)
