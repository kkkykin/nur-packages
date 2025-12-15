{ lib
, stdenv
, fetchFromGitHub
, cmake
, gnumake
, enableUasm ? false
, uasm ? null
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "c7zip";
  version = "24.09.1";

  src = fetchFromGitHub {
    owner = "cielavenir";
    repo = "p7zip";
    rev = finalAttrs.version;
    fetchSubmodules = true;
    hash = "sha256-aEyYkW11iag6ETqT3zwO1UDKJWPdsqrHgGHqTOeAn5s=";
  };

  nativeBuildInputs = [
    cmake
    gnumake
  ] ++ lib.optional enableUasm (assert uasm != null; uasm);

  dontConfigure = true;

  postPatch = ''
    patchShebangs build_linux.sh
    substituteInPlace build_linux.sh \
      --replace "-j16" "-j ''${NIX_BUILD_CORES:-1}"

    substituteInPlace Codecs/zstd/build/cmake/CMakeLists.txt \
      --replace "cmake_minimum_required(VERSION 2.8.12 FATAL_ERROR)" "cmake_minimum_required(VERSION 3.5 FATAL_ERROR)"

    substituteInPlace Codecs/lizard/cmake_unofficial/CMakeLists.txt \
      --replace "cmake_minimum_required (VERSION 2.6)" "cmake_minimum_required(VERSION 3.5)"

    substituteInPlace Codecs/brotli/CMakeLists.txt \
      --replace "cmake_minimum_required(VERSION 2.8.6)" "cmake_minimum_required(VERSION 3.5)"

    substituteInPlace Codecs/brotli/research/libdivsufsort/CMakeLists.txt \
      --replace "cmake_minimum_required(VERSION 2.4.4)" "cmake_minimum_required(VERSION 3.5)"

    for file in \
      Codecs/lzham_codec_devel/CMakeLists.txt \
      Codecs/lzham_codec_devel/lzhamcomp/CMakeLists.txt \
      Codecs/lzham_codec_devel/lzhamdecomp/CMakeLists.txt \
      Codecs/lzham_codec_devel/lzhamdll/CMakeLists.txt \
      Codecs/lzham_codec_devel/lzhamtest/CMakeLists.txt; do
      substituteInPlace "$file" \
        --replace "cmake_minimum_required(VERSION 2.8)" "cmake_minimum_required(VERSION 3.5)"
    done
  '';

  buildPhase = ''
    runHook preBuild

    export CMPL=cmpl_gcc_x64
    export OUTDIR=g_x64
    export FLAGS="${lib.optionalString (!enableUasm) "USE_ASM="}"
    export CFLAGS_ADDITIONAL=""

    ./build_linux.sh

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/lib/7z/Codecs

    for binary in 7z 7za 7zz 7zr 7zcl 7zdec 7lzma; do
      if [ -f bin/$binary ]; then
        install -Dm755 bin/$binary $out/bin/$binary
      fi
    done

    if [ -f bin/7z.so ]; then
      install -Dm755 bin/7z.so $out/lib/7z/7z.so
      ln -sfn ../lib/7z/7z.so $out/bin/7z.so
    fi

    if [ -f bin/7zCon.sfx ]; then
      install -Dm755 bin/7zCon.sfx $out/lib/7z/7zCon.sfx
    fi

    if [ -d bin/Codecs ]; then
      install -Dm644 bin/Codecs/*.so -t $out/lib/7z/Codecs
      ln -sfn ../lib/7z/Codecs $out/bin/Codecs
    fi

    runHook postInstall
  '';

  meta = with lib; {
    description = "Enhanced p7zip with additional codec support";
    longDescription = ''
      A fork of p7zip that includes support for modern compression algorithms
      including Zstd, LZ4, Lizard, Brotli, Fast-LZMA2, Lzham, and various
      hash algorithms.
    '';
    homepage = "https://github.com/cielavenir/p7zip";
    license = licenses.lgpl21Plus;
    maintainers = with maintainers; [];
    platforms = platforms.linux;
    mainProgram = "7z";
  };
})
