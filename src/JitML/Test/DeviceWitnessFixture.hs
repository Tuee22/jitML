{-# LANGUAGE OverloadedStrings #-}

-- | A device execution witness for offline fixtures.
--
-- 'JitML.Product.DeviceWitness.witnessDeviceExecution' exposes no pure
-- constructor, so a suite that needs a completed ProductRow cannot conjure the
-- witness that completion now requires — it has to materialise an artifact on
-- disk and let the mint read and digest it. This module does exactly that and
-- nothing more.
--
-- It deliberately lives in the @JitML.Test@ namespace rather than beside the
-- witness type: production callers obtain a witness from the engine that just
-- executed ('JitML.Numerics.MlpDevice.mlpdExecutionWitness',
-- 'JitML.Numerics.LayerGraphDevice.layerGraphDeviceExecutionWitness'), and
-- nothing in the product path may reach for a fixture instead.
module JitML.Test.DeviceWitnessFixture
  ( fixtureDeviceExecutionWitness
  , fixtureDeviceExecutionWitnessFor
  , fixtureClassificationDeviceExecutionWitnessFor
  )
where

import Data.ByteString.Char8 qualified as ByteString.Char8
import Data.Text (Text)
import Data.Text qualified as Text
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)

import JitML.Product.DeviceWitness
  ( DeviceExecutionWitness
  , witnessDeviceExecution
  )
import JitML.Substrate (Substrate (..), renderSubstrate)

-- | A @linux-cpu@ fixture witness over a freshly written artifact.
fixtureDeviceExecutionWitness :: IO (Either Text DeviceExecutionWitness)
fixtureDeviceExecutionWitness =
  fixtureDeviceExecutionWitnessFor LinuxCPU

-- | A fixture witness for a chosen lane.
--
-- The artifact body is derived from the lane so two lanes never mint witnesses
-- with the same artifact digest; a suite comparing per-lane evidence therefore
-- sees distinct cells, as it would from real per-lane artifacts.
fixtureDeviceExecutionWitnessFor
  :: Substrate -> IO (Either Text DeviceExecutionWitness)
fixtureDeviceExecutionWitnessFor substrate =
  mintFixtureDeviceExecutionWitness
    substrate
    "jitml-fixture-artifact:"
    ( case substrate of
        AppleSilicon -> ("metal", ".metal.json", "jitml_kernel")
        LinuxCPU -> ("onednn", ".so", "jitml_matmul_forward")
        LinuxCUDA -> ("cuda", ".so", "jitml_cublas_sgemm")
    )

-- | A synthetic classification/layer-training fixture for a chosen lane.
-- The independent literal backend identities match that execution family.
-- Family and lane are explicit in the artifact body; no hardware or training
-- execution is claimed by minting this offline fixture.
fixtureClassificationDeviceExecutionWitnessFor
  :: Substrate -> IO (Either Text DeviceExecutionWitness)
fixtureClassificationDeviceExecutionWitnessFor substrate =
  mintFixtureDeviceExecutionWitness
    substrate
    "jitml-fixture-classification-artifact:"
    ( case substrate of
        AppleSilicon -> ("apple-metal-fixed-bridge", ".metal.json", "jitml_fixture_classification")
        LinuxCPU -> ("linux-cpu-onednn", ".so", "jitml_fixture_classification")
        LinuxCUDA -> ("linux-cuda-cudnn", ".so", "jitml_fixture_classification")
    )

mintFixtureDeviceExecutionWitness
  :: Substrate -> String -> (Text, FilePath, Text) -> IO (Either Text DeviceExecutionWitness)
mintFixtureDeviceExecutionWitness substrate artifactPrefix (backend, artifactExtension, executedIdentity) =
  withSystemTempDirectory "jitml-fixture-artifact" $ \dir -> do
    let artifact = dir </> "kernel" <> artifactExtension
    ByteString.Char8.writeFile
      artifact
      (ByteString.Char8.pack (artifactPrefix <> Text.unpack lane))
    witnessDeviceExecution
      substrate
      backend
      (Text.replicate 64 "0")
      artifact
      executedIdentity
 where
  lane = renderSubstrate substrate
