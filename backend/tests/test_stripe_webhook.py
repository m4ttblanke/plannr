"""Tests for POST /stripe/webhook — TestFlight payment fulfillment + the
beta_purchasers backstop write."""

import pytest
from fastapi.testclient import TestClient

from app import app


@pytest.fixture
def client():
    return TestClient(app)


@pytest.fixture(autouse=True)
def _webhook_secret(monkeypatch):
    monkeypatch.setattr("app.settings.stripe_webhook_secret", "whsec_test", raising=False)


class _Obj(dict):
    def to_dict(self):
        return dict(self)


def _install_event(monkeypatch, event_type, obj):
    """Make stripe.Webhook.construct_event return a fixed event, bypassing the
    signature check."""
    event = {"type": event_type, "data": {"object": _Obj(obj)}}
    monkeypatch.setattr("app.stripe.Webhook.construct_event",
                        lambda payload, sig, secret: event)


_PAID_SESSION = {
    "id": "cs_test_123",
    "payment_status": "paid",
    "amount_total": 900,
    "currency": "usd",
    "customer_details": {"email": "beta@example.com"},
}


@pytest.mark.parametrize("event_type", [
    "checkout.session.completed",
    "checkout.session.async_payment_succeeded",
])
def test_webhook_records_beta_purchaser(client, monkeypatch, event_type):
    calls = []
    monkeypatch.setattr("app.record_beta_purchase",
                        lambda **kw: calls.append(kw) or True)
    _install_event(monkeypatch, event_type, _PAID_SESSION)

    resp = client.post("/stripe/webhook", content=b"{}",
                       headers={"stripe-signature": "t=1,v1=deadbeef"})

    assert resp.status_code == 200
    assert calls == [{
        "stripe_session_id": "cs_test_123",
        "email": "beta@example.com",
        "amount_total": 900,
        "currency": "usd",
    }]


def test_webhook_does_not_record_unpaid_session(client, monkeypatch):
    calls = []
    monkeypatch.setattr("app.record_beta_purchase",
                        lambda **kw: calls.append(kw) or True)
    _install_event(monkeypatch, "checkout.session.completed",
                   {**_PAID_SESSION, "payment_status": "unpaid"})

    resp = client.post("/stripe/webhook", content=b"{}",
                       headers={"stripe-signature": "sig"})

    assert resp.status_code == 200
    assert calls == []


def test_webhook_still_200_when_backstop_write_raises(client, monkeypatch):
    def _boom(**kw):
        raise RuntimeError("db down")
    monkeypatch.setattr("app.record_beta_purchase", _boom)
    _install_event(monkeypatch, "checkout.session.completed", _PAID_SESSION)

    resp = client.post("/stripe/webhook", content=b"{}",
                       headers={"stripe-signature": "sig"})

    assert resp.status_code == 200
    assert resp.json() == {"received": True}


def test_webhook_rejects_bad_signature(client, monkeypatch):
    def _bad(payload, sig, secret):
        raise ValueError("bad sig")
    monkeypatch.setattr("app.stripe.Webhook.construct_event", _bad)
    monkeypatch.setattr("app.record_beta_purchase",
                        lambda **kw: pytest.fail("should not run on bad signature"))

    resp = client.post("/stripe/webhook", content=b"{}",
                       headers={"stripe-signature": "nope"})

    assert resp.status_code == 400


def test_webhook_500_when_secret_unset(client, monkeypatch):
    monkeypatch.setattr("app.settings.stripe_webhook_secret", None, raising=False)
    resp = client.post("/stripe/webhook", content=b"{}",
                       headers={"stripe-signature": "sig"})
    assert resp.status_code == 500
