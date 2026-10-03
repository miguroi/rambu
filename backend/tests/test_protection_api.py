from pathlib import Path
from datetime import UTC, datetime, timedelta
from uuid import uuid4

from fastapi.testclient import TestClient

from rambu_api.app import create_app
from rambu_api.langflow_client import LangflowFailure
from rambu_api.models import ProtectionFailure, RiskAssessment
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


class HighRiskAnalyzer:
    def analyze(self, transcript: str, final: bool) -> RiskAssessment:
        return RiskAssessment(
            risk_level="high_risk",
            signals=["secret_code", "transfer"],
            evidence=[
                {"quote": "Halo", "signals": ["secret_code", "transfer"]},
            ],
            explanation="Penelepon meminta kode dan transfer.",
            recommended_action="Tutup telepon sekarang.",
        )


class RecordingProtectionPushSender:
    def __init__(self) -> None:
        self.sent: list[tuple[list[str], str, str, str]] = []

    def send(self, tokens: list[str], title: str, body: str, alert_id: str) -> None:
        self.sent.append((tokens, title, body, alert_id))

    def close(self) -> None:
        pass


def auth(token: str) -> dict[str, str]:
    return {"authorization": f"Bearer {token}"}


def session_payload(call_id: str = "7f011753-8f09-4a45-8812-8a4591a96b3c") -> dict:
    return {
        "call_id": call_id,
        "started_at": "2026-10-01T10:00:00Z",
        "channel": None,
    }


def build_client(
    *, analyzer: LowRiskAnalyzer | HighRiskAnalyzer | None = None,
    push_sender: RecordingProtectionPushSender | None = None,
) -> tuple[TestClient, PilotStore, TextTranscriber, ProtectionService]:
    store = PilotStore(":memory:")
    transcriber = TextTranscriber()
    protection = ProtectionService(store, transcriber, analyzer or LowRiskAnalyzer())
    app = create_app(
        service=StubDemoService(),
        pilot_store=store,
        protection_service=protection,
        push_sender=push_sender,
    )
    return TestClient(app), store, transcriber, protection


def finish_store_session(
    store: PilotStore,
    parent_token: str,
    puck_token: str,
    *,
    call_id: str,
    started_at: datetime,
    assessment: RiskAssessment,
    title: str,
) -> None:
    session = store.create_protection_session(
        parent_token,
        call_id,
        started_at,
        "cellular",
        title,
        "+62 812-••••-4417",
    )
    store.active_protection_session(puck_token)
    store.record_protection_chunk(
        puck_token,
        session.id,
        sequence=0,
        digest=f"digest-{call_id}",
        masked_transcript="Halo dari pihak bank.",
        assessment=assessment,
        final=True,
    )
    ended_at = started_at + timedelta(seconds=45)
    with store._connection:
        store._connection.execute(
            "UPDATE protection_sessions SET ended_at = ? WHERE id = ?",
            (ended_at.isoformat(), session.id),
        )


def test_high_risk_chunk_pushes_parent_once_when_risk_increases() -> None:
    pushes = RecordingProtectionPushSender()
    client, store, _, _ = build_client(
        analyzer=HighRiskAnalyzer(), push_sender=pushes
    )
    parent = store.create_family("Ibu Ratna")
    store.register_push_token(parent.access_token, "aa" * 32, "sandbox")
    puck = store.pair_puck(parent.invite_code or "", "Mac")
    session = store.create_protection_session(
        parent.access_token,
        session_payload()["call_id"],
        datetime.fromisoformat("2026-10-01T10:00:00+00:00"),
        None,
    )
    store.active_protection_session(puck.access_token)
    path = f"/api/pucks/sessions/{session.id}/chunks"

    first = client.post(
        path,
        headers={
            **auth(puck.access_token),
            "content-type": "audio/wav",
            "x-rambu-sequence": "0",
            "x-rambu-final": "false",
        },
        content=wav_bytes(),
    )
    second = client.post(
        path,
        headers={
            **auth(puck.access_token),
            "content-type": "audio/wav",
            "x-rambu-sequence": "1",
            "x-rambu-final": "false",
        },
        content=wav_bytes(),
    )

    assert first.status_code == 200
    assert second.status_code == 200
    assert pushes.sent == [
        (
            ["aa" * 32],
            "Bahaya: terindikasi penipuan",
            "Jangan berikan kode atau transfer. Tutup telepon sekarang.",
            session_payload()["call_id"],
        )
    ]


def test_parent_and_guardian_share_safe_review_danger_and_unassessed_history() -> None:
    client, store, _, _ = build_client()
    parent = store.create_family("Ibu Ratna")
    guardian = store.join_family(parent.invite_code or "", "Richard", "Anak")
    puck = store.pair_puck(parent.invite_code or "", "Mac")
    start = datetime(2026, 10, 3, 10, 0, tzinfo=UTC)

    finish_store_session(
        store,
        parent.access_token,
        puck.access_token,
        call_id="10000000-0000-0000-0000-000000000001",
        started_at=start,
        title="Telepon aman",
        assessment=RiskAssessment(
            risk_level="low",
            signals=[],
            evidence=[],
            explanation="Tidak ada tanda penipuan.",
            recommended_action="Tetap waspada.",
        ),
    )
    finish_store_session(
        store,
        parent.access_token,
        puck.access_token,
        call_id="10000000-0000-0000-0000-000000000002",
        started_at=start + timedelta(minutes=1),
        title="Telepon perlu ditinjau",
        assessment=RiskAssessment(
            risk_level="needs_review",
            signals=["impersonation"],
            evidence=[{"quote": "pihak bank", "signals": ["impersonation"]}],
            explanation="Penelepon mengaku dari bank.",
            recommended_action="Verifikasi melalui kanal resmi.",
        ),
    )
    finish_store_session(
        store,
        parent.access_token,
        puck.access_token,
        call_id="10000000-0000-0000-0000-000000000003",
        started_at=start + timedelta(minutes=2),
        title="Telepon bahaya",
        assessment=RiskAssessment(
            risk_level="high_risk",
            signals=["secret_code", "remote_app"],
            evidence=[
                {"quote": "Halo", "signals": ["secret_code"]},
                {"quote": "pihak bank", "signals": ["remote_app"]},
            ],
            explanation="Penelepon meminta akses sensitif.",
            recommended_action="Tutup telepon sekarang.",
        ),
    )
    no_speech = store.create_protection_session(
        parent.access_token,
        "10000000-0000-0000-0000-000000000004",
        start + timedelta(minutes=3),
        "cellular",
        "Tidak terdengar",
        "Nomor tidak tersedia",
    )
    store.request_protection_end(parent.access_token, no_speech.id)
    failed = store.create_protection_session(
        parent.access_token,
        "10000000-0000-0000-0000-000000000005",
        start + timedelta(minutes=4),
        "cellular",
        "Analisis gagal",
        "Nomor tidak tersedia",
    )
    store.active_protection_session(puck.access_token)
    store.fail_protection_session(
        puck.access_token,
        failed.id,
        ProtectionFailure(code="analysis_timeout", message="Analisis panggilan gagal."),
    )

    parent_response = client.get(
        "/api/pilot/history", headers=auth(parent.access_token)
    )
    guardian_response = client.get(
        "/api/pilot/history", headers=auth(guardian.access_token)
    )

    assert parent_response.status_code == 200
    assert guardian_response.status_code == 200
    assert guardian_response.json() == parent_response.json()
    records = {record["title"]: record for record in parent_response.json()}
    assert records["Telepon aman"]["presentation"] == "safe"
    assert records["Telepon perlu ditinjau"]["presentation"] == "review"
    assert records["Telepon bahaya"]["presentation"] == "danger"
    assert records["Telepon bahaya"]["signals"] == ["secretCode", "remoteApp"]
    assert records["Telepon bahaya"]["evidence"] == [
        {
            "id": 0,
            "offset": 0.0,
            "speaker": "unknown",
            "text": "Halo",
            "flagged": ["Halo"],
            "signals": ["secretCode"],
        },
        {
            "id": 1,
            "offset": 5.0,
            "speaker": "unknown",
            "text": "pihak bank",
            "flagged": ["pihak bank"],
            "signals": ["remoteApp"],
        },
    ]
    assert records["Telepon bahaya"]["duration_seconds"] == 45.0
    assert records["Tidak terdengar"]["outcome"] == "no_speech"
    assert records["Tidak terdengar"]["presentation"] == "unassessed"
    assert records["Tidak terdengar"]["signals"] == []
    assert records["Tidak terdengar"]["evidence"] == []
    assert records["Analisis gagal"]["outcome"] == "error"
    assert records["Analisis gagal"]["presentation"] == "unassessed"
    assert records["Analisis gagal"]["failure"] == {
        "code": "analysis_timeout",
        "message": "Analisis panggilan gagal.",
    }
    assert records["Analisis gagal"]["signals"] == []
    assert records["Analisis gagal"]["evidence"] == []


def test_history_excludes_active_sessions_and_isolates_families() -> None:
    client, store, _, _ = build_client()
    first_parent = store.create_family("Ibu Ratna")
    first_guardian = store.join_family(first_parent.invite_code or "", "Richard", "Anak")
    first_puck = store.pair_puck(first_parent.invite_code or "", "Mac pertama")
    second_parent = store.create_family("Bapak Budi")
    start = datetime(2026, 10, 3, 10, 0, tzinfo=UTC)

    finish_store_session(
        store,
        first_parent.access_token,
        first_puck.access_token,
        call_id="20000000-0000-0000-0000-000000000001",
        started_at=start,
        title="Selesai keluarga pertama",
        assessment=RiskAssessment(
            risk_level="low",
            signals=[],
            evidence=[],
            explanation="Aman.",
            recommended_action="Tetap waspada.",
        ),
    )
    store.create_protection_session(
        first_parent.access_token,
        "20000000-0000-0000-0000-000000000002",
        start + timedelta(minutes=1),
        "cellular",
        "Masih aktif",
        "Nomor tidak tersedia",
    )
    other = store.create_protection_session(
        second_parent.access_token,
        "20000000-0000-0000-0000-000000000003",
        start + timedelta(minutes=2),
        "cellular",
        "Keluarga lain",
        "Nomor tidak tersedia",
    )
    store.request_protection_end(second_parent.access_token, other.id)

    response = client.get(
        "/api/pilot/history", headers=auth(first_guardian.access_token)
    )

    assert response.status_code == 200
    assert [record["title"] for record in response.json()] == [
        "Selesai keluarga pertama"
    ]


def test_history_is_newest_first_and_limited_to_one_hundred() -> None:
    client, store, _, _ = build_client()
    parent = store.create_family("Ibu Ratna")
    start = datetime(2026, 10, 1, 10, 0, tzinfo=UTC)
    call_ids: list[str] = []

    for index in range(101):
        call_id = str(uuid4())
        call_ids.append(call_id)
        session = store.create_protection_session(
            parent.access_token,
            call_id,
            start + timedelta(minutes=index),
            "cellular",
            f"Telepon {index}",
            "Nomor tidak tersedia",
        )
        store.request_protection_end(parent.access_token, session.id)

    response = client.get("/api/pilot/history", headers=auth(parent.access_token))

    assert response.status_code == 200
    assert len(response.json()) == 100
    assert response.json()[0]["id"] == call_ids[-1]
    assert response.json()[-1]["id"] == call_ids[1]


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
