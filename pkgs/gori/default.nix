{ lib, fetchurl, stdenvNoCC, nix-update-script }:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "gori";
  version = "0.5.0";

  # Linux release assets are raw binaries (no tarball, no enclosing dir).
  src =
    if stdenvNoCC.hostPlatform.isAarch64 then
      fetchurl {
        url = "https://github.com/hahwul/gori/releases/download/v${finalAttrs.version}/gori-v${finalAttrs.version}-linux-arm64";
        hash = "sha256-A1jq1s5pHDEFTw3eLkDAyloiTCMq+pA1VBe45jrla5w=";
      }
    else
      fetchurl {
        url = "https://github.com/hahwul/gori/releases/download/v${finalAttrs.version}/gori-v${finalAttrs.version}-linux-x86_64";
        hash = "sha256-7nC6RVCxClxPX19rBDg4jXnBeEDGzD9uLBLzBFyuRIk=";
      };

  # Raw ELF binary — nothing to unpack.
  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/gori
    runHook postInstall
  '';

  passthru.updateScript = nix-update-script { };

  meta = with lib; {
    description = "Fast, keyboard-driven HTTP intercepting proxy and hacking & pentesting toolkit for the terminal";
    homepage = "https://github.com/hahwul/gori";
    changelog = "https://github.com/hahwul/gori/releases/tag/v${finalAttrs.version}";
    license = licenses.asl20;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    mainProgram = "gori";
  };
})
