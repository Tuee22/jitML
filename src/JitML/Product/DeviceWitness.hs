{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE OverloadedStrings #-}

-- | The execution witness a device call leaves behind.
--
-- Before this module the product matrix composed its @DeviceEvidence@ cell from
-- a declared 'JitML.Substrate.Substrate' and a declared @DeviceClaim@ — a total
-- pure function that performed no execution, consulted no artifact, and could
-- not fail, so a row attested an engine that need never have run.
--
-- A 'DeviceExecutionWitness' is different in kind: it has no exported
-- constructor and no pure smart constructor. The only way to obtain one is
-- 'witnessDeviceExecution', which runs in 'IO', requires the compiled artifact
-- the engine actually produced to be present at the path the engine reports,
-- and records that artifact's SHA-256 alongside the identity the artifact
-- itself reports for the code that ran. A caller that never compiled and never
-- dispatched cannot produce the value, so an evidence cell derived from a
-- witness is a measurement rather than a declaration.
--
-- Values decoded from the wire come back through
-- 'refineRawDeviceExecutionWitness', which cannot re-open the artifact (the
-- journal outlives the JIT cache) but does hold the recorded digest and the
-- recorded identity to the same shape the mint enforces, so a hand-authored
-- journal row still fails closed.
module JitML.Product.DeviceWitness
  ( DeviceExecutionWitness
  , RawDeviceExecutionWitness (..)
  , deviceExecutionWitnessToRaw
  , refineRawDeviceExecutionWitness
  , renderDeviceExecutionWitness
  , witnessArtifactPath
  , witnessArtifactSha256
  , witnessBackend
  , witnessDeviceExecution
  , witnessExecutedIdentity
  , witnessKernelHash
  , witnessSubstrate
  )
where

import Codec.Serialise (Serialise)
import Control.Exception (IOException, try)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified as ByteString
import Data.Char (intToDigit, isHexDigit, toLower)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word8)
import GHC.Generics (Generic)
import System.Directory (doesFileExist)

import JitML.Substrate (Substrate, parseSubstrate, renderSubstrate)

-- | A hidden-constructor record of one successful device execution.
--
-- @witnessArtifactSha256@ is the digest of the bytes that were loaded, so the
-- witness names a specific compiled artifact rather than a substrate label.
data DeviceExecutionWitness = DeviceExecutionWitness
  { witnessSubstrateValue :: !Substrate
  , witnessBackendValue :: !Text
  , witnessKernelHashValue :: !Text
  , witnessArtifactPathValue :: !Text
  , witnessArtifactSha256Value :: !Text
  , witnessExecutedIdentityValue :: !Text
  }
  deriving stock (Eq, Ord, Show)

-- | Deliberately forgeable wire shape. Refinement is mandatory before a decoded
-- witness can reach an evidence renderer.
data RawDeviceExecutionWitness = RawDeviceExecutionWitness
  { rawWitnessSubstrate :: !Text
  , rawWitnessBackend :: !Text
  , rawWitnessKernelHash :: !Text
  , rawWitnessArtifactPath :: !Text
  , rawWitnessArtifactSha256 :: !Text
  , rawWitnessExecutedIdentity :: !Text
  }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (Serialise)

witnessSubstrate :: DeviceExecutionWitness -> Substrate
witnessSubstrate = witnessSubstrateValue

-- | The backend identity the loaded artifact reports for itself.
witnessBackend :: DeviceExecutionWitness -> Text
witnessBackend = witnessBackendValue

-- | The content-addressed JIT cache key the artifact was compiled under.
witnessKernelHash :: DeviceExecutionWitness -> Text
witnessKernelHash = witnessKernelHashValue

witnessArtifactPath :: DeviceExecutionWitness -> Text
witnessArtifactPath = witnessArtifactPathValue

-- | SHA-256 of the artifact bytes as they existed when the call succeeded.
witnessArtifactSha256 :: DeviceExecutionWitness -> Text
witnessArtifactSha256 = witnessArtifactSha256Value

-- | The identity of the code that ran, read back out of the artifact rather
-- than asserted by the host.
witnessExecutedIdentity :: DeviceExecutionWitness -> Text
witnessExecutedIdentity = witnessExecutedIdentityValue

-- | Mint a witness from a completed device call.
--
-- This is the only constructor. It fails closed when the artifact the engine
-- named is absent or unreadable, when the cache key is not a hex digest, or
-- when the backend / executed identity read back from the artifact is blank.
witnessDeviceExecution
  :: Substrate
  -> Text
  -- ^ backend identity reported by the loaded artifact
  -> Text
  -- ^ content-addressed JIT cache key
  -> FilePath
  -- ^ artifact path the engine loaded
  -> Text
  -- ^ executed identity read back out of the artifact
  -> IO (Either Text DeviceExecutionWitness)
witnessDeviceExecution substrate backend kernelHash artifactPath executedIdentity
  | Text.null (Text.strip backend) =
      pure (Left "device execution witness requires a backend identity")
  | not (isHexDigest kernelHash) =
      pure
        ( Left
            ( "device execution witness requires a hex cache key, saw "
                <> Text.pack (show kernelHash)
            )
        )
  | Text.null (Text.strip executedIdentity) =
      pure (Left "device execution witness requires an executed identity")
  | null artifactPath =
      pure (Left "device execution witness requires an artifact path")
  | otherwise = do
      present <- doesFileExist artifactPath
      if not present
        then
          pure
            ( Left
                ( "device execution witness names an absent artifact: "
                    <> Text.pack artifactPath
                )
            )
        else do
          readResult <- try (ByteString.readFile artifactPath)
          pure $
            case readResult :: Either IOException ByteString.ByteString of
              Left err ->
                Left
                  ( "device execution witness could not read "
                      <> Text.pack artifactPath
                      <> ": "
                      <> Text.pack (show err)
                  )
              Right bytes ->
                Right
                  DeviceExecutionWitness
                    { witnessSubstrateValue = substrate
                    , witnessBackendValue = Text.strip backend
                    , witnessKernelHashValue = Text.toLower kernelHash
                    , witnessArtifactPathValue = Text.pack artifactPath
                    , witnessArtifactSha256Value = hexBytes (SHA256.hash bytes)
                    , witnessExecutedIdentityValue = Text.strip executedIdentity
                    }

deviceExecutionWitnessToRaw :: DeviceExecutionWitness -> RawDeviceExecutionWitness
deviceExecutionWitnessToRaw witness =
  RawDeviceExecutionWitness
    { rawWitnessSubstrate = renderSubstrate (witnessSubstrateValue witness)
    , rawWitnessBackend = witnessBackendValue witness
    , rawWitnessKernelHash = witnessKernelHashValue witness
    , rawWitnessArtifactPath = witnessArtifactPathValue witness
    , rawWitnessArtifactSha256 = witnessArtifactSha256Value witness
    , rawWitnessExecutedIdentity = witnessExecutedIdentityValue witness
    }

-- | Refine a decoded witness. The artifact is deliberately /not/ re-opened: a
-- journal is read long after the content-addressed JIT cache is pruned. What is
-- re-checked is every property the mint enforced that survives serialization.
refineRawDeviceExecutionWitness
  :: RawDeviceExecutionWitness -> Either Text DeviceExecutionWitness
refineRawDeviceExecutionWitness raw = do
  substrate <-
    maybe
      ( Left
          ( "device execution witness names an unknown substrate: "
              <> rawWitnessSubstrate raw
          )
      )
      Right
      (parseSubstrate (rawWitnessSubstrate raw))
  ensureNonBlank "backend identity" (rawWitnessBackend raw)
  ensureNonBlank "artifact path" (rawWitnessArtifactPath raw)
  ensureNonBlank "executed identity" (rawWitnessExecutedIdentity raw)
  ensureHexDigest "cache key" (rawWitnessKernelHash raw)
  ensureArtifactDigest (rawWitnessArtifactSha256 raw)
  pure
    DeviceExecutionWitness
      { witnessSubstrateValue = substrate
      , witnessBackendValue = Text.strip (rawWitnessBackend raw)
      , witnessKernelHashValue = Text.toLower (rawWitnessKernelHash raw)
      , witnessArtifactPathValue = Text.strip (rawWitnessArtifactPath raw)
      , witnessArtifactSha256Value = Text.toLower (rawWitnessArtifactSha256 raw)
      , witnessExecutedIdentityValue = Text.strip (rawWitnessExecutedIdentity raw)
      }
 where
  ensureNonBlank label value
    | Text.null (Text.strip value) =
        Left ("device execution witness requires a " <> label)
    | otherwise = Right ()
  ensureHexDigest label value
    | isHexDigest value = Right ()
    | otherwise =
        Left
          ( "device execution witness requires a hex "
              <> label
              <> ", saw "
              <> Text.pack (show value)
          )
  ensureArtifactDigest value
    | Text.length value == 64 && isHexDigest value = Right ()
    | otherwise =
        Left
          ( "device execution witness requires a sha256 artifact digest, saw "
              <> Text.pack (show value)
          )

-- | The measured device-evidence cell.
--
-- Every component is read off the witness: the lane the artifact was compiled
-- for, the backend the artifact reports, the identity of the code that ran, and
-- the digest of the bytes that ran. Nothing here is derivable from a declared
-- row.
renderDeviceExecutionWitness :: DeviceExecutionWitness -> Text
renderDeviceExecutionWitness witness =
  Text.intercalate
    ":"
    [ "device"
    , renderSubstrate (witnessSubstrateValue witness)
    , witnessBackendValue witness
    , witnessExecutedIdentityValue witness
    , Text.take 16 (witnessArtifactSha256Value witness)
    ]

isHexDigest :: Text -> Bool
isHexDigest value =
  not (Text.null value) && Text.all isHexDigit value

hexBytes :: ByteString.ByteString -> Text
hexBytes =
  Text.pack . concatMap hexOctet . ByteString.unpack
 where
  hexOctet :: Word8 -> String
  hexOctet byte =
    [ toLower (intToDigit (fromIntegral byte `div` 16))
    , toLower (intToDigit (fromIntegral byte `mod` 16))
    ]
