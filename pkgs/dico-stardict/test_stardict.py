"""Format and callback tests using small, generated StarDict dictionaries."""

from contextlib import redirect_stderr, redirect_stdout
import gzip
import io
from pathlib import Path
import struct
import tempfile
from types import SimpleNamespace
import unittest

from stardict import DicoModule, decode_article


class StarDictTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.ifo = Path(self.directory.name) / "test.ifo"

    def dictionary(self, records, *, sequence="m", bits=32, compressed=False, synonyms=()):
        index = bytearray()
        data = bytearray()
        for word, article in records:
            index += word.encode() + b"\0"
            index += struct.pack(">II" if bits == 32 else ">QI", len(data), len(article))
            data += article
        metadata = [
            "StarDict's dict ifo file",
            "version=3.0.0" if bits == 64 else "version=2.4.2",
            f"wordcount={len(records)}",
            f"idxfilesize={len(index)}",
            "bookname=Test dictionary",
            f"idxoffsetbits={bits}",
            f"synwordcount={len(synonyms)}",
        ]
        if sequence:
            metadata.append(f"sametypesequence={sequence}")
        self.ifo.write_text("\n".join(metadata), encoding="utf-8")
        if compressed:
            self.ifo.with_suffix(".idx.gz").write_bytes(gzip.compress(index))
            self.ifo.with_suffix(".dict.dz").write_bytes(gzip.compress(data))
        else:
            self.ifo.with_suffix(".idx").write_bytes(index)
            self.ifo.with_suffix(".dict").write_bytes(data)
        if synonyms:
            self.ifo.with_suffix(".syn").write_bytes(b"".join(
                word.encode() + b"\0" + struct.pack(">I", entry) for word, entry in synonyms
            ))
        module = DicoModule(self.ifo)
        self.addCleanup(module.close)
        return module

    def match(self, module, name, word, **kwargs):
        return module.match_word(SimpleNamespace(name=name, has_selector=False, **kwargs), SimpleNamespace(word=word))

    def test_duplicate_definitions_and_synonyms(self):
        module = self.dictionary([
            ("Hello", "你好".encode()), ("Hello", b"greeting"), ("help", b"assistance")
        ], synonyms=[("hi", 0), ("hi", 1), ("hi", 1)])
        self.assertTrue(module.open("test"))
        result = module.define_word("HI")
        self.assertEqual(module.result_count(result), 2)
        output = io.StringIO()
        with redirect_stdout(output):
            module.output(result, 0)
        self.assertEqual(output.getvalue(), "Hello\n你好")
        self.assertEqual(self.match(module, "exact", "HELLO").items, ["Hello"])
        self.assertEqual(self.match(module, "prefix", "HE").items, ["Hello", "help"])
        self.assertFalse(module.define_word("missing"))
        self.assertFalse(self.match(module, "prefix", "missing"))

    def test_compressed_index_data_and_64_bit_offsets(self):
        module = self.dictionary([("苹果", "apple".encode())], bits=64, compressed=True)
        self.assertTrue(module.open("test"))
        self.assertEqual(module.article(module.define_word("苹果").items[0]), "apple")

    def test_unicode_casefold_and_selector(self):
        module = self.dictionary([("Straße", b"street"), ("house", b"home")])
        self.assertTrue(module.open("test"))
        self.assertTrue(module.define_word("STRASSE"))
        calls = []

        def select(word, key):
            calls.append((word, key.word))
            return word == "house"

        result = module.match_word(
            SimpleNamespace(name="custom", has_selector=True, select=select),
            SimpleNamespace(word="home"),
        )
        self.assertEqual(result.items, ["house"])
        self.assertEqual(module.compare_count(result), 2)
        self.assertEqual(len(calls), 2)

    def test_match_output_is_unquoted_and_has_no_newline(self):
        module = self.dictionary([("two words", b"definition")])
        self.assertTrue(module.open("test"))
        output = io.StringIO()
        with redirect_stdout(output):
            module.output(self.match(module, "exact", "two words"), 0)
        self.assertEqual(output.getvalue(), "two words")

    def test_typed_fields(self):
        self.assertEqual(decode_article(b"pronunciation\0meaning", "tm"), "pronunciation\nmeaning")
        self.assertEqual(decode_article(b"mplain\0h<b>HTML</b><br>text &amp; more\0", ""), "plain\nHTML\ntext & more")
        self.assertEqual(decode_article(b"P\0\0\0\3abc", ""), "[binary field P: 3 bytes]")
        self.assertEqual(decode_article(b"abc", "P"), "[binary field P: 3 bytes]")
        for data, sequence in [(b"mno terminator", ""), (b"P\0\0", ""), (b"P\0\0\0\5abc", "")]:
            with self.subTest(data=data), self.assertRaises(ValueError):
                decode_article(data, sequence)

    def test_corrupt_index_is_rejected_and_resources_are_closed(self):
        module = self.dictionary([("word", b"definition")])
        self.ifo.with_suffix(".dict").write_bytes(b"short")
        with redirect_stderr(io.StringIO()):
            self.assertFalse(module.open("test"))
        self.assertIsNone(module.data)
        self.assertEqual(module.entries, [])

    def test_invalid_synonym_is_rejected(self):
        module = self.dictionary([("word", b"definition")], synonyms=[("alias", 42)])
        with redirect_stderr(io.StringIO()):
            self.assertFalse(module.open("test"))

    def test_reopen_does_not_duplicate_entries(self):
        module = self.dictionary([("word", b"definition")])
        self.assertTrue(module.open("first"))
        self.assertTrue(module.open("second"))
        self.assertEqual(len(module.entries), 1)


if __name__ == "__main__":
    unittest.main()
