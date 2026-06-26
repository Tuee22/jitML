{-# LANGUAGE OverloadedStrings #-}

module JitML.Engines.MlpCheckpoint
  ( MlpCheckpointPlan (..)
  , fitMlpInput
  , mlpCheckpointPlan
  , runMlpCheckpointForwardWith
  )
where

import Data.List qualified as List
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU

import JitML.Checkpoint.Format
  ( ArchitectureMetadata (..)
  , CheckpointManifest (..)
  , TensorSpec (..)
  , WeightLayout (..)
  )
import JitML.Checkpoint.Store (LoadedWeightTensor (..))
import JitML.Numerics.Mlp
  ( MlpForward (..)
  , MlpParams
  , MlpShape (..)
  , mlpParamsFromFlat
  )

data MlpCheckpointPlan = MlpCheckpointPlan
  { mcpShape :: MlpShape
  , mcpSemanticOutputWidth :: Int
  }
  deriving stock (Eq, Show)

runMlpCheckpointForwardWith
  :: (MlpParams -> VU.Vector Double -> IO (Either Text MlpForward))
  -> CheckpointManifest
  -> [LoadedWeightTensor]
  -> [Double]
  -> IO (Maybe (Either Text [Double]))
runMlpCheckpointForwardWith forward manifest weights input =
  case mlpCheckpointPlan manifest of
    Left err -> pure (Just (Left err))
    Right Nothing -> pure Nothing
    Right (Just plan) ->
      case mlpParamsFromFlat (mcpShape plan) (concatMap loadedWeightValues weights) of
        Left err -> pure (Just (Left (Text.pack err)))
        Right params -> do
          result <- forward params (fitMlpInput (mlpInputs (mcpShape plan)) input)
          pure $
            Just $
              fmap
                (take (mcpSemanticOutputWidth plan) . VU.toList . forwardOutput)
                result

mlpCheckpointPlan :: CheckpointManifest -> Either Text (Maybe MlpCheckpointPlan)
mlpCheckpointPlan manifest =
  case fmap (`lookupTensorSpec` layoutSpecs manifest) ["W1", "b1", "W2", "b2"] of
    [Nothing, Nothing, Nothing, Nothing] -> Right Nothing
    [Just w1, Just b1, Just w2, Just b2] -> Just <$> planFromSpecs w1 b1 w2 b2 manifest
    partial ->
      Left
        ( "incomplete MLP checkpoint layout; found "
            <> Text.intercalate "," (mapMaybe (fmap tensorSpecName) partial)
            <> ", expected W1,b1,W2,b2"
        )

fitMlpInput :: Int -> [Double] -> VU.Vector Double
fitMlpInput width input =
  VU.fromList (take width (input <> repeat 0.0))

layoutSpecs :: CheckpointManifest -> [TensorSpec]
layoutSpecs manifest =
  case manifestWeightLayout manifest of
    FlatWeightLayout specs -> specs
    NamedTensorWeightLayout specs -> specs

lookupTensorSpec :: Text -> [TensorSpec] -> Maybe TensorSpec
lookupTensorSpec name =
  List.find ((== name) . tensorSpecName)

planFromSpecs
  :: TensorSpec
  -> TensorSpec
  -> TensorSpec
  -> TensorSpec
  -> CheckpointManifest
  -> Either Text MlpCheckpointPlan
planFromSpecs w1 b1 w2 b2 manifest = do
  (hidden, inputs) <- matrixShape "W1" (tensorSpecShape w1)
  b1Width <- vectorShape "b1" (tensorSpecShape b1)
  (rawOutputs, hidden2) <- matrixShape "W2" (tensorSpecShape w2)
  b2Width <- vectorShape "b2" (tensorSpecShape b2)
  if hidden /= b1Width
    then
      Left ("MLP checkpoint shape mismatch: W1 hidden=" <> showText hidden <> ", b1=" <> showText b1Width)
    else
      if hidden /= hidden2
        then
          Left
            ("MLP checkpoint shape mismatch: W1 hidden=" <> showText hidden <> ", W2 hidden=" <> showText hidden2)
        else
          if rawOutputs /= b2Width
            then
              Left
                ("MLP checkpoint shape mismatch: W2 outputs=" <> showText rawOutputs <> ", b2=" <> showText b2Width)
            else do
              semanticWidth <- semanticOutputWidth rawOutputs manifest
              Right
                MlpCheckpointPlan
                  { mcpShape =
                      MlpShape
                        { mlpInputs = inputs
                        , mlpHidden = hidden
                        , mlpOutputs = rawOutputs
                        }
                  , mcpSemanticOutputWidth = semanticWidth
                  }

semanticOutputWidth :: Int -> CheckpointManifest -> Either Text Int
semanticOutputWidth rawOutputs manifest =
  case architectureOutputs (manifestArchitecture manifest) of
    [] -> Right rawOutputs
    (firstOutput : _) -> do
      width <-
        positiveProduct ("architecture output " <> tensorSpecName firstOutput) (tensorSpecShape firstOutput)
      if width <= rawOutputs
        then Right width
        else
          Left
            ( "MLP semantic output width "
                <> showText width
                <> " exceeds raw output width "
                <> showText rawOutputs
            )

matrixShape :: Text -> [Int] -> Either Text (Int, Int)
matrixShape _ [rows, cols]
  | rows > 0 && cols > 0 = Right (rows, cols)
matrixShape name shape =
  Left (name <> " must have positive matrix shape [rows, cols], got " <> showText shape)

vectorShape :: Text -> [Int] -> Either Text Int
vectorShape _ [width]
  | width > 0 = Right width
vectorShape name shape =
  Left (name <> " must have positive vector shape [width], got " <> showText shape)

positiveProduct :: Text -> [Int] -> Either Text Int
positiveProduct name shape
  | not (null shape) && all (> 0) shape = Right (product shape)
  | otherwise = Left (name <> " must have positive shape, got " <> showText shape)

showText :: (Show a) => a -> Text
showText = Text.pack . show
