-- | Portals home: default landing for the demo SPA. Renders the slim
-- | shared header plus a two-column directory — left column lists the
-- | in-SPA panels (from `PanelRegistry`), right column lists the
-- | Envoy-routed admin portals (from the generated `AdminPortals`
-- | module, sourced from `src/JitML/Routes.hs`). No state; pure render.
module Panels.Portals where

import Prelude

import Effect.Aff (Aff)
import Effect.Aff.Class (class MonadAff)
import Generated.AdminPortals (AdminPortal, adminPortals)
import Halogen as H
import Halogen.Aff (awaitBody)
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Halogen.VDom.Driver (runUI)
import Chrome.Header as Header
import PanelRegistry (PanelEntry, panels)

panelName :: String
panelName = "portals"

component :: forall query input output m. MonadAff m => H.Component query input output m
component =
  H.mkComponent
    { initialState: \_ -> unit
    , render: \_ -> render
    , eval: H.mkEval H.defaultEval
    }
  where
  render =
    HH.div
      [ HP.id panelName, HP.classes [ H.ClassName "jitml-panel" ] ]
      [ Header.render
      , HH.h2_ [ HH.text "jitML demo portals" ]
      , HH.div
          [ HP.classes [ H.ClassName "jitml-portals-columns" ] ]
          [ panelColumn
          , adminColumn
          ]
      ]

  panelColumn =
    HH.section
      [ HP.id "jitml-portals-panels"
      , HP.classes [ H.ClassName "jitml-portals-column" ]
      ]
      [ HH.h3_ [ HH.text "Panels" ]
      , HH.ul_ (map renderPanel panels)
      ]

  adminColumn =
    HH.section
      [ HP.id "jitml-portals-admin"
      , HP.classes [ H.ClassName "jitml-portals-column" ]
      ]
      [ HH.h3_ [ HH.text "Admin portals" ]
      , HH.ul_ (map renderAdmin adminPortals)
      ]

  renderPanel :: forall w i. PanelEntry -> HH.HTML w i
  renderPanel entry =
    HH.li_
      [ HH.a
          [ HP.id ("jitml-portals-panel-" <> entry.hash)
          , HP.href ("#" <> entry.hash)
          , HP.classes [ H.ClassName "jitml-portals-link" ]
          ]
          [ HH.text entry.label ]
      ]

  renderAdmin :: forall w i. AdminPortal -> HH.HTML w i
  renderAdmin portal =
    HH.li_
      [ HH.a
          [ HP.id ("jitml-portals-admin-" <> portal.name)
          , HP.href portal.path
          , HP.classes [ H.ClassName "jitml-portals-link" ]
          ]
          [ HH.text portal.label ]
      ]

mount :: Aff (Aff Unit)
mount = do
  body <- awaitBody
  ui <- runUI component unit body
  pure ui.dispose
