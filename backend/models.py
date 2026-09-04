import uuid
from datetime import datetime
from sqlalchemy import String, Text, DateTime, ForeignKey, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID, ARRAY
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship
from sqlalchemy.sql import func


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    email: Mapped[str] = mapped_column(String, unique=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    credentials: Mapped["GoogleCredentials"] = relationship(
        "GoogleCredentials", back_populates="user", uselist=False, cascade="all, delete-orphan"
    )


class GoogleCredentials(Base):
    __tablename__ = "google_credentials"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    # Google OAuth tokens — Fernet-encrypted at rest when TOKEN_ENC_KEY is set
    # (stored with an "enc:v1:" prefix), plaintext otherwise. Always read/written
    # through repositories.user_repository, which handles (de)cryption.
    access_token: Mapped[str | None] = mapped_column(Text, nullable=True)
    refresh_token: Mapped[str] = mapped_column(Text, nullable=False)
    token_uri: Mapped[str] = mapped_column(Text, nullable=False)
    scopes: Mapped[list[str] | None] = mapped_column(ARRAY(Text), nullable=True)
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    # SHA-256 hash of the opaque bearer token handed to the iOS app after sign-in
    # and required on every per-user request. Rotated on each successful OAuth
    # callback; cleared implicitly when the row is deleted (account deletion).
    # NULL only for rows written before this column existed — those users must
    # sign in again.
    session_token: Mapped[str | None] = mapped_column(Text, nullable=True, unique=True)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )

    user: Mapped["User"] = relationship("User", back_populates="credentials")

    __table_args__ = (UniqueConstraint("user_id", name="uq_google_credentials_user"),)
