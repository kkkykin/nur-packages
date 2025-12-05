{ lib
, buildNpmPackage
, fetchFromGitHub
, nodejs
, makeWrapper
}:

buildNpmPackage rec {
  pname = "snow-ai";
  version = "0.4.33";

  src = fetchFromGitHub {
    owner = "MayDay-wpf";
    repo = "snow-cli";
    rev = "v${version}";
    hash = "sha256-k9ht8qDP2MZsjI40J3at0du0LXeiOorUA/htS/IUshw=";
  };

  npmDepsHash = "sha256-VI/HOGfDZD6QnarqUZOa50CjdDTPKY0JtAyElGLCRH4=";

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
