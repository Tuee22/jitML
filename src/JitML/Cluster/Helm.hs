{-# LANGUAGE OverloadedStrings #-}

module JitML.Cluster.Helm
  ( HelmPhase (..)
  , HelmRelease (..)
  , helmDependencyBuildSubprocess
  , helmInstallSubprocess
  , helmInstallSubprocessForEdgePort
  , helmInstallSubprocessForSubstrate
  , helmPhasedRolloutPlan
  , kindCreateSubprocess
  , kindDeleteSubprocess
  , phasedReleases
  , renderHelmDependencyBuildPlan
  , renderHelmPhasedRolloutPlan
  )
where

import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import System.FilePath ((</>))

import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Subprocess (Subprocess, subprocess)
import JitML.Substrate (Substrate, renderSubstrate, substrateEdgePort)

helmDependencyBuildSubprocess :: FilePath -> Subprocess
helmDependencyBuildSubprocess chartPath =
  subprocess
    "sh"
    [ "-c"
    , Text.unwords
        [ "if"
        , Text.intercalate " && " (fmap (packageExists chartPath) dependencyPackages)
        , "; then exit 0;"
        , "fi;"
        , "helm dependency build"
        , Text.pack chartPath
        ]
    ]

renderHelmDependencyBuildPlan :: FilePath -> Text
renderHelmDependencyBuildPlan chartPath =
  "helm dependency build " <> Text.pack chartPath

-- | Helm releases in the cluster reconciler. `JitML.Bootstrap` inserts the
-- non-Helm Docker build / Kind image-load phase between Harbor and the final
-- workload releases.
data HelmPhase
  = HarborPhase
  | PlatformPhase
  | FinalPhase
  deriving stock (Eq, Show)

data HelmRelease = HelmRelease
  { releaseName :: Text
  , releaseChart :: Text
  , releasePhase :: HelmPhase
  , releasePackage :: Maybe Text
  , releaseValuesFile :: Maybe FilePath
  }
  deriving stock (Eq, Show)

phasedReleases :: [HelmRelease]
phasedReleases =
  [ HelmRelease "harbor-pg" "pg-operator" HarborPhase (Just "pg-operator-2.5.1.tgz") Nothing
  , HelmRelease "minio" "minio" HarborPhase (Just "minio-14.8.5.tgz") (Just "values/minio.yaml")
  , HelmRelease "harbor" "harbor" HarborPhase (Just "harbor-1.16.2.tgz") (Just "values/harbor.yaml")
  , HelmRelease "pulsar" "pulsar" PlatformPhase (Just "pulsar-3.6.0.tgz") (Just "values/pulsar.yaml")
  , HelmRelease
      "kube-prometheus-stack"
      "kube-prometheus-stack"
      PlatformPhase
      (Just "kube-prometheus-stack-70.4.2.tgz")
      (Just "values/kube-prometheus-stack.yaml")
  , HelmRelease "tensorboard" "tensorboard" PlatformPhase Nothing Nothing
  , HelmRelease "jitml-service" "jitml-service" FinalPhase Nothing Nothing
  , HelmRelease "jitml-demo" "jitml-demo" FinalPhase Nothing Nothing
  , HelmRelease "envoy-gateway" "gateway-helm" FinalPhase (Just "gateway-helm-1.2.6.tgz") Nothing
  ]

dependencyPackages :: [Text]
dependencyPackages =
  mapMaybe releasePackage phasedReleases

packageExists :: FilePath -> Text -> Text
packageExists chartPath package =
  "test -f " <> Text.pack chartPath <> "/charts/" <> package

helmInstallSubprocess :: HelmRelease -> FilePath -> Subprocess
helmInstallSubprocess =
  helmInstallSubprocessWith []

helmInstallSubprocessForSubstrate :: Substrate -> HelmRelease -> FilePath -> Subprocess
helmInstallSubprocessForSubstrate substrate =
  helmInstallSubprocessForEdgePort substrate (substrateEdgePort substrate)

helmInstallSubprocessForEdgePort :: Substrate -> Int -> HelmRelease -> FilePath -> Subprocess
helmInstallSubprocessForEdgePort substrate edgePort release =
  helmInstallSubprocessWith
    ( [ "--set"
      , "substrate=" <> renderSubstrate substrate
      , "--set"
      , "edgePort=" <> Text.pack (show edgePort)
      ]
        <> harborEdgeArgs edgePort release
    )
    release

helmInstallSubprocessWith :: [Text] -> HelmRelease -> FilePath -> Subprocess
helmInstallSubprocessWith extraArgs release chartPath =
  subprocess
    "helm"
    ( [ "upgrade"
      , "--install"
      , releaseName release
      , chartReference release chartPath
      , "--namespace"
      , "platform"
      , "--create-namespace"
      , "--wait"
      , "--kubeconfig"
      , "./.build/jitml.kubeconfig"
      ]
        <> valuesArgs release chartPath
        <> extraArgs
    )

chartReference :: HelmRelease -> FilePath -> Text
chartReference release chartPath =
  case releasePackage release of
    Just package -> Text.pack chartPath <> "/charts/" <> package
    Nothing -> Text.pack chartPath <> "/local/" <> releaseChart release

valuesArgs :: HelmRelease -> FilePath -> [Text]
valuesArgs release chartPath =
  case releaseValuesFile release of
    Just valuesFile -> ["--values", Text.pack (chartPath </> valuesFile)]
    Nothing -> []

harborEdgeArgs :: Int -> HelmRelease -> [Text]
harborEdgeArgs edgePort release
  | releaseName release == "harbor" =
      [ "--set"
      , "expose.type=clusterIP"
      , "--set"
      , "expose.tls.enabled=false"
      , "--set-string"
      , "externalURL=http://127.0.0.1:" <> Text.pack (show edgePort)
      ]
  | otherwise = []

helmPhasedRolloutPlan :: FilePath -> [Subprocess]
helmPhasedRolloutPlan chartPath =
  helmDependencyBuildSubprocess chartPath
    : [helmInstallSubprocess release chartPath | release <- phasedReleases]

renderHelmPhasedRolloutPlan :: FilePath -> Text
renderHelmPhasedRolloutPlan chartPath =
  Text.unlines (fmap renderSubprocess (helmPhasedRolloutPlan chartPath))

kindCreateSubprocess :: Substrate -> FilePath -> Subprocess
kindCreateSubprocess substrate kindConfigPath =
  subprocess
    "sh"
    [ "-c"
    , Text.unwords
        [ "tmpKubeconfig=/tmp/"
            <> clusterName
            <> ".kubeconfig;"
        , "rm -f \"$tmpKubeconfig\" \"$tmpKubeconfig.lock\";"
        , "if kind get clusters | grep -Fx"
        , clusterName
        , ">/dev/null;"
        , "then kind export kubeconfig --name"
        , clusterName
        , "--kubeconfig \"$tmpKubeconfig\";"
        , "else kind create cluster --name"
        , clusterName
        , "--config"
        , Text.pack kindConfigPath
        , "--kubeconfig \"$tmpKubeconfig\";"
        , "fi;"
        , "mkdir -p ./.build;"
        , "cp \"$tmpKubeconfig\" ./.build/jitml.kubeconfig;"
        , "rm -f \"$tmpKubeconfig\" \"$tmpKubeconfig.lock\""
        ]
    ]
 where
  clusterName = "jitml-" <> renderSubstrate substrate

kindDeleteSubprocess :: Substrate -> Subprocess
kindDeleteSubprocess substrate =
  subprocess
    "sh"
    [ "-c"
    , Text.unwords
        [ "if kind get clusters | grep -Fx"
        , clusterName
        , ">/dev/null;"
        , "then kind delete cluster --name"
        , clusterName
        , ";"
        , "else exit 3;"
        , "fi"
        ]
    ]
 where
  clusterName = "jitml-" <> renderSubstrate substrate
