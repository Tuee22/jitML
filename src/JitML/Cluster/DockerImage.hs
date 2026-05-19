{-# LANGUAGE OverloadedStrings #-}

module JitML.Cluster.DockerImage
  ( dockerBuildAndKindLoadPlan
  , dockerBuildSubprocess
  , dockerLoginSubprocess
  , dockerMirrorPlan
  , dockerPushSubprocess
  , dockerTagSubprocess
  , kindLoadDockerImageSubprocess
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import System.FilePath ((</>))

import JitML.Sub.Subprocess (Subprocess, subprocess)
import JitML.Substrate (Substrate, renderSubstrate)

-- | `docker build -t <localTag> <contextDir>` — builds the image locally.
dockerBuildSubprocess :: Text -> FilePath -> Subprocess
dockerBuildSubprocess localTag contextDir =
  subprocess
    "docker"
    [ "build"
    , "-t"
    , localTag
    , "-f"
    , Text.pack (contextDir </> "docker" </> "Dockerfile")
    , Text.pack contextDir
    ]

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

-- | `kind load docker-image <tag> --name jitml-<substrate>` — loads a
-- locally built image into the local Kind cluster's container runtime.
kindLoadDockerImageSubprocess :: Substrate -> Text -> Subprocess
kindLoadDockerImageSubprocess substrate localTag =
  subprocess
    "kind"
    [ "load"
    , "docker-image"
    , localTag
    , "--name"
    , "jitml-" <> renderSubstrate substrate
    ]

-- | Phase 3 local live path: build the image locally, then load it into
-- Kind explicitly. This avoids relying on host Docker or Kind containerd
-- resolving an in-cluster Harbor DNS name during local bootstrap.
dockerBuildAndKindLoadPlan :: Substrate -> Text -> FilePath -> [Subprocess]
dockerBuildAndKindLoadPlan substrate localTag contextDir =
  [ dockerBuildSubprocess localTag contextDir
  , kindLoadDockerImageSubprocess substrate localTag
  ]

-- | Harbor mirror/build phase plan: build the image locally,
-- tag it for Harbor, push it. The caller supplies the contextDir,
-- localTag, and harborTag; the sequencer walks the three subprocesses
-- through the typed `runStreaming` boundary.
dockerMirrorPlan :: Text -> FilePath -> Text -> [Subprocess]
dockerMirrorPlan localTag contextDir harborTag =
  [ dockerBuildSubprocess localTag contextDir
  , dockerTagSubprocess localTag harborTag
  , dockerPushSubprocess harborTag
  ]
