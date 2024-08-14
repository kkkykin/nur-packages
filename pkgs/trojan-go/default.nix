{ fetchFromGitHub
, buildGoModule
, lib
, v2ray-geoip
, v2ray-domain-list-community
}:

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

  buildPhase = ''
    runHook preBuild
    mkdir -p build
    env CGO_ENABLED=0 go build -tags "full" -trimpath \
 -ldflags="-s -w -buildid= -X github.com/p4gefau1t/trojan-go/constant.Version=${version} -X github.com/p4gefau1t/trojan-go/constant.Commit=${src.rev}" \
 -o build
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p $out/{bin,etc}
    cp example/*.json $out/etc/
    cp build/trojan-go $out/bin/
    runHook postInstall
  '';
  # Maybe the checkPhase cannot pass because of network issues.
  doCheck = false;

  meta = with lib; {
    description = "A Trojan proxy written in Go.";
    homepage = src.meta.homepage;
    license = licenses.gpl3;
    platforms = [ "x86_64-linux" ];
  };
}
