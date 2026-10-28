#!/usr/bin/env python3
"""Convert any PyGlossary input to a portable dictzip-compressed DICT database."""
import argparse
from contextlib import closing
import gzip
from html import unescape
from html.parser import HTMLParser
import json
import logging
from pathlib import Path
import re
import sqlite3
import subprocess
import tempfile
from urllib.parse import unquote

from pyglossary import plugin_handler
from pyglossary.glossary_v2 import Glossary as BaseGlossary
from pyglossary.plugin_lib.dictdlib import b64_decode
from pyglossary.plugins.dict_org.writer import Writer

from morphology import Inflections


class Glossary(BaseGlossary):
    @classmethod
    def init(cls, resource_dir):
        # Plugin discovery also creates a cache directory in PyGlossary 5.x.
        previous = plugin_handler.cacheDir
        try:
            plugin_handler.cacheDir = str(resource_dir)
            super().init()
        finally:
            plugin_handler.cacheDir = previous

    def __init__(self, resource_dir):
        super().__init__()
        self.resource_dir = resource_dir

    def _setTmpDataDir(self, filename):
        # PyGlossary 5.x ignores XDG_CACHE_HOME. Keep reader scratch resources
        # inside this conversion, including when Nix provides no writable HOME.
        self.resource_dir.mkdir(exist_ok=True)
        self._tmpDataDir = str(self.resource_dir)
        self._cleanupPathList.add(self._tmpDataDir)


def reference_target(href):
    """Recognize dictionary links without turning other URL schemes into lookups."""
    if not href:
        return None
    target = href.strip()
    for prefix in ("bword:", "entry:", "d:", "x:"):
        if target.lower().startswith(prefix):
            target = target[len(prefix):].removeprefix("//")
            break
    else:
        if target.startswith(("#", "//")) or re.match(r"[A-Za-z][A-Za-z0-9+.-]*:", target):
            return None
    try:
        target = unquote(target, errors="strict").strip()
        validate_word(target)
    except (ValueError, UnicodeError):
        return None
    # Braces would split one target into multiple DICT cross-references.
    return None if "{" in target or "}" in target else target


class PlainText(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []
        self.links = []

    def handle_starttag(self, tag, attrs):
        if tag in {"a", "kref"}:
            href = dict(attrs).get("href" if tag == "a" else "k")
            self.links.append((tag, href, len(self.parts)))
        if tag in {"br", "p", "div", "li", "tr"}:
            self.parts.append("\n")

    def handle_endtag(self, tag):
        if self.links and tag == self.links[-1][0]:
            _, href, start = self.links.pop()
            label = "".join(self.parts[start:])
            text = label.strip()
            target = reference_target(text if tag == "kref" and href is None else href)
            if target:
                link = f"{text} ({{{target}}})" if text and text != target else f"{{{target}}}"
                self.parts[start:] = [label.replace(text, link, 1) if text else link]
        if tag in {"p", "div", "li", "tr"}:
            self.parts.append("\n")

    def handle_data(self, text):
        self.parts.append(text)


def plain_text(entry):
    # Some readers, including DictOrg, emit HTML with the default text format.
    if entry.detectDefiFormat() in {"h", "x"}:
        parser = PlainText()
        parser.feed(entry.defi)
        parser.close()
        text = "".join(parser.parts)
    else:
        text = entry.defi
    # DICT is a line protocol. Preserve text and tabs/newlines, not terminal
    # control sequences or embedded NULs from a source dictionary.
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    return "".join(c for c in text if c in "\n\t" or (ord(c) >= 32 and ord(c) != 127)).strip()


def validate_word(word):
    if not word or len(word.encode("utf-8")) > 4096 or any(ord(c) < 32 or ord(c) == 127 for c in word):
        raise ValueError(f"invalid DICT headword: {word[:80]!r}")


class ConversionErrors(logging.Handler):
    def __init__(self):
        super().__init__(logging.ERROR)
        self.errors = []

    def emit(self, record):
        self.errors.append(record.getMessage())


def rewrite_index(base, languages):
    """Add aliases without copying articles; let dictfmt normalize UTF-8 keys.

    PyGlossary's DictOrg writer uses an ASCII dictionary-order sort. dictfmt
    supplies the UTF-8/allchars order and markers expected by both servers.
    SQLite keeps deduplication of expanded indexes out of the Python heap.
    """
    inflections = Inflections(languages)
    original = base.with_suffix(".index")
    with closing(sqlite3.connect(base.with_suffix(".sqlite"))) as db, db:
        db.execute("PRAGMA journal_mode=OFF")
        db.execute("PRAGMA synchronous=OFF")
        db.execute("CREATE TABLE entries (word TEXT, start INTEGER, size INTEGER, PRIMARY KEY(word, start, size)) WITHOUT ROWID")
        source_count = 0
        with original.open(encoding="utf-8") as index:
            for line in index:
                word, offset, length = line.rstrip("\n").split("\t")
                validate_word(word)
                start, size = b64_decode(offset), b64_decode(length)
                forms = () if word.startswith("00-database-") else inflections.forms(word)
                words = {word, *forms}
                for form in words:
                    validate_word(form)
                db.executemany("INSERT OR IGNORE INTO entries VALUES (?, ?, ?)",
                               ((form, start, size) for form in sorted(words)))
                source_count += 1
        count = db.execute("SELECT COUNT(*) FROM entries").fetchone()[0]
        raw = base.with_suffix(".unsorted")
        with raw.open("w", encoding="utf-8", newline="\n") as output:
            for word, start, size in db.execute("SELECT word, start, size FROM entries ORDER BY word, start, size"):
                output.write(f"{word}\t{start}\t{size}\n")
        with raw.open("rb") as source, original.open("wb") as output:
            subprocess.run(["dictfmt", "-i", "--utf8", "--allchars", "--index-keep-orig", "--quiet"],
                           stdin=source, stdout=output, check=True)
    # Case variants may normalize to the same (word, article). Keep the first
    # original spelling, retaining separate definitions at different offsets.
    dedup = base.with_suffix(".dedup")
    previous_word, positions = None, set()
    final_count = 0
    with original.open("rb") as source, dedup.open("wb") as output:
        for line in source:
            columns = line.rstrip(b"\n").split(b"\t")
            if columns[0] != previous_word:
                previous_word, positions = columns[0], set()
            position = tuple(columns[1:3])
            if position not in positions:
                output.write(line)
                positions.add(position)
                final_count += 1
    dedup.replace(original)
    return {"sourceHeadwords": source_count - 4, "indexEntries": final_count, "generatedEntries": count - source_count,
            "languages": list(languages)}


def convert(input_file, output_base, *, input_format="", languages=(), read_options=None):
    output_base = Path(output_base).absolute()
    output_base.parent.mkdir(parents=True, exist_ok=True)
    targets = [Path(str(output_base) + suffix) for suffix in (".index", ".dict", ".dict.dz", ".json")]
    if any(path.exists() for path in targets):
        raise ValueError("output already exists; choose a new output basename")
    errors = ConversionErrors()
    log = logging.getLogger("pyglossary")
    log.addHandler(errors)
    writer = entries = None
    glos = None
    try:
        with tempfile.TemporaryDirectory(prefix="dict-convert-", dir=output_base.parent) as directory:
            base = Path(directory) / "dictionary"
            if not Glossary.plugins:
                Glossary.init(Path(directory) / "resources")
            glos = Glossary(Path(directory) / "resources")
            glos.progressbar = False
            glos.config = {"skip_resources": True}
            input_format = Glossary.detectInputFormat(str(input_file), formatName=input_format).formatName
            reader_options = dict(read_options or {})
            if input_format == "Stardict":
                # PyGlossary 5.3's XDXF-to-HTML transform strips inline spaces.
                # Our text renderer handles native XDXF, preserving the source.
                reader_options = {"xdxf_to_html": False, **reader_options}
            glos.directRead(str(input_file), formatName=input_format, **reader_options)
            writer = Writer(glos)
            # These are the DictOrg plugin's own write options (the same
            # attributes PyGlossary's convert API sets from writeOptions).
            writer._dictzip = True
            writer._install = False
            writer.open(str(base.with_suffix(".index")))
            entries = writer.write()
            next(entries)
            metadata = dict(glos.iterInfo())
            title = " ".join(unescape(metadata.get("name", Path(input_file).stem)).split())
            info = "\n".join(f"{key}: {value}" for key, value in sorted(metadata.items())
                             if key in {"name", "author", "copyright", "description", "website", "date"})
            for word, text in {
                "00-database-utf8": "",
                "00-database-allchars": "",
                "00-database-short": title,
                "00-database-info": info,
            }.items():
                entries.send(glos.newEntry(word, word + "\n" + text, defiFormat="m"))
            count = 0
            for entry in glos:
                if entry.isData():
                    continue
                words = [word for word in entry.l_term if not word.startswith("00-database-")]
                if not words:
                    continue
                for word in words:
                    validate_word(word)
                definition = words[0] + "\n" + plain_text(entry)
                entries.send(glos.newEntry(words, definition, defiFormat="m"))
                count += 1
            try:
                entries.send(None)
            except StopIteration:
                pass
            writer.finish()  # PyGlossary writes the index and invokes dictzip.
            compressed = base.with_suffix(".dict.dz")
            if errors.errors:
                raise ValueError("PyGlossary reported errors: " + "; ".join(errors.errors))
            if not compressed.is_file() or base.with_suffix(".dict").exists():
                raise ValueError("PyGlossary did not produce dictzip output; is dictzip installed?")
            # gzip MTIME is nonsemantic. Normalize it for reproducible Nix
            # outputs; dictzip does not emit the optional header CRC.
            with compressed.open("r+b") as stream:
                header = stream.read(10)
                if header[:3] != b"\x1f\x8b\x08" or not header[3] & 4 or header[3] & 2:
                    raise ValueError("unexpected dictzip header")
                stream.seek(4)
                stream.write(b"\0" * 4)
            # Consume EOF as well, so a failed compressor/checksum is fatal.
            with gzip.open(compressed, "rb") as stream:
                while stream.read(1024 * 1024):
                    pass
            stats = rewrite_index(base, languages)
            stats["articles"] = count
            base.with_suffix(".json").write_text(json.dumps(stats, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            for suffix in (".index", ".dict.dz", ".json"):
                base.with_suffix(suffix).replace(Path(str(output_base) + suffix))
            return stats
    finally:
        if entries is not None:
            entries.close()
        if writer is not None and writer._dictdb is not None:
            writer._dictdb.indexFile.close()
            writer._dictdb.dictFile.close()
        if glos is not None:
            glos.clear()
            glos.cleanup()
        log.removeHandler(errors)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", help="input file, e.g. StarDict .ifo, DSL, TSV, or another PyGlossary format")
    parser.add_argument("output", help="output basename (without .index/.dict.dz)")
    parser.add_argument("--input-format", default="", help="PyGlossary format name; default: autodetect")
    parser.add_argument("--language", action="append", choices=("en", "ja"), default=[])
    parser.add_argument("--read-options", default="{}", help="JSON object of PyGlossary reader options")
    args = parser.parse_args()
    try:
        stats = convert(args.input, args.output, input_format=args.input_format,
                        languages=args.language, read_options=json.loads(args.read_options))
    except (ValueError, OSError, RuntimeError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"dict-convert: {error}\n")
    print(json.dumps(stats, ensure_ascii=False))


if __name__ == "__main__":
    main()
