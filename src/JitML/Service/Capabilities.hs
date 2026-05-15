{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.Capabilities
  ( BucketName (..)
  , ImageRef (..)
  , KubeResource (..)
  , ObjectKey (..)
  , ObjectRef (..)
  , TopicName (..)
  , HasHarbor (..)
  , HasKubectl (..)
  , HasMinIO (..)
  , HasPulsar (..)
  , capabilityNames
  , renderCapabilitySurface
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Service.Retry (ServiceError)

newtype BucketName = BucketName {unBucketName :: Text}
  deriving stock (Eq, Show)

newtype ObjectKey = ObjectKey {unObjectKey :: Text}
  deriving stock (Eq, Show)

data ObjectRef = ObjectRef
  { objectBucket :: BucketName
  , objectKey :: ObjectKey
  }
  deriving stock (Eq, Show)

newtype TopicName = TopicName {unTopicName :: Text}
  deriving stock (Eq, Show)

newtype ImageRef = ImageRef {unImageRef :: Text}
  deriving stock (Eq, Show)

newtype KubeResource = KubeResource {unKubeResource :: Text}
  deriving stock (Eq, Show)

class (Monad m) => HasMinIO m where
  minioPutIfAbsent :: ObjectRef -> Text -> m (Either ServiceError ObjectRef)
  minioReadObject :: ObjectRef -> m (Either ServiceError Text)

class (Monad m) => HasPulsar m where
  pulsarPublish :: TopicName -> Text -> m (Either ServiceError Text)
  pulsarAcknowledge :: TopicName -> Text -> m (Either ServiceError ())

class (Monad m) => HasHarbor m where
  harborImageExists :: ImageRef -> m (Either ServiceError Bool)
  harborPromoteImage :: ImageRef -> ImageRef -> m (Either ServiceError ImageRef)

class (Monad m) => HasKubectl m where
  kubectlApply :: KubeResource -> Text -> m (Either ServiceError ())
  kubectlStatus :: KubeResource -> m (Either ServiceError Text)

capabilityNames :: [Text]
capabilityNames =
  [ "HasMinIO"
  , "HasPulsar"
  , "HasHarbor"
  , "HasKubectl"
  ]

renderCapabilitySurface :: Text
renderCapabilitySurface =
  Text.unlines capabilityNames
