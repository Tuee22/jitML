{-# LANGUAGE OverloadedStrings #-}

-- | Apple-Silicon implementation of the supervised-runtime structural
-- operation contract. Metal has no fp64 type, so the fixed bridge makes the
-- selected backend's Double-to-fp32 transport explicit; all computation still
-- executes in generated MSL on the visible Metal device.
module JitML.Engines.RuntimeOperationsMetal
  ( MetalRuntimeOperationsTransport (..)
  , classifyMetalRuntimeOperationsBridgeFailure
  , metalRuntimeOperationsBackendExecutor
  , metalRuntimeOperationsBackendExecutorWith
  , metalRuntimeOperationsHash
  , metalRuntimeOperationsProductionTransport
  , metalRuntimeOperationsRuntimeSource
  , metalRuntimeOperationsToolchainFingerprint
  , runMetalRuntimeOperation
  , verifyMetalRuntimeOperationsMetadata
  )
where

import Control.Exception.Safe (displayException, tryAny)
import Data.Bits ((.&.))
import Data.Foldable (traverse_)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word32, Word64)
import System.Info qualified as SystemInfo

import JitML.Cache.Key qualified as Cache
import JitML.Codegen.Metal (metalBridgeAbiVersion)
import JitML.Codegen.RuntimeOperationsMetal
  ( renderRuntimeOperationsMetalMetadata
  , runtimeOperationsMetalKernelSpec
  , runtimeOperationsMetalSource
  )
import JitML.Codegen.RuntimeSource
  ( RuntimeSource (..)
  , runtimeSourcePayload
  )
import JitML.Codegen.SourceFile (SourceFile (..))
import JitML.Engines.Engine
  ( KernelHandle (..)
  , engineForSubstrate
  )
import JitML.Engines.Loader
  ( ensureKernelArtifact
  , kernelArtifactHandle
  , renderKernelArtifactError
  )
import JitML.Engines.MetalBridge qualified as MetalBridge
import JitML.Engines.RuntimeOperationsDevice
  ( RuntimeOperation (..)
  , RuntimeOperationsDeviceError (..)
  , renderRuntimeOperationsDeviceError
  , runtimeOperationCapability
  , runtimeOperationsAbiVersion
  , runtimeOperationsAllCapabilities
  )
import JitML.Env.Env (Env)
import JitML.Numerics.Mlp (MlpParams)
import JitML.SL.RuntimeArtifact qualified as Runtime
import JitML.Substrate (Substrate (..))

type MetalDispatch =
  Env
  -> Text
  -> [Float]
  -> [Float]
  -> Int
  -> IO (Either RuntimeOperationsDeviceError [Float])

-- | Injectable fixed-bridge boundary. Tests can remove a capability or symbol
-- and can make dispatch fail without pretending a callback label is hardware
-- execution; production uses 'metalRuntimeOperationsProductionTransport'.
data MetalRuntimeOperationsTransport = MetalRuntimeOperationsTransport
  { metalRuntimeOperationsAbiVersion :: !Word32
  , metalRuntimeOperationsCapabilities :: !Word64
  , metalRuntimeOperationsSymbols :: !(Set Text)
  , metalRuntimeOperationsDispatch :: MetalDispatch
  }

metalRuntimeOperationsSymbolsAll :: Set Text
metalRuntimeOperationsSymbolsAll =
  Set.fromList
    [ "jitml_runtime_input_transform"
    , "jitml_runtime_output_transform"
    , "jitml_runtime_residual_add"
    , "jitml_runtime_layer_norm"
    , "jitml_runtime_token_mix_pack"
    , "jitml_runtime_token_mix_merge"
    , "jitml_runtime_patch_extract"
    , "jitml_runtime_attention"
    , "jitml_runtime_mean_pool"
    ]

metalRuntimeOperationsRuntimeSource :: RuntimeSource
metalRuntimeOperationsRuntimeSource =
  GeneratedMetalSourceMetadata
    { runtimeSourceKernel = runtimeOperationsMetalKernelSpec
    , runtimeSourceKind = Cache.Inference
    , runtimeSourceTuning = Cache.defaultTuningChoice
    , runtimeSourceKernelFamily = Nothing
    , runtimeSourceFiles = renderRuntimeOperationsMetalMetadata
    }

metalRuntimeOperationsToolchainFingerprint :: Cache.ToolchainFingerprint
metalRuntimeOperationsToolchainFingerprint =
  Cache.ToolchainFingerprint
    ( Text.intercalate
        ";"
        [ "fixed-metal-bridge"
        , "bridge-abi=" <> metalBridgeAbiVersion
        , "artifact-abi=" <> Text.pack SystemInfo.os <> "-" <> Text.pack SystemInfo.arch
        , "runtime-abi=jitml-runtime-operations-v1"
        , "capabilities=0xff"
        , "transport=explicit-double-to-fp32-host-buffers"
        , "device-arithmetic=metal-fp32"
        , "fast-math=false"
        , "single-stream-launch-order"
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

metalRuntimeOperationsHash :: Cache.Hash
metalRuntimeOperationsHash =
  Cache.cacheKey
    runtimeOperationsMetalKernelSpec
    Cache.Inference
    Cache.AppleSilicon
    metalRuntimeOperationsToolchainFingerprint
    (runtimeSourcePayload metalRuntimeOperationsRuntimeSource)
    Cache.defaultTuningChoice

metalRuntimeOperationsProductionTransport :: MetalRuntimeOperationsTransport
metalRuntimeOperationsProductionTransport =
  MetalRuntimeOperationsTransport
    { metalRuntimeOperationsAbiVersion = runtimeOperationsAbiVersion
    , metalRuntimeOperationsCapabilities = runtimeOperationsAllCapabilities
    , metalRuntimeOperationsSymbols = metalRuntimeOperationsSymbolsAll
    , metalRuntimeOperationsDispatch = productionDispatch
    }

productionDispatch :: MetalDispatch
productionDispatch env symbol input arguments outputCount = do
  artifactAttempt <-
    tryAny
      ( ensureKernelArtifact
          env
          (engineForSubstrate AppleSilicon)
          metalRuntimeOperationsRuntimeSource
          metalRuntimeOperationsHash
      )
  case artifactAttempt of
    Left err ->
      pure
        ( Left
            ( RuntimeOperationsExecutionError
                "apple-silicon metadata cache"
                (Text.pack (displayException err))
            )
        )
    Right (Left err) ->
      pure (Left (RuntimeOperationsCompileError (renderKernelArtifactError err)))
    Right (Right artifact) -> do
      let artifactPath =
            kernelHandleArtifactPath
              (kernelArtifactHandle artifact)
      metadataAttempt <- tryAny (Text.IO.readFile (Text.unpack artifactPath))
      case metadataAttempt of
        Left err ->
          pure
            ( Left
                ( RuntimeOperationsLoadError
                    ( "could not read cached Metal runtime metadata "
                        <> artifactPath
                        <> ": "
                        <> Text.pack (displayException err)
                    )
                )
            )
        Right metadata ->
          case verifyMetalRuntimeOperationsMetadata metadata of
            Left err -> pure (Left err)
            Right () -> do
              dispatched <-
                tryAny
                  ( MetalBridge.runMetalSource
                      runtimeOperationsMetalSource
                      symbol
                      128
                      input
                      (Just arguments)
                      outputCount
                  )
              pure $
                case dispatched of
                  Left err ->
                    Left
                      ( RuntimeOperationsExecutionError
                          ("apple-silicon fixed bridge fp32 dispatch " <> artifactPath)
                          (Text.pack (displayException err))
                      )
                  Right (Left detail) ->
                    Left (classifyMetalRuntimeOperationsBridgeFailure symbol detail)
                  Right (Right output) -> Right output

verifyMetalRuntimeOperationsMetadata
  :: Text -> Either RuntimeOperationsDeviceError ()
verifyMetalRuntimeOperationsMetadata actual
  | actual == expectedMetalRuntimeOperationsMetadata = Right ()
  | otherwise =
      Left
        ( RuntimeOperationsLoadError
            "cached Metal runtime metadata bytes do not match the exact generated ABI/capability/source envelope"
        )

expectedMetalRuntimeOperationsMetadata :: Text
expectedMetalRuntimeOperationsMetadata =
  case renderRuntimeOperationsMetalMetadata of
    [SourceFile _ contents] -> contents
    _ -> ""

classifyMetalRuntimeOperationsBridgeFailure
  :: Text -> Text -> RuntimeOperationsDeviceError
classifyMetalRuntimeOperationsBridgeFailure symbol detail
  | "function not found" `Text.isInfixOf` lowered =
      RuntimeOperationsSymbolError symbol detail
  | "symbol not found" `Text.isInfixOf` lowered
      || "undefined symbol" `Text.isInfixOf` lowered
      || "dlsym" `Text.isInfixOf` lowered =
      RuntimeOperationsSymbolError "jitml_metal_bridge_run" detail
  | "dylib not found" `Text.isInfixOf` lowered
      || "dlopen" `Text.isInfixOf` lowered
      || "image not found" `Text.isInfixOf` lowered =
      RuntimeOperationsLoadError detail
  | "compile" `Text.isInfixOf` lowered
      || "metal library" `Text.isInfixOf` lowered
      || "program_source" `Text.isInfixOf` lowered =
      RuntimeOperationsCompileError detail
  | otherwise =
      RuntimeOperationsExecutionError
        ("apple-silicon " <> symbol <> " fixed-bridge-fp32 dispatch")
        detail
 where
  lowered = Text.toLower detail

runMetalRuntimeOperation
  :: MetalRuntimeOperationsTransport
  -> Env
  -> RuntimeOperation
  -> Text
  -> [Double]
  -> [Double]
  -> Int
  -> IO (Either RuntimeOperationsDeviceError (Vector Double))
runMetalRuntimeOperation transport env operation symbol input arguments outputCount =
  case do
    validateTransport transport operation symbol
    requirePositiveWidth operation "Metal output count" outputCount
    validateBridgeCount operation "Metal output count" outputCount
    validateBridgeCount operation "Metal input count" (length input)
    validateBridgeCount operation "Metal argument count" (length arguments)
    if outputCount > length input
      then
        Left
          ( RuntimeOperationsContractError
              operation
              "Metal fixed-bridge dispatch width exceeds the padded input dispatch width"
          )
      else Right () of
    Left err -> pure (Left err)
    Right () ->
      case traverse exactFloat (input <> arguments) of
        Left detail ->
          pure (Left (RuntimeOperationsContractError operation detail))
        Right packed -> do
          let (floatInput, floatArguments) = splitAt (length input) packed
          dispatched <-
            metalRuntimeOperationsDispatch
              transport
              env
              symbol
              floatInput
              floatArguments
              outputCount
          pure $ do
            output <- dispatched
            if length output /= outputCount
              then
                Left
                  ( RuntimeOperationsExecutionError
                      (operationText operation <> " fixed-bridge-fp32 readback")
                      ( "expected "
                          <> showText outputCount
                          <> " values, got "
                          <> showText (length output)
                      )
                  )
              else Right ()
            let decoded = VU.fromList (fmap realToFrac output)
            traverse_
              (requireFinite operation "Metal fp32 output")
              (VU.toList decoded)
            Right decoded

validateTransport
  :: MetalRuntimeOperationsTransport
  -> RuntimeOperation
  -> Text
  -> Either RuntimeOperationsDeviceError ()
validateTransport transport operation symbol = do
  if metalRuntimeOperationsAbiVersion transport /= runtimeOperationsAbiVersion
    then
      Left
        RuntimeOperationsAbiMismatch
          { runtimeOperationsExpectedAbi = runtimeOperationsAbiVersion
          , runtimeOperationsActualAbi = metalRuntimeOperationsAbiVersion transport
          }
    else Right ()
  let actualCapabilities = metalRuntimeOperationsCapabilities transport
  if actualCapabilities .&. runtimeOperationsAllCapabilities
    /= runtimeOperationsAllCapabilities
    then
      Left
        RuntimeOperationsCapabilityMismatch
          { runtimeOperationsErrorRequiredCapabilities =
              runtimeOperationsAllCapabilities
          , runtimeOperationsErrorActualCapabilities = actualCapabilities
          }
    else Right ()
  if actualCapabilities .&. runtimeOperationCapability operation == 0
    then Left (RuntimeOperationsCapabilityMissing operation)
    else Right ()
  if Set.member symbol (metalRuntimeOperationsSymbols transport)
    then Right ()
    else Left (RuntimeOperationsSymbolError symbol "not declared by cached Metal metadata")

metalRuntimeOperationsBackendExecutor
  :: Env
  -> Runtime.RuntimeMlpExecutor
  -> Runtime.RuntimeBackendExecutor
metalRuntimeOperationsBackendExecutor =
  metalRuntimeOperationsBackendExecutorWith
    metalRuntimeOperationsProductionTransport

metalRuntimeOperationsBackendExecutorWith
  :: MetalRuntimeOperationsTransport
  -> Env
  -> Runtime.RuntimeMlpExecutor
  -> Runtime.RuntimeBackendExecutor
metalRuntimeOperationsBackendExecutorWith transport env executeMlp = backend
 where
  backend =
    Runtime.RuntimeBackendExecutor
      { Runtime.runtimeBackendLabel = "apple-silicon"
      , Runtime.runtimeBackendInputTransformExecutor =
          metalInputTransform transport env
      , Runtime.runtimeBackendOutputTransformExecutor =
          metalOutputTransform transport env
      , Runtime.runtimeBackendMlpExecutor = executeMlpSafely
      , Runtime.runtimeBackendResidualAddExecutor =
          metalResidualAdd transport env
      , Runtime.runtimeBackendLayerNormExecutor =
          metalLayerNorm transport env
      , Runtime.runtimeBackendTokenMixExecutor =
          metalTokenMix transport env
      , Runtime.runtimeBackendPatchExtractExecutor =
          metalPatchExtract transport env
      , Runtime.runtimeBackendAttentionExecutor =
          metalAttention transport env
      , Runtime.runtimeBackendMeanPoolExecutor =
          metalMeanPool transport env
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

metalInputTransform
  :: MetalRuntimeOperationsTransport
  -> Env
  -> Runtime.RuntimeInputTransformExecutor
metalInputTransform transport env transform input =
  validatedCallback (inputTransformArguments transform input) $
    \(code, means, scales) ->
      runMetalRuntimeOperation
        transport
        env
        RuntimeInputTransformOperation
        "jitml_runtime_input_transform"
        (VU.toList input)
        (fromIntegral code : means <> scales)
        (VU.length input)

metalOutputTransform
  :: MetalRuntimeOperationsTransport
  -> Env
  -> Runtime.RuntimeOutputTransformExecutor
metalOutputTransform transport env task transform input =
  validatedCallback (outputTransformArguments task transform input) $
    \(outputCount, code, means, scales) ->
      runMetalRuntimeOperation
        transport
        env
        RuntimeOutputTransformOperation
        "jitml_runtime_output_transform"
        (VU.toList input)
        (fmap fromIntegral [code, outputCount] <> means <> scales)
        outputCount

metalResidualAdd
  :: MetalRuntimeOperationsTransport
  -> Env
  -> Runtime.RuntimeResidualAddExecutor
metalResidualAdd transport env scale input residual =
  validatedCallback validation $ \() ->
    runMetalRuntimeOperation
      transport
      env
      operation
      "jitml_runtime_residual_add"
      (VU.toList input <> VU.toList residual)
      [fromIntegral (VU.length input), scale]
      (VU.length input)
 where
  operation = RuntimeResidualAddOperation
  validation = do
    requirePositiveWidth operation "residual width" (VU.length input)
    if VU.length input /= VU.length residual
      then Left (RuntimeOperationsContractError operation "input/residual widths differ")
      else Right ()
    exactFloatInteger operation "residual width" (VU.length input)
    requireFinitePositive operation "residual scale" scale
    validateVector operation "residual input" input
    validateVector operation "residual delta" residual

metalLayerNorm
  :: MetalRuntimeOperationsTransport
  -> Env
  -> Runtime.RuntimeLayerNormExecutor
metalLayerNorm transport env input =
  validatedCallback validation $ \() ->
    runMetalRuntimeOperation
      transport
      env
      operation
      "jitml_runtime_layer_norm"
      (VU.toList input)
      [fromIntegral (VU.length input)]
      (VU.length input)
 where
  operation = RuntimeLayerNormOperation
  validation = do
    requirePositiveWidth operation "token width" (VU.length input)
    exactFloatInteger operation "token width" (VU.length input)
    validateVector operation "layer-norm input" input

metalTokenMix
  :: MetalRuntimeOperationsTransport
  -> Env
  -> Runtime.RuntimeTokenMixExecutor
metalTokenMix transport env backend layer tokenCount width shape params tokens =
  case do
    validateTokens RuntimeTokenMixOperation tokenCount width tokens
    exactFloatInteger RuntimeTokenMixOperation "token count" tokenCount
    exactFloatInteger RuntimeTokenMixOperation "token width" width of
    Left err -> pure (Left (renderRuntimeOperationsDeviceError err))
    Right () -> do
      packed <-
        runMetalRuntimeOperation
          transport
          env
          RuntimeTokenMixOperation
          "jitml_runtime_token_mix_pack"
          (concatMap VU.toList tokens)
          [fromIntegral tokenCount, fromIntegral width]
          (tokenCount * width)
      case packed of
        Left err -> pure (Left (renderRuntimeOperationsDeviceError err))
        Right channels -> do
          mixed <-
            traverse
              (runBackendMlp RuntimeTokenMixOperation backend layer shape params)
              (chunksOf tokenCount channels)
          case sequence mixed of
            Left err -> pure (Left (renderRuntimeOperationsDeviceError err))
            Right mixedChannels -> do
              merged <-
                runMetalRuntimeOperation
                  transport
                  env
                  RuntimeTokenMixOperation
                  "jitml_runtime_token_mix_merge"
                  (concatMap VU.toList tokens <> concatMap VU.toList mixedChannels)
                  [fromIntegral tokenCount, fromIntegral width]
                  (tokenCount * width)
              pure $
                fmap (chunksOf width) (mapLeft renderRuntimeOperationsDeviceError merged)

metalPatchExtract
  :: MetalRuntimeOperationsTransport
  -> Env
  -> Runtime.RuntimePatchExtractExecutor
metalPatchExtract transport env geometry positions input =
  validatedCallback validation $
    \(patchWidth, outputCount, paddedInput, arguments) ->
      fmap (chunksOf patchWidth)
        <$> runMetalRuntimeOperation
          transport
          env
          operation
          "jitml_runtime_patch_extract"
          paddedInput
          arguments
          outputCount
 where
  operation = RuntimePatchExtractOperation
  inputCount = VU.length input
  expectedInput = Runtime.runtimeImageElementCount geometry
  validation = do
    validateVector operation "patch input" input
    if inputCount /= expectedInput
      then Left (RuntimeOperationsContractError operation "image/input element count mismatch")
      else Right ()
    valueWidth <- patchShape positions
    let patchCount = length positions
        patchWidth = valueWidth + 2
        outputCount = patchCount * patchWidth
        indices = concat positions
    traverse_
      ( \index ->
          if index < 0 || index >= inputCount
            then Left (RuntimeOperationsContractError operation "patch index is out of bounds")
            else exactFloatInteger operation "patch index" index
      )
      indices
    traverse_
      (uncurry (exactFloatInteger operation))
      [ ("image width", Runtime.runtimeImageWidth geometry)
      , ("image height", Runtime.runtimeImageHeight geometry)
      , ("image channels", Runtime.runtimeImageChannels geometry)
      , ("input count", inputCount)
      , ("patch count", patchCount)
      , ("patch value width", valueWidth)
      , ("patch output width", patchWidth)
      , ("patch output count", outputCount)
      ]
    let arguments =
          fmap
            fromIntegral
            ( [ inputCount
              , Runtime.runtimeImageWidth geometry
              , Runtime.runtimeImageHeight geometry
              , Runtime.runtimeImageChannels geometry
              , patchCount
              , valueWidth
              ]
                <> indices
            )
        paddedInput = VU.toList input <> replicate (max 0 (outputCount - inputCount)) 0.0
    Right (patchWidth, outputCount, paddedInput, arguments)

metalAttention
  :: MetalRuntimeOperationsTransport
  -> Env
  -> Runtime.RuntimeAttentionExecutor
metalAttention transport env backend layer width shape params tokens =
  case do
    validateTokens RuntimeAttentionOperation (length tokens) width tokens
    exactFloatInteger RuntimeAttentionOperation "token count" (length tokens)
    exactFloatInteger RuntimeAttentionOperation "token width" width of
    Left err -> pure (Left (renderRuntimeOperationsDeviceError err))
    Right () -> do
      qkvResults <-
        traverse
          (runBackendMlp RuntimeAttentionOperation backend layer shape params)
          tokens
      case sequence qkvResults of
        Left err -> pure (Left (renderRuntimeOperationsDeviceError err))
        Right qkvs ->
          case traverse_ (validateVectorWidth RuntimeAttentionOperation "attention QKV" (3 * width)) qkvs of
            Left err -> pure (Left (renderRuntimeOperationsDeviceError err))
            Right () -> do
              output <-
                runMetalRuntimeOperation
                  transport
                  env
                  RuntimeAttentionOperation
                  "jitml_runtime_attention"
                  (concatMap VU.toList tokens <> concatMap VU.toList qkvs)
                  [fromIntegral (length tokens), fromIntegral width]
                  (length tokens * width)
              pure $
                fmap (chunksOf width) (mapLeft renderRuntimeOperationsDeviceError output)

metalMeanPool
  :: MetalRuntimeOperationsTransport
  -> Env
  -> Runtime.RuntimeMeanPoolExecutor
metalMeanPool transport env tokens =
  case tokens of
    [] ->
      pure
        ( Left
            ( renderRuntimeOperationsDeviceError
                (RuntimeOperationsContractError RuntimeMeanPoolOperation "token sequence is empty")
            )
        )
    first : _ ->
      case do
        validateTokens RuntimeMeanPoolOperation (length tokens) (VU.length first) tokens
        exactFloatInteger RuntimeMeanPoolOperation "token count" (length tokens)
        exactFloatInteger RuntimeMeanPoolOperation "token width" (VU.length first) of
        Left err -> pure (Left (renderRuntimeOperationsDeviceError err))
        Right () ->
          renderCallback $
            runMetalRuntimeOperation
              transport
              env
              RuntimeMeanPoolOperation
              "jitml_runtime_mean_pool"
              (concatMap VU.toList tokens)
              [fromIntegral (length tokens), fromIntegral (VU.length first)]
              (VU.length first)

renderCallback
  :: IO (Either RuntimeOperationsDeviceError value)
  -> IO (Either Text value)
renderCallback = fmap (mapLeft renderRuntimeOperationsDeviceError)

validatedCallback
  :: Either RuntimeOperationsDeviceError arguments
  -> (arguments -> IO (Either RuntimeOperationsDeviceError value))
  -> IO (Either Text value)
validatedCallback validation action =
  case validation of
    Left err -> pure (Left (renderRuntimeOperationsDeviceError err))
    Right arguments -> renderCallback (action arguments)

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
      attempted <-
        tryAny (Runtime.runtimeBackendMlpExecutor backend params input)
      pure $ do
        result <-
          mapLeft
            ( RuntimeOperationsExecutionError
                (operationText operation <> " selected-backend MLP callback")
                . Text.pack
                . displayException
            )
            attempted
        output <- mapLeft (RuntimeOperationsBackendCallbackError operation) result
        validateVectorWidth
          operation
          (Runtime.runtimeLayerName layer <> " MLP output")
          (Runtime.runtimeMlpOutputs shape)
          output
        Right output

inputTransformArguments
  :: Runtime.RuntimeInputTransform
  -> Vector Double
  -> Either RuntimeOperationsDeviceError (Int, [Double], [Double])
inputTransformArguments transform input = do
  let operation = RuntimeInputTransformOperation
  validateVector operation "runtime input" input
  case Runtime.runtimeInputTransformToRaw transform of
    Runtime.RawIdentityInput width -> do
      validateVectorWidth operation "identity input" width input
      exactFloatInteger operation "input transform code" 0
      Right (0, [], [])
    Runtime.RawUnitImageInput _ -> do
      validateVectorWidth
        operation
        "unit-image input"
        (Runtime.runtimeInputWidth transform)
        input
      exactFloatInteger operation "input transform code" 1
      traverse_
        ( \value ->
            if value < 0.0 || value > 1.0
              then Left (RuntimeOperationsContractError operation "unit-image values must be in [0,1]")
              else Right ()
        )
        (VU.toList input)
      Right (1, [], [])
    Runtime.RawStandardizeInput means scales -> do
      validateVectorWidth operation "standardized input" (length means) input
      exactFloatInteger operation "input transform code" 2
      if length means /= length scales
        then Left (RuntimeOperationsContractError operation "standardization statistic widths differ")
        else Right ()
      traverse_ (requireFinite operation "input mean") means
      traverse_ (requireFinitePositive operation "input scale") scales
      Right (2, means, scales)

outputTransformArguments
  :: Runtime.RuntimeTask
  -> Runtime.RuntimeOutputTransform
  -> Vector Double
  -> Either RuntimeOperationsDeviceError (Int, Int, [Double], [Double])
outputTransformArguments task transform input = do
  let operation = RuntimeOutputTransformOperation
      semanticWidth = Runtime.runtimeTaskSemanticWidth task
  validateVector operation "runtime raw output" input
  case Runtime.runtimeOutputTransformToRaw transform of
    Runtime.RawIdentityOutput -> do
      validateVectorWidth operation "identity output" semanticWidth input
      exactFloatInteger operation "output transform code" 0
      exactFloatInteger operation "semantic output width" semanticWidth
      Right (semanticWidth, 0, [], [])
    Runtime.RawSemanticPrefixOutput width
      | width == semanticWidth && VU.length input >= width -> do
          exactFloatInteger operation "output transform code" 1
          exactFloatInteger operation "semantic output width" width
          Right (width, 1, [], [])
      | otherwise ->
          Left (RuntimeOperationsContractError operation "semantic-prefix width mismatch")
    Runtime.RawDestandardizeOutput means scales -> do
      validateVectorWidth operation "destandardized output" semanticWidth input
      exactFloatInteger operation "output transform code" 2
      exactFloatInteger operation "semantic output width" semanticWidth
      if length means /= semanticWidth || length scales /= semanticWidth
        then Left (RuntimeOperationsContractError operation "destandardization statistic width mismatch")
        else Right ()
      traverse_ (requireFinite operation "output mean") means
      traverse_ (requireFinitePositive operation "output scale") scales
      Right (semanticWidth, 2, means, scales)

validateTokens
  :: RuntimeOperation
  -> Int
  -> Int
  -> [Vector Double]
  -> Either RuntimeOperationsDeviceError ()
validateTokens operation expectedCount expectedWidth tokens = do
  requirePositiveWidth operation "token count" expectedCount
  requirePositiveWidth operation "token width" expectedWidth
  if length tokens /= expectedCount
    then Left (RuntimeOperationsContractError operation "token count mismatch")
    else Right ()
  traverse_ (validateVectorWidth operation "token" expectedWidth) tokens

validateVectorWidth
  :: RuntimeOperation
  -> Text
  -> Int
  -> Vector Double
  -> Either RuntimeOperationsDeviceError ()
validateVectorWidth operation label expected vector = do
  if VU.length vector /= expected
    then
      Left
        ( RuntimeOperationsContractError
            operation
            ( label
                <> " width mismatch: expected "
                <> showText expected
                <> ", got "
                <> showText (VU.length vector)
            )
        )
    else Right ()
  validateVector operation label vector

validateVector
  :: RuntimeOperation
  -> Text
  -> Vector Double
  -> Either RuntimeOperationsDeviceError ()
validateVector operation label =
  traverse_ (requireFinite operation label) . VU.toList

requirePositiveWidth
  :: RuntimeOperation -> Text -> Int -> Either RuntimeOperationsDeviceError ()
requirePositiveWidth operation label value
  | value > 0 = Right ()
  | otherwise = Left (RuntimeOperationsContractError operation (label <> " must be positive"))

requireFinite
  :: RuntimeOperation -> Text -> Double -> Either RuntimeOperationsDeviceError ()
requireFinite operation label value
  | isNaN value || isInfinite value =
      Left (RuntimeOperationsContractError operation (label <> " must be finite"))
  | otherwise = Right ()

requireFinitePositive
  :: RuntimeOperation -> Text -> Double -> Either RuntimeOperationsDeviceError ()
requireFinitePositive operation label value = do
  requireFinite operation label value
  let encoded = realToFrac value :: Float
  if value > 0.0 && encoded > 0.0 && not (isInfinite encoded)
    then Right ()
    else
      Left
        ( RuntimeOperationsContractError
            operation
            (label <> " must remain positive and finite through the Metal fp32 transport")
        )

patchShape :: [[Int]] -> Either RuntimeOperationsDeviceError Int
patchShape [] =
  Left (RuntimeOperationsContractError RuntimePatchExtractOperation "patch position list is empty")
patchShape positions@(first : _)
  | null first =
      Left
        (RuntimeOperationsContractError RuntimePatchExtractOperation "patch positions contain no pixels")
  | any ((/= length first) . length) positions =
      Left (RuntimeOperationsContractError RuntimePatchExtractOperation "patch position widths differ")
  | otherwise = Right (length first)

exactFloatInteger
  :: RuntimeOperation -> Text -> Int -> Either RuntimeOperationsDeviceError ()
exactFloatInteger operation label value =
  let encoded = fromIntegral value :: Float
      integerValue = toInteger value
      maximumUint = toInteger (maxBound :: Word32)
   in if integerValue < 0 || integerValue > maximumUint
        then
          Left
            ( RuntimeOperationsContractError
                operation
                (label <> " is outside the Metal uint32 argument ABI")
            )
        else
          if (truncate encoded :: Integer) == integerValue
            then Right ()
            else
              Left
                ( RuntimeOperationsContractError
                    operation
                    (label <> " cannot be represented exactly by the Metal fp32 argument ABI")
                )

validateBridgeCount
  :: RuntimeOperation -> Text -> Int -> Either RuntimeOperationsDeviceError ()
validateBridgeCount operation label value
  | value <= 0 =
      Left
        (RuntimeOperationsContractError operation (label <> " must be positive"))
  | toInteger value > toInteger (maxBound :: Word32) =
      Left
        ( RuntimeOperationsContractError
            operation
            (label <> " exceeds the fixed Metal bridge uint32 ABI")
        )
  | otherwise = Right ()

exactFloat :: Double -> Either Text Float
exactFloat value
  | isNaN value || isInfinite value =
      Left "Metal fixed-bridge fp32 transport received a nonfinite value"
  | isInfinite encoded =
      Left "Metal fixed-bridge fp32 transport overflowed"
  | otherwise = Right encoded
 where
  encoded = realToFrac value

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

mapLeft :: (left -> other) -> Either left value -> Either other value
mapLeft transform result =
  case result of
    Left err -> Left (transform err)
    Right value -> Right value

showText :: (Show value) => value -> Text
showText = Text.pack . show
