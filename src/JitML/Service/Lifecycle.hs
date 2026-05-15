{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.Lifecycle
    ( LifecyclePhase (..)
    , SPhase (..)
    , lifecyclePlan
    , renderLifecyclePhase
    )
where

import Data.Text (Text)

data LifecyclePhase
    = Load
    | Prereq
    | Acquire
    | Ready
    | Serve
    | Drain
    | Exit
    deriving stock (Eq, Show)

data SPhase phase where
    SLoad :: SPhase 'Load
    SPrereq :: SPhase 'Prereq
    SAcquire :: SPhase 'Acquire
    SReady :: SPhase 'Ready
    SServe :: SPhase 'Serve
    SDrain :: SPhase 'Drain
    SExit :: SPhase 'Exit

lifecyclePlan :: [LifecyclePhase]
lifecyclePlan =
    [Load, Prereq, Acquire, Ready, Serve, Drain, Exit]

renderLifecyclePhase :: LifecyclePhase -> Text
renderLifecyclePhase Load = "load"
renderLifecyclePhase Prereq = "prereq"
renderLifecyclePhase Acquire = "acquire"
renderLifecyclePhase Ready = "ready"
renderLifecyclePhase Serve = "serve"
renderLifecyclePhase Drain = "drain"
renderLifecyclePhase Exit = "exit"
