import io
import wave
from pathlib import Path

from fastapi.testclient import TestClient

from rambu_transcriber.app import create_app


def mono_wav(sample_rate: int = 16_000, frames: int = 1_600) -> bytes:
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(sample_rate)
        output.writeframes(b"\x01\x00" * frames)
    return buffer.getvalue()


class RecordingTranscriber:
    def __init__(self) -> None:
        self.paths: list[Path] = []

    def transcribe(self, path: Path) -> str:
        assert path.exists()
        self.paths.append(path)
        return "Ini adalah contoh percakapan dalam bahasa Indonesia."


def test_health_reports_ready_without_loading_whisper() -> None:
    client = TestClient(create_app(transcriber=RecordingTranscriber()))

    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ready"}


def test_transcription_requires_explicit_consent() -> None:
    transcriber = RecordingTranscriber()
    client = TestClient(create_app(transcriber=transcriber))

    response = client.post(
        "/transcribe",
        content=mono_wav(),
        headers={"content-type": "audio/wav"},
    )

    assert response.status_code == 403
    assert response.json()["detail"] == "Persetujuan perekaman belum dikonfirmasi."
    assert transcriber.paths == []


def test_transcribes_supported_wav_and_removes_temporary_audio() -> None:
    transcriber = RecordingTranscriber()
    client = TestClient(create_app(transcriber=transcriber))

    response = client.post(
        "/transcribe",
        content=mono_wav(),
        headers={
            "content-type": "audio/wav",
            "x-rambu-consent": "true",
        },
    )

    assert response.status_code == 200
    assert response.json() == {
        "text": "Ini adalah contoh percakapan dalam bahasa Indonesia.",
        "language": "id",
        "duration_seconds": 0.1,
        "sample_rate": 16_000,
    }
    assert len(transcriber.paths) == 1
    assert not transcriber.paths[0].exists()


def test_rejects_non_wav_audio_before_transcription() -> None:
    transcriber = RecordingTranscriber()
    client = TestClient(create_app(transcriber=transcriber))

    response = client.post(
        "/transcribe",
        content=b"not a wave file",
        headers={
            "content-type": "audio/wav",
            "x-rambu-consent": "true",
        },
    )

    assert response.status_code == 422
    assert response.json()["detail"] == "Audio WAV tidak valid."
    assert transcriber.paths == []


def test_rejects_wav_with_wrong_capture_format() -> None:
    transcriber = RecordingTranscriber()
    client = TestClient(create_app(transcriber=transcriber))

    response = client.post(
        "/transcribe",
        content=mono_wav(sample_rate=8_000),
        headers={
            "content-type": "audio/wav",
            "x-rambu-consent": "true",
        },
    )

    assert response.status_code == 422
    assert response.json()["detail"] == "Gunakan WAV mono PCM 16-bit dengan sample rate 16 kHz."
    assert transcriber.paths == []
