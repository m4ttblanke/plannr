from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker
from config import settings

engine = create_engine(settings.database_url, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)


def verify_connection() -> None:
    """Confirm the database is reachable. Called at startup."""
    with engine.connect() as conn:
        conn.execute(text("SELECT 1"))
    print("Database connection verified.")
