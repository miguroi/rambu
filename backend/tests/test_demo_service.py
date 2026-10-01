import time
from pathlib import Path

from rambu_api.demo import DemoService, Scenario
from rambu_api.models import RiskAssessment

from .conftest import write_test_wav


class SequentialTranscriber:
    def __init__(self, texts: list[str]) -> None:
        self.texts = iter(texts)
        self.paths: list[Path] = []

    def transcribe(self, path: Path) -> str:
        assert path.exists()
        self.paths.append(path)
        return next(self.texts)


class EvidenceAnalyzer:
    def __init__(self) -> None:
        self.inputs: list[str] = []

    def analyze(self, transcript: str, final: bool) -> RiskAssessment:
        self.inputs.append(transcript)
        high = "OTP [KODE]" in transcript
        return RiskAssessment(
            risk_level="high_risk" if high else "needs_review",
            indicators=["Meminta OTP [KODE]"] if high else [],
            explanation="Ada permintaan kode rahasia." if high else "Belum cukup bukti.",
            recommended_action="Akhiri panggilan." if high else "Tetap waspada.",
        )


def wait_for_completion(service: DemoService, session_id: str):
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline:
        snapshot = service.get(session_id)
        if snapshot.status in {"completed", "error"}:
            return snapshot
        time.sleep(0.01)
    raise AssertionError("demo did not finish")


def test_demo_processes_chunks_masks_transcript_and_removes_temporary_files(tmp_path) -> None:
    audio = write_test_wav(tmp_path / "otp.wav", seconds=6)
    transcriber = SequentialTranscriber(
        ["Saya dari bank dan perlu verifikasi.", "Berikan OTP 482913 sekarang."]
    )
    analyzer = EvidenceAnalyzer()
    service = DemoService(
        scenarios={
            "otp": Scenario("otp", "Permintaan OTP", "Uji risiko tinggi", audio, "high_risk")
        },
        transcriber=transcriber,
        analyzer=analyzer,
        delay_seconds=0,
    )

    started = service.start("otp")
    completed = wait_for_completion(service, started.id)

    assert completed.status == "completed"
    assert completed.progress == 100
    assert completed.assessment is not None
    assert completed.assessment.risk_level == "high_risk"
    assert "482913" not in analyzer.inputs[-1]
    assert "OTP [KODE]" in analyzer.inputs[-1]
    assert all(not path.exists() for path in transcriber.paths)
    service.close()


def test_unknown_scenario_is_rejected() -> None:
    service = DemoService({}, SequentialTranscriber([]), EvidenceAnalyzer(), delay_seconds=0)

    try:
        service.start("missing")
    except KeyError as error:
        assert error.args == ("missing",)
    else:
        raise AssertionError("missing scenario was accepted")
    finally:
        service.close()


def test_live_chunk_is_masked_before_analysis_and_temporary_audio_is_removed(tmp_path) -> None:
    transcriber = SequentialTranscriber(["Tolong sebutkan OTP 482913 sekarang."])
    analyzer = EvidenceAnalyzer()
    service = DemoService({}, transcriber, analyzer, delay_seconds=0)

    from .conftest import wav_bytes

    result = service.analyze_chunk(wav_bytes(seconds=1), final=False)

    assert result.transcript == "Tolong sebutkan OTP [KODE] sekarang."
    assert analyzer.inputs == [result.transcript]
    assert all(not path.exists() for path in transcriber.paths)
    service.close()
