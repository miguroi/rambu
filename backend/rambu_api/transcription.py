import wave
from pathlib import Path
from typing import Protocol


class Transcriber(Protocol):
    def transcribe(self, path: Path) -> str: ...


class FasterWhisperTranscriber:
    def __init__(self, model_name: str = "small") -> None:
        self.model_name = model_name
        self._model = None

    def transcribe(self, path: Path) -> str:
        # Runtime puck chunks are WAV. Dataset evaluation also accepts formats
        # supported by faster-whisper/PyAV, including MP3.
        if path.suffix.lower() == ".wav":
            with wave.open(str(path), "rb") as source:
                duration = source.getnframes() / source.getframerate()
            if duration < 0.75:
                return ""

        if self._model is None:
            from faster_whisper import WhisperModel

            self._model = WhisperModel(
                self.model_name,
                device="cpu",
                compute_type="int8",
            )

        segments, _ = self._model.transcribe(
            str(path),
            language="id",
            vad_filter=True,
            beam_size=5,
        )
        return " ".join(segment.text.strip() for segment in segments).strip()
