{
  lib,
  buildGoModule,
  fetchFromGitHub,
  stdenvNoCC,
  nodejs,
  pnpm_9,
  gqlgen,
  ent,
}:
buildGoModule (finalAttrs: {
  pname = "axonhub";
  version = "0.5.10";
  src = fetchFromGitHub {
    owner = "looplj";
    repo = "axonhub";
    tag = "v${finalAttrs.version}";
    hash = "sha256-bT8W+dk4UPjVUbGoLgnmMnGK3OjwAIeyObrOIItxg6g=";
  };

  preBuild = ''
    cd internal/server/gql && go generate
    cd ../../..

    mkdir -p internal/server/static/dist
    cp -r ${finalAttrs.axonhub-web}/* internal/server/static/dist/
  '';

  subPackages = [ "./cmd/axonhub" ];

  axonhub-web = stdenvNoCC.mkDerivation (finalAttrs': {
    pname = "${finalAttrs.pname}-web";
    inherit (finalAttrs) src version;

    nativeBuildInputs = [
      nodejs
      pnpm_9.configHook
    ];

    sourceRoot = "${finalAttrs.src.name}/frontend";

    pnpmDeps = pnpm_9.fetchDeps {
      inherit (finalAttrs')
        pname
        version
        src
        sourceRoot
        ;
      fetcherVersion = 2;
      hash = "sha256-8qc1D2ZgZVhCb+pCZSHCU0yjl5KdH2HHnom6EIZmeRc=";
    };

    buildPhase = ''
      pnpm run build
    '';

    installPhase = ''
      cp -r dist $out
    '';
  });

  vendorHash = lib.fakeHash;

  ldflags = [
    "-X github.com/looplj/axonhub/internal/build.Version=${finalAttrs.version}"
  ];

  meta = {
    broken = true;
    description = "Unified API gateway for LLM providers with multi-format support and advanced tracing";
    license = lib.licenses.mit;
    homepage = "https://github.com/looplj/axonhub";
    changelog = "https://github.com/looplj/axonhub/releases/tag/v${finalAttrs.version}";
    maintainers = with lib.maintainers; [ ];
    mainProgram = "axonhub";
    platforms = lib.platforms.unix;
  };
})
