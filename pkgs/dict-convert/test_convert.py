"""Real PyGlossary conversion and DICT queries against both stock servers."""
import gzip
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from convert import convert
from morphology import Inflections
from pyglossary.plugin_lib.dictdlib import b64_decode


class ConversionTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="dict-convert-test-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def stardict(self, records, *, synonyms=(), bits=32, compressed=False):
        base = self.root / "source"
        data, index = bytearray(), bytearray()
        for word, definition in records:
            definition = definition.encode("utf-8")
            index += word.encode("utf-8") + b"\0"
            index += struct.pack(">QI" if bits == 64 else ">II", len(data), len(definition))
            data += definition
        base.with_suffix(".ifo").write_text(
            "StarDict's dict ifo file\n" + ("version=3.0.0\n" if bits == 64 else "version=2.4.2\n")
            + f"bookname=测试辞書\nwordcount={len(records)}\nidxfilesize={len(index)}\n"
            + f"idxoffsetbits={bits}\nsynwordcount={len(synonyms)}\nsametypesequence=h\n",
            encoding="utf-8")
        if compressed:
            base.with_suffix(".idx.gz").write_bytes(gzip.compress(index))
            base.with_suffix(".dict.dz").write_bytes(gzip.compress(data))
        else:
            base.with_suffix(".idx").write_bytes(index)
            base.with_suffix(".dict").write_bytes(data)
        if synonyms:
            base.with_suffix(".syn").write_bytes(b"".join(
                word.encode() + b"\0" + struct.pack(">I", entry) for word, entry in synonyms))
        return base.with_suffix(".ifo")

    def tabfile(self, records):
        source = self.root / "source.tsv"
        source.write_text("".join(f"{word}\t{definition}\n" for word, definition in records), encoding="utf-8")
        return source

    def index(self, base):
        result = {}
        for line in base.with_suffix(".index").read_text(encoding="utf-8").splitlines():
            word, offset, size, *_ = line.split("\t")
            result.setdefault(word, []).append((b64_decode(offset), b64_decode(size)))
        return result

    def query(self, server, base, commands):
        config = self.root / (server + ".conf")
        if server == "dico":
            config.write_text(
                'timing no;\nload-module dictorg { command "dictorg"; }\n'
                + 'database { name fixture; handler ' + json.dumps("dictorg database=" + str(base)) + '; }\n')
            argv = [os.environ["DICOD"], "--inetd", "--stderr", "--no-preprocessor"]
        else:
            config.write_text('access { allow * }\ndatabase fixture {\n'
                              + f'  data "{base}.dict.dz"\n  index "{base}.index"\n}}\n')
            argv = [os.environ["DICTD"], "--inetd", "--stdin2stdout"]
        result = subprocess.run([*argv, "--config=" + str(config)],
                                input="\r\n".join([*commands, "QUIT", ""]),
                                capture_output=True, text=True, encoding="utf-8", timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertIn("220 ", result.stdout)
        self.assertIn("221 ", result.stdout)
        return result.stdout

    def test_english_and_japanese_queries_in_both_servers(self):
        source = self.tabfile([
            ("go", "GO"), ("child", "CHILD"), ("run", "RUN"), ("good", "GOOD"),
            ("食べる", "EAT"), ("帰る", "RETURN"), ("行く", "GO-JA"),
            ("来る", "COME"), ("する", "DO"), ("勉強", "STUDY"), ("高い", "HIGH"), ("きれい", "CLEAN"),
        ])
        base = self.root / "converted"
        convert(source, base, languages=["en", "ja"])
        expected = {
            "went": "go\nGO", "children": "child\nCHILD", "running": "run\nRUN", "better": "good\nGOOD",
            "食べました": "食べる\nEAT", "食べなかった": "食べる\nEAT", "食べられませんでした": "食べる\nEAT",
            "食べていました": "食べる\nEAT", "帰りました": "帰る\nRETURN", "行った": "行く\nGO-JA",
            "来なかった": "来る\nCOME", "しました": "する\nDO", "勉強しました": "勉強\nSTUDY", "きれいでした": "きれい\nCLEAN",
            "高くなかった": "高い\nHIGH",
        }
        commands = ["DEFINE fixture " + json.dumps(word, ensure_ascii=False) for word in expected]
        for server in ("dico", "dictd"):
            with self.subTest(server=server):
                output = self.query(server, base, commands)
                self.assertEqual(output.count("150 1 definitions"), len(expected))
                for body in expected.values():
                    self.assertIn(body + "\n", output)
        index = self.index(base)
        self.assertEqual(index["went"], index["go"])
        self.assertEqual(index["食べました"], index["食べる"])
        self.assertNotIn("帰ます", index)
        self.assertNotIn("帰ました", index)

    def test_stardict_synonyms_duplicates_unicode_and_markup(self):
        source = self.stardict([
            ("Apple", "<p>first &amp; <b>bold</b></p><p>line</p>"),
            ("Apple", "second"), ("a-b", "punctuation"), ("中", "中文"), ("日本", "Japanese"),
        ], synonyms=[("fruit", 0), ("fruit", 1), ("apple", 0)], bits=64, compressed=True)
        base = self.root / "converted"
        convert(source, base)
        for server in ("dico", "dictd"):
            with self.subTest(server=server):
                output = self.query(server, base, ["DEFINE fixture FRUIT", "DEFINE fixture apple",
                    "DEFINE fixture a-b", "DEFINE fixture 中", "DEFINE fixture 日本", "MATCH fixture exact Apple"])
                self.assertEqual(output.count("150 2 definitions"), 2)
                self.assertEqual(output.count("Apple\nfirst & bold\n\nline"), 2)
                self.assertEqual(output.count("Apple\nsecond"), 2)
                self.assertIn("中\n中文", output)
                self.assertIn("日本\nJapanese", output)
                self.assertIn('fixture "Apple"', output)
        self.assertEqual(len(self.index(base)["apple"]), 2)

    def test_compression_reproducibility_and_no_runtime_python(self):
        source = self.tabfile([("go", "definition" * 10000), ("child", "small")])
        one, two = self.root / "one", self.root / "two"
        convert(source, one, languages=["en"])
        convert(source, two, languages=["en"])
        for suffix in (".index", ".dict.dz", ".json"):
            self.assertEqual(one.with_suffix(suffix).read_bytes(), two.with_suffix(suffix).read_bytes())
        compressed = one.with_suffix(".dict.dz").read_bytes()
        self.assertEqual(compressed[4:8], b"\0" * 4)
        self.assertIn(b"RA", compressed[:100])  # dictzip random-access header
        self.assertLess(len(compressed), len(gzip.decompress(compressed)) // 5)
        self.assertFalse(one.with_suffix(".dict").exists())
        self.assertEqual(sorted(p.name for p in self.root.iterdir()),
                         ["one.dict.dz", "one.index", "one.json", "source.tsv", "two.dict.dz", "two.index", "two.json"])

    def test_disable_inflections_and_preserve_ambiguous_aliases(self):
        source = self.tabfile([("go", "verb"), ("went", "existing definition"), ("child", "noun")])
        base = self.root / "disabled"
        convert(source, base)
        self.assertNotIn("children", self.index(base))
        enabled = self.root / "enabled"
        convert(source, enabled, languages=["en"])
        self.assertEqual(len(self.index(enabled)["went"]), 2)
        for server in ("dico", "dictd"):
            output = self.query(server, enabled, ["DEFINE fixture went"])
            self.assertIn("150 2 definitions", output)
            self.assertIn("existing definition", output)
            self.assertIn("go\nverb", output)

    def test_refuse_existing_output_and_invalid_words(self):
        source = self.stardict([("bad\tword", "definition")])
        base = self.root / "bad"
        with self.assertRaisesRegex(ValueError, "invalid DICT headword"):
            convert(source, base)
        self.assertFalse(base.with_suffix(".index").exists())
        source = self.tabfile([("go", "definition")])
        base.with_suffix(".dict.dz").write_bytes(b"keep this")
        with self.assertRaisesRegex(ValueError, "already exists"):
            convert(source, base)
        self.assertEqual(base.with_suffix(".dict.dz").read_bytes(), b"keep this")

    def test_compression_failure_is_not_silently_accepted(self):
        source = self.tabfile([("go", "definition")])
        base = self.root / "bad"
        with patch("pyglossary.os_utils.runDictzip"), self.assertRaisesRegex(ValueError, "did not produce dictzip"):
            convert(source, base)
        self.assertFalse(base.with_suffix(".index").exists())
        self.assertFalse(base.with_suffix(".dict.dz").exists())

    def test_japanese_lexical_classification_and_irregular_forms(self):
        forms = Inflections(["ja"])
        for word, required, forbidden in [
            ("食べる", "食べました", "食べりました"),
            ("走る", "走った", "走た"), ("行く", "行った", "行いた"),
            ("くる", "こなかった", "くなかった"), ("する", "しなかった", "すらない"),
            ("ある", "なかった", "あらなかった"), ("いい", "よかった", "いかった"),
        ]:
            with self.subTest(word=word):
                self.assertIn(required, forms.forms(word))
                self.assertNotIn(forbidden, forms.forms(word))
        self.assertIn("勉強しました", forms.forms("勉強"))
        self.assertIn("勉強しました", forms.forms("勉強する"))
        self.assertIn("きれいでした", forms.forms("きれい"))
        self.assertFalse(forms.forms("時計"))
        self.assertFalse(forms.forms("ホテル"))
        self.assertFalse(forms.forms("食べました"))


if __name__ == "__main__":
    unittest.main()
