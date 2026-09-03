"""Tests for POST /calendar/meetings — declarative recurring class meetings.

Every call removes all Plannr-tagged meeting events, then inserts one recurring
RRULE event per pattern. A retry can never leave duplicates, and the class
calendar is never deleted."""

import pytest
from fastapi.testclient import TestClient

from app import (
    app, _first_occurrence_on_or_after, _add_minutes_to_hhmm,
    MEETING_TAG_KEY, MEETING_TAG_VALUE,
)


# ── Unit: schedule math ─────────────────────────────────────────────────────

def test_first_occurrence_on_start_day():
    assert _first_occurrence_on_or_after("2026-09-02", ["MO", "WE", "FR"]).isoformat() == "2026-09-02"


def test_first_occurrence_skips_forward():
    assert _first_occurrence_on_or_after("2026-01-06", ["WE"]).isoformat() == "2026-01-07"


def test_add_minutes_to_hhmm():
    assert _add_minutes_to_hhmm("09:00", 50) == "09:50"
    assert _add_minutes_to_hhmm("09:40", 80) == "11:00"
    assert _add_minutes_to_hhmm("23:30", 60) == "00:30"
    assert _add_minutes_to_hhmm("11:00:00", 75) == "12:15"  # tolerates HH:MM:SS


# ── Fake Google Calendar service ───────────────────────────────────────────

class _FakeResp(dict):
    def __init__(self, status):
        super().__init__(status=status)
        self.status = status
        self.reason = "Test"


class _Call:
    def __init__(self, result=None, raises=None):
        self._result, self._raises = result, raises

    def execute(self):
        if self._raises:
            raise self._raises
        return self._result


class _Events:
    def __init__(self, rec):
        self.rec = rec
        self.tagged_items = []       # events _delete_tagged_meeting_events will find
        self.insert_bodies = []

    def list(self, calendarId, privateExtendedProperty=None, showDeleted=None,
             maxResults=None, pageToken=None):
        self.rec.append(("events.list", privateExtendedProperty))
        return _Call(result={"items": self.tagged_items})

    def insert(self, calendarId, body):
        self.rec.append(("insert", body["summary"]))
        self.insert_bodies.append(body)
        return _Call(result={"id": "new-" + body["summary"]})

    def patch(self, calendarId, eventId, body):
        self.rec.append(("patch", eventId))          # must never be called now
        return _Call(result={"id": eventId})

    def delete(self, calendarId, eventId):
        self.rec.append(("delete", eventId))
        return _Call(result={})


class _Calendars:
    def __init__(self, rec, get_raises=None):
        self.rec, self.get_raises = rec, get_raises

    def get(self, calendarId):
        self.rec.append(("calendars.get", calendarId))
        return _Call(result={"id": calendarId}, raises=self.get_raises)

    def insert(self, body):
        self.rec.append(("calendars.insert", body["summary"]))
        return _Call(result={"id": "cal-" + body["summary"]})

    def delete(self, calendarId):
        self.rec.append(("calendars.delete", calendarId))   # must never be called
        return _Call(result={})


class _CalendarList:
    def __init__(self, rec):
        self.rec = rec

    def list(self):
        self.rec.append(("calendarList.list", None))
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


def _lecture(**overrides):
    p = {"kind": "lecture", "byday": ["MO", "WE", "FR"], "start_time": "11:00", "duration_minutes": 75}
    p.update(overrides)
    return p


def _post(client, patterns=None, remove=None, google_calendar_id="cal-123",
          until="2026-12-11", start="2026-09-02", final_exam=None):
    body = {
        "class_name": "CS101",
        "timezone": "America/Los_Angeles",
        "start_date": start,
        "until_date": until,
        "patterns": patterns or [],
        "remove_event_ids": remove or [],
    }
    if google_calendar_id is not None:
        body["google_calendar_id"] = google_calendar_id
    if final_exam is not None:
        body["final_exam"] = final_exam
    return client.post("/calendar/meetings", params={"email": "s@e.com"}, json=body)


# ── Behaviour ─────────────────────────────────────────────────────────────

def test_new_pattern_lists_then_inserts_one_tagged_recurring_event(meetings):
    client, rec, fake = meetings
    resp = _post(client, patterns=[_lecture()])
    assert resp.status_code == 200
    assert resp.json() == {
        "google_calendar_id": "cal-123",
        "meetings": [{"kind": "lecture", "google_event_id": "new-CS101"}],
    }

    # Declarative: tagged list first, then insert. Never patch, never delete the calendar.
    assert ("events.list", f"{MEETING_TAG_KEY}={MEETING_TAG_VALUE}") in rec
    assert ("insert", "CS101") in rec
    assert not any(k == "patch" for k, _ in rec)
    assert not any(k == "calendars.delete" for k, _ in rec)

    ev = fake.events().insert_bodies[0]
    assert ev["recurrence"] == ["RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR;UNTIL=20261211T235959Z"]
    assert ev["start"]["dateTime"] == "2026-09-02T11:00:00"
    assert ev["end"]["dateTime"] == "2026-09-02T12:15:00"   # +75 min
    assert ev["start"]["timeZone"] == "America/Los_Angeles"
    assert ev["extendedProperties"]["private"][MEETING_TAG_KEY] == MEETING_TAG_VALUE
    assert ev["extendedProperties"]["private"]["plannrMeetingKind"] == "lecture"


def test_open_ended_when_no_until(meetings):
    client, rec, fake = meetings
    _post(client, patterns=[_lecture()], until=None)
    assert fake.events().insert_bodies[0]["recurrence"] == ["RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR"]


def test_backwards_until_is_dropped(meetings):
    client, rec, fake = meetings
    # until before the first occurrence → no UNTIL clause (Google would reject it).
    _post(client, patterns=[_lecture()], start="2026-09-02", until="2026-08-01")
    assert fake.events().insert_bodies[0]["recurrence"] == ["RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR"]


def test_section_pattern_titled_and_timed(meetings):
    client, rec, fake = meetings
    _post(client, patterns=[_lecture(kind="section", byday=["TH"], start_time="14:00",
                                     duration_minutes=110)])
    ev = fake.events().insert_bodies[0]
    assert ev["summary"] == "CS101 (Section)"
    assert ev["start"]["dateTime"] == "2026-09-03T14:00:00"   # first Thursday on/after 2026-09-02
    assert ev["end"]["dateTime"] == "2026-09-03T15:50:00"
    assert ev["extendedProperties"]["private"]["plannrMeetingKind"] == "section"


def test_two_patterns_produce_two_events(meetings):
    client, rec, fake = meetings
    resp = _post(client, patterns=[
        _lecture(),
        _lecture(kind="section", byday=["TH"], start_time="15:00", duration_minutes=50),
    ])
    kinds = [m["kind"] for m in resp.json()["meetings"]]
    assert kinds == ["lecture", "section"]
    assert len(fake.events().insert_bodies) == 2


def test_turning_off_deletes_tagged_events_and_inserts_nothing(meetings):
    client, rec, fake = meetings
    fake.events().tagged_items = [{"id": "old-lec"}, {"id": "old-sec"}]
    resp = _post(client, patterns=[])   # meetings toggled off, class already has a calendar
    assert resp.status_code == 200
    assert resp.json()["meetings"] == []
    assert ("delete", "old-lec") in rec and ("delete", "old-sec") in rec
    assert not any(k == "insert" for k, _ in rec)
    assert not any(k == "calendars.delete" for k, _ in rec)


def test_turning_off_with_no_calendar_is_a_noop(meetings):
    client, rec, _ = meetings
    resp = _post(client, patterns=[], google_calendar_id=None)
    assert resp.status_code == 200
    assert resp.json() == {"google_calendar_id": None, "meetings": []}
    assert rec == []   # no Google calls at all


def test_stale_pre_existing_meetings_are_cleared_before_re_insert(meetings):
    client, rec, fake = meetings
    fake.events().tagged_items = [{"id": "stale-1"}]
    _post(client, patterns=[_lecture()])
    # The stale one is deleted; exactly one fresh insert.
    assert ("delete", "stale-1") in rec
    assert len(fake.events().insert_bodies) == 1


def test_explicit_remove_event_ids_are_also_deleted(meetings):
    client, rec, _ = meetings
    _post(client, patterns=[_lecture()], remove=["extra-id"])
    assert ("delete", "extra-id") in rec


def test_stale_calendar_id_falls_through_to_find_or_create(meetings):
    client, rec, fake = meetings
    from googleapiclient.errors import HttpError
    fake._calendars.get_raises = HttpError(resp=_FakeResp(404), content=b"{}")
    resp = _post(client, patterns=[_lecture()], google_calendar_id="gone-1")
    assert resp.status_code == 200
    assert resp.json()["google_calendar_id"] == "cal-CS101"
    assert ("calendarList.list", None) in rec
    assert ("calendars.insert", "CS101") in rec


# ── Final exam ────────────────────────────────────────────────────────────

def test_final_exam_inserts_a_one_off_tagged_event(meetings):
    client, rec, fake = meetings
    resp = _post(client, patterns=[_lecture()], final_exam={
        "date": "2026-12-15", "start_time": "19:00", "duration_minutes": 180,
    })
    assert resp.status_code == 200
    kinds = [m["kind"] for m in resp.json()["meetings"]]
    assert kinds == ["lecture", "final"]

    fe = fake.events().insert_bodies[-1]
    assert fe["summary"] == "CS101 — Final Exam"
    assert "recurrence" not in fe                    # one-off, not recurring
    assert fe["start"]["dateTime"] == "2026-12-15T19:00:00"
    assert fe["end"]["dateTime"] == "2026-12-15T22:00:00"
    assert fe["transparency"] == "opaque"
    assert fe["extendedProperties"]["private"]["plannrMeetingKind"] == "final"
    assert fe["extendedProperties"]["private"][MEETING_TAG_KEY] == MEETING_TAG_VALUE


def test_final_exam_without_patterns_still_inserts(meetings):
    client, rec, fake = meetings
    resp = _post(client, patterns=[], final_exam={
        "date": "2026-12-15", "start_time": "08:00", "duration_minutes": 120,
    })
    assert resp.status_code == 200
    assert [m["kind"] for m in resp.json()["meetings"]] == ["final"]


def test_no_final_exam_field_inserts_nothing_extra(meetings):
    client, rec, fake = meetings
    _post(client, patterns=[_lecture()])
    assert len(fake.events().insert_bodies) == 1
