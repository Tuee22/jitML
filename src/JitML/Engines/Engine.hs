{-# LANGUAGE OverloadedStrings #-}

module JitML.Engines.Engine
  ( Engine (..)
  , EngineEnvelope (..)
  , CompileArgument (..)
  , CompileFlag (..)
  , CompileFlagRole (..)
  , compileFlagText
  , compileLineReproducibility
  , renderCompileFlag
  , CudaLibrary (..)
  , programCudaLibraries
  , programLibraryDefines
  , JitCacheStatus (..)
  , KernelHandle (..)
  , KernelInputs (..)
  , KernelOutputs (..)
  , compileLineDeterminism
  , compileSubprocess
  , deterministicFlags
  , engineCompileFlagSpecs
  , engineCompileFlags
  , engineCompiler
  , engineEnvelope
  , engineForSubstrate
  , engineLinkFlags
  , engineSourceFileName
  , kernelHandleFor
  , renderedScratchDirectory
  , renderedStagingPath
  , renderBuildPlan
  , renderEngineEnvelope
  , renderEnginePlan
  , resolveKernelCache
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Cache.Key qualified as Cache
import JitML.Codegen.RuntimeSource
  ( KernelProgram (..)
  , RuntimeSource
  , runtimeSourceProgram
  , runtimeSourceRelativeDirectory
  )
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Subprocess (Subprocess, subprocess)
import JitML.Substrate
  ( ArtifactFill (..)
  , PinnedNonDeterminism (..)
  , Substrate (..)
  , SubstrateProfile (..)
  , producerPins
  , profileFor
  , renderSubstrate
  )

data Engine = Engine
  { engineSubstrate :: Substrate
  , engineBackend :: Text
  , engineArtifactExtension :: Text
  }
  deriving stock (Eq, Show)

data KernelHandle = KernelHandle
  { kernelHandleEngine :: Engine
  , kernelHandleHash :: Cache.Hash
  , kernelHandleArtifactPath :: Text
  }
  deriving stock (Eq, Show)

data KernelInputs = KernelInputs
  { kernelInputShape :: [Int]
  , kernelInputBytes :: Int
  }
  deriving stock (Eq, Show)

data KernelOutputs = KernelOutputs
  { kernelOutputShape :: [Int]
  , kernelOutputBytes :: Int
  }
  deriving stock (Eq, Show)

data EngineEnvelope = EngineEnvelope
  { envelopeHandle :: KernelHandle
  , envelopeInputs :: KernelInputs
  , envelopeOutputs :: KernelOutputs
  , envelopeDeterminism :: [Text]
  , envelopeCompileCommand :: Text
  }
  deriving stock (Eq, Show)

data JitCacheStatus
  = JitCacheHit KernelHandle
  | JitCacheMiss KernelHandle Subprocess
  deriving stock (Eq, Show)

-- | The engine record is a projection of the profile, so the two cannot
-- disagree about a substrate's backend or artifact extension.
engineForSubstrate :: Substrate -> Engine
engineForSubstrate substrate =
  Engine
    { engineSubstrate = profileSubstrate profile
    , engineBackend = profileBackend profile
    , engineArtifactExtension = profileArtifactExtension profile
    }
 where
  profile = profileFor substrate

-- | The determinism facts an artifact built by this engine advertises to the
-- JIT cache key.
--
-- Sprint `78.1` — the compile-line half is 'compileLineDeterminism', a
-- projection of the very list 'compileSubprocess' renders, so the advertised
-- facts and the rendered compile line come from one source and cannot describe
-- a command the engine does not run. The remaining half is
-- 'JitML.Substrate.profileDeterminism': the substrate's runtime determinism
-- properties, which no compile line establishes.
deterministicFlags :: Engine -> [Text]
deterministicFlags engine =
  compileLineDeterminism engine
    <> profileDeterminism (profileFor (engineSubstrate engine))

-- | The determinism facts the rendered compile command establishes, read off
-- 'engineCompileFlagSpecs' rather than restated beside it.
--
-- Two things are derived here. The 'DeterminismFlag'-roled arguments are quoted
-- verbatim, so adding or dropping one moves the compile command and the cache
-- key in a single edit. The @fast-math@ entry is read off the same list: it
-- says @absent@ because no fast-math argument is passed — nvcc rejects the
-- @--use_fast_math=false@ spelling and absence is off — and it flips to
-- @passed@, invalidating every artifact, the moment one is added.
--
-- A substrate whose artifact is filled by a metadata write rather than a
-- compile subprocess ('SourceMetadataWriteFill') runs no compile line, so it
-- contributes nothing here and carries its determinism properties in
-- 'JitML.Substrate.profileDeterminism' instead.
compileLineDeterminism :: Engine -> [Text]
compileLineDeterminism engine =
  case profileArtifactFill (profileFor (engineSubstrate engine)) of
    SourceMetadataWriteFill -> []
    CompileSubprocessFill ->
      fastMathFact
        : [compileFlagText flag | flag <- specs, compileFlagRole flag == DeterminismFlag]
 where
  specs = engineCompileFlagSpecs engine
  fastMathFact
    | any (isFastMathArgument . compileFlagText) specs = "fast-math=passed"
    | otherwise = "fast-math=absent"
  isFastMathArgument argument =
    "fast-math" `Text.isInfixOf` argument || "fast_math" `Text.isInfixOf` argument

-- | The reproducibility facts the compile line establishes, read off the same
-- one list. Rendered for every substrate — empty where the producer injects
-- nothing — so the fact is uniform rather than a per-substrate branch.
compileLineReproducibility :: Engine -> [Text]
compileLineReproducibility engine =
  [ compileFlagText flag
  | flag <- engineCompileFlagSpecs engine
  , compileFlagRole flag == ReproducibilityFlag
  ]

renderEnginePlan :: Engine -> Text
renderEnginePlan engine =
  Text.unlines
    [ "substrate: " <> renderSubstrate (engineSubstrate engine)
    , "backend: " <> engineBackend engine
    , "artifact_extension: " <> engineArtifactExtension engine
    , "determinism:"
    , "  - " <> Text.intercalate "\n  - " (deterministicFlags engine)
    ]

renderBuildPlan :: Engine -> RuntimeSource -> Cache.Hash -> Text
renderBuildPlan engine source hash =
  Text.unlines
    [ renderEnginePlan engine
    , "generated_source_dir: " <> Text.pack (runtimeSourceRelativeDirectory source hash)
    , "cache_artifact: " <> artifactPathText engine hash
    , "compile:"
    , "  - "
        <> renderSubprocess
          ( compileSubprocess
              engine
              source
              hash
              renderedScratchDirectory
              (renderedStagingPath engine hash)
          )
    ]

kernelHandleFor :: Engine -> Cache.Hash -> KernelHandle
kernelHandleFor engine hash =
  KernelHandle
    { kernelHandleEngine = engine
    , kernelHandleHash = hash
    , kernelHandleArtifactPath = artifactPathText engine hash
    }

resolveKernelCache :: Engine -> RuntimeSource -> Cache.Hash -> Bool -> JitCacheStatus
resolveKernelCache engine source hash cacheArtifactExists =
  let handle = kernelHandleFor engine hash
   in if cacheArtifactExists
        then JitCacheHit handle
        else
          JitCacheMiss
            handle
            ( compileSubprocess
                engine
                source
                hash
                renderedScratchDirectory
                (renderedStagingPath engine hash)
            )

engineEnvelope
  :: Engine -> RuntimeSource -> Cache.Hash -> KernelInputs -> KernelOutputs -> EngineEnvelope
engineEnvelope engine source hash inputs outputs =
  EngineEnvelope
    { envelopeHandle = kernelHandleFor engine hash
    , envelopeInputs = inputs
    , envelopeOutputs = outputs
    , envelopeDeterminism = deterministicFlags engine
    , envelopeCompileCommand =
        renderSubprocess
          ( compileSubprocess
              engine
              source
              hash
              renderedScratchDirectory
              (renderedStagingPath engine hash)
          )
    }

renderEngineEnvelope :: EngineEnvelope -> Text
renderEngineEnvelope envelope =
  Text.unlines
    [ "artifact: " <> kernelHandleArtifactPath handle
    , "backend: " <> engineBackend (kernelHandleEngine handle)
    , "input_shape: " <> renderIntList (kernelInputShape (envelopeInputs envelope))
    , "input_bytes: " <> Text.pack (show (kernelInputBytes (envelopeInputs envelope)))
    , "output_shape: " <> renderIntList (kernelOutputShape (envelopeOutputs envelope))
    , "output_bytes: " <> Text.pack (show (kernelOutputBytes (envelopeOutputs envelope)))
    , "determinism:"
    , "  - " <> Text.intercalate "\n  - " (envelopeDeterminism envelope)
    , "compile: " <> envelopeCompileCommand envelope
    ]
 where
  handle = envelopeHandle envelope

-- | The program each substrate's cache-miss path invokes.
--
-- Apple cache misses are metadata writes handled in-process by
-- 'JitML.Engines.Loader'; the named program is retained only as a typed,
-- renderable diagnostic in the existing cache-miss status shape.
engineCompiler :: Engine -> Text
engineCompiler engine =
  case engineSubstrate engine of
    AppleSilicon -> "jitml-metal-metadata-cache"
    LinuxCPU -> "g++"
    LinuxCUDA -> "nvcc"

-- | Why a compile argument is on the command line.
data CompileFlagRole
  = -- | Target, language, and link plumbing. It selects toolchain behaviour the
    -- artifact needs, but it is not what pins the arithmetic.
    BuildFlag
  | -- | The argument exists to pin numerical behaviour. 'compileLineDeterminism'
    -- reads exactly these, so the determinism facts a cache key advertises are
    -- the determinism arguments the compile command passes.
    DeterminismFlag
  | -- | The argument exists to pin the __artifact bytes__, not the arithmetic.
    -- Kept distinct from 'DeterminismFlag' because that role feeds
    -- 'JitML.Engines.Fingerprint.factsDeterminism', which
    -- @documents/engineering/determinism_contract.md@ defines as /numerical/
    -- determinism; an argument that pins a compiler's embedded identifiers pins
    -- nothing numerical, and saying otherwise would make the determinism
    -- contract state something false.
    ReproducibilityFlag
  deriving stock (Eq, Show)

-- | A compile argument's shape.
--
-- Sprint `78.1` — most arguments are literals, but a pin can need a value the
-- caller supplies per invocation. Splitting the two lets 'engineCompileFlags'
-- contribute only the literal prefix to the cache key (so the key stays free of
-- invocation-scoped paths) while 'renderCompileFlag' emits the full argument
-- pair, and keeps the prefix and its value inseparable: neither can be passed
-- without the other.
data CompileArgument
  = -- | Rendered verbatim.
    FixedArgument !Text
  | -- | Rendered as @\<prefix\> \<scratch dir\>@. The scratch directory's path
    -- is measured __not__ to be embedded in the artifact, which is what makes it
    -- safe to vary per invocation while the bytes stay reproducible.
    ScratchDirArgument !Text
  deriving stock (Eq, Show)

-- | One hash-free compile argument together with the role it plays.
data CompileFlag = CompileFlag
  { compileFlagArgument :: !CompileArgument
  , compileFlagRole :: !CompileFlagRole
  }
  deriving stock (Eq, Show)

-- | The cache-key-visible text of an argument: the literal, or a value
-- argument's prefix. Never an invocation-scoped path.
compileFlagText :: CompileFlag -> Text
compileFlagText flag =
  case compileFlagArgument flag of
    FixedArgument text -> text
    ScratchDirArgument prefix -> prefix

-- | The argument as the compiler receives it.
renderCompileFlag :: FilePath -> CompileFlag -> [Text]
renderCompileFlag scratchDir flag =
  case compileFlagArgument flag of
    FixedArgument text -> [text]
    ScratchDirArgument prefix -> [prefix, Text.pack scratchDir]

-- | The hash-free compile arguments, split out of 'compileSubprocess' so the
-- toolchain fingerprint (Sprint `78.1`) can name the flags the compile command
-- actually passes without becoming circular in the cache key: the artifact and
-- source paths depend on the hash, these do not.
--
-- Each argument carries its 'CompileFlagRole', so 'engineCompileFlags' (what
-- the compiler is invoked with) and 'compileLineDeterminism' (what the cache
-- key advertises about that invocation) are two projections of one list rather
-- than two lists that can drift apart.
engineCompileFlagSpecs :: Engine -> [CompileFlag]
engineCompileFlagSpecs engine =
  substrateCompileFlags engine <> reproducibilityFlags engine

-- | The arguments a substrate's compiler needs regardless of reproducibility.
substrateCompileFlags :: Engine -> [CompileFlag]
substrateCompileFlags engine =
  case engineSubstrate engine of
    AppleSilicon -> []
    LinuxCPU ->
      [ fixed "-std=c++20" BuildFlag
      , fixed "-O2" BuildFlag
      , fixed "-fPIC" BuildFlag
      , fixed "-shared" BuildFlag
      , fixed "-DJITML_DETERMINISTIC_REDUCTIONS=1" DeterminismFlag
      ]
    LinuxCUDA ->
      [ fixed "--shared" BuildFlag
      , fixed "--compiler-options=-fPIC" BuildFlag
      , fixed "-arch=sm_70" BuildFlag
      , -- Disable FMA contraction so the device multiply-adds round the same
        -- way the CPU (oneDNN) build does with its separate multiply-then-add
        -- and fixed reduction order. With `--fmad=true` (the nvcc default) the
        -- MLP kernels contract `acc += w*x` into a fused op that rounds once
        -- instead of twice; in the chaotic RL training loop that sub-ULP skew
        -- amplifies into materially different convergence (e.g. PPO/cartpole
        -- 450 on oneDNN vs 286 on CUDA at the same seed/config). Matching the
        -- rounding makes the substrates track and keeps the determinism
        -- contract's cross-substrate intent honest.
        --
        -- Fast math is off by omission: `--use_fast_math` is a presence flag,
        -- the modern nvcc parser rejects the `--use_fast_math=false` spelling
        -- with `no argument expected after '--use_fast_math'`, and absence is
        -- off. 'compileLineDeterminism' reads that absence off this list rather
        -- than restating a flag no compile line passes.
        fixed "--fmad=false" DeterminismFlag
      ]

-- | The arguments that pin this substrate's artifact bytes, one per
-- 'PinnedNonDeterminism' its producer carries.
--
-- Sprint `78.1` — total over the pin set, so a substrate whose producer gains a
-- source of non-determinism cannot acquire it without also acquiring its
-- remedy, and a substrate whose set is empty contributes nothing.
-- 'SymbolMangling' is pinned in the renderer rather than on the command line
-- (the construct is removed, see 'JitML.Substrate.InternalLinkageStyle'), so it
-- contributes no argument here.
reproducibilityFlags :: Engine -> [CompileFlag]
reproducibilityFlags engine =
  concatMap pinArguments (producerPins (engineSubstrate engine))
 where
  pinArguments pin =
    case pin of
      IntermediateFileNaming ->
        [ fixed "--keep" ReproducibilityFlag
        , CompileFlag (ScratchDirArgument "--keep-dir") ReproducibilityFlag
        ]
      SymbolMangling -> []

fixed :: Text -> CompileFlagRole -> CompileFlag
fixed text = CompileFlag (FixedArgument text)

-- | A CUDA math library a generated program calls.
data CudaLibrary = Cublas | Cudnn
  deriving stock (Eq, Show)

-- | Which CUDA math libraries each generated program really calls.
--
-- Sprint `265.1` — read off the renderers. 'JitML.Codegen.Cuda' guards its
-- cuBLAS and cuDNN call sites behind the two macros and
-- 'JitML.Codegen.CudaLayerTraining' includes @cublas_v2.h@ and @cudnn.h@
-- unconditionally, but 'JitML.Codegen.MlpCuda' includes only @cuda_runtime.h@
-- and calls neither. Defining the macros and linking the libraries for every
-- CUDA artifact regardless left the MLP @.so@ carrying @DT_NEEDED@ entries it
-- never enters, and put two libraries it does not use into its cache key.
programCudaLibraries :: KernelProgram -> [CudaLibrary]
programCudaLibraries FamilyProgram = [Cublas, Cudnn]
programCudaLibraries MlpProgram = []
programCudaLibraries LayerTrainingProgram = [Cublas, Cudnn]

-- | The arguments the compiler is invoked with, in command order: the
-- substrate-wide arguments, then the macros the __program__'s own source reads.
engineCompileFlags :: Engine -> KernelProgram -> [Text]
engineCompileFlags engine program =
  fmap compileFlagText (engineCompileFlagSpecs engine)
    <> programLibraryDefines engine program

programLibraryDefines :: Engine -> KernelProgram -> [Text]
programLibraryDefines engine program =
  case engineSubstrate engine of
    AppleSilicon -> []
    LinuxCPU -> []
    LinuxCUDA -> concatMap defineFor (programCudaLibraries program)
 where
  defineFor Cublas = ["-DJITML_USE_CUBLAS=1"]
  defineFor Cudnn = ["-DJITML_USE_CUDNN=1"]

-- | The link arguments passed after the source file: the substrate's own, then
-- the math libraries the __program__ calls (Sprint `265.1`).
engineLinkFlags :: Engine -> KernelProgram -> [Text]
engineLinkFlags engine program =
  case engineSubstrate engine of
    AppleSilicon -> []
    LinuxCPU -> ["-ldnnl"]
    LinuxCUDA ->
      [ -- Sprint 13.11 — the CUDA-shipped stubs dir holds a link-time
        -- `libcuda.so` that we need at compile time but not at runtime.
        -- Pass it explicitly so link succeeds without leaving stubs on
        -- LD_LIBRARY_PATH, which would otherwise shadow the real driver
        -- library injected by the NVIDIA Container Toolkit.
        "-L/usr/local/cuda/lib64/stubs"
      , "-lcudart"
      ]
        <> concatMap linkFor (programCudaLibraries program)
 where
  linkFor Cublas = ["-lcublas"]
  linkFor Cudnn = ["-lcudnn"]

-- | The generated source file each substrate compiles.
engineSourceFileName :: Engine -> Text
engineSourceFileName engine =
  case engineSubstrate engine of
    AppleSilicon -> "kernel.metal.json"
    LinuxCPU -> "kernel.cc"
    LinuxCUDA -> "kernel.cu"

-- | The compile command, as a total fold over 'engineCompileFlagSpecs'.
--
-- Sprint `78.1` — no argument reaches the compiler that the spec list does not
-- contain, so the cache key cannot be blind to an argument the compiler is
-- given. (The converse — no advertised fact without a real argument — is what
-- the original Sprint `78.1` closed; both directions now hold and both are
-- tested.)
--
-- @scratchDir@ is the per-invocation directory the producer's intermediate
-- files are directed at, and @stagingPath@ is where the artifact is written
-- before being renamed into its content-addressed cache slot. Neither is a
-- cache-key input: the scratch path is measured not to be embedded in the
-- artifact, and the staging path is measured not to change the emitted bytes.
compileSubprocess :: Engine -> RuntimeSource -> Cache.Hash -> FilePath -> FilePath -> Subprocess
compileSubprocess engine source hash scratchDir stagingPath =
  subprocess (Text.unpack (engineCompiler engine)) arguments
 where
  sourceDir = Text.pack (runtimeSourceRelativeDirectory source hash)
  sourcePath = sourceDir <> "/" <> engineSourceFileName engine
  staging = Text.pack stagingPath
  arguments =
    case engineSubstrate engine of
      AppleSilicon -> [staging, sourcePath]
      LinuxCPU -> hostCompileArguments
      LinuxCUDA -> hostCompileArguments
  -- The program is read off the rendered source rather than passed alongside
  -- it, so a compile command cannot name libraries for a different program than
  -- the one it is compiling (Sprint `265.1`).
  program = runtimeSourceProgram source
  hostCompileArguments =
    concatMap (renderCompileFlag scratchDir) (engineCompileFlagSpecs engine)
      <> programLibraryDefines engine program
      <> ["-o", staging, sourcePath]
      <> engineLinkFlags engine program

-- | The scratch directory and staging path a rendering context shows when no
-- real compile is being performed. Named once so a rendered plan displays the
-- true argument /shape/ and no call site invents its own placeholder.
renderedScratchDirectory :: FilePath
renderedScratchDirectory = ".build/jit-scratch/<compile>"

renderedStagingPath :: Engine -> Cache.Hash -> FilePath
renderedStagingPath engine hash =
  Text.unpack (artifactPathText engine hash) <> ".<compile>.partial"

artifactPathText :: Engine -> Cache.Hash -> Text
artifactPathText engine hash =
  Text.concat
    [ ".build/jit/"
    , renderSubstrate (engineSubstrate engine)
    , "/"
    , Cache.hashHex hash
    , "."
    , engineArtifactExtension engine
    ]

renderIntList :: [Int] -> Text
renderIntList values =
  "[" <> Text.intercalate ", " (fmap (Text.pack . show) values) <> "]"
