{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.openlist;
  hardening = import ../../lib/service-hardening.nix {inherit lib;};
in {
  options.services.openlist = {
    enable = mkEnableOption "openlist daemon";

    package = mkOption {
      type = types.package;
      default = pkgs.openlist;
      description = "openlist binary package";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/openlist";
      description = "Data directory (also working directory)";
    };

    envFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = "/run/secrets/openlist";
      description = "Environment file (KEY=value) passed to systemd";
    };

    user  = mkOption {
      type = types.str;
      default = "openlist";
      description = "User to run openlist";
    };
  };

  config = mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.user;
    };
    users.groups.${cfg.user} = {};

    systemd.services.openlist = {
      description = "OpenList file browser & server";
      wantedBy    = [ "multi-user.target" ];
      after       = [ "network.target" ];

      serviceConfig = hardening // {
        User             = cfg.user;
        Group            = cfg.user;
        StateDirectory   = mkIf (cfg.dataDir == "/var/lib/openlist") "openlist";
        StateDirectoryMode = "0770";
        WorkingDirectory = cfg.dataDir;
        ExecStart        = "${cfg.package}/bin/OpenList server --data ${cfg.dataDir}";
        Restart          = "on-failure";
        EnvironmentFile  = mkIf (cfg.envFile != null) cfg.envFile;
        UMask            = "0002";
        ReadWritePaths   = [ cfg.dataDir ];
      };
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0770 ${cfg.user} ${cfg.user} -"
    ];
  };
}
