import enum
import uuid
from datetime import datetime

from sqlalchemy import (
    Column, String, Integer, BigInteger, Float, Boolean, DateTime, Date, ForeignKey, Enum, JSON, Text, func,
    UniqueConstraint, Index,
)
from sqlalchemy.dialects.postgresql import JSONB
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
    # The case-folded form of `username`, kept as its own column with its
    # own unique index rather than relying on a functional index nobody
    # can see from models.py. This is what makes "Anna" and "anna" the
    # same account instead of two — the old code compared usernames
    # case-sensitively at registration but case-INsensitively when
    # sending a friend request (see routers/friends.py::send_request) and
    # when matching invite codes, which meant two accounts could exist
    # that no one could tell apart and only one of which was reachable.
    # Written by app/usernames.py::normalize_username on every write path;
    # never shown to anyone (the display form stays in `username`).
    username_lower = Column(String, unique=True, index=True, nullable=True)
    password_hash = Column(String, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    # --- Account recovery -------------------------------------------------
    # Optional, and deliberately so: this app has always let someone start
    # a diary with nothing but a username, and demanding an address up
    # front would be a worse first run for the people who don't want one.
    # But without it a forgotten password means a permanently lost archive
    # of years of evenings, so the app asks for one (skippably) after
    # signup and everywhere the diary starts to look valuable. Stored
    # case-folded in `email` itself — addresses are matched
    # case-insensitively for the local part too here, which is technically
    # stricter than the RFC but matches what every mail provider actually
    # does and avoids "i typed it with a capital" lockouts.
    #
    # Unverified until a link from PasswordResetToken's sibling flow is
    # clicked (see routers/auth.py) — and password reset deliberately only
    # works for a VERIFIED address, so someone who typos a stranger's
    # address can't hand that stranger their account.
    email = Column(String, unique=True, index=True, nullable=True)
    email_verified = Column(Boolean, nullable=False, default=False, server_default="false")

    # --- Token revocation -------------------------------------------------
    # Bumped whenever every existing session for this account must stop
    # working at once: a password change, an explicit "sign out
    # everywhere", a password reset, or an account deletion request. Every
    # access/refresh token carries the value this was at issue time (see
    # app/security.py's `ver` claim), and app/deps.py rejects any token
    # whose `ver` is behind — so revocation is one integer write, with no
    # denylist table to grow forever and no per-request lookup beyond the
    # user row the request was already going to load.
    token_version = Column(Integer, nullable=False, default=0, server_default="0")

    # --- Deletion (App Store guideline 5.1.1(v), GDPR art. 17, 152-ФЗ) ----
    # Two-phase on purpose. DELETE /auth/account sets `deleted_at` and
    # revokes every token immediately — from that moment the account is
    # gone as far as the app, friends, search, and the activity feed are
    # concerned. The rows themselves are destroyed by the purge job
    # (app/account_deletion.py) once settings.account_purge_after_days
    # have passed, which is what makes "I deleted it by accident last
    # night" recoverable without making "delete my data" a lie. `username`
    # and `email` are released (nulled/renamed) at purge time, not at
    # request time, so a restore has something to restore to.
    deleted_at = Column(DateTime(timezone=True), nullable=True, index=True)
    # Set alongside deleted_at; kept separate so a future "we tried to
    # purge this and something failed" retry has somewhere to record that
    # without moving the user-visible countdown.
    purge_after = Column(DateTime(timezone=True), nullable=True, index=True)

    # --- Moderation (App Store guideline 1.2) -----------------------------
    # Set by an admin acting on a report (see routers/moderation.py). A
    # suspended account can still sign in and read/export its own diary —
    # what it can't do is be seen by or interact with anyone else. Making
    # it a hard sign-in block was considered and rejected: it would mean
    # confiscating someone's personal archive over a UGC complaint, which
    # is a much bigger punishment than the offence and not something an
    # appeal could undo after the fact.
    suspended_at = Column(DateTime(timezone=True), nullable=True)
    suspended_until = Column(DateTime(timezone=True), nullable=True)
    suspension_reason = Column(String, nullable=True)

    # Which version of the EULA this account accepted, and when. Apple
    # requires an agreement where a user acknowledges there's no tolerance
    # for objectionable content or abusive behavior; recording the
    # acceptance is what makes enforcing it defensible later. NULL for
    # every account created before the EULA existed — those are prompted
    # to accept on next launch rather than being locked out.
    eula_version = Column(String, nullable=True)
    eula_accepted_at = Column(DateTime(timezone=True), nullable=True)

    # --- Discoverability --------------------------------------------------
    # "people can find me by my username" — see routers/friends.py::
    # search_users. ON by default (friend search is most of how this app's
    # social half gets used at all), but turning it off makes this account
    # unreachable through search while leaving every existing friendship,
    # and an invite code shared directly, working exactly as before.
    discoverable = Column(Boolean, nullable=False, default=True, server_default="true")

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
    referred_by_id = Column(String, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)

    # Best-effort signup fingerprint captured for EVERY account (not just
    # referred ones — compare to Referral.ip_at_signup, which only exists
    # for accounts that came in through the invite-link flow). Backs the
    # promo-code self-dealing check in routers/premium.py::purchase: a
    # PromoCode is meant to be shared publicly with an entire audience
    # (see models.PromoCode's own docstring), so redemption itself stays
    # open to anyone — but two accounts sharing a signup IP is the same
    # "looks like one person working the program twice" signal
    # create_referral_for_signup already uses, and here it gates whether
    # the code OWNER gets paid, not whether the code works. NULL for
    # accounts created before this column existed; nothing retroactively
    # backfilled.
    signup_ip = Column(String, nullable=True)

    # Editable profile identity — deliberately separate from `username`
    # (the login handle friend search/requests key off — see
    # routers/friends.py). NULL means "never set one", the client falls
    # back to showing `username` wherever display_name would go.
    display_name = Column(String, nullable=True)

    # An actual account flag, gated behind the normal JWT login like
    # everything else, rather than a single shared secret header
    # everyone with .env access shared (see app/deps.py::
    # require_admin_user, which this backs, and
    # migrations/versions/<rev>_user_is_admin.py). Nobody starts admin;
    # see scripts/grant_admin.py for how the first one gets set.
    is_admin = Column(Boolean, nullable=False, default=False, server_default="false")

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
    # Up to 3 + bonus_pin_slots achievement ids (see
    # routers/profile.py::get_achievements) this account has chosen to
    # show off — the badge-showcase equivalent of top_favorite_media_id
    # above. Comma-joined rather than a separate table since it's always
    # read/written as one small ordered set, never queried by individual
    # id. NULL/empty means nothing pinned yet — the profile header simply
    # shows no showcase row. Visible on the friend profile screen too
    # (routers/friends.py::get_friend_profile).
    pinned_achievement_ids = Column(String, nullable=True)
    # Extra showcase slots bought with sincerity points, on top of the
    # free 3 — see app/sincerity.py::spend_pin_slot and
    # routers/profile.py::buy_pin_slot. Capped at
    # sincerity.MAX_BONUS_PIN_SLOTS; never decremented on its own (a
    # bought slot is permanent, same as debt_settled's exemption never
    # reverting).
    bonus_pin_slots = Column(Integer, nullable=False, default=0, server_default="0")

    # "Sincerity points" (see app/sincerity.py) — a running total that
    # now genuinely buys a handful of small, real things (see that
    # module's own docstring for the reversal from this column's
    # original "purely reflective, never gated" design). Denormalized
    # onto the user row rather than always summed from
    # SincerityTransaction below, the same tradeoff as
    # UserPremiumState-style denormalized fields elsewhere in this file:
    # every screen that shows the balance (profile badge, settings) reads
    # this one column instead of aggregating the whole ledger each time.
    # app/sincerity.py::record_transaction is the only code path allowed
    # to change it — always alongside inserting the matching
    # SincerityTransaction row in the same commit, so the column and the
    # ledger can never drift apart.
    sincerity_balance = Column(Integer, nullable=False, default=0, server_default="0")
    # Lifetime total ever earned (every positive-delta SincerityTransaction,
    # summed as it's written — see app/sincerity.py::record_transaction).
    # Deliberately never decreases when the balance above is spent: this is
    # what the level ring in the merged Sincerity screen is computed from
    # (app/sincerity.py::compute_level), so buying a pin slot or staking a
    # recommendation can never knock someone back down a level the way
    # reading the *balance* for that would. sincerity_balance is "what you
    # can spend right now"; this is "how far you've come, ever".
    lifetime_sincerity_earned = Column(Integer, nullable=False, default=0, server_default="0")
    # High-water mark of this account's current daily streak (see
    # app/streaks.py::current_streak) already paid out via
    # SincerityReason.streak_milestone — see app/sincerity.py::
    # earn_streak_progress. Only ever moves up: a broken streak that
    # starts over from day 1 doesn't claw back points for days already
    # paid for, it just stops earning new ones until it passes this mark
    # again.
    streak_sincerity_award_days = Column(Integer, nullable=False, default=0, server_default="0")
    # Off by default — this number is a private, personal thing (see the
    # settings screen's own privacy section) until the person explicitly
    # decides it's something friends should see on their profile. Purely
    # a display toggle: it never changes how the balance is earned or
    # spent, only whether GET /friends/profile includes it for others.
    sincerity_visible_to_friends = Column(Boolean, nullable=False, default=False, server_default="false")

    # Per-category push opt-outs — see app/push.py::PushService.send_to_user,
    # the only code path that reads this. Keys are "friend_activity",
    # "partner_activity", "matches", "level_ups", "streak_reminders",
    # "memories" (see PushCategory in app/push.py for the authoritative
    # list); a missing key means "on" (opt-out model — see the settings
    # screen's own copy on why: someone has to actively decide these
    # aren't for them, the same default direction as privacy_watched
    # above, just the opposite value, because an unsent push has no
    # downside for anyone but this app's own re-engagement numbers, while
    # an unwanted-default-private profile has a real downside for the
    # person who forgot to open it). NULL (never touched
    # PATCH /push/preferences) is exactly equivalent to `{}` — both mean
    # "everything on" — so there's nothing to migrate/backfill for
    # existing rows.
    notification_prefs = Column(JSON, nullable=True)

    watchlist = relationship("WatchlistEntry", back_populates="user", cascade="all, delete-orphan", passive_deletes=True)
    activity = relationship("ActivityEvent", back_populates="user", cascade="all, delete-orphan", passive_deletes=True)
    diary_entries = relationship("DiaryEntry", back_populates="user", cascade="all, delete-orphan", passive_deletes=True)
    episode_progress = relationship("EpisodeProgress", back_populates="user", cascade="all, delete-orphan", passive_deletes=True)
    reading_progress = relationship("ReadingProgress", back_populates="user", cascade="all, delete-orphan", passive_deletes=True)
    lists = relationship("UserList", back_populates="user", cascade="all, delete-orphan", passive_deletes=True)
    sincerity_transactions = relationship(
        "SincerityTransaction", back_populates="user", cascade="all, delete-orphan", passive_deletes=True
    )


class WatchlistEntry(Base):
    """
    Stores a snapshot of a UnifiedMedia object at the time the user reacted to it,
    so the library still renders correctly even if the upstream source changes
    or is temporarily unreachable.
    """
    __tablename__ = "watchlist_entries"

    id = Column(String, primary_key=True, default=gen_uuid)
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)

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
    # Only ever set alongside status -> dropped (see routers/watchlist.py
    # ::drop_entry) — the honest one-line "why" that sincerity.py's
    # earn_honest_drop requires before it awards anything for a
    # mid-watch drop. Left null for a watch_later item closed via
    # "not for me" instead (that's earn_closed_gestalt, which doesn't
    # need a reason — see that function's own docstring) and for every
    # other status, including a plain `watched`.
    drop_reason = Column(String, nullable=True)
    # Set once by app/sincerity.py::spend_debt_settlement — a one-time,
    # flat-fee purchase that means "this item never gets charged
    # stale_debt again" (see apply_stale_planned_decay_for_user, whose
    # query filters this column out). Never reset back to False by
    # anything: leaving the item on watch_later after settling it is the
    # whole point (you paid to stop the bleed, not to be pushed off the
    # shelf), and a later re-add after it's watched/dropped just creates
    # a fresh row anyway.
    debt_exempt = Column(Boolean, nullable=False, default=False, server_default="false")
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
    watched_at = Column(DateTime(timezone=True), nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    user = relationship("User", back_populates="watchlist")

    __table_args__ = (
        # Every shelf read (watched/plan-to-watch/watching-now, a
        # friend's profile grid) is `filter(user_id == ...).order_by(
        # updated_at.desc())` — see routers/profile.py, routers/friends.py.
        # A composite index with user_id leading covers a bare
        # user_id-only filter too (leftmost-prefix rule), so this
        # replaces the single-column index this table never had rather
        # than sitting alongside one.
        Index("ix_watchlist_entries_user_id_updated_at", "user_id", "updated_at"),
    )


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
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)

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

    # --- Shared (couple/company) diary ------------------------------------
    # Which co-viewing circle this evening also belongs to, if any — see
    # app/routers/shared_diary.py. The shared diary is deliberately NOT a
    # second copy of the row: it's the same personal DiaryEntry, tagged
    # with the link it's visible on. That way editing a rating/note in
    # your own diary updates what your partner sees, deleting it removes
    # it from both, and there's no sync job that can drift.
    #
    # NULL is the normal state for anyone without a link, and also for
    # someone who turned "write my own evenings into our diary" off (see
    # models.PartnerPrefs.auto_share_logs) — that setting is read once, at
    # log time, and decides whether this column gets filled. Flipping the
    # setting later never retroactively un-shares (or shares) old
    # evenings; the shared diary screen has its own explicit per-entry
    # share/unshare action for that.
    #
    # Deliberately no `ondelete` here even though the rest of this table
    # has none either — see the audit note; when cascade rules are added
    # project-wide this one wants SET NULL, not CASCADE: unlinking a
    # couple must not delete anybody's personal diary.
    shared_link_id = Column(String, ForeignKey("partner_links.id", ondelete="SET NULL"), nullable=True, index=True)
    # 0/1 — whether this specific evening was actually watched *together*
    # (came from the co-viewing screen's "watched" button, or the log
    # form's "watched with" toggle) versus merely shared into the couple's
    # diary afterwards. The shared diary renders these differently: a
    # together-watch shows one card with both people's ratings side by
    # side, a shared solo watch shows one person's card with a quiet
    # "watched alone" marker.
    watched_together = Column(Integer, default=0, server_default="0")

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
    # ISO-3166-1 alpha-2 country of origin, snapshotted at log time the
    # same way genres/year/director are. Powers the "films from N
    # different countries" challenges (see app/challenges.py) without
    # needing a catalog round-trip per diary row at challenge-computation
    # time.
    #
    # Only GET /media/detail ever populates MediaItem.country, so a title
    # logged straight from search wouldn't have one — routers/diary.py::
    # log_watched therefore falls back to the *already-cached* static
    # title detail (app/cache.py::get_static_title) before giving up, which
    # costs one indexed local SELECT and no network. NULL means "we never
    # found out", not "no country" — challenges count distinct non-null
    # values and say so in their caption.
    country = Column(String, nullable=True)

    watched_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User", back_populates="diary_entries")

    __table_args__ = (
        # Same reasoning as WatchlistEntry.__table_args__ above — the
        # diary list, Wrapped, and every "this title's evenings" lookup
        # filter on user_id and sort by watched_at (see routers/diary.py,
        # routers/profile.py). This table has no other index at all
        # right now, so this is the first one, not an addition.
        Index("ix_diary_entries_user_id_watched_at", "user_id", "watched_at"),
    )


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
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)

    name = Column(String, nullable=False)
    description = Column(String, nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    user = relationship("User", back_populates="lists")
    items = relationship(
        "UserListItem", back_populates="list",
        cascade="all, delete-orphan", passive_deletes=True, order_by="UserListItem.added_at.desc()",
    )


class UserListItem(Base):
    """One title in one personal list — a snapshot, same reasoning as
    WatchlistEntry: the list still renders correctly even if TMDB/IGDB is
    briefly unreachable or a title later disappears upstream."""
    __tablename__ = "user_list_items"

    id = Column(String, primary_key=True, default=gen_uuid)
    list_id = Column(String, ForeignKey("user_lists.id", ondelete="CASCADE"), nullable=False, index=True)

    media_id = Column(String, nullable=False)
    media_type = Column(Enum(MediaType), nullable=False)
    source = Column(String, nullable=False)

    title_ru = Column(String, nullable=True)
    title_en = Column(String, nullable=True)
    poster_url = Column(String, nullable=True)
    year = Column(Integer, nullable=True)
    genres = Column(JSON, default=list)
    rating = Column(Float, nullable=True)

    added_at = Column(DateTime(timezone=True), server_default=func.now())

    list = relationship("UserList", back_populates="items")

    __table_args__ = (
        UniqueConstraint("list_id", "source", "media_id", name="uq_user_list_item"),
    )


class ActivityEvent(Base):
    __tablename__ = "activity_events"

    id = Column(String, primary_key=True, default=gen_uuid)
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    verb = Column(String, nullable=False)          # e.g. "added_to_watchlist", "marked_watched"
    media_title = Column(String, nullable=False)
    media_type = Column(Enum(MediaType), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

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

    __table_args__ = (
        # Same reasoning as WatchlistEntry/DiaryEntry above — every read
        # here (your own activity, a friend's, the aggregated friends
        # feed via user_id.in_(...)) filters on user_id and sorts by
        # created_at (see routers/activity.py, routers/friends.py). A
        # user_id-leading composite index still serves the .in_() form
        # fine — it's just multiple leftmost-prefix lookups under the hood.
        Index("ix_activity_events_user_id_created_at", "user_id", "created_at"),
    )


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
    from_user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    to_user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    status = Column(Enum(FriendRequestStatus), default=FriendRequestStatus.pending, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    responded_at = Column(DateTime(timezone=True), nullable=True)

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
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)

    media_id = Column(String, nullable=False)
    source = Column(String, nullable=False)
    season = Column(Integer, nullable=False)
    episode = Column(Integer, nullable=False)

    rating = Column(Integer, nullable=True)
    note = Column(String, nullable=True)

    watched_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User", back_populates="episode_progress")

    __table_args__ = (
        UniqueConstraint(
            "user_id", "source", "media_id", "season", "episode",
            name="uq_episode_progress",
        ),
    )


class ReadingProgress(Base):
    """Where a user is in one book or manga: the current volume, chapter
    and/or page. The reading counterpart of EpisodeProgress, but one row per
    TITLE rather than one per episode — a book has no per-page "watched"
    state worth storing, just "I'm on page 212".

    Deliberately holds no totals: how many volumes/chapters/pages a title has
    is catalog data that can change (an ongoing manga gains volumes), and the
    client already has it on the card. It also never touches WatchlistEntry
    or the diary — moving a bookmark is not logging an evening, and the
    sincerity/stale-debt rules hang off those, not off this. Finishing is the
    client's prompt (see mobile's reading_tracker.dart), not a server rule.

    Any of the three counters may be NULL ("not tracking that"); a row with
    all three empty is deleted rather than kept (see
    routers/progress.py::set_reading_progress).
    """
    __tablename__ = "reading_progress"

    id = Column(String, primary_key=True, default=gen_uuid)
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)

    media_id = Column(String, nullable=False)
    source = Column(String, nullable=False)

    volume = Column(Integer, nullable=True)
    chapter = Column(Integer, nullable=True)
    page = Column(Integer, nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    user = relationship("User", back_populates="reading_progress")

    __table_args__ = (
        UniqueConstraint("user_id", "source", "media_id", name="uq_reading_progress"),
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
    cached_at = Column(DateTime(timezone=True), server_default=func.now())


class CachedEpisodes(Base):
    """A series' season/episode list — same forever-cache shape as
    CachedTitleDetail, just a separate table so the two payload types never
    collide under the same (media_id, source) key."""
    __tablename__ = "cached_episodes"

    media_id = Column(String, primary_key=True)
    source = Column(String, primary_key=True)
    payload_json = Column(Text, nullable=False)  # serialized EpisodesOut
    cached_at = Column(DateTime(timezone=True), server_default=func.now())


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
    cached_at = Column(DateTime(timezone=True), server_default=func.now())


class CachedFeedSnapshot(Base):
    __tablename__ = "cached_feed_snapshots"

    cache_key = Column(String, primary_key=True)  # e.g. "feed:collections"
    payload_json = Column(Text, nullable=False)
    cached_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


# ---------------------------------------------------------------------------
# Backs rate_limit.py's RateLimiter — a fixed window (see that module's own
# docstring for the "why fixed, not sliding" trade-off) of hit counts per
# (limiter name, caller key, window). Living in Postgres instead of a
# per-process dict is the whole point: every uvicorn worker and every
# replica behind a load balancer reads and writes the *same* row for a
# given key, so the limit is actually the limit — not (limit × worker
# count) — regardless of how many processes this backend is running as.
# ---------------------------------------------------------------------------

class RateLimitHit(Base):
    __tablename__ = "rate_limit_hits"

    limiter = Column(String, primary_key=True)       # e.g. "login", "ai_ask"
    key = Column(String, primary_key=True)            # IP address or user id
    window_start = Column(Integer, primary_key=True)  # epoch seconds, floored to the window
    count = Column(Integer, nullable=False, default=0)


# ---------------------------------------------------------------------------
# Product analytics (see routers/analytics.py and docs/analytics.md).
#
# One row per thing that happened in the mobile app: a screen was opened,
# an evening was logged, a setting was changed. Written in batches by
# POST /analytics/events, read by scripts/analytics_report.py and (through
# a read-only database role) by Metabase.
#
# Deliberately NOT a foreign key to `users`: this table takes a lot of
# inserts and its rows are meant to be cheap and disposable. Erasure is
# done explicitly instead — account_deletion.purge_user deletes every row
# carrying the account's user_id *and* every row from any device that
# account ever signed in on, and the retention sweep deletes by age.
#
# What is never stored: titles, notes, search text, e-mail addresses,
# IP addresses. `props` carries small, closed-vocabulary facts (a media
# type, a count, a boolean) — see routers/analytics.py::_clean_props for
# the rules enforced on the way in.
# ---------------------------------------------------------------------------

class AnalyticsEvent(Base):
    __tablename__ = "analytics_events"

    # BigInteger on Postgres (this table will pass 2^31 rows long before
    # anything else here does); plain Integer elsewhere, because SQLite
    # only autoincrements an INTEGER PRIMARY KEY.
    id = Column(BigInteger().with_variant(Integer, "sqlite"), primary_key=True, autoincrement=True)
    # Random, generated on the device when the event happens. The unique
    # index is what makes a retried batch (the phone got no answer, so it
    # sent the same events again) harmless instead of double-counted.
    event_id = Column(String(40), nullable=False, unique=True)
    # When it happened, per the device's clock — clamped on the way in.
    ts = Column(DateTime(timezone=True), nullable=False)
    received_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())
    # Random per install (reset on reinstall / when the person opts out).
    # The unit "active devices" is counted in.
    anon_id = Column(String(40), nullable=False)
    # Only when the request carried a valid access token for a live account.
    user_id = Column(String, nullable=True)
    session_id = Column(String(40), nullable=False)
    name = Column(String(64), nullable=False)
    # Set for `screen_view`: which screen/sheet. NULL for everything else.
    screen = Column(String(80), nullable=True)
    props = Column(JSON().with_variant(JSONB(), "postgresql"), nullable=True)
    platform = Column(String(16), nullable=True)      # android / iOS / ...
    app_version = Column(String(32), nullable=True)
    build = Column(String(8), nullable=True)          # debug / profile / release
    locale = Column(String(8), nullable=True)         # ru / en

    __table_args__ = (
        Index("ix_analytics_events_ts", "ts"),
        Index("ix_analytics_events_name_ts", "name", "ts"),
        Index("ix_analytics_events_anon_ts", "anon_id", "ts"),
        Index("ix_analytics_events_user_id", "user_id"),
    )


# ---------------------------------------------------------------------------
# Premium subscription state (see routers/premium.py) — lives here now
# instead of only in the mobile app's own local SharedPreferences (see
# PremiumService's old docstring in the mobile app, kept for history).
# That used to mean a subscription bought on one device was invisible on
# a second device signed into the same account, and vanished outright on
# reinstall — this table is what makes the account, not the phone, the
# thing that's actually premium. Still NOT backed by a real payment
# processor or IAP receipt validation (see routers/premium.py's own
# docstring) — that's a separate, bigger project — this only fixes
# *where the state of truth lives*, not how it gets set in the first
# place.
# ---------------------------------------------------------------------------

class PremiumPlanKind(str, enum.Enum):
    individual = "individual"
    couple = "couple"
    # Up to four people (the payer plus three more) in one co-viewing
    # circle — "семья / друзья" on the paywall. Member and value are the
    # same string on purpose: SQLAlchemy stores an Enum's *name*, and the
    # Postgres label added by migration a3d6c8f1e572 is the value, so a
    # name that differs from its value would be a label the column can't
    # write.
    family = "family"


class PremiumDuration(str, enum.Enum):
    month = "month"
    # Kept for backward compatibility with historical purchase/gift rows
    # only — no longer offered as a purchasable option (see
    # PremiumScreen/GiftPremiumScreen on the mobile side, which now list
    # three_months instead as the mid-length tier). Never remove a value
    # a real row might already reference; see three_months's own comment
    # on why the replacement is additive rather than a rename.
    six_months = "sixMonths"
    # Replaces six_months as the mid-length option (product decision:
    # a shorter, lower-commitment middle tier reads better between a
    # single month and a full year than six months did — see
    # migrations/versions for the ADD VALUE migration that introduced
    # this without touching six_months's existing rows).
    three_months = "threeMonths"
    year = "year"


class UserPremiumState(Base):
    __tablename__ = "user_premium_state"

    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    is_premium = Column(Boolean, nullable=False, default=False)
    plan_kind = Column(Enum(PremiumPlanKind), nullable=True)
    plan_duration = Column(Enum(PremiumDuration), nullable=True)
    purchased_at = Column(DateTime(timezone=True), nullable=True)

    # Mirrors PremiumService's old local-only "3 free asks a month"
    # counter, now the authoritative copy. ai_asks_month is a "YYYY-M"
    # bucket (see routers/premium.py::_current_month_key) — the counter
    # resets whenever the stored bucket no longer matches the current
    # one, same reset-on-read shape the mobile-only version always used.
    ai_asks_used = Column(Integer, nullable=False, default=0)
    ai_asks_month = Column(String, nullable=True)

    # Bonus days granted by the referral program (see models.Referral /
    # ReferralReward and routers/referrals.py) live here, as a plain
    # expiry timestamp, rather than as a separate ledger the client
    # would need to add up itself. `is_premium` above stays exactly what
    # it always was — the flag a real purchase flips, with no expiry
    # logic of its own (see this table's own module docstring: there's
    # still no real billing/IAP behind it, so a purchase currently never
    # lapses). `premium_expires_at` is additive on top of that: someone
    # who has never purchased anything is premium only while
    # `premium_expires_at` is in the future; someone who *has* purchased
    # is already premium regardless, and referral days just sit banked
    # here for whenever that changes. See _is_premium_now() in
    # routers/premium.py for the exact combination.
    premium_expires_at = Column(DateTime(timezone=True), nullable=True)

    # Set the moment this account starts its one-time free trial (see
    # routers/premium.py::start_trial) and never cleared afterward —
    # its only job is to answer "has this account ever had a trial?",
    # so a lapsed trial can't be restarted by waiting it out. A trial
    # grant itself rides on premium_expires_at, same mechanism as a
    # referral bonus (see grant_premium_days) — there's no separate
    # ledger for "how much of the grant was trial vs. referral", since
    # both are just "premium until this timestamp" from the account's
    # point of view.
    trial_started_at = Column(DateTime(timezone=True), nullable=True)

    # Progress of the "your free period is ending" reminder series (see
    # app/trial.py): 0 = nothing sent yet, 1 = "ends soon", 2 = "last
    # hours", 3 = the one post-expiry win-back. Only ever moves forward,
    # and only after a push was actually delivered to at least one
    # device, so a user with no token / push switched off is retried
    # (harmlessly) until the window for that stage closes. The in-app
    # half of the series is client-side and doesn't depend on this.
    trial_reminder_stage = Column(Integer, nullable=False, default=0, server_default="0")
    trial_reminder_sent_at = Column(DateTime(timezone=True), nullable=True)

    # Cancel / pause / win-back (see app/subscription.py for the rules).
    #
    # There is still no payment processor behind a purchase (see
    # routers/premium.py's module docstring), so a purchase has no
    # renewal date of its own. `purchased_at` plus the plan length, rolled
    # forward in whole periods, is the stand-in for "paid until" — good
    # enough to give cancel and pause a real moment to take effect, and
    # the one place to swap for the store's own date once billing exists.
    #
    # `cancel_effective_at`: set when the person cancels, the end of the
    # period they already have. Premium keeps working until then (the flag
    # `is_premium` is never flipped — the purchase is judged through
    # subscription.purchase_active()), and after it the win-back window
    # opens. Cleared by resuming (undo cancel) or by buying again.
    cancelled_at = Column(DateTime(timezone=True), nullable=True)
    cancel_effective_at = Column(DateTime(timezone=True), nullable=True)
    # A pause suspends the purchase's premium until `paused_until` and
    # pushes the renewal grid out by the same time (the month is free).
    # `pause_used_at` is what the cooldown between two pauses is measured
    # from; it survives resume so pause can't be looped.
    paused_at = Column(DateTime(timezone=True), nullable=True)
    paused_until = Column(DateTime(timezone=True), nullable=True)
    pause_used_at = Column(DateTime(timezone=True), nullable=True)
    # One personal win-back discount per account, ever: set the moment a
    # purchase redeems it. The offer itself is derived, never stored.
    winback_used_at = Column(DateTime(timezone=True), nullable=True)
    # Push bookkeeping, one per message, so the hourly cron sends each
    # at most once: the win-back offer, and "your pause is ending".
    winback_push_sent_at = Column(DateTime(timezone=True), nullable=True)
    pause_ending_push_sent_at = Column(DateTime(timezone=True), nullable=True)


class PremiumSeat(Base):
    """One person a purchased shared plan (couple / family) has been
    bound to — the plan's payer on one side, the covered person on the
    other, and *when* the binding was made.

    Coverage itself is never stored: whether a person is covered right
    now is derived on every read from "is the payer's purchase still
    active, and does the circle still fit the plan" (see routers/
    premium.py::_seat_covers). This table only remembers who took which
    seat and since when, so the seats can't be rotated between strangers
    faster than SEAT_REASSIGN_COOLDOWN — otherwise one plan could be
    rented out to a new person every day.

    The number of rows per payer never exceeds the plan's seats minus
    the payer's own (1 for a couple, 3 for a family). Both ends cascade:
    a deleted holder frees the seat at once, a deleted payer takes their
    seats with them. The (payer, holder) pair is unique, so two devices
    racing to claim the same seat can't leave two rows for one person.
    """
    __tablename__ = "premium_seats"
    __table_args__ = (
        UniqueConstraint("payer_id", "holder_id", name="uq_premium_seat_payer_holder"),
    )

    id = Column(String, primary_key=True, default=gen_uuid)
    payer_id = Column(
        String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True,
    )
    holder_id = Column(
        String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True,
    )
    assigned_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())


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

    owner_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    guest_id = Column(String, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)

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

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    owner = relationship("User", foreign_keys=[owner_id])
    guest = relationship("User", foreign_keys=[guest_id])
    swipes = relationship(
        "TogetherSwipe", back_populates="session", cascade="all, delete-orphan", passive_deletes=True,
    )


class TogetherSwipe(Base):
    """One person's yes/no on one card, in one session. A match is simply
    both participants having a "yes" row for the same (media_id, source)."""
    __tablename__ = "together_swipes"

    id = Column(String, primary_key=True, default=gen_uuid)
    session_id = Column(String, ForeignKey("together_sessions.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)

    media_id = Column(String, nullable=False)
    source = Column(String, nullable=False)
    decision = Column(Integer, nullable=False)  # 0/1 — same int-bool convention as is_rewatch

    created_at = Column(DateTime(timezone=True), server_default=func.now())

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

    # Indexed on both — routers/partner.py's _active_link (the "who's my
    # partner" check called from routers/co_view_vote.py, together.py,
    # etc.) filters `owner_id == user_id OR partner_id == user_id` on
    # every call, with no other column to lean on the way
    # WatchlistEntry/DiaryEntry/ActivityEvent's own composite indexes do
    # (see those __table_args__) — this table doesn't have one shared
    # secondary sort column the same way, and an OR across two columns
    # can't share a single composite index the way an AND can, so two
    # single-column indexes (letting Postgres BitmapOr them together)
    # is the right shape here instead.
    owner_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    partner_id = Column(String, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)

    status = Column(Enum(PartnerLinkStatus), default=PartnerLinkStatus.pending, nullable=False)

    created_at = Column(DateTime(timezone=True), server_default=func.now())

    owner = relationship("User", foreign_keys=[owner_id])
    partner = relationship("User", foreign_keys=[partner_id])
    extra_members = relationship(
        "PartnerLinkMember", back_populates="link", cascade="all, delete-orphan", passive_deletes=True,
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
    link_id = Column(String, ForeignKey("partner_links.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    joined_at = Column(DateTime(timezone=True), server_default=func.now())

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
    link_id = Column(String, ForeignKey("partner_links.id", ondelete="CASCADE"), nullable=False, index=True)
    from_user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    to_user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    status = Column(Enum(PartnerLinkInviteStatus), default=PartnerLinkInviteStatus.pending, nullable=False)

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    responded_at = Column(DateTime(timezone=True), nullable=True)

    link = relationship("PartnerLink")
    from_user = relationship("User", foreign_keys=[from_user_id])
    to_user = relationship("User", foreign_keys=[to_user_id])

    __table_args__ = (
        UniqueConstraint("link_id", "to_user_id", name="uq_partner_link_invite"),
    )


class PartnerPrefs(Base):
    """One person's own settings *for one circle they're in* — not a
    setting on the circle itself. Two people in the same couple can
    disagree about all of these, and each one only ever governs their own
    rows: if you turn `auto_share_logs` off, your evenings stop appearing
    in the shared diary, your partner's keep appearing in it for you.

    Deliberately per-(user, link) rather than a plain column on `users`:
    someone can leave one circle and join another (or, for a company, be
    in a different circle than they were last year), and "don't share my
    evenings with *these* people" shouldn't silently carry over to a
    different set of people. Created lazily with defaults on first read —
    see app/routers/shared_diary.py::get_prefs — so nobody has a row until
    they've either opened the settings or logged something.
    """
    __tablename__ = "partner_prefs"

    id = Column(String, primary_key=True, default=gen_uuid)
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    link_id = Column(String, ForeignKey("partner_links.id", ondelete="CASCADE"), nullable=False, index=True)

    # "Записывать мои просмотры в общий дневник" — the one the product
    # brief calls out by name. ON by default: a shared diary that starts
    # empty and requires a settings trip to fill reads as broken, and the
    # off switch is one tap away in the same place people go looking for
    # it. Evenings watched *together* are exempt and always land in the
    # shared diary regardless — see app/routers/shared_diary.py::
    # shared_link_for_log; hiding half of an evening you demonstrably
    # spent with someone isn't privacy, it's a bug from their side.
    auto_share_logs = Column(Boolean, nullable=False, default=True, server_default="true")
    # Whether the number next to your name on a shared card is visible.
    # ON by default — the ratings are most of the point of a shared diary
    # ("ты поставил 6?!"). Off hides only the score; the entry itself
    # still shows.
    share_ratings = Column(Boolean, nullable=False, default=True, server_default="true")
    # Your written note on an evening. OFF by default, unlike the two
    # above: a diary note is the most personal thing in this app, and
    # opting *in* to showing it is the right default even inside a couple.
    share_notes = Column(Boolean, nullable=False, default=False, server_default="false")

    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User")
    link = relationship("PartnerLink")

    __table_args__ = (
        UniqueConstraint("user_id", "link_id", name="uq_partner_prefs"),
    )


class ChallengeProgress(Base):
    """Per-person state for one challenge in one period — see
    app/challenges.py for the catalog itself and how progress is
    computed.

    This table stores as little as possible on purpose. Current progress
    is NOT kept here: it's recomputed from the person's own DiaryEntry
    rows every time challenges are read, the same way achievements and
    levels already are (see routers/profile.py's own note on why). A
    stored counter would be a second source of truth that drifts the
    moment someone edits or deletes a logged evening.

    What genuinely can't be recomputed is what the person *did* about it:
    when they first completed it (so the completion date doesn't move
    around if they later delete an entry), whether they've collected the
    reward, and whether they've seen the "готово!" banner yet — which is
    what stops Home from announcing the same finished challenge every
    single time it loads.
    """
    __tablename__ = "challenge_progress"

    id = Column(String, primary_key=True, default=gen_uuid)
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)

    # Stable id from the catalog in app/challenges.py, e.g. "twelve_countries".
    challenge_id = Column(String, nullable=False)
    # Which run of it this row is. "2026-W38" for a weekly, "2026" for a
    # yearly — see challenges.py::period_key. Part of the unique key, so
    # the same weekly challenge coming back around next month is a
    # genuinely fresh row with its own completion and its own reward,
    # rather than something already-claimed that can never pay out again.
    period_key = Column(String, nullable=False)

    completed_at = Column(DateTime(timezone=True), nullable=True)
    claimed_at = Column(DateTime(timezone=True), nullable=True)
    # When the client last showed this completion to the person. NULL +
    # completed_at set is exactly the "announce this on Home" condition —
    # see routers/challenges.py::mark_seen.
    seen_at = Column(DateTime(timezone=True), nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User")

    __table_args__ = (
        UniqueConstraint("user_id", "challenge_id", "period_key", name="uq_challenge_progress"),
        Index("ix_challenge_progress_user_period", "user_id", "period_key"),
    )


class CardShare(Base):
    """One share card someone actually sent out of the app — the only
    sincerity source that can't be recomputed from what's logged (see
    app/sincerity.py::earn_card_share), which is why it's a table at
    all: whether a card left the app is a fact about the share sheet,
    not about any diary row.

    `card_key` identifies the *card*, not the act of sharing it — the
    client's own stable id for it (e.g. "seenly-<diary entry id>" for an
    evening card, "title-<media id>" for a title card; see
    mobile/lib/widgets/share_sheet.dart). The unique constraint on
    (user_id, card_key) is what makes the reward a once-per-card thing:
    sharing the same card again later is fine and free, it just doesn't
    pay twice. `day_key` (UTC, "YYYY-MM-DD") exists only so the per-day
    cap in routers/card_shares.py is one indexed count instead of a
    timestamp-range scan.

    Nothing server-side can confirm the card really reached anyone, so
    both limits above are the whole anti-farming story — see
    routers/card_shares.py's docstring for the numbers and the reasoning.
    """
    __tablename__ = "card_shares"

    id = Column(String, primary_key=True, default=gen_uuid)
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)

    card_key = Column(String, nullable=False)
    day_key = Column(String, nullable=False)

    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User")

    __table_args__ = (
        UniqueConstraint("user_id", "card_key", name="uq_card_share_user_card"),
        Index("ix_card_shares_user_day", "user_id", "day_key"),
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
    link_id = Column(String, ForeignKey("partner_links.id", ondelete="CASCADE"), nullable=False, index=True)

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
    added_by_id = Column(String, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    watched_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

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
    scheduled_date = Column(DateTime(timezone=True), nullable=True)  # day precision — see planned_hour/minute for a time
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
    link_id = Column(String, ForeignKey("partner_links.id", ondelete="CASCADE"), nullable=False, index=True)

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

    started_by_id = Column(String, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    link = relationship("PartnerLink")
    votes = relationship(
        "CoViewVoteCast", back_populates="session", cascade="all, delete-orphan", passive_deletes=True,
    )


class CoViewVoteCast(Base):
    """One person's yes/no on one title, in one round. A match is both
    participants having a "yes" row for the same (media_id, source) —
    identical shape to TogetherSwipe, just scoped to a standing link
    instead of a join-by-code session."""
    __tablename__ = "co_view_vote_casts"

    id = Column(String, primary_key=True, default=gen_uuid)
    session_id = Column(String, ForeignKey("co_view_vote_sessions.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)

    media_id = Column(String, nullable=False)
    source = Column(String, nullable=False)
    decision = Column(Integer, nullable=False)  # 0/1

    created_at = Column(DateTime(timezone=True), server_default=func.now())

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
    link_id = Column(String, ForeignKey("partner_links.id", ondelete="CASCADE"), nullable=False, index=True)

    status = Column(Enum(CoViewPollStatus), default=CoViewPollStatus.active, nullable=False)

    # Same pool_source options as a vote round — see _build_vote_pool.
    pool_source = Column(String, nullable=False, default="personal")

    # This round's shortlist. Replaced in place (not appended to) on a
    # runoff — see _resolve_if_needed — so it always reflects exactly
    # what the *current* round_number is voting on.
    candidates_json = Column(Text, nullable=False)
    round_number = Column(Integer, nullable=False, default=1)
    deadline = Column(DateTime(timezone=True), nullable=False)

    winner_source = Column(String, nullable=True)
    winner_media_id = Column(String, nullable=True)

    started_by_id = Column(String, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    link = relationship("PartnerLink")
    votes = relationship(
        "CoViewPollVote", back_populates="session", cascade="all, delete-orphan", passive_deletes=True,
    )


class CoViewPollVote(Base):
    """One person's pick among the *current* round's candidates, by index
    into candidates_json. Indexed rather than keyed by (source, media_id)
    since a runoff's shortlist is a fresh subset with its own indices —
    votes don't carry over between rounds anyway, they're cleared when a
    runoff starts (see _resolve_if_needed)."""
    __tablename__ = "co_view_poll_votes"

    id = Column(String, primary_key=True, default=gen_uuid)
    session_id = Column(String, ForeignKey("co_view_poll_sessions.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
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
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    integration = Column(String, nullable=False)  # "plex" | "jellyfin" | "kodi" | "netflix" | ...
    raw_title = Column(String, nullable=True)
    matched_media_id = Column(String, nullable=True)  # null if nothing in the catalog matched
    matched_source = Column(String, nullable=True)
    action = Column(String, nullable=False)  # "logged" | "ignored" | "unmatched"
    detail = Column(String, nullable=True)   # short human-readable reason, e.g. "below threshold"
    created_at = Column(DateTime(timezone=True), server_default=func.now())


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
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


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
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class Suggestion(Base):
    """One title sent from one account to its linked partner — the "I'm
    suggesting this for tonight" tap on a title screen. A snapshot of the
    title, same reasoning as UserListItem/WatchlistEntry: it still renders
    correctly even if the source is briefly unreachable later."""
    __tablename__ = "suggestions"

    id = Column(String, primary_key=True, default=gen_uuid)

    sender_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    receiver_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)

    media_id = Column(String, nullable=False)
    media_type = Column(Enum(MediaType), nullable=False)
    source = Column(String, nullable=False)

    title_ru = Column(String, nullable=True)
    title_en = Column(String, nullable=True)
    poster_url = Column(String, nullable=True)
    year = Column(Integer, nullable=True)

    seen = Column(Integer, default=0)  # 0/1 — same int-bool convention as is_rewatch

    created_at = Column(DateTime(timezone=True), server_default=func.now())

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

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    items = relationship(
        "TeamiraCollectionItem", back_populates="collection",
        cascade="all, delete-orphan", passive_deletes=True, order_by="TeamiraCollectionItem.position",
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
    collection_id = Column(String, ForeignKey("teamira_collections.id", ondelete="CASCADE"), nullable=False, index=True)

    media_id = Column("tmdb_id", String, nullable=False)
    media_type = Column(String, nullable=False)  # "movie" | "series" | "anime" | "game" | "book" | "manga"
    source = Column(String, nullable=True)  # "tmdb" | "igdb" | "google_books" | "shikimori_manga"; NULL == "tmdb"
    position = Column(Integer, nullable=False, default=0)

    added_at = Column(DateTime(timezone=True), server_default=func.now())

    collection = relationship("TeamiraCollection", back_populates="items")

    __table_args__ = (
        # media_type is already source-specific (movie/series/anime only
        # ever come from tmdb; game only from igdb; book/manga only from
        # their own Open Library sources) — so (media_id, media_type)
        # alone still can't collide across sources, no need to add
        # `source` into this constraint.
        UniqueConstraint("collection_id", "tmdb_id", "media_type", name="uq_teamira_collection_item"),
    )


# ---------------------------------------------------------------------------
# Referral program — separate from the plain "invite a friend" graph above
# (User.invite_code / User.referred_by_id, routers/friends.py). That graph
# only ever answers "who invited whom"; everything about turning an invite
# into a reward — anti-fraud gating, milestone bonuses, the personal
# purchase-discount promo code — lives in the three tables below instead of
# growing directly on User, since almost none of it is a permanent identity
# fact the way invite_code is. See routers/referrals.py for the actual
# verification/reward logic that reads and writes these.
# ---------------------------------------------------------------------------

class ReferralStatus(str, enum.Enum):
    pending = "pending"    # link used, real-person conditions not all met yet
    verified = "verified"  # conditions met, counts toward the referrer's tally
    rewarded = "rewarded"  # verified *and* this is the one that crossed a milestone
    rejected = "rejected"  # never counts (self-referral, duplicate signup, admin action)


class ReferralRewardReason(str, enum.Enum):
    milestone_1 = "milestone_1"    # 1st confirmed invite
    milestone_5 = "milestone_5"    # 5th confirmed invite (cumulative, on top of milestone_1)
    milestone_10 = "milestone_10"  # 10th confirmed invite (cumulative, on top of the two above)
    # Every RECURRING_MILESTONE_STEP confirmed invites past the highest
    # named tier (see routers/referrals.py::RECURRING_MILESTONE_STEP) —
    # one shared reason across every crossing (15th, 20th, 25th, ...),
    # unlike the named tiers above which each get their own value. See
    # that constant's own comment for how uniqueness is still enforced
    # per-crossing despite the shared reason.
    milestone_recurring = "milestone_recurring"
    purchase_bonus = "purchase_bonus"  # a referred person paid for premium using this referrer's promo code
    # The REFERRED person's own reward, not the referrer's — granted once,
    # to referred_id rather than referrer_id, the moment their own
    # Referral row passes verification (see routers/referrals.py::
    # REFERRED_WELCOME_DAYS). Symmetric with milestone_1 on purpose: the
    # invited person earns it by doing exactly what the verification gate
    # already asks of them (use the app for a week), so this doubles as
    # the immediate, non-purchase-dependent incentive to actually accept
    # an invite in the first place — the promo-code discount alone gave
    # them nothing to look forward to before an eventual purchase that,
    # given this app has no real billing yet (see UserPremiumState's own
    # docstring), currently saves them nothing at all.
    referred_welcome = "referred_welcome"


class Referral(Base):
    """One row per (referrer, referred) pair, created the moment the
    referred person's account picks up a referrer — at registration
    (routers/auth.py::register) or via the deferred claim
    (routers/friends.py::claim_invite), whichever happens first. Not the
    same event as User.referred_by_id being set (that's the permanent
    identity fact); this is the mutable, re-checkable state around
    whether that invite should actually pay out.
    """
    __tablename__ = "referrals"

    id = Column(String, primary_key=True, default=gen_uuid)
    referrer_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    referred_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, unique=True, index=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    status = Column(Enum(ReferralStatus), nullable=False, default=ReferralStatus.pending)
    verified_at = Column(DateTime(timezone=True), nullable=True)

    # Snapshots from the most recent recompute (see routers/referrals.py::
    # _recompute_pending), kept on the row so GET /referrals/status can
    # show live per-person progress without recomputing on every single
    # read of every referral ever made — only the referrer's own pending
    # rows get recomputed when they load that screen.
    streak_days_current = Column(Integer, nullable=False, default=0)
    entries_count_snapshot = Column(Integer, nullable=False, default=0)

    # Best-effort signup fingerprint for the one dedup check this program
    # does — no SMS verification, no device SDK, just "does this look
    # like the same signup happening twice" (see _reject_if_duplicate_ip
    # in routers/referrals.py). device_fingerprint stays unused for now
    # (nothing on the client sends one yet) but is here so adding that
    # later doesn't need another migration.
    ip_at_signup = Column(String, nullable=True)
    device_fingerprint = Column(String, nullable=True)

    __table_args__ = (
        Index("ix_referrals_referrer_status", "referrer_id", "status"),
    )


class ReferralReward(Base):
    """Append-only log of every payout the referral program has ever
    granted — one row per grant, never edited or deleted, so a bonus can
    always be traced back to exactly why it happened and (via
    source_referral_id) to whom. `granted_days` is the only payout kind
    implemented right now (see routers/referrals.py::MILESTONES and
    PURCHASE_BONUS_DAYS) — a cosmetics/AI-limit alternative for the
    milestone_1 tier was floated during planning but not built, so that
    column stays nullable for a possible future non-day reward without
    another migration.
    """
    __tablename__ = "referral_rewards"

    id = Column(String, primary_key=True, default=gen_uuid)
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    reason = Column(Enum(ReferralRewardReason), nullable=False)
    granted_days = Column(Integer, nullable=True)
    granted_at = Column(DateTime(timezone=True), server_default=func.now())
    source_referral_id = Column(String, ForeignKey("referrals.id", ondelete="SET NULL"), nullable=True)


class PromoCode(Base):
    """A referrer's own personal purchase-discount code — one per
    account, minted lazily (same lazy-on-first-request shape as
    User.invite_code, see routers/friends.py::get_invite) rather than
    one per invitee. Shared the same way invite_code is; whoever is
    first to actually redeem it on a premium purchase gets bound to it
    (`referred_id`, `used_at` set together, see routers/referrals.py::
    apply_promo_at_purchase) and it can never be redeemed by anyone else
    after that — "personal" describes who *owns* the code (the
    referrer), "one-time" describes how many people can ever spend it.
    Not to be confused with User.invite_code: that one gets someone
    *into* the referral program at signup; this one is what a referred
    person spends, once, on their own first premium purchase.
    """
    __tablename__ = "promo_codes"

    id = Column(String, primary_key=True, default=gen_uuid)
    code = Column(String, unique=True, nullable=False, index=True)
    referrer_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, unique=True, index=True)
    # Bound the moment the code is first redeemed at purchase; NULL until
    # then, per this class's own docstring.
    referred_id = Column(String, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)
    discount_percent = Column(Integer, nullable=False, default=15)
    used_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class SincerityReason(str, enum.Enum):
    """Every way a SincerityTransaction can happen — see
    app/sincerity.py's module docstring for the product reasoning behind
    each one. Deliberately a short, closed list: the whole point of this
    system is that it rewards a few specific honest acts, not general
    activity, so a new reason should be added here only when it's a
    genuinely new kind of honest act, not a new place to farm points for
    an existing one.
    """
    # Earning
    closed_gestalt = "closed_gestalt"                # a stale planned item finally watched, or honestly marked "not for me"
    revised_rating = "revised_rating"                 # changed an old rating instead of defending it
    accurate_recommendation = "accurate_recommendation"  # a staked recommendation to a friend turned out right
    honest_drop = "honest_drop"                       # dropped something mid-way with a real reason, instead of leaving it hanging
    # honest_drop above and formed_own_opinion below were joined by this
    # pair once the recommendation-stake economy actually shipped (see
    # app/routers/recommendations.py) — a v1 stake either resolves into
    # accurate_recommendation above or one of the two outcomes below, never
    # silently disappearing.
    formed_own_opinion = "formed_own_opinion"          # rated a shared title before seeing a circle-mate's already-shared rating for it
    second_chance = "second_chance"                     # went back to something you'd honestly dropped, and actually finished it this time
    # Everyday-activity earning — merged in from the old, separate XP/
    # level system (see app/sincerity.py's module docstring for why that
    # system and this one used to be kept apart, and why they no longer
    # are). Each of these is a small, flat, one-time ledger award for an
    # ordinary logging action, not a rare honest act — deliberately not
    # gated behind any "closing a loop" requirement the way the six
    # reasons above are.
    watched_logged = "watched_logged"                  # a title reached `watched` for the first time
    review_written = "review_written"                  # a diary entry was logged with an actual note attached
    rewatch_logged = "rewatch_logged"                  # logged watching something again
    watched_together_bonus = "watched_together_bonus"  # an evening logged as watched together with a partner
    genre_explored = "genre_explored"                  # a genre logged for the first time ever on this account
    streak_milestone = "streak_milestone"              # one more day added to this account's longest-ever streak
    friend_invited = "friend_invited"                  # someone registered using this account's invite code
    card_shared = "card_shared"                        # a share card left the app (see app/routers/card_shares.py)
    challenge_claimed = "challenge_claimed"             # a weekly/yearly challenge's reward was collected
    # Spending
    recommendation_stake = "recommendation_stake"     # staked on a friend recommendation (see accurate_recommendation for the payout)
    stake_forfeited = "stake_forfeited"                # the staked recommendation above turned out wrong — stake burned, not returned
    stake_expired = "stake_expired"                    # the friend never got around to the title — stake returned in full, nobody's fault
    spoiler_unlock = "spoiler_unlock"                 # paid to see a circle-mate's already-logged rating before rating the title yourself
    debt_settled = "debt_settled"                     # paid a flat fee to permanently exempt one planned item from stale_debt
    pin_slot_purchased = "pin_slot_purchased"          # paid a flat fee for one more permanent badge-showcase slot
    nudge_sent = "nudge_sent"                          # paid to nudge a circle-mate about a stale shared plan
    # Passive, no user action — the one reason that can be negative on
    # its own rather than as a spend
    stale_debt = "stale_debt"                          # a planned item has been sitting untouched past the threshold


class SincerityTransaction(Base):
    """One line of the ledger behind User.sincerity_balance — see that
    column's docstring for why the balance is denormalized rather than
    always summed from here. Every row is written by
    app/sincerity.py::record_transaction, atomically with the balance
    update it corresponds to, so this table is always a complete,
    ordered history of exactly how the current balance was arrived at —
    the same "why does this number look like this" transparency the
    Sincerity screen's history list is built to show.

    `delta` is usually positive (earned) or negative (spent, or
    stale-debt decay) — callers skip writing a row rather than log a
    genuine no-op change. The one exception is `stake_forfeited`: the
    cost of a recommendation stake is already charged up front, at
    `recommendation_stake` time, so a losing stake's resolution has
    nothing further to deduct — this row exists purely so the history
    list can say what happened to that earlier stake, with `delta=0`.

    `related_entry_id`/`related_user_id` are both nullable and mean
    different things per reason: for closed_gestalt/revised_rating/
    honest_drop it's the WatchlistEntry or DiaryEntry id involved; for
    recommendation_stake/accurate_recommendation/stake_forfeited it's
    the *other* person's user id (who the stake was with), not a
    content id. Left as two loosely-typed nullable columns rather than
    a real polymorphic FK — this table is read, never joined on, so
    there's nothing to gain from a stricter schema here.
    """
    __tablename__ = "sincerity_transactions"

    id = Column(String, primary_key=True, default=gen_uuid)
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    delta = Column(Integer, nullable=False)
    reason = Column(Enum(SincerityReason), nullable=False)
    # Short, human-readable line shown directly in the Sincerity
    # screen's history list next to this entry — e.g. the title
    # involved, or the friend's display name — filled in by
    # app/sincerity.py at write time rather than reconstructed later
    # from related_entry_id/related_user_id (which may point at
    # something since renamed, deleted, or unfriended).
    note = Column(String, nullable=True)
    related_entry_id = Column(String, nullable=True)
    related_user_id = Column(String, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User", back_populates="sincerity_transactions")


class RecommendationStatus(str, enum.Enum):
    pending = "pending"    # staked, waiting on the friend to log a rating
    hit = "hit"            # resolved — see SincerityReason.accurate_recommendation
    missed = "missed"      # resolved — see SincerityReason.stake_forfeited
    expired = "expired"    # never resolved in time — see SincerityReason.stake_expired


class Recommendation(Base):
    """One staked "I bet you'll rate this N" — the real feature behind
    the recommendation_stake/accurate_recommendation/stake_forfeited
    trio in SincerityReason, which existed in app/sincerity.py's ledger
    math for a while before there was anywhere in the product to
    actually create one of these (see app/routers/recommendations.py,
    the first and only place that does).

    Created by POST /recommendations, which calls
    sincerity.spend_recommendation_stake up front — the cost is taken
    at stake time, not at resolution, same as a real bet. Resolved
    exactly once, by whichever comes first:

    - the recipient logs their own rating for this exact (source,
      media_id) — routers/diary.py::log_watched checks for a pending
      Recommendation aimed at the person doing the logging and calls
      sincerity.resolve_recommendation_stake, or
    - RECOMMENDATION_EXPIRY passes with no rating logged —
      routers/recommendations.py's list endpoint sweeps for these
      lazily on read, the same "no scheduler in this backend" shape
      apply_stale_planned_decay uses, and calls
      sincerity.expire_recommendation_stake to hand the stake back in
      full (an unwatched title isn't a broken promise on either side).

    `title` is a snapshot (same reasoning as WatchlistEntry's own
    title_ru/title_en) so a resolved or expired card still reads
    correctly if the title's catalog entry changes shape later.
    """
    __tablename__ = "recommendations"

    id = Column(String, primary_key=True, default=gen_uuid)
    staker_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    recipient_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)

    source = Column(String, nullable=False)
    media_id = Column(String, nullable=False)
    title = Column(String, nullable=False)

    predicted_rating = Column(Integer, nullable=False)
    staked_amount = Column(Integer, nullable=False)

    status = Column(Enum(RecommendationStatus), default=RecommendationStatus.pending, nullable=False)
    actual_rating = Column(Integer, nullable=True)
    resolved_at = Column(DateTime(timezone=True), nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())

    staker = relationship("User", foreign_keys=[staker_id])
    recipient = relationship("User", foreign_keys=[recipient_id])

    __table_args__ = (
        # list_recommendations reads "my pending outgoing" (staker_id +
        # status); log_watched's resolution hook reads "pending
        # recommendations aimed at me" (recipient_id + status) before
        # narrowing further by title in Python — a circle-mate rarely has
        # more than a handful pending at once, so filtering the rest in
        # Python rather than a second indexed column is the simpler
        # tradeoff here.
        Index("ix_recommendations_recipient_status", "recipient_id", "status"),
        Index("ix_recommendations_staker_status", "staker_id", "status"),
    )


# ---------------------------------------------------------------------------
# Sessions, recovery links, blocks and reports — everything the account
# lifecycle needs that isn't a column on `users` itself.
#
# Four tables, deliberately separate from each other rather than one
# generic "security events" table: they have genuinely different
# lifetimes (a refresh session lives for months, a reset link for an
# hour), different read patterns (one is looked up on every token
# refresh, another only when someone clicks a link in their mail), and
# different retention rules (a report has to survive the account it was
# filed about being deleted — see Report.reported_user_id's ondelete).
# ---------------------------------------------------------------------------

class RefreshSession(Base):
    """One signed-in device. Backs the refresh-token half of the token
    pair issued by routers/auth.py — the access token stays short-lived
    (settings.jwt_expire_minutes, now measured in minutes rather than the
    week it used to be), and this is what lets the app get a new one
    silently instead of dumping someone back at the login screen.

    The token itself is never stored — only `token_hash`, a SHA-256 of
    it. A database dump therefore doesn't hand anyone a working session,
    the same reason `users.password_hash` isn't a password. SHA-256 and
    not bcrypt here on purpose: unlike a password, a refresh token is
    256 bits of real randomness generated by this server, so there's no
    dictionary to slow down, and this lookup happens on every refresh.

    **Rotation with reuse detection.** Every refresh returns a new token
    and marks the old row `rotated_at` + `replaced_by_id`. If a token
    that has already been rotated is presented again, that means two
    parties hold the same token — the real device and a thief — and
    there's no way to tell which one just called. So the entire chain
    (see `family_id`) is revoked and both are forced to log in again.
    That's the standard OAuth 2.0 BCP response to refresh-token replay,
    and it's the one thing that makes a long-lived refresh token safer
    than the long-lived access token this replaces, rather than just a
    rename of it.
    """
    __tablename__ = "refresh_sessions"

    id = Column(String, primary_key=True, default=gen_uuid)
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)

    token_hash = Column(String, unique=True, nullable=False, index=True)
    # Every session descended from one original login shares this id, so
    # a detected replay can revoke the whole chain in one UPDATE instead
    # of walking replaced_by_id links.
    family_id = Column(String, nullable=False, index=True)
    replaced_by_id = Column(String, nullable=True)

    # Shown on the "where you're signed in" list — whatever the client
    # sent as its device name, plus a coarse fingerprint. Deliberately
    # not a full user-agent dump or a precise IP history: enough to
    # recognise your own phone, not enough to be a tracking log.
    device_label = Column(String, nullable=True)
    created_ip = Column(String, nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    last_used_at = Column(DateTime(timezone=True), nullable=True)
    expires_at = Column(DateTime(timezone=True), nullable=False)
    rotated_at = Column(DateTime(timezone=True), nullable=True)
    revoked_at = Column(DateTime(timezone=True), nullable=True)
    # "logout" | "rotation_reuse" | "password_change" | "account_deleted"
    # | "logout_all" — kept for the security screen and for working out
    # after the fact why someone got signed out.
    revoked_reason = Column(String, nullable=True)

    user = relationship("User")

    __table_args__ = (
        Index("ix_refresh_sessions_user_active", "user_id", "revoked_at"),
    )


class AccountTokenPurpose(str, enum.Enum):
    password_reset = "password_reset"
    email_verify = "email_verify"


class AccountToken(Base):
    """A single-use, short-lived link sent to an email address — the
    password-reset link and the address-verification link, which are the
    same mechanism with different consequences, so they share one table
    and differ only by `purpose`.

    Same hash-don't-store rule as RefreshSession above, for the same
    reason: whoever can read this table would otherwise be able to take
    over every account with a reset in flight.

    `consumed_at` rather than deleting the row on use — a used link that
    still exists can answer "this link was already used" instead of the
    indistinguishable "this link is wrong", which matters because people
    routinely click the link in their mail twice.
    """
    __tablename__ = "account_tokens"

    id = Column(String, primary_key=True, default=gen_uuid)
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    purpose = Column(Enum(AccountTokenPurpose), nullable=False)
    token_hash = Column(String, unique=True, nullable=False, index=True)
    # Snapshot of the address this was sent to. A verification link must
    # only ever verify the address it was mailed to, even if the person
    # has since typed a different one into settings — otherwise clicking
    # an old link would silently confirm an address nobody proved they
    # own.
    email = Column(String, nullable=False)
    expires_at = Column(DateTime(timezone=True), nullable=False)
    consumed_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    created_ip = Column(String, nullable=True)

    user = relationship("User")


class UserBlock(Base):
    """One account has blocked another. Directional as stored, symmetric
    in effect: app/blocking.py treats a block in either direction as a
    wall between the two, so blocking someone also stops *them* seeing
    *you*, not just the other way round. Anything else would make
    blocking an announcement ("why can I still see their profile but
    they can't see mine?") instead of a way out.

    Blocking is immediate and needs no review — unlike a Report below,
    which asks a human to look. The two are deliberately separate
    actions that the UI offers together: "block and report" is one tap,
    but blocking alone doesn't file a complaint about someone, and
    reporting alone doesn't force you to keep seeing them.
    """
    __tablename__ = "user_blocks"

    id = Column(String, primary_key=True, default=gen_uuid)
    blocker_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    blocked_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    blocker = relationship("User", foreign_keys=[blocker_id])
    blocked = relationship("User", foreign_keys=[blocked_id])

    __table_args__ = (
        UniqueConstraint("blocker_id", "blocked_id", name="uq_user_block_pair"),
    )


class ReportTargetType(str, enum.Enum):
    user = "user"                 # the profile itself: nickname, avatar, status line
    diary_entry = "diary_entry"   # a note written on an evening
    activity_event = "activity_event"
    list = "list"                 # a user list's name/description
    review = "review"


class ReportReason(str, enum.Enum):
    """Kept short and concrete. A long taxonomy makes people pick
    "other" and write the real reason in free text, which is slower to
    triage, not faster."""
    harassment = "harassment"
    hate = "hate"
    sexual_content = "sexual_content"
    violence = "violence"
    spam = "spam"
    impersonation = "impersonation"
    self_harm = "self_harm"
    child_safety = "child_safety"
    other = "other"


class ReportStatus(str, enum.Enum):
    pending = "pending"
    actioned = "actioned"   # something was done: content removed, account suspended
    dismissed = "dismissed"  # looked at, nothing to act on


class Report(Base):
    """A complaint about a person or a piece of user-generated content,
    and what was done about it.

    Apple's Guideline 1.2 asks for a mechanism to report objectionable
    content and for the developer to *act on* reports within 24 hours.
    `due_at` is what makes that checkable rather than aspirational: it's
    set at filing time to created_at + settings.report_sla_hours, and
    GET /moderation/admin/reports sorts the queue by it, oldest first,
    flagging anything overdue.

    `reported_user_id` is ON DELETE SET NULL, not CASCADE — unlike almost
    everything else that points at `users`. A report has to outlive the
    account it was about: "this account was suspended for X and then
    deleted itself" is exactly the history that needs to survive, and the
    snapshot columns below are there so the row still means something
    once the live rows are gone. `reporter_id` is SET NULL for the
    mirror-image reason: someone deleting their own account shouldn't
    retract complaints they filed about other people.
    """
    __tablename__ = "reports"

    id = Column(String, primary_key=True, default=gen_uuid)

    reporter_id = Column(String, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)
    reported_user_id = Column(String, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)

    target_type = Column(Enum(ReportTargetType), nullable=False)
    # NULL when target_type is `user` — the account itself is the target.
    target_id = Column(String, nullable=True)

    reason = Column(Enum(ReportReason), nullable=False)
    details = Column(String, nullable=True)

    # Frozen copies of what was actually being complained about, taken at
    # filing time. Without these, someone could report an abusive note,
    # the author could edit it to something innocuous before a moderator
    # opened the queue, and the report would read as baseless. Also what
    # keeps the row meaningful after the target is deleted.
    target_snapshot = Column(Text, nullable=True)
    reported_username_snapshot = Column(String, nullable=True)

    status = Column(Enum(ReportStatus), nullable=False, default=ReportStatus.pending)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    due_at = Column(DateTime(timezone=True), nullable=True, index=True)
    resolved_at = Column(DateTime(timezone=True), nullable=True)
    resolved_by_id = Column(String, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    # What the moderator actually did, in their own words — shown back to
    # the reporter as "we looked at this" and kept as the audit trail.
    resolution_note = Column(String, nullable=True)
    # "none" | "content_removed" | "user_suspended" | "user_banned"
    action_taken = Column(String, nullable=True)

    reporter = relationship("User", foreign_keys=[reporter_id])
    reported_user = relationship("User", foreign_keys=[reported_user_id])
    resolved_by = relationship("User", foreign_keys=[resolved_by_id])

    __table_args__ = (
        # The moderation queue is "pending, oldest due first" on every
        # single load — see routers/moderation.py::admin_list_reports.
        Index("ix_reports_status_due", "status", "due_at"),
        # NOT a plain UniqueConstraint — an earlier version of this file
        # had one on (reporter_id, target_type, target_id,
        # reported_user_id) and documented it as "stops one person filing
        # the same complaint fifty times". That claim was false: SQL
        # unique constraints treat every NULL as distinct from every
        # other NULL, and target_id IS NULL for every `user`-type report
        # (see that column's own comment above) — so two rows reporting
        # the same account, filed by the same person, both with
        # target_id NULL, do not collide on a plain UniqueConstraint at
        # all. Verified directly: inserting two such rows against this
        # exact constraint succeeds both times.
        #
        # The actual backstop is the expression-based unique index this
        # migration creates on Postgres — see
        # migrations/versions/a7d3f1e08b45's `uq_report_once_per_reporter`,
        # built on `COALESCE(target_id, '')` so NULL is treated as an
        # ordinary, comparable value instead of "distinct from itself".
        # That index isn't expressible as SQLAlchemy table metadata (no
        # portable way to declare a functional unique index across
        # dialects), which is why it isn't declared here — this table's
        # metadata intentionally has no unique constraint of its own, and
        # `create_all()` (used by tests and fresh local dev) relies
        # entirely on the application-level check in
        # routers/moderation.py::create_report for the non-Postgres case.
        # That check is a plain SELECT-then-insert and therefore has a
        # TOCTOU race under concurrent identical requests; the index is
        # what closes that race on the database this app actually runs on.
    )


# ---------------------------------------------------------------------------


class PushToken(Base):
    """One device's FCM registration token — see app/push.py for the
    service that actually sends through these. A person can (and often
    does) have several: a phone and a tablet, or a phone they reinstalled
    the app on without ever explicitly logging out of the old install.
    All of them get pushed to; there's no concept of a single "current"
    device.

    `token` itself is what Firebase hands the client after
    `FirebaseMessaging.getToken()` — opaque, device+app-install specific,
    and does rotate occasionally (a fresh install, a token refresh
    Firebase decides to do on its own) — see routers/push.py::
    register_token's upsert-by-token logic for why the unique constraint
    is on the token alone, not (user_id, token): a token FCM reissues to
    the same physical device after this app already stored it under a
    *different* user (a logout/login-as-someone-else on a shared device)
    needs to move to the new owner, not collide with a stale row.
    """
    __tablename__ = "push_tokens"

    id = Column(String, primary_key=True, default=gen_uuid)
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    token = Column(String, unique=True, nullable=False, index=True)
    platform = Column(String, nullable=False)  # "ios" | "android"
    # IANA name ("Europe/Moscow"), reported by the client alongside the
    # token (see routers/push.py::register_token) — this is the only
    # place this app knows anything about what timezone a person is
    # actually in, and it exists solely so
    # scripts/send_scheduled_push.py's streak reminder can fire in *this*
    # device's evening rather than at some fixed UTC hour that's the
    # middle of the night for half the audience. Nullable because an
    # older client build might not send it yet; that device simply never
    # matches the "it's evening there" check and gets no streak reminder,
    # rather than a raise or a UTC-guess.
    timezone = Column(String, nullable=True)
    # "ru" | "en" — the language the device's app shows, sent on every
    # registration so a push is worded for the person holding it. NULL (an
    # install from before this existed) is treated as Russian, which is what
    # every push used to be. See app/bi.py.
    locale = Column(String(8), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    # Bumped on every successful register call (even for a token this
    # table already has) and read by nothing yet — kept anyway, the same
    # reasoning as RefreshSession.last_used_at: cheap to have on hand the
    # first time "which of this person's devices are actually still
    # active" turns out to matter, expensive to reconstruct after the
    # fact if it's missing then.
    last_seen_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User")


class NotifiedRelease(Base):
    """One row per (user, title, specific release) this app has already
    pushed a "new episode"/"it's out" notification for — see
    scripts/send_new_episode_push.py. PushLog (below) already dedupes
    the streak-reminder/memory pushes, but only at "already sent this
    *category* today" granularity; a new-episode push needs a finer key
    than that, since a show can air a new episode every week and each
    one deserves exactly one push, not zero (blocked by yesterday's
    already-sent-today row) or unlimited (one per cron run all evening).

    `release_key` is what actually disambiguates one release from the
    next for the same title: "sE<season>e<episode>" for a series/anime
    episode, "release" for a game (which only ever has the one release
    to notify about). Combined with (user_id, source, media_id) via the
    unique constraint below, re-running the cron script — hourly, same
    "no in-process scheduler" reasoning as every other cron job in this
    backend (see scripts/send_scheduled_push.py's own docstring) — can
    always ask "did I already tell this person about this exact episode"
    with a single indexed lookup, no free-text matching against
    PushLog.body required.
    """
    __tablename__ = "notified_releases"

    id = Column(String, primary_key=True, default=gen_uuid)
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    source = Column(String, nullable=False)   # "tmdb" | "igdb"
    media_id = Column(String, nullable=False)
    release_key = Column(String, nullable=False)  # "s<season>e<episode>" | "release"
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    __table_args__ = (
        UniqueConstraint(
            "user_id", "source", "media_id", "release_key",
            name="uq_notified_release",
        ),
    )


class PushLog(Base):
    """One row per push notification actually handed to Firebase —
    written by app/push.py::PushService.send_to_user regardless of
    whether Firebase ends up delivering it. Two independent reasons this
    exists, not one:

    1. **Debugging.** "Did X actually get a push for Y" is otherwise
       unanswerable after the fact — Firebase's own delivery receipts
       don't go anywhere this app can query them later.
    2. **Idempotency for the scheduled script.** send_scheduled_push.py
       runs on a plain cron schedule (see that script's own docstring for
       why this app has no in-process scheduler) with no memory of its
       own between invocations — an hourly run has to be able to ask "did
       I already send this category to this person today" itself, or a
       streak reminder would fire once per hour all evening instead of
       once. See `already_sent_today` below for that check.
    """
    __tablename__ = "push_log"

    id = Column(String, primary_key=True, default=gen_uuid)
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    category = Column(String, nullable=False)  # see PushCategory in app/push.py
    title = Column(String, nullable=False)
    body = Column(String, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    __table_args__ = (
        # send_scheduled_push.py's "already sent today" check (see the
        # class docstring above) is exactly this shape: user_id +
        # category + created_at's calendar date. Composite index rather
        # than two separate ones — every query that hits this table
        # filters on user_id and category together, never category alone.
        Index("ix_push_log_user_category_created", "user_id", "category", "created_at"),
    )


# ---------------------------------------------------------------------------
# Pair album — the premium "Альбом пары" living on the co-viewing screen.
# Three small things a couple accumulates that a shared diary alone doesn't
# hold: notes to each other that stay sealed until an evening has actually
# been watched, time capsules that open on a date, and the date the two of
# them started. Everything hangs off the standing PartnerLink and goes with
# it when the link does (ON DELETE CASCADE) — an album belongs to the two
# people in it, so it doesn't outlive their pairing. See routers/
# pair_album.py for the rules, and app/pair_album.py for the pure helpers.
# ---------------------------------------------------------------------------

class PairAlbumSettings(Base):
    """One row per pair, created the first time either side sets the date
    they started. `together_since` is a plain calendar date (no time, no
    timezone) — an anniversary is a day, not an instant — and either
    member can change it, last write wins; `set_by_id` only remembers who
    so the other side can be told \"X changed it\" instead of it silently
    shifting under them."""
    __tablename__ = "pair_album_settings"

    link_id = Column(String, ForeignKey("partner_links.id", ondelete="CASCADE"), primary_key=True)
    together_since = Column(Date, nullable=True)
    set_by_id = Column(String, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


class PairNote(Base):
    """A note one partner leaves for the other on a title's card, written
    *before* the evening. Sealed until that evening is marked watched —
    the API never returns the other person's text while `revealed_at` is
    null, only the fact that a note exists.

    Keyed by (link, source, media_id) — the same identity CoViewEntry's own
    unique constraint uses — rather than by the CoViewEntry row itself, for
    three reasons: a note can be written before the evening is even
    planned (there is no entry yet), deleting a planned entry doesn't
    destroy words someone wrote, and re-planning a title later simply
    starts a new `round` instead of resurrecting sealed state on notes
    that were already read. Title fields are snapshots for the same
    reason every other snapshot table here has them.

    One note per author per round. Editable and deletable by its author
    only while unrevealed; once revealed it is a record and is frozen —
    the recipient can only react to it."""
    __tablename__ = "pair_notes"

    id = Column(String, primary_key=True, default=gen_uuid)
    link_id = Column(String, ForeignKey("partner_links.id", ondelete="CASCADE"), nullable=False, index=True)
    author_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)

    media_id = Column(String, nullable=False)
    media_type = Column(Enum(MediaType), nullable=False)
    source = Column(String, nullable=False)
    title_ru = Column(String, nullable=True)
    title_en = Column(String, nullable=True)
    poster_url = Column(String, nullable=True)
    year = Column(Integer, nullable=True)

    # Which viewing of this title the note is for. Starts at 1 and only
    # moves on once a round has been revealed (see pair_album.current_round).
    round = Column(Integer, nullable=False, default=1)

    body = Column(Text, nullable=False)
    mood = Column(String(16), nullable=True)  # one emoji the author picked, purely decorative

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    revealed_at = Column(DateTime(timezone=True), nullable=True)  # set when the evening is marked watched
    evening_on = Column(Date, nullable=True)  # the calendar day of that evening (the client's own day, as logged)
    opened_at = Column(DateTime(timezone=True), nullable=True)    # the *recipient* opened it (drives the one-time reveal)
    reaction = Column(String(16), nullable=True)                  # the recipient's emoji reply

    __table_args__ = (
        UniqueConstraint("link_id", "source", "media_id", "author_id", "round", name="uq_pair_note_round"),
        Index("ix_pair_notes_title", "link_id", "source", "media_id"),
    )


class PairCapsule(Base):
    """A time capsule for two. Either partner creates one with a date to
    open on and their own sealed letter; the other can add theirs any time
    before that date. Nobody — the author included — can read a letter
    until `opens_on` arrives, and `opens_on` never changes after creation:
    the whole point is the promise.

    The date is compared against the *server's* UTC date, never the
    client's clock, so a phone with a shifted clock can't open one early."""
    __tablename__ = "pair_capsules"

    id = Column(String, primary_key=True, default=gen_uuid)
    link_id = Column(String, ForeignKey("partner_links.id", ondelete="CASCADE"), nullable=False, index=True)
    created_by_id = Column(String, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    title = Column(String(60), nullable=True)
    opens_on = Column(Date, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class PairCapsuleLetter(Base):
    """One partner's letter inside a [PairCapsule]. Sealed on submit — there
    is no server-side draft state (drafts live on the device while typing)
    — and immutable afterwards. One per author per capsule."""
    __tablename__ = "pair_capsule_letters"

    id = Column(String, primary_key=True, default=gen_uuid)
    capsule_id = Column(String, ForeignKey("pair_capsules.id", ondelete="CASCADE"), nullable=False, index=True)
    author_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    body = Column(Text, nullable=False)
    sealed_at = Column(DateTime(timezone=True), server_default=func.now())

    __table_args__ = (
        UniqueConstraint("capsule_id", "author_id", name="uq_pair_capsule_letter_author"),
    )


class PairCapsuleRead(Base):
    """Who has already watched a capsule open. Kept per person so the
    opening ceremony plays exactly once for each of the two, on whichever
    device they happen to be holding when it opens."""
    __tablename__ = "pair_capsule_reads"

    capsule_id = Column(String, ForeignKey("pair_capsules.id", ondelete="CASCADE"), primary_key=True)
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    read_at = Column(DateTime(timezone=True), server_default=func.now())



# ---------------------------------------------------------------------------
# Co-view rooms ("Гостиная") — watching together inside the app.
# Rules and reasoning: app/co_view_room.py; HTTP shape: routers/co_view_room.py.
# ---------------------------------------------------------------------------

class CoViewRoomStatus(str, enum.Enum):
    lobby = "lobby"   # created, nobody has pressed play yet
    live = "live"     # playback has started at least once
    ended = "ended"   # finished (saved) or closed (discarded)


class CoViewRoom(Base):
    """One shared viewing session for a linked circle (a couple or a
    company of up to four). At most one un-ended room per link — enforced
    by the partial unique index below, not just by the router's check.

    The player state is a tiny clock, not a video feed: `position_ms` was
    true at `position_updated_at` (server time) and keeps advancing from
    there while `is_playing`. Every client derives "where are we" from
    those two numbers plus the server's own `server_now`, so a phone with
    a shifted clock can't drift the room. `control_seq` bumps on every
    play/pause/seek so clients can ignore stale echoes of their own
    commands.

    The media columns are a snapshot for the same reason every other
    snapshot table here has them. `player_kind` says how the picture
    arrives: youtube/twitch (embedded by id), direct (an https file/stream
    URL), or parallel (each person plays the title in their own streaming
    app; the room only keeps the shared clock, voice and reactions)."""
    __tablename__ = "co_view_rooms"

    id = Column(String, primary_key=True, default=gen_uuid)
    link_id = Column(String, ForeignKey("partner_links.id", ondelete="CASCADE"), nullable=False, index=True)
    host_id = Column(String, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)

    media_id = Column(String, nullable=False)
    media_type = Column(Enum(MediaType), nullable=False)
    source = Column(String, nullable=False)
    title_ru = Column(String, nullable=True)
    title_en = Column(String, nullable=True)
    poster_url = Column(String, nullable=True)
    year = Column(Integer, nullable=True)

    player_kind = Column(String(16), nullable=False, default="parallel")
    player_ref = Column(String(600), nullable=True)
    duration_ms = Column(BigInteger, nullable=True)

    status = Column(Enum(CoViewRoomStatus), nullable=False, default=CoViewRoomStatus.lobby)
    is_playing = Column(Boolean, nullable=False, default=False)
    position_ms = Column(BigInteger, nullable=False, default=0)
    position_updated_at = Column(DateTime(timezone=True), server_default=func.now())
    control_seq = Column(Integer, nullable=False, default=0)
    event_seq = Column(Integer, nullable=False, default=0)

    # The room's own "save this to our shared list" switch. On by default;
    # anyone in the room can flip it until the room ends, and whatever it
    # says at that moment decides whether the evening lands on the shared
    # list/diary (see routers/co_view_room.py::finish_room).
    save_to_shared = Column(Boolean, nullable=False, default=True)
    # The planned co-view card this room was started from, if any.
    entry_id = Column(String, nullable=True)
    # Set when the room ended by being saved: lets the client find the shared
    # entry and the reviews that belong to it.
    saved_entry_id = Column(String, nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    started_at = Column(DateTime(timezone=True), nullable=True)
    ended_at = Column(DateTime(timezone=True), nullable=True)
    last_activity_at = Column(DateTime(timezone=True), server_default=func.now())

    # --- reading together (see app/co_reading.py) ---
    # `activity` says what the room keeps in sync: "watch" is the clock above,
    # "read" is a place in a book or manga. A reading room never carries the
    # text — each person opens their own copy — so all that is kept is the
    # fingerprint of the file (`content_hash`, to tell whether two devices
    # hold the same edition), how long it is (`read_units`: chapters for an
    # EPUB, pages for a CBZ), and where people are. In "together" mode
    # `lead_locator` is the one place everybody follows (and `position_ms`
    # is its progress, scaled so the moments timeline works unchanged);
    # `lead_user_id` is who turned the page last, for "аня листает".
    activity = Column(String(8), nullable=False, default="watch", server_default="watch")
    read_kind = Column(String(12), nullable=True)
    content_hash = Column(String(64), nullable=True)
    read_units = Column(Integer, nullable=True)
    read_mode = Column(String(8), nullable=False, default="own", server_default="own")
    lead_locator = Column(String(24), nullable=True)
    lead_user_id = Column(String, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)

    link = relationship("PartnerLink")
    host = relationship("User", foreign_keys=[host_id])
    members = relationship("CoViewRoomMember", back_populates="room", cascade="all, delete-orphan", passive_deletes=True)

    __table_args__ = (
        Index(
            "uq_co_view_rooms_one_open_per_link", "link_id", unique=True,
            postgresql_where=(status.in_(["lobby", "live"])),
        ),
    )


class CoViewRoomMember(Base):
    """Someone who has entered a room. Presence is `left_at IS NULL` plus a
    fresh `last_seen_at` (the room socket touches it); a person who closes
    the app without leaving simply stops being fresh."""
    __tablename__ = "co_view_room_members"

    room_id = Column(String, ForeignKey("co_view_rooms.id", ondelete="CASCADE"), primary_key=True)
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    joined_at = Column(DateTime(timezone=True), server_default=func.now())
    last_seen_at = Column(DateTime(timezone=True), server_default=func.now())
    left_at = Column(DateTime(timezone=True), nullable=True)
    # Has a voice token been issued and not yet released. The audio itself
    # is carried by the voice server and is never recorded anywhere.
    voice_on = Column(Boolean, nullable=False, default=False)
    # Reading rooms: where this person is (a locator, see app/co_reading.py),
    # how far through that is (a permille), when they last moved, and the
    # fingerprint of the file *they* opened.
    locator = Column(String(24), nullable=True)
    progress = Column(Integer, nullable=False, default=0, server_default="0")
    locator_at = Column(DateTime(timezone=True), nullable=True)
    content_hash = Column(String(64), nullable=True)
    # Game rooms: "готов" — the ready check before a session (see app/co_play.py).
    ready = Column(Boolean, nullable=False, default=False, server_default="false")

    room = relationship("CoViewRoom", back_populates="members")
    user = relationship("User")


class CoViewRoomEvent(Base):
    """The room's append-only log: chat lines, emoji reactions, signals,
    emotion taps, and the system's own notes (joined, pressed play...).
    `seq` is per room, gapless, and assigned under the room's row lock, so
    a client can ask for "everything after N" and never miss or reorder
    anything. `position_ms` is where in the video it happened — what turns
    reactions into the moments timeline afterwards."""
    __tablename__ = "co_view_room_events"

    id = Column(String, primary_key=True, default=gen_uuid)
    room_id = Column(String, ForeignKey("co_view_rooms.id", ondelete="CASCADE"), nullable=False)
    seq = Column(Integer, nullable=False)
    user_id = Column(String, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    kind = Column(String(16), nullable=False)
    body = Column(Text, nullable=True)
    emoji = Column(String(16), nullable=True)
    position_ms = Column(BigInteger, nullable=True)
    # Reading rooms: the place a reaction or a margin note is pinned to, and
    # a short passage of text it refers to (never more than a line or two).
    locator = Column(String(24), nullable=True)
    quote = Column(String(240), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User")

    __table_args__ = (
        UniqueConstraint("room_id", "seq", name="uq_co_view_room_event_seq"),
        Index("ix_co_view_room_events_room_seq", "room_id", "seq"),
    )


# ---------------------------------------------------------------------------
# Circle reviews ("Рецензия круга") — the joint review of an evening watched
# together, whether in a co-view room or simply logged with a partner.
# Rules: app/circle_review.py; HTTP shape: routers/circle_review.py.
# ---------------------------------------------------------------------------

class CircleReview(Base):
    """One joint review of one evening for a linked circle. Everyone who was
    there writes their own rating, tags and line; nobody sees anyone else's
    until everyone has written (or skipped), or seven days have passed — the
    same sealed-then-opened shape as the album's notes, so a rating is never
    shaped by the other person's number.

    `participant_ids` is who is expected (frozen at creation), not who is in
    the circle today. `moments` is the reactions timeline, computed from the
    room's events when the review opens and only while the circle is premium;
    once stored it stays readable forever, and a circle that subscribes later
    can still unlock it (the events are kept with the room)."""
    __tablename__ = "circle_reviews"

    id = Column(String, primary_key=True, default=gen_uuid)
    link_id = Column(String, ForeignKey("partner_links.id", ondelete="CASCADE"), nullable=False, index=True)
    created_by_id = Column(String, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    origin = Column(String(12), nullable=False, default="logged")  # "room" | "logged"
    room_id = Column(String, ForeignKey("co_view_rooms.id", ondelete="SET NULL"), nullable=True, index=True)

    media_id = Column(String, nullable=False)
    media_type = Column(Enum(MediaType), nullable=False)
    source = Column(String, nullable=False)
    title_ru = Column(String, nullable=True)
    title_en = Column(String, nullable=True)
    poster_url = Column(String, nullable=True)
    year = Column(Integer, nullable=True)

    watched_on = Column(Date, nullable=False)
    participant_ids = Column(JSON, nullable=False, default=list)
    status = Column(String(10), nullable=False, default="open")  # "open" | "revealed"
    moments = Column(JSON, nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    expires_at = Column(DateTime(timezone=True), nullable=False)
    revealed_at = Column(DateTime(timezone=True), nullable=True)

    entries = relationship("CircleReviewEntry", back_populates="review", cascade="all, delete-orphan", passive_deletes=True)

    __table_args__ = (
        Index("ix_circle_reviews_title", "link_id", "source", "media_id"),
    )


class CircleReviewEntry(Base):
    """One person's part of a [CircleReview]. `skipped` means "I'd rather not"
    — it counts as done so the others aren't kept waiting, and shows as a
    quiet blank rather than as a refusal."""
    __tablename__ = "circle_review_entries"

    review_id = Column(String, ForeignKey("circle_reviews.id", ondelete="CASCADE"), primary_key=True)
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    rating = Column(Integer, nullable=True)
    tags = Column(JSON, nullable=False, default=list)
    line = Column(Text, nullable=True)
    skipped = Column(Boolean, nullable=False, default=False)
    submitted_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    review = relationship("CircleReview", back_populates="entries")
    user = relationship("User")


class CoViewRoomGuest(Base):
    """A friend of someone in the circle, invited into one particular room
    without joining the circle. The row only grants access to that room;
    being *in* the room (presence, voice) is an ordinary CoViewRoomMember row.

    Guests can watch, chat, react, signal and talk; they can't move the
    playback, flip the save switch, finish or close the room, invite others,
    or see the circle's review/list — those belong to the circle. status:
      invited   — may enter (a pending invitation, or already inside)
      removed   — a circle member took the invitation back (can be re-invited)
      declined  — the guest said no / left for good (not re-invited to this room)
    """
    __tablename__ = "co_view_room_guests"

    room_id = Column(String, ForeignKey("co_view_rooms.id", ondelete="CASCADE"), primary_key=True)
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True, index=True)
    invited_by_id = Column(String, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    status = Column(String(10), nullable=False, default="invited")
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User", foreign_keys=[user_id])
    invited_by = relationship("User", foreign_keys=[invited_by_id])
