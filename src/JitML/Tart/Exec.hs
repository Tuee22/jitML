{-# LANGUAGE OverloadedStrings #-}

-- | Render a @tart exec@ subprocess that runs a command inside the named build
-- VM (reinstated 2026-06-10, Phase 2 Sprint 2.11).
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
