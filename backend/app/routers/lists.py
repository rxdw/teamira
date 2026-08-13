from typing import List as TypingList

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app import models
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
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The lists screen's overview — one card per list, newest first."""
    rows = (
        db.query(models.UserList)
        .filter_by(user_id=current_user.id)
        .order_by(models.UserList.created_at.desc())
        .all()
    )
    return [_to_overview(r) for r in rows]


@router.post("", response_model=UserListOut, status_code=201)
def create_list(
    payload: UserListCreate,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    row = models.UserList(
        user_id=current_user.id,
        name=payload.name.strip(),
        description=payload.description,
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
