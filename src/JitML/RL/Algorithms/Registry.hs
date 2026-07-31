{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.Algorithms.Registry
  ( algorithmModuleRegistry
  , moduleFor
  , offPolicyModules
  , onPolicyModules
  , specialisedModules
  , updateContractFor
  , validateAlgorithmModuleRegistry

    -- * Phase 250 — typed action-domain cohort
  , ActionDomain (..)
  , RLCohort
  , cohortAlgorithmName
  , cohortEnvironmentName
  , cohortActionDomain
  , cohortTrainerKind
  , mkCohort
  , mkCohortForAlgorithm
  , allCohorts
  , trainerKindForAlgorithmName
  , algorithmNameForTrainerKind
  , supportedEnvironmentsForTrainer
  , trainerEnvironmentCompatibilityError
  , renderActionDomain
  )
where

import Data.List qualified as List
import Data.Maybe (listToMaybe)
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.RL.Algorithms (RLAlgorithm (..))
import JitML.RL.Algorithms.A2c (a2cModule)
import JitML.RL.Algorithms.Ars (arsModule)
import JitML.RL.Algorithms.Common
  ( AlgorithmModule (..)
  , AlgorithmUpdateContract (..)
  )
import JitML.RL.Algorithms.CrossQ (crossQModule)
import JitML.RL.Algorithms.Ddpg (ddpgModule)
import JitML.RL.Algorithms.Dqn (dqnModule)
import JitML.RL.Algorithms.Her (herModule)
import JitML.RL.Algorithms.MaskablePpo (maskablePpoModule)
import JitML.RL.Algorithms.Ppo (ppoModule)
import JitML.RL.Algorithms.QrDqn (qrDqnModule)
import JitML.RL.Algorithms.RecurrentPpo (recurrentPpoModule)
import JitML.RL.Algorithms.Sac (sacModule)
import JitML.RL.Algorithms.Td3 (td3Module)
import JitML.RL.Algorithms.Tqc (tqcModule)
import JitML.RL.Algorithms.Trpo (trpoModule)
import JitML.RL.Environments (RLEnvironment (..))
import JitML.RL.Framework (ActionDomain (..), renderActionDomain)

algorithmModuleRegistry :: [AlgorithmModule]
algorithmModuleRegistry =
  onPolicyModules <> offPolicyModules <> specialisedModules

onPolicyModules :: [AlgorithmModule]
onPolicyModules =
  [ ppoModule
  , a2cModule
  , trpoModule
  , maskablePpoModule
  , recurrentPpoModule
  ]

offPolicyModules :: [AlgorithmModule]
offPolicyModules =
  [ dqnModule
  , qrDqnModule
  , ddpgModule
  , td3Module
  , sacModule
  ]

specialisedModules :: [AlgorithmModule]
specialisedModules =
  [ crossQModule
  , tqcModule
  , arsModule
  , herModule
  ]

moduleFor :: Text -> Maybe AlgorithmModule
moduleFor name =
  case [m | m <- algorithmModuleRegistry, algorithmName (moduleAlgorithm m) == name] of
    (first : _) -> Just first
    [] -> Nothing

updateContractFor :: Text -> Maybe AlgorithmUpdateContract
updateContractFor name =
  moduleUpdateContract <$> moduleFor name

validateAlgorithmModuleRegistry :: [AlgorithmModule] -> [Text]
validateAlgorithmModuleRegistry modules =
  duplicateAlgorithmErrors
    <> duplicateUpdateIdentityErrors
    <> missingContractErrors
 where
  algorithmNames = fmap (algorithmName . moduleAlgorithm) modules
  updateIdentities = fmap (updateIdentity . moduleUpdateContract) modules
  duplicateAlgorithmErrors =
    [ "duplicate algorithm module: " <> name
    | name <- duplicates algorithmNames
    ]
  duplicateUpdateIdentityErrors =
    [ "duplicate algorithm update identity: " <> identity
    | identity <- duplicates updateIdentities
    ]
  missingContractErrors =
    [ algorithmName (moduleAlgorithm m) <> " has incomplete update contract"
    | m <- modules
    , contractIncomplete (moduleUpdateContract m)
    ]
  contractIncomplete contract =
    Text.null (Text.strip (updateIdentity contract))
      || Text.null (Text.strip (trainerEntryPoint contract))
      || Text.null (Text.strip (rolloutSurface contract))
      || Text.null (Text.strip (learnedArtifact contract))
      || null (updateFeatures contract)

duplicates :: (Ord a) => [a] -> [a]
duplicates values =
  [ value
  | value : _ : _ <- List.group (List.sort values)
  ]

-- Phase 250 — typed action-domain cohort. ---------------------------------
--
-- A single source of truth for which @(algorithm, environment)@ pairs are
-- admissible and, for each admissible pair, which 'ActionDomain' the canonical
-- trainer exercises. This subsumes the former hand-maintained string relation
-- in 'JitML.RL.ProductBudget' (which now delegates here) and the parallel
-- @algorithm@ ↔ @trainerKind@ mapping functions that were duplicated across the
-- daemon, the worker, the publisher, and the completion path.
--
-- 'RLCohort' is abstract: its constructor is not exported, so the only way to
-- obtain a value is through the smart constructor 'mkCohort', which fails
-- ('Left') for any incompatible pair. There is therefore no valid 'RLCohort'
-- for e.g. @SAC@+@cartpole@, @DQN@+@pendulum@, or @HER@+@cartpole@.

-- | An admissible, action-domain-checked @(algorithm, environment)@ cohort.
data RLCohort = RLCohort
  { cohortAlgorithmName :: !Text
  -- ^ Canonical public matrix name (for example @QR-DQN@).
  , cohortEnvironmentName :: !Text
  -- ^ Lower-cased, stripped environment name (for example @lunar-lander@).
  , cohortActionDomain :: !ActionDomain
  -- ^ The action domain this specific pair exercises.
  , cohortTrainerKind :: !Text
  -- ^ Worker-side trainer selector; the exact lower-case identity string baked
  --   into content-addressed evidence and checkpoint tensor names.
  }
  deriving stock (Eq, Show)

-- | One algorithm's cohort row: its public name, the lower-case trainer kind it
-- renders to, and the ordered environments it supports paired with the action
-- domain each pair exercises. The environment order is load-bearing: it is the
-- order rendered into the compatibility-error message.
data CohortSpec = CohortSpec
  { specAlgorithmName :: !Text
  , specTrainerKind :: !Text
  , specEnvironments :: ![(Text, ActionDomain)]
  }

-- | The canonical cohort registry. Reproduces exactly the compatibility
-- relation formerly inlined in 'JitML.RL.ProductBudget'
-- (@rlTrainerEnvironmentCompatibilityError@), now carrying each pair's action
-- domain. @lunar-lander@ appears as 'DiscreteDomain' for the on-policy and ARS
-- rows and as 'ContinuousDomain' for the DDPG/TD3/SAC/CrossQ/TQC rows, so the
-- dual domain is resolved per @(algorithm, environment)@ pair.
cohortRegistry :: [CohortSpec]
cohortRegistry =
  [ CohortSpec "PPO" "ppo" onPolicyDiscreteWide
  , CohortSpec "A2C" "a2c" onPolicyDiscreteCore
  , CohortSpec "TRPO" "trpo" onPolicyDiscreteCore
  , CohortSpec "MaskablePPO" "maskableppo" onPolicyDiscreteCore
  , CohortSpec "RecurrentPPO" "recurrentppo" onPolicyDiscreteCore
  , CohortSpec "DQN" "dqn" offPolicyDiscrete
  , CohortSpec "QR-DQN" "qrdqn" offPolicyDiscrete
  , CohortSpec "DDPG" "ddpg" continuousControl
  , CohortSpec "TD3" "td3" continuousControl
  , CohortSpec "SAC" "sac" continuousControl
  , CohortSpec "CrossQ" "crossq" continuousControl
  , CohortSpec "TQC" "tqc" continuousControl
  , CohortSpec "ARS" "ars" onPolicyDiscreteCore
  , CohortSpec "HER" "her" [("goal-reaching", GoalConditionedDomain)]
  ]
 where
  onPolicyDiscreteWide =
    [ ("cartpole", DiscreteDomain)
    , ("mountain-car", DiscreteDomain)
    , ("acrobot", DiscreteDomain)
    , ("lunar-lander", DiscreteDomain)
    , ("key-door-grid", DiscreteDomain)
    , ("gridworld-deterministic", DiscreteDomain)
    ]
  onPolicyDiscreteCore =
    [ ("cartpole", DiscreteDomain)
    , ("mountain-car", DiscreteDomain)
    , ("lunar-lander", DiscreteDomain)
    , ("key-door-grid", DiscreteDomain)
    ]
  offPolicyDiscrete =
    [ ("cartpole", DiscreteDomain)
    , ("mountain-car", DiscreteDomain)
    , ("key-door-grid", DiscreteDomain)
    ]
  continuousControl =
    [ ("pendulum", ContinuousDomain)
    , ("lunar-lander", ContinuousDomain)
    ]

-- | Canonical public-name → trainer-kind rendering. Accepts either the public
-- matrix name (any case) or an already-rendered trainer kind. Unknown names
-- fall through to their lower-cased/stripped form so downstream dispatch fails
-- closed. Byte-identical to the former @trainerKindForAlgorithm@.
trainerKindForAlgorithmName :: Text -> Text
trainerKindForAlgorithmName algorithm =
  case lookup (Text.toUpper stripped) normalizedTrainerKinds of
    Just kind -> kind
    Nothing -> Text.toLower stripped
 where
  stripped = Text.strip algorithm

-- | Uppercased public name → trainer kind, including the hyphen-free @QRDQN@
-- alias the daemon and CLI both accept.
normalizedTrainerKinds :: [(Text, Text)]
normalizedTrainerKinds =
  [(Text.toUpper (specAlgorithmName spec), specTrainerKind spec) | spec <- cohortRegistry]
    <> [("QRDQN", "qrdqn")]

-- | Inverse of 'trainerKindForAlgorithmName': a trainer kind → its canonical
-- public matrix name. 'Nothing' for an unknown trainer kind.
algorithmNameForTrainerKind :: Text -> Maybe Text
algorithmNameForTrainerKind trainer =
  fmap specAlgorithmName (cohortSpecForTrainer trainer)

cohortSpecForTrainer :: Text -> Maybe CohortSpec
cohortSpecForTrainer trainer =
  listToMaybe [spec | spec <- cohortRegistry, specTrainerKind spec == normalized]
 where
  normalized = Text.toLower (Text.strip trainer)

-- | The ordered environments a trainer kind supports, or 'Nothing' for an
-- unknown trainer kind (which, matching the historical relation, imposes no
-- compatibility restriction so dispatch can fail closed elsewhere).
supportedEnvironmentsForTrainer :: Text -> Maybe [Text]
supportedEnvironmentsForTrainer trainer =
  fmap (fmap fst . specEnvironments) (cohortSpecForTrainer trainer)

-- | Closed compatibility relation keyed by trainer kind, byte-identical to the
-- former 'JitML.RL.ProductBudget' implementation this now backs.
trainerEnvironmentCompatibilityError :: Text -> Text -> Maybe Text
trainerEnvironmentCompatibilityError rawTrainer rawEnvironment =
  case supportedEnvironmentsForTrainer trainer of
    Nothing -> Nothing
    Just environments
      | environment `elem` environments -> Nothing
      | otherwise -> Just (unsupportedEnvironmentMessage trainer environment environments)
 where
  trainer = Text.toLower (Text.strip rawTrainer)
  environment = Text.toLower (Text.strip rawEnvironment)

unsupportedEnvironmentMessage :: Text -> Text -> [Text] -> Text
unsupportedEnvironmentMessage trainer environment environments =
  "RL trainer "
    <> trainer
    <> " does not support environment "
    <> environment
    <> "; supported environments: "
    <> Text.intercalate ", " environments

-- | The smart constructor. Given an algorithm (public name or trainer kind) and
-- an environment name, return the action-domain-checked cohort or a typed
-- rejection. An incompatible pair has no 'RLCohort' value: the pair is rejected
-- either because the algorithm is unknown or because the environment is outside
-- the algorithm's action domain.
mkCohort :: Text -> Text -> Either Text RLCohort
mkCohort algorithm environment =
  case cohortSpecForTrainer trainer of
    Nothing -> Left ("unknown RL algorithm: " <> algorithm)
    Just spec ->
      case lookup env (specEnvironments spec) of
        Nothing ->
          Left (unsupportedEnvironmentMessage trainer env (fmap fst (specEnvironments spec)))
        Just domain ->
          Right
            RLCohort
              { cohortAlgorithmName = specAlgorithmName spec
              , cohortEnvironmentName = env
              , cohortActionDomain = domain
              , cohortTrainerKind = trainer
              }
 where
  trainer = trainerKindForAlgorithmName algorithm
  env = Text.toLower (Text.strip environment)

-- | Typed variant of 'mkCohort' over the catalog value types.
mkCohortForAlgorithm :: RLAlgorithm -> RLEnvironment -> Either Text RLCohort
mkCohortForAlgorithm algorithm environment =
  mkCohort (algorithmName algorithm) (environmentName environment)

-- | Every admissible cohort, flattened from the registry. Useful for exhaustive
-- coverage assertions.
allCohorts :: [RLCohort]
allCohorts =
  [ RLCohort
      { cohortAlgorithmName = specAlgorithmName spec
      , cohortEnvironmentName = environment
      , cohortActionDomain = domain
      , cohortTrainerKind = specTrainerKind spec
      }
  | spec <- cohortRegistry
  , (environment, domain) <- specEnvironments spec
  ]
