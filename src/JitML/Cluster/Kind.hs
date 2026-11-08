{-# LANGUAGE OverloadedStrings #-}

module JitML.Cluster.Kind
  ( KindConfig (..)
  , defaultKindestNodeImage
  , defaultKindWorkerCount
  , kindConfigFor
  , kindConfigForEdgePort
  , kindConfigForEdgePortAndWorkers
  , kindConfigForWorkers
  , kindConfigNodeContainerNames
  , renderKindConfig
  , renderKindConfigWithResourcePolicy
  , rewriteKubeletResourceFlags
  , substrateKindNodeContainerNames
  )
where

import Control.Monad (unless)
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Char (isAscii, isAsciiLower, isAsciiUpper, isDigit)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding

import JitML.Substrate (Substrate (..), renderSubstrate, substrateClusterName, substrateEdgePort)

data KindConfig = KindConfig
  { kindConfigSubstrate :: Substrate
  , kindConfigName :: Text
  , kindConfigNodeImage :: Text
  , kindConfigEdgePort :: Int
  , kindConfigWorkerCount :: Int
  , kindConfigGpuLabel :: Bool
  }
  deriving stock (Eq, Show)

defaultKindestNodeImage :: Text
defaultKindestNodeImage = "kindest/node:v1.34.0"

defaultKindWorkerCount :: Int
defaultKindWorkerCount = 1

kindConfigFor :: Substrate -> KindConfig
kindConfigFor substrate =
  kindConfigForEdgePort substrate (substrateEdgePort substrate)

kindConfigForEdgePort :: Substrate -> Int -> KindConfig
kindConfigForEdgePort substrate edgePort =
  kindConfigForEdgePortAndWorkers substrate edgePort defaultKindWorkerCount

kindConfigForWorkers :: Substrate -> Int -> KindConfig
kindConfigForWorkers substrate =
  kindConfigForEdgePortAndWorkers substrate (substrateEdgePort substrate)

kindConfigForEdgePortAndWorkers :: Substrate -> Int -> Int -> KindConfig
kindConfigForEdgePortAndWorkers substrate edgePort workerCount =
  KindConfig
    { kindConfigSubstrate = substrate
    , kindConfigName = substrateClusterName substrate
    , kindConfigNodeImage = defaultKindestNodeImage
    , kindConfigEdgePort = edgePort
    , kindConfigWorkerCount = max 1 workerCount
    , kindConfigGpuLabel = substrate == LinuxCUDA
    }

-- | Rewrite only the two resource flags in a known kubeadm environment record.
-- No shell syntax is interpreted. Unrelated arguments and spacing are retained;
-- unfamiliar records, duplicate targets and extra reserved dimensions refuse.
rewriteKubeletResourceFlags :: (Text, Text) -> Text -> Either Text Text
rewriteKubeletResourceFlags (cpu, memory) raw = do
  require (Text.length raw <= 65536) "kubelet flags record exceeds its read cap"
  require
    (maybe False positiveDigits (Text.stripSuffix "m" cpu) && positiveDigits memory)
    "kubelet reservation requires positive ASCII millicores and decimal bytes"
  body <-
    maybe (Left "unrecognized kubelet flags assignment") Right $
      Text.stripPrefix "KUBELET_KUBEADM_ARGS=\"" raw >>= Text.stripSuffix "\"\n"
  let (tokens, trailing) = tokenize body
  require (not (null tokens)) "kubelet flags assignment contains no arguments"
  names <- traverse (validateToken . snd) tokens
  mapM_
    ( \name -> require (length (filter (== name) names) <= 1) ("duplicate kubelet resource flag: " <> name)
    )
    [systemFlag, enforceFlag]
  let missing = [replacement name | name <- [systemFlag, enforceFlag], name `notElem` names]
      rewritten = Text.concat [spaces <> replace token | (spaces, token) <- tokens]
      inserted = Text.concat (fmap (" " <>) missing)
  pure ("KUBELET_KUBEADM_ARGS=\"" <> rewritten <> inserted <> trailing <> "\"\n")
 where
  systemFlag = "--system-reserved"
  enforceFlag = "--enforce-node-allocatable"
  replacement name
    | name == systemFlag = systemFlag <> "=cpu=" <> cpu <> ",memory=" <> memory
    | otherwise = enforceFlag <> "=pods"
  flagName = Text.takeWhile (/= '=')
  replace token
    | flagName token `elem` [systemFlag, enforceFlag] = replacement (flagName token)
    | otherwise = token

  validateToken token = do
    require (Text.all safeArgumentChar token) "unsafe quoting or shell syntax in kubelet flags"
    let (name, suffix) = Text.breakOn "=" token
    nameBody <- maybe (Left "kubelet argument must be a long flag") Right (Text.stripPrefix "--" name)
    require
      (not (Text.null nameBody) && Text.all flagNameChar nameBody && asciiLetter (Text.head nameBody))
      "unrecognized kubelet flag name"
    whenTarget name $ do
      value <-
        maybe (Left "kubelet resource flag requires an inline value") Right (Text.stripPrefix "=" suffix)
      require (not (Text.null value)) "kubelet resource flag has an empty value"
      if name == systemFlag
        then do
          let components = fmap (Text.breakOn "=") (Text.splitOn "," value)
              keys = fmap fst components
          require
            ( keys `elem` [["cpu", "memory"], ["memory", "cpu"]]
                && all (\(_, component) -> maybe False (not . Text.null) (Text.stripPrefix "=" component)) components
            )
            "system-reserved must contain only one CPU and one memory reservation"
        else
          require
            ( all
                ( `elem`
                    [ "pods"
                    , "none"
                    , "system-reserved"
                    , "kube-reserved"
                    , "system-reserved-compressible"
                    , "kube-reserved-compressible"
                    ]
                )
                (Text.splitOn "," value)
            )
            "unrecognized enforce-node-allocatable value"
    pure name

  whenTarget name action
    | name `elem` [systemFlag, enforceFlag] = action
    | otherwise = Right ()

  positiveDigits value =
    not (Text.null value)
      && Text.length value <= 128
      && Text.all asciiDigit value
      && Text.any (/= '0') value
  asciiDigit char = isAscii char && isDigit char
  asciiLetter char = isAsciiLower char || isAsciiUpper char
  flagNameChar char = asciiLetter char || asciiDigit char || char == '-'
  safeArgumentChar char = asciiLetter char || asciiDigit char || char `elem` ("-._/=:,+@%[]" :: String)

  tokenize remaining =
    let (spaces, afterSpaces) = Text.span (== ' ') remaining
     in if Text.null afterSpaces
          then ([], spaces)
          else
            let (token, rest) = Text.break (== ' ') afterSpaces
                (tokens, trailing) = tokenize rest
             in ((spaces, token) : tokens, trailing)

  require condition reason = unless condition (Left reason)

renderKindConfig :: KindConfig -> Text
renderKindConfig = renderKindConfigWithResourcePolicy False Nothing

-- | Opt-in scheduling and kubelet reservations, after resource validation.
-- Reserves must account for the capacity actually exposed by the runtime;
-- callers must check live node Allocatable before deploying workloads.
-- This reserves pod capacity without enforcing an OS-daemon cgroup limit.
renderKindConfigWithResourcePolicy :: Bool -> Maybe (Text, Text) -> KindConfig -> Text
renderKindConfigWithResourcePolicy scheduleControlPlane systemReserve config =
  Text.unlines $
    [ "kind: Cluster"
    , "apiVersion: kind.x-k8s.io/v1alpha4"
    , "name: " <> kindConfigName config
    ]
      <> nvidiaContainerdPatch
      <> ["nodes:"]
      <> controlPlaneNode
      <> concatMap workerNode [1 .. kindConfigWorkerCount config]
 where
  controlPlaneNode =
    [ "  - role: control-plane"
    , "    image: " <> kindConfigNodeImage config
    , "    extraPortMappings:"
    , "      - containerPort: 30090"
    , "        hostPort: " <> Text.pack (show (kindConfigEdgePort config))
    , "        listenAddress: 127.0.0.1"
    , "        protocol: TCP"
    ]
      <> nodeLabels "InitConfiguration" False
      <> nodeMounts False

  workerNode _index =
    [ "  - role: worker"
    , "    image: " <> kindConfigNodeImage config
    ]
      <> nodeLabels "JoinConfiguration" True
      <> nodeMounts True

  nvidiaContainerdPatch
    | kindConfigGpuLabel config =
        [ "containerdConfigPatches:"
        , "  - |-"
        , "    [plugins.\"io.containerd.grpc.v1.cri\".containerd.runtimes.nvidia]"
        , "      runtime_type = \"io.containerd.runc.v2\""
        , "      base_runtime_spec = \"/etc/containerd/cri-base.json\""
        , "      privileged_without_host_devices = false"
        , "    [plugins.\"io.containerd.grpc.v1.cri\".containerd.runtimes.nvidia.options]"
        , "      BinaryName = \"/usr/bin/nvidia-container-runtime\""
        , "      SystemdCgroup = true"
        ]
    | otherwise = []

  nodeLabels kubeadmKind computeNode =
    [ "    kubeadmConfigPatches:"
    , "      - |"
    , "        kind: " <> kubeadmKind
    , "        nodeRegistration:"
    ]
      <> ["          taints: []" | scheduleControlPlane && not computeNode]
      <> [ "          kubeletExtraArgs:"
         , "            node-labels: " <> Text.intercalate "," labels
         ]
      <> reserveArgs
   where
    labels =
      ["jitml.substrate/" <> renderSubstrate (kindConfigSubstrate config) <> "=true"]
        <> ["jitml.node-role/compute=true" | computeNode]
        <> ["jitml.runtime/gpu=true" | computeNode && kindConfigGpuLabel config]

  reserveArgs =
    case systemReserve of
      Nothing -> []
      Just (cpu, memory) ->
        [ "            system-reserved: " <> quantity ("cpu=" <> cpu <> ",memory=" <> memory)
        , "            enforce-node-allocatable: pods"
        ]

  quantity = Text.Encoding.decodeUtf8 . LazyByteString.toStrict . Aeson.encode

  nodeMounts includeNvidia =
    [ "    extraMounts:"
    , "      - hostPath: ./.build"
    , "        containerPath: /jitml/.build"
    , "        readOnly: false"
    , "      - hostPath: ./.data"
    , "        containerPath: /jitml/.data"
    , "        readOnly: false"
    ]
      <> nvidiaToolkitMounts includeNvidia

  nvidiaToolkitMounts includeNvidia
    | includeNvidia && kindConfigGpuLabel config =
        concatMap
          renderReadOnlyMount
          [ ("./kind/nvidia-container-runtime", "/etc/nvidia-container-runtime")
          , ("/", "/run/nvidia/driver")
          , ("/usr/bin/nvidia-container-runtime", "/usr/bin/nvidia-container-runtime")
          , ("/usr/bin/nvidia-container-runtime-hook", "/usr/bin/nvidia-container-runtime-hook")
          , ("/usr/bin/nvidia-container-toolkit", "/usr/bin/nvidia-container-toolkit")
          , ("/usr/bin/nvidia-container-cli", "/usr/bin/nvidia-container-cli")
          , ("/usr/bin/nvidia-cdi-hook", "/usr/bin/nvidia-cdi-hook")
          , ("/usr/bin/nvidia-ctk", "/usr/bin/nvidia-ctk")
          ,
            ( "/usr/lib/x86_64-linux-gnu/libnvidia-container.so.1"
            , "/usr/lib/x86_64-linux-gnu/libnvidia-container.so.1"
            )
          ,
            ( "/usr/lib/x86_64-linux-gnu/libnvidia-container-go.so.1"
            , "/usr/lib/x86_64-linux-gnu/libnvidia-container-go.so.1"
            )
          , ("/usr/lib/x86_64-linux-gnu/libnvidia-ml.so.1", "/usr/lib/x86_64-linux-gnu/libnvidia-ml.so.1")
          ]
    | otherwise = []

  renderReadOnlyMount (hostPath, containerPath) =
    [ "      - hostPath: " <> hostPath
    , "        containerPath: " <> containerPath
    , "        readOnly: true"
    ]

kindConfigNodeContainerNames :: KindConfig -> [Text]
kindConfigNodeContainerNames config =
  substrateKindNodeContainerNames
    (kindConfigSubstrate config)
    (kindConfigWorkerCount config)

substrateKindNodeContainerNames :: Substrate -> Int -> [Text]
substrateKindNodeContainerNames substrate workerCount =
  substrateClusterName substrate
    <> "-control-plane"
    : [ substrateClusterName substrate <> workerSuffix index
      | index <- [1 .. max 1 workerCount]
      ]
 where
  workerSuffix 1 = "-worker"
  workerSuffix index = "-worker" <> Text.pack (show index)
