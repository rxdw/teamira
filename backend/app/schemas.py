from datetime import datetime
from typing import Optional, List
from pydantic import BaseModel, Field, field_validator


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


class CastMember(BaseModel):
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


class MediaItem(BaseModel):
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
    source: str  # "tmdb" | "igdb" | "open_library" | "open_library_manga"

    # Populated only by GET /media/detail (the TMDB full-detail call, or
    # the IGDB game-detail call) — every search/feed/collections
    # response leaves these null regardless of source. Exception:
    # runtime_minutes for games is always null — IGDB has no average
    # playtime field, unlike some other game catalogs.
    tagline: Optional[str] = None
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


class PersonDetailOut(BaseModel):
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
    # "open_library" (book), "open_library_manga" (manga).
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


class TeamiraSearchResultOut(BaseModel):
    """One catalog search hit — just enough to pick the right
    (media_id, source, media_type) when adding a manual item (see GET
    /teamira/admin/search). Covers every catalog a shelf can now draw
    from, not just TMDB."""
    media_id: str
    media_type: str  # "movie" | "series" | "anime" | "game" | "book" | "manga"
    source: str  # "tmdb" | "igdb" | "open_library" | "open_library_manga"
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


class SeasonOut(BaseModel):
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
    note: Optional[str] = None


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
    username: str
    password: str = Field(min_length=1, max_length=72)
    # Someone else's standing invite code (see routers/friends.py) —
    # optional, matched case-insensitively at registration. An unknown or
    # empty code is silently ignored rather than rejected: a typo'd code
    # shouldn't block someone from making an account.
    referral_code: Optional[str] = None


class LoginRequest(BaseModel):
    username: str
    password: str = Field(min_length=1, max_length=72)


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UserOut(BaseModel):
    id: str
    username: str
    created_at: Optional[datetime] = None
    display_name: Optional[str] = None
    avatar_preset: Optional[str] = None
    avatar_url: Optional[str] = None
    status_text: Optional[str] = None

    class Config:
        from_attributes = True


# ---------------------------------------------------------------------------
# Feed / watchlist reactions
# ---------------------------------------------------------------------------

class FeedReaction(BaseModel):
    item: MediaItem
    action: str  # "like" (watch_later) | "watched" | "skip"


class WatchlistEntryOut(BaseModel):
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

class UserListItemOut(BaseModel):
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
    note: Optional[str] = None
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
    note: Optional[str] = None
    mood_tags: Optional[List[str]] = None
    watched_at: Optional[str] = None  # ISO date/datetime
    # Up to 3 cast members picked as this evening's standouts — see
    # models.DiaryEntry.favorite_cast's own docstring. Editable after the
    # fact from the "edit this evening" sheet, same as rating/note/mood.
    favorite_cast: Optional[List[CastMember]] = None


class DiaryEntryOut(BaseModel):
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

    class Config:
        from_attributes = True


# ---------------------------------------------------------------------------
# AI (mock)
# ---------------------------------------------------------------------------

class AiAskRequest(BaseModel):
    query: str


class AiMatchOut(BaseModel):
    item: MediaItem
    match: int  # 0-100, local heuristic score — see app/routers/ai.py
    reasoning: Optional[str] = None


class AiAskResponse(BaseModel):
    results: List[AiMatchOut] = Field(default_factory=list)
    is_mock: bool = True


# ---------------------------------------------------------------------------
# Activity
# ---------------------------------------------------------------------------

class ActivityItem(BaseModel):
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


# ---------------------------------------------------------------------------
# Friends — see app/routers/friends.py for the whole flow. A `FriendRequest`
# row with status=accepted *is* the friendship (no separate friendship
# table), the same one-row-is-the-relationship shape PartnerLink already
# uses for co-viewing pairs.
# ---------------------------------------------------------------------------

class FriendOut(BaseModel):
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


class FriendRequestOut(BaseModel):
    id: str
    user_id: str
    username: str
    created_at: Optional[datetime] = None
    display_name: Optional[str] = None
    avatar_preset: Optional[str] = None
    avatar_url: Optional[str] = None


class FriendsOut(BaseModel):
    friends: List[FriendOut] = Field(default_factory=list)
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
# +90 xp" without a second round trip.
class InviteOut(BaseModel):
    code: str
    share_text: str
    invited_count: int
    xp_bonus: int
    xp_per_friend: int


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
    logged but the series hasn't been explicitly completed yet."""
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
    # — always visible, same as the current-level bunny already shown on a
    # friend's profile; a deliberate self-presentation choice, not a
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
    # at most 3, in the order they were pinned.
    pinned_ids: List[str] = []


class PinAchievementsIn(BaseModel):
    achievement_ids: List[str]


# ---------------------------------------------------------------------------
# Leveling — like Achievements above, this is computed fresh from the
# person's own logged rows every time (see
# app/routers/profile.py::get_level), never a stored counter. `xp` is the
# lifetime total; `xp_into_level`/`xp_for_next_level` describe progress
# toward the *next* level only, which is what the profile ring actually
# draws. `progress` is that same progress pre-divided (0..1) so the client
# doesn't need to replicate the level curve just to draw the arc.
# ---------------------------------------------------------------------------

class LevelOut(BaseModel):
    level: int
    xp: int
    xp_into_level: int
    xp_for_next_level: int
    progress: float
    # Breakdown of total_xp by source — same five wells levelXpNote already
    # describes on the client, exposed here so the level detail screen can
    # show its numbers instead of just naming the categories.
    watched_count: int = 0
    xp_from_watched: int = 0
    reviews_count: int = 0
    xp_from_reviews: int = 0
    rewatch_count: int = 0
    xp_from_rewatches: int = 0
    genres_count: int = 0
    xp_from_genres: int = 0
    longest_streak_ever: int = 0
    xp_from_streak: int = 0
    # A sixth well: friends who joined via this account's own invite code
    # (see routers/friends.py) — real people onboarded, not something
    # farmable by re-watching or re-tagging existing entries like the
    # other five.
    invites_count: int = 0
    xp_from_invites: int = 0


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
    type_filter: str = "all"  # "all" | "movie" | "series" | "game"
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


class SendPartnerInviteRequest(BaseModel):
    user_id: str


class SuggestRequest(BaseModel):
    item: MediaItem


class SuggestionOut(BaseModel):
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

class CoViewEntryOut(BaseModel):
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


class WatchProviderOut(BaseModel):
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
    """One written review from GET /media/reviews. Two sources feed this
    now — TMDB's own /reviews and Trakt's /comments (see
    app/routers/reviews.py for why: TMDB alone is often nearly empty).
    IMDB still isn't an option — no public API at all for review text."""
    author: str
    avatar_url: Optional[str] = None
    rating: Optional[float] = None  # the reviewer's own 0-10 score, when they left one
    content: str
    created_at: Optional[datetime] = None
    url: str  # the review's page on themoviedb.org or trakt.tv, for "read more" / full context
    source: str = "tmdb"  # "tmdb" | "trakt"


class TmdbReviewsOut(BaseModel):
    reviews: List[TmdbReviewOut]
    attribution: str = "Отзывы предоставлены TMDB и Trakt"


class WrappedStat(BaseModel):
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

class WrappedTitleMoment(BaseModel):
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


class WrappedReviewItem(BaseModel):
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


class WrappedSummary(BaseModel):
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

