{-# LANGUAGE GADTs #-}

-- | Package-internal constructors for the receipt-bound Pulsar contract.
-- Public callers receive these types abstractly from
-- "JitML.Service.Capabilities"; only the transport interpreter can mint broker
-- receipts or deliveries.
module JitML.Service.Pulsar.Internal
  ( Subscription (..)
  , SubscriptionStart (..)
  , SubscriptionOwnership (..)
  , DeliveryReceipt (..)
  , Delivery (..)
  , DeliveryBatch (..)
  , NackReason (..)
  , Disposition (..)
  , ConsumerDecision (..)
  , ConsumerBatchDecision (..)
  , ConsumerSessionEvent (..)
  , ConsumerFailure (..)
  )
where

import Data.List.NonEmpty (NonEmpty)
import Data.Text (Text)
import Data.Word (Word64)

import JitML.Coordinator.Topology (Topic, TopicDecodeError)
import JitML.Service.InferenceBatch (BatchWindow)
import JitML.Service.Retry (ServiceError)
import JitML.Sub.Outcome (ProcessFailure, ProcessOutcome, ProcessTranscript)

data SubscriptionStart
  = FromEarliest
  | FromLatest
  deriving stock (Eq, Show)

data SubscriptionOwnership
  = Borrowed
  | Owned
  deriving stock (Eq, Show)

data Subscription event = Subscription
  { subscriptionTopicInternal :: Topic event
  , subscriptionNameInternal :: Text
  , subscriptionStartInternal :: SubscriptionStart
  , subscriptionOwnershipInternal :: SubscriptionOwnership
  }
  deriving stock (Eq, Show)

-- | Session-scoped bridge receipt. The Node bridge keeps the broker message id
-- exclusively in its private receipt-token map; Haskell only receives the
-- session, generation, and opaque delivery token needed to request settlement.
data DeliveryReceipt = DeliveryReceipt
  { receiptSessionInternal :: Text
  , receiptGenerationInternal :: Word64
  , receiptDeliveryIdInternal :: Text
  }
  deriving stock (Eq)

instance Show DeliveryReceipt where
  showsPrec precedence _receipt =
    showParen (precedence > 10) (showString "DeliveryReceipt <opaque>")

data Delivery event = Delivery
  { deliveryEventInternal :: event
  , deliveryReceiptInternal :: DeliveryReceipt
  , deliveryRedeliveryCountInternal :: Int
  }
  deriving stock (Eq, Show)

-- | A transport-owned group of decoded deliveries.  The public capability
-- exposes only the events, counts, and redelivery metadata; receipt tokens
-- remain inside the interpreter until one positional disposition is supplied
-- for every member.
data DeliveryBatch event = DeliveryBatch
  { deliveryBatchWindowInternal :: BatchWindow
  , deliveryBatchInternal :: NonEmpty (Delivery event)
  }
  deriving stock (Eq, Show)

data NackReason
  = DecodeRejected Text
  | HandlerRejected Text
  | RetryRequested Text
  | DrainRequested
  deriving stock (Eq, Show)

data Disposition
  = AckInternal
  | NackInternal NackReason
  deriving stock (Eq, Show)

-- | Every handled delivery has exactly one disposition.  @Done@ settles the
-- current delivery before draining and returning the result.
data ConsumerDecision result
  = ContinueInternal Disposition
  | DoneInternal Disposition result
  deriving stock (Eq, Show)

-- | One disposition applied by the interpreter to every hidden receipt in the
-- compatible batch.  This makes omission and duplicate settlement
-- unrepresentable at the handler boundary.
data ConsumerBatchDecision result
  = ContinueBatchInternal Disposition
  | DoneBatchInternal Disposition result
  deriving stock (Eq, Show)

-- | Observable connection lifecycle for readiness and diagnostics.  The
-- broker message id is intentionally absent; it remains private to the Node
-- bridge's receipt map.
data ConsumerSessionEvent
  = ConsumerSessionConnected Word64
  | ConsumerSessionDisconnected Text
  | ConsumerSessionDraining
  | ConsumerSessionDrained
  deriving stock (Eq, Show)

data ConsumerFailure
  = ConsumerDecodeFailure TopicDecodeError
  | ConsumerHandlerFailure Text
  | ConsumerPermitFailure ServiceError
  | ConsumerSettlementFailure Text ServiceError
  | ConsumerProtocolFailure Text
  | ConsumerTransportFailure ProcessFailure
  | ConsumerTransportContextFailure ConsumerFailure ProcessFailure
  | ConsumerTransportExited ProcessTranscript
  | ConsumerPipedActionFailure Text ProcessOutcome
  | ConsumerCleanupFailure ServiceError
  | ConsumerCleanupContextFailure ConsumerFailure ServiceError
  deriving stock (Eq, Show)
