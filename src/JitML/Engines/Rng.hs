{-# LANGUAGE NumericUnderscores #-}

module JitML.Engines.Rng
  ( SplitMixSeed (..)
  , deriveSplitMixSeed
  , splitMixNext
  , splitMixUnitDouble
  , splitMixWords
  )
where

import Data.Bits (shiftR, xor)
import Data.Word (Word64)

newtype SplitMixSeed = SplitMixSeed
  { unSplitMixSeed :: Word64
  }
  deriving stock (Eq, Ord, Show)

splitMixNext :: SplitMixSeed -> (Word64, SplitMixSeed)
splitMixNext (SplitMixSeed state) =
  let nextState = state + splitMixGamma
   in (mix64 nextState, SplitMixSeed nextState)

splitMixWords :: Int -> SplitMixSeed -> [Word64]
splitMixWords count seed
  | count <= 0 = []
  | otherwise =
      let (word, nextSeed) = splitMixNext seed
       in word : splitMixWords (count - 1) nextSeed

deriveSplitMixSeed :: SplitMixSeed -> Word64 -> SplitMixSeed
deriveSplitMixSeed (SplitMixSeed masterSeed) streamIndex =
  SplitMixSeed $
    fst $
      splitMixNext $
        SplitMixSeed (masterSeed + streamIndex * splitMixGamma)

splitMixUnitDouble :: Word64 -> Double
splitMixUnitDouble word =
  fromIntegral (word `shiftR` 11) * (1.0 / 9_007_199_254_740_992.0)

mix64 :: Word64 -> Word64
mix64 value =
  let first = (value `xor` (value `shiftR` 30)) * 0xBF58_476D_1CE4_E5B9
      second = (first `xor` (first `shiftR` 27)) * 0x94D0_49BB_1331_11EB
   in second `xor` (second `shiftR` 31)

splitMixGamma :: Word64
splitMixGamma = 0x9E37_79B9_7F4A_7C15
