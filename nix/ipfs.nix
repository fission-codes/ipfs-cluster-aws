{ stdenv, buildGoModule, fetchurl, nixosTests }:

buildGoModule rec {
  pname = "ipfs";
  version = "0.7.0";
  rev = "v${version}";

  src = (import ./sources.nix).ipfs;

  subPackages = [ "cmd/ipfs" ];

  passthru.tests.ipfs = nixosTests.ipfs;

  vendorSha256 = "1493a01ckgjmyxr88fk39la5fask4plnl0lajgixhyjzpr6p5hss";

  postInstall = ''
    install --mode=444 -D misc/systemd/ipfs.service $out/etc/systemd/system/ipfs.service
    install --mode=444 -D misc/systemd/ipfs-api.socket $out/etc/systemd/system/ipfs-api.socket
    install --mode=444 -D misc/systemd/ipfs-gateway.socket $out/etc/systemd/system/ipfs-gateway.socket
    substituteInPlace $out/etc/systemd/system/ipfs.service \
      --replace /usr/bin/ipfs $out/bin/ipfs
  '';

  meta = with stdenv.lib; {
    description = "A global, versioned, peer-to-peer filesystem";
    homepage = "https://ipfs.io/";
    license = licenses.mit;
    platforms = platforms.unix;
    maintainers = with maintainers; [ fpletz ];
  };
}
