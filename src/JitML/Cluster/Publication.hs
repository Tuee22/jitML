{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TupleSections #-}

module JitML.Cluster.Publication
  ( ClusterPublication (..)
  , defaultPublication
  , markPublicationLive
  , publicationComponentsReady
  , publicationHasLiveEvidence
  , publicationWithLeasedPort
  , requiredPublicationComponents
  , renderPublicationSummary
  )
where

import Data.Aeson (FromJSON (..), ToJSON (..), object, withObject, (.:), (.:?), (.=))
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Cluster.EdgePort (EdgePortLease (..))
import JitML.Substrate
  ( Substrate (..)
  , parseSubstrate
  , renderSubstrate
  , substrateEdgePort
  , substrateHasClusterCompute
  )

data ClusterPublication = ClusterPublication
  { publicationSubstrate :: Substrate
  , publicationEdgePort :: Int
  , publicationPulsarUrl :: Text
  , publicationMinioUrl :: Text
  , publicationComponents :: [(Text, Text)]
  , publicationEvidence :: Maybe Text
  }
  deriving stock (Eq, Show)

instance ToJSON ClusterPublication where
  toJSON publication =
    object
      [ "substrate" .= renderSubstrate (publicationSubstrate publication)
      , "edge_port" .= publicationEdgePort publication
      , "pulsar_url" .= publicationPulsarUrl publication
      , "minio_url" .= publicationMinioUrl publication
      , "components" .= fmap componentObject (publicationComponents publication)
      , "evidence" .= publicationEvidence publication
      ]
   where
    componentObject (name, status) =
      object ["name" .= name, "status" .= status]

instance FromJSON ClusterPublication where
  parseJSON =
    withObject "ClusterPublication" $ \objectValue -> do
      substrateText <- objectValue .: "substrate"
      substrate <-
        maybe
          (fail ("unknown substrate: " <> Text.unpack substrateText))
          pure
          (parseSubstrate substrateText)
      components <- objectValue .: "components"
      ClusterPublication substrate
        <$> objectValue .: "edge_port"
        <*> objectValue .: "pulsar_url"
        <*> objectValue .: "minio_url"
        <*> traverse parseComponent components
        <*> objectValue .:? "evidence"
   where
    parseComponent =
      withObject "component" $ \component ->
        (,)
          <$> component .: "name"
          <*> component .: "status"

defaultPublication :: Substrate -> ClusterPublication
defaultPublication substrate =
  ClusterPublication
    { publicationSubstrate = substrate
    , publicationEdgePort = substrateEdgePort substrate
    , publicationPulsarUrl =
        "pulsar://127.0.0.1:" <> Text.pack (show (substrateEdgePort substrate)) <> "/pulsar"
    , publicationMinioUrl =
        "http://127.0.0.1:" <> Text.pack (show (substrateEdgePort substrate)) <> "/minio/s3"
    , publicationComponents = fmap (,"ready") (requiredPublicationComponents substrate)
    , publicationEvidence = Nothing
    }

-- | The exact component family a consumable live publication must prove. The
-- Linux publications require distinct Engine and Coordinator rows because one
-- Helm release owns both Deployments. Apple Silicon deliberately omits Engine:
-- its clustered Engine Deployment has zero replicas, while the separately
-- launched host daemon is outside cluster-bootstrap readiness and must not be
-- inferred ready from that zero-replica rollout.
requiredPublicationComponents :: Substrate -> [Text]
requiredPublicationComponents substrate =
  [ -- No "postgres": `harbor-pg` was the only registered service Postgres and
    -- left with Harbor, so nothing measures that component any more. Requiring
    -- a component no health check reports would fail every publication.
    "registry"
  , "minio"
  , "pulsar"
  , "observability"
  ]
    <> engineComponents
    <> [ "jitml-coordinator"
       , "jitml-demo"
       , "edge"
       ]
 where
  engineComponents = ["jitml-engine" | substrateHasClusterCompute substrate]

-- | Require one and only one ready row for every required component, with no
-- legacy, duplicate, or unexpected rows. This is intentionally stricter than
-- checking that each name occurs somewhere: duplicate ready rows must not mint
-- evidence, and a not-ready extra check must not be ignored.
publicationComponentsReady :: ClusterPublication -> Bool
publicationComponentsReady publication =
  length components == length requiredComponents
    && all requiredComponentReady requiredComponents
    && all ((== "ready") . snd) components
 where
  components = publicationComponents publication
  requiredComponents = requiredPublicationComponents (publicationSubstrate publication)
  requiredComponentReady requiredName =
    [status | (name, status) <- components, name == requiredName] == ["ready"]

markPublicationLive :: ClusterPublication -> ClusterPublication
markPublicationLive publication =
  publication
    { publicationEvidence =
        if publicationComponentsReady publication
          then Just "live-readiness"
          else Nothing
    }

publicationHasLiveEvidence :: ClusterPublication -> Bool
publicationHasLiveEvidence publication =
  publicationEvidence publication == Just "live-readiness"
    && publicationComponentsReady publication

-- | Overlay a `leaseEdgePort` result onto a `ClusterPublication`,
-- rewriting `publicationEdgePort` and the Pulsar / MinIO URLs so they
-- point at the actually-bindable port. The lease's host (always
-- `"127.0.0.1"` per `JitML.Cluster.EdgePort.leaseEdgePort`) is used
-- verbatim. This is the bridge between Sprint 3.5's port-lease probe
-- and the JSON publication consumed by downstream Apple-host /
-- Linux-host substrates.
publicationWithLeasedPort :: EdgePortLease -> ClusterPublication -> ClusterPublication
publicationWithLeasedPort lease publication =
  publication
    { publicationEdgePort = leasedPort lease
    , publicationPulsarUrl =
        "pulsar://"
          <> Text.pack (leasedHost lease)
          <> ":"
          <> Text.pack (show (leasedPort lease))
          <> "/pulsar"
    , publicationMinioUrl =
        "http://"
          <> Text.pack (leasedHost lease)
          <> ":"
          <> Text.pack (show (leasedPort lease))
          <> "/minio/s3"
    }

renderPublicationSummary :: ClusterPublication -> Text
renderPublicationSummary publication =
  Text.unlines $
    [ "substrate: " <> renderSubstrate (publicationSubstrate publication)
    , "edge_port: " <> Text.pack (show (publicationEdgePort publication))
    , "pulsar_url: " <> publicationPulsarUrl publication
    , "minio_url: " <> publicationMinioUrl publication
    , "evidence: " <> fromMaybe "none" (publicationEvidence publication)
    , "components:"
    ]
      <> fmap renderComponent (publicationComponents publication)
 where
  renderComponent (name, status) =
    "  - " <> name <> ": " <> status
