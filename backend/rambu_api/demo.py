import os
import tempfile
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol
from uuid import uuid4

from .audio import split_wav, validate_wav_bytes
from .models import ChunkAnalysisResponse, DemoSnapshot, RiskAssessment, RiskLevel
from .redaction import mask_sensitive_text
from .transcription import Transcriber


class Analyzer(Protocol):
    def analyze(self, transcript: str, final: bool) -> RiskAssessment: ...


@dataclass(frozen=True)
class Scenario:
    slug: str
    title: str
    description: str
    audio_path: Path
    expected_risk: RiskLevel


def default_scenarios(root: Path | None = None) -> dict[str, Scenario]:
    project_root = root or Path(__file__).resolve().parents[2]
    audio = project_root / "samples" / "audio"
    scenarios = [
        Scenario("normal", "Konfirmasi pengiriman", "Percakapan layanan yang wajar", audio / "normal.wav", "low"),
        Scenario("unclear", "Permintaan mendesak", "Permintaan mendesak tanpa bukti penipuan", audio / "unclear.wav", "needs_review"),
        Scenario("otp", "Permintaan OTP", "Permintaan kode rahasia dan pembayaran", audio / "otp.wav", "high_risk"),
    ]
    return {scenario.slug: scenario for scenario in scenarios}


class DemoService:
    def __init__(
        self,
        scenarios: dict[str, Scenario],
        transcriber: Transcriber,
        analyzer: Analyzer,
        delay_seconds: float = 5,
    ) -> None:
        self.scenarios = scenarios
        self.transcriber = transcriber
        self.analyzer = analyzer
        self.delay_seconds = delay_seconds
        self._sessions: dict[str, DemoSnapshot] = {}
        self._cancel: dict[str, threading.Event] = {}
        self._lock = threading.RLock()
        self._executor = ThreadPoolExecutor(max_workers=2, thread_name_prefix="rambu-demo")

    def start(self, scenario_slug: str) -> DemoSnapshot:
        if scenario_slug not in self.scenarios:
            raise KeyError(scenario_slug)
        scenario = self.scenarios[scenario_slug]
        if not scenario.audio_path.exists():
            raise FileNotFoundError(scenario.audio_path)

        session_id = uuid4().hex
        snapshot = DemoSnapshot(
            id=session_id,
            scenario=scenario.slug,
            title=scenario.title,
            status="running",
            progress=0,
            transcript="",
            assessment=None,
            error=None,
        )
        with self._lock:
            self._sessions[session_id] = snapshot
            self._cancel[session_id] = threading.Event()
        self._executor.submit(self._run, session_id, scenario)
        return snapshot.model_copy(deep=True)

    def get(self, session_id: str) -> DemoSnapshot:
        with self._lock:
            if session_id not in self._sessions:
                raise KeyError(session_id)
            return self._sessions[session_id].model_copy(deep=True)

    def delete(self, session_id: str) -> None:
        with self._lock:
            if session_id not in self._sessions:
                raise KeyError(session_id)
            self._cancel[session_id].set()
            del self._sessions[session_id]
            del self._cancel[session_id]

    def close(self) -> None:
        with self._lock:
            for event in self._cancel.values():
                event.set()
        self._executor.shutdown(wait=True, cancel_futures=True)

    def analyze_chunk(self, audio: bytes, final: bool) -> ChunkAnalysisResponse:
        validate_wav_bytes(audio)
        text = self._transcribe_temporary_chunk(audio)
        masked = mask_sensitive_text(text)
        assessment = self.analyzer.analyze(masked, final=final) if masked else None
        return ChunkAnalysisResponse(transcript=masked, assessment=assessment)

    def _run(self, session_id: str, scenario: Scenario) -> None:
        try:
            chunks = list(split_wav(scenario.audio_path, chunk_seconds=5))
            if not chunks:
                raise ValueError("Rekaman tidak berisi audio.")
            transcript_parts: list[str] = []
            for index, chunk in enumerate(chunks, start=1):
                if self.delay_seconds:
                    time.sleep(self.delay_seconds)
                if self._is_cancelled(session_id):
                    return

                text = self._transcribe_temporary_chunk(chunk)
                if text:
                    transcript_parts.append(text)
                masked_transcript = mask_sensitive_text(" ".join(transcript_parts))
                assessment = None
                analysis_error = None
                if masked_transcript:
                    try:
                        assessment = self.analyzer.analyze(
                            masked_transcript,
                            final=index == len(chunks),
                        )
                    except Exception as error:  # The transcript must continue if Langflow fails.
                        analysis_error = f"Analisis Langflow gagal: {error}"

                with self._lock:
                    current = self._sessions.get(session_id)
                    if current is None:
                        return
                    current.transcript = masked_transcript
                    current.progress = round(index / len(chunks) * 100)
                    if assessment is not None:
                        current.assessment = assessment
                    current.error = analysis_error

            with self._lock:
                current = self._sessions.get(session_id)
                if current is not None:
                    current.status = "completed"
        except Exception as error:
            with self._lock:
                current = self._sessions.get(session_id)
                if current is not None:
                    current.status = "error"
                    current.error = str(error)

    def _is_cancelled(self, session_id: str) -> bool:
        with self._lock:
            event = self._cancel.get(session_id)
            return event is None or event.is_set()

    def _transcribe_temporary_chunk(self, audio: bytes) -> str:
        temporary_path: Path | None = None
        try:
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as temporary:
                temporary.write(audio)
                temporary_path = Path(temporary.name)
            return self.transcriber.transcribe(temporary_path)
        finally:
            if temporary_path is not None:
                temporary_path.unlink(missing_ok=True)


def delay_from_environment() -> float:
    return max(0, float(os.getenv("RAMBU_DEMO_DELAY_SECONDS", "5")))
