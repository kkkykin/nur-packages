{
  dico,
  python3,
}:
# strictDeps keeps programs from buildInputs out of PATH. Upstream silently
# disables its Python module unless the interpreter is a native build input.
dico.overrideAttrs (old: {
  nativeBuildInputs = (old.nativeBuildInputs or []) ++ [python3];
  env =
    (old.env or {})
    // {
      PYTHON = "${python3}/bin/python3";
      PYTHON_CONFIG = "${python3}/bin/python3-config";
    };
  configureFlags = (old.configureFlags or []) ++ ["--with-python"];
  postInstall =
    (old.postInstall or "")
    + ''
      test -f "$out/lib/dico/python.so"
    '';
})
