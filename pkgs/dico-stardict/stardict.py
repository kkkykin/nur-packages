#!/usr/bin/env python3
"""StarDict database backend for GNU Dico, also usable as a query CLI.

Load with: python load-path=/path/to/script init-script=stardict
                root-class=DicoModule
The database handler takes the path to its .ifo file as its only argument.
Only index entries are loaded into memory; definitions are read on demand.
"""

import argparse
from bisect import bisect_left, bisect_right
from dataclasses import dataclass
import gzip
from html.parser import HTMLParser
import mmap
from pathlib import Path
import struct
import sys


class _PlainText(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []

    def handle_starttag(self, tag, attrs):
        if tag in {"br", "p", "div", "li", "tr"}:
            self.parts.append("\n")

    def handle_endtag(self, tag):
        if tag in {"p", "div", "li", "tr"}:
            self.parts.append("\n")

    def handle_data(self, data):
        self.parts.append(data)


def _render_field(kind, data):
    if kind.isupper():
        return f"[binary field {kind}: {len(data)} bytes]"
    text = data.decode("utf-8", errors="replace")
    if kind in {"h", "g", "x"}:
        parser = _PlainText()
        parser.feed(text)
        parser.close()
        text = "".join(parser.parts)
    return text.strip("\x00\r\n")


def decode_article(data, sequence):
    """Decode StarDict's typed fields, including the implicit final field."""
    fields = []
    pos = 0
    kinds = iter(sequence) if sequence else None
    while pos < len(data) or (kinds is not None and len(fields) < len(sequence)):
        if kinds is not None:
            kind = next(kinds, None)
            if kind is None:
                raise ValueError("extra data after sametypesequence fields")
            last = len(fields) == len(sequence) - 1
        else:
            kind = chr(data[pos])
            pos += 1
            last = False
        if not kind.isascii() or not kind.isalpha():
            raise ValueError(f"invalid StarDict field type: {kind!r}")
        if last:
            end = len(data)
        elif kind.islower():
            end = data.find(b"\0", pos)
            if end < 0:
                raise ValueError("unterminated StarDict text field")
        else:
            if pos + 4 > len(data):
                raise ValueError("truncated StarDict binary field size")
            size = struct.unpack_from(">I", data, pos)[0]
            pos += 4
            end = pos + size
            if end > len(data):
                raise ValueError("truncated StarDict binary field")
        fields.append(_render_field(kind, data[pos:end]))
        pos = end + (kind.islower() and not last)
    return "\n".join(field for field in fields if field)


@dataclass
class SearchResult:
    items: list
    definitions: bool = False
    comparisons: int = 0


class DicoModule:
    def __init__(self, ifo):
        self.ifo = Path(ifo)
        self.metadata = {}
        self.entries = []
        self.words = []
        self.keys = []
        self.data = None
        self.data_file = None

    def _companion(self, suffix):
        return self.ifo.with_suffix(suffix)

    def open(self, dbname):
        self.close()
        try:
            self._load()
        except (OSError, ValueError, UnicodeError, EOFError, struct.error) as error:
            self.close()
            print(f"stardict: {dbname}: {error}", file=sys.stderr)
            return False
        return True

    def _load(self):
        lines = self.ifo.read_text(encoding="utf-8-sig").splitlines()
        if not lines or lines[0] != "StarDict's dict ifo file":
            raise ValueError("invalid StarDict .ifo header")
        self.metadata = dict(line.split("=", 1) for line in lines[1:] if "=" in line)
        if not {"version", "wordcount", "idxfilesize"} <= self.metadata.keys():
            raise ValueError("missing required StarDict metadata")
        if self.metadata.get("version") not in {"2.4.2", "3.0.0"}:
            raise ValueError("unsupported StarDict version")
        bits = int(self.metadata.get("idxoffsetbits", "32"))
        if bits not in {32, 64}:
            raise ValueError("idxoffsetbits must be 32 or 64")
        record = struct.Struct(">II" if bits == 32 else ">QI")
        idx = self._companion(".idx")
        if idx.exists():
            index = idx.read_bytes()
        else:
            with gzip.open(self._companion(".idx.gz"), "rb") as stream:
                index = stream.read()
        if len(index) != int(self.metadata["idxfilesize"]):
            raise ValueError("idxfilesize does not match index size")
        pos = 0
        while pos < len(index):
            end = index.find(b"\0", pos)
            if end < 0 or end + 1 + record.size > len(index):
                raise ValueError("truncated StarDict index entry")
            word = index[pos:end].decode("utf-8")
            offset, size = record.unpack_from(index, end + 1)
            self.words.append((word.casefold(), word, len(self.entries)))
            self.entries.append((word, offset, size))
            pos = end + 1 + record.size
        if len(self.entries) != int(self.metadata["wordcount"]):
            raise ValueError("wordcount does not match index entry count")
        syn = self._companion(".syn")
        synonyms = syn.read_bytes() if syn.exists() else b""
        pos = count = 0
        while pos < len(synonyms):
            end = synonyms.find(b"\0", pos)
            if end < 0 or end + 5 > len(synonyms):
                raise ValueError("truncated StarDict synonym entry")
            word = synonyms[pos:end].decode("utf-8")
            entry = struct.unpack_from(">I", synonyms, end + 1)[0]
            if entry >= len(self.entries):
                raise ValueError("StarDict synonym index is out of range")
            self.words.append((word.casefold(), word, entry))
            count += 1
            pos = end + 5
        if count != int(self.metadata.get("synwordcount", "0")):
            raise ValueError("synwordcount does not match synonym entry count")
        self.words.sort()
        self.keys = [row[0] for row in self.words]
        dictionary = self._companion(".dict")
        if dictionary.exists():
            self.data_file = dictionary.open("rb")
            length = dictionary.stat().st_size
            self.data = mmap.mmap(self.data_file.fileno(), 0, access=mmap.ACCESS_READ) if length else b""
            if any(offset + size > length for _, offset, size in self.entries):
                raise ValueError("StarDict definition offset is out of range")
        else:
            # dictzip is gzip-compatible. Packaged dictionaries are decompressed
            # at build time; this fallback also supports existing .dict.dz files.
            self.data = gzip.open(self._companion(".dict.dz"), "rb")

    def close(self):
        if self.data is not None and hasattr(self.data, "close"):
            self.data.close()
        if self.data_file is not None:
            self.data_file.close()
        self.data = self.data_file = None
        self.entries = []
        self.words = []
        self.keys = []
        return True

    def descr(self):
        return self.metadata.get("bookname", self.ifo.stem)

    def info(self):
        return "\n".join(f"{key}: {value}" for key, value in self.metadata.items())

    def _exact(self, word):
        key = word.casefold()
        return self.words[bisect_left(self.keys, key):bisect_right(self.keys, key)]

    def define_word(self, word):
        entries = list(dict.fromkeys(row[2] for row in self._exact(word)))
        return SearchResult(entries, definitions=True) if entries else False

    def match_word(self, strat, key):
        needle = key.word.casefold()
        comparisons = 0
        if strat.name == "exact":
            rows = self._exact(key.word)
            comparisons = len(self.keys).bit_length()
        elif strat.name == "prefix":
            start = bisect_left(self.keys, needle)
            end = start
            while end < len(self.keys) and self.keys[end].startswith(needle):
                end += 1
            rows = self.words[start:end]
            comparisons = len(self.keys).bit_length() + end - start
        elif strat.name in {"suffix", "substring"}:
            rows = [row for row in self.words if (
                row[0].endswith(needle) if strat.name == "suffix" else needle in row[0]
            )]
            comparisons = len(self.words)
        elif strat.has_selector:
            rows = [row for row in self.words if strat.select(row[1], key)]
            comparisons = len(self.words)
        else:
            return False
        words = list(dict.fromkeys(row[1] for row in rows))
        return SearchResult(words, comparisons=comparisons) if words else False

    def article(self, entry):
        word, offset, size = self.entries[entry]
        if hasattr(self.data, "seek"):
            self.data.seek(offset)
            data = self.data.read(size)
        else:
            data = self.data[offset:offset + size]
        if len(data) != size:
            raise ValueError(f"truncated definition for {word!r}")
        return decode_article(data, self.metadata.get("sametypesequence", ""))

    def output(self, result, n):
        if result.definitions:
            entry = result.items[n]
            print(self.entries[entry][0])
            print(self.article(entry), end="")
        else:
            # Dico quotes MATCH headwords and terminates protocol lines itself.
            print(result.items[n], end="")
        return True

    def result_count(self, result):
        return len(result.items)

    def compare_count(self, result):
        return result.comparisons

    def result_headers(self, result, headers):
        return {"Content-Type": "text/plain; charset=utf-8"}

    def free_result(self, result):
        return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ifo", help="path to the StarDict .ifo file")
    parser.add_argument("word", nargs="?")
    parser.add_argument("--match", choices=["exact", "prefix", "suffix", "substring"])
    parser.add_argument("--check", action="store_true", help="validate dictionary metadata and index")
    args = parser.parse_args()
    if not args.check and args.word is None:
        parser.error("word is required unless --check is used")
    database = DicoModule(args.ifo)
    if not database.open(Path(args.ifo).stem):
        return 1
    try:
        if args.check:
            print(f"{database.descr()}: {len(database.entries)} entries")
            return 0
        if args.match:
            from types import SimpleNamespace
            result = database.match_word(SimpleNamespace(name=args.match), SimpleNamespace(word=args.word))
        else:
            result = database.define_word(args.word)
        if not result:
            return 1
        for n in range(database.result_count(result)):
            database.output(result, n)
            print()
        return 0
    finally:
        database.close()


if __name__ == "__main__":
    sys.exit(main())
