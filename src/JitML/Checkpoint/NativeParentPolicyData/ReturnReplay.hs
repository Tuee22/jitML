{-# LANGUAGE OverloadedStrings #-}

-- | Closed recorded-output mathematical replay. This is neither a real device
-- nor a device witness and exposes no callback/capability factory. Environment
-- transitions and family/mask/action rules belong to the existing evaluator.
module JitML.Checkpoint.NativeParentPolicyData.ReturnReplay (auditReturnEvaluationData) where

import Control.Monad (unless)
import Data.IORef (newIORef, readIORef, writeIORef)
import Data.Text (Text)
import Data.Vector.Unboxed qualified as VU
import GHC.Float (castDoubleToWord64)

import JitML.Checkpoint.NativePhase.Graph qualified as Graph
import JitML.Checkpoint.NativePhase.Projection qualified as Projection
import JitML.Checkpoint.NativePhase.Projection.Build qualified as Build
import JitML.Checkpoint.NativePhase.Types
import JitML.Numerics.Mlp qualified as Mlp
import JitML.Numerics.MlpDevice (MlpDevice (..))
import JitML.RL.NativeReturnEvaluation qualified as Return

auditReturnEvaluationData
  :: Return.RawNativeReturnEvaluation -> IO (Either Build.ProjectionFailure ())
auditReturnEvaluationData observed = do
  replayed <- case Return.nativeEvaluationPolicy observed of
    Return.NativeArsHostEvaluation config theta -> pure (Return.evaluateNativeArsReturnPolicy (Return.nativeEvaluationSpec observed) config theta)
    Return.NativeNeuralEvaluation policy -> do
      pending <- newIORef (Return.nativeEvaluationForwards observed)
      let denied :: IO (Either Text value)
          denied = pure (Left "parent recorded-forward audit refuses a non-scalar numerical operation")
          forward params input = do
            remaining <- readIORef pending
            case remaining of
              event : rest
                | sameParams params (Return.nativeForwardParameters event)
                    && sameVector input (Return.nativeForwardInput event) -> do
                    writeIORef pending rest
                    case Return.nativeForwardOutcome event of
                      Return.NativeForwardReturned (Right output) -> pure (Right (Mlp.MlpForward input VU.empty VU.empty output))
                      _ -> pure (Left "parent recorded-forward audit encountered a failed captured call")
              _ -> pure (Left "parent recorded-forward input/params/order or EOF differs")
          device =
            MlpDevice
              { mlpdForward = forward
              , mlpdBackward = \_ _ _ -> denied
              , mlpdForwardBatch = \_ _ -> denied
              , mlpdBatchGradient = \_ _ -> denied
              , mlpdInputGradientBatch = \_ _ -> denied
              , mlpdExecutionWitness = denied
              , mlpdExecution = Nothing
              }
      result <-
        Return.evaluateNativeNeuralReturnPolicy device (Return.nativeEvaluationSpec observed) policy
      remaining <- readIORef pending
      pure $
        if null remaining
          then result
          else
            result
              { Return.nativeEvaluationStatus =
                  Return.NativeEvaluationRejected "parent recorded-forward audit has unused observations"
              }
  before <- Projection.projectReturnEvaluationData Graph.emptyNodePool observed
  after <- Projection.projectReturnEvaluationData Graph.emptyNodePool replayed
  pure $ do
    (original, pool) <- before
    (actual, replayedPool) <- after
    unless
      (original == actual && bytes pool == bytes replayedPool)
      ( Left
          ( Build.ProjectionDataRejected
              (Malformed "parent complete RETURN result differs from recorded-forward/public-rule replay")
          )
      )
 where
  bytes pool = [(digest, raw) | (digest, _, raw) <- Graph.nodePoolEntries pool]
  sameVector a b =
    VU.length a == VU.length b
      && VU.ifoldl' (\equal i x -> equal && castDoubleToWord64 x == castDoubleToWord64 (b VU.! i)) True a
  sameParams a b =
    Mlp.paramShape a == Mlp.paramShape b
      && and
        ( zipWith
            sameVector
            [Mlp.paramW1 a, Mlp.paramB1 a, Mlp.paramW2 a, Mlp.paramB2 a]
            [Mlp.paramW1 b, Mlp.paramB1 b, Mlp.paramW2 b, Mlp.paramB2 b]
        )
