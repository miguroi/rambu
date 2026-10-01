from pathlib import Path
from datetime import datetime

from fastapi.testclient import TestClient

from rambu_api.app import create_app
from rambu_api.langflow_client import LangflowFailure
from rambu_api.models import RiskAssessment
from rambu_api.pilot import PilotStore
from rambu_api.protection import ProtectionService

from .conftest import wav_bytes
from .test_api import StubDemoService


class TextTranscriber:
    def __init__(self, text: str = "Halo") -> None:
        self.text = text
        self.calls = 0

    def transcribe(self, path: Path) -> str:
        self.calls += 1
        return self.text


class LowRiskAnalyzer:
    def __init__(self, error: Exception | None = None) -> None:
        self.error = error

    def analyze(self, transcript: str, final: bool) -> RiskAssessment:
        if self.error is not None:
            raise self.error
        return RiskAssessment(
            risk_level="low",
            signals=[],
            evidence=[],
            explanation="Tidak ada tanda penipuan.",
            recommended_action="Tetap waspada.",
        )


def auth(token: str) -> dict[str, str]:
    return {"authorization": f"Bearer {token}"}


def session_payload(call_id: str = "7f011753-8f09-4a45-8812-8a4591a96b3c") -> dict:
    return {
        "call_id": call_id,
        "started_at": "2026-10-01T10:00:00Z",
        "channel": None,
    }


def build_client(
    *, analyzer: LowRiskAnalyzer | None = None
) -> tuple[TestClient, PilotStore, TextTranscriber, ProtectionService]:
    store = PilotStore(":memory:")
    transcriber = TextTranscriber()
    protection = ProtectionService(store, transcriber, analyzer or LowRiskAnalyzer())
    app = create_app(
        service=StubDemoService(),
        pilot_store=store,
        protection_service=protection,
    )
    return TestClient(app), store, transcriber, protection


def test_protection_routes_complete_authenticated_parent_and_puck_flow() -> None:
    client, store, _, _ = build_client()
    parent = store.create_family("Ibu Ratna")

    paired_response = client.post(
        "/api/pucks/pair",
        json={"code": parent.invite_code, "display_name": "Mac ruang tamu"},
    )
    assert paired_response.status_code == 201
    puck_token = paired_response.json()["access_token"]

    created_response = client.post(
        "/api/protection/sessions",
        headers=auth(parent.access_token),
        json=session_payload(),
    )
    assert created_response.status_code == 201
    session_id = created_response.json()["id"]
    assert created_response.json()["status"] == "waiting_for_puck"

    repeated = client.post(
        "/api/protection/sessions",
        headers=auth(parent.access_token),
        json=session_payload(),
    )
    assert repeated.status_code == 201
    assert repeated.json()["id"] == session_id

    claimed = client.get("/api/pucks/sessions/active", headers=auth(puck_token))
    assert claimed.status_code == 200
    assert claimed.json()["status"] == "listening"

    chunk = client.post(
        f"/api/pucks/sessions/{session_id}/chunks",
        headers={
            **auth(puck_token),
            "content-type": "audio/wav",
            "x-rambu-sequence": "0",
            "x-rambu-final": "false",
        },
        content=wav_bytes(),
    )
    assert chunk.status_code == 200
    assert chunk.json()["masked_transcript"] == "Halo"

    status = client.get(
        f"/api/protection/sessions/{session_id}", headers=auth(parent.access_token)
    )
    assert status.status_code == 200
    assert status.json()["assessment"]["risk_level"] == "low"

    ending = client.post(
        f"/api/protection/sessions/{session_id}/end", headers=auth(parent.access_token)
    )
    assert ending.status_code == 200
    assert ending.json()["end_requested"] is True

    final = client.post(
        f"/api/pucks/sessions/{session_id}/chunks",
        headers={
            **auth(puck_token),
            "content-type": "audio/wav",
            "x-rambu-sequence": "1",
            "x-rambu-final": "true",
        },
        content=wav_bytes(seconds=0),
    )
    assert final.status_code == 200
    assert final.json()["status"] == "completed"

    deleted = client.delete(
        f"/api/protection/sessions/{session_id}", headers=auth(parent.access_token)
    )
    assert deleted.status_code == 204


def test_parent_and_puck_credentials_cannot_cross_roles() -> None:
    client, store, _, _ = build_client()
    parent = store.create_family("Ibu Ratna")
    puck = store.pair_puck(parent.invite_code or "", "Mac")
    session = store.create_protection_session(
        parent.access_token,
        session_payload()["call_id"],
        datetime.fromisoformat("2026-10-01T10:00:00+00:00"),
        None,
    )

    assert client.post(
        "/api/protection/sessions", headers=auth(puck.access_token), json=session_payload()
    ).status_code == 401
    assert client.get(
        "/api/pucks/sessions/active", headers=auth(parent.access_token)
    ).status_code == 401
    assert client.post(
        f"/api/protection/sessions/{session.id}/end", headers=auth(puck.access_token)
    ).status_code == 401


def test_chunk_requires_wav_content_type_and_both_valid_headers() -> None:
    client, store, _, _ = build_client()
    parent = store.create_family("Ibu Ratna")
    puck = store.pair_puck(parent.invite_code or "", "Mac")
    session = store.create_protection_session(
        parent.access_token,
        session_payload()["call_id"],
        datetime.fromisoformat("2026-10-01T10:00:00+00:00"),
        None,
    )
    store.active_protection_session(puck.access_token)
    path = f"/api/pucks/sessions/{session.id}/chunks"

    assert client.post(path, headers=auth(puck.access_token), content=wav_bytes()).status_code == 422
    assert client.post(
        path,
        headers={**auth(puck.access_token), "content-type": "audio/wav"},
        content=wav_bytes(),
    ).status_code == 422
    assert client.post(
        path,
        headers={
            **auth(puck.access_token),
            "content-type": "audio/wav",
            "x-rambu-sequence": "zero",
            "x-rambu-final": "sometimes",
        },
        content=wav_bytes(),
    ).status_code == 422
    assert client.post(
        path,
        headers={
            **auth(puck.access_token),
            "content-type": "audio/wav",
            "x-rambu-sequence": "0",
            "x-rambu-final": "false",
        },
        content=b"0" * (1_048_576 + 1),
    ).status_code == 413


def test_chunk_retry_is_idempotent_and_sequence_conflict_is_409() -> None:
    client, store, transcriber, _ = build_client()
    parent = store.create_family("Ibu Ratna")
    puck = store.pair_puck(parent.invite_code or "", "Mac")
    session = store.create_protection_session(
        parent.access_token,
        session_payload()["call_id"],
        datetime.fromisoformat("2026-10-01T10:00:00+00:00"),
        None,
    )
    store.active_protection_session(puck.access_token)
    path = f"/api/pucks/sessions/{session.id}/chunks"
    headers = {
        **auth(puck.access_token),
        "content-type": "audio/wav",
        "x-rambu-sequence": "0",
        "x-rambu-final": "false",
    }

    assert client.post(path, headers=headers, content=wav_bytes()).status_code == 200
    assert client.post(path, headers=headers, content=wav_bytes()).status_code == 200
    assert transcriber.calls == 1
    assert client.post(path, headers=headers, content=wav_bytes(seconds=2)).status_code == 409


def test_langflow_failure_returns_sanitized_502_without_fallback() -> None:
    client, store, _, _ = build_client(
        analyzer=LowRiskAnalyzer(
            LangflowFailure(
                "timeout",
                "Langflow tidak merespons sebelum batas waktu.",
                "http://secret.internal/api/v1/run/key",
            )
        )
    )
    parent = store.create_family("Ibu Ratna")
    puck = store.pair_puck(parent.invite_code or "", "Mac")
    session = store.create_protection_session(
        parent.access_token,
        session_payload()["call_id"],
        datetime.fromisoformat("2026-10-01T10:00:00+00:00"),
        None,
    )
    store.active_protection_session(puck.access_token)

    response = client.post(
        f"/api/pucks/sessions/{session.id}/chunks",
        headers={
            **auth(puck.access_token),
            "content-type": "audio/wav",
            "x-rambu-sequence": "0",
            "x-rambu-final": "false",
        },
        content=wav_bytes(),
    )

    assert response.status_code == 502
    assert response.json() == {
        "detail": {
            "code": "analysis_timeout",
            "message": "Langflow tidak merespons sebelum batas waktu.",
        }
    }
    assert "secret.internal" not in response.text


def test_untyped_analyzer_failure_uses_persisted_analysis_error_not_transcription_error() -> None:
    client, store, _, _ = build_client(
        analyzer=LowRiskAnalyzer(RuntimeError("provider implementation crashed"))
    )
    parent = store.create_family("Ibu Ratna")
    puck = store.pair_puck(parent.invite_code or "", "Mac")
    session = store.create_protection_session(
        parent.access_token,
        session_payload()["call_id"],
        datetime.fromisoformat("2026-10-01T10:00:00+00:00"),
        None,
    )
    store.active_protection_session(puck.access_token)

    response = client.post(
        f"/api/pucks/sessions/{session.id}/chunks",
        headers={
            **auth(puck.access_token),
            "content-type": "audio/wav",
            "x-rambu-sequence": "0",
            "x-rambu-final": "false",
        },
        content=wav_bytes(),
    )

    assert response.status_code == 502
    assert response.json()["detail"] == {
        "code": "analysis_failed",
        "message": "Analisis panggilan gagal.",
    }
    assert "provider implementation crashed" not in response.text
