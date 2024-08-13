{
  fetchFromGitHub,
  buildGoModule,
  lib
}:

buildGoModule rec {
  pname = "trojan-go";
  version = "20240307.0";
  # Maybe the checkPhase cannot pass because of network issues.
  doCheck = false;
  src = fetchFromGitHub ({
    owner = "fregie";
    repo = "trojan-go";
    rev = "02d5c1234d4d31ebc258c884183567c996fade64";
    sha256 = "017zfbiizkpnzmjajh06icf6mkcri9wrn5bkdd43vryl1s6mhhg8";
  });
  vendorHash = "sha256-cQil3OMjzQR9RjqA/vMDl21Gt00PVtzkNrp7BjYyLxI=";

  meta = with lib; {
    description = "A Trojan proxy written in Go.";
    homepage = src.meta.homepage;
    license = licenses.gpl3;
  };
}
