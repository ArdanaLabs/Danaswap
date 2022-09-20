module Test.HelloWorld.Discovery.Api
  ( spec
  , localOnlySpec
  ) where

import Contract.Prelude

import CBOR as CBOR
import Contract.Address (getWalletAddress, ownPaymentPubKeyHash, scriptHashAddress)
import Contract.Hashing (datumHash)
import Contract.Log (logInfo')
import Contract.Monad (Contract, liftContractM)
import Contract.PlutusData (Datum(..), Redeemer(Redeemer), fromData, toData)
import Contract.ScriptLookups as Lookups
import Contract.Scripts (mintingPolicyHash, validatorHash)
import Contract.Test.Plutip (runContractInEnv, withPlutipContractEnv)
import Contract.Transaction (TransactionInput(..))
import Contract.TxConstraints (TxConstraints)
import Contract.TxConstraints as Constraints
import Contract.Utxos (getUtxo, getWalletBalance)
import Contract.Value (Value, adaToken, mkTokenName, mpsSymbol, scriptCurrencySymbol)
import Contract.Wallet (withKeyWallet)
import Data.BigInt as BigInt
import Data.Map as Map
import Data.Time.Duration (Minutes(..))
import Effect.Exception (throw)
import HelloWorld.Api (enoughForFees)
import HelloWorld.Discovery.Api (closeVault, getAllVaults, getMyVaults, getVaultById, incrementVault, incrementVault', makeNftPolicy, mintNft, openVault, openVault', protocolInit, seedTx)
import HelloWorld.Discovery.Types (HelloAction(..), HelloRedeemer(..), NftRedeemer(..), Vault(..), Protocol)
import Plutus.Types.Address (Address(..))
import Plutus.Types.Credential (Credential(..))
import Plutus.Types.Value as Value
import Test.HelloWorld.EnvRunner (EnvRunner, defaultWallet, plutipConfig, runEnvSpec)
import Test.Spec (Spec, describe, it, itOnly)
import Test.Spec.Assertions (expectError, shouldEqual, shouldReturn)
import Types.PlutusData (PlutusData)
import Util (buildBalanceSignAndSubmitTx, decodeCbor, getDatum, getUtxos, maxWait, waitForTx, withOurLogger)

spec :: EnvRunner -> Spec Unit
spec = runEnvSpec do
  describe "HelloWorld.Discovery.Api" do

    describe "misc" do

      when false $ it "script with serialise works" $ useRunnerSimple do
        val <- liftContractM "failed to decode" $ decodeCbor CBOR.trivialSerialise
        let vhash = validatorHash val
        tx1 <- buildBalanceSignAndSubmitTx
          mempty
          (Constraints.mustPayToScript vhash (Datum $ unit # toData) Constraints.DatumInline enoughForFees)
        tx1' <- liftContractM "time out" =<< waitForTx maxWait (scriptHashAddress vhash) tx1
        utxos <- getUtxos (scriptHashAddress vhash)
        buildBalanceSignAndSubmitTx
          (Lookups.validator val <> Lookups.unspentOutputs utxos)
          (Constraints.mustSpendScriptOutput tx1' (Redeemer $ unit # toData))

    describe "nft" do

      it "mint runs" $ useRunnerSimple do
        mintNft

      it "double minting fails on second mint" $ useRunnerSimple do
        txOut <- seedTx
        adr <- liftContractM "no wallet" =<< getWalletAddress
        utxos <- getUtxos adr
        nftPolicy <- makeNftPolicy txOut
        cs <- liftContractM "failed to hash MintingPolicy into CurrencySymbol" $ scriptCurrencySymbol nftPolicy
        let
          lookups :: Lookups.ScriptLookups PlutusData
          lookups = Lookups.mintingPolicy nftPolicy
            <> Lookups.unspentOutputs utxos

          constraints :: TxConstraints Unit Unit
          constraints = Constraints.mustMintValue (Value.singleton cs adaToken (BigInt.fromInt 1))
            <> Constraints.mustSpendPubKeyOutput txOut
        txId <- buildBalanceSignAndSubmitTx lookups constraints
        _ <- waitForTx maxWait adr txId
        expectError $ buildBalanceSignAndSubmitTx lookups constraints

      it "seedTx is spent after mint" $ useRunnerSimple do
        txOut <- seedTx
        adr <- liftContractM "no wallet" =<< getWalletAddress
        utxos <- getUtxos adr
        nftPolicy <- makeNftPolicy txOut
        cs <- liftContractM "failed to hash MintingPolicy into CurrencySymbol" $ scriptCurrencySymbol nftPolicy
        logInfo' $ "NFT cs: " <> show cs
        let
          lookups :: Lookups.ScriptLookups PlutusData
          lookups = Lookups.mintingPolicy nftPolicy
            <> Lookups.unspentOutputs utxos

          constraints :: TxConstraints Unit Unit
          constraints = Constraints.mustMintValue (Value.singleton cs adaToken (BigInt.fromInt 1))
            <> Constraints.mustSpendPubKeyOutput txOut
        txId <- buildBalanceSignAndSubmitTx lookups constraints
        _ <- waitForTx maxWait adr txId
        getUtxo txOut >>= case _ of
          Nothing -> pure unit
          Just _ -> liftEffect $ throw "seed tx still existed"

      it "wallet has nft after mint" $ useRunnerSimple do
        cs <- mintNft
        bal <- liftContractM "no ballance" =<< getWalletBalance
        let nfts = Value.valueOf bal cs adaToken
        nfts `shouldEqual` (BigInt.fromInt 1)

      it "burning nft fails" $ useRunnerSimple do
        txOut <- seedTx
        nftPolicy <- makeNftPolicy txOut
        cs <- liftContractM "hash failed" $ scriptCurrencySymbol nftPolicy
        adr <- liftContractM "no wallet" =<< getWalletAddress
        utxos <- getUtxos adr
        let
          mintLookups :: Lookups.ScriptLookups PlutusData
          mintLookups = Lookups.mintingPolicy nftPolicy
            <> Lookups.unspentOutputs utxos

          mintConstraints :: TxConstraints Unit Unit
          mintConstraints = Constraints.mustMintValue (Value.singleton cs adaToken (BigInt.fromInt 1))
            <> Constraints.mustSpendPubKeyOutput txOut
        txid <- buildBalanceSignAndSubmitTx mintLookups mintConstraints
        _ <- waitForTx waitTime adr txid
        let
          burnLookups :: Lookups.ScriptLookups PlutusData
          burnLookups = Lookups.mintingPolicy nftPolicy
            <> Lookups.unspentOutputs utxos

          burnConstraints :: TxConstraints Unit Unit
          burnConstraints =
            Constraints.mustSpendPubKeyOutput txOut
              <> Constraints.mustMintValue (Value.singleton cs adaToken (BigInt.fromInt $ -1))
        expectError
          $ void
          $ buildBalanceSignAndSubmitTx burnLookups burnConstraints

  describe "protocol" do

    it "initialize protocol" $ useRunnerSimple do
      protocolInit

    it "initialize protocol but fail to steal the utxo" $ useRunnerSimple do
      txin <- _.config <$> protocolInit
      validator <- liftContractM "decoding failed" $ decodeCbor CBOR.configScript
      let vhash = validatorHash validator
      utxos <- getUtxos (scriptHashAddress vhash)
      let
        lookups :: Lookups.ScriptLookups PlutusData
        lookups = Lookups.validator validator <> Lookups.unspentOutputs utxos

        constraints :: TxConstraints Unit Unit
        constraints = Constraints.mustSpendScriptOutput txin (Redeemer (toData unit))
      expectError $ buildBalanceSignAndSubmitTx lookups constraints

    it "initialize protocol and open a vault" $ useRunnerSimple do
      protocol <- protocolInit
      openVault protocol

    it "find a vault" $ useRunnerSimple do
      protocol <- protocolInit
      vault <- openVault protocol
      getVaultById protocol vault

    it "increment a vault" $ useRunnerSimple do
      protocol <- protocolInit
      vault <- openVault protocol
      incrementVault protocol vault

    it "find after inc" $ useRunnerSimple do
      protocol <- protocolInit
      vault <- openVault protocol
      incrementVault protocol vault
      getVaultById protocol vault

    it "close a vault" $ useRunnerSimple do
      protocol <- protocolInit
      vault <- openVault protocol
      closeVault protocol vault

    it "close after inc" $ useRunnerSimple do
      protocol <- protocolInit
      vault <- openVault protocol
      incrementVault protocol vault
      closeVault protocol vault

    it "vault gone after close" $ useRunnerSimple do
      protocol <- protocolInit
      vault <- openVault protocol
      closeVault protocol vault
      expectError $ getVaultById protocol vault

    describe "attacks" do
      it "can't open vault at 1" $ useRunnerSimple do
        protocol <- protocolInit
        expectError $ openVault' 1 protocol

      it "can't inc vault by 2" $ useRunnerSimple do
        protocol <- protocolInit
        vault <- openVault protocol
        expectError $ incrementVault' 2 protocol vault

      describe "invalid vaults" $ do
        it "invalid vaults don't show up in getAllVaults" $ useRunnerSimple do
          protocol <- protocolInit
          _ <- openInvalidVault protocol
          getAllVaults protocol `shouldReturn` Map.empty

        it "invalid vaults can't be incremented" $ useRunnerSimple do
          protocol <- protocolInit
          txin <- openInvalidVault protocol
          utxos <- getUtxos (scriptHashAddress $ validatorHash protocol.vaultValidator)
          key <- liftContractM "no wallet" =<< ownPaymentPubKeyHash
          pkh <- getWalletAddress
            >>= case _ of
              Just (Address { addressCredential: PubKeyCredential pkh }) -> pure pkh
              _ -> liftEffect $ throw "failed to get wallet pubkey hash"
          let
            red :: Redeemer
            red = Redeemer $ toData $ HelloRedeemer { tn: adaToken, action: Inc }

            newVault :: Vault
            newVault = Vault { owner: pkh, count: BigInt.fromInt 2 }

            lookups :: Lookups.ScriptLookups PlutusData
            lookups = Lookups.validator protocol.vaultValidator
              <> Lookups.unspentOutputs utxos

            constraints :: TxConstraints Unit Unit
            constraints = Constraints.mustSpendScriptOutput txin red
              <> Constraints.mustPayToScript (validatorHash protocol.vaultValidator) (Datum $ newVault # toData) Constraints.DatumInline enoughForFees
              <> Constraints.mustReferenceOutput protocol.config
              <> Constraints.mustBeSignedBy key
          expectError $ buildBalanceSignAndSubmitTx lookups constraints

      describe "steal nft" $ do
        it "on open" $ useRunnerSimple do
          protocol <- protocolInit
          nftCs <- liftContractM "mpsSymbol failed" $ mpsSymbol $ mintingPolicyHash protocol.nftMp
          txOut <- seedTx
          nftTn <- liftContractM "failed to make nft token name" $ datumHash (Datum (toData txOut)) <#> unwrap >>= mkTokenName
          let nftRed = NftRedeemer { tn: nftTn, txId: txOut }
          pkh <- getWalletAddress >>= case _ of
            Just (Address { addressCredential: PubKeyCredential pkh }) -> pure pkh
            _ -> liftEffect $ throw "failed to get wallet pubkey hash"
          let
            nft :: Value.Value
            nft = Value.singleton nftCs nftTn $ BigInt.fromInt 1

            vault :: Vault
            vault = Vault { owner: pkh, count: BigInt.fromInt 0 }

            lookups :: Lookups.ScriptLookups PlutusData
            lookups = Lookups.mintingPolicy protocol.nftMp

            constraints :: TxConstraints Unit Unit
            constraints =
              Constraints.mustPayToScript (validatorHash protocol.vaultValidator) (Datum $ vault # toData) Constraints.DatumInline enoughForFees
                <> Constraints.mustMintValueWithRedeemer (Redeemer $ nftRed # toData) nft
          expectError $ buildBalanceSignAndSubmitTx lookups constraints

        it "on open mint 2 steal 1" $ useRunnerSimple do
          protocol <- protocolInit
          nftCs <- liftContractM "mpsSymbol failed" $ mpsSymbol $ mintingPolicyHash protocol.nftMp
          txOut <- seedTx
          nftTn <- liftContractM "failed to make nft token name" $ datumHash (Datum (toData txOut)) <#> unwrap >>= mkTokenName
          let nftRed = NftRedeemer { tn: nftTn, txId: txOut }
          pkh <- getWalletAddress >>= case _ of
            Just (Address { addressCredential: PubKeyCredential pkh }) -> pure pkh
            _ -> liftEffect $ throw "failed to get wallet pubkey hash"
          let
            nft :: Value.Value
            nft = Value.singleton nftCs nftTn $ BigInt.fromInt 1

            vault :: Vault
            vault = Vault { owner: pkh, count: BigInt.fromInt 0 }

            lookups :: Lookups.ScriptLookups PlutusData
            lookups = Lookups.mintingPolicy protocol.nftMp

            constraints :: TxConstraints Unit Unit
            constraints =
              Constraints.mustPayToScript (validatorHash protocol.vaultValidator) (Datum $ vault # toData) Constraints.DatumInline (enoughForFees <> nft)
                <> Constraints.mustMintValueWithRedeemer (Redeemer $ nftRed # toData) (nft <> nft)
          expectError $ buildBalanceSignAndSubmitTx lookups constraints

        it "on inc" $ useRunnerSimple do
          protocol <- protocolInit
          vaultId <- openVault protocol
          txin /\ txOut <- getVaultById protocol vaultId
          utxos <- getUtxos (scriptHashAddress $ validatorHash protocol.vaultValidator)
          (oldVault :: Vault) <- liftContractM "failed to parse old vault" <<< fromData <<< unwrap =<< getDatum (unwrap (unwrap txOut).output).datum
          key <- liftContractM "no wallet" =<< ownPaymentPubKeyHash
          let
            red :: Redeemer
            red = Redeemer $ toData $ HelloRedeemer { tn: vaultId, action: Inc }

            newVault :: Vault
            newVault = Vault { owner: (unwrap oldVault).owner, count: (unwrap oldVault).count + BigInt.fromInt 1 }

            lookups :: Lookups.ScriptLookups PlutusData
            lookups = Lookups.validator protocol.vaultValidator
              <> Lookups.unspentOutputs utxos

            constraints :: TxConstraints Unit Unit
            constraints = Constraints.mustSpendScriptOutput txin red
              <> Constraints.mustPayToScript (validatorHash protocol.vaultValidator) (Datum $ newVault # toData) Constraints.DatumInline enoughForFees
              <> Constraints.mustReferenceOutput protocol.config
              <> Constraints.mustBeSignedBy key
          expectError $ buildBalanceSignAndSubmitTx lookups constraints

        it "on close" $ useRunnerSimple do
          protocol <- protocolInit
          vaultId <- openVault protocol
          txin <- fst <$> getVaultById protocol vaultId
          utxos <- getUtxos (scriptHashAddress $ validatorHash protocol.vaultValidator)
          key <- liftContractM "no wallet" =<< ownPaymentPubKeyHash
          let
            red :: Redeemer
            red = Redeemer $ toData $ HelloRedeemer { tn: vaultId, action: Spend }

            lookups :: Lookups.ScriptLookups PlutusData
            lookups = Lookups.validator protocol.vaultValidator
              <> Lookups.unspentOutputs utxos
              <> Lookups.mintingPolicy protocol.nftMp

            constraints :: TxConstraints Unit Unit
            constraints = Constraints.mustSpendScriptOutput txin red
              <> Constraints.mustReferenceOutput protocol.config
              <> Constraints.mustBeSignedBy key
          expectError $ buildBalanceSignAndSubmitTx lookups constraints

localOnlySpec :: Spec Unit
localOnlySpec = describe "HelloWorld.Discovery.Api" do
  describe "two wallet tests" $ do

    it "getMyVaults gets my vaults" $ useTwoWalletRunner $ \asAlice asBob -> do
      protocol <- asAlice protocolInit
      aliceVault <- asAlice $ openVault protocol
      bobVault <- asBob $ openVault protocol
      aliceVaultTx <- getVaultById protocol aliceVault
      (asAlice $ getMyVaults protocol) `shouldReturn` (uncurry Map.singleton aliceVaultTx)
      bobVaultTx <- getVaultById protocol bobVault
      (asBob $ getMyVaults protocol) `shouldReturn` (uncurry Map.singleton bobVaultTx)

    describe "attacks" $ do
      it "bob can't inc alices vault" $ useTwoWalletRunner $ \asAlice asBob -> do
        (protocol /\ aliceVault) <- asAlice do
          protocol <- protocolInit
          vault <- openVault protocol
          pure $ protocol /\ vault
        asBob do
          expectError $ incrementVault protocol aliceVault

      -- "attack" is a strong word but it's a thing you're not supposed to be able to do in the protocol
      it "alice can't gitf bob a vault" $ useTwoWalletRunner $ \asAlice asBob -> do
        (protocol /\ aliceVault) <- asAlice do
          protocol <- protocolInit
          vault <- openVault protocol
          pure $ protocol /\ vault
        bobKey <- asBob $
          getWalletAddress >>= case _ of
              Just (Address { addressCredential: PubKeyCredential pkh }) -> pure pkh
              _ -> liftEffect $ throw "failed to get wallet pubkey hash"
        asAlice $ do
          let vaultId = aliceVault
          txin <- fst <$> getVaultById protocol vaultId
          utxos <- getUtxos (scriptHashAddress $ validatorHash protocol.vaultValidator)
          cs <- liftContractM "invalid protocol" $ mpsSymbol $ mintingPolicyHash protocol.nftMp
          key <- liftContractM "no wallet" =<< ownPaymentPubKeyHash
          let
            nft :: Value
            nft = Value.singleton cs vaultId $ BigInt.fromInt 1

            red :: Redeemer
            red = Redeemer $ toData $ HelloRedeemer { tn: vaultId, action: Inc }

            newVault :: Vault
            newVault = Vault { owner: bobKey, count: BigInt.fromInt 1}

            lookups :: Lookups.ScriptLookups PlutusData
            lookups = Lookups.validator protocol.vaultValidator
              <> Lookups.unspentOutputs utxos

            constraints :: TxConstraints Unit Unit
            constraints = Constraints.mustSpendScriptOutput txin red
              <> Constraints.mustPayToScript (validatorHash protocol.vaultValidator) (Datum $ newVault # toData) Constraints.DatumInline (enoughForFees <> nft)
              <> Constraints.mustReferenceOutput protocol.config
              <> Constraints.mustBeSignedBy key
          expectError $ buildBalanceSignAndSubmitTx lookups constraints

      it "bob can't close alices vault" $ useTwoWalletRunner $ \asAlice asBob -> do
        (protocol /\ aliceVault) <- asAlice do
          protocol <- protocolInit
          vault <- openVault protocol
          pure $ protocol /\ vault
        asBob do
          expectError $ closeVault protocol aliceVault

useTwoWalletRunner
  :: forall a
   . ( (forall b. Contract () b -> Contract () b)
       -> (forall b. Contract () b -> Contract () b)
       -> Contract () a
     )
  -> Aff Unit
useTwoWalletRunner contract = do
  withPlutipContractEnv plutipConfig (defaultWallet /\ defaultWallet) \env (alice /\ bob) ->
    runContractInEnv (withOurLogger "apiTest.log" env) $ void
      $ contract (withKeyWallet alice) (withKeyWallet bob)

useRunnerSimple :: forall a. Contract () a -> EnvRunner -> Aff Unit
useRunnerSimple contract runner = do
  runner \env alice ->
    runContractInEnv (withOurLogger "apiTest.log" env)
      $ withKeyWallet alice
      $ void contract

waitTime :: Minutes
waitTime = 5.0 # Minutes

openInvalidVault :: Protocol -> Contract () TransactionInput
openInvalidVault protocol = do
  pkh <- getWalletAddress
    >>= case _ of
      Just (Address { addressCredential: PubKeyCredential pkh }) -> pure pkh
      _ -> liftEffect $ throw "failed to get wallet pubkey hash"
  let
    vault :: Vault
    vault = Vault { owner: pkh, count: BigInt.fromInt 1 }

    lookups :: Lookups.ScriptLookups PlutusData
    lookups = mempty

    constraints :: TxConstraints Unit Unit
    constraints =
      Constraints.mustPayToScript (validatorHash protocol.vaultValidator) (Datum $ vault # toData) Constraints.DatumInline enoughForFees
  txout <- buildBalanceSignAndSubmitTx lookups constraints
  liftContractM "time out" =<< waitForTx maxWait (scriptHashAddress $ validatorHash protocol.vaultValidator) txout
