{-# LANGUAGE OverloadedStrings #-}

module JitML.Engines.CpuFeatures
  ( CpuFeatures (..)
  , detectCpuFeatures
  , microKernelChoice
  )
where

import Control.Exception qualified
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import System.Exit (ExitCode (..))

import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (subprocess)

-- | Detected CPU feature flags relevant to the oneDNN micro-kernel knob.
-- The reader maps onto `JitML.Engines.Tuning.linuxCpuKnobs`'s
-- `micro-kernel` axis: AVX-512 capable hosts pick
-- `onednn-jit-avx512`; AVX2 falls back to `onednn-jit-avx2`; neither falls
-- through to `onednn-reference` (correct but slow).
data CpuFeatures = CpuFeatures
  { cpuHasAvx2 :: Bool
  , cpuHasAvx512 :: Bool
  , cpuVendor :: Text
  }
  deriving stock (Eq, Show)

-- | Detect CPU features through OS-native probes. Apple Silicon hosts have
-- neither AVX2 nor AVX-512 (they're ARM NEON). Linux hosts query
-- `/proc/cpuinfo`; Darwin hosts query `sysctl -a` for `hw.optional.avx*`.
-- Both probes flow through the typed `Subprocess` boundary so the lint
-- stack's "forbidden subprocess primitive" check stays satisfied.
detectCpuFeatures :: IO CpuFeatures
detectCpuFeatures = do
  detectDarwin <- tryDarwinSysctl
  case detectDarwin of
    Just features -> pure features
    Nothing -> do
      detectLinux <- tryLinuxCpuinfo
      case detectLinux of
        Just features -> pure features
        Nothing ->
          pure
            CpuFeatures {cpuHasAvx2 = False, cpuHasAvx512 = False, cpuVendor = "unknown"}

-- | Best micro-kernel knob name for the detected feature set. Returned value
-- is one of `JitML.Engines.Tuning.linuxCpuKnobs`'s `micro-kernel` axis
-- choices.
microKernelChoice :: CpuFeatures -> Text
microKernelChoice features
  | cpuHasAvx512 features = "onednn-jit-avx512"
  | cpuHasAvx2 features = "onednn-jit-avx2"
  | otherwise = "onednn-reference"

tryDarwinSysctl :: IO (Maybe CpuFeatures)
tryDarwinSysctl =
  (Just <$> probeDarwin)
    `Control.Exception.catch` \(_ :: Control.Exception.SomeException) -> pure Nothing
 where
  probeDarwin = do
    (exitCode, stdoutText, _) <-
      runStreaming defaultSubprocessEnv (subprocess "sysctl" ["-a"])
    case exitCode of
      ExitFailure _ ->
        Control.Exception.throwIO (userError "sysctl probe failed")
      ExitSuccess ->
        let avx2 = "hw.optional.avx2_0: 1" `Text.isInfixOf` stdoutText
            avx512 = "hw.optional.avx512f: 1" `Text.isInfixOf` stdoutText
            vendor =
              if "machdep.cpu.brand_string" `Text.isInfixOf` stdoutText
                && ("Apple" `Text.isInfixOf` stdoutText)
                then "apple-silicon"
                else "intel-or-amd"
         in pure CpuFeatures {cpuHasAvx2 = avx2, cpuHasAvx512 = avx512, cpuVendor = vendor}

tryLinuxCpuinfo :: IO (Maybe CpuFeatures)
tryLinuxCpuinfo =
  (Just <$> probeLinux)
    `Control.Exception.catch` \(_ :: Control.Exception.SomeException) -> pure Nothing
 where
  probeLinux = do
    text <- Text.IO.readFile "/proc/cpuinfo"
    pure
      CpuFeatures
        { cpuHasAvx2 = " avx2" `Text.isInfixOf` text
        , cpuHasAvx512 = " avx512f" `Text.isInfixOf` text
        , cpuVendor =
            if "GenuineIntel" `Text.isInfixOf` text
              then "intel"
              else
                if "AuthenticAMD" `Text.isInfixOf` text
                  then "amd"
                  else "unknown"
        }
