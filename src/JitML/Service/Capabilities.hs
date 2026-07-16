{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.Capabilities
  ( BucketName (..)
  , ETag (..)
  , ImageRef (..)
  , KubeResource (..)
  , ObjectKey (..)
  , ObjectRef (..)
  , Subscription
  , SubscriptionStart (..)
  , SubscriptionOwnership (..)
  , SubscriptionError (..)
  , mkSubscription
  , subscriptionTopic
  , subscriptionName
  , subscriptionStart
  , subscriptionOwnership
  , Delivery
  , DeliveryReceipt
  , deliveryEvent
  , deliveryReceipt
  , deliveryReceiptFingerprint
  , deliveryRedeliveryCount
  , DeliveryBatch
  , deliveryBatchEvents
  , deliveryBatchRedeliveryCounts
  , deliveryBatchSize
  , deliveryBatchWindow
  , mapDeliveryBatch
  , NackReason (..)
  , Disposition
  , ack
  , nack
  , ConsumerDecision
  , ConsumerSessionEvent (..)
  , continue
  , done
  , ConsumerBatchDecision
  , continueBatch
  , doneBatch
  , ConsumerFailure (..)
  , HasHarbor (..)
  , HasKubectl (..)
  , HasMinIO (..)
  , HasPulsar (..)
  , capabilityNames
  , renderCapabilitySurface
  )
where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified
import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import GHC.Clock (getMonotonicTimeNSec)

import JitML.Coordinator.Topology (Topic)
import JitML.Service.InferenceBatch
  ( BatchPolicy
  , BatchWindow
  , batchWindow
  , openBatch
  )
import JitML.Service.Pulsar.Internal
  ( ConsumerBatchDecision (..)
  , ConsumerDecision (..)
  , ConsumerFailure (..)
  , ConsumerSessionEvent (..)
  , Delivery (..)
  , DeliveryBatch (..)
  , DeliveryReceipt (..)
  , Disposition (..)
  , NackReason (..)
  , Subscription (..)
  , SubscriptionOwnership (..)
  , SubscriptionStart (..)
  )
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

newtype ImageRef = ImageRef {unImageRef :: Text}
  deriving stock (Eq, Show)

newtype KubeResource = KubeResource {unKubeResource :: Text}
  deriving stock (Eq, Show)

newtype ETag = ETag {unETag :: Text}
  deriving stock (Eq, Show)

data SubscriptionError
  = EmptySubscriptionName
  | SubscriptionNameTooLong Int
  | InvalidSubscriptionNameCharacter Char
  deriving stock (Eq, Show)

mkSubscription
  :: Topic event
  -> Text
  -> SubscriptionStart
  -> SubscriptionOwnership
  -> Either SubscriptionError (Subscription event)
mkSubscription topic rawName start ownership = do
  let name = Text.strip rawName
  if Text.null name
    then Left EmptySubscriptionName
    else Right ()
  if Text.length name > 128
    then Left (SubscriptionNameTooLong (Text.length name))
    else Right ()
  case Text.find (not . validSubscriptionCharacter) name of
    Just character -> Left (InvalidSubscriptionNameCharacter character)
    Nothing ->
      Right
        Subscription
          { subscriptionTopicInternal = topic
          , subscriptionNameInternal = name
          , subscriptionStartInternal = start
          , subscriptionOwnershipInternal = ownership
          }
 where
  validSubscriptionCharacter character =
    isAsciiLower character
      || isAsciiUpper character
      || isDigit character
      || character `elem` ("._-" :: String)

subscriptionTopic :: Subscription event -> Topic event
subscriptionTopic = subscriptionTopicInternal

subscriptionName :: Subscription event -> Text
subscriptionName = subscriptionNameInternal

subscriptionStart :: Subscription event -> SubscriptionStart
subscriptionStart = subscriptionStartInternal

subscriptionOwnership :: Subscription event -> SubscriptionOwnership
subscriptionOwnership = subscriptionOwnershipInternal

deliveryEvent :: Delivery event -> event
deliveryEvent = deliveryEventInternal

deliveryReceipt :: Delivery event -> DeliveryReceipt
deliveryReceipt = deliveryReceiptInternal

deliveryRedeliveryCount :: Delivery event -> Int
deliveryRedeliveryCount = deliveryRedeliveryCountInternal

deliveryBatchEvents :: DeliveryBatch event -> NonEmpty event
deliveryBatchEvents = fmap deliveryEventInternal . deliveryBatchInternal

deliveryBatchRedeliveryCounts :: DeliveryBatch event -> NonEmpty Int
deliveryBatchRedeliveryCounts = fmap deliveryRedeliveryCountInternal . deliveryBatchInternal

deliveryBatchSize :: DeliveryBatch event -> Int
deliveryBatchSize = NonEmpty.length . deliveryBatchInternal

deliveryBatchWindow :: DeliveryBatch event -> BatchWindow
deliveryBatchWindow = deliveryBatchWindowInternal

-- | Transform decoded events while preserving the transport-owned receipt set
-- and admission window.  This is the safe existential-elimination seam used
-- by daemon subscriptions; receipt constructors remain inaccessible.
mapDeliveryBatch :: (event -> mapped) -> DeliveryBatch event -> DeliveryBatch mapped
mapDeliveryBatch transform (DeliveryBatch window deliveries) =
  DeliveryBatch window (fmap mapDelivery deliveries)
 where
  mapDelivery delivery =
    Delivery
      { deliveryEventInternal = transform (deliveryEventInternal delivery)
      , deliveryReceiptInternal = deliveryReceiptInternal delivery
      , deliveryRedeliveryCountInternal = deliveryRedeliveryCountInternal delivery
      }

-- | Stable diagnostic fingerprint of the Haskell-visible receipt token. The
-- broker message id remains exclusively in the Node bridge's private map.
deliveryReceiptFingerprint :: DeliveryReceipt -> Text
deliveryReceiptFingerprint receipt =
  Text.pack (concatMap byteHex (Data.ByteString.unpack (SHA256.hash bytes)))
 where
  bytes =
    Text.Encoding.encodeUtf8
      ( Text.intercalate
          ":"
          [ receiptSessionInternal receipt
          , Text.pack (show (receiptGenerationInternal receipt))
          , receiptDeliveryIdInternal receipt
          ]
      )
  byteHex byte =
    let digits = "0123456789abcdef"
        value = fromIntegral byte
     in [digits !! (value `div` 16), digits !! (value `mod` 16)]

ack :: Disposition
ack = AckInternal

nack :: NackReason -> Disposition
nack = NackInternal

continue :: Disposition -> ConsumerDecision result
continue = ContinueInternal

done :: Disposition -> result -> ConsumerDecision result
done = DoneInternal

continueBatch :: Disposition -> ConsumerBatchDecision result
continueBatch = ContinueBatchInternal

doneBatch :: Disposition -> result -> ConsumerBatchDecision result
doneBatch = DoneBatchInternal

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

-- | Receipt-bound Pulsar capability. Publication takes the event fixed by the
-- topic witness. Consumption is one scoped persistent session: the event codec
-- comes from that topic, the handler returns one disposition, and only the
-- interpreter can settle the private receipt.
class (MonadIO m) => HasPulsar m where
  pulsarPublish :: Topic event -> event -> m (Either ServiceError Text)
  pulsarConsumeUntil
    :: Subscription event
    -> (ConsumerSessionEvent -> m ())
    -> (Delivery event -> m (ConsumerDecision result))
    -> m (Either ConsumerFailure result)
  pulsarConsumeBatchesUntil
    :: (Eq key)
    => m BatchPolicy
    -> (event -> key)
    -> Subscription event
    -> (ConsumerSessionEvent -> m ())
    -> (DeliveryBatch event -> m (ConsumerBatchDecision result))
    -> m (Either ConsumerFailure result)
  pulsarConsumeBatchesUntil readPolicy _compatibilityKey subscription observe handler =
    pulsarConsumeUntil subscription observe $ \delivery -> do
      policySnapshot <- readPolicy
      admittedAt <- liftIO getMonotonicTimeNSec
      let window = batchWindow (openBatch admittedAt policySnapshot () delivery)
      decision <- handler (DeliveryBatch window (delivery :| []))
      pure $
        case decision of
          ContinueBatchInternal disposition -> ContinueInternal disposition
          DoneBatchInternal disposition result -> DoneInternal disposition result

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
