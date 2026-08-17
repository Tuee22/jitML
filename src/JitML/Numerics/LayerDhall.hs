{-# LANGUAGE OverloadedStrings #-}

-- | Sprint 77.1 — the layer vocabulary as __parameterised Dhall constructors__,
-- reflected off the real decoder.
--
-- The numerics catalog leaves (@dhall/numerics/Layer.dhall@ and friends) are
-- Dhall /values/: hand-free lists of constructor names emitted from
-- 'JitML.Numerics.Catalog'. They name the vocabulary but carry no geometry, so
-- they cannot describe an architecture. This module adds the missing half — the
-- Dhall /type/ of the executed operator 'LayerOp', complete with each
-- operator's real geometry, read back off the same 'Dhall.Decoder' the loader
-- uses via 'Dhall.expected'. That is the convention already proven for
-- @BootConfig@ and @dhall/run/Schema.dhall@ in 'JitML.Service.DhallSchema': the
-- checked-in schema cannot drift from the Haskell type, because it /is/ the
-- Haskell type.
--
-- Three surfaces close the loop:
--
--   * 'layerOpDecoder' decodes a parameterised Dhall union into the executed
--     'LayerOp'. 'layerOpSchema' is its reflected type, emitted to
--     @dhall/numerics/LayerOp.dhall@.
--   * 'renderLayerOp' writes an operator back out as Dhall text. The unit lane
--     asserts @decode . render == id@ over every operator witness, so the
--     decoder cannot silently stop covering a constructor.
--   * 'layerOpAuditMismatches' is the cross-type audit extended to the
--     /executed/ operator (Sprint 77.1's second obligation): the reflected
--     union's alternatives must be exactly the constructors of 'LayerOp', and
--     each one must project onto exactly one 'Catalog.Layer' through 'opLayer'.
--
-- 'LayerGraphDescription' lifts the vocabulary to a whole architecture — nodes
-- plus shapes plus a seed — so a network is data rather than a hardcoded
-- Haskell builder. 'buildLayerGraph' realises a description through the
-- correctness-checked smart constructors and __fails closed__ when the
-- description's declared shapes disagree with the geometry its operators
-- actually produce.
--
-- The DSL deliberately carries no @substrate@ field: an architecture is
-- substrate-independent, and substrate selection lives on the CLI/plan seam.
-- 'mlDslSubstrateMentions' is the standing guard for that.
module JitML.Numerics.LayerDhall
  ( -- * Reflected schema
    layerOpSchema
  , layerGraphSchema
  , layerOpSchemaPath
  , layerGraphSchemaPath
  , numericsTypeSchemas
  , numericsTypeFileSchemas

    -- * Decoders
  , layerOpDecoder
  , layerNodeDescriptionDecoder
  , layerGraphDescriptionDecoder
  , loadLayerGraphDescription

    -- * Architecture descriptions
  , LayerNodeDescription (..)
  , LayerGraphDescription (..)
  , buildLayerGraph
  , layerNodeFromOp

    -- * Dhall rendering (the round-trip side)
  , renderLayerOp
  , renderLayerGraphDescription

    -- * Cross-type audit
  , layerOpUnionAlternatives
  , executedLayerOpAlternatives
  , layerOpAuditMismatches
  , mlDslSubstrateMentions
  )
where

import Data.Either.Validation (Validation (..))
import Data.List qualified as List
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Void (Void)
import Dhall qualified
import Dhall.Core (Expr)
import Dhall.Core qualified as Core
import Dhall.Map qualified as DhallMap
import Dhall.Src (Src)
import Numeric.Natural (Natural)

import JitML.Dhall.Reflect (reflectedSchemaText)
import JitML.Numerics.Catalog qualified as Catalog
import JitML.Numerics.LayerGraph
  ( AffineSpec (..)
  , AttentionSpec (..)
  , BlockSpec (..)
  , BlockStage (..)
  , ConvSpec (..)
  , GeGLUSpec (..)
  , LayerActivation (..)
  , LayerGraph (..)
  , LayerMode (..)
  , LayerNode (..)
  , LayerOp (..)
  , LayerParameters
  , NormFlavor (..)
  , NormSpec (..)
  , PatchSpec (..)
  , PoolSpec (..)
  , PoolWindow (..)
  , Shortcut (..)
  , SpatialShape (..)
  , TensorShape (..)
  , blockIsBottleneck
  , deterministicOpParameters
  , deterministicParameters
  , layerOpName
  , layerOpTemplate
  , mkAffineLayer
  , mkAttentionLayer
  , mkBasicBlock
  , mkBottleneck
  , mkConv3DLayer
  , mkConvLayer
  , mkDropoutLayer
  , mkGeGLULayer
  , mkIdentityLayer
  , mkNormLayer
  , mkPatchEmbedLayer
  , mkPoolLayer
  , mkResidualNode
  , opLayer
  , tensorShapeWidth
  )

-- ---------------------------------------------------------------------------
-- Descriptions
-- ---------------------------------------------------------------------------

-- | One described node: the operator plus the shapes the description claims it
-- has. The claim is checked against the geometry the operator actually
-- produces in 'buildLayerGraph'; parameters are never described, they are
-- derived deterministically from the graph seed.
data LayerNodeDescription = LayerNodeDescription
  { descNodeName :: !Text
  , descNodeOp :: !LayerOp
  , descNodeInputShape :: !TensorShape
  , descNodeOutputShape :: !TensorShape
  , descNodeMode :: !LayerMode
  , descNodeActivation :: !LayerActivation
  }
  deriving stock (Eq, Show)

-- | A whole architecture as data. @descGraphSeed@ fixes the deterministic
-- initialiser, so a description names exactly one graph.
data LayerGraphDescription = LayerGraphDescription
  { descGraphName :: !Text
  , descGraphSeed :: !Int
  , descGraphInputShape :: !TensorShape
  , descGraphOutputShape :: !TensorShape
  , descGraphNodes :: ![LayerNodeDescription]
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------------
-- Decoders
-- ---------------------------------------------------------------------------

naturalDecoder :: Dhall.Decoder Int
naturalDecoder = fromIntegral <$> Dhall.natural

shapeDecoder :: Dhall.Decoder TensorShape
shapeDecoder = TensorShape <$> Dhall.list naturalDecoder

layerModeDecoder :: Dhall.Decoder LayerMode
layerModeDecoder =
  Dhall.union $
    Dhall.constructor "TrainingMode" (TrainingMode <$ Dhall.unit)
      <> Dhall.constructor "InferenceMode" (InferenceMode <$ Dhall.unit)

layerActivationDecoder :: Dhall.Decoder LayerActivation
layerActivationDecoder =
  Dhall.union $
    Dhall.constructor "LinearActivation" (LinearActivation <$ Dhall.unit)
      <> Dhall.constructor "TanhActivation" (TanhActivation <$ Dhall.unit)
      <> Dhall.constructor "ReluActivation" (ReluActivation <$ Dhall.unit)
      <> Dhall.constructor "SoftmaxActivation" (SoftmaxActivation <$ Dhall.unit)

convSpecDecoder :: Dhall.Decoder ConvSpec
convSpecDecoder =
  Dhall.record $
    ConvSpec
      <$> Dhall.field "convIn" naturalDecoder
      <*> Dhall.field "convOut" naturalDecoder
      <*> Dhall.field "convInputDims" (Dhall.list naturalDecoder)
      <*> Dhall.field "convKernelDims" (Dhall.list naturalDecoder)
      <*> Dhall.field "convStride" (Dhall.list naturalDecoder)
      <*> Dhall.field "convPadding" (Dhall.list naturalDecoder)

spatialShapeDecoder :: Dhall.Decoder SpatialShape
spatialShapeDecoder =
  Dhall.record $
    SpatialShape
      <$> Dhall.field "spC" naturalDecoder
      <*> Dhall.field "spH" naturalDecoder
      <*> Dhall.field "spW" naturalDecoder

poolWindowDecoder :: Dhall.Decoder PoolWindow
poolWindowDecoder =
  Dhall.record $
    PoolWindow
      <$> Dhall.field "pwKh" naturalDecoder
      <*> Dhall.field "pwKw" naturalDecoder
      <*> Dhall.field "pwSh" naturalDecoder
      <*> Dhall.field "pwSw" naturalDecoder
      <*> Dhall.field "pwPh" naturalDecoder
      <*> Dhall.field "pwPw" naturalDecoder
      <*> Dhall.field "pwCountPad" Dhall.bool

poolSpecDecoder :: Dhall.Decoder PoolSpec
poolSpecDecoder =
  Dhall.union $
    Dhall.constructor "PoolMax" (PoolMax <$> poolWindowDecoder)
      <> Dhall.constructor "PoolAvg" (PoolAvg <$> poolWindowDecoder)
      <> Dhall.constructor "PoolGlobal" (PoolGlobal <$ Dhall.unit)

normFlavorDecoder :: Dhall.Decoder NormFlavor
normFlavorDecoder =
  Dhall.union $
    Dhall.constructor "NormBatch" (NormBatch <$ Dhall.unit)
      <> Dhall.constructor "NormLayerWise" (NormLayerWise <$ Dhall.unit)
      <> Dhall.constructor "NormGroup" (NormGroup <$> naturalDecoder)

normSpecDecoder :: Dhall.Decoder NormSpec
normSpecDecoder =
  Dhall.record $
    NormSpec
      <$> Dhall.field "nFlavor" normFlavorDecoder
      <*> Dhall.field "nChannels" naturalDecoder
      <*> Dhall.field "nSpatial" naturalDecoder
      <*> Dhall.field "nEps" Dhall.double

attentionSpecDecoder :: Dhall.Decoder AttentionSpec
attentionSpecDecoder =
  Dhall.record $
    AttentionSpec
      <$> Dhall.field "attnSeqLen" naturalDecoder
      <*> Dhall.field "attnEmbedDim" naturalDecoder
      <*> Dhall.field "attnNumHeads" naturalDecoder
      <*> Dhall.field "attnCausal" Dhall.bool

geGLUSpecDecoder :: Dhall.Decoder GeGLUSpec
geGLUSpecDecoder =
  Dhall.record $
    GeGLUSpec
      <$> Dhall.field "ggIn" naturalDecoder
      <*> Dhall.field "ggFf" naturalDecoder
      <*> Dhall.field "ggOut" naturalDecoder

affineSpecDecoder :: Dhall.Decoder AffineSpec
affineSpecDecoder =
  Dhall.record $
    AffineSpec
      <$> Dhall.field "asIn" naturalDecoder
      <*> Dhall.field "asOut" naturalDecoder

shortcutDecoder :: Dhall.Decoder Shortcut
shortcutDecoder =
  Dhall.union $
    Dhall.constructor "IdentityShortcut" (IdentityShortcut <$ Dhall.unit)
      <> Dhall.constructor "ProjectionShortcut" (ProjectionShortcut <$> affineSpecDecoder)

blockStageDecoder :: Dhall.Decoder BlockStage
blockStageDecoder =
  Dhall.record $
    BlockStage
      <$> Dhall.field "bsAffine" affineSpecDecoder
      <*> Dhall.field "bsNorm" (Dhall.maybe normSpecDecoder)
      <*> Dhall.field "bsAct" layerActivationDecoder

blockSpecDecoder :: Dhall.Decoder BlockSpec
blockSpecDecoder =
  Dhall.record $
    BlockSpec
      <$> Dhall.field "blStages" (Dhall.list blockStageDecoder)
      <*> Dhall.field "blShortcut" shortcutDecoder
      <*> Dhall.field "blScale" Dhall.double
      <*> Dhall.field "blFinalAct" layerActivationDecoder

patchSpecDecoder :: Dhall.Decoder PatchSpec
patchSpecDecoder =
  Dhall.record $
    PatchSpec
      <$> Dhall.field "peC" naturalDecoder
      <*> Dhall.field "peH" naturalDecoder
      <*> Dhall.field "peW" naturalDecoder
      <*> Dhall.field "peP" naturalDecoder
      <*> Dhall.field "peStride" naturalDecoder
      <*> Dhall.field "peD" naturalDecoder

poolOpDecoder :: Dhall.Decoder LayerOp
poolOpDecoder =
  Dhall.record $
    PoolOp
      <$> Dhall.field "shape" spatialShapeDecoder
      <*> Dhall.field "pool" poolSpecDecoder

residualOpDecoder :: Dhall.Decoder LayerOp
residualOpDecoder =
  Dhall.record $
    ResidualOp
      <$> Dhall.field "inner" affineSpecDecoder
      <*> Dhall.field "shortcut" shortcutDecoder
      <*> Dhall.field "scale" Dhall.double
      <*> Dhall.field "innerActivation" layerActivationDecoder

-- | The executed operator vocabulary as a parameterised Dhall union. Each
-- alternative carries the operator's real geometry, so a described network is
-- executable without a hardcoded Haskell builder.
layerOpDecoder :: Dhall.Decoder LayerOp
layerOpDecoder =
  Dhall.union $
    Dhall.constructor "DenseOp" (DenseOp <$ Dhall.unit)
      <> Dhall.constructor "IdentityOp" (IdentityOp <$ Dhall.unit)
      <> Dhall.constructor "DropoutOp" (DropoutOp <$> Dhall.double)
      <> Dhall.constructor "ConvOp" (ConvOp <$> convSpecDecoder)
      <> Dhall.constructor "PoolOp" poolOpDecoder
      <> Dhall.constructor "NormOp" (NormOp <$> normSpecDecoder)
      <> Dhall.constructor "AttentionOp" (AttentionOp <$> attentionSpecDecoder)
      <> Dhall.constructor "GeGLUOp" (GeGLUOp <$> geGLUSpecDecoder)
      <> Dhall.constructor "PatchOp" (PatchOp <$> patchSpecDecoder)
      <> Dhall.constructor "ResidualOp" residualOpDecoder
      <> Dhall.constructor "BlockOp" (BlockOp <$> blockSpecDecoder)

layerNodeDescriptionDecoder :: Dhall.Decoder LayerNodeDescription
layerNodeDescriptionDecoder =
  Dhall.record $
    LayerNodeDescription
      <$> Dhall.field "name" Dhall.strictText
      <*> Dhall.field "op" layerOpDecoder
      <*> Dhall.field "inputShape" shapeDecoder
      <*> Dhall.field "outputShape" shapeDecoder
      <*> Dhall.field "mode" layerModeDecoder
      <*> Dhall.field "activation" layerActivationDecoder

layerGraphDescriptionDecoder :: Dhall.Decoder LayerGraphDescription
layerGraphDescriptionDecoder =
  Dhall.record $
    LayerGraphDescription
      <$> Dhall.field "name" Dhall.strictText
      <*> Dhall.field "seed" naturalDecoder
      <*> Dhall.field "inputShape" shapeDecoder
      <*> Dhall.field "outputShape" shapeDecoder
      <*> Dhall.field "nodes" (Dhall.list layerNodeDescriptionDecoder)

-- | Decode an architecture description from a checked-in @.dhall@ file.
loadLayerGraphDescription :: FilePath -> IO LayerGraphDescription
loadLayerGraphDescription = Dhall.inputFile layerGraphDescriptionDecoder

-- ---------------------------------------------------------------------------
-- Reflected schema
-- ---------------------------------------------------------------------------

layerOpSchemaPath :: FilePath
layerOpSchemaPath = "dhall/numerics/LayerOp.dhall"

layerGraphSchemaPath :: FilePath
layerGraphSchemaPath = "dhall/numerics/LayerGraph.dhall"

-- | The reflected type of 'layerOpDecoder' — the content of
-- @dhall/numerics/LayerOp.dhall@.
layerOpSchema :: Text
layerOpSchema = reflectedSchemaText layerOpDecoder

-- | The reflected type of 'layerGraphDescriptionDecoder' — the content of
-- @dhall/numerics/LayerGraph.dhall@.
layerGraphSchema :: Text
layerGraphSchema = reflectedSchemaText layerGraphDescriptionDecoder

-- | The reflected numerics /type/ schemas, keyed by the name used on the
-- @jitml internal dhall-schema --config@ leaf.
numericsTypeSchemas :: [(Text, Text)]
numericsTypeSchemas =
  [ ("LayerOp", layerOpSchema)
  , ("LayerGraph", layerGraphSchema)
  ]

-- | The checked-in type file each reflected numerics schema maps to, with the
-- trailing newline the file carries. Parity is compared after canonicalisation,
-- so the newline is a file convention rather than part of the schema.
numericsTypeFileSchemas :: [(FilePath, Text)]
numericsTypeFileSchemas =
  [ (layerOpSchemaPath, layerOpSchema <> "\n")
  , (layerGraphSchemaPath, layerGraphSchema <> "\n")
  ]

-- ---------------------------------------------------------------------------
-- Cross-type audit (Sprint 77.1 — extended to the executed operator)
-- ---------------------------------------------------------------------------

-- | The alternative names of the reflected 'layerOpDecoder' union, read out of
-- the reflected expression rather than restated.
layerOpUnionAlternatives :: Either Text [Text]
layerOpUnionAlternatives =
  case Dhall.expected layerOpDecoder of
    Failure errs -> Left ("layer operator schema failed to reflect: " <> Text.pack (show errs))
    Success expr -> unionAlternatives expr

unionAlternatives :: Expr Src Void -> Either Text [Text]
unionAlternatives expr =
  case Core.denote expr :: Expr Void Void of
    Core.Union alternatives -> Right (DhallMap.keys alternatives)
    other -> Left ("expected a union type, got: " <> Core.pretty other)

-- | The constructors of the /executed/ operator, derived from the catalog
-- through 'layerOpTemplate' so the list cannot be hand-maintained: a new
-- 'Catalog.Layer' fails @-Werror=incomplete-patterns@ in 'layerOpTemplate', and
-- a new 'LayerOp' fails it in 'layerOpName' and 'opLayer'.
executedLayerOpAlternatives :: [Text]
executedLayerOpAlternatives =
  fmap (layerOpName . layerOpTemplate) Catalog.layerCatalog

-- | The cross-type audit extended from @Catalog.Layer@ to the executed
-- 'LayerOp': the Dhall union describes exactly the operators the IR executes,
-- and each alternative projects onto exactly one catalog constructor.
layerOpAuditMismatches :: [Text]
layerOpAuditMismatches =
  case layerOpUnionAlternatives of
    Left err -> [err]
    Right alternatives -> alternativeMismatch alternatives <> projectionMismatch
 where
  alternativeMismatch alternatives =
    [ "layer operator schema mismatch: expected ["
        <> Text.intercalate ", " expected
        <> "], got ["
        <> Text.intercalate ", " (List.sort alternatives)
        <> "]"
    | List.sort alternatives /= expected
    ]
  projectionMismatch =
    [ "layer operator projection is not one-to-one onto the catalog: "
        <> Text.intercalate ", " (fmap renderCollision collisions)
    | not (null collisions)
    ]
  expected = List.sort executedLayerOpAlternatives
  projections =
    [ (layerOpName op, Text.pack (show (opLayer op)))
    | layer <- Catalog.layerCatalog
    , let op = layerOpTemplate layer
    ]
  collisions =
    [ (name, targets)
    | name <- List.nub (fmap fst projections)
    , let targets = List.nub [target | (n, target) <- projections, n == name]
    , length targets /= 1
    ]
  renderCollision (name, targets) = name <> " -> {" <> Text.intercalate ", " targets <> "}"

-- | Every @substrate@ mention in an ML-describing Dhall file. An architecture
-- is substrate-independent — substrate selection belongs on the CLI/plan seam —
-- so this must stay empty. Callers supply the ML-describing file contents.
mlDslSubstrateMentions :: [(FilePath, Text)] -> [FilePath]
mlDslSubstrateMentions files =
  [path | (path, contents) <- files, "substrate" `Text.isInfixOf` Text.toLower contents]

-- ---------------------------------------------------------------------------
-- Dhall rendering (the round-trip side)
-- ---------------------------------------------------------------------------

-- | Render an operator as Dhall text, annotated with the reflected union type
-- so the result decodes standalone through 'layerOpDecoder'. The unit lane
-- asserts @decode . render == id@ over every operator witness, which is what
-- keeps the writer and the decoder from drifting apart.
renderLayerOp :: LayerOp -> Text
renderLayerOp op =
  "( " <> reflectedSchemaText layerOpDecoder <> " )." <> layerOpName op <> renderLayerOpPayload op

renderLayerOpPayload :: LayerOp -> Text
renderLayerOpPayload op =
  case op of
    DenseOp -> ""
    IdentityOp -> ""
    DropoutOp rate -> " " <> renderDouble rate
    ConvOp spec ->
      " "
        <> renderRecord
          [ ("convIn", renderNatural (convIn spec))
          , ("convOut", renderNatural (convOut spec))
          , ("convInputDims", renderNaturalList (convInputDims spec))
          , ("convKernelDims", renderNaturalList (convKernelDims spec))
          , ("convStride", renderNaturalList (convStride spec))
          , ("convPadding", renderNaturalList (convPadding spec))
          ]
    PoolOp shape poolSpec ->
      " "
        <> renderRecord
          [ ("shape", renderSpatialShape shape)
          , ("pool", renderPoolSpec poolSpec)
          ]
    NormOp spec -> " " <> renderNormSpec spec
    AttentionOp spec ->
      " "
        <> renderRecord
          [ ("attnSeqLen", renderNatural (attnSeqLen spec))
          , ("attnEmbedDim", renderNatural (attnEmbedDim spec))
          , ("attnNumHeads", renderNatural (attnNumHeads spec))
          , ("attnCausal", renderBool (attnCausal spec))
          ]
    GeGLUOp spec ->
      " "
        <> renderRecord
          [ ("ggIn", renderNatural (ggIn spec))
          , ("ggFf", renderNatural (ggFf spec))
          , ("ggOut", renderNatural (ggOut spec))
          ]
    PatchOp spec ->
      " "
        <> renderRecord
          [ ("peC", renderNatural (peC spec))
          , ("peH", renderNatural (peH spec))
          , ("peW", renderNatural (peW spec))
          , ("peP", renderNatural (peP spec))
          , ("peStride", renderNatural (peStride spec))
          , ("peD", renderNatural (peD spec))
          ]
    ResidualOp inner shortcut scale innerAct ->
      " "
        <> renderRecord
          [ ("inner", renderAffineSpec inner)
          , ("shortcut", renderShortcut shortcut)
          , ("scale", renderDouble scale)
          , ("innerActivation", renderActivation innerAct)
          ]
    BlockOp spec -> " " <> renderBlockSpec spec

renderSpatialShape :: SpatialShape -> Text
renderSpatialShape shape =
  renderRecord
    [ ("spC", renderNatural (spC shape))
    , ("spH", renderNatural (spH shape))
    , ("spW", renderNatural (spW shape))
    ]

renderPoolWindow :: PoolWindow -> Text
renderPoolWindow win =
  renderRecord
    [ ("pwKh", renderNatural (pwKh win))
    , ("pwKw", renderNatural (pwKw win))
    , ("pwSh", renderNatural (pwSh win))
    , ("pwSw", renderNatural (pwSw win))
    , ("pwPh", renderNatural (pwPh win))
    , ("pwPw", renderNatural (pwPw win))
    , ("pwCountPad", renderBool (pwCountPad win))
    ]

renderPoolSpec :: PoolSpec -> Text
renderPoolSpec spec =
  case spec of
    PoolMax win -> alternative "PoolMax" <> " " <> renderPoolWindow win
    PoolAvg win -> alternative "PoolAvg" <> " " <> renderPoolWindow win
    PoolGlobal -> alternative "PoolGlobal"
 where
  alternative name = "( " <> reflectedSchemaText poolSpecDecoder <> " )." <> name

renderNormFlavor :: NormFlavor -> Text
renderNormFlavor flavor =
  case flavor of
    NormBatch -> alternative "NormBatch"
    NormLayerWise -> alternative "NormLayerWise"
    NormGroup groups -> alternative "NormGroup" <> " " <> renderNatural groups
 where
  alternative name = "( " <> reflectedSchemaText normFlavorDecoder <> " )." <> name

renderNormSpec :: NormSpec -> Text
renderNormSpec spec =
  renderRecord
    [ ("nFlavor", renderNormFlavor (nFlavor spec))
    , ("nChannels", renderNatural (nChannels spec))
    , ("nSpatial", renderNatural (nSpatial spec))
    , ("nEps", renderDouble (nEps spec))
    ]

renderAffineSpec :: AffineSpec -> Text
renderAffineSpec spec =
  renderRecord
    [ ("asIn", renderNatural (asIn spec))
    , ("asOut", renderNatural (asOut spec))
    ]

renderShortcut :: Shortcut -> Text
renderShortcut shortcut =
  case shortcut of
    IdentityShortcut -> alternative "IdentityShortcut"
    ProjectionShortcut spec -> alternative "ProjectionShortcut" <> " " <> renderAffineSpec spec
 where
  alternative name = "( " <> reflectedSchemaText shortcutDecoder <> " )." <> name

renderBlockStage :: BlockStage -> Text
renderBlockStage stage =
  renderRecord
    [ ("bsAffine", renderAffineSpec (bsAffine stage))
    , ("bsNorm", renderOptionalNorm (bsNorm stage))
    , ("bsAct", renderActivation (bsAct stage))
    ]
 where
  renderOptionalNorm value =
    case value of
      Nothing -> "None " <> renderTypeParen normSpecDecoder
      Just spec -> "Some " <> renderNormSpec spec

renderBlockSpec :: BlockSpec -> Text
renderBlockSpec spec =
  renderRecord
    [ ("blStages", renderStages (blStages spec))
    , ("blShortcut", renderShortcut (blShortcut spec))
    , ("blScale", renderDouble (blScale spec))
    , ("blFinalAct", renderActivation (blFinalAct spec))
    ]
 where
  renderStages stages =
    case stages of
      [] -> "([] : List " <> reflectedSchemaText blockStageDecoder <> ")"
      _ -> "[ " <> Text.intercalate ", " (fmap renderBlockStage stages) <> " ]"

renderActivation :: LayerActivation -> Text
renderActivation activation =
  "( " <> reflectedSchemaText layerActivationDecoder <> " )." <> name
 where
  name =
    case activation of
      LinearActivation -> "LinearActivation"
      TanhActivation -> "TanhActivation"
      ReluActivation -> "ReluActivation"
      SoftmaxActivation -> "SoftmaxActivation"

renderMode :: LayerMode -> Text
renderMode mode =
  "( " <> reflectedSchemaText layerModeDecoder <> " )." <> name
 where
  name =
    case mode of
      TrainingMode -> "TrainingMode"
      InferenceMode -> "InferenceMode"

-- | Render a whole architecture description as Dhall text that decodes back
-- through 'layerGraphDescriptionDecoder'.
renderLayerGraphDescription :: LayerGraphDescription -> Text
renderLayerGraphDescription description =
  renderRecord
    [ ("name", renderTextLiteral (descGraphName description))
    , ("seed", renderNatural (descGraphSeed description))
    , ("inputShape", renderNaturalList (unTensorShape (descGraphInputShape description)))
    , ("outputShape", renderNaturalList (unTensorShape (descGraphOutputShape description)))
    , ("nodes", renderNodes (descGraphNodes description))
    ]
 where
  renderNodes nodes =
    case nodes of
      [] -> "([] : List " <> reflectedSchemaText layerNodeDescriptionDecoder <> ")"
      _ -> "[ " <> Text.intercalate "\n, " (fmap renderNode nodes) <> " ]"
  renderNode node =
    renderRecord
      [ ("name", renderTextLiteral (descNodeName node))
      , ("op", renderLayerOp (descNodeOp node))
      , ("inputShape", renderNaturalList (unTensorShape (descNodeInputShape node)))
      , ("outputShape", renderNaturalList (unTensorShape (descNodeOutputShape node)))
      , ("mode", renderMode (descNodeMode node))
      , ("activation", renderActivation (descNodeActivation node))
      ]

renderTypeParen :: Dhall.Decoder a -> Text
renderTypeParen decoder = "( " <> reflectedSchemaText decoder <> " )"

renderRecord :: [(Text, Text)] -> Text
renderRecord fields =
  "{ " <> Text.intercalate ", " [name <> " = " <> value | (name, value) <- fields] <> " }"

renderNaturalList :: [Int] -> Text
renderNaturalList values =
  case values of
    [] -> "([] : List Natural)"
    _ -> "[ " <> Text.intercalate ", " (fmap renderNatural values) <> " ]"

-- | Render a Dhall @Natural@ literal.
--
-- Sprint `229.1` audit — this used to clamp with @max 0@, so a negative seed
-- rendered as @0@, decoded back as @0@, and seeded @deterministicParameters@
-- with a different value: different weights, no error, no finding. The clamp is
-- gone. A negative renders as a negative literal, which is not a Dhall
-- @Natural@, so the round trip fails at decode instead of silently substituting
-- a different graph.
renderNatural :: Int -> Text
renderNatural value
  | value < 0 = Text.pack (show value)
  | otherwise = Text.pack (show (fromIntegral value :: Natural))

renderDouble :: Double -> Text
renderDouble value = Text.pack (show value)

renderBool :: Bool -> Text
renderBool value = if value then "True" else "False"

renderTextLiteral :: Text -> Text
renderTextLiteral value = "\"" <> Text.replace "\"" "\\\"" (Text.replace "\\" "\\\\" value) <> "\""

-- ---------------------------------------------------------------------------
-- Realising a description
-- ---------------------------------------------------------------------------

-- | Build one node from its described operator through the correctness-checked
-- smart constructor for that operator. Total over 'LayerOp': a new constructor
-- fails @-Werror=incomplete-patterns@ here, so no described operator can fall
-- through to a stand-in.
layerNodeFromOp
  :: Text
  -> LayerOp
  -> TensorShape
  -> TensorShape
  -> LayerActivation
  -> LayerMode
  -> LayerParameters
  -> Either Text LayerNode
layerNodeFromOp name op inputShape outputShape activation mode params =
  case op of
    DenseOp -> do
      inputWidth <- tensorShapeWidth inputShape
      outputWidth <- tensorShapeWidth outputShape
      mkAffineLayer name inputWidth outputWidth activation mode params
    IdentityOp -> do
      width <- tensorShapeWidth inputShape
      mkIdentityLayer name width mode
    DropoutOp rate -> do
      width <- tensorShapeWidth inputShape
      mkDropoutLayer name rate width mode
    ConvOp spec
      | length (convInputDims spec) == 3 -> mkConv3DLayer name spec activation mode params
      | otherwise -> mkConvLayer name spec activation mode params
    PoolOp shape poolSpec -> mkPoolLayer name shape poolSpec mode
    NormOp spec -> mkNormLayer name spec mode params
    AttentionOp spec -> mkAttentionLayer name spec mode params
    GeGLUOp spec -> mkGeGLULayer name spec mode params
    PatchOp spec -> mkPatchEmbedLayer name spec mode params
    ResidualOp inner shortcut scale innerAct ->
      mkResidualNode name inner shortcut scale innerAct activation mode params
    BlockOp spec
      | blockIsBottleneck spec -> mkBottleneck name spec mode params
      | otherwise -> mkBasicBlock name spec mode params

-- | Realise a described architecture. Every node is built through its smart
-- constructor, parameters come from the description's seed, and the result
-- __fails closed__ when a described shape disagrees with the geometry the
-- operator actually produces, when consecutive nodes do not chain, or when the
-- graph's own input/output shapes do not match its ends. A description can
-- therefore never name a graph that executes something else.
buildLayerGraph :: LayerGraphDescription -> Either Text LayerGraph
buildLayerGraph description = do
  case descGraphNodes description of
    [] -> Left (descGraphName description <> ": architecture must have at least one node")
    _ -> Right ()
  nodes <- traverse buildNode (zip [0 ..] (descGraphNodes description))
  checkChain (zip (descGraphNodes description) nodes)
  firstNode <- headOr "architecture has no first node" nodes
  lastNode <- headOr "architecture has no last node" (reverse nodes)
  requireShape
    "graph input"
    (descGraphInputShape description)
    (layerInputShape firstNode)
  requireShape
    "graph output"
    (descGraphOutputShape description)
    (layerOutputShape lastNode)
  pure
    LayerGraph
      { layerGraphName = descGraphName description
      , layerGraphInputShape = descGraphInputShape description
      , layerGraphOutputShape = descGraphOutputShape description
      , layerGraphNodes = nodes
      }
 where
  headOr message values =
    case values of
      (value : _) -> Right value
      [] -> Left (descGraphName description <> ": " <> message)
  buildNode (index, node) = do
    params <- nodeParameters index node
    built <-
      layerNodeFromOp
        (descNodeName node)
        (descNodeOp node)
        (descNodeInputShape node)
        (descNodeOutputShape node)
        (descNodeActivation node)
        (descNodeMode node)
        params
    requireShape
      (descNodeName node <> " input")
      (descNodeInputShape node)
      (layerInputShape built)
    requireShape
      (descNodeName node <> " output")
      (descNodeOutputShape node)
      (layerOutputShape built)
    pure built
  nodeParameters index node =
    case descNodeOp node of
      DenseOp -> do
        inputWidth <- tensorShapeWidth (descNodeInputShape node)
        outputWidth <- tensorShapeWidth (descNodeOutputShape node)
        pure (deterministicParameters (seedFor index) inputWidth outputWidth)
      op -> Right (deterministicOpParameters (seedFor index) op)
  seedFor index = descGraphSeed description + index
  requireShape label expectedShape actualShape =
    if expectedShape == actualShape
      then Right ()
      else
        Left
          ( descGraphName description
              <> ": "
              <> label
              <> " shape "
              <> Text.pack (show (unTensorShape expectedShape))
              <> " disagrees with the operator geometry "
              <> Text.pack (show (unTensorShape actualShape))
          )
  checkChain pairs =
    case pairs of
      ((_, previous) : rest@((describedNext, next) : _)) ->
        if layerOutputShape previous == layerInputShape next
          then checkChain rest
          else
            Left
              ( descGraphName description
                  <> ": "
                  <> descNodeName describedNext
                  <> " input shape "
                  <> Text.pack (show (unTensorShape (layerInputShape next)))
                  <> " does not chain from "
                  <> layerNodeName previous
                  <> " output shape "
                  <> Text.pack (show (unTensorShape (layerOutputShape previous)))
              )
      _ -> Right ()
