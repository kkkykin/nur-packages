let
  modules = {
    # Add your NixOS modules here
    #
    # my-module = ./my-module;
    cli-proxy-api = ./cli-proxy-api;
    cpa-manager-plus = ./cpa-manager-plus;
    hubproxy = ./hubproxy;
    matrix-pylon = ./matrix-pylon;
    napcat = ./napcat;
    openlist = ./openlist;
    proxy-checker = ./proxy-checker;
    resin = ./resin;
    romm = ./romm;
    srs-decompile = ./srs-decompile;
  };
in
modules
// {
  default = {
    imports = builtins.attrValues modules;
  };
}
