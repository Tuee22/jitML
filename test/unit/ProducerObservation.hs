{-# LANGUAGE OverloadedStrings #-}

module ProducerObservation (producerObservationTests) where

import Control.Exception (IOException, bracket, try)
import Control.Monad (forM_)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified as BS
import Data.Char (intToDigit)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Version (showVersion)
import System.Directory (createDirectory)
import System.Environment (getExecutablePath)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Info qualified as Info
import System.Posix.Files (createSymbolicLink, fileMode, getFileStatus, setFileMode)
import System.Posix.Process (getParentProcessID, getProcessID)
import System.Posix.Unistd qualified as Posix
import Test.Tasty (TestTree, testGroup, withResource)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Execution.ProducerObservation qualified as Observation
import JitML.Product.SourceDigest qualified as Source

-- These controls observe the test process/file and explicitly synthetic source
-- fixtures. They do not claim the fixture built the process, provider execution,
-- actual ARS origin, physical Store admission or parent source authentication.
producerObservationTests :: TestTree
producerObservationTests =
  withResource (observe Observation.NoSourceObservation) (const (pure ())) $ \actual ->
    testGroup
      "actual producer process file and optional source observations"
      [ testCase "actual executable FILE identity equals an independent read of getExecutablePath" $ do
          observed <- actual
          path <- getExecutablePath
          bytes <- BS.readFile path
          Observation.producerExecutableFilePath observed @?= path
          Observation.producerExecutableFileSha256 observed @?= independentSha bytes
          Observation.producerExecutableFileByteCount observed @?= fromIntegral (BS.length bytes)
      , testCase "actual process and parent ids equal POSIX observations including possible parent zero" $ do
          observed <- actual
          pid <- getProcessID
          ppid <- getParentProcessID
          Observation.producerProcessId observed @?= toInteger pid
          Observation.producerParentProcessId observed @?= toInteger ppid
          assertBool "actual process id must be positive" (Observation.producerProcessId observed > 0)
          assertBool "parent id must allow zero" (Observation.producerParentProcessId observed >= 0)
      , testCase "actual kernel OS machine and release equal POSIX uname without hostname claims" $ do
          observed <- actual
          kernel <- Posix.getSystemID
          Observation.producerKernelOperatingSystem observed @?= Text.pack (Posix.systemName kernel)
          Observation.producerKernelMachine observed @?= Text.pack (Posix.machine kernel)
          Observation.producerKernelRelease observed @?= Text.pack (Posix.release kernel)
      , testCase "build OS architecture and compiler are retained separately from kernel observations" $ do
          observed <- actual
          Observation.producerBuildOperatingSystem observed @?= Text.pack Info.os
          Observation.producerBuildArchitecture observed @?= Text.pack Info.arch
          Observation.producerBuildCompiler observed @?= Text.pack Info.compilerName
          Observation.producerBuildCompilerVersion observed @?= Text.pack (showVersion Info.compilerVersion)
      , testCase "NoSourceObservation is explicit absence with no caller or inferred source hash" $ do
          observed <- actual
          Observation.producerObservedSource observed @?= Nothing
          Observation.recordedObservedSource (Observation.recordedProducerObservation observed) @?= Nothing
      , testCase "an explicit actual source fixture agrees with the independent exact file-set stamp" $
          withSourceFixture $ \root files -> do
            observed <- observe (Observation.ObserveSourceAt root)
            let expected = Source.sourceStampFromFiles files
            Observation.producerObservedSource observed @?= Just (root, expected)
            independent <- Source.computeSourceStampIn root >>= expectRight
            independent @?= expected
      , testCase "a missing source root returns the actual typed source failure and requested path" $
          withSystemTempDirectory "jitml-observation-missing" $ \root -> do
            let missing = root </> "missing"
            expected <- sourceFailure missing
            result <- Observation.observeProducerProcess (Observation.ObserveSourceAt missing)
            assertSourceFailure missing expected result
      , testCase "a non-directory source root preserves SourceDigest rejection without fallback" $
          withSystemTempDirectory "jitml-observation-not-directory" $ \root -> do
            let fileRoot = root </> "regular-file"
            BS.writeFile fileRoot "not a repository"
            expected <- sourceFailure fileRoot
            result <- Observation.observeProducerProcess (Observation.ObserveSourceAt fileRoot)
            assertSourceFailure fileRoot expected result
      , testCase "a symlink under a code root is rejected by the unchanged actual SourceDigest semantics" $
          withSourceFixture $ \root _ -> do
            let sourcePath = root </> "src" </> "Linked.hs"
                target = root </> "outside.txt"
            BS.writeFile target "not an accepted external source"
            createSymbolicLink target sourcePath
            expected <- sourceFailure root
            assertBool
              "actual source rejection should name the symbolic link"
              ("symbolic" `Text.isInfixOf` expected || "symlink" `Text.isInfixOf` expected)
            result <- Observation.observeProducerProcess (Observation.ObserveSourceAt root)
            assertSourceFailure root expected result
      , testCase
          "source permission outcome matches actual independent IO rather than assuming non-root denial"
          $ withSourceFixture
          $ \root files -> do
            let sourcePath = root </> "src" </> "Observed.hs"
            status <- getFileStatus sourcePath
            bracket
              (setFileMode sourcePath 0)
              (const (setFileMode sourcePath (fileMode status)))
              $ \() -> do
                independent <- try (BS.readFile sourcePath) :: IO (Either IOException BS.ByteString)
                result <- Observation.observeProducerProcess (Observation.ObserveSourceAt root)
                case independent of
                  Left _ -> sourceFailure root >>= \expected -> assertSourceFailure root expected result
                  Right bytes -> do
                    bytes @?= fixtureSource
                    observed <- expectRight result
                    Observation.producerObservedSource observed @?= Just (root, Source.sourceStampFromFiles files)
      , testCase "two genuine before-after observations compare every exact observed field" $ do
          before <- actual
          after <- observe Observation.NoSourceObservation
          Observation.compareProducerProcessObservations before after @?= Right ()
      , testCase "recorded-only field mutations report each exact mismatch without minting an observation" $ do
          observed <- actual
          let recorded = Observation.recordedProducerObservation observed
              source = Source.sourceStampFromFiles [("fixture.hs", "raw comparison data")]
              mutations =
                [
                  ( Observation.ExecutableFilePath
                  , recorded {Observation.recordedExecutableFilePath = "different-path"}
                  )
                ,
                  ( Observation.ExecutableFileSha256
                  , recorded {Observation.recordedExecutableFileSha256 = "different-recorded-sha"}
                  )
                ,
                  ( Observation.ExecutableFileByteCount
                  , recorded
                      { Observation.recordedExecutableFileByteCount =
                          Observation.recordedExecutableFileByteCount recorded + 1
                      }
                  )
                ,
                  ( Observation.ProcessId
                  , recorded {Observation.recordedProcessId = Observation.recordedProcessId recorded + 1}
                  )
                ,
                  ( Observation.ParentProcessId
                  , recorded {Observation.recordedParentProcessId = Observation.recordedParentProcessId recorded + 1}
                  )
                ,
                  ( Observation.KernelOperatingSystem
                  , recorded {Observation.recordedKernelOperatingSystem = "different-kernel"}
                  )
                , (Observation.KernelMachine, recorded {Observation.recordedKernelMachine = "different-machine"})
                , (Observation.KernelRelease, recorded {Observation.recordedKernelRelease = "different-release"})
                ,
                  ( Observation.BuildOperatingSystem
                  , recorded {Observation.recordedBuildOperatingSystem = "different-build-os"}
                  )
                ,
                  ( Observation.BuildArchitecture
                  , recorded {Observation.recordedBuildArchitecture = "different-build-arch"}
                  )
                , (Observation.BuildCompiler, recorded {Observation.recordedBuildCompiler = "different-compiler"})
                ,
                  ( Observation.BuildCompilerVersion
                  , recorded {Observation.recordedBuildCompilerVersion = "different-compiler-version"}
                  )
                ,
                  ( Observation.SourceObservation
                  , recorded {Observation.recordedObservedSource = Just ("fixture-only", source)}
                  )
                ]
          Observation.compareRecordedProducerObservationData recorded recorded @?= Right ()
          forM_ mutations $ \(field, changed) ->
            Observation.compareRecordedProducerObservationData recorded changed
              @?= Left (Observation.ProducerObservationMismatch [field])
          let zeroParent = recorded {Observation.recordedParentProcessId = 0}
          Observation.compareRecordedProducerObservationData zeroParent zeroParent @?= Right ()
          let present = recorded {Observation.recordedObservedSource = Just ("fixture-only", source)}
          forM_
            [ present {Observation.recordedObservedSource = Just ("other-path", source)}
            , present
                { Observation.recordedObservedSource =
                    Just ("fixture-only", source {Source.stampAlgorithm = Source.stampAlgorithm source + 1})
                }
            , present
                { Observation.recordedObservedSource =
                    Just ("fixture-only", source {Source.stampSha256 = "other-recorded-sha"})
                }
            ]
            $ \changed ->
              Observation.compareRecordedProducerObservationData present changed
                @?= Left (Observation.ProducerObservationMismatch [Observation.SourceObservation])
          let twoChanges =
                recorded
                  { Observation.recordedExecutableFilePath = "different-path"
                  , Observation.recordedProcessId = Observation.recordedProcessId recorded + 1
                  }
          Observation.compareRecordedProducerObservationData recorded twoChanges
            @?= Left
              (Observation.ProducerObservationMismatch [Observation.ExecutableFilePath, Observation.ProcessId])
      ]

observe :: Observation.SourceObservationMode -> IO Observation.ObservedProducerProcess
observe mode = Observation.observeProducerProcess mode >>= expectRight

expectRight :: (Show err) => Either err value -> IO value
expectRight = either (assertFailure . show) pure

sourceFailure :: FilePath -> IO Text
sourceFailure root = do
  result <- Source.computeSourceStampIn root
  case result of
    Left detail -> pure detail
    Right _ -> assertFailure "negative source fixture unexpectedly became a repository"

assertSourceFailure
  :: FilePath
  -> Text
  -> Either Observation.ProducerObservationError Observation.ObservedProducerProcess
  -> Assertion
assertSourceFailure root expected result = case result of
  Left (Observation.ProducerSourceObservationFailure actualRoot actualDetail) -> do
    actualRoot @?= root
    actualDetail @?= expected
    assertBool "source rejection lost its actual detail" (not (Text.null actualDetail))
  Left other -> assertFailure ("wrong source rejection boundary: " <> show other)
  Right _ -> assertFailure "source observation unexpectedly succeeded"

fixtureSource :: BS.ByteString
fixtureSource = "module Observed where\nvalue :: Int\nvalue = 1\n"

withSourceFixture :: (FilePath -> [(FilePath, BS.ByteString)] -> IO value) -> IO value
withSourceFixture use = withSystemTempDirectory "jitml-source-observation" $ \root -> do
  forM_ ["app", "gen", "src", "test"] (createDirectory . (root </>))
  let files =
        [ ("src/Observed.hs", fixtureSource)
        , ("cabal.project", "packages: .\n")
        , ("jitml.cabal", "cabal-version: 3.0\nname: observation-fixture\n")
        ]
  forM_ files $ \(path, bytes) -> BS.writeFile (root </> path) bytes
  use root files

independentSha :: BS.ByteString -> Text
independentSha = Text.pack . concatMap byteHex . BS.unpack . SHA256.hash
 where
  byteHex byte = [intToDigit (fromIntegral byte `div` 16), intToDigit (fromIntegral byte `mod` 16)]
