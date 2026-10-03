#!/usr/bin/env python3
"""Plain-text usage report straight from the analytics_events table.

The quickest way to answer "which screens does anyone actually use?" —
no dashboard to set up, one command:

    docker compose exec api python -m scripts.analytics_report
    docker compose exec api python -m scripts.analytics_report --days 30
    docker compose exec api python -m scripts.analytics_report --build release

    --days N     the window to report on (default 7)
    --build B    all (default) | release | debug | profile.
                 While you're developing, your own debug builds are the only
                 traffic there is, so the default counts everything and the
                 header shows how much of it is which. Once real users exist,
                 use --build release.
    --top N      rows in the ranked tables (default 25)

Sections: who is active, the screens ranked (with the ones nobody opened
at all called out), sheets, key actions, the onboarding funnel, an
activation funnel, day-1/day-7 retention, and the version/platform mix.

The list of screens that *exist* comes from app/analytics_screens.json,
generated from the Flutter sources by mobile/tools/analytics/list_screens.py
— that's what lets this report say "never opened" rather than only ranking
what was opened. Re-run that script after adding or removing a screen.

Devices, not people: everything is counted in `anon_id` (one per install).
Someone with two phones counts twice; someone who reinstalls counts twice.
That's the standard trade-off for mobile analytics and it's stated in the
output so nobody reads "active devices" as "users".
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from sqlalchemy import text  # noqa: E402
from sqlalchemy.orm import Session  # noqa: E402

_REGISTRY_PATH = os.path.join(os.path.dirname(__file__), "..", "app", "analytics_screens.json")

# Events that describe the app being alive rather than something a person
# chose to do — kept out of the "key actions" table so it isn't drowned.
_HOUSEKEEPING_EVENTS = ("screen_view", "app_open", "app_background")

# The same names, in the same order, as `_stepNames` in
# mobile/lib/screens/onboarding/onboarding_screen.dart — the app reports the
# step as a number and this list is what turns it back into a name. (There is a
# mobile test, test/onboarding_funnel_test.dart, that fails when the two drift
# apart; they had: this list was missing "people_like_you".)
ONBOARDING_STEPS = [
    "welcome", "features_tour", "partner", "language", "skin", "ritual",
    "interests", "favorites", "people_like_you", "motivation", "plan_reveal", "import",
]


# --------------------------------------------------------------------- utils

def _load_registry() -> list[str]:
    try:
        with open(_REGISTRY_PATH, encoding="utf-8") as fh:
            return list(json.load(fh).get("screens", []))
    except (OSError, ValueError):
        return []


def _table(headers: list[str], rows: list[list], aligns: str | None = None) -> str:
    """Fixed-width text table. `aligns`: one char per column, l or r."""
    if not rows:
        return "  (нет данных)"
    aligns = aligns or "l" * len(headers)
    cells = [[str(c) for c in r] for r in rows]
    widths = [max(len(h), *(len(r[i]) for r in cells)) for i, h in enumerate(headers)]

    def fmt(row: list[str]) -> str:
        parts = [c.ljust(w) if a == "l" else c.rjust(w) for c, w, a in zip(row, widths, aligns)]
        return "  " + "  ".join(parts).rstrip()

    lines = [fmt(headers), "  " + "  ".join("-" * w for w in widths)]
    lines += [fmt(r) for r in cells]
    return "\n".join(lines)


def _pct(part: int, whole: int) -> str:
    return f"{round(100 * part / whole)}%" if whole else "-"


def _dur(seconds) -> str:
    if seconds is None:
        return "-"
    s = int(round(float(seconds)))
    return f"{s // 60}:{s % 60:02d}"


def _section(title: str) -> str:
    return f"\n{title}\n{'=' * len(title)}"


# -------------------------------------------------------------------- report

def build_report(db: Session, days: int = 7, build: str = "all", top: int = 25, now: datetime | None = None) -> str:
    now = now or datetime.now(timezone.utc)
    since = now - timedelta(days=days)
    today = now.date()
    build_sql = "" if build == "all" else " AND build = :build"
    p = {"since": since, "build": build, "today": today, "top": top}
    out: list[str] = []

    def q(sql: str, **extra):
        return db.execute(text(sql), {**p, **extra}).all()

    # --- header -------------------------------------------------------------
    by_build = q("SELECT COALESCE(build, '?') AS b, COUNT(*) AS n FROM analytics_events WHERE ts >= :since GROUP BY 1 ORDER BY 2 DESC")
    total_events = sum(r.n for r in by_build)
    out.append(f"Seenly — отчёт по использованию за последние {days} дн. (до {now:%Y-%m-%d %H:%M} UTC)")
    out.append(f"Фильтр сборки: {build}.  Событий в базе за период, все сборки: {total_events}"
               + (f"  ({', '.join(f'{r.b}: {r.n}' for r in by_build)})" if by_build else ""))
    if total_events == 0:
        out.append("\nСобытий нет. Проверьте: приложение запущено с адресом этого сервера, "
                   "в Настройках включена «анонимная статистика», прошло ≥15 секунд или приложение свернули "
                   "(события уходят пачками).")
        return "\n".join(out)
    out.append("Считаем устройства (одна установка = одно устройство), а не людей.")

    # --- activity -----------------------------------------------------------
    act = q(f"""
        SELECT
          COUNT(DISTINCT anon_id) FILTER (WHERE (ts AT TIME ZONE 'UTC')::date = :today)              AS dau,
          COUNT(DISTINCT anon_id) FILTER (WHERE ts >= :now - interval '7 days')                       AS wau,
          COUNT(DISTINCT anon_id) FILTER (WHERE ts >= :now - interval '30 days')                      AS mau,
          COUNT(DISTINCT anon_id) FILTER (WHERE ts >= :since)                                         AS active,
          COUNT(DISTINCT anon_id) FILTER (WHERE ts >= :since AND user_id IS NOT NULL)                 AS signed_in,
          COUNT(DISTINCT session_id) FILTER (WHERE ts >= :since)                                      AS sessions
        FROM analytics_events
        WHERE ts >= :now - interval '30 days' {build_sql}
    """, now=now)[0]
    new_devices = q(f"""
        SELECT COUNT(*) AS n FROM (
          SELECT anon_id FROM analytics_events WHERE TRUE {build_sql}
          GROUP BY anon_id HAVING MIN(ts) >= :since
        ) t
    """)[0].n
    sess_len = q(f"""
        SELECT AVG(EXTRACT(EPOCH FROM (last_ts - first_ts))) AS avg_s FROM (
          SELECT session_id, MIN(ts) AS first_ts, MAX(ts) AS last_ts
          FROM analytics_events WHERE ts >= :since {build_sql} GROUP BY session_id
          HAVING COUNT(*) > 1
        ) t
    """)[0].avg_s
    active = act.active or 0
    out.append(_section("Кто пользуется"))
    out.append(_table(
        ["сегодня", "7 дней", "30 дней", f"за {days} дн.", "новых", "вошли в аккаунт", "сессий", "средняя сессия"],
        [[act.dau or 0, act.wau or 0, act.mau or 0, active, new_devices,
          f"{act.signed_in or 0} ({_pct(act.signed_in or 0, active)})", act.sessions or 0, _dur(sess_len)]],
        "rrrrrrrr",
    ))
    out.append("  (устройств: сегодня / за 7 / за 30 / за период; «новых» — впервые замеченных в период)")

    # --- screens & sheets ----------------------------------------------------
    screen_sql = f"""
        SELECT screen,
               COUNT(*) FILTER (WHERE nav <> 'back')        AS views,
               COUNT(DISTINCT anon_id)                      AS devices,
               AVG(secs) FILTER (WHERE secs IS NOT NULL)    AS avg_s
        FROM (
          SELECT screen, anon_id, COALESCE(props->>'nav', 'push') AS nav, COALESCE(props->>'kind', 'screen') AS kind, name,
                 LEAST(EXTRACT(EPOCH FROM (LEAD(ts) OVER (PARTITION BY session_id ORDER BY ts, id) - ts)), 600) AS secs
          FROM analytics_events
          WHERE name IN ('screen_view', 'app_background') AND ts >= :since {build_sql}
        ) t
        WHERE name = 'screen_view' AND kind = :kind
        GROUP BY screen
        HAVING COUNT(*) FILTER (WHERE nav <> 'back') > 0
        ORDER BY views DESC, devices DESC
    """
    screens = q(screen_sql, kind="screen")
    out.append(_section("Экраны: что открывают"))
    out.append(_table(
        ["#", "экран", "открытий", "устройств", "% активных", "ср. время"],
        [[i + 1, r.screen, r.views, r.devices, _pct(r.devices, active), _dur(r.avg_s)] for i, r in enumerate(screens[:top])],
        "rlrrrr",
    ))
    if len(screens) > top:
        out.append(f"  … и ещё {len(screens) - top} (--top {len(screens)} покажет все)")

    registry = _load_registry()
    seen = {r.screen for r in screens}
    if registry:
        never = sorted(set(registry) - seen)
        out.append(_section(f"Экраны, которые не открыли НИ РАЗУ за {days} дн. ({len(never)} из {len(registry)})"))
        out.append("\n".join(f"  {n}" for n in never) if never else "  (таких нет)")
        unknown = sorted(n for n in seen if n not in set(registry) and not n.startswith("("))
        if unknown:
            out.append(f"\n  Есть в данных, но нет в списке экранов ({len(unknown)}): {', '.join(unknown[:15])}"
                       f"{' …' if len(unknown) > 15 else ''}\n"
                       "  (новый/переименованный экран — перегенерируйте список: mobile/tools/analytics/list_screens.py)")
    else:
        out.append("\n  Список существующих экранов не найден (app/analytics_screens.json), поэтому "
                   "«не открыли ни разу» не посчитать. См. mobile/tools/analytics/list_screens.py.")
    unnamed = next((r for r in screens if r.screen == "(unnamed)"), None)
    if unnamed:
        out.append(f"\n  ⚠ {unnamed.views} открытий без имени экрана «(unnamed)» — маршрут, в котором не нашёлся виджет "
                   "*Screen. Они не потеряны, но в рейтинг по именам не попали.")

    sheets = q(screen_sql, kind="sheet")
    out.append(_section("Шторки (bottom sheet)"))
    out.append(_table(
        ["шторка", "открытий", "устройств", "% активных"],
        [[r.screen, r.views, r.devices, _pct(r.devices, active)] for r in sheets[:top]],
        "lrrr",
    ))

    # --- key actions ---------------------------------------------------------
    actions = q(f"""
        SELECT name, COUNT(*) AS n, COUNT(DISTINCT anon_id) AS devices
        FROM analytics_events
        WHERE ts >= :since AND name NOT IN ('screen_view', 'app_open', 'app_background') {build_sql}
        GROUP BY name ORDER BY n DESC, name LIMIT :top
    """)
    out.append(_section("Действия"))
    out.append(_table(["событие", "раз", "устройств", "% активных"],
                      [[r.name, r.n, r.devices, _pct(r.devices, active)] for r in actions], "lrrr"))
    search = q(f"""
        SELECT COUNT(*) AS n, COUNT(*) FILTER (WHERE (props->>'results') = '0') AS empty
        FROM analytics_events WHERE name = 'search_performed' AND ts >= :since {build_sql}
    """)[0]
    if search.n:
        out.append(f"  Поиск: {search.n} запросов, из них без результатов — {search.empty} ({_pct(search.empty, search.n)}).")

    # --- funnels ---------------------------------------------------------------
    steps = q(f"""
        SELECT (props->>'step')::int AS step, COUNT(DISTINCT anon_id) AS devices
        FROM analytics_events
        WHERE name = 'onboarding_step' AND ts >= :since AND props->>'step' ~ '^[0-9]+$' {build_sql}
        GROUP BY 1 ORDER BY 1
    """)
    reached = {r.step: r.devices for r in steps}
    started = q(f"""
        SELECT COUNT(DISTINCT anon_id) AS n FROM analytics_events
        WHERE ts >= :since AND name = 'screen_view' AND screen = 'OnboardingScreen' {build_sql}
    """)[0].n
    done = q(f"""
        SELECT COUNT(DISTINCT anon_id) AS n FROM analytics_events
        WHERE ts >= :since AND name = 'onboarding_completed' {build_sql}
    """)[0].n
    out.append(_section("Онбординг: где отваливаются"))
    if started or reached:
        rows = [["0", ONBOARDING_STEPS[0], started, "100%"]]
        for i, label in enumerate(ONBOARDING_STEPS[1:], start=1):
            n = reached.get(i, 0)
            rows.append([str(i), label, n, _pct(n, started)])
        rows.append(["✓", "завершили", done, _pct(done, started)])
        out.append(_table(["шаг", "название", "устройств", "от начавших"], rows, "llrr"))
    else:
        out.append("  (никто не проходил онбординг в этом периоде)")

    fun = q(f"""
        SELECT
          COUNT(DISTINCT anon_id)                                             AS opened,
          COUNT(DISTINCT anon_id) FILTER (WHERE name = 'signup')              AS signup,
          COUNT(DISTINCT anon_id) FILTER (WHERE name = 'search_performed')    AS searched,
          COUNT(DISTINCT anon_id) FILTER (WHERE name = 'title_detail_loaded') AS opened_title,
          COUNT(DISTINCT anon_id) FILTER (WHERE name = 'diary_entry_logged')  AS logged
        FROM analytics_events WHERE ts >= :since {build_sql}
    """)[0]
    out.append(_section("Путь до первой записи в дневник (устройства, делавшие это в периоде)"))
    out.append(_table(["шаг", "устройств", "от открывших"], [
        ["открыли приложение", fun.opened, "100%"],
        ["зарегистрировались", fun.signup, _pct(fun.signup, fun.opened)],
        ["искали тайтл", fun.searched, _pct(fun.searched, fun.opened)],
        ["открыли страницу тайтла", fun.opened_title, _pct(fun.opened_title, fun.opened)],
        ["записали вечер в дневник", fun.logged, _pct(fun.logged, fun.opened)],
    ], "lrr"))
    out.append("  (это доли «делали хоть раз», а не строгая цепочка по порядку)")

    # --- retention -------------------------------------------------------------
    ret = q(f"""
        WITH first AS (
          SELECT anon_id, MIN((ts AT TIME ZONE 'UTC')::date) AS d0
          FROM analytics_events WHERE TRUE {build_sql} GROUP BY anon_id
        ), act AS (
          SELECT DISTINCT anon_id, (ts AT TIME ZONE 'UTC')::date AS d FROM analytics_events WHERE TRUE {build_sql}
        )
        SELECT
          COUNT(*) FILTER (WHERE f.d0 <= :today - 1) AS elig1,
          COUNT(*) FILTER (WHERE f.d0 <= :today - 1 AND EXISTS (SELECT 1 FROM act a WHERE a.anon_id = f.anon_id AND a.d = f.d0 + 1)) AS ret1,
          COUNT(*) FILTER (WHERE f.d0 <= :today - 7) AS elig7,
          COUNT(*) FILTER (WHERE f.d0 <= :today - 7 AND EXISTS (SELECT 1 FROM act a WHERE a.anon_id = f.anon_id AND a.d = f.d0 + 7)) AS ret7
        FROM first f WHERE f.d0 >= :today - 30
    """)[0]
    out.append(_section("Возвращаемость (новые устройства за последние 30 дней)"))
    out.append(_table(["", "вернулись", "из", "доля"], [
        ["на 1-й день", ret.ret1, ret.elig1, _pct(ret.ret1, ret.elig1)],
        ["на 7-й день", ret.ret7, ret.elig7, _pct(ret.ret7, ret.elig7)],
    ], "lrrr"))
    if ret.elig1 < 30:
        out.append("  ⚠ меньше 30 устройств в выборке — доли шумные, смотрите на них как на ориентир, не как на факт.")

    # --- mix -------------------------------------------------------------------
    mix = q(f"""
        SELECT COALESCE(platform, '?') AS platform, COALESCE(app_version, '?') AS version,
               COALESCE(locale, '?') AS locale, COUNT(DISTINCT anon_id) AS devices
        FROM analytics_events WHERE ts >= :since {build_sql}
        GROUP BY 1, 2, 3 ORDER BY devices DESC LIMIT 15
    """)
    out.append(_section("Платформы, версии, язык интерфейса"))
    out.append(_table(["платформа", "версия", "язык", "устройств"],
                      [[r.platform, r.version, r.locale, r.devices] for r in mix], "lllr"))
    return "\n".join(out) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--days", type=int, default=7)
    parser.add_argument("--build", choices=["all", "release", "debug", "profile"], default="all")
    parser.add_argument("--top", type=int, default=25)
    args = parser.parse_args()

    from app.database import SessionLocal

    db = SessionLocal()
    try:
        sys.stdout.write(build_report(db, days=args.days, build=args.build, top=args.top))
    finally:
        db.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
