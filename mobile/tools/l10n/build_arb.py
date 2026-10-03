#!/usr/bin/env python3
"""
One-time migration script that produced lib/l10n/app_en.arb and
lib/l10n/app_ru.arb from the old lib/services/app_translations.dart —
two hand-written, opposite-direction dictionaries keyed by literal
source text (`ru`: English source -> Russian text; `en`: Russian
source -> English text, used by the handful of screens — Stats, parts
of Profile, Wrapped-adjacent copy — originally written Russian-first).

Kept in the repo as documentation of exactly how the ARB files were
derived, and as a starting point for a similar extraction later (e.g.
if a future screen is again written in one language first and needs
retrofitting). Safe to re-run against a version-controlled copy of the
old app_translations.dart if you ever need to re-derive or audit the
mapping; it does not touch anything else and only prints to stdout /
writes the two .arb files passed on the command line.

See changes/CHANGES_localization_migration.md for the full
story of this migration, and generate_compat_layer.py in this same
folder for the other half — ARB back into the `.tr`-compatible Dart
lookup tables ~1800 existing call sites still use.

Usage:
    python3 build_arb.py path/to/old_app_translations.dart out_en.arb out_ru.arb
"""
from __future__ import annotations

import json
import re
import sys
from collections import OrderedDict


def extract_map_body(src: str, var_name: str) -> str:
    """Returns the `{ ... }` body of `static const Map<String, String>
    var_name = { ... };`, by depth-counting braces while skipping over
    string literals and `//` comments (so a brace or `//` that happens to
    appear *inside* a translated string — e.g. a pasted URL — doesn't
    confuse the boundary search)."""
    marker = f"static const Map<String, String> {var_name} = {{"
    start = src.index(marker) + len(marker)
    i, depth, n = start, 1, len(src)
    while i < n and depth > 0:
        c = src[i]
        if c == '/' and i + 1 < n and src[i + 1] == '/':
            i = src.index('\n', i) + 1
            continue
        if c in ("'", '"'):
            quote = c
            i += 1
            while i < n:
                if src[i] == '\\':
                    i += 2
                    continue
                if src[i] == quote:
                    i += 1
                    break
                i += 1
            continue
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                break
        i += 1
    return src[start:i]


def tokenize_strings(body: str) -> list[str]:
    """Every string literal in source order, with Dart's `\\'`/`\\n`
    escapes resolved. The dictionaries this reads only ever use those two
    escape forms (verified against the source before writing this) —
    anything else is preserved with its backslash so it's visibly wrong
    rather than silently mis-decoded.

    Both `\\'` and `\\"` always resolve to a literal quote character in
    Dart regardless of which quote delimits the string around them
    (`"it\\'s"` is valid, if unnecessary, Dart) — mapping only the
    delimiter's own quote character here left the *other* one keeping
    its backslash instead of resolving, which is exactly the kind of
    off-by-one-case bug this migration's own coverage checker
    (check_missing_translations.py) is meant to catch elsewhere."""
    tokens, i, n = [], 0, len(body)
    while i < n:
        c = body[i]
        if c == '/' and i + 1 < n and body[i + 1] == '/':
            i = body.index('\n', i) if '\n' in body[i:] else n
            continue
        if c in ("'", '"'):
            quote = c
            i += 1
            buf = []
            while i < n:
                ch = body[i]
                if ch == '\\':
                    nxt = body[i + 1] if i + 1 < n else ''
                    buf.append({'n': '\n', "'": "'", '"': '"', '\\': '\\', '$': '$'}
                               .get(nxt, '\\' + nxt))
                    i += 2
                    continue
                if ch == quote:
                    i += 1
                    break
                buf.append(ch)
                i += 1
            tokens.append(''.join(buf))
            continue
        i += 1
    return tokens


_STOPWORDS = {'a', 'an', 'the', 'is', 'are', 'to', 'of', 'in', 'on', 'for',
              'and', 'this', 'that', 'your', 'you', 'it', 'with', 'or',
              'as', 'at', 'be'}

# Dart reserved words: cannot be used as an identifier in ANY position,
# including `String get <name>`. (Not to be confused with Dart's
# "built-in identifiers" — import, get, static, on, show, hide, etc. —
# which *are* legal getter names and are deliberately left out here.)
# Without this guard, slugify() can and did produce keys like "for"
# (from "for you") or "new" (from "new ›"), which flutter gen-l10n then
# emits verbatim as `String get for;` — a syntax error, not a warning.
_DART_RESERVED_WORDS = {
    'assert', 'break', 'case', 'catch', 'class', 'const', 'continue',
    'default', 'do', 'else', 'enum', 'extends', 'false', 'final',
    'finally', 'for', 'if', 'in', 'is', 'new', 'null', 'rethrow',
    'return', 'super', 'switch', 'this', 'throw', 'true', 'try', 'var',
    'void', 'while', 'with',
}

# Names the generated AppLocalizations class already declares itself
# (see l10n.yaml's `output-class` and the flutter gen-l10n template) —
# an ARB key equal to one of these compiles fine on its own but then
# collides with that existing declaration ("'of' is already declared in
# this scope"). `of` is the one that has actually bitten us; the rest
# are the same shape of bug waiting to happen and cost nothing to guard.
_GENERATED_CLASS_MEMBERS = {
    'of', 'delegate', 'localeName', 'supportedLocales',
    'localizationsDelegates',
}

_UNSAFE_KEY_NAMES = _DART_RESERVED_WORDS | _GENERATED_CLASS_MEMBERS


def slugify(english: str, max_words: int = 6) -> str:
    """"not sure what to watch or play?" -> "notSureWhatToWatch" — a
    short, readable lowerCamelCase ARB key derived from the English
    source, not a hash. Stopwords are dropped after the first word so a
    key never starts with (or consists entirely of) filler.

    The one-word case is where this collides with Dart's own reserved
    words or with a name the generated AppLocalizations class already
    uses: a source string that's just "for" or "new ›" slugifies to the
    single kept word "for"/"new" with nothing to disambiguate it. Rather
    than special-case the dropping logic above (which would still miss
    a translator adding a new single-word "in" or "of" string later),
    every candidate is checked against that fixed list right before
    it's returned, and gets a trailing `Label` if it matches — cheap,
    stable across re-runs, and keeps the key human-readable
    ("forLabel", "ofLabel") instead of an opaque numeric suffix."""
    words = re.findall(r"[A-Za-z0-9]+", english)
    if not words:
        return "text"
    kept = []
    for w in words:
        if len(kept) >= max_words:
            break
        if w.lower() in _STOPWORDS and kept:
            continue
        kept.append(w)
    if not kept:
        kept = words[:max_words]
    camel = kept[0].lower() + ''.join(w.capitalize() for w in kept[1:])
    if camel[0].isdigit():
        camel = 'n' + camel
    if camel in _UNSAFE_KEY_NAMES:
        camel += 'Label'
    return camel


def make_unique_keys(pairs):
    seen = {}
    out = OrderedDict()
    for en, ru in pairs:
        base = slugify(en)
        key, n = base, 2
        while key in out and out[key] != (en, ru):
            key = f"{base}{n}"
            n += 1
        if key in out and out[key] == (en, ru):
            continue  # exact duplicate pair from both source dicts
        out[key] = (en, ru)
    return out


def main() -> None:
    src_path, out_en, out_ru = sys.argv[1], sys.argv[2], sys.argv[3]
    src = open(src_path, encoding='utf-8').read()

    ru_tokens = tokenize_strings(extract_map_body(src, 'ru'))
    en_tokens = tokenize_strings(extract_map_body(src, 'en'))
    ru_pairs = list(zip(ru_tokens[0::2], ru_tokens[1::2]))   # (english, russian)
    en_pairs = list(zip(en_tokens[0::2], en_tokens[1::2]))   # (russian, english)

    canonical = [(en, ru) for en, ru in ru_pairs] + [(en, ru) for ru, en in en_pairs]
    unique = make_unique_keys(canonical)

    en_arb = {"@@locale": "en", **{k: en for k, (en, ru) in unique.items()}}
    ru_arb = {"@@locale": "ru", **{k: ru for k, (en, ru) in unique.items()}}

    json.dump(en_arb, open(out_en, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
    json.dump(ru_arb, open(out_ru, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
    print(f"{len(unique)} unique entries -> {out_en}, {out_ru}")


if __name__ == '__main__':
    main()
