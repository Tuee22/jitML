{-# LANGUAGE OverloadedStrings #-}

-- | Pure-Haskell simulator bindings used by the RL canonical stanza
-- ahead of the live env runtime owned by Phase 13. Provides typed
-- initial / step boundaries for the canonical @cartpole@
-- (CartPole-v1), @mountain-car@ (MountainCar-v0), @lunar-lander@
-- (LunarLander-v2, simplified rigid-body port of the Gym Box2D
-- reference), and @key-door-grid@ (jitML-owned visual discrete control)
-- environments plus a deterministic render-frame projection.
--
-- The lunar-lander port is a pure-Haskell rigid-body simulation in
-- the style of OpenAI Gym's @lunar_lander.py@ but written from the
-- documented equations rather than depending on Box2D — bit-for-bit
-- equivalence with Box2D is explicitly *not* a goal; same-substrate,
-- same-seed reproducibility is. Atari 2600 execution is owned by
-- "JitML.RL.ALE" so ROM bytes remain explicit and uncommitted.
module JitML.RL.Simulator
  ( CartPoleState (..)
  , ContinuousEnvironment (..)
  , ContinuousSimStep (..)
  , KeyDoorGridAction (..)
  , KeyDoorGridPosition (..)
  , KeyDoorGridState (..)
  , LunarLanderState (..)
  , MountainCarState (..)
  , PendulumState (..)
  , RenderFrame (..)
  , SimStep (..)
  , SimulatedEnvironment (..)
  , cartPoleEnvironment
  , cartPoleInitial
  , cartPoleRenderFrame
  , cartPoleStep
  , keyDoorGridEnvironment
  , keyDoorGridInitial
  , keyDoorGridLegalActionMask
  , keyDoorGridObservation
  , keyDoorGridRenderFrame
  , keyDoorGridStep
  , lunarLanderEnvironment
  , lunarLanderInitial
  , lunarLanderRenderFrame
  , lunarLanderStep
  , mountainCarEnvironment
  , mountainCarInitial
  , mountainCarRenderFrame
  , mountainCarStep
  , pendulumEnvironment
  , pendulumInitial
  , pendulumObservation
  , pendulumStep
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

-- * Pendulum-v1 (continuous action)

-- | Result of advancing one continuous-action simulator state by one
-- real-valued action. Mirrors 'SimStep' but for the continuous-control
-- env-step boundary the actor-critic catalog (DDPG / TD3 / SAC / CrossQ
-- / TQC) consumes.
data ContinuousSimStep state = ContinuousSimStep
  { cStepState :: state
  , cStepReward :: Double
  , cStepDone :: Bool
  }
  deriving stock (Eq, Show)

-- | The continuous-action env-step boundary. The action is a scalar
-- torque in @[cEnvActionLow, cEnvActionHigh]@; the observation is the
-- @cEnvObservationSize@-wide vector the policy/critic networks consume.
data ContinuousEnvironment state = ContinuousEnvironment
  { cEnvName :: Text
  , cEnvInitial :: state
  , cEnvStep :: state -> Double -> ContinuousSimStep state
  , cEnvObservation :: state -> [Double]
  , cEnvActionLow :: Double
  , cEnvActionHigh :: Double
  , cEnvObservationSize :: Int
  }

-- | Pendulum-v1 state: pole angle @theta@ (radians, 0 = upright) and
-- angular velocity @thetadot@ (rad/s). The canonical Gym observation is
-- the angle projected to @(cos theta, sin theta)@ plus @thetadot@.
data PendulumState = PendulumState
  { pendTheta :: Double
  , pendThetaDot :: Double
  }
  deriving stock (Eq, Show)

-- | Canonical deterministic reset: the pendulum hangs straight down
-- (@theta = pi@) at rest. The Gym env randomises the reset; the
-- determinism contract here prefers a fixed start so same-seed trainer
-- runs are bit-reproducible (exploration noise comes from the trainer's
-- seeded RNG, not env-internal stochasticity).
pendulumInitial :: PendulumState
pendulumInitial = PendulumState pi 0.0

pendulumEnvironment :: ContinuousEnvironment PendulumState
pendulumEnvironment =
  ContinuousEnvironment
    { cEnvName = "pendulum"
    , cEnvInitial = pendulumInitial
    , cEnvStep = pendulumStep
    , cEnvObservation = pendulumObservation
    , cEnvActionLow = -pendulumMaxTorque
    , cEnvActionHigh = pendulumMaxTorque
    , cEnvObservationSize = 3
    }

-- | Advance the pendulum one Gym timestep under a continuous torque.
-- Dynamics follow the documented @Pendulum-v1@ equations:
--
-- @newthdot = thetadot + (3*g/(2*l) * sin theta + 3/(m*l^2) * u) * dt@
--
-- clamped to @[-maxSpeed, maxSpeed]@, then @newtheta = theta + newthdot
-- * dt@. The reward is the negated cost
-- @-(angle_normalize(theta)^2 + 0.1*thetadot^2 + 0.001*u^2)@ (computed
-- from the /pre-step/ angle and the applied torque, per the Gym
-- reference). The episode never self-terminates; the trainer caps the
-- horizon.
pendulumStep :: PendulumState -> Double -> ContinuousSimStep PendulumState
pendulumStep state actionRaw =
  let u = clamp actionRaw (-pendulumMaxTorque) pendulumMaxTorque
      theta = pendTheta state
      thetadot = pendThetaDot state
      cost =
        angleNormalize theta * angleNormalize theta
          + 0.1 * thetadot * thetadot
          + 0.001 * u * u
      newThetaDotRaw =
        thetadot
          + ( 3.0 * pendulumGravity / (2.0 * pendulumLength) * sin theta
                + 3.0 / (pendulumMass * pendulumLength * pendulumLength) * u
            )
            * pendulumDt
      newThetaDot = clamp newThetaDotRaw (-pendulumMaxSpeed) pendulumMaxSpeed
      newTheta = theta + newThetaDot * pendulumDt
   in ContinuousSimStep
        { cStepState = PendulumState newTheta newThetaDot
        , cStepReward = negate cost
        , cStepDone = False
        }

pendulumObservation :: PendulumState -> [Double]
pendulumObservation state =
  [ cos (pendTheta state)
  , sin (pendTheta state)
  , pendThetaDot state
  ]

pendulumGravity
  , pendulumMass
  , pendulumLength
  , pendulumMaxSpeed
  , pendulumMaxTorque
  , pendulumDt
    :: Double
pendulumGravity = 10.0
pendulumMass = 1.0
pendulumLength = 1.0
pendulumMaxSpeed = 8.0
pendulumMaxTorque = 2.0
pendulumDt = 0.05

-- | Normalise an angle to @[-pi, pi)@.
angleNormalize :: Double -> Double
angleNormalize x =
  let twoPi = 2.0 * pi
   in x - twoPi * fromIntegral (floor ((x + pi) / twoPi) :: Int)

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

-- * KeyDoorGrid-v0

-- | A cell coordinate in the deterministic 5x5 KeyDoorGrid map.
data KeyDoorGridPosition = KeyDoorGridPosition
  { keyDoorGridRow :: Int
  , keyDoorGridCol :: Int
  }
  deriving stock (Eq, Show)

-- | Discrete action surface for KeyDoorGrid-v0.
data KeyDoorGridAction
  = KeyDoorGridNorth
  | KeyDoorGridSouth
  | KeyDoorGridWest
  | KeyDoorGridEast
  | KeyDoorGridPickUpKey
  | KeyDoorGridOpenDoor
  deriving stock (Bounded, Enum, Eq, Show)

-- | Native jitML visual discrete-control state. The seed determines the key
-- location and wall rotation while preserving a solvable corridor through key,
-- door, and goal.
data KeyDoorGridState = KeyDoorGridState
  { keyDoorGridSeed :: Int
  , keyDoorGridAgent :: KeyDoorGridPosition
  , keyDoorGridKey :: KeyDoorGridPosition
  , keyDoorGridDoor :: KeyDoorGridPosition
  , keyDoorGridGoal :: KeyDoorGridPosition
  , keyDoorGridWalls :: [KeyDoorGridPosition]
  , keyDoorGridHasKey :: Bool
  , keyDoorGridDoorOpen :: Bool
  , keyDoorGridStepCount :: Int
  }
  deriving stock (Eq, Show)

keyDoorGridEnvironment :: SimulatedEnvironment KeyDoorGridState
keyDoorGridEnvironment =
  SimulatedEnvironment
    { envName = "key-door-grid"
    , envInitial = keyDoorGridInitial 0
    , envStep = keyDoorGridStep
    , envRenderFrame = keyDoorGridRenderFrame
    , envActionCount = keyDoorGridActionCount
    , envObservationSize = keyDoorGridObservationSize
    }

keyDoorGridInitial :: Int -> KeyDoorGridState
keyDoorGridInitial seed =
  KeyDoorGridState
    { keyDoorGridSeed = seed
    , keyDoorGridAgent = KeyDoorGridPosition 0 0
    , keyDoorGridKey = keyPosition
    , keyDoorGridDoor = KeyDoorGridPosition 3 4
    , keyDoorGridGoal = KeyDoorGridPosition 4 4
    , keyDoorGridWalls = take 3 (rotateList (abs seed) wallCandidates)
    , keyDoorGridHasKey = False
    , keyDoorGridDoorOpen = False
    , keyDoorGridStepCount = 0
    }
 where
  keyPosition = keyCandidates !! (abs seed `mod` length keyCandidates)

keyDoorGridLegalActionMask :: KeyDoorGridState -> [Bool]
keyDoorGridLegalActionMask state =
  [ canMove KeyDoorGridNorth
  , canMove KeyDoorGridSouth
  , canMove KeyDoorGridWest
  , canMove KeyDoorGridEast
  , keyDoorGridAgent state == keyDoorGridKey state && not (keyDoorGridHasKey state)
  , keyDoorGridHasKey state
      && not (keyDoorGridDoorOpen state)
      && adjacent (keyDoorGridAgent state) (keyDoorGridDoor state)
  ]
 where
  canMove action =
    case moveTarget action (keyDoorGridAgent state) of
      Nothing -> False
      Just pos -> keyDoorGridCanEnter state pos

keyDoorGridStep :: KeyDoorGridState -> Int -> SimStep KeyDoorGridState
keyDoorGridStep state rawAction =
  case keyDoorGridActionFromInt rawAction of
    Nothing -> invalidStep
    Just action ->
      if not (keyDoorGridLegalActionMask state !! fromEnum action)
        then invalidStep
        else applyAction action
 where
  nextStepCount = keyDoorGridStepCount state + 1
  withTick next = next {keyDoorGridStepCount = nextStepCount}
  doneFor next =
    nextStepCount >= keyDoorGridMaxSteps
      || ( keyDoorGridAgent next == keyDoorGridGoal next
             && keyDoorGridHasKey next
             && keyDoorGridDoorOpen next
         )
  invalidStep =
    let next = withTick state
     in SimStep next (-0.05) (doneFor next)
  applyAction KeyDoorGridPickUpKey =
    let next = withTick state {keyDoorGridHasKey = True}
     in SimStep next 0.20 (doneFor next)
  applyAction KeyDoorGridOpenDoor =
    let next = withTick state {keyDoorGridDoorOpen = True}
     in SimStep next 0.30 (doneFor next)
  applyAction action =
    case moveTarget action (keyDoorGridAgent state) of
      Nothing -> invalidStep
      Just pos ->
        let next = withTick state {keyDoorGridAgent = pos}
            reachedGoal =
              pos == keyDoorGridGoal state
                && keyDoorGridHasKey state
                && keyDoorGridDoorOpen state
            reward = if reachedGoal then 1.0 else -0.01
         in SimStep next reward (doneFor next)

keyDoorGridObservation :: KeyDoorGridState -> [Double]
keyDoorGridObservation state =
  concatMap channelsFor gridPositions
    <> [ boolToDouble (keyDoorGridHasKey state)
       , boolToDouble (keyDoorGridDoorOpen state)
       ]
 where
  channelsFor pos =
    [ boolToDouble (pos `elem` keyDoorGridWalls state)
    , boolToDouble (pos == keyDoorGridKey state && not (keyDoorGridHasKey state))
    , boolToDouble (pos == keyDoorGridDoor state && not (keyDoorGridDoorOpen state))
    , boolToDouble (pos == keyDoorGridGoal state)
    , boolToDouble (pos == keyDoorGridAgent state)
    ]

keyDoorGridRenderFrame :: KeyDoorGridState -> RenderFrame
keyDoorGridRenderFrame state =
  RenderFrame
    { renderObservation = keyDoorGridObservation state
    , renderCaption =
        Text.unlines
          ( [ "key-door-grid step="
                <> Text.pack (show (keyDoorGridStepCount state))
                <> " key="
                <> (if keyDoorGridHasKey state then "carried" else "free")
                <> " door="
                <> (if keyDoorGridDoorOpen state then "open" else "locked")
            ]
              <> [ Text.pack [cellChar (KeyDoorGridPosition row col) | col <- [0 .. keyDoorGridWidth - 1]]
                 | row <- [0 .. keyDoorGridHeight - 1]
                 ]
          )
    }
 where
  cellChar pos
    | pos == keyDoorGridAgent state = '@'
    | pos `elem` keyDoorGridWalls state = '#'
    | pos == keyDoorGridKey state && not (keyDoorGridHasKey state) = 'k'
    | pos == keyDoorGridDoor state && keyDoorGridDoorOpen state = 'd'
    | pos == keyDoorGridDoor state = 'D'
    | pos == keyDoorGridGoal state = 'G'
    | otherwise = '.'

keyDoorGridCanEnter :: KeyDoorGridState -> KeyDoorGridPosition -> Bool
keyDoorGridCanEnter state pos =
  inGrid pos
    && pos `notElem` keyDoorGridWalls state
    && (pos /= keyDoorGridDoor state || keyDoorGridDoorOpen state)

keyDoorGridActionFromInt :: Int -> Maybe KeyDoorGridAction
keyDoorGridActionFromInt raw
  | raw < 0 || raw >= keyDoorGridActionCount = Nothing
  | otherwise = Just (toEnum raw)

moveTarget :: KeyDoorGridAction -> KeyDoorGridPosition -> Maybe KeyDoorGridPosition
moveTarget action (KeyDoorGridPosition row col) =
  case action of
    KeyDoorGridNorth -> Just (KeyDoorGridPosition (row - 1) col)
    KeyDoorGridSouth -> Just (KeyDoorGridPosition (row + 1) col)
    KeyDoorGridWest -> Just (KeyDoorGridPosition row (col - 1))
    KeyDoorGridEast -> Just (KeyDoorGridPosition row (col + 1))
    KeyDoorGridPickUpKey -> Nothing
    KeyDoorGridOpenDoor -> Nothing

adjacent :: KeyDoorGridPosition -> KeyDoorGridPosition -> Bool
adjacent (KeyDoorGridPosition aRow aCol) (KeyDoorGridPosition bRow bCol) =
  abs (aRow - bRow) + abs (aCol - bCol) == 1

inGrid :: KeyDoorGridPosition -> Bool
inGrid (KeyDoorGridPosition row col) =
  row >= 0 && row < keyDoorGridHeight && col >= 0 && col < keyDoorGridWidth

rotateList :: Int -> [a] -> [a]
rotateList _ [] = []
rotateList n xs =
  let k = n `mod` length xs
   in drop k xs <> take k xs

gridPositions :: [KeyDoorGridPosition]
gridPositions =
  [ KeyDoorGridPosition row col
  | row <- [0 .. keyDoorGridHeight - 1]
  , col <- [0 .. keyDoorGridWidth - 1]
  ]

keyCandidates :: [KeyDoorGridPosition]
keyCandidates =
  [ KeyDoorGridPosition 0 2
  , KeyDoorGridPosition 1 4
  , KeyDoorGridPosition 2 0
  , KeyDoorGridPosition 3 1
  , KeyDoorGridPosition 2 3
  ]

wallCandidates :: [KeyDoorGridPosition]
wallCandidates =
  [ KeyDoorGridPosition 1 1
  , KeyDoorGridPosition 1 3
  , KeyDoorGridPosition 2 2
  , KeyDoorGridPosition 3 2
  ]

keyDoorGridWidth, keyDoorGridHeight, keyDoorGridActionCount, keyDoorGridMaxSteps :: Int
keyDoorGridWidth = 5
keyDoorGridHeight = 5
keyDoorGridActionCount = 6
keyDoorGridMaxSteps = 64

keyDoorGridObservationSize :: Int
keyDoorGridObservationSize = keyDoorGridWidth * keyDoorGridHeight * 5 + 2
