{-# LANGUAGE OverloadedStrings #-}

-- | Synthetic archive-format controls, not dataset training or a hardware gate.
module TinyArchiveControls
  ( tinyArchiveControls
  , tinyArchiveFormatTest
  , tinyInterleavingTest
  , tinyCoverageTest
  , tinyMetadataTest
  , tinyHeldOutOrderTest
  )
where

import Codec.Archive.Zip qualified as Zip
import Codec.Picture qualified as Picture
import Control.Monad (forM_)
import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as ByteString.Char8
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word8)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertFailure, testCase, (@?=))

import JitML.SL.Classifier (ClassifierConfig (..), LabeledExample (..), defaultClassifierConfig)
import JitML.SL.Dataset qualified as Dataset
import JitML.SL.TinyImageNet qualified as TinyImageNet

tinyArchiveControls :: TestTree
tinyArchiveControls =
  testGroup
    "Tiny archive local controls"
    [ tinyArchiveFormatTest
    , tinyInterleavingTest
    , tinyCoverageTest
    , tinyMetadataTest
    , tinyHeldOutOrderTest
    ]

tinyArchiveFormatTest :: TestTree
tinyArchiveFormatTest =
  testCase "Tiny ImageNet archive pin and metadata parsers use real file formats (Sprint 8.12)" $ do
    Dataset.canonicalArtifactSha256For "Tiny ImageNet" Dataset.TrainSplit Dataset.ArchiveArtifact
      @?= Just "6198c8ae015e2b3e007c7841da39ec069199b9aa3bfa943a462022fe5e43c821"
    let wnids =
          Text.Encoding.encodeUtf8 $
            Text.unlines
              [ "n01443537"
              , "n01629819"
              ]
        wordsFile =
          Text.Encoding.encodeUtf8 $
            Text.unlines
              [ "n01443537\tgoldfish, Carassius auratus"
              , "n01629819\tEuropean fire salamander, Salamandra salamandra"
              ]
        valAnnotations =
          Text.Encoding.encodeUtf8 $
            Text.unlines
              [ "val_0.JPEG\tn01443537\t0\t0\t63\t63"
              , "val_1.JPEG\tn01629819\t3\t4\t60\t61"
              ]
    TinyImageNet.parseTinyImageNetWnids wnids @?= Right ["n01443537", "n01629819"]
    case TinyImageNet.parseTinyImageNetWords wordsFile of
      Left err -> assertFailure ("Tiny ImageNet words parse failed: " <> err)
      Right classes -> do
        fmap TinyImageNet.tinyClassId classes @?= ["n01443537", "n01629819"]
        case classes of
          first : _ ->
            TinyImageNet.tinyClassNames first @?= ["goldfish", "Carassius auratus"]
          [] -> assertFailure "expected Tiny ImageNet classes"
    case TinyImageNet.parseTinyImageNetValAnnotations valAnnotations of
      Left err -> assertFailure ("Tiny ImageNet val_annotations parse failed: " <> err)
      Right annotations -> do
        fmap TinyImageNet.tinyValImage annotations @?= ["val_0.JPEG", "val_1.JPEG"]
        fmap TinyImageNet.tinyValClassId annotations @?= ["n01443537", "n01629819"]
        fmap TinyImageNet.tinyValBoxX1 annotations @?= [63, 60]
    let trainJpeg = tinyJpeg 10 20 30
        valJpeg = tinyJpeg 40 50 60
        archiveBytes =
          zipArchive
            [ ("tiny-imagenet-200/wnids.txt", wnids)
            , ("tiny-imagenet-200/train/n01443537/images/n01443537_0.JPEG", trainJpeg)
            , ("tiny-imagenet-200/val/val_annotations.txt", valAnnotations)
            , ("tiny-imagenet-200/val/images/val_0.JPEG", valJpeg)
            , ("tiny-imagenet-200/val/images/val_1.JPEG", valJpeg)
            ]
    case TinyImageNet.decodeTinyImageNetArchiveBoundedDataset Dataset.TrainSplit (Just 1) archiveBytes of
      Left err -> assertFailure ("Tiny ImageNet train archive decode failed: " <> err)
      Right examples -> do
        fmap exampleLabel examples @?= [0]
        case examples of
          first : _ -> VU.length (exampleFeatures first) @?= 3
          [] -> assertFailure "expected Tiny ImageNet train example"
    case TinyImageNet.decodeTinyImageNetArchiveBoundedDataset Dataset.TestSplit (Just 1) archiveBytes of
      Left err -> assertFailure ("Tiny ImageNet validation archive decode failed: " <> err)
      Right examples ->
        fmap exampleLabel examples @?= [0]

tinyInterleavingTest :: TestTree
tinyInterleavingTest =
  testCase "Tiny ImageNet training interleaves canonical labels and preserves every bounded prefix" $ do
    -- Canonical order intentionally differs from path order, and the
    -- absent first class must not cause the remaining labels to shift.
    let wnids = "nMissing\nnZulu\nnAlpha\nnMiddle\n"
        imageA = tinyJpeg 20 128 128
        imageB = tinyJpeg 40 128 128
        imageC = tinyJpeg 60 128 128
        imageD = tinyJpeg 80 128 128
        imageE = tinyJpeg 100 128 128
        imageF = tinyJpeg 120 128 128
        entry classId name payload =
          ("tiny-imagenet-200/train/" <> classId <> "/images/" <> name <> ".JPEG", payload)
        entries =
          [ entry "nAlpha" "b" imageE
          , entry "nZulu" "c" imageF
          , entry "nMiddle" "a" imageC
          , entry "nZulu" "b" imageD
          , entry "nAlpha" "a" imageB
          , entry "nZulu" "a" imageA
          ]
        archiveBytes = zipArchive (("tiny-imagenet-200/wnids.txt", wnids) : entries)
        reversedArchiveBytes = zipArchive (("tiny-imagenet-200/wnids.txt", wnids) : reverse entries)
    case ( TinyImageNet.decodeTinyImageNetArchiveBoundedDataset Dataset.TrainSplit Nothing archiveBytes
         , traverse TinyImageNet.decodeTinyImageNetJpeg [imageA, imageB, imageC, imageD, imageE, imageF]
         ) of
      (Right examples, Right expectedFeatures) -> do
        fmap exampleLabel examples @?= [1, 2, 3, 1, 2, 1]
        fmap exampleFeatures examples @?= expectedFeatures
        TinyImageNet.decodeTinyImageNetArchiveBoundedDataset Dataset.TrainSplit Nothing reversedArchiveBytes
          @?= Right examples
        forM_ [0 .. length examples] $ \limit ->
          TinyImageNet.decodeTinyImageNetArchiveBoundedDataset Dataset.TrainSplit (Just limit) archiveBytes
            @?= Right (take limit examples)
      result -> assertFailure ("Tiny ImageNet interleaved archive decode failed: " <> show result)

tinyCoverageTest :: TestTree
tinyCoverageTest =
  testCase "Tiny ImageNet gradient and selection prefixes both cover all 200 classes" $ do
    let classIds = ["n" <> show index | index <- [199, 198 .. 0 :: Int]]
        wnids = ByteString.Char8.pack (unlines classIds)
        image = tinyJpeg 80 128 128
        entries =
          [ ("tiny-imagenet-200/train/" <> classId <> "/images/" <> show imageIndex <> ".JPEG", image)
          | classId <- classIds
          , imageIndex <- [0 .. 2 :: Int]
          ]
        archiveBytes = zipArchive (("tiny-imagenet-200/wnids.txt", wnids) : reverse entries)
    case TinyImageNet.decodeTinyImageNetArchiveBoundedClassificationDataset
      defaultClassifierConfig
      Dataset.TrainSplit
      (Just 600)
      archiveBytes of
      Left err -> assertFailure ("Tiny ImageNet class-coverage decode failed: " <> err)
      Right (config, examples) -> do
        clfClasses config @?= 200
        length examples @?= 600
        let trainLabels = fmap exampleLabel (take 400 examples)
            selectionLabels = fmap exampleLabel (drop 400 examples)
        take 200 trainLabels @?= [0 .. 199]
        selectionLabels @?= [0 .. 199]
        forM_ [0 .. 199] $ \label ->
          length (filter (== label) trainLabels) @?= 2

tinyMetadataTest :: TestTree
tinyMetadataTest =
  testCase "Tiny ImageNet selection validates class metadata before bounding image decoding" $ do
    let metadata = ("tiny-imagenet-200/wnids.txt", "nKnown\n")
        firstImage =
          ("tiny-imagenet-200/train/nKnown/images/a.JPEG", tinyJpeg 80 128 128)
        laterInvalidImage =
          ("tiny-imagenet-200/train/nKnown/images/z.JPEG", "not a JPEG")
        decode entries =
          TinyImageNet.decodeTinyImageNetArchiveBoundedDataset
            Dataset.TrainSplit
            (Just 1)
            (zipArchive (metadata : entries))
    case decode [laterInvalidImage, firstImage] of
      Right examples -> fmap exampleLabel examples @?= [0]
      Left err -> assertFailure ("Tiny ImageNet decoded an image beyond its bound: " <> err)
    decode
      [ firstImage
      , ("tiny-imagenet-200/train/nUnknown/images/z.JPEG", "not a JPEG")
      ]
      @?= Left "tiny-imagenet: unknown class id nUnknown"
    decode
      [ firstImage
      , ("tiny-imagenet-200/train/orphan.JPEG", "not a JPEG")
      ]
      @?= Left "tiny-imagenet train: cannot derive class id from tiny-imagenet-200/train/orphan.JPEG"
    TinyImageNet.parseTinyImageNetWnids "nKnown\nnKnown\n"
      @?= Left "tiny-imagenet wnids: duplicate class ids"

tinyHeldOutOrderTest :: TestTree
tinyHeldOutOrderTest =
  testCase "Tiny ImageNet held-out decoding retains annotation order" $ do
    let wnids = "nZulu\nnAlpha\nnMiddle\n"
        annotations =
          "last.JPEG\tnMiddle\t0\t0\t0\t0\nfirst.JPEG\tnZulu\t0\t0\t0\t0\nmiddle.JPEG\tnAlpha\t0\t0\t0\t0\n"
        image = tinyJpeg 80 128 128
        archiveBytes =
          zipArchive
            [ ("tiny-imagenet-200/wnids.txt", wnids)
            , ("tiny-imagenet-200/val/val_annotations.txt", annotations)
            , ("tiny-imagenet-200/val/images/first.JPEG", image)
            , ("tiny-imagenet-200/val/images/middle.JPEG", image)
            , ("tiny-imagenet-200/val/images/last.JPEG", image)
            ]
    forM_ [Dataset.ValidationSplit, Dataset.TestSplit] $ \split ->
      case TinyImageNet.decodeTinyImageNetArchiveBoundedDataset split (Just 3) archiveBytes of
        Left err -> assertFailure ("Tiny ImageNet held-out annotation decode failed: " <> err)
        Right examples -> fmap exampleLabel examples @?= [2, 0, 1]

tinyJpeg :: Word8 -> Word8 -> Word8 -> ByteString.ByteString
tinyJpeg r g b =
  LazyByteString.toStrict $
    Picture.encodeJpeg $
      Picture.generateImage
        (\_ _ -> Picture.PixelYCbCr8 r g b)
        1
        1

zipArchive :: [(FilePath, ByteString.ByteString)] -> ByteString.ByteString
zipArchive entries =
  LazyByteString.toStrict (Zip.fromArchive (foldr addEntry Zip.emptyArchive entries))
 where
  addEntry (path, payload) =
    Zip.addEntryToArchive
      (Zip.toEntry path 0 (LazyByteString.fromStrict payload))
