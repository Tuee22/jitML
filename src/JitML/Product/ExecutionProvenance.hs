-- | Closed recorded/admitted execution kind. The host payload determines its
-- authority: a parsed reference is data, not an actual producer capability.
-- Neural execution always retains its existing opaque device witness.
module JitML.Product.ExecutionProvenance
  ( ExecutionProvenance (..)
  ) where

import JitML.Product.DeviceWitness (DeviceExecutionWitness)

data ExecutionProvenance host
  = NeuralDeviceExecution !DeviceExecutionWitness
  | ArsHostLinearExecution !host
  deriving stock (Eq, Ord, Show)
