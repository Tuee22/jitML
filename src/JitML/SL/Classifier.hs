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
  , classify
  , accuracy
  , crossEntropyLoss
  )
where

import Data.Bits (shiftL, (.|.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.List qualified
import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU

import JitML.Numerics.Mlp
  ( AdamConfig (..)
  , MlpParams
  , MlpShape (..)
  , PolicyValueOutput (..)
  , adamInit
  , adamStep
  , defaultAdamConfig
  , mlpInit
  , policyValueBackward
  , policyValueForward
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
