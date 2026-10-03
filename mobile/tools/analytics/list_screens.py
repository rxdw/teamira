#!/usr/bin/env python3
"""Writes the list of every screen in the Flutter app to
backend/app/analytics_screens.json.

Why: scripts/analytics_report.py can rank the screens people *opened*, but
"which screens does nobody use?" needs the list of screens that *exist* to
subtract from. Analytics only ever sees the ones that were opened, so the
list has to come from the source.

A "screen" here is any widget class whose name ends in `Screen` — the same
rule lib/analytics/screen_names.dart uses at runtime to name a screen, so
the two lists agree by construction. A leading underscore is dropped
(`_SessionsScreen` -> `SessionsScreen`), again matching the runtime.

    python3 tools/analytics/list_screens.py            # rewrite the JSON
    python3 tools/analytics/list_screens.py --check    # exit 1 if it's stale

Run it after adding, renaming or deleting a screen. `--check` is cheap
enough for CI or a pre-commit hook.

EXCLUDED below are `*Screen` classes that are not navigable screens — they
are slides or placeholders inside another screen — and would otherwise be
reported as "never opened" forever, which is noise that trains people to
ignore the report.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]            # mobile/
OUT = ROOT.parent / "backend" / "app" / "analytics_screens.json"

EXCLUDED = {
    "MessageScreen": "a slide inside WrappedScreen's PageView, not a route",
    "EnvelopeScreen": "a slide inside WrappedScreen's PageView, not a route",
    "SplashScreen": "boot placeholder shown by _AuthGate while the session loads; never a route",
}

_CLASS_RE = re.compile(r"^(?:abstract\s+)?class\s+(_?[A-Z][A-Za-z0-9]*Screen)\s+extends\s+\w+", re.MULTILINE)
# State<...> subclasses are named FooScreenState — they end in "State", so
# the regex above never matches them, and `extends` must be a Widget-ish
# base (Stateless/Stateful/Consumer...), which the next check enforces.
_WIDGET_BASES = re.compile(r"extends\s+(StatelessWidget|StatefulWidget|\w*Widget)\b")


def find_screens() -> list[str]:
    names: set[str] = set()
    for path in sorted((ROOT / "lib").rglob("*.dart")):
        if "l10n" in path.parts:
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        for m in _CLASS_RE.finditer(text):
            line_end = text.find("{", m.start())
            header = text[m.start(): line_end if line_end != -1 else m.end() + 80]
            if not _WIDGET_BASES.search(header):
                continue
            names.add(m.group(1).lstrip("_"))
    return sorted(names - set(EXCLUDED))


def render(screens: list[str]) -> str:
    payload = {
        "generated_by": "mobile/tools/analytics/list_screens.py — do not edit by hand",
        "excluded": EXCLUDED,
        "screens": screens,
    }
    return json.dumps(payload, ensure_ascii=False, indent=2) + "\n"


def main() -> int:
    screens = find_screens()
    rendered = render(screens)
    if "--check" in sys.argv:
        current = OUT.read_text(encoding="utf-8") if OUT.exists() else ""
        if current != rendered:
            print(f"{OUT} is out of date — run: python3 tools/analytics/list_screens.py", file=sys.stderr)
            return 1
        print(f"ok: {len(screens)} screens")
        return 0
    OUT.write_text(rendered, encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT.parent)}: {len(screens)} screens")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
