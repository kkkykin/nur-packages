{
  lib,
  buildGo127Module,
  fetchFromGitHub,
  nix-update-script,
}:

buildGo127Module (finalAttrs: {
  pname = "matterbridge";
  version = "0-unstable-2026-11-19";

  src = fetchFromGitHub {
    owner = "kkkykin";
    repo = "matterbridge";
    rev = "bd7175ab33e309267447fb5c2113e8f876693e7f";
    hash = "sha256-PonmbvmOjX8jts2p8NKj17fsyo/zlEdDEzjbhzhCDxc=";
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
