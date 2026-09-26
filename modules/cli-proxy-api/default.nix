{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.cli-proxy-api;
in
{

  options.services.cli-proxy-api = {
    enable = mkEnableOption "CLIProxyAPI service";

    package = mkOption {
      type = types.package;
      default = pkgs.nur.repos.xddxdd.cliproxyapi;
      defaultText = literalExpression "pkgs.nur.repos.xddxdd.cliproxyapi";
      description = "CLIProxyAPI package to run";
    };

    configFile = mkOption {
      type = types.path;
      example = "/etc/cli-proxy-api/config.yaml";
      description = "Path to CLIProxyAPI config.yaml (managed outside Nix)";
    };

    user = mkOption {
      type = types.str;
      default = "cli-proxy-api";
    };

    group = mkOption {
      type = types.str;
      default = "cli-proxy-api";
    };

    homeDir = mkOption {
      type = types.path;
      default = "/var/lib/cli-proxy-api";
    };

    environmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to an environment file.
      '';
      example = "/etc/nixos/cli-proxy-cli.env";
    };

  };

  config = mkIf cfg.enable {

    users.groups.${cfg.group} = {};

    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.homeDir;
      createHome = true;
      homeMode = "0770";
      description = "CLIProxyAPI service user";
    };

    systemd.services.cli-proxy-api = {
      description = "CLIProxyAPI - AI Proxy Server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.homeDir;
        EnvironmentFile = mkIf (cfg.environmentFile != null) [ cfg.environmentFile ];

        ExecStart = "${lib.getExe cfg.package} -config ${cfg.configFile}";

        Restart = "on-failure";
        RestartSec = "5s";

        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        RestrictRealtime = true;
        RestrictNamespaces = true;
        LockPersonality = true;

        ReadWritePaths = [ cfg.homeDir ];
      };
    };
  };
}
