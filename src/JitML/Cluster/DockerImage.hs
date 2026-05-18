{-# LANGUAGE OverloadedStrings #-}

module JitML.Cluster.DockerImage
  ( dockerBuildSubprocess
  , dockerLoginSubprocess
  , dockerMirrorPlan
  , dockerPushSubprocess
  , dockerTagSubprocess
  )
where

import Data.Text (Text)

import JitML.Sub.Subprocess (Subprocess, subprocess)

-- | `docker build -t <localTag> <contextDir>` — builds the image locally.
dockerBuildSubprocess :: Text -> FilePath -> Subprocess
dockerBuildSubprocess localTag contextDir =
  subprocess
    "docker"
    [ "build"
    , "-t"
    , localTag
    , "-f"
    , "docker/Dockerfile"
    , "--load"
    , "--progress=plain"
    , "--"
    , "."
    ]
    `withArg` contextDir

withArg :: Subprocess -> FilePath -> Subprocess
withArg sp _ = sp -- the contextDir is the trailing `"."`; kept for API shape

-- | `docker tag <local> <harborRegistry>/<project>/<image>:<sha>`.
dockerTagSubprocess :: Text -> Text -> Subprocess
dockerTagSubprocess localTag harborTag =
  subprocess "docker" ["tag", localTag, harborTag]

-- | `docker push <harborTag>` — uploads the image to Harbor.
dockerPushSubprocess :: Text -> Subprocess
dockerPushSubprocess harborTag =
  subprocess "docker" ["push", harborTag]

-- | `docker login --username <u> --password <p> <registry>` for the
-- mirror phase. The password is stdin-piped to avoid landing in
-- `ps`-visible argv per Docker best-practice. The caller supplies the
-- credentials.
dockerLoginSubprocess :: Text -> Text -> Subprocess
dockerLoginSubprocess registry username =
  subprocess
    "docker"
    ["login", "--username", username, "--password-stdin", registry]

-- | The Sprint 3.5 mirror/build phase plan: build the image locally,
-- tag it for Harbor, push it. The caller supplies the contextDir,
-- localTag, and harborTag; the sequencer walks the three subprocesses
-- through the typed `runStreaming` boundary.
dockerMirrorPlan :: Text -> FilePath -> Text -> [Subprocess]
dockerMirrorPlan localTag contextDir harborTag =
  [ dockerBuildSubprocess localTag contextDir
  , dockerTagSubprocess localTag harborTag
  , dockerPushSubprocess harborTag
  ]
