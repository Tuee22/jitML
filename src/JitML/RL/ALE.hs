{-# LANGUAGE OverloadedStrings #-}

-- | Runtime-loaded Arcade Learning Environment adapter.
--
-- The Haskell package deliberately does not link against ALE at build time:
-- host builds and code-quality checks must keep working on machines where the
-- ALE C++ library is absent. The repository does not carry checked-in C++ shim
-- source; this module only loads an explicit generated or externally supplied
-- `libjitml_ale_shim.so` when an Atari run supplies an uncommitted ROM path.
module JitML.RL.ALE
  ( AleEpisode (..)
  , AleSmokeResult (..)
  , atariRomPolicyMessage
  , resolveAtariRomPath
  , runAtariSubsetEpisodes
  , runAleSmoke
  )
where

import Control.Exception (SomeException, bracket, try)
import Data.Either (fromRight)
import Data.Maybe (maybeToList)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word8)
import Foreign
  ( FunPtr
  , Ptr
  , alloca
  , allocaArray
  , castFunPtr
  , nullPtr
  , peek
  , peekArray
  )
import Foreign.C
  ( CDouble (..)
  , CInt (..)
  , CString
  , peekCString
  , withCString
  )
import System.Directory (doesFileExist)
import System.Environment (lookupEnv)
import System.Posix.DynamicLinker
  ( DL
  , RTLDFlags (RTLD_LOCAL, RTLD_NOW)
  , dlopen
  , dlsym
  )

data AleRuntime = AleRuntime
  { rtCreate :: IO (Ptr ())
  , rtDestroy :: Ptr () -> IO ()
  , rtSeed :: Ptr () -> CInt -> IO CInt
  , rtLoadRom :: Ptr () -> CString -> IO CInt
  , rtReset :: Ptr () -> IO CInt
  , rtAct :: Ptr () -> CInt -> Ptr CDouble -> IO CInt
  , rtGameOver :: Ptr () -> Ptr CInt -> IO CInt
  , rtGetRam :: Ptr () -> Ptr Word8 -> CInt -> IO CInt
  , rtScreenDims :: Ptr () -> Ptr CInt -> Ptr CInt -> IO CInt
  , rtGetScreenRgb :: Ptr () -> Ptr Word8 -> CInt -> IO CInt
  , rtLegalActions :: Ptr () -> Ptr CInt -> CInt -> Ptr CInt -> IO CInt
  , rtLastError :: IO CString
  }

data AleEpisode = AleEpisode
  { aleEpisodeIndex :: Int
  , aleEpisodeSteps :: Int
  , aleEpisodeReward :: Double
  , aleEpisodeDone :: Bool
  }
  deriving stock (Eq, Show)

data AleSmokeResult = AleSmokeResult
  { aleSmokeRamBytes :: Int
  , aleSmokeScreenBytes :: Int
  , aleSmokeScreenWidth :: Int
  , aleSmokeScreenHeight :: Int
  , aleSmokeActionCount :: Int
  , aleSmokeReward :: Double
  , aleSmokeDone :: Bool
  , aleSmokeDeterministic :: Bool
  }
  deriving stock (Eq, Show)

foreign import ccall "dynamic"
  mkCreate :: FunPtr (IO (Ptr ())) -> IO (Ptr ())

foreign import ccall "dynamic"
  mkDestroy :: FunPtr (Ptr () -> IO ()) -> Ptr () -> IO ()

foreign import ccall "dynamic"
  mkSeed :: FunPtr (Ptr () -> CInt -> IO CInt) -> Ptr () -> CInt -> IO CInt

foreign import ccall "dynamic"
  mkLoadRom :: FunPtr (Ptr () -> CString -> IO CInt) -> Ptr () -> CString -> IO CInt

foreign import ccall "dynamic"
  mkReset :: FunPtr (Ptr () -> IO CInt) -> Ptr () -> IO CInt

foreign import ccall "dynamic"
  mkAct
    :: FunPtr (Ptr () -> CInt -> Ptr CDouble -> IO CInt) -> Ptr () -> CInt -> Ptr CDouble -> IO CInt

foreign import ccall "dynamic"
  mkGameOver :: FunPtr (Ptr () -> Ptr CInt -> IO CInt) -> Ptr () -> Ptr CInt -> IO CInt

foreign import ccall "dynamic"
  mkGetRam
    :: FunPtr (Ptr () -> Ptr Word8 -> CInt -> IO CInt) -> Ptr () -> Ptr Word8 -> CInt -> IO CInt

foreign import ccall "dynamic"
  mkScreenDims
    :: FunPtr (Ptr () -> Ptr CInt -> Ptr CInt -> IO CInt) -> Ptr () -> Ptr CInt -> Ptr CInt -> IO CInt

foreign import ccall "dynamic"
  mkGetScreenRgb
    :: FunPtr (Ptr () -> Ptr Word8 -> CInt -> IO CInt) -> Ptr () -> Ptr Word8 -> CInt -> IO CInt

foreign import ccall "dynamic"
  mkLegalActions
    :: FunPtr (Ptr () -> Ptr CInt -> CInt -> Ptr CInt -> IO CInt)
    -> Ptr ()
    -> Ptr CInt
    -> CInt
    -> Ptr CInt
    -> IO CInt

foreign import ccall "dynamic"
  mkLastError :: FunPtr (IO CString) -> IO CString

atariRomPolicyMessage :: Text
atariRomPolicyMessage =
  Text.unlines
    [ "atari-subset requires an explicit uncommitted Atari 2600 ROM path."
    , "Set JITML_ATARI_ROM, JITML_ALE_ROM, or RunConfig.atariRomPath to a local file under an ignored directory such as ./.roms/."
    , "Do not commit commercial ROM bytes to the repository."
    ]

resolveAtariRomPath :: Maybe Text -> IO (Either Text FilePath)
resolveAtariRomPath configuredPath = do
  envPrimary <- lookupEnv "JITML_ATARI_ROM"
  envCompat <- lookupEnv "JITML_ALE_ROM"
  let selected =
        firstNonEmpty
          [ fmap Text.unpack configuredPath
          , envPrimary
          , envCompat
          ]
  case selected of
    Nothing -> pure (Left atariRomPolicyMessage)
    Just path -> do
      exists <- doesFileExist path
      pure $
        if exists
          then Right path
          else
            Left $
              Text.unlines
                [ "configured Atari ROM path does not exist: " <> Text.pack path
                , atariRomPolicyMessage
                ]

runAleSmoke :: Maybe Text -> IO (Either Text AleSmokeResult)
runAleSmoke configuredPath = do
  pathResult <- resolveAtariRomPath configuredPath
  case pathResult of
    Left err -> pure (Left err)
    Right romPath -> do
      runtimeResult <- loadAleRuntime
      case runtimeResult of
        Left err -> pure (Left err)
        Right runtime ->
          withAleSession runtime 17 romPath $ \handle -> do
            frame0Result <- readFrame runtime handle
            case frame0Result of
              Left err -> pure (Left err)
              Right frame0 -> do
                (reward, done) <- actOne runtime handle (firstAction (frameActions frame0))
                frame1Result <- readFrame runtime handle
                case frame1Result of
                  Left err -> pure (Left err)
                  Right frame1 -> do
                    episodesA <- runEpisodesWithLoadedRom runtime handle 17 2 12
                    case episodesA of
                      Left err -> pure (Left err)
                      Right episodesAValue -> do
                        episodesB <- runEpisodesWithLoadedRom runtime handle 17 2 12
                        case episodesB of
                          Left err -> pure (Left err)
                          Right episodesBValue ->
                            pure $
                              Right
                                AleSmokeResult
                                  { aleSmokeRamBytes = length (frameRam frame1)
                                  , aleSmokeScreenBytes = frameScreenBytes frame1
                                  , aleSmokeScreenWidth = frameScreenWidth frame1
                                  , aleSmokeScreenHeight = frameScreenHeight frame1
                                  , aleSmokeActionCount = length (frameActions frame1)
                                  , aleSmokeReward = reward
                                  , aleSmokeDone = done
                                  , aleSmokeDeterministic = episodesAValue == episodesBValue
                                  }

runAtariSubsetEpisodes :: Maybe Text -> Int -> Int -> Int -> IO (Either Text [AleEpisode])
runAtariSubsetEpisodes configuredPath seed episodeCount maxSteps = do
  pathResult <- resolveAtariRomPath configuredPath
  case pathResult of
    Left err -> pure (Left err)
    Right romPath -> do
      runtimeResult <- loadAleRuntime
      case runtimeResult of
        Left err -> pure (Left err)
        Right runtime ->
          withAleSession runtime seed romPath $ \handle ->
            runEpisodesWithLoadedRom runtime handle seed episodeCount maxSteps

data AleFrame = AleFrame
  { frameRam :: [Word8]
  , frameScreenBytes :: Int
  , frameScreenWidth :: Int
  , frameScreenHeight :: Int
  , frameActions :: [Int]
  }
  deriving stock (Eq, Show)

runEpisodesWithLoadedRom
  :: AleRuntime -> Ptr () -> Int -> Int -> Int -> IO (Either Text [AleEpisode])
runEpisodesWithLoadedRom runtime handle seed episodeCount maxSteps =
  goEpisodes 0 []
 where
  safeEpisodeCount = max 0 episodeCount
  safeMaxSteps = max 1 maxSteps
  goEpisodes episodeId acc
    | episodeId >= safeEpisodeCount = pure (Right (reverse acc))
    | otherwise = do
        resetResult <- checked runtime "jitml_ale_reset" (rtReset runtime handle)
        case resetResult of
          Left err -> pure (Left err)
          Right () -> do
            episodeResult <- runOneEpisode episodeId 0 0.0 False
            case episodeResult of
              Left err -> pure (Left err)
              Right episode -> goEpisodes (episodeId + 1) (episode : acc)
  runOneEpisode episodeId stepIndex rewardAcc done
    | stepIndex >= safeMaxSteps || done =
        pure $
          Right
            AleEpisode
              { aleEpisodeIndex = episodeId
              , aleEpisodeSteps = stepIndex
              , aleEpisodeReward = rewardAcc
              , aleEpisodeDone = done
              }
    | otherwise = do
        frame <- readFrame runtime handle
        case frame of
          Left err -> pure (Left err)
          Right currentFrame -> do
            let actions = frameActions currentFrame
                action =
                  if null actions
                    then 0
                    else actions !! ((stepIndex + episodeId + seed) `mod` length actions)
            (reward, doneNow) <- actOne runtime handle action
            runOneEpisode episodeId (stepIndex + 1) (rewardAcc + reward) doneNow

withAleSession
  :: AleRuntime
  -> Int
  -> FilePath
  -> (Ptr () -> IO (Either Text a))
  -> IO (Either Text a)
withAleSession runtime seed romPath action =
  bracket (rtCreate runtime) (rtDestroy runtime) $ \handle ->
    if handle == nullPtr
      then Left <$> runtimeError runtime "jitml_ale_create"
      else do
        seedResult <- checked runtime "jitml_ale_seed" (rtSeed runtime handle (fromIntegral seed))
        case seedResult of
          Left err -> pure (Left err)
          Right () ->
            withCString romPath $ \romCString -> do
              loadResult <- checked runtime "jitml_ale_load_rom" (rtLoadRom runtime handle romCString)
              case loadResult of
                Left err -> pure (Left err)
                Right () -> action handle

readFrame :: AleRuntime -> Ptr () -> IO (Either Text AleFrame)
readFrame runtime handle = do
  ramResult <- readRam runtime handle
  case ramResult of
    Left err -> pure (Left err)
    Right ram -> do
      screenResult <- readScreen runtime handle
      case screenResult of
        Left err -> pure (Left err)
        Right (screenBytes, width, height) -> do
          actionsResult <- readLegalActions runtime handle
          pure $
            AleFrame ram screenBytes width height
              <$> actionsResult

readRam :: AleRuntime -> Ptr () -> IO (Either Text [Word8])
readRam runtime handle =
  allocaArray 128 $ \ramPtr -> do
    result <- checked runtime "jitml_ale_get_ram" (rtGetRam runtime handle ramPtr 128)
    case result of
      Left err -> pure (Left err)
      Right () -> Right <$> peekArray 128 ramPtr

readScreen :: AleRuntime -> Ptr () -> IO (Either Text (Int, Int, Int))
readScreen runtime handle =
  alloca $ \widthPtr ->
    alloca $ \heightPtr -> do
      dimsResult <-
        checked runtime "jitml_ale_screen_dims" (rtScreenDims runtime handle widthPtr heightPtr)
      case dimsResult of
        Left err -> pure (Left err)
        Right () -> do
          width <- fmap fromIntegral (peek widthPtr)
          height <- fmap fromIntegral (peek heightPtr)
          let capacity = max 0 (width * height * 3)
          allocaArray capacity $ \screenPtr -> do
            count <- rtGetScreenRgb runtime handle screenPtr (fromIntegral capacity)
            if count < 0
              then Left <$> runtimeError runtime "jitml_ale_get_screen_rgb"
              else pure (Right (fromIntegral count, width, height))

readLegalActions :: AleRuntime -> Ptr () -> IO (Either Text [Int])
readLegalActions runtime handle =
  allocaArray 64 $ \actionsPtr ->
    alloca $ \countPtr -> do
      result <-
        checked runtime "jitml_ale_legal_actions" (rtLegalActions runtime handle actionsPtr 64 countPtr)
      case result of
        Left err -> pure (Left err)
        Right () -> do
          count <- fmap fromIntegral (peek countPtr)
          fmap (Right . fmap fromIntegral) (peekArray count actionsPtr)

actOne :: AleRuntime -> Ptr () -> Int -> IO (Double, Bool)
actOne runtime handle action =
  alloca $ \rewardPtr -> do
    actResult <- checked runtime "jitml_ale_act" (rtAct runtime handle (fromIntegral action) rewardPtr)
    case actResult of
      Left err -> fail (Text.unpack err)
      Right () -> do
        CDouble reward <- peek rewardPtr
        done <- readGameOver runtime handle
        pure (reward, done)

readGameOver :: AleRuntime -> Ptr () -> IO Bool
readGameOver runtime handle =
  alloca $ \donePtr -> do
    doneResult <- checked runtime "jitml_ale_game_over" (rtGameOver runtime handle donePtr)
    case doneResult of
      Left err -> fail (Text.unpack err)
      Right () -> do
        done <- peek donePtr
        pure (done /= 0)

checked :: AleRuntime -> Text -> IO CInt -> IO (Either Text ())
checked runtime label action = do
  status <- action
  if status == 0
    then pure (Right ())
    else do
      err <- runtimeError runtime label
      pure (Left err)

runtimeError :: AleRuntime -> Text -> IO Text
runtimeError runtime label = do
  cString <- rtLastError runtime
  if cString == nullPtr
    then pure (label <> " failed")
    else do
      msg <- Text.pack <$> peekCStringSafe cString
      pure $
        if Text.null msg
          then label <> " failed"
          else msg

peekCStringSafe :: CString -> IO String
peekCStringSafe cString = do
  result <- try (peekCString cString) :: IO (Either SomeException String)
  pure (fromRight "" result)

loadAleRuntime :: IO (Either Text AleRuntime)
loadAleRuntime = do
  envPath <- lookupEnv "JITML_ALE_SHIM_PATH"
  let paths =
        maybeToList envPath
          <> [ "libjitml_ale_shim.so"
             , "/usr/local/lib/libjitml_ale_shim.so"
             , "./.build/ale/libjitml_ale_shim.so"
             ]
  loadFirst paths []
 where
  loadFirst [] failures =
    pure $
      Left $
        Text.unlines $
          ( "ALE runtime shim is unavailable. Generate or supply "
              <> "libjitml_ale_shim.so with JITML_ALE_SHIM_PATH."
          )
            : fmap Text.pack (reverse failures)
  loadFirst (path : rest) failures = do
    attempt <- try (dlopen path [RTLD_NOW, RTLD_LOCAL]) :: IO (Either SomeException DL)
    case attempt of
      Left ex -> loadFirst rest ((path <> ": " <> show ex) : failures)
      Right handle -> do
        runtimeAttempt <- try (loadRuntimeSymbols handle) :: IO (Either SomeException AleRuntime)
        case runtimeAttempt of
          Left ex -> loadFirst rest ((path <> ": " <> show ex) : failures)
          Right runtime -> pure (Right runtime)

loadRuntimeSymbols :: DL -> IO AleRuntime
loadRuntimeSymbols handle = do
  create <- symbol "jitml_ale_create"
  destroy <- symbol "jitml_ale_destroy"
  seed <- symbol "jitml_ale_seed"
  loadRom <- symbol "jitml_ale_load_rom"
  reset <- symbol "jitml_ale_reset"
  act <- symbol "jitml_ale_act"
  gameOver <- symbol "jitml_ale_game_over"
  getRam <- symbol "jitml_ale_get_ram"
  screenDims <- symbol "jitml_ale_screen_dims"
  getScreenRgb <- symbol "jitml_ale_get_screen_rgb"
  legalActions <- symbol "jitml_ale_legal_actions"
  lastError <- symbol "jitml_ale_last_error"
  pure
    AleRuntime
      { rtCreate = mkCreate (castFunPtr create)
      , rtDestroy = mkDestroy (castFunPtr destroy)
      , rtSeed = mkSeed (castFunPtr seed)
      , rtLoadRom = mkLoadRom (castFunPtr loadRom)
      , rtReset = mkReset (castFunPtr reset)
      , rtAct = mkAct (castFunPtr act)
      , rtGameOver = mkGameOver (castFunPtr gameOver)
      , rtGetRam = mkGetRam (castFunPtr getRam)
      , rtScreenDims = mkScreenDims (castFunPtr screenDims)
      , rtGetScreenRgb = mkGetScreenRgb (castFunPtr getScreenRgb)
      , rtLegalActions = mkLegalActions (castFunPtr legalActions)
      , rtLastError = mkLastError (castFunPtr lastError)
      }
 where
  symbol = dlsym handle

firstNonEmpty :: [Maybe String] -> Maybe String
firstNonEmpty [] = Nothing
firstNonEmpty (candidate : rest) =
  case candidate of
    Just value | not (null value) -> Just value
    _ -> firstNonEmpty rest

firstAction :: [Int] -> Int
firstAction [] = 0
firstAction (action : _) = action
