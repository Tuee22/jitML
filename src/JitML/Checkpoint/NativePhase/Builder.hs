{-# LANGUAGE OverloadedStrings #-}

-- | Checked canonical DATA construction shared by actual projection adapters.
-- Tensors/pages are interned by bytes. No execution, origin or ACK is minted.
module JitML.Checkpoint.NativePhase.Builder
  ( internTensor
  , internSequence
  ) where

import Control.Monad (foldM, unless)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS

import JitML.Checkpoint.NativePhase.Graph
import JitML.Checkpoint.NativePhase.Schema
import JitML.Checkpoint.NativePhase.SchemaTable
import JitML.Checkpoint.NativePhase.Types

-- Exact big-endian IEEE754 bit bytes. Empty is one empty leaf. The builder
-- never interprets, normalizes or rounds a Double, including signedzero/NaN.
internTensor :: ByteString -> NodePool -> Either CodecError (Digest, NodePool)
internTensor bytes pool = do
  let totalBytes = BS.length bytes
      count = totalBytes `div` 8
  unless (totalBytes `mod` 8 == 0) (Left (Malformed "tensor input has partial F64 coordinate"))
  checkLimit WholePayloadBytes (toInteger totalBytes)
  checkLimit AggregateF64Coordinates (toInteger count)
  if toInteger totalBytes <= nativePhaseLimit TensorChunkBytes
    then mkNodeData NTensorLeaf [VWord (fromIntegral count), VBytes bytes] >>= (`internNode` pool)
    else do
      let parts = byteChunks (fromInteger (nativePhaseLimit TensorChunkBytes)) bytes
      _ <- boundedLength SequenceFanout (nativePhaseLimit SequenceFanout) parts
      (references, after) <- foldM addChunk ([], pool) (zip [0 :: Int ..] parts)
      node <-
        mkNodeData
          NTensorManifest
          [VWord (fromIntegral count), VWord (fromIntegral totalBytes), VList (reverse references)]
      internNode node after
 where
  addChunk (references, current) (ordinal, chunk) = do
    node <- mkNodeData NTensorChunk [VWord (fromIntegral ordinal), VBytes chunk]
    (digest, after) <- internNode node current
    pure (VRef digest : references, after)

byteChunks :: Int -> ByteString -> [ByteString]
byteChunks size bytes
  | BS.null bytes = []
  | otherwise = let (first, rest) = BS.splitAt size bytes in first : byteChunks size rest

internSequence :: ElementKind -> [NodeValue] -> NodePool -> Either CodecError (Digest, NodePool)
internSequence kind values pool = do
  _ <- readElementKind (elementKindValue kind)
  count <- boundedLength PerSequenceElements (nativePhaseLimit PerSequenceElements) values
  let elementType = case kind of
        ScalarElement scalar -> scalarType scalar
        RefElement target -> TReference (NodeTargets [target])
        AliasElement target -> TReference (NodeTargets (aliasKinds target))
  mapM_ (validateValue elementType) values
  (pagesReversed, afterPages) <- foldM addPage ([], pool) (listChunks 256 values)
  let pages = reverse pagesReversed
  (height, children, afterChildren) <-
    if count == 0
      then Right (0, [], afterPages)
      else
        if length pages <= 256
          then Right (1, fmap (VRef . fst) pages, afterPages)
          else do
            (indices, after) <- foldM addIndex ([], afterPages) (listChunks 256 pages)
            pure (2, reverse indices, after)
  root <-
    mkNodeData
      NSequenceManifest
      [elementKindValue kind, VWord (fromIntegral count), VWord height, VList children]
  internNode root afterChildren
 where
  addPage (pages, current) page = do
    let pageKind = case kind of ScalarElement _ -> NScalarPage; _ -> NReferencePage
        count = length page
    node <- mkNodeData pageKind [elementKindValue kind, VWord (fromIntegral count), VList page]
    (digest, after) <- internNode node current
    pure ((digest, count) : pages, after)
  addIndex (indices, current) pages = do
    let count = sum (fmap snd pages)
    node <-
      mkNodeData
        NSequenceIndex
        [elementKindValue kind, VWord 1, VWord (fromIntegral count), VList (fmap (VRef . fst) pages)]
    (digest, after) <- internNode node current
    pure (VRef digest : indices, after)

listChunks :: Int -> [a] -> [[a]]
listChunks _ [] = []
listChunks size values = let (first, rest) = splitAt size values in first : listChunks size rest
