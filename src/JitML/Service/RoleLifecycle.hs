{-# LANGUAGE OverloadedStrings #-}

-- | Sprint 5.14 (Pulsar ML-Workflow convergence) — the one-binary role model
-- layered onto the existing shared lifecycle skeleton
-- ('JitML.Service.Lifecycle': @Load → Prereq → Acquire → Ready → Serve → Drain →
-- Exit@). The one @jitml service@ binary runs as exactly one 'Role'
-- ('JitML.Service.BootConfig.Role') selected by typed Dhall @activeRole@; this
-- module owns the /pure/ per-role capability profile that distinguishes the
-- role-specific @Acquire@/@Serve@/@Drain@ behaviour. The live role-specific
-- serving (Coordinator topic reconcile, Webapp websocket fan-out) is wired by
-- Phases @11@/@15@. See @documents/engineering/pulsar_ml_workflow.md@ → /The
-- three roles/ + /Configuration and roles/.
module JitML.Service.RoleLifecycle
  ( RoleProfile (..)
  , roleProfile
  , roleLabel
  , computeRoles
  , roleLifecyclePlan
  )
where

import Data.Text (Text)

import JitML.Service.BootConfig (Role (..))
import JitML.Service.Lifecycle (LifecyclePhase, lifecyclePlan)

-- | The capability profile of a role. Exactly one role computes ML (the
-- Engine); exactly one owns the Pulsar topic lifecycle (the Coordinator); exactly
-- one serves the browser websocket (the Webapp). These invariants are what make
-- the Webapp substrate-agnostic and the Engine the single worker.
data RoleProfile = RoleProfile
  { profileRole :: Role
  , profileComputes :: Bool
  -- ^ Runs ML compute (training + inference). Engine only.
  , profileOwnsTopics :: Bool
  -- ^ Owns the derived topic-algebra reconcile + readiness gating. Coordinator
  -- only.
  , profileServesWebsocket :: Bool
  -- ^ Serves the browser snapshot/patch websocket + static artifacts. Webapp
  -- only.
  }
  deriving stock (Eq, Show)

roleProfile :: Role -> RoleProfile
roleProfile Engine =
  RoleProfile
    { profileRole = Engine
    , profileComputes = True
    , profileOwnsTopics = False
    , profileServesWebsocket = False
    }
roleProfile Coordinator =
  RoleProfile
    { profileRole = Coordinator
    , profileComputes = False
    , profileOwnsTopics = True
    , profileServesWebsocket = False
    }
roleProfile Webapp =
  RoleProfile
    { profileRole = Webapp
    , profileComputes = False
    , profileOwnsTopics = False
    , profileServesWebsocket = True
    }

roleLabel :: Role -> Text
roleLabel Engine = "engine"
roleLabel Coordinator = "coordinator"
roleLabel Webapp = "webapp"

-- | Every role runs the same shared lifecycle skeleton in the same phase order;
-- only the @Acquire@/@Serve@/@Drain@ behaviour differs (by 'roleProfile').
roleLifecyclePlan :: Role -> [LifecyclePhase]
roleLifecyclePlan _ = lifecyclePlan

-- | The roles that compute ML. Invariant: exactly one (the Engine). The Webapp
-- and Coordinator run no ML compute.
computeRoles :: [Role]
computeRoles = filter (profileComputes . roleProfile) [Engine, Coordinator, Webapp]
