{ buildGoModule, lib }:

buildGoModule rec {
  pname = "ipfs-migrator";
  version = "1.7.1";
  rev = "v${version}";

  src = (import ./sources.nix).ipfs-migrator;

  vendorSha256 = null;

  doCheck = false;

  subPackages = [ "." ];

  meta = with lib; {
    description = "Migrations for the filesystem repository of ipfs clients";
    homepage = "https://ipfs.io/";
    license = licenses.mit;
    platforms = platforms.unix;
    maintainers = with maintainers; [ elitak ];
  };
}

