{ buildGoModule, lib }:

let
  version = "1.7.1";
  pkgs = import ./sources.nix;
in
  buildGoModule {
    inherit version;

    pname = "ipfs-migrator";
    rev = "v${version}";

    src = pkgs.ipfs-migrator;
    vendorSha256 = null;
    doCheck = false;
    subPackages = [ "." ];

    meta = {
      description = "Migrations for the filesystem repository of ipfs clients";
      homepage = "https://ipfs.io/";
      license = lib.licenses.mit;
      platforms = lib.platforms.unix;
      maintainers =  [ lib.maintainers.elitak ];
    };
}
