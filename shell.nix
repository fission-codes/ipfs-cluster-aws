# Shell environment for deployment

let
  inherit (import <nixpkgs> {}) fetchFromGitHub;

  pkgs = import (fetchFromGitHub {
    owner  = "NixOS";
    repo   = "nixpkgs";
    rev    = "840c782d507d60aaa49aa9e3f6d0b0e780912742";
    sha256 = "14q3kvnmgz19pgwyq52gxx0cs90ddf24pnplmq33pdddbb6c51zn";
  }) {};

  writeTurtleBin = name: text:
    pkgs.writers.writeHaskellBin name { libraries = with pkgs.haskellPackages; [
      turtle
      text-show
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
        putStrLn ("Connecting via ssh to '" <> destination <>"' and running `" <> command <> "` ...")
        procs "ssh" (sshOptions <> [destination, command]) empty

      sshOptions =
        [ "-oStrictHostKeyChecking=accept-new"
        , "-oBatchMode=yes"
        , "-i", "SECRET_private_key"
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
    '';

  commands = {
    terraform = pkgs.terraform_0_12.withPlugins (p : with p;
      [ aws local p.null random template tls ]
    );

    validate = writeTurtleBin "validate" ''
      main = do
        options "Build and validate the project without connecting to AWS." $ pure ()

        echo "Setting variables..."
        export "AWS_ACCESS_KEY_ID" "fake"
        export "AWS_SECRET_ACCESS_KEY" "fake"
        export "AWS_DEFAULT_REGION" "us-west-2"

        run "terraform validate"
        run "terraform plan -refresh=false -out=terraform.plan"
        echo "Success."
    '';

    deploy-nixos = writeTurtleBin "deploy-nixos" ''
      main = do
        (destination, config) <-
          options "Deploy a NixOS configuration via SSH." $ (,)
            <$> (argText "destination" "SSH destination")
            <*> (optText "config" 'c' "NixOS configuration" & optional)
        rsync sources (destination <> ":" <> "/etc/nixos/")
        do
          let (Just c) = config
          rsync [c] (destination <> ":" <> "/etc/nixos/configuration.nix")
        ssh destination deployCommand

      sources = [ "ipfs-cluster-aws.nix", "ipfs-cluster.nix" ]

      deployCommand = intercalate " && "
        [ "nixos-rebuild build > /dev/null"
        , "nixos-rebuild switch --show-trace"
        ]
    '';
  };

in
pkgs.mkShell {
  buildInputs = pkgs.lib.attrValues commands ++ (with pkgs; [ openssh rsync ]) ;
  shellHook = ''
    set -e
    terraform init -input=false -get-plugins=false >/dev/null
    [ $0 == "bash" ] &&
      echo && \
      echo "Welcome to the 'ipfs-cluster-aws' deployment shell." && \
      echo "Available commands: ${pkgs.lib.concatStringsSep ", " (pkgs.lib.attrNames commands)}."
    set +e
  '';

  passthru = commands;
}
