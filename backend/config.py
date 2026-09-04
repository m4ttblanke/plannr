from pydantic_settings import BaseSettings
from typing import Optional


class Settings(BaseSettings):
    gemini_api_key: Optional[str] = None
    google_client_id: str
    google_client_secret: str
    google_redirect_uri: str = "http://localhost:8000/auth/callback"
    database_url: str = "postgresql://localhost/plannr"
    stripe_secret_key: Optional[str] = None
    stripe_webhook_secret: Optional[str] = None
    testflight_link: Optional[str] = None
    # Fernet key(s) for encrypting stored Google OAuth tokens at rest. One or
    # more urlsafe-base64 32-byte keys, newest first, comma-separated (extra keys
    # are for rotation — reads try them all). Unset = tokens stored in plaintext
    # (dev only). Generate: python -c "from cryptography.fernet import Fernet;
    # print(Fernet.generate_key().decode())"
    token_enc_key: Optional[str] = None

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8", "extra": "ignore"}


settings = Settings()
