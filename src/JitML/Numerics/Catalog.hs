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

data Layer
  = Dense
  | Embedding
  | Conv1D
  | Conv2D
  | Conv3D
  | ConvTranspose
  | ComplexDense
  | ComplexConv2D
  | BatchNorm
  | LayerNorm
  | GroupNorm
  | Dropout
  | ResidualBlock
  | ScaledDotProductAttention
  | MultiHeadAttention
  | RotaryPositionalEmbedding
  deriving stock (Eq, Ord, Show)

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

layerCatalog :: [Layer]
layerCatalog =
  [ Dense
  , Embedding
  , Conv1D
  , Conv2D
  , Conv3D
  , ConvTranspose
  , ComplexDense
  , ComplexConv2D
  , BatchNorm
  , LayerNorm
  , GroupNorm
  , Dropout
  , ResidualBlock
  , ScaledDotProductAttention
  , MultiHeadAttention
  , RotaryPositionalEmbedding
  ]

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
