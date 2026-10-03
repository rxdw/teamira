#!/usr/bin/env python3
"""Adds a new build of the app to a SideStore / AltStore "source" file.

A source is a JSON file on your own web server that tells SideStore which
apps you offer and where their .ipa files are. Once a person has added your
source URL to SideStore once, every new build you list here shows up in
their "My Apps" tab as an update — no cable, no re-sending files.

    python3 tools/ios/make_altstore_source.py Seenly.ipa \\
        --ipa-url https://ваш-домен.ru/ios/Seenly-0.1.0-3.ipa \\
        --source site/ios/source.json \\
        --notes "Подключили боевой сервер"

What it does, and why each part exists (all of these are the ways a
hand-edited source goes wrong):

  * Reads version, build number, bundle id, minimum iOS, and the camera/
    photo-style permission texts FROM THE IPA ITSELF, so the source can never
    disagree with the file it points at. AltStore's own documentation says
    the source must list every entitlement and privacy permission and that
    they are checked against the downloaded .ipa — a mismatch and the app
    is refused. SideStore is a fork of AltStore and reads the same format;
    filling these in from the file is the safe choice.
  * Puts the new build FIRST in the app's `versions` list. Updates are
    detected by comparing the *first* entry with what's installed — dates
    are not used — so order matters, and every entry needs a version or
    build number different from the one before it.
  * Refuses a build number that's already listed (`--replace` overrides),
    which is what happens when you forget to bump `--build-number`.
  * Records the true file size in bytes.

First run creates the source; later runs add versions to it. Host the JSON
and the .ipa on your site (the Caddy static folder from phase 2.12 of the
launch plan works), then in SideStore: Sources → "+" → paste the URL of the
JSON file.

Only the standard library is used.
"""

from __future__ import annotations

import argparse
import json
import plistlib
import re
import sys
import zipfile
from datetime import datetime, timezone
from pathlib import Path


class SourceError(Exception):
    """A problem the user can fix; printed without a traceback."""


def read_ipa(path: Path) -> dict:
    """Facts from Payload/<Name>.app/Info.plist inside the .ipa."""
    if not path.is_file():
        raise SourceError(f"нет такого файла: {path}")
    try:
        zf = zipfile.ZipFile(path)
    except zipfile.BadZipFile:
        raise SourceError(f"{path} — не .ipa (это не zip-архив)")
    with zf:
        plist_names = [
            n for n in zf.namelist()
            if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", n)
        ]
        if len(plist_names) != 1:
            raise SourceError(
                "в архиве должна быть ровно одна папка Payload/<имя>.app с Info.plist "
                f"(найдено: {len(plist_names)}). Нужен именно .ipa, а не zip из «Runner.app»."
            )
        info = plistlib.loads(zf.read(plist_names[0]))
        app_dir = plist_names[0].rsplit("/", 1)[0]

        entitlements: list[str] = []
        xcent = f"{app_dir}/archived-expanded-entitlements.xcent"
        if xcent in zf.namelist():
            ent = plistlib.loads(zf.read(xcent))
            # These two are implied for every app and must not be listed.
            entitlements = sorted(k for k in ent if k not in ("application-identifier", "com.apple.developer.team-identifier"))

    for key in ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion"):
        if not info.get(key):
            raise SourceError(f"в Info.plist внутри .ipa нет ключа {key}")
    return {
        "bundle_id": str(info["CFBundleIdentifier"]),
        "version": str(info["CFBundleShortVersionString"]),
        "build": str(info["CFBundleVersion"]),
        "name": str(info.get("CFBundleDisplayName") or info.get("CFBundleName") or ""),
        "min_os": str(info["MinimumOSVersion"]) if info.get("MinimumOSVersion") else None,
        "privacy": {k: str(v) for k, v in sorted(info.items()) if k.startswith("NS") and k.endswith("UsageDescription")},
        "entitlements": entitlements,
        "size": path.stat().st_size,
    }


def update_source(source: dict, facts: dict, *, ipa_url: str, notes: str, when: datetime, replace: bool,
                  source_name: str | None, developer: str | None, app_name: str | None,
                  icon_url: str | None, description: str | None, extra_entitlements: list[str]) -> dict:
    """Returns `source` with this build added as the newest version."""
    source.setdefault("name", source_name or "Seenly")
    source.setdefault("identifier", f"{facts['bundle_id']}.source")
    source.setdefault("apps", [])
    source.setdefault("news", [])
    if source_name:
        source["name"] = source_name

    app = next((a for a in source["apps"] if a.get("bundleIdentifier") == facts["bundle_id"]), None)
    if app is None:
        app = {"bundleIdentifier": facts["bundle_id"], "versions": []}
        source["apps"].insert(0, app)
    app["name"] = app_name or app.get("name") or facts["name"] or "Seenly"
    app["developerName"] = developer or app.get("developerName") or app["name"]
    app["localizedDescription"] = description or app.get("localizedDescription") or f"{app['name']} — личный дневник фильмов и сериалов."
    if icon_url:
        app["iconURL"] = icon_url
    app.setdefault("iconURL", "")

    versions = app.setdefault("versions", [])
    duplicate = next((v for v in versions if v.get("version") == facts["version"] and v.get("buildVersion") == facts["build"]), None)
    if duplicate is not None:
        if not replace:
            raise SourceError(
                f"версия {facts['version']} ({facts['build']}) уже есть в источнике. Обычно это значит, что вы забыли "
                "поднять --build-number при сборке: без нового номера SideStore не увидит обновление. "
                "Если это осознанная замена файла, добавьте --replace."
            )
        versions.remove(duplicate)

    entry = {
        "version": facts["version"],
        "buildVersion": facts["build"],
        "date": when.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "localizedDescription": notes or f"Версия {facts['version']} ({facts['build']})",
        "downloadURL": ipa_url,
        "size": facts["size"],
    }
    if facts["min_os"]:
        entry["minOSVersion"] = facts["min_os"]
    versions.insert(0, entry)  # newest FIRST — updates are detected from index 0

    app["appPermissions"] = {
        "entitlements": sorted(set(facts["entitlements"]) | set(extra_entitlements)),
        "privacy": facts["privacy"],
    }
    return source


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("ipa", type=Path, help="собранный .ipa")
    p.add_argument("--ipa-url", required=True, help="публичная ссылка, по которой этот .ipa будет скачиваться")
    p.add_argument("--source", type=Path, required=True, help="путь к source.json (создаётся, если нет)")
    p.add_argument("--notes", default="", help="что нового в этой версии (видно в SideStore)")
    p.add_argument("--replace", action="store_true", help="заменить уже существующую запись с тем же номером сборки")
    p.add_argument("--source-name", help="название источника (по умолчанию Seenly)")
    p.add_argument("--app-name", help="название приложения в источнике")
    p.add_argument("--developer", help="имя разработчика в источнике")
    p.add_argument("--description", help="описание приложения")
    p.add_argument("--icon-url", help="ссылка на иконку (квадратный PNG)")
    p.add_argument("--entitlement", action="append", default=[], help="добавить entitlement вручную (можно несколько раз)")
    args = p.parse_args(argv)

    try:
        if not re.match(r"^https?://", args.ipa_url):
            raise SourceError("--ipa-url должен начинаться с https:// (SideStore скачивает файл по этой ссылке)")
        facts = read_ipa(args.ipa)
        source: dict = {}
        if args.source.exists():
            try:
                source = json.loads(args.source.read_text(encoding="utf-8"))
            except json.JSONDecodeError as e:
                raise SourceError(f"{args.source} — не JSON: {e}")
        source = update_source(
            source, facts, ipa_url=args.ipa_url, notes=args.notes, when=datetime.now(timezone.utc), replace=args.replace,
            source_name=args.source_name, developer=args.developer, app_name=args.app_name, icon_url=args.icon_url,
            description=args.description, extra_entitlements=args.entitlement,
        )
    except SourceError as e:
        print(f"Ошибка: {e}", file=sys.stderr)
        return 1

    args.source.parent.mkdir(parents=True, exist_ok=True)
    args.source.write_text(json.dumps(source, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    app = next(a for a in source["apps"] if a["bundleIdentifier"] == facts["bundle_id"])
    print(f"Готово: {facts['bundle_id']} {facts['version']} ({facts['build']}), {facts['size']} байт")
    print(f"  в источнике теперь версий: {len(app['versions'])}, первая (её видит SideStore): {app['versions'][0]['version']} ({app['versions'][0]['buildVersion']})")
    print(f"  разрешения из .ipa: entitlements={app['appPermissions']['entitlements'] or 'нет'}, privacy={list(app['appPermissions']['privacy']) or 'нет'}")
    print(f"Осталось: выложить {args.source} и сам .ipa по адресу {args.ipa_url}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
