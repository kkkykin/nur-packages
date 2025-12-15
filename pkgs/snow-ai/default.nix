{ lib
, buildNpmPackage
, fetchFromGitHub
, nodejs
, makeWrapper
}:

buildNpmPackage rec {
  pname = "snow-ai";
  version = "0.5.5";

  src = fetchFromGitHub {
    owner = "MayDay-wpf";
    repo = "snow-cli";
    rev = "v${version}";
    sha256 = "0h7w47kd5j0xhs8b3n7hlycg9j0r2q0qpzlkxdy70bkjy79f90qz";
  };

  npmDepsHash = "sha256-8UPFCxaL+Ea5+Wzzt/v+dg4rUjdbeN+zTElQ8XXNQZw=";

  nativeBuildInputs = [ makeWrapper ];

  buildPhase = ''
    npm run build
  '';

  installPhase = ''
    mkdir -p $out/bin $out/lib/snow-ai
    cp -r bundle $out/lib/snow-ai/
    cp -r scripts $out/lib/snow-ai/
    cp package.json $out/lib/snow-ai/

    makeWrapper ${nodejs}/bin/node $out/bin/snow \
      --add-flags "$out/lib/snow-ai/bundle/cli.mjs"
  '';

  meta = with lib; {
    description = "Intelligent Command Line Assistant powered by AI";
    homepage = "https://github.com/MayDay-wpf/snow-cli";
    license = licenses.mit;
    maintainers = [ ];
    mainProgram = "snow";
  };
}
