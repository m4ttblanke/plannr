"""Tests for GET /health — the uptime-monitor / keep-warm endpoint."""

import pytest
from fastapi.testclient import TestClient

from app import app


@pytest.fixture
def client():
    return TestClient(app)


def test_health_is_200_and_shaped(client, monkeypatch):
    monkeypatch.setattr("app.db_ping", lambda: True)
    resp = client.get("/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ok"
    assert body["ready"] is True
    assert body["database"] == "ok"
    assert isinstance(body["uptime_seconds"], int) and body["uptime_seconds"] >= 0
    assert "version" in body and "time" in body


def test_health_still_200_when_the_database_is_down(client, monkeypatch):
    # A Render free-Postgres nap must not make the health check fail (Render would
    # cycle the instance); it's only reflected in the body.
    monkeypatch.setattr("app.db_ping", lambda: False)
    resp = client.get("/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ok"
    assert body["ready"] is False
    assert body["database"] == "unavailable"


def test_health_is_not_rate_limited(client, monkeypatch):
    monkeypatch.setattr("app.db_ping", lambda: True)
    for _ in range(30):
        assert client.get("/health").status_code == 200
