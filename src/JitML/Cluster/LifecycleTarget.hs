{-# LANGUAGE OverloadedStrings #-}

-- Exact authority selection for state-preserving and destructive lifecycle commands.
module JitML.Cluster.LifecycleTarget
  ( LifecycleTarget (..)
  , PublicationAuthority (..)
  , parseLifecycleSubstrate
  , selectLifecycleTarget
  , stoppedPublication
  , stoppingPublication
  , requireExclusivePurgeTarget
  ) where

import Control.Monad (unless)
import Data.Text (Text)

import JitML.Cluster.EdgePort (EdgePortLease (..))
import JitML.Cluster.Publication
  ( ClusterPublication (..)
  , defaultPublication
  , publicationWithLeasedPort
  )
import JitML.Substrate (Substrate, parseSubstrate, substrateClusterName)

data PublicationAuthority
  = PublicationMissing
  | PublicationCorrupt Text
  | PublicationPresent ClusterPublication
  deriving (Eq, Show)

data LifecycleTarget = LifecycleTarget
  { targetSubstrate :: Substrate
  , targetPublication :: Maybe ClusterPublication
  }
  deriving (Eq, Show)

-- Destructive operations have no default substrate. Even repeated identical
-- values are rejected so a wrapper never silently changes the selected target.
parseLifecycleSubstrate :: [Text] -> Either Text (Maybe Substrate)
parseLifecycleSubstrate [] = Right Nothing
parseLifecycleSubstrate [value] =
  maybe (Left "unknown lifecycle substrate") (Right . Just) (parseSubstrate value)
parseLifecycleSubstrate _ = Left "lifecycle operation requires at most one --substrate"

-- A reconciling or stopped publication still supplies coordinates. Its lack
-- of live evidence never grants readiness, and must not prevent safe recovery.
-- Missing authority requires an explicit exact target; corrupt or conflicting
-- authority is never ignored in favour of a command-line guess.
selectLifecycleTarget
  :: Maybe Substrate -> PublicationAuthority -> Either Text LifecycleTarget
selectLifecycleTarget explicit authority = case authority of
  PublicationCorrupt _ -> Left "cluster publication is invalid; lifecycle target is unresolved"
  PublicationMissing -> case explicit of
    Nothing -> Left "cluster publication is missing; specify --substrate for observed-target recovery"
    Just substrate -> Right (LifecycleTarget substrate Nothing)
  PublicationPresent publication -> do
    let substrate = publicationSubstrate publication
        port = publicationEdgePort publication
        expected = publicationWithLeasedPort (EdgePortLease port "127.0.0.1") (defaultPublication substrate)
    unless
      (maybe True (== substrate) explicit)
      (Left "explicit substrate conflicts with cluster publication")
    unless (port >= 1 && port <= 65535) (Left "cluster publication has an invalid edge port")
    unless
      ( publicationPulsarUrl publication == publicationPulsarUrl expected
          && publicationMinioUrl publication == publicationMinioUrl expected
      )
      (Left "cluster publication coordinates do not match its loopback edge port")
    Right (LifecycleTarget substrate (Just publication))

stoppedPublication :: ClusterPublication -> ClusterPublication
stoppedPublication = lifecyclePublication "stopped"

stoppingPublication :: ClusterPublication -> ClusterPublication
stoppingPublication = lifecyclePublication "stopping"

lifecyclePublication :: Text -> ClusterPublication -> ClusterPublication
lifecyclePublication status publication =
  publication
    { publicationComponents = [(name, status) | (name, _) <- publicationComponents publication]
    , publicationEvidence = Nothing
    }

-- .data is shared by the supported local lanes. Purging it must not delete
-- storage underneath a different live Kind cluster. The concrete interpreter
-- obtains this complete canonical cluster inventory under the lifecycle lock.
requireExclusivePurgeTarget :: Substrate -> [Text] -> Either Text ()
requireExclusivePurgeTarget selected observed =
  unless
    (all (== substrateClusterName selected) observed)
    (Left "another jitML substrate cluster exists; shared .data cannot be purged")
