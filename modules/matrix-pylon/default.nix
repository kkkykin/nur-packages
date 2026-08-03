{
  config,
  lib,
  ...
}:

let
  cfg = config.services.matrix-pylon;
in
{
  options.services.matrix-pylon = {
    enable = lib.mkEnableOption "matrix-pylon — a general-purpose Matrix bridge with Onebot11 support (OCI containers)";

    user = lib.mkOption {
      type = lib.types.str;
      default = "matrix-pylon";
      description = "User owning matrix-pylon data directories.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "matrix-pylon";
      description = "Group owning matrix-pylon data directories.";
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
      default = "lxduo/matrix-pylon:latest";
      description = "matrix-pylon container image.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/matrix-pylon";
      description = ''
        Data directory mounted at /data inside the container. Holds config.yaml
        and the generated registration.yaml. A default config.yaml is generated
        automatically on first start; edit it, then restart to generate the
        registration file. See https://docs.mau.fi/bridges/go/setup.html.
      '';
    };

    listenPort = lib.mkOption {
      type = lib.types.port;
      default = 29317;
      description = ''
        Host port published for the bridge's appservice listen port, mapped
        straight through (hostPort:containerPort). The image has no EXPOSE
        directive, so this only needs to match the `appservice` listen port in
        config.yaml. Set `publishPort = false` to not publish a host port
        (use host networking or a custom network instead).
      '';
    };

    publishPort = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to publish the appservice port to the host. Disable when using
        host networking or when no host port mapping is desired.
      '';
    };

    containerUid = lib.mkOption {
      type = lib.types.int;
      default = 1337;
      description = "UID the bridge process runs as inside the container (matches the image default).";
    };

    containerGid = lib.mkOption {
      type = lib.types.int;
      default = 1337;
      description = "GID the bridge process runs as inside the container (matches the image default).";
    };

    extraEnvironment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Extra environment variables passed to the matrix-pylon container.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/secrets/matrix-pylon";
      description = ''
        Environment file containing secrets.
      '';
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether the container should be started automatically.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to open the firewall for the matrix-pylon appservice port.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.dataDir;
    };
    users.groups.${cfg.group} = { };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} -"
    ];

    virtualisation.oci-containers = {
      backend = cfg.backend;

      containers.matrix-pylon = {
        image = cfg.image;
        autoStart = cfg.autoStart;

        # The image's entrypoint chowns /data to $UID:$GID and runs the bridge
        # via su-exec, so pin them to the configured in-container uid/gid.
        environment = {
          UID = toString cfg.containerUid;
          GID = toString cfg.containerGid;
        } // cfg.extraEnvironment;

        environmentFiles = lib.optional (cfg.environmentFile != null) cfg.environmentFile;

        volumes = [
          "${cfg.dataDir}:/data"
        ];

        ports = lib.optional cfg.publishPort "${toString cfg.listenPort}:${toString cfg.listenPort}";
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [
      cfg.listenPort
    ];
  };
}
