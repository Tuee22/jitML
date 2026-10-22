{-# LANGUAGE OverloadedStrings #-}

-- | Frozen Haskell grammar, authored from the independently reviewed73-tag
-- design. There is no runtime JSON/schema loading or extensible supplied parser.
module JitML.Checkpoint.NativePhase.SchemaTable
  ( FieldType (..)
  , ReferenceTarget (..)
  , fieldTypes
  , namedType
  , contextTypes
  , allowedPhaseKinds
  , scalarType
  , elementTarget
  , sequenceElementKinds
  ) where

import Data.Text (Text)
import Data.Word (Word64)

import JitML.Checkpoint.NativePhase.Types

data ReferenceTarget = NodeTargets ![NodeKind] | SequenceTarget !ElementKind
  deriving stock (Eq, Show)

data FieldType
  = TWord
  | TInt
  | TBits
  | TBool
  | TDigest
  | TMagnitude
  | TElementKind
  | TText !Resource !Integer
  | TBytes !Resource !Integer
  | TExactWord !Word64
  | TExactText !Text
  | TEnum ![Word64]
  | TTuple ![FieldType]
  | TSum ![(Word64, [FieldType])]
  | TReference !ReferenceTarget
  | TOptional !FieldType
  | TArray !FieldType
  | TDynamicRefs
  | TDynamicScalars
  | TNamed !Text
  deriving stock (Eq, Show)

fieldTypes :: NodeKind -> [(Text, FieldType)]
fieldTypes kind = case kind of
  NTensorLeaf -> [("coordinateCount", TWord), ("rawF64Bytes", TBytes TensorChunkBytes 1048576)]
  NParams ->
    [ ("shape", TNamed "Shape3")
    , ("w1", TReference (NodeTargets [NTensorLeaf, NTensorManifest]))
    , ("b1", TReference (NodeTargets [NTensorLeaf, NTensorManifest]))
    , ("w2", TReference (NodeTargets [NTensorLeaf, NTensorManifest]))
    , ("b2", TReference (NodeTargets [NTensorLeaf, NTensorManifest]))
    ]
  NGradient ->
    [ ("w1", TReference (NodeTargets [NTensorLeaf, NTensorManifest]))
    , ("b1", TReference (NodeTargets [NTensorLeaf, NTensorManifest]))
    , ("w2", TReference (NodeTargets [NTensorLeaf, NTensorManifest]))
    , ("b2", TReference (NodeTargets [NTensorLeaf, NTensorManifest]))
    ]
  NAdam ->
    [ ("step", TInt)
    , ("m", TReference (NodeTargets [NGradient]))
    , ("v", TReference (NodeTargets [NGradient]))
    ]
  NPVN ->
    [("params", TReference (NodeTargets [NParams])), ("actionCount", TInt), ("observationSize", TInt)]
  NTensorManifest ->
    [ ("coordinateCount", TWord)
    , ("totalBytes", TWord)
    , ("chunks", TArray (TReference (NodeTargets [NTensorChunk])))
    ]
  NTensorChunk -> [("ordinal", TWord), ("rawF64Bytes", TBytes TensorChunkBytes 1048576)]
  NSequenceManifest ->
    [ ("elementKind", TNamed "ElementKind")
    , ("count", TWord)
    , ("height", TNamed "Height0to2")
    , ("children", TArray (TReference (NodeTargets [NSequenceIndex, NReferencePage, NScalarPage])))
    ]
  NSequenceIndex ->
    [ ("elementKind", TNamed "ElementKind")
    , ("remainingHeight", TExactWord 1)
    , ("subtreeCount", TWord)
    , ("children", TArray (TReference (NodeTargets [NReferencePage, NScalarPage])))
    ]
  NReferencePage -> [("elementKind", TNamed "ElementKind"), ("count", TWord), ("elements", TDynamicRefs)]
  NScalarPage -> [("elementKind", TNamed "ElementKind"), ("count", TWord), ("elements", TDynamicScalars)]
  NGeneratorState ->
    [ ("representation", TExactText "stdgen-seedgen-toSeed64-v1")
    , ("randomVersion", TText ProducerComponentBytes 256)
    , ("wordCount", TExactWord 2)
    , ("words", TNamed "Word64Pair")
    ]
  NProducerContextBundle ->
    [ ("before", TOptional (TReference (NodeTargets [NRecordedProducer])))
    , ("after", TOptional (TReference (NodeTargets [NRecordedProducer])))
    , ("runtimeMetadata", TOptional (TReference (NodeTargets [NRuntimeMetadata])))
    ]
  NRuntimeMetadata ->
    [ ("coverage", TNamed "RuntimeMetadataCoverage")
    , ("planSha", TOptional TDigest)
    , ("compilerId", TText ProducerComponentBytes 256)
    , ("os", TText ProducerComponentBytes 256)
    , ("arch", TText ProducerComponentBytes 256)
    , ("randomPackageId", TText GeneralTextBytes 1024)
    , ("randomVersion", TText ProducerComponentBytes 256)
    , ("splitmixPackageId", TOptional (TText GeneralTextBytes 1024))
    , ("splitmixVersion", TOptional (TText ProducerComponentBytes 256))
    , ("wordSize", TExactWord 64)
    ]
  NRecordedProducer ->
    [ ("executableFilePath", TText PathTextBytes 4096)
    , ("executableSha", TDigest)
    , ("executableBytes", TWord)
    , ("pid", TNamed "MagnitudeInteger")
    , ("ppid", TNamed "MagnitudeInteger")
    , ("kernelOS", TText ProducerComponentBytes 256)
    , ("kernelMachine", TText ProducerComponentBytes 256)
    , ("kernelRelease", TText ProducerComponentBytes 256)
    , ("buildOS", TText ProducerComponentBytes 256)
    , ("buildArch", TText ProducerComponentBytes 256)
    , ("compiler", TText ProducerComponentBytes 256)
    , ("compilerVersion", TText ProducerComponentBytes 256)
    , ("observedSource", TNamed "MaybeObservedSource")
    ]
  NPpoConfig ->
    [ ("ppoSeed", TInt)
    , ("ppoHiddenUnits", TInt)
    , ("ppoVectorEnvCount", TInt)
    , ("ppoRolloutSteps", TInt)
    , ("ppoNumIterations", TInt)
    , ("ppoEpochsPerUpdate", TInt)
    , ("ppoMiniBatchSize", TInt)
    , ("ppoGamma", TBits)
    , ("ppoLambda", TBits)
    , ("ppoClipEps", TBits)
    , ("ppoValueCoef", TBits)
    , ("ppoEntropyCoef", TBits)
    , ("ppoCountBeta", TBits)
    , ("ppoMaxEpisodeSteps", TInt)
    , ("ppoActionCount", TInt)
    , ("ppoObsSize", TInt)
    , ("ppoLearningRate", TBits)
    , ("ppoVariant", TNamed "OnPolicyVariant")
    , ("ppoKlTarget", TBits)
    , ("ppoTrpoCgIterations", TInt)
    , ("ppoTrpoCgDamping", TBits)
    , ("ppoTrpoBacktrackIterations", TInt)
    , ("ppoTrpoBacktrackCoef", TBits)
    , ("ppoTrpoCriticUpdates", TInt)
    , ("ppoTrpoCriticLearningRate", TBits)
    , ("ppoRecurrentStateSize", TInt)
    ]
  NDqnConfig ->
    [ ("dqnSeed", TInt)
    , ("dqnHiddenUnits", TInt)
    , ("dqnNumSteps", TInt)
    , ("dqnReplayCapacity", TInt)
    , ("dqnBatchSize", TInt)
    , ("dqnLearningRate", TBits)
    , ("dqnGamma", TBits)
    , ("dqnTargetUpdateInterval", TInt)
    , ("dqnEpsilonStart", TBits)
    , ("dqnEpsilonEnd", TBits)
    , ("dqnEpsilonDecaySteps", TInt)
    , ("dqnTrainStart", TInt)
    , ("dqnUpdateFrequency", TInt)
    , ("dqnMaxEpisodeSteps", TInt)
    , ("dqnActionCount", TInt)
    , ("dqnObsSize", TInt)
    , ("dqnStatInterval", TInt)
    , ("dqnUseDouble", TBool)
    ]
  NQrConfig ->
    [ ("qrSeed", TInt)
    , ("qrHiddenUnits", TInt)
    , ("qrNumQuantiles", TInt)
    , ("qrNumSteps", TInt)
    , ("qrReplayCapacity", TInt)
    , ("qrBatchSize", TInt)
    , ("qrLearningRate", TBits)
    , ("qrGamma", TBits)
    , ("qrKappa", TBits)
    , ("qrTargetUpdateInterval", TInt)
    , ("qrEpsilonStart", TBits)
    , ("qrEpsilonEnd", TBits)
    , ("qrEpsilonDecaySteps", TInt)
    , ("qrTrainStart", TInt)
    , ("qrUpdateFrequency", TInt)
    , ("qrMaxEpisodeSteps", TInt)
    , ("qrActionCount", TInt)
    , ("qrObsSize", TInt)
    , ("qrStatInterval", TInt)
    ]
  NContinuousConfig ->
    [ ("ctVariant", TNamed "ContinuousVariant")
    , ("ctSeed", TInt)
    , ("ctHidden", TInt)
    , ("ctNumSteps", TInt)
    , ("ctReplayCapacity", TInt)
    , ("ctBatchSize", TInt)
    , ("ctActorLr", TBits)
    , ("ctCriticLr", TBits)
    , ("ctGamma", TBits)
    , ("ctTau", TBits)
    , ("ctPolicyDelay", TInt)
    , ("ctExplNoise", TBits)
    , ("ctTargetNoise", TBits)
    , ("ctNoiseClip", TBits)
    , ("ctSacAlpha", TBits)
    , ("ctAlphaLr", TBits)
    , ("ctTargetEntropy", TBits)
    , ("ctPolicyStd", TBits)
    , ("ctTqcDropPerCritic", TInt)
    , ("ctStartSteps", TInt)
    , ("ctTrainStart", TInt)
    , ("ctMaxEpisodeSteps", TInt)
    , ("ctObsSize", TInt)
    , ("ctActionLow", TBits)
    , ("ctActionHigh", TBits)
    , ("ctStatInterval", TInt)
    , ("ctEnvName", TText GeneralTextBytes 1024)
    , ("ctCountBeta", TBits)
    ]
  NHerConfig ->
    [ ("herSeed", TInt)
    , ("herNumBits", TInt)
    , ("herHiddenUnits", TInt)
    , ("herEpisodes", TInt)
    , ("herReplayCapacity", TInt)
    , ("herBatchSize", TInt)
    , ("herLearningRate", TBits)
    , ("herGamma", TBits)
    , ("herTargetUpdateInterval", TInt)
    , ("herEpsilon", TBits)
    , ("herUseHindsight", TBool)
    , ("herStrategy", TNamed "HerStrategy")
    , ("herStatInterval", TInt)
    , ("herUpdatesPerEpisode", TInt)
    ]
  NArsConfig ->
    [ ("arsSeed", TInt)
    , ("arsIterations", TInt)
    , ("arsNumDirections", TInt)
    , ("arsTopB", TInt)
    , ("arsStepSize", TBits)
    , ("arsNoiseStd", TBits)
    , ("arsMaxEpisodeSteps", TInt)
    , ("arsActionCount", TInt)
    , ("arsObsSize", TInt)
    ]
  NPpoStat ->
    [ ("iterIndex", TInt)
    , ("iterMeanReward", TBits)
    , ("iterMedianReward", TBits)
    , ("iterMaxReward", TBits)
    , ("iterEpisodes", TInt)
    ]
  NDqnStat ->
    [ ("dqnIterStep", TInt)
    , ("dqnIterEpisodes", TInt)
    , ("dqnIterMeanReward", TBits)
    , ("dqnIterLastEpisodeReward", TBits)
    ]
  NQrStat -> [("qrIterStep", TInt), ("qrIterEpisodes", TInt), ("qrIterMeanReward", TBits)]
  NContinuousStat ->
    [ ("contIterStep", TInt)
    , ("contIterEpisodes", TInt)
    , ("contIterMeanReward", TBits)
    , ("contIterLastEpisodeReward", TBits)
    ]
  NHerStat -> [("herIterEpisode", TInt), ("herIterSuccessRate", TBits)]
  NArsStat -> [("arsIterIndex", TInt), ("arsIterMeanReturn", TBits), ("arsIterBestReturn", TBits)]
  NArsPerturbation ->
    [ ("plusReward", TBits)
    , ("plusSteps", TInt)
    , ("minusReward", TBits)
    , ("minusSteps", TInt)
    , ("delta", TReference (NodeTargets [NTensorLeaf, NTensorManifest]))
    ]
  NArsKeptDirection ->
    [ ("plusReward", TBits)
    , ("minusReward", TBits)
    , ("delta", TReference (NodeTargets [NTensorLeaf, NTensorManifest]))
    ]
  NArsAppliedStep ->
    [ ("config", TReference (NodeTargets [NArsConfig]))
    , ("runtime", TReference (NodeTargets [NArsRuntime]))
    , ("index", TInt)
    , ("thetaBefore", TReference (NodeTargets [NTensorLeaf, NTensorManifest]))
    , ("thetaAfter", TReference (NodeTargets [NTensorLeaf, NTensorManifest]))
    , ("sampledDirections", TReference (SequenceTarget (AliasElement TensorAlias)))
    , ("evaluatedPerturbations", TReference (SequenceTarget (RefElement NArsPerturbation)))
    , ("keptDirections", TReference (SequenceTarget (RefElement NArsKeptDirection)))
    , ("noiseStd", TBits)
    , ("returnStdDev", TBits)
    , ("updateDirection", TReference (NodeTargets [NTensorLeaf, NTensorManifest]))
    , ("scale", TBits)
    , ("observedTransitions", TNamed "MagnitudeInteger")
    ]
  NArsIterationObservation ->
    [ ("stat", TReference (NodeTargets [NArsStat]))
    , ("appliedStep", TReference (NodeTargets [NArsAppliedStep]))
    ]
  NArsRuntime ->
    [ ("os", TText ProducerComponentBytes 256)
    , ("arch", TText ProducerComponentBytes 256)
    , ("compiler", TText ProducerComponentBytes 256)
    , ("compilerVersion", TText ProducerComponentBytes 256)
    , ("arithmeticRecipe", TText GeneralTextBytes 1024)
    ]
  NDiscreteReplay ->
    [ ("observation", TReference (NodeTargets [NTensorLeaf, NTensorManifest]))
    , ("action", TInt)
    , ("reward", TBits)
    , ("nextObservation", TReference (NodeTargets [NTensorLeaf, NTensorManifest]))
    , ("done", TBool)
    ]
  NContinuousReplay ->
    [ ("observation", TReference (NodeTargets [NTensorLeaf, NTensorManifest]))
    , ("action", TBits)
    , ("reward", TBits)
    , ("nextObservation", TReference (NodeTargets [NTensorLeaf, NTensorManifest]))
    , ("done", TBool)
    ]
  NPolicyValueSample ->
    [ ("state", TReference (NodeTargets [NGameState]))
    , ("visitDistribution", TReference (NodeTargets [NTensorLeaf, NTensorManifest]))
    , ("outcome", TBits)
    ]
  NStarted -> [("observedStage", TNamed "StartCoverage")]
  NPpoSnapshot ->
    [ ("config", TReference (NodeTargets [NPpoConfig]))
    , ("initialParams", TReference (NodeTargets [NParams]))
    , ("adam", TReference (NodeTargets [NAdam]))
    , ("generator", TReference (NodeTargets [NGeneratorState]))
    , ("singleState", TNamed "StatePresenceOnly")
    , ("vectorSlots", TReference (SequenceTarget (ScalarElement ScalarSlotSummary)))
    , ("frames", TReference (SequenceTarget (AliasElement TensorAlias)))
    , ("countEntries", TReference (SequenceTarget (ScalarElement ScalarCountTriple)))
    , ("statistics", TReference (SequenceTarget (RefElement NPpoStat)))
    , ("actorSteps", TInt)
    , ("transitions", TNamed "MagnitudeInteger")
    , ("environmentName", TText GeneralTextBytes 1024)
    , ("observationWidth", TInt)
    , ("actionCount", TInt)
    ]
  NDqnSnapshot ->
    [ ("config", TReference (NodeTargets [NDqnConfig]))
    , ("initialParams", TReference (NodeTargets [NParams]))
    , ("onlineParams", TReference (NodeTargets [NParams]))
    , ("targetParams", TReference (NodeTargets [NParams]))
    , ("adam", TReference (NodeTargets [NAdam]))
    , ("generator", TReference (NodeTargets [NGeneratorState]))
    , ("replay", TReference (SequenceTarget (RefElement NDiscreteReplay)))
    , ("step", TInt)
    , ("state", TNamed "StateNotCaptured")
    , ("episodeLength", TInt)
    , ("episodeReturn", TBits)
    , ("recentReturns", TReference (SequenceTarget (ScalarElement ScalarBits)))
    , ("statistics", TReference (SequenceTarget (RefElement NDqnStat)))
    , ("environmentName", TText GeneralTextBytes 1024)
    , ("observationWidth", TInt)
    , ("actionCount", TInt)
    , ("frame", TReference (NodeTargets [NTensorLeaf, NTensorManifest]))
    ]
  NQrSnapshot ->
    [ ("config", TReference (NodeTargets [NQrConfig]))
    , ("initialParams", TReference (NodeTargets [NParams]))
    , ("onlineParams", TReference (NodeTargets [NParams]))
    , ("targetParams", TReference (NodeTargets [NParams]))
    , ("adam", TReference (NodeTargets [NAdam]))
    , ("generator", TReference (NodeTargets [NGeneratorState]))
    , ("replay", TReference (SequenceTarget (RefElement NDiscreteReplay)))
    , ("step", TInt)
    , ("state", TNamed "StateNotCaptured")
    , ("episodeLength", TInt)
    , ("episodeReturn", TBits)
    , ("recentReturns", TReference (SequenceTarget (ScalarElement ScalarBits)))
    , ("statistics", TReference (SequenceTarget (RefElement NQrStat)))
    , ("environmentName", TText GeneralTextBytes 1024)
    , ("observationWidth", TInt)
    , ("actionCount", TInt)
    , ("frame", TReference (NodeTargets [NTensorLeaf, NTensorManifest]))
    ]
  NContinuousSnapshot ->
    [ ("stage", TNamed "ContinuousPreparationStage")
    , ("config", TReference (NodeTargets [NContinuousConfig]))
    , ("coldActor", TReference (NodeTargets [NParams]))
    , ("actor", TReference (NodeTargets [NParams]))
    , ("criticA", TReference (NodeTargets [NParams]))
    , ("criticB", TReference (NodeTargets [NParams]))
    , ("targetActor", TOptional (TReference (NodeTargets [NParams])))
    , ("targetCriticA", TOptional (TReference (NodeTargets [NParams])))
    , ("targetCriticB", TOptional (TReference (NodeTargets [NParams])))
    , ("logAlpha", TBits)
    , ("actorAdam", TReference (NodeTargets [NAdam]))
    , ("criticAAdam", TReference (NodeTargets [NAdam]))
    , ("criticBAdam", TReference (NodeTargets [NAdam]))
    , ("warmAdam", TOptional (TReference (NodeTargets [NAdam])))
    , ("generator", TReference (NodeTargets [NGeneratorState]))
    , ("replay", TReference (SequenceTarget (RefElement NContinuousReplay)))
    , ("step", TInt)
    , ("state", TNamed "StateNotCaptured")
    , ("episodeLength", TInt)
    , ("episodeReturn", TBits)
    , ("recentReturns", TReference (SequenceTarget (ScalarElement ScalarBits)))
    , ("statistics", TReference (SequenceTarget (RefElement NContinuousStat)))
    , ("environmentName", TText GeneralTextBytes 1024)
    , ("observation", TReference (NodeTargets [NTensorLeaf, NTensorManifest]))
    , ("countEntries", TReference (SequenceTarget (ScalarElement ScalarCountTriple)))
    , ("warmUpdateCount", TInt)
    ]
  NHerSnapshot ->
    [ ("config", TReference (NodeTargets [NHerConfig]))
    , ("initialParams", TReference (NodeTargets [NParams]))
    , ("onlineParams", TReference (NodeTargets [NParams]))
    , ("targetParams", TReference (NodeTargets [NParams]))
    , ("adam", TReference (NodeTargets [NAdam]))
    , ("generator", TReference (NodeTargets [NGeneratorState]))
    , ("replay", TReference (SequenceTarget (RefElement NDiscreteReplay)))
    , ("episode", TInt)
    , ("observedTransitions", TNamed "MagnitudeInteger")
    , ("recentSuccesses", TReference (SequenceTarget (ScalarElement ScalarBool)))
    , ("statistics", TReference (SequenceTarget (RefElement NHerStat)))
    ]
  NArsSnapshot ->
    [ ("config", TReference (NodeTargets [NArsConfig]))
    , ("initialTheta", TReference (NodeTargets [NTensorLeaf, NTensorManifest]))
    , ("generator", TReference (NodeTargets [NGeneratorState]))
    , ("initialFrame", TReference (NodeTargets [NTensorLeaf, NTensorManifest]))
    ]
  NAlphaZeroSnapshot ->
    [ ("game", TText GeneralTextBytes 1024)
    , ("initialState", TReference (NodeTargets [NGameState]))
    , ("initialNet", TReference (NodeTargets [NPVN]))
    , ("initialAdam", TReference (NodeTargets [NAdam]))
    , ("hiddenUnits", TInt)
    , ("seed", TInt)
    , ("generationTarget", TInt)
    , ("games", TInt)
    , ("simulations", TInt)
    , ("maxPlies", TInt)
    , ("updates", TInt)
    ]
  NRawNeural ->
    [ ("family", TNamed "NeuralFamily")
    , ("actualLowBoundCompiledTransport", TText CompiledTransportBytes 32768)
    ,
      ( "expectedConfig"
      , TReference (NodeTargets [NPpoConfig, NDqnConfig, NQrConfig, NContinuousConfig, NHerConfig])
      )
    , ("expectedInitial", TReference (NodeTargets [NParams]))
    ,
      ( "actualConfig"
      , TReference (NodeTargets [NPpoConfig, NDqnConfig, NQrConfig, NContinuousConfig, NHerConfig])
      )
    , ("actualInitial", TReference (NodeTargets [NParams]))
    , ("actualFinal", TReference (NodeTargets [NParams]))
    , ("statistics", TReference (SequenceTarget (AliasElement NeuralStatAlias)))
    , ("observedTransitions", TWord)
    , ("observedUpdates", TWord)
    ]
  NRawArs ->
    [ ("compiledTransport", TText CompiledTransportBytes 32768)
    , ("actualConfig", TReference (NodeTargets [NArsConfig]))
    , ("initialTheta", TReference (NodeTargets [NTensorLeaf, NTensorManifest]))
    , ("finalTheta", TReference (NodeTargets [NTensorLeaf, NTensorManifest]))
    , ("iterations", TReference (SequenceTarget (RefElement NArsIterationObservation)))
    , ("observedTransitions", TWord)
    , ("observedUpdates", TWord)
    ]
  NRawAlphaZero ->
    [ ("initialState", TReference (NodeTargets [NGameState]))
    , ("initialNet", TReference (NodeTargets [NPVN]))
    , ("initialAdam", TReference (NodeTargets [NAdam]))
    , ("finalNet", TReference (NodeTargets [NPVN]))
    , ("finalAdam", TReference (NodeTargets [NAdam]))
    , ("samples", TReference (SequenceTarget (RefElement NPolicyValueSample)))
    , ("generationCount", TInt)
    , ("generationTarget", TInt)
    , ("games", TInt)
    , ("simulations", TInt)
    , ("maxPlies", TInt)
    , ("updates", TInt)
    , ("seed", TInt)
    ]
  NReturnEvaluation ->
    [ ("spec", TReference (NodeTargets [NReturnSpec]))
    , ("policy", TReference (NodeTargets [NReturnPolicy]))
    , ("episodes", TReference (SequenceTarget (RefElement NReturnEpisode)))
    , ("forwards", TReference (SequenceTarget (RefElement NReturnForward)))
    , ("status", TNamed "ReturnStatus")
    , ("work", TNamed "ReturnWork")
    , ("failedReturnedEpisodes", TOptional (TReference (SequenceTarget (RefElement NCommonEpisode))))
    ]
  NHerEvaluation ->
    [ ("schedule", TReference (NodeTargets [NHerSchedule]))
    , ("config", TReference (NodeTargets [NHerConfig]))
    , ("parameters", TReference (NodeTargets [NParams]))
    , ("outcomes", TReference (SequenceTarget (RefElement NHerOutcome)))
    , ("forwards", TReference (SequenceTarget (RefElement NHerForward)))
    , ("status", TNamed "HerStatus")
    , ("work", TNamed "HerWork")
    , ("failedProgress", TOptional (TReference (NodeTargets [NHerProgress])))
    ]
  NArenaEvaluation ->
    [ ("input", TOptional (TReference (NodeTargets [NArenaInput])))
    , ("episodes", TReference (SequenceTarget (RefElement NArenaEpisode)))
    , ("progress", TOptional (TReference (NodeTargets [NArenaProgress])))
    , ("forwards", TReference (NodeTargets [NArenaSummary]))
    , ("status", TNamed "ArenaStatus")
    , ("work", TNamed "ArenaWork")
    ]
  NSafeFailure ->
    [ ("family", TNamed "AttemptFamily")
    , ("stage", TNamed "FailureStage")
    , ("kind", TNamed "FailureKind")
    , ("diagnostic", TNamed "DiagnosticCapture")
    , ("returnMaterialization", TNamed "ReturnMaterialization")
    , ("captureStatus", TNamed "CaptureStatus")
    , ("payloadCoverage", TNamed "FailurePayloadCoverage6")
    ,
      ( "snapshot"
      , TOptional
          ( TReference
              ( NodeTargets
                  [ NPpoSnapshot
                  , NDqnSnapshot
                  , NQrSnapshot
                  , NContinuousSnapshot
                  , NHerSnapshot
                  , NArsSnapshot
                  , NAlphaZeroSnapshot
                  ]
              )
          )
      )
    ,
      ( "coldSnapshot"
      , TOptional
          ( TReference
              ( NodeTargets
                  [ NPpoSnapshot
                  , NDqnSnapshot
                  , NQrSnapshot
                  , NContinuousSnapshot
                  , NHerSnapshot
                  , NArsSnapshot
                  , NAlphaZeroSnapshot
                  ]
              )
          )
      )
    , ("raw", TOptional (TReference (NodeTargets [NRawNeural, NRawArs, NRawAlphaZero])))
    ,
      ( "initialEvaluation"
      , TOptional (TReference (NodeTargets [NReturnEvaluation, NHerEvaluation, NArenaEvaluation]))
      )
    ,
      ( "currentEvaluation"
      , TOptional (TReference (NodeTargets [NReturnEvaluation, NHerEvaluation, NArenaEvaluation]))
      )
    , ("lowFailure", TOptional (TReference (NodeTargets [NLowNeuralFailure])))
    ]
  NLowNeuralFailureFacts ->
    [ ("plan", TOptional (TText CompiledTransportBytes 32768))
    ,
      ( "expectedConfig"
      , TOptional
          (TReference (NodeTargets [NPpoConfig, NDqnConfig, NQrConfig, NContinuousConfig, NHerConfig]))
      )
    , ("initialParams", TOptional (TReference (NodeTargets [NParams])))
    ,
      ( "returnedConfig"
      , TOptional
          (TReference (NodeTargets [NPpoConfig, NDqnConfig, NQrConfig, NContinuousConfig, NHerConfig]))
      )
    , ("observedCounters", TNamed "MaybeObservedCounters")
    ]
  NLowNeuralFailure ->
    [ ("stage", TNamed "LowNeuralStage")
    , ("kind", TNamed "LowNeuralFailureKind")
    , ("diagnostic", TText DiagnosticTextBytes 1048576)
    , ("facts", TReference (NodeTargets [NLowNeuralFailureFacts]))
    ]
  NReturnSpec ->
    [ ("rowId", TText GeneralTextBytes 1024)
    , ("algorithm", TText GeneralTextBytes 1024)
    , ("environment", TText GeneralTextBytes 1024)
    , ("trainer", TText GeneralTextBytes 1024)
    , ("trainingBudget", TNamed "Budget3")
    , ("trainingSchedule", TNamed "RlTrainingSchedule")
    , ("episodeCount", TInt)
    , ("horizon", TInt)
    , ("observationWidth", TInt)
    , ("domain", TNamed "ReturnDomain")
    ]
  NReturnPolicy ->
    [ ("family", TNamed "AttemptFamily")
    ,
      ( "config"
      , TReference (NodeTargets [NPpoConfig, NDqnConfig, NQrConfig, NContinuousConfig, NArsConfig])
      )
    , ("parametersOrTheta", TReference (NodeTargets [NParams, NTensorLeaf, NTensorManifest]))
    ]
  NReturnEpisode -> [("caseId", TInt), ("reward", TBits), ("steps", TInt), ("terminated", TBool)]
  NReturnForward ->
    [ ("caseId", TInt)
    , ("callIndex", TNamed "MagnitudeInteger")
    , ("params", TReference (NodeTargets [NParams]))
    , ("input", TReference (NodeTargets [NTensorLeaf, NTensorManifest]))
    , ("outcome", TNamed "ForwardOutcome")
    ]
  NHerSpec ->
    [ ("rowId", TText GeneralTextBytes 1024)
    , ("bits", TInt)
    , ("horizon", TInt)
    , ("episodeCount", TInt)
    , ("baseSeed", TInt)
    , ("evaluationSeed", TInt)
    , ("trainingBudget", TNamed "Budget3")
    ]
  NHerGoalCase -> [("caseId", TInt), ("goal", TReference (NodeTargets [NTensorLeaf, NTensorManifest]))]
  NHerSchedule ->
    [ ("spec", TReference (NodeTargets [NHerSpec]))
    , ("cases", TReference (SequenceTarget (RefElement NHerGoalCase)))
    ]
  NHerOutcome ->
    [ ("caseId", TInt)
    , ("goal", TReference (NodeTargets [NTensorLeaf, NTensorManifest]))
    , ("finalState", TReference (NodeTargets [NTensorLeaf, NTensorManifest]))
    , ("success", TBool)
    , ("normalizedDistance", TBits)
    , ("hammingDistance", TInt)
    , ("steps", TInt)
    , ("terminated", TBool)
    , ("consumedActions", TReference (SequenceTarget (ScalarElement ScalarInt)))
    ]
  NHerForward ->
    [ ("caseId", TInt)
    , ("callIndex", TInt)
    , ("params", TReference (NodeTargets [NParams]))
    , ("input", TReference (NodeTargets [NTensorLeaf, NTensorManifest]))
    , ("outcome", TNamed "ForwardOutcome")
    ]
  NHerProgress ->
    [ ("caseId", TInt)
    , ("goal", TReference (NodeTargets [NTensorLeaf, NTensorManifest]))
    , ("state", TReference (NodeTargets [NTensorLeaf, NTensorManifest]))
    , ("actions", TReference (SequenceTarget (ScalarElement ScalarInt)))
    , ("transitions", TInt)
    , ("phase", TNamed "HerPhase")
    ]
  NArenaSpec ->
    [ ("gameKey", TText GeneralTextBytes 1024)
    , ("trainingBudget", TNamed "Budget3")
    , ("trainingSimulations", TWord)
    , ("actionCount", TInt)
    , ("observationSize", TInt)
    , ("maxPlies", TInt)
    , ("arenaSimulations", TInt)
    , ("tapeSpec", TNamed "ArenaTapeSpec6")
    ]
  NArenaTape -> [("canonicalBytes", TBytes TensorChunkBytes 1048576)]
  NArenaInput ->
    [ ("scope", TNamed "ArenaScope")
    , ("spec", TOptional (TReference (NodeTargets [NArenaSpec])))
    , ("initialState", TReference (NodeTargets [NGameState]))
    , ("tape", TReference (NodeTargets [NArenaTape]))
    , ("policy", TReference (NodeTargets [NPVN]))
    ]
  NArenaForward ->
    [ ("game", TInt)
    , ("slot", TInt)
    , ("ordinal", TNamed "MagnitudeInteger")
    , ("params", TReference (NodeTargets [NParams]))
    , ("input", TReference (NodeTargets [NTensorLeaf, NTensorManifest]))
    , ("outcome", TNamed "ForwardOutcome")
    ]
  NArenaSummary ->
    [ ("calls", TNamed "MagnitudeInteger")
    , ("firstForwards", TReference (SequenceTarget (RefElement NArenaForward)))
    , ("failedForward", TOptional (TReference (NodeTargets [NArenaForward])))
    ]
  NArenaDecision ->
    [ ("slot", TInt)
    , ("rawState", TReference (NodeTargets [NGameState]))
    , ("normalizedState", TReference (NodeTargets [NGameState]))
    , ("forcedPass", TBool)
    , ("player", TInt)
    , ("legalActions", TReference (SequenceTarget (ScalarElement ScalarInt)))
    , ("distribution", TReference (NodeTargets [NTensorLeaf, NTensorManifest]))
    , ("action", TInt)
    , ("tapeEntry", TReference (NodeTargets [NTapeEntry]))
    , ("searchRootVisits", TInt)
    , ("postState", TReference (NodeTargets [NGameState]))
    , ("postOutcome", TNamed "GameOutcome")
    ]
  NArenaEpisode ->
    [ ("caseId", TInt)
    , ("initialState", TReference (NodeTargets [NGameState]))
    , ("finalState", TReference (NodeTargets [NGameState]))
    , ("ruleOutcome", TNamed "GameOutcome")
    , ("scoredOutcome", TNamed "GameOutcome")
    , ("horizonTruncated", TBool)
    , ("decisions", TReference (SequenceTarget (RefElement NArenaDecision)))
    ]
  NArenaProgress ->
    [ ("game", TInt)
    , ("transitions", TInt)
    , ("state", TReference (NodeTargets [NGameState]))
    , ("decisions", TReference (SequenceTarget (RefElement NArenaDecision)))
    ]
  NGameState ->
    [ ("gameName", TText GeneralTextBytes 1024)
    , ("moves", TReference (SequenceTarget (ScalarElement ScalarInt)))
    , ("currentPlayer", TInt)
    ]
  NTapeEntry ->
    [ ("game", TWord)
    , ("slot", TWord)
    , ("signedPlayer", TInt)
    , ("sideCode", TWord)
    , ("q", TWord)
    , ("unit", TBits)
    , ("mctsSeed", TInt)
    ]
  NCommonEpisode -> [("reward", TBits), ("steps", TInt), ("terminated", TBool)]

namedType :: Text -> Maybe FieldType
namedType name = case name of
  "OnPolicyVariant" -> Just (TEnum [0, 1, 2, 3, 4])
  "ContinuousVariant" -> Just (TEnum [0, 1, 2, 3, 4])
  "HerStrategy" -> Just (TEnum [0, 1, 2])
  "BudgetKind" -> Just (TEnum [0, 1, 2, 3])
  "ContinuousPreparationStage" -> Just (TEnum [0, 1])
  "NeuralFamily" -> Just (TEnum [0, 1, 2, 3, 4])
  "AttemptFamily" -> Just (TEnum [0, 1, 2, 3, 4, 5, 6])
  "HerPhase" -> Just (TEnum [0, 1, 2, 3])
  "ArenaScope" -> Just (TEnum [0, 1])
  "ReturnFailureKind" -> Just (TEnum [0, 1, 2, 3, 4])
  "HerFailureKind" -> Just (TEnum [0, 1, 2, 3, 4, 5])
  "ArenaFailureKind" -> Just (TEnum [0, 1, 2, 3, 4, 5, 6])
  "ReturnMaterialization" -> Just (TEnum [0, 1, 2, 3])
  "RuntimeMetadataCoverage" -> Just (TEnum [0, 1])
  "StartCoverage" -> Just (TEnum [0, 1])
  "LowNeuralStage" -> Just (TEnum [0, 1, 2, 3, 4, 5, 6, 7])
  "LowNeuralFailureKind" -> Just (TEnum [0, 1, 2])
  "neuralStage" -> Just (TEnum [0, 1, 2, 3, 4, 5, 6])
  "neuralFailureKind" -> Just (TEnum [0, 1, 2, 3, 4])
  "arsStage" -> Just (TEnum [0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
  "arsFailureKind" -> Just (TEnum [0, 1, 2, 3])
  "alphazeroStage" -> Just (TEnum [0, 1, 2, 3, 4, 5])
  "alphazeroFailureKind" -> Just (TEnum [0, 1, 2, 3, 4])
  "Shape3" -> Just (TTuple [TInt, TInt, TInt])
  "Budget3" -> Just (TTuple [TNamed "BudgetKind", TWord, TOptional TWord])
  "EvaluationPlan1" -> Just (TTuple [TInt])
  "RlTrainingSchedule" ->
    Just
      ( TSum
          [ (0, [TWord, TInt, TInt, TInt, TInt])
          , (1, [TWord, TInt, TInt])
          , (2, [TWord, TInt, TInt, TInt])
          , (3, [TWord, TInt, TInt])
          ]
      )
  "ArenaTapeSpec6" -> Just (TTuple [TText GeneralTextBytes 1024, TWord, TWord, TWord, TWord, TWord])
  "ObservedSource2" -> Just (TTuple [TText PathTextBytes 4096, TNamed "SourceStamp2"])
  "MaybeObservedSource" -> Just (TOptional (TNamed "ObservedSource2"))
  "SourceStamp2" -> Just (TTuple [TWord, TDigest])
  "MaybeObservedCounters" -> Just (TOptional (TTuple [TWord, TWord]))
  "StateNotCaptured" -> Just (TSum [(0, [])])
  "StatePresenceOnly" -> Just (TSum [(0, []), (1, [])])
  "SlotSummary" -> Just (TTuple [TNamed "StateNotCaptured", TBits, TInt])
  "CountTriple" -> Just (TTuple [TInt, TInt, TInt])
  "GameOutcome" -> Just (TSum [(0, []), (1, []), (2, [TInt])])
  "ReturnDomain" -> Just (TSum [(0, [TInt]), (1, [TInt]), (2, [TBits, TBits])])
  "ForwardOutcome" ->
    Just
      ( TSum
          [ (0, [TReference (NodeTargets [NTensorLeaf, NTensorManifest])])
          , (1, [TText DiagnosticTextBytes 1048576])
          , (2, [TText DiagnosticTextBytes 1048576])
          ]
      )
  "ReturnStatus" ->
    Just
      ( TSum
          [ (0, [])
          , (1, [TText DiagnosticTextBytes 1048576])
          , (2, [TInt, TNamed "ReturnFailureKind", TText DiagnosticTextBytes 1048576])
          ]
      )
  "ReturnWork" ->
    Just
      ( TSum
          [ (0, [TNamed "MagnitudeInteger"])
          , (1, [])
          , (2, [TNamed "MagnitudeInteger", TNamed "MaybeMagnitudeInteger"])
          ]
      )
  "HerStatus" ->
    Just
      ( TSum
          [ (0, [])
          , (1, [TNamed "HerFailureKind", TText DiagnosticTextBytes 1048576])
          , (2, [TInt, TNamed "HerFailureKind", TText DiagnosticTextBytes 1048576])
          ]
      )
  "HerWork" ->
    Just
      ( TSum
          [ (0, [TNamed "MagnitudeInteger"])
          , (1, [])
          , (2, [TNamed "MagnitudeInteger", TNamed "MagnitudeInteger", TNamed "MaybeMagnitudeInteger"])
          ]
      )
  "ArenaStatus" ->
    Just
      ( TSum
          [ (0, [])
          , (1, [TText DiagnosticTextBytes 1048576])
          , (2, [TInt, TInt, TNamed "ArenaFailureKind", TText DiagnosticTextBytes 1048576])
          ]
      )
  "ArenaWork" ->
    Just
      ( TTuple
          [TNamed "MagnitudeInteger", TNamed "MagnitudeInteger", TNamed "MagnitudeInteger", TEnum [0, 1]]
      )
  "DiagnosticCapture" -> Just (TSum [(0, [TText DiagnosticTextBytes 1048576]), (1, [TNamed "SizeKnowledge"]), (2, [])])
  "SizeKnowledge" -> Just (TSum [(0, [TWord]), (1, [TWord]), (2, [])])
  "FamilyStage" ->
    Just (TSum [(0, [TNamed "neuralStage"]), (1, [TNamed "arsStage"]), (2, [TNamed "alphazeroStage"])])
  "FamilyFailureKind" ->
    Just
      ( TSum
          [ (0, [TNamed "neuralFailureKind"])
          , (1, [TNamed "arsFailureKind"])
          , (2, [TNamed "alphazeroFailureKind"])
          ]
      )
  "FailureStage" -> Just (TSum [(0, [TNamed "FamilyStage"]), (1, [TEnum [0, 1, 2, 3, 4, 5, 6]])])
  "FailureKind" -> Just (TSum [(0, [TNamed "FamilyFailureKind"]), (1, [TNamed "CaptureStatus"])])
  "CaptureStatus" ->
    Just
      ( TSum
          [ (0, [])
          , (1, [TText GeneralTextBytes 1024, TText GeneralTextBytes 1024])
          , (2, [TNamed "ResourceKind", TWord, TNamed "SizeKnowledge"])
          , (3, [TText GeneralTextBytes 1024])
          ]
      )
  "FailurePayloadCoverage6" ->
    Just
      ( TTuple
          [ TNamed "PayloadCoverage"
          , TNamed "PayloadCoverage"
          , TNamed "PayloadCoverage"
          , TNamed "PayloadCoverage"
          , TNamed "PayloadCoverage"
          , TNamed "PayloadCoverage"
          ]
      )
  "PayloadCoverage" ->
    Just
      ( TSum
          [ (0, [])
          , (1, [])
          , (2, [])
          , (3, [])
          , (4, [TNamed "ResourceKind", TWord, TNamed "SizeKnowledge"])
          , (5, [])
          ]
      )
  "MagnitudeInteger" -> Just TMagnitude
  "MaybeMagnitudeInteger" -> Just (TOptional TMagnitude)
  "ElementKind" -> Just TElementKind
  "Height0to2" -> Just (TEnum [0, 1, 2])
  "Word64Pair" -> Just (TTuple [TWord, TWord])
  "NestedPlanIds7" -> Just (TTuple [TDigest, TDigest, TDigest, TDigest, TDigest, TDigest, TOptional TDigest])
  "AssociationData" -> Just (TSum [(0, []), (1, [TText InvocationTextBytes 8192, TText AssociationTextBytes 131072])])
  "InvocationContext" -> Just (TSum [(0, [TDigest]), (1, [TDigest])])
  "SourceCoverage" -> Just (TTuple [TNamed "MaybeSourceStamp2", TNamed "MaybeSourceStamp2"])
  "MaybeSourceStamp2" -> Just (TOptional (TNamed "SourceStamp2"))
  "Substrate" -> Just (TEnum [0, 1, 2])
  "Coverage" -> Just (TTuple [TExactWord 0, TExactWord 0, TExactWord 0, TExactWord 0])
  "ResourceKind" ->
    Just
      (TEnum [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25])
  _ -> Nothing

contextTypes :: [(Text, FieldType)]
contextTypes =
  [ ("rowId", TText GeneralTextBytes 1024)
  , ("substrate", TNamed "Substrate")
  , ("parentSingletonTransport", TText SingletonTransportBytes 32768)
  , ("rowFiveChildCohortTransport", TText CohortTransportBytes 1048576)
  , ("childSingletonTransport", TText SingletonTransportBytes 32768)
  , ("nestedPlanIds", TNamed "NestedPlanIds7")
  , ("actualCompiledOrOuterAlphaZeroId", TDigest)
  , ("association", TNamed "AssociationData")
  , ("childIndex", TWord)
  , ("childSeed", TWord)
  , ("trainingBudget", TNamed "Budget3")
  , ("attemptId", TDigest)
  , ("acquisitionId", TDigest)
  , ("invocationOrLocalContext", TNamed "InvocationContext")
  , ("sourceCoverage", TNamed "SourceCoverage")
  , ("producer", TReference (NodeTargets [NProducerContextBundle]))
  ]

-- Only field element kinds present in the frozen schema may form sequences.
sequenceElementKinds :: [ElementKind]
sequenceElementKinds =
  [ RefElement NArenaDecision
  , RefElement NArenaEpisode
  , RefElement NArenaForward
  , RefElement NArsIterationObservation
  , RefElement NArsKeptDirection
  , RefElement NArsPerturbation
  , ScalarElement ScalarBool
  , RefElement NCommonEpisode
  , RefElement NContinuousReplay
  , RefElement NContinuousStat
  , ScalarElement ScalarCountTriple
  , RefElement NDiscreteReplay
  , RefElement NDqnStat
  , ScalarElement ScalarBits
  , RefElement NHerForward
  , RefElement NHerGoalCase
  , RefElement NHerOutcome
  , RefElement NHerStat
  , AliasElement NeuralStatAlias
  , RefElement NPolicyValueSample
  , RefElement NPpoStat
  , RefElement NQrStat
  , RefElement NReturnEpisode
  , RefElement NReturnForward
  , ScalarElement ScalarInt
  , ScalarElement ScalarSlotSummary
  , AliasElement TensorAlias
  ]

allowedPhaseKinds :: PhaseTag -> [NodeKind]
allowedPhaseKinds phase = case phase of
  StartedPhase -> [NStarted]
  ColdSnapshotPhase ->
    [ NPpoSnapshot
    , NDqnSnapshot
    , NQrSnapshot
    , NContinuousSnapshot
    , NHerSnapshot
    , NArsSnapshot
    , NAlphaZeroSnapshot
    ]
  EffectiveSnapshotPhase ->
    [ NPpoSnapshot
    , NDqnSnapshot
    , NQrSnapshot
    , NContinuousSnapshot
    , NHerSnapshot
    , NArsSnapshot
    , NAlphaZeroSnapshot
    ]
  InitialEvaluationPhase -> [NReturnEvaluation, NHerEvaluation, NArenaEvaluation]
  RawReturnPhase -> [NRawNeural, NRawArs, NRawAlphaZero]
  FinalEvaluationPhase -> [NReturnEvaluation, NHerEvaluation, NArenaEvaluation]
  FailurePhase -> [NSafeFailure]

scalarType :: ScalarKind -> FieldType
scalarType kind = case kind of
  ScalarInt -> TInt
  ScalarBool -> TBool
  ScalarBits -> TBits
  ScalarCountTriple -> TNamed "CountTriple"
  ScalarSlotSummary -> TNamed "SlotSummary"

elementTarget :: ElementKind -> Either CodecError ReferenceTarget
elementTarget kind = case kind of
  RefElement value -> Right (NodeTargets [value])
  AliasElement value -> Right (NodeTargets (aliasKinds value))
  ScalarElement _ -> Left (Malformed "scalar element cannot be a node reference")
