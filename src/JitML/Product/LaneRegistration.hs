{-# LANGUAGE OverloadedStrings #-}

-- | Actual fixed-path observation of separately governed expected pins. This
-- opaque value records FILE reads, not a review or admitted lane capability.
module JitML.Product.LaneRegistration
  ( LoadedLaneRegistration
  , LaneRegistrationError (..)
  , loadLaneRegistration
  , loadLaneRegistrationIn
  , loadedLaneGeneration
  , loadedLaneSelectionFile
  , loadedLaneGenerationFile
  , readSelectedLaneFileIn
  )
where

import Control.Exception (IOException, try)
import Control.Monad (unless)
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.Either.Combinators (mapLeft)
import Data.Text (Text)
import Data.Text qualified as Text
import System.Directory (makeAbsolute)
import System.FilePath (splitDirectories, (</>))
import System.IO (IOMode (ReadMode), withBinaryFile)
import System.IO.Error (isDoesNotExistError)
import System.Posix.Files (getSymbolicLinkStatus, isDirectory, isRegularFile, isSymbolicLink)

import JitML.Product.LaneRegistrationData
import JitML.Product.ValidationRecord (sha256Hex)
import JitML.Substrate (Substrate)

data LoadedLaneRegistration = LoadedLaneRegistration
  { loadedGenerationValue :: !LaneGenerationData
  , loadedSelectionFileValue :: !SelectedLaneFileData
  , loadedGenerationFileValue :: !SelectedLaneFileData
  }
  deriving stock (Eq, Show)

loadedLaneGeneration :: LoadedLaneRegistration -> LaneGenerationData
loadedLaneGeneration = loadedGenerationValue

loadedLaneSelectionFile :: LoadedLaneRegistration -> SelectedLaneFileData
loadedLaneSelectionFile = loadedSelectionFileValue

loadedLaneGenerationFile :: LoadedLaneRegistration -> SelectedLaneFileData
loadedLaneGenerationFile = loadedGenerationFileValue

data LaneRegistrationError
  = LaneRegistrationMissing !FilePath
  | LaneRegistrationReadFailure !FilePath !Text
  | LaneRegistrationRejected !FilePath !LaneRegistrationDataError
  | LaneRegistrationFileMismatch !FilePath !Text !Text !Integer !Integer
  | LaneRegistrationLaneMismatch !Substrate !Substrate
  deriving stock (Eq, Show)

loadLaneRegistration :: Substrate -> IO (Either LaneRegistrationError LoadedLaneRegistration)
loadLaneRegistration = loadLaneRegistrationIn "."

loadLaneRegistrationIn
  :: FilePath -> Substrate -> IO (Either LaneRegistrationError LoadedLaneRegistration)
loadLaneRegistrationIn root lane = do
  let relative = laneRegistrationPath lane
  selection <- readBounded root relative maximumLaneRegistrationBytes
  case selection of
    Left err -> pure (Left err)
    Right bytes ->
      case decodeLaneRegistrationData bytes of
        Left err -> pure (Left (LaneRegistrationRejected relative err))
        Right registration
          | laneRegistrationSubstrate registration /= lane ->
              pure (Left (LaneRegistrationLaneMismatch lane (laneRegistrationSubstrate registration)))
          | otherwise -> case reverse (laneRegistrationEntries registration) of
              [] ->
                pure
                  (Left (LaneRegistrationRejected relative (LaneRegistrationDataError "empty selection history")))
              selected : _ -> do
                let expected = laneRegistrationGeneration selected
                actual <- readSelectedLaneFileIn root maximumLaneGenerationBytes expected
                pure $ do
                  generationBytes <- actual
                  generation <-
                    mapLeft
                      (LaneRegistrationRejected (Text.unpack (selectedLaneFilePath expected)))
                      (decodeLaneGenerationData generationBytes)
                  unless (laneGenerationSubstrate generation == lane) $
                    Left (LaneRegistrationLaneMismatch lane (laneGenerationSubstrate generation))
                  pure
                    ( LoadedLaneRegistration
                        generation
                        (SelectedLaneFileData (Text.pack relative) (sha256Hex bytes) (fromIntegral (ByteString.length bytes)))
                        expected
                    )

-- | Read using an independently selected expected count/SHA. The computed
-- digest is compared with that pin; it never becomes a new expected identity.
-- This function returns bytes only and cannot construct LoadedLaneRegistration.
readSelectedLaneFileIn
  :: FilePath
  -> Integer
  -> SelectedLaneFileData
  -> IO (Either LaneRegistrationError ByteString)
readSelectedLaneFileIn root cap selected
  | count <= 0 || count > cap || cap > maximumRegisteredJournalBytes =
      pure
        ( Left
            (LaneRegistrationRejected relative (LaneRegistrationDataError "selected FILE count/cap invalid"))
        )
  | otherwise = do
      actual <- readBounded root relative count
      pure $ do
        bytes <- actual
        let actualSha = sha256Hex bytes
            actualCount = toInteger (ByteString.length bytes)
        unless (actualCount == count && actualSha == selectedLaneFileSha256 selected) $
          Left
            (LaneRegistrationFileMismatch relative (selectedLaneFileSha256 selected) actualSha count actualCount)
        pure bytes
 where
  count = toInteger (selectedLaneFileBytes selected)
  relative = Text.unpack (selectedLaneFilePath selected)

readBounded :: FilePath -> FilePath -> Integer -> IO (Either LaneRegistrationError ByteString)
readBounded root relative cap = do
  captured <- try (readChecked root relative cap) :: IO (Either IOException ByteString)
  pure $ case captured of
    Left err
      | isDoesNotExistError err -> Left (LaneRegistrationMissing relative)
      | otherwise -> Left (LaneRegistrationReadFailure relative (Text.pack (show err)))
    Right bytes -> Right bytes

readChecked :: FilePath -> FilePath -> Integer -> IO ByteString
readChecked root relative cap = do
  unless (cap > 0 && cap <= maximumRegisteredJournalBytes) $
    ioError (userError "registration FILE cap is invalid")
  unless (safeRelative relative) $
    ioError (userError "registration FILE path is not a governed relative path")
  let path = root </> relative
  unless (length (take 8193 path) <= 8192) $
    ioError (userError "registration FILE path exceeds its cap")
  absolute <- makeAbsolute path
  checkPrefixes (scanl1 (</>) (splitDirectories absolute))
  withBinaryFile absolute ReadMode $ \handle -> do
    -- At most cap+1 bytes are allocated even for a sparse or replaced file.
    bytes <- ByteString.hGet handle (fromInteger (cap + 1))
    unless (toInteger (ByteString.length bytes) <= cap) $
      ioError (userError "registration FILE bytes exceed their bound")
    pure bytes
 where
  checkPrefixes [] = ioError (userError "empty registration FILE path")
  checkPrefixes [path] = do
    status <- getSymbolicLinkStatus path
    unless (isRegularFile status && not (isSymbolicLink status)) $
      ioError (userError "registration FILE must be a regular nonlink")
  checkPrefixes (path : rest) = do
    status <- getSymbolicLinkStatus path
    unless (isDirectory status && not (isSymbolicLink status)) $
      ioError (userError "registration FILE prefix must be a nonlink directory")
    checkPrefixes rest

safeRelative :: FilePath -> Bool
safeRelative path =
  let text = Text.pack path
      components = Text.splitOn "/" text
   in Text.isPrefixOf "DEVELOPMENT_PLAN/attestations/" text
        && not (Text.any (\c -> c == '\\' || c < ' ' || c == '\DEL') text)
        && all (\component -> not (Text.null component) && component `notElem` [".", ".."]) components
