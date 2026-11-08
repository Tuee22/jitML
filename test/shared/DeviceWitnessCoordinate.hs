{-# LANGUAGE OverloadedStrings #-}

-- | Real selected-lane compiler/cache/loader regression. Three separate helper
-- processes execute an MLP: A and B share one artifact from different working
-- directories, while C compiles into an independent cache. This is device and
-- artifact-coordinate evidence, never training or convergence qualification.
module DeviceWitnessCoordinate
  ( deviceWitnessCoordinateTest
  , runDeviceWitnessCoordinateWorker
  )
where

import Codec.Serialise (deserialiseOrFail, serialise)
import Data.Bifunctor qualified as Bifunctor
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import System.Directory
  ( canonicalizePath
  , createDirectoryIfMissing
  , doesFileExist
  , getCurrentDirectory
  , getModificationTime
  )
import System.Environment (getExecutablePath)
import System.FilePath (isAbsolute, isRelative, (</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Timeout (timeout)
import Test.Tasty (TestTree)
import Test.Tasty.HUnit (assertBool, assertEqual, assertFailure, testCase, (@?=))

import JitML.CLI.Output (writeLineIO)
import JitML.Engines.Engine qualified as Engine
import JitML.Engines.Loader qualified as Loader
import JitML.Engines.MetalBridge qualified as MetalBridge
import JitML.Env.Build (GlobalFlags (..), buildEnv, defaultGlobalFlags)
import JitML.Numerics.Mlp qualified as Mlp
import JitML.Numerics.MlpCuda qualified as MlpCuda
import JitML.Numerics.MlpDevice qualified as MlpDevice
import JitML.Numerics.MlpDeviceSelect qualified as MlpDeviceSelect
import JitML.Numerics.MlpMetal qualified as MlpMetal
import JitML.Numerics.MlpOneDnn qualified as MlpOneDnn
import JitML.Product.DeviceWitness qualified as Witness
import JitML.Sub.Outcome (ProcessOutcome (..), ProcessTranscript (..), renderProcessFailure)
import JitML.Sub.Stream
  ( SubprocessEnv
  , defaultSubprocessEnv
  , runStreaming
  , subprocessEnvOverrideAndRemove
  )
import JitML.Sub.Subprocess (Subprocess (..), subprocess)
import JitML.Substrate (Substrate (..), parseSubstrate, renderSubstrate)

type WorkerData = (Witness.RawDeviceExecutionWitness, Text, Bool)

deviceWitnessCoordinateTest :: Substrate -> TestTree
deviceWitnessCoordinateTest substrate =
  testCase
    ( Text.unpack (renderSubstrate substrate)
        <> " MLP witness coordinates survive three real processes and different working directories"
    )
    $ withSystemTempDirectory "jitml-device-witness-coordinate"
    $ \temporaryRoot -> do
      root <- canonicalizePath temporaryRoot
      executable <- getExecutablePath >>= canonicalizePath
      environment <- workerEnvironment substrate
      let sharedCache = root </> "shared cache"
          independentCache = root </> "independent cache"
          workdirB = root </> "working-directory-b"
          workdirC = root </> "working-directory-c"
      createDirectoryIfMissing True workdirB
      createDirectoryIfMissing True workdirC
      (rawA, loaderPathA, compiledA) <-
        runWorker environment executable substrate "a" root sharedCache root
      assertBool "A compiled a fresh real artifact" compiledA
      assertBool "A's loader coordinate is caller-relative" (isRelative (Text.unpack loaderPathA))
      witnessA <- expectRight (Witness.refineRawDeviceExecutionWitness rawA)
      let artifactPath = Text.unpack (Witness.witnessArtifactPath witnessA)
      assertBool "the minted coordinate is absolute" (isAbsolute artifactPath)
      canonicalizePath artifactPath >>= (@?= artifactPath)
      artifactBytes <- ByteString.readFile artifactPath
      assertBool "the real artifact is nonempty" (not (ByteString.null artifactBytes))
      artifactTime <- getModificationTime artifactPath
      (rawB, loaderPathB, compiledB) <-
        runWorker environment executable substrate "b" root sharedCache workdirB
      assertBool "B reused A's artifact" (not compiledB)
      assertBool "the two callers receive distinct loader spellings" (loaderPathA /= loaderPathB)
      assertSixFields rawA rawB
      Witness.refineRawDeviceExecutionWitness rawB @?= Right witnessA
      ByteString.readFile artifactPath >>= (@?= artifactBytes)
      getModificationTime artifactPath >>= (@?= artifactTime)
      -- Separate compiler invocations need not produce identical ELF bytes.
      -- Only A/B share an artifact and owe exact digest/mtime preservation.
      (rawC, _, compiledC) <-
        runWorker environment executable substrate "c" root independentCache workdirC
      assertBool "C compiled in its independent cache" compiledC
      assertEqual
        "independent cache preserves the four execution identities"
        (executionFields rawA)
        (executionFields rawC)
      assertBool
        "independent cache keeps its actual artifact coordinate"
        (Witness.rawWitnessArtifactPath rawA /= Witness.rawWitnessArtifactPath rawC)
      witnessC <- expectRight (Witness.refineRawDeviceExecutionWitness rawC)
      assertBool "independent artifacts are distinct complete witnesses" (witnessA /= witnessC)
      assertBool
        "C's artifact coordinate is absolute"
        (isAbsolute (Text.unpack (Witness.witnessArtifactPath witnessC)))

runWorker
  :: SubprocessEnv -> FilePath -> Substrate -> Text -> FilePath -> FilePath -> FilePath -> IO WorkerData
runWorker environment executable substrate stage root cacheDirectory workdir = do
  let command =
        ( subprocess
            executable
            [ "--jitml-device-witness-coordinate-worker"
            , renderSubstrate substrate
            , stage
            , Text.pack root
            , Text.pack cacheDirectory
            ]
        )
          { subprocessWorkingDirectory = Just workdir
          }
  result <- timeout 120000000 (runStreaming environment command)
  case result of
    Nothing -> assertFailure "real MLP coordinate helper timed out" >> fail "unreachable"
    Just (ProcessFailed failure) -> assertFailure (Text.unpack (renderProcessFailure failure)) >> fail "unreachable"
    Just (ProcessSucceeded transcript) -> do
      processTranscriptStdout transcript @?= acknowledgement stage
      processTranscriptStderr transcript @?= ""
      bytes <- LazyByteString.readFile (workerDataPath root stage)
      actual <- expectRight (deserialiseOrFail bytes)
      serialise actual @?= bytes
      pure actual

-- Resolve the same first-existing fixed bridge the real parent runtime uses,
-- before changing cwd in the helpers. The override is scoped to each launch;
-- this neither installs nor copies a bridge, and absence remains a failure.
workerEnvironment :: Substrate -> IO SubprocessEnv
workerEnvironment AppleSilicon = do
  candidates <- MetalBridge.fixedMetalBridgePathCandidates
  bridge <- firstExistingBridge candidates
  pure (subprocessEnvOverrideAndRemove [("JITML_METAL_BRIDGE_PATH", Text.pack bridge)] [])
 where
  firstExistingBridge [] =
    assertFailure "real MLP coordinate regression requires the installed fixed Metal bridge"
      >> fail "unreachable"
  firstExistingBridge (candidate : rest) = do
    present <- doesFileExist candidate
    if present then canonicalizePath candidate else firstExistingBridge rest
workerEnvironment _ = pure defaultSubprocessEnv

-- Only dedicated backend-binary argv reaches this helper. Cwd belongs to this
-- actual process; the shared test runner never mutates its process-global cwd.
runDeviceWitnessCoordinateWorker :: String -> String -> FilePath -> FilePath -> IO ()
runDeviceWitnessCoordinateWorker rawSubstrate rawStage root cacheDirectory = do
  substrate <-
    maybe
      (assertFailure "invalid coordinate helper substrate" >> fail "unreachable")
      pure
      (parseSubstrate (Text.pack rawSubstrate))
  let stage = Text.pack rawStage
  assertBool "unknown coordinate helper stage" (stage `elem` ["a", "b", "c"])
  cwd <- getCurrentDirectory >>= canonicalizePath
  cwd @?= case stage of
    "a" -> root
    "b" -> root </> "working-directory-b"
    _ -> root </> "working-directory-c"
  env <-
    buildEnv
      defaultGlobalFlags {globalCacheDir = Just cacheDirectory, globalDataDir = Just (root </> "data")}
  let spec = backendSpec substrate
      device = MlpDeviceSelect.mlpDeviceForSubstrate substrate env
      params = Mlp.mlpInit (Mlp.MlpShape 2 3 2) 11
      input = VU.fromList [0.3, -0.4]
      expected = Mlp.forwardOutput (Mlp.mlpForward params input)
  built <-
    Loader.ensureKernelArtifact
      env
      (MlpDevice.mbsEngine spec)
      (MlpDevice.mbsRuntimeSource spec)
      (MlpDevice.mbsHash spec)
      >>= expectRight . Bifunctor.first Loader.renderKernelArtifactError
  actual <- MlpDevice.mlpdForward device params input >>= expectRight
  let output = Mlp.forwardOutput actual
  VU.length output @?= VU.length expected
  assertBool
    "actual selected-device forward differs from its pure reference"
    ( VU.and
        ( VU.zipWith
            (\left right -> not (isNaN left || isInfinite left) && abs (left - right) <= 1.0e-5)
            output
            expected
        )
    )
  witnessed <- MlpDevice.mlpdExecutionWitness device >>= expectRight
  witness <- maybe (assertFailure "real MLP returned no witness" >> fail "unreachable") pure witnessed
  Witness.witnessSubstrate witness @?= substrate
  LazyByteString.writeFile
    (workerDataPath root stage)
    ( serialise
        ( Witness.deviceExecutionWitnessToRaw witness
        , Engine.kernelHandleArtifactPath (Loader.kernelArtifactHandle built)
        , Loader.kernelArtifactCompiled built
        )
    )
  writeLineIO (Text.dropEnd 1 (acknowledgement stage))

backendSpec :: Substrate -> MlpDevice.MlpBackendSpec
backendSpec LinuxCPU = MlpOneDnn.oneDnnMlpSpec
backendSpec AppleSilicon = MlpMetal.metalMlpSpec
backendSpec LinuxCUDA = MlpCuda.cudaMlpSpec

workerDataPath :: FilePath -> Text -> FilePath
workerDataPath root stage = root </> Text.unpack stage <> ".cbor"

acknowledgement :: Text -> Text
acknowledgement stage = "real MLP coordinate helper " <> stage <> " completed\n"

executionFields :: Witness.RawDeviceExecutionWitness -> [Text]
executionFields raw =
  [ Witness.rawWitnessSubstrate raw
  , Witness.rawWitnessBackend raw
  , Witness.rawWitnessKernelHash raw
  , Witness.rawWitnessExecutedIdentity raw
  ]

assertSixFields :: Witness.RawDeviceExecutionWitness -> Witness.RawDeviceExecutionWitness -> IO ()
assertSixFields expected actual = do
  assertEqual "substrate" (Witness.rawWitnessSubstrate expected) (Witness.rawWitnessSubstrate actual)
  assertEqual "backend" (Witness.rawWitnessBackend expected) (Witness.rawWitnessBackend actual)
  assertEqual
    "kernel hash"
    (Witness.rawWitnessKernelHash expected)
    (Witness.rawWitnessKernelHash actual)
  assertEqual
    "artifact path"
    (Witness.rawWitnessArtifactPath expected)
    (Witness.rawWitnessArtifactPath actual)
  assertEqual
    "artifact digest"
    (Witness.rawWitnessArtifactSha256 expected)
    (Witness.rawWitnessArtifactSha256 actual)
  assertEqual
    "executed identity"
    (Witness.rawWitnessExecutedIdentity expected)
    (Witness.rawWitnessExecutedIdentity actual)
  actual @?= expected

expectRight :: (Show failure) => Either failure value -> IO value
expectRight result = case result of
  Left failure -> assertFailure (show failure) >> fail "unreachable"
  Right value -> pure value
