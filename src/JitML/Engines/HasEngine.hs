{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Engines.HasEngine
  ( EngineRequest (..)
  , EngineRun (..)
  , HasEngine (..)
  , LocalLinuxCpuEngine (..)
  , runLinuxCpuEngine
  , runLocalLinuxCpuEngine
  )
where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Reader (MonadReader, ReaderT, ask, runReaderT)
import Data.Text (Text)

import JitML.Codegen.KernelFamily (KernelFamily, familyName)
import JitML.Engines.Engine (KernelHandle)
import JitML.Engines.Local qualified as Local
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

runLocalLinuxCpuEngine :: Env -> LocalLinuxCpuEngine a -> IO a
runLocalLinuxCpuEngine env action =
  runReaderT (unLocalLinuxCpuEngine action) env

runLinuxCpuEngine :: Env -> EngineRequest -> IO (Either Text EngineRun)
runLinuxCpuEngine env request =
  runLocalLinuxCpuEngine env (runEngine request)

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
