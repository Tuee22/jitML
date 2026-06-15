{-# LANGUAGE OverloadedStrings #-}

-- | Substrate-backed supervised-learning architecture runtime.
--
-- The older classifier path in "JitML.SL.Classifier" trains one
-- single-hidden-layer MLP. This module composes the same real
-- @jitml_mlp_*@ device ABI into the canonical SL model families: deep dense
-- stacks, residual stacks, patch-convolution stems, and a compact
-- patch-attention encoder. Every trainable layer calls the injected
-- 'MlpDevice' for batched forward, parameter-gradient, and input-gradient
-- work; a device failure is returned as 'Left' and never falls back to the
-- pure-Haskell reference path.
module JitML.SL.Architecture
  ( ArchitectureFamily (..)
  , ArchitectureSpec (..)
  , TrainedArchitecture (..)
  , architectureSpecForProblem
  , allCanonicalArchitectureSpecs
  , trainArchitectureWithDevice
  , accuracyArchitectureWithDevice
  )
where

import Control.Monad (foldM)
import Data.Bifunctor (second)
import Data.List qualified as List
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU

import JitML.Numerics.Mlp
  ( AdamConfig (..)
  , AdamState
  , MlpGradient (..)
  , MlpParams
  , MlpShape (..)
  , adamInit
  , adamStep
  , defaultAdamConfig
  , mlpInit
  , softmax
  )
import JitML.Numerics.MlpDevice (MlpDevice (..))
import JitML.SL.Canonicals
  ( CanonicalProblem (..)
  , canonicalProblems
  )
import JitML.SL.Classifier
  ( ClassifierConfig (..)
  , Dataset
  , LabeledExample (..)
  )

data ArchitectureFamily
  = DenseFamily
  | DeepDenseFamily
  | Conv2DLeNetFamily
  | ResidualFamily Int
  | WideResidualFamily Int
  | VisionTransformerFamily
  deriving stock (Eq, Show)

data ArchitectureSpec = ArchitectureSpec
  { archProblem :: !CanonicalProblem
  , archFamily :: !ArchitectureFamily
  , archLayers :: ![LayerSpec]
  }
  deriving stock (Eq, Show)

data TrainedArchitecture = TrainedArchitecture
  { trainedArchSpec :: !ArchitectureSpec
  , trainedArchLayers :: ![LayerState]
  , trainedArchConfig :: !ClassifierConfig
  }
  deriving stock (Eq, Show)

data LayerSpec
  = DenseSpec
      { layerName :: !Text
      , layerInputs :: !Int
      , layerHidden :: !Int
      , layerOutputs :: !Int
      }
  | ResidualSpec
      { layerName :: !Text
      , layerWidth :: !Int
      , layerHidden :: !Int
      , layerResidualScale :: !Double
      }
  | PatchSpec
      { layerName :: !Text
      , patchGeometry :: !ImageGeometry
      , patchSize :: !Int
      , patchStride :: !Int
      , patchHidden :: !Int
      , patchOutputs :: !Int
      }
  | AttentionSpec
      { layerName :: !Text
      , attentionWidth :: !Int
      , attentionHidden :: !Int
      }
  | MeanPoolSpec
      { layerName :: !Text
      }
  deriving stock (Eq, Show)

data LayerState
  = DenseState !Text !MlpParams !AdamState
  | ResidualState !Text !Double !MlpParams !AdamState
  | PatchState !Text !PatchRuntime !MlpParams !AdamState
  | AttentionState !Text !MlpParams !AdamState
  | MeanPoolState !Text
  deriving stock (Eq, Show)

data ImageGeometry = ImageGeometry
  { geomWidth :: !Int
  , geomHeight :: !Int
  , geomChannels :: !Int
  }
  deriving stock (Eq, Show)

data PatchRuntime = PatchRuntime
  { patchRuntimeGeometry :: !ImageGeometry
  , patchRuntimePositions :: ![[Int]]
  , patchRuntimeInputCount :: !Int
  }
  deriving stock (Eq, Show)

data BatchRep
  = FlatBatch ![Vector Double]
  | TokenBatch ![[Vector Double]]
  deriving stock (Eq, Show)

data LayerTape
  = DenseTape ![Vector Double]
  | ResidualTape ![Vector Double]
  | PatchTape ![[Vector Double]]
  | AttentionTape ![[AttentionToken]]
  | MeanPoolTape ![Int]
  deriving stock (Eq, Show)

data AttentionToken = AttentionToken
  { tokenInput :: !(Vector Double)
  , tokenQ :: !(Vector Double)
  , tokenK :: !(Vector Double)
  , tokenV :: !(Vector Double)
  , tokenWeights :: !(Vector Double)
  , tokenOutput :: !(Vector Double)
  }
  deriving stock (Eq, Show)

-- | Architecture row for every canonical SL problem. The specs are sized from
-- the concrete training config, so the same row works for small tests and for
-- real IDX image widths.
architectureSpecForProblem :: ClassifierConfig -> CanonicalProblem -> ArchitectureSpec
architectureSpecForProblem config problem =
  ArchitectureSpec
    { archProblem = problem
    , archFamily = familyForModel (problemModel problem)
    , archLayers = layersForFamily (familyForModel (problemModel problem))
    }
 where
  inputs = clfInputs config
  outputs = clfClasses config + 1
  baseHidden = max 4 (clfHidden config)
  latent = clamp 4 32 (baseHidden `div` 2)
  wideLatent = clamp 8 48 baseHidden
  geometry = geometryForInput inputs
  denseFinal name inWidth = DenseSpec name inWidth baseHidden outputs
  projection name = DenseSpec name inputs baseHidden
  residualBlock idx width hidden =
    ResidualSpec ("residual-" <> Text.pack (show idx)) width hidden 0.1
  patchStem name outWidth hidden =
    PatchSpec
      name
      geometry
      (patchSide geometry)
      (patchSide geometry)
      hidden
      outWidth
  layersForFamily DenseFamily =
    [denseFinal "dense-classifier" inputs]
  layersForFamily DeepDenseFamily =
    [ projection "deep-dense-1" latent
    , DenseSpec "deep-dense-2" latent baseHidden latent
    , denseFinal "deep-dense-classifier" latent
    ]
  layersForFamily Conv2DLeNetFamily =
    [ patchStem "conv2d-patch-stem" latent baseHidden
    , MeanPoolSpec "conv2d-global-mean-pool"
    , denseFinal "lenet-classifier" latent
    ]
  layersForFamily (ResidualFamily depth) =
    [projection "residual-stem" latent]
      <> fmap (\i -> residualBlock i latent baseHidden) [1 .. depth]
      <> [denseFinal "residual-classifier" latent]
  layersForFamily (WideResidualFamily depth) =
    [projection "wide-residual-stem" wideLatent]
      <> fmap (\i -> residualBlock i wideLatent (baseHidden * 2)) [1 .. depth]
      <> [denseFinal "wide-residual-classifier" wideLatent]
  layersForFamily VisionTransformerFamily =
    [ patchStem "vit-patch-embedding" latent baseHidden
    , AttentionSpec "vit-self-attention" latent baseHidden
    , MeanPoolSpec "vit-token-mean-pool"
    , denseFinal "vit-classifier" latent
    ]

allCanonicalArchitectureSpecs :: ClassifierConfig -> [ArchitectureSpec]
allCanonicalArchitectureSpecs config =
  fmap (architectureSpecForProblem config) canonicalProblems

familyForModel :: Text -> ArchitectureFamily
familyForModel "Dense" = DenseFamily
familyForModel "DeepDense" = DeepDenseFamily
familyForModel "Conv2D" = Conv2DLeNetFamily
familyForModel "ResidualBlock" = ResidualFamily 2
familyForModel "ResidualBlock20" = ResidualFamily 20
familyForModel "ResidualBlock56" = ResidualFamily 56
familyForModel "WideResidualBlock" = WideResidualFamily 16
familyForModel "VisionTransformer" = VisionTransformerFamily
familyForModel "ResidualBlock50" = ResidualFamily 50
familyForModel _ = DenseFamily

-- | Train a canonical architecture through the substrate device. The loss is
-- mean softmax cross entropy; Adam updates are host-owned but every layer's
-- forward, backward, and input-gradient pass goes through 'MlpDevice'.
trainArchitectureWithDevice
  :: MlpDevice
  -> ArchitectureSpec
  -> ClassifierConfig
  -> Dataset
  -> IO (Either Text (TrainedArchitecture, Double))
trainArchitectureWithDevice device spec config dataset
  | null dataset = pure (Left "trainArchitectureWithDevice: empty dataset")
  | otherwise = do
      let adamConfig =
            defaultAdamConfig {adamLearningRate = clfLearningRate config}
          inputs = FlatBatch (fmap exampleFeatures dataset)
          labels = fmap exampleLabel dataset
      statesE <- initialiseLayers (clfSeed config) (archLayers spec)
      case statesE of
        Left err -> pure (Left err)
        Right states0 -> do
          trainedE <-
            foldM
              ( \acc _epoch -> case acc of
                  Left err -> pure (Left err)
                  Right states -> trainEpoch device adamConfig (clfClasses config) labels states inputs
              )
              (Right states0)
              [1 .. max 1 (clfEpochs config)]
          case trainedE of
            Left err -> pure (Left err)
            Right states -> do
              let trained =
                    TrainedArchitecture
                      { trainedArchSpec = spec
                      , trainedArchLayers = states
                      , trainedArchConfig = config
                      }
              accE <- accuracyArchitectureWithDevice device trained dataset
              pure (fmap (trained,) accE)

accuracyArchitectureWithDevice
  :: MlpDevice -> TrainedArchitecture -> Dataset -> IO (Either Text Double)
accuracyArchitectureWithDevice _ _ [] = pure (Right 0.0)
accuracyArchitectureWithDevice device trained dataset = do
  outE <- forwardOnly device (trainedArchLayers trained) (FlatBatch (fmap exampleFeatures dataset))
  pure $ do
    outs <- outE
    case outs of
      FlatBatch vectors ->
        let classes = clfClasses (trainedArchConfig trained)
            predicted = fmap (VU.maxIndex . VU.take classes) vectors
            correct =
              length
                (filter id (zipWith (==) predicted (fmap exampleLabel dataset)))
         in Right (fromIntegral correct / fromIntegral (length dataset))
      TokenBatch _ -> Left "accuracyArchitectureWithDevice: final representation is token-shaped"

trainEpoch
  :: MlpDevice
  -> AdamConfig
  -> Int
  -> [Int]
  -> [LayerState]
  -> BatchRep
  -> IO (Either Text [LayerState])
trainEpoch device adamConfig numClasses labels states inputs = do
  fwdE <- forwardWithTapes device states inputs
  case fwdE of
    Left err -> pure (Left err)
    Right (FlatBatch outputs, tapes) -> do
      let outputGrads = zipWith (classifierOutputGradient numClasses) outputs labels
      backE <- backwardAll device adamConfig states tapes (FlatBatch outputGrads) (length labels)
      pure (fmap fst backE)
    Right (TokenBatch _, _) ->
      pure (Left "trainArchitectureWithDevice: final layer produced token representation")

initialiseLayers :: Int -> [LayerSpec] -> IO (Either Text [LayerState])
initialiseLayers seed specs =
  pure (traverse (uncurry initialiseLayer) (zip [0 :: Int ..] specs))
 where
  initialiseLayer idx spec =
    let layerSeed = seed + idx * 1009
     in case spec of
          DenseSpec name inputs hidden outputs ->
            let shape = MlpShape inputs hidden outputs
                params = mlpInit shape layerSeed
             in Right (DenseState name params (adamInit shape))
          ResidualSpec name width hidden scale ->
            let shape = MlpShape width hidden width
                params = mlpInit shape layerSeed
             in Right (ResidualState name scale params (adamInit shape))
          PatchSpec name geometry pSize pStride hidden outputs
            | pSize <= 0 || pStride <= 0 ->
                Left (name <> ": patch size and stride must be positive")
            | otherwise ->
                let positions = patchPositions geometry pSize pStride
                    patchInputs = pSize * pSize * geomChannels geometry
                    shape = MlpShape patchInputs hidden outputs
                    params = mlpInit shape layerSeed
                    runtime =
                      PatchRuntime
                        { patchRuntimeGeometry = geometry
                        , patchRuntimePositions = positions
                        , patchRuntimeInputCount =
                            geomWidth geometry * geomHeight geometry * geomChannels geometry
                        }
                 in if null positions
                      then Left (name <> ": image geometry produced no patches")
                      else Right (PatchState name runtime params (adamInit shape))
          AttentionSpec name width hidden ->
            let shape = MlpShape width hidden (width * 3)
                params = mlpInit shape layerSeed
             in Right (AttentionState name params (adamInit shape))
          MeanPoolSpec name -> Right (MeanPoolState name)

forwardOnly :: MlpDevice -> [LayerState] -> BatchRep -> IO (Either Text BatchRep)
forwardOnly device states input =
  fmap fst <$> foldM step (Right (input, [] :: [LayerTape])) states
 where
  step acc state = case acc of
    Left err -> pure (Left err)
    Right (rep, tapes) -> do
      next <- forwardLayer device state rep
      pure (fmap (\(rep', tape) -> (rep', tape : tapes)) next)

forwardWithTapes
  :: MlpDevice -> [LayerState] -> BatchRep -> IO (Either Text (BatchRep, [LayerTape]))
forwardWithTapes device states input = do
  result <- foldM step (Right (input, [])) states
  pure (fmap (second reverse) result)
 where
  step acc state = case acc of
    Left err -> pure (Left err)
    Right (rep, tapes) -> do
      next <- forwardLayer device state rep
      pure (fmap (\(rep', tape) -> (rep', tape : tapes)) next)

forwardLayer :: MlpDevice -> LayerState -> BatchRep -> IO (Either Text (BatchRep, LayerTape))
forwardLayer device state rep =
  case (state, rep) of
    (DenseState _ params _, FlatBatch xs) -> do
      outsE <- mlpdForwardBatch device params xs
      pure (fmap (\outs -> (FlatBatch outs, DenseTape xs)) outsE)
    (ResidualState _ scale params _, FlatBatch xs) -> do
      outsE <- mlpdForwardBatch device params xs
      pure $
        fmap
          ( \outs ->
              let scaled = fmap (VU.map (* scale)) outs
               in (FlatBatch (zipWith addVec xs scaled), ResidualTape xs)
          )
          outsE
    (PatchState _ runtime params _, FlatBatch xs) -> do
      let patchesBySample = fmap (extractPatches runtime) xs
          flatPatches = concat patchesBySample
      outsE <- mlpdForwardBatch device params flatPatches
      pure $
        fmap
          ( \flatOuts ->
              ( TokenBatch (unflattenBy (fmap length patchesBySample) flatOuts)
              , PatchTape patchesBySample
              )
          )
          outsE
    (AttentionState _ params _, TokenBatch samples) -> do
      let flatTokens = concat samples
      qkvE <- mlpdForwardBatch device params flatTokens
      pure $
        fmap
          ( \flatQkv ->
              let grouped = unflattenBy (fmap length samples) flatQkv
                  attended = zipWith attentionForward samples grouped
               in ( TokenBatch (fmap (fmap attentionOutput) attended)
                  , AttentionTape attended
                  )
          )
          qkvE
    (MeanPoolState _, TokenBatch samples) ->
      pure (Right (FlatBatch (fmap meanVector samples), MeanPoolTape (fmap length samples)))
    (DenseState name _ _, TokenBatch _) ->
      pure (Left (name <> ": dense layer expected flat inputs"))
    (ResidualState name _ _ _, TokenBatch _) ->
      pure (Left (name <> ": residual layer expected flat inputs"))
    (PatchState name _ _ _, TokenBatch _) ->
      pure (Left (name <> ": patch layer expected flat inputs"))
    (AttentionState name _ _, FlatBatch _) ->
      pure (Left (name <> ": attention layer expected token inputs"))
    (MeanPoolState name, FlatBatch _) ->
      pure (Left (name <> ": mean-pool layer expected token inputs"))

backwardAll
  :: MlpDevice
  -> AdamConfig
  -> [LayerState]
  -> [LayerTape]
  -> BatchRep
  -> Int
  -> IO (Either Text ([LayerState], BatchRep))
backwardAll device adamConfig states tapes upstream batchN = do
  result <-
    foldM
      step
      (Right ([], upstream))
      (zip (reverse states) (reverse tapes))
  pure $ fmap (\(statesRev, grad) -> (statesRev, grad)) result
 where
  step acc (state, tape) = case acc of
    Left err -> pure (Left err)
    Right (statesRev, grad) -> do
      back <- backwardLayer device adamConfig state tape grad batchN
      pure (fmap (\(state', grad') -> (state' : statesRev, grad')) back)

backwardLayer
  :: MlpDevice
  -> AdamConfig
  -> LayerState
  -> LayerTape
  -> BatchRep
  -> Int
  -> IO (Either Text (LayerState, BatchRep))
backwardLayer device adamConfig state tape upstream batchN =
  case (state, tape, upstream) of
    (DenseState name params adam, DenseTape xs, FlatBatch dys) -> do
      result <- deviceGradientStep device adamConfig params adam xs dys batchN
      pure (fmap (\(params', adam', dxs) -> (DenseState name params' adam', FlatBatch dxs)) result)
    (ResidualState name scale params adam, ResidualTape xs, FlatBatch dys) -> do
      let residualDys = fmap (VU.map (* scale)) dys
      result <- deviceGradientStep device adamConfig params adam xs residualDys batchN
      pure $
        fmap
          ( \(params', adam', dxs) ->
              ( ResidualState name scale params' adam'
              , FlatBatch (zipWith addVec dys dxs)
              )
          )
          result
    (PatchState name runtime params adam, PatchTape patchesBySample, TokenBatch tokenDys) -> do
      let flatPatches = concat patchesBySample
          flatDys = concat tokenDys
      result <- deviceGradientStep device adamConfig params adam flatPatches flatDys batchN
      pure $
        fmap
          ( \(params', adam', patchDxs) ->
              let dxs =
                    scatterPatchGradients
                      runtime
                      (fmap length patchesBySample)
                      patchDxs
               in (PatchState name runtime params' adam', FlatBatch dxs)
          )
          result
    (AttentionState name params adam, AttentionTape attended, TokenBatch dysBySample) -> do
      let back = zipWith attentionBackward attended dysBySample
          tokenInputs = concatMap (fmap tokenInput) attended
          qkvDys = concatMap fst back
          tokenDxsFromAttention = fmap snd back
      result <- deviceGradientStep device adamConfig params adam tokenInputs qkvDys batchN
      pure $
        fmap
          ( \(params', adam', tokenDxsFromQkv) ->
              let qkvGrouped = unflattenBy (fmap length attended) tokenDxsFromQkv
                  combined =
                    zipWith
                      (zipWith addVec)
                      tokenDxsFromAttention
                      qkvGrouped
               in (AttentionState name params' adam', TokenBatch combined)
          )
          result
    (MeanPoolState name, MeanPoolTape counts, FlatBatch dys) ->
      pure
        ( Right
            ( MeanPoolState name
            , TokenBatch
                [ replicate n (VU.map (/ fromIntegral n) dy)
                | (n, dy) <- zip counts dys
                ]
            )
        )
    _ -> pure (Left "backwardLayer: layer/tape/upstream shape mismatch")

deviceGradientStep
  :: MlpDevice
  -> AdamConfig
  -> MlpParams
  -> AdamState
  -> [Vector Double]
  -> [Vector Double]
  -> Int
  -> IO (Either Text (MlpParams, AdamState, [Vector Double]))
deviceGradientStep device adamConfig params adam xs dys batchN
  | length xs /= length dys =
      pure (Left "deviceGradientStep: input/gradient batch size mismatch")
  | otherwise = do
      dxE <- mlpdInputGradientBatch device params (zip xs dys)
      gradE <- mlpdBatchGradient device params (zip xs dys)
      pure $ do
        dxs <- dxE
        grad <- gradE
        let meanGrad = scaleMlpGradient (1.0 / fromIntegral (max 1 batchN)) grad
            (params', adam') = adamStep adamConfig adam params meanGrad
        Right (params', adam', dxs)

classifierOutputGradient :: Int -> Vector Double -> Int -> Vector Double
classifierOutputGradient numClasses outputVec label =
  let logits = VU.take numClasses outputVec
      probs = softmax logits
      dLogits =
        VU.imap
          (\i p -> p - if i == label then 1.0 else 0.0)
          probs
      tailCount = max 0 (VU.length outputVec - numClasses)
   in dLogits VU.++ VU.replicate tailCount 0.0

scaleMlpGradient :: Double -> MlpGradient -> MlpGradient
scaleMlpGradient s grad =
  MlpGradient
    { gradW1 = VU.map (* s) (gradW1 grad)
    , gradB1 = VU.map (* s) (gradB1 grad)
    , gradW2 = VU.map (* s) (gradW2 grad)
    , gradB2 = VU.map (* s) (gradB2 grad)
    }

attentionForward :: [Vector Double] -> [Vector Double] -> [AttentionToken]
attentionForward inputs qkvs =
  let triples = fmap splitQkv qkvs
      qs = fmap first3 triples
      ks = fmap second3 triples
      vs = fmap third3 triples
      scale =
        case qs of
          q : _ -> 1.0 / sqrt (fromIntegral (max 1 (VU.length q)))
          [] -> 1.0
      weightsByToken =
        [ softmax (VU.fromList [dot q k * scale | k <- ks])
        | q <- qs
        ]
      outputs =
        [ weightedSum weights vs
        | weights <- weightsByToken
        ]
   in [ AttentionToken
          { tokenInput = input
          , tokenQ = q
          , tokenK = k
          , tokenV = v
          , tokenWeights = weights
          , tokenOutput = output
          }
      | (input, q, k, v, weights, output) <- zip6 inputs qs ks vs weightsByToken outputs
      ]
 where
  first3 (a, _, _) = a
  second3 (_, b, _) = b
  third3 (_, _, c) = c

attentionOutput :: AttentionToken -> Vector Double
attentionOutput = tokenOutput

attentionBackward
  :: [AttentionToken]
  -> [Vector Double]
  -> ([Vector Double], [Vector Double])
attentionBackward tokens dzs =
  let qs = fmap tokenQ tokens
      ks = fmap tokenK tokens
      vs = fmap tokenV tokens
      weightsByToken = fmap tokenWeights tokens
      width =
        case qs of
          q : _ -> VU.length q
          [] -> 0
      scale = 1.0 / sqrt (fromIntegral (max 1 width))
      n = length tokens
      dV =
        [ VU.generate width $ \d ->
            sum
              [ (weightsByToken !! i VU.! j) * (dzs !! i VU.! d)
              | i <- [0 .. n - 1]
              ]
        | j <- [0 .. n - 1]
        ]
      dScores =
        [ let weights = weightsByToken !! i
              dA =
                VU.fromList
                  [ dot (dzs !! i) (vs !! j)
                  | j <- [0 .. n - 1]
                  ]
              weightedMean = VU.sum (VU.zipWith (*) weights dA)
           in VU.imap (\j w -> w * ((dA VU.! j) - weightedMean)) weights
        | i <- [0 .. n - 1]
        ]
      dQ =
        [ VU.generate width $ \d ->
            sum
              [ (dScores !! i VU.! j) * (ks !! j VU.! d) * scale
              | j <- [0 .. n - 1]
              ]
        | i <- [0 .. n - 1]
        ]
      dK =
        [ VU.generate width $ \d ->
            sum
              [ (dScores !! i VU.! j) * (qs !! i VU.! d) * scale
              | i <- [0 .. n - 1]
              ]
        | j <- [0 .. n - 1]
        ]
      dQkv = zipWith3 concat3 dQ dK dV
      dAttentionInputs = replicate n (VU.replicate width 0.0)
   in (dQkv, dAttentionInputs)

splitQkv :: Vector Double -> (Vector Double, Vector Double, Vector Double)
splitQkv vector =
  let n = VU.length vector `div` 3
      q = VU.slice 0 n vector
      k = VU.slice n n vector
      v = VU.slice (2 * n) n vector
   in (q, k, v)

concat3 :: Vector Double -> Vector Double -> Vector Double -> Vector Double
concat3 a b c = a VU.++ b VU.++ c

patchPositions :: ImageGeometry -> Int -> Int -> [[Int]]
patchPositions geometry size stride =
  [ [ pixelIndex geometry (x + dx) (y + dy) c
    | dy <- [0 .. size - 1]
    , dx <- [0 .. size - 1]
    , c <- [0 .. geomChannels geometry - 1]
    ]
  | y <- takeWhile (<= geomHeight geometry - size) [0, stride ..]
  , x <- takeWhile (<= geomWidth geometry - size) [0, stride ..]
  ]

extractPatches :: PatchRuntime -> Vector Double -> [Vector Double]
extractPatches runtime input =
  [ VU.fromList
      [ if idx < VU.length input then input VU.! idx else 0.0
      | idx <- indices
      ]
  | indices <- patchRuntimePositions runtime
  ]

scatterPatchGradients :: PatchRuntime -> [Int] -> [Vector Double] -> [Vector Double]
scatterPatchGradients runtime counts patchDxs =
  fmap scatterOne (unflattenBy counts patchDxs)
 where
  inputCount = patchRuntimeInputCount runtime
  positions = patchRuntimePositions runtime
  scatterOne dxs =
    VU.accum (+) (VU.replicate inputCount 0.0) $
      concat
        [ [ (idx, dx VU.! offset)
          | (offset, idx) <- zip [0 ..] indices
          , idx < inputCount
          ]
        | (indices, dx) <- zip positions dxs
        ]

pixelIndex :: ImageGeometry -> Int -> Int -> Int -> Int
pixelIndex geometry x y c =
  ((y * geomWidth geometry) + x) * geomChannels geometry + c

geometryForInput :: Int -> ImageGeometry
geometryForInput inputs
  | inputs == 784 = ImageGeometry 28 28 1
  | inputs == 3072 = ImageGeometry 32 32 3
  | inputs == 12288 = ImageGeometry 64 64 3
  | side * side == inputs = ImageGeometry side side 1
  | otherwise = ImageGeometry inputs 1 1
 where
  side = floor (sqrt (fromIntegral inputs :: Double))

patchSide :: ImageGeometry -> Int
patchSide geometry
  | geomHeight geometry <= 1 = 1
  | geomWidth geometry <= 2 = geomWidth geometry
  | geomWidth geometry <= 8 = 2
  | geomWidth geometry <= 32 = 4
  | otherwise = 8

meanVector :: [Vector Double] -> Vector Double
meanVector [] = VU.empty
meanVector vectors@(first : _) =
  VU.map (/ fromIntegral (length vectors)) $
    List.foldl' addVec (VU.replicate (VU.length first) 0.0) vectors

addVec :: Vector Double -> Vector Double -> Vector Double
addVec = VU.zipWith (+)

dot :: Vector Double -> Vector Double -> Double
dot a b = VU.sum (VU.zipWith (*) a b)

weightedSum :: Vector Double -> [Vector Double] -> Vector Double
weightedSum weights vectors =
  case vectors of
    [] -> VU.empty
    first : _ ->
      VU.generate (VU.length first) $ \d ->
        sum
          [ (weights VU.! i) * (vectors !! i VU.! d)
          | i <- [0 .. length vectors - 1]
          ]

unflattenBy :: [Int] -> [a] -> [[a]]
unflattenBy counts values =
  case counts of
    [] -> []
    n : ns ->
      let (chunk, rest) = splitAt n values
       in chunk : unflattenBy ns rest

clamp :: Int -> Int -> Int -> Int
clamp lo hi value = max lo (min hi value)

zip6 :: [a] -> [b] -> [c] -> [d] -> [e] -> [f] -> [(a, b, c, d, e, f)]
zip6 (a : as) (b : bs) (c : cs) (d : ds) (e : es) (f : fs) =
  (a, b, c, d, e, f) : zip6 as bs cs ds es fs
zip6 _ _ _ _ _ _ = []
