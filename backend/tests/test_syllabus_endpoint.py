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


def test_parse_failure_surfaces_as_400(client, monkeypatch):
    monkeypatch.setattr(app_module, "extract_text_from_pdf", lambda b: "some text")

    async def _fail(text):
        raise app_module.SyllabusParsingError("Gemini did not return a parseable response.")

    monkeypatch.setattr(app_module, "parse_with_gemini", _fail)

    resp = _upload(client, b"%PDF-1.4 ...")
    assert resp.status_code == 400
    assert "parseable" in resp.json()["error"].lower()
