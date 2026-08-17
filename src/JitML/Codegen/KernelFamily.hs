{-# LANGUAGE OverloadedStrings #-}

module JitML.Codegen.KernelFamily
  ( KernelFamily (..)
  , familyName
  , kernelFamilies
  , kernelFamilyKernelSpec
  )
where

import Data.Text (Text)

import JitML.Cache.Key (KernelSpec (..))

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

kernelFamilyKernelSpec :: KernelFamily -> KernelSpec
kernelFamilyKernelSpec family =
  KernelSpec ("jitml-kernel-family:" <> familyName family)
