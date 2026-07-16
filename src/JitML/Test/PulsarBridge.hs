{-# LANGUAGE OverloadedStrings #-}

module JitML.Test.PulsarBridge
  ( pulsarBridgeTests
  )
where

import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.Foldable (traverse_)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Service.Pulsar.Bridge
  ( BridgeCodecError (..)
  , BridgeErrorScope (..)
  , BridgeState
  , BridgeStateError (..)
  , ChildFrame (..)
  , ParentCommand (..)
  , Settlement (..)
  , SettlementKind (..)
  , applyChildFrame
  , applyParentCommand
  , bridgeTrackedReceiptCount
  , decodeChildFrame
  , decodeParentCommand
  , emptyBridgeState
  , encodeChildFrame
  , encodeParentCommand
  )
import JitML.Service.Pulsar.Internal (DeliveryReceipt (..))

pulsarBridgeTests :: TestTree
pulsarBridgeTests =
  testGroup
    "PulsarBridge"
    [ testCase "child frames round trip through versioned NDJSON" $ do
        traverse_ assertChildRoundTrip childFrames
        traverse_
          (assertBool "child frame must end in one NDJSON newline" . hasNdjsonTerminator . encodeChildFrame)
          childFrames
    , testCase "parent commands round trip through versioned NDJSON" $ do
        traverse_ assertParentRoundTrip parentCommands
        traverse_
          ( assertBool "parent command must end in one NDJSON newline"
              . hasNdjsonTerminator
              . encodeParentCommand
          )
          parentCommands
    , testCase "wrong versions and unknown message types are rejected" $ do
        decodeChildFrame "{\"version\":2,\"type\":\"drained\"}\n"
          @?= Left (UnsupportedBridgeVersion 2)
        decodeChildFrame "{\"version\":1,\"type\":\"surprise\"}\n"
          @?= Left (UnknownBridgeMessageType "surprise")
        decodeParentCommand "{\"version\":1,\"type\":\"connected\",\"generation\":1}\n"
          @?= Left (UnknownBridgeMessageType "connected")
    , testCase "invalid base64, redelivery counts, and receipt ids are rejected" $ do
        assertInvalidChildMessage invalidBase64Delivery
        assertInvalidChildMessage negativeRedeliveryDelivery
        assertInvalidChildMessage emptySessionDelivery
        assertInvalidChildMessage emptyDeliveryIdDelivery
    , testCase "duplicate, opposite, and unknown settlement are rejected" $
        withDeliveredReceipt receipt1 $ \delivered -> do
          let requested = applyParentCommand delivered (Settle receipt1 Ack)
          expectRight requested $ \settlementPending -> do
            applyParentCommand settlementPending (Settle receipt1 Ack)
              @?= Left (DuplicateSettlement receipt1 AckKind)
            applyParentCommand settlementPending (Settle receipt1 (Nack "retry"))
              @?= Left (OppositeSettlement receipt1 AckKind NackKind)
            applyParentCommand settlementPending (Settle unknownReceipt Ack)
              @?= Left (UnknownReceipt unknownReceipt)
            applyChildFrame settlementPending (Settled receipt1 NackKind)
              @?= Left (OppositeSettlement receipt1 AckKind NackKind)
    , testCase "reconnect retains pending old-generation settlement and drain state" $
        withDeliveredReceipt receipt1 $ \delivered ->
          expectRight (applyParentCommand delivered (Settle receipt1 Ack)) $ \settlementPending ->
            expectRight (applyParentCommand settlementPending Drain) $ \draining ->
              expectRight (applyChildFrame draining (Connected 2)) $ \reconnected -> do
                applyChildFrame reconnected (Delivery receipt2 "late" 0)
                  @?= Left (DeliveryAfterDrain receipt2)
                expectRight (applyChildFrame reconnected (Settled receipt1 AckKind)) $ \settled ->
                  expectRight (applyChildFrame settled Drained) (const (pure ()))
    , testCase "drain waits for settlement confirmation" $
        withDeliveredReceipt receipt1 $ \delivered ->
          expectRight (applyParentCommand delivered (Settle receipt1 Ack)) $ \settlementPending ->
            expectRight (applyParentCommand settlementPending Drain) $ \draining -> do
              applyChildFrame draining Drained
                @?= Left (DrainWithUnsettledReceipts [receipt1])
              expectRight (applyChildFrame draining (Settled receipt1 AckKind)) $ \settled ->
                expectRight (applyChildFrame settled Drained) (const (pure ()))
    , testCase "multiple hidden receipts are tracked and settled independently" $
        expectRight (applyChildFrame emptyBridgeState (Connected 1)) $ \connected ->
          expectRight (applyParentCommand connected (Permit 1)) $ \permitted ->
            expectRight (applyChildFrame permitted (Delivery receipt1 "first" 0)) $ \first ->
              expectRight (applyChildFrame first (Delivery receiptSameGeneration2 "second" 0)) $ \second -> do
                bridgeTrackedReceiptCount second @?= 2
                expectRight (applyParentCommand second (Settle receipt1 Ack)) $ \firstRequested ->
                  expectRight
                    (applyParentCommand firstRequested (Settle receiptSameGeneration2 Ack))
                    $ \bothRequested ->
                      expectRight (applyChildFrame bothRequested (Settled receipt1 AckKind)) $ \oneLeft -> do
                        bridgeTrackedReceiptCount oneLeft @?= 1
                        expectRight
                          (applyChildFrame oneLeft (Settled receiptSameGeneration2 AckKind))
                          $ \settled -> bridgeTrackedReceiptCount settled @?= 0
    , testCase "a delivery racing an outstanding permit after drain is still settled exactly once" $
        expectRight (applyChildFrame emptyBridgeState (Connected 1)) $ \connected ->
          expectRight (applyParentCommand connected (Permit 1)) $ \permitted ->
            expectRight (applyParentCommand permitted Drain) $ \draining ->
              expectRight (applyChildFrame draining (Delivery receipt1 "raced" 0)) $ \delivered ->
                expectRight (applyParentCommand delivered (Settle receipt1 (Nack "drain-requested"))) $
                  \requested ->
                    expectRight (applyChildFrame requested (Settled receipt1 NackKind)) $ \settled ->
                      expectRight (applyChildFrame settled Drained) $ \drained ->
                        bridgeTrackedReceiptCount drained @?= 0
    , testCase "confirmed receipts are pruned across many sequential cycles" $
        expectRight (applyChildFrame emptyBridgeState (Connected 1)) $ \connected ->
          expectRight (foldl' settleCycle (Right (connected, 0)) [1 .. receiptCycleCount]) $
            \(settledState, maximumTracked) -> do
              bridgeTrackedReceiptCount settledState @?= 0
              maximumTracked @?= 1
              let finalReceipt = receipt "session-1" 1 "delivery-final"
              expectRight (applyChildFrame settledState (Delivery finalReceipt "final" 0)) $ \delivered -> do
                bridgeTrackedReceiptCount delivered @?= 1
                expectRight (applyParentCommand delivered (Settle finalReceipt Ack)) $ \requested ->
                  expectRight (applyChildFrame requested (Settled finalReceipt AckKind)) $ \settled -> do
                    bridgeTrackedReceiptCount settled @?= 0
                    expectRight (applyParentCommand settled Drain) $ \draining ->
                      expectRight (applyChildFrame draining Drained) (const (pure ()))
    ]

settleCycle
  :: Either BridgeStateError (BridgeState, Int)
  -> Int
  -> Either BridgeStateError (BridgeState, Int)
settleCycle accumulated cycleNumber = do
  (state, previousMaximum) <- accumulated
  let cycleReceipt =
        receipt
          "session-1"
          1
          ("delivery-" <> Text.pack (show cycleNumber))
  delivered <- applyChildFrame state (Delivery cycleReceipt "payload" 0)
  requested <- applyParentCommand delivered (Settle cycleReceipt Ack)
  settled <- applyChildFrame requested (Settled cycleReceipt AckKind)
  pure
    ( settled
    , maximum
        [ previousMaximum
        , bridgeTrackedReceiptCount delivered
        , bridgeTrackedReceiptCount requested
        , bridgeTrackedReceiptCount settled
        ]
    )

receiptCycleCount :: Int
receiptCycleCount = 10000

childFrames :: [ChildFrame]
childFrames =
  [ Connected 1
  , Delivery receipt1 (ByteString.pack [0, 1, 2, 255]) 3
  , Settled receipt1 AckKind
  , Settled receipt1 NackKind
  , BridgeError ConnectionScope Nothing True "socket closed"
  , BridgeError SettlementScope (Just receipt1) False "retrying"
  , Drained
  ]

parentCommands :: [ParentCommand]
parentCommands =
  [ Permit 1
  , Settle receipt1 Ack
  , Settle receipt1 (Nack "decode rejected")
  , Drain
  ]

receipt1 :: DeliveryReceipt
receipt1 = receipt "session-1" 1 "delivery-1"

receipt2 :: DeliveryReceipt
receipt2 = receipt "session-1" 2 "delivery-2"

receiptSameGeneration2 :: DeliveryReceipt
receiptSameGeneration2 = receipt "session-1" 1 "delivery-2"

unknownReceipt :: DeliveryReceipt
unknownReceipt = receipt "session-1" 1 "unknown"

receipt :: Text -> Word64 -> Text -> DeliveryReceipt
receipt session generation deliveryId =
  DeliveryReceipt
    { receiptSessionInternal = session
    , receiptGenerationInternal = generation
    , receiptDeliveryIdInternal = deliveryId
    }

assertChildRoundTrip :: ChildFrame -> Assertion
assertChildRoundTrip frame =
  decodeChildFrame (encodeChildFrame frame) @?= Right frame

assertParentRoundTrip :: ParentCommand -> Assertion
assertParentRoundTrip command =
  decodeParentCommand (encodeParentCommand command) @?= Right command

hasNdjsonTerminator :: ByteString -> Bool
hasNdjsonTerminator bytes =
  not (ByteString.null bytes) && ByteString.last bytes == 10

assertInvalidChildMessage :: ByteString -> Assertion
assertInvalidChildMessage encoded =
  case decodeChildFrame encoded of
    Left (InvalidBridgeMessage _) -> pure ()
    result -> assertFailure ("expected InvalidBridgeMessage, got " <> show result)

withDeliveredReceipt
  :: DeliveryReceipt
  -> (BridgeState -> Assertion)
  -> Assertion
withDeliveredReceipt deliveryReceipt assertion =
  expectRight (applyChildFrame emptyBridgeState (Connected 1)) $ \connected ->
    expectRight (applyChildFrame connected (Delivery deliveryReceipt "payload" 0)) assertion

expectRight :: (Show err) => Either err value -> (value -> Assertion) -> Assertion
expectRight result assertion =
  case result of
    Left err -> assertFailure ("expected Right, got Left " <> show err)
    Right value -> assertion value

invalidBase64Delivery :: ByteString
invalidBase64Delivery =
  "{\"version\":1,\"type\":\"delivery\",\"receipt\":{\"session\":\"s\",\"generation\":1,\"deliveryId\":\"d\"},\"payloadBase64\":\"%%%\",\"redeliveryCount\":0}\n"

negativeRedeliveryDelivery :: ByteString
negativeRedeliveryDelivery =
  "{\"version\":1,\"type\":\"delivery\",\"receipt\":{\"session\":\"s\",\"generation\":1,\"deliveryId\":\"d\"},\"payloadBase64\":\"\",\"redeliveryCount\":-1}\n"

emptySessionDelivery :: ByteString
emptySessionDelivery =
  "{\"version\":1,\"type\":\"delivery\",\"receipt\":{\"session\":\"\",\"generation\":1,\"deliveryId\":\"d\"},\"payloadBase64\":\"\",\"redeliveryCount\":0}\n"

emptyDeliveryIdDelivery :: ByteString
emptyDeliveryIdDelivery =
  "{\"version\":1,\"type\":\"delivery\",\"receipt\":{\"session\":\"s\",\"generation\":1,\"deliveryId\":\"\"},\"payloadBase64\":\"\",\"redeliveryCount\":0}\n"
