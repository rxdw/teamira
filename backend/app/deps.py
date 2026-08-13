from fastapi import Depends, Header, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app.security import decode_access_token
from app import models

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")


def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
) -> models.User:
    user_id = decode_access_token(token)
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not validate credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )
    user = db.get(models.User, user_id)
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found")
    return user


def require_teamira_admin(x_teamira_admin_key: str = Header(default="")) -> None:
    """Guards the Teamira-picks admin endpoints (app/routers/teamira.py) —
    creating/editing shelves everyone sees, not a per-user action, so this
    intentionally does NOT reuse get_current_user/JWT above. There's no
    role/admin-flag system anywhere else in this app, so a single shared
    secret (TEAMIRA_ADMIN_KEY, see app/config.py) compared against a
    request header is the whole story. An unset key always rejects —
    never treat "not configured" as "wide open"."""
    if not settings.teamira_admin_key or x_teamira_admin_key != settings.teamira_admin_key:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or missing admin key")
