{ config, lib, pkgs, ... }:

let
  cfg = config.services.srsDecompile;

  # 运行脚本（位于 Nix store，不可被运行用户篡改）
  runner = pkgs.writeShellScript "srs-decompile-run" ''
    set -euo pipefail
    umask 077

    out_dir="${cfg.outputDir}"
    mkdir -p "$out_dir"

    url_basename() {
      local url="$1"
      # 去掉 query string
      url="''${url%%\?*}"
      printf '%s' "''${url##*/}"
    }

    for url in ${lib.concatStringsSep " " (map lib.escapeShellArg cfg.urls)}; do
      fname="$(url_basename "$url")"
      if [ -z "$fname" ] || [ "$fname" = "/" ] || printf '%s' "$fname" | grep -q '/'; then
        echo "Invalid filename from URL: $url" >&2
        exit 1
      fi

      srs_path="$out_dir/$fname"
      base="''${fname%.*}"
      json_path="$out_dir/$base.json"
      txt_path="$out_dir/$base.cidr.txt"

      echo "==> Download: $url"
      ${pkgs.curl}/bin/curl \
        --fail --location \
        --proto '=https' --tlsv1.2 \
        --retry 3 --retry-delay 1 \
        -o "$srs_path" \
        "$url"

      echo "==> Decompile: $srs_path -> $json_path"
      ${pkgs.sing-box}/bin/sing-box rule-set decompile "$srs_path" -o "$json_path"

      echo "==> Extract CIDR: $json_path -> $txt_path"
      ${pkgs.jq}/bin/jq -r '.. | .ip_cidr? // empty | .[]' "$json_path" \
        | ${pkgs.gawk}/bin/awk 'NF' \
        | ${pkgs.coreutils}/bin/sort -u \
        > "$txt_path"

      echo "==> Done: $txt_path ($(${pkgs.coreutils}/bin/wc -l < "$txt_path") lines)"
    done
  '';
in
{
  options.services.srsDecompile = {
    enable = lib.mkEnableOption "periodically decompile sing-box .srs to CIDR text (hardened)";

    urls = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "https://github.com/SagerNet/sing-geoip/raw/refs/heads/rule-set/geoip-cn.srs"
        "https://github.com/SagerNet/sing-geoip/raw/refs/heads/rule-set/geoip-us.srs"
      ];
      description = "List of .srs URLs to download and process.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "caddy";
      description = "User to run the job as (should exist).";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "caddy";
      description = "Group to run the job as.";
    };

    # 安全默认：写到 /var/lib 下（配合 ProtectSystem=strict + ReadWritePaths）
    outputDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/srs-decompile";
      description = "Directory to write downloaded .srs, decompiled .json and extracted .cidr.txt.";
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "12h";
      description = "Run interval for the timer (systemd time span).";
    };

    onBoot = lib.mkOption {
      type = lib.types.str;
      default = "5min";
      description = "Delay after boot before the first run (systemd time span).";
    };

    randomizedDelay = lib.mkOption {
      type = lib.types.str;
      default = "30min";
      description = "Randomized delay to avoid thundering herd (systemd time span).";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.urls != [ ];
        message = "services.srsDecompile.urls must be set (non-empty).";
      }
      {
        assertion = builtins.hasAttr cfg.user config.users.users;
        message = "services.srsDecompile.user '${cfg.user}' does not exist. Enable services.caddy or create the user.";
      }
    ];

    systemd.services.srs-decompile = {
      description = "Decompile sing-box rule-set .srs and extract CIDR (hardened)";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];

      # 让 PATH 里有基础命令（尽量少依赖环境）
      path = with pkgs; [ coreutils curl jq sing-box gawk gnugrep gnused ];

      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        UMask = "0077";

        # 让 systemd 管理/创建 state 目录：/var/lib/srs-decompile
        StateDirectory = "srs-decompile";
        StateDirectoryMode = "0750";

        WorkingDirectory = cfg.outputDir;

        # --- Hardening ---
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;

        ProtectSystem = "strict";
        ProtectHome = true;

        ProtectControlGroups = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectHostname = true;

        LockPersonality = true;
        MemoryDenyWriteExecute = true;

        RestrictSUIDSGID = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RemoveIPC = true;

        SystemCallArchitectures = "native";

        # 需要联网下载：仅放行常用地址族
        RestrictAddressFamilies = "AF_UNIX AF_INET AF_INET6";

        # 不给任何 capabilities
        CapabilityBoundingSet = "";
        AmbientCapabilities = "";

        # ProtectSystem=strict 下，明确只允许写 outputDir
        ReadWritePaths = [ cfg.outputDir ];

        Nice = 10;
        IOSchedulingClass = "idle";
        TimeoutStartSec = "10min";
      };

      script = ''
        exec ${runner}
      '';
    };

    systemd.timers.srs-decompile = {
      description = "Run srs-decompile periodically";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = cfg.onBoot;
        OnUnitActiveSec = cfg.interval;
        Persistent = true;
        RandomizedDelaySec = cfg.randomizedDelay;
        AccuracySec = "1min";
      };
    };
  };
}
