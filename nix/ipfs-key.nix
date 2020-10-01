{ buildGoModule } :
buildGoModule {
  pname = "ipfs-key";
  version = "2020-08-14";

  src = (import ./sources.nix).ipfs-key;

  vendorSha256 = "0yq14f02fz623xd04wn382gs6kc2bia93y84pwsmg3vl7yqqxv0b";
}
