from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.database import get_db
from app import models
from app.schemas import RegisterRequest, LoginRequest, TokenResponse, UserOut
from app.security import hash_password, verify_password, create_access_token
from app.deps import get_current_user

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
def register(payload: RegisterRequest, db: Session = Depends(get_db)):
    existing = db.query(models.User).filter(models.User.username == payload.username).first()
    if existing:
        raise HTTPException(status_code=400, detail="Username already taken")

    try:
        password_hash = hash_password(payload.password)
    except ValueError:
        raise HTTPException(status_code=400, detail="Password is too long")

    # See friends.py's own docstring on InviteOut — a code is minted
    # lazily per account and reusable by anyone, so this is just a
    # lookup, not a one-time-use redemption. Matched case-insensitively
    # since codes are meant to be read aloud/typed by hand. An unknown
    # code (typo, or simply none entered) is silently ignored rather than
    # blocking account creation over it.
    referred_by_id = None
    code = (payload.referral_code or "").strip()
    if code:
        referrer = (
            db.query(models.User)
            .filter(func.upper(models.User.invite_code) == code.upper())
            .first()
        )
        if referrer:
            referred_by_id = referrer.id

    user = models.User(
        username=payload.username,
        password_hash=password_hash,
        referred_by_id=referred_by_id,
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    token = create_access_token(user.id)
    return TokenResponse(access_token=token)


@router.post("/login", response_model=TokenResponse)
def login(payload: LoginRequest, db: Session = Depends(get_db)):
    user = db.query(models.User).filter(models.User.username == payload.username).first()
    if not user or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid username or password")

    token = create_access_token(user.id)
    return TokenResponse(access_token=token)


@router.get("/me", response_model=UserOut)
def me(current_user: models.User = Depends(get_current_user)):
    return current_user
