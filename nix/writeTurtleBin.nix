{ haskellPackages, writeHaskellBin }:
name: text:
  writeHaskellBin name { libraries = with haskellPackages; [
    extra turtle text-show
  ]; } ''
    {-# LANGUAGE OverloadedStrings #-}
    import qualified System.Environment
    import Turtle hiding (setEnv, export)
    import qualified Turtle.Prelude
    import Data.Maybe (maybeToList)
    import Data.Text (unwords, unpack, intercalate)
    import Data.Text.IO (putStrLn)
    import TextShow
    import Prelude hiding (putStrLn, unwords, intercalate)
    import Control.Monad.Extra (whenJust, whenM)

    export :: Text -> Text -> IO ()
    export var val = do
      putStrLn ("export " <> var <> "=" <> val)
      Turtle.Prelude.export var val

    run :: Text -> IO ()
    run command = do
      putStrLn ("Running " <> showt command <> " ...")
      shells command empty

    ssh :: Text -> Text -> IO ()
    ssh destination command = do
      putStrLn ("Connecting via SSH to '" <> destination <>"' and running `" <> command <> "` ...")
      procs "ssh" (sshOptions <> [destination, command]) empty

    sshOptions =
      [ "-oStrictHostKeyChecking=accept-new"
      , "-oBatchMode=yes"
      , "-i", "SECRET/private_key"
      ]

    rsync :: [Text] -> Text -> IO ()
    rsync sources destination = do
      putStrLn ("Copying " <> showt sources <> " to '" <> destination <> "' ...")
      procs "rsync" (rsyncOptions <> sources <> [destination]) empty

    rsyncOptions =
      [ "--recursive"
      , "--rsh=" <> unwords ("ssh" : sshOptions)
      ]

    ${text}
  ''

