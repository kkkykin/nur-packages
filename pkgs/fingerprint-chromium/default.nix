{ lib, appimageTools, fetchurl }:

let
  pname = "fingerprint-chromium";
  version = "148.0.7778.215";

  src = fetchurl {
    url = "https://github.com/adryfish/fingerprint-chromium/releases/download/${version}/ungoogled-chromium-${version}-1-x86_64.AppImage";
    sha256 = "a5fa5e6c05cb7fa3617ec2ca642ad3cc6e586ac5249cc29edb0a602d695685f0";
  };

  appimageContents = appimageTools.extractType2 {
    inherit pname version src;
  };

in appimageTools.wrapType2 {
  inherit pname version src;

  preferLocalBuild = true;

  extraInstallCommands = ''
    install -m 444 -D ${appimageContents}/ungoogled-chromium.desktop $out/share/applications/${pname}.desktop
    install -m 444 -D ${appimageContents}/chromium.png $out/share/icons/hicolor/256x256/apps/${pname}.png

    substituteInPlace $out/share/applications/${pname}.desktop \
      --replace-fail 'Exec=AppRun' 'Exec=${pname}'
  '';

  meta = with lib; {
    description = "Ungoogled Chromium with fingerprint resistance";
    homepage = "https://github.com/adryfish/fingerprint-chromium";
    license = licenses.bsd3;
    platforms = [ "x86_64-linux" ];
    mainProgram = "fingerprint-chromium";
  };
}
