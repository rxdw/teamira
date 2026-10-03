#!/usr/bin/env python3
"""
Scans every `'...'.tr` / `"...".tr` call site in lib/ and reports any
literal string that has no corresponding entry in lib/l10n/app_en.arb or
lib/l10n/app_ru.arb — the actual, reliable answer to "I changed the UI
text by one character and the translation silently fell back to the
source language".

Why a static script rather than a runtime check: `.tr` (see
lib/services/app_translations.dart) already collects misses into
`debugMissingTranslations` at runtime, but a runtime miss can't tell a
genuine bug (a source string was edited, the old ARB key is now
orphaned, the new text falls back untranslated) apart from a string
that's legitimately identical in both languages by design ("PDF", "OK",
a brand name) and was correctly never in either ARB file — those would
fire the exact same "miss" at runtime with no way to tell them apart
without a human. This script can't fully tell them apart either, but it
runs over every call site at once, every time, deterministically, which
a person skimming a diff cannot — so pair it with judgement: a big new
batch of misses after a text edit is almost certainly the edit; a single
short, ALL-CAPS, or non-letter miss is very often a deliberate
identical-in-both-languages string.

Usage (from mobile/):
    python3 tools/l10n/check_missing_translations.py
    python3 tools/l10n/check_missing_translations.py --ci   # exit 1 on any miss

Intended to run in CI on every PR that touches lib/**/*.dart or
lib/l10n/*.arb — wire it into whatever CI this repo already uses
alongside `flutter analyze`.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]  # mobile/
LIB = ROOT / "lib"
ARB_EN = ROOT / "lib/l10n/app_en.arb"
ARB_RU = ROOT / "lib/l10n/app_ru.arb"

_CYRILLIC = re.compile('[\u0400-\u04FF]')
# Matches 'literal'.tr and "literal".tr — deliberately NOT matching a
# `.tr` on anything but a plain string literal (an interpolated string
# like '$x'.tr or a variable's .tr can't be checked statically, and
# isn't how this app uses .tr anyway — every real call site is a plain
# literal, by convention).
_TR_CALL = re.compile(r"""(?P<q>['"])(?P<text>(?:\\.|(?!\1).)*)(?P=q)\.tr\b""")


def unescape_dart(s: str, quote: str) -> str:
    # Both \' and \" always produce a literal quote character in Dart,
    # regardless of which quote character actually delimits the string —
    # "hasn\'t" is valid (if unnecessary) Dart for hasn't, the same as
    # 'hasn\'t' would be. Not just `quote: quote`, or the *other* quote
    # character escaped inside a string delimited by this one silently
    # keeps its backslash instead of resolving to a bare quote.
    out = []
    i = 0
    while i < len(s):
        if s[i] == '\\' and i + 1 < len(s):
            nxt = s[i + 1]
            out.append({'n': '\n', "'": "'", '"': '"', '\\': '\\', '$': '$'}
                       .get(nxt, '\\' + nxt))
            i += 2
        else:
            out.append(s[i])
            i += 1
    return ''.join(out)


def find_call_sites(path: Path) -> list[tuple[int, str]]:
    text = path.read_text(encoding='utf-8')
    sites = []
    for m in _TR_CALL.finditer(text):
        literal = unescape_dart(m.group('text'), m.group('q'))
        line = text.count('\n', 0, m.start()) + 1
        sites.append((line, literal))
    return sites


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--ci', action='store_true',
                         help='exit with status 1 if any missing translation is found')
    args = parser.parse_args()

    en = json.loads(ARB_EN.read_text(encoding='utf-8'))
    ru = json.loads(ARB_RU.read_text(encoding='utf-8'))
    en_values = {v for k, v in en.items() if not k.startswith('@')}
    ru_values = {v for k, v in ru.items() if not k.startswith('@')}
    known = en_values | ru_values

    missing: dict[str, list[str]] = {}
    total_sites = 0
    for path in sorted(LIB.rglob('*.dart')):
        if path.name == 'app_translations.dart':
            continue  # the compat layer's own doctest-style examples, not UI copy
        for line, literal in find_call_sites(path):
            total_sites += 1
            if literal in known:
                continue
            rel = path.relative_to(ROOT)
            missing.setdefault(literal, []).append(f"{rel}:{line}")

    print(f"scanned {total_sites} '.tr' call sites across lib/")
    if not missing:
        print("no missing translations — every .tr literal has ARB coverage.")
        return 0

    print(f"\n{len(missing)} distinct literal(s) with no ARB entry in either language:\n")
    for literal, locations in sorted(missing.items()):
        is_cyrillic = bool(_CYRILLIC.search(literal))
        direction = "ru->en" if is_cyrillic else "en->ru"
        preview = literal if len(literal) <= 70 else literal[:67] + "..."
        print(f"  [{direction}] {preview!r}")
        for loc in locations[:3]:
            print(f"      {loc}")
        if len(locations) > 3:
            print(f"      ...and {len(locations) - 3} more")

    if args.ci:
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
