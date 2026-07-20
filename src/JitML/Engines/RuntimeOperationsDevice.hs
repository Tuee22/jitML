{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Shared host runner for generated supervised-runtime structural kernels.
--
-- The ABI is deliberately substrate-neutral: implementations expose the same
-- version/capability probes and @double@ buffer operations.  Linux CPU uses a
-- generated shared object today; CUDA can put launches behind the same C ABI,
-- while Metal can use the same operation contract through its fixed bridge.
module JitML.Engines.RuntimeOperationsDevice
  ( RuntimeOperation (..)
  , RuntimeOperationsArtifact (..)
  , RuntimeOperationsBackendSpec (..)
  , RuntimeOperationsDeviceError (..)
  , linuxCpuRuntimeOperationsSpec
  , probeRuntimeOperationsBackend
  , probeRuntimeOperationsSymbol
  , renderRuntimeOperationsDeviceError
  , runtimeOperationsAbiVersion
  , runtimeOperationsAllCapabilities
  , runtimeOperationCapability
  , runtimeOperationsBackendExecutor
  , runtimeOperationsInputTransform
  , runtimeOperationsOutputTransform
  , runtimeOperationsResidualAdd
  , runtimeOperationsLayerNorm
  , runtimeOperationsTokenMix
  , runtimeOperationsPatchExtract
  , runtimeOperationsAttention
  , runtimeOperationsMeanPool
  , runtimeOperationsCpuHash
  , runtimeOperationsCpuRuntimeSource
  , runtimeOperationsCpuToolchainFingerprint
  )
where

import Control.Exception.Safe (displayException, tryAny)
import Control.Monad (void)
import Data.Bits (shiftL, (.&.), (.|.))
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word32, Word64)
import Foreign.C.Types
  ( CDouble (..)
  , CInt (..)
  , CLLong (..)
  , CSize (..)
  , CUInt (..)
  , CULLong (..)
  )
import Foreign.Marshal.Array (allocaArray, peekArray, withArray)
import Foreign.Ptr (FunPtr, Ptr)
import System.Info qualified as SystemInfo

import JitML.Cache.Key qualified as Cache
import JitML.Codegen.RuntimeOperationsCpu
  ( renderRuntimeOperationsCpuSource
  , runtimeOperationsCpuKernelSpec
  )
import JitML.Codegen.RuntimeSource
  ( RuntimeSource (..)
  , runtimeSourcePayload
  )
import JitML.Engines.Engine
  ( Engine
  , KernelHandle (..)
  , engineForSubstrate
  )
import JitML.Engines.Loader
  ( ensureKernelArtifact
  , kernelArtifactCompileCommand
  , kernelArtifactCompiled
  , kernelArtifactHandle
  , loadKernelLibrary
  , renderKernelArtifactError
  , withKernelSymbol
  )
import JitML.Env.Env (Env)
import JitML.Numerics.Mlp (MlpParams)
import JitML.SL.RuntimeArtifact qualified as Runtime
import JitML.Substrate (Substrate (..))

data RuntimeOperation
  = RuntimeInputTransformOperation
  | RuntimeOutputTransformOperation
  | RuntimeResidualAddOperation
  | RuntimeLayerNormOperation
  | RuntimeTokenMixOperation
  | RuntimePatchExtractOperation
  | RuntimeAttentionOperation
  | RuntimeMeanPoolOperation
  deriving stock (Bounded, Enum, Eq, Ord, Show)

runtimeOperationsAbiVersion :: Word32
runtimeOperationsAbiVersion = 1

runtimeOperationCapability :: RuntimeOperation -> Word64
runtimeOperationCapability operation = shiftL 1 (fromEnum operation)

runtimeOperationsAllCapabilities :: Word64
runtimeOperationsAllCapabilities =
  foldr
    ((.|.) . runtimeOperationCapability)
    0
    [minBound .. maxBound]

data RuntimeOperationsBackendSpec = RuntimeOperationsBackendSpec
  { runtimeOperationsBackendLabel :: !Text
  , runtimeOperationsBackendEngine :: !Engine
  , runtimeOperationsBackendSource :: !RuntimeSource
  , runtimeOperationsBackendHash :: !Cache.Hash
  , runtimeOperationsBackendExpectedAbi :: !Word32
  , runtimeOperationsBackendRequiredCapabilities :: !Word64
  }
  deriving stock (Eq, Show)

data RuntimeOperationsArtifact = RuntimeOperationsArtifact
  { runtimeOperationsArtifactHandle :: !KernelHandle
  , runtimeOperationsArtifactCompiled :: !Bool
  , runtimeOperationsArtifactCompileCommand :: !Text
  , runtimeOperationsArtifactAbiVersion :: !Word32
  , runtimeOperationsArtifactCapabilities :: !Word64
  }
  deriving stock (Eq, Show)

data RuntimeOperationsDeviceError
  = RuntimeOperationsCompileError !Text
  | RuntimeOperationsLoadError !Text
  | RuntimeOperationsSymbolError !Text !Text
  | RuntimeOperationsAbiMismatch
      { runtimeOperationsExpectedAbi :: !Word32
      , runtimeOperationsActualAbi :: !Word32
      }
  | RuntimeOperationsCapabilityMismatch
      { runtimeOperationsErrorRequiredCapabilities :: !Word64
      , runtimeOperationsErrorActualCapabilities :: !Word64
      }
  | RuntimeOperationsCapabilityMissing !RuntimeOperation
  | RuntimeOperationsContractError !RuntimeOperation !Text
  | RuntimeOperationsNativeStatus !RuntimeOperation !Int
  | RuntimeOperationsExecutionError !Text !Text
  | RuntimeOperationsBackendCallbackError !RuntimeOperation !Text
  deriving stock (Eq, Show)

renderRuntimeOperationsDeviceError :: RuntimeOperationsDeviceError -> Text
renderRuntimeOperationsDeviceError err =
  case err of
    RuntimeOperationsCompileError detail -> "compile failed: " <> detail
    RuntimeOperationsLoadError detail -> "artifact load failed: " <> detail
    RuntimeOperationsSymbolError symbol detail ->
      "symbol resolution failed for " <> symbol <> ": " <> detail
    RuntimeOperationsAbiMismatch expected actual ->
      "ABI version mismatch: expected "
        <> showText expected
        <> ", got "
        <> showText actual
    RuntimeOperationsCapabilityMismatch required actual ->
      "capability mask mismatch: required "
        <> showText required
        <> ", got "
        <> showText actual
    RuntimeOperationsCapabilityMissing operation ->
      "native capability missing for " <> operationText operation
    RuntimeOperationsContractError operation detail ->
      operationText operation <> " contract: " <> detail
    RuntimeOperationsNativeStatus operation status ->
      operationText operation
        <> " native status "
        <> showText status
        <> " ("
        <> nativeStatusText status
        <> ")"
    RuntimeOperationsExecutionError stage detail ->
      stage <> " execution exception: " <> detail
    RuntimeOperationsBackendCallbackError operation detail ->
      operationText operation <> " selected-backend MLP callback: " <> detail

runtimeOperationsCpuRuntimeSource :: RuntimeSource
runtimeOperationsCpuRuntimeSource =
  GeneratedOneDnnSource
    { runtimeSourceKernel = runtimeOperationsCpuKernelSpec
    , runtimeSourceKind = Cache.Inference
    , runtimeSourceTuning = Cache.defaultTuningChoice
    , runtimeSourceFiles = renderRuntimeOperationsCpuSource
    }

runtimeOperationsCpuToolchainFingerprint :: Cache.ToolchainFingerprint
runtimeOperationsCpuToolchainFingerprint =
  Cache.ToolchainFingerprint
    ( Text.intercalate
        ";"
        [ "g++-shared-c++20-O2-fPIC"
        , "artifact-abi=" <> Text.pack SystemInfo.os <> "-" <> Text.pack SystemInfo.arch
        , "abi=jitml-runtime-operations-v1-double"
        , "capabilities=0xff"
        , "reductions=sequential-fixed-order"
        , "softmax=max-shifted-sequential"
        , "jitml_runtime_operations_abi_version(void)"
        , "jitml_runtime_operations_capabilities(void)"
        , "jitml_runtime_input_transform"
        , "jitml_runtime_output_transform"
        , "jitml_runtime_residual_add"
        , "jitml_runtime_layer_norm"
        , "jitml_runtime_token_mix_pack"
        , "jitml_runtime_token_mix_merge"
        , "jitml_runtime_patch_extract"
        , "jitml_runtime_attention"
        , "jitml_runtime_mean_pool"
        ]
    )

runtimeOperationsCpuHash :: Cache.Hash
runtimeOperationsCpuHash =
  Cache.cacheKey
    runtimeOperationsCpuKernelSpec
    Cache.Inference
    Cache.LinuxCPU
    runtimeOperationsCpuToolchainFingerprint
    (runtimeSourcePayload runtimeOperationsCpuRuntimeSource)
    Cache.defaultTuningChoice

linuxCpuRuntimeOperationsSpec :: RuntimeOperationsBackendSpec
linuxCpuRuntimeOperationsSpec =
  RuntimeOperationsBackendSpec
    { runtimeOperationsBackendLabel = "linux-cpu"
    , runtimeOperationsBackendEngine = engineForSubstrate LinuxCPU
    , runtimeOperationsBackendSource = runtimeOperationsCpuRuntimeSource
    , runtimeOperationsBackendHash = runtimeOperationsCpuHash
    , runtimeOperationsBackendExpectedAbi = runtimeOperationsAbiVersion
    , runtimeOperationsBackendRequiredCapabilities = runtimeOperationsAllCapabilities
    }

-- ABI ------------------------------------------------------------------------

type AbiVersionFunction = IO CUInt
type CapabilitiesFunction = IO CULLong

type InputTransformFunction =
  Ptr CDouble
  -> Ptr CDouble
  -> CSize
  -> CUInt
  -> Ptr CDouble
  -> Ptr CDouble
  -> CSize
  -> IO CInt

type OutputTransformFunction =
  Ptr CDouble
  -> CSize
  -> Ptr CDouble
  -> CSize
  -> CUInt
  -> Ptr CDouble
  -> Ptr CDouble
  -> CSize
  -> IO CInt

type ResidualAddFunction =
  Ptr CDouble
  -> Ptr CDouble
  -> Ptr CDouble
  -> CSize
  -> CDouble
  -> IO CInt

type LayerNormFunction =
  Ptr CDouble -> Ptr CDouble -> CSize -> IO CInt

type TokenMixPackFunction =
  Ptr CDouble -> Ptr CDouble -> CSize -> CSize -> IO CInt

type TokenMixMergeFunction =
  Ptr CDouble
  -> Ptr CDouble
  -> Ptr CDouble
  -> CSize
  -> CSize
  -> IO CInt

type PatchExtractFunction =
  Ptr CDouble
  -> CSize
  -> CSize
  -> Ptr CDouble
  -> CSize
  -> Ptr CLLong
  -> CSize
  -> CSize
  -> CSize
  -> CSize
  -> IO CInt

type AttentionFunction =
  Ptr CDouble
  -> Ptr CDouble
  -> Ptr CDouble
  -> CSize
  -> CSize
  -> IO CInt

type MeanPoolFunction =
  Ptr CDouble -> Ptr CDouble -> CSize -> CSize -> IO CInt

foreign import ccall "dynamic"
  mkAbiVersionFunction :: FunPtr AbiVersionFunction -> AbiVersionFunction

foreign import ccall "dynamic"
  mkCapabilitiesFunction :: FunPtr CapabilitiesFunction -> CapabilitiesFunction

foreign import ccall "dynamic"
  mkInputTransformFunction :: FunPtr InputTransformFunction -> InputTransformFunction

foreign import ccall "dynamic"
  mkOutputTransformFunction :: FunPtr OutputTransformFunction -> OutputTransformFunction

foreign import ccall "dynamic"
  mkResidualAddFunction :: FunPtr ResidualAddFunction -> ResidualAddFunction

foreign import ccall "dynamic"
  mkLayerNormFunction :: FunPtr LayerNormFunction -> LayerNormFunction

foreign import ccall "dynamic"
  mkTokenMixPackFunction :: FunPtr TokenMixPackFunction -> TokenMixPackFunction

foreign import ccall "dynamic"
  mkTokenMixMergeFunction :: FunPtr TokenMixMergeFunction -> TokenMixMergeFunction

foreign import ccall "dynamic"
  mkPatchExtractFunction :: FunPtr PatchExtractFunction -> PatchExtractFunction

foreign import ccall "dynamic"
  mkAttentionFunction :: FunPtr AttentionFunction -> AttentionFunction

foreign import ccall "dynamic"
  mkMeanPoolFunction :: FunPtr MeanPoolFunction -> MeanPoolFunction

probeRuntimeOperationsBackend
  :: RuntimeOperationsBackendSpec
  -> Env
  -> IO (Either RuntimeOperationsDeviceError RuntimeOperationsArtifact)
probeRuntimeOperationsBackend spec env = do
  artifactResult <-
    ensureKernelArtifact
      env
      (runtimeOperationsBackendEngine spec)
      (runtimeOperationsBackendSource spec)
      (runtimeOperationsBackendHash spec)
  case artifactResult of
    Left err ->
      pure (Left (RuntimeOperationsCompileError (renderKernelArtifactError err)))
    Right artifact -> do
      let handle = kernelArtifactHandle artifact
          artifactPath = Text.unpack (kernelHandleArtifactPath handle)
      loadResult <- tryAny (loadKernelLibrary artifactPath)
      case loadResult of
        Left err ->
          pure
            ( Left
                (RuntimeOperationsLoadError (Text.pack (displayException err)))
            )
        Right () -> do
          probeResult <- loadRuntimeOperationsProbe artifactPath
          pure $ do
            (actualAbi, actualCapabilities) <- probeResult
            if actualAbi /= runtimeOperationsBackendExpectedAbi spec
              then
                Left
                  RuntimeOperationsAbiMismatch
                    { runtimeOperationsExpectedAbi = runtimeOperationsBackendExpectedAbi spec
                    , runtimeOperationsActualAbi = actualAbi
                    }
              else Right ()
            let required = runtimeOperationsBackendRequiredCapabilities spec
            if actualCapabilities .&. required /= required
              then
                Left
                  RuntimeOperationsCapabilityMismatch
                    { runtimeOperationsErrorRequiredCapabilities = required
                    , runtimeOperationsErrorActualCapabilities = actualCapabilities
                    }
              else Right ()
            Right
              RuntimeOperationsArtifact
                { runtimeOperationsArtifactHandle = handle
                , runtimeOperationsArtifactCompiled = kernelArtifactCompiled artifact
                , runtimeOperationsArtifactCompileCommand =
                    kernelArtifactCompileCommand artifact
                , runtimeOperationsArtifactAbiVersion = actualAbi
                , runtimeOperationsArtifactCapabilities = actualCapabilities
                }

loadRuntimeOperationsProbe
  :: FilePath
  -> IO (Either RuntimeOperationsDeviceError (Word32, Word64))
loadRuntimeOperationsProbe artifactPath = do
  abiResult <-
    resolveRuntimeOperationsSymbol
      artifactPath
      "jitml_runtime_operations_abi_version"
  case abiResult of
    Left err -> pure (Left err)
    Right abiSymbol -> do
      capabilitiesResult <-
        resolveRuntimeOperationsSymbol
          artifactPath
          "jitml_runtime_operations_capabilities"
      case capabilitiesResult of
        Left err -> pure (Left err)
        Right capabilitiesSymbol -> do
          invoked <- tryAny $ do
            CUInt abi <- mkAbiVersionFunction abiSymbol
            CULLong capabilities <- mkCapabilitiesFunction capabilitiesSymbol
            pure (fromIntegral abi, fromIntegral capabilities)
          pure
            ( mapLeft
                ( RuntimeOperationsExecutionError "ABI/capability probe"
                    . Text.pack
                    . displayException
                )
                invoked
            )

resolveRuntimeOperationsSymbol
  :: FilePath
  -> Text
  -> IO (Either RuntimeOperationsDeviceError (FunPtr symbol))
resolveRuntimeOperationsSymbol artifactPath symbolName = do
  resolved <-
    tryAny
      (withKernelSymbol artifactPath (Text.unpack symbolName) pure)
  pure
    ( mapLeft
        ( RuntimeOperationsSymbolError symbolName
            . Text.pack
            . displayException
        )
        resolved
    )

probeRuntimeOperationsSymbol
  :: RuntimeOperationsBackendSpec
  -> Env
  -> Text
  -> IO (Either RuntimeOperationsDeviceError ())
probeRuntimeOperationsSymbol spec env symbolName = do
  artifactResult <- probeRuntimeOperationsBackend spec env
  case artifactResult of
    Left err -> pure (Left err)
    Right artifact -> do
      let artifactPath =
            Text.unpack
              (kernelHandleArtifactPath (runtimeOperationsArtifactHandle artifact))
      void
        <$> ( resolveRuntimeOperationsSymbol artifactPath symbolName
                :: IO
                     ( Either
                         RuntimeOperationsDeviceError
                         (FunPtr (IO ()))
                     )
            )

runNativeOperation
  :: RuntimeOperationsBackendSpec
  -> Env
  -> RuntimeOperation
  -> Text
  -> (FunPtr symbol -> IO (Either Int value))
  -> IO (Either RuntimeOperationsDeviceError value)
runNativeOperation spec env operation symbolName action = do
  artifactResult <- probeRuntimeOperationsBackend spec env
  case artifactResult of
    Left err -> pure (Left err)
    Right artifact
      | runtimeOperationsArtifactCapabilities artifact
          .&. runtimeOperationCapability operation
          == 0 ->
          pure (Left (RuntimeOperationsCapabilityMissing operation))
      | otherwise -> do
          let artifactPath =
                Text.unpack
                  (kernelHandleArtifactPath (runtimeOperationsArtifactHandle artifact))
          symbolResult <- resolveRuntimeOperationsSymbol artifactPath symbolName
          case symbolResult of
            Left err -> pure (Left err)
            Right symbol -> do
              result <- tryAny (action symbol)
              pure $
                case result of
                  Left err ->
                    Left
                      ( RuntimeOperationsExecutionError
                          (operationText operation)
                          (Text.pack (displayException err))
                      )
                  Right (Left status) ->
                    Left (RuntimeOperationsNativeStatus operation status)
                  Right (Right value) -> Right value

-- Callbacks ------------------------------------------------------------------

runtimeOperationsBackendExecutor
  :: RuntimeOperationsBackendSpec
  -> Env
  -> Runtime.RuntimeMlpExecutor
  -> Runtime.RuntimeBackendExecutor
runtimeOperationsBackendExecutor spec env executeMlp = backend
 where
  backend =
    Runtime.RuntimeBackendExecutor
      { Runtime.runtimeBackendLabel = runtimeOperationsBackendLabel spec
      , Runtime.runtimeBackendInputTransformExecutor =
          runtimeOperationsInputTransform spec env
      , Runtime.runtimeBackendOutputTransformExecutor =
          runtimeOperationsOutputTransform spec env
      , Runtime.runtimeBackendMlpExecutor = executeMlpSafely
      , Runtime.runtimeBackendResidualAddExecutor =
          runtimeOperationsResidualAdd spec env
      , Runtime.runtimeBackendLayerNormExecutor =
          runtimeOperationsLayerNorm spec env
      , Runtime.runtimeBackendTokenMixExecutor =
          runtimeOperationsTokenMix spec env
      , Runtime.runtimeBackendPatchExtractExecutor =
          runtimeOperationsPatchExtract spec env
      , Runtime.runtimeBackendAttentionExecutor =
          runtimeOperationsAttention spec env
      , Runtime.runtimeBackendMeanPoolExecutor =
          runtimeOperationsMeanPool spec env
      }

  executeMlpSafely params input = do
    invoked <- tryAny (executeMlp params input)
    pure $
      case invoked of
        Left err ->
          Left
            ( renderRuntimeOperationsDeviceError
                ( RuntimeOperationsExecutionError
                    "MLP selected-backend callback"
                    (Text.pack (displayException err))
                )
            )
        Right result -> result

runtimeOperationsInputTransform
  :: RuntimeOperationsBackendSpec
  -> Env
  -> Runtime.RuntimeInputTransformExecutor
runtimeOperationsInputTransform spec env transform input =
  case inputTransformArguments transform input of
    Left err -> pure (Left (renderRuntimeOperationsDeviceError err))
    Right (transformCode, means, scales) ->
      fmap (mapLeft renderRuntimeOperationsDeviceError)
        $ runNativeOperation
          spec
          env
          RuntimeInputTransformOperation
          "jitml_runtime_input_transform"
        $ \symbol -> do
          let execute = mkInputTransformFunction symbol
              count = VU.length input
          withDoubleVector input $ \inputPtr ->
            withDoubleList means $ \meansPtr ->
              withDoubleList scales $ \scalesPtr ->
                allocaArray count $ \outputPtr -> do
                  status <-
                    execute
                      outputPtr
                      inputPtr
                      (fromIntegral count)
                      (fromIntegral transformCode)
                      meansPtr
                      scalesPtr
                      (fromIntegral (length means))
                  peekNativeVector status count outputPtr

runtimeOperationsOutputTransform
  :: RuntimeOperationsBackendSpec
  -> Env
  -> Runtime.RuntimeOutputTransformExecutor
runtimeOperationsOutputTransform spec env task transform input =
  case outputTransformArguments task transform input of
    Left err -> pure (Left (renderRuntimeOperationsDeviceError err))
    Right (outputCount, transformCode, means, scales) ->
      fmap (mapLeft renderRuntimeOperationsDeviceError)
        $ runNativeOperation
          spec
          env
          RuntimeOutputTransformOperation
          "jitml_runtime_output_transform"
        $ \symbol -> do
          let execute = mkOutputTransformFunction symbol
          withDoubleVector input $ \inputPtr ->
            withDoubleList means $ \meansPtr ->
              withDoubleList scales $ \scalesPtr ->
                allocaArray outputCount $ \outputPtr -> do
                  status <-
                    execute
                      outputPtr
                      (fromIntegral outputCount)
                      inputPtr
                      (fromIntegral (VU.length input))
                      (fromIntegral transformCode)
                      meansPtr
                      scalesPtr
                      (fromIntegral (length means))
                  peekNativeVector status outputCount outputPtr

runtimeOperationsResidualAdd
  :: RuntimeOperationsBackendSpec
  -> Env
  -> Runtime.RuntimeResidualAddExecutor
runtimeOperationsResidualAdd spec env scale input residual
  | VU.null input = callbackContract RuntimeResidualAddOperation "input is empty"
  | VU.length input /= VU.length residual =
      callbackContract RuntimeResidualAddOperation "input/residual widths differ"
  | otherwise =
      fmap (mapLeft renderRuntimeOperationsDeviceError)
        $ runNativeOperation
          spec
          env
          RuntimeResidualAddOperation
          "jitml_runtime_residual_add"
        $ \symbol -> do
          let execute = mkResidualAddFunction symbol
              count = VU.length input
          withDoubleVector input $ \inputPtr ->
            withDoubleVector residual $ \residualPtr ->
              allocaArray count $ \outputPtr -> do
                status <-
                  execute
                    outputPtr
                    inputPtr
                    residualPtr
                    (fromIntegral count)
                    (realToFrac scale)
                peekNativeVector status count outputPtr

runtimeOperationsLayerNorm
  :: RuntimeOperationsBackendSpec
  -> Env
  -> Runtime.RuntimeLayerNormExecutor
runtimeOperationsLayerNorm spec env input
  | VU.null input = callbackContract RuntimeLayerNormOperation "token width is zero"
  | otherwise =
      fmap (mapLeft renderRuntimeOperationsDeviceError)
        $ runNativeOperation
          spec
          env
          RuntimeLayerNormOperation
          "jitml_runtime_layer_norm"
        $ \symbol -> do
          let execute = mkLayerNormFunction symbol
              count = VU.length input
          withDoubleVector input $ \inputPtr ->
            allocaArray count $ \outputPtr -> do
              status <- execute outputPtr inputPtr (fromIntegral count)
              peekNativeVector status count outputPtr

runtimeOperationsTokenMix
  :: RuntimeOperationsBackendSpec
  -> Env
  -> Runtime.RuntimeTokenMixExecutor
runtimeOperationsTokenMix spec env backend layer tokenCount width shape params tokens =
  case validateTokens RuntimeTokenMixOperation tokenCount width tokens of
    Left err -> pure (Left (renderRuntimeOperationsDeviceError err))
    Right () -> do
      packedResult <- nativeTokenMixPack spec env tokenCount width tokens
      case packedResult of
        Left err -> pure (Left (renderRuntimeOperationsDeviceError err))
        Right packed -> do
          mixedResults <-
            traverse
              (runBackendMlp RuntimeTokenMixOperation backend layer shape params)
              (chunksOf tokenCount packed)
          case sequence mixedResults of
            Left err -> pure (Left (renderRuntimeOperationsDeviceError err))
            Right mixedChannels -> do
              mergedResult <-
                nativeTokenMixMerge spec env tokenCount width tokens mixedChannels
              pure (mapLeft renderRuntimeOperationsDeviceError mergedResult)

runtimeOperationsPatchExtract
  :: RuntimeOperationsBackendSpec
  -> Env
  -> Runtime.RuntimePatchExtractExecutor
runtimeOperationsPatchExtract spec env geometry positions input =
  case patchShape positions of
    Left detail -> callbackContract RuntimePatchExtractOperation detail
    Right valueWidth ->
      fmap (mapLeft renderRuntimeOperationsDeviceError)
        $ runNativeOperation
          spec
          env
          RuntimePatchExtractOperation
          "jitml_runtime_patch_extract"
        $ \symbol -> do
          let execute = mkPatchExtractFunction symbol
              patchCount = length positions
              patchWidth = valueWidth + 2
              outputCount = patchCount * patchWidth
              indices = fmap (fromIntegral @Int @CLLong) (concat positions)
          withDoubleVector input $ \inputPtr ->
            withArray indices $ \indicesPtr ->
              allocaArray outputCount $ \outputPtr -> do
                status <-
                  execute
                    outputPtr
                    (fromIntegral patchCount)
                    (fromIntegral patchWidth)
                    inputPtr
                    (fromIntegral (VU.length input))
                    indicesPtr
                    (fromIntegral (length indices))
                    (fromIntegral (Runtime.runtimeImageWidth geometry))
                    (fromIntegral (Runtime.runtimeImageHeight geometry))
                    (fromIntegral (Runtime.runtimeImageChannels geometry))
                flatResult <- peekNativeVector status outputCount outputPtr
                pure (fmap (chunksOf patchWidth) flatResult)

runtimeOperationsAttention
  :: RuntimeOperationsBackendSpec
  -> Env
  -> Runtime.RuntimeAttentionExecutor
runtimeOperationsAttention spec env backend layer width shape params tokens =
  case validateTokens RuntimeAttentionOperation (length tokens) width tokens of
    Left err -> pure (Left (renderRuntimeOperationsDeviceError err))
    Right () -> do
      qkvResults <-
        traverse
          (runBackendMlp RuntimeAttentionOperation backend layer shape params)
          tokens
      case sequence qkvResults of
        Left err -> pure (Left (renderRuntimeOperationsDeviceError err))
        Right qkvs ->
          fmap (mapLeft renderRuntimeOperationsDeviceError)
            $ runNativeOperation
              spec
              env
              RuntimeAttentionOperation
              "jitml_runtime_attention"
            $ \symbol -> do
              let execute = mkAttentionFunction symbol
                  tokenCount = length tokens
                  outputCount = tokenCount * width
              withDoubleList (concatMap VU.toList tokens) $ \tokensPtr ->
                withDoubleList (concatMap VU.toList qkvs) $ \qkvPtr ->
                  allocaArray outputCount $ \outputPtr -> do
                    status <-
                      execute
                        outputPtr
                        tokensPtr
                        qkvPtr
                        (fromIntegral tokenCount)
                        (fromIntegral width)
                    flatResult <- peekNativeVector status outputCount outputPtr
                    pure (fmap (chunksOf width) flatResult)

runtimeOperationsMeanPool
  :: RuntimeOperationsBackendSpec
  -> Env
  -> Runtime.RuntimeMeanPoolExecutor
runtimeOperationsMeanPool spec env tokens =
  case tokens of
    [] -> callbackContract RuntimeMeanPoolOperation "token sequence is empty"
    first : _ ->
      case validateTokens RuntimeMeanPoolOperation (length tokens) (VU.length first) tokens of
        Left err -> pure (Left (renderRuntimeOperationsDeviceError err))
        Right () ->
          fmap (mapLeft renderRuntimeOperationsDeviceError)
            $ runNativeOperation
              spec
              env
              RuntimeMeanPoolOperation
              "jitml_runtime_mean_pool"
            $ \symbol -> do
              let execute = mkMeanPoolFunction symbol
                  tokenCount = length tokens
                  width = VU.length first
              withDoubleList (concatMap VU.toList tokens) $ \tokensPtr ->
                allocaArray width $ \outputPtr -> do
                  status <-
                    execute
                      outputPtr
                      tokensPtr
                      (fromIntegral tokenCount)
                      (fromIntegral width)
                  peekNativeVector status width outputPtr

-- Callback orchestration -----------------------------------------------------

nativeTokenMixPack
  :: RuntimeOperationsBackendSpec
  -> Env
  -> Int
  -> Int
  -> [Vector Double]
  -> IO (Either RuntimeOperationsDeviceError (Vector Double))
nativeTokenMixPack spec env tokenCount width tokens =
  runNativeOperation
    spec
    env
    RuntimeTokenMixOperation
    "jitml_runtime_token_mix_pack"
    $ \symbol -> do
      let execute = mkTokenMixPackFunction symbol
          count = tokenCount * width
      withDoubleList (concatMap VU.toList tokens) $ \tokensPtr ->
        allocaArray count $ \channelsPtr -> do
          status <-
            execute
              channelsPtr
              tokensPtr
              (fromIntegral tokenCount)
              (fromIntegral width)
          peekNativeVector status count channelsPtr

nativeTokenMixMerge
  :: RuntimeOperationsBackendSpec
  -> Env
  -> Int
  -> Int
  -> [Vector Double]
  -> [Vector Double]
  -> IO (Either RuntimeOperationsDeviceError [Vector Double])
nativeTokenMixMerge spec env tokenCount width tokens mixedChannels =
  runNativeOperation
    spec
    env
    RuntimeTokenMixOperation
    "jitml_runtime_token_mix_merge"
    $ \symbol -> do
      let execute = mkTokenMixMergeFunction symbol
          count = tokenCount * width
      withDoubleList (concatMap VU.toList tokens) $ \tokensPtr ->
        withDoubleList (concatMap VU.toList mixedChannels) $ \mixedPtr ->
          allocaArray count $ \outputPtr -> do
            status <-
              execute
                outputPtr
                tokensPtr
                mixedPtr
                (fromIntegral tokenCount)
                (fromIntegral width)
            flatResult <- peekNativeVector status count outputPtr
            pure (fmap (chunksOf width) flatResult)

runBackendMlp
  :: RuntimeOperation
  -> Runtime.RuntimeBackendExecutor
  -> Runtime.RuntimeLayer
  -> Runtime.RuntimeMlpShape
  -> MlpParams
  -> Vector Double
  -> IO (Either RuntimeOperationsDeviceError (Vector Double))
runBackendMlp operation backend layer shape params input
  | VU.length input /= Runtime.runtimeMlpInputs shape =
      pure
        ( Left
            ( RuntimeOperationsContractError
                operation
                (Runtime.runtimeLayerName layer <> " MLP input width mismatch")
            )
        )
  | otherwise = do
      invoked <-
        tryAny (Runtime.runtimeBackendMlpExecutor backend params input)
      pure $
        case invoked of
          Left err ->
            Left
              ( RuntimeOperationsExecutionError
                  (operationText operation <> " selected-backend MLP callback")
                  (Text.pack (displayException err))
              )
          Right result -> do
            output <- mapLeft (RuntimeOperationsBackendCallbackError operation) result
            if VU.length output /= Runtime.runtimeMlpOutputs shape
              then
                Left
                  ( RuntimeOperationsContractError
                      operation
                      (Runtime.runtimeLayerName layer <> " MLP output width mismatch")
                  )
              else Right output

inputTransformArguments
  :: Runtime.RuntimeInputTransform
  -> Vector Double
  -> Either RuntimeOperationsDeviceError (Word32, [Double], [Double])
inputTransformArguments transform input = do
  let operation = RuntimeInputTransformOperation
      mismatch expected =
        RuntimeOperationsContractError
          operation
          ( "expected width "
              <> showText expected
              <> ", got "
              <> showText (VU.length input)
          )
  case Runtime.runtimeInputTransformToRaw transform of
    Runtime.RawIdentityInput width
      | VU.length input == width -> Right (0, [], [])
      | otherwise -> Left (mismatch width)
    Runtime.RawUnitImageInput _
      | VU.length input == Runtime.runtimeInputWidth transform -> Right (1, [], [])
      | otherwise -> Left (mismatch (Runtime.runtimeInputWidth transform))
    Runtime.RawStandardizeInput means scales
      | VU.length input == length means -> Right (2, means, scales)
      | otherwise -> Left (mismatch (length means))

outputTransformArguments
  :: Runtime.RuntimeTask
  -> Runtime.RuntimeOutputTransform
  -> Vector Double
  -> Either RuntimeOperationsDeviceError (Int, Word32, [Double], [Double])
outputTransformArguments task transform input =
  case Runtime.runtimeOutputTransformToRaw transform of
    Runtime.RawIdentityOutput
      | VU.length input == semanticWidth -> Right (semanticWidth, 0, [], [])
      | otherwise -> Left (mismatch "identity output must equal semantic width")
    Runtime.RawSemanticPrefixOutput width
      | width == semanticWidth && VU.length input >= width -> Right (width, 1, [], [])
      | otherwise -> Left (mismatch "semantic prefix width mismatch")
    Runtime.RawDestandardizeOutput means scales
      | VU.length input == semanticWidth
          && length means == semanticWidth
          && length scales == semanticWidth ->
          Right (semanticWidth, 2, means, scales)
      | otherwise -> Left (mismatch "destandardize width mismatch")
 where
  semanticWidth = Runtime.runtimeTaskSemanticWidth task
  mismatch = RuntimeOperationsContractError RuntimeOutputTransformOperation

validateTokens
  :: RuntimeOperation
  -> Int
  -> Int
  -> [Vector Double]
  -> Either RuntimeOperationsDeviceError ()
validateTokens operation expectedCount expectedWidth tokens
  | expectedCount <= 0 || expectedWidth <= 0 =
      Left (RuntimeOperationsContractError operation "token dimensions must be positive")
  | length tokens /= expectedCount =
      Left (RuntimeOperationsContractError operation "token count mismatch")
  | any ((/= expectedWidth) . VU.length) tokens =
      Left (RuntimeOperationsContractError operation "token width mismatch")
  | otherwise = Right ()

patchShape :: [[Int]] -> Either Text Int
patchShape [] = Left "patch position list is empty"
patchShape positions@(first : _)
  | null first = Left "patch positions contain no pixels"
  | any ((/= length first) . length) positions =
      Left "patch position widths differ"
  | otherwise = Right (length first)

callbackContract
  :: RuntimeOperation -> Text -> IO (Either Text value)
callbackContract operation detail =
  pure
    ( Left
        ( renderRuntimeOperationsDeviceError
            (RuntimeOperationsContractError operation detail)
        )
    )

withDoubleVector :: Vector Double -> (Ptr CDouble -> IO value) -> IO value
withDoubleVector values = withDoubleList (VU.toList values)

withDoubleList :: [Double] -> (Ptr CDouble -> IO value) -> IO value
withDoubleList values = withArray (fmap realToFrac values)

peekNativeVector
  :: CInt
  -> Int
  -> Ptr CDouble
  -> IO (Either Int (Vector Double))
peekNativeVector (CInt status) count outputPtr
  | status /= 0 = pure (Left (fromIntegral status))
  | otherwise = do
      values <- peekArray count outputPtr
      pure (Right (VU.fromList (fmap (\(CDouble value) -> realToFrac value) values)))

chunksOf :: Int -> Vector Double -> [Vector Double]
chunksOf width values
  | width <= 0 || VU.null values = []
  | otherwise = VU.take width values : chunksOf width (VU.drop width values)

operationText :: RuntimeOperation -> Text
operationText operation =
  case operation of
    RuntimeInputTransformOperation -> "input-transform"
    RuntimeOutputTransformOperation -> "output-transform"
    RuntimeResidualAddOperation -> "residual-add"
    RuntimeLayerNormOperation -> "layer-norm"
    RuntimeTokenMixOperation -> "token-mix"
    RuntimePatchExtractOperation -> "patch-extract"
    RuntimeAttentionOperation -> "attention"
    RuntimeMeanPoolOperation -> "mean-pool"

nativeStatusText :: Int -> Text
nativeStatusText status =
  case status of
    1 -> "invalid dimension"
    2 -> "nonfinite input"
    3 -> "value out of range"
    4 -> "invalid scale"
    5 -> "invalid transform"
    6 -> "nonfinite output"
    7 -> "invalid index"
    8 -> "CUDA execution failure"
    _ -> "unknown status"

mapLeft :: (left -> other) -> Either left value -> Either other value
mapLeft transform result =
  case result of
    Left err -> Left (transform err)
    Right value -> Right value

showText :: (Show value) => value -> Text
showText = Text.pack . show
