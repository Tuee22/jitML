module JitML.RL.AlphaZero.Arena
  ( ArenaConfig (..)
  , ArenaOutcome (..)
  , candidateShouldBePromoted
  , defaultArenaConfig
  , playArena
  )
where

import JitML.RL.AlphaZero (ArenaSummary (..), arenaWinRate)

data ArenaConfig = ArenaConfig
  { arenaGames :: Int
  , arenaPromotionThreshold :: Double
  , arenaSeed :: Int
  }
  deriving stock (Eq, Show)

defaultArenaConfig :: ArenaConfig
defaultArenaConfig =
  ArenaConfig
    { arenaGames = 40
    , arenaPromotionThreshold = 0.55
    , arenaSeed = 12345
    }

data ArenaOutcome = ArenaOutcome
  { arenaSummary :: ArenaSummary
  , arenaPromoted :: Bool
  }
  deriving stock (Eq, Show)

-- | Deterministic arena driver: alternates the side the candidate plays each
-- game and computes a fixed seed-derived result. Replace with a real network
-- evaluation when the engine layer can execute the network.
playArena :: ArenaConfig -> ArenaOutcome
playArena config =
  let outcomes =
        [ outcomeFor (arenaSeed config + gameId)
        | gameId <- [0 .. arenaGames config - 1]
        ]
      candidateWins = length [() | Just True <- outcomes]
      referenceWins = length [() | Just False <- outcomes]
      draws = length [() | Nothing <- outcomes]
      summary =
        ArenaSummary
          { arenaCandidateWins = candidateWins
          , arenaReferenceWins = referenceWins
          , arenaDraws = draws
          }
   in ArenaOutcome
        { arenaSummary = summary
        , arenaPromoted = candidateShouldBePromoted config summary
        }

candidateShouldBePromoted :: ArenaConfig -> ArenaSummary -> Bool
candidateShouldBePromoted config summary =
  arenaWinRate summary >= arenaPromotionThreshold config

outcomeFor :: Int -> Maybe Bool
outcomeFor seed =
  case (seed * 1103515245 + 12345) `mod` 12 of
    n | n < 7 -> Just True
    n | n < 10 -> Just False
    _ -> Nothing
