# IPFS package with built-in S3 datastore plugin

{ stdenv, buildGoModule, fetchurl, nixosTests }:

buildGoModule rec {
  pname = "ipfs";
  version = "0.7.0";
  rev = "v${version}";

  src = (import ./sources.nix).ipfs;

  subPackages = [ "cmd/ipfs" ];

  vendorSha256 = "1493a01ckgjmyxr88fk39la5fask4plnl0lajgixhyjzpr6p5hss";

  postInstall = ''
    install --mode=444 -D misc/systemd/ipfs.service $out/etc/systemd/system/ipfs.service
    install --mode=444 -D misc/systemd/ipfs-api.socket $out/etc/systemd/system/ipfs-api.socket
    install --mode=444 -D misc/systemd/ipfs-gateway.socket $out/etc/systemd/system/ipfs-gateway.socket
    substituteInPlace $out/etc/systemd/system/ipfs.service \
      --replace /usr/bin/ipfs $out/bin/ipfs
  '';
}
