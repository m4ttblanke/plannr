"""Tests for the Gemini retry/backoff logic in parse_with_gemini."""

import asyncio
from unittest.mock import MagicMock, patch

import pytest
from google.genai import errors as genai_errors

import app as app_module
from app import parse_with_gemini, SyllabusParsingError, GEMINI_MAX_ATTEMPTS


def _api_error(code: int, status: str = "UNAVAILABLE") -> genai_errors.APIError:
    return genai_errors.APIError(
        code, {"error": {"code": code, "message": "high demand", "status": status}}
    )


def _fake_success_response():
    response = MagicMock()
    response.text = '{"events": []}'
    return response


@patch("app.asyncio.sleep", return_value=None)
def test_retries_on_503_then_succeeds(mock_sleep):
    """A 503 should be retried and a subsequent success should return normally."""
    mock_client = MagicMock()
    mock_client.models.generate_content.side_effect = [
        _api_error(503),
        _api_error(503),
        _fake_success_response(),
    ]

    with patch.object(app_module, "_gemini_client", mock_client):
        result = asyncio.run(parse_with_gemini("some syllabus text"))

    assert result == {"events": []}
    assert mock_client.models.generate_content.call_count == 3
    assert mock_sleep.call_count == 2  # slept between attempts 1→2 and 2→3


@patch("app.asyncio.sleep", return_value=None)
def test_exhausts_retries_and_raises(mock_sleep):
    """Persistent 503s should raise SyllabusParsingError after GEMINI_MAX_ATTEMPTS."""
    mock_client = MagicMock()
    mock_client.models.generate_content.side_effect = _api_error(503)

    with patch.object(app_module, "_gemini_client", mock_client):
        with pytest.raises(SyllabusParsingError):
            asyncio.run(parse_with_gemini("some syllabus text"))

    assert mock_client.models.generate_content.call_count == GEMINI_MAX_ATTEMPTS


@patch("app.asyncio.sleep", return_value=None)
def test_non_retryable_error_raises_immediately(mock_sleep):
    """A non-retryable status (e.g. 400) should fail fast with no retries."""
    mock_client = MagicMock()
    mock_client.models.generate_content.side_effect = _api_error(400, status="INVALID_ARGUMENT")

    with patch.object(app_module, "_gemini_client", mock_client):
        with pytest.raises(SyllabusParsingError):
            asyncio.run(parse_with_gemini("some syllabus text"))

    assert mock_client.models.generate_content.call_count == 1
    mock_sleep.assert_not_called()
