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
import System.Directory (createDirectoryIfMissing)
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

materializeBootstrapFiles :: FilePath -> Substrate -> IO ()
materializeBootstrapFiles root substrate = do
    let buildRoot = root </> ".build"
        runtimeRoot = buildRoot </> "runtime"
        clusterConfRoot = buildRoot </> "conf" </> "cluster"
        hostConfRoot = buildRoot </> "conf" </> "host"
    createDirectoryIfMissing True "kind"
    createDirectoryIfMissing True "chart/templates"
    createDirectoryIfMissing True runtimeRoot
    createDirectoryIfMissing True clusterConfRoot
    createDirectoryIfMissing True hostConfRoot
    Text.IO.writeFile ("kind/cluster-" <> Text.unpack (renderSubstrate substrate) <> ".yaml") $
        renderKindConfig (kindConfigFor substrate)
    Text.IO.writeFile "chart/templates/storageclass-jitml-manual.yaml" renderStorageClass
    mapM_ writePv manualPVs
    Text.IO.writeFile "chart/templates/gatewayclass-jitml.yaml" renderGatewayClass
    Text.IO.writeFile "chart/templates/gateway-jitml-edge.yaml" (renderGateway (substrateEdgePort substrate))
    Text.IO.writeFile "chart/templates/envoyproxy-jitml-edge.yaml" renderEnvoyProxy
    mapM_ writeRoute routeRegistry
    Text.IO.writeFile "chart/templates/minio-values.yaml" renderMinioValues
    let clusterBoot = defaultBootConfig substrate Cluster
    Text.IO.writeFile (clusterConfRoot </> Text.unpack (renderSubstrate substrate) <> ".dhall") $
        renderBootConfigDhall clusterBoot
    Text.IO.writeFile (clusterConfRoot </> "LiveConfig.dhall") (renderLiveConfigDhall defaultLiveConfig)
    Text.IO.writeFile "chart/templates/configmap-jitml-service.yaml" $
        renderServiceConfigMap clusterBoot defaultLiveConfig
    Text.IO.writeFile "chart/templates/deployment-jitml-service.yaml" $
        renderServiceDeployment substrate
    case substrate of
        AppleSilicon ->
            Text.IO.writeFile (hostConfRoot </> "apple-silicon.dhall") $
                renderBootConfigDhall (defaultBootConfig AppleSilicon Host)
        _ -> pure ()
    LazyByteString.writeFile (runtimeRoot </> "cluster-publication.json") $
        encode (defaultPublication substrate)
  where
    writePv pv =
        Text.IO.writeFile
            ( "chart/templates/pv-"
                <> Text.unpack (pvNamespace pv)
                <> "-"
                <> Text.unpack (pvStatefulSet pv)
                <> "-"
                <> show (pvReplica pv)
                <> ".yaml"
            )
            (renderManualPV pv)

    writeRoute route =
        Text.IO.writeFile
            ("chart/templates/httproute-" <> Text.unpack (routeName route) <> ".yaml")
            (renderHTTPRoute route)
