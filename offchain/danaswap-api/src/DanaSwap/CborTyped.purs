module DanaSwap.CborTyped
  ( poolAddressValidator
  , poolIdTokenMintingPolicy
  , liqudityTokenMintingPolicy
  , simpleNft
  , configAddressValidator
  ) where

import Contract.Prelude

import CBOR as CBOR
import Contract.Log (logDebug')
import Contract.Monad (Contract, liftContractM)
import Contract.PlutusData (toData)
import Contract.Prim.ByteArray (hexToByteArray)
import Contract.Scripts (MintingPolicy(..), Validator(..), applyArgsM)
import Contract.Transaction (TransactionInput, plutusV2Script)
import Contract.Value (CurrencySymbol)

{- This module should be the only place where CBOR is imported
- all of its exports should handle all of the validator's parameters
- this way there is only one module that needs to be checked
- for type errors between on and off chain code
-}

-- | Placeholder
poolAddressValidator :: CurrencySymbol -> CurrencySymbol -> Contract () Validator
poolAddressValidator poolIdToken liquidityToken = do
  logDebug' "creating pool address validator"
  logDebug' $ "pool id:" <> show poolIdToken
  logDebug' $ "liquidity token:" <> show liquidityToken
  decodeCbor CBOR.trivial

-- | Placeholder
poolIdTokenMintingPolicy :: CurrencySymbol -> Contract () MintingPolicy
poolIdTokenMintingPolicy configUtxoNftCS = do
  logDebug' "creating pool id token minting policy"
  logDebug' $ "nft cs:" <> show configUtxoNftCS
  decodeCborMp CBOR.trivial

-- | MintingPolicy for the pool liquidity tokens parametized by the
-- currency symbol of the poolId tokens
liqudityTokenMintingPolicy :: CurrencySymbol -> Contract () MintingPolicy
liqudityTokenMintingPolicy poolId = do
  logDebug' "creating liquidity token minting policy"
  logDebug' $ "pool id:" <> show poolId
  raw <- decodeCborMp CBOR.liqudityTokenMintingPolicy
  applyArgsM raw [ toData poolId ]
    >>= liftContractM "failed to apply args"

configAddressValidator :: Contract () Validator
configAddressValidator = decodeCbor CBOR.configScript

-- | Simple NFT minting policy parametized by a transaction input
simpleNft :: TransactionInput -> Contract () MintingPolicy
simpleNft ref = do
  raw <- decodeCborMp CBOR.nft
  applyArgsM raw [ toData ref ]
    >>= liftContractM "failed to apply args"

-- These helpers should not be exported

decodeCbor :: String -> Contract () Validator
decodeCbor cborHex = liftContractM "failed to decode cbor"
  $ Validator
  <<< plutusV2Script
  <$> hexToByteArray cborHex

decodeCborMp :: String -> Contract () MintingPolicy
decodeCborMp cborHex = liftContractM "failed to decode cbor"
  $ MintingPolicy
  <<< plutusV2Script
  <$> hexToByteArray cborHex
