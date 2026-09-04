"""Tests for the OAuth start endpoint, /me, and account deletion."""

from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient
from googleapiclient.errors import HttpError
from google.auth.exceptions import RefreshError

from app import app


class _FakeResp(dict):
    def __init__(self, status):
        super().__init__(status=status)
        self.status = status
        self.reason = "Test"


@pytest.fixture
def client():
    return TestClient(app, follow_redirects=False)


# ── /auth/google ────────────────────────────────────────────────────────────

def test_auth_google_redirects_with_pkce_and_offline_access(client):
    from urllib.parse import parse_qs, urlparse

    resp = client.get("/auth/google")
    assert resp.status_code == 307

    q = parse_qs(urlparse(resp.headers["location"]).query)
    assert q["code_challenge_method"] == ["S256"]
    assert len(q["code_challenge"][0]) > 20
    assert q["access_type"] == ["offline"]
    assert q["prompt"] == ["consent"]
    assert "state" in q


def test_legacy_google_oauth_login_endpoint_is_gone(client):
    # Removed as dead code — should 404/405, not redirect.
    assert client.post("/google-oauth-login").status_code in (404, 405)


# ── /me ─────────────────────────────────────────────────────────────────────

def test_me_unknown_email_is_401(client, monkeypatch):
    monkeypatch.setattr("app.authenticate", lambda e, t: None)
    resp = client.get("/me", params={"email": "nobody@example.com"},
                      headers={"Authorization": "Bearer whatever"})
    assert resp.status_code == 401


def test_me_missing_bearer_token_is_401(client, monkeypatch):
    # A valid session would authenticate, but no Authorization header is sent.
    monkeypatch.setattr("app.authenticate", lambda e, t: {"refresh_token": "r"} if t else None)
    resp = client.get("/me", params={"email": "someone@example.com"})
    assert resp.status_code == 401


def test_me_revoked_token_is_401_not_400(client, monkeypatch):
    monkeypatch.setattr("app.authenticate", lambda e, t: {"refresh_token": "r"})
    monkeypatch.setattr("app._build_credentials", lambda d: object())

    def _raise(*a, **k):
        raise RefreshError("token revoked")

    monkeypatch.setattr("app.build", _raise)
    resp = client.get("/me", params={"email": "someone@example.com"})
    assert resp.status_code == 401
    assert "sign in" in resp.json()["error"].lower()


def test_me_success_returns_profile(client, monkeypatch):
    monkeypatch.setattr("app.authenticate", lambda e, t: {"refresh_token": "r"})
    monkeypatch.setattr("app._build_credentials", lambda d: object())

    userinfo = SimpleNamespace(
        userinfo=lambda: SimpleNamespace(
            get=lambda: SimpleNamespace(
                execute=lambda: {"email": "a@b.com", "name": "Ada", "picture": "http://x/p.jpg"}
            )
        )
    )
    monkeypatch.setattr("app.build", lambda *a, **k: userinfo)

    resp = client.get("/me", params={"email": "a@b.com"})
    assert resp.status_code == 200
    body = resp.json()
    assert body == {"email": "a@b.com", "name": "Ada", "picture": "http://x/p.jpg"}


# ── DELETE /account ─────────────────────────────────────────────────────────

def test_delete_account_success_is_200(client, monkeypatch):
    called = {}
    monkeypatch.setattr("app.authenticate", lambda e, t: {"refresh_token": "r"})
    monkeypatch.setattr("app.delete_user", lambda email: called.setdefault("email", email))
    resp = client.request("DELETE", "/account", params={"email": "gone@example.com"},
                          headers={"Authorization": "Bearer tok"})
    assert resp.status_code == 200
    assert called["email"] == "gone@example.com"


def test_delete_account_db_failure_is_500(client, monkeypatch):
    def _boom(email):
        raise RuntimeError("db down")

    monkeypatch.setattr("app.authenticate", lambda e, t: {"refresh_token": "r"})
    monkeypatch.setattr("app.delete_user", _boom)
    resp = client.request("DELETE", "/account", params={"email": "x@example.com"},
                          headers={"Authorization": "Bearer tok"})
    assert resp.status_code == 500
    assert "try again" in resp.json()["error"].lower()


def test_delete_account_without_token_is_401_when_account_exists(client, monkeypatch):
    monkeypatch.setattr("app.authenticate", lambda e, t: None)
    monkeypatch.setattr("app.user_exists", lambda e: True)
    deleted = {}
    monkeypatch.setattr("app.delete_user", lambda e: deleted.setdefault("hit", True))
    resp = client.request("DELETE", "/account", params={"email": "x@example.com"})
    assert resp.status_code == 401
    assert "hit" not in deleted  # must not delete without authentication


def test_delete_account_is_idempotent_when_already_gone(client, monkeypatch):
    monkeypatch.setattr("app.authenticate", lambda e, t: None)
    monkeypatch.setattr("app.user_exists", lambda e: False)
    resp = client.request("DELETE", "/account", params={"email": "gone@example.com"})
    assert resp.status_code == 200
