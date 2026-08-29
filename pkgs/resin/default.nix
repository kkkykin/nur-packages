{
  lib,
  buildGoModule,
  fetchFromGitHub,
  buildNpmPackage,
  nix-update-script,
}:
let
  version = "1.2.0";

  src = fetchFromGitHub {
    owner = "Resinat";
    repo = "Resin";
    tag = "v${version}";
    hash = "sha256-tqSuYZce0uq9gVSstNLPlSyJPGWwYrfvCEgAyXiek4c=";
  };

  # Built separately with the Nix-managed npm toolchain, then dropped into
  # webui/dist so the `//go:embed dist` directive in webui/embed.go can pull it
  # into the Go binary. Mirrors the release workflow's `npm ci && npm run build`
  # step (run inside ./webui); Vite writes to its default outDir, webui/dist.
  resin-web = buildNpmPackage {
    pname = "resin-web";
    inherit version src;

    sourceRoot = "${src.name}/webui";

    npmDepsHash = "sha256-HM1+bcEry9BY39xt7qUgRwnNfXwyfBJyUeFAPosrnKU=";

    buildPhase = ''
      runHook preBuild
      npm run build
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out/dist
      cp -r dist/. $out/dist/
      runHook postInstall
    '';
  };
in
buildGoModule (finalAttrs: {
  pname = "resin";
  inherit version src;

  # Drop the compiled WebUI into webui/dist so embed.go finds it at go-build
  # time. The `with_*` build tags mirror the upstream release workflow
  # (.github/workflows/release.yml), with `with_gvisor` added on top to enable
  # the gVisor netstack/TUN transport paths.
  preBuild = ''
    cp -r ${resin-web}/dist webui/dist
    chmod -R u+w webui/dist
  '';

  subPackages = [ "cmd/resin" ];

  vendorHash = "sha256-7Nys4ybPKtdS8fU0yUuYk5BEergdLkmNabFnsiap+L0=";

  # The -tags match the upstream release workflow (.github/workflows/release.yml),
  # with `with_gvisor` added on top to enable the gVisor netstack/TUN transport
  # paths. GitCommit uses the short rev from the pinned tag; BuildTime is omitted
  # for reproducibility (CI injects a wall-clock time).
  tags = [
    "with_quic"
    "with_wireguard"
    "with_grpc"
    "with_utls"
    "with_embedded_tor"
    "with_naive_outbound"
    "with_gvisor"
  ];

  ldflags = [
    "-s"
    "-w"
    "-X github.com/Resinat/Resin/internal/buildinfo.Version=${finalAttrs.version}"
    "-X github.com/Resinat/Resin/internal/buildinfo.GitCommit=${builtins.substring 0 8 finalAttrs.src.rev}"
  ];

  env.CGO_ENABLED = 0;

  passthru.updateScript = nix-update-script { };


  meta = with lib; {
    description = "A high-performance proxy pool gateway. Turn massive proxy subscriptions into a stable, smart, and observable network with sticky sessions.";
    homepage = "https://github.com/Resinat/Resin";
    license = licenses.mit;
    mainProgram = "resin";
    # Pure-Go build with CGO disabled; buildable wherever Go runs.
    platforms = platforms.linux ++ platforms.darwin;
  };
})
