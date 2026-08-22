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

-- | `docker tag <local> <imageRegistry>/<project>/<image>:<sha>`.
dockerTagSubprocess :: Text -> Text -> Subprocess
dockerTagSubprocess localTag registryTag =
  subprocess "docker" ["tag", localTag, registryTag]

-- | `docker push <registryTag>` — uploads the image to the registry.
dockerPushSubprocess :: Text -> Subprocess
dockerPushSubprocess registryTag =
  subprocess "docker" ["push", registryTag]

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
-- resolving an in-cluster registry DNS name during local bootstrap.
dockerBuildAndKindLoadPlan :: Substrate -> Text -> FilePath -> [Subprocess]
dockerBuildAndKindLoadPlan substrate localTag contextDir =
  [ dockerBuildSubprocess localTag contextDir
  , kindLoadDockerImageSubprocess substrate localTag
  ]

-- | Registry mirror/build phase plan: build the image locally,
-- tag it for the registry, push it. The caller supplies the contextDir,
-- localTag, and registryTag; the sequencer walks the three subprocesses
-- through the typed `runStreaming` boundary.
dockerMirrorPlan :: Text -> FilePath -> Text -> [Subprocess]
dockerMirrorPlan localTag contextDir registryTag =
  [ dockerBuildSubprocess localTag contextDir
  , dockerTagSubprocess localTag registryTag
  , dockerPushSubprocess registryTag
  ]
