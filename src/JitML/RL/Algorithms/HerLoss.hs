-- | Sprint 13.8 — real HER relabeling math (Andrychowicz et al. 2017,
-- "Hindsight Experience Replay").
--
-- HER is a sample-efficiency wrapper around any off-policy algorithm
-- (DDPG, TD3, SAC). Given a goal-conditioned environment with a
-- sparse reward, HER:
--
--   1. Stores the original transition @(s, a, r, s', g)@.
--   2. Relabels the goal to one achieved later in the same episode
--      and recomputes the reward against the relabeled goal.
--   3. Adds the relabeled transition to the replay buffer.
--
-- The HER-specific math here is the @future@ goal-sampling strategy
-- and the reward recomputation against the relabeled goal. The
-- underlying critic / actor losses come from the wrapped off-policy
-- algorithm.
module JitML.RL.Algorithms.HerLoss
  ( HerStrategy (..)
  , RelabeledTransition (..)
  , herRelabel
  , sparseGoalReward
  )
where

-- | Goal-relabeling strategy. @Future@ samples a goal from the same
-- trajectory occurring after the current step; @Episode@ samples
-- uniformly from the trajectory; @Random@ samples from a buffer of
-- previously-achieved goals (the caller supplies the candidate goal
-- pool).
data HerStrategy
  = HerFuture
  | HerEpisode
  | HerRandom
  deriving stock (Eq, Show)

data RelabeledTransition state goal = RelabeledTransition
  { relState :: state
  , relAction :: Int
  , relNextState :: state
  , relRelabeledGoal :: goal
  , relRelabeledReward :: Double
  , relTerminal :: Bool
  }
  deriving stock (Eq, Show)

-- | Canonical sparse goal-conditioned reward: @0@ if the next-state
-- distance to the goal is within @epsilon@, @-1@ otherwise.
sparseGoalReward
  :: (state -> goal -> Double)
  -- ^ goal-distance function
  -> Double
  -- ^ epsilon (success threshold)
  -> state
  -> goal
  -> Double
sparseGoalReward distance epsilon nextState goal
  | distance nextState goal <= epsilon = 0.0
  | otherwise = -1.0

-- | Relabel one transition against a freshly-sampled goal under the
-- chosen strategy. The deterministic-test path passes the chosen goal
-- in; the live path picks it from the trajectory (Future / Episode)
-- or from the buffer pool (Random) via a typed RNG.
herRelabel
  :: (state -> goal -> Double)
  -- ^ goal-distance function
  -> Double
  -- ^ success epsilon
  -> goal
  -- ^ caller-chosen relabeled goal
  -> (state, Int, state, Bool)
  -- ^ @(s, a, s', terminal)@ from the original transition
  -> RelabeledTransition state goal
herRelabel distance epsilon newGoal (s, a, s', terminal) =
  RelabeledTransition
    { relState = s
    , relAction = a
    , relNextState = s'
    , relRelabeledGoal = newGoal
    , relRelabeledReward = sparseGoalReward distance epsilon s' newGoal
    , relTerminal = terminal
    }
