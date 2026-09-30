{
  lib,
  buildGoModule,
  fetchFromGitHub,
  nix-update-script,
}:

buildGoModule (finalAttrs: {
  pname = "matterbridge";
  version = "0-unstable-2026-09-30";

  src = fetchFromGitHub {
    owner = "kkkykin";
    repo = "matterbridge";
    rev = "ef194d2adcb912e297d1b0b868dfecdeb6685a0f";
    hash = "sha256-RXfKFuAWy0BP3+5ssmP01LyRZBN3UENPQRhx1wDuYmc=";
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
