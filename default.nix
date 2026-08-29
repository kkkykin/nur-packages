# This file describes your repository contents.
# It should return a set of nix derivations
# and optionally the special attributes `lib`, `modules` and `overlays`.
# It should NOT import <nixpkgs>. Instead, you should take pkgs as an argument.
# Having pkgs default to <nixpkgs> is fine though, and it lets you use short
# commands such as:
#     nix-build -A mypackage
#  or nix build ".#mypackage"

{ pkgs ? import <nixpkgs> { } }:

{
  # The `lib`, `modules`, and `overlays` names are special
  lib = import ./lib { inherit pkgs; }; # functions
  modules = import ./modules; # NixOS modules
  overlays = import ./overlays; # nixpkgs overlays

  # snow-ai = pkgs.callPackage ./pkgs/snow-ai { };
  # uni-api = pkgs.callPackage ./pkgs/uni-api { };
  # c7zip = pkgs.callPackage ./pkgs/c7zip { };
  # c7zip-unfree = pkgs.callPackage ./pkgs/c7zip {
  #   enableUasm = true;
  #   uasm = pkgs.uasm;
  # };
  # cataclysm-dda-ncurses = pkgs.cataclysm-dda.override {
  #   tiles = false;
  # };
  # proxy-checker = pkgs.callPackage ./pkgs/proxy-checker { };
  # fingerprint-chromium = pkgs.callPackage ./pkgs/fingerprint-chromium { };
  montecarlo-ip-searcher = pkgs.callPackage ./pkgs/montecarlo-ip-searcher {};
  # cli-proxy-api = pkgs.callPackage ./pkgs/cliproxyapi {};
  cpa-manager-plus = pkgs.callPackage ./pkgs/cpa-manager-plus { };
  resin = pkgs.callPackage ./pkgs/resin { };
  # dwarf-fortress-terminal =
  #   (pkgs.dwarf-fortress-packages.dwarf-fortress-full.override {
  #     enableTextMode = true;
  #   }).overrideAttrs (_old: {
  #     # ci.nix 会过滤 preferLocalBuild=true 的包（视为不可缓存），
  #     # 为了进入 cacheOutputs 并推送到 Cachix，这里显式关闭它。
  #     preferLocalBuild = false;
  #   });
  # axonhub = pkgs.callPackage ./pkgs/axonhub { };
  # example-package = pkgs.callPackage ./pkgs/example-package { };
  # some-qt5-package = pkgs.libsForQt5.callPackage ./pkgs/some-qt5-package { };
  # ...
}
