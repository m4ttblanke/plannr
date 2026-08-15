from pydantic_settings import BaseSettings
from typing import Optional


class Settings(BaseSettings):
    gemini_api_key: Optional[str] = None
    google_client_id: str
    google_client_secret: str
    google_redirect_uri: str = "http://localhost:8000/auth/callback"
    database_url: str = "postgresql://localhost/plannr"

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8", "extra": "ignore"}


settings = Settings()
