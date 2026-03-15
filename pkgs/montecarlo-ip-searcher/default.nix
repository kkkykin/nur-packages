{ lib, buildGoModule, fetchFromGitHub }:

let
  version = "0.2.4";
in buildGoModule {
  pname = "mcis";
  inherit version;

  src = fetchFromGitHub {
    owner = "Leo-Mu";
    repo = "montecarlo-ip-searcher";
    rev = "v${version}";
    hash = "sha256-zGMNbfyYhdrWfUacY82fbpfp49itg5Vm+K9wuyQLrgc=";
  };

  vendorHash = null;

  meta = with lib; {
    description = "Monte Carlo IP Searcher - Cloudflare IP optimization tool using hierarchical Thompson Sampling";
    homepage = "https://github.com/Leo-Mu/montecarlo-ip-searcher";
    license = licenses.gpl3Only;
    platforms = platforms.linux ++ platforms.darwin;
    mainProgram = "mcis";
  };
}
