-- | The production-path negative controls that are still owed.
--
-- This leaf module holds only the list, so the production status loader can ask
-- whether any control is pending without linking the negative-control suite and
-- its fixtures. "JitML.Test.NegativeControls" re-exports it.
module JitML.Test.NegativeControls.Pending
  ( pendingProductionControls
  )
where

import Data.Text (Text)

-- | Controls that require external production evidence or a later phase.  The
-- suite keeps this explicit so a blocked live lane is not mistaken for a green
-- negative-control surface, and an entry reads @Phase \<n\>: ...@ so the phase
-- status projection can attribute it.  Every control is committed (the request,
-- event, journal, lifecycle, and per-row controls live beside this module), so
-- nothing is pending; a future control that cannot yet run is listed here, and
-- the stanza fails until it does.
pendingProductionControls :: [Text]
pendingProductionControls = []
