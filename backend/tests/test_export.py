"""Tests for POST /export endpoint (.ics and .csv export)."""

from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient

from app import app

SAMPLE_EVENTS = [
    {
        "title": "Midterm Exam",
        "date": "2025-05-01",
        "type": "exam",
        "description": "Covers chapters 1-5"
    },
    {
        "title": "HW1",
        "date": "2025-04-15",
        "type": "homework",
        "description": ""
    }
]

@pytest.fixture
def client():
    return TestClient(app)


def test_export_ics_valid(client):
    """A valid request returns a text/calendar response containing VEVENTs."""
    resp = client.post(
        "/export",
        params={"email": "student@example.com", "format": "ics"},
        json={"events": SAMPLE_EVENTS}
    )
    assert resp.status_code == 200
    assert "text/calendar" in resp.headers["content-type"]
    assert "attachment" in resp.headers["content-disposition"]
    assert "events.ics" in resp.headers["content-disposition"]
    body = resp.text
    assert "BEGIN:VEVENT" in body
    assert "Midterm Exam" in body
    assert "HW1" in body


def test_export_csv_valid(client):
    """A valid request returns a text/csv response with the correct columns."""
    resp = client.post(
        "/export",
        params={"email": "student@example.com", "format": "csv"},
        json={"events": SAMPLE_EVENTS}
    )
    assert resp.status_code == 200
    assert "text/csv" in resp.headers["content-type"]
    assert "attachment" in resp.headers["content-disposition"]
    assert "events.csv" in resp.headers["content-disposition"]
    lines = resp.text.strip().splitlines()
    assert lines[0] == "Title,Date,Type,Description"
    assert "Midterm Exam" in lines[1]
    assert "2025-05-01" in lines[1]
    assert "exam" in lines[1]


def test_export_invalid_format(client):
    """Unsupported format parameter returns 400."""
    resp = client.post(
        "/export",
        params={"email": "student@example.com", "format": "pdf"},
        json={"events": SAMPLE_EVENTS}
    )
    assert resp.status_code == 400
    assert "format" in resp.json()["error"].lower()


def test_export_works_without_credentials(client):
    """Export only serializes the request body, so guests (no stored creds) can use it."""
    with patch("app.get_google_credentials", return_value=None):
        resp = client.post(
            "/export",
            params={"email": "guest@plannr.local", "format": "ics"},
            json={"events": SAMPLE_EVENTS}
        )
    assert resp.status_code == 200
    assert "BEGIN:VEVENT" in resp.text


def test_export_without_email_param(client):
    """The email query param is optional."""
    resp = client.post("/export", params={"format": "csv"}, json={"events": SAMPLE_EVENTS})
    assert resp.status_code == 200


def test_export_empty_events(client):
    """An empty events list returns 400."""
    resp = client.post(
        "/export",
        params={"email": "student@example.com", "format": "ics"},
        json={"events": []}
    )
    assert resp.status_code == 400
    assert "no events" in resp.json()["error"].lower()


def test_ics_has_one_vevent_per_event_with_dates_and_categories(client):
    resp = client.post(
        "/export",
        params={"format": "ics"},
        json={"events": SAMPLE_EVENTS},
    )
    body = resp.text
    assert body.count("BEGIN:VEVENT") == 2
    assert body.count("END:VEVENT") == 2
    assert "DTSTART" in body and "DTEND" in body
    # All-day dates render as VALUE=DATE:YYYYMMDD.
    assert "20250501" in body
    assert "CATEGORIES:exam" in body
    assert "PRODID:-//Plannr//Syllabus Export//EN" in body


def test_csv_quotes_fields_containing_commas(client):
    tricky = [{
        "title": 'Essay, final draft',
        "date": "2026-05-10",
        "type": "homework",
        "description": 'Say "hello"; cite sources',
    }]
    resp = client.post("/export", params={"format": "csv"}, json={"events": tricky})
    assert resp.status_code == 200
    lines = resp.text.strip().splitlines()
    # csv.writer quotes the comma-bearing title and doubles the inner quotes.
    assert '"Essay, final draft"' in lines[1]
    assert '""hello""' in lines[1]
    # One data row only (the embedded ; and quotes didn't split it).
    assert len(lines) == 2


def test_csv_uppercases_format_param(client):
    resp = client.post("/export", params={"format": "CSV"}, json={"events": SAMPLE_EVENTS})
    assert resp.status_code == 200
    assert "text/csv" in resp.headers["content-type"]
