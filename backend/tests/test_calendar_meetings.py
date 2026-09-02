"""Tests for POST /calendar/meetings — recurring class-meeting events.

One RRULE event per pattern (lecture, section); patterns with a google_event_id
are patched, the rest inserted; remove_event_ids are deleted; the class calendar
is never re-created from scratch."""

import pytest
from fastapi.testclient import TestClient
from googleapiclient.errors import HttpError

from app import app, _first_occurrence_on_or_after, _add_minutes_to_hhmm


# ── Unit: schedule math ─────────────────────────────────────────────────────

def test_first_occurrence_on_start_day():
    # 2026-01-05 is a Monday.
    assert _first_occurrence_on_or_after("2026-01-05", ["MO", "WE", "FR"]).isoformat() == "2026-01-05"


def test_first_occurrence_skips_forward():
    # From a Tuesday to the next Wednesday.
    assert _first_occurrence_on_or_after("2026-01-06", ["WE"]).isoformat() == "2026-01-07"


def test_add_minutes_to_hhmm():
    assert _add_minutes_to_hhmm("09:00", 50) == "09:50"
    assert _add_minutes_to_hhmm("09:40", 80) == "11:00"
    assert _add_minutes_to_hhmm("23:30", 60) == "00:30"  # wraps


# ── Fake Google Calendar service (records event bodies) ─────────────────────

class _FakeResp(dict):
    def __init__(self, status):
        super().__init__(status=status)
        self.status = status
        self.reason = "Test"


class _Call:
    def __init__(self, result=None, raises=None):
        self._result = result
        self._raises = raises

    def execute(self):
        if self._raises:
            raise self._raises
        return self._result


class _Events:
    def __init__(self, rec):
        self.rec = rec
        self.patch_raises = {}

    def insert(self, calendarId, body):
        self.rec.append(("insert", None, body))
        return _Call(result={"id": "new-" + body["summary"]})

    def patch(self, calendarId, eventId, body):
        self.rec.append(("patch", eventId, body))
        return _Call(result={"id": eventId}, raises=self.patch_raises.get(eventId))

    def delete(self, calendarId, eventId):
        self.rec.append(("delete", eventId, None))
        return _Call(result={})


class _Calendars:
    def __init__(self, rec, get_raises=None):
        self.rec = rec
        self.get_raises = get_raises

    def get(self, calendarId):
        self.rec.append(("calendars.get", calendarId, None))
        return _Call(result={"id": calendarId}, raises=self.get_raises)

    def insert(self, body):
        self.rec.append(("calendars.insert", body["summary"], None))
        return _Call(result={"id": "cal-" + body["summary"]})

    def delete(self, calendarId):
        self.rec.append(("calendars.delete", calendarId, None))
        return _Call(result={})


class _CalendarList:
    def __init__(self, rec):
        self.rec = rec

    def list(self):
        self.rec.append(("calendarList.list", None, None))
        return _Call(result={"items": []})

    def patch(self, calendarId, body, colorRgbFormat=None):
        return _Call(result={})


class FakeService:
    def __init__(self, rec, get_raises=None):
        self._events = _Events(rec)
        self._calendars = _Calendars(rec, get_raises)
        self._calendar_list = _CalendarList(rec)

    def events(self):
        return self._events

    def calendars(self):
        return self._calendars

    def calendarList(self):
        return self._calendar_list


@pytest.fixture
def meetings(monkeypatch):
    rec = []
    fake = FakeService(rec)
    monkeypatch.setattr("app.build", lambda *a, **k: fake)
    monkeypatch.setattr("app.get_google_credentials", lambda email: {"refresh_token": "r"})
    monkeypatch.setattr("app._build_credentials", lambda data: object())
    return TestClient(app), rec, fake


def _lecture_pattern(**overrides):
    p = {"kind": "lecture", "byday": ["MO", "WE", "FR"], "start_time": "09:00", "duration_minutes": 50}
    p.update(overrides)
    return p


def _post(client, patterns=None, remove=None, google_calendar_id="cal-123", until="2026-03-13"):
    body = {
        "class_name": "CS101",
        "google_calendar_id": google_calendar_id,
        "timezone": "America/Los_Angeles",
        "start_date": "2026-01-05",
        "until_date": until,
        "patterns": patterns or [],
        "remove_event_ids": remove or [],
    }
    return client.post("/calendar/meetings", params={"email": "s@e.com"}, json=body)


# ── Endpoint behaviour ─────────────────────────────────────────────────────

def test_new_pattern_creates_one_recurring_event(meetings):
    client, rec, _ = meetings
    resp = _post(client, patterns=[_lecture_pattern()])
    assert resp.status_code == 200
    body = resp.json()
    assert body["google_calendar_id"] == "cal-123"
    assert body["meetings"] == [{"kind": "lecture", "google_event_id": "new-CS101"}]

    inserts = [b for (op, _id, b) in rec if op == "insert"]
    assert len(inserts) == 1
    ev = inserts[0]
    assert ev["summary"] == "CS101"
    assert ev["recurrence"] == ["RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR;UNTIL=20260313T235959Z"]
    assert ev["start"]["dateTime"] == "2026-01-05T09:00:00"   # first Monday on/after start
    assert ev["end"]["dateTime"] == "2026-01-05T09:50:00"
    assert ev["start"]["timeZone"] == "America/Los_Angeles"
    assert not any(op == "calendars.delete" for (op, _1, _2) in rec)


def test_open_ended_recurrence_has_no_until(meetings):
    client, rec, _ = meetings
    _post(client, patterns=[_lecture_pattern()], until=None)
    ev = next(b for (op, _id, b) in rec if op == "insert")
    assert ev["recurrence"] == ["RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR"]


def test_section_pattern_titled_and_timed(meetings):
    client, rec, _ = meetings
    _post(client, patterns=[
        _lecture_pattern(kind="section", byday=["TH"], start_time="14:00", duration_minutes=110),
    ])
    ev = next(b for (op, _id, b) in rec if op == "insert")
    assert ev["summary"] == "CS101 (Section)"
    assert ev["start"]["dateTime"] == "2026-01-08T14:00:00"   # first Thursday on/after 2026-01-05
    assert ev["end"]["dateTime"] == "2026-01-08T15:50:00"
    assert ev["recurrence"][0].startswith("RRULE:FREQ=WEEKLY;BYDAY=TH;")


def test_existing_pattern_is_patched_not_reinserted(meetings):
    client, rec, _ = meetings
    resp = _post(client, patterns=[_lecture_pattern(google_event_id="G-lec")])
    assert resp.status_code == 200
    assert resp.json()["meetings"] == [{"kind": "lecture", "google_event_id": "G-lec"}]
    assert any(op == "patch" and _id == "G-lec" for (op, _id, _b) in rec)
    assert not any(op == "insert" for (op, _1, _2) in rec)


def test_remove_event_ids_are_deleted(meetings):
    client, rec, _ = meetings
    _post(client, patterns=[], remove=["G-old-1", "G-old-2"])
    deleted = {_id for (op, _id, _b) in rec if op == "delete"}
    assert deleted == {"G-old-1", "G-old-2"}
    assert not any(op == "calendars.delete" for (op, _1, _2) in rec)


def test_patch_404_recreates_the_meeting(meetings):
    client, rec, fake = meetings
    fake.events().patch_raises["G-stale"] = HttpError(resp=_FakeResp(404), content=b"{}")
    resp = _post(client, patterns=[_lecture_pattern(google_event_id="G-stale")])
    assert resp.status_code == 200
    assert resp.json()["meetings"] == [{"kind": "lecture", "google_event_id": "new-CS101"}]
    ops = [op for (op, _1, _2) in rec]
    assert "patch" in ops and "insert" in ops


def test_stale_calendar_id_falls_through_to_find_or_create(meetings):
    client, rec, fake = meetings
    fake._calendars.get_raises = HttpError(resp=_FakeResp(404), content=b"{}")
    resp = _post(client, patterns=[_lecture_pattern()], google_calendar_id="gone-1")
    assert resp.status_code == 200
    assert resp.json()["google_calendar_id"] == "cal-CS101"
    assert ("calendarList.list", None, None) in rec
    assert ("calendars.insert", "CS101", None) in rec
