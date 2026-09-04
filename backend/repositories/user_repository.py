import secrets
from contextlib import contextmanager
from sqlalchemy import text
from sqlalchemy.orm import Session
from db import SessionLocal, engine
from models import User, GoogleCredentials
from crypto import (
    encrypt_token,
    decrypt_token,
    hash_session_token,
    session_token_matches,
)


@contextmanager
def _session():
    db: Session = SessionLocal()
    try:
        yield db
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def initialize() -> None:
    """Verify database connectivity at startup."""
    with engine.connect() as conn:
        conn.execute(text("SELECT 1"))
    print("Database connection verified.")


def get_google_credentials(email: str) -> dict | None:
    """Return the stored Google OAuth credentials for the given email, or None."""
    with _session() as db:
        user = db.query(User).filter(User.email == email).first()
        if not user or not user.credentials:
            return None
        cred = user.credentials
        return {
            "token": decrypt_token(cred.access_token),
            "refresh_token": decrypt_token(cred.refresh_token),
            "token_uri": cred.token_uri,
            "scopes": cred.scopes,
        }


def user_exists(email: str) -> bool:
    """True if a user record exists for this email (with or without credentials)."""
    with _session() as db:
        return db.query(User.id).filter(User.email == email).first() is not None


def rotate_session_token(email: str) -> str | None:
    """Issue a fresh opaque session token for the user's credentials row and
    return it (in the clear — the caller hands it to the app). Only a SHA-256
    hash of it is stored. Returns None if the user has no credentials row yet
    (shouldn't happen — this is called straight after upsert_google_credentials)."""
    token = secrets.token_urlsafe(32)
    with _session() as db:
        user = db.query(User).filter(User.email == email).first()
        if not user or not user.credentials:
            return None
        user.credentials.session_token = hash_session_token(token)
    return token


def authenticate(email: str, token: str | None) -> dict | None:
    """Return the stored Google OAuth credentials (decrypted) for `email` **only
    if** `token` matches the session token issued to that account. Returns None
    for an unknown account, a row with no session token (pre-migration), or a
    token mismatch. The comparison is constant-time."""
    if not token:
        return None
    with _session() as db:
        user = db.query(User).filter(User.email == email).first()
        if not user or not user.credentials:
            return None
        cred = user.credentials
        if not session_token_matches(token, cred.session_token):
            return None
        return {
            "token": decrypt_token(cred.access_token),
            "refresh_token": decrypt_token(cred.refresh_token),
            "token_uri": cred.token_uri,
            "scopes": cred.scopes,
        }


def delete_user(email: str) -> None:
    """Delete the user record for the given email, cascading to their stored credentials."""
    with _session() as db:
        user = db.query(User).filter(User.email == email).first()
        if user:
            db.delete(user)


def upsert_google_credentials(email: str, creds: dict) -> None:
    """Create the user if needed, then store their Google OAuth credentials."""
    with _session() as db:
        user = db.query(User).filter(User.email == email).first()
        if not user:
            user = User(email=email)
            db.add(user)
            db.flush()  # populate user.id before inserting credentials

        if user.credentials:
            user.credentials.access_token = encrypt_token(creds.get("token"))
            user.credentials.refresh_token = encrypt_token(creds["refresh_token"])
            user.credentials.token_uri = creds["token_uri"]
            user.credentials.scopes = creds.get("scopes")
        else:
            db.add(GoogleCredentials(
                user_id=user.id,
                access_token=encrypt_token(creds.get("token")),
                refresh_token=encrypt_token(creds["refresh_token"]),
                token_uri=creds["token_uri"],
                scopes=creds.get("scopes"),
            ))
