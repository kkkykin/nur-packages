{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule (finalAttrs: {
  pname = "matterbridge";
  version = "1.26.0-unstable-2026-09-09";

  src = fetchFromGitHub {
    owner = "matterbridge-org";
    repo = "matterbridge";
    rev = "0f595bc86e2b4469240212ec7ffd920c0b3db23b";
    hash = "sha256-KzoAUnTaoGFww1QiDLMyDGGUrc9YF4Bia4MpLIZkNUs=";
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

  meta = with lib; {
    description = "Bridge between mattermost, IRC, XMPP, Gitter, Slack, Discord, Telegram, Rocket.Chat, Zulip, Matrix, Steam, Twitch and more";
    homepage = "https://github.com/matterbridge-org/matterbridge";
    changelog = "https://github.com/matterbridge-org/matterbridge/blob/master/changelog.md";
    license = licenses.agpl3Plus;
    mainProgram = "matterbridge";
    platforms = platforms.linux ++ platforms.darwin;
  };
})
