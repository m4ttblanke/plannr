"""At-rest protection for the secrets in `google_credentials`.

- **Google OAuth `access_token` / `refresh_token`** need to be recoverable (we
  replay them to Google), so they are encrypted with Fernet (AES-128-CBC +
  HMAC). `TOKEN_ENC_KEY` holds one or more keys, newest first; writes use the
  first, reads try all (key rotation). No key configured → pass-through, so
  local dev without the key still runs (with a startup warning).

- **The session bearer token** is a 256-bit random value we only ever need to
  *compare*, so it is stored as an unsalted SHA-256 hash. A DB leak then yields
  no usable tokens and there is no key to steal.

Legacy plaintext rows (written before this module existed) are detected by the
absence of the `enc:v1:` prefix and returned as-is, so the columns migrate
lazily the next time each row is written (i.e. on the user's next sign-in).
"""

import hashlib
import hmac
import logging
from typing import Optional

from cryptography.fernet import Fernet, InvalidToken, MultiFernet

from config import settings

logger = logging.getLogger("plannr")

_ENC_PREFIX = "enc:v1:"


def _load_fernet() -> Optional[MultiFernet]:
    raw = (settings.token_enc_key or "").strip()
    if not raw:
        logger.warning(
            "TOKEN_ENC_KEY not set — Google OAuth tokens are stored in PLAINTEXT. "
            "Set it in production (see docs/DEPLOY.md)."
        )
        return None
    try:
        keys = [Fernet(k.strip()) for k in raw.split(",") if k.strip()]
        if not keys:
            raise ValueError("no keys parsed from TOKEN_ENC_KEY")
        return MultiFernet(keys)
    except Exception:
        logger.error(
            "TOKEN_ENC_KEY is set but is not a valid Fernet key list — refusing to "
            "start with an unusable key.",
            exc_info=True,
        )
        raise


_fernet: Optional[MultiFernet] = _load_fernet()


def encryption_enabled() -> bool:
    return _fernet is not None


def encrypt_token(plaintext: Optional[str]) -> Optional[str]:
    """Encrypt a token for storage. Returns the input unchanged when no key is
    configured (dev) or the input is None."""
    if plaintext is None or _fernet is None:
        return plaintext
    return _ENC_PREFIX + _fernet.encrypt(plaintext.encode()).decode()


def decrypt_token(stored: Optional[str]) -> Optional[str]:
    """Inverse of `encrypt_token`. A value without the `enc:v1:` prefix is treated
    as legacy plaintext and returned as-is."""
    if stored is None:
        return None
    if not stored.startswith(_ENC_PREFIX):
        return stored  # legacy plaintext, or a dev row written without a key
    if _fernet is None:
        logger.error("Stored token is encrypted but TOKEN_ENC_KEY is not set.")
        return None
    try:
        return _fernet.decrypt(stored[len(_ENC_PREFIX):].encode()).decode()
    except InvalidToken:
        logger.error("Could not decrypt a stored token (wrong or rotated-out key).")
        return None


def hash_session_token(token: str) -> str:
    """One-way hash of the session bearer token, for storage and comparison."""
    return hashlib.sha256(token.encode()).hexdigest()


def session_token_matches(provided: Optional[str], stored_hash: Optional[str]) -> bool:
    """Constant-time check of a presented bearer token against the stored hash."""
    if not provided or not stored_hash:
        return False
    return hmac.compare_digest(hash_session_token(provided), stored_hash)
