{-# LANGUAGE CPP #-}
{-# LANGUAGE OverloadedStrings #-}

#ifdef JITML_CUDA_BINDINGS
{-# LANGUAGE ForeignFunctionInterface #-}
#endif

-- | Typed Haskell binding surface for cuDNN. Companion to
-- 'JitML.Engines.CublasBindings' and the second half of the
-- "binding crate equivalent" remaining work for Sprint 7.4 (Phase 7,
-- @phase-7-jit-codegen-and-substrates.md@).
--
-- Determinism notes that participate in the cuDNN contract:
--
--   * Convolution descriptors must be configured with the explicit
--     algorithm id @CUDNN_CONVOLUTION_FWD_ALGO_IMPLICIT_PRECOMP_GEMM@,
--     captured by 'JitML.Engines.Tuning.cuDnnDeterministicAlgorithms'
--     and embedded in the generated CUDA source by
--     'JitML.Codegen.Cuda.renderCudaFamilySource'.
--   * Spatial batch norm uses @CUDNN_BATCHNORM_SPATIAL_PERSISTENT@; the
--     same string is part of the cache key payload.
module JitML.Engines.CudnnBindings
  ( CudnnHandle
  , CudnnStatus (..)
  , CudnnVersion (..)
  , cudnnBindingsCompiledIn
  , renderCudnnStatus
  , verifyCudnnRuntime
  , withCudnnHandle
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

#ifdef JITML_CUDA_BINDINGS
import Control.Exception qualified as Exception
import Foreign.C.Types (CInt (..))
import Foreign.Marshal.Alloc (alloca)
import Foreign.Ptr (Ptr, nullPtr)
import Foreign.Storable (peek)
#endif

-- | Opaque handle returned by @cudnnCreate@.
newtype CudnnHandle = CudnnHandle CudnnHandlePtr
  deriving stock (Eq)

#ifdef JITML_CUDA_BINDINGS
type CudnnHandlePtr = Ptr ()
#else
type CudnnHandlePtr = ()
#endif

-- | Raw @cudnnStatus_t@. @0@ is @CUDNN_STATUS_SUCCESS@.
newtype CudnnStatus = CudnnStatus {cudnnStatusCode :: Int}
  deriving stock (Eq, Show)

-- | Decoded @cudnnGetVersion@ output. cuDNN encodes version as
-- @major * 10000 + minor * 100 + patch@ (matching cuBLAS).
data CudnnVersion = CudnnVersion
  { cudnnVersionMajor :: Int
  , cudnnVersionMinor :: Int
  , cudnnVersionPatch :: Int
  , cudnnVersionRaw :: Int
  }
  deriving stock (Eq, Show)

cudnnBindingsCompiledIn :: Bool
#ifdef JITML_CUDA_BINDINGS
cudnnBindingsCompiledIn = True
#else
cudnnBindingsCompiledIn = False
#endif

renderCudnnStatus :: CudnnStatus -> Text
renderCudnnStatus (CudnnStatus code) =
  "cudnn-status=" <> Text.pack (show code)

withCudnnHandle :: (CudnnHandle -> IO a) -> IO (Either CudnnStatus a)
#ifdef JITML_CUDA_BINDINGS
withCudnnHandle action =
  alloca $ \handlePtr -> do
    createStatus <- c_cudnnCreate handlePtr
    if createStatus /= 0
      then pure (Left (CudnnStatus (fromIntegral createStatus)))
      else do
        rawHandle <- peek handlePtr
        if rawHandle == nullPtr
          then pure (Left (CudnnStatus (-1)))
          else
            Exception.bracket_
              (pure ())
              (c_cudnnDestroy rawHandle >> pure ())
              (Right <$> action (CudnnHandle rawHandle))
#else
withCudnnHandle _ =
  pure (Left (CudnnStatus (-2)))
#endif

verifyCudnnRuntime :: IO (Either CudnnStatus CudnnVersion)
#ifdef JITML_CUDA_BINDINGS
verifyCudnnRuntime = do
  raw <- fromIntegral <$> c_cudnnGetVersion
  result <- withCudnnHandle $ \_ ->
    pure (decodeCudnnVersion raw)
  pure result
#else
verifyCudnnRuntime =
  pure (Left (CudnnStatus (-2)))
#endif

#ifdef JITML_CUDA_BINDINGS
decodeCudnnVersion :: Int -> CudnnVersion
decodeCudnnVersion raw =
  let major = raw `div` 10000
      minor = (raw `div` 100) `mod` 100
      patch = raw `mod` 100
   in CudnnVersion
        { cudnnVersionMajor = major
        , cudnnVersionMinor = minor
        , cudnnVersionPatch = patch
        , cudnnVersionRaw = raw
        }

foreign import ccall unsafe "cudnnCreate"
  c_cudnnCreate :: Ptr (Ptr ()) -> IO CInt

foreign import ccall unsafe "cudnnDestroy"
  c_cudnnDestroy :: Ptr () -> IO CInt

foreign import ccall unsafe "cudnnGetVersion"
  c_cudnnGetVersion :: IO CInt
#endif
