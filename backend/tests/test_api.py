from fastapi.testclient import TestClient

from rambu_api.app import create_app
from rambu_api.models import ChunkAnalysisResponse, DemoSnapshot, RiskAssessment

from .conftest import wav_bytes


class StubDemoService:
    def __init__(self) -> None:
        self.deleted: list[str] = []

    def start(self, scenario: str) -> DemoSnapshot:
        if scenario == "missing":
            raise KeyError(scenario)
        return DemoSnapshot(
            id="demo-1",
            scenario=scenario,
            title="Permintaan OTP",
            status="running",
            progress=0,
            transcript="",
            assessment=None,
            error=None,
        )

    def get(self, session_id: str) -> DemoSnapshot:
        if session_id != "demo-1":
            raise KeyError(session_id)
        return DemoSnapshot(
            id="demo-1",
            scenario="otp",
            title="Permintaan OTP",
            status="completed",
            progress=100,
            transcript="Berikan OTP [KODE].",
            assessment=None,
            error=None,
        )

    def delete(self, session_id: str) -> None:
        if session_id != "demo-1":
            raise KeyError(session_id)
        self.deleted.append(session_id)

    def close(self) -> None:
        pass

    def analyze_chunk(self, audio: bytes, final: bool) -> ChunkAnalysisResponse:
        return ChunkAnalysisResponse(
            transcript="Berikan OTP [KODE].",
            assessment=RiskAssessment(
                risk_level="high_risk",
                indicators=["Meminta OTP [KODE]"],
                explanation="Meminta kode rahasia.",
                recommended_action="Tutup telepon.",
            ),
        )


def test_dashboard_and_demo_api_contract() -> None:
    service = StubDemoService()
    client = TestClient(create_app(service=service))

    page = client.get("/")
    started = client.post("/api/demo/otp")
    status = client.get("/api/demo/demo-1")
    deleted = client.delete("/api/demo/demo-1")

    assert page.status_code == 200
    assert "Rambu" in page.text
    assert "Simulasi" in page.text
    assert started.status_code == 201
    assert started.json()["id"] == "demo-1"
    assert status.json()["progress"] == 100
    assert deleted.status_code == 204
    assert service.deleted == ["demo-1"]


def test_unknown_demo_returns_not_found() -> None:
    client = TestClient(create_app(service=StubDemoService()))

    assert client.post("/api/demo/missing").status_code == 404
    assert client.get("/api/demo/missing").status_code == 404
    assert client.delete("/api/demo/missing").status_code == 404


def test_live_chunk_requires_consent_and_returns_masked_analysis() -> None:
    client = TestClient(create_app(service=StubDemoService()))

    denied = client.post("/api/analyze-chunk", content=wav_bytes(), headers={"content-type": "audio/wav"})
    accepted = client.post(
        "/api/analyze-chunk",
        content=wav_bytes(),
        headers={"content-type": "audio/wav", "x-rambu-consent": "true", "x-rambu-final": "false"},
    )

    assert denied.status_code == 403
    assert accepted.status_code == 200
    assert accepted.json()["transcript"] == "Berikan OTP [KODE]."
    assert accepted.json()["assessment"]["risk_level"] == "high_risk"
