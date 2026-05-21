{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.Workload
  ( WorkloadEffect (..)
  , WorkloadEffectResult (..)
  , dispatchWorkloadPayload
  , parseWorkloadEffectPayload
  , renderWorkloadEffect
  , renderWorkloadEffectPayload
  , renderWorkloadEffectResult
  , runWorkloadEffect
  , runWorkloadEffects
  )
where

import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.Char (digitToInt, intToDigit, isHexDigit)
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Service.Capabilities
  ( BucketName (..)
  , ETag (..)
  , HasHarbor (..)
  , HasKubectl (..)
  , HasMinIO (..)
  , ImageRef (..)
  , KubeResource (..)
  , ObjectKey (..)
  , ObjectRef (..)
  )
import JitML.Service.Retry (ServiceError)

data WorkloadEffect
  = WriteCheckpointBlob ObjectRef ByteString
  | UpdateCheckpointPointer ObjectRef (Maybe ETag) Text
  | PromoteWorkloadImage ImageRef ImageRef
  | ApplyWorkloadResource KubeResource Text
  | ReadWorkloadResourceStatus KubeResource
  | DeleteWorkloadResource KubeResource
  deriving stock (Eq, Show)

data WorkloadEffectResult
  = CheckpointBlobWritten ETag
  | CheckpointPointerUpdated ETag
  | WorkloadImagePromoted ImageRef
  | WorkloadResourceApplied
  | WorkloadResourceStatus Text
  | WorkloadResourceDeleted
  deriving stock (Eq, Show)

runWorkloadEffect
  :: (HasHarbor m, HasKubectl m, HasMinIO m)
  => WorkloadEffect
  -> m (Either ServiceError WorkloadEffectResult)
runWorkloadEffect effect =
  case effect of
    WriteCheckpointBlob ref payload ->
      fmap CheckpointBlobWritten <$> putBlobBytesIfAbsent ref payload
    UpdateCheckpointPointer ref expected payload ->
      fmap CheckpointPointerUpdated <$> casPointer ref expected payload
    PromoteWorkloadImage source target ->
      fmap WorkloadImagePromoted <$> harborPromoteImage source target
    ApplyWorkloadResource resource manifest ->
      fmap (const WorkloadResourceApplied) <$> kubectlApply resource manifest
    ReadWorkloadResourceStatus resource ->
      fmap WorkloadResourceStatus <$> kubectlStatus resource
    DeleteWorkloadResource resource ->
      fmap (const WorkloadResourceDeleted) <$> kubectlDelete resource

runWorkloadEffects
  :: (HasHarbor m, HasKubectl m, HasMinIO m)
  => [WorkloadEffect]
  -> m [Either ServiceError WorkloadEffectResult]
runWorkloadEffects =
  traverse runWorkloadEffect

dispatchWorkloadPayload
  :: (HasHarbor m, HasKubectl m, HasMinIO m)
  => Text
  -> m (Maybe (Either ServiceError WorkloadEffectResult))
dispatchWorkloadPayload payload =
  case parseWorkloadEffectPayload payload of
    Nothing -> pure Nothing
    Just effect -> Just <$> runWorkloadEffect effect

renderWorkloadEffectPayload :: WorkloadEffect -> Text
renderWorkloadEffectPayload effect =
  Text.unlines $
    [ "kind: WorkloadEffect"
    , "effect: " <> workloadEffectTag effect
    ]
      <> workloadEffectFields effect

parseWorkloadEffectPayload :: Text -> Maybe WorkloadEffect
parseWorkloadEffectPayload payload = do
  let fields = mapMaybe parseField (Text.lines payload)
      value key = lookup key fields
  "WorkloadEffect" <- value "kind"
  effectTag <- value "effect"
  case effectTag of
    "WriteCheckpointBlob" -> do
      ref <- objectRefFromFields value
      payloadBytes <- value "payload-hex" >>= hexDecodeText
      pure (WriteCheckpointBlob ref payloadBytes)
    "UpdateCheckpointPointer" -> do
      ref <- objectRefFromFields value
      pointerPayload <- value "payload"
      let expected = ETag <$> value "expected-etag"
      pure (UpdateCheckpointPointer ref expected pointerPayload)
    "PromoteWorkloadImage" -> do
      source <- ImageRef <$> value "source-image"
      target <- ImageRef <$> value "target-image"
      pure (PromoteWorkloadImage source target)
    "ApplyWorkloadResource" -> do
      resource <- KubeResource <$> value "resource"
      manifest <- value "manifest"
      pure (ApplyWorkloadResource resource (Text.replace "\\n" "\n" manifest))
    "ReadWorkloadResourceStatus" -> do
      resource <- KubeResource <$> value "resource"
      pure (ReadWorkloadResourceStatus resource)
    "DeleteWorkloadResource" -> do
      resource <- KubeResource <$> value "resource"
      pure (DeleteWorkloadResource resource)
    _ -> Nothing

renderWorkloadEffect :: WorkloadEffect -> Text
renderWorkloadEffect effect =
  case effect of
    WriteCheckpointBlob ref _ ->
      "minio:write-checkpoint-blob " <> renderObjectRef ref
    UpdateCheckpointPointer ref expected _ ->
      "minio:update-checkpoint-pointer "
        <> renderObjectRef ref
        <> " expected="
        <> maybe "(none)" unETag expected
    PromoteWorkloadImage source target ->
      "harbor:promote-image " <> unImageRef source <> " -> " <> unImageRef target
    ApplyWorkloadResource resource _ ->
      "kubectl:apply " <> unKubeResource resource
    ReadWorkloadResourceStatus resource ->
      "kubectl:status " <> unKubeResource resource
    DeleteWorkloadResource resource ->
      "kubectl:delete " <> unKubeResource resource

renderWorkloadEffectResult :: WorkloadEffectResult -> Text
renderWorkloadEffectResult result =
  case result of
    CheckpointBlobWritten etag ->
      "checkpoint-blob-written " <> unETag etag
    CheckpointPointerUpdated etag ->
      "checkpoint-pointer-updated " <> unETag etag
    WorkloadImagePromoted image ->
      "workload-image-promoted " <> unImageRef image
    WorkloadResourceApplied ->
      "workload-resource-applied"
    WorkloadResourceStatus status ->
      "workload-resource-status " <> Text.replace "\n" " " status
    WorkloadResourceDeleted ->
      "workload-resource-deleted"

renderObjectRef :: ObjectRef -> Text
renderObjectRef ref =
  let BucketName bucket = objectBucket ref
      ObjectKey key = objectKey ref
   in bucket <> "/" <> key

workloadEffectTag :: WorkloadEffect -> Text
workloadEffectTag effect =
  case effect of
    WriteCheckpointBlob _ _ -> "WriteCheckpointBlob"
    UpdateCheckpointPointer {} -> "UpdateCheckpointPointer"
    PromoteWorkloadImage _ _ -> "PromoteWorkloadImage"
    ApplyWorkloadResource _ _ -> "ApplyWorkloadResource"
    ReadWorkloadResourceStatus _ -> "ReadWorkloadResourceStatus"
    DeleteWorkloadResource _ -> "DeleteWorkloadResource"

workloadEffectFields :: WorkloadEffect -> [Text]
workloadEffectFields effect =
  case effect of
    WriteCheckpointBlob ref payload ->
      objectRefFields ref
        <> ["payload-hex: " <> hexEncodeText payload]
    UpdateCheckpointPointer ref expected payload ->
      objectRefFields ref
        <> maybe [] (\etag -> ["expected-etag: " <> unETag etag]) expected
        <> ["payload: " <> payload]
    PromoteWorkloadImage source target ->
      [ "source-image: " <> unImageRef source
      , "target-image: " <> unImageRef target
      ]
    ApplyWorkloadResource resource manifest ->
      [ "resource: " <> unKubeResource resource
      , "manifest: " <> Text.replace "\n" "\\n" manifest
      ]
    ReadWorkloadResourceStatus resource ->
      ["resource: " <> unKubeResource resource]
    DeleteWorkloadResource resource ->
      ["resource: " <> unKubeResource resource]

objectRefFields :: ObjectRef -> [Text]
objectRefFields ref =
  let BucketName bucket = objectBucket ref
      ObjectKey key = objectKey ref
   in [ "bucket: " <> bucket
      , "key: " <> key
      ]

objectRefFromFields :: (Text -> Maybe Text) -> Maybe ObjectRef
objectRefFromFields value = do
  bucket <- BucketName <$> value "bucket"
  key <- ObjectKey <$> value "key"
  pure (ObjectRef bucket key)

parseField :: Text -> Maybe (Text, Text)
parseField line =
  let (key, rest) = Text.breakOn ":" line
   in if Text.null rest
        then Nothing
        else Just (Text.strip key, Text.strip (Text.drop 1 rest))

hexEncodeText :: ByteString -> Text
hexEncodeText =
  Text.pack . concatMap byteToHex . ByteString.unpack
 where
  byteToHex byte =
    [ intToDigit (fromIntegral (byte `div` 16))
    , intToDigit (fromIntegral (byte `mod` 16))
    ]

hexDecodeText :: Text -> Maybe ByteString
hexDecodeText value =
  ByteString.pack <$> go (Text.unpack value)
 where
  go [] = Just []
  go [_] = Nothing
  go (hi : lo : rest)
    | isHexDigit hi && isHexDigit lo = do
        bytes <- go rest
        pure (fromIntegral (digitToInt hi * 16 + digitToInt lo) : bytes)
    | otherwise = Nothing
