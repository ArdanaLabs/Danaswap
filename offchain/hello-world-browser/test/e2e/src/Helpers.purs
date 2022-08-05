module HelloWorld.Test.E2E.Helpers where

import Prelude

import Contract.Test.E2E (RunningExample, TestOptions(..), WalletExt, WalletPassword, namiSign, withBrowser, withExample)
import Data.Maybe (Maybe(..))
import Data.Newtype (class Newtype, unwrap, wrap)
import Data.String (trim)
import Effect (Effect)
import Effect.Aff (Aff, error, throwError)
import Effect.Class (liftEffect)
import Foreign (Foreign, unsafeFromForeign)
import HelloWorld.Test.E2E.Env as Env
import Mote (test)
import Node.Buffer as Buffer
import Node.ChildProcess (defaultExecSyncOptions, execSync)
import Node.Encoding (Encoding(UTF8))
import Node.Express.App (listenHttp, use)
import Node.Express.Middleware.Static (static)
import Node.Express.Types (Port)
import Node.HTTP (close, Server)
import Node.Process (lookupEnv)
import TestM (TestPlanM)
import Toppokki as T

-- | A String representing a jQuery selector, e.g. "#my-id" or ".my-class"
newtype Selector = Selector String

derive instance Newtype Selector _
-- | A String representing a jQuery action, e.g. "click" or "enable".
newtype Action = Action String

derive instance Newtype Action _

port :: Port
port = 8080

localhost :: String
localhost = "http://127.0.0.1"

helloWorldBrowserURL :: T.URL
helloWorldBrowserURL = T.URL $ localhost <> ":" <> show port

-- | Run an E2E test. Parameters are:
-- |   String: Just a name for the logs
-- |   Toppokki.URL: URL where the example is running
-- |   TestOptions: Options to start the browser with
-- |   WalletExt: An extension which should be used
-- |   RunningExample -> Aff a: A function which runs the test
runE2ETest
  :: forall (a :: Type)
   . String
  -> TestOptions
  -> WalletExt
  -> (RunningExample -> Aff a)
  -> TestPlanM Unit
runE2ETest example opts ext f = test example $ withBrowser opts ext $
  \browser -> withExample helloWorldBrowserURL browser $ void <<< f

-- | Build a primitive jQuery expression like '$("button").click()' and
-- | out of a selector and action and evaluate it in Toppokki
doJQ :: Selector -> Action -> T.Page -> Aff Foreign
doJQ selector action page = do
  T.unsafeEvaluateStringFunction jq page
  where
  jq :: String
  jq = "$('" <> unwrap selector <> "')." <> unwrap action

-- | select a button with a specific text inside
buttonWithText :: String -> Selector
buttonWithText text = wrap $ "button:contains(" <> text <> ")"

click :: Action
click = wrap "click()"

clickButton :: String -> T.Page -> Aff Unit
clickButton buttonText = void <$> doJQ (buttonWithText buttonText) click

injectJQuery :: String -> T.Page -> Aff Unit
injectJQuery jQuery page = do
  (alreadyInjected :: Boolean) <-
    unsafeFromForeign <$>
      T.unsafeEvaluateStringFunction "typeof(jQuery) !== 'undefined'"
        page
  unless alreadyInjected $ void $ T.unsafeEvaluateStringFunction jQuery
    page

namiWalletPassword :: WalletPassword
namiWalletPassword = wrap "ctlctlctl"

namiSign' :: RunningExample -> Aff Unit
namiSign' = namiSign namiWalletPassword

startStaticServer :: String -> Aff Server
startStaticServer directory =
  liftEffect $ listenHttp (use $ static directory) port $ \_ -> pure unit

closeStaticServer :: Server -> Aff Unit
closeStaticServer server = liftEffect $ close server (pure unit)

mkTempDir :: Effect String
mkTempDir = do
  buf <- execSync "mktemp --directory" defaultExecSyncOptions
  trim <$> Buffer.toString UTF8 buf

apiKey :: String
apiKey = "r8m9YXmqCkFWDDZ2540IJaJwr1JBxqXB"

paymentAddress :: String
paymentAddress = "addr_test1qzc62f70pn5l9aytwdwpnzfn0tyc9jxlar07nr4332vla7ms347sjjelw3e22se5lrnw968mnyvz5ma5hshl8lywv45qnmkvkl"

topup :: Effect Unit
topup = do
  let url = "https://faucet.cardano-testnet.iohkdev.io/send-money/" <> paymentAddress <> "?apiKey=" <> apiKey
  void $ execSync ("curl -XPOST " <> url) defaultExecSyncOptions

unzipNamiSettings :: String -> Effect Unit
unzipNamiSettings dir = do
  namiSettings <- lookupEnv "NAMI_SETTINGS"
  case namiSettings of
    Nothing -> throwError $ error "NAMI_SETTINGS not set"
    Just settings ->
      void $ execSync ("tar zxf " <> settings <> " --directory " <> dir) defaultExecSyncOptions

unzipNamiExtension :: String -> Effect Unit
unzipNamiExtension dir = do
  namiExtension <- lookupEnv "NAMI_EXTENSION"
  case namiExtension of
    Nothing -> throwError $ error "NAMI_EXTENSION not set"
    Just extension ->
      void $ execSync ("unzip " <> extension <> " -d " <> dir <> "/nami > /dev/zero || echo \"ignore warnings\"") defaultExecSyncOptions

mkTestOptions :: Effect TestOptions
mkTestOptions = do
  chromeExe <- lookupEnv Env.chromeExe

  testData <- mkTempDir
  unzipNamiSettings testData
  unzipNamiExtension testData

  case mkTestOptions' <$> Just testData <*> chromeExe of
    Nothing -> throwError $ error "failed to setup test options"
    Just testOptions -> do
      topup
      pure testOptions
  where
  mkTestOptions' :: String -> String -> TestOptions
  mkTestOptions' testData chromeExe =
    TestOptions
      { chromeExe: Just chromeExe
      , namiDir: testData <> "/nami"
      , geroDir: testData <> "/gero"
      , chromeUserDataDir: testData <> "/test-data/chrome-user-data"
      , noHeadless: true
      }
