# PyGlossary → DICT

`lib.makeDictdDB` converts a dictionary at Nix build time using PyGlossary and
its DictOrg writer with **dictzip enabled**. It installs standard
`share/dictd/<dbName>.index` and `<dbName>.dict.dz` files. Both **dictd** and GNU
Dico's **dictorg** backend read the compressed definitions directly, with
random access. No StarDict module, Python, or morphology engine runs on the
server.

```nix
let
  nur = import /path/to/nur-packages { inherit pkgs; };
  english = nur.lib.makeDictdDB {
    src = ./stardict-langdao-ec-gb-2.4.2.tar.bz2;
    dbName = "langdao-eng-zho";
    inputFile = "stardict-langdao-ec-gb-2.4.2/langdao-ec-gb.ifo";
    languages = [ "en" ];
  };
  japanese = nur.lib.makeDictdDB {
    src = ./stardict-XiaoXueTang-jc-2.4.2.tar.bz2;
    dbName = "xxt-jpn-zho";
    inputFile = "stardict-XiaoXueTang-jc-2.4.2/XiaoXueTang-jc.ifo";
    languages = [ "ja" ];
  };
in {
  services.dictd = {
    enable = true;
    DBs = [ english japanese ];
  };
  # Or, with nur.modules.dico imported:
  # services.dico = { enable = true; DBs = [ english japanese ]; };
}
```

This is a separate helper from nixpkgs' archive-installing `makeDictdDB` and
this repository's `makeStardictDB`. Its argument is an attribute set:

| Argument | Meaning |
| --- | --- |
| `src` | A source archive, directory, or single dictionary file. |
| `dbName` | Output basename: letters, digits, `_`, `-`. |
| `inputFile` | Path **inside** the directory/archive, without an initial `/`. Omit for single-file inputs. For StarDict, supply the whole directory/archive and select its `.ifo`, so companion files are available. |
| `inputFormat` | PyGlossary format name, e.g. `Stardict`, `Tabfile`, `ABBYYLingvoDSL`; default: detect from filename. |
| `languages` | Inflection indexes to generate: `[ "en" ]`, `[ "ja" ]`, or both. Default `[]` preserves only the source headwords/synonyms. |
| `readOptions` | Attribute set passed to the selected PyGlossary reader, e.g. `{ encoding = "utf-8"; }`. |
| `locale` | Locale file used by NixOS's dictd database collector; default `en_US.UTF-8`. |
| `converter` | Override the converter package if additional PyGlossary reader dependencies are needed. |
| `meta` | Output package metadata, including the source dictionary's license if known. |

Input is not restricted to StarDict. For example, a UTF-8 tab-separated glossary:

```nix
nur.lib.makeDictdDB {
  src = ./glossary.tsv;
  dbName = "my-glossary";
  languages = [ "en" "ja" ];
}
```

The `dict-convert` package also provides a CLI:

```sh
dict-convert dictionary.ifo output/my-dictionary --language en --language ja
# Select a format or its reader options when autodetection is insufficient:
dict-convert dictionary.dsl output/my-dictionary \
  --input-format ABBYYLingvoDSL --read-options '{"encoding":"utf-8"}'
```

The helper exports `dbName`, `locale`, `format = "dictd"`, `indexFile`, and
`dataFile`. It is accepted by NixOS `services.dictd.DBs` and this repository's
`services.dico.DBs`. For a manual Dico configuration, use
`handler "dictorg database=/path/to/my-dictionary";`. The index is already
sorted; no runtime `sort` option is necessary for these generated databases.

## Inflection lookup

Aliases point to the **same definition offsets** as their dictionary forms;
articles are not duplicated. Existing headwords, synonyms, multiple senses,
and ambiguous aliases remain searchable. For example:

- English: `went → go`, `children → child`, `running → run`, `better → good`.
  LemmInflect supplies dictionary-backed inflections, including irregular
  verbs, plurals, and comparison forms. Unknown words are not guessed. A form
  can have several valid lemmas; exact source entries are also retained.
- Japanese: `食べました → 食べる`, `帰りました → 帰る`, `行った → 行く`,
  `来なかった → 来る`, `勉強しました → 勉強する`, `高くなかった → 高い`.
  Fugashi/UniDic identifies verb/adjective classes rather than treating every
  word ending in `る` or `い` as inflectable. Generation covers modern polite,
  negative, past, te, conditional, imperative, volitional and desire forms,
  plus potential/passive/causative/progressive forms with tense and politeness.
  Na-adjectives also get common copula forms. Verbal nouns marked by UniDic
  as サ変可能 also get `する` forms, so `勉強しました` can find a `勉強` entry.

This is a **finite, build-time index**, not unrestricted sentence analysis.
UniDic's selected lexical analysis determines the Japanese conjugation class;
unknown words, alternative analyses, dialects, classical forms, and arbitrary
chains of auxiliaries may require additional source aliases. The base lemma (or a サ変可能 verbal noun)
must be present in the source dictionary. No dictionary meanings are invented.

Choose the source language: enabling Japanese forms for a Chinese-only
headword dictionary is unnecessary. Inflections increase the **uncompressed
index** and therefore the server's index memory, even though the compressed
article file stays the same. `<dbName>.json` records source/article/index counts.
For example, a local XiaoXueTang Japanese–Chinese conversion grew from about
217,000 source headwords to 3.45 million index entries (about 108 MiB on disk).
Full dictionaries can still exceed a small VPS's available memory; conversion
and dictzip do not remove the backend's own index allocations.

## Cross-references

HTML dictionary links and XDXF `<kref>` references become DICT `{target}`
markers. When the label differs from the target, both are kept:

| Input | DICT text |
| --- | --- |
| `<a href="bword://apple">apple</a>` | `{apple}` |
| `<a href="bword://apple">apples</a>` | `apples ({apple})` |
| `<a href="bword://%E9%A3%9F%E3%81%B9%E3%82%8B">食事</a>` | `食事 ({食べる})` |
| `<kref k="apple">apples</kref>` | `apples ({apple})` |

The converter recognizes `bword:`, `entry:`, `d:`, `x:` and bare dictionary
targets, decodes URL escapes, and preserves inline text and paragraph breaks.
External URLs and invalid targets retain their labels as plain text. Existing
literal braces are preserved. DICT clients decide how to display `{target}`;
the server transmits the markers as part of the definition.

This handling lives in `dict-convert` and uses the stock PyGlossary package.

## Output and validation

Definitions contain the original headword and plain UTF-8 text. HTML/XDXF tags
are removed; binary resources are omitted because ordinary DICT clients cannot
render them. PyGlossary reader support determines which source features are
available. Reader errors and missing/failed dictzip output fail the build.
Headwords containing protocol control characters or exceeding 4096 UTF-8 bytes
are rejected, and existing
output files are not overwritten by the CLI.

The DictOrg writer's index is normalized and sorted by `dictfmt --utf8
--allchars`, including the necessary format markers. This preserves Japanese
and punctuation keys and works in both backends. Identical normalized aliases
for the same article are deduplicated. dictzip's timestamp is normalized so
identical source data produces identical outputs.

The converter's Nix check phase runs protocol tests against **unmodified Dico
and dictd**. Tests cover compressed StarDict with 64-bit offsets, tab-separated
input, synonyms, duplicate definitions, English/Japanese inflections, Unicode
and punctuation lookup, HTML/XDXF cross-references, DICT round trips, invalid
link targets, compression errors, and reproducible compressed output.
