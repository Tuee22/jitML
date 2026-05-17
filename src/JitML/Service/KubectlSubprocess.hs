{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.KubectlSubprocess
  ( KubectlSubprocess (..)
  , KubectlSettings (..)
  , defaultKubectlSettings
  , runKubectlSubprocess
  )
where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Reader (MonadReader, ReaderT, ask, runReaderT)
import Data.Text (Text)
import Data.Text qualified as Text
import System.Exit (ExitCode (..))

import JitML.Service.Capabilities
  ( HasKubectl (..)
  , KubeResource (..)
  )
import JitML.Service.Retry (ServiceError (..))
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (Subprocess, subprocess, subprocessWithStdin)

-- | Pinned `kubectl` invocation knobs. The kubeconfig path is the
-- isolated `./.build/jitml.kubeconfig` produced by `jitml bootstrap`, never
-- the host's `~/.kube/config`.
data KubectlSettings = KubectlSettings
  { kubectlBinary :: FilePath
  , kubectlKubeconfig :: FilePath
  , kubectlNamespace :: Text
  }
  deriving stock (Eq, Show)

defaultKubectlSettings :: KubectlSettings
defaultKubectlSettings =
  KubectlSettings
    { kubectlBinary = "kubectl"
    , kubectlKubeconfig = "./.build/jitml.kubeconfig"
    , kubectlNamespace = "platform"
    }

-- | `HasKubectl` instance backed by the real `kubectl` binary through the
-- typed `Subprocess` boundary. Used by `jitml-integration` against the live
-- Kind cluster from Sprint 3.5.
newtype KubectlSubprocess a = KubectlSubprocess
  { unKubectlSubprocess :: ReaderT KubectlSettings IO a
  }
  deriving newtype
    ( Functor
    , Applicative
    , Monad
    , MonadIO
    , MonadReader KubectlSettings
    )

runKubectlSubprocess :: KubectlSettings -> KubectlSubprocess a -> IO a
runKubectlSubprocess settings action =
  runReaderT (unKubectlSubprocess action) settings

kubectlCmd :: KubectlSettings -> [Text] -> Subprocess
kubectlCmd settings args =
  subprocess
    (kubectlBinary settings)
    ( ["--kubeconfig", Text.pack (kubectlKubeconfig settings)]
        <> args
    )

kubectlApplyCmd :: KubectlSettings -> Text -> Subprocess
kubectlApplyCmd settings =
  subprocessWithStdin
    (kubectlBinary settings)
    [ "--kubeconfig"
    , Text.pack (kubectlKubeconfig settings)
    , "apply"
    , "-f"
    , "-"
    , "-n"
    , kubectlNamespace settings
    ]

instance HasKubectl KubectlSubprocess where
  kubectlApply (KubeResource _resource) yaml = do
    settings <- ask
    let cmd = kubectlApplyCmd settings yaml
    invoke "kubectlApply" cmd

  kubectlStatus (KubeResource resource) = do
    settings <- ask
    let cmd =
          kubectlCmd
            settings
            ["get", resource, "-n", kubectlNamespace settings, "-o", "yaml"]
    invokeText "kubectlStatus" cmd

  kubectlGet (KubeResource resource) = do
    settings <- ask
    let cmd =
          kubectlCmd
            settings
            ["get", resource, "-n", kubectlNamespace settings, "-o", "yaml"]
    invokeText "kubectlGet" cmd

  kubectlDelete (KubeResource resource) = do
    settings <- ask
    let cmd =
          kubectlCmd
            settings
            ["delete", resource, "-n", kubectlNamespace settings]
    invoke "kubectlDelete" cmd

invoke :: Text -> Subprocess -> KubectlSubprocess (Either ServiceError ())
invoke tag cmd = do
  (exitCode, _stdoutText, stderrText) <- liftIO (runStreaming defaultSubprocessEnv cmd)
  case exitCode of
    ExitSuccess -> pure (Right ())
    ExitFailure code ->
      pure
        ( Left
            ( SETransient
                ( tag
                    <> ": exit "
                    <> Text.pack (show code)
                    <> ": "
                    <> stderrText
                )
            )
        )

invokeText :: Text -> Subprocess -> KubectlSubprocess (Either ServiceError Text)
invokeText tag cmd = do
  (exitCode, stdoutText, stderrText) <- liftIO (runStreaming defaultSubprocessEnv cmd)
  case exitCode of
    ExitSuccess -> pure (Right stdoutText)
    ExitFailure code ->
      pure
        ( Left
            ( SETransient
                ( tag
                    <> ": exit "
                    <> Text.pack (show code)
                    <> ": "
                    <> stderrText
                )
            )
        )
