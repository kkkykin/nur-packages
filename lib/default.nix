{pkgs}:
with pkgs.lib; {
  makeDictdDB = pkgs.callPackage ../pkgs/dict-db.nix {};
  makeStardictDB = pkgs.callPackage ../pkgs/stardict-db.nix {};
  # Add your library functions here
  #
  # hexint = x: hexvals.${toLower x};
}
