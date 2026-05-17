{-# LANGUAGE OverloadedStrings #-}

module JitML.Codegen.KernelFamily
  ( KernelFamily (..)
  , familyForLayer
  , familyName
  , kernelFamilies
  , kernelFamilyKernelSpec
  )
where

import Data.Text (Text)

import JitML.Cache.Key (KernelSpec (..))
import JitML.Numerics.Catalog (Layer (..))

data KernelFamily
  = Identity
  | Reduction
  | Dense2D
  | Conv2DKernel
  | Conv3DKernel
  | BatchNormKernel
  | LayerNormKernel
  | MultiHeadAttentionKernel
  | EmbeddingKernel
  deriving stock (Eq, Ord, Show)

kernelFamilies :: [KernelFamily]
kernelFamilies =
  [ Identity
  , Reduction
  , Dense2D
  , Conv2DKernel
  , Conv3DKernel
  , BatchNormKernel
  , LayerNormKernel
  , MultiHeadAttentionKernel
  , EmbeddingKernel
  ]

familyName :: KernelFamily -> Text
familyName Identity = "identity"
familyName Reduction = "reduction"
familyName Dense2D = "dense"
familyName Conv2DKernel = "conv2d"
familyName Conv3DKernel = "conv3d"
familyName BatchNormKernel = "batchnorm"
familyName LayerNormKernel = "layernorm"
familyName MultiHeadAttentionKernel = "mha"
familyName EmbeddingKernel = "embedding"

familyForLayer :: Layer -> KernelFamily
familyForLayer Dense = Dense2D
familyForLayer Embedding = EmbeddingKernel
familyForLayer Conv1D = Conv2DKernel
familyForLayer Conv2D = Conv2DKernel
familyForLayer Conv3D = Conv3DKernel
familyForLayer ConvTranspose = Conv2DKernel
familyForLayer ComplexDense = Dense2D
familyForLayer ComplexConv2D = Conv2DKernel
familyForLayer BatchNorm = BatchNormKernel
familyForLayer LayerNorm = LayerNormKernel
familyForLayer GroupNorm = LayerNormKernel
familyForLayer Dropout = Identity
familyForLayer ResidualBlock = Identity
familyForLayer ScaledDotProductAttention = MultiHeadAttentionKernel
familyForLayer MultiHeadAttention = MultiHeadAttentionKernel
familyForLayer RotaryPositionalEmbedding = Identity

kernelFamilyKernelSpec :: KernelFamily -> KernelSpec
kernelFamilyKernelSpec family =
  KernelSpec ("jitml-kernel-family:" <> familyName family)
