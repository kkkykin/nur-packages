# StarDict for GNU Dico

`lib.makeStardictDB` uses the same positional arguments as nixpkgs'
`makeDictdDB`: source archive, database name, archive subdirectory, and locale.
The subdirectory must contain exactly one dictionary. Its `.ifo`, `.idx` (or
`.idx.gz`), `.dict` (or `.dict.dz`), and optional `.syn` are installed under
`share/stardict/<dbName>.*`. Compressed files are decompressed during the build
so the server can read definitions without repeatedly inflating the dictionary.
The package exposes `dbName`, `locale`, `format = "stardict"`, and `ifoFile`.

```nix
let
  nur = import /path/to/nur-packages { inherit pkgs; };
  langdao = nur.lib.makeStardictDB
    /path/to/stardict-langdao-ec-gb-2.4.2.tar.bz2
    "langdao-ec-gb"
    "stardict-langdao-ec-gb-2.4.2"
    "en_US";
in {
  imports = [ nur.modules.dico ];
  services.dico = {
    enable = true;
    DBs = [ langdao pkgs.dictdDBs.wordnet ];
  };
}
```

The service listens on `127.0.0.1:2628` by default. `listenAddress`, `port`,
`openFirewall`, `package`, `stardictModule`, and `extraConfig` can be overridden.
Existing `pkgs.dictdDBs` packages can be served alongside StarDict dictionaries.
The service uses this repository's `dico` package, which explicitly enables the
Python module that nixpkgs' build otherwise skips under `strictDeps`.

The backend supports StarDict 2.4.2 and 3.0.0, 32/64-bit index offsets, gzip
indexes, dictzip definitions, synonyms, multiple definitions, and typed article
fields. It returns plain UTF-8 text; HTML/Pango/XDXF tags are stripped, and
binary media fields are represented by a type and byte-count placeholder.
Exact and prefix searches use a sorted index; other Dico strategies can use
their selector callbacks. The definition file is mapped into memory and read
on demand. Direct use of `.dict.dz` is supported but has slower random seeks.

Query without starting a server:

```sh
python3 pkgs/dico-stardict/stardict.py /path/to/dictionary.ifo hello
python3 pkgs/dico-stardict/stardict.py /path/to/dictionary.ifo hel --match prefix
python3 pkgs/dico-stardict/stardict.py /path/to/dictionary.ifo --check
# The dico-stardict package installs the same CLI as stardict-query.
```

To load the script in a manual `dicod.conf`:

```text
load-module stardict {
  command "python load-path=/path/to/script init-script=stardict root-class=DicoModule";
}
database {
  name "langdao";
  handler "stardict /path/to/langdao-ec-gb.ifo";
}
```

Run the format and callback tests with:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s pkgs/dico-stardict -v
```
