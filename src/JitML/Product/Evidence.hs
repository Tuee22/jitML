{-# LANGUAGE OverloadedStrings #-}

module JitML.Product.Evidence
  ( TrainingEvidence
  , attachDeviceExecutionWitness
  , attachRecordedArsHostReference
  , evidenceDatasetShaAtRead
  , evidenceDeviceWitness
  , evidenceExecutionProvenance
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
import Control.Monad (when)
import Data.ByteString qualified as ByteString
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import GHC.Generics (Generic)

import JitML.Product.ArsHostReference (ArsHostReference)
import JitML.Product.ArsHostReference qualified as ArsHostReference
import JitML.Product.ExecutionProvenance (ExecutionProvenance (..))

import JitML.Product.DeviceWitness
  ( DeviceExecutionWitness
  , RawDeviceExecutionWitness
  , deviceExecutionWitnessToRaw
  , refineRawDeviceExecutionWitness
  )

-- | Strict observations plus optional recorded execution provenance. This data
-- is not actual producer origin, physical admission or parent authentication.
-- The neural raw form is retained so legacy malformed witnesses keep their
-- existing fail-closed accessor/refinement path.
data StoredExecutionProvenance
  = StoredNeuralExecution !(Maybe RawDeviceExecutionWitness)
  | StoredArsHostExecution !ArsHostReference
  deriving stock (Eq, Ord, Show)

data TrainingEvidence = TrainingEvidence
  { trainingInitialWeightHashValue :: Text
  , trainingFinalWeightHashValue :: Text
  , trainingUpdateCountValue :: Word64
  , trainingDatasetShaAtReadValue :: Text
  , trainingExecutionProvenanceValue :: StoredExecutionProvenance
  }
  deriving stock (Eq, Generic, Ord, Show)

-- | Existing neural six/tag0 and historical pre-witness five/tag0 codecs
-- remain byte/behaviour compatible. Host six/tag1 embeds one canonical definite
-- byte string containing the lower canonical reference CBOR. This does not
-- strengthen the preexisting outer Evidence/CompletedTraining decoder globally.
instance Serialise TrainingEvidence where
  encode evidence =
    Encoding.encodeListLen 6
      <> Encoding.encodeWord
        ( case trainingExecutionProvenanceValue evidence of
            StoredNeuralExecution _ -> 0
            StoredArsHostExecution _ -> 1
        )
      <> Serialise.encode (trainingInitialWeightHashValue evidence)
      <> Serialise.encode (trainingFinalWeightHashValue evidence)
      <> Serialise.encode (trainingUpdateCountValue evidence)
      <> Serialise.encode (trainingDatasetShaAtReadValue evidence)
      <> case trainingExecutionProvenanceValue evidence of
        StoredNeuralExecution witness -> Serialise.encode witness
        StoredArsHostExecution reference -> Encoding.encodeBytes (ArsHostReference.encodeArsHostReference reference)

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
          <*> (StoredNeuralExecution <$> Serialise.decode)
      (5, 0) ->
        -- Historical honest absence. Current admission still rejects absence.
        TrainingEvidence
          <$> Serialise.decode
          <*> Serialise.decode
          <*> Serialise.decode
          <*> Serialise.decode
          <*> pure (StoredNeuralExecution Nothing)
      (6, 1) -> do
        initial <- Serialise.decode
        final <- Serialise.decode
        updates <- Serialise.decode
        dataset <- Serialise.decode
        encodedReference <- Decoding.decodeBytesCanonical
        when (ByteString.length encodedReference > 8192) $
          fail "TrainingEvidence: ARS host reference exceeds its byte limit"
        reference <-
          either
            (fail . Text.unpack . ("TrainingEvidence: ARS host reference rejected: " <>))
            pure
            (ArsHostReference.decodeArsHostReference encodedReference)
        pure (TrainingEvidence initial final updates dataset (StoredArsHostExecution reference))
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

-- | Checked recorded provenance only. Wire/refinement is not fresh execution.
-- Malformed neural payloads fail instead of degrading to honest absence.
evidenceExecutionProvenance
  :: TrainingEvidence
  -> Either Text (Maybe (ExecutionProvenance ArsHostReference))
evidenceExecutionProvenance evidence =
  case trainingExecutionProvenanceValue evidence of
    StoredNeuralExecution Nothing -> Right Nothing
    StoredNeuralExecution (Just raw) ->
      fmap (Just . NeuralDeviceExecution) (refineRawDeviceExecutionWitness raw)
    StoredArsHostExecution reference -> Right (Just (ArsHostLinearExecution reference))

-- | Preserve the neural-only API. Host is an explicit wrong kind, never absence
-- and never an invented device witness.
evidenceDeviceWitness :: TrainingEvidence -> Either Text (Maybe DeviceExecutionWitness)
evidenceDeviceWitness evidence = do
  recorded <- evidenceExecutionProvenance evidence
  case recorded of
    Nothing -> Right Nothing
    Just (NeuralDeviceExecution witness) -> Right (Just witness)
    Just (ArsHostLinearExecution _) ->
      Left
        "training evidence records ARS host linear execution and does not carry a neural device witness"

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
  case trainingExecutionProvenanceValue evidence of
    StoredArsHostExecution _ ->
      Left "training evidence is already bound to ARS host linear execution"
    StoredNeuralExecution (Just existing)
      | existing /= raw ->
          Left "training evidence is already bound to a different device execution witness"
      | otherwise -> Right evidence
    StoredNeuralExecution Nothing ->
      Right evidence {trainingExecutionProvenanceValue = StoredNeuralExecution (Just raw)}
 where
  raw = deviceExecutionWitnessToRaw witness

-- | Attach checked recorded host data, not actual-origin or admission authority.
-- No attachment can replace a different kind or a different recorded value.
attachRecordedArsHostReference
  :: ArsHostReference -> TrainingEvidence -> Either Text TrainingEvidence
attachRecordedArsHostReference reference evidence =
  case trainingExecutionProvenanceValue evidence of
    StoredNeuralExecution (Just _) ->
      Left "training evidence is already bound to neural device execution"
    StoredNeuralExecution Nothing ->
      Right evidence {trainingExecutionProvenanceValue = StoredArsHostExecution reference}
    StoredArsHostExecution existing
      | existing == reference -> Right evidence
      | otherwise -> Left "training evidence is already bound to a different ARS host reference"

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
          , trainingExecutionProvenanceValue = StoredNeuralExecution Nothing
          }
