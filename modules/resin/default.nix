{ config, lib, pkgs, ... }:

let
  cfg = config.services.resin;
in {
  options.services.resin = {
    enable = lib.mkEnableOption "Resin — a high-performance proxy pool gateway";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../pkgs/resin { };
      defaultText = lib.literalExpression "pkgs.resin";
      description = "The Resin package to use.";
    };

    authVersion = lib.mkOption {
      type = lib.types.enum [ "V1" "LEGACY_V0" ];
      description = ''
        Auth version: V1 (recommended for new deployments) or LEGACY_V0 (upgrade compatibility).
      '';
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Address to listen on for both proxy and admin HTTP.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 2260;
      description = "HTTP proxy and Web admin dashboard port.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/resin";
      description = "Persistent state directory (node data, leases, metrics).";
    };

    cacheDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/cache/resin";
      description = "Cache directory (temp data, GeoIP DB).";
    };

    logDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/log/resin";
      description = "Request and runtime log directory.";
    };

    proxyBypass = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "localhost;127.*;10.*;192.168.*;<local>";
      description = ''
        Proxy bypass rules (semicolon/comma/newline separated). Matching requests
        are forwarded directly instead of through the proxy pool.
      '';
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        RESIN_NODE_DNS_UPSTREAM = "https://dns.google/dns-query";
        RESIN_PROXY_BYPASS = "localhost;127.*;10.*";
      };
      description = ''
        Extra environment variables for advanced Resin configuration.
        See https://github.com/Resinat/Resin for all options.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/secrets/resin";
      description = ''
        Environment file containing RESIN_ADMIN_TOKEN (required) and RESIN_PROXY_TOKEN (required).
        Format: one KEY=value per line. Tokens can be set to empty with KEY= (bare key with no value).
        This file should NOT be in the Nix store — use agenix, sops-nix, or a manual path.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.resin = { };
    users.users.resin = {
      isSystemUser = true;
      group = "resin";
      home = cfg.stateDir;
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 resin resin -"
      "d ${cfg.cacheDir} 0750 resin resin -"
      "d ${cfg.logDir} 0750 resin resin -"
    ];

    systemd.services.resin = {
      description = "Resin Proxy Pool Gateway";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        RESIN_AUTH_VERSION = cfg.authVersion;
        RESIN_LISTEN_ADDRESS = cfg.listenAddress;
        RESIN_PORT = toString cfg.port;
        RESIN_STATE_DIR = cfg.stateDir;
        RESIN_CACHE_DIR = cfg.cacheDir;
        RESIN_LOG_DIR = cfg.logDir;
      } // lib.optionalAttrs (cfg.proxyBypass != null) {
        RESIN_PROXY_BYPASS = cfg.proxyBypass;
      } // cfg.settings;

      serviceConfig = {
        Type = "simple";
        User = "resin";
        Group = "resin";
        WorkingDirectory = cfg.stateDir;
        ExecStart = lib.getExe cfg.package;
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
        ReadWritePaths = [ cfg.stateDir cfg.cacheDir cfg.logDir ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        UMask = "0077";
      };
    };
  };
}
