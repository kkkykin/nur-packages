{ lib, buildGoModule, fetchFromGitHub, nix-update-script }:

buildGoModule (finalAttrs: {
  pname = "mcis";
  version = "0.2.4";

  src = fetchFromGitHub {
    owner = "Leo-Mu";
    repo = "montecarlo-ip-searcher";
    rev = "v${finalAttrs.version}";
    hash = "sha256-F6KYnaZZF/o5udZK2A00Gs7Z4y3vzbBGi1vDVM06VrM=";
  };

  vendorHash = null;

  passthru.updateScript = nix-update-script { };

  meta = with lib; {
    description = "Monte Carlo IP Searcher - Cloudflare IP optimization tool using hierarchical Thompson Sampling";
    homepage = "https://github.com/Leo-Mu/montecarlo-ip-searcher";
    license = licenses.gpl3Only;
    platforms = platforms.linux ++ platforms.darwin;
    mainProgram = "mcis";
  };
})
