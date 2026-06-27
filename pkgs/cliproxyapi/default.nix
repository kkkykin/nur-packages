{ lib
, buildGoModule
, fetchFromGitHub
, gcc
}:

let
  version = "7.2.42";
in buildGoModule rec {
  pname = "cliproxyapi";
  inherit version;

  src = fetchFromGitHub {
    owner = "router-for-me";
    repo = "CLIProxyAPI";
    rev = "v${version}";
    hash = "sha256-ZaUCRIgKo3NQCXI9tMOwB70zl94n8smOwUXlc1w7EzQ=";
  };

  vendorHash = "sha256-vQU3hLDga5PMUwH4KSB3T5sZ1uPUgHQHeyQGJTKHIYs=";

  nativeBuildInputs = [ gcc ];

  subPackages = [ "./cmd/server" ];

  ldflags = [
    "-s"
    "-w"
    "-X main.Version=v${version}"
    "-X main.Commit=4c0c602"
    "-X main.BuildDate=unknown"
  ];

  meta = {
    description = "Proxy server providing OpenAI/Gemini/Claude/Codex/Grok compatible API interfaces for CLI tools";
    longDescription = ''
      A proxy server that provides OpenAI/Gemini/Claude/Codex/Grok compatible API
      interfaces for CLI tools. Supports OpenAI Codex (GPT models) and Claude Code
      via OAuth, with streaming, function calling, multimodal input, and multi-account
      load balancing.
    '';
    homepage = "https://github.com/router-for-me/CLIProxyAPI";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    mainProgram = "CLIProxyAPI";
    maintainers = with lib.maintainers; [ ];
  };
}
