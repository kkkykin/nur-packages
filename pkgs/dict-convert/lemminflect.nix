{
  lib,
  buildPythonPackage,
  fetchPypi,
  numpy,
}:
buildPythonPackage rec {
  pname = "lemminflect";
  version = "0.2.3";
  format = "wheel";
  src = fetchPypi {
    inherit pname version format;
    dist = "py3";
    python = "py3";
    hash = "sha256-HPRw76eDczylZUzBpu4d53TlkDHmG/YhBGdiXoSozxw=";
  };
  dependencies = [numpy];
  pythonImportsCheck = ["lemminflect"];
  meta = {
    description = "English lemmatization and inflection";
    homepage = "https://github.com/bjascob/LemmInflect";
    license = lib.licenses.mit;
  };
}
