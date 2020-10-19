# Shell environment for deployment
{ pkgs ? import ./nix { }, ... }:
let
  commands = {
    inherit (pkgs) niv;

    terraform = pkgs.terraform_0_13.withPlugins
      (p: with p; [ acme aws external local p.null random shell template tls ]);

    validate = pkgs.writeTurtleBin "validate" ''
      main = do
        options "Build and validate the project without connecting to AWS." $ pure ()
        run "terraform fmt -check -recursive"
        run "terraform validate"
        echo "Success."
    '';

    deploy-nixos = pkgs.writeTurtleBin "deploy-nixos" ''
      main = do
        (destination, config) <- options "Deploy a NixOS configuration via SSH." $ (,)
          <$> (argText "destination" "SSH destination, eg. root@server-fqdn.example.com or user@123.45.67.89")
          <*> (optText "config" 'c' "path of NixOS configuration to be uploaded to /etc/nixos/configuration.nix" & optional)

        rsync [ "nix", "nixos" ] (destination <> ":" <> "/root/ipfs-cluster-aws/")
        whenJust config (\source -> rsync [source] (destination <> ":" <> "/etc/nixos/configuration.nix"))
        ssh destination deployCommand

      deployCommand = intercalate " && "
        [ "nixos-rebuild build --show-trace > /dev/null"
        , "nixos-rebuild switch --show-trace -j 1"
        ]
    '';

    update-deps = pkgs.writeTurtleBin "update-deps" ''
      main = do
        options "Update dependencies." $ pure ()
        run "niv update"
    '';
  };
in pkgs.mkShell rec {
  buildInputs = pkgs.lib.attrValues commands
    ++ (with pkgs; [ ipfs-key openssh rsync ]);
  shellHook = ''
    terraform init -input=false -get-plugins=false -upgrade >/dev/null
    [ $0 == "bash" ] && echo && \
      ${pkgs.toilet}/bin/toilet fission.codes --metal --font smblock && \
      echo "Welcome to the 'ipfs-cluster-aws' deployment shell." && \
      echo "Available commands: ${
        pkgs.lib.concatStringsSep ", " (pkgs.lib.attrNames commands)
      }."
    set +e
  '';

  passthru = commands // { inherit buildInputs; };
}
