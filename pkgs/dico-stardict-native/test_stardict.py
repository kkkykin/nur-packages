"""Exercise the native module through an unmodified dicod's DICT protocol."""
import gzip
import json
import os
from pathlib import Path
import shlex
import struct
import subprocess
import tempfile
import unittest


class StarDictProtocolTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="dico-stardict-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def dictionary(self, records, *, sequence="m", bits=32, compressed=False,
                   synonyms=(), base="fixture", sparse_offset=0):
        path = self.root / base
        data, index = bytearray(), bytearray()
        for word, article in records:
            article = article.encode() if isinstance(article, str) else article
            index += word.encode() + b"\0"
            index += struct.pack(">QI" if bits == 64 else ">II", sparse_offset + len(data), len(article))
            data += article
        info = ["StarDict's dict ifo file", "version=3.0.0" if bits == 64 else "version=2.4.2",
                "bookname=测试词典", f"wordcount={len(records)}", f"idxfilesize={len(index)}",
                f"idxoffsetbits={bits}", f"synwordcount={len(synonyms)}"]
        if sequence:
            info.append("sametypesequence=" + sequence)
        path.with_suffix(".ifo").write_text("\n".join(info) + "\n", encoding="utf-8")
        if compressed:
            path.with_suffix(".idx.gz").write_bytes(gzip.compress(index))
            path.with_suffix(".dict.dz").write_bytes(gzip.compress(data))
        else:
            path.with_suffix(".idx").write_bytes(index)
            with path.with_suffix(".dict").open("wb") as output:
                output.seek(sparse_offset)
                output.write(data)
        if synonyms:
            path.with_suffix(".syn").write_bytes(b"".join(
                word.encode() + b"\0" + struct.pack(">I", entry) for word, entry in synonyms))
        return path.with_suffix(".ifo")

    def query(self, ifo, *commands):
        module = os.environ["STARDICT_MODULE"]
        config = self.root / "dicod.conf"
        quote = lambda value: json.dumps(value, ensure_ascii=False)
        config.write_text(
            "timing no;\ncapability (mime);\n"
            + "load-module stardict { command " + quote(shlex.join([module])) + "; }\n"
            + "database { name fixture; handler " + quote(shlex.join(["stardict", str(ifo)])) + "; }\n",
            encoding="utf-8")
        return subprocess.run(
            [os.environ["DICOD"], "--inetd", "--stderr", "--no-preprocessor", "--config=" + str(config)],
            input="\r\n".join([*commands, "QUIT", ""]), text=True, encoding="utf-8",
            capture_output=True, timeout=30)

    def success(self, result):
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("220 ", result.stdout)
        self.assertIn("221 ", result.stdout)
        self.assertEqual(result.stderr, "")
        return result.stdout

    def test_definitions_duplicates_synonyms_and_unicode_casefold(self):
        ifo = self.dictionary([
            ("hello", "first"), ("hello", "second"), ("Straße", "street"), ("中", "zhōng"),
        ], synonyms=[("greeting", 0), ("greeting", 1), ("HELLO", 0), ("中文", 3)])
        output = self.success(self.query(ifo, "SHOW DB", "SHOW INFO fixture",
                                          "DEFINE fixture HELLO", "DEFINE fixture greeting",
                                          "DEFINE fixture STRASSE", "DEFINE fixture 中文",
                                          "DEFINE fixture missing"))
        self.assertIn('fixture "测试词典"', output)
        self.assertEqual(output.count("150 2 definitions found"), 2)
        self.assertEqual(output.count("\nfirst\n"), 2)
        self.assertEqual(output.count("\nsecond\n"), 2)
        self.assertIn("Straße\nstreet", output)
        self.assertIn("中\nzhōng", output)
        self.assertIn("552 ", output)

    def test_match_strategies_and_duplicate_spelling(self):
        ifo = self.dictionary([(word, "definition") for word in ["hello", "hello", "help", "shell", "world"]])
        output = self.success(self.query(ifo,
            "MATCH fixture exact HELLO", "MATCH fixture prefix HEL", "MATCH fixture suffix LD",
            "MATCH fixture substring ELL", 'MATCH fixture regexp "^hel.*$"',
            "MATCH fixture lev helo", "MATCH fixture soundex hello"))
        self.assertEqual(output.count("152 "), 7)
        self.assertIn("152 2 matches found", output)
        self.assertEqual(output.count('fixture "hello"'), 6)
        self.assertIn('fixture "world"', output)
        self.assertIn('fixture "shell"', output)

    def test_compressed_index_and_data_with_64_bit_records(self):
        ifo = self.dictionary([("alpha", "α"), ("beta", "β"), ("zero", "")], bits=64, compressed=True)
        output = self.success(self.query(ifo, "DEFINE fixture beta", "DEFINE fixture alpha",
                                          "DEFINE fixture zero"))
        self.assertIn("beta\nβ", output)
        self.assertIn("alpha\nα", output)
        self.assertEqual(output.count("150 1 definitions found"), 3)

    @unittest.skipUnless(struct.calcsize("P") >= 8, "requires a 64-bit address space")
    def test_offset_above_four_gib(self):
        ifo = self.dictionary([("large", "beyond 32 bits")], bits=64, sparse_offset=2**32 + 16)
        output = self.success(self.query(ifo, "DEFINE fixture large"))
        self.assertIn("large\nbeyond 32 bits", output)

    def test_explicit_types_markup_entities_binary_and_mime(self):
        article = (b"mplain\0h<p title='x>y'>HTML &amp; &#x4e2d;&NotEqualTilde;"
                   b"<br>line<!-- hidden --></p>\0" + b"W" + struct.pack(">I", 3) + b"\0\xff\0")
        ifo = self.dictionary([("typed", article)], sequence="")
        output = self.success(self.query(ifo, "OPTION MIME", "DEFINE fixture typed"))
        self.assertIn("Content-Type: text/plain; charset=utf-8", output)
        self.assertIn("Content-Transfer-Encoding: 8bit", output)
        self.assertIn("plain\nHTML & 中≂̸\nline\n[binary field W: 3 bytes]", output)
        self.assertNotIn("hidden", output)
        self.assertNotIn("<p", output)

    def test_same_type_sequence_and_protocol_escaping(self):
        article = b"pronunciation\0" + "<b>definition</b> &quot;quoted&quot;\n.\n.dot".encode()
        word = 'a "quote" \\ path'
        ifo = self.dictionary([(word, article)], sequence="mh", base="dictionary with spaces")
        output = self.success(self.query(ifo, "DEFINE fixture " + json.dumps(word),
                                          "MATCH fixture exact " + json.dumps(word)))
        self.assertIn('pronunciation\ndefinition "quoted"\n..\n..dot', output)
        self.assertIn('fixture "a \\"quote\\" \\\\ path"', output)

    def test_empty_dictionary(self):
        ifo = self.dictionary([])
        output = self.success(self.query(ifo, "DEFINE fixture missing", 'MATCH fixture prefix ""'))
        self.assertEqual(output.count("552 "), 2)

    def test_reject_malformed_metadata_index_synonym_and_offsets(self):
        mutations = [
            (".ifo", lambda data: data.replace(b"wordcount=1", b"wordcount=-1")),
            (".ifo", lambda data: data.replace(b"idxoffsetbits=32", b"idxoffsetbits=48")),
            (".ifo", lambda data: data.replace(b"version=2.4.2", b"version=9.9.9")),
            (".idx", lambda data: data[:-1]),
            (".idx", lambda data: b"\xff" + data[1:]),
            (".syn", lambda data: data[:-4] + struct.pack(">I", 99)),
            (".dict", lambda data: b""),
        ]
        for suffix, mutate in mutations:
            with self.subTest(suffix=suffix, mutate=mutate):
                ifo = self.dictionary([("test", "definition")], synonyms=[("alias", 0)])
                file = ifo.with_suffix(suffix)
                file.write_bytes(mutate(file.read_bytes()))
                result = self.query(ifo, "SHOW DB", "DEFINE fixture test")
                # dicod removes a failed database and keeps serving the session.
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("cannot load dictionary", result.stderr)
                self.assertIn("removing database fixture", result.stderr)
                self.assertIn("554 No databases present", result.stdout)
                self.assertIn("550 invalid database", result.stdout)
                self.assertNotIn("150 ", result.stdout)

    def test_reject_truncated_typed_article(self):
        for sequence, article in [("", b"mno terminator"), ("", b"W\0\0\0\x20x"), ("mm", b"no separator")]:
            with self.subTest(sequence=sequence, article=article):
                ifo = self.dictionary([("broken", article)], sequence=sequence)
                result = self.query(ifo, "DEFINE fixture broken")
                self.assertIn("invalid article for broken", result.stderr)
                self.assertNotIn("no terminator", result.stdout)


if __name__ == "__main__":
    unittest.main()
