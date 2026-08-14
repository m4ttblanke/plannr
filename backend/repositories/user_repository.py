import json
from database.db_manager import fetch_user_creds, update_creds, init_db as _init_db


def initialize() -> None:
    """Initialize the database. Called once at application startup."""
    _init_db()


def get_google_credentials(email: str) -> dict | None:
    """Return the stored Google OAuth credentials for the given email, or None."""
    raw = fetch_user_creds(email)
    if raw is None:
        return None
    return json.loads(raw)


def upsert_google_credentials(email: str, creds: dict) -> None:
    """Create the user if needed, then store their Google OAuth credentials."""
    fetch_user_creds(email)  # creates user row if this is a new email
    update_creds(email, creds)
