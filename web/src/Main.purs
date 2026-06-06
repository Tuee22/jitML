-- | Halogen shell entrypoint. Reads `location.hash` (without the leading
-- | `#`) and mounts the matching `Panels.*` component. Falls back to the
-- | portals home when no hash is set so the bundled admin portals
-- | declared in `src/JitML/Routes.hs` are discoverable without prior
-- | knowledge of edge route prefixes. The hash routing keeps the demo
-- | bundle a single static artifact while the Playwright e2e matrix
-- | selects which panel each test exercises.
module Main where

import Prelude

import Data.Either (either)
import Data.Maybe as Maybe
import Data.String as String
import Effect (Effect)
import Effect.Aff (Aff, runAff_)
import Effect.Class (liftEffect)
import Effect.Exception (throwException)
import Effect.Ref (Ref)
import Effect.Ref as Ref
import PanelRegistry as PanelRegistry
import Panels.Portals as Portals
import Web.HTML (window)
import Web.HTML.Location as Location
import Web.HTML.Window as Window

foreign import onHashChange :: Effect Unit -> Effect Unit

main :: Effect Unit
main = do
  currentDispose <- Ref.new (pure unit :: Aff Unit)
  mountCurrentHash currentDispose
  onHashChange (mountCurrentHash currentDispose)

mountCurrentHash :: Ref (Aff Unit) -> Effect Unit
mountCurrentHash currentDispose =
  runAff_ (either throwException (const (pure unit))) do
    selectedMount <- liftEffect currentMount
    previousDispose <- liftEffect (Ref.read currentDispose)
    previousDispose
    nextDispose <- selectedMount
    liftEffect (Ref.write nextDispose currentDispose)

currentMount :: Effect (Aff (Aff Unit))
currentMount = do
  w <- window
  loc <- Window.location w
  hashRaw <- Location.hash loc
  let hash = String.drop 1 hashRaw
  pure case hash of
    h | h == Portals.panelName -> Portals.mount
    h -> Maybe.fromMaybe Portals.mount (PanelRegistry.mountForHash h)
