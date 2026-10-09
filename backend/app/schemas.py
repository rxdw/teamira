from datetime import date, datetime
from typing import Optional, List, Literal
from pydantic import BaseModel, EmailStr, Field, field_validator, field_serializer, SerializationInfo

from app.image_urls import (
    resolve_image_url,
    TMDB_LOGO_BASE,
    TMDB_PROFILE_BASE,
    TMDB_POSTER_BASE,
    TMDB_BACKDROP_BASE,
)


class ImageFieldsModel(BaseModel):
    """Mixin for any response schema carrying a TMDB image reference —
    see app/image_urls.py for why this has to happen at serialization
    time rather than whenever the field was first set. Every serializer
    below is guarded with check_fields=False so a subclass only needs to
    actually declare the fields it has; the rest are silent no-ops.
    Covers every field name any schema in this file uses for an image.

    Every serializer below checks `info.context.get("raw")` and, when
    set, returns the value untouched instead of resolving it. This is
    what app/cache.py's `_dump_json` passes when writing a model into one
    of the forever/dynamic caches (CachedTitleDetail, CachedFeedSnapshot,
    ...) — without it, `model_dump_json()` (called from *both* a real API
    response *and* cache.py's own cache-write path) would bake whatever
    PUBLIC_API_BASE_URL happens to be configured *right now* into the
    stored JSON forever, defeating the entire point of resolving lazily
    at response time (see image_urls.py's module docstring). A row
    cached under an old/blank PUBLIC_API_BASE_URL would then keep serving
    an unproxied, direct image.tmdb.org link indefinitely — even after
    the setting is fixed — since resolve_image_url() treats any string
    already starting with http(s):// as an already-resolved foreign URL
    and passes it through unchanged. Caching the untouched bare path
    instead means every read resolves against the *current* setting."""

    @field_serializer("poster_url", "poster_url_ru", "favorite_poster", check_fields=False)
    def _ser_poster(self, v: Optional[str], info: SerializationInfo) -> Optional[str]:
        if info.context and info.context.get("raw"):
            return v
        return resolve_image_url(v, TMDB_POSTER_BASE)

    @field_serializer("backdrop_url", check_fields=False)
    def _ser_backdrop(self, v: Optional[str], info: SerializationInfo) -> Optional[str]:
        if info.context and info.context.get("raw"):
            return v
        return resolve_image_url(v, TMDB_BACKDROP_BASE)

    @field_serializer("photo_url", check_fields=False)
    def _ser_photo(self, v: Optional[str], info: SerializationInfo) -> Optional[str]:
        if info.context and info.context.get("raw"):
            return v
        return resolve_image_url(v, TMDB_PROFILE_BASE)

    @field_serializer("logo_url", check_fields=False)
    def _ser_logo(self, v: Optional[str], info: SerializationInfo) -> Optional[str]:
        if info.context and info.context.get("raw"):
            return v
        return resolve_image_url(v, TMDB_LOGO_BASE)

    @field_serializer("poster_urls", check_fields=False)
    def _ser_poster_list(self, v: Optional[List[str]], info: SerializationInfo) -> Optional[List[str]]:
        if not v:
            return v
        if info.context and info.context.get("raw"):
            return v
        return [resolve_image_url(u, TMDB_POSTER_BASE) for u in v]


# ---------------------------------------------------------------------------
# The shared media model. TMDB is the movie/series/anime catalog (games have
# their own IGDB-backed adapter, books/manga their own Open Library one) —
# every movie/series/anime field below always has the same shape. Anime is
# detected off TMDB's own data (Animation genre + Japanese origin — see
# app/adapters/tmdb.py's _is_anime), then gets its Russian text overlaid
# from Shikimori instead of TMDB's own (frequently thin/absent) Russian
# translation — see app/adapters/shikimori.py's module docstring.
# Missing localisation is simply null; the client falls back to the other
# language rather than showing an empty string.
# ---------------------------------------------------------------------------

class ExternalIds(BaseModel):
    tmdb: Optional[str] = None
    imdb: Optional[str] = None


class LocalizedText(BaseModel):
    ru: Optional[str] = None
    en: Optional[str] = None


class CastMember(ImageFieldsModel):
    # TMDB's own person id — None only for a cast/crew row built before
    # this field existed and never re-resolved (a forever-cached row from
    # before this change); every fresh fetch always has it. Powers a
    # tappable cast tile / "directed by" name -> GET /media/person.
    person_id: Optional[str] = None
    # The person's own name — TMDB does not localize this per `language`
    # (unlike `character` below), so it's the same string regardless of
    # which language the request was made in. Left as a single string on
    # purpose, not LocalizedText.
    name: str
    # The role they played — TMDB DOES translate this per `language`
    # ("Tony Stark" vs "Тони Старк"), so unlike `name` above this has to
    # be fetched in both languages and localized the same way title/
    # description are (see app/adapters/tmdb.py::full_detail).
    character: Optional[LocalizedText] = None
    photo_url: Optional[str] = None


# ---------------------------------------------------------------------------
# "Title extras" — the richer, per-type layer of the title screen for
# games, books, manga and anime (screenshots, authors, characters, languages,
# where to play/read/buy, related works ...). Everything lives in ONE nested
# object on MediaItem (`extras`) instead of ~30 new top-level fields: the
# card shape the rest of the app already relies on stays untouched, and a
# client that doesn't know about extras simply ignores the key. Every field
# is optional/empty by default — "unknown", never a fabricated value — and a
# whole `extras` is None for titles no source had anything extra for.
# Images here are full URLs from the source's own CDN (same as IGDB covers
# and Shikimori posters already are), so they pass through untouched.
# ---------------------------------------------------------------------------

class TitleTag(BaseModel):
    """A descriptive tag. `rank` is the community's 0-100 agreement with the
    tag (AniList); None for tags without a weight (IGDB themes)."""
    name: str
    rank: Optional[int] = None


class GameLanguage(BaseModel):
    """One language a game supports and in which ways. Which flags are known
    depends on the source (IGDB knows all three; Steam only 'audio')."""
    name: str
    interface: bool = False
    audio: bool = False
    subtitles: bool = False


class TimeToBeat(BaseModel):
    """Hours to finish a game (IGDB game_time_to_beats), each optional."""
    hastily: Optional[float] = None     # main story, rushed
    normally: Optional[float] = None    # main story + some extras
    completely: Optional[float] = None  # 100%
    votes: Optional[int] = None


class TitleLink(BaseModel):
    """Where to play / read / buy / learn more. `kind` picks the icon and
    grouping on the client: official | steam | gog | epic | playstation |
    xbox | nintendo | itch | store | read | preview | buy | wiki | other."""
    kind: str
    label: str
    url: str


class TitleCreator(BaseModel):
    """A person behind the work — author/artist of a book or manga, studio
    staff of an anime. Not a TMDB person, so never tappable to a person
    screen (CastMember.person_id is TMDB-only)."""
    name: str
    name_ru: Optional[str] = None     # Shikimori keeps Cyrillic names; the client picks per language
    role: Optional[str] = None
    photo_url: Optional[str] = None
    bio: Optional[str] = None
    born: Optional[str] = None


class TitleCharacter(BaseModel):
    name: str
    name_ru: Optional[str] = None
    role: Optional[str] = None        # "Main" | "Supporting" (localised client-side)
    photo_url: Optional[str] = None


class RelatedTitle(BaseModel):
    """Another work connected to this one: a sequel, an adaptation, a DLC,
    a game from the same series. When `id`+`source` are set the client can
    open its card directly; otherwise it searches by `title` + `media_type`
    (e.g. a manga's anime adaptation, whose TMDB id isn't known here)."""
    relation: str                     # "Adaptation" | "Sequel" | "DLC" | ... (English key)
    title: str
    title_ru: Optional[str] = None
    media_type: str
    year: Optional[int] = None
    poster_url: Optional[str] = None
    id: Optional[str] = None
    source: Optional[str] = None


class ReadingLog(BaseModel):
    """Open Library readers: how many want to read / are reading / read."""
    want: Optional[int] = None
    reading: Optional[int] = None
    read: Optional[int] = None


class SpecRow(BaseModel):
    """One line of a system-requirements list: "Memory" / "8 GB RAM". `label`
    is empty for a line Steam wrote without one."""
    label: str = ""
    value: str


class SystemRequirements(BaseModel):
    """PC requirements as Steam lists them (minimum and, when the studio gave
    one, recommended). Labels are canonical English where recognised
    ("OS", "Processor", "Memory", "Graphics", "Storage" ...) so the client
    can translate them; values are the studio's own text."""
    minimum: List[SpecRow] = Field(default_factory=list)
    recommended: List[SpecRow] = Field(default_factory=list)


class TitleExtras(BaseModel):
    # False when a source we depend on for this title's extras couldn't be
    # asked (Shikimori throttled ...). GET /media/detail then doesn't treat
    # the cached copy as final and rebuilds it on the next open, so a bad
    # minute is retried instead of remembered forever. An *empty* extras with
    # complete=True means "asked, nothing to show" — also how a row cached
    # before extras existed (extras=None) is told apart and refreshed once.
    complete: bool = True

    # --- shared ---------------------------------------------------------
    screenshots: List[str] = Field(default_factory=list)
    tags: List[TitleTag] = Field(default_factory=list)
    links: List[TitleLink] = Field(default_factory=list)
    related: List[RelatedTitle] = Field(default_factory=list)
    alt_titles: List[str] = Field(default_factory=list)
    original_language: Optional[str] = None   # "ru", "en", "ja" ...
    popularity: Optional[int] = None          # people who track/list it
    favourites: Optional[int] = None

    # --- games ----------------------------------------------------------
    storyline: Optional[str] = None
    perspectives: List[str] = Field(default_factory=list)
    languages: List[GameLanguage] = Field(default_factory=list)
    time_to_beat: Optional[TimeToBeat] = None
    price: Optional[str] = None               # formatted by the store, e.g. "1 299 ₽"
    price_discount_pct: Optional[int] = None
    free_to_play: Optional[bool] = None
    metacritic: Optional[int] = None
    achievements: Optional[int] = None
    steam_features: List[str] = Field(default_factory=list)  # "Controller support", ...
    requirements: Optional[SystemRequirements] = None
    pc_platforms: List[str] = Field(default_factory=list)    # "windows" | "mac" | "linux"
    steam_deck: Optional[str] = None                         # "verified" | "playable" | "unsupported"
    critic_score: Optional[int] = None        # IGDB critics 0-100
    critic_votes: Optional[int] = None

    # --- books ----------------------------------------------------------
    pages: Optional[int] = None
    published_date: Optional[str] = None
    subtitle: Optional[str] = None
    book_language: Optional[str] = None
    creators: List[TitleCreator] = Field(default_factory=list)  # also manga/anime staff
    first_sentence: Optional[str] = None
    reading_log: Optional[ReadingLog] = None

    # --- manga / anime --------------------------------------------------
    characters: List[TitleCharacter] = Field(default_factory=list)
    studios: List[str] = Field(default_factory=list)
    source_material: Optional[str] = None     # "Manga" | "Light novel" | "Original" ...
    episodes: Optional[int] = None
    episodes_aired: Optional[int] = None
    episode_minutes: Optional[int] = None
    next_episode_at: Optional[str] = None     # ISO datetime
    start_date: Optional[str] = None
    end_date: Optional[str] = None



class MediaItem(ImageFieldsModel):
    id: str
    media_type: str  # "movie" | "series" | "anime" | "game" | "book" | "manga"
    external_ids: ExternalIds
    title: LocalizedText
    description: LocalizedText
    poster_url: Optional[str] = None
    backdrop_url: Optional[str] = None  # wide still/fanart image, not the portrait poster
    # A Russian-localized poster from TMDB, when TMDB actually had one for
    # this title (see app/adapters/tmdb.py::full_detail) — populated
    # only by GET /media/detail, same as cast/director below. poster_url
    # above is unaffected; the client decides which one to show
    # per its own language setting.
    poster_url_ru: Optional[str] = None
    year: Optional[int] = None
    genres: List[str] = Field(default_factory=list)
    rating: Optional[float] = None
    source: str  # "tmdb" | "igdb" | "google_books" | "shikimori_manga"

    # Populated only by GET /media/detail (the TMDB full-detail call, or
    # the IGDB game-detail call) — every search/feed/collections
    # response leaves these null regardless of source. Exception:
    # runtime_minutes for games is always null — IGDB has no average
    # playtime field, unlike some other game catalogs.
    tagline: Optional[str] = None
    # TMDB's Russian-localized tagline, when TMDB actually has one (see
    # app/adapters/tmdb.py::full_detail) — same "second field, client
    # picks" convention as poster_url_ru above, rather than folding this
    # into a LocalizedText: only ever populated for source=="tmdb", and
    # every other adapter's tagline (a synthesized "By <author>" byline
    # for books, "Published by <x>" for manga) is already language-
    # agnostic, so a full LocalizedText here would be dead weight for
    # every non-tmdb title.
    tagline_ru: Optional[str] = None
    runtime_minutes: Optional[int] = None
    certification: Optional[str] = None   # age rating, e.g. "PG-13", "TV-MA"
    release_date: Optional[str] = None    # full date when TMDB has one, else just the year
    status: Optional[str] = None          # "released" | "returning series" | "ended" | ...
    country: Optional[str] = None
    has_trailer: Optional[bool] = None

    # Populated only by GET /feed/for-you (movies/series only) — a YouTube
    # video id resolved from TMDB's /videos endpoint (see
    # app/adapters/tmdb.py::videos). Null whenever there's no tmdb id to
    # look up, TMDB has nothing for it, or the item isn't part of the
    # for-you feed at all.
    trailer_youtube_id: Optional[str] = None

    # Populated only by GET /media/detail, for movie/series/anime titles
    # with a resolved TMDB id (source=="tmdb") — games/books/manga carry
    # neither of these. See app/adapters/tmdb.py::full_detail. Empty list /
    # null rather than an error when there's no tmdb id, TMDB has nothing,
    # or the fetch failed — same "degrade to what we already had" as
    # everything else TMDB-sourced here.
    cast: List[CastMember] = Field(default_factory=list)
    director: Optional[str] = None
    # TMDB person id of the *first* credited director — used to make
    # "directed by ___" tappable (see GET /media/person). Only one id even
    # when `director` above is a joined "A, B" string for co-directors;
    # good enough for the common single-director case, and a co-directed
    # title still shows the names, just isn't tappable to the second name.
    director_id: Optional[str] = None

    # ------------------------------------------------------------------
    # Game/book/manga-specific enrichment. All populated only by
    # GET /media/detail (same convention as tagline/runtime/certification
    # above) — search/feed/collections leave these null/empty too. Each
    # field is meaningful for exactly one or two media types and simply
    # stays empty for the rest, same as cast/director already do for
    # games/books/manga.
    # ------------------------------------------------------------------

    # Games (IGDB involved_companies) — the developer(s)/publisher(s),
    # joined "A, B" the same way `director` joins co-directors above.
    developer: Optional[str] = None
    # Games (IGDB involved_companies): publisher(s). Books (Google Books
    # volumeInfo.publisher): the single publisher, unjoined.
    publisher: Optional[str] = None
    # Games (IGDB platforms.name), e.g. ["PC", "PlayStation 5", "Xbox Series X|S"].
    platforms: List[str] = Field(default_factory=list)
    # Games (IGDB game_modes.name), e.g. ["Single player", "Co-operative"].
    game_modes: List[str] = Field(default_factory=list)
    # Books (Google Books industryIdentifiers) — ISBN-13, falling back to
    # ISBN-10 when that's all the source has.
    isbn: Optional[str] = None
    # Manga (Shikimori) — total volume/chapter counts when the work is far
    # enough along (or finished) for Shikimori to know them; null for an
    # ongoing series still short on either count, same "unknown, not
    # zero" convention as everything else optional on this model.
    volumes: Optional[int] = None
    chapters: Optional[int] = None

    # The richer per-type layer (screenshots, authors, characters, languages,
    # links, related works ...) — see TitleExtras above. GET /media/detail
    # only; None on every search/feed/collections card.
    extras: Optional[TitleExtras] = None


class RatingsOut(BaseModel):
    """From GET /media/detail's `ratings` field — the community/critic
    layer, distinct from a user's own hearts (see
    WatchlistEntryOut.user_rating / DiaryEntryOut.rating). Sourced
    entirely from TMDB. Both fields optional because a very obscure title can have too few
    TMDB votes to mean much, though TMDB rarely has literally zero."""
    tmdb_rating: Optional[float] = None
    tmdb_votes: Optional[int] = None
    # Merged TMDB-review + Trakt-review count — see
    # app/routers/media.py::_apply_review_count. Unrelated to tmdb_votes
    # above (that's star-rating voters, this is written reviews).
    reviews_count: Optional[int] = None
    # Kinopoisk + IMDb, via ПоискКино (see app/adapters/poiskkino.py).
    # Filled in per request and only for Russian-language callers
    # (GET /media/detail?lang=ru) — never part of the cached detail, so
    # a rating that moved isn't frozen in. Null = unknown, not zero.
    kp_rating: Optional[float] = None
    kp_votes: Optional[int] = None
    imdb_rating: Optional[float] = None
    imdb_votes: Optional[int] = None
    # Books only (GET /media/detail for a Google Books title): Hardcover's
    # community rating on its own 0-5 scale, how many people rated, and the
    # book's page there (where its reviews live — their text is not ours to
    # show, see app/adapters/hardcover.py). Same "per request, never in the
    # forever cache" rule as the Kinopoisk fields above.
    hc_rating: Optional[float] = None
    hc_votes: Optional[int] = None
    hc_url: Optional[str] = None
    # Games only (GET /media/detail for an IGDB game that has a Steam page):
    # share of positive Steam reviews (0-100) over all languages, and how
    # many reviews that is. Same "per request, never in the forever cache".
    steam_pct: Optional[int] = None
    steam_votes: Optional[int] = None
    # Manga only: AniList's community mean score on a 0-10 scale.
    al_rating: Optional[float] = None


class TitleTrailer(BaseModel):
    """One YouTube-hosted video for the title screen's "trailers" shelf —
    see app/adapters/tmdb.py::TmdbAdapter._extract_trailers. `name` is
    TMDB's own label for the video (e.g. "Official Trailer", "Teaser #2"),
    shown as the card's caption; `thumbnail_url` is a YouTube-hosted still
    built straight from the video id, no extra TMDB image call needed."""
    video_id: str
    name: str
    thumbnail_url: Optional[str] = None


class MediaDetailOut(BaseModel):
    """Response for GET /media/detail — everything the title screen needs
    in one call: the enriched item, the ratings block, and a short "similar
    titles" shelf. `ratings`/`similar` are null/empty rather than erroring
    when TMDB doesn't have the data (or for a game, which has neither)."""
    item: MediaItem
    ratings: Optional[RatingsOut] = None
    similar: List[MediaItem] = Field(default_factory=list)
    # This title's own trailers/teasers, for the shelf between ratings and
    # "if you liked this" — populated only alongside item.cast/director
    # (see app/adapters/tmdb.py::full_detail), since it comes from the
    # exact same TMDB call. Empty, never null, when TMDB has none.
    trailers: List[TitleTrailer] = Field(default_factory=list)
    # Set only when item.cast/director or a translated title/overview came
    # from TMDB (see app/routers/media.py) — TMDB's terms require
    # attribution wherever their data is shown, same reasoning as
    # WatchProvidersOut.attribution above.
    tmdb_attribution: Optional[str] = None
    # Set only for anime (item.media_type == "anime") when title.ru/
    # description.ru/poster_url_ru were overlaid from Shikimori instead of
    # TMDB — see app/adapters/shikimori.py and app/routers/media.py::
    # _apply_shikimori_ru. Independent of tmdb_attribution above: an
    # anime title can carry both at once (cast/director/trailers still come
    # from TMDB, only the Russian text is Shikimori's).
    shikimori_attribution: Optional[str] = None


class PersonDetailOut(ImageFieldsModel):
    """Response for GET /media/person — what a tapped cast tile or
    "directed by ___" name opens. TMDB-only (there's no other source for
    person data in this app); no ratings/similar-titles concept the way
    a title has, just who they are and what they've worked on. See
    app/adapters/tmdb.py::person_detail."""
    person_id: str
    name: str
    photo_url: Optional[str] = None
    biography: Optional[LocalizedText] = None
    birthday: Optional[str] = None  # "YYYY-MM-DD", as TMDB has it
    known_for_department: Optional[str] = None  # "Acting" | "Directing" | ...
    # Their most notable movie/series/anime credits (cast or crew, merged
    # and deduped by title), newest/most-popular first, capped — see
    # app/adapters/tmdb.py::person_detail for the exact cap and sort. Each
    # card is the same MediaItem shape as everywhere else, so it's just
    # another title grid on the client, reusing whatever card widget
    # search results already use.
    filmography: List[MediaItem] = Field(default_factory=list)
    tmdb_attribution: Optional[str] = None



class Collection(BaseModel):
    """A named shelf of real titles for the "Today" screen, curated
    algorithmically off TMDB/IGDB/Open Library — see GET /feed/collections."""
    title: str
    # English name of the shelf — set only for franchise shelves (see
    # app/curated_franchises.py, where each row now carries an English
    # name alongside the Russian one in `title` above). None for
    # /feed/collections and hand-picked teamira shelves, same as
    # description below; the client falls back to `title` when this is
    # unset, same LocalizedText.display convention as everywhere else.
    title_en: Optional[str] = None
    items: List[MediaItem]
    # True only for the franchise shelves GET /feed/teamira builds from
    # app/curated_franchises.py — lets the client render those as a
    # full-width banner instead of the usual horizontal poster row.
    # Always False for /feed/collections and for hand-picked teamira shelves.
    is_franchise: bool = False
    # Short synopsis of the franchise as a whole — TMDB's own `overview`
    # for the /collection, fetched live in app/adapters/tmdb.py::collection
    # (no hand-written text). Only ever set for franchise shelves; None
    # everywhere else, including when TMDB simply has no overview for that
    # collection.
    description: Optional[str] = None
    # Russian translation of `description` above, when TMDB has one for
    # this collection — same pattern as MediaItem.title/description
    # (LocalizedText) but kept as a flat sibling field rather than
    # switching `description` itself to LocalizedText, so older/other
    # clients reading this field as a plain string don't break. Only
    # ever set for franchise shelves, same as `description`.
    description_ru: Optional[str] = None
    # Deeper "how this franchise was made" copy — hand-written text from
    # app/curated_franchises.py (TMDB's overview above doesn't cover
    # production history). Used to be fetched live from Wikipedia; that
    # adapter's gone now, so this is our own text and `history_url` is
    # always None (kept only so older/other clients reading this field
    # don't break).
    history: Optional[str] = None
    history_url: Optional[str] = None


class TodayPickOut(BaseModel):
    """The Home screen's \"today's pick\" card — one franchise shelf (see
    app/curated_franchises.py) picked for today, plus how far the current
    user already is into it. See GET /feed/today-pick.

    `pick_date` is the calendar date (server-side, UTC) this pick was made
    for, ISO `YYYY-MM-DD` — the client keys its own \"dismissed for today\" /
    \"seen today\" state off this rather than off the device's own clock, so
    a rollover mid-session and a rollover the client just didn't notice
    both resolve the same way.
    """
    collection: Collection
    watched_count: int
    total_count: int
    pick_date: str


# ---------------------------------------------------------------------------
# Release calendar — Home screen's two "what's coming out" blocks. See
# app/routers/calendar.py.
#
# ReleaseCalendarItem backs the discovery grid (GET /calendar/releases): a
# date-sorted mix of anime (Shikimori's own calendar), games (IGDB) and
# movies (TMDB) — not tied to anything the current user has logged, same
# spirit as the Collections tab's shelves.
#
# WatchingReleaseItem backs the personal strip (GET /calendar/watching):
# per-title next-episode/release checks against whatever's actually on
# this user's own "watching"/"watch later" shelves. See each schema's own
# docstring for why the two need different shapes.
# ---------------------------------------------------------------------------

class ReleaseCalendarItem(ImageFieldsModel):
    """One dated card on the Home screen's discovery calendar grid — see
    TmdbAdapter.upcoming_movies_calendar, IgdbAdapter.calendar, and
    ShikimoriAdapter.calendar for where each source's rows come from.

    `item` carries the full catalog MediaItem for source in ("tmdb",
    "igdb") — everything the client needs to open TitleDetailScreen the
    same way any other poster grid in this app does. For source ==
    "shikimori" there's no MediaItem-shaped detail screen behind the
    card at all: this app has no id in common with Shikimori's own
    catalog (see ShikimoriAdapter.calendar's own docstring on why a
    title already in this app's library can't be resolved back to its
    Shikimori id, and the same is just as true in reverse — a bare
    calendar row has nothing to match against this app's own titles
    with). `item` is null there and the client instead renders the card
    from title/poster_url directly, opening `external_url` (Shikimori's
    own page for it) on tap rather than an in-app detail screen.
    """
    source: str  # "tmdb" | "igdb" | "shikimori"
    media_type: str  # "movie" | "game" | "anime"
    # ISO date (YYYY-MM-DD) for tmdb/igdb rows; ISO datetime (with
    # timezone offset, as Shikimori's own next_episode_at already is)
    # for shikimori rows, since those carry a real air *time*, not just
    # a day. The client parses either — DateTime.parse handles both
    # shapes fine — and only ever displays the date portion on the grid.
    release_date: str
    title: LocalizedText
    poster_url: Optional[str] = None
    # Shikimori rows only — which episode number airs on release_date.
    year: Optional[int] = None
    episode: Optional[int] = None
    item: Optional[MediaItem] = None
    external_url: Optional[str] = None
    # Genre labels (English, same vocabulary MediaItem.genres uses) so the
    # calendar can be filtered by genre the way the "can't decide?" flow
    # does. For tmdb/igdb rows this is a copy of item.genres; shikimori rows
    # have no `item` at all, so this is the only place their genres live
    # (see ShikimoriAdapter.calendar). Empty when the source had none.
    genres: List[str] = []


class WatchingReleaseItem(ImageFieldsModel):
    """One row on the Home screen's "new episodes" strip — GET
    /calendar/watching. Always about a title already on this user's own
    watching/watch-later shelf (models.WatchStatus), never a discovery
    suggestion — that's ReleaseCalendarItem's job.

    `is_out` is the whole point of this shape: true means the
    episode/release this row describes has already aired/shipped as of
    `release_date` and this user hasn't logged it yet (see
    app/routers/calendar.py::watching_releases for exactly how that's
    decided per media_type) — "there's something new to watch right
    now". False means it's still upcoming — "coming up", a countdown,
    not a call to action. Both states share one shape/one shelf rather
    than being two separate lists, since the client draws them as the
    same card either way, just with a different label
    ("new episode!" vs "in 3 days").
    """
    media_id: str
    source: str  # "tmdb" | "igdb" — see app/routers/calendar.py::watching_releases for why never "shikimori" here
    media_type: str  # "series" | "anime" | "game"
    title: LocalizedText
    poster_url: Optional[str] = None
    release_date: str  # ISO date, or ISO datetime for a tmdb episode air date
    is_out: bool
    # Series/anime only — which episode this row is about. Null for games.
    season: Optional[int] = None
    episode: Optional[int] = None
    episode_name: Optional[str] = None


# ---------------------------------------------------------------------------
# Teamira picks — hand-curated shelves (see app/models.py::TeamiraCollection
# for the "why a third concept" reasoning, and app/curated_franchises.py for
# the other, code-defined half of this feature — franchise shelves aren't
# managed through these schemas at all). GET /feed/teamira returns both
# halves in the same `Collection` shape as the shelves above, so the
# mobile client reuses the exact same widgets; the schemas below are only
# for the admin endpoints that create/edit the hand-picked half.
# ---------------------------------------------------------------------------

class TeamiraCollectionItemIn(BaseModel):
    media_id: str
    media_type: str  # "movie" | "series" | "anime" | "game" | "book" | "manga"
    # Which catalog media_id belongs to — defaults to "tmdb" for
    # movie/series/anime, since that was the only source this ever
    # supported before games/books/manga were added, and old callers
    # never had to send this. Explicit for the others: "igdb" (game),
    # "google_books" (book), "shikimori_manga" (manga).
    source: str = "tmdb"


class TeamiraCollectionItemOut(BaseModel):
    id: str
    media_id: str
    media_type: str
    source: str
    position: int

    class Config:
        from_attributes = True


class TeamiraCollectionIn(BaseModel):
    title: str
    # Optional English shelf name — same fallback convention as
    # Collection.title_en (franchise shelves) and MediaItem's
    # LocalizedText: unset means the client just shows `title` regardless
    # of the language toggle, same as before this field existed.
    title_en: Optional[str] = None


class TeamiraCollectionOut(BaseModel):
    id: str
    title: str
    title_en: Optional[str] = None
    position: int
    items: List[TeamiraCollectionItemOut] = Field(default_factory=list)

    class Config:
        from_attributes = True


class TeamiraSearchResultOut(ImageFieldsModel):
    """One catalog search hit — just enough to pick the right
    (media_id, source, media_type) when adding a manual item (see GET
    /teamira/admin/search). Covers every catalog a shelf can now draw
    from, not just TMDB."""
    media_id: str
    media_type: str  # "movie" | "series" | "anime" | "game" | "book" | "manga"
    source: str  # "tmdb" | "igdb" | "google_books" | "shikimori_manga"
    title: str
    year: Optional[int] = None
    poster_url: Optional[str] = None


# ---------------------------------------------------------------------------
# Seasons & episodes — a series' structure (from TMDB, best-effort) plus
# one user's own watched/unwatched marks on top of it. The two are fetched
# separately (GET /media/episodes is public catalog data, cached forever
# per title; GET+POST /progress/* is per-user) so a title with no episode
# data from TMDB can still, in principle, carry progress rows — the UI
# just has nothing to render a checklist against in that case.
# ---------------------------------------------------------------------------

class EpisodeOut(BaseModel):
    season: int
    episode: int
    title: Optional[str] = None


class SeasonOut(ImageFieldsModel):
    season: int
    episodes: List[EpisodeOut]
    # From TMDB — best-effort, see TmdbAdapter.season_posters. None when TMDB has no
    # id match for this title, no key is configured, or TMDB simply has
    # no poster for that particular season.
    poster_url: Optional[str] = None


class EpisodesOut(BaseModel):
    seasons: List[SeasonOut] = Field(default_factory=list)


class EpisodeKey(BaseModel):
    season: int
    episode: int


class ProgressToggleRequest(BaseModel):
    media_id: str
    source: str
    watched: bool
    episodes: List[EpisodeKey]  # one entry for a single episode, many to bulk-toggle a season


class WatchedEpisodeOut(BaseModel):
    season: int
    episode: int
    # When this mark was made — EpisodeProgress has always stored this,
    # it just wasn't surfaced here before. Lets a client show "watched
    # Jul 14" next to a ticked episode instead of just a bare checkmark.
    watched_at: str
    # That episode's own lightweight rating/note — set from the episode
    # list (see routers/progress.py::rate_episode), not the full log
    # ritual. Null until the person rates that specific episode.
    rating: Optional[int] = None
    note: Optional[str] = None


class SeriesProgressOut(BaseModel):
    watched: List[WatchedEpisodeOut] = Field(default_factory=list)


# Counters above this are a typo or abuse, not a reader (the longest manga
# runs to a few thousand chapters).
READING_COUNTER_MAX = 100000


class ReadingProgressIn(BaseModel):
    """PUT /progress/reading. A counter left out (or null) means "not
    tracking that one"; all three empty/zero clears the bookmark."""
    media_id: str
    source: str
    volume: Optional[int] = Field(default=None, ge=0, le=READING_COUNTER_MAX)
    chapter: Optional[int] = Field(default=None, ge=0, le=READING_COUNTER_MAX)
    page: Optional[int] = Field(default=None, ge=0, le=READING_COUNTER_MAX)


class ReadingProgressOut(BaseModel):
    """Everything null when the user has no bookmark on this title."""
    volume: Optional[int] = None
    chapter: Optional[int] = None
    page: Optional[int] = None
    updated_at: Optional[str] = None


class EpisodeRatingRequest(BaseModel):
    """One episode's own lightweight rating/note, set right from the
    episode list — not the full log ritual, and never creates a diary
    row by itself. Marks the episode watched if it wasn't already (you
    can't rate something you haven't seen). See
    routers/progress.py::rate_episode, and mobile's
    episode_log_followup.dart::maybeLogCompletedSeason for how a whole
    season's worth of these later becomes one diary entry.
    """
    media_id: str
    source: str
    season: int
    episode: int
    rating: Optional[int] = Field(default=None, ge=1, le=10)
    note: Optional[str] = Field(default=None, max_length=2000)


class CompleteSeriesRequest(BaseModel):
    """The explicit "every episode is watched now" transition — sent once
    the client's own episode count says the series is fully watched.
    Never inferred implicitly from a single episode log (see
    routers/diary.py::log_watched), so a half-watched series doesn't get
    silently promoted to `watched` just because one evening was logged."""
    media_id: str
    source: str


# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------

class RegisterRequest(BaseModel):
    # Length, character set, separator rules and the reserved-name list
    # all live in app/usernames.py::validate_username, which
    # routers/auth.py calls — one place decides what a username may be,
    # rather than this schema and that router each enforcing half of it
    # and disagreeing about case (which is exactly how "Anna" and "anna"
    # both came to exist). The bounds here are the loose outer envelope
    # so a hostile 10 MB string is rejected before it reaches any of it.
    username: str = Field(min_length=1, max_length=64)
    # Client already enforces >=6 (see register_screen.dart) — matched
    # here too since this schema is what actually decides what's
    # allowed, not the app screen in front of it; someone hitting the
    # API directly shouldn't get a weaker bar than the app gives.
    password: str = Field(min_length=6, max_length=72)
    # Someone else's standing invite code (see routers/friends.py) —
    # optional, matched case-insensitively at registration. An unknown or
    # empty code is silently ignored rather than rejected: a typo'd code
    # shouldn't block someone from making an account.
    referral_code: Optional[str] = Field(default=None, max_length=32)

    # Optional, sent by the mobile client so "where you're signed in"
    # can say "iPhone 14" instead of an opaque id. Never trusted for
    # anything but display — see models.RefreshSession.device_label.
    device_label: Optional[str] = Field(default=None, max_length=60)


class LoginRequest(BaseModel):
    username: str = Field(min_length=1, max_length=64)
    password: str = Field(min_length=1, max_length=72)
    device_label: Optional[str] = Field(default=None, max_length=60)


class TokenResponse(BaseModel):
    """The pair every sign-in hands back.

    `refresh_token` is Optional only so this model can also describe a
    response from a deployment with refresh disabled; in practice every
    path in routers/auth.py fills it. `expires_in` is seconds and is
    there so the client can refresh *before* a request fails rather than
    discovering expiry by getting a 401 — see mobile's api_client.dart,
    which does both (proactive refresh, plus a 401 retry as the backstop).
    """
    access_token: str
    token_type: str = "bearer"
    refresh_token: Optional[str] = None
    expires_in: Optional[int] = None


class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=10, max_length=256)


class SessionOut(BaseModel):
    """One row of "where you're signed in"."""
    id: str
    device_label: Optional[str] = None
    created_at: Optional[datetime] = None
    last_used_at: Optional[datetime] = None
    expires_at: Optional[datetime] = None
    revoked: bool = False
    revoked_reason: Optional[str] = None


class SimpleMessageOut(BaseModel):
    message: str


class PasswordChangeRequest(BaseModel):
    current_password: str = Field(min_length=1, max_length=72)
    new_password: str = Field(min_length=6, max_length=72)
    device_label: Optional[str] = Field(default=None, max_length=60)


class PasswordForgotRequest(BaseModel):
    email: EmailStr


class PasswordResetRequest(BaseModel):
    token: str = Field(min_length=10, max_length=256)
    new_password: str = Field(min_length=6, max_length=72)


class EmailSetRequest(BaseModel):
    email: EmailStr
    # The account password, required because an email address can be
    # traded for the account itself through password reset — see
    # routers/auth.py::set_email.
    password: str = Field(min_length=1, max_length=72)


class EmailVerifyRequest(BaseModel):
    token: str = Field(min_length=10, max_length=256)


class EulaAcceptRequest(BaseModel):
    version: Optional[str] = Field(default=None, max_length=32)


class AccountDeleteRequest(BaseModel):
    password: str = Field(min_length=1, max_length=72)
    # Free-text, optional, never shown to the person again — a single
    # line of "why" is the cheapest product feedback there is, and asking
    # for it at the moment someone leaves is the only time they'll answer.
    reason: Optional[str] = Field(default=None, max_length=500)


class AccountDeletionOut(BaseModel):
    deleted_at: datetime
    purge_after: datetime
    restore_days: int
    message: str


class AccountRestoreRequest(BaseModel):
    username: str = Field(min_length=1, max_length=64)
    password: str = Field(min_length=1, max_length=72)
    device_label: Optional[str] = Field(default=None, max_length=60)


class UserOut(BaseModel):
    id: str
    username: str
    created_at: Optional[datetime] = None
    display_name: Optional[str] = None
    avatar_preset: Optional[str] = None
    avatar_url: Optional[str] = None
    status_text: Optional[str] = None
    # Recovery state, so the app knows whether to keep nudging for an
    # address (see the mobile Account screen). The address itself is
    # returned so someone can check *which* one they used; it's their
    # own, so there's nothing to withhold.
    email: Optional[str] = None
    email_verified: bool = False
    # False when the account has never accepted the agreement, or
    # accepted a version older than the current one — the client shows
    # the EULA sheet on next launch. See routers/auth.py::accept_eula.
    eula_current: bool = True
    is_admin: bool = False

    class Config:
        from_attributes = True


# --- Moderation ------------------------------------------------------------

class BlockRequest(BaseModel):
    user_id: str = Field(min_length=1, max_length=64)


class BlockedUserOut(BaseModel):
    user_id: str
    username: str
    display_name: Optional[str] = None
    avatar_preset: Optional[str] = None
    avatar_url: Optional[str] = None
    blocked_at: Optional[datetime] = None


class ReportCreateRequest(BaseModel):
    # "user" | "diary_entry" | "activity_event" | "list" | "review"
    target_type: str
    # The account the complaint is about. Always required, even when the
    # target is a piece of content: a moderator acting on a report needs
    # to know whose it is, and resolving content -> author server-side
    # for every target type would mean five separate lookups where the
    # client already knows the answer.
    reported_user_id: str = Field(min_length=1, max_length=64)
    # NULL when target_type is "user".
    target_id: Optional[str] = Field(default=None, max_length=64)
    reason: str
    details: Optional[str] = Field(default=None, max_length=1000)


class ReportOut(BaseModel):
    id: str
    target_type: str
    target_id: Optional[str] = None
    reason: str
    details: Optional[str] = None
    status: str
    created_at: Optional[datetime] = None
    due_at: Optional[datetime] = None
    resolved_at: Optional[datetime] = None
    action_taken: Optional[str] = None
    reported_username: Optional[str] = None


class ReportAdminOut(ReportOut):
    reporter_username: Optional[str] = None
    reported_user_id: Optional[str] = None
    target_snapshot: Optional[str] = None
    # True once due_at has passed with the report still pending — the
    # queue's own answer to Apple's 24-hour expectation.
    overdue: bool = False


class ReportResolveRequest(BaseModel):
    # "none" | "content_removed" | "user_suspended" | "user_banned"
    action_taken: str = "none"
    note: Optional[str] = Field(default=None, max_length=1000)
    # Only read when action_taken is a suspension. None means indefinite,
    # which is what "banned" is.
    suspend_days: Optional[int] = Field(default=None, ge=1, le=3650)


# ---------------------------------------------------------------------------
# Feed / watchlist reactions
# ---------------------------------------------------------------------------

class FeedReaction(BaseModel):
    item: MediaItem
    action: str  # "like" (watch_later) | "watched" | "skip"


class WatchlistEntryOut(ImageFieldsModel):
    id: str
    media_id: str
    media_type: str
    source: str
    title_ru: Optional[str]
    title_en: Optional[str]
    poster_url: Optional[str]
    # Wide still/fanart image — see models.WatchlistEntry.backdrop_url's
    # own docstring. None on a row from before this shipped.
    backdrop_url: Optional[str] = None
    year: Optional[int]
    genres: List[str]
    rating: Optional[float]        # source's score (TMDB/IMDb-style)
    runtime_minutes: Optional[int] = None
    user_rating: Optional[int] = None   # personal hearts, 1-5
    note: Optional[str] = None
    # Mirrors of the latest logged evening's DiaryEntry.mood_tags /
    # favorite_cast — see models.WatchlistEntry.mood_tags's own
    # docstring. NULL on any row from before this shipped (the column
    # was added via ALTER TABLE, which only sets new rows' default, not
    # existing ones) — the validator below reads that back as "no
    # tags/cast yet", same as a freshly-logged row with none picked.
    mood_tags: List[str] = Field(default_factory=list)
    favorite_cast: List[CastMember] = Field(default_factory=list)
    watched_at: Optional[datetime] = None
    status: str
    is_favorite: bool = False

    @field_validator("mood_tags", "favorite_cast", mode="before")
    @classmethod
    def _null_to_empty_list(cls, v):
        return v if v is not None else []

    class Config:
        from_attributes = True


class FavoriteToggleIn(BaseModel):
    """POST /profile/favorites/toggle — same `item` shape /feed/react
    takes, so the title screen's heart button can fire this with whatever
    MediaItem it already has in hand, watched or not."""
    item: MediaItem
    is_favorite: bool


class FavoriteToggleOut(BaseModel):
    is_favorite: bool


# ---------------------------------------------------------------------------
# Lists — user-made collections, distinct from the editorial shelves in
# Collection/named_collections above (those have no user_id at all).
# ---------------------------------------------------------------------------

class UserListItemOut(ImageFieldsModel):
    id: str
    media_id: str
    media_type: str
    source: str
    title_ru: Optional[str]
    title_en: Optional[str]
    poster_url: Optional[str]
    year: Optional[int]
    genres: List[str]
    rating: Optional[float]
    added_at: datetime

    class Config:
        from_attributes = True


class UserListCreate(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    description: Optional[str] = Field(default=None, max_length=300)


class UserListUpdate(BaseModel):
    name: Optional[str] = Field(default=None, min_length=1, max_length=80)
    description: Optional[str] = Field(default=None, max_length=300)


class UserListOut(BaseModel):
    """The lists screen's overview — no items, just enough to render a
    card (name, count, a few posters for a collage preview)."""
    id: str
    name: str
    description: Optional[str]
    item_count: int
    preview_posters: List[str] = Field(default_factory=list)
    created_at: datetime


class UserListDetailOut(BaseModel):
    id: str
    name: str
    description: Optional[str]
    items: List[UserListItemOut]
    created_at: datetime


class AddListItemRequest(BaseModel):
    item: MediaItem


# ---------------------------------------------------------------------------
# Diary — one row per logged evening, including rewatches
# ---------------------------------------------------------------------------

class DiaryEntryCreate(BaseModel):
    item: MediaItem
    rating: Optional[int] = Field(default=None, ge=1, le=10)
    note: Optional[str] = Field(default=None, max_length=2000)
    mood_tags: Optional[List[str]] = None  # free-form vibe tags, e.g. "cozy night in", "background noise"
    # Up to 3 cast members picked as this evening's standouts — see
    # models.DiaryEntry.favorite_cast's own docstring. Optional/omittable
    # like mood_tags; the client only sends it when that step wasn't
    # skipped.
    favorite_cast: Optional[List[CastMember]] = None
    watched_at: Optional[str] = None  # ISO date/datetime; defaults to now
    # "watched with [partner]" toggle on the log form — only has any effect
    # while the caller has an active partner link; silently ignored
    # otherwise (see routers/diary.py::log_entry).
    watched_with_partner: Optional[bool] = False
    # "add to favorite films" toggle on the log form, next to the hearts —
    # see routers/diary.py::log_watched. Only ever flips the title's
    # favorite flag ON here; unfavoriting is a title-screen action (see
    # FavoriteToggleIn), not something re-logging without the box checked
    # should silently undo.
    is_favorite: Optional[bool] = False
    # Set `season` (with or without `episode`) to log any progress on a
    # series — a single episode, or a just-completed season. Either way
    # this never creates a second diary row for the series: it's upserted
    # into the one row that series already has, or creates that row if
    # this is the very first time it's being logged (see
    # models.DiaryEntry's own docstring and routers/diary.py::log_watched).
    # Both null (the default) logs a whole title in one row, as always —
    # still valid for movies/games/books.
    season: Optional[int] = None
    episode: Optional[int] = None
    # Only meaningful alongside a season-only log (season set, episode
    # null), as a fallback for the episode count if per-episode progress
    # can't be counted for some reason — see routers/diary.py::log_watched.
    episode_count: Optional[int] = None


class DiaryEntryUpdate(BaseModel):
    """Editing an already-logged evening — the rating/review text (and,
    more rarely, the mood tags or the date) after the fact, from the
    diary, the title screen's rewatch timeline, or anywhere else a past
    entry is shown. Every field is optional and only sent ones the person
    actually changed; `season`/`episode`/the underlying title are never
    editable here — those are structural, not part of the review, so
    changing them means logging a new evening instead of rewriting this
    one. The router only touches fields the client actually included in
    the request body (`exclude_unset`), so leaving a field out keeps it
    as-is while sending it explicitly as `null` clears it (e.g. removing
    a rating or a note).
    """
    rating: Optional[int] = Field(default=None, ge=1, le=10)
    note: Optional[str] = Field(default=None, max_length=2000)
    mood_tags: Optional[List[str]] = None
    watched_at: Optional[str] = None  # ISO date/datetime
    # Up to 3 cast members picked as this evening's standouts — see
    # models.DiaryEntry.favorite_cast's own docstring. Editable after the
    # fact from the "edit this evening" sheet, same as rating/note/mood.
    favorite_cast: Optional[List[CastMember]] = None




# ---------------------------------------------------------------------------
# Sincerity points — see app/sincerity.py's module docstring
# ---------------------------------------------------------------------------

class SincerityTransactionOut(BaseModel):
    id: str
    delta: int
    reason: str
    note: Optional[str] = None
    created_at: datetime


class SincerityStaleItemOut(BaseModel):
    """One watch_later item old enough to owe (or already be exempt
    from) stale_debt — what the Sincerity screen's "settle" section
    renders a button from. `settle_cost` rides along rather than the
    client hardcoding sincerity.DEBT_SETTLEMENT_COST, same reasoning as
    SharedPlannedOut.limit not hardcoding CO_VIEW_FREE_LIMIT.
    """
    entry_id: str
    title: str
    poster_url: Optional[str] = None
    age_days: int
    debt_exempt: bool
    settle_cost: int


class SincerityBalanceOut(BaseModel):
    balance: int
    visible_to_friends: bool
    # The merged level ring (see app/sincerity.py's module docstring for
    # why this screen now carries both the spendable balance above and
    # the lifetime level below): level and its progress are computed
    # from lifetime_earned, which only ever goes up, so spending
    # `balance` down can never knock the level itself back down.
    level: int
    lifetime_earned: int
    points_into_level: int
    points_for_next_level: int
    # Most recent first, capped at a page size the router controls — the
    # Sincerity screen shows this as a scroll-to-load list, not a fixed
    # "last 10" preview.
    history: List[SincerityTransactionOut]
    has_more: bool
    # Every still-`watch_later` item past STALE_DEBT_THRESHOLD, exempt or
    # not — see routers/sincerity.py::get_my_sincerity. Small in
    # practice (this is the same shelf apply_stale_planned_decay_for_user
    # already walks), so it rides along on every GET rather than needing
    # its own paginated endpoint.
    stale_items: List[SincerityStaleItemOut] = Field(default_factory=list)


class SincerityPrivacyUpdate(BaseModel):
    visible_to_friends: bool


# ---------------------------------------------------------------------------
# Recommendation stakes — see app/sincerity.py's module docstring and
# app/routers/recommendations.py
# ---------------------------------------------------------------------------

class RecommendationCreate(BaseModel):
    friend_id: str
    source: str
    media_id: str
    title: str
    predicted_rating: int = Field(ge=1, le=10)
    # Clamped server-side to [sincerity.MIN_RECOMMENDATION_STAKE,
    # sincerity.MAX_RECOMMENDATION_STAKE] rather than here — same
    # "caller validates" convention the underlying sincerity.py
    # functions already use, so the two live bounds have one home.
    stake: int = Field(ge=1)


class RecommendationOut(BaseModel):
    id: str
    staker_id: str
    staker_username: str
    recipient_id: str
    recipient_username: str
    source: str
    media_id: str
    title: str
    predicted_rating: int
    staked_amount: int
    status: str
    actual_rating: Optional[int] = None
    created_at: datetime
    resolved_at: Optional[datetime] = None
    # True when the person asking is the one who staked it — lets the
    # client render "ты поставил(а) на Борис — 8" vs "Борис поставил(а)
    # на тебя — 8" from one shape instead of needing separate endpoints
    # for outgoing vs incoming.
    is_mine: bool


class RecommendationsOut(BaseModel):
    outgoing: List[RecommendationOut] = Field(default_factory=list)
    incoming: List[RecommendationOut] = Field(default_factory=list)


class WatchlistDropIn(BaseModel):
    source: str
    media_id: str
    # Required for a mid-watch drop (status was `watching`) — see
    # earn_honest_drop, which awards nothing without one. Optional for a
    # watch_later item that was never actually started — that's
    # earn_closed_gestalt's "not for me" case instead, which doesn't
    # need a reason.
    reason: Optional[str] = None


class WatchlistDropOut(BaseModel):
    status: str
    sincerity_awarded: Optional[List[SincerityTransactionOut]] = None


class DiaryEntryOut(ImageFieldsModel):
    id: str
    media_id: str
    media_type: str
    source: str
    title_ru: Optional[str]
    title_en: Optional[str]
    poster_url: Optional[str]
    # Wide still/fanart image — see models.DiaryEntry.backdrop_url's own
    # docstring. Null on rows logged before this shipped or from a
    # source with no backdrop on file; the client falls back to
    # poster_url either way.
    backdrop_url: Optional[str] = None
    season: Optional[int] = None
    episode: Optional[int] = None
    # Running count of watched episodes — only set on a series' single
    # row (see models.DiaryEntry's docstring), null for movies/etc.
    episodes_watched: Optional[int] = None
    rating: Optional[int]
    note: Optional[str]
    mood_tags: List[str]
    favorite_cast: List[CastMember] = Field(default_factory=list)
    watched_with_username: Optional[str] = None
    is_rewatch: bool
    watched_at: str
    created_at: str
    # Only ever populated by POST /diary (routers/diary.py::log_entry)
    # for the transaction(s) sincerity.py just awarded on this exact
    # log — see log_watched's `_sincerity_awards` docstring. Always
    # None from every other place a DiaryEntryOut gets built (GET
    # /diary, co-view, imports, ...): nothing else has a "just
    # happened" moment worth a toast for.
    sincerity_awarded: Optional[List[SincerityTransactionOut]] = None

    class Config:
        from_attributes = True


# ---------------------------------------------------------------------------
# AI (mock)
# ---------------------------------------------------------------------------

class AiAskRequest(BaseModel):
    query: str = Field(min_length=1, max_length=500)
    # "Сколько у тебя времени сегодня" — the evening-shaped half of Ask
    # tanè (see routers/ai.py::_time_budget). Set by the time chips above
    # the text field; None means the person didn't say, in which case the
    # free text is still scanned for a spoken-out-loud budget ("у меня
    # часа полтора") before giving up on the idea entirely.
    #
    # Capped at 12 hours rather than unbounded: past that it stops being a
    # constraint and starts being a way to ask the ranker to sort the
    # whole catalog by runtime.
    minutes_available: Optional[int] = Field(default=None, ge=10, le=720)


class TimeBudgetOut(BaseModel):
    """What the ranker actually used as the evening's time budget, echoed
    back so the results screen can say "под 40 минут" honestly — including
    when the number came from the free text rather than a chip, which is
    otherwise invisible to the person who typed it."""
    minutes: int
    # "chip" when it came from minutes_available, "text" when it was
    # parsed out of the query itself.
    source: str
    # What that budget was read as wanting — "episode" under ~70 minutes,
    # "movie" above it, "either" in the overlap. Drives the caption, not
    # the filtering (which is done on real runtimes).
    shape: str


class AiMatchOut(BaseModel):
    item: MediaItem
    match: int  # 0-100, local heuristic score — see app/routers/ai.py
    reasoning: Optional[str] = None


class AiAskResponse(BaseModel):
    results: List[AiMatchOut] = Field(default_factory=list)
    is_mock: bool = True
    # Non-null whenever a time budget was in play — see TimeBudgetOut.
    time_budget: Optional[TimeBudgetOut] = None
    # True when a budget was asked for but the shortlist had to include
    # titles that overrun it anyway (nothing short enough scored well
    # enough). The client says so rather than quietly showing a
    # three-hour film to someone who said they had forty minutes.
    time_budget_relaxed: bool = False


# ---------------------------------------------------------------------------
# Activity
# ---------------------------------------------------------------------------

class ActivityItem(ImageFieldsModel):
    # The underlying ActivityEvent id. Empty string for the (now
    # theoretical) case of an item built without a backing row; used
    # purely as an opaque paging cursor for GET /activity's `before` —
    # never shown in the UI.
    id: str = ""
    who: str
    text: str
    media_type: Optional[str] = None
    created_at: str
    # Everything below is optional so older/self rows (or a friend row
    # with no snapshot yet) degrade to the old text-only look instead of
    # failing validation — see routers/activity.py.
    user_id: Optional[str] = None
    username: Optional[str] = None
    display_name: Optional[str] = None
    avatar_preset: Optional[str] = None
    avatar_url: Optional[str] = None
    verb: Optional[str] = None
    media_title: Optional[str] = None
    media_id: Optional[str] = None
    source: Optional[str] = None
    poster_url: Optional[str] = None
    rating: Optional[int] = None


class ActivityFeedOut(BaseModel):
    """GET /activity — cursor-paginated the same way GET /sincerity/me
    is (see routers/sincerity.py). Own events and friends' events are
    merged into one chronological feed server-side (rather than two
    fixed-size buckets stapled together), so `before` pages back through
    real "show more" history instead of hitting a hard wall."""
    items: List[ActivityItem]
    has_more: bool


# ---------------------------------------------------------------------------
# Friends — see app/routers/friends.py for the whole flow. A `FriendRequest`
# row with status=accepted *is* the friendship (no separate friendship
# table), the same one-row-is-the-relationship shape PartnerLink already
# uses for co-viewing pairs.
# ---------------------------------------------------------------------------

class SharedTasteTitleOut(BaseModel):
    """One title behind a TasteMatchOut's shared_titles — a light,
    already-snapshotted reference (same title_ru/title_en/poster_url
    shape as WatchlistEntry itself), never a fresh catalog fetch."""
    media_id: str
    source: str
    media_type: str
    title_ru: Optional[str] = None
    title_en: Optional[str] = None
    poster_url: Optional[str] = None


class TasteMatchOut(BaseModel):
    """The one similarity scale this app shows anywhere two people's
    taste is compared — see app/similarity.py for how it's built.
    Deliberately more than a bare percentage: `headline` is the single
    best plain-language reason for the match (a shared title you're
    both watching right now beats a shared genre), `shared_titles`/
    `shared_genres` are the receipts behind it, and `confidence` lets
    the client soften its own presentation for a very new account
    rather than presenting a five-favorite guess with the same
    certainty as a match built from years of diary history.
    """
    overall: int  # 0-100
    headline: str
    basis: str
    confidence: str  # "new" | "some" | "solid"
    shared_titles: List[SharedTasteTitleOut] = Field(default_factory=list)
    shared_genres: List[str] = Field(default_factory=list)


class FriendOut(BaseModel):
    # The underlying (accepted) FriendRequest id — an opaque paging
    # cursor for GET /friends's `before`, never shown in the UI. Not
    # `user_id` because that's the *other* account's id, not something
    # that orders the friendship itself.
    request_id: str = ""
    user_id: str
    username: str
    level: int
    friends_since: Optional[datetime] = None
    display_name: Optional[str] = None
    avatar_preset: Optional[str] = None
    avatar_url: Optional[str] = None
    status_text: Optional[str] = None
    # The single most recent thing this friend logged, if they've allowed
    # it to be seen (privacy_watched/watching/planned — see models.User)
    # and the client's privacy check passes — shown as a small "last
    # seen" line + rating under their name on the friends screen. Null
    # for a friend with nothing loggable yet, or who's hidden all three
    # shelves.
    recent_activity: Optional[ActivityItem] = None
    # None when there isn't enough shelf data on either side yet to say
    # anything (see similarity.compare) — the client shows nothing
    # rather than a fabricated "0% match" in that case.
    taste_match: Optional[TasteMatchOut] = None


class FriendRequestOut(BaseModel):
    id: str
    user_id: str
    username: str
    created_at: Optional[datetime] = None
    display_name: Optional[str] = None
    avatar_preset: Optional[str] = None
    avatar_url: Optional[str] = None


class FriendsOut(BaseModel):
    # Cursor-paginated the same way GET /sincerity/me is (see
    # routers/sincerity.py) — newest-accepted-first, `has_more` tells the
    # client whether another page exists to ask for with `before`.
    # `total_friends` is a plain count, independent of how much of the
    # list has actually been paged in, so a badge/count display never
    # needs the whole list loaded just to be accurate.
    friends: List[FriendOut] = Field(default_factory=list)
    has_more: bool = False
    total_friends: int = 0
    # Pending requests aren't paginated — bounded by nature (nobody
    # realistically has hundreds of open requests either way), unlike
    # the accepted list above which only ever grows over the life of an
    # account.
    incoming_requests: List[FriendRequestOut] = Field(default_factory=list)
    outgoing_requests: List[FriendRequestOut] = Field(default_factory=list)


class FriendSearchResultOut(BaseModel):
    user_id: str
    username: str
    # "none" | "friends" | "pending_outgoing" | "pending_incoming" — tells
    # the client whether to show "add", "requested", "respond", or nothing.
    status: str
    display_name: Optional[str] = None
    avatar_preset: Optional[str] = None
    avatar_url: Optional[str] = None


class FriendRequestCreate(BaseModel):
    username: str = Field(min_length=1)


# GET /friends/invite — a standing, reusable code plus this account's own
# invite tally, so the profile's invite card can show "3 friends joined —
# +9 sincerity points" without a second round trip.
class InviteOut(BaseModel):
    code: str
    share_text: str
    invited_count: int
    sincerity_bonus: int
    sincerity_per_friend: int


class InviteClaimRequest(BaseModel):
    code: str = Field(min_length=4, max_length=12)


# ---------------------------------------------------------------------------
# Profile
# ---------------------------------------------------------------------------

# GET/PATCH /profile/me — the editable identity block (see models.User):
# name, avatar (preset id or an uploaded photo URL, never both — see
# models.User.avatar_preset's docstring), and status line. Kept separate
# from ProfileStats/CollectionsOut below since those are read-only
# derived data and this is the one part of the profile a person edits.
class TopFavoritePick(BaseModel):
    """One slide of the Profile header's stories-style banner — see
    models.User.top_favorite_picks."""
    media_id: str
    source: str


class ProfileMeOut(BaseModel):
    user_id: str
    username: str
    display_name: Optional[str] = None
    avatar_preset: Optional[str] = None
    avatar_url: Optional[str] = None
    status_text: Optional[str] = None
    created_at: Optional[datetime] = None
    # "everyone" | "friends" | "nobody" each — see models.User.
    privacy_watched: str = "everyone"
    privacy_watching: str = "everyone"
    privacy_planned: str = "everyone"
    privacy_favorites: str = "everyone"
    # "people can find me by my username" — see models.User.discoverable
    # and routers/friends.py::search_users.
    discoverable: bool = True
    # Up to 5 favorites shown as a swipeable stories deck on the Profile
    # header banner, in the order the person arranged them — see
    # models.User.top_favorite_picks. Empty until picked on the
    # favorite-films screen.
    top_favorite_picks: List[TopFavoritePick] = Field(default_factory=list)


_PRIVACY_LEVELS = {"everyone", "friends", "nobody"}


class ProfileUpdateIn(BaseModel):
    # Each field left unset (as opposed to explicitly null) leaves that
    # column untouched — see routers/profile.py::update_me. An explicit
    # "" clears display_name/status_text back to unset.
    display_name: Optional[str] = Field(default=None, max_length=40)
    status_text: Optional[str] = Field(default=None, max_length=120)
    # Picking a preset clears any uploaded avatar_url, and vice versa via
    # POST /profile/avatar — see routers/profile.py.
    avatar_preset: Optional[str] = None
    # Any of these left unset leaves that shelf's setting untouched —
    # same "unset vs explicit" rule as display_name/status_text above.
    discoverable: Optional[bool] = None
    privacy_watched: Optional[str] = None
    privacy_watching: Optional[str] = None
    privacy_planned: Optional[str] = None
    privacy_favorites: Optional[str] = None

    @field_validator("privacy_watched", "privacy_watching", "privacy_planned", "privacy_favorites")
    @classmethod
    def _valid_privacy_level(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v not in _PRIVACY_LEVELS:
            raise ValueError(f"must be one of {sorted(_PRIVACY_LEVELS)}")
        return v


class TopFavoritePickIn(BaseModel):
    """POST /profile/favorites/pick body — the full ordered stories deck,
    replacing whatever was picked before. An empty list clears the
    banner back to its plain placeholder look, same as sending both
    fields null used to. Up to 5 entries; every one must already be one
    of this account's own favorite movies — this only chooses which
    existing favorites get the spotlight and in what order, it doesn't
    create one (use POST /profile/favorites/toggle for that)."""
    picks: List[TopFavoritePick] = Field(default_factory=list, max_length=5)


class AvatarUploadOut(BaseModel):
    avatar_url: str


class ProfileStats(BaseModel):
    movies: int
    series: int
    games: int
    anime: int = 0
    books: int = 0
    manga: int = 0


class CollectionsOut(BaseModel):
    """Reads back the WatchlistEntry rows split by their current status —
    watch_later/watched are the two the app has always produced from
    /feed/react; watching is the new mid-series shelf (see
    models.WatchStatus.watching), populated once an episode has been
    logged but the series hasn't been explicitly completed yet.

    This body is exactly the three keys it's always had — tests pin
    that exact shape (see tests/test_profile.py's
    test_collections_do_not_leak_between_accounts). Each shelf is
    cursor-paginated independently the same way GET /sincerity/me is
    (see routers/sincerity.py), but the has-more flag for each rides in
    a response header (X-Watch-Later-Has-More etc — see
    routers/profile.py::get_collections) instead of a new body field,
    for the same reason GET /diary's own docstring gives.
    `GET /profile/collections?full=true` (the default for every current
    caller, all of which need the complete shelves to compute
    membership/status locally rather than browse them) bypasses paging
    and returns everything, same as GET /diary's own `full` flag."""
    watch_later: List[WatchlistEntryOut]
    watching: List[WatchlistEntryOut] = Field(default_factory=list)
    watched: List[WatchlistEntryOut]


class FriendCollectionsOut(BaseModel):
    """Same shape as CollectionsOut, but each shelf can also come back
    hidden — the friend has that shelf's privacy set below what the
    viewer is allowed to see (see routers/friends.py::get_friend_profile).
    `visible=False` means "don't show this shelf at all", not "it's
    empty" — the client should tell the two apart (a quiet "this person
    keeps their plan to watch private" beats an empty grid that reads as
    them having nothing planned)."""
    watch_later: List[WatchlistEntryOut] = Field(default_factory=list)
    watch_later_visible: bool = True
    watching: List[WatchlistEntryOut] = Field(default_factory=list)
    watching_visible: bool = True
    watched: List[WatchlistEntryOut] = Field(default_factory=list)
    watched_visible: bool = True
    # Favorite films — a status-independent subset (is_favorite=True,
    # media_type="movie") gated by its own privacy_favorites setting
    # rather than folded into watched_visible, since a favorite can be
    # pinned from any shelf. See routers/friends.py::get_friend_profile.
    favorites: List[WatchlistEntryOut] = Field(default_factory=list)
    favorites_visible: bool = True
    # The friend's own stories-deck picks among their favorites (see
    # models.User.top_favorite_picks) — only set when favorites_ok, same
    # gating as `favorites` itself. Lets a friend's profile highlight the
    # same picks this account's own header banner spotlights.
    top_favorite_picks: List[TopFavoritePick] = Field(default_factory=list)


class AchievementOut(BaseModel):
    """Every figure behind this is computed fresh from the person's own
    WatchlistEntry/DiaryEntry/ActivityEvent rows (see
    app/routers/profile.py::get_achievements), nothing stored or
    separately tracked that could drift out of sync with what's actually
    logged. `icon_key` is a small fixed vocabulary the client maps to its
    own icon set per category — see AchievementIcon in the Flutter model —
    rather than shipping icon names or asset paths from the backend.

    Defined here (ahead of FriendProfileOut) because
    FriendProfileOut.pinned_achievements references it — Pydantic
    resolves annotations at class-definition time, so the referenced
    model has to exist above the class that uses it, not just anywhere
    in the module."""
    id: str
    category: str  # "milestone" | "craft" | "genre" | "saga" | "devotion"
    icon_key: str
    title: str
    caption: str
    unlocked: bool
    progress_current: int
    progress_target: int
    # One of "habit" | "devoted" | "obsession" | "legend" — how hard this
    # particular badge is to earn, purely derived from progress_target
    # (see profile.py::_rarity_for_target), never stored. Drives the
    # visual treatment on the badge itself (see AchievementBadge in the
    # mobile app) — nothing else about unlock logic depends on it.
    rarity: str


class FriendProfileOut(BaseModel):
    """Any account's profile screen state in one call — header plus the
    three (privacy-filtered) shelves. Reachable for an accepted friend
    (full "friends"+"everyone" visibility) and for a stranger alike (only
    "everyone" visibility) — see routers/friends.py::get_friend_profile."""
    user_id: str
    username: str
    level: int
    display_name: Optional[str] = None
    avatar_preset: Optional[str] = None
    avatar_url: Optional[str] = None
    status_text: Optional[str] = None
    collections: FriendCollectionsOut
    # This account's pinned badge showcase (see User.pinned_achievement_ids)
    # — always visible; a deliberate self-presentation choice, not a
    # privacy-gated shelf. Empty if they haven't pinned anything yet.
    pinned_achievements: List[AchievementOut] = []
    # This account's recent activity, same privacy gating as the shelves
    # above: an accepted friend sees anything left at "friends" or
    # "everyone", a stranger only sees "everyone" — never "nobody" either
    # way. See routers/friends.py::get_friend_profile.
    recent_activity: List[ActivityItem] = Field(default_factory=list)

    # Relationship state for the two action buttons on this screen (see
    # mobile's friend_profile_screen.dart::_ActionRow) — same
    # "none" | "friends" | "pending_outgoing" | "pending_incoming" shape
    # FriendSearchResultOut already uses, so the client has one status
    # vocabulary for "are we friends" everywhere it appears.
    friendship_status: str = "none"
    # The FriendRequest id behind a pending status, whichever direction —
    # lets the button accept/cancel it directly without a second lookup.
    friend_request_id: Optional[str] = None

    # Same shape, for "are we in the same co-viewing circle" — "none" |
    # "same_circle" (already linked together, couple or company) |
    # "pending_outgoing" (this account invited them, waiting on a reply) |
    # "pending_incoming" (they invited this account) | "unavailable" (this
    # account isn't in a circle it can invite through, or the other side
    # already belongs to a different circle — see
    # routers/partner.py::send_invite for what makes it unavailable).
    coview_status: str = "none"
    coview_invite_id: Optional[str] = None

    # Same taste scale as FriendOut.taste_match/SuggestedFriendOut.taste_match
    # — shown here too so opening someone's profile (friend or stranger)
    # gets the full breakdown, not just the compact card version.
    taste_match: Optional[TasteMatchOut] = None


class SuggestedFriendOut(BaseModel):
    """One row in the friends screen's \"people you may know\" section —
    anyone on teamira who isn't already a friend and has no pending
    request either way. Carries a small preview of their most recent
    *public* ("everyone"-visibility) activity, same card shape as the
    friends activity feed, so tapping it can open the same preview card
    before sending a request."""
    user_id: str
    username: str
    level: int
    display_name: Optional[str] = None
    avatar_preset: Optional[str] = None
    avatar_url: Optional[str] = None
    status_text: Optional[str] = None
    recent_activity: List[ActivityItem] = Field(default_factory=list)
    # Same taste scale as FriendOut.taste_match — this is what lets
    # "people you may know" be ranked (and shown) by actual taste
    # overlap instead of just "who signed up most recently."
    taste_match: Optional[TasteMatchOut] = None


class GenreCount(BaseModel):
    genre: str
    count: int


class ProfileYearStats(BaseModel):
    movies: int
    series: int
    games: int
    anime: int = 0
    books: int = 0
    manga: int = 0
    total: int
    top_genres: List[GenreCount]
    streak_days: int


# ---------------------------------------------------------------------------
# Achievements — AchievementOut itself now lives above (right before
# FriendProfileOut, which references it) — see the docstring there for
# why. AchievementsOut, below, only needs it as a forward reference
# inside a List[...] and has no such ordering constraint.
# ---------------------------------------------------------------------------

class AchievementsOut(BaseModel):
    unlocked_count: int
    total_count: int
    achievements: List[AchievementOut]
    # Which of the unlocked achievement ids this account has chosen to
    # pin to their profile showcase (see User.pinned_achievement_ids) —
    # at most max_pinned, in the order they were pinned.
    pinned_ids: List[str] = []
    # 3 + however many extra slots this account has bought (see
    # User.bonus_pin_slots, app/sincerity.py::spend_pin_slot) — the
    # client reads this instead of hardcoding 3, so a bought slot shows
    # up without a client update. bonus_pin_slots rides along too so the
    # client can tell "at the free cap" from "at a paid cap" and offer
    # the purchase (or not) accordingly.
    max_pinned: int = 3
    bonus_pin_slots: int = 0


class PinAchievementsIn(BaseModel):
    achievement_ids: List[str]


# ---------------------------------------------------------------------------
# Leveling — level and its ring are computed straight from
# User.lifetime_sincerity_earned (see app/routers/profile.py::get_level
# and app/sincerity.py::compute_level; that column only ever goes up,
# even when the spendable sincerity balance is spent down). `points` is
# that lifetime total; `points_into_level`/`points_for_next_level`
# describe progress toward the *next* level only, which is what the
# Sincerity screen's ring actually draws. `progress` is that same
# progress pre-divided (0..1) so the client doesn't need to replicate
# the level curve just to draw the arc.
# ---------------------------------------------------------------------------

class LevelOut(BaseModel):
    # Level and its ring are computed straight from
    # User.lifetime_sincerity_earned (see app/sincerity.py::compute_level
    # and that column's own docstring for why level uses the lifetime
    # total rather than the spendable sincerity_balance). This used to be
    # a second, parallel point system with its own per-source XP
    # breakdown; it no longer is — see app/sincerity.py's module
    # docstring for that merge. The counts below are pure informational
    # stats for the level-detail screen, not a weighted contribution to
    # `points`: for the honest, itemized "where did my points actually
    # come from", see GET /sincerity/me's transaction history instead.
    level: int
    points: int
    points_into_level: int
    points_for_next_level: int
    progress: float
    watched_count: int = 0
    reviews_count: int = 0
    rewatch_count: int = 0
    genres_count: int = 0
    longest_streak_ever: int = 0
    # Friends who joined via this account's own invite code (see
    # routers/friends.py) — real people onboarded, not something
    # farmable by re-watching or re-tagging existing entries.
    invites_count: int = 0
    # Only rewards the person actually pressed the button to collect
    # (see app/challenges.py) — which is why the level detail screen
    # labels it "собранные челленджи" rather than "выполненные".
    challenges_claimed: int = 0
    # Evenings watched *together* (a DiaryEntry the co-viewing screen or
    # the log form's "watched with" toggle marked as such) and share
    # cards sent out of the app (see routers/card_shares.py — once per
    # distinct card, capped per day).
    watched_together_count: int = 0
    card_shares_count: int = 0


class CardShareIn(BaseModel):
    # The client's own stable id for the card being shared — see
    # models.CardShare. Bounded so it can't be used to stuff arbitrary
    # blobs into a table that exists to hold short ids.
    card_key: str = Field(min_length=1, max_length=128)


class CardShareOut(BaseModel):
    # False when this card already paid out once, or today's cap was
    # already used up — either way the share itself is fine, it just
    # earned nothing. `reason` says which, for the client's own copy.
    counted: bool
    points_awarded: int = 0
    reason: Optional[str] = None  # "already_counted" | "daily_limit" | None
    total_points: int
    level: int
    leveled_up: bool = False


# ---------------------------------------------------------------------------
# Wrapped — the Spotify-Wrapped-style monthly/yearly recap. Everything here
# is an honest estimate built from what's already logged (see
# app/routers/profile.py for the per-media-type hour assumptions), never a
# separately tracked counter that could drift.
# ---------------------------------------------------------------------------

class WrappedBreakdown(BaseModel):
    movies: int = 0
    series: int = 0
    anime: int = 0
    games: int = 0
    books: int = 0
    manga: int = 0



# ---------------------------------------------------------------------------
# Watch Together, over the network — see app/models.py for the reasoning
# behind the code-based pairing (no persistent friends graph).
# ---------------------------------------------------------------------------

class TogetherCreateRequest(BaseModel):
    type_filter: Literal["all", "movie", "series", "game"] = "all"
    genres: List[str] = []  # TMDB-style genre names, e.g. ["Comedy", "Horror"]; [] = no narrowing
    # This device's own Settings > co-viewing choice — whether a match
    # should also land on *this* account's personal "watch together" list.
    sync_to_own_list: bool = True


class TogetherJoinRequest(BaseModel):
    code: str = Field(min_length=6, max_length=6)
    sync_to_own_list: bool = True


class TogetherSwipeRequest(BaseModel):
    media_id: str
    source: str
    decision: bool


class TogetherSessionOut(BaseModel):
    """Everything one screen needs to render its side of a session —
    who's who, the shared deck, how far each side has gotten, and the
    matches so far. `my_role`/`my_swiped`/`partner_swiped` are computed
    relative to whichever account is asking, so both phones can poll the
    exact same endpoint and each see themselves as "me"."""
    id: str
    code: str
    status: str  # "waiting" | "active" | "done"
    type_filter: str
    genres_filter: List[str] = []
    deck: List[MediaItem]
    owner_username: str
    guest_username: Optional[str] = None
    my_role: str  # "owner" | "guest"
    my_swiped: int
    partner_swiped: int
    matches: List[MediaItem]
    created_at: datetime


# ---------------------------------------------------------------------------
# Partner link + suggestions — a standing pairing (link once with a code,
# stays linked) used to send a one-tap "I'm suggesting this for tonight"
# from a title screen straight to the linked partner's Home.
# ---------------------------------------------------------------------------

class PartnerJoinRequest(BaseModel):
    code: str = Field(min_length=6, max_length=6)


class PartnerMemberOut(BaseModel):
    """One seat on the co-viewing circle, for the members list on
    [PartnerOut] — includes the caller's own seat so the client can
    render one consistent "everyone in this circle" row instead of
    special-casing "me" out of a member list."""
    user_id: str
    username: str
    display_name: Optional[str] = None
    avatar_preset: Optional[str] = None
    avatar_url: Optional[str] = None
    is_you: bool = False


class PartnerOut(BaseModel):
    """The co-viewing card's entire state in one shape: linked, waiting on
    a code you just generated, or neither.

    `partner_username` stays around unchanged for a plain couple (the
    overwhelming common case, and simplest for any UI that only ever
    cares about "who's my partner"). `members`/`is_company` are the
    company-aware view of the same state — a couple's `members` is
    just the two of them with `is_company=False`; a company's
    `partner_username` is simply the first other member's name (kept
    populated rather than null so old UI that hasn't been updated for
    companies yet still shows *someone's* name instead of going blank).
    """
    linked: bool
    partner_username: Optional[str] = None
    pending_code: Optional[str] = None  # a code you generated, not yet joined
    members: List[PartnerMemberOut] = Field(default_factory=list)
    is_company: bool = False


class PartnerInviteOut(BaseModel):
    """One pending (or just-answered) direct invite to join a co-viewing
    circle — the alternative to a pairing code, used from a friend's own
    profile screen. See routers/partner.py::send_invite."""
    id: str
    user_id: str  # the *other* side of this invite from the caller's POV
    username: str
    display_name: Optional[str] = None
    avatar_preset: Optional[str] = None
    avatar_url: Optional[str] = None
    status: str  # "pending" | "accepted" | "declined"
    created_at: datetime


class PartnerInvitesOut(BaseModel):
    incoming: List[PartnerInviteOut] = Field(default_factory=list)
    outgoing: List[PartnerInviteOut] = Field(default_factory=list)


class CircleCompatibilityOut(BaseModel):
    """This account's taste match (see app/similarity.py) against one
    other member of its co-viewing circle — a couple gets exactly one
    of these, a company one per other seat. Powers the \"мы\" tab's
    compatibility section (see routers/partner.py::get_compatibility)."""
    user_id: str
    username: str
    display_name: Optional[str] = None
    avatar_preset: Optional[str] = None
    avatar_url: Optional[str] = None
    taste_match: Optional[TasteMatchOut] = None


class SendPartnerInviteRequest(BaseModel):
    user_id: str


class SuggestRequest(BaseModel):
    item: MediaItem


class SuggestionOut(ImageFieldsModel):
    id: str
    media_id: str
    media_type: str
    source: str
    title_ru: Optional[str]
    title_en: Optional[str]
    poster_url: Optional[str]
    year: Optional[int]
    sender_username: str
    created_at: datetime

    class Config:
        from_attributes = True


# ---------------------------------------------------------------------------
# Co-viewing — the shared "planned together" / "watched together" list
# behind a linked pair's dedicated screen. Fed by the suggest heart, and by
# Watch Together matches (both local pass-the-phone and network modes).
# ---------------------------------------------------------------------------

class CoViewEntryOut(ImageFieldsModel):
    id: str
    media_id: str
    media_type: str
    source: str
    title_ru: Optional[str]
    title_en: Optional[str]
    poster_url: Optional[str]
    year: Optional[int]
    status: str  # "planned" | "watched"
    added_by_username: Optional[str] = None
    watched_at: Optional[datetime] = None
    created_at: datetime
    # Set only when this entry came from "plan an evening"'s co-viewing
    # toggle — see models.CoViewEntry.
    scheduled_date: Optional[datetime] = None
    scheduled_hour: Optional[int] = None
    scheduled_minute: Optional[int] = None
    # Set only on the response to "mark watched": how many of the partner's
    # sealed notes that call just opened for the caller. Non-zero is the
    # client's cue to play the reveal (see routers/pair_album.py). Always 0
    # everywhere else this shape is returned.
    album_reveal_count: int = 0

    class Config:
        from_attributes = True


class CoViewOut(BaseModel):
    my_username: str
    partner_username: Optional[str] = None
    # Everyone else in the circle besides the caller — a couple has
    # exactly one entry here (same person `partner_username` names),
    # a company has two or more. See PartnerOut.members for the same
    # shape used on the co-viewing card itself.
    other_usernames: List[str] = Field(default_factory=list)
    planned: List[CoViewEntryOut]
    watched: List[CoViewEntryOut]


class CoViewBulkAddRequest(BaseModel):
    items: List[MediaItem]


class PlanCoViewingRequest(BaseModel):
    """Mirrors a "plan an evening" ticket planned as co-viewing onto the
    shared list — see routers/partner.py::plan_co_viewing."""
    item: MediaItem
    scheduled_date: Optional[datetime] = None
    scheduled_hour: Optional[int] = None
    scheduled_minute: Optional[int] = None


class AcceptSuggestionRequest(BaseModel):
    """Optional body for POST /partner/suggestions/{id}/accept. Approving
    a suggestion is planning an evening around it — see
    routers/partner.py::accept_suggestion — so this carries the same
    "when" the plan-an-evening ritual already collects for any other
    title. All optional (and the whole body itself is optional) so an
    older client that just wants the pre-existing bare-add behavior
    doesn't need to change anything."""
    scheduled_date: Optional[datetime] = None
    scheduled_hour: Optional[int] = None
    scheduled_minute: Optional[int] = None


class MarkCoViewWatchedRequest(BaseModel):
    """Optional body for POST /partner/co-viewing/{entry_id}/watched — the
    client's own local wall-clock instant at the moment "watched" was
    tapped, same convention DiaryEntryCreate.watched_at already uses (a
    bare ISO date or full datetime, defaulting to the server's own UTC
    now when omitted — see routers/diary.py::_parse_watched_at). Without
    this, the co-viewing "mark watched" button was the one write path
    that stamped a real UTC instant into DiaryEntry.watched_at while
    every other path stamps the caller's own local time — and the
    client always reads that column back as if it were local (see
    mobile/lib/models/diary_entry.dart), so co-viewed evenings could
    silently land under the wrong calendar day near a midnight
    boundary."""
    watched_at: Optional[str] = None
    # True when the caller already wrote their own DiaryEntry for this
    # evening some other way (the planned co-view card's "смотрю" button
    # now sends the person through the normal per-title logging ritual —
    # see WatchingChoiceScreen — instead of this endpoint's own bare,
    # no-rating write). When set, this endpoint only flips the
    # CoViewEntry's status/watched_at and skips log_watched entirely, for
    # *every* member including the caller — writing a second, duplicate
    # diary row for whoever just rated it themselves would be a bug, and
    # the other member(s) get their own row the same way anyone else
    # ends up in a shared evening: by logging it themselves. Defaults to
    # False so every existing caller (the instant "mark watched" tick,
    # still used wherever the full ritual isn't) keeps writing both
    # diaries exactly as before.
    already_logged: bool = False


# ---------------------------------------------------------------------------
# Co-viewing vote — deciding which of the titles either side of a linked
# pair already means to watch is the one for tonight. See
# app/routers/co_view_vote.py and models.CoViewVoteSession.
# ---------------------------------------------------------------------------

class CoViewVoteCastRequest(BaseModel):
    media_id: str
    source: str
    decision: bool


class CoViewVoteProposeRequest(BaseModel):
    """Body for POST /partner/co-viewing/vote/propose — one specific pick
    (teamira's suggestion, a reel spin, a random draw) put in front of
    the whole circle instead of one person adding it straight to the
    shared list. Just the item(s) themselves; everything else about the
    round (matching rule, winner, member_count) is identical to a normal
    pool-sourced one — see routers/co_view_vote.py."""
    items: List[MediaItem]


class CoViewPollVoteRequest(BaseModel):
    candidate_index: int


class CoViewPollSessionOut(BaseModel):
    """One head-to-head poll round — see models.CoViewPollSession and
    routers/co_view_poll.py. `candidates`/`vote_counts` are index-aligned
    (candidates[i] got vote_counts[i] votes); a runoff replaces both with
    just the tied leaders and bumps round_number, so the client doesn't
    need to track round history itself, just re-render whatever this
    currently holds."""
    id: str
    status: str  # "active" | "done"
    pool_source: str
    round_number: int
    deadline: datetime
    candidates: List[MediaItem]
    vote_counts: List[int]
    my_vote: Optional[int] = None
    voted_count: int
    member_count: int
    winner: Optional[MediaItem] = None
    created_at: datetime


class CoViewVoteSessionOut(BaseModel):
    """One shared voting round. There's no code to join — an active
    PartnerLink already means everyone's a confirmed member, so every
    phone in the circle polls this same session and each always sees
    itself as "me" via `my_decided`. A match needs a yes from every
    other member, not just one — see
    routers/co_view_vote.py::cast_vote."""
    id: str
    status: str  # "active" | "done"
    pool_source: str  # "personal" | "coview" | "both" | "catalog" — see CoViewVoteSession.pool_source
    deck: List[MediaItem]
    my_decided: List[str] = []  # "source:id" keys this account already voted on
    partner_decided_count: int = 0
    # Everyone currently in the circle, including this account — lets a
    # company's UI show "2 of 3 others have decided" (partner_decided_count
    # out of member_count - 1) instead of just a raw count with nothing
    # to measure it against. Always 2 for a plain couple.
    member_count: int = 2
    winner: Optional[MediaItem] = None
    created_at: datetime


# ---------------------------------------------------------------------------
# Where to watch — availability by provider, plus a click-through link that
# always points back at *our own* backend (never the raw provider URL), so
# the destination can change server-side. See app/routers/watch.py.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Automatic watch tracking ("scrobbling") — see app/routers/integrations.py
# for the full picture of what's genuinely reliable here (Plex/Jellyfin
# webhooks) versus inherently fragile (streaming-site browser scrobbling).
# ---------------------------------------------------------------------------

class ScrobblePayload(BaseModel):
    """The one shape every integration normalizes into before the shared
    logging path runs. Plex/Jellyfin webhooks get translated into this
    server-side; the Kodi addon and the browser extension build it
    themselves and POST it directly, since they have no webhook format of
    their own to translate from."""
    title: str
    media_type: str = "movie"  # "movie" | "series" — best guess if the source can't say
    season: Optional[int] = None
    episode: Optional[int] = None
    year: Optional[int] = None
    tmdb_id: Optional[str] = None
    imdb_id: Optional[str] = None
    progress: float = 1.0    # 0..1, fraction watched — only meaningful when completed=False
    completed: bool = True   # an explicit "yes, this counts as watched" signal, when the source has one


class IntegrationTokenOut(BaseModel):
    """Everything the Integrations settings screen needs to render: the
    raw token (shown once, for anyone who wants to configure something
    these ready-made URLs don't cover) plus a URL already built for each
    supported source."""
    token: str
    plex_webhook_url: str
    jellyfin_webhook_url: str
    kodi_url: str
    extension_ingest_url: str


class ScrobbleEventOut(BaseModel):
    id: str
    integration: str
    raw_title: Optional[str] = None
    matched_media_id: Optional[str] = None
    matched_source: Optional[str] = None
    action: str
    detail: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True


class WatchProviderOut(ImageFieldsModel):
    provider_key: str
    name: str
    logo_url: Optional[str] = None
    kind: str  # "flatrate" | "rent" | "buy"
    out_url: str  # our own /media/watch-out redirect — see app/routers/watch.py


class WatchProvidersOut(BaseModel):
    country: str
    providers: List[WatchProviderOut]
    more_url: Optional[str] = None  # TMDB's own JustWatch-attributed "watch" page
    attribution: str = "Streaming data provided by JustWatch"


class TmdbReviewOut(BaseModel):
    """One written review from GET /media/reviews. Up to three sources
    feed this — TMDB's own /reviews, Trakt's /comments (see
    app/routers/reviews.py for why: TMDB alone is often nearly empty),
    and, for Russian-language callers only, Kinopoisk via ПоискКино.
    IMDB still isn't an option — no public API at all for review text."""
    author: str
    avatar_url: Optional[str] = None
    rating: Optional[float] = None  # the reviewer's own 0-10 score, when they left one
    content: str
    created_at: Optional[datetime] = None
    url: str  # the review's page on themoviedb.org, trakt.tv, kinopoisk.ru, steam or anilist.co, for "read more" / full context
    source: str = "tmdb"  # "tmdb" | "trakt" | "kinopoisk" | "steam" | "anilist"
    # Kinopoisk, Steam and AniList reviews (null for TMDB/Trakt): a headline
    # where the source has one (Kinopoisk's title, AniList's summary line), a
    # tone ("positive" | "negative" | "neutral" — Kinopoisk reviewers pick
    # one, Steam's is recommend / don't recommend, AniList's is derived from
    # the reviewer's score), and how many people found it useful.
    title: Optional[str] = None
    tone: Optional[str] = None
    likes: Optional[int] = None
    # Steam only: hours the reviewer had played when they wrote it.
    playtime_hours: Optional[float] = None

    # Deliberately NOT on the shared ImageFieldsModel mixin — avatar_url
    # is also a field name UserOut/ActivityItem use for a user's own
    # *uploaded* avatar (served from this app's own /static/avatars/,
    # nothing to do with TMDB), so resolving it generically there would
    # be wrong. This is TmdbReviewOut's own field_serializer, scoped to
    # just this class, for TMDB's reviewer avatar specifically.
    @field_serializer("avatar_url")
    def _ser_avatar(self, v: Optional[str]) -> Optional[str]:
        return resolve_image_url(v, TMDB_PROFILE_BASE)


class TmdbReviewsOut(BaseModel):
    reviews: List[TmdbReviewOut]
    attribution: str = "Отзывы предоставлены TMDB и Trakt"


class WrappedStat(ImageFieldsModel):
    period: str            # "month" | "year"
    period_label: str      # e.g. "July 2026" or "2026"
    total_logged: int
    hours: float            # estimated total hours spent, this period
    breakdown: WrappedBreakdown
    top_genres: List[GenreCount]
    longest_streak: int
    busiest_day: Optional[str] = None       # weekday name, e.g. "Saturday"
    favorite_title: Optional[str] = None
    favorite_poster: Optional[str] = None
    favorite_media_type: Optional[str] = None
    is_premium: bool = True
    unlocked: bool = True   # always true in the demo, regardless of is_premium


# ---------------------------------------------------------------------------
# Wrapped — full year recap ("envelope -> cards -> letter -> receipt").
# Every field is computed fresh from the person's own DiaryEntry rows for
# the selected period (see app/routers/profile.py::get_wrapped_summary) —
# nothing here is stored separately, so it can never drift out of sync
# with what's actually logged. director/year are best-effort snapshots
# (see models.DiaryEntry.director/year) — null/empty just means that data
# wasn't known at log time, not an error.
# ---------------------------------------------------------------------------

class WrappedTitleMoment(ImageFieldsModel):
    title: str
    date_label: str        # e.g. "1 января"
    poster_url: Optional[str] = None


class WrappedDirectorCount(BaseModel):
    name: str
    count: int


class WrappedDecadeBucket(BaseModel):
    label: str              # "2020s" | "2010s" | "older"
    count: int
    percent: float


class WrappedTimelineBucket(BaseModel):
    """One point on the card that varies by scope: day-of-month counts
    for a `month` summary, month-of-year counts for a `year`/`all` one."""
    label: str              # e.g. "1" (day) or "янв" (month)
    count: int


class WrappedWeekdayCount(BaseModel):
    weekday: int            # 0=Monday .. 6=Sunday
    count: int


class WrappedGenreShare(BaseModel):
    genre: str
    count: int
    percent: float


class WrappedReviewItem(ImageFieldsModel):
    title: str
    rating: Optional[int] = None   # 1-10
    note: Optional[str] = None
    date_label: Optional[str] = None
    poster_url: Optional[str] = None


class WrappedReceiptItem(BaseModel):
    title: str
    count: int             # times logged (rewatches included)


class WrappedRatingBucket(BaseModel):
    rating: int             # 1-10
    count: int


class WrappedSummary(ImageFieldsModel):
    scope: str              # "month" | "year" | "all"
    year: int               # anchor year (month/year scope); current year for "all"
    month: Optional[int] = None   # 1-12, only set for scope == "month"
    period_label: str       # e.g. "май 2026", "2026", "за всё время"
    range_label: str        # e.g. "01.05 — 31.05", "01.01 — 31.12", "12.03.25 — 29.07.26"

    total_logged: int
    total_hours: float

    first: Optional[WrappedTitleMoment] = None
    last: Optional[WrappedTitleMoment] = None
    days_span: int = 0

    top_directors: List[WrappedDirectorCount] = Field(default_factory=list)
    decades: List[WrappedDecadeBucket] = Field(default_factory=list)

    new_count: int = 0       # first-ever logged titles this period
    rewatch_count: int = 0   # logged evenings that were rewatches

    timeline: List[WrappedTimelineBucket] = Field(default_factory=list)
    busiest_timeline_label: Optional[str] = None
    longest_streak_days: int = 0

    weekdays: List[WrappedWeekdayCount] = Field(default_factory=list)
    weekend_percent: float = 0.0

    solo_count: int = 0
    company_count: int = 0
    solo_percent: float = 0.0

    peak_hour: Optional[int] = None       # 0-23
    peak_hour_percent: float = 0.0        # share of evenings within +-1h of peak_hour
    archetype_label: str = ""

    genre_mix: List[WrappedGenreShare] = Field(default_factory=list)
    top_genre: Optional[str] = None

    review_count: int = 0
    average_rating: float = 0.0
    full_marks_count: int = 0             # rating == 10 ("full five hearts")
    top_reviews: List[WrappedReviewItem] = Field(default_factory=list)
    favorite_review: Optional[WrappedReviewItem] = None
    rating_histogram: List[WrappedRatingBucket] = Field(default_factory=list)

    hours_percentile: Optional[int] = None  # this account vs everyone else, this same period, 1-100

    receipt_items: List[WrappedReceiptItem] = Field(default_factory=list)

    # A handful of poster URLs from this period's own entries, most
    # recent first — purely decorative (poster strips on cards that would
    # otherwise be mostly empty space), never used as data.
    poster_urls: List[str] = Field(default_factory=list)

    is_premium: bool = True
    unlocked: bool = True


class WrappedMonthPeriod(BaseModel):
    year: int
    month: int


class WrappedPeriodsOut(BaseModel):
    """Powers the period picker — every (year) and (year, month) that this
    account actually has diary entries in, so the picker only ever offers
    periods with something to show. Newest first."""
    years: List[int] = Field(default_factory=list)
    months: List[WrappedMonthPeriod] = Field(default_factory=list)
    has_any: bool = False


# ---------------------------------------------------------------------------
# Premium (see routers/premium.py and models.UserPremiumState).
# ---------------------------------------------------------------------------

class PremiumStatusOut(BaseModel):
    is_premium: bool
    plan_kind: Optional[str] = None      # "individual" | "couple" | "family"
    # How many people this account's own purchase covers, itself
    # included (1 individual, 2 couple, 4 family) — None when there is
    # no purchase. Lets the client say "covers up to N of you" without
    # hardcoding the seat counts (routers/premium.py::PLAN_SEATS).
    plan_seats: Optional[int] = None
    plan_duration: Optional[str] = None  # "month" | "threeMonths" | "sixMonths" | "year"
    ai_asks_used: int = 0
    ai_asks_remaining: int = 0
    # Mirrored here rather than hardcoded twice — PremiumService in the
    # mobile app reads this instead of keeping its own copy of the free
    # tier's monthly cap, so the two can't drift out of sync.
    free_ai_asks_per_month: int = 3
    # Referral-granted bonus days, see models.UserPremiumState.
    # premium_expires_at and routers/referrals.py. None when no referral
    # bonus has ever been granted to this account.
    premium_expires_at: Optional[datetime] = None
    # Whether this account can still call POST /premium/start-trial —
    # false once either a purchase or a trial has ever been recorded
    # (see routers/premium.py::_status_out). The paywall reads this to
    # decide whether its main call-to-action is "start your free trial"
    # or a straight purchase.
    trial_available: bool = False
    # Mirrored the same way free_ai_asks_per_month is, so the client
    # never hardcodes a number that could drift from what the server
    # actually grants.
    trial_days: int = 3
    # Where this account is in its free period: "active" (a trial that
    # hasn't run out — includes any referral days stacked on it),
    # "expired" (trialed, never bought, no premium left) or None (never
    # trialed, or already a paying customer). `trial_ends_at` is the
    # moment premium actually stops (premium_expires_at) while active.
    # `trial_logged_count` is what the person did in the app since the
    # trial began, for the "here's what you built" line on the expiry
    # paywall; 0 whenever trial_phase is None. See app/trial.py.
    trial_phase: Optional[str] = None
    trial_ends_at: Optional[datetime] = None
    trial_logged_count: int = 0
    # Only set on the response to a POST /premium/purchase call that
    # actually redeemed a promo code — a one-shot receipt for the
    # "промокод применён: -15%" toast, not a standing property of the
    # account, so it's always None on GET /premium/status.
    applied_discount_percent: Optional[int] = None
    # Where is_premium comes from right now: "own" (this account's own
    # purchase, trial or referral days), "partner" (covered by the other
    # person's couple or family plan — see routers/premium.py::_seat_covers), or
    # None when not premium. Lets the client tell "you pay" from "you're
    # covered" (no purchase CTA for the second, no double payment)
    # without guessing from plan_kind, which stays None for a covered
    # account: it has no plan of its own.
    premium_source: Optional[str] = None
    # Which kind of discount `applied_discount_percent` was: "promo" (a
    # referral code) or "winback" (the personal comeback offer). Same
    # one-shot receipt semantics as the percent itself.
    applied_discount_kind: Optional[str] = None
    # A purchased plan's life, see app/subscription.py: "active",
    # "cancelling" (cancelled, still running until cancel_effective_at),
    # "paused" (until paused_until), "lapsed" (cancelled and run out —
    # the win-back moment), or None for an account that never bought.
    subscription_phase: Optional[str] = None
    # End of the paid period we're in (the next renewal) while the plan
    # is "active"; None in every other phase.
    paid_until: Optional[datetime] = None
    cancel_effective_at: Optional[datetime] = None
    paused_until: Optional[datetime] = None
    # Whether POST /premium/pause would be accepted right now, and how
    # long a pause lasts — echoed so the client never hardcodes either.
    pause_available: bool = False
    pause_days: int = 30
    # The personal comeback discount open right now, if any: percent off
    # and the moment it stops. None outside that window and once used.
    winback_percent: Optional[int] = None
    winback_expires_at: Optional[datetime] = None


class PremiumPurchaseIn(BaseModel):
    plan_kind: str      # "individual" | "couple" | "family"
    plan_duration: str  # "month" | "threeMonths" | "sixMonths" | "year"
    # A referred person's personal code (see models.PromoCode) — optional,
    # matched case-insensitively. Invalid/foreign/already-used codes
    # raise 400 rather than being silently ignored, so the purchase
    # screen can tell the person their code didn't work instead of
    # quietly charging them full price.
    promo_code: Optional[str] = Field(default=None, max_length=16)


class PremiumAiAskOut(BaseModel):
    allowed: bool
    ai_asks_used: int
    ai_asks_remaining: int


# ---------------------------------------------------------------------------
# Referral program (see models.Referral / ReferralReward / PromoCode and
# routers/referrals.py). Separate from InviteOut/InviteClaimRequest above,
# which are the plain "who invited whom" graph — this is the reward layer
# on top of it.
# ---------------------------------------------------------------------------

class ReferredUserOut(BaseModel):
    """One row in "Мои приглашения" — enough to render the person's name,
    their status, and — for anyone still pending — literal progress
    against the three real-person conditions, so the UI can show exactly
    what's missing instead of just a spinner."""
    referred_user_id: str
    display_name: Optional[str] = None
    username: str
    status: str  # "pending" | "verified" | "rewarded" | "rejected"
    created_at: datetime
    verified_at: Optional[datetime] = None

    # Progress toward the three pending-only conditions — always present
    # (0s once verified/rejected) so the client doesn't need separate
    # optional-handling for "still relevant" vs "no longer relevant".
    entries_count: int
    entries_required: int
    streak_days: int
    streak_days_required: int
    days_since_signup: int
    days_since_signup_required: int
    # The earliest calendar date this referral could ever be counted,
    # regardless of how fast the other two conditions are met — mirrors
    # the exact "не раньше [дата]" copy from the product spec.
    eligible_not_before: datetime


class ReferralStatusOut(BaseModel):
    verified_count: int    # cumulative verified+rewarded, never resets
    pending_count: int
    next_milestone_at: Optional[int] = None       # next confirmed-invite count that pays out — see
                                                    # routers/referrals.py::_next_milestone; None once
                                                    # RECURRING_MILESTONE_LAST_AT is reached (nothing left)
    next_milestone_days: Optional[int] = None      # bonus days that milestone grants
    referred: List[ReferredUserOut]
    promo_code: Optional[str] = None               # this account's OWN code, if it has one to share (i.e. was itself referred)
    promo_discount_percent: int = 15
    # Mirrored here rather than hardcoded on the client — see
    # routers/referrals.py::REFERRED_WELCOME_DAYS's own comment on what
    # this is (the invited person's own reward, separate from the
    # referrer's milestones above).
    referred_welcome_days: int = 3
    # Fine-print for the referral screen — see invite_copy.py::
    # REFERRAL_RULES_TEXT for why the wording lives there and not here.
    rules_text: str = ""


class AdminReferralOut(BaseModel):
    id: str
    referrer_username: str
    referred_username: str
    status: str
    created_at: datetime
    verified_at: Optional[datetime] = None
    entries_count_snapshot: int
    streak_days_current: int
    ip_at_signup: Optional[str] = None


# ---------------------------------------------------------------------------
# Shared (couple / company) diary — see app/routers/shared_diary.py
# ---------------------------------------------------------------------------


class SharedDiaryPersonOut(BaseModel):
    """One member's side of a shared evening. A film watched together has
    two (or more) of these on a single card — that's the whole point of
    the shared diary over just seeing each other's separate feeds.

    `rating` and `note` are each independently nullable for two different
    reasons that the client deliberately doesn't get to tell apart: the
    person didn't leave one, or their own privacy prefs hide it (see
    models.PartnerPrefs). Leaking "they wrote something but you can't see
    it" would be worse than leaking the note.
    """
    user_id: str
    username: str
    display_name: Optional[str] = None
    avatar_preset: Optional[str] = None
    avatar_url: Optional[str] = None
    rating: Optional[int] = None
    note: Optional[str] = None
    # True when `rating` reads null specifically because the viewer
    # hasn't yet logged their own rating for this title and hasn't paid
    # to peek (see app/sincerity.py's spoiler_unlock/formed_own_opinion
    # pair and routers/shared_diary.py::_person_out) — distinct from a
    # plain "didn't rate it" or a privacy-hidden rating, which both also
    # read as `rating: null` but leave this False. The client uses it to
    # show a "reveal for N points" affordance instead of just "no
    # rating yet".
    rating_hidden: bool = False
    watched_at: str
    entry_id: str
    # True when this row belongs to the person asking — the client uses it
    # to decide whose card gets the edit/unshare affordances, rather than
    # comparing usernames itself.
    is_me: bool = False


class SharedDiaryItemOut(ImageFieldsModel):
    """One title on the shared diary, with everyone's side of it merged
    into a single card. Keyed by (source, media_id) rather than by diary
    row id, since the whole job here is collapsing two people's separate
    rows for the same film into one entry."""
    media_id: str
    source: str
    media_type: str
    title_ru: Optional[str] = None
    title_en: Optional[str] = None
    poster_url: Optional[str] = None
    backdrop_url: Optional[str] = None
    year: Optional[int] = None
    genres: List[str] = Field(default_factory=list)
    runtime_minutes: Optional[int] = None
    # The most recent watched_at across everyone's rows — what the list
    # sorts and groups by, so a card doesn't jump around as the second
    # person logs their side of the same evening.
    watched_at: str
    watched_together: bool = False
    people: List[SharedDiaryPersonOut] = Field(default_factory=list)
    # Set only when every member visible on this card left a rating —
    # the "вы разошлись на 4 балла" line needs both halves to mean
    # anything.
    rating_gap: Optional[int] = None


class SharedDiaryOut(BaseModel):
    items: List[SharedDiaryItemOut] = Field(default_factory=list)
    # Cursor for "показать ещё" — the watched_at of the last item, to be
    # sent back as `before`. Null when there's nothing older.
    next_before: Optional[str] = None
    member_usernames: List[str] = Field(default_factory=list)


class SharedPlannedOut(BaseModel):
    """The co-viewing queue, plus the free-tier ceiling alongside it so
    the client never has to hardcode the number (see
    routers/partner.py::CO_VIEW_FREE_LIMIT)."""
    planned: List[CoViewEntryOut] = Field(default_factory=list)
    limit: Optional[int] = None      # null once premium — no ceiling
    used: int = 0
    is_premium: bool = False


class SharedStatsOut(BaseModel):
    """"Наш год" — the couple's own numbers, the shared-diary answer to
    the personal Wrapped. Almost everything here is computed from the
    same shared rows the diary list shows, so a number can never
    describe an evening the person can't scroll to — the one exception
    is `added_by_counts`, see its own comment below."""
    period: str                       # "year" | "all"
    period_label: str
    evenings_together: int = 0
    evenings_shared_total: int = 0
    hours_together: float = 0.0
    top_genres: List[str] = Field(default_factory=list)
    # Average rating each member gave across shared entries, only for
    # members whose share_ratings is on.
    average_ratings: dict = Field(default_factory=dict)
    # The title with the largest disagreement, if any — the single best
    # conversation starter this screen can produce.
    biggest_disagreement: Optional[SharedDiaryItemOut] = None
    # The highest-scoring title both people rated well.
    best_shared_pick: Optional[SharedDiaryItemOut] = None
    # Longest run of consecutive calendar days with a shared evening.
    longest_streak_days: int = 0
    first_evening_at: Optional[str] = None
    planned_count: int = 0
    # "кто чаще предлагает" — username -> count. The one field here NOT
    # built from the shared-diary rows described above: it's sourced from
    # the co-viewing inbox (CoViewEntry, planned + watched) instead, since
    # the question is who reaches for the app to suggest something, not
    # who watched more. See shared_stats() in routers/shared_diary.py.
    added_by_counts: dict = Field(default_factory=dict)


class PartnerPrefsOut(BaseModel):
    auto_share_logs: bool = True
    share_ratings: bool = True
    share_notes: bool = False


class PartnerPrefsUpdate(BaseModel):
    auto_share_logs: Optional[bool] = None
    share_ratings: Optional[bool] = None
    share_notes: Optional[bool] = None


class ShareDiaryEntryIn(BaseModel):
    """Per-entry override for the auto-share setting — the "поделиться с
    нами" / "убрать из общего" action on a diary card. `shared=False` on
    an evening that was watched together is refused rather than honored;
    see routers/shared_diary.py::set_entry_shared for why."""
    shared: bool


# ---------------------------------------------------------------------------
# Challenges — see app/challenges.py
# ---------------------------------------------------------------------------


class ChallengeOut(BaseModel):
    id: str
    cadence: str            # "weekly" | "yearly"
    icon_key: str
    title: str
    caption: str
    rule: str = ""
    current: int
    target: int
    progress: float = 0.0   # 0..1, pre-divided so the client doesn't redo it
    completed: bool = False
    claimed: bool = False
    points: int = 0
    days_left: Optional[int] = None
    period_key: str = ""
    completed_at: Optional[datetime] = None


class ChallengesOut(BaseModel):
    weekly: List[ChallengeOut] = Field(default_factory=list)
    yearly: List[ChallengeOut] = Field(default_factory=list)
    # Finished but not yet acknowledged by the client — what Home's
    # banner shows. Emptied by POST /challenges/seen.
    to_announce: List[ChallengeOut] = Field(default_factory=list)
    # Ready to collect. Drives the badge on the Home card.
    claimable_count: int = 0
    week_ends_at: Optional[str] = None


class ChallengeClaimOut(BaseModel):
    challenge: ChallengeOut
    points_awarded: int
    # The level total *after* this claim, so the client can animate the
    # ring without a second round trip to /sincerity/me.
    total_points: int
    level: int
    leveled_up: bool = False


# ---------------------------------------------------------------------------
# Pair album — see routers/pair_album.py and app/pair_album.py.
# ---------------------------------------------------------------------------

class AlbumPersonOut(BaseModel):
    user_id: str
    username: str
    display_name: Optional[str] = None
    avatar_preset: Optional[str] = None
    avatar_url: Optional[str] = None
    is_you: bool = False


class AlbumFirstEveningOut(ImageFieldsModel):
    """The first evening the pair marked watched together — the anniversary
    screen's \"our first film\"."""
    title_ru: Optional[str] = None
    title_en: Optional[str] = None
    poster_url: Optional[str] = None
    watched_at: Optional[datetime] = None


class AlbumStatusOut(BaseModel):
    is_couple: bool
    # Whether either member has premium: unlimited notes and capsules, and
    # the anniversary date. Reading is never gated, and a free circle still
    # gets a small allowance of notes and one capsule — see the limits below.
    is_premium: bool
    # The server's calendar day. The client renders countdowns from this, not
    # from its own clock, so a shifted phone clock can't fake an opening.
    server_today: date
    together_since: Optional[date] = None
    together_set_by: Optional[str] = None  # username of whoever last set it
    # The day the two accounts were linked here — offered as a starting point
    # when nobody has set an anniversary yet, never assumed to be one.
    linked_on: Optional[date] = None
    people: List[AlbumPersonOut] = Field(default_factory=list)
    evenings_together: int = 0
    first_evening: Optional[AlbumFirstEveningOut] = None
    pages_count: int = 0        # revealed evenings that have at least one note
    unread_pages: int = 0       # revealed, partner's note, not opened by me yet
    waiting_mine: int = 0       # my notes still sealed
    waiting_partner: int = 0    # partner's notes still sealed (a count, never text)
    capsules_sealed: int = 0    # not open yet
    capsules_ready: int = 0     # open, and I haven't opened it yet
    has_content: bool = False   # anything at all that unlinking would destroy
    # The free allowance, sent rather than hardcoded in the client (same
    # reasoning as SharedPlannedOut.limit). `null` limit = no ceiling, i.e.
    # premium. Notes are counted per person (these are *mine*), capsules per
    # couple; both count what exists now, see app/pair_album.py.
    notes_limit: Optional[int] = None
    notes_used: int = 0
    capsules_limit: Optional[int] = None
    capsules_used: int = 0


class AlbumNoteOut(BaseModel):
    id: str
    is_mine: bool
    author_username: str
    body: str
    mood: Optional[str] = None
    # On my note: the partner's reaction to it. On the partner's note: mine.
    reaction: Optional[str] = None
    opened: bool = False  # for the partner's note: have I opened it yet
    created_at: datetime


class AlbumPageOut(ImageFieldsModel):
    """One title's page in the shared book: the two notes (or one) left for
    a given viewing. `state == "waiting"` pages carry only *my* text plus
    `partner_sealed`; `"revealed"` pages carry both."""
    source: str
    media_id: str
    media_type: str
    title_ru: Optional[str] = None
    title_en: Optional[str] = None
    poster_url: Optional[str] = None
    year: Optional[int] = None
    round: int
    state: str  # "waiting" | "revealed"
    mine: Optional[AlbumNoteOut] = None
    partner: Optional[AlbumNoteOut] = None
    partner_sealed: bool = False
    entry_id: Optional[str] = None       # the planned co-view entry, when there is one
    evening_on: Optional[date] = None    # revealed pages: the evening's day
    revealed_at: Optional[datetime] = None
    unread: bool = False


class AlbumPagesOut(BaseModel):
    items: List[AlbumPageOut]
    next_before: Optional[datetime] = None


class PutAlbumNoteRequest(BaseModel):
    item: MediaItem
    body: str
    mood: Optional[str] = None


class AlbumReactRequest(BaseModel):
    emoji: Optional[str] = None  # null clears the reaction


class TogetherSinceRequest(BaseModel):
    together_since: Optional[date] = None  # null clears it


class CreateCapsuleRequest(BaseModel):
    opens_on: date
    title: Optional[str] = None
    body: str


class AddCapsuleLetterRequest(BaseModel):
    body: str


class CapsuleLetterOut(BaseModel):
    is_mine: bool
    author_username: str
    body: str
    sealed_at: datetime


class CapsuleOut(BaseModel):
    id: str
    title: Optional[str] = None
    opens_on: date
    created_at: datetime
    created_by_username: Optional[str] = None
    created_by_me: bool = False
    state: str  # "sealed" | "open"
    days_left: int  # 0 once open
    my_letter_sealed: bool = False
    partner_letter_sealed: bool = False
    # Empty until `state == "open"` — the server does not return sealed text
    # to anyone, the author included.
    letters: List[CapsuleLetterOut] = Field(default_factory=list)
    opened_by_me: bool = False
    # Creator only, before opening, and only while the partner hasn't put a
    # letter in — nobody else's words get destroyed by deleting it.
    can_delete: bool = False


class CapsulesOut(BaseModel):
    items: List[CapsuleOut]

