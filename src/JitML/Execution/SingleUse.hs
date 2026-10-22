-- | A small atomic consumption guard. This is coordination data, not evidence
-- of execution, durable storage, producer identity or checkpoint admission.
module JitML.Execution.SingleUse
  ( SingleUse
  , newSingleUse
  , tryConsumeSingleUse
  )
where

import Data.IORef (IORef, atomicModifyIORef', newIORef)

-- Deliberately no exported constructor, record field or deriving instance.
-- Keep the existing data wrapper: a newtype changes its WHNF/laziness.
{- HLINT ignore SingleUse "Use newtype instead of data" -}
data SingleUse = SingleUse (IORef Bool)

newSingleUse :: IO SingleUse
newSingleUse = SingleUse <$> newIORef False

-- | Exactly one caller observes True, including concurrent callers. A claimed
-- action which later throws or is interrupted remains consumed.
tryConsumeSingleUse :: SingleUse -> IO Bool
tryConsumeSingleUse (SingleUse ref) =
  atomicModifyIORef' ref (\consumed -> (True, not consumed))
