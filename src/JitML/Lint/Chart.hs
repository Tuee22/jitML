{-# LANGUAGE OverloadedStrings #-}

module JitML.Lint.Chart
  ( checkChartFiles
  )
where

import Data.List (isPrefixOf, isSuffixOf)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath ((</>))

import JitML.Cluster.PostgresRegistry
  ( perconaPgVolumeNames
  , postgresRegistry
  , validateRegisteredPostgres
  )
import JitML.Lint.Stack.Types (LintFinding (..))
import JitML.Routes (Route (..), renderHTTPRoute, routeRegistry)

checkChartFiles :: IO [LintFinding]
checkChartFiles = do
  exists <- doesDirectoryExist "chart"
  if exists
    then checkChartWhenPresent
    else pure []

checkChartWhenPresent :: IO [LintFinding]
checkChartWhenPresent = do
  chartFiles <- repoFiles "chart"
  storageFindings <- checkStorageClass
  pvFindings <- concat <$> traverse checkPvFile (filter isPvFile chartFiles)
  forbiddenFindings <- concat <$> traverse checkForbiddenProvisioner chartFiles
  routeFindings <- checkRouteFiles chartFiles
  pgFindings <- concat <$> traverse checkPerconaCluster chartFiles
  let templateValueFindings = fmap templateValuesFinding (filter isTemplateValuesFile chartFiles)
  pure
    ( storageFindings
        <> pvFindings
        <> forbiddenFindings
        <> routeFindings
        <> pgFindings
        <> templateValueFindings
    )

-- | Reject any `PerconaPGCluster` resource not declared in
-- `JitML.Cluster.PostgresRegistry.postgresRegistry`. The registry is the
-- single source for service-Postgres clusters; hand edits in
-- `chart/templates/*.yaml` that introduce new clusters fail the lint.
checkPerconaCluster :: FilePath -> IO [LintFinding]
checkPerconaCluster path
  | ".yaml" `isSuffixOf` path = do
      content <- Text.IO.readFile path
      if "kind: PerconaPGCluster" `Text.isInfixOf` content
        then pure (concatMap (clusterFinding path) (extractClusterNames content))
        else pure []
  | otherwise = pure []
 where
  clusterFinding path' name =
    case validateRegisteredPostgres name of
      Nothing -> []
      Just reason ->
        [ LintFinding
            path'
            "chart.postgres.unregistered"
            reason
            "add the cluster to JitML.Cluster.PostgresRegistry.postgresRegistry"
        ]

  extractClusterNames =
    fmap (Text.strip . Text.drop 6 . Text.dropWhile (/= ':'))
      . filter ("  name:" `Text.isPrefixOf`)
      . Text.lines

checkStorageClass :: IO [LintFinding]
checkStorageClass = do
  let path = "chart/templates/storageclass-jitml-manual.yaml"
  exists <- doesFileExist path
  if exists
    then do
      content <- Text.IO.readFile path
      pure
        [ LintFinding
            path
            "chart.storageclass.provisioner"
            "jitml-manual must use kubernetes.io/no-provisioner"
            "regenerate chart templates with `jitml bootstrap --<substrate>`"
        | not ("provisioner: kubernetes.io/no-provisioner" `Text.isInfixOf` content)
        ]
    else
      pure
        [ LintFinding
            path
            "chart.storageclass.missing"
            "missing jitml-manual StorageClass"
            "run `jitml bootstrap --apple-silicon` to materialize chart templates"
        ]

checkPvFile :: FilePath -> IO [LintFinding]
checkPvFile path = do
  content <- Text.IO.readFile path
  pure $
    [ LintFinding
        path
        "chart.pv.claimref"
        "manual PersistentVolume must declare claimRef unless a registered PerconaPGCluster pins it by volumeName"
        "render PVs from JitML.Cluster.Storage and Percona clusters from JitML.Cluster.PostgresRegistry"
    | not ("claimRef:" `Text.isInfixOf` content)
        && not (pvPinnedByRegisteredPerconaCluster content)
    ]
      <> [ LintFinding
             path
             "chart.pv.hostpath"
             "manual PersistentVolume hostPath must live under /jitml/.data/ inside the Kind node"
             "render PVs from JitML.Cluster.Storage"
         | not ("/jitml/.data/" `Text.isInfixOf` content)
         ]

pvPinnedByRegisteredPerconaCluster :: Text.Text -> Bool
pvPinnedByRegisteredPerconaCluster content =
  any
    ( any
        (\volumeName -> ("  name: " <> volumeName) `Text.isInfixOf` content)
        . perconaPgVolumeNames
    )
    postgresRegistry

checkForbiddenProvisioner :: FilePath -> IO [LintFinding]
checkForbiddenProvisioner path = do
  content <- Text.IO.readFile path
  pure
    [ LintFinding
        path
        "chart.storageclass.forbidden-provisioner"
        "non-manual StorageClass provisioner is forbidden"
        "use the jitml-manual StorageClass only"
    | "kubernetes.io/aws-ebs" `Text.isInfixOf` content
        || "ebs.csi.aws.com" `Text.isInfixOf` content
        || "provisioner: rancher.io/local-path" `Text.isInfixOf` content
    ]

checkRouteFiles :: [FilePath] -> IO [LintFinding]
checkRouteFiles chartFiles = do
  let routeFiles = filter isRouteFile chartFiles
      extraFindings = [extraRouteFinding path | path <- routeFiles, path `notElem` expectedRouteFiles]
  missingFindings <- concat <$> traverse (checkRoutePresent routeFiles) routeRegistry
  driftFindings <- concat <$> traverse checkRouteDrift routeRegistry
  pure (missingFindings <> driftFindings <> extraFindings)

checkRoutePresent :: [FilePath] -> Route -> IO [LintFinding]
checkRoutePresent routeFiles route =
  pure
    [ LintFinding
        (routeFile route)
        "chart.route.missing"
        "generated HTTPRoute manifest is missing"
        "regenerate route manifests from JitML.Routes"
    | routeFile route `notElem` routeFiles
    ]

checkRouteDrift :: Route -> IO [LintFinding]
checkRouteDrift route = do
  let path = routeFile route
  exists <- doesFileExist path
  if exists
    then do
      content <- Text.IO.readFile path
      pure
        [ LintFinding
            path
            "chart.route.drift"
            "HTTPRoute manifest differs from route registry"
            "regenerate route manifests from JitML.Routes"
        | content /= renderHTTPRoute route
        ]
    else pure []

extraRouteFinding :: FilePath -> LintFinding
extraRouteFinding path =
  LintFinding
    path
    "chart.route.extra"
    "HTTPRoute manifest has no route registry entry"
    "delete hand-written HTTPRoute YAML"

expectedRouteFiles :: [FilePath]
expectedRouteFiles = fmap routeFile routeRegistry

routeFile :: Route -> FilePath
routeFile route =
  "chart/templates/httproute-" <> Text.unpack (routeName route) <> ".yaml"

isPvFile :: FilePath -> Bool
isPvFile path =
  "chart/templates/pv-" `isPrefixOf` path && ".yaml" `isSuffixOf` path

isRouteFile :: FilePath -> Bool
isRouteFile path =
  "chart/templates/httproute-" `isPrefixOf` path && ".yaml" `isSuffixOf` path

isTemplateValuesFile :: FilePath -> Bool
isTemplateValuesFile path =
  "chart/templates/" `isPrefixOf` path
    && ("values.yaml" `isSuffixOf` path || "-values.yaml" `isSuffixOf` path)

templateValuesFinding :: FilePath -> LintFinding
templateValuesFinding path =
  LintFinding
    path
    "chart.templates.values-file"
    "chart/templates must contain Kubernetes manifests, not Helm values files"
    "move subchart values under chart/values.yaml or pass a separate values file through a typed Helm subprocess"

repoFiles :: FilePath -> IO [FilePath]
repoFiles = go
 where
  go dir = do
    entries <- listDirectory dir
    paths <- traverse (descend dir) entries
    pure (concat paths)

  descend dir entry = do
    let path = dir </> entry
    isDir <- doesDirectoryExist path
    if isDir
      then go path
      else pure [path]
