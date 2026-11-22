{pkgs}:
with pkgs.lib; {
  makeDictdDB = pkgs.callPackage ../pkgs/dict-db.nix {};
  makeStardictDB = pkgs.callPackage ../pkgs/stardict-db.nix {};
  serviceHardening = import ./service-hardening.nix {lib = pkgs.lib;};
  # Add your library functions here
  #
  # hexint = x: hexvals.${toLower x};
}
