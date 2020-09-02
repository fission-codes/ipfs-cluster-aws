self: super:
let
  sources =  import ./sources.nix;
in
{
  ipfs = self.callPackage ./ipfs.nix { go-ds-s3-source = sources.go-ds-s3; };
  ipfs-key = self.callPackage ./ipfs-key.nix {};
  writeTurtleBin = self.callPackage ./writeTurtleBin.nix { inherit (self.writers) writeHaskellBin; };
}
