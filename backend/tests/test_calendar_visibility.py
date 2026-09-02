"""Tests for POST /calendar/visibility — check/uncheck a class's calendar in
the user's Google Calendar sidebar (calendarList.selected) when the class is
switched active/inactive."""

import pytest
from fastapi.testclient import TestClient
from googleapiclient.errors import HttpError

from app import app


class _FakeResp:
    def __init__(self, status):
        self.status = status
        self.reason = "Test"


class _Call:
    def __init__(self, result=None, raises=None):
        self._result, self._raises = result, raises

    def execute(self):
        if self._raises:
            raise self._raises
        return self._result


class _CalendarList:
    def __init__(self, rec, patch_raises=None):
        self.rec = rec
        self.patch_raises = patch_raises

    def patch(self, calendarId, body, colorRgbFormat=None):
        self.rec.append(("calendarList.patch", calendarId, body))
        return _Call(result={"id": calendarId, **body}, raises=self.patch_raises)


class FakeService:
    def __init__(self, rec, patch_raises=None):
        self._calendar_list = _CalendarList(rec, patch_raises)

    def calendarList(self):
        return self._calendar_list


def _client(monkeypatch, patch_raises=None):
    rec = []
    fake = FakeService(rec, patch_raises)
    monkeypatch.setattr("app.build", lambda *a, **k: fake)
    monkeypatch.setattr("app.get_google_credentials", lambda email: {"refresh_token": "r"})
    monkeypatch.setattr("app._build_credentials", lambda data: object())
    return TestClient(app), rec


def _post(client, selected, cal_id="cal-123"):
    return client.post(
        "/calendar/visibility",
        params={"email": "s@e.com"},
        json={"google_calendar_id": cal_id, "selected": selected},
    )


def test_uncheck_patches_selected_false(monkeypatch):
    client, rec = _client(monkeypatch)
    resp = _post(client, selected=False)
    assert resp.status_code == 200
    assert resp.json() == {"selected": False}
    assert rec == [("calendarList.patch", "cal-123", {"selected": False})]


def test_check_patches_selected_true(monkeypatch):
    client, rec = _client(monkeypatch)
    resp = _post(client, selected=True)
    assert resp.status_code == 200
    assert resp.json() == {"selected": True}
    assert rec == [("calendarList.patch", "cal-123", {"selected": True})]


def test_missing_calendar_is_skipped_not_an_error(monkeypatch):
    err = HttpError(_FakeResp(404), b"not found")
    client, rec = _client(monkeypatch, patch_raises=err)
    resp = _post(client, selected=False)
    assert resp.status_code == 200
    assert resp.json() == {"selected": False, "skipped": True}


def test_unauthenticated_returns_401(monkeypatch):
    client, _ = _client(monkeypatch)
    monkeypatch.setattr("app.get_google_credentials", lambda email: None)
    resp = _post(client, selected=False)
    assert resp.status_code == 401


def test_other_http_error_is_400(monkeypatch):
    err = HttpError(_FakeResp(500), b"boom")
    client, _ = _client(monkeypatch, patch_raises=err)
    resp = _post(client, selected=True)
    assert resp.status_code == 400
