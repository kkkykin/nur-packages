{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.cpa-manager-plus;
in
{
  options.services.cpa-manager-plus = {
    enable = lib.mkEnableOption "CPA Manager Plus Manager Server";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../pkgs/cpa-manager-plus { };
      defaultText = lib.literalExpression "pkgs.cpa-manager-plus";
      description = "The CPA Manager Plus package to use.";
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        LOG_LEVEL = "info";
      };
      description = "Environment variables used to configure CPA Manager Plus.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/secrets/cpa-manager-plus";
      description = ''
        Optional environment file containing secrets, such as CPAMP_ADMIN_KEY.
      '';
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = ":18317";
      description = "Address and port on which CPA Manager Plus listens.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/cpa-manager-plus";
      description = "Directory used to store CPA Manager Plus data.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.cpa-manager-plus = { };

    users.users.cpa-manager-plus = {
      isSystemUser = true;
      group = "cpa-manager-plus";
      home = cfg.dataDir;
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 cpa-manager-plus cpa-manager-plus -"
    ];

    systemd.services.cpa-manager-plus = {
      description = "CPA Manager Plus Manager Server";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        HTTP_ADDR = cfg.listenAddress;
        USAGE_DATA_DIR = cfg.dataDir;
      } // cfg.settings;

      serviceConfig = {
        Type = "simple";
        User = "cpa-manager-plus";
        Group = "cpa-manager-plus";
        WorkingDirectory = cfg.dataDir;
        ExecStart = lib.getExe cfg.package;
        Restart = "on-failure";
        RestartSec = 3;
        EnvironmentFile = lib.optional (cfg.environmentFile != null) cfg.environmentFile;

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
