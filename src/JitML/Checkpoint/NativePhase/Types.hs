{-# LANGUAGE OverloadedStrings #-}

-- | Ordinary wire DATA only. Digests and checked graphs confer no authority.
module JitML.Checkpoint.NativePhase.Types
  ( Digest
  , mkDigest
  , digestBytes
  , hashBytes
  , NodeKind (..)
  , nodeTag
  , nodeKindFromTag
  , allNodeKinds
  , NodeAlias (..)
  , aliasTag
  , aliasFromTag
  , aliasKinds
  , ScalarKind (..)
  , scalarTag
  , scalarFromTag
  , ElementKind (..)
  , PhaseTag (..)
  , phaseTag
  , phaseFromTag
  , NodeValue (..)
  , Resource (..)
  , nativePhaseLimit
  , resourceTag
  , resourceFromTag
  , CodecError (..)
  , GraphUsage (..)
  , emptyUsage
  , checkLimit
  , boundedLength
  , nativePhaseSafeFailureHeaderBytes
  ) where

import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Char (intToDigit)
import Data.Int (Int64)
import Data.Text (Text)
import Data.Word (Word64)

newtype Digest = Digest ByteString
  deriving stock (Eq, Ord)

instance Show Digest where
  show (Digest bytes) =
    concatMap
      (\b -> [intToDigit (fromIntegral b `div` 16), intToDigit (fromIntegral b `mod` 16)])
      (BS.unpack bytes)

mkDigest :: ByteString -> Either CodecError Digest
mkDigest bytes
  | BS.length bytes == 32 = Right (Digest bytes)
  | otherwise = Left (Malformed "digest must have exactly32 bytes")

digestBytes :: Digest -> ByteString
digestBytes (Digest value) = value

hashBytes :: ByteString -> Digest
hashBytes = Digest . SHA256.hash

data NodeKind
  = NTensorLeaf
  | NParams
  | NGradient
  | NAdam
  | NPVN
  | NTensorManifest
  | NTensorChunk
  | NSequenceManifest
  | NSequenceIndex
  | NReferencePage
  | NScalarPage
  | NGeneratorState
  | NProducerContextBundle
  | NRuntimeMetadata
  | NRecordedProducer
  | NPpoConfig
  | NDqnConfig
  | NQrConfig
  | NContinuousConfig
  | NHerConfig
  | NArsConfig
  | NPpoStat
  | NDqnStat
  | NQrStat
  | NContinuousStat
  | NHerStat
  | NArsStat
  | NArsPerturbation
  | NArsKeptDirection
  | NArsAppliedStep
  | NArsIterationObservation
  | NArsRuntime
  | NDiscreteReplay
  | NContinuousReplay
  | NPolicyValueSample
  | NStarted
  | NPpoSnapshot
  | NDqnSnapshot
  | NQrSnapshot
  | NContinuousSnapshot
  | NHerSnapshot
  | NArsSnapshot
  | NAlphaZeroSnapshot
  | NRawNeural
  | NRawArs
  | NRawAlphaZero
  | NReturnEvaluation
  | NHerEvaluation
  | NArenaEvaluation
  | NSafeFailure
  | NLowNeuralFailureFacts
  | NLowNeuralFailure
  | NReturnSpec
  | NReturnPolicy
  | NReturnEpisode
  | NReturnForward
  | NHerSpec
  | NHerGoalCase
  | NHerSchedule
  | NHerOutcome
  | NHerForward
  | NHerProgress
  | NArenaSpec
  | NArenaTape
  | NArenaInput
  | NArenaForward
  | NArenaSummary
  | NArenaDecision
  | NArenaEpisode
  | NArenaProgress
  | NGameState
  | NTapeEntry
  | NCommonEpisode
  deriving stock (Eq, Ord, Show, Enum, Bounded)

allNodeKinds :: [NodeKind]
allNodeKinds = [minBound .. maxBound]

nodeTag :: NodeKind -> Word64
nodeTag kind = case kind of
  NTensorLeaf -> 0
  NParams -> 1
  NGradient -> 2
  NAdam -> 3
  NPVN -> 4
  NTensorManifest -> 5
  NTensorChunk -> 6
  NSequenceManifest -> 7
  NSequenceIndex -> 8
  NReferencePage -> 9
  NScalarPage -> 10
  NGeneratorState -> 11
  NProducerContextBundle -> 12
  NRuntimeMetadata -> 13
  NRecordedProducer -> 14
  NPpoConfig -> 20
  NDqnConfig -> 21
  NQrConfig -> 22
  NContinuousConfig -> 23
  NHerConfig -> 24
  NArsConfig -> 25
  NPpoStat -> 30
  NDqnStat -> 31
  NQrStat -> 32
  NContinuousStat -> 33
  NHerStat -> 34
  NArsStat -> 35
  NArsPerturbation -> 40
  NArsKeptDirection -> 41
  NArsAppliedStep -> 42
  NArsIterationObservation -> 43
  NArsRuntime -> 44
  NDiscreteReplay -> 45
  NContinuousReplay -> 46
  NPolicyValueSample -> 47
  NStarted -> 50
  NPpoSnapshot -> 51
  NDqnSnapshot -> 52
  NQrSnapshot -> 53
  NContinuousSnapshot -> 54
  NHerSnapshot -> 55
  NArsSnapshot -> 56
  NAlphaZeroSnapshot -> 57
  NRawNeural -> 60
  NRawArs -> 61
  NRawAlphaZero -> 62
  NReturnEvaluation -> 70
  NHerEvaluation -> 71
  NArenaEvaluation -> 72
  NSafeFailure -> 73
  NLowNeuralFailureFacts -> 74
  NLowNeuralFailure -> 75
  NReturnSpec -> 80
  NReturnPolicy -> 81
  NReturnEpisode -> 82
  NReturnForward -> 83
  NHerSpec -> 84
  NHerGoalCase -> 85
  NHerSchedule -> 86
  NHerOutcome -> 87
  NHerForward -> 88
  NHerProgress -> 89
  NArenaSpec -> 90
  NArenaTape -> 91
  NArenaInput -> 92
  NArenaForward -> 93
  NArenaSummary -> 94
  NArenaDecision -> 95
  NArenaEpisode -> 96
  NArenaProgress -> 97
  NGameState -> 98
  NTapeEntry -> 99
  NCommonEpisode -> 100

nodeKindFromTag :: Word64 -> Either CodecError NodeKind
nodeKindFromTag tag = case tag of
  0 -> Right NTensorLeaf
  1 -> Right NParams
  2 -> Right NGradient
  3 -> Right NAdam
  4 -> Right NPVN
  5 -> Right NTensorManifest
  6 -> Right NTensorChunk
  7 -> Right NSequenceManifest
  8 -> Right NSequenceIndex
  9 -> Right NReferencePage
  10 -> Right NScalarPage
  11 -> Right NGeneratorState
  12 -> Right NProducerContextBundle
  13 -> Right NRuntimeMetadata
  14 -> Right NRecordedProducer
  20 -> Right NPpoConfig
  21 -> Right NDqnConfig
  22 -> Right NQrConfig
  23 -> Right NContinuousConfig
  24 -> Right NHerConfig
  25 -> Right NArsConfig
  30 -> Right NPpoStat
  31 -> Right NDqnStat
  32 -> Right NQrStat
  33 -> Right NContinuousStat
  34 -> Right NHerStat
  35 -> Right NArsStat
  40 -> Right NArsPerturbation
  41 -> Right NArsKeptDirection
  42 -> Right NArsAppliedStep
  43 -> Right NArsIterationObservation
  44 -> Right NArsRuntime
  45 -> Right NDiscreteReplay
  46 -> Right NContinuousReplay
  47 -> Right NPolicyValueSample
  50 -> Right NStarted
  51 -> Right NPpoSnapshot
  52 -> Right NDqnSnapshot
  53 -> Right NQrSnapshot
  54 -> Right NContinuousSnapshot
  55 -> Right NHerSnapshot
  56 -> Right NArsSnapshot
  57 -> Right NAlphaZeroSnapshot
  60 -> Right NRawNeural
  61 -> Right NRawArs
  62 -> Right NRawAlphaZero
  70 -> Right NReturnEvaluation
  71 -> Right NHerEvaluation
  72 -> Right NArenaEvaluation
  73 -> Right NSafeFailure
  74 -> Right NLowNeuralFailureFacts
  75 -> Right NLowNeuralFailure
  80 -> Right NReturnSpec
  81 -> Right NReturnPolicy
  82 -> Right NReturnEpisode
  83 -> Right NReturnForward
  84 -> Right NHerSpec
  85 -> Right NHerGoalCase
  86 -> Right NHerSchedule
  87 -> Right NHerOutcome
  88 -> Right NHerForward
  89 -> Right NHerProgress
  90 -> Right NArenaSpec
  91 -> Right NArenaTape
  92 -> Right NArenaInput
  93 -> Right NArenaForward
  94 -> Right NArenaSummary
  95 -> Right NArenaDecision
  96 -> Right NArenaEpisode
  97 -> Right NArenaProgress
  98 -> Right NGameState
  99 -> Right NTapeEntry
  100 -> Right NCommonEpisode
  _ -> Left (Malformed "unknown native phase node tag")

data NodeAlias
  = TensorAlias
  | NeuralConfigAlias
  | ReturnConfigAlias
  | NeuralStatAlias
  | ParamsOrTensorAlias
  | SnapshotAlias
  | RawReturnAlias
  | EvaluationAlias
  deriving stock (Eq, Ord, Show, Enum, Bounded)

aliasTag :: NodeAlias -> Word64
aliasTag = fromIntegral . fromEnum

aliasFromTag :: Word64 -> Either CodecError NodeAlias
aliasFromTag value
  | value <= 7 = Right (toEnum (fromIntegral value))
  | otherwise = Left (Malformed "unknown node alias")

aliasKinds :: NodeAlias -> [NodeKind]
aliasKinds value = case value of
  TensorAlias -> [NTensorLeaf, NTensorManifest]
  NeuralConfigAlias -> [NPpoConfig, NDqnConfig, NQrConfig, NContinuousConfig, NHerConfig]
  ReturnConfigAlias -> [NPpoConfig, NDqnConfig, NQrConfig, NContinuousConfig, NArsConfig]
  NeuralStatAlias -> [NPpoStat, NDqnStat, NQrStat, NContinuousStat, NHerStat]
  ParamsOrTensorAlias -> [NParams, NTensorLeaf, NTensorManifest]
  SnapshotAlias ->
    [ NPpoSnapshot
    , NDqnSnapshot
    , NQrSnapshot
    , NContinuousSnapshot
    , NHerSnapshot
    , NArsSnapshot
    , NAlphaZeroSnapshot
    ]
  RawReturnAlias -> [NRawNeural, NRawArs, NRawAlphaZero]
  EvaluationAlias -> [NReturnEvaluation, NHerEvaluation, NArenaEvaluation]

data ScalarKind = ScalarInt | ScalarBool | ScalarBits | ScalarCountTriple | ScalarSlotSummary
  deriving stock (Eq, Ord, Show, Enum, Bounded)

scalarTag :: ScalarKind -> Word64
scalarTag = fromIntegral . fromEnum

scalarFromTag :: Word64 -> Either CodecError ScalarKind
scalarFromTag value
  | value <= 4 = Right (toEnum (fromIntegral value))
  | otherwise = Left (Malformed "unknown scalar kind")

data ElementKind = RefElement !NodeKind | AliasElement !NodeAlias | ScalarElement !ScalarKind
  deriving stock (Eq, Ord, Show)

data PhaseTag
  = StartedPhase
  | ColdSnapshotPhase
  | EffectiveSnapshotPhase
  | InitialEvaluationPhase
  | RawReturnPhase
  | FinalEvaluationPhase
  | FailurePhase
  deriving stock (Eq, Ord, Show, Enum, Bounded)

phaseTag :: PhaseTag -> Word64
phaseTag = fromIntegral . fromEnum

phaseFromTag :: Word64 -> Either CodecError PhaseTag
phaseFromTag value
  | value <= 6 = Right (toEnum (fromIntegral value))
  | otherwise = Left (Malformed "unknown phase tag")

-- Lists are fixed-schema tuples or arrays of at most256 items, never expanded
-- logical sequences. F64 is a Word64 bit pattern, including NaN/signed zero.
data NodeValue
  = VWord !Word64
  | VInt !Int64
  | VBits !Word64
  | VBool !Bool
  | VText !Text
  | VBytes !ByteString
  | VDigest !Digest
  | VRef !Digest
  | VList ![NodeValue]
  | VNull
  deriving stock (Eq, Show)

data Resource
  = WholePayloadBytes
  | TensorChunkBytes
  | SequenceFanout
  | PerSequenceElements
  | AggregateSequenceElements
  | AggregateF64Coordinates
  | PoolNodes
  | TypedReferenceEdges
  | ReferenceDepth
  | ContextBytes
  | ProducerBundleBytes
  | GeneralTextBytes
  | PathTextBytes
  | ProducerComponentBytes
  | InvocationTextBytes
  | AssociationTextBytes
  | CompiledTransportBytes
  | SingletonTransportBytes
  | CohortTransportBytes
  | CohortFields
  | DiagnosticTextBytes
  | FrameBytes
  | IntegerMagnitudeBytes
  | NativeIntMinimum
  | NativeIntMaximum
  | ContinuousHeaderReservation
  deriving stock (Eq, Ord, Show, Enum, Bounded)

resourceTag :: Resource -> Word64
resourceTag = fromIntegral . fromEnum

resourceFromTag :: Word64 -> Either CodecError Resource
resourceFromTag value
  | value <= 25 = Right (toEnum (fromIntegral value))
  | otherwise = Left (Malformed "unknown resource kind")

-- One frozen source of limits, shared by schema, parser, builder and graph.
nativePhaseLimit :: Resource -> Integer
nativePhaseLimit value = case value of
  WholePayloadBytes -> 268435456
  TensorChunkBytes -> 1048576
  SequenceFanout -> 256
  PerSequenceElements -> 4000000
  AggregateSequenceElements -> 16777216
  AggregateF64Coordinates -> 33554432
  PoolNodes -> 1048576
  TypedReferenceEdges -> 4194304
  ReferenceDepth -> 14
  ContextBytes -> 2097152
  ProducerBundleBytes -> 16384
  GeneralTextBytes -> 1024
  PathTextBytes -> 4096
  ProducerComponentBytes -> 256
  InvocationTextBytes -> 8192
  AssociationTextBytes -> 131072
  CompiledTransportBytes -> 32768
  SingletonTransportBytes -> 32768
  CohortTransportBytes -> 1048576
  CohortFields -> 512
  DiagnosticTextBytes -> 1048576
  FrameBytes -> 8388608
  IntegerMagnitudeBytes -> 32
  NativeIntMinimum -> -9223372036854775808
  NativeIntMaximum -> 9223372036854775807
  ContinuousHeaderReservation -> 2048

-- Separate sizing reservation; it does not add a new ResourceKind wire tag.
nativePhaseSafeFailureHeaderBytes :: Integer
nativePhaseSafeFailureHeaderBytes = 8192

data CodecError
  = Malformed !Text
  | NonCanonical !Text
  | ResourceExceeded !Resource !Integer !Integer
  | UnexpectedEnd !Int
  | MissingReference !Digest
  | WrongReferenceType !Digest !Text
  | HashMismatch !Digest
  | DigestCollision !Digest
  | ReferenceCycle !Digest
  | UnreachablePoolMember !Digest
  deriving stock (Eq, Show)

data GraphUsage = GraphUsage
  { usageNodes :: !Integer
  , usageEdges :: !Integer
  , usageSequenceElements :: !Integer
  , usageF64Coordinates :: !Integer
  , usageReferenceDepth :: !Integer
  , usageEncodedBytes :: !Integer
  }
  deriving stock (Eq, Show)

emptyUsage :: GraphUsage
emptyUsage = GraphUsage 0 0 0 0 0 0

checkLimit :: Resource -> Integer -> Either CodecError ()
checkLimit resource actual
  | actual < 0 = Left (Malformed "negative resource observation")
  | actual > nativePhaseLimit resource =
      Left (ResourceExceeded resource (nativePhaseLimit resource) actual)
  | otherwise = Right ()

-- Stop after cap+1; never first length an unbounded supplied list.
boundedLength :: Resource -> Integer -> [a] -> Either CodecError Int
boundedLength resource cap values
  | cap < 0 || cap > nativePhaseLimit resource || cap > toInteger (maxBound :: Int) =
      Left (Malformed "invalid bounded-list limit")
  | otherwise = go 0 values
 where
  go count [] = Right count
  go count (_ : rest)
    | toInteger count >= cap = Left (ResourceExceeded resource cap (toInteger count + 1))
    | otherwise = go (count + 1) rest
