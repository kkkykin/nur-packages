"""Keep Yomitan deinflection references readable with PyGlossary's ZIP reader."""
from html import escape
import json
from urllib.parse import quote

from pyglossary.plugins.yomichan.reader import Reader, _readDefinition


def definition_html(definitions):
    parts = []
    for definition in definitions:
        if isinstance(definition, list):
            # Yomitan v3 also allows [uninflected term, inflection rule chain].
            # Jitendex uses these for redirects from old kanji and other forms.
            if (len(definition) != 2 or not isinstance(definition[0], str)
                    or not isinstance(definition[1], list)
                    or not all(isinstance(rule, str) for rule in definition[1])):
                raise ValueError(f"invalid Yomitan deinflection: {definition!r}")
            target, rules = definition
            link = f'<a href="bword://{quote(target, safe="")}">{escape(target)}</a>'
            annotation = " (" + "; ".join(map(escape, rules)) + ")" if rules else ""
            parts.append(f"<div>→ {link}{annotation}</div>")
        else:
            parts.append(_readDefinition([definition]))
    return "\n".join(parts)


class YomitanReader(Reader):
    def _readIndex(self):
        super()._readIndex()
        with self._dictFile.open("index.json") as stream:
            index = json.load(stream)
        if attribution := index.get("attribution"):
            self._glos.setInfo("copyright", attribution)
        if url := index.get("url"):
            self._glos.setInfo("website", url)

    def _readTermBank(self, name):
        with self._dictFile.open(name) as stream:
            bank = json.load(stream)
        for item in bank:
            term = [item[0], item[1]] if item[1] else item[0]
            yield self._glos.newEntry(term, definition_html(item[5]), defiFormat="h")
