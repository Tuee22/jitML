{-# LANGUAGE OverloadedStrings #-}

module ProductAggregation (productAggregationTests) where

import Data.Aeson (Value (..), eitherDecodeStrict', encode)
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Foldable (traverse_)
import Data.List (find)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Maybe (fromMaybe)
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
import JitML.Test.Report qualified as Report
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
        <> [ testCase
               ("learning-signal policy invalidates exactly historical supervised contracts on " <> show lane)
               $ do
                 inputs <- loadInputs
                 historicalSupervisedContractsAreStale lane inputs
           | lane <- [LinuxCPU, LinuxCUDA]
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

-- Immutable identities from before the additional learning-signal policy.
-- These are contract fixtures, never model measurements. Historical lane wire
-- bytes remain obsolete and are never upgraded or admitted. Only their raw
-- row-contract table is inspected by the production structural predicate;
-- non-supervised contract values remain exactly those in the retained bytes.
historicalSupervisedContracts :: [(Text, Text)]
historicalSupervisedContracts =
  [ ("mnist-shallow-mlp", "07784be77e793ed7ec294fe7f93636f32f2d3603bea04f2c97cf87c68f4e1dc0")
  , ("mnist-deep-mlp", "d826bc8f21119432d814d354854335e5a7deee1dcbca66b386ba4a0da56dd152")
  , ("mnist-lenet", "be5ffee81b8794ff09472993cc69e96d47a16db5c28f8f275ab9e9ab44653aad")
  , ("fashion-mnist-mlp", "a57dce6302154b6c4f5e5b064fc6a74b90c99714e9990d8483590decc049b2d8")
  , ("fashion-mnist-resnet", "7941b55a68b70acf62e227dda5c57d163574d84ec8232c90a6cb758cd922e130")
  , ("cifar10-resnet20", "c6af93984b9f1a0e3e139cff389c020a2c312d57b6a893ef894b464652b3c4b4")
  , ("cifar10-resnet56", "f6c7d951ac261285b93ebff98ef85b80d227980597a3caa158927cb9921029e4")
  , ("cifar100-wide-resnet", "046c54435fc58d05fe92b3fd954c86eeb8013b810ecc547717b81937a0cd3826")
  , ("cifar10-vit", "5c0144b7345e6fe430b8e9e9a1c652a81dc977c9f98e468ff74a0d3a4df3bc2b")
  , ("tiny-imagenet-resnet50", "05eab9ec181d0a6a89b6cfce3e9b79e15e6e564b257237a9e6518a0db029b6c6")
  , ("california-housing-mlp", "71718269cda5092bb9c59a7173999bffcb3f9abe00a68bb03b6059cca1bb4673")
  ]

historicalSupervisedContractsAreStale :: Substrate -> Inputs -> Assertion
historicalSupervisedContractsAreStale lane inputs = do
  let supervisedIds =
        [ Product.rowId row
        | row <- Product.allProductRows
        , Product.family row == Product.Supervised
        ]
  length supervisedIds @?= 11
  fmap fst historicalSupervisedContracts @?= supervisedIds
  (input, bytes) <-
    maybe
      (assertFailure ("missing retained " <> show lane <> " journal") >> fail "unreachable")
      pure
      (find ((== lane) . Aggregate.productLaneInputSubstrate . fst) inputs)
  digest bytes @?= Aggregate.productLaneInputSha256 input
  batch <-
    case Product.projectProductRows lane Product.allProductRows of
      Failure errors -> assertFailure (show errors) >> fail "unreachable"
      Success projected -> pure projected
  -- Obsolete real evidence remains rejected before row parsing. Nothing below
  -- upgrades its version, rewrites it on disk, or mints an admitted journal.
  case Lane.admitProductLaneJournal (digest bytes) batch bytes of
    Right _ -> assertFailure "historical lane wire admitted under the current qualification contract"
    Left failures ->
      NonEmpty.toList failures @?= [Lane.ProductLaneJournalWireStale Lane.productLaneJournalWireVersion 1]
  let projections = Product.productProjectionBatchProjections batch
  traverse_
    ( \(Product.SomeProductProjection _ projection) ->
        Lane.validateProductLaneContract
          projection
          (Report.productScenarioProjectionContractDigest projection)
          @?= Right ()
    )
    projections
  raw <- requireRight (eitherDecodeStrict' bytes)
  rowValues <- getField "rows" raw
  rawRows <- case rowValues of
    Array values -> pure (Vector.toList values)
    _ -> assertFailure "retained contract table has no row array" >> fail "unreachable"
  contracts <- traverse readContract rawRows
  fmap fst contracts @?= Product.productProjectionBatchRowIds batch
  let errors = concat (zipWith checkContract projections contracts)
      staleContracts =
        [ (rowId, current, historical)
        | Lane.ProductLaneJournalContractStale rowId current historical <- errors
        ]
  fmap (\(rowId, _, _) -> rowId) staleContracts @?= supervisedIds
  length errors @?= length staleContracts
  traverse_
    ( \(rowId, current, historical) -> do
        lookup rowId historicalSupervisedContracts @?= Just historical
        assertBool
          "current supervised contract differs from its historical identity"
          (current /= historical)
    )
    staleContracts
 where
  -- Retain all real non-supervised contract values. Override only the eleven
  -- named historical SL constants, exactly as the original contract control did.
  -- This is a raw value table, not a current-wire or authenticated fixture.
  readContract raw = do
    row <- getField "row_id" raw
    contract <- getField "contract_sha256" raw
    case (row, contract) of
      (String rowId, String observed) ->
        pure (rowId, fromMaybe observed (lookup rowId historicalSupervisedContracts))
      _ ->
        assertFailure "retained contract table has a malformed row identity/digest" >> fail "unreachable"
  checkContract (Product.SomeProductProjection _ projection) (_, observed) =
    either (: []) (const []) (Lane.validateProductLaneContract projection observed)

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
