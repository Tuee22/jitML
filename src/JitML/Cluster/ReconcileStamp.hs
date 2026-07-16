{-# LANGUAGE OverloadedStrings #-}

-- | Pure convergence evidence plus the deterministic workspace fingerprint
-- used by the retained-cluster reconciler. This module deliberately owns no
-- Kind, Helm, kubectl, or publication mutation; callers gather observations
-- and apply the resulting decision at the CLI boundary.
module JitML.Cluster.ReconcileStamp
  ( DesiredInputFingerprint (..)
  , EvidenceScope (..)
  , LivePublicationObservation (..)
  , ReconcileDecision (..)
  , ReconcileDriftReason (..)
  , ReconcileEvidence (..)
  , ReconcileObservation (..)
  , ReconcileStamp (..)
  , classifyReconcileObservation
  , currentReconcileStampVersion
  , fingerprintWorkspace
  , mkDesiredInputFingerprint
  , mkReconcileStamp
  , workspaceFingerprintExcludedDirectories
  )
where

import Crypto.Hash.SHA256 qualified as SHA256
import Data.Aeson
  ( FromJSON (..)
  , ToJSON (..)
  , object
  , withObject
  , withText
  , (.:)
  , (.=)
  )
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as ByteString.Char8
import Data.Char (isHexDigit, toLower)
import Data.List qualified as List
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word8)
import System.Directory
  ( doesDirectoryExist
  , doesFileExist
  , getSymbolicLinkTarget
  , listDirectory
  , pathIsSymbolicLink
  )
import System.FilePath
  ( makeRelative
  , normalise
  , takeFileName
  , (</>)
  )

import JitML.Substrate (Substrate, parseSubstrate, renderSubstrate)

-- | Increment when the persisted stamp or its fingerprint framing changes.
currentReconcileStampVersion :: Int
currentReconcileStampVersion = 1

-- | Lower-case SHA-256 of the canonical desired-input stream.
newtype DesiredInputFingerprint = DesiredInputFingerprint
  { unDesiredInputFingerprint :: Text
  }
  deriving stock (Eq, Ord, Show)

instance ToJSON DesiredInputFingerprint where
  toJSON = toJSON . unDesiredInputFingerprint

instance FromJSON DesiredInputFingerprint where
  parseJSON =
    withText "DesiredInputFingerprint" $ \value ->
      case mkDesiredInputFingerprint value of
        Left message -> fail (Text.unpack message)
        Right fingerprint -> pure fingerprint

mkDesiredInputFingerprint :: Text -> Either Text DesiredInputFingerprint
mkDesiredInputFingerprint value
  | Text.length stripped /= 64 =
      Left "desired-input fingerprint must contain exactly 64 hexadecimal characters"
  | not (Text.all isHexDigit stripped) =
      Left "desired-input fingerprint contains a non-hexadecimal character"
  | otherwise =
      Right (DesiredInputFingerprint (Text.map toLower stripped))
 where
  stripped = Text.strip value

-- | The successful desired state recorded after a live reconcile.
data ReconcileStamp = ReconcileStamp
  { reconcileStampVersion :: Int
  , reconcileStampSubstrate :: Substrate
  , reconcileStampEdgePort :: Int
  , reconcileStampDesiredInputFingerprint :: DesiredInputFingerprint
  , reconcileStampRepoAppImageIds :: Map Text Text
  }
  deriving stock (Eq, Show)

instance ToJSON ReconcileStamp where
  toJSON stamp =
    object
      [ "version" .= reconcileStampVersion stamp
      , "substrate" .= renderSubstrate (reconcileStampSubstrate stamp)
      , "edge_port" .= reconcileStampEdgePort stamp
      , "desired_input_fingerprint" .= reconcileStampDesiredInputFingerprint stamp
      , "repo_app_image_ids" .= reconcileStampRepoAppImageIds stamp
      ]

instance FromJSON ReconcileStamp where
  parseJSON =
    withObject "ReconcileStamp" $ \objectValue -> do
      version <- objectValue .: "version"
      substrateText <- objectValue .: "substrate"
      substrate <-
        maybe
          (fail ("unknown substrate: " <> Text.unpack substrateText))
          pure
          (parseSubstrate substrateText)
      edgePort <- objectValue .: "edge_port"
      fingerprint <- objectValue .: "desired_input_fingerprint"
      imageIds <- objectValue .: "repo_app_image_ids"
      case validateStampFields version edgePort imageIds of
        Left message -> fail (Text.unpack message)
        Right () ->
          pure
            ReconcileStamp
              { reconcileStampVersion = version
              , reconcileStampSubstrate = substrate
              , reconcileStampEdgePort = edgePort
              , reconcileStampDesiredInputFingerprint = fingerprint
              , reconcileStampRepoAppImageIds = imageIds
              }

mkReconcileStamp
  :: Substrate
  -> Int
  -> DesiredInputFingerprint
  -> Map Text Text
  -> Either Text ReconcileStamp
mkReconcileStamp substrate edgePort fingerprint imageIds = do
  validateStampFields currentReconcileStampVersion edgePort imageIds
  pure
    ReconcileStamp
      { reconcileStampVersion = currentReconcileStampVersion
      , reconcileStampSubstrate = substrate
      , reconcileStampEdgePort = edgePort
      , reconcileStampDesiredInputFingerprint = fingerprint
      , reconcileStampRepoAppImageIds = imageIds
      }

validateStampFields :: Int -> Int -> Map Text Text -> Either Text ()
validateStampFields version edgePort imageIds
  | version < 1 = Left "reconcile stamp version must be positive"
  | edgePort < 1 || edgePort > 65535 =
      Left "reconcile stamp edge port must be within 1..65535"
  | Map.null imageIds =
      Left "reconcile stamp must carry at least one repo app image ID"
  | any (Text.null . Text.strip) (Map.keys imageIds) =
      Left "reconcile stamp contains an empty repo app image key"
  | any (Text.null . Text.strip) (Map.elems imageIds) =
      Left "reconcile stamp contains an empty repo app image ID"
  | otherwise = Right ()

-- | Directory basenames omitted at any workspace depth. These are mutable
-- build/runtime caches, never desired deployment inputs. Symlinks are hashed as
-- symlinks and are not traversed, even when their target names one of these
-- directories.
workspaceFingerprintExcludedDirectories :: [FilePath]
workspaceFingerprintExcludedDirectories =
  [ ".git"
  , ".build"
  , ".data"
  , ".dist-newstyle"
  , "dist-newstyle"
  , "node_modules"
  , ".spago"
  , "playwright-report"
  , "test-results"
  ]

workspaceFingerprintExcludedRelativeDirectories :: [FilePath]
workspaceFingerprintExcludedRelativeDirectories =
  ["web/output"]

data WorkspaceEntry
  = WorkspaceRegularFile FilePath ByteString
  | WorkspaceSymbolicLink FilePath FilePath

-- | Hash every regular file and symlink below the root in sorted relative-path
-- order. File contents, symlink targets, entry types, and paths are
-- length-framed, so neither traversal order nor concatenation ambiguity can
-- alter the digest. Symlinks are never followed.
fingerprintWorkspace :: FilePath -> IO DesiredInputFingerprint
fingerprintWorkspace root = do
  entries <- collectWorkspaceEntries root root
  let canonical =
        ByteString.concat
          ( "jitml-reconcile-workspace-v1\NUL"
              : fmap renderWorkspaceEntry (List.sortOn workspaceEntryPath entries)
          )
  pure (DesiredInputFingerprint (sha256Hex canonical))

collectWorkspaceEntries :: FilePath -> FilePath -> IO [WorkspaceEntry]
collectWorkspaceEntries root directory = do
  names <- List.sort <$> listDirectory directory
  concat <$> traverse collect names
 where
  collect name = do
    let absolutePath = directory </> name
        relativePath = canonicalRelativePath root absolutePath
    symbolic <- pathIsSymbolicLink absolutePath
    if symbolic
      then do
        target <- getSymbolicLinkTarget absolutePath
        pure [WorkspaceSymbolicLink relativePath target]
      else do
        isDirectory <- doesDirectoryExist absolutePath
        if isDirectory
          then
            if takeFileName absolutePath `elem` workspaceFingerprintExcludedDirectories
              || relativePath `elem` workspaceFingerprintExcludedRelativeDirectories
              then pure []
              else collectWorkspaceEntries root absolutePath
          else do
            isFile <- doesFileExist absolutePath
            if isFile
              then do
                bytes <- ByteString.readFile absolutePath
                pure [WorkspaceRegularFile relativePath bytes]
              else pure []

canonicalRelativePath :: FilePath -> FilePath -> FilePath
canonicalRelativePath root =
  fmap slash . normalise . makeRelative root
 where
  slash '\\' = '/'
  slash character = character

workspaceEntryPath :: WorkspaceEntry -> FilePath
workspaceEntryPath (WorkspaceRegularFile path _) = path
workspaceEntryPath (WorkspaceSymbolicLink path _) = path

renderWorkspaceEntry :: WorkspaceEntry -> ByteString
renderWorkspaceEntry entry =
  case entry of
    WorkspaceRegularFile path bytes ->
      "F" <> frame (pathBytes path) <> frame bytes
    WorkspaceSymbolicLink path target ->
      "L" <> frame (pathBytes path) <> frame (pathBytes target)
 where
  pathBytes = Text.Encoding.encodeUtf8 . Text.pack

frame :: ByteString -> ByteString
frame bytes =
  ByteString.Char8.pack (show (ByteString.length bytes))
    <> ":"
    <> bytes

sha256Hex :: ByteString -> Text
sha256Hex =
  Text.pack . concatMap byteHex . ByteString.unpack . SHA256.hash
 where
  byteHex :: Word8 -> String
  byteHex byte =
    let digits = "0123456789abcdef"
        high = fromIntegral byte `div` 16
        low = fromIntegral byte `mod` 16
     in [digits !! high, digits !! low]

data EvidenceScope
  = ReleaseEvidence
  | ReadinessEvidence
  | TopicEvidence
  | NodeImageEvidence
  | AppImageEvidence
  deriving stock (Eq, Ord, Show)

-- | Exact expected names and the observations gathered for one convergence
-- family. Lists retain duplicate evidence so the classifier can reject it.
data ReconcileEvidence = ReconcileEvidence
  { reconcileEvidenceExpected :: [Text]
  , reconcileEvidenceObserved :: [(Text, Bool)]
  }
  deriving stock (Eq, Show)

data LivePublicationObservation
  = LivePublicationReady
  | LivePublicationMissing
  | LivePublicationInvalid Text
  | LivePublicationNotReady Text
  deriving stock (Eq, Show)

data ReconcileObservation = ReconcileObservation
  { reconcileExpectedStamp :: ReconcileStamp
  , reconcilePersistedStamp :: Maybe ReconcileStamp
  , reconcileLivePublication :: LivePublicationObservation
  , reconcileReleaseEvidence :: ReconcileEvidence
  , reconcileReadinessEvidence :: ReconcileEvidence
  , reconcileTopicEvidence :: ReconcileEvidence
  , reconcileNodeImageEvidence :: ReconcileEvidence
  , reconcileAppImageEvidence :: ReconcileEvidence
  , reconcilePortAwareMaterializationUnchanged :: Bool
  }
  deriving stock (Eq, Show)

data ReconcileDriftReason
  = ReconcileStampMissing
  | ReconcileStampVersionMismatch Int Int
  | ReconcileStampSubstrateMismatch Substrate Substrate
  | ReconcileStampEdgePortMismatch Int Int
  | ReconcileStampDesiredInputMismatch DesiredInputFingerprint DesiredInputFingerprint
  | ReconcileStampRepoAppImageIdsMismatch (Map Text Text) (Map Text Text)
  | LivePublicationDrift LivePublicationObservation
  | PortAwareMaterializationChanged
  | EvidenceExpectedFamilyEmpty EvidenceScope
  | EvidenceExpectedDuplicate EvidenceScope Text
  | EvidenceObservedDuplicate EvidenceScope Text
  | EvidenceMissing EvidenceScope Text
  | EvidenceUnexpected EvidenceScope Text
  | EvidenceNotReady EvidenceScope Text
  deriving stock (Eq, Show)

data ReconcileDecision
  = AlreadyConverged
  | NeedsReconcile [ReconcileDriftReason]
  deriving stock (Eq, Show)

-- | Classify a complete retained-cluster observation. Empty, missing,
-- duplicate, unexpected, or false evidence is drift; success is therefore
-- non-vacuous for every required family.
classifyReconcileObservation :: ReconcileObservation -> ReconcileDecision
classifyReconcileObservation observation =
  case reasons of
    [] -> AlreadyConverged
    _ -> NeedsReconcile reasons
 where
  reasons =
    stampDriftReasons
      (reconcileExpectedStamp observation)
      (reconcilePersistedStamp observation)
      <> publicationReasons
      <> materializationReasons
      <> evidenceDriftReasons ReleaseEvidence (reconcileReleaseEvidence observation)
      <> evidenceDriftReasons ReadinessEvidence (reconcileReadinessEvidence observation)
      <> evidenceDriftReasons TopicEvidence (reconcileTopicEvidence observation)
      <> evidenceDriftReasons NodeImageEvidence (reconcileNodeImageEvidence observation)
      <> evidenceDriftReasons AppImageEvidence (reconcileAppImageEvidence observation)
  publicationReasons =
    case reconcileLivePublication observation of
      LivePublicationReady -> []
      unavailable -> [LivePublicationDrift unavailable]
  materializationReasons
    | reconcilePortAwareMaterializationUnchanged observation = []
    | otherwise = [PortAwareMaterializationChanged]

stampDriftReasons :: ReconcileStamp -> Maybe ReconcileStamp -> [ReconcileDriftReason]
stampDriftReasons _ Nothing = [ReconcileStampMissing]
stampDriftReasons expected (Just actual) =
  versionReason
    <> substrateReason
    <> portReason
    <> fingerprintReason
    <> imageReason
 where
  versionReason =
    stampFieldMismatch
      reconcileStampVersion
      ReconcileStampVersionMismatch
      expected
      actual
  substrateReason =
    stampFieldMismatch
      reconcileStampSubstrate
      ReconcileStampSubstrateMismatch
      expected
      actual
  portReason =
    stampFieldMismatch
      reconcileStampEdgePort
      ReconcileStampEdgePortMismatch
      expected
      actual
  fingerprintReason =
    stampFieldMismatch
      reconcileStampDesiredInputFingerprint
      ReconcileStampDesiredInputMismatch
      expected
      actual
  imageReason =
    stampFieldMismatch
      reconcileStampRepoAppImageIds
      ReconcileStampRepoAppImageIdsMismatch
      expected
      actual

stampFieldMismatch
  :: (Eq value)
  => (ReconcileStamp -> value)
  -> (value -> value -> ReconcileDriftReason)
  -> ReconcileStamp
  -> ReconcileStamp
  -> [ReconcileDriftReason]
stampFieldMismatch project constructor expected actual
  | project expected == project actual = []
  | otherwise = [constructor (project expected) (project actual)]

evidenceDriftReasons
  :: EvidenceScope
  -> ReconcileEvidence
  -> [ReconcileDriftReason]
evidenceDriftReasons scope evidence =
  emptyReason
    <> fmap (EvidenceExpectedDuplicate scope) expectedDuplicates
    <> fmap (EvidenceObservedDuplicate scope) observedDuplicates
    <> fmap (EvidenceMissing scope) missing
    <> fmap (EvidenceUnexpected scope) unexpected
    <> fmap (EvidenceNotReady scope) notReady
 where
  expected = List.sort (List.nub (reconcileEvidenceExpected evidence))
  observedNames = fmap fst (reconcileEvidenceObserved evidence)
  observed = List.sort (List.nub observedNames)
  expectedDuplicates = duplicateValues (reconcileEvidenceExpected evidence)
  observedDuplicates = duplicateValues observedNames
  missing = filter (`notElem` observed) expected
  unexpected = filter (`notElem` expected) observed
  notReady =
    [ name
    | name <- expected
    , any
        not
        [ready | (observedName, ready) <- reconcileEvidenceObserved evidence, observedName == name]
    ]
  emptyReason
    | null expected = [EvidenceExpectedFamilyEmpty scope]
    | otherwise = []

duplicateValues :: (Ord value) => [value] -> [value]
duplicateValues values =
  [ value
  | value : _ : _ <- List.group (List.sort values)
  ]
