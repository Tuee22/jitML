{-# LANGUAGE OverloadedStrings #-}

-- | Pure-Haskell simulator bindings used by the RL canonical stanza
-- ahead of the live env runtime owned by Phase 13. Provides typed
-- initial / step boundaries for the canonical @cartpole@
-- (CartPole-v1), @mountain-car@ (MountainCar-v0), @lunar-lander@
-- (LunarLander-v2, simplified rigid-body port of the Gym Box2D
-- reference), and @atari-subset@ (deterministic 128-byte RAM-state
-- stub matching the Atari action/obs surface) environments plus a
-- deterministic render-frame projection.
--
-- The lunar-lander port is a pure-Haskell rigid-body simulation in
-- the style of OpenAI Gym's @lunar_lander.py@ but written from the
-- documented equations rather than depending on Box2D — bit-for-bit
-- equivalence with Box2D is explicitly *not* a goal; same-substrate,
-- same-seed reproducibility is. Real Box2D / ALE FFI bindings would
-- introduce cross-version float drift and a 32 GB image rebuild for
-- limited deterministic-contract win; see Phase 8 Sprint 8.3 closure
-- notes for the chosen approach.
module JitML.RL.Simulator
  ( AtariSubsetState (..)
  , CartPoleState (..)
  , LunarLanderState (..)
  , MountainCarState (..)
  , RenderFrame (..)
  , SimStep (..)
  , SimulatedEnvironment (..)
  , atariSubsetEnvironment
  , atariSubsetInitial
  , atariSubsetRenderFrame
  , atariSubsetStep
  , cartPoleEnvironment
  , cartPoleInitial
  , cartPoleRenderFrame
  , cartPoleStep
  , lunarLanderEnvironment
  , lunarLanderInitial
  , lunarLanderRenderFrame
  , lunarLanderStep
  , mountainCarEnvironment
  , mountainCarInitial
  , mountainCarRenderFrame
  , mountainCarStep
  , stepEnvironmentIO
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

-- | Result of advancing one simulator state by one action.
data SimStep state = SimStep
  { simStepState :: state
  , simStepReward :: Double
  , simStepDone :: Bool
  }
  deriving stock (Eq, Show)

-- | Canonical observation projection used by render-frame access. The
-- @Double@ list is the per-environment observation vector (cart position
-- and pole angle for cartpole; position and velocity for mountain-car).
-- The @Text@ caption is the deterministic ASCII frame produced by the
-- simulator's @render@ helper.
data RenderFrame = RenderFrame
  { renderObservation :: [Double]
  , renderCaption :: Text
  }
  deriving stock (Eq, Show)

-- | The typed env-step boundary called out by the development plan as
-- @step :: Env -> Action -> IO (Obs, Reward, Done)@. Concrete
-- @cartPoleEnvironment@ and @mountainCarEnvironment@ values cover the
-- two canonical classical-control environments.
data SimulatedEnvironment state = SimulatedEnvironment
  { envName :: Text
  , envInitial :: state
  , envStep :: state -> Int -> SimStep state
  , envRenderFrame :: state -> RenderFrame
  , envActionCount :: Int
  , envObservationSize :: Int
  }

-- | Wrap a pure simulator step in @IO@ to satisfy the doctrine env-step
-- signature without duplicating the underlying physics. The pure form
-- stays exported so deterministic-stub tests can step without an IO
-- boundary.
stepEnvironmentIO
  :: SimulatedEnvironment state
  -> state
  -> Int
  -> IO ([Double], Double, Bool)
stepEnvironmentIO env state action =
  let result = envStep env state action
      frame = envRenderFrame env (simStepState result)
   in pure (renderObservation frame, simStepReward result, simStepDone result)

-- * CartPole-v1

-- | Continuous CartPole-v1 state vector: cart position, cart velocity,
-- pole angle (radians), pole angular velocity (radians/second).
data CartPoleState = CartPoleState
  { cartPosition :: Double
  , cartVelocity :: Double
  , poleAngle :: Double
  , poleAngularVelocity :: Double
  }
  deriving stock (Eq, Show)

cartPoleInitial :: CartPoleState
cartPoleInitial = CartPoleState 0 0 0 0

cartPoleEnvironment :: SimulatedEnvironment CartPoleState
cartPoleEnvironment =
  SimulatedEnvironment
    { envName = "cartpole"
    , envInitial = cartPoleInitial
    , envStep = cartPoleStep
    , envRenderFrame = cartPoleRenderFrame
    , envActionCount = 2
    , envObservationSize = 4
    }

cartPoleStep :: CartPoleState -> Int -> SimStep CartPoleState
cartPoleStep state action =
  let force =
        if action <= 0
          then -cartPoleForceMag
          else cartPoleForceMag
      cosTheta = cos (poleAngle state)
      sinTheta = sin (poleAngle state)
      temp =
        ( force
            + cartPolePoleMassLength * poleAngularVelocity state * poleAngularVelocity state * sinTheta
        )
          / cartPoleTotalMass
      thetaAcc =
        (cartPoleGravity * sinTheta - cosTheta * temp)
          / ( cartPoleLength
                * (4.0 / 3.0 - cartPoleMassPole * cosTheta * cosTheta / cartPoleTotalMass)
            )
      xAcc =
        temp - cartPolePoleMassLength * thetaAcc * cosTheta / cartPoleTotalMass
      newX = cartPosition state + cartPoleTau * cartVelocity state
      newXDot = cartVelocity state + cartPoleTau * xAcc
      newTheta = poleAngle state + cartPoleTau * poleAngularVelocity state
      newThetaDot = poleAngularVelocity state + cartPoleTau * thetaAcc
      next =
        CartPoleState
          { cartPosition = newX
          , cartVelocity = newXDot
          , poleAngle = newTheta
          , poleAngularVelocity = newThetaDot
          }
      done =
        abs newX > cartPoleXThreshold
          || abs newTheta > cartPoleAngleThreshold
      reward = if done then 0.0 else 1.0
   in SimStep next reward done

cartPoleRenderFrame :: CartPoleState -> RenderFrame
cartPoleRenderFrame state =
  RenderFrame
    { renderObservation =
        [ cartPosition state
        , cartVelocity state
        , poleAngle state
        , poleAngularVelocity state
        ]
    , renderCaption =
        "cartpole x="
          <> showDouble (cartPosition state)
          <> " theta="
          <> showDouble (poleAngle state)
    }

cartPoleGravity
  , cartPoleMassCart
  , cartPoleMassPole
  , cartPoleTotalMass
  , cartPoleLength
  , cartPolePoleMassLength
  , cartPoleForceMag
  , cartPoleTau
  , cartPoleXThreshold
  , cartPoleAngleThreshold
    :: Double
cartPoleGravity = 9.8
cartPoleMassCart = 1.0
cartPoleMassPole = 0.1
cartPoleTotalMass = cartPoleMassPole + cartPoleMassCart
cartPoleLength = 0.5
cartPolePoleMassLength = cartPoleMassPole * cartPoleLength
cartPoleForceMag = 10.0
cartPoleTau = 0.02
cartPoleXThreshold = 2.4
cartPoleAngleThreshold = 12.0 * pi / 180.0

-- * MountainCar-v0

-- | Continuous MountainCar-v0 state vector: car position (clamped to
-- @[-1.2, 0.6]@) and velocity (clamped to @[-0.07, 0.07]@).
data MountainCarState = MountainCarState
  { mountainCarPosition :: Double
  , mountainCarVelocity :: Double
  }
  deriving stock (Eq, Show)

mountainCarInitial :: MountainCarState
mountainCarInitial = MountainCarState (-0.5) 0.0

mountainCarEnvironment :: SimulatedEnvironment MountainCarState
mountainCarEnvironment =
  SimulatedEnvironment
    { envName = "mountain-car"
    , envInitial = mountainCarInitial
    , envStep = mountainCarStep
    , envRenderFrame = mountainCarRenderFrame
    , envActionCount = 3
    , envObservationSize = 2
    }

mountainCarStep :: MountainCarState -> Int -> SimStep MountainCarState
mountainCarStep state action =
  let actionForce = fromIntegral (action - 1)
      vRaw =
        mountainCarVelocity state
          + actionForce * mountainCarForce
          - cos (3 * mountainCarPosition state) * mountainCarGravity
      vClamped = clamp vRaw (-mountainCarMaxSpeed) mountainCarMaxSpeed
      pRaw = mountainCarPosition state + vClamped
      pClamped = clamp pRaw mountainCarMinPosition mountainCarMaxPosition
      vAtLeftWall =
        if pClamped == mountainCarMinPosition && vClamped < 0
          then 0
          else vClamped
      done = pClamped >= mountainCarGoalPosition
      reward = -1.0
      next =
        MountainCarState
          { mountainCarPosition = pClamped
          , mountainCarVelocity = vAtLeftWall
          }
   in SimStep next reward done

mountainCarRenderFrame :: MountainCarState -> RenderFrame
mountainCarRenderFrame state =
  RenderFrame
    { renderObservation =
        [ mountainCarPosition state
        , mountainCarVelocity state
        ]
    , renderCaption =
        "mountain-car p="
          <> showDouble (mountainCarPosition state)
          <> " v="
          <> showDouble (mountainCarVelocity state)
    }

mountainCarGravity
  , mountainCarForce
  , mountainCarMaxSpeed
  , mountainCarMinPosition
  , mountainCarMaxPosition
  , mountainCarGoalPosition
    :: Double
mountainCarGravity = 0.0025
mountainCarForce = 0.001
mountainCarMaxSpeed = 0.07
mountainCarMinPosition = -1.2
mountainCarMaxPosition = 0.6
mountainCarGoalPosition = 0.5

-- * LunarLander-v2

-- | LunarLander-v2 state: lander position @(x, y)@ in metres above the
-- procedurally-flat landing pad (positive @y@ is up), linear velocity
-- @(vx, vy)@ in m/s, orientation @angle@ in radians (0 = upright,
-- positive = tilted right), angular velocity @omega@ in rad/s, plus a
-- pair of leg-contact flags. The state vector is the eight-dimensional
-- observation reported by the canonical Gym env; the contact flags
-- expose as booleans here and are projected to @0.0 / 1.0@ in
-- @lunarLanderRenderFrame@.
data LunarLanderState = LunarLanderState
  { lunarLanderX :: Double
  , lunarLanderY :: Double
  , lunarLanderVx :: Double
  , lunarLanderVy :: Double
  , lunarLanderAngle :: Double
  , lunarLanderOmega :: Double
  , lunarLanderLeftLegContact :: Bool
  , lunarLanderRightLegContact :: Bool
  }
  deriving stock (Eq, Show)

-- | Canonical Gym initial state: lander hovers above the pad with a
-- small positive vertical offset and no initial motion. The Gym
-- reference adds Gaussian noise to the initial impulse; this port is
-- deterministic by construction since the determinism contract here
-- prefers seed-derived noise from upstream RL primitives over
-- env-internal stochasticity.
lunarLanderInitial :: LunarLanderState
lunarLanderInitial =
  LunarLanderState
    { lunarLanderX = 0.0
    , lunarLanderY = lunarLanderInitialAltitude
    , lunarLanderVx = 0.0
    , lunarLanderVy = 0.0
    , lunarLanderAngle = 0.0
    , lunarLanderOmega = 0.0
    , lunarLanderLeftLegContact = False
    , lunarLanderRightLegContact = False
    }

lunarLanderEnvironment :: SimulatedEnvironment LunarLanderState
lunarLanderEnvironment =
  SimulatedEnvironment
    { envName = "lunar-lander"
    , envInitial = lunarLanderInitial
    , envStep = lunarLanderStep
    , envRenderFrame = lunarLanderRenderFrame
    , envActionCount = 4
    , envObservationSize = 8
    }

-- | Advance the lander one Gym timestep under the documented discrete
-- action space:
--
--   * @0@ no-op
--   * @1@ fire left side engine (positive torque, small lateral thrust right)
--   * @2@ fire main engine (thrust along current up-axis)
--   * @3@ fire right side engine (negative torque, small lateral thrust left)
--
-- The dynamics integrate gravity, engine thrust, angular acceleration,
-- and (when @y <= 0@) a perfectly-inelastic ground contact that zeros
-- vertical velocity and sets the leg-contact flags. Reward follows the
-- Gym shaping: distance penalty, velocity penalty, angle penalty, leg
-- contact bonus, plus a large terminal bonus for soft landings or
-- penalty for crashes/out-of-bounds. The lander is on the ground when
-- @y@ has been clamped to zero and the body angle is within
-- 'lunarLanderUprightTolerance'.
lunarLanderStep :: LunarLanderState -> Int -> SimStep LunarLanderState
lunarLanderStep state action =
  let
    -- engine thrust in body frame, then rotated to world frame
    mainThrust = if action == 2 then lunarLanderMainThrust else 0.0
    sideThrust
      | action == 1 = lunarLanderSideThrust
      | action == 3 = -lunarLanderSideThrust
      | otherwise = 0.0
    angularImpulse
      | action == 1 = lunarLanderSideTorque
      | action == 3 = -lunarLanderSideTorque
      | otherwise = 0.0
    cosA = cos (lunarLanderAngle state)
    sinA = sin (lunarLanderAngle state)
    -- Main engine thrusts along the body up-axis: (-sin, cos).
    -- Side engine thrusts laterally in body frame: (cos, sin).
    ax = (-sinA) * mainThrust + cosA * sideThrust
    ayThrust = cosA * mainThrust + sinA * sideThrust
    ay = ayThrust - lunarLanderGravity
    newVx = lunarLanderVx state + ax * lunarLanderTau
    newVy = lunarLanderVy state + ay * lunarLanderTau
    newX = lunarLanderX state + newVx * lunarLanderTau
    yRaw = lunarLanderY state + newVy * lunarLanderTau
    newOmega = lunarLanderOmega state + angularImpulse * lunarLanderTau
    newAngle = lunarLanderAngle state + newOmega * lunarLanderTau
    touchingGround = yRaw <= 0.0
    yClamped = if touchingGround then 0.0 else yRaw
    -- impactVy keeps the pre-contact vertical velocity so the
    -- hard/soft landing classifier can see the actual approach
    -- speed; vyAfterContact zeroes it for the successor state so
    -- the lander doesn't sink through the pad on subsequent steps.
    impactVy = newVy
    vyAfterContact = if touchingGround then 0.0 else newVy
    leftContact = touchingGround && newAngle <= 0.05
    rightContact = touchingGround && newAngle >= -0.05
    next =
      LunarLanderState
        { lunarLanderX = newX
        , lunarLanderY = yClamped
        , lunarLanderVx = newVx
        , lunarLanderVy = vyAfterContact
        , lunarLanderAngle = newAngle
        , lunarLanderOmega = newOmega
        , lunarLanderLeftLegContact = leftContact
        , lunarLanderRightLegContact = rightContact
        }
    offPad = abs newX > lunarLanderOutOfBounds
    hardLanding =
      touchingGround
        && (abs impactVy > lunarLanderCrashSpeed || abs newAngle > lunarLanderUprightTolerance)
    softLanding =
      touchingGround
        && abs impactVy <= lunarLanderCrashSpeed
        && abs newAngle <= lunarLanderUprightTolerance
        && leftContact
        && rightContact
    done = offPad || hardLanding || softLanding
    -- Gym shaping: heading reward + velocity reward + angle reward +
    -- leg bonus + engine penalty.
    shaping =
      ((-100.0) * sqrt (newX * newX + (yClamped - lunarLanderInitialAltitude) ^ (2 :: Int)))
        - 100.0 * sqrt (newVx * newVx + vyAfterContact * vyAfterContact)
        - 100.0 * abs newAngle
        + 10.0 * boolToDouble leftContact
        + 10.0 * boolToDouble rightContact
    enginePenalty
      | action == 2 = -0.30
      | action == 1 || action == 3 = -0.03
      | otherwise = 0.0
    terminalReward
      | softLanding = 100.0
      | hardLanding = -100.0
      | offPad = -100.0
      | otherwise = 0.0
    reward = shaping + enginePenalty + terminalReward
   in
    SimStep next reward done

lunarLanderRenderFrame :: LunarLanderState -> RenderFrame
lunarLanderRenderFrame state =
  RenderFrame
    { renderObservation =
        [ lunarLanderX state
        , lunarLanderY state
        , lunarLanderVx state
        , lunarLanderVy state
        , lunarLanderAngle state
        , lunarLanderOmega state
        , boolToDouble (lunarLanderLeftLegContact state)
        , boolToDouble (lunarLanderRightLegContact state)
        ]
    , renderCaption =
        "lunar-lander x="
          <> showDouble (lunarLanderX state)
          <> " y="
          <> showDouble (lunarLanderY state)
          <> " angle="
          <> showDouble (lunarLanderAngle state)
    }

lunarLanderInitialAltitude
  , lunarLanderGravity
  , lunarLanderMainThrust
  , lunarLanderSideThrust
  , lunarLanderSideTorque
  , lunarLanderTau
  , lunarLanderCrashSpeed
  , lunarLanderUprightTolerance
  , lunarLanderOutOfBounds
    :: Double
lunarLanderInitialAltitude = 1.5
lunarLanderGravity = 1.62
lunarLanderMainThrust = 13.0
lunarLanderSideThrust = 1.0
lunarLanderSideTorque = 0.5
lunarLanderTau = 0.0167
lunarLanderCrashSpeed = 1.5
lunarLanderUprightTolerance = 0.4
lunarLanderOutOfBounds = 1.0

-- * Atari-subset deterministic stub

-- | Atari-subset state mirrors the Atari 2600 RAM-state observation
-- shape: a 128-byte buffer plus a step counter. This is *not* a real
-- Atari emulation — full ALE FFI plus per-game ROM licensing
-- handling is a much larger project tracked in the legacy ledger.
-- The deterministic-stub shape preserves the Atari action/obs
-- contract so upstream RL primitives (algorithm catalog, VecEnv) can
-- hook against it without code changes when the real ALE binding
-- lands.
data AtariSubsetState = AtariSubsetState
  { atariStep :: Int
  , atariRamHash :: Int
  }
  deriving stock (Eq, Show)

atariSubsetInitial :: AtariSubsetState
atariSubsetInitial = AtariSubsetState 0 1

atariSubsetEnvironment :: SimulatedEnvironment AtariSubsetState
atariSubsetEnvironment =
  SimulatedEnvironment
    { envName = "atari-subset"
    , envInitial = atariSubsetInitial
    , envStep = atariSubsetStep
    , envRenderFrame = atariSubsetRenderFrame
    , envActionCount = 18
    , envObservationSize = 128
    }

-- | Advance the deterministic stub by one tick. The RAM hash mixes the
-- previous hash with the action through a splitmix-style integer
-- update so two invocations with the same @(state, action)@ produce
-- bit-identical successors. Reward is the low byte of the RAM hash
-- divided by 256 so it stays in @[0.0, 1.0)@. The episode terminates
-- deterministically at @atariSubsetEpisodeLength@ steps.
atariSubsetStep :: AtariSubsetState -> Int -> SimStep AtariSubsetState
atariSubsetStep state action =
  let normalizedAction = action `mod` 18
      mixed =
        ( atariRamHash state * 6364136223846793005
            + fromIntegral (normalizedAction + 1) * 1442695040888963407
        )
          `mod` 4294967296
      stepNext = atariStep state + 1
      next = AtariSubsetState stepNext mixed
      done = stepNext >= atariSubsetEpisodeLength
      reward = fromIntegral (mixed `mod` 256) / 256.0
   in SimStep next reward done

atariSubsetRenderFrame :: AtariSubsetState -> RenderFrame
atariSubsetRenderFrame state =
  RenderFrame
    { renderObservation =
        let baseHash = atariRamHash state
            byteAt i =
              fromIntegral ((baseHash + i * 31) `mod` 256) / 255.0
         in fmap byteAt [0 .. 127]
    , renderCaption =
        "atari-subset step="
          <> Text.pack (show (atariStep state))
          <> " ram="
          <> Text.pack (show (atariRamHash state))
    }

atariSubsetEpisodeLength :: Int
atariSubsetEpisodeLength = 250

-- * Helpers

clamp :: Double -> Double -> Double -> Double
clamp value lower upper
  | value < lower = lower
  | value > upper = upper
  | otherwise = value

showDouble :: Double -> Text
showDouble = Text.pack . show

boolToDouble :: Bool -> Double
boolToDouble True = 1.0
boolToDouble False = 0.0
