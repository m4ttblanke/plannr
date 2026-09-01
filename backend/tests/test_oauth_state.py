"""Tests for OAuth CSRF protection via signed, self-contained state tokens."""

import time
from urllib.parse import parse_qs, urlparse

import pytest

from app import issue_oauth_state, verify_oauth_state, OAUTH_STATE_TTL


class TestSignedState:
    """The state token round-trips the PKCE verifier and rejects tampering."""

    def test_roundtrip_returns_verifier(self):
        token = issue_oauth_state("my-code-verifier")
        assert verify_oauth_state(token) == "my-code-verifier"

    def test_tampered_body_rejected(self):
        body, sig = issue_oauth_state("v").split(".", 1)
        assert verify_oauth_state(f"{body}x.{sig}") is None

    def test_tampered_signature_rejected(self):
        body, _ = issue_oauth_state("v").split(".", 1)
        assert verify_oauth_state(f"{body}.deadbeef") is None

    def test_malformed_rejected(self):
        assert verify_oauth_state("") is None
        assert verify_oauth_state("no-dot") is None
        assert verify_oauth_state("a.b.c") is None

    def test_expired_rejected(self, monkeypatch):
        token = issue_oauth_state("v")
        real_time = time.time
        monkeypatch.setattr("app.time.time", lambda: real_time() + OAUTH_STATE_TTL + 1)
        assert verify_oauth_state(token) is None

    def test_each_issue_is_unique(self):
        assert issue_oauth_state("a") != issue_oauth_state("b")


class TestAuthCallback:
    """/auth/callback rejects missing or invalid state before touching Google."""

    def _client(self):
        from fastapi.testclient import TestClient
        from app import app
        return TestClient(app, follow_redirects=False)

    def test_missing_state_rejected(self):
        resp = self._client().get("/auth/callback", params={"code": "fake_code"})
        assert resp.status_code == 307
        assert "error=" in resp.headers["location"]

    def test_invalid_state_rejected(self):
        resp = self._client().get(
            "/auth/callback", params={"code": "fake_code", "state": "bogus.state"}
        )
        assert resp.status_code == 307
        assert "error=" in resp.headers["location"]


class TestAuthGoogle:
    """/auth/google issues a valid signed state in its redirect."""

    def _state_from_redirect(self, resp):
        return parse_qs(urlparse(resp.headers["location"]).query)["state"][0]

    def test_google_auth_redirects_with_signed_state(self):
        from fastapi.testclient import TestClient
        from app import app

        client = TestClient(app, follow_redirects=False)
        resp = client.get("/auth/google")
        assert resp.status_code == 307
        assert verify_oauth_state(self._state_from_redirect(resp)) is not None

    def test_each_request_generates_unique_state(self):
        from fastapi.testclient import TestClient
        from app import app

        client = TestClient(app, follow_redirects=False)
        s1 = self._state_from_redirect(client.get("/auth/google"))
        s2 = self._state_from_redirect(client.get("/auth/google"))
        assert s1 != s2
