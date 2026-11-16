{
  lib,
  buildPythonPackage,
  fetchPypi,
  lxml,
  python,
  regex,
  setuptools,
}:
buildPythonPackage rec {
  pname = "kovidgoyal-langtool";
  version = "1.3.0";
  pyproject = true;

  src = fetchPypi {
    pname = "kovidgoyal_langtool";
    inherit version;
    hash = "sha256-IVmHEMgDUz62GRksA2M4egfN0JFpgyMQHcewobJEjkU=";
  };

  build-system = [setuptools lxml regex];
  dependencies = [lxml regex];

  postPatch = ''
    # Calibre requires the extension and its tables; upstream silently falls
    # back to an extension without tables when the generator fails.
    substituteInPlace setup.py \
      --replace-fail \
        "r = subprocess.run(cmd, env=dict(os.environ, PYTHONHASHSEED='0'))" \
        "r = subprocess.run(cmd, env=dict(os.environ, PYTHONHASHSEED='0'), check=True)" \
      --replace-fail "optional=True" "optional=False"
  '';

  # Static rule tables must use the same regex version as the runtime.
  preBuild = ''
    # Loading ca/de rules extracts bundled dictionary resources to this cache.
    # The default cache is under Nix's unwritable HOME (/homeless-shelter).
    export LANGTOOL_CACHE_DIR="$TMPDIR/langtool-cache"
    export LANGTOOL_RULE_TABLES_JOBS="$NIX_BUILD_CORES"
  '';

  postInstall = ''
    PYTHONPATH="$out/${python.sitePackages}:$PYTHONPATH" python - <<'PY'
    import langtool
    from langtool.languages import LANGUAGES
    from langtool.patterns.static import available_languages, tables_for

    assert set(available_languages()) == set(LANGUAGES), 'Missing static rule tables'
    for code in available_languages():
        tables = tables_for(code)
        assert tables is not None, langtool.static_rules_status()
        assert tables.regex_programs_usable(), f'Incompatible regex rule tables for {code}'
    PY
  '';

  pythonImportsCheck = ["langtool" "langtool._speedups"];

  meta = {
    description = "Grammar and style checking based on LanguageTool rules";
    homepage = "https://github.com/kovidgoyal/langtool";
    license = lib.licenses.lgpl21Plus;
  };
}
