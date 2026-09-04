"""Tests for crypto.py — at-rest encryption of OAuth tokens and hashing of the
session bearer token."""

import pytest
from cryptography.fernet import Fernet, MultiFernet

import crypto


@pytest.fixture
def with_key(monkeypatch):
    """Run the token (en/de)cryption helpers with a real Fernet key installed."""
    fernet = MultiFernet([Fernet(Fernet.generate_key())])
    monkeypatch.setattr(crypto, "_fernet", fernet)
    return fernet


@pytest.fixture
def no_key(monkeypatch):
    monkeypatch.setattr(crypto, "_fernet", None)


# ── Reversible token encryption ─────────────────────────────────────────────

def test_encrypt_then_decrypt_round_trips(with_key):
    ct = crypto.encrypt_token("ya29.super-secret-access-token")
    assert ct != "ya29.super-secret-access-token"
    assert ct.startswith("enc:v1:")
    assert crypto.decrypt_token(ct) == "ya29.super-secret-access-token"


def test_none_passes_through(with_key):
    assert crypto.encrypt_token(None) is None
    assert crypto.decrypt_token(None) is None


def test_legacy_plaintext_is_returned_unchanged(with_key):
    # A row written before encryption existed has no prefix — read it as-is.
    assert crypto.decrypt_token("1//0legacy-refresh-token") == "1//0legacy-refresh-token"


def test_without_a_key_encryption_is_a_no_op(no_key):
    assert crypto.encrypt_token("tok") == "tok"
    assert crypto.decrypt_token("tok") == "tok"


def test_ciphertext_from_a_different_key_fails_closed(with_key, monkeypatch):
    ct = crypto.encrypt_token("secret")
    monkeypatch.setattr(crypto, "_fernet", MultiFernet([Fernet(Fernet.generate_key())]))
    assert crypto.decrypt_token(ct) is None


def test_key_rotation_reads_old_ciphertext(monkeypatch):
    old = Fernet(Fernet.generate_key())
    new = Fernet(Fernet.generate_key())
    monkeypatch.setattr(crypto, "_fernet", MultiFernet([old]))
    ct = crypto.encrypt_token("secret")
    # New key added in front; old kept for reads.
    monkeypatch.setattr(crypto, "_fernet", MultiFernet([new, old]))
    assert crypto.decrypt_token(ct) == "secret"


# ── Session token hashing ──────────────────────────────────────────────────

def test_hash_is_deterministic_and_not_the_input():
    h = crypto.hash_session_token("abc123")
    assert h == crypto.hash_session_token("abc123")
    assert h != "abc123"
    assert len(h) == 64  # sha256 hex


def test_session_token_matches():
    stored = crypto.hash_session_token("the-real-token")
    assert crypto.session_token_matches("the-real-token", stored) is True
    assert crypto.session_token_matches("wrong", stored) is False
    assert crypto.session_token_matches("", stored) is False
    assert crypto.session_token_matches("the-real-token", None) is False
