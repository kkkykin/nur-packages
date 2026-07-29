{ lib, fetchurl, stdenvNoCC }:

let
  version = "1.1.2";
in
stdenvNoCC.mkDerivation rec {
  pname = "resin";
  inherit version;

  src = fetchurl {
    url = "https://github.com/Resinat/Resin/releases/download/v${version}/resin-linux-amd64.tar.gz";
    hash = "sha256-7la8WdSNP3KRg3GQSMydu1aFes0NtQgk/n75qf8zOsI=";
  };

  sourceRoot = ".";

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 resin $out/bin/resin
    runHook postInstall
  '';

  meta = with lib; {
    description = "A high-performance proxy pool gateway. Turn massive proxy subscriptions into a stable, smart, and observable network with sticky sessions.";
    homepage = "https://github.com/Resinat/Resin";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "resin";
  };
}
