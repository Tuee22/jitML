{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Experiment.Product
  ( AlphaZeroExperiment (..)
  , ProductExperiment (..)
  , RlExperiment (..)
  , SupervisedExperiment (..)
  , loadProductExperimentForRow
  , loadRlExperimentByPath
  , loadSupervisedProblemByPath
  , normalizeAlphaZeroGame
  , renderProductExperimentDhall
  )
where

import Control.Exception.Safe (displayException, tryAny)
import Data.Bifunctor (first)
import Data.List qualified as List
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Dhall qualified
import Numeric.Natural (Natural)
import System.Directory (doesFileExist)

import JitML.Product.Matrix qualified as Product
import JitML.SL.Canonicals qualified as SL
import JitML.Training.Budget (TrainingBudget (..))
import JitML.Tune.Catalog qualified as Tune

data SupervisedExperiment = SupervisedExperiment
  { supervisedExperimentName :: Text
  , supervisedExperimentDataset :: Text
  , supervisedExperimentModel :: Text
  , supervisedExperimentSeed :: Natural
  }
  deriving stock (Eq, Show)

data RlExperiment = RlExperiment
  { rlExperimentName :: Text
  , rlExperimentEnvironment :: Text
  , rlExperimentAlgorithm :: Text
  , rlExperimentSeed :: Natural
  }
  deriving stock (Eq, Show)

data AlphaZeroExperiment = AlphaZeroExperiment
  { alphaZeroExperimentName :: Text
  , alphaZeroExperimentGame :: Text
  , alphaZeroExperimentSeed :: Natural
  , alphaZeroExperimentSimulationsPerMove :: Natural
  }
  deriving stock (Eq, Show)

data ProductExperiment
  = ProductSupervisedExperiment SupervisedExperiment
  | ProductRlExperiment RlExperiment
  | ProductAlphaZeroExperiment AlphaZeroExperiment
  | ProductTuningExperiment Tune.TuningExperiment
  deriving stock (Eq, Show)

loadSupervisedProblemByPath :: FilePath -> IO (Either Text SL.CanonicalProblem)
loadSupervisedProblemByPath path = do
  exists <- doesFileExist path
  if exists
    then SL.loadCanonicalProblemExperiment path
    else case productRowsForPath path of
      row : _ -> decodeSupervisedProblemText path =<< renderProductExperimentDhall row
      [] -> pure (Left ("missing supervised experiment config: " <> Text.pack path))

loadRlExperimentByPath :: FilePath -> IO (Either Text RlExperiment)
loadRlExperimentByPath path = do
  exists <- doesFileExist path
  if exists
    then fmap normalizeRlExperiment <$> decodeRlExperimentFile path
    else case productRowsForPath path of
      row : _ -> do
        rendered <- renderProductExperimentDhall row
        fmap normalizeRlExperiment <$> decodeRlExperimentText path rendered
      [] -> pure (Left ("missing RL experiment config: " <> Text.pack path))

loadProductExperimentForRow :: Product.ProductRow state -> IO (Either Text ProductExperiment)
loadProductExperimentForRow row = do
  exists <- doesFileExist path
  case Product.rowClass row of
    Product.SupervisedClassification expectedDataset expectedModel ->
      loadSupervised exists expectedDataset expectedModel
    Product.SupervisedRegression expectedDataset expectedModel ->
      loadSupervised exists expectedDataset expectedModel
    Product.RlAlgorithmEnvironment expectedAlgorithm expectedEnvironment ->
      loadRl exists expectedAlgorithm expectedEnvironment
    Product.RlGoalConditioned expectedEnvironment ->
      loadRl exists "HER" expectedEnvironment
    Product.AlphaZeroGame expectedGame ->
      loadAlphaZero exists expectedGame
    Product.HyperparameterTuning _ ->
      fmap ProductTuningExperiment <$> Tune.loadTuningExperiment path
 where
  path = Text.unpack (Product.experimentConfig row)
  loadSupervised exists expectedDataset expectedModel = do
    experiment <-
      if exists
        then decodeSupervisedExperimentFile path
        else decodeSupervisedExperimentText path =<< renderProductExperimentDhall row
    pure $ do
      resolved <- experiment >>= validateSupervised expectedDataset expectedModel
      Right (ProductSupervisedExperiment resolved)
  loadRl exists expectedAlgorithm expectedEnvironment = do
    experiment <-
      if exists
        then decodeRlExperimentFile path
        else decodeRlExperimentText path =<< renderProductExperimentDhall row
    pure $ do
      resolved <- experiment >>= validateRl expectedEnvironment
      Right (ProductRlExperiment resolved {rlExperimentAlgorithm = expectedAlgorithm})
  loadAlphaZero exists expectedGame = do
    experiment <-
      if exists
        then decodeAlphaZeroExperimentFile path
        else decodeAlphaZeroExperimentText path =<< renderProductExperimentDhall row
    pure $ do
      resolved <- experiment >>= validateAlphaZero expectedGame
      Right (ProductAlphaZeroExperiment resolved)

renderProductExperimentDhall :: Product.ProductRow state -> IO (Either Text Text)
renderProductExperimentDhall row =
  pure $
    case Product.rowClass row of
      Product.SupervisedClassification dataset model ->
        Right (renderSupervisedExperiment row dataset model)
      Product.SupervisedRegression dataset model ->
        Right (renderSupervisedExperiment row dataset model)
      Product.RlAlgorithmEnvironment algorithm environment ->
        Right (renderRlExperiment row algorithm environment)
      Product.RlGoalConditioned environment ->
        Right (renderRlExperiment row "HER" environment)
      Product.AlphaZeroGame game ->
        Right (renderAlphaZeroExperiment row game)
      Product.HyperparameterTuning _ ->
        Left ("tuning row requires checked-in Dhall config: " <> Product.experimentConfig row)

decodeSupervisedProblemText :: FilePath -> Either Text Text -> IO (Either Text SL.CanonicalProblem)
decodeSupervisedProblemText path rendered =
  case rendered of
    Left err -> pure (Left err)
    Right text -> do
      decoded <- decodeDhallText supervisedExperimentDecoder path text
      pure (decoded >>= resolveSupervisedExperiment)

decodeSupervisedExperimentFile :: FilePath -> IO (Either Text SupervisedExperiment)
decodeSupervisedExperimentFile =
  decodeDhallFile supervisedExperimentDecoder

decodeSupervisedExperimentText
  :: FilePath -> Either Text Text -> IO (Either Text SupervisedExperiment)
decodeSupervisedExperimentText path rendered =
  case rendered of
    Left err -> pure (Left err)
    Right text -> decodeDhallText supervisedExperimentDecoder path text

decodeRlExperimentFile :: FilePath -> IO (Either Text RlExperiment)
decodeRlExperimentFile =
  decodeDhallFile rlExperimentDecoder

decodeRlExperimentText :: FilePath -> Either Text Text -> IO (Either Text RlExperiment)
decodeRlExperimentText path rendered =
  case rendered of
    Left err -> pure (Left err)
    Right text -> decodeDhallText rlExperimentDecoder path text

decodeAlphaZeroExperimentFile :: FilePath -> IO (Either Text AlphaZeroExperiment)
decodeAlphaZeroExperimentFile =
  decodeDhallFile alphaZeroExperimentDecoder

decodeAlphaZeroExperimentText
  :: FilePath -> Either Text Text -> IO (Either Text AlphaZeroExperiment)
decodeAlphaZeroExperimentText path rendered =
  case rendered of
    Left err -> pure (Left err)
    Right text -> decodeDhallText alphaZeroExperimentDecoder path text

decodeDhallFile :: Dhall.Decoder a -> FilePath -> IO (Either Text a)
decodeDhallFile decoder path = do
  decoded <- tryAny (Dhall.inputFile decoder path)
  pure (first (Text.pack . displayException) decoded)

decodeDhallText :: Dhall.Decoder a -> FilePath -> Text -> IO (Either Text a)
decodeDhallText decoder path text = do
  decoded <- tryAny (Dhall.input decoder text)
  pure $
    case decoded of
      Left err ->
        Left ("generated Dhall for " <> Text.pack path <> " failed: " <> Text.pack (displayException err))
      Right value -> Right value

supervisedExperimentDecoder :: Dhall.Decoder SupervisedExperiment
supervisedExperimentDecoder =
  Dhall.record $
    SupervisedExperiment
      <$> Dhall.field "name" Dhall.strictText
      <*> Dhall.field "dataset" Dhall.strictText
      <*> Dhall.field "model" Dhall.strictText
      <*> Dhall.field "seed" Dhall.natural

rlExperimentDecoder :: Dhall.Decoder RlExperiment
rlExperimentDecoder =
  Dhall.record $
    RlExperiment
      <$> Dhall.field "name" Dhall.strictText
      <*> Dhall.field "environment" Dhall.strictText
      <*> Dhall.field "algorithm" Dhall.strictText
      <*> Dhall.field "seed" Dhall.natural

alphaZeroExperimentDecoder :: Dhall.Decoder AlphaZeroExperiment
alphaZeroExperimentDecoder =
  Dhall.record $
    AlphaZeroExperiment
      <$> Dhall.field "name" Dhall.strictText
      <*> Dhall.field "game" Dhall.strictText
      <*> Dhall.field "seed" Dhall.natural
      <*> Dhall.field "simulationsPerMove" Dhall.natural

resolveSupervisedExperiment :: SupervisedExperiment -> Either Text SL.CanonicalProblem
resolveSupervisedExperiment experiment =
  case exactSeed `orElse` datasetModel of
    Just problem -> Right problem
    Nothing ->
      Left
        ( "supervised experiment "
            <> supervisedExperimentName experiment
            <> " names dataset/model not present in canonicalProblems: "
            <> supervisedExperimentDataset experiment
            <> "/"
            <> supervisedExperimentModel experiment
        )
 where
  matchesDatasetModel problem =
    SL.problemDataset problem == supervisedExperimentDataset experiment
      && SL.problemModel problem == supervisedExperimentModel experiment
  exactSeed =
    List.find
      ( \problem ->
          matchesDatasetModel problem
            && SL.problemSeed problem == fromIntegral (supervisedExperimentSeed experiment)
      )
      SL.canonicalProblems
  datasetModel = List.find matchesDatasetModel SL.canonicalProblems
  orElse (Just value) _ = Just value
  orElse Nothing fallback = fallback

validateSupervised :: Text -> Text -> SupervisedExperiment -> Either Text SupervisedExperiment
validateSupervised expectedDataset expectedModel experiment
  | supervisedExperimentDataset experiment /= expectedDataset =
      Left
        ( "supervised experiment dataset mismatch: expected "
            <> expectedDataset
            <> ", got "
            <> supervisedExperimentDataset experiment
        )
  | supervisedExperimentModel experiment /= expectedModel =
      Left
        ( "supervised experiment model mismatch: expected "
            <> expectedModel
            <> ", got "
            <> supervisedExperimentModel experiment
        )
  | otherwise = Right experiment

validateRl :: Text -> RlExperiment -> Either Text RlExperiment
validateRl expectedEnvironment experiment
  | normalizeRlEnvironment (rlExperimentEnvironment experiment) /= expectedEnvironment =
      Left
        ( "RL experiment environment mismatch: expected "
            <> expectedEnvironment
            <> ", got "
            <> rlExperimentEnvironment experiment
        )
  | otherwise =
      Right (normalizeRlExperiment experiment {rlExperimentEnvironment = expectedEnvironment})

normalizeRlExperiment :: RlExperiment -> RlExperiment
normalizeRlExperiment experiment =
  experiment {rlExperimentEnvironment = normalizeRlEnvironment (rlExperimentEnvironment experiment)}

validateAlphaZero :: Text -> AlphaZeroExperiment -> Either Text AlphaZeroExperiment
validateAlphaZero expectedGame experiment
  | normalizeAlphaZeroGame (alphaZeroExperimentGame experiment) /= expectedGame =
      Left
        ( "AlphaZero experiment game mismatch: expected "
            <> expectedGame
            <> ", got "
            <> alphaZeroExperimentGame experiment
        )
  | otherwise =
      Right experiment {alphaZeroExperimentGame = expectedGame}

renderSupervisedExperiment :: Product.ProductRow state -> Text -> Text -> Text
renderSupervisedExperiment row dataset model =
  Text.unlines
    [ "{ name = " <> quote (Product.rowId row)
    , ", dataset = " <> quote dataset
    , ", model = " <> quote model
    , ", seed = " <> renderSeed row
    , "}"
    ]

renderRlExperiment :: Product.ProductRow state -> Text -> Text -> Text
renderRlExperiment row algorithm environment =
  Text.unlines
    [ "{ name = " <> quote (Product.rowId row)
    , ", environment = " <> quote environment
    , ", algorithm = " <> quote algorithm
    , ", seed = " <> renderSeed row
    , "}"
    ]

renderAlphaZeroExperiment :: Product.ProductRow state -> Text -> Text
renderAlphaZeroExperiment row game =
  Text.unlines
    [ "{ name = " <> quote (Product.rowId row)
    , ", game = " <> quote game
    , ", seed = " <> renderSeed row
    , ", simulationsPerMove = " <> Text.pack (show (alphaZeroSims game))
    , "}"
    ]

renderSeed :: Product.ProductRow state -> Text
renderSeed row =
  Text.pack . show $ fromMaybe 42 (tbSeed (Product.trainingBudget row))

alphaZeroSims :: Text -> Natural
alphaZeroSims game =
  case game of
    "connect4" -> 128
    "othello" -> 192
    "hex" -> 256
    "gomoku" -> 256
    _ -> 128

productRowsForPath :: FilePath -> [Product.ProductRow 'Product.Declared]
productRowsForPath path =
  [ row
  | row <- Product.allProductRows
  , Product.experimentConfig row == Text.pack path
  ]

normalizeRlEnvironment :: Text -> Text
normalizeRlEnvironment raw =
  case Text.toLower (Text.strip raw) of
    "cartpole" -> "cartpole"
    "cartpole-v1" -> "cartpole"
    "mountaincar" -> "mountain-car"
    "mountaincar-v0" -> "mountain-car"
    "mountain-car" -> "mountain-car"
    "mountain-car-v0" -> "mountain-car"
    "acrobot" -> "acrobot"
    "acrobot-v1" -> "acrobot"
    "pendulum" -> "pendulum"
    "pendulum-v1" -> "pendulum"
    "lunarlander" -> "lunar-lander"
    "lunarlander-v2" -> "lunar-lander"
    "lunar-lander" -> "lunar-lander"
    "lunar-lander-v2" -> "lunar-lander"
    "keydoorgrid" -> "key-door-grid"
    "keydoorgrid-v0" -> "key-door-grid"
    "key-door-grid" -> "key-door-grid"
    "key-door-grid-v0" -> "key-door-grid"
    "gridworld-deterministic" -> "gridworld-deterministic"
    "gridworld-deterministic-v0" -> "gridworld-deterministic"
    "goal-reaching" -> "goal-reaching"
    other -> other

normalizeAlphaZeroGame :: Text -> Text
normalizeAlphaZeroGame raw =
  case Text.toLower (Text.strip raw) of
    "connect 4" -> "connect4"
    "connect4" -> "connect4"
    "othello" -> "othello"
    "othello (reversi)" -> "othello"
    "hex" -> "hex"
    "gomoku" -> "gomoku"
    "gomoku-9x9" -> "gomoku"
    other -> other

quote :: Text -> Text
quote value =
  "\"" <> Text.concatMap escape value <> "\""

escape :: Char -> Text
escape '"' = "\\\""
escape '\\' = "\\\\"
escape ch = Text.singleton ch
