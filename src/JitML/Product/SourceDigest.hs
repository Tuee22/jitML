{-# LANGUAGE OverloadedStrings #-}

-- | Phase 288 - a deterministic digest of the code roots a validation gate ran
-- against.
--
-- A gate transcript is only worth as much as the tree it validated. The stamp
-- computed here is what 'JitML.Product.ValidationRecord' binds to and what the
-- status projection compares against the tree it is evaluated in, so a
-- transcript recorded for older code is reported as stale instead of being
-- honoured indefinitely.
--
-- Algorithm version @1@:
--
-- * roots: the directories @app@, @gen@, @src@, and @test@ plus the files
--   @cabal.project@ and @jitml.cabal@, relative to the repository root. They are
--   exactly the @hs-source-dirs@ of every stanza and the two project files, so
--   everything the Haskell build compiles is covered, including the checked-in
--   generated protocol modules under @gen@; a unit test compares the list with
--   the cabal file, so a new source directory cannot escape the digest;
-- * a file participates when its name does not start with a dot and its
--   extension is in 'sourceDigestExtensions'; anything else under a root is not
--   code and cannot move the digest;
-- * a symbolic link under a root is rejected rather than followed, because a
--   link target outside the roots would make the digest depend on the host;
-- * files are ordered by their @/@-separated relative path (code point order,
--   which equals UTF-8 byte order), so directory listing order cannot matter;
-- * each file contributes its path, its normalised byte length, and its
--   normalised bytes, where normalisation rewrites every CRLF pair to LF so a
--   checkout with converted line endings hashes identically;
-- * the SHA-256 is seeded with the tag @jitml-source-digest-v1@.
--
-- Any change to the roots, the extension set, or the normalisation must bump
-- 'sourceDigestAlgorithm'; a record carrying another version is never compared.
-- The stamp reads no clock, no environment, and no version-control state.
module JitML.Product.SourceDigest
  ( SourceStamp (..)
  , computeSourceStamp
  , computeSourceStampIn
  , sourceDigestAlgorithm
  , sourceDigestDirectoryRoots
  , sourceDigestExtensions
  , sourceDigestFileRoots
  , sourceStampFromFiles
  )
where

import Control.Exception (IOException, try)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as ByteString.Char8
import Data.Char (intToDigit)
import Data.List qualified as List
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word64, Word8)
import System.Directory
  ( doesDirectoryExist
  , doesFileExist
  , listDirectory
  , pathIsSymbolicLink
  )
import System.FilePath (takeExtension, (</>))

-- | The algorithm version and the digest it produced.
data SourceStamp = SourceStamp
  { stampAlgorithm :: !Word64
  , stampSha256 :: !Text
  }
  deriving stock (Eq, Show)

sourceDigestAlgorithm :: Word64
sourceDigestAlgorithm = 1

-- | Directories walked recursively.
sourceDigestDirectoryRoots :: [FilePath]
sourceDigestDirectoryRoots = ["app", "gen", "src", "test"]

-- | Individual files read from the repository root.
sourceDigestFileRoots :: [FilePath]
sourceDigestFileRoots = ["cabal.project", "jitml.cabal"]

-- | Extensions of the files under the directory roots that count as code or
-- code-adjacent fixtures. Anything else under a root is ignored.
--
-- The set leaves out the extensions of JIT source artefacts (@.cc@, @.cpp@,
-- @.cxx@, @.cu@, @.metal@, @.swift@). That is safe only because the repository
-- lint @files.static-jit-source@ rejects a checked-in file with any of them
-- anywhere in the tree it lints, which includes @app/@, @src/@, and @test/@
-- (compiler inputs are rendered from Haskell under @.build/jit-src/@), so those
-- roots hold none. It is not because the image's @.dockerignore@ strips them:
-- its patterns such as @*.cc@ match only at the root of the build context, never
-- below @src/@. A file type that is ever added under a root must be added here in
-- the same change, together with a bump of 'sourceDigestAlgorithm' (a unit test
-- pins this list).
sourceDigestExtensions :: [String]
sourceDigestExtensions =
  [ ".hs"
  , ".hsc"
  , ".hs-boot"
  , ".c"
  , ".h"
  , ".txt"
  , ".md"
  , ".yaml"
  , ".yml"
  , ".json"
  , ".dhall"
  , ".cabal"
  , ".project"
  ]

-- | The pure core: digest an explicit file set. The input order is irrelevant.
sourceStampFromFiles :: [(FilePath, ByteString)] -> SourceStamp
sourceStampFromFiles files =
  SourceStamp
    { stampAlgorithm = sourceDigestAlgorithm
    , stampSha256 = hexDigest (SHA256.finalize (List.foldl' absorb seeded ordered))
    }
 where
  seeded = SHA256.update SHA256.init "jitml-source-digest-v1\NUL"
  ordered =
    List.sortOn
      fst
      [(normalisePath path, normaliseNewlines bytes) | (path, bytes) <- files]
  absorb context (path, bytes) =
    SHA256.updates
      context
      [ Text.Encoding.encodeUtf8 (Text.pack path)
      , "\NUL"
      , ByteString.Char8.pack (show (ByteString.length bytes))
      , "\NUL"
      , bytes
      , "\NUL"
      ]

-- | Digest the code roots under the current directory. A missing root, an
-- unreadable file, or a symbolic link is reported instead of producing a
-- digest that depends on the host.
computeSourceStamp :: IO (Either Text SourceStamp)
computeSourceStamp = computeSourceStampIn "."

-- | Digest the code roots below @root@. Paths enter the digest relative to
-- @root@, so the same tree digests identically wherever it is checked out.
computeSourceStampIn :: FilePath -> IO (Either Text SourceStamp)
computeSourceStampIn root = do
  directoryPaths <- traverse (walkRoot root) sourceDigestDirectoryRoots
  filePaths <- traverse (requireFileRoot root) sourceDigestFileRoots
  case (sequence directoryPaths, sequence filePaths) of
    (Left reason, _) -> pure (Left reason)
    (_, Left reason) -> pure (Left reason)
    (Right directories, Right files) -> do
      loaded <- traverse readOne (concat directories <> files)
      pure (sourceStampFromFiles <$> sequence loaded)
 where
  readOne path = do
    result <- tryIO (ByteString.readFile (root </> path))
    pure $ case result of
      Left exception ->
        Left ("could not read " <> Text.pack path <> ": " <> Text.pack (show exception))
      Right bytes -> Right (path, bytes)

-- | Every counted file below one directory root, as paths relative to @root@.
walkRoot :: FilePath -> FilePath -> IO (Either Text [FilePath])
walkRoot root directory = do
  exists <- doesDirectoryExist (root </> directory)
  if exists
    then walkDirectory root directory
    else pure (Left ("missing code root: " <> Text.pack directory))

walkDirectory :: FilePath -> FilePath -> IO (Either Text [FilePath])
walkDirectory root directory = do
  listed <- tryIO (listDirectory (root </> directory))
  case listed of
    Left exception ->
      pure (Left ("could not list " <> Text.pack directory <> ": " <> Text.pack (show exception)))
    Right names -> do
      results <- traverse (walkEntry root . (directory </>)) (List.sort (filter (not . hidden) names))
      pure (concat <$> sequence results)
 where
  hidden name = take 1 name == "."

walkEntry :: FilePath -> FilePath -> IO (Either Text [FilePath])
walkEntry root path = do
  linked <- tryIO (pathIsSymbolicLink (root </> path))
  case linked of
    Left exception ->
      pure (Left ("could not inspect " <> Text.pack path <> ": " <> Text.pack (show exception)))
    Right True -> pure (Left ("symbolic link under a code root: " <> Text.pack path))
    Right False -> do
      isDirectory <- doesDirectoryExist (root </> path)
      isFile <- doesFileExist (root </> path)
      if isDirectory
        then walkDirectory root path
        else
          pure
            ( Right
                [path | isFile, takeExtension path `elem` sourceDigestExtensions]
            )

requireFileRoot :: FilePath -> FilePath -> IO (Either Text FilePath)
requireFileRoot root path = do
  exists <- doesFileExist (root </> path)
  pure $
    if exists
      then Right path
      else Left ("missing code root: " <> Text.pack path)

-- | Path separators are normalised so the digest does not depend on the host.
normalisePath :: FilePath -> FilePath
normalisePath = fmap (\char -> if char == '\\' then '/' else char)

-- | Rewrite every CRLF pair to LF. A lone carriage return is content and stays.
normaliseNewlines :: ByteString -> ByteString
normaliseNewlines bytes =
  ByteString.concat (go bytes)
 where
  go remaining =
    case ByteString.breakSubstring "\r\n" remaining of
      (before, after)
        | ByteString.null after -> [before]
        | otherwise -> before : "\n" : go (ByteString.drop 2 after)

hexDigest :: ByteString -> Text
hexDigest = Text.pack . concatMap hexOctet . ByteString.unpack
 where
  hexOctet :: Word8 -> String
  hexOctet byte =
    [ intToDigit (fromIntegral byte `div` 16)
    , intToDigit (fromIntegral byte `mod` 16)
    ]

tryIO :: IO value -> IO (Either IOException value)
tryIO = try
