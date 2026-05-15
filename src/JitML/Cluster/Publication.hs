{-# LANGUAGE OverloadedStrings #-}

module JitML.Cluster.Publication
    ( ClusterPublication (..)
    , defaultPublication
    , renderPublicationSummary
    )
where

import Data.Aeson (FromJSON (..), ToJSON (..), object, withObject, (.:), (.=))
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Substrate (Substrate, parseSubstrate, renderSubstrate, substrateEdgePort)

data ClusterPublication = ClusterPublication
    { publicationSubstrate :: Substrate
    , publicationEdgePort :: Int
    , publicationPulsarUrl :: Text
    , publicationMinioUrl :: Text
    , publicationComponents :: [(Text, Text)]
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
            ClusterPublication
                <$> pure substrate
                <*> objectValue .: "edge_port"
                <*> objectValue .: "pulsar_url"
                <*> objectValue .: "minio_url"
                <*> traverse parseComponent components
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
        , publicationPulsarUrl = "pulsar://127.0.0.1:" <> Text.pack (show (substrateEdgePort substrate)) <> "/pulsar"
        , publicationMinioUrl = "http://127.0.0.1:" <> Text.pack (show (substrateEdgePort substrate)) <> "/minio/s3"
        , publicationComponents =
            [ ("harbor", "ready")
            , ("minio", "ready")
            , ("pulsar", "ready")
            , ("postgres", "ready")
            , ("observability", "ready")
            , ("jitml-service", "ready")
            , ("jitml-demo", "ready")
            ]
        }

renderPublicationSummary :: ClusterPublication -> Text
renderPublicationSummary publication =
    Text.unlines $
        [ "substrate: " <> renderSubstrate (publicationSubstrate publication)
        , "edge_port: " <> Text.pack (show (publicationEdgePort publication))
        , "pulsar_url: " <> publicationPulsarUrl publication
        , "minio_url: " <> publicationMinioUrl publication
        , "components:"
        ]
            <> fmap renderComponent (publicationComponents publication)
  where
    renderComponent (name, status) =
        "  - " <> name <> ": " <> status
