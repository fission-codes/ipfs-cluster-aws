# NixOS module defining ipfs-cluster service
{ config, lib, pkgs, ... }:
let
  inherit (lib) mkIf mkEnableOption mkOption types;
  inherit (lib) concatStringsSep optionalString;

  cfg = config.services.ipfs-cluster;
in
{
  options.services.ipfs-cluster = with types; {
    enable = mkEnableOption "Pinset orchestration for IPFS.";

    user = mkOption {
      type = str;
      default = "ipfs-cluster";
      description = "User under which the ipfs-cluster daemon runs.";
    };

    group = mkOption {
      type = str;
      default = "ipfs-cluster";
      description = "Group under which the ipfs-cluster daemon runs.";
    };

    dataDir = mkOption {
      type = path;
      default = "/var/lib/ipfs-cluster";
      description = "The data directory for ipfs-cluster.";
    };

    identityFile = mkOption {
      type = nullOr path;
      default = null;
      description = "The path of an `identity.json` file containing the node id and private key. If provided, it will be copied to dataDir, unless one is already there.";
    };

    extraEnv = mkOption {
      type = attrsOf str;
      default = {};
      description = "Extra environment variables to pass to ipfs-cluster-service.";
    };

    bootstrapPeers = mkOption {
      type = listOf str;
      default = [];
      description = "List of trusted peer multiadresses to use for bootstrapping the cluster.";
    };
  };

  config = let
    bootstrapArgs = optionalString (cfg.bootstrapPeers != null) "--bootstrap ${concatStringsSep "," cfg.bootstrapPeers}";
  in {
    environment.systemPackages = [ pkgs.ipfs-cluster ];

    users.users = mkIf (cfg.user == "ipfs-cluster") {
      ipfs-cluster = {
        description = "ipfs-cluster daemon user";
        # add a uid/gid to nixos/modules/misc/ids.nix or use DynamicUser
        # uid = config.ids.uids.ipfs-cluster;
        group = cfg.group;
        home = cfg.dataDir;
        createHome = true;
      };
    };

    users.groups = mkIf (cfg.group == "ipfs-cluster") {
      ipfs-cluster = {
        # add a uid/gid to nixos/modules/misc/ids.nix or use DynamicUser
        # gid = config.ids.gids.ipfs-cluster;
      };
    };

    systemd.tmpfiles.rules = [
      "d '${cfg.dataDir}' - ${cfg.user} ${cfg.group} - -"
    ];

    systemd.services.ipfs-cluster-init = {
      description = "ipfs-cluster initializer";

      environment = { IPFS_CLUSTER_PATH = cfg.dataDir; } // cfg.extraEnv;

      path = [ pkgs.ipfs-cluster ];

      preStart = mkIf (cfg.identityFile != null) ''
        if [ ! -f "${cfg.dataDir}/identity.json" ]; then
          cp "${cfg.identityFile}" "${cfg.dataDir}/identity.json"
        fi
      '';

      script = ''
        ipfs-cluster-service init --force
      '';

      wants = [ "ipfs.service" ];
      after = [ "ipfs.service" ];
      wantedBy = [ "default.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = cfg.user;
        Group = cfg.group;
        PermissionsStartOnly = true;
      };

    };

    systemd.services.ipfs-cluster = {
      description = "ipfs-cluster daemon";
      path = [ "/run/wrappers" pkgs.ipfs-cluster ];

      environment = { IPFS_CLUSTER_PATH = cfg.dataDir; } // cfg.extraEnv;

      script = ''
        ipfs-cluster-service daemon ${bootstrapArgs}
      '';

      wantedBy = [ "default.target" ];
      wants = [ "ipfs-cluster-init.service" "ipfs.service" ];
      after = [ "ipfs-cluster-init.service" "ipfs.service" ];

      restartIfChanged = true;

      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
      };
    };

  };

  meta = {
    maintainers = with lib.maintainers; [ brainrape ];
  };
}
