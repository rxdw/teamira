"""The pair album ("Альбом пары") — notes, capsules and the anniversary date
for a linked couple. The rules and the reasoning behind them are in
app/pair_album.py's module docstring; this file is the HTTP shape of them.

Only ever for a circle of exactly two. A company (3+) has no "album" —
notes to *each other* and a letter for *two* don't mean anything for
three — so every endpoint here answers 409 for one, and the client hides
the entry point.

Every read is open to both members regardless of premium. Writes are
open up to a small free allowance (notes per person, one capsule per couple
— see pair_album.FREE_NOTES_PER_AUTHOR / FREE_CAPSULES_PER_LINK) and
unlimited for a premium circle (either member's premium counts, the same
rule as the co-viewing queue — see partner.py::_circle_has_premium). The
anniversary date is premium-only.
"""

from __future__ import annotations

from datetime import date, datetime, timezone
from typing import List as TypingList

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query
from sqlalchemy import desc, func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app import content_filter, models, pair_album, push
from app.database import get_db
from app.deps import get_current_user
from app.routers.partner import _circle_has_premium, _member_ids, get_active_link
from app.schemas import (
    AddCapsuleLetterRequest,
    AlbumFirstEveningOut,
    AlbumNoteOut,
    AlbumPageOut,
    AlbumPagesOut,
    AlbumPersonOut,
    AlbumReactRequest,
    AlbumStatusOut,
    CapsuleLetterOut,
    CapsuleOut,
    CapsulesOut,
    CreateCapsuleRequest,
    PutAlbumNoteRequest,
    TogetherSinceRequest,
)

router = APIRouter(prefix="/partner/album", tags=["pair-album"])

_PAGE_SIZE_MAX = 50


# --- shared guards ----------------------------------------------------------

def _couple_link(db: Session, user: models.User) -> models.PartnerLink:
    link = get_active_link(db, user.id)
    if link is None:
        raise HTTPException(status_code=409, detail="Link with a partner first")
    if len(_member_ids(link)) != 2:
        raise HTTPException(status_code=409, detail="Альбом доступен только паре")
    return link


def _require_premium(db: Session, link: models.PartnerLink) -> None:
    """402, not 409: the request is fine, the circle just hasn't unlocked
    this. The client answers it with the upsell sheet. Used where there is
    no free allowance — today only the anniversary date."""
    if not _circle_has_premium(db, link):
        raise HTTPException(
            status_code=402,
            detail="Годовщина — часть альбома пары: она открывается с подпиской на двоих",
        )


def _require_note_slot(db: Session, link: models.PartnerLink, user_id: str) -> None:
    """Called only when a note is about to be *created* — rewriting one you
    already left costs nothing. 402 for the same reason as above: the
    request is fine, the free notes are just spent."""
    if _circle_has_premium(db, link):
        return
    if pair_album.notes_used(db, link.id, user_id) >= pair_album.FREE_NOTES_PER_AUTHOR:
        raise HTTPException(
            status_code=402,
            detail="Бесплатные записки закончились — с подпиской на двоих их можно оставлять без счёта",
        )


def _require_capsule_slot(db: Session, link: models.PartnerLink) -> None:
    if _circle_has_premium(db, link):
        return
    if pair_album.capsules_used(db, link.id) >= pair_album.FREE_CAPSULES_PER_LINK:
        raise HTTPException(
            status_code=402,
            detail="Бесплатная капсула уже запечатана — новые капсулы открываются с подпиской на двоих",
        )


def _partner_user(link: models.PartnerLink, user_id: str) -> models.User:
    other = link.partner if link.owner_id == user_id else link.owner
    return other


def _name(user: models.User | None) -> str:
    if user is None:
        return "партнёр"
    return (user.display_name or "").strip() or user.username


def _clean_text(text: str, *, field: str, max_chars: int, label: str) -> str:
    body = (text or "").strip()
    if not body:
        raise HTTPException(status_code=400, detail=f"Пустое поле: {label}")
    if len(body) > max_chars:
        raise HTTPException(status_code=400, detail=f"Слишком длинно: {label} — не больше {max_chars} символов")
    try:
        content_filter.check(body, field=field)
    except content_filter.ContentRejected as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return body


def _title_of(page_like) -> str:
    return page_like.title_ru or page_like.title_en or "фильм"


# --- notes: helpers ---------------------------------------------------------

def _note_out(note: models.PairNote, me_id: str, authors: dict[str, models.User], *, reveal_text: bool) -> AlbumNoteOut:
    mine = note.author_id == me_id
    return AlbumNoteOut(
        id=note.id,
        is_mine=mine,
        author_username=(authors.get(note.author_id).username if authors.get(note.author_id) else "—"),
        body=note.body if (mine or reveal_text) else "",
        mood=note.mood,
        reaction=note.reaction,
        # For the partner's note: has *this* person opened it. Mine are always
        # "opened" from my own point of view.
        opened=True if mine else note.opened_at is not None,
        created_at=note.created_at,
    )


def _authors(link: models.PartnerLink) -> dict[str, models.User]:
    return {u.id: u for u in (link.owner, link.partner) if u is not None}


def _group(notes: TypingList[models.PairNote]) -> dict[tuple[str, str, int], TypingList[models.PairNote]]:
    grouped: dict[tuple[str, str, int], TypingList[models.PairNote]] = {}
    for n in notes:
        grouped.setdefault((n.source, n.media_id, n.round), []).append(n)
    return grouped


def _page_out(
    group: TypingList[models.PairNote],
    me_id: str,
    authors: dict[str, models.User],
    *,
    entry_id: str | None,
) -> AlbumPageOut:
    head = group[0]
    revealed = all(n.revealed_at is not None for n in group)
    mine = next((n for n in group if n.author_id == me_id), None)
    theirs = next((n for n in group if n.author_id != me_id), None)
    partner_out = None
    if theirs is not None and revealed:
        partner_out = _note_out(theirs, me_id, authors, reveal_text=True)
    return AlbumPageOut(
        source=head.source,
        media_id=head.media_id,
        media_type=head.media_type.value if hasattr(head.media_type, "value") else head.media_type,
        title_ru=head.title_ru,
        title_en=head.title_en,
        poster_url=head.poster_url,
        year=head.year,
        round=head.round,
        state="revealed" if revealed else "waiting",
        mine=_note_out(mine, me_id, authors, reveal_text=True) if mine is not None else None,
        partner=partner_out,
        partner_sealed=theirs is not None and not revealed,
        entry_id=entry_id,
        evening_on=head.evening_on,
        revealed_at=head.revealed_at if revealed else None,
        unread=bool(theirs is not None and revealed and theirs.opened_at is None),
    )


def _entry_ids(db: Session, link_id: str) -> dict[tuple[str, str], str]:
    rows = (
        db.query(models.CoViewEntry.source, models.CoViewEntry.media_id, models.CoViewEntry.id)
        .filter(
            models.CoViewEntry.link_id == link_id,
            models.CoViewEntry.status == models.CoViewStatus.planned,
        )
        .all()
    )
    return {(s, m): i for s, m, i in rows}


# --- status -----------------------------------------------------------------

@router.get("", response_model=AlbumStatusOut)
def get_album(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    link = get_active_link(db, current_user.id)
    if link is None:
        raise HTTPException(status_code=409, detail="Link with a partner first")
    today = pair_album.utc_today()
    if len(_member_ids(link)) != 2:
        # Reachable so the client can tell "company" from "not linked" and
        # simply not draw the entry point.
        return AlbumStatusOut(is_couple=False, is_premium=False, server_today=today)

    me = current_user.id
    settings = db.get(models.PairAlbumSettings, link.id)
    set_by = None
    if settings is not None and settings.set_by_id:
        setter = db.get(models.User, settings.set_by_id)
        set_by = setter.username if setter else None

    premium = _circle_has_premium(db, link)
    notes = db.query(models.PairNote).filter(models.PairNote.link_id == link.id).all()
    waiting_mine = sum(1 for n in notes if n.revealed_at is None and n.author_id == me)
    waiting_partner = sum(1 for n in notes if n.revealed_at is None and n.author_id != me)
    revealed_groups = _group([n for n in notes if n.revealed_at is not None])
    unread = sum(
        1 for g in revealed_groups.values()
        if any(n.author_id != me and n.opened_at is None for n in g)
    )

    capsules = db.query(models.PairCapsule).filter(models.PairCapsule.link_id == link.id).all()
    reads = {
        r.capsule_id
        for r in db.query(models.PairCapsuleRead).filter(
            models.PairCapsuleRead.user_id == me,
            models.PairCapsuleRead.capsule_id.in_([c.id for c in capsules] or [""]),
        )
    }
    sealed = sum(1 for c in capsules if not pair_album.capsule_is_open(c.opens_on, today))
    ready = sum(1 for c in capsules if pair_album.capsule_is_open(c.opens_on, today) and c.id not in reads)

    watched = (
        db.query(models.CoViewEntry)
        .filter(models.CoViewEntry.link_id == link.id, models.CoViewEntry.status == models.CoViewStatus.watched)
        .order_by(models.CoViewEntry.watched_at.asc().nullslast(), models.CoViewEntry.created_at.asc())
        .all()
    )
    first = None
    if watched:
        f = watched[0]
        first = AlbumFirstEveningOut(
            title_ru=f.title_ru, title_en=f.title_en, poster_url=f.poster_url,
            watched_at=f.watched_at,
        )

    people = [
        AlbumPersonOut(
            user_id=u.id, username=u.username, display_name=u.display_name,
            avatar_preset=u.avatar_preset, avatar_url=u.avatar_url, is_you=u.id == me,
        )
        for u in (link.owner, link.partner) if u is not None
    ]
    # Me first, so the client can lay the pair out the same way on both phones.
    people.sort(key=lambda p: 0 if p.is_you else 1)

    return AlbumStatusOut(
        is_couple=True,
        is_premium=premium,
        server_today=today,
        together_since=settings.together_since if settings else None,
        together_set_by=set_by,
        linked_on=link.created_at.date() if link.created_at else None,
        people=people,
        evenings_together=len(watched),
        first_evening=first,
        pages_count=len(revealed_groups),
        unread_pages=unread,
        waiting_mine=waiting_mine,
        waiting_partner=waiting_partner,
        capsules_sealed=sealed,
        capsules_ready=ready,
        has_content=bool(notes or capsules or (settings and settings.together_since)),
        notes_limit=None if premium else pair_album.FREE_NOTES_PER_AUTHOR,
        notes_used=sum(1 for n in notes if n.author_id == me),
        capsules_limit=None if premium else pair_album.FREE_CAPSULES_PER_LINK,
        capsules_used=len(capsules),
    )


# --- anniversary ------------------------------------------------------------

@router.put("/together-since", response_model=AlbumStatusOut)
def set_together_since(
    payload: TogetherSinceRequest,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    link = _couple_link(db, current_user)
    _require_premium(db, link)
    if payload.together_since is not None:
        problem = pair_album.valid_together_since(payload.together_since)
        if problem:
            raise HTTPException(status_code=400, detail=problem)
    settings = db.get(models.PairAlbumSettings, link.id)
    if settings is None:
        settings = models.PairAlbumSettings(link_id=link.id)
        db.add(settings)
    settings.together_since = payload.together_since
    settings.set_by_id = current_user.id
    db.commit()
    return get_album(current_user=current_user, db=db)


# --- notes ------------------------------------------------------------------

@router.get("/notes/waiting", response_model=TypingList[AlbumPageOut])
def list_waiting_notes(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Every title that has a sealed note on it, from either side — what the
    planned cards decorate themselves with (\"you left one\", \"they left one\").
    The partner's text is never in here, only that it exists."""
    link = _couple_link(db, current_user)
    notes = (
        db.query(models.PairNote)
        .filter(models.PairNote.link_id == link.id, models.PairNote.revealed_at.is_(None))
        .order_by(desc(models.PairNote.updated_at))
        .all()
    )
    authors = _authors(link)
    entries = _entry_ids(db, link.id)
    return [
        _page_out(g, current_user.id, authors, entry_id=entries.get((key[0], key[1])))
        for key, g in _group(notes).items()
    ]


@router.put("/notes", response_model=AlbumPageOut)
def put_note(
    payload: PutAlbumNoteRequest,
    background_tasks: BackgroundTasks,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Leaves (or rewrites) *my* note on this title for the coming evening.
    One per person per viewing. Idempotent by (title, me): calling it again
    edits the same sealed note."""
    link = _couple_link(db, current_user)

    body = _clean_text(payload.body, field="note", max_chars=pair_album.NOTE_MAX_CHARS, label="записка")
    mood = payload.mood
    if mood is not None and mood not in pair_album.ALLOWED_MOODS:
        raise HTTPException(status_code=400, detail="Неизвестный значок")

    item = payload.item
    # Lock the shared entry (when there is one) so this can't interleave with
    # "mark watched": either the note lands first and gets revealed with the
    # rest, or the evening is already watched and the write is refused —
    # never a note stranded sealed on a finished evening.
    entry = (
        db.query(models.CoViewEntry)
        .filter_by(link_id=link.id, source=item.source, media_id=item.id)
        .with_for_update()
        .first()
    )
    if entry is not None and entry.status == models.CoViewStatus.watched:
        raise HTTPException(
            status_code=409,
            detail="Этот вечер уже прошёл — запланируйте его снова, чтобы оставить записку",
        )

    rnd = pair_album.current_round(db, link.id, item.source, item.id)

    def _find() -> models.PairNote | None:
        return (
            db.query(models.PairNote)
            .filter_by(link_id=link.id, source=item.source, media_id=item.id,
                       author_id=current_user.id, round=rnd)
            .first()
        )

    note = _find()
    created = False
    if note is None:
        # Only a *new* note takes a slot from the free allowance; rewriting
        # one that's already sealed never does, so this sits inside the
        # creation branch. Checked then committed in separate steps, so two
        # devices of one person racing on two different titles could land
        # one note over — a soft ceiling, deliberately not worth a lock.
        _require_note_slot(db, link, current_user.id)
        pending = (
            db.query(models.PairNote)
            .filter(
                models.PairNote.link_id == link.id,
                models.PairNote.author_id == current_user.id,
                models.PairNote.revealed_at.is_(None),
            )
            .count()
        )
        if pending >= pair_album.MAX_PENDING_NOTES_PER_AUTHOR:
            raise HTTPException(status_code=409, detail="Слишком много неоткрытых записок — сначала посмотрите что-нибудь вместе")
        note = models.PairNote(
            link_id=link.id, author_id=current_user.id,
            source=item.source, media_id=item.id, media_type=item.media_type, round=rnd,
            body=body, mood=mood,
        )
        db.add(note)
        created = True
    else:
        note.body = body
        note.mood = mood
    # Snapshot fields track the latest metadata either side sent.
    note.title_ru = item.title.ru
    note.title_en = item.title.en
    note.poster_url = item.poster_url
    note.year = item.year

    try:
        db.commit()
    except IntegrityError:
        # Two devices submitting at once: the loser finds the winner's row
        # and edits it instead — same end state as sequential calls.
        db.rollback()
        note = _find()
        if note is None:
            raise HTTPException(status_code=409, detail="Не получилось сохранить записку — попробуйте ещё раз")
        note.body = body
        note.mood = mood
        created = False
        db.commit()
    db.refresh(note)

    if created:
        partner = _partner_user(link, current_user.id)
        if partner is not None:
            background_tasks.add_task(
                push.notify_album_note, partner.id, _name(current_user),
                item.title.ru or item.title.en or "фильм",
            )

    group = (
        db.query(models.PairNote)
        .filter_by(link_id=link.id, source=item.source, media_id=item.id, round=rnd)
        .all()
    )
    entries = _entry_ids(db, link.id)
    return _page_out(group, current_user.id, _authors(link), entry_id=entries.get((item.source, item.id)))


@router.delete("/notes/{note_id}", status_code=204)
def delete_note(
    note_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Takes back my own sealed note. Not allowed once it's been revealed —
    by then it has been read and is a record of the evening."""
    link = _couple_link(db, current_user)
    note = db.query(models.PairNote).filter_by(id=note_id, link_id=link.id).first()
    if note is None or note.author_id != current_user.id:
        raise HTTPException(status_code=404, detail="Not found")
    if note.revealed_at is not None:
        raise HTTPException(status_code=409, detail="Записка уже открыта — её нельзя убрать")
    db.delete(note)
    db.commit()


@router.get("/pages", response_model=AlbumPagesOut)
def list_pages(
    before: datetime | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=_PAGE_SIZE_MAX),
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The shared book itself: revealed evenings, newest first. Reading is
    never premium-gated."""
    link = _couple_link(db, current_user)
    q = (
        db.query(
            models.PairNote.source, models.PairNote.media_id, models.PairNote.round,
            func.max(models.PairNote.revealed_at).label("at"),
        )
        .filter(models.PairNote.link_id == link.id, models.PairNote.revealed_at.isnot(None))
    )
    if before is not None:
        b = before if before.tzinfo else before.replace(tzinfo=timezone.utc)
        q = q.filter(models.PairNote.revealed_at < b)
    keys = (
        q.group_by(models.PairNote.source, models.PairNote.media_id, models.PairNote.round)
        .order_by(desc("at"))
        .limit(limit + 1)
        .all()
    )
    has_more = len(keys) > limit
    keys = keys[:limit]
    if not keys:
        return AlbumPagesOut(items=[], next_before=None)

    authors = _authors(link)
    items: TypingList[AlbumPageOut] = []
    for source, media_id, rnd, _at in keys:
        group = (
            db.query(models.PairNote)
            .filter_by(link_id=link.id, source=source, media_id=media_id, round=rnd)
            .all()
        )
        items.append(_page_out(group, current_user.id, authors, entry_id=None))
    return AlbumPagesOut(items=items, next_before=keys[-1][3] if has_more else None)


def _partner_note(db: Session, link: models.PartnerLink, note_id: str, me_id: str) -> models.PairNote:
    note = db.query(models.PairNote).filter_by(id=note_id, link_id=link.id).first()
    if note is None or note.author_id == me_id:
        raise HTTPException(status_code=404, detail="Not found")
    if note.revealed_at is None:
        raise HTTPException(status_code=409, detail="Записка ещё запечатана")
    return note


@router.post("/notes/{note_id}/opened", status_code=204)
def mark_note_opened(
    note_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The reader has watched the partner's note open. Only ever moves
    null → now, so the reveal plays once per person."""
    link = _couple_link(db, current_user)
    note = _partner_note(db, link, note_id, current_user.id)
    if note.opened_at is None:
        note.opened_at = datetime.now(timezone.utc)
        db.commit()


@router.post("/notes/{note_id}/react", status_code=204)
def react_to_note(
    note_id: str,
    payload: AlbumReactRequest,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The recipient's one-emoji answer to a revealed note. Replying is not
    a write in the premium sense — it changes nothing that was written — so
    it's open to both members regardless of plan."""
    link = _couple_link(db, current_user)
    note = _partner_note(db, link, note_id, current_user.id)
    if payload.emoji is not None and payload.emoji not in pair_album.ALLOWED_REACTIONS:
        raise HTTPException(status_code=400, detail="Неизвестная реакция")
    note.reaction = payload.emoji
    if note.opened_at is None:
        note.opened_at = datetime.now(timezone.utc)
    db.commit()


# --- capsules ---------------------------------------------------------------

def _capsule_out(
    db: Session,
    capsule: models.PairCapsule,
    letters: TypingList[models.PairCapsuleLetter],
    me_id: str,
    authors: dict[str, models.User],
    read_by_me: bool,
    today: date,
) -> CapsuleOut:
    is_open = pair_album.capsule_is_open(capsule.opens_on, today)
    mine = next((l for l in letters if l.author_id == me_id), None)
    theirs = next((l for l in letters if l.author_id != me_id), None)
    creator = authors.get(capsule.created_by_id) if capsule.created_by_id else None
    return CapsuleOut(
        id=capsule.id,
        title=capsule.title,
        opens_on=capsule.opens_on,
        created_at=capsule.created_at,
        created_by_username=creator.username if creator else None,
        created_by_me=capsule.created_by_id == me_id,
        state="open" if is_open else "sealed",
        days_left=0 if is_open else pair_album.days_until(capsule.opens_on, today),
        my_letter_sealed=mine is not None,
        partner_letter_sealed=theirs is not None,
        # Sealed text is never serialized for anyone, its author included.
        letters=[
            CapsuleLetterOut(
                is_mine=l.author_id == me_id,
                author_username=(authors.get(l.author_id).username if authors.get(l.author_id) else "—"),
                body=l.body,
                sealed_at=l.sealed_at,
            )
            for l in sorted(letters, key=lambda x: x.sealed_at)
        ] if is_open else [],
        opened_by_me=read_by_me,
        can_delete=bool(
            not is_open and capsule.created_by_id == me_id and theirs is None
        ),
    )


def _capsules_for(db: Session, link: models.PartnerLink, me_id: str) -> TypingList[CapsuleOut]:
    today = pair_album.utc_today()
    capsules = db.query(models.PairCapsule).filter_by(link_id=link.id).all()
    if not capsules:
        return []
    ids = [c.id for c in capsules]
    letters_by: dict[str, TypingList[models.PairCapsuleLetter]] = {}
    for l in db.query(models.PairCapsuleLetter).filter(models.PairCapsuleLetter.capsule_id.in_(ids)):
        letters_by.setdefault(l.capsule_id, []).append(l)
    reads = {
        r.capsule_id
        for r in db.query(models.PairCapsuleRead).filter(
            models.PairCapsuleRead.user_id == me_id, models.PairCapsuleRead.capsule_id.in_(ids),
        )
    }
    authors = _authors(link)
    out = [
        _capsule_out(db, c, letters_by.get(c.id, []), me_id, authors, c.id in reads, today)
        for c in capsules
    ]
    # Still sealed first (soonest to open on top), then the opened ones, most
    # recently opened first.
    out.sort(key=lambda c: (0, c.opens_on) if c.state == "sealed" else (1, -c.opens_on.toordinal()))
    return out


def _one_capsule(db: Session, link: models.PartnerLink, capsule_id: str, me_id: str) -> CapsuleOut:
    for c in _capsules_for(db, link, me_id):
        if c.id == capsule_id:
            return c
    raise HTTPException(status_code=404, detail="Not found")


def _get_capsule(db: Session, link: models.PartnerLink, capsule_id: str) -> models.PairCapsule:
    capsule = db.query(models.PairCapsule).filter_by(id=capsule_id, link_id=link.id).first()
    if capsule is None:
        raise HTTPException(status_code=404, detail="Not found")
    return capsule


_RU_MONTHS_GEN = [
    "января", "февраля", "марта", "апреля", "мая", "июня",
    "июля", "августа", "сентября", "октября", "ноября", "декабря",
]


def _ru_date(d: date) -> str:
    return f"{d.day} {_RU_MONTHS_GEN[d.month - 1]} {d.year}"


@router.get("/capsules", response_model=CapsulesOut)
def list_capsules(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    link = _couple_link(db, current_user)
    return CapsulesOut(items=_capsules_for(db, link, current_user.id))


@router.post("/capsules", response_model=CapsuleOut, status_code=201)
def create_capsule(
    payload: CreateCapsuleRequest,
    background_tasks: BackgroundTasks,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Seals a capsule with the creator's own letter already inside. The
    date is fixed for good; the other side is told and can add theirs any
    time before it opens."""
    link = _couple_link(db, current_user)

    problem = pair_album.valid_opens_on(payload.opens_on)
    if problem:
        raise HTTPException(status_code=400, detail=problem)
    body = _clean_text(payload.body, field="letter", max_chars=pair_album.CAPSULE_LETTER_MAX_CHARS, label="письмо")
    title = None
    if payload.title and payload.title.strip():
        title = _clean_text(payload.title, field="title", max_chars=pair_album.CAPSULE_TITLE_MAX_CHARS, label="название")

    _require_capsule_slot(db, link)

    today = pair_album.utc_today()
    unopened = sum(
        1 for c in db.query(models.PairCapsule).filter_by(link_id=link.id).all()
        if not pair_album.capsule_is_open(c.opens_on, today)
    )
    if unopened >= pair_album.MAX_SEALED_CAPSULES_PER_LINK:
        raise HTTPException(
            status_code=409,
            detail=f"Одновременно можно хранить не больше {pair_album.MAX_SEALED_CAPSULES_PER_LINK} запечатанных капсул",
        )

    capsule = models.PairCapsule(
        link_id=link.id, created_by_id=current_user.id, title=title, opens_on=payload.opens_on,
    )
    db.add(capsule)
    db.flush()
    db.add(models.PairCapsuleLetter(capsule_id=capsule.id, author_id=current_user.id, body=body))
    db.commit()

    partner = _partner_user(link, current_user.id)
    if partner is not None:
        background_tasks.add_task(
            push.notify_capsule_created, partner.id, _name(current_user), _ru_date(payload.opens_on),
        )
    return _one_capsule(db, link, capsule.id, current_user.id)


@router.post("/capsules/{capsule_id}/letter", response_model=CapsuleOut)
def add_capsule_letter(
    capsule_id: str,
    payload: AddCapsuleLetterRequest,
    background_tasks: BackgroundTasks,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    # Not premium-gated, on purpose: the capsule already exists (it took a
    # free slot or a premium one), and the other half of a promise for two
    # can't sit behind a wall — a free couple's one capsule would otherwise
    # stay half-empty, and so would one made while premium was active.
    link = _couple_link(db, current_user)
    capsule = _get_capsule(db, link, capsule_id)
    if pair_album.capsule_is_open(capsule.opens_on):
        raise HTTPException(status_code=409, detail="Капсула уже открылась — письмо не успело попасть внутрь")
    body = _clean_text(payload.body, field="letter", max_chars=pair_album.CAPSULE_LETTER_MAX_CHARS, label="письмо")
    if db.query(models.PairCapsuleLetter).filter_by(capsule_id=capsule.id, author_id=current_user.id).first():
        raise HTTPException(status_code=409, detail="Ваше письмо уже запечатано в этой капсуле")
    db.add(models.PairCapsuleLetter(capsule_id=capsule.id, author_id=current_user.id, body=body))
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=409, detail="Ваше письмо уже запечатано в этой капсуле")

    partner = _partner_user(link, current_user.id)
    if partner is not None:
        background_tasks.add_task(push.notify_capsule_letter, partner.id, _name(current_user))
    return _one_capsule(db, link, capsule.id, current_user.id)


@router.post("/capsules/{capsule_id}/open", response_model=CapsuleOut)
def open_capsule(
    capsule_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Records that this person has opened an open capsule (so the
    ceremony plays once for each of the two) and returns it with its
    letters. Refuses before the date — judged by the server's clock."""
    link = _couple_link(db, current_user)
    capsule = _get_capsule(db, link, capsule_id)
    if not pair_album.capsule_is_open(capsule.opens_on):
        raise HTTPException(status_code=409, detail="Ещё рано — капсула откроется позже")
    if db.get(models.PairCapsuleRead, (capsule.id, current_user.id)) is None:
        db.add(models.PairCapsuleRead(capsule_id=capsule.id, user_id=current_user.id))
        try:
            db.commit()
        except IntegrityError:
            db.rollback()  # the other device got there first; same end state
    return _one_capsule(db, link, capsule.id, current_user.id)


@router.delete("/capsules/{capsule_id}", status_code=204)
def delete_capsule(
    capsule_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The creator can take a capsule back — a wrong date, a change of mind
    — but only before it opens and only while nobody else's words are in
    it. After that it's a promise for two."""
    link = _couple_link(db, current_user)
    capsule = _get_capsule(db, link, capsule_id)
    if capsule.created_by_id != current_user.id:
        raise HTTPException(status_code=403, detail="Убрать капсулу может только тот, кто её запечатал")
    if pair_album.capsule_is_open(capsule.opens_on):
        raise HTTPException(status_code=409, detail="Капсула уже открылась")
    partner_letter = (
        db.query(models.PairCapsuleLetter)
        .filter(models.PairCapsuleLetter.capsule_id == capsule.id,
                models.PairCapsuleLetter.author_id != current_user.id)
        .first()
    )
    if partner_letter is not None:
        raise HTTPException(status_code=409, detail="В капсуле уже лежит письмо партнёра — её нельзя убрать")
    db.delete(capsule)
    db.commit()
