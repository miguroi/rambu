import hashlib
import json
import logging
import tempfile
from pathlib import Path
from typing import Protocol

from .audio import validate_wav_bytes
from .langflow_client import LangflowFailure
from .models import (
    CreateProtectionSessionRequest,
    PairPuckResponse,
    ProtectionFailure,
    ProtectionSessionSnapshot,
    RiskAssessment,
)
from .pilot import PilotStore
from .redaction import mask_sensitive_text
from .transcription import Transcriber


MAXIMUM_CHUNK_BYTES = 1_048_576
TRANSCRIPTION_LOGGER = logging.getLogger("uvicorn.error.rambu.transcription")


class Analyzer(Protocol):
    def analyze(self, transcript: str, final: bool) -> RiskAssessment: ...


class ProtectionService:
    def __init__(
        self,
        store: PilotStore,
        transcriber: Transcriber,
        analyzer: Analyzer,
    ) -> None:
        self.store = store
        self.transcriber = transcriber
        self.analyzer = analyzer

    def pair_puck(self, invitation_code: str, display_name: str) -> PairPuckResponse:
        return self.store.pair_puck(invitation_code, display_name)

    def create_session(
        self, parent_token: str, request: CreateProtectionSessionRequest
    ) -> ProtectionSessionSnapshot:
        return self.store.create_protection_session(
            parent_token,
            str(request.call_id),
            request.started_at,
            request.channel,
            request.title,
            request.caller_detail,
        )

    def get_parent_session(
        self, parent_token: str, session_id: str
    ) -> ProtectionSessionSnapshot:
        return self.store.get_protection_session(parent_token, session_id)

    def get_active_puck_session(self, puck_token: str) -> ProtectionSessionSnapshot:
        return self.store.active_protection_session(puck_token)

    def get_puck_session(
        self, puck_token: str, session_id: str
    ) -> ProtectionSessionSnapshot:
        return self.store.get_puck_protection_session(puck_token, session_id)

    def process_chunk(
        self,
        puck_token: str,
        session_id: str,
        sequence: int,
        final: bool,
        audio: bytes,
    ) -> ProtectionSessionSnapshot:
        if len(audio) > MAXIMUM_CHUNK_BYTES:
            raise ValueError("Potongan audio melebihi batas 1 MB.")
        validate_wav_bytes(audio)
        digest = hashlib.sha256(audio).hexdigest()
        current, duplicate = self.store.inspect_protection_chunk(
            puck_token,
            session_id,
            sequence=sequence,
            digest=digest,
        )
        if duplicate:
            return current

        try:
            text = self._transcribe_temporary_chunk(audio).strip()
        except Exception:
            self.store.fail_protection_session(
                puck_token,
                session_id,
                ProtectionFailure(
                    code="transcription_failed",
                    message="Transkripsi audio gagal.",
                ),
            )
            raise

        masked_chunk = mask_sensitive_text(text)
        logged_text = (
            json.dumps(masked_chunk, ensure_ascii=False) if masked_chunk else "<empty>"
        )
        TRANSCRIPTION_LOGGER.info(
            "transcription session=%s sequence=%d final=%s text=%s",
            session_id,
            sequence,
            final,
            logged_text,
        )

        combined = " ".join(
            part for part in (current.masked_transcript.strip(), text) if part
        )
        masked_transcript = mask_sensitive_text(combined)
        assessment: RiskAssessment | None = None
        if masked_transcript:
            try:
                assessment = self.analyzer.analyze(masked_transcript, final=final)
            except LangflowFailure as error:
                self.store.fail_protection_session(
                    puck_token,
                    session_id,
                    ProtectionFailure(
                        code=f"analysis_{error.code}",
                        message=error.safe_message,
                    ),
                )
                raise
            except Exception:
                self.store.fail_protection_session(
                    puck_token,
                    session_id,
                    ProtectionFailure(
                        code="analysis_failed",
                        message="Analisis panggilan gagal.",
                    ),
                )
                raise

        return self.store.record_protection_chunk(
            puck_token,
            session_id,
            sequence=sequence,
            digest=digest,
            masked_transcript=masked_transcript,
            assessment=assessment,
            final=final,
        )

    def end_session(
        self, parent_token: str, session_id: str
    ) -> ProtectionSessionSnapshot:
        return self.store.request_protection_end(parent_token, session_id)

    def cancel_session(self, parent_token: str, session_id: str) -> None:
        self.store.delete_protection_session(parent_token, session_id)

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
