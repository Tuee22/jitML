{-# LANGUAGE OverloadedStrings #-}

-- Actual temporary FILE utility controls only. These ordinary inputs never
-- construct a private retained qualification, copy plan, Lane audit or ML cap.
module NativeLaneBundleFiles (nativeLaneBundleFilesTests) where

import Control.Exception
  ( AsyncException (ThreadKilled)
  , Exception
  , IOException
  , displayException
  , throw
  , try
  )
import Control.Monad (void)
import Data.Bits (xor)
import Data.ByteString qualified as BS
import Data.List (isInfixOf)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import System.Directory (createDirectory, doesFileExist, listDirectory)
import System.FilePath ((</>))
import System.IO (IOMode (WriteMode), hSetFileSize, withBinaryFile)
import System.IO.Temp (withSystemTempDirectory)
import System.Posix.Files
  ( createSymbolicLink
  , deviceID
  , fileID
  , getSymbolicLinkStatus
  , isDirectory
  , isRegularFile
  , isSymbolicLink
  )
import System.Timeout (timeout)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertEqual, assertFailure, testCase)

import JitML.Checkpoint.NativePhase.Failure qualified as Failure
import JitML.Product.ValidationRecord (sha256Hex)
import JitML.Test.NativeLaneBundle.Data qualified as Data
import JitML.Test.NativeLaneBundle.Write qualified as Files
import JitML.Test.NativeScenarioRetention qualified as Retained

nativeLaneBundleFilesTests :: TestTree
nativeLaneBundleFilesTests =
  testGroup
    "portable native bundle actual FILE utilities"
    [ temporary "fresh nested parents become real nonlink directories" $ \root -> do
        let journal = root </> "fresh" </> "nested" </> "lane.json"
        right =<< Files.prepareNativeBundleDirectory journal
        mapM_ assertDirectory [root </> "fresh", root </> "fresh" </> "nested", directory journal]
        assertBool "preparation does not fabricate the main journal" . not =<< doesFileExist journal
    , temporary "binary NUL and invalid UTF8 copy read and stream remain byte exact" $ \root -> do
        (journal, file) <- source root "binary.source" binary
        right =<< Files.copyNativeBundleFileData journal file
        actual <-
          Files.readNativeBundleObjectBytes (directory journal) (object file) (toInteger (BS.length binary))
        assertEqual "exact binary payload" binary actual
        Files.verifyNativeBundleObjectFile (directory journal) (object file) (toInteger (BS.length binary))
        assertBool "ordinary copy does not issue a main journal" . not =<< doesFileExist journal
    , temporary "actual empty bytes create a real zero byte object" $ \root -> do
        (journal, file) <- source root "empty.source" BS.empty
        right =<< Files.copyNativeBundleFileData journal file
        path <- target journal file
        status <- getSymbolicLinkStatus path
        assertBool
          "zero bytes are an existing regular object"
          (isRegularFile status && not (isSymbolicLink status))
        assertEqual "empty object reads exactly" BS.empty
          =<< Files.readNativeBundleObjectBytes (directory journal) (object file) 0
        Files.verifyNativeBundleObjectFile (directory journal) (object file) 0
    , temporary "different logical keys with identical bytes share one SHA object" $ \root -> do
        (journal, first) <- source root "first.source" binary
        (_, second) <- source root "second.source" binary
        right =<< Files.copyNativeBundleFileData journal first
        right =<< Files.copyNativeBundleFileData journal second
        basename <- right (Data.nativeBundleObjectBasename (sha256Hex binary))
        assertEqual "one exact content address and no temporary files" [basename]
          =<< listDirectory (directory journal)
        assertBool
          "logical fixture keys really differ"
          (Retained.nativePortableObjectKey first /= Retained.nativePortableObjectKey second)
    , temporary "an exact existing object is accepted without replacement" $ \root -> do
        (journal, file) <- source root "source" binary
        right =<< Files.copyNativeBundleFileData journal file
        path <- target journal file
        before <- getSymbolicLinkStatus path
        right =<< Files.copyNativeBundleFileData journal file
        after <- getSymbolicLinkStatus path
        assertEqual
          "existing physical object is not replaced"
          (deviceID before, fileID before)
          (deviceID after, fileID after)
        assertEqual "existing bytes unchanged" binary =<< BS.readFile path
    , temporary "same size corrupt existing destination refuses and remains unchanged" $ \root -> do
        (journal, file) <- source root "source" binary
        right =<< Files.prepareNativeBundleDirectory journal
        path <- target journal file
        let corrupt = BS.map (`xor` 1) binary
        BS.writeFile path corrupt
        refuses "destination bytes differ" =<< Files.copyNativeBundleFileData journal file
        assertEqual "create-only conflict is not overwritten" corrupt =<< BS.readFile path
    , temporary "truncated existing destination refuses without repair" $ \root -> do
        (journal, file) <- source root "source" binary
        right =<< Files.prepareNativeBundleDirectory journal
        path <- target journal file
        let truncated = BS.take (BS.length binary - 1) binary
        BS.writeFile path truncated
        refuses "destination count differs" =<< Files.copyNativeBundleFileData journal file
        assertEqual "truncation retained rather than overwritten" truncated =<< BS.readFile path
    , temporary "overlong existing destination refuses without repair" $ \root -> do
        (journal, file) <- source root "source" binary
        right =<< Files.prepareNativeBundleDirectory journal
        path <- target journal file
        let overlong = binary <> BS.singleton 7
        BS.writeFile path overlong
        refuses "destination count differs" =<< Files.copyNativeBundleFileData journal file
        assertEqual "overlong conflict remains exact" overlong =<< BS.readFile path
    , temporary "wrong source SHA refuses without installing an object" $ \root -> do
        (journal, file) <- source root "source" binary
        refuses "source actual bytes differ"
          =<< Files.copyNativeBundleFileData
            journal
            (file {Retained.nativePortableObjectSha256 = Text.replicate 64 "0"})
        assertEqual "no failed object or temporary is installed" [] =<< listDirectory (directory journal)
    , temporary "truncated source refuses its original count" $ \root -> do
        (journal, file) <- source root "source" binary
        BS.writeFile (Retained.nativePortableOriginalPath file) (BS.take 1 binary)
        refuses "source file size changed" =<< Files.copyNativeBundleFileData journal file
        assertEqual "no object after source truncation" [] =<< listDirectory (directory journal)
    , temporary "overlong source refuses its original count" $ \root -> do
        (journal, file) <- source root "source" binary
        BS.writeFile (Retained.nativePortableOriginalPath file) (binary <> BS.singleton 3)
        refuses "source file size changed" =<< Files.copyNativeBundleFileData journal file
        assertEqual "no object after source growth" [] =<< listDirectory (directory journal)
    , temporary "source role cap refuses before copying existing bytes" $ \root -> do
        (journal, file) <- source root "source" binary
        refuses "source count exceeds its original role cap"
          =<< Files.copyNativeBundleFileData
            journal
            (file {Retained.nativePortableObjectMaximumBytes = toInteger (BS.length binary) - 1})
        assertEqual "no object after cap refusal" [] =<< listDirectory (directory journal)
    , temporary "strict read refuses same size corruption by SHA" $ \root -> do
        (journal, file) <- copied root
        path <- target journal file
        BS.writeFile path (BS.map (`xor` 1) binary)
        ioRefuses
          "actual count/SHA differs"
          (Files.readNativeBundleObjectBytes (directory journal) (object file) 4096)
    , temporary "strict read refuses truncated physical size" $ \root -> do
        (journal, file) <- copied root
        path <- target journal file
        BS.writeFile path (BS.take 1 binary)
        ioRefuses "size differs" (Files.readNativeBundleObjectBytes (directory journal) (object file) 4096)
    , temporary "stream verification refuses an extra physical byte" $ \root -> do
        (journal, file) <- copied root
        path <- target journal file
        BS.writeFile path (binary <> BS.singleton 0)
        ioRefuses "size differs" (Files.verifyNativeBundleObjectFile (directory journal) (object file) 4096)
    , temporary "stream verification independently refuses same size wrong SHA" $ \root -> do
        (journal, file) <- copied root
        path <- target journal file
        BS.writeFile path (BS.reverse binary)
        ioRefuses
          "actual count/SHA differs"
          (Files.verifyNativeBundleObjectFile (directory journal) (object file) 4096)
    , temporary "read and stream role caps refuse before nonexistent path access" $ \root -> do
        let missing = root </> "absent.qualifications"
            claimed = Data.NativeBundleObjectData "ordinary/missing" (sha256Hex binary) 2
        ioRefuses "role or Int allocation cap" (Files.readNativeBundleObjectBytes missing claimed 1)
        ioRefuses "role cap" (Files.verifyNativeBundleObjectFile missing claimed 1)
    , temporary "strict read refuses Word64 maximum before Int conversion or file access" $ \root -> do
        let claimed = Data.NativeBundleObjectData "ordinary/huge" (sha256Hex binary) maxBound
        ioRefuses
          "Int allocation cap"
          (Files.readNativeBundleObjectBytes (root </> "absent") claimed (toInteger (maxBound :: Word64)))
    , temporary "sparse oversized physical object refuses within the small claimed role" $ \root -> do
        (journal, file) <- copied root
        path <- target journal file
        withBinaryFile path WriteMode (\handle -> hSetFileSize handle (16 * 1024 * 1024))
        bounded "small claimed-size refusal terminates" $ do
          ioRefuses "size differs" (Files.readNativeBundleObjectBytes (directory journal) (object file) 4096)
          ioRefuses "size differs" (Files.verifyNativeBundleObjectFile (directory journal) (object file) 4096)
    , temporary "malformed SHA cannot enter a destination or reader path" $ \root -> do
        (journal, file) <- source root "source" binary
        mapM_
          ( \sha -> do
              refuses "filename SHA is not canonical"
                =<< Files.copyNativeBundleFileData
                  journal
                  (file {Retained.nativePortableObjectSha256 = sha})
              ioRefuses
                "filename SHA is not canonical"
                ( Files.readNativeBundleObjectBytes
                    (directory journal)
                    ((object file) {Data.nativeBundleObjectSha256 = sha})
                    4096
                )
          )
          ["../escape", Text.replicate 64 "A", Text.replicate 63 "0", Text.replicate 64 "g"]
    , temporary "source final symlink refuses instead of following exact bytes" $ \root -> do
        (journal, file) <- source root "source" binary
        let linked = root </> "source-link"
        createSymbolicLink (Retained.nativePortableOriginalPath file) linked
        refuses "regular nonlink"
          =<< Files.copyNativeBundleFileData
            journal
            (file {Retained.nativePortableOriginalPath = linked})
    , temporary "source directory symlink refuses before following an exact payload" $ \root -> do
        let actual = root </> "actual"
            alias = root </> "alias"
        createDirectory actual
        BS.writeFile (actual </> "source") binary
        createSymbolicLink actual alias
        let file = ordinaryFile (alias </> "source") "ordinary/source" binary
        refuses "nonlink directory" =<< Files.copyNativeBundleFileData (root </> "journal") file
    , temporary "destination final symlink refuses without changing its target" $ \root -> do
        (journal, file) <- source root "source" binary
        right =<< Files.prepareNativeBundleDirectory journal
        path <- target journal file
        createSymbolicLink (Retained.nativePortableOriginalPath file) path
        refuses "regular nonlink" =<< Files.copyNativeBundleFileData journal file
        ioRefuses
          "regular nonlink"
          (Files.readNativeBundleObjectBytes (directory journal) (object file) 4096)
        assertEqual "symlink target remains exact" binary
          =<< BS.readFile (Retained.nativePortableOriginalPath file)
    , temporary "dangling destination symlink refuses rather than becoming absent" $ \root -> do
        (journal, file) <- source root "source" binary
        right =<< Files.prepareNativeBundleDirectory journal
        path <- target journal file
        createSymbolicLink (root </> "nonexistent") path
        refuses "regular nonlink" =<< Files.copyNativeBundleFileData journal file
        status <- getSymbolicLinkStatus path
        assertBool "dangling symlink is preserved" (isSymbolicLink status)
    , temporary "destination parent symlink refuses without creating objects in its target" $ \root -> do
        let actual = root </> "actual"
            alias = root </> "alias"
        createDirectory actual
        createSymbolicLink actual alias
        refuses "nonlink directory" =<< Files.prepareNativeBundleDirectory (alias </> "journal")
        assertEqual "nothing created through alias" [] =<< listDirectory actual
    , temporary "dangling parent symlink refuses without creating its missing target" $ \root -> do
        let alias = root </> "alias"
            absent = root </> "absent"
        createSymbolicLink absent alias
        refuses "nonlink directory" =<< Files.prepareNativeBundleDirectory (alias </> "journal")
        status <- getSymbolicLinkStatus alias
        assertBool "dangling prefix remains a symlink" (isSymbolicLink status)
    , temporary "directory at a SHA destination cannot represent an object" $ \root -> do
        (journal, file) <- source root "source" binary
        right =<< Files.prepareNativeBundleDirectory journal
        path <- target journal file
        createDirectory path
        refuses "regular nonlink" =<< Files.copyNativeBundleFileData journal file
        ioRefuses
          "regular nonlink"
          (Files.verifyNativeBundleObjectFile (directory journal) (object file) 4096)
    , testCase "hostile path spine is bounded before its poisoned suffix" $ do
        let path = replicate 4097 'x' <> error "path suffix must remain unforced"
        refuses "character cap" =<< Files.prepareNativeBundleDirectory path
    , testCase "synchronous ordinary file poison preserves complete Unicode diagnostic" $ do
        result <- Files.copyNativeBundleFileData "unused" (throw UnicodeFault)
        assertEqual
          "exact complete diagnostic"
          (Left (Failure.CompleteNativeDiagnostic unicodeMessage))
          result
    , testCase "endless exception rendering is bounded without a complete prefix" $ bounded "endless renderer terminates" $ do
        result <- Files.copyNativeBundleFileData "unused" (throw EndlessFault)
        case result of
          Left (Failure.OversizeNativeDiagnostic _) -> pure ()
          other -> assertFailure ("expected explicit oversize diagnostic, got " <> show other)
    , testCase "ordinary file input asynchronous cancellation propagates" $
        asynchronous (Files.copyNativeBundleFileData "unused" (throw ThreadKilled))
    , testCase "exception renderer asynchronous cancellation propagates" $
        asynchronous (Files.copyNativeBundleFileData "unused" (throw RendererAsyncFault))
    ]

temporary :: String -> (FilePath -> IO ()) -> TestTree
temporary title action = testCase title (withSystemTempDirectory "jitml-native-bundle-files-" action)

binary :: BS.ByteString
binary = BS.pack [0, 255, 254, 128, 10, 13, 1, 127, 192, 175, 0, 42]

-- All fixture records remain public ordinary DATA, not a retained plan.
source
  :: FilePath -> FilePath -> BS.ByteString -> IO (FilePath, Retained.NativeScenarioPortableFileData)
source root leaf bytes = do
  let path = root </> leaf
  BS.writeFile path bytes
  pure (root </> "journal", ordinaryFile path ("ordinary/" <> Text.pack leaf) bytes)

ordinaryFile :: FilePath -> Text -> BS.ByteString -> Retained.NativeScenarioPortableFileData
ordinaryFile path key bytes =
  Retained.NativeScenarioPortableFileData
    key
    path
    (fromIntegral (BS.length bytes))
    (sha256Hex bytes)
    (toInteger (BS.length bytes))

object :: Retained.NativeScenarioPortableFileData -> Data.NativeBundleObjectData
object file =
  Data.NativeBundleObjectData
    (Retained.nativePortableObjectKey file)
    (Retained.nativePortableObjectSha256 file)
    (Retained.nativePortableObjectBytes file)

directory :: FilePath -> FilePath
directory journal = journal <> ".qualifications"

target :: FilePath -> Retained.NativeScenarioPortableFileData -> IO FilePath
target journal file =
  (directory journal </>)
    <$> right
      (Data.nativeBundleObjectBasename (Retained.nativePortableObjectSha256 file))

copied :: FilePath -> IO (FilePath, Retained.NativeScenarioPortableFileData)
copied root = do
  pair@(journal, file) <- source root "source" binary
  right =<< Files.copyNativeBundleFileData journal file
  pure pair

assertDirectory :: FilePath -> IO ()
assertDirectory path = do
  status <- getSymbolicLinkStatus path
  assertBool
    "actual directory is not a symbolic link"
    (isDirectory status && not (isSymbolicLink status))

right :: (Show e) => Either e a -> IO a
right value = case value of
  Right actual -> pure actual
  Left failure -> assertFailure (show failure) >> fail "unreachable"

refuses :: String -> Either Failure.NativeDiagnosticData a -> IO ()
refuses fragment value = case value of
  Left (Failure.CompleteNativeDiagnostic detail) ->
    assertBool
      ("diagnostic must identify the intended refusal: " <> Text.unpack detail)
      (Text.pack fragment `Text.isInfixOf` detail)
  Left failure -> assertFailure ("expected complete intended refusal, got " <> show failure)
  Right _ -> assertFailure "invalid ordinary file input was accepted"

ioRefuses :: String -> IO a -> IO ()
ioRefuses fragment action = do
  attempted <- try (void action) :: IO (Either IOException ())
  case attempted of
    Left exception ->
      assertBool
        ("unexpected IO failure: " <> displayException exception)
        (fragment `isInfixOf` displayException exception)
    Right () -> assertFailure "invalid physical object was accepted"

bounded :: String -> IO () -> IO ()
bounded label action = do
  result <- timeout 5000000 action
  case result of
    Just () -> pure ()
    Nothing -> assertFailure label

asynchronous :: IO a -> IO ()
asynchronous action = do
  attempted <- try (void action) :: IO (Either AsyncException ())
  case attempted of
    Left ThreadKilled -> pure ()
    Left other -> assertFailure ("unexpected asynchronous exception: " <> show other)
    Right () -> assertFailure "asynchronous cancellation was swallowed"

data FixtureFault = UnicodeFault | EndlessFault | RendererAsyncFault
instance Show FixtureFault where
  show UnicodeFault = Text.unpack unicodeMessage
  show EndlessFault = repeat 'x'
  show RendererAsyncFault = throw ThreadKilled
instance Exception FixtureFault

unicodeMessage :: Text
unicodeMessage = "ordinary file input: λ雪\NULexact\nretained"
