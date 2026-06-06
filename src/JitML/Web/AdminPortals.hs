{-# LANGUAGE OverloadedStrings #-}

module JitML.Web.AdminPortals
  ( renderPureScriptAdminPortals
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Routes (Route (..), adminPortalRoutes)

renderPureScriptAdminPortals :: Text
renderPureScriptAdminPortals =
  Text.unlines $
    [ "module Generated.AdminPortals where"
    , ""
    , "type AdminPortal = { name :: String, path :: String, label :: String }"
    , ""
    , "adminPortals :: Array AdminPortal"
    , "adminPortals ="
    ]
      <> portalArrayLines
 where
  portalArrayLines =
    case adminPortalRoutes of
      [] -> ["  []"]
      first : rest ->
        ("  [ " <> renderPortalBody first)
          : fmap (\p -> "  , " <> renderPortalBody p) rest
            <> ["  ]"]

  renderPortalBody (route, label) =
    "{ name: \""
      <> routeName route
      <> "\", path: \""
      <> routePathPrefix route
      <> "\", label: \""
      <> label
      <> "\" }"
