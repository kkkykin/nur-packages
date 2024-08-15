{ fetchFromGitHub
, system
, buildGoModule
, lib
, v2ray-geoip
, v2ray-domain-list-community
}:

# let
#   package_name = "github.com/p4gefau1t/trojan-go";
# in
buildGoModule rec {
  pname = "trojan-go";
  version = "20240307.0";
  src = fetchFromGitHub ({
    owner = "fregie";
    repo = "trojan-go";
    rev = "02d5c1234d4d31ebc258c884183567c996fade64";
    sha256 = "017zfbiizkpnzmjajh06icf6mkcri9wrn5bkdd43vryl1s6mhhg8";
  });
  vendorHash = "sha256-cQil3OMjzQR9RjqA/vMDl21Gt00PVtzkNrp7BjYyLxI=";

  # NIX_DEBUG=7;
  # CGO_ENABLED = "0";
  # ldflags = [
  #   "-s"
  #   "-w"
  #   "-X ${package_name}/constant.Version=${version}"
  #   "-X ${package_name}/constant.Commit=${src.rev}"
  # ];
  # GOFLAGS = [ "-trimpath" ];
  # tags = "full";

  prePatch = ''
    sed -i \
      -e s/^linux-arm:/aarch64-linux:/ \
      -e s/^linux-amd64:/x86_64-linux:/ \
      -e s/^darwin-amd64:/x86_64-darwin:/ \
      -e s/^darwin-arm64:/aarch64-darwin:/ \
      Makefile
  '';
  buildPhase = ''
    runHook preBuild
    make ${system} VERSION=${version} COMMIT=${src.rev}
    runHook postBuild
  '';
  doCheck = false;
  installPhase = ''
    runHook preInstall
    sed -i \
      -e s#/usr/share/trojan-go/geoip.dat#${v2ray-geoip}/share/v2ray/geoip.dat# \
      -e s#/usr/share/trojan-go/geosite.dat#${v2ray-domain-list-community}/share/v2ray/geosite.dat# \
      example/*.json
    install -D -m444 -t $out/etc/ example/*.json
    install -D -t $out/bin/ build/${system}/trojan-go
    runHook postInstall
  '';

   buildInputs = [
     v2ray-geoip
     v2ray-domain-list-community
   ];

  meta = with lib; {
    description = "A Trojan proxy written in Go.";
    homepage = src.meta.homepage;
    license = licenses.gpl3;
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
