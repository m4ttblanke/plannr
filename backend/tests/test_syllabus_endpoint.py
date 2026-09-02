"""Tests for POST /syllabus — the upload guardrails and the extract → parse flow."""

import io

import pytest
from fastapi.testclient import TestClient

import app as app_module
from app import app, MAX_SYLLABUS_BYTES


@pytest.fixture
def client():
    return TestClient(app)


def _upload(client, data: bytes, filename="syllabus.pdf"):
    return client.post(
        "/syllabus",
        files={"file": (filename, io.BytesIO(data), "application/pdf")},
    )


def test_oversize_upload_is_rejected_with_413(client, monkeypatch):
    # Don't actually run PDF parsing — the size check happens first.
    monkeypatch.setattr(app_module, "extract_text_from_pdf", lambda b: "unused")
    big = b"x" * (MAX_SYLLABUS_BYTES + 1)
    resp = _upload(client, big)
    assert resp.status_code == 413
    assert "10 MB" in resp.json()["error"]


def test_unextractable_pdf_returns_400(client, monkeypatch):
    monkeypatch.setattr(app_module, "extract_text_from_pdf", lambda b: "")
    resp = _upload(client, b"%PDF-1.4 not really")
    assert resp.status_code == 400
    assert "could not extract text" in resp.json()["error"].lower()


def test_successful_parse_returns_events(client, monkeypatch):
    monkeypatch.setattr(app_module, "extract_text_from_pdf", lambda b: "CS101 fake syllabus text")

    async def _fake_parse(text):
        return {"events": [
            {"title": "HW1", "date": "2026-03-01", "type": "homework",
             "description": "ch1", "Class": "CS101", "isSyllabus": True},
            {"title": "Midterm", "date": "2026-03-15", "type": "exam",
             "description": "", "Class": "CS101", "isSyllabus": True},
        ]}

    monkeypatch.setattr(app_module, "parse_with_gemini", _fake_parse)

    resp = _upload(client, b"%PDF-1.4 ...")
    assert resp.status_code == 200
    body = resp.json()
    assert body["filename"] == "syllabus.pdf"
    assert [e["title"] for e in body["events"]] == ["HW1", "Midterm"]
    # No meeting times in this fake response → schedule is null.
    assert body["schedule"] is None


def test_successful_parse_passes_through_meeting_schedule(client, monkeypatch):
    monkeypatch.setattr(app_module, "extract_text_from_pdf", lambda b: "CS101 fake syllabus text")

    async def _fake_parse(text):
        return {
            "events": [{"title": "HW1", "date": "2026-03-01", "type": "homework",
                        "description": "", "Class": "CS101", "isSyllabus": True}],
            "schedule": {
                "lecture_days": ["MO", "we", "FR", "garbage"], "lecture_start": "10:00",
                "lecture_end": "10:50", "section_days": ["TH"], "section_start": "15:00",
                "section_end": None, "final_date": "2026-12-12", "final_start": "16:00",
                "final_end": "19:00",
            },
        }

    monkeypatch.setattr(app_module, "parse_with_gemini", _fake_parse)

    body = _upload(client, b"%PDF-1.4 ...").json()
    sched = body["schedule"]
    assert sched["lecture_days"] == ["MO", "WE", "FR"]   # normalized + garbage dropped
    assert sched["lecture_start"] == "10:00" and sched["lecture_end"] == "10:50"
    assert sched["section_days"] == ["TH"] and sched["section_start"] == "15:00"
    assert sched["section_end"] is None
    assert sched["final_date"] == "2026-12-12"
    assert sched["final_start"] == "16:00" and sched["final_end"] == "19:00"


def test_parse_drops_days_without_a_start_time(client, monkeypatch):
    monkeypatch.setattr(app_module, "extract_text_from_pdf", lambda b: "text")

    async def _fake_parse(text):
        return {
            "events": [{"title": "HW1", "date": "2026-03-01", "type": "homework",
                        "description": "", "Class": "CS101", "isSyllabus": True}],
            "schedule": {"lecture_days": ["MO", "WE"], "section_days": [],
                         "final_date": "not-a-date"},
        }

    monkeypatch.setattr(app_module, "parse_with_gemini", _fake_parse)

    # lecture has no start time, no section, bad final date → nothing usable.
    assert _upload(client, b"%PDF-1.4 ...").json()["schedule"] is None


def test_parse_failure_surfaces_as_400(client, monkeypatch):
    monkeypatch.setattr(app_module, "extract_text_from_pdf", lambda b: "some text")

    async def _fail(text):
        raise app_module.SyllabusParsingError("Gemini did not return a parseable response.")

    monkeypatch.setattr(app_module, "parse_with_gemini", _fail)

    resp = _upload(client, b"%PDF-1.4 ...")
    assert resp.status_code == 400
    assert "parseable" in resp.json()["error"].lower()
