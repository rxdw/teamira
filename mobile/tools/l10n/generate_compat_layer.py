#!/usr/bin/env python3
"""
Regenerates lib/services/app_translations.dart from lib/l10n/app_en.arb
and lib/l10n/app_ru.arb.

Why this exists at all, given `flutter gen-l10n` already turns those same
ARB files into a real, officially-generated `AppLocalizations` class
(lib/l10n/app_localizations.dart, via l10n.yaml): that class needs a
BuildContext (`AppLocalizations.of(context)`), and roughly 1800 existing
call sites across this app call `'some literal string'.tr` with no
context in reach — inside static helpers, model formatters, and plain
(non-widget) classes, not just inside `build()` methods. Rewriting all
1800 to thread a BuildContext through would be a much larger, much
riskier change than the localization gap this migration was meant to
close, and isn't something to do by search-and-replace without a
compiler on hand to verify every site.

So the ARB files are still the single source of truth — CI or a human
editing lib/l10n/*.arb and re-running this script is now the *only*
supported way strings get into the app, replacing the old pattern of
hand-editing two independent, opposite-direction Dart dictionaries — but
they're compiled here into a second, context-free artifact that keeps
every existing `.tr` call site working completely unchanged. New code
should prefer `AppLocalizations.of(context).xyz` (typed, autocompleted,
validated at build time by gen-l10n); `.tr` remains supported for
everything already written against it.

Usage (from mobile/):
    python3 tools/l10n/generate_compat_layer.py

Regenerates lib/services/app_translations.dart in place. Run this after
any edit to lib/l10n/app_en.arb or lib/l10n/app_ru.arb — the two files
must stay in lockstep (same keys) or this script raises rather than
silently emitting a mismatched compat layer.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]  # mobile/
ARB_EN = ROOT / "lib/l10n/app_en.arb"
ARB_RU = ROOT / "lib/l10n/app_ru.arb"
OUT = ROOT / "lib/services/app_translations.dart"

_PLURAL_RE = re.compile(
    r"^\{count, plural, (?P<body>.+)\}$"
)
_PLURAL_FORM_RE = re.compile(
    r"(zero|one|two|few|many|other) \{\{count\} ([^{}]*)\}"
)


def _is_plural_message(s: str) -> bool:
    return s.startswith("{count, plural,")


def _plural_block_end(msg: str) -> int:
    """Index of the `}` that closes the outer `{count, plural, ...}`
    block — i.e. where the message text resumes (if any), for a compound
    message like friendsJoinedWithCode's trailing ` — +{xp} xp so far`.

    Deliberately not `msg.rindex('}')`: the message can contain other,
    *later* brace pairs after the plural block closes (`{xp}` in exactly
    that example), so the last `}` in the whole string is the wrong one.
    This instead depth-counts forward from the message's own opening
    `{`, the only reliable way to find where that specific pair closes.
    """
    assert msg[0] == '{', f"expected a message starting with '{{': {msg!r}"
    depth = 0
    for i, ch in enumerate(msg):
        if ch == '{':
            depth += 1
        elif ch == '}':
            depth -= 1
            if depth == 0:
                return i
    raise ValueError(f"unbalanced braces in plural message: {msg!r}")


def _parse_plural_forms(msg: str) -> dict:
    """Pulls the `one {...}`, `few {...}`, etc. noun forms back out of an
    ICU plural message of the exact shape this migration writes
    (`{count, plural, one {{count} X} few {{count} Y} ...}`, optionally
    followed by more text after the closing brace for a compound
    message like friendsJoinedWithCode). Only handles that one shape —
    see this module's own docstring; if lib/l10n/*.arb ever grows a
    plural message with placeholders beyond `{count}`, or with `select`/
    `selectordinal` constructs, this raises rather than mis-parsing it,
    which is the correct failure mode for a codegen step.
    """
    block = msg[:_plural_block_end(msg) + 1]
    forms = {}
    for form, noun in _PLURAL_FORM_RE.findall(block):
        forms[form] = noun.strip()
    if 'other' not in forms:
        raise ValueError(f"plural message missing required 'other' form: {msg!r}")
    return forms


def esc(s: str) -> str:
    """Dart single-quoted string literal escaping — only `\\` and `'`
    need it for anything actually present in these ARB files (checked:
    no raw newlines survive past the ARB layer unescaped, no `$`)."""
    return s.replace('\\', '\\\\').replace("'", "\\'").replace('\n', '\\n')


def main() -> None:
    en = json.loads(ARB_EN.read_text(encoding='utf-8'))
    ru = json.loads(ARB_RU.read_text(encoding='utf-8'))

    en_keys = {k for k in en if not k.startswith('@')}
    ru_keys = {k for k in ru if not k.startswith('@')}
    if en_keys != ru_keys:
        missing_in_ru = en_keys - ru_keys
        missing_in_en = ru_keys - en_keys
        raise SystemExit(
            "app_en.arb and app_ru.arb have drifted apart — every key must "
            f"exist in both.\n  missing in ru: {sorted(missing_in_ru)[:10]}\n"
            f"  missing in en: {sorted(missing_in_en)[:10]}"
        )

    plain_keys = [k for k in en_keys if not _is_plural_message(en[k])]
    plural_keys = [k for k in en_keys if _is_plural_message(en[k])]
    # The one hand-authored compound message (noun + verb agreement +
    # an extra {xp} placeholder) doesn't fit the generic plural-catalog
    # shape below — it's emitted as its own small resolver function
    # instead of a catalog entry. See build_final_arb (or
    # changes/CHANGES_localization_migration.md) for why it exists at all.
    compound_keys = [k for k in plural_keys if '{xp}' in en[k]]
    plural_keys = [k for k in plural_keys if k not in compound_keys]

    # --- bulk (english_source -> russian) and (russian_source -> english) ---
    # [TrString.tr] looks these dicts up by literal source text, so two
    # different ARB keys whose *source*-language text happens to be
    # identical (e.g. "days" used as both a calendar unit and a section
    # header, correctly given two different Russian forms in the ARB)
    # necessarily produce a duplicate key here — there's no third
    # language to disambiguate by. That's a real, pre-existing ambiguity
    # in the flat `.tr()` design (see this file's own docstring), not
    # something this generator can fix by picking a "correct" side; it's
    # printed so a human can see it and, if it matters, reword one of
    # the ARB entries to stop colliding. Left as a `final` (not `const`)
    # map below so a collision degrades to "last write wins" — exactly
    # how a plain, non-const Dart map literal already behaves, and how
    # the hand-maintained dictionaries this replaced behaved — rather
    # than a hard compile error.
    def _warn_dupes(pairs, direction):
        seen = {}
        for source, translated, key in pairs:
            if source in seen and seen[source][0] != translated:
                print(f"  ! duplicate {direction} source text {source!r}: "
                      f"{seen[source][1]!r} -> {seen[source][0]!r} vs "
                      f"{key!r} -> {translated!r} (last one wins at runtime)")
            seen[source] = (translated, key)

    _warn_dupes([(en[k], ru[k], k) for k in sorted(plain_keys)], "English")
    _warn_dupes([(ru[k], en[k], k) for k in sorted(plain_keys)], "Russian")

    ru_dict_lines = []
    en_dict_lines = []
    for k in sorted(plain_keys):
        e, r = en[k], ru[k]
        ru_dict_lines.append(f"    '{esc(e)}': '{esc(r)}',")
        en_dict_lines.append(f"    '{esc(r)}': '{esc(e)}',")

    # --- plural catalog -----------------------------------------------
    catalog_lines = []
    for k in sorted(plural_keys):
        ru_forms = _parse_plural_forms(ru[k])
        en_forms = _parse_plural_forms(en[k])
        catalog_lines.append(
            "  '{key}': PluralForms(one: '{one}', few: '{few}', many: '{many}', "
            "englishOne: '{eone}', englishOther: '{eother}'),".format(
                key=k,
                one=esc(ru_forms.get('one', ru_forms['other'])),
                few=esc(ru_forms.get('few', ru_forms['other'])),
                many=esc(ru_forms.get('many', ru_forms['other'])),
                eone=esc(en_forms.get('one', en_forms['other'])),
                eother=esc(en_forms.get('other')),
            )
        )

    # --- the one compound message --------------------------------------
    compound_fn_lines = []
    for k in compound_keys:
        ru_msg, en_msg = ru[k], en[k]
        ru_forms = _parse_plural_forms(ru_msg)
        en_forms = _parse_plural_forms(en_msg)

        def dart_map_literal(forms: dict) -> str:
            # Built explicitly (not via Python's dict repr(), which
            # happens to *often* look like valid Dart map syntax but
            # isn't guaranteed to — e.g. its quote-style choice per
            # entry depends on each string's own content) so every
            # character that ends up in the generated .dart file went
            # through this module's own `esc()`, the same escaping used
            # everywhere else in this generator.
            items = ", ".join(f"'{form}': '{esc(noun)}'" for form, noun in forms.items())
            return "{" + items + "}"

        # Text after the plural block's closing brace, common to every
        # form (e.g. " — +{xp} xp so far") — split out once so the
        # generated function only substitutes {xp} in one place.
        ru_suffix = ru_msg[_plural_block_end(ru_msg) + 1:]
        en_suffix = en_msg[_plural_block_end(en_msg) + 1:]
        compound_fn_lines.append(f'''
/// Generated from ARB key `{k}` — a whole-sentence plural (noun and verb
/// agreement folded together), not a reusable noun family, which is why
/// it's its own function instead of a [pluralCatalog] entry. See
/// changes/CHANGES_localization_migration.md for why composing this from a
/// separate noun fragment and a hand-branched verb was the pattern being
/// fixed, not preserved.
String {k}(int count, int xp) {{
  final ru = {dart_map_literal(ru_forms)};
  final en = {dart_map_literal(en_forms)};
  final forms = LocaleService.appIsRussian ? ru : en;
  final category = LocaleService.appIsRussian
      ? _ruCategory(count)
      : (count == 1 ? 'one' : 'other');
  final form = forms[category] ?? forms['other']!;
  final sentence = form.replaceAll('{{count}}', '$count');
  final suffix = (LocaleService.appIsRussian ? '{esc(ru_suffix)}' : '{esc(en_suffix)}')
      .replaceAll('{{xp}}', '$xp');
  return '$sentence$suffix';
}}
''')

    template = f'''// GENERATED FILE — DO NOT EDIT BY HAND.
//
// Source of truth: lib/l10n/app_en.arb + lib/l10n/app_ru.arb
// Regenerate with: python3 tools/l10n/generate_compat_layer.py
//
// This is the compatibility layer for the ~1800 `'some string'.tr` call
// sites written before this app adopted ARB. New code should prefer the
// officially-generated `AppLocalizations.of(context)` (see l10n.yaml,
// lib/l10n/*.arb) — typed, autocomplete-friendly, and checked against
// the template ARB file at build time. `.tr` keeps working, unchanged,
// for everything already written against it; see this file's own
// top-of-module docstring in generate_compat_layer.py for the full
// reasoning on why both exist side by side rather than one replacing
// the other outright.
//
// UI copy translations for the interface-language toggle in Settings
// ('russian interface'). [AppTranslations.ru] is keyed by English source
// text (most of the app); [AppTranslations.en] is keyed by Russian
// source text (Stats, parts of Profile, and other screens originally
// written Russian-first). A miss in either map falls back to the
// original source text — safe by construction, never a blank label; see
// [TrString.tr] below for how the two are chosen between, and
// [debugMissingTranslations] for how a miss is surfaced during
// development instead of just silently passing through.
//
// Known gap: screens/profile/wrapped_screen.dart used to be written
// entirely in Russian and unwired from this file. That's fixed as part
// of this same migration — see changes/CHANGES_localization_migration.md — but
// a couple of decorative month/weekday abbreviations on ticket- and
// stamp-style widgets (widgets/ticket.dart, stamp.dart) are still
// hand-rolled short forms rather than routed through `.tr`.

import 'locale_service.dart';

class AppTranslations {{
  // Not `const`: see this generator's own _warn_dupes() docstring —
  // two different ARB keys can legitimately share the same source-
  // language text, which a `const` map literal rejects outright as a
  // duplicate-key compile error even when nothing is actually wrong
  // with either entry on its own.
  static final Map<String, String> ru = {{
{chr(10).join(ru_dict_lines)}
  }};

  static final Map<String, String> en = {{
{chr(10).join(en_dict_lines)}
  }};
}}

const _cyrillic = _CyrillicMatcher();

/// A tiny stand-in for `RegExp(r'[\\u0400-\\u04FF]')` that's `const`-
/// constructible — regex literals in Dart can't be `const`, and this is
/// checked on every single `.tr` call, including ones that run during
/// widget build; avoiding a fresh RegExp allocation per call is cheap
/// insurance at that call volume.
class _CyrillicMatcher {{
  const _CyrillicMatcher();
  bool hasMatch(String s) {{
    for (final code in s.codeUnits) {{
      if (code >= 0x0400 && code <= 0x04FF) return true;
    }}
    return false;
  }}
}}

extension TrString on String {{
  String get tr {{
    final wantRussian = LocaleService.appIsRussian;
    final isRussianSource = _cyrillic.hasMatch(this);
    final hit = wantRussian
        ? (isRussianSource ? null : AppTranslations.ru[this])
        : (!isRussianSource ? null : AppTranslations.en[this]);
    final attemptedLookup = wantRussian != isRussianSource;
    if (hit == null && attemptedLookup) {{
      // A miss in the direction that actually needed translating —
      // as opposed to a string that's legitimately identical in both
      // languages (a brand name, "PDF", "OK") and was never in either
      // map to begin with. See debugMissingTranslations's own doc for
      // why this only logs rather than asserting.
      debugMissingTranslations.add(this);
    }}
    final resolved = hit ?? this;
    return _lowercaseUiText(resolved);
  }}
}}

/// Every literal string that reached [TrString.tr] wanting the *other*
/// language and found no entry for it — populated only in debug mode
/// (see main.dart's own startup hook, if wired; safe to ignore
/// otherwise, this is purely a development aid).
///
/// This is what actually answers the old "changed the UI text by one
/// character, the translation silently fell back to English" problem:
/// rather than guess at runtime whether a miss is a real bug or a
/// string that's deliberately identical in both languages (which would
/// make a hard assert fire constantly for legitimate cases like "PDF"
/// or "OK" and train everyone to ignore it), every miss is collected
/// here and can be printed or asserted-empty from a widget test or a
/// dev-only debug panel. See tools/l10n/check_missing_translations.py
/// for the complementary *static* check — scans every `.tr` literal in
/// the codebase against lib/l10n/*.arb without running the app at all,
/// which is the version worth running in CI.
final Set<String> debugMissingTranslations = <String>{{}};

/// Russian noun plurals depend on the number itself (1 тайтл vs. 2–4
/// тайтла vs. 5+ тайтлов, with an exception for 11–14) — unlike
/// English's simple one/other split. [PluralForms] holds the three
/// Russian forms plus the two English ones for a given noun; see
/// [pluralCatalog] for the ones already generated from lib/l10n/*.arb's
/// ICU plural messages, and [nCount]/[nOnly] for how to use them.
class PluralForms {{
  final String one, few, many, englishOne, englishOther;
  const PluralForms({{
    required this.one,
    required this.few,
    required this.many,
    required this.englishOne,
    required this.englishOther,
  }});
}}

/// Every reusable "count + noun" family used more than once across the
/// app, generated from the ICU plural messages in lib/l10n/*.arb —
/// editing a form here means editing the .arb and re-running
/// tools/l10n/generate_compat_layer.py, not this file directly.
const Map<String, PluralForms> pluralCatalog = {{
{chr(10).join(catalog_lines)}
}};

String _ruCategory(int n) {{
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 14) return 'many';
  if (mod10 == 1) return 'one';
  if (mod10 >= 2 && mod10 <= 4) return 'few';
  return 'many';
}}

String _formFor(PluralForms f, int n) {{
  if (!LocaleService.appIsRussian) {{
    return n == 1 ? f.englishOne : f.englishOther;
  }}
  switch (_ruCategory(n)) {{
    case 'one': return f.one;
    case 'few': return f.few;
    default: return f.many;
  }}
}}

/// "5 тайтлов" / "5 titles" — the count *and* the correctly-agreeing
/// noun, for a family already in [pluralCatalog] (see that map's own
/// keys for what's available — `nTitles`, `nDays`, `nEvenings`, and so
/// on). For a one-off noun that doesn't warrant a permanent catalog
/// entry, [ruCount] below still works exactly as it always did, with
/// the forms spelled out at the call site.
String nCount(String catalogKey, int n) {{
  final forms = pluralCatalog[catalogKey];
  assert(forms != null, "no plural catalog entry for '$catalogKey' — "
      "check lib/l10n/app_en.arb for the key, or add one and regenerate");
  if (forms == null) return '$n';
  return '$n ${{_formFor(forms, n)}}';
}}

/// Just the agreeing noun, no number — "тайтлов" / "titles" — for spots
/// like `'$watched/$total ${{nOnly('nEpisodes', total)}}'` where the
/// count is already shown as a fraction.
String nOnly(String catalogKey, int n) {{
  final forms = pluralCatalog[catalogKey];
  assert(forms != null, "no plural catalog entry for '$catalogKey' — "
      "check lib/l10n/app_en.arb for the key, or add one and regenerate");
  if (forms == null) return '';
  return _formFor(forms, n);
}}
{"".join(compound_fn_lines)}
/// English/Russian noun for a media type on its own (a filter chip, a
/// tab label) — "movie" / "фильм". Not count-based (see [pluralCatalog]
/// for that); this is a closed, fixed set of six media types, so a
/// small lookup table is simpler than routing it through the general
/// translation map for six entries that never change.
const _mediaTypeSingularRu = {{
  'movie': 'фильм',
  'series': 'сериал',
  'anime': 'аниме',
  'game': 'игра',
  'book': 'книга',
  'manga': 'манга',
}};

String mediaTypeLabel(String mediaType) {{
  if (!LocaleService.appIsRussian) return mediaType;
  return _mediaTypeSingularRu[mediaType] ?? mediaType;
}}

/// Plural counterpart to [mediaTypeLabel] — e.g. a tab or filter chip
/// labelled "movies" / "series" / "games".
const _mediaTypePluralRu = {{
  'movie': 'фильмы',
  'series': 'сериалы',
  'anime': 'аниме',
  'game': 'игры',
  'book': 'книги',
  'manga': 'манга',
}};

String mediaTypeLabelPlural(String mediaType) {{
  if (!LocaleService.appIsRussian) return mediaType;
  return _mediaTypePluralRu[mediaType] ?? mediaType;
}}

/// Every screen in this app writes its own UI copy lowercase —
/// "choose a period", not "Choose a period" — no Title Case, no
/// capitalized sentence starts, on purpose (a lowercase interface reads
/// calmer/softer). Doing it here, once, at the one place all static UI
/// copy actually funnels through, means every string gets this
/// treatment automatically, including ones a future screen adds without
/// knowing this rule exists.
///
/// The whole string is lowercased, not just its first letter (used to
/// be first-letter-only, which left "united Kingdom" / "south Korea" /
/// "Settings → Import" half-lowered). Two deliberate exceptions:
///   * a word written in ALL CAPS (2+ letters) is an acronym and stays
///     as written — "TMDB", "CSV", "HD", "США";
///   * a string that's ALL CAPS on purpose — the boarding-pass/
///     ticket-styled log screens' "ADMIT ONE", "NOW BOARDING", "GATE",
///     "SEAT" and friends — is left completely alone.
final RegExp _letterRun = RegExp(r'[\p{{L}}\p{{M}}]+', unicode: true);

String _lowercaseUiText(String s) {{
  if (s.isEmpty) return s;
  if (s == s.toUpperCase() && s != s.toLowerCase()) return s;
  return s.replaceAllMapped(_letterRun, (m) {{
    final word = m[0]!;
    final isAcronym = word.length >= 2 && word == word.toUpperCase();
    return isAcronym ? word : word.toLowerCase();
  }});
}}

/// Kept for any call site not yet migrated to [nCount] — spells the
/// Russian forms out inline instead of naming a [pluralCatalog] entry.
/// Equivalent to `nCount`, just without needing a catalog key.
String ruCount(
  int n, {{
  required String one,
  required String few,
  required String many,
  required String englishOne,
  required String englishOther,
}}) {{
  if (!LocaleService.appIsRussian) {{
    return '$n ${{n == 1 ? englishOne : englishOther}}';
  }}
  return '$n ${{ruPluralForm(n, one: one, few: few, many: many, englishOne: englishOne, englishOther: englishOther)}}';
}}

/// Just the noun form for [ruCount]'s inline-forms sibling — see
/// [nOnly] for the [pluralCatalog]-backed equivalent.
String ruPluralForm(
  int n, {{
  required String one,
  required String few,
  required String many,
  required String englishOne,
  required String englishOther,
}}) {{
  if (!LocaleService.appIsRussian) {{
    return n == 1 ? englishOne : englishOther;
  }}
  switch (_ruCategory(n)) {{
    case 'one': return one;
    case 'few': return few;
    default: return many;
  }}
}}
'''

    OUT.write_text(template, encoding='utf-8')
    print(f"wrote {OUT} — {len(plain_keys)} plain strings, "
          f"{len(plural_keys)} plural families, {len(compound_keys)} compound message(s)")


if __name__ == '__main__':
    main()
