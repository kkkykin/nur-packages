{ lib, pkgs, config, ... }:

let
  cfg = config.services.hubproxy;

  tomlFormat = pkgs.formats.toml { };

  # 生成的 TOML（不含注释）
  generatedToml =
    tomlFormat.generate "hubproxy-config.toml" cfg.settings;

  # 支持：
  # - configText != null：完全使用用户给的 TOML（可保留注释）
  # - 否则用 settings 生成 + extraConfig 追加
  renderedConfig =
    if cfg.configText != null then
      pkgs.writeText "hubproxy-config.toml" cfg.configText
    else if cfg.extraConfig == "" then
      generatedToml
    else
      pkgs.runCommand "hubproxy-config.toml" { } ''
        cat ${generatedToml} > $out
        cat >> $out <<'EOF'
${cfg.extraConfig}
EOF
      '';

  configPath = "${cfg.dataDir}/${cfg.configFileName}";

  port = lib.attrByPath [ "server" "port" ] 5000 cfg.settings;
in
{
  options.services.hubproxy = {
    enable = lib.mkEnableOption "hubproxy service";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = pkgs.callPackage ../../pkgs/hubproxy { };
      defaultText = lib.literalExpression "pkgs.hubproxy";
      description = "hubproxy 软件包，例如 pkgs.hubproxy。";
    };

    createUser = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "是否创建系统用户/组（当 user/group 不是 root 时生效）。";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "hubproxy";
      description = "systemd 运行用户。";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "hubproxy";
      description = "systemd 运行组。";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/hubproxy";
      description = "工作目录/数据目录，配置文件会放到这里。";
    };

    configFileName = lib.mkOption {
      type = lib.types.str;
      default = "config.toml";
      description = "配置文件名（位于 dataDir 下）。";
    };

    # 用 settings 生成 TOML（不保留注释）
    settings = lib.mkOption {
      type = tomlFormat.type;
      default = {
        server = {
          host = "127.0.0.1";
          port = 5000;
          fileSize = 2147483648;
          enableH2C = true;
          enableFrontend = false;
        };

        rateLimit = {
          requestLimit = 500;
          periodHours = 3.0;
        };

        security = {
          whiteList = [
            "127.0.0.1"
          ];
          blackList = [
            # "192.168.100.1"
            # "192.168.100.0/24"
          ];
        };

        access = {
          whiteList = [ ];
          blackList = [
            # "baduser/malicious-repo"
            # "*/malicious-repo"
            # "baduser/*"
          ];
          proxy = "";
        };

        download = {
          maxImages = 10;
        };

        registries = {
          "ghcr.io" = {
            upstream = "ghcr.io";
            authHost = "ghcr.io/token";
            authType = "github";
            enabled = true;
          };
          "gcr.io" = {
            upstream = "gcr.io";
            authHost = "gcr.io/v2/token";
            authType = "google";
            enabled = true;
          };
          "quay.io" = {
            upstream = "quay.io";
            authHost = "quay.io/v2/auth";
            authType = "quay";
            enabled = true;
          };
          "registry.k8s.io" = {
            upstream = "registry.k8s.io";
            authHost = "registry.k8s.io";
            authType = "anonymous";
            enabled = true;
          };
        };

        tokenCache = {
          enabled = true;
          defaultTTL = "20m";
        };
      };
      description = ''
        hubproxy 的配置，会被生成 TOML 写到 dataDir/configFileName。
        注意：这里写的内容会进 Nix store，包含密码/Token 会泄露（world-readable）。
      '';
    };

    # 完全手写 TOML（保留注释/格式），优先级最高
    configText = lib.mkOption {
      type = lib.types.nullOr lib.types.lines;
      default = null;
      description = "直接写完整 TOML 配置（可保留注释）。设置后会忽略 settings。";
    };

    # 追加到生成的 TOML 后面（可写注释/自定义段落）
    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "附加到生成的 TOML 末尾的原始文本。";
    };

    # 如果程序需要参数（如 --config），就往这里加
    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "传给 hubproxy 的命令行参数（默认不传）。";
    };

    # 直接覆盖 ExecStart
    execStart = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        直接覆盖 systemd 的 ExecStart。
        例如："/nix/store/...-hubproxy/bin/hubproxy --config /var/lib/hubproxy/config.toml"
      '';
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "systemd Environment=...";
    };

    path = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "给服务补充 PATH（systemd.services.<name>.path）。";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "是否自动放行 settings.server.port 对应的 TCP 端口。";
    };

    serviceConfig = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "额外的 systemd serviceConfig 覆盖/补充。";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.package != null;
        message = "services.hubproxy.package。";
      }
    ];

    users.groups = lib.mkIf (cfg.createUser && cfg.group != "root") {
      ${cfg.group} = { };
    };

    users.users = lib.mkIf (cfg.createUser && cfg.user != "root") {
      ${cfg.user} = {
        isSystemUser = true;
        group = cfg.group;
        home = cfg.dataDir;
        createHome = true;
      };
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} - -"
    ];

    systemd.services.hubproxy =
      lib.mkMerge [
        {
          description = "hubproxy";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];

          preStart = ''
            mkdir -p ${lib.escapeShellArg cfg.dataDir}
            ln -sfT ${renderedConfig} ${lib.escapeShellArg configPath}
          '';

          environment = cfg.environment;
          path = cfg.path;

          serviceConfig = ({
            Type = "simple";
            User = cfg.user;
            Group = cfg.group;
            WorkingDirectory = cfg.dataDir;

            Restart = "always";
            RestartSec = 5;

            StandardOutput = "journal";
            StandardError = "journal";
            SyslogIdentifier = "hubproxy";
          } // cfg.serviceConfig);
        }

        # 默认：用脚本启动（更安全地处理参数转义）
        (lib.mkIf (cfg.execStart == null) {
          script = ''
            exec ${lib.getExe cfg.package} ${lib.escapeShellArgs cfg.extraArgs}
          '';
        })

        # 需要完全自定义 ExecStart 时用
        (lib.mkIf (cfg.execStart != null) {
          serviceConfig.ExecStart = cfg.execStart;
        })
      ];

    networking.firewall.allowedTCPPorts =
      lib.mkIf cfg.openFirewall [ port ];
  };
}
