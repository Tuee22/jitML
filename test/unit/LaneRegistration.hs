{-# LANGUAGE OverloadedStrings #-}

module LaneRegistration (laneRegistrationTests) where

import Control.Monad ((>=>))
import Data.Aeson (Value (..), eitherDecodeStrict', encode, toJSON)
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Either (isLeft)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector qualified as Vector
import System.Directory (canonicalizePath, createDirectoryIfMissing, removeFile)
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Posix.Files (createSymbolicLink)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

import JitML.Plan.Plan (Validation (..))
import JitML.Product.LaneRegistration qualified as IORegistration
import JitML.Product.LaneRegistrationData
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.SourceDigest (SourceStamp (..))
import JitML.Product.StatusEvidence qualified as Status
import JitML.Product.StatusLoader qualified as StatusLoader
import JitML.Product.ValidationRecord (sha256Hex)
import JitML.Substrate (Substrate (..))
import JitML.Test.ProductAggregation qualified as Aggregate
import JitML.Test.RegisteredLaneEvidence qualified as Registered

-- The positive fixtures below prove ordinary canonical DATA and actual bounded
-- FILE reads only. Marker journal bytes are never a successful admitted lane;
-- the high adapter is explicitly required to refuse them. No native, review,
-- training, publication, Store or device capability is manufactured.
laneRegistrationTests :: TestTree
laneRegistrationTests =
  testGroup
    "separately selected lane generation registration"
    [ testCase "ordinary generation canonical roundtrip retains full ordered55 and original epoch" $ do
        bytes <- right (encodeLaneGenerationData generation)
        decodeLaneGenerationData bytes @?= Right generation
    , testCase "ordinary selection history canonical roundtrip retains independent expected snapshot pin" $ do
        let history = historyFor generationBytes
        bytes <- right (encodeLaneRegistrationData history)
        decodeLaneRegistrationData bytes @?= Right history
    , testCase "ordered contract digest matches independent ASCII known answer" $
        laneRowContractsSha256 rows
          @?= Right "af08053ede85e6f0a429932b95db06cdeebafeb7f82d62161f2a0cbea76dd9fe"
    , testCase "contract digest changes on order plan or contract mutation" $ do
        let altered =
              [ reverse rows
              , fmap (\r -> r {laneRowPlanId = digest "c"}) rows
              , fmap (\r -> r {laneRowContractSha256 = digest "c"}) rows
              ]
        mapM_
          ( \value ->
              assertBool
                "changed contract set retained digest"
                (laneRowContractsSha256 value /= laneRowContractsSha256 rows)
          )
          altered
    , testCase "both review identities bind full55 contract digest" $
        rejected
          ( encodeLaneGenerationData
              generation {laneGenerationNativeReview = review {laneReviewContractSetSha256 = digest "c"}}
          )
    , testCase "generation rejects fewer more or duplicate rows before encoding" $
        mapM_
          (rejected . encodeLaneGenerationData)
          [ generation {laneGenerationRows = take 54 rows}
          , generation {laneGenerationRows = rows <> rows}
          , generation {laneGenerationRows = replicate 55 row0}
          ]
    , testCase "source algorithm and source SHA must be supported canonical identities" $
        mapM_
          (rejected . encodeLaneGenerationData)
          [ generation {laneGenerationSource = SourceStamp 2 (digest "a")}
          , generation {laneGenerationSource = SourceStamp 1 (digest "A")}
          ]
    , testCase "unknown generation domain version arity and substrate are refused" $
        mapM_
          (rejected . decodeLaneGenerationData)
          [ change 0 (String "other") generationBytes
          , change 1 (toJSON (2 :: Int)) generationBytes
          , change 2 (String "pretend-lane") generationBytes
          , canonical (Array Vector.empty)
          ]
    , testCase "generation rejects noncanonical trailing whitespace and malformed JSON" $
        mapM_ (rejected . decodeLaneGenerationData) [generationBytes <> "\n", "[", "{}"]
    , testCase "declared root byte caps refuse overlong input before JSON decoding" $ do
        rejected
          (decodeLaneGenerationData (ByteString.replicate (fromInteger maximumLaneGenerationBytes + 1) 32))
        rejected
          (decodeLaneRegistrationData (ByteString.replicate (fromInteger maximumLaneRegistrationBytes + 1) 32))
    , testCase "SHA path lane and journal count cannot drift from independent pins" $
        mapM_
          (rejected . encodeLaneGenerationData)
          [ generation
              { laneGenerationJournal = journal {selectedLaneFilePath = "DEVELOPMENT_PLAN/attestations/other.json"}
              }
          , generation {laneGenerationJournal = journal {selectedLaneFileBytes = 0}}
          , generation
              { laneGenerationJournal =
                  journal {selectedLaneFileBytes = fromInteger maximumRegisteredJournalBytes + 1}
              }
          , generation {laneGenerationSubstrate = AppleSilicon}
          ]
    , testCase
        "review paths preserve governed criterion subtree and reject traversal control or backslash"
        $ do
          let withPath path =
                generation
                  { laneGenerationSupervisedReview =
                      review {laneReviewSelection = (laneReviewSelection review) {selectedLaneFilePath = path}}
                  }
          _ <-
            right
              ( encodeLaneGenerationData
                  ( withPath
                      "DEVELOPMENT_PLAN/attestations/phase278-20261015-mac-validation/criterion-reviews/source/linux-cpu/supervised/selection.cbor"
                  )
              )
          mapM_
            (rejected . encodeLaneGenerationData . withPath)
            [ "documents/validation/criterion-reviews/source/linux-cpu/supervised/selection.cbor"
            , "/tmp/outside"
            , "DEVELOPMENT_PLAN/attestations/../outside"
            , "DEVELOPMENT_PLAN/attestations/a\\b"
            , "DEVELOPMENT_PLAN/attestations/a\n"
            ]
    , testCase "row scalar UTF8 caps are checked before encoding" $
        rejected
          ( encodeLaneGenerationData
              generation
                { laneGenerationRows =
                    (row0 {laneRowId = Text.replicate 257 "x"})
                      : (case rows of [] -> []; _ : remainingRows -> remainingRows)
                }
          )
    , testCase "empty or overlong selection history is refused" $ do
        rejected (encodeLaneRegistrationData (LaneRegistrationData LinuxCPU []))
        rejected
          (encodeLaneRegistrationData (LaneRegistrationData LinuxCPU (replicate 4097 (entry generationBytes))))
    , testCase "history ordinal predecessor and SHA-derived snapshot path are exact" $ do
        let first = entry generationBytes
        previous <- right (laneRegistrationEntrySha256 first)
        let second = LaneRegistrationEntryData 1 (Just previous) (selectedGeneration otherGenerationBytes)
        _ <- right (encodeLaneRegistrationData (LaneRegistrationData LinuxCPU [first, second]))
        mapM_
          (rejected . encodeLaneRegistrationData . LaneRegistrationData LinuxCPU)
          [ [first {laneRegistrationOrdinal = 1}]
          , [first, second {laneRegistrationPreviousSha256 = Just (digest "e")}]
          , [first, second {laneRegistrationOrdinal = 2}]
          ,
            [ first
                { laneRegistrationGeneration =
                    (selectedGeneration generationBytes)
                      { selectedLaneFilePath = "DEVELOPMENT_PLAN/attestations/current.json"
                      }
                }
            ]
          ]
    , testCase "history cannot select duplicate snapshot twice" $ do
        let first = entry generationBytes
        previous <- right (laneRegistrationEntrySha256 first)
        rejected
          ( encodeLaneRegistrationData
              ( LaneRegistrationData
                  LinuxCPU
                  [first, first {laneRegistrationOrdinal = 1, laneRegistrationPreviousSha256 = Just previous}]
              )
          )
    , testCase "actual fixed-path loader reads exact snapshot FILE but mints no admitted lane" $
        temporary $ \root -> do
          writeSelection root (historyFor generationBytes)
          writeGeneration root generationBytes
          loaded <- IORegistration.loadLaneRegistrationIn root LinuxCPU >>= right
          IORegistration.loadedLaneGeneration loaded @?= generation
          selectedLaneFileSha256 (IORegistration.loadedLaneGenerationFile loaded)
            @?= sha256Hex generationBytes
    , testCase "last selected generation is current even when an earlier snapshot is absent" $
        temporary $ \root -> do
          history <- twoEntryHistory
          writeSelection root history
          writeGeneration root otherGenerationBytes
          loaded <- IORegistration.loadLaneRegistrationIn root LinuxCPU >>= right
          IORegistration.loadedLaneGeneration loaded @?= otherGeneration
    , testCase "missing last snapshot never falls back to earlier existing generation" $
        temporary $ \root -> do
          history <- twoEntryHistory
          writeSelection root history
          writeGeneration root generationBytes
          actual <- IORegistration.loadLaneRegistrationIn root LinuxCPU
          case actual of
            Left (IORegistration.LaneRegistrationMissing path) -> path @?= Text.unpack (laneGenerationPath (sha256Hex otherGenerationBytes))
            _ -> assertFailure "missing current generation did not fail closed"
    , testCase "missing selection is explicit and no literal historical pin is consulted" $
        temporary $ \root -> do
          actual <- IORegistration.loadLaneRegistrationIn root LinuxCPU
          actual @?= Left (IORegistration.LaneRegistrationMissing (laneRegistrationPath LinuxCPU))
    , testCase "snapshot count and SHA tampering are refused under independently recorded pin" $
        temporary $ \root -> do
          writeSelection root (historyFor generationBytes)
          let path = root </> Text.unpack (laneGenerationPath (sha256Hex generationBytes))
          writeBytes path (generationBytes <> "x")
          IORegistration.loadLaneRegistrationIn root LinuxCPU >>= rejected
          writeBytes path (ByteString.map (\v -> if v == 97 then 98 else v) generationBytes)
          IORegistration.loadLaneRegistrationIn root LinuxCPU >>= rejected
    , testCase "selection lane mismatch does not relabel snapshot" $
        temporary $ \root -> do
          let history = (historyFor generationBytes) {laneRegistrationSubstrate = AppleSilicon}
          bytes <- right (encodeLaneRegistrationData history)
          writeBytes (root </> laneRegistrationPath LinuxCPU) bytes
          IORegistration.loadLaneRegistrationIn root LinuxCPU >>= rejected
    , testCase "directories and dangling symlink selections are refused" $
        temporary $ \root -> do
          let target = root </> laneRegistrationPath LinuxCPU
          createDirectoryIfMissing True (takeDirectory target)
          createSymbolicLink "missing-target" target
          IORegistration.loadLaneRegistrationIn root LinuxCPU >>= rejected
          removeFile target
          createDirectoryIfMissing True target
          IORegistration.loadLaneRegistrationIn root LinuxCPU >>= rejected
    , testCase "selected FILE reader refuses traversal before opening an existing outside target" $
        temporary $ \root -> do
          writeBytes (root </> "outside") marker
          let hostile =
                SelectedLaneFileData
                  "DEVELOPMENT_PLAN/attestations/../../outside"
                  (sha256Hex marker)
                  (fromIntegral (ByteString.length marker))
          IORegistration.readSelectedLaneFileIn root maximumRegisteredJournalBytes hostile >>= rejected
    , testCase "changing selected bytes is observed on each actual FILE read" $
        temporary $ \root -> do
          writeSelection root (historyFor generationBytes)
          writeGeneration root generationBytes
          _ <- IORegistration.loadLaneRegistrationIn root LinuxCPU >>= right
          writeBytes
            (root </> Text.unpack (laneGenerationPath (sha256Hex generationBytes)))
            otherGenerationBytes
          IORegistration.loadLaneRegistrationIn root LinuxCPU >>= rejected
    , testCase
        "high adapter refuses marker journal instead of promoting ordinary registration FILE success"
        $ temporary
        $ \root -> do
          actualGeneration <- canonicalGeneration
          bytes <- right (encodeLaneGenerationData actualGeneration)
          writeSelection root (historyFor bytes)
          writeGeneration root bytes
          writeBytes
            (root </> Text.unpack (selectedLaneFilePath (laneGenerationJournal actualGeneration)))
            marker
          actual <- Registered.loadRegisteredLaneEvidenceIn root LinuxCPU
          case actual of
            Left (Registered.RegisteredLaneJournalRejected _) -> pure ()
            _ -> assertFailure "ordinary marker DATA escaped full lane admission"
    , testCase "canonical current projection contracts are compared before journal IO" $ do
        batch <- canonicalBatch
        value <- canonicalGeneration
        Registered.checkRegisteredLaneGeneration value batch @?= Right ()
        changed <- withRows value (reverse (laneGenerationRows value))
        case Registered.checkRegisteredLaneGeneration changed batch of
          Left (Registered.RegisteredLaneContractsStale _ _) -> pure ()
          _ -> assertFailure "reordered independent expected contracts were accepted"
    , testCase "compare-only review bindings require original source scope and all55 order" $ do
        value <- canonicalGeneration
        let bindings = reviewBindings value
        Registered.checkRegisteredLaneReviewBindings value bindings @?= Right ()
        mapM_
          (rejected . Registered.checkRegisteredLaneReviewBindings value)
          [ reverse bindings
          , take 54 bindings
          , fmap (\(row, _, sl, native) -> (row, Just (SourceStamp 1 (digest "d")), sl, native)) bindings
          ]
    , testCase "old unreviewed chain or replacement review SHA cannot satisfy current registered boundary" $ do
        value <- canonicalGeneration
        let bindings = reviewBindings value
            absent (row, source, _, _) = (row, source, Nothing, Nothing)
            changed (row, source, sl, native) = (row, source, fmap (\(_, receipt, contracts) -> (digest "d", receipt, contracts)) sl, native)
        mapM_
          (rejected . Registered.checkRegisteredLaneReviewBindings value)
          [fmap absent bindings, fmap changed bindings]
    , testCase "status current CPU error remains independent of absent CUDA and Apple registrations" $
        temporary $ \root -> do
          (lane, actual) <- StatusLoader.loadRegisteredLaneJournalIn root LinuxCPU
          lane @?= LinuxCPU
          actual @?= Status.Unproven (Status.Missing (Text.pack (laneRegistrationPath LinuxCPU)) :| [])
    , testCase "current aggregate reports registration absence without falling back to literal history" $
        temporary $ \root -> do
          actual <- Aggregate.loadRegisteredProductAggregationIn root
          case actual of
            Left
              ( Aggregate.ProductAggregationRegisteredLaneRejected
                  LinuxCPU
                  (Registered.RegisteredLaneSelectionRejected (IORegistration.LaneRegistrationMissing path))
                  :| _
                ) ->
                path @?= laneRegistrationPath LinuxCPU
            _ -> assertFailure "current aggregate did not preserve missing registration"
    ]

marker :: ByteString
marker = "ordinary journal marker, never admitted lane evidence"

digest :: Text -> Text
digest = Text.replicate 64

rows :: [LaneRowContractData]
rows =
  [ LaneRowContractData ("row-" <> Text.pack (show index)) (digest "a") (digest "b")
  | index <- [0 :: Int .. 54]
  ]

row0 :: LaneRowContractData
row0 = LaneRowContractData "row-0" (digest "a") (digest "b")

review :: LaneReviewIdentityData
review =
  LaneReviewIdentityData
    ( SelectedLaneFileData
        "DEVELOPMENT_PLAN/attestations/phase278-20261015-mac-validation/criterion-reviews/source/linux-cpu/supervised/selection.cbor"
        (digest "c")
        42
    )
    ( SelectedLaneFileData
        "DEVELOPMENT_PLAN/attestations/phase278-20261015-mac-validation/criterion-reviews/source/linux-cpu/supervised/receipt.cbor"
        (digest "d")
        43
    )
    "af08053ede85e6f0a429932b95db06cdeebafeb7f82d62161f2a0cbea76dd9fe"

journal :: SelectedLaneFileData
journal =
  SelectedLaneFileData
    (laneGenerationJournalPath LinuxCPU (sha256Hex marker))
    (sha256Hex marker)
    (fromIntegral (ByteString.length marker))

generation :: LaneGenerationData
generation = LaneGenerationData LinuxCPU (SourceStamp 1 (digest "a")) journal rows review review

otherGeneration :: LaneGenerationData
otherGeneration = generation {laneGenerationSource = SourceStamp 1 (digest "b")}

generationBytes, otherGenerationBytes :: ByteString
generationBytes = rawGeneration generation
otherGenerationBytes = rawGeneration otherGeneration

-- Independently assembled closed JSON DATA; the production encoder does not
-- generate its own expected parsing fixture.
rawGeneration :: LaneGenerationData -> ByteString
rawGeneration value =
  canonical
    ( arr
        [ String "jitml-product-lane-generation"
        , toJSON (1 :: Int)
        , String "linux-cpu"
        , arr
            [ toJSON (stampAlgorithm (laneGenerationSource value))
            , String (stampSha256 (laneGenerationSource value))
            ]
        , file (laneGenerationJournal value)
        , arr
            [ arr [String (laneRowId row), String (laneRowPlanId row), String (laneRowContractSha256 row)]
            | row <- laneGenerationRows value
            ]
        , reviewWire (laneGenerationSupervisedReview value)
        , reviewWire (laneGenerationNativeReview value)
        ]
    )
 where
  arr = toJSON :: [Value] -> Value
  file selected =
    arr
      [ String (selectedLaneFilePath selected)
      , String (selectedLaneFileSha256 selected)
      , toJSON (selectedLaneFileBytes selected)
      ]
  reviewWire selected =
    arr
      [ file (laneReviewSelection selected)
      , file (laneReviewReceipt selected)
      , String (laneReviewContractSetSha256 selected)
      ]

selectedGeneration :: ByteString -> SelectedLaneFileData
selectedGeneration bytes =
  SelectedLaneFileData
    (laneGenerationPath (sha256Hex bytes))
    (sha256Hex bytes)
    (fromIntegral (ByteString.length bytes))

entry :: ByteString -> LaneRegistrationEntryData
entry bytes = LaneRegistrationEntryData 0 Nothing (selectedGeneration bytes)

historyFor :: ByteString -> LaneRegistrationData
historyFor bytes = LaneRegistrationData LinuxCPU [entry bytes]

twoEntryHistory :: IO LaneRegistrationData
twoEntryHistory = do
  previous <- right (laneRegistrationEntrySha256 (entry generationBytes))
  pure
    ( LaneRegistrationData
        LinuxCPU
        [ entry generationBytes
        , LaneRegistrationEntryData 1 (Just previous) (selectedGeneration otherGenerationBytes)
        ]
    )

canonicalBatch :: IO Matrix.ProductProjectionBatch
canonicalBatch = case Matrix.projectProductRows LinuxCPU Matrix.allProductRows of
  Failure errors -> fail (show errors)
  Success batch -> pure batch

canonicalGeneration :: IO LaneGenerationData
canonicalGeneration = canonicalBatch >>= withRows generation . Registered.currentLaneRowContracts

withRows :: LaneGenerationData -> [LaneRowContractData] -> IO LaneGenerationData
withRows value contracts = do
  sha <- right (laneRowContractsSha256 contracts)
  pure
    value
      { laneGenerationRows = contracts
      , laneGenerationSupervisedReview =
          (laneGenerationSupervisedReview value) {laneReviewContractSetSha256 = sha}
      , laneGenerationNativeReview = (laneGenerationNativeReview value) {laneReviewContractSetSha256 = sha}
      }

reviewBindings
  :: LaneGenerationData
  -> [(Text, Maybe SourceStamp, Maybe (Text, Text, Text), Maybe (Text, Text, Text))]
reviewBindings value = fmap one Matrix.allProductRows
 where
  identity reviewData =
    ( selectedLaneFileSha256 (laneReviewSelection reviewData)
    , selectedLaneFileSha256 (laneReviewReceipt reviewData)
    , laneReviewContractSetSha256 reviewData
    )
  sl = identity (laneGenerationSupervisedReview value)
  native = identity (laneGenerationNativeReview value)
  one row =
    let scopes = case Matrix.family row of
          Matrix.Supervised -> (Just sl, Nothing)
          Matrix.ReinforcementLearning -> (Nothing, Just native)
          Matrix.AlphaZero -> (Nothing, Just native)
          Matrix.Tuning -> (Nothing, Nothing)
        source = case Matrix.family row of
          Matrix.Tuning -> Nothing
          _ -> Just (laneGenerationSource value)
     in (Matrix.rowId row, source, fst scopes, snd scopes)

temporary :: (FilePath -> IO a) -> IO a
temporary action = withSystemTempDirectory "jitml-lane-registration" (canonicalizePath >=> action)

writeBytes :: FilePath -> ByteString -> IO ()
writeBytes path bytes = createDirectoryIfMissing True (takeDirectory path) >> ByteString.writeFile path bytes

writeSelection :: FilePath -> LaneRegistrationData -> IO ()
writeSelection root value =
  right (encodeLaneRegistrationData value)
    >>= writeBytes (root </> laneRegistrationPath (laneRegistrationSubstrate value))

writeGeneration :: FilePath -> ByteString -> IO ()
writeGeneration root bytes = writeBytes (root </> Text.unpack (laneGenerationPath (sha256Hex bytes))) bytes

canonical :: Value -> ByteString
canonical = LazyByteString.toStrict . encode

change :: Int -> Value -> ByteString -> ByteString
change index replacement bytes = case eitherDecodeStrict' bytes of
  Right (Array values) -> canonical (Array (Vector.imap (\i value -> if i == index then replacement else value) values))
  _ -> "invalid test fixture"

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure

rejected :: Either e a -> IO ()
rejected = assertBool "hostile ordinary DATA was accepted" . isLeft
