{
  lib,
  stdenv,
  dico,
  zlib,
  libunistring,
  python3,
}:
stdenv.mkDerivation {
  pname = "dico-stardict-native";
  version = "1.0.0";
  src = ./.;
  strictDeps = true;
  dontConfigure = true;
  nativeBuildInputs = [python3];
  buildInputs = [dico zlib libunistring];
  doCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;

  buildPhase = ''
    runHook preBuild
    python3 html_entities.py html_entities.h
    $CC -std=c11 -Wall -Wextra -Werror -fPIC -shared -O2 \
      -I${lib.getDev dico}/include/dico \
      stardict.c -ldico -lunistring -lz -o stardict.so
    runHook postBuild
  '';

  checkPhase = ''
    runHook preCheck
    DICOD=${lib.getBin dico}/bin/dicod STARDICT_MODULE="$PWD/stardict.so" \
      python3 -m unittest -v test_stardict
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 stardict.so "$out/lib/dico/stardict.so"
    runHook postInstall
  '';

  meta = {
    description = "Native StarDict database module for GNU Dico";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
