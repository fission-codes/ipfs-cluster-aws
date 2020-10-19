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

    nodeFqdn = mkOption {
      type = str;
      description = "Fully qualified domain name assigned to node, for setting up IPFS gateway and swarm TLS via ACME.";
    };

    regionFqdn = mkOption {
      type = str;
      description = "Fully qualified domain name assigned to region, for setting up IPFS gateway and swarm TLS";
    };

    fqdn = mkOption {
      type = str;
      description = "Fully qualified domain name assigned to cluster, for setting up IPFS gateway and swarm TLS";
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
          4003 # IPFS swarm Secure Websocket
          9096 # IPFS Cluster swarm
        ];
        allowedUDPPorts = [
          4001 # IPFS swarm QUIC
        ];
      };
    };

    security.acme.acceptTerms = true;

    services.openssh.enable = true;

    services.nginx = {
      enable = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;

      virtualHosts.ipfs-gateway = {
        serverName = cfg.nodeFqdn;
        forceSSL = true;
        enableACME = true;

        locations."/" = {
          proxyPass = "http://127.0.0.1:8080";
          proxyWebsockets = true;
        };
      };

      virtualHosts.ipfs-swarm-wss = {
        serverName = lib.escape ["."] "~^(${cfg.fqdn}|${cfg.regionFqdn}|${cfg.nodeFqdn})$";
        onlySSL = true;
        sslCertificate = "/var/lib/ssl/cert";
        sslCertificateKey = "/var/lib/ssl/key";

        listen = [
          { addr = "0.0.0.0"; port = 4003; ssl = true; }
          { addr = "[::]";    port = 4003; ssl = true; }
        ];

        locations."/" = {
          proxyPass = "http://127.0.0.1:4002";
          proxyWebsockets = true;
        };
      };
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

      swarmAddress = [
        "/ip4/0.0.0.0/tcp/4001"
        "/ip6/::/tcp/4001"
        "/ip4/0.0.0.0/udp/4001/quic"
        "/ip6/::/udp/4001/quic"
        "/ip4/127.0.0.1/tcp/4002/ws"
        "/ip6/::1/tcp/4002/ws"
      ];

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
