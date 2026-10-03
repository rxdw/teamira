# Ask tanè: game results that are actually good

## The bug

"co-op game for two" returned *Sonic 1 Co-op* (a fan mod), *Challenge Me:
Math Workout* and *Interwebs Troll Simulator* (no cover).

Root causes, all in the games half of `POST /ai/ask`:

1. **Name search on a description.** The ask has no genre or reference, so
   `routers/ai.py` sent it to IGDB `search`, which only matches game
   *names*. Result: whatever obscure entry had "co-op" in its title.
2. **No quality gate.** Mods, re-listed editions, DLC, coverless and
   almost-unrated entries all qualified.
3. **Play mode was ignored.** `game_modes` was already fetched from IGDB
   but never looked at, and "co-op / for two / split screen" wasn't parsed.
4. **Pool-relative semantics.** Min-max normalization over a pile of junk
   crowns the least-unrelated item (the "60" badges in the screenshot).
5. Smaller: game genre matching used genre *names* only, but IGDB keeps
   sci-fi / horror / fantasy / comedy under **themes**, so those asks never
   matched; genre score divided by keyword count instead of concept count.

## What changed

**Backend**

- `app/game_intent.py` (new, pure): parses how a game should be played —
  co-op, split-screen, multiplayer, party, head-counts ("for two",
  "вдвоём", "with a friend"), EN + RU. Strong words ("co-op") imply a
  games ask by themselves; soft ones ("for two") only count when the ask
  already says it wants a game, so "movie for two" is untouched. Traps
  handled: "for 2 hours", "party-based RPG".
- `app/adapters/igdb.py`: new `IgdbAdapter.discover()` — server-side
  filters (game mode, genre ids, theme ids, release window) plus a
  quality gate (cover, rating count, rating; DLC/edition/mod exclusion via
  `parent_game`/`version_parent`), most-rated + best-rated lists per tier,
  tiers relax only when thin. Falls back without the structural clauses on
  an HTTP 400; stops stepping down tiers when IGDB is failing rather than
  empty. `search()` and everything else are unchanged.
- `app/routers/ai.py`:
  - play mode is a **hard requirement** (`GameIntent.evaluate`); MMOs and
    battle royales are dropped for small-group asks;
  - genres/themes/eras go to IGDB as filters (`_GAME_FILTERS`); scoring
    matches genre *and* theme names, per concept;
  - thin results relax the era, then genre, never the play mode; padding
    that matches no requested genre is penalized;
  - mood-only asks use a cached, quality-gated broad game pool cut by an
    absolute semantic floor (never the old ungated "top rated" list);
  - leftover words become a title lookup only if they could be a title and
    the hit shares its words;
  - quality (rating count + score) is a small tiebreaker; at most two
    games per series in the shortlist;
  - discovery is cached by *filters* (6h; broad pool 24h); an empty IGDB
    answer is never cached;
  - game embeddings now include themes + play modes (versioned cache
    source `igdb:v2`, old vectors are simply not reused);
  - "что посмотреть" / "watch" rules out games and "поиграть" / "play"
    means games when no kind word is present; a film that merely shares a
    name with the "like X" reference no longer drags movies into a games
    ask; games-only asks no longer pay for the ~85-call TMDB pool;
  - fallback game lookup is quality-gated, respects kinds and play mode.

**Mobile**

- `ask_teamira_results_screen.dart`: the new reasoning fragment
  (`modes: co-op, split screen`) renders as «кооператив · сплит-скрин».

## Tests

`tests/test_game_intent.py`, `tests/test_igdb_discover.py`,
`tests/test_ai_games.py` (all pure, like `test_ai_time_budget.py`).

## Verify against real IGDB before shipping

This was developed without network access; the logic was exercised
against a faked IGDB with the real `ask_ai`. Two things only a real call
can confirm:

- the query text is accepted by IGDB as written (`parent_game = null`,
  `version_parent = null`, `(genres = (…) | themes = (…))`); if not, the
  adapter retries without the structural clauses and logs a warning
  ("IGDB rejected the discover query");
- the theme ids in `_GAME_FILTERS` (18 sci-fi, 17 fantasy, 19 horror,
  21 survival, 27 comedy, 23 stealth, 39 warfare, 35 kids, 43 mystery,
  44 romance, 1 action).

Quick manual check: ask "co-op game for two", "horror co-op game",
"кооперативная игра на двоих", "cozy farming game", "sci-fi game 90s",
"что посмотреть вдвоём" (must still be films).

## Not done (possible next steps)

- "games like X" still resolves the reference through TMDB (no games); a
  proper version would use IGDB `similar_games`.
- "for two" could prefer games whose co-op max is exactly 2 via IGDB
  `multiplayer_modes` (sparse data; not requested here).
- Movie/series text-search fallbacks have the same descriptive-query
  weakness in principle; untouched.
