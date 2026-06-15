{-# LANGUAGE OverloadedStrings #-}

module JitML.SL.TinyImageNet
  ( TinyImageNetClass (..)
  , TinyImageNetValAnnotation (..)
  , parseTinyImageNetWnids
  , parseTinyImageNetWords
  , parseTinyImageNetValAnnotations
  , decodeTinyImageNetJpeg
  , decodeTinyImageNetArchiveBoundedDataset
  , decodeTinyImageNetArchiveBoundedClassificationDataset
  )
where

import Codec.Compression.Zlib.Raw qualified as ZlibRaw
import Codec.Picture qualified as Picture
import Data.Bits (shiftL, (.|.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as ByteString.Char8
import Data.ByteString.Lazy qualified as LazyByteString
import Data.List qualified as List
import Data.Map.Strict qualified as Map
import Data.Maybe qualified as Maybe
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word16, Word32, Word64, Word8)
import Text.Read qualified

import JitML.SL.Classifier (ClassifierConfig (..), Dataset, LabeledExample (..))
import JitML.SL.Dataset qualified as DatasetRegistry

data TinyImageNetClass = TinyImageNetClass
  { tinyClassId :: !Text
  , tinyClassNames :: ![Text]
  }
  deriving stock (Eq, Show)

data TinyImageNetValAnnotation = TinyImageNetValAnnotation
  { tinyValImage :: !Text
  , tinyValClassId :: !Text
  , tinyValBoxX0 :: !Int
  , tinyValBoxY0 :: !Int
  , tinyValBoxX1 :: !Int
  , tinyValBoxY1 :: !Int
  }
  deriving stock (Eq, Show)

parseTinyImageNetWnids :: ByteString -> Either String [Text]
parseTinyImageNetWnids bytes = do
  text <- decodeUtf8 "wnids" bytes
  let wnids =
        [ Text.strip line
        | line <- Text.lines text
        , not (Text.null (Text.strip line))
        ]
  if null wnids
    then Left "tiny-imagenet wnids: no class ids"
    else Right wnids

parseTinyImageNetWords :: ByteString -> Either String [TinyImageNetClass]
parseTinyImageNetWords bytes = do
  text <- decodeUtf8 "words" bytes
  traverse
    parseWordsLine
    [ (lineNumber, line)
    | (lineNumber, line) <- zip [1 :: Int ..] (Text.lines text)
    , not (Text.null (Text.strip line))
    ]

parseTinyImageNetValAnnotations :: ByteString -> Either String [TinyImageNetValAnnotation]
parseTinyImageNetValAnnotations bytes = do
  text <- decodeUtf8 "val_annotations" bytes
  traverse
    parseValLine
    [ (lineNumber, line)
    | (lineNumber, line) <- zip [1 :: Int ..] (Text.lines text)
    , not (Text.null (Text.strip line))
    ]

decodeTinyImageNetJpeg :: ByteString -> Either String (Vector Double)
decodeTinyImageNetJpeg bytes = do
  dynamic <- Picture.decodeImage bytes
  let image = Picture.convertRGB8 dynamic
      width = Picture.imageWidth image
      height = Picture.imageHeight image
  Right $
    VU.generate
      (width * height * 3)
      ( \idx ->
          let pixelIdx = idx `div` 3
              channel = idx `mod` 3
              x = pixelIdx `mod` width
              y = pixelIdx `div` width
              Picture.PixelRGB8 r g b = Picture.pixelAt image x y
           in fromIntegral (case channel of 0 -> r; 1 -> g; _ -> b) / 255.0
      )

decodeTinyImageNetArchiveBoundedDataset
  :: DatasetRegistry.DatasetSplit
  -> Maybe Int
  -> ByteString
  -> Either String Dataset
decodeTinyImageNetArchiveBoundedDataset split subsetLimit archiveBytes = do
  archive <- readTinyZipArchive archiveBytes
  wnids <- parseTinyImageNetWnids =<< readZipEntry archive "tiny-imagenet-200/wnids.txt"
  let labelMap = Map.fromList (zip wnids [0 :: Int ..])
  decodeTinyImageNetArchive split subsetLimit archive labelMap

decodeTinyImageNetArchiveBoundedClassificationDataset
  :: ClassifierConfig
  -> DatasetRegistry.DatasetSplit
  -> Maybe Int
  -> ByteString
  -> Either String (ClassifierConfig, Dataset)
decodeTinyImageNetArchiveBoundedClassificationDataset config split subsetLimit archiveBytes = do
  archive <- readTinyZipArchive archiveBytes
  wnids <- parseTinyImageNetWnids =<< readZipEntry archive "tiny-imagenet-200/wnids.txt"
  let labelMap = Map.fromList (zip wnids [0 :: Int ..])
  dataset <- decodeTinyImageNetArchive split subsetLimit archive labelMap
  firstExample <- case Maybe.listToMaybe dataset of
    Just example -> Right example
    Nothing -> Left "tiny-imagenet: produced no labeled examples"
  Right
    ( config
        { clfInputs = VU.length (exampleFeatures firstExample)
        , clfClasses = length wnids
        }
    , dataset
    )

parseWordsLine :: (Int, Text) -> Either String TinyImageNetClass
parseWordsLine (lineNumber, line) =
  case Text.splitOn "\t" line of
    [wnid, namesText]
      | Text.null (Text.strip wnid) ->
          Left ("tiny-imagenet words: line " <> show lineNumber <> " has empty wnid")
      | otherwise ->
          Right
            TinyImageNetClass
              { tinyClassId = Text.strip wnid
              , tinyClassNames =
                  [ Text.strip name
                  | name <- Text.splitOn "," namesText
                  , not (Text.null (Text.strip name))
                  ]
              }
    _ ->
      Left ("tiny-imagenet words: line " <> show lineNumber <> " must have wnid and names")

parseValLine :: (Int, Text) -> Either String TinyImageNetValAnnotation
parseValLine (lineNumber, line) =
  case Text.splitOn "\t" line of
    [imageName, wnid, x0Text, y0Text, x1Text, y1Text] -> do
      x0 <- parseInt "x0" x0Text
      y0 <- parseInt "y0" y0Text
      x1 <- parseInt "x1" x1Text
      y1 <- parseInt "y1" y1Text
      Right
        TinyImageNetValAnnotation
          { tinyValImage = imageName
          , tinyValClassId = wnid
          , tinyValBoxX0 = x0
          , tinyValBoxY0 = y0
          , tinyValBoxX1 = x1
          , tinyValBoxY1 = y1
          }
    _ ->
      Left
        ( "tiny-imagenet val_annotations: line "
            <> show lineNumber
            <> " must have image, class, and bbox fields"
        )
 where
  parseInt field value =
    case Text.Read.readMaybe (Text.unpack (Text.strip value)) of
      Just parsed -> Right parsed
      Nothing ->
        Left
          ( "tiny-imagenet val_annotations: line "
              <> show lineNumber
              <> " has non-integer "
              <> field
          )

decodeUtf8 :: String -> ByteString -> Either String Text
decodeUtf8 label bytes =
  case Text.Encoding.decodeUtf8' bytes of
    Left err -> Left ("tiny-imagenet " <> label <> ": invalid UTF-8: " <> show err)
    Right text -> Right text

decodeTinyImageNetArchive
  :: DatasetRegistry.DatasetSplit
  -> Maybe Int
  -> TinyZipArchive
  -> Map.Map Text Int
  -> Either String Dataset
decodeTinyImageNetArchive split subsetLimit archive labelMap =
  case split of
    DatasetRegistry.TrainSplit ->
      decodeTrainingImages archive labelMap subsetLimit
    DatasetRegistry.ValidationSplit ->
      decodeValidationImages archive labelMap subsetLimit
    DatasetRegistry.TestSplit ->
      decodeValidationImages archive labelMap subsetLimit

decodeTrainingImages :: TinyZipArchive -> Map.Map Text Int -> Maybe Int -> Either String Dataset
decodeTrainingImages archive labelMap subsetLimit =
  traverse decodeEntry selected
 where
  selected =
    takeBound subsetLimit $
      List.sortOn tinyZipPath $
        filter isTrainingJpeg (tinyZipEntries archive)
  isTrainingJpeg entry =
    let path = tinyZipPath entry
     in "tiny-imagenet-200/train/" `List.isPrefixOf` path
          && ".JPEG" `List.isSuffixOf` path
  decodeEntry entry =
    case trainClassIdFromPath (tinyZipPath entry) of
      Nothing -> Left ("tiny-imagenet train: cannot derive class id from " <> tinyZipPath entry)
      Just classId -> do
        label <- lookupLabel labelMap classId
        features <- decodeTinyImageNetJpeg =<< inflateTinyZipEntry archive entry
        Right (LabeledExample features label)

decodeValidationImages :: TinyZipArchive -> Map.Map Text Int -> Maybe Int -> Either String Dataset
decodeValidationImages archive labelMap subsetLimit = do
  annotations <-
    parseTinyImageNetValAnnotations
      =<< readZipEntry archive "tiny-imagenet-200/val/val_annotations.txt"
  traverse decodeAnnotation (takeBound subsetLimit annotations)
 where
  decodeAnnotation annotation = do
    label <- lookupLabel labelMap (tinyValClassId annotation)
    imageBytes <-
      readZipEntry
        archive
        ("tiny-imagenet-200/val/images/" <> Text.unpack (tinyValImage annotation))
    features <- decodeTinyImageNetJpeg imageBytes
    Right (LabeledExample features label)

readZipEntry :: TinyZipArchive -> FilePath -> Either String ByteString
readZipEntry archive path =
  case Map.lookup path (tinyZipEntryMap archive) of
    Nothing -> Left ("zip: missing entry " <> path)
    Just entry -> inflateTinyZipEntry archive entry

data TinyZipArchive = TinyZipArchive
  { tinyZipBytes :: !ByteString
  , tinyZipEntries :: ![TinyZipEntry]
  , tinyZipEntryMap :: !(Map.Map FilePath TinyZipEntry)
  }

data TinyZipEntry = TinyZipEntry
  { tinyZipPath :: !FilePath
  , tinyZipMethod :: !Word16
  , tinyZipCompressedSize :: !Int
  , tinyZipUncompressedSize :: !Int
  , tinyZipLocalHeaderOffset :: !Int
  }
  deriving stock (Eq, Show)

data CentralDirectoryLocation = CentralDirectoryLocation
  { centralDirectoryOffset :: !Int
  , centralDirectorySize :: !Int
  , centralDirectoryEntryCount :: !Int
  }
  deriving stock (Eq, Show)

readTinyZipArchive :: ByteString -> Either String TinyZipArchive
readTinyZipArchive bytes = do
  directory <- readCentralDirectoryLocation bytes
  entries <- readCentralDirectory bytes directory
  let fileEntries =
        filter (not . List.isSuffixOf "/" . tinyZipPath) entries
  Right
    TinyZipArchive
      { tinyZipBytes = bytes
      , tinyZipEntries = fileEntries
      , tinyZipEntryMap = Map.fromList [(tinyZipPath entry, entry) | entry <- fileEntries]
      }

readCentralDirectoryLocation :: ByteString -> Either String CentralDirectoryLocation
readCentralDirectoryLocation bytes = do
  eocdOffset <-
    case findSignatureReverse eocdSignature bytes of
      Just offset -> Right offset
      Nothing -> Left "zip: missing end of central directory"
  requireBytes "zip end of central directory" eocdOffset 22 bytes
  let entryCount16 = word16LEAt bytes (eocdOffset + 10)
      centralSize32 = word32LEAt bytes (eocdOffset + 12)
      centralOffset32 = word32LEAt bytes (eocdOffset + 16)
      needsZip64 =
        entryCount16 == maxBound
          || centralSize32 == maxBound
          || centralOffset32 == maxBound
  if needsZip64
    then readZip64CentralDirectoryLocation bytes eocdOffset
    else do
      entryCount <- word64ToInt "zip central directory entry count" (fromIntegral entryCount16)
      centralSize <- word64ToInt "zip central directory size" (fromIntegral centralSize32)
      centralOffset <- word64ToInt "zip central directory offset" (fromIntegral centralOffset32)
      Right
        CentralDirectoryLocation
          { centralDirectoryOffset = centralOffset
          , centralDirectorySize = centralSize
          , centralDirectoryEntryCount = entryCount
          }

readZip64CentralDirectoryLocation :: ByteString -> Int -> Either String CentralDirectoryLocation
readZip64CentralDirectoryLocation bytes eocdOffset = do
  let locatorOffset = eocdOffset - 20
  if locatorOffset < 0 || not (matchesSignature bytes locatorOffset zip64LocatorSignature)
    then Left "zip: Zip64 end of central directory locator is missing"
    else do
      zip64EocdOffset <-
        word64ToInt
          "zip64 end of central directory offset"
          (word64LEAt bytes (locatorOffset + 8))
      requireBytes "zip64 end of central directory" zip64EocdOffset 56 bytes
      if not (matchesSignature bytes zip64EocdOffset zip64EocdSignature)
        then Left "zip: Zip64 end of central directory signature is invalid"
        else do
          entryCount <-
            word64ToInt
              "zip64 central directory entry count"
              (word64LEAt bytes (zip64EocdOffset + 32))
          centralSize <-
            word64ToInt
              "zip64 central directory size"
              (word64LEAt bytes (zip64EocdOffset + 40))
          centralOffset <-
            word64ToInt
              "zip64 central directory offset"
              (word64LEAt bytes (zip64EocdOffset + 48))
          Right
            CentralDirectoryLocation
              { centralDirectoryOffset = centralOffset
              , centralDirectorySize = centralSize
              , centralDirectoryEntryCount = entryCount
              }

readCentralDirectory :: ByteString -> CentralDirectoryLocation -> Either String [TinyZipEntry]
readCentralDirectory bytes directory = do
  requireBytes
    "zip central directory"
    (centralDirectoryOffset directory)
    (centralDirectorySize directory)
    bytes
  go [] (centralDirectoryEntryCount directory) (centralDirectoryOffset directory)
 where
  go acc remaining offset
    | remaining == 0 = Right (reverse acc)
    | otherwise = do
        requireBytes "zip central directory entry" offset 46 bytes
        if not (matchesSignature bytes offset centralDirectorySignature)
          then Left ("zip: invalid central directory entry at offset " <> show offset)
          else do
            let method = word16LEAt bytes (offset + 10)
                compressedSize32 = word32LEAt bytes (offset + 20)
                uncompressedSize32 = word32LEAt bytes (offset + 24)
                nameLength = fromIntegral (word16LEAt bytes (offset + 28))
                extraLength = fromIntegral (word16LEAt bytes (offset + 30))
                commentLength = fromIntegral (word16LEAt bytes (offset + 32))
                localHeaderOffset32 = word32LEAt bytes (offset + 42)
                nameOffset = offset + 46
                extraOffset = nameOffset + nameLength
                commentOffset = extraOffset + extraLength
                nextOffset = commentOffset + commentLength
            requireBytes "zip central directory entry name" nameOffset nameLength bytes
            requireBytes "zip central directory entry extra field" extraOffset extraLength bytes
            requireBytes "zip central directory entry comment" commentOffset commentLength bytes
            let path = ByteString.Char8.unpack (byteSlice bytes nameOffset nameLength)
                extra = byteSlice bytes extraOffset extraLength
            (uncompressedSize64, compressedSize64, localHeaderOffset64) <-
              resolveZip64Metadata
                uncompressedSize32
                compressedSize32
                localHeaderOffset32
                extra
            uncompressedSize <- word64ToInt ("zip uncompressed size for " <> path) uncompressedSize64
            compressedSize <- word64ToInt ("zip compressed size for " <> path) compressedSize64
            localHeaderOffset <- word64ToInt ("zip local header offset for " <> path) localHeaderOffset64
            let entry =
                  TinyZipEntry
                    { tinyZipPath = path
                    , tinyZipMethod = method
                    , tinyZipCompressedSize = compressedSize
                    , tinyZipUncompressedSize = uncompressedSize
                    , tinyZipLocalHeaderOffset = localHeaderOffset
                    }
            go (entry : acc) (remaining - 1) nextOffset

resolveZip64Metadata
  :: Word32
  -> Word32
  -> Word32
  -> ByteString
  -> Either String (Word64, Word64, Word64)
resolveZip64Metadata uncompressed32 compressed32 localHeaderOffset32 extra =
  if not (needsUncompressed || needsCompressed || needsLocalHeaderOffset)
    then
      Right
        ( fromIntegral uncompressed32
        , fromIntegral compressed32
        , fromIntegral localHeaderOffset32
        )
    else do
      zip64 <- findZip64Extra extra
      (uncompressed64, offset1) <-
        readMaybeZip64Value needsUncompressed (fromIntegral uncompressed32) zip64 0 "uncompressed size"
      (compressed64, offset2) <-
        readMaybeZip64Value needsCompressed (fromIntegral compressed32) zip64 offset1 "compressed size"
      (localHeaderOffset64, _) <-
        readMaybeZip64Value
          needsLocalHeaderOffset
          (fromIntegral localHeaderOffset32)
          zip64
          offset2
          "local header offset"
      Right (uncompressed64, compressed64, localHeaderOffset64)
 where
  needsUncompressed = uncompressed32 == maxBound
  needsCompressed = compressed32 == maxBound
  needsLocalHeaderOffset = localHeaderOffset32 == maxBound

findZip64Extra :: ByteString -> Either String ByteString
findZip64Extra extra = go 0
 where
  total = ByteString.length extra
  go offset
    | offset == total = Left "zip: Zip64 extra field is missing"
    | offset + 4 > total = Left "zip: truncated extra field header"
    | otherwise =
        let headerId = word16LEAt extra offset
            payloadLength = fromIntegral (word16LEAt extra (offset + 2))
            payloadOffset = offset + 4
            nextOffset = payloadOffset + payloadLength
         in if nextOffset > total
              then Left "zip: truncated extra field payload"
              else
                if headerId == 0x0001
                  then Right (byteSlice extra payloadOffset payloadLength)
                  else go nextOffset

readMaybeZip64Value :: Bool -> Word64 -> ByteString -> Int -> String -> Either String (Word64, Int)
readMaybeZip64Value needed fallback zip64 offset label =
  if not needed
    then Right (fallback, offset)
    else do
      requireBytes ("zip64 " <> label) offset 8 zip64
      Right (word64LEAt zip64 offset, offset + 8)

inflateTinyZipEntry :: TinyZipArchive -> TinyZipEntry -> Either String ByteString
inflateTinyZipEntry archive entry = do
  compressed <- readTinyZipCompressedPayload archive entry
  case tinyZipMethod entry of
    0 ->
      if ByteString.length compressed == tinyZipUncompressedSize entry
        then Right compressed
        else
          Left
            ( "zip: stored entry "
                <> tinyZipPath entry
                <> " has compressed/uncompressed size mismatch"
            )
    8 -> do
      let inflated =
            LazyByteString.toStrict $
              ZlibRaw.decompress (LazyByteString.fromStrict compressed)
      if ByteString.length inflated == tinyZipUncompressedSize entry
        then Right inflated
        else
          Left
            ( "zip: deflated entry "
                <> tinyZipPath entry
                <> " inflated to "
                <> show (ByteString.length inflated)
                <> " bytes, expected "
                <> show (tinyZipUncompressedSize entry)
            )
    method ->
      Left
        ( "zip: unsupported compression method "
            <> show method
            <> " for "
            <> tinyZipPath entry
        )

readTinyZipCompressedPayload :: TinyZipArchive -> TinyZipEntry -> Either String ByteString
readTinyZipCompressedPayload archive entry = do
  let bytes = tinyZipBytes archive
      localOffset = tinyZipLocalHeaderOffset entry
  requireBytes "zip local file header" localOffset 30 bytes
  if not (matchesSignature bytes localOffset localFileHeaderSignature)
    then Left ("zip: invalid local file header for " <> tinyZipPath entry)
    else do
      let nameLength = fromIntegral (word16LEAt bytes (localOffset + 26))
          extraLength = fromIntegral (word16LEAt bytes (localOffset + 28))
          payloadOffset = localOffset + 30 + nameLength + extraLength
      requireBytes
        ("zip compressed payload for " <> tinyZipPath entry)
        payloadOffset
        (tinyZipCompressedSize entry)
        bytes
      Right (byteSlice bytes payloadOffset (tinyZipCompressedSize entry))

findSignatureReverse :: [Word8] -> ByteString -> Maybe Int
findSignatureReverse signature bytes =
  List.find
    (\offset -> matchesSignature bytes offset signature)
    [firstOffset, firstOffset - 1 .. lastOffset]
 where
  len = ByteString.length bytes
  signatureLength = length signature
  firstOffset = max 0 (len - signatureLength)
  lastOffset = max 0 (len - 65557)

matchesSignature :: ByteString -> Int -> [Word8] -> Bool
matchesSignature bytes offset signature =
  offset >= 0
    && offset + length signature <= ByteString.length bytes
    && and
      [ ByteString.index bytes (offset + idx) == expected
      | (idx, expected) <- zip [0 ..] signature
      ]

requireBytes :: String -> Int -> Int -> ByteString -> Either String ()
requireBytes label offset size bytes
  | offset < 0 || size < 0 =
      Left ("zip: invalid " <> label <> " bounds")
  | offset + size <= ByteString.length bytes =
      Right ()
  | otherwise =
      Left
        ( "zip: "
            <> label
            <> " extends beyond archive bounds at offset "
            <> show offset
            <> " with size "
            <> show size
        )

byteSlice :: ByteString -> Int -> Int -> ByteString
byteSlice bytes offset size =
  ByteString.take size (ByteString.drop offset bytes)

word16LEAt :: ByteString -> Int -> Word16
word16LEAt bytes offset =
  fromIntegral (ByteString.index bytes offset)
    .|. shiftL (fromIntegral (ByteString.index bytes (offset + 1))) 8

word32LEAt :: ByteString -> Int -> Word32
word32LEAt bytes offset =
  fromIntegral (ByteString.index bytes offset)
    .|. shiftL (fromIntegral (ByteString.index bytes (offset + 1))) 8
    .|. shiftL (fromIntegral (ByteString.index bytes (offset + 2))) 16
    .|. shiftL (fromIntegral (ByteString.index bytes (offset + 3))) 24

word64LEAt :: ByteString -> Int -> Word64
word64LEAt bytes offset =
  foldr
    ( \idx acc ->
        acc
          .|. shiftL
            (fromIntegral (ByteString.index bytes (offset + idx)))
            (idx * 8)
    )
    0
    [0 .. 7]

word64ToInt :: String -> Word64 -> Either String Int
word64ToInt label value
  | value <= fromIntegral (maxBound :: Int) = Right (fromIntegral value)
  | otherwise = Left ("zip: " <> label <> " exceeds Int bounds")

eocdSignature :: [Word8]
eocdSignature = [0x50, 0x4b, 0x05, 0x06]

zip64LocatorSignature :: [Word8]
zip64LocatorSignature = [0x50, 0x4b, 0x06, 0x07]

zip64EocdSignature :: [Word8]
zip64EocdSignature = [0x50, 0x4b, 0x06, 0x06]

centralDirectorySignature :: [Word8]
centralDirectorySignature = [0x50, 0x4b, 0x01, 0x02]

localFileHeaderSignature :: [Word8]
localFileHeaderSignature = [0x50, 0x4b, 0x03, 0x04]

lookupLabel :: Map.Map Text Int -> Text -> Either String Int
lookupLabel labelMap classId =
  case Map.lookup classId labelMap of
    Just label -> Right label
    Nothing -> Left ("tiny-imagenet: unknown class id " <> Text.unpack classId)

trainClassIdFromPath :: FilePath -> Maybe Text
trainClassIdFromPath path =
  case List.stripPrefix "tiny-imagenet-200/train/" path of
    Just rest ->
      case break (== '/') rest of
        (classId, '/' : _) | not (null classId) -> Just (Text.pack classId)
        _ -> Nothing
    Nothing -> Nothing

takeBound :: Maybe Int -> [a] -> [a]
takeBound (Just limit) values
  | limit >= 0 = take limit values
takeBound _ values = values
