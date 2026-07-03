module JitML.Engines.LayerGraphCheckpoint
  ( fitLayerGraphInput
  , runLayerGraphCheckpointForwardOneDnn
  )
where

import Data.Text (Text)
import Data.Vector.Unboxed qualified as VU

import JitML.Checkpoint.Format (CheckpointManifest)
import JitML.Checkpoint.Store
  ( LoadedWeightTensor
  , layerGraphFromCheckpoint
  )
import JitML.Env.Env (Env)
import JitML.Numerics.LayerGraph qualified as LayerGraph
import JitML.Numerics.LayerGraphOneDnn qualified as LayerGraphOneDnn

runLayerGraphCheckpointForwardOneDnn
  :: Env
  -> CheckpointManifest
  -> [LoadedWeightTensor]
  -> [Double]
  -> IO (Maybe (Either Text [Double]))
runLayerGraphCheckpointForwardOneDnn env manifest weights input =
  case layerGraphFromCheckpoint manifest weights of
    Left err -> pure (Just (Left err))
    Right Nothing -> pure Nothing
    Right (Just graph) ->
      case LayerGraph.tensorShapeWidth (LayerGraph.layerGraphInputShape graph) of
        Left err -> pure (Just (Left err))
        Right inputWidth -> do
          result <-
            LayerGraphOneDnn.runLayerGraphForwardOneDnn
              env
              graph
              (fitLayerGraphInput inputWidth input)
          pure $
            Just $
              fmap
                (VU.toList . LayerGraph.layerTapeOutput . LayerGraphOneDnn.layerGraphOneDnnForwardTape)
                result

fitLayerGraphInput :: Int -> [Double] -> VU.Vector Double
fitLayerGraphInput width input =
  VU.fromList (take width (input <> repeat 0.0))
