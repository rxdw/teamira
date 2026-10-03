from typing import List as TypingList, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from sqlalchemy import and_, or_
from sqlalchemy.orm import Session

from app import content_filter, models
from app.database import get_db
from app.deps import get_current_user
from app.schemas import (
    AddListItemRequest,
    UserListCreate,
    UserListDetailOut,
    UserListItemOut,
    UserListOut,
    UserListUpdate,
)

router = APIRouter(prefix="/lists", tags=["lists"])

# Matches the page size routers/sincerity.py uses for the same
# cursor-pagination shape (see get_lists below).
_PAGE_SIZE = 30


def _get_owned_list(db: Session, user_id: str, list_id: str) -> models.UserList:
    row = (
        db.query(models.UserList)
        .filter_by(id=list_id, user_id=user_id)
        .first()
    )
    if row is None:
        raise HTTPException(status_code=404, detail="List not found")
    return row


def _to_overview(row: models.UserList) -> UserListOut:
    posters = [it.poster_url for it in row.items[:4] if it.poster_url]
    return UserListOut(
        id=row.id,
        name=row.name,
        description=row.description,
        item_count=len(row.items),
        preview_posters=posters,
        created_at=row.created_at,
    )


@router.get("", response_model=TypingList[UserListOut])
def get_lists(
    response: Response,
    before: Optional[str] = Query(
        default=None, description="list id to page before, for older lists"
    ),
    limit: int = Query(default=_PAGE_SIZE, ge=1, le=200),
    full: bool = Query(
        default=False,
        description=(
            "bypass pagination and return every list in one response — for "
            "pickers (e.g. the \"add to list\" sheet) that need the complete "
            "set to search through, not the lists screen's own scrolling view."
        ),
    ),
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The lists screen's overview — one card per list, newest first.
    The body is still the same bare array it's always been; pagination
    rides in the `X-Has-More` response header instead of reshaping it
    (see GET /diary's own docstring for why)."""
    q = db.query(models.UserList).filter_by(user_id=current_user.id)

    if full:
        rows = q.order_by(models.UserList.created_at.desc(), models.UserList.id.desc()).all()
        response.headers["X-Has-More"] = "false"
        return [_to_overview(r) for r in rows]

    if before:
        anchor = (
            db.query(models.UserList)
            .filter(models.UserList.id == before, models.UserList.user_id == current_user.id)
            .first()
        )
        if anchor is not None:
            q = q.filter(
                or_(
                    models.UserList.created_at < anchor.created_at,
                    and_(models.UserList.created_at == anchor.created_at, models.UserList.id < anchor.id),
                )
            )
    rows = q.order_by(models.UserList.created_at.desc(), models.UserList.id.desc()).limit(limit + 1).all()
    has_more = len(rows) > limit
    rows = rows[:limit]
    response.headers["X-Has-More"] = "true" if has_more else "false"
    return [_to_overview(r) for r in rows]


@router.post("", response_model=UserListOut, status_code=201)
def create_list(
    payload: UserListCreate,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    # A list name and description are visible to friends on the profile
    # screen (see routers/friends.py::get_friend_collections), which makes
    # them user-generated content like any other — same filter as the
    # nickname and status line. See app/content_filter.py.
    try:
        name = content_filter.check(payload.name.strip(), field="list name")
        description = content_filter.check(payload.description, field="list description")
    except content_filter.ContentRejected as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    row = models.UserList(
        user_id=current_user.id,
        name=name,
        description=description,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return _to_overview(row)


@router.get("/membership", response_model=TypingList[str])
def get_membership(
    media_id: str,
    source: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Which of the user's lists already contain this title — powers the
    checkmarks in the "add to list" sheet on the title screen."""
    rows = (
        db.query(models.UserListItem.list_id)
        .join(models.UserList)
        .filter(
            models.UserList.user_id == current_user.id,
            models.UserListItem.media_id == media_id,
            models.UserListItem.source == source,
        )
        .all()
    )
    return [r[0] for r in rows]


@router.get("/{list_id}", response_model=UserListDetailOut)
def get_list_detail(
    list_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    row = _get_owned_list(db, current_user.id, list_id)
    return UserListDetailOut(
        id=row.id,
        name=row.name,
        description=row.description,
        items=[UserListItemOut.model_validate(it) for it in row.items],
        created_at=row.created_at,
    )


@router.patch("/{list_id}", response_model=UserListOut)
def update_list(
    list_id: str,
    payload: UserListUpdate,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    row = _get_owned_list(db, current_user.id, list_id)
    if payload.name is not None:
        row.name = payload.name.strip()
    if payload.description is not None:
        row.description = payload.description
    db.commit()
    db.refresh(row)
    return _to_overview(row)


@router.delete("/{list_id}", status_code=204)
def delete_list(
    list_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    row = _get_owned_list(db, current_user.id, list_id)
    db.delete(row)
    db.commit()


@router.post("/{list_id}/items", response_model=UserListDetailOut, status_code=201)
def add_item(
    list_id: str,
    payload: AddListItemRequest,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    row = _get_owned_list(db, current_user.id, list_id)
    item = payload.item

    existing = (
        db.query(models.UserListItem)
        .filter_by(list_id=row.id, source=item.source, media_id=item.id)
        .first()
    )
    if existing is None:
        db.add(models.UserListItem(
            list_id=row.id,
            media_id=item.id,
            media_type=item.media_type,
            source=item.source,
            title_ru=item.title.ru,
            title_en=item.title.en,
            poster_url=item.poster_url,
            year=item.year,
            genres=item.genres,
            rating=item.rating,
        ))
        db.commit()
        db.refresh(row)

    return UserListDetailOut(
        id=row.id,
        name=row.name,
        description=row.description,
        items=[UserListItemOut.model_validate(it) for it in row.items],
        created_at=row.created_at,
    )


@router.delete("/{list_id}/items/{item_id}", response_model=UserListDetailOut)
def remove_item(
    list_id: str,
    item_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    row = _get_owned_list(db, current_user.id, list_id)
    item = db.query(models.UserListItem).filter_by(id=item_id, list_id=row.id).first()
    if item is None:
        raise HTTPException(status_code=404, detail="Item not in this list")
    db.delete(item)
    db.commit()
    db.refresh(row)
    return UserListDetailOut(
        id=row.id,
        name=row.name,
        description=row.description,
        items=[UserListItemOut.model_validate(it) for it in row.items],
        created_at=row.created_at,
    )
