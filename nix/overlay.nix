self: super:
let
  sources = import ./sources.nix;
in
{
  ipfs-key = self.callPackage ./ipfs-key.nix {};
  writeTurtleBin = self.callPackage ./writeTurtleBin.nix { inherit (self.writers) writeHaskellBin; };
}
