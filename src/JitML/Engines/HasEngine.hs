{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Engines.HasEngine
  ( EngineRequest (..)
  , EngineRun (..)
  , HasEngine (..)
  , LocalAppleSiliconEngine (..)
  , LocalCudaEngine (..)
  , LocalLinuxCpuEngine (..)
  , runAppleSiliconEngine
  , runCudaEngine
  , runLocalAppleSiliconEngine
  , runLocalCudaEngine
  , runLinuxCpuEngine
  , runLocalLinuxCpuEngine
  )
where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Reader (MonadReader, ReaderT, ask, runReaderT)
import Data.Text (Text)

import JitML.Codegen.KernelFamily (KernelFamily, familyName)
import JitML.Engines.CudaLocal qualified as CudaLocal
import JitML.Engines.Engine (KernelHandle)
import JitML.Engines.Local qualified as Local
import JitML.Engines.MetalLocal qualified as MetalLocal
import JitML.Env.Env (Env)

data EngineRequest = EngineRequest
  { engineRequestFamily :: KernelFamily
  , engineRequestInput :: [Float]
  }
  deriving stock (Eq, Show)

data EngineRun = EngineRun
  { engineRunHandle :: KernelHandle
  , engineRunFamily :: KernelFamily
  , engineRunOutput :: [Float]
  , engineRunReportedFamily :: Text
  , engineRunCompileCommand :: Text
  , engineRunCompiled :: Bool
  }
  deriving stock (Eq, Show)

class (Monad m) => HasEngine m where
  runEngine :: EngineRequest -> m (Either Text EngineRun)

newtype LocalLinuxCpuEngine a = LocalLinuxCpuEngine
  { unLocalLinuxCpuEngine :: ReaderT Env IO a
  }
  deriving newtype (Functor, Applicative, Monad, MonadIO, MonadReader Env)

newtype LocalCudaEngine a = LocalCudaEngine
  { unLocalCudaEngine :: ReaderT Env IO a
  }
  deriving newtype (Functor, Applicative, Monad, MonadIO, MonadReader Env)

newtype LocalAppleSiliconEngine a = LocalAppleSiliconEngine
  { unLocalAppleSiliconEngine :: ReaderT Env IO a
  }
  deriving newtype (Functor, Applicative, Monad, MonadIO, MonadReader Env)

runLocalLinuxCpuEngine :: Env -> LocalLinuxCpuEngine a -> IO a
runLocalLinuxCpuEngine env action =
  runReaderT (unLocalLinuxCpuEngine action) env

runLocalCudaEngine :: Env -> LocalCudaEngine a -> IO a
runLocalCudaEngine env action =
  runReaderT (unLocalCudaEngine action) env

runLocalAppleSiliconEngine :: Env -> LocalAppleSiliconEngine a -> IO a
runLocalAppleSiliconEngine env action =
  runReaderT (unLocalAppleSiliconEngine action) env

runLinuxCpuEngine :: Env -> EngineRequest -> IO (Either Text EngineRun)
runLinuxCpuEngine env request =
  runLocalLinuxCpuEngine env (runEngine request)

runCudaEngine :: Env -> EngineRequest -> IO (Either Text EngineRun)
runCudaEngine env request =
  runLocalCudaEngine env (runEngine request)

runAppleSiliconEngine :: Env -> EngineRequest -> IO (Either Text EngineRun)
runAppleSiliconEngine env request =
  runLocalAppleSiliconEngine env (runEngine request)

instance HasEngine LocalLinuxCpuEngine where
  runEngine request = do
    env <- ask
    kernelResult <-
      liftIO
        ( Local.runLinuxCpuFamilyKernel
            env
            (engineRequestFamily request)
            (engineRequestInput request)
        )
    pure (kernelResult >>= toEngineRun (engineRequestFamily request))

instance HasEngine LocalCudaEngine where
  runEngine request = do
    env <- ask
    kernelResult <-
      liftIO
        ( CudaLocal.runCudaFamilyKernel
            env
            (engineRequestFamily request)
            (engineRequestInput request)
        )
    pure (kernelResult >>= toCudaEngineRun (engineRequestFamily request))

instance HasEngine LocalAppleSiliconEngine where
  runEngine request = do
    env <- ask
    kernelResult <-
      liftIO
        ( MetalLocal.runMetalFamilyKernel
            env
            (engineRequestFamily request)
            (engineRequestInput request)
        )
    pure (kernelResult >>= toMetalEngineRun (engineRequestFamily request))

toEngineRun :: KernelFamily -> Local.LinuxCpuKernelRun -> Either Text EngineRun
toEngineRun family kernelRun =
  if reportedFamily == expectedFamily
    then
      Right
        EngineRun
          { engineRunHandle = Local.linuxCpuKernelHandle kernelRun
          , engineRunFamily = family
          , engineRunOutput = Local.linuxCpuKernelOutput kernelRun
          , engineRunReportedFamily = reportedFamily
          , engineRunCompileCommand = Local.linuxCpuKernelCompileCommand kernelRun
          , engineRunCompiled = Local.linuxCpuKernelCompiled kernelRun
          }
    else
      Left
        ( "linux-cpu engine loaded family "
            <> reportedFamily
            <> " for requested family "
            <> expectedFamily
        )
 where
  expectedFamily = familyName family
  reportedFamily = Local.linuxCpuKernelReportedFamily kernelRun

toCudaEngineRun :: KernelFamily -> CudaLocal.CudaKernelRun -> Either Text EngineRun
toCudaEngineRun family kernelRun =
  if reportedFamily == expectedFamily
    then
      Right
        EngineRun
          { engineRunHandle = CudaLocal.cudaKernelHandle kernelRun
          , engineRunFamily = family
          , engineRunOutput = CudaLocal.cudaKernelOutput kernelRun
          , engineRunReportedFamily = reportedFamily
          , engineRunCompileCommand = CudaLocal.cudaKernelCompileCommand kernelRun
          , engineRunCompiled = CudaLocal.cudaKernelCompiled kernelRun
          }
    else
      Left
        ( "linux-cuda engine loaded family "
            <> reportedFamily
            <> " for requested family "
            <> expectedFamily
        )
 where
  expectedFamily = familyName family
  reportedFamily = CudaLocal.cudaKernelReportedFamily kernelRun

toMetalEngineRun :: KernelFamily -> MetalLocal.MetalKernelRun -> Either Text EngineRun
toMetalEngineRun family kernelRun =
  if reportedFamily == expectedFamily
    then
      Right
        EngineRun
          { engineRunHandle = MetalLocal.metalKernelHandle kernelRun
          , engineRunFamily = family
          , engineRunOutput = MetalLocal.metalKernelOutput kernelRun
          , engineRunReportedFamily = reportedFamily
          , engineRunCompileCommand = MetalLocal.metalKernelCompileCommand kernelRun
          , engineRunCompiled = MetalLocal.metalKernelCompiled kernelRun
          }
    else
      Left
        ( "apple-silicon engine loaded family "
            <> reportedFamily
            <> " for requested family "
            <> expectedFamily
        )
 where
  expectedFamily = familyName family
  reportedFamily = MetalLocal.metalKernelReportedFamily kernelRun
