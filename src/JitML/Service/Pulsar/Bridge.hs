{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PackageImports #-}

-- | Versioned NDJSON protocol shared with the persistent Pulsar bridge child.
-- This module is deliberately package-internal: public callers only see the
-- opaque receipt-bound capability in "JitML.Service.Capabilities".
module JitML.Service.Pulsar.Bridge
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
where

import Data.Aeson
  ( Value
  , eitherDecodeStrict'
  , encode
  , object
  , withObject
  , (.:)
  , (.:?)
  , (.=)
  )
import Data.Aeson.Types (Pair, Parser, parseEither)
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word64)
import "base64-bytestring" Data.ByteString.Base64 qualified as Base64

import JitML.Service.Pulsar.Internal (DeliveryReceipt (..))

bridgeProtocolVersion :: Int
bridgeProtocolVersion = 1

-- | Settlement requested by the parent. Negative acknowledgement carries the
-- reason into the bridge journal, while the child confirmation reports only
-- which broker operation completed.
data Settlement
  = Ack
  | Nack Text
  deriving stock (Eq, Show)

data SettlementKind
  = AckKind
  | NackKind
  deriving stock (Eq, Show)

-- | Closed ownership domains for child-reported failures. Unknown wire values
-- are rejected by the codec rather than becoming free-form routing strings.
data BridgeErrorScope
  = ConnectionScope
  | DeliveryScope
  | SettlementScope
  | ProtocolScope
  | DrainScope
  deriving stock (Eq, Show)

data ChildFrame
  = Connected Word64
  | Delivery DeliveryReceipt ByteString Int
  | Settled DeliveryReceipt SettlementKind
  | BridgeError BridgeErrorScope (Maybe DeliveryReceipt) Bool Text
  | Drained
  deriving stock (Eq, Show)

data ParentCommand
  = Permit Int
  | Settle DeliveryReceipt Settlement
  | Drain
  deriving stock (Eq, Show)

data BridgeCodecError
  = MalformedBridgeJson Text
  | UnsupportedBridgeVersion Int
  | UnknownBridgeMessageType Text
  | InvalidBridgeMessage Text
  deriving stock (Eq, Show)

data ReceiptState
  = AwaitingSettlement
  | SettlementRequested SettlementKind
  deriving stock (Eq, Show)

data DrainState
  = AcceptingDeliveries
  | DrainRequested
  | DrainConfirmed
  deriving stock (Eq, Show)

data BridgeState = BridgeState
  { bridgeGeneration :: Maybe Word64
  , bridgeReceipts :: [(DeliveryReceipt, ReceiptState)]
  , bridgeOutstandingPermits :: Int
  , bridgeDrainState :: DrainState
  }
  deriving stock (Eq, Show)

data BridgeStateError
  = DuplicateConnection Word64
  | StaleConnection Word64 Word64
  | DeliveryBeforeConnection DeliveryReceipt
  | DeliveryGenerationMismatch Word64 DeliveryReceipt
  | DuplicateDelivery DeliveryReceipt
  | DeliveryWhileUnsettled DeliveryReceipt DeliveryReceipt
  | DeliveryAfterDrain DeliveryReceipt
  | InvalidPermitCount Int
  | PermitAfterDrain
  | UnknownReceipt DeliveryReceipt
  | SettlementNotRequested DeliveryReceipt
  | DuplicateSettlement DeliveryReceipt SettlementKind
  | OppositeSettlement DeliveryReceipt SettlementKind SettlementKind
  | DuplicateDrain
  | DrainNotRequested
  | DrainWithUnsettledReceipts [DeliveryReceipt]
  | ErrorForUnknownReceipt DeliveryReceipt
  | EmptyReceiptSession
  | EmptyReceiptDeliveryId
  | NegativeRedeliveryCount Int
  deriving stock (Eq, Show)

emptyBridgeState :: BridgeState
emptyBridgeState =
  BridgeState
    { bridgeGeneration = Nothing
    , bridgeReceipts = []
    , bridgeOutstandingPermits = 0
    , bridgeDrainState = AcceptingDeliveries
    }

applyChildFrame :: BridgeState -> ChildFrame -> Either BridgeStateError BridgeState
applyChildFrame state frame =
  case frame of
    Connected generation -> connect generation
    Delivery receipt _payload redeliveryCount -> deliver receipt redeliveryCount
    Settled receipt confirmedKind -> confirmSettlement receipt confirmedKind
    BridgeError _scope maybeReceipt _fatal _message -> validateErrorReceipt maybeReceipt
    Drained -> confirmDrain
 where
  connect generation =
    case bridgeGeneration state of
      Nothing ->
        Right
          state
            { bridgeGeneration = Just generation
            , bridgeReceipts = []
            , bridgeOutstandingPermits = 0
            , bridgeDrainState = AcceptingDeliveries
            }
      Just current
        | generation == current -> Left (DuplicateConnection generation)
        | generation < current -> Left (StaleConnection current generation)
        | otherwise ->
            Right
              state
                { bridgeGeneration = Just generation
                , bridgeOutstandingPermits = 0
                }

  deliver receipt redeliveryCount =
    case bridgeGeneration state of
      Nothing -> Left (DeliveryBeforeConnection receipt)
      Just generation
        | bridgeDrainState state /= AcceptingDeliveries
            && not
              ( bridgeDrainState state == DrainRequested
                  && bridgeOutstandingPermits state > 0
              ) ->
            Left (DeliveryAfterDrain receipt)
        | Left err <- validateReceipt receipt -> Left err
        | redeliveryCount < 0 -> Left (NegativeRedeliveryCount redeliveryCount)
        | receiptGenerationInternal receipt /= generation ->
            Left (DeliveryGenerationMismatch generation receipt)
        | Just _ <- lookup receipt (bridgeReceipts state) -> Left (DuplicateDelivery receipt)
        | otherwise ->
            Right
              state
                { bridgeReceipts = (receipt, AwaitingSettlement) : bridgeReceipts state
                , bridgeOutstandingPermits = max 0 (bridgeOutstandingPermits state - 1)
                }

  confirmSettlement receipt observed =
    case lookup receipt (bridgeReceipts state) of
      Nothing -> Left (UnknownReceipt receipt)
      Just AwaitingSettlement -> Left (SettlementNotRequested receipt)
      Just (SettlementRequested expected)
        | expected /= observed -> Left (OppositeSettlement receipt expected observed)
        | otherwise -> Right (removeReceipt receipt state)

  validateErrorReceipt Nothing = Right state
  validateErrorReceipt (Just receipt)
    | Just _ <- lookup receipt (bridgeReceipts state) = Right state
    | otherwise = Left (ErrorForUnknownReceipt receipt)

  confirmDrain
    | bridgeDrainState state /= DrainRequested = Left DrainNotRequested
    | null trackedReceipts =
        Right
          state
            { bridgeOutstandingPermits = 0
            , bridgeDrainState = DrainConfirmed
            }
    | otherwise = Left (DrainWithUnsettledReceipts trackedReceipts)
   where
    trackedReceipts = fmap fst (bridgeReceipts state)

applyParentCommand :: BridgeState -> ParentCommand -> Either BridgeStateError BridgeState
applyParentCommand state command =
  case command of
    Permit count
      | count <= 0 -> Left (InvalidPermitCount count)
      | bridgeDrainState state /= AcceptingDeliveries -> Left PermitAfterDrain
      | otherwise ->
          Right
            state
              { bridgeOutstandingPermits = bridgeOutstandingPermits state + count
              }
    Settle receipt settlement -> requestSettlement receipt (settlementKind settlement)
    Drain
      | bridgeDrainState state == AcceptingDeliveries ->
          Right state {bridgeDrainState = DrainRequested}
      | otherwise -> Left DuplicateDrain
 where
  requestSettlement receipt requested =
    case lookup receipt (bridgeReceipts state) of
      Nothing -> Left (UnknownReceipt receipt)
      Just AwaitingSettlement ->
        Right (replaceReceiptState receipt (SettlementRequested requested) state)
      Just (SettlementRequested previous)
        | previous == requested -> Left (DuplicateSettlement receipt requested)
        | otherwise -> Left (OppositeSettlement receipt previous requested)

-- | Number of live receipts awaiting a parent decision or child settlement
-- confirmation. Confirmed receipts are pruned at the transition boundary.
bridgeTrackedReceiptCount :: BridgeState -> Int
bridgeTrackedReceiptCount = length . bridgeReceipts

encodeChildFrame :: ChildFrame -> ByteString
encodeChildFrame = encodeNdjson . childFrameValue

decodeChildFrame :: ByteString -> Either BridgeCodecError ChildFrame
decodeChildFrame input = do
  value <- decodeValue input
  messageType <- validateEnvelope value
  parser <-
    case messageType of
      "connected" -> Right parseConnected
      "delivery" -> Right parseDelivery
      "settled" -> Right parseSettled
      "bridge-error" -> Right parseBridgeError
      "drained" -> Right parseDrained
      unknown -> Left (UnknownBridgeMessageType unknown)
  first (InvalidBridgeMessage . Text.pack) (parseEither parser value)

encodeParentCommand :: ParentCommand -> ByteString
encodeParentCommand = encodeNdjson . parentCommandValue

decodeParentCommand :: ByteString -> Either BridgeCodecError ParentCommand
decodeParentCommand input = do
  value <- decodeValue input
  messageType <- validateEnvelope value
  parser <-
    case messageType of
      "permit" -> Right parsePermit
      "settle" -> Right parseSettle
      "drain" -> Right parseDrain
      unknown -> Left (UnknownBridgeMessageType unknown)
  first (InvalidBridgeMessage . Text.pack) (parseEither parser value)

childFrameValue :: ChildFrame -> Value
childFrameValue frame =
  case frame of
    Connected generation -> envelope "connected" ["generation" .= generation]
    Delivery receipt payload redeliveryCount ->
      envelope
        "delivery"
        [ "receipt" .= receiptValue receipt
        , "payloadBase64" .= Text.Encoding.decodeUtf8 (Base64.encode payload)
        , "redeliveryCount" .= redeliveryCount
        ]
    Settled receipt kind ->
      envelope
        "settled"
        [ "receipt" .= receiptValue receipt
        , "settlement" .= settlementKindText kind
        ]
    BridgeError scope receipt fatal message ->
      envelope
        "bridge-error"
        [ "scope" .= bridgeErrorScopeText scope
        , "receipt" .= fmap receiptValue receipt
        , "fatal" .= fatal
        , "message" .= message
        ]
    Drained -> envelope "drained" []

parentCommandValue :: ParentCommand -> Value
parentCommandValue command =
  case command of
    Permit count -> envelope "permit" ["permitMessages" .= count]
    Settle receipt settlement ->
      envelope
        "settle"
        [ "receipt" .= receiptValue receipt
        , "settlement" .= settlementValue settlement
        ]
    Drain -> envelope "drain" []

envelope :: Text -> [Pair] -> Value
envelope messageType fields =
  object (["version" .= bridgeProtocolVersion, "type" .= messageType] <> fields)

encodeNdjson :: Value -> ByteString
encodeNdjson value = LazyByteString.toStrict (encode value) <> "\n"

decodeValue :: ByteString -> Either BridgeCodecError Value
decodeValue = first (MalformedBridgeJson . Text.pack) . eitherDecodeStrict'

validateEnvelope :: Value -> Either BridgeCodecError Text
validateEnvelope value = do
  (version, messageType) <-
    first (InvalidBridgeMessage . Text.pack) (parseEither parseHeader value)
  if version == bridgeProtocolVersion
    then Right messageType
    else Left (UnsupportedBridgeVersion version)
 where
  parseHeader = withObject "bridge message" $ \objectValue ->
    (,) <$> objectValue .: "version" <*> objectValue .: "type"

parseConnected :: Value -> Parser ChildFrame
parseConnected = withObject "connected frame" $ \objectValue ->
  Connected <$> objectValue .: "generation"

parseDelivery :: Value -> Parser ChildFrame
parseDelivery = withObject "delivery frame" $ \objectValue -> do
  receipt <- objectValue .: "receipt" >>= parseReceipt
  encodedPayload <- objectValue .: "payloadBase64"
  payload <-
    either
      (fail . ("invalid payloadBase64: " <>))
      pure
      (Base64.decode (Text.Encoding.encodeUtf8 encodedPayload))
  redeliveryCount <- objectValue .: "redeliveryCount"
  if redeliveryCount < 0
    then fail "redeliveryCount must be non-negative"
    else pure (Delivery receipt payload redeliveryCount)

parseSettled :: Value -> Parser ChildFrame
parseSettled = withObject "settled frame" $ \objectValue ->
  Settled
    <$> (objectValue .: "receipt" >>= parseReceipt)
    <*> (objectValue .: "settlement" >>= parseSettlementKind)

parseBridgeError :: Value -> Parser ChildFrame
parseBridgeError = withObject "bridge-error frame" $ \objectValue ->
  BridgeError
    <$> (objectValue .: "scope" >>= parseBridgeErrorScope)
    <*> (objectValue .:? "receipt" >>= traverse parseReceipt)
    <*> objectValue .: "fatal"
    <*> objectValue .: "message"

parseDrained :: Value -> Parser ChildFrame
parseDrained = withObject "drained frame" (const (pure Drained))

parseSettle :: Value -> Parser ParentCommand
parseSettle = withObject "settle command" $ \objectValue ->
  Settle
    <$> (objectValue .: "receipt" >>= parseReceipt)
    <*> (objectValue .: "settlement" >>= parseSettlement)

parsePermit :: Value -> Parser ParentCommand
parsePermit = withObject "permit command" $ \objectValue -> do
  count <- objectValue .: "permitMessages"
  if count <= 0
    then fail "permitMessages must be positive"
    else pure (Permit count)

parseDrain :: Value -> Parser ParentCommand
parseDrain = withObject "drain command" (const (pure Drain))

settlementKind :: Settlement -> SettlementKind
settlementKind Ack = AckKind
settlementKind (Nack _) = NackKind

settlementKindText :: SettlementKind -> Text
settlementKindText AckKind = "ack"
settlementKindText NackKind = "nack"

parseSettlementKind :: Text -> Parser SettlementKind
parseSettlementKind "ack" = pure AckKind
parseSettlementKind "nack" = pure NackKind
parseSettlementKind unknown = fail ("unknown settlement kind: " <> show unknown)

bridgeErrorScopeText :: BridgeErrorScope -> Text
bridgeErrorScopeText ConnectionScope = "connection"
bridgeErrorScopeText DeliveryScope = "delivery"
bridgeErrorScopeText SettlementScope = "settlement"
bridgeErrorScopeText ProtocolScope = "protocol"
bridgeErrorScopeText DrainScope = "drain"

parseBridgeErrorScope :: Text -> Parser BridgeErrorScope
parseBridgeErrorScope "connection" = pure ConnectionScope
parseBridgeErrorScope "delivery" = pure DeliveryScope
parseBridgeErrorScope "settlement" = pure SettlementScope
parseBridgeErrorScope "protocol" = pure ProtocolScope
parseBridgeErrorScope "drain" = pure DrainScope
parseBridgeErrorScope unknown = fail ("unknown bridge error scope: " <> show unknown)

settlementValue :: Settlement -> Value
settlementValue settlement =
  case settlement of
    Ack -> object ["type" .= ("ack" :: Text)]
    Nack reason -> object ["type" .= ("nack" :: Text), "reason" .= reason]

parseSettlement :: Value -> Parser Settlement
parseSettlement = withObject "settlement" $ \objectValue -> do
  settlementType <- objectValue .: "type"
  case settlementType :: Text of
    "ack" -> pure Ack
    "nack" -> Nack <$> objectValue .: "reason"
    unknown -> fail ("unknown settlement type: " <> show unknown)

replaceReceiptState :: DeliveryReceipt -> ReceiptState -> BridgeState -> BridgeState
replaceReceiptState receipt replacement state =
  state
    { bridgeReceipts =
        fmap
          ( \entry@(candidate, _receiptState) ->
              if candidate == receipt then (candidate, replacement) else entry
          )
          (bridgeReceipts state)
    }

removeReceipt :: DeliveryReceipt -> BridgeState -> BridgeState
removeReceipt receipt state =
  state
    { bridgeReceipts =
        filter ((/= receipt) . fst) (bridgeReceipts state)
    }

receiptValue :: DeliveryReceipt -> Value
receiptValue receipt =
  object
    [ "session" .= receiptSessionInternal receipt
    , "generation" .= receiptGenerationInternal receipt
    , "deliveryId" .= receiptDeliveryIdInternal receipt
    ]

parseReceipt :: Value -> Parser DeliveryReceipt
parseReceipt = withObject "delivery receipt" $ \objectValue -> do
  receipt <-
    DeliveryReceipt
      <$> objectValue .: "session"
      <*> objectValue .: "generation"
      <*> objectValue .: "deliveryId"
  case validateReceipt receipt of
    Left EmptyReceiptSession -> fail "receipt session must be non-empty"
    Left EmptyReceiptDeliveryId -> fail "receipt deliveryId must be non-empty"
    Left _ -> fail "invalid receipt"
    Right () -> pure receipt

validateReceipt :: DeliveryReceipt -> Either BridgeStateError ()
validateReceipt receipt
  | Text.null (receiptSessionInternal receipt) = Left EmptyReceiptSession
  | Text.null (receiptDeliveryIdInternal receipt) = Left EmptyReceiptDeliveryId
  | otherwise = Right ()
