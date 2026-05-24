{-# LANGUAGE OverloadedStrings #-}

-- | Pure-Haskell classical-control simulator bindings used by the RL
-- canonical stanza ahead of the live env runtime owned by Phase 13.
-- Provides typed initial / step boundaries for the canonical
-- @cartpole@ (CartPole-v1) and @mountain-car@ (MountainCar-v0)
-- environments plus a deterministic render-frame projection. Box2D
-- @lunar-lander@ and ALE @atari-subset@ bindings remain target work
-- once their C libraries are baked into @jitml:local@.
module JitML.RL.Simulator
  ( CartPoleState (..)
  , MountainCarState (..)
  , RenderFrame (..)
  , SimStep (..)
  , SimulatedEnvironment (..)
  , cartPoleEnvironment
  , cartPoleInitial
  , cartPoleRenderFrame
  , cartPoleStep
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

-- * Helpers

clamp :: Double -> Double -> Double -> Double
clamp value lower upper
  | value < lower = lower
  | value > upper = upper
  | otherwise = value

showDouble :: Double -> Text
showDouble = Text.pack . show
