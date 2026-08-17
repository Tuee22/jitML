{-# LANGUAGE OverloadedStrings #-}

module JitML.Product.Evidence
  ( TrainingEvidence
  , attachDeviceExecutionWitness
  , evidenceDatasetShaAtRead
  , evidenceDeviceWitness
  , evidenceFinalWeightHash
  , evidenceInitialWeightHash
  , evidenceObservationsMatch
  , evidenceUpdateCount
  , mkTrainingEvidence
  )
where

import Codec.CBOR.Decoding qualified as Decoding
import Codec.CBOR.Encoding qualified as Encoding
import Codec.Serialise (Serialise (..))
import Codec.Serialise qualified as Serialise
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import GHC.Generics (Generic)

import JitML.Product.DeviceWitness
  ( DeviceExecutionWitness
  , RawDeviceExecutionWitness
  , deviceExecutionWitnessToRaw
  , refineRawDeviceExecutionWitness
  )

-- | Observed training evidence, optionally carrying the execution witness the
-- device call left behind.
--
-- The witness is 'Maybe' because RL replay fixtures and pure-reference training
-- legitimately produce evidence without a device dispatch. It is /not/ optional
-- where it matters: product-row checkpoint admission rejects a completion whose
-- evidence carries no witness, so every admitted product row's device-evidence
-- cell is minted from a real artifact rather than composed from its declaration.
data TrainingEvidence = TrainingEvidence
  { trainingInitialWeightHashValue :: Text
  , trainingFinalWeightHashValue :: Text
  , trainingUpdateCountValue :: Word64
  , trainingDatasetShaAtReadValue :: Text
  , trainingDeviceWitnessValue :: Maybe RawDeviceExecutionWitness
  }
  deriving stock (Eq, Generic, Ord, Show)

-- | Sprint `229.1` added 'trainingDeviceWitnessValue'. A checkpoint persisted
-- before that field decodes one element short, and a generic instance rejects
-- it with @Wrong number of fields: expected=6 got=5@ — a deserialise crash that
-- says nothing about why the artifact is inadmissible.
--
-- The decoder therefore accepts the pre-witness shape and fills the witness
-- with 'Nothing'. This does not weaken the contract: an evidence value carrying
-- no witness is exactly what checkpoint admission rejects, so a legacy
-- checkpoint now fails at the admission gate with a message naming the missing
-- device witness instead of failing at CBOR with a field count.
instance Serialise TrainingEvidence where
  encode evidence =
    Encoding.encodeListLen 6
      <> Encoding.encodeWord 0
      <> Serialise.encode (trainingInitialWeightHashValue evidence)
      <> Serialise.encode (trainingFinalWeightHashValue evidence)
      <> Serialise.encode (trainingUpdateCountValue evidence)
      <> Serialise.encode (trainingDatasetShaAtReadValue evidence)
      <> Serialise.encode (trainingDeviceWitnessValue evidence)

  decode = do
    listLen <- Decoding.decodeListLen
    tag <- Decoding.decodeWord
    case (listLen, tag) of
      (6, 0) ->
        TrainingEvidence
          <$> Serialise.decode
          <*> Serialise.decode
          <*> Serialise.decode
          <*> Serialise.decode
          <*> Serialise.decode
      (5, 0) ->
        -- Pre-witness shape: witnessless, and admission rejects it as such.
        TrainingEvidence
          <$> Serialise.decode
          <*> Serialise.decode
          <*> Serialise.decode
          <*> Serialise.decode
          <*> pure Nothing
      _ ->
        fail
          ( "TrainingEvidence: unsupported encoding (listLen="
              <> show listLen
              <> ", tag="
              <> show tag
              <> ")"
          )

-- Ordinary observations keep opaque evidence immutable to downstream code.
-- Exporting the record labels themselves would permit post-validation update.
evidenceInitialWeightHash :: TrainingEvidence -> Text
evidenceInitialWeightHash = trainingInitialWeightHashValue

evidenceFinalWeightHash :: TrainingEvidence -> Text
evidenceFinalWeightHash = trainingFinalWeightHashValue

evidenceUpdateCount :: TrainingEvidence -> Word64
evidenceUpdateCount = trainingUpdateCountValue

evidenceDatasetShaAtRead :: TrainingEvidence -> Text
evidenceDatasetShaAtRead = trainingDatasetShaAtReadValue

-- | The execution witness recorded for this evidence, refined back from the
-- wire.
--
-- @Right Nothing@ is an honest absence (pure-reference or replay training);
-- @Left@ is a stored witness that does not refine, which is a decode failure
-- rather than an absence, so a tampered journal row fails closed instead of
-- degrading to \"no device claimed\".
evidenceDeviceWitness :: TrainingEvidence -> Either Text (Maybe DeviceExecutionWitness)
evidenceDeviceWitness evidence =
  case trainingDeviceWitnessValue evidence of
    Nothing -> Right Nothing
    Just raw -> fmap Just (refineRawDeviceExecutionWitness raw)

-- | Compare two evidence values on their observations alone.
--
-- The checkpoint manifest stores the four observations but not the device
-- execution witness (the witness travels inside the embedded completion), so
-- the manifest-versus-completion cross-check has to compare what the manifest
-- actually carries. Comparing whole records here would report a mismatch for
-- every witnessed completion.
evidenceObservationsMatch :: TrainingEvidence -> TrainingEvidence -> Bool
evidenceObservationsMatch left right =
  observations left == observations right
 where
  observations evidence =
    ( trainingInitialWeightHashValue evidence
    , trainingFinalWeightHashValue evidence
    , trainingUpdateCountValue evidence
    , trainingDatasetShaAtReadValue evidence
    )

-- | Bind a device execution witness to observed evidence.
--
-- A witness cannot be replaced once bound: rebinding would let a second,
-- cheaper dispatch relabel the artifact a training run actually used.
attachDeviceExecutionWitness
  :: DeviceExecutionWitness -> TrainingEvidence -> Either Text TrainingEvidence
attachDeviceExecutionWitness witness evidence =
  case trainingDeviceWitnessValue evidence of
    Just existing
      | existing /= raw ->
          Left "training evidence is already bound to a different device execution witness"
      | otherwise -> Right evidence
    _ -> Right evidence {trainingDeviceWitnessValue = Just raw}
 where
  raw = deviceExecutionWitnessToRaw witness

mkTrainingEvidence
  :: Text
  -> Text
  -> Word64
  -> Text
  -> Either Text TrainingEvidence
mkTrainingEvidence initialHash finalHash updateCount datasetSha
  | Text.null (Text.strip initialHash) =
      Left "training evidence requires an initial weight hash"
  | Text.null (Text.strip finalHash) =
      Left "training evidence requires a final weight hash"
  | initialHash == finalHash =
      Left "training evidence requires weight movement"
  | updateCount == 0 =
      Left "training evidence requires a positive update count"
  | Text.null (Text.strip datasetSha) =
      Left "training evidence requires a dataset SHA observed at read"
  | otherwise =
      Right
        TrainingEvidence
          { trainingInitialWeightHashValue = initialHash
          , trainingFinalWeightHashValue = finalHash
          , trainingUpdateCountValue = updateCount
          , trainingDatasetShaAtReadValue = datasetSha
          , trainingDeviceWitnessValue = Nothing
          }
