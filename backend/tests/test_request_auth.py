"""Tests for per-user request authentication: every per-user endpoint requires an
`Authorization: Bearer <session_token>` header whose token matches the one issued
to that email at sign-in. Knowing the email is not enough."""

from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

import app as app_module
from app import app, _bearer_token


@pytest.fixture
def client():
    return TestClient(app)


# ── _bearer_token unit ─────────────────────────────────────────────────────

def test_bearer_token_parsing():
    assert _bearer_token("Bearer abc123") == "abc123"
    assert _bearer_token("bearer abc123") == "abc123"     # scheme is case-insensitive
    assert _bearer_token("  Bearer   abc123  ") == "abc123"
    assert _bearer_token("Basic abc123") is None           # wrong scheme
    assert _bearer_token("abc123") is None                 # no scheme
    assert _bearer_token("Bearer ") is None                # empty value
    assert _bearer_token(None) is None
    assert _bearer_token("") is None


# ── require_account, exercised through /me ──────────────────────────────────

@pytest.fixture
def me_backend(monkeypatch):
    """/me wired so a matching token yields a profile. `authenticate` accepts only
    the token "good-token" for any email."""
    monkeypatch.setattr(
        app_module, "authenticate",
        lambda email, token: {"refresh_token": "r"} if token == "good-token" else None,
    )
    monkeypatch.setattr(app_module, "_build_credentials", lambda d: object())
    userinfo = SimpleNamespace(
        userinfo=lambda: SimpleNamespace(
            get=lambda: SimpleNamespace(
                execute=lambda: {"email": "a@b.com", "name": "Ada", "picture": ""}
            )
        )
    )
    monkeypatch.setattr(app_module, "build", lambda *a, **k: userinfo)


def test_missing_authorization_header_is_401(client, me_backend):
    resp = client.get("/me", params={"email": "a@b.com"})
    assert resp.status_code == 401
    assert "sign in" in resp.json()["error"].lower()


def test_wrong_token_is_401(client, me_backend):
    resp = client.get("/me", params={"email": "a@b.com"},
                      headers={"Authorization": "Bearer wrong-token"})
    assert resp.status_code == 401


def test_non_bearer_scheme_is_401(client, me_backend):
    resp = client.get("/me", params={"email": "a@b.com"},
                      headers={"Authorization": "Basic good-token"})
    assert resp.status_code == 401


def test_correct_token_is_200(client, me_backend):
    resp = client.get("/me", params={"email": "a@b.com"},
                      headers={"Authorization": "Bearer good-token"})
    assert resp.status_code == 200
    assert resp.json()["name"] == "Ada"


def test_calendar_sync_also_requires_the_token(client, me_backend):
    # Same dependency guards the mutating endpoints — no header, no access.
    resp = client.post("/calendar/sync", params={"email": "a@b.com"},
                       json={"class_name": "CS101", "events": []})
    assert resp.status_code == 401
