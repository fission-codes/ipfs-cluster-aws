# Shell environment for deployment
{ pkgs ? import ./nix { }, ... }:
let
  commands = {
    inherit (pkgs) niv;

    # terraform = pkgs.terraform_0_12.withPlugins
    #   (p: with p; [ aws local p.null random template tls ]);

    terraform = pkgs.terraform_0_13;

    validate = pkgs.writeTurtleBin "validate" ''
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

    deploy-nixos = pkgs.writeTurtleBin "deploy-nixos" ''
      main = do
        (destination, config) <-
          options "Deploy a NixOS configuration via SSH." $ (,)
            <$> (argText "destination" "SSH destination, eg. root@server-fqdn.example.com or user@123.45.67.89")
            <*> (optText "config" 'c' "path of NixOS configuration to be uploaded to /etc/nixos/configuration.nix" & optional)
        rsync sources (destination <> ":" <> "/etc/nixos/")
        whenJust config (\source -> rsync [source] (destination <> ":" <> "/etc/nixos/configuration.nix"))
        ssh destination deployCommand

      sources = [ "ipfs-cluster-aws.nix", "ipfs-cluster.nix", "nix" ]

      deployCommand = intercalate " && "
        [ "nixos-rebuild build --show-trace > /dev/null"
        , "nixos-rebuild switch --show-trace -j 1"
        ]
    '';
  };
in pkgs.mkShell {
  buildInputs = pkgs.lib.attrValues commands
    ++ (with pkgs; [ ipfs-key openssh rsync ]);
  shellHook = ''
    set -e
    terraform init -input=false -get-plugins=false >/dev/null
    [ $0 == "bash" ] && \
      echo && \
      echo "Welcome to the 'ipfs-cluster-aws' deployment shell." && \
      echo "Available commands: ${
        pkgs.lib.concatStringsSep ", " (pkgs.lib.attrNames commands)
      }."
    set +e
  '';

  passthru = commands;
}
