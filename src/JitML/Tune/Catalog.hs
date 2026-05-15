{-# LANGUAGE OverloadedStrings #-}

module JitML.Tune.Catalog
    ( Pruner (..)
    , Sampler (..)
    , Scheduler (..)
    , deterministicTrials
    , prunerCatalog
    , samplerCatalog
    , schedulerCatalog
    )
where

data Sampler
    = Sobol
    | Random
    | GeneticAlgorithm
    | EvolutionStrategies
    deriving stock (Eq, Show)

data Scheduler
    = Fifo
    | SuccessiveHalving
    | Hyperband
    | ASHA
    deriving stock (Eq, Show)

data Pruner
    = NoPruner
    | MedianPruner
    | PercentilePruner
    deriving stock (Eq, Show)

samplerCatalog :: [Sampler]
samplerCatalog = [Sobol, Random, GeneticAlgorithm, EvolutionStrategies]

schedulerCatalog :: [Scheduler]
schedulerCatalog = [Fifo, SuccessiveHalving, Hyperband, ASHA]

prunerCatalog :: [Pruner]
prunerCatalog = [NoPruner, MedianPruner, PercentilePruner]

deterministicTrials :: Sampler -> Int -> [Double]
deterministicTrials sampler count =
    take count $
        fmap normalize $
            iterate (\value -> (value * multiplier + 17) `mod` 10_000) (seed sampler)
  where
    multiplier =
        case sampler of
            Sobol -> 101
            Random -> 137
            GeneticAlgorithm -> 149
            EvolutionStrategies -> 163
    normalize value = fromIntegral value / 10_000

seed :: Sampler -> Int
seed Sobol = 11
seed Random = 23
seed GeneticAlgorithm = 37
seed EvolutionStrategies = 41
