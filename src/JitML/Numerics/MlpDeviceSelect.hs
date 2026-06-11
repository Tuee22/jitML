-- | Resolve the substrate-backed MLP device for a resolved 'Substrate'.
--
-- The per-backend modules ("JitML.Numerics.MlpCuda" /
-- "JitML.Numerics.MlpOneDnn" / "JitML.Numerics.MlpMetal") each supply an
-- @'Env' -> 'MlpDevice'@ builder that compiles the generated kernel through that
-- substrate's engine, @dlopen@s the artifact, and marshals the real
-- @jitml_mlp_*@ symbols (see "JitML.Numerics.MlpDevice"). This module is the
-- single DRY seam that maps the CLI-resolved @--substrate@ to the matching
-- builder so the SL classifier trainer (Sprint 8.10) and the RL trainers
-- (Sprint 8.11) route through the JIT engine on every substrate rather than the
-- pure-Haskell reference path.
--
-- It lives in its own module — not in "JitML.Numerics.MlpDevice" — because the
-- per-backend modules import @MlpDevice@, so selecting across them from inside
-- @MlpDevice@ would form an import cycle.
module JitML.Numerics.MlpDeviceSelect
  ( mlpDeviceForSubstrate
  , rlDeviceForSubstrate
  )
where

import JitML.Env.Env (Env)
import JitML.Numerics.MlpCuda (cudaMlpDevice)
import JitML.Numerics.MlpDevice (MlpDevice)
import JitML.Numerics.MlpMetal (metalMlpDevice)
import JitML.Numerics.MlpOneDnn (oneDnnMlpDevice)
import JitML.Substrate (Substrate (..))

-- | Select the substrate's JIT-compiled MLP device. @apple-silicon@ runs the
-- Metal kernel on the host GPU, @linux-cpu@ the oneDNN kernel, @linux-cuda@ the
-- CUDA kernel; each fails closed at the engine boundary (returns @Left@) when its
-- toolchain/hardware is absent, so there is no silent degradation to a
-- non-substrate path.
mlpDeviceForSubstrate :: Substrate -> Env -> MlpDevice
mlpDeviceForSubstrate AppleSilicon = metalMlpDevice
mlpDeviceForSubstrate LinuxCPU = oneDnnMlpDevice
mlpDeviceForSubstrate LinuxCUDA = cudaMlpDevice

-- | Sprint 8.11 — the single DRY seam the RL worker dispatch
-- ('JitML.App.runTrainerEpisodes') routes every MLP-backed trainer through.
-- It resolves to the same JIT-compiled device as 'mlpDeviceForSubstrate':
-- the 13 MLP-backed RL algorithms (PPO/A2C/TRPO/MaskablePPO/RecurrentPPO,
-- DQN/QR-DQN, DDPG/TD3/SAC/CrossQ/TQC, HER) share one device per substrate.
-- ARS is the lone no-MLP exception — it is a finite-difference random-search
-- method with no network forward/backward, so it never consumes this seam.
rlDeviceForSubstrate :: Substrate -> Env -> MlpDevice
rlDeviceForSubstrate = mlpDeviceForSubstrate
