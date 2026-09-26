{ lib, stdenv }:

stdenv.mkDerivation rec {
  pname = "hubproxy";
  version = "1.2.4";

  src = fetchTarball {
    url = "https://github.com/sky22333/hubproxy/releases/download/v${version}/hubproxy-v${version}-linux-amd64.tar.gz";
    sha256 = "sha256:11khbnkxln522w6hc73h9xpfrpf5p3s2ahgl48apxgd3mks6lkc4";
  };

  installPhase = ''
    mkdir -p $out/bin

    # Install binary
    cp hubproxy $out/bin/
    chmod +x $out/bin/hubproxy
  '';

  meta = with lib; {
    description = "Docker and GitHub acceleration proxy server";
    homepage = "https://github.com/sky22333/hubproxy";
    license = licenses.mit;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    mainProgram = "hubproxy";
  };
}
