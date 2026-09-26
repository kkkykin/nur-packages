{ lib, stdenv }:

stdenv.mkDerivation rec {
  pname = "caddy-custom";
  version = "2.11.4-2026-09-09-071152";

  src = fetchTarball {
    url = "https://github.com/kkkykin/custom-caddy/releases/download/v${version}/caddy-linux-amd64.tar.gz";
    sha256 = "sha256:1kp0hbviv7jl6rvh8915bdwdj1gfvjhdwkm4drffq79n3qa5fw36";
  };

  installPhase = ''
    mkdir -p $out/bin
    cp caddy $out/bin
    chmod +x $out/bin/caddy
  '';

  meta = with lib; {
    description = "Prebuilt custom Caddy binary";
    homepage = "https://github.com/kkkykin/custom-caddy";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "caddy";
  };
}
