-- | Explicit test-interpreter observations for the otherwise opaque
-- receipt-bound Pulsar contract. 'simulateDeliveryDecisionForTest' supplies a
-- fabricated 'Delivery' to a test handler, but that value and its
-- receipt carry no settlement operation. The returned value is only an inert
-- observation; a 'HasPulsar' interpreter remains the sole settlement authority.
module JitML.Test.Pulsar
  ( SyntheticDeliveryError (..)
  , ObservedDisposition (..)
  , ObservedDecision (..)
  , simulateDeliveryDecisionForTest
  , observeDisposition
  , observeDecision
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)

import JitML.Service.Capabilities
  ( ConsumerDecision
  , Delivery
  , Disposition
  , NackReason
  , deliveryReceipt
  , deliveryReceiptFingerprint
  )
import JitML.Service.Pulsar.Internal
  ( ConsumerDecision (..)
  , Delivery (..)
  , DeliveryReceipt (..)
  , Disposition (..)
  )

data SyntheticDeliveryError
  = EmptySyntheticSession
  | EmptySyntheticDeliveryId
  | NegativeSyntheticRedeliveryCount Int
  deriving stock (Eq, Show)

data ObservedDisposition
  = ObservedAck
  | ObservedNack NackReason
  deriving stock (Eq, Show)

data ObservedDecision result
  = ObservedContinue ObservedDisposition
  | ObservedDone ObservedDisposition result
  deriving stock (Eq, Show)

-- | Simulate decoding one valid broker delivery and observe the handler's
-- decision. This deliberately performs no Ack/Nack operation: synthetic
-- transport interpreters must apply the observed disposition themselves, just
-- as the production interpreter exclusively owns real settlement.
simulateDeliveryDecisionForTest
  :: (Monad m)
  => Text
  -> Word64
  -> Text
  -> Int
  -> event
  -> (Delivery event -> m (ConsumerDecision result))
  -> m (Either SyntheticDeliveryError (ObservedDecision result, Text))
simulateDeliveryDecisionForTest rawSession generation rawDeliveryId redeliveryCount event handler
  | Text.null session = pure (Left EmptySyntheticSession)
  | Text.null deliveryId = pure (Left EmptySyntheticDeliveryId)
  | redeliveryCount < 0 = pure (Left (NegativeSyntheticRedeliveryCount redeliveryCount))
  | otherwise = do
      let delivery =
            Delivery
              { deliveryEventInternal = event
              , deliveryReceiptInternal =
                  DeliveryReceipt
                    { receiptSessionInternal = session
                    , receiptGenerationInternal = generation
                    , receiptDeliveryIdInternal = deliveryId
                    }
              , deliveryRedeliveryCountInternal = redeliveryCount
              }
      decision <- handler delivery
      pure
        ( Right
            ( observeDecision decision
            , deliveryReceiptFingerprint (deliveryReceipt delivery)
            )
        )
 where
  session = Text.strip rawSession
  deliveryId = Text.strip rawDeliveryId

observeDisposition :: Disposition -> ObservedDisposition
observeDisposition disposition =
  case disposition of
    AckInternal -> ObservedAck
    NackInternal reason -> ObservedNack reason

observeDecision :: ConsumerDecision result -> ObservedDecision result
observeDecision decision =
  case decision of
    ContinueInternal disposition -> ObservedContinue (observeDisposition disposition)
    DoneInternal disposition result -> ObservedDone (observeDisposition disposition) result
