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
from .langflow_client import LangflowFailure
from .models import ChunkAnalysisResponse, DemoFailure, DemoSnapshot, RiskAssessment, RiskLevel
from .redaction import mask_sensitive_text
from .transcription import Transcriber


class Analyzer(Protocol):
    def analyze(self, transcript: str, final: bool) -> RiskAssessment: ...
    def probe(self) -> None: ...


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
        Scenario("bank-otp", "Telepon dari Bank Nusantara", "Permintaan kode OTP", audio / "bank-otp.wav", "high_risk"),
        Scenario("kecelakaan-transfer", "Kabar kecelakaan keluarga", "Permintaan transfer mendesak", audio / "kecelakaan-transfer.wav", "high_risk"),
        Scenario("kurir-aplikasi", "Kurir meminta pasang aplikasi", "Tautan dan aplikasi berbahaya", audio / "kurir-aplikasi.wav", "high_risk"),
        Scenario("tetangga-aman", "Telepon dari Bu Wati", "Informasi jadwal arisan", audio / "tetangga-aman.wav", "low"),
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

    def probe(self) -> None:
        probe = getattr(self.transcriber, "probe", None)
        if probe is not None:
            probe()
        self.analyzer.probe()

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

                try:
                    text = self._transcribe_temporary_chunk(chunk)
                except Exception:
                    self._fail(
                        session_id,
                        DemoFailure(
                            code="transcription_failed",
                            message="Transkripsi audio gagal.",
                        ),
                    )
                    return
                text = text.strip()
                if text:
                    transcript_parts.append(text)
                if index == len(chunks) and not transcript_parts:
                    self._fail(
                        session_id,
                        DemoFailure(
                            code="transcription_failed",
                            message="Transkripsi audio tidak menghasilkan teks.",
                        ),
                    )
                    return
                masked_transcript = mask_sensitive_text(" ".join(transcript_parts))
                assessment = None
                if masked_transcript:
                    try:
                        assessment = self.analyzer.analyze(
                            masked_transcript,
                            final=index == len(chunks),
                        )
                    except LangflowFailure as error:
                        self._fail(
                            session_id,
                            DemoFailure(
                                code=f"analysis_{error.code}",
                                message=error.safe_message,
                            ),
                        )
                        return
                    except Exception:
                        self._fail(
                            session_id,
                            DemoFailure(
                                code="analysis_failed",
                                message="Analisis panggilan gagal.",
                            ),
                        )
                        return

                with self._lock:
                    current = self._sessions.get(session_id)
                    if current is None:
                        return
                    current.transcript = masked_transcript
                    current.progress = round(index / len(chunks) * 100)
                    if assessment is not None:
                        current.assessment = assessment

            with self._lock:
                current = self._sessions.get(session_id)
                if current is not None:
                    current.status = "completed"
        except Exception:
            self._fail(
                session_id,
                DemoFailure(
                    code="processing_failed",
                    message="Pemrosesan audio gagal.",
                ),
            )

    def _fail(self, session_id: str, failure: DemoFailure) -> None:
        with self._lock:
            current = self._sessions.get(session_id)
            if current is not None:
                current.status = "error"
                current.assessment = None
                current.error = failure

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
