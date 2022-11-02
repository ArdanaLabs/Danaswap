module Main (main) where

import Control.Monad (unless)
import DanaSwap (configScriptCbor, liqudityTokenCbor, nftCbor, poolAdrValidatorCbor, poolIdTokenMPCbor, trivialCbor)
import Data.Default (Default (def))
import Plutarch (Config (tracingMode), TracingMode (..))
import System.Directory (doesDirectoryExist)
import System.Environment (getArgs)
import System.Exit (die)
import Utils (Cbor (..), toPureScript)

{- | Main takes a directory as a comand line argument
  and creates a file CBOR.purs in that directory
  which will provide variables as configured in
  the cbors constant
-}

-- TODO should this be a utility? or should we just remove the helloworld one eventually
main :: IO ()
main = do
  getArgs >>= \case
    [out] -> do
      exists <- doesDirectoryExist out
      unless exists $ die $ "directory: " <> out <> " does not exist"
      writeFile (out ++ "/CBOR.purs")
        . ( "--this file was automatically generated by the onchain code\n"
              <>
          )
        =<< toPureScript config cbors
    _ -> die "usage: cabal run hello-world <file_path>"

config :: Config
config = def {tracingMode = DoTracing}

cbors :: [Cbor]
cbors =
  [ Cbor "trivial" trivialCbor
  , Cbor "nft" nftCbor
  , Cbor "configScript" $ const $ pure configScriptCbor
  , Cbor "liqudityTokenMintingPolicy" liqudityTokenCbor
  , Cbor "poolIdTokenMintingPolicy" poolIdTokenMPCbor
  , Cbor "poolAdrValidator" poolAdrValidatorCbor
  ]
