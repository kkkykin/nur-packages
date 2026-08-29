{
  description = "My personal NUR repository";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  outputs =
    { self, nixpkgs }:
    let
      forAllSystems = nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed;
    in
    {
      nixosModules = import ./modules;

      legacyPackages = forAllSystems (system: import ./default.nix {
        pkgs = import nixpkgs { inherit system; };
      });
      packages = forAllSystems (system: nixpkgs.lib.filterAttrs (_: v: nixpkgs.lib.isDerivation v) self.legacyPackages.${system});

      apps = forAllSystems (system: {
        update = {
          type = "app";
          program = toString (
            nixpkgs.legacyPackages.${system}.writeShellScript "update" ''
              set -euo pipefail
              echo "=== nix flake update ==="
              ${nixpkgs.legacyPackages.${system}.nix}/bin/nix flake update
              echo "=== running passthru.updateScript for all packages ==="
              ./tools/update-package --all
            ''
          );
        };
        update-pkg = {
          type = "app";
          program = toString (
            nixpkgs.legacyPackages.${system}.writeShellScript "update-pkg" ''
              set -euo pipefail
              exec ./tools/update-package "$@"
            ''
          );
        };
      });
    };
}
