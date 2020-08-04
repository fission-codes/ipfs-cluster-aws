# Shell environment for deployment

let
  inherit (import <nixpkgs> {}) fetchFromGitHub;

  pkgs = import (fetchFromGitHub {
    owner  = "NixOS";
    repo   = "nixpkgs";
    rev    = "840c782d507d60aaa49aa9e3f6d0b0e780912742";
    sha256 = "14q3kvnmgz19pgwyq52gxx0cs90ddf24pnplmq33pdddbb6c51zn";
  }) {};


  commands = {
    check = pkgs.writeScriptBin "check" ''
      echo TODO
    '';

    terraform = pkgs.terraform_0_12.withPlugins (p : with p;
      [ aws local p.null random template tls ]
    );
  };

in
pkgs.mkShell {
  buildInputs = pkgs.lib.attrValues commands ++ (with pkgs; [ openssh rsync ]) ;
  shellHook = ''
    set -e
    terraform init -input=false -get-plugins=false >/dev/null
    echo "Welcome to the 'ipfs-cluster-aws' deployment shell."
    echo "Available commands: ${pkgs.lib.concatStringsSep ", " (pkgs.lib.attrNames commands)}."
    set +e
  '';
}
