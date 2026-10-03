from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime

from fastapi.testclient import TestClient

from rambu_api.app import create_app
from rambu_api.models import PilotAlertInput, RiskAssessment
from rambu_api.pilot import DecisionConflict, PilotStore

from .test_api import StubDemoService


class RecordingPushSender:
    def __init__(self) -> None:
        self.sent: list[tuple[list[str], str, str, str]] = []

    def send(self, tokens: list[str], title: str, body: str, alert_id: str) -> None:
        self.sent.append((tokens, title, body, alert_id))

    def close(self) -> None:
        pass


def authorization(token: str) -> dict[str, str]:
    return {"authorization": f"Bearer {token}"}


def alert_payload(alert_id: str = "98f73943-b925-4984-a26d-0e193e1521a4") -> dict:
    return {
        "id": alert_id,
        "caller_detail": "+62 812-••••-4417",
        "channel": "cellular",
        "started_at": "2026-10-01T10:00:00Z",
        "raised_at": "2026-10-01T10:00:10Z",
        "level": "danger",
        "signals": ["impersonation", "secretCode"],
        "evidence": [
            {
                "id": 2,
                "offset": 10,
                "speaker": "caller",
                "text": "Tolong bacakan kode OTP itu.",
                "flagged": ["bacakan kode OTP"],
                "signals": ["secretCode"],
            }
        ],
    }


def test_two_devices_share_alert_and_first_guardian_decision_wins() -> None:
    store = PilotStore(":memory:")
    pushes = RecordingPushSender()
    app = create_app(service=StubDemoService(), pilot_store=store, push_sender=pushes)

    with TestClient(app) as client:
        parent = client.post("/api/pilot/families", json={"parent_name": "Ibu Ratna"})
        assert parent.status_code == 201
        parent_session = parent.json()
        code = parent_session["invite_code"]

        first = client.post(
            "/api/pilot/families/join",
            json={"code": code, "name": "Sinta", "relation": "Anak"},
        ).json()
        second = client.post(
            "/api/pilot/families/join",
            json={"code": code, "name": "Richard", "relation": "Anak"},
        ).json()

        assert client.put(
            "/api/pilot/push-token",
            headers=authorization(parent_session["access_token"]),
            json={"token": "aa" * 32, "environment": "sandbox"},
        ).status_code == 204
        assert client.put(
            "/api/pilot/push-token",
            headers=authorization(first["access_token"]),
            json={"token": "bb" * 32, "environment": "sandbox"},
        ).status_code == 204

        published = client.post(
            "/api/pilot/alerts",
            headers=authorization(parent_session["access_token"]),
            json=alert_payload(),
        )
        assert published.status_code == 201
        assert [person["name"] for person in published.json()["recipients"]] == ["Sinta", "Richard"]
        assert pushes.sent[0][0] == ["bb" * 32]
        assert "mungkin sedang ditipu" in pushes.sent[0][1]

        duplicate = client.post(
            "/api/pilot/alerts",
            headers=authorization(parent_session["access_token"]),
            json=alert_payload(),
        )
        assert duplicate.status_code == 201
        assert len(pushes.sent) == 1

        received = client.get(
            "/api/pilot/alerts", headers=authorization(first["access_token"])
        )
        assert received.status_code == 200
        assert received.json()[0]["evidence"][0]["text"] == "Tolong bacakan kode OTP itu."

        accepted = client.post(
            f"/api/pilot/alerts/{alert_payload()['id']}/decision",
            headers=authorization(first["access_token"]),
            json={"verdict": "scam"},
        )
        assert accepted.status_code == 200
        assert accepted.json()["accepted"] is True
        assert accepted.json()["decision"]["by"]["name"] == "Sinta"
        assert pushes.sent[1][0] == ["aa" * 32]
        assert pushes.sent[1][2] == "Tutup telepon sekarang."

        rejected = client.post(
            f"/api/pilot/alerts/{alert_payload()['id']}/decision",
            headers=authorization(second["access_token"]),
            json={"verdict": "safe"},
        )
        assert rejected.status_code == 409
        assert rejected.json()["accepted"] is False
        assert rejected.json()["decision"]["by"]["name"] == "Sinta"

        ended = client.post(
            f"/api/pilot/alerts/{alert_payload()['id']}/end",
            headers=authorization(parent_session["access_token"]),
        )
        assert ended.status_code == 200
        assert ended.json()["call_ended"] is True


def test_pilot_rejects_invalid_credentials_and_roles() -> None:
    app = create_app(service=StubDemoService(), pilot_store=PilotStore(":memory:"))

    with TestClient(app) as client:
        parent = client.post("/api/pilot/families", json={"parent_name": "Ibu Ratna"}).json()
        guardian = client.post(
            "/api/pilot/families/join",
            json={"code": parent["invite_code"], "name": "Sinta", "relation": "Anak"},
        ).json()

        assert client.get("/api/pilot/profile").status_code == 401
        assert client.get(
            "/api/pilot/profile", headers=authorization("wrong-token")
        ).status_code == 401
        assert client.post(
            "/api/pilot/alerts",
            headers=authorization(guardian["access_token"]),
            json=alert_payload(),
        ).status_code == 403
        assert client.post(
            f"/api/pilot/alerts/{alert_payload()['id']}/decision",
            headers=authorization(parent["access_token"]),
            json={"verdict": "scam"},
        ).status_code == 403


def test_store_atomically_accepts_only_one_concurrent_decision() -> None:
    store = PilotStore(":memory:")
    parent = store.create_family("Ibu Ratna")
    first = store.join_family(parent.invite_code or "", "Sinta", "Anak")
    second = store.join_family(parent.invite_code or "", "Richard", "Anak")

    from rambu_api.models import PilotAlertInput

    store.publish_alert(parent.access_token, PilotAlertInput.model_validate(alert_payload()))

    def decide(token: str, verdict: str) -> str:
        try:
            return store.decide(token, alert_payload()["id"], verdict).by.name
        except DecisionConflict as error:
            return f"lost:{error.decision.by.name}"

    with ThreadPoolExecutor(max_workers=2) as executor:
        results = list(
            executor.map(
                lambda args: decide(*args),
                [(first.access_token, "scam"), (second.access_token, "safe")],
            )
        )

    winners = [result for result in results if not result.startswith("lost:")]
    losers = [result for result in results if result.startswith("lost:")]
    assert len(winners) == 1
    assert losers == [f"lost:{winners[0]}"]
    store.close()


def test_legacy_parent_publish_is_idempotent_with_backend_alert() -> None:
    store = PilotStore(":memory:")
    parent = store.create_family("Ibu Ratna")
    puck = store.pair_puck(parent.invite_code or "", "Mac")
    session = store.create_protection_session(
        parent.access_token,
        alert_payload()["id"],
        datetime(2026, 10, 1, 10, 0, tzinfo=UTC),
        "cellular",
        "Panggilan terdeteksi",
        "+62 812-••••-4417",
    )
    store.active_protection_session(puck.access_token)
    store.record_protection_chunk(
        puck.access_token,
        session.id,
        sequence=0,
        digest="digest-zero",
        masked_transcript="Halo OTP transfer",
        assessment=RiskAssessment(
            risk_level="high_risk",
            signals=["secret_code", "transfer"],
            evidence=[
                {"quote": "OTP", "signals": ["secret_code"]},
                {"quote": "transfer", "signals": ["transfer"]},
            ],
            explanation="Penelepon meminta kode dan transfer.",
            recommended_action="Tutup telepon sekarang.",
        ),
        final=False,
    )
    backend_alert, backend_should_notify = store.upsert_protection_alert(
        puck.access_token, session.id
    )
    legacy = alert_payload()
    legacy["level"] = "review"

    published, legacy_should_notify = store.publish_alert_result(
        parent.access_token,
        PilotAlertInput.model_validate(legacy),
    )

    assert backend_alert is not None
    assert backend_should_notify is True
    assert legacy_should_notify is False
    assert published.level == "danger"
    assert len(published.evidence) == 2
