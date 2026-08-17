{-# LANGUAGE OverloadedStrings #-}

-- | The two pure primitives every reflected-schema surface shares: read a Dhall
-- /type/ back off a live 'Dhall.Decoder', and canonicalise a checked-in schema
-- file through the same pretty-printer so a parity assertion between the two is
-- a plain text comparison.
--
-- Both the daemon config surfaces ('JitML.Service.DhallSchema') and the
-- numerical ML DSL ('JitML.Numerics.LayerDhall') reflect their schemas this
-- way, so the primitives live below both rather than being restated in each.
module JitML.Dhall.Reflect
  ( reflectedSchemaText
  , canonicalDhallType
  )
where

import Data.Either.Validation (Validation (..))
import Data.Text (Text)
import Data.Text qualified as Text
import Dhall qualified
import Dhall.Core (Expr, Import)
import Dhall.Core qualified as Core
import Dhall.Parser qualified as Parser
import Dhall.Src (Src)

-- | Pretty-print the Dhall /type/ a decoder accepts. Because the type is read
-- back off the live decoder, it is structurally identical to what the loader
-- will accept — the schema cannot drift from the code.
reflectedSchemaText :: Dhall.Decoder a -> Text
reflectedSchemaText decoder =
  case Dhall.expected decoder of
    Success expr -> Core.pretty expr
    Failure errs -> "-- unable to reflect schema: " <> Text.pack (show errs)

-- | Canonicalise a checked-in Dhall /type/ file through the same pretty-printer
-- the reflected schema uses, with source notes stripped, so a parity assertion
-- between the file and 'reflectedSchemaText' is a plain text comparison.
-- Schema files reference no imports, so parsing is pure.
canonicalDhallType :: Text -> Either Text Text
canonicalDhallType src =
  case Parser.exprFromText "<dhall-schema>" src of
    Left err -> Left (Text.pack (show err))
    Right expr -> Right (Core.pretty (Core.denote expr :: Expr Src Import))
