{
  lib,
  stdenvNoCC,
  python3,
}:
stdenvNoCC.mkDerivation {
  pname = "dico-stardict";
  version = "1.0.0";
  src = ./.;
  dontBuild = true;
  nativeCheckInputs = [python3];
  doCheck = true;

  checkPhase = ''
    runHook preCheck
    python3 -m unittest -v test_stardict
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 stardict.py "$out/share/dico/python/stardict.py"
    mkdir -p "$out/bin"
    cat > "$out/bin/stardict-query" <<EOF
    #!${stdenvNoCC.shell}
    exec ${python3}/bin/python3 "$out/share/dico/python/stardict.py" "\$@"
    EOF
    chmod +x "$out/bin/stardict-query"
    runHook postInstall
  '';

  meta = {
    description = "StarDict Python backend for GNU Dico and dictionary query tool";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    mainProgram = "stardict-query";
  };
}
