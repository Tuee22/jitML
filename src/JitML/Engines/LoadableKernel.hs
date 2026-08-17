{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE OverloadedStrings #-}

-- | The one @dlopen@/@dlsym@ kernel ABI, shared by every substrate whose
-- profile carries 'JitML.Substrate.LoadableSymbolLaunch'.
--
-- Sprint `79.1` extracted this from 'JitML.Engines.Local' and
-- 'JitML.Engines.CudaLocal', where the four FFI type aliases, the four
-- @foreign import ccall "dynamic"@ declarations, and both driver helpers were
-- byte-identical apart from one comment word. The substrate difference on this
-- path is which artifact is loaded, not how it is entered, so it belongs in the
-- profile rather than in two copies of the same marshalling code.
module JitML.Engines.LoadableKernel
  ( KernelFamilyFunction
  , KernelFunction
  , KernelOutputCountFunction
  , WeightedKernelFunction
  , loadAndRun
  , loadAndRunWeighted
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Foreign.C.String (CString, peekCString)
import Foreign.C.Types (CFloat (..), CSize (..))
import Foreign.Marshal.Array (allocaArray, peekArray, withArray)
import Foreign.Ptr (FunPtr, Ptr)

import JitML.Engines.Loader (withKernelSymbol)

type KernelFunction =
  Ptr CFloat -> Ptr CFloat -> CSize -> IO ()

-- Sprint 13.11 — weighted ABI: caller supplies a flat row-major weights
-- buffer alongside the input. Output, input, input_count, weights,
-- weights_count.
type WeightedKernelFunction =
  Ptr CFloat -> Ptr CFloat -> CSize -> Ptr CFloat -> CSize -> IO ()

type KernelFamilyFunction =
  IO CString

type KernelOutputCountFunction =
  CSize -> IO CSize

foreign import ccall "dynamic" mkKernelFunction :: FunPtr KernelFunction -> KernelFunction

foreign import ccall "dynamic"
  mkWeightedKernelFunction :: FunPtr WeightedKernelFunction -> WeightedKernelFunction

foreign import ccall "dynamic"
  mkKernelFamilyFunction :: FunPtr KernelFamilyFunction -> KernelFamilyFunction

foreign import ccall "dynamic"
  mkKernelOutputCountFunction :: FunPtr KernelOutputCountFunction -> KernelOutputCountFunction

-- | Resolve the three metadata symbols plus @jitml_kernel@, marshal the input
-- across the FFI, and copy the output back. The reported family is read out of
-- the loaded artifact, never restated from the request.
loadAndRun :: FilePath -> [Float] -> IO (Text, [Float])
loadAndRun artifactPath input =
  withKernelSymbol artifactPath "jitml_kernel_family_name" $ \familySymbol ->
    withKernelSymbol artifactPath "jitml_kernel_output_count" $ \outputCountSymbol ->
      withKernelSymbol artifactPath "jitml_kernel" $ \kernelSymbol -> do
        reportedFamily <- Text.pack <$> (mkKernelFamilyFunction familySymbol >>= peekCString)
        let kernel = mkKernelFunction kernelSymbol
            outputCount = mkKernelOutputCountFunction outputCountSymbol
            cInput = fmap CFloat input
            inputCount = length input
        outputLength <- fromIntegral <$> outputCount (fromIntegral inputCount)
        output <-
          withArray cInput $ \inputPtr ->
            allocaArray outputLength $ \outputPtr -> do
              kernel outputPtr inputPtr (fromIntegral inputCount)
              fmap (\(CFloat value) -> value) <$> peekArray outputLength outputPtr
        pure (reportedFamily, output)

-- | Sprint 13.11 — weighted variant of 'loadAndRun'. Resolves the same three
-- metadata symbols, plus @jitml_weighted_kernel@, and threads the input +
-- weights buffers across the FFI.
loadAndRunWeighted :: FilePath -> [Float] -> [Float] -> IO (Text, [Float])
loadAndRunWeighted artifactPath input weights =
  withKernelSymbol artifactPath "jitml_kernel_family_name" $ \familySymbol ->
    withKernelSymbol artifactPath "jitml_kernel_output_count" $ \outputCountSymbol ->
      withKernelSymbol artifactPath "jitml_weighted_kernel" $ \kernelSymbol -> do
        reportedFamily <- Text.pack <$> (mkKernelFamilyFunction familySymbol >>= peekCString)
        let kernel = mkWeightedKernelFunction kernelSymbol
            outputCount = mkKernelOutputCountFunction outputCountSymbol
            cInput = fmap CFloat input
            cWeights = fmap CFloat weights
            inputCount = length input
            weightsCount = length weights
        outputLength <- fromIntegral <$> outputCount (fromIntegral inputCount)
        output <-
          withArray cInput $ \inputPtr ->
            withArray cWeights $ \weightsPtr ->
              allocaArray outputLength $ \outputPtr -> do
                kernel
                  outputPtr
                  inputPtr
                  (fromIntegral inputCount)
                  weightsPtr
                  (fromIntegral weightsCount)
                fmap (\(CFloat value) -> value) <$> peekArray outputLength outputPtr
        pure (reportedFamily, output)
