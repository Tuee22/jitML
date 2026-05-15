{-# LANGUAGE OverloadedStrings #-}

module JitML.Substrate
    ( Substrate (..)
    , allSubstrates
    , parseSubstrate
    , renderSubstrate
    , substrateClusterName
    , substrateEdgePort
    , substrateRuntimeClass
    )
where

import Data.Text (Text)

data Substrate
    = AppleSilicon
    | LinuxCPU
    | LinuxCUDA
    deriving stock (Bounded, Enum, Eq, Ord, Show)

allSubstrates :: [Substrate]
allSubstrates = [minBound .. maxBound]

renderSubstrate :: Substrate -> Text
renderSubstrate AppleSilicon = "apple-silicon"
renderSubstrate LinuxCPU = "linux-cpu"
renderSubstrate LinuxCUDA = "linux-cuda"

parseSubstrate :: Text -> Maybe Substrate
parseSubstrate "apple-silicon" = Just AppleSilicon
parseSubstrate "linux-cpu" = Just LinuxCPU
parseSubstrate "linux-cuda" = Just LinuxCUDA
parseSubstrate _ = Nothing

substrateClusterName :: Substrate -> Text
substrateClusterName substrate = "jitml-" <> renderSubstrate substrate

substrateEdgePort :: Substrate -> Int
substrateEdgePort AppleSilicon = 9090
substrateEdgePort LinuxCPU = 9091
substrateEdgePort LinuxCUDA = 9092

substrateRuntimeClass :: Substrate -> Maybe Text
substrateRuntimeClass LinuxCUDA = Just "nvidia"
substrateRuntimeClass _ = Nothing
