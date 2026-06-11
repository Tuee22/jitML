{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TupleSections #-}

-- | Sprint 13.4 — real differentiable supervised-learning classifier
-- wired through the pure-Haskell network seam in "JitML.Numerics.Mlp".
-- This closes the "SL training network seam" the live MNIST convergence
-- assertion needs: a softmax-cross-entropy MLP that trains on labeled
-- examples with Adam and reports train/test accuracy.
--
-- The module is substrate-portable and bit-deterministic on the same
-- seed (per the determinism contract). The IDX parser
-- ('parseIdxImages' / 'parseIdxLabels') decodes the canonical MNIST
-- on-disk format so the classifier can consume the real
-- `train-images-idx3-ubyte` / `train-labels-idx1-ubyte` payloads
-- uploaded to MinIO by `jitml internal upload-dataset` (Sprint 13.4
-- upload half).
--
-- The classifier reuses the policy head of 'JitML.Numerics.Mlp' as a
-- softmax output over @numClasses@ logits; the cross-entropy gradient
-- @softmax - onehot@ is identical to the AlphaZero policy gradient, so
-- the same backward path is exercised.
module JitML.SL.Classifier
  ( -- * Labeled examples
    LabeledExample (..)
  , Dataset

    -- * IDX parsing (canonical MNIST format)
  , parseIdxImages
  , parseIdxLabels
  , zipImagesLabels

    -- * Classifier
  , ClassifierConfig (..)
  , defaultClassifierConfig
  , TrainedClassifier (..)
  , trainClassifier
  , trainClassifierFromIdx
  , trainClassifierFromIdxBounded
  , classify
  , accuracy
  , crossEntropyLoss

    -- * Substrate-backed classifier (Sprint 8.10)
  , trainClassifierWithDevice
  , trainClassifierWithDeviceFromIdxBounded
  , classifyWithDevice
  , accuracyWithDevice
  )
where

import Control.Monad (foldM)
import Data.Bits (shiftL, (.|.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.List qualified
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU

import JitML.Numerics.Mlp
  ( AdamConfig (..)
  , MlpGradient (..)
  , MlpParams
  , MlpShape (..)
  , PolicyValueOutput (..)
  , adamInit
  , adamStep
  , defaultAdamConfig
  , mlpInit
  , policyValueBackward
  , policyValueForward
  , softmax
  )
import JitML.Numerics.MlpDevice
  ( MlpDevice (..)
  )

-- | One labeled example: a flat feature vector plus an integer class label.
data LabeledExample = LabeledExample
  { exampleFeatures :: !(Vector Double)
  , exampleLabel :: !Int
  }
  deriving stock (Eq, Show)

type Dataset = [LabeledExample]

-- | Parse the canonical IDX3 image format (magic @0x00000803@): a
-- 4-byte magic, 4-byte image count, 4-byte rows, 4-byte cols, then
-- @count * rows * cols@ unsigned bytes. Each image is flattened
-- row-major and scaled to @[0, 1]@. Returns @(rows*cols, [image])@.
parseIdxImages :: ByteString -> Either String (Int, [Vector Double])
parseIdxImages bytes
  | ByteString.length bytes < 16 = Left "idx images: header too short"
  | magic /= 0x0803 = Left ("idx images: bad magic " <> show magic)
  | otherwise = Right (rows * cols, images)
 where
  magic = be32 bytes 0
  count = be32 bytes 4
  rows = be32 bytes 8
  cols = be32 bytes 12
  pixelsPer = rows * cols
  body = ByteString.drop 16 bytes
  images =
    [ VU.generate
        pixelsPer
        ( \j ->
            fromIntegral (ByteString.index body (i * pixelsPer + j)) / 255.0
        )
    | i <- [0 .. count - 1]
    , (i + 1) * pixelsPer <= ByteString.length body
    ]

-- | Parse the canonical IDX1 label format (magic @0x00000801@): a
-- 4-byte magic, 4-byte count, then @count@ unsigned label bytes.
parseIdxLabels :: ByteString -> Either String [Int]
parseIdxLabels bytes
  | ByteString.length bytes < 8 = Left "idx labels: header too short"
  | magic /= 0x0801 = Left ("idx labels: bad magic " <> show magic)
  | otherwise = Right labels
 where
  magic = be32 bytes 0
  count = be32 bytes 4
  body = ByteString.drop 8 bytes
  labels =
    [ fromIntegral (ByteString.index body i)
    | i <- [0 .. count - 1]
    , i < ByteString.length body
    ]

-- | Combine parsed images and labels into labeled examples (truncating
-- to the shorter of the two).
zipImagesLabels :: [Vector Double] -> [Int] -> Dataset
zipImagesLabels images labels =
  [LabeledExample img lbl | (img, lbl) <- zip images labels]

-- | Big-endian 32-bit read at a byte offset.
be32 :: ByteString -> Int -> Int
be32 bs off =
  (fromIntegral (ByteString.index bs off) `shiftL` 24)
    .|. (fromIntegral (ByteString.index bs (off + 1)) `shiftL` 16)
    .|. (fromIntegral (ByteString.index bs (off + 2)) `shiftL` 8)
    .|. fromIntegral (ByteString.index bs (off + 3))

-- | Classifier configuration.
data ClassifierConfig = ClassifierConfig
  { clfSeed :: !Int
  , clfInputs :: !Int
  , clfHidden :: !Int
  , clfClasses :: !Int
  , clfEpochs :: !Int
  , clfLearningRate :: !Double
  }
  deriving stock (Eq, Show)

defaultClassifierConfig :: ClassifierConfig
defaultClassifierConfig =
  ClassifierConfig
    { clfSeed = 42
    , clfInputs = 784
    , clfHidden = 128
    , clfClasses = 10
    , clfEpochs = 5
    , clfLearningRate = 1.0e-3
    }

data TrainedClassifier = TrainedClassifier
  { trainedParams :: !MlpParams
  , trainedConfig :: !ClassifierConfig
  }
  deriving stock (Eq, Show)

-- | Train the classifier for @clfEpochs@ full passes over the dataset
-- via Adam on the softmax cross-entropy loss. The traversal order is
-- the dataset order (deterministic); same seed + same data → identical
-- parameters.
trainClassifier :: ClassifierConfig -> Dataset -> TrainedClassifier
trainClassifier config dataset =
  let shape =
        MlpShape
          { mlpInputs = clfInputs config
          , mlpHidden = clfHidden config
          , mlpOutputs = clfClasses config + 1
          }
      params0 = mlpInit shape (clfSeed config)
      adam0 = adamInit shape
      adamConfig = defaultAdamConfig {adamLearningRate = clfLearningRate config}
      stepOne (params, adam) example =
        let pv = policyValueForward params (clfClasses config) (exampleFeatures example)
            probs = pvPolicy pv
            -- cross-entropy gradient w.r.t. logits = softmax - onehot
            dLogits =
              VU.imap
                (\i p -> p - if i == exampleLabel example then 1.0 else 0.0)
                probs
            grad = policyValueBackward params pv dLogits 0.0
         in adamStep adamConfig adam params grad
      runEpoch (params, adam) _epoch =
        Data.List.foldl' stepOne (params, adam) dataset
      (finalParams, _) =
        Data.List.foldl' runEpoch (params0, adam0) [1 .. clfEpochs config]
   in TrainedClassifier {trainedParams = finalParams, trainedConfig = config}

-- | Predict the class of a single feature vector (argmax of softmax).
classify :: TrainedClassifier -> Vector Double -> Int
classify trained features =
  let pv =
        policyValueForward
          (trainedParams trained)
          (clfClasses (trainedConfig trained))
          features
      probs = pvPolicy pv
   in VU.maxIndex probs

-- | Fraction of correctly-classified examples in @[0, 1]@.
accuracy :: TrainedClassifier -> Dataset -> Double
accuracy _ [] = 0.0
accuracy trained dataset =
  let correct =
        length
          [ ()
          | example <- dataset
          , classify trained (exampleFeatures example) == exampleLabel example
          ]
   in fromIntegral correct / fromIntegral (length dataset)

-- | Mean softmax cross-entropy loss over the dataset.
crossEntropyLoss :: TrainedClassifier -> Dataset -> Double
crossEntropyLoss _ [] = 0.0
crossEntropyLoss trained dataset =
  let lossOne example =
        let pv =
              policyValueForward
                (trainedParams trained)
                (clfClasses (trainedConfig trained))
                (exampleFeatures example)
            probs = pvPolicy pv
            p = probs VU.! exampleLabel example
         in if p <= 0 then 1.0e9 else negate (log p)
   in sum (map lossOne dataset) / fromIntegral (length dataset)

-- | Sprint 13.4 — the end-to-end training entry point the worker's
-- @jitml train@ command drives over real MNIST: parse the canonical IDX3
-- image bytes and IDX1 label bytes, zip them into a 'Dataset', train the
-- softmax classifier, and return the trained model plus its train-set
-- accuracy. The input width (@clfInputs@) is taken from the parsed image
-- dimensions so the network shape matches the data. Pure and
-- bit-deterministic on the same seed; the worker fetches the two byte
-- blobs from MinIO and the rest is this function.
trainClassifierFromIdx
  :: ClassifierConfig
  -> ByteString
  -- ^ raw IDX3 image bytes (@data.bin@)
  -> ByteString
  -- ^ raw IDX1 label bytes (@labels.bin@)
  -> Either String (TrainedClassifier, Double)
trainClassifierFromIdx config = trainClassifierFromIdxBounded config Nothing

-- | Bounded variant of 'trainClassifierFromIdx': train over at most
-- @limit@ examples (drawn in dataset order) when @Just limit@ is supplied.
-- The full 60k-example MNIST pass under the pure-Haskell MLP is
-- operationally heavy; the worker's @jitml train@ caps the example count
-- (via @JITML_SL_TRAIN_LIMIT@) so a live cluster run is tractable while
-- still exercising the real fetch → IDX parse → differentiable train path.
-- Returns the trained model and its accuracy over the (possibly bounded)
-- training subset.
trainClassifierFromIdxBounded
  :: ClassifierConfig
  -> Maybe Int
  -> ByteString
  -- ^ raw IDX3 image bytes (@data.bin@)
  -> ByteString
  -- ^ raw IDX1 label bytes (@labels.bin@)
  -> Either String (TrainedClassifier, Double)
trainClassifierFromIdxBounded config subsetLimit imageBytes labelBytes = do
  (pixelsPer, images) <- parseIdxImages imageBytes
  labels <- parseIdxLabels labelBytes
  let full = zipImagesLabels images labels
      dataset = case subsetLimit of
        Just limit | limit >= 0 -> take limit full
        _ -> full
  if null dataset
    then Left "idx: produced no labeled examples (empty images or labels)"
    else
      let trainedConfigForData = config {clfInputs = pixelsPer}
          trained = trainClassifier trainedConfigForData dataset
       in Right (trained, accuracy trained dataset)

-- | Sprint 8.10 — the substrate-backed classifier trainer. This mirrors
-- 'JitML.RL.AlphaZero.PolicyValueNet.trainPolicyValueNetOnSamplesWithDevice':
-- the network forward and the batched parameter gradient run on the injected
-- JIT-compiled 'MlpDevice' (oneDNN / CUDA / Metal), while the softmax
-- cross-entropy head and the Adam update stay on the host. The classifier
-- reuses the AlphaZero policy/value head — @clfClasses + 1@ outputs, the first
-- @clfClasses@ softmaxed into class probabilities and the trailing slot an
-- unused value head whose loss gradient is zero — so the @softmax − onehot@
-- output gradient is identical to the policy gradient the device backward path
-- already serves.
--
-- There is __no pure-Haskell fallback__: a device 'Left' (toolchain/hardware
-- absent, compile failure) propagates as a 'Left', so the worker path fails
-- closed rather than silently degrading to the reference 'trainClassifier'.
-- Each epoch is one full-batch forward + one batched gradient + one Adam step;
-- same seed + same data + same substrate ⇒ identical parameters.
trainClassifierWithDevice
  :: MlpDevice
  -> ClassifierConfig
  -> Dataset
  -> IO (Either Text (TrainedClassifier, Double))
trainClassifierWithDevice device config dataset
  | null dataset = pure (Left "trainClassifierWithDevice: empty dataset")
  | otherwise = do
      let shape =
            MlpShape
              { mlpInputs = clfInputs config
              , mlpHidden = clfHidden config
              , mlpOutputs = clfClasses config + 1
              }
          params0 = mlpInit shape (clfSeed config)
          adam0 = adamInit shape
          adamConfig = defaultAdamConfig {adamLearningRate = clfLearningRate config}
          numClasses = clfClasses config
          inputs = map exampleFeatures dataset
          labels = map exampleLabel dataset
          batchN = length dataset
          -- One full-batch device epoch: forward all inputs, build the
          -- per-sample softmax cross-entropy output gradient, take the
          -- mean device gradient, and apply one Adam step.
          stepEpoch (params, adam) = do
            fwdE <- mlpdForwardBatch device params inputs
            case fwdE of
              Left e -> pure (Left e)
              Right outs -> do
                let dys = zipWith (classifierDLdy numClasses) outs labels
                gradE <- mlpdBatchGradient device params (zip inputs dys)
                case gradE of
                  Left e -> pure (Left e)
                  Right summedGrad ->
                    let meanGrad = scaleMlpGradient (1.0 / fromIntegral batchN) summedGrad
                     in pure (Right (adamStep adamConfig adam params meanGrad))
          runEpoch acc _epoch = case acc of
            Left e -> pure (Left e)
            Right st -> stepEpoch st
      trainedE <- foldM runEpoch (Right (params0, adam0)) [1 .. max 1 (clfEpochs config)]
      case trainedE of
        Left e -> pure (Left e)
        Right (finalParams, _) -> do
          let trained = TrainedClassifier {trainedParams = finalParams, trainedConfig = config}
          accE <- accuracyWithDevice device trained dataset
          pure (fmap (trained,) accE)

-- | Sprint 8.10 — the device-backed end-to-end worker entry: parse the
-- canonical IDX3 image / IDX1 label bytes, bound the example count, and train
-- the substrate-backed classifier. Mirrors 'trainClassifierFromIdxBounded'
-- but routes through 'trainClassifierWithDevice', so a missing/failed device
-- surfaces as a 'Left' rather than a pure-Haskell training run.
trainClassifierWithDeviceFromIdxBounded
  :: MlpDevice
  -> ClassifierConfig
  -> Maybe Int
  -> ByteString
  -- ^ raw IDX3 image bytes (@data.bin@)
  -> ByteString
  -- ^ raw IDX1 label bytes (@labels.bin@)
  -> IO (Either Text (TrainedClassifier, Double))
trainClassifierWithDeviceFromIdxBounded device config subsetLimit imageBytes labelBytes =
  case decodeBoundedDataset config subsetLimit imageBytes labelBytes of
    Left err -> pure (Left (Text.pack err))
    Right (configForData, dataset) -> trainClassifierWithDevice device configForData dataset

-- | Shared IDX decode + bound used by the pure and device worker entries.
decodeBoundedDataset
  :: ClassifierConfig
  -> Maybe Int
  -> ByteString
  -> ByteString
  -> Either String (ClassifierConfig, Dataset)
decodeBoundedDataset config subsetLimit imageBytes labelBytes = do
  (pixelsPer, images) <- parseIdxImages imageBytes
  labels <- parseIdxLabels labelBytes
  let full = zipImagesLabels images labels
      dataset = case subsetLimit of
        Just limit | limit >= 0 -> take limit full
        _ -> full
  if null dataset
    then Left "idx: produced no labeled examples (empty images or labels)"
    else Right (config {clfInputs = pixelsPer}, dataset)

-- | The softmax cross-entropy output gradient for one example, shaped for the
-- device backward ABI: the first @numClasses@ entries are @softmax − onehot@
-- over the class logits; the trailing value-head slot is zero (classification
-- carries no value target). Identical to the gradient the pure
-- 'JitML.Numerics.Mlp.policyValueBackward' assembles.
classifierDLdy :: Int -> Vector Double -> Int -> Vector Double
classifierDLdy numClasses outputVec label =
  let logits = VU.take numClasses outputVec
      probs = softmax logits
      dLogits = VU.imap (\i p -> p - if i == label then 1.0 else 0.0) probs
   in dLogits VU.++ VU.singleton 0.0

-- | Scale every component of an 'MlpGradient' (used to turn the device's
-- batch-summed gradient into the mean gradient before the Adam step).
scaleMlpGradient :: Double -> MlpGradient -> MlpGradient
scaleMlpGradient s grad =
  MlpGradient
    { gradW1 = VU.map (* s) (gradW1 grad)
    , gradB1 = VU.map (* s) (gradB1 grad)
    , gradW2 = VU.map (* s) (gradW2 grad)
    , gradB2 = VU.map (* s) (gradB2 grad)
    }

-- | Predict a single feature vector's class through the device forward
-- (argmax of the softmax over the first @clfClasses@ logits). Returns 'Left'
-- when the device forward is unavailable.
classifyWithDevice :: MlpDevice -> TrainedClassifier -> Vector Double -> IO (Either Text Int)
classifyWithDevice device trained features = do
  outE <- mlpdForwardBatch device (trainedParams trained) [features]
  pure $ case outE of
    Left e -> Left e
    Right (outputVec : _) ->
      Right (VU.maxIndex (VU.take (clfClasses (trainedConfig trained)) outputVec))
    Right [] -> Left "classifyWithDevice: device returned no output"

-- | Held-out accuracy in @[0, 1]@ computed through the device forward over the
-- whole dataset in one batched round-trip. Returns 'Left' on device failure.
accuracyWithDevice :: MlpDevice -> TrainedClassifier -> Dataset -> IO (Either Text Double)
accuracyWithDevice _ _ [] = pure (Right 0.0)
accuracyWithDevice device trained dataset = do
  outE <- mlpdForwardBatch device (trainedParams trained) (map exampleFeatures dataset)
  pure $ case outE of
    Left e -> Left e
    Right outs
      | length outs /= length dataset ->
          Left "accuracyWithDevice: device output count mismatch"
      | otherwise ->
          let numClasses = clfClasses (trainedConfig trained)
              predicted = map (VU.maxIndex . VU.take numClasses) outs
              correct = length (filter id (zipWith (==) predicted (map exampleLabel dataset)))
           in Right (fromIntegral correct / fromIntegral (length dataset))
