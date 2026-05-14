{-# LANGUAGE OverloadedStrings #-}

module JitML.Cache.Layout
    ( appleHostDir
    , appleSymlinkPath
    , cachePath
    , cacheRoot
    , cacheSubstrateDir
    , manifestPath
    )
where

import Data.Text qualified as Text
import Path (Abs, Dir, File, Path, Rel, parseRelDir, parseRelFile, (</>))

import JitML.Cache.Key
    ( Extension
    , Hash
    , ModelId (..)
    , Substrate
    , extensionFileSuffix
    , hashHex
    , substrateText
    )

cacheRoot :: Path Abs Dir -> IO (Path Abs Dir)
cacheRoot buildRoot = (buildRoot </>) <$> parseRelDir "jit"

cacheSubstrateDir :: Path Abs Dir -> Substrate -> IO (Path Abs Dir)
cacheSubstrateDir buildRoot substrate = do
    root <- cacheRoot buildRoot
    substrateDir <- parseRelDir (Text.unpack (substrateText substrate))
    pure (root </> substrateDir)

cachePath :: Path Abs Dir -> Substrate -> Hash -> Extension -> IO (Path Abs File)
cachePath buildRoot substrate hash extension = do
    directory <- cacheSubstrateDir buildRoot substrate
    file <- cacheFile hash extension
    pure (directory </> file)

manifestPath :: Path Abs Dir -> IO (Path Abs File)
manifestPath buildRoot = do
    root <- cacheRoot buildRoot
    manifestFile <- parseRelFile "manifest.json"
    pure (root </> manifestFile)

appleHostDir :: Path Abs Dir -> IO (Path Abs Dir)
appleHostDir buildRoot = do
    hostDir <- parseRelDir "host"
    appleDir <- parseRelDir "apple-silicon"
    pure (buildRoot </> hostDir </> appleDir)

appleSymlinkPath :: Path Abs Dir -> ModelId -> Extension -> IO (Path Abs File)
appleSymlinkPath buildRoot (ModelId modelId) extension = do
    directory <- appleHostDir buildRoot
    file <- parseRelFile (Text.unpack (modelId <> extensionFileSuffix extension))
    pure (directory </> file)

cacheFile :: Hash -> Extension -> IO (Path Rel File)
cacheFile hash extension =
    parseRelFile (Text.unpack (hashHex hash <> extensionFileSuffix extension))
