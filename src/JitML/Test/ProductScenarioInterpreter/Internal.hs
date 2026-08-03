-- | Internal capability connecting the real live-workflow interpreter to the
-- ProductScenario report boundary.  This module is deliberately hidden from
-- the library's public module surface: callers of 'JitML.Test.Report' cannot
-- wrap an arbitrary value and claim that the interpreter completed it.
module JitML.Test.ProductScenarioInterpreter.Internal
  ( ProductScenarioInterpreterRun
  , productScenarioInterpreterRun
  , productScenarioInterpreterCompletedRun
  )
where

import JitML.Test.LiveWorkflow (CompletedRunEvidence)

-- | Opaque proof that the ProductScenario runner received this exact
-- completion from 'JitML.Test.LiveWorkflow.runLiveWorkflow'.  The runner is
-- the production constructor; 'JitML.Test.RunContract' uses the same hidden
-- constructor only for positive interpreter fixtures.
newtype ProductScenarioInterpreterRun terminal evidence violation missing
  = ProductScenarioInterpreterRun
      (CompletedRunEvidence terminal evidence violation missing)
  deriving stock (Eq, Show)

productScenarioInterpreterRun
  :: CompletedRunEvidence terminal evidence violation missing
  -> ProductScenarioInterpreterRun terminal evidence violation missing
productScenarioInterpreterRun = ProductScenarioInterpreterRun

productScenarioInterpreterCompletedRun
  :: ProductScenarioInterpreterRun terminal evidence violation missing
  -> CompletedRunEvidence terminal evidence violation missing
productScenarioInterpreterCompletedRun
  (ProductScenarioInterpreterRun completed) = completed
