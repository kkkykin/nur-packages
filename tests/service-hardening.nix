# Evaluation regressions for the public module interfaces and generated units.
# nix-instantiate --eval --strict --json tests/service-hardening.nix --arg nixpkgs /path/to/nixpkgs
{
  nixpkgs,
  system ? "x86_64-linux",
}: let
  lib = import (nixpkgs + "/lib");
  pkgs = import nixpkgs {inherit system;};
  evaluate = extra:
    (import (nixpkgs + "/nixos/lib/eval-config.nix") {
      inherit system pkgs;
      modules = [
        (import ../modules).default
        {
          services.openlist = {
            enable = true;
            package = pkgs.hello;
          };
          services.hubproxy = {
            enable = true;
            package = pkgs.hello;
          };
          services.napcat = {
            enable = true;
            publishPorts = true;
          };
          services.matrix-pylon.enable = true;
          system.stateVersion = "25.05";
        }
        extra
      ];
    }).config;
  defaults = evaluate {};
  custom = evaluate {
    services.openlist.dataDir = "/srv/openlist";
    systemd.services.openlist.serviceConfig.ReadWritePaths = ["/srv/downloads"];
    services.hubproxy = {
      dataDir = "/srv/hubproxy";
      serviceConfig.PrivateTmp = false;
    };
    services.napcat.onebotListenAddress = "0.0.0.0";
    services.matrix-pylon.listenAddress = "192.0.2.1";
  };
  openlist = custom.systemd.services.openlist.serviceConfig;
  checks = {
    customStateDirectory =
      !(openlist ? StateDirectory)
      && builtins.elem "/srv/openlist" openlist.ReadWritePaths
      && builtins.elem "d /srv/openlist 0770 openlist openlist -" custom.systemd.tmpfiles.rules;
    sharedDownloads = builtins.elem "/srv/downloads" openlist.ReadWritePaths;
    hardeningCanBeOverridden = custom.systemd.services.hubproxy.serviceConfig.PrivateTmp == false;
    customHubproxyState = builtins.elem "/srv/hubproxy" custom.systemd.services.hubproxy.serviceConfig.ReadWritePaths;
    nativeUnitsAreSandboxed = lib.all (name:
      lib.hasInfix "NoNewPrivileges=true" defaults.systemd.units."${name}.service".text
      && lib.hasInfix "ProtectSystem=strict" defaults.systemd.units."${name}.service".text)
    ["openlist" "hubproxy"];
    loopbackPublishing =
      lib.all (port: lib.hasPrefix "127.0.0.1:" port)
      (defaults.virtualisation.oci-containers.containers.napcat.ports
        ++ defaults.virtualisation.oci-containers.containers.matrix-pylon.ports);
    remoteOnebotKeepsWebuiLocal =
      custom.virtualisation.oci-containers.containers.napcat.ports
      == ["127.0.0.1:6099:6099" "0.0.0.0:3001:3001" "0.0.0.0:3000:3000"];
    customPylonAddress =
      custom.virtualisation.oci-containers.containers.matrix-pylon.ports
      == ["192.0.2.1:29317:29317"];
    napcatPtraceRetained = defaults.virtualisation.oci-containers.containers.napcat.capabilities.SYS_PTRACE;
    containerPrivilegeEscalationDisabled =
      builtins.elem "--security-opt=no-new-privileges=true"
      defaults.virtualisation.oci-containers.containers.napcat.extraOptions;
  };
in
  assert lib.assertMsg (lib.all (result: result) (builtins.attrValues checks))
  "Service hardening regressions failed: ${lib.concatStringsSep ", " (builtins.attrNames (lib.filterAttrs (_: result: !result) checks))}"; checks
