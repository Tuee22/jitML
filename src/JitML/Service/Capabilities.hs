{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.Capabilities
  ( BucketName (..)
  , ETag (..)
  , ImageRef (..)
  , KubeResource (..)
  , ObjectKey (..)
  , ObjectRef (..)
  , SubscriptionId (..)
  , TopicName (..)
  , HasHarbor (..)
  , HasKubectl (..)
  , HasMinIO (..)
  , HasPulsar (..)
  , capabilityNames
  , renderCapabilitySurface
  )
where

import Data.ByteString qualified
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

newtype ETag = ETag {unETag :: Text}
  deriving stock (Eq, Show)

newtype SubscriptionId = SubscriptionId {unSubscriptionId :: Text}
  deriving stock (Eq, Show)

-- | MinIO conditional-write capability. `putBlobIfAbsent` returns
-- `Left SEConflict` when the server responds with `412` from
-- `If-None-Match: *`; `casPointer` issues an `If-Match: <etag>` PUT and
-- surfaces `412` as `SEConflict` so the caller's `retryServiceAction` harness
-- can back off per the typed `RetryPolicy`.
--
-- `minioReadObject` returns Text (lenient-decoded for binary safety); the
-- byte-faithful sibling `minioReadBytes` returns the raw `ByteString` and
-- is the right call for binary CBOR manifests / split-blob tensor payloads.
-- `putBlobBytesIfAbsent` is the byte-faithful PUT variant.
class (Monad m) => HasMinIO m where
  minioPutIfAbsent :: ObjectRef -> Text -> m (Either ServiceError ObjectRef)
  minioReadObject :: ObjectRef -> m (Either ServiceError Text)
  minioReadBytes :: ObjectRef -> m (Either ServiceError Data.ByteString.ByteString)
  putBlobIfAbsent :: ObjectRef -> Text -> m (Either ServiceError ETag)
  putBlobBytesIfAbsent :: ObjectRef -> Data.ByteString.ByteString -> m (Either ServiceError ETag)
  casPointer :: ObjectRef -> Maybe ETag -> Text -> m (Either ServiceError ETag)
  listObjects :: BucketName -> Text -> m (Either ServiceError [ObjectRef])
  deleteObject :: ObjectRef -> m (Either ServiceError ())

-- | Pulsar capability. `pulsarSubscribe` returns a typed `SubscriptionId`
-- naming the broker-side subscription cursor; `pulsarSeek` rewinds the cursor
-- to a known event id (used by at-least-once redelivery).
class (Monad m) => HasPulsar m where
  pulsarPublish :: TopicName -> Text -> m (Either ServiceError Text)
  pulsarAcknowledge :: TopicName -> Text -> m (Either ServiceError ())
  pulsarSubscribe :: TopicName -> Text -> m (Either ServiceError SubscriptionId)
  pulsarConsume :: SubscriptionId -> m (Either ServiceError (Text, Text))
  pulsarSeek :: SubscriptionId -> Text -> m (Either ServiceError ())

-- | Harbor capability. `harborPushImage` and `harborPullImage` exercise the
-- container-registry push/pull contract; `harborListImages` enumerates the
-- catalogue under a project.
class (Monad m) => HasHarbor m where
  harborImageExists :: ImageRef -> m (Either ServiceError Bool)
  harborPromoteImage :: ImageRef -> ImageRef -> m (Either ServiceError ImageRef)
  harborPushImage :: ImageRef -> m (Either ServiceError ETag)
  harborPullImage :: ImageRef -> m (Either ServiceError ETag)
  harborListImages :: Text -> m (Either ServiceError [ImageRef])

-- | kubectl capability. `kubectlGet` returns the live YAML/JSON shape of a
-- resource the cluster reports; `kubectlDelete` removes it through the typed
-- subprocess boundary.
class (Monad m) => HasKubectl m where
  kubectlApply :: KubeResource -> Text -> m (Either ServiceError ())
  kubectlStatus :: KubeResource -> m (Either ServiceError Text)
  kubectlGet :: KubeResource -> m (Either ServiceError Text)
  kubectlDelete :: KubeResource -> m (Either ServiceError ())

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
