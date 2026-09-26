{
  lib,
  fetchurl,
  stdenvNoCC,
  nix-update-script,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "caddy-custom";
  version = "2.11.4-2026-09-20-034351";

  src = fetchurl {
    url = "https://github.com/kkkykin/custom-caddy/releases/download/v${finalAttrs.version}/caddy-linux-amd64.tar.gz";
    hash = "sha256-FM400oLzSpZT6eCihroIb1i0skcH5jqvbfrpOPZene4=";
  };

  dontBuild = true;
  dontUnpack = false;
  sourceRoot = ".";

  installPhase = ''
    runHook preInstall

    install -Dm755 caddy $out/bin/caddy

    runHook postInstall
  '';

  passthru.updateScript = nix-update-script { };

  meta = with lib; {
    description = "Prebuilt custom Caddy binary";
    homepage = "https://github.com/kkkykin/custom-caddy";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "caddy";
  };
})
