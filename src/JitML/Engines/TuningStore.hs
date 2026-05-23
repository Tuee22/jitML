{-# LANGUAGE OverloadedStrings #-}

module JitML.Engines.TuningStore
  ( PersistedTuningSelection (..)
  , persistSelectedMeasuredTuning
  , readTuningSelection
  , tuningSelectionPath
  , writeTuningSelectionAtomic
  )
where

import Data.Aeson
  ( FromJSON (..)
  , ToJSON (..)
  , eitherDecode
  , encode
  , object
  , withObject
  , (.:)
  , (.=)
  )
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Text (Text)
import Data.Text qualified as Text
import System.Directory (createDirectoryIfMissing, doesFileExist, renameFile)
import System.FilePath (takeDirectory, (</>))

import JitML.Cache.Key qualified as Cache
import JitML.Engines.Tuning
  ( BenchmarkMeasurement (..)
  , BenchmarkPlan (..)
  , selectBenchmarkMeasurement
  , tuningChoiceForResult
  )
import JitML.Substrate (Substrate, parseSubstrate, renderSubstrate)

data PersistedTuningSelection = PersistedTuningSelection
  { persistedTuningSubstrate :: Substrate
  , persistedTuningBaseHash :: Cache.Hash
  , persistedTuningChoice :: Cache.TuningChoice
  , persistedTuningLatencyMicros :: Int
  , persistedTuningOutputDigest :: Text
  }
  deriving stock (Eq, Show)

persistSelectedMeasuredTuning
  :: FilePath
  -> Cache.Hash
  -> BenchmarkPlan
  -> [BenchmarkMeasurement]
  -> IO (Either Text PersistedTuningSelection)
persistSelectedMeasuredTuning buildRoot baseHash plan measurements =
  case selectBenchmarkMeasurement plan measurements of
    Left err ->
      pure (Left err)
    Right measurement -> do
      let selection = persistedSelection baseHash measurement
      _ <- writeTuningSelectionAtomic buildRoot selection
      pure (Right selection)
 where
  persistedSelection selectedBaseHash measurement =
    PersistedTuningSelection
      { persistedTuningSubstrate = benchmarkPlanSubstrate plan
      , persistedTuningBaseHash = selectedBaseHash
      , persistedTuningChoice = tuningChoiceForResult (benchmarkMeasurementResult measurement)
      , persistedTuningLatencyMicros = benchmarkMeasurementLatencyMicros measurement
      , persistedTuningOutputDigest = benchmarkMeasurementOutputDigest measurement
      }

readTuningSelection
  :: FilePath
  -> Substrate
  -> Cache.Hash
  -> IO (Either Text (Maybe PersistedTuningSelection))
readTuningSelection buildRoot substrate baseHash = do
  let path = tuningSelectionPath buildRoot substrate baseHash
  exists <- doesFileExist path
  if exists
    then do
      decoded <- eitherDecode <$> LazyByteString.readFile path
      pure $
        case decoded of
          Left err -> Left ("invalid persisted tuning selection: " <> Text.pack err)
          Right selection -> validateSelection selection
    else pure (Right Nothing)
 where
  validateSelection selection
    | persistedTuningSubstrate selection /= substrate =
        Left
          ( "persisted tuning selection substrate mismatch: expected "
              <> renderSubstrate substrate
              <> ", found "
              <> renderSubstrate (persistedTuningSubstrate selection)
          )
    | persistedTuningBaseHash selection /= baseHash =
        Left
          ( "persisted tuning selection base hash mismatch: expected "
              <> Cache.hashHex baseHash
              <> ", found "
              <> Cache.hashHex (persistedTuningBaseHash selection)
          )
    | otherwise =
        Right (Just selection)

writeTuningSelectionAtomic :: FilePath -> PersistedTuningSelection -> IO FilePath
writeTuningSelectionAtomic buildRoot selection = do
  let path =
        tuningSelectionPath
          buildRoot
          (persistedTuningSubstrate selection)
          (persistedTuningBaseHash selection)
      tmpPath = path <> ".tmp"
  createDirectoryIfMissing True (takeDirectory path)
  LazyByteString.writeFile tmpPath (encode selection)
  renameFile tmpPath path
  pure path

tuningSelectionPath :: FilePath -> Substrate -> Cache.Hash -> FilePath
tuningSelectionPath buildRoot substrate baseHash =
  buildRoot
    </> "jit"
    </> "tuning"
    </> Text.unpack (renderSubstrate substrate)
    </> Text.unpack (Cache.hashHex baseHash)
    <> ".json"

instance ToJSON PersistedTuningSelection where
  toJSON selection =
    object
      [ "substrate" .= renderSubstrate (persistedTuningSubstrate selection)
      , "baseHash" .= persistedTuningBaseHash selection
      , "choice" .= persistedTuningChoice selection
      , "latencyMicros" .= persistedTuningLatencyMicros selection
      , "outputDigest" .= persistedTuningOutputDigest selection
      ]

instance FromJSON PersistedTuningSelection where
  parseJSON =
    withObject "PersistedTuningSelection" $ \record -> do
      substrateText <- record .: "substrate"
      substrate <-
        maybe
          (fail ("unknown persisted tuning substrate: " <> Text.unpack substrateText))
          pure
          (parseSubstrate substrateText)
      baseHash <- record .: "baseHash"
      choice <- record .: "choice"
      latencyMicros <- record .: "latencyMicros"
      outputDigest <- record .: "outputDigest"
      pure $
        PersistedTuningSelection
          substrate
          baseHash
          choice
          latencyMicros
          outputDigest
