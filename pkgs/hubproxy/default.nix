{
  lib,
  fetchurl,
  stdenvNoCC,
  nix-update-script,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "hubproxy";
  version = "1.2.4";

  src = fetchurl {
    url = "https://github.com/sky22333/hubproxy/releases/download/v${finalAttrs.version}/hubproxy-linux-amd64.tar.gz";
    hash = "sha256-gyaIb/Qm9RS4cpiowrLQMAkh/jCS3jgY/epDo9pTSCE=";
  };

  dontBuild = true;
  dontUnpack = false;

  installPhase = ''
    runHook preInstall

    install -Dm755 hubproxy $out/bin/hubproxy

    runHook postInstall
  '';

  passthru.updateScript = nix-update-script { };

  meta = with lib; {
    description = "Docker and GitHub acceleration proxy server";
    homepage = "https://github.com/sky22333/hubproxy";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "hubproxy";
  };
})
