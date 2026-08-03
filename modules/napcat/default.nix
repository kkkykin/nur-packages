{
  config,
  lib,
  ...
}:

let
  cfg = config.services.napcat;

  # Directory layout under cfg.dataDir mirrors the in-container paths so the
  # mounts stay stable regardless of the backend.
  configDir = "${cfg.dataDir}/config";
  qqDir = "${cfg.dataDir}/QQ";
  pluginsDir = "${cfg.dataDir}/plugins";
in
{
  options.services.napcat = {
    enable = lib.mkEnableOption "NapCatQQ — an OneBot11 protocol QQ bot framework (OCI containers)";

    user = lib.mkOption {
      type = lib.types.str;
      default = "napcat";
      description = "User owning NapCat data directories.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "napcat";
      description = "Group owning NapCat data directories.";
    };

    uid = lib.mkOption {
      type = lib.types.int;
      default = 1337;
      description = ''
        UID of the NapCat system user that owns the data directories. It is
        also passed to the container as NAPCAT_UID, so the files NapCat writes
        on the mounted volumes stay owned by this host user. A NixOS system
        user is allocated a dynamic UID otherwise, which cannot be pinned here.
      '';
    };

    gid = lib.mkOption {
      type = lib.types.int;
      default = 1337;
      description = ''
        GID of the NapCat system group that owns the data directories. Also
        passed to the container as NAPCAT_GID (see `uid`).
      '';
    };

    backend = lib.mkOption {
      type = lib.types.enum [
        "docker"
        "podman"
      ];
      default = "podman";
      description = "OCI container backend.";
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "mlikiowa/napcat-docker:latest";
      description = "NapCat container image.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/napcat";
      description = "Base data directory for NapCat. Holds NapCat config, QQ persistent data and plugins.";
    };

    webuiPort = lib.mkOption {
      type = lib.types.port;
      default = 6099;
      description = "Host port for the NapCat WebUI (served at /webui).";
    };

    onebotWsPort = lib.mkOption {
      type = lib.types.port;
      default = 3001;
      description = "Host port for the OneBot11 WebSocket upstream/connections.";
    };

    onebotHttpPort = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "Host port for the OneBot11 HTTP API.";
    };

    extraEnvironment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        ACCOUNT = "123456789";
      };
      description = ''
        Extra environment variables passed to the NapCat container.

        NapCat itself runs the negotiated account login through the WebUI or a
        QR code shown in the container logs, so usually only NAPCAT_UID /
        NAPCAT_GID (handled automatically by this module) need to be set here.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/secrets/napcat";
      description = ''
        Environment file containing secrets.

        Example:
          ACCOUNT=123456789
          WEBUI_TOKEN=xxx
      '';
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether the container should be started automatically.";
    };

    restartPolicy = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "unless-stopped";
      example = "always";
      description = ''
        Container restart policy.
      '';
    };

    capabilities = lib.mkOption {
      type = lib.types.attrsOf lib.types.bool;
      default = {};
      description = "Linux capabilities added to the NapCat container.";
    };

    extraOptions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "--network=host" ];
      description = "Extra command line options passed to the container runtime.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to open the firewall for the NapCat WebUI and OneBot ports.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.dataDir;
      uid = cfg.uid;
    };
    users.groups.${cfg.group} = {
      gid = cfg.gid;
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} -"
      "d ${configDir} 0750 ${cfg.user} ${cfg.group} -"
      "d ${qqDir} 0750 ${cfg.user} ${cfg.group} -"
      "d ${pluginsDir} 0750 ${cfg.user} ${cfg.group} -"
    ];

    virtualisation.oci-containers = {
      backend = cfg.backend;

      containers.napcat = {
        image = cfg.image;
        autoStart = cfg.autoStart;

        # NapCat drops privileges to the container user via NAPCAT_UID/GID, so
        # pin them to the host system user/group owning the data directories.
        environment = {
          NAPCAT_UID = toString config.users.users.${cfg.user}.uid;
          NAPCAT_GID = toString config.users.groups.${cfg.group}.gid;
        } // cfg.extraEnvironment;

        environmentFiles = lib.optional (cfg.environmentFile != null) cfg.environmentFile;

        volumes = [
          "${configDir}:/app/napcat/config"
          "${qqDir}:/app/.config/QQ"
          "${pluginsDir}:/app/napcat/plugins"
        ];

        ports = [
          "${toString cfg.webuiPort}:6099"
          "${toString cfg.onebotWsPort}:3001"
          "${toString cfg.onebotHttpPort}:3000"
        ];

        # NapCat needs SYS_PTRACE and seccomp unconfined.
        capabilities = {
          SYS_PTRACE = true;
        } // cfg.capabilities;

        # Restart policy joins any user-supplied extra options.
        extraOptions =
          cfg.extraOptions
          ++ [ "--security-opt=seccomp=unconfined" ]
          ++ lib.optional (cfg.restartPolicy != null) "--restart=${cfg.restartPolicy}";
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [
      cfg.webuiPort
      cfg.onebotWsPort
      cfg.onebotHttpPort
    ];
  };
}
