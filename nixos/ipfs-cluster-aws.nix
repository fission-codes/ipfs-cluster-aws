# NixOS profile for running an `ipfs-cluster` node on AWS EC2
{ config, lib, pkgs, ... }:
let
  inherit (lib) mkIf mkEnableOption mkOption types;

  cfg = config.services.ipfs-cluster-aws;
in
{
  imports = [
    <nixpkgs/nixos/modules/virtualisation/amazon-image.nix>
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

    domain = mkOption {
      type = str;
      description = "Root domain for TLS ACME Certs";
    };

    fqdn = mkOption {
      type = str;
      description = "Full domain for node";
    };

    crons = mkOption {
      type = listOf str;
      description = "List of cronjobs";
    };
  };
  
  config = mkIf cfg.enable {
    nixpkgs.overlays = [ (import ../nix/overlay.nix) ];

    swapDevices = [ { device = "/swapfile"; size = 4096; } ];

    system.autoUpgrade.enable = true;

    networking = {
      enableIPv6 = true;
      firewall = {
        allowedTCPPorts = [
          80 # HTTP ACME and redirect to :443
          443 # IPFS gateway https
          4001 # IPFS swarm TCPACME
          4002 # IPFS swarm Websocket
          4003 # IPFS swarm Secure Websocket
          5001 # IPFS HTTP API
          8080 # IPFS Gateway
          9094 # IPFS Cluster HTTP API
          9096 # IPFS Cluster swarm
        ];
        allowedUDPPorts = [
          4001 # IPFS swarm QUIC
        ];
      };
    };

    security.acme.acceptTerms = true;
    security.acme.email = "support@fission.codes";

    services.openssh.enable = true;

    services.nginx = {
      enable = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;

      appendHttpConfig = ''
        server_names_hash_bucket_size 128;
      '';

      # Even though we don't use port 80/443, we leave this in the nginx config to help out Let's Encrypt
      virtualHosts.root = {
        addSSL = true;
        enableACME = true;
        serverName = "${cfg.fqdn}";

        locations."/" = {
          root = "/var/www";
        };
      };

      virtualHosts."${cfg.fqdn}" = {
        addSSL = true;
        enableACME = true;

        listen = [
          { addr = "0.0.0.0"; port = 4003; ssl = true; }
          { addr = "[::]";    port = 4003; ssl = true; }
        ];

        locations."/" = {
          proxyPass = "http://127.0.0.1:4002";
          proxyWebsockets = true;
          root = "/var/www";
        };
      };
    };

    services.cron = {
      enable = true;
      systemCronJobs = cfg.crons;
    };

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

      apiAddress = "/ip4/0.0.0.0/tcp/5001";
      gatewayAddress = "/ip4/0.0.0.0/tcp/8080";

      swarmAddress = [
        "/ip4/0.0.0.0/tcp/4001"
        "/ip6/::/tcp/4001"
        "/ip4/0.0.0.0/udp/4001/quic"
        "/ip6/::/udp/4001/quic"
        "/ip4/0.0.0.0/tcp/4002/ws"
        "/ip6/::1/tcp/4002/ws"
      ];

      extraConfig = {
        API = {
          HTTPHeaders = {
            Access-Control-Allow-Origin = ["*"];
          };
        };
        Datastore = {
          StorageMax = "10000GB";
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
        Gateway = {
          NoFetch = true;
        };
      };
    };
  };
}
