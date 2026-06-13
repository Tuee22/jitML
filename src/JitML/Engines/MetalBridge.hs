{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Engines.MetalBridge
  ( fixedMetalBridgePathCandidates
  , installFixedMetalBridge
  , probeFixedMetalBridge
  , runMetalMlpBackward
  , runMetalMlpBatchGradient
  , runMetalMlpForward
  , runMetalMlpForwardBatch
  , runMetalMlpInputGradientBatch
  , runMetalSource
  )
where

import Control.Exception qualified as Exception
import Data.Maybe (fromMaybe, maybeToList)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import Foreign.C.String (CString, withCString)
import Foreign.C.Types (CChar, CFloat (..), CInt (..), CSize (..))
import Foreign.Marshal.Array (allocaArray, peekArray, withArray)
import Foreign.Ptr (FunPtr, Ptr, nullPtr)
import Foreign.Storable (peekElemOff, poke)
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory)
import System.Info qualified as SystemInfo
import System.Posix.DynamicLinker (RTLDFlags (RTLD_NOW), dlsym, withDL)

import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (subprocess)

type MetalBridgeProbe =
  IO CInt

type MetalBridgeRun =
  CString
  -> CString
  -> Ptr CFloat
  -> CSize
  -> Ptr CFloat
  -> CSize
  -> Ptr CFloat
  -> CSize
  -> CSize
  -> Ptr CChar
  -> CSize
  -> IO CInt

type MetalBridgeMlpForward =
  CString
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> CInt
  -> CInt
  -> CInt
  -> CSize
  -> Ptr CChar
  -> CSize
  -> IO CInt

type MetalBridgeMlpBackward =
  CString
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> CInt
  -> CInt
  -> CInt
  -> CSize
  -> Ptr CChar
  -> CSize
  -> IO CInt

type MetalBridgeMlpBatchGradient =
  CString
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CSize
  -> Ptr CChar
  -> CSize
  -> IO CInt

type MetalBridgeMlpForwardBatch =
  CString
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CSize
  -> Ptr CChar
  -> CSize
  -> IO CInt

type MetalBridgeMlpInputGradientBatch =
  CString
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> Ptr CFloat
  -> CInt
  -> CInt
  -> CInt
  -> CInt
  -> CSize
  -> Ptr CChar
  -> CSize
  -> IO CInt

foreign import ccall "dynamic"
  mkMetalBridgeProbe :: FunPtr MetalBridgeProbe -> MetalBridgeProbe

foreign import ccall "dynamic"
  mkMetalBridgeRun :: FunPtr MetalBridgeRun -> MetalBridgeRun

foreign import ccall "dynamic"
  mkMetalBridgeMlpForward :: FunPtr MetalBridgeMlpForward -> MetalBridgeMlpForward

foreign import ccall "dynamic"
  mkMetalBridgeMlpBackward :: FunPtr MetalBridgeMlpBackward -> MetalBridgeMlpBackward

foreign import ccall "dynamic"
  mkMetalBridgeMlpBatchGradient
    :: FunPtr MetalBridgeMlpBatchGradient -> MetalBridgeMlpBatchGradient

foreign import ccall "dynamic"
  mkMetalBridgeMlpForwardBatch
    :: FunPtr MetalBridgeMlpForwardBatch -> MetalBridgeMlpForwardBatch

foreign import ccall "dynamic"
  mkMetalBridgeMlpInputGradientBatch
    :: FunPtr MetalBridgeMlpInputGradientBatch -> MetalBridgeMlpInputGradientBatch

fixedMetalBridgePathCandidates :: IO [FilePath]
fixedMetalBridgePathCandidates = do
  configured <- lookupEnv "JITML_METAL_BRIDGE_PATH"
  pure $
    maybeToList configured
      <> [ ".build/host/apple-silicon/libJitMLMetalBridge.dylib"
         , ".build/host/apple-silicon/libjitml-metal-bridge.dylib"
         ]

installFixedMetalBridge :: IO (Either Text FilePath)
installFixedMetalBridge
  | SystemInfo.os /= "darwin" =
      pure (Left "fixed Metal bridge can only be built on macOS")
  | otherwise = do
      createDirectoryIfMissing True fixedMetalBridgeDir
      Text.IO.writeFile fixedMetalBridgeSourcePath fixedMetalBridgeSource
      (exitCode, _stdoutText, stderrText) <-
        runStreaming
          defaultSubprocessEnv
          ( subprocess
              "/usr/bin/clang"
              [ "-dynamiclib"
              , "-fobjc-arc"
              , "-ObjC"
              , Text.pack fixedMetalBridgeSourcePath
              , "-framework"
              , "Foundation"
              , "-framework"
              , "Metal"
              , "-o"
              , Text.pack defaultFixedMetalBridgePath
              ]
          )
      case exitCode of
        ExitSuccess -> do
          ok <- probeBridgeAt defaultFixedMetalBridgePath
          pure $
            if ok
              then Right defaultFixedMetalBridgePath
              else Left "fixed Metal bridge built but its probe symbol failed"
        ExitFailure _ ->
          pure (Left ("fixed Metal bridge build failed: " <> stderrText))

probeFixedMetalBridge :: IO Bool
probeFixedMetalBridge = do
  candidates <- fixedMetalBridgePathCandidates
  go candidates
 where
  go [] = pure False
  go (candidate : rest) = do
    exists <- doesFileExist candidate
    if exists
      then do
        result <- probeBridgeAt candidate
        if result then pure True else go rest
      else go rest

probeBridgeAt :: FilePath -> IO Bool
probeBridgeAt path =
  Exception.handle
    (\(_err :: Exception.SomeException) -> pure False)
    ( withDL path [RTLD_NOW] $ \handle -> do
        symbol <- dlsym handle "jitml_metal_bridge_probe"
        exitCode <- mkMetalBridgeProbe symbol
        _mlpSymbol <- dlsym handle "jitml_metal_bridge_mlp_forward"
        pure (exitCode == 0)
    )

runMetalSource
  :: Text
  -> Text
  -> Int
  -> [Float]
  -> Maybe [Float]
  -> Int
  -> IO (Either Text [Float])
runMetalSource source functionName threadgroupSize input maybeWeights outputCount
  | threadgroupSize <= 0 =
      pure (Left "threadgroup size must be positive")
  | outputCount < 0 =
      pure (Left "output count must be non-negative")
  | outputCount == 0 =
      pure (Right [])
  | otherwise = do
      candidates <- fixedMetalBridgePathCandidates
      bridgePath <- firstExisting candidates
      case bridgePath of
        Nothing ->
          pure
            ( Left
                ( "fixed Metal bridge dylib not found; tried "
                    <> Text.intercalate ", " (fmap Text.pack candidates)
                )
            )
        Just path -> callBridge path
 where
  callBridge path =
    Exception.handle
      (\(err :: Exception.SomeException) -> pure (Left (Text.pack (Exception.displayException err))))
      ( withDL path [RTLD_NOW] $ \handle -> do
          symbol <- dlsym handle "jitml_metal_bridge_run"
          let bridgeRun = mkMetalBridgeRun symbol
              cInput = fmap CFloat input
              cWeights = fmap CFloat (fromMaybe [] maybeWeights)
          withCString (Text.unpack source) $ \sourcePtr ->
            withCString (Text.unpack functionName) $ \functionPtr ->
              withArray cInput $ \inputPtr ->
                withOptionalWeights cWeights $ \weightsPtr ->
                  allocaArray outputCount $ \outputPtr ->
                    allocaArray errorBufferLength $ \errorPtr -> do
                      poke errorPtr 0
                      exitCode <-
                        bridgeRun
                          sourcePtr
                          functionPtr
                          inputPtr
                          (fromIntegral (length input))
                          weightsPtr
                          (fromIntegral (maybe 0 length maybeWeights))
                          outputPtr
                          (fromIntegral outputCount)
                          (fromIntegral threadgroupSize)
                          errorPtr
                          (fromIntegral errorBufferLength)
                      if exitCode == 0
                        then do
                          output <- peekArray outputCount outputPtr
                          pure (Right (fmap (\(CFloat value) -> value) output))
                        else do
                          message <- Text.pack <$> peekCStringLenNul errorPtr errorBufferLength
                          pure (Left (bridgeErrorMessage exitCode message))
      )

  withOptionalWeights [] use = use nullPtr
  withOptionalWeights weights use = withArray weights use

runMetalMlpForward
  :: Text
  -> Int
  -> Int
  -> Int
  -> [Float]
  -> [Float]
  -> [Float]
  -> [Float]
  -> [Float]
  -> IO (Either Text ([Float], [Float], [Float]))
runMetalMlpForward source inputCount hidden outputs input w1 b1 w2 b2
  | inputCount < 0 || hidden < 0 || outputs < 0 =
      pure (Left "MLP dimensions must be non-negative")
  | otherwise =
      withFixedMetalBridgeSymbol "jitml_metal_bridge_mlp_forward" $ \symbol -> do
        let bridgeRun = mkMetalBridgeMlpForward symbol
        withCString (Text.unpack source) $ \sourcePtr ->
          withArray (fmap CFloat input) $ \inputPtr ->
            withArray (fmap CFloat w1) $ \w1Ptr ->
              withArray (fmap CFloat b1) $ \b1Ptr ->
                withArray (fmap CFloat w2) $ \w2Ptr ->
                  withArray (fmap CFloat b2) $ \b2Ptr ->
                    allocaArray hidden $ \hiddenPrePtr ->
                      allocaArray hidden $ \hiddenActPtr ->
                        allocaArray outputs $ \outputPtr ->
                          callWithErrorBuffer $ \errorPtr -> do
                            exitCode <-
                              bridgeRun
                                sourcePtr
                                hiddenPrePtr
                                hiddenActPtr
                                outputPtr
                                inputPtr
                                w1Ptr
                                b1Ptr
                                w2Ptr
                                b2Ptr
                                (fromIntegral inputCount)
                                (fromIntegral hidden)
                                (fromIntegral outputs)
                                (fromIntegral defaultMlpThreadgroupSize)
                                errorPtr
                                (fromIntegral errorBufferLength)
                            if exitCode == 0
                              then do
                                hiddenPre <- peekCFloatArray hidden hiddenPrePtr
                                hiddenAct <- peekCFloatArray hidden hiddenActPtr
                                output <- peekCFloatArray outputs outputPtr
                                pure (Right (hiddenPre, hiddenAct, output))
                              else bridgeError exitCode errorPtr

runMetalMlpBackward
  :: Text
  -> Int
  -> Int
  -> Int
  -> [Float]
  -> [Float]
  -> [Float]
  -> [Float]
  -> IO (Either Text ([Float], [Float], [Float], [Float]))
runMetalMlpBackward source inputCount hidden outputs dLdy input hiddenAct w2
  | inputCount < 0 || hidden < 0 || outputs < 0 =
      pure (Left "MLP dimensions must be non-negative")
  | otherwise =
      withFixedMetalBridgeSymbol "jitml_metal_bridge_mlp_backward" $ \symbol -> do
        let bridgeRun = mkMetalBridgeMlpBackward symbol
            w1Count = hidden * inputCount
            w2Count = outputs * hidden
        withCString (Text.unpack source) $ \sourcePtr ->
          withArray (fmap CFloat dLdy) $ \dLdyPtr ->
            withArray (fmap CFloat input) $ \inputPtr ->
              withArray (fmap CFloat hiddenAct) $ \hiddenActPtr ->
                withArray (fmap CFloat w2) $ \w2Ptr ->
                  allocaArray w1Count $ \gW1Ptr ->
                    allocaArray hidden $ \gB1Ptr ->
                      allocaArray w2Count $ \gW2Ptr ->
                        allocaArray outputs $ \gB2Ptr ->
                          callWithErrorBuffer $ \errorPtr -> do
                            exitCode <-
                              bridgeRun
                                sourcePtr
                                gW1Ptr
                                gB1Ptr
                                gW2Ptr
                                gB2Ptr
                                dLdyPtr
                                inputPtr
                                hiddenActPtr
                                w2Ptr
                                (fromIntegral inputCount)
                                (fromIntegral hidden)
                                (fromIntegral outputs)
                                (fromIntegral defaultMlpThreadgroupSize)
                                errorPtr
                                (fromIntegral errorBufferLength)
                            if exitCode == 0
                              then do
                                gW1 <- peekCFloatArray w1Count gW1Ptr
                                gB1 <- peekCFloatArray hidden gB1Ptr
                                gW2 <- peekCFloatArray w2Count gW2Ptr
                                gB2 <- peekCFloatArray outputs gB2Ptr
                                pure (Right (gW1, gB1, gW2, gB2))
                              else bridgeError exitCode errorPtr

runMetalMlpForwardBatch
  :: Text
  -> Int
  -> Int
  -> Int
  -> Int
  -> [Float]
  -> [Float]
  -> [Float]
  -> [Float]
  -> [Float]
  -> IO (Either Text [Float])
runMetalMlpForwardBatch source inputCount hidden outputs batch input w1 b1 w2 b2
  | inputCount < 0 || hidden < 0 || outputs < 0 || batch < 0 =
      pure (Left "MLP dimensions must be non-negative")
  | otherwise =
      withFixedMetalBridgeSymbol "jitml_metal_bridge_mlp_forward_batch" $ \symbol -> do
        let bridgeRun = mkMetalBridgeMlpForwardBatch symbol
            outputCount = batch * outputs
        withCString (Text.unpack source) $ \sourcePtr ->
          withArray (fmap CFloat input) $ \inputPtr ->
            withArray (fmap CFloat w1) $ \w1Ptr ->
              withArray (fmap CFloat b1) $ \b1Ptr ->
                withArray (fmap CFloat w2) $ \w2Ptr ->
                  withArray (fmap CFloat b2) $ \b2Ptr ->
                    allocaArray outputCount $ \outputPtr ->
                      callWithErrorBuffer $ \errorPtr -> do
                        exitCode <-
                          bridgeRun
                            sourcePtr
                            outputPtr
                            inputPtr
                            w1Ptr
                            b1Ptr
                            w2Ptr
                            b2Ptr
                            (fromIntegral inputCount)
                            (fromIntegral hidden)
                            (fromIntegral outputs)
                            (fromIntegral batch)
                            (fromIntegral defaultMlpThreadgroupSize)
                            errorPtr
                            (fromIntegral errorBufferLength)
                        if exitCode == 0
                          then Right <$> peekCFloatArray outputCount outputPtr
                          else bridgeError exitCode errorPtr

runMetalMlpBatchGradient
  :: Text
  -> Int
  -> Int
  -> Int
  -> Int
  -> [Float]
  -> [Float]
  -> [Float]
  -> [Float]
  -> [Float]
  -> IO (Either Text ([Float], [Float], [Float], [Float]))
runMetalMlpBatchGradient source inputCount hidden outputs batch input dLdy w1 b1 w2
  | inputCount < 0 || hidden < 0 || outputs < 0 || batch < 0 =
      pure (Left "MLP dimensions must be non-negative")
  | otherwise =
      withFixedMetalBridgeSymbol "jitml_metal_bridge_mlp_batch_gradient" $ \symbol -> do
        let bridgeRun = mkMetalBridgeMlpBatchGradient symbol
            w1Count = hidden * inputCount
            w2Count = outputs * hidden
        withCString (Text.unpack source) $ \sourcePtr ->
          withArray (fmap CFloat input) $ \inputPtr ->
            withArray (fmap CFloat dLdy) $ \dLdyPtr ->
              withArray (fmap CFloat w1) $ \w1Ptr ->
                withArray (fmap CFloat b1) $ \b1Ptr ->
                  withArray (fmap CFloat w2) $ \w2Ptr ->
                    allocaArray w1Count $ \gW1Ptr ->
                      allocaArray hidden $ \gB1Ptr ->
                        allocaArray w2Count $ \gW2Ptr ->
                          allocaArray outputs $ \gB2Ptr ->
                            callWithErrorBuffer $ \errorPtr -> do
                              exitCode <-
                                bridgeRun
                                  sourcePtr
                                  gW1Ptr
                                  gB1Ptr
                                  gW2Ptr
                                  gB2Ptr
                                  inputPtr
                                  dLdyPtr
                                  w1Ptr
                                  b1Ptr
                                  w2Ptr
                                  (fromIntegral inputCount)
                                  (fromIntegral hidden)
                                  (fromIntegral outputs)
                                  (fromIntegral batch)
                                  (fromIntegral defaultMlpThreadgroupSize)
                                  errorPtr
                                  (fromIntegral errorBufferLength)
                              if exitCode == 0
                                then do
                                  gW1 <- peekCFloatArray w1Count gW1Ptr
                                  gB1 <- peekCFloatArray hidden gB1Ptr
                                  gW2 <- peekCFloatArray w2Count gW2Ptr
                                  gB2 <- peekCFloatArray outputs gB2Ptr
                                  pure (Right (gW1, gB1, gW2, gB2))
                                else bridgeError exitCode errorPtr

runMetalMlpInputGradientBatch
  :: Text
  -> Int
  -> Int
  -> Int
  -> Int
  -> [Float]
  -> [Float]
  -> [Float]
  -> [Float]
  -> [Float]
  -> IO (Either Text [Float])
runMetalMlpInputGradientBatch source inputCount hidden outputs batch input dLdy w1 b1 w2
  | inputCount < 0 || hidden < 0 || outputs < 0 || batch < 0 =
      pure (Left "MLP dimensions must be non-negative")
  | otherwise =
      withFixedMetalBridgeSymbol "jitml_metal_bridge_mlp_input_gradient_batch" $ \symbol -> do
        let bridgeRun = mkMetalBridgeMlpInputGradientBatch symbol
            dxCount = batch * inputCount
        withCString (Text.unpack source) $ \sourcePtr ->
          withArray (fmap CFloat input) $ \inputPtr ->
            withArray (fmap CFloat dLdy) $ \dLdyPtr ->
              withArray (fmap CFloat w1) $ \w1Ptr ->
                withArray (fmap CFloat b1) $ \b1Ptr ->
                  withArray (fmap CFloat w2) $ \w2Ptr ->
                    allocaArray dxCount $ \dxPtr ->
                      callWithErrorBuffer $ \errorPtr -> do
                        exitCode <-
                          bridgeRun
                            sourcePtr
                            dxPtr
                            inputPtr
                            dLdyPtr
                            w1Ptr
                            b1Ptr
                            w2Ptr
                            (fromIntegral inputCount)
                            (fromIntegral hidden)
                            (fromIntegral outputs)
                            (fromIntegral batch)
                            (fromIntegral defaultMlpThreadgroupSize)
                            errorPtr
                            (fromIntegral errorBufferLength)
                        if exitCode == 0
                          then Right <$> peekCFloatArray dxCount dxPtr
                          else bridgeError exitCode errorPtr

withFixedMetalBridgeSymbol
  :: String -> (FunPtr a -> IO (Either Text b)) -> IO (Either Text b)
withFixedMetalBridgeSymbol symbolName use = do
  candidates <- fixedMetalBridgePathCandidates
  bridgePath <- firstExisting candidates
  case bridgePath of
    Nothing ->
      pure
        ( Left
            ( "fixed Metal bridge dylib not found; tried "
                <> Text.intercalate ", " (fmap Text.pack candidates)
            )
        )
    Just path ->
      Exception.handle
        (\(err :: Exception.SomeException) -> pure (Left (Text.pack (Exception.displayException err))))
        (withDL path [RTLD_NOW] $ \handle -> dlsym handle symbolName >>= use)

callWithErrorBuffer :: (Ptr CChar -> IO (Either Text a)) -> IO (Either Text a)
callWithErrorBuffer action =
  allocaArray errorBufferLength $ \errorPtr -> do
    poke errorPtr 0
    action errorPtr

bridgeError :: CInt -> Ptr CChar -> IO (Either Text a)
bridgeError exitCode errorPtr = do
  message <- Text.pack <$> peekCStringLenNul errorPtr errorBufferLength
  pure (Left (bridgeErrorMessage exitCode message))

peekCFloatArray :: Int -> Ptr CFloat -> IO [Float]
peekCFloatArray count ptr =
  fmap (\(CFloat value) -> value) <$> peekArray count ptr

defaultMlpThreadgroupSize :: Int
defaultMlpThreadgroupSize = 128

errorBufferLength :: Int
errorBufferLength = 4096

bridgeErrorMessage :: CInt -> Text -> Text
bridgeErrorMessage exitCode message
  | Text.null message = "fixed Metal bridge returned " <> Text.pack (show exitCode)
  | otherwise = message

firstExisting :: [FilePath] -> IO (Maybe FilePath)
firstExisting [] = pure Nothing
firstExisting (path : rest) = do
  exists <- doesFileExist path
  if exists then pure (Just path) else firstExisting rest

fixedMetalBridgeDir :: FilePath
fixedMetalBridgeDir = takeDirectory defaultFixedMetalBridgePath

defaultFixedMetalBridgePath :: FilePath
defaultFixedMetalBridgePath = ".build/host/apple-silicon/libJitMLMetalBridge.dylib"

fixedMetalBridgeSourcePath :: FilePath
fixedMetalBridgeSourcePath = ".build/host/apple-silicon/JitMLMetalBridge.m"

fixedMetalBridgeSource :: Text
fixedMetalBridgeSource =
  Text.unlines
    [ "#import <Foundation/Foundation.h>"
    , "#import <Metal/Metal.h>"
    , "#include <stdint.h>"
    , "#include <stdio.h>"
    , "#include <string.h>"
    , ""
    , "static id<MTLDevice> jitml_device = nil;"
    , "static id<MTLCommandQueue> jitml_queue = nil;"
    , "static NSMutableDictionary *jitml_pipeline_cache = nil;"
    , ""
    , "static size_t jitml_max_size(size_t a, size_t b) { return a > b ? a : b; }"
    , ""
    , "static int jitml_error(char *buffer, size_t buffer_len, NSString *message) {"
    , "  if (buffer != NULL && buffer_len > 0) {"
    , "    const char *utf8 = message == nil ? \"unknown Metal bridge error\" : [message UTF8String];"
    , "    snprintf(buffer, buffer_len, \"%s\", utf8 == NULL ? \"unknown Metal bridge error\" : utf8);"
    , "  }"
    , "  return 1;"
    , "}"
    , ""
    , "static void jitml_init(void) {"
    , "  @synchronized([NSObject class]) {"
    , "    if (jitml_device == nil) {"
    , "      jitml_device = MTLCreateSystemDefaultDevice();"
    , "      jitml_queue = jitml_device == nil ? nil : [jitml_device newCommandQueue];"
    , "      jitml_pipeline_cache = [NSMutableDictionary dictionary];"
    , "    }"
    , "  }"
    , "}"
    , ""
    , "static id<MTLComputePipelineState> jitml_pipeline(NSString *source,"
    , "                                                  NSString *function_name,"
    , "                                                  size_t threadgroup_size,"
    , "                                                  char *error_buffer,"
    , "                                                  size_t error_buffer_len) {"
    , "  jitml_init();"
    , "  if (jitml_device == nil || jitml_queue == nil) {"
    , "    jitml_error(error_buffer, error_buffer_len, @\"Metal device or command queue unavailable\");"
    , "    return nil;"
    , "  }"
    , "  NSString *cache_key = [NSString stringWithFormat:@\"%@|%@|%zu\", function_name, source, threadgroup_size];"
    , "  @synchronized(jitml_pipeline_cache) {"
    , "    id<MTLComputePipelineState> cached = [jitml_pipeline_cache objectForKey:cache_key];"
    , "    if (cached != nil) { return cached; }"
    , "  }"
    , "  MTLCompileOptions *options = [MTLCompileOptions new];"
    , "  options.fastMathEnabled = NO;"
    , "  NSError *library_error = nil;"
    , "  id<MTLLibrary> library = [jitml_device newLibraryWithSource:source options:options error:&library_error];"
    , "  if (library == nil) {"
    , "    jitml_error(error_buffer, error_buffer_len, library_error.localizedDescription);"
    , "    return nil;"
    , "  }"
    , "  id<MTLFunction> function = [library newFunctionWithName:function_name];"
    , "  if (function == nil) {"
    , "    jitml_error(error_buffer, error_buffer_len, [NSString stringWithFormat:@\"Metal function not found: %@\", function_name]);"
    , "    return nil;"
    , "  }"
    , "  NSError *pipeline_error = nil;"
    , "  id<MTLComputePipelineState> pipeline = [jitml_device newComputePipelineStateWithFunction:function error:&pipeline_error];"
    , "  if (pipeline == nil) {"
    , "    jitml_error(error_buffer, error_buffer_len, pipeline_error.localizedDescription);"
    , "    return nil;"
    , "  }"
    , "  @synchronized(jitml_pipeline_cache) {"
    , "    [jitml_pipeline_cache setObject:pipeline forKey:cache_key];"
    , "  }"
    , "  return pipeline;"
    , "}"
    , ""
    , "int jitml_metal_bridge_probe(void) {"
    , "  @autoreleasepool {"
    , "    char error_buffer[1024];"
    , "    const char *probe_source ="
    , "      \"#include <metal_stdlib>\\n\""
    , "      \"using namespace metal;\\n\""
    , "      \"kernel void jitml_probe(device float *out [[buffer(0)]], uint id [[thread_position_in_grid]]) { if (id == 0) { out[0] = 1.0f; } }\\n\";"
    , "    NSString *source = [NSString stringWithUTF8String:probe_source];"
    , "    id<MTLComputePipelineState> pipeline = jitml_pipeline(source, @\"jitml_probe\", 1, error_buffer, sizeof(error_buffer));"
    , "    if (pipeline == nil) { return 1; }"
    , "    id<MTLBuffer> output = [jitml_device newBufferWithLength:sizeof(float) options:MTLResourceStorageModeShared];"
    , "    id<MTLCommandBuffer> command_buffer = [jitml_queue commandBuffer];"
    , "    id<MTLComputeCommandEncoder> encoder = [command_buffer computeCommandEncoder];"
    , "    if (output == nil || command_buffer == nil || encoder == nil) { return 2; }"
    , "    [encoder setComputePipelineState:pipeline];"
    , "    [encoder setBuffer:output offset:0 atIndex:0];"
    , "    [encoder dispatchThreadgroups:MTLSizeMake(1, 1, 1) threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];"
    , "    [encoder endEncoding];"
    , "    [command_buffer commit];"
    , "    [command_buffer waitUntilCompleted];"
    , "    if (command_buffer.error != nil) { return 3; }"
    , "    float value = ((float *)[output contents])[0];"
    , "    return value == 1.0f ? 0 : 4;"
    , "  }"
    , "}"
    , ""
    , "int jitml_metal_bridge_run(const char *metal_source,"
    , "                           const char *function_name,"
    , "                           const float *input,"
    , "                           size_t input_count,"
    , "                           const float *weights,"
    , "                           size_t weights_count,"
    , "                           float *output,"
    , "                           size_t output_count,"
    , "                           size_t threadgroup_size,"
    , "                           char *error_buffer,"
    , "                           size_t error_buffer_len) {"
    , "  @autoreleasepool {"
    , "    if (error_buffer != NULL && error_buffer_len > 0) { error_buffer[0] = '\\0'; }"
    , "    if (output != NULL && output_count > 0) { memset(output, 0, output_count * sizeof(float)); }"
    , "    if (metal_source == NULL || function_name == NULL || output == NULL) {"
    , "      return jitml_error(error_buffer, error_buffer_len, @\"Metal bridge received a null required pointer\");"
    , "    }"
    , "    if (output_count == 0) { return 0; }"
    , "    if (threadgroup_size == 0) {"
    , "      return jitml_error(error_buffer, error_buffer_len, @\"Metal bridge threadgroup size must be positive\");"
    , "    }"
    , "    NSString *source = [NSString stringWithUTF8String:metal_source];"
    , "    NSString *name = [NSString stringWithUTF8String:function_name];"
    , "    if (source == nil || name == nil) {"
    , "      return jitml_error(error_buffer, error_buffer_len, @\"Metal bridge received non-UTF8 source or function name\");"
    , "    }"
    , "    id<MTLComputePipelineState> pipeline = jitml_pipeline(source, name, threadgroup_size, error_buffer, error_buffer_len);"
    , "    if (pipeline == nil) { return 1; }"
    , "    size_t input_bytes = jitml_max_size(input_count, 1) * sizeof(float);"
    , "    size_t output_bytes = jitml_max_size(output_count, 1) * sizeof(float);"
    , "    id<MTLBuffer> input_buffer = input == NULL || input_count == 0"
    , "      ? [jitml_device newBufferWithLength:input_bytes options:MTLResourceStorageModeShared]"
    , "      : [jitml_device newBufferWithBytes:input length:input_bytes options:MTLResourceStorageModeShared];"
    , "    id<MTLBuffer> output_buffer = [jitml_device newBufferWithLength:output_bytes options:MTLResourceStorageModeShared];"
    , "    if (input_buffer == nil || output_buffer == nil) {"
    , "      return jitml_error(error_buffer, error_buffer_len, @\"Metal bridge failed to allocate input/output buffers\");"
    , "    }"
    , "    id<MTLBuffer> weights_buffer = nil;"
    , "    if (weights != NULL && weights_count > 0) {"
    , "      weights_buffer = [jitml_device newBufferWithBytes:weights length:(weights_count * sizeof(float)) options:MTLResourceStorageModeShared];"
    , "      if (weights_buffer == nil) {"
    , "        return jitml_error(error_buffer, error_buffer_len, @\"Metal bridge failed to allocate weights buffer\");"
    , "      }"
    , "    }"
    , "    id<MTLCommandBuffer> command_buffer = [jitml_queue commandBuffer];"
    , "    id<MTLComputeCommandEncoder> encoder = [command_buffer computeCommandEncoder];"
    , "    if (command_buffer == nil || encoder == nil) {"
    , "      return jitml_error(error_buffer, error_buffer_len, @\"Metal bridge failed to create command encoder\");"
    , "    }"
    , "    uint32_t n = input_count > UINT32_MAX ? UINT32_MAX : (uint32_t)input_count;"
    , "    uint32_t wn = weights_count > UINT32_MAX ? UINT32_MAX : (uint32_t)weights_count;"
    , "    [encoder setComputePipelineState:pipeline];"
    , "    [encoder setBuffer:output_buffer offset:0 atIndex:0];"
    , "    [encoder setBuffer:input_buffer offset:0 atIndex:1];"
    , "    if (weights_buffer != nil) { [encoder setBuffer:weights_buffer offset:0 atIndex:2]; }"
    , "    [encoder setBytes:&n length:sizeof(n) atIndex:3];"
    , "    [encoder setBytes:&wn length:sizeof(wn) atIndex:4];"
    , "    size_t dispatch_count = jitml_max_size(input_count, 1);"
    , "    size_t groups = (dispatch_count + threadgroup_size - 1) / threadgroup_size;"
    , "    [encoder dispatchThreadgroups:MTLSizeMake(groups, 1, 1) threadsPerThreadgroup:MTLSizeMake(threadgroup_size, 1, 1)];"
    , "    [encoder endEncoding];"
    , "    [command_buffer commit];"
    , "    [command_buffer waitUntilCompleted];"
    , "    if (command_buffer.error != nil) {"
    , "      return jitml_error(error_buffer, error_buffer_len, command_buffer.error.localizedDescription);"
    , "    }"
    , "    memcpy(output, [output_buffer contents], output_count * sizeof(float));"
    , "    return 0;"
    , "  }"
    , "}"
    , ""
    , "static id<MTLBuffer> jitml_float_buffer(const float *data, size_t count) {"
    , "  size_t bytes = jitml_max_size(count, 1) * sizeof(float);"
    , "  if (data == NULL || count == 0) {"
    , "    return [jitml_device newBufferWithLength:bytes options:MTLResourceStorageModeShared];"
    , "  }"
    , "  return [jitml_device newBufferWithBytes:data length:bytes options:MTLResourceStorageModeShared];"
    , "}"
    , ""
    , "static int jitml_commit(id<MTLCommandBuffer> command_buffer, char *error_buffer, size_t error_buffer_len) {"
    , "  [command_buffer commit];"
    , "  [command_buffer waitUntilCompleted];"
    , "  if (command_buffer.error != nil) {"
    , "    return jitml_error(error_buffer, error_buffer_len, command_buffer.error.localizedDescription);"
    , "  }"
    , "  return 0;"
    , "}"
    , ""
    , "static int jitml_dispatch_encoder(id<MTLCommandBuffer> command_buffer,"
    , "                                 id<MTLComputePipelineState> pipeline,"
    , "                                 size_t dispatch_count,"
    , "                                 size_t threadgroup_size,"
    , "                                 char *error_buffer,"
    , "                                 size_t error_buffer_len,"
    , "                                 id<MTLBuffer> b0, id<MTLBuffer> b1, id<MTLBuffer> b2,"
    , "                                 id<MTLBuffer> b3, id<MTLBuffer> b4, id<MTLBuffer> b5,"
    , "                                 const int *i0, int i0_index,"
    , "                                 const int *i1, int i1_index,"
    , "                                 const int *i2, int i2_index,"
    , "                                 const int *i3, int i3_index) {"
    , "  if (dispatch_count == 0) { return 0; }"
    , "  id<MTLComputeCommandEncoder> encoder = [command_buffer computeCommandEncoder];"
    , "  if (encoder == nil) {"
    , "    return jitml_error(error_buffer, error_buffer_len, @\"Metal bridge failed to create MLP command encoder\");"
    , "  }"
    , "  [encoder setComputePipelineState:pipeline];"
    , "  if (b0 != nil) { [encoder setBuffer:b0 offset:0 atIndex:0]; }"
    , "  if (b1 != nil) { [encoder setBuffer:b1 offset:0 atIndex:1]; }"
    , "  if (b2 != nil) { [encoder setBuffer:b2 offset:0 atIndex:2]; }"
    , "  if (b3 != nil) { [encoder setBuffer:b3 offset:0 atIndex:3]; }"
    , "  if (b4 != nil) { [encoder setBuffer:b4 offset:0 atIndex:4]; }"
    , "  if (b5 != nil) { [encoder setBuffer:b5 offset:0 atIndex:5]; }"
    , "  if (i0 != NULL) { [encoder setBytes:i0 length:sizeof(int) atIndex:i0_index]; }"
    , "  if (i1 != NULL) { [encoder setBytes:i1 length:sizeof(int) atIndex:i1_index]; }"
    , "  if (i2 != NULL) { [encoder setBytes:i2 length:sizeof(int) atIndex:i2_index]; }"
    , "  if (i3 != NULL) { [encoder setBytes:i3 length:sizeof(int) atIndex:i3_index]; }"
    , "  size_t groups = (dispatch_count + threadgroup_size - 1) / threadgroup_size;"
    , "  [encoder dispatchThreadgroups:MTLSizeMake(groups, 1, 1) threadsPerThreadgroup:MTLSizeMake(threadgroup_size, 1, 1)];"
    , "  [encoder endEncoding];"
    , "  return 0;"
    , "}"
    , ""
    , "int jitml_metal_bridge_mlp_forward(const char *metal_source,"
    , "                                  float *hidden_pre_out,"
    , "                                  float *hidden_act_out,"
    , "                                  float *output_out,"
    , "                                  const float *input,"
    , "                                  const float *w1,"
    , "                                  const float *b1,"
    , "                                  const float *w2,"
    , "                                  const float *b2,"
    , "                                  int inputs,"
    , "                                  int hidden,"
    , "                                  int outputs,"
    , "                                  size_t threadgroup_size,"
    , "                                  char *error_buffer,"
    , "                                  size_t error_buffer_len) {"
    , "  @autoreleasepool {"
    , "    if (error_buffer != NULL && error_buffer_len > 0) { error_buffer[0] = '\\0'; }"
    , "    if (metal_source == NULL || hidden_pre_out == NULL || hidden_act_out == NULL || output_out == NULL) {"
    , "      return jitml_error(error_buffer, error_buffer_len, @\"Metal MLP forward received a null required pointer\");"
    , "    }"
    , "    if (inputs < 0 || hidden < 0 || outputs < 0 || threadgroup_size == 0) {"
    , "      return jitml_error(error_buffer, error_buffer_len, @\"Metal MLP forward received invalid dimensions\");"
    , "    }"
    , "    if (hidden == 0 || outputs == 0) { return 0; }"
    , "    NSString *source = [NSString stringWithUTF8String:metal_source];"
    , "    if (source == nil) { return jitml_error(error_buffer, error_buffer_len, @\"Metal MLP source is not UTF-8\"); }"
    , "    id<MTLComputePipelineState> hidden_pipe = jitml_pipeline(source, @\"jitml_mlp_hidden\", threadgroup_size, error_buffer, error_buffer_len);"
    , "    id<MTLComputePipelineState> output_pipe = jitml_pipeline(source, @\"jitml_mlp_output\", threadgroup_size, error_buffer, error_buffer_len);"
    , "    if (hidden_pipe == nil || output_pipe == nil) { return 1; }"
    , "    id<MTLBuffer> hidden_pre = jitml_float_buffer(NULL, hidden);"
    , "    id<MTLBuffer> hidden_act = jitml_float_buffer(NULL, hidden);"
    , "    id<MTLBuffer> output = jitml_float_buffer(NULL, outputs);"
    , "    id<MTLBuffer> input_buf = jitml_float_buffer(input, inputs);"
    , "    id<MTLBuffer> w1_buf = jitml_float_buffer(w1, ((size_t)hidden) * ((size_t)jitml_max_size(inputs, 0)));"
    , "    id<MTLBuffer> b1_buf = jitml_float_buffer(b1, hidden);"
    , "    id<MTLBuffer> w2_buf = jitml_float_buffer(w2, ((size_t)outputs) * ((size_t)hidden));"
    , "    id<MTLBuffer> b2_buf = jitml_float_buffer(b2, outputs);"
    , "    if (hidden_pre == nil || hidden_act == nil || output == nil || input_buf == nil || w1_buf == nil || b1_buf == nil || w2_buf == nil || b2_buf == nil) {"
    , "      return jitml_error(error_buffer, error_buffer_len, @\"Metal MLP forward failed to allocate buffers\");"
    , "    }"
    , "    id<MTLCommandBuffer> command_buffer = [jitml_queue commandBuffer];"
    , "    if (command_buffer == nil) { return jitml_error(error_buffer, error_buffer_len, @\"Metal MLP forward failed to create command buffer\"); }"
    , "    int rc = jitml_dispatch_encoder(command_buffer, hidden_pipe, hidden, threadgroup_size, error_buffer, error_buffer_len, hidden_pre, hidden_act, input_buf, w1_buf, b1_buf, nil, &inputs, 5, &hidden, 6, NULL, 0, NULL, 0);"
    , "    if (rc != 0) { return rc; }"
    , "    rc = jitml_dispatch_encoder(command_buffer, output_pipe, outputs, threadgroup_size, error_buffer, error_buffer_len, output, hidden_act, w2_buf, b2_buf, nil, nil, &hidden, 4, &outputs, 5, NULL, 0, NULL, 0);"
    , "    if (rc != 0) { return rc; }"
    , "    rc = jitml_commit(command_buffer, error_buffer, error_buffer_len);"
    , "    if (rc != 0) { return rc; }"
    , "    memcpy(hidden_pre_out, [hidden_pre contents], ((size_t)hidden) * sizeof(float));"
    , "    memcpy(hidden_act_out, [hidden_act contents], ((size_t)hidden) * sizeof(float));"
    , "    memcpy(output_out, [output contents], ((size_t)outputs) * sizeof(float));"
    , "    return 0;"
    , "  }"
    , "}"
    , ""
    , "int jitml_metal_bridge_mlp_backward(const char *metal_source,"
    , "                                   float *g_w1_out,"
    , "                                   float *g_b1_out,"
    , "                                   float *g_w2_out,"
    , "                                   float *g_b2_out,"
    , "                                   const float *d_l_dy,"
    , "                                   const float *input,"
    , "                                   const float *hidden_act_in,"
    , "                                   const float *w2,"
    , "                                   int inputs,"
    , "                                   int hidden,"
    , "                                   int outputs,"
    , "                                   size_t threadgroup_size,"
    , "                                   char *error_buffer,"
    , "                                   size_t error_buffer_len) {"
    , "  @autoreleasepool {"
    , "    if (error_buffer != NULL && error_buffer_len > 0) { error_buffer[0] = '\\0'; }"
    , "    if (metal_source == NULL || g_w1_out == NULL || g_b1_out == NULL || g_w2_out == NULL || g_b2_out == NULL) {"
    , "      return jitml_error(error_buffer, error_buffer_len, @\"Metal MLP backward received a null required pointer\");"
    , "    }"
    , "    if (inputs < 0 || hidden < 0 || outputs < 0 || threadgroup_size == 0) {"
    , "      return jitml_error(error_buffer, error_buffer_len, @\"Metal MLP backward received invalid dimensions\");"
    , "    }"
    , "    if (hidden == 0 || outputs == 0) { return 0; }"
    , "    NSString *source = [NSString stringWithUTF8String:metal_source];"
    , "    if (source == nil) { return jitml_error(error_buffer, error_buffer_len, @\"Metal MLP source is not UTF-8\"); }"
    , "    id<MTLComputePipelineState> grad_output_pipe = jitml_pipeline(source, @\"jitml_mlp_grad_output\", threadgroup_size, error_buffer, error_buffer_len);"
    , "    id<MTLComputePipelineState> grad_hidden_pipe = jitml_pipeline(source, @\"jitml_mlp_grad_hidden\", threadgroup_size, error_buffer, error_buffer_len);"
    , "    if (grad_output_pipe == nil || grad_hidden_pipe == nil) { return 1; }"
    , "    id<MTLBuffer> g_w1 = jitml_float_buffer(NULL, ((size_t)hidden) * ((size_t)jitml_max_size(inputs, 0)));"
    , "    id<MTLBuffer> g_b1 = jitml_float_buffer(NULL, hidden);"
    , "    id<MTLBuffer> g_w2 = jitml_float_buffer(NULL, ((size_t)outputs) * ((size_t)hidden));"
    , "    id<MTLBuffer> g_b2 = jitml_float_buffer(NULL, outputs);"
    , "    id<MTLBuffer> dy_buf = jitml_float_buffer(d_l_dy, outputs);"
    , "    id<MTLBuffer> input_buf = jitml_float_buffer(input, inputs);"
    , "    id<MTLBuffer> hidden_act = jitml_float_buffer(hidden_act_in, hidden);"
    , "    id<MTLBuffer> w2_buf = jitml_float_buffer(w2, ((size_t)outputs) * ((size_t)hidden));"
    , "    if (g_w1 == nil || g_b1 == nil || g_w2 == nil || g_b2 == nil || dy_buf == nil || input_buf == nil || hidden_act == nil || w2_buf == nil) {"
    , "      return jitml_error(error_buffer, error_buffer_len, @\"Metal MLP backward failed to allocate buffers\");"
    , "    }"
    , "    id<MTLCommandBuffer> command_buffer = [jitml_queue commandBuffer];"
    , "    if (command_buffer == nil) { return jitml_error(error_buffer, error_buffer_len, @\"Metal MLP backward failed to create command buffer\"); }"
    , "    int rc = jitml_dispatch_encoder(command_buffer, grad_output_pipe, outputs, threadgroup_size, error_buffer, error_buffer_len, g_w2, g_b2, dy_buf, hidden_act, nil, nil, &hidden, 4, &outputs, 5, NULL, 0, NULL, 0);"
    , "    if (rc != 0) { return rc; }"
    , "    rc = jitml_dispatch_encoder(command_buffer, grad_hidden_pipe, hidden, threadgroup_size, error_buffer, error_buffer_len, g_w1, g_b1, dy_buf, input_buf, hidden_act, w2_buf, &inputs, 6, &hidden, 7, &outputs, 8, NULL, 0);"
    , "    if (rc != 0) { return rc; }"
    , "    rc = jitml_commit(command_buffer, error_buffer, error_buffer_len);"
    , "    if (rc != 0) { return rc; }"
    , "    memcpy(g_w1_out, [g_w1 contents], ((size_t)hidden) * ((size_t)jitml_max_size(inputs, 0)) * sizeof(float));"
    , "    memcpy(g_b1_out, [g_b1 contents], ((size_t)hidden) * sizeof(float));"
    , "    memcpy(g_w2_out, [g_w2 contents], ((size_t)outputs) * ((size_t)hidden) * sizeof(float));"
    , "    memcpy(g_b2_out, [g_b2 contents], ((size_t)outputs) * sizeof(float));"
    , "    return 0;"
    , "  }"
    , "}"
    , ""
    , "int jitml_metal_bridge_mlp_forward_batch(const char *metal_source,"
    , "                                        float *output_out,"
    , "                                        const float *input,"
    , "                                        const float *w1,"
    , "                                        const float *b1,"
    , "                                        const float *w2,"
    , "                                        const float *b2,"
    , "                                        int inputs,"
    , "                                        int hidden,"
    , "                                        int outputs,"
    , "                                        int batch,"
    , "                                        size_t threadgroup_size,"
    , "                                        char *error_buffer,"
    , "                                        size_t error_buffer_len) {"
    , "  @autoreleasepool {"
    , "    if (error_buffer != NULL && error_buffer_len > 0) { error_buffer[0] = '\\0'; }"
    , "    if (metal_source == NULL || output_out == NULL) { return jitml_error(error_buffer, error_buffer_len, @\"Metal MLP batch forward received a null required pointer\"); }"
    , "    if (inputs < 0 || hidden < 0 || outputs < 0 || batch < 0 || threadgroup_size == 0) { return jitml_error(error_buffer, error_buffer_len, @\"Metal MLP batch forward received invalid dimensions\"); }"
    , "    if (hidden == 0 || outputs == 0 || batch == 0) { return 0; }"
    , "    NSString *source = [NSString stringWithUTF8String:metal_source];"
    , "    if (source == nil) { return jitml_error(error_buffer, error_buffer_len, @\"Metal MLP source is not UTF-8\"); }"
    , "    id<MTLComputePipelineState> hidden_pipe = jitml_pipeline(source, @\"jitml_mlp_batch_hidden\", threadgroup_size, error_buffer, error_buffer_len);"
    , "    id<MTLComputePipelineState> output_pipe = jitml_pipeline(source, @\"jitml_mlp_batch_output\", threadgroup_size, error_buffer, error_buffer_len);"
    , "    if (hidden_pipe == nil || output_pipe == nil) { return 1; }"
    , "    size_t batch_hidden = ((size_t)batch) * ((size_t)hidden);"
    , "    size_t batch_outputs = ((size_t)batch) * ((size_t)outputs);"
    , "    id<MTLBuffer> hidden_act = jitml_float_buffer(NULL, batch_hidden);"
    , "    id<MTLBuffer> output = jitml_float_buffer(NULL, batch_outputs);"
    , "    id<MTLBuffer> input_buf = jitml_float_buffer(input, ((size_t)batch) * ((size_t)jitml_max_size(inputs, 0)));"
    , "    id<MTLBuffer> w1_buf = jitml_float_buffer(w1, ((size_t)hidden) * ((size_t)jitml_max_size(inputs, 0)));"
    , "    id<MTLBuffer> b1_buf = jitml_float_buffer(b1, hidden);"
    , "    id<MTLBuffer> w2_buf = jitml_float_buffer(w2, ((size_t)outputs) * ((size_t)hidden));"
    , "    id<MTLBuffer> b2_buf = jitml_float_buffer(b2, outputs);"
    , "    if (hidden_act == nil || output == nil || input_buf == nil || w1_buf == nil || b1_buf == nil || w2_buf == nil || b2_buf == nil) { return jitml_error(error_buffer, error_buffer_len, @\"Metal MLP batch forward failed to allocate buffers\"); }"
    , "    id<MTLCommandBuffer> command_buffer = [jitml_queue commandBuffer];"
    , "    if (command_buffer == nil) { return jitml_error(error_buffer, error_buffer_len, @\"Metal MLP batch forward failed to create command buffer\"); }"
    , "    int rc = jitml_dispatch_encoder(command_buffer, hidden_pipe, batch_hidden, threadgroup_size, error_buffer, error_buffer_len, hidden_act, input_buf, w1_buf, b1_buf, nil, nil, &inputs, 4, &hidden, 5, &batch, 6, NULL, 0);"
    , "    if (rc != 0) { return rc; }"
    , "    rc = jitml_dispatch_encoder(command_buffer, output_pipe, batch_outputs, threadgroup_size, error_buffer, error_buffer_len, output, hidden_act, w2_buf, b2_buf, nil, nil, &hidden, 4, &outputs, 5, &batch, 6, NULL, 0);"
    , "    if (rc != 0) { return rc; }"
    , "    rc = jitml_commit(command_buffer, error_buffer, error_buffer_len);"
    , "    if (rc != 0) { return rc; }"
    , "    memcpy(output_out, [output contents], batch_outputs * sizeof(float));"
    , "    return 0;"
    , "  }"
    , "}"
    , ""
    , "int jitml_metal_bridge_mlp_batch_gradient(const char *metal_source,"
    , "                                         float *g_w1_out,"
    , "                                         float *g_b1_out,"
    , "                                         float *g_w2_out,"
    , "                                         float *g_b2_out,"
    , "                                         const float *input,"
    , "                                         const float *d_l_dy,"
    , "                                         const float *w1,"
    , "                                         const float *b1,"
    , "                                         const float *w2,"
    , "                                         int inputs,"
    , "                                         int hidden,"
    , "                                         int outputs,"
    , "                                         int batch,"
    , "                                         size_t threadgroup_size,"
    , "                                         char *error_buffer,"
    , "                                         size_t error_buffer_len) {"
    , "  @autoreleasepool {"
    , "    if (error_buffer != NULL && error_buffer_len > 0) { error_buffer[0] = '\\0'; }"
    , "    if (metal_source == NULL || g_w1_out == NULL || g_b1_out == NULL || g_w2_out == NULL || g_b2_out == NULL) { return jitml_error(error_buffer, error_buffer_len, @\"Metal MLP batch gradient received a null required pointer\"); }"
    , "    if (inputs < 0 || hidden < 0 || outputs < 0 || batch < 0 || threadgroup_size == 0) { return jitml_error(error_buffer, error_buffer_len, @\"Metal MLP batch gradient received invalid dimensions\"); }"
    , "    if (hidden == 0 || outputs == 0 || batch == 0) { return 0; }"
    , "    NSString *source = [NSString stringWithUTF8String:metal_source];"
    , "    if (source == nil) { return jitml_error(error_buffer, error_buffer_len, @\"Metal MLP source is not UTF-8\"); }"
    , "    id<MTLComputePipelineState> hidden_pipe = jitml_pipeline(source, @\"jitml_mlp_batch_hidden\", threadgroup_size, error_buffer, error_buffer_len);"
    , "    id<MTLComputePipelineState> grad_output_pipe = jitml_pipeline(source, @\"jitml_mlp_batch_grad_output\", threadgroup_size, error_buffer, error_buffer_len);"
    , "    id<MTLComputePipelineState> grad_hidden_pipe = jitml_pipeline(source, @\"jitml_mlp_batch_grad_hidden\", threadgroup_size, error_buffer, error_buffer_len);"
    , "    if (hidden_pipe == nil || grad_output_pipe == nil || grad_hidden_pipe == nil) { return 1; }"
    , "    size_t batch_hidden = ((size_t)batch) * ((size_t)hidden);"
    , "    id<MTLBuffer> hidden_act = jitml_float_buffer(NULL, batch_hidden);"
    , "    id<MTLBuffer> g_w1 = jitml_float_buffer(NULL, ((size_t)hidden) * ((size_t)jitml_max_size(inputs, 0)));"
    , "    id<MTLBuffer> g_b1 = jitml_float_buffer(NULL, hidden);"
    , "    id<MTLBuffer> g_w2 = jitml_float_buffer(NULL, ((size_t)outputs) * ((size_t)hidden));"
    , "    id<MTLBuffer> g_b2 = jitml_float_buffer(NULL, outputs);"
    , "    id<MTLBuffer> input_buf = jitml_float_buffer(input, ((size_t)batch) * ((size_t)jitml_max_size(inputs, 0)));"
    , "    id<MTLBuffer> dy_buf = jitml_float_buffer(d_l_dy, ((size_t)batch) * ((size_t)outputs));"
    , "    id<MTLBuffer> w1_buf = jitml_float_buffer(w1, ((size_t)hidden) * ((size_t)jitml_max_size(inputs, 0)));"
    , "    id<MTLBuffer> b1_buf = jitml_float_buffer(b1, hidden);"
    , "    id<MTLBuffer> w2_buf = jitml_float_buffer(w2, ((size_t)outputs) * ((size_t)hidden));"
    , "    if (hidden_act == nil || g_w1 == nil || g_b1 == nil || g_w2 == nil || g_b2 == nil || input_buf == nil || dy_buf == nil || w1_buf == nil || b1_buf == nil || w2_buf == nil) { return jitml_error(error_buffer, error_buffer_len, @\"Metal MLP batch gradient failed to allocate buffers\"); }"
    , "    id<MTLCommandBuffer> command_buffer = [jitml_queue commandBuffer];"
    , "    if (command_buffer == nil) { return jitml_error(error_buffer, error_buffer_len, @\"Metal MLP batch gradient failed to create command buffer\"); }"
    , "    int rc = jitml_dispatch_encoder(command_buffer, hidden_pipe, batch_hidden, threadgroup_size, error_buffer, error_buffer_len, hidden_act, input_buf, w1_buf, b1_buf, nil, nil, &inputs, 4, &hidden, 5, &batch, 6, NULL, 0);"
    , "    if (rc != 0) { return rc; }"
    , "    rc = jitml_dispatch_encoder(command_buffer, grad_output_pipe, outputs, threadgroup_size, error_buffer, error_buffer_len, g_w2, g_b2, dy_buf, hidden_act, nil, nil, &hidden, 4, &outputs, 5, &batch, 6, NULL, 0);"
    , "    if (rc != 0) { return rc; }"
    , "    rc = jitml_dispatch_encoder(command_buffer, grad_hidden_pipe, hidden, threadgroup_size, error_buffer, error_buffer_len, g_w1, g_b1, dy_buf, input_buf, hidden_act, w2_buf, &inputs, 6, &hidden, 7, &outputs, 8, &batch, 9);"
    , "    if (rc != 0) { return rc; }"
    , "    rc = jitml_commit(command_buffer, error_buffer, error_buffer_len);"
    , "    if (rc != 0) { return rc; }"
    , "    memcpy(g_w1_out, [g_w1 contents], ((size_t)hidden) * ((size_t)jitml_max_size(inputs, 0)) * sizeof(float));"
    , "    memcpy(g_b1_out, [g_b1 contents], ((size_t)hidden) * sizeof(float));"
    , "    memcpy(g_w2_out, [g_w2 contents], ((size_t)outputs) * ((size_t)hidden) * sizeof(float));"
    , "    memcpy(g_b2_out, [g_b2 contents], ((size_t)outputs) * sizeof(float));"
    , "    return 0;"
    , "  }"
    , "}"
    , ""
    , "int jitml_metal_bridge_mlp_input_gradient_batch(const char *metal_source,"
    , "                                                float *dx_out,"
    , "                                                const float *input,"
    , "                                                const float *d_l_dy,"
    , "                                                const float *w1,"
    , "                                                const float *b1,"
    , "                                                const float *w2,"
    , "                                                int inputs,"
    , "                                                int hidden,"
    , "                                                int outputs,"
    , "                                                int batch,"
    , "                                                size_t threadgroup_size,"
    , "                                                char *error_buffer,"
    , "                                                size_t error_buffer_len) {"
    , "  @autoreleasepool {"
    , "    if (error_buffer != NULL && error_buffer_len > 0) { error_buffer[0] = '\\0'; }"
    , "    if (metal_source == NULL || dx_out == NULL) { return jitml_error(error_buffer, error_buffer_len, @\"Metal MLP input-gradient received a null required pointer\"); }"
    , "    if (inputs < 0 || hidden < 0 || outputs < 0 || batch < 0 || threadgroup_size == 0) { return jitml_error(error_buffer, error_buffer_len, @\"Metal MLP input-gradient received invalid dimensions\"); }"
    , "    if (hidden == 0 || outputs == 0 || inputs == 0 || batch == 0) { return 0; }"
    , "    NSString *source = [NSString stringWithUTF8String:metal_source];"
    , "    if (source == nil) { return jitml_error(error_buffer, error_buffer_len, @\"Metal MLP source is not UTF-8\"); }"
    , "    id<MTLComputePipelineState> hidden_pipe = jitml_pipeline(source, @\"jitml_mlp_batch_hidden\", threadgroup_size, error_buffer, error_buffer_len);"
    , "    id<MTLComputePipelineState> dpre_pipe = jitml_pipeline(source, @\"jitml_mlp_dpre_batch\", threadgroup_size, error_buffer, error_buffer_len);"
    , "    id<MTLComputePipelineState> dx_pipe = jitml_pipeline(source, @\"jitml_mlp_dx_batch\", threadgroup_size, error_buffer, error_buffer_len);"
    , "    if (hidden_pipe == nil || dpre_pipe == nil || dx_pipe == nil) { return 1; }"
    , "    size_t batch_hidden = ((size_t)batch) * ((size_t)hidden);"
    , "    size_t batch_inputs = ((size_t)batch) * ((size_t)inputs);"
    , "    id<MTLBuffer> hidden_act = jitml_float_buffer(NULL, batch_hidden);"
    , "    id<MTLBuffer> dpre = jitml_float_buffer(NULL, batch_hidden);"
    , "    id<MTLBuffer> dx = jitml_float_buffer(NULL, batch_inputs);"
    , "    id<MTLBuffer> input_buf = jitml_float_buffer(input, batch_inputs);"
    , "    id<MTLBuffer> dy_buf = jitml_float_buffer(d_l_dy, ((size_t)batch) * ((size_t)outputs));"
    , "    id<MTLBuffer> w1_buf = jitml_float_buffer(w1, ((size_t)hidden) * ((size_t)inputs));"
    , "    id<MTLBuffer> b1_buf = jitml_float_buffer(b1, hidden);"
    , "    id<MTLBuffer> w2_buf = jitml_float_buffer(w2, ((size_t)outputs) * ((size_t)hidden));"
    , "    if (hidden_act == nil || dpre == nil || dx == nil || input_buf == nil || dy_buf == nil || w1_buf == nil || b1_buf == nil || w2_buf == nil) { return jitml_error(error_buffer, error_buffer_len, @\"Metal MLP input-gradient failed to allocate buffers\"); }"
    , "    id<MTLCommandBuffer> command_buffer = [jitml_queue commandBuffer];"
    , "    if (command_buffer == nil) { return jitml_error(error_buffer, error_buffer_len, @\"Metal MLP input-gradient failed to create command buffer\"); }"
    , "    int rc = jitml_dispatch_encoder(command_buffer, hidden_pipe, batch_hidden, threadgroup_size, error_buffer, error_buffer_len, hidden_act, input_buf, w1_buf, b1_buf, nil, nil, &inputs, 4, &hidden, 5, &batch, 6, NULL, 0);"
    , "    if (rc != 0) { return rc; }"
    , "    rc = jitml_dispatch_encoder(command_buffer, dpre_pipe, batch_hidden, threadgroup_size, error_buffer, error_buffer_len, dpre, dy_buf, hidden_act, w2_buf, nil, nil, &hidden, 4, &outputs, 5, &batch, 6, NULL, 0);"
    , "    if (rc != 0) { return rc; }"
    , "    rc = jitml_dispatch_encoder(command_buffer, dx_pipe, batch_inputs, threadgroup_size, error_buffer, error_buffer_len, dx, dpre, w1_buf, nil, nil, nil, &inputs, 3, &hidden, 4, &batch, 5, NULL, 0);"
    , "    if (rc != 0) { return rc; }"
    , "    rc = jitml_commit(command_buffer, error_buffer, error_buffer_len);"
    , "    if (rc != 0) { return rc; }"
    , "    memcpy(dx_out, [dx contents], batch_inputs * sizeof(float));"
    , "    return 0;"
    , "  }"
    , "}"
    ]

peekCStringLenNul :: Ptr CChar -> Int -> IO String
peekCStringLenNul ptr len = go 0 []
 where
  go index acc
    | index >= len = pure (reverse acc)
    | otherwise = do
        char <- peekElemOff ptr index
        if char == 0
          then pure (reverse acc)
          else go (index + 1) (toEnum (fromEnum char) : acc)
