{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Product.Evidence
  ( TrainingEvidence
  , evidenceDatasetShaAtRead
  , evidenceFinalWeightHash
  , evidenceInitialWeightHash
  , evidenceUpdateCount
  , mkTrainingEvidence
  )
where

import Codec.Serialise (Serialise)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import GHC.Generics (Generic)

data TrainingEvidence = TrainingEvidence
  { evidenceInitialWeightHash :: Text
  , evidenceFinalWeightHash :: Text
  , evidenceUpdateCount :: Word64
  , evidenceDatasetShaAtRead :: Text
  }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (Serialise)

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
          { evidenceInitialWeightHash = initialHash
          , evidenceFinalWeightHash = finalHash
          , evidenceUpdateCount = updateCount
          , evidenceDatasetShaAtRead = datasetSha
          }
