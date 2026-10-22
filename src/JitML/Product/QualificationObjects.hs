{-# LANGUAGE OverloadedStrings #-}

-- | Read a lane journal's explicitly named portable qualification objects.
-- Object names never become filesystem paths: only a checked lowercase SHA256
-- basename is read below the journal's sibling object directory. Bytes are
-- captured once and returned for the pinned production admission boundary.
module JitML.Product.QualificationObjects
  ( readProductLaneQualificationObjects
  )
where

import Control.Exception (IOException, try)
import Control.Monad (when)
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.Char (isControl)
import Data.List qualified as List
import Data.Text (Text)
import Data.Text qualified as Text
import System.FilePath ((</>))
import System.Posix.Files (fileSize, getSymbolicLinkStatus)

import JitML.Product.ValidationRecord (sha256Hex)
import JitML.Test.NativeLaneBundle qualified as Native
import JitML.Test.ProductLaneJournal qualified as Lane

-- | A successful read is not admission or producer authentication. The exact
-- captured journal and explicit object map must subsequently be supplied to
-- 'Lane.admitProductLaneJournalWithQualifications'. Missing files retain their
-- actual path in the existing typed I/O error; malformed bytes never fall back
-- to an empty map or a legacy reader.
readProductLaneQualificationObjects
  :: FilePath
  -> ByteString
  -> IO (Either Lane.ProductLaneJournalError [(Text, ByteString)])
readProductLaneQualificationObjects journalPath journalBytes =
  case Lane.productLaneJournalQualificationObjectKeys journalBytes of
    Left err -> pure (Left err)
    Right keys
      | length keys /= length (List.nub keys) ->
          pure (Left (Lane.ProductLaneJournalMalformed "qualification object keys are duplicated"))
      | otherwise -> do
          captured <- traverse readObject keys
          pure (sequence captured)
 where
  readObject key =
    case objectSha key of
      Left err -> pure (Left err)
      Right sha -> do
        let path = (journalPath <> ".qualifications") </> (Text.unpack sha <> ".cbor")
        readResult <-
          try
            ( if Text.isPrefixOf "jitml-checkpoints/native-lane-bundles-v1/" key
                then do
                  let prefix = take 4097 path
                  when
                    (length prefix > 4096)
                    (ioError (userError "native portable root path exceeds its character cap"))
                  status <- getSymbolicLinkStatus prefix
                  -- The shared reader checks every real nonlink prefix before
                  -- opening. Stat-derived count is not a journal/reference claim;
                  -- exact declared count is checked again by native admission.
                  let count = toInteger (fileSize status)
                  if count < 0 || count > Native.maximumNativeBundleRootBytes
                    then ioError (userError "native portable root exceeds1MiB")
                    else
                      Native.readNativeBundleObjectBytes
                        (journalPath <> ".qualifications")
                        (Native.NativeBundleObjectData key sha (fromInteger count))
                        Native.maximumNativeBundleRootBytes
                else ByteString.readFile path
            )
            :: IO (Either IOException ByteString)
        pure $
          case readResult of
            Left exception -> Left (Lane.ProductLaneJournalIOFailure path (Text.pack (show exception)))
            Right bytes
              | sha256Hex bytes == sha -> Right (key, bytes)
              | otherwise ->
                  Left
                    ( Lane.ProductLaneJournalMalformed
                        ("qualification object bytes at " <> Text.pack path <> " differ from their canonical SHA256 filename")
                    )

-- The journal extractor already requires canonical wire keys. Check the exact
-- shape again at this filesystem boundary so a future extractor change cannot
-- accidentally turn a path component into authority to read arbitrary files.
objectSha :: Text -> Either Lane.ProductLaneJournalError Text
objectSha key =
  case Text.splitOn "/" key of
    ["jitml-checkpoints", "native-lane-bundles-v1", filename] ->
      case Text.stripSuffix ".cbor" filename of
        Just sha | canonicalSha sha -> Right sha
        _ -> rejected
    ["jitml-checkpoints", experiment, "artifacts", "supervised-qualification", filename]
      | safeExperiment experiment ->
          case Text.stripSuffix ".cbor" filename of
            Just sha | canonicalSha sha -> Right sha
            _ -> rejected
    _ -> rejected
 where
  rejected = Left (Lane.ProductLaneJournalMalformed ("qualification object key is not canonical: " <> key))
  safeExperiment experiment =
    not (Text.null experiment)
      && experiment `notElem` [".", ".."]
      && Text.all (\character -> character /= '\\' && not (isControl character)) experiment

canonicalSha :: Text -> Bool
canonicalSha sha =
  Text.length sha == 64
    && Text.all (\character -> character `elem` ("0123456789abcdef" :: String)) sha
