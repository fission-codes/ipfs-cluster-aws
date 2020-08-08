# NixOS profile for running an `ipfs-cluster` node on AWS EC2
{
  imports = [
    <nixpkgs/nixos/modules/virtualisation/amazon-image.nix>
    ./ipfs-cluster.nix
  ];

  swapDevices = [ { device = "/swapfile"; size = 4096; } ];

  system.autoUpgrade.enable = true;

  services.openssh.enable = true;

  services.ipfs.enable = true;
}
