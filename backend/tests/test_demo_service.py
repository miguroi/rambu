import time
from pathlib import Path

from rambu_api.audio import split_wav
from rambu_api.demo import DemoService, Scenario, default_scenarios
from rambu_api.langflow_client import LangflowFailure
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
            signals=["secret_code"] if high else ["impersonation"],
            evidence=[
                {
                    "quote": "OTP [KODE]" if high else transcript,
                    "signals": ["secret_code"] if high else ["impersonation"],
                }
            ],
            explanation="Ada permintaan kode rahasia." if high else "Belum cukup bukti.",
            recommended_action="Akhiri panggilan." if high else "Tetap waspada.",
        )

    def probe(self) -> None:
        pass


class ThrowingTranscriber:
    def __init__(self) -> None:
        self.paths: list[Path] = []

    def transcribe(self, path: Path) -> str:
        self.paths.append(path)
        raise RuntimeError("raw whisper diagnostic")


class FailingSecondAnalyzer:
    def __init__(self) -> None:
        self.calls = 0
        self.probes = 0

    def analyze(self, transcript: str, final: bool) -> RiskAssessment:
        self.calls += 1
        if self.calls == 2:
            raise LangflowFailure(
                "timeout",
                "Langflow tidak merespons sebelum batas waktu.",
                "http://langflow/api/v1/run/rambu",
            )
        return RiskAssessment(
            risk_level="needs_review",
            signals=["impersonation"],
            evidence=[{"quote": transcript, "signals": ["impersonation"]}],
            explanation="Identitas penelepon belum terverifikasi.",
            recommended_action="Jangan berikan data.",
        )

    def probe(self) -> None:
        self.probes += 1


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


def test_transcription_failure_is_terminal_sanitized_and_removes_temporary_file(tmp_path) -> None:
    audio = write_test_wav(tmp_path / "call.wav", seconds=6)
    transcriber = ThrowingTranscriber()
    analyzer = EvidenceAnalyzer()
    service = DemoService(
        {"bank-otp": Scenario("bank-otp", "OTP", "", audio, "high_risk")},
        transcriber,
        analyzer,
        delay_seconds=0,
    )

    failed = wait_for_completion(service, service.start("bank-otp").id)

    assert failed.status == "error"
    assert failed.progress == 0
    assert failed.assessment is None
    assert failed.error is not None
    assert failed.error.code == "transcription_failed"
    assert "raw whisper diagnostic" not in failed.error.message
    assert analyzer.inputs == []
    assert all(not path.exists() for path in transcriber.paths)
    service.close()


def test_empty_transcription_is_a_terminal_failure(tmp_path) -> None:
    audio = write_test_wav(tmp_path / "silent.wav", seconds=1)
    transcriber = SequentialTranscriber(["   "])
    analyzer = EvidenceAnalyzer()
    service = DemoService(
        {"tetangga-aman": Scenario("tetangga-aman", "Aman", "", audio, "low")},
        transcriber,
        analyzer,
        delay_seconds=0,
    )

    failed = wait_for_completion(service, service.start("tetangga-aman").id)

    assert failed.status == "error"
    assert failed.progress == 0
    assert failed.assessment is None
    assert failed.error is not None
    assert failed.error.code == "transcription_failed"
    assert analyzer.inputs == []
    assert all(not path.exists() for path in transcriber.paths)
    service.close()


def test_analysis_failure_clears_stale_assessment_and_stops_later_chunks(tmp_path) -> None:
    audio = write_test_wav(tmp_path / "call.wav", seconds=11)
    transcriber = SequentialTranscriber(["Saya dari bank.", "Segera jawab.", "Berikan kode."])
    analyzer = FailingSecondAnalyzer()
    service = DemoService(
        {"bank-otp": Scenario("bank-otp", "OTP", "", audio, "high_risk")},
        transcriber,
        analyzer,
        delay_seconds=0,
    )

    failed = wait_for_completion(service, service.start("bank-otp").id)

    assert failed.status == "error"
    assert failed.progress == 33
    assert failed.assessment is None
    assert failed.error is not None
    assert failed.error.code == "analysis_timeout"
    assert failed.error.message == "Langflow tidak merespons sebelum batas waktu."
    assert analyzer.calls == 2
    assert len(transcriber.paths) == 2
    assert all(not path.exists() for path in transcriber.paths)
    service.close()


def test_probe_is_forwarded_to_the_analyzer() -> None:
    analyzer = FailingSecondAnalyzer()
    service = DemoService({}, SequentialTranscriber([]), analyzer, delay_seconds=0)

    service.probe()

    assert analyzer.probes == 1
    service.close()


def test_default_scenarios_match_ios_and_all_audio_exists() -> None:
    scenarios = default_scenarios()

    assert set(scenarios) == {
        "bank-otp",
        "kecelakaan-transfer",
        "kurir-aplikasi",
        "tetangga-aman",
    }
    assert all(value.audio_path.exists() for value in scenarios.values())
    assert all(list(split_wav(value.audio_path, chunk_seconds=5)) for value in scenarios.values())
