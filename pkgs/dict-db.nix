{
  lib,
  stdenvNoCC,
  callPackage,
  unzip,
}: {
  src,
  dbName,
  # Set for a file inside a source directory or archive. Omit for a single file.
  inputFile ? null,
  inputFormat ? "",
  languages ? [],
  readOptions ? {},
  locale ? "en_US.UTF-8",
  converter ? callPackage ./dict-convert {},
  meta ? {},
}:
assert lib.assertMsg (builtins.match "[A-Za-z0-9][A-Za-z0-9_-]*" dbName != null)
"makeDictdDB: dbName must contain only letters, digits, underscores and hyphens";
assert lib.assertMsg (lib.all (language: lib.elem language ["en" "ja"]) languages)
"makeDictdDB: languages must be a list containing en and/or ja";
assert lib.assertMsg (inputFile
  == null
  || (inputFile != "" && !(lib.hasPrefix "/" inputFile) && !(lib.elem ".." (lib.splitString "/" inputFile))))
"makeDictdDB: inputFile must be a relative path inside src";
  stdenvNoCC.mkDerivation {
    name = "dict-db-${dbName}";
    inherit src dbName locale;
    nativeBuildInputs = [converter unzip];
    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      mkdir -p source "$out/share/dictd"
      ${
        if inputFile == null
        then ''
          # Copy single-file inputs to a writable directory: some PyGlossary
          # readers decompress alongside their input. Keep the original extension.
          cp "$src" ${lib.escapeShellArg ("source/" + baseNameOf (toString src))}
          chmod u+w ${lib.escapeShellArg ("source/" + baseNameOf (toString src))}
          input="$PWD/"${lib.escapeShellArg ("source/" + baseNameOf (toString src))}
        ''
        else ''
          if [ -d "$src" ]; then
            cp -R "$src"/. source/
          else
            (cd source; unpackFile "$src")
          fi
          chmod -R u+w source
          input="$PWD/source/"${lib.escapeShellArg inputFile}
        ''
      }
      dict-convert "$input" "$out/share/dictd/${dbName}" \
        --input-format ${lib.escapeShellArg inputFormat} \
        --read-options ${lib.escapeShellArg (builtins.toJSON readOptions)} \
        ${lib.escapeShellArgs (lib.concatMap (language: ["--language" language]) (lib.unique languages))}
      printf '%s\n' ${lib.escapeShellArg locale} > "$out/share/dictd/locale"
      runHook postInstall
    '';
    passthru = {
      format = "dictd";
      indexFile = "share/dictd/${dbName}.index";
      dataFile = "share/dictd/${dbName}.dict.dz";
    };
    meta = {description = "DICT dictionary: ${dbName}";} // meta;
  }
