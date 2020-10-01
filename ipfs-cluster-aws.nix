# NixOS profile for running an `ipfs-cluster` node on AWS EC2
{ config, lib, pkgs, ... }:
let
  inherit (lib) mkIf mkEnableOption mkOption types;

  cfg = config.services.ipfs-cluster-aws;
in
{
  imports = [
    <nixpkgs/nixos/modules/virtualisation/amazon-image.nix>
    ./ipfs-cluster.nix
  ];

  options.services.ipfs-cluster-aws = with types; {
    enable = mkEnableOption "Configuration for running IPFS Cluster on AWS";

    region = mkOption {
      type = str;
      description = "AWS region where S3 bucket is hosted.";
    };

    bucket = mkOption {
      type = str;
      description = "Name of AWS S3 bucket to use as data store.";
    };
  };

  config = mkIf cfg.enable {
    nixpkgs.overlays = [ (import ./nix/overlay.nix) ];

    swapDevices = [ { device = "/swapfile"; size = 4096; } ];

    system.autoUpgrade.enable = true;

    networking.firewall.allowedTCPPorts = [ 8080 9096 ];

    services.openssh.enable = true;

    systemd.services.ipfs-init = {
      unitConfig.PartOf = [ "ipfs.service" ];
      postStart = let
        datastoreSpec = {
          mounts = [
            {
              bucket = cfg.bucket;
              mountpoint = "/blocks";
              region = cfg.region;
              rootDirectory = "";
            }
            {
              mountpoint = "/";
              path = "datastore";
              type = "levelds";
            }
          ];
          type = "mount";
        };
      in ''
        echo "Configuring S3 datastore"
        ipfs --local config --json Datastore '${builtins.toJSON config.services.ipfs.extraConfig.Datastore}'
        echo '${builtins.toJSON datastoreSpec}' > ${config.services.ipfs.dataDir}/datastore_spec
      '';
    };

    services.ipfs = {
      enable = true;
      emptyRepo = true;

      extraConfig = {
        Datastore = {
          StorageMax = "100GB";
          Spec = {
            type = "mount";
            mounts = [
              {
                child = {
                  type = "s3ds";
                  region = cfg.region;
                  bucket = cfg.bucket;
                  rootDirectory = "";
                  accessKey = "";
                  secretKey = "";
                };
                mountpoint = "/blocks";
                prefix = "s3.datastore";
                type = "measure";
              }
              {
                child = {
                  compression = "none";
                  path = "datastore";
                  type = "levelds";
                };
                mountpoint = "/";
                prefix = "leveldb.datastore";
                type = "measure";
              }
            ];
          };
        };
      };
    };

    services.ipfs-cluster = {
      enable = true;
      identityFile = "/root/SECRET_identity.json";
    };

    systemd.services.ipfs-cluster-init.serviceConfig.EnvironmentFile = "/root/SECRET_ipfs-cluster";
    systemd.services.ipfs-cluster.serviceConfig.EnvironmentFile = "/root/SECRET_ipfs-cluster";
  };
}
