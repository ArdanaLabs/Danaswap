module HelloWorld.Test.E2E.Main where

import Contract.Prelude

import Data.BigInt as BigInt
import Data.Maybe (Maybe(..))
import Data.UInt as UInt
import Effect.Aff (bracket, launchAff_)
import Effect.Exception (throw, error)
import HelloWorld.Test.E2E.Env as Env
import HelloWorld.Test.E2E.Helpers (Cookie(..), closeStaticServer, startStaticServer)
import HelloWorld.Test.E2E.TestPlans.KeyWallet as Key
import HelloWorld.Test.E2E.TestPlans.NamiWallet as Nami
import Node.Process (lookupEnv)
import Plutip.Server (withPlutipContractEnv)
import Plutip.Types (PlutipConfig)
import Wallet.Key (keyWalletPrivatePaymentKey, keyWalletPrivateStakeKey)
import Wallet.KeyFile (formatPaymentKey, formatStakeKey)

main ∷ Effect Unit
main =
  lookupEnv Env.helloWorldBrowserIndex >>= case _ of
    Nothing -> throw "HELLO_WORLD_BROWSER_INDEX not set"
    Just index ->
      lookupEnv Env.mode >>= case _ of
        Just "testnet" ->
          launchAff_ do
            let
              cookies =
                [ Cookie { key: "paymentKey", value: Nothing }
                , Cookie { key: "stakeKey", value: Nothing }
                , Cookie { key: "networkId", value: Nothing }
                ]
            bracket (startStaticServer cookies index) closeStaticServer $ const Nami.runTestPlans
        Just "local" ->
          launchAff_
            $ withPlutipContractEnv config [ BigInt.fromInt 2_000_000_000 ] \env wallet -> do
                paymentKey <- liftM (error "Failed to format payment key") $ formatPaymentKey (keyWalletPrivatePaymentKey wallet)
                let
                  stakeKey = keyWalletPrivateStakeKey wallet >>= formatStakeKey
                  networkId = (unwrap env).config.networkId
                  cookies =
                    [ Cookie { key: "paymentKey", value: Just paymentKey }
                    , Cookie { key: "stakeKey", value: stakeKey }
                    , Cookie { key: "networkId", value: Just (show networkId) }
                    ]
                bracket (startStaticServer cookies index) closeStaticServer $ const Key.runTestPlans
        Just e -> throw $ "expected local or testnet got: " <> e
        Nothing -> throw "MODE not set"

config :: PlutipConfig
config =
  { host: "127.0.0.1"
  , port: UInt.fromInt 8082
  , logLevel: Error
  , customLogger: Nothing
  , suppressLogs: false
  -- Server configs are used to deploy the corresponding services.
  , ogmiosConfig:
      { port: UInt.fromInt 1337
      , host: "127.0.0.1"
      , secure: false
      , path: Nothing
      }
  , ogmiosDatumCacheConfig:
      { port: UInt.fromInt 9999
      , host: "127.0.0.1"
      , secure: false
      , path: Nothing
      }
  , ctlServerConfig: Just
      { port: UInt.fromInt 8081
      , host: "127.0.0.1"
      , secure: false
      , path: Nothing
      }
  , postgresConfig:
      { host: "127.0.0.1"
      , port: UInt.fromInt 5432
      , user: "ctxlib"
      , password: "ctxlib"
      , dbname: "ctxlib"
      }
  }