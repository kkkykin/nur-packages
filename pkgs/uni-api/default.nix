{
  lib,
  fetchFromGitHub,
  python3,
  makeWrapper,
}:

let
  python = python3.withPackages (ps: with ps; [
    aiofiles
    aiosqlite
    asyncpg
    certifi
    cryptography
    fastapi
    greenlet
    httpx-socks
    httpx
    h2
    pillow
    pytest
    python-multipart
    ruamel-yaml
    sqlalchemy
    uvicorn
    watchfiles
  ]);
in

python3.pkgs.buildPythonApplication rec {
  pname = "uni-api";
  version = "1.7.5";
  pyproject = false;  # Not a standard Python package

  src = fetchFromGitHub {
    owner = "yym68686";
    repo = "uni-api";
    rev = "dfdaa7cb07855a6442e2833a6c4b894902259ec5";
    hash = "sha256-5iswmaIotRzcBa3JIZWEKzFU3aistoVtuWEuCQZ3uQs=";
    fetchSubmodules = true;
  };

  nativeBuildInputs = [ makeWrapper ];

  # Skip standard Python build phases
  dontBuild = true;
  doCheck = false;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/uni-api $out/bin
    cp -r . $out/lib/uni-api/

    makeWrapper ${python}/bin/python $out/bin/uni-api \
      --add-flags "-m uvicorn main:app" \
      --chdir "$out/lib/uni-api" \
      --prefix PYTHONPATH : "$out/lib/uni-api"

    runHook postInstall
  '';

  meta = with lib; {
    description = "Unified API gateway for multiple AI model providers";
    homepage = "https://github.com/yym68686/uni-api";
    license = licenses.gpl3;
    platforms = platforms.linux ++ platforms.darwin;
    mainProgram = "uni-api";
  };
}
