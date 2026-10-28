{
  lib,
  stdenvNoCC,
  python3,
  makeWrapper,
  dict,
  dico,
}: let
  python = python3.withPackages (ps: [
    ps.pyglossary
    (ps.callPackage ./lemminflect.nix {})
    ps.fugashi
    ps.unidic-lite
  ]);
in
  stdenvNoCC.mkDerivation {
    pname = "dict-convert";
    version = "1.0.0";
    src = ./.;
    nativeBuildInputs = [makeWrapper];
    nativeCheckInputs = [python dict dico];
    dontBuild = true;
    doCheck = stdenvNoCC.buildPlatform.canExecute stdenvNoCC.hostPlatform;
    checkPhase = ''
      runHook preCheck
      DICOD=${lib.getBin dico}/bin/dicod DICTD=${dict}/sbin/dictd \
        ${python}/bin/python3 -m unittest -v test_convert
      runHook postCheck
    '';
    installPhase = ''
      runHook preInstall
      install -Dm644 convert.py "$out/lib/dict-convert/convert.py"
      install -Dm644 morphology.py "$out/lib/dict-convert/morphology.py"
      makeWrapper ${python}/bin/python3 "$out/bin/dict-convert" \
        --add-flags "$out/lib/dict-convert/convert.py" \
        --prefix PATH : ${lib.makeBinPath [dict]}
      runHook postInstall
    '';
    meta = {
      description = "Convert PyGlossary dictionaries to dictzip with English and Japanese inflection indexes";
      license = lib.licenses.mit;
      platforms = lib.platforms.unix;
      mainProgram = "dict-convert";
    };
  }
