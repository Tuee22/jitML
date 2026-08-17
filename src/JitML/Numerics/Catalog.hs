{-# LANGUAGE OverloadedStrings #-}

module JitML.Numerics.Catalog
  ( Activation (..)
  , Layer (..)
  , Loss (..)
  , Optimizer (..)
  , Scheduler (..)
  , SpectralOp (..)
  , activationCatalog
  , layerCatalog
  , lossCatalog
  , optimizerCatalog
  , renderNumericalCatalog
  , schedulerCatalog
  , spectralCatalog
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

-- | The single layer-operator vocabulary (Sprint `72.1`).
--
-- Every constructor names exactly one executed operator of the typed
-- @LayerGraph@ IR: @JitML.Numerics.LayerGraph.opLayer@ is a total map from
-- @LayerOp@ onto this type, and @layerOpTemplate@ is a total map back, so a
-- constructor cannot exist here without an executable operator or vice versa.
-- The documentation table and @dhall/numerics/Layer.dhall@ are both projections
-- of 'layerCatalog', which is itself derived from the type rather than
-- hand-listed.
data Layer
  = Dense
  | Identity
  | Dropout
  | Convolution
  | Pooling
  | Normalization
  | MultiHeadAttention
  | GeGLU
  | PatchEmbedding
  | Residual
  | ResidualBlock
  deriving stock (Bounded, Enum, Eq, Ord, Show)

data Activation
  = Relu
  | LeakyRelu
  | Elu
  | Silu
  | Gelu
  | Tanh
  | Sigmoid
  | Softmax
  | ComplexModRelu
  | ComplexCardioid
  | ComplexZRelu
  deriving stock (Eq, Ord, Show)

data SpectralOp
  = FFT
  | FFTAlongAxis
  | IFFT
  | IFFTAlongAxis
  | RFFT
  | IRFFT
  | STFT
  | DCT
  | ComplexConjugate
  | ComplexMatMul
  deriving stock (Eq, Ord, Show)

data Optimizer
  = SGD
  | MomentumSGD
  | NesterovSGD
  | RMSProp
  | Adagrad
  | Adadelta
  | Adam
  | AdamW
  | LAMB
  | LARS
  | Lion
  | AdaFactor
  | Shampoo
  deriving stock (Eq, Ord, Show)

data Scheduler
  = Constant
  | Linear
  | Cosine
  | CosineWithWarmup
  | Exponential
  | Polynomial
  | OneCycle
  | Piecewise
  | ReduceOnPlateau
  deriving stock (Eq, Ord, Show)

data Loss
  = CrossEntropy
  | BinaryCrossEntropy
  | SparseCrossEntropy
  | Focal
  | MSE
  | Huber
  | IoU
  | Dice
  | KLDiv
  | Contrastive
  deriving stock (Eq, Ord, Show)

-- | Derived from the 'Layer' type itself, so the list cannot drift from the
-- vocabulary. Every downstream projection — the generated documentation table,
-- @dhall/numerics/Layer.dhall@, and the cross-type audit — reads this list.
layerCatalog :: [Layer]
layerCatalog = [minBound .. maxBound]

activationCatalog :: [Activation]
activationCatalog =
  [ Relu
  , LeakyRelu
  , Elu
  , Silu
  , Gelu
  , Tanh
  , Sigmoid
  , Softmax
  , ComplexModRelu
  , ComplexCardioid
  , ComplexZRelu
  ]

spectralCatalog :: [SpectralOp]
spectralCatalog =
  [ FFT
  , FFTAlongAxis
  , IFFT
  , IFFTAlongAxis
  , RFFT
  , IRFFT
  , STFT
  , DCT
  , ComplexConjugate
  , ComplexMatMul
  ]

optimizerCatalog :: [Optimizer]
optimizerCatalog =
  [ SGD
  , MomentumSGD
  , NesterovSGD
  , RMSProp
  , Adagrad
  , Adadelta
  , Adam
  , AdamW
  , LAMB
  , LARS
  , Lion
  , AdaFactor
  , Shampoo
  ]

schedulerCatalog :: [Scheduler]
schedulerCatalog =
  [ Constant
  , Linear
  , Cosine
  , CosineWithWarmup
  , Exponential
  , Polynomial
  , OneCycle
  , Piecewise
  , ReduceOnPlateau
  ]

lossCatalog :: [Loss]
lossCatalog =
  [ CrossEntropy
  , BinaryCrossEntropy
  , SparseCrossEntropy
  , Focal
  , MSE
  , Huber
  , IoU
  , Dice
  , KLDiv
  , Contrastive
  ]

renderNumericalCatalog :: Text
renderNumericalCatalog =
  Text.unlines
    [ "layers: " <> renderNames layerCatalog
    , "activations: " <> renderNames activationCatalog
    , "spectral: " <> renderNames spectralCatalog
    , "optimizers: " <> renderNames optimizerCatalog
    , "schedulers: " <> renderNames schedulerCatalog
    , "losses: " <> renderNames lossCatalog
    ]

renderNames :: (Show a) => [a] -> Text
renderNames values =
  Text.intercalate ", " (fmap (Text.pack . show) values)
