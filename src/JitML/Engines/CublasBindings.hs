{-# LANGUAGE CPP #-}
{-# LANGUAGE OverloadedStrings #-}

#ifdef JITML_CUDA_BINDINGS
{-# LANGUAGE ForeignFunctionInterface #-}
#endif

-- | Typed Haskell binding surface for cuBLAS. This is the "binding crate
-- equivalent" referenced by Sprint 7.4 `### Remaining Work` (Phase 7,
-- @phase-7-jit-codegen-and-substrates.md@). The module exposes
-- 'cublasBindingsCompiledIn' so callers can branch on whether the
-- @jitml@ library was built with the @cuda@ cabal flag, and
-- 'verifyCublasRuntime' which exercises the bindings end-to-end against
-- the host's @libcublas@.
--
-- Determinism notes that participate in the cuBLAS contract:
--
--   * The host's CUBLAS pointer mode is left at the default
--     (@CUBLAS_POINTER_MODE_HOST@) so scalar arguments are read from host
--     memory, preventing nondeterministic device-side scalar loads.
--   * Real production GEMMs are scheduled with the deterministic
--     algorithm pinned by @JitML.Engines.Tuning@; the same algorithm
--     string is embedded in the generated kernel source by
--     'JitML.Codegen.Cuda.renderCudaFamilySource'.
module JitML.Engines.CublasBindings
  ( CublasHandle
  , CublasStatus (..)
  , CublasVersion (..)
  , cublasBindingsCompiledIn
  , renderCublasStatus
  , verifyCublasRuntime
  , withCublasHandle
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

-- | Opaque handle returned by @cublasCreate_v2@. The constructor is not
-- exported because mis-use (double free, use-after-free) breaks the
-- bit-determinism contract.
newtype CublasHandle = CublasHandle CublasHandlePtr
  deriving stock (Eq)

#ifdef JITML_CUDA_BINDINGS
type CublasHandlePtr = Ptr ()
#else
type CublasHandlePtr = ()
#endif

-- | Raw integer cuBLAS status code. @0@ is @CUBLAS_STATUS_SUCCESS@.
newtype CublasStatus = CublasStatus {cublasStatusCode :: Int}
  deriving stock (Eq, Show)

-- | Decoded @cublasGetVersion_v2@ output. cuBLAS encodes versions as
-- @major * 10000 + minor * 100 + patch@.
data CublasVersion = CublasVersion
  { cublasVersionMajor :: Int
  , cublasVersionMinor :: Int
  , cublasVersionPatch :: Int
  , cublasVersionRaw :: Int
  }
  deriving stock (Eq, Show)

-- | True when the @jitml@ library was built with the @cuda@ cabal flag
-- and the bindings actually point at @libcublas@. Pure-Haskell
-- consumers branch on this without importing @libcublas@ themselves.
cublasBindingsCompiledIn :: Bool
#ifdef JITML_CUDA_BINDINGS
cublasBindingsCompiledIn = True
#else
cublasBindingsCompiledIn = False
#endif

renderCublasStatus :: CublasStatus -> Text
renderCublasStatus (CublasStatus code) =
  "cublas-status=" <> Text.pack (show code)

-- | Bracket a cuBLAS handle: create on entry, destroy on exit. Returns
-- @Left@ with a typed status code if @cublasCreate_v2@ fails. When the
-- bindings are compiled out, returns a typed compile-time error.
withCublasHandle :: (CublasHandle -> IO a) -> IO (Either CublasStatus a)
#ifdef JITML_CUDA_BINDINGS
withCublasHandle action =
  alloca $ \handlePtr -> do
    createStatus <- c_cublasCreate handlePtr
    if createStatus /= 0
      then pure (Left (CublasStatus (fromIntegral createStatus)))
      else do
        rawHandle <- peek handlePtr
        if rawHandle == nullPtr
          then pure (Left (CublasStatus (-1)))
          else
            Exception.bracket_
              (pure ())
              (c_cublasDestroy rawHandle >> pure ())
              (Right <$> action (CublasHandle rawHandle))
#else
withCublasHandle _ =
  pure (Left (CublasStatus (-2)))
#endif

-- | Verify the cuBLAS runtime: create a handle, query the version,
-- destroy the handle. Returns the typed version on success or a status
-- code on failure. This is the routine exercised by the live CUDA
-- integration test under Sprint 7.4.
verifyCublasRuntime :: IO (Either CublasStatus CublasVersion)
#ifdef JITML_CUDA_BINDINGS
verifyCublasRuntime = do
  result <- withCublasHandle $ \(CublasHandle handle) ->
    alloca $ \versionPtr -> do
      status <- c_cublasGetVersion handle versionPtr
      if status /= 0
        then pure (Left (CublasStatus (fromIntegral status)))
        else do
          raw <- fromIntegral <$> peek versionPtr
          pure (Right (decodeCublasVersion raw))
  case result of
    Left status -> pure (Left status)
    Right inner -> pure inner
#else
verifyCublasRuntime =
  pure (Left (CublasStatus (-2)))
#endif

#ifdef JITML_CUDA_BINDINGS
decodeCublasVersion :: Int -> CublasVersion
decodeCublasVersion raw =
  let major = raw `div` 10000
      minor = (raw `div` 100) `mod` 100
      patch = raw `mod` 100
   in CublasVersion
        { cublasVersionMajor = major
        , cublasVersionMinor = minor
        , cublasVersionPatch = patch
        , cublasVersionRaw = raw
        }

foreign import ccall unsafe "cublasCreate_v2"
  c_cublasCreate :: Ptr (Ptr ()) -> IO CInt

foreign import ccall unsafe "cublasDestroy_v2"
  c_cublasDestroy :: Ptr () -> IO CInt

foreign import ccall unsafe "cublasGetVersion_v2"
  c_cublasGetVersion :: Ptr () -> Ptr CInt -> IO CInt
#endif
