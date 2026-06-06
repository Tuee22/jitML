module Chrome.Header where

import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP

-- | Slim shared header rendered at the top of every panel.
-- | Pure render; carries the jitML wordmark and a [home] link to
-- | the portals panel (#portals).
render :: forall w i. HH.HTML w i
render =
  HH.header
    [ HP.id "jitml-chrome", HP.classes [ H.ClassName "jitml-chrome" ] ]
    [ HH.span
        [ HP.classes [ H.ClassName "jitml-wordmark" ] ]
        [ HH.text "jitML" ]
    , HH.a
        [ HP.id "jitml-chrome-home"
        , HP.href "#portals"
        , HP.classes [ H.ClassName "jitml-chrome-home" ]
        ]
        [ HH.text "[home]" ]
    ]
