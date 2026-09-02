{
  lib,
  fetchurl,
  stdenvNoCC,
  nix-update-script,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "cpa-manager-plus";
  version = "1.12.8";

  src = fetchurl {
    url = "https://github.com/seakee/CPA-Manager-Plus/releases/download/v${finalAttrs.version}/cpa-manager-plus_v${finalAttrs.version}_linux_amd64.tar.gz";
    hash = "sha256-D2UO31ZrotLE/ix50RZ3hUW2voi/1PhleCLtFUrELpM=";
  };

  dontBuild = true;
  dontUnpack = false;

  installPhase = ''
    runHook preInstall

    install -Dm755 cpa-manager-plus $out/bin/cpa-manager-plus

    if [ -f management.html ]; then
      install -Dm644 management.html $out/share/cpa-manager-plus/management.html
    fi

    runHook postInstall
  '';

  passthru.updateScript = nix-update-script { };

  meta = with lib; {
    description = "CPA Manager Plus - Manager Server for CPA (Chrome PaLM API) management";
    homepage = "https://github.com/seakee/CPA-Manager-Plus";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "cpa-manager-plus";
  };
})
