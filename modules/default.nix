let
  modules = {
    # Add your NixOS modules here
    #
    # my-module = ./my-module;
    cpa-manager-plus = ./cpa-manager-plus;
    matrix-pylon = ./matrix-pylon;
    napcat = ./napcat;
    proxy-checker = ./proxy-checker;
    resin = ./resin;
  };
in
modules
// {
  default = {
    imports = builtins.attrValues modules;
  };
}
