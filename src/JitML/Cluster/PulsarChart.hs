{-# LANGUAGE OverloadedStrings #-}

-- | Deliberate corrections of the pinned Pulsar 3.6.0 startup templates.
-- The upstream template exports BOOKIE_MEM before invoking @bin/pulsar
-- zookeeper-shell@, whose launcher uses PULSAR_MEM. Without that setting the
-- Pulsar 3.0.7 image selects a 2 GiB initial heap inside the 512 MiB init limit.
-- Correct only the equal-length variable name, retaining both upstream guards,
-- deadlines, images, TLS settings, metadata paths, and every other tar byte.
-- Separately redirect the four StatefulSets' init resource references to the
-- selected supporting budget. Initialization Job templates remain unchanged:
-- their completed immutable templates must survive retained-cluster upgrades.
--
-- The original archive is authenticated by the SHA256 published for version
-- 3.6.0 in https://pulsar.apache.org/charts/index.yaml. Its public template is
-- https://github.com/apache/pulsar-helm-chart/blob/pulsar-3.6.0/charts/pulsar/templates/broker-statefulset.yaml.
-- A changed dependency refuses preparation; there is no unpatched fallback.
module JitML.Cluster.PulsarChart
  ( preparePulsarChart
  , preparePulsarChartArchive
  , preparedPulsarChartPath
  , patchPulsarChartTar
  , patchPulsarStatefulInitTar
  )
where

import Codec.Compression.GZip qualified as GZip
import Control.Exception (evaluate)
import Control.Exception.Safe (bracketOnError, displayException, tryAny)
import Control.Monad (unless, void, when)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word8)
import System.Directory (createDirectory, doesPathExist, removeFile, renameFile)
import System.FilePath (takeDirectory, (</>))
import System.IO (IOMode (ReadMode), hClose, hFlush, openBinaryTempFile, withBinaryFile)
import System.Posix.Files (fileSize, getSymbolicLinkStatus, isDirectory, isRegularFile)

preparedPulsarChartPath :: FilePath
preparedPulsarChartPath = ".build/conf/cluster/charts/pulsar-3.6.0.tgz"

originalArchiveBytes :: Int
originalArchiveBytes = 560310

originalArchiveSHA256 :: Text
originalArchiveSHA256 = "fb4da72fa8ad6a2e41cc406b0d65659369f5ad5892a733aa0dcbb3525c11d32f"

maximumTarBytes :: Int
maximumTarBytes = 16 * 1024 * 1024

-- | Prepare a separate ignored chart after dependency download/cache discovery.
-- The public upstream archive is read-only; a private temporary file and rename
-- publish the corrected copy only after all authentication and patch checks.
preparePulsarChart :: FilePath -> IO (Either Text ())
preparePulsarChart chartRoot = catchingPreparation $ do
  let source = chartRoot </> "charts/pulsar-3.6.0.tgz"
      destination = preparedPulsarChartPath
      directory = takeDirectory destination
  physicalDirectory False (takeDirectory source)
  status <- getSymbolicLinkStatus source
  unless (isRegularFile status && fileSize status == fromIntegral originalArchiveBytes) $
    ioError (userError "pinned Pulsar chart must be a physical regular file of the expected size")
  original <-
    withBinaryFile source ReadMode (\handle -> ByteString.hGet handle (originalArchiveBytes + 1))
  corrected <- preparePulsarChartArchive original
  case corrected of
    Left reason -> pure (Left reason)
    Right bytes -> do
      physicalDirectory True directory
      bracketOnError
        (openBinaryTempFile directory "pulsar-3.6.0.tgz.tmp")
        (\(path, handle) -> void (tryAny (hClose handle)) >> void (tryAny (removeFile path)))
        ( \(path, handle) -> do
            ByteString.hPut handle bytes
            hFlush handle
            hClose handle
            renameFile path destination
        )
      pure (Right ())

-- | Authenticate before decoding and bound inflated bytes before collecting
-- them. Forcing both strict results here catches lazy gzip/CRC exceptions.
-- GZip.compress is pure and emits the same gzip bytes for the same tar bytes.
preparePulsarChartArchive :: ByteString -> IO (Either Text ByteString)
preparePulsarChartArchive original =
  catchingPreparation $
    if ByteString.length original /= originalArchiveBytes
      then pure (Left "pinned Pulsar chart archive size differs")
      else
        if sha256Hex original /= originalArchiveSHA256
          then pure (Left "pinned Pulsar chart archive SHA256 differs")
          else do
            inflated <-
              forceBytes $
                LazyByteString.toStrict $
                  LazyByteString.take (fromIntegral maximumTarBytes + 1) $
                    GZip.decompress (LazyByteString.fromStrict original)
            case patchPulsarChartTar inflated >>= patchPulsarStatefulInitTar of
              Left reason -> pure (Left reason)
              Right patched -> do
                compressed <-
                  forceBytes (LazyByteString.toStrict (GZip.compress (LazyByteString.fromStrict patched)))
                pure (Right compressed)

-- | The authenticated tar needs no extraction or repacking. Equal-length
-- content substitution preserves every tar header, file size, and checksum.
-- This pure helper also refuses missing, changed, and duplicated contexts.
patchPulsarChartTar :: ByteString -> Either Text ByteString
patchPulsarChartTar original
  | ByteString.length original > maximumTarBytes =
      Left "pinned Pulsar chart exceeds its inflated byte limit"
  | ByteString.null targetAndRest = Left "pinned Pulsar broker ZooKeeper wait context differs"
  | waitContext `ByteString.isInfixOf` rest =
      Left "pinned Pulsar broker ZooKeeper wait context is not unique"
  | otherwise = Right (before <> correctedContext <> rest)
 where
  (before, targetAndRest) = ByteString.breakSubstring waitContext original
  rest = ByteString.drop (ByteString.length waitContext) targetAndRest
  correctedContext =
    "export PULSAR_MEM"
      <> ByteString.drop (ByteString.length ("export BOOKIE_MEM" :: ByteString)) waitContext

-- | Scope six equal-length substitutions to four authenticated tar entries.
-- Preserve all headers, padding and other payloads, especially initialization
-- Jobs. The supporting resource overlay is present on every supported Helm path.
patchPulsarStatefulInitTar :: ByteString -> Either Text ByteString
patchPulsarStatefulInitTar original
  | ByteString.length original > maximumTarBytes =
      Left "pinned Pulsar chart exceeds its inflated byte limit"
  | otherwise = go statefulTemplates original []
 where
  go pending bytes chunks
    | ByteString.length bytes < 512 = Left "pinned Pulsar tar is truncated"
    | ByteString.all (== 0) header =
        if not (null pending)
          then Left "pinned Pulsar StatefulSet resource template is missing"
          else
            if ByteString.all (== 0) bytes
              then Right (ByteString.concat (reverse (bytes : chunks)))
              else Left "pinned Pulsar tar has data after its terminator"
    | otherwise = do
        size <- tarSize (ByteString.take 12 (ByteString.drop 124 header))
        let padded = ((size + 511) `div` 512) * 512
            payload = ByteString.take size (ByteString.drop 512 bytes)
            padding = ByteString.take (padded - size) (ByteString.drop (512 + size) bytes)
            name = ByteString.takeWhile (/= 0) (ByteString.take 100 header)
        unless
          (512 + padded <= ByteString.length bytes)
          (Left "pinned Pulsar tar payload is truncated")
        (remaining, updated) <- case lookup name pending of
          Just count -> do
            unless
              (ByteString.index header 156 `elem` [0, 48])
              (Left "pinned Pulsar StatefulSet template is not a regular file")
            unless
              (ByteString.all (== 0) (ByteString.take 155 (ByteString.drop 345 header)))
              (Left "pinned Pulsar StatefulSet tar path prefix differs")
            replacement <- replaceReferences count payload
            pure (filter ((/= name) . fst) pending, replacement)
          Nothing ->
            if name `elem` fmap fst statefulTemplates
              then Left "pinned Pulsar StatefulSet resource template is duplicated"
              else Right (pending, payload)
        go remaining (ByteString.drop (512 + padded) bytes) ((header <> updated <> padding) : chunks)
   where
    header = ByteString.take 512 bytes

  tarSize field =
    let digits = ByteString.takeWhile (\byte -> byte /= 0 && byte /= 32) (ByteString.dropWhile (== 32) field)
        value = ByteString.foldl' (\total byte -> total * 8 + fromIntegral (byte - 48)) 0 digits
     in if ByteString.null digits || not (ByteString.all (\byte -> byte >= 48 && byte <= 55) digits)
          then Left "pinned Pulsar tar size is not octal"
          else
            if value > maximumTarBytes
              then Left "pinned Pulsar tar entry exceeds its inflated byte limit"
              else Right value

  replaceReferences count bytes =
    let (before, target) = ByteString.breakSubstring initResourceReference bytes
     in if count == 0
          then
            if ByteString.null target
              then Right bytes
              else Left "pinned Pulsar StatefulSet has extra init resource references"
          else
            if ByteString.null target
              then Left "pinned Pulsar StatefulSet init resource context differs"
              else do
                rest <-
                  replaceReferences (count - 1) (ByteString.drop (ByteString.length initResourceReference) target)
                pure (before <> ".Values.statefulInit.resources " <> rest)

statefulTemplates :: [(ByteString, Int)]
statefulTemplates =
  [ ("pulsar/templates/autorecovery-statefulset.yaml", 1)
  , ("pulsar/templates/bookkeeper-statefulset.yaml", 1)
  , ("pulsar/templates/broker-statefulset.yaml", 2)
  , ("pulsar/templates/proxy-statefulset.yaml", 2)
  ]

initResourceReference :: ByteString
initResourceReference = ".Values.initContainer.resources"

waitContext :: ByteString
waitContext =
  "export BOOKIE_MEM=\"-Xmx128M\";\n"
    <> "            {{- if .Values.pulsar_metadata.configurationStore }}\n"
    <> "            until timeout 15 bin/pulsar zookeeper-shell -server "

forceBytes :: ByteString -> IO ByteString
forceBytes bytes = evaluate (ByteString.length bytes) >> pure bytes

catchingPreparation :: IO (Either Text a) -> IO (Either Text a)
catchingPreparation action = do
  result <- tryAny action
  pure $ case result of
    Left failure -> Left ("Pulsar chart preparation failed: " <> Text.pack (displayException failure))
    Right value -> value

-- Refuse symbolic links in existing cache/output directory components.
physicalDirectory :: Bool -> FilePath -> IO ()
physicalDirectory create path = do
  let parent = takeDirectory path
  when (parent /= path) (physicalDirectory create parent)
  present <- doesPathExist path
  when (create && not present) (createDirectory path)
  status <- getSymbolicLinkStatus path
  unless
    (isDirectory status)
    (ioError (userError "Pulsar chart preparation requires physical directories"))

sha256Hex :: ByteString -> Text
sha256Hex = Text.pack . concatMap byteHex . ByteString.unpack . SHA256.hash
 where
  byteHex :: Word8 -> String
  byteHex byte =
    let digits = "0123456789abcdef"
        high = fromIntegral byte `div` 16
        low = fromIntegral byte `mod` 16
     in [digits !! high, digits !! low]
