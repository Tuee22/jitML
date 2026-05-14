{-# LANGUAGE OverloadedStrings #-}

module JitML.CLI.Output
    ( exitWithError
    , exitWithErrorIO
    , renderError
    , writeJsonValue
    , writeLazyByteString
    , writeLine
    , writeText
    )
where

import Control.Monad.IO.Class (liftIO)
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy (ByteString)
import Data.ByteString.Lazy.Char8 qualified as ByteString
import Data.Text (Text)
import Data.Text.IO qualified as Text.IO
import System.IO (stderr)
import System.Exit (exitWith)

import JitML.AppError.AppError (AppError, exitCodeFor)
import JitML.AppError.Render qualified as AppError
import JitML.Env.Env (App)

renderError :: AppError -> Text
renderError = AppError.renderError

writeText :: Text -> App ()
writeText = liftIO . Text.IO.putStr

writeLine :: Text -> App ()
writeLine = liftIO . Text.IO.putStrLn

writeLazyByteString :: ByteString -> App ()
writeLazyByteString = liftIO . ByteString.putStr

writeJsonValue :: Aeson.Value -> App ()
writeJsonValue = writeLazyByteString . Aeson.encode

exitWithError :: AppError -> App a
exitWithError = liftIO . exitWithErrorIO

exitWithErrorIO :: AppError -> IO a
exitWithErrorIO err = do
    Text.IO.hPutStr stderr (renderError err)
    exitWith (exitCodeFor err)
