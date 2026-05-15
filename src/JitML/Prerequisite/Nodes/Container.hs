{-# LANGUAGE OverloadedStrings #-}

module JitML.Prerequisite.Nodes.Container
  ( containerPrerequisites
  )
where

import JitML.Prerequisite.Nodes.Common
  ( commandPrerequisite
  , homebrewPackagePrerequisite
  , purePrerequisite
  )
import JitML.Prerequisite.Types (NodeId (..), Prerequisite)

containerPrerequisites :: [Prerequisite]
containerPrerequisites =
  [ purePrerequisite
      (NodeId "container")
      "Container prerequisite root."
      [NodeId "container.docker"]
  , purePrerequisite
      (NodeId "container.apple-silicon")
      "Apple Silicon container and VM prerequisite root."
      [ NodeId "container.docker"
      , NodeId "container.colima"
      ]
  , purePrerequisite
      (NodeId "container.apple-silicon.jit-cache-miss")
      "Apple Silicon first JIT cache miss prerequisite root."
      [ NodeId "container.colima"
      , NodeId "container.tart"
      ]
  , commandPrerequisite
      (NodeId "container.docker")
      "Docker CLI is installed."
      "docker"
      "install Docker"
      []
  , homebrewPackagePrerequisite
      (NodeId "container.colima")
      "Colima is installed for Apple Silicon bootstrap."
      "colima"
      "colima"
      []
  , homebrewPackagePrerequisite
      (NodeId "container.tart")
      "Tart is installed for Apple Silicon Metal builds."
      "tart"
      "cirruslabs/cli/tart"
      []
  ]
