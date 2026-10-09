import io
import wave
from collections.abc import Iterator
from pathlib import Path


def split_wav(path: Path, chunk_seconds: int = 5) -> Iterator[bytes]:
    try:
        source = wave.open(str(path), "rb")
    except (EOFError, wave.Error) as error:
        raise ValueError("Audio WAV tidak valid.") from error

    with source:
        channels = source.getnchannels()
        sample_width = source.getsampwidth()
        sample_rate = source.getframerate()
        if channels != 1 or sample_width != 2 or sample_rate != 16_000:
            raise ValueError("Gunakan WAV mono PCM 16-bit dengan sample rate 16 kHz.")

        frames_per_chunk = sample_rate * chunk_seconds
        while frames := source.readframes(frames_per_chunk):
            buffer = io.BytesIO()
            with wave.open(buffer, "wb") as output:
                output.setnchannels(channels)
                output.setsampwidth(sample_width)
                output.setframerate(sample_rate)
                output.writeframes(frames)
            yield buffer.getvalue()


def validate_wav_bytes(value: bytes, maximum_seconds: float = 6.5) -> float:
    try:
        source = wave.open(io.BytesIO(value), "rb")
    except (EOFError, wave.Error) as error:
        raise ValueError("Audio WAV tidak valid.") from error

    with source:
        if source.getnchannels() != 1 or source.getsampwidth() != 2 or source.getframerate() != 16_000:
            raise ValueError("Gunakan WAV mono PCM 16-bit dengan sample rate 16 kHz.")
        duration = source.getnframes() / source.getframerate()
        if duration > maximum_seconds:
            raise ValueError("Potongan audio terlalu panjang; kirim paling lama 6,5 detik.")
        return duration
