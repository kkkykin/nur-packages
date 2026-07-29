{ config, lib, pkgs, ... }:

let
  cfg = config.services.proxy-checker;
in {
  options.services.proxy-checker = {
    enable = lib.mkEnableOption "Proxy Checker — a self-hosted proxy checker panel";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../pkgs/proxy-checker { };
      defaultText = lib.literalExpression "pkgs.proxy-checker";
      description = "The proxy-checker package to use.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8888;
      description = "HTTP server port.";
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        AUTH_PASSWORD = "my-secure-password";
        MAX_CONCURRENT = "50";
      };
      description = ''
        Extra environment variables passed to the service.
        See https://github.com/strongshuai/proxy-checker for all options.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/secrets/proxy-checker";
      description = ''
        Optional environment file for secrets (e.g. AUTH_PASSWORD).
        Values from this file override settings from the Nix option.
      '';
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/proxy-checker";
      description = "Data directory for checked proxies, repo data, logs, etc.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.proxy-checker = { };
    users.users.proxy-checker = {
      isSystemUser = true;
      group = "proxy-checker";
      home = cfg.dataDir;
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 proxy-checker proxy-checker -"
    ];

    systemd.services.proxy-checker = {
      description = "Proxy Checker";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        PORT = toString cfg.port;
      } // cfg.settings;

      serviceConfig = {
        Type = "simple";
        User = "proxy-checker";
        Group = "proxy-checker";
        WorkingDirectory = cfg.dataDir;
        ExecStart = "${cfg.package}/bin/proxy-checker";
        Restart = "on-failure";
        RestartSec = 3;
        EnvironmentFile = lib.optional (cfg.environmentFile != null) cfg.environmentFile;

        # Hardening
        CapabilityBoundingSet = "";
        LockPersonality = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ cfg.dataDir ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        UMask = "0077";
      };
    };
  };
}
