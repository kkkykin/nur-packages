{
  lib,
  stdenvNoCC,
  python3,
  gzip,
}:
# Same argument order as nixpkgs' makeDictdDB: src, name, subdir, locale.
src: dbName: subdir: locale:
assert lib.assertMsg (builtins.match "[A-Za-z0-9][A-Za-z0-9_.-]*" dbName != null)
"makeStardictDB: dbName must be a safe dictionary basename";
  stdenvNoCC.mkDerivation {
    name = "stardict-db-${dbName}";
    inherit src dbName locale;
    nativeBuildInputs = [gzip python3];
    dontBuild = true;
    dontConfigure = true;

    # Preserve the archive root so subdir has the same meaning as makeDictdDB.
    sourceRoot = ".";

    installPhase = ''
      runHook preInstall
      shopt -s nullglob
      dictionaries=( ${lib.escapeShellArg subdir}/*.ifo )
      if [ "''${#dictionaries[@]}" -ne 1 ]; then
        printf 'makeStardictDB: expected one .ifo file in %s\n' ${lib.escapeShellArg subdir} >&2
        exit 1
      fi
      base="''${dictionaries[0]%.ifo}"
      destination="$out/share/stardict"
      mkdir -p "$destination"
      cp "$base.ifo" "$destination/${dbName}.ifo"
      for suffix in idx dict; do
        if [ -f "$base.$suffix" ]; then
          cp "$base.$suffix" "$destination/${dbName}.$suffix"
        else
          case "$suffix" in
            idx) compressed="$base.idx.gz" ;;
            dict) compressed="$base.dict.dz" ;;
          esac
          gzip -dc "$compressed" > "$destination/${dbName}.$suffix"
        fi
      done
      if [ -f "$base.syn" ]; then
        cp "$base.syn" "$destination/${dbName}.syn"
      fi
      for document in ${lib.escapeShellArg subdir}/{COPYING,LICENSE,README,INSTALL,AUTHORS}*; do
        if [ -f "$document" ]; then
          mkdir -p "$out/share/doc/stardict/${dbName}"
          cp "$document" "$out/share/doc/stardict/${dbName}/"
        fi
      done
      printf '%s\n' ${lib.escapeShellArg locale} > "$destination/locale"
      python3 ${./dico-stardict/stardict.py} "$destination/${dbName}.ifo" --check
      runHook postInstall
    '';

    passthru = {
      format = "stardict";
      ifoFile = "share/stardict/${dbName}.ifo";
    };

    meta = {
      description = "StarDict dictionary: ${dbName}";
      platforms = lib.platforms.unix;
    };
  }
