{
  lib,
  buildGoModule,
  fetchFromGitHub,
  nix-update-script,
}:

buildGoModule (finalAttrs: {
  pname = "matterbridge";
  version = "0-unstable-2026-10-01";

  src = fetchFromGitHub {
    owner = "kkkykin";
    repo = "matterbridge";
    rev = "c10dab1a3db08834d6919ee76d2ac2f7fb2d41ba";
    hash = "sha256-bgVdURGOPNF95nfV26H360KGJF13PX+BspGC2Mpkgiw=";
  };

  vendorHash = "sha256-1hrGSYJFZH/v3EShMINkmCRE6UuY+osNg8aoj1nzeQE=";

  tags = [ "goolm" ];

  subPackages = [ "." ];

  ldflags = [
    "-s"
    "-w"
    "-X github.com/matterbridge-org/matterbridge/version.GitHash=${builtins.substring 0 7 finalAttrs.src.rev}"
  ];

  env.CGO_ENABLED = 0;

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--version=branch=feature/onebot-protocol"
    ];
  };

  meta = with lib; {
    description = "Bridge between mattermost, IRC, XMPP, Gitter, Slack, Discord, Telegram, Rocket.Chat, Zulip, Matrix, Steam, Twitch and more";
    homepage = "https://github.com/matterbridge-org/matterbridge";
    changelog = "https://github.com/matterbridge-org/matterbridge/blob/master/changelog.md";
    license = licenses.agpl3Plus;
    mainProgram = "matterbridge";
    platforms = platforms.linux ++ platforms.darwin;
  };
})
