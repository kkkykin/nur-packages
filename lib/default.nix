{pkgs}:
with pkgs.lib; {
  makeStardictDB = pkgs.callPackage ../pkgs/stardict-db.nix {};
  # Add your library functions here
  #
  # hexint = x: hexvals.${toLower x};
}
