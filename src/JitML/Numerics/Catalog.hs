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
  | Conv1D
  | Conv2D
  | Conv3D
  | ConvTranspose
  | BatchNorm
  | LayerNorm
  | GroupNorm
  | Dropout
  | ResidualBlock
  | MultiHeadAttention
  deriving stock (Eq, Ord, Show)

data Activation
  = Relu
  | Gelu
  | Tanh
  | Sigmoid
  | Softmax
  | ComplexModRelu
  | ComplexCardioid
  deriving stock (Eq, Ord, Show)

data SpectralOp
  = FFT
  | IFFT
  | STFT
  | DCT
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
  deriving stock (Eq, Ord, Show)

data Loss
  = CrossEntropy
  | Focal
  | MSE
  | Huber
  | IoU
  deriving stock (Eq, Ord, Show)

layerCatalog :: [Layer]
layerCatalog =
  [ Dense
  , Conv1D
  , Conv2D
  , Conv3D
  , ConvTranspose
  , BatchNorm
  , LayerNorm
  , GroupNorm
  , Dropout
  , ResidualBlock
  , MultiHeadAttention
  ]

activationCatalog :: [Activation]
activationCatalog = [Relu, Gelu, Tanh, Sigmoid, Softmax, ComplexModRelu, ComplexCardioid]

spectralCatalog :: [SpectralOp]
spectralCatalog = [FFT, IFFT, STFT, DCT]

optimizerCatalog :: [Optimizer]
optimizerCatalog = [SGD, MomentumSGD, NesterovSGD, RMSProp, Adagrad, Adadelta, Adam, AdamW, LAMB, LARS, Lion]

schedulerCatalog :: [Scheduler]
schedulerCatalog = [Constant, Linear, Cosine, CosineWithWarmup, Exponential, Polynomial, OneCycle, Piecewise]

lossCatalog :: [Loss]
lossCatalog = [CrossEntropy, Focal, MSE, Huber, IoU]

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
