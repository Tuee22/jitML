{-# LANGUAGE OverloadedStrings #-}

-- | Ordinary portable transport and separate actual FILE copy/audit APIs.
-- No decoded DATA creates an original execution, Store or authentication cap.
module JitML.Test.NativeLaneBundle
  ( module Data
  , module Write
  , module Read
  , nativeBundleReferenceObjectKey
  ) where

import Data.Text (Text)
import JitML.Checkpoint.NativePhase.Types (CodecError)
import JitML.Test.NativeLaneBundle.Data as Data
import JitML.Test.NativeLaneBundle.Read as Read
import JitML.Test.NativeLaneBundle.Write as Write

nativeBundleReferenceObjectKey :: NativeBundleReferenceData -> Either CodecError Text
nativeBundleReferenceObjectKey reference = do
  _ <- renderNativeBundleReferenceData reference
  pure
    ("jitml-checkpoints/native-lane-bundles-v1/" <> nativeBundleReferenceSha256 reference <> ".cbor")
