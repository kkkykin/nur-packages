"""Build-time inflection aliases. No morphology engine is needed by the server."""
from functools import lru_cache
import re


class Inflections:
    def __init__(self, languages):
        self.english = None
        self.tagger = None
        if "en" in languages:
            from lemminflect import getAllInflections
            self.english = getAllInflections
        if "ja" in languages:
            import fugashi
            import unidic_lite
            self.tagger = fugashi.Tagger(f'-r /dev/null -d "{unidic_lite.DICDIR}"')

    @lru_cache(maxsize=4096)
    def forms(self, word):
        forms = set()
        if self.english and re.fullmatch(r"[A-Za-z]+(?:[-' ][A-Za-z]+)*", word):
            # Dictionary-backed forms include irregular verbs and plurals. Do
            # not guess a part of speech for unknown words/proper names.
            for variants in self.english(word).values():
                forms.update(variants)
        if self.tagger and re.search(r"[\u3040-\u30ff\u3400-\u9fff]", word):
            tokens = list(self.tagger(word))
            if tokens and "".join(t.surface for t in tokens) == word:
                token = tokens[-1]
                feature = token.feature
                # Only inflect dictionary forms, not arbitrary nouns ending in
                # い/る or already inflected headwords. UniDic distinguishes
                # ichidan 食べる from godan 帰る, and lexical exceptions.
                if feature.pos1 == "名詞" and "サ変可能" in feature.pos3:
                    # Many dictionaries list 勉強 rather than 勉強する.
                    forms.add(word + "する")
                    forms.update(verb_forms(word + "する", "suru"))
                if feature.pos1 == "形状詞" or (feature.cForm and feature.cForm.startswith("終止形")):
                    prefix = word[:-len(token.surface)]
                    forms.update(prefix + form for form in japanese_forms(
                        token.surface, feature.cType, feature.pos1))
        forms.discard(word)
        return tuple(sorted(forms))


def adjective_forms(word):
    stem = word[:-1]
    if word == "いい":
        stem = "よ"
    return {
        word + "です", stem + "かった", stem + "かったです",
        stem + "く", stem + "くて", stem + "ければ", stem + "かったら",
        stem + "くない", stem + "くなかった", stem + "くなくて",
        stem + "くなければ", stem + "くなかったら",
        stem + "くないです", stem + "くなかったです",
        stem + "くありません", stem + "くありませんでした",
    }


def verb_forms(word, kind, *, derived=True):
    """Finite modern forms, including one voice/aspect + tense/politeness.

    Deliberately no recursive closure: auxiliary chains are unbounded and
    would produce an enormous index. The supported families are documented.
    """
    root = word[:-1]
    if kind == "ichidan":
        stem, negative, te, past = root, root + "ない", root + "て", root + "た"
        conditional, imperative, volitional = root + "れば", root + "ろ", root + "よう"
        voices = {root + "られる", root + "させる", root + "させられる"}
    elif kind == "suru":
        root = word[:-2]
        stem, negative, te, past = root + "し", root + "しない", root + "して", root + "した"
        conditional, imperative, volitional = root + "すれば", root + "しろ", root + "しよう"
        voices = {root + "される", root + "させる", root + "させられる", root + "できる"}
    elif kind == "kuru":
        root = word[:-2]
        ki, ko, ku = (root + "来",) * 3 if word.endswith("来る") else (root + "き", root + "こ", root + "く")
        stem, negative, te, past = ki, ko + "ない", ki + "て", ki + "た"
        conditional, imperative, volitional = ku + "れば", ko + "い", ko + "よう"
        voices = {ko + "られる", ko + "させる", ko + "させられる"}
    else:
        # a/i/e/o rows and sound changes for the te/ta forms.
        rows = {
            "う": ("わ", "い", "え", "お", "って"),
            "く": ("か", "き", "け", "こ", "いて"),
            "ぐ": ("が", "ぎ", "げ", "ご", "いで"),
            "す": ("さ", "し", "せ", "そ", "して"),
            "つ": ("た", "ち", "て", "と", "って"),
            "ぬ": ("な", "に", "ね", "の", "んで"),
            "ぶ": ("ば", "び", "べ", "ぼ", "んで"),
            "む": ("ま", "み", "め", "も", "んで"),
            "る": ("ら", "り", "れ", "ろ", "って"),
        }
        if word[-1] not in rows:
            return set()
        a, i, e, o, ending = rows[word[-1]]
        stem, negative, te = root + i, root + a + "ない", root + ending
        if word in {"行く", "いく", "ゆく", "逝く", "往く"}:
            te = root + "って"
        if word in {"ある", "有る", "在る"}:
            negative = "ない"
        if word in {"くださる", "下さる", "なさる", "いらっしゃる", "おっしゃる", "仰る", "ござる"}:
            stem = root + "い"
        past = te[:-1] + ("た" if te.endswith("て") else "だ")
        conditional, imperative, volitional = root + e + "ば", root + e, root + o + "う"
        voices = {root + e + "る", root + a + "れる", root + a + "せる", root + a + "せられる"}
    forms = {
        stem + "ます", stem + "ました", stem + "ません", stem + "ませんでした",
        stem + "ましょう", te, past, past + "ら", past + "り",
        negative, negative[:-1] + "かった", negative[:-1] + "くて",
        negative[:-1] + "ければ", negative + "で", negative + "でください",
        conditional, imperative, volitional, te + "ください", word + "な",
    }
    if derived:
        forms.update({stem + "たい", *adjective_forms(stem + "たい")})
        # Potential/passive/causative and progressive forms, with their own
        # polite, negative and past forms. Do not conjugate them recursively.
        for derived_word in voices | {te + "いる"}:
            forms.add(derived_word)
            forms.update(verb_forms(derived_word, "ichidan", derived=False))
    return forms


def japanese_forms(word, conjugation, part_of_speech):
    if part_of_speech == "形状詞":
        return {word + ending for ending in (
            "だ", "です", "だった", "でした", "なら", "ならば", "で",
            "ではない", "ではなかった", "ではありません", "ではありませんでした",
            "じゃない", "じゃなかった", "じゃありません", "じゃありませんでした",
        )}
    if part_of_speech == "形容詞" and conjugation == "形容詞" and word.endswith("い"):
        return adjective_forms(word)
    if part_of_speech != "動詞":
        return set()
    if conjugation.startswith(("上一段", "下一段")):
        return verb_forms(word, "ichidan") if word.endswith("る") else set()
    if conjugation.startswith("五段"):
        return verb_forms(word, "godan")
    if conjugation == "サ行変格" and word.endswith("する"):
        return verb_forms(word, "suru")
    if conjugation == "カ行変格" and word.endswith(("くる", "来る")):
        return verb_forms(word, "kuru")
    return set()
