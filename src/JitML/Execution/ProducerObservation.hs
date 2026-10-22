{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Actual process and executable FILE observations. These are neither loaded
-- image/build coherence nor source authentication, ARS origin or libm proof.
module JitML.Execution.ProducerObservation
  ( SourceObservationMode (..)
  , ObservedProducerProcess
  , ProducerObservationError (..)
  , ProducerObservationField (..)
  , RecordedProducerObservation (..)
  , observeProducerProcess
  , recordedProducerObservation
  , compareProducerProcessObservations
  , compareRecordedProducerObservationData
  , producerExecutableFilePath
  , producerExecutableFileSha256
  , producerExecutableFileByteCount
  , producerProcessId
  , producerParentProcessId
  , producerKernelOperatingSystem
  , producerKernelMachine
  , producerKernelRelease
  , producerBuildOperatingSystem
  , producerBuildArchitecture
  , producerBuildCompiler
  , producerBuildCompilerVersion
  , producerObservedSource
  ) where

import Control.Exception (IOException, try)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified as BS
import Data.Char (intToDigit)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Version (showVersion)
import Data.Word (Word64)
import System.Environment (getExecutablePath)
import System.IO (IOMode (ReadMode), withBinaryFile)
import System.Info qualified as Info
import System.Posix.Process (getParentProcessID, getProcessID)
import System.Posix.Unistd qualified as Posix

import JitML.Product.SourceDigest qualified as Source

-- No caller-provided source SHA is accepted. A path is an observation request,
-- not evidence that the observed tree built the executable.
data SourceObservationMode
  = NoSourceObservation
  | ObserveSourceAt !FilePath
  deriving stock (Eq, Show)

data ProducerObservationField
  = ExecutableFilePath
  | ExecutableFileSha256
  | ExecutableFileByteCount
  | ProcessId
  | ParentProcessId
  | KernelOperatingSystem
  | KernelMachine
  | KernelRelease
  | BuildOperatingSystem
  | BuildArchitecture
  | BuildCompiler
  | BuildCompilerVersion
  | SourceObservation
  deriving stock (Eq, Ord, Show)

data ProducerObservationError
  = ProducerObservationIOFailure !IOException
  | ProducerSourceObservationFailure !FilePath !Text
  | ProducerObservationMismatch ![ProducerObservationField]
  deriving stock (Eq, Show)

-- | Public, deliberately forgeable comparison data. Its constructor and pure
-- comparator cannot construct 'ObservedProducerProcess'. No parser or data
-- refinement converts this record to an actual observation.
data RecordedProducerObservation = RecordedProducerObservation
  { recordedExecutableFilePath :: !FilePath
  , recordedExecutableFileSha256 :: !Text
  , recordedExecutableFileByteCount :: !Word64
  , recordedProcessId :: !Integer
  , recordedParentProcessId :: !Integer
  , recordedKernelOperatingSystem :: !Text
  , recordedKernelMachine :: !Text
  , recordedKernelRelease :: !Text
  , recordedBuildOperatingSystem :: !Text
  , recordedBuildArchitecture :: !Text
  , recordedBuildCompiler :: !Text
  , recordedBuildCompilerVersion :: !Text
  , recordedObservedSource :: !(Maybe (FilePath, Source.SourceStamp))
  }
  deriving stock (Eq, Show)

-- Constructor/field labels/Generic/Read/codecs are deliberately unavailable.
-- Actual IO below is the sole construction route; raw comparison data is not.
-- Keep the strict data capsule and its existing pattern/WHNF boundary.
{- HLINT ignore ObservedProducerProcess "Use newtype instead of data" -}
data ObservedProducerProcess = ObservedProducerProcess !RecordedProducerObservation

recordedProducerObservation :: ObservedProducerProcess -> RecordedProducerObservation
recordedProducerObservation (ObservedProducerProcess value) = value

producerExecutableFilePath :: ObservedProducerProcess -> FilePath
producerExecutableFilePath = recordedExecutableFilePath . recordedProducerObservation

producerExecutableFileSha256 :: ObservedProducerProcess -> Text
producerExecutableFileSha256 = recordedExecutableFileSha256 . recordedProducerObservation

producerExecutableFileByteCount :: ObservedProducerProcess -> Word64
producerExecutableFileByteCount = recordedExecutableFileByteCount . recordedProducerObservation

producerProcessId, producerParentProcessId :: ObservedProducerProcess -> Integer
producerProcessId = recordedProcessId . recordedProducerObservation
producerParentProcessId = recordedParentProcessId . recordedProducerObservation

producerKernelOperatingSystem
  , producerKernelMachine
  , producerKernelRelease
  , producerBuildOperatingSystem
  , producerBuildArchitecture
  , producerBuildCompiler
  , producerBuildCompilerVersion
    :: ObservedProducerProcess -> Text
producerKernelOperatingSystem = recordedKernelOperatingSystem . recordedProducerObservation
producerKernelMachine = recordedKernelMachine . recordedProducerObservation
producerKernelRelease = recordedKernelRelease . recordedProducerObservation
producerBuildOperatingSystem = recordedBuildOperatingSystem . recordedProducerObservation
producerBuildArchitecture = recordedBuildArchitecture . recordedProducerObservation
producerBuildCompiler = recordedBuildCompiler . recordedProducerObservation
producerBuildCompilerVersion = recordedBuildCompilerVersion . recordedProducerObservation

producerObservedSource :: ObservedProducerProcess -> Maybe (FilePath, Source.SourceStamp)
producerObservedSource = recordedObservedSource . recordedProducerObservation

observeProducerProcess
  :: SourceObservationMode -> IO (Either ProducerObservationError ObservedProducerProcess)
observeProducerProcess mode = do
  attempted <- tryIO observe
  pure $ case attempted of
    Left failure -> Left (ProducerObservationIOFailure failure)
    Right value -> value
 where
  observe = do
    executable <- getExecutablePath
    (executableSha, byteCount) <- observeExecutableFile executable
    pid <- getProcessID
    ppid <- getParentProcessID
    kernel <- Posix.getSystemID
    source <- case mode of
      NoSourceObservation -> pure (Right Nothing)
      ObserveSourceAt root -> do
        stamp <- Source.computeSourceStampIn root
        pure $ case stamp of
          Left detail -> Left (ProducerSourceObservationFailure root detail)
          Right actual -> Right (Just (root, actual))
    pure $ do
      actualSource <- source
      Right
        ( ObservedProducerProcess
            RecordedProducerObservation
              { recordedExecutableFilePath = executable
              , recordedExecutableFileSha256 = executableSha
              , recordedExecutableFileByteCount = byteCount
              , recordedProcessId = toInteger pid
              , recordedParentProcessId = toInteger ppid
              , recordedKernelOperatingSystem = Text.pack (Posix.systemName kernel)
              , recordedKernelMachine = Text.pack (Posix.machine kernel)
              , recordedKernelRelease = Text.pack (Posix.release kernel)
              , recordedBuildOperatingSystem = Text.pack Info.os
              , recordedBuildArchitecture = Text.pack Info.arch
              , recordedBuildCompiler = Text.pack Info.compilerName
              , recordedBuildCompilerVersion = Text.pack (showVersion Info.compilerVersion)
              , recordedObservedSource = actualSource
              }
        )

-- Fixed chunks bound auxiliary executable-read memory. The byte count is from
-- the actual stream, not a separate stat or caller-provided file size. A file
-- may change while read: no atomic/loaded-image snapshot claim is made here.
observeExecutableFile :: FilePath -> IO (Text, Word64)
observeExecutableFile path = withBinaryFile path ReadMode (loop SHA256.init 0)
 where
  loop !context !count handle = do
    chunk <- BS.hGetSome handle 65536
    if BS.null chunk
      then pure (hex (SHA256.finalize context), fromInteger count)
      else do
        let nextCount = count + toInteger (BS.length chunk)
        if nextCount > toInteger (maxBound :: Word64)
          then ioError (userError "producer executable file byte count exceeds Word64")
          else loop (SHA256.update context chunk) nextCount handle

hex :: BS.ByteString -> Text
hex = Text.pack . concatMap byteHex . BS.unpack
 where
  byteHex byte =
    [ intToDigit (fromIntegral byte `div` 16)
    , intToDigit (fromIntegral byte `mod` 16)
    ]

-- Catch synchronous IO failures only. AsyncException (including cancellation)
-- is deliberately not caught or converted into a successful/failed record.
tryIO :: IO value -> IO (Either IOException value)
tryIO = try

compareProducerProcessObservations
  :: ObservedProducerProcess
  -> ObservedProducerProcess
  -> Either ProducerObservationError ()
compareProducerProcessObservations left right =
  compareRecordedProducerObservationData
    (recordedProducerObservation left)
    (recordedProducerObservation right)

-- | Equality of supplied data only. Even Right () for two identical invented
-- records grants no observation, producer origin, physical admission or auth.
compareRecordedProducerObservationData
  :: RecordedProducerObservation
  -> RecordedProducerObservation
  -> Either ProducerObservationError ()
compareRecordedProducerObservationData left right =
  case [field | (field, equal) <- comparisons, not equal] of
    [] -> Right ()
    mismatches -> Left (ProducerObservationMismatch mismatches)
 where
  comparisons =
    [ (ExecutableFilePath, recordedExecutableFilePath left == recordedExecutableFilePath right)
    , (ExecutableFileSha256, recordedExecutableFileSha256 left == recordedExecutableFileSha256 right)
    ,
      ( ExecutableFileByteCount
      , recordedExecutableFileByteCount left == recordedExecutableFileByteCount right
      )
    , (ProcessId, recordedProcessId left == recordedProcessId right)
    , (ParentProcessId, recordedParentProcessId left == recordedParentProcessId right)
    , (KernelOperatingSystem, recordedKernelOperatingSystem left == recordedKernelOperatingSystem right)
    , (KernelMachine, recordedKernelMachine left == recordedKernelMachine right)
    , (KernelRelease, recordedKernelRelease left == recordedKernelRelease right)
    , (BuildOperatingSystem, recordedBuildOperatingSystem left == recordedBuildOperatingSystem right)
    , (BuildArchitecture, recordedBuildArchitecture left == recordedBuildArchitecture right)
    , (BuildCompiler, recordedBuildCompiler left == recordedBuildCompiler right)
    , (BuildCompilerVersion, recordedBuildCompilerVersion left == recordedBuildCompilerVersion right)
    , (SourceObservation, recordedObservedSource left == recordedObservedSource right)
    ]
