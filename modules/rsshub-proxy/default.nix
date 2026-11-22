{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.rsshubProxy;
  caddy = config.services.caddy;
  stateDir = "/var/lib/rsshub-proxy";
  settings = pkgs.writeText "rsshub-proxy.json" (builtins.toJSON {
    inherit (cfg) sourceUrl fallbackSourceUrl extraBackends proxy;
    inherit stateDir;
    curl = lib.getExe pkgs.curl;
    caddy = lib.getExe caddy.package;
    caddyConfig = toString caddy.configFile;
  });
  runner = pkgs.writeShellScript "rsshub-proxy" ''
    exec ${lib.getExe pkgs.python3} ${./update.py} ${settings} "$@"
  '';
in {
  options.services.rsshubProxy = {
    enable = lib.mkEnableOption "Caddy RSSHub proxy with periodically refreshed public instances";

    virtualHost = lib.mkOption {
      type = lib.types.str;
      default = ":80";
      description = "Caddy virtual host to serve the RSSHub proxy.";
    };

    pathPrefix = lib.mkOption {
      type = lib.types.strMatching "/[A-Za-z0-9/_-]+";
      default = "/rsshub";
      description = "Request path prefix, without a trailing slash; stripped before proxying.";
    };

    sourceUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://docs.rsshub.app/guide/instances";
      description = "RSSHub documentation page containing the instances table.";
    };

    fallbackSourceUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "https://raw.githubusercontent.com/RSSNext/rsshub-docs/main/.vitepress/theme/components/InstanceList.vue";
      description = "Official instance-list source to use if the documentation page cannot be parsed or fetched; null disables the fallback.";
    };

    extraBackends = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["http://127.0.0.1:1200" "https://rsshub.example.com"];
      description = ''
        Additional HTTP(S) backend origins. Paths, credentials, queries and
        fragments are not supported. HTTP and HTTPS backends must use different
        ports because Caddy's TLS transport is selected by port.
      '';
    };

    proxy = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "http://127.0.0.1:10807";
      description = "Optional HTTP(S) or SOCKS5 proxy for fetching the list and reaching backends. Requires Caddy's network_proxy url module.";
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "12h";
      description = "Interval between instance-list refreshes (systemd time span).";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = caddy.enable && caddy.adapter == "caddyfile" && !caddy.resume;
        message = "services.rsshubProxy requires Caddy enabled with the caddyfile adapter and resume disabled.";
      }
      {
        assertion = !lib.hasSuffix "/" cfg.pathPrefix;
        message = "services.rsshubProxy.pathPrefix must not end with a slash.";
      }
    ];

    services.caddy.virtualHosts.${cfg.virtualHost}.extraConfig = ''
      handle_path ${cfg.pathPrefix}/* {
        import ${stateDir}/upstreams.caddy
      }
    '';

    # Initialize from the cached list and current Nix options without blocking
    # Caddy startup on network access. A fresh install uses extraBackends or 503
    # until the first successful refresh.
    systemd.services.caddy = {
      preStart = "${runner} init";
      serviceConfig = {
        StateDirectory = ["rsshub-proxy"];
        ReadWritePaths = [stateDir];
      };
    };

    systemd.services.rsshub-proxy-update = {
      description = "Refresh Caddy RSSHub public instances";
      wants = ["network-online.target"];
      after = ["network-online.target" "caddy.service"];
      partOf = ["caddy.service"];
      # Reloading the complete Caddyfile needs the same environment, including
      # DNS-provider credentials and any placeholders used elsewhere in it.
      inherit (config.systemd.services.caddy) environment;
      serviceConfig = (import ../../lib/service-hardening.nix {inherit lib;}) // {
        Type = "oneshot";
        User = caddy.user;
        Group = caddy.group;
        EnvironmentFile = config.systemd.services.caddy.serviceConfig.EnvironmentFile or [];
        StateDirectory = "rsshub-proxy";
        StateDirectoryMode = "0750";
        UMask = "0027";
        ExecStart = "${runner} update";
        TimeoutStartSec = "3min";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [stateDir];
      };
    };

    systemd.timers.rsshub-proxy-update = {
      description = "Periodically refresh RSSHub public instances";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitInactiveSec = cfg.interval;
        RandomizedDelaySec = "30s";
      };
    };
  };
}
