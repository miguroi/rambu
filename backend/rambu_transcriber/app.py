import os
import tempfile
import wave
from pathlib import Path

from fastapi import FastAPI, Header, HTTPException, Request

from .transcriber import FasterWhisperTranscriber, Transcriber

MAX_AUDIO_BYTES = 25 * 1024 * 1024


def _inspect_wave(path: Path) -> tuple[int, float]:
    try:
        with wave.open(str(path), "rb") as source:
            channels = source.getnchannels()
            sample_width = source.getsampwidth()
            sample_rate = source.getframerate()
            frame_count = source.getnframes()
    except (EOFError, wave.Error) as error:
        raise HTTPException(status_code=422, detail="Audio WAV tidak valid.") from error

    if channels != 1 or sample_width != 2 or sample_rate != 16_000:
        raise HTTPException(
            status_code=422,
            detail="Gunakan WAV mono PCM 16-bit dengan sample rate 16 kHz.",
        )
    if frame_count == 0:
        raise HTTPException(status_code=422, detail="Rekaman tidak berisi audio.")

    return sample_rate, round(frame_count / sample_rate, 3)


def create_app(transcriber: Transcriber | None = None) -> FastAPI:
    app = FastAPI(title="Rambu Local Transcriber", version="0.1.0")
    speech_to_text = transcriber or FasterWhisperTranscriber(
        os.getenv("RAMBU_WHISPER_MODEL", "small")
    )

    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ready"}

    @app.post("/transcribe")
    async def transcribe_audio(
        request: Request,
        x_rambu_consent: str | None = Header(default=None),
    ) -> dict[str, str | int | float]:
        if x_rambu_consent != "true":
            raise HTTPException(
                status_code=403,
                detail="Persetujuan perekaman belum dikonfirmasi.",
            )
        if request.headers.get("content-type", "").split(";", 1)[0] != "audio/wav":
            raise HTTPException(status_code=415, detail="Format audio harus audio/wav.")

        audio = await request.body()
        if len(audio) > MAX_AUDIO_BYTES:
            raise HTTPException(status_code=413, detail="Rekaman terlalu besar.")

        temporary_path: Path | None = None
        try:
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as temporary:
                temporary.write(audio)
                temporary_path = Path(temporary.name)

            sample_rate, duration = _inspect_wave(temporary_path)
            text = speech_to_text.transcribe(temporary_path)
            return {
                "text": text,
                "language": "id",
                "duration_seconds": duration,
                "sample_rate": sample_rate,
            }
        finally:
            if temporary_path is not None:
                temporary_path.unlink(missing_ok=True)

    return app


app = create_app()
