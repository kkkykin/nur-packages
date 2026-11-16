{
  lib,
  buildPythonPackage,
  fetchPypi,
  lxml,
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

  # Static rule tables must be built with the regex version used at runtime.
  preBuild = ''
    export LANGTOOL_RULE_TABLES_JOBS="$NIX_BUILD_CORES"
  '';

  pythonImportsCheck = ["langtool" "langtool._speedups"];

  meta = {
    description = "Grammar and style checking based on LanguageTool rules";
    homepage = "https://github.com/kovidgoyal/langtool";
    license = lib.licenses.lgpl21Plus;
  };
}
