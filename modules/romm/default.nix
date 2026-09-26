{ config, lib, ... }:

let
  cfg = config.services.romm;

  libraryDir =
    if cfg.libraryDir == null
    then "${cfg.dataDir}/library"
    else cfg.libraryDir;

  assetsDir =
    if cfg.assetsDir == null
    then "${cfg.dataDir}/assets"
    else cfg.assetsDir;

  configDir =
    if cfg.configDir == null
    then "${cfg.dataDir}/config"
    else cfg.configDir;

  resourcesDir =
    if cfg.resourcesDir == null
    then "${cfg.dataDir}/resources"
    else cfg.resourcesDir;

in
{
  options.services.romm = {

    enable = lib.mkEnableOption "RomM ROM Manager (OCI containers)";


    user = lib.mkOption {
      type = lib.types.str;
      default = "romm";
      description = "User owning RomM data directories";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "romm";
      description = "Group owning RomM data directories";
    };


    backend = lib.mkOption {
      type = lib.types.enum [
        "docker"
        "podman"
      ];
      default = "podman";
      description = "OCI container backend";
    };


    image = lib.mkOption {
      type = lib.types.str;
      default = "rommapp/romm:latest";
      description = "RomM container image";
    };


    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/romm";
      description = "Base data directory for RomM";
    };


    libraryDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "ROM library directory";
    };

    assetsDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Saves, states, screenshots directory";
    };

    configDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "RomM config directory";
    };

    resourcesDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "IGDB resources directory";
    };


    redisVolumeName = lib.mkOption {
      type = lib.types.str;
      default = "romm_redis_data";
      description = "Redis volume name";
    };


    listenPort = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Host port for RomM web interface";
    };


    authSecretKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        RomM auth secret key.
        Generate with:
          openssl rand -hex 32
      '';
    };


    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Environment file containing secrets.

        Example:
          ROMM_AUTH_SECRET_KEY=xxx
          DB_PASSWD=xxx
      '';
    };


    hostName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Public hostname";
    };


    database = {

      driver = lib.mkOption {
        type = lib.types.enum [
          "mariadb"
          "mysql"
          "postgresql"
        ];
        default = "mariadb";
      };


      host = lib.mkOption {
        type = lib.types.str;
        default = "romm-db";
      };


      port = lib.mkOption {
        type = lib.types.port;
        default = 3306;
      };


      name = lib.mkOption {
        type = lib.types.str;
        default = "romm";
      };


      user = lib.mkOption {
        type = lib.types.str;
        default = "romm-user";
      };


      password = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };


      rootPassword = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
    };


    extraEnvironment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Extra environment variables";
    };


    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };


    restartPolicy = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Container restart policy.
        Example: unless-stopped
      '';
    };


    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
  };


  config = lib.mkIf cfg.enable {

    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
    };

    users.groups.${cfg.group} = {};


    virtualisation.oci-containers = {
      backend = cfg.backend;

      containers.romm = {

        image = cfg.image;

        autoStart = cfg.autoStart;


        environment =
          {
            DB_HOST = cfg.database.host;
            DB_NAME = cfg.database.name;
            DB_USER = cfg.database.user;
            DB_PORT = toString cfg.database.port;

            ROMM_DB_DRIVER = cfg.database.driver;
          }

          // lib.optionalAttrs (cfg.authSecretKey != null) {
            ROMM_AUTH_SECRET_KEY = cfg.authSecretKey;
          }

          // lib.optionalAttrs (cfg.database.password != null) {
            DB_PASSWD = cfg.database.password;
          }

          // lib.optionalAttrs (cfg.hostName != null) {
            ROMM_BASE_URL =
              "https://${cfg.hostName}";
          }

          // cfg.extraEnvironment;


        environmentFiles =
          lib.optional (cfg.environmentFile != null)
            cfg.environmentFile;


        volumes = [
          "${libraryDir}:/romm/library"
          "${assetsDir}:/romm/assets"
          "${configDir}:/romm/config"
          "${resourcesDir}:/romm/resources"

          "${cfg.redisVolumeName}:/redis-data"
        ];


        ports = [
          "${toString cfg.listenPort}:8080"
        ];


        extraOptions =
          lib.optional (cfg.restartPolicy != null)
            "--restart=${cfg.restartPolicy}";
      };
    };


    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 ${cfg.user} ${cfg.group} -"

      "d ${libraryDir} 0755 ${cfg.user} ${cfg.group} -"
      "d ${assetsDir} 0755 ${cfg.user} ${cfg.group} -"
      "d ${configDir} 0755 ${cfg.user} ${cfg.group} -"
      "d ${resourcesDir} 0755 ${cfg.user} ${cfg.group} -"
    ];


    networking.firewall.allowedTCPPorts =
      lib.mkIf cfg.openFirewall [
        cfg.listenPort
      ];
  };
}
