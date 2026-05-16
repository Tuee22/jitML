{-# LANGUAGE OverloadedStrings #-}

module JitML.Bootstrap
  ( bootstrapPlanSteps
  , materializeBootstrapFiles
  )
where

import Data.Aeson (encode)
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import System.Directory (createDirectoryIfMissing, doesFileExist, removeFile, renameFile)
import System.FilePath ((</>))

import JitML.Cluster.Gateway (renderEnvoyProxy, renderGateway, renderGatewayClass)
import JitML.Cluster.Kind (kindConfigFor, renderKindConfig)
import JitML.Cluster.Publication (defaultPublication)
import JitML.Cluster.Storage (ManualPV (..), manualPVs, renderManualPV, renderStorageClass)
import JitML.Routes (Route (..), renderHTTPRoute, routeRegistry)
import JitML.Service.BootConfig (Residency (..), defaultBootConfig, renderBootConfigDhall)
import JitML.Service.ConfigMap (renderServiceConfigMap, renderServiceDeployment)
import JitML.Service.LiveConfig (defaultLiveConfig, renderLiveConfigDhall)
import JitML.Storage.Buckets (renderMinioValues)
import JitML.Substrate (Substrate (..), renderSubstrate, substrateEdgePort)

bootstrapPlanSteps :: Substrate -> [Text]
bootstrapPlanSteps substrate =
  [ "reconcile prerequisite graph for cluster"
  , "render kind/cluster-" <> renderSubstrate substrate <> ".yaml"
  , "create Kind cluster with ./.build/jitml.kubeconfig"
  , "apply jitml-manual StorageClass and manual PVs"
  , "install Harbor bootstrap phase"
  , "push jitml:local into Harbor"
  , "install MinIO, Pulsar, Envoy Gateway, observability, jitml-service, jitml-demo"
  , "write ./.build/runtime/cluster-publication.json"
  ]

materializeBootstrapFiles :: FilePath -> Substrate -> IO Bool
materializeBootstrapFiles root substrate = do
  let buildRoot = root </> ".build"
      runtimeRoot = buildRoot </> "runtime"
      clusterConfRoot = buildRoot </> "conf" </> "cluster"
      hostConfRoot = buildRoot </> "conf" </> "host"
      kindRoot = root </> "kind"
      chartRoot = root </> "chart"
      chartTemplatesRoot = chartRoot </> "templates"
  createDirectoryIfMissing True kindRoot
  createDirectoryIfMissing True chartRoot
  createDirectoryIfMissing True chartTemplatesRoot
  createDirectoryIfMissing True runtimeRoot
  createDirectoryIfMissing True clusterConfRoot
  createDirectoryIfMissing True hostConfRoot
  results <-
    sequence
      [ writeTextFileIfChanged
          (kindRoot </> "cluster-" <> Text.unpack (renderSubstrate substrate) <> ".yaml")
          (renderKindConfig (kindConfigFor substrate))
      , writeTextFileIfChanged (chartTemplatesRoot </> "storageclass-jitml-manual.yaml") renderStorageClass
      , writeTextFileIfChanged (chartTemplatesRoot </> "gatewayclass-jitml.yaml") renderGatewayClass
      , writeTextFileIfChanged
          (chartTemplatesRoot </> "gateway-jitml-edge.yaml")
          (renderGateway (substrateEdgePort substrate))
      , writeTextFileIfChanged (chartTemplatesRoot </> "envoyproxy-jitml-edge.yaml") renderEnvoyProxy
      , writeTextFileIfChanged (chartRoot </> "minio-values.yaml") renderMinioValues
      ]
  pvResults <- traverse (writePv chartTemplatesRoot) manualPVs
  routeResults <- traverse (writeRoute chartTemplatesRoot) routeRegistry
  legacyValuesChanged <- removeFileIfExists (chartTemplatesRoot </> "minio-values.yaml")
  let clusterBoot = defaultBootConfig substrate Cluster
  configResults <-
    sequence
      [ writeTextFileIfChanged
          (clusterConfRoot </> Text.unpack (renderSubstrate substrate) <> ".dhall")
          (renderBootConfigDhall clusterBoot)
      , writeTextFileIfChanged
          (clusterConfRoot </> "LiveConfig.dhall")
          (renderLiveConfigDhall defaultLiveConfig)
      , writeTextFileIfChanged (chartTemplatesRoot </> "configmap-jitml-service.yaml") $
          renderServiceConfigMap clusterBoot defaultLiveConfig
      , writeTextFileIfChanged (chartTemplatesRoot </> "deployment-jitml-service.yaml") $
          renderServiceDeployment substrate
      ]
  hostResults <- case substrate of
    AppleSilicon ->
      fmap (: []) $
        writeTextFileIfChanged (hostConfRoot </> "apple-silicon.dhall") $
          renderBootConfigDhall (defaultBootConfig AppleSilicon Host)
    _ -> pure []
  publicationChanged <-
    writeLazyByteStringIfChanged (runtimeRoot </> "cluster-publication.json") $
      encode (defaultPublication substrate)
  pure
    ( or
        ( results
            <> pvResults
            <> routeResults
            <> configResults
            <> hostResults
            <> [publicationChanged, legacyValuesChanged]
        )
    )
 where
  writePv chartTemplatesRoot pv =
    writeTextFileIfChanged
      ( chartTemplatesRoot
          </> ( "pv-"
                  <> Text.unpack (pvNamespace pv)
                  <> "-"
                  <> Text.unpack (pvStatefulSet pv)
                  <> "-"
                  <> show (pvReplica pv)
                  <> ".yaml"
              )
      )
      (renderManualPV pv)

  writeRoute chartTemplatesRoot route =
    writeTextFileIfChanged
      (chartTemplatesRoot </> ("httproute-" <> Text.unpack (routeName route) <> ".yaml"))
      (renderHTTPRoute route)

writeTextFileIfChanged :: FilePath -> Text -> IO Bool
writeTextFileIfChanged path expected = do
  exists <- doesFileExist path
  current <-
    if exists
      then Text.IO.readFile path
      else pure ""
  if current == expected
    then pure False
    else do
      let tmpPath = path <> ".tmp"
      Text.IO.writeFile tmpPath expected
      renameFile tmpPath path
      pure True

writeLazyByteStringIfChanged :: FilePath -> LazyByteString.ByteString -> IO Bool
writeLazyByteStringIfChanged path expected = do
  exists <- doesFileExist path
  current <-
    if exists
      then LazyByteString.readFile path
      else pure ""
  if current == expected
    then pure False
    else do
      let tmpPath = path <> ".tmp"
      LazyByteString.writeFile tmpPath expected
      renameFile tmpPath path
      pure True

removeFileIfExists :: FilePath -> IO Bool
removeFileIfExists path = do
  exists <- doesFileExist path
  if exists
    then do
      removeFile path
      pure True
    else pure False
