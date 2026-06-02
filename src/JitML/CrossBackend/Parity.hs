{-# LANGUAGE OverloadedStrings #-}

module JitML.CrossBackend.Parity
  ( CrossBackendDrift (..)
  , CrossBackendReport (..)
  , CrossBackendReportBundle (..)
  , CrossBackendTensor (..)
  , WeightedCohortCase (..)
  , allDriftsPass
  , compareReportBundle
  , decodeCrossBackendReportBundle
  , encodeCrossBackendReportBundle
  , renderDriftSummary
  , runWeightedCohortForSubstrate
  , weightedCrossSubstrateCohort
  )
where

import Control.Monad (when)
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
import Data.Aeson.Types qualified as AesonTypes
import Data.ByteString.Lazy qualified as LazyByteString
import Data.List (find, tails)
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Codegen.KernelFamily (KernelFamily (..), familyName)
import JitML.Engines.CudaLocal qualified as Cuda
import JitML.Engines.Local qualified as Local
import JitML.Engines.MetalLocal qualified as Metal
import JitML.Engines.Tolerance qualified as Tolerance
import JitML.Env.Env (Env)
import JitML.Substrate (Substrate (..), parseSubstrate, renderSubstrate)

crossBackendReportVersion :: Int
crossBackendReportVersion = 1

crossBackendCohortName :: Text
crossBackendCohortName = "sprint-15.1-weighted"

data WeightedCohortCase = WeightedCohortCase
  { cohortFamily :: KernelFamily
  , cohortInput :: [Float]
  , cohortWeights :: [Float]
  }
  deriving stock (Eq, Show)

data CrossBackendTensor = CrossBackendTensor
  { tensorFamily :: KernelFamily
  , tensorInput :: [Float]
  , tensorWeights :: [Float]
  , tensorOutput :: [Float]
  }
  deriving stock (Eq, Show)

data CrossBackendReport = CrossBackendReport
  { reportSubstrate :: Substrate
  , reportTensors :: [CrossBackendTensor]
  }
  deriving stock (Eq, Show)

newtype CrossBackendReportBundle = CrossBackendReportBundle
  { bundleReports :: [CrossBackendReport]
  }
  deriving stock (Eq, Show)

data CrossBackendDrift = CrossBackendDrift
  { driftLeftSubstrate :: Substrate
  , driftRightSubstrate :: Substrate
  , driftFamily :: KernelFamily
  , driftObserved :: Double
  , driftBound :: Double
  , driftPassed :: Bool
  }
  deriving stock (Eq, Show)

instance ToJSON CrossBackendTensor where
  toJSON tensor =
    object
      [ "family" .= familyName (tensorFamily tensor)
      , "input" .= tensorInput tensor
      , "weights" .= tensorWeights tensor
      , "output" .= tensorOutput tensor
      ]

instance FromJSON CrossBackendTensor where
  parseJSON =
    withObject "CrossBackendTensor" $ \value -> do
      familyText <- value .: "family"
      family <- parseKernelFamily familyText
      CrossBackendTensor family
        <$> value .: "input"
        <*> value .: "weights"
        <*> value .: "output"

instance ToJSON CrossBackendReport where
  toJSON report =
    object
      [ "version" .= crossBackendReportVersion
      , "cohort" .= crossBackendCohortName
      , "substrate" .= renderSubstrate (reportSubstrate report)
      , "tensors" .= reportTensors report
      ]

instance FromJSON CrossBackendReport where
  parseJSON =
    withObject "CrossBackendReport" $ \value -> do
      version <- value .: "version"
      when (version /= crossBackendReportVersion) $
        fail ("unsupported cross-backend report version: " <> show (version :: Int))
      cohort <- value .: "cohort"
      when (cohort /= crossBackendCohortName) $
        fail ("unsupported cross-backend cohort: " <> Text.unpack cohort)
      substrateText <- value .: "substrate"
      substrate <- parseSubstrateField substrateText
      CrossBackendReport substrate <$> value .: "tensors"

instance ToJSON CrossBackendReportBundle where
  toJSON bundle =
    object
      [ "version" .= crossBackendReportVersion
      , "cohort" .= crossBackendCohortName
      , "reports" .= bundleReports bundle
      ]

instance FromJSON CrossBackendReportBundle where
  parseJSON =
    withObject "CrossBackendReportBundle" $ \value -> do
      version <- value .: "version"
      when (version /= crossBackendReportVersion) $
        fail ("unsupported cross-backend bundle version: " <> show (version :: Int))
      cohort <- value .: "cohort"
      when (cohort /= crossBackendCohortName) $
        fail ("unsupported cross-backend cohort: " <> Text.unpack cohort)
      CrossBackendReportBundle <$> value .: "reports"

weightedCrossSubstrateCohort :: [WeightedCohortCase]
weightedCrossSubstrateCohort =
  [ WeightedCohortCase
      Identity
      [0.25, -1.0, 2.5, 4.0]
      []
  , WeightedCohortCase
      Dense2D
      [1.0, 2.0, 3.0, 4.0]
      [ 1.0
      , 0.0
      , 0.0
      , 0.0
      , 0.0
      , 2.0
      , 0.0
      , 0.0
      , 0.0
      , 0.0
      , 3.0
      , 0.0
      , 0.0
      , 0.0
      , 0.0
      , 4.0
      ]
  , WeightedCohortCase
      Conv2DKernel
      [0.5, -1.5, 2.5, -3.5]
      [1.25]
  , WeightedCohortCase
      Conv3DKernel
      [0.5, -1.5, 2.5, -3.5]
      [0.75]
  , WeightedCohortCase
      BatchNormKernel
      [0.5, 1.5, 2.5, 3.5]
      [ 1.0
      , 1.1
      , 0.9
      , 1.2
      , 0.0
      , -0.1
      , 0.2
      , -0.2
      , 0.1
      , 0.2
      , 0.3
      , 0.4
      , 1.0
      , 1.5
      , 2.0
      , 2.5
      ]
  , WeightedCohortCase
      LayerNormKernel
      [0.5, 1.5, 2.5, 3.5]
      [ 1.0
      , 1.1
      , 0.9
      , 1.2
      , 0.0
      , -0.1
      , 0.2
      , -0.2
      ]
  , WeightedCohortCase
      MultiHeadAttentionKernel
      [0.25, -0.5, 0.75, 1.0]
      (mhaBlock 1.0 <> mhaBlock 0.75 <> mhaBlock 0.5)
  , WeightedCohortCase
      EmbeddingKernel
      [0.0, 1.0, 2.0, 1.0]
      [ 10.0
      , 11.0
      , 12.0
      , 13.0
      , 20.0
      , 21.0
      , 22.0
      , 23.0
      , 30.0
      , 31.0
      , 32.0
      , 33.0
      ]
  ]

runWeightedCohortForSubstrate :: Env -> Substrate -> IO (Either Text CrossBackendReport)
runWeightedCohortForSubstrate env substrate = do
  tensors <- traverse (runWeightedCohortCase env substrate) weightedCrossSubstrateCohort
  pure (CrossBackendReport substrate <$> sequence tensors)

compareReportBundle :: CrossBackendReportBundle -> Either Text [CrossBackendDrift]
compareReportBundle (CrossBackendReportBundle reports) =
  case comparablePairs reports of
    [] -> Left "cross-backend comparison needs at least two distinct substrate reports"
    pairs -> concat <$> traverse (uncurry compareReports) pairs

allDriftsPass :: [CrossBackendDrift] -> Bool
allDriftsPass =
  all driftPassed

renderDriftSummary :: [CrossBackendDrift] -> Text
renderDriftSummary drifts =
  Text.unlines ("cross-backend drift summary:" : fmap renderDrift drifts)

encodeCrossBackendReportBundle :: CrossBackendReportBundle -> LazyByteString.ByteString
encodeCrossBackendReportBundle =
  encode

decodeCrossBackendReportBundle :: LazyByteString.ByteString -> Either Text CrossBackendReportBundle
decodeCrossBackendReportBundle payload =
  case eitherDecode payload of
    Left err -> Left (Text.pack err)
    Right bundle -> Right bundle

runWeightedCohortCase
  :: Env
  -> Substrate
  -> WeightedCohortCase
  -> IO (Either Text CrossBackendTensor)
runWeightedCohortCase env substrate cohort = do
  outputResult <-
    case substrate of
      LinuxCPU ->
        fmap Local.linuxCpuWeightedKernelOutput
          <$> Local.runLinuxCpuWeightedFamilyKernel
            env
            (cohortFamily cohort)
            (cohortInput cohort)
            (cohortWeights cohort)
      LinuxCUDA ->
        fmap Cuda.cudaWeightedKernelOutput
          <$> Cuda.runCudaWeightedFamilyKernel
            env
            (cohortFamily cohort)
            (cohortInput cohort)
            (cohortWeights cohort)
      AppleSilicon ->
        fmap Metal.metalWeightedKernelOutput
          <$> Metal.runMetalWeightedFamilyKernel
            env
            (cohortFamily cohort)
            (cohortInput cohort)
            (cohortWeights cohort)
  pure
    ( CrossBackendTensor
        (cohortFamily cohort)
        (cohortInput cohort)
        (cohortWeights cohort)
        <$> outputResult
    )

compareReports :: CrossBackendReport -> CrossBackendReport -> Either Text [CrossBackendDrift]
compareReports left right =
  traverse compareFamily weightedCrossSubstrateCohort
 where
  compareFamily cohort = do
    leftTensor <- findTensor left (cohortFamily cohort)
    rightTensor <- findTensor right (cohortFamily cohort)
    if tensorInput leftTensor /= tensorInput rightTensor
      || tensorWeights leftTensor /= tensorWeights rightTensor
      then
        Left
          ( driftPairText left right
              <> " "
              <> familyName (cohortFamily cohort)
              <> " input or weight buffers differ"
          )
      else case maxAbsDelta (tensorOutput leftTensor) (tensorOutput rightTensor) of
        Nothing ->
          Left
            ( driftPairText left right
                <> " "
                <> familyName (cohortFamily cohort)
                <> " output lengths differ"
            )
        Just observed ->
          let bound = Tolerance.toleranceBound (cohortFamily cohort)
           in Right
                CrossBackendDrift
                  { driftLeftSubstrate = reportSubstrate left
                  , driftRightSubstrate = reportSubstrate right
                  , driftFamily = cohortFamily cohort
                  , driftObserved = observed
                  , driftBound = bound
                  , driftPassed = Tolerance.withinTolerance (cohortFamily cohort) observed
                  }

findTensor :: CrossBackendReport -> KernelFamily -> Either Text CrossBackendTensor
findTensor report family =
  case find ((== family) . tensorFamily) (reportTensors report) of
    Just tensor -> Right tensor
    Nothing ->
      Left
        ( renderSubstrate (reportSubstrate report)
            <> " report is missing tensor family "
            <> familyName family
        )

comparablePairs :: [CrossBackendReport] -> [(CrossBackendReport, CrossBackendReport)]
comparablePairs reports =
  [ (left, right)
  | left : rest <- tails reports
  , right <- rest
  , reportSubstrate left /= reportSubstrate right
  ]

maxAbsDelta :: [Float] -> [Float] -> Maybe Double
maxAbsDelta leftOutput rightOutput
  | length leftOutput /= length rightOutput = Nothing
  | otherwise =
      Just
        ( maximum
            ( 0.0
                : zipWith
                  (\left right -> abs (realToFrac left - realToFrac right))
                  leftOutput
                  rightOutput
            )
        )

mhaBlock :: Float -> [Float]
mhaBlock scale =
  [ if row == col then scale else scale / 10.0
  | row <- [0 :: Int .. 3]
  , col <- [0 :: Int .. 3]
  ]

parseKernelFamily :: Text -> AesonTypes.Parser KernelFamily
parseKernelFamily label =
  case lookup label familyByName of
    Just family -> pure family
    Nothing -> fail ("unknown kernel family: " <> Text.unpack label)

parseSubstrateField :: Text -> AesonTypes.Parser Substrate
parseSubstrateField label =
  case parseSubstrate label of
    Just substrate -> pure substrate
    Nothing -> fail ("unknown substrate: " <> Text.unpack label)

familyByName :: [(Text, KernelFamily)]
familyByName =
  [ (familyName Identity, Identity)
  , (familyName Reduction, Reduction)
  , (familyName Dense2D, Dense2D)
  , (familyName Conv2DKernel, Conv2DKernel)
  , (familyName Conv3DKernel, Conv3DKernel)
  , (familyName BatchNormKernel, BatchNormKernel)
  , (familyName LayerNormKernel, LayerNormKernel)
  , (familyName MultiHeadAttentionKernel, MultiHeadAttentionKernel)
  , (familyName EmbeddingKernel, EmbeddingKernel)
  ]

renderDrift :: CrossBackendDrift -> Text
renderDrift drift =
  "  "
    <> renderSubstrate (driftLeftSubstrate drift)
    <> "/"
    <> renderSubstrate (driftRightSubstrate drift)
    <> " "
    <> familyName (driftFamily drift)
    <> ": observed="
    <> showText (driftObserved drift)
    <> " bound="
    <> showText (driftBound drift)
    <> " "
    <> if driftPassed drift then "PASS" else "FAIL"

driftPairText :: CrossBackendReport -> CrossBackendReport -> Text
driftPairText left right =
  renderSubstrate (reportSubstrate left) <> "/" <> renderSubstrate (reportSubstrate right)

showText :: (Show a) => a -> Text
showText =
  Text.pack . show
