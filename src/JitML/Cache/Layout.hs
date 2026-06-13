{-# LANGUAGE OverloadedStrings #-}

module JitML.Cache.Layout
  ( appleHostDir
  , appleMetalMetadataPath
  , cachePath
  , cacheRoot
  , cacheSubstrateDir
  , manifestPath
  )
where

import Data.Text qualified as Text
import Path (Abs, Dir, File, Path, Rel, parseRelDir, parseRelFile, (</>))

import JitML.Cache.Key
  ( Extension (Extension)
  , Hash
  , Substrate (AppleSilicon)
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

appleMetalMetadataPath :: Path Abs Dir -> Hash -> IO (Path Abs File)
appleMetalMetadataPath buildRoot hash =
  cachePath buildRoot AppleSilicon hash (Extension "metal.json")

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

cacheFile :: Hash -> Extension -> IO (Path Rel File)
cacheFile hash extension =
  parseRelFile (Text.unpack (hashHex hash <> extensionFileSuffix extension))
