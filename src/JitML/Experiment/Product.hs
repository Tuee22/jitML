{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StandaloneDeriving #-}

module JitML.Experiment.Product
  ( AlphaZeroExperiment (..)
  , PreparedProductExperiment
  , ProductExperiment (..)
  , RlExperiment (..)
  , SupervisedExperiment (..)
  , loadAlphaZeroProductExperiment
  , loadProductExperimentForRow
  , loadProductExperimentForProjection
  , loadRlProductExperiment
  , loadRlExperimentByPath
  , loadSupervisedProductExperiment
  , loadSupervisedProblemByPath
  , normalizeAlphaZeroGame
  , preparedAlphaZeroProductExperiment
  , preparedRlProductExperiment
  , preparedSupervisedProductExperiment
  , preparedTuningProductExperiment
  , preflightAllThenExecute
  , prepareProductExperiment
  , renderProductExperimentDhall
  )
where

import Control.Exception.Safe (displayException, tryAny)
import Data.Bifunctor (first)
import Data.Either (lefts, rights)
import Data.List qualified as List
import Data.List.NonEmpty qualified as NonEmpty
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import Dhall qualified
import Numeric.Natural (Natural)
import System.Directory (doesFileExist)

import JitML.Plan.Plan qualified as Plan
import JitML.Plan.Workload qualified as Workload
import JitML.Product.Matrix qualified as Product
import JitML.SL.Canonicals qualified as SL
import JitML.Substrate (Substrate (LinuxCPU))
import JitML.Training.Budget (trainingBudgetSeed)
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

-- | A decoded ProductRow configuration retained across batch preflight and
-- execution.  The kind index prevents a successfully validated configuration
-- from being paired with a projection for a different executor, while keeping
-- the exact observed values alive so the runner never reopens the path.
data PreparedProductExperiment (kind :: Plan.RunKind) where
  PreparedSupervisedProductExperiment
    :: SupervisedExperiment
    -> SL.CanonicalProblem
    -> PreparedProductExperiment 'Plan.SupervisedTraining
  PreparedRlProductExperiment
    :: RlExperiment
    -> PreparedProductExperiment 'Plan.ReinforcementLearning
  PreparedTuningProductExperiment
    :: Tune.TuningExperiment
    -> PreparedProductExperiment 'Plan.HyperparameterTuning
  PreparedAlphaZeroProductExperiment
    :: AlphaZeroExperiment
    -> PreparedProductExperiment 'Plan.AlphaZeroSelfPlay

deriving instance Eq (PreparedProductExperiment kind)
deriving instance Show (PreparedProductExperiment kind)

-- | Prepare an entire ordered batch before allowing the first execution
-- effect.  Every preparation is attempted so independent failures accumulate;
-- retained typed values are passed to the runner in input order only when the
-- whole batch succeeded.
preflightAllThenExecute
  :: (Monad m)
  => (input -> m (Either error prepared))
  -> (prepared -> m result)
  -> [input]
  -> m (Either [error] [result])
preflightAllThenExecute prepare execute inputs = do
  preparedResults <- traverse prepare inputs
  case lefts preparedResults of
    [] ->
      Right
        <$> traverse execute (rights preparedResults)
    errors -> pure (Left errors)

preparedSupervisedProductExperiment
  :: PreparedProductExperiment 'Plan.SupervisedTraining
  -> (SupervisedExperiment, SL.CanonicalProblem)
preparedSupervisedProductExperiment prepared =
  case prepared of
    PreparedSupervisedProductExperiment experiment problem -> (experiment, problem)

preparedRlProductExperiment
  :: PreparedProductExperiment 'Plan.ReinforcementLearning
  -> RlExperiment
preparedRlProductExperiment prepared =
  case prepared of
    PreparedRlProductExperiment experiment -> experiment

preparedTuningProductExperiment
  :: PreparedProductExperiment 'Plan.HyperparameterTuning
  -> Tune.TuningExperiment
preparedTuningProductExperiment prepared =
  case prepared of
    PreparedTuningProductExperiment experiment -> experiment

preparedAlphaZeroProductExperiment
  :: PreparedProductExperiment 'Plan.AlphaZeroSelfPlay
  -> AlphaZeroExperiment
preparedAlphaZeroProductExperiment prepared =
  case prepared of
    PreparedAlphaZeroProductExperiment experiment -> experiment

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

-- | Load one ProductRow through its opaque projection.  Non-tuning rows never
-- synthesize a missing file and never rewrite decoded values to match the
-- projection: every accepted external field is checked exactly against
-- PlanId-bound row/descriptor/seed/path semantics before execution can start.
loadProductExperimentForProjection
  :: Product.ProductProjection kind
  -> IO (Either Text ProductExperiment)
loadProductExperimentForProjection projection =
  fmap preparedProductExperimentValue <$> prepareProductExperiment projection

prepareProductExperiment
  :: Product.ProductProjection kind
  -> IO (Either Text (PreparedProductExperiment kind))
prepareProductExperiment projection =
  case Product.productProjectionDescriptor projection of
    Product.SupervisedProductDescriptor {} ->
      fmap
        (uncurry PreparedSupervisedProductExperiment)
        <$> loadSupervisedProductExperiment projection
    Product.RlProductDescriptor {} ->
      fmap PreparedRlProductExperiment <$> loadRlProductExperiment projection
    Product.AlphaZeroProductDescriptor {} ->
      fmap PreparedAlphaZeroProductExperiment <$> loadAlphaZeroProductExperiment projection
    Product.TuningProductDescriptor {} -> do
      decoded <-
        Tune.loadTuningExperiment
          (Text.unpack (Product.productProjectionExperimentConfig projection))
      pure (PreparedTuningProductExperiment <$> (decoded >>= validateTuningProjection projection))

preparedProductExperimentValue :: PreparedProductExperiment kind -> ProductExperiment
preparedProductExperimentValue prepared =
  case prepared of
    PreparedSupervisedProductExperiment experiment _problem ->
      ProductSupervisedExperiment experiment
    PreparedRlProductExperiment experiment -> ProductRlExperiment experiment
    PreparedTuningProductExperiment experiment -> ProductTuningExperiment experiment
    PreparedAlphaZeroProductExperiment experiment -> ProductAlphaZeroExperiment experiment

loadProductExperimentForRow :: Product.ProductRow state -> IO (Either Text ProductExperiment)
loadProductExperimentForRow row =
  case Product.projectProductRow LinuxCPU row of
    Plan.Failure errors ->
      pure
        ( Left
            ( "ProductRow projection failed before experiment loading: "
                <> Text.intercalate
                  "; "
                  (fmap (Text.pack . show) (NonEmpty.toList errors))
            )
        )
    Plan.Success (Product.SomeProductProjection _ projection) ->
      loadProductExperimentForProjection projection

-- | Strict supervised ProductRow boundary.  The returned canonical problem is
-- selected by all four decoded fields, never by the historical dataset/model
-- fallback used by the public example loader.
loadSupervisedProductExperiment
  :: Product.ProductProjection 'Plan.SupervisedTraining
  -> IO (Either Text (SupervisedExperiment, SL.CanonicalProblem))
loadSupervisedProductExperiment projection = do
  decoded <-
    decodeSupervisedExperimentFile
      (Text.unpack (Product.productProjectionExperimentConfig projection))
  pure $ do
    experiment <- decoded
    validated <- validateSupervisedProjection projection experiment
    problem <- resolveExactSupervisedProblem validated
    Right (validated, problem)

-- | Strict RL ProductRow boundary.  Algorithm and environment are observed
-- values: neither is normalized or overwritten with the expected descriptor.
loadRlProductExperiment
  :: Product.ProductProjection 'Plan.ReinforcementLearning
  -> IO (Either Text RlExperiment)
loadRlProductExperiment projection = do
  decoded <-
    decodeRlExperimentFile
      (Text.unpack (Product.productProjectionExperimentConfig projection))
  pure (decoded >>= validateRlProjection projection)

-- | Strict AlphaZero ProductRow boundary, including the MCTS simulation count
-- that directly controls self-play execution.
loadAlphaZeroProductExperiment
  :: Product.ProductProjection 'Plan.AlphaZeroSelfPlay
  -> IO (Either Text AlphaZeroExperiment)
loadAlphaZeroProductExperiment projection = do
  decoded <-
    decodeAlphaZeroExperimentFile
      (Text.unpack (Product.productProjectionExperimentConfig projection))
  pure (decoded >>= validateAlphaZeroProjection projection)

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

validateSupervisedProjection
  :: Product.ProductProjection 'Plan.SupervisedTraining
  -> SupervisedExperiment
  -> Either Text SupervisedExperiment
validateSupervisedProjection projection experiment = do
  (expectedDataset, expectedModel) <-
    case Product.productProjectionRowClass projection of
      Product.SupervisedClassification dataset model -> Right (dataset, model)
      Product.SupervisedRegression dataset model -> Right (dataset, model)
      other ->
        Left
          ( "supervised projection carries incompatible row class: "
              <> Product.renderRowClass other
          )
  requireExactText
    "supervised experiment name"
    (Product.productProjectionRowId projection)
    (supervisedExperimentName experiment)
  requireExactText
    "supervised experiment dataset"
    expectedDataset
    (supervisedExperimentDataset experiment)
  requireExactText
    "supervised experiment model"
    expectedModel
    (supervisedExperimentModel experiment)
  validateProjectionSeed
    "supervised experiment seed"
    projection
    (supervisedExperimentSeed experiment)
  Right experiment

resolveExactSupervisedProblem :: SupervisedExperiment -> Either Text SL.CanonicalProblem
resolveExactSupervisedProblem experiment =
  case List.find matchesExactly SL.canonicalProblems of
    Just problem -> Right problem
    Nothing ->
      Left
        ( "supervised ProductRow config does not identify one exact canonical problem: "
            <> supervisedExperimentName experiment
            <> "/"
            <> supervisedExperimentDataset experiment
            <> "/"
            <> supervisedExperimentModel experiment
            <> "/seed="
            <> showNatural (supervisedExperimentSeed experiment)
        )
 where
  matchesExactly problem =
    SL.problemName problem == supervisedExperimentName experiment
      && SL.problemDataset problem == supervisedExperimentDataset experiment
      && SL.problemModel problem == supervisedExperimentModel experiment
      && toInteger (SL.problemSeed problem) == toInteger (supervisedExperimentSeed experiment)

validateRlProjection
  :: Product.ProductProjection 'Plan.ReinforcementLearning
  -> RlExperiment
  -> Either Text RlExperiment
validateRlProjection projection experiment =
  case Product.productProjectionDescriptor projection of
    Product.RlProductDescriptor expectedAlgorithm expectedEnvironment _ _ _ _ -> do
      requireExactText
        "RL experiment name"
        (Product.productProjectionRowId projection)
        (rlExperimentName experiment)
      requireExactText
        "RL experiment algorithm"
        expectedAlgorithm
        (rlExperimentAlgorithm experiment)
      requireExactText
        "RL experiment environment"
        expectedEnvironment
        (rlExperimentEnvironment experiment)
      validateProjectionSeed
        "RL experiment seed"
        projection
        (rlExperimentSeed experiment)
      Right experiment

normalizeRlExperiment :: RlExperiment -> RlExperiment
normalizeRlExperiment experiment =
  experiment {rlExperimentEnvironment = normalizeRlEnvironment (rlExperimentEnvironment experiment)}

validateAlphaZeroProjection
  :: Product.ProductProjection 'Plan.AlphaZeroSelfPlay
  -> AlphaZeroExperiment
  -> Either Text AlphaZeroExperiment
validateAlphaZeroProjection projection experiment =
  case Product.productProjectionDescriptor projection of
    Product.AlphaZeroProductDescriptor expectedGame _ expectedSimulations _ _ _ -> do
      requireExactText
        "AlphaZero experiment name"
        (Product.productProjectionRowId projection)
        (alphaZeroExperimentName experiment)
      requireExactText
        "AlphaZero experiment game"
        expectedGame
        (alphaZeroExperimentGame experiment)
      requireExactNatural
        "AlphaZero experiment simulationsPerMove"
        expectedSimulations
        (alphaZeroExperimentSimulationsPerMove experiment)
      validateProjectionSeed
        "AlphaZero experiment seed"
        projection
        (alphaZeroExperimentSeed experiment)
      Right experiment

validateTuningProjection
  :: Product.ProductProjection 'Plan.HyperparameterTuning
  -> Tune.TuningExperiment
  -> Either Text Tune.TuningExperiment
validateTuningProjection projection experiment =
  case ( Product.productProjectionDescriptor projection
       , Product.productProjectionResolvedPlan projection
       ) of
    ( Product.TuningProductDescriptor descriptorSpec _ _ _
      , Product.ResolvedTuningProductPlan plan
      ) -> do
        decodedSpec <- Tune.tuningExecutionSpecForExperiment experiment
        requireExactValue
          "tuning descriptor/resolved-plan execution spec"
          descriptorSpec
          (Workload.tuningPlanExecutionSpec plan)
        requireExactValue
          "tuning experiment execution spec"
          descriptorSpec
          decodedSpec
        validateProjectionSeed
          "tuning experiment seed"
          projection
          (Tune.tuningExperimentSeed experiment)
        requireExactValue
          "tuning experiment/sampler seed"
          (Tune.tuningExperimentSeed experiment)
          (Tune.tuningSamplerSeed (Tune.tuningExecutionSampler decodedSpec))
        Right experiment

validateProjectionSeed
  :: Text
  -> Product.ProductProjection kind
  -> Natural
  -> Either Text ()
validateProjectionSeed label projection observed =
  case NonEmpty.toList
    (Plan.seedCohortValues (Plan.runPlanSeeds (Product.productProjectionRunPlan projection))) of
    [expected] -> requireExactNatural label expected observed
    seeds ->
      Left
        ( "ProductRow config requires exactly one resolved seed, got "
            <> Text.pack (show (length seeds))
        )

requireExactText :: Text -> Text -> Text -> Either Text ()
requireExactText label expected observed
  | observed == expected = Right ()
  | otherwise =
      Left
        ( label
            <> " mismatch: expected "
            <> expected
            <> ", got "
            <> observed
        )

requireExactNatural :: Text -> Word64 -> Natural -> Either Text ()
requireExactNatural label expected observed
  | toInteger observed == toInteger expected = Right ()
  | otherwise =
      Left
        ( label
            <> " mismatch: expected "
            <> Text.pack (show expected)
            <> ", got "
            <> showNatural observed
        )

requireExactValue :: (Eq value, Show value) => Text -> value -> value -> Either Text ()
requireExactValue label expected observed
  | observed == expected = Right ()
  | otherwise =
      Left
        ( label
            <> " mismatch: expected "
            <> Text.pack (show expected)
            <> ", got "
            <> Text.pack (show observed)
        )

showNatural :: Natural -> Text
showNatural = Text.pack . show

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
  Text.pack . show $ fromMaybe 42 (trainingBudgetSeed (Product.trainingBudget row))

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
