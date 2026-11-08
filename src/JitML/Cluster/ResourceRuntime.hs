{-# LANGUAGE OverloadedStrings #-}

-- | Read the already-running Docker runtime and the actual Linux caller's
-- cgroup limits. These probes never start a VM.
module JitML.Cluster.ResourceRuntime
  ( CallerResourceLimits (..)
  , validateCallerResourceLimits
  , resolveUnifiedCgroupDirectory
  , checkCallerResourceLimitsIO
  , probeRuntimeCapacity
  , checkResourceEnvelopeIO
  , reserveCallerForSibling
  , checkResourceEnvelopeWithSiblingIO
  , kubeletReservationsFromNodeCapacities
  , reconcileKubeletResourcesIO
  )
where

import Control.Exception.Safe (displayException, tryAny)
import Control.Monad (unless)
import Data.Aeson (Value, eitherDecode, eitherDecodeStrict', withObject, (.:))
import Data.Aeson.Types (Parser, parseEither)
import Data.ByteString qualified as Bytes
import Data.ByteString.Lazy qualified as Lazy
import Data.Char (isAscii, isControl, isDigit)
import Data.Either.Combinators (mapLeft)
import Data.List (isPrefixOf, nub)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Encoding
import GHC.Clock (getMonotonicTimeNSec)
import System.FilePath.Posix (isAbsolute, normalise, splitDirectories, takeDirectory, (</>))
import System.IO (IOMode (ReadMode), withBinaryFile)
import System.Info qualified as System
import System.Posix.Files qualified as Posix
import System.Timeout (timeout)

import JitML.Cluster.Kind (rewriteKubeletResourceFlags, substrateKindNodeContainerNames)
import JitML.Cluster.ResourceBudget
  ( ResourceEnvelope (..)
  , RuntimeCapacity (..)
  , parseCpuMilli
  , parseMemoryBytes
  , validateResourceEnvelope
  )
import JitML.Cluster.Resources (ClusterResources, workerCount)
import JitML.Sub.Outcome (ProcessOutcome (..), ProcessTranscript (..), renderProcessFailure)
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (subprocess, subprocessWithStdin)
import JitML.Substrate (Substrate, substrateClusterName)

-- | Literal cgroup-v2 control values observed for the current calling
-- process. "max", missing values and malformed limits are not finite caps.
data CallerResourceLimits = CallerResourceLimits
  { callerMemoryMax :: Text
  , callerMemorySwapMax :: Text
  , callerCpuMax :: Text
  }
  deriving stock (Eq, Show)

validateCallerResourceLimits :: ResourceEnvelope -> CallerResourceLimits -> Either Text ()
validateCallerResourceLimits envelope limits = do
  memory <- scalar "memory.max" (callerMemoryMax limits)
  swap <- scalar "memory.swap.max" (callerMemorySwapMax limits)
  (quota, period) <- case Text.words (callerCpuMax limits) of
    [rawQuota, rawPeriod] -> (,) <$> decimal "cpu.max quota" rawQuota <*> decimal "cpu.max period" rawPeriod
    _ -> Left "caller cpu.max must contain one finite quota and period"
  require
    (memory > 0 && memory <= envelopeJobMemoryBytes envelope)
    "caller memory.max exceeds the selected job budget or is not positive"
  require (swap == 0) "caller memory.swap.max must be zero"
  require (quota > 0 && period > 0) "caller cpu.max quota and period must be positive"
  require
    (quota * 1000 <= envelopeJobCpuMilli envelope * period)
    "caller cpu.max exceeds the selected job CPU budget"
 where
  scalar label raw = case Text.words raw of
    [value] -> decimal label value
    _ -> Left ("caller " <> label <> " must contain one finite integer")

decimal :: Text -> Text -> Either Text Integer
decimal label value = do
  require
    (not (Text.null value) && Text.length value <= 20 && Text.all (\c -> isAscii c && isDigit c) value)
    ("caller " <> label <> " must be a finite decimal integer")
  let parsed = Text.foldl' (\n c -> n * 10 + toInteger (fromEnum c - fromEnum '0')) 0 value
  require
    (parsed <= 9223372036854775807)
    ("caller " <> label <> " exceeds the supported integer range")
  pure parsed

require :: Bool -> Text -> Either Text ()
require condition reason = unless condition (Left reason)

-- | Resolve the process's unified membership against cgroup2 mount roots.
-- Namespace-relative '/' membership and mounted subtrees are both supported.
-- Ambiguous mappings, v1/hybrid membership and traversal refuse rather than
-- guessing that the visible /sys/fs/cgroup belongs to the caller.
resolveUnifiedCgroupDirectory :: Text -> Text -> Either Text FilePath
resolveUnifiedCgroupDirectory membership mountinfo = do
  member <- case filter (not . Text.null) (Text.lines membership) of
    [line] -> case Text.splitOn ":" line of
      ["0", "", path] -> absolutePath path
      _ -> Left "caller requires one unified cgroup-v2 membership"
    _ -> Left "caller requires one unified cgroup-v2 membership"
  mounts <- traverse parseMount (filter (not . Text.null) (Text.lines mountinfo))
  let candidates =
        nub
          [ if null suffix then point else point </> suffix
          | Just (root, point) <- mounts
          , Just suffix <- [relativeMember root member]
          ]
  case candidates of
    [directory] -> pure (normalise directory)
    [] -> Left "caller cgroup-v2 membership has no visible matching mount"
    _ -> Left "caller cgroup-v2 membership has ambiguous visible mounts"
 where
  relativeMember root member
    | root == member = Just ""
    | root == "/" = case member of
        '/' : suffix -> Just suffix
        _ -> Nothing
    | (root <> "/") `isPrefixOf` member = Just (drop (length root + 1) member)
    | otherwise = Nothing
  parseMount line = case break (== "-") (Text.words line) of
    (before, _ : filesystem : _source : _options : _)
      | length before >= 6 ->
          if filesystem == "cgroup2"
            then do
              root <- decodeMountField (before !! 3) >>= absolutePath
              point <- decodeMountField (before !! 4) >>= absolutePath
              pure (Just (root, point))
            else pure Nothing
    _ -> Left "cannot parse caller mountinfo"

absolutePath :: Text -> Either Text FilePath
absolutePath value = do
  let path = Text.unpack value
  require
    ( isAbsolute path
        && normalise path == path
        && not (Text.any isControl value)
        && all (`notElem` [".", ".."]) (splitDirectories path)
    )
    "noncanonical caller cgroup coordinate"
  pure path

decodeMountField :: Text -> Either Text Text
decodeMountField = fmap Text.pack . go . Text.unpack
 where
  go [] = Right []
  go ('\\' : a : b : c : rest) = do
    decoded <- case [a, b, c] of
      "040" -> Right ' '
      "011" -> Right '\t'
      "012" -> Right '\n'
      "134" -> Right '\\'
      _ -> Left "unsupported caller mountinfo escape"
    (decoded :) <$> go rest
  go ('\\' : _) = Left "truncated caller mountinfo escape"
  go (c : rest) = (c :) <$> go rest

-- | Linux callers must themselves have finite cgroup-v2 job limits. This
-- never starts a runtime and does not inspect another probe container.
-- On non-Linux hosts it returns Right without a containment claim: native
-- host work remains subject to its separate operator CPU/heap/pressure guard.
checkCallerResourceLimitsIO :: ResourceEnvelope -> IO (Either Text ())
checkCallerResourceLimitsIO envelope
  | System.os /= "linux" = pure (Right ())
  | otherwise = do
      outcome <- tryAny $ do
        membership <- readSmall 16384 "/proc/self/cgroup"
        mountinfo <- readSmall 1048576 "/proc/self/mountinfo"
        directory <-
          either (ioError . userError . Text.unpack) pure (resolveUnifiedCgroupDirectory membership mountinfo)
        let paths = fmap (directory </>) ["memory.max", "memory.swap.max", "cpu.max"]
        values <- traverse readControl paths
        again <- traverse readControl paths
        membershipAfter <- readSmall 16384 "/proc/self/cgroup"
        mountinfoAfter <- readSmall 1048576 "/proc/self/mountinfo"
        unless (values == again && membership == membershipAfter && mountinfo == mountinfoAfter) $
          ioError (userError "caller cgroup membership, mounts or limits changed during observation")
        case values of
          [memory, swap, cpu] -> pure (validateCallerResourceLimits envelope (CallerResourceLimits memory swap cpu))
          _ -> pure (Left "caller cgroup control observation is incomplete")
      pure $ case outcome of
        Left failure -> Left ("cannot verify Linux caller cgroup limits: " <> Text.pack (displayException failure))
        Right result -> result
 where
  readControl path = do
    let parents = case splitDirectories (takeDirectory path) of
          [] -> []
          _ : rest -> scanl (</>) "/" rest
    mapM_
      ( \parent -> do
          status <- Posix.getSymbolicLinkStatus parent
          unless (Posix.isDirectory status) (ioError (userError "caller cgroup parent is not physical"))
      )
      parents
    status <- Posix.getSymbolicLinkStatus path
    unless
      (Posix.isRegularFile status)
      (ioError (userError "caller cgroup control is not an ordinary file"))
    readSmall 256 path

readSmall :: Int -> FilePath -> IO Text
readSmall limit path = withBinaryFile path ReadMode $ \handle -> do
  bytes <- Bytes.hGet handle (limit + 1)
  unless
    (Bytes.length bytes <= limit)
    (ioError (userError "caller cgroup metadata exceeds its read cap"))
  either (ioError . userError . show) pure (Encoding.decodeUtf8' bytes)

probeRuntimeCapacity :: IO (Either Text RuntimeCapacity)
probeRuntimeCapacity = do
  outcome <-
    timeout 15000000 $
      runStreaming defaultSubprocessEnv $
        subprocess "docker" ["info", "--format", "{\"NCPU\":{{.NCPU}},\"MemTotal\":{{.MemTotal}}}"]
  pure $ case outcome of
    Nothing -> Left "Docker runtime capacity probe exceeded its 15-second budget"
    Just (ProcessFailed failure) -> Left ("cannot inspect the explicitly selected Docker runtime: " <> renderProcessFailure failure)
    Just (ProcessSucceeded transcript) -> do
      value <-
        mapLeft Text.pack $
          eitherDecode (Lazy.fromStrict (Encoding.encodeUtf8 (processTranscriptStdout transcript)))
      mapLeft Text.pack $
        parseEither
          ( withObject "Docker runtime capacity" $ \obj -> RuntimeCapacity <$> obj .: "NCPU" <*> obj .: "MemTotal"
          )
          value

checkResourceEnvelopeIO :: ClusterResources -> IO (Either Text (RuntimeCapacity, ResourceEnvelope))
checkResourceEnvelopeIO = checkResourceEnvelopeForCallerIO Right

-- | Split the existing job slot, rather than adding a sibling helper on top
-- of an already admitted VM envelope. Hard node/VM totals remain unchanged;
-- only the maximum actual caller is reduced while the sibling is active.
reserveCallerForSibling :: Integer -> Integer -> ResourceEnvelope -> Either Text ResourceEnvelope
reserveCallerForSibling memoryBytes cpuMilli envelope = do
  require (memoryBytes > 0 && cpuMilli > 0) "sibling memory and CPU reservations must be positive"
  require
    (memoryBytes < envelopeJobMemoryBytes envelope && cpuMilli < envelopeJobCpuMilli envelope)
    "sibling reservation leaves no positive caller allowance within the selected job budget"
  pure
    envelope
      { envelopeJobMemoryBytes = envelopeJobMemoryBytes envelope - memoryBytes
      , envelopeJobCpuMilli = envelopeJobCpuMilli envelope - cpuMilli
      }

checkResourceEnvelopeWithSiblingIO
  :: Integer -> Integer -> ClusterResources -> IO (Either Text (RuntimeCapacity, ResourceEnvelope))
checkResourceEnvelopeWithSiblingIO memoryBytes cpuMilli =
  checkResourceEnvelopeForCallerIO (reserveCallerForSibling memoryBytes cpuMilli)

checkResourceEnvelopeForCallerIO
  :: (ResourceEnvelope -> Either Text ResourceEnvelope)
  -> ClusterResources
  -> IO (Either Text (RuntimeCapacity, ResourceEnvelope))
checkResourceEnvelopeForCallerIO callerAllowance resources = do
  capacity <- probeRuntimeCapacity
  case capacity of
    Left failure -> pure (Left failure)
    Right runtime -> case validateResourceEnvelope runtime resources of
      Left failure -> pure (Left failure)
      Right envelope -> case callerAllowance envelope of
        Left failure -> pure (Left failure)
        Right allowed -> do
          caller <- checkCallerResourceLimitsIO allowed
          pure ((\() -> (runtime, envelope)) <$> caller)

-- | Calibrate against the capacity reported by each actual kubelet, rather
-- than Docker's independently observed MemTotal. Even a page-sized difference
-- otherwise leaves Allocatable above the strict application budget. No margin
-- or tolerance is introduced: capacity minus reservation equals that budget.
kubeletReservationsFromNodeCapacities
  :: Substrate -> ClusterResources -> ResourceEnvelope -> Text -> Either Text [(Text, (Text, Text))]
kubeletReservationsFromNodeCapacities substrate resources envelope raw = do
  require (Text.length raw <= 1048576) "node capacity inventory exceeds its read cap"
  value <-
    mapLeft
      (("invalid node capacity JSON: " <>) . Text.pack)
      (eitherDecodeStrict' (Encoding.encodeUtf8 raw))
  observed <-
    mapLeft (("invalid node capacity inventory: " <>) . Text.pack) (parseEither parseInventory value)
  let expected = substrateKindNodeContainerNames substrate (workerCount resources)
      names = [name | (name, _, _) <- observed]
      capacities = Map.fromList [(name, (cpu, memory)) | (name, cpu, memory) <- observed]
  require (workerCount resources >= 1) "node capacity inventory requires at least one compute worker"
  require
    (toInteger (length expected) == envelopeNodeCount envelope)
    "node capacity inventory profile does not match the validated envelope node count"
  require
    (length names == Set.size (Set.fromList names))
    "node capacity inventory contains duplicate names"
  require
    (Set.fromList names == Set.fromList expected)
    "node capacity inventory names do not match the exact selected Kind topology"
  require
    (envelopeNodeApplicationCpuMilli envelope > 0 && envelopeNodeApplicationMemoryBytes envelope > 0)
    "validated envelope has no positive per-node application capacity"
  traverse (reservation capacities) expected
 where
  parseInventory :: Value -> Parser [(Text, Text, Text)]
  parseInventory = withObject "node capacity inventory" $ \object -> do
    version <- object .: "apiVersion"
    kind <- object .: "kind"
    unless (version == ("v1" :: Text) && kind `elem` (["List", "NodeList"] :: [Text])) $
      fail "expected a v1 List or NodeList"
    nodes <- object .: "items"
    traverse parseCapacity nodes
  parseCapacity :: Value -> Parser (Text, Text, Text)
  parseCapacity = withObject "node capacity" $ \object -> do
    metadata <- object .: "metadata"
    status <- object .: "status"
    capacity <- status .: "capacity"
    (,,) <$> metadata .: "name" <*> capacity .: "cpu" <*> capacity .: "memory"
  reservation capacities name = do
    (rawCpu, rawMemory) <-
      maybe (Left (name <> ": capacity is absent")) Right (Map.lookup name capacities)
    cpu <- mapLeft ((name <> ": capacity CPU: ") <>) (parseCpuMilli rawCpu)
    memory <- mapLeft ((name <> ": capacity memory: ") <>) (parseMemoryBytes rawMemory)
    let reservedCpu = cpu - envelopeNodeApplicationCpuMilli envelope
        reservedMemory = memory - envelopeNodeApplicationMemoryBytes envelope
    require
      (reservedCpu > 0 && reservedMemory > 0)
      (name <> ": capacity leaves no positive kubelet system reservation")
    pure (name, (Text.pack (show reservedCpu) <> "m", Text.pack (show reservedMemory)))

-- | Reconcile the actual Kind kubelet resource flags without recreating nodes
-- or touching their PVs. Only changed files cause a kubelet restart. Writes use
-- a separate file and an atomic rename after exact readback; a later live Node
-- observation must still prove the intended Allocatable values.
reconcileKubeletResourcesIO
  :: Substrate -> ClusterResources -> ResourceEnvelope -> IO (Either Text [Text])
reconcileKubeletResourcesIO substrate resources envelope = do
  inventory <-
    execute $
      subprocess
        "kubectl"
        [ "--kubeconfig"
        , "./.build/jitml.kubeconfig"
        , "--context"
        , "kind-" <> substrateClusterName substrate
        , "--request-timeout=5s"
        , "get"
        , "nodes"
        , "-o"
        , "json"
        ]
  case inventory >>= kubeletReservationsFromNodeCapacities substrate resources envelope of
    Left reason -> pure (Left reason)
    Right reservations -> go [] reservations
 where
  flagsPath = "/var/lib/kubelet/kubeadm-flags.env"
  execute command = do
    outcome <- tryAny (timeout 10000000 (runStreaming defaultSubprocessEnv command))
    pure $ case outcome of
      Left failure -> Left ("kubelet resource command exception: " <> Text.pack (displayException failure))
      Right Nothing -> Left "kubelet resource command exceeded its 10-second budget"
      Right (Just (ProcessFailed failure)) -> Left (renderProcessFailure failure)
      Right (Just (ProcessSucceeded transcript))
        | Text.length (processTranscriptStdout transcript) <= 1048576 ->
            Right (processTranscriptStdout transcript)
        | otherwise -> Left "kubelet resource metadata exceeds its read cap"
  remoteDeadline = ["/usr/bin/timeout", "--signal=TERM", "--kill-after=1s", "5s"]
  inside node arguments = subprocess "docker" (["exec", node] <> remoteDeadline <> arguments)
  go changed [] = pure (Right (reverse changed))
  go changed ((node, reservation) : rest) = do
    physical <- execute (inside node ["stat", "--format=%F %h", "--", flagsPath])
    case physical of
      Left reason -> pure (Left (node <> ": " <> reason))
      Right value
        | Text.strip value /= "regular file 1" ->
            pure (Left (node <> ": kubelet flags must be a regular single-link file"))
      Right _ -> do
        observed <- execute (inside node ["head", "-c", "65537", "--", flagsPath])
        case observed >>= rewriteKubeletResourceFlags reservation of
          Left reason -> pure (Left (node <> ": " <> reason))
          Right desired -> case observed of
            Right original | original == desired -> go ((node <> ": kubelet resources unchanged") : changed) rest
            _ -> do
              nonce <- getMonotonicTimeNSec
              let temporaryPath = flagsPath <> ".jitml-resource-" <> Text.pack (show nonce) <> ".tmp"
              written <-
                execute
                  ( subprocessWithStdin
                      "docker"
                      ( [ "exec"
                        , "--interactive"
                        , node
                        ]
                          <> remoteDeadline
                          <> [ "dd"
                             , "of=" <> temporaryPath
                             , "oflag=nofollow"
                             , "conv=excl,fsync"
                             , "status=none"
                             ]
                      )
                      desired
                  )
              case written of
                Left reason -> pure (Left (node <> ": " <> reason))
                Right _ -> do
                  readback <- execute (inside node ["head", "-c", "65537", "--", temporaryPath])
                  if readback /= Right desired
                    then pure (Left (node <> ": temporary kubelet resource flags readback differs"))
                    else do
                      applied <-
                        applyCommands
                          node
                          [ ["chmod", "0600", "--", temporaryPath]
                          , ["mv", "--", temporaryPath, flagsPath]
                          , ["systemctl", "--no-block", "restart", "kubelet"]
                          ]
                      case applied of
                        Left reason -> pure (Left (node <> ": " <> reason))
                        Right () -> go ((node <> ": kubelet resource reservation reconciled") : changed) rest
  applyCommands _ [] = pure (Right ())
  applyCommands node (command : rest) = do
    outcome <- execute (inside node command)
    case outcome of
      Left reason -> pure (Left reason)
      Right _ -> applyCommands node rest
