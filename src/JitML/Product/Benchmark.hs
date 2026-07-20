{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Product.Benchmark
  ( runProductRowWallClockBenchmark
  )
where

import Control.Monad (unless, void)
import Control.Monad.Reader (ask, liftIO)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time.Clock.POSIX (getPOSIXTime)
import Data.Vector.Unboxed qualified as VU
import System.Environment (lookupEnv)
import Text.Printf (printf)

import JitML.AppError.AppError (AppError (..))
import JitML.CLI.Output (exitWithError, writeLine, writeText)
import JitML.Env.Env (App)
import JitML.Numerics.Mlp (MlpParams, MlpShape (..), mlpInit)
import JitML.Numerics.MlpDevice (MlpDevice (..), probeMlpDevice)
import JitML.Numerics.MlpDeviceSelect (mlpDeviceForSubstrate)
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Substrate (Substrate (..))

data ProductRowTimingResult = ProductRowTimingResult
  { productTimingRowId :: !Text
  , productTimingShape :: !MlpShape
  , productTimingBatchSize :: !Int
  , productTimingRepetitions :: !Int
  , productTimingCpuSeconds :: !Double
  , productTimingCudaSeconds :: !Double
  }
  deriving stock (Eq, Show)

runProductRowWallClockBenchmark :: App ()
runProductRowWallClockBenchmark = do
  env <- ask
  rowFilterRaw <- liftIO (lookupEnv "JITML_PRODUCT_ROW_FILTER")
  selectedRows <-
    either
      (exitWithError . InvalidConfig)
      pure
      (ProductMatrix.selectProductRows (Text.pack <$> rowFilterRaw))
  let cpuDevice = mlpDeviceForSubstrate LinuxCPU env
      cudaDevice = mlpDeviceForSubstrate LinuxCUDA env
  requireProductTimingProbe "linux-cpu" cpuDevice
  requireProductTimingProbe "linux-cuda" cudaDevice
  results <- traverse (benchmarkProductTimingRow cpuDevice cudaDevice) selectedRows
  let failingRows =
        [ productTimingRowId result
        | result <- results
        , productTimingCudaSeconds result >= productTimingCpuSeconds result
        ]
  writeText $
    Text.unlines
      ( [ "benchmark-product-row-wall-clock: rows=" <> Text.pack (show (length results))
        , "benchmark-product-row-wall-clock: status="
            <> if null failingRows then "PASS" else "FAIL"
        , Text.intercalate
            "\t"
            [ "row_id"
            , "inputs"
            , "hidden"
            , "outputs"
            , "batch"
            , "repetitions"
            , "linux_cpu_seconds"
            , "linux_cuda_seconds"
            , "speedup"
            , "status"
            ]
        ]
          <> fmap renderProductTimingResult results
      )
  unless (null failingRows) $
    exitWithError
      ( InvalidConfig
          ( "benchmark-product-row-wall-clock failed; linux-cuda was not strictly faster for rows: "
              <> Text.intercalate ", " failingRows
          )
      )

requireProductTimingProbe :: Text -> MlpDevice -> App ()
requireProductTimingProbe label device = do
  probe <- liftIO (probeMlpDevice device)
  case probe of
    Left err ->
      exitWithError
        ( InvalidConfig
            ( "benchmark-product-row-wall-clock: "
                <> label
                <> " MLP device probe failed: "
                <> err
            )
        )
    Right () -> pure ()

benchmarkProductTimingRow
  :: MlpDevice
  -> MlpDevice
  -> ProductMatrix.ProductRow 'ProductMatrix.Declared
  -> App ProductRowTimingResult
benchmarkProductTimingRow cpuDevice cudaDevice row = do
  let shape = productRowTimingShape row
  batchSize <- productEnvInt "JITML_PRODUCT_TIMING_BATCH" (productRowTimingDefaultBatch row shape)
  repetitions <- productEnvInt "JITML_PRODUCT_TIMING_REPETITIONS" 4
  let params = mlpInit shape (productRowTimingSeed row)
      inputs = productRowTimingInputs row shape batchSize
      deltas = productRowTimingDeltas row shape batchSize
      gradientBatch = zip inputs deltas
  writeLine
    ( "benchmark-product-row-wall-clock: row="
        <> ProductMatrix.rowId row
        <> " shape="
        <> renderMlpShape shape
        <> " batch="
        <> Text.pack (show batchSize)
        <> " repetitions="
        <> Text.pack (show repetitions)
    )
  requireProductTimingAction
    (ProductMatrix.rowId row <> "/linux-cpu warmup")
    (warmProductTimingDevice cpuDevice params inputs gradientBatch)
  requireProductTimingAction
    (ProductMatrix.rowId row <> "/linux-cuda warmup")
    (warmProductTimingDevice cudaDevice params inputs gradientBatch)
  cpuSeconds <-
    requireProductTimingAction
      (ProductMatrix.rowId row <> "/linux-cpu timing")
      (timeProductTimingDevice cpuDevice params inputs gradientBatch repetitions)
  cudaSeconds <-
    requireProductTimingAction
      (ProductMatrix.rowId row <> "/linux-cuda timing")
      (timeProductTimingDevice cudaDevice params inputs gradientBatch repetitions)
  pure
    ProductRowTimingResult
      { productTimingRowId = ProductMatrix.rowId row
      , productTimingShape = shape
      , productTimingBatchSize = batchSize
      , productTimingRepetitions = repetitions
      , productTimingCpuSeconds = cpuSeconds
      , productTimingCudaSeconds = cudaSeconds
      }

requireProductTimingAction :: Text -> IO (Either Text a) -> App a
requireProductTimingAction label action = do
  result <- liftIO action
  case result of
    Left err ->
      exitWithError
        ( InvalidConfig
            ( "benchmark-product-row-wall-clock: "
                <> label
                <> " failed: "
                <> err
            )
        )
    Right value -> pure value

warmProductTimingDevice
  :: MlpDevice
  -> MlpParams
  -> [VU.Vector Double]
  -> [(VU.Vector Double, VU.Vector Double)]
  -> IO (Either Text ())
warmProductTimingDevice device params inputs gradientBatch =
  void <$> runProductTimingIteration device params inputs gradientBatch

timeProductTimingDevice
  :: MlpDevice
  -> MlpParams
  -> [VU.Vector Double]
  -> [(VU.Vector Double, VU.Vector Double)]
  -> Int
  -> IO (Either Text Double)
timeProductTimingDevice device params inputs gradientBatch repetitions = do
  start <- getPOSIXTime
  runResult <- go repetitions
  end <- getPOSIXTime
  let elapsed = fromRational (toRational (end - start))
  pure (elapsed <$ runResult)
 where
  go remaining
    | remaining <= 0 = pure (Right ())
    | otherwise = do
        result <- runProductTimingIteration device params inputs gradientBatch
        case result of
          Left err -> pure (Left err)
          Right () -> go (remaining - 1)

runProductTimingIteration
  :: MlpDevice
  -> MlpParams
  -> [VU.Vector Double]
  -> [(VU.Vector Double, VU.Vector Double)]
  -> IO (Either Text ())
runProductTimingIteration device params inputs gradientBatch = do
  forward <- mlpdForwardBatch device params inputs
  case forward of
    Left err -> pure (Left err)
    Right outputs
      | length outputs /= length inputs ->
          pure (Left "forward batch returned an unexpected output count")
      | otherwise -> do
          gradient <- mlpdBatchGradient device params gradientBatch
          pure (void gradient)

productRowTimingShape :: ProductMatrix.ProductRow state -> MlpShape
productRowTimingShape row =
  case ProductMatrix.rowId row of
    "mnist-shallow-mlp" -> MlpShape 784 64 10
    "mnist-deep-mlp" -> MlpShape 784 128 10
    "mnist-lenet" -> MlpShape 784 96 10
    "fashion-mnist-mlp" -> MlpShape 784 96 10
    "fashion-mnist-resnet" -> MlpShape 784 160 10
    "cifar10-resnet20" -> MlpShape 3072 192 10
    "cifar10-resnet56" -> MlpShape 3072 256 10
    "cifar100-wide-resnet" -> MlpShape 3072 256 100
    "cifar10-vit" -> MlpShape 3072 256 10
    "tiny-imagenet-resnet50" -> MlpShape 3072 320 200
    "california-housing-mlp" -> MlpShape 8 96 1
    _ ->
      case ProductMatrix.rowClass row of
        ProductMatrix.RlAlgorithmEnvironment algorithm environment ->
          productRowTimingRlShape algorithm environment
        ProductMatrix.RlGoalConditioned environment ->
          productRowTimingGoalShape environment
        ProductMatrix.AlphaZeroGame game ->
          productRowTimingAlphaZeroShape game
        ProductMatrix.HyperparameterTuning _ ->
          MlpShape 784 128 10
        ProductMatrix.SupervisedClassification _ _ ->
          MlpShape 784 128 10
        ProductMatrix.SupervisedRegression _ _ ->
          MlpShape 8 96 1

productRowTimingRlShape :: Text -> Text -> MlpShape
productRowTimingRlShape algorithm environment =
  let (inputs, outputs) = productRowTimingRlDims algorithm environment
   in MlpShape inputs 128 outputs

productRowTimingRlDims :: Text -> Text -> (Int, Int)
productRowTimingRlDims algorithm environment
  | algorithm `elem` ["DDPG", "TD3", "SAC", "CrossQ", "TQC"] =
      case environment of
        "pendulum" -> (3, 1)
        "lunar-lander" -> (8, 2)
        _ -> discreteDims environment
  | otherwise = discreteDims environment
 where
  discreteDims "cartpole" = (4, 2)
  discreteDims "mountain-car" = (2, 3)
  discreteDims "acrobot" = (6, 3)
  discreteDims "lunar-lander" = (8, 4)
  discreteDims "key-door-grid" = (16, 4)
  discreteDims "gridworld-deterministic" = (8, 4)
  discreteDims "pendulum" = (3, 3)
  discreteDims _ = (8, 4)

productRowTimingGoalShape :: Text -> MlpShape
productRowTimingGoalShape "goal-reaching" = MlpShape 6 128 4
productRowTimingGoalShape _ = MlpShape 8 128 4

productRowTimingAlphaZeroShape :: Text -> MlpShape
productRowTimingAlphaZeroShape "connect4" = MlpShape 42 160 8
productRowTimingAlphaZeroShape "othello" = MlpShape 64 192 65
productRowTimingAlphaZeroShape "hex" = MlpShape 121 224 122
productRowTimingAlphaZeroShape "gomoku" = MlpShape 225 256 226
productRowTimingAlphaZeroShape _ = MlpShape 64 192 65

productRowTimingDefaultBatch :: ProductMatrix.ProductRow state -> MlpShape -> Int
productRowTimingDefaultBatch row shape =
  case ProductMatrix.family row of
    ProductMatrix.Supervised
      | mlpInputs shape >= 3000 -> 512
      | otherwise -> 2048
    ProductMatrix.ReinforcementLearning -> 65536
    ProductMatrix.AlphaZero -> 4096
    ProductMatrix.Tuning -> 2048

productRowTimingSeed :: ProductMatrix.ProductRow state -> Int
productRowTimingSeed row =
  1
    + ( Text.foldl'
          (\acc ch -> (acc * 33 + fromEnum ch) `mod` 2147483646)
          (17 :: Int)
          (ProductMatrix.rowId row)
          `mod` 2147483646
      )

productRowTimingInputs :: ProductMatrix.ProductRow state -> MlpShape -> Int -> [VU.Vector Double]
productRowTimingInputs row shape batchSize =
  [ VU.generate
      (mlpInputs shape)
      (deterministicTimingValue (productRowTimingSeed row) sampleIndex)
  | sampleIndex <- [0 .. batchSize - 1]
  ]

productRowTimingDeltas :: ProductMatrix.ProductRow state -> MlpShape -> Int -> [VU.Vector Double]
productRowTimingDeltas row shape batchSize =
  [ VU.generate
      (mlpOutputs shape)
      (deterministicTimingValue (productRowTimingSeed row + 104729) sampleIndex)
  | sampleIndex <- [0 .. batchSize - 1]
  ]

deterministicTimingValue :: Int -> Int -> Int -> Double
deterministicTimingValue seed sampleIndex featureIndex =
  let raw =
        ( seed
            + 1103515245 * (sampleIndex + 1)
            + 12345 * (featureIndex + 3)
        )
          `mod` 2003
   in (fromIntegral raw / 1001.5) - 1.0

renderProductTimingResult :: ProductRowTimingResult -> Text
renderProductTimingResult result =
  Text.intercalate
    "\t"
    [ productTimingRowId result
    , Text.pack (show (mlpInputs shape))
    , Text.pack (show (mlpHidden shape))
    , Text.pack (show (mlpOutputs shape))
    , Text.pack (show (productTimingBatchSize result))
    , Text.pack (show (productTimingRepetitions result))
    , renderTimingDouble (productTimingCpuSeconds result)
    , renderTimingDouble (productTimingCudaSeconds result)
    , renderTimingDouble (productTimingCpuSeconds result / productTimingCudaSeconds result)
    , if productTimingCudaSeconds result < productTimingCpuSeconds result then "PASS" else "FAIL"
    ]
 where
  shape = productTimingShape result

renderMlpShape :: MlpShape -> Text
renderMlpShape shape =
  Text.intercalate
    "x"
    [ Text.pack (show (mlpInputs shape))
    , Text.pack (show (mlpHidden shape))
    , Text.pack (show (mlpOutputs shape))
    ]

renderTimingDouble :: Double -> Text
renderTimingDouble value =
  Text.pack (printf "%.6f" value)

productEnvInt :: String -> Int -> App Int
productEnvInt name fallback = do
  raw <- liftIO (lookupEnv name)
  let rendered =
        case raw of
          Just value | not (null value) -> Text.pack value
          _ -> Text.pack (show fallback)
      parsed =
        case reads (Text.unpack rendered) of
          [(value, "")] -> value
          _ -> fallback
  pure (max 1 parsed)
