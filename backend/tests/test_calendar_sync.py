"""Tests for POST /calendar/sync — incremental sync must patch/insert/delete the
diff and never delete-and-recreate the class calendar."""

import pytest
from fastapi.testclient import TestClient
from googleapiclient.errors import HttpError

from app import app


# ── Fake Google Calendar service ─────────────────────────────────────────────

class _FakeResp(dict):
    """Enough of an httplib2.Response for HttpError (has .status and .get)."""
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
        self.patch_raises = {}   # eventId -> exception raised by patch(...).execute()
        self.list_items = []     # events the full-rebuild path will find and delete
        self.tag_lookup = {}     # "plannrLocalId=<id>" -> [event dicts] found by tag
        self.last_insert_body = None

    def patch(self, calendarId, eventId, body):
        self.rec.append(("patch", eventId))
        return _Call(result={"id": eventId}, raises=self.patch_raises.get(eventId))

    def update(self, calendarId, eventId, body):          # must never be called
        self.rec.append(("update", eventId))
        return _Call(result={"id": eventId})

    def insert(self, calendarId, body):
        self.rec.append(("insert", body["summary"]))
        self.last_insert_body = body
        return _Call(result={"id": "new-" + body["summary"]})

    def delete(self, calendarId, eventId):
        self.rec.append(("delete", eventId))
        return _Call(result={})

    def list(self, calendarId, singleEvents=None, pageToken=None,
             privateExtendedProperty=None, showDeleted=None, maxResults=None):
        if privateExtendedProperty:   # idempotency lookup before an insert
            self.rec.append(("events.list.byTag", privateExtendedProperty))
            return _Call(result={"items": self.tag_lookup.get(privateExtendedProperty, [])})
        self.rec.append(("events.list", None))   # full rebuild only
        return _Call(result={"items": self.list_items})


class _Calendars:
    def __init__(self, rec, get_raises=None):
        self.rec = rec
        self.get_raises = get_raises

    def get(self, calendarId):
        self.rec.append(("calendars.get", calendarId))
        return _Call(result={"id": calendarId}, raises=self.get_raises)

    def insert(self, body):
        self.rec.append(("calendars.insert", body["summary"]))
        return _Call(result={"id": "cal-" + body["summary"]})

    def delete(self, calendarId):                          # must never be called
        self.rec.append(("calendars.delete", calendarId))
        return _Call(result={})


class _CalendarList:
    def __init__(self, rec, items=None):
        self.rec = rec
        self.items = items or []

    def list(self):
        self.rec.append(("calendarList.list", None))
        return _Call(result={"items": self.items})

    def patch(self, calendarId, body, colorRgbFormat=None):
        self.rec.append(("calendarList.patch", calendarId))
        return _Call(result={})


class FakeService:
    def __init__(self, rec, get_raises=None, cal_items=None):
        self._events = _Events(rec)
        self._calendars = _Calendars(rec, get_raises)
        self._calendar_list = _CalendarList(rec, cal_items)

    def events(self):
        return self._events

    def calendars(self):
        return self._calendars

    def calendarList(self):
        return self._calendar_list


@pytest.fixture
def synced(monkeypatch):
    """Returns (client, rec, fake). Configure fake before calling the endpoint."""
    rec = []
    fake = FakeService(rec)

    monkeypatch.setattr("app.build", lambda *a, **k: fake)
    monkeypatch.setattr("app.get_google_credentials", lambda email: {"refresh_token": "r"})
    monkeypatch.setattr("app._build_credentials", lambda data: object())

    return TestClient(app), rec, fake


def _post(client, events, google_calendar_id="cal-123"):
    body = {"class_name": "CS101", "events": events}
    if google_calendar_id is not None:
        body["google_calendar_id"] = google_calendar_id
    return client.post("/calendar/sync", params={"email": "student@example.com"}, json=body)


# ── Tests ───────────────────────────────────────────────────────────────────

def test_existing_event_is_patched_not_recreated(synced):
    client, rec, _ = synced
    resp = _post(client, [
        {"local_id": "L1", "title": "HW1", "date": "2026-03-01",
         "google_event_id": "G1", "is_deleted": False},
    ])
    assert resp.status_code == 200
    body = resp.json()
    assert body["google_calendar_id"] == "cal-123"
    assert body["synced_events"] == [{"local_id": "L1", "google_event_id": "G1"}]

    assert ("patch", "G1") in rec
    assert not any(k == "update" for k, _ in rec), "must use events.patch, not events.update"
    assert not any(k == "calendars.delete" for k, _ in rec), "must not delete the class calendar"
    assert not any(k == "events.list" for k, _ in rec), "must not fall back to a full rebuild"


def test_new_event_is_inserted(synced):
    client, rec, fake = synced
    resp = _post(client, [
        {"local_id": "L2", "title": "HW2", "date": "2026-03-08", "is_deleted": False},
    ])
    assert resp.status_code == 200
    assert resp.json()["synced_events"] == [{"local_id": "L2", "google_event_id": "new-HW2"}]
    assert ("insert", "HW2") in rec
    # It looked for an existing copy first, and tagged what it inserted.
    assert ("events.list.byTag", "plannrLocalId=L2") in rec
    assert fake.events().last_insert_body["extendedProperties"]["private"]["plannrLocalId"] == "L2"


def test_retried_insert_patches_the_existing_event_instead_of_duplicating(synced):
    client, rec, fake = synced
    # A prior sync already created this event; its response was lost, so the
    # client re-sends it with no google_event_id.
    fake.events().tag_lookup["plannrLocalId=L2"] = [{"id": "G-already"}]

    resp = _post(client, [
        {"local_id": "L2", "title": "HW2", "date": "2026-03-08", "is_deleted": False},
    ])
    assert resp.status_code == 200
    assert resp.json()["synced_events"] == [{"local_id": "L2", "google_event_id": "G-already"}]
    assert ("patch", "G-already") in rec
    assert not any(k == "insert" for k, _ in rec), "must not insert a duplicate"


def test_deleted_event_is_removed_and_not_returned(synced):
    client, rec, _ = synced
    resp = _post(client, [
        {"local_id": "L3", "title": "HW3", "date": "2026-03-15",
         "google_event_id": "G3", "is_deleted": True},
    ])
    assert resp.status_code == 200
    assert resp.json()["synced_events"] == []
    assert ("delete", "G3") in rec
    assert not any(k == "calendars.delete" for k, _ in rec)


def test_patch_404_recreates_only_that_event(synced):
    client, rec, fake = synced
    fake.events().patch_raises["G-stale"] = HttpError(resp=_FakeResp(404), content=b"{}")

    resp = _post(client, [
        {"local_id": "L4", "title": "HW4", "date": "2026-03-22",
         "google_event_id": "G-stale", "is_deleted": False},
    ])
    assert resp.status_code == 200
    assert resp.json()["synced_events"] == [{"local_id": "L4", "google_event_id": "new-HW4"}]

    assert ("patch", "G-stale") in rec
    assert ("insert", "HW4") in rec
    assert not any(k == "events.list" for k, _ in rec), "one stale id must not trigger a full rebuild"


def test_non_404_patch_error_triggers_full_rebuild(synced):
    client, rec, fake = synced
    fake.events().patch_raises["G-boom"] = HttpError(resp=_FakeResp(500), content=b"{}")

    resp = _post(client, [
        {"local_id": "L5", "title": "HW5", "date": "2026-03-29",
         "google_event_id": "G-boom", "is_deleted": False},
    ])
    assert resp.status_code == 200
    # Fell back to the event-level rebuild, but still never deletes the calendar.
    assert any(k == "events.list" for k, _ in rec)
    assert not any(k == "calendars.delete" for k, _ in rec)


def test_stale_calendar_id_falls_through_to_find_or_create(synced):
    client, rec, fake = synced
    fake._calendars.get_raises = HttpError(resp=_FakeResp(404), content=b"{}")

    resp = _post(client, [
        {"local_id": "L6", "title": "HW6", "date": "2026-04-05", "is_deleted": False},
    ], google_calendar_id="gone-123")
    assert resp.status_code == 200
    assert resp.json()["google_calendar_id"] == "cal-CS101"

    assert ("calendars.get", "gone-123") in rec
    assert ("calendarList.list", None) in rec
    assert ("calendars.insert", "CS101") in rec


def test_full_rebuild_clears_assignments_but_keeps_calendar_and_meeting_events(synced):
    client, rec, fake = synced
    fake.events().patch_raises["G-boom"] = HttpError(resp=_FakeResp(500), content=b"{}")
    fake.events().list_items = [
        {"id": "old-a"},
        {"id": "old-b"},
        {"id": "meeting-lec", "recurrence": ["RRULE:FREQ=WEEKLY;BYDAY=MO"],
         "extendedProperties": {"private": {"plannrMeeting": "1"}}},
    ]

    resp = _post(client, [
        {"local_id": "L7", "title": "HW7", "date": "2026-04-12",
         "google_event_id": "G-boom", "is_deleted": False},
        {"local_id": "L8", "title": "HW8", "date": "2026-04-13", "is_deleted": False},
    ])
    assert resp.status_code == 200
    # Assignment events deleted, then re-inserted; the recurring meeting is left alone.
    assert ("delete", "old-a") in rec and ("delete", "old-b") in rec
    assert ("delete", "meeting-lec") not in rec
    assert ("insert", "HW7") in rec and ("insert", "HW8") in rec
    assert not any(k == "calendars.delete" for k, _ in rec)
    assert {m["local_id"] for m in resp.json()["synced_events"]} == {"L7", "L8"}


def test_is_deleted_event_without_google_id_is_a_no_op(synced):
    client, rec, _ = synced
    resp = _post(client, [
        {"local_id": "L9", "title": "Never synced", "date": "2026-04-20",
         "is_deleted": True},   # no google_event_id
    ])
    assert resp.status_code == 200
    assert resp.json()["synced_events"] == []
    assert not any(k == "delete" for k, _ in rec)
    assert not any(k == "insert" for k, _ in rec)


def test_reminder_minutes_flow_into_the_event_body(synced):
    client, rec, fake = synced
    client.post("/calendar/sync", params={"email": "s@e.com"}, json={
        "class_name": "CS101",
        "google_calendar_id": "cal-123",
        "reminder_minutes": 2880,   # 2 days
        "events": [{"local_id": "L1", "title": "HW1", "date": "2026-03-01", "is_deleted": False}],
    })
    body = fake.events().last_insert_body
    assert body["reminders"]["useDefault"] is False
    assert body["reminders"]["overrides"] == [{"method": "popup", "minutes": 2880}]


def test_no_reminder_minutes_leaves_google_defaults(synced):
    client, rec, fake = synced
    _post(client, [{"local_id": "L1", "title": "HW1", "date": "2026-03-01", "is_deleted": False}])
    assert "reminders" not in fake.events().last_insert_body
