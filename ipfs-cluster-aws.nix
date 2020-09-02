# NixOS profile for running an `ipfs-cluster` node on AWS EC2
{
  imports = [
    <nixpkgs/nixos/modules/virtualisation/amazon-image.nix>
    ./ipfs-cluster.nix
  ];

  swapDevices = [ { device = "/swapfile"; size = 4096; } ];

  system.autoUpgrade.enable = true;

  networking.firewall.allowedTCPPorts = [ 4002 8080 9096 ];

  services.openssh.enable = true;

  services.ipfs.enable = true;

  services.ipfs-cluster = {
    enable = true;
    identityFile = "/root/SECRET_identity.json";
  };
}
