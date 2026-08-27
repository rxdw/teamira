import enum
import uuid
from datetime import datetime

from sqlalchemy import (
    Column, String, Integer, Float, Boolean, DateTime, ForeignKey, Enum, JSON, Text, func,
    UniqueConstraint,
)
from sqlalchemy.orm import relationship

from app.database import Base


def gen_uuid() -> str:
    return str(uuid.uuid4())


class MediaType(str, enum.Enum):
    movie = "movie"
    series = "series"
    game = "game"
    # Its own type, not a "series" subset — detected off TMDB's own data
    # (Animation genre + Japanese origin, see app/adapters/tmdb.py::
    # _is_anime) and tagged with this media_type instead of folding it
    # into "series". TMDB itself has no equivalent split (it keeps anime
    # under "tv"), which only matters for the handful of TMDB-only call
    # sites that already branch on media_type == "movie" vs. anything
    # else.
    anime = "anime"
    book = "book"
    manga = "manga"
    # A single trackable unit from "your sources" (see routers/sources.py) —
    # one YouTube video, one Twitch VOD, or a whole playlist/channel pasted
    # in as a link. Deliberately its own type rather than folding into any
    # of the above: these never come from TMDB/IGDB/Open Library, carry no
    # runtime/genre data worth the name, and GET /media/detail has nothing
    # to look them up by — media_type == "video" is exactly how the client
    # knows to open the original link instead of the title detail screen.
    video = "video"


class WatchStatus(str, enum.Enum):
    watch_later = "watch_later"   # "want to watch/play"
    watching = "watching"         # mid-series: at least one episode logged, not all of them yet
    watched = "watched"           # "watched/finished"
    dropped = "dropped"


class User(Base):
    __tablename__ = "users"

    id = Column(String, primary_key=True, default=gen_uuid)
    username = Column(String, unique=True, index=True, nullable=False)
    password_hash = Column(String, nullable=False)
    created_at = Column(DateTime, server_default=func.now())

    # A personal secret embedded in the URL Plex/Jellyfin/Kodi/the browser
    # extension all call — see app/routers/integrations.py. Not a JWT on
    # purpose: those integrations mostly can't be configured with custom
    # Authorization headers, only a plain URL, so the secret has to live
    # in the URL itself. Generated lazily on first request for one,
    # rotatable if it ever leaks.
    scrobble_token = Column(String, unique=True, nullable=True, index=True)

    # This account's own standing "invite a friend" code — see
    # app/routers/friends.py. One code per account, reusable by any
    # number of people (unlike PartnerLink's one-code-one-join model),
    # generated lazily the first time GET /friends/invite is called —
    # same lazy pattern as scrobble_token above.
    invite_code = Column(String, unique=True, nullable=True, index=True)

    # Set once, at registration, if this account was created by entering
    # someone else's invite code (see routers/auth.py::register). Never
    # changes after that. Powers both "invited by ___" and the referrer's
    # own invite-bonus XP count (routers/profile.py counts how many
    # accounts have referred_by_id == their own id).
    referred_by_id = Column(String, ForeignKey("users.id"), nullable=True)

    # Editable profile identity — deliberately separate from `username`
    # (the login handle friend search/requests key off — see
    # routers/friends.py). NULL means "never set one", the client falls
    # back to showing `username` wherever display_name would go.
    display_name = Column(String, nullable=True)

    # One of two ways to have an avatar (see routers/profile.py):
    # avatar_preset is a bundled-in-app asset id (e.g. "bunnies_coviewing",
    # picked for free with no upload), avatar_url is a photo the person
    # uploaded (served from /static/avatars — see main.py's StaticFiles
    # mount). Mutually exclusive in practice — setting one clears the
    # other — but both columns exist so the client always knows which
    # kind it's rendering without guessing from the string shape.
    avatar_preset = Column(String, nullable=True)
    avatar_url = Column(String, nullable=True)

    # Free-form status line under the name on the profile header. Same
    # single column whether it came from tapping a preset chip or typing
    # something custom — the client doesn't need to distinguish once it's
    # saved, only offer both ways to set it (see PATCH /profile/me).
    status_text = Column(String, nullable=True)

    # Privacy — who can see each of this account's three shelves (watched,
    # watching now, plan to watch) on the friends screen / friend profile /
    # activity feed. One of "everyone" | "friends" | "nobody" each,
    # independent per shelf so e.g. "watching now" can stay private while
    # "watched" stays open. Defaults to "everyone" — the app ships open by
    # default, someone has to deliberately dial it back. See
    # routers/profile.py::update_me and routers/friends.py's profile/
    # suggested endpoints, which are the only places that read these.
    privacy_watched = Column(String, nullable=False, default="everyone", server_default="everyone")
    privacy_watching = Column(String, nullable=False, default="everyone", server_default="everyone")
    privacy_planned = Column(String, nullable=False, default="everyone", server_default="everyone")
    # Same three-level scheme as the shelves above, but for the
    # "favorite films" shortcut on Profile — who can open this account's
    # favorites (own profile header shortcut, or another account's
    # profile screen). Independent of privacy_watched on purpose: a
    # favorite can be pinned from any shelf, not only `watched` — see
    # WatchlistEntry.is_favorite's own docstring.
    privacy_favorites = Column(String, nullable=False, default="everyone", server_default="everyone")
    # Which one favorite film shows in the Profile header's corner button
    # (see _FavoritesCornerButton in profile_screen.dart) instead of a
    # plain heart+count — a deliberate single pick, not just "whichever
    # was favorited most recently". Both null until the person picks one
    # on the favorite-films screen (POST /profile/favorites/pick); a
    # WatchlistEntry composite key rather than a foreign key since a
    # favorite can be un-favorited/removed without a DB-level cascade
    # needed — routers/profile.py clears these two columns itself
    # whenever that happens to be the current pick.
    top_favorite_media_id = Column(String, nullable=True)
    top_favorite_source = Column(String, nullable=True)

    # The stories-style spotlight row on the Profile header banner — an
    # ordered list of up to 5 favorite movies, each stored as
    # {"media_id": ..., "source": ...}, swiped through like a stories
    # deck instead of showing a single static pick. Supersedes
    # top_favorite_media_id/top_favorite_source above (kept alongside,
    # unused by any new client code, purely so nothing on an old build
    # crashes reading a NULL). Empty list/NULL until the person picks at
    # least one on the favorite-films screen — see POST
    # /profile/favorites/pick and routers/profile.py::set_top_favorites.
    top_favorite_picks = Column(JSON, nullable=True, default=list)

    # Up to 3 achievement ids (see routers/profile.py::get_achievements)
    # this account has chosen to show off — the badge-showcase equivalent
    # of top_favorite_media_id above. Comma-joined rather than a separate
    # table since it's always read/written as one small ordered set, never
    # queried by individual id. NULL/empty means nothing pinned yet — the
    # profile header simply shows no showcase row. Visible on the friend
    # profile screen too (routers/friends.py::get_friend_profile).
    pinned_achievement_ids = Column(String, nullable=True)

    watchlist = relationship("WatchlistEntry", back_populates="user", cascade="all, delete-orphan")
    activity = relationship("ActivityEvent", back_populates="user", cascade="all, delete-orphan")
    diary_entries = relationship("DiaryEntry", back_populates="user", cascade="all, delete-orphan")
    episode_progress = relationship("EpisodeProgress", back_populates="user", cascade="all, delete-orphan")
    lists = relationship("UserList", back_populates="user", cascade="all, delete-orphan")


class WatchlistEntry(Base):
    """
    Stores a snapshot of a UnifiedMedia object at the time the user reacted to it,
    so the library still renders correctly even if the upstream source changes
    or is temporarily unreachable.
    """
    __tablename__ = "watchlist_entries"

    id = Column(String, primary_key=True, default=gen_uuid)
    user_id = Column(String, ForeignKey("users.id"), nullable=False)

    media_id = Column(String, nullable=False)          # id from the source adapter
    media_type = Column(Enum(MediaType), nullable=False)
    source = Column(String, nullable=False)             # which adapter produced this card, e.g. "tmdb"

    title_ru = Column(String, nullable=True)
    title_en = Column(String, nullable=True)
    poster_url = Column(String, nullable=True)
    # Wide still/fanart image, same field MediaItem carries (see
    # MediaItem.backdrop_url) — snapshotted here so the Profile header's
    # stories banner (see mobile's _StoriesBanner/_Slide) can show a real
    # horizontal shot instead of stretching the vertical poster into a
    # wide frame. NULL on any row written before this shipped, or for a
    # source with no backdrop on file — the client falls back to
    # poster_url either way.
    backdrop_url = Column(String, nullable=True)
    year = Column(Integer, nullable=True)
    genres = Column(JSON, default=list)
    rating = Column(Float, nullable=True)
    runtime_minutes = Column(Integer, nullable=True)  # snapshot, for Wrapped hour estimates

    status = Column(Enum(WatchStatus), default=WatchStatus.watch_later, nullable=False)

    # "favorite films" on Profile — set either from the log form (see
    # DiaryEntryCreate.is_favorite) or toggled straight from the title
    # screen (see POST /profile/favorites/toggle). Independent of `status`
    # on purpose: something can be a favorite whether it's watched or
    # still on the watch-later shelf.
    is_favorite = Column(Boolean, default=False, nullable=False)

    # Personal layer added for the diary UI: hearts (1-5), a free-text note,
    # and the most recent watch date. `rating` above stays the *source's*
    # score (TMDB/IMDb-style, shown on the title page) — this is the
    # user's own reaction, shown as hearts on Home/Diary/Profile.
    user_rating = Column(Integer, nullable=True)
    note = Column(String, nullable=True)
    # Mirrors of the most recently logged evening's DiaryEntry.mood_tags /
    # favorite_cast (see log_watched / PATCH /diary/{id} in
    # routers/diary.py), same "snapshot of the latest log" story as
    # user_rating/note just above — so anything reading the title-level
    # shelf (Profile's watched grid, a friend's watched grid) sees the
    # same tags/cast the diary itself would show for that evening,
    # without a second round-trip. Empty on any row logged before this
    # shipped, same as everywhere else this convention is used.
    mood_tags = Column(JSON, default=list)
    favorite_cast = Column(JSON, default=list)
    watched_at = Column(DateTime, nullable=True)

    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    user = relationship("User", back_populates="watchlist")


class DiaryEntry(Base):
    """
    One row per evening logged for movies/games/books/etc — including
    rewatches of the same title. WatchlistEntry stays the *current*
    snapshot (one row per title, used for the watched/plan-to-watch
    shelves); DiaryEntry is the append-only journal behind the Diary tab
    and the "your evenings with this film" timeline on the title screen.

    A **series is the one deliberate exception**: it only ever gets a
    single DiaryEntry row, created the first time any episode of it is
    logged, and updated in place after that as more gets watched — never
    a new row per episode, per season, or even per rewatch (see
    routers/diary.py::log_watched). season/episode hold the *latest*
    episode reached, not "the episode this row represents" — tap the
    diary card to see the actual season/episode breakdown, which comes
    from EpisodeProgress, not from a pile of DiaryEntry rows.
    episodes_watched is a running count of that same EpisodeProgress
    table, kept here as a snapshot so the diary list can show "12
    episodes watched" without a second fetch. runtime_minutes is
    recomputed the same way each update — episodes_watched × the show's
    per-episode runtime — so Wrapped's hour totals stay honest as the
    single row's progress grows, instead of needing N rows to add up.
    Movies/games/books/etc. never set season/episode/episodes_watched —
    one row is already one whole watch there.
    """
    __tablename__ = "diary_entries"

    id = Column(String, primary_key=True, default=gen_uuid)
    user_id = Column(String, ForeignKey("users.id"), nullable=False)

    media_id = Column(String, nullable=False)
    media_type = Column(Enum(MediaType), nullable=False)
    source = Column(String, nullable=False)

    title_ru = Column(String, nullable=True)
    title_en = Column(String, nullable=True)
    poster_url = Column(String, nullable=True)

    # Wide still/fanart image, same snapshot WatchlistEntry.backdrop_url
    # keeps (see that column's own docstring) — powers the Home "on this
    # day" card's wide banner (see mobile's _OnThisDayCard) instead of
    # stretching the vertical poster into a wide frame. NULL on any row
    # written before this shipped, or for a source with no backdrop on
    # file — the client falls back to poster_url either way.
    backdrop_url = Column(String, nullable=True)

    # Set only on a series' single row — the latest season/episode
    # reached, updated in place on every log. Null for movies/games/
    # books/etc. See the class docstring.
    season = Column(Integer, nullable=True)
    episode = Column(Integer, nullable=True)
    # Running count of watched episodes for a series' single row (mirrors
    # EpisodeProgress) — null for movies/games/books/etc. See the class
    # docstring.
    episodes_watched = Column(Integer, nullable=True)

    rating = Column(Integer, nullable=True)   # hearts, 1-10, personal
    note = Column(String, nullable=True)
    mood_tags = Column(JSON, default=list)    # free-form vibe tags, e.g. "cozy night in", "background noise"
    # Up to 3 cast members picked as standouts for this particular
    # evening (see the themed log flows' "who did you love most
    # tonight?" step) — a snapshot list of {person_id, name, photo_url}
    # dicts, same shape as MediaItem.cast entries, so the diary card can
    # render their faces without a second title/person lookup. Empty
    # list when the step was skipped, same convention as mood_tags.
    favorite_cast = Column(JSON, default=list)
    # Snapshot of the linked partner's username at the moment this evening
    # was logged — either set manually ("watched with" toggle on the log
    # form) or automatically when this entry came from marking a
    # co-viewing title watched (routers/partner.py::mark_co_viewing_watched).
    # A snapshot rather than a live lookup so it still reads correctly if
    # the pair later unlinks.
    watched_with_username = Column(String, nullable=True)
    is_rewatch = Column(Integer, default=0)   # 0/1 — set from prior-entry count at write time
    genres = Column(JSON, default=list)       # snapshot, so Wrapped can compute top genres per period
    runtime_minutes = Column(Integer, nullable=True)  # snapshot, for Wrapped hour estimates
    # Snapshot of item.year / item.director at log time (same reasoning as
    # genres/runtime_minutes above) — powers Wrapped's "decade breakdown"
    # and "directors of the year" cards. director is only ever populated
    # when the client had already fetched GET /media/detail (title screen)
    # before logging, same caveat as MediaItem.director itself; null just
    # means that title's director wasn't known at log time, not an error.
    year = Column(Integer, nullable=True)
    director = Column(String, nullable=True)

    watched_at = Column(DateTime, nullable=False, server_default=func.now())
    created_at = Column(DateTime, server_default=func.now())

    user = relationship("User", back_populates="diary_entries")


class UserList(Base):
    """A personal, user-made collection — e.g. "Cozy rainy-day picks" or
    "Games to play with my brother". Deliberately separate from the
    editorial shelves in /feed/collections (TMDB/IGDB curated, no user_id
    at all) — these two concepts share the word "collection" in casual
    speech but nothing else, so the API calls this one "lists" to keep
    them unambiguous in code and endpoints alike.
    """
    __tablename__ = "user_lists"

    id = Column(String, primary_key=True, default=gen_uuid)
    user_id = Column(String, ForeignKey("users.id"), nullable=False, index=True)

    name = Column(String, nullable=False)
    description = Column(String, nullable=True)

    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    user = relationship("User", back_populates="lists")
    items = relationship(
        "UserListItem", back_populates="list",
        cascade="all, delete-orphan", order_by="UserListItem.added_at.desc()",
    )


class UserListItem(Base):
    """One title in one personal list — a snapshot, same reasoning as
    WatchlistEntry: the list still renders correctly even if TMDB/IGDB is
    briefly unreachable or a title later disappears upstream."""
    __tablename__ = "user_list_items"

    id = Column(String, primary_key=True, default=gen_uuid)
    list_id = Column(String, ForeignKey("user_lists.id"), nullable=False, index=True)

    media_id = Column(String, nullable=False)
    media_type = Column(Enum(MediaType), nullable=False)
    source = Column(String, nullable=False)

    title_ru = Column(String, nullable=True)
    title_en = Column(String, nullable=True)
    poster_url = Column(String, nullable=True)
    year = Column(Integer, nullable=True)
    genres = Column(JSON, default=list)
    rating = Column(Float, nullable=True)

    added_at = Column(DateTime, server_default=func.now())

    list = relationship("UserList", back_populates="items")

    __table_args__ = (
        UniqueConstraint("list_id", "source", "media_id", name="uq_user_list_item"),
    )


class ActivityEvent(Base):
    __tablename__ = "activity_events"

    id = Column(String, primary_key=True, default=gen_uuid)
    user_id = Column(String, ForeignKey("users.id"), nullable=False)
    verb = Column(String, nullable=False)          # e.g. "added_to_watchlist", "marked_watched"
    media_title = Column(String, nullable=False)
    media_type = Column(Enum(MediaType), nullable=False)
    created_at = Column(DateTime, server_default=func.now())

    # Added so the friends activity feed can show a real poster and open
    # the actual title (see routers/activity.py) instead of just a line
    # of text — same (media_id, source) pair every other snapshot table
    # in this file already keys on. Nullable because rows written before
    # this column existed have neither; the client just falls back to a
    # plain text row for those (no poster, tapping it does nothing).
    media_id = Column(String, nullable=True)
    source = Column(String, nullable=True)
    poster_url = Column(String, nullable=True)
    # Personal hearts, same scale as whatever wrote them (DiaryEntry.rating
    # / WatchlistEntry.user_rating), snapshotted at the moment this event
    # was logged — only set when the action that produced it had a rating
    # to give (a diary log does; a plain "added to watch later" doesn't).
    # Lets the feed card show a rating without a second round-trip.
    rating = Column(Integer, nullable=True)

    user = relationship("User", back_populates="activity")


class FriendRequestStatus(str, enum.Enum):
    pending = "pending"
    accepted = "accepted"
    declined = "declined"


class FriendRequest(Base):
    """One row per friend request, kept around after it's answered rather
    than turning into a separate "Friendship" row once accepted — an
    `accepted` row *is* the friendship (see routers/friends.py::are_friends
    and list_friends), same one-row-is-the-relationship shape PartnerLink
    already uses for co-viewing pairs. Unfriending just deletes the row;
    declining flips status to `declined` so a fresh request can be sent
    again later without the unique pair constraint fighting it (the old
    declined row is deleted first — see routers/friends.py::send_request).

    Directional (from_user_id -> to_user_id) so "pending" naturally reads
    as "waiting on to_user_id to answer" for either side without a
    separate `direction` field.
    """
    __tablename__ = "friend_requests"

    id = Column(String, primary_key=True, default=gen_uuid)
    from_user_id = Column(String, ForeignKey("users.id"), nullable=False, index=True)
    to_user_id = Column(String, ForeignKey("users.id"), nullable=False, index=True)
    status = Column(Enum(FriendRequestStatus), default=FriendRequestStatus.pending, nullable=False)
    created_at = Column(DateTime, server_default=func.now())
    responded_at = Column(DateTime, nullable=True)

    from_user = relationship("User", foreign_keys=[from_user_id])
    to_user = relationship("User", foreign_keys=[to_user_id])

    __table_args__ = (
        UniqueConstraint("from_user_id", "to_user_id", name="uq_friend_request_pair"),
    )


class EpisodeProgress(Base):
    """One row per episode a user has marked watched for a series. Separate
    from DiaryEntry on purpose — logging "an evening" (with hearts/a note)
    and ticking off "I've seen S2E4" are different actions at different
    granularities; a season can be ticked off in bulk without that meaning
    ten diary entries got written.

    `rating`/`note` are that episode's own lightweight rating — set from
    the episode list, not from the full log ritual (see
    routers/progress.py::rate_episode). They never create a DiaryEntry by
    themselves; the client averages a season's episode ratings into the
    one diary row it logs once every episode in that season is watched
    (see mobile's episode_log_followup.dart::maybeLogCompletedSeason).
    """
    __tablename__ = "episode_progress"

    id = Column(String, primary_key=True, default=gen_uuid)
    user_id = Column(String, ForeignKey("users.id"), nullable=False, index=True)

    media_id = Column(String, nullable=False)
    source = Column(String, nullable=False)
    season = Column(Integer, nullable=False)
    episode = Column(Integer, nullable=False)

    rating = Column(Integer, nullable=True)
    note = Column(String, nullable=True)

    watched_at = Column(DateTime, server_default=func.now())

    user = relationship("User", back_populates="episode_progress")

    __table_args__ = (
        UniqueConstraint(
            "user_id", "source", "media_id", "season", "episode",
            name="uq_episode_progress",
        ),
    )


# ---------------------------------------------------------------------------
# TMDB (and other adapter) response cache — keeps us well inside their API
# rate limits.
#
# Two tiers, matching how the data actually behaves:
#   - CachedTitleDetail: one title's synopsis/genres/runtime/ratings/similar
#     doesn't meaningfully change day to day once TMDB has answered for it,
#     so it's cached forever (no TTL, no background refresh).
#   - CachedFeedSnapshot: collections/discover/movies-feed are genuinely
#     time-varying (today's "premieres", trending charts), but don't need
#     to be fetched more than once a day — every request within a day of
#     the last fetch reads the same cached JSON.
# See app/cache.py for the read/write helpers built on these tables.
# ---------------------------------------------------------------------------

class CachedTitleDetail(Base):
    __tablename__ = "cached_title_details"

    media_id = Column(String, primary_key=True)
    source = Column(String, primary_key=True)
    payload_json = Column(Text, nullable=False)  # serialized MediaDetailOut
    cached_at = Column(DateTime, server_default=func.now())


class CachedEpisodes(Base):
    """A series' season/episode list — same forever-cache shape as
    CachedTitleDetail, just a separate table so the two payload types never
    collide under the same (media_id, source) key."""
    __tablename__ = "cached_episodes"

    media_id = Column(String, primary_key=True)
    source = Column(String, primary_key=True)
    payload_json = Column(Text, nullable=False)  # serialized EpisodesOut
    cached_at = Column(DateTime, server_default=func.now())


class CachedEmbedding(Base):
    """One title's semantic-embedding vector for Ask Teamira's free-text
    matching (app/embeddings.py, used from app/routers/ai.py) — same
    forever-cache shape as CachedTitleDetail, in its own table so a
    384-float vector never collides with or bloats that payload. Keyed
    the same (media_id, source) way, since the text it's derived from
    (title/genres/description) is itself pulled from that same cached
    detail and essentially never changes."""
    __tablename__ = "cached_embeddings"

    media_id = Column(String, primary_key=True)
    source = Column(String, primary_key=True)
    payload_json = Column(Text, nullable=False)  # JSON list[float]
    cached_at = Column(DateTime, server_default=func.now())


class CachedFeedSnapshot(Base):
    __tablename__ = "cached_feed_snapshots"

    cache_key = Column(String, primary_key=True)  # e.g. "feed:collections"
    payload_json = Column(Text, nullable=False)
    cached_at = Column(DateTime, server_default=func.now(), onupdate=func.now())


# ---------------------------------------------------------------------------
# Watch Together, over the network — two accounts, two phones, one shared
# deck. Deliberately *not* built on a persistent friends graph: a session is
# a short-lived pairing keyed by a human-typeable code (like a Watch Party
# PIN), created by one account and joined by exactly one other. No request/
# accept flow, no standing relationship — just "here's a code, type it in".
# The same-phone pass-and-swipe mode in the app keeps working exactly as it
# did; this is an alternate way to reach the same "matches" outcome when the
# two people aren't sharing a screen.
# ---------------------------------------------------------------------------

class TogetherSessionStatus(str, enum.Enum):
    waiting = "waiting"   # code issued, no guest yet
    active = "active"     # guest joined, both swiping
    done = "done"         # either side ended it


class TogetherSession(Base):
    __tablename__ = "together_sessions"

    id = Column(String, primary_key=True, default=gen_uuid)
    code = Column(String, unique=True, index=True, nullable=False)

    owner_id = Column(String, ForeignKey("users.id"), nullable=False)
    guest_id = Column(String, ForeignKey("users.id"), nullable=True)

    type_filter = Column(String, nullable=False, default="all")
    # Genre names (TMDB-style, e.g. "Comedy", "Horror") picked in the setup
    # step. Empty list means no genre narrowing — same "no filter" meaning
    # type_filter's "all" has. Only ever set at creation time, same as
    # type_filter, so both phones swipe through one deck built from one
    # set of filters.
    genres_filter = Column(JSON, default=list)
    status = Column(Enum(TogetherSessionStatus), default=TogetherSessionStatus.waiting, nullable=False)

    # Each side's own "add a match to my personal watch-together list?"
    # choice (Settings > co-viewing) — sent along with create/join so the
    # match-handling code can honor it per participant even though it runs
    # on the server. Defaults to True (today's always-on behavior) so an
    # older client that doesn't send the field yet keeps working exactly
    # as before. Doesn't touch the *shared* co-viewing list on a standing
    # partner link — that one is never gated by this, see
    # _add_match_to_both_lists.
    owner_sync_to_list = Column(Boolean, default=True, nullable=False)
    guest_sync_to_list = Column(Boolean, default=True, nullable=False)

    # A snapshot of the shuffled deck, fixed at creation time, so both
    # phones swipe through titles in the exact same order — matches are
    # keyed on media identity either way, but a shared order is what makes
    # it feel like swiping through the same stack together.
    deck_json = Column(Text, nullable=False)

    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    owner = relationship("User", foreign_keys=[owner_id])
    guest = relationship("User", foreign_keys=[guest_id])
    swipes = relationship(
        "TogetherSwipe", back_populates="session", cascade="all, delete-orphan",
    )


class TogetherSwipe(Base):
    """One person's yes/no on one card, in one session. A match is simply
    both participants having a "yes" row for the same (media_id, source)."""
    __tablename__ = "together_swipes"

    id = Column(String, primary_key=True, default=gen_uuid)
    session_id = Column(String, ForeignKey("together_sessions.id"), nullable=False, index=True)
    user_id = Column(String, ForeignKey("users.id"), nullable=False)

    media_id = Column(String, nullable=False)
    source = Column(String, nullable=False)
    decision = Column(Integer, nullable=False)  # 0/1 — same int-bool convention as is_rewatch

    created_at = Column(DateTime, server_default=func.now())

    session = relationship("TogetherSession", back_populates="swipes")

    __table_args__ = (
        UniqueConstraint(
            "session_id", "user_id", "media_id", "source",
            name="uq_together_swipe",
        ),
    )


# ---------------------------------------------------------------------------
# Partner link — a standing, one-time pairing between two accounts (unlike
# TogetherSession above, which is a fresh code every swipe session). You
# link once with a code, the same way you'd join a Watch Together session,
# and after that the link just sits there quietly until either side removes
# it — no re-pairing needed to send a one-tap "suggest this for tonight".
# ---------------------------------------------------------------------------

class PartnerLinkStatus(str, enum.Enum):
    pending = "pending"   # code issued, nobody's entered it yet
    active = "active"     # someone joined — the link is live


class PartnerLink(Base):
    """A standing co-viewing circle. `owner_id`/`partner_id` are the
    original two seats from when this was strictly a couple — kept
    exactly as before so every 2-person link (the overwhelming common
    case) still works through the old owner/partner columns without
    touching a second table. A third-plus person joining (see
    [PartnerLinkMember] below) is what turns a couple into a company;
    nothing about the first two seats changes when that happens.
    """
    __tablename__ = "partner_links"

    id = Column(String, primary_key=True, default=gen_uuid)
    code = Column(String, unique=True, index=True, nullable=False)

    owner_id = Column(String, ForeignKey("users.id"), nullable=False)
    partner_id = Column(String, ForeignKey("users.id"), nullable=True)

    status = Column(Enum(PartnerLinkStatus), default=PartnerLinkStatus.pending, nullable=False)

    created_at = Column(DateTime, server_default=func.now())

    owner = relationship("User", foreign_keys=[owner_id])
    partner = relationship("User", foreign_keys=[partner_id])
    extra_members = relationship(
        "PartnerLinkMember", back_populates="link", cascade="all, delete-orphan",
    )


class PartnerLinkMember(Base):
    """A third-plus seat on a [PartnerLink] — what makes it a "company"
    (3+) rather than a couple. The first two seats stay on the link's
    own owner_id/partner_id columns (see PartnerLink's docstring for
    why); this table only ever holds member #3 onward, so a plain
    couple never has any rows here at all and every existing
    owner/partner query keeps working untouched. Deliberately no
    "role" beyond membership — a company doesn't have a second-class
    seat, just whoever got there first (owner_id) for the handful of
    things that need exactly one "whose code is this" answer (pairing
    codes, who to reassign when someone leaves — see
    routers/partner.py::unlink_partner).
    """
    __tablename__ = "partner_link_members"

    id = Column(String, primary_key=True, default=gen_uuid)
    link_id = Column(String, ForeignKey("partner_links.id"), nullable=False, index=True)
    user_id = Column(String, ForeignKey("users.id"), nullable=False, index=True)
    joined_at = Column(DateTime, server_default=func.now())

    link = relationship("PartnerLink", back_populates="extra_members")
    user = relationship("User")

    __table_args__ = (
        UniqueConstraint("link_id", "user_id", name="uq_partner_link_member"),
    )


class PartnerLinkInviteStatus(str, enum.Enum):
    pending = "pending"
    accepted = "accepted"
    declined = "declined"


class PartnerLinkInvite(Base):
    """A direct "join my co-viewing circle" invite to one specific
    friend — the alternative to sharing a pairing code, and the only
    way to *add* someone to a circle that already has two people in it
    (a fresh code can only ever start a brand new pending link, which
    is exactly wrong once a couple already exists — see
    routers/partner.py::send_invite). One row per invite, kept around
    after it's answered the same way FriendRequest is: an `accepted`
    row is just history once the membership itself has been written
    onto the link, `declined` lets a fresh invite be sent again later.
    """
    __tablename__ = "partner_link_invites"

    id = Column(String, primary_key=True, default=gen_uuid)
    link_id = Column(String, ForeignKey("partner_links.id"), nullable=False, index=True)
    from_user_id = Column(String, ForeignKey("users.id"), nullable=False)
    to_user_id = Column(String, ForeignKey("users.id"), nullable=False, index=True)
    status = Column(Enum(PartnerLinkInviteStatus), default=PartnerLinkInviteStatus.pending, nullable=False)

    created_at = Column(DateTime, server_default=func.now())
    responded_at = Column(DateTime, nullable=True)

    link = relationship("PartnerLink")
    from_user = relationship("User", foreign_keys=[from_user_id])
    to_user = relationship("User", foreign_keys=[to_user_id])

    __table_args__ = (
        UniqueConstraint("link_id", "to_user_id", name="uq_partner_link_invite"),
    )


class CoViewStatus(str, enum.Enum):
    planned = "planned"   # matched/suggested, not watched together yet
    watched = "watched"   # marked done from the co-viewing screen


class CoViewEntry(Base):
    """One title on a linked pair's shared co-viewing screen. Fed from
    three places: the one-tap "suggest this for tonight" heart, a Watch
    Together match over the network, and a Watch Together match from the
    local pass-the-phone mode — all funnel into this single per-link list
    so "planned together" means the same thing regardless of which of the
    three produced it. Marking one "watched" writes a DiaryEntry for both
    accounts in the link (see routers/partner.py::mark_coview_watched)."""
    __tablename__ = "co_view_entries"

    id = Column(String, primary_key=True, default=gen_uuid)
    link_id = Column(String, ForeignKey("partner_links.id"), nullable=False, index=True)

    media_id = Column(String, nullable=False)
    media_type = Column(Enum(MediaType), nullable=False)
    source = Column(String, nullable=False)

    title_ru = Column(String, nullable=True)
    title_en = Column(String, nullable=True)
    poster_url = Column(String, nullable=True)
    year = Column(Integer, nullable=True)
    genres = Column(JSON, default=list)
    rating = Column(Float, nullable=True)

    status = Column(Enum(CoViewStatus), default=CoViewStatus.planned, nullable=False)
    added_by_id = Column(String, ForeignKey("users.id"), nullable=True)
    watched_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, server_default=func.now())

    # The "plan an evening" ritual's own co-viewing toggle (mobile/lib/
    # widgets/plan_evening_sheet.dart) — when someone plans an evening as
    # watching-together, this is what makes it show up on their partner's
    # side of the shared co-viewing screen too, instead of staying a
    # device-local ticket only they can see (see PlannedEvening's own
    # docstring on the client for that half of the picture). All three
    # nullable, same "backfills as absent" story as every other optional
    # column here: a co-view entry created any other way (the suggest
    # heart, a Watch Together match) simply has no scheduled time, and the
    # co-viewing screen reads that as "planned, whenever."
    scheduled_date = Column(DateTime, nullable=True)  # day precision — see planned_hour/minute for a time
    scheduled_hour = Column(Integer, nullable=True)  # 0-23, local to whoever scheduled it
    scheduled_minute = Column(Integer, nullable=True)  # 0-59

    link = relationship("PartnerLink")
    added_by = relationship("User", foreign_keys=[added_by_id])

    __table_args__ = (
        UniqueConstraint("link_id", "source", "media_id", name="uq_co_view_entry"),
    )


# ---------------------------------------------------------------------------
# Co-viewing vote — a linked pair deciding *which* of the titles either of
# them already means to watch is the one for tonight. By default the deck
# is built entirely from both accounts' own "plan to watch" shelves — see
# routers/co_view_vote.py::_build_vote_pool — but pool_source can also be
# "catalog", which draws from the same whole-app pool Watch Together/GET
# /feed use instead, for whoever actually wants to shuffle through
# something neither of you has queued yet. No code to join, either: an
# active PartnerLink already means there are exactly two participants, so
# starting a round just needs the standing link, the same way the shared
# co-viewing list itself does.
# ---------------------------------------------------------------------------

class CoViewVoteStatus(str, enum.Enum):
    active = "active"  # deck is out, at least one side hasn't finished voting
    done = "done"      # a match was found (winner set), or someone ended it early


class CoViewVoteSession(Base):
    """One shared voting round for a linked pair. At most one active round
    per link at a time — starting a round while one is already active just
    hands back the same session (see start_vote), so both phones land on
    the identical deck instead of racing to create two."""
    __tablename__ = "co_view_vote_sessions"

    id = Column(String, primary_key=True, default=gen_uuid)
    link_id = Column(String, ForeignKey("partner_links.id"), nullable=False, index=True)

    status = Column(Enum(CoViewVoteStatus), default=CoViewVoteStatus.active, nullable=False)

    # Which pool this round's deck was drawn from — "personal" (each
    # side's own plan-to-watch shelf, minus anything already decided),
    # "coview" (the shared co-viewing planned list itself — deciding
    # which of what you've already agreed on to watch tonight), "both"
    # (the union of those two — still only what's queued or agreed
    # between the two of you), or "catalog" (the whole app catalog,
    # unrelated to either shelf). Stored so a poller can show what it's
    # voting through without having to be told separately. See
    # _build_vote_pool.
    pool_source = Column(String, nullable=False, default="personal")

    # A snapshot of the shuffled pool, fixed at creation time — same
    # reasoning as TogetherSession.deck_json: both phones need to vote
    # through titles in the same order for "a match" to feel like landing
    # on the same card, not just the same eventual title.
    deck_json = Column(Text, nullable=False)

    # Set once both sides have voted yes on the same title — the round is
    # done at that point and this is what it landed on.
    winner_source = Column(String, nullable=True)
    winner_media_id = Column(String, nullable=True)

    started_by_id = Column(String, ForeignKey("users.id"), nullable=True)
    created_at = Column(DateTime, server_default=func.now())

    link = relationship("PartnerLink")
    votes = relationship(
        "CoViewVoteCast", back_populates="session", cascade="all, delete-orphan",
    )


class CoViewVoteCast(Base):
    """One person's yes/no on one title, in one round. A match is both
    participants having a "yes" row for the same (media_id, source) —
    identical shape to TogetherSwipe, just scoped to a standing link
    instead of a join-by-code session."""
    __tablename__ = "co_view_vote_casts"

    id = Column(String, primary_key=True, default=gen_uuid)
    session_id = Column(String, ForeignKey("co_view_vote_sessions.id"), nullable=False, index=True)
    user_id = Column(String, ForeignKey("users.id"), nullable=False)

    media_id = Column(String, nullable=False)
    source = Column(String, nullable=False)
    decision = Column(Integer, nullable=False)  # 0/1

    created_at = Column(DateTime, server_default=func.now())

    session = relationship("CoViewVoteSession", back_populates="votes")

    __table_args__ = (
        UniqueConstraint(
            "session_id", "user_id", "media_id", "source",
            name="uq_covote_cast",
        ),
    )


# ---------------------------------------------------------------------------
# Co-viewing poll — the head-to-head "vote it out" method: a small
# shortlist (drawn from the same pool_source concept as a vote round, see
# routers/co_view_poll.py) that everyone in the circle picks one favorite
# from, on a countdown, instead of swiping through the whole deck looking
# for unanimous yes. A tie for the lead doesn't end it — the very same
# session narrows its own candidates_json down to just the tied leaders
# and reopens for a fresh round (round_number ticks up) rather than
# starting over from the full pool, so a runoff is always "from what's
# left", never a brand new draw.
# ---------------------------------------------------------------------------

class CoViewPollStatus(str, enum.Enum):
    active = "active"  # still within its deadline and not everyone's voted
    done = "done"      # a clear leader was found (winner set), or someone ended it early


class CoViewPollSession(Base):
    """One shared poll round for a linked pair/circle. At most one active
    poll per link at a time, same "hand back what's already running"
    reasoning as CoViewVoteSession."""
    __tablename__ = "co_view_poll_sessions"

    id = Column(String, primary_key=True, default=gen_uuid)
    link_id = Column(String, ForeignKey("partner_links.id"), nullable=False, index=True)

    status = Column(Enum(CoViewPollStatus), default=CoViewPollStatus.active, nullable=False)

    # Same pool_source options as a vote round — see _build_vote_pool.
    pool_source = Column(String, nullable=False, default="personal")

    # This round's shortlist. Replaced in place (not appended to) on a
    # runoff — see _resolve_if_needed — so it always reflects exactly
    # what the *current* round_number is voting on.
    candidates_json = Column(Text, nullable=False)
    round_number = Column(Integer, nullable=False, default=1)
    deadline = Column(DateTime, nullable=False)

    winner_source = Column(String, nullable=True)
    winner_media_id = Column(String, nullable=True)

    started_by_id = Column(String, ForeignKey("users.id"), nullable=True)
    created_at = Column(DateTime, server_default=func.now())

    link = relationship("PartnerLink")
    votes = relationship(
        "CoViewPollVote", back_populates="session", cascade="all, delete-orphan",
    )


class CoViewPollVote(Base):
    """One person's pick among the *current* round's candidates, by index
    into candidates_json. Indexed rather than keyed by (source, media_id)
    since a runoff's shortlist is a fresh subset with its own indices —
    votes don't carry over between rounds anyway, they're cleared when a
    runoff starts (see _resolve_if_needed)."""
    __tablename__ = "co_view_poll_votes"

    id = Column(String, primary_key=True, default=gen_uuid)
    session_id = Column(String, ForeignKey("co_view_poll_sessions.id"), nullable=False, index=True)
    user_id = Column(String, ForeignKey("users.id"), nullable=False)
    candidate_index = Column(Integer, nullable=False)

    session = relationship("CoViewPollSession", back_populates="votes")

    __table_args__ = (
        UniqueConstraint("session_id", "user_id", name="uq_co_view_poll_vote"),
    )


class ScrobbleEvent(Base):
    """One incoming event from Plex, Jellyfin, Kodi, or the browser
    extension — logged whether or not it matched anything or ended up
    writing a diary entry. This is the debugging surface for "why didn't
    my Netflix watch show up": without it, a silent mismatch (wrong title
    text scraped, no tmdb id in the webhook, below the watched threshold)
    is completely invisible to the person it happened to.
    """
    __tablename__ = "scrobble_events"

    id = Column(String, primary_key=True, default=gen_uuid)
    user_id = Column(String, ForeignKey("users.id"), nullable=False, index=True)
    integration = Column(String, nullable=False)  # "plex" | "jellyfin" | "kodi" | "netflix" | ...
    raw_title = Column(String, nullable=True)
    matched_media_id = Column(String, nullable=True)  # null if nothing in the catalog matched
    matched_source = Column(String, nullable=True)
    action = Column(String, nullable=False)  # "logged" | "ignored" | "unmatched"
    detail = Column(String, nullable=True)   # short human-readable reason, e.g. "below threshold"
    created_at = Column(DateTime, server_default=func.now())


class AffiliateProvider(Base):
    """One row per streaming provider (Netflix, Disney+, ...), keyed by its
    TMDB provider_id. `deep_link_template` is where the actual money story
    lives: it's a plain format string with a `{title}` placeholder, seeded
    (see app/seed.py) with each provider's own free, non-affiliate search
    URL so the feature works and logs real clicks from day one. Swapping
    in a real affiliate link — an Amazon Associates tag, a JustWatch
    partner deep link, an Impact/CJ/Rakuten tracking URL — later is just an
    UPDATE to this one row; nothing else changes. See
    app/routers/watch.py's module docstring for the full monetization
    picture.
    """
    __tablename__ = "affiliate_providers"

    provider_key = Column(String, primary_key=True)  # TMDB provider_id, as a string
    display_name = Column(String, nullable=False)
    deep_link_template = Column(String, nullable=True)
    is_affiliate = Column(Integer, default=0)  # flips to 1 once deep_link_template actually earns something
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())


class OutboundClick(Base):
    """One tap on a "where to watch" provider. Logged unconditionally,
    whether or not that provider currently earns anything — this is the
    traffic evidence a JustWatch/Amazon/Impact partner application asks
    for ("here's how many people click through to Netflix from our app").
    No user_id: the redirect this comes from is opened in the device's own
    browser, outside the app's authenticated API client, so there's no
    reliable identity to attach here without leaking a token into a plain
    browser link."""
    __tablename__ = "outbound_clicks"

    id = Column(String, primary_key=True, default=gen_uuid)
    media_id = Column(String, nullable=False)
    media_type = Column(Enum(MediaType), nullable=False)
    source = Column(String, nullable=False)
    title = Column(String, nullable=True)
    provider_key = Column(String, nullable=False)
    provider_name = Column(String, nullable=False)
    target_url = Column(String, nullable=False)
    created_at = Column(DateTime, server_default=func.now())


class Suggestion(Base):
    """One title sent from one account to its linked partner — the "I'm
    suggesting this for tonight" tap on a title screen. A snapshot of the
    title, same reasoning as UserListItem/WatchlistEntry: it still renders
    correctly even if the source is briefly unreachable later."""
    __tablename__ = "suggestions"

    id = Column(String, primary_key=True, default=gen_uuid)

    sender_id = Column(String, ForeignKey("users.id"), nullable=False)
    receiver_id = Column(String, ForeignKey("users.id"), nullable=False, index=True)

    media_id = Column(String, nullable=False)
    media_type = Column(Enum(MediaType), nullable=False)
    source = Column(String, nullable=False)

    title_ru = Column(String, nullable=True)
    title_en = Column(String, nullable=True)
    poster_url = Column(String, nullable=True)
    year = Column(Integer, nullable=True)

    seen = Column(Integer, default=0)  # 0/1 — same int-bool convention as is_rewatch

    created_at = Column(DateTime, server_default=func.now())

    sender = relationship("User", foreign_keys=[sender_id])
    receiver = relationship("User", foreign_keys=[receiver_id])


class TeamiraCollection(Base):
    """One hand-curated shelf added through the /teamira/admin/* API — the
    "add picks myself" half of "подборки Teamira". Deliberately separate
    from both `Collection` (TMDB/IGDB/Open Library editorial shelves in
    /feed/collections, no DB row at all) and `UserList` (a *user's own*
    personal list): editorial like those shelves (same for every user,
    no user_id), but hand-authored by us rather than pulled from a
    catalog's own "best of" chart.

    The *other* half of "подборки Teamira" — whole TMDB franchises, e.g.
    Star Wars — deliberately does NOT live in this table. Those are
    defined in code instead, see app/curated_franchises.py: a franchise is
    just a (title, tmdb_collection_id) pair, TMDB already keeps the
    membership current (new films added to a franchise show up on our
    side the next time the cache refreshes, no edit needed on our end),
    and there's no per-title curation decision to make or store — so a
    DB row would just be a copy of what TMDB already tracks. This table
    is only for shelves that TMDB has no grouping for at all (e.g. "Top
    10 Movies of 2020"), where titles genuinely need to be picked one by
    one — see TeamiraCollectionItem below and app/routers/teamira.py's
    admin endpoints for how they get added.
    """
    __tablename__ = "teamira_collections"

    id = Column(String, primary_key=True, default=gen_uuid)
    title = Column(String, nullable=False)
    # English shelf name, same optional-sibling-field pattern as
    # curated_franchises.py's franchise rows / schemas.Collection.title_en:
    # nullable because every shelf existed with only a Russian `title`
    # before this shipped, and the client already falls back to `title`
    # whenever this is unset (see mobile/lib/models/collection.dart's
    # displayTitle) — so nothing else needs to change for old rows to
    # keep working, only newly-authored ones need to set this too.
    title_en = Column(String, nullable=True)
    position = Column(Integer, nullable=False, default=0)

    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    items = relationship(
        "TeamiraCollectionItem", back_populates="collection",
        cascade="all, delete-orphan", order_by="TeamiraCollectionItem.position",
    )


class TeamiraCollectionItem(Base):
    """One title in a hand-curated TeamiraCollection. Only stores a
    catalog id + source + type — not a title/poster snapshot like
    UserListItem/WatchlistEntry do — because this is editorial catalog
    data we resolve fresh through the same forever-cached lookup every
    other title on this app uses (see app/routers/teamira.py's
    _resolve_manual_item), not a per-user reaction that needs to survive
    the source disappearing.

    Started TMDB-only (movie/series), hence the physical column still
    being named `tmdb_id` — kept as-is rather than renamed, since
    SQLite/Postgres RENAME COLUMN isn't a migration pattern this app
    otherwise uses (see main.py's _STARTUP_COLUMN_MIGRATIONS, all
    ADD COLUMN). `media_id` is just a friendlier Python-side name over
    that same column now that a shelf can hold anime/games/books/manga
    too. `source` is nullable for the same reason: every row written
    before this shipped is a TMDB movie/series with no source stored —
    see _resolve_manual_item for where that NULL is read back as "tmdb".
    """
    __tablename__ = "teamira_collection_items"

    id = Column(String, primary_key=True, default=gen_uuid)
    collection_id = Column(String, ForeignKey("teamira_collections.id"), nullable=False, index=True)

    media_id = Column("tmdb_id", String, nullable=False)
    media_type = Column(String, nullable=False)  # "movie" | "series" | "anime" | "game" | "book" | "manga"
    source = Column(String, nullable=True)  # "tmdb" | "igdb" | "google_books" | "shikimori_manga"; NULL == "tmdb"
    position = Column(Integer, nullable=False, default=0)

    added_at = Column(DateTime, server_default=func.now())

    collection = relationship("TeamiraCollection", back_populates="items")

    __table_args__ = (
        # media_type is already source-specific (movie/series/anime only
        # ever come from tmdb; game only from igdb; book/manga only from
        # their own Open Library sources) — so (media_id, media_type)
        # alone still can't collide across sources, no need to add
        # `source` into this constraint.
        UniqueConstraint("collection_id", "tmdb_id", "media_type", name="uq_teamira_collection_item"),
    )
