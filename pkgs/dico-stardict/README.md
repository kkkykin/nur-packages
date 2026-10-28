# StarDict for GNU Dico

For a standard dictzip-compressed database usable by both dictd and Dico,
including English/Japanese inflection lookup, use
[`lib.makeDictdDB`](../dict-convert/README.md). It accepts other PyGlossary
input formats as well and needs no StarDict module at runtime.

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
The service uses nixpkgs' unmodified `pkgs.dico` and the independently compiled
`dico-stardict-native` C module. The module links against Dico, libunistring and
zlib. Python generates its HTML entity table and runs tests during the build;
serving dictionaries does not use Dico's Python bridge.

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

To load the native module in a manual `dicod.conf`:

```text
load-module stardict {
  command "/path/to/dico-stardict-native/lib/dico/stardict";
}
database {
  name "langdao";
  handler "stardict /path/to/langdao-ec-gb.ifo";
}
```

The Python CLI remains available for independent queries and build-time
dictionary validation. Run its format and callback tests with:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s pkgs/dico-stardict -v
```

The native package runs integration tests through `dicod` during its check phase.
To run them against an already compiled module:

```sh
DICOD=/path/to/dicod STARDICT_MODULE=/path/to/stardict.so \
  python3 -m unittest discover -s pkgs/dico-stardict-native -v
```

MATCH results escape quotes and backslashes in headwords. GNU Dico 2.12 itself
does not escape the query word in the `151` DEFINE response header; this upstream
limitation also applies when using the native module.
