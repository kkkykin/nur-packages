{ lib
, buildNpmPackage
, fetchFromGitHub
, nodejs
, makeWrapper
}:

buildNpmPackage rec {
  pname = "snow-ai";
  version = "0.5.20";

  src = fetchFromGitHub {
    owner = "MayDay-wpf";
    repo = "snow-cli";
    rev = "v${version}";
    sha256 = "1b88zjwsyy9dzc60k12y0n6q28q1c1myqhyvil3mjs7xjqy1wicj";
  };

  npmDepsHash = "sha256-GQMk0B7E2XFTV+tyrs0o1FxLqwt8PaLJgHsHBKjmdA0=";

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
