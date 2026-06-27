{ lib
, buildGoModule
, gcc
}:

let
  version = "7.2.42";
in buildGoModule rec {
  pname = "cliproxyapi";
  inherit version;

  # Use builtins.fetchTarball (eval-time, not a derivation) to avoid
  # the fetchzip cross-device mv issue in this nix sandbox
  src = builtins.fetchTarball {
    url = "https://github.com/router-for-me/CLIProxyAPI/archive/v${version}.tar.gz";
    sha256 = "0d0k7df77ra5q67ckwi7vsbk7g87n31v8gbj158778qai12059b5";
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
