from contextlib import contextmanager
from sqlalchemy import text
from sqlalchemy.orm import Session
from db import SessionLocal, engine
from models import User, GoogleCredentials


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
            "token": cred.access_token,
            "refresh_token": cred.refresh_token,
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
            user.credentials.access_token = creds.get("token")
            user.credentials.refresh_token = creds["refresh_token"]
            user.credentials.token_uri = creds["token_uri"]
            user.credentials.scopes = creds.get("scopes")
        else:
            db.add(GoogleCredentials(
                user_id=user.id,
                access_token=creds.get("token"),
                refresh_token=creds["refresh_token"],
                token_uri=creds["token_uri"],
                scopes=creds.get("scopes"),
            ))
