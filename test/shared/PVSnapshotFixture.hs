{-# LANGUAGE OverloadedStrings #-}

-- Deliberately authored ordinary filesystem metadata. No incident/run payload,
-- live PV, tar, qualification or user data is embedded in these test fixtures.
module PVSnapshotFixture (sourceManifest, restoredManifest) where

import Crypto.Hash.SHA256 qualified as SHA
import Data.Aeson (Value, encode, object, (.=))
import Data.Aeson.Types (Pair)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.List (sort, sortOn)
import Data.Text (Text)
import Data.Text qualified as Text
import Numeric (showHex)

sourceManifest, restoredManifest :: ByteString
sourceManifest = manifest False
restoredManifest = manifest True

manifest :: Bool -> ByteString
manifest restored =
  LBS.toStrict $
    encode $
      object
        [ "format" .= ("quiesced-tree-manifest-v1" :: Text)
        , "root" .= (if restored then "/restore" else "/nodevar/local/jitml-stateful-pv" :: Text)
        , "completed" .= True
        , "records" .= fmap snd (sortOn fst rows)
        , "hardlink_groups" .= [sort [filePath, hardlinkPath]]
        , "unsupported_restore_types" .= ([] :: [Text])
        ]
 where
  directories =
    [".", "jitml", "jitml/.data", "jitml/.data/platform"]
      <> concatMap
        (\name -> [prefix <> name, prefix <> name <> "/pv_0"])
        ["minio", "pulsar-bookie-journal", "pulsar-bookie-ledgers", "pulsar-zookeeper-data"]
  prefix = "jitml/.data/platform/"
  filePath = prefix <> "minio/pv_0/object.bin"
  hardlinkPath = prefix <> "minio/pv_0/object-copy.bin"
  parentOf path =
    let (parent, _) = Text.breakOnEnd "/" path
     in if Text.null parent then "." else Text.dropEnd 1 parent
  linksFor path = 2 + toInteger (length [child | child <- directories, child /= ".", parentOf child == path])
  rows =
    zipWith
      (\path index -> (path, row path "directory" index 493 4096 (linksFor path) []))
      directories
      [1 ..]
      <> [ (filePath, row filePath "file" 100 420 7 2 ["sha256" .= payloadSHA])
         , (hardlinkPath, row hardlinkPath "file" 100 420 7 2 ["sha256" .= payloadSHA])
         ,
           ( prefix <> "minio/pv_0/object-symlink"
           , row
               (prefix <> "minio/pv_0/object-symlink")
               "symlink"
               101
               511
               10
               1
               ["link_target" .= ("object.bin" :: Text)]
           )
         ]
  row :: Text -> Text -> Integer -> Integer -> Integer -> Integer -> [Pair] -> Value
  row path kind inode mode size links extra =
    object $
      [ "path" .= path
      , "type" .= kind
      , "mode" .= mode
      , "uid" .= (1000 :: Integer)
      , "gid" .= (1000 :: Integer)
      , "nlink" .= links
      , "size" .= (if restored && kind == "directory" then 16384 else size)
      , "mtime_ns" .= (1700000000123456789 :: Integer)
      , "rdev" .= (0 :: Integer)
      , "identity"
          .= object
            [ "device" .= (if restored then 22 else 11 :: Integer)
            , "inode" .= (if restored then inode + 10000 else inode)
            , "ctime_ns" .= (if restored then 1700000000999999999 else 1700000000222222222 :: Integer)
            ]
      , "xattrs_base64" .= object ["user.jitml-fixture" .= ("Zml4dHVyZQ==" :: Text)]
      ]
        <> extra

payloadSHA :: Text
payloadSHA =
  Text.pack $
    concatMap
      (\octet -> let hex = showHex octet "" in if length hex == 1 then '0' : hex else hex)
      (BS.unpack (SHA.hash "fixture"))
