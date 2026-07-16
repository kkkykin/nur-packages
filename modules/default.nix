let
  modules = {
    # Add your NixOS modules here
    #
    # my-module = ./my-module;
    cpa-manager-plus = ./cpa-manager-plus;
  };
in
modules
// {
  default = {
    imports = builtins.attrValues modules;
  };
}
