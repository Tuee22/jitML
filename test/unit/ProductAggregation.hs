{-# LANGUAGE OverloadedStrings #-}

module ProductAggregation (productAggregationTests) where

import Data.Aeson (Value (..), eitherDecodeStrict', encode)
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Foldable (traverse_)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector qualified as Vector
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Checkpoint.WeightCodec qualified as WeightCodec
import JitML.Plan.Plan (Validation (..))
import JitML.Product.Matrix qualified as Product
import JitML.Substrate (Substrate (..))
import JitML.Test.ProductAggregation qualified as Aggregate
import JitML.Test.ProductLaneJournal qualified as Lane
import JitML.Training.Budget qualified as Budget

type Inputs = [(Aggregate.ProductLaneInput, ByteString)]

productAggregationTests :: TestTree
productAggregationTests =
  testGroup
    "Journal-derived product aggregation (Phase 276)"
    ( [ testCase "all real retained lanes join in product order with lane-specific plans" $ do
          inputs <- loadInputs
          aggregate <- requireRight (Aggregate.aggregateProductLaneJournals inputs)
          let rows = Aggregate.productAggregationRows aggregate
          fmap Aggregate.productAggregateRowId rows @?= Product.productRowIds
          Aggregate.productAggregationCellCount aggregate @?= 3 * length Product.productRowIds
          traverse_
            ( \row ->
                fmap Lane.productLaneJournalRowSubstrate (Aggregate.productAggregateRowLanes row)
                  @?= [LinuxCPU, LinuxCUDA, AppleSilicon]
            )
            rows
      , testCase "source ordering cannot change the canonical report" $ do
          inputs <- loadInputs
          forward <- requireRight (Aggregate.aggregateProductLaneJournals inputs)
          backward <- requireRight (Aggregate.aggregateProductLaneJournals (reverse inputs))
          Aggregate.productAggregationBytes forward @?= Aggregate.productAggregationBytes backward
      , testCase "retained aggregate bytes are the exact current typed projection" $ do
          aggregate <- Aggregate.readRetainedProductAggregation >>= requireRight
          inputs <- loadInputs
          Aggregate.admitProductAggregation inputs (Aggregate.productAggregationBytes aggregate)
            @?= Right aggregate
      , testCase "report values come from refined measurements and completed counters" $ do
          aggregate <- Aggregate.loadProductAggregation >>= requireRight
          raw <- requireRight (eitherDecodeStrict' (Aggregate.productAggregationBytes aggregate))
          case Aggregate.productAggregationRows aggregate of
            [] -> assertFailure "complete aggregate has no rows"
            row : _ -> case Aggregate.productAggregateRowLanes row of
              [] -> assertFailure "complete aggregate has no lanes"
              cell : _ -> do
                let completed = Lane.productLaneJournalRowCompletedTraining cell
                    expectedUnits = Number (fromIntegral (Budget.completedTrainingObservedUnits completed))
                    expectedUpdates = Number (fromIntegral (Budget.completedTrainingUpdateCount completed))
                rawRows <- getField "rows" raw >>= firstValue
                rawCell <- getField "lanes" rawRows >>= firstValue
                getField "observed_units" rawCell >>= (@?= expectedUnits)
                getField "update_count" rawCell >>= (@?= expectedUpdates)
                getField "completed_training" rawCell >>= (@?= String (Budget.renderCompletedTraining completed))
                case Budget.completedTrainingMetrics completed of
                  [] -> assertFailure "refined completion has no metrics"
                  metric : _ -> do
                    rawMetric <- getField "metrics" rawCell >>= firstValue
                    expected <-
                      requireRight (eitherDecodeStrict' (LazyByteString.toStrict (encode (Budget.coMetricValue metric))))
                    getField "value" rawMetric >>= (@?= expected)
                    getField "passed" rawMetric >>= (@?= Bool (Budget.convergencePassed metric))
      , testCase "missing journal produces a typed IO failure" $
          withSystemTempDirectory "jitml-aggregate-missing" $ \root -> do
            let inputs =
                  fmap
                    (\input -> input {Aggregate.productLaneInputPath = root </> "absent.json"})
                    Aggregate.productLaneInputs
            result <- Aggregate.loadProductAggregationFrom inputs
            case result of
              Left errors -> assertBool "IO failure is retained" (any isIOFailure errors)
              Right _ -> assertFailure "missing files admitted"
      , testCase "a digest computed from altered bytes cannot replace the external pin" $ do
          inputs <- loadInputs
          case inputs of
            [] -> assertFailure "no lane inputs"
            (input, bytes) : rest ->
              assertRejected (Aggregate.aggregateProductLaneJournals ((input, bytes <> " ") : rest))
      , testCase "noncanonical JSON is rejected even with a matching digest" $ do
          inputs <- loadInputs
          case inputs of
            [] -> assertFailure "no lane inputs"
            (input, bytes) : rest -> do
              let altered = bytes <> " "
                  repinned = input {Aggregate.productLaneInputSha256 = digest altered}
              assertLaneRejected ((repinned, altered) : rest)
      , testCase "aggregate authority cannot be replaced by caller-supplied pins or paths" $ do
          inputs <- loadInputs
          case inputs of
            [] -> assertFailure "no lane inputs"
            (input, bytes) : rest ->
              traverse_
                ( \changed -> case Aggregate.aggregateProductLaneJournals ((changed, bytes) : rest) of
                    Left errors -> assertBool "unregistered authority rejected" (any isUnregisteredInput errors)
                    Right _ -> assertFailure "caller-supplied authority admitted"
                )
                [ input {Aggregate.productLaneInputSha256 = zeroDigest}
                , input {Aggregate.productLaneInputPath = "invented-source.json"}
                ]
      ]
        <> [ testCase ("missing lane " <> show lane) $ do
               inputs <- loadInputs
               assertRejected
                 ( Aggregate.aggregateProductLaneJournals
                     (filter ((/= lane) . Aggregate.productLaneInputSubstrate . fst) inputs)
                 )
           | lane <- [LinuxCPU, LinuxCUDA, AppleSilicon]
           ]
        <> [ testCase ("duplicate lane " <> show lane) $ do
               inputs <- loadInputs
               let duplicate = filter ((== lane) . Aggregate.productLaneInputSubstrate . fst) inputs
               assertRejected (Aggregate.aggregateProductLaneJournals (inputs <> duplicate))
           | lane <- [LinuxCPU, LinuxCUDA, AppleSilicon]
           ]
        <> [ testCase ("lane reader rejects repinned " <> label) $ do
               inputs <- loadInputs
               tampered <- tamperInput mutation inputs
               assertLaneRejected tampered
           | (label, mutation) <- journalMutations
           ]
        <> [ testCase ("aggregate rejects altered " <> Text.unpack field) $ do
               inputs <- loadInputs
               aggregate <- requireRight (Aggregate.aggregateProductLaneJournals inputs)
               raw <- requireRight (eitherDecodeStrict' (Aggregate.productAggregationBytes aggregate))
               assertRejected (Aggregate.admitProductAggregation inputs (canonical (setField field value raw)))
           | (field, value) <-
               [ ("version", Number 2)
               , ("row_count", Number 0)
               , ("completed_cell_count", Number 0)
               , ("sources", Array Vector.empty)
               , ("rows", Array Vector.empty)
               ]
           ]
    )

journalMutations :: [(String, Value -> Value)]
journalMutations =
  [ ("missing row", mapRows (Vector.drop 1))
  , ("duplicate row", mapRows (\rows -> rows <> Vector.take 1 rows))
  , ("row order drift", mapRows Vector.reverse)
  , ("unknown row", firstRow (setField "row_id" (String "unknown-product")))
  , ("non-product row", firstRow (setField "row_id" (String "tic-tac-toe")))
  , ("ordinal drift", firstRow (setField "ordinal" (Number 2)))
  , ("wrong top-level lane", setField "substrate" (String "apple-silicon"))
  , ("wrong row lane", firstRow (setField "substrate" (String "apple-silicon")))
  , ("wrong plan", firstRow (setField "plan_id" (String zeroDigest)))
  , ("wrong checkpoint", firstRow (setField "admitted_manifest_sha256" (String zeroDigest)))
  , ("wrong inference checkpoint", firstRow (setField "inference_manifest_sha256" (String zeroDigest)))
  , ("wrong contract", firstRow (setField "contract_sha256" (String zeroDigest)))
  , ("wrong measurement digest", firstRow (setField "measured_sha256" (String zeroDigest)))
  , ("wrong invocation", firstRow (setField "invocation_sha256" (String zeroDigest)))
  ,
    ( "wrong device witness"
    , firstRow (setField "device_witness" (String "device:apple-silicon:invented"))
    )
  , ("malformed completion", firstRow (setField "completed_training" (String "00")))
  , ("failed row", firstRow (setField "status" (String "Failed")))
  , ("not-run row", firstRow (setField "status" (String "NotRun")))
  , ("unknown field", setField "extra" Null)
  , ("unknown version", setField "version" (Number 9))
  ]

loadInputs :: IO Inputs
loadInputs = traverse load Aggregate.productLaneInputs
 where
  load input = do
    bytes <- ByteString.readFile (Aggregate.productLaneInputPath input)
    pure (input, bytes)

tamperInput :: (Value -> Value) -> Inputs -> IO Inputs
tamperInput mutation inputs = case inputs of
  [] -> assertFailure "no lane inputs" >> pure []
  (input, bytes) : rest -> do
    raw <- requireRight (eitherDecodeStrict' bytes)
    let altered = canonical (mutation raw)
    assertBool "mutation must change bytes" (altered /= bytes)
    pure ((input {Aggregate.productLaneInputSha256 = digest altered}, altered) : rest)

canonical :: Value -> ByteString
canonical value = LazyByteString.toStrict (encode value) <> "\n"

digest :: ByteString -> Text
digest = WeightCodec.jmw1ContentSha . LazyByteString.fromStrict

zeroDigest :: Text
zeroDigest = Text.replicate 64 "0"

setField :: Text -> Value -> Value -> Value
setField field value (Object record) = Object (KeyMap.insert (Key.fromText field) value record)
setField _ _ value = value

mapRows :: (Vector.Vector Value -> Vector.Vector Value) -> Value -> Value
mapRows change raw@(Object record) =
  case KeyMap.lookup "rows" record of
    Just (Array rows) -> setField "rows" (Array (change rows)) raw
    _ -> raw
mapRows _ raw = raw

firstRow :: (Value -> Value) -> Value -> Value
firstRow change = mapRows (Vector.imap (\index row -> if index == 0 then change row else row))

requireRight :: (Show error) => Either error value -> IO value
requireRight result = case result of
  Left failure -> assertFailure (show failure) >> fail "assertFailure returned"
  Right value -> pure value

assertRejected :: (Show value) => Either error value -> Assertion
assertRejected result = case result of
  Left _ -> pure ()
  Right value -> assertFailure ("unexpectedly admitted: " <> show value)

isIOFailure :: Aggregate.ProductAggregationError -> Bool
isIOFailure Aggregate.ProductAggregationIOFailure {} = True
isIOFailure _ = False

isUnregisteredInput :: Aggregate.ProductAggregationError -> Bool
isUnregisteredInput Aggregate.ProductAggregationUnregisteredInput {} = True
isUnregisteredInput _ = False

assertLaneRejected :: Inputs -> Assertion
assertLaneRejected inputs = case inputs of
  [] -> assertFailure "no lane input to challenge"
  (input, bytes) : _ ->
    case Product.projectProductRows (Aggregate.productLaneInputSubstrate input) Product.allProductRows of
      Failure errors -> assertFailure (show errors)
      Success batch ->
        assertRejected (Lane.admitProductLaneJournal (Aggregate.productLaneInputSha256 input) batch bytes)

getField :: Text -> Value -> IO Value
getField name (Object record) =
  maybe
    (assertFailure ("missing field " <> Text.unpack name) >> pure Null)
    pure
    (KeyMap.lookup (Key.fromText name) record)
getField _ _ = assertFailure "expected object" >> pure Null

firstValue :: Value -> IO Value
firstValue (Array values) =
  maybe (assertFailure "empty array" >> pure Null) pure (values Vector.!? 0)
firstValue _ = assertFailure "expected array" >> pure Null
