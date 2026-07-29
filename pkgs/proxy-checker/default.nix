{ lib, fetchFromGitHub, python3, makeWrapper }:

let
  python = python3.withPackages (ps: with ps; [
    curl-cffi
  ]);
in

python3.pkgs.buildPythonApplication rec {
  pname = "proxy-checker";
  version = "6.3";

  src = fetchFromGitHub {
    owner = "strongshuai";
    repo = "proxy-checker";
    rev = "v${version}";
    hash = "sha256-SSnugAPrKW4O+FU1LY4XIM4Mi5a4zYB3yN4Wr2YUVdw=";
  };

  patches = [ ./base-dir.patch ];

  format = "other";

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;
  doCheck = false;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/proxy-checker $out/bin
    cp -r . $out/lib/proxy-checker/

    makeWrapper ${python}/bin/python $out/bin/proxy-checker \
      --add-flags "$out/lib/proxy-checker/server.py" \
      --prefix PYTHONPATH : "$out/lib/proxy-checker"

    runHook postInstall
  '';

  meta = with lib; {
    description = "Self-hosted proxy checker — fetch, test, and maintain a pool of free proxies";
    homepage = "https://github.com/strongshuai/proxy-checker";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "proxy-checker";
  };
}
