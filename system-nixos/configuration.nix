# This is the system NixOS config which sits at /etc/nixos/configuration.nix
# The variables in this config need to be updated per-node
let
  custom = import /root/ipfs-cluster-aws/nix/default.nix {};
in
{
  imports = [ /root/ipfs-cluster-aws/nixos/ipfs-cluster-aws.nix ];

  environment.systemPackages = [ custom.ipfs-migrator ];

  networking.hostName = "staging-ipfs-cluster-us-east-1-node1";

  services.ipfs-cluster-aws = {
    enable = true;
    region = "us-east-1";
    bucket = "staging-ipfs-cluster-us-east-1";
    domain = "runfission.net";
    fqdn  = "staging-ipfs-cluster-us-east-1-node1.runfission.net";
    crons = [
        "15 9 * * *     root    systemctl restart ipfs"
        "* * * * *      root    ipfs swarm connect /dns4/staging-ipfs-cluster-us-east-1-node0.runfission.net/tcp/4001/p2p/12D3KooWDX4mGcThxuWHqySi8awYXgLDTEhNSjp1BY9ToWbBh8q5"
        "* * * * *      root    ipfs swarm connect /dns4/staging-ipfs-cluster-eu-north-1-node0.runfission.net/tcp/4001/p2p/12D3KooWLYqhKbUa9LSdzPZrKPSePipXgVRrHqzr8Uw5cmqqvXuC"
    ];
  };
}
