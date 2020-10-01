self: super:
let
  sources =  import ./sources.nix;
  nixpkgs-unstable = import sources.nixpkgs {};
in
{
  ipfs-key = self.callPackage ./ipfs-key.nix {};
  ipfs = nixpkgs-unstable.callPackage ./ipfs.nix {};
  writeTurtleBin = self.callPackage ./writeTurtleBin.nix { inherit (self.writers) writeHaskellBin; };
}
