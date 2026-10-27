{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.dico;
  quote = builtins.toJSON;
  dbName = db: db.dbName or (lib.removePrefix "dict-db-" (lib.getName db));
  format = db: db.format or "dictd";
  command = args: quote (lib.escapeShellArgs args);
  address =
    if lib.hasInfix ":" cfg.listenAddress
    then "[${cfg.listenAddress}]"
    else cfg.listenAddress;

  # WordNet and Wiktionary do not expose dbName, and their file basenames
  # differ from their package names. Discover the index during the build.
  dictdDatabase = db:
    pkgs.runCommand "dico-dictd-${dbName db}" {} ''
      shopt -s nullglob
      if [ -f ${lib.escapeShellArg "${db}.index"} ]; then
        indexes=( ${lib.escapeShellArg "${db}.index"} )
      else
        indexes=( ${lib.escapeShellArg "${db}/share/dictd"}/*.index )
      fi
      if [ "''${#indexes[@]}" -ne 1 ]; then
        printf 'Dico: expected one dictd index in %s\n' ${lib.escapeShellArg (toString db)} >&2
        exit 1
      fi
      base="''${indexes[0]%.index}"
      mkdir -p "$out"
      ln -s "$base.index" "$out/database.index"
      if [ -f "$base.dict" ]; then
        ln -s "$base.dict" "$out/database.dict"
      else
        test -f "$base.dict.dz"
        ln -s "$base.dict.dz" "$out/database.dict.dz"
      fi
    '';

  databaseConfig = db: ''
    database {
      name ${quote (dbName db)};
      handler ${command (
      if format db == "stardict"
      then ["stardict" "${db}/${db.ifoFile or "share/stardict/${dbName db}.ifo"}"]
      else ["dictorg" "database=${dictdDatabase db}/database"]
    )};
    }
  '';

  configFile = pkgs.writeText "dicod.conf" ''
    listen ${quote "${address}:${toString cfg.port}"};
    pidfile "/run/dico/dicod.pid";
    ${lib.optionalString (lib.any (db: format db == "dictd") cfg.DBs) ''
      load-module dictorg {
        command "dictorg trim-ws sort";
      }
    ''}
    ${lib.optionalString (lib.any (db: format db == "stardict") cfg.DBs) ''
      load-module stardict {
        command ${command [
        "python"
        "load-path=${cfg.stardictModule}/share/dico/python"
        "init-script=stardict"
        "root-class=DicoModule"
      ]};
      }
    ''}
    ${lib.concatMapStringsSep "\n" databaseConfig cfg.DBs}
    ${cfg.extraConfig}
  '';
in {
  options.services.dico = {
    enable = lib.mkEnableOption "GNU Dico dictionary server";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../pkgs/dico {};
      defaultText = lib.literalExpression "pkgs.kkkykin.dico";
      description = "GNU Dico built with its Python database module enabled.";
    };

    stardictModule = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../pkgs/dico-stardict {};
      defaultText = lib.literalExpression "pkgs.kkkykin.dico-stardict";
      description = "Package providing share/dico/python/stardict.py.";
    };

    DBs = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      example = lib.literalExpression "[ pkgs.dictdDBs.wordnet ]";
      description = ''
        Dictionaries to serve. StarDict packages created by lib.makeStardictDB
        are detected by their format attribute. Other packages use the dictd
        layout, with one .index and its .dict or .dict.dz in share/dictd.
      '';
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "IP address on which to listen for DICT connections.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 2628;
      description = "TCP port for the DICT protocol.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the DICT TCP port in the firewall.";
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Additional dicod.conf statements appended to the generated configuration.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.all (db: lib.elem (format db) ["dictd" "stardict"]) cfg.DBs;
        message = "services.dico.DBs supports dictd and stardict dictionaries.";
      }
      {
        assertion = let names = map dbName cfg.DBs; in lib.length names == lib.length (lib.unique names);
        message = "services.dico.DBs must have unique dbName attributes.";
      }
      {
        assertion = !(config.services.dictd.enable && cfg.port == 2628);
        message = "Dico and dictd cannot both use port 2628; disable dictd or change services.dico.port.";
      }
    ];

    environment.systemPackages = [cfg.package cfg.stardictModule];
    environment.etc."dicod.conf".source = configFile;

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [cfg.port];

    systemd.services.dico = {
      description = "GNU Dico Dictionary Server";
      wantedBy = ["multi-user.target"];
      after = ["network.target"];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/dicod --foreground --stderr --config=${configFile}";
        DynamicUser = true;
        RuntimeDirectory = "dico";
        Restart = "on-failure";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
      };
    };
  };
}
